(function()
	-- A timed measurement (middle click on the performance display) says in the chat that it has started
	local saved = { ns.PrintAlways, C_Timer.NewTimer, ns.measureTimer, ns.measureUntil }
	local said
	ns.PrintAlways = function(msg, ...) said = msg:format(...) end
	C_Timer.NewTimer = function() return { Cancel = function() end } end
	ns.measureTimer = nil
	ns.StartTimedMeasure(30)
	assert(said == ns.L.TIMINGS_ON_TIMED:format(30) and said:find("30"), "start message with the duration")
	ns.SetMeasuring(false)
	ns.PrintAlways, C_Timer.NewTimer, ns.measureTimer, ns.measureUntil = unpack(saved, 1, 4)
	print("timed measurement start OK")
end)()

-- Weapon reminder: a permanent enchant on the same weapon does not stand in for the imbue's time
;(function()
	local buffs = ns:GetModule("Buffs")
	local saved = Enum.ItemEnchantType
	Enum.ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 }
	local imbue = { hasEnchant = true, enchantType = 3, timeLeft = 1680000 }
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 0 }, imbue }) == 1680,
		"permanent enchant listed first with no timer: imbue time counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 1 }, imbue }) == 1680,
		"permanent enchant listed first with a tiny timer: imbue time counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 0 } }) == nil,
		"only a permanent enchant: imbue missing")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = false, enchantType = 0, timeLeft = 0 } }) == nil, "nothing on the weapon")
	assert(buffs.EnchantTimeLeft(nil) == nil and buffs.EnchantTimeLeft({}) == nil, "no list")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 2, timeLeft = 30000 } }) == 30, "temporary enchant counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 2, timeLeft = 30000 }, imbue }) == 1680,
		"two timed entries: the longer one")
	Enum.ItemEnchantType = saved
	print("weapon enchant time OK")
end)()
-- Auction house: cash register sound on live sales and unread sale mail with gold
;(function()
	local A = ns:GetModule("Auction")
	local saved = {
		PlaySoundFile, PlaySound, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo,
		ERR_AUCTION_SOLD_S, AUCTION_SOLD_MAIL_SUBJECT, Enum.AuctionHouseNotification, SOUNDKIT.LOOT_WINDOW_COIN_SOUND,
		A.db.saleSound,
	}
	local now, filePlays, kitPlays, fileOk = 100, {}, {}, true
	PlaySoundFile = function(file, channel)
		filePlays[#filePlays + 1] = { file, channel }
		return fileOk
	end
	PlaySound = function(kit, channel)
		kitPlays[#kitPlays + 1] = { kit, channel }
	end
	GetTime = function() return now end
	SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 895
	Enum.AuctionHouseNotification = {
		BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2,
		AuctionOutbid = 3, AuctionSold = 4, AuctionExpired = 5,
	}
	ERR_AUCTION_SOLD_S = "Für Eure Auktion von %s wurde ein Käufer gefunden."
	AUCTION_SOLD_MAIL_SUBJECT = "Auktion erfolgreich: %s"

	local inbox = {}
	GetInboxNumItems = function() return #inbox, #inbox end
	GetInboxHeaderInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, m.money, 0, 29, m.items, m.wasRead
	end
	GetInboxInvoiceInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return m.invoiceType, m.itemName, m.playerName, m.bid
	end

	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end

	A.db.saleSound = true
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()

	-- Live notification events: only AuctionSold plays
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionExpired, "Kupfererz")
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionOutbid, "Kupfererz")
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionWon, "Kupfererz")
	assert(#filePlays == 0, "expired, outbid, won stay silent")

	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold, "Kupfererz")
	assert(#filePlays == 1 and filePlays[1][1]:find("AuctionKaChing%.mp3$") and filePlays[1][2] == "Master",
		"live formatted AuctionSold plays the cash register sound on Master")

	-- Debounce prevents stacked noise when several auctions sell in the same second
	now = 100.5
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#filePlays == 1, "rapid second sale within cooldown stays silent")

	now = 103
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#filePlays == 2, "sale after cooldown plays again")

	-- System chat fallback matches both German and English ERR_AUCTION_SOLD_S
	now = 110
	Fire("CHAT_MSG_SYSTEM", "Eure Auktion von Kupfererz ist abgelaufen.")
	assert(#filePlays == 2, "unrelated system message stays silent")
	Fire("CHAT_MSG_SYSTEM", "Für Eure Auktion von Kupfererz wurde ein Käufer gefunden.")
	assert(#filePlays == 3, "German ERR_AUCTION_SOLD_S system message plays")
	ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
	now = 115
	Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Copper Ore.")
	assert(#filePlays == 4, "English ERR_AUCTION_SOLD_S system message plays")

	-- Mailbox scan: only unread AH sale mail with money plays
	now = 120
	inbox = {
		{ sender = "Auktionshaus der Allianz", subject = "Auktion abgelaufen: Kupfererz", money = 0, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Überboten: Kupfererz", money = 5000, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion gewonnen: Leinenstoff", money = 0, wasRead = false, invoiceType = "buyer", itemName = "Leinenstoff", bid = 1200 },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Seidenstoff", money = 0, wasRead = false, invoiceType = "seller_temp_invoice", itemName = "Seidenstoff", bid = 3000 },
		{ sender = "Freund", subject = "Hier dein Gold", money = 10000, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Kupfererz", money = 4750, wasRead = true, invoiceType = "seller", itemName = "Kupfererz", bid = 5000 },
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 4, "expired, outbid, bought, pending temp invoice, player gold, and already-read sale mail stay silent")

	-- Unread seller mail with proceeds plays once, not repeatedly while the mailbox stays open
	now = 125
	inbox[#inbox + 1] = {
		sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz",
		money = 9500, wasRead = false, invoiceType = "seller", itemName = "Silbererz", bid = 10000,
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "unread AH sale mail with gold plays")

	now = 130
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "same unread sale mail does not replay on next inbox update")

	-- MAIL_SHOW with empty inbox before server response must not clear remembered unread mails
	local savedInbox = inbox
	inbox = {}
	now = 135
	Fire("MAIL_SHOW")
	inbox = savedInbox
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "empty MAIL_SHOW before MAIL_INBOX_UPDATE keeps remembered sale mails")

	-- A second identical unread sale increases the count and plays
	now = 140
	inbox[#inbox + 1] = {
		sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz",
		money = 9500, wasRead = false, invoiceType = "seller", itemName = "Silbererz", bid = 10000,
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 6, "a second identical unread sale plays")

	-- After looting all mails, a later identical sale plays again
	inbox = {}
	now = 145
	Fire("MAIL_INBOX_UPDATE")
	inbox = {
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz", money = 9500, wasRead = false },
	}
	now = 150
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 7, "fallback subject match plays when invoice info is nil and money > 0")

	-- Fallback to Blizzard coin sound when PlaySoundFile returns false
	fileOk = false
	now = 155
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#kitPlays == 1 and kitPlays[1][1] == 895 and kitPlays[1][2] == "Master",
		"falls back to LOOT_WINDOW_COIN_SOUND when custom file fails")
	fileOk = true

	-- Option off unregisters events; test button still plays via force
	A.db.saleSound = false
	A:OnOptionChanged("saleSound")
	now = 160
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 8, "option off: live sale and mailbox updates stay silent")
	assert(A.PlaySaleSound(true) == true and #filePlays == 9, "test button plays regardless of option and cooldown")
	assert(A.PlaySaleSound(true) == true and #filePlays == 10, "repeated test clicks play without cooldown")

	PlaySoundFile, PlaySound, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = unpack(saved, 1, 6)
	ERR_AUCTION_SOLD_S, AUCTION_SOLD_MAIL_SUBJECT, Enum.AuctionHouseNotification, SOUNDKIT.LOOT_WINDOW_COIN_SOUND = unpack(saved, 7, 10)
	A.db.saleSound = saved[11]
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()
	print("auction sale sound OK")
end)()
;(function()
	-- Emote tab: sections like the chat menu, aliases, faction filtering, search and token resolution.
	local emotes = ns:GetModule("ChatEmotes")
	assert(emotes and emotes.BuildSections and emotes.FilterSections and emotes.ResolveToken, "chat emotes module")
	local strings = {
		EMOTE1_TOKEN = "WAVE", EMOTE1_CMD1 = "/winken", EMOTE1_CMD2 = "/wave", EMOTE1_CMD3 = "/WINKEN",
		EMOTE2_TOKEN = "BOW", EMOTE2_CMD1 = "/Verbeugen", EMOTE2_CMD2 = "/bow",
		EMOTE3_TOKEN = "UNUSED", EMOTE3_CMD1 = "/unused",
		EMOTE4_TOKEN = "CHEER", EMOTE4_CMD1 = "/jubeln", EMOTE4_CMD2 = "/cheer",
		EMOTE5_TOKEN = "WAVE", EMOTE5_CMD1 = "/wave2",
		EMOTE6_TOKEN = "NOCMD",
		EMOTE7_TOKEN = "FORTHEALLIANCE", EMOTE7_CMD1 = "/fürdieallianz",
		EMOTE8_TOKEN = "FORTHEHORDE", EMOTE8_CMD1 = "/fürdiehorde",
	}
	local sections = emotes.BuildSections(
		function(name) return strings[name] end,
		{ "WAVE", "UNKNOWN" },
		{ "CHEER", "FORTHEALLIANCE", "FORTHEHORDE" },
		8,
		"Alliance"
	)
	assert(#sections == 3, "three sections")
	assert(sections[1].title == ns.L.CHATEMOTES_ANIMATED and sections[2].title == ns.L.CHATEMOTES_VOICE
		and sections[3].title == ns.L.CHATEMOTES_ALL, "section titles")
	assert(sections[1].entries[1].token == "WAVE" and sections[1].entries[1].command == "/winken", "animated: first index command")
	assert(#sections[1].entries[1].aliases == 1 and sections[1].entries[1].aliases[1] == "/wave", "aliases deduplicated case-insensitively")
	assert(sections[1].entries[2].command == "UNKNOWN", "token without command keeps token as label")
	assert(#sections[2].entries == 2 and sections[2].entries[1].token == "CHEER"
		and sections[2].entries[2].token == "FORTHEALLIANCE", "voice emotes skip opposite faction")
	local all = sections[3].entries
	assert(#all == 4, "all: skips UNUSED, NOCMD, duplicate WAVE and opposite faction: " .. #all)
	assert(all[1].token == "FORTHEALLIANCE" and all[2].token == "CHEER" and all[3].token == "BOW" and all[4].token == "WAVE",
		"all: sorted by command")
	assert(emotes.FilterSections(sections, "   ") == sections and emotes.FilterSections(sections, "/") == sections,
		"empty or slash-only filter keeps all sections")
	local byAlias = emotes.FilterSections(sections, "/WAVE")
	assert(#byAlias == 1 and #byAlias[1].entries == 1 and byAlias[1].entries[1].token == "WAVE", "filter matches English alias with slash")
	local byCmd = emotes.FilterSections(sections, "jubel")
	assert(#byCmd == 1 and #byCmd[1].entries == 1 and byCmd[1].entries[1].token == "CHEER", "filter matches localized command")
	assert(#emotes.FilterSections(sections, "gibtesnicht") == 0, "unmatched filter returns empty")
	assert(emotes.ResolveToken("FORTHEHORDE", "Alliance") == "FORTHEALLIANCE", "resolve switches battle cry to Alliance")
	assert(emotes.ResolveToken("FORTHEALLIANCE", "Horde") == "FORTHEHORDE", "resolve switches battle cry to Horde")
	assert(emotes.ResolveToken("WAVE", "Horde") == "WAVE", "resolve leaves normal emotes untouched")
	assert(#emotes.BuildSections(function() end, nil, nil, nil)[3].entries == 0, "missing game lists give empty sections")
	-- Virtualized layout: rows and visible viewport window.
	local rows, totalHeight, totalEntries = emotes.BuildRows(sections, 2)
	-- 3 sections: (2 -> 1 row), (2 -> 1 row), (4 -> 2 rows) = 3 headers + 4 entry rows = 7 rows.
	assert(#rows == 7 and totalEntries == 8 and totalHeight == 3 * (20 + 6) + 4 * 18, "virtual row layout math")
	assert(rows[1].header == ns.L.CHATEMOTES_ANIMATED and rows[2].first == 1 and rows[2].last == 2, "first section rows")
	assert(rows[6].first == 1 and rows[6].last == 2 and rows[7].first == 3 and rows[7].last == 4, "all section split into two rows")
	local first, last = emotes.VisibleRange(rows, 0, 40)
	assert(first == 1 and last >= 2 and last < #rows, "top viewport renders only visible prefix")
	local fMid, lMid = emotes.VisibleRange(rows, totalHeight - 36, 36)
	assert(fMid > 1 and lMid == #rows, "bottom viewport renders tail rows")
	local fEmpty, lEmpty = emotes.VisibleRange(rows, totalHeight + 200, 36)
	assert(fEmpty > lEmpty, "scroll past end renders nothing")
	local fZero, lZero = emotes.VisibleRange({}, 0, 100)
	assert(fZero > lZero, "empty rows render nothing")
	print("chat emotes OK")
end)()
;(function()
	local M = ns:GetModule("MacroIcons")
	assert(M and M.db.enabled == true, "macro icon search on by default")
	assert(M.Normalize("ÄÖÜ Sword_04") == "äöü sword 04", "normalize lowers ASCII, capital umlauts and underscores")
	local data = "\nspell fire flamebolt|fireball|feuerball\t135812\nability warrior charge|charge|sturmangriff\t132337\ninv sword 04\t135274\n"
	local found = M.Find(data, "Feuerball")
	assert(found[135812] and not found[132337], "German name finds the icon")
	found = M.Find(data, "FIREBALL")
	assert(found[135812], "English name, any case")
	found = M.Find(data, "fire  sword")
	assert(not next(found), "all words must match")
	found = M.Find(data, "sturm  warrior")
	assert(found[132337] and not found[135812], "several words from different names")
	found = M.Find(data, "135")
	assert(not next(found), "file IDs are not searched")
	assert(M.Find(data, "   ") == nil, "empty query searches nothing")
	-- Long line (> 256 bytes) and no trailing newline.
	local longData = "alpha|" .. string.rep("x", 320) .. "|omega\t999001"
	local longFound = M.Find(longData, "alpha omega")
	assert(longFound[999001], "multi-word match across >256-byte line without trailing newline")
	local icons = { "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK", 132337, 135812, 135274, 132337, "INTERFACE\\ICONS\\Spell_Fire_Fireball" }
	local f2, words = M.Find(data, "fire")
	local results = M.Collect(function(i) return icons[i] end, #icons, f2, words)
	assert(#results == 2 and results[1].icon == 135812 and results[1].index == 3
		and results[2].icon == "INTERFACE\\ICONS\\Spell_Fire_Fireball" and results[2].index == 6,
		"picker order, loose icons by file name, no repeats")
	f2, words = M.Find(data, "charge")
	results = M.Collect(function(i) return icons[i] end, #icons, f2, words)
	assert(#results == 1 and results[1].index == 2, "repeated icon listed once at its first place")

	-- Indexed & time-sliced search matches Collect and yields cleanly under a tight deadline.
	local idx = M.NewIndex(function(i) return icons[i] end, #icons)
	assert(M.StepIndex(idx) == true and idx.ready, "index builds completely")
	local findState, fWords = M.StartFind(data, "fire")
	assert(M.StepFind(findState) == true and findState.done, "step find completes")
	local st = { find = findState, words = fWords, collectPos = 1, collected = false }
	assert(M.StepCollect(idx, st) == true and st.collected, "direct indexed collect completes")
	assert(#st.results == 2 and st.results[1].icon == 135812 and st.results[1].index == 3
		and st.results[2].icon == "INTERFACE\\ICONS\\Spell_Fire_Fireball" and st.results[2].index == 6,
		"indexed direct collect matches Collect order")
	-- Force the large-match sliced path (count > 400) and verify identical picker order.
	local bigSt = { find = { found = findState.found, count = 500 }, words = fWords, collectPos = 1, collected = false }
	assert(M.StepCollect(idx, bigSt) == true and bigSt.collected, "sliced indexed collect completes")
	assert(#bigSt.results == 2 and bigSt.results[1].index == 3 and bigSt.results[2].index == 6,
		"sliced indexed collect matches Collect order")

	-- Bundled data: real names in both languages, fast enough per keystroke, exact match vs full scan.
	local bundled = ns.MacroIconNames
	assert(type(bundled) == "string" and #bundled > 500000, "bundled icon names loaded")
	local start = os.clock()
	local de = M.Find(bundled, "feuerball")
	local elapsed = os.clock() - start
	local en = M.Find(bundled, "fireball")
	assert(de[135812] and en[135812], "Fireball icon by German and English name")
	assert(M.Find(bundled, "sword")[135274], "file name search")
	assert(M.Find(bundled, "heiltrank")[134831], "German item name")
	-- Cross-check sliced Find against a reference gmatch scan on a multi-word query.
	local ref = {}
	for text, id in bundled:gmatch("([^\t\n]+)\t(%d+)") do
		if text:find("fire", 1, true) and text:find("bolt", 1, true) then ref[tonumber(id)] = true end
	end
	local savedClock, clock = debugprofilestop, 0
	debugprofilestop = function() clock = clock + 1 return clock end
	local sliced = M.StartFind(bundled, "fire bolt")
	local steps = 0
	while not M.StepFind(sliced, clock + 0.5) do steps = steps + 1 end
	local miss = M.StartFind(bundled, "zzzznotaniconzzzz")
	local missSteps = 0
	while not M.StepFind(miss, clock + 0.5) do missSteps = missSteps + 1 end
	debugprofilestop = savedClock
	assert(steps >= 1 and missSteps >= 1 and not next(miss.found), "chunked find yields on both hits and zero-match scans")
	local refCount, slicedCount = 0, 0
	for id in pairs(ref) do
		refCount = refCount + 1
		assert(sliced.found[id], "sliced find includes " .. id)
	end
	for id in pairs(sliced.found) do
		slicedCount = slicedCount + 1
		assert(ref[id], "sliced find has no extra id " .. id)
	end
	assert(refCount == slicedCount and refCount > 0, "sliced find matches reference scan exactly")
	assert(elapsed < 0.05, "search over all icons takes " .. elapsed .. " s")
	print(("macro icon search OK (%.1f ms)"):format(elapsed * 1000))
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	local db = visuals.db
	local savedClass, savedUsable, savedButton = UnitClass, C_Spell.IsSpellUsable, MultiCastRecallSpellButton
	local savedSecret, savedColors = issecretvalue, db.totemRecallColors
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local onEvent = eventFrame:GetScript("OnEvent")
	local icon = NewFrame("Texture")
	local button = { icon = icon }
	local usable, noMana, queries = false, false, 0
	local secret = {}
	issecretvalue = function(value) return value == secret end
	UnitClass = function() return "Shaman", "SHAMAN" end
	MultiCastRecallSpellButton = button
	C_Spell.IsSpellUsable = function(spellID)
		assert(spellID == 36936, "recall uses the spell ID assigned by the native button")
		queries = queries + 1
		return usable, noMana
	end
	assert(visuals.defaults.totemRecallColors, "recall colors default on")
	assert(_G["BINDING_NAME_CLICK MultiCastRecallSpellButton:LeftButton"] == ns.L.VISUALS_TOTEM_RECALL_BINDING,
		"binding targets the original recall button")
	db.totemRecallColors = true
	visuals:OnOptionChanged("totemRecallColors")
	assert(queries == 0, "unlearned recall has no spell usability query")

	button.spellId = 36936
	onEvent(eventFrame, "PLAYER_TOTEM_UPDATE")
	assert(icon.vertexColor[1] == 0.4 and icon.vertexColor[3] == 0.4, "unusable recall is gray")
	noMana = true
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 0.5 and icon.vertexColor[3] == 1, "low mana colors recall blue")
	usable = secret
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 0.5, "protected usability keeps the last readable color")
	usable, noMana = true, false
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 1, "usable recall has full color")

	usable = false
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	db.totemRecallColors = false
	visuals:OnOptionChanged("totemRecallColors")
	local before = queries
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 1 and queries == before, "turning recall colors off restores the original icon")

	UnitClass, C_Spell.IsSpellUsable, MultiCastRecallSpellButton = savedClass, savedUsable, savedButton
	issecretvalue, db.totemRecallColors = savedSecret, savedColors
	visuals:OnOptionChanged("totemRecallColors")
	print("totem recall binding and action colors OK")
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	local setup = assert(uv(visuals.OnLogin, "SetupTotemBindings"))
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local updateBindings = eventFrame:GetScript("OnEvent")
	local savedFrame, savedRegistry, savedMixin = CreateFrame, EventRegistry, QuickKeybindButtonTemplateMixin
	local savedQuickKeybindFrame = QuickKeybindFrame
	local savedRecallSpells, savedSummonSpells = TOTEM_MULTI_CAST_RECALL_SPELLS, TOTEM_MULTI_CAST_SUMMON_SPELLS
	local savedRecall, savedSummon, savedKey = MultiCastRecallSpellButton, MultiCastSummonSpellButton, GetBindingKey
	local savedClear, savedOverride = ClearOverrideBindings, SetOverrideBindingClick
	local recallCastName, summonCastName = "ForeverPlusTotemRecallCastButton", "ForeverPlusTotemSummonCastButton"
	local recallCommand = "CLICK MultiCastRecallSpellButton:LeftButton"
	local summonCommand = "CLICK MultiCastSummonSpellButton:LeftButton"
	local recall, summon = NewFrame("CheckButton"), NewFrame("CheckButton")
	local currentPage = 1
	local modeShown, summonHover, nativeEnters = false, false, 0
	summon.GetID = function() return currentPage end
	summon.IsMouseMotionFocus = function() return summonHover end
	summon:SetScript("OnEnter", function() nativeEnters = nativeEnters + 1 end)
	MultiCastRecallSpellButton, MultiCastSummonSpellButton = recall, summon
	local events, overrides, casts, selectors = {}, {}, {}, {}
	local keys = { [recallCommand] = { "SHIFT-R", "CTRL-R" }, [summonCommand] = { "SHIFT-T" } }
	TOTEM_MULTI_CAST_RECALL_SPELLS = { 36936 }
	TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 }
	EventRegistry = { RegisterCallback = function(_, event, fn, owner)
		events[event] = events[event] or {}
		events[event][owner] = fn
	end }
	local function Fire(event)
		for owner, callback in pairs(events[event]) do callback(owner) end
	end
	QuickKeybindButtonTemplateMixin = {}
	QuickKeybindFrame = {
		SetSelected = function(self, command, selector)
			self.command, self.mouseOverButton = command, selector
		end,
	}
	CreateFrame = function(kind, name, parent, template)
		local frame = savedFrame(kind, name, parent, template)
		local attributes = {}
		local frameRefs = {}
		frame.SetAttribute = function(_, key, value) attributes[key] = value end
		frame.GetAttribute = function(_, key) return attributes[key] end
		frame.SetFrameRef = function(_, key, value) frameRefs[key] = value end
		frame.GetFrameRef = function(_, key) return frameRefs[key] end
		frame.WrapScript = function(self, target, script, body)
			assert(template == "SecureActionButtonTemplate, SecureHandlerBaseTemplate", "page switching is secure")
			assert(target == self and script == "PreClick", "select the spell before casting")
			self.preClick = setfenv(assert(loadstring(body)), { self = target })
		end
		frame.RegisterForClicks = function(self, ...) self.clicks = table.concat({ ... }, ",") end
		frame.SetAllPoints = function(self, target) self.anchor = target end
		if template == "QuickKeybindButtonTemplate" then
			selectors[parent] = frame
			frame.DoModeChange = function(self, enabled) self.highlighted = enabled end
			frame.SetMouseMotionEnabled = function(self, enabled) self.mouseMotion = enabled end
			frame.SetMouseClickEnabled = function(self, enabled) self.mouseClick = enabled end
			frame.Show = function(self)
				self.shown = true
				local script = self:GetScript("OnShow")
				if script then script(self) end
			end
			frame.Hide = function(self)
				self.shown = false
				local script = self:GetScript("OnHide")
				if script then script(self) end
			end
			frame.QuickKeybindButtonOnEnter = function(self)
				assert(modeShown, "ordinary native hover does not enter quick binding")
				QuickKeybindFrame:SetSelected(self.commandName, self)
			end
			frame.QuickKeybindButtonOnLeave = function()
				if modeShown then QuickKeybindFrame:SetSelected(nil, nil) end
			end
		else
			casts[name] = frame
		end
		return frame
	end
	GetBindingKey = function(action)
		local bound = assert(keys[action], "each button uses its own saved command")
		return unpack(bound)
	end
	ClearOverrideBindings = function(owner)
		overrides[owner] = {}
	end
	SetOverrideBindingClick = function(owner, priority, key, name, mouseButton)
		assert(owner == casts[name] and not priority and mouseButton == "LeftButton", "ordinary binding priority")
		overrides[owner][key] = name
	end
	setup()
	local recallCast, summonCast = casts[recallCastName], casts[summonCastName]
	assert(recallCast:GetAttribute("type") == "spell" and recallCast:GetAttribute("spell") == 36936, "secure recall is unchanged")
	assert(summonCast:GetAttribute("type") == "spell", "the totem page casts a spell")
	assert(recallCast.clicks == "AnyUp,AnyDown" and summonCast.clicks == recallCast.clicks,
		"both buttons support the game's key press or release setting")
	for page, spellID in ipairs(TOTEM_MULTI_CAST_SUMMON_SPELLS) do
		currentPage = page
		summonCast.preClick()
		assert(summonCast:GetAttribute("spell") == spellID, "secure summon follows the native page at click time")
	end
	currentPage = 4
	summonCast.preClick()
	assert(summonCast:GetAttribute("spell") == nil, "an unknown page cannot reuse the previous summon spell")
	assert(overrides[recallCast]["SHIFT-R"] == recallCastName and overrides[recallCast]["CTRL-R"] == recallCastName,
		"both recall keys use the secure cast")
	assert(overrides[summonCast]["SHIFT-T"] == summonCastName, "summon has an independent binding")
	assert(selectors[recall].commandName == recallCommand and selectors[summon].commandName == summonCommand,
		"quick binding selects the correct saved command")
	for button, selector in pairs(selectors) do
		assert(selector.anchor == button and not selector:IsShown(), "each selector starts hidden over its native button")
	end
	assert(selectors[summon].mouseMotion == false and selectors[summon].mouseClick == true,
		"the selector leaves mouse motion to summon and catches clicks during quick binding")
	summon:GetScript("OnEnter")(summon, true)
	assert(nativeEnters == 1 and not QuickKeybindFrame.mouseOverButton, "native hover outside quick binding stays intact")
	modeShown, summonHover = true, true
	Fire("QuickKeybindFrame.QuickKeybindModeEnabled")
	assert(selectors[recall]:IsShown() and selectors[summon]:IsShown() and selectors[summon].highlighted,
		"quick binding shows both selectors")
	assert(QuickKeybindFrame.command == summonCommand, "opening while already over the native button selects summon")
	summon:GetScript("OnLeave")(summon, true)
	assert(not QuickKeybindFrame.mouseOverButton, "leaving the native button clears the selection")
	summon:GetScript("OnEnter")(summon, true)
	assert(nativeEnters == 2 and QuickKeybindFrame.mouseOverButton == selectors[summon],
		"the live hover script selects the shortcut while preserving native hover")
	keys[recallCommand], keys[summonCommand] = { "ALT-R" }, { "ALT-T" }
	updateBindings(eventFrame, "UPDATE_BINDINGS")
	assert(overrides[recallCast]["ALT-R"] == recallCastName and not overrides[recallCast]["SHIFT-R"]
		and not overrides[recallCast]["CTRL-R"], "rebinding recall replaces both old keys")
	assert(overrides[summonCast]["ALT-T"] == summonCastName and not overrides[summonCast]["SHIFT-T"],
		"rebinding summon replaces its old key")
	keys[summonCommand] = {}
	updateBindings(eventFrame, "UPDATE_BINDINGS")
	assert(not next(overrides[summonCast]) and overrides[recallCast]["ALT-R"] == recallCastName,
		"clearing summon leaves the recall shortcut intact")
	modeShown = false
	Fire("QuickKeybindFrame.QuickKeybindModeDisabled")
	assert(not selectors[recall]:IsShown() and not selectors[summon]:IsShown(),
		"closing quick binding returns mouse input to the native buttons")
	assert(not QuickKeybindFrame.mouseOverButton, "closing quick binding clears the summon key listener")
	visuals:UnregisterEvent("UPDATE_BINDINGS")
	_G[recallCastName], _G[summonCastName] = nil, nil
	CreateFrame, EventRegistry, QuickKeybindButtonTemplateMixin = savedFrame, savedRegistry, savedMixin
	QuickKeybindFrame = savedQuickKeybindFrame
	TOTEM_MULTI_CAST_RECALL_SPELLS, TOTEM_MULTI_CAST_SUMMON_SPELLS = savedRecallSpells, savedSummonSpells
	MultiCastRecallSpellButton, MultiCastSummonSpellButton, GetBindingKey = savedRecall, savedSummon, savedKey
	ClearOverrideBindings, SetOverrideBindingClick = savedClear, savedOverride
	print("totem summon and recall quick keybind, secure cast and page switching OK")
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	assert(visuals.defaults.totemTimers == true, "totem timers default on")
	local foundOption
	for _, opt in ipairs(visuals.options) do
		if opt.key == "totemTimers" then
			foundOption = opt
			break
		end
	end
	assert(foundOption and foundOption.new == true, "totem timers option carries the NEW mark")

	local saved = {
		UnitClass = UnitClass,
		CreateFrame = CreateFrame,
		hooksecurefunc = hooksecurefunc,
		GetTotemInfo = GetTotemInfo,
		GetTotemDuration = GetTotemDuration,
		GetTime = GetTime,
		issecretvalue = issecretvalue,
		NUM_MULTI_CAST_BUTTONS_PER_PAGE = NUM_MULTI_CAST_BUTTONS_PER_PAGE,
		MultiCastActionBarFrame_Update = MultiCastActionBarFrame_Update,
		ChangeMultiCastActionPage = ChangeMultiCastActionPage,
		Enum = Enum,
		option = visuals.db.totemTimers,
	}
	local savedSlots = {}
	for i = 1, 4 do
		savedSlots[i] = rawget(_G, "MultiCastSlotButton" .. i)
	end

	local currentClass = "SHAMAN"
	UnitClass = function() return "Shaman", currentClass end
	NUM_MULTI_CAST_BUTTONS_PER_PAGE = 4
	GetTime = function() return 1000 end
	Enum = setmetatable({
		StatusBarInterpolation = { Immediate = 0 },
		StatusBarTimerDirection = { RemainingTime = 1 },
	}, { __index = saved.Enum })
	hooksecurefunc = function(a, b, c)
		saved.hooksecurefunc(a, b, c)
		if type(a) == "string" and type(_G[a]) == "function" then
			local orig = _G[a]
			_G[a] = function(...)
				local r = orig(...)
				b(...)
				return r
			end
		end
	end

	local created = {}
	CreateFrame = function(kind, name, parent, template)
		local f = saved.CreateFrame(kind, name, parent, template)
		f.kind = kind
		f.parent = parent
		f.level = 1
		f.GetParent = function(self) return rawget(self, "parent") end
		f.SetFrameLevel = function(self, lvl) self.level = lvl end
		f.GetFrameLevel = function(self) return self.level end
		if kind == "StatusBar" then
			f.SetStatusBarTexture = function(self, tex) self.texture = tex end
			f.SetStatusBarColor = function(self, r, g, b) self.color = { r, g, b } end
			f.SetTimerDuration = function(self, dur, interp, dir) self.timerDur, self.timerInterp, self.timerDir = dur, interp, dir end
			f.SetMinMaxValues = function(self, lo, hi) self.minVal, self.maxVal = lo, hi end
			f.SetValue = function(self, v) self.val = v end
		elseif kind == "Cooldown" then
			local fs = NewFrame("FontString")
			fs.SetPoint = function(self, ...) self.anchor = { ... } end
			fs.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
			f.countdownFS = fs
			f.GetCountdownFontString = function(self) return self.countdownFS end
			f.SetDrawSwipe = function(self, v) self.drawSwipe = v end
			f.SetDrawEdge = function(self, v) self.drawEdge = v end
			f.SetDrawBling = function(self, v) self.drawBling = v end
			f.SetHideCountdownNumbers = function(self, v) self.hideNumbers = v end
			f.SetMinimumCountdownDuration = function(self, v) self.minDuration = v end
			f.SetCountdownAbbrevThreshold = function(self, v) self.abbrevThreshold = v end
			f.SetCountdownFont = function(self, v) self.countdownFont = v end
			f.SetCooldownFromDurationObject = function(self, dur, clearIfZero)
				self.durObj, self.clearIfZero, self.cleared = dur, clearIfZero, false
			end
			f.SetCooldown = function(self, s, d, m)
				self.start, self.duration, self.modRate, self.cleared = s, d, m, false
			end
			f.Clear = function(self)
				self.durObj, self.start, self.duration, self.cleared = nil, nil, nil, true
			end
		end
		created[#created + 1] = f
		return f
	end

	local slots = {}
	local slotIDs = { 1, 2, 3, 0 }
	for i = 1, 4 do
		local btn = NewFrame("CheckButton")
		btn.slotID = slotIDs[i]
		btn.GetID = function(self) return self.slotID end
		btn.GetFrameLevel = function() return 10 end
		btn.actionButton = { GetFrameLevel = function() return 14 end }
		btn.SetFrameLevel = function(self, lvl) self.level = lvl end
		_G["MultiCastSlotButton" .. i] = btn
		slots[i] = btn
	end
	local origOverlayFrameLevel
	local function FindOverlay(slotButton)
		for _, f in ipairs(created) do
			if f.kind == "Frame" and f:GetParent() == slotButton and f.cooldown and f.bar then
				return f
			end
		end
	end

	local totemInfo = {
		[1] = { true, "Searing Totem", 980, 60, 123, 1 },
		[2] = { false, "", 0, 0, 0, 1 },
		[3] = { true, "Healing Stream Totem", 990, 120, 456, 1 },
	}
	local durObjs = {
		[1] = { id = "fire-dur" },
		[2] = { id = "earth-zero" },
		[3] = { id = "water-dur" },
	}
	GetTotemInfo = function(slot)
		local info = totemInfo[slot]
		if info then return unpack(info, 1, 6) end
		return false, "", 0, 0, 0, 1
	end
	GetTotemDuration = function(slot) return durObjs[slot] end
	MultiCastActionBarFrame_Update = function() end
	ChangeMultiCastActionPage = function() end

	visuals.db.totemTimers = true
	visuals:OnOptionChanged("totemTimers")

	local fireOv = assert(FindOverlay(slots[1]), "fire totem overlay created")
	local waterOv = assert(FindOverlay(slots[3]), "water totem overlay created")
	assert(fireOv:IsShown() and waterOv:IsShown(), "active totem slots show overlays")
	assert(not FindOverlay(slots[2]) and not FindOverlay(slots[4]), "inactive or hidden slots stay empty")
	assert(fireOv.cooldown.durObj == durObjs[1] and fireOv.cooldown.clearIfZero == true, "duration object passed to cooldown")
	assert(fireOv.cooldown.drawSwipe == false and fireOv.cooldown.hideNumbers == false, "countdown shown without swipe")
	assert(fireOv.cooldown.abbrevThreshold == 600 and fireOv.cooldown.minDuration == 0, "mm:ss threshold and 0s min configured")
	assert(fireOv.cooldown.countdownFS.anchor and fireOv.cooldown.countdownFS.anchor[1] == "BOTTOM", "countdown anchored at bottom")
	assert(fireOv.bar:IsShown() and fireOv.bar.timerDur == durObjs[1] and fireOv.bar.timerDir == 1, "progress bar driven by duration object")
	assert(fireOv.bar.color[1] > 0.9 and waterOv.bar.color[3] > 0.9, "element colours distinguish fire and water")
	origOverlayFrameLevel = fireOv:GetFrameLevel()
	assert(origOverlayFrameLevel == 18, "overlay sits above the action button and its spell cooldown")

	-- Secret values in combat: GetTotemInfo returns secret booleans/numbers; GetTotemDuration drives the widgets safely.
	local secretVal = {}
	issecretvalue = function(v) return v == secretVal end
	totemInfo[2] = { secretVal, secretVal, secretVal, secretVal, secretVal, 1 }
	MultiCastActionBarFrame_Update()
	local earthOv = assert(FindOverlay(slots[2]), "secret totem slot still updates via duration object")
	assert(earthOv:IsShown() and earthOv.cooldown.durObj == durObjs[2] and earthOv.bar.timerDur == durObjs[2],
		"secret totem uses SetCooldownFromDurationObject and SetTimerDuration without Lua comparison")

	-- Expiring / recalling a totem hides and clears the overlay on PLAYER_TOTEM_UPDATE.
	issecretvalue = saved.issecretvalue
	totemInfo[1] = { false, "", 0, 0, 0, 1 }
	totemInfo[2] = { false, "", 0, 0, 0, 1 }
	ChangeMultiCastActionPage(2)
	assert(not fireOv:IsShown() and fireOv.cooldown.cleared and not fireOv.bar:IsShown(), "expired fire totem cleared")
	assert(not earthOv:IsShown() and earthOv.cooldown.cleared, "cleared earth totem hidden")

	-- Fallback path when GetTotemDuration is absent, triggered via PLAYER_TOTEM_UPDATE event.
	local watchFrame
	for _, f in ipairs(created) do
		if f.kind == "Frame" and rawget(f, "parent") == nil and f:GetScript("OnEvent") then
			watchFrame = f
			break
		end
	end
	assert(watchFrame, "totem watcher frame created")
	GetTotemDuration = nil
	totemInfo[1] = { true, "Searing Totem", 980, 60, 123, 1 }
	watchFrame:GetScript("OnEvent")(watchFrame, "PLAYER_TOTEM_UPDATE", 1)
	assert(fireOv:IsShown() and fireOv.cooldown.start == 980 and fireOv.cooldown.duration == 60, "fallback uses SetCooldown")
	assert(fireOv.bar:IsShown() and fireOv.bar.maxVal == 60 and fireOv.bar.val == 40, "fallback sets status bar remaining time")

	-- Disabling the option clears all overlays.
	visuals.db.totemTimers = false
	visuals:OnOptionChanged("totemTimers")
	assert(not fireOv:IsShown() and fireOv.cooldown.cleared and not waterOv:IsShown(), "turning option off hides all totem overlays")

	-- Non-shaman class stays inactive even when option is enabled.
	currentClass = "WARRIOR"
	visuals.db.totemTimers = true
	visuals:OnOptionChanged("totemTimers")
	assert(not fireOv:IsShown() and not waterOv:IsShown(), "non-shaman does not show totem overlays")

	-- Restore globals and option state.
	for i = 1, 4 do
		_G["MultiCastSlotButton" .. i] = savedSlots[i]
	end
	UnitClass = saved.UnitClass
	CreateFrame = saved.CreateFrame
	hooksecurefunc = saved.hooksecurefunc
	GetTotemInfo = saved.GetTotemInfo
	GetTotemDuration = saved.GetTotemDuration
	GetTime = saved.GetTime
	issecretvalue = saved.issecretvalue
	NUM_MULTI_CAST_BUTTONS_PER_PAGE = saved.NUM_MULTI_CAST_BUTTONS_PER_PAGE
	MultiCastActionBarFrame_Update = saved.MultiCastActionBarFrame_Update
	ChangeMultiCastActionPage = saved.ChangeMultiCastActionPage
	Enum = saved.Enum
	visuals.db.totemTimers = saved.option
	visuals:OnOptionChanged("totemTimers")
end)()

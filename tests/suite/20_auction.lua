-- Auction house: mailbox sale summary (revenue, costs, net profit, refunded deposit, batch total)
(function()
	local A = ns:GetModule("Auction")
	local saved = {
		GetMoneyString, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo,
		C_Timer.After, ns.Print, PlaySoundFile, issecretvalue,
		A.db.saleMailSummary, A.db.saleSound, ns.db.quiet,
	}
	local now, messages, timers, soundPlays = 200, {}, {}, 0
	GetMoneyString = function(v) return tostring(v) .. "c" end
	GetTime = function() return now end
	PlaySoundFile = function() soundPlays = soundPlays + 1 return true end
	C_Timer.After = function(delay, fn)
		timers[#timers + 1] = { delay = delay, fn = fn }
	end
	ns.Print = function(msg, ...)
		if ns.db and ns.db.quiet then
			return
		end
		if select("#", ...) > 0 then
			msg = msg:format(...)
		end
		messages[#messages + 1] = tostring(msg)
	end

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
		return m.invoiceType, m.itemName, m.playerName, m.bid, m.buyout, m.deposit, m.consignment, nil, nil, nil, m.count
	end

	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end

	ns.db.quiet = false
	A.db.saleMailSummary = true
	A.db.saleSound = false
	A:OnOptionChanged("saleSound")
	A:OnOptionChanged("saleMailSummary")
	A.ResetSaleMailSummaryState()

	-- ReadSaleMail: distinguishes seller mail from buyer/temp/regular mail and separates deposit from costs/net
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 190100, invoiceType = "seller", itemName = "Kupfererz", bid = 200000, deposit = 100, consignment = 10000, count = 20 },
		{ subject = "Auktion gewonnen: Leinenstoff", money = 0, invoiceType = "buyer", itemName = "Leinenstoff", bid = 1200 },
		{ subject = "Auktion erfolgreich: Seidenstoff", money = 0, invoiceType = "seller_temp_invoice", itemName = "Seidenstoff", bid = 3000 },
		{ subject = "Gold von Freund", money = 50000 },
	}
	local m1 = A.ReadSaleMail(1)
	assert(m1 and m1.itemName == "Kupfererz" and m1.count == 20 and m1.revenue == 200000
		and m1.cost == 10000 and m1.deposit == 100 and m1.net == 190000,
		"ReadSaleMail parses seller invoice fields and separates refunded deposit from net profit")
	assert(A.ReadSaleMail(2) == nil and A.ReadSaleMail(3) == nil and A.ReadSaleMail(4) == nil,
		"ReadSaleMail ignores buyer, temp invoice and non-auction mail")

	-- Single sale mail: prints one line, no total line when timer expires
	Fire("MAIL_SHOW")
	A.OnTakeSaleMail(1)
	-- Double-click before server response must not duplicate
	A.OnTakeSaleMail(1)
	table.remove(inbox, 1)
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 1, "single loot prints one chat line")
	assert(messages[1]:find("Kupfererz x20", 1, true) and messages[1]:find("200000c", 1, true)
		and messages[1]:find("10000c", 1, true) and messages[1]:find("190000c", 1, true)
		and messages[1]:find("100c", 1, true),
		"single line contains item+count, revenue, cost, net and separate refunded deposit: " .. messages[1])
	assert(#timers == 1, "batch timer scheduled")
	timers[1].fn()
	assert(#messages == 1, "single mail does not print a redundant total line")

	-- MAIL_FAILED cancels pending take without printing
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Eisenschwert", money = 490000, invoiceType = "seller", itemName = "Eisenschwert", bid = 500000, deposit = 15000, consignment = 25000, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1)
	Fire("MAIL_FAILED")
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "failed take prints nothing")

	-- MAIL_SUCCESS before MAIL_INBOX_UPDATE reports once (no double report on subsequent MAIL_INBOX_UPDATE)
	A.OnTakeSaleMail(1)
	Fire("MAIL_SUCCESS", nil)
	table.remove(inbox, 1)
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 1 and messages[1]:find("Eisenschwert", 1, true) and not messages[1]:find("x1", 1, true),
		"MAIL_SUCCESS before MAIL_INBOX_UPDATE prints once without x1 suffix")
	timers[#timers].fn()
	assert(#messages == 1, "still no total line for 1 mail")

	-- Rapid sequence of 3 sale mails (including 2 identical, like OpenAllMail): individual lines + total line
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 5 },
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 5 },
		{ subject = "Auktion erfolgreich: Silbererz", money = 19200, invoiceType = "seller", itemName = "Silbererz", bid = 20000, deposit = 200, consignment = 1000, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	for step = 1, 3 do
		now = now + 0.2
		A.OnTakeSaleMail(1)
		table.remove(inbox, 1)
		Fire("MAIL_INBOX_UPDATE")
		Fire("MAIL_SUCCESS", nil)
	end
	assert(#messages == 3, "three individual lines printed during rapid sequence")
	-- Stale earlier timers must not flush early
	timers[1].fn()
	timers[2].fn()
	assert(#messages == 3, "earlier superseded timers do not flush")
	-- Final timer flushes the total line
	timers[3].fn()
	assert(#messages == 4, "final timer prints total summary line")
	assert(messages[4]:find("3", 1, true) and messages[4]:find("40000c", 1, true)
		and messages[4]:find("2000c", 1, true) and messages[4]:find("38000c", 1, true)
		and messages[4]:find("200c", 1, true),
		"total line sums count, revenue, costs, net and refunded deposit: " .. messages[4])

	-- Closing mailbox flushes active batch immediately and prevents duplicate print when timer later fires
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Wollstoff", money = 4750, invoiceType = "seller", itemName = "Wollstoff", bid = 5000, deposit = 0, consignment = 250, count = 10 },
		{ subject = "Auktion erfolgreich: Seidenstoff", money = 9500, invoiceType = "seller", itemName = "Seidenstoff", bid = 10000, deposit = 0, consignment = 500, count = 10 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 2, "two lines printed before MAIL_CLOSED")
	Fire("MAIL_CLOSED")
	assert(#messages == 3 and messages[3]:find("15000c", 1, true) and messages[3]:find("750c", 1, true)
		and messages[3]:find("14250c", 1, true),
		"MAIL_CLOSED flushes total line immediately without deposit suffix when deposit == 0")
	timers[#timers].fn()
	assert(#messages == 3, "timer firing after MAIL_CLOSED does not duplicate total line")

	-- Respects ns.db.quiet ("mute all messages")
	wipe(messages); wipe(timers)
	ns.db.quiet = true
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "ns.db.quiet silences sale mail summary")
	ns.db.quiet = false

	-- Option independence: disabling saleSound keeps saleMailSummary working, and vice versa
	wipe(messages); wipe(timers); soundPlays = 0
	A.db.saleSound = true
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()
	A.db.saleMailSummary = false
	A:OnOptionChanged("saleMailSummary")
	inbox = {
		{ sender = "AH", subject = "Auktion erfolgreich: Golderz", money = 9500, wasRead = false, invoiceType = "seller", itemName = "Golderz", bid = 10000, deposit = 0, consignment = 500, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(soundPlays == 1, "disabling saleMailSummary leaves saleSound MAIL_INBOX_UPDATE active")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "saleMailSummary off prints nothing")

	-- Secret values in inbox data are skipped safely without error
	local secretTag = {}
	issecretvalue = function(v) return v == secretTag end
	inbox = {
		{ subject = "Auktion", money = secretTag, invoiceType = "seller", itemName = "Erz", bid = 1000, deposit = 0, consignment = 50, count = 1 },
		{ subject = "Auktion", money = 950, invoiceType = secretTag, itemName = "Erz", bid = 1000, deposit = 0, consignment = 50, count = 1 },
	}
	assert(A.ReadSaleMail(1) == nil and A.ReadSaleMail(2) == nil, "ReadSaleMail skips secret values safely")
	issecretvalue = saved[9]

	GetMoneyString, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = unpack(saved, 1, 5)
	C_Timer.After, ns.Print, PlaySoundFile, issecretvalue = unpack(saved, 6, 9)
	A.db.saleMailSummary, A.db.saleSound, ns.db.quiet = unpack(saved, 10, 12)
	A:OnOptionChanged("saleSound")
	A:OnOptionChanged("saleMailSummary")
	A.ResetSaleMailState()
	A.ResetSaleMailSummaryState()
	print("auction sale mail summary OK")
end)()
;(function()
	-- World map quest starts: profession skill & max-level filtering, nearby pin grouping and combined tooltip.
	local symbols = ns.MapSymbols
	local wm = ns:GetModule("WorldMap")
	local collect = uv(symbols.Count, "Collect")
	local questSource
	for _, source in ipairs(uv(collect, "sources")) do
		if uv(source, "QuestStartAvailable") then questSource = source end
	end
	assert(questSource, "quest start source registered")
	local savedStarts, savedLib = uv(questSource, "questStarts"), ns.QuestieDB.Get
	local savedComplete, savedActive, savedTitle = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetTitleForQuestID
	local savedLevel, savedProfs, savedProfInfo = UnitLevel, GetProfessions, GetProfessionInfo
	local savedOption, savedDisc = wm.db.questStarts, wm.db.discoveries

	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	C_QuestLog.GetTitleForQuestID = function() return nil end
	ns.QuestieDB.Get = function() return { Quest = { Get = function() return nil end } } end
	wm.db.questStarts, wm.db.discoveries = true, false
	UnitLevel = function() return 10 end
	-- Player knows Alchemy (171) at rank 50 only; nil hole in slot 1 verifies select() handling.
	GetProfessions = function() return nil, 2 end
	GetProfessionInfo = function(i)
		if i == 2 then return "Alchemie", 1, 50, 75, 0, 0, 171 end
	end

	setuv(questSource, "questStarts", {
		[1429] = {
			-- Two quests on the same NPC + one slightly offset within 0.8% -> merged into 1 pin, duplicate ID deduped.
			{ x = 42.1, y = 65.9, data = { id = 1001, name = "Alpha Quest" } },
			{ x = 42.1, y = 65.9, data = { id = 1002, name = "Beta Quest" } },
			{ x = 42.5, y = 66.1, data = { id = 1001, name = "Alpha Quest" } },
			-- Profession quest met (Alchemy 1) and unmet (Blacksmithing 1, Alchemy 75).
			{ x = 42.2, y = 65.9, data = { id = 1003, name = "Alchemy Intro", skill = 1710001 } },
			{ x = 42.2, y = 65.9, data = { id = 1004, name = "Smithing Intro", skill = 1640001 } },
			{ x = 42.2, y = 65.9, data = { id = 1005, name = "Alchemy Expert", skill = 1710075 } },
			-- Max-level gate: maxLevel 8 hidden at level 10, maxLevel 10 allowed at level 10.
			{ x = 42.2, y = 65.9, data = { id = 1006, name = "Too High", maxLevel = 8 } },
			{ x = 42.2, y = 65.9, data = { id = 1007, name = "Just In Time", maxLevel = 10 } },
			-- Separate location >0.8% away -> second pin.
			{ x = 48.9, y = 41.6, data = { id = 1008, name = "Northshire Quest" } },
		},
	})

	local pins = {}
	questSource(1429, function(x, y, symbol)
		pins[#pins + 1] = { x = x, y = y, symbol = symbol }
	end)
	assert(#pins == 2, "nearby starts merge into one pin while distant ones stay separate (got " .. #pins .. ")")
	assert(#pins[1].symbol.data == 4, "group keeps 4 eligible unique quests (1001, 1002, 1003, 1007)")
	assert(#pins[2].symbol.data == 1 and pins[2].symbol.data[1].id == 1008, "single distant quest stays standalone")

	-- Verify tooltip formatting for single, grouped and >15 capped groups.
	local lines = {}
	local tip = { AddLine = function(_, text) lines[#lines + 1] = text end }
	pins[2].symbol.tooltip(tip, pins[2].symbol)
	assert(lines[1] == "Northshire Quest" and lines[2] == ns.L.WORLDMAP_QUEST_START, "single quest tooltip format")
	lines = {}
	pins[1].symbol.tooltip(tip, pins[1].symbol)
	assert(lines[1] == ns.L.WORLDMAP_QUEST_START_GROUP:format(4), "grouped tooltip header shows count")
	assert(lines[2] == "Alchemy Intro" and lines[3] == "Alpha Quest" and lines[4] == "Beta Quest" and lines[5] == "Just In Time",
		"grouped tooltip sorts titles alphabetically")

	local many = {}
	for i = 1, 18 do many[i] = { id = 2000 + i, name = ("Quest %02d"):format(i) } end
	lines = {}
	pins[1].symbol.tooltip(tip, { data = many })
	assert(lines[1] == ns.L.WORLDMAP_QUEST_START_GROUP:format(18) and lines[17] == ns.L.WORLDMAP_QUEST_START_MORE:format(3),
		"large group tooltips cap lines and show remainder count")

	setuv(questSource, "questStarts", savedStarts)
	ns.QuestieDB.Get, C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetTitleForQuestID =
		savedLib, savedComplete, savedActive, savedTitle
	UnitLevel, GetProfessions, GetProfessionInfo = savedLevel, savedProfs, savedProfInfo
	wm.db.questStarts, wm.db.discoveries = savedOption, savedDisc
	print("quest start filtering & grouping OK")
end)()
dofile("wanderlust.lua")
dofile("bundled.lua")
;(function()
	local voice = ns:GetModule("EmoteVoice")
	local calls = {}
	local saved = voice.Command
	voice.Command = function(msg) calls[#calls + 1] = msg end
	SlashCmdList.FOREVERPLUS("stimme taverne")
	SlashCmdList.FOREVERPLUS("voice epic")
	SlashCmdList.FOREVERPLUS("stimme")
	SlashCmdList.FOREVERPLUS("voice")
	voice.Command = saved
	assert(#calls == 4 and calls[1] == "stimme taverne" and calls[2] == "voice epic"
		and calls[3] == "stimme" and calls[4] == "voice", "slash commands route to EmoteVoice.Command")
end)()
;(function()
	-- Portrait mode activation flashes & natural-decay client sounds: Wanderlust (Brann), RP (Chromie), Berserker (Muradin/Grommash).
	local pm = ns.PortraitModes
	local visuals = ns:GetModule("Visuals")
	local helpers = ns:GetModule("Helpers")
	local flash = uv(pm.StopFlash, "Flash")
	assert(pm and visuals and helpers and flash, "PortraitModes Flash subsystem loaded")

	-- All four new TGA assets exist on disk.
	for _, file in ipairs({ "ModeBrann.tga", "ModeChromie.tga", "ModeMuradin.tga", "ModeGrommash.tga" }) do
		local f = io.open(root .. "/Media/" .. file, "rb")
		assert(f, "missing mode flash texture: " .. file)
		local header = f:read(18)
		f:close()
		assert(header and #header == 18, "valid TGA header for " .. file)
	end

	-- Visuals options expose portraitModeFlash and portraitModeFlashSound with new = true and sensible defaults.
	local flashOpt, soundOpt
	for _, opt in ipairs(visuals.options) do
		if opt.key == "portraitModeFlash" then flashOpt = opt end
		if opt.key == "portraitModeFlashSound" then soundOpt = opt end
	end
	assert(flashOpt and flashOpt.new == true and flashOpt.parent == "playerPortraitWheel" and visuals.db.portraitModeFlash == true,
		"portraitModeFlash defaults on, is child of playerPortraitWheel and marked NEW")
	assert(soundOpt and soundOpt.new == true and soundOpt.parent == "portraitModeFlash" and visuals.db.portraitModeFlashSound == true,
		"portraitModeFlashSound defaults on, is child of portraitModeFlash and marked NEW")

	local savedFlashOpt, savedSoundOpt = visuals.db.portraitModeFlash, visuals.db.portraitModeFlashSound
	local savedCreate, savedPlay, savedPlayFile, savedStop, savedAfter, savedTicker =
		CreateFrame, PlaySound, PlaySoundFile, StopSound, C_Timer.After, C_Timer.NewTicker
	local savedFaction, savedSecret = rawget(_G, "UnitFactionGroup"), rawget(_G, "issecretvalue")
	local savedW, savedH = UIParent.w, UIParent.h
	local savedFrame = flash.frame
	local savedGlobal = rawget(_G, "ForeverPlusModeFlash")

	local WIND_IDS = { [982361] = true, [982363] = true, [982365] = true, [982367] = true }
	local IMPACT_IDS = { [567634] = true, [1324858] = true, [1324859] = true }
	local flashFrame, texturePath, strata, mouseEnabled, ignoreAlpha
	local playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	local nextHandle = 400
	local factionValue, secretToken = "Alliance", nil

	UIParent.w, UIParent.h = 1600, 900
	flash.frame = nil
	ForeverPlusModeFlash = nil
	UnitFactionGroup = function() return factionValue end
	issecretvalue = function(v) return secretToken ~= nil and v == secretToken end
	PlaySound = function(kit, channel)
		nextHandle = nextHandle + 1
		playedKits[#playedKits + 1] = { kit = kit, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	PlaySoundFile = function(id, channel)
		nextHandle = nextHandle + 1
		playedFiles[#playedFiles + 1] = { id = id, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	StopSound = function(handle) stopped[#stopped + 1] = handle end
	C_Timer.After = function(delay, fn) pendingAfter[#pendingAfter + 1] = { delay = delay, fn = fn } end
	C_Timer.NewTicker = function() return { Cancel = function() end } end
	CreateFrame = function(kind, name, parent, template)
		local f = savedCreate(kind, name, parent, template)
		if name == "ForeverPlusModeFlash" then
			flashFrame = f
			local origStrata = f.SetFrameStrata
			f.SetFrameStrata = function(self, s) strata = s; return origStrata(self, s) end
			local origMouse = f.EnableMouse
			f.EnableMouse = function(self, on) mouseEnabled = on; return origMouse(self, on) end
			f.SetIgnoreParentAlpha = function(_, on) ignoreAlpha = on end
			f.SetSize = function(self, w, h) self.w, self.h = w, h end
			local origCreateTex = f.CreateTexture
			f.CreateTexture = function(self, ...)
				local tex = origCreateTex(self, ...)
				local origSetTex = tex.SetTexture
				tex.SetTexture = function(t, path) texturePath = path; return origSetTex(t, path) end
				return tex
			end
		end
		return f
	end

	-- 1. Wanderlust off -> on triggers Brann Bronzebeard, map open sound, delayed wind gust, natural decay on finish.
	local wander = ns:GetModule("Wanderlust")
	local savedWanderOn = wander.db.enabled
	if pm.IsModeActive("wanderlust") then pm.ToggleMode("wanderlust") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	pm.ToggleMode("wanderlust")
	assert(pm.IsModeActive("wanderlust") and flashFrame and flashFrame:IsShown(), "activating Wanderlust shows Brann")
	assert(strata == "FULLSCREEN_DIALOG" and mouseEnabled == false and ignoreAlpha == true,
		"mode flash uses non-interactive fullscreen overlay ignoring parent alpha")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeBrann.tga]], "Wanderlust shows ModeBrann.tga")
	assert(#playedKits == 1 and playedKits[1].kit == (SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844) and playedKits[1].channel == "SFX",
		"Wanderlust plays map/quest log open sound immediately on SFX")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.22) < 0.001, "Wanderlust schedules wind gust 0.22 s later")
	pendingAfter[1].fn()
	assert(#playedFiles == 1 and WIND_IDS[playedFiles[1].id] and playedFiles[1].channel == "SFX",
		"delayed Wanderlust timer plays verified wind gust on SFX")
	local update = flashFrame:GetScript("OnUpdate")
	assert(type(update) == "function", "mode flash runs OnUpdate while animating")
	update(flashFrame, 0.40)
	local holdW, holdA = flashFrame:GetWidth(), flashFrame:GetAlpha()
	assert(holdW > 700 and math.abs(holdW - flash.baseSize) < 1 and math.abs(holdA - 0.50) < 0.01,
		"Brann fills screen height at half alpha during hold")
	update(flashFrame, 1.35)
	assert(not flashFrame:IsShown() and flashFrame:GetAlpha() == 0 and flashFrame:GetScript("OnUpdate") == nil,
		"Brann finishes cleanly and stops OnUpdate (0 CPU idle)")
	assert(#stopped == 0, "normal completion lets Wanderlust sounds finish decaying naturally")

	-- 2. RP mode off -> on triggers Chromie, spellbook open + delayed quill sound.
	if pm.IsModeActive("rp") then pm.ToggleMode("rp") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	pm.ToggleMode("rp")
	assert(pm.IsModeActive("rp") and flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeChromie.tga]],
		"activating RP mode shows ModeChromie.tga")
	assert(#playedKits == 1 and playedKits[1].kit == (SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN or 829),
		"RP mode plays spellbook open immediately")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.26) < 0.001, "RP mode schedules quill sound 0.26 s later")
	pendingAfter[1].fn()
	assert(#playedKits == 2 and playedKits[2].kit == (SOUNDKIT and SOUNDKIT.IG_WRITE_QUEST or 3093),
		"delayed RP timer plays quill sound")
	-- Deactivating RP mode mid-flash stops the active portrait and sounds.
	local stoppedBeforeRP = #stopped
	pm.ToggleMode("rp")
	assert(not flashFrame:IsShown() and #stopped == stoppedBeforeRP + 2,
		"deactivating RP mode mid-flash stops visual and sound handles")

	-- 3. Berserker mode chooses Muradin for Alliance, Grommash for Horde, and falls back to Muradin on secret faction.
	if pm.IsModeActive("berserker") then pm.ToggleMode("berserker") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	factionValue = "Alliance"
	pm.ToggleMode("berserker")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]],
		"Alliance Berserker shows ModeMuradin.tga")
	assert(#playedFiles == 1 and playedFiles[1].id == 567473, "Berserker plays metal unsheathe immediately")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.18) < 0.001, "Berserker schedules impact 0.18 s later")
	pendingAfter[1].fn()
	local firstImpactID = playedFiles[2] and playedFiles[2].id
	assert(#playedFiles == 2 and IMPACT_IDS[firstImpactID], "delayed Berserker timer plays verified heavy impact")
	-- Overshoot punch peaks above base size during fade-in end, then settles and finishes cleanly.
	flashFrame:GetScript("OnUpdate")(flashFrame, 0.14)
	assert(flashFrame:GetWidth() > flash.baseSize * 1.02, "Berserker has punch overshoot scale on entry")
	flashFrame:GetScript("OnUpdate")(flashFrame, 1.30)
	assert(not flashFrame:IsShown() and #stopped == 0, "Berserker finishes cleanly with natural sound decay")

	-- Horde Berserker shows Grommash and alternates the impact sound.
	pm.ToggleMode("berserker")
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	factionValue = "Horde"
	pm.ToggleMode("berserker")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeGrommash.tga]], "Horde Berserker shows ModeGrommash.tga")
	pendingAfter[1].fn()
	assert(IMPACT_IDS[playedFiles[2].id] and playedFiles[2].id ~= firstImpactID,
		"second Berserker impact alternates to another verified hit")

	-- Secret faction falls back cleanly to Muradin without error.
	secretToken = "SECRET_FACTION"
	factionValue = secretToken
	pm.PreviewFlash("berserker")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "secret faction falls back cleanly to Muradin")
	secretToken, factionValue = nil, "Alliance"

	-- 4. Disabling portraitModeFlashSound stops active sounds immediately and keeps future previews silent;
	--    disabling portraitModeFlash hides the active flash and suppresses ToggleMode flashes.
	ns.SetOption("Visuals", "portraitModeFlashSound", false)
	assert(flashFrame:IsShown() and #stopped > 0, "disabling portraitModeFlashSound stops active sounds without hiding portrait")
	ns.SetOption("Visuals", "portraitModeFlash", false)
	assert(not flashFrame:IsShown() and flashFrame:GetScript("OnUpdate") == nil, "disabling portraitModeFlash stops active flash")
	playedKits, playedFiles, pendingAfter = {}, {}, {}
	pm.ToggleMode("berserker")
	pm.ToggleMode("berserker")
	assert(not flashFrame:IsShown() and #playedFiles == 0, "portraitModeFlash = false suppresses activation flash")

	-- 5. Slash commands preview each mode and explicit faction variants.
	ns.SetOption("Visuals", "portraitModeFlash", true)
	SlashCmdList.FOREVERPLUS("brann")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeBrann.tga]], "/fp brann previews Brann")
	SlashCmdList.FOREVERPLUS("chromie")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeChromie.tga]], "/fp chromie previews Chromie")
	SlashCmdList.FOREVERPLUS("grommash")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeGrommash.tga]], "/fp grommash previews Grommash")
	SlashCmdList.FOREVERPLUS("muradin")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "/fp muradin previews Muradin")
	SlashCmdList.FOREVERPLUS("berserker")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "/fp berserker uses player faction")

	-- 6. Mutual exclusion with Nat Pagle (Helpers.PreviewBear hides mode flash and vice versa).
	helpers.PreviewBear()
	assert(not flashFrame:IsShown(), "starting Nat Pagle flash stops active PortraitModes flash")
	pm.PreviewFlash("wanderlust")
	assert(flashFrame:IsShown(), "starting PortraitModes flash shows Brann cleanly")
	pm.StopFlash()
	helpers.StopBearFlash()

	-- Restore state cleanly.
	if pm.IsModeActive("wanderlust") ~= (savedWanderOn and true or false) then
		ns.SetOption("Wanderlust", "enabled", savedWanderOn)
	end
	if pm.IsModeActive("berserker") then pm.ToggleMode("berserker") end
	ns.SetOption("Visuals", "portraitModeFlashSound", savedSoundOpt)
	ns.SetOption("Visuals", "portraitModeFlash", savedFlashOpt)
	UIParent.w, UIParent.h = savedW, savedH
	CreateFrame, PlaySound, PlaySoundFile, StopSound, C_Timer.After, C_Timer.NewTicker =
		savedCreate, savedPlay, savedPlayFile, savedStop, savedAfter, savedTicker
	UnitFactionGroup, issecretvalue = savedFaction, savedSecret
	flash.frame = savedFrame
	ForeverPlusModeFlash = savedGlobal
	print("portrait mode flashes OK")
end)()
assert(loadfile("emote_voice.lua"))(root, ns)
assert(loadfile("chronicle.lua"))(root, ns, uv)
;(function()
	-- Waypoint: quest objective clicks (questPOI) and arrow designs/colors/preview
	local way = ns:GetModule("Waypoint")
	assert(way.db.questWaypoint == true, "questWaypoint enabled by default")
	assert(way.db.arrowStyle == "standard" and way.db.arrowColor == "DEFAULT", "default arrow style and color")
	assert(type(way.db.arrowCustomColor) == "table", "default custom arrow color")

	local optsByKey, hasColorBtn = {}, false
	for _, opt in ipairs(way.options) do
		if opt.key then optsByKey[opt.key] = opt end
		if opt.type == "button" and opt.func == way.ChooseColor then hasColorBtn = true end
	end
	assert(optsByKey.questWaypoint and optsByKey.questWaypoint.new == true, "questWaypoint has new=true")
	assert(optsByKey.arrowStyle and optsByKey.arrowStyle.new == true, "arrowStyle has new=true")
	assert(optsByKey.arrowColor and optsByKey.arrowColor.new == true, "arrowColor has new=true")
	assert(hasColorBtn, "custom arrow color picker button present")
	assert(#optsByKey.arrowStyle.values() == 5, "5 arrow designs available")
	local colorValues = optsByKey.arrowColor.values()
	assert(#colorValues == 11, "gold, 9 class colors plus custom available")
	assert(colorValues[1][1] == "DEFAULT" and colorValues[2][1] == "WARRIOR" and colorValues[10][1] == "HUNTER"
		and colorValues[11][1] == "CUSTOM", "gold first, class colors in Forever order, custom last")
	assert(colorValues[8][2]:find("Mage", 1, true), "class color named after the class")

	-- Old color presets become the same custom color
	local legacyDb = { arrowColor = "BLUE", arrowCustomColor = { r = 1, g = 0.82, b = 0 } }
	way.MigrateArrowColor(legacyDb)
	assert(legacyDb.arrowColor == "CUSTOM" and math.abs(legacyDb.arrowCustomColor.g - 0.78) < 1e-6,
		"old BLUE preset migrates to custom color")
	legacyDb = { arrowColor = "MAGE" }
	way.MigrateArrowColor(legacyDb)
	assert(legacyDb.arrowColor == "MAGE" and legacyDb.arrowCustomColor == nil, "class color left as is")

	-- Quest objective click tests
	local savedCVar, savedShift = GetCVarBool, IsShiftKeyDown
	local savedCan, savedSet, savedClear = C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint
	local savedHas, savedGet, savedBest, savedInfo = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.GetBestMapForUnit, C_Map.GetMapInfo
	local savedUiPoint, savedSuper, savedPrint = UiMapPoint, C_SuperTrack, ns.Print
	local savedQuestsOnMap, savedNextWp, savedNextWpMap, savedTitle =
		C_QuestLog.GetQuestsOnMap, C_QuestLog.GetNextWaypoint, C_QuestLog.GetNextWaypointForMap, C_QuestLog.GetTitleForQuestID
	local savedContinent = Enum.UIMapType.Continent

	local questPOIOn, shiftDown = false, false
	local userWp, superUserWp, superQuestID
	GetCVarBool = function(name) return name == "questPOI" and questPOIOn or false end
	IsShiftKeyDown = function() return shiftDown end
	Enum.UIMapType.Continent = 2
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.SetUserWaypoint = function(pt) userWp = pt return true end
	C_Map.ClearUserWaypoint = function() userWp = nil end
	C_Map.HasUserWaypoint = function() return userWp ~= nil end
	C_Map.GetUserWaypoint = function() return userWp end
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(id) return { mapID = id, mapType = id == 1415 and 2 or 3, name = "Zone" .. tostring(id) } end
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
	C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(v) superUserWp = v end,
		GetSuperTrackedQuestID = function() return superQuestID end,
	}
	C_QuestLog.GetTitleForQuestID = function(id) return id == 33 and "Wolves Across the Border" or nil end
	C_QuestLog.GetQuestsOnMap = function(mapID)
		if mapID == 1429 then
			return { { questID = 33, x = 0.46, y = 0.62 } }
		end
		return {}
	end
	C_QuestLog.GetNextWaypoint = function(id)
		if id == 33 then return 1429, 0.48, 0.65 end
	end
	C_QuestLog.GetNextWaypointForMap = function() return nil end
	ns.Print = function() end

	local zonePin = {
		GetQuestID = function() return 33 end,
		GetMap = function() return { GetMapID = function() return 1429 end } end,
		GetPosition = function() return 0.47, 0.63 end,
	}
	local continentPin = {
		GetQuestID = function() return 33 end,
		GetMap = function() return { GetMapID = function() return 1415 end } end,
		GetPosition = function() return 0.50, 0.50 end,
	}
	local trackerBtn = { GetQuestID = function() return 33 end }

	-- Disabled when questPOI CVar is off
	way.Clear()
	superQuestID, questPOIOn = 33, false
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "no waypoint when Blizzard questPOI is disabled")

	-- Disabled when questWaypoint option is off
	questPOIOn, way.db.questWaypoint = true, false
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "no waypoint when questWaypoint option is disabled")
	way.db.questWaypoint = true

	-- Ignored for right-click and shift-click
	way.OnQuestPOIClick(zonePin, "RightButton")
	assert(way.Target() == nil, "right-click ignored")
	shiftDown = true
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "shift-click ignored")
	shiftDown = false

	-- Left-click on zone map pin uses unquantized GetQuestsOnMap coordinates and preserves quest super-tracking
	local wind = ns:GetModule("GuidingWind")
	local savedWindEnabled = wind and wind.db and wind.db.enabled
	if wind and wind.db then wind.db.enabled = true end
	superUserWp = nil
	way.OnQuestPOIClick(zonePin, "LeftButton")
	local goal = way.Target()
	assert(goal and goal.mapID == 1429 and math.abs(goal.x - 0.46) < 1e-6 and math.abs(goal.y - 0.62) < 1e-6
		and goal.name == "Wolves Across the Border" and goal.questID == 33, "zone pin sets quest waypoint")
	assert(userWp and userWp.uiMapID == 1429 and superUserWp == nil, "sets user waypoint without overriding quest super-track")
	assert(not (_G.ForeverPlusWaypointArrow and _G.ForeverPlusWaypointArrow:IsShown()),
		"active GuidingWind keeps the waypoint arrow hidden even after quest objective click")
	if wind and wind.db then wind.db.enabled = false end

	-- Clicking the same pin again (Blizzard clears super-tracking) clears the quest waypoint
	superQuestID = 0
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil and userWp == nil, "deselecting quest objective clears its waypoint")

	-- Continent pin resolves to the zone map via GetNextWaypoint
	superQuestID = 33
	way.OnQuestPOIClick(continentPin, "LeftButton")
	goal = way.Target()
	assert(goal and goal.mapID == 1429 and math.abs(goal.x - 0.48) < 1e-6 and math.abs(goal.y - 0.65) < 1e-6,
		"continent pin resolves to zone waypoint")

	-- Tracker/log POI button (no GetMap) resolves via GetNextWaypoint
	way.Clear()
	way.OnQuestPOIClick(trackerBtn, "LeftButton")
	goal = way.Target()
	assert(goal and goal.mapID == 1429 and goal.questID == 33, "tracker POI button sets quest waypoint")

	-- QUEST_TURNED_IN clears matching quest waypoint, leaves unrelated ones intact
	local listeners = uv(ns.RegisterEvent, "listeners")
	listeners.QUEST_TURNED_IN[way](way, "QUEST_TURNED_IN", 999)
	assert(way.Target() ~= nil, "unrelated quest turn-in keeps waypoint")
	listeners.QUEST_TURNED_IN[way](way, "QUEST_TURNED_IN", 33)
	assert(way.Target() == nil, "matching quest turn-in clears quest waypoint")

	-- Tooltip hint on MapCanvas.QuestPin.OnEnter
	local savedTipOwner, savedTipShown, savedTipAdd = GameTooltip.GetOwner, GameTooltip.IsShown, GameTooltip_AddInstructionLine
	local tipLines = {}
	GameTooltip.IsShown = function() return true end
	GameTooltip.GetOwner = function() return zonePin end
	GameTooltip_AddInstructionLine = function(_, text) tipLines[#tipLines + 1] = text end
	way.OnQuestPinEnter(nil, zonePin, 33)
	assert(#tipLines == 1 and tipLines[1] == ns.L.WAYPOINT_QUEST_CLICK, "quest pin tooltip adds click hint")
	questPOIOn = false
	way.OnQuestPinEnter(nil, zonePin, 33)
	assert(#tipLines == 1, "no tooltip hint when questPOI is off")
	GameTooltip.GetOwner, GameTooltip.IsShown, GameTooltip_AddInstructionLine = savedTipOwner, savedTipShown, savedTipAdd

	-- HookQuestPOI installs post-hook on POIButtonMixin.OnClick once
	local savedMixin, savedHook = rawget(_G, "POIButtonMixin"), hooksecurefunc
	local hookCount = 0
	_G.POIButtonMixin = { OnClick = function() end }
	hooksecurefunc = function(tbl, method)
		if tbl == _G.POIButtonMixin and method == "OnClick" then hookCount = hookCount + 1 end
	end
	way.HookQuestPOI()
	way.HookQuestPOI()
	assert(hookCount == 1, "HookQuestPOI hooks POIButtonMixin.OnClick once")
	_G.POIButtonMixin, hooksecurefunc = savedMixin, savedHook

	-- Arrow designs, colors, custom color picker, corpse tint and preview
	local arrow = _G.ForeverPlusWaypointArrow
	local tex = arrow.Arrow
	local lastAtlas, lastTex, lastCoords, lastDesat
	local savedSetAtlas, savedSetTex, savedSetCoords, savedSetDesat = tex.SetAtlas, tex.SetTexture, tex.SetTexCoord, tex.SetDesaturated
	local savedNewTimer, savedPicker = ns.NewTimer, ColorPickerFrame
	local savedGhost = rawget(_G, "UnitIsGhost")
	local previewCallback, pickerSpec, pickerShown = nil, nil, false
	tex.SetAtlas = function(_, a) lastAtlas, lastTex, lastCoords = a, nil, nil end
	tex.SetTexture = function(_, t) lastTex, lastAtlas = t, nil end
	tex.SetTexCoord = function(_, l, r, t, b) lastCoords = { l, r, t, b } end
	tex.SetDesaturated = function(_, d) lastDesat = d end
	ns.NewTimer = function(_, _, fn)
		previewCallback = fn
		return { Cancel = function() previewCallback = nil end }
	end

	-- Standard + Default keeps original untinted atlas
	arrow.lastStyleKey, arrow.lastDesat, arrow.lastR = nil, nil, nil
	way.db.arrowStyle, way.db.arrowColor = "standard", "DEFAULT"
	way:OnOptionChanged("arrowStyle")
	assert(arrow:IsShown(), "preview shows arrow when no waypoint is active")
	assert(lastAtlas == "Navigation-Tracked-Arrow" and lastDesat == false
		and tex.vertexColor[1] == 1 and tex.vertexColor[2] == 1 and tex.vertexColor[3] == 1, "standard default untinted")
	assert(previewCallback ~= nil, "preview timer scheduled")
	previewCallback()
	assert(not arrow:IsShown(), "preview hides arrow after timer expires")

	-- Standard + class color desaturates and tints with the client's class color
	local savedGetClassColor = C_ClassColor.GetClassColor
	C_ClassColor.GetClassColor = function(classFile)
		if classFile == "MAGE" then
			return { GetRGB = function() return 0.25, 0.78, 0.92 end }
		end
	end
	way.db.arrowColor = "MAGE"
	way:OnOptionChanged("arrowColor")
	assert(lastDesat == true and math.abs(tex.vertexColor[1] - 0.25) < 0.01
		and math.abs(tex.vertexColor[3] - 0.92) < 0.01, "standard mage color tints desaturated atlas")
	way.db.arrowColor = "WARRIOR"
	way:OnOptionChanged("arrowColor")
	assert(math.abs(tex.vertexColor[1] - 1) < 0.01 and math.abs(tex.vertexColor[2] - 0.82) < 0.01
		and math.abs(tex.vertexColor[3] - 0) < 0.01, "unknown class color falls back to gold")
	C_ClassColor.GetClassColor = savedGetClassColor

	-- Custom arrow designs load Media\WaypointArrows.tga with 1/256 UV inset
	local expectedTiles = {
		classic = { 0, 0 }, compass = { 1, 0 }, chevron = { 0, 1 }, rune = { 1, 1 },
	}
	for styleKey, pos in pairs(expectedTiles) do
		way.db.arrowStyle = styleKey
		way:OnOptionChanged("arrowStyle")
		assert(lastTex and lastTex:find("WaypointArrows.tga", 1, true), styleKey .. " uses custom sheet")
		assert(lastDesat == false, styleKey .. " is not desaturated")
		local inset = 1 / 256
		assert(math.abs(lastCoords[1] - (pos[1] * 0.5 + inset)) < 1e-6
			and math.abs(lastCoords[2] - ((pos[1] + 1) * 0.5 - inset)) < 1e-6
			and math.abs(lastCoords[3] - (pos[2] * 0.5 + inset)) < 1e-6
			and math.abs(lastCoords[4] - ((pos[2] + 1) * 0.5 - inset)) < 1e-6, styleKey .. " UV coords inset")
	end

	-- Corpse run keeps user style and forces spectral blue tint
	UnitIsGhost = function() return true end
	way.Refresh()
	assert(lastTex and lastTex:find("WaypointArrows.tga", 1, true), "corpse keeps custom arrow style")
	assert(math.abs(tex.vertexColor[1] - 0.40) < 0.01 and math.abs(tex.vertexColor[2] - 0.85) < 0.01
		and math.abs(tex.vertexColor[3] - 1.00) < 0.01, "corpse uses spectral blue color")
	UnitIsGhost = function() return false end

	-- Color picker updates custom color and cancel restores previous state
	local pickedRGB = { 0.2, 0.9, 0.4 }
	ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, spec) pickerSpec = spec pickerShown = true end,
		GetColorRGB = function() return pickedRGB[1], pickedRGB[2], pickedRGB[3] end,
		IsShown = function() return pickerShown end,
	}
	way.db.arrowStyle, way.db.arrowColor = "classic", "MAGE"
	way.db.arrowCustomColor = { r = 1, g = 0.82, b = 0 }
	way.ChooseColor()
	assert(pickerSpec and pickerSpec.hasOpacity == false, "color picker opened without opacity")
	pickerSpec.swatchFunc()
	assert(way.db.arrowColor == "CUSTOM" and math.abs(tex.vertexColor[2] - 0.9) < 1e-6, "swatch applies custom color")
	pickerShown = false
	pickerSpec.cancelFunc()
	assert(way.db.arrowColor == "MAGE" and math.abs(way.db.arrowCustomColor.r - 1) < 1e-6, "cancel restores previous color")

	-- Middle-click during preview closes preview cleanly
	way.Preview(false)
	assert(arrow:IsShown(), "preview active")
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	assert(not arrow:IsShown(), "middle-click closes preview")

	-- Inline preview images in design dropdown & large preview panel when SettingsPanel is open
	way.db.arrowColor, way.db.arrowCustomColor = "CUSTOM", { r = 0.27, g = 0.78, b = 1.00 }
	local styleEntries = optsByKey.arrowStyle.values()
	assert(styleEntries[1][2]:find("Navigation-Tracked-Arrow", 1, true) or styleEntries[1][2]:find("MiniMap-QuestArrow", 1, true),
		"standard design dropdown entry carries inline arrow preview")
	assert(styleEntries[2][2]:find("|TInterface\\AddOns\\ForeverPlus\\Media\\WaypointArrows.tga:18:18:0:0:256:256:1:127:1:127:69:199:255|t", 1, true),
		"classic dropdown entry carries tinted inline sprite preview")
	assert(styleEntries[5][2]:find(":129:255:129:255:69:199:255|t", 1, true),
		"rune dropdown entry uses bottom-right tile in current color")

	local savedSettingsShown, savedSettingsHook = SettingsPanel.IsShown, SettingsPanel.HookScript
	local settingsHideFn
	SettingsPanel.IsShown = function() return true end
	SettingsPanel.HookScript = function(_, script, fn)
		if script == "OnHide" then settingsHideFn = fn end
	end
	way.db.arrowStyle, way.db.arrowColor = "rune", "CUSTOM"
	way.db.arrowCustomColor = { r = 1.00, g = 0.52, b = 0.15 }
	way:OnOptionChanged("arrowStyle")
	local previewFrame = _G.ForeverPlusWaypointPreview
	assert(previewFrame and previewFrame:IsShown(), "large preview panel opens beside SettingsPanel")
	assert(previewFrame.Arrow and previewFrame.Arrow.vertexColor
		and math.abs(previewFrame.Arrow.vertexColor[1] - 1.00) < 0.01
		and math.abs(previewFrame.Arrow.vertexColor[2] - 0.52) < 0.01, "preview panel renders chosen arrow tint")
	assert(settingsHideFn ~= nil, "SettingsPanel OnHide hook installed")
	settingsHideFn()
	assert(not previewFrame:IsShown(), "closing SettingsPanel hides preview panel")

	-- Regression: changing design while standing still re-applies arrow rotation, and middle-click clears active waypoint
	local savedPlayerPos, savedFacing = C_Map.GetPlayerMapPosition, GetPlayerFacing
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	GetPlayerFacing = function() return 0 end
	way.Set(80, 50, "East")
	arrow:GetScript("OnUpdate")(arrow, 0.2)
	local rotBefore = tex.rotation
	assert(rotBefore and math.abs(rotBefore + math.pi / 2) < 1e-4, "active waypoint points east")
	tex.rotation = 0 -- simulate WoW resetting texture rotation on SetTexCoord/SetAtlas
	way.db.arrowStyle = "compass"
	way:OnOptionChanged("arrowStyle")
	assert(previewFrame:IsShown(), "preview panel opens alongside active waypoint in settings")
	arrow:GetScript("OnUpdate")(arrow, 0.2)
	assert(math.abs(tex.rotation - rotBefore) < 1e-4, "style change re-applies arrow rotation even while standing still")

	local click, doubleClick = arrow:GetScript("OnClick"), arrow:GetScript("OnDoubleClick")
	assert(way.db.clickArrowStyle and optsByKey.clickArrowStyle, "arrow click controls enabled by default")
	local savedList, savedGetSetting = SettingsPanel.GetSettingsList, Settings.GetSetting
	local setting, menu, label = {}, {}, nil
	local dropdown = {
		GetMenuDescription = function() return menu end,
		UpdateToMenuSelections = function(_, description)
			assert(description == menu)
			label = way.db.arrowStyle
		end,
	}
	local row = { GetSetting = function() return setting end, Control = { Dropdown = dropdown } }
	Settings.GetSetting = function(variable)
		if variable == "ForeverPlus_Waypoint_arrowStyle" then return setting end
	end
	SettingsPanel.GetSettingsList = function()
		return { ScrollBox = { ForEachFrame = function(_, visit) visit({}) visit(row) end } }
	end
	local goal = way.Target()
	for _, key in ipairs({ "chevron", "rune", "standard", "classic", "compass" }) do
		click(arrow, "LeftButton")
		assert(way.db.arrowStyle == key and arrow.lastStyleKey == key and label == key, "single-click selects and renders " .. key)
	end
	for _, entry in ipairs(way.ARROW_STYLES) do
		ns.SetOption("Waypoint", "arrowStyle", entry.key)
		click(arrow, "LeftButton")
		doubleClick(arrow, "LeftButton")
		assert(way.db.arrowStyle == "standard" and lastAtlas == "Navigation-Tracked-Arrow" and label == "standard", "double-click resets " .. entry.key)
	end
	assert(way.db.arrowColor == "CUSTOM" and way.Target() == goal, "design clicks preserve color and destination")
	ns.SetOption("Waypoint", "arrowStyle", "rune")
	click(arrow, "RightButton")
	doubleClick(arrow, "RightButton")
	assert(way.db.arrowStyle == "rune", "right-click leaves design alone")
	ns.SetOption("Waypoint", "clickArrowStyle", false)
	click(arrow, "LeftButton")
	doubleClick(arrow, "LeftButton")
	assert(way.db.arrowStyle == "rune", "disabled design gestures leave selection alone")
	ns.SetOption("Waypoint", "clickArrowStyle", true)
	SettingsPanel.GetSettingsList, Settings.GetSetting = savedList, savedGetSetting
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	assert(way.Target() == nil, "middle-click on active arrow clears waypoint even while preview panel is shown")
	settingsHideFn()
	C_Map.GetPlayerMapPosition, GetPlayerFacing = savedPlayerPos, savedFacing
	SettingsPanel.IsShown, SettingsPanel.HookScript = savedSettingsShown, savedSettingsHook

	-- Restore all mocked state
	way.Clear()
	if wind and wind.db then wind.db.enabled = savedWindEnabled end
	way.db.questWaypoint, way.db.arrowStyle, way.db.arrowColor = true, "standard", "DEFAULT"
	way.db.arrowCustomColor = { r = 1, g = 0.82, b = 0 }
	tex.SetAtlas, tex.SetTexture, tex.SetTexCoord, tex.SetDesaturated = savedSetAtlas, savedSetTex, savedSetCoords, savedSetDesat
	ns.NewTimer, ColorPickerFrame, UnitIsGhost = savedNewTimer, savedPicker, savedGhost
	GetCVarBool, IsShiftKeyDown = savedCVar, savedShift
	C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint = savedCan, savedSet, savedClear
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.GetBestMapForUnit, C_Map.GetMapInfo = savedHas, savedGet, savedBest, savedInfo
	UiMapPoint, C_SuperTrack, ns.Print = savedUiPoint, savedSuper, savedPrint
	C_QuestLog.GetQuestsOnMap, C_QuestLog.GetNextWaypoint, C_QuestLog.GetNextWaypointForMap, C_QuestLog.GetTitleForQuestID =
		savedQuestsOnMap, savedNextWp, savedNextWpMap, savedTitle
	Enum.UIMapType.Continent = savedContinent
	print("waypoint quest POI & arrow styles OK")
end)()

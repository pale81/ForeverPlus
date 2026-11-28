-- Damage meter reset modes
do
	local mr = ns:GetModule("MeterReset")
	local on = {}
	mr.ToggleEvent = function(_, event, enabled) on[event] = enabled end
	local resets = 0
	C_DamageMeter = { ResetAllCombatSessions = function() resets = resets + 1 end }
	assert(mr.db.mode == "never", "meter reset default")
	local function Check(mode, boss, mplus, combat)
		mr.db.mode = mode
		mr:Apply()
		assert(on.ENCOUNTER_START == boss and on.CHALLENGE_MODE_START == mplus and on.PLAYER_REGEN_DISABLED == combat, mode)
	end
	Check("never", false, false, false)
	Check("boss", true, false, false)
	Check("mplus", false, true, false)
	Check("bossMplus", true, true, false)
	Check("combat", false, false, true)
	mr.db.mode = "never"
	print("meter reset OK")
end
-- Library books
;(function()
	local Lib = ns:GetModule("Library")
	local seen, located = {}, 0
	for _, b in ipairs(ns.LibraryBooks) do
		seen[b[1]] = true
		if b[2] then
			located = located + 1
			assert(b[3] > 0 and b[3] < 100 and b[4] > 0 and b[4] < 100, "position in range " .. b[1])
		end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	assert(n == 40, "40 different books: " .. n)
	assert(located >= 30, "most books have a position")
	local source
	for _, candidate in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		if uv(candidate, "Positions") then source = candidate break end
	end
	assert(source, "library source on the world map")
	local oldSymbols, oldPrint, oldMenu = Lib.db.symbols, ns.PrintAlways, MenuUtil.CreateContextMenu
	local oldOwned, oldQuestDone = Lib.cdb.owned, C_QuestLog.IsQuestFlaggedCompleted
	Lib.db.symbols, Lib.cdb.owned = true, {}
	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	local list = {}
	ns.PrintAlways = function(line, ...) list[#list + 1] = line:format(...) end
	Lib.Command("")
	assert(list[1] == ns.L.LIBRARY_STATUS:format(0, 40) and #list == 41, "Rumi counts and appears once")
	local function Pins(mapID)
		local pins = {}
		source(mapID, function(_, _, pin) pins[#pins + 1] = pin end)
		return pins
	end
	assert(#Pins(1431) == 1 and #Pins(1423) == 3, "new Duskwood and Eastern Plaguelands pins")
	assert(#Pins(1432) == 2 and #Pins(1436) == 2, "both Rumi locations are shown")
	assert(#Pins(1444) == 0, "the old SoD location has no shipped pin")
	local blackrock = Pins(1428)
	assert(#blackrock == 1, "the two Blackrock books share a single pin")
	local tooltip = {}
	blackrock[1].tooltip({ AddLine = function(_, line) tooltip[line] = true end }, blackrock[1])
	assert(tooltip[ns.L.LIBRARY_STONEWROUGHT_HINT] and tooltip[ns.L.LIBRARY_MAGMA_HINT], "both directions are shown")
	local choices = {}
	MenuUtil.CreateContextMenu = function(owner, build)
		build(owner, { CreateTitle = function() end, CreateButton = function(_, _, callback, itemID)
			choices[itemID] = function() callback(itemID) end
		end })
	end
	blackrock[1].click(blackrock[1], "RightButton")
	assert(choices[220349] and choices[228133], "choose either book from the shared pin")
	choices[220349]()
	blackrock = Pins(1428)
	assert(#blackrock == 1 and Lib.cdb.owned[220349] and not Lib.cdb.owned[228133], "mark only the chosen book")
	blackrock[1].click(blackrock[1], "RightButton")
	assert(Lib.cdb.owned[228133] and #Pins(1428) == 0, "last book is directly marked and the shared pin disappears")
	Lib.cdb.owned, C_QuestLog.IsQuestFlaggedCompleted = oldOwned, oldQuestDone
	Lib.db.symbols, ns.PrintAlways, MenuUtil.CreateContextMenu = oldSymbols, oldPrint, oldMenu
	-- a book in the bags after login counts as collected and its find is remembered
	local id = ns.LibraryBooks[1][1]
	local inBags = false
	C_Item.GetItemCount = function(item) return inBags and item == id and 1 or 0 end
	C_Map.GetBestMapForUnit = function() return 1455 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.757, 0.105 end } end
	Lib.Scan()
	assert(not Lib.cdb.owned[id], "no book yet")
	inBags = true
	Lib.Scan()
	assert(Lib.cdb.owned[id], "collected once in the bags")
	local find = ns.db.libraryFinds[id]
	assert(find and find[1] == 1455 and math.abs(find[2] - 75.7) < 0.01, "find location remembered")
	local text = Lib.ExportText(ns.db.libraryFinds)
	assert(text:find("{ " .. id .. ", 1455, 75.7, 10.5 },", 1, true), "export line")
	Lib.cdb.owned[id], ns.db.libraryFinds[id] = nil, nil
	-- a book handed in before (its quest is done) counts without ever being in the bags
	inBags = false
	local handedIn
	for _, b in ipairs(ns.LibraryBooks) do if b[6] then handedIn = b break end end
	assert(handedIn, "hand-in quests known")
	C_QuestLog.IsQuestFlaggedCompleted = function(quest) return quest == handedIn[6] end
	Lib.Scan()
	assert(Lib.cdb.owned[handedIn[1]] and not ns.db.libraryFinds[handedIn[1]], "quest done: collected, no find recorded")
	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	Lib.cdb.owned[handedIn[1]] = nil
	print("library OK")
end)()
-- Shipped flight points and instance entrances
;(function()
	local P = assert(ns.Points, "Data/Points.lua loaded")
	local listed = {}
	assert(loadfile(root .. "/Data/Instances.lua"))("ForeverPlus", listed)
	local n, factions = 0, {}
	for node, f in pairs(P.flights) do
		n = n + 1
		factions[f[5]] = true
		assert(type(f[1]) == "string" and f[2] > 1000 and f[3] > 0 and f[3] < 100 and f[4] > 0 and f[4] < 100, "flight " .. node)
	end
	assert(n >= 60 and factions.A and factions.H, "flight points of both factions: " .. n)
	for id, row in pairs(P.entrances) do
		assert(listed.Instances[id], "entrance of a listed instance " .. id)
		assert(row[2] == "w" or row[2] == "m", "entrance kind " .. id)
	end
	assert(P.entrances[36] and P.entrances[36][2] == "w", "Deadmines entrance from the game table")
	print("points OK")
end)()
-- Innkeepers
;(function()
	local I = ns:GetModule("Innkeepers")
	assert(I.NpcID("Creature-0-4379-0-27-8931-00001F5C36") == 8931, "NPC ID from the GUID")
	assert(I.NpcID("Player-4379-00112233") == nil and I.NpcID(nil) == nil, "only creatures")
	UnitGUID = function() return "Creature-0-4379-0-27-8931-00001F5C36" end
	UnitName = function() return "Gastwirtin Heather" end
	UnitFactionGroup = function() return "Alliance" end
	C_Map.GetBestMapForUnit = function() return 1436 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5293, 0.5374 end } end
	ns.db.innkeepers = {}
	I.Record()
	local inn = ns.db.innkeepers[8931]
	assert(inn and inn[1] == "Gastwirtin Heather" and inn[2] == 1436 and inn[3] == 52.9 and inn[4] == 53.7 and inn[5] == "A", "innkeeper remembered")
	UnitFactionGroup = function() return "Horde" end
	I.Record()
	assert(ns.db.innkeepers[8931][5] == "N" and ns.db.innkeepers[8931][3] == 52.9, "met by both factions: neutral, first position kept")
	-- the gossip window with the binder option records without binding
	ns.db.innkeepers = {}
	UnitFactionGroup = function() return "Alliance" end
	C_GossipInfo = { GetOptions = function() return { { icon = 132060 } } end }
	I.OnGossipShow()
	assert(next(ns.db.innkeepers) == nil, "a vendor option is no innkeeper")
	C_GossipInfo = { GetOptions = function() return { { icon = 132060 }, { icon = 132052 } } end }
	I.OnGossipShow()
	assert(ns.db.innkeepers[8931] and ns.db.innkeepers[8931][5] == "A", "binder option recorded")
	UnitFactionGroup = function() return "Horde" end
	I.Record()
	local text = I.ExportText(ns.db.innkeepers)
	assert(text:find('{ 8931, 1436, 52.9, 53.7, "N", "Gastwirtin Heather" },', 1, true), "export line")
	ns.db.innkeepers = {}
	print("innkeepers OK")
end)()
-- Companion
;(function()
	local C = ns:GetModule("Companion")
	local dead, combat, resting = false, false, false
	UnitIsDeadOrGhost = function() return dead end
	UnitAffectingCombat = function() return combat end
	IsResting = function() return resting end
	assert(C.State() == "idle", "idle")
	resting = true
	assert(C.State() == "rest", "resting")
	combat = true
	assert(C.State() == "combat", "combat beats resting")
	dead = true
	assert(C.State() == "dead", "dead beats everything")
	dead, combat, resting = false, false, false
	C.db.enabled = true
	C:Apply()
	local after, pending = C_Timer.After, nil
	C_Timer.After = function(_, fn) pending = fn end
	C.React("levelUp")
	assert(C.State() == "levelUp", "a reaction shows until it ends")
	pending()
	assert(C.State() == "idle", "back to idle afterwards")
	C_Timer.After = after
	C.db.enabled = false
	C:Apply()
	print("companion OK")
end)()
-- Auction house: profit filter
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local prices = { [9001] = 100, [9002] = 50, [9003] = 0 }
	C_Item.GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[id] end
	local timers, refreshes, savedAfter = {}, {}, C_Timer.After
	C_Timer.After = function(delay, fn)
		local queue = delay >= 10 and timers or refreshes
		queue[#queue + 1] = fn
	end
	local function FlushRefreshes()
		while #refreshes > 0 do table.remove(refreshes, 1)() end
	end
	local uncached = { [9004] = true, [9005] = true }
	C_Item.IsItemDataCachedByID = function(id) return not uncached[id] end
	local requested = {}
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	local full, more = false, 0
	C_AuctionHouse = { HasFullBrowseResults = function() return full end, RequestMoreBrowseResults = function() more = more + 1 end }
	A.db.vendorBuyFilter = true
	A.db.vendorMinMargin = 0
	local function row(id, price, quantity) return { itemKey = { itemID = id }, minPrice = price, totalQuantity = quantity or 5 } end
	assert(F.Profitable(row(9001, 99)) and not F.Profitable(row(9001, 100)) and not F.Profitable(row(9001, 101)), "vendor price must be above the buy price")
	A.db.vendorMinMargin = 10
	assert(F.Profitable(row(9001, 90)) and not F.Profitable(row(9001, 91)), "at least 10 % below the merchant price")
	A.db.vendorMinMargin = 0
	assert(not F.Profitable(row(9003, 1)), "no merchant value, no profit")
	assert(not F.Profitable(row(9002, 10, 0)) and not F.Profitable({ isVirtualEntry = true }), "empty and virtual rows are left out")
	assert(F.Profitable(row(9004, 1)) == nil, "an unknown merchant price is neither yes nor no")
	-- the view onto a list, growing with the pages
	local provider
	local redraws = 0
	local scrollEnd = 0
	local frame = { browseResults = { row(9001, 10), row(9001, 500), row(9002, 20) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			ScrollBox = { GetDataIndexEnd = function() return scrollEnd end },
			SetDataProvider = function(_, started, entry, count, hasFull) provider = { started = started, entry = entry, count = count, hasFull = hasFull } end,
			RefreshScrollFrame = function() redraws = redraws + 1 end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	F.Apply()
	F.Provider(frame, true)
	assert(provider.count() == 2 and provider.entry(1) == frame.browseResults[1] and provider.entry(2) == frame.browseResults[3], "only profitable rows")
	frame.browseResults[#frame.browseResults + 1] = row(9001, 1)
	assert(provider.count() == 3, "added rows are judged on the way")
	-- a row whose item data is missing: asked for once, judged when it arrives, kept in its place
	frame.browseResults[#frame.browseResults + 1] = row(9005, 5)
	frame.browseResults[#frame.browseResults + 1] = row(9005, 6)
	frame.browseResults[#frame.browseResults + 1] = row(9001, 2)
	assert(provider.count() == 4, "pending rows are not shown")
	local asked = 0
	for _, id in ipairs(requested) do if id == 9005 then asked = asked + 1 end end
	assert(asked == 1, "item data asked once per item")
	prices[9005] = 20
	uncached[9005] = nil
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 9005)
	assert(provider.count() == 4, "late verdicts wait for the batched refresh")
	FlushRefreshes()
	assert(provider.count() == 6, "both rows of the item judged")
	local r = frame.browseResults
	assert(provider.entry(1) == r[4] and provider.entry(2) == r[7] and provider.entry(3) == r[1] and provider.entry(4) == r[3]
		and provider.entry(5) == r[5] and provider.entry(6) == r[6], "highest merchant profit first, late rows at their place")
	A.db.vendorProfitSort = false
	F.Apply()
	assert(provider.count() == 6 and provider.entry(1) == r[1] and provider.entry(2) == r[3] and provider.entry(3) == r[4]
		and provider.entry(6) == r[7], "without the profit sort Blizzard's order stays")
	A.db.vendorProfitSort = true
	-- many rows are judged in portions
	local big = {}
	for i = 1, 400 do big[i] = row(9001, i == 400 and 10 or 500) end
	frame.browseResults = big
	F.Apply() -- (a new search resets the view through the query hook)
	redraws = 0
	provider.count()
	local judged = F.State.judged
	assert(judged > 0 and judged < 400 and #refreshes == 1, "one portion, then a queued slice")
	provider.count(); F.Page(frame)
	assert(F.State.judged == judged, "provider and paging calls share the pending slice")
	full = true
	FlushRefreshes()
	assert(F.State.judged == 400 and provider.count() == 1 and redraws == 1, "only the slice with a new hit redraws")
	full = false
	big[400] = row(9001, 500)
	F.Apply()
	more, redraws = 0, 0
	FlushRefreshes()
	assert(provider.count() == 0 and more == 1 and redraws == 0, "an empty filtered page keeps paging without a redraw")
	frame.browseResults = { row(9001, 500) }
	more = 0
	F.Apply()
	assert(provider.count() == 0, "a new result table starts a new view")
	assert(provider.hasFull() == false, "searching while pages are missing")
	-- paging: asks while the view is short, one request per answer
	F.Page(frame)
	F.Page(frame)
	assert(more == 1, "one request until new rows arrive")
	frame.browseResults[#frame.browseResults + 1] = row(9001, 500)
	F.Page(frame)
	assert(more == 2, "next page after new rows")
	full = true
	F.Page(frame)
	assert(more == 2 and provider.hasFull() == true, "nothing more to ask for when the list is complete")
	full = false
	-- the search for hits is given up after a while: no spinner for ever
	F.Apply()
	frame.browseResults = { row(9001, 500) }
	provider.count()
	more, timers = 0, {}
	F.Page(frame)
	assert(more == 1 and #timers >= 1 and provider.hasFull() == false, "searching, timer set")
	for _, fn in ipairs(timers) do fn() end
	FlushRefreshes()
	assert(provider.hasFull() == true, "given up: the list says no results instead of searching")
	F.Page(frame)
	assert(more == 1, "no more pages by itself after giving up")
	C_Timer.After = savedAfter
	-- filter off: Blizzard's provider comes back
	local restored
	frame.ItemList.SetDataProvider = function(_, a, b, c, d) restored = { a, b, c, d } end
	F.Provider(frame, false)
	assert(restored and restored[3] and restored[3]() == 0, "original provider restored")
	A.db.vendorBuyFilter = false
	print("auction filter OK")
end)()
-- Auction house: buy list sorted by item rating
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedRating, savedAPI, savedAfter = ns.ItemLinkRating, C_AuctionHouse, C_Timer.After
	local savedCached, savedRequest = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	local refreshes = {}
	C_Timer.After = function(_, fn) refreshes[#refreshes + 1] = fn end
	-- item ID -> gain, block; nil = still loading
	local ratings = { [1] = { 5, "ok" }, [2] = { 9, "level" }, [3] = { -2 }, [4] = { 12, "no" }, [6] = { 3, "ok" } }
	ns.ItemLinkRating = function(link)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id == 5 then return false end
		local r = ratings[id]
		if not r then return nil end
		return r[1], r[2]
	end
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end,
		GetItemKeySampleLink = function(key) return "|Hitem:" .. key.itemID .. "|h" end }
	C_Item.IsItemDataCachedByID = function() return true end
	C_Item.RequestLoadItemDataByID = function() end
	local function row(id) return { itemKey = { itemID = id }, minPrice = 10, totalQuantity = 1 } end
	local provider
	local frame = { browseResults = { row(3), row(5), row(1), row(4), row(2), row(6), row(7) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, started, entry, count, hasFull) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.scoreValueSort = false, true, false
	F.Apply()
	local r = frame.browseResults
	local order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(table.concat(order, ",") == "1,6,2",
		"only upgrades, wearable ones by gain, then later ones; worse, no comparison and loading left out: " .. table.concat(order, ","))
	assert(A.GainText(5) == "+5.0" and select(2, A.GainText(5)) == true, "a gain shows green with its sign")
	local worse, better = A.GainText(-2)
	assert(worse == "-2.0" and better == false and A.GainText(nil) == nil, "a loss shows grey, no rating no label")
	-- the label in the name cell: shown for rated rows while there is room, never over the name
	local function fakeText(width)
		local fs = { text = "", shown = false, w = width }
		function fs:SetText(t) self.text = t end
		function fs:GetStringWidth() return self.w or #self.text * 6 end
		function fs:SetShown(v) self.shown = v end
		function fs:Hide() self.shown = false end
		function fs:SetPoint() end
		function fs:SetTextColor() end
		return fs
	end
	local made
	local function cell(rowData, nameWidth)
		return { rowData = rowData, Icon = { IsShown = function() return true end, GetWidth = function() return 14 end },
			Text = fakeText(nameWidth), GetWidth = function() return 200 end,
			CreateFontString = function() made = fakeText() return made end }
	end
	local savedUpgrade = ns.ItemLinkUpgradeState
	ns.ItemLinkUpgradeState = function() return false end
	local c = cell(r[3], 100)
	F.ItemCell(c, r[3].itemKey)
	assert(made and made.text == "+5.0" and made.shown, "the gain of a rated row is shown")
	made = nil
	F.ItemCell(cell(r[3], 170), r[3].itemKey)
	assert(made and not made.shown, "a long name keeps its room")
	made = nil
	F.ItemCell(cell(r[2], 100), r[2].itemKey)
	assert(made == nil, "no label without a comparison")
	ns.ItemLinkUpgradeState = savedUpgrade
	-- a short list asks for the next page by itself
	local full, more = false, 0
	C_AuctionHouse.HasFullBrowseResults = function() return full end
	C_AuctionHouse.RequestMoreBrowseResults = function() more = more + 1 end
	F.Apply()
	provider.count()
	assert(more == 1, "a short list asks for the next page by itself")
	assert(A.FilterStatusText(2, 0, false, true) == ns.L.AUCTION_FILTER_STATUS_OTHER:format(2, 20, 10), "status line without profit wording")
	ratings[7] = { 8, "ok" }
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 7)
	while #refreshes > 0 do table.remove(refreshes, 1)() end
	assert(provider.count() == 4 and provider.entry(1) == r[7] and provider.entry(2) == r[3], "a late upgrade joins at its place")
	-- value: gain per gold of the cheapest offer, within the groups (5 for 4 g, 3 for 1 g, 8 for 2 g, later 9 for 1 c)
	ratings[1], ratings[6], ratings[7], ratings[2] = { 5, "ok" }, { 3, "ok" }, { 8, "ok" }, { 9, "level" }
	r[3].minPrice, r[6].minPrice, r[7].minPrice, r[5].minPrice = 40000, 10000, 20000, 1
	A.ClearOwnFilters()
	A.db.scoreValueSort = true
	A:OnOptionChanged("scoreValueSort")
	assert(not A.db.scoreSort, "value and upgrades exclude each other")
	order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(table.concat(order, ",") == "7,6,1,2", "most gain per gold first, later upgrades after: " .. table.concat(order, ","))
	A.db.scoreSort = true
	A:OnOptionChanged("scoreSort")
	assert(not A.db.scoreValueSort, "upgrades switch value off")
	A.db.scoreSort, A.db.scoreValueSort = false, true
	assert(A.GainText(3, 12) == "+3.0 · 12/g" and A.GainText(3, 0.5) == "+3.0 · 0.5/g", "gain and rating per gold in the row")
	A.db.scoreValueSort = false
	assert(A.GainText(3, 12) == "+3.0", "without the value sort only the gain")
	-- the order holds when rows arrive in pages and their item data later, in both modes (seen wrong in game)
	local gains = { 6.1, 4.5, 9.5, 5.6, 5.1, 0.4, 12.0, 7.3 }
	local costs = { 549, 600, 1200, 900, 899, 50, 75000, 2000 }
	for _, value in ipairs({ false, true }) do
		A.db.scoreSort, A.db.scoreValueSort = not value, value
		ratings = {}
		frame.browseResults = {}
		F.Apply()
		for id = 11, 14 do frame.browseResults[#frame.browseResults + 1] = { itemKey = { itemID = id }, minPrice = costs[id - 10] * 100, totalQuantity = 1 } end
		ratings[12], ratings[13] = { gains[2], "ok" }, { gains[3], "ok" }
		provider.count()
		for id = 15, 18 do frame.browseResults[#frame.browseResults + 1] = { itemKey = { itemID = id }, minPrice = costs[id - 10] * 100, totalQuantity = 1 } end
		provider.count()
		for id = 11, 18 do
			ratings[id] = { gains[id - 10], "ok" }
			F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", id)
			while #refreshes > 0 do table.remove(refreshes, 1)() end
		end
		local last
		for i = 1, provider.count() do
			local key = provider.entry(i).itemKey.itemID - 10
			local measure = value and gains[key] / costs[key] or gains[key]
			assert(not last or measure <= last, (value and "value" or "upgrades") .. ": row " .. i .. " out of order")
			last = measure
		end
		assert(provider.count() == 8, "all upgrades shown")
	end
	ratings = {}
	A.ClearOwnFilters()
	ns.ItemLinkRating, C_AuctionHouse, C_Timer.After = savedRating, savedAPI, savedAfter
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = savedCached, savedRequest
	print("auction rating sort OK")
end)()
-- Auction house: the work of a refresh is spread over frames
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedRating, savedAPI, savedAfter, savedClock = ns.ItemLinkRating, C_AuctionHouse, C_Timer.After, debugprofilestop
	local savedCached = C_Item.IsItemDataCachedByID
	local queue, clock, ratings, redraws = {}, 0, {}, 0
	C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
	local function Tick() table.remove(queue, 1)() end
	debugprofilestop = function() return clock end
	-- every rating costs 0.3 ms of the 0.5 ms slice
	ns.ItemLinkRating = function(link)
		clock = clock + 0.3
		local r = ratings[tonumber(link:match("item:(%d+)"))]
		if not r then return nil end
		return r[1], r[2]
	end
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end,
		GetItemKeySampleLink = function(key) return "|Hitem:" .. key.itemID .. "|h" end }
	C_Item.IsItemDataCachedByID = function() return true end
	local rows, provider = {}, nil
	for i = 1, 10 do rows[i] = { itemKey = { itemID = i }, minPrice = 10, totalQuantity = 1 } end
	local frame = { browseResults = rows, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, _, entry, count) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() redraws = redraws + 1 end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.scoreValueSort, A.db.hideVendorItems = false, true, false, false
	F.Apply()
	provider.count()
	while #queue > 0 do Tick() end
	-- "Upgrades" shows only rated upgrades: rows still waiting for item data are not shown yet
	assert(provider.count() == 0 and #F.State.loading == 10, "all rows judged, all waiting for item data")
	for i = 1, 10 do ratings[i] = { i, "ok" } end
	redraws = 0
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 1)
	Tick()
	assert(#F.State.loading == 8, "rating again stops at the slice budget: " .. #F.State.loading)
	assert(redraws == 0, "the slice that changed the view does not redraw in the same frame")
	Tick()
	assert(redraws == 1, "Blizzard's list is redrawn on the next frame")
	while #queue > 0 do Tick() end
	local order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(#F.State.loading == 0 and table.concat(order, ",") == "10,9,8,7,6,5,4,3,2,1",
		"all rated in later slices and at their place: " .. table.concat(order, ","))
	A.db.scoreSort = false
	F.Apply()
	ns.ItemLinkRating, C_AuctionHouse, C_Timer.After, debugprofilestop = savedRating, savedAPI, savedAfter, savedClock
	C_Item.IsItemDataCachedByID = savedCached
	print("auction refresh slices OK")
end)()
-- Auction house: merchant goods hidden from the buy list
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedAPI, savedCdb = C_AuctionHouse, A.cdb
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end }
	A.cdb = { vendorBuyPrices = { [424242] = 5 } }
	assert(A.IsMerchantGood(159) and A.IsMerchantGood(424242) and not A.IsMerchantGood(424243) and not A.IsMerchantGood(nil),
		"bundled list and own merchant visits")
	assert(A.IsMerchantGood(728) and A.IsMerchantGood(2697), "recipes of the recipe vendors (Westfall Stew, Goretusk Liver Pie)")
	local function row(id) return { itemKey = { itemID = id }, minPrice = 10, totalQuantity = 1 } end
	local provider
	local frame = { browseResults = { row(424243), row(159), row(424242), row(424244) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, _, entry, count) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.hideVendorItems = false, false, true
	F.Apply()
	local r = frame.browseResults
	assert(provider.count() == 2 and provider.entry(1) == r[1] and provider.entry(2) == r[4], "merchant goods left out, order kept")
	-- the first search after opening showed Blizzard's own list: a view that is on but not in place is put back
	local blizzardCount = function() return #frame.browseResults end
	frame.ItemList.getNumEntries = blizzardCount
	provider = nil
	F.Ensure(frame)
	assert(provider and provider.count() == 2, "the filtered view is put back in place")
	local own = provider
	provider = nil
	frame.ItemList.getNumEntries = own.count
	F.Ensure(frame)
	assert(provider == nil, "a view in place is left alone")
	-- Blizzard's clear button (the X) shows while an own filter is on and clears the own filters too
	local shown = false
	AuctionHouseFrame.SearchBar = { FilterButton = { ClearFiltersButton = { Show = function() shown = true end } } }
	A:OnOptionChanged("hideVendorItems")
	assert(shown and A.OwnFiltersOn(), "the X shows for an own filter")
	A.db.scoreSort = true
	A.ClearOwnFilters()
	assert(not A.OwnFiltersOn() and not A.db.hideVendorItems and not A.db.scoreSort, "the X clears the own filters")
	shown = false
	A:OnOptionChanged("hideVendorItems")
	assert(not shown, "no own filter, the X is Blizzard's alone")
	AuctionHouseFrame.SearchBar = nil
	A.db.hideVendorItems = false
	F.Apply()
	C_AuctionHouse, A.cdb = savedAPI, savedCdb
	print("auction merchant goods OK")
end)()
-- Auction house: quick buy plan
;(function()
	local A = ns:GetModule("Auction")
	local function row(price, quantity) return { itemKey = { itemID = 9001 }, minPrice = price, totalQuantity = quantity } end
	local id, count, unit, total = A.QuickBuyPlan(row(40, 10), 3)
	assert(id == 9001 and count == 3 and unit == 40 and total == 120, "quantity times the minimum price")
	assert(select(2, A.QuickBuyPlan(row(40, 2), 5)) == 2, "never more than offered")
	assert(select(2, A.QuickBuyPlan(row(40, 9), nil)) == 1 and select(2, A.QuickBuyPlan(row(40, 9), 0)) == 1, "at least one")
	assert(A.QuickBuyPlan(row(40, 0), 1) == nil and A.QuickBuyPlan(row(0, 5), 1) == nil, "no offer, no price: no plan")
	assert(A.QuickBuyPlan({ isVirtualEntry = true, minPrice = 5, totalQuantity = 5 }, 1) == nil, "virtual rows have no plan")
	assert(A.QuickBuyPlan({ minPrice = 5, totalQuantity = 5 }, 1) == nil and A.QuickBuyPlan(nil, 1) == nil, "no item, no plan")
	print("auction quick buy OK")
end)()
-- Bag sorting on open: one sort at a time, none while items are locked
;(function()
	local items = ns:GetModule("Items")
	local SortOnOpen = uv(uv(items.OnLogin, "QueueSort"), "SortOnOpen")
	local OnBagLayoutChanged = uv(items.OnLogin, "OnBagLayoutChanged")
	assert(SortOnOpen, "sort function")
	local saved = { C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo }
	local sorts, locked, now, ticker, itemId, slotReads = 0, false, 100, nil, 1, 0
	C_Container.SortBags = function() sorts = sorts + 1 end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot)
		slotReads = slotReads + 1
		return bag == 0 and slot == 1 and { isLocked = locked, itemID = itemId, stackCount = 1 } or nil
	end
	C_Timer.NewTicker = function(_, fn) ticker = { fn = fn, Cancel = function(self) self.dead = true end } return ticker end
	GetTime = function() return now end
	InCombatLockdown = function() return false end
	GetCursorInfo = function() return nil end
	items.db.autoSort = true
	for _, name in ipairs({ "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame", "ScrappingMachineFrame", "ItemSocketingFrame" }) do
		_G[name] = false
	end
	setuv(SortOnOpen, "sellTicker", nil)
	SortOnOpen()
	assert(sorts == 1 and ticker, "first sort runs and is watched")
	now = 110
	SortOnOpen()
	assert(sorts == 1, "no second sort while the first is watched")
	locked = true
	slotReads = 0
	ticker.fn(ticker); ticker.fn(ticker); ticker.fn(ticker)
	assert(not ticker.dead and slotReads == 2, "still running while locked, with one read for unchanged slots")
	locked = false
	now = 120
	SortOnOpen()
	assert(sorts == 1, "no sort before the bags were quiet")
	ticker.fn(ticker); ticker.fn(ticker)
	assert(ticker.dead, "over after two quiet looks")
	now = 125
	locked = true
	OnBagLayoutChanged(nil, nil, 0)
	SortOnOpen()
	assert(sorts == 1, "no sort while an item is locked")
	locked = false
	MerchantFrame = { IsShown = function() return true end }
	SortOnOpen()
	assert(sorts == 1, "no sort at a merchant")
	MerchantFrame = false
	now = 130
	slotReads = 0
	SortOnOpen()
	assert(sorts == 1, "no new sort while the sorted bags are unchanged (the junk must not jump to and fro)")
	assert(slotReads == 2, "locks and the unchanged layout are checked in a single slot pass")
	slotReads = 0
	SortOnOpen()
	assert(slotReads == 0, "the confirmed layout is reused until a bag event arrives")
	itemId = 2
	OnBagLayoutChanged(nil, nil, 0)
	local savedAfter, pending = C_Timer.After
	C_Timer.After = function(_, fn) pending = fn end
	SortOnOpen()
	assert(pending and sorts == 1, "the game sort runs after the inspection frame")
	OnBagLayoutChanged(nil, nil, 0)
	pending()
	assert(sorts == 1, "a bag change between inspection and execution cancels the stale sort")
	C_Timer.After = savedAfter
	SortOnOpen()
	assert(sorts == 2, "next sort afterwards")
	items.db.autoSort = false
	C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo = unpack(saved, 1, 7)
	print("bag sort OK")
end)()
;(function()
	-- Place texts: every name token resolves (the client's name or the English fallback), every key is a known place.
	local data = {}
	assert(loadfile("../Data/Places.lua"))("ForeverPlus", data)
	local keepPlaces = ns.Places
	ns.Places = data.Places
	local known = {}
	for _, place in ipairs(ns.Places) do known[place[4]] = true end
	local function Check(list, isInstance)
		for key, info in pairs(list) do
			assert(isInstance or known[key], "place of the text " .. tostring(key))
			for _, text in ipairs({ info.de, info.en }) do
				assert(not ns.PlaceText(text):find("%?") and not ns.PlaceText(text):find("{"), "names resolve in " .. tostring(key) .. ": " .. ns.PlaceText(text))
			end
		end
	end
	Check(ns.PlaceInfo, false)
	Check(ns.InstanceInfo, true)
	Check(ns.AreaInfo, true)
	local keepZone = GetRealZoneText
	GetRealZoneText = function() end
	assert(ns.PlaceText("in {m1431} / {a42} / {i36}") == "in Duskwood / Darkshire / The Deadmines", "english fallback names: " .. ns.PlaceText("in {m1431} / {a42} / {i36}"))
	GetRealZoneText = keepZone
	local saved = C_Map.GetMapInfo
	C_Map.GetMapInfo = function() return { name = "Dämmerwald" } end
	assert(ns.PlaceText("{m1431}") == "Dämmerwald", "the client's name wins")
	C_Map.GetMapInfo = saved
	ns.Places = keepPlaces
	print("place texts OK")
end)()

-- Nameplate quest marker: creatures whose drop a quest asks for
;(function()
	local quests = ns:GetModule("Quests")
	local plate = { IsForbidden = function() return false end, UnitFrame = {} }
	local isQuestUnit = uv(uv(quests.RefreshNameplates, "UpdateNameplate"), "IsQuestUnit")
	assert(isQuestUnit, "quest unit check")
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
	UnitIsPlayer = function() return false end
	UnitCanAttack = function() return true end
	Enum.TooltipDataLineType = { QuestObjective = 8 }
	C_TooltipInfo.GetUnit = function() return { lines = { { type = 8, leftText = "Klippeneberrippchen: 2/6" } } } end
	assert(isQuestUnit("nameplate1"), "found by the tooltip objective")
	C_TooltipInfo.GetUnit = function() return { lines = { { type = 0, leftText = "Wildtier" } } } end
	assert(not isQuestUnit("nameplate1"), "no objective, no marker")
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	assert(isQuestUnit("nameplate1"), "the game's flag still counts")
	UnitIsPlayer = function() return true end
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
	assert(not isQuestUnit("nameplate1"), "players are never quest units")
	print("nameplate quest marker OK", plate ~= nil)
end)()
-- Quest symbols share the nameplate rules in the unit tooltip and above the cursor.
;(function()
	local tip, quests = ns:GetModule("Tooltip"), ns:GetModule("Quests")
	local handler = uv(tip.OnInitialize, "OnUnitTooltip")
	local withIcon = uv(handler, "WithQuestIcon")
	local saved = { C_QuestLog, C_TooltipInfo, UnitIsPlayer, UnitCanAttack, UnitGUID, UnitName, UnitIsUnit,
		GameTooltip.GetUnit, GameTooltip.IsForbidden, GameTooltipTextLeft1, issecretvalue, ns.QuestData }
	local savedOptions = { tip.db.questIcon, quests.db.nameplateIcons, quests.db.dropObjectives }
	local sources = ns:GetModule("LootSources")
	local savedDrops = sources.DropsFrom
	local state = uv(uv(quests.IsQuestUnit, "DropObjectives"), "state")
	local related, player, scans = false, false, 0
	local data = { lines = { { type = Enum.TooltipDataLineType.QuestObjective, leftText = "Rippchen: 2/6" } } }
	C_QuestLog = { UnitIsRelatedToActiveQuest = function() return related end,
		GetQuestObjectives = function() return { { text = "Rippchen: 2/6", numFulfilled = 2, numRequired = 6, finished = false } } end,
		GetTitleForQuestID = function() return "Rippchen sammeln" end }
	C_TooltipInfo = { GetUnit = function() scans = scans + 1 return data end }
	UnitIsPlayer = function() return player end
	UnitCanAttack = function() return true end
	UnitGUID = function() return "Creature-0-0-0-0-123-0000000001" end
	UnitName = function() return "Klippeneber" end
	UnitIsUnit = function() return false end
	GameTooltip.GetUnit = function() return "Klippeneber", "mouseover" end
	GameTooltip.IsForbidden = function() return false end
	local text = "Klippeneber"
	GameTooltipTextLeft1 = { GetText = function() return text end, SetText = function(_, value) text = value end,
		GetTextColor = function() return 0.2, 0.6, 1 end }
	assert(tip.db.questIcon == true, "quest symbol is enabled by default")
	quests.db.nameplateIcons = false
	local marked = quests.unitIconPrefix .. "Klippeneber"
	assert(withIcon("Klippeneber", "mouseover", data) == marked and scans == 0,
		"tooltip objectives are reused even with nameplate symbols off")
	handler(GameTooltip, data)
	assert(text == marked, "quest symbol precedes the tooltip name")
	handler(GameTooltip, data)
	assert(text == marked, "tooltip updates do not duplicate the symbol")
	data.lines[1].leftText = "Rippchen: 6/6"
	related = true
	handler(GameTooltip, data)
	assert(text == "Klippeneber", "completed objectives remove the symbol despite the game's quest flag")
	data.lines[1].leftText = "Rippchen: 2/6"
	local showName = uv(tip.OnLogin, "ShowHoverName")
	local frame = uv(showName, "GetHover")()
	local savedSetText = frame.Name.SetText
	local hoverText
	frame.Name.SetText = function(_, value) hoverText = value end
	uv(showName, "Layout")(frame, data)
	assert(hoverText == marked, "same symbol precedes the name above the cursor")
	frame:Show()
	frame.object = false
	UnitIsUnit = function() return true end
	data.lines[1].leftText = "Rippchen: 6/6"
	handler(GameTooltip, data)
	assert(hoverText == "Klippeneber", "tooltip completion also updates the visible cursor name")
	data.lines[1].leftText = "Rippchen: 2/6"
	handler(GameTooltip, data)
	assert(hoverText == marked, "tooltip updates restore the cursor symbol for open objectives")
	tip.db.questIcon = false
	tip:OnOptionChanged("questIcon")
	assert(hoverText == "Klippeneber", "disabling immediately updates the visible cursor name")
	handler(GameTooltip, data)
	assert(text == "Klippeneber" and withIcon(marked, "mouseover", data) == "Klippeneber", "disabled symbol is removed")
	tip.db.questIcon = true
	related = false
	player = true
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "players get no quest symbol")
	player = false
	issecretvalue = function(value) return value == "secret-name" or value == "secret-unit" end
	assert(withIcon("secret-name", "mouseover", data) == "secret-name", "restricted names stay untouched")
	assert(withIcon("Klippeneber", "secret-unit", data) == "Klippeneber", "restricted unit tokens are not queried")
	assert(withIcon("Klippeneber", nil, data) == "Klippeneber", "missing unit tokens get no symbol")
	data = { lines = {} }
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "unrelated creatures get no symbol")
	ns.QuestData = { targets = { [999999] = { { "i", 999998 } } } }
	state[999999] = {}
	sources.DropsFrom = function(itemID, key) return itemID == 999998 and key == "npc:123" end
	quests.db.dropObjectives = true
	assert(withIcon("Klippeneber", "mouseover", data) == marked, "recorded quest drops use the shared marker rules")
	quests.db.dropObjectives = false
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "recorded drops respect their own option")
	GameTooltip.IsForbidden = function() return true end
	handler(GameTooltip, data)
	assert(text == "Klippeneber", "forbidden tooltips stay untouched")
	state[999999] = nil
	frame.Name.SetText = savedSetText
	sources.DropsFrom = savedDrops
	C_QuestLog, C_TooltipInfo, UnitIsPlayer, UnitCanAttack, UnitGUID, UnitName, UnitIsUnit,
		GameTooltip.GetUnit, GameTooltip.IsForbidden, GameTooltipTextLeft1, issecretvalue, ns.QuestData = unpack(saved, 1, 12)
	tip.db.questIcon, quests.db.nameplateIcons, quests.db.dropObjectives = unpack(savedOptions)
	print("quest symbols in tooltip and cursor name OK")
end)()
-- A native quest objective does not hide another open objective from the same creature's loot.
;(function()
	local quests = ns:GetModule("Quests")
	local handler = uv(quests.OnInitialize, "OnUnitTooltip")
	local state = uv(uv(handler, "DropObjectives"), "state")
	local questCall, lootCall
	for index, callback in ipairs(TEST_POSTCALLS) do
		local fn = uv(callback, "fn")
		if fn == handler then questCall = index end
		if fn and uv(fn, "MouseoverCreatureKey") then lootCall = index end
	end
	assert(questCall and lootCall and questCall < lootCall, "missing objectives precede the observed loot section")
	local savedLog, savedTypes, savedOption = C_QuestLog, Enum.TooltipDataLineType, quests.db.dropObjectives
	local savedAddLine, savedNumLines = GameTooltip.AddLine, GameTooltip.NumLines
	local questID = 92909
	local title, spring, stabilizer = "Die Ernter ernten", "Golemisofeder: 1/14", "Gyrostabilisator für Erntearbeiter: 5/5"
	local oldState = state[questID]
	quests.db.dropObjectives = true
	state[questID] = {}
	C_QuestLog = {
		GetQuestObjectives = function(id)
			if id == questID then
				return { { text = spring, numFulfilled = 1, numRequired = 14, finished = false },
					{ text = stabilizer, numFulfilled = 5, numRequired = 5, finished = true } }
			end
		end,
		GetTitleForQuestID = function() return title end,
	}
	local types = { QuestTitle = 17, QuestObjective = 8 }
	Enum.TooltipDataLineType = types
	local data = { guid = "Creature-0-0-0-0-114-0000000001", lines = {
		{ type = types.QuestTitle, id = questID, leftText = title, lineIndex = 4 },
		{ type = types.QuestObjective, leftText = stabilizer, completed = true, lineIndex = 5 },
	} }
	local added, numLines = {}, 5
	GameTooltip.AddLine = function(_, text) added[#added + 1] = text end
	GameTooltip.NumLines = function() return numLines end
	handler(GameTooltip, data)
	assert(#added == 1 and added[1] == "- " .. spring, "only the missing open drop follows the native quest block")
	added, numLines = {}, 6
	data.lines[3] = { type = types.QuestObjective, leftText = " |cffffffff- " .. spring .. "|r ", lineIndex = 6 }
	handler(GameTooltip, data)
	assert(#added == 0, "an already displayed objective is not duplicated")
	data.lines[3] = { type = types.QuestTitle, id = questID + 1, leftText = "Andere Quest", lineIndex = 6 }
	handler(GameTooltip, data)
	assert(#added == 2 and added[1] == title and added[2] == "- " .. spring, "a different trailing quest keeps its own heading")
	added, numLines, data.lines = {}, 3, {}
	handler(GameTooltip, data)
	assert(#added == 2 and added[1] == title and added[2] == "- " .. spring, "the recorded drop is also shown on its own")
	added = {}
	quests.db.dropObjectives = false
	handler(GameTooltip, data)
	assert(#added == 0, "the tooltip respects the recorded drop option")
	state[questID] = oldState
	C_QuestLog, Enum.TooltipDataLineType, quests.db.dropObjectives = savedLog, savedTypes, savedOption
	GameTooltip.AddLine, GameTooltip.NumLines = savedAddLine, savedNumLines
	print("missing quest objectives in unit tooltip OK")
end)()
-- Speech bubbles
;(function()
	local sb = ns:GetModule("SpeechBubbles")
	local saved = { UnitExists, UnitGUID, C_NamePlate, sb.db.fallback }
	local guid = { npc = "Creature-NPC", nameplate1 = "Creature-NPC" }
	local plate, playerPlate = CreateFrame("Frame"), CreateFrame("Frame")
	local plates = { npc = plate, nameplate1 = plate }
	UnitExists = function(unit) return guid[unit] ~= nil end
	UnitGUID = function(unit) return guid[unit] end
	C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }
	sb.db.fallback = true
	sb.Show("Willkommen, Reisender.")
	local bubble = uv(sb.Show, "speechBubble")
	local anchored
	bubble.SetPoint = function(_, _, to) anchored = to end
	sb.Show("Willkommen, Reisender.")
	assert(bubble:IsShown() and anchored == plate and bubble.Tail:IsShown(), "speech starts on the NPC's plate")
	guid.target, plates.npc = "Player-Other", playerPlate
	local watch = bubble:GetScript("OnUpdate")
	watch()
	assert(anchored == plate, "speech stays with the NPC when targeting a player")
	uv(sb.Apply, "OnPlateRemoved")(nil, nil, "nameplate1")
	watch()
	assert(anchored == UIParent and not bubble.Tail:IsShown(), "speech leaves a removed plate immediately")
	guid.nameplate1 = "Player-Other"
	uv(sb.Apply, "OnPlateAdded")(nil, nil, "nameplate1")
	assert(anchored == UIParent, "speech ignores the player on the recycled plate")
	guid.nameplate2, plates.nameplate2 = "Creature-NPC", plate
	uv(sb.Apply, "OnPlateAdded")(nil, nil, "nameplate2")
	assert(anchored == plate and bubble.Tail:IsShown(), "speech returns to the NPC")
	sb.Hide()
	sb.db.fallback = false
	sb.Show("Kein Platz am Bildschirm.")
	guid.nameplate2 = "Player-Other"
	watch()
	assert(not bubble:IsShown(), "speech hides when the NPC loses its plate and fallback is off")
	sb.Hide()
	bubble.SetPoint = nil
	UnitExists, UnitGUID, C_NamePlate, sb.db.fallback = unpack(saved, 1, 4)
	print("speech bubbles OK")
end)()
-- Diagnosis report
;(function()
	local dc = ns:GetModule("DataCapture")
	local text = dc.DiagnoseText()
	local errors = ns.L.DIAG_ERRORS:match("^(.-)%%d")
	assert(text:find("== ForeverPlus ==", 1, true) and text:find("== " .. errors, 1, true)
		and text:find("== " .. ns.L.DIAG_STATUS .. " ==", 1, true), "report sections")
	assert(text:find("== " .. ns.L.DIAG_CHANGED_OPTIONS .. " ==", 1, true), "options section")
	print("diagnose OK")
end)()

-- Loot sources
(function()
	local S = ns:GetModule("LootSources")
	assert(S.SourceKey("Creature-0-4379-0-27-8931-00001F5C36") == "npc:8931", "corpse key")
	assert(S.SourceKey("GameObject-0-4379-0-27-2061-00001F5C36") == "object:2061", "node key")
	assert(S.SourceKey("Item-4379-0-400000001") == nil and S.SourceKey(nil) == nil, "containers and nothing are left out")
	ns.db.lootSources = {}
	S.count, S.merged = 0, nil
	S.Record("g1", "npc:777", { 100, 101 }, "Test Wolf")
	S.Record("g2", "npc:777", { 100 }, nil)
	local e = ns.db.lootSources["npc:777"]
	assert(e.windows == 2 and e.items[100] == 2 and e.items[101] == 1 and e.name == "Test Wolf", "windows and drops counted")
	assert(S.DropsFrom(100, "npc:777") and not S.DropsFrom(100, "npc:778") and not S.DropsFrom(99999999, "npc:777"), "drop lookup by source")
	local sources = S.Sources(100)
	assert(#sources >= 1 and sources[1].key == "npc:777" and sources[1].drops == 2 and sources[1].windows == 2, "own data in the lookup")
	-- shipped data and own windows add up
	local key, row
	for item, rows in pairs(ns.LootData.items) do key, row = item, rows[1] break end
	S.Record("g3", row[1], { key }, nil)
	local merged
	for _, s in ipairs(S.Sources(key)) do if s.key == row[1] then merged = s end end
	assert(merged and merged.drops == row[2] + 1 and merged.windows == row[3] + 1, "shipped and own windows add up")
	local text = S.ExportText(ns.db.lootSources)
	assert(text:find('{ "npc:777", "Test Wolf", 2, { [100] = 2, [101] = 1 } },', 1, true), "export line")
	ns.db.lootSources = {}
	S.count, S.merged = 0, nil
	-- names: unknown ones get the number, learned ones the client name
	local savedNames, savedGUID, savedUnitName = ns.LootData.names, UnitGUID, UnitName
	ns.LootData.names = { ["npc:8931"] = "?", ["npc:5"] = "Wolf" }
	ns.db.lootNames, S.nameCount = {}, 0
	assert(S.SourceName("npc:8931") == "Kreatur 8931" or S.SourceName("npc:8931") == "Creature 8931", "unknown name shows the number")
	assert(S.SourceName("npc:5") == "Wolf", "shipped name")
	UnitGUID, UnitName = function() return "Creature-0-4379-0-27-8931-00001F5C36" end, function() return "Zottel" end
	S.LearnName("mouseover")
	assert(S.SourceName("npc:8931") == "Zottel", "learned name replaces the number")
	UnitGUID = function() return "Creature-0-4379-0-27-999-00001F5C36" end
	S.LearnName("mouseover")
	assert(ns.db.lootNames["npc:999"] == nil, "units without a loot source are not stored")
	UnitGUID, UnitName, ns.LootData.names = savedGUID, savedUnitName, savedNames
	ns.db.lootNames, S.nameCount = {}, 0
	-- /fp daten export collects every recording
	ns.db.innkeepers = { [1] = { "Wirt", 1436, 10, 20, "A" } }
	local DC = ns:GetModule("DataCapture")
	local all = DC.ExportText()
	assert(all and all:find('{ 1, 1436, 10.0, 20.0, "A", "Wirt" },', 1, true), "combined export holds the innkeepers")
	assert(all:find("^%-%- @fp%-export 1 build=") and all:find("-- @fp inns", 1, true) and all:find("issues/new", 1, true), "export header and section tag")
	ns.db.innkeepers = {}
	print("loot sources OK")
end)()
;(function()
	local loot, items = ns:GetModule("LootSources"), ns:GetModule("Items")
	local savedSources, savedCount, savedMerged = ns.db.lootSources, loot.count, loot.merged
	local savedRecord, savedFastLoot, savedToggle = loot.db.record, items.db.fastLoot, loot.ToggleEvent
	local savedNum, savedType, savedLink, savedSource = GetNumLootItems, GetLootSlotType, GetLootSlotLink, GetLootSourceInfo
	local savedFishing, savedSlot, savedCVar, savedClick = IsFishingLoot, LootSlot, GetCVarBool, IsModifiedClick
	local savedGUID, savedName, savedSecret = UnitGUID, UnitName, issecretvalue
	local observations = ns:GetModule("Observations")
	local savedCreature, observed = observations.Creature, 0
	observations.Creature = function() observed = observed + 1 end
	ns.db.lootSources, loot.count, loot.merged = {}, 0, nil
	loot.db.record, items.db.fastLoot = true, true
	local handlers = {}
	loot.ToggleEvent = function(_, event, _, fn) handlers[event] = fn end
	loot:Apply()
	loot.ToggleEvent = savedToggle
	local first = "Creature-0-1-2-3-999981-0001"
	local second = "Creature-0-1-2-3-999981-0002"
	local third = "Creature-0-1-2-3-999982-0001"
	local key = "npc:999981"
	local window = { { 1, "item:35", first, 2, second, 1 }, { 1, "item:35", first, 1 }, { 2, nil, second, 15 } }
	GetNumLootItems = function() return #window end
	GetLootSlotType = function(i) return window[i][1] end
	GetLootSlotLink = function(i) return window[i][2] end
	GetLootSourceInfo = function(i)
		local slot = window[i]
		return unpack(slot, 3, slot[5] and 6 or 4)
	end
	IsFishingLoot = function() return false end
	GetCVarBool = function() return true end
	IsModifiedClick = function() return false end
	UnitGUID = function(unit) return unit == "mouseover" and first end
	UnitName = function() return "Wolf" end
	issecretvalue = function(v) return v == "secret" end
	LootSlot = function(i)
		assert(ns.db.lootSources[key] and ns.db.lootSources[key].windows == 2, "fast loot records every corpse before looting")
		table.remove(window, i)
	end
	items:LOOT_READY()
	local entry = ns.db.lootSources[key]
	assert(#window == 0 and entry.items[35] == 2 and entry.name == "Wolf" and observed == 2,
		"shared and duplicate item slots count once per corpse")
	handlers.LOOT_OPENED()
	window = { { 1, "item:35", first, 1 } }
	handlers.LOOT_OPENED()
	assert(entry.windows == 2, "reopening the same corpse and overlapping loot events do not double count")
	items.db.fastLoot = false
	window = { { 1, "secret", third, 1 } }
	handlers.LOOT_READY()
	window = { { 1, "item:25", third, 1 } }
	assert(not ns.db.lootSources["npc:999982"], "a protected item leaves the snapshot available to retry")
	handlers.UNIT_SPELLCAST_SENT(nil, nil, "player", nil, "skinning", 8613)
	handlers.LOOT_READY()
	assert(not ns.db.lootSources["npc:999982"], "skinning does not count as corpse loot")
	handlers.UNIT_SPELLCAST_INTERRUPTED(nil, nil, "player", "skinning")
	handlers.LOOT_OPENED(nil, nil, false, true)
	assert(not ns.db.lootSources["npc:999982"], "opening a bag item does not record a corpse")
	handlers.LOOT_OPENED()
	assert(ns.db.lootSources["npc:999982"].items[25] == 1, "manual opening retries once loot is readable")
	window = { { 2, nil, "Creature-0-1-2-3-999982-0002", 40 } }
	handlers.LOOT_READY()
	assert(ns.db.lootSources["npc:999982"].windows == 2, "a money-only corpse counts toward the number of windows")
	loot.db.record = false
	window = { { 1, "item:25", "Creature-0-1-2-3-999983-0001", 1 } }
	loot.CaptureWindow()
	assert(not ns.db.lootSources["npc:999983"], "recording off leaves the saved data alone")
	assert(ns:GetModule("DataCapture").DiagnoseText():find(ns.L.LOOTSRC_STATUS:format(NO, 2, 4), 1, true), "diagnosis shows saved loot counts")
	GetNumLootItems, GetLootSlotType, GetLootSlotLink, GetLootSourceInfo = savedNum, savedType, savedLink, savedSource
	IsFishingLoot, LootSlot, GetCVarBool, IsModifiedClick = savedFishing, savedSlot, savedCVar, savedClick
	UnitGUID, UnitName, issecretvalue, observations.Creature = savedGUID, savedName, savedSecret, savedCreature
	loot.db.record, items.db.fastLoot = savedRecord, savedFastLoot
	ns.db.lootSources, loot.count, loot.merged = savedSources, savedCount, savedMerged
	print("loot capture before fast loot OK")
end)()
;(function()
	local loot, tooltipModule = ns:GetModule("LootSources"), ns:GetModule("Tooltip")
	local onShift = uv(tooltipModule.OnLogin, "OnShiftChanged")
	local onUnit
	for _, callback in ipairs(TEST_POSTCALLS) do
		local fn = uv(callback, "fn")
		if fn and uv(fn, "MouseoverCreatureKey") then onUnit = callback break end
	end
	assert(onUnit, "loot is registered for unit tooltips")
	local savedTooltip, savedItem, savedGUID, savedAttack, savedShift = GameTooltip, C_Item, UnitGUID, UnitCanAttack, IsShiftKeyDown
	local savedItems, savedSources, savedCount, savedMerged = ns.LootData.items, ns.db.lootSources, loot.count, loot.merged
	local savedShiftInfo, savedUnitLoot = tooltipModule.db.shiftInfo, loot.db.unitLoot
	local guid = "Creature-0-1-2-3-999987-0001"
	local data = { type = Enum.TooltipDataType.Unit, guid = guid, lines = {} }
	local shift, attackable, mouseover, requests = false, true, guid, 0
	local lines, drops = {}, {}
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.infoList = { { tooltipData = data } }
	GameTooltip.GetPrimaryTooltipData = function() return data end
	GameTooltip.AddLine = function(_, line) lines[#lines + 1] = line end
	GameTooltip.AddDoubleLine = function(_, name, rate) drops[#drops + 1] = { name, rate } end
	GameTooltip.RefreshData = function()
		wipe(lines)
		wipe(drops)
		onUnit(GameTooltip, data)
	end
	UnitGUID = function() return mouseover end
	UnitCanAttack = function() return attackable end
	IsShiftKeyDown = function() return shift end
	local loaded = false
	C_Item = { GetItemInfo = function(id) if id ~= 2 or loaded then return "Drop " .. id, nil, 2 end end,
		RequestLoadItemDataByID = function(id) assert(id == 2) requests = requests + 1 end }
	local key = "npc:999987"
	ns.LootData.items = { [1] = { { key, 750, 2000 } }, [3] = { { key, 2100, 2000 } } }
	ns.db.lootSources = { [key] = { windows = 1, items = { [1] = 1, [2] = 1 } } }
	tooltipModule.db.shiftInfo, loot.db.unitLoot = false, true
	onUnit(GameTooltip, data)
	assert(#lines == 0 and requests == 0, "without Shift the creature tooltip does no loot work")
	shift = true
	onShift(nil, nil, "LSHIFT")
	assert(lines[2] == ns.L.LOOTSRC_UNIT_HEADER and #drops == 3, "pressing Shift adds loot independently of the global Shift setting")
	assert(lines[3] == ns.L.LOOTSRC_UNIT_OWN_WINDOWS:format(1), "local windows are visible separately")
	assert(drops[1][1] == "Drop 3" and drops[1][2] == ns.L.LOOTSRC_UNIT_COUNT:format(2100, 2001), "multiple slots show counts")
	assert(drops[2][1] == "Drop 1" and drops[2][2]:find("751", 1, true), "common drops first with both sets of records")
	assert(requests == 1 and drops[3][1] == ns.L.LOOTSRC_UNIT_ITEM:format(2)
		and drops[3][2] == ns.L.LOOTSRC_SHARE:format(ns.L.LOOTSRC_UNIT_BELOW, 1, 2001), "local-only drop uses all windows")
	local callbacks = {}
	local savedToggle, savedAfter = loot.ToggleEvent, ns.After
	loot.ToggleEvent = function(_, event, _, callback) callbacks[event] = callback end
	loot:Apply()
	loot.ToggleEvent = savedToggle
	local refresh
	ns.After = function(_, _, fn) refresh = fn end
	loaded = true
	callbacks.ITEM_DATA_LOAD_RESULT(nil, nil, 2, true)
	refresh()
	ns.After = savedAfter
	assert(drops[3][1] == "Drop 2" and requests == 1, "item data refreshes the visible name without repeating the request")
	loot.Record("tooltip-test", key, { 1 }, nil)
	GameTooltip:RefreshData()
	assert(drops[2][2]:find("752", 1, true), "new loot updates the cached list")
	shift = false
	onShift(nil, nil, "RSHIFT")
	assert(#lines == 0 and #drops == 0, "releasing Shift clears the section")
	shift, attackable = true, false
	onUnit(GameTooltip, data)
	assert(#lines == 0, "friendly creatures do not get the loot section")
	attackable, mouseover = true, "Creature-0-1-2-3-999986-0001"
	onUnit(GameTooltip, data)
	assert(#lines == 0, "another unit's tooltip does not get the mouseover loot")
	data.guid = mouseover
	onUnit(GameTooltip, data)
	assert(lines[3] == ns.L.LOOTSRC_UNIT_EMPTY, "missing data shows a clear message")
	loot.db.unitLoot = false
	GameTooltip:RefreshData()
	assert(#lines == 0, "loot option can be disabled")
	ns.LootData.items, ns.db.lootSources, loot.count, loot.merged = savedItems, savedSources, savedCount, savedMerged
	local onUnitTooltip = uv(onUnit, "fn")
	setuv(uv(onUnitTooltip, "CreatureDrops"), "shippedByCreature", nil)
	tooltipModule.db.shiftInfo, loot.db.unitLoot = savedShiftInfo, savedUnitLoot
	GameTooltip, C_Item, UnitGUID, UnitCanAttack, IsShiftKeyDown = savedTooltip, savedItem, savedGUID, savedAttack, savedShift
	print("enemy loot tooltip OK")
end)()
-- Observations
;(function()
	local O = ns:GetModule("Observations")
	-- cells merge close points
	local cells = {}
	O.AddCell(cells, 1436, 50.0, 50.0)
	O.AddCell(cells, 1436, 50.5, 50.4)
	O.AddCell(cells, 1436, 60.0, 50.0)
	assert(#cells == 2 and cells[1][4] == 2, "close points merge into one cell")
	-- NPC quests from the gossip window
	ns.db.npcQuests, ns.db.objectivePoints, ns.db.creaturePoints = {}, {}, {}
	O.npcCount, O.objectiveCount, O.creatureCount = 0, 0, 0
	UnitGUID = function() return "Creature-0-4379-0-27-8931-00001F5C36" end
	UnitName = function() return "Gastwirtin Heather" end
	C_Map.GetBestMapForUnit = function() return 1436 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	C_GossipInfo = { GetAvailableQuests = function() return { { questID = 11 }, { questID = 12 } } end,
		GetActiveQuests = function() return { { questID = 13, isComplete = true }, { questID = 14, isComplete = false } } end }
	ns:GetModule("Observations").RecordNpc(O.NpcID(UnitGUID("npc")), "offers", { 11, 12 })
	ns:GetModule("Observations").RecordNpc(8931, "takes", { 13 })
	local npc = O.Npc(8931)
	assert(npc and npc.offers[11] and npc.offers[12] and npc.takes[13] and not npc.takes[14] and npc.name == "Gastwirtin Heather", "NPC quests remembered")
	assert(#O.Takers(13) == 1 and O.Takers(13)[1].id == 8931, "who takes a quest back")
	-- shipped recordings are part of the lookup
	local shipped, row = next(ns.QuestData.npcs)
	assert(O.Npc(shipped).name == row[1], "shipped NPC")
	-- objective counts going up record where the player stood
	local count = 0
	C_QuestLog.GetQuestObjectives = function() return { { numFulfilled = count, finished = false } } end
	O.OnObjectiveUpdate(700)
	count = 3
	O.OnObjectiveUpdate(700)
	local points = O.ObjectivePoints(700, 1)
	assert(#points == 1 and points[1][1] == 1436 and points[1][2] == 50 and points[1][3] == 50, "objective point recorded")
	O.OnObjectiveUpdate(700)
	assert(#O.ObjectivePoints(700, 1) == 1 and ns.db.objectivePoints[700][1][1][4] == 1, "no change, no new point")
	-- the count arrives only after QUEST_WATCH_UPDATE: read again at the next QUEST_LOG_UPDATE, once
	local handlers = {}
	local savedToggle = O.ToggleEvent
	O.ToggleEvent = function(_, event, _, fn) handlers[event] = fn end
	O:Apply()
	O.ToggleEvent = savedToggle
	count = 0
	handlers.QUEST_WATCH_UPDATE(nil, "QUEST_WATCH_UPDATE", 701)
	assert(not ns.db.objectivePoints[701], "count not up yet")
	count = 4
	handlers.QUEST_LOG_UPDATE()
	handlers.QUEST_LOG_UPDATE()
	assert(ns.db.objectivePoints[701] and ns.db.objectivePoints[701][1][1][4] == 1, "recorded at the quest log update, once")
	-- the first update after loading only sets the counts: a count already reached gets no point here
	count = 2
	O.OnObjectiveUpdate(703, "watch")
	assert(not ns.db.objectivePoints[703], "count reached before /reload: no point")
	assert(ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("703/1", 1, true)
		and ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("Anfang", 1, true), ns.db.objectiveTrace[#ns.db.objectiveTrace])
	count = 3
	O.OnObjectiveUpdate(703, "log")
	assert(ns.db.objectivePoints[703] and ns.db.objectivePoints[703][1][1][4] == 1, "next step after loading is recorded")
	-- a progress bar counts in percent
	local percent = 0
	GetQuestProgressBarPercent = function() return percent end
	C_QuestLog.GetQuestObjectives = function() return { { type = "progressbar", numFulfilled = 0, finished = false } } end
	O.OnObjectiveUpdate(702)
	percent = 40
	O.OnObjectiveUpdate(702)
	GetQuestProgressBarPercent = nil
	assert(ns.db.objectivePoints[702], "progress bar point")
	assert(#ns.db.objectiveTrace > 0 and ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("702/1 progressbar 40", 1, true),
		ns.db.objectiveTrace[#ns.db.objectiveTrace])
	O.db.record = true
	O.Creature(6)
	O.Creature(6)
	assert(ns.db.creaturePoints[6][1][4] == 2, "creature cell counted twice")
	local text = O.ExportText()
	assert(text:find('{ 8931, "Gastwirtin Heather", { 11, 12 }, { 13 }, { { 1436, 50.0, 50.0, 2 } } },', 1, true), "NPC export line")
	assert(text:find("{ 700, 1, { { 1436, 50.0, 50.0, 1 } } },", 1, true), "objective export line")
	assert(text:find("{ 6, { { 1436, 50.0, 50.0, 2 } } },", 1, true), "creature export line")
	-- quest targets: a creature objective leads to the places where that creature was seen
	local quest, targets
	for q, list in pairs(ns.QuestData.targets) do
		for _, t in ipairs(list) do
			if t[1] == "m" and #O.CreaturePoints(t[2]) > 0 then quest, targets = q, t break end
		end
		if quest then break end
	end
	assert(quest, "a shipped quest with a creature that has positions")
	local ordinal = 0
	for _, t in ipairs(ns.QuestData.targets[quest]) do
		if t[1] == "m" then ordinal = ordinal + 1 end
		if t == targets then break end
	end
	assert(#O.TargetPoints(quest, "monster", ordinal) > 0, "creature objective: points of the creature")
	assert(#O.TargetPoints(quest, "monster", 99) == 0 and #O.TargetPoints(0, "monster", 1) == 0, "no target, no points")
	-- quest requirements: level, side, race and the quest before
	local info = ns:GetModule("QuestieInfo")
	local savedRequirements = ns.QuestData.requirements
	ns.QuestData.requirements = {
		[9001] = { 20, 0, {} }, [9002] = { 1, "H", {} }, [9003] = { 1, { 3, 4 }, {} }, [9004] = { 1, 0, { 9005, 9006 } },
	}
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 9006 end
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	UnitLevel = function() return 19 end
	UnitFactionGroup = function() return "Alliance" end
	UnitRace = function() return "Zwerg", "Dwarf", 3 end
	assert(not info.OwnAvailable(9001), "level too low")
	UnitLevel = function() return 20 end
	assert(info.OwnAvailable(9001), "level reached")
	assert(not info.OwnAvailable(9002), "Horde quest for an Alliance player")
	assert(info.OwnAvailable(9003), "race in the list")
	UnitRace = function() return "Mensch", "Human", 1 end
	assert(not info.OwnAvailable(9003), "race not in the list")
	assert(info.OwnAvailable(9004), "one quest before it is done")
	assert(not info.OwnAvailable(9006), "done quests are not offered")
	ns.QuestData.requirements = savedRequirements
	ns.db.npcQuests, ns.db.objectivePoints, ns.db.creaturePoints = {}, {}, {}
	O.npcCount, O.objectiveCount, O.creatureCount = 0, 0, 0
	print("observations OK")
end)()
-- Gathering tracking reminder
;(function()
	local B = ns:GetModule("Buffs")
	local active = false
	C_Minimap = { GetNumTrackingTypes = function() return 3 end,
		GetTrackingInfo = function(i) return { active = active and i == 2, spellID = i == 2 and 2383 or 1000 + i } end }
	assert(B.TrackingActive({ 2383, 2580 }) == false, "nothing tracked")
	active = true
	assert(B.TrackingActive({ 2383, 2580 }) == true, "Find Herbs tracked")
	assert(B.TrackingActive({ 2580 }) == false, "another ability is not the tracked one")
	print("tracking reminder OK")
end)()
-- World map filter menu
;(function()
	local WM = ns:GetModule("WorldMap")
	local library = ns:GetModule("Library")
	local texts, setters, nested = {}, {}, 0
	local values = {}
	Settings.SetValue = function(var, value) values[var] = value end
	local setOption = ns.SetOption
	ns.SetOption = function(moduleName, key, value) values["ForeverPlus_" .. moduleName .. "_" .. key] = value end
	local function node(depth, parent)
		return { CreateDivider = function() end, CreateTitle = function(_, t) texts[#texts + 1] = "# " .. t end,
			CreateRadio = function(_, name, isOn, set) setters[name .. depth] = { isOn = isOn, set = set } end,
			CreateColorSwatch = function(_, name, onClick, color)
				setters[name] = { set = onClick, color = color }
				return { SetTooltip = function() end }
			end,
			CreateButton = function(_, name)
				texts[#texts + 1] = (depth > 0 and "  " or "") .. name
				nested = nested + 1
				return node(depth + 1, name)
			end,
			CreateCheckbox = function(_, name, isOn, set)
				texts[#texts + 1] = (depth > 0 and "  " or "") .. name
				setters[name] = { isOn = isOn, set = set, parent = parent }
				if depth > 0 then nested = nested + 1 end
				local box = node(depth + 1, name)
				box.SetTooltip = function() end
				return box
			end }
	end
	WM.db.filterMenu = false
	WM.AddFilterMenu(node(0))
	assert(#texts == 0, "option off: no entries")
	WM.db.filterMenu = true
	WM.AddFilterMenu(node(0))
	assert(texts[1] == "# " .. ns.L.MENU_EXTRAS, "localized heading for the extra map filters")
	assert(setters[ns.L.WORLDMAP_FLIGHTS] and setters[ns.L.WORLDMAP_INNS] and setters[ns.L.LIBRARY_SYMBOLS]
		and setters[ns.L.TRANSPORTS_DOCKS] and setters[ns.L.RADAR_TITLE], "symbols, books, docks and radar present")
	local discoveries, books = setters[ns.L.WORLDMAP_DISCOVERIES], setters[ns.L.LIBRARY_SYMBOLS]
	assert(discoveries and books and discoveries.parent == ns.L.WORLDMAP_DISCOVERIES_MENU and books.parent == ns.L.WORLDMAP_DISCOVERIES_MENU,
		"discoveries and books are in the Secrets submenu")
	assert(not discoveries.isOn(), "discoveries filter starts off")
	local savedBooks = library.db.symbols
	library.db.symbols = true
	assert(books.isOn(), "books keep their independent setting while discoveries are off")
	books.set()
	assert(values.ForeverPlus_Library_symbols == false and values.ForeverPlus_WorldMap_discoveries == nil,
		"the book filter only changes book markers")
	library.db.symbols = savedBooks
	discoveries.set()
	assert(values.ForeverPlus_WorldMap_discoveries == true, "the map filter enables discoveries")
	assert(nested >= 3, "recipe radar options as a submenu")
	local swatch = setters[ns.L.WORLDMAP_REVEAL_COLOR]
	assert(swatch and swatch.set == WM.ChooseTint and swatch.color.g == 1 and swatch.color.r == 0.75, "colour entry with the current tint")
	WM.db.flightPoints = true
	assert(setters[ns.L.WORLDMAP_FLIGHTS].isOn() == true, "state read from the option")
	setters[ns.L.WORLDMAP_FLIGHTS].set()
	assert(values.ForeverPlus_WorldMap_flightPoints == false, "click switches the option")
	setters[ns.L.RADAR_TITLE].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_worldMap ~= nil, "radar entry switches on")
	ns.SetOption = setOption
	print("map filter menu OK")
end)()
;(function()
	-- Readables: the material decides the look, a book shows two pages, Blizzard's window gives back its room
	local R = ns:GetModule("Readable")
	assert(R.Look(nil, 1, false) == "SHEET", "a single sheet on parchment")
	assert(R.Look("Parchment", 1, true) == "BOOK" and R.Look("Parchment", 2, false) == "BOOK", "several pages: a book")
	assert(R.Look("ParchmentLarge", 1, false) == "BOOK", "the large parchment is a book")
-- Choices in menus keep the menu open
;(function()
	MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
	local response, picked
	local parent = { CreateRadio = function(_, text, isSelected, setSelected, data)
		return { text = text, isSelected = isSelected, setSelected = setSelected, data = data,
			SetResponse = function(_, value) response = value end }
	end }
	local radio = ns.CreateMenuRadio(parent, "60 %", function() return true end, function(value) picked = value end, 60)
	radio.setSelected(radio.data)
	assert(radio.text == "60 %" and radio.isSelected() and picked == 60, "text, state and choice passed through")
	assert(response == MenuResponse.Refresh, "the menu stays open after a choice")
	local sizes = 0
	parent.CreateButton = function() return { CreateRadio = function(...) sizes = sizes + 1 return parent.CreateRadio(...) end } end
	response = nil
	ns.CreateSizeMenu(parent, "Size", "WorldMap", "symbolScale")
	assert(sizes == 6 and response == MenuResponse.Refresh, "size menus stay open too")
	print("menu choices OK")
end)()
	local look, material = R.Look("Stone", 1, true)
	assert(look == "SHEET" and material == "Stone", "stone stays a plate, also with several pages")
	assert(select(2, R.Look("Valentine", 1, false)) == "Parchment", "unknown material on parchment")
	assert(R.TextHeight(400, 0) == 400 and R.TextHeight(400, nil) == 400, "text keeps the page height before layout")
	assert(R.TextHeight(400, 620) == 630, "longer text grows and scrolls")
	-- the book font as a copy without outline, every alphabet kept, at the height the game uses now
	do
		local savedFamily, made = CreateFontFamily, nil
		CreateFontFamily = function(name, list) made = list return { name = name } end
		TestBookFont = { GetFont = function() return "Fonts\\MORPHEUS.ttf", 18, "OUTLINE" end }
		ns.FontFamilies.families.TestBookFont = { roman = { "Fonts\\MORPHEUS.ttf", 15 }, russian = { "Fonts\\MORPHEUS_CYR.TTF", 15 } }
		local plain = ns.PlainFont("TestBookFont")
		assert(plain ~= TestBookFont and made and #made == 2, "a family of its own")
		for _, member in ipairs(made) do
			assert(member.flags == "" and member.height == 18, "no outline, current height: " .. member.alphabet)
		end
		assert(ns.PlainFont("TestBookFont") == plain, "made once")
		CreateFontFamily = savedFamily
	end
	-- the outline option leaves our own font families alone when it runs again for a later addon (it made the
	-- book font one outlined file of another alphabet)
	do
		local own = NewFont("ForeverPlusFontFamily999", 15)
		own.face = "Fonts\\K_Pagetext.ttf"
		local savedGetFonts = GetFonts
		GetFonts = function() return { "ForeverPlusFontFamily999" } end
		local eventFrame = uv(ns.RegisterEvent, "eventFrame")
		eventFrame:GetScript("OnEvent")(eventFrame, "ADDON_LOADED", "Blizzard_Test")
		assert(own.flags == "", "own font family keeps no outline: " .. own.flags)
		GetFonts, ForeverPlusFontFamily999 = savedGetFonts, nil
	end
	-- a book of five pages, as the game hands them out one at a time
	local saved = { ItemTextFrame, ItemTextGetPage, ItemTextHasNextPage, ItemTextGetMaterial, ItemTextGetItem,
		ItemTextGetText, ItemTextGetCreator, ItemTextNextPage, ItemTextPrevPage, C_Timer.After }
	local current, last = 1, 5
	local function Ready()
		R.Show()
	end
	ItemTextGetPage, ItemTextHasNextPage = function() return current end, function() return current < last end
	ItemTextGetMaterial, ItemTextGetItem = function() return "Parchment" end, function() return "Ein Buch" end
	ItemTextGetText, ItemTextGetCreator = function() return "Seite " .. current end, function() return nil end
	local asked = 0
	ItemTextNextPage = function() asked = asked + 1; current = current + 1; Ready() end
	ItemTextPrevPage = function() asked = asked + 1; current = current - 1; Ready() end
	C_Timer.After = function() end
	local window = NewFrame("Frame", "ItemTextFrame")
	local scale = 1
	window.SetScale = function(_, value) scale = value end
	window.GetScale = function() return scale end
	ItemTextFrame = window
	R.db.enabled = true
	R.ResetSpread()
	Ready()
	local spread = R.spread
	assert(spread.left.page == 1 and spread.right.page == 2 and spread.right.text == "Seite 2", "opens on pages 1 and 2")
	assert(scale == 0.001 and window.alpha == 0, "Blizzard's window collapsed while the book shows")
	assert(not R.CanTurn(false) and R.CanTurn(true), "only forward from the first spread")
	local traced = table.concat(ns.db.readableTrace or {}, "\n")
	for page = 1, 2 do
		local label = strtrim(ns.L.READABLE_TRACE_STYLE:format(page, "BOOK", "Parchment", "Text", 7, "", "", ""))
		assert(traced:find(label, 1, true), "pages in the trace: " .. traced)
	end
	R.Turn(true)
	assert(R.spread.left.page == 3 and R.spread.right.page == 4, "forward: pages 3 and 4")
	R.Turn(true)
	assert(R.spread.left.page == 5 and not R.spread.right and not R.CanTurn(true), "last page alone on the left")
	asked = 0
	R.Turn(false)
	assert(R.spread.left.page == 3 and R.spread.right.page == 4 and asked == 3, "back: two pages down, then the right one")
	R.Hide()
	assert(scale == 1 and window.alpha == 1 and not R.spread.left, "window given back on closing")
	-- a stone plate with two pages turns one page at a time
	ItemTextGetMaterial = function() return "Stone" end
	current, last = 1, 2
	Ready()
	assert(not R.spread.left, "no spread for a plate")
	R.Turn(true)
	assert(current == 2, "plate turned to page 2")
	R.Hide()
	ItemTextFrame, ItemTextGetPage, ItemTextHasNextPage, ItemTextGetMaterial, ItemTextGetItem, ItemTextGetText,
		ItemTextGetCreator, ItemTextNextPage, ItemTextPrevPage, C_Timer.After = unpack(saved, 1, 10)
	print("readable OK")
end)()
;(function()
	local readable = ns:GetModule("Readable")
	local oldTooltip, oldContainerInfo = GameTooltip, C_Container.GetContainerItemInfo
	local oldPage, oldTitle, oldText = ItemTextGetPage, ItemTextGetItem, ItemTextGetText
	local oldStatus, oldEnabled, oldTitles = readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles
	local title, line, red, titleRed = "Chronik von Azeroth"
	local oldGray, oldFirst = GRAY_FONT_COLOR, GameTooltipTextLeft1
	GameTooltipTextLeft1 = { SetTextColor = function(_, r) titleRed = r end }
	GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
	local getter = "GetBagItem"
	local isReadable = true
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.GetProcessingTooltipInfo = function()
		return { getterName = getter, getterArgs = { 0, 1 } }
	end
	GameTooltip.AddLine = function(_, value, r) line, red = value, r end
	C_Container.GetContainerItemInfo = function(bag, slot)
		if bag == 0 and slot == 1 then return { isReadable = isReadable } end
	end
	ItemTextGetPage = function() return 1 end
	ItemTextGetItem = function() return title end
	ItemTextGetText = function() return "Erste Seite" end
	readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles = true, false, {}
	local calls = {}
	local addPostCall = TooltipDataProcessor.AddTooltipPostCall
	TooltipDataProcessor.AddTooltipPostCall = function(kind, fn) calls[kind] = fn end
	readable:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall = addPostCall
	local function Hover(kind, name)
		line, titleRed = nil, nil
		calls[kind](GameTooltip, { lines = { { leftText = name } } })
		return line
	end
	local types = Enum.TooltipDataType
	assert(Hover(types.Item, title) == ns.L.READABLE_UNREAD, "unopened book in the bag")
	getter = "GetWorldCursor"
	assert(Hover(types.Object, title) == nil, "no unread label on an unknown world object")
	readable.Show()
	assert(Hover(types.Object, title) == ns.L.READABLE_ALREADY_READ, "a text from the normal reading window counts")
	getter = "GetBagItem"
	assert(Hover(types.Item, title) == ns.L.READABLE_ALREADY_READ, "known book in the bag")
	assert(red == 0.5, "already read is shown in grey")
	isReadable = false
	assert(Hover(types.Item, title) == nil, "a non-readable item with the same title is ignored")
	getter = "GetWorldCursor"
	readable.db.readStatus = false
	assert(Hover(types.Object, title) == nil, "tooltip option can be disabled")
	assert(titleRed == 0.5, "opened text keeps its grey title without the option")
	assert(Hover(types.Object, "Anderes Buch") == nil and titleRed == nil, "unopened text keeps its title colour")
	ItemTextGetItem = function() return "Anderes Buch" end
	readable.Show()
	assert(readable.cdb.openedTitles["Anderes Buch"], "texts are recorded without the option")
	GameTooltipTextLeft1 = oldFirst
	GameTooltip, C_Container.GetContainerItemInfo, GRAY_FONT_COLOR = oldTooltip, oldContainerInfo, oldGray
	ItemTextGetPage, ItemTextGetItem, ItemTextGetText = oldPage, oldTitle, oldText
	readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles = oldStatus, oldEnabled, oldTitles
	print("read status on mouseover OK")
end)()
;(function()
	-- Coordinates with one decimal place or, with the option, whole numbers
	local M = ns:GetModule("Minimap")
	local saved = M.db.wholeCoords
	M.db.wholeCoords = false
	assert(M.Format(45.34, 61.75) == "45.3, 61.8", M.Format(45.34, 61.75))
	M.db.wholeCoords = true
	assert(M.Format(45.34, 61.75) == "45, 62", M.Format(45.34, 61.75))
	M.db.wholeCoords = saved
	print("coordinates OK")
end)()
;(function()
	local minimap = ns:GetModule("Minimap")
	local savedCluster, savedHasMail = rawget(_G, "MinimapCluster"), rawget(_G, "HasNewMail")
	local frame, icon = CreateFrame("Frame"), CreateFrame("Frame")
	local fallback, hasMail = nil, true
	MinimapCluster = { IndicatorFrame = { MailFrame = frame } }
	HasNewMail = function() return hasMail end
	frame.MailIcon = icon
	frame.NewMailAnim, frame.MailReminderAnim = false, false
	icon.GetAtlas = function() return "ui-hud-minimap-mail-icon" end
	frame.CreateTexture = function()
		assert(not fallback, "one fallback texture is enough")
		fallback = CreateFrame("Frame")
		return fallback
	end
	frame:SetScript("OnHide", function() icon:Hide() end)
	frame:SetScript("OnEvent", function()
		frame:SetShown(hasMail)
		icon:SetShown(hasMail)
	end)

	assert(minimap.db.restoreMailIcon == true, "restoring the icon is enabled by default")
	minimap:OnOptionChanged("restoreMailIcon")
	assert(not fallback, "the original icon is visible")
	frame:GetScript("OnHide")(frame) -- parent was hidden; the mail frame is still marked shown
	frame:GetScript("OnShow")(frame)
	assert(fallback and fallback:IsShown() and not icon:IsShown(), "restore the envelope after showing the UI")

	minimap.db.restoreMailIcon = false
	minimap:OnOptionChanged("restoreMailIcon")
	assert(not fallback:IsShown(), "disabling the option immediately hides the fallback")
	minimap.db.restoreMailIcon = true
	minimap:OnOptionChanged("restoreMailIcon")
	assert(fallback:IsShown(), "reenabling restores the envelope again")

	frame:GetScript("OnEvent")(frame, "UPDATE_PENDING_MAIL")
	assert(icon:IsShown() and not fallback:IsShown(), "only the original icon shows after the mail update")
	hasMail = false
	frame:GetScript("OnEvent")(frame, "UPDATE_PENDING_MAIL")
	assert(not frame:IsShown() and not fallback:IsShown(), "clearing new mail hides the envelope")
	MinimapCluster, HasNewMail = savedCluster, savedHasMail
	print("minimap mail icon OK")
end)()
;(function()
	-- The text of a step: all of it up to the limit, the rest scrolls; slow text grows by whole words
	local D = ns:GetModule("Dialog")
	assert(D.ContentHeight(120.4) == 121, "short text whole")
	assert(D.ContentHeight(900) == 150, "long text up to the limit")
	local text = "Seid gegrüßt, Reisender."
	assert(D.RevealCut(text, 3) == 0, "no half word")
	assert(text:sub(1, D.RevealCut(text, 16)) == "Seid gegrüßt,", text:sub(1, D.RevealCut(text, 16)))
	assert(D.RevealCut(text, 99) == #text, "all said")
	print("speech OK")
end)()
;(function()
	-- Weapon masters: own faction on its city map, masters standing together share a symbol
	local Symbols = ns.MapSymbols
	local orgrimmar = Symbols.WeaponMasterGroups(1454, "H")
	assert(#orgrimmar == 1 and #orgrimmar[1].masters == 2, "Hanashi and Sayoc together")
	assert(#Symbols.WeaponMasterGroups(1454, "A") == 0, "not for the other faction")
	assert(#Symbols.WeaponMasterGroups(1453, "A") == 1, "Woo Ping in Stormwind")
	for _, master in ipairs(ns.WeaponMasters) do
		for _, skill in ipairs(master[6]) do
			assert(ns.WeaponSkillClasses[skill] and ns.L["WEAPON_" .. skill], "known skill " .. skill)
		end
	end
	print("weapon masters OK")
end)()
;(function()
	-- Opening: the bubble shows once the NPC's plate has stopped growing; the plates stay on while anyone needs them
	local D = ns:GetModule("Dialog")
	assert(not D.OpenReady(0.1, 0.1), "not before the shortest wait")
	assert(not D.OpenReady(0.2, 0.01), "not while the plate grows")
	assert(D.OpenReady(0.2, 0.06), "once the plate is still")
	assert(D.OpenReady(0.5, 0), "at the latest")
	assert(D.ScaleMoved(0.89, 0.90) and not D.ScaleMoved(0.95, 0.951), "small steps do not count")
	assert(D.ScaleMoved(nil, 0.5) and not D.ScaleMoved(nil, nil), "a plate that comes moves")
	local getCVar, setCVar = GetCVar, SetCVar
	local values = { nameplateShowFriendlyNpcs = "0", nameplateShowAll = "1" }
	GetCVar = function(cvar) return values[cvar] end
	SetCVar = function(cvar, value) values[cvar] = value end
	ns.ShowFriendlyPlates(true, "dialog")
	ns.ShowFriendlyPlates(true, "speech")
	assert(values.nameplateShowFriendlyNpcs == "1" and values.nameplateShowAll == "1", "plates on")
	ns.ShowFriendlyPlates(false, "speech")
	assert(values.nameplateShowFriendlyNpcs == "1", "the gossip ends, the conversation goes on: plates stay")
	ns.ShowFriendlyPlates(false, "dialog")
	assert(values.nameplateShowFriendlyNpcs == "0" and values.nameplateShowAll == "1", "each setting is restored")
	values.nameplateShowAll = "0"
	ns.ShowFriendlyPlates(true, "dialog")
	uv(ns.RegisterEvent, "listeners").PLAYER_LOGOUT["NPC bubble nameplates"]()
	assert(values.nameplateShowFriendlyNpcs == "0" and values.nameplateShowAll == "0", "restores both settings on reload")
	GetCVar, SetCVar = getCVar, setCVar
	print("opening OK")
end)()
;(function()
	-- Group quests: the kind of group, the group finder activities found by name, a listing that grows
	local G = ns:GetModule("GroupFinder")
	assert(G.QuestKind({ tagID = 81 }) == "dungeon" and G.QuestKind(nil, 0, true) == "dungeon", "dungeon by tag or data")
	assert(G.QuestKind({ tagID = 62 }) == "raid" and G.QuestKind({ tagID = 1 }) == "elite", "raid, group")
	assert(G.QuestKind(nil, 3) == "elite" and G.QuestKind({ tagID = 0, isElite = true }) == "elite", "suggested group, elite")
	assert(G.QuestKind(nil, 0, false) == nil and G.QuestKind({ tagID = 0 }, 1) == nil, "a quest for one: no button")
	local activities = {
		{ id = 799, fullName = "Die Todesminen", shortName = "Todesminen", categoryID = 2 },
		{ id = 805, fullName = "Scharlachrotes Kloster - Friedhof", shortName = "Friedhof", categoryID = 2 },
		{ id = 829, fullName = "Scharlachrotes Kloster - Bibliothek", shortName = "Bibliothek", categoryID = 2 },
		{ id = 813, fullName = "Düsterbruch (Ost)", shortName = "Düsterbruch (Ost)", categoryID = 2 },
		{ id = 814, fullName = "Düsterbruch (West)", shortName = "Düsterbruch (West)", categoryID = 2 },
		{ id = 854, fullName = "Westfall", shortName = "Westfall", categoryID = 116 },
		{ id = 855, fullName = "Dämmerwald", shortName = "Dämmerwald", categoryID = 116 },
	}
	local function ids(t) return table.concat(t, ",") end
	assert(ids(G.MatchActivities({ "Die Todesminen" }, activities, "dungeon")) == "799", "exact dungeon")
	assert(ids(G.MatchActivities({ "Scharlachrotes Kloster" }, activities, "dungeon")) == "805,829", "all wings")
	assert(ids(G.MatchActivities({ "Düsterbruch" }, activities, "dungeon")) == "813,814", "bracketed wings")
	assert(ids(G.MatchActivities({ "Westfall" }, activities, "elite")) == "854", "elite quest: its zone")
	assert(ids(G.MatchActivities({ "Die Todesminen" }, activities, "elite")) == "799", "elite quest in a dungeon")
	assert(#G.MatchActivities({ "Westfal" }, activities, "elite") == 0, "no half names")
	assert(#G.MatchActivities({ "Rotkammgebirge" }, activities, "elite") == 0, "nothing fits: no button")
	assert(ids(G.MergeActivities({ 854, 799 }, { 799, 805 })) == "854,799,805", "listing keeps its activities")
	-- The tracker asks on every update: one match per place and kind, again for a new activity list.
	local match, calls = G.MatchActivities, 0
	G.MatchActivities = function(...)
		calls = calls + 1
		return match(...)
	end
	local first = G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "dungeon")
	assert(ids(first) == "805,829" and calls == 1, "cached match: first look")
	assert(G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "dungeon") == first and calls == 1,
		"cached match: same place again, no new match")
	assert(ids(G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "elite")) == "805,829" and calls == 2,
		"cached match: another kind")
	assert(ids(G.CachedMatch({ "Die Todesminen" }, activities, "dungeon")) == "799" and calls == 3, "cached match: other place")
	local fewer = { activities[1] }
	assert(#G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, fewer, "dungeon") == 0 and calls == 4,
		"cached match: new activity list")
	G.MatchActivities = match
	print("group quests OK")
end)()
;(function()
	-- Auction prices: the newest look counts, within one look the lowest; the tooltip line for what one can make
	local A = ns:GetModule("Auction")
	local store = {}
	assert(A.RecordPrice(store, 2840, 500, 1000) and store[2840][1] == 500, "first price noted")
	assert(A.RecordPrice(store, 2840, 450, 1100) and store[2840][1] == 450, "lower in the same look")
	assert(not A.RecordPrice(store, 2840, 600, 1200) and store[2840][1] == 450, "higher in the same look: kept")
	assert(A.RecordPrice(store, 2840, 800, 1000 + 86400) and store[2840][1] == 800, "a later look replaces it")
	assert(not A.RecordPrice(store, 2840, 0, 1) and not A.RecordPrice(store, nil, 5, 1), "no price, no item")
	assert(A.PriceAge(60) == ns.L.AUCTION_AGE_NOW and A.PriceAge(7200) == ns.L.AUCTION_AGE_HOURS:format(2)
		and A.PriceAge(3 * 86400 + 5) == ns.L.AUCTION_AGE_DAYS:format(3), "age in words")
	local money = GetMoneyString
	GetMoneyString = function(copper) return copper .. "c" end
	local line = A.CraftPriceText(25, { 450, 1000 }, 1000 + 2 * 86400)
	assert(line:find("25c", 1, true) and line:find("450c", 1, true) and line:find(ns.L.AUCTION_AGE_DAYS:format(2), 1, true), line)
	assert(A.CraftPriceText(nil, nil, 0) == ns.L.AUCTION_CRAFT_UNKNOWN, "nothing known")
	assert(A.ShowsPriceLine(true, false, true) and A.ShowsPriceLine(nil, true, true), "crafted, or a known auction price")
	assert(not A.ShowsPriceLine(nil, false, true), "neither: no line")
	assert(not A.ShowsPriceLine(true, true, false), "extra lines only with Shift: hidden without")
	assert(A.FilterStatusText(4, 0, false):find("4", 1, true) and A.FilterStatusText(7, 0, true):find("7", 1, true),
		"filter status while searching and after")
	assert(A.FilterStatusText(3, 2, false) == nil, "hits shown: no status line")
	GetMoneyString = money
	do
		-- Upgrade arrow in the browse list
		local savedAPI, savedState = C_AuctionHouse, ns.ItemLinkUpgradeState
		local sample = "|Hitem:5::::|h[X]|h"
		C_AuctionHouse = { GetItemKeySampleLink = function(key) return key.itemID == 5 and sample or nil end }
		assert(A.RowLink({ itemLink = "|Hitem:9|h[Y]|h" }, { itemID = 5 }) == "|Hitem:9|h[Y]|h", "an auction's own link first")
		assert(A.RowLink({}, { itemID = 5 }) == sample, "else the sample link of the item key")
		assert(A.RowLink({}, { itemID = 6 }) == nil, "no sample link: no row link")
		assert(A.RowLink({ itemLink = "|Hbattlepet:1|h[P]|h" }) == nil, "pets get no arrow")
		local asked
		ns.ItemLinkUpgradeState = function(link) asked = link return "later" end
		local tex = NewFrame("Texture")
		function tex:SetDesaturated(v) self.desat = v end
		local cell = { Icon = { IsShown = function() return true end }, rowData = {},
			CreateTexture = function() return tex end }
		local onCell, onClear = uv(A.OnLogin, "OnItemCell"), uv(A.OnLogin, "OnItemCellCleared")
		onCell(cell, { itemID = 5 })
		assert(asked == sample and tex.shown and tex.desat, "grey arrow if only the level is missing")
		ns.ItemLinkUpgradeState = function() return "worse" end
		onCell(cell, { itemID = 5 })
		assert(tex.shown and tex.rotation == math.pi and tex.vertexColor[2] < 0.2, "worse auctions show the red down arrow")
		onClear(cell)
		assert(not tex.shown, "a cleared cell hides the arrow")
		cell.Prefix = {}
		onCell(cell, { itemID = 5 })
		assert(not tex.shown, "own auctions get no arrow")
		C_AuctionHouse, ns.ItemLinkUpgradeState = savedAPI, savedState
	end
	local savedAPI, savedStore, savedAfter, savedTime, savedProfile = C_AuctionHouse, ns.db.auctionPrices, C_Timer.After, time, debugprofilestop
	local timers, reads, now, ticks = {}, 0, 1000, 0
	C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
	time = function() return now end
	debugprofilestop = function() ticks = ticks + 1 return ticks * 0.15 end
	ns.db.auctionPrices = {}
	local function result(id, price) return { itemKey = { itemID = id }, minPrice = price } end
	C_AuctionHouse = {
		GetBrowseResults = function()
			reads = reads + 1
			return { result(1, 100), result(2, 200), result(3, 300), result(4, 400), result(5, 500) }
		end,
		GetCommoditySearchResultInfo = function() return { unitPrice = 150 } end,
	}
	local browse = uv(A.OnLogin, "OnBrowseResults")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { result(1, 80), result(6, 600) })
	do
		local frame = { UpdateBrowseResults = function() end, browseResults = { result(7, 700) } }
		local savedHook, savedUnregister, queue, unregistered = hooksecurefunc, A.UnregisterEvent, nil, 0
		hooksecurefunc = function(target, name, fn)
			assert(target == frame and name == "UpdateBrowseResults")
			queue = fn
		end
		A.UnregisterEvent = function() unregistered = unregistered + 1 end
		uv(A.OnLogin, "HookBrowsePrices")(frame)
		A.UnregisterEvent, hooksecurefunc = savedUnregister, savedHook
		assert(unregistered == 2, "the Blizzard hook replaces both browse event listeners")
		queue(frame)
		queue(frame, { result(7, 650) })
	end
	now = now + 1800
	uv(A.OnLogin, "OnCommodityResults")(A, "COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	assert(reads == 1 and #timers == 1 and next(ns.db.auctionPrices) == nil, "pages queue together and additions use the payload")
	table.remove(timers, 1)()
	assert(ns.db.auctionPrices[1] and not ns.db.auctionPrices[5] and #timers == 1, "the first price slice yields at its budget")
	while #timers > 0 do table.remove(timers, 1)() end
	assert(ns.db.auctionPrices[1][1] == 150 and ns.db.auctionPrices[1][2] == now and ns.db.auctionPrices[6][1] == 600,
		"queued snapshots preserve order and the time of each event")
	assert(ns.db.auctionPrices[7][1] == 650, "the Blizzard snapshot and appended page are saved without another read")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { result(8, 800) })
	uv(A.OnLogin, "SaveQueuedPrices")(true)
	assert(ns.db.auctionPrices[8][1] == 800, "logout saves the queued prices before the next frame")
	table.remove(timers, 1)()
	assert(#timers == 0, "a timer left after the flush has nothing to do")
	C_AuctionHouse, ns.db.auctionPrices, C_Timer.After, time, debugprofilestop = savedAPI, savedStore, savedAfter, savedTime, savedProfile
	print("craft prices OK")
end)()

-- Quest item pick
GetQuestLogSpecialItemInfo = function(i) if i == 1 then return "item:5", 123, 3, false end end
IsQuestLogSpecialItemInRange = function() return nil end
C_QuestLog.GetDistanceSqToQuest = function() return 900 end
C_QuestLog.IsComplete = function() return false end
local pick = uv(uv(ns:GetModule("Quests").UpdateItemTicker, "UpdateItemButton"), "PickQuestItem")
assert(pick() == 1, "quest item picked")
print("xp/questitem OK")
-- Tracker sort
local q = ns:GetModule("Quests")
local watches = { 11, 12, 13 }
C_QuestLog.GetNumQuestWatches = function() return #watches end
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return watches[i] end
C_QuestLog.RemoveQuestWatch = function(id) for i, v in ipairs(watches) do if v == id then table.remove(watches, i) break end end end
C_QuestLog.AddQuestWatch = function(id) watches[#watches + 1] = id end
C_QuestLog.GetNumQuestLogEntries = function() return 4 end
local log = { { isHeader = true, title = "Brachland" }, { questID = 11, level = 15, title = "C" }, { questID = 12, level = 10, title = "A" }, { questID = 13, level = 12, title = "B" } }
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.GetQuestObjectives = function() return {} end
GetZoneText = function() return "Brachland" end
strcmputf8i = function(a, b) return a < b and -1 or (a > b and 1 or 0) end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local sort = uv(uv(q.UpdateTrackerSort, "QueueSort"), "SortTracker")
q.cdb = q.cdb or {}
q.cdb.watched, q.cdb.trackerTab = nil, "world"
q.db.classFirst, q.db.instanceTab, q.db.regionOnly = false, false, false
C_QuestLog.GetQuestTagInfo = function() return nil end
q.db.trackerSort = "level"; sort()
print("  level order:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "12,13,11")
q.db.trackerSort = "name"; sort()
assert(table.concat(watches, ",") == "12,13,11")
-- Client that puts new watches on top: detected and corrected.
C_QuestLog.AddQuestWatch = function(id) table.insert(watches, 1, id) end
q.db.trackerSort = "default"; q.db.classFirst = true; sort()
print("  top-insert default:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "11,12,13")
sort()
assert(table.concat(watches, ",") == "11,12,13", "stable, no loop")
-- Class quests first, instance tab, region filter
function setuv(fn, name, value) for i = 1, 200 do local n = debug.getupvalue(fn, i) if not n then return end if n == name then debug.setupvalue(fn, i, value) return end end end
local facts = uv(uv(sort, "DesiredWatches"), "QuestFacts") or uv(sort, "QuestFacts")
setuv(facts, "playerClassName", "Schamane")
log = { { isHeader = true, title = "Brachland" }, { questID = 11, level = 15, title = "C" }, { questID = 12, level = 10, title = "A" },
	{ isHeader = true, title = "Schamane" }, { questID = 14, level = 20, title = "Klasse" },
	{ isHeader = true, title = "Die Todesminen" }, { questID = 15, level = 18, title = "Dungeon" },
	{ isHeader = true, title = "Mulgore" }, { questID = 16, level = 8, title = "Fern" } }
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetQuestTagInfo = function() return nil end
Enum.UIMapType = { Dungeon = 4 }
C_Map.GetMapInfo = function(id) if id == 36 then return { mapType = 4, name = "Die Todesminen" } end end
local isInst = uv(facts, "IsInstanceQuest")
setuv(uv(isInst, "InstanceNames"), "instanceNames", nil)
C_QuestLog.IsOnMap = function() return false end
q.cdb.watched = { [11] = true, [12] = true, [14] = true, [15] = true, [16] = true }
for i = #watches, 1, -1 do table.remove(watches, i) end
q.db.instanceTab = true; q.db.trackerSort = "level"
sort()
print("  world tab:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,16,12,11", "class first, instance quest on its own tab")
do
	local savedInfo, savedObjectives, savedDistance = C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives, C_QuestLog.GetDistanceSqToQuest
	local logReads, objectiveReads, distanceReads = 0, 0, 0
	C_QuestLog.GetInfo = function(index) logReads = logReads + 1 return savedInfo(index) end
	C_QuestLog.GetQuestObjectives = function() objectiveReads = objectiveReads + 1 return {} end
	C_QuestLog.GetDistanceSqToQuest = function() distanceReads = distanceReads + 1 return 0, true end
	sort()
	assert(logReads == #log and objectiveReads == 0 and distanceReads == 0,
		"the stable tracker sort and both tabs share one log read and skip unused keys")
	C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives, C_QuestLog.GetDistanceSqToQuest = savedInfo, savedObjectives, savedDistance
end
q.cdb.trackerTab = "instance"; sort()
assert(table.concat(watches, ",") == "15", "instance tab")
do
	local updateTabs = uv(sort, "UpdateTabs")
	local savedTabs = uv(updateTabs, "tabs")
	local textWrites, highlightWrites = 0, 0
	local function Tab()
		local tab = NewFrame("Button")
		tab.SetText = function() textWrites = textWrites + 1 end
		tab.GetTextWidth = function() return 40 end
		tab.GetFontString = function() return NewFrame("FontString") end
		tab.Underline = { SetShown = function() highlightWrites = highlightWrites + 1 end }
		return tab
	end
	setuv(updateTabs, "tabs", { world = Tab(), instance = Tab() })
	updateTabs(4, 1, "world")
	updateTabs(4, 1, "world")
	assert(textWrites == 2 and highlightWrites == 2, "unchanged tracker tabs do not rewrite their UI")
	updateTabs(3, 1, "instance")
	assert(textWrites == 3 and highlightWrites == 4, "changed count and selection refresh independently")
	setuv(updateTabs, "tabs", savedTabs)
end
q.cdb.watched[15] = nil; sort()
print("  instance tab without instance quests:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,16,12,11", "empty instance tab falls back to world")
q.cdb.watched[15] = true
q.cdb.trackerTab = "world"; q.db.regionOnly = true; sort()
print("  region only:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,12,11", "region filter keeps class quests")
q.db.regionOnly, q.db.instanceTab, q.db.classFirst = false, false, false
q.db.trackerSort = "zone"; sort()
q.db.trackerSort = "progress"; sort()
-- Only quests ready to turn in (everything when none is)
do
	local readyID = 12
	local realReady = ns.IsQuestReady
	local savedAdd, adds = C_QuestLog.AddQuestWatch, 0
	C_QuestLog.AddQuestWatch = function(id) adds = adds + 1 return savedAdd(id) end
	ns.IsQuestReady = function(id) return id == readyID end
	q.cdb.watched = nil
	q.db.trackerSort = "default"; q.db.readyOnly = true; sort()
	assert(table.concat(watches, ",") == "12" and adds == 0, "filtering out other quests leaves the existing watch in place")
	readyID = nil; sort()
	table.sort(watches)
	assert(table.concat(watches, ",") == "11,12,14,15,16", "nothing ready: all shown again")
	q.db.readyOnly = false; sort()
	ns.IsQuestReady = realReady
	C_QuestLog.AddQuestWatch = savedAdd
end
print("sort OK")
-- Reputation text
local repText = uv(uv(xp.OnLogin, "HookBars"), "UpdateRepText")
local rbar = { name = "Donnerfels %d / %d", value = 1200, max = 3000, SetBarText = function(_, t) print("  rep:", t) end }
for _, f in ipairs({ "percent", "remaining", "full" }) do xp.db.repFormat = f; repText(rbar) end
IsResting = function() return true end
print("rep OK")
-- Unified moving/locking
local mover = ns:GetModule("Mover")
local disp = NewFrame("Frame")
local entry = ns:RegisterDisplay(disp, "TestDisplay", function(f) f:SetPoint("CENTER") end)
IsAltKeyDown = function() return true end
GetMouseFoci = function() return { disp } end
assert(ns.db.locked == nil and not ns.db.unlocked["M:TestDisplay"], "locked by default")
clicks = 0
PlaySound = function() clicks = clicks + 1 end
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(ns.db.unlocked["M:TestDisplay"] == true, "alt right-click unlocks")
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(ns.db.unlocked["M:TestDisplay"] == nil, "alt right-click locks")
assert(clicks == 2, "a click for unlocking and for locking")
ns.db.lockSound = false
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(clicks == 2, "no click with the option off")
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
ns.db.lockSound = true
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
ns.db.lockAll = true
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(uv(mover.GLOBAL_MOUSE_UP, "moving") == nil, "locked: no move")
ns.db.lockAll = false
ns:SetAllLocked(false)
-- Window locking uses the title row, including when Alt is held.
;(function()
	local window = {
		GetLeft = function() return 10 end, GetRight = function() return 400 end,
		GetTop = function() return 500 end, GetEffectiveScale = function() return 1 end,
	}
	local child = NewFrame("Frame")
	child.IsObjectType = function(_, kind) return kind == "Frame" end
	local findTarget = uv(mover.GLOBAL_MOUSE_DOWN, "FindTarget")
	local savedWheel = uv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel")
	local savedCursor, savedAlt, savedFoci = GetCursorPosition, IsAltKeyDown, GetMouseFoci
	setuv(mover.GLOBAL_MOUSE_DOWN, "FindTarget", function() return window, "CharacterFrame" end)
	setuv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel", function() end)
	local function RightClick(region, x, y, alt)
		IsAltKeyDown = function() return alt end
		GetMouseFoci = function() return { region } end
		GetCursorPosition = function() return x, y end
		mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	end

	ns.db.unlocked.CharacterFrame = nil
	RightClick(window, 200, 300, false)
	RightClick(child, 200, 300, true)
	assert(not ns.db.unlocked.CharacterFrame, "window contents cannot unlock the window")
	RightClick(window, 200, 478, false)
	assert(ns.db.unlocked.CharacterFrame, "a window without a title container uses the top row")

	window.TitleContainer = {
		GetTop = function() return 499 end, GetHeight = function() return 20 end,
		GetLeft = function() return 40 end, GetRight = function() return 376 end,
		GetEffectiveScale = function() return 1.2 end,
	}
	RightClick(child, 240, 568, true)
	RightClick(window, 25, 590, false)
	assert(ns.db.unlocked.CharacterFrame, "the real title bounds exclude nearby window content and trim")
	local close = NewFrame("Button")
	RightClick(close, 240, 590, true)
	assert(ns.db.unlocked.CharacterFrame, "title bar controls keep their right-clicks")
	RightClick(child, 240, 590, false)
	assert(not ns.db.unlocked.CharacterFrame, "right-click on the title locks")
	RightClick(window, 240, 590, true)
	assert(ns.db.unlocked.CharacterFrame, "Alt-right-click on the title unlocks")
	GetCursorPosition, IsAltKeyDown, GetMouseFoci = savedCursor, savedAlt, savedFoci
	ns.db.unlocked.CharacterFrame = nil
	setuv(mover.GLOBAL_MOUSE_DOWN, "FindTarget", findTarget)
	setuv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel", savedWheel)
end)()
ns:ResetFramePositions()
assert(entry and not ns:HasSavedPosition(entry))
assert(next(ns.db.unlocked) == nil, "reset locks again")
print("mover OK")
;(function()
	local talents = ns:GetModule("Talents")
	local savedBook, savedSpell, savedFrame, savedRegistry = C_SpellBook, C_Spell, CreateFrame, EventRegistry
	local savedKnown, savedAfter = IsPlayerSpell, C_Timer.After
	local savedIndex, savedQueue = Enum.SpellBookSkillLineIndex, uv(talents.Update, "queueTrainerBook")
	local savedTrainer, savedLevel = talents.db.trainer.MAGE, UnitLevel
	local savedAvailable, savedTrainable, savedColor = SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE, SPELLBOOK_FONT_COLOR
	Enum.SpellBookSkillLineIndex = { General = 1 }
	IsPlayerSpell = function() return false end
	UnitLevel = function() return 20 end
	SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE = "Level %d", "Trainable"
	SPELLBOOK_FONT_COLOR = { GetRGB = function() return 0.15, 0.1, 0.05 end }

	local slots = {
		{ name = "A", spellID = 101 },
		{ name = "Frost", spellID = 102, subName = "Rank 1" },
		{ name = "Frost", spellID = 104, subName = "Rank 2" },
	}
	C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 2 end,
		GetSpellBookSkillLineInfo = function(line)
			return line == 1 and { name = "General", itemIndexOffset = 0, numSpellBookItems = 1 }
				or { name = "Frost", itemIndexOffset = 1, numSpellBookItems = 2 }
		end,
		GetSpellBookItemInfo = function(slot) return slots[slot] end,
		IsSpellKnown = function(id) return id == 101 or id == 102 or id == 108 end,
		GetCurrentLevelSpells = function(level) return level == 10 and { 101, 103, 104, 108 } or {} end,
	}
	C_Spell = {
		GetSpellName = function(id) return ({ [101] = "A", [103] = "C", [104] = "Frost", [108] = "Known" })[id] end,
		GetSpellSubtext = function(id) return id == 104 and "Rank 2" or "" end,
		GetSpellTexture = function() return 1 end,
	}
	talents.db.trainer.MAGE = {
		{ name = "B", level = 30, icon = 1 },
		{ name = "Known", level = 10 },
		{ name = "Frost", rank = "Rank 2", level = 14, line = "Frost" },
		{ name = "Frost", rank = "Rank 3", level = 20, line = "Frost" },
	}

	local frames, onPageChanged, fontWrites, bookScripts = {}, nil, 0, {}
	CreateFrame = function(kind, name, parent, template)
		local frame = savedFrame(kind, name, parent, template)
		frame.SetPoint = function(self, ...) self.testAnchor = { ... } end
		frame.testTemplate = template
		if template == "SpellBookItemTemplate" then
			for _, text in ipairs({ frame.Name, frame.SubName, frame.RequiredLevel }) do
				text.GetFont = function() return "Font", 14, "OUTLINE" end
				text.SetFont = function(self, _, _, flags) self.testFlags = flags fontWrites = fontWrites + 1 end
				text.SetText = function(self, content) self.testText = content end
			end
		end
		frames[#frames + 1] = frame
		return frame
	end
	EventRegistry = { RegisterCallback = function(_, _, fn) onPageChanged = fn end }
	local category = { skillLineIndex = 1, GetSpellBank = function() return Enum.SpellBookSpellBank.Player end }
	local view = { GetWidth = function() return 220 end, GetHeight = function() return 130 end }
	local nativeLayout = { { gridRow = 1, gridColumn = 1, isHeader = true }, { gridRow = 2, gridColumn = 1 } }
	local pager = {
		ViewFrames = { view, view }, columnsPerRow = 2, viewsPerPage = 1, xPadding = 10, yPadding = 10,
		viewDataList = { nativeLayout }, GetFrameLevel = function() return 10 end,
		PagingControls = NewFrame("Frame"),
	}
	pager.PagingControls.GetCurrentPage = function() return 1 end
	pager.PagingControls.GetMaxPages = function() return 1 end
	local book = {
		PagedSpellsFrame = pager, IsVisible = function() return true end,
		GetActiveCategoryMixin = function() return category end, categoryMixins = { category },
		OnActiveCategoryChanged = function() end, HookScript = function(_, script, fn) bookScripts[script] = fn end,
	}
	uv(talents.OnLogin, "SetupSpellsBook")(book)
	talents:Update()
	local row, nextPage, previousPage
	for _, frame in ipairs(frames) do
		if frame.testTemplate == "SpellBookItemTemplate" then row = frame end
		if frame.testTemplate == "PagingControlsNextPageButtonTemplate" then nextPage = frame end
		if frame.testTemplate == "PagingControlsPrevPageButtonTemplate" then previousPage = frame end
	end
	assert(row.fpTrainerEntry.spellID == 103 and row.testAnchor[4] == 115 and row.testAnchor[5] == -70,
		"the lowest-level preview uses the free cell alongside a native spell")
	assert(row.Name.testFlags == "" and row.RequiredLevel.testText:find("Trainable", 1, true),
		"readable text and trainer label")
	assert(nextPage:IsShown() and #nativeLayout == 2, "overflow uses an arrow and leaves the native page data intact")
	local refresh, scheduled = nil, 0
	C_Timer.After = function(_, fn) refresh, scheduled = fn, scheduled + 1 end
	nextPage:GetScript("OnClick")()
	nextPage:GetScript("OnClick")()
	previousPage:GetScript("OnClick")()
	assert(scheduled == 1, "several page turns in one frame share a refresh")
	local originalAnchor = row.testAnchor
	refresh()
	assert(row.fpTrainerEntry.spellID == 103 and row.testAnchor == originalAnchor and fontWrites == 3,
		"an unchanged page reuses the anchors and font settings")
	C_Timer.After = savedAfter
	nextPage:GetScript("OnClick")()
	assert(row.fpTrainerEntry.name == "B" and row.testAnchor[4] == 0, "the higher-level preview follows on the next page")
	assert(row.RequiredLevel.testText == "Level 30", "future entry shows the required level")
	previousPage:GetScript("OnClick")()
	assert(row.fpTrainerEntry.spellID == 103 and fontWrites == 3, "previous arrow reuses the existing fonts")
	local originalEntry = row.fpTrainerEntry
	bookScripts.OnHide()
	bookScripts.OnShow()
	assert(row.fpTrainerEntry == originalEntry, "reopening the book reuses the spell results")
	pager.viewsPerPage = 2
	onPageChanged()
	assert(not nextPage:IsShown(), "the second visible book page also has room for previews")
	pager.viewsPerPage = 1
	category.skillLineIndex = 2
	onPageChanged()
	assert(row.fpTrainerEntry.rank == "Rank 3" and not nextPage:IsShown(), "native future ranks are skipped in their own category")
	talents.db.enabled = false
	talents:Update()
	assert(not frames[1]:IsShown(), "disabling hides only the preview layer")
	talents.db.enabled = true
	talents:Update()
	assert(frames[1]:IsShown(), "previews reappear in the active category")

	local savedTicker = C_Timer.NewTicker
	local pending
	C_Timer.NewTicker = function(_, fn)
		pending = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return pending
	end
	talents:Update()
	local oldScan = pending
	oldScan:Run()
	bookScripts.OnHide()
	assert(oldScan.cancelled and not frames[1]:IsShown(), "closing the book cancels an unfinished spell scan")
	bookScripts.OnShow()
	assert(pending ~= oldScan and not pending.cancelled, "reopening starts a new scan")
	talents:Update()
	assert(pending and not pending.cancelled, "changed spell data replaces the current scan")
	bookScripts.OnHide()
	C_Timer.NewTicker = savedTicker

	local collect = uv(uv(talents.Update, "queueTrainerBook"), "RefreshTrainerBook")
	collect = uv(collect, "CollectTrainerSpells")
	local trainerList = uv(collect, "TrainerList")
	local savedShaman, savedSkills = talents.db.trainer.SHAMAN, C_SkillInfo
	setuv(collect, "playerClass", "SHAMAN")
	talents.db.trainer.SHAMAN = {
		{ name = "Welle der Heilung", rank = "Rang 2", level = 6, line = "Wiederherstellung" },
		{ name = "Großer Lehrerzauber", level = 40, line = "Wiederherstellung" },
	}
	local restoration = { name = "Wiederherstellung", itemIndexOffset = 0, numSpellBookItems = 1 }
	C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 2 end,
		GetSpellBookSkillLineInfo = function(line)
			return line == 2 and restoration or { name = "Allgemein", itemIndexOffset = 0, numSpellBookItems = 0 }
		end,
		GetSkillLineIndexByID = function() return nil end,
		GetSpellBookItemInfo = function() return { spellID = 332, name = "Welle der Heilung", subName = "Rang 2" } end,
		IsSpellKnown = function(id) return id == 332 end,
		GetCurrentLevelSpells = function() return {} end,
	}
	C_SkillInfo = { GetSkillLineInfoByID = function(id) return id == 374 and restoration or nil end }
	C_Spell.GetSpellName = function(id)
		return ({ [332] = "Welle der Heilung", [547] = "Welle der Heilung", [2008] = "Geist der Ahnen" })[id]
	end
	C_Spell.GetSpellSubtext = function(id)
		return ({ [332] = "Rang 2", [547] = "", [2008] = "Rang 1" })[id]
	end

	local scan = uv(talents.OnLogin, "ScanTrainer")
	local savedTrainerAPI, savedTrainerType = C_Trainer, Enum.TrainerType
	local savedGetFilter, savedSetFilter = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
	local savedCount, savedService, savedSkill = GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine
	Enum.TrainerType = { Class = 0, Pet = 1, Tradeskills = 2 }
	C_Trainer = { GetTrainerType = function() return Enum.TrainerType.Class end }
	local filters = { available = true, unavailable = false, used = false }
	GetTrainerServiceTypeFilter = function(filter) return filters[filter] end
	SetTrainerServiceTypeFilter = function(filter, enabled) filters[filter] = enabled end
	GetNumTrainerServices = function() return 1 end
	GetTrainerServiceInfo = function()
		assert(filters.available and filters.unavailable and filters.used, "the scan includes every trainer filter")
		return "Welle der Heilung", "available", 136052, 6, "Rang 2"
	end
	GetTrainerServiceSkillLine = function() return "Wiederherstellung" end
	scan()
	assert(#trainerList() == 2 and trainerList()[1].icon == 136052 and trainerList()[2].level == 40,
		"a starting-area trainer updates its ranks and keeps the previously recorded high-level spells")
	assert(filters.available and not filters.unavailable and not filters.used, "the user's trainer filters are restored")

	local results
	collect(function(spells) results = spells end)
	assert(#results[2] == 3 and results[2][1].spellID == 2008 and results[2][1].level == 12
		and results[2][2].spellID == 547 and results[2][2].level == 12
		and results[2][2].rank == ns.L.TALENTS_SPELL_RANK:format(3) and results[2][3].level == 40,
		"at level 6 the indexed preview includes new spells and higher ranks in Restoration, minus the learned rank")
	UnitLevel = function() return 6 end
	talents:Update()
	assert(row.fpTrainerEntry.spellID == 2008 and row.RequiredLevel.testText == "Level 12",
		"a Shaman future spell is drawn inside the Restoration tab with its level")

	C_Trainer, Enum.TrainerType = savedTrainerAPI, savedTrainerType
	GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = savedGetFilter, savedSetFilter
	GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine = savedCount, savedService, savedSkill
	talents.db.trainer.SHAMAN, C_SkillInfo = savedShaman, savedSkills
	setuv(collect, "playerClass", "MAGE")
	C_SpellBook, C_Spell, CreateFrame, EventRegistry = savedBook, savedSpell, savedFrame, savedRegistry
	IsPlayerSpell, UnitLevel = savedKnown, savedLevel
	SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE, SPELLBOOK_FONT_COLOR = savedAvailable, savedTrainable, savedColor
	Enum.SpellBookSkillLineIndex, talents.db.trainer.MAGE = savedIndex, savedTrainer
	setuv(talents.Update, "queueTrainerBook", savedQueue)
	print("trainer spells in spellbook OK")
end)()
-- Helpers: disenchant detection and fishing binding
local helpers = ns:GetModule("Helpers")
IsPlayerSpell = function(id) return id == 13262 or id == 7620 end
C_Container.GetContainerItemInfo = function() return { hyperlink = "item:1", stackCount = 1 } end
C_Item.GetItemInfo = function() return "Sword", "item:1", 2, 10, 1, "W", "S", 1, "INVTYPE_WEAPON", 1, 100, 2, 7 end
Enum.ItemClass = Enum.ItemClass or {}
Enum.ItemClass.Weapon, Enum.ItemClass.Armor, Enum.ItemClass.Tradegoods, Enum.ItemClass.Recipe = 2, 4, 7, 9
Enum.ItemQuality.Uncommon, Enum.ItemQuality.Epic = 2, 4
local proc = uv(uv(helpers.MODIFIER_STATE_CHANGED, "ShowGlows"), "ProcessSpell")
assert(proc(0, 1) == 13262, "disenchant")
;(function()
	local savedBind, savedClear, savedTimer = SetOverrideBindingClick, ClearOverrideBindings, C_Timer.NewTimer
	local savedCombat, savedMounted, savedFoci, savedExists = InCombatLockdown, IsMounted, GetMouseFoci, UnitExists
	local savedPosition, savedInventory, savedCursor = GetCursorPosition, GetInventoryItemID, GetCursorInfo
	local savedShift, savedAlt, savedCtrl, savedCount = IsShiftKeyDown, IsAltKeyDown, IsControlKeyDown, C_Item.GetItemCount
	local savedDelta, savedMouseDown = GetCursorDelta, IsMouseButtonDown
	local savedInstant, savedSubclasses = C_Item.GetItemInfoInstant, Enum.ItemWeaponSubclass
	local savedSlots, savedBag, savedTooltip = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_TooltipInfo.GetBagItem
	local button = _G.ForeverPlusFishButton
	local tracker = _G.ForeverPlusFishingMotion
	local savedAttribute, attrs = button.SetAttribute, {}
	local savedWeapons, savedEquip = helpers.cdb.fishingWeapons, helpers.db.fishingEquip
	helpers.cdb.fishingWeapons = {}
	local shift, offHand, bagCounts = false, 2, { [1] = 1, [2] = 1 }
	local binding, timer, equipped, blocked, mouseover, focus, cursor = nil, nil, 1, false, false, nil, nil
	local x = 100
	button.SetAttribute = function(_, key, value) attrs[key] = value end
	SetOverrideBindingClick = function(_, _, key, name) binding = key .. ">" .. name end
	ClearOverrideBindings = function() binding = nil end
	C_Timer.NewTimer = function(_, callback)
		timer = { Cancel = function(self) self.cancelled = true end, expire = callback }
		return timer
	end
	InCombatLockdown = function() return blocked end
	IsMounted = function() return false end
	GetMouseFoci = function() return { focus } end
	UnitExists = function() return mouseover end
	GetCursorPosition = function() return x, 100 end
	GetInventoryItemID = function(_, slot) if slot == INVSLOT_MAINHAND then return equipped end return offHand end
	GetCursorInfo = function() return cursor end
	IsShiftKeyDown = function() return shift end
	IsAltKeyDown = function() return false end
	IsControlKeyDown = function() return false end
	C_Item.GetItemCount = function(id) return bagCounts[id] or 0 end
	Enum.ItemWeaponSubclass = { Fishingpole = 20 }
	C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 2, id >= 6256 and 20 or 7 end
	local bagItems = { { itemID = 1 }, { itemID = 6257, isLocked = true }, { itemID = 6258 }, { itemID = 6256 } }
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end
	C_Container.GetContainerItemInfo = function(_, slot) return bagItems[slot] end
	C_TooltipInfo.GetBagItem = function(_, slot)
		return { lines = slot == 3 and { { leftColor = { r = 1, g = 0.1, b = 0.1 } } } or {} }
	end
	local function click()
		helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
		assert(not binding, "the first press alone does not arm the button")
		helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	end

	assert(helpers.db.fishingMenu == nil and helpers.db.fishing and savedEquip and helpers.db.fishingRestore,
		"the three core angler options are enabled by default and the old player-frame rod shortcut is gone")
	click()
	assert(not binding, "a plain pair never equips a pole from the bag")
	shift = true
	helpers.db.fishingEquip = false
	click()
	assert(not binding, "no override without an equipped pole while the option is off")
	helpers.db.fishingEquip = true
	blocked = true
	click()
	blocked, mouseover = false, true
	click()
	mouseover, focus = false, UIParent
	click()
	focus, cursor = nil, "item"
	click()
	assert(not binding, "combat, mouseover units, UI and a held item prevent auto-equip")
	cursor = nil
	helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	x = 180
	helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	assert(not binding, "camera turn does not arm fishing")
	helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	GetCursorDelta = function() return 8, 0 end
	tracker:GetScript("OnUpdate")(tracker)
	GetCursorDelta = savedDelta
	helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	assert(not binding, "camera motion cancels the gesture even if the pointer stayed locked in place")
	click()
	GetCursorDelta = function() return 0, 8 end
	tracker:GetScript("OnUpdate")(tracker)
	GetCursorDelta = savedDelta
	assert(not binding, "mouse movement during the double-click window releases the camera binding")
	IsMouseButtonDown = function() return true end
	click()
	IsMouseButtonDown = savedMouseDown
	assert(not binding, "a physical press that is already underway keeps its native release")
	click()
	assert(binding == "SHIFT-BUTTON2>ForeverPlusFishButton" and attrs.type == "macro" and attrs.useOnKeyDown == false
		and attrs.macrotext == "/equipslot [@mouseover,noexists,nocombat,nomounted,mod:shift] 16 item:6256",
		"the first pair selects the unlocked pole for a guarded main-hand equip")
	local equipTimer = timer
	local postClick = button:GetScript("PostClick")
	postClick(button, "LeftButton", true)
	assert(binding and not equipTimer.cancelled, "a secure mouse action can still be waiting for the release")
	postClick(button, "LeftButton", false)
	assert(not binding and equipTimer.cancelled, "consuming a pair cancels its override and timeout")
	equipped, offHand = 6256, nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	local shiftCondition = "[@mouseover,noexists,nocombat,nomounted,mod:shift]"
	local restoreBeforeShift = helpers.db.fishingRestore
	helpers.db.fishingRestore = false
	click()
	assert(not binding, "Shift with a pole equipped does nothing when weapon restoration is disabled")
	helpers.db.fishingRestore = restoreBeforeShift
	cursor = "item"
	click()
	assert(not binding, "Shift with a pole equipped does not swap weapons while holding an item")
	cursor = nil
	local savedChannel = UnitChannelInfo
	UnitChannelInfo = function() return "Fishing", nil, nil, nil, nil, nil, nil, 7620 end
	click()
	assert(binding == "SHIFT-BUTTON2>ForeverPlusFishButton" and attrs.type == "macro" and attrs.useOnKeyDown == false
		and attrs.macrotext == "/equipslot " .. shiftCondition .. " 16 item:1\n/equipslot " .. shiftCondition .. " 17 item:2",
		"Shift with a pole equipped restores the previous weapon and shield even while channelling Fishing")
	timer.expire()
	UnitChannelInfo = savedChannel
	bagCounts[2] = nil
	click()
	assert(binding == "SHIFT-BUTTON2>ForeverPlusFishButton"
		and attrs.macrotext == "/equipslot " .. shiftCondition .. " 16 item:1",
		"Shift with a pole equipped still restores the main hand when the saved shield is missing")
	timer.expire()
	bagCounts[1] = nil
	click()
	assert(not binding, "Shift with a pole equipped stays free when the saved main hand is missing")
	bagCounts[1], bagCounts[2] = 1, 1
	shift = false
	click()
	assert(binding == "BUTTON2>ForeverPlusFishButton" and attrs.type == "spell" and attrs.spell == 7620 and attrs.useOnKeyDown == false,
		"the next pair casts Fishing on release after the pole is equipped")
	timer.expire()
	assert(not binding, "an unused binding expires")
	equipped = nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	local restore = helpers.db.fishingRestore
	helpers.db.fishingRestore = false
	click()
	assert(not binding, "restoration can be disabled independently")
	helpers.db.fishingRestore = restore
	click()
	local condition = "[@mouseover,noexists,nocombat,nomounted,nomod]"
	assert(binding == "BUTTON2>ForeverPlusFishButton" and attrs.type == "macro" and attrs.useOnKeyDown == false
		and attrs.macrotext == "/equipslot " .. condition .. " 16 item:1\n/equipslot " .. condition .. " 17 item:2",
		"after removing the pole, a plain pair restores the saved weapon and shield")
	timer.expire()
	equipped = 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	bagCounts[1] = nil
	click()
	assert(not binding, "a missing saved main hand leaves the normal click free")
	bagCounts[1], equipped = 1, 1
	click()
	assert(binding and attrs.macrotext == "/equipslot " .. condition .. " 17 item:2",
		"only the missing shield is equipped")
	timer.expire()
	offHand = 2
	click()
	assert(not binding, "already wearing the saved set leaves the plain click free")
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_OFFHAND)
	equipped = 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	click()
	assert(not binding, "a later weapon upgrade is kept after the fishing set has been restored")
	offHand = nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_OFFHAND)
	local splitUpdate = timer
	click()
	assert(not binding, "a normal click during a split equipment update leaves a manually removed shield alone")
	equipped = 6256
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	assert(splitUpdate.cancelled and helpers.cdb.fishingWeapons.main == 3 and helpers.cdb.fishingWeapons.off == 2,
		"manually equipping a pole just after a weapon change remembers the new weapon and its shield")
	bagCounts[2], equipped = nil, 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	assert(not helpers.cdb.fishingWeapons.pending, "an unavailable shield does not keep a restored main hand pending")
	equipped = nil
	shift, bagItems = true, {}
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	click()
	assert(not binding, "no override when there is no pole to equip")

	helpers.db.fishingEquip = savedEquip
	helpers.cdb.fishingWeapons = savedWeapons
	button.SetAttribute = savedAttribute
	SetOverrideBindingClick, ClearOverrideBindings, C_Timer.NewTimer = savedBind, savedClear, savedTimer
	InCombatLockdown, IsMounted, GetMouseFoci, UnitExists = savedCombat, savedMounted, savedFoci, savedExists
	GetCursorPosition, GetInventoryItemID, GetCursorInfo = savedPosition, savedInventory, savedCursor
	GetCursorDelta = savedDelta
	IsShiftKeyDown, IsAltKeyDown, IsControlKeyDown, C_Item.GetItemCount = savedShift, savedAlt, savedCtrl, savedCount
	C_Item.GetItemInfoInstant, Enum.ItemWeaponSubclass = savedInstant, savedSubclasses
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_TooltipInfo.GetBagItem = savedSlots, savedBag, savedTooltip
end)()
print("helpers OK")
;(function()
	assert(rawget(_G, "ForeverPlusFishingMenu") == nil and uv(helpers.OnLogin, "CreateFishingMenu") == nil,
		"angler shortcut button on the player frame is removed")
	local fishingSettings, optionByKey = {}, {}
	for _, option in ipairs(helpers.options) do
		if option.key and option.key:match("^fishing") then
			fishingSettings[#fishingSettings + 1] = option.key
			optionByKey[option.key] = option
		end
	end
	assert(table.concat(fishingSettings, ",") == "fishing,fishingEquip,fishingRestore,fishingHideUI,fishingSound,fishingBear,fishingBearSound",
		"settings expose all angler mode options without the removed player-frame shortcut")
	assert(optionByKey.fishingEquip.parent == "fishing" and optionByKey.fishingRestore.parent == "fishing"
		and optionByKey.fishingHideUI.parent == "fishing" and optionByKey.fishingSound.parent == "fishing"
		and optionByKey.fishingBear.parent == "fishing" and optionByKey.fishingBearSound.parent == "fishingBear",
		"angler settings keep parent dependencies intact")
	assert(optionByKey.fishingHideUI.new == true and optionByKey.fishingSound.new == true
		and optionByKey.fishingBear.new == true and optionByKey.fishingBearSound.new == true,
		"newer angler options remain marked NEW")
	local subKeys = {}
	for _, feature in ipairs(ns.PortraitModes.FEATURES) do
		if feature.key == "angler" then
			for _, sub in ipairs(feature.subOptions or {}) do
				subKeys[#subKeys + 1] = sub.key
			end
		end
	end
	assert(table.concat(subKeys, ",") == "fishingEquip,fishingRestore,fishingHideUI,fishingSound,fishingBear,fishingBearSound",
		"PortraitModes angler mode exposes all six angler sub-options")
end)()
;(function()
	local savedChannel, savedVisibility, savedGet, savedSet = UnitChannelInfo, SetUIVisibility, GetCVar, SetCVar
	local originalVisibility = UIParent:IsShown()
	local spellID
	local volumes = { Sound_SFXVolume = "0.2", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.8", Sound_DialogVolume = "0.6" }
	UnitChannelInfo = function()
		if spellID then return C_Spell.GetSpellName(spellID), nil, nil, nil, nil, nil, nil, spellID end
	end
	SetUIVisibility = function(visible) UIParent:SetShown(visible) end
	GetCVar = function(key) return volumes[key] end
	SetCVar = function(key, value) volumes[key] = value end
	local event = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	UIParent:Show()
	ns.SetOption("Helpers", "fishingHideUI", true)
	ns.SetOption("Helpers", "fishingSound", true)
	spellID = 10
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	assert(UIParent:IsShown() and volumes.Sound_MusicVolume == "0.4", "an unrelated channel leaves the UI and volumes alone")
	spellID = 7620
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	assert(not UIParent:IsShown() and volumes.Sound_SFXVolume == "0.65" and volumes.Sound_MusicVolume == "0.1",
		"a real Fishing channel hides the UI and makes effects easier to hear")
	volumes.Sound_DialogVolume = "0.7"
	spellID = nil
	event(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
	assert(UIParent:IsShown() and volumes.Sound_SFXVolume == "0.2" and volumes.Sound_MusicVolume == "0.4"
		and volumes.Sound_AmbienceVolume == "0.8" and volumes.Sound_DialogVolume == "0.7",
		"channel end restores the UI and original volumes while preserving a manual change")
	UIParent:Hide()
	spellID = 7620
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	event(nil, "PLAYER_LOGOUT")
	assert(not UIParent:IsShown() and volumes.Sound_SFXVolume == "0.2" and volumes.Sound_MusicVolume == "0.4",
		"logout restores the volumes and leaves an already-hidden UI hidden")
	spellID = nil
	ns.SetOption("Helpers", "fishingHideUI", false)
	ns.SetOption("Helpers", "fishingSound", false)
	UIParent:SetShown(originalVisibility)
	UnitChannelInfo, SetUIVisibility, GetCVar, SetCVar = savedChannel, savedVisibility, savedGet, savedSet
end)()
;(function()
	-- Angler mode Nat Pagle flash & native sounds: trigger, geometry/animation, delayed splash, abort, options and previews.
	local showBear = uv(helpers.PreviewBear, "ShowAnglerBear")
	local ensureBear = uv(showBear, "EnsureAnglerBearFrame")
	local savedBearFrame = uv(ensureBear, "bearFrame")
	local savedGlobalBear = ForeverPlusAnglerBear
	local savedCreate, savedPlay, savedStop, savedAfter =
		CreateFrame, PlaySoundFile, rawget(_G, "StopSound"), C_Timer.After
	local savedW, savedH = UIParent.w, UIParent.h
	local savedFishing, savedBearOpt, savedBearSoundOpt =
		helpers.db.fishing, helpers.db.fishingBear, helpers.db.fishingBearSound
	local bear, strata, mouseEnabled, ignoreAlpha, texturePath, anchorPoint
	local played, stopped, pendingAfter, nextHandle = {}, {}, {}, 100
	local CAST_IDS = { [3610663] = true, [3610665] = true }
	local SPLASH_IDS = { [569285] = true, [568970] = true, [569044] = true }

	UIParent.w, UIParent.h = 1920, 1080
	setuv(ensureBear, "bearFrame", nil)
	PlaySoundFile = function(id, channel)
		nextHandle = nextHandle + 1
		played[#played + 1] = { id = id, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	StopSound = function(handle)
		stopped[#stopped + 1] = handle
	end
	C_Timer.After = function(delay, fn)
		pendingAfter[#pendingAfter + 1] = { delay = delay, fn = fn }
	end
	CreateFrame = function(kind, name, parent)
		local frame = savedCreate(kind, name, parent)
		if name == "ForeverPlusAnglerBear" then
			bear = frame
			frame.SetFrameStrata = function(_, value) strata = value end
			frame.EnableMouse = function(_, value) mouseEnabled = value end
			frame.SetIgnoreParentAlpha = function(_, value) ignoreAlpha = value end
			frame.SetPoint = function(_, point, relative) anchorPoint = { point, relative } end
			frame.SetSize = function(self, width, height) self.w, self.h = width, height end
			local origCreateTexture = frame.CreateTexture
			frame.CreateTexture = function(self, ...)
				local tex = origCreateTexture(self, ...)
				tex.SetTexture = function(_, path) texturePath = path end
				return tex
			end
		end
		return frame
	end

	-- Settings expose fishingBear + fishingBearSound with new = true and a preview button; PortraitModes lists both.
	local bearOpt, soundOpt, previewOpt
	for _, opt in ipairs(helpers.options) do
		if opt.key == "fishingBear" then bearOpt = opt end
		if opt.key == "fishingBearSound" then soundOpt = opt end
		if opt.type == "button" and opt.name == ns.L.HELPERS_FISHING_BEAR_PREVIEW then previewOpt = opt end
	end
	assert(bearOpt and bearOpt.new == true and helpers.db.fishingBear == true, "fishingBear option defaults on and is marked NEW")
	assert(soundOpt and soundOpt.new == true and soundOpt.parent == "fishingBear" and helpers.db.fishingBearSound == true,
		"fishingBearSound option defaults on, depends on fishingBear and is marked NEW")
	assert(previewOpt and type(previewOpt.func) == "function", "Nat Pagle preview button is present in settings")
	assert(ns.L.SLASH_HELP:find("/fp nat", 1, true), "slash help documents /fp nat")
	local pmBearFound, pmSoundFound = false, false
	for _, feature in ipairs(ns.PortraitModes.FEATURES) do
		if feature.key == "angler" then
			for _, sub in ipairs(feature.subOptions or {}) do
				if sub.module == "Helpers" and sub.key == "fishingBear" then pmBearFound = true end
				if sub.module == "Helpers" and sub.key == "fishingBearSound" then pmSoundFound = true end
			end
		end
	end
	assert(pmBearFound and pmSoundFound, "PortraitModes angler sub-options include fishingBear and fishingBearSound")

	-- Staying on or turning off does not flash Nat Pagle or play sounds.
	ns.SetOption("Helpers", "fishing", true)
	assert(not bear and #played == 0, "re-enabling an already active fishing mode does not trigger Nat Pagle")
	ns.SetOption("Helpers", "fishing", false)
	assert(not bear and #played == 0, "disabling fishing mode does not trigger Nat Pagle")

	-- Turning off -> on triggers Nat Pagle overlay, immediate cast sound and delayed splash.
	ns.SetOption("Helpers", "fishing", true)
	assert(bear and bear:IsShown(), "off -> on fishing transition shows Nat Pagle")
	assert(strata == "FULLSCREEN_DIALOG" and mouseEnabled == false and ignoreAlpha == true,
		"Nat Pagle uses non-interactive fullscreen overlay ignoring parent alpha")
	assert(anchorPoint and anchorPoint[1] == "CENTER" and anchorPoint[2] == UIParent, "Nat Pagle is centered on UIParent")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\AnglerNatPagle.tga]], "Nat Pagle loads AnglerNatPagle.tga")
	assert(#played == 1 and CAST_IDS[played[1].id] and played[1].channel == "SFX",
		"activation plays a verified fishing cast sound immediately on SFX")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.35) < 0.001,
		"bobber splash is scheduled 0.35 s after cast via ns.After")
	local firstCastID, firstCastHandle = played[1].id, played[1].handle
	pendingAfter[1].fn()
	assert(#played == 2 and SPLASH_IDS[played[2].id] and played[2].channel == "SFX",
		"delayed timer plays a verified bobber splash sound on SFX")
	local firstSplashID, firstSplashHandle = played[2].id, played[2].handle

	local update = bear:GetScript("OnUpdate")
	assert(type(update) == "function", "Nat Pagle starts an OnUpdate handler while active")
	update(bear, 0.40)
	local holdSize, holdAlpha = bear:GetWidth(), bear:GetAlpha()
	assert(holdSize > 900 and math.abs(holdAlpha - 0.50) < 0.01, "during hold Nat Pagle fills screen height at half transparency")
	update(bear, 0.70)
	local midSize, midAlpha = bear:GetWidth(), bear:GetAlpha()
	assert(midSize < holdSize and midAlpha < holdAlpha, "during shrink Nat Pagle starts shrinking and fading")
	update(bear, 0.40)
	assert(bear:GetWidth() < holdSize * 0.35 and bear:GetWidth() < midSize and bear:GetAlpha() < midAlpha,
		"accelerated in-easing rapidly shrinks Nat Pagle toward the screen center")
	update(bear, 0.15)
	assert(not bear:IsShown() and bear:GetAlpha() == 0 and bear:GetScript("OnUpdate") == nil,
		"after completion Nat Pagle hides cleanly and stops OnUpdate (0 CPU idle)")
	assert(#stopped == 0,
		"normal completion lets cast and bobber splash sounds finish decaying naturally")

	-- PortraitModes ToggleMode off -> on triggers Nat Pagle and alternates cast/splash sounds.
	played, stopped, pendingAfter = {}, {}, {}
	ns.PortraitModes.ToggleMode("angler")
	assert(not helpers.db.fishing and not bear:IsShown(), "PortraitModes turns angler mode off")
	assert(stopped[1] == firstCastHandle and stopped[2] == firstSplashHandle,
		"turning fishing off stops any still-active cast and splash handles")
	stopped = {}
	ns.PortraitModes.ToggleMode("angler")
	assert(helpers.db.fishing and bear:IsShown() and bear:GetScript("OnUpdate") ~= nil,
		"PortraitModes off -> on transition plays Nat Pagle")
	assert(#played == 1 and CAST_IDS[played[1].id] and played[1].id ~= firstCastID,
		"consecutive casts alternate between the two verified cast sounds")
	local pendingSplash = pendingAfter[1]
	-- Turning fishingBear off stops an active animation, stops sound handles and cancels the pending splash.
	local activeCastHandle = played[1].handle
	ns.SetOption("Helpers", "fishingBear", false)
	assert(not bear:IsShown() and bear:GetScript("OnUpdate") == nil, "disabling fishingBear stops an active flash")
	assert(stopped[1] == activeCastHandle, "disabling fishingBear stops active sound handle")
	pendingSplash.fn()
	assert(#played == 1, "cancelled splash timer does not fire after StopAnglerBear")
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("Helpers", "fishing", true)
	assert(not bear:IsShown() and #played == 1, "fishingBear = false suppresses the flash and sound on activation")

	-- Re-triggering preview stops previous handles and cancels stale splash timer; new timer plays alternate splash.
	played, stopped, pendingAfter = {}, {}, {}
	SlashCmdList.FOREVERPLUS("nat")
	assert(bear:IsShown() and bear:GetScript("OnUpdate") ~= nil and #played == 1 and #pendingAfter == 1,
		"/fp nat previews Nat Pagle with cast sound and scheduled splash")
	local staleCastHandle, staleSplash = played[1].handle, pendingAfter[1]
	SlashCmdList.FOREVERPLUS("pagle")
	assert(stopped[1] == staleCastHandle and #played == 2 and #pendingAfter == 2,
		"/fp pagle stops previous sound handle and restarts preview")
	staleSplash.fn()
	assert(#played == 2, "stale splash timer from previous start is ignored")
	pendingAfter[2].fn()
	assert(#played == 3 and SPLASH_IDS[played[3].id] and played[3].id ~= firstSplashID,
		"active splash timer plays the next bobber splash variant")
	-- Disabling fishingBearSound mid-flash stops active sounds without hiding the portrait.
	local countBeforeMute = #stopped
	ns.SetOption("Helpers", "fishingBearSound", false)
	assert(bear:IsShown() and #stopped > countBeforeMute, "disabling fishingBearSound stops active sounds immediately")
	bear:GetScript("OnUpdate")(bear, 2.0)

	-- With fishingBearSound = false, activation and all preview commands/aliases stay completely silent.
	played, stopped, pendingAfter = {}, {}, {}
	ns.SetOption("Helpers", "fishingBear", true)
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("Helpers", "fishing", true)
	assert(bear:IsShown() and #played == 0 and #pendingAfter == 0, "fishingBearSound = false stays silent on activation")
	bear:GetScript("OnUpdate")(bear, 2.0)
	for _, cmd in ipairs({ "nat", "pagle", "angler", "bär", "anglerbär", "bear", "anglerbear" }) do
		SlashCmdList.FOREVERPLUS(cmd)
		assert(bear:IsShown() and bear:GetScript("OnUpdate") ~= nil, "/fp " .. cmd .. " previews Nat Pagle")
		bear:GetScript("OnUpdate")(bear, 2.0)
		assert(not bear:IsShown() and bear:GetScript("OnUpdate") == nil, "preview finishes and stops OnUpdate")
	end
	previewOpt.func()
	assert(bear:IsShown() and #played == 0 and #pendingAfter == 0, "settings preview stays silent when fishingBearSound is off")
	bear:GetScript("OnUpdate")(bear, 2.0)

	ns.SetOption("Helpers", "fishingBearSound", savedBearSoundOpt)
	ns.SetOption("Helpers", "fishingBear", savedBearOpt)
	ns.SetOption("Helpers", "fishing", savedFishing)
	UIParent.w, UIParent.h = savedW, savedH
	CreateFrame, PlaySoundFile, StopSound, C_Timer.After = savedCreate, savedPlay, savedStop, savedAfter
	ForeverPlusAnglerBear = savedGlobalBear
	setuv(ensureBear, "bearFrame", savedBearFrame)
end)()
print("ttd OK")
-- Junk marks tell random suffixes apart
local isJunk = uv(uv(items.LOOT_READY or items.OnLogin, "UpdateAllBags") or function() end, "x")
local junkKey = nil
itemsMod = ns:GetModule("Items")
itemsMod.db.junk, itemsMod.db.keep = {}, {}
IsJunkItemFn = nil
for i = 1, 200 do
	local n, v = debug.getupvalue(itemsMod.ShowJunkMenu, i)
	if not n then break end
end

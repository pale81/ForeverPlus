-- Quests: sounds on quest progress and completion, quest icon with progress
-- on the nameplates of units related to an active quest.
local _, ns = ...
local L = ns.L

local Quests = ns:NewModule("Quests", {
	title = L.QUESTS_TITLE,
	order = 5.2,
	defaults = {
		sounds = true,
		completeSound = "peon",
		progressSound = "peonReady",
		nameplateIcons = true,
		itemButton = true,
		trackerSort = "default",
		classFirst = true,
		instanceTab = true,
		instancePreQuests = true,
		regionOnly = false,
		questParchment = false,
		foreverMark = true,
		foreverMarkStyle = "ICON",
	},
	charDefaults = {
		trackerTab = "world",
		-- watched = { [questID] = true }: quests the player wants tracked
	},
})

local SCAN_DELAY = 0.3
-- File IDs: sound/creature/peon/peonbuildingcomplete1.ogg ("Work complete")
-- and peonready1.ogg ("Ready to work").
local PEON_DONE, PEON_READY = 558132, 558137

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
local SOUNDS = {
	peon = function()
		-- Falls back to Blizzard's sound when the client cannot find the file.
		if not PlaySoundFile(PEON_DONE, "Master") then
			PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
		end
	end,
	peonReady = function()
		if not PlaySoundFile(PEON_READY, "Master") then
			PlaySound(SOUNDKIT.MAP_PING, "Master")
		end
	end,
	complete = function()
		PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
	end,
	ping = function()
		PlaySound(SOUNDKIT.MAP_PING, "Master")
	end,
	select = function()
		PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT, "Master")
	end,
}

local function Play(key)
	local fn = SOUNDS[key]
	if fn then
		fn()
	end
end

local state = {} -- questID -> { done = fulfilled objectives, complete = bool }
local scanPending, initialized = false, false

local function ScanQuests()
	scanPending = false
	local seen = {}
	local progressed, completed = false, false
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID and info.questID > 0 then
			local questID = info.questID
			local done = 0
			for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
				done = done + (objective.numFulfilled or 0)
			end
			local complete = ns.IsQuestReady(questID, index)
			local old = state[questID]
			if initialized and old then
				if complete and not old.complete then
					completed = true
				elseif done > old.done then
					progressed = true
				end
			end
			state[questID] = { done = done, complete = complete }
			seen[questID] = true
		end
	end
	for questID in pairs(state) do
		if not seen[questID] then
			state[questID] = nil
		end
	end
	initialized = true
	if completed then
		Play(Quests.db.completeSound)
	elseif progressed then
		Play(Quests.db.progressSound)
	end
	if (completed or progressed) and Quests.db.trackerSort == "progress" then
		Quests:QueueTrackerSort()
	end
	Quests:RefreshNameplates()
end

local function QueueScan()
	if not scanPending then
		scanPending = true
		C_Timer.After(SCAN_DELAY, ns.Measured("Quests: quest log scan", ScanQuests))
	end
end

---------------------------------------------------------------------------
-- Nameplate quest icons
---------------------------------------------------------------------------
local QUEST_ICON = [[Interface\GossipFrame\AvailableQuestIcon]]
local markers = {} -- nameplate -> marker frame

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- First open objective of the unit's quest lines, e.g. "3/8".
local function QuestProgress(unit)
	local data = C_TooltipInfo.GetUnit(unit)
	local found
	for _, line in ipairs(data and data.lines or {}) do
		if line.type == Enum.TooltipDataLineType.QuestObjective then
			found = ""
			local text = line.leftText
			if text and not Secret(text) then
				local have, need = text:match("(%d+)%s*/%s*(%d+)")
				if have and tonumber(have) < tonumber(need) then
					return ("%s/%s"):format(have, need)
				end
			end
		end
	end
	return found
end

local function GetMarker(nameplate)
	local marker = markers[nameplate]
	if not marker then
		marker = CreateFrame("Frame", nil, nameplate)
		marker:SetSize(16, 16)
		marker:SetPoint("LEFT", nameplate, "RIGHT", -2, 0)
		marker.Icon = marker:CreateTexture(nil, "OVERLAY")
		marker.Icon:SetAllPoints()
		marker.Icon:SetTexture(QUEST_ICON)
		marker.Text = marker:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		marker.Text:SetPoint("LEFT", marker, "RIGHT", 1, 0)
		markers[nameplate] = marker
	end
	return marker
end

-- Vertically centred on the health bar, right of the level box if shown.
local function PlaceMarker(marker, nameplate)
	local unitFrame = nameplate.UnitFrame
	local health = unitFrame and unitFrame.HealthBarsContainer
	marker:ClearAllPoints()
	if not health then
		marker:SetPoint("LEFT", nameplate, "RIGHT", -2, 0)
		return
	end
	local level = unitFrame.PlayerLevelDiffFrame
	local offset = 3
	if level and level:IsShown() then
		offset = offset + ns.Number(level:GetWidth(), 0)
	end
	marker:SetPoint("LEFT", health, "RIGHT", offset, 0)
end

local function UpdateNameplate(unit)
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	if not nameplate or nameplate:IsForbidden() then
		return
	end
	local related = Quests.db.nameplateIcons and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if related and not Secret(related) then
		local marker = GetMarker(nameplate)
		PlaceMarker(marker, nameplate)
		marker.Text:SetText(QuestProgress(unit) or "")
		marker:Show()
	elseif markers[nameplate] then
		markers[nameplate]:Hide()
	end
end

function Quests:RefreshNameplates()
	for _, nameplate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = nameplate.unitToken or (nameplate.UnitFrame and nameplate.UnitFrame.unit)
		if unit then
			UpdateNameplate(unit)
		elseif markers[nameplate] then
			markers[nameplate]:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Extra button for the usable quest item of the nearest quest
---------------------------------------------------------------------------
local ITEM_INTERVAL = 0.5
local ITEM_MAX_DIST_SQ = 150 * 150 -- yards²: show when the quest area is this close
local itemButton, itemTicker
local PLACEHOLDER_ICON = 134400

_G["BINDING_NAME_CLICK ForeverPlusQuestItemButton:LeftButton"] = L.QUESTS_ITEM_BINDING

-- Index of the quest log entry whose item should be shown, or nil.
local function PickQuestItem()
	local best, bestDist
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local link, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(index)
		local info = link and C_QuestLog.GetInfo(index)
		if info and info.questID and (showWhenComplete or not C_QuestLog.IsComplete(info.questID)) then
			local inRange = IsQuestLogSpecialItemInRange(index)
			if inRange == 1 then
				return index
			end
			local distSq = C_QuestLog.GetDistanceSqToQuest(info.questID)
			if distSq and distSq <= ITEM_MAX_DIST_SQ and (not bestDist or distSq < bestDist) then
				best, bestDist = index, distSq
			end
		end
	end
	return best
end

-- The button is a secure action button: using quest items is reserved for
-- secure code. Item and visibility can only change out of combat.
local function UpdateItemButton()
	local button = itemButton
	local inCombat = InCombatLockdown()
	local index = button.questLogIndex
	if not inCombat then
		index = Quests.db.itemButton and PickQuestItem()
		button.questLogIndex = index
		local link = index and GetQuestLogSpecialItemInfo(index)
		local itemID = link and link:match("item:(%d+)")
		button:SetAttribute("item", itemID and ("item:" .. itemID) or nil)
	end
	if not index then
		if inCombat then
			return
		end
		if Quests.db.itemButton and ns:IsEditModeActive() then
			button.icon:SetTexture(PLACEHOLDER_ICON)
			button.Count:SetText("")
			button:Show()
		else
			button:Hide()
		end
		return
	end
	local _, texture, charges = GetQuestLogSpecialItemInfo(index)
	button.icon:SetTexture(texture)
	button.Count:SetText(charges and charges > 1 and charges or "")
	local start, duration, enable = GetQuestLogSpecialItemCooldown(index)
	if start then
		CooldownFrame_Set(button.cooldown, start, duration, enable)
	end
	-- Red while the target is out of range.
	if IsQuestLogSpecialItemInRange(index) == 0 then
		button.icon:SetVertexColor(1, 0.3, 0.3)
	else
		button.icon:SetVertexColor(1, 1, 1)
	end
	if not inCombat then
		button:Show()
	end
end

local function CreateItemButton()
	local button = CreateFrame("Button", "ForeverPlusQuestItemButton", UIParent, "SecureActionButtonTemplate, ActionButtonTemplate")
	button:SetSize(40, 40)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")
	button:SetScript("OnEnter", function(self)
		if self.questLogIndex then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetQuestLogSpecialItem(self.questLogIndex)
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	itemButton = button
	ns:RegisterEditFrame(button, "QuestItem", L.QUESTS_ITEM_BUTTON, { "CENTER", UIParent, "CENTER", 0, -180 }, UpdateItemButton)
end

function Quests:UpdateItemTicker()
	if self.db.itemButton then
		if not itemButton then
			CreateItemButton()
		end
		itemTicker = itemTicker or C_Timer.NewTicker(ITEM_INTERVAL, UpdateItemButton)
		UpdateItemButton()
	else
		if itemTicker then
			itemTicker:Cancel()
			itemTicker = nil
		end
		if itemButton then
			itemButton:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Quest tracker: order, class quests first, a tab for instance quests and an
-- optional filter for the current region. ForeverPlus remembers which quests
-- the player tracks and shows the matching ones in the chosen order by
-- re-adding the watches (Blizzard's tracker lists them in watch order).
---------------------------------------------------------------------------
local SORT_DELAY = 1
local DISTANCE_INTERVAL = 10
local VERIFY_DELAY = 0.5
local OWN_CHANGE_TIME = 1.5 -- watch list events after our own re-adding are ignored
local SORT_MODES = { "default", "level", "zone", "distance", "name", "progress" }
local INSTANCE_TAGS = { [81] = true, [62] = true, [85] = true, [88] = true, [89] = true }
local MAX_WATCHES = Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES or 25
local sortPending, sortTicker
local ownChangeUntil = 0
local managing = false
local forced = {} -- tracked by the player in this zone despite the region filter
-- Whether a new watch lands at the top; found out from the result.
local addsOnTop = false
local playerClassName = UnitClass("player")

local function TextLess(a, b)
	if strcmputf8i then
		return strcmputf8i(a, b) < 0
	end
	return a:lower() < b:lower()
end

-- Names of all dungeon and raid maps; the quest log files instance quests
-- under the instance's name.
local MAX_MAP_ID = 2500
local instanceNames

local QueueSort

-- Built in slices after the first request; until then quest tags and
-- QuestieDB decide alone, and the tracker sorts again once it is complete.
local function InstanceNames()
	if not instanceNames then
		instanceNames = {}
		ns.RunSliced("Quests: instance names", MAX_MAP_ID, function(mapID)
			local info = C_Map.GetMapInfo(mapID)
			if info and info.mapType == Enum.UIMapType.Dungeon and info.name then
				instanceNames[info.name] = true
			end
		end, function()
			if QueueSort then
				QueueSort()
			end
		end)
	end
	return instanceNames
end

local questHeaders = {} -- questID -> quest log header, filled by QuestFacts

-- Instance quest: QuestieDB (quest zone is an instance, or with the option
-- a quest leading to one), otherwise the quest log header or quest tag.
local function IsInstanceQuest(questID)
	local qdb = ns.QuestieDB
	if qdb.IsDungeonQuest(questID) then
		return true
	end
	if Quests.db.instancePreQuests and qdb.LeadsToDungeon(questID) then
		return true
	end
	local header = questHeaders[questID]
	if header and InstanceNames()[header] then
		return true
	end
	local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
	return tag and INSTANCE_TAGS[tag.tagID] or false
end

local function QuestFacts()
	local facts, zone = {}, ""
	local currentZone = GetZoneText()
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info then
			if info.isHeader then
				zone = info.title or ""
			elseif info.questID then
				local questID = info.questID
				questHeaders[questID] = zone
				local done, total = 0, 0
				for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
					done = done + min(objective.numFulfilled or 0, objective.numRequired or 0)
					total = total + (objective.numRequired or 0)
				end
				local distance, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
				facts[questID] = {
					index = index, level = info.level or 0, title = info.title or "", zone = zone,
					here = zone == currentZone,
					class = zone == playerClassName,
					instance = IsInstanceQuest(questID),
					ready = ns.IsQuestReady(questID, index),
					progress = total > 0 and done / total or 0,
					distance = onContinent and distance or math.huge,
				}
			end
		end
	end
	return facts
end

-- Strict orders: equal keys fall back to the quest log position.
local COMPARE = {
	default = function(a, b)
		return a.index < b.index
	end,
	level = function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.index < b.index
	end,
	zone = function(a, b)
		if a.here ~= b.here then
			return a.here
		end
		if a.zone ~= b.zone then
			return TextLess(a.zone, b.zone)
		end
		return a.index < b.index
	end,
	distance = function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.index < b.index
	end,
	name = function(a, b)
		if a.title ~= b.title then
			return TextLess(a.title, b.title)
		end
		return a.index < b.index
	end,
	progress = function(a, b)
		if a.ready ~= b.ready then
			return a.ready
		end
		if a.progress ~= b.progress then
			return a.progress > b.progress
		end
		return a.index < b.index
	end,
}

local function CurrentWatches(facts)
	local list = {}
	for watch = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(watch)
		if questID and facts[questID] then
			list[#list + 1] = questID
		end
	end
	return list
end

local function SameOrder(a, b, reversed)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[reversed and #b + 1 - i or i] then
			return false
		end
	end
	return true
end

local function WriteWatches(current, sorted)
	ownChangeUntil = GetTime() + OWN_CHANGE_TIME
	for _, questID in ipairs(current) do
		C_QuestLog.RemoveQuestWatch(questID)
	end
	local first, last, step = 1, #sorted, 1
	if addsOnTop then
		first, last, step = #sorted, 1, -1
	end
	for i = first, last, step do
		C_QuestLog.AddQuestWatch(sorted[i])
	end
end

-- Something to manage at all; otherwise Blizzard's tracker stays untouched.
local function IsManaging()
	local db = Quests.db
	return db.trackerSort ~= "default" or db.classFirst or db.instanceTab or db.regionOnly
end

local function WantedList(facts)
	local cdb = Quests.cdb
	if not cdb.watched then
		cdb.watched = {}
		for _, questID in ipairs(CurrentWatches(facts)) do
			cdb.watched[questID] = true
		end
	end
	-- Quests no longer in the log are forgotten (only once the log is loaded).
	if next(facts) then
		for questID in pairs(cdb.watched) do
			if not facts[questID] then
				cdb.watched[questID] = nil
			end
		end
	end
	return cdb.watched
end

local function TabCounts()
	local facts = QuestFacts()
	local world, instance = 0, 0
	for questID in pairs(WantedList(facts)) do
		if facts[questID] then
			if facts[questID].instance then
				instance = instance + 1
			else
				world = world + 1
			end
		end
	end
	return world, instance
end

-- The selected tab, or the other one while the selected tab has no quest:
-- an empty tracker would hide its header and with it the tabs.
local function EffectiveTab()
	local tab = Quests.cdb.trackerTab
	local world, instance = TabCounts()
	if tab == "instance" and instance == 0 then
		return "world"
	elseif tab ~= "instance" and world == 0 and instance > 0 then
		return "instance"
	end
	return tab == "instance" and "instance" or "world"
end

local function Passes(questID, fact, tab)
	local db = Quests.db
	if db.instanceTab then
		if (tab == "instance") ~= fact.instance then
			return false
		end
	end
	if db.regionOnly and not fact.instance and not fact.class and not forced[questID] then
		return fact.here or (C_QuestLog.IsOnMap and C_QuestLog.IsOnMap(questID)) or false
	end
	return true
end

-- Watches that should be shown, in order.
local function DesiredWatches(facts)
	local compare = COMPARE[Quests.db.trackerSort] or COMPARE.default
	local classFirst = Quests.db.classFirst
	local list = {}
	local tab = Quests.db.instanceTab and EffectiveTab()
	for questID in pairs(WantedList(facts)) do
		local fact = facts[questID]
		if fact and Passes(questID, fact, tab) then
			list[#list + 1] = questID
		end
	end
	table.sort(list, function(a, b)
		local fa, fb = facts[a], facts[b]
		if classFirst and fa.class ~= fb.class then
			return fa.class
		end
		return compare(fa, fb)
	end)
	for i = #list, MAX_WATCHES + 1, -1 do
		list[i] = nil
	end
	return list
end

local SortTracker

-- Checks the result once; a reversed list means new watches land on top.
local function VerifyOrder(sorted, retried)
	if InCombatLockdown() then
		return
	end
	local current = CurrentWatches(QuestFacts())
	if not retried and not SameOrder(current, sorted) and SameOrder(current, sorted, true) then
		addsOnTop = not addsOnTop
		WriteWatches(current, sorted)
		C_Timer.After(VERIFY_DELAY, function()
			VerifyOrder(sorted, true)
		end)
	end
end

local UpdateTabs

function SortTracker()
	sortPending = false
	if InCombatLockdown() then
		return
	end
	if UpdateTabs then
		UpdateTabs()
	end
	if not IsManaging() then
		return
	end
	local facts = QuestFacts()
	local current = CurrentWatches(facts)
	local desired = DesiredWatches(facts)
	if SameOrder(current, desired) then
		return
	end
	WriteWatches(current, desired)
	C_Timer.After(VERIFY_DELAY, function()
		VerifyOrder(desired)
	end)
end

function QueueSort()
	if not sortPending and IsManaging() then
		sortPending = true
		C_Timer.After(SORT_DELAY, ns.Measured("Quests: tracker sort", SortTracker))
	end
end

function Quests:QueueTrackerSort()
	QueueSort()
end

-- Player's own tracking changes are remembered; ours are ignored.
local function OnWatchListChanged(_, _, questID, added)
	if GetTime() < ownChangeUntil then
		return
	end
	if questID and IsManaging() then
		local watched = WantedList(QuestFacts())
		if added == nil then
			added = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
		end
		watched[questID] = added and true or nil
		if added then
			forced[questID] = true
			-- A quest tracked from the other tab switches to that tab.
			if Quests.db.instanceTab then
				Quests.cdb.trackerTab = IsInstanceQuest(questID) and "instance" or "world"
			end
		end
	end
	QueueSort()
end

local function OnZoneChanged()
	wipe(forced)
	-- Entering or leaving a dungeon or raid picks the matching tab.
	if Quests.db.instanceTab then
		local inInstance, instanceType = IsInInstance()
		local tab = inInstance and (instanceType == "party" or instanceType == "raid") and "instance" or "world"
		if Quests.lastInstanceState ~= tab then
			Quests.lastInstanceState = tab
			Quests.cdb.trackerTab = tab
		end
	end
	QueueSort()
end

-- Switching everything off shows all tracked quests again in log order.
local function RestoreWatches()
	if InCombatLockdown() or not Quests.cdb.watched then
		return
	end
	local facts = QuestFacts()
	local list = {}
	for questID in pairs(WantedList(facts)) do
		list[#list + 1] = questID
	end
	table.sort(list, function(a, b)
		return facts[a].index < facts[b].index
	end)
	WriteWatches(CurrentWatches(facts), list)
end

function Quests:UpdateTrackerSort(switched)
	local mode = self.db.trackerSort
	if sortTicker then
		sortTicker:Cancel()
		sortTicker = nil
	end
	if mode == "distance" then
		sortTicker = C_Timer.NewTicker(DISTANCE_INTERVAL, QueueSort)
	end
	local now = IsManaging()
	if now then
		-- Switched on in the settings: start from what is tracked right now.
		if switched and not managing then
			self.cdb.watched = nil
		end
		QueueSort()
	elseif managing and switched then
		RestoreWatches()
		self.cdb.watched = nil
	end
	managing = now
	if UpdateTabs then
		UpdateTabs()
	end
end

---------------------------------------------------------------------------
-- Tabs on the tracker header: world quests | instance quests
---------------------------------------------------------------------------
local tabs

function UpdateTabs()
	if not tabs then
		return
	end
	local shown = Quests.db.instanceTab
	tabs.world:SetShown(shown)
	tabs.instance:SetShown(shown)
	if not shown then
		return
	end
	local world, instance = TabCounts()
	local selected = EffectiveTab()
	for key, tab in pairs({ world = tabs.world, instance = tabs.instance }) do
		local count = key == "world" and world or instance
		tab:SetText(("%s (%d)"):format(key == "world" and L.QUESTS_TAB_WORLD or L.QUESTS_TAB_INSTANCE, count))
		tab:SetWidth(tab:GetTextWidth() + 10)
		local color = key == selected and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
		tab:GetFontString():SetTextColor(color:GetRGB())
		tab.Underline:SetShown(key == selected)
	end
end

local function CreateTab(header, key)
	local tab = CreateFrame("Button", nil, header)
	tab:SetHeight(16)
	tab:SetNormalFontObject("GameFontNormalSmall")
	tab:SetText(key)
	tab:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
	tab.Underline = tab:CreateTexture(nil, "ARTWORK")
	tab.Underline:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.8)
	tab.Underline:SetHeight(1)
	tab.Underline:SetPoint("BOTTOMLEFT", 3, 0)
	tab.Underline:SetPoint("BOTTOMRIGHT", -3, 0)
	tab:SetScript("OnClick", function()
		local world, instance = TabCounts()
		if (key == "instance" and instance or world) == 0 then
			ns.Print(key == "instance" and L.QUESTS_TAB_EMPTY_INSTANCE or L.QUESTS_TAB_EMPTY_WORLD)
			return
		end
		Quests.cdb.trackerTab = key
		UpdateTabs()
		SortTracker()
	end)
	return tab
end

local function ShowSortMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L.QUESTS_SORT)
		for _, mode in ipairs(SORT_MODES) do
			root:CreateRadio(L["QUESTS_SORT_" .. mode], function()
				return Quests.db.trackerSort == mode
			end, function()
				Settings.SetValue("ForeverPlus_Quests_trackerSort", mode)
			end)
		end
	end)
end

local function CreateSortButton()
	local header = QuestObjectiveTracker and QuestObjectiveTracker.Header
	local minimize = header and header.MinimizeButton
	if not minimize then
		return
	end
	local button = CreateFrame("Button", nil, header)
	button:SetSize(16, 16)
	button:SetPoint("RIGHT", minimize, "LEFT", -2, 0)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if not icon:SetAtlas("ui-questtrackerbutton-filter") then
		icon:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
	end
	button:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
	button:SetScript("OnClick", ShowSortMenu)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.QUESTS_SORT)
		GameTooltip_AddNormalLine(GameTooltip, L["QUESTS_SORT_" .. Quests.db.trackerSort])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	tabs = { world = CreateTab(header, "world"), instance = CreateTab(header, "instance") }
	tabs.instance:SetPoint("RIGHT", button, "LEFT", -4, 0)
	tabs.world:SetPoint("RIGHT", tabs.instance, "LEFT", -2, 0)
	UpdateTabs()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Forever quests: quests added by Forever carry IDs far above the classic
-- ones (classic data ends at 9665, Forever's new quests start at 76156).
-- They get a star in front of the title or their own title colour, in the
-- quest log and in the tracker. Blizzard rebuilds both lists itself; an
-- option change shows with their next update (no forced refresh, which
-- would run Blizzard's list code from addon code).
---------------------------------------------------------------------------
local FOREVER_FIRST_QUEST = 10000
local FOREVER_COLOR = CreateColor(0.35, 0.8, 1)
local FOREVER_ICON = "|A:auctionhouse-icon-favorite:12:12|a "

local function IsForeverQuest(questID)
	return type(questID) == "number" and questID >= FOREVER_FIRST_QUEST
end

local function MarkMode()
	return Quests.db.foreverMark and Quests.db.foreverMarkStyle or nil
end

local function MarkText(fontString)
	local text = fontString:GetText()
	if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and not text:find(FOREVER_ICON, 1, true) then
		fontString:SetText(FOREVER_ICON .. text)
	end
end

local function RecolorBlock(block)
	if MarkMode() == "COLOR" and IsForeverQuest(block.poiQuestID or block.id) and block.HeaderText then
		block.HeaderText:SetTextColor(FOREVER_COLOR:GetRGB())
	end
end

local hookedBlocks = {}

local function MarkTracker()
	local mode = MarkMode()
	if not mode or not (QuestObjectiveTracker and QuestObjectiveTracker.EnumerateActiveBlocks) then
		return
	end
	QuestObjectiveTracker:EnumerateActiveBlocks(function(block)
		if block.HeaderText and IsForeverQuest(block.poiQuestID or block.id) then
			if mode == "ICON" then
				MarkText(block.HeaderText)
			else
				if not hookedBlocks[block] and block.UpdateHighlight then
					hookedBlocks[block] = true
					hooksecurefunc(block, "UpdateHighlight", RecolorBlock)
				end
				RecolorBlock(block)
			end
		end
	end)
end

local hookedTitles = {}

local function RecolorTitle(button)
	if MarkMode() == "COLOR" and IsForeverQuest(button.questID) and button.Text then
		button.Text:SetTextColor(FOREVER_COLOR:GetRGB())
	end
end

local function MarkQuestLog()
	local mode = MarkMode()
	local pool = mode and QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		if button.Text and IsForeverQuest(button.questID) then
			if mode == "ICON" then
				MarkText(button.Text)
			else
				if not hookedTitles[button] then
					hookedTitles[button] = true
					button:HookScript("OnLeave", RecolorTitle)
				end
				RecolorTitle(button)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quest and gossip window as plain parchment: Blizzard's frame, portrait,
-- background and close button are hidden; parchment, text, scroll bar and
-- buttons stay (Escape still closes).
---------------------------------------------------------------------------
local CHROME = { "NineSlice", "PortraitContainer", "Bg", "TopTileStreaks", "Inset" }

function Quests:UpdateQuestParchment()
	local plain = self.db.questParchment
	for _, frame in ipairs({ QuestFrame, GossipFrame }) do
		for _, key in ipairs(CHROME) do
			local region = frame[key]
			if region and region.SetAlpha then
				region:SetAlpha(plain and 0 or 1)
			end
		end
		if frame.CloseButton then
			frame.CloseButton:SetShown(not plain)
		end
	end
end

function Quests:OnLogin()
	self:UpdateQuestParchment()
	if QuestLogQuests_Update then
		hooksecurefunc("QuestLogQuests_Update", ns.Measured("Quests: Forever marks (log)", MarkQuestLog))
	end
	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", function()
		if QuestObjectiveTracker and QuestObjectiveTracker.Update then
			hooksecurefunc(QuestObjectiveTracker, "Update", ns.Measured("Quests: Forever marks (tracker)", MarkTracker))
		end
	end)
	-- QuestieDB quest chains for pre-quests of instance quests, built in the
	-- background a little after login.
	C_Timer.After(5, function()
		if self.db.instanceTab and self.db.instancePreQuests then
			ns.QuestieDB.BuildChains(QueueSort)
		end
	end)
	self:RegisterEvent("QUEST_LOG_UPDATE", QueueScan)
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit)
		UpdateNameplate(unit)
	end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
		local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
		if nameplate and markers[nameplate] then
			markers[nameplate]:Hide()
		end
	end)
	QueueScan()
	self:UpdateItemTicker()
	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", CreateSortButton)
	self:RegisterEvent("QUEST_ACCEPTED", QueueSort)
	self:RegisterEvent("QUEST_REMOVED", function(_, _, questID)
		if questID and self.cdb.watched then
			self.cdb.watched[questID] = nil
		end
		QueueSort()
	end)
	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED", OnWatchListChanged)
	-- Blizzard sorts the watches by proximity on zone changes.
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneChanged)
	self:RegisterEvent("ZONE_CHANGED", QueueSort)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnZoneChanged)
	self:UpdateTrackerSort()
end

function Quests:OnOptionChanged(key, value)
	if key == "sounds" then
		-- Off silences both; on brings back the defaults if both were silent.
		if not value then
			Settings.SetValue("ForeverPlus_Quests_completeSound", "none")
			Settings.SetValue("ForeverPlus_Quests_progressSound", "none")
		elseif self.db.completeSound == "none" and self.db.progressSound == "none" then
			Settings.SetValue("ForeverPlus_Quests_completeSound", self.defaults.completeSound)
			Settings.SetValue("ForeverPlus_Quests_progressSound", self.defaults.progressSound)
		end
	elseif (key == "completeSound" or key == "progressSound") and value ~= "none" and not self.db.sounds then
		Settings.SetValue("ForeverPlus_Quests_sounds", true)
	elseif key == "questParchment" then
		self:UpdateQuestParchment()
	elseif key == "nameplateIcons" then
		self:RefreshNameplates()
	elseif key == "itemButton" then
		self:UpdateItemTicker()
	elseif key == "trackerSort" or key == "classFirst" or key == "instanceTab" or key == "regionOnly" or key == "instancePreQuests" then
		if self.db.instanceTab and self.db.instancePreQuests then
			ns.QuestieDB.BuildChains(QueueSort)
		end
		self:UpdateTrackerSort(true)
	end
end

local SOUND_CHOICES = {
	{ "peon", L.QUESTS_SOUND_PEON }, { "peonReady", L.QUESTS_SOUND_PEON_READY }, { "complete", L.QUESTS_SOUND_COMPLETE },
	{ "ping", L.QUESTS_SOUND_PING }, { "select", L.QUESTS_SOUND_SELECT }, { "none", L.QUESTS_SOUND_NONE },
}

Quests.options = {
	{ type = "header", name = L.QUESTS_SOUNDS },
	{ key = "sounds", type = "toggle", name = L.QUESTS_SOUNDS_ENABLE, desc = L.QUESTS_SOUNDS_ENABLE_DESC },
	{ key = "completeSound", type = "dropdown", name = L.QUESTS_COMPLETE_SOUND, desc = L.QUESTS_COMPLETE_SOUND_DESC, values = SOUND_CHOICES, parent = "sounds" },
	{ type = "button", name = L.QUESTS_TEST_COMPLETE, text = L.QUESTS_TEST, func = function()
		Play(Quests.db.completeSound)
	end },
	{ key = "progressSound", type = "dropdown", name = L.QUESTS_PROGRESS_SOUND, desc = L.QUESTS_PROGRESS_SOUND_DESC, values = SOUND_CHOICES, parent = "sounds" },
	{ type = "button", name = L.QUESTS_TEST_PROGRESS, text = L.QUESTS_TEST, func = function()
		Play(Quests.db.progressSound)
	end },
	{ type = "header", name = L.QUESTS_TRACKER },
	{ key = "trackerSort", type = "dropdown", name = L.QUESTS_SORT, desc = L.QUESTS_SORT_DESC, values = function()
		local values = {}
		for _, mode in ipairs(SORT_MODES) do
			values[#values + 1] = { mode, L["QUESTS_SORT_" .. mode] }
		end
		return values
	end },
	{ key = "classFirst", type = "toggle", name = L.QUESTS_CLASS_FIRST, desc = L.QUESTS_CLASS_FIRST_DESC },
	{ key = "instanceTab", type = "toggle", name = L.QUESTS_INSTANCE_TAB, desc = L.QUESTS_INSTANCE_TAB_DESC },
	{ key = "instancePreQuests", type = "toggle", name = L.QUESTS_INSTANCE_PREQUESTS, desc = L.QUESTS_INSTANCE_PREQUESTS_DESC, parent = "instanceTab" },
	{ key = "regionOnly", type = "toggle", name = L.QUESTS_REGION_ONLY, desc = L.QUESTS_REGION_ONLY_DESC },
	{ type = "header", name = L.QUESTS_FOREVER_HEADER },
	{ key = "foreverMark", type = "toggle", name = L.QUESTS_FOREVER_MARK, desc = L.QUESTS_FOREVER_MARK_DESC },
	{ key = "foreverMarkStyle", type = "dropdown", name = L.QUESTS_FOREVER_STYLE, parent = "foreverMark", values = {
		{ "ICON", L.QUESTS_FOREVER_STYLE_ICON }, { "COLOR", L.QUESTS_FOREVER_STYLE_COLOR },
	} },
	{ type = "header", name = L.QUESTS_WINDOW },
	{ key = "questParchment", type = "toggle", name = L.QUESTS_PARCHMENT, desc = L.QUESTS_PARCHMENT_DESC },
	{ type = "header", name = L.QUESTS_ITEM_BUTTON },
	{ key = "itemButton", type = "toggle", name = L.QUESTS_ITEM_BUTTON_OPT, desc = L.QUESTS_ITEM_BUTTON_DESC },
	{ type = "header", name = L.QUESTS_NAMEPLATES },
	{ key = "nameplateIcons", type = "toggle", name = L.QUESTS_NAMEPLATE_ICONS, desc = L.QUESTS_NAMEPLATE_ICONS_DESC },
}

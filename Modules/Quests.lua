-- Quests: sounds on quest progress and completion, quest icon with progress
-- on the nameplates of units related to an active quest.
local _, ns = ...
local L = ns.L

local Quests = ns:NewModule("Quests", {
	title = L.QUESTS_TITLE,
	order = 5.2,
	defaults = {
		completeSound = "peon",
		progressSound = "peonReady",
		nameplateIcons = true,
		itemButton = true,
		trackerSort = "default",
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
		C_Timer.After(SCAN_DELAY, ScanQuests)
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

local function UpdateNameplate(unit)
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	if not nameplate or nameplate:IsForbidden() then
		return
	end
	local related = Quests.db.nameplateIcons and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if related and not Secret(related) then
		local marker = GetMarker(nameplate)
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
-- Quest tracker order: watched quests are re-added in the chosen order
---------------------------------------------------------------------------
local SORT_DELAY = 1
local DISTANCE_INTERVAL = 10
local VERIFY_DELAY = 0.5
local OWN_CHANGE_TIME = 1.5 -- watch list events after our own re-adding are ignored
local SORT_MODES = { "default", "level", "zone", "distance", "name", "progress" }
local sortPending, sortTicker
local ownChangeUntil = 0
-- Whether a new watch lands at the top; found out from the result.
local addsOnTop = false

local function TextLess(a, b)
	if strcmputf8i then
		return strcmputf8i(a, b) < 0
	end
	return a:lower() < b:lower()
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
				local done, total = 0, 0
				for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
					done = done + min(objective.numFulfilled or 0, objective.numRequired or 0)
					total = total + (objective.numRequired or 0)
				end
				local distance, onContinent = C_QuestLog.GetDistanceSqToQuest(info.questID)
				facts[info.questID] = {
					index = index, level = info.level or 0, title = info.title or "", zone = zone,
					here = zone == currentZone,
					ready = ns.IsQuestReady(info.questID, index),
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

function SortTracker()
	sortPending = false
	local compare = COMPARE[Quests.db.trackerSort]
	if not compare or InCombatLockdown() then
		return
	end
	local facts = QuestFacts()
	local current = CurrentWatches(facts)
	local sorted = CopyTable(current)
	table.sort(sorted, function(a, b)
		return compare(facts[a], facts[b])
	end)
	if SameOrder(current, sorted) then
		return
	end
	WriteWatches(current, sorted)
	C_Timer.After(VERIFY_DELAY, function()
		VerifyOrder(sorted)
	end)
end

local function QueueSort()
	if not sortPending and Quests.db.trackerSort ~= "default" then
		sortPending = true
		C_Timer.After(SORT_DELAY, SortTracker)
	end
end

function Quests:QueueTrackerSort()
	QueueSort()
end

local function OnWatchListChanged()
	if GetTime() >= ownChangeUntil then
		QueueSort()
	end
end

-- "default" leaves Blizzard's order alone; only switching back to it from
-- another mode restores the quest log order once.
function Quests:UpdateTrackerSort(switched)
	local mode = self.db.trackerSort
	if sortTicker then
		sortTicker:Cancel()
		sortTicker = nil
	end
	if mode == "distance" then
		sortTicker = C_Timer.NewTicker(DISTANCE_INTERVAL, QueueSort)
	end
	if mode ~= "default" then
		QueueSort()
	elseif switched then
		SortTracker()
	end
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
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Quests:OnLogin()
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
	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED", OnWatchListChanged)
	-- Blizzard sorts the watches by proximity on zone changes.
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", QueueSort)
	self:RegisterEvent("ZONE_CHANGED", QueueSort)
	self:UpdateTrackerSort()
end

function Quests:OnOptionChanged(key)
	if key == "nameplateIcons" then
		self:RefreshNameplates()
	elseif key == "itemButton" then
		self:UpdateItemTicker()
	elseif key == "trackerSort" then
		self:UpdateTrackerSort(true)
	end
end

local SOUND_CHOICES = {
	{ "peon", L.QUESTS_SOUND_PEON }, { "peonReady", L.QUESTS_SOUND_PEON_READY }, { "complete", L.QUESTS_SOUND_COMPLETE },
	{ "ping", L.QUESTS_SOUND_PING }, { "select", L.QUESTS_SOUND_SELECT }, { "none", L.QUESTS_SOUND_NONE },
}

Quests.options = {
	{ type = "header", name = L.QUESTS_SOUNDS },
	{ key = "completeSound", type = "dropdown", name = L.QUESTS_COMPLETE_SOUND, desc = L.QUESTS_COMPLETE_SOUND_DESC, values = SOUND_CHOICES },
	{ type = "button", name = L.QUESTS_TEST_COMPLETE, text = L.QUESTS_TEST, func = function()
		Play(Quests.db.completeSound)
	end },
	{ key = "progressSound", type = "dropdown", name = L.QUESTS_PROGRESS_SOUND, desc = L.QUESTS_PROGRESS_SOUND_DESC, values = SOUND_CHOICES },
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
	{ type = "header", name = L.QUESTS_ITEM_BUTTON },
	{ key = "itemButton", type = "toggle", name = L.QUESTS_ITEM_BUTTON_OPT, desc = L.QUESTS_ITEM_BUTTON_DESC },
	{ type = "header", name = L.QUESTS_NAMEPLATES },
	{ key = "nameplateIcons", type = "toggle", name = L.QUESTS_NAMEPLATE_ICONS, desc = L.QUESTS_NAMEPLATE_ICONS_DESC },
}

-- Quests: sounds on quest progress and completion, quest icon with progress
-- on the nameplates of units related to an active quest.
local _, ns = ...
local L = ns.L

local Quests = ns:NewModule("Quests", {
	title = L.QUESTS_TITLE,
	order = 5.2,
	defaults = {
		completeSound = "peon",
		progressSound = "ping",
		nameplateIcons = true,
		itemButton = true,
	},
})

local SCAN_DELAY = 0.3
local PEON_DONE = [[Sound\Creature\Peon\PeonBuildingComplete1.ogg]]

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
			local complete = C_QuestLog.IsComplete(questID) and true or false
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

local function UpdateItemButton()
	local button = itemButton
	local index = Quests.db.itemButton and PickQuestItem()
	button.questLogIndex = index
	if not index then
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
	button:Show()
end

local function CreateItemButton()
	local button = CreateFrame("Button", "ForeverPlusQuestItemButton", UIParent, "ActionButtonTemplate")
	button:SetSize(40, 40)
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnClick", function(self)
		local index = self.questLogIndex
		if not index then
			return
		end
		if IsModifiedClick("CHATLINK") then
			ChatFrameUtil.InsertLink((GetQuestLogSpecialItemInfo(index)))
		else
			UseQuestLogSpecialItem(index)
		end
	end)
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
end

function Quests:OnOptionChanged(key)
	if key == "nameplateIcons" then
		self:RefreshNameplates()
	elseif key == "itemButton" then
		self:UpdateItemTicker()
	end
end

local SOUND_CHOICES = {
	{ "peon", L.QUESTS_SOUND_PEON }, { "complete", L.QUESTS_SOUND_COMPLETE },
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
	{ type = "header", name = L.QUESTS_ITEM_BUTTON },
	{ key = "itemButton", type = "toggle", name = L.QUESTS_ITEM_BUTTON_OPT, desc = L.QUESTS_ITEM_BUTTON_DESC },
	{ type = "header", name = L.QUESTS_NAMEPLATES },
	{ key = "nameplateIcons", type = "toggle", name = L.QUESTS_NAMEPLATE_ICONS, desc = L.QUESTS_NAMEPLATE_ICONS_DESC },
}

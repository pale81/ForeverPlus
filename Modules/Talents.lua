-- Talents: spells by level and talent builds (save, export, import, apply)
-- on Blizzard's talent window. Builds use Blizzard's loadout string format.
local _, ns = ...
local L = ns.L

local Talents = ns:NewModule("Talents", {
	title = L.TALENTS_TITLE,
	order = 8.5,
	defaults = {
		enabled = true,
		planner = true,
		builds = {}, -- classFile -> { { name =, text = }, ... }
		plans = {}, -- "classFile:specID" -> { [nodeID] = planned ranks }
		trainer = {}, -- classFile -> { { name, rank, icon, level }, ... } from the class trainer
	},
	charDefaults = {
		seenSpells = {}, -- learnable spells already shown to the player
	},
})

local MAX_APPLY_PASSES = 10
local _, playerClass = UnitClass("player")

---------------------------------------------------------------------------
-- Trainer spells: what the game lists per level and the spell book, plus the
-- class trainer's list (stored at each visit), which also holds the spells
-- of later levels.
---------------------------------------------------------------------------
local function IsKnown(spellID)
	return C_SpellBook.IsSpellKnown(spellID) or (IsPlayerSpell and IsPlayerSpell(spellID))
end

local function SpellKey(name, rank)
	return (name or "") .. "|" .. (rank or "")
end

local function SpellBookLines()
	local lines = {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID and not info.isGuild then
			lines[#lines + 1] = info
		end
	end
	return lines
end

-- name|rank of every spell the player knows.
local function KnownSpellKeys()
	local known = {}
	local bank = Enum.SpellBookSpellBank.Player
	for _, info in ipairs(SpellBookLines()) do
		for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
			local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
			if item and item.spellID and IsKnown(item.spellID) then
				known[SpellKey(item.name, item.subName)] = true
			end
		end
	end
	return known
end

local function TrainerList()
	local lists = Talents.db.trainer
	lists[playerClass] = lists[playerClass] or {}
	return lists[playerClass]
end

-- Reads the whole service list of a class trainer, all filters switched on.
local TRAINER_FILTERS = { "available", "unavailable", "used" }

local function ScanTrainer()
	local trainerType = C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType()
	if trainerType == Enum.TrainerType.Tradeskills or trainerType == Enum.TrainerType.Pet then
		return
	end
	local classLines = {}
	for _, info in ipairs(SpellBookLines()) do
		classLines[info.name] = true
	end
	local saved = {}
	for _, filter in ipairs(TRAINER_FILTERS) do
		saved[filter] = GetTrainerServiceTypeFilter(filter)
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, true)
		end
	end
	local list = TrainerList()
	local found = {}
	for index = 1, GetNumTrainerServices() do
		local name, serviceType, icon, level, rank = GetTrainerServiceInfo(index)
		local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(index)
		if name and serviceType ~= "header" and level and level > 0 and (not line or classLines[line]) then
			found[#found + 1] = { name = name, rank = rank ~= "" and rank or nil, icon = icon, level = level }
		end
	end
	for _, filter in ipairs(TRAINER_FILTERS) do
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, false)
		end
	end
	if #found > 0 then
		wipe(list)
		for i, entry in ipairs(found) do
			list[i] = entry
		end
	end
end

-- All entries: { key, level, name, rank, icon, known }, by level.
local function CollectSpells()
	local byLevel, seen = {}, {}
	local function Add(level, key, name, rank, icon, known)
		if level and level > 0 and not seen[key] then
			seen[key] = true
			byLevel[level] = byLevel[level] or {}
			tinsert(byLevel[level], { key = key, level = level, name = name, rank = rank, icon = icon, known = known })
		end
	end
	local function AddSpell(level, spellID)
		if not spellID then
			return
		end
		local name = C_Spell.GetSpellName(spellID) or ("spell:" .. spellID)
		local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
		rank = rank ~= "" and rank or nil
		Add(level, SpellKey(name, rank), name, rank, C_Spell.GetSpellTexture(spellID), IsKnown(spellID))
	end
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	for level = 1, maxLevel do
		for _, spellID in ipairs(C_SpellBook.GetCurrentLevelSpells(level) or {}) do
			AddSpell(level, spellID)
		end
	end
	local bank = Enum.SpellBookSpellBank.Player
	for _, info in ipairs(SpellBookLines()) do
		for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
			local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
			if item and item.spellID then
				AddSpell(C_SpellBook.GetSpellBookItemLevelLearned(index, bank), item.spellID)
			end
		end
	end
	local known = KnownSpellKeys()
	for _, entry in ipairs(TrainerList()) do
		local key = SpellKey(entry.name, entry.rank)
		Add(entry.level, key, entry.name, entry.rank, entry.icon, known[key] or false)
	end
	return byLevel
end

-- Spells the player could learn at the trainer right now.
local function LearnableSpells(byLevel)
	local playerLevel = UnitLevel("player")
	local list = {}
	for level, spells in pairs(byLevel or CollectSpells()) do
		if level <= playerLevel then
			for _, entry in ipairs(spells) do
				if not entry.known then
					list[#list + 1] = entry.key
				end
			end
		end
	end
	return list
end

local spellsButton

-- The button sparkles while there is something new to learn.
local function UpdateSpellsGlow()
	if not spellsButton then
		return
	end
	local seen = Talents.cdb.seenSpells
	local new = false
	for _, key in ipairs(LearnableSpells()) do
		if not seen[key] then
			new = true
			break
		end
	end
	spellsButton.Alert:SetShown(new and Talents.db.enabled)
end

local function ShowSpellsByLevel()
	local byLevel = CollectSpells()
	local seen = Talents.cdb.seenSpells
	for _, key in ipairs(LearnableSpells(byLevel)) do
		seen[key] = true
	end
	UpdateSpellsGlow()
	local levels = {}
	for level in pairs(byLevel) do
		levels[#levels + 1] = level
	end
	table.sort(levels)
	local playerLevel = UnitLevel("player")
	local lines = {}
	if #TrainerList() == 0 then
		lines[1] = L.TALENTS_VISIT_TRAINER
		lines[2] = " "
	end
	for _, level in ipairs(levels) do
		local color = level <= playerLevel and NORMAL_FONT_COLOR or WHITE_FONT_COLOR
		lines[#lines + 1] = color:WrapTextInColorCode(L.TALENTS_LEVEL:format(level))
		table.sort(byLevel[level], function(a, b)
			return a.name < b.name
		end)
		for _, entry in ipairs(byLevel[level]) do
			local name = entry.rank and ("%s (%s)"):format(entry.name, entry.rank) or entry.name
			local text = ("   |T%s:16:16|t %s"):format(entry.icon or 134400, name)
			lines[#lines + 1] = entry.known and GRAY_FONT_COLOR:WrapTextInColorCode(text) or text
		end
		lines[#lines + 1] = " "
	end
	if #levels == 0 then
		lines[#lines + 1] = L.TALENTS_NO_SPELLS
	end
	ns.ShowTextWindow("Spells", L.TALENTS_SPELLS, table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
local function TalentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local ApplyPlan, ClearPlan -- planner, defined below

local function ClassBuilds()
	local builds = Talents.db.builds
	builds[playerClass] = builds[playerClass] or {}
	return builds[playerClass]
end

-- Parses a loadout string into node purchases using Blizzard's own reader.
local function ParseBuild(frame, text)
	local stream = ExportUtil.MakeImportDataStream(text)
	local valid, version, specID = frame:ReadLoadoutHeader(stream)
	if not valid then
		return nil, L.TALENTS_ERROR_STRING
	end
	if version ~= C_Traits.GetLoadoutSerializationVersion() then
		return nil, L.TALENTS_ERROR_VERSION
	end
	if specID ~= PlayerUtil.GetCurrentSpecID() then
		return nil, L.TALENTS_ERROR_SPEC
	end
	local configID, treeID = frame:GetConfigID(), frame:GetTreeInfo().ID
	local content = frame:ReadLoadoutContent(stream, treeID)
	return frame:ConvertToImportLoadoutEntryInfo(configID, treeID, content), nil, configID, treeID
end

-- Buys ranks until every node has its wanted ranks or nothing changes;
-- prerequisites need several passes. Nodes higher up the tree go first.
local function PurchaseTowards(configID, wanted, selection)
	local order = {}
	for nodeID in pairs(wanted) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		order[#order + 1] = { nodeID = nodeID, y = node and node.posY or 0, x = node and node.posX or 0 }
	end
	table.sort(order, function(a, b)
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.x < b.x
	end)
	for _ = 1, MAX_APPLY_PASSES do
		local progress = false
		for _, entry in ipairs(order) do
			local nodeID, ranks = entry.nodeID, wanted[entry.nodeID]
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			if node and node.ranksPurchased < ranks then
				if node.type == Enum.TraitNodeType.Selection and selection and selection[nodeID] then
					if C_Traits.SetSelection(configID, nodeID, selection[nodeID]) then
						progress = true
					end
				else
					while node.ranksPurchased < ranks and C_Traits.PurchaseRank(configID, nodeID) do
						progress = true
						node = C_Traits.GetNodeInfo(configID, nodeID)
					end
				end
			end
		end
		if not progress then
			break
		end
	end
end

-- Stages the build in the talent tree; Blizzard's apply button commits it.
local function ApplyBuild(build)
	local frame = TalentsFrame()
	if InCombatLockdown() or not frame or not frame:GetConfigID() then
		ns.Print(L.TALENTS_ERROR_FRAME)
		return
	end
	local entries, err, configID, treeID = ParseBuild(frame, build.text)
	if not entries then
		ns.Print(err)
		return
	end
	-- Ranks per node; tiered nodes come as several entries.
	local wanted, selection = {}, {}
	for _, entry in ipairs(entries) do
		if entry.ranksPurchased and entry.ranksPurchased > 0 then
			wanted[entry.nodeID] = (wanted[entry.nodeID] or 0) + entry.ranksPurchased
			selection[entry.nodeID] = selection[entry.nodeID] or entry.selectionEntryID
		end
	end
	C_Traits.ResetTree(configID, treeID)
	PurchaseTowards(configID, wanted, selection)
	ns.Print(L.TALENTS_APPLIED, build.name)
end

local function SaveBuild(name, text)
	if name == "" then
		name = date("%d.%m. %H:%M")
	end
	local builds = ClassBuilds()
	for _, build in ipairs(builds) do
		if build.name == name then
			build.text = text
			return
		end
	end
	tinsert(builds, { name = name, text = text })
end

local function SaveCurrent()
	local frame = TalentsFrame()
	if not frame or not frame:GetConfigID() then
		return
	end
	local text = frame:GetLoadoutExportString()
	ns.ShowEditWindow("BuildName", L.TALENTS_SAVE, "", SAVE, function(name)
		SaveBuild(name, text)
	end, L.TALENTS_NAME_HINT)
end

local function ImportBuild()
	ns.ShowEditWindow("BuildImport", L.TALENTS_IMPORT, "", L.TALENTS_IMPORT, function(text)
		if text == "" then
			return
		end
		local frame = TalentsFrame()
		if frame and frame:GetConfigID() then
			local entries, err = ParseBuild(frame, text)
			if not entries then
				ns.Print(err)
				return
			end
		end
		ns.ShowEditWindow("BuildName", L.TALENTS_SAVE, "", SAVE, function(name)
			SaveBuild(name, text)
		end, L.TALENTS_NAME_HINT)
	end, L.TALENTS_IMPORT_HINT)
end

local function ShowBuildMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L.TALENTS_BUILDS)
		root:CreateButton(L.TALENTS_SAVE, SaveCurrent)
		root:CreateButton(L.TALENTS_IMPORT, ImportBuild)
		if Talents.db.planner then
			root:CreateDivider()
			root:CreateTitle(L.TALENTS_PLAN)
			root:CreateButton(L.TALENTS_PLAN_APPLY, ApplyPlan)
			root:CreateButton(L.TALENTS_PLAN_CLEAR, ClearPlan)
		end
		local builds = ClassBuilds()
		if #builds > 0 then
			root:CreateDivider()
		end
		for index, build in ipairs(builds) do
			local sub = root:CreateButton(build.name)
			sub:CreateButton(L.TALENTS_APPLY, function()
				ApplyBuild(build)
			end)
			sub:CreateButton(L.TALENTS_EXPORT, function()
				ns.ShowEditWindow("BuildExport", build.name, build.text, CLOSE, nil, L.TALENTS_EXPORT_HINT)
			end)
			sub:CreateButton(DELETE, function()
				tremove(builds, index)
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Planner: right-click plans a rank (blue), Shift + right-click removes it.
-- Plans go up to the points of level 60 and are bought with "apply plan".
---------------------------------------------------------------------------
local PLAN_COLOR = CreateColor(0.3, 0.65, 1)
local FIRST_TALENT_LEVEL, PLAN_MAX_LEVEL = 10, 60
local PLAN_POINTS = PLAN_MAX_LEVEL - FIRST_TALENT_LEVEL + 1
local planCounter

local function CurrentPlan()
	local key = ("%s:%s"):format(playerClass, PlayerUtil.GetCurrentSpecID() or 0)
	local plans = Talents.db.plans
	plans[key] = plans[key] or {}
	return plans[key]
end

local function PlannedPoints(plan)
	local total = 0
	for _, ranks in pairs(plan) do
		total = total + ranks
	end
	return total
end

local function PlanOverlay(button)
	local overlay = button.fpPlan
	if not overlay then
		overlay = {}
		overlay.Tint = button:CreateTexture(nil, "OVERLAY", nil, 6)
		overlay.Tint:SetAllPoints(button.Icon or button)
		overlay.Tint:SetColorTexture(PLAN_COLOR.r, PLAN_COLOR.g, PLAN_COLOR.b, 0.4)
		overlay.Tint:SetBlendMode("ADD")
		-- Above the button, so Blizzard's own rank number stays visible.
		overlay.Text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		overlay.Text:SetPoint("BOTTOM", button, "TOP", 0, -6)
		overlay.Text:SetTextColor(PLAN_COLOR:GetRGB())
		button.fpPlan = overlay
	end
	return overlay
end

-- Tooltip of a planned talent: the values of the planned rank below
-- Blizzard's own text, so the effect of the plan is visible while planning.
local function AddPlanTooltip(button)
	if not (Talents.db.enabled and Talents.db.planner) or GameTooltip:GetOwner() ~= button then
		return
	end
	local frame = TalentsFrame()
	local configID = frame and frame:GetConfigID()
	local nodeID = button.GetNodeID and button:GetNodeID()
	local planned = nodeID and CurrentPlan()[nodeID]
	local node = planned and configID and C_Traits.GetNodeInfo(configID, nodeID)
	if not node or planned <= node.ranksPurchased then
		return
	end
	local entry = node.activeEntry or node.nextEntry
	local entryID = entry and entry.entryID or (node.entryIDs and node.entryIDs[1])
	if not entryID then
		return
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_PLAN_RANK:format(planned, node.maxRanks), PLAN_COLOR)
	if GameTooltip.AppendInfo then
		GameTooltip:AppendInfo("GetTraitEntry", entryID, planned)
	else
		GameTooltip_AddHighlightLine(GameTooltip, C_Traits.GetTraitDescription(entryID, planned), true)
	end
	GameTooltip:Show()
end

local tooltipHooked = {}

local function HookPlanTooltip(button)
	if not tooltipHooked[button] and button.SetTooltipInternal then
		tooltipHooked[button] = true
		hooksecurefunc(button, "SetTooltipInternal", AddPlanTooltip)
	end
end

local function UpdatePlan()
	local frame = TalentsFrame()
	if not frame or not frame:IsVisible() or not frame.EnumerateAllTalentButtons then
		return
	end
	local configID = frame:GetConfigID()
	local plan = CurrentPlan()
	local enabled = Talents.db.enabled and Talents.db.planner
	for button in frame:EnumerateAllTalentButtons() do
		HookPlanTooltip(button)
		local nodeID = button.GetNodeID and button:GetNodeID()
		local planned = enabled and nodeID and plan[nodeID]
		if planned or button.fpPlan then
			local overlay = PlanOverlay(button)
			local node = planned and configID and C_Traits.GetNodeInfo(configID, nodeID)
			if node then
				overlay.Text:SetFormattedText("%d/%d", planned, node.maxRanks)
				overlay.Text:Show()
				overlay.Tint:SetShown(planned > node.ranksPurchased)
			else
				overlay.Text:Hide()
				overlay.Tint:Hide()
			end
		end
	end
	if planCounter then
		local points = PlannedPoints(plan)
		planCounter:SetShown(enabled and points > 0)
		planCounter:SetText(L.TALENTS_PLAN_COUNTER:format(points, PLAN_POINTS, FIRST_TALENT_LEVEL - 1 + max(points, 1)))
	end
end

local updatePending = false
local function QueuePlanUpdate()
	if not updatePending then
		updatePending = true
		C_Timer.After(0, function()
			updatePending = false
			UpdatePlan()
		end)
	end
end

local function OnTalentClick(_, button, mouseButton)
	if mouseButton ~= "RightButton" or IsControlKeyDown() or not (Talents.db.enabled and Talents.db.planner) then
		return
	end
	local frame = TalentsFrame()
	local nodeID = button.GetNodeID and button:GetNodeID()
	local configID = frame and frame:GetConfigID()
	local node = nodeID and configID and C_Traits.GetNodeInfo(configID, nodeID)
	if not node or not node.maxRanks or node.maxRanks == 0 then
		return
	end
	local plan = CurrentPlan()
	local planned = plan[nodeID] or 0
	if IsShiftKeyDown() then
		planned = planned - 1
	elseif button.CanRefundRank and button:CanRefundRank() then
		return -- Blizzard refunds a staged rank with this click
	elseif planned < node.maxRanks and PlannedPoints(plan) < PLAN_POINTS then
		planned = planned + 1
	end
	plan[nodeID] = planned > 0 and planned or nil
	QueuePlanUpdate()
	-- Rebuild the open tooltip with the new planned rank.
	if GameTooltip:GetOwner() == button and button.SetTooltipInternal then
		HookPlanTooltip(button)
		button:SetTooltipInternal()
	end
end

function ApplyPlan()
	local frame = TalentsFrame()
	local configID = frame and frame:GetConfigID()
	if InCombatLockdown() or not configID then
		ns.Print(L.TALENTS_ERROR_FRAME)
		return
	end
	PurchaseTowards(configID, CurrentPlan())
	QueuePlanUpdate()
end

function ClearPlan()
	wipe(CurrentPlan())
	QueuePlanUpdate()
end

local function SetupPlanner(frame)
	planCounter = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local anchor = frame.ClassCurrencyDisplay or frame
	planCounter:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
	planCounter:SetTextColor(PLAN_COLOR:GetRGB())
	planCounter:Hide()
	EventRegistry:RegisterCallback("TalentButton.OnClick", OnTalentClick, Talents)
	frame:HookScript("OnShow", QueuePlanUpdate)
	if frame.SetTab then
		hooksecurefunc(frame, "SetTab", QueuePlanUpdate)
	end
	for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
		Talents:RegisterEvent(event, QueuePlanUpdate)
	end
end

---------------------------------------------------------------------------
-- Buttons below the talent window
---------------------------------------------------------------------------
local buttons

local function CreateButtons()
	local parent = PlayerSpellsFrame
	local builds = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	builds:SetSize(120, 22)
	builds:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -20, -2)
	builds:SetText(L.TALENTS_BUILDS)
	builds:SetScript("OnClick", ShowBuildMenu)

	local spells = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	spells:SetSize(150, 22)
	spells:SetPoint("RIGHT", builds, "LEFT", -6, 0)
	spells:SetText(L.TALENTS_SPELLS)
	spells:SetScript("OnClick", ShowSpellsByLevel)
	-- Spell book icon left of the button carries the spell alert sparkle.
	local icon = spells:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("RIGHT", spells, "LEFT", -4, 0)
	icon:SetTexture(133741)
	local alert = CreateFrame("Frame", nil, spells, "ActionButtonSpellAlertTemplate")
	alert:SetSize(22 * 1.4, 22 * 1.4)
	alert:SetPoint("CENTER", icon, "CENTER")
	alert.animationPlaying = true
	alert:Hide()
	spells.Alert = alert
	spellsButton = spells
	buttons = { builds, spells }
end

function Talents:Update()
	for _, button in ipairs(buttons or {}) do
		button:SetShown(self.db.enabled)
	end
	UpdateSpellsGlow()
end

local glowPending = false
local function QueueGlowUpdate()
	if not glowPending then
		glowPending = true
		C_Timer.After(1, function()
			glowPending = false
			UpdateSpellsGlow()
		end)
	end
end

function Talents:OnLogin()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		if PlayerSpellsFrame then
			CreateButtons()
			self:Update()
			PlayerSpellsFrame:HookScript("OnShow", UpdateSpellsGlow)
			if TalentsFrame() then
				SetupPlanner(TalentsFrame())
			end
		end
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", QueueGlowUpdate)
	self:RegisterEvent("TRAINER_SHOW", function()
		C_Timer.After(0.3, function()
			ScanTrainer()
			QueueGlowUpdate()
		end)
	end)
	self:RegisterEvent("SPELLS_CHANGED", QueueGlowUpdate)
end

function Talents:OnOptionChanged()
	self:Update()
	QueuePlanUpdate()
end

Talents.options = {
	{ key = "enabled", type = "toggle", name = L.TALENTS_ENABLE, desc = L.TALENTS_ENABLE_DESC },
	{ key = "planner", type = "toggle", name = L.TALENTS_PLANNER, desc = L.TALENTS_PLANNER_DESC },
}

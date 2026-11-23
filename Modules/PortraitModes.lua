-- Shift-wheel mode switcher on the player portrait with left-click toggle
-- and a right-click menu supporting drag-and-drop reassignment between modes.
local _, ns = ...
local L = ns.L

local PortraitModes = {}
ns.PortraitModes = PortraitModes

local MEDIA = "Interface\\AddOns\\ForeverPlus\\Media\\"
local ROUND_MASK = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

-- Slot 1 is always the standard Blizzard portrait; slots 2..5 are clickable mode emblems.
local MODES = {
	{ key = "normal" },
	{ key = "wanderlust", name = L.WANDERLUST_TITLE, short = L.WANDERLUST_TITLE, icon = MEDIA .. "PortraitModeWanderlust" },
	{ key = "angler", name = L.HELPERS_FISHING_MODE, short = L.PORTRAIT_MODE_ANGLER_SHORT, icon = MEDIA .. "PortraitModeAngler" },
	{ key = "rp", name = L.PORTRAIT_MODE_RP, short = L.PORTRAIT_MODE_RP_SHORT, icon = MEDIA .. "PortraitModeRP" },
	{ key = "berserker", name = L.PORTRAIT_MODE_BERSERKER, short = L.PORTRAIT_MODE_BERSERKER_SHORT, icon = MEDIA .. "PortraitModeBerserker" },
}
local MODE_BY_KEY = {}
for index, mode in ipairs(MODES) do
	mode.index = index
	MODE_BY_KEY[mode.key] = mode
end
local SELECTABLE_MODES = { MODES[2], MODES[3], MODES[4], MODES[5] }

local function ModuleOn(moduleName, key)
	local mod = ns:GetModule(moduleName)
	return mod and mod.db and mod.db[key] and true or false
end

local function SetModuleOn(moduleName, key, value)
	ns.SetOption(moduleName, key, value and true or false)
end

-- Draggable feature blocks that can belong to any of the four modes.
local FEATURES = {
	{
		key = "wanderlust",
		defaultMode = "wanderlust",
		name = L.WANDERLUST_TITLE,
		desc = L.WANDERLUST_DESC,
		modules = { Wanderlust = true },
		isOn = function() return ModuleOn("Wanderlust", "enabled") end,
		setOn = function(on) SetModuleOn("Wanderlust", "enabled", on) end,
		subOptions = {
			{ module = "Wanderlust", key = "minimapMouseover", name = L.WANDERLUST_MINIMAP, desc = L.WANDERLUST_MINIMAP_DESC },
			{ module = "Wanderlust", key = "hoverText", name = L.WANDERLUST_HOVER_TEXT, desc = L.WANDERLUST_HOVER_TEXT_DESC },
			{ module = "Wanderlust", key = "showChat", name = L.WANDERLUST_CHAT, desc = L.WANDERLUST_CHAT_DESC },
			{ module = "Wanderlust", key = "showBags", name = L.WANDERLUST_BAGS, desc = L.WANDERLUST_BAGS_DESC },
			{ module = "Wanderlust", key = "showBubbles", name = L.WANDERLUST_BUBBLES, desc = L.WANDERLUST_BUBBLES_DESC },
			{ module = "Wanderlust", key = "hideTeleports", name = L.WANDERLUST_TELEPORTS, desc = L.WANDERLUST_TELEPORTS_DESC },
			{ module = "Wanderlust", key = "showOnTarget", name = L.WANDERLUST_TARGET, desc = L.WANDERLUST_TARGET_DESC },
			{ module = "Wanderlust", key = "showProfessions", name = L.WANDERLUST_PROFESSIONS, desc = L.WANDERLUST_PROFESSIONS_DESC },
		},
	},
	{
		key = "angler",
		defaultMode = "angler",
		name = L.HELPERS_FISHING_MODE,
		desc = L.HELPERS_FISHING_DESC,
		modules = { Helpers = true },
		isOn = function() return ModuleOn("Helpers", "fishing") end,
		setOn = function(on) SetModuleOn("Helpers", "fishing", on) end,
		subOptions = {
			{ module = "Helpers", key = "fishingEquip", name = L.HELPERS_FISHING_EQUIP, desc = L.HELPERS_FISHING_EQUIP_DESC },
			{ module = "Helpers", key = "fishingRestore", name = L.HELPERS_FISHING_RESTORE, desc = L.HELPERS_FISHING_RESTORE_DESC },
			{ module = "Helpers", key = "fishingHideUI", name = L.HELPERS_FISHING_HIDE_UI, desc = L.HELPERS_FISHING_HIDE_UI_DESC },
			{ module = "Helpers", key = "fishingSound", name = L.HELPERS_FISHING_SOUND, desc = L.HELPERS_FISHING_SOUND_DESC },
		},
	},
	{
		key = "rpProfiles",
		defaultMode = "rp",
		name = L.RP_ENABLE,
		desc = L.RP_ENABLE_DESC,
		modules = { Roleplay = true },
		isOn = function() return ModuleOn("Roleplay", "enabled") end,
		setOn = function(on) SetModuleOn("Roleplay", "enabled", on) end,
		subOptions = {
			{ module = "Roleplay", key = "hoverTargetProfile", name = L.RP_HOVER_TARGET },
			{ module = "Roleplay", key = "compatibleProfiles", name = L.RP_COMPATIBILITY, desc = L.RP_COMPATIBILITY_DESC },
			{ module = "Roleplay", key = "profileTooltip", name = L.RP_TOOLTIP },
			{ module = "Roleplay", key = "playerPortraitClick", name = L.RP_PLAYER_PORTRAIT_CLICK },
		},
		action = {
			text = L.RP_EDIT,
			onClick = function()
				local rp = ns:GetModule("Roleplay")
				if rp and rp.OpenEditor then
					rp.OpenEditor()
				end
			end,
		},
	},
	{
		key = "dialog",
		defaultMode = "rp",
		name = L.DIALOG_TITLE,
		desc = L.DIALOG_ENABLE_DESC,
		modules = { Dialog = true },
		isOn = function() return ModuleOn("Dialog", "enabled") end,
		setOn = function(on) SetModuleOn("Dialog", "enabled", on) end,
	},
	{
		key = "speechBubbles",
		defaultMode = "rp",
		name = L.SPEECH_TITLE,
		desc = L.SPEECH_ENABLE_DESC,
		modules = { SpeechBubbles = true },
		isOn = function() return ModuleOn("SpeechBubbles", "enabled") end,
		setOn = function(on) SetModuleOn("SpeechBubbles", "enabled", on) end,
	},
	{
		key = "chatEmotes",
		defaultMode = "rp",
		name = L.CHATEMOTES_TITLE,
		desc = L.CHATEMOTES_DESC,
		modules = { ChatEmotes = true },
		isOn = function() return ModuleOn("ChatEmotes", "enabled") end,
		setOn = function(on) SetModuleOn("ChatEmotes", "enabled", on) end,
	},
	{
		key = "camera",
		defaultMode = "rp",
		name = L.CAMERA_ENABLE,
		desc = L.CAMERA_ENABLE_DESC,
		modules = { Camera = true },
		isOn = function() return ModuleOn("Camera", "enabled") end,
		setOn = function(on) SetModuleOn("Camera", "enabled", on) end,
	},
	{
		key = "bloody",
		defaultMode = "berserker",
		name = L.PORTRAIT_FEATURE_BLOODY,
		desc = L.SOLO_PARTY_BLOODY_DESC,
		modules = { SoloParty = true },
		isOn = function()
			return ModuleOn("SoloParty", "enabled") and ModuleOn("SoloParty", "criticals") and ModuleOn("SoloParty", "bloody")
		end,
		setOn = function(on)
			if on then
				SetModuleOn("SoloParty", "enabled", true)
				SetModuleOn("SoloParty", "criticals", true)
				SetModuleOn("SoloParty", "bloody", true)
			else
				SetModuleOn("SoloParty", "bloody", false)
				SetModuleOn("SoloParty", "enabled", false)
			end
		end,
		subOptions = {
			{ module = "SoloParty", key = "sounds", name = L.SOLO_PARTY_SOUNDS, desc = L.SOLO_PARTY_SOUNDS_DESC },
			{ module = "SoloParty", key = "effects", name = L.SOLO_PARTY_EFFECTS, desc = L.SOLO_PARTY_EFFECTS_DESC },
		},
	},
	{
		key = "landing",
		defaultMode = "berserker",
		name = L.LANDING_ENABLE,
		desc = L.LANDING_ENABLE_DESC,
		modules = { Landing = true },
		isOn = function() return ModuleOn("Landing", "enabled") end,
		setOn = function(on) SetModuleOn("Landing", "enabled", on) end,
	},
	{
		key = "combatText",
		defaultMode = "berserker",
		name = L.COMBATTEXT_TITLE,
		desc = L.COMBATTEXT_ENABLE_DESC,
		modules = { CombatText = true },
		isOn = function() return ModuleOn("CombatText", "enabled") end,
		setOn = function(on) SetModuleOn("CombatText", "enabled", on) end,
	},
}

local FEATURE_BY_KEY = {}
local WATCHED_MODULES = {}
for _, feature in ipairs(FEATURES) do
	FEATURE_BY_KEY[feature.key] = feature
	for modName in pairs(feature.modules) do
		WATCHED_MODULES[modName] = true
	end
end

local function VisualsDB()
	local visuals = ns:GetModule("Visuals")
	if not visuals then return nil, nil end
	if visuals.db then
		if type(visuals.db.portraitModeAssignments) ~= "table" then
			visuals.db.portraitModeAssignments = {}
		end
		if type(visuals.db.portraitModeDisabled) ~= "table" then
			visuals.db.portraitModeDisabled = {}
		end
	end
	return visuals.db, visuals.cdb
end

local function FeatureMode(featureKey)
	local feature = FEATURE_BY_KEY[featureKey]
	if not feature then return nil end
	local db = VisualsDB()
	local custom = db and db.portraitModeAssignments[featureKey]
	if custom and MODE_BY_KEY[custom] and custom ~= "normal" then
		return custom
	end
	return feature.defaultMode
end

local function ModeFeatures(modeKey)
	local list = {}
	for _, feature in ipairs(FEATURES) do
		if FeatureMode(feature.key) == modeKey then
			list[#list + 1] = feature
		end
	end
	return list
end

local function IsFeatureSelected(featureKey)
	local db = VisualsDB()
	return not (db and db.portraitModeDisabled[featureKey])
end

local function ModeCounts(modeKey)
	local features = ModeFeatures(modeKey)
	local activeCount, selectedCount = 0, 0
	for _, feature in ipairs(features) do
		if IsFeatureSelected(feature.key) then
			selectedCount = selectedCount + 1
			if feature.isOn() then
				activeCount = activeCount + 1
			end
		end
	end
	return activeCount, selectedCount, #features
end

local function IsModeActive(modeKey)
	local activeCount, selectedCount = ModeCounts(modeKey)
	return selectedCount > 0 and activeCount == selectedCount
end

local UpdatePlayerPortrait, RefreshMenu, StopDrag

local function ToggleMode(modeKey)
	if not MODE_BY_KEY[modeKey] or modeKey == "normal" then return end
	local target = not IsModeActive(modeKey)
	for _, feature in ipairs(ModeFeatures(modeKey)) do
		if IsFeatureSelected(feature.key) then
			feature.setOn(target)
		end
	end
	UpdatePlayerPortrait()
	RefreshMenu()
end

local function SetFeatureSelected(featureKey, selected)
	local feature = FEATURE_BY_KEY[featureKey]
	local db = VisualsDB()
	if not (feature and db) then return end
	local modeKey = FeatureMode(featureKey)
	local wasActive = IsModeActive(modeKey)
	db.portraitModeDisabled[featureKey] = (not selected) or nil
	if wasActive then
		feature.setOn(selected and true or false)
	end
	UpdatePlayerPortrait()
	RefreshMenu()
end

local function MoveFeature(featureKey, targetModeKey)
	local feature = FEATURE_BY_KEY[featureKey]
	local db = VisualsDB()
	if not (feature and db and MODE_BY_KEY[targetModeKey] and targetModeKey ~= "normal") then
		return false
	end
	local sourceModeKey = FeatureMode(featureKey)
	if sourceModeKey == targetModeKey then
		return false
	end
	local sourceWasActive = IsModeActive(sourceModeKey)
	local targetWasActive = IsModeActive(targetModeKey)
	db.portraitModeAssignments[featureKey] = (targetModeKey ~= feature.defaultMode) and targetModeKey or nil
	if IsFeatureSelected(featureKey) then
		if targetWasActive and not sourceWasActive then
			feature.setOn(true)
		elseif sourceWasActive and not targetWasActive then
			feature.setOn(false)
		end
	end
	UpdatePlayerPortrait()
	RefreshMenu()
	return true
end

local function ResetAssignments()
	local db = VisualsDB()
	if not db then return end
	wipe(db.portraitModeAssignments)
	wipe(db.portraitModeDisabled)
	UpdatePlayerPortrait()
	RefreshMenu()
end

local function HasCustomAssignments()
	local db = VisualsDB()
	if not db then return false end
	return next(db.portraitModeAssignments) ~= nil or next(db.portraitModeDisabled) ~= nil
end

-- Exposed helpers for unit tests and inspection.
PortraitModes.MODES = MODES
PortraitModes.FEATURES = FEATURES
PortraitModes.FeatureMode = FeatureMode
PortraitModes.ModeFeatures = ModeFeatures
PortraitModes.IsFeatureSelected = IsFeatureSelected
PortraitModes.ModeCounts = ModeCounts
PortraitModes.IsModeActive = IsModeActive
PortraitModes.ToggleMode = ToggleMode
PortraitModes.SetFeatureSelected = SetFeatureSelected
PortraitModes.MoveFeature = MoveFeature
PortraitModes.ResetAssignments = ResetAssignments

---------------------------------------------------------------------------
-- Right-click mode menu with drag-and-drop between mode tabs
---------------------------------------------------------------------------
local MENU_WIDTH = 368
local TAB_HEIGHT = 48
local TAB_GAP = 6
local FEATURE_ROW_HEIGHT = 24
local SUB_ROW_HEIGHT = 20
local ACTION_ROW_HEIGHT = 24
local MAX_LIST_HEIGHT = 290
local PAD = ns.PANEL_PADDING or 10

local menu, dragGhost
local selectedMenuMode = "wanderlust"
local expandedFeatures = {}
local draggingFeature, hoveredDropTab
local listScrollOffset = 0

local function StatusText(modeKey)
	local activeCount, selectedCount, totalCount = ModeCounts(modeKey)
	if totalCount == 0 or selectedCount == 0 then
		return GRAY_FONT_COLOR:WrapTextInColorCode(L.PORTRAIT_MODE_OFF)
	elseif activeCount == selectedCount then
		return GREEN_FONT_COLOR:WrapTextInColorCode(L.PORTRAIT_MODE_ON)
	elseif activeCount > 0 then
		return ORANGE_FONT_COLOR:WrapTextInColorCode(L.PORTRAIT_MODE_PARTIAL:format(activeCount, selectedCount))
	end
	return GRAY_FONT_COLOR:WrapTextInColorCode(L.PORTRAIT_MODE_OFF)
end

local function IsExpanded(feature, modeFeatureCount)
	if not (feature.subOptions and #feature.subOptions > 0) then
		return false
	end
	local saved = expandedFeatures[feature.key]
	if saved ~= nil then
		return saved
	end
	return modeFeatureCount == 1 or #feature.subOptions <= 2
end

local function StyleCheckBox(box, checked, disabled)
	if checked then
		box.Mark:SetAtlas("common-icon-checkmark")
		if disabled then
			box.Mark:SetVertexColor(0.55, 0.55, 0.55)
		else
			box.Mark:SetVertexColor(0.45, 0.95, 0.45)
		end
		box.Mark:Show()
	else
		box.Mark:Hide()
	end
	if disabled then
		box.Border:ShowColor(0.45, 0.45, 0.45, 0.6)
	else
		box.Border:ShowColor(ns.PANEL_BORDER[1], ns.PANEL_BORDER[2], ns.PANEL_BORDER[3], 0.9)
	end
end

local function CreateCheckBox(parent, size)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box.Bg = box:CreateTexture(nil, "BACKGROUND")
	box.Bg:SetAllPoints()
	box.Bg:SetColorTexture(0.05, 0.06, 0.09, 0.9)
	box.Border = ns.CreatePixelBorder(box, box, 1, "OVERLAY", 5)
	box.Mark = box:CreateTexture(nil, "OVERLAY", nil, 6)
	box.Mark:SetPoint("TOPLEFT", 1, -1)
	box.Mark:SetPoint("BOTTOMRIGHT", -1, 1)
	box.Mark:Hide()
	return box
end

local function UpdateTabStyles()
	if not menu then return end
	local sourceMode = draggingFeature and FeatureMode(draggingFeature) or nil
	for _, tab in ipairs(menu.tabs) do
		local modeKey = tab.modeKey
		local active = IsModeActive(modeKey)
		local selected = modeKey == selectedMenuMode
		local isDropTarget = draggingFeature ~= nil and modeKey ~= sourceMode
		local isDropHover = isDropTarget and tab == hoveredDropTab
		tab.Icon:SetDesaturated(not active)
		tab.Icon:SetAlpha(active and 1 or 0.65)
		tab.Dot:SetColorTexture(active and 0.35 or 0.45, active and 0.90 or 0.45, active and 0.35 or 0.45, active and 1 or 0.65)
		if isDropHover then
			tab.Bg:SetColorTexture(0.32, 0.42, 0.18, 0.85)
			tab.Border:ShowColor(0.65, 1, 0.45, 1)
		elseif isDropTarget then
			tab.Bg:SetColorTexture(0.24, 0.22, 0.14, 0.65)
			tab.Border:ShowColor(1, 0.82, 0.3, 0.75)
		elseif selected then
			tab.Bg:SetColorTexture(0.24, 0.27, 0.36, 0.92)
			tab.Border:ShowColor(1, 0.82, 0.3, 1)
		else
			tab.Bg:SetColorTexture(0.09, 0.10, 0.15, 0.75)
			tab.Border:ShowColor(ns.PANEL_BORDER[1], ns.PANEL_BORDER[2], ns.PANEL_BORDER[3], 0.45)
		end
		local _, _, count = ModeCounts(modeKey)
		tab.Count:SetText(tostring(count))
	end
end

local function TabUnderCursor()
	if not (menu and menu:IsShown()) then return nil end
	for _, tab in ipairs(menu.tabs) do
		if tab:IsShown() and tab:IsMouseOver() then
			return tab
		end
	end
	return nil
end

local function UpdateDragGhost()
	if not (draggingFeature and dragGhost) then return end
	local x, y = GetCursorPosition()
	local scale = ns.Number(UIParent:GetEffectiveScale(), 1)
	dragGhost:ClearAllPoints()
	dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 10)
	local over = TabUnderCursor()
	if over ~= hoveredDropTab then
		hoveredDropTab = over
		UpdateTabStyles()
	end
end

local function EnsureDragGhost()
	if dragGhost then return dragGhost end
	local ghost = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetHeight(24)
	ghost:EnableMouse(false)
	if ghost.NineSlice then
		if ghost.NineSlice.SetBorderColor then
			ghost.NineSlice:SetBorderColor(1, 0.82, 0.3, 1)
		end
		if ghost.NineSlice.SetCenterColor then
			ghost.NineSlice:SetCenterColor(0.14, 0.16, 0.22, 0.96)
		end
	end
	ghost.Text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ghost.Text:SetPoint("CENTER")
	ghost:Hide()
	dragGhost = ghost
	return ghost
end

local function StartDrag(featureKey)
	local feature = FEATURE_BY_KEY[featureKey]
	if not feature then return end
	GameTooltip_Hide()
	draggingFeature = featureKey
	hoveredDropTab = TabUnderCursor()
	local ghost = EnsureDragGhost()
	ghost.Text:SetText(feature.name)
	ghost:SetWidth(math.max(110, ns.Number(ghost.Text:GetStringWidth(), 100) + 22))
	ghost:Show()
	UpdateDragGhost()
	ns.SetUpdate(ghost, "PortraitModes: drag ghost", UpdateDragGhost)
	UpdateTabStyles()
end

StopDrag = function(commit)
	if not draggingFeature then return end
	local featureKey = draggingFeature
	local dropTab = commit and (TabUnderCursor() or hoveredDropTab) or nil
	draggingFeature = nil
	hoveredDropTab = nil
	if dragGhost then
		ns.SetUpdate(dragGhost, "PortraitModes: drag ghost", nil)
		dragGhost:Hide()
	end
	if dropTab and dropTab.modeKey then
		MoveFeature(featureKey, dropTab.modeKey)
	else
		UpdateTabStyles()
	end
end

local function AcquireRow(index)
	local row = menu.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, menu.List)
	row:RegisterForClicks("LeftButtonUp")
	row:RegisterForDrag("LeftButton")
	local hl = row:CreateTexture()
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	row:SetHighlightTexture(hl)
	-- Three thin grip bars on the left to indicate drag-and-drop capability.
	row.Grip = CreateFrame("Frame", nil, row)
	row.Grip:SetSize(8, 12)
	row.Grip:SetPoint("LEFT", 4, 0)
	for g = 1, 3 do
		local bar = row.Grip:CreateTexture(nil, "ARTWORK")
		bar:SetSize(6, 1)
		bar:SetPoint("TOPLEFT", 1, -(g - 1) * 4 - 1)
		bar:SetColorTexture(ns.PANEL_BORDER[1], ns.PANEL_BORDER[2], ns.PANEL_BORDER[3], 0.75)
	end
	row.Check = CreateCheckBox(row, 14)
	row.Check:SetPoint("LEFT", 16, 0)
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
	row.Expand = CreateFrame("Button", nil, row)
	row.Expand:SetSize(20, 20)
	row.Expand:SetPoint("RIGHT", -2, 0)
	row.Expand.Label = row.Expand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Expand.Label:SetPoint("CENTER")
	row.Expand:SetScript("OnClick", ns.Measured("PortraitModes: toggle details", function()
		local entry = row.entry
		if entry and entry.feature then
			expandedFeatures[entry.feature.key] = not entry.expanded
			RefreshMenu()
		end
	end))
	row:SetScript("OnClick", ns.Measured("PortraitModes: menu row click", function(self)
		local entry = self.entry
		if not entry then return end
		if entry.kind == "feature" then
			SetFeatureSelected(entry.feature.key, not IsFeatureSelected(entry.feature.key))
		elseif entry.kind == "sub" then
			local sub = entry.sub
			SetModuleOn(sub.module, sub.key, not ModuleOn(sub.module, sub.key))
			RefreshMenu()
		elseif entry.kind == "action" and entry.action and entry.action.onClick then
			menu:Hide()
			entry.action.onClick()
		end
	end))
	row:SetScript("OnDragStart", ns.Measured("PortraitModes: drag start", function(self)
		local entry = self.entry
		if entry and entry.kind == "feature" then
			StartDrag(entry.feature.key)
		end
	end))
	row:SetScript("OnDragStop", ns.Measured("PortraitModes: drag stop", function()
		StopDrag(true)
	end))
	row:SetScript("OnEnter", ns.Measured("PortraitModes: menu row enter", function(self)
		if draggingFeature then return end
		local entry = self.entry
		if not entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.kind == "feature" then
			GameTooltip_SetTitle(GameTooltip, entry.feature.name)
			if entry.feature.desc then
				GameTooltip_AddNormalLine(GameTooltip, entry.feature.desc)
			end
			GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODES_DRAG_TOOLTIP)
			GameTooltip:Show()
		elseif entry.kind == "sub" and entry.sub.desc then
			GameTooltip_SetTitle(GameTooltip, entry.sub.name)
			GameTooltip_AddNormalLine(GameTooltip, entry.sub.desc)
			GameTooltip:Show()
		end
	end))
	row:SetScript("OnLeave", GameTooltip_Hide)
	menu.rows[index] = row
	return row
end

local function BuildMenuEntries(modeKey)
	local entries = {}
	local features = ModeFeatures(modeKey)
	for _, feature in ipairs(features) do
		local expanded = IsExpanded(feature, #features)
		entries[#entries + 1] = { kind = "feature", feature = feature, expanded = expanded, height = FEATURE_ROW_HEIGHT }
		if expanded and feature.subOptions then
			for _, sub in ipairs(feature.subOptions) do
				entries[#entries + 1] = { kind = "sub", feature = feature, sub = sub, height = SUB_ROW_HEIGHT }
			end
		end
		if feature.action then
			entries[#entries + 1] = { kind = "action", feature = feature, action = feature.action, height = ACTION_ROW_HEIGHT }
		end
	end
	return entries
end

RefreshMenu = function()
	if not (menu and menu:IsShown()) then return end
	local mode = MODE_BY_KEY[selectedMenuMode] or MODES[2]
	selectedMenuMode = mode.key
	menu.Title:SetText(L.PORTRAIT_MODES_MENU_TITLE)
	UpdateTabStyles()
	local active = IsModeActive(mode.key)
	menu.ModeStatus:SetText(("%s: %s"):format(mode.name, StatusText(mode.key)))
	menu.ToggleButton:SetText(active and L.PORTRAIT_MODE_DISABLE or L.PORTRAIT_MODE_ENABLE)
	local _, selectedCount = ModeCounts(mode.key)
	menu.ToggleButton:SetEnabled(selectedCount > 0)

	local entries = BuildMenuEntries(mode.key)
	local totalHeight = 0
	for _, entry in ipairs(entries) do
		totalHeight = totalHeight + entry.height
	end
	local listHeight = math.max(32, math.min(MAX_LIST_HEIGHT, totalHeight))
	local maxScroll = math.max(0, totalHeight - listHeight)
	listScrollOffset = math.max(0, math.min(listScrollOffset, maxScroll))
	menu.List:SetHeight(listHeight)
	menu.Empty:SetShown(#entries == 0)

	local y = -listScrollOffset
	local visibleCount = 0
	for _, entry in ipairs(entries) do
		local rowTop = y
		local rowBottom = y + entry.height
		y = rowBottom
		if rowBottom > 0 and rowTop < listHeight then
			visibleCount = visibleCount + 1
			local row = AcquireRow(visibleCount)
			row.entry = entry
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", menu.List, "TOPLEFT", 0, -rowTop)
			row:SetPoint("RIGHT", menu.List, "RIGHT", 0, 0)
			row:SetHeight(entry.height)
			if entry.kind == "feature" then
				local feature = entry.feature
				local checked = IsFeatureSelected(feature.key)
				row.Grip:Show()
				row.Check:SetSize(14, 14)
				row.Check:ClearAllPoints()
				row.Check:SetPoint("LEFT", 16, 0)
				row.Check:Show()
				StyleCheckBox(row.Check, checked, false)
				row.Text:SetFontObject(checked and "GameFontHighlight" or "GameFontDisable")
				row.Text:SetText(feature.name)
				row.Text:ClearAllPoints()
				row.Text:SetPoint("LEFT", row.Check, "RIGHT", 7, 0)
				local hasSubs = feature.subOptions and #feature.subOptions > 0
				row.Expand:SetShown(hasSubs)
				if hasSubs then
					row.Expand.Label:SetText(entry.expanded and "−" or "+")
					row.Text:SetPoint("RIGHT", row.Expand, "LEFT", -4, 0)
				else
					row.Text:SetPoint("RIGHT", -6, 0)
				end
			elseif entry.kind == "sub" then
				local sub = entry.sub
				local checked = ModuleOn(sub.module, sub.key)
				local parentSelected = IsFeatureSelected(entry.feature.key)
				row.Grip:Hide()
				row.Expand:Hide()
				row.Check:SetSize(12, 12)
				row.Check:ClearAllPoints()
				row.Check:SetPoint("LEFT", 32, 0)
				row.Check:Show()
				StyleCheckBox(row.Check, checked, not parentSelected)
				row.Text:SetFontObject(parentSelected and "GameFontHighlightSmall" or "GameFontDisableSmall")
				row.Text:SetText(sub.name)
				row.Text:ClearAllPoints()
				row.Text:SetPoint("LEFT", row.Check, "RIGHT", 6, 0)
				row.Text:SetPoint("RIGHT", -6, 0)
			else
				row.Grip:Hide()
				row.Expand:Hide()
				row.Check:Hide()
				row.Text:SetFontObject("GameFontNormalSmall")
				row.Text:SetText("• " .. entry.action.text)
				row.Text:ClearAllPoints()
				row.Text:SetPoint("LEFT", 32, 0)
				row.Text:SetPoint("RIGHT", -6, 0)
			end
			row:Show()
		end
	end
	for i = visibleCount + 1, #menu.rows do
		menu.rows[i].entry = nil
		menu.rows[i]:Hide()
	end
	menu.ResetButton:SetEnabled(HasCustomAssignments())
	-- Top padding + title (22) + tabs (48 + 8) + status bar (28 + 6) + list + footer (30) + bottom padding
	menu:SetHeight(PAD + 22 + TAB_HEIGHT + 8 + 28 + 6 + listHeight + 34 + PAD)
end

local function CreateModeMenu()
	if menu then return menu end
	local panel = ns.CreatePanel("ForeverPlusPortraitModeMenu", { strata = "FULLSCREEN_DIALOG", close = true })
	panel:SetWidth(MENU_WIDTH)
	panel.tabs = {}
	panel.rows = {}

	local tabWidth = math.floor((MENU_WIDTH - PAD * 2 - TAB_GAP * (#SELECTABLE_MODES - 1)) / #SELECTABLE_MODES)
	for i, mode in ipairs(SELECTABLE_MODES) do
		local tab = CreateFrame("Button", nil, panel)
		tab.modeKey = mode.key
		tab:SetSize(tabWidth, TAB_HEIGHT)
		tab:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (i - 1) * (tabWidth + TAB_GAP), -(PAD + 24))
		tab.Bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.Bg:SetAllPoints()
		tab.Border = ns.CreatePixelBorder(tab, tab, 1, "OVERLAY", 5)
		tab.Icon = tab:CreateTexture(nil, "ARTWORK")
		tab.Icon:SetSize(24, 24)
		tab.Icon:SetPoint("TOP", 0, -5)
		tab.Icon:SetTexture(mode.icon)
		tab.Mask = tab:CreateMaskTexture()
		tab.Mask:SetAllPoints(tab.Icon)
		tab.Mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		tab.Icon:AddMaskTexture(tab.Mask)
		tab.Dot = tab:CreateTexture(nil, "OVERLAY", nil, 6)
		tab.Dot:SetSize(6, 6)
		tab.Dot:SetPoint("TOPRIGHT", -4, -4)
		tab.Count = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		tab.Count:SetPoint("TOPLEFT", 5, -4)
		tab.Label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tab.Label:SetPoint("BOTTOMLEFT", 2, 4)
		tab.Label:SetPoint("BOTTOMRIGHT", -2, 4)
		tab.Label:SetJustifyH("CENTER")
		tab.Label:SetWordWrap(false)
		tab.Label:SetText(mode.short)
		tab:SetScript("OnClick", ns.Measured("PortraitModes: select menu tab", function(self)
			if selectedMenuMode ~= self.modeKey then
				selectedMenuMode = self.modeKey
				listScrollOffset = 0
				RefreshMenu()
			end
		end))
		tab:SetScript("OnEnter", ns.Measured("PortraitModes: menu tab enter", function(self)
			if draggingFeature then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip_SetTitle(GameTooltip, mode.name)
			GameTooltip_AddNormalLine(GameTooltip, StatusText(mode.key))
			GameTooltip:Show()
		end))
		tab:SetScript("OnLeave", GameTooltip_Hide)
		panel.tabs[i] = tab
	end

	local statusBar = CreateFrame("Frame", nil, panel)
	statusBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + 24 + TAB_HEIGHT + 8))
	statusBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(PAD + 24 + TAB_HEIGHT + 8))
	statusBar:SetHeight(26)
	local statusBg = statusBar:CreateTexture(nil, "BACKGROUND")
	statusBg:SetAllPoints()
	statusBg:SetColorTexture(0, 0, 0, 0.28)
	panel.ModeStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.ModeStatus:SetPoint("LEFT", 6, 0)
	panel.ModeStatus:SetJustifyH("LEFT")

	local toggleButton = CreateFrame("Button", nil, statusBar, "UIPanelButtonTemplate")
	toggleButton:SetSize(102, 20)
	toggleButton:SetPoint("RIGHT", -4, 0)
	toggleButton:SetScript("OnClick", ns.Measured("PortraitModes: menu toggle mode", function()
		ToggleMode(selectedMenuMode)
	end))
	panel.ToggleButton = toggleButton

	local list = CreateFrame("Frame", nil, panel)
	list:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 0, -6)
	list:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 0, -6)
	list:SetClipsChildren(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", ns.Measured("PortraitModes: menu scroll", function(_, delta)
		listScrollOffset = listScrollOffset - delta * 24
		RefreshMenu()
	end))
	ns.AddPanelInset(panel, list)
	panel.List = list

	panel.Empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Empty:SetPoint("LEFT", 8, 0)
	panel.Empty:SetPoint("RIGHT", -8, 0)
	panel.Empty:SetJustifyH("CENTER")
	panel.Empty:SetText(L.PORTRAIT_MODES_EMPTY)
	panel.Empty:Hide()

	panel.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Hint:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
	panel.Hint:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -(PAD + 92), PAD + 4)
	panel.Hint:SetJustifyH("LEFT")
	panel.Hint:SetWordWrap(false)
	panel.Hint:SetText(L.PORTRAIT_MODES_DRAG_HINT)

	local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetButton:SetSize(84, 20)
	resetButton:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	resetButton:SetText(L.PORTRAIT_MODES_RESET)
	resetButton:SetScript("OnClick", ns.Measured("PortraitModes: reset assignments", ResetAssignments))
	panel.ResetButton = resetButton

	panel:SetScript("OnEvent", ns.Measured("PortraitModes: menu outside click", function(self)
		if draggingFeature then return end
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end))
	panel:HookScript("OnShow", ns.Measured("PortraitModes: menu show", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end))
	panel:SetScript("OnHide", ns.Measured("PortraitModes: menu hide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		StopDrag(false)
	end))

	menu = panel
	return panel
end

local function OpenModeMenu(owner, modeKey)
	local panel = CreateModeMenu()
	if panel:IsShown() and selectedMenuMode == modeKey then
		panel:Hide()
		return
	end
	selectedMenuMode = MODE_BY_KEY[modeKey] and modeKey ~= "normal" and modeKey or "wanderlust"
	listScrollOffset = 0
	panel.owner = owner
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -8)
	panel:Show()
	RefreshMenu()
end

---------------------------------------------------------------------------
-- Portrait wheel & clickable mode emblem on PlayerFrame
---------------------------------------------------------------------------
local portraitWheel, portraitBackground, portraitIcon, portraitShine
local optionListenerRegistered

local function ShowsOwnPortrait()
	local unit = PlayerFrame and PlayerFrame.unit
	return not ns.Secret(unit) and unit == "player"
end

local function CanCyclePortrait()
	local db = VisualsDB()
	return db and db.playerPortraitWheel and ShowsOwnPortrait() and not EditModeManagerFrame:IsEditModeActive() or false
end

local function CurrentMode()
	local db, cdb = VisualsDB()
	if not (db and cdb and db.playerPortraitWheel and ShowsOwnPortrait()) then
		return nil
	end
	return MODES[cdb.playerPortraitMode] or MODES[1]
end

local function UpdatePortraitInput()
	if not portraitWheel then return end
	local canUse = CanCyclePortrait()
	local mode = CurrentMode()
	local interactive = canUse and mode ~= nil and mode.key ~= "normal"
	portraitWheel:EnableMouseWheel(canUse and IsShiftKeyDown() and true or false)
	portraitWheel:SetMouseClickEnabled(interactive)
	portraitWheel:SetMouseMotionEnabled(interactive)
	if not interactive then
		if portraitShine then portraitShine:Hide() end
		if GameTooltip:IsOwned(portraitWheel) then GameTooltip:Hide() end
		if menu and menu:IsShown() then menu:Hide() end
	end
end

local function ShowPortraitTooltip()
	local mode = CurrentMode()
	if not (portraitWheel and mode and mode.key ~= "normal" and CanCyclePortrait()) then
		return
	end
	GameTooltip:SetOwner(portraitWheel, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, ("%s — %s"):format(mode.name, StatusText(mode.key)))
	local features = ModeFeatures(mode.key)
	if #features == 0 then
		GameTooltip_AddColoredLine(GameTooltip, L.PORTRAIT_MODES_EMPTY_SHORT, GRAY_FONT_COLOR)
	else
		for _, feature in ipairs(features) do
			local selected = IsFeatureSelected(feature.key)
			local on = feature.isOn()
			local color = not selected and GRAY_FONT_COLOR or (on and GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
			local prefix = not selected and "− " or (on and "✓ " or "○ ")
			GameTooltip_AddColoredLine(GameTooltip, prefix .. feature.name, color)
		end
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_LEFT)
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_RIGHT)
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_WHEEL)
	GameTooltip:Show()
end

UpdatePlayerPortrait = function()
	if not portraitWheel then return end
	local mode = CurrentMode()
	local iconShown = false
	if mode and mode.key ~= "normal" and mode.icon then
		local active = IsModeActive(mode.key)
		portraitIcon:SetAllPoints(portraitBackground)
		iconShown = portraitIcon:SetTexture(mode.icon) ~= false
		portraitIcon:SetDesaturated(not active)
		if active then
			portraitIcon:SetVertexColor(1, 1, 1)
			portraitIcon:SetAlpha(1)
		else
			portraitIcon:SetVertexColor(0.76, 0.76, 0.76)
			portraitIcon:SetAlpha(0.84)
		end
		if portraitShine then
			portraitShine:SetTexture(mode.icon)
		end
	end
	portraitIcon:SetShown(iconShown)
	portraitBackground:SetShown(iconShown)
	if not iconShown and portraitShine then
		portraitShine:Hide()
	end
	UpdatePortraitInput()
	if portraitWheel:IsMouseOver() and iconShown then
		ShowPortraitTooltip()
	end
end

local function OnAnyOptionChanged(moduleName)
	if WATCHED_MODULES[moduleName] then
		UpdatePlayerPortrait()
		RefreshMenu()
	end
end

function PortraitModes.Refresh()
	if not portraitWheel then return end
	UpdatePlayerPortrait()
	local visuals = ns:GetModule("Visuals")
	local enabled = visuals and visuals.db and visuals.db.playerPortraitWheel or false
	if visuals then
		visuals:ToggleEvent("MODIFIER_STATE_CHANGED", enabled, UpdatePortraitInput)
		visuals:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, UpdatePlayerPortrait)
	end
end

function PortraitModes.Setup()
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	local portrait = container and container.PlayerPortrait
	local mask = container and container.PlayerPortraitMask
	if not (portrait and mask) then return end

	portraitWheel = CreateFrame("Button", "ForeverPlusPlayerPortraitWheel", container)
	portraitWheel:SetAllPoints(portrait)
	portraitWheel:SetFrameLevel(PlayerFrame:GetFrameLevel() + 12)
	portraitWheel:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	portraitWheel:SetPassThroughButtons("MiddleButton", "Button4", "Button5")
	portraitWheel:SetMouseClickEnabled(false)
	portraitWheel:SetMouseMotionEnabled(false)

	portraitWheel:SetScript("OnMouseWheel", ns.Measured("PortraitModes: cycle mode", function(_, delta)
		if delta == 0 or not IsShiftKeyDown() or not CanCyclePortrait() then return end
		local _, cdb = VisualsDB()
		if not cdb then return end
		local current = cdb.playerPortraitMode
		if not MODES[current] then current = 1 end
		local step = delta > 0 and 1 or -1
		cdb.playerPortraitMode = (current - 1 + step) % #MODES + 1
		UpdatePlayerPortrait()
		local mode = CurrentMode()
		if menu and menu:IsShown() then
			if mode and mode.key ~= "normal" then
				selectedMenuMode = mode.key
				listScrollOffset = 0
				RefreshMenu()
			else
				menu:Hide()
			end
		end
	end))

	portraitWheel:SetScript("OnClick", ns.Measured("PortraitModes: portrait click", function(self, button)
		if IsModifierKeyDown() or not CanCyclePortrait() then return end
		local mode = CurrentMode()
		if not (mode and mode.key ~= "normal") then return end
		if button == "LeftButton" then
			ToggleMode(mode.key)
		elseif button == "RightButton" then
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
			OpenModeMenu(self, mode.key)
		end
	end))

	portraitWheel:SetScript("OnEnter", ns.Measured("PortraitModes: portrait enter", function()
		local mode = CurrentMode()
		if mode and mode.key ~= "normal" and CanCyclePortrait() then
			if portraitShine then portraitShine:Show() end
			ShowPortraitTooltip()
		end
	end))

	portraitWheel:SetScript("OnLeave", ns.Measured("PortraitModes: portrait leave", function()
		if portraitShine then portraitShine:Hide() end
		if GameTooltip:IsOwned(portraitWheel) then GameTooltip:Hide() end
	end))

	portraitWheel:SetScript("OnHide", ns.Measured("PortraitModes: portrait hide", function()
		if portraitShine then portraitShine:Hide() end
		if menu and menu:IsShown() then menu:Hide() end
	end))

	-- Use the portrait's own mask and draw below the dragon and status flash.
	portraitBackground = container:CreateTexture(nil, "ARTWORK", nil, 0)
	portraitBackground:SetAllPoints(portrait)
	portraitBackground:AddMaskTexture(mask)
	portraitBackground:SetColorTexture(0.06, 0.05, 0.04, 1)

	portraitIcon = container:CreateTexture(nil, "ARTWORK", nil, 1)
	portraitIcon:SetAllPoints(portrait)
	portraitIcon:AddMaskTexture(mask)

	portraitShine = container:CreateTexture(nil, "ARTWORK", nil, 2)
	portraitShine:SetAllPoints(portrait)
	portraitShine:AddMaskTexture(mask)
	portraitShine:SetBlendMode("ADD")
	portraitShine:SetAlpha(0.22)
	portraitShine:Hide()

	hooksecurefunc("UnitFrame_SetUnit", ns.Measured("PortraitModes: unit changed", function(frame)
		local db = VisualsDB()
		if frame == PlayerFrame and db and db.playerPortraitWheel then
			UpdatePlayerPortrait()
		end
	end))

	local visuals = ns:GetModule("Visuals")
	local onEditMode = ns.Measured("PortraitModes: edit mode", UpdatePortraitInput)
	EventRegistry:RegisterCallback("EditMode.Enter", onEditMode, visuals)
	EventRegistry:RegisterCallback("EditMode.Exit", onEditMode, visuals)
	if not optionListenerRegistered then
		optionListenerRegistered = true
		ns.RegisterOptionListener(OnAnyOptionChanged)
	end
	PortraitModes.Refresh()
end

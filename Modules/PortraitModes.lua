-- Shift-wheel mode switcher on the player portrait with left-click toggle
-- and a right-click WoW-style window supporting drag-and-drop between modes.
local _, ns = ...
local L = ns.L

local PortraitModes = {}
ns.PortraitModes = PortraitModes

local ROUND_MASK = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local ROW_HIGHLIGHT = [[Interface\QuestFrame\UI-QuestTitleHighlight]]
local PLUS_UP = [[Interface\Buttons\UI-PlusButton-Up]]
local PLUS_DOWN = [[Interface\Buttons\UI-PlusButton-Down]]
local MINUS_UP = [[Interface\Buttons\UI-MinusButton-Up]]
local MINUS_DOWN = [[Interface\Buttons\UI-MinusButton-Down]]
local PLUS_HIGHLIGHT = [[Interface\Buttons\UI-PlusButton-Hilight]]

-- Place the round 44x44 mode emblem slightly up-right inside the 60x60 portrait
-- so the player level badge at the bottom-left never clips the motif.
local EMBLEM_SIZE = 44
local EMBLEM_OFFSET_X = 5
local EMBLEM_OFFSET_Y = 4

-- Slot 1 is always the standard Blizzard portrait; slots 2..5 use classic WoW icons.
local MODES = {
	{ key = "normal" },
	{ key = "wanderlust", name = L.WANDERLUST_TITLE, short = L.WANDERLUST_TITLE, icon = 134269, bg = { 0.08, 0.13, 0.18 } },
	{ key = "angler", name = L.HELPERS_FISHING_MODE, short = L.PORTRAIT_MODE_ANGLER_SHORT, icon = 136245, bg = { 0.06, 0.15, 0.20 } },
	{ key = "rp", name = L.PORTRAIT_MODE_RP, short = L.PORTRAIT_MODE_RP_SHORT, icon = 133741, bg = { 0.17, 0.08, 0.09 } },
	{ key = "berserker", name = L.PORTRAIT_MODE_BERSERKER, short = L.PORTRAIT_MODE_BERSERKER_SHORT, icon = 136009, bg = { 0.20, 0.06, 0.05 } },
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

local ITEM_BY_KEY = {}
local SUB_ITEMS = {}
local WATCHED_MODULES = {}
for _, feature in ipairs(FEATURES) do
	ITEM_BY_KEY[feature.key] = feature
	for modName in pairs(feature.modules) do
		WATCHED_MODULES[modName] = true
	end
	if feature.subOptions then
		for _, sub in ipairs(feature.subOptions) do
			local modName, optKey = sub.module, sub.key
			sub.id = modName .. ":" .. optKey
			sub.parentKey = feature.key
			sub.isSub = true
			sub.isOn = function() return ModuleOn(modName, optKey) end
			sub.setOn = function(on) SetModuleOn(modName, optKey, on) end
			SUB_ITEMS[#SUB_ITEMS + 1] = sub
			ITEM_BY_KEY[sub.id] = sub
			WATCHED_MODULES[modName] = true
		end
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

local function FeatureMode(itemKey)
	local item = ITEM_BY_KEY[itemKey]
	if not item then return nil end
	local db = VisualsDB()
	local custom = db and db.portraitModeAssignments[itemKey]
	if custom and MODE_BY_KEY[custom] and custom ~= "normal" then
		return custom
	end
	if item.isSub then
		return FeatureMode(item.parentKey)
	end
	return item.defaultMode
end

local function IsDetachedSub(sub)
	return FeatureMode(sub.id) ~= FeatureMode(sub.parentKey)
end

local function FeatureSubOptions(feature, modeKey)
	if not feature.subOptions then return nil end
	local list = {}
	for _, sub in ipairs(feature.subOptions) do
		if FeatureMode(sub.id) == modeKey then
			list[#list + 1] = sub
		end
	end
	return list
end

local function ModeFeatures(modeKey)
	local list = {}
	for _, feature in ipairs(FEATURES) do
		if FeatureMode(feature.key) == modeKey then
			list[#list + 1] = feature
		end
	end
	for _, sub in ipairs(SUB_ITEMS) do
		if IsDetachedSub(sub) and FeatureMode(sub.id) == modeKey then
			list[#list + 1] = sub
		end
	end
	return list
end

local function ItemKey(item)
	return item.isSub and item.id or item.key
end

local function IsFeatureSelected(itemKey)
	local db = VisualsDB()
	return not (db and db.portraitModeDisabled[itemKey])
end

local function ModeCounts(modeKey)
	local features = ModeFeatures(modeKey)
	local activeCount, selectedCount = 0, 0
	for _, feature in ipairs(features) do
		if IsFeatureSelected(ItemKey(feature)) then
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
		if IsFeatureSelected(ItemKey(feature)) then
			feature.setOn(target)
		end
	end
	UpdatePlayerPortrait()
	RefreshMenu()
end

local function SetFeatureSelected(itemKey, selected)
	local item = ITEM_BY_KEY[itemKey]
	local db = VisualsDB()
	if not (item and db) then return end
	local modeKey = FeatureMode(itemKey)
	local wasActive = IsModeActive(modeKey)
	db.portraitModeDisabled[itemKey] = (not selected) or nil
	if wasActive then
		item.setOn(selected and true or false)
	end
	UpdatePlayerPortrait()
	RefreshMenu()
end

local function MoveFeature(itemKey, targetModeKey)
	local item = ITEM_BY_KEY[itemKey]
	local db = VisualsDB()
	if not (item and db and MODE_BY_KEY[targetModeKey] and targetModeKey ~= "normal") then
		return false
	end
	local sourceModeKey = FeatureMode(itemKey)
	if sourceModeKey == targetModeKey then
		return false
	end
	local sourceWasActive = IsModeActive(sourceModeKey)
	local targetWasActive = IsModeActive(targetModeKey)
	local wasDetachedSub = item.isSub and IsDetachedSub(item)
	if item.isSub then
		local parentMode = FeatureMode(item.parentKey)
		if targetModeKey == parentMode then
			db.portraitModeAssignments[itemKey] = nil
			db.portraitModeDisabled[itemKey] = nil
		else
			db.portraitModeAssignments[itemKey] = targetModeKey
		end
	else
		db.portraitModeAssignments[itemKey] = (targetModeKey ~= item.defaultMode) and targetModeKey or nil
	end
	if IsFeatureSelected(itemKey) then
		if targetWasActive and not sourceWasActive and (not item.isSub or IsDetachedSub(item)) then
			item.setOn(true)
		elseif sourceWasActive and not targetWasActive and (not item.isSub or wasDetachedSub) then
			item.setOn(false)
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
-- WoW-style PortraitFrameTemplate window with PanelTopTabButtonTemplate tabs
-- and drag-and-drop reassignment between modes.
---------------------------------------------------------------------------
local MENU_WIDTH = 404
local INSET_TOP = 86
local INSET_BOTTOM = 40
local HEADER_HEIGHT = 36
local FEATURE_ROW_HEIGHT = 26
local SUB_ROW_HEIGHT = 22
local ACTION_ROW_HEIGHT = 26
local MAX_LIST_HEIGHT = 276

local menu, dragGhost
local selectedMenuMode = "wanderlust"
local expandedFeatures = {}
local draggingFeature, hoveredDropTab
local listScrollOffset = 0

local function AtlasIcon(atlas, size)
	if CreateAtlasMarkup then
		local markup = CreateAtlasMarkup(atlas, size, size)
		if type(markup) == "string" and markup ~= "" then
			return markup
		end
	end
	return ""
end

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

local function IsExpanded(feature, modeFeatureCount, subList)
	if not (subList and #subList > 0) then
		return false
	end
	local saved = expandedFeatures[feature.key]
	if saved ~= nil then
		return saved
	end
	return modeFeatureCount == 1 or #subList <= 2
end

local function SelectWoWTab(tab, selected)
	if selected then
		PanelTemplates_SelectTab(tab)
	else
		PanelTemplates_DeselectTab(tab)
	end
end

local function UpdateTabStyles()
	if not menu then return end
	local sourceMode = draggingFeature and FeatureMode(draggingFeature) or nil
	local checkMark = AtlasIcon("common-icon-checkmark", 11)
	for _, tab in ipairs(menu.tabs) do
		local mode = MODE_BY_KEY[tab.modeKey]
		local active = IsModeActive(tab.modeKey)
		local selected = tab.modeKey == selectedMenuMode
		local isDropTarget = draggingFeature ~= nil and tab.modeKey ~= sourceMode
		local isDropHover = isDropTarget and tab == hoveredDropTab
		local label = active and checkMark ~= "" and (checkMark .. " " .. mode.short) or mode.short
		tab:SetText(label)
		if PanelTemplates_TabResize then
			PanelTemplates_TabResize(tab, 0)
		end
		SelectWoWTab(tab, selected)
		if tab.DropGlow then
			if isDropHover then
				tab.DropGlow:SetVertexColor(1, 0.90, 0.35)
				tab.DropGlow:SetAlpha(0.95)
				tab.DropGlow:Show()
			elseif isDropTarget then
				tab.DropGlow:SetVertexColor(1, 0.80, 0.25)
				tab.DropGlow:SetAlpha(0.45)
				tab.DropGlow:Show()
			else
				tab.DropGlow:Hide()
			end
		end
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
	ghost:SetHeight(26)
	ghost:EnableMouse(false)
	ghost.Text = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ghost.Text:SetPoint("CENTER")
	ghost:Hide()
	dragGhost = ghost
	return ghost
end

local function StartDrag(itemKey)
	local item = ITEM_BY_KEY[itemKey]
	if not item then return end
	GameTooltip_Hide()
	draggingFeature = itemKey
	hoveredDropTab = TabUnderCursor()
	local ghost = EnsureDragGhost()
	ghost.Text:SetText(item.name)
	ghost:SetWidth(math.max(120, ns.Number(ghost.Text:GetStringWidth(), 100) + 24))
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

local function SetExpandVisual(button, expanded)
	button:SetNormalTexture(expanded and MINUS_UP or PLUS_UP)
	button:SetPushedTexture(expanded and MINUS_DOWN or PLUS_DOWN)
end

local function AcquireRow(index)
	local row = menu.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, menu.List)
	row:RegisterForClicks("LeftButtonUp")
	row:RegisterForDrag("LeftButton")
	row:SetHighlightTexture(ROW_HIGHLIGHT, "ADD")

	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("LEFT", 4, 0)
	check:EnableMouse(false)
	row.Check = check

	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)

	local expand = CreateFrame("Button", nil, row)
	expand:SetSize(16, 16)
	expand:SetPoint("RIGHT", -6, 0)
	expand:SetHighlightTexture(PLUS_HIGHLIGHT, "ADD")
	expand:SetScript("OnClick", ns.Measured("PortraitModes: toggle details", function()
		local entry = row.entry
		if entry and entry.feature then
			expandedFeatures[entry.feature.key] = not entry.expanded
			RefreshMenu()
		end
	end))
	row.Expand = expand

	local actionButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	actionButton:SetSize(196, 21)
	actionButton:SetPoint("LEFT", 32, 0)
	actionButton:SetScript("OnClick", ns.Measured("PortraitModes: action button", function()
		local entry = row.entry
		if entry and entry.action and entry.action.onClick then
			menu:Hide()
			entry.action.onClick()
		end
	end))
	actionButton:Hide()
	row.ActionButton = actionButton

	row:SetScript("OnClick", ns.Measured("PortraitModes: menu row click", function(self)
		local entry = self.entry
		if not entry then return end
		if entry.kind == "feature" then
			local key = ItemKey(entry.feature)
			SetFeatureSelected(key, not IsFeatureSelected(key))
		elseif entry.kind == "sub" then
			local sub = entry.sub
			SetModuleOn(sub.module, sub.key, not ModuleOn(sub.module, sub.key))
			RefreshMenu()
		end
	end))
	row:SetScript("OnDragStart", ns.Measured("PortraitModes: drag start", function(self)
		local entry = self.entry
		if not entry then return end
		if entry.kind == "feature" then
			StartDrag(ItemKey(entry.feature))
		elseif entry.kind == "sub" then
			StartDrag(entry.sub.id)
		end
	end))
	row:SetScript("OnDragStop", ns.Measured("PortraitModes: drag stop", function()
		StopDrag(true)
	end))
	row:SetScript("OnEnter", ns.Measured("PortraitModes: menu row enter", function(self)
		if draggingFeature then return end
		local entry = self.entry
		if not entry then return end
		if entry.kind == "feature" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, entry.feature.name)
			if entry.feature.desc then
				GameTooltip_AddNormalLine(GameTooltip, entry.feature.desc)
			end
			GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODES_DRAG_TOOLTIP)
			GameTooltip:Show()
		elseif entry.kind == "sub" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, entry.sub.name)
			if entry.sub.desc then
				GameTooltip_AddNormalLine(GameTooltip, entry.sub.desc)
			end
			GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODES_DRAG_TOOLTIP)
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
		local subList = not feature.isSub and FeatureSubOptions(feature, modeKey) or nil
		local hasSubs = subList and #subList > 0 or false
		local expanded = hasSubs and IsExpanded(feature, #features, subList) or false
		entries[#entries + 1] = {
			kind = "feature",
			feature = feature,
			hasSubs = hasSubs,
			expanded = expanded,
			height = FEATURE_ROW_HEIGHT,
		}
		if expanded then
			for _, sub in ipairs(subList) do
				entries[#entries + 1] = { kind = "sub", feature = feature, sub = sub, height = SUB_ROW_HEIGHT }
			end
		end
		if not feature.isSub and feature.action then
			entries[#entries + 1] = { kind = "action", feature = feature, action = feature.action, height = ACTION_ROW_HEIGHT }
		end
	end
	return entries
end

RefreshMenu = function()
	if not (menu and menu:IsShown()) then return end
	local mode = MODE_BY_KEY[selectedMenuMode] or MODES[2]
	selectedMenuMode = mode.key
	menu:SetTitle(L.PORTRAIT_MODES_MENU_TITLE)
	if menu.SetPortraitToAsset and mode.icon then
		menu:SetPortraitToAsset(mode.icon)
	end
	local active = IsModeActive(mode.key)
	local portrait = menu.GetPortrait and menu:GetPortrait()
	if portrait and portrait.SetDesaturated then
		portrait:SetDesaturated(not active)
	end
	UpdateTabStyles()
	menu.ModeStatus:SetText(("%s: %s"):format(mode.name, StatusText(mode.key)))
	menu.ToggleButton:SetText(active and L.PORTRAIT_MODE_DISABLE or L.PORTRAIT_MODE_ENABLE)
	local _, selectedCount = ModeCounts(mode.key)
	menu.ToggleButton:SetEnabled(selectedCount > 0)

	local entries = BuildMenuEntries(mode.key)
	local totalHeight = 0
	for _, entry in ipairs(entries) do
		totalHeight = totalHeight + entry.height
	end
	local listHeight = math.max(56, math.min(MAX_LIST_HEIGHT, totalHeight))
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
				local checked = IsFeatureSelected(ItemKey(feature))
				row:EnableMouse(true)
				row.ActionButton:Hide()
				row.Check:SetSize(24, 24)
				row.Check:ClearAllPoints()
				row.Check:SetPoint("LEFT", 4, 0)
				row.Check:SetChecked(checked)
				row.Check:SetEnabled(true)
				row.Check:Show()
				row.Text:SetFontObject(checked and "GameFontHighlight" or "GameFontDisable")
				row.Text:SetText(feature.name)
				row.Text:ClearAllPoints()
				row.Text:SetPoint("LEFT", row.Check, "RIGHT", 2, 0)
				row.Text:Show()
				row.Expand:SetShown(entry.hasSubs)
				if entry.hasSubs then
					SetExpandVisual(row.Expand, entry.expanded)
					row.Text:SetPoint("RIGHT", row.Expand, "LEFT", -6, 0)
				else
					row.Text:SetPoint("RIGHT", -8, 0)
				end
			elseif entry.kind == "sub" then
				local sub = entry.sub
				local checked = ModuleOn(sub.module, sub.key)
				local parentSelected = IsFeatureSelected(entry.feature.key)
				row:EnableMouse(true)
				row.ActionButton:Hide()
				row.Expand:Hide()
				row.Check:SetSize(20, 20)
				row.Check:ClearAllPoints()
				row.Check:SetPoint("LEFT", 26, 0)
				row.Check:SetChecked(checked)
				row.Check:SetEnabled(parentSelected)
				row.Check:Show()
				row.Text:SetFontObject(parentSelected and "GameFontHighlightSmall" or "GameFontDisableSmall")
				row.Text:SetText(sub.name)
				row.Text:ClearAllPoints()
				row.Text:SetPoint("LEFT", row.Check, "RIGHT", 2, 0)
				row.Text:SetPoint("RIGHT", -8, 0)
				row.Text:Show()
			else
				row:EnableMouse(false)
				row.Check:Hide()
				row.Expand:Hide()
				row.Text:Hide()
				row.ActionButton:SetText(entry.action.text)
				row.ActionButton:Show()
			end
			row:Show()
		end
	end
	for i = visibleCount + 1, #menu.rows do
		menu.rows[i].entry = nil
		menu.rows[i]:Hide()
	end
	menu.ResetButton:SetEnabled(HasCustomAssignments())
	menu:SetHeight(INSET_TOP + HEADER_HEIGHT + listHeight + 16 + INSET_BOTTOM)
end

local function CreateModeMenu()
	if menu then return menu end
	local panel = CreateFrame("Frame", "ForeverPlusPortraitModeMenu", UIParent, "PortraitFrameTemplate")
	panel:Hide()
	panel:SetSize(MENU_WIDTH, 320)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", ns.Measured("PortraitModes: move menu", panel.StartMoving))
	panel:SetScript("OnDragStop", ns.Measured("PortraitModes: stop moving menu", panel.StopMovingOrSizing))
	panel.tabPadding = 12
	panel.CloseButton:SetScript("OnClick", ns.Measured("PortraitModes: close menu", function() panel:Hide() end))
	tinsert(UISpecialFrames, "ForeverPlusPortraitModeMenu")
	ns.FadeIn(panel)
	panel.tabs = {}
	panel.rows = {}

	local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 11, -INSET_TOP)
	inset:SetPoint("BOTTOMRIGHT", -11, INSET_BOTTOM)
	panel.Inset = inset

	local previousTab
	for i, mode in ipairs(SELECTABLE_MODES) do
		local tab = CreateFrame("Button", nil, panel, "PanelTopTabButtonTemplate")
		tab.modeKey = mode.key
		tab:SetText(mode.short)
		if previousTab then
			tab:SetPoint("LEFT", previousTab, "RIGHT", 4, 0)
		else
			tab:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 6, -2)
		end
		previousTab = tab
		tab.DropGlow = tab:CreateTexture(nil, "OVERLAY")
		tab.DropGlow:SetAllPoints()
		tab.DropGlow:SetTexture(ROW_HIGHLIGHT)
		tab.DropGlow:SetBlendMode("ADD")
		tab.DropGlow:Hide()
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

	local header = CreateFrame("Frame", nil, inset)
	header:SetPoint("TOPLEFT", 8, -6)
	header:SetPoint("TOPRIGHT", -8, -6)
	header:SetHeight(HEADER_HEIGHT - 6)
	panel.ModeStatus = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.ModeStatus:SetPoint("LEFT", 4, 0)
	panel.ModeStatus:SetJustifyH("LEFT")

	local toggleButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	toggleButton:SetSize(108, 22)
	toggleButton:SetPoint("RIGHT", -2, 0)
	toggleButton:SetScript("OnClick", ns.Measured("PortraitModes: menu toggle mode", function()
		ToggleMode(selectedMenuMode)
	end))
	panel.ToggleButton = toggleButton

	local divider = inset:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", 8, -(HEADER_HEIGHT + 2))
	divider:SetPoint("TOPRIGHT", -8, -(HEADER_HEIGHT + 2))
	divider:SetColorTexture(0.62, 0.48, 0.28, 0.55)

	local list = CreateFrame("Frame", nil, inset)
	list:SetPoint("TOPLEFT", 6, -(HEADER_HEIGHT + 8))
	list:SetPoint("TOPRIGHT", -6, -(HEADER_HEIGHT + 8))
	list:SetClipsChildren(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", ns.Measured("PortraitModes: menu scroll", function(_, delta)
		listScrollOffset = listScrollOffset - delta * 24
		RefreshMenu()
	end))
	panel.List = list

	panel.Empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Empty:SetPoint("LEFT", 10, 0)
	panel.Empty:SetPoint("RIGHT", -10, 0)
	panel.Empty:SetJustifyH("CENTER")
	panel.Empty:SetText(L.PORTRAIT_MODES_EMPTY)
	panel.Empty:Hide()

	panel.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.Hint:SetPoint("BOTTOMLEFT", 14, 15)
	panel.Hint:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -116, 15)
	panel.Hint:SetJustifyH("LEFT")
	panel.Hint:SetWordWrap(false)
	panel.Hint:SetText(L.PORTRAIT_MODES_DRAG_HINT)

	local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetButton:SetSize(96, 22)
	resetButton:SetPoint("BOTTOMRIGHT", -12, 10)
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
local portraitWheel, portraitBackground, portraitIcon, portraitShine, portraitIconMask
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
	local checkMark = AtlasIcon("common-icon-checkmark", 12)
	local crossMark = AtlasIcon("common-icon-redx", 11)
	GameTooltip:SetOwner(portraitWheel, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, ("%s (%s)"):format(mode.name, StatusText(mode.key)))
	local features = ModeFeatures(mode.key)
	if #features == 0 then
		GameTooltip_AddColoredLine(GameTooltip, L.PORTRAIT_MODES_EMPTY_SHORT, GRAY_FONT_COLOR)
	else
		for _, feature in ipairs(features) do
			local selected = IsFeatureSelected(ItemKey(feature))
			local on = feature.isOn()
			local color = not selected and GRAY_FONT_COLOR or (on and GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
			local prefix
			if not selected then
				prefix = "- "
			elseif on then
				prefix = checkMark ~= "" and (checkMark .. " ") or "+ "
			else
				prefix = crossMark ~= "" and (crossMark .. " ") or "- "
			end
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
		iconShown = portraitIcon:SetTexture(mode.icon) ~= false
		portraitIcon:SetDesaturated(not active)
		if active then
			local bg = mode.bg
			portraitBackground:SetColorTexture(bg[1], bg[2], bg[3], 1)
			portraitIcon:SetVertexColor(1, 1, 1)
			portraitIcon:SetAlpha(1)
		else
			portraitBackground:SetColorTexture(0.08, 0.08, 0.09, 1)
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

	-- Use the portrait's own mask for the backdrop, and a smaller round emblem mask
	-- offset up-right so the level badge at the bottom-left never overlaps the icon.
	portraitBackground = container:CreateTexture(nil, "ARTWORK", nil, 0)
	portraitBackground:SetAllPoints(portrait)
	portraitBackground:AddMaskTexture(mask)
	portraitBackground:SetColorTexture(0.08, 0.08, 0.09, 1)

	portraitIcon = container:CreateTexture(nil, "ARTWORK", nil, 1)
	portraitIcon:SetSize(EMBLEM_SIZE, EMBLEM_SIZE)
	portraitIcon:SetPoint("CENTER", portrait, "CENTER", EMBLEM_OFFSET_X, EMBLEM_OFFSET_Y)
	portraitIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	portraitIconMask = container:CreateMaskTexture()
	portraitIconMask:SetAllPoints(portraitIcon)
	portraitIconMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	portraitIcon:AddMaskTexture(portraitIconMask)
	portraitIcon:AddMaskTexture(mask)

	portraitShine = container:CreateTexture(nil, "ARTWORK", nil, 2)
	portraitShine:SetAllPoints(portraitIcon)
	portraitShine:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	portraitShine:AddMaskTexture(portraitIconMask)
	portraitShine:AddMaskTexture(mask)
	portraitShine:SetBlendMode("ADD")
	portraitShine:SetAlpha(0.24)
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

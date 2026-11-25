-- Shift-wheel mode switcher on the player portrait with left-click toggle
-- and a right-click WoW-style window supporting drag-and-drop between modes.
local _, ns = ...
local L = ns.L

local PortraitModes = {}
ns.PortraitModes = PortraitModes

local ROW_HIGHLIGHT = [[Interface\QuestFrame\UI-QuestTitleHighlight]]
local ICON_HIGHLIGHT = [[Interface\Buttons\ButtonHilight-Square]]
local ICON_SELECTED = [[Interface\Buttons\UI-ActionButton-Border]]
local PORTRAIT_SHADE = [[Interface\AddOns\ForeverPlus\Media\PortraitModeShade]]
local PLUS_UP = [[Interface\Buttons\UI-PlusButton-Up]]
local PLUS_DOWN = [[Interface\Buttons\UI-PlusButton-Down]]
local MINUS_UP = [[Interface\Buttons\UI-MinusButton-Up]]
local MINUS_DOWN = [[Interface\Buttons\UI-MinusButton-Down]]
local PLUS_HIGHLIGHT = [[Interface\Buttons\UI-PlusButton-Hilight]]

-- Slot 1 is always the standard Blizzard portrait; slots 2..5 use full-bleed
-- original Blizzard icons from the client (every ID verified in Data/MacroIcons.lua).
local MODES = {
	{ key = "normal" },
	{
		key = "wanderlust",
		name = L.WANDERLUST_TITLE,
		short = L.WANDERLUST_TITLE,
		icon = 237386,
		iconRotation = -math.rad(35),
		presets = { 237386, 456568, 134269, 134377, 134249, 134440, 237382, 413583, 132144, 135725 },
	},
	{
		key = "angler",
		name = L.HELPERS_FISHING_MODE,
		short = L.PORTRAIT_MODE_ANGLER_SHORT,
		icon = 643874,
		presets = { 643874, 136245, 132931, 132932, 236574, 236572, 133888, 774121, 612075, 133887 },
	},
	{
		key = "rp",
		name = L.PORTRAIT_MODE_RP,
		short = L.PORTRAIT_MODE_RP_SHORT,
		icon = 133740,
		presets = { 133740, 133460, 133458, 133735, 133742, 133743, 134328, 132920, 133736, 133739 },
	},
	{
		key = "berserker",
		name = L.PORTRAIT_MODE_BERSERKER,
		short = L.PORTRAIT_MODE_BERSERKER_SHORT,
		icon = 132400,
		presets = { 132400, 132397, 132403, 132393, 132355, 132277, 136009, 236364, 236304, 236303 },
	},
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
			{ module = "Wanderlust", key = "softHide", name = L.WANDERLUST_SOFT_HIDE, desc = L.WANDERLUST_SOFT_HIDE_DESC },
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
		key = "guidingWind",
		defaultMode = "wanderlust",
		defaultSelected = false,
		name = L.WIND_TITLE,
		desc = L.WIND_ENABLE_DESC,
		modules = { GuidingWind = true },
		isOn = function() return ModuleOn("GuidingWind", "enabled") end,
		setOn = function(on) SetModuleOn("GuidingWind", "enabled", on) end,
		subOptions = {
			{ module = "GuidingWind", key = "autoGusts", name = L.WIND_AUTO, desc = L.WIND_AUTO_DESC },
			{ module = "GuidingWind", key = "biomeParticles", name = L.WIND_BIOME, desc = L.WIND_BIOME_DESC },
			{ module = "GuidingWind", key = "sound", name = L.WIND_SOUND, desc = L.WIND_SOUND_DESC },
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
			{ module = "Helpers", key = "fishingBear", name = L.HELPERS_FISHING_BEAR, desc = L.HELPERS_FISHING_BEAR_DESC },
			{ module = "Helpers", key = "fishingBearSound", name = L.HELPERS_FISHING_BEAR_SOUND, desc = L.HELPERS_FISHING_BEAR_SOUND_DESC },
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

local visualsModule
local suppressOptionNotify = false

local function VisualsDB()
	local visuals = visualsModule or ns:GetModule("Visuals")
	if not visuals then return nil, nil end
	visualsModule = visuals
	if visuals.db then
		if type(visuals.db.portraitModeAssignments) ~= "table" then
			visuals.db.portraitModeAssignments = {}
		end
		if type(visuals.db.portraitModeDisabled) ~= "table" then
			visuals.db.portraitModeDisabled = {}
		end
		if type(visuals.db.portraitModeIcons) ~= "table" then
			visuals.db.portraitModeIcons = {}
		end
	end
	return visuals.db, visuals.cdb
end

local function ModeIcon(modeKey)
	local mode = MODE_BY_KEY[modeKey]
	if not mode then return nil end
	local db = VisualsDB()
	local custom = db and db.portraitModeIcons[modeKey]
	if type(custom) == "number" and custom > 0 then
		return custom
	end
	return mode.icon
end

local function ModeIconRotation(modeKey, icon)
	local mode = MODE_BY_KEY[modeKey]
	return mode and icon == mode.icon and mode.iconRotation or 0
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
	local item = ITEM_BY_KEY[itemKey]
	local db = VisualsDB()
	local saved = db and db.portraitModeDisabled[itemKey]
	if saved ~= nil then
		return not saved
	end
	return not (item and item.defaultSelected == false)
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

local UpdatePlayerPortrait, RefreshMenu, RefreshIconPicker, StopDrag

---------------------------------------------------------------------------
-- Mode activation portrait flashes and natural-decay client sounds
---------------------------------------------------------------------------
local Flash = {
	frame = nil,
	activeMode = nil,
	profile = nil,
	elapsed = nil,
	baseSize = 720,
	gen = 0,
	handles = {},
	fileIndex = {},
	profiles = {
		wanderlust = {
			art = [[Interface\AddOns\ForeverPlus\Media\ModeBrann.tga]],
			fadeIn = 0.24,
			hold = 0.54,
			shrink = 0.87,
			startScale = 0.92,
			peakScale = 1.00,
			minScale = 0.04,
			maxAlpha = 0.50,
			sound1 = { kit = "IG_QUEST_LOG_OPEN", fallbackKit = 844 },
			sound2 = { delay = 0.22, files = { 982361, 982363, 982365, 982367 } },
		},
		rp = {
			art = [[Interface\AddOns\ForeverPlus\Media\ModeChromie.tga]],
			fadeIn = 0.22,
			hold = 0.48,
			shrink = 0.85,
			startScale = 0.94,
			peakScale = 1.00,
			minScale = 0.04,
			maxAlpha = 0.50,
			sound1 = { kit = "IG_SPELLBOOK_OPEN", fallbackKit = 829 },
			sound2 = { delay = 0.26, kit = "IG_WRITE_QUEST", fallbackKit = 3093 },
		},
		berserker = {
			artAlliance = [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]],
			artHorde = [[Interface\AddOns\ForeverPlus\Media\ModeGrommash.tga]],
			fadeIn = 0.14,
			hold = 0.42,
			shrink = 0.74,
			startScale = 0.84,
			peakScale = 1.04,
			minScale = 0.04,
			maxAlpha = 0.56,
			sound1 = { files = { 567473 } },
			sound2 = { delay = 0.18, files = { 567634, 1324858, 1324859 } },
		},
	},
}

function Flash.ArtPath(modeKey, variant)
	local profile = Flash.profiles[modeKey]
	if not profile then return nil end
	if profile.art then
		return profile.art
	end
	if variant == "grommash" then
		return profile.artHorde
	elseif variant == "muradin" then
		return profile.artAlliance
	end
	local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
	if faction and not ns.Secret(faction) and faction == "Horde" then
		return profile.artHorde
	end
	return profile.artAlliance
end

function Flash.StopSounds()
	Flash.gen = Flash.gen + 1
	for i = 1, #Flash.handles do
		if StopSound then
			StopSound(Flash.handles[i])
		end
		Flash.handles[i] = nil
	end
end

function Flash.PlaySoundSpec(spec, key)
	if not spec then return end
	local ok, handle
	if spec.files then
		if not PlaySoundFile then return end
		local idx = ((Flash.fileIndex[key] or 0) % #spec.files) + 1
		Flash.fileIndex[key] = idx
		ok, handle = PlaySoundFile(spec.files[idx], "SFX")
	elseif spec.kit or spec.fallbackKit then
		if not PlaySound then return end
		local kitID = (SOUNDKIT and spec.kit and SOUNDKIT[spec.kit]) or spec.fallbackKit
		if kitID then
			ok, handle = PlaySound(kitID, "SFX")
		end
	end
	if ok and handle then
		Flash.handles[#Flash.handles + 1] = handle
	end
end

function Flash.PlaySounds(modeKey, profile)
	Flash.StopSounds()
	local db = VisualsDB()
	if not (db and db.portraitModeFlashSound) then
		return
	end
	local gen = Flash.gen
	Flash.PlaySoundSpec(profile.sound1, modeKey .. ":1")
	if profile.sound2 then
		ns.After("PortraitModes: mode flash sound", profile.sound2.delay or 0.20, function()
			local cur = VisualsDB()
			if gen ~= Flash.gen or not (cur and cur.portraitModeFlashSound) then
				return
			end
			Flash.PlaySoundSpec(profile.sound2, modeKey .. ":2")
		end)
	end
end

function Flash.BaseSize()
	local width = ns.Number(UIParent and UIParent:GetWidth(), 1280)
	local height = ns.Number(UIParent and UIParent:GetHeight(), 720)
	local size = math.min(width, height) * 0.96
	return size > 0 and size or 720
end

function Flash.Apply(t)
	local profile = Flash.profile
	if not (profile and Flash.frame) then return end
	local alpha, scale
	local fadeIn, hold, shrink = profile.fadeIn, profile.hold, profile.shrink
	local peak = profile.peakScale or 1
	if t < fadeIn then
		local p = t / fadeIn
		local eased = 1 - (1 - p) * (1 - p)
		alpha = profile.maxAlpha * eased
		scale = profile.startScale + (peak - profile.startScale) * eased
	elseif t < fadeIn + hold then
		alpha = profile.maxAlpha
		if peak ~= 1 then
			local p = math.min(1, (t - fadeIn) / (hold * 0.5))
			scale = peak + (1 - peak) * (1 - (1 - p) * (1 - p))
		else
			scale = 1
		end
	else
		local p = math.min(1, (t - fadeIn - hold) / shrink)
		local eased = p * p * (0.4 + 0.6 * p)
		scale = 1 - (1 - profile.minScale) * eased
		alpha = profile.maxAlpha * (1 - p * p)
	end
	local size = Flash.baseSize * scale
	Flash.frame:SetSize(size, size)
	Flash.frame:SetAlpha(alpha)
end

function Flash.Hide()
	Flash.elapsed = nil
	Flash.activeMode = nil
	Flash.profile = nil
	if Flash.frame then
		ns.SetUpdate(Flash.frame, "PortraitModes: mode flash", nil)
		Flash.frame:SetAlpha(0)
		if Flash.frame:IsShown() then
			Flash.frame:Hide()
		end
	end
end

function Flash.Stop()
	Flash.StopSounds()
	Flash.Hide()
end

function Flash.OnUpdate(_, delta)
	local profile = Flash.profile
	if not (Flash.elapsed and profile) then
		Flash.Hide()
		return
	end
	Flash.elapsed = Flash.elapsed + (delta or 0)
	local total = profile.fadeIn + profile.hold + profile.shrink
	if Flash.elapsed >= total then
		-- Let mode sounds finish decaying naturally without cutting them off.
		Flash.Hide()
		return
	end
	Flash.Apply(Flash.elapsed)
end

function Flash.EnsureFrame()
	if Flash.frame then
		return Flash.frame
	end
	local frame = CreateFrame("Frame", "ForeverPlusModeFlash", UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(100)
	frame:EnableMouse(false)
	if frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame.art = frame:CreateTexture(nil, "OVERLAY")
	frame.art:SetAllPoints()
	frame:SetScript("OnHide", ns.Measured("PortraitModes: mode flash hide", Flash.Hide))
	frame:Hide()
	Flash.frame = frame
	return frame
end

function Flash.Show(modeKey, variant)
	local profile = Flash.profiles[modeKey]
	if not profile then return false end
	local helpers = ns:GetModule("Helpers")
	if helpers and helpers.StopBearFlash then
		helpers.StopBearFlash()
	end
	local frame = Flash.EnsureFrame()
	local art = Flash.ArtPath(modeKey, variant)
	frame.art:SetTexture(art)
	Flash.activeMode = modeKey
	Flash.profile = profile
	Flash.baseSize = Flash.BaseSize()
	Flash.elapsed = 0
	Flash.Apply(0)
	frame:Show()
	ns.SetUpdate(frame, "PortraitModes: mode flash", Flash.OnUpdate)
	Flash.PlaySounds(modeKey, profile)
	return true
end

function PortraitModes.StopFlash()
	Flash.Stop()
end

function PortraitModes.StopFlashSounds()
	Flash.StopSounds()
end

function PortraitModes.PreviewFlash(modeKey, variant)
	if modeKey == "angler" then
		local helpers = ns:GetModule("Helpers")
		if helpers and helpers.PreviewBear then
			helpers.PreviewBear()
			return true
		end
		return false
	end
	return Flash.Show(modeKey, variant)
end

local function SetModeIcon(modeKey, iconID)
	local mode = MODE_BY_KEY[modeKey]
	local db = VisualsDB()
	if not (mode and db and modeKey ~= "normal") then return false end
	if type(iconID) ~= "number" or iconID <= 0 then return false end
	db.portraitModeIcons[modeKey] = (iconID ~= mode.icon) and iconID or nil
	UpdatePlayerPortrait()
	RefreshMenu()
	RefreshIconPicker()
	return true
end

local function ToggleMode(modeKey)
	if not MODE_BY_KEY[modeKey] or modeKey == "normal" then return end
	local wasActive = IsModeActive(modeKey)
	local target = not wasActive
	suppressOptionNotify = true
	for _, feature in ipairs(ModeFeatures(modeKey)) do
		if IsFeatureSelected(ItemKey(feature)) then
			feature.setOn(target)
		end
	end
	suppressOptionNotify = false
	if modeKey ~= "angler" then
		local db = VisualsDB()
		if not wasActive and target and IsModeActive(modeKey) then
			if db and db.portraitModeFlash then
				Flash.Show(modeKey)
			end
		elseif not target and Flash.activeMode == modeKey then
			Flash.Stop()
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
	local defaultOn = item.defaultSelected ~= false
	local disabled = not selected
	if disabled == (not defaultOn) then
		db.portraitModeDisabled[itemKey] = nil
	else
		db.portraitModeDisabled[itemKey] = disabled
	end
	if wasActive then
		suppressOptionNotify = true
		item.setOn(selected and true or false)
		suppressOptionNotify = false
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
		suppressOptionNotify = true
		if targetWasActive and not sourceWasActive and (not item.isSub or IsDetachedSub(item)) then
			item.setOn(true)
		elseif sourceWasActive and not targetWasActive and (not item.isSub or wasDetachedSub) then
			item.setOn(false)
		end
		suppressOptionNotify = false
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
	wipe(db.portraitModeIcons)
	UpdatePlayerPortrait()
	RefreshMenu()
	RefreshIconPicker()
end

local function HasCustomAssignments()
	local db = VisualsDB()
	if not db then return false end
	return next(db.portraitModeAssignments) ~= nil
		or next(db.portraitModeDisabled) ~= nil
		or next(db.portraitModeIcons) ~= nil
end

-- Exposed helpers for unit tests and inspection.
PortraitModes.MODES = MODES
PortraitModes.FEATURES = FEATURES
PortraitModes.ModeIcon = ModeIcon
PortraitModes.SetModeIcon = SetModeIcon
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

local menu, iconPicker, dragGhost
local selectedMenuMode = "wanderlust"
local expandedFeatures = {}
local draggingFeature, hoveredDropTab
local listScrollOffset = 0
local pickerIcons, pickerOffset, pickerSearchToken = {}, 0, 0
local PICKER_COLS, PICKER_ROWS = 5, 5
local PICKER_CELL, PICKER_GAP = 36, 5
local PICKER_MAX_RESULTS = 200

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
	local icon = ModeIcon(mode.key)
	if menu.SetPortraitToAsset and icon then
		menu:SetPortraitToAsset(icon)
	end
	local active = IsModeActive(mode.key)
	local portrait = menu.GetPortrait and menu:GetPortrait()
	if portrait and portrait.SetDesaturated then
		portrait:SetDesaturated(not active)
	end
	if portrait and portrait.SetRotation then
		portrait:SetRotation(ModeIconRotation(mode.key, icon))
	end
	if iconPicker and iconPicker:IsShown() then
		RefreshIconPicker()
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

local function RenderIconGrid()
	if not (iconPicker and iconPicker:IsShown()) then return end
	local perPage = PICKER_COLS * PICKER_ROWS
	local totalRows = math.ceil(#pickerIcons / PICKER_COLS)
	local maxOffset = math.max(0, totalRows - PICKER_ROWS)
	pickerOffset = math.max(0, math.min(pickerOffset, maxOffset))
	local currentIcon = ModeIcon(selectedMenuMode)
	if iconPicker.SetPortraitToAsset and currentIcon then
		iconPicker:SetPortraitToAsset(currentIcon)
	end
	local pickerPortrait = iconPicker.GetPortrait and iconPicker:GetPortrait()
	if pickerPortrait and pickerPortrait.SetRotation then
		pickerPortrait:SetRotation(ModeIconRotation(selectedMenuMode, currentIcon))
	end
	iconPicker.Empty:SetShown(#pickerIcons == 0)
	local startIndex = pickerOffset * PICKER_COLS
	for i = 1, perPage do
		local cell = iconPicker.cells[i]
		local iconID = pickerIcons[startIndex + i]
		cell.iconID = iconID
		if iconID then
			cell.Icon:SetTexture(iconID)
			cell.Selected:SetShown(iconID == currentIcon)
			cell:Show()
		else
			cell:Hide()
		end
	end
end

local function RunIconSearch(query)
	pickerSearchToken = pickerSearchToken + 1
	local token = pickerSearchToken
	pickerOffset = 0
	local trimmed = strtrim(query or "")
	local mode = MODE_BY_KEY[selectedMenuMode] or MODES[2]
	if trimmed == "" then
		pickerIcons = {}
		for _, id in ipairs(mode.presets or {}) do
			pickerIcons[#pickerIcons + 1] = id
		end
		RenderIconGrid()
		return
	end
	local macroIcons = ns:GetModule("MacroIcons")
	local data = ns.MacroIconNames
	if not (macroIcons and macroIcons.StartFind and macroIcons.StepFind and type(data) == "string") then
		pickerIcons = {}
		RenderIconGrid()
		return
	end
	local state = macroIcons.StartFind(data, trimmed)
	if not state then
		pickerIcons = {}
		RenderIconGrid()
		return
	end
	local function Finish()
		if token ~= pickerSearchToken then return end
		local results = {}
		for id in pairs(state.found) do
			results[#results + 1] = id
		end
		table.sort(results)
		pickerIcons = {}
		local limit = math.min(#results, PICKER_MAX_RESULTS)
		for i = 1, limit do
			pickerIcons[i] = results[i]
		end
		RenderIconGrid()
	end
	ns.RunSliced("PortraitModes: icon search", 0.5, function(deadline)
		if token ~= pickerSearchToken then return true end
		return macroIcons.StepFind(state, deadline)
	end, Finish)
end

RefreshIconPicker = function()
	if not (iconPicker and iconPicker:IsShown()) then return end
	local query = iconPicker.Search and iconPicker.Search:GetText() or ""
	if strtrim(query) == "" then
		RunIconSearch("")
	else
		RenderIconGrid()
	end
end

local function CreateIconPicker()
	if iconPicker then return iconPicker end
	local width = 22 + PICKER_COLS * PICKER_CELL + (PICKER_COLS - 1) * PICKER_GAP + 20
	local height = 104 + PICKER_ROWS * PICKER_CELL + (PICKER_ROWS - 1) * PICKER_GAP + 22
	local panel = CreateFrame("Frame", "ForeverPlusPortraitModeIconPicker", UIParent, "PortraitFrameTemplate")
	panel:Hide()
	panel:SetSize(width, height)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetTitle(L.PORTRAIT_MODES_ICON_TITLE)
	panel.CloseButton:SetScript("OnClick", ns.Measured("PortraitModes: close icon picker", function()
		panel:Hide()
	end))
	tinsert(UISpecialFrames, "ForeverPlusPortraitModeIconPicker")
	ns.FadeIn(panel)

	local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 11, -64)
	inset:SetPoint("BOTTOMRIGHT", -11, 12)

	local search = CreateFrame("EditBox", nil, inset, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", 12, -10)
	search:SetPoint("TOPRIGHT", -10, -10)
	search:SetHeight(22)
	search:SetAutoFocus(false)
	search:SetMaxLetters(80)
	search.Instructions:SetText(L.PORTRAIT_MODES_ICON_SEARCH)
	search:HookScript("OnTextChanged", ns.Measured("PortraitModes: search mode icons", function(self)
		if panel:IsShown() then
			RunIconSearch(self:GetText())
		end
	end))
	panel.Search = search

	local grid = CreateFrame("Frame", nil, inset)
	grid:SetPoint("TOPLEFT", 10, -38)
	grid:SetPoint("BOTTOMRIGHT", -10, 8)
	grid:EnableMouseWheel(true)
	grid:SetScript("OnMouseWheel", ns.Measured("PortraitModes: scroll icon picker", function(_, delta)
		pickerOffset = pickerOffset - delta
		RenderIconGrid()
	end))

	panel.Empty = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Empty:SetPoint("CENTER")
	panel.Empty:SetText(L.PORTRAIT_MODES_ICON_EMPTY)
	panel.Empty:Hide()

	panel.cells = {}
	for i = 1, PICKER_COLS * PICKER_ROWS do
		local rowIdx = math.floor((i - 1) / PICKER_COLS)
		local colIdx = (i - 1) % PICKER_COLS
		local cell = CreateFrame("Button", nil, grid)
		cell:SetSize(PICKER_CELL, PICKER_CELL)
		cell:SetPoint("TOPLEFT", colIdx * (PICKER_CELL + PICKER_GAP), -rowIdx * (PICKER_CELL + PICKER_GAP))
		cell:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
		cell.Icon = cell:CreateTexture(nil, "ARTWORK")
		cell.Icon:SetAllPoints()
		cell.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		cell.Selected = cell:CreateTexture(nil, "OVERLAY")
		cell.Selected:SetTexture(ICON_SELECTED)
		cell.Selected:SetBlendMode("ADD")
		cell.Selected:SetVertexColor(1, 0.85, 0.2)
		cell.Selected:SetPoint("CENTER")
		cell.Selected:SetSize(PICKER_CELL * 1.65, PICKER_CELL * 1.65)
		cell.Selected:Hide()
		cell:SetScript("OnClick", ns.Measured("PortraitModes: pick mode icon", function(self)
			if self.iconID then
				SetModeIcon(selectedMenuMode, self.iconID)
			end
		end))
		panel.cells[i] = cell
	end

	panel:SetScript("OnHide", ns.Measured("PortraitModes: hide icon picker", function()
		pickerSearchToken = pickerSearchToken + 1
	end))

	iconPicker = panel
	return panel
end

local function ToggleIconPicker()
	local picker = CreateIconPicker()
	if picker:IsShown() then
		picker:Hide()
		return
	end
	picker:ClearAllPoints()
	picker:SetPoint("TOPLEFT", menu, "TOPRIGHT", 6, 0)
	picker.Search:SetText("")
	picker:Show()
	RunIconSearch("")
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
	panel.ModeStatus:SetWordWrap(false)

	local toggleButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	toggleButton:SetSize(108, 22)
	toggleButton:SetPoint("RIGHT", -2, 0)
	toggleButton:SetScript("OnClick", ns.Measured("PortraitModes: menu toggle mode", function()
		ToggleMode(selectedMenuMode)
	end))
	panel.ToggleButton = toggleButton

	local previewButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	previewButton:SetSize(74, 22)
	previewButton:SetPoint("RIGHT", toggleButton, "LEFT", -6, 0)
	previewButton:SetText(L.PORTRAIT_MODES_PREVIEW)
	previewButton:SetScript("OnClick", ns.Measured("PortraitModes: preview mode flash", function()
		PortraitModes.PreviewFlash(selectedMenuMode)
	end))
	previewButton:SetScript("OnEnter", ns.Measured("PortraitModes: preview button tooltip", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L.PORTRAIT_MODES_PREVIEW)
		GameTooltip_AddNormalLine(GameTooltip, L.PORTRAIT_MODES_PREVIEW_DESC)
		GameTooltip:Show()
	end))
	previewButton:SetScript("OnLeave", GameTooltip_Hide)
	panel.PreviewButton = previewButton
	panel.ModeStatus:SetPoint("RIGHT", previewButton, "LEFT", -6, 0)

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
	panel.Hint:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -196, 15)
	panel.Hint:SetJustifyH("LEFT")
	panel.Hint:SetWordWrap(false)
	panel.Hint:SetText(L.PORTRAIT_MODES_DRAG_HINT)

	local iconButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	iconButton:SetSize(74, 22)
	iconButton:SetPoint("BOTTOMRIGHT", -114, 10)
	iconButton:SetText(L.PORTRAIT_MODES_ICON_BUTTON)
	iconButton:SetScript("OnClick", ns.Measured("PortraitModes: open icon picker", ToggleIconPicker))
	iconButton:SetScript("OnEnter", ns.Measured("PortraitModes: icon button tooltip", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L.PORTRAIT_MODES_ICON_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, L.PORTRAIT_MODES_ICON_HINT)
		GameTooltip:Show()
	end))
	iconButton:SetScript("OnLeave", GameTooltip_Hide)
	panel.IconButton = iconButton

	local portraitHit = CreateFrame("Button", nil, panel)
	portraitHit:SetSize(58, 58)
	portraitHit:SetPoint("TOPLEFT", -4, 4)
	portraitHit:SetFrameLevel(panel:GetFrameLevel() + 12)
	portraitHit:SetScript("OnClick", ns.Measured("PortraitModes: portrait icon picker", ToggleIconPicker))
	portraitHit:SetScript("OnEnter", ns.Measured("PortraitModes: portrait icon tooltip", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.PORTRAIT_MODES_ICON_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, L.PORTRAIT_MODES_ICON_HINT)
		GameTooltip:Show()
	end))
	portraitHit:SetScript("OnLeave", GameTooltip_Hide)

	local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetButton:SetSize(96, 22)
	resetButton:SetPoint("BOTTOMRIGHT", -12, 10)
	resetButton:SetText(L.PORTRAIT_MODES_RESET)
	resetButton:SetScript("OnClick", ns.Measured("PortraitModes: reset assignments", ResetAssignments))
	panel.ResetButton = resetButton

	panel:SetScript("OnEvent", ns.Measured("PortraitModes: menu outside click", function(self)
		if draggingFeature then return end
		if iconPicker and iconPicker:IsShown() and iconPicker:IsMouseOver() then return end
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
		if iconPicker and iconPicker:IsShown() then
			iconPicker:Hide()
		end
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
local portraitWheel, portraitBackground, portraitIcon, portraitShade, portraitShine
local optionListenerRegistered
local wanderlustHidden = false

local function ShowsOwnPortrait()
	local unit = PlayerFrame and PlayerFrame.unit
	return not ns.Secret(unit) and unit == "player"
end

local function PlayerFrameVisible()
	return not wanderlustHidden and PlayerFrame
		and (not PlayerFrame.GetEffectiveAlpha or ns.Number(PlayerFrame:GetEffectiveAlpha(), 1) > 0.05) or false
end

local function CanCyclePortrait()
	local db = VisualsDB()
	return db and db.playerPortraitWheel and ShowsOwnPortrait() and PlayerFrameVisible()
		and not EditModeManagerFrame:IsEditModeActive() or false
end

local function CurrentMode()
	local db, cdb = VisualsDB()
	if not (db and cdb and db.playerPortraitWheel and ShowsOwnPortrait()) then
		return nil
	end
	return MODES[cdb.playerPortraitMode] or MODES[1]
end

local lastWheelEnabled, lastInteractive

local function UpdatePortraitInput(_, event, key)
	if not portraitWheel then return end
	if event == "MODIFIER_STATE_CHANGED" and key and key ~= "LSHIFT" and key ~= "RSHIFT" then
		return
	end
	local canUse = CanCyclePortrait()
	local mode = CurrentMode()
	local interactive = canUse and mode ~= nil and mode.key ~= "normal"
	local wheelEnabled = canUse and IsShiftKeyDown() and true or false
	if lastWheelEnabled ~= wheelEnabled then
		lastWheelEnabled = wheelEnabled
		portraitWheel:EnableMouseWheel(wheelEnabled)
	end
	if lastInteractive ~= interactive then
		lastInteractive = interactive
		portraitWheel:SetMouseClickEnabled(interactive)
		portraitWheel:SetMouseMotionEnabled(interactive)
	end
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
	local subCheck = AtlasIcon("common-icon-checkmark", 10)
	local subCross = AtlasIcon("common-icon-redx", 9)
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
			if not feature.isSub then
				local subs = FeatureSubOptions(feature, mode.key)
				if subs then
					for _, sub in ipairs(subs) do
						local subOn = sub.isOn()
						local subColor = not selected and GRAY_FONT_COLOR
							or (subOn and (on and GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR) or GRAY_FONT_COLOR)
						local subPrefix
						if not selected then
							subPrefix = "   - "
						elseif subOn then
							subPrefix = "   " .. (subCheck ~= "" and (subCheck .. " ") or "+ ")
						else
							subPrefix = "   " .. (subCross ~= "" and (subCross .. " ") or "- ")
						end
						GameTooltip_AddColoredLine(GameTooltip, subPrefix .. sub.name, subColor)
					end
				end
			end
		end
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_LEFT)
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_RIGHT)
	GameTooltip_AddInstructionLine(GameTooltip, L.PORTRAIT_MODE_HINT_WHEEL)
	GameTooltip:Show()
end

UpdatePlayerPortrait = function()
	if not portraitWheel then return end
	if wanderlustHidden then
		portraitIcon:Hide()
		portraitBackground:Hide()
		if portraitShade then portraitShade:Hide() end
		if portraitShine then portraitShine:Hide() end
		UpdatePortraitInput()
		return
	end
	local mode = CurrentMode()
	local iconShown = false
	local icon = mode and mode.key ~= "normal" and ModeIcon(mode.key)
	if icon then
		local active = IsModeActive(mode.key)
		local rotation = ModeIconRotation(mode.key, icon)
		iconShown = portraitIcon:SetTexture(icon) ~= false
		portraitIcon:SetRotation(rotation)
		portraitIcon:SetDesaturated(not active)
		if active then
			-- Slightly warm, toned brightness so icons sit naturally inside the bronze portrait frame.
			portraitIcon:SetVertexColor(0.92, 0.90, 0.86)
			portraitIcon:SetAlpha(1)
		else
			portraitIcon:SetVertexColor(0.68, 0.68, 0.68)
			portraitIcon:SetAlpha(0.84)
		end
		if portraitShine then
			portraitShine:SetTexture(icon)
			portraitShine:SetRotation(rotation)
		end
	end
	portraitIcon:SetShown(iconShown)
	portraitBackground:SetShown(iconShown)
	if portraitShade then
		portraitShade:SetShown(iconShown)
	end
	if not iconShown and portraitShine then
		portraitShine:Hide()
	end
	UpdatePortraitInput()
	if portraitWheel:IsMouseOver() and iconShown then
		ShowPortraitTooltip()
	end
end

local function OnAnyOptionChanged(moduleName)
	if not suppressOptionNotify and WATCHED_MODULES[moduleName] then
		UpdatePlayerPortrait()
		RefreshMenu()
	end
end

function PortraitModes.SetWanderlustHidden(hidden)
	hidden = hidden and true or false
	if hidden == wanderlustHidden then return end
	wanderlustHidden = hidden
	UpdatePlayerPortrait()
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

	-- Fill the portrait circle edge-to-edge under the portrait's own mask.
	portraitBackground = container:CreateTexture(nil, "ARTWORK", nil, 0)
	portraitBackground:SetAllPoints(portrait)
	portraitBackground:AddMaskTexture(mask)
	portraitBackground:SetColorTexture(0.06, 0.05, 0.04, 1)

	portraitIcon = container:CreateTexture(nil, "ARTWORK", nil, 1)
	portraitIcon:SetAllPoints(portrait)
	portraitIcon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
	portraitIcon:AddMaskTexture(mask)

	-- Soft inner edge vignette embeds the icon smoothly inside the portrait ring.
	portraitShade = container:CreateTexture(nil, "ARTWORK", nil, 2)
	portraitShade:SetAllPoints(portrait)
	portraitShade:SetTexture(PORTRAIT_SHADE)
	portraitShade:AddMaskTexture(mask)

	portraitShine = container:CreateTexture(nil, "ARTWORK", nil, 3)
	portraitShine:SetAllPoints(portrait)
	portraitShine:SetTexCoord(0.04, 0.96, 0.04, 0.96)
	portraitShine:AddMaskTexture(mask)
	portraitShine:SetBlendMode("ADD")
	portraitShine:SetAlpha(0.18)
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

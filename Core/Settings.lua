-- Builds the ForeverPlus page in the native settings panel: one sub menu per module.
local _, ns = ...
local L = ns.L

local mainCategory

local function VarType(value)
	local t = type(value)
	if t == "boolean" then
		return Settings.VarType.Boolean
	elseif t == "number" then
		return Settings.VarType.Number
	end
	return Settings.VarType.String
end

local function DropdownOptions(values)
	return function()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(type(values) == "function" and values() or values) do
			container:Add(entry[1], entry[2], entry[3])
		end
		return container:GetData()
	end
end

-- Like CreateSettingsButtonInitializer, but with ForeverPlus' own frame pool.
-- The button starts where checkboxes, sliders and dropdowns start, so all
-- controls line up and the label keeps the same width.
local function ButtonInitializer(name, buttonText, onClick, tooltip)
	local initializer = Settings.CreateElementInitializer("ForeverPlusSettingsButtonTemplate", {
		name = name,
		buttonText = buttonText,
		buttonClick = onClick,
		tooltip = tooltip,
	})
	initializer:AddSearchTags(name)
	local initFrame = initializer.InitFrame
	function initializer:InitFrame(frame)
		initFrame(self, frame)
		frame.Button:ClearAllPoints()
		frame.Button:SetPoint("LEFT", frame, "CENTER", -80, 0)
	end
	return initializer
end

local function MainCheckbox(variable, key, default, name, desc, onChange)
	if ns.db[key] == nil then
		ns.db[key] = default
	end
	local setting = Settings.RegisterAddOnSetting(mainCategory, variable, key, ns.db, Settings.VarType.Boolean, name, default)
	if onChange then
		setting:SetValueChangedCallback(function(_, value)
			onChange(value)
		end)
	end
	Settings.CreateCheckbox(mainCategory, setting, desc)
end

local function AddOption(module, category, layout, opt, initializers)
	if opt.type == "header" then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(opt.name, opt.desc))
		return
	elseif opt.type == "button" then
		local init = ButtonInitializer(opt.name, opt.text or opt.name, opt.func, opt.desc)
		layout:AddInitializer(init)
		return
	end

	local tbl = opt.db or module.db
	local default = opt.default
	if default == nil then
		default = module.defaults and module.defaults[opt.key]
	end
	if tbl[opt.key] == nil then
		tbl[opt.key] = default
	end

	local variable = ("ForeverPlus_%s_%s"):format(module.name, opt.variable or opt.key)
	local setting = Settings.RegisterAddOnSetting(category, variable, opt.key, tbl, VarType(default), opt.name, default)
	setting:SetValueChangedCallback(function(_, value)
		if module.OnOptionChanged then
			module:OnOptionChanged(opt.key, value, opt)
		end
	end)

	local init
	if opt.type == "toggle" then
		init = Settings.CreateCheckbox(category, setting, opt.desc)
	elseif opt.type == "slider" then
		local options = Settings.CreateSliderOptions(opt.min, opt.max, opt.step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, opt.format or function(v)
			return ("%d"):format(v)
		end)
		init = Settings.CreateSlider(category, setting, options, opt.desc)
	elseif opt.type == "dropdown" then
		init = Settings.CreateDropdown(category, setting, DropdownOptions(opt.values), opt.desc)
	end

	if init and opt.parent then
		local parentInit = initializers[opt.parent]
		if parentInit then
			init:SetParentInitializer(parentInit, function()
				return tbl[opt.parent] and true or false
			end)
		end
	end
	initializers[opt.key] = init
end

-- Settings pages: which module options appear where. Entries list a module,
-- optionally only some of its option keys and a section header. Modules not
-- listed get a page of their own.
local function Keys(...)
	local set = {}
	for i = 1, select("#", ...) do
		set[select(i, ...)] = true
	end
	return set
end

local MOUSEOVER_KEYS = Keys("mouseover", "mouseoverMicro", "mouseoverTracker", "mouseoverBags", "mouseoverMainBar",
	"mouseoverBar2", "mouseoverBar3", "mouseoverBar4", "mouseoverBar5", "mouseoverBar6", "mouseoverBar7", "mouseoverBar8",
	"mouseoverStance", "mouseoverPet")

local PAGES = {
	{ title = L.CHAT_TITLE, { "Chat" }, { "Loot", header = L.LOOT_TITLE } },
	{ title = L.TOOLTIP_TITLE, { "Tooltip" }, { "QuestieInfo", header = L.QDB_TITLE } },
	{ title = L.ITEMS_TITLE,
		{ "Items" },
		{ "Auction", header = L.AUCTION_TITLE },
		{ "Helpers", header = L.HELPERS_TITLE },
		{ "QoL", keys = Keys("bagSlots") },
	},
	{ title = L.QUESTS_TITLE, { "Quests" } },
	{ title = L.GROUPFINDER_TITLE, { "GroupFinder" } },
	{ title = L.PAGE_BARS,
		{ "QoL", header = L.QOL_MOUSEOVER_HEADER, keys = MOUSEOVER_KEYS },
		{ "QoL", header = L.QOL_ACTIONBAR_HEADER, keys = Keys("actionText", "hideHotkeys", "hideMacroNames") },
		{ "QoL", header = L.QOL_RANK_UP_HEADER, keys = Keys("rankUp") },
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("actionColors", "colorRange", "colorMana", "colorUnusable") },
		{ "Visuals", header = L.VISUALS_SQUID_HEADER, keys = Keys("squid") },
	},
	{ title = L.PAGE_COMBAT,
		{ "QoL", header = L.QOL_NAMEPLATES_HEADER, keys = Keys("nameplatesCombat") },
		{ "QoL", header = L.QOL_ERRORS_HEADER, keys = Keys("hideErrors") },
	},
	{ title = L.BUFFS_TITLE, { "Buffs" } },
	{ title = L.TALENTS_TITLE, { "Talents" } },
	{ title = L.PAGE_INFO,
		{ "QoL", header = L.QOL_MINIMAP_HEADER, keys = Keys("hideMinimapButtons") },
		{ "Minimap" },
		{ "Info", header = L.INFO_TITLE },
		{ "Flight", header = L.FLIGHT_TITLE },
		{ "Errors", header = L.ERRORS_TITLE },
	},
	{ title = L.XP_TITLE, { "XPBar" } },
	{ title = L.VISUALS_TITLE,
		{ "Visuals", header = L.VISUALS_ICON_FRAME_HEADER, headerDesc = L.VISUALS_ICON_FRAME_HEADER_DESC, keys = Keys("iconFrameStyle") },
		{ "Visuals", header = L.VISUALS_PORTRAIT_HEADER, keys = Keys("playerDragon", "dragonScale") },
		{ "Visuals", header = L.VISUALS_BARS_HEADER, keys = Keys("unitBars") },
	},
	{ title = L.FONTS_TITLE, { "Fonts" } },
	{ title = L.RADAR_TITLE, { "RecipeRadar" } },
}

local function ModuleOptions(module)
	return type(module.options) == "function" and module:options() or module.options or {}
end

-- Adds one page entry; returns false if the module does not exist.
local function AddEntry(category, layout, entry, pageTitle, initializers)
	local module = ns:GetModule(entry[1])
	if not module or not module.options then
		return false
	end
	if entry.header then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(entry.header, entry.headerDesc))
	end
	initializers[module] = initializers[module] or {}
	for _, opt in ipairs(ModuleOptions(module)) do
		local include
		if entry.keys then
			include = opt.key and entry.keys[opt.key]
		else
			-- A header repeating the page or section title is left out.
			include = not (opt.type == "header" and (opt.name == pageTitle or opt.name == entry.header))
		end
		if include then
			AddOption(module, category, layout, opt, initializers[module])
		end
	end
	module.settingsCategory = module.settingsCategory or category
	return true
end

function ns:BuildSettings()
	mainCategory = Settings.RegisterVerticalLayoutCategory("ForeverPlus")
	local mainLayout = SettingsPanel:GetLayout(mainCategory)
	mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(("ForeverPlus %s"):format(ns.version), L.ABOUT_TEXT))
	MainCheckbox("ForeverPlus_quiet", "quiet", false, L.QUIET, L.QUIET_DESC)
	mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.POSITIONS, L.POSITIONS_DESC))
	local mover = ns:GetModule("Mover")
	local moverInit = {}
	AddOption(mover, mainCategory, mainLayout, mover.options[1], moverInit)
	MainCheckbox("ForeverPlus_lockAll", "lockAll", false, L.LOCK_ALL, L.LOCK_ALL_DESC, function(value)
		ns:SetAllLocked(value)
	end)
	MainCheckbox("ForeverPlus_lockMessage", "lockMessage", true, L.DISPLAY_LOCK_MESSAGE, L.MESSAGE_DESC)
	mainLayout:AddInitializer(ButtonInitializer(L.MOVER_RESET, L.RESET, function()
		ns:ResetFramePositions()
	end, L.MOVER_RESET_DESC))
	AddOption(mover, mainCategory, mainLayout, mover.options[2], moverInit)
	mainLayout:AddInitializer(ButtonInitializer(L.RELOAD_UI, L.RELOAD, ReloadUI))
	mover.settingsCategory = mainCategory

	local listed = { Mover = true }
	for _, page in ipairs(PAGES) do
		local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, page.title)
		local layout = SettingsPanel:GetLayout(category)
		local initializers = {}
		for _, entry in ipairs(page) do
			if AddEntry(category, layout, entry, page.title, initializers) then
				listed[entry[1]] = true
			end
		end
	end

	-- Safety net: modules that are not part of the layout above.
	for _, module in ipairs(self.modules) do
		if module.options and not listed[module.name] then
			local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, module.title or module.name)
			AddEntry(category, SettingsPanel:GetLayout(category), { module.name }, module.title, {})
		end
	end

	Settings.RegisterAddOnCategory(mainCategory)
end

function ns:OpenSettings(module)
	if not mainCategory then
		return
	end
	local category = module and module.settingsCategory or mainCategory
	Settings.OpenToCategory(category:GetID())
end

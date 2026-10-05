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
local function ButtonInitializer(name, buttonText, onClick, tooltip)
	local initializer = Settings.CreateElementInitializer("ForeverPlusSettingsButtonTemplate", {
		name = name,
		buttonText = buttonText,
		buttonClick = onClick,
		tooltip = tooltip,
	})
	initializer:AddSearchTags(name)
	return initializer
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

function ns:BuildSettings()
	mainCategory = Settings.RegisterVerticalLayoutCategory("ForeverPlus")
	local mainLayout = SettingsPanel:GetLayout(mainCategory)
	mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(("ForeverPlus %s"):format(ns.version), L.ABOUT_TEXT))
	mainLayout:AddInitializer(ButtonInitializer(L.MOVER_RESET, L.RESET, function()
		ns:ResetFramePositions()
	end, L.MOVER_RESET_DESC))
	mainLayout:AddInitializer(ButtonInitializer(L.DISPLAY_LOCK_ALL, L.DISPLAY_LOCK, function()
		ns:LockAllDisplays()
	end, L.DISPLAY_LOCK_ALL_DESC))
	mainLayout:AddInitializer(ButtonInitializer(L.RELOAD_UI, L.RELOAD, ReloadUI))

	local modules = {}
	for _, module in ipairs(self.modules) do
		if module.options then
			modules[#modules + 1] = module
		end
	end
	table.sort(modules, function(a, b)
		return (a.order or 100) < (b.order or 100)
	end)

	for _, module in ipairs(modules) do
		local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, module.title or module.name)
		local layout = SettingsPanel:GetLayout(category)
		local options = type(module.options) == "function" and module:options() or module.options
		local initializers = {}
		for _, opt in ipairs(options) do
			AddOption(module, category, layout, opt, initializers)
		end
		module.settingsCategory = category
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

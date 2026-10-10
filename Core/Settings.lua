-- Builds the ForeverPlus page in the native settings panel: one sub menu per module.
local _, ns = ...
local L = ns.L

local mainCategory
local NEW_SEEN_LIMIT = 3

local function NewSeenCounts()
	ns.db.settingsNewSeen = ns.db.settingsNewSeen or {}
	return ns.db.settingsNewSeen
end

local function IsNew(id, enabled)
	return enabled and (NewSeenCounts()[id] or 0) < NEW_SEEN_LIMIT
end

local function CountAsSeen(id)
	local counts = NewSeenCounts()
	counts[id] = math.min(NEW_SEEN_LIMIT, (counts[id] or 0) + 1)
end

local function SetFrameLabel(frame, text)
	local label = frame.Text or frame.Label or frame.Name
	if label and label.SetText then
		label:SetText(text)
	end
end

local function ClearPageBadge(category, page)
	if category.SetName then
		category:SetName(page.title)
	elseif category.name then
		category.name = page.title
	end

	local list = SettingsPanel and SettingsPanel.CategoryList
	local scrollBox = list and (list.ScrollBox or list.scrollBox)
	if not scrollBox or not scrollBox.ForEachFrame then
		return
	end
	local categoryID = category:GetID()
	scrollBox:ForEachFrame(function(button)
		local data = button.GetElementData and button:GetElementData()
		local id = data and (data.categoryID or data.id)
		if data and data.category and data.category.GetID then
			id = data.category:GetID()
		end
		if id == categoryID then
			SetFrameLabel(button, page.title)
		end
	end)
end

local function AddSearchTags(initializer, ...)
	if not initializer or not initializer.AddSearchTags then
		return
	end
	local tags = {}
	for index = 1, select("#", ...) do
		local tag = select(index, ...)
		if type(tag) == "string" and tag ~= "" then
			tags[#tags + 1] = tag
		end
	end
	if #tags > 0 then
		initializer:AddSearchTags(unpack(tags))
	end
end

-- Count a feature each time its settings row is displayed. Settings rows are
-- hidden and shown again when switching pages, so revisiting the page counts
-- as another view. The count is account-wide and survives reloads.
local function TrackNew(initializer, id, text, enabled)
	if not enabled then
		return initializer
	end
	local initFrame = initializer.InitFrame
	function initializer:InitFrame(frame)
		initFrame(self, frame)
		if not frame.foreverPlusNewTracked then
			frame.foreverPlusNewTracked = true
			frame:HookScript("OnShow", function(row)
				if IsNew(id, true) then
					CountAsSeen(id)
					if not IsNew(id, true) then
						SetFrameLabel(row, text)
					end
				end
			end)
		end
	end
	return initializer
end

local function OptionName(opt)
	if IsNew(opt._newID, opt.new) then
		return ("%s  |cff00ff00%s|r"):format(opt.name, L.SETTINGS_NEW or _G.NEW or "NEW")
	end
	return opt.name
end

local function PageName(page)
	if IsNew(page._newID, page.new) then
		return ("%s  |cff00ff00%s|r"):format(page.title, L.SETTINGS_NEW or _G.NEW or "NEW")
	end
	return page.title
end

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
	AddSearchTags(initializer, name, buttonText, tooltip, "ForeverPlus")
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
	local initializer = Settings.CreateCheckbox(mainCategory, setting, desc)
	AddSearchTags(initializer, name, desc, key, "ForeverPlus")
end

local function AddOption(module, category, layout, opt, initializers)
	if opt.type == "header" then
		local name = opt.name
		if IsNew(opt._newID, opt.new) then
			name = name .. "  |cff00ff00" .. (L.SETTINGS_NEW or _G.NEW or "NEW") .. "|r"
		end
		local header = CreateSettingsListSectionHeaderInitializer(name, opt.desc)
		AddSearchTags(header, opt.name, opt.desc, "ForeverPlus")
		if opt.new then
			header = TrackNew(header, opt._newID, opt.name, true)
		end
		layout:AddInitializer(header)
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
	local name = OptionName(opt)
	local setting = Settings.RegisterAddOnSetting(category, variable, opt.key, tbl, VarType(default), name, default)
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
	if init then
		AddSearchTags(init, opt.name, opt.desc, opt.key, module.title, opt._pageTitle, "ForeverPlus")
		if opt.new then
			init = TrackNew(init, opt._newID, opt.name, true)
		end
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

local MOUSEOVER_BAR_KEYS = Keys("mouseover", "mouseoverCombat", "mouseoverMicro", "mouseoverTracker", "mouseoverBags", "mouseoverMainBar",
	"mouseoverBar2", "mouseoverBar3", "mouseoverBar4", "mouseoverBar5", "mouseoverBar6", "mouseoverBar7", "mouseoverBar8",
	"mouseoverStance", "mouseoverPet")
local MOUSEOVER_FRAME_KEYS = Keys("mouseoverXP", "mouseoverRep", "mouseoverPlayer", "mouseoverTarget", "mouseoverMinimap")

local PAGES = {
	{ title = L.CHAT_TITLE, { "Chat", exclude = Keys("tabFade") }, { "Loot", header = L.LOOT_TITLE } },
	{ title = L.TOOLTIP_TITLE, { "Tooltip" }, { "LootSources", header = L.LOOTSRC_TITLE }, { "QuestieInfo", header = L.QDB_TITLE } },
	{ title = L.ITEMS_TITLE,
		{ "Items" },
		{ "Auction", header = L.AUCTION_TITLE },
		{ "Restock", header = L.RESTOCK_TITLE },
		{ "Services", header = L.SERVICES_TITLE },
		{ "Helpers", header = L.HELPERS_TITLE },
		{ "QoL", keys = Keys("bagSlots") },
	},
	{ title = L.QUESTS_TITLE, { "Quests" } },
	{ title = L.GROUPFINDER_TITLE, { "GroupFinder" } },
	{ title = L.PAGE_MOUSEOVER,
		{ "QoL", header = L.QOL_MOUSEOVER_HEADER, keys = MOUSEOVER_BAR_KEYS },
		{ "QoL", header = L.QOL_MOUSEOVER_FRAMES_HEADER, keys = MOUSEOVER_FRAME_KEYS },
		{ "XPBar", header = L.XP_TITLE, keys = Keys("textMode") },
		{ "Chat", header = L.CHAT_TITLE, keys = Keys("tabFade") },
	},
	{ title = L.PAGE_BARS,
		{ "QoL", header = L.QOL_ACTIONBAR_HEADER, keys = Keys("actionText", "hideHotkeys", "hideMacroNames") },
		{ "QoL", header = L.QOL_RANK_UP_HEADER, keys = Keys("rankUp") },
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("actionColors", "colorRange", "colorMana", "colorUnusable", "colorActiveBuff", "castsLeft", "buffExceptions") },
		{ "Visuals", header = L.VISUALS_SQUID_HEADER, keys = Keys("squid") },
	},
	{ title = L.PAGE_COMBAT,
		{ "QoL", header = L.QOL_NAMEPLATES_HEADER, keys = Keys("nameplatesCombat", "nameplatesFade", "nameplatesFadeAmount") },
		{ "QoL", header = L.QOL_ERRORS_HEADER, keys = Keys("hideErrors") },
		{ "MeterReset", header = L.METER_TITLE },
	},
	{ title = L.BUFFS_TITLE, { "Buffs" } },
	{ title = L.TALENTS_TITLE, { "Talents" } },
	{ title = L.PAGE_INFO,
		{ "QoL", header = L.QOL_MINIMAP_HEADER, keys = Keys("hideMinimapButtons") },
		{ "Minimap" },
		{ "WorldMap", header = L.WORLDMAP_TITLE },
		{ "Info", header = L.INFO_TITLE },
		{ "DataCapture", header = L.DATA_TITLE },
		{ "Transports", header = L.TRANSPORTS_TITLE },
		{ "Library", header = L.LIBRARY_TITLE },
		{ "Innkeepers", header = L.INNS_TITLE },
		{ "Flight", header = L.FLIGHT_TITLE },
		{ "Errors", header = L.ERRORS_TITLE },
	},
	{ title = L.XP_TITLE, { "XPBar", exclude = Keys("textMode") } },
	{ title = L.VISUALS_TITLE, new = true,
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("auraActionFrame") },
		{ "Visuals", header = L.VISUALS_PORTRAIT_HEADER, keys = Keys("playerDragon", "dragonScale") },
		{ "Visuals", header = L.VISUALS_BARS_HEADER, keys = Keys("unitBars") },
		{ "Companion", header = L.COMPANION_TITLE },
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
	initializers[module] = initializers[module] or {}
	local hasNew = false
	for _, opt in ipairs(ModuleOptions(module)) do
		local included = entry.keys and opt.key and entry.keys[opt.key]
		if not entry.keys and not (entry.exclude and opt.key and entry.exclude[opt.key]) then
			included = true
		end
		if included and opt.new then
			hasNew = true
			opt._newID = opt._newID or ("option:" .. module.name .. ":" .. tostring(opt.key or opt.name))
		end
	end
	if entry.header then
		local sectionName = entry.header
		local sectionID = "section:" .. tostring(entry._pageID) .. ":" .. module.name .. ":" .. tostring(entry.header)
		if IsNew(sectionID, hasNew) then
			sectionName = sectionName .. "  |cff00ff00" .. (L.SETTINGS_NEW or _G.NEW or "NEW") .. "|r"
		end
		local header = CreateSettingsListSectionHeaderInitializer(sectionName, entry.headerDesc)
		AddSearchTags(header, entry.header, entry.headerDesc, pageTitle, "ForeverPlus")
		if hasNew then
			header = TrackNew(header, sectionID, entry.header, true)
		end
		layout:AddInitializer(header)
	elseif hasNew then
		local sectionName = module.title or module.name
		local sectionID = "section:" .. tostring(entry._pageID) .. ":" .. module.name
		if IsNew(sectionID, true) then
			sectionName = sectionName .. "  |cff00ff00" .. (L.SETTINGS_NEW or _G.NEW or "NEW") .. "|r"
		end
		local header = CreateSettingsListSectionHeaderInitializer(sectionName)
		AddSearchTags(header, module.title, module.name, pageTitle, "ForeverPlus")
		header = TrackNew(header, sectionID, module.title or module.name, true)
		layout:AddInitializer(header)
	end
	for _, opt in ipairs(ModuleOptions(module)) do
		local include
		if entry.keys then
			include = opt.key and entry.keys[opt.key]
		elseif entry.exclude and opt.key and entry.exclude[opt.key] then
			include = false -- shown on another page
		else
			-- A header repeating the page or section title is left out.
			include = not (opt.type == "header" and (opt.name == pageTitle or opt.name == entry.header))
		end
		if include then
			opt._pageTitle = pageTitle
			if opt.new then
				opt._newID = opt._newID or ("option:" .. module.name .. ":" .. tostring(opt.key or opt.name))
			end
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
	MainCheckbox("ForeverPlus_lockSound", "lockSound", true, L.LOCK_SOUND, L.LOCK_SOUND_DESC)
	mainLayout:AddInitializer(ButtonInitializer(L.MOVER_RESET, L.RESET, function()
		ns:ResetFramePositions()
	end, L.MOVER_RESET_DESC))
	AddOption(mover, mainCategory, mainLayout, mover.options[2], moverInit)
	mainLayout:AddInitializer(ButtonInitializer(L.RELOAD_UI, L.RELOAD, ReloadUI))
	mover.settingsCategory = mainCategory

	local listed = { Mover = true }
	for pageIndex, page in ipairs(PAGES) do
		page._newID = "page:" .. pageIndex
		local hasNew = page.new == true
		for _, entry in ipairs(page) do
			local module = ns:GetModule(entry[1])
			if module and module.options then
				for _, opt in ipairs(ModuleOptions(module)) do
					local included = entry.keys and opt.key and entry.keys[opt.key]
					if not entry.keys and not (entry.exclude and opt.key and entry.exclude[opt.key]) then
						included = true
					end
					if included and opt.new then
						hasNew = true
						opt._newID = opt._newID or ("option:" .. module.name .. ":" .. tostring(opt.key or opt.name))
					end
				end
			end
		end
		page.new = hasNew
		local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, PageName(page))
		local layout = SettingsPanel:GetLayout(category)
		local initializers = {}
		for _, entry in ipairs(page) do
			entry._pageID = page._newID
			if AddEntry(category, layout, entry, page.title, initializers) then
				listed[entry[1]] = true
			end
		end
		if hasNew then
			local pageSeen = false
			local pageRef, categoryRef = page, category
			for _, entry in ipairs(page) do
				local module = ns:GetModule(entry[1])
				for _, opt in ipairs(module and ModuleOptions(module) or {}) do
					if opt.new and not pageSeen then
						local init = initializers[module] and initializers[module][opt.key]
						if init then
							local pageID = pageRef._newID
							local wrapped = init.InitFrame
							init.InitFrame = function(initializer, frame)
								wrapped(initializer, frame)
								if not frame.foreverPlusPageTracked then
									frame.foreverPlusPageTracked = true
									frame:HookScript("OnShow", function()
										if IsNew(pageID, true) then
											CountAsSeen(pageID)
											if not IsNew(pageID, true) then
												ClearPageBadge(categoryRef, pageRef)
											end
										end
									end)
								end
							end
							pageSeen = true
						end
					end
				end
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

-- Builds the ForeverPlus page in the native settings panel: one sub menu per module.
local _, ns = ...
local L = ns.L

local mainCategory
local RefreshBadges
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
-- The glowing "NEW" label behind the name of a settings row (checkbox, slider, section title) while it is new.
local function RowLabel(frame)
	return frame.Text or frame.Label or frame.Title or frame.Name
end

local function ShowRowBadge(frame, on)
	local badge = frame.fpNewBadge
	if on then
		if not badge then
			badge = ns.CreateNewBadge(frame, L.SETTINGS_NEW or _G.NEW or "NEW")
			frame.fpNewBadge = badge
			-- Rows are reused for other settings: the label goes away with the row.
			frame:HookScript("OnHide", function(row)
				if row.fpNewBadge then
					row.fpNewBadge:Hide()
				end
			end)
		end
		local label = RowLabel(frame)
		badge:ClearAllPoints()
		if label and label.GetStringWidth then
			badge:SetPoint("LEFT", label, "LEFT", ns.Number(label:GetStringWidth(), 0) + 8, 0)
		else
			badge:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
		end
		badge:Show()
	elseif badge then
		badge:Hide()
	end
end

-- hover: an option row counts as seen when the mouse has been over it three times (it is meant to be tried);
-- section titles count each time they are shown.
local function TrackNew(initializer, id, hover, enabled)
	if not enabled then
		return initializer
	end
	-- The marks sit on the initializer (the row asks it, so a row reused for other settings counts nothing wrong).
	initializer.fpNewID, initializer.fpNewHover = id, hover and true or false
	local initFrame = initializer.InitFrame
	local function Seen(row, byMouse)
		local data = row.GetElementData and row:GetElementData()
		local rowID = type(data) == "table" and data.fpNewID
		if not rowID or data.fpNewHover ~= byMouse or not IsNew(rowID, true) then
			return
		end
		-- Row and control report the same pass of the mouse: once a second at most.
		if byMouse then
			if GetTime() - (row.fpNewLast or 0) < 1 then
				return
			end
			row.fpNewLast = GetTime()
		end
		CountAsSeen(rowID)
		if not IsNew(rowID, true) then
			ShowRowBadge(row, false)
			if RefreshBadges then
				RefreshBadges()
			end
		end
	end
	-- Mouse over the row or one of the controls on it (the control may cover the row).
	local function HookHover(row, region)
		if not region.fpNewHooked and region.HookScript then
			region.fpNewHooked = true
			region:HookScript("OnEnter", function()
				Seen(row, true)
			end)
		end
	end
	function initializer:InitFrame(frame)
		initFrame(self, frame)
		ShowRowBadge(frame, IsNew(id, true))
		if not frame.foreverPlusNewTracked then
			frame.foreverPlusNewTracked = true
			frame:HookScript("OnShow", function(row)
				Seen(row, false)
			end)
		end
		if hover then
			HookHover(frame, frame)
			for _, child in ipairs({ frame:GetChildren() }) do
				HookHover(frame, child)
			end
		end
	end
	return initializer
end

-- New options carry the glowing label (see ShowRowBadge) instead of a coloured word in the name.
local function OptionName(opt)
	return opt.name
end

-- The page entry carries no text mark: a glowing "NEW" label is put beside it while something on the page is new.
local function PageName(page)
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
		local header = CreateSettingsListSectionHeaderInitializer(opt.name, opt.desc)
		AddSearchTags(header, opt.name, opt.desc, "ForeverPlus")
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
			init = TrackNew(init, opt._newID, true, true)
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
	{ group = 1, title = L.CHAT_TITLE, { "Chat", exclude = Keys("tabFade") }, { "Loot", header = L.LOOT_TITLE }, { "Trivial", header = L.TRIVIAL_TITLE }, { "ChatIndent", header = L.CHATINDENT_TITLE }, { "ChatMinimize", header = L.CHATMIN_TITLE } },
	{ group = 1, title = L.TOOLTIP_TITLE, { "Tooltip" }, { "LootSources", header = L.LOOTSRC_TITLE }, { "Observations", header = L.OBS_TITLE }, { "QuestieInfo", header = L.QDB_TITLE } },
	{ group = 3, title = L.ITEMS_TITLE,
		{ "Items", header = L.ITEMS_MERCHANT, keys = Keys("autoSell", "sellMessage", "sellButton", "autoRepair", "repairGuild",
			"repairMessage", "junkButton", "markMessage", "junkPerCharacter", "junkList") },
		{ "Items", header = L.ITEMS_BAGS, keys = Keys("autoSort", "sortSkip", "bagMenu") },
		{ "QoL", keys = Keys("bagSlots") },
		{ "Items", header = L.ITEMS_DISPLAY, keys = Keys("questReward", "upgradeArrow", "upgradeScore", "upgradePopup") },
		{ "Durability" },
		{ "Items", header = L.ITEMS_LOOT, keys = Keys("fastLoot", "destroyPrompt", "autoBind", "autoEquipBind", "deleteText", "rollCounts") },
		{ "Auction", header = L.AUCTION_TITLE },
		{ "Restock", header = L.RESTOCK_TITLE },
		{ "Services", header = L.SERVICES_TITLE },
		{ "Helpers", header = L.HELPERS_TITLE },
	},
	{ group = 2, title = L.QUESTS_TITLE, { "Quests" }, { "SpeechBubbles", header = L.SPEECH_TITLE },
		{ "Dialog", header = L.DIALOG_TITLE } },
	{ group = 2, title = L.GROUPFINDER_TITLE, { "GroupFinder" } },
	{ group = 1, title = L.PAGE_MOUSEOVER,
		{ "QoL", header = L.QOL_MOUSEOVER_HEADER, keys = MOUSEOVER_BAR_KEYS },
		{ "QoL", header = L.QOL_MOUSEOVER_FRAMES_HEADER, keys = MOUSEOVER_FRAME_KEYS },
		{ "XPBar", header = L.XP_TITLE, keys = Keys("textMode") },
		{ "Chat", header = L.CHAT_TITLE, keys = Keys("tabFade") },
	},
	{ group = 1, title = L.PAGE_BARS,
		{ "QoL", header = L.QOL_ACTIONBAR_HEADER, keys = Keys("actionText", "hideHotkeys", "hideMacroNames") },
		{ "QoL", header = L.QOL_RANK_UP_HEADER, keys = Keys("rankUp") },
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("actionColors", "colorRange", "colorMana", "colorUnusable", "colorActiveBuff", "castsLeft", "buffExceptions") },
		{ "Visuals", header = L.VISUALS_SQUID_HEADER, keys = Keys("squid") },
	},
	{ group = 3, title = L.PAGE_COMBAT,
		{ "QoL", header = L.QOL_NAMEPLATES_HEADER, keys = Keys("nameplatesCombat", "nameplatesFade", "nameplatesTargetFull", "nameplatesFadeCombat", "nameplatesFadeAmount") },
		{ "QoL", header = L.QOL_ERRORS_HEADER, keys = Keys("hideErrors") },
		{ "MeterReset", header = L.METER_TITLE },
	},
	{ group = 3, title = L.BUFFS_TITLE, { "Buffs" } },
	{ group = 3, title = L.TALENTS_TITLE, { "Talents" } },
	{ group = 2, title = L.PAGE_INFO,
		-- By sense, then alphabetical: minimap, world map, places and routes, data and displays, errors.
		{ "QoL", header = L.QOL_MINIMAP_HEADER, keys = Keys("hideMinimapButtons") },
		{ "Minimap", exclude = Keys("worldMapCoords") },
		{ "Teleports", header = L.TELEPORTS_TITLE },
		{ "WorldMap", header = L.WORLDMAP_TITLE },
		{ "Minimap", keys = Keys("worldMapCoords") },
		{ "Library", header = L.LIBRARY_TITLE },
		{ "InstanceStats", header = L.INSTSTATS_TITLE },
		{ "Flight", header = L.FLIGHT_TITLE },
		{ "Innkeepers", header = L.INNS_TITLE },
		{ "Transports", header = L.TRANSPORTS_TITLE },
		{ "DataCapture", header = L.DATA_TITLE },
		{ "Info", header = L.INFO_TITLE },
		{ "Errors", header = L.ERRORS_TITLE },
	},
	{ group = 3, title = L.XP_TITLE, { "XPBar", exclude = Keys("textMode") }, { "RepFlash", header = L.REPFLASH_TITLE } },
	{ group = 1, title = L.VISUALS_TITLE, new = true,
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("auraActionFrame") },
		{ "Visuals", header = L.VISUALS_PORTRAIT_HEADER, keys = Keys("playerDragon", "dragonScale") },
		{ "Visuals", header = L.VISUALS_BARS_HEADER, keys = Keys("unitBars") },
		{ "Companion", header = L.COMPANION_TITLE },
	},
	{ group = 1, title = L.EDITLAYOUT_TITLE, new = true, { "EditLayouts" } },
	{ group = 1, title = L.FONTS_TITLE, { "Fonts" } },
	{ group = 2, title = L.RADAR_TITLE, { "RecipeRadar" } },
}

-- The pages by sense (what is shown, the world, the character), each group alphabetical.
table.sort(PAGES, function(a, b)
	if a.group ~= b.group then
		return a.group < b.group
	end
	return a.title:lower() < b.title:lower()
end)

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
	for _, opt in ipairs(ModuleOptions(module)) do
		local included = entry.keys and opt.key and entry.keys[opt.key]
		if not entry.keys and not (entry.exclude and opt.key and entry.exclude[opt.key]) then
			included = true
		end
		if included and opt.new then
			opt._newID = opt._newID or ("option:" .. module.name .. ":" .. tostring(opt.key or opt.name))
		end
	end
	if entry.header then
		local header = CreateSettingsListSectionHeaderInitializer(entry.header, entry.headerDesc)
		AddSearchTags(header, entry.header, entry.headerDesc, pageTitle, "ForeverPlus")
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

---------------------------------------------------------------------------
-- A glowing "NEW" label (yellow, with turning rays) at the tab "Addons", the entry "ForeverPlus", the pages and the
-- button "Addons" of the game menu, while something on a page is new (like the game's own label on new settings).
---------------------------------------------------------------------------
local ownBadges = setmetatable({}, { __mode = "k" })

local function PageStillNew(page)
	for _, entry in ipairs(page) do
		local module = ns:GetModule(entry[1])
		for _, opt in ipairs(module and ModuleOptions(module) or {}) do
			if opt.new and opt._newID and IsNew(opt._newID, true) then
				local included = entry.keys and opt.key and entry.keys[opt.key]
				if not entry.keys and not (entry.exclude and opt.key and entry.exclude[opt.key]) then
					included = true
				end
				if included then
					return true
				end
			end
		end
	end
	return false
end

local function Mark(owner, on, place)
	if not owner or (owner.IsForbidden and owner:IsForbidden()) then
		return
	end
	local badge = ownBadges[owner]
	if on then
		if not badge then
			badge = ns.CreateNewBadge(owner, L.SETTINGS_NEW or _G.NEW or "NEW")
			ownBadges[owner] = badge
		end
		badge:ClearAllPoints()
		place(badge, owner)
		badge:Show()
	elseif badge then
		badge:Hide()
	end
end

local function LabelOf(button)
	local label = button.Label or button.Text or button.Name
	if label then
		return label
	end
	-- Else the first text of the entry.
	for _, region in ipairs({ button:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			return region
		end
	end
end

-- Beside the name of an entry in the list: behind it (the entry "ForeverPlus"), in front of it (the pages).
local function BehindLabel(badge, button)
	local label = LabelOf(button)
	if label and label.GetStringWidth then
		badge:SetPoint("LEFT", label, "LEFT", ns.Number(label:GetStringWidth(), 0) + 8, 0)
	else
		badge:SetPoint("RIGHT", button, "RIGHT", -8, 0)
	end
end

local function BeforeLabel(badge, button)
	local label = LabelOf(button)
	if label then
		badge:SetPoint("RIGHT", label, "LEFT", 6, 0)
	else
		badge:SetPoint("LEFT", button, "LEFT", 2, 0)
	end
end

-- The category an entry of the list stands for: the list is a tree, the entry's data is a node whose data holds the
-- category (or the category itself, or an ID).
local function CategoryIDOf(button)
	local element = button.GetElementData and button:GetElementData()
	if not element then
		return nil
	end
	local candidates = { element }
	if type(element.GetData) == "function" then
		candidates[#candidates + 1] = element:GetData()
	end
	if type(element.data) == "table" then
		candidates[#candidates + 1] = element.data
	end
	for _, data in ipairs(candidates) do
		if type(data) == "table" then
			local category = data.category or data
			if type(category.GetID) == "function" then
				return category:GetID()
			end
			if data.categoryID or data.id then
				return data.categoryID or data.id
			end
		end
	end
end

function RefreshBadges()
	if not mainCategory or not SettingsPanel then
		return
	end
	local newIDs, any = {}, false
	for _, page in ipairs(PAGES) do
		if page._category and PageStillNew(page) then
			newIDs[page._category:GetID()] = true
			any = true
		end
	end
	newIDs[mainCategory:GetID()] = any
	Mark(SettingsPanel.AddOnsTab, any, function(badge, tab)
		badge:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -6, -3)
	end)
	local list = SettingsPanel.CategoryList
	local scrollBox = list and (list.ScrollBox or list.scrollBox)
	if scrollBox and type(scrollBox.ForEachFrame) == "function" then
		scrollBox:ForEachFrame(function(button)
			local id = CategoryIDOf(button)
			Mark(button, id and newIDs[id] or false, id == mainCategory:GetID() and BehindLabel or BeforeLabel)
		end)
	end
	if GameMenuFrame and GameMenuFrame:IsShown() and GameMenuFrame.buttonPool and type(GameMenuFrame.buttonPool.EnumerateActive) == "function" then
		for button in GameMenuFrame.buttonPool:EnumerateActive() do
			-- On "Options": the settings of ForeverPlus are in there (Options > Addons).
			local isOptions = button == _G.GameMenuButtonOptions or (button.GetText and button:GetText() == OPTIONS)
			Mark(button, isOptions and any or false, function(badge, owner)
				badge:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -10, -1)
			end)
		end
	end
end

local function HookBadges()
	if type(SettingsPanel.HookScript) == "function" then
		-- While the panel is open the labels are looked after twice a second (entries are made anew when the list
		-- is opened, closed or scrolled; no event is relied on).
		local ticker
		SettingsPanel:HookScript("OnShow", function()
			C_Timer.After(0, RefreshBadges)
			if ticker then
				ticker:Cancel()
			end
			ticker = C_Timer.NewTicker(0.5, RefreshBadges)
		end)
		SettingsPanel:HookScript("OnHide", function()
			if ticker then
				ticker:Cancel()
				ticker = nil
			end
		end)
	end
	local list = SettingsPanel.CategoryList
	local scrollBox = list and (list.ScrollBox or list.scrollBox)
	if scrollBox and scrollBox.RegisterCallback then
		local event = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnDataRangeChanged or "OnDataRangeChanged"
		pcall(scrollBox.RegisterCallback, scrollBox, event, RefreshBadges, ns)
	end
	if GameMenuFrame and type(GameMenuFrame.HookScript) == "function" then
		GameMenuFrame:HookScript("OnShow", function()
			C_Timer.After(0, RefreshBadges)
		end)
	end
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
	MainCheckbox("ForeverPlus_fadeIn", "fadeIn", true, L.FADE_IN, L.FADE_IN_DESC)
	mainLayout:AddInitializer(ButtonInitializer(L.MOVER_RESET, L.RESET, function()
		ns:ResetFramePositions()
	end, L.MOVER_RESET_DESC))
	AddOption(mover, mainCategory, mainLayout, mover.options[2], moverInit)
	AddOption(mover, mainCategory, mainLayout, mover.options[3], moverInit)
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
		page._category = category
	end

	-- Safety net: modules that are not part of the layout above.
	for _, module in ipairs(self.modules) do
		if module.options and not listed[module.name] then
			local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, module.title or module.name)
			AddEntry(category, SettingsPanel:GetLayout(category), { module.name }, module.title, {})
		end
	end

	HookBadges()
	RefreshBadges()
	Settings.RegisterAddOnCategory(mainCategory)
end

function ns:OpenSettings(module)
	if not mainCategory then
		return
	end
	local category = module and module.settingsCategory or mainCategory
	Settings.OpenToCategory(category:GetID())
end

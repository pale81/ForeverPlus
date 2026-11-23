-- Builds the ForeverPlus page in the native settings panel: one sub menu per module.
local _, ns = ...
local L = ns.L

local mainCategory
local newOptionsByCategory = {}
local firstBuildByScope = {}
local RefreshBadges
local NEW_SEEN_LIMIT = 2

local function NewSeenCounts()
	ns.db.settingsNewSeen = ns.db.settingsNewSeen or {}
	return ns.db.settingsNewSeen
end

local function IsNew(id)
	return (NewSeenCounts()[id] or 0) < NEW_SEEN_LIMIT
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

-- The glowing "NEW" label beside the name of a settings row while it is new.
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
			frame:HookScript("OnHide", ns.Measured("Settings: hide NEW row", function(row)
				row.fpNewMouseID = nil
				row.fpNewBadge:Hide()
			end))
		end
		local label = RowLabel(frame)
		badge:ClearAllPoints()
		if label and label.GetStringWidth then
			badge:SetPoint("RIGHT", label, "LEFT", -8, 0)
		else
			badge:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
		end
		badge:Show()
	elseif badge then
		badge:Hide()
	end
end

local function HookNewHover(row, region)
	if not region.fpNewHooked then
		region.fpNewHooked = true
		region:HookScript("OnEnter", ns.Measured("Settings: see NEW row", function()
			local data = row.GetElementData and row:GetElementData()
			local id = data and data.fpNewID
			if not id or row.fpNewMouseID == id or not IsNew(id) then
				return
			end
			row.fpNewMouseID = id
			local counts = NewSeenCounts()
			counts[id] = (counts[id] or 0) + 1
			if not IsNew(id) then
				ShowRowBadge(row, false)
				RefreshBadges()
			end
		end))
		region:HookScript("OnLeave", ns.Measured("Settings: leave NEW row", function()
			-- Hover can pass between the label and the controls without leaving the row.
			if not row:IsMouseOver() then
				row.fpNewMouseID = nil
			end
		end))
	end
	for _, child in ipairs({ region:GetChildren() }) do
		if child ~= row.fpNewBadge then
			HookNewHover(row, child)
		end
	end
end

local function TrackNew(initializer, id)
	-- The row reads its current initializer because the settings list recycles rows.
	initializer.fpNewID = id
	-- A hook after the game's own InitFrame (not a replacement of it): our code then does not run inside the game's
	-- way through the list, whose later steps (search results with the Discord button, for one) refuse calls
	-- once addon code has run there (ADDON_ACTION_FORBIDDEN IsUserOAuthed).
	hooksecurefunc(initializer, "InitFrame", ns.Measured("Settings: show NEW row", function(_, frame)
		local new = IsNew(id)
		ShowRowBadge(frame, new)
		if new then
			HookNewHover(frame, frame)
		end
	end))
end

local function RegisterOptionBadge(initializer, category, id, markedNew, scope)
	if not initializer then
		return
	end
	scope = scope or "account"
	local history = ns.db.settingsOptionHistory
	local options = history[scope]
	if not options then
		options = {}
		history[scope] = options
		firstBuildByScope[scope] = true
	end
	if markedNew or options[id] == nil then
		options[id] = markedNew == true or not firstBuildByScope[scope]
	end
	if options[id] then
		TrackNew(initializer, id)
		local ids = newOptionsByCategory[category] or {}
		ids[#ids + 1] = id
		newOptionsByCategory[category] = ids
	end
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
		buttonClick = ns.Measured("Settings: " .. tostring(name), onClick),
		tooltip = tooltip,
	})
	AddSearchTags(initializer, name, buttonText, tooltip, "ForeverPlus")
	hooksecurefunc(initializer, "InitFrame", ns.Measured("Settings: InitFrame", function(_, frame)
		frame.Button:ClearAllPoints()
		frame.Button:SetPoint("LEFT", frame, "CENTER", -80, 0)
	end))
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
	RegisterOptionBadge(initializer, mainCategory, "option:Main:" .. key)
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

	local key = opt.variable or opt.key
	local variable = ("ForeverPlus_%s_%s"):format(module.name, key)
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
		RegisterOptionBadge(init, category, "option:" .. module.name .. ":" .. key, opt.new, opt.newScope)
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
	{ group = 1, title = L.CHAT_TITLE, { "Chat", exclude = Keys("tabFade") }, { "Loot", header = L.LOOT_TITLE }, { "Trivial", header = L.TRIVIAL_TITLE }, { "ChatIndent", header = L.CHATINDENT_TITLE }, { "ChatMinimize", header = L.CHATMIN_TITLE }, { "ChatEmotes", header = L.CHATEMOTES_TITLE } },
	{ group = 1, title = L.TOOLTIP_TITLE, { "Tooltip" }, { "LootSources", header = L.LOOTSRC_TITLE }, { "Observations", header = L.OBS_TITLE }, { "PlayerNotes", header = L.NOTES_TITLE }, { "QuestieInfo", header = L.QDB_TITLE } },
	{ group = 3, title = L.ITEMS_TITLE,
		{ "Items", header = L.ITEMS_MERCHANT, keys = Keys("autoSell", "sellMessage", "sellButton", "autoRepair", "repairGuild",
			"repairMessage", "junkButton", "markMessage", "junkPerCharacter", "junkList") },
		{ "Items", header = L.ITEMS_BAGS, keys = Keys("autoSort", "sortSkip", "bagMenu", "moneyPickup", "fullSound", "fullSoundChoice", "fullSoundTest") },
		{ "BankView" },
		{ "Items", header = L.ITEMS_DISPLAY, keys = Keys("questReward", "upgradeArrow", "rewardUpgrade", "scoreSpec", "upgradeScore",
			"upgradePopup", "upgradeCelebrate", "upgradeMarkOld", "upgradeStyle") },
		{ "StatRank", header = L.STATRANK_TITLE },
		{ "Upgrades", header = L.UPGRADES_TITLE },
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
		{ "QoL", header = L.QOL_ACTIONBAR_HEADER, keys = Keys("actionText", "hideHotkeys", "hideMacroNames", "autoPlace") },
		{ "QoL", header = L.QOL_RANK_UP_HEADER, keys = Keys("rankUp") },
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("actionColors", "colorRange", "colorMana", "colorUnusable",
			"colorActiveBuff", "castsLeft", "totemTimers", "paladinRecommendations", "paladinSealRecommendation", "combatBuffRecommendation", "buffExceptions") },
		{ "Visuals", header = L.VISUALS_SQUID_HEADER, keys = Keys("squid") },
		{ "MacroIcons", header = L.MACROICONS_TITLE },
	},
	{ group = 3, title = L.PAGE_COMBAT,
		{ "QoL", header = L.QOL_NAMEPLATES_HEADER, keys = Keys("nameplatesCombat", "nameplatesFade", "nameplatesTargetFull", "nameplatesFadeCombat", "nameplatesFadeAmount") },
		{ "QoL", header = L.QOL_ERRORS_HEADER, keys = Keys("hideErrors") },
		{ "CombatText", header = L.COMBATTEXT_TITLE },
		{ "MeterReset", header = L.METER_TITLE },
		{ "DPSSim", header = L.DPSSIM_TITLE },
	},
	{ group = 3, title = L.BUFFS_TITLE, { "Buffs" } },
	{ group = 3, title = L.TALENTS_TITLE, { "Talents" } },
	{ group = 3, title = L.RP_TITLE, { "Roleplay" }, { "Landing", header = L.LANDING_TITLE } },
	{ group = 2, title = L.PAGE_INFO,
		-- By sense, then alphabetical: minimap, world map, places and routes, data and displays, errors.
		{ "QoL", header = L.QOL_MINIMAP_HEADER, keys = Keys("hideMinimapButtons") },
		{ "Minimap", exclude = Keys("worldMapCoords") },
		{ "Teleports", header = L.TELEPORTS_TITLE },
		{ "WorldMap", header = L.WORLDMAP_TITLE },
		{ "Minimap", keys = Keys("worldMapCoords") },
		{ "Library", header = L.LIBRARY_TITLE },
		{ "InstanceStats", header = L.INSTSTATS_TITLE },
		{ "DungeonJournal", header = L.JOURNAL_TITLE },
		{ "Flight", header = L.FLIGHT_TITLE },
		{ "Waypoint", header = L.WAYPOINT_TITLE },
		{ "Scout", header = L.SCOUT_TITLE },
		{ "Innkeepers", header = L.INNS_TITLE },
		{ "Transports", header = L.TRANSPORTS_TITLE },
		{ "DataCapture", header = L.DATA_TITLE },
		{ "Moments", header = L.MOMENTS_TITLE },
		{ "SoloParty", header = L.SOLO_PARTY_TITLE },
		{ "Info", header = L.INFO_TITLE },
		{ "Errors", header = L.ERRORS_TITLE },
	},
	{ group = 3, title = L.XP_TITLE, { "XPBar", exclude = Keys("textMode") }, { "RepFlash", header = L.REPFLASH_TITLE } },
	{ group = 1, title = L.VISUALS_TITLE,
		{ "Visuals", header = L.VISUALS_ACTION_HEADER, keys = Keys("auraActionFrame", "bagActionFrame") },
		{ "Visuals", header = L.VISUALS_PORTRAIT_HEADER, keys = Keys("playerPortraitWheel", "playerDragon", "dragonScale") },
		{ "Visuals", header = L.VISUALS_BARS_HEADER, keys = Keys("unitBars") },
		{ "Companion", header = L.COMPANION_TITLE },
		{ "Wanderlust" },
	},
	{ group = 1, title = L.FONTS_TITLE, { "Fonts" } },
	{ group = 2, title = L.RADAR_TITLE, { "RecipeRadar" } },
}
ns.SettingsPages = PAGES -- read by the tests: every option must appear on a page

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
	for category, ids in pairs(newOptionsByCategory) do
		for _, id in ipairs(ids) do
			if IsNew(id) then
				newIDs[category:GetID()] = true
				any = true
				break
			end
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
			ns.After("Settings: RefreshBadges", 0, RefreshBadges)
			if ticker then
				ticker:Cancel()
			end
			ticker = ns.NewTicker("Settings: RefreshBadges", 0.5, RefreshBadges)
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
		pcall(scrollBox.RegisterCallback, scrollBox, event, ns.Measured("Settings: RefreshBadges", RefreshBadges), ns)
	end
	if GameMenuFrame and type(GameMenuFrame.HookScript) == "function" then
		GameMenuFrame:HookScript("OnShow", function()
			ns.After("Settings: RefreshBadges", 0, RefreshBadges)
		end)
	end
end

function ns:BuildSettings()
	ns.db.settingsOptionHistory = ns.db.settingsOptionHistory or {}
	firstBuildByScope = {}
	newOptionsByCategory = {}
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

	-- Profiles: a snapshot of game settings, key bindings, Edit Mode layouts and the settings of ForeverPlus.
	local profiles = ns:GetModule("Profiles")
	if profiles then
		mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.PROFILES_TITLE, L.PROFILES_DESC))
		mainLayout:AddInitializer(ButtonInitializer(L.PROFILES_SAVE_BUTTON, L.PROFILES_SAVE, function()
			profiles.ShowSave()
		end, L.PROFILES_DESC))
		mainLayout:AddInitializer(ButtonInitializer(L.PROFILES_LIST_BUTTON, L.PROFILES_LIST, function(button)
			profiles.ShowList(button)
		end, L.PROFILES_DESC))
		AddOption(profiles, mainCategory, mainLayout, profiles.options[1], moverInit)
	end
	-- Edit Mode layouts that come with the addon.
	local layouts = ns:GetModule("EditLayouts")
	if layouts and #layouts.options > 0 then
		mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.EDITLAYOUT_TITLE))
		for _, opt in ipairs(layouts.options) do
			AddOption(layouts, mainCategory, mainLayout, opt, moverInit)
		end
	end
	-- Restore NEW labels that have been dismissed.
	mainLayout:AddInitializer(ButtonInitializer(L.NEW_RESET, L.NEW_RESET_BUTTON, function()
		ns.db.settingsNewSeen = {}
		RefreshBadges()
		ns.PrintAlways(L.NEW_RESET_DONE)
	end, L.NEW_RESET_DESC))
	-- What the addon learned while playing, as one text.
	mainLayout:AddInitializer(ButtonInitializer(L.EXPORT_BUTTON, L.EXPORT, function()
		ns:GetModule("DataCapture").Export()
	end, L.EXPORT_BUTTON_DESC))
	mainLayout:AddInitializer(ButtonInitializer(L.RELOAD_UI, L.RELOAD, ReloadUI))
	mover.settingsCategory = mainCategory

	local listed = { Mover = true, Profiles = true, EditLayouts = true }
	for _, page in ipairs(PAGES) do
		local category = Settings.RegisterVerticalLayoutSubcategory(mainCategory, PageName(page))
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

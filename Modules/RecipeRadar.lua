-- Recipe radar: vendors selling recipes the player does not know yet, shown on
-- the world map and/or minimap; clicking sets a waypoint. Recipe items also get
-- their sources (vendors, quests, drops) in the tooltip.
--
-- Data comes from QuestieDB at runtime (current Forever data set with Forever
-- coordinates and localized names). Nothing is copied into ForeverPlus.
local _, ns = ...
local L = ns.L

local Radar = ns:NewModule("RecipeRadar", {
	title = L.RADAR_TITLE,
	order = 10,
	defaults = {
		enabled = true,
		worldMap = true,
		minimap = true,
		showLowSkill = true,
		tooltipSources = true,
		waypointMessage = true,
	},
})

local PIN_TEMPLATE = "ForeverPlusRecipePinTemplate"
local MINIMAP_UPDATE_INTERVAL = 0.05
local RECIPE_CLASS = 9           -- Enum.ItemClass.Recipe
local TOOLTIP_MAX_VENDORS = 3
local TOOLTIP_MAX_QUESTS = 2

-- Recipe item subclass -> profession skill line.
local RECIPE_SKILL = {
	[1] = 165, -- Leatherworking
	[2] = 197, -- Tailoring
	[3] = 202, -- Engineering
	[4] = 164, -- Blacksmithing
	[5] = 185, -- Cooking
	[6] = 171, -- Alchemy
	[7] = 129, -- First Aid
	[8] = 333, -- Enchanting
	[9] = 356, -- Fishing
	[10] = 755, -- Jewelcrafting
}

local DB                -- LibQuestieDB
local recipes = {}      -- itemID -> { skill =, vendors =, drops =, quests = }
local vendorsByMap = {} -- uiMapID -> { { npc =, team =, x =, y =, items = {} }, ... }
local areaToUiMap = {}
local indexReady = false
local skills = {}       -- skillLineID -> current rank
local statusCache = {}  -- itemID -> "known" | "ok" | "low"
local playerTeam
local waitingForItems = false

---------------------------------------------------------------------------
-- QuestieDB index (built once per session, spread over frames)
---------------------------------------------------------------------------
local function LoadAreaMap()
	local ok, zoneDB = pcall(DB.Support.Get, "ZoneDB")
	local private = ok and zoneDB and zoneDB.private
	if not private then
		return
	end
	for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
		local source = private[key]
		if type(source) == "string" then
			local chunk = loadstring(source)
			local success, map = pcall(chunk or error)
			source = success and map or nil
		end
		if type(source) == "table" then
			for areaID, uiMapID in pairs(source) do
				areaToUiMap[areaID] = uiMapID
			end
		end
	end
end

local function AddVendorSpawns(npc, items)
	local spawns = DB.Npc.spawns(npc)
	local faction = DB.Npc.friendlyToFaction(npc)
	if not spawns or not faction then
		return -- hostile to both factions or no known position
	end
	local team = faction == "AH" and "N" or faction
	for areaID, points in pairs(spawns) do
		local uiMapID = areaToUiMap[areaID]
		local point = points[1]
		if uiMapID and uiMapID > 0 and point and point[1] and point[1] >= 0 then
			local list = vendorsByMap[uiMapID]
			if not list then
				list = {}
				vendorsByMap[uiMapID] = list
			end
			list[#list + 1] = { npc = npc, team = team, x = point[1], y = point[2], items = items }
		end
	end
end

local function BuildIndex(onDone)
	LoadAreaMap()
	local ids = DB.Item.GetAllIds()
	local npcItems = {}
	ns.RunSliced("RecipeRadar: recipes", #ids, function(i)
		local id = ids[i]
		if DB.Item.class(id) == RECIPE_CLASS then
			local skill = RECIPE_SKILL[DB.Item.subClass(id)]
			if skill then
				local vendors = DB.Item.vendors(id)
				recipes[id] = {
					skill = skill,
					vendors = vendors,
					drops = DB.Item.npcDrops(id),
					quests = DB.Item.questRewards(id),
				}
				for _, npc in ipairs(vendors or {}) do
					npcItems[npc] = npcItems[npc] or {}
					tinsert(npcItems[npc], id)
				end
			end
		end
	end, function()
		local npcs = {}
		for npc in pairs(npcItems) do
			npcs[#npcs + 1] = npc
		end
		ns.RunSliced("RecipeRadar: vendors", #npcs, function(i)
			AddVendorSpawns(npcs[i], npcItems[npcs[i]])
		end, function()
			indexReady = true
			onDone()
		end)
	end)
end

---------------------------------------------------------------------------
-- Player state
---------------------------------------------------------------------------
local function UpdateSkills()
	wipe(skills)
	wipe(statusCache)
	for _, index in pairs({ GetProfessions() }) do
		if index then
			local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				skills[skillLine] = rank or 0
			end
		end
	end
end

local function IsRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

-- Reads "already known" and "skill too low" from the item's tooltip data.
local function ScanRecipe(itemID)
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		waitingForItems = true
		return nil
	end
	local status = "ok"
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	for _, line in ipairs(tooltip and tooltip.lines or {}) do
		if line.type == Enum.TooltipDataLineType.UsageRequirement then
			if line.requirementType == Enum.TooltipDataUsageRequirementType.NotAlreadyKnown then
				return "known"
			elseif line.requirementType == Enum.TooltipDataUsageRequirementType.Skill and IsRed(line.leftColor) then
				status = "low"
			end
		elseif line.leftText == ITEM_SPELL_KNOWN then
			return "known"
		end
	end
	return status
end

-- Returns "ok" (learnable now), "low" (skill too low) or nil (irrelevant / known).
local function RecipeStatus(itemID)
	local recipe = recipes[itemID]
	if not recipe or not skills[recipe.skill] then
		return nil
	end
	local status = statusCache[itemID]
	if not status then
		status = ScanRecipe(itemID)
		statusCache[itemID] = status
	end
	if status == "ok" or (status == "low" and Radar.db.showLowSkill) then
		return status
	end
end

local function GetVendors(mapID)
	local list = indexReady and mapID and vendorsByMap[mapID]
	if not list then
		return nil
	end
	local result
	for _, vendor in ipairs(list) do
		if vendor.team == "N" or vendor.team == playerTeam then
			local open
			for _, itemID in ipairs(vendor.items) do
				local status = RecipeStatus(itemID)
				if status then
					open = open or {}
					open[#open + 1] = { itemID, status }
				end
			end
			if open then
				result = result or {}
				result[#result + 1] = { vendor = vendor, recipes = open }
			end
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Shared pin behaviour (tooltip, waypoint)
---------------------------------------------------------------------------
local function ShowVendorTooltip(owner, entry)
	local vendor = entry.vendor
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, DB.Npc.name(vendor.npc) or "?")
	local subName = DB.Npc.subName(vendor.npc)
	if subName then
		GameTooltip_AddNormalLine(GameTooltip, subName)
	end
	GameTooltip_AddNormalLine(GameTooltip, ("%.1f, %.1f"):format(vendor.x, vendor.y))
	for _, recipe in ipairs(entry.recipes) do
		local itemID, status = recipe[1], recipe[2]
		local name = C_Item.GetItemNameByID(itemID) or DB.Item.name(itemID) or ("item:" .. itemID)
		local color = status == "ok" and GREEN_FONT_COLOR or ORANGE_FONT_COLOR
		GameTooltip:AddLine(name, color.r, color.g, color.b)
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.RADAR_CLICK_WAYPOINT)
	GameTooltip:Show()
end

local function SetWaypoint(mapID, vendor)
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, vendor.x / 100, vendor.y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	if Radar.db.waypointMessage then
		ns.Print(L.RADAR_WAYPOINT_SET, DB.Npc.name(vendor.npc) or "?")
	end
end

local function PinIcon(entry)
	return C_Item.GetItemIconByID(entry.recipes[1][1]) or 134939
end

---------------------------------------------------------------------------
-- Recipe sources in item tooltips
---------------------------------------------------------------------------
local function ZoneName(npc)
	local spawns = DB.Npc.spawns(npc)
	for areaID in pairs(spawns or {}) do
		local info = areaToUiMap[areaID] and C_Map.GetMapInfo(areaToUiMap[areaID])
		if info then
			return info.name
		end
	end
	return ""
end

local function AddRecipeSources(tooltip, data)
	if not (indexReady and Radar.db.enabled and Radar.db.tooltipSources) or tooltip:IsForbidden() then
		return
	end
	local recipe = data and data.id and recipes[data.id]
	if not recipe then
		return
	end
	local shown = 0
	for _, npc in ipairs(recipe.vendors or {}) do
		local team = DB.Npc.friendlyToFaction(npc)
		if team and (team == "AH" or team == playerTeam) then
			shown = shown + 1
			if shown > TOOLTIP_MAX_VENDORS then
				tooltip:AddLine(L.RADAR_MORE_VENDORS, 0.7, 0.7, 0.7)
				break
			end
			tooltip:AddDoubleLine(L.RADAR_SOURCE_VENDOR:format(DB.Npc.name(npc) or "?"), ZoneName(npc), 1, 0.82, 0, 0.8, 0.8, 0.8)
		end
	end
	for i, questID in ipairs(recipe.quests or {}) do
		if i > TOOLTIP_MAX_QUESTS then
			break
		end
		tooltip:AddLine(L.RADAR_SOURCE_QUEST:format(DB.Quest.name(questID) or questID), 1, 0.82, 0)
	end
	if recipe.drops then
		tooltip:AddLine(L.RADAR_SOURCE_DROP:format(#recipe.drops), 1, 0.82, 0)
	end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
ForeverPlusRecipePinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverPlusRecipePinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

function ForeverPlusRecipePinMixin:OnAcquired(entry, mapID)
	self.entry, self.mapID = entry, mapID
	self.Icon:SetTexture(PinIcon(entry))
	self:SetPosition(entry.vendor.x / 100, entry.vendor.y / 100)
end

function ForeverPlusRecipePinMixin:OnMouseEnter()
	ShowVendorTooltip(self, self.entry)
end

function ForeverPlusRecipePinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function ForeverPlusRecipePinMixin:OnMouseClickAction(button)
	if button == "LeftButton" then
		SetWaypoint(self.mapID, self.entry.vendor)
	end
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function provider:RefreshAllData()
	self:RemoveAllData()
	local db = Radar.db
	if not (db.enabled and db.worldMap) then
		return
	end
	local mapID = self:GetMap():GetMapID()
	for _, entry in ipairs(GetVendors(mapID) or {}) do
		self:GetMap():AcquirePin(PIN_TEMPLATE, entry, mapID)
	end
end

local function RefreshWorldMap()
	if provider:GetMap() and provider:GetMap():IsShown() then
		provider:RefreshAllData()
	end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local minimapPins = {}
local activePins = {}
local minimapHolder
local currentMapID

local function CreateMinimapPin(index)
	local pin = CreateFrame("Button", nil, minimapHolder)
	pin:SetSize(14, 14)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetAllPoints()
	local mask = pin:CreateMaskTexture()
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints()
	pin.Icon:AddMaskTexture(mask)
	pin:SetScript("OnEnter", function(self)
		ShowVendorTooltip(self, self.entry)
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", function(self)
		SetWaypoint(currentMapID, self.entry.vendor)
	end)
	minimapPins[index] = pin
	return pin
end

local function PositionMinimapPins()
	if #activePins == 0 then
		return
	end
	local position = currentMapID and C_Map.GetPlayerMapPosition(currentMapID, "player")
	local width, height = C_Map.GetMapWorldSize(currentMapID)
	if not position or not width or width == 0 then
		for _, pin in ipairs(activePins) do
			pin:Hide()
		end
		return
	end
	local px, py = position:GetXY()
	local radius = C_Minimap.GetViewRadius()
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local facing = GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
	local sin, cos = math.sin(facing), math.cos(facing)

	for _, pin in ipairs(activePins) do
		local vendor = pin.entry.vendor
		-- Yards in screen orientation (x east, y north).
		local sx = (vendor.x / 100 - px) * width
		local sy = (py - vendor.y / 100) * height
		if facing ~= 0 then
			sx, sy = sx * cos + sy * sin, -sx * sin + sy * cos
		end
		local distance = math.sqrt(sx * sx + sy * sy)
		local onEdge = distance > radius
		if onEdge then
			sx, sy = sx * radius / distance, sy * radius / distance
		end
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", Minimap, "CENTER", sx / radius * halfWidth, sy / radius * halfHeight)
		pin:SetAlpha(onEdge and 0.6 or 1)
		pin:Show()
	end
end

local moving, turning = false, false
local elapsedSinceUpdate = 0

local function UpdateMinimapDriver()
	minimapHolder:SetScript("OnUpdate", (#activePins > 0 and (moving or turning)) and function(_, elapsed)
		elapsedSinceUpdate = elapsedSinceUpdate + elapsed
		if elapsedSinceUpdate >= MINIMAP_UPDATE_INTERVAL then
			elapsedSinceUpdate = 0
			PositionMinimapPins()
		end
	end or nil)
end

local function RefreshMinimap()
	wipe(activePins)
	for _, pin in ipairs(minimapPins) do
		pin:Hide()
	end
	local db = Radar.db
	currentMapID = C_Map.GetBestMapForUnit("player")
	if db.enabled and db.minimap and currentMapID then
		for index, entry in ipairs(GetVendors(currentMapID) or {}) do
			local pin = minimapPins[index] or CreateMinimapPin(index)
			pin.entry = entry
			pin.Icon:SetTexture(PinIcon(entry))
			activePins[index] = pin
		end
	end
	PositionMinimapPins()
	UpdateMinimapDriver()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local refreshPending = false

local function Refresh()
	refreshPending = false
	waitingForItems = false
	RefreshMinimap()
	RefreshWorldMap()
	Radar:ToggleEvent("GET_ITEM_INFO_RECEIVED", waitingForItems, function()
		wipe(statusCache)
		Radar:RequestRefresh()
	end)
end

function Radar:RequestRefresh()
	if not refreshPending then
		refreshPending = true
		C_Timer.After(0.5, Refresh)
	end
end

local function OnSkillsChanged()
	UpdateSkills()
	Radar:RequestRefresh()
end

local function SetMoving(_, event)
	if event == "PLAYER_STARTED_MOVING" then
		moving = true
	elseif event == "PLAYER_STOPPED_MOVING" then
		moving = false
	elseif event == "PLAYER_STARTED_TURNING" then
		turning = GetCVarBool("rotateMinimap")
	elseif event == "PLAYER_STOPPED_TURNING" then
		turning = false
	end
	UpdateMinimapDriver()
	PositionMinimapPins()
end

function Radar:Apply()
	local enabled = self.db.enabled and DB ~= nil
	local events = {
		ZONE_CHANGED_NEW_AREA = Radar.RequestRefresh,
		ZONE_CHANGED = Radar.RequestRefresh,
		ZONE_CHANGED_INDOORS = Radar.RequestRefresh,
		PLAYER_ENTERING_WORLD = Radar.RequestRefresh,
		SKILL_LINES_CHANGED = OnSkillsChanged,
		NEW_RECIPE_LEARNED = OnSkillsChanged,
		LEARNED_SPELL_IN_SKILL_LINE = OnSkillsChanged,
		PLAYER_STARTED_MOVING = SetMoving,
		PLAYER_STOPPED_MOVING = SetMoving,
		PLAYER_STARTED_TURNING = SetMoving,
		PLAYER_STOPPED_TURNING = SetMoving,
		MINIMAP_UPDATE_ZOOM = PositionMinimapPins,
	}
	for event, handler in pairs(events) do
		self:ToggleEvent(event, enabled, handler)
	end
	if enabled and not indexReady and not self.indexing then
		self.indexing = true
		BuildIndex(Refresh)
	end
	Refresh()
end

-- QuestieDB is an optional dependency (separate data addon).
local function FindQuestieDB()
	local lib = _G.LibQuestieDB
	if type(lib) ~= "table" or not lib.RequireContract or not lib.Item or not lib.Npc then
		return nil
	end
	local ok = lib.RequireContract(1)
	return ok and (ns.QuestieDB.Get() or lib) or nil
end

function Radar:OnLogin()
	playerTeam = UnitFactionGroup("player") == "Horde" and "H" or "A"
	minimapHolder = CreateFrame("Frame", nil, Minimap)
	minimapHolder:SetAllPoints()
	minimapHolder:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	DB = FindQuestieDB()
	if not DB then
		return
	end
	UpdateSkills()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(provider)
	end)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("RecipeRadar: tooltip", AddRecipeSources))
	-- Index after the login burst; it only runs while the radar is enabled.
	C_Timer.After(5, function()
		self:Apply()
	end)
end

-- /fp radar: state of the radar for troubleshooting.
function Radar:PrintStatus()
	if not DB then
		ns.PrintAlways(L.RADAR_STATUS_NO_DB)
		return
	end
	local recipeCount, vendorCount = 0, 0
	for _ in pairs(recipes) do
		recipeCount = recipeCount + 1
	end
	for _, list in pairs(vendorsByMap) do
		vendorCount = vendorCount + #list
	end
	ns.PrintAlways(L.RADAR_STATUS_INDEX, indexReady and L.RADAR_STATUS_READY or L.RADAR_STATUS_BUILDING, recipeCount, vendorCount)
	local professions = {}
	for skillLine, rank in pairs(skills) do
		professions[#professions + 1] = ("%d (%d)"):format(skillLine, rank)
	end
	ns.PrintAlways(L.RADAR_STATUS_SKILLS, #professions > 0 and table.concat(professions, ", ") or "-")
	local mapID = C_Map.GetBestMapForUnit("player")
	local all = mapID and vendorsByMap[mapID]
	ns.PrintAlways(L.RADAR_STATUS_MAP, mapID or 0, all and #all or 0, #(GetVendors(mapID) or {}))
end

function Radar:OnOptionChanged()
	if DB then
		self:Apply()
	end
end

Radar.options = {
	{ type = "header", name = L.RADAR_TITLE, desc = L.RADAR_REQUIRES },
	{ key = "enabled", type = "toggle", name = L.RADAR_ENABLE, desc = L.RADAR_ENABLE_DESC },
	{ key = "worldMap", type = "toggle", name = L.RADAR_WORLDMAP, parent = "enabled" },
	{ key = "minimap", type = "toggle", name = L.RADAR_MINIMAP, parent = "enabled" },
	{ key = "showLowSkill", type = "toggle", name = L.RADAR_LOW_SKILL, desc = L.RADAR_LOW_SKILL_DESC, parent = "enabled" },
	{ key = "tooltipSources", type = "toggle", name = L.RADAR_TOOLTIP, desc = L.RADAR_TOOLTIP_DESC, parent = "enabled" },
	{ key = "waypointMessage", type = "toggle", name = L.RADAR_WAYPOINT_MESSAGE, desc = L.MESSAGE_DESC, parent = "enabled" },
}

-- Recipe radar (like RecipeRadar): vendors selling recipes the player does not
-- know yet, shown on the world map and/or minimap. Clicking sets a waypoint.
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
	},
})

local PIN_TEMPLATE = "ForeverPlusRecipePinTemplate"
local MINIMAP_UPDATE_INTERVAL = 0.05

local data = ns.RecipeData
local zonesByMap        -- uiMapID -> zone entry
local skills = {}       -- skillLineID -> current rank
local known = {}        -- recipe itemID -> true once learned
local playerTeam
local waitingForItems = false

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
local function ResolveZones()
	zonesByMap = {}
	local unresolved = {}
	for name, zone in pairs(data.zones) do
		local info = C_Map.GetMapInfo(zone.map)
		if info and info.mapType == Enum.UIMapType.Zone then
			zonesByMap[zone.map] = zone
		else
			unresolved[name] = zone
			unresolved[zone.de] = zone
		end
	end
	if next(unresolved) == nil then
		return
	end
	-- Fall back to matching zone names (English / German clients).
	local azeroth = C_Map.GetMapChildrenInfo(947, Enum.UIMapType.Zone, true) or {}
	for _, info in ipairs(azeroth) do
		local zone = unresolved[info.name]
		if zone and not zonesByMap[info.mapID] then
			zonesByMap[info.mapID] = zone
		end
	end
end

local function UpdateSkills()
	wipe(skills)
	for _, index in pairs({ GetProfessions() }) do
		if index then
			local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				skills[skillLine] = rank or 0
			end
		end
	end
end

local function IsRecipeKnown(itemID)
	if known[itemID] then
		return true
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		waitingForItems = true
		return nil
	end
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	for _, line in ipairs(tooltip and tooltip.lines or {}) do
		if (line.type == Enum.TooltipDataLineType.UsageRequirement and line.requirementType == Enum.TooltipDataUsageRequirementType.NotAlreadyKnown)
			or line.leftText == ITEM_SPELL_KNOWN then
			known[itemID] = true
			return true
		end
	end
	return false
end

-- Returns "ok" (learnable now), "low" (skill too low) or nil (irrelevant/known).
local function RecipeStatus(itemID)
	local recipe = data.recipes[itemID]
	local rank = recipe and skills[recipe[1]]
	if not rank or IsRecipeKnown(itemID) ~= false then
		return nil
	end
	if rank >= recipe[2] then
		return "ok"
	end
	return Radar.db.showLowSkill and "low" or nil
end

-- Returns a list of { vendor = entry, recipes = { {itemID, status}, … } } for a map.
local function GetVendors(mapID)
	local zone = zonesByMap and zonesByMap[mapID]
	if not zone then
		return nil
	end
	local result
	for _, vendor in ipairs(zone.vendors) do
		local team = vendor[2]
		if team == "N" or team == playerTeam then
			local recipes
			for _, itemID in ipairs(vendor[5]) do
				local status = RecipeStatus(itemID)
				if status then
					recipes = recipes or {}
					recipes[#recipes + 1] = { itemID, status }
				end
			end
			if recipes then
				result = result or {}
				result[#result + 1] = { vendor = vendor, recipes = recipes }
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
	GameTooltip_SetTitle(GameTooltip, vendor[1])
	GameTooltip_AddNormalLine(GameTooltip, ("%.1f, %.1f"):format(vendor[3], vendor[4]))
	for _, recipe in ipairs(entry.recipes) do
		local itemID, status = recipe[1], recipe[2]
		local name = C_Item.GetItemNameByID(itemID) or ("item:" .. itemID)
		local color = status == "ok" and GREEN_FONT_COLOR or ORANGE_FONT_COLOR
		GameTooltip:AddDoubleLine(name, data.recipes[itemID][2], color.r, color.g, color.b, color.r, color.g, color.b)
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.RADAR_CLICK_WAYPOINT)
	GameTooltip:Show()
end

local function SetWaypoint(mapID, vendor)
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, vendor[3] / 100, vendor[4] / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	ns.Print(L.RADAR_WAYPOINT_SET, vendor[1])
end

local function PinIcon(entry)
	return C_Item.GetItemIconByID(entry.recipes[1][1]) or 134939
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
	self:SetPosition(entry.vendor[3] / 100, entry.vendor[4] / 100)
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
		local sx = (vendor[3] / 100 - px) * width
		local sy = (py - vendor[4] / 100) * height
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
	Radar:ToggleEvent("GET_ITEM_INFO_RECEIVED", waitingForItems, Radar.RequestRefresh)
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
	local enabled = self.db.enabled
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
	Refresh()
end

function Radar:OnLogin()
	playerTeam = UnitFactionGroup("player") == "Horde" and "H" or "A"
	minimapHolder = CreateFrame("Frame", nil, Minimap)
	minimapHolder:SetAllPoints()
	minimapHolder:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	ResolveZones()
	UpdateSkills()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(provider)
	end)
	self:Apply()
end

function Radar:OnOptionChanged()
	self:Apply()
end

Radar.options = {
	{ key = "enabled", type = "toggle", name = L.RADAR_ENABLE, desc = L.RADAR_ENABLE_DESC },
	{ key = "worldMap", type = "toggle", name = L.RADAR_WORLDMAP, parent = "enabled" },
	{ key = "minimap", type = "toggle", name = L.RADAR_MINIMAP, parent = "enabled" },
	{ key = "showLowSkill", type = "toggle", name = L.RADAR_LOW_SKILL, desc = L.RADAR_LOW_SKILL_DESC, parent = "enabled" },
	{ type = "header", name = L.RADAR_CREDIT_HEADER, desc = L.RADAR_CREDIT },
}

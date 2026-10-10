-- Minimap: player coordinates below the north marker. Updates only while the
-- player (or a taxi) is moving. World map: Blizzard's coordinates movable.
local _, ns = ...
local L = ns.L

local MinimapCoords = ns:NewModule("Minimap", {
	title = L.MINIMAP_TITLE,
	order = 3,
	defaults = {
		worldMapCoords = true,
		trackingIcons = true,
		trackingEntries = true,
		campfires = false,
	},
})

-- WoW Forever reports campfire placement through its item-effect spell casts,
-- but does not expose a list of nearby world objects to addons. Track exact
-- positions when the player or a group member places one.
local CAMPFIRE_SPELLS = {
	[1307227] = 15 * 60, -- Basic Campfire
	[1307252] = 15 * 60, -- Journeyman Campfire
	[1307237] = 15 * 60, -- Expert Campfire
}
local campfires, campfireHolder = {}, nil
local CAMPFIRE_ICON = [[Interface\Icons\INV_Misc_BBQFire_01]]

local function IsGroupUnit(unit)
	if type(unit) ~= "string" then
		return false
	end
	return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local function AddCampfire(unit, duration)
	local mapID = C_Map.GetBestMapForUnit(unit)
	local playerMapID = C_Map.GetBestMapForUnit("player")
	if not mapID or mapID ~= playerMapID then
		return
	end
	local position = C_Map.GetPlayerMapPosition(mapID, unit)
	if not position then
		return
	end
	local x, y = position:GetXY()
	local name, realm = UnitName(unit)
	local fire = {
		mapID = mapID,
		x = x,
		y = y,
		owner = realm and realm ~= "" and (name .. " - " .. realm) or name,
		expires = GetTime() + duration,
	}
	local pin = CreateFrame("Button", nil, campfireHolder)
	pin:SetSize(26, 28)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetSize(18, 18)
	pin.Icon:SetPoint("TOP", pin, "TOP")
	pin.Icon:SetTexture(CAMPFIRE_ICON)
	pin.Timer = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pin.Timer:SetPoint("TOP", pin.Icon, "BOTTOM", 0, 1)
	pin.Timer:SetJustifyH("CENTER")
	pin.Timer:SetTextColor(1, 0.85, 0.3)
	pin.Timer:SetShadowOffset(1, -1)
	pin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_CAMPFIRE)
		GameTooltip:AddLine(L.MINIMAP_CAMPFIRE_OWNER:format(fire.owner), 1, 1, 1)
		GameTooltip:AddLine(L.MINIMAP_CAMPFIRE_REMAINING:format(pin.Timer:GetText()), 1, 0.85, 0.3)
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	fire.pin = pin
	campfires[#campfires + 1] = fire
	return fire
end

local function FormatRemaining(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

local function PositionCampfires()
	if not campfireHolder or not MinimapCoords.db.campfires then
		if campfireHolder then
			campfireHolder:SetScript("OnUpdate", nil)
			for _, fire in ipairs(campfires) do fire.pin:Hide() end
		end
		return
	end
	local currentMapID = C_Map.GetBestMapForUnit("player")
	local position = currentMapID and C_Map.GetPlayerMapPosition(currentMapID, "player")
	local width, height
	if currentMapID then
		width, height = C_Map.GetMapWorldSize(currentMapID)
	end
	local radius = C_Minimap.GetViewRadius()
	if not position or not width or width == 0 or not height or height == 0 or not radius or radius == 0 then
		for _, fire in ipairs(campfires) do fire.pin:Hide() end
		return
	end
	local px, py = position:GetXY()
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local facing = GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
	local sin, cos = math.sin(facing), math.cos(facing)
	local now = GetTime()
	for index = #campfires, 1, -1 do
		local fire = campfires[index]
		if fire.expires <= now then
			fire.pin:Hide()
			table.remove(campfires, index)
		elseif fire.mapID == currentMapID then
			local sx = (fire.x - px) * width
			local sy = (py - fire.y) * height
			if facing ~= 0 then
				sx, sy = sx * cos + sy * sin, -sx * sin + sy * cos
			end
			local distance = math.sqrt(sx * sx + sy * sy)
			local onEdge = distance > radius
			if onEdge then
				sx, sy = sx * radius / distance, sy * radius / distance
			end
			fire.pin:ClearAllPoints()
			fire.pin:SetPoint("CENTER", Minimap, "CENTER", sx / radius * halfWidth, sy / radius * halfHeight)
			fire.pin:SetAlpha(onEdge and 0.6 or 1)
			fire.pin.Timer:SetText(FormatRemaining(fire.expires - now))
			fire.pin:Show()
		else
			fire.pin:Hide()
		end
	end
	if #campfires == 0 then
		campfireHolder:SetScript("OnUpdate", nil)
	elseif not campfireHolder:GetScript("OnUpdate") then
		campfireHolder:SetScript("OnUpdate", function(_, elapsed)
			MinimapCoords.campfireElapsed = (MinimapCoords.campfireElapsed or 0) + elapsed
			if MinimapCoords.campfireElapsed >= 0.2 then
				MinimapCoords.campfireElapsed = 0
				PositionCampfires()
			end
		end)
	end
end

function MinimapCoords:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
	if type(spellID) ~= "number" or issecretvalue(spellID) then
		return
	end
	local duration = CAMPFIRE_SPELLS[spellID]
	if not self.db.campfires or not IsGroupUnit(unit) or not duration then
		return
	end
	AddCampfire(unit, duration)
	PositionCampfires()
end

local UPDATE_INTERVAL = 0.2
local text, ticker, lastX, lastY

local function Update()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		if lastX then
			text:SetText("")
			lastX, lastY = nil, nil
		end
		return
	end
	local x, y = position:GetXY()
	x, y = floor(x * 1000 + 0.5), floor(y * 1000 + 0.5)
	if x ~= lastX or y ~= lastY then
		lastX, lastY = x, y
		text:SetFormattedText("%.1f, %.1f", x / 10, y / 10)
	end
end

local function StartTicker()
	if not ticker then
		ticker = C_Timer.NewTicker(UPDATE_INTERVAL, Update)
	end
end

local function StopTicker()
	if ticker and not UnitOnTaxi("player") then
		ticker:Cancel()
		ticker = nil
	end
	Update()
end

---------------------------------------------------------------------------
-- World map: own coordinate display of fixed size (Blizzard's panel changes
-- size whenever the cursor leaves the map, so it cannot be grabbed). Blizzard's
-- panel is only made invisible.
---------------------------------------------------------------------------
local MAP_INTERVAL = 0.05
local mapCoords, blizzardPanel

local function FindCoordsPanel()
	for _, frame in ipairs(WorldMapFrame.overlayFrames or {}) do
		if frame.PlayerCoords and frame.CursorCoords then
			return frame
		end
	end
end

local function FormatCoords(x, y)
	if not x or not y then
		return "–"
	end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local function UpdateMapCoords()
	local map = WorldMapFrame
	local cursorX, cursorY
	if map:IsCanvasMouseFocusOrPinFocus() then
		cursorX, cursorY = map:GetNormalizedCursorPosition()
	end
	local mapID = map:GetMapID()
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local playerX, playerY
	if position then
		playerX, playerY = position:GetXY()
	end
	mapCoords.Cursor:SetText(L.MAP_CURSOR:format(FormatCoords(cursorX, cursorY)))
	mapCoords.Player:SetText(L.MAP_PLAYER:format(FormatCoords(playerX, playerY)))
end

local function CreateMapCoords()
	local container = WorldMapFrame:GetCanvasContainer()
	local frame = CreateFrame("Frame", nil, WorldMapFrame)
	frame:SetSize(170, 32)
	frame:SetFrameStrata("HIGH")
	frame.Cursor = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Cursor:SetPoint("TOPLEFT", 4, -3)
	frame.Cursor:SetJustifyH("LEFT")
	frame.Player = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Player:SetPoint("TOPLEFT", frame.Cursor, "BOTTOMLEFT", 0, -2)
	frame.Player:SetJustifyH("LEFT")
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_WORLDMAP_COORDS)
		GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= MAP_INTERVAL then
			elapsed = 0
			UpdateMapCoords()
		end
	end)
	ns:RegisterDisplay(frame, "MapCoords", function(self)
		self:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 6)
	end, container)
	mapCoords = frame
end

function MinimapCoords:UpdateWorldMapCoords()
	if not WorldMapFrame then
		return
	end
	blizzardPanel = blizzardPanel or FindCoordsPanel()
	local enabled = self.db.worldMapCoords
	if enabled and not mapCoords then
		CreateMapCoords()
	end
	if mapCoords then
		mapCoords:SetShown(enabled)
	end
	if blizzardPanel then
		blizzardPanel:SetAlpha(enabled and 0 or 1)
	end
end

function MinimapCoords:UpdateFont()
	if text then
		text:SetFont(ns.GetFontFace(), 14, "OUTLINE")
	end
end

---------------------------------------------------------------------------
-- Tracking menu: spell icons fill their whole square, the other symbols
-- have empty margins. Spell icons get the visible size of the others.
---------------------------------------------------------------------------
local MENU_ICON_SIZE = 20 -- Blizzard's size in the tracking menu
local SPELL_ICON_SIZE = 15

local function ShrinkTrackingIcon(button, description)
	local info = description:GetData()
	if not MinimapCoords.db.trackingIcons or type(info) ~= "table" or info.type ~= "spell" then
		return
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:IsObjectType("Texture") and region:GetNumPoints() == 1 then
			local point, relativeTo = region:GetPoint(1)
			if point == "RIGHT" and relativeTo == button then
				region:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
				region:SetPoint("RIGHT", button, "RIGHT", -(MENU_ICON_SIZE - SPELL_ICON_SIZE) / 2, 0)
			end
		end
	end
end

local function AddIconInitializers(description)
	for _, element in description:EnumerateElementDescriptions() do
		element:AddInitializer(ShrinkTrackingIcon)
		AddIconInitializers(element)
	end
end

-- Entries of ForeverPlus functions in the tracking menu: ns.AddTrackingEntry(fn)
-- with fn(rootDescription) adding its checkbox or submenu.
local trackingEntries = {}

function ns.AddTrackingEntry(fn)
	trackingEntries[#trackingEntries + 1] = fn
end

local function AddForeverPlusEntries(rootDescription)
	if not MinimapCoords.db.trackingEntries or #trackingEntries == 0 then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle("ForeverPlus")
	for _, fn in ipairs(trackingEntries) do
		fn(rootDescription)
	end
end

function MinimapCoords:OnLogin()
	campfireHolder = CreateFrame("Frame", nil, Minimap)
	campfireHolder:SetAllPoints()
	campfireHolder:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", self.db.campfires)
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_MINIMAP_TRACKING", function(_, rootDescription)
			AddIconInitializers(rootDescription)
			AddForeverPlusEntries(rootDescription)
		end)
	end
	-- Small frame around the text: movable and lockable like a window.
	local holder = CreateFrame("Frame", nil, Minimap)
	holder:SetSize(100, 18)
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	text = holder:CreateFontString(nil, "OVERLAY")
	self:UpdateFont()
	text:SetPoint("CENTER")
	holder:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_COORDS)
		GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
		GameTooltip:Show()
	end)
	holder:SetScript("OnLeave", GameTooltip_Hide)
	ns:RegisterDisplay(holder, "MinimapCoords", function(frame)
		frame:SetPoint("TOP", Minimap, "TOP", 0, -12)
	end, Minimap)
	local _, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	if color then
		text:SetTextColor(color:GetRGB())
	end

	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		self:UpdateWorldMapCoords()
	end)

	self:RegisterEvent("PLAYER_STARTED_MOVING", StartTicker)
	self:RegisterEvent("PLAYER_STOPPED_MOVING", StopTicker)
	self:RegisterEvent("PLAYER_CONTROL_LOST", StartTicker)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", StopTicker)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Update)
	self:RegisterEvent("ZONE_CHANGED", Update)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", Update)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", Update)
	Update()
end

function MinimapCoords:OnOptionChanged(key)
	if key == "campfires" then
		self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", self.db.campfires)
		PositionCampfires()
	else
		self:UpdateWorldMapCoords()
	end
end

MinimapCoords.options = {
	{ key = "worldMapCoords", type = "toggle", name = L.MINIMAP_WORLDMAP_COORDS, desc = L.MINIMAP_WORLDMAP_COORDS_DESC },
	{ key = "trackingIcons", type = "toggle", name = L.MINIMAP_TRACKING_ICONS, desc = L.MINIMAP_TRACKING_ICONS_DESC },
	{ key = "trackingEntries", type = "toggle", name = L.MINIMAP_TRACKING_ENTRIES, desc = L.MINIMAP_TRACKING_ENTRIES_DESC },
	{ key = "campfires", type = "toggle", name = L.MINIMAP_CAMPFIRES, desc = L.MINIMAP_CAMPFIRES_DESC, new = true },
}

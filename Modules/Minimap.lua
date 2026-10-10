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
	},
})

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

function MinimapCoords:OnOptionChanged()
	self:UpdateWorldMapCoords()
end

MinimapCoords.options = {
	{ key = "worldMapCoords", type = "toggle", name = L.MINIMAP_WORLDMAP_COORDS, desc = L.MINIMAP_WORLDMAP_COORDS_DESC },
	{ key = "trackingIcons", type = "toggle", name = L.MINIMAP_TRACKING_ICONS, desc = L.MINIMAP_TRACKING_ICONS_DESC },
	{ key = "trackingEntries", type = "toggle", name = L.MINIMAP_TRACKING_ENTRIES, desc = L.MINIMAP_TRACKING_ENTRIES_DESC },
}

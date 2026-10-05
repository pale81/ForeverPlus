-- Minimap: player coordinates below the north marker. Updates only while the
-- player (or a taxi) is moving. World map: Blizzard's coordinates movable.
local _, ns = ...
local L = ns.L

local MinimapCoords = ns:NewModule("Minimap", {
	title = L.MINIMAP_TITLE,
	order = 3,
	defaults = {
		lockCoords = false,
		lockWorldMap = false,
		lockMessage = true,
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
-- World map: Blizzard's coordinate panel a bit higher and movable by mouse
---------------------------------------------------------------------------
local WORLDMAP_KEY = "WorldMapCoords"
local WORLDMAP_RAISE = 24 -- default lift above Blizzard's position

local function FindCoordsPanel()
	for _, frame in ipairs(WorldMapFrame.overlayFrames or {}) do
		if frame.PlayerCoords and frame.CursorCoords then
			return frame
		end
	end
end

local function SetupWorldMapCoords()
	local panel = FindCoordsPanel()
	if not panel then
		return
	end
	local container = WorldMapFrame:GetCanvasContainer()
	local raisedY

	-- Runs after Blizzard placed the panel next to its neighbours.
	local function Apply()
		local saved = ns.db.frames[WORLDMAP_KEY]
		if saved then
			panel:ClearAllPoints()
			panel:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", saved.x, saved.y)
		else
			-- Lift only Blizzard's own placement, never our previous one.
			local point, relativeTo, relativePoint, x, y = panel:GetPoint(1)
			if point and y ~= raisedY then
				raisedY = y + WORLDMAP_RAISE
				panel:ClearAllPoints()
				panel:SetPoint(point, relativeTo, relativePoint, x, raisedY)
			end
		end
	end
	hooksecurefunc(panel, "PostRefresh", Apply)

	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self)
		if not MinimapCoords.db.lockWorldMap then
			self:StartMoving()
		end
	end)
	panel:HookScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			local locked = not MinimapCoords.db.lockWorldMap
			Settings.SetValue("ForeverPlus_Minimap_lockWorldMap", locked)
			if MinimapCoords.db.lockMessage then
				ns.Print(locked and L.DISPLAY_LOCKED or L.DISPLAY_UNLOCKED)
			end
		end
	end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		local scale = container:GetEffectiveScale() / self:GetEffectiveScale()
		ns.db.frames[WORLDMAP_KEY] = {
			x = self:GetLeft() - container:GetLeft() * scale,
			y = self:GetBottom() - container:GetBottom() * scale,
		}
		Apply()
	end)
	Apply()
end

function MinimapCoords:UpdateFont()
	if text then
		text:SetFont(ns.GetFontFace(), 14, "OUTLINE")
	end
end

function MinimapCoords:OnLogin()
	-- Small frame around the text: movable like a window, right-click locks.
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
	ns:RegisterDisplay(holder, "MinimapCoords", self, "lockCoords", function(frame)
		frame:SetPoint("TOP", Minimap, "TOP", 0, -12)
	end)
	local _, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	if color then
		text:SetTextColor(color:GetRGB())
	end

	ns.OnAddOnLoaded("Blizzard_WorldMap", SetupWorldMapCoords)

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

MinimapCoords.options = {
	{ key = "lockCoords", type = "toggle", name = L.MINIMAP_LOCK_COORDS, desc = L.DISPLAY_LOCK_DESC },
	{ key = "lockWorldMap", type = "toggle", name = L.MINIMAP_LOCK_WORLDMAP, desc = L.DISPLAY_LOCK_DESC },
	{ key = "lockMessage", type = "toggle", name = L.DISPLAY_LOCK_MESSAGE, desc = L.MESSAGE_DESC },
}

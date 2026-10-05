-- Minimap: player coordinates below the north marker. Updates only while the
-- player (or a taxi) is moving.
local _, ns = ...
local L = ns.L

local MinimapCoords = ns:NewModule("Minimap", {
	title = L.MINIMAP_TITLE,
	order = 3,
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

function MinimapCoords:OnLogin()
	local holder = CreateFrame("Frame", nil, Minimap)
	holder:SetAllPoints()
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)

	text = holder:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
	text:SetPoint("TOP", Minimap, "TOP", 0, -14)
	local color = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
	if color then
		text:SetTextColor(color:GetRGB())
	end

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

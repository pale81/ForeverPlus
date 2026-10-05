-- Flight times: every flight is timed and remembered per route. The taxi map
-- shows the known time, during the flight a bar counts down (or up while the
-- route is still unknown).
local _, ns = ...
local L = ns.L

local Flight = ns:NewModule("Flight", {
	title = L.FLIGHT_TITLE,
	order = 5.3,
	defaults = {
		enabled = true,
		times = {}, -- "From -> To" -> seconds
	},
})

local MIN_FLIGHT = 5
local current -- { route =, start =, duration =, destination = }
local bar

local function CurrentNode()
	for index = 1, NumTaxiNodes() do
		if TaxiNodeGetType(index) == "CURRENT" then
			return TaxiNodeName(index)
		end
	end
end

local function RouteKey(from, to)
	return from and to and (from .. " -> " .. to)
end

local function KnownTime(index)
	local key = RouteKey(CurrentNode(), TaxiNodeName(index))
	return key and Flight.db.times[key]
end

local function FormatTime(seconds)
	seconds = max(0, floor(seconds + 0.5))
	return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Tooltips on the taxi map
---------------------------------------------------------------------------
local function AddTimeLine(index)
	if not Flight.db.enabled or not index or TaxiNodeGetType(index) ~= "REACHABLE" then
		return
	end
	local known = KnownTime(index)
	if known then
		GameTooltip:AddLine(L.FLIGHT_TIME:format(FormatTime(known)), 0.4, 0.8, 1)
	else
		GameTooltip:AddLine(L.FLIGHT_UNKNOWN, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Flight bar
---------------------------------------------------------------------------
local function UpdateBar()
	if not current then
		return
	end
	local elapsed = GetTime() - current.start
	if current.duration then
		local left = current.duration - elapsed
		bar:SetMinMaxValues(0, current.duration)
		bar:SetValue(min(elapsed, current.duration))
		bar.Time:SetText(left >= 0 and FormatTime(left) or ("+" .. FormatTime(-left)))
	else
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar.Time:SetText(FormatTime(elapsed))
	end
end

local function CreateBar()
	bar = CreateFrame("StatusBar", nil, UIParent)
	bar:SetSize(220, 14)
	bar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
	bar:SetStatusBarColor(0.25, 0.6, 1)
	bar.Background = bar:CreateTexture(nil, "BACKGROUND")
	bar.Background:SetAllPoints()
	bar.Background:SetColorTexture(0, 0, 0, 0.6)
	bar.Border = ns.CreatePixelBorder(bar, bar, 1, "OVERLAY", 7)
	bar.Border:ShowColor(0.1, 0.1, 0.1)
	bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Text:SetPoint("LEFT", 4, 0)
	bar.Time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Time:SetPoint("RIGHT", -4, 0)
	bar:Hide()
	local elapsed = 0
	bar:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 0.2 then
			elapsed = 0
			UpdateBar()
		end
	end)
	ns:RegisterDisplay(bar, "FlightBar", function(frame)
		frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end)
end

function Flight:UpdateFont()
	if bar then
		bar.Text:SetFont(ns.GetFontFace(), 11, "OUTLINE")
		bar.Time:SetFont(ns.GetFontFace(), 11, "OUTLINE")
	end
end

---------------------------------------------------------------------------
-- Timing
---------------------------------------------------------------------------
local pending -- route chosen on the taxi map, flight not started yet

local function OnTakeTaxi(index)
	local from, to = CurrentNode(), TaxiNodeName(index)
	pending = { route = RouteKey(from, to), destination = to }
end

function Flight:PLAYER_CONTROL_LOST()
	if not pending then
		return
	end
	C_Timer.After(0.5, function()
		if not pending or not UnitOnTaxi("player") then
			return
		end
		current = pending
		pending = nil
		current.start = GetTime() - 0.5
		current.duration = current.route and self.db.times[current.route]
		if self.db.enabled then
			if not bar then
				CreateBar()
			end
			self:UpdateFont()
			bar.Text:SetText(current.destination or "")
			UpdateBar()
			bar:Show()
		end
	end)
end

function Flight:PLAYER_CONTROL_GAINED()
	if not current then
		return
	end
	local duration = GetTime() - current.start
	-- Only complete flights count (not a flight ended early by a disconnect).
	if current.route and duration >= MIN_FLIGHT and not UnitOnTaxi("player") then
		self.db.times[current.route] = floor(duration + 0.5)
	end
	current = nil
	if bar then
		bar:Hide()
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Flight:OnLogin()
	hooksecurefunc("TakeTaxiNode", OnTakeTaxi)
	if TaxiNodeOnButtonEnter then
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
			AddTimeLine(button:GetID())
		end)
	end
	ns.OnAddOnLoaded("Blizzard_FlightMap", function()
		if FlightMap_FlightPointPinMixin and FlightMap_FlightPointPinMixin.OnMouseEnter then
			hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", function(pin)
				AddTimeLine(pin.taxiNodeData and pin.taxiNodeData.slotIndex)
			end)
		end
	end)
	self:RegisterEvent("PLAYER_CONTROL_LOST")
	self:RegisterEvent("PLAYER_CONTROL_GAINED")
end

function Flight:OnOptionChanged()
	if bar and not self.db.enabled then
		bar:Hide()
	end
end

Flight.options = {
	{ key = "enabled", type = "toggle", name = L.FLIGHT_ENABLE, desc = L.FLIGHT_ENABLE_DESC },
	{ type = "button", name = L.FLIGHT_RESET, text = L.RESET, desc = L.FLIGHT_RESET_DESC, func = function()
		wipe(Flight.db.times)
	end },
}

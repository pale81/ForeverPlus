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
		bar.StatusBar:SetMinMaxValues(0, current.duration)
		bar.StatusBar:SetValue(max(0, current.duration - elapsed))
		bar.Time:SetText(left >= 0 and FormatTime(left) or ("+" .. FormatTime(-left)))
	else
		bar.StatusBar:SetMinMaxValues(0, 1)
		bar.StatusBar:SetValue(1)
		bar.Time:SetText(FormatTime(elapsed))
	end
end

-- Built like Blizzard's timer bars (breath, fatigue): the casting bar art
-- with the name in the box below.
local function CreateBar()
	bar = CreateFrame("Frame", nil, UIParent)
	bar:SetSize(206, 32)
	bar.StatusBar = CreateFrame("StatusBar", nil, bar)
	bar.StatusBar:SetSize(195, 13)
	bar.StatusBar:SetPoint("TOP", 0, -2)
	bar.StatusBar:SetStatusBarTexture("ui-castingbar-filling-channel")
	bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())
	bar.TextBorder = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
	bar.TextBorder:SetAtlas("ui-castingbar-textbox")
	bar.TextBorder:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT")
	bar.TextBorder:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 0, -14)
	bar.Background = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
	bar.Background:SetAtlas("ui-castingbar-background")
	bar.Background:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", -1, 1)
	bar.Background:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 1, -1)
	bar.Border = bar:CreateTexture(nil, "OVERLAY")
	bar.Border:SetAtlas("ui-castingbar-frame")
	bar.Border:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", -2, 2)
	bar.Border:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 2, -2)
	bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Text:SetPoint("TOPLEFT", bar.StatusBar, "BOTTOMLEFT", 6, 0)
	bar.Text:SetPoint("BOTTOMRIGHT", bar.TextBorder, "BOTTOMRIGHT", -40, 2)
	bar.Text:SetJustifyH("LEFT")
	bar.Text:SetWordWrap(false)
	bar.Time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Time:SetPoint("TOPRIGHT", bar.StatusBar, "BOTTOMRIGHT", -6, 0)
	bar.Time:SetPoint("BOTTOM", bar.TextBorder, "BOTTOM", 0, 2)
	bar.Time:SetJustifyH("RIGHT")
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

---------------------------------------------------------------------------
-- Timing
---------------------------------------------------------------------------
local pending -- route chosen on the taxi map, flight not started yet

local function OnTakeTaxi(index)
	if not Flight.db.enabled then
		return
	end
	local from, to = CurrentNode(), TaxiNodeName(index)
	pending = { route = RouteKey(from, to), destination = to }
end

function Flight:PLAYER_CONTROL_LOST()
	if not pending or not self.db.enabled then
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

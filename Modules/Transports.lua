-- Zeppelin and boat rides: the client offers no list of transports, so rides
-- are recorded (a player who moves on the map without moving himself is on
-- one). The docks and destinations found this way appear as symbols on the
-- world map. Recordings stay in the saved settings of the player; /fp daten
-- export shows them as text to send in, so they can ship with a later update
-- (Data/Transports.lua).
local _, ns = ...
local L = ns.L

local Transports = ns:NewModule("Transports", {
	title = L.TRANSPORTS_TITLE,
	order = 11.5,
	defaults = {
		record = true,
		docks = true,
	},
})

local SAMPLE_INTERVAL = 0.5
local MOVE_EPS = 0.0008    -- map units per sample (about 2 yards) that count as moving
local START_SAMPLES = 2    -- samples of moving along without moving oneself
local STOP_SAMPLES = 4     -- samples of own or no movement that end the ride
local MIN_SECONDS = 20     -- shorter ones (elevators, knockbacks) are not rides
local MAX_RIDES = 200
local PATH_INTERVAL, MAX_PATH = 5, 60
local LOST_SECONDS = 90    -- without a position (open sea) for this long: ride over
local DOCK_RADIUS = 0.02   -- rides starting or ending this close share a dock

---------------------------------------------------------------------------
-- Recording: one sample every SAMPLE_INTERVAL, fed to a small state machine
---------------------------------------------------------------------------
local function Point(sample)
	return { mapID = sample.mapID, x = sample.x, y = sample.y }
end

local function Moved(a, b)
	return a.mapID == b.mapID and math.abs(a.x - b.x) + math.abs(a.y - b.y) > MOVE_EPS
end

-- sample: { time, mapID, x, y (nil without a position), speed, blocked }.
-- Returns the finished ride when this sample ends one:
-- { from = point, to = point, seconds, crossed, path = { { mapID, x, y }, … } }
function Transports.Step(state, sample)
	if not sample.x then
		local ride = state.ride
		if ride and sample.time - ride.lastSeen > LOST_SECONDS then
			state.ride, state.passive, state.calm = nil, 0, 0
			return ride.lastSeen - ride.start >= MIN_SECONDS and Transports.Finish(ride) or nil
		end
		return nil
	end
	local last = state.last
	local passive = false
	if last and not sample.blocked and sample.speed == 0 then
		-- Another map while a ride runs is a loading screen on a boat.
		passive = Moved(last, sample) or (state.ride ~= nil and last.mapID ~= sample.mapID)
	end
	local finished
	if passive then
		state.calm = 0
		state.passive = (state.passive or 0) + 1
		local ride = state.ride
		if not ride and state.passive >= START_SAMPLES and state.anchor then
			ride = { from = state.anchor, start = sample.time - SAMPLE_INTERVAL * state.passive, lastSeen = sample.time,
				path = {}, crossed = false, nextPath = sample.time }
			state.ride = ride
		end
		if ride then
			if last.mapID ~= sample.mapID then
				ride.crossed = true
			end
			ride.to, ride.lastSeen = Point(sample), sample.time
			if sample.time >= ride.nextPath and #ride.path < MAX_PATH then
				ride.path[#ride.path + 1] = { sample.mapID, sample.x, sample.y }
				ride.nextPath = sample.time + PATH_INTERVAL
			end
		end
	else
		state.passive = 0
		local ride = state.ride
		if ride then
			state.calm = (state.calm or 0) + 1
			if state.calm >= STOP_SAMPLES then
				state.ride, state.calm = nil, 0
				if ride.lastSeen - ride.start >= MIN_SECONDS then
					finished = Transports.Finish(ride)
				end
			end
		end
		if not state.ride then
			state.anchor = Point(sample)
		end
	end
	state.last = Point(sample)
	return finished
end

function Transports.Finish(ride)
	return {
		from = ride.from, to = ride.to or ride.from, seconds = math.floor(ride.lastSeen - ride.start + 0.5),
		crossed = ride.crossed, path = ride.path,
	}
end

local state = {}

local function Sample()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if position then
		x, y = position:GetXY()
		x, y = ns.Number(x), ns.Number(y)
	end
	local ride = Transports.Step(state, {
		time = GetTime(), mapID = mapID, x = x, y = y,
		speed = ns.Number((GetUnitSpeed("player")), 1),
		blocked = UnitOnTaxi("player") or IsFalling() or UnitIsDeadOrGhost("player") or InCombatLockdown(),
	})
	if ride then
		Transports:AddRide(ride)
	end
end

function Transports:AddRide(ride)
	local rides = ns.db.transportRides
	rides[#rides + 1] = {
		ride.from.mapID, ride.from.x, ride.from.y, ride.to.mapID, ride.to.x, ride.to.y, ride.seconds,
		time = time(), crossed = ride.crossed or nil, path = #ride.path > 0 and ride.path or nil,
	}
	while #rides > MAX_RIDES do
		table.remove(rides, 1)
	end
	self.docks = nil
	ns.MapSymbols.Refresh()
end

---------------------------------------------------------------------------
-- Docks and routes: shipped rides plus the player's own
---------------------------------------------------------------------------
local function Round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end

-- { [mapID] = { { x, y, map, routes = { { to = dock, seconds = {…} } } } } }
function Transports.BuildDocks(rides)
	local docks = {}
	local function Dock(mapID, x, y)
		local list = docks[mapID] or {}
		docks[mapID] = list
		for _, dock in ipairs(list) do
			if math.abs(dock.x - x) + math.abs(dock.y - y) <= DOCK_RADIUS then
				return dock
			end
		end
		local dock = { x = x, y = y, mapID = mapID, routes = {} }
		list[#list + 1] = dock
		return dock
	end
	for _, ride in ipairs(rides) do
		local fromMap, fromX, fromY, toMap, toX, toY, seconds = unpack(ride, 1, 7)
		if type(fromMap) == "number" and type(toMap) == "number" and type(fromX) == "number" and type(toX) == "number"
			and type(fromY) == "number" and type(toY) == "number" and type(seconds) == "number" then
			local from, to = Dock(fromMap, fromX, fromY), Dock(toMap, toX, toY)
			if from ~= to then
				local route
				for _, known in ipairs(from.routes) do
					if known.to == to then
						route = known
					end
				end
				if not route then
					route = { to = to, seconds = {} }
					from.routes[#from.routes + 1] = route
				end
				route.seconds[#route.seconds + 1] = seconds
			end
		end
	end
	return docks
end

local function AllRides()
	local list = {}
	for _, ride in ipairs(ns.TransportRoutes or {}) do
		list[#list + 1] = ride
	end
	for _, ride in ipairs(ns.db.transportRides or {}) do
		list[#list + 1] = ride
	end
	return list
end

function Transports:Docks()
	if not self.docks then
		self.docks = Transports.BuildDocks(AllRides())
	end
	return self.docks
end

local function Median(values)
	local sorted = { unpack(values) }
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

local function FormatTime(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and ns.Number(info.mapID) and type(info.name) == "string" and info.name or "?"
end

local function DockTooltip(tooltip, symbol)
	local dock = symbol.data
	tooltip:AddLine(L.TRANSPORTS_DOCK, 1, 1, 1)
	for _, route in ipairs(dock.routes) do
		tooltip:AddDoubleLine(L.TRANSPORTS_TO:format(MapName(route.to.mapID), #route.seconds),
			FormatTime(Median(route.seconds)), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if #dock.routes == 0 then
		tooltip:AddLine(L.TRANSPORTS_ARRIVAL, 0.6, 0.6, 0.6)
	end
end

ns.MapSymbols.AddSource(function(mapID, add)
	if not Transports.db.docks then
		return
	end
	local docks = Transports:Docks()
	ns.MapSymbols.ForZones(mapID, function(zoneMapID, toMap)
		for _, dock in ipairs(docks[zoneMapID] or {}) do
			local x, y = toMap(dock.x * 100, dock.y * 100)
			add(x, y, { kind = "transport", atlas = "taxinode_neutral", size = 18, data = dock, tooltip = DockTooltip })
		end
	end)
end)

---------------------------------------------------------------------------
-- Export: the recordings as text
---------------------------------------------------------------------------
function Transports.ExportText(rides)
	local lines = { L.TRANSPORTS_EXPORT_HEADER }
	for _, ride in ipairs(rides) do
		lines[#lines + 1] = ("{ %d, %.4f, %.4f, %d, %.4f, %.4f, %d },"):format(
			ride[1], Round(ride[2]), Round(ride[3]), ride[4], Round(ride[5]), Round(ride[6]), ride[7])
	end
	return table.concat(lines, "\n")
end

function Transports.Export()
	local rides = ns.db.transportRides
	if #rides == 0 then
		ns.PrintAlways(L.TRANSPORTS_EXPORT_NONE)
		return
	end
	ns.ShowEditWindow("TransportExport", L.TRANSPORTS_TITLE, Transports.ExportText(rides), CLOSE, function() end,
		L.TRANSPORTS_EXPORT_HINT)
end

function Transports.Clear()
	ns.db.transportRides = {}
	Transports.docks = nil
	state = {}
end

ns.AddDataSection(function()
	local rides = ns.db.transportRides
	return rides and #rides > 0 and Transports.ExportText(rides) or nil
end, Transports.Clear)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local ticker

function Transports:Apply()
	if self.db.record and not ticker then
		ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, Sample)
	elseif not self.db.record and ticker then
		ticker:Cancel()
		ticker, state = nil, {}
	end
	self:ToggleEvent("PLAYER_ENTERING_WORLD", self.db.record, function()
		-- A loading screen mid-ride (boats between continents) does not end it.
		state.last = nil
	end)
	if self.db.docks then
		ns.MapSymbols.Setup()
	end
	ns.MapSymbols.Refresh()
end

function Transports:OnInitialize()
	ns.db.transportRides = ns.db.transportRides or {}
end

function Transports:OnLogin()
	self:Apply()
end

function Transports:OnOptionChanged()
	self:Apply()
end

Transports.options = {
	{ key = "record", type = "toggle", name = L.TRANSPORTS_RECORD, desc = L.TRANSPORTS_RECORD_DESC },
	{ key = "docks", type = "toggle", name = L.TRANSPORTS_DOCKS, desc = L.TRANSPORTS_DOCKS_DESC },
}

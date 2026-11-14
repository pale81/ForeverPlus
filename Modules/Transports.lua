-- Zeppelin and boat rides: the stops come from Data/TransportPaths.lua,
-- the travel times from recordings: the client offers no list of rides, so rides
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
local SHIP_ICON = [[Interface\Icons\INV_Misc_Anchor]]
local AIRSHIP_ICON = [[Interface\Icons\INV_Misc_Toy_05]]

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

-- Docks by home map, and known stops by every map that shows them.
function Transports.BuildDocks(rides)
	local docks, positions = {}, {}
	local function AddPosition(dock, mapID, x, y)
		local entries = positions[mapID] or {}
		positions[mapID] = entries
		entries[#entries + 1] = { x = x, y = y, dock = dock }
	end

	local function Dock(mapID, x, y, stop, kind)
		local nearest, distance = nil, DOCK_RADIUS
		for _, entry in ipairs(positions[mapID] or {}) do
			local dock = entry.dock
			local delta = math.abs(entry.x - x) + math.abs(entry.y - y)
			if delta <= distance and (not stop or (dock.kind == kind and dock.area == stop[1])) then
				nearest, distance = dock, delta
			end
		end
		if nearest then
			return nearest
		end
		local dock = { x = x, y = y, mapID = mapID, routes = {}, area = stop and stop[1], kind = kind, stop = stop }
		local list = docks[mapID] or {}
		docks[mapID] = list
		list[#list + 1] = dock
		-- Recordings can report a nearby stop on the city map or its surrounding zone.
		if stop then
			for i = 2, #stop do
				AddPosition(dock, unpack(stop[i]))
			end
		else
			AddPosition(dock, mapID, x, y)
		end
		return dock
	end
	for _, ride in ipairs(rides) do
		local fromMap, fromX, fromY, toMap, toX, toY, seconds = unpack(ride, 1, 7)
		-- seconds: nil for a route known from the game data without a recorded ride
		if type(fromMap) == "number" and type(toMap) == "number" and type(fromX) == "number" and type(toX) == "number"
			and type(fromY) == "number" and type(toY) == "number" and (seconds == nil or type(seconds) == "number") then
			local from = Dock(fromMap, fromX, fromY, ride.fromStop, ride.kind)
			local to = Dock(toMap, toX, toY, ride.toStop, ride.kind)
			if from ~= to then
				local route
				for _, known in ipairs(from.routes) do
					if known.to == to then
						route = known
						break
					end
				end
				if not route then
					route = { to = to, seconds = {}, following = ride.following }
					from.routes[#from.routes + 1] = route
				end
				if seconds then
					route.seconds[#route.seconds + 1] = seconds
				end
			end
		end
	end
	return docks, positions
end

-- The first position of each stop is on its zone or city map, used to match recordings.
function Transports.PathRides(paths)
	local rides = {}
	for _, path in ipairs(paths or {}) do
		local kind, stops = path[1], path[2]
		for i, from in ipairs(stops) do
			local to = stops[i % #stops + 1]
			local a, b = from[2], to[2]
			local following = {}
			for offset = 2, #stops - 1 do
				following[#following + 1] = stops[(i + offset - 1) % #stops + 1]
			end
			rides[#rides + 1] = { a[1], a[2], a[3], b[1], b[2], b[3],
				kind = kind, fromStop = from, toStop = to, following = following }
		end
	end
	return rides
end

local function AllRides()
	local list = Transports.PathRides(ns.TransportPaths)
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
		self.docks, self.docksByMap = Transports.BuildDocks(AllRides())
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

local function PlaceName(mapID, area)
	local name = area and C_Map.GetAreaInfo(area)
	if type(name) == "string" and not ns.Secret(name) and name ~= "" then
		return name
	end
	local info = C_Map.GetMapInfo(mapID)
	name = info and info.name
	return type(name) == "string" and not ns.Secret(name) and name ~= "" and name or "?"
end

local function DockTooltip(tooltip, symbol)
	local dock, routes = symbol.data, symbol.routes
	local kind = dock.kind == "ship" and L.TRANSPORTS_SHIP
		or dock.kind == "zeppelin" and L.TRANSPORTS_ZEPPELIN
		or dock.kind == "airship" and L.TRANSPORTS_AIRSHIP or L.TRANSPORTS_DOCK
	tooltip:AddLine(kind, 1, 1, 1)
	tooltip:AddLine(PlaceName(dock.mapID, dock.area), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	for _, route in ipairs(routes) do
		local destination = PlaceName(route.to.mapID, route.to.area)
		if #route.seconds > 0 then
			tooltip:AddDoubleLine(L.TRANSPORTS_TO:format(destination, #route.seconds),
				FormatTime(Median(route.seconds)), 0.8, 0.8, 0.8, 1, 1, 1)
		else
			tooltip:AddLine(L.TRANSPORTS_TO_KNOWN:format(destination), 0.8, 0.8, 0.8)
		end
		for _, stop in ipairs(route.following or {}) do
			tooltip:AddLine(L.TRANSPORTS_THEN:format(PlaceName(stop[2][1], stop[1])), 0.8, 0.8, 0.8)
		end
	end
	if #routes == 0 then
		tooltip:AddLine(L.TRANSPORTS_ARRIVAL, 0.6, 0.6, 0.6)
	end
end

ns.MapSymbols.AddSource(function(mapID, add)
	if not Transports.db.docks then
		return
	end
	local docks = Transports:Docks()
	local info = C_Map.GetMapInfo(mapID)
	local overview = info and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.World)
	local grouped = {}
	local function AddDock(x, y, dock)
		local key = overview and dock.area and dock.kind .. ":" .. dock.area
		local symbol = key and grouped[key]
		if not symbol then
			local airborne = dock.kind == "zeppelin" or dock.kind == "airship"
			symbol = { kind = "transport", texture = airborne and AIRSHIP_ICON or SHIP_ICON, round = true,
				size = 18, data = dock, routes = {}, tooltip = DockTooltip }
			if key then
				grouped[key] = symbol
			end
			add(x, y, symbol)
		end
		for _, route in ipairs(dock.routes) do
			symbol.routes[#symbol.routes + 1] = route
		end
	end
	for _, entry in ipairs(Transports.docksByMap[mapID] or {}) do
		if entry.dock.stop then
			AddDock(entry.x, entry.y, entry.dock)
		end
	end
	ns.MapSymbols.ForZones(mapID, function(zoneMapID, toMap)
		for _, dock in ipairs(docks[zoneMapID] or {}) do
			if not dock.stop then
				local x, y = toMap(dock.x * 100, dock.y * 100)
				AddDock(x, y, dock)
			end
		end
	end)
end)

---------------------------------------------------------------------------
-- Export: the recordings as text
---------------------------------------------------------------------------
function Transports.ExportText(rides)
	local lines = { ns.ExportTag("rides"), L.TRANSPORTS_EXPORT_HEADER }
	for _, ride in ipairs(rides) do
		lines[#lines + 1] = ("{ %d, %.4f, %.4f, %d, %.4f, %.4f, %d },"):format(
			ride[1], Round(ride[2]), Round(ride[3]), ride[4], Round(ride[5]), Round(ride[6]), ride[7])
	end
	return table.concat(lines, "\n")
end

ns.AddMapFilterEntry(function(root)
	ns.CreateOptionCheckbox(root, L.TRANSPORTS_DOCKS, "Transports", "docks", L.TRANSPORTS_DOCKS_DESC)
end)

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
		ticker = ns.NewTicker("Transports: Sample", SAMPLE_INTERVAL, Sample)
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

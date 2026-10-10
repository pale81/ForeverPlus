-- Symbols and names on the world map: instance entrances, flight masters,
-- inns, names of towns and capitals and the recipe radar's vendors. Own
-- frames over Blizzard's map canvas instead of its pin system: pins acquired
-- from addon code set protected mouse settings (SetPassThroughButtons) and
-- are blocked in combat. Options live in the WorldMap module and the radar.
local _, ns = ...
local L = ns.L

local Symbols = {}
ns.MapSymbols = Symbols

local ENTRANCE_SIZE, FLIGHT_SIZE, INN_SIZE = 22, 16, 15
local MERGE_DISTANCE = 1 -- entrances closer than this (map percent) share a symbol
-- npcFlags bits in QuestieDB's Forever data (checked on known flight masters
-- and innkeepers); the inn flag also marks some mount vendors, so innkeepers
-- are recognised by their base title as well.
local FLIGHT_MASTER_FLAG, INNKEEPER_FLAG = 8, 128
local INNKEEPER_TITLE = "Innkeeper"
local FLIGHT_ATLAS = { A = "taxinode_alliance", H = "taxinode_horde", AH = "taxinode_neutral" }
local ROUND_MASK = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

local layer
local frames, used = {}, 0
local sources = {}
local entrances  -- uiMapID -> { { x, y, names = { { name, kind } } } } (x, y: 0–100)
local npcs       -- { flights = { [uiMapID] = { … } }, inns = { … } }
local npcsBuilding = false
local rects = {}      -- "child:parent" -> { left, right, top, bottom } or false
local continents = {} -- uiMapID -> continent (instance map) ID or false
local positions = {}  -- uiMapID -> { [place] = { x, y } or false }

local function Text(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= "" then
		return value
	end
end

local function Options()
	return ns:GetModule("WorldMap").db
end

---------------------------------------------------------------------------
-- Map geometry
---------------------------------------------------------------------------
local function IsContinent(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.mapType == Enum.UIMapType.Continent or false
end

-- Position of a child map on a continent map (0–1), cached.
local function Rect(child, parent)
	local key = child .. ":" .. parent
	local rect = rects[key]
	if rect == nil then
		local left, right, top, bottom = C_Map.GetMapRectOnMap(child, parent)
		rect = left and right and top and bottom and { left, right, top, bottom } or false
		rects[key] = rect
	end
	return rect or nil
end

-- Calls fn(zoneMapID, toMap) for the map itself and, on continents, for its
-- zones; toMap(x, y) turns a zone position in percent into one on the map (0–1).
local function ForZones(mapID, fn)
	fn(mapID, function(x, y)
		return x / 100, y / 100
	end)
	if not IsContinent(mapID) then
		return
	end
	for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
		local rect = child.mapID and Rect(child.mapID, mapID)
		if rect then
			fn(child.mapID, function(x, y)
				return rect[1] + x / 100 * (rect[2] - rect[1]), rect[3] + y / 100 * (rect[4] - rect[3])
			end)
		end
	end
end

local function Continent(mapID)
	local continent = continents[mapID]
	if continent == nil then
		local id = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
		continent = ns.Number(id) or false
		continents[mapID] = continent
	end
	return continent or nil
end

-- Map of a world position and the position on that map, or on mapID.
local function WorldToMap(continent, x, y, mapID)
	local uiMapID, position = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), mapID)
	if not position then
		return nil
	end
	local px, py = position:GetXY()
	return ns.Number(uiMapID), ns.Number(px), ns.Number(py)
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function AddEntrance(uiMapID, x, y, name, kind)
	local list = entrances[uiMapID]
	if not list then
		list = {}
		entrances[uiMapID] = list
	end
	for _, entrance in ipairs(list) do
		if math.abs(entrance.x - x) < MERGE_DISTANCE and math.abs(entrance.y - y) < MERGE_DISTANCE then
			for _, known in ipairs(entrance.names) do
				if known[1] == name then
					return
				end
			end
			entrance.names[#entrance.names + 1] = { name, kind }
			return
		end
	end
	list[#list + 1] = { x = x, y = y, names = { { name, kind } } }
end

-- Entrances of the instances in the client's group finder
-- (Data/Instances.lua) at QuestieDB's positions; names from the client.
local function BuildEntrances(lib)
	entrances = {}
	local ok, zoneDB = pcall(lib.Support.Get, "ZoneDB")
	local dungeons = ok and type(zoneDB) == "table" and type(zoneDB.private) == "table" and zoneDB.private.dungeons
	local instanceAreas = ok and type(zoneDB) == "table" and zoneDB.instanceIdToAreaId
	if type(dungeons) ~= "table" or type(instanceAreas) ~= "table" then
		return
	end
	for instanceID, kind in pairs(ns.Instances or {}) do
		local areaID = instanceAreas[instanceID]
		local entry = areaID and dungeons[areaID]
		if type(entry) == "table" and type(entry[4]) == "table" then
			local name = Text(GetRealZoneText(instanceID)) or Text(entry[1]) or tostring(instanceID)
			for _, location in ipairs(entry[4]) do
				local uiMapID = type(location) == "table" and ns.QuestieDB.UiMapForArea(lib, location[1])
				local x, y = uiMapID and location[2], uiMapID and location[3]
				if type(x) == "number" and type(y) == "number" then
					AddEntrance(uiMapID, x, y, name, kind)
				end
			end
		end
	end
end

local function HasFlag(flags, flag)
	return type(flags) == "number" and math.floor(flags / flag) % 2 == 1
end

local function AddNpc(list, lib, npc, id, faction)
	for uiMapID, points in pairs(ns.QuestieDB.SpawnsByMap(lib, npc.Get(id, "spawns"))) do
		local entries = list[uiMapID]
		if not entries then
			entries = {}
			list[uiMapID] = entries
		end
		entries[#entries + 1] = { x = points[1][1], y = points[1][2], name = Text(npc.Get(id, "name")),
			title = Text(npc.Get(id, "subName")), faction = faction }
	end
end

-- Flight masters and innkeepers of the player's faction and neutral ones,
-- read once in the background.
local function BuildNpcs(lib, onDone)
	if npcs or npcsBuilding then
		return
	end
	local npc = lib.Npc
	if type(npc) ~= "table" or type(npc.GetAllIds) ~= "function" or type(npc.Get) ~= "function" then
		npcs = { flights = {}, inns = {} }
		return
	end
	npcsBuilding = true
	local faction = UnitFactionGroup("player")
	local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	local raw = type(npc.GetRaw) == "function" and npc.GetRaw or npc.Get
	local ids = npc.GetAllIds() or {}
	local found = { flights = {}, inns = {} }
	ns.RunSliced("Map symbols: NPCs", #ids, function(i)
		local id = ids[i]
		local flags = npc.Get(id, "npcFlags")
		local flight, inn = HasFlag(flags, FLIGHT_MASTER_FLAG), HasFlag(flags, INNKEEPER_FLAG)
		if flight or inn then
			local friendly = npc.Get(id, "friendlyToFaction")
			if type(friendly) == "string" and letter and friendly:find(letter, 1, true) then
				if flight then
					AddNpc(found.flights, lib, npc, id, friendly)
				end
				if inn and raw(id, "subName") == INNKEEPER_TITLE then
					AddNpc(found.inns, lib, npc, id, friendly)
				end
			end
		end
	end, function()
		npcs, npcsBuilding = found, false
		onDone()
	end)
end

-- Position of a place from Data/Places.lua on a map (0–1), cached per map.
local function PlacePosition(place, mapID)
	local cache = positions[mapID]
	if not cache then
		cache = {}
		positions[mapID] = cache
	end
	local cached = cache[place]
	if cached == nil then
		local _, x, y = WorldToMap(place[1], place[2], place[3], mapID)
		cached = x and y and x > 0 and x < 1 and y > 0 and y < 1 and { x, y } or false
		cache[place] = cached
	end
	return cached or nil
end

local function PlaceName(place)
	local info = place[4] ~= 0 and C_Map.GetAreaInfo(place[4])
	return Text(info) or place[5]
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
-- A source is function(mapID, add); add(x, y, symbol) with x, y from 0 to 1
-- on mapID and symbol = { kind, atlas | texture, size, round, label, font,
-- tooltip = function(tooltip, symbol), click = function(symbol, button) }.
function Symbols.AddSource(source)
	sources[#sources + 1] = source
end

local function EntranceTooltip(tooltip, symbol)
	for _, entry in ipairs(symbol.data.names) do
		tooltip:AddLine(entry[2] == "raid" and L.WORLDMAP_RAID:format(entry[1]) or entry[1], 1, 1, 1)
	end
	tooltip:AddLine(L.WORLDMAP_ENTRANCE, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
end

local function NpcTooltip(tooltip, symbol)
	tooltip:AddLine(symbol.data.name or symbol.fallback, 1, 1, 1)
	tooltip:AddLine(symbol.data.title or symbol.fallback, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
end

Symbols.AddSource(function(mapID, add)
	if not (Options().entrances and entrances) then
		return
	end
	ForZones(mapID, function(zoneMapID, toMap)
		for _, entrance in ipairs(entrances[zoneMapID] or {}) do
			local raid = true
			for _, entry in ipairs(entrance.names) do
				raid = raid and entry[2] == "raid"
			end
			local x, y = toMap(entrance.x, entrance.y)
			add(x, y, { kind = "entrance", atlas = raid and "raid" or "dungeon", size = ENTRANCE_SIZE, data = entrance, tooltip = EntranceTooltip })
		end
	end)
end)

Symbols.AddSource(function(mapID, add)
	if not (Options().flightPoints and npcs) then
		return
	end
	ForZones(mapID, function(zoneMapID, toMap)
		for _, flight in ipairs(npcs.flights[zoneMapID] or {}) do
			local x, y = toMap(flight.x, flight.y)
			add(x, y, { kind = "flight", atlas = FLIGHT_ATLAS[flight.faction] or FLIGHT_ATLAS.AH, size = FLIGHT_SIZE, data = flight,
				fallback = L.WORLDMAP_FLIGHT, tooltip = NpcTooltip })
		end
	end)
end)

-- Inns only on zone and city maps (on continents they would cover the towns).
Symbols.AddSource(function(mapID, add)
	if not (Options().inns and npcs) or IsContinent(mapID) then
		return
	end
	for _, inn in ipairs(npcs.inns[mapID] or {}) do
		add(inn.x / 100, inn.y / 100, { kind = "inn", atlas = "innkeeper", size = INN_SIZE, data = inn, fallback = L.WORLDMAP_INN, tooltip = NpcTooltip })
	end
end)

-- Towns on the map they belong to, capitals on the zone and continent maps
-- around them (not on their own city map).
Symbols.AddSource(function(mapID, add)
	if not Options().places or not ns.Places then
		return
	end
	local continent = Continent(mapID)
	for _, place in ipairs(ns.Places) do
		local city, home = place[6] == "city", place[7]
		local position = place[1] == continent and (city and home ~= mapID or not city and home == mapID)
			and PlacePosition(place, mapID)
		if position then
			add(position[1], position[2], { kind = "place", label = PlaceName(place),
				font = city and "GameFontNormalOutline" or "GameFontHighlightSmallOutline" })
		end
	end
end)

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function OnEnter(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	frame.symbol.tooltip(GameTooltip, frame.symbol)
	GameTooltip:Show()
end

local function OnMouseUp(frame, button)
	if frame.symbol.click then
		frame.symbol.click(frame.symbol, button)
	end
end

local function Acquire()
	used = used + 1
	local frame = frames[used]
	if not frame then
		frame = CreateFrame("Frame", nil, layer)
		frame.Icon = frame:CreateTexture(nil, "ARTWORK")
		frame.Icon:SetAllPoints()
		frame.Mask = frame:CreateMaskTexture()
		frame.Mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		frame.Mask:SetAllPoints(frame.Icon)
		frame.Label = frame:CreateFontString(nil, "OVERLAY")
		frame.Label:SetPoint("CENTER")
		frame:SetScript("OnEnter", OnEnter)
		frame:SetScript("OnLeave", GameTooltip_Hide)
		frame:SetScript("OnMouseUp", OnMouseUp)
		frames[used] = frame
	end
	frame:SetFrameLevel(layer:GetFrameLevel() + 1)
	frame:Show()
	return frame
end

local function Setup(frame, symbol)
	frame.symbol = symbol
	-- Like Blizzard's pins: hovering a symbol still counts as hovering the map
	-- (coordinates, zone highlight).
	frame.owningMap = WorldMapFrame
	if symbol.label then
		frame.Icon:Hide()
		frame.Label:SetFontObject(symbol.font)
		frame.Label:SetText(symbol.label)
		frame.Label:Show()
		frame:SetSize(frame.Label:GetStringWidth(), frame.Label:GetStringHeight())
		frame:EnableMouse(false)
		return
	end
	frame.Label:Hide()
	frame.Icon:Show()
	if symbol.atlas then
		frame.Icon:SetAtlas(symbol.atlas)
	else
		frame.Icon:SetTexture(symbol.texture)
	end
	if symbol.round then
		frame.Icon:AddMaskTexture(frame.Mask)
	else
		frame.Icon:RemoveMaskTexture(frame.Mask)
	end
	frame:SetSize(symbol.size, symbol.size)
	-- Hover shows the tooltip; clicks go on to the map unless the symbol
	-- has its own.
	frame:EnableMouse(symbol.tooltip ~= nil)
	frame:SetMouseClickEnabled(symbol.click ~= nil)
end

-- Positions in the canvas; the symbols keep their size while zooming.
local function Position()
	if used == 0 then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	local scale = 1 / ns.Number(WorldMapFrame:GetCanvasScale(), 1)
	for i = 1, used do
		local frame = frames[i]
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", canvas, "TOPLEFT", width * frame.x / scale, -height * frame.y / scale)
	end
end

local function Collect(mapID)
	local items = {}
	local function Add(x, y, symbol)
		if type(x) == "number" and type(y) == "number" then
			symbol.x, symbol.y = x, y
			items[#items + 1] = symbol
		end
	end
	for _, source in ipairs(sources) do
		source(mapID, Add)
	end
	return items
end

local function Draw()
	for i = 1, used do
		frames[i]:Hide()
	end
	used = 0
	local mapID = layer and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	if not mapID then
		return
	end
	for _, symbol in ipairs(Collect(mapID)) do
		local frame = Acquire()
		frame.x, frame.y = symbol.x, symbol.y
		Setup(frame, symbol)
	end
	Position()
end

-- Data on first use (the map open with an option on); the NPCs arrive a few
-- frames later and are drawn then.
function Symbols.Refresh()
	if not (layer and WorldMapFrame:IsShown()) then
		Draw()
		return
	end
	local db = Options()
	local lib = (db.entrances or db.flightPoints or db.inns) and ns.QuestieDB.Get()
	if lib then
		if db.entrances and not entrances then
			BuildEntrances(lib)
		end
		if db.flightPoints or db.inns then
			BuildNpcs(lib, Draw)
		end
	end
	Draw()
end

function Symbols.Setup()
	if layer or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	layer = CreateFrame("Frame", nil, canvas)
	layer:SetAllPoints(canvas)
	-- Between Blizzard's map layers and its pins, where its own entrance pins would be.
	local levels = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	local level = levels and ns.Number(levels:GetFrameLevelStart("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE"))
	if level then
		layer:SetFrameLevel(level)
	end
	local hooks = {
		OnMapChanged = ns.Measured("Map symbols", Symbols.Refresh),
		OnCanvasScaleChanged = Position,
		OnCanvasSizeChanged = Position,
	}
	for method, fn in pairs(hooks) do
		if type(WorldMapFrame[method]) == "function" then
			hooksecurefunc(WorldMapFrame, method, fn)
		end
	end
	WorldMapFrame:HookScript("OnShow", Symbols.Refresh)
end

-- Number of symbols per kind on a map, for /fp karte.
function Symbols.Count(mapID)
	local counts = {}
	for _, symbol in ipairs(Collect(mapID)) do
		counts[symbol.kind] = (counts[symbol.kind] or 0) + 1
	end
	return counts
end

-- World map: unexplored areas drawn faded (optionally tinted green) instead
-- of staying blank. The client only hands out explored map parts; the full
-- list comes from the game data in Data/MapOverlays.lua
-- (tools/mapoverlays.py). Blizzard's exploration pin stays untouched apart
-- from extra textures below its own.
-- Also symbols for instance entrances and flight masters (positions from
-- QuestieDB) on own frames over the map; Blizzard's map shows neither on
-- Forever's maps (no map has the ShowTaxiNodes flag).
local _, ns = ...
local L = ns.L

local WorldMap = ns:NewModule("WorldMap", {
	title = L.WORLDMAP_TITLE,
	order = 3.1,
	defaults = {
		reveal = true,
		revealAlpha = 60,
		revealTint = true,
		entrances = true,
		flightPoints = true,
	},
})

local PIN_TEMPLATE = "MapExplorationPinTemplate"
local TINT_R, TINT_G, TINT_B = 0.75, 1, 0.75
local DRAW_LAYER, SUB_LEVEL = "ARTWORK", -1 -- Blizzard draws explored parts at sub level 0

local pin
local textures, used = {}, 0
local parsed = {}

-- Map parts of one map art: { { width, height, left, top, file, file, … }, …,
-- known = { [first file] = true } }. Parsed on first use.
local function Overlays(artID)
	local list = artID and parsed[artID]
	if list == nil and artID then
		local raw = ns.MapOverlays and ns.MapOverlays[artID]
		list = false
		if raw then
			list = { known = {} }
			for part in raw:gmatch("[^;]+") do
				local overlay = {}
				for number in part:gmatch("-?%d+") do
					overlay[#overlay + 1] = tonumber(number)
				end
				list[#list + 1] = overlay
				list.known[overlay[5]] = true
			end
		end
		parsed[artID] = list
	end
	return list or nil
end

-- Parts of the map to draw: data for the map, explored parts by first file
-- and the number of explored parts missing from the data (then the data
-- belong to another map version and nothing is drawn).
local function Analyse(mapID)
	local artID = ns.Number(C_Map.GetMapArtID(mapID))
	local overlays = Overlays(artID)
	local explored, unknown = {}, 0
	if overlays then
		for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
			-- Parts without files (they exist in the data) have nothing to compare.
			local file = info.fileDataIDs and info.fileDataIDs[1]
			if file and overlays.known[file] then
				explored[file] = true
			elseif file then
				unknown = unknown + 1
			end
		end
	end
	return overlays, explored, unknown, artID
end

local function Release()
	for i = 1, used do
		textures[i]:Hide()
	end
	used = 0
end

local function Acquire()
	used = used + 1
	local texture = textures[used]
	if not texture then
		texture = pin:CreateTexture(nil, DRAW_LAYER, nil, SUB_LEVEL)
		textures[used] = texture
	end
	return texture
end

-- Visible pixels and file size of tile `index` out of `count`: the last
-- tile holds the rest, stored in the next power of two (at least 16).
local function TileSize(index, count, total, tile)
	if index < count then
		return tile, tile
	end
	local pixels = total - tile * (count - 1)
	local file = 16
	while file < pixels do
		file = file * 2
	end
	return pixels, file
end

local function DrawOverlay(acquire, overlay, tileWidth, tileHeight, alpha, r, g, b)
	local width, height, left, top = overlay[1], overlay[2], overlay[3], overlay[4]
	local columns, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
	if #overlay - 4 ~= columns * rows then
		return -- tiles of another size than the data were made for
	end
	for row = 1, rows do
		local pixelHeight, fileHeight = TileSize(row, rows, height, tileHeight)
		for column = 1, columns do
			local pixelWidth, fileWidth = TileSize(column, columns, width, tileWidth)
			local texture = acquire()
			texture:SetSize(pixelWidth, pixelHeight)
			texture:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
			texture:ClearAllPoints()
			texture:SetPoint("TOPLEFT", left + tileWidth * (column - 1), -(top + tileHeight * (row - 1)))
			texture:SetTexture(overlay[4 + (row - 1) * columns + column], nil, nil, "TRILINEAR")
			texture:SetVertexColor(r, g, b)
			texture:SetAlpha(alpha)
			texture:Show()
		end
	end
end

-- Unexplored parts of the map as the options ask for them.
local function DrawUnexplored(mapID, layer, acquire)
	local overlays, explored, unknown = Analyse(mapID)
	if not overlays or unknown > 0 then
		return
	end
	local db = WorldMap.db
	local alpha = db.revealAlpha / 100
	local r, g, b = 1, 1, 1
	if db.revealTint then
		r, g, b = TINT_R, TINT_G, TINT_B
	end
	for _, overlay in ipairs(overlays) do
		if not explored[overlay[5]] then
			DrawOverlay(acquire, overlay, layer.tileWidth, layer.tileHeight, alpha, r, g, b)
		end
	end
end

local function Draw()
	Release()
	local map = pin and pin:GetMap()
	local mapID = WorldMap.db.reveal and map and map:GetMapID()
	-- The data hold the first art layer (the only one of these maps).
	if not mapID or map:GetCanvasContainer():GetCurrentLayerIndex() ~= 1 then
		return
	end
	local layers = C_Map.GetMapArtLayers(mapID)
	if layers and layers[1] then
		DrawUnexplored(mapID, layers[1], Acquire)
	end
end

-- The map as the world map draws it, for small map views: base tiles,
-- explored parts and, with the reveal option, the unexplored ones; in map
-- pixels from the top left. acquire(drawLayer, subLevel) hands out a
-- texture. Returns the art layer (size of the drawing) or nil.
function WorldMap:DrawMapArt(mapID, acquire)
	local layers = C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	local files = layer and C_Map.GetMapArtLayerTextures(mapID, 1)
	if not files or #files == 0 then
		return nil
	end
	local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
	local columns = math.ceil(layer.layerWidth / tileWidth)
	for index, file in ipairs(files) do
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		local texture = acquire("BACKGROUND", 0)
		texture:SetSize(tileWidth, tileHeight)
		texture:SetTexCoord(0, 1, 0, 1)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", tileWidth * column, -tileHeight * row)
		texture:SetTexture(file, nil, nil, "TRILINEAR")
		texture:SetVertexColor(1, 1, 1)
		texture:SetAlpha(1)
		texture:Show()
	end
	for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
		if not info.isShownByMouseOver and type(info.fileDataIDs) == "table" then
			local part = { info.textureWidth, info.textureHeight, info.offsetX, info.offsetY, unpack(info.fileDataIDs) }
			local subLevel = info.isDrawOnTopLayer and 1 or 0
			DrawOverlay(function()
				return acquire("ARTWORK", subLevel)
			end, part, tileWidth, tileHeight, 1, 1, 1, 1)
		end
	end
	if self.db.reveal then
		DrawUnexplored(mapID, layer, function()
			return acquire("ARTWORK", SUB_LEVEL)
		end)
	end
	return layer
end

-- The map has exactly one exploration pin.
local function FindPin()
	local found
	for active in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do
		found = found or active
	end
	return found
end

---------------------------------------------------------------------------
-- Instance entrances and flight masters
---------------------------------------------------------------------------
local ENTRANCE_SIZE, FLIGHT_SIZE = 22, 16
local MERGE_DISTANCE = 1 -- entrances closer than this (map percent) share a symbol
local FLIGHT_MASTER_FLAG = 8 -- npcFlags bit in QuestieDB's Forever data
local FLIGHT_ATLAS = { A = "taxinode_alliance", H = "taxinode_horde", AH = "taxinode_neutral" }

local symbolLayer
local symbols, symbolsUsed = {}, 0
local entrances  -- uiMapID -> { { x, y, names = { { name, kind } } } } (x, y: 0–100)
local flights    -- uiMapID -> { { x, y, npc, name, title, faction } }
local flightsBuilding = false
local rects = {} -- "child:parent" -> { left, right, top, bottom } or false

local function Text(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= "" then
		return value
	end
end

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

local function PlayerFactionLetter()
	local faction = UnitFactionGroup("player")
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- Flight masters of the player's faction and neutral ones: all NPCs with
-- the flight master flag, read once in the background.
local function BuildFlights(lib, onDone)
	if flights or flightsBuilding then
		return
	end
	local npc = lib.Npc
	if type(npc) ~= "table" or type(npc.GetAllIds) ~= "function" or type(npc.Get) ~= "function" then
		flights = {}
		return
	end
	flightsBuilding = true
	local letter = PlayerFactionLetter()
	local ids = npc.GetAllIds() or {}
	local found = {}
	ns.RunSliced("WorldMap: flight masters", #ids, function(i)
		local id = ids[i]
		local flags = npc.Get(id, "npcFlags")
		if type(flags) == "number" and math.floor(flags / FLIGHT_MASTER_FLAG) % 2 == 1 then
			local faction = npc.Get(id, "friendlyToFaction")
			if type(faction) == "string" and letter and faction:find(letter, 1, true) then
				for uiMapID, points in pairs(ns.QuestieDB.SpawnsByMap(lib, npc.Get(id, "spawns"))) do
					local list = found[uiMapID]
					if not list then
						list = {}
						found[uiMapID] = list
					end
					list[#list + 1] = { x = points[1][1], y = points[1][2], name = Text(npc.Get(id, "name")),
						title = Text(npc.Get(id, "subName")), faction = faction }
				end
			end
		end
	end, function()
		flights, flightsBuilding = found, false
		onDone()
	end)
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

-- Symbols for a map: { x, y (0–1), kind = "entrance"|"flight", data }.
-- Continents show the symbols of their zones.
local function Collect(mapID, into)
	local db = WorldMap.db
	local function Add(childMapID, rect)
		local function Place(x, y, kind, data)
			x, y = x / 100, y / 100
			if rect then
				x, y = rect[1] + x * (rect[2] - rect[1]), rect[3] + y * (rect[4] - rect[3])
			end
			into[#into + 1] = { x = x, y = y, kind = kind, data = data }
		end
		if db.entrances and entrances then
			for _, entrance in ipairs(entrances[childMapID] or {}) do
				Place(entrance.x, entrance.y, "entrance", entrance)
			end
		end
		if db.flightPoints and flights then
			for _, flight in ipairs(flights[childMapID] or {}) do
				Place(flight.x, flight.y, "flight", flight)
			end
		end
	end
	Add(mapID)
	local info = C_Map.GetMapInfo(mapID)
	if info and info.mapType == Enum.UIMapType.Continent then
		for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
			local rect = child.mapID and Rect(child.mapID, mapID)
			if rect then
				Add(child.mapID, rect)
			end
		end
	end
	return into
end

local function ShowSymbolTooltip(symbol)
	local data = symbol.data
	GameTooltip:SetOwner(symbol, "ANCHOR_RIGHT")
	if symbol.kind == "entrance" then
		for _, entry in ipairs(data.names) do
			local name = entry[2] == "raid" and L.WORLDMAP_RAID:format(entry[1]) or entry[1]
			GameTooltip:AddLine(name, 1, 1, 1)
		end
		GameTooltip:AddLine(L.WORLDMAP_ENTRANCE, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	else
		GameTooltip:AddLine(data.name or L.WORLDMAP_FLIGHT, 1, 1, 1)
		GameTooltip:AddLine(data.title or L.WORLDMAP_FLIGHT, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	end
	GameTooltip:Show()
end

local function AcquireSymbol()
	symbolsUsed = symbolsUsed + 1
	local symbol = symbols[symbolsUsed]
	if not symbol then
		symbol = CreateFrame("Frame", nil, symbolLayer)
		symbol.Icon = symbol:CreateTexture(nil, "ARTWORK")
		symbol.Icon:SetAllPoints()
		-- Hover shows the tooltip; clicks go on to the map (dragging, zooming).
		symbol:EnableMouse(true)
		symbol:SetMouseClickEnabled(false)
		symbol:SetScript("OnEnter", ShowSymbolTooltip)
		symbol:SetScript("OnLeave", GameTooltip_Hide)
		symbols[symbolsUsed] = symbol
	end
	symbol:SetFrameLevel(symbolLayer:GetFrameLevel() + 1)
	symbol:Show()
	return symbol
end

-- Positions in the canvas; the symbols keep their size while zooming.
local function PlaceSymbols()
	if symbolsUsed == 0 then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	local scale = 1 / ns.Number(WorldMapFrame:GetCanvasScale(), 1)
	for i = 1, symbolsUsed do
		local symbol = symbols[i]
		symbol:SetScale(scale)
		symbol:ClearAllPoints()
		symbol:SetPoint("CENTER", canvas, "TOPLEFT", width * symbol.x / scale, -height * symbol.y / scale)
	end
end

local function DrawSymbols()
	for i = 1, symbolsUsed do
		symbols[i]:Hide()
	end
	symbolsUsed = 0
	local mapID = symbolLayer and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	if not mapID then
		return
	end
	for _, item in ipairs(Collect(mapID, {})) do
		local symbol = AcquireSymbol()
		symbol.x, symbol.y, symbol.kind, symbol.data = item.x, item.y, item.kind, item.data
		if item.kind == "entrance" then
			local raid = true
			for _, entry in ipairs(item.data.names) do
				raid = raid and entry[2] == "raid"
			end
			symbol.Icon:SetAtlas(raid and "raid" or "dungeon")
			symbol:SetSize(ENTRANCE_SIZE, ENTRANCE_SIZE)
		else
			symbol.Icon:SetAtlas(FLIGHT_ATLAS[item.data.faction] or FLIGHT_ATLAS.AH)
			symbol:SetSize(FLIGHT_SIZE, FLIGHT_SIZE)
		end
	end
	PlaceSymbols()
end

-- Data on first use (the map open with an option on); the flight masters
-- arrive a few frames later and are drawn then.
local function RefreshSymbols()
	local db = WorldMap.db
	local lib = (db.entrances or db.flightPoints) and ns.QuestieDB.Get()
	if lib then
		if db.entrances and not entrances then
			BuildEntrances(lib)
		end
		if db.flightPoints then
			BuildFlights(lib, DrawSymbols)
		end
	end
	DrawSymbols()
end

local function SetupSymbols()
	if symbolLayer or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	symbolLayer = CreateFrame("Frame", nil, canvas)
	symbolLayer:SetAllPoints(canvas)
	-- Between Blizzard's map layers and its pins, where its own entrance pins would be.
	local levels = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	local level = levels and ns.Number(levels:GetFrameLevelStart("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE"))
	if level then
		symbolLayer:SetFrameLevel(level)
	end
	local hooks = {
		OnMapChanged = ns.Measured("WorldMap: symbols", RefreshSymbols),
		OnCanvasScaleChanged = PlaceSymbols,
		OnCanvasSizeChanged = PlaceSymbols,
	}
	for method, fn in pairs(hooks) do
		if type(WorldMapFrame[method]) == "function" then
			hooksecurefunc(WorldMapFrame, method, fn)
		end
	end
	WorldMapFrame:HookScript("OnShow", RefreshSymbols)
end

-- /fp karte: how the data fit the open map (or the player's map).
-- Blizzard's pin redraws on map changes, exploration and zoom layer
-- changes; the extra parts follow right after.
function WorldMap:Apply()
	if self.db.reveal and ns.MapOverlays and not pin and WorldMapFrame then
		pin = FindPin()
		if pin then
			hooksecurefunc(pin, "RemoveAllData", Release)
			hooksecurefunc(pin, "RefreshOverlays", ns.Measured("WorldMap: overlays", Draw))
		end
	end
	if pin then
		Draw()
	end
	if (self.db.entrances or self.db.flightPoints) and WorldMapFrame then
		SetupSymbols()
	end
	if symbolLayer then
		RefreshSymbols()
	end
end

function WorldMap:OnLogin()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		self:Apply()
	end)
end

function WorldMap:OnOptionChanged()
	self:Apply()
end

local function PrintSymbolStatus(mapID)
	local counts = { entrance = 0, flight = 0 }
	for _, item in ipairs(Collect(mapID, {})) do
		counts[item.kind] = counts[item.kind] + 1
	end
	ns.PrintAlways(L.WORLDMAP_STATUS_SYMBOLS, counts.entrance, counts.flight, ns.InstanceBuild or "-")
end

function WorldMap:PrintStatus()
	local mapID = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
	if not mapID then
		return
	end
	local overlays, explored, unknown, artID = Analyse(mapID)
	if not overlays then
		ns.PrintAlways(L.WORLDMAP_STATUS_NO_DATA, mapID, artID or 0, ns.MapOverlayBuild or "-")
	else
		local exploredCount = 0
		for _ in pairs(explored) do
			exploredCount = exploredCount + 1
		end
		local layers = C_Map.GetMapArtLayers(mapID)
		local layer = layers and layers[1]
		ns.PrintAlways(L.WORLDMAP_STATUS, mapID, artID, #overlays, exploredCount,
			layer and ns.Number(layer.tileWidth, 0) or 0, layer and ns.Number(layer.tileHeight, 0) or 0)
		if unknown > 0 then
			ns.PrintAlways(L.WORLDMAP_STATUS_MISMATCH, unknown)
		end
	end
	PrintSymbolStatus(mapID)
end

WorldMap.options = {
	{ key = "entrances", type = "toggle", name = L.WORLDMAP_ENTRANCES, desc = L.WORLDMAP_ENTRANCES_DESC },
	{ key = "flightPoints", type = "toggle", name = L.WORLDMAP_FLIGHTS, desc = L.WORLDMAP_FLIGHTS_DESC },
}

-- Without the map data there is nothing to reveal.
if ns.MapOverlays then
	tinsert(WorldMap.options, 1, { key = "reveal", type = "toggle", name = L.WORLDMAP_REVEAL, desc = L.WORLDMAP_REVEAL_DESC })
	tinsert(WorldMap.options, 2, { key = "revealAlpha", type = "slider", name = L.WORLDMAP_REVEAL_ALPHA, parent = "reveal",
		min = 10, max = 100, step = 5, format = function(value)
			return ("%d %%"):format(value)
		end })
	tinsert(WorldMap.options, 3, { key = "revealTint", type = "toggle", name = L.WORLDMAP_REVEAL_TINT, desc = L.WORLDMAP_REVEAL_TINT_DESC, parent = "reveal" })
end

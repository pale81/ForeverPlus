-- World map: unexplored areas drawn faded (optionally tinted green) instead
-- of staying blank. The client only hands out explored map parts; the full
-- list comes from the game data in Data/MapOverlays.lua
-- (tools/mapoverlays.py). Blizzard's exploration pin stays untouched apart
-- from extra textures below its own.
-- Options for the symbols and names on the map (Modules/MapSymbols.lua).
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
		inns = true,
		places = true,
		placeInfo = true,
		questStarts = true,
		filterMenu = true,
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
	-- The zoom levels exist only once the map has been shown.
	local mapID = WorldMap.db.reveal and map and map:IsShown() and map:GetMapID()
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

-- Blizzard's pin redraws on map changes, exploration and zoom layer
-- changes; the extra parts follow right after.
function WorldMap:Apply()
	if self.db.reveal and ns.MapOverlays and not pin and WorldMapFrame then
		pin = FindPin()
		if pin then
			hooksecurefunc(pin, "RemoveAllData", Release)
			hooksecurefunc(pin, "RefreshOverlays", ns.Measured("WorldMap: overlays", Draw))
			-- A change of the options while the map was closed drew nothing: draw when it opens.
			WorldMapFrame:HookScript("OnShow", function()
				C_Timer.After(0, Draw)
			end)
		end
	end
	if pin then
		Draw()
	end
	local db = self.db
	if (db.entrances or db.flightPoints or db.inns or db.places or db.questStarts) and WorldMapFrame then
		ns.MapSymbols.Setup()
	end
	ns.MapSymbols.Refresh()
end

-- Our own entries in the filter menu of the map: the symbols and names.
ns.AddMapFilterEntry(function(root)
	if ns.MapOverlays then
		-- A submenu: on or off, how opaque, tinted green.
		local reveal = root:CreateButton(L.WORLDMAP_REVEAL)
		ns.CreateOptionCheckbox(reveal, L.WORLDMAP_REVEAL_SHOW, "WorldMap", "reveal", L.WORLDMAP_REVEAL_DESC)
		reveal:CreateTitle(L.WORLDMAP_REVEAL_ALPHA)
		for _, percent in ipairs({ 20, 40, 60, 80, 100 }) do
			reveal:CreateRadio(("%d %%"):format(percent), function()
				return math.abs((WorldMap.db.revealAlpha or 60) - percent) < 10
			end, function()
				Settings.SetValue("ForeverPlus_WorldMap_revealAlpha", percent)
			end)
		end
		ns.CreateOptionCheckbox(reveal, L.WORLDMAP_REVEAL_TINT, "WorldMap", "revealTint", L.WORLDMAP_REVEAL_TINT_DESC)
	end
	ns.CreateOptionCheckbox(root, L.WORLDMAP_ENTRANCES, "WorldMap", "entrances", L.WORLDMAP_ENTRANCES_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_FLIGHTS, "WorldMap", "flightPoints", L.WORLDMAP_FLIGHTS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_INNS, "WorldMap", "inns", L.WORLDMAP_INNS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_PLACES, "WorldMap", "places", L.WORLDMAP_PLACES_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_PLACE_INFO, "WorldMap", "placeInfo", L.WORLDMAP_PLACE_INFO_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_QUEST_STARTS, "WorldMap", "questStarts", L.WORLDMAP_QUEST_STARTS_DESC)
end)

-- The section of the map's filter menu (Blizzard's "Show" menu): a title and
-- every registered entry.
function WorldMap.AddFilterMenu(rootDescription)
	if not WorldMap.db.filterMenu or #ns.mapFilterEntries == 0 then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle(L.MENU_EXTRAS)
	for _, fn in ipairs(ns.mapFilterEntries) do
		fn(rootDescription)
	end
end

function WorldMap:OnLogin()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		self:Apply()
	end)
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, rootDescription)
			WorldMap.AddFilterMenu(rootDescription)
		end)
	end
end

function WorldMap:OnOptionChanged()
	self:Apply()
end

-- /fp karte: how the data fit the open map (or the player's map).
local function PrintSymbolStatus(mapID)
	local counts = ns.MapSymbols.Count(mapID)
	ns.PrintAlways(L.WORLDMAP_STATUS_SYMBOLS, counts.entrance or 0, counts.flight or 0, counts.inn or 0, counts.place or 0,
		counts.radar or 0, ns.InstanceBuild or "-")
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
	{ key = "filterMenu", type = "toggle", name = L.WORLDMAP_FILTER_MENU, desc = L.WORLDMAP_FILTER_MENU_DESC },
	{ key = "entrances", type = "toggle", name = L.WORLDMAP_ENTRANCES, desc = L.WORLDMAP_ENTRANCES_DESC },
	{ key = "flightPoints", type = "toggle", name = L.WORLDMAP_FLIGHTS, desc = L.WORLDMAP_FLIGHTS_DESC },
	{ key = "inns", type = "toggle", name = L.WORLDMAP_INNS, desc = L.WORLDMAP_INNS_DESC },
	{ key = "places", type = "toggle", name = L.WORLDMAP_PLACES, desc = L.WORLDMAP_PLACES_DESC },
	{ key = "placeInfo", type = "toggle", name = L.WORLDMAP_PLACE_INFO, desc = L.WORLDMAP_PLACE_INFO_DESC, parent = "places", new = true },
	{ key = "questStarts", type = "toggle", name = L.WORLDMAP_QUEST_STARTS, desc = L.WORLDMAP_QUEST_STARTS_DESC },
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

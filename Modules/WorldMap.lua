-- World map: unexplored areas drawn faded (optionally tinted green) instead
-- of staying blank. The client only hands out explored map parts; the full
-- list comes from the game data in Data/MapOverlays.lua
-- (tools/mapoverlays.py). Blizzard's exploration pin stays untouched apart
-- from extra textures below its own.
local _, ns = ...
local L = ns.L

local WorldMap = ns:NewModule("WorldMap", {
	title = L.WORLDMAP_TITLE,
	order = 3.1,
	defaults = {
		reveal = true,
		revealAlpha = 60,
		revealTint = true,
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

local function DrawOverlay(overlay, tileWidth, tileHeight, alpha, r, g, b)
	local width, height, left, top = overlay[1], overlay[2], overlay[3], overlay[4]
	local columns, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
	if #overlay - 4 ~= columns * rows then
		return -- tiles of another size than the data were made for
	end
	for row = 1, rows do
		local pixelHeight, fileHeight = TileSize(row, rows, height, tileHeight)
		for column = 1, columns do
			local pixelWidth, fileWidth = TileSize(column, columns, width, tileWidth)
			local texture = Acquire()
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

local function Draw()
	Release()
	local db = WorldMap.db
	local map = pin and pin:GetMap()
	local mapID = db.reveal and map and map:GetMapID()
	-- The data hold the first art layer (the only one of these maps).
	if not mapID or map:GetCanvasContainer():GetCurrentLayerIndex() ~= 1 then
		return
	end
	local overlays, explored, unknown = Analyse(mapID)
	local layers = overlays and unknown == 0 and C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	if not layer then
		return
	end
	local alpha = db.revealAlpha / 100
	local r, g, b = 1, 1, 1
	if db.revealTint then
		r, g, b = TINT_R, TINT_G, TINT_B
	end
	for _, overlay in ipairs(overlays) do
		if not explored[overlay[5]] then
			DrawOverlay(overlay, layer.tileWidth, layer.tileHeight, alpha, r, g, b)
		end
	end
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
		end
	end
	if pin then
		Draw()
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

-- /fp karte: how the data fit the open map (or the player's map).
function WorldMap:PrintStatus()
	local mapID = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
	if not mapID then
		return
	end
	local overlays, explored, unknown, artID = Analyse(mapID)
	if not overlays then
		ns.PrintAlways(L.WORLDMAP_STATUS_NO_DATA, mapID, artID or 0, ns.MapOverlayBuild or "-")
		return
	end
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

-- Without the map data there is nothing to offer.
WorldMap.options = ns.MapOverlays and {
	{ key = "reveal", type = "toggle", name = L.WORLDMAP_REVEAL, desc = L.WORLDMAP_REVEAL_DESC },
	{ key = "revealAlpha", type = "slider", name = L.WORLDMAP_REVEAL_ALPHA, parent = "reveal", min = 10, max = 100, step = 5,
		format = function(value)
			return ("%d %%"):format(value)
		end },
	{ key = "revealTint", type = "toggle", name = L.WORLDMAP_REVEAL_TINT, desc = L.WORLDMAP_REVEAL_TINT_DESC, parent = "reveal" },
}

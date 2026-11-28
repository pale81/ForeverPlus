-- World map: unexplored areas drawn faded (optionally tinted, green by default) instead
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
		revealAreas = true,
		revealColor = { r = 0.75, g = 1, b = 0.75 }, -- the tint, chosen in the map's filter menu
		entrances = true,
		flightPoints = true,
		inns = true,
		weaponMasters = true,
		places = true,
		placeInfo = true,
		areaInfo = true,
		symbolScale = 100,
		labelScale = 100,
		labelsMovable = false,
		labelOffsets = {}, -- "map:name" -> { dx, dy } in parts of the canvas
		questStarts = true,
		questTurnIns = true,
		discoveries = false,
		discoveryWaypoint = true,
		filterMenu = true,
		zoneLevels = true, -- the level range after the name of the zone under the mouse
	},
	charDefaults = {
		collectedDiscoveries = {},
	},
})

local PIN_TEMPLATE = "MapExplorationPinTemplate"
local DRAW_LAYER, SUB_LEVEL = "ARTWORK", -1 -- Blizzard draws explored parts at sub level 0
local CORE_SUB_LEVEL = 2 -- core area outlines sit above explored/unexplored tiles, below map pins
local CORE_BORDER = 2
local CORE_FILL_ALPHA, CORE_BORDER_ALPHA = 0.14, 0.65
local CORE_DOT_TEXTURE = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

local pin
local textures, used = {}, 0
local areaTextures, usedAreaTextures = {}, 0
local areaLayer, areaMarkers, usedAreaMarkers = nil, {}, 0
local parsed = {}
local parsedAreas = {}

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

-- Core HitRect and AreaID per map art part (parallel to Overlays):
-- { { hitLeft, hitTop, hitRight, hitBottom, areaID }, … }.
local function OverlayAreas(artID)
	local raw = artID and ns.MapOverlayAreas and ns.MapOverlayAreas[artID]
	if not raw then
		return nil
	end
	local cached = parsedAreas[artID]
	if cached and cached.raw == raw then
		return cached.list
	end
	local list = {}
	for part in raw:gmatch("[^;]+") do
		local entry = {}
		for number in part:gmatch("-?%d+") do
			entry[#entry + 1] = tonumber(number)
		end
		list[#list + 1] = entry
	end
	parsedAreas[artID] = { raw = raw, list = list }
	return list
end

-- Tighter core rectangle (pixels from top-left) and AreaID for an overlay part.
-- Uses Blizzard's HitRect when present, otherwise a centered inner half of the overlay texture.
function WorldMap.CoreRect(overlay, area, layerWidth, layerHeight)
	if not overlay then
		return nil
	end
	local left, top, right, bottom
	local areaID = area and area[5] or 0
	if area and area[3] and area[1] and area[4] and area[2] and area[3] > area[1] and area[4] > area[2] then
		left, top, right, bottom = area[1], area[2], area[3], area[4]
	else
		local w, h, ox, oy = overlay[1], overlay[2], overlay[3], overlay[4]
		left, top = ox + w * 0.25, oy + h * 0.25
		right, bottom = ox + w * 0.75, oy + h * 0.75
	end
	if type(layerWidth) == "number" and layerWidth > 0 then
		left = math.max(0, math.min(layerWidth, left))
		right = math.max(0, math.min(layerWidth, right))
	end
	if type(layerHeight) == "number" and layerHeight > 0 then
		top = math.max(0, math.min(layerHeight, top))
		bottom = math.max(0, math.min(layerHeight, bottom))
	end
	if right <= left or bottom <= top then
		return nil
	end
	return left, top, right, bottom, areaID
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
	for i = 1, usedAreaTextures do
		areaTextures[i]:Hide()
	end
	usedAreaTextures = 0
	for i = 1, usedAreaMarkers do
		areaMarkers[i]:Hide()
	end
	usedAreaMarkers = 0
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

local function AcquireAreaTexture()
	usedAreaTextures = usedAreaTextures + 1
	local texture = areaTextures[usedAreaTextures]
	if not texture then
		texture = pin:CreateTexture(nil, DRAW_LAYER, nil, CORE_SUB_LEVEL)
		areaTextures[usedAreaTextures] = texture
	end
	return texture
end

local function AreaDisplayName(areaID)
	local name = areaID and areaID > 0 and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
	if type(name) == "string" and not ns.Secret(name) and name ~= "" then
		return name
	end
	return L.WORLDMAP_UNEXPLORED_AREA
end

local function PositionAreaMarkers()
	if usedAreaMarkers == 0 or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then
		return
	end
	local scale = 1 / ns.Number(WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale(), 1)
	local width = ns.Number(canvas.GetWidth and canvas:GetWidth(), 0)
	local height = ns.Number(canvas.GetHeight and canvas:GetHeight(), 0)
	if width <= 0 or height <= 0 then
		return
	end
	for i = 1, usedAreaMarkers do
		local marker = areaMarkers[i]
		marker:SetScale(scale)
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", canvas, "TOPLEFT", width * marker.nx / scale, -height * marker.ny / scale)
	end
end

local function EnsureAreaLayer()
	if areaLayer or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return areaLayer
	end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then
		return nil
	end
	areaLayer = CreateFrame("Frame", nil, canvas)
	areaLayer:SetAllPoints(canvas)
	local levels = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	local level = levels and ns.Number(levels:GetFrameLevelStart("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE"))
	if level and level > 1 then
		areaLayer:SetFrameLevel(level - 1)
	end
	local reposition = ns.Measured("WorldMap: core markers", PositionAreaMarkers)
	for _, method in ipairs({ "OnCanvasScaleChanged", "OnCanvasSizeChanged" }) do
		if type(WorldMapFrame[method]) == "function" then
			hooksecurefunc(WorldMapFrame, method, reposition)
		end
	end
	return areaLayer
end

local function AcquireAreaMarker()
	local parent = EnsureAreaLayer()
	if not parent then
		return nil
	end
	usedAreaMarkers = usedAreaMarkers + 1
	local marker = areaMarkers[usedAreaMarkers]
	if not marker then
		marker = CreateFrame("Button", nil, parent)
		marker:SetSize(14, 14)
		marker:RegisterForClicks("LeftButtonUp")
		marker.owningMap = WorldMapFrame
		local ring = marker:CreateTexture(nil, "BACKGROUND")
		ring:SetSize(12, 12)
		ring:SetPoint("CENTER")
		ring:SetTexture(CORE_DOT_TEXTURE)
		ring:SetVertexColor(0, 0, 0)
		ring:SetAlpha(0.75)
		local dot = marker:CreateTexture(nil, "ARTWORK")
		dot:SetSize(8, 8)
		dot:SetPoint("CENTER")
		dot:SetTexture(CORE_DOT_TEXTURE)
		dot:SetAlpha(0.95)
		marker.dot = dot
		marker:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, AreaDisplayName(self.areaID))
			GameTooltip_AddNormalLine(GameTooltip, L.WORLDMAP_UNEXPLORED_AREA_HINT)
			if ns:GetModule("Waypoint") then
				GameTooltip_AddInstructionLine(GameTooltip, L.WORLDMAP_DISCOVERY_WAYPOINT_CLICK)
			end
			GameTooltip:Show()
		end)
		marker:SetScript("OnLeave", GameTooltip_Hide)
		marker:SetScript("OnClick", function(self, button)
			if button ~= "LeftButton" then
				return
			end
			local waypoint = ns:GetModule("Waypoint")
			if waypoint and waypoint.SetOnMap and self.mapID and self.nx and self.ny then
				GameTooltip:Hide()
				if not waypoint.SetOnMap(self.mapID, self.nx * 100, self.ny * 100, AreaDisplayName(self.areaID)) then
					ns.PrintAlways(L.WAYPOINT_NOT_HERE)
				end
			end
		end)
		areaMarkers[usedAreaMarkers] = marker
	end
	return marker
end

local function PlaceSolid(left, top, width, height, r, g, b, alpha)
	local texture = AcquireAreaTexture()
	texture:SetSize(width, height)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", left, -top)
	if texture.SetColorTexture then
		texture:SetColorTexture(1, 1, 1, 1)
	else
		texture:SetTexture([[Interface\Buttons\WHITE8X8]])
	end
	texture:SetVertexColor(r, g, b)
	texture:SetAlpha(alpha)
	texture:Show()
end

local function DrawCoreArea(mapID, left, top, right, bottom, areaID, layerWidth, layerHeight, r, g, b)
	local width, height = right - left, bottom - top
	if width <= 0 or height <= 0 then
		return
	end
	local border = math.min(CORE_BORDER, width / 2, height / 2)
	PlaceSolid(left, top, width, height, r, g, b, CORE_FILL_ALPHA)
	PlaceSolid(left, top, width, border, r, g, b, CORE_BORDER_ALPHA)
	PlaceSolid(left, bottom - border, width, border, r, g, b, CORE_BORDER_ALPHA)
	if height > border * 2 then
		PlaceSolid(left, top + border, border, height - border * 2, r, g, b, CORE_BORDER_ALPHA)
		PlaceSolid(right - border, top + border, border, height - border * 2, r, g, b, CORE_BORDER_ALPHA)
	end
	if type(layerWidth) == "number" and layerWidth > 0 and type(layerHeight) == "number" and layerHeight > 0 then
		local marker = AcquireAreaMarker()
		if marker then
			marker.mapID = mapID
			marker.areaID = areaID
			marker.nx = (left + right) / 2 / layerWidth
			marker.ny = (top + bottom) / 2 / layerHeight
			marker.dot:SetVertexColor(r, g, b)
			marker:Show()
		end
	end
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

-- The tint of unexplored parts: white (none) or the chosen colour; values that are not
-- colours (damaged saved data) count as the green of the defaults.
function WorldMap.TintColor(db)
	if not db.revealTint then
		return 1, 1, 1
	end
	local color, default = db.revealColor, WorldMap.defaults.revealColor
	local function Channel(key)
		local value = type(color) == "table" and tonumber(color[key])
		return value and math.min(1, math.max(0, value)) or default[key]
	end
	return Channel("r"), Channel("g"), Channel("b")
end

-- Colour and opacity of the unexplored parts on the map, without drawing them again
-- (the colour picker calls this while the colour is being chosen).
local function Paint()
	local db = WorldMap.db
	local r, g, b = WorldMap.TintColor(db)
	for i = 1, used do
		textures[i]:SetVertexColor(r, g, b)
		textures[i]:SetAlpha(db.revealAlpha / 100)
	end
	local cr, cg, cb = WorldMap.TintColor({ revealTint = true, revealColor = db.revealColor })
	for i = 1, usedAreaTextures do
		areaTextures[i]:SetVertexColor(cr, cg, cb)
	end
	for i = 1, usedAreaMarkers do
		areaMarkers[i].dot:SetVertexColor(cr, cg, cb)
	end
end

-- Unexplored parts of the map as the options ask for them.
local function DrawUnexplored(mapID, layer, acquire, withCores)
	local overlays, explored, unknown, artID = Analyse(mapID)
	if not overlays or unknown > 0 then
		return
	end
	local db = WorldMap.db
	local alpha = db.revealAlpha / 100
	local r, g, b = WorldMap.TintColor(db)
	local areas = withCores and db.revealAreas and OverlayAreas(artID) or nil
	local cr, cg, cb
	if areas then
		cr, cg, cb = WorldMap.TintColor({ revealTint = true, revealColor = db.revealColor })
	end
	local layerWidth = ns.Number(layer.layerWidth, 0)
	local layerHeight = ns.Number(layer.layerHeight, 0)
	for index, overlay in ipairs(overlays) do
		if not explored[overlay[5]] then
			DrawOverlay(acquire, overlay, layer.tileWidth, layer.tileHeight, alpha, r, g, b)
			if areas then
				local left, top, right, bottom, areaID = WorldMap.CoreRect(overlay, areas[index], layerWidth, layerHeight)
				if left then
					DrawCoreArea(mapID, left, top, right, bottom, areaID, layerWidth, layerHeight, cr, cg, cb)
				end
			end
		end
	end
	if usedAreaMarkers > 0 then
		PositionAreaMarkers()
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
		DrawUnexplored(mapID, layers[1], Acquire, true)
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
				ns.After("WorldMap: Draw", 0, Draw)
			end)
		end
	end
	if pin then
		Draw()
	end
	local db = self.db
	if (db.entrances or db.flightPoints or db.inns or db.weaponMasters or db.places or db.questStarts or db.questTurnIns or db.discoveries)
		and WorldMapFrame then
		ns.MapSymbols.Setup()
	end
	ns.MapSymbols.Refresh()
end

-- Blizzard's colour picker for the tint, with the opacity as its alpha slider (as for the chat
-- background). Changes show on the open map at once; Cancel puts the old values back.
function WorldMap.ChooseTint()
	local db = WorldMap.db
	local r, g, b = WorldMap.TintColor({ revealTint = true, revealColor = db.revealColor })
	local before = { color = { r = r, g = g, b = b }, alpha = db.revealAlpha, tint = db.revealTint }
	local function Changed()
		local newR, newG, newB = ColorPickerFrame:GetColorRGB()
		db.revealColor = { r = newR, g = newG, b = newB }
		db.revealAlpha = math.min(100, math.max(10, math.floor(ColorPickerFrame:GetColorAlpha() * 100 + 0.5)))
		db.revealTint = true
		Paint()
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, opacity = db.revealAlpha / 100, hasOpacity = true,
		swatchFunc = Changed, opacityFunc = Changed,
		cancelFunc = function()
			db.revealColor, db.revealAlpha, db.revealTint = before.color, before.alpha, before.tint
			Paint()
		end,
	})
end

-- Our own entries in the filter menu of the map: the symbols and names.
ns.AddMapFilterEntry(function(root)
	if ns.MapOverlays then
		-- A submenu: on or off, how opaque, tinted green.
		local reveal = root:CreateButton(L.WORLDMAP_REVEAL)
		ns.CreateOptionCheckbox(reveal, L.WORLDMAP_REVEAL_SHOW, "WorldMap", "reveal", L.WORLDMAP_REVEAL_DESC)
		reveal:CreateTitle(L.WORLDMAP_REVEAL_ALPHA)
		for _, percent in ipairs({ 20, 40, 60, 80, 100 }) do
			ns.CreateMenuRadio(reveal, ("%d %%"):format(percent), function()
				return math.abs((WorldMap.db.revealAlpha or 60) - percent) < 10
			end, function()
				ns.SetOption("WorldMap", "revealAlpha", percent)
			end)
		end
		ns.CreateOptionCheckbox(reveal, L.WORLDMAP_REVEAL_TINT, "WorldMap", "revealTint", L.WORLDMAP_REVEAL_TINT_DESC)
		ns.CreateOptionCheckbox(reveal, L.WORLDMAP_REVEAL_AREAS, "WorldMap", "revealAreas", L.WORLDMAP_REVEAL_AREAS_DESC)
		-- Blizzard's own colour entry: the name and a swatch of the current colour on the right.
		local r, g, b = WorldMap.TintColor({ revealTint = true, revealColor = WorldMap.db.revealColor })
		local swatch = reveal:CreateColorSwatch(L.WORLDMAP_REVEAL_COLOR, WorldMap.ChooseTint, { r = r, g = g, b = b })
		if swatch and swatch.SetTooltip then
			swatch:SetTooltip(function(tip)
				GameTooltip_SetTitle(tip, L.WORLDMAP_REVEAL_COLOR)
				GameTooltip_AddNormalLine(tip, L.WORLDMAP_REVEAL_COLOR_DESC)
			end)
		end
	end
	ns.CreateOptionCheckbox(root, L.WORLDMAP_ENTRANCES, "WorldMap", "entrances", L.WORLDMAP_ENTRANCES_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_FLIGHTS, "WorldMap", "flightPoints", L.WORLDMAP_FLIGHTS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_INNS, "WorldMap", "inns", L.WORLDMAP_INNS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_WEAPONS, "WorldMap", "weaponMasters", L.WORLDMAP_WEAPONS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_PLACES, "WorldMap", "places", L.WORLDMAP_PLACES_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_PLACE_INFO, "WorldMap", "placeInfo", L.WORLDMAP_PLACE_INFO_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_AREA_INFO, "WorldMap", "areaInfo", L.WORLDMAP_AREA_INFO_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_QUEST_STARTS, "WorldMap", "questStarts", L.WORLDMAP_QUEST_STARTS_DESC)
	ns.CreateOptionCheckbox(root, L.WORLDMAP_QUEST_TURN_INS, "WorldMap", "questTurnIns", L.WORLDMAP_QUEST_TURN_INS_DESC)
	local discoveries = root:CreateButton(L.WORLDMAP_DISCOVERIES_MENU)
	ns.CreateOptionCheckbox(discoveries, L.WORLDMAP_DISCOVERIES, "WorldMap", "discoveries", L.WORLDMAP_DISCOVERIES_DESC)
	ns.CreateOptionCheckbox(discoveries, L.LIBRARY_SYMBOLS, "Library", "symbols", L.LIBRARY_SYMBOLS_DESC)
	ns.CreateSizeMenu(root, L.WORLDMAP_SYMBOL_SCALE, "WorldMap", "symbolScale")
	ns.CreateSizeMenu(root, L.WORLDMAP_LABEL_SCALE, "WorldMap", "labelScale")
	ns.CreateOptionCheckbox(root, L.WORLDMAP_LABELS_MOVABLE, "WorldMap", "labelsMovable", L.WORLDMAP_LABELS_MOVABLE_DESC)
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

---------------------------------------------------------------------------
-- Recommended player levels for Forever's zones (Data/ZoneLevels.lua), in Blizzard's difficulty colours.
---------------------------------------------------------------------------
-- The text and colour for a range at the player's level, as Blizzard's own label does it.
function WorldMap.LevelText(low, high, playerLevel)
	local color
	if playerLevel < low then
		color = GetQuestDifficultyColor(low)
	elseif playerLevel > high then
		color = GetQuestDifficultyColor(high - 2) -- zones entirely below the player do not turn yellow
	else
		color = QuestDifficultyColors.difficult
	end
	local text = low == high and ("(%d)"):format(high) or ("(%d-%d)"):format(low, high)
	return text, color
end

-- The zone under the mouse, including the currently opened zone when there is no child map under the mouse.
function WorldMap.HoveredRange(map)
	if not (WorldMap.db.zoneLevels and ns.ZoneLevels and map:IsCanvasMouseFocus()) then
		return nil
	end
	local mapID = map:GetMapID()
	local x, y = map:GetNormalizedCursorPosition()
	if not (mapID and x and y) then
		return nil
	end
	local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
	local zoneID = info and info.mapID or mapID
	local range = ns.ZoneLevels[zoneID]
	if not range then
		return nil
	end
	local currentZone = zoneID == mapID
	if not currentZone then
		local low, high = C_Map.GetMapLevels(zoneID)
		if low and high and low > 0 and high > 0 then
			return nil -- Blizzard includes its own range in the name of the child map.
		end
	end
	info = info or C_Map.GetMapInfo(zoneID)
	if info and info.name then
		return range, info.name, currentZone
	end
end

local function UpdateLevelLabel(label)
	local text = label.fpLevels
	local map = label.dataProvider and label.dataProvider:GetMap()
	local range, name, currentZone
	if map then
		range, name, currentZone = WorldMap.HoveredRange(map)
	end
	if not range then
		text:Hide()
		return
	end
	local labelName = label.Name:GetText()
	local showZoneName = currentZone and (not labelName or labelName == "")
	-- A pin or a subzone can have its own label. Use the opened zone's name when Blizzard has no label.
	if not showZoneName and (labelName ~= name or not label.Name:IsVisible()) then
		text:Hide()
		return
	end
	if label.fpLevelCentered ~= showZoneName then
		label.fpLevelCentered = showZoneName
		text:ClearAllPoints()
		if showZoneName then
			text:SetPoint("TOP", label.Name, "TOP")
		else
			text:SetPoint("LEFT", label.Name, "RIGHT", 6, 0)
		end
	end
	local levels, color = WorldMap.LevelText(range[1], range[2], UnitLevel("player"))
	text:SetText(showZoneName and (name .. " " .. levels) or levels)
	text:SetTextColor(color.r, color.g, color.b)
	text:Show()
end

local function HookAreaLabel()
	for provider in pairs(WorldMapFrame.dataProviders or {}) do
		local label = type(provider) == "table" and provider.Label
		if label and label.Name and label.labelInfoByType and not label.fpLevels then
			label.fpLevels = label:CreateFontString(nil, "OVERLAY")
			label.fpLevels:SetFontObject(label.Name:GetFontObject() or "GameFontNormalLarge")
			label.fpLevels:Hide()
			label:HookScript("OnUpdate", ns.Measured("WorldMap: zone levels", UpdateLevelLabel))
			return label
		end
	end
end
WorldMap.HookAreaLabel = HookAreaLabel

function WorldMap:OnLogin()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PET_JOURNAL_LIST_UPDATE" }) do
		self:RegisterEvent(event, ns.MapSymbols.ScanDiscoveries)
	end
	ns.MapSymbols.ScanDiscoveries()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		self:Apply()
		HookAreaLabel()
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
		counts.radar or 0, counts.discovery or 0, ns.InstanceBuild or "-")
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
	{ key = "weaponMasters", type = "toggle", name = L.WORLDMAP_WEAPONS, desc = L.WORLDMAP_WEAPONS_DESC, new = true },
	{ key = "places", type = "toggle", name = L.WORLDMAP_PLACES, desc = L.WORLDMAP_PLACES_DESC },
	{ key = "placeInfo", type = "toggle", name = L.WORLDMAP_PLACE_INFO, desc = L.WORLDMAP_PLACE_INFO_DESC, parent = "places", new = true },
	{ key = "areaInfo", type = "toggle", name = L.WORLDMAP_AREA_INFO, desc = L.WORLDMAP_AREA_INFO_DESC, parent = "placeInfo", new = true },
	{ key = "questStarts", type = "toggle", name = L.WORLDMAP_QUEST_STARTS, desc = L.WORLDMAP_QUEST_STARTS_DESC },
	{ key = "questTurnIns", type = "toggle", name = L.WORLDMAP_QUEST_TURN_INS, desc = L.WORLDMAP_QUEST_TURN_INS_DESC, new = true },
	{ key = "discoveries", type = "toggle", name = L.WORLDMAP_DISCOVERIES, desc = L.WORLDMAP_DISCOVERIES_DESC, new = true },
	{ key = "discoveryWaypoint", type = "toggle", name = L.WORLDMAP_DISCOVERY_WAYPOINT, parent = "discoveries", new = true },
	{ type = "button", name = L.WORLDMAP_DISCOVERY_RESET, text = L.WORLDMAP_DISCOVERY_RESET, parent = "discoveries", func = function()
		ns.MapSymbols.ResetDiscoveryMarks()
	end },
	{ key = "zoneLevels", type = "toggle", name = L.WORLDMAP_ZONE_LEVELS, desc = L.WORLDMAP_ZONE_LEVELS_DESC, new = true },
	{ key = "symbolScale", type = "slider", name = L.WORLDMAP_SYMBOL_SCALE, desc = L.WORLDMAP_SYMBOL_SCALE_DESC, min = 50, max = 200, step = 5, new = true,
		format = function(value)
			return ("%d %%"):format(value)
		end },
	{ key = "labelsMovable", type = "toggle", name = L.WORLDMAP_LABELS_MOVABLE, desc = L.WORLDMAP_LABELS_MOVABLE_DESC, new = true },
	{ type = "button", name = L.WORLDMAP_LABELS_RESET, text = L.WORLDMAP_LABELS_RESET_TEXT, desc = L.WORLDMAP_LABELS_RESET_DESC, func = function()
		ns.MapSymbols.ResetNames()
	end },
	{ key = "labelScale", type = "slider", name = L.WORLDMAP_LABEL_SCALE, desc = L.WORLDMAP_LABEL_SCALE_DESC, min = 50, max = 200, step = 5, new = true,
		format = function(value)
			return ("%d %%"):format(value)
		end },
}

-- Without the map data there is nothing to reveal.
if ns.MapOverlays then
	tinsert(WorldMap.options, 1, { key = "reveal", type = "toggle", name = L.WORLDMAP_REVEAL, desc = L.WORLDMAP_REVEAL_DESC })
	tinsert(WorldMap.options, 2, { key = "revealAlpha", type = "slider", name = L.WORLDMAP_REVEAL_ALPHA, parent = "reveal",
		min = 10, max = 100, step = 5, format = function(value)
			return ("%d %%"):format(value)
		end })
	tinsert(WorldMap.options, 3, { key = "revealTint", type = "toggle", name = L.WORLDMAP_REVEAL_TINT, desc = L.WORLDMAP_REVEAL_TINT_DESC, parent = "reveal" })
	tinsert(WorldMap.options, 4, { key = "revealAreas", type = "toggle", name = L.WORLDMAP_REVEAL_AREAS, desc = L.WORLDMAP_REVEAL_AREAS_DESC, parent = "reveal", new = true })
end

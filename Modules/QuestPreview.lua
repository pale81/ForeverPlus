-- Quest preview: hovering a quest in the objective tracker shows a small map
-- of where its open objectives are, or where it is handed in once they are
-- done, with the objectives below. Positions come from QuestieDB; the map is
-- drawn like the world map (Modules/WorldMap.lua).
local _, ns = ...
local L = ns.L

local Preview = {}
ns.QuestPreview = Preview

local MAP_WIDTH = 260
local PADDING = ns.PANEL_PADDING
local GAP = 6
local MAX_POINTS = 150  -- per map; longer spawn lists are thinned out
local MAX_SOURCES = 12  -- NPCs or objects per item objective
local MAX_TURNIN_POINTS = 20
local MAX_OTHER_MAPS = 3
local DOT_SIZE, OUTLINE_SIZE = 6, 8
local TURNIN_SIZE, PLAYER_SIZE = 18, 16
local DOT_ATLAS = "WhiteCircle-RaidBlips"
local TURNIN_ATLAS = "QuestTurnin"
local PLAYER_ATLAS = "minimaparrow"
local OBJECTIVE_R, OBJECTIVE_G, OBJECTIVE_B = 1, 0.3, 0.1

local frame, canvas, marks
local mapTextures, mapUsed = {}, 0
local markTextures, markUsed = {}, 0
local spawnCache = { Npc = {}, Object = {} }

local function Text(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= "" then
		return value
	end
end

---------------------------------------------------------------------------
-- Targets from QuestieDB
---------------------------------------------------------------------------
-- Spawn points of an NPC or object by map, cached per session.
local function Spawns(lib, kind, id)
	local cache = spawnCache[kind]
	local cached = cache[id]
	if cached == nil then
		local entity = lib[kind]
		local ok, spawns = false, nil
		if type(entity) == "table" and type(entity.Get) == "function" and type(id) == "number" then
			ok, spawns = pcall(entity.Get, id, "spawns")
		end
		cached = ok and ns.QuestieDB.SpawnsByMap(lib, spawns) or false
		cache[id] = cached
	end
	return cached or nil
end

local function AddPoints(into, byMap)
	for mapID, points in pairs(byMap or {}) do
		local list = into[mapID]
		if not list then
			list = {}
			into[mapID] = list
		end
		for _, point in ipairs(points) do
			list[#list + 1] = point
		end
	end
end

-- Points of a target ({ npcs = {}, objects = {}, spawns = raw spawn list }).
local function AddTarget(lib, into, target)
	for _, id in ipairs(target.npcs or {}) do
		AddPoints(into, Spawns(lib, "Npc", id))
	end
	for _, id in ipairs(target.objects or {}) do
		AddPoints(into, Spawns(lib, "Object", id))
	end
	if target.spawns then
		AddPoints(into, ns.QuestieDB.SpawnsByMap(lib, target.spawns))
	end
end

-- The bundled MIT waypoint tables provide one quest-level objective point
-- (or a turn-in fallback), plus a separate turn-in point. Use them only when
-- richer objective-specific QuestieDB spawn data did not produce pins.
local function AddBundledPoints(_, questID, field, into)
	local bundled = ns.QuestieDB.Bundled()
	local points = bundled and bundled.Quest.Get(questID, field)
	if type(points) ~= "table" then
		return false
	end
	local added = false
	for _, point in ipairs(points) do
		if type(point) == "table" and type(point[1]) == "number"
			and type(point[2]) == "number" and type(point[3]) == "number" then
			local list = into[point[1]] or {}
			into[point[1]] = list
			list[#list + 1] = { point[2], point[3] }
			added = true
		end
	end
	return added
end

local function PointCount(maps)
	local count = 0
	for _, list in pairs(maps) do
		count = count + #list
	end
	return count
end

-- Recorded points (Modules/Observations.lua) of an objective or of the NPCs that take the quest back.
local function AddCells(into, cells)
	local added = false
	for _, cell in ipairs(cells) do
		local list = into[cell[1]] or {}
		into[cell[1]] = list
		list[#list + 1] = { cell[2], cell[3] }
		added = true
	end
	return added
end

local function First(list, count)
	local result = {}
	for i = 1, math.min(#(list or {}), count) do
		result[i] = list[i]
	end
	return result
end

local function ItemTarget(lib, itemID)
	local item = lib.Item
	if type(item) ~= "table" or type(item.Get) ~= "function" then
		return {}
	end
	return {
		npcs = First(item.Get(itemID, "npcDrops"), MAX_SOURCES),
		objects = First(item.Get(itemID, "objectDrops"), MAX_SOURCES),
	}
end

-- QuestieDB's targets per objective type, in the order in which the client
-- lists the objectives of that type (kill credit after the creatures unless
-- QuestieDB marks the quest otherwise).
local function TargetsByType(lib, questID)
	local objectives = lib.Quest.Get(questID, "objectives")
	objectives = type(objectives) == "table" and objectives or {}
	local creatures, credits = {}, {}
	for _, objective in ipairs(objectives[1] or {}) do
		creatures[#creatures + 1] = { npcs = { objective[1] } }
	end
	for _, objective in ipairs(objectives[5] or {}) do
		local npcs = First(objective[1], MAX_SOURCES)
		if type(objective[2]) == "number" and objective[2] ~= 0 then
			npcs[#npcs + 1] = objective[2]
		end
		credits[#credits + 1] = { npcs = npcs }
	end
	local first = type(lib.ObjectiveFirst) == "table" and lib.ObjectiveFirst.killCreditObjectiveFirst
	local monster = {}
	for _, list in ipairs(type(first) == "table" and first[questID] and { credits, creatures } or { creatures, credits }) do
		for _, target in ipairs(list) do
			monster[#monster + 1] = target
		end
	end
	local objects, items = {}, {}
	for _, objective in ipairs(objectives[2] or {}) do
		objects[#objects + 1] = { objects = { objective[1] } }
	end
	for _, objective in ipairs(objectives[3] or {}) do
		items[#items + 1] = ItemTarget(lib, objective[1])
	end
	local event = {}
	local trigger = lib.Quest.Get(questID, "triggerEnd")
	if type(trigger) == "table" and type(trigger[2]) == "table" then
		event[1] = { spawns = trigger[2] }
	end
	return { monster = monster, object = objects, item = items, event = event }
end

-- What the preview shows: title, objective lines, points per map and
-- whether the points are where the quest is handed in.
local function Build(questID)
	local lib = ns.QuestieDB.Get()
	if not lib then
		return nil
	end
	local model = {
		title = ns.QuestieDB.QuestName(lib, questID) or tostring(questID),
		lines = {},
		maps = {},
	}
	local targets = TargetsByType(lib, questID)
	local seen, open, total = {}, 0, 0
	for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		total = total + 1
		local kind = Text(objective.type) or "?"
		seen[kind] = (seen[kind] or 0) + 1
		local text = Text(objective.text)
		if text then
			model.lines[#model.lines + 1] = { text, objective.finished }
		end
		if not objective.finished then
			open = open + 1
			local list = targets[kind]
			local target = list and list[seen[kind]]
			local before = PointCount(model.maps)
			if target then
				AddTarget(lib, model.maps, target)
			end
			local observations = ns:GetModule("Observations")
			if PointCount(model.maps) == before then
				AddCells(model.maps, observations.TargetPoints(questID, kind, seen[kind]))
			end
			if PointCount(model.maps) == before then
				AddCells(model.maps, observations.ObjectivePoints(questID, total))
			end
		end
	end
	if open > 0 and next(model.maps) == nil then
		model.pointFallback = AddBundledPoints(lib, questID, "previewPoint", model.maps)
	end
	if total > 0 and open == 0 then
		model.turnIn = true
		local finishedBy = lib.Quest.Get(questID, "finishedBy")
		if type(finishedBy) == "table" then
			local npcs = First(finishedBy[1], MAX_TURNIN_POINTS)
			AddTarget(lib, model.maps, { npcs = npcs, objects = First(finishedBy[2], MAX_TURNIN_POINTS) })
			local npc = npcs[1]
			model.turnInName = npc and Text(lib.Npc.Get(npc, "name"))
		end
		if next(model.maps) == nil then
			for _, taker in ipairs(ns:GetModule("Observations").Takers(questID)) do
				if AddCells(model.maps, taker.cells) then
					model.turnInName = model.turnInName or Text(taker.name)
				end
			end
		end
		if next(model.maps) == nil then
			model.pointFallback = AddBundledPoints(lib, questID, "turnInPoint", model.maps)
				or AddBundledPoints(lib, questID, "previewPoint", model.maps)
		end
	end
	return model
end

-- The player's map when it holds points, else the map with the most.
local function ChooseMap(maps)
	local playerMap = ns.Number(C_Map.GetBestMapForUnit("player"))
	if playerMap and maps[playerMap] then
		return playerMap
	end
	local best, count = nil, 0
	for mapID, points in pairs(maps) do
		if #points > count then
			best, count = mapID, #points
		end
	end
	return best
end

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and Text(info.name)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function AcquireMap(drawLayer, subLevel)
	mapUsed = mapUsed + 1
	local texture = mapTextures[mapUsed]
	if not texture then
		texture = canvas:CreateTexture()
		mapTextures[mapUsed] = texture
	end
	texture:SetDrawLayer(drawLayer, subLevel)
	return texture
end

local function AcquireMark(subLevel)
	markUsed = markUsed + 1
	local texture = markTextures[markUsed]
	if not texture then
		texture = marks:CreateTexture()
		markTextures[markUsed] = texture
	end
	texture:SetDrawLayer("OVERLAY", subLevel)
	texture:SetRotation(0)
	texture:SetVertexColor(1, 1, 1)
	texture:Show()
	return texture
end

local function ReleaseAll()
	for i = 1, mapUsed do
		mapTextures[i]:Hide()
	end
	for i = 1, markUsed do
		markTextures[i]:Hide()
	end
	mapUsed, markUsed = 0, 0
end

local function Place(subLevel, atlas, size, x, y, width, height)
	local texture = AcquireMark(subLevel)
	texture:SetAtlas(atlas)
	texture:SetSize(size, size)
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", marks, "TOPLEFT", x * width, -y * height)
	return texture
end

-- Objective points as dots with a dark ring, turn-in points as the quest
-- turn-in icon.
local function DrawPoints(points, turnIn, width, height)
	local step = math.max(1, #points / (turnIn and MAX_TURNIN_POINTS or MAX_POINTS))
	local index = 1
	while index <= #points do
		local point = points[math.floor(index)]
		local x, y = point[1] / 100, point[2] / 100
		if turnIn then
			Place(2, TURNIN_ATLAS, TURNIN_SIZE, x, y, width, height)
		else
			Place(0, DOT_ATLAS, OUTLINE_SIZE, x, y, width, height):SetVertexColor(0, 0, 0)
			Place(1, DOT_ATLAS, DOT_SIZE, x, y, width, height):SetVertexColor(OBJECTIVE_R, OBJECTIVE_G, OBJECTIVE_B)
		end
		index = index + step
	end
end

local function DrawPlayer(mapID, width, height)
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return
	end
	local x, y = position:GetXY()
	x, y = ns.Number(x), ns.Number(y)
	if not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then
		return
	end
	Place(3, PLAYER_ATLAS, PLAYER_SIZE, x, y, width, height):SetRotation(ns.Number(GetPlayerFacing(), 0))
end

local function CreateWindow()
	-- The panel all ForeverPlus popups share (Core/Widgets.lua), shown like a tooltip.
	frame = ns.CreatePanel("ForeverPlusQuestPreview", { strata = "TOOLTIP", escape = false })
	frame:EnableMouse(false)
	frame:SetWidth(MAP_WIDTH + 2 * PADDING)
	frame.Title:SetWidth(MAP_WIDTH)
	frame.Map = CreateFrame("Frame", nil, frame)
	frame.Map:SetClipsChildren(true)
	frame.Map:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -GAP)
	canvas = CreateFrame("Frame", nil, frame.Map)
	canvas:SetPoint("TOPLEFT")
	marks = CreateFrame("Frame", nil, frame.Map)
	marks:SetAllPoints()
	marks:SetFrameLevel(canvas:GetFrameLevel() + 2)
	frame.Zone = marks:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	frame.Zone:SetPoint("TOPLEFT", 4, -4)
	frame.Body = frame:CreateFontString(nil, "ARTWORK", "GameTooltipText")
	frame.Body:SetWidth(MAP_WIDTH)
	frame.Body:SetJustifyH("LEFT")
	ns.SetUpdate(frame, "QuestPreview: update", function(self)
		if not (self.owner and self.owner:IsVisible() and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	frame:SetScript("OnHide", function(self)
		self.owner = nil
		ReleaseAll()
	end)
end

local function BodyText(model, mapID)
	local lines = {}
	for _, line in ipairs(model.lines) do
		local color = line[2] and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR
		lines[#lines + 1] = color:WrapTextInColorCode("- " .. line[1])
	end
	if model.turnIn then
		local place = model.turnInName or (mapID and MapName(mapID))
		lines[#lines + 1] = NORMAL_FONT_COLOR:WrapTextInColorCode(place and L.QUEST_PREVIEW_TURNIN:format(place) or L.QUEST_PREVIEW_TURNIN_NOW)
	end
	if model.pointFallback then
		lines[#lines + 1] = DISABLED_FONT_COLOR:WrapTextInColorCode(L.QUEST_PREVIEW_SOURCE_POINT)
	end
	if not mapID then
		lines[#lines + 1] = DISABLED_FONT_COLOR:WrapTextInColorCode(L.QUEST_PREVIEW_NO_PLACE)
	else
		local others = {}
		for otherID in pairs(model.maps) do
			local name = otherID ~= mapID and MapName(otherID)
			if name and #others < MAX_OTHER_MAPS then
				others[#others + 1] = name
			end
		end
		if #others > 0 then
			table.sort(others)
			lines[#lines + 1] = DISABLED_FONT_COLOR:WrapTextInColorCode(L.QUEST_PREVIEW_ELSEWHERE:format(table.concat(others, ", ")))
		end
	end
	return table.concat(lines, "\n")
end

-- Next to the tracker on the side facing the screen centre; beside
-- Blizzard's group progress tooltip when it shows.
local function Anchor(owner)
	local anchor = owner
	if GameTooltip:IsShown() and GameTooltip:GetOwner() == owner then
		anchor = GameTooltip
	end
	local center = owner:GetCenter()
	local onRight = center and center * owner:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
	frame:ClearAllPoints()
	if onRight then
		frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
	else
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
	end
end

-- The model of a quest is built once and kept until the quest log changes:
-- moving the mouse over the same title again costs nothing.
local modelCache = {}
local cacheWatching = false

function Preview.Show(owner, questID)
	questID = ns.Number(questID)
	if not cacheWatching then
		cacheWatching = true
		ns:RegisterEvent("QUEST_LOG_UPDATE", modelCache, function()
			wipe(modelCache)
		end)
	end
	local model = questID and questID > 0 and (modelCache[questID] or Build(questID))
	if model then
		modelCache[questID] = model
	end
	if not model then
		Preview.Hide()
		return
	end
	if not frame then
		CreateWindow()
	end
	ReleaseAll()
	frame.Title:SetText(model.title)
	local mapID = ChooseMap(model.maps)
	local layer = mapID and ns:GetModule("WorldMap"):DrawMapArt(mapID, AcquireMap)
	local mapHeight = 0
	if layer then
		local scale = MAP_WIDTH / layer.layerWidth
		mapHeight = layer.layerHeight * scale
		canvas:SetScale(scale)
		canvas:SetSize(layer.layerWidth, layer.layerHeight)
		frame.Map:SetSize(MAP_WIDTH, mapHeight)
		frame.Zone:SetText(MapName(mapID) or "")
		DrawPoints(model.maps[mapID], model.turnIn, MAP_WIDTH, mapHeight)
		DrawPlayer(mapID, MAP_WIDTH, mapHeight)
	else
		mapID = nil
		frame.Map:SetSize(MAP_WIDTH, 1)
	end
	frame.Map:SetShown(layer and true or false)
	frame.Body:ClearAllPoints()
	if layer then
		frame.Body:SetPoint("TOPLEFT", frame.Map, "BOTTOMLEFT", 0, -GAP)
	else
		frame.Body:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -GAP)
	end
	frame.Body:SetText(BodyText(model, mapID))
	local height = PADDING + frame.Title:GetStringHeight() + GAP + frame.Body:GetStringHeight() + PADDING
	if layer then
		height = height + mapHeight + GAP
	end
	frame:SetHeight(height)
	frame.owner = owner
	Anchor(owner)
	frame:Show()
end

function Preview.Hide()
	if frame then
		frame:Hide()
	end
end

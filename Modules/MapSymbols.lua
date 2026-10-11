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

local layer, currentMap
local PositionOne -- below
local frames, used = {}, 0
local sources = {}
local entrances  -- uiMapID -> { { x, y, names = { { name, kind } } } } (x, y: 0–100)
local npcs       -- { flights = { [uiMapID] = { … } }, inns = { … } }
local npcsBuilding = false
local questStarts -- uiMapID -> { { id, x, y, gate, any, all, excluded, blockedBy, parent, name } }
local questStartsBuilding = false
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
local function AddEntrance(uiMapID, x, y, name, kind, instanceID)
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
			entrance.names[#entrance.names + 1] = { name, kind, instanceID }
			return
		end
	end
	list[#list + 1] = { x = x, y = y, names = { { name, kind, instanceID } } }
end

-- Entrances of the instances in the client's group finder
-- (Data/Instances.lua): positions from the shipped data (Data/Points.lua),
-- QuestieDB's for the instances it does not cover; names from the client.
local function BuildEntrances(lib)
	entrances = {}
	local covered = {}
	local points = ns.Points and ns.Points.entrances or {}
	for instanceID, kind in pairs(ns.Instances or {}) do
		local row = points[instanceID]
		if row then
			local uiMapID, x, y
			if row[2] == "w" then
				uiMapID, x, y = WorldToMap(row[3], row[4], row[5])
				if not (x and y and x > 0 and x < 1 and y > 0 and y < 1) then
					uiMapID = nil
				end
				x, y = x and x * 100, y and y * 100
			else
				uiMapID, x, y = row[3], row[4], row[5]
			end
			if uiMapID and x and y then
				covered[instanceID] = true
				AddEntrance(uiMapID, x, y, Text(GetRealZoneText(instanceID)) or row[1], kind, instanceID)
			end
		end
	end
	if not lib then
		return
	end
	local ok, zoneDB = pcall(lib.Support.Get, "ZoneDB")
	local dungeons = ok and type(zoneDB) == "table" and type(zoneDB.private) == "table" and zoneDB.private.dungeons
	local instanceAreas = ok and type(zoneDB) == "table" and zoneDB.instanceIdToAreaId
	if type(dungeons) ~= "table" or type(instanceAreas) ~= "table" then
		return
	end
	for instanceID, kind in pairs(ns.Instances or {}) do
		local areaID = not covered[instanceID] and instanceAreas[instanceID]
		local entry = areaID and dungeons[areaID]
		if type(entry) == "table" and type(entry[4]) == "table" then
			local name = Text(GetRealZoneText(instanceID)) or Text(entry[1]) or tostring(instanceID)
			for _, location in ipairs(entry[4]) do
				local uiMapID = type(location) == "table" and ns.QuestieDB.UiMapForArea(lib, location[1])
				local x, y = uiMapID and location[2], uiMapID and location[3]
				if type(x) == "number" and type(y) == "number" then
					AddEntrance(uiMapID, x, y, name, kind, instanceID)
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
		entries[#entries + 1] = { id = id, x = points[1][1], y = points[1][2], name = Text(npc.Get(id, "name")),
			title = Text(npc.Get(id, "subName")), faction = faction }
	end
end

-- Flight masters of the player's faction and neutral ones from the shipped
-- data (Data/Points.lua); by map: { x, y, name, title, node, faction }.
local function BundledFlights(letter)
	local list = {}
	for _, flight in pairs(ns.Points and ns.Points.flights or {}) do
		local team = flight[5]
		if team == "N" or team == letter then
			local uiMapID = flight[2]
			list[uiMapID] = list[uiMapID] or {}
			tinsert(list[uiMapID], { x = flight[3], y = flight[4], name = flight[6] or flight[1], title = flight[7] or nil,
				node = flight[1], faction = team == "N" and "AH" or team })
		end
	end
	return list
end

-- Flight masters (shipped data, else QuestieDB's) and innkeepers (QuestieDB)
-- of the player's faction and neutral ones, read once in the background.
local function BuildNpcs(lib, onDone)
	if npcs or npcsBuilding then
		return
	end
	local faction = UnitFactionGroup("player")
	local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	local found = { flights = BundledFlights(letter), inns = {} }
	local bundledFlights = next(found.flights) ~= nil
	local npc = lib and lib.Npc
	if type(npc) ~= "table" or type(npc.GetAllIds) ~= "function" or type(npc.Get) ~= "function" then
		npcs = found
		return
	end
	npcsBuilding = true
	local raw = type(npc.GetRaw) == "function" and npc.GetRaw or npc.Get
	local ids = npc.GetAllIds() or {}
	ns.RunSliced("Map symbols: NPCs", #ids, function(i)
		local id = ids[i]
		local flags = npc.Get(id, "npcFlags")
		local flight, inn = HasFlag(flags, FLIGHT_MASTER_FLAG) and not bundledFlights, HasFlag(flags, INNKEEPER_FLAG)
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

local function BuildQuestStarts(lib, onDone)
	if questStarts or questStartsBuilding then
		return
	end
	local bundled = ns.QuestieDB.Bundled()
	local quest = bundled and bundled.Quest or lib.Quest
	if type(quest) ~= "table" or type(quest.GetAllIds) ~= "function" or type(quest.Get) ~= "function" then
		questStarts = {}
		return
	end
	questStartsBuilding = true
	local ids = quest.GetAllIds() or {}
	local found = {}
	ns.RunSliced("Map symbols: quest starts", #ids, function(i)
		local id = ids[i]
		local points = quest.Get(id, "startPoints")
		if type(points) == "table" then
			local entry = {
				id = id, gate = quest.Get(id, "startGate"),
				any = quest.Get(id, "startRequiresAny"), all = quest.Get(id, "startRequiresAll"),
				excluded = quest.Get(id, "startExcluded"), blockedBy = quest.Get(id, "startBlockedBy"),
				parent = quest.Get(id, "startParent"), name = quest.Get(id, "name"),
			}
			for _, point in ipairs(points) do
				if type(point) == "table" and type(point[1]) == "number"
					and type(point[2]) == "number" and type(point[3]) == "number" then
					local list = found[point[1]] or {}
					found[point[1]] = list
					-- Share metadata for every point of this quest. Copying all of
					-- these fields per point created thousands of table fields while
					-- opening the world map.
					list[#list + 1] = { x = point[2], y = point[3], data = entry }
				end
			end
		end
	end, function()
		questStarts, questStartsBuilding = found, false
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
Symbols.ForZones = ForZones

function Symbols.AddSource(source)
	sources[#sources + 1] = source
end

local function EntranceTooltip(tooltip, symbol)
	local showInfo = Options().placeInfo and ns.InstanceInfo
	for _, entry in ipairs(symbol.data.names) do
		tooltip:AddLine(entry[2] == "raid" and L.WORLDMAP_RAID:format(entry[1]) or entry[1], 1, 1, 1)
		-- A short text about the place (own texts, Data/PlaceInfo.lua).
		local info = showInfo and entry[3] and ns.InstanceInfo[entry[3]]
		if info then
			tooltip:AddLine(GetLocale() == "deDE" and info.de or info.en, 0.8, 0.8, 0.8, true)
		end
		-- How often this character went through and died in it (counted by ForeverPlus).
		local stats = entry[3] and ns:GetModule("InstanceStats")
		if stats then
			local runs, deaths = stats.Get(entry[3])
			if runs then
				tooltip:AddLine(L.INSTSTATS_LINE:format(runs, deaths), 0.6, 0.8, 1)
			end
		end
	end
	tooltip:AddLine(L.WORLDMAP_ENTRANCE, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
end

local function NpcTooltip(tooltip, symbol)
	tooltip:AddLine(symbol.data.name or symbol.fallback, 1, 1, 1)
	tooltip:AddLine(symbol.data.title or symbol.fallback, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	if symbol.data.node then
		tooltip:AddLine(symbol.data.node, 0.8, 0.8, 0.8)
	end
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

local function HasMaskBit(mask, bitValue)
	return type(mask) == "number" and mask > 0 and math.floor(mask / bitValue) % 2 == 1
end

local function CompletedOrActive(questID)
	return C_QuestLog.IsQuestFlaggedCompleted(questID) or C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

local function QuestStartAvailable(entry, lib)
	local quest = entry.data or entry
	if CompletedOrActive(quest.id) then
		return false
	end
	local gate = type(quest.gate) == "number" and quest.gate or 0
	local requiredLevel = math.floor(gate / 100000000000)
	if requiredLevel > 0 and UnitLevel("player") < requiredLevel then
		return false
	end
	local raceMask = math.floor((gate % 100000000) / 10000)
	local classMask = gate % 10000
	local _, _, classID = UnitClass("player")
	local _, _, raceID = UnitRace("player")
	local enum = lib.Enum
	local playerRaceMask = type(enum) == "table" and type(enum.raceMaskById) == "table" and enum.raceMaskById[raceID]
	if not playerRaceMask and raceID then playerRaceMask = 2 ^ (raceID - 1) end
	local playerClassMask = classID and 2 ^ (classID - 1)
	if raceMask ~= 0 and playerRaceMask and not HasMaskBit(raceMask, playerRaceMask) then
		return false
	end
	if classMask ~= 0 and playerClassMask and not HasMaskBit(classMask, playerClassMask) then
		return false
	end
	local anyFound, anyCompleted = false, false
	for _, id in ipairs(quest.any or {}) do
		anyFound = true
		if C_QuestLog.IsQuestFlaggedCompleted(id) then anyCompleted = true end
	end
	if anyFound and not anyCompleted then return false end
	for _, id in ipairs(quest.all or {}) do
		if not C_QuestLog.IsQuestFlaggedCompleted(id) then return false end
	end
	for _, id in ipairs(quest.excluded or {}) do
		if CompletedOrActive(id) then return false end
	end
	if quest.blockedBy and CompletedOrActive(quest.blockedBy) then return false end
	if quest.parent and not C_QuestLog.GetLogIndexForQuestID(quest.parent) then return false end
	return true
end

local function QuestStartTooltip(tooltip, symbol)
	local entry, lib = symbol.data, ns.QuestieDB.Get()
	local title = ns.QuestieDB.QuestName(lib, entry.id) or entry.name or ("Quest %d"):format(entry.id)
	tooltip:AddLine(title, 1, 1, 1, true)
	tooltip:AddLine(L.WORLDMAP_QUEST_START, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	tooltip:AddLine(L.WORLDMAP_QUEST_START_REQUIREMENTS, 0.8, 0.8, 0.8, true)
end

Symbols.AddSource(function(mapID, add)
	if not (Options().questStarts and questStarts) then
		return
	end
	local lib = ns.QuestieDB.Get()
	if not lib then return end
	local availability = {}
	ForZones(mapID, function(zoneMapID, toMap)
		for _, entry in ipairs(questStarts[zoneMapID] or {}) do
			local id = entry.data.id
			local isAvailable = availability[id]
			if isAvailable == nil then
				isAvailable = QuestStartAvailable(entry, lib)
				availability[id] = isAvailable
			end
			if isAvailable then
				local x, y = toMap(entry.x, entry.y)
				add(x, y, { kind = "questStart", atlas = "QuestNormal", size = 16, data = entry.data, tooltip = QuestStartTooltip })
			end
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
-- Besides QuestieDB's: the shipped list (Data/Inns.lua) and the inns the player
-- bound his hearthstone at (Modules/Innkeepers.lua), unless QuestieDB has them.
Symbols.AddSource(function(mapID, add)
	if not (Options().inns and npcs) or IsContinent(mapID) then
		return
	end
	local known = {}
	for _, inn in ipairs(npcs.inns[mapID] or {}) do
		known[inn.id or 0] = true
		add(inn.x / 100, inn.y / 100, { kind = "inn", atlas = "innkeeper", size = INN_SIZE, data = inn, fallback = L.WORLDMAP_INN, tooltip = NpcTooltip })
	end
	local faction = UnitFactionGroup("player")
	local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	local function AddKnown(id, map, x, y, team, name)
		if map == mapID and not known[id] and (team == "N" or team == letter) then
			known[id] = true
			add(x / 100, y / 100, { kind = "inn", atlas = "innkeeper", size = INN_SIZE, fallback = L.WORLDMAP_INN, tooltip = NpcTooltip,
				data = { id = id, x = x, y = y, name = name, faction = team == "N" and "AH" or team } })
		end
	end
	for id, inn in pairs(ns.db.innkeepers or {}) do
		AddKnown(id, inn[2], inn[3], inn[4], inn[5], inn[1])
	end
	for _, inn in ipairs(ns.InnData or {}) do
		AddKnown(inn[1], inn[2], inn[3], inn[4], inn[5], inn[6])
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
			-- Hovering the name shows a short text about the place (Data/PlaceInfo.lua, own texts).
			local info = Options().placeInfo and ns.PlaceInfo and ns.PlaceInfo[place[4]]
			local text = info and (GetLocale() == "deDE" and info.de or info.en)
			local name = PlaceName(place)
			add(position[1], position[2], { kind = "place", label = name,
				font = city and "GameFontNormalOutline" or "GameFontHighlightSmallOutline",
				tooltip = text and function(tooltip)
					tooltip:AddLine(name, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
					tooltip:AddLine(text, 1, 1, 1, true)
				end or nil })
		end
	end
end)

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function OnEnter(frame)
	local tooltip = frame.symbol.tooltip
	local movable = frame.offsetKey and Options().labelsMovable
	if not (tooltip or movable) then
		return
	end
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	if tooltip then
		tooltip(GameTooltip, frame.symbol)
	else
		GameTooltip_SetTitle(GameTooltip, frame.symbol.label)
	end
	if movable then
		GameTooltip_AddInstructionLine(GameTooltip, L.WORLDMAP_LABEL_DRAG)
	end
	GameTooltip:Show()
end

local function OnMouseUp(frame, button)
	if frame.symbol.click then
		frame.symbol.click(frame.symbol, button)
	end
end

-- Names can be dragged while "movable" is on (WorldMap option); the place is kept per map and name.
local function DragUpdate(frame)
	local drag = frame.drag
	local canvas = WorldMapFrame:GetCanvas()
	local scale, width, height = ns.Number(canvas:GetEffectiveScale(), 0), canvas:GetWidth(), canvas:GetHeight()
	if not drag or scale <= 0 or width <= 0 or height <= 0 then
		return
	end
	local cx, cy = GetCursorPosition()
	frame.ox = drag.ox + (cx - drag.cx) / scale / width
	frame.oy = drag.oy - (cy - drag.cy) / scale / height
	PositionOne(frame)
end

local function DragStart(frame)
	if not (frame.offsetKey and Options().labelsMovable) then
		return
	end
	local cx, cy = GetCursorPosition()
	frame.drag = { cx = cx, cy = cy, ox = ns.Number(frame.ox, 0), oy = ns.Number(frame.oy, 0) }
	GameTooltip:Hide()
	ns.SetUpdate(frame, "Map names: drag", DragUpdate)
end

local function DragStop(frame)
	ns.SetUpdate(frame, "Map names: drag", nil)
	if not frame.drag then
		return
	end
	frame.drag = nil
	local db = Options()
	db.labelOffsets = db.labelOffsets or {}
	local ox, oy = ns.Number(frame.ox, 0), ns.Number(frame.oy, 0)
	if math.abs(ox) < 0.0005 and math.abs(oy) < 0.0005 then
		db.labelOffsets[frame.offsetKey] = nil
	else
		db.labelOffsets[frame.offsetKey] = { math.floor(ox * 10000 + 0.5) / 10000, math.floor(oy * 10000 + 0.5) / 10000 }
	end
end

-- All moved names back to their places.
function Symbols.ResetNames()
	Options().labelOffsets = {}
	Symbols.Refresh()
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
		frame:SetScript("OnDragStart", DragStart)
		frame:SetScript("OnDragStop", DragStop)
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
		-- Names have their own size and lie behind all symbols (they would cover everything else).
		local scale = (Options().labelScale or 100) / 100
		frame:SetFrameLevel(layer:GetFrameLevel())
		frame.Label:SetScale(scale)
		frame:SetSize(frame.Label:GetStringWidth() * scale, frame.Label:GetStringHeight() * scale)
		-- A name with a text shows it on hover; clicks still reach the map, except while the names are movable.
		local db = Options()
		local movable = db.labelsMovable and true or false
		frame.offsetKey = tostring(currentMap) .. ":" .. symbol.label
		local offset = db.labelOffsets and db.labelOffsets[frame.offsetKey]
		frame.ox, frame.oy = offset and ns.Number(offset[1]), offset and ns.Number(offset[2])
		frame:EnableMouse(movable or symbol.tooltip ~= nil)
		frame:SetMouseClickEnabled(movable)
		if movable then
			frame:RegisterForDrag("LeftButton")
		else
			frame:RegisterForDrag()
		end
		return
	end
	frame.offsetKey, frame.ox, frame.oy = nil, nil, nil
	frame:RegisterForDrag()
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
	local size = symbol.size * (Options().symbolScale or 100) / 100
	frame:SetFrameLevel(layer:GetFrameLevel() + 2)
	frame:SetSize(size, size)
	-- Hover shows the tooltip; clicks go on to the map unless the symbol
	-- has its own.
	frame:EnableMouse(symbol.tooltip ~= nil)
	frame:SetMouseClickEnabled(symbol.click ~= nil)
end

-- Position in the canvas; the symbols keep their size while zooming. Names can be moved by the player
-- (offset in parts of the canvas, so it stays with the name while zooming).
function PositionOne(frame, canvas, scale)
	canvas = canvas or WorldMapFrame:GetCanvas()
	scale = scale or 1 / ns.Number(WorldMapFrame:GetCanvasScale(), 1)
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", canvas, "TOPLEFT", width * (frame.x + ns.Number(frame.ox, 0)) / scale, -height * (frame.y + ns.Number(frame.oy, 0)) / scale)
end

local function Position()
	if used == 0 then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	local scale = 1 / ns.Number(WorldMapFrame:GetCanvasScale(), 1)
	for i = 1, used do
		PositionOne(frames[i], canvas, scale)
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
	currentMap = mapID
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
	local lib = (db.entrances or db.flightPoints or db.inns or db.questStarts) and ns.QuestieDB.Get()
	if db.entrances and not entrances then
		BuildEntrances(lib)
	end
	if db.flightPoints or db.inns then
		BuildNpcs(lib, Draw)
	end
	if lib and db.questStarts then
		BuildQuestStarts(lib, Draw)
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
	local events = CreateFrame("Frame")
	events:RegisterEvent("QUEST_LOG_UPDATE")
	events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
	-- The quest log changes in bursts: one refresh after the last change, not one per event.
	local queued = false
	events:SetScript("OnEvent", ns.Measured("Map symbols: quest event", function()
		if queued or not WorldMapFrame:IsShown() then
			return
		end
		queued = true
		C_Timer.After(0.4, function()
			queued = false
			if WorldMapFrame:IsShown() then
				Symbols.Refresh()
			end
		end)
	end))
end

-- Number of symbols per kind on a map, for /fp karte.
function Symbols.Count(mapID)
	local counts = {}
	for _, symbol in ipairs(Collect(mapID)) do
		counts[symbol.kind] = (counts[symbol.kind] or 0) + 1
	end
	return counts
end

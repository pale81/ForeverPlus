-- ForeverPlus ships a compact, generated dataset. QuestieDB remains an
-- optional richer provider when installed; it is never required at runtime.
local _, ns = ...

local QDB = {}
ns.QuestieDB = QDB

local MAX_CHAIN_STEPS = 200 -- quests visited per chain search

local function HasFunctions(tbl, ...)
	if type(tbl) ~= "table" then
		return false
	end
	for i = 1, select("#", ...) do
		if type(tbl[select(i, ...)]) ~= "function" then
			return false
		end
	end
	return true
end

-- Names come in English until a locale is chosen; another QuestieDB user
-- (Questie) may already have chosen one, which is kept.
local localeChecked

local function EnsureLocale(lib)
	localeChecked = true
	local l10n = lib.l10n
	local locale = GetLocale()
	if type(l10n) == "table" and type(l10n.SetLocale) == "function" and locale ~= "enUS"
		and (l10n.currentLocale == nil or l10n.currentLocale == "enUS") then
		pcall(l10n.SetLocale, locale)
	end
end

-- QuestieDB draws its own notice on the screen in source mode (source code
-- instead of a release package); ForeverPlus only mentions it in its README.
local function HideModeIndicator(lib)
	local indicator = lib.ModeIndicator
	if type(indicator) == "table" and type(indicator.Hide) == "function" then
		pcall(indicator.Hide)
	end
end

-- The library, if QuestieDB is loaded and offers the functions used here.
function QDB.Get()
	local lib = _G.LibQuestieDB
	if type(lib) == "table" and HasFunctions(lib.Quest, "Get", "GetAll", "GetAllIds", "Exists")
		and HasFunctions(lib.Support, "Get") then
		if not localeChecked then
			EnsureLocale(lib)
			HideModeIndicator(lib)
		end
		return lib
	end
	local bundled = ns.BundledDatabaseAPI
	if type(bundled) == "table" and HasFunctions(bundled.Quest, "Get", "GetAll", "GetAllIds", "Exists")
		and HasFunctions(bundled.Support, "Get") then
		return bundled
	end
end

-- Data that ForeverPlus ships itself (custom waypoint and availability fields)
-- must remain available even when an external QuestieDB provider is preferred.
function QDB.Bundled()
	return type(ns.BundledDatabaseAPI) == "table" and ns.BundledDatabaseAPI or nil
end

-- Quest name in the client's language where the client knows the quest,
-- otherwise QuestieDB's name.
function QDB.QuestName(lib, questID)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if type(title) == "string" and not (issecretvalue and issecretvalue(title)) and title ~= "" then
		return title
	end
	return lib and lib.Quest.Get(questID, "name")
end

-- Contract check of QuestieDB (true when the provider guarantees `version`).
function QDB.HasContract(lib, version)
	if type(lib.RequireContract) ~= "function" then
		return false
	end
	local ok, result = pcall(lib.RequireContract, version)
	return ok and result and true or false
end

---------------------------------------------------------------------------
-- QuestieDB's areas (zone IDs of the spawn lists) to the client's map IDs.
-- Loaded on first use; QuestieDB may hand the tables over as source text.
---------------------------------------------------------------------------
local areaToUiMap

local function LoadAreaMap(lib)
	areaToUiMap = {}
	local ok, zoneDB = pcall(lib.Support.Get, "ZoneDB")
	local private = ok and type(zoneDB) == "table" and zoneDB.private
	if type(private) ~= "table" then
		return
	end
	for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
		local source = private[key]
		if type(source) == "string" then
			local chunk = loadstring(source)
			local success, map = pcall(chunk or error)
			source = success and map or nil
		end
		if type(source) == "table" then
			for areaID, uiMapID in pairs(source) do
				areaToUiMap[areaID] = uiMapID
			end
		end
	end
end

-- Map ID of a QuestieDB area, nil when the client has no map for it.
function QDB.UiMapForArea(lib, areaID)
	if not areaToUiMap then
		LoadAreaMap(lib)
	end
	local uiMapID = areaToUiMap[areaID]
	return type(uiMapID) == "number" and uiMapID > 0 and uiMapID or nil
end

-- Spawn points of a QuestieDB spawn list ({ [areaID] = { { x, y }, … } },
-- 0–100 per zone map) by map: { [uiMapID] = { { x, y }, … } }. Points
-- without a position on the map (instances: -1) are left out.
function QDB.SpawnsByMap(lib, spawns, into)
	into = into or {}
	if type(spawns) ~= "table" then
		return into
	end
	for areaID, points in pairs(spawns) do
		local uiMapID = QDB.UiMapForArea(lib, areaID)
		if uiMapID and type(points) == "table" then
			local list = into[uiMapID]
			for _, point in ipairs(points) do
				local x, y = point[1], point[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
					if not list then
						list = {}
						into[uiMapID] = list
					end
					list[#list + 1] = { x, y }
				end
			end
		end
	end
	return into
end

---------------------------------------------------------------------------
-- Dungeon and raid quests: the quest's zone (zoneOrSort) is the area of an
-- instance in QuestieDB's dungeon table (including alternative area IDs).
---------------------------------------------------------------------------
local dungeonAreas

local function DungeonAreas(lib)
	if dungeonAreas == nil then
		dungeonAreas = false
		local ok, zoneDB = pcall(lib.Support.Get, "ZoneDB")
		local dungeons = ok and type(zoneDB) == "table" and zoneDB.private and zoneDB.private.dungeons
		if type(dungeons) == "table" then
			dungeonAreas = {}
			for areaID, entry in pairs(dungeons) do
				dungeonAreas[areaID] = true
				if type(entry) == "table" and type(entry[2]) == "table" then
					for _, alternative in ipairs(entry[2]) do
						dungeonAreas[alternative] = true
					end
				end
			end
		end
	end
	return dungeonAreas or nil
end

-- true/false, or nil when QuestieDB is missing or does not know the quest.
function QDB.IsDungeonQuest(questID)
	local lib = QDB.Get()
	local areas = lib and DungeonAreas(lib)
	if not areas or not lib.Quest.Exists(questID) then
		return nil
	end
	local zone = lib.Quest.Get(questID, "zoneOrSort")
	if type(zone) ~= "number" then
		return nil -- partial waypoint-only rows do not establish dungeon membership
	end
	return zone > 0 and areas[zone] or false
end

---------------------------------------------------------------------------
-- Quest chains: which quests a quest opens (follow-up, quests requiring it,
-- breadcrumb target). Built once in the background, a batch per frame.
---------------------------------------------------------------------------
local followers -- questID -> { questIDs that need it or follow it }
local building
local waiting = {}
local leadsCache = {}

local function Add(map, from, to)
	if type(from) ~= "number" or from <= 0 or type(to) ~= "number" or to <= 0 then
		return
	end
	local list = map[from]
	if not list then
		list = {}
		map[from] = list
	end
	list[#list + 1] = to
end

local function AddList(map, list, to)
	if type(list) == "table" then
		for _, from in ipairs(list) do
			Add(map, from, to)
		end
	end
end

-- Calls onDone once the index exists (right away if it already does).
function QDB.BuildChains(onDone)
	if followers then
		if onDone then
			onDone()
		end
		return
	end
	if onDone then
		waiting[#waiting + 1] = onDone
	end
	local lib = QDB.Get()
	if building or not lib then
		return
	end
	building = true
	local ids = lib.Quest.GetAllIds() or {}
	local map = {}
	local keys = { "preQuestSingle", "preQuestGroup", "nextQuestInChain", "breadcrumbForQuestId" }
	ns.RunSliced("QuestieDB: quest chains", #ids, function(i)
		local id = ids[i]
		local values = lib.Quest.GetAll(id, keys)
		if values then
			AddList(map, values[1], id)
			AddList(map, values[2], id)
			Add(map, id, values[3])
			Add(map, id, values[4])
		end
	end, function()
		followers, building = map, false
		wipe(leadsCache)
		local callbacks = waiting
		waiting = {}
		for _, callback in ipairs(callbacks) do
			callback()
		end
	end)
end

-- true when the quest leads (directly or over a chain) to a dungeon or raid
-- quest; nil while QuestieDB or the chain index is not available.
function QDB.LeadsToDungeon(questID)
	if not followers then
		return nil
	end
	local cached = leadsCache[questID]
	if cached ~= nil then
		return cached
	end
	local result = false
	local seen, queue, head = { [questID] = true }, { questID }, 1
	while queue[head] and head <= MAX_CHAIN_STEPS and not result do
		for _, nextID in ipairs(followers[queue[head]] or {}) do
			if not seen[nextID] then
				seen[nextID] = true
				if QDB.IsDungeonQuest(nextID) then
					result = true
					break
				end
				queue[#queue + 1] = nextID
			end
		end
		head = head + 1
	end
	leadsCache[questID] = result
	return result
end

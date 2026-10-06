-- Optional runtime access to QuestieDB, a separate data addon with a public
-- interface for other addons (LibQuestieDB). Nothing is copied; without
-- QuestieDB every lookup answers nil and the callers keep their own logic.
local _, ns = ...

local QDB = {}
ns.QuestieDB = QDB

local MAX_CHAIN_STEPS = 200 -- quests visited per chain search
local BUILD_BATCH = 400     -- quests read per frame while building the index

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

-- The library, if QuestieDB is loaded and offers the functions used here.
function QDB.Get()
	local lib = _G.LibQuestieDB
	if type(lib) == "table" and HasFunctions(lib.Quest, "Get", "GetAll", "GetAllIds", "Exists")
		and HasFunctions(lib.Support, "Get") then
		return lib
	end
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
	return type(zone) == "number" and zone > 0 and areas[zone] or false
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
	local map, index = {}, 1
	C_Timer.NewTicker(0, function(ticker)
		local last = math.min(index + BUILD_BATCH - 1, #ids)
		for i = index, last do
			local id = ids[i]
			local values = lib.Quest.GetAll(id, { "preQuestSingle", "preQuestGroup", "nextQuestInChain", "breadcrumbForQuestId" })
			if values then
				AddList(map, values[1], id)
				AddList(map, values[2], id)
				Add(map, id, values[3])
				Add(map, id, values[4])
			end
		end
		index = last + 1
		if index > #ids then
			ticker:Cancel()
			followers, building = map, false
			wipe(leadsCache)
			local callbacks = waiting
			waiting = {}
			for _, callback in ipairs(callbacks) do
				callback()
			end
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

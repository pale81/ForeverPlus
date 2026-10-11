-- Build a LibQuestieDB mock from the real Forever raw data.
-- Path to a QuestieDB checkout (https://github.com/Questie/QuestieDB), with trailing slash.
local root = os.getenv("QUESTIEDB") or "../../QuestieDB/"
local mods = {}
local function mod(n) mods[n] = mods[n] or { private = {} } return mods[n] end
QuestieLoader = { ImportModule = function(_, n) return mod(n) end, CreateModule = function(_, n) return mod(n) end }
local function load(path) local chunk = assert(loadfile(root .. path)); chunk() end
load("data/Forever/foreverItemDB.lua"); load("data/Forever/foreverNpcDB.lua"); load("data/Forever/foreverQuestDB.lua")
load("support/Forever/Zones/areaIdToUiMapId.lua")
local QDB = mod("QuestieDB")
local items = assert(loadstring(QDB.itemData))()
local npcs = assert(loadstring(QDB.npcData))()
local quests = assert(loadstring(QDB.questData))()
local ik, nk = QDB.itemKeys, QDB.npcKeys
local ids = {} for id in pairs(items) do ids[#ids + 1] = id end table.sort(ids)
local function getter(tbl, key) return function(id) local r = tbl[id]; return r and r[key] end end
LibQuestieDB = {
	RequireContract = function() return true end,
	Item = { GetAllIds = function() return ids end, class = function(id) return items[id][ik.class] or 0 end,
		subClass = function(id) return items[id][ik.subClass] or 0 end, vendors = getter(items, ik.vendors),
		npcDrops = getter(items, ik.npcDrops), questRewards = getter(items, ik.questRewards), name = getter(items, ik.name) },
	Npc = { spawns = getter(npcs, nk.spawns), friendlyToFaction = getter(npcs, nk.friendlyToFaction),
		name = getter(npcs, nk.name), subName = getter(npcs, nk.subName) },
	Quest = { name = function(id) return quests[id] and quests[id][1] end },
	Support = { Get = function(n) return mod(n) end },
}
-- Canonical reads: Entity.Get(id, key), as the public API offers them.
local qk = QDB.questKeys
local function GetFrom(tbl, keys, defaults)
	return function(id, key)
		local row = tbl[id]
		local value = row and row[keys[key] or key]
		if value == nil and defaults then
			value = defaults[key]
		end
		return value
	end
end
LibQuestieDB.Item.Get = GetFrom(items, ik, { class = 0, subClass = 0 })
LibQuestieDB.Npc.Get = GetFrom(npcs, nk)
LibQuestieDB.Quest.Get = GetFrom(quests, qk)
LibQuestieDB.Quest.GetAll = function(id, keys) local r = {} for i, k in ipairs(keys) do r[i] = LibQuestieDB.Quest.Get(id, k) end return r end
LibQuestieDB.Quest.GetAllIds = function() local r = {} for id in pairs(quests) do r[#r + 1] = id end return r end
LibQuestieDB.Quest.Exists = function(id) return quests[id] ~= nil end

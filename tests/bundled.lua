-- ForeverPlus's own data: loads the shipped quest tables without a QuestieDB addon.
local root = (arg and arg[1]) or ".."
local ns = {}
assert(loadfile(root .. "/Data/Database.lua"))("ForeverPlus", ns)
assert(loadfile(root .. "/Data/DatabaseLoader.lua"))("ForeverPlus", ns)
assert(loadfile(root .. "/Core/QuestieDB.lua"))("ForeverPlus", ns)
local saved = LibQuestieDB
LibQuestieDB = nil
assert(ns.QuestieDB.Get() == ns.BundledDatabaseAPI, "the adapter falls back to the shipped data without QuestieDB")
local quest = ns.BundledDatabaseAPI.Quest
assert(quest.Exists(2), "quest row with waypoints")
local point = quest.Get(2, "previewPoint")
point = point and point[1]
assert(type(point) == "table" and type(point[1]) == "number" and type(point[2]) == "number" and type(point[3]) == "number",
	"a waypoint is { map, x, y }")
assert(ns.QuestieDB.Bundled() == ns.BundledDatabaseAPI, "bundled-only fields stay reachable")
assert(not quest.Exists(99999999), "unknown quests stay unknown")
assert(not ns.BundledDatabaseAPI.Npc.Exists(523), "no NPC facts are shipped")
assert(ns.BundledDatabase.meta.counts.Quest == #quest.GetAllIds(), "meta count matches the rows")
LibQuestieDB = saved
print("bundled data OK: " .. #quest.GetAllIds() .. " quests")

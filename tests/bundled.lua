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
-- Plainstrider Menace in the Barrens, as recorded in the three pinned source tables.
local function CheckPoint(field, x, y)
	local point = quest.Get(844, field)[1]
	assert(point[1] == 1413 and point[2] == x and point[3] == y, field .. " must use zone percentages")
end
CheckPoint("startPoints", 52.23, 31.01)
CheckPoint("previewPoint", 51.38, 28.01)
CheckPoint("turnInPoint", 52.23, 31.01)
assert(ns.QuestieDB.Bundled() == ns.BundledDatabaseAPI, "bundled-only fields stay reachable")
assert(not quest.Exists(99999999), "unknown quests stay unknown")
assert(not ns.BundledDatabaseAPI.Npc.Exists(523), "no NPC facts are shipped")
assert(ns.BundledDatabase.meta.counts.Quest == #quest.GetAllIds(), "meta count matches the rows")
LibQuestieDB = saved
print("bundled data OK: " .. #quest.GetAllIds() .. " quests")

-- Structural validation for the generated artifact; invoke with Lua 5.1.
local root = assert(arg[1], "usage: lua5.1 validate_database.lua <addon-root>")
local ns = {}
assert(loadfile(root .. "/Data/Database.lua"))("ForeverPlus", ns)
local data = assert(ns.BundledDatabase, "generated database was not loaded")
assert(data.meta and data.meta.schema == 1, "unsupported/missing database schema")
assert(data.meta.sourceRevision and data.meta.clientBuild, "source provenance is incomplete")
-- Quest tables only, or with the optional AHledger item catalog (--items).
local withItems = data.meta.source == "AHledger public catalog API; Everything Quests MIT quest tables"
assert(withItems or data.meta.source == "Everything Quests MIT quest tables", "unexpected or unapproved data source")
assert(data.meta.trust == (withItems and "AHledger item catalog; " or "") .. "MIT quest waypoint and availability tables; no NPC/object spawn facts",
	"unexpected trust classification")
assert(type(data.meta.license) == "string" and data.meta.license:find("Everything Quests MIT", 1, true)
	and (not withItems or data.meta.license:find("AHledger API terms", 1, true)), "data permission metadata is missing")
assert(type(data.meta.apiResponseSha256) == "table", "API response hashes are missing")
assert(data.meta.questSourceCommit == "bb29c7326185377d05381a0a7c6817e4d3f1e883", "quest source is not the reviewed commit")
assert(type(data.meta.questSourceSha256) == "table", "quest source hashes are missing")

local entities = assert(data.entities)
local total = 0
for _, kind in ipairs({ "Quest", "Npc", "Item", "Object" }) do
	local entity = assert(entities[kind], "missing entity " .. kind)
	local previous, idSet = 0, {}
	for _, id in ipairs(entity.ids) do
		assert(type(id) == "number" and id > 0 and id % 1 == 0, kind .. " has a bad id")
		assert(id > previous, kind .. " ids are duplicate or unsorted: " .. id)
		assert(type(entity.rows[id]) == "table", kind .. " has no row for id " .. id)
		idSet[id] = true
		previous = id
	end
	for id, row in pairs(entity.rows) do
		assert(idSet[id], kind .. " row missing from id list: " .. tostring(id))
		assert(#row <= #entity.fields, kind .. " row exceeds field schema: " .. id)
	end
	assert(#entity.ids == data.meta.counts[kind], kind .. " count differs from provenance metadata")
	total = total + #entity.ids
end
assert(#entities.Quest.ids > 0 and #entities.Npc.ids == 0 and #entities.Object.ids == 0,
	"only quest points and availability metadata may be bundled")
assert(withItems == (#entities.Item.ids > 0), "item catalog and source metadata disagree")
local questIndexes = {}
for index, field in ipairs(entities.Quest.fields) do questIndexes[field] = index end
for _, id in ipairs(entities.Quest.ids) do
	local row = entities.Quest.rows[id]
	for _, field in ipairs({ "previewPoint", "turnInPoint", "startPoints" }) do
		local points = row[questIndexes[field]]
		if points ~= nil then
			assert(type(points) == "table" and #points > 0, "invalid " .. field .. " for quest " .. id)
			for _, point in ipairs(points) do
				assert(type(point) == "table" and #point == 3, "invalid point in " .. field .. " for quest " .. id)
				assert(type(point[1]) == "number" and point[1] > 0, "invalid map ID for quest " .. id)
				assert(type(point[2]) == "number" and point[2] >= 0 and point[2] <= 100, "invalid x for quest " .. id)
				assert(type(point[3]) == "number" and point[3] >= 0 and point[3] <= 100, "invalid y for quest " .. id)
			end
		end
	end
end

local function exists(kind, id)
	return type(id) == "number" and id > 0 and entities[kind].rows[id] ~= nil
end
local function checkValue(owner, kind, field, value)
	if type(value) == "number" then
		assert(exists(kind, value), owner .. "." .. field .. " references missing " .. kind .. " " .. value)
	elseif type(value) == "table" then
		for _, id in pairs(value) do
			if type(id) == "number" then
				assert(exists(kind, id), owner .. "." .. field .. " references missing " .. kind .. " " .. id)
			end
		end
	end
end
local relationFields = {
	Quest = { preQuestSingle = "Quest", preQuestGroup = "Quest", nextQuestInChain = "Quest", breadcrumbForQuestId = "Quest" },
	Npc = { questStarts = "Quest", questEnds = "Quest" },
	Item = { startQuest = "Quest" },
	Object = { questStarts = "Quest", questEnds = "Quest" },
}
for ownerKind, fields in pairs(relationFields) do
	local entity = entities[ownerKind]
	local indexes = {}
	for index, field in ipairs(entity.fields) do indexes[field] = index end
	for _, id in ipairs(entity.ids) do
		local row = entity.rows[id]
		for field, targetKind in pairs(fields) do
			local value = row[indexes[field]]
			if value ~= nil then checkValue(ownerKind .. " " .. id, targetKind, field, value) end
		end
	end
end

io.write(("Database structure OK: %d catalog items and %d quest point/availability rows; no bundled NPC/object facts; source %s, client %s.\n")
	:format(#entities.Item.ids, #entities.Quest.ids, data.meta.sourceRevision, data.meta.clientBuild))

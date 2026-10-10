-- Public lookup surface over ForeverPlus's bundled data file.
local _, ns = ...

local source = ns.BundledDatabase
if type(source) ~= "table" then
	ns.BundledDatabaseAPI = nil
	return
end

local function Entity(kind)
	local payload = source.entities and source.entities[kind]
	if type(payload) ~= "table" then return nil end
	local fieldIndexes = {}
	for index, name in ipairs(payload.fields or {}) do
		fieldIndexes[name] = index
	end
	local entity = {}
	function entity.Get(id, field)
		local row = payload.rows[id]
		local index = fieldIndexes[field]
		if not row or not index then return nil end
		return row[index]
	end
	function entity.GetAll(id, fields)
		local row, result = payload.rows[id], { n = #fields }
		if not row then return nil end
		for index, field in ipairs(fields) do
			local fieldIndex = fieldIndexes[field]
			if fieldIndex then result[index] = row[fieldIndex] end
		end
		return result
	end
	function entity.Exists(id)
		return payload.rows[id] ~= nil
	end
	function entity.GetAllIds()
		return payload.ids
	end
	-- Some consumers use this only as a compatibility optimization.
	entity.GetRaw = entity.Get
	return entity
end

local entities = {}
for _, kind in ipairs({ "Quest", "Npc", "Item", "Object" }) do
	entities[kind] = Entity(kind)
end

local support = {
	Get = function(name)
		if name == "ZoneDB" then return source.zone end
	end,
}

local database = {
	Item = entities.Item,
	Npc = entities.Npc,
	Quest = entities.Quest,
	Object = entities.Object,
	Support = support,
	Enum = source.enum,
	version = 3,
	meta = source.meta,
	GetDataSource = function() return "foreverplus" end,
	RequireContract = function(contract) return type(contract) == "number" and contract <= 3 end,
}

ns.BundledDatabaseAPI = database

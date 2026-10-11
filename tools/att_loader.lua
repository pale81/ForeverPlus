-- Loader for the compiled Forever categories of AllTheThings (db/Camelot/Categories):
-- load(attDir) returns the root nodes { kind, id, t = fields }; children are in t.g
-- or in the array part of t.
local loader = {}

local function Read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return (text:gsub("^\239\187\191", ""))
end

local function Node(kind)
	return function(id, t)
		return { kind = kind, id = id, t = type(t) == "table" and t or {} }
	end
end

function loader.load(att, files)
	local env = {}
	for _, name in ipairs({ "CreateAchievement", "CreateHeader", "CreateAchievementCriteria", "CreateCurrencyClass",
		"CreateExploration", "CreateFaction", "CreateFilter", "CreateFlightPath", "CreateCustomHeader", "CreateItem",
		"CreateMap", "CreateMount", "CreateNPC", "CreateObject", "CreateSpecies", "CreateProfession", "CreateQuest",
		"CreateQuestObjective", "CreateRecipe", "CreateItemSource", "CreateInstance", "CreateEncounter",
		"CreateCharacterClass", "CreateToy", "CreateExpansion" }) do
		env[name] = Node(name)
	end
	local Any
	Any = function()
		return setmetatable({}, { __call = function() return Any() end, __index = function() return Any() end, __newindex = function() end })
	end
	local handler
	env.AddEventHandler = function(_, fn) handler = fn end
	setmetatable(env, { __index = function() return Any() end })
	local roots = {}
	for _, file in ipairs(files) do
		local chunk = assert(loadstring(Read(att .. "/db/Camelot/Categories/" .. file .. ".lua"), file))
		local categories = {}
		chunk("ATT", env)
		handler(categories)
		for _, root in pairs(categories) do
			roots[#roots + 1] = root
		end
	end
	return roots
end

function loader.children(node)
	local list = {}
	for _, child in ipairs(node.t.g or node.t) do list[#list + 1] = child end
	if node.t.g then
		for _, child in ipairs(node.t) do list[#list + 1] = child end
	end
	return list
end

return loader

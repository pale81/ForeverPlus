-- Talent plans by name: a list of plans { id =, name =, ranks = { [talent] = rank }, order = { talent, … } }.
-- Pure table work without the game's API.
local _, ns = ...

local Builds = {}
ns.TalentBuilds = Builds

-- "nodeID:rank,…" (how templates were stored) as a table talent -> rank.
function Builds.ParseRanks(text)
	local ranks = {}
	for nodeText, rankText in tostring(text or ""):gmatch("(%d+):(%d+)") do
		ranks[tonumber(nodeText)] = tonumber(rankText)
	end
	return ranks
end

-- A name no other plan of the list has: "Name", then "Name (2)", "Name (3)" …
function Builds.UniqueName(list, name, except)
	local function Taken(candidate)
		for _, build in ipairs(list) do
			if build ~= except and build.name == candidate then
				return true
			end
		end
		return false
	end
	local candidate, number = name, 1
	while Taken(candidate) do
		number = number + 1
		candidate = ("%s (%d)"):format(name, number)
	end
	return candidate
end

-- Adds a plan; counter.buildSeq gives every plan a number of its own that survives renaming and deleting.
function Builds.Add(list, counter, name, ranks, order)
	counter.buildSeq = (tonumber(counter.buildSeq) or 0) + 1
	local build = { id = counter.buildSeq, name = Builds.UniqueName(list, name), ranks = ranks or {}, order = order or {} }
	list[#list + 1] = build
	return build
end

function Builds.Find(list, id)
	for index, build in ipairs(list) do
		if build.id == id then
			return build, index
		end
	end
	return nil
end

function Builds.Remove(list, id)
	local _, index = Builds.Find(list, id)
	if index then
		table.remove(list, index)
		return true
	end
	return false
end

function Builds.Points(build)
	local points = 0
	for _, rank in pairs(build.ranks) do
		points = points + rank
	end
	return points
end

-- What was stored before there were plans by name: the one plan (with its order) becomes the first plan of the
-- list, the own templates follow as plans. Nothing is added for an empty plan or without templates.
function Builds.Migrate(list, counter, plan, order, templates, planName)
	if type(plan) == "table" and next(plan) ~= nil then
		Builds.Add(list, counter, planName, plan, type(order) == "table" and order or {})
	end
	for _, template in ipairs(type(templates) == "table" and templates or {}) do
		if type(template) == "table" then
			local ranks = Builds.ParseRanks(template.ranks)
			if next(ranks) ~= nil then
				Builds.Add(list, counter, tostring(template.name or planName), ranks, {})
			end
		end
	end
	return list
end

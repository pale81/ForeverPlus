-- Talent plan order: the planned points as a list of steps (one talent per point, in the order they are to be
-- learned). Pure list work without the game's API; the rules of the trees come in as a function.
local _, ns = ...

local Order = {}
ns.TalentOrder = Order

-- Brings the steps in line with what is still to learn (wanted: talent -> points). Of a talent with too many
-- steps the earliest go (those points are learned). Returns the kept steps and, per talent, the points that
-- have no step yet.
function Order.Reconcile(steps, wanted)
	local have = {}
	for _, id in ipairs(steps) do
		have[id] = (have[id] or 0) + 1
	end
	local kept = {}
	for _, id in ipairs(steps) do
		if have[id] > (wanted[id] or 0) then
			have[id] = have[id] - 1
		else
			kept[#kept + 1] = id
		end
	end
	local missing = {}
	for id, count in pairs(wanted) do
		if count > (have[id] or 0) then
			missing[id] = count - (have[id] or 0)
		end
	end
	return kept, missing
end

-- Takes the last step of a talent out of the list (a planned rank taken back).
function Order.RemoveLast(steps, id)
	for index = #steps, 1, -1 do
		if steps[index] == id then
			table.remove(steps, index)
			return true
		end
	end
	return false
end

-- Puts the steps into an order the rules allow, changing as little as possible: always the first remaining
-- step that may be learned now. allowed(id, ranks) says whether the talent may take one more rank; ranks
-- (talent -> rank, starting with what is learned) is counted up here. Steps no order can reach stay at the end.
function Order.Repair(steps, allowed, ranks)
	local rest, result = {}, {}
	for index, id in ipairs(steps) do
		rest[index] = id
	end
	while #rest > 0 do
		local found
		for index, id in ipairs(rest) do
			if allowed(id, ranks) then
				found = index
				break
			end
		end
		if not found then
			for _, id in ipairs(rest) do
				result[#result + 1] = id
			end
			break
		end
		local id = table.remove(rest, found)
		ranks[id] = (ranks[id] or 0) + 1
		result[#result + 1] = id
	end
	return result
end

-- Per talent the levels of its steps as text, "14–16" or "14–16, 29" when other talents come in between.
-- firstLevel is the level of the first step.
function Order.LevelTexts(steps, firstLevel)
	local runs = {}
	for index, id in ipairs(steps) do
		local level = firstLevel + index - 1
		local list = runs[id]
		if not list then
			list = {}
			runs[id] = list
		end
		local last = list[#list]
		if last and last[2] == level - 1 then
			last[2] = level
		else
			list[#list + 1] = { level, level }
		end
	end
	local texts = {}
	for id, list in pairs(runs) do
		local parts = {}
		for _, run in ipairs(list) do
			parts[#parts + 1] = run[1] == run[2] and tostring(run[1]) or (run[1] .. "–" .. run[2])
		end
		texts[id] = table.concat(parts, ", ")
	end
	return texts
end

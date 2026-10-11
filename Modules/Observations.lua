-- Observations: what the client cannot list, recorded while playing (nothing is
-- sent; /fp daten export shows it as text to pass on):
--   * which quests an NPC offers and takes back, with where he stands,
--   * where the player stood when a quest objective count went up,
--   * where creatures lay when their loot window opened.
-- Together with the shipped recordings (Data/QuestsEG.lua) this feeds the NPC
-- tooltip lines and the quest preview without QuestieDB.
local _, ns = ...
local L = ns.L

local Observations = ns:NewModule("Observations", {
	title = L.OBS_TITLE,
	order = 11.9,
	defaults = {
		record = true,
	},
})

local CELL_DISTANCE = 1.5 -- percent of the map: points closer than this are one
local MAX_CELLS = 10      -- per objective / creature
local MAX_ENTRIES = 3000  -- per table

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function NpcID(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
		return
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end
Observations.NpcID = NpcID

local function PlayerPosition()
	local mapID = ns.Number(C_Map.GetBestMapForUnit("player"))
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return
	end
	local x, y = position:GetXY()
	x, y = ns.Number(x), ns.Number(y)
	if x and y and (x ~= 0 or y ~= 0) then
		return mapID, x * 100, y * 100
	end
end

-- Adds a point to a list of cells { map, x, y, n }: merged with a close one.
function Observations.AddCell(list, mapID, x, y)
	for _, cell in ipairs(list) do
		if cell[1] == mapID and math.abs(cell[2] - x) < CELL_DISTANCE and math.abs(cell[3] - y) < CELL_DISTANCE then
			cell[4] = cell[4] + 1
			return
		end
	end
	if #list < MAX_CELLS then
		list[#list + 1] = { mapID, tonumber(("%.1f"):format(x)), tonumber(("%.1f"):format(y)), 1 }
	end
end

local function Count(tbl)
	local n = 0
	for _ in pairs(tbl) do
		n = n + 1
	end
	return n
end

---------------------------------------------------------------------------
-- NPCs and their quests
---------------------------------------------------------------------------
local function NpcEntry(npcID)
	local npcs = ns.db.npcQuests
	local entry = npcs[npcID]
	if not entry then
		if Observations.npcCount >= MAX_ENTRIES then
			return
		end
		Observations.npcCount = Observations.npcCount + 1
		entry = { offers = {}, takes = {}, cells = {} }
		npcs[npcID] = entry
	end
	return entry
end

-- kind: "offers" or "takes"; quests: list of quest IDs.
function Observations.RecordNpc(npcID, kind, quests)
	local entry = npcID and #quests > 0 and NpcEntry(npcID)
	if not entry then
		return
	end
	for _, questID in ipairs(quests) do
		entry[kind][questID] = true
	end
	if not entry.name then
		local name = UnitName("npc")
		if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			entry.name = name
		end
	end
	local mapID, x, y = PlayerPosition()
	if mapID then
		Observations.AddCell(entry.cells, mapID, x, y)
	end
	Observations.merged = nil
end

local function OnGossipShow()
	local npcID = NpcID(UnitGUID("npc"))
	if not npcID then
		return
	end
	local offered, taken = {}, {}
	for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		local id = ns.Number(quest.questID)
		if id then
			offered[#offered + 1] = id
		end
	end
	for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		local id = ns.Number(quest.questID)
		if id and quest.isComplete then
			taken[#taken + 1] = id
		end
	end
	Observations.RecordNpc(npcID, "offers", offered)
	Observations.RecordNpc(npcID, "takes", taken)
end

local function OnQuestDetail()
	local id = ns.Number(GetQuestID())
	if id and id > 0 then
		Observations.RecordNpc(NpcID(UnitGUID("npc")), "offers", { id })
	end
end

local function OnQuestComplete()
	local id = ns.Number(GetQuestID())
	if id and id > 0 then
		Observations.RecordNpc(NpcID(UnitGUID("npc")), "takes", { id })
	end
end

---------------------------------------------------------------------------
-- Objectives and creatures
---------------------------------------------------------------------------
local lastCounts = {} -- questID -> { count per objective }

function Observations.OnObjectiveUpdate(questID)
	questID = ns.Number(questID)
	local objectives = questID and C_QuestLog.GetQuestObjectives(questID)
	if not objectives then
		return
	end
	local last = lastCounts[questID] or {}
	lastCounts[questID] = last
	local mapID, x, y = PlayerPosition()
	for index, objective in ipairs(objectives) do
		local fulfilled = ns.Number(objective.numFulfilled, 0)
		if mapID and fulfilled > (last[index] or 0) then
			local byQuest = ns.db.objectivePoints[questID]
			if not byQuest and Observations.objectiveCount < MAX_ENTRIES then
				byQuest = {}
				ns.db.objectivePoints[questID] = byQuest
				Observations.objectiveCount = Observations.objectiveCount + 1
			end
			if byQuest then
				byQuest[index] = byQuest[index] or {}
				Observations.AddCell(byQuest[index], mapID, x, y)
				Observations.merged = nil
			end
		end
		last[index] = fulfilled
	end
end

-- A creature's loot window opened: the player stands next to it.
function Observations.Creature(npcID)
	if not (Observations.db.record and npcID) then
		return
	end
	local list = ns.db.creaturePoints[npcID]
	if not list then
		if Observations.creatureCount >= MAX_ENTRIES then
			return
		end
		Observations.creatureCount = Observations.creatureCount + 1
		list = {}
		ns.db.creaturePoints[npcID] = list
	end
	local mapID, x, y = PlayerPosition()
	if mapID then
		Observations.AddCell(list, mapID, x, y)
	end
end

---------------------------------------------------------------------------
-- Lookup: shipped recordings and the player's own together
---------------------------------------------------------------------------
-- { name =, offers = { [questID] = true }, takes = { … }, cells = { { map, x, y }, … } } or nil.
function Observations.Npc(npcID)
	local shipped = ns.QuestData and ns.QuestData.npcs and ns.QuestData.npcs[npcID]
	local own = ns.db.npcQuests[npcID]
	if not shipped and not own then
		return
	end
	local result = { offers = {}, takes = {}, cells = {} }
	if shipped then
		result.name = shipped[1]
		result.cells[1] = { shipped[2], shipped[3], shipped[4] }
		for _, id in ipairs(shipped[5]) do result.offers[id] = true end
		for _, id in ipairs(shipped[6]) do result.takes[id] = true end
	end
	if own then
		result.name = result.name or own.name
		for id in pairs(own.offers) do result.offers[id] = true end
		for id in pairs(own.takes) do result.takes[id] = true end
		for _, cell in ipairs(own.cells) do result.cells[#result.cells + 1] = cell end
	end
	return result
end

-- NPCs that take a quest back: { { name =, cells = { { map, x, y }, … } }, … }.
function Observations.Takers(questID)
	local result = {}
	for npcID, row in pairs(ns.QuestData and ns.QuestData.npcs or {}) do
		for _, id in ipairs(row[6]) do
			if id == questID then
				result[#result + 1] = { id = npcID, name = row[1], cells = { { row[2], row[3], row[4] } } }
			end
		end
	end
	for npcID, entry in pairs(ns.db.npcQuests) do
		if entry.takes[questID] then
			local known
			for _, taker in ipairs(result) do
				known = known or taker.id == npcID
			end
			if not known then
				result[#result + 1] = { id = npcID, name = entry.name, cells = entry.cells }
			end
		end
	end
	return result
end

-- Where a creature was seen dying (shipped) or looted (own): { { map, x, y }, … }.
function Observations.CreaturePoints(npcID)
	local points = {}
	for _, point in ipairs(ns.QuestData and ns.QuestData.creatures and ns.QuestData.creatures[npcID] or {}) do
		points[#points + 1] = point
	end
	for _, cell in ipairs(ns.db.creaturePoints[npcID] or {}) do
		points[#points + 1] = cell
	end
	return points
end

local TARGET_CODE = { monster = "m", item = "i", object = "o" }
local MAX_DROP_SOURCES = 5

-- Points of the `ordinal`-th objective of a kind ("monster", "item", "object")
-- of a quest: its creature, the creatures an item drops from, or its object.
function Observations.TargetPoints(questID, kind, ordinal)
	local code = TARGET_CODE[kind]
	local list = code and ns.QuestData and ns.QuestData.targets and ns.QuestData.targets[questID]
	if not list then
		return {}
	end
	local target
	for _, entry in ipairs(list) do
		if entry[1] == code then
			ordinal = ordinal - 1
			if ordinal == 0 then
				target = entry[2]
				break
			end
		end
	end
	if not target then
		return {}
	end
	if code == "m" then
		return Observations.CreaturePoints(target)
	elseif code == "o" then
		return ns.QuestData.objects and ns.QuestData.objects[target] or {}
	end
	local points = {}
	local sources = ns:GetModule("LootSources").Sources(target)
	for i = 1, math.min(MAX_DROP_SOURCES, #sources) do
		local kindName, id = sources[i].key:match("^(%a+):(%d+)$")
		id = tonumber(id)
		local found = kindName == "npc" and Observations.CreaturePoints(id)
			or kindName == "object" and ns.QuestData.objects and ns.QuestData.objects[id] or {}
		for _, point in ipairs(found) do
			points[#points + 1] = point
		end
	end
	return points
end

-- Points where objective `index` of a quest was advanced: { { map, x, y }, … }.
function Observations.ObjectivePoints(questID, index)
	local points = {}
	local shipped = ns.QuestData and ns.QuestData.objectives and ns.QuestData.objectives[questID]
	for _, point in ipairs(shipped and shipped[index] or {}) do
		points[#points + 1] = point
	end
	local own = ns.db.objectivePoints[questID]
	for _, cell in ipairs(own and own[index] or {}) do
		points[#points + 1] = cell
	end
	return points
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function Ids(set)
	local list = {}
	for id in pairs(set) do
		list[#list + 1] = id
	end
	table.sort(list)
	return table.concat(list, ", ")
end

local function CellText(cells)
	local parts = {}
	for _, cell in ipairs(cells) do
		parts[#parts + 1] = ("{ %d, %.1f, %.1f, %d }"):format(cell[1], cell[2], cell[3], cell[4] or 1)
	end
	return table.concat(parts, ", ")
end

function Observations.ExportText()
	local lines = {}
	local npcs = {}
	for id in pairs(ns.db.npcQuests) do npcs[#npcs + 1] = id end
	table.sort(npcs)
	if #npcs > 0 then
		lines[#lines + 1] = ns.ExportTag("npcs")
		lines[#lines + 1] = L.OBS_EXPORT_NPCS
		for _, id in ipairs(npcs) do
			local entry = ns.db.npcQuests[id]
			lines[#lines + 1] = ("{ %d, %q, { %s }, { %s }, { %s } },"):format(id, entry.name or "?", Ids(entry.offers), Ids(entry.takes), CellText(entry.cells))
		end
	end
	local quests = {}
	for id in pairs(ns.db.objectivePoints) do quests[#quests + 1] = id end
	table.sort(quests)
	if #quests > 0 then
		lines[#lines + 1] = ns.ExportTag("objectives")
		lines[#lines + 1] = L.OBS_EXPORT_OBJECTIVES
		for _, id in ipairs(quests) do
			local indices = {}
			for index in pairs(ns.db.objectivePoints[id]) do indices[#indices + 1] = index end
			table.sort(indices)
			for _, index in ipairs(indices) do
				lines[#lines + 1] = ("{ %d, %d, { %s } },"):format(id, index, CellText(ns.db.objectivePoints[id][index]))
			end
		end
	end
	local creatures = {}
	for id in pairs(ns.db.creaturePoints) do creatures[#creatures + 1] = id end
	table.sort(creatures)
	if #creatures > 0 then
		lines[#lines + 1] = ns.ExportTag("creatures")
		lines[#lines + 1] = L.OBS_EXPORT_CREATURES
		for _, id in ipairs(creatures) do
			lines[#lines + 1] = ("{ %d, { %s } },"):format(id, CellText(ns.db.creaturePoints[id]))
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

ns.AddDataSection(function()
	return Observations.ExportText()
end, function()
	ns.db.npcQuests, ns.db.objectivePoints, ns.db.creaturePoints = {}, {}, {}
	Observations.npcCount, Observations.objectiveCount, Observations.creatureCount = 0, 0, 0
	Observations.merged = nil
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Observations:OnInitialize()
	ns.db.npcQuests = ns.db.npcQuests or {}
	ns.db.objectivePoints = ns.db.objectivePoints or {}
	ns.db.creaturePoints = ns.db.creaturePoints or {}
	self.npcCount, self.objectiveCount, self.creatureCount = Count(ns.db.npcQuests), Count(ns.db.objectivePoints), Count(ns.db.creaturePoints)
end

function Observations:Apply()
	local on = self.db.record
	self:ToggleEvent("GOSSIP_SHOW", on, OnGossipShow)
	self:ToggleEvent("QUEST_DETAIL", on, OnQuestDetail)
	self:ToggleEvent("QUEST_COMPLETE", on, OnQuestComplete)
	self:ToggleEvent("QUEST_WATCH_UPDATE", on, function(_, _, questID)
		Observations.OnObjectiveUpdate(questID)
	end)
end

function Observations:OnLogin()
	self:Apply()
end

function Observations:OnOptionChanged()
	self:Apply()
end

Observations.options = {
	{ key = "record", type = "toggle", name = L.OBS_RECORD, desc = L.OBS_RECORD_DESC },
}

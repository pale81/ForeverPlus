-- Tooltip lines from QuestieDB (optional data addon): where an item comes from
-- and which quests an NPC offers or takes back.
local _, ns = ...
local L = ns.L

local Info = ns:NewModule("QuestieInfo", {
	title = L.QDB_TITLE,
	order = 2.1,
	defaults = {
		itemSources = true,
		npcQuests = true,
	},
})

local MAX_NAMES = 3
local MAX_QUEST_LINES = 4
local SOURCE_COLOR = "|cff99ccff%s|r"
local QUEST_COLOR = "|cffffd100%s|r"

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- An entity table of QuestieDB (Item, Npc, Object) with the functions used here.
local function Entity(lib, name)
	local entity = lib and lib[name]
	if type(entity) == "table" and type(entity.Get) == "function" and type(entity.Exists) == "function" then
		return entity
	end
end

---------------------------------------------------------------------------
-- Item sources
---------------------------------------------------------------------------
local itemCache = {} -- itemID -> lines ({ label, text }) or false

-- Distinct names of the given IDs, at most MAX_NAMES plus "(+n)".
-- Names are read only until MAX_NAMES distinct ones are found (items such
-- as cloth drop from hundreds of NPCs); the rest is counted by ID.
local function NameList(entity, ids)
	if not entity or type(ids) ~= "table" then
		return nil
	end
	local names, seen = {}, {}
	local index = 0
	while index < #ids and #names < MAX_NAMES do
		index = index + 1
		local name = entity.Get(ids[index], "name")
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		return nil
	end
	local text = table.concat(names, ", ")
	local extra = #ids - index
	if extra > 0 then
		text = text .. " " .. L.QDB_MORE:format(extra)
	end
	return text
end

local function ItemLines(itemID)
	local cached = itemCache[itemID]
	if cached ~= nil then
		return cached
	end
	local lib = ns.QuestieDB.Get()
	local item = Entity(lib, "Item")
	if not item or not item.Exists(itemID) then
		return nil -- not cached: QuestieDB may still load
	end
	local npc, object = Entity(lib, "Npc"), Entity(lib, "Object")
	local lines = {}
	local function Add(label, text)
		if text then
			lines[#lines + 1] = { label, text }
		end
	end
	Add(L.QDB_DROPS, NameList(npc, item.Get(itemID, "npcDrops")))
	Add(L.QDB_OBJECTS, NameList(object, item.Get(itemID, "objectDrops")))
	Add(L.QDB_CONTAINERS, NameList(item, item.Get(itemID, "itemDrops")))
	Add(L.QDB_VENDORS, NameList(npc, item.Get(itemID, "vendors")))
	local quest = item.Get(itemID, "startQuest")
	if type(quest) == "number" and quest > 0 then
		Add(L.QDB_STARTS_QUEST, lib.Quest.Get(quest, "name"))
	end
	itemCache[itemID] = #lines > 0 and lines or false
	return itemCache[itemID]
end

local function OnItemTooltip(tooltip, data)
	if not Info.db.itemSources or tooltip:IsForbidden() or tooltip.isShopping then
		return
	end
	local itemID = data and data.id
	if type(itemID) ~= "number" or Secret(itemID) then
		return
	end
	-- Recipes already get their sources from the recipe radar.
	local radar = ns:GetModule("RecipeRadar")
	if radar and radar.db and radar.db.enabled and radar.db.tooltipSources
		and select(6, C_Item.GetItemInfoInstant(itemID)) == Enum.ItemClass.Recipe then
		return
	end
	local lines = ItemLines(itemID)
	if not lines then
		return
	end
	for _, line in ipairs(lines) do
		tooltip:AddLine(("%s %s"):format(SOURCE_COLOR:format(line[1]), line[2]), 1, 1, 1, true)
	end
	tooltip:Show()
end

---------------------------------------------------------------------------
-- NPC quests: quests the player can take here and quests to hand in here
---------------------------------------------------------------------------
local playerRaceMask, playerClassMask

local function PlayerMasks(lib)
	if playerClassMask == nil then
		local _, _, classID = UnitClass("player")
		playerClassMask = classID and 2 ^ (classID - 1) or false
		local _, _, raceID = UnitRace("player")
		local masks = ns.QuestieDB.HasContract(lib, 3) and lib.Enum and lib.Enum.raceMaskById
		playerRaceMask = masks and raceID and masks[raceID] or false
	end
	return playerRaceMask, playerClassMask
end

-- Bit test without bit operations (masks may exceed 32 bits).
local function HasBit(mask, bitValue)
	return math.floor(mask / bitValue) % 2 == 1
end

local function Completed(questID)
	return C_QuestLog.IsQuestFlaggedCompleted(questID)
end

local function AnyCompleted(list)
	for _, questID in ipairs(list) do
		if Completed(questID) then
			return true
		end
	end
	return false
end

local function AllCompleted(list)
	for _, questID in ipairs(list) do
		if not Completed(questID) then
			return false
		end
	end
	return true
end

-- Available by the data: not done, not in the log, level, race, class,
-- pre-quests and mutually exclusive quests. Events and reputation are not checked.
local function IsAvailable(lib, questID)
	if Completed(questID) or C_QuestLog.GetLogIndexForQuestID(questID) then
		return false
	end
	local values = lib.Quest.GetAll(questID, { "requiredLevel", "requiredRaces", "requiredClasses", "preQuestSingle", "preQuestGroup", "exclusiveTo" })
	if not values then
		return false
	end
	local level, races, classes, single, group, exclusive = values[1], values[2], values[3], values[4], values[5], values[6]
	if type(level) == "number" and level > UnitLevel("player") then
		return false
	end
	local raceMask, classMask = PlayerMasks(lib)
	if raceMask and type(races) == "number" and races ~= 0 and not HasBit(races, raceMask) then
		return false
	end
	if classMask and type(classes) == "number" and classes ~= 0 and not HasBit(classes, classMask) then
		return false
	end
	if type(single) == "table" and #single > 0 and not AnyCompleted(single) then
		return false
	end
	if type(group) == "table" and not AllCompleted(group) then
		return false
	end
	if type(exclusive) == "table" and AnyCompleted(exclusive) then
		return false
	end
	return true
end

local function NpcID(guid)
	if type(guid) ~= "string" or Secret(guid) then
		return nil
	end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(npcID)
	end
end

local function AddQuestLines(tooltip, label, quests)
	for i, name in ipairs(quests) do
		if i > MAX_QUEST_LINES then
			tooltip:AddLine(L.QDB_MORE:format(#quests - MAX_QUEST_LINES), 0.6, 0.6, 0.6)
			break
		end
		tooltip:AddLine(("%s %s"):format(QUEST_COLOR:format(label), name), 1, 1, 1, true)
	end
end

local function OnUnitTooltip(tooltip, data)
	if not Info.db.npcQuests or tooltip:IsForbidden() or tooltip ~= GameTooltip then
		return
	end
	local npcID = NpcID(data and data.guid)
	local lib = npcID and ns.QuestieDB.Get()
	local npc = Entity(lib, "Npc")
	if not npc or not npc.Exists(npcID) then
		return
	end
	local offers, turnIns = {}, {}
	for _, questID in ipairs(npc.Get(npcID, "questStarts") or {}) do
		if IsAvailable(lib, questID) then
			offers[#offers + 1] = lib.Quest.Get(questID, "name") or tostring(questID)
		end
	end
	for _, questID in ipairs(npc.Get(npcID, "questEnds") or {}) do
		if C_QuestLog.GetLogIndexForQuestID(questID) then
			turnIns[#turnIns + 1] = lib.Quest.Get(questID, "name") or tostring(questID)
		end
	end
	if #offers + #turnIns > 0 then
		AddQuestLines(tooltip, L.QDB_QUEST_OFFER, offers)
		AddQuestLines(tooltip, L.QDB_QUEST_TURNIN, turnIns)
		tooltip:Show()
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Info:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("QuestieInfo: item tooltip", OnItemTooltip))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Measured("QuestieInfo: unit tooltip", OnUnitTooltip))
end

Info.options = {
	{ key = "itemSources", type = "toggle", name = L.QDB_ITEM_SOURCES, desc = L.QDB_ITEM_SOURCES_DESC },
	{ key = "npcQuests", type = "toggle", name = L.QDB_NPC_QUESTS, desc = L.QDB_NPC_QUESTS_DESC },
}

-- Scout: a message when the nameplate of a rare creature appears, and the herbs and ore veins the player gathered,
-- remembered by place and shown on the world map. Whether a node is a herb or ore comes from what it gave
-- (trade goods: herbs, or metal and stone), so no gathering spell IDs are needed.
local _, ns = ...
local L = ns.L

local Scout = ns:NewModule("Scout", {
	title = L.SCOUT_TITLE,
	order = 12.5,
	defaults = { rareAlert = true, rareSound = true, rareSoundChoice = "warning", gatherRecord = true, gatherMap = true },
})

local RARE = { rare = true, rareelite = true }
local RARE_PAUSE = 600 -- seconds before the same creature is announced again
local SAME_NODE = 0.006 -- closer than this (fraction of the map) is the same spot
local MAX_NODES = 400 -- per map
local TRADE_GOODS = Enum.ItemClass and ns.Number(Enum.ItemClass.Tradegoods) or 7
local KINDS = { [9] = "herb", [7] = "ore" } -- trade goods subclasses: herb, metal and stone
local ICONS = { herb = [[Interface\Icons\INV_Misc_Flower_02]], ore = [[Interface\Icons\INV_Ore_Copper_01]] }
local announced = {}
local requestedItems = {}

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- Adds a node to the list of a map, or counts it again at a known spot. Returns the entry.
function Scout.AddNode(list, object, kind, x, y)
	for _, node in ipairs(list) do
		if node[3] == object and math.abs(node[1] - x) < SAME_NODE and math.abs(node[2] - y) < SAME_NODE then
			node[5] = (node[5] or 1) + 1
			return node
		end
	end
	if #list >= MAX_NODES then table.remove(list, 1) end
	local node = { x, y, object, kind, 1 }
	list[#list + 1] = node
	return node
end

-- Whether a rare creature (by GUID) should be announced now.
function Scout.ShouldAnnounce(guid, now, last)
	if last[guid] and now - last[guid] < RARE_PAUSE then return false end
	last[guid] = now
	return true
end

---------------------------------------------------------------------------
-- Gathering
---------------------------------------------------------------------------
local function Nodes(mapID)
	if type(ns.db.gatherNodes) ~= "table" then ns.db.gatherNodes = {} end
	ns.db.gatherNodes[mapID] = ns.db.gatherNodes[mapID] or {}
	return ns.db.gatherNodes[mapID]
end

local function ItemKind(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if ns.Number(classID) == TRADE_GOODS then
		return KINDS[ns.Number(subclassID)]
	end
end

local function ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if type(name) == "string" and not ns.Secret(name) and name ~= "" then return name end
end

local function OnObjectLoot(key, items, itemNames)
	if not Scout.db.gatherRecord then return end
	local object = tonumber(key:match("^object:(%d+)$"))
	if not object then return end
	local kind, materials
	for _, itemID in ipairs(items) do
		local itemKind = ItemKind(itemID)
		if itemKind then
			kind = kind or itemKind
			if itemKind == kind then
				materials = materials or {}
				materials[itemID] = itemNames and itemNames[itemID] or ItemName(itemID) or false
			end
		end
	end
	if not kind then return end
	local mapID = ns.Number(C_Map.GetBestMapForUnit("player"))
	if not mapID then return end
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y = position and ns.Number(position.x), position and ns.Number(position.y)
	if not (x and y) or (x == 0 and y == 0) then return end
	local node = Scout.AddNode(Nodes(mapID), object, kind, x, y)
	node.items = node.items or {}
	for itemID, name in pairs(materials) do
		node.items[itemID] = name or node.items[itemID] or false
	end
	ns.MapSymbols.Refresh()
end

-- Old pins only have the object ID. Use the local loot history if it identifies a single material.
local function LegacyItemID(node)
	local source = ns.db.lootSources["object:" .. node[3]]
	local match
	for itemID in pairs(source and source.items or {}) do
		if ItemKind(itemID) == node[4] then
			if match then return end
			match = itemID
		end
	end
	return match
end

local function NodeName(node)
	local name = ns.LootData and ns.LootData.names and ns.LootData.names["object:" .. node[3]]
	return name and name ~= "?" and name or (node[4] == "herb" and L.SCOUT_HERB or L.SCOUT_ORE)
end

local function LoadItemName(itemID)
	local name = ItemName(itemID)
	if not name and not requestedItems[itemID] then
		requestedItems[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name
end

local function NodeTooltip(tooltip, symbol)
	local node = symbol.data
	local names = {}
	if node.items then
		for itemID, savedName in pairs(node.items) do
			local name = savedName or LoadItemName(itemID)
			if name then
				node.items[itemID] = name
				names[#names + 1] = name
			end
		end
	else
		local itemID = LegacyItemID(node)
		local name = itemID and LoadItemName(itemID)
		if name then names[1] = name end
	end
	if #names == 0 then names[1] = NodeName(node) end
	table.sort(names)
	for _, name in ipairs(names) do
		tooltip:AddLine(name, 1, 1, 1)
	end
	tooltip:AddLine(L.SCOUT_GATHERED:format(node[5] or 1), 0.7, 0.7, 0.7)
end

ns.MapSymbols.AddSource(function(mapID, add)
	local db = Scout.db
	local nodes = db and db.gatherMap and type(ns.db.gatherNodes) == "table" and ns.db.gatherNodes[mapID]
	for _, node in ipairs(nodes or {}) do
		add(node[1], node[2], { kind = "gather", texture = ICONS[node[4]] or ICONS.ore, size = 14, round = true,
			data = node, mapID = mapID, tooltip = NodeTooltip })
	end
end)

---------------------------------------------------------------------------
-- Rare creatures
---------------------------------------------------------------------------
local function OnNameplate(_, _, unit)
	if ns.Secret(unit) or type(unit) ~= "string" then return end
	local classification, dead, guid = UnitClassification(unit), UnitIsDead(unit), UnitGUID(unit)
	if ns.Secret(classification) or ns.Secret(dead) or ns.Secret(guid) or not RARE[classification] or dead or not guid then
		return
	end
	if not Scout.ShouldAnnounce(guid, GetTime(), announced) then return end
	local name, level = UnitName(unit), UnitLevel(unit)
	if ns.Secret(name) or type(name) ~= "string" then return end
	level = ns.Number(level)
	ns.PrintAlways(L.SCOUT_RARE, name, level and level > 0 and tostring(level) or "??")
	if Scout.db.rareSound then ns.AlertSounds.PlayWarning(Scout.db.rareSoundChoice) end
end

function Scout:OnOptionChanged()
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", self.db.rareAlert, OnNameplate)
	ns.MapSymbols.Refresh()
end

function Scout:OnLogin()
	local sources = ns:GetModule("LootSources")
	sources.objectListeners[#sources.objectListeners + 1] = ns.Measured("Scout: object loot", OnObjectLoot)
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", self.db.rareAlert, OnNameplate)
end

Scout.options = {
	{ key = "rareAlert", type = "toggle", name = L.SCOUT_RARE_OPTION, desc = L.SCOUT_RARE_OPTION_DESC },
	{ key = "rareSound", type = "toggle", name = L.SCOUT_RARE_SOUND, parent = "rareAlert" },
	{ key = "rareSoundChoice", type = "dropdown", name = L.ITEMS_FULL_SOUND_CHOICE, parent = "rareSound",
		values = function() return ns.AlertSounds.WarningChoices() end },
	{ type = "button", name = L.ITEMS_FULL_SOUND_TEST, text = L.QUESTS_TEST,
		func = function() ns.AlertSounds.PlayWarning(Scout.db.rareSoundChoice) end },
	{ key = "gatherRecord", type = "toggle", name = L.SCOUT_GATHER_OPTION, desc = L.SCOUT_GATHER_OPTION_DESC },
	{ key = "gatherMap", type = "toggle", name = L.SCOUT_GATHER_MAP, desc = L.SCOUT_GATHER_MAP_DESC },
}

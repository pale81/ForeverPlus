-- Loot sources: where items drop. Every loot window of a corpse or a node
-- counts for its source (kills) and for each item in it (drops); item tooltips
-- show the best sources with their share. Data from the open Efficient Games
-- recordings (Data/LootEG.lua) plus the player's own windows, which can be
-- exported (/fp daten export) to complete a later update.
local _, ns = ...
local L = ns.L

local LootSources = ns:NewModule("LootSources", {
	title = L.LOOTSRC_TITLE,
	order = 11.8,
	defaults = {
		record = true,
		tooltip = true,
	},
})

local MAX_SOURCES = 3000   -- recorded sources
local MAX_ITEMS = 80       -- items per source
local TOOLTIP_SOURCES = 3
local MIN_WINDOWS = 2      -- sources with fewer windows are not shown as a share

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- "npc:<id>" or "object:<id>" of a loot source GUID; containers (item GUIDs
-- carry no item ID) and everything else are left out.
function LootSources.SourceKey(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
		return
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	id = tonumber(id)
	if not id then
		return
	elseif kind == "Creature" then
		return "npc:" .. id
	elseif kind == "GameObject" then
		return "object:" .. id
	end
end

local function ItemID(link)
	if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then
		return
	end
	return tonumber(link:match("item:(%d+)"))
end

local opened = {} -- GUIDs counted in this session

-- The items of the open loot window by the one source that holds them.
local function ReadWindow()
	local sourceGUID, items = nil, {}
	for slot = 1, ns.Number(GetNumLootItems(), 0) do
		local guid1, _, guid2 = GetLootSourceInfo(slot)
		if guid2 or not guid1 then
			return -- several sources (area loot) or none: not attributable
		end
		if sourceGUID and sourceGUID ~= guid1 then
			return
		end
		sourceGUID = guid1
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local id = ItemID(GetLootSlotLink(slot))
			if id then
				items[#items + 1] = id
			end
		end
	end
	return sourceGUID, items
end

function LootSources.Record(guid, key, items, name)
	local sources = ns.db.lootSources
	local entry = sources[key]
	if not entry then
		if LootSources.count >= MAX_SOURCES then
			return
		end
		LootSources.count = LootSources.count + 1
		entry = { windows = 0, items = {} }
		sources[key] = entry
	end
	opened[guid] = true
	entry.windows = entry.windows + 1
	if name and not entry.name then
		entry.name = name
	end
	local known = 0
	for _ in pairs(entry.items) do
		known = known + 1
	end
	for _, id in ipairs(items) do
		if entry.items[id] or known < MAX_ITEMS then
			if not entry.items[id] then
				known = known + 1
			end
			entry.items[id] = (entry.items[id] or 0) + 1
		end
	end
	LootSources.merged = nil
end

local function OnLootOpened()
	if not GetLootSourceInfo or IsFishingLoot() then
		return
	end
	local guid, items = ReadWindow()
	local key = guid and LootSources.SourceKey(guid)
	if not key or opened[guid] then
		return
	end
	local name
	if UnitGUID("target") == guid then
		name = UnitName("target")
		if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then
			name = nil
		end
	end
	LootSources.Record(guid, key, items, name)
end

---------------------------------------------------------------------------
-- Lookup: shipped data and the player's own windows together
---------------------------------------------------------------------------
-- item -> { { key, drops, windows }, ... }, built on first use.
local function Merged()
	if LootSources.merged then
		return LootSources.merged
	end
	local byItem = {}
	for item, rows in pairs(ns.LootData and ns.LootData.items or {}) do
		local list = {}
		for _, row in ipairs(rows) do
			list[row[1]] = { drops = row[2], windows = row[3] }
		end
		byItem[item] = list
	end
	for key, entry in pairs(ns.db.lootSources) do
		for item, drops in pairs(entry.items) do
			local list = byItem[item]
			if not list then
				list = {}
				byItem[item] = list
			end
			local row = list[key]
			if row then
				row.drops, row.windows = row.drops + drops, row.windows + entry.windows
			else
				list[key] = { drops = drops, windows = entry.windows }
			end
		end
	end
	LootSources.merged = byItem
	return byItem
end

-- The best sources of an item: { { key, drops, windows }, ... } by share.
function LootSources.Sources(itemID)
	local list = Merged()[itemID]
	if not list then
		return {}
	end
	local sorted = {}
	for key, row in pairs(list) do
		sorted[#sorted + 1] = { key = key, drops = row.drops, windows = row.windows }
	end
	table.sort(sorted, function(a, b)
		local sa, sb = a.drops / a.windows, b.drops / b.windows
		if sa ~= sb then
			return sa > sb
		end
		return a.windows > b.windows
	end)
	return sorted
end

local function SourceName(key)
	local own = ns.db.lootSources[key]
	local name = own and own.name or ns.LootData and ns.LootData.names and ns.LootData.names[key]
	if name and name ~= "?" then
		return name
	end
	return key
end

local function AddTooltipLines(tooltip, data)
	if not (LootSources.db.tooltip and ns.ExtraInfoShown()) or tooltip:IsForbidden() then
		return
	end
	local id = data and ns.Number(data.id)
	local sources = id and LootSources.Sources(id)
	if not sources or #sources == 0 then
		return
	end
	for i = 1, math.min(TOOLTIP_SOURCES, #sources) do
		local source = sources[i]
		local share = ("%d%%"):format(math.floor(source.drops / source.windows * 100 + 0.5))
		local right = source.windows >= MIN_WINDOWS and L.LOOTSRC_SHARE:format(share, source.drops, source.windows)
			or L.LOOTSRC_ONCE
		tooltip:AddDoubleLine(L.LOOTSRC_FROM:format(SourceName(source.key)), right, 1, 0.82, 0, 0.8, 0.8, 0.8)
	end
	if #sources > TOOLTIP_SOURCES then
		tooltip:AddLine(L.LOOTSRC_MORE:format(#sources - TOOLTIP_SOURCES), 0.7, 0.7, 0.7)
	end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
function LootSources.ExportText(sources)
	local lines = { L.LOOTSRC_EXPORT_HEADER }
	local keys = {}
	for key in pairs(sources) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local entry = sources[key]
		local ids = {}
		for id in pairs(entry.items) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		local parts = {}
		for _, id in ipairs(ids) do
			parts[#parts + 1] = ("[%d] = %d"):format(id, entry.items[id])
		end
		lines[#lines + 1] = ("{ %q, %q, %d, { %s } },"):format(key, entry.name or "?", entry.windows, table.concat(parts, ", "))
	end
	return table.concat(lines, "\n")
end

ns.AddDataSection(function()
	return next(ns.db.lootSources) ~= nil and LootSources.ExportText(ns.db.lootSources) or nil
end, function()
	ns.db.lootSources = {}
	LootSources.count = 0
	LootSources.merged = nil
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function LootSources:Apply()
	self:ToggleEvent("LOOT_OPENED", self.db.record, OnLootOpened)
end

function LootSources:OnInitialize()
	ns.db.lootSources = ns.db.lootSources or {}
	local count = 0
	for _ in pairs(ns.db.lootSources) do
		count = count + 1
	end
	self.count = count
end

function LootSources:OnLogin()
	self:Apply()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("LootSources: tooltip", AddTooltipLines))
end

function LootSources:OnOptionChanged()
	self:Apply()
end

LootSources.options = {
	{ key = "tooltip", type = "toggle", name = L.LOOTSRC_TOOLTIP, desc = L.LOOTSRC_TOOLTIP_DESC },
	{ key = "record", type = "toggle", name = L.LOOTSRC_RECORD, desc = L.LOOTSRC_RECORD_DESC },
}

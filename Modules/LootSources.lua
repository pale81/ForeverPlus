-- Loot sources: where items drop. Every loot window counts once per source
-- (corpse or node) and once per item found there; item tooltips
-- show the best sources with their share. Data from the open Efficient Games
-- recordings (Data/LootEG.lua) plus the player's own windows, which can be
-- exported (/fp daten export) to complete a later update.
local _, ns = ...
local L = ns.L
local decimalComma = GetLocale() == "deDE"

local LootSources = ns:NewModule("LootSources", {
	title = L.LOOTSRC_TITLE,
	order = 11.8,
	defaults = {
		record = true,
		tooltip = true,
		unitLoot = true,
	},
})

local MAX_SOURCES = 3000   -- recorded sources
local MAX_ITEMS = 80       -- items per source
local TOOLTIP_SOURCES = 3
local TOOLTIP_DROPS = 20
local MIN_WINDOWS = 2      -- sources with fewer windows are not shown as a share
local creatureDrops = {}
local NON_CORPSE_SPELLS = { [921] = true, [8613] = true, [8617] = true, [8618] = true, [10768] = true }
local CAST_GRACE = 6
local lastNonCorpseCast, lastLootCastGUID

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- "npc:<id>" or "object:<id>" of a loot source GUID; containers (item GUIDs
-- carry no item ID) and everything else are left out.
function LootSources.SourceKey(guid)
	local kind, id = ns.GuidParts(guid)
	if not id then
		return
	elseif kind == "Creature" then
		return "npc:" .. id
	elseif kind == "GameObject" then
		return "object:" .. id
	end
end

local function ItemID(link)
	if type(link) ~= "string" or ns.Secret(link) then
		return
	end
	return tonumber(link:match("item:(%d+)"))
end

local opened = {} -- GUIDs counted in this session

local function ReadSlotSources(sources, itemID, ...)
	if select("#", ...) == 0 then
		return false
	end
	for i = 1, select("#", ...), 2 do
		local guid = select(i, ...)
		local key = LootSources.SourceKey(guid)
		if not key then
			return false
		end
		local source = sources[guid]
		if not source then
			source = { key = key, items = {} }
			sources[guid] = source
		end
		if itemID then
			source.items[#source.items + 1] = itemID
		end
	end
	return true
end

-- An unreadable slot could hide a drop, so discard the whole incomplete snapshot.
local function ReadWindow()
	local sources = {}
	for slot = 1, ns.Number(GetNumLootItems(), 0) do
		local slotType = ns.Number(GetLootSlotType(slot))
		if not slotType or slotType == Enum.LootSlotType.None then
			return
		end
		local isItem = slotType == Enum.LootSlotType.Item
		local itemID = isItem and ItemID(GetLootSlotLink(slot))
		if (isItem and not itemID) or not ReadSlotSources(sources, itemID, GetLootSourceInfo(slot)) then
			return
		end
	end
	return next(sources) and sources
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
	local seen = {}
	for _, id in ipairs(items) do
		if not seen[id] and (entry.items[id] or known < MAX_ITEMS) then
			seen[id] = true
			if not entry.items[id] then
				known = known + 1
			end
			entry.items[id] = (entry.items[id] or 0) + 1
		end
	end
	LootSources.merged = nil
	creatureDrops[key] = nil
end

local MAX_NAMES = 2000  -- learned names

-- Learns the name of a unit in the client language when its source is not
-- named yet or only by the shipped (English) name. Cheap: a lookup per event.
local function LearnName(unit)
	local key = LootSources.SourceKey(UnitGUID(unit))
	if not key or ns.db.lootNames[key] or ns.db.lootSources[key] and ns.db.lootSources[key].name then
		return
	end
	local names = ns.LootData and ns.LootData.names
	local known = names and names[key]
	if not known and not ns.db.lootSources[key] and not key:find("^npc:") then
		return
	end
	local name = UnitName(unit)
	if type(name) ~= "string" or ns.Secret(name) or name == "" then
		return
	end
	if LootSources.nameCount < MAX_NAMES and (known or ns.db.lootSources[key]) then
		ns.db.lootNames[key] = name
		LootSources.nameCount = LootSources.nameCount + 1
	end
end

LootSources.LearnName = LearnName

local function OnTargetChanged()
	LearnName("target")
end

local function OnMouseoverChanged()
	LearnName("mouseover")
end

local function OnSpellSent(_, _, unit, _, castGUID, spellID)
	if not ns.Secret(unit) and unit == "player" then
		local id = ns.Number(spellID)
		lastNonCorpseCast = id and NON_CORPSE_SPELLS[id] and GetTime() or nil
		lastLootCastGUID = lastNonCorpseCast and not ns.Secret(castGUID) and castGUID or nil
	end
end

local function OnSpellFailed(_, _, unit, castGUID)
	if lastLootCastGUID and not ns.Secret(unit) and unit == "player" and not ns.Secret(castGUID) and castGUID == lastLootCastGUID then
		lastNonCorpseCast, lastLootCastGUID = nil, nil
	end
end

-- Fast loot calls this before taking slots. The two loot events cover manual
-- looting, the game's auto-loot, and clients whose slots only appear on opening.
function LootSources.CaptureWindow()
	if not LootSources.db.record or not GetLootSourceInfo then
		return
	end
	local fishing = IsFishingLoot and IsFishingLoot()
	if ns.Secret(fishing) or fishing then
		return
	end
	-- A restricted loot API call must not interrupt fast loot.
	local ok, sources = pcall(ReadWindow)
	if not ok or not sources then
		return
	end
	-- Pick Pocket and Skinning open loot on the same GUID as ordinary corpse loot.
	local nonCorpseLoot = lastNonCorpseCast and GetTime() - lastNonCorpseCast <= CAST_GRACE
	for _, unit in ipairs({ "target", "mouseover" }) do
		local guid = UnitGUID(unit)
		local source = not ns.Secret(guid) and sources[guid]
		if source and not source.name then
			local name = UnitName(unit)
			if type(name) == "string" and not ns.Secret(name) and name ~= "" then
				source.name = name
			end
		end
	end
	for guid, source in pairs(sources) do
		local npcID = tonumber(source.key:match("^npc:(%d+)$"))
		if not opened[guid] and not (npcID and nonCorpseLoot) then
			LootSources.Record(guid, source.key, source.items, source.name)
			if npcID then
				ns:GetModule("Observations").Creature(npcID)
			end
		end
	end
end

local function OnLootReady()
	-- Fast loot takes the snapshot itself, before mutating any of the slots.
	if not ns:GetModule("Items").db.fastLoot then
		LootSources.CaptureWindow()
	end
end

local function OnLootOpened(_, _, _, isFromItem)
	if not ns.Secret(isFromItem) and not isFromItem then
		LootSources.CaptureWindow()
	end
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

-- Whether the recordings (shipped and own) have the item dropping from the source ("npc:<id>").
function LootSources.DropsFrom(itemID, key)
	local list = Merged()[itemID]
	return list ~= nil and list[key] ~= nil
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
	-- By the lower end of the share (95 % interval): 40 of 60 windows are a better
	-- hint than 2 of 2.
	for _, source in ipairs(sorted) do
		local n, p = source.windows, source.drops / source.windows
		local z2 = 1.96 * 1.96
		source.score = (p + z2 / (2 * n) - 1.96 * math.sqrt((p * (1 - p) + z2 / (4 * n)) / n)) / (1 + z2 / n)
	end
	table.sort(sorted, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.windows > b.windows
	end)
	return sorted
end

local function SourceName(key)
	local own = ns.db.lootSources[key]
	local name = own and own.name or ns.db.lootNames[key]
	local kind, id = key:match("^(%a+):(%d+)$")
	if not name and kind == "npc" then
		local npc = ns:GetModule("Observations").Npc(tonumber(id))
		name = npc and npc.name
	end
	if not name and kind == "item" then
		name = C_Item.GetItemNameByID(tonumber(id))
	end
	name = name or ns.LootData and ns.LootData.names and ns.LootData.names[key]
	if name and name ~= "?" then
		return name
	end
	return kind == "npc" and L.LOOTSRC_NPC:format(id) or kind == "object" and L.LOOTSRC_OBJECT:format(id)
		or kind == "item" and L.LOOTSRC_ITEM:format(id) or key
end

LootSources.SourceName = SourceName

-- A section of the extra block of item tooltips: a heading and the best sources.
ns.AddItemSection(20, function(data)
	if not LootSources.db.tooltip then
		return
	end
	local id = data and ns.Number(data.id)
	local sources = id and LootSources.Sources(id)
	if not sources or #sources == 0 then
		return
	end
	local lines = { { left = L.LOOTSRC_HEADER, lc = { 1, 0.82, 0 } } }
	for i = 1, math.min(TOOLTIP_SOURCES, #sources) do
		local source = sources[i]
		local share = ("%d%%"):format(math.floor(source.drops / source.windows * 100 + 0.5))
		lines[#lines + 1] = { left = "  " .. SourceName(source.key), lc = { 1, 1, 1 }, rc = { 0.7, 0.7, 0.7 },
			right = source.windows >= MIN_WINDOWS and L.LOOTSRC_SHARE:format(share, source.drops, source.windows) or L.LOOTSRC_ONCE }
	end
	if #sources > TOOLTIP_SOURCES then
		lines[#lines + 1] = { left = "  " .. L.LOOTSRC_MORE:format(#sources - TOOLTIP_SOURCES), lc = { 0.7, 0.7, 0.7 } }
	end
	return lines
end)

---------------------------------------------------------------------------
-- Loot of the creature under the cursor
---------------------------------------------------------------------------
local shippedByCreature

local function CreatureDrops(key)
	if creatureDrops[key] then
		return creatureDrops[key]
	end
	if not shippedByCreature then
		shippedByCreature = {}
		for item, rows in pairs(ns.LootData and ns.LootData.items or {}) do
			for _, row in ipairs(rows) do
				local source = row[1]
				if source:sub(1, 4) == "npc:" then
					local entry = shippedByCreature[source] or { windows = row[3], items = {} }
					entry.items[item] = row[2]
					shippedByCreature[source] = entry
				end
			end
		end
	end
	local shipped, own = shippedByCreature[key], ns.db.lootSources[key]
	if not shipped and not (own and next(own.items)) then
		return
	end
	local rows = {}
	for item, drops in pairs(shipped and shipped.items or {}) do
		rows[#rows + 1] = { id = item, drops = drops + (own and own.items[item] or 0) }
	end
	for item, drops in pairs(own and own.items or {}) do
		if not shipped or not shipped.items[item] then
			rows[#rows + 1] = { id = item, drops = drops }
		end
	end
	table.sort(rows, function(a, b)
		if a.drops ~= b.drops then
			return a.drops > b.drops
		end
		return a.id < b.id
	end)
	rows.windows = (shipped and shipped.windows or 0) + (own and own.windows or 0)
	rows.ownWindows = own and own.windows or 0
	creatureDrops[key] = rows
	return rows
end

local function MouseoverCreatureKey(data)
	local guid = data and data.guid
	local kind, id = ns.GuidParts(guid)
	if kind ~= "Creature" or not id then
		return
	end
	local mouseover = UnitGUID("mouseover")
	if ns.Secret(mouseover) or mouseover ~= guid then
		return
	end
	local attackable = UnitCanAttack("player", "mouseover")
	if not ns.Secret(attackable) and attackable == true then
		return "npc:" .. id
	end
end

local requestedItems, pendingItems = {}, {}
local lootTooltipData, itemRefreshQueued

function LootSources.ShouldRefreshUnitLoot(data)
	return not ns.Secret(data) and data
		and (data == lootTooltipData or LootSources.db.unitLoot and MouseoverCreatureKey(data) ~= nil)
end

local function RefreshLoadedItems()
	itemRefreshQueued = false
	local tooltip = GameTooltip
	if not LootSources.db.unitLoot or not IsShiftKeyDown() or not tooltip:IsShown() or tooltip:IsForbidden() then
		return
	end
	local data = tooltip:GetPrimaryTooltipData()
	if not ns.Secret(data) and lootTooltipData == data and MouseoverCreatureKey(data) then
		ns.RefreshGameTooltip()
	end
end

local function OnItemData(_, _, itemID, success)
	if ns.Number(itemID) and pendingItems[itemID] then
		pendingItems[itemID] = nil
		if not ns.Secret(success) and success and not itemRefreshQueued then
			itemRefreshQueued = true
			ns.After("LootSources: loaded item names", 0, RefreshLoadedItems)
		end
	end
end

local function DropRate(drops, windows)
	-- The source can count several slots for one item in the same window.
	if drops > windows then
		return L.LOOTSRC_UNIT_COUNT:format(drops, windows)
	elseif windows < MIN_WINDOWS then
		return L.LOOTSRC_ONCE
	end
	local rate = drops / windows * 100
	local share = rate < 0.1 and L.LOOTSRC_UNIT_BELOW or L.LOOTSRC_UNIT_PERCENT:format(rate)
	if decimalComma then
		share = share:gsub("%.", ",")
	end
	return L.LOOTSRC_SHARE:format(share, drops, windows)
end

local function OnUnitTooltip(tooltip, data)
	if not LootSources.db.unitLoot or tooltip ~= GameTooltip or tooltip:IsForbidden()
		or not IsShiftKeyDown() or ns.Secret(data) or data ~= tooltip:GetPrimaryTooltipData() then
		return
	end
	local key = MouseoverCreatureKey(data)
	if not key then
		return
	end
	lootTooltipData = data
	wipe(pendingItems)
	local rows = CreatureDrops(key)
	ns.AddTooltipSeparator(tooltip)
	tooltip:AddLine(L.LOOTSRC_UNIT_HEADER, 1, 0.82, 0)
	if not rows then
		tooltip:AddLine(L.LOOTSRC_UNIT_EMPTY, 0.7, 0.7, 0.7)
		return
	end
	if rows.ownWindows > 0 then
		tooltip:AddLine(L.LOOTSRC_UNIT_OWN_WINDOWS:format(rows.ownWindows), 0.7, 0.7, 0.7)
	end
	for i = 1, math.min(TOOLTIP_DROPS, #rows) do
		local row = rows[i]
		local name, _, quality = C_Item.GetItemInfo(row.id)
		if type(name) ~= "string" or ns.Secret(name) or name == "" then
			name = L.LOOTSRC_UNIT_ITEM:format(row.id)
			pendingItems[row.id] = true
			if not requestedItems[row.id] then
				requestedItems[row.id] = true
				C_Item.RequestLoadItemDataByID(row.id)
			end
		end
		quality = ns.Number(quality)
		local color = quality and ITEM_QUALITY_COLORS[quality]
		tooltip:AddDoubleLine(name, DropRate(row.drops, rows.windows), color and color.r or 1, color and color.g or 1,
			color and color.b or 1, 0.7, 0.7, 0.7)
	end
	if #rows > TOOLTIP_DROPS then
		tooltip:AddLine(L.LOOTSRC_UNIT_MORE:format(#rows - TOOLTIP_DROPS), 0.7, 0.7, 0.7)
	end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
function LootSources.ExportText(sources)
	local lines = { ns.ExportTag("loot"), L.LOOTSRC_EXPORT_HEADER }
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
	ns.db.lootNames = {}
	LootSources.nameCount = 0
	LootSources.count = 0
	LootSources.merged = nil
	wipe(creatureDrops)
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function LootSources:Apply()
	self:ToggleEvent("LOOT_OPENED", self.db.record, OnLootOpened)
	self:ToggleEvent("LOOT_READY", self.db.record, OnLootReady)
	self:ToggleEvent("UNIT_SPELLCAST_SENT", self.db.record, OnSpellSent)
	self:ToggleEvent("UNIT_SPELLCAST_FAILED", self.db.record, OnSpellFailed)
	self:ToggleEvent("UNIT_SPELLCAST_INTERRUPTED", self.db.record, OnSpellFailed)
	if not self.db.record then
		lastNonCorpseCast, lastLootCastGUID = nil, nil
	end
	self:ToggleEvent("PLAYER_TARGET_CHANGED", self.db.record, OnTargetChanged)
	self:ToggleEvent("UPDATE_MOUSEOVER_UNIT", self.db.record, OnMouseoverChanged)
	self:ToggleEvent("ITEM_DATA_LOAD_RESULT", self.db.unitLoot, OnItemData)
end

function LootSources:OnInitialize()
	ns.db.lootSources = ns.db.lootSources or {}
	ns.db.lootNames = ns.db.lootNames or {}
	local names = 0
	for _ in pairs(ns.db.lootNames) do
		names = names + 1
	end
	self.nameCount = names
	local count = 0
	for _ in pairs(ns.db.lootSources) do
		count = count + 1
	end
	self.count = count
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Measured("LootSources: unit tooltip", OnUnitTooltip))
end

function LootSources:OnLogin()
	self:Apply()
end

function LootSources:OnOptionChanged()
	self:Apply()
end

function LootSources:PrintStatus()
	local windows = 0
	for _, source in pairs(ns.db.lootSources) do
		windows = windows + source.windows
	end
	ns.PrintAlways(L.LOOTSRC_STATUS, self.db.record and YES or NO, self.count, windows)
end

LootSources.options = {
	{ key = "tooltip", type = "toggle", name = L.LOOTSRC_TOOLTIP, desc = L.LOOTSRC_TOOLTIP_DESC },
	{ key = "unitLoot", type = "toggle", name = L.LOOTSRC_UNIT_TOOLTIP, desc = L.LOOTSRC_UNIT_TOOLTIP_DESC },
	{ key = "record", type = "toggle", name = L.LOOTSRC_RECORD, desc = L.LOOTSRC_RECORD_DESC },
}

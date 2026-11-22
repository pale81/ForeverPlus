-- Upgrades: the best known loot for each equipment slot. Candidates are the items of the shipped and recorded loot
-- (boss rolls and corpses) that the character can equip; they are rated like the green arrows (better than what is
-- worn and usable by the class; grey while only the level is missing). Opened from a button on the character
-- window or with /fp besser.
local _, ns = ...
local L = ns.L

local Upgrades = ns:NewModule("Upgrades", {
	title = L.UPGRADES_TITLE,
	order = 12.6,
	defaults = { enabled = true, button = true },
})

local PER_SLOT = 3
local candidates -- { { id, equipLoc }, ... }, built once
local requested, pendingRefresh = {}, false
local button, owner

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- rows: { { id, slot, gain, state }, ... } with slot an equipLoc. Keeps the best `perSlot` upgrades of each slot
-- (state true or "later"), highest gain first; slots in the order of `order`.
function Upgrades.Pick(rows, perSlot, order)
	local bySlot = {}
	for _, row in ipairs(rows) do
		if row.state and row.gain and row.gain > 0 then
			bySlot[row.slot] = bySlot[row.slot] or {}
			table.insert(bySlot[row.slot], row)
		end
	end
	local result = {}
	for _, slot in ipairs(order) do
		local list = bySlot[slot]
		if list then
			table.sort(list, function(a, b)
				if (a.state == true) ~= (b.state == true) then return a.state == true end
				if a.gain ~= b.gain then return a.gain > b.gain end
				return a.id < b.id
			end)
			for index = perSlot + 1, #list do list[index] = nil end
			result[#result + 1] = { slot = slot, rows = list }
		end
	end
	return result
end

-- Equipment locations in the order of the character window.
Upgrades.ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE",
	"INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
	"INVTYPE_2HWEAPON", "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
	"INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" }

---------------------------------------------------------------------------
-- Candidates and sources
---------------------------------------------------------------------------
local bossOf -- encounter ID -> boss name (in the client language), instance name

local function BossNames()
	if bossOf then return bossOf end
	bossOf = {}
	local german = GetLocale() == "deDE"
	for _, entry in pairs(ns.DungeonJournalData and ns.DungeonJournalData.instances or {}) do
		local instance = german and entry.name[2] or entry.name[1]
		for _, boss in ipairs(entry.bosses or {}) do
			bossOf[boss[1]] = { german and boss[3] or boss[2], instance }
		end
	end
	return bossOf
end

-- The best place to get an item: encounter rolls first, then the corpse with the best record.
local function BestSource(id)
	local best
	for encounter, entry in pairs(ns.LootData and ns.LootData.encounters or {}) do
		for _, row in ipairs(entry[2]) do
			if row[1] == id and (not best or row[2] / entry[1] > best.share) then
				local boss = BossNames()[encounter]
				best = { share = row[2] / entry[1], drops = row[2], windows = entry[1],
					name = boss and L.UPGRADES_BOSS:format(boss[1], boss[2]) or L.UPGRADES_ENCOUNTER:format(encounter) }
			end
		end
	end
	if best then return best end
	local sources = ns:GetModule("LootSources")
	local first = sources.Sources(id)[1]
	if first then
		return { share = first.drops / first.windows, drops = first.drops, windows = first.windows,
			name = sources.SourceName(first.key) }
	end
end

local function Candidates()
	if candidates then return candidates end
	candidates = {}
	local seen = {}
	local function Add(id)
		if seen[id] then return end
		seen[id] = true
		local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
		if type(equipLoc) == "string" and equipLoc ~= "" and ns.EquipSlots(equipLoc) then
			candidates[#candidates + 1] = { id = id, slot = equipLoc }
		end
	end
	for id in pairs(ns.LootData and ns.LootData.items or {}) do Add(id) end
	for _, entry in pairs(ns.LootData and ns.LootData.encounters or {}) do
		for _, row in ipairs(entry[2]) do Add(row[1]) end
	end
	for _, entry in pairs(ns.db.lootSources or {}) do
		for id in pairs(type(entry) == "table" and type(entry.items) == "table" and entry.items or {}) do Add(id) end
	end
	return candidates
end

-- Rated candidates; the second value counts the items whose data is still loading.
function Upgrades.Rate()
	local rows, loading = {}, 0
	for _, candidate in ipairs(Candidates()) do
		local _, link = C_Item.GetItemInfo(candidate.id)
		if type(link) ~= "string" or ns.Secret(link) then
			loading = loading + 1
			if not requested[candidate.id] then
				requested[candidate.id] = true
				C_Item.RequestLoadItemDataByID(candidate.id)
			end
		else
			local state = ns.ItemLinkUpgradeState(link)
			if state == nil then
				loading = loading + 1
			elseif state then
				rows[#rows + 1] = { id = candidate.id, slot = candidate.slot, link = link, state = state,
					gain = ns.ItemUpgradeGain(link) }
			end
		end
	end
	return rows, loading
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Build()
	local rows, loading = Upgrades.Rate()
	local items = {}
	for _, group in ipairs(Upgrades.Pick(rows, PER_SLOT, Upgrades.ORDER)) do
		items[#items + 1] = { text = _G[group.slot] or group.slot }
		for _, row in ipairs(group.rows) do
			local name, _, quality, _, minLevel = C_Item.GetItemInfo(row.id)
			local source = BestSource(row.id)
			local share = source and ("%d%%"):format(math.floor(source.share * 100 + 0.5)) or ""
			local text = name or row.link
			if row.state == "later" then text = text .. "  |cff999999" .. L.UPGRADES_LEVEL:format(ns.Number(minLevel, 0)) .. "|r" end
			items[#items + 1] = {
				text = text, icon = C_Item.GetItemIconByID(row.id), quality = ns.Number(quality), right = share,
				tooltip = function(tooltip)
					tooltip:SetHyperlink(row.link)
					if source then
						tooltip:AddLine(" ")
						tooltip:AddLine(L.UPGRADES_SOURCE:format(source.name, share, source.drops, source.windows), 1, 0.82, 0, true)
					end
				end,
				onClick = function()
					if HandleModifiedItemClick then HandleModifiedItemClick(row.link) end
				end,
			}
		end
	end
	local title = loading > 0 and L.UPGRADES_LOADING:format(loading) or L.UPGRADES_TITLE
	return { title = title, items = items, empty = loading > 0 and L.UPGRADES_WAIT or L.UPGRADES_NONE, width = 420 }
end

function Upgrades.Open(anchor)
	if not Upgrades.db.enabled then return end
	owner = anchor or owner or UIParent
	Upgrades.popup = ns.ShowPopupList(owner, Build, "Upgrades")
	Upgrades:ToggleEvent("ITEM_DATA_LOAD_RESULT", true, function(_, _, itemID)
		if not ns.Number(itemID) or not requested[itemID] or pendingRefresh then return end
		pendingRefresh = true
		ns.After("Upgrades: refresh", 0.5, function()
			pendingRefresh = false
			if Upgrades.popup and Upgrades.popup:IsShown() then
				Upgrades.popup = ns.ShowPopupList(owner, Build, "Upgrades")
			else
				Upgrades:ToggleEvent("ITEM_DATA_LOAD_RESULT", false)
			end
		end)
	end)
end

local function CreateButton()
	local slot = _G.CharacterMainHandSlot
	if button or not slot then return end
	button = CreateFrame("Button", "ForeverPlusUpgradesButton", _G.PaperDollFrame)
	button:SetSize(24, 24)
	button:SetPoint("RIGHT", slot, "LEFT", -8, 0)
	button:SetNormalAtlas("bags-greenarrow")
	button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	button:SetScript("OnClick", ns.Measured("Upgrades: button", function(self) Upgrades.Open(self) end))
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.UPGRADES_TITLE, 1, 1, 1)
		GameTooltip:AddLine(L.UPGRADES_BUTTON_DESC, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

function Upgrades:OnOptionChanged()
	if button then button:SetShown(self.db.enabled and self.db.button) end
end

function Upgrades:OnLogin()
	CreateButton()
	self:OnOptionChanged()
end

Upgrades.options = {
	{ key = "enabled", type = "toggle", name = L.UPGRADES_ENABLE, desc = L.UPGRADES_ENABLE_DESC },
	{ key = "button", type = "toggle", name = L.UPGRADES_BUTTON, desc = L.UPGRADES_BUTTON_DESC, parent = "enabled" },
	{ type = "button", name = L.UPGRADES_TITLE, text = L.UPGRADES_OPEN, func = function() Upgrades.Open() end },
}

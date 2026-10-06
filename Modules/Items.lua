-- Items: junk selling and marking, auto repair, quest reward value,
-- upgrade arrows in bags and fast looting.
local _, ns = ...
local L = ns.L

local Items = ns:NewModule("Items", {
	title = L.ITEMS_TITLE,
	order = 4,
	defaults = {
		autoSell = true,
		autoRepair = true,
		repairGuild = true,
		questReward = true,
		upgradeArrow = true,
		fastLoot = true,
		sellMessage = true,
		repairMessage = true,
		markMessage = true,
		destroyPrompt = true,
		autoBind = false,
		rollCounts = true,
		junkButton = "MiddleButton",
		junk = {},
		keep = {}, -- grey items the player unmarked: never sold
	},
})

-- Key binding labels (Bindings.xml).
BINDING_HEADER_FOREVERPLUS = "ForeverPlus"
BINDING_NAME_FOREVERPLUS_TOGGLEJUNK = L.ITEMS_BINDING_JUNK

-- Each chat message can be switched off next to its function.
local function Report(key, ...)
	if Items.db[key] then
		ns.Print(...)
	end
end

local SELL_BATCH = 10
local SELL_INTERVAL = 0.2

---------------------------------------------------------------------------
-- Junk marking (middle mouse button in bags, configurable)
---------------------------------------------------------------------------
-- Items with a random suffix ("of the Monkey", "of Frost Resistance") share
-- one item ID; they are told apart by the suffix in the link. Key: the item ID
-- (number) or "itemID:suffixID" (string, stored with the link for the list).
local function SuffixID(link)
	local itemString = link and link:match("item:([%-%d:]+)")
	if not itemString then
		return
	end
	local fields = { strsplit(":", itemString) }
	local suffix = tonumber(fields[7])
	return suffix and suffix ~= 0 and suffix or nil
end

local function JunkKey(info)
	local suffix = SuffixID(info.hyperlink)
	if suffix then
		return ("%d:%d"):format(info.itemID, suffix), info.hyperlink
	end
	return info.itemID, true
end

local function IsMarked(info)
	return info.itemID and Items.db.junk[(JunkKey(info))] and true or false
end

local function IsKept(info)
	return info.itemID and Items.db.keep[(JunkKey(info))] and true or false
end

-- Grey items count as junk unless kept; other items only when marked.
local function IsJunkItem(info)
	if info.quality == Enum.ItemQuality.Poor then
		return not IsKept(info)
	end
	return IsMarked(info)
end

local function IsJunk(info)
	if not info or info.hasNoValue or info.isLocked then
		return false
	end
	return IsJunkItem(info)
end

---------------------------------------------------------------------------
-- Upgrade arrows
---------------------------------------------------------------------------
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_2HWEAPON = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONMAINHAND = { INVSLOT_MAINHAND }, INVTYPE_WEAPONOFFHAND = { INVSLOT_OFFHAND },
	INVTYPE_SHIELD = { INVSLOT_OFFHAND }, INVTYPE_HOLDABLE = { INVSLOT_OFFHAND },
	INVTYPE_RANGED = { INVSLOT_RANGED }, INVTYPE_RANGEDRIGHT = { INVSLOT_RANGED },
	INVTYPE_THROWN = { INVSLOT_RANGED }, INVTYPE_RELIC = { INVSLOT_RANGED },
}
local ONE_HAND_SLOTS = { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
local MAIN_HAND_SLOT = { INVSLOT_MAINHAND }

local upgradeCache = {}    -- hyperlink -> bool

-- Profession tools (fishing poles, mining picks, …) are never shown as upgrades.
local IGNORED_WEAPONS = {
	[Enum.ItemWeaponSubclass.Fishingpole] = true,
	[Enum.ItemWeaponSubclass.Generic] = true,
}

local ARMOR = Enum.ItemArmorSubclass
-- Best armor type per class; classes learning mail/plate switch at level 40.
local ARMOR_TYPE = {
	WARRIOR = { ARMOR.Mail, ARMOR.Plate }, PALADIN = { ARMOR.Mail, ARMOR.Plate },
	HUNTER = { ARMOR.Leather, ARMOR.Mail }, SHAMAN = { ARMOR.Leather, ARMOR.Mail },
	ROGUE = { ARMOR.Leather }, DRUID = { ARMOR.Leather },
	PRIEST = { ARMOR.Cloth }, MAGE = { ARMOR.Cloth }, WARLOCK = { ARMOR.Cloth },
}

-- Stat weights per point, derived from the classic game mechanics (e.g. 1
-- strength = 2 attack power for warriors, 1 % hit/crit ≈ 15 attack power,
-- 1 weapon DPS ≈ 14 attack power). Rough on purpose: they only have to
-- tell useful from useless stats for the specialization.
local MELEE = { STR = 2, AGI = 1.2, STA = 0.3, AP = 1, HIT = 15, CRIT = 15, ARMOR = 0.01, DPS = 14, RDPS = 2 }
local AGI_MELEE = { STR = 1, AGI = 1.8, STA = 0.3, AP = 1, HIT = 15, CRIT = 15, ARMOR = 0.01, DPS = 14, RDPS = 2 }
local TANK = { STR = 1, AGI = 1, STA = 1.5, AP = 0.4, HIT = 8, CRIT = 4, DEF = 1.5, DODGE = 12, PARRY = 12, BLOCK = 8, BVAL = 0.5, ARMOR = 0.1, DPS = 5, RDPS = 1 }
local HEALER = { INT = 1, SPI = 0.6, STA = 0.3, SP = 0.8, HEAL = 1, SCRIT = 8, MP5 = 2, ARMOR = 0.005 }
local CASTER = { INT = 0.6, SPI = 0.3, STA = 0.3, SP = 1, SHIT = 14, SCRIT = 12, MP5 = 1, ARMOR = 0.005 }
local WEIGHTS = {
	WARRIOR = { MELEE, MELEE, TANK },
	PALADIN = { HEALER, { STA = 1.5, STR = 0.8, AGI = 0.8, INT = 0.5, SP = 0.8, DEF = 1.5, DODGE = 12, PARRY = 12, BLOCK = 8, BVAL = 0.5, ARMOR = 0.1, DPS = 5 },
		{ STR = 2, AGI = 1, STA = 0.3, INT = 0.3, AP = 1, SP = 0.3, HIT = 15, CRIT = 15, ARMOR = 0.01, DPS = 14 } },
	HUNTER = { AGI = 2, STA = 0.3, INT = 0.4, AP = 0.2, RAP = 1, HIT = 15, CRIT = 15, ARMOR = 0.01, DPS = 3, RDPS = 14 },
	ROGUE = AGI_MELEE,
	PRIEST = { HEALER, HEALER, { INT = 0.6, SPI = 0.4, STA = 0.4, SP = 1, SHIT = 12, SCRIT = 8, MP5 = 1 } },
	SHAMAN = { { INT = 0.7, SPI = 0.1, STA = 0.3, SP = 1, SHIT = 12, SCRIT = 12, MP5 = 1.5, ARMOR = 0.005 },
		{ STR = 2, AGI = 1.3, STA = 0.3, INT = 0.3, AP = 1, HIT = 15, CRIT = 15, ARMOR = 0.01, DPS = 14 },
		{ INT = 1, SPI = 0.2, STA = 0.3, SP = 0.8, HEAL = 1, SCRIT = 8, MP5 = 2, ARMOR = 0.005 } },
	MAGE = CASTER,
	WARLOCK = { INT = 0.4, SPI = 0.2, STA = 0.6, SP = 1, SHIT = 14, SCRIT = 8 },
	DRUID = { CASTER, { STR = 2, AGI = 1.5, STA = 0.8, AP = 1, HIT = 15, CRIT = 15, DEF = 0.5, DODGE = 10, ARMOR = 0.05 }, HEALER },
}
-- Specialization used before talents are chosen (low level).
local DEFAULT_SPEC = { WARRIOR = 1, PALADIN = 3, PRIEST = 3, SHAMAN = 2, DRUID = 1 }

-- Maps the keys of C_Item.GetItemStats to the short names above.
local STAT_PATTERNS = {
	{ "RESISTANCE0", "ARMOR" }, { "DAMAGE_PER_SECOND", "DPS" },
	{ "STRENGTH", "STR" }, { "AGILITY", "AGI" }, { "STAMINA", "STA" }, { "INTELLECT", "INT" }, { "SPIRIT", "SPI" },
	{ "RANGED_ATTACK_POWER", "RAP" }, { "ATTACK_POWER", "AP" },
	{ "HEALING", "HEAL" }, { "SPELL_POWER", "SP" }, { "SPELL_DAMAGE", "SP" },
	{ "HIT_SPELL", "SHIT" }, { "CRIT_SPELL", "SCRIT" }, { "HIT", "HIT" }, { "CRIT", "CRIT" },
	{ "MANA_REGENERATION", "MP5" }, { "POWER_REGEN0", "MP5" },
	{ "DEFENSE", "DEF" }, { "DODGE", "DODGE" }, { "PARRY", "PARRY" }, { "BLOCK_VALUE", "BVAL" }, { "BLOCK", "BLOCK" },
}
local statNames = {} -- GetItemStats key -> short name (false = unweighted)

local function StatName(key)
	local name = statNames[key]
	if name == nil then
		name = false
		for _, entry in ipairs(STAT_PATTERNS) do
			if key:find(entry[1], 1, true) then
				name = entry[2]
				break
			end
		end
		statNames[key] = name
	end
	return name
end

local weights -- of the current class/specialization, cleared on spec change
local _, playerClass = UnitClass("player")

local function CurrentSpecIndex()
	local index = C_SpecializationInfo.GetSpecialization()
	if index and index > 0 then
		return index
	end
	-- Talent tree with the most points (classic talents).
	local best, bestPoints = nil, 0
	for i = 1, 4 do
		local specID, _, _, _, _, _, points = C_SpecializationInfo.GetSpecializationInfo(i)
		if specID and specID ~= 0 and points and points > bestPoints then
			best, bestPoints = i, points
		end
	end
	return best
end

local function GetWeights()
	if weights then
		return weights
	end
	local classWeights = WEIGHTS[playerClass] or MELEE
	if classWeights[1] then
		local index = CurrentSpecIndex() or DEFAULT_SPEC[playerClass] or 1
		local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(index)
		-- Druids have four specializations in some clients; the role decides.
		if playerClass == "DRUID" then
			index = role == "HEALER" and 3 or (index == 1 and 1 or 2)
		end
		classWeights = classWeights[index] or classWeights[1]
	end
	weights = classWeights
	return weights
end

-- Weighted value of an item; weapon DPS counts per slot (melee/ranged).
local function Score(link, ranged)
	local w = GetWeights()
	local score = 0
	for key, value in pairs(C_Item.GetItemStats(link) or {}) do
		local name = StatName(key)
		if name == "DPS" and ranged then
			name = "RDPS"
		end
		if name and w[name] then
			score = score + w[name] * value
		end
	end
	return score
end

local function IsRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

-- Red lines in the item tooltip mean the player cannot use it (class, armor type, level).
local function CanUse(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	if not data or not data.lines then
		return false
	end
	for _, line in ipairs(data.lines) do
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			return false
		end
	end
	return true
end

local function IsBestArmorType(classID, subClassID, equipLoc)
	if classID ~= Enum.ItemClass.Armor or equipLoc == "INVTYPE_CLOAK"
		or subClassID < ARMOR.Cloth or subClassID > ARMOR.Plate then
		return true -- jewellery, cloaks, shields, off hands
	end
	local types = ARMOR_TYPE[playerClass]
	if not types then
		return true
	end
	local best = UnitLevel("player") >= 40 and types[2] or types[1]
	return subClassID == best
end

-- Returns the link of the equipped item, nil for an empty slot, false while loading.
local function EquippedLink(invSlot)
	local location = ItemLocation:CreateFromEquipmentSlot(invSlot)
	if not C_Item.DoesItemExist(location) then
		return nil
	end
	local link = GetInventoryItemLink("player", invSlot)
	if not link or not C_Item.IsItemDataCachedByID(link) then
		return false
	end
	return link
end

local function EquippedScore(invSlot)
	local link = EquippedLink(invSlot)
	if link == false then
		return false
	end
	return link and Score(link, invSlot == INVSLOT_RANGED) or 0
end

local function IsTwoHand(link)
	return link and select(4, C_Item.GetItemInfoInstant(link)) == "INVTYPE_2HWEAPON"
end

-- An upgrade is the best armor type for the class, usable, and has a higher
-- weighted value (stats of the current specialization) than the weakest
-- equipped item it could replace. Unknown data never shows an arrow.
local function IsUpgrade(bag, slot, link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end
	local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
	local slots = EQUIP_SLOTS[equipLoc]
	if equipLoc == "INVTYPE_WEAPON" then
		slots = CanDualWield() and ONE_HAND_SLOTS or MAIN_HAND_SLOT
	end
	if not slots or (classID == Enum.ItemClass.Weapon and IGNORED_WEAPONS[subClassID])
		or not IsBestArmorType(classID, subClassID, equipLoc) then
		upgradeCache[link] = false
		return false
	end
	if not C_Item.IsItemDataCachedByID(link) then
		return false
	end

	local equippedScore
	if equipLoc == "INVTYPE_2HWEAPON" then
		-- Replaces main and off hand together.
		local mainScore = EquippedScore(INVSLOT_MAINHAND)
		local offScore = EquippedScore(INVSLOT_OFFHAND)
		if mainScore == false or offScore == false then
			return false
		end
		equippedScore = mainScore + offScore
	elseif slots[1] == INVSLOT_OFFHAND and IsTwoHand(EquippedLink(INVSLOT_MAINHAND)) then
		-- No off hand next to a two-hand weapon.
		upgradeCache[link] = false
		return false
	else
		for _, invSlot in ipairs(slots) do
			local value = EquippedScore(invSlot)
			if value == false then
				return false
			end
			if not equippedScore or value < equippedScore then
				equippedScore = value
			end
		end
	end

	local result = Score(link, slots[1] == INVSLOT_RANGED) > equippedScore + 0.01 and CanUse(bag, slot)
	upgradeCache[link] = result
	return result
end

---------------------------------------------------------------------------
-- Bag button decoration
---------------------------------------------------------------------------
local function UpdateButton(button)
	local bag, slot = button:GetBagID(), button:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)

	if button.JunkIcon then
		-- Coin on everything that will be sold: grey items (unless kept) and marked items.
		local show = info and not info.hasNoValue and IsJunkItem(info)
		button.JunkIcon:SetShown(show and true or false)
	end

	if button.UpgradeIcon then
		local show = false
		if Items.db.upgradeArrow and info and info.hyperlink and C_Item.IsEquippableItem(info.hyperlink) then
			show = IsUpgrade(bag, slot, info.hyperlink)
		end
		button.UpgradeIcon:SetShown(show)
	end
end

local function UpdateContainerFrame(frame)
	if not frame:IsShown() then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		UpdateButton(button)
	end
end

local function UpdateAllBags()
	if ContainerFrameCombinedBags then
		UpdateContainerFrame(ContainerFrameCombinedBags)
	end
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		UpdateContainerFrame(frame)
	end
end

local hookedButtons = {}

local function ToggleJunk(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then
		return
	end
	-- Grey items are junk by default: toggling stores an exception instead.
	local list = info.quality == Enum.ItemQuality.Poor and Items.db.keep or Items.db.junk
	local isGrey = list == Items.db.keep
	local key, value = JunkKey(info)
	if list[key] then
		list[key] = nil
	else
		list[key] = value
	end
	Report("markMessage", IsJunkItem(info) and L.ITEMS_MARKED or L.ITEMS_UNMARKED, info.hyperlink)
	if isGrey then
		Items.db.junk[key] = nil
	end
	UpdateAllBags()
end

-- Marks/unmarks junk with the configured mouse button (middle button by default).
-- OnMouseUp also fires for buttons the item button is not registered to click with.
local function OnItemMouseUp(button, mouseButton)
	if mouseButton == Items.db.junkButton and button:IsMouseOver() then
		ToggleJunk(button:GetBagID(), button:GetID())
	end
end

-- Key binding (Bindings.xml): toggles the bag item under the mouse.
function ForeverPlus_ToggleJunkUnderMouse()
	local frame = GetMouseFoci()[1]
	while frame and not frame:IsForbidden() do
		if frame.GetBagID and frame.GetID then
			local bag = frame:GetBagID()
			if bag then
				ToggleJunk(bag, frame:GetID())
			end
			return
		end
		frame = frame:GetParent()
	end
end

---------------------------------------------------------------------------
-- Junk list: every marked item, click removes the mark
---------------------------------------------------------------------------
local function KeyItemID(key)
	return tonumber(key) or tonumber(tostring(key):match("^(%d+)"))
end

local function JunkEntryText(key, value)
	local itemID = KeyItemID(key)
	local icon = itemID and C_Item.GetItemIconByID(itemID)
	if type(value) == "string" then
		-- Suffix items: the stored link carries the full coloured name.
		local name = value:match("%[(.-)%]") or value
		return icon and ("|T%d:16:16|t %s"):format(icon, value) or value, name
	end
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		name = ("item:%d"):format(itemID)
	end
	local quality = C_Item.GetItemQualityByID(itemID)
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		name = CreateColor(r, g, b):WrapTextInColorCode(name)
	end
	return icon and ("|T%d:16:16|t %s"):format(icon, name) or name, C_Item.GetItemNameByID(itemID) or ""
end

local function AddJunkEntries(root, list, onRemove)
	local entries = {}
	for key, value in pairs(list) do
		local text, sortName = JunkEntryText(key, value)
		entries[#entries + 1] = { id = key, value = value, text = text, sortName = sortName }
	end
	table.sort(entries, function(a, b)
		return a.sortName < b.sortName
	end)
	for _, entry in ipairs(entries) do
		local button = root:CreateButton(entry.text, function()
			list[entry.id] = nil
			onRemove(entry.id, entry.value)
			return MenuResponse.CloseAll
		end)
		button:SetTooltip(function(tooltip)
			if type(entry.value) == "string" then
				tooltip:SetHyperlink(entry.value)
			else
				tooltip:SetItemByID(KeyItemID(entry.id))
			end
			GameTooltip_AddInstructionLine(tooltip, L.ITEMS_JUNK_REMOVE_HINT)
		end)
	end
	return #entries
end

function Items:ShowJunkMenu(owner)
	-- Menus do not rebuild their entries; reopen after each removal.
	local function Reopen()
		UpdateAllBags()
		C_Timer.After(0, function()
			self:ShowJunkMenu(owner)
		end)
	end
	MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
		root:SetScrollMode(400)
		root:CreateTitle(L.ITEMS_JUNK_LIST)
		-- A grey item taken off the junk list would still be sold as grey;
		-- it moves to the kept list instead.
		local marked = AddJunkEntries(root, self.db.junk, function(key, value)
			if C_Item.GetItemQualityByID(KeyItemID(key)) == Enum.ItemQuality.Poor then
				self.db.keep[key] = value
			end
			Reopen()
		end)
		if next(self.db.keep) then
			root:CreateDivider()
			root:CreateTitle(L.ITEMS_JUNK_KEPT)
		end
		local kept = AddJunkEntries(root, self.db.keep, Reopen)
		if marked + kept == 0 then
			root:CreateTitle(L.ITEMS_JUNK_NONE)
			return
		end
		root:CreateDivider()
		root:CreateButton(L.ITEMS_CLEAR_JUNK, function()
			wipe(self.db.junk)
			wipe(self.db.keep)
			UpdateAllBags()
		end)
	end)
end

local function PostUpdateItems(frame)
	for _, button in frame:EnumerateValidItems() do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnMouseUp", OnItemMouseUp)
		end
		UpdateButton(button)
	end
end

local function HookContainerFrames()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", PostUpdateItems)
		end
	end
end

---------------------------------------------------------------------------
-- Merchant: sell junk and repair
---------------------------------------------------------------------------
local sellTicker, soldValue
local merchantOpen = false

local function StopSelling()
	if sellTicker then
		sellTicker:Cancel()
		sellTicker = nil
	end
	if soldValue and soldValue > 0 then
		Report("sellMessage", L.ITEMS_SOLD, GetMoneyString(soldValue, true))
	end
	soldValue = nil
end

local function SellBatch()
	-- MERCHANT_SHOW can arrive before the merchant window is shown.
	if not merchantOpen then
		StopSelling()
		return
	end
	local sold = 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsJunk(info) then
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 then
					C_Container.UseContainerItem(bag, slot)
					soldValue = soldValue + price * info.stackCount
					sold = sold + 1
					if sold >= SELL_BATCH then
						return
					end
				end
			end
		end
	end
	StopSelling()
end

local function Repair()
	if not CanMerchantRepair() then
		return
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost <= 0 then
		return
	end
	if Items.db.repairGuild and IsInGuild() and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney()
		if limit == -1 or limit >= cost then
			RepairAllItems(true)
			Report("repairMessage", L.ITEMS_REPAIRED_GUILD, GetMoneyString(cost, true))
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems(false)
		Report("repairMessage", L.ITEMS_REPAIRED, GetMoneyString(cost, true))
	else
		Report("repairMessage", L.ITEMS_REPAIR_NO_MONEY)
	end
end

function Items:MERCHANT_SHOW()
	merchantOpen = true
	if self.db.autoRepair then
		Repair()
	end
	if self.db.autoSell and not sellTicker then
		soldValue = 0
		SellBatch()
		if soldValue then
			sellTicker = C_Timer.NewTicker(SELL_INTERVAL, SellBatch)
		end
	end
end

function Items:MERCHANT_CLOSED()
	merchantOpen = false
	StopSelling()
end

---------------------------------------------------------------------------
-- Quest rewards: highlight the most valuable choice
---------------------------------------------------------------------------
local rewardMarks = {}

local function GetRewardMark(button)
	local mark = rewardMarks[button]
	if not mark then
		mark = CreateFrame("Frame", nil, button)
		mark:SetAllPoints(button.Icon or button.icon or button)
		mark:SetFrameLevel(button:GetFrameLevel() + 5)
		local glow = mark:CreateTexture(nil, "OVERLAY")
		glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1, 0.82, 0)
		glow:SetPoint("CENTER")
		glow:SetSize(button:GetHeight() * 1.9, button:GetHeight() * 1.9)
		-- Same coin as the junk mark in the bags.
		local coin = mark:CreateTexture(nil, "OVERLAY", nil, 2)
		coin:SetAtlas("bags-junkcoin", true)
		coin:SetPoint("TOPLEFT", 1, 0)
		rewardMarks[button] = mark
	end
	return mark
end

local function HideRewardMarks()
	for _, mark in pairs(rewardMarks) do
		mark:Hide()
	end
end

local function MarkBestReward()
	HideRewardMarks()
	if not Items.db.questReward or QuestInfoFrame.questLog then
		return
	end
	local numChoices = GetNumQuestChoices()
	if numChoices < 2 then
		return
	end
	local bestIndex, bestValue, waiting = nil, 0, false
	for i = 1, numChoices do
		local link = GetQuestItemLink("choice", i)
		if link then
			local price = select(11, C_Item.GetItemInfo(link))
			if price == nil then
				waiting = true
				Item:CreateFromItemLink(link):ContinueOnItemLoad(MarkBestReward)
			else
				local _, _, count = GetQuestItemInfo("choice", i)
				local value = price * max(count or 1, 1)
				if value > bestValue then
					bestIndex, bestValue = i, value
				end
			end
		end
	end
	if waiting or not bestIndex then
		return
	end
	local rewardsFrame = QuestInfoFrame.rewardsFrame
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button:IsShown() and button.type == "choice" and button.objectType == "item" and button:GetID() == bestIndex then
			GetRewardMark(button):Show()
			break
		end
	end
end

---------------------------------------------------------------------------
-- Fast loot: take every slot as soon as the loot window is ready
---------------------------------------------------------------------------
local lastLoot = 0

function Items:LOOT_READY()
	local now = GetTime()
	if now - lastLoot < 0.3 then
		return
	end
	lastLoot = now
	if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
		for i = GetNumLootItems(), 1, -1 do
			LootSlot(i)
		end
	end
end

---------------------------------------------------------------------------
-- Full bags: offer the cheapest item for destruction. The item is only picked
-- up; Blizzard's own delete confirmation does the rest (deleting is
-- restricted for addons).
---------------------------------------------------------------------------
local PROMPT_COOLDOWN = 60
local lastPrompt = 0
local destroyDialog

local function FindCheapestItem()
	local best
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and not info.hasNoValue and not info.isLocked then
				local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 and not (quest and (quest.isQuestItem or quest.questID)) then
					local value = price * info.stackCount
					if not best or value < best.value then
						best = { bag = bag, slot = slot, value = value, link = info.hyperlink, icon = info.iconFileID, count = info.stackCount }
					end
				end
			end
		end
	end
	return best
end

local function CreateDestroyDialog()
	local frame = CreateFrame("Frame", "ForeverPlusDestroyDialog", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(360, 150)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame.TitleText:SetText(L.ITEMS_BAGS_FULL)
	tinsert(UISpecialFrames, frame:GetName())

	frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	frame.Icon:SetSize(36, 36)
	frame.Icon:SetPoint("TOPLEFT", 18, -36)
	frame.Item = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.Item:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 10, -2)
	frame.Item:SetPoint("RIGHT", -16, 0)
	frame.Item:SetJustifyH("LEFT")
	frame.Value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Value:SetPoint("TOPLEFT", frame.Item, "BOTTOMLEFT", 0, -4)
	frame.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Hint:SetPoint("TOPLEFT", frame.Icon, "BOTTOMLEFT", 0, -8)
	frame.Hint:SetPoint("RIGHT", -16, 0)
	frame.Hint:SetJustifyH("LEFT")
	frame.Hint:SetText(L.ITEMS_DESTROY_HINT)

	frame.Accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Accept:SetSize(150, 22)
	frame.Accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
	frame.Accept:SetText(L.ITEMS_DESTROY_PICKUP)
	frame.Accept:SetScript("OnClick", function()
		local entry = frame.entry
		frame:Hide()
		if entry and not InCombatLockdown() then
			ClearCursor()
			C_Container.PickupContainerItem(entry.bag, entry.slot)
		end
	end)
	frame.Cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Cancel:SetSize(150, 22)
	frame.Cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
	frame.Cancel:SetText(CANCEL)
	frame.Cancel:SetScript("OnClick", function()
		frame:Hide()
	end)
	frame:Hide()
	return frame
end

local function OfferDestroy()
	local now = GetTime()
	if now - lastPrompt < PROMPT_COOLDOWN or InCombatLockdown() then
		return
	end
	local entry = FindCheapestItem()
	if not entry then
		return
	end
	lastPrompt = now
	destroyDialog = destroyDialog or CreateDestroyDialog()
	destroyDialog.entry = entry
	destroyDialog.Icon:SetTexture(entry.icon)
	destroyDialog.Item:SetText(entry.count > 1 and ("%s x%d"):format(entry.link, entry.count) or entry.link)
	destroyDialog.Value:SetText(L.ITEMS_DESTROY_VALUE:format(GetMoneyString(entry.value, true)))
	destroyDialog:Show()
end

function Items:UI_ERROR_MESSAGE(_, _, message)
	if issecretvalue and issecretvalue(message) then
		return
	end
	if message == ERR_INV_FULL then
		OfferDestroy()
	end
end

---------------------------------------------------------------------------
-- Bind on pickup: confirm automatically (loot window and group rolls)
---------------------------------------------------------------------------
local function HidePopup(which)
	C_Timer.After(0, function()
		StaticPopup_Hide(which)
	end)
end

function Items:LOOT_BIND_CONFIRM(_, slot)
	ConfirmLootSlot(slot)
	HidePopup("LOOT_BIND")
end

function Items:CONFIRM_LOOT_ROLL(_, rollID, rollType)
	ConfirmLootRoll(rollID, rollType)
	HidePopup("CONFIRM_LOOT_ROLL")
end

---------------------------------------------------------------------------
-- Group loot: number of need/greed/pass choices on the buttons, names on hover
---------------------------------------------------------------------------
local ROLL_BUTTONS = {
	NeedButton = { [Enum.EncounterLootDropRollState.NeedMainSpec] = true, [Enum.EncounterLootDropRollState.NeedOffSpec] = true },
	GreedButton = { [Enum.EncounterLootDropRollState.Greed] = true },
	TransmogButton = { [Enum.EncounterLootDropRollState.Transmog] = true },
	PassButton = { [Enum.EncounterLootDropRollState.Pass] = true },
}
local rollNames = {}  -- button -> { names }
local rollLabels = {} -- button -> font string
local rollHooked = {}

local function ItemIDOfLink(link)
	return link and not (issecretvalue and issecretvalue(link)) and C_Item.GetItemInfoInstant(link)
end

local function ShowRollNames(button)
	local names = rollNames[button]
	if not Items.db.rollCounts or not names or #names == 0 or GameTooltip:GetOwner() ~= button then
		return
	end
	for _, name in ipairs(names) do
		GameTooltip:AddLine(name, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function SetRollCount(button, names)
	if not rollHooked[button] then
		rollHooked[button] = true
		button:HookScript("OnEnter", ShowRollNames)
	end
	local label = rollLabels[button]
	if not label then
		label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
		rollLabels[button] = label
	end
	rollNames[button] = names
	label:SetText(#names > 0 and #names or "")
	label:SetShown(Items.db.rollCounts)
end

local function ResetRollFrame(frame)
	local container = frame.LootButtonContainer or frame
	for key in pairs(ROLL_BUTTONS) do
		local button = container[key]
		if button then
			SetRollCount(button, {})
		end
	end
end

function Items:LOOT_HISTORY_UPDATE_DROP(_, encounterID, lootListKey)
	local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
	local itemID = info and ItemIDOfLink(info.itemHyperlink)
	if not itemID then
		return
	end
	for index = 1, 4 do
		local frame = _G["GroupLootFrame" .. index]
		if frame and frame:IsShown() and frame.rollID and ItemIDOfLink(GetLootRollItemLink(frame.rollID)) == itemID then
			local container = frame.LootButtonContainer or frame
			for key, states in pairs(ROLL_BUTTONS) do
				local button = container[key]
				if button then
					local names = {}
					for _, roll in ipairs(info.rollInfos or {}) do
						if states[roll.state] and not (issecretvalue and issecretvalue(roll.playerName)) then
							local color = C_ClassColor.GetClassColor(roll.playerClass)
							names[#names + 1] = color and color:WrapTextInColorCode(roll.playerName) or roll.playerName
						end
					end
					SetRollCount(button, names)
				end
			end
		end
	end
end

local function HookRollFrames()
	for index = 1, 4 do
		local frame = _G["GroupLootFrame" .. index]
		if frame then
			frame:HookScript("OnShow", ResetRollFrame)
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Items:Refresh()
	local db = self.db
	local merchant = db.autoSell or db.autoRepair
	self:ToggleEvent("MERCHANT_SHOW", merchant)
	self:ToggleEvent("MERCHANT_CLOSED", merchant)
	if not merchant then
		merchantOpen = false
	end
	self:ToggleEvent("LOOT_READY", db.fastLoot)
	self:ToggleEvent("UI_ERROR_MESSAGE", db.destroyPrompt)
	self:ToggleEvent("LOOT_BIND_CONFIRM", db.autoBind)
	self:ToggleEvent("CONFIRM_LOOT_ROLL", db.autoBind)
	self:ToggleEvent("LOOT_HISTORY_UPDATE_DROP", db.rollCounts)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", db.upgradeArrow, function()
		wipe(upgradeCache)
		UpdateAllBags()
	end)
	self:ToggleEvent("PLAYER_LEVEL_UP", db.upgradeArrow, function()
		wipe(upgradeCache)
	end)
	-- Specialization or talent changes alter the stat weights.
	for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
		if C_EventUtils.IsEventValid(event) then
			self:ToggleEvent(event, db.upgradeArrow, function()
				weights = nil
				wipe(upgradeCache)
				UpdateAllBags()
			end)
		end
	end
end

function Items:OnInitialize()
	-- Former single switch for all messages of this module.
	if self.db.messages == false then
		self.db.sellMessage, self.db.repairMessage, self.db.markMessage = false, false, false
	end
	self.db.messages = nil
end

function Items:OnLogin()
	HookContainerFrames()
	HookRollFrames()
	hooksecurefunc("QuestInfo_Display", MarkBestReward)
	self:Refresh()
end

function Items:OnOptionChanged()
	self:Refresh()
	UpdateAllBags()
	if QuestInfoFrame:IsVisible() then
		MarkBestReward()
	end
end

Items.options = {
	{ type = "header", name = L.ITEMS_MERCHANT },
	{ key = "autoSell", type = "toggle", name = L.ITEMS_AUTOSELL, desc = L.ITEMS_AUTOSELL_DESC },
	{ key = "sellMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "autoSell" },
	{ key = "autoRepair", type = "toggle", name = L.ITEMS_AUTOREPAIR, desc = L.ITEMS_AUTOREPAIR_DESC },
	{ key = "repairGuild", type = "toggle", name = L.ITEMS_REPAIR_GUILD, desc = L.ITEMS_REPAIR_GUILD_DESC, parent = "autoRepair" },
	{ key = "repairMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "autoRepair" },
	{ key = "junkButton", type = "dropdown", name = L.ITEMS_JUNK_BUTTON, desc = L.ITEMS_JUNK_BUTTON_DESC, values = {
		{ "MiddleButton", L.ITEMS_MOUSE_MIDDLE }, { "Button4", L.ITEMS_MOUSE_4 }, { "Button5", L.ITEMS_MOUSE_5 },
		{ "None", L.ITEMS_MOUSE_NONE },
	} },
	{ key = "markMessage", type = "toggle", name = L.ITEMS_MARK_MESSAGE, desc = L.MESSAGE_DESC },
	{ type = "button", name = L.ITEMS_JUNK_LIST, text = L.ITEMS_JUNK_SHOW, desc = L.ITEMS_JUNK_LIST_DESC, func = function()
		Items:ShowJunkMenu()
	end },
	{ type = "header", name = L.ITEMS_DISPLAY },
	{ key = "questReward", type = "toggle", name = L.ITEMS_QUEST_REWARD, desc = L.ITEMS_QUEST_REWARD_DESC },
	{ key = "upgradeArrow", type = "toggle", name = L.ITEMS_UPGRADE, desc = L.ITEMS_UPGRADE_DESC },
	{ type = "header", name = L.ITEMS_LOOT },
	{ key = "fastLoot", type = "toggle", name = L.ITEMS_FASTLOOT, desc = L.ITEMS_FASTLOOT_DESC },
	{ key = "destroyPrompt", type = "toggle", name = L.ITEMS_DESTROY, desc = L.ITEMS_DESTROY_DESC },
	{ key = "autoBind", type = "toggle", name = L.ITEMS_AUTOBIND, desc = L.ITEMS_AUTOBIND_DESC },
	{ key = "rollCounts", type = "toggle", name = L.ITEMS_ROLL_COUNTS, desc = L.ITEMS_ROLL_COUNTS_DESC },

}

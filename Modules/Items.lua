-- Items: junk selling and marking, auto repair, quest reward value,
-- upgrade arrows in bags and fast looting.
local _, ns = ...
local L = ns.L

local Items = ns:NewModule("Items", {
	title = L.ITEMS_TITLE,
	order = 4,
	defaults = {
		autoSell = true,
		sellButton = true,
		autoSort = false,
		sortMarkedJunk = true,
		autoRepair = true,
		repairGuild = true,
		questReward = true,
		upgradeArrow = true,
		upgradeScore = false,
		upgradePopup = true,
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
		junkPerCharacter = false,
	},
	charDefaults = {
		junk = {},
		keep = {},
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

-- Marked and kept items: for the account or, as an option, per character.
local function JunkLists()
	local db = Items.db.junkPerCharacter and Items.cdb or Items.db
	return db.junk, db.keep
end

local function IsMarked(info)
	local junk = JunkLists()
	return info.itemID and junk[(JunkKey(info))] and true or false
end

local function IsKept(info)
	local _, keep = JunkLists()
	return info.itemID and keep[(JunkKey(info))] and true or false
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

-- Inventory slots an item can go to (also used by the trainer comparison).
function ns.EquipSlots(equipLoc)
	if equipLoc == "INVTYPE_WEAPON" then
		return CanDualWield() and ONE_HAND_SLOTS or MAIN_HAND_SLOT
	end
	return EQUIP_SLOTS[equipLoc]
end

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
local weightsName -- talent tree the weights belong to (nil = default)
local _, playerClass = UnitClass("player")

-- Forever has one specialization per class (C_SpecializationInfo); the three
-- classic talent trees are trait groups. The tree with the most points wins,
-- in the order the talent frame shows them (orderIndex).
local function TalentTree()
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	local configInfo = configID and C_Traits.GetConfigInfo(configID)
	local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
	if not treeID then
		return nil
	end
	local trees = {}
	for _, info in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		trees[#trees + 1] = info
	end
	table.sort(trees, function(a, b)
		return a.orderIndex < b.orderIndex
	end)
	local groupIDs, indexOf = {}, {}
	for i, info in ipairs(trees) do
		groupIDs[i] = info.groupID
		indexOf[info.groupID] = i
	end
	local best, bestPoints = nil, 0
	for _, info in ipairs(#groupIDs > 0 and C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
		local currency = info.currencyInfos and info.currencyInfos[1]
		local spent = currency and currency.spent or 0
		if spent > bestPoints and indexOf[info.traitNodeGroupID] then
			best, bestPoints = indexOf[info.traitNodeGroupID], spent
		end
	end
	return best, best and trees[best].displayName
end

-- Hybrids hit with their weapon while levelling in every talent tree: below
-- level 20 weapon DPS counts fully for their caster and healer trees, fading
-- out until level 40.
local LEVELLING_MELEE = { SHAMAN = true, PALADIN = true }
local LEVELLING_FULL, LEVELLING_NONE = 20, 40

local function GetWeights()
	if weights then
		return weights, weightsName
	end
	local classWeights = WEIGHTS[playerClass] or MELEE
	weightsName = nil
	if classWeights[1] then
		local index, name = TalentTree()
		if not index then
			index = DEFAULT_SPEC[playerClass] or 1
		end
		weightsName = name
		classWeights = classWeights[index] or classWeights[1]
	end
	if LEVELLING_MELEE[playerClass] and not classWeights.DPS then
		local level = UnitLevel("player")
		local share = math.min(1, math.max(0, (LEVELLING_NONE - level) / (LEVELLING_NONE - LEVELLING_FULL)))
		if share > 0 then
			classWeights = CopyTable(classWeights)
			classWeights.DPS = MELEE.DPS * share
		end
	end
	weights = classWeights
	return weights, weightsName
end

-- Weighted value of an item; weapon DPS counts per slot (melee/ranged).
-- Weapon DPS from the tooltip line, for clients whose item stats lack it.
local DPS_PATTERN = type(DPS_TEMPLATE) == "string" and "^" .. DPS_TEMPLATE:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%%%%.1f", "([%%d%%.,]+)") .. "$"

local function TooltipDPS(link)
	local data = DPS_PATTERN and C_TooltipInfo.GetHyperlink(link)
	for _, line in ipairs(data and data.lines or {}) do
		local value = line.leftText and line.leftText:match(DPS_PATTERN)
		if value then
			return tonumber((value:gsub(",", ".")))
		end
	end
end

local function Score(link, ranged)
	local w = GetWeights()
	local score, hasDPS = 0, false
	for key, value in pairs(C_Item.GetItemStats(link) or {}) do
		local name = StatName(key)
		if name == "DPS" then
			hasDPS = true
			if ranged then
				name = "RDPS"
			end
		end
		if name and w[name] then
			score = score + w[name] * value
		end
	end
	if not hasDPS and select(6, C_Item.GetItemInfoInstant(link)) == Enum.ItemClass.Weapon then
		local dps = TooltipDPS(link)
		local weight = w[ranged and "RDPS" or "DPS"]
		if dps and weight then
			score = score + weight * dps
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
-- Returns the weighted value of the item and of the weakest equipped item it
-- could replace; false if it never counts as an upgrade, nil while loading.
local function CompareScores(link)
	local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
	local slots = ns.EquipSlots(equipLoc)
	if not slots or (classID == Enum.ItemClass.Weapon and IGNORED_WEAPONS[subClassID])
		or not IsBestArmorType(classID, subClassID, equipLoc) then
		return false
	end
	if not C_Item.IsItemDataCachedByID(link) then
		return nil
	end

	local equippedScore
	if equipLoc == "INVTYPE_2HWEAPON" then
		-- Replaces main and off hand together.
		local mainScore = EquippedScore(INVSLOT_MAINHAND)
		local offScore = EquippedScore(INVSLOT_OFFHAND)
		if mainScore == false or offScore == false then
			return nil
		end
		equippedScore = mainScore + offScore
	elseif slots[1] == INVSLOT_OFFHAND and IsTwoHand(EquippedLink(INVSLOT_MAINHAND)) then
		-- No off hand next to a two-hand weapon.
		return false
	else
		for _, invSlot in ipairs(slots) do
			local value = EquippedScore(invSlot)
			if value == false then
				return nil
			end
			if not equippedScore or value < equippedScore then
				equippedScore = value
			end
		end
	end
	return Score(link, slots[1] == INVSLOT_RANGED), equippedScore
end

-- An upgrade is the best armor type for the class, usable, and has a higher
-- weighted value (stats of the current talent tree) than the weakest
-- equipped item it could replace. Unknown data never shows an arrow.
local function IsUpgrade(bag, slot, link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end
	local score, equippedScore = CompareScores(link)
	if score == nil then
		return false
	end
	local result = score and score > equippedScore + 0.01 and CanUse(bag, slot) or false
	upgradeCache[link] = result
	return result
end

-- Optional tooltip line with both values, to check the rating.
local function AddScoreLine(tooltip)
	if not Items.db.upgradeScore or tooltip:IsForbidden() or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
		return
	end
	local _, link = tooltip:GetItem()
	if not link or (issecretvalue and issecretvalue(link)) or not C_Item.IsEquippableItem(link) then
		return
	end
	local score, equippedScore = CompareScores(link)
	if not score then
		return
	end
	local _, treeName = GetWeights()
	tooltip:AddLine(L.ITEMS_SCORE_LINE:format(score, equippedScore, treeName or L.ITEMS_SCORE_DEFAULT), 0.5, 0.7, 1)
	tooltip:Show()
end

---------------------------------------------------------------------------
-- Upgrade popup: a new item in the bags (loot, quest reward, purchase) that
-- is better than the equipped one is offered for equipping, one at a time.
---------------------------------------------------------------------------
local offered = {}      -- item GUID or link -> true once checked
local upgradeQueue = {} -- { link, score, equippedScore, invSlot }
local upgradeFrame
local bagsSeen = false  -- the first scan after login only records the items

local PARCHMENT_TEXT = { 0.18, 0.1, 0.04 }

-- Equipped slot the item would replace: the weaker of two (rings, trinkets).
local function TargetSlot(link)
	local slots = ns.EquipSlots(select(4, C_Item.GetItemInfoInstant(link)))
	if not slots then
		return nil
	end
	local target, lowest = slots[1], nil
	for _, invSlot in ipairs(slots) do
		local value = EquippedScore(invSlot)
		if value and (not lowest or value < lowest) then
			target, lowest = invSlot, value
		end
	end
	return target
end

local ShowNextUpgrade

local function CreateUpgradeFrame()
	local frame = CreateFrame("Frame", "ForeverPlusUpgradeFrame", UIParent)
	frame:SetSize(360, 172)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:Hide()

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", 8, -8)
	background:SetPoint("BOTTOMRIGHT", -8, 8)
	if not background:SetAtlas("QuestBG-Parchment") then
		background:SetColorTexture(0.84, 0.74, 0.55)
	end
	frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderNoCenterTemplate")

	local title = frame:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	title:SetPoint("TOP", 0, -22)
	title:SetText(L.ITEMS_UPGRADE_POPUP_TITLE)
	title:SetTextColor(unpack(PARCHMENT_TEXT))

	local icon = CreateFrame("Button", nil, frame, "ItemButtonTemplate")
	icon:SetPoint("TOPLEFT", 26, -50)
	icon:SetScript("OnEnter", function(self)
		local entry = upgradeQueue[1]
		if entry then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(entry.link)
			GameTooltip:Show()
		end
	end)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	frame.Icon = icon

	local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
	name:SetPoint("RIGHT", -26, 0)
	name:SetJustifyH("LEFT")
	name:SetShadowOffset(0, 0)
	frame.Name = name

	local replaces = frame:CreateFontString(nil, "ARTWORK", "QuestFont")
	replaces:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	replaces:SetPoint("RIGHT", -26, 0)
	replaces:SetJustifyH("LEFT")
	replaces:SetTextColor(unpack(PARCHMENT_TEXT))
	frame.Replaces = replaces

	local score = frame:CreateFontString(nil, "ARTWORK", "QuestFont")
	score:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
	score:SetPoint("RIGHT", -26, 0)
	score:SetJustifyH("LEFT")
	score:SetTextColor(unpack(PARCHMENT_TEXT))
	frame.Score = score

	local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	equip:SetSize(110, 24)
	equip:SetPoint("BOTTOMRIGHT", -24, 20)
	equip:SetText(L.ITEMS_UPGRADE_POPUP_EQUIP)
	equip:SetScript("OnClick", function()
		local entry = table.remove(upgradeQueue, 1)
		-- Only if the item is still in the bags (sorting may have moved it).
		if entry and not InCombatLockdown() and C_Item.GetItemCount(entry.link) > 0 then
			C_Item.EquipItemByName(entry.link, TargetSlot(entry.link))
		end
		ShowNextUpgrade()
	end)

	local later = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	later:SetSize(110, 24)
	later:SetPoint("RIGHT", equip, "LEFT", -8, 0)
	later:SetText(L.ITEMS_UPGRADE_POPUP_LATER)
	later:SetScript("OnClick", function()
		table.remove(upgradeQueue, 1)
		ShowNextUpgrade()
	end)

	local fade = frame:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.2)
	frame:SetScript("OnShow", function()
		fade:Play()
	end)
	-- Escape closes it; the offers stay declined for this session. Hiding
	-- for combat keeps them.
	frame:SetScript("OnHide", function(self)
		if not self.combatHide then
			wipe(upgradeQueue)
		end
		self.combatHide = nil
	end)
	tinsert(UISpecialFrames, frame:GetName())
	return frame
end

function ShowNextUpgrade()
	local entry = upgradeQueue[1]
	if not entry or InCombatLockdown() or not Items.db.upgradePopup then
		if upgradeFrame and not entry then
			upgradeFrame:Hide()
		end
		return
	end
	upgradeFrame = upgradeFrame or CreateUpgradeFrame()
	local frame = upgradeFrame
	local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(entry.link)
	SetItemButtonTexture(frame.Icon, texture)
	SetItemButtonQuality(frame.Icon, quality, entry.link)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	frame.Name:SetText(itemName or entry.link)
	if color then
		frame.Name:SetTextColor(color.r, color.g, color.b)
	end
	local equipped = entry.invSlot and GetInventoryItemLink("player", entry.invSlot)
	local equippedName = equipped and C_Item.GetItemInfo(equipped)
	frame.Replaces:SetText(equippedName and L.ITEMS_UPGRADE_POPUP_REPLACES:format(equippedName) or L.ITEMS_UPGRADE_POPUP_EMPTY)
	local gain = entry.equippedScore > 0 and (entry.score / entry.equippedScore - 1) * 100
	frame.Score:SetText(gain and L.ITEMS_UPGRADE_POPUP_SCORE:format(entry.equippedScore, entry.score, gain)
		or L.ITEMS_UPGRADE_POPUP_SCORE_NEW:format(entry.score))
	frame:Show()
end

local function ItemKey(bag, slot, link)
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	local guid = C_Item.DoesItemExist(location) and C_Item.GetItemGUID(location)
	return guid or link
end

-- New items in the bags: checked once each; data still loading is retried
-- on the next bag update.
local function ScanNewItems()
	local record = not bagsSeen
	bagsSeen = true
	local added = false
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and C_NewItems.IsNewItem(bag, slot) and C_Item.IsEquippableItem(link) then
				local key = ItemKey(bag, slot, link)
				if not offered[key] then
					local score, equippedScore = CompareScores(link)
					if record or score == false then
						offered[key] = true
					elseif score ~= nil then
						offered[key] = true
						if score > equippedScore + 0.01 and CanUse(bag, slot) then
							upgradeQueue[#upgradeQueue + 1] = {
								link = link, score = score, equippedScore = equippedScore, invSlot = TargetSlot(link),
							}
							added = true
						end
					end
				end
			end
		end
	end
	if added and not (upgradeFrame and upgradeFrame:IsShown()) then
		ShowNextUpgrade()
	end
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
		-- Top right, so it does not cover the junk coin at the top left.
		if not button.fpUpgradeMoved then
			button.fpUpgradeMoved = true
			button.UpgradeIcon:ClearAllPoints()
			button.UpgradeIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		end
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
	local junk, keep = JunkLists()
	local list = info.quality == Enum.ItemQuality.Poor and keep or junk
	local isGrey = list == keep
	local key, value = JunkKey(info)
	if list[key] then
		list[key] = nil
	else
		list[key] = value
	end
	Report("markMessage", IsJunkItem(info) and L.ITEMS_MARKED or L.ITEMS_UNMARKED, info.hyperlink)
	if isGrey then
		junk[key] = nil
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

-- Icon, coloured name and sort name of a junk list entry.
local function JunkEntry(key, value)
	local itemID = KeyItemID(key)
	local icon = itemID and C_Item.GetItemIconByID(itemID)
	if type(value) == "string" then
		-- Suffix items: the stored link carries the full coloured name.
		local name = value:match("%[(.-)%]") or value
		return icon, value:gsub("|H.-|h(.-)|h", "%1"), name
	end
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		name = ("item:%d"):format(itemID)
	end
	local sortName = name
	local quality = C_Item.GetItemQualityByID(itemID)
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		name = CreateColor(r, g, b):WrapTextInColorCode(name)
	end
	return icon, name, sortName
end

local function AddJunkItems(items, list, onRemove)
	local entries = {}
	for key, value in pairs(list) do
		local icon, text, sortName = JunkEntry(key, value)
		entries[#entries + 1] = { id = key, value = value, icon = icon, text = text, sortName = sortName }
	end
	table.sort(entries, function(a, b)
		return a.sortName < b.sortName
	end)
	for _, entry in ipairs(entries) do
		items[#items + 1] = {
			icon = entry.icon,
			text = entry.text,
			onClick = function()
				list[entry.id] = nil
				onRemove(entry.id, entry.value)
			end,
			tooltip = function(tooltip)
				if type(entry.value) == "string" then
					tooltip:SetHyperlink(entry.value)
				else
					tooltip:SetItemByID(KeyItemID(entry.id))
				end
				GameTooltip_AddInstructionLine(tooltip, L.ITEMS_JUNK_REMOVE_HINT)
			end,
		}
	end
	return #entries
end

-- Popup at the owner (settings button) or at the cursor (/fp schrott).
function Items:ShowJunkMenu(owner)
	ns.ShowPopupList(owner, function()
		local items = {}
		local junk, keep = JunkLists()
		-- A grey item taken off the junk list would still be sold as grey;
		-- it moves to the kept list instead.
		local marked = AddJunkItems(items, junk, function(key, value)
			if C_Item.GetItemQualityByID(KeyItemID(key)) == Enum.ItemQuality.Poor then
				keep[key] = value
			end
			UpdateAllBags()
		end)
		if next(keep) then
			items[#items + 1] = { text = L.ITEMS_JUNK_KEPT }
		end
		local kept = AddJunkItems(items, keep, UpdateAllBags)
		local footer
		if marked + kept > 0 then
			footer = { { text = L.ITEMS_CLEAR_JUNK, onClick = function()
				wipe(junk)
				wipe(keep)
				UpdateAllBags()
			end } }
		end
		return { title = L.ITEMS_JUNK_LIST, items = items, empty = L.ITEMS_JUNK_NONE, footer = footer }
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
			hooksecurefunc(frame, "UpdateItems", ns.Measured("Items: bag update", PostUpdateItems))
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

local function StartSelling()
	if sellTicker then
		return
	end
	soldValue = 0
	SellBatch()
	if soldValue then
		sellTicker = C_Timer.NewTicker(SELL_INTERVAL, SellBatch)
	end
end

-- Count and value of the junk in the bags (same rules as selling).
local function JunkValue()
	local count, value = 0, 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsJunk(info) then
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 then
					count = count + 1
					value = value + price * info.stackCount
				end
			end
		end
	end
	return count, value
end

-- Blizzard's sell-junk button sells every grey item, including kept ones.
-- A button of our own lies on top and sells by the junk rules instead.
local sellButton

local function UpdateSellButton()
	if not sellButton or not sellButton:IsShown() then
		return
	end
	local count = JunkValue()
	sellButton:GetParent().Icon:SetDesaturated(count == 0)
	sellButton:SetEnabled(count > 0)
end

local function CreateSellButton()
	local parent = _G.MerchantSellAllJunkButton
	if sellButton or not parent then
		return
	end
	sellButton = CreateFrame("Button", nil, parent)
	sellButton:SetAllPoints()
	sellButton:SetFrameLevel(parent:GetFrameLevel() + 2)
	sellButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	sellButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	-- Disabled buttons get no OnEnter; keep the tooltip anyway.
	sellButton:SetMotionScriptsWhileDisabled(true)
	sellButton:SetScript("OnClick", function()
		if merchantOpen then
			StartSelling()
		end
	end)
	sellButton:SetScript("OnEnter", function(self)
		local count, value = JunkValue()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(SELL_ALL_JUNK_ITEMS)
		GameTooltip:AddLine(L.ITEMS_SELL_BUTTON_TIP, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		if count > 0 then
			GameTooltip:AddDoubleLine(L.ITEMS_SELL_BUTTON_COUNT:format(count), GetMoneyString(value, true), 1, 1, 1, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	sellButton:SetScript("OnLeave", GameTooltip_Hide)
	sellButton:SetScript("OnShow", UpdateSellButton)
	hooksecurefunc("MerchantFrame_Update", ns.Measured("Items: sell button", UpdateSellButton))
end

function Items:MERCHANT_SHOW()
	merchantOpen = true
	if self.db.autoRepair then
		Repair()
	end
	if self.db.autoSell then
		StartSelling()
	end
end

function Items:MERCHANT_CLOSED()
	merchantOpen = false
	StopSelling()
end

---------------------------------------------------------------------------
-- Bags: sorted by the game's own cleanup when they open
---------------------------------------------------------------------------
local SORT_PAUSE = 3 -- seconds between automatic sorts
local lastSort, sortQueued = 0, false

local function SortOnOpen()
	sortQueued = false
	-- Not while selling, in combat or with an item on the cursor.
	if not Items.db.autoSort or InCombatLockdown() or sellTicker or GetCursorInfo() then
		return
	end
	local now = GetTime()
	if now - lastSort < SORT_PAUSE then
		return
	end
	lastSort = now
	C_Container.SortBags()
end

-- After any sort (own or Blizzard's button) marked junk joins the grey
-- items, which the game's cleanup puts together. Waits until the bags are
-- quiet, then moves one item at a time.
local SORT_QUIET = 0.7  -- seconds without bag updates: the sort is done
local SORT_TIMEOUT = 10
local MOVE_INTERVAL = 0.1
local placing -- state while waiting for the sort or moving items

-- Slots that take part in the cleanup, in bag order.
local function SortedSlots()
	local slots = {}
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local disabled
		if bag == BACKPACK_CONTAINER then
			disabled = C_Container.GetBackpackAutosortDisabled and C_Container.GetBackpackAutosortDisabled()
		else
			disabled = C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.DisableAutoSort)
		end
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		if not disabled and (family or 0) == 0 then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				slots[#slots + 1] = { bag, slot }
			end
		end
	end
	return slots
end

local function AnyLocked(slots)
	for _, position in ipairs(slots) do
		local info = C_Container.GetContainerItemInfo(position[1], position[2])
		if info and info.isLocked then
			return true
		end
	end
	return false
end

-- Moves (from, to) that put the marked items right next to the grey ones:
-- before them when the greys lie at the end, after them when at the start.
local function PlanJunkMoves(slots)
	local isGrey, isMarked = {}, {}
	local firstGrey, lastGrey, markedCount = nil, nil, 0
	for index, position in ipairs(slots) do
		local info = C_Container.GetContainerItemInfo(position[1], position[2])
		if info and info.quality == Enum.ItemQuality.Poor then
			isGrey[index] = true
			firstGrey = firstGrey or index
			lastGrey = index
		elseif info and IsMarked(info) then
			isMarked[index] = true
			markedCount = markedCount + 1
		end
	end
	if markedCount == 0 then
		return {}
	end
	local block = {}
	if firstGrey and firstGrey == 1 and lastGrey < #slots then
		for index = lastGrey + 1, math.min(#slots, lastGrey + markedCount) do
			block[#block + 1] = index
		end
	else
		local stop = (firstGrey or #slots + 1) - 1
		for index = stop, math.max(1, stop - markedCount + 1), -1 do
			block[#block + 1] = index
		end
	end
	local inBlock = {}
	for _, index in ipairs(block) do
		inBlock[index] = true
	end
	-- Marked items outside the block, farthest first.
	local outside = {}
	for index in pairs(isMarked) do
		if not inBlock[index] then
			outside[#outside + 1] = index
		end
	end
	local reference = block[1] or 1
	table.sort(outside, function(a, b)
		return math.abs(a - reference) > math.abs(b - reference)
	end)
	local moves = {}
	for _, index in ipairs(block) do
		if not isMarked[index] and not isGrey[index] then
			local from = table.remove(outside)
			if not from then
				break
			end
			moves[#moves + 1] = { slots[from], slots[index] }
		end
	end
	return moves
end

local function StopPlacing()
	if placing and placing.ticker then
		placing.ticker:Cancel()
	end
	placing = nil
end

local function PlacingStep()
	local state = placing
	if not state or InCombatLockdown() or GetCursorInfo() then
		StopPlacing()
		return
	end
	local now = GetTime()
	if now - state.started > SORT_TIMEOUT then
		StopPlacing()
		return
	end
	if not state.moves then
		-- Waiting for the sort to finish.
		if now - state.lastUpdate < SORT_QUIET or AnyLocked(state.slots) then
			return
		end
		state.moves = PlanJunkMoves(state.slots)
		state.next = 1
	end
	local move = state.moves[state.next]
	if not move then
		StopPlacing()
		return
	end
	if AnyLocked({ move[1], move[2] }) then
		return
	end
	C_Container.PickupContainerItem(move[1][1], move[1][2])
	C_Container.PickupContainerItem(move[2][1], move[2][2])
	ClearCursor()
	state.next = state.next + 1
end

local function OnSortStarted()
	if not Items.db.sortMarkedJunk or InCombatLockdown() then
		return
	end
	StopPlacing()
	placing = { started = GetTime(), lastUpdate = GetTime(), slots = SortedSlots() }
	placing.ticker = C_Timer.NewTicker(MOVE_INTERVAL, PlacingStep)
end

function Items:BAG_UPDATE()
	if placing and not placing.moves then
		placing.lastUpdate = GetTime()
	end
end

-- Opening all bags opens each frame; one sort after the last of them.
local function QueueSort()
	if Items.db.autoSort and not sortQueued then
		sortQueued = true
		C_Timer.After(0, SortOnOpen)
	end
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
		local height = ns.Number(button:GetHeight(), 39)
		glow:SetSize(height * 1.9, height * 1.9)
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
			-- Only grey (poor) items are offered for destruction.
			if info and not info.hasNoValue and not info.isLocked and info.quality == Enum.ItemQuality.Poor then
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

-- Vendor value of the most valuable item still in the open loot window
-- (math.huge for quest items); nil without loot window or item prices.
local function IncomingValue()
	local best
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local _, _, quantity, _, _, _, isQuestItem = GetLootSlotInfo(slot)
			local link = GetLootSlotLink(slot)
			local price = link and select(11, C_Item.GetItemInfo(link))
			local value = isQuestItem and math.huge or (price and price * math.max(quantity or 1, 1))
			if value and (not best or value > best) then
				best = value
			end
		end
	end
	return best
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
	-- Never offer something worth more than what is waiting to be looted.
	local incoming = IncomingValue()
	if incoming and entry.value >= incoming then
		lastPrompt = now
		ns.Print(L.ITEMS_DESTROY_NOT_WORTH)
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
	local merchant = db.autoSell or db.autoRepair or db.sellButton
	if db.sellButton then
		CreateSellButton()
	end
	if sellButton then
		sellButton:SetShown(db.sellButton)
		if not db.sellButton and MerchantFrame:IsShown() then
			MerchantFrame_Update()
		end
	end
	self:ToggleEvent("MERCHANT_SHOW", merchant)
	self:ToggleEvent("MERCHANT_CLOSED", merchant)
	if not merchant then
		merchantOpen = false
	end
	self:ToggleEvent("LOOT_READY", db.fastLoot)
	-- Fast loot builds on the game's auto loot; switch that on with it.
	if db.fastLoot and not GetCVarBool("autoLootDefault") then
		SetCVar("autoLootDefault", "1")
	end
	self:ToggleEvent("UI_ERROR_MESSAGE", db.destroyPrompt)
	self:ToggleEvent("LOOT_BIND_CONFIRM", db.autoBind)
	self:ToggleEvent("CONFIRM_LOOT_ROLL", db.autoBind)
	self:ToggleEvent("LOOT_HISTORY_UPDATE_DROP", db.rollCounts)
	self:ToggleEvent("BAG_UPDATE", db.sortMarkedJunk)
	self:ToggleEvent("BAG_UPDATE_DELAYED", db.upgradePopup, ns.Measured("Items: upgrade popup", ScanNewItems))
	-- Equipping is not possible in combat: hidden meanwhile, shown again after.
	self:ToggleEvent("PLAYER_REGEN_DISABLED", db.upgradePopup, function()
		if upgradeFrame and upgradeFrame:IsShown() then
			upgradeFrame.combatHide = true
			upgradeFrame:Hide()
		end
	end)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", db.upgradePopup, ShowNextUpgrade)
	if not db.upgradePopup then
		wipe(upgradeQueue)
		if upgradeFrame then
			upgradeFrame:Hide()
		end
	end
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", db.upgradeArrow, function()
		wipe(upgradeCache)
		UpdateAllBags()
	end)
	-- Level, specialization and talent changes alter the stat weights.
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
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
	if C_Container.SortBags then
		hooksecurefunc(C_Container, "SortBags", OnSortStarted)
	end
	EventRegistry:RegisterCallback("ContainerFrame.OpenBag", QueueSort, self)
	EventRegistry:RegisterCallback("ContainerFrame.OpenAllBags", QueueSort, self)
	hooksecurefunc("QuestInfo_Display", MarkBestReward)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Items: tooltip rating", AddScoreLine))
	self:Refresh()
end

function Items:OnOptionChanged(key)
	-- A character list starts as a copy of the account list.
	if key == "junkPerCharacter" and self.db.junkPerCharacter
		and next(self.cdb.junk) == nil and next(self.cdb.keep) == nil then
		self.cdb.junk = CopyTable(self.db.junk)
		self.cdb.keep = CopyTable(self.db.keep)
	end
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
	{ key = "sellButton", type = "toggle", name = L.ITEMS_SELL_BUTTON, desc = L.ITEMS_SELL_BUTTON_DESC },
	{ key = "autoRepair", type = "toggle", name = L.ITEMS_AUTOREPAIR, desc = L.ITEMS_AUTOREPAIR_DESC },
	{ key = "repairGuild", type = "toggle", name = L.ITEMS_REPAIR_GUILD, desc = L.ITEMS_REPAIR_GUILD_DESC, parent = "autoRepair" },
	{ key = "repairMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "autoRepair" },
	{ key = "junkButton", type = "dropdown", name = L.ITEMS_JUNK_BUTTON, desc = L.ITEMS_JUNK_BUTTON_DESC, values = {
		{ "MiddleButton", L.ITEMS_MOUSE_MIDDLE }, { "Button4", L.ITEMS_MOUSE_4 }, { "Button5", L.ITEMS_MOUSE_5 },
		{ "None", L.ITEMS_MOUSE_NONE },
	} },
	{ key = "markMessage", type = "toggle", name = L.ITEMS_MARK_MESSAGE, desc = L.MESSAGE_DESC },
	{ key = "junkPerCharacter", type = "toggle", name = L.ITEMS_JUNK_PER_CHAR, desc = L.ITEMS_JUNK_PER_CHAR_DESC },
	{ type = "button", name = L.ITEMS_JUNK_LIST, text = L.ITEMS_JUNK_SHOW, desc = L.ITEMS_JUNK_LIST_DESC, func = function(button)
		Items:ShowJunkMenu(button)
	end },
	{ type = "header", name = L.ITEMS_BAGS },
	{ key = "autoSort", type = "toggle", name = L.ITEMS_AUTOSORT, desc = L.ITEMS_AUTOSORT_DESC },
	{ key = "sortMarkedJunk", type = "toggle", name = L.ITEMS_SORT_JUNK, desc = L.ITEMS_SORT_JUNK_DESC },
	{ type = "header", name = L.ITEMS_DISPLAY },
	{ key = "questReward", type = "toggle", name = L.ITEMS_QUEST_REWARD, desc = L.ITEMS_QUEST_REWARD_DESC },
	{ key = "upgradeArrow", type = "toggle", name = L.ITEMS_UPGRADE, desc = L.ITEMS_UPGRADE_DESC },
	{ key = "upgradeScore", type = "toggle", name = L.ITEMS_SCORE, desc = L.ITEMS_SCORE_DESC },
	{ key = "upgradePopup", type = "toggle", name = L.ITEMS_UPGRADE_POPUP, desc = L.ITEMS_UPGRADE_POPUP_DESC },
	{ type = "header", name = L.ITEMS_LOOT },
	{ key = "fastLoot", type = "toggle", name = L.ITEMS_FASTLOOT, desc = L.ITEMS_FASTLOOT_DESC },
	{ key = "destroyPrompt", type = "toggle", name = L.ITEMS_DESTROY, desc = L.ITEMS_DESTROY_DESC },
	{ key = "autoBind", type = "toggle", name = L.ITEMS_AUTOBIND, desc = L.ITEMS_AUTOBIND_DESC },
	{ key = "rollCounts", type = "toggle", name = L.ITEMS_ROLL_COUNTS, desc = L.ITEMS_ROLL_COUNTS_DESC },

}

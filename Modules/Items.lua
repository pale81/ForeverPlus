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
		sortSkip = true,
		fullSound = true,   -- a sound when the bags are full
		fullSoundChoice = "ping",
		bagMenu = true,
		autoRepair = true,
		repairGuild = true,
		questReward = true,
		upgradeArrow = true,
		rewardUpgrade = true,
		moneyPickup = true,
		upgradeScore = false,
		upgradePopup = true,
		upgradeCelebrate = true,
		upgradeMarkOld = false,
		fastLoot = true,
		sellMessage = true,
		repairMessage = true,
		markMessage = true,
		destroyPrompt = true,
		autoBind = false,
		autoEquipBind = false,
		deleteText = false,
		rollCounts = true,
		junkButton = "MiddleButton",
		junk = {},
		keep = {}, -- grey items the player unmarked: never sold
		junkPerCharacter = false,
	},
	charDefaults = {
		junk = {},
		keep = {},
		scoreSpec = 0, -- talent tree whose weights the rating uses: 0 = the one with the most points
	},
})

-- Key binding labels (Bindings.xml).
BINDING_HEADER_FOREVERPLUS = "ForeverPlus"
-- The keybinding page of this client lists a binding whose name starts with PREFACE as a line of text.
PREFACE_FOREVERPLUS = "ForeverPlus"
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

-- Bags flagged "ignore for junk selling" in Blizzard's bag menu.
local function BagExcludesJunk(bag)
	if bag == BACKPACK_CONTAINER then
		return C_Container.GetBackpackSellJunkDisabled()
	end
	return C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.ExcludeJunkSell)
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
local scoreCache = {}      -- hyperlink (+ ranged) -> weighted value; weapons need a tooltip for it
local equippedCache = {}   -- inventory slot -> weighted value of the worn item

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
	return best, best and trees[best].displayName, trees
end

-- The tree chosen in the options when this class has it, else the automatic one.
function Items.PickTree(choice, auto, count)
	if choice and choice >= 1 and choice <= count then
		return choice
	end
	return auto
end

-- Choices for the rating: automatic, then the talent trees of the class (names from the talent data when known).
local function ScoreSpecValues()
	local values = { { 0, L.ITEMS_SCORE_SPEC_AUTO } }
	local classWeights = WEIGHTS[playerClass]
	if classWeights and classWeights[1] then
		local _, _, trees = TalentTree()
		for index = 1, #classWeights do
			local tree = trees and trees[index]
			values[#values + 1] = { index, tree and tree.displayName or L.ITEMS_SCORE_SPEC_TREE:format(index) }
		end
	end
	return values
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
		local index, name, trees = TalentTree()
		if not index then
			index = DEFAULT_SPEC[playerClass] or 1
		end
		local chosen = Items.PickTree(Items.cdb and Items.cdb.scoreSpec, index, #classWeights)
		if chosen ~= index then
			index = chosen
			name = trees and trees[index] and trees[index].displayName or L.ITEMS_SCORE_SPEC_TREE:format(index)
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
	local cacheKey = ranged and link .. "#r" or link
	local cached = scoreCache[cacheKey]
	if cached then
		return cached
	end
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
	scoreCache[cacheKey] = score
	return score
end

local function IsRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

-- Red lines in the item tooltip mean the player cannot use it (class, armor type, level): "ok", "level" when the
-- only red line is the level the item needs (usable later), "no" otherwise.
function Items.UseBlock(lines, levelPattern)
	if not lines then
		return "no"
	end
	local level = false
	for _, line in ipairs(lines) do
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			local text = line.leftText
			if levelPattern and type(text) == "string" and not ns.Secret(text) and text:find(levelPattern) then
				level = true
			else
				return "no"
			end
		end
	end
	return level and "level" or "ok"
end

local function LevelPattern()
	if Items.levelPattern == nil then
		Items.levelPattern = type(ITEM_MIN_LEVEL) == "string" and ns.FormatToPattern(ITEM_MIN_LEVEL, true).pattern or false
	end
	return Items.levelPattern or nil
end

local function BagUseBlock(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	return Items.UseBlock(data and data.lines, LevelPattern())
end

local function CanUse(bag, slot)
	return BagUseBlock(bag, slot) == "ok"
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
	local cached = equippedCache[invSlot]
	if cached then
		return cached
	end
	local link = EquippedLink(invSlot)
	if link == false then
		return false
	end
	local value = link and Score(link, invSlot == INVSLOT_RANGED) or 0
	equippedCache[invSlot] = value
	return value
end

-- Everything that depends on what is worn or on the stat weights.
local function ClearWeighCaches()
	wipe(upgradeCache)
	wipe(scoreCache)
	wipe(equippedCache)
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
local WEIGH_BUDGET = 2 -- ms per bag update: the rest of the new items is weighed a moment later
local weighStart, weighDone, weighDeferred, weighActive = 0, 0, false, false

local function IsUpgrade(bag, slot, link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end
	if weighActive then
		if weighDone > 0 and debugprofilestop() - weighStart > WEIGH_BUDGET then
			weighDeferred = true
			return false
		end
		weighDone = weighDone + 1
	end
	local score, equippedScore = CompareScores(link)
	if score == nil then
		return false
	end
	-- Better, but the level is still missing: "later" (a grey arrow).
	local result = false
	if score and score > equippedScore + 0.01 then
		local block = BagUseBlock(bag, slot)
		result = block == "ok" or (block == "level" and "later") or false
	end
	upgradeCache[link] = result
	return result
end

-- The same check for an item that is not in the bags (quest rewards, merchant): usable by the
-- red lines of its tooltip.
local function CanUseLink(link)
	local data = C_TooltipInfo.GetHyperlink(link)
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

local rewardRetries = {}

-- True if the item (a link) beats what is worn, false if not or if it is no equipment, nil while its
-- data loads (onLoaded is called again a little later, at most three times per item).
function ns.IsRewardUpgrade(link, onLoaded)
	if not Items.db or not Items.db.rewardUpgrade or type(link) ~= "string" or ns.Secret(link)
		or not C_Item.IsEquippableItem(link) then
		return false
	end
	local score, equippedScore = CompareScores(link)
	if score == nil then
		local tries = rewardRetries[link] or 0
		if onLoaded and tries < 3 then
			rewardRetries[link] = tries + 1
			ns.After("Items: onLoaded", 1, onLoaded)
		end
		return nil
	end
	return score and score > equippedScore + 0.01 and CanUseLink(link) or false
end

-- Optional tooltip line with both values, to check the rating.
local function AddScoreLine(tooltip)
	if not Items.db.upgradeScore or tooltip:IsForbidden() or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
		return
	end
	local _, link = tooltip:GetItem()
	if not link or ns.Secret(link) or not C_Item.IsEquippableItem(link) then
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

-- The window looks like the game's loot upgrade toast (its background, the quality border of the item, arrows that
-- rise over the icon, a glow on the border), with the two buttons below it.
local TOAST_BORDER = { [0] = "gray", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }

-- The gain over the worn item in percent (nil for an empty slot) and the title line of the toast.
function Items.UpgradeGain(score, equippedScore)
	if equippedScore and equippedScore > 0 then
		return (score / equippedScore - 1) * 100
	end
end

local function SetAtlasOr(texture, atlas, fallback)
	if C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, true)
		return true
	end
	if fallback then
		fallback()
	end
	return false
end

local function CreateUpgradeFrame()
	local frame = CreateFrame("Button", "ForeverPlusUpgradeFrame", UIParent)
	frame:SetSize(276, 96)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("RightButtonUp")
	frame:Hide()
	-- Escape closes it like the panel before.
	tinsert(UISpecialFrames, "ForeverPlusUpgradeFrame")

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetPoint("TOPLEFT")
	SetAtlasOr(frame.Background, "loottoast-bg-questrewardupgrade", function()
		frame.Background:SetAllPoints()
		frame.Background:SetColorTexture(0.08, 0.08, 0.1, 0.92)
	end)

	frame.Border = frame:CreateTexture(nil, "BORDER", nil, 2)
	frame.Border:SetPoint("LEFT", frame.Background, "LEFT", 19, -1)
	frame.Icon = frame:CreateTexture(nil, "BORDER", nil, 1)
	frame.Icon:SetSize(50, 50)
	frame.Icon:SetPoint("LEFT", frame, "LEFT", 23, -1)
	frame.Glow = frame:CreateTexture(nil, "BORDER", nil, 4)
	frame.Glow:SetPoint("CENTER", frame.Icon, "CENTER")
	frame.Glow:SetBlendMode("ADD")
	frame.Glow:SetAlpha(0)
	SetAtlasOr(frame.Glow, "loottoast-itemborder-glow")

	-- Pointing at the icon shows the item.
	local hit = CreateFrame("Frame", nil, frame)
	hit:SetAllPoints(frame.Icon)
	hit:SetScript("OnEnter", function(self)
		local entry = upgradeQueue[1]
		if entry then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(entry.link)
			GameTooltip:Show()
		end
	end)
	hit:SetScript("OnLeave", GameTooltip_Hide)

	frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 14, 2)
	frame.Title:SetPoint("RIGHT", -18, 0)
	frame.Title:SetJustifyH("LEFT")
	frame.Name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	frame.Name:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -3)
	frame.Name:SetPoint("RIGHT", -18, 0)
	frame.Name:SetJustifyH("LEFT")
	frame.Name:SetWordWrap(false)
	frame.Score = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.Score:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -3)
	frame.Score:SetPoint("RIGHT", -18, 0)
	frame.Score:SetJustifyH("LEFT")
	frame.Replaces = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.Replaces:SetPoint("TOPLEFT", frame.Score, "BOTTOMLEFT", 0, -2)
	frame.Replaces:SetPoint("RIGHT", -18, 0)
	frame.Replaces:SetJustifyH("LEFT")
	frame.Replaces:SetWordWrap(false)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- In: fades in while sliding up a little; the arrows rise over the icon one after another, the border glows.
	frame.In = frame:CreateAnimationGroup()
	frame.In:SetToFinalAlpha(true)
	local fade = frame.In:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.25)
	local slide = frame.In:CreateAnimation("Translation")
	slide:SetOffset(0, 12)
	slide:SetDuration(0.25)
	slide:SetSmoothing("OUT")
	frame.Celebrate = frame:CreateAnimationGroup()
	frame.Celebrate:SetToFinalAlpha(true)
	local glowIn = frame.Celebrate:CreateAnimation("Alpha")
	glowIn:SetTarget(frame.Glow)
	glowIn:SetStartDelay(0.2)
	glowIn:SetFromAlpha(0)
	glowIn:SetToAlpha(1)
	glowIn:SetDuration(0.6)
	glowIn:SetSmoothing("IN")
	local glowOut = frame.Celebrate:CreateAnimation("Alpha")
	glowOut:SetTarget(frame.Glow)
	glowOut:SetStartDelay(0.9)
	glowOut:SetFromAlpha(1)
	glowOut:SetToAlpha(0)
	glowOut:SetDuration(0.8)
	frame.Arrows = {}
	for index, x in ipairs({ 0, 16, -16, 5, -12 }) do
		local arrow = frame:CreateTexture(nil, "ARTWORK")
		arrow:SetPoint("CENTER", frame.Icon, "CENTER", x, -8)
		arrow:SetAlpha(0)
		frame.Arrows[index] = arrow
		local delay = 0.4 + (index - 1) * 0.12
		local show = frame.Celebrate:CreateAnimation("Alpha")
		show:SetTarget(arrow)
		show:SetStartDelay(delay)
		show:SetFromAlpha(0)
		show:SetToAlpha(1)
		show:SetDuration(0.2)
		local hide = frame.Celebrate:CreateAnimation("Alpha")
		hide:SetTarget(arrow)
		hide:SetStartDelay(delay + 0.3)
		hide:SetFromAlpha(1)
		hide:SetToAlpha(0)
		hide:SetDuration(0.2)
		local rise = frame.Celebrate:CreateAnimation("Translation")
		rise:SetTarget(arrow)
		rise:SetStartDelay(delay)
		rise:SetOffset(0, 50)
		rise:SetDuration(0.5)
	end

	local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	equip:SetSize(110, 22)
	equip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -14, 2)
	equip:SetText(L.ITEMS_UPGRADE_POPUP_EQUIP)
	equip:SetScript("OnClick", function()
		local entry = table.remove(upgradeQueue, 1)
		-- Only if the item is still in the bags (sorting may have moved it).
		if entry and not InCombatLockdown() and C_Item.GetItemCount(entry.link) > 0 then
			local old = Items.db.upgradeMarkOld and entry.invSlot and GetInventoryItemLink("player", entry.invSlot)
			C_Item.EquipItemByName(entry.link, TargetSlot(entry.link))
			-- The replaced item goes to the bags; with the option it is marked for sale right away.
			if old then
				Items.MarkLinkJunk(old)
			end
		end
		ShowNextUpgrade()
	end)
	local later = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	later:SetSize(110, 22)
	later:SetPoint("RIGHT", equip, "LEFT", -6, 0)
	later:SetText(L.ITEMS_UPGRADE_POPUP_LATER)
	local function Later()
		table.remove(upgradeQueue, 1)
		ShowNextUpgrade()
	end
	later:SetScript("OnClick", Later)
	-- A right click on the toast is "not now".
	frame:SetScript("OnClick", Later)

	-- Escape closes it; the offers stay declined for this session. Hiding for combat keeps them.
	frame:SetScript("OnHide", function(self)
		if not self.combatHide then
			wipe(upgradeQueue)
		end
		self.combatHide = nil
	end)
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
	local border = TOAST_BORDER[quality or 2] or "gold"
	frame.Icon:SetTexture(texture)
	SetAtlasOr(frame.Border, "loottoast-itemborder-" .. border)
	for _, arrow in ipairs(frame.Arrows) do
		SetAtlasOr(arrow, "loottoast-arrow-" .. ((border == "gray" or border == "white") and "green" or border))
	end
	local color = quality and ITEM_QUALITY_COLORS[quality]
	frame.Name:SetText(itemName or entry.link)
	if color then
		frame.Name:SetTextColor(color.r, color.g, color.b)
	end
	local gain = Items.UpgradeGain(entry.score, entry.equippedScore)
	frame.Title:SetText(gain and L.ITEMS_UPGRADE_TOAST_TITLE:format(gain) or L.ITEMS_UPGRADE_TOAST_NEW)
	frame.Score:SetText(gain and L.ITEMS_UPGRADE_POPUP_SCORE:format(entry.equippedScore, entry.score, gain)
		or L.ITEMS_UPGRADE_POPUP_SCORE_NEW:format(entry.score))
	local equipped = entry.invSlot and GetInventoryItemLink("player", entry.invSlot)
	local equippedName = equipped and C_Item.GetItemInfo(equipped)
	frame.Replaces:SetText(equippedName and L.ITEMS_UPGRADE_POPUP_REPLACES:format(equippedName) or L.ITEMS_UPGRADE_POPUP_EMPTY)
	local wasShown = frame:IsShown()
	frame:Show()
	if not wasShown then
		frame.In:Stop()
		frame.In:Play()
	end
	frame.Celebrate:Stop()
	if Items.db.upgradeCelebrate then
		frame.Celebrate:Play()
		if SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then
			PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
		end
	end
end

-- /fp aufwertung: the toast with the first piece of equipment in the bags, to see how it looks.
function Items.PreviewUpgrade()
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and C_Item.IsEquippableItem(link) then
				local score, equippedScore = CompareScores(link)
				if score then
					table.insert(upgradeQueue, 1, { link = link, score = score, equippedScore = equippedScore, invSlot = TargetSlot(link) })
					ShowNextUpgrade()
					return true
				end
			end
		end
	end
	ns.PrintAlways(L.ITEMS_UPGRADE_PREVIEW_NONE)
	return false
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
			-- The cheap question first: only new items are looked at further.
			local info = C_NewItems.IsNewItem(bag, slot) and C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and C_Item.IsEquippableItem(link) then
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

	-- Grey and white items: the action button frame (Visuals, option); the hook on the quality alone does not
	-- reach the bag buttons, this loop does.
	if ns.FrameItemButton then
		ns.FrameItemButton(button, info and info.quality)
	end

	if button.JunkIcon then
		-- Coin on everything that will be sold: grey items (unless kept) and marked items.
		local show = info and not info.hasNoValue and IsJunkItem(info) and not BagExcludesJunk(bag)
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
		button.UpgradeIcon:SetShown(show and true or false)
		-- Usable only at a higher level: the arrow is grey.
		button.UpgradeIcon:SetDesaturated(show == "later")
		button.UpgradeIcon:SetAlpha(show == "later" and 0.75 or 1)
	end
end

local function UpdateContainerFrame(frame)
	if not frame:IsShown() then
		return
	end
	weighStart, weighDone, weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		UpdateButton(button)
	end
	weighActive = false
	if weighDeferred then
		weighDeferred = false
		ns.After("Items: UpdateContainerFrame (timer)", 0.05, function()
			UpdateContainerFrame(frame)
		end)
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

-- Talent and level changes come in bursts: one refresh a moment after the last one.
local weighRefreshQueued = false
local function QueueWeighRefresh()
	if weighRefreshQueued then
		return
	end
	weighRefreshQueued = true
	ns.After("Items: QueueWeighRefresh (timer)", 0.5, function()
		weighRefreshQueued = false
		weights = nil
		ClearWeighCaches()
		UpdateAllBags()
	end)
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

-- Marks an item (by link) for sale, e.g. the item an upgrade replaced; grey items are junk anyway.
function Items.MarkLinkJunk(link)
	local itemID = link and C_Item.GetItemInfoInstant(link)
	local quality = itemID and select(3, C_Item.GetItemInfo(link))
	if not itemID or quality == Enum.ItemQuality.Poor then
		return
	end
	local junk = JunkLists()
	local key, value = JunkKey({ itemID = itemID, hyperlink = link })
	if not junk[key] then
		junk[key] = value
		Report("markMessage", L.ITEMS_MARKED, link)
		UpdateAllBags()
	end
end

-- Marks/unmarks junk with the configured mouse button (middle button by default).
-- OnMouseUp also fires for buttons the item button is not registered to click with.
local function OnItemMouseUp(button, mouseButton)
	-- Alt + middle click marks for the restock list instead.
	local restock = mouseButton == "MiddleButton" and IsAltKeyDown() and ns:GetModule("Restock")
	if restock and restock:ClaimsAltMiddleClick() then
		return
	end
	if mouseButton == Items.db.junkButton and button:IsMouseOver() then
		ToggleJunk(button:GetBagID(), button:GetID())
	end
end

-- Key binding (Bindings.xml): toggles the bag item under the mouse.
function ForeverPlus_ToggleJunkUnderMouse()
	local frame = GetMouseFoci()[1]
	while frame and not frame:IsForbidden() do
		-- Item buttons only (bag windows have GetBagID too).
		if frame.JunkIcon and frame.GetBagID then
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

---------------------------------------------------------------------------
-- Right-click on the bag symbol (portrait) of an open bag: menu with the
-- settings that concern the bags.
---------------------------------------------------------------------------
local MENU_SECTIONS_BAG = {
	{ L.ITEMS_BAGS, { { "Items", "autoSort", "ITEMS_AUTOSORT" }, { "Items", "moneyPickup", "ITEMS_MONEY_PICKUP" } } },
	{ L.ITEMS_DISPLAY, {
		{ "Items", "upgradeArrow", "ITEMS_UPGRADE" }, { "Items", "rewardUpgrade", "ITEMS_REWARD_UPGRADE" }, { "Items", "upgradeScore", "ITEMS_SCORE" },
		{ "Items", "upgradePopup", "ITEMS_UPGRADE_POPUP" },
	} },
	{ L.ITEMS_MERCHANT, {
		{ "Items", "autoSell", "ITEMS_AUTOSELL" }, { "Items", "sellButton", "ITEMS_SELL_BUTTON" },
		{ "Items", "autoRepair", "ITEMS_AUTOREPAIR" },
	} },
}

local MENU_SECTIONS_MERCHANT = {
	{ L.ITEMS_MERCHANT, {
		{ "Items", "autoSell", "ITEMS_AUTOSELL" }, { "Items", "autoRepair", "ITEMS_AUTOREPAIR" },
		{ "Items", "repairGuild", "ITEMS_REPAIR_GUILD" }, { "Items", "sellButton", "ITEMS_SELL_BUTTON" },
		{ "Items", "junkPerCharacter", "ITEMS_JUNK_PER_CHAR" },
	} },
}

local function MenuItems(sections, owner, menuKey)
	local items = {}
	for _, section in ipairs(sections) do
		items[#items + 1] = { text = section[1] }
		for _, entry in ipairs(section[2]) do
			local module = ns:GetModule(entry[1])
			local key, name, desc = entry[2], L[entry[3]], L[entry[3] .. "_DESC"]
			if module and module.db and name then
				items[#items + 1] = {
					text = name,
					checked = module.db[key] and true or false,
					onClick = function()
						module.db[key] = not module.db[key]
						if module.OnOptionChanged then
							module:OnOptionChanged(key, module.db[key])
						end
					end,
					tooltip = desc and function(tooltip)
						tooltip:SetText(name, 1, 1, 1)
						tooltip:AddLine(desc, nil, nil, nil, true)
					end,
				}
			end
		end
	end
	items[#items + 1] = { text = L.ITEMS_JUNK_LIST }
	items[#items + 1] = { text = L.ITEMS_JUNK_SHOW, onClick = function()
		local menu = _G["ForeverPlusPopup" .. menuKey]
		if menu then
			menu:Hide()
		end
		ns.After("Items: onClick (timer)", 0, function()
			Items:ShowJunkMenu(owner)
		end)
	end }
	items[#items + 1] = { text = L.ITEMS_BAG_MENU_ALL, onClick = function()
		ns:OpenSettings(Items)
	end }
	return items
end

function Items:ShowBagMenu(owner)
	ns.ShowPopupList(owner, function()
		return { title = L.ITEMS_BAG_MENU_TITLE, items = MenuItems(MENU_SECTIONS_BAG, owner, "BagMenu"), width = 340 }
	end, "BagMenu")
end

function Items:ShowMerchantMenu(owner)
	ns.ShowPopupList(owner, function()
		return { title = L.ITEMS_MERCHANT_MENU_TITLE, items = MenuItems(MENU_SECTIONS_MERCHANT, owner, "MerchantMenu"), width = 340 }
	end, "MerchantMenu")
end

local bagMenuHooked = {}

local function HookBagMenu(owner, frame)
	if not owner or bagMenuHooked[owner] then
		return
	end
	bagMenuHooked[owner] = true
	owner:HookScript("OnMouseDown", function(self, button)
		if button ~= "RightButton" or not Items.db.bagMenu then
			return
		end
		-- Blizzard's own menu (opened by any button on the title bar) makes room for ours.
		if frame.PortraitButton and frame.PortraitButton.CloseMenu then
			frame.PortraitButton:CloseMenu()
		end
		Items:ShowBagMenu(frame.PortraitButton or self)
	end)
end

local function HookBagFrameMenu(frame)
	if not frame or not frame.PortraitButton then
		return
	end
	HookBagMenu(frame.PortraitButton, frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.routeToSibling == "PortraitButton" then
			HookBagMenu(child, frame)
		end
	end
end

local function PostUpdateItems(frame)
	weighStart, weighDone, weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnMouseUp", OnItemMouseUp)
		end
		UpdateButton(button)
	end
	weighActive = false
	if weighDeferred then
		weighDeferred = false
		ns.After("Items: PostUpdateItems (timer)", 0.05, function()
			UpdateContainerFrame(frame)
		end)
	end
end

-- Money of the backpack: Blizzard's click opens the currency tab; here a click takes up coins again
-- (a window asks for the amount, then the coins hang on the cursor like an item), Shift + click
-- opens the currency tab as before. Own click areas lie on the coin buttons.
local moneyAreas = {}
local hookedMoney = setmetatable({}, { __mode = "k" })

-- "12g 5s 3k", "12 g", "5s" or a bare number (gold) in copper; nil when it cannot be read.
local function ParseMoney(text)
	local total, found = 0, false
	for number, unit in (text or ""):lower():gsub(",", "."):gmatch("(%d+%.?%d*)%s*([gsk]?)") do
		local value = tonumber(number)
		if value then
			found = true
			total = total + value * (unit == "s" and 100 or unit == "k" and 1 or 10000)
		end
	end
	return found and math.floor(total + 0.5) or nil
end

-- Own window for the amount, when Blizzard's window does not come up.
local function AskMoney()
	ns.ShowEditWindow("MoneyPickup", L.ITEMS_MONEY_TIP, "", ACCEPT, function(text)
		local copper = ParseMoney(text)
		if not copper or copper <= 0 then
			return
		end
		if copper > GetMoney() then
			ns.Print(L.ITEMS_MONEY_TOO_MUCH)
			return
		end
		local ok, err = pcall(PickupPlayerMoney, copper)
		if not ok then
			ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
		end
	end, L.ITEMS_MONEY_HINT)
end

local lastMoneyClick, characterWasShown = 0, false

local function MoneyClick(moneyFrame, afterBlizzard)
	-- A click can arrive twice (our area and the hook on the game's button): once is enough.
	if GetTime() - lastMoneyClick < 0.3 then
		return
	end
	lastMoneyClick = GetTime()
	if afterBlizzard then
		-- The game's own button already ran: Shift + click is meant to open the currency tab; otherwise that tab
		-- (opened by the click, not before it) closes again.
		if IsShiftKeyDown() then
			return
		end
		if CharacterFrame and CharacterFrame:IsShown() and not characterWasShown and not InCombatLockdown() then
			HideUIPanel(CharacterFrame)
		end
	end
	if GetCursorMoney() > 0 then
		local ok, err = pcall(DropCursorMoney)
		if not ok then
			ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
		end
		return
	end
	if IsShiftKeyDown() or not (MoneyInputFrame_OpenPopup and MoneyTypeInfo and MoneyTypeInfo.PLAYER) then
		-- Blizzard's own behaviour (currency tab).
		if MoneyInputFrame_OpenPopup then
			MoneyInputFrame_OpenPopup(moneyFrame)
		end
		return
	end
	-- A stand-in without the currency flag: Blizzard's window asks how much to take up.
	local ok, err = pcall(MoneyInputFrame_OpenPopup, { info = MoneyTypeInfo.PLAYER })
	if not ok then
		ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
	end
	-- If the window did not come up, the own one does.
	ns.After("Items: MoneyClick (timer)", 0.3, function()
		if not (StaticPopup_Visible and StaticPopup_Visible("PICKUP_MONEY")) then
			AskMoney()
		end
	end)
end

local function HookMoneyFrame(moneyFrame)
	if not moneyFrame then
		return
	end
	for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
		local button = moneyFrame[key]
		if button and not moneyAreas[button] then
			local area = CreateFrame("Button", nil, button)
			area:SetAllPoints(button)
			area:SetFrameLevel(button:GetFrameLevel() + 3)
			area:SetScript("OnClick", function()
				MoneyClick(moneyFrame)
			end)
			area:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(L.ITEMS_MONEY_TIP, 1, 1, 1)
				GameTooltip:AddLine(L.ITEMS_MONEY_TIP_PICK, nil, nil, nil, true)
				GameTooltip:AddLine(L.ITEMS_MONEY_TIP_CURRENCY, 0.7, 0.7, 0.7, true)
				GameTooltip:Show()
			end)
			area:SetScript("OnLeave", GameTooltip_Hide)
			moneyAreas[button] = area
		end
		if moneyAreas[button] then
			moneyAreas[button]:SetShown(Items.db.moneyPickup and true or false)
		end
		-- Safety net: if the click does not reach our area (covered, other geometry), the game's own button
		-- still tells us (hooks only add, nothing of the game's click is changed).
		if button and not hookedMoney[button] then
			hookedMoney[button] = true
			button:HookScript("OnMouseDown", function()
				characterWasShown = CharacterFrame and CharacterFrame:IsShown() or false
			end)
			for _, script in ipairs({ "OnClick", "OnMouseUp" }) do
				button:HookScript(script, function(_, mouseButton)
					if Items.db.moneyPickup and (mouseButton == nil or mouseButton == "LeftButton") then
						MoneyClick(moneyFrame, true)
					end
				end)
			end
		end
	end
end

-- /fp geld: without an amount the state of the click areas and the amount window; with an amount ("12g 5s")
-- the coins are taken up directly, which shows whether the game lets an addon do that.
function Items.MoneyCommand(argument)
	argument = strtrim(argument or "")
	if argument ~= "" then
		local copper = ParseMoney(argument)
		if not copper or copper <= 0 or copper > GetMoney() then
			ns.PrintAlways(L.ITEMS_MONEY_TOO_MUCH)
			return
		end
		local ok, err = pcall(PickupPlayerMoney, copper)
		ns.PrintAlways(ok and L.ITEMS_MONEY_TRIED or L.ITEMS_MONEY_ERROR, ok and GetCursorMoney() or tostring(err))
		return
	end
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		local moneyFrame = frame and frame.MoneyFrame
		if moneyFrame then
			for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
				local button = moneyFrame[key]
				local area = button and moneyAreas[button]
				ns.PrintAlways(L.ITEMS_MONEY_STATUS, frame:GetName() or "?", key, tostring(area ~= nil), tostring(area and area:IsShown()),
					tostring(area and area:IsMouseEnabled()), ns.Number(area and area:GetWidth(), 0), ns.Number(area and area:GetHeight(), 0),
					tostring(button and button:IsShown()), ns.Number(area and area:GetFrameLevel(), 0))
			end
		end
	end
	AskMoney()
end

local function HookContainerFrames()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		HookBagFrameMenu(frame)
		HookMoneyFrame(frame.MoneyFrame)
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
		for slot = 1, BagExcludesJunk(bag) and 0 or C_Container.GetContainerNumSlots(bag) do
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
		sellTicker = ns.NewTicker("Items: SellBatch", SELL_INTERVAL, SellBatch)
	end
end

-- Count and value of the junk in the bags (same rules as selling).
local function JunkValue()
	local count, value = 0, 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, BagExcludesJunk(bag) and 0 or C_Container.GetContainerNumSlots(bag) do
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

-- For the merchant list in the dialog bubble (Modules/Dialog.lua).
ns.MerchantTools = { SellJunk = StartSelling, JunkValue = JunkValue, Repair = Repair }

-- Blizzard's sell-junk button sells every grey item, including kept ones.
-- A button of our own lies on top and sells by the junk rules instead.
local sellButton

local function UpdateSellButton()
	-- MerchantFrame updates on every bag change, also with the window closed.
	if not sellButton or not sellButton:IsVisible() then
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
	sellButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	sellButton:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			if Items.db.bagMenu then
				Items:ShowMerchantMenu(self)
			end
		elseif merchantOpen then
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
		if Items.db.bagMenu then
			GameTooltip_AddInstructionLine(GameTooltip, L.ITEMS_MERCHANT_MENU_HINT)
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
-- The last steps of sorting with their time (/fp taschen verlauf): who sorted, when the layout counted as settled. For seeing in what order things happen when the bags look odd.
Items.trace = {}
function Items.Trace(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	if #Items.trace >= 80 then
		table.remove(Items.trace, 1)
	end
	Items.trace[#Items.trace + 1] = ("%.2f %s"):format(ns.Number(GetTime(), 0) % 1000, text)
end

function Items.PrintTrace()
	ns.ShowTrace(L.ITEMS_TRACE:format(#Items.trace), Items.trace)
end

local SORT_PAUSE = 3 -- seconds between automatic sorts
local SORT_CHECK = 0.4 -- seconds between looks at the bags while a sort runs
local SETTLE = 1.5 -- seconds the layout of the bags must stay the same (and unlocked) for a sort to count as over
local SETTLE_LOOK = 0.25 -- seconds between two looks at the layout
local SORT_MAX = 15 -- seconds after which a sort counts as over whatever the bags show
local lastSort, sortQueued, sorting = 0, false, false
-- Layout of the bags after the last finished sort (items and counts). While it is unchanged, opening the bags sorts
-- nothing.
local sortedLayout
local RecordLayout -- below

-- Windows in which items are moved by other things: no sorting in them.
local TRADE_WINDOWS = { "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame",
	"ScrappingMachineFrame", "ItemSocketingFrame" }

local function OtherWindowOpen()
	for _, name in ipairs(TRADE_WINDOWS) do
		local frame = _G[name]
		if frame and frame.IsShown and frame:IsShown() then
			return true
		end
	end
	return false
end

-- An item is locked (grey) while the game moves it.
local function AnyLocked()
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then
				return true
			end
		end
	end
	return false
end

-- The game's cleanup works in bursts with pauses (the server moves the items); "no bag update for a moment" took
-- such a pause for the end and the marked items were placed in a half-finished layout, which the rest of the cleanup
-- then undid a few seconds later. A layout counts as settled when it has not changed for SETTLE seconds and no
-- item is locked.
local settle = { signature = nil, since = 0, checked = 0, result = false }

local function ResetSettle()
	settle.signature, settle.since, settle.checked, settle.result = nil, GetTime(), 0, false
end

local function LayoutSettled(need)
	local now = GetTime()
	if now - settle.checked < SETTLE_LOOK and not need then
		return settle.result
	end
	settle.checked = now
	local signature = Items.LayoutSignature()
	if signature ~= settle.signature then
		settle.signature, settle.since = signature, now
	end
	settle.result = now - settle.since >= (need or SETTLE) and not AnyLocked()
	return settle.result
end

-- The game sorts in steps over a while. A new sort before it is over (or
-- while items are still locked) would work against the first and leave
-- the items locked, so a sort counts as running until the bags have been
-- quiet for a moment.
local function WatchSort()
	sorting = true
	local waited = 0
	ResetSettle()
	ns.NewTicker("Items: WatchSort (timer)", SORT_CHECK, function(ticker)
		waited = waited + SORT_CHECK
		if LayoutSettled() or waited >= SORT_MAX then
			Items.Trace("Sortieren beendet nach %.1f s (%s)", waited, waited >= SORT_MAX and "Zeitgrenze" or "Belegung ruhig")
			sorting = false
			lastSort = GetTime()
			ticker:Cancel()
			RecordLayout()
		end
	end)
end

local function SortOnOpen()
	sortQueued = false
	-- Not while selling, in combat, with an item on the cursor, in a window that moves items or during a sort.
	if not Items.db.autoSort or InCombatLockdown() or sellTicker or GetCursorInfo() or sorting or OtherWindowOpen() then
		return
	end
	local now = GetTime()
	if now - lastSort < SORT_PAUSE or AnyLocked() then
		Items.Trace("Öffnen: nicht sortiert (Pause oder Gegenstand gesperrt)")
		return
	end
	if Items.db.sortSkip and sortedLayout and sortedLayout == Items.LayoutSignature() then
		Items.Trace("Öffnen: nicht sortiert (Belegung unverändert)")
		return
	end
	lastSort = now
	Items.sortSource = "Addon beim Öffnen"
	C_Container.SortBags()
	Items.sortSource = nil
	WatchSort()
end

function Items.LayoutSignature()
	local parts = {}
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			parts[#parts + 1] = info and (tostring(info.itemID) .. "x" .. tostring(info.stackCount)) or "-"
		end
	end
	return table.concat(parts, ",")
end

-- Called when a sort is over.
function RecordLayout()
	if not sorting and not InCombatLockdown() then
		Items.Trace("Stand gemerkt")
		sortedLayout = Items.LayoutSignature()
	end
end

-- Marked junk is not moved after a sort any more: the game's cleanup puts each item back in its place, so the marked
-- items jumped to and fro on every sort. They keep their coin and are sold with the greys.
local function OnSortStarted()
	Items.Trace("Sortieren gestartet von: %s", Items.sortSource or "Blizzard (Knopf, Taschenmenü) oder anderes")
end

-- The game's cleanup button: while nothing changed since the last finished sort it does nothing.
local sortOverlay

local function BagsUnchanged()
	return Items.db.sortSkip and sortedLayout and not sorting and not InCombatLockdown()
		and sortedLayout == Items.LayoutSignature()
end

local function UpdateSortOverlay()
	local parent = _G.BagItemAutoSortButton
	if not parent then
		return
	end
	if not sortOverlay then
		sortOverlay = CreateFrame("Button", nil, parent)
		sortOverlay:SetAllPoints()
		sortOverlay:SetFrameLevel(ns.Number(parent:GetFrameLevel(), 1) + 2)
		sortOverlay:RegisterForClicks("LeftButtonUp")
		sortOverlay:SetScript("OnClick", function()
			if BagsUnchanged() then
				return
			end
			PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			Items.sortSource = "Knopf (Aufräumen)"
			C_Container.SortBags()
			Items.sortSource = nil
		end)
		sortOverlay:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self)
			GameTooltip_SetTitle(GameTooltip, BAG_CLEANUP_BAGS, HIGHLIGHT_FONT_COLOR)
			GameTooltip_AddNormalLine(GameTooltip, BAG_CLEANUP_BAGS_DESCRIPTION)
			if BagsUnchanged() then
				GameTooltip_AddInstructionLine(GameTooltip, L.ITEMS_SORT_DONE)
			end
			GameTooltip:Show()
		end)
		sortOverlay:SetScript("OnLeave", GameTooltip_Hide)
	end
	sortOverlay:SetShown(Items.db.sortSkip and true or false)
end

-- Opening all bags opens each frame; one sort after the last of them.
local function QueueSort()
	if Items.db.autoSort and not sortQueued then
		sortQueued = true
		ns.After("Items: SortOnOpen", 0, SortOnOpen)
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
		-- The coin of the junk mark in the bags marks the most valuable reward.
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

-- Index of the most valuable choice (by vendor price) of the open quest; nil with fewer than two
-- choices, with the option off, or while item data is still loading (onLoaded runs then).
function ns.BestQuestChoice(onLoaded)
	if not Items.db or not Items.db.questReward or (GetNumQuestChoices() or 0) < 2 then
		return nil
	end
	local bestIndex, bestValue, waiting = nil, 0, false
	for i = 1, GetNumQuestChoices() do
		local link = GetQuestItemLink("choice", i)
		if link then
			local price = select(11, C_Item.GetItemInfo(link))
			if price == nil then
				waiting = true
				if onLoaded then
					Item:CreateFromItemLink(link):ContinueOnItemLoad(onLoaded)
				end
			else
				local _, _, count = GetQuestItemInfo("choice", i)
				local value = price * max(count or 1, 1)
				if value > bestValue then
					bestIndex, bestValue = i, value
				end
			end
		end
	end
	return not waiting and bestIndex or nil
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

-- Green arrow on the items of a quest (offered choices and sure rewards, also in the quest log) that
-- are better than the worn ones.
local rewardArrows = {}

local function GetRewardArrow(button)
	local arrow = rewardArrows[button]
	if not arrow then
		arrow = CreateFrame("Frame", nil, button)
		arrow:SetAllPoints(button.Icon or button.icon or button)
		arrow:SetFrameLevel(button:GetFrameLevel() + 6)
		local texture = arrow:CreateTexture(nil, "OVERLAY", nil, 3)
		texture:SetAtlas("bags-greenarrow", true)
		texture:SetPoint("TOPRIGHT", 0, 0)
		rewardArrows[button] = arrow
	end
	return arrow
end

local function MarkRewardUpgrades()
	for _, arrow in pairs(rewardArrows) do
		arrow:Hide()
	end
	if not Items.db.rewardUpgrade then
		return
	end
	local rewardsFrame = QuestInfoFrame.rewardsFrame
	local getLink = QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button:IsShown() and button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
			if ns.IsRewardUpgrade(getLink(button.type, button:GetID()), MarkRewardUpgrades) then
				GetRewardArrow(button):Show()
			end
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
	local frame = ns.CreatePanel("ForeverPlusDestroyDialog", { close = true })
	frame:SetSize(360, 150)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
	frame.Title:SetText(L.ITEMS_BAGS_FULL)

	frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	frame.Icon:SetSize(36, 36)
	frame.Icon:SetPoint("TOPLEFT", ns.PANEL_PADDING + 2, -36)
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
		-- Only if that slot still holds the offered item (the bags may have changed).
		local info = entry and C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if info and info.hyperlink == entry.link and not InCombatLockdown() then
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

-- A sound when the bags have just become full (the last free slot taken) or an item found no room.
Items.fullState = { last = 0 }

function Items.PlayFullSound()
	local state = Items.fullState
	local now = GetTime()
	if now - state.last < 3 then
		return
	end
	state.last = now
	if ns.AlertSounds then
		ns.AlertSounds.play(Items.db.fullSoundChoice)
	end
end

-- Free slots of the bags that take any item (not those of special bags).
function Items.FreeSlots()
	local free = 0
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			free = free + ns.Number(slots, 0)
		end
	end
	return free
end

function Items.CheckFull()
	local state = Items.fullState
	local full = Items.FreeSlots() == 0
	if full and state.wasFull == false then
		Items.PlayFullSound()
	end
	state.wasFull = full
end

function Items:UpdateFullSound()
	local state = self.fullState
	if not state.frame then
		state.frame = CreateFrame("Frame")
		state.frame:SetScript("OnEvent", ns.Measured("Items: bags full", function(_, event, _, message)
			if event == "UI_ERROR_MESSAGE" then
				if not ns.Secret(message) and message == ERR_INV_FULL then
					Items.PlayFullSound()
				end
			else
				Items.CheckFull()
			end
		end))
	end
	if self.db.fullSound then
		state.frame:RegisterEvent("BAG_UPDATE_DELAYED")
		state.frame:RegisterEvent("UI_ERROR_MESSAGE")
		if state.wasFull == nil then
			state.wasFull = Items.FreeSlots() == 0 -- the state now, so there is no sound at login with full bags
		end
	else
		state.frame:UnregisterAllEvents()
		state.wasFull = nil
	end
end

function Items:UI_ERROR_MESSAGE(_, _, message)
	if ns.Secret(message) then
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
	ns.After("Items: HidePopup (timer)", 0, function()
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

-- Equipping or using an item that binds.
local function EquipBound(self, _, slot)
	EquipPendingItem(slot)
	HidePopup("EQUIP_BIND")
	HidePopup("EQUIP_BIND_REFUNDABLE")
	HidePopup("EQUIP_BIND_TRADEABLE")
end

function Items:USE_BIND_CONFIRM()
	ConfirmBindOnUse()
	HidePopup("USE_BIND")
end

-- Deleting valuable items asks to type the word; the text is entered, the
-- confirming click stays with the player (deleting is closed to addons).
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local function FillDeleteText(which)
	if not DELETE_POPUPS[which] or not Items.db.deleteText then
		return
	end
	local dialog = StaticPopup_FindVisible(which)
	local editBox = dialog and dialog:GetEditBox()
	if editBox and DELETE_ITEM_CONFIRM_STRING then
		editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
	end
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
	return link and not ns.Secret(link) and C_Item.GetItemInfoInstant(link)
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
						if states[roll.state] and not ns.Secret(roll.playerName) then
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
			sellButton:GetParent().Icon:SetDesaturated(C_MerchantFrame.GetNumJunkItems() == 0)
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
	self:UpdateFullSound()
	self:ToggleEvent("EQUIP_BIND_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("EQUIP_BIND_TRADEABLE_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("EQUIP_BIND_REFUNDABLE_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("USE_BIND_CONFIRM", db.autoEquipBind)
	self:ToggleEvent("LOOT_BIND_CONFIRM", db.autoBind)
	self:ToggleEvent("CONFIRM_LOOT_ROLL", db.autoBind)
	self:ToggleEvent("LOOT_HISTORY_UPDATE_DROP", db.rollCounts)
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
	local weighs = db.upgradeArrow or db.upgradePopup or db.upgradeScore or db.rewardUpgrade
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", weighs, function()
		ClearWeighCaches()
		UpdateAllBags()
	end)
	-- Level, specialization and talent changes alter the stat weights.
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
		if C_EventUtils.IsEventValid(event) then
			self:ToggleEvent(event, weighs, QueueWeighRefresh)
		end
	end
end

function Items:OnInitialize()
	-- Former single switch for all messages of this module.
	if self.db.messages == false then
		self.db.sellMessage, self.db.repairMessage, self.db.markMessage = false, false, false
	end
	self.db.messages = nil
	-- Marked junk is no longer moved after a sort (the option is gone).
	self.db.sortMarkedJunk = nil
	-- The choice of the rating belongs to the character.
	for _, opt in ipairs(Items.options) do
		if opt.key == "scoreSpec" then
			opt.db = self.cdb
		end
	end
end

function Items:OnLogin()
	HookContainerFrames()
	hooksecurefunc("StaticPopup_Show", FillDeleteText)
	HookRollFrames()
	if C_Container.SortBags then
		hooksecurefunc(C_Container, "SortBags", OnSortStarted)
	end
	UpdateSortOverlay()
	EventRegistry:RegisterCallback("ContainerFrame.OpenBag", QueueSort, self)
	EventRegistry:RegisterCallback("ContainerFrame.OpenAllBags", QueueSort, self)
	hooksecurefunc("QuestInfo_Display", MarkBestReward)
	hooksecurefunc("QuestInfo_Display", MarkRewardUpgrades)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Items: tooltip rating", AddScoreLine))
	self:Refresh()
end

function Items:OnOptionChanged(key)
	if key == "sortSkip" then
		UpdateSortOverlay()
	elseif key == "scoreSpec" then
		QueueWeighRefresh()
	end
	-- A character list starts as a copy of the account list.
	if key == "junkPerCharacter" and self.db.junkPerCharacter
		and next(self.cdb.junk) == nil and next(self.cdb.keep) == nil then
		self.cdb.junk = CopyTable(self.db.junk)
		self.cdb.keep = CopyTable(self.db.keep)
	end
	self:Refresh()
	UpdateAllBags()
	if key == "moneyPickup" then
		for _, area in pairs(moneyAreas) do
			area:SetShown(self.db.moneyPickup and true or false)
		end
	end
	if QuestInfoFrame:IsVisible() then
		MarkBestReward()
		MarkRewardUpgrades()
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
	{ key = "junkList", type = "button", name = L.ITEMS_JUNK_LIST, text = L.ITEMS_JUNK_SHOW, desc = L.ITEMS_JUNK_LIST_DESC, func = function(button)
		Items:ShowJunkMenu(button)
	end },
	{ type = "header", name = L.ITEMS_BAGS },
	{ key = "autoSort", type = "toggle", name = L.ITEMS_AUTOSORT, desc = L.ITEMS_AUTOSORT_DESC },
	{ key = "sortSkip", type = "toggle", name = L.ITEMS_SORT_SKIP, desc = L.ITEMS_SORT_SKIP_DESC, new = true },
	{ key = "bagMenu", type = "toggle", name = L.ITEMS_BAG_MENU, desc = L.ITEMS_BAG_MENU_DESC },
	{ key = "moneyPickup", type = "toggle", name = L.ITEMS_MONEY_PICKUP, desc = L.ITEMS_MONEY_PICKUP_DESC, new = true },
	{ key = "fullSound", type = "toggle", name = L.ITEMS_FULL_SOUND, desc = L.ITEMS_FULL_SOUND_DESC, new = true },
	{ key = "fullSoundChoice", type = "dropdown", name = L.ITEMS_FULL_SOUND_CHOICE, parent = "fullSound", new = true, values = function()
		return ns.AlertSounds and ns.AlertSounds.choices or {}
	end },
	{ type = "button", name = L.ITEMS_FULL_SOUND_TEST, text = L.QUESTS_TEST, func = function()
		if ns.AlertSounds then
			ns.AlertSounds.play(Items.db.fullSoundChoice)
		end
	end },
	{ type = "header", name = L.ITEMS_DISPLAY },
	{ key = "questReward", type = "toggle", name = L.ITEMS_QUEST_REWARD, desc = L.ITEMS_QUEST_REWARD_DESC },
	{ key = "upgradeArrow", type = "toggle", name = L.ITEMS_UPGRADE, desc = L.ITEMS_UPGRADE_DESC },
	{ key = "rewardUpgrade", type = "toggle", name = L.ITEMS_REWARD_UPGRADE, desc = L.ITEMS_REWARD_UPGRADE_DESC, new = true },
	{ key = "scoreSpec", type = "dropdown", name = L.ITEMS_SCORE_SPEC, desc = L.ITEMS_SCORE_SPEC_DESC, default = 0,
		values = ScoreSpecValues, new = true },
	{ key = "upgradeScore", type = "toggle", name = L.ITEMS_SCORE, desc = L.ITEMS_SCORE_DESC },
	{ key = "upgradePopup", type = "toggle", name = L.ITEMS_UPGRADE_POPUP, desc = L.ITEMS_UPGRADE_POPUP_DESC },
	{ key = "upgradeCelebrate", type = "toggle", name = L.ITEMS_UPGRADE_CELEBRATE, desc = L.ITEMS_UPGRADE_CELEBRATE_DESC, parent = "upgradePopup", new = true },
	{ key = "upgradeMarkOld", type = "toggle", name = L.ITEMS_UPGRADE_MARK_OLD, desc = L.ITEMS_UPGRADE_MARK_OLD_DESC, parent = "upgradePopup", new = true },
	{ type = "header", name = L.ITEMS_LOOT },
	{ key = "fastLoot", type = "toggle", name = L.ITEMS_FASTLOOT, desc = L.ITEMS_FASTLOOT_DESC },
	{ key = "destroyPrompt", type = "toggle", name = L.ITEMS_DESTROY, desc = L.ITEMS_DESTROY_DESC },
	{ key = "autoBind", type = "toggle", name = L.ITEMS_AUTOBIND, desc = L.ITEMS_AUTOBIND_DESC },
	{ key = "autoEquipBind", type = "toggle", name = L.ITEMS_AUTOEQUIPBIND, desc = L.ITEMS_AUTOEQUIPBIND_DESC },
	{ key = "deleteText", type = "toggle", name = L.ITEMS_DELETETEXT, desc = L.ITEMS_DELETETEXT_DESC },
	{ key = "rollCounts", type = "toggle", name = L.ITEMS_ROLL_COUNTS, desc = L.ITEMS_ROLL_COUNTS_DESC },

}

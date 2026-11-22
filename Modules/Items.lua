-- Items: junk selling and marking, auto repair, quest reward value,
-- upgrade arrows in bags and loot, and fast looting.
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
		fullSoundChoice = "warning",
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

local upgradeCache = {}     -- hyperlink -> comparison state in the bags
local linkUpgradeCache = {} -- hyperlink -> comparison state outside the bags
local scoreCache = {}      -- hyperlink (+ ranged) -> base score and bonus against Humanoids
local equippedCache = {}   -- inventory slot -> base score and bonus against Humanoids

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

-- PvE defaults for Forever. Flat stats and weapon DPS are weighted per point.
-- Combat chances and haste are weighted per percentage point (see RATING_STATS).
-- Damage profiles use rounded reference-build EP and leveling allowances. Healing
-- and mitigation weights are estimates based on the priorities in DATA-SOURCES.md.
local PROTECTION_SPELL_POWER = 0.8
local PROTECTION_PALADIN = {
	STA = 1.5, STR = 0.8, AP = 0.35, AGI = 0.8, INT = 0.5, SP = PROTECTION_SPELL_POWER,
	DEF = 1.5, DODGE = 8, PARRY = 8, BLOCK = 12, BVAL = 0.5, ARMOR = 0.1, DPS = 5, HOLY = PROTECTION_SPELL_POWER,
	HIT = 21 * PROTECTION_SPELL_POWER, SHIT = 9 * PROTECTION_SPELL_POWER, CRIT = 12 * PROTECTION_SPELL_POWER,
	EXPERTISE = 15 * PROTECTION_SPELL_POWER, HASTE = 7 * PROTECTION_SPELL_POWER,
}
local FERAL_BEAR = {
	AGI = 1.3, STA = 1.8, STR = 0.9, AP = 0.45, ARMOR = 0.16, DEF = 1.5, DODGE = 9,
	DPS = 8, HIT = 9, EXPERTISE = 16, CRIT = 8, HASTE = 5, ARP = 0.08,
}
-- Left to right, matching the game's talent groups and the standard plans.
local WEIGHTS = {
	WARRIOR = {
		-- Arms
		{ STR = 2, AGI = 1.7, STA = 0.3, AP = 0.9, DPS = 14, RDPS = 1,
			HIT = 22, CRIT = 30, EXPERTISE = 21, HASTE = 17, ARP = 0.4, ARMOR = 0.01 },
		-- Fury
		{ STR = 2, AGI = 1.6, STA = 0.3, AP = 0.9, DPS = 14, RDPS = 1,
			HIT = 27, CRIT = 29, EXPERTISE = 31, HASTE = 17, ARP = 0.4, ARMOR = 0.01 },
		-- Protection
		{ STA = 1.7, AGI = 1.15, STR = 0.95, AP = 0.45, ARMOR = 0.13, DEF = 1.25,
			DODGE = 9, PARRY = 9, BLOCK = 7, BVAL = 0.65, DPS = 6,
			HIT = 12, EXPERTISE = 16, CRIT = 9, HASTE = 6, ARP = 0.15 },
	},
	PALADIN = {
		-- Holy
		{ HEAL = 1, SP = 0.85, INT = 0.85, SPI = 0.55, MP5 = 0.5, SCRIT = 6, SHASTE = 4, STA = 0.3, ARMOR = 0.005 },
		PROTECTION_PALADIN,
		-- Retribution
		{ STR = 2, AGI = 2.5, INT = 2.9, SP = 3.8, HOLY = 3.8, AP = 0.8, STA = 0.3, DPS = 14,
			HIT = 21, SHIT = 8, EXPERTISE = 50, CRIT = 44, HASTE = 26, ARP = 0.2, ARMOR = 0.01 },
	},
	HUNTER = {
		-- Beast Mastery
		{ AGI = 2, INT = 1.2, STR = 0.2, STA = 0.3, RAP = 0.6, AP = 0.2, MP5 = 0.5,
			HIT = 28, CRIT = 25, HASTE = 8, EXPERTISE = 14, ARP = 0.25, RDPS = 14, DPS = 3, ARMOR = 0.01 },
		-- Marksmanship
		{ AGI = 2, INT = 1.15, STR = 0.2, STA = 0.3, RAP = 0.6, AP = 0.2, MP5 = 0.4,
			HIT = 22, CRIT = 24, HASTE = 8, EXPERTISE = 6, ARP = 0.25, RDPS = 15, DPS = 3, ARMOR = 0.01 },
		-- Survival, assumes a mix of melee and ranged attacks
		{ AGI = 2, INT = 1.35, STR = 0.35, STA = 0.3, RAP = 0.4, AP = 0.3, MP5 = 0.75,
			HIT = 24, CRIT = 22, HASTE = 8, EXPERTISE = 12, ARP = 0.25, RDPS = 12, DPS = 11, ARMOR = 0.01 },
	},
	ROGUE = {
		-- Assassination
		{ AGI = 2.05, STR = 1.1, STA = 0.3, AP = 1, DPS = 14, HIT = 19, CRIT = 26, EXPERTISE = 30, HASTE = 14, ARP = 0.42, ARMOR = 0.01 },
		-- Combat
		{ AGI = 1.8, STR = 1.1, STA = 0.3, AP = 1, DPS = 14, HIT = 23, CRIT = 19, EXPERTISE = 28, HASTE = 16, ARP = 0.35, ARMOR = 0.01 },
		-- Subtlety
		{ AGI = 1.9, STR = 1.1, STA = 0.3, AP = 1, DPS = 14, HIT = 21, CRIT = 22, EXPERTISE = 26, HASTE = 15, ARP = 0.26, ARMOR = 0.01 },
	},
	PRIEST = {
		-- Discipline
		{ HEAL = 1, SP = 0.9, MP5 = 0.8, SPI = 0.65, INT = 0.55, SCRIT = 5, SHASTE = 4, STA = 0.3, ARMOR = 0.005 },
		-- Holy
		{ HEAL = 1, SP = 0.85, MP5 = 0.75, SPI = 0.7, INT = 0.5, SCRIT = 4, SHASTE = 3, STA = 0.3, ARMOR = 0.005 },
		-- Shadow
		{ SP = 1, SHADOW = 1, SHIT = 12, SCRIT = 13, SHASTE = 6.5, INT = 0.3, SPI = 0.08, STA = 0.25, MP5 = 0.25, ARMOR = 0.005 },
	},
	SHAMAN = {
		-- Elemental
		{ SP = 1, NATURE = 0.9, SHIT = 13, SCRIT = 10, SHASTE = 9.5, INT = 0.35, SPI = 0.15, MP5 = 0.35, STA = 0.3, ARMOR = 0.005 },
		-- Enhancement, adjusted for the November 10 Mental Dexterity and Windfury changes
		{ STR = 2.2, AGI = 1.4, INT = 1.15, STA = 0.3, AP = 1, SP = 0.65, DPS = 14,
			HIT = 18, SHIT = 12, CRIT = 22, HASTE = 20, EXPERTISE = 36, ARP = 0.35, ARMOR = 0.01 },
		-- Restoration
		{ HEAL = 1, SP = 0.85, INT = 0.62, SPI = 0.42, MP5 = 0.45, SCRIT = 10, SHASTE = 5, STA = 0.3, ARMOR = 0.005 },
	},
	MAGE = {
		-- Arcane
		{ SP = 1, ARCANE = 0.9, SHIT = 18, SCRIT = 11, SHASTE = 6.5, INT = 1, SPI = 0.35, MP5 = 0.45, STA = 0.3, ARMOR = 0.005 },
		-- Fire
		{ SP = 1, FIRE = 0.9, ARCANE = 0.1, SHIT = 15, SCRIT = 11, SHASTE = 3, INT = 0.5, SPI = 0.3, MP5 = 0.25, STA = 0.3, ARMOR = 0.005 },
		-- Frost
		{ SP = 1, FROST = 0.8, ARCANE = 0.2, SHIT = 16, SCRIT = 9.5, SHASTE = 12, INT = 0.27, SPI = 0.10, MP5 = 0.15, STA = 0.20, ARMOR = 0.005 },
	},
	WARLOCK = {
		-- Affliction
		{ SP = 1, SHADOW = 1, SHIT = 8, SCRIT = 9.5, SHASTE = 3, INT = 0.2, SPI = 0.3, MP5 = 0.1, STA = 0.45, ARMOR = 0.005 },
		-- Demonology
		{ SP = 1, SHADOW = 0.8, FIRE = 0.2, SHIT = 13, SCRIT = 11, SHASTE = 9, INT = 0.45, SPI = 0.3, MP5 = 0.25, STA = 0.5, ARMOR = 0.005 },
		-- Destruction
		{ SP = 1, FIRE = 0.75, SHADOW = 0.55, SHIT = 12, SCRIT = 12, SHASTE = 8, INT = 0.5, SPI = 0.28, MP5 = 0.3, STA = 0.4, ARMOR = 0.005 },
	},
	DRUID = {
		-- Balance
		{ SP = 1, ARCANE = 0.65, NATURE = 0.35, SHIT = 11, SCRIT = 9.5, SHASTE = 8.5, INT = 0.3, SPI = 0.10, MP5 = 0.2, STA = 0.25, ARMOR = 0.005 },
		-- Feral (cat)
		{ AGI = 2, STR = 1.8, STA = 0.45, AP = 0.72, DPS = 14,
			HIT = 14, CRIT = 22, EXPERTISE = 14, HASTE = 11, ARP = 0.25, ARMOR = 0.02 },
		-- Restoration
		{ HEAL = 1, SP = 0.85, INT = 0.7, SPI = 0.6, MP5 = 0.5, SCRIT = 5, SHASTE = 3.5, STA = 0.3, ARMOR = 0.005 },
	},
}
-- Before spending points, use an entry suitable for leveling.
local DEFAULT_SPEC = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 1 }
local FERAL_TREE, BEAR_PROFILE = 2, 4

-- Maps the keys of C_Item.GetItemStats to the short names above.
local STAT_PATTERNS = {
	{ "RESISTANCE0", "ARMOR" }, { "DAMAGE_PER_SECOND", "DPS" },
	{ "STRENGTH", "STR" }, { "AGILITY", "AGI" }, { "STAMINA", "STA" }, { "INTELLECT", "INT" }, { "SPIRIT", "SPI" },
	{ "HEALING", "HEAL" }, { "SPELL_POWER", "SP" }, { "SPELL_DAMAGE", "SD" },
	{ "HOLY_DAMAGE_DONE", "HOLY" }, { "FIRE_DAMAGE_DONE", "FIRE" }, { "NATURE_DAMAGE_DONE", "NATURE" },
	{ "FROST_DAMAGE_DONE", "FROST" }, { "SHADOW_DAMAGE_DONE", "SHADOW" }, { "ARCANE_DAMAGE_DONE", "ARCANE" },
	{ "EXTRA_ARMOR", "ARMOR" },
	{ "HIT_SPELL", "SHIT" }, { "CRIT_SPELL", "SCRIT" }, { "HIT", "HIT" }, { "CRIT", "CRIT" },
	{ "EXPERTISE", "EXPERTISE" }, { "HASTE_SPELL", "SHASTE" }, { "SPELL_HASTE", "SHASTE" }, { "HASTE", "HASTE" },
	{ "ARMOR_PENETRATION", "ARP" }, { "ARMORPENETRATION", "ARP" },
	{ "MANA_REGENERATION", "MP5" }, { "POWER_REGEN0", "MP5" },
	{ "DEFENSE", "DEF" }, { "DODGE", "DODGE" }, { "PARRY", "PARRY" }, { "BLOCK_VALUE", "BVAL" }, { "BLOCK", "BLOCK" },
}
-- Specific creature bonuses must never fall through to unconditional attack power.
local ATTACK_POWER_KEYS = {
	ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_ATTACK_POWER = "AP",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP", ITEM_MOD_RANGED_ATTACK_POWER = "RAP",
}
local statNames = {} -- GetItemStats key -> short name (false = unweighted)

local function StatName(key)
	local name = statNames[key]
	if name == nil then
		name = ATTACK_POWER_KEYS[key] or false
		if not name then
			for _, entry in ipairs(STAT_PATTERNS) do
				if key:find(entry[1], 1, true) then
					name = entry[2]
					break
				end
			end
		end
		statNames[key] = name
	end
	return name
end

-- Camelot combat rating indices and the Forever rating cost of one percentage point.
local RATING_STATS = {
	DODGE = { 3, 12 }, PARRY = { 4, 15 }, BLOCK = { 5, 5 },
	HIT = { 6, 10 }, SHIT = { 8, 10 }, CRIT = { 9, 14 }, SCRIT = { 11, 14 },
	HASTE = { 18, 10 }, SHASTE = { 20, 10 }, EXPERTISE = { 24, 10 },
}
local SHARED_WEIGHT = { HIT = "SHIT", CRIT = "SCRIT", HASTE = "SHASTE", SP = "HEAL" }

function ns.SharedStatWeight(weights, name)
	local other = SHARED_WEIGHT[name]
	return math.max(weights[name] or 0, other and weights[other] or 0)
end

local function RatingPercent(rating, value)
	if value ~= 0 and type(GetCombatRatingBonusForCombatRatingValue) == "function" then
		local ok, percent = pcall(GetCombatRatingBonusForCombatRatingValue, rating[1], math.abs(value))
		percent = ok and ns.Number(percent, 0) or 0
		if percent > 0 then
			return value > 0 and percent or -percent
		end
	end
	return value / rating[2]
end

local weights -- of the current class/specialization, cleared on spec change
local weightsName, weightsTree, weightsPreset
local _, playerClass = UnitClass("player")

-- The client exposes the classic talent trees as groups ordered left to right.
function ns.TalentGroups(configID)
	if type(C_Traits.GetConfigInfo) ~= "function" or type(C_Traits.GetGroupDisplayInfoByTreeID) ~= "function" then
		return {}
	end
	local configInfo = configID and C_Traits.GetConfigInfo(configID)
	local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
	local trees = {}
	for _, info in ipairs(treeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		trees[#trees + 1] = info
	end
	table.sort(trees, function(a, b)
		return a.orderIndex < b.orderIndex
	end)
	return trees
end

-- Forever has one specialization per class. The tree with the most points wins.
local function TalentTree(configID)
	configID = configID or (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID())
	local trees = ns.TalentGroups(configID)
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

-- Name and icon of the tree with the most points: one's own (configID nil) or of an inspected player
-- (Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID after INSPECT_READY). Also returns the tree index.
-- nil when unknown or no point is spent.
function ns.TalentTreeOf(configID)
	local ok, index, name, trees = pcall(TalentTree, configID)
	if not ok or not index or ns.Secret(name) then
		return nil
	end
	local icon = trees and trees[index] and trees[index].icon
	return name, not ns.Secret(icon) and icon or nil, index
end

-- The tree chosen in the options when this class has it, else the automatic one.
function Items.PickTree(choice, auto, count)
	if type(choice) == "number" and choice >= 1 and choice <= count and choice % 1 == 0 then
		return choice
	end
	return auto
end

local function ScoreTreeName(index, trees)
	local tree = trees and trees[index]
	local displayName = tree and tree.displayName
	if type(displayName) == "string" and not ns.Secret(displayName) and displayName ~= "" then
		return displayName
	end
	local presets = ns.TalentPresets and ns.TalentPresets[playerClass]
	local preset = presets and presets[index]
	return preset and (GetLocale() == "deDE" and preset.de or preset.en) or L.ITEMS_SCORE_SPEC_TREE:format(index)
end

-- Choices for the rating: automatic, then the talent trees of the class (names from the talent data when known).
local function ScoreSpecValues()
	local values = { { 0, L.ITEMS_SCORE_SPEC_AUTO } }
	local classWeights = WEIGHTS[playerClass]
	if classWeights then
		local _, _, trees = TalentTree()
		for index = 1, #classWeights do
			values[#values + 1] = { index, ScoreTreeName(index, trees) }
		end
	end
	if playerClass == "DRUID" then
		values[#values + 1] = { BEAR_PROFILE, L.ITEMS_SCORE_SPEC_BEAR }
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
		return weights, weightsName, weightsTree, weightsPreset
	end
	local classWeights = WEIGHTS[playerClass] or WEIGHTS.WARRIOR
	local index, _, trees = TalentTree()
	local profile = Items.PickTree(Items.cdb and Items.cdb.scoreSpec, index or DEFAULT_SPEC[playerClass] or 1,
		playerClass == "DRUID" and BEAR_PROFILE or #classWeights)
	weightsPreset = profile
	if profile == BEAR_PROFILE then
		weights, weightsName, weightsTree = FERAL_BEAR, L.ITEMS_SCORE_SPEC_BEAR, FERAL_TREE
		return weights, weightsName, weightsTree, weightsPreset
	end
	weightsName, weightsTree = ScoreTreeName(profile, trees), profile
	classWeights = classWeights[profile]
	if LEVELLING_MELEE[playerClass] and not classWeights.DPS then
		local level = UnitLevel("player")
		local share = math.min(1, math.max(0, (LEVELLING_NONE - level) / (LEVELLING_NONE - LEVELLING_FULL)))
		if share > 0 then
			classWeights = CopyTable(classWeights)
			classWeights.DPS = WEIGHTS.WARRIOR[1].DPS * share
		end
	end
	weights = classWeights
	return weights, weightsName, weightsTree, weightsPreset
end
ns.StatWeights = GetWeights -- for the ranking of the attributes in the character window

-- Weighted value of an item; weapon DPS counts per slot (melee/ranged).
-- Weapon DPS from the tooltip line, for clients whose item stats lack it.
local DPS_PATTERN = type(DPS_TEMPLATE) == "string" and "^" .. DPS_TEMPLATE:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%%%%.1f", "([%%d%%.,]+)") .. "$"

local equipPattern = ns.FormatToPattern(L.ITEMS_EQUIP_EFFECT, true).pattern
local attackPowerPattern = ns.FormatToPattern(L.ITEMS_EFFECT_AP, true).pattern
local attackPowerLongPattern = ns.FormatToPattern(L.ITEMS_EFFECT_AP_LONG, true).pattern
local humanoidPowerPattern = ns.FormatToPattern(L.ITEMS_EFFECT_AP_HUMANOID, true).pattern
local equipLineType = Enum.TooltipDataLineType.ItemSpellTriggerOnEquip
-- "Chance on hit" effects count at the weapon's procs per minute from Data/ProcRates.lua (WoWSims
-- Forever), otherwise at the median of the rates measured on Forever.
-- 14 attack power add 1 damage per second, so a point of extra damage per second is worth 14 AP.
local PROC = { apPerDPS = 14 }

-- Procs per minute of the item and the kind of source (0 = default, see Data/ProcRates.lua).
function PROC.Rate(link)
	local entry = ns.ProcRates and ns.ProcRates[C_Item.GetItemInfoInstant(link)]
	if entry then
		return entry[1], entry[2]
	end
	return ns.ProcRateDefault or 1, 0
end
local TooltipStats
do
	local procPattern = ns.FormatToPattern(L.ITEMS_PROC_EFFECT, true).pattern
	local procLineType = Enum.TooltipDataLineType.ItemSpellTriggerOnProc
	-- Instant attacks that add the weapon's own hit: a slower weapon of the same DPS hits harder.
	-- Uses per minute are rotation estimates; `swing` attacks also scale attack power with the weapon
	-- speed, the others use the normalized speed (WoWSims Forever). Only spells the player knows count.
	local BACKSTAB = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 }
	local OVERPOWER = { 7384, 7887, 11584, 11585, perMinute = 1 }
	local AIMED_SHOT = { 19434, 20900, 20901, 20902, 20903, 20904, perMinute = 6, ranged = true }
	local MULTI_SHOT = { 2643, perMinute = 6, ranged = true }
	local HUNTER = { AIMED_SHOT, MULTI_SHOT }
	local ABILITIES = {
		WARRIOR = {
			{ { 12294, 21551, 21552, 21553, perMinute = 10 }, { 1680, perMinute = 6 },
				{ 1240193, 1464, 8820, 11604, 11605, perMinute = 4, swing = true }, OVERPOWER },
			{ { 1680, perMinute = 6 }, OVERPOWER },
		},
		-- Stormstrike's hit also brings the main hand's Windfury or Flametongue (DPS simulator values).
		SHAMAN = { nil, { { 17364, perMinute = 3, imbue = true } } },
		-- Seal of Command: 7 procs per minute, each 70% of a weapon swing.
		PALADIN = { nil, nil, { { 20375, 20915, 20918, 20919, 20920, perMinute = 4.9, swing = true } } },
		ROGUE = {
			{ { 399956, 1241582, 1241584, unpack(BACKSTAB) } },
			{ { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 } },
			{ { 16511, unpack(BACKSTAB) } },
		},
		HUNTER = { HUNTER, HUNTER, HUNTER },
	}
	-- Instant Poison per enchant: Forever's average base damage (SpellEffect, build 1.60.1.70938) at a 20%
	-- chance per hit, plus 1% of attack power (WoWSims, measured in game). More hits from a faster weapon
	-- mean more poison; Deadly Poison only keeps its stacks up, whatever the speed.
	local INSTANT_POISON = { [323] = 15, [324] = 23, [325] = 33, [623] = 51, [624] = 71, [625] = 88 }
	local POISON_CHANCE, POISON_AP = 0.2, 0.01
	-- Weapon skill names on items and the weapon subclasses they raise (checked: Edgemaster's Handguards,
	-- Aged Core Leather Gloves). Each point lowers miss and dodge by 0.1% each (Classic and Forever).
	local SKILL_SUBCLASS = { [L.ITEMS_SKILL_AXES:lower()] = 0, [L.ITEMS_SKILL_SWORDS:lower()] = 7,
		[L.ITEMS_SKILL_DAGGERS:lower()] = 15 }
	local SKILL_HIT = 0.2
	for _, trees in pairs(ABILITIES) do
		for _, tree in pairs(trees) do
			for _, ability in ipairs(tree) do
				ability.perMinute = ability.perMinute or 10
			end
		end
	end

	-- Average damage of a "Chance on hit" effect text ("… 155 to 197 Fire damage"), 0 without damage.
	function Items.ProcDamage(effect)
		local text = effect:lower()
		local low, high = text:match(L.ITEMS_PROC_DAMAGE_RANGE)
		if low then
			return (tonumber(low) + tonumber(high)) / 2
		end
		return tonumber(text:match(L.ITEMS_PROC_DAMAGE)) or 0
	end

	-- Extra attacks granted by an effect text ("Grants 2 extra attacks"), 0 without.
	function Items.ExtraAttacks(effect)
		local count = effect:lower():match(L.ITEMS_EXTRA_ATTACK)
		return count and (tonumber(count) or 1) or 0
	end

	-- Attack speed increase in percent and its duration in seconds, nil without.
	function Items.ProcHaste(effect)
		local text = effect:lower()
		local percent = tonumber(text:match(L.ITEMS_PROC_HASTE))
		local duration = tonumber(text:match(L.ITEMS_PROC_DURATION))
		if percent and duration then
			return percent, duration
		end
	end

	local function Readable(value)
		return type(value) == "number" and not ns.Secret(value) and value or 0
	end

	local function AttackPower(ranged)
		local base, plus, minus = (ranged and UnitRangedAttackPower or UnitAttackPower)("player")
		return math.max(0, Readable(base) + Readable(plus) + Readable(minus))
	end

	-- Temporary enchant (imbue, poison) on a hand, 0 without or while unreadable.
	local function HandEnchant(slot)
		local list = Enum.WeaponSlot and C_Item.GetWeaponEnchantInfo and C_Item.GetWeaponEnchantInfo(slot)
		if type(list) ~= "table" or ns.Secret(list) then
			return 0
		end
		for _, enchant in pairs(list) do
			if not ns.Secret(enchant) and type(enchant) == "table" and not ns.Secret(enchant.hasEnchant)
				and enchant.hasEnchant and not ns.Secret(enchant.enchantID) then
				return tonumber(enchant.enchantID) or 0
			end
		end
		return 0
	end

	-- Both hands' temporary enchants, part of the rating's cache key.
	function PROC.Enchants()
		if not Enum.WeaponSlot then
			return 0, 0
		end
		return HandEnchant(Enum.WeaponSlot.MainHand), HandEnchant(Enum.WeaponSlot.OffHand)
	end

	-- Weapon subclass held in a hand, nil without a weapon.
	local function HandSubclass(slot)
		local link = GetInventoryItemLink("player", slot)
		return link and not ns.Secret(link) and select(7, C_Item.GetItemInfoInstant(link)) or nil
	end

	-- Weapon skill bonus of an Equip line ("Daggers +5") counted for the weapons in hand, 0 otherwise.
	function Items.WeaponSkill(effect)
		local name, points = effect:lower():match(L.ITEMS_SKILL)
		local subclass = name and SKILL_SUBCLASS[name]
		if subclass and (HandSubclass(INVSLOT_MAINHAND) == subclass or HandSubclass(INVSLOT_OFFHAND) == subclass) then
			return tonumber(points)
		end
		return 0
	end

	local function MainHandDPS()
		local link = GetInventoryItemLink("player", INVSLOT_MAINHAND)
		local stats = link and not ns.Secret(link) and C_Item.GetItemStats(link)
		return stats and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0
	end

	-- Normalized speed of the weapon type, the reference for the weapon speed rating.
	local function NormalSpeed(link, ranged)
		local _, _, _, equipLoc, _, _, subClassID = C_Item.GetItemInfoInstant(link)
		if ranged then
			return 2.8
		elseif equipLoc == "INVTYPE_2HWEAPON" then
			return 3.3
		elseif subClassID == Enum.ItemWeaponSubclass.Dagger then
			return 1.7
		end
		return 2.4
	end

	local function Known(ability)
		for _, spellID in ipairs(ability) do
			if IsPlayerSpell(spellID) then
				return true
			end
		end
	end

	-- Extra damage per second of weapon speed through the known instant attacks, compared with the
	-- weapon type's normalized speed.
	local function SpeedDPS(link, info, tree, ranged, offhand, ap)
		local normal = NormalSpeed(link, ranged)
		local speedGain = info.speed - normal
		local abilities = ABILITIES[playerClass]
		local mainEnchant, offEnchant = PROC.Enchants()
		local dps = 0
		for _, ability in ipairs(not offhand and abilities and abilities[tree] or {}) do
			if (not ability.ranged) == (not ranged) and Known(ability) then
				local hit = info.dps + (ability.swing and ap / PROC.apPerDPS or 0)
				dps = dps + ability.perMinute / 60 * hit * speedGain
				local imbued = ability.imbue and ns.ImbueHitDamage
					and ns.ImbueHitDamage(mainEnchant, info.speed, info.dps, ap)
				if imbued then
					dps = dps + ability.perMinute / 60 * (imbued - ns.ImbueHitDamage(mainEnchant, normal, info.dps, ap))
				end
			end
		end
		local poison = INSTANT_POISON[offhand and offEnchant or mainEnchant]
		if poison and not ranged then
			dps = dps + POISON_CHANCE * (poison + POISON_AP * ap) * (1 / info.speed - 1 / normal)
		end
		return dps
	end

	-- Rating of the effects the item stats leave out: "Chance on hit" damage, extra attacks and attack
	-- speed, the Equip chance of an extra attack, and the weapon speed. Returns proc and speed points.
	function PROC.WeaponExtras(link, info, w, tree, ranged, offhand)
		local apWeight = w[ranged and "RAP" or "AP"] or 0
		if apWeight <= 0 then
			return 0, 0
		end
		local ap = AttackPower(ranged)
		local perMinute = PROC.Rate(link)
		local perSecond = perMinute / 60
		local dps = info.procDamage * perSecond
		if info.speed and info.dps then
			dps = dps + perSecond * info.extraAttacks * (info.dps + ap / PROC.apPerDPS) * info.speed
		end
		if info.equipExtraChance > 0 then
			dps = dps + info.equipExtraChance / 100 * info.equipExtraAttacks * (MainHandDPS() + ap / PROC.apPerDPS)
		end
		local procPoints = apWeight * PROC.apPerDPS * dps
		if info.haste > 0 and not ranged then
			procPoints = procPoints + (w.HASTE or 0) * info.haste * math.min(1, perMinute * info.hasteDuration / 60)
		end
		local speedPoints = 0
		if info.speed and info.dps then
			speedPoints = apWeight * PROC.apPerDPS * SpeedDPS(link, info, tree, ranged, offhand, ap)
		end
		if info.weaponSkill > 0 and not ranged then
			procPoints = procPoints + (w.HIT or 0) * SKILL_HIT * info.weaponSkill
		end
		return procPoints, speedPoints
	end

	function TooltipStats(link, readDPS, readAP, readProc)
		local data = type(C_TooltipInfo.GetHyperlink) == "function" and C_TooltipInfo.GetHyperlink(link)
		local info = { ap = 0, humanoidAP = 0, procDamage = 0, extraAttacks = 0, haste = 0, hasteDuration = 0,
			equipExtraChance = 0, equipExtraAttacks = 0, weaponSkill = 0, creatureAP = {} }
		for _, line in ipairs(data and data.lines or {}) do
			local value = line.leftText
			if not ns.Secret(value) and type(value) == "string" then
				if readDPS and not info.dps then
					local number = value:match(DPS_PATTERN)
					info.dps = number and tonumber((number:gsub(",", ".")))
				end
				local right = line.rightText
				if readProc and not info.speed and type(right) == "string" and not ns.Secret(right) then
					local number = right:match("(%d+[%.,]%d%d)$")
					info.speed = number and tonumber((number:gsub(",", ".")))
				end
				if readAP or readProc then
					local plain = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+$", "")
					local effect = readAP and (plain:match(equipPattern) or (equipLineType and line.type == equipLineType and plain))
					if effect then
						effect = effect:gsub("%.?%s*$", "")
						info.ap = info.ap + (tonumber(effect:match(attackPowerPattern) or effect:match(attackPowerLongPattern)) or 0)
						info.humanoidAP = info.humanoidAP + (tonumber(effect:match(humanoidPowerPattern)) or 0)
						info.weaponSkill = info.weaponSkill + Items.WeaponSkill(effect)
						local creatureAP, creatures = effect:match(L.ITEMS_EFFECT_AP_CREATURE)
						if creatureAP and not effect:match(humanoidPowerPattern) then
							info.creatureAP[#info.creatureAP + 1] = { tonumber(creatureAP), creatures }
						end
						local extra = Items.ExtraAttacks(effect)
						local chance = tonumber(effect:match("(%d+)%%"))
						if extra > 0 and chance then
							info.equipExtraChance, info.equipExtraAttacks = chance, extra
						end
					end
					local proc = readProc and (plain:match(procPattern) or (procLineType and line.type == procLineType and plain))
					if proc then
						info.procDamage = info.procDamage + Items.ProcDamage(proc)
						info.extraAttacks = info.extraAttacks + Items.ExtraAttacks(proc)
						local haste, duration = Items.ProcHaste(proc)
						if haste then
							info.haste, info.hasteDuration = haste, duration
						end
					end
				end
			end
		end
		return info
	end
end

local function Score(link, ranged, offhand)
	local mainEnchant, offEnchant = PROC.Enchants()
	local cacheKey = link .. (ranged and "#r" or "") .. (offhand and "#o" or "") .. "#" .. mainEnchant .. ":" .. offEnchant
	local cached = scoreCache[cacheKey]
	if cached then
		return cached[1], cached[2], cached[3], cached[4], cached[5]
	end
	local w, _, tree = GetWeights()
	local score, humanoidBonus, hasDPS, hasAP, weaponDPS = 0, 0, false, false, nil
	for key, value in pairs(C_Item.GetItemStats(link) or {}) do
		local name = StatName(key)
		if name == "DPS" then
			hasDPS, weaponDPS = true, value
			if ranged then
				name = "RDPS"
			end
		elseif name == "AP" and value ~= 0 then
			hasAP = true
		end
		local weight = name and w[name]
		if name == "SD" then
			weight = w.SP
		elseif SHARED_WEIGHT[name] and not key:find("_MELEE", 1, true) and not key:find("_RANGED", 1, true) then
			-- Weigh a shared gear bonus once, using the stronger contribution.
			weight = ns.SharedStatWeight(w, name)
		end
		if weight and weight > 0 then
			local rating = RATING_STATS[name]
			if rating and key:find("_RATING", 1, true) then
				value = RatingPercent(rating, value)
			end
			score = score + weight * value
		end
	end
	local dpsWeight = w[ranged and "RDPS" or "DPS"]
	local readDPS = not hasDPS and DPS_PATTERN and dpsWeight
		and select(6, C_Item.GetItemInfoInstant(link)) == Enum.ItemClass.Weapon
	local readAP = w.AP and w.AP > 0
	local procWeight = w[ranged and "RAP" or "AP"]
	local readProc = procWeight and procWeight > 0
	local procPoints, speedPoints, creatures = 0, 0, nil
	if readDPS or readAP or readProc then
		local info = TooltipStats(link, readDPS, readAP, readProc)
		if info.dps then
			score = score + dpsWeight * info.dps
		end
		info.dps = weaponDPS or info.dps
		if readAP then
			if not hasAP then
				score = score + w.AP * info.ap
			end
			humanoidBonus = w.AP * info.humanoidAP
			creatures = info.creatureAP
		end
		if readProc then
			procPoints, speedPoints = PROC.WeaponExtras(link, info, w, tree, ranged, offhand)
			score = score + procPoints + speedPoints
		end
	end
	scoreCache[cacheKey] = { score, humanoidBonus, procPoints, speedPoints, creatures }
	return score, humanoidBonus, procPoints, speedPoints, creatures
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
		return cached[1], cached[2]
	end
	local link = EquippedLink(invSlot)
	if link == false then
		return false
	end
	local value, bonus = 0, 0
	if link then
		value, bonus = Score(link, invSlot == INVSLOT_RANGED, invSlot == INVSLOT_OFFHAND)
	end
	equippedCache[invSlot] = { value, bonus }
	return value, bonus
end

-- Everything that depends on what is worn or on the stat weights.
local function ClearWeighCaches()
	wipe(upgradeCache)
	wipe(linkUpgradeCache)
	wipe(scoreCache)
	wipe(equippedCache)
end

local function IsTwoHand(link)
	return link and select(4, C_Item.GetItemInfoInstant(link)) == "INVTYPE_2HWEAPON"
end

-- Returns the weighted value of the item and of the weakest equipped item it
-- could replace, with a second comparison against Humanoids when different.
-- False if it is unsuitable for comparison, nil while loading.
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

	local ranged = slots[1] == INVSLOT_RANGED
	local score, bonus, equippedScore, equippedHumanoidScore, humanoidScore
	if equipLoc == "INVTYPE_2HWEAPON" then
		-- Replaces main and off hand together.
		local mainScore, mainBonus = EquippedScore(INVSLOT_MAINHAND)
		local offScore, offBonus = EquippedScore(INVSLOT_OFFHAND)
		if mainScore == false or offScore == false then
			return nil
		end
		equippedScore = mainScore + offScore
		equippedHumanoidScore = equippedScore + mainBonus + offBonus
		score, bonus = Score(link, ranged)
		humanoidScore = score + bonus
	elseif slots[1] == INVSLOT_OFFHAND and IsTwoHand(EquippedLink(INVSLOT_MAINHAND)) then
		-- No off hand next to a two-hand weapon.
		return false
	else
		-- The slot with the largest gain; an off-hand weapon has no weapon speed rating.
		for _, invSlot in ipairs(slots) do
			local value, equippedBonus = EquippedScore(invSlot)
			if value == false then
				return nil
			end
			local own, ownBonus = Score(link, ranged, invSlot == INVSLOT_OFFHAND)
			if not score or own - value > score - equippedScore then
				score, bonus, equippedScore = own, ownBonus, value
			end
			local humanoidValue = value + equippedBonus
			if not humanoidScore or own + ownBonus - humanoidValue > humanoidScore - equippedHumanoidScore then
				humanoidScore, equippedHumanoidScore = own + ownBonus, humanoidValue
			end
		end
	end
	if bonus ~= 0 or equippedScore ~= equippedHumanoidScore or humanoidScore ~= score + bonus then
		return score, equippedScore, humanoidScore, equippedHumanoidScore
	end
	return score, equippedScore
end

-- Arrow states: true for an upgrade, "later" for a level-gated upgrade, "worse"
-- for an equippable downgrade, false for a tie or unsuitable gear.
local function ScoreDirection(score, equippedScore)
	if score then
		local gain = score - equippedScore
		if gain > 0.01 then
			return true
		elseif gain < -0.01 then
			return "worse"
		end
	end
	return false
end

local function UsableArrowState(direction, block)
	if block == "ok" then
		return direction
	end
	return direction == true and block == "level" and "later" or false
end

local WEIGH_BUDGET = 0.6 -- ms per bag update: the rest of the new items is weighed a moment later
local weighStart, weighDone, weighDeferred, weighActive = 0, 0, false, false

local function BagComparisonState(bag, slot, link)
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
	local result = ScoreDirection(score, equippedScore)
	if result then
		result = UsableArrowState(result, BagUseBlock(bag, slot))
	end
	upgradeCache[link] = result
	return result
end

-- As in the bags, using the linked item tooltip. Nil while data is loading.
local function LinkComparisonState(link)
	if type(link) ~= "string" or ns.Secret(link)
		or not C_Item.IsEquippableItem(link) then
		return false
	end
	local cached = linkUpgradeCache[link]
	if cached ~= nil then
		return cached
	end
	local score, equippedScore = CompareScores(link)
	if score == nil then
		return nil
	end
	local result = ScoreDirection(score, equippedScore)
	if result then
		local data = C_TooltipInfo.GetHyperlink(link)
		if not data or not data.lines then
			return nil
		end
		result = UsableArrowState(result, Items.UseBlock(data.lines, LevelPattern()))
	end
	linkUpgradeCache[link] = result
	return result
end

local function LinkUpgradeState(link)
	return Items.db and Items.db.upgradeArrow and LinkComparisonState(link)
end

ns.ItemLinkUpgradeState = LinkUpgradeState

-- How much an item (a link) adds over what it would replace, by the same rating as the arrows; nil if unknown.
function ns.ItemUpgradeGain(link)
	if type(link) ~= "string" or ns.Secret(link) then return end
	local score, equippedScore = CompareScores(link)
	if score and equippedScore then return score - equippedScore end
end
ns.RecipeUpgradeState = LinkUpgradeState

-- For lists sorted by rating (auction house): the weighted value an item adds over the weakest worn item it would
-- replace (negative if worse) and, for a gain, whether it can be worn ("ok", "level", "no"). False for items that are
-- never compared (no equipment, another armor type), nil while data loads. Independent of the arrow option.
function ns.ItemLinkRating(link)
	if not Items.db or type(link) ~= "string" or ns.Secret(link) or not C_Item.IsEquippableItem(link) then
		return false
	end
	local score, equippedScore = CompareScores(link)
	if not score then
		return score
	end
	local gain = score - equippedScore
	if gain <= 0.01 then
		return gain
	end
	local data = C_TooltipInfo.GetHyperlink(link)
	return gain, Items.UseBlock(data and data.lines, LevelPattern())
end

-- Comparison tooltips: the hovered item (a link) against the worn items shown beside it (`worn`, links).
-- Returns "hovered" and its upgrade state (true or "later"), or "worn" and the position of the best worn
-- item in `worn`; nil if neither is clearly better or the data is missing. Same rule as the bag arrows.
function ns.CompareWinner(link, worn)
	if not Items.db or not Items.db.upgradeArrow or type(link) ~= "string" or ns.Secret(link)
		or not C_Item.IsEquippableItem(link) then
		return nil
	end
	local score, equippedScore = CompareScores(link)
	if not score then
		return nil
	end
	if score > equippedScore + 0.01 then
		local state = LinkUpgradeState(link)
		if state then
			return "hovered", state
		end
		return nil
	end
	if equippedScore > score + 0.01 then
		local slots = ns.EquipSlots(select(4, C_Item.GetItemInfoInstant(link)))
		local ranged = slots and slots[1] == INVSLOT_RANGED
		local best, bestScore
		for index, wornLink in ipairs(worn) do
			if type(wornLink) == "string" and not ns.Secret(wornLink) then
				local value = Score(wornLink, ranged)
				if not bestScore or value > bestScore then
					best, bestScore = index, value
				end
			end
		end
		if best then
			return "worn", best
		end
	end
	return nil
end

local function AddRatingLines(tooltip, link, score, equippedScore, humanoidScore, equippedHumanoidScore)
	local _, treeName = GetWeights()
	tooltip:AddLine(L.ITEMS_SCORE_LINE:format(score, equippedScore, ("%+.1f"):format(score - equippedScore),
		treeName or L.ITEMS_SCORE_DEFAULT), 0.5, 0.7, 1)
	if humanoidScore then
		tooltip:AddLine(L.ITEMS_SCORE_HUMANOID_LINE:format(humanoidScore, equippedHumanoidScore), 0.5, 0.7, 1)
	end
	local slots = ns.EquipSlots(select(4, C_Item.GetItemInfoInstant(link)))
	local _, _, procPoints, speedPoints, creatures = Score(link, slots and slots[1] == INVSLOT_RANGED)
	local apWeight = GetWeights().AP or 0
	for _, bonus in ipairs(creatures or {}) do
		tooltip:AddLine(L.ITEMS_SCORE_CREATURE_LINE:format(bonus[2], score + apWeight * bonus[1]), 0.5, 0.7, 1)
	end
	if procPoints and procPoints ~= 0 then
		local perMinute, kind = PROC.Rate(link)
		tooltip:AddLine(L.ITEMS_SCORE_PROC_LINE:format(procPoints, perMinute, L["ITEMS_PROC_RATE_" .. kind]), 0.5, 0.7, 1)
	end
	if speedPoints and speedPoints ~= 0 then
		tooltip:AddLine(L.ITEMS_SCORE_SPEED_LINE:format(speedPoints), 0.5, 0.7, 1)
	end
end

-- The rating of a recipe's product in another tooltip (trainer, list of recipes), as on items.
function ns.AddRecipeScoreLine(tooltip, link)
	if not (Items.db and Items.db.upgradeScore) or type(link) ~= "string" or ns.Secret(link)
		or not C_Item.IsEquippableItem(link) then
		return
	end
	local score, equippedScore, humanoidScore, equippedHumanoidScore = CompareScores(link)
	if score then
		AddRatingLines(tooltip, link, score, equippedScore, humanoidScore, equippedHumanoidScore)
	end
end

local rewardRetries = {}

-- Rewards and merchant wares have a separate option and only mark currently usable equipment.
function ns.RewardComparisonState(link, onLoaded)
	if not Items.db or not Items.db.rewardUpgrade then
		return false
	end
	local state = LinkComparisonState(link)
	if state == nil then
		local tries = rewardRetries[link] or 0
		if onLoaded and tries < 3 then
			rewardRetries[link] = tries + 1
			ns.After("Items: onLoaded", 1, onLoaded)
		end
	end
	return state ~= "later" and state
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
	local score, equippedScore, humanoidScore, equippedHumanoidScore = CompareScores(link)
	if not score then
		return
	end
	AddRatingLines(tooltip, link, score, equippedScore, humanoidScore, equippedHumanoidScore)
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

-- The window is the game's loot toast (its artwork, item border, glow, sheen and rising arrows) with the gain big
-- between heading and name; the two buttons sit under it.
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

local TOAST_FILE = [[Interface\LootFrame\LootToast]]

local function CreateUpgradeFrame()
	-- The size and artwork of the game's loot toast (276 x 96), a little bigger.
	local frame = CreateFrame("Button", "ForeverPlusUpgradeFrame", UIParent)
	frame:SetSize(276, 96)
	frame:SetScale(1.25)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("RightButtonUp")
	frame:Hide()
	-- Escape closes it like the panel before.
	tinsert(UISpecialFrames, "ForeverPlusUpgradeFrame")

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints()
	frame.Background:SetTexture(TOAST_FILE)
	frame.Background:SetTexCoord(0.28222656, 0.55175781, 0.578125, 0.953125)

	frame.Icon = frame:CreateTexture(nil, "BORDER", nil, 1)
	frame.Icon:SetSize(50, 50)
	frame.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -23)
	frame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.Border = frame:CreateTexture(nil, "BORDER", nil, 2)
	frame.Border:SetPoint("CENTER", frame.Icon, "CENTER")
	frame.Glow = frame:CreateTexture(nil, "BORDER", nil, 4)
	frame.Glow:SetPoint("CENTER", frame.Icon, "CENTER")
	frame.Glow:SetBlendMode("ADD")
	frame.Glow:SetAlpha(0)
	SetAtlasOr(frame.Glow, "loottoast-itemborder-glow")

	-- Pointing at the icon shows the item and the rating comparison.
	local hit = CreateFrame("Frame", nil, frame)
	hit:SetAllPoints(frame.Icon)
	hit:SetScript("OnEnter", function(self)
		local entry = upgradeQueue[1]
		if entry then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(entry.link)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(entry.equippedScore and entry.equippedScore > 0
				and L.ITEMS_UPGRADE_POPUP_SCORE:format(entry.score, entry.equippedScore)
				or L.ITEMS_UPGRADE_POPUP_SCORE_NEW:format(entry.score), 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	hit:SetScript("OnLeave", GameTooltip_Hide)

	-- Like the game's toast: a yellow heading, the item name under it, both centred next to the icon.
	frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 8, 8)
	frame.Title:SetPoint("RIGHT", -18, 0)
	frame.Title:SetJustifyH("CENTER")
	frame.Title:SetWordWrap(false)
	-- The gain sits between heading and name, big and green, and pops up with a little overshoot; it has its own frame
	-- so it can scale.
	frame.GainBox = CreateFrame("Frame", nil, frame)
	frame.GainBox:SetHeight(24)
	frame.GainBox:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -1)
	frame.GainBox:SetPoint("RIGHT", -18, 0)
	frame.Gain = frame.GainBox:CreateFontString(nil, "OVERLAY")
	frame.Gain:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
	frame.Gain:SetPoint("CENTER")
	frame.Gain:SetTextColor(0.3, 1, 0.3)
	frame.Gain:SetShadowColor(0, 0, 0, 0.8)
	frame.Gain:SetShadowOffset(1, -1)
	frame.Name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	frame.Name:SetJustifyH("CENTER")
	frame.Name:SetWordWrap(false)
	-- Like the game's upgrade toast, the name flashes white once.
	frame.NameFlash = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	frame.NameFlash:SetJustifyH("CENTER")
	frame.NameFlash:SetWordWrap(false)
	frame.NameFlash:SetTextColor(1, 1, 1)
	frame.NameFlash:SetAlpha(0)
	frame.Replaces = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.Replaces:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -3)
	frame.Replaces:SetPoint("RIGHT", -18, 0)
	frame.Replaces:SetJustifyH("CENTER")
	frame.Replaces:SetWordWrap(false)
	frame.GainPop = frame.GainBox:CreateAnimationGroup()
	frame.GainPop:SetToFinalAlpha(true)
	local popFade = frame.GainPop:CreateAnimation("Alpha")
	popFade:SetFromAlpha(0)
	popFade:SetToAlpha(1)
	popFade:SetDuration(0.15)
	popFade:SetStartDelay(0.25)
	popFade:SetOrder(1)
	for order, step in ipairs({ { 0.4, 1.3, 0.2 }, { 1.3, 1, 0.14 } }) do
		local from, to, duration = step[1], step[2], step[3]
		local pop = frame.GainPop:CreateAnimation("Scale")
		pop:SetOrigin("CENTER", 0, 0)
		if pop.SetScaleFrom then
			pop:SetScaleFrom(from, from)
			pop:SetScaleTo(to, to)
		else
			pop:SetFromScale(from, from)
			pop:SetToScale(to, to)
		end
		pop:SetDuration(duration)
		pop:SetOrder(order)
		if order == 1 then
			pop:SetStartDelay(0.25)
		end
	end

	-- The game's flash over the toast and the sheen that sweeps across it.
	frame.Flash = frame:CreateTexture(nil, "OVERLAY")
	frame.Flash:SetPoint("CENTER")
	frame.Flash:SetBlendMode("ADD")
	frame.Flash:SetAlpha(0)
	SetAtlasOr(frame.Flash, "loottoast-glow")
	frame.Sheen = frame:CreateTexture(nil, "OVERLAY")
	frame.Sheen:SetPoint("BOTTOMLEFT", -10, 12)
	frame.Sheen:SetBlendMode("ADD")
	frame.Sheen:SetAlpha(0)
	SetAtlasOr(frame.Sheen, "loottoast-sheen", function()
		frame.Sheen:SetSize(171, 75)
		frame.Sheen:SetTexture(TOAST_FILE)
		frame.Sheen:SetTexCoord(0.56347656, 0.73046875, 0.57421875, 0.86718750)
	end)
	-- Sparkles in the quality colour: small stars that twinkle one after another at random places on the toast.
	frame.Sparkles = {}
	for index = 1, 10 do
		local star = frame:CreateTexture(nil, "OVERLAY", nil, 2)
		star:SetTexture([[Interface\Cooldown\star4]])
		star:SetBlendMode("ADD")
		star:SetSize(14 + (index % 3) * 6, 14 + (index % 3) * 6)
		star:SetAlpha(0)
		frame.Sparkles[index] = star
	end

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
	local nameIn = frame.Celebrate:CreateAnimation("Alpha")
	nameIn:SetTarget(frame.NameFlash)
	nameIn:SetStartDelay(0.2)
	nameIn:SetSmoothing("IN")
	nameIn:SetFromAlpha(0)
	nameIn:SetToAlpha(0.9)
	nameIn:SetDuration(0.5)
	local nameOut = frame.Celebrate:CreateAnimation("Alpha")
	nameOut:SetTarget(frame.NameFlash)
	nameOut:SetStartDelay(0.7)
	nameOut:SetFromAlpha(0.9)
	nameOut:SetToAlpha(0)
	nameOut:SetDuration(0.7)
	for index, star in ipairs(frame.Sparkles) do
		local delay = 0.3 + (index - 1) * 0.13
		local show = frame.Celebrate:CreateAnimation("Alpha")
		show:SetTarget(star)
		show:SetStartDelay(delay)
		show:SetFromAlpha(0)
		show:SetToAlpha(1)
		show:SetDuration(0.15)
		local hide = frame.Celebrate:CreateAnimation("Alpha")
		hide:SetTarget(star)
		hide:SetStartDelay(delay + 0.15)
		hide:SetFromAlpha(1)
		hide:SetToAlpha(0)
		hide:SetDuration(0.35)
		local turn = frame.Celebrate:CreateAnimation("Rotation")
		turn:SetTarget(star)
		turn:SetStartDelay(delay)
		turn:SetDegrees(-70)
		turn:SetDuration(0.5)
	end
	local flashIn = frame.Celebrate:CreateAnimation("Alpha")
	flashIn:SetTarget(frame.Flash)
	flashIn:SetFromAlpha(0)
	flashIn:SetToAlpha(1)
	flashIn:SetDuration(0.2)
	local flashOut = frame.Celebrate:CreateAnimation("Alpha")
	flashOut:SetTarget(frame.Flash)
	flashOut:SetFromAlpha(1)
	flashOut:SetToAlpha(0)
	flashOut:SetStartDelay(0.2)
	flashOut:SetDuration(0.5)
	local sheenIn = frame.Celebrate:CreateAnimation("Alpha")
	sheenIn:SetTarget(frame.Sheen)
	sheenIn:SetStartDelay(0.1)
	sheenIn:SetFromAlpha(0)
	sheenIn:SetToAlpha(1)
	sheenIn:SetDuration(0.1)
	local sheenMove = frame.Celebrate:CreateAnimation("Translation")
	sheenMove:SetTarget(frame.Sheen)
	sheenMove:SetStartDelay(0.1)
	sheenMove:SetOffset(165, 0)
	sheenMove:SetDuration(0.5)
	local sheenOut = frame.Celebrate:CreateAnimation("Alpha")
	sheenOut:SetTarget(frame.Sheen)
	sheenOut:SetStartDelay(0.3)
	sheenOut:SetFromAlpha(1)
	sheenOut:SetToAlpha(0)
	sheenOut:SetDuration(0.25)
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
	equip:SetSize(132, 24)
	equip:SetPoint("TOPLEFT", frame, "BOTTOM", 3, 2)
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
	later:SetSize(132, 24)
	later:SetPoint("TOPRIGHT", frame, "BOTTOM", -3, 2)
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
	frame.Title:SetText(L.ITEMS_UPGRADE_POPUP_HEAD)
	frame.Gain:SetText(gain and L.ITEMS_UPGRADE_POPUP_GAIN:format(gain) or "")
	frame.GainBox:SetShown(gain ~= nil)
	frame.Name:ClearAllPoints()
	frame.Name:SetPoint("TOPLEFT", gain and frame.GainBox or frame.Title, "BOTTOMLEFT", 0, gain and 0 or -6)
	frame.Name:SetPoint("RIGHT", -18, 0)
	frame.NameFlash:SetText(itemName or entry.link)
	frame.NameFlash:ClearAllPoints()
	frame.NameFlash:SetPoint("TOPLEFT", frame.Name, "TOPLEFT")
	frame.NameFlash:SetPoint("TOPRIGHT", frame.Name, "TOPRIGHT")
	-- The sparkle, glow and sheen take the quality colour (green for grey and white items).
	local tr, tg, tb = 0.3, 1, 0.3
	if color and quality >= 2 then
		tr, tg, tb = color.r, color.g, color.b
	end
	frame.Glow:SetVertexColor(tr, tg, tb)
	frame.Flash:SetVertexColor(tr, tg, tb)
	frame.Sheen:SetVertexColor(0.5 + tr / 2, 0.5 + tg / 2, 0.5 + tb / 2)
	for _, star in ipairs(frame.Sparkles) do
		star:SetVertexColor(0.4 + tr * 0.6, 0.4 + tg * 0.6, 0.4 + tb * 0.6)
		star:ClearAllPoints()
		star:SetPoint("CENTER", frame, "TOPLEFT", math.random(18, 258), -math.random(14, 82))
	end
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
	frame.GainPop:Stop()
	frame.GainBox:SetAlpha(1)
	if Items.db.upgradeCelebrate then
		frame.Celebrate:Play()
		frame.GainBox:SetAlpha(0)
		frame.GainPop:Play()
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
-- Bag and loot button decoration
---------------------------------------------------------------------------
local function SetUpgradeArrow(arrow, state)
	if not state then
		if not arrow.IsShown or arrow:IsShown() then
			arrow:SetShown(false)
		end
		return
	end
	if arrow.fpState ~= state then
		arrow.fpState = state
		arrow:SetDesaturated(state == "later")
		arrow:SetAlpha(state == "later" and 0.75 or 1)
	end
	if not arrow.IsShown or not arrow:IsShown() then
		arrow:SetShown(true)
	end
end

-- Rotate and tint the same atlas on addon-owned textures. Recycled rows restore the original
-- color and orientation when they next show an upgrade.
function ns.SetItemComparisonArrow(arrow, state, laterAlpha)
	if state and arrow.fpComparisonState ~= state then
		arrow.fpComparisonState = state
		local worse = state == "worse"
		local accent = worse and 0.12 or 1
		arrow:SetDesaturated(worse or state == "later")
		arrow:SetVertexColor(1, accent, accent)
		arrow:SetRotation(worse and math.pi or 0)
		if laterAlpha then
			arrow:SetAlpha(state == "later" and laterAlpha or 1)
		end
	end
	arrow:SetShown(not not state)
end

local bagDowngradeArrows = setmetatable({}, { __mode = "k" })

local function UpdateButton(button, excludedBags)
	local bag, slot = button:GetBagID(), button:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)

	-- Grey and white items: the action button frame (Visuals, option); the hook on the quality alone does not
	-- reach the bag buttons, this loop does.
	if ns.FrameItemButton then
		ns.FrameItemButton(button, info and info.quality)
	end

	if button.JunkIcon then
		-- Coin on everything that will be sold: grey items (unless kept) and marked items.
		local show = false
		if info and not info.hasNoValue and IsJunkItem(info) then
			local excluded = excludedBags and excludedBags[bag]
			if excluded == nil then
				excluded = BagExcludesJunk(bag) and true or false
				if excludedBags then
					excludedBags[bag] = excluded
				end
			end
			show = not excluded
		end
		if not button.JunkIcon.IsShown or button.JunkIcon:IsShown() ~= show then
			button.JunkIcon:SetShown(show)
		end
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
			show = BagComparisonState(bag, slot, info.hyperlink)
		end
		local worse = show == "worse"
		SetUpgradeArrow(button.UpgradeIcon, not worse and show)
		local arrow = bagDowngradeArrows[button]
		if worse and not arrow then
			arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
			arrow:SetAtlas("bags-greenarrow", true)
			arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT")
			bagDowngradeArrows[button] = arrow
		end
		if arrow then
			ns.SetItemComparisonArrow(arrow, worse and show)
		end
	end
end

local function UpdateContainerFrame(frame)
	if not frame:IsShown() then
		return
	end
	local excludedBags = {}
	weighStart, weighDone, weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		UpdateButton(button, excludedBags)
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

local lootArrows = {}
local lootWaitingForData = false

local function UpdateLootRow(row, data)
	local state = false
	if Items.db.upgradeArrow and row.Item and GetLootSlotType(data.slotIndex) == Enum.LootSlotType.Item then
		local link = GetLootSlotLink(data.slotIndex)
		state = LinkUpgradeState(link)
		if state == nil then
			lootWaitingForData = true
			if not C_Item.IsItemDataCachedByID(link) then
				C_Item.RequestLoadItemDataByID(link)
			end
		end
	end
	local arrow = lootArrows[row]
	if state and not arrow then
		arrow = row.Item:CreateTexture(nil, "OVERLAY", nil, 7)
		arrow:SetAtlas("bags-greenarrow", true)
		arrow:SetPoint("TOPRIGHT", row.Item, "TOPRIGHT")
		lootArrows[row] = arrow
	end
	if arrow then
		ns.SetItemComparisonArrow(arrow, state, 0.75)
	end
end

local function UpdateLootUpgrades()
	lootWaitingForData = false
	if LootFrame and LootFrame.ScrollBox and LootFrame:IsShown() then
		LootFrame.ScrollBox:ForEachFrame(UpdateLootRow)
	end
end

local function OnLootItemData(_, _, _, success)
	if success and lootWaitingForData then
		UpdateLootUpgrades()
	end
end

local function UsesGearScores()
	local db = Items.db
	return db.upgradeArrow or db.upgradePopup or db.upgradeScore or db.rewardUpgrade
end

-- Coalesce bursts of talent and level changes.
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
		local statRank = ns:GetModule("StatRank")
		if statRank and statRank.db.enabled then
			statRank.Refresh()
		end
		if UsesGearScores() then
			UpdateAllBags()
		end
		UpdateLootUpgrades()
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
	{ L.ITEMS_BAGS, { { "Items", "autoSort", "ITEMS_AUTOSORT" }, { "Items", "moneyPickup", "ITEMS_MONEY_PICKUP" },
		{ "BankView", "enabled", "BANKVIEW_ENABLE" } } },
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
	local excludedBags = {}
	weighStart, weighDone, weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnMouseUp", OnItemMouseUp)
		end
		UpdateButton(button, excludedBags)
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
local SORT_MAX = 15 -- seconds after which a sort counts as over whatever the bags show
local lastSort, sortQueued, sorting = 0, false, false
-- Layout of the bags after the last finished sort (items and counts). While it is unchanged, opening the bags sorts
-- nothing.
local sortedLayout, sortedRevision
local bagRevision = 0
local RecordLayout -- below

local function OnBagLayoutChanged(_, _, bag)
	if type(bag) == "number" and bag >= BACKPACK_CONTAINER and bag <= NUM_TOTAL_EQUIPPED_BAG_SLOTS then
		bagRevision = bagRevision + 1
	end
end

local function InvalidateBagLayout()
	bagRevision = bagRevision + 1
end

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

-- Read locks and, when needed, the layout in a single pass over the bags.
local function ReadBagLayout(withSignature, stopWhenLocked)
	local parts = withSignature and {} or nil
	local locked = false
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then
				if stopWhenLocked then
					return nil, true
				end
				locked = true
			end
			if parts then
				parts[#parts + 1] = info and (tostring(info.itemID) .. "x" .. tostring(info.stackCount)) or "-"
			end
		end
	end
	return parts and table.concat(parts, ","), locked
end

-- The game's cleanup works in bursts with pauses (the server moves the items); "no bag update for a moment" took
-- such a pause for the end and the marked items were placed in a half-finished layout, which the rest of the cleanup
-- then undid a few seconds later. A layout counts as settled when it has not changed for SETTLE seconds and no
-- item is locked.
local settle = {}

local function ResetSettle()
	settle.signature, settle.since, settle.revision = nil, GetTime(), nil
end

local function LayoutSettled()
	local now = GetTime()
	-- Bag and lock events invalidate the observation. Recheck once more before accepting a quiet layout.
	if settle.revision == bagRevision and now - (settle.locked and settle.checked or settle.since) < SETTLE then
		return false
	end
	local signature, locked = ReadBagLayout(true)
	settle.revision, settle.locked, settle.checked = bagRevision, locked, now
	if signature ~= settle.signature then
		settle.signature, settle.since = signature, now
	end
	return now - settle.since >= SETTLE and not locked
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
		local settled = LayoutSettled()
		if settled or waited >= SORT_MAX then
			Items.Trace("Sortieren beendet nach %.1f s (%s)", waited, waited >= SORT_MAX and "Zeitgrenze" or "Belegung ruhig")
			sorting = false
			lastSort = GetTime()
			ticker:Cancel()
			RecordLayout(settle.signature)
		end
	end)
end

local function CanSortOnOpen()
	return Items.db.autoSort and not InCombatLockdown() and not sellTicker and not GetCursorInfo() and not sorting and not OtherWindowOpen()
end

local function StartAutomaticSort(revision)
	if revision ~= bagRevision or not CanSortOnOpen() then
		return
	end
	lastSort = GetTime()
	Items.sortSource = "Addon beim Öffnen"
	C_Container.SortBags()
	Items.sortSource = nil
	WatchSort()
end

local function SortOnOpen()
	sortQueued = false
	-- Not while selling, in combat, with an item on the cursor, in a window that moves items or during a sort.
	if not CanSortOnOpen() then
		return
	end
	local now = GetTime()
	if now - lastSort < SORT_PAUSE then
		Items.Trace("Öffnen: nicht sortiert (Pause)")
		return
	end
	local compare = Items.db.sortSkip and sortedLayout
	if compare and sortedRevision == bagRevision then
		Items.Trace("Öffnen: nicht sortiert (Belegung unverändert)")
		return
	end
	local signature, locked = ReadBagLayout(compare, true)
	if locked then
		Items.Trace("Öffnen: nicht sortiert (Gegenstand gesperrt)")
		return
	end
	if signature and sortedLayout == signature then
		sortedRevision = bagRevision
		Items.Trace("Öffnen: nicht sortiert (Belegung unverändert)")
		return
	end
	local revision = bagRevision
	sortQueued = true
	ns.After("Items: start game bag sort", 0, function()
		sortQueued = false
		StartAutomaticSort(revision)
	end)
end

function Items.LayoutSignature()
	return (ReadBagLayout(true))
end

-- Called when a sort is over.
function RecordLayout(signature)
	if not sorting and not InCombatLockdown() then
		Items.Trace("Stand gemerkt")
		sortedLayout = signature or Items.LayoutSignature()
		sortedRevision = bagRevision
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
	if not (Items.db.sortSkip and sortedLayout and not sorting and not InCombatLockdown()) then
		return false
	end
	if sortedRevision == bagRevision then
		return true
	end
	if sortedLayout == Items.LayoutSignature() then
		sortedRevision = bagRevision
		return true
	end
	return false
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

-- Comparison arrow on offered and guaranteed quest rewards, also in the quest log.
local rewardArrows = {}

local function GetRewardArrow(button)
	local arrow = rewardArrows[button]
	if not arrow then
		arrow = CreateFrame("Frame", nil, button)
		arrow:SetAllPoints(button.Icon or button.icon or button)
		arrow:SetFrameLevel(button:GetFrameLevel() + 6)
		arrow.texture = arrow:CreateTexture(nil, "OVERLAY", nil, 3)
		arrow.texture:SetAtlas("bags-greenarrow", true)
		arrow.texture:SetPoint("TOPRIGHT", 0, 0)
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
			local state = ns.RewardComparisonState(getLink(button.type, button:GetID()), MarkRewardUpgrades)
			if state then
				local arrow = GetRewardArrow(button)
				ns.SetItemComparisonArrow(arrow.texture, state)
				arrow:Show()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Fast loot: take every slot as soon as the loot window is ready
---------------------------------------------------------------------------
local lastLoot = 0

function Items:LOOT_READY()
	ns:GetModule("LootSources").CaptureWindow()
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
local QUEST_FAILED_SOUND = 567459 -- sound/interface/igquestfailed.ogg in the client

local function PlaySelectedFullSound()
	local choice = Items.db.fullSoundChoice
	if choice == "warning" then
		if not PlaySoundFile(QUEST_FAILED_SOUND, "Master") and SOUNDKIT and SOUNDKIT.RAID_WARNING then
			PlaySound(SOUNDKIT.RAID_WARNING, "Master")
		end
	elseif ns.AlertSounds then
		ns.AlertSounds.play(choice)
	end
end

function Items.PlayFullSound()
	local state = Items.fullState
	local now = GetTime()
	if now - state.last < 3 then
		return
	end
	state.last = now
	PlaySelectedFullSound()
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
	self:ToggleEvent("LOOT_SLOT_CHANGED", db.upgradeArrow, UpdateLootUpgrades)
	self:ToggleEvent("ITEM_DATA_LOAD_RESULT", db.upgradeArrow, OnLootItemData)
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
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", UsesGearScores(), function()
		ClearWeighCaches()
		UpdateAllBags()
		UpdateLootUpgrades()
	end)
end

function Items:OnInitialize()
	-- The old default was persisted even if the player never chose it.
	if not self.db.fullSoundDefaultUpdated then
		if self.db.fullSoundChoice == "ping" then
			self.db.fullSoundChoice = self.defaults.fullSoundChoice
		end
		self.db.fullSoundDefaultUpdated = true
	end
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
	ns.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
		if LootFrame and LootFrame.ScrollBox then
			ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, ns.Measured("Items: loot arrow", function(_, row, data)
				UpdateLootRow(row, data)
			end), self)
			UpdateLootUpgrades()
		end
	end)
	hooksecurefunc("StaticPopup_Show", FillDeleteText)
	HookRollFrames()
	if C_Container.SortBags then
		hooksecurefunc(C_Container, "SortBags", OnSortStarted)
	end
	UpdateSortOverlay()
	EventRegistry:RegisterCallback("ContainerFrame.OpenBag", QueueSort, self)
	EventRegistry:RegisterCallback("ContainerFrame.OpenAllBags", QueueSort, self)
	self:RegisterEvent("BAG_UPDATE", OnBagLayoutChanged)
	self:RegisterEvent("ITEM_LOCK_CHANGED", InvalidateBagLayout)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", InvalidateBagLayout)
	hooksecurefunc("QuestInfo_Display", MarkBestReward)
	hooksecurefunc("QuestInfo_Display", MarkRewardUpgrades)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Items: tooltip rating", AddScoreLine))
	-- The character window also uses these weights, even with all item ratings switched off.
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
		"LEARNED_SPELL_IN_SKILL_LINE" }) do
		self:RegisterEvent(event, QueueWeighRefresh)
	end
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
	if key == "upgradeArrow" then
		UpdateLootUpgrades()
	end
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
		local choices = { { "warning", L.ITEMS_FULL_SOUND_WARNING } }
		for _, entry in ipairs(ns.AlertSounds and ns.AlertSounds.choices or {}) do
			choices[#choices + 1] = entry
		end
		return choices
	end },
	{ key = "fullSoundTest", type = "button", name = L.ITEMS_FULL_SOUND_TEST, text = L.QUESTS_TEST, func = PlaySelectedFullSound },
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

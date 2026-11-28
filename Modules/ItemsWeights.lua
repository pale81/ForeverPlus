-- Items: stat weights per class and talent tree.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate

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
local function ClearWeights() weights = nil end
local _, playerClass = UnitClass("player")
local function PlayerClass() return playerClass end

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

-- Passive stat conversions and percentage stat multipliers from Forever's talent tables
-- (build 1.60.1.71037: SpellEffect, TraitDefinitionEffectPoints, CurvePoint).
-- Multipliers scale total stats before conversions run:
--   w(S) = mult(S) * (v0(S) + conv(S)), where v0(S) = max(0, w_ref(S) / mult_ref(S) - conv_ref(S)).
-- Warrior and Rogue have no passive stat-conversion or percentage stat-multiplier talents.
do
	local TALENT_MODS = {
		PALADIN = {
			{ spell = 20262, stat = "STR", step = 0.02, max = 5, ref = { 0, 0, 5 } }, -- Divine Strength
			{ spell = 20257, stat = "INT", step = 0.02, max = 5, ref = { 5, 0, 5 } }, -- Divine Intellect
			{ spell = 20143, stat = "ARMOR", step = 0.02, max = 5, ref = { 5, 3, 0 } }, -- Toughness
			{ spell = 20150, stat = "BVAL", step = 0.15, max = 2, ref = { 0, 2, 0 } }, -- Shield Specialization
			{ spell = 1311084, stat = "INT", target = "SP_DMG", step = 0.12, max = 5, ref = { 0, 0, 5 } }, -- Champion of the Light
		},
		HUNTER = {
			{ spell = 1223984, stat = "INT", target = "AP_RAP", step = 0.20, max = 5, ref = { 5, 5, 5 } }, -- Careful Aim
			{ spell = 19168, stat = "AGI", step = 0.03, max = 5, ref = { 0, 0, 5 } }, -- Lightning Reflexes
			{ spell = 19255, stat = "STA", step = 0.02, max = 5, ref = { 0, 0, 0 } }, -- Survivalist
		},
		PRIEST = {
			{ spell = 18551, stat = "INT", step = 0.02, max = 5, ref = { 5, 5, 3 } }, -- Mental Strength
			{ spell = 14901, stat = "SPI", target = "SP_DMG", curve = { 0.01, 0.03, 0.05, 0.06, 0.08 }, max = 5, ref = { 0, 5, 0 } }, -- Spiritual Guidance (damage)
			{ spell = 14901, stat = "SPI", target = "HEAL", step = 0.05, max = 5, ref = { 0, 5, 0 } }, -- Spiritual Guidance (healing)
		},
		SHAMAN = {
			{ spell = 17485, stat = "INT", step = 0.02, max = 5, ref = { 5, 3, 5 } }, -- Ancestral Knowledge
			{ spell = 415140, stat = "INT", target = "AP", curve = { 0.33, 0.66, 1.00 }, max = 3, ref = { 0, 3, 0 } }, -- Mental Dexterity
			{ spell = 30812, stat = "INT", target = "SP_BOTH", step = 0.15, max = 2, ref = { 0, 2, 0 } }, -- Mental Quickness
			{ spell = 16252, stat = "STA", step = 0.02, max = 5, ref = { 0, 0, 0 } }, -- Toughness
			{ spell = 16184, stat = "STA", step = 0.02, max = 2, ref = { 0, 0, 0 } }, -- Improved Reincarnation
		},
		MAGE = {
			{ spell = 11232, stat = "INT", step = 0.02, max = 5, ref = { 5, 0, 0 } }, -- Arcane Mind
			{ spell = 28574, stat = "INT", target = "ARMOR", step = 0.25, max = 3, ref = { 0, 0, 3 } }, -- Arcane Resilience
		},
		WARLOCK = {
			{ spell = 18697, stat = "STA", step = 0.03, max = 5, ref = { 5, 0, 0 } }, -- Demonic Embrace
		},
		DRUID = {
			{ spell = 17003, stat = "INT", step = 0.02, max = 5, ref = { 0, 5, 5, 5 } }, -- Heart of the Wild
			{ spell = 17003, stat = "STR", step = 0.02, max = 5, ref = { 0, 5, 5, 5 }, profiles = { [2] = true } }, -- Heart of the Wild (Cat)
			{ spell = 17003, stat = "STA", step = 0.04, max = 5, ref = { 0, 5, 5, 5 }, profiles = { [4] = true } }, -- Heart of the Wild (Bear)
			{ spell = 1309631, stat = "SPI", step = 0.05, max = 3, ref = { 0, 0, 3, 0 } }, -- Living Spirit
			{ spell = 1223242, stat = "INT", target = "HEAL", curve = { 0.12, 0.25 }, max = 2, ref = { 0, 2, 0, 2 } }, -- Natural Instinct
			{ spell = 16929, stat = "DEF", target = "ARMOR", curve = { 0.67, 1.33, 2.00 }, max = 3, ref = { 0, 0, 0, 3 }, profiles = { [1] = true, [2] = true, [4] = true } }, -- Thick Hide
		},
	}
	local TALENT_SPELLS = {}
	for class, list in pairs(TALENT_MODS) do
		local set = {}
		for _, entry in ipairs(list) do
			set[entry.spell] = true
		end
		TALENT_SPELLS[class] = set
	end

	local function Rate(entry, rank)
		rank = math.max(0, math.min(entry.max, rank or 0))
		if rank == 0 then
			return 0
		end
		return entry.curve and entry.curve[rank] or entry.step * rank
	end

	local function TargetWeight(base, target)
		if target == "SP_DMG" then
			return (base.HEAL or 0) > 0 and 0 or (base.SP or 0)
		elseif target == "HEAL" then
			return base.HEAL or 0
		elseif target == "SP_BOTH" then
			return base.HEAL or base.SP or 0
		elseif target == "AP_RAP" then
			return (base.AP or 0) + (base.RAP or 0)
		end
		return base[target] or 0
	end

	-- Adjusts a reference weight table for the player's actual learned talent ranks (`ranks[spellID]`).
	function Items.AdjustWeights(base, class, profile, ranks)
		local rules = TALENT_MODS[class]
		if not (base and rules and ranks) then
			return base
		end
		local touched, refMult, curMult, refConv, curConv = {}, {}, {}, {}, {}
		local anyChanged = false
		for _, entry in ipairs(rules) do
			if not entry.profiles or entry.profiles[profile] then
				local stat = entry.stat
				local refRank = entry.ref[profile] or 0
				local curRank = ranks[entry.spell] or 0
				if refRank ~= curRank then
					touched[stat] = true
					anyChanged = true
				end
				if entry.target then
					local tw = TargetWeight(base, entry.target)
					if tw > 0 then
						refConv[stat] = (refConv[stat] or 0) + Rate(entry, refRank) * tw
						curConv[stat] = (curConv[stat] or 0) + Rate(entry, curRank) * tw
					end
				else
					refMult[stat] = (refMult[stat] or 1) * (1 + Rate(entry, refRank))
					curMult[stat] = (curMult[stat] or 1) * (1 + Rate(entry, curRank))
				end
			end
		end
		if not anyChanged then
			return base
		end
		local adjusted
		for stat in pairs(touched) do
			local rm, cm = refMult[stat] or 1, curMult[stat] or 1
			local rc, cc = refConv[stat] or 0, curConv[stat] or 0
			local oldValue = base[stat] or 0
			local unscaled = oldValue / rm
			local intrinsic, scale = unscaled - rc, 1
			if rc > 0 and intrinsic < 0.25 then
				-- Keep a mana/crit floor when a rounded profile's weight is below the raw conversion sum
				-- (e.g. Enhancement Shaman INT = 1.15) and scale conversions proportionally to preserve identity.
				intrinsic = math.min(unscaled, 0.25)
				scale = (unscaled - intrinsic) / rc
			elseif intrinsic < 0 then
				intrinsic = 0
			end
			local newValue = cm * (intrinsic + cc * scale)
			if math.abs(newValue - oldValue) > 1e-6 and (newValue > 0 or base[stat] ~= nil) then
				adjusted = adjusted or CopyTable(base)
				adjusted[stat] = newValue
			end
		end
		return adjusted or base
	end

	local function ReadTalentRanks(configID, wanted)
		if not (configID and wanted and type(C_Traits.GetConfigInfo) == "function"
			and type(C_Traits.GetTreeNodes) == "function" and type(C_Traits.GetNodeInfo) == "function"
			and type(C_Traits.GetEntryInfo) == "function" and type(C_Traits.GetDefinitionInfo) == "function") then
			return nil
		end
		local config = C_Traits.GetConfigInfo(configID)
		local treeIDs = config and config.treeIDs
		if type(treeIDs) ~= "table" or #treeIDs == 0 then
			return nil
		end
		local ranks, seenNodes = {}, false
		for _, treeID in ipairs(treeIDs) do
			for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
				seenNodes = true
				local node = C_Traits.GetNodeInfo(configID, nodeID)
				local active = node and node.activeEntry
				local rank = node and ns.Number(node.activeRank, 0) or 0
				if active and rank > 0 and not ns.Secret(active.entryID) then
					local entry = C_Traits.GetEntryInfo(configID, active.entryID)
					local definitionID = entry and entry.definitionID
					local definition = definitionID and not ns.Secret(definitionID) and C_Traits.GetDefinitionInfo(definitionID)
					local spellID = definition and ns.Number(definition.spellID)
					if spellID and wanted[spellID] then
						ranks[spellID] = rank
					end
				end
			end
		end
		return seenNodes and ranks or nil
	end

	function Items.ApplyTalentWeights(base, class, profile, configID)
		local wanted = TALENT_SPELLS[class]
		if not wanted then
			return base
		end
		local ok, ranks = pcall(ReadTalentRanks, configID, wanted)
		if not ok or not ranks then
			return base
		end
		return Items.AdjustWeights(base, class, profile, ranks)
	end
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
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and ns.Number(C_ClassTalents.GetActiveConfigID())
	local index, _, trees = TalentTree(configID)
	local profile = Items.PickTree(Items.cdb and Items.cdb.scoreSpec, index or DEFAULT_SPEC[playerClass] or 1,
		playerClass == "DRUID" and BEAR_PROFILE or #classWeights)
	weightsPreset = profile
	local base
	if profile == BEAR_PROFILE then
		base, weightsName, weightsTree = FERAL_BEAR, L.ITEMS_SCORE_SPEC_BEAR, FERAL_TREE
	else
		base, weightsName, weightsTree = classWeights[profile], ScoreTreeName(profile, trees), profile
	end
	local adjusted = Items.ApplyTalentWeights(base, playerClass, profile, configID)
	if LEVELLING_MELEE[playerClass] and not adjusted.DPS then
		local level = UnitLevel("player")
		local share = math.min(1, math.max(0, (LEVELLING_NONE - level) / (LEVELLING_NONE - LEVELLING_FULL)))
		if share > 0 then
			if adjusted == base then
				adjusted = CopyTable(base)
			end
			adjusted.DPS = WEIGHTS.WARRIOR[1].DPS * share
		end
	end
	weights = adjusted
	return weights, weightsName, weightsTree, weightsPreset
end
ns.StatWeights = GetWeights -- for the ranking of the attributes in the character window

-- For the Items*.lua files loaded after this one.
P.ARMOR = ARMOR
P.ARMOR_TYPE = ARMOR_TYPE
P.ClearWeights = ClearWeights
P.GetWeights = GetWeights
P.IGNORED_WEAPONS = IGNORED_WEAPONS
P.PlayerClass = PlayerClass
P.RATING_STATS = RATING_STATS
P.RatingPercent = RatingPercent
P.SHARED_WEIGHT = SHARED_WEIGHT
P.ScoreSpecValues = ScoreSpecValues
P.StatName = StatName
P.equippedCache = equippedCache
P.linkUpgradeCache = linkUpgradeCache
P.scoreCache = scoreCache
P.upgradeCache = upgradeCache

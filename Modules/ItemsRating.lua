-- Items: weighted item value, usability and upgrade states.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local ARMOR, ARMOR_TYPE, GetWeights, IGNORED_WEAPONS = P.ARMOR, P.ARMOR_TYPE, P.GetWeights, P.IGNORED_WEAPONS
local IsRed, PlayerClass, RATING_STATS, RatingPercent = P.IsRed, P.PlayerClass, P.RATING_STATS, P.RatingPercent
local SHARED_WEIGHT, StatName, equippedCache, linkUpgradeCache = P.SHARED_WEIGHT, P.StatName, P.equippedCache, P.linkUpgradeCache
local scoreCache, upgradeCache = P.scoreCache, P.upgradeCache

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
		local abilities = ABILITIES[PlayerClass()]
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
	local types = ARMOR_TYPE[PlayerClass()]
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
P.weighStart, P.weighDone, P.weighDeferred, P.weighActive = 0, 0, false, false

local function BagComparisonState(bag, slot, link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end
	if P.weighActive then
		if P.weighDone > 0 and debugprofilestop() - P.weighStart > WEIGH_BUDGET then
			P.weighDeferred = true
			return false
		end
		P.weighDone = P.weighDone + 1
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

-- For the Items*.lua files loaded after this one.
P.AddScoreLine = AddScoreLine
P.BagComparisonState = BagComparisonState
P.CanUse = CanUse
P.ClearWeighCaches = ClearWeighCaches
P.CompareScores = CompareScores
P.EquippedScore = EquippedScore
P.LinkComparisonState = LinkComparisonState
P.LinkUpgradeState = LinkUpgradeState

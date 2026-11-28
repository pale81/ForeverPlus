-- Items: junk selling and marking, auto repair, quest reward value,
-- upgrade arrows in bags and loot, and fast looting. This file: the module, its options and the
-- junk rules; the rest follows in the Items*.lua files listed after it in ForeverPlus.toc.
local _, ns = ...
local L = ns.L
local P = {} -- shared by the Items*.lua files
ns.ItemsPrivate = P

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
		markWorseReward = true,
		markUnusableBound = true,
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

local function IsRed(color)
	return type(color) == "table" and not ns.Secret(color)
		and not ns.Secret(color.r) and not ns.Secret(color.g) and not ns.Secret(color.b)
		and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

do
	-- Classes in Forever (build 1.60.1.71037, docs/wissen/klassen.md) and the armor/weapon
	-- subclasses each class can EVER use, including trainer- and weapon-master-learned skills.
	local KNOWN_CLASSES = {
		WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
		SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
	}
	local ARMOR_PROFICIENCY = {
		[2] = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, SHAMAN = true, DRUID = true }, -- Leather
		[3] = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true }, -- Mail
		[4] = { WARRIOR = true, PALADIN = true }, -- Plate
		[6] = { WARRIOR = true, PALADIN = true, SHAMAN = true }, -- Shield
		[7] = { PALADIN = true }, -- Libram
		[8] = { DRUID = true }, -- Idol
		[9] = { SHAMAN = true }, -- Totem
	}
	local WEAPON_PROFICIENCY = {
		[0] = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, SHAMAN = true }, -- Axe1H
		[1] = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true }, -- Axe2H
		[2] = { WARRIOR = true, HUNTER = true, ROGUE = true }, -- Bows
		[3] = { WARRIOR = true, HUNTER = true, ROGUE = true }, -- Guns
		[4] = { WARRIOR = true, PALADIN = true, ROGUE = true, PRIEST = true, SHAMAN = true, DRUID = true }, -- Mace1H
		[5] = { WARRIOR = true, PALADIN = true, SHAMAN = true, DRUID = true }, -- Mace2H
		[6] = { WARRIOR = true, PALADIN = true, HUNTER = true, DRUID = true }, -- Polearm
		[7] = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true }, -- Sword1H
		[8] = { WARRIOR = true, PALADIN = true, HUNTER = true }, -- Sword2H
		[10] = { WARRIOR = true, HUNTER = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }, -- Staff
		[13] = { WARRIOR = true, HUNTER = true, ROGUE = true, SHAMAN = true, DRUID = true }, -- Unarmed / Fist
		[15] = { WARRIOR = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }, -- Dagger
		[16] = { WARRIOR = true, HUNTER = true, ROGUE = true }, -- Thrown
		[18] = { WARRIOR = true, HUNTER = true, ROGUE = true }, -- Crossbow
		[19] = { PRIEST = true, MAGE = true, WARLOCK = true }, -- Wand
	}

	local function FormatPatternCached(cacheKey, globalText)
		if Items[cacheKey] == nil then
			Items[cacheKey] = type(globalText) == "string" and ns.FormatToPattern(globalText, true).pattern or false
		end
		return Items[cacheKey] or nil
	end

	-- Returns true if an armor/weapon item can NEVER be used by `classFile` (neither by
	-- training weapon/armor proficiencies nor by leveling/professions), and is not currently
	-- group-tradeable.
	function Items.IsNeverUsableEquip(classID, subClassID, classFile, lines)
		local armorClass = type(Enum.ItemClass.Armor) == "number" and Enum.ItemClass.Armor or 4
		local weaponClass = type(Enum.ItemClass.Weapon) == "number" and Enum.ItemClass.Weapon or 2
		if classID ~= armorClass and classID ~= weaponClass then
			return false
		end
		classFile = classFile or select(2, UnitClass("player"))
		if not KNOWN_CLASSES[classFile] then
			return false
		end
		local allowed = (classID == armorClass and ARMOR_PROFICIENCY or WEAPON_PROFICIENCY)[subClassID]
		local subclassBlocked = allowed ~= nil and not allowed[classFile]
		local restricted = false
		if type(lines) == "table" then
			local tradeType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining
			local tradePattern = FormatPatternCached("tradeTimePattern", BIND_TRADE_TIME_REMAINING)
			local classPattern = not subclassBlocked and FormatPatternCached("classRestrictionPattern", ITEM_CLASSES_ALLOWED) or nil
			local racePattern = not subclassBlocked and FormatPatternCached("raceRestrictionPattern", ITEM_RACES_ALLOWED) or nil
			for _, line in ipairs(lines) do
				if type(line) == "table" and not ns.Secret(line) then
					if tradeType and not ns.Secret(line.type) and line.type == tradeType then
						return false
					end
					local text = line.leftText
					if type(text) == "string" and not ns.Secret(text) then
						if tradePattern and text:find(tradePattern) then
							return false
						end
						if not subclassBlocked and (IsRed(line.leftColor) or IsRed(line.rightColor)) then
							if (classPattern and text:find(classPattern)) or (racePattern and text:find(racePattern)) then
								restricted = true
							end
						end
					end
				end
			end
		end
		return subclassBlocked or restricted
	end

	function Items.IsNeverUsableBoundGear(info, bag, slot)
		if not (Items.db and Items.db.markUnusableBound) or not info or not info.itemID
			or info.hasNoValue or info.quality == Enum.ItemQuality.Poor then
			return false
		end
		if ns.Secret(info.isBound) or not info.isBound then
			return false
		end
		local item = (type(info.hyperlink) == "string" and not ns.Secret(info.hyperlink)) and info.hyperlink or info.itemID
		local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(item)
		local armorClass = type(Enum.ItemClass.Armor) == "number" and Enum.ItemClass.Armor or 4
		local weaponClass = type(Enum.ItemClass.Weapon) == "number" and Enum.ItemClass.Weapon or 2
		if classID ~= armorClass and classID ~= weaponClass then
			return false
		end
		local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
		if sellPrice ~= nil and sellPrice <= 0 then
			return false
		end
		if bag ~= nil and slot ~= nil then
			if type(C_Container.GetContainerItemQuestInfo) == "function" then
				local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
				if type(quest) == "table" and not ns.Secret(quest) then
					if (not ns.Secret(quest.isQuestItem) and quest.isQuestItem)
						or (not ns.Secret(quest.questID) and quest.questID) then
						return false
					end
				end
			end
			if type(C_Container.GetContainerItemPurchaseInfo) == "function" then
				local purchase = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
				if type(purchase) == "table" and not ns.Secret(purchase)
					and ns.Number(purchase.refundSeconds, 0) > 0 then
					return false
				end
			end
			if type(C_Item.IsBoundToAccountUntilEquip) == "function"
				and ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function" then
				local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
				if loc and C_Item.DoesItemExist(loc) and C_Item.IsBoundToAccountUntilEquip(loc) then
					return false
				end
			end
		end
		local data = bag ~= nil and slot ~= nil and type(C_TooltipInfo.GetBagItem) == "function"
			and C_TooltipInfo.GetBagItem(bag, slot) or nil
		return Items.IsNeverUsableEquip(classID, subClassID, nil, data and data.lines)
	end
end

-- Grey items and (when enabled) never-usable soulbound armor/weapons count as junk unless kept;
-- other items only when marked.
local function IsJunkItem(info, bag, slot)
	if info.quality == Enum.ItemQuality.Poor or Items.IsNeverUsableBoundGear(info, bag, slot) then
		return not IsKept(info)
	end
	return IsMarked(info)
end

local function IsJunk(info, bag, slot)
	if not info or info.hasNoValue or info.isLocked then
		return false
	end
	return IsJunkItem(info, bag, slot)
end

-- Bags flagged "ignore for junk selling" in Blizzard's bag menu.
local function BagExcludesJunk(bag)
	if bag == BACKPACK_CONTAINER then
		return C_Container.GetBackpackSellJunkDisabled()
	end
	return C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.ExcludeJunkSell)
end

-- For the Items*.lua files loaded after this one.
P.BagExcludesJunk = BagExcludesJunk
P.IsJunk = IsJunk
P.IsJunkItem = IsJunkItem
P.IsKept = IsKept
P.IsRed = IsRed
P.JunkKey = JunkKey
P.JunkLists = JunkLists
P.Report = Report
P.SELL_BATCH = SELL_BATCH
P.SELL_INTERVAL = SELL_INTERVAL

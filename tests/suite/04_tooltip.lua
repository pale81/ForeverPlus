-- find IsJunkItem via UpdateButton upvalue chain
local updateAll = uv(itemsMod.ShowJunkMenu, "UpdateAllBags")
local updateFrame = uv(updateAll, "UpdateContainerFrame")
local updateButton = uv(updateFrame, "UpdateButton")
IsJunkItemFn = uv(updateButton, "IsJunkItem")
local jkey = uv(uv(IsJunkItemFn, "IsMarked"), "JunkKey")
local monkey = { itemID = 100, quality = 2, hyperlink = "|cff1eff00|Hitem:100::::::612:::::|h[Hose des Affen]|h|r" }
local frost = { itemID = 100, quality = 2, hyperlink = "|cff1eff00|Hitem:100::::::1401:::::|h[Hose des Frostschutzes]|h|r" }
local k = jkey(monkey)
itemsMod.db.junk[k] = monkey.hyperlink
print("  keys", k, jkey(frost), IsJunkItemFn(monkey), IsJunkItemFn(frost), strsplit)
assert(IsJunkItemFn(monkey) and not IsJunkItemFn(frost), "suffix items told apart")
print("junk suffix OK", k)
-- Unit price behind the sell price
local tt = { lines = { "Hose", "Verkaufspreis: 40" }, GetName = function() return "TT" end, NumLines = function(self) return #self.lines end }
for i, text in ipairs(tt.lines) do _G["TTTextLeft" .. i] = { GetText = function() return tt.lines[i] end, SetText = function(_, t) tt.lines[i] = t end } end
local append = uv(uv(ns:GetModule("Tooltip").OnInitialize, "OnItemTooltip"), "AddUnitPrice")
local appendLine = uv(append, "AppendToSellLine")
assert(appendLine(tt, "(20 / Stück)") and tt.lines[2] == "Verkaufspreis: 40 (20 / Stück)", "unit price appended")
print("unit price OK")
-- Hover name with health mask (smoke test)
GetMouseFoci = function() return {} end
GetCursorPosition = function() return 180, 100 end
UnitExists = function() return true end
UnitName = function() return "Helaku" end
UnitLevel = function() return 13 end
UnitHealthPercent = function() return 0.3 end
GameTooltip_UnitColor = function() return 0.2, 0.6, 1 end
local show = uv(ns:GetModule("Tooltip").OnLogin, "ShowHoverName")
if show then show() end
do
	local Tip = ns:GetModule("Tooltip")
	local objectCall = uv(Tip.OnInitialize, "OnObjectTooltip")
	assert(objectCall, "object tooltip handler")
	UnitExists = function() return false end
	GameTooltipTextLeft1 = { GetText = function() return "Briefkasten" end, GetTextColor = function() return 1, 0.82, 0 end }
	GameTooltip.IsForbidden = function() return false end
	objectCall(GameTooltip)
	do
		-- An opened text keeps its grey name over the cursor, also without the read status option.
		local readable, hoverName = ns:GetModule("Readable"), uv(show, "GetHover")().Name
		local oldTitles, oldStatus, oldGray, oldColor = readable.cdb.openedTitles, readable.db.readStatus, GRAY_FONT_COLOR,
			hoverName.SetTextColor
		local red
		hoverName.SetTextColor = function(_, r) red = r end
		GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
		readable.cdb.openedTitles, readable.db.readStatus = {}, false
		objectCall(GameTooltip)
		assert(red == 1, "unopened object keeps its colour over the cursor")
		readable.cdb.openedTitles.Briefkasten = true
		objectCall(GameTooltip)
		assert(red == 0.5, "opened text is grey over the cursor")
		readable.cdb.openedTitles, readable.db.readStatus, GRAY_FONT_COLOR, hoverName.SetTextColor = oldTitles, oldStatus,
			oldGray, oldColor
	end

	-- A readable name can still have secret font measurements after hovering a unit.
	local frame = uv(show, "GetHover")()
	local savedSecret, savedSetSize = issecretvalue, frame.SetSize
	local savedWidth, savedHeight, savedLevelWidth = frame.Name.GetStringWidth, frame.Name.GetStringHeight, frame.Level.GetStringWidth
	local savedGreyWidth, savedGreyHeight = frame.Grey.GetStringWidth, frame.Grey.GetStringHeight
	local secret = 9999
	issecretvalue = function(value) return value == secret end
	frame.SetSize = function(self, width, height) self.w, self.h = width, height end
	frame.Name.GetStringWidth = function() return secret end
	frame.Name.GetStringHeight = function() return secret end
	objectCall(GameTooltip)
	assert(frame:IsShown() and not frame.masked and frame.w == 82 and frame.h == 14, "object uses unclipped text measurements")

	UnitExists = function() return true end
	show()
	assert(frame.masked and frame.w == 166 and frame.h == 14, "health mask works with secret dimensions on the clipped copy")
	frame.Grey.GetStringWidth = function() return secret end
	show()
	assert(frame:IsShown() and not frame.masked and not frame.Level:IsShown() and frame.w == 1 and frame.h == 13,
		"secret name width falls back to an unclipped label")
	frame.Grey.GetStringWidth = savedGreyWidth
	frame.Grey.GetStringHeight = function() return secret end
	show()
	assert(not frame.masked and not frame.Level:IsShown() and frame.w == 1 and frame.h == 13,
		"secret name height falls back to an unclipped label")
	frame.Grey.GetStringHeight = savedGreyHeight
	frame.Level.GetStringWidth = function() return secret end
	show()
	assert(frame.masked and not frame.Level:IsShown() and frame.w == 82 and frame.h == 14,
		"secret level width is excluded from layout")
	frame.Level.GetStringWidth = savedLevelWidth
	show()
	assert(frame.masked and frame.Level:IsShown() and frame.w == 166 and frame.h == 14,
		"regular layout returns with readable measurements")
	frame.Name.GetStringWidth, frame.Name.GetStringHeight = savedWidth, savedHeight
	issecretvalue, frame.SetSize = savedSecret, savedSetSize

	-- the name stays while the tooltip comes and shows, and goes when the game starts fading it out
	local stays, peak = Tip.ObjectNameStays(false, 0, nil, 0.05)
	assert(stays, "tooltip not shown yet right after its data: name stays")
	stays, peak = Tip.ObjectNameStays(true, 1, peak, 0.5)
	assert(stays and peak == 1, "full tooltip: name stays")
	stays = Tip.ObjectNameStays(true, 0.7, peak, 0.8)
	assert(not stays, "fading tooltip: name goes")
	stays = Tip.ObjectNameStays(false, 1, 1, 0.5)
	assert(not stays, "tooltip gone: name goes")
	stays, peak = Tip.ObjectNameStays(true, 0.3, 0.3, 0.3)
	assert(stays and peak == 0.3, "taken over while fading: stays")
	stays, peak = Tip.ObjectNameStays(true, 1, peak, 0.4)
	assert(stays and peak == 1, "comes back up: stays")
end
print("hover OK")
;(function()
	local tooltip = ns:GetModule("Tooltip")
	local frame = uv(show, "GetHover")()
	local savedUnit, savedWorld, savedFoci, savedCursor = UnitExists, WorldFrame, GetMouseFoci, C_TooltipInfo.GetWorldCursor
	local savedParent, savedScale = frame.SetParent, frame.SetScale
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local unit, data, parent, scale = true
	WorldFrame = { GetEffectiveScale = function() return 0.5 end }
	GetMouseFoci = function() return { WorldFrame } end
	UnitExists = function(token) return token == "mouseover" and unit end
	C_TooltipInfo.GetWorldCursor = function() return data end
	frame.SetParent = function(_, value) parent = value end
	frame.SetScale = function(_, value) scale = value end

	tooltip.SetWanderlustHover(true)
	assert(frame:IsShown() and not frame.object and parent == WorldFrame and scale == 2,
		"Wanderlust moves the existing unit label outside the hidden interface and preserves its scale")
	unit = false
	data = { type = Enum.TooltipDataType.Object, lines = { { leftText = "Copper Vein" } } }
	local function CursorChanged() eventFrame.scripts.OnEvent(eventFrame, "WORLD_CURSOR_TOOLTIP_UPDATE") end
	CursorChanged()
	assert(frame:IsShown() and frame.object, "Wanderlust shows the object from world cursor data")
	GameTooltip.scripts.OnTooltipCleared(GameTooltip)
	frame.scripts.OnUpdate(frame, 0.1)
	assert(frame:IsShown(), "GameTooltip clearing and fading do not hide the independent object label")
	tooltip.db.hoverObjects = false
	tooltip:OnOptionChanged("hoverObjects")
	assert(not frame:IsShown(), "the normal object option is respected during Wanderlust")
	tooltip.db.hoverObjects = true
	tooltip:OnOptionChanged("hoverObjects")
	assert(frame:IsShown(), "reenabling object text refreshes the current cursor")
	data = nil
	CursorChanged()
	assert(not frame:IsShown(), "leaving the object hides the label")

	unit = true
	tooltip.db.hoverName = false
	tooltip:OnOptionChanged("hoverName")
	show()
	assert(not frame:IsShown(), "the normal mouseover option also controls the Wanderlust unit label")
	tooltip.db.hoverName = true
	tooltip:OnOptionChanged("hoverName")
	tooltip.SetWanderlustHover(false)
	assert(frame:IsShown() and parent == UIParent and scale == 1, "restoring the interface returns the unit label to its normal parent")
	assert(not uv(ns.RegisterEvent, "listeners").WORLD_CURSOR_TOOLTIP_UPDATE,
		"restoring the interface stops reading world cursor data for Wanderlust")
	UnitExists, WorldFrame, GetMouseFoci, C_TooltipInfo.GetWorldCursor = savedUnit, savedWorld, savedFoci, savedCursor
	frame.SetParent, frame.SetScale = savedParent, savedScale
end)()
-- Rank up: rank 2 replaced by rank 3, rank 1 kept
local qolMod = ns:GetModule("QoL")
local rankUp = uv(qolMod.UpdateRankUp, "RankUp")
local bars = { [1] = 101, [2] = 102 }
local names = { [101] = "Welle", [102] = "Welle", [103] = "Welle" }
local ranks = { [101] = "Rang 1", [102] = "Rang 2", [103] = "Rang 3" }
C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellSubtext = function(id) return ranks[id] end
HasAction = function(slot) return bars[slot] ~= nil end
GetActionInfo = function(slot) return "spell", bars[slot] end
local cursor
C_Spell.PickupSpell = function(id) cursor = id end
ClearCursor = function() cursor = nil end
PlaceAction = function(slot) bars[slot] = cursor end
rankUp(103)
assert(bars[1] == 101 and bars[2] == 103, "rank up")
print("rank up OK")
-- Chat: whole word keywords, highlight, short channels
local chatMod = ns:GetModule("Chat")
chatMod.cdb.keywords = "it, Müller"
local parse = uv(chatMod.UpdateKeywordAlert, "ParseKeywords")
parse()
local contains = uv(uv(chatMod.UpdateKeywordAlert, "HighlightFilter"), "ContainsKeyword")
assert(not contains("bitte invite mich"), "invite no match")
assert(contains("IT geht"), "it match")
assert(contains("wer ist müller?") == false or true)
assert(not contains("|cff1eff00|Hitem:1|h[it]|h|r"), "link ignored")
local highlight = uv(chatMod.UpdateKeywordAlert, "HighlightFilter")
chatMod.db.keywordColor = "ORANGE"
local _, text = highlight(nil, "CHAT_MSG_SAY", "it is it, invite it", "Other")
print("  hl", text)
assert(text == "|cffff8000it|r is |cffff8000it|r, invite |cffff8000it|r", "highlight")
local short = uv(uv(chatMod.UpdateChannelNames, "ChannelFilter"), "ShortName")
assert(short("Allgemein") == "A" and short("Handel") == "H" and short("LokaleVerteidigung") == "LV" and short("Handel lokal") == "HL", "short names")
local cf = uv(chatMod.UpdateChannelNames, "ChannelFilter")
local r = { cf(nil, "CHAT_MSG_CHANNEL", "hi", "X", "", "2. Handel - Stadt", "", "", 2, 2, "Handel") }
print("  chan", r[5], #r[5])
assert(r[5]:sub(1, 4) == "2. H" and #r[5] >= #"2. Handel - Stadt" and r[10] == "Handel", "channel filter")
print("chat OK")
-- Loot summary
LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
LOOT_ITEM_CREATED_SELF = "Ihr stellt her: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "Ihr stellt her: %sx%d."
YOU_LOOT_MONEY = "Ihr plündert %s"
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silber", "%d Kupfer"
local lootMod = ns:GetModule("Loot")
-- rebuild patterns by reloading the file with the globals set
local chunk = assert(loadfile(root .. "/Modules/Loot.lua"))
ns.modules.Loot = nil
chunk("ForeverPlus", ns)
lootMod = ns.modules.Loot
lootMod.db = { summary = true, delay = 20, inlineQuality = "UNCOMMON" }
local onLoot = lootMod.CHAT_MSG_LOOT
local parseItem = uv(onLoot, "ParseItem")
link = "|cff1eff00|Hitem:100::::|h[Hose]|h|r"
local l1, c1 = parseItem("Ihr erhaltet Beute: " .. link .. "x3.")
assert(l1 == link and c1 == 3, "multiple parse")
local l2, c2 = parseItem("Ihr erhaltet Beute: " .. link .. ".")
assert(l2 == link and c2 == 1, "single parse")
assert(not parseItem("Helaku erhält Beute: " .. link .. "."), "other player")
do
	local l3, c3, cr3 = parseItem("Ihr stellt her: " .. link .. "x4.")
	assert(l3 == link and c3 == 4 and cr3 == true, "created multiple")
	local l4, c4, cr4 = parseItem("Ihr stellt her: " .. link .. ".")
	assert(l4 == link and c4 == 1 and cr4 == true, "created single")
end
assert(select(3, parseItem("Ihr erhaltet Beute: " .. link .. ".")) == false, "looted not created")
local parseMoney = uv(lootMod.CHAT_MSG_MONEY, "ParseMoney")
assert(parseMoney("Ihr plündert 1 Gold, 2 Silber, 3 Kupfer") == 10203, "money parse")
print("loot OK")
-- Loot flow: filter hides, event collects, flush prints one line per group
ChatTypeInfo = { LOOT = { r = 0, g = 1, b = 0, id = 1 }, MONEY = { r = 1, g = 1, b = 0, id = 2 } }
GetMoneyString = function(v) return tostring(v) .. "c" end
C_Item.GetItemQualityByID = function() return 2 end
local out = {}
local fakeFrame = { AddMessage = function(_, t) out[#out + 1] = t end }
local lootFilter = uv(lootMod.Update, "LootFilter")
local moneyFilter = uv(lootMod.Update, "MoneyFilter")
local msg = "Ihr erhaltet Beute: " .. link .. "x2."
assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", msg) == true, "filter hides")
assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", "Helaku erhält Beute: x.") == false, "filter keeps others")
lootMod:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg)
lootMod:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link .. ".")
assert(moneyFilter(fakeFrame, "CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer") == true)
-- Chat filters leave protected text alone (patterns and comparisons on it are errors in the game)
;(function()
	local savedSecret = issecretvalue
	local secret = {}
	issecretvalue = function(value) return secret[value] == true end
	secret[msg] = true
	assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", msg) == false, "loot filter: protected text stays")
	secret["Ihr plündert 5 Kupfer"] = true
	assert(moneyFilter(fakeFrame, "CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer") == false, "money filter: protected text stays")
	secret["it is it"] = true
	assert(select("#", highlight(nil, "CHAT_MSG_SAY", "it is it", "Other")) == 1, "highlight: protected text unchanged")
	secret["it is it"] = nil
	secret["Geheim"] = true
	assert(select("#", highlight(nil, "CHAT_MSG_SAY", "it is it", "Geheim")) == 1, "highlight: protected sender")
	secret["Handel"] = true
	assert(select("#", cf(nil, "CHAT_MSG_CHANNEL", "hi", "X", "", "2. Handel - Stadt", "", "", 2, 2, "Handel")) == 1,
		"channel filter: protected name unchanged")
	issecretvalue = savedSecret
	print("chat filters with protected text OK")
end)()
lootMod:CHAT_MSG_MONEY("CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer")
uv(lootMod.Update, "Flush")()
for _, t in ipairs(out) do print("  ", t) end
assert(#out == 2 and out[1]:find(" 3 ", 1, true) and out[1]:find(link .. "x3", 1, true) and out[2]:find("5c", 1, true), "summary lines")
print("loot flow OK")

-- Upgrade: Forever talent trees, shaman hammer from the screenshot
local scoreFn = upvalue(upvalue(compare, "EquippedScore"), "Score")
getW = upvalue(scoreFn, "GetWeights")
local function resetWeights()
	local scoreFn = upvalue(upvalue(compare, "EquippedScore"), "Score")
	for k in pairs(upvalue(scoreFn, "scoreCache")) do upvalue(scoreFn, "scoreCache")[k] = nil end
	for k in pairs(upvalue(upvalue(compare, "EquippedScore"), "equippedCache")) do upvalue(upvalue(compare, "EquippedScore"), "equippedCache")[k] = nil end
	for i = 1, 200 do local n = debug.getupvalue(getW, i) if not n then break end if n == "weights" then debug.setupvalue(getW, i, nil) end if n == "playerClass" then debug.setupvalue(getW, i, "SHAMAN") end end end
trees = { { groupID = 11, orderIndex = 0, displayName = "Elementar" }, { groupID = 12, orderIndex = 1, displayName = "Verstärkung" }, { groupID = 13, orderIndex = 2, displayName = "Wiederherstellung" } }
local spent = { [11] = 0, [12] = 0, [13] = 0 }
C_ClassTalents = { GetActiveConfigID = function() return 5 end }
C_Traits = rawget(_G, "C_Traits") or {}
C_Traits.GetConfigInfo = function() return { treeIDs = { 77 } } end
C_Traits.GetGroupDisplayInfoByTreeID = function() return { trees[3], trees[1], trees[2] } end
C_Traits.GetGroupCurrencyInfo = function(_, ids) local r = {} for _, id in ipairs(ids) do r[#r + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = spent[id] } } } end return r end
CopyTable = CopyTable or function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
ITEMS["talk"] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6.1, ITEM_MOD_STAMINA_SHORT = 1 } }
ITEMS["hammer"] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 7.3, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1 } }
CanDualWield = function() return false end
GetInventoryItemLink = function(_, slot) return slot == 16 and "talk" or nil end
UnitLevel = function() return 10 end
resetWeights()
C_Item.GetItemInfoInstant = function(link) local d = ITEMS[link] return 1, nil, nil, d[1], nil, d[2], d[3] end
C_Item.GetItemStats = function(link) return ITEMS[link][4] end
C_Item.IsItemDataCachedByID = function() return true end
C_Item.DoesItemExist = function() return true end
local s1, e1 = compare("hammer")
print("  no points", s1, e1, select(2, getW()))
assert(s1 > e1 and select(3, getW()) == 2, "hammer better without points, enhancement weights by default")
spent[11] = 1
resetWeights()
local s2, e2 = compare("hammer")
print("  elemental lvl10", s2, e2, select(2, getW()))
assert(select(2, getW()) == "Elementar" and select(3, getW()) == 1 and s2 > e2, "hammer better for levelling elemental")
UnitLevel = function() return 60 end
resetWeights()
local s3, e3 = compare("hammer")
print("  elemental lvl60", s3, e3)
assert(s3 < e3, "weapon dps irrelevant for elemental at 60")
-- DPS from the tooltip when stats lack it
DPS_TEMPLATE = "(%.1f Schaden pro Sekunde)"
local chunk = assert(loadfile(root .. "/Modules/Items.lua"))
local pat = "^" .. DPS_TEMPLATE:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%%%%.1f", "([%%d%%.,]+)") .. "$"
print("  pattern", pat, ("(7,3 Schaden pro Sekunde)"):match(pat))
assert(("(7,3 Schaden pro Sekunde)"):match(pat) == "7,3")
print("upgrade trees OK")
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedStats, savedInfo = C_Item.GetItemStats, C_Item.GetItemInfoInstant
	local savedRating = GetCombatRatingBonusForCombatRatingValue
	local serial = 0
	local function CheckScore(stats, expected)
		C_Item.GetItemStats = function() return stats end
		serial = serial + 1
		local score = scoreFn("rating-test:" .. serial)
		assert(math.abs(score - expected) < 0.0001, ("expected %.2f, got %.2f"):format(expected, score))
	end
	C_Item.GetItemInfoInstant = function() return nil, nil, nil, nil, nil, Enum.ItemClass.Armor end
	GetCombatRatingBonusForCombatRatingValue = nil
	local shared = { ITEM_MOD_HIT_RATING_SHORT = 4, ITEM_MOD_CRIT_RATING_SHORT = 14 }
	setuv(getW, "weights", { HIT = 15, SHIT = 14, CRIT = 10, SCRIT = 12 })
	CheckScore(shared, 18)
	setuv(getW, "weights", { SHIT = 14, SCRIT = 12 })
	CheckScore(shared, 17.6)
	CheckScore({ ITEM_MOD_HIT_RANGED_RATING_SHORT = 4 }, 0)
	setuv(getW, "weights", { SP = 0.85, HEAL = 1, SHASTE = 12 })
	CheckScore({ ITEM_MOD_HASTE_RATING_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 20, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 }, 34.5)
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").MAGE[2])
	CheckScore({ ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 10, ITEM_MOD_FROST_DAMAGE_DONE_SHORT = 20 }, 9)

	setuv(getW, "weights", upvalue(getW, "WEIGHTS").PALADIN[2])
	CheckScore({
		ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 4, ITEM_MOD_BLOCK_VALUE_SHORT = 3,
		ITEM_MOD_BLOCK_RATING_SHORT = 5, ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_PARRY_RATING_SHORT = 15,
		ITEM_MOD_EXPERTISE_RATING_SHORT = 10, ITEM_MOD_HASTE_RATING_SHORT = 10,
	}, 53.1)
	local index, value
	GetCombatRatingBonusForCombatRatingValue = function(ratingIndex, raw)
		index, value = ratingIndex, raw
		return 0.2
	end
	setuv(getW, "weights", { HIT = 15 })
	CheckScore({ ITEM_MOD_HIT_RATING_SHORT = 4 }, 3)
	assert(index == 6 and value == 4, "prefer the client's conversion for the actual rating amount")
	setuv(getW, "weights", savedProfile)
	C_Item.GetItemStats, C_Item.GetItemInfoInstant = savedStats, savedInfo
	GetCombatRatingBonusForCombatRatingValue = savedRating
	print("forever item rating units OK")
end)()
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip = GetInventoryItemLink, C_TooltipInfo.GetHyperlink
	local savedEquippable, savedEnabled = C_Item.IsEquippableItem, itemsMod.db.upgradeScore
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local flat = de and "Anlegen: +3 Angriffskraft" or "Equip: +3 Attack Power"
	local against = de and "Anlegen: +4 Angriffskraft gegen Humanoide." or "Equip: +4 Attack Power against Humanoids."
	local baseStats = { RESISTANCE0_NAME = 15, ITEM_MOD_STAMINA_SHORT = 2 }
	local cloak, defender, situational = "catacombCloak", "shadowDefenderCloak", "situationalCloak"
	ITEMS[cloak] = { "INVTYPE_CLOAK", 4, 1, baseStats }
	ITEMS[defender] = { "INVTYPE_CLOAK", 4, 1, { RESISTANCE0_NAME = 17, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE5_NAME = 2 } }
	ITEMS[situational] = { "INVTYPE_CLOAK", 4, 1, { RESISTANCE0_NAME = 14, ITEM_MOD_STAMINA_SHORT = 2 } }
	local equipped = cloak
	GetInventoryItemLink = function(_, slot) return slot == 15 and equipped or nil end
	C_Item.IsEquippableItem = function() return true end
	C_TooltipInfo.GetHyperlink = function(link)
		local effects = {}
		if link == cloak then
			effects = {
				{ leftText = flat },
				{ type = 45, leftText = "|cff00ff00" .. against .. "|r" },
				{ leftText = de and "Benutzen: +99 Angriffskraft" or "Use: +99 Attack Power" },
			}
		elseif link == situational then
			effects = { { type = 45, leftText = against:match(": (.+)") } }
		end
		return { lines = effects }
	end
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").PALADIN[2])
	clear()
	local score, worn, humanoid, wornHumanoid = compare(defender)
	assert(math.abs(score - 4.7) < 0.001 and math.abs(worn - 5.55) < 0.001, "flat attack power beats two additional armor")
	assert(humanoid == score and math.abs(wornHumanoid - 6.95) < 0.001, "equipped cloak gains only four more AP against Humanoids")
	assert(BagComparisonState(0, 1, defender) == "worse", "the Defender Cloak is worse than the Catacomb Cloak")

	local lines = {}
	local tip = { AddLine = function(_, line) lines[#lines + 1] = line end }
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine(tip, defender)
	assert(#lines == 2 and lines[2] == ns.L.ITEMS_SCORE_HUMANOID_LINE:format(humanoid, wornHumanoid),
		"the tooltip shows both items' rating against Humanoids even if only the equipped one has the bonus")

	clear()
	baseStats.ITEM_MOD_ATTACK_POWER_SHORT = 3
	local apiScore, apiBonus = scoreFn(cloak)
	assert(apiScore == worn and math.abs(apiBonus - 1.4) < 0.001, "do not double count flat AP reported by the client")
	equipped = defender
	local conditional, normal, againstHumanoid, wornAgainst = compare(situational)
	assert(conditional < normal and againstHumanoid > wornAgainst, "a situational cloak can win the Humanoid comparison")
	assert(BagComparisonState(0, 1, situational) == "worse", "the generic arrow uses the base rating")

	-- Comparison tooltips: the arrow goes to the better of the hovered and the worn item.
	clear()
	equipped = cloak
	local winner, which = ns.CompareWinner(defender, { cloak })
	assert(winner == "worn" and which == 1, "the better worn cloak gets the arrow")
	assert(ns.RewardComparisonState(defender) == "worse", "a worse quest reward uses the same rating")
	equipped = defender
	clear()
	winner, which = ns.CompareWinner(cloak, { defender })
	assert(winner == "hovered" and which == true, "the better hovered cloak gets the arrow")
	equipped = cloak
	clear()
	assert(ns.CompareWinner(cloak, { cloak }) == nil, "equal items: no arrow")
	itemsMod.db.upgradeArrow = false
	assert(ns.CompareWinner(cloak, { defender }) == nil, "option off: no arrow")
	-- the rating for sorted lists: gain over the worn item, independent of the arrow option
	equipped = defender
	clear()
	local gain, block = ns.ItemLinkRating(cloak)
	assert(gain > 0.01 and block == "ok", "the better cloak gains and can be worn")
	equipped = cloak
	clear()
	gain, block = ns.ItemLinkRating(defender)
	assert(gain < 0 and block == nil, "the worse cloak loses, no tooltip read")
	itemsMod.db.upgradeArrow = true

	clear()
	ITEMS[cloak], ITEMS[defender], ITEMS[situational] = nil, nil, nil
	itemsMod.db.upgradeScore = savedEnabled
	C_Item.IsEquippableItem = savedEquippable
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink = savedEquipped, savedTooltip
	setuv(getW, "weights", savedProfile)
	print("protection paladin attack power and humanoid cloak comparison OK")
end)()
-- "Chance on hit" damage counts at 1 proc per minute (screenshot: axe against Ironforge great hammer).
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip = GetInventoryItemLink, C_TooltipInfo.GetHyperlink
	local savedLocation, savedExists, savedEnabled = ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, itemsMod.db.upgradeScore
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local procText = de and "Trefferchance: Fügt einem Ziel 42 Feuerschaden zu." or "Chance on hit: Blasts a target for 42 Fire damage."
	local R = ns.ProcRateDefault
	assert(R == 1.95 and ns.ProcRates[17705][1] == 1, "bundled rates: default is the Forever median, Thrash Blade measured")
	assert(itemsMod.ProcDamage(de and "Schleudert einen Feuerball, der 155 bis 197 Feuerschaden verursacht."
		or "Hurls a fiery ball that causes 155 to 197 Fire damage.") == 176, "a damage range counts with its average")
	assert(itemsMod.ProcDamage(de and "Verursacht 30 Schaden." or "Deals 30 damage.") == 30, "plain damage without a school")
	assert(itemsMod.ProcDamage(de and "Betäubt das Ziel 3 Sek. lang." or "Stuns target for 3 sec.") == 0, "no damage, no value")
	assert(itemsMod.ProcDamage("Schleudert eine glühende Kugel hinaus, die 155 bis 197 Punkt(e) Feuerschaden sowie zusätzlich 6 Sek. lang 24 Punkt(e) Schaden verursacht.") == 176
		or not de, "German damage with Punkt(e)")
	local axe, hammer = "excavationAxe", "ironforgeHammer"
	ITEMS[axe] = { "INVTYPE_2HWEAPON", 2, 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.5, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 8 } }
	ITEMS[hammer] = { "INVTYPE_2HWEAPON", 2, 5, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.97 } }
	GetInventoryItemLink = function(_, slot) return slot == 16 and axe or nil end
	ItemLocation.CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end
	C_Item.DoesItemExist = function(location) return location.slot == 16 end
	C_TooltipInfo.GetHyperlink = function(link)
		return { lines = link == hammer and { { type = 46, leftText = "|cff00ff00" .. procText .. "|r" } } or {} }
	end
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").SHAMAN[2])
	clear()
	local score, worn = compare(hammer)
	assert(math.abs(worn - 262.8) < 0.001, "equipped axe: 17.5 DPS, 7 strength, 8 stamina")
	assert(math.abs(score - (15.97 * 14 + R * 42 / 60 * 14)) < 0.001, "the hammer's proc counts at the default rate")
	assert(BagComparisonState(0, 1, hammer) == "worse", "the proc does not make up for the axe's stats")
	local lines = {}
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(#lines == 2 and lines[2] == ns.L.ITEMS_SCORE_PROC_LINE:format(R * 42 / 60 * 14, R, ns.L.ITEMS_PROC_RATE_0),
		"the tooltip names the counted proc rating and the default rate")
	-- A weapon with a measured rate uses it (the harness gives every item ID 1).
	ns.ProcRates[1] = { 0.95, 1 }
	clear()
	assert(math.abs(scoreFn(hammer) - (15.97 * 14 + 0.95 * 42 / 60 * 14)) < 0.001, "measured rate")
	lines = {}
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(lines[2] == ns.L.ITEMS_SCORE_PROC_LINE:format(0.95 * 42 / 60 * 14, 0.95, ns.L.ITEMS_PROC_RATE_1), "the tooltip names a measured rate")
	ns.ProcRates[1] = nil
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").MAGE[1])
	clear()
	assert(select(3, scoreFn(hammer)) == 0, "casters do not count melee procs")

	clear()
	ITEMS[axe], ITEMS[hammer] = nil, nil
	itemsMod.db.upgradeScore = savedEnabled
	ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist = savedLocation, savedExists
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink = savedEquipped, savedTooltip
	setuv(getW, "weights", savedProfile)
	print("chance on hit damage rating OK")
end)()
-- Weapon speed through known instant attacks, extra attacks, attack speed procs and Hand of Justice.
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip, savedKnown = GetInventoryItemLink, C_TooltipInfo.GetHyperlink, IsPlayerSpell
	local savedLocation, savedExists, savedAP = ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, rawget(_G, "UnitAttackPower")
	local savedDual, savedSubclass = rawget(_G, "CanDualWield"), Enum.ItemWeaponSubclass
	local savedClass, savedTree = upvalue(getW, "playerClass"), upvalue(getW, "weightsTree")
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local function speedLine(speed) return { leftText = "1 - 2", rightText = (de and "Tempo " or "Speed ") .. speed } end
	local axe, hammer, thrash, ironfoe, demolisher, hand = "speedAxe", "speedHammer", "thrashBlade", "ironfoe", "demolisher", "handOfJustice"
	ITEMS[axe] = { "INVTYPE_2HWEAPON", 2, 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.5, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 8 } }
	ITEMS[hammer] = { "INVTYPE_2HWEAPON", 2, 5, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.97 } }
	ITEMS[thrash] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[ironfoe] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[demolisher] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[hand] = { "INVTYPE_TRINKET", 4, 0, {} }
	local tips = {
		[axe] = { speedLine("2,40") },
		[hammer] = { speedLine("3,10"), { type = 46, leftText = de and "Trefferchance: Fügt einem Ziel 42 Feuerschaden zu." or "Chance on hit: Blasts a target for 42 Fire damage." } },
		[thrash] = { speedLine("2.70"), { leftText = de and "Trefferchance: Gewährt Euch einen zusätzlichen Angriff bei Eurem nächsten Schwung."
			or "Chance on hit: Grants an extra attack on your next swing." } },
		[ironfoe] = { speedLine("2.40"), { leftText = de and "Trefferchance: Gewährt Euch 2 zusätzliche Angriffe bei Eurem nächsten Schwung."
			or "Chance on hit: Grants 2 extra attacks on your next swing." } },
		[demolisher] = { speedLine("2.40"), { leftText = de and "Trefferchance: Erhöht Euer Angriffstempo 10 Sek. lang um 20%."
			or "Chance on hit: Increases your attack speed by 20% for 10 sec." } },
		[hand] = { { leftText = de and "Anlegen: Chance von 2%, bei einem Nahkampftreffer einen zusätzlichen Angriff zu erhalten."
			or "Equip: 2% chance on melee hit to gain 1 extra attack." } },
	}
	C_TooltipInfo.GetHyperlink = function(link) return { lines = tips[link] or {} } end
	local mainHand = axe
	GetInventoryItemLink = function(_, slot) return slot == 16 and mainHand or nil end
	ItemLocation.CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end
	C_Item.DoesItemExist = function(location) return location.slot == 16 end
	UnitAttackPower = function() return 0, 0, 0 end
	Enum.ItemWeaponSubclass = { Dagger = 15, Fishingpole = 20 }
	local known = {}
	IsPlayerSpell = function(id) return known[id] == true end
	local function profile(class, tree)
		setuv(getW, "weights", upvalue(getW, "WEIGHTS")[class][tree])
		setuv(getW, "weightsTree", tree)
		setuv(getW, "playerClass", class)
		clear()
	end

	-- Level 15 Enhancement shaman without Stormstrike: the weapon speed does not count.
	profile("SHAMAN", 2)
	local _, _, proc, speed = scoreFn(hammer)
	local R = ns.ProcRateDefault
	assert(speed == 0 and math.abs(proc - R * 42 / 60 * 14) < 0.001, "no Stormstrike, no speed rating")
	-- With Stormstrike (3 per minute, normalized): the slower weapon loses less against 3.3 s.
	known[17364] = true
	clear()
	local hammerScore, _, _, hammerSpeed = scoreFn(hammer)
	local axeScore, _, _, axeSpeed = scoreFn(axe)
	assert(math.abs(hammerSpeed - 14 * 3 / 60 * 15.97 * (3.1 - 3.3)) < 0.001, "hammer speed rating")
	assert(math.abs(axeSpeed - 14 * 3 / 60 * 17.5 * (2.4 - 3.3)) < 0.001, "axe speed rating")
	assert(axeScore > hammerScore, "the axe stays better with Stormstrike")
	local lines = {}
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(lines[#lines] == ns.L.ITEMS_SCORE_SPEED_LINE:format(hammerSpeed), "the tooltip names the speed rating")
	-- Attack power counts for swing attacks (Seal of Command) but not for normalized ones.
	UnitAttackPower = function() return 700, 0, 0 end
	clear()
	assert(math.abs(select(4, scoreFn(hammer)) - hammerSpeed) < 0.001, "normalized attacks ignore attack power")
	profile("PALADIN", 3)
	known[20375] = true
	assert(math.abs(select(4, scoreFn(hammer)) - 0.8 * 14 * 4.9 / 60 * (15.97 + 50) * (3.1 - 3.3)) < 0.001,
		"Seal of Command scales attack power with the weapon speed")

	-- Extra attacks: one proc per minute adds a whole swing with attack power.
	profile("ROGUE", 2)
	UnitAttackPower = function() return 280, 0, 0 end
	local thrashProc = select(3, scoreFn(thrash))
	assert(math.abs(thrashProc - 1 * 14 * (R / 60) * (40 + 20) * 2.7) < 0.001, "one extra attack per proc")
	assert(math.abs(select(3, scoreFn(ironfoe)) - 1 * 14 * (2 * R / 60) * (40 + 20) * 2.4) < 0.001, "two extra attacks per proc")
	-- Attack speed: 20% for 10 s of every minute.
	local haste = upvalue(getW, "WEIGHTS").ROGUE[2].HASTE
	assert(math.abs(select(3, scoreFn(demolisher)) - haste * 20 * R * 10 / 60) < 0.001, "attack speed proc uses the haste weight")
	-- Hand of Justice: 2% of the main hand's white damage per second.
	mainHand = thrash
	clear()
	assert(math.abs(select(3, scoreFn(hand)) - 1 * 14 * 0.02 * (40 + 20)) < 0.001, "Equip chance of an extra attack")

	-- Dual wield: Sinister Strike rates the main hand speed, the off hand has none.
	known[1752] = true
	CanDualWield = function() return true end
	C_Item.DoesItemExist = function(location) return location.slot == 16 or location.slot == 17 end
	local slow, fast = "slowSword", "fastSword"
	ITEMS[slow] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[fast] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	tips[slow], tips[fast] = { speedLine("2.90") }, { speedLine("1.50") }
	GetInventoryItemLink = function(_, slot) return (slot == 16 or slot == 17) and fast or nil end
	clear()
	assert(select(4, scoreFn(slow, false, true)) == 0, "no speed rating in the off hand")
	local score, worn = compare(slow)
	assert(math.abs(worn - 40 * 14 - 14 * 10 / 60 * 40 * (1.5 - 2.4)) < 0.001, "the slow sword replaces the fast main hand")
	assert(score > worn, "a slow main hand is an upgrade for Sinister Strike")

	-- Instant Poison VI on both hands: a faster weapon procs it more often, in either hand.
	local savedSlot, savedEnchants, savedHit = Enum.WeaponSlot, C_Item.GetWeaponEnchantInfo, ns.ImbueHitDamage
	local enchants = { [1] = 625, [2] = 625 }
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	C_Item.GetWeaponEnchantInfo = function(slot) return { { hasEnchant = true, enchantID = enchants[slot] } } end
	clear()
	local poison = function(speed) return 0.2 * (88 + 0.01 * 280) * (1 / speed - 1 / 2.4) end
	assert(math.abs(select(4, scoreFn(slow, false, true)) - 14 * poison(2.9)) < 0.001, "slow off hand: less poison")
	assert(math.abs(select(4, scoreFn(fast, false, true)) - 14 * poison(1.5)) < 0.001, "fast off hand: more poison")
	enchants = {}
	clear()
	assert(select(4, scoreFn(fast, false, true)) == 0, "no poison, no speed rating in the off hand")

	-- Weapon skill counts for the weapon in hand only: Edgemaster's Handguards with a dagger.
	local gloves, dagger = "edgemaster", "dagger"
	ITEMS[gloves] = { "INVTYPE_HAND", 4, 2, {} }
	ITEMS[dagger] = { "INVTYPE_WEAPON", 2, 15, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	tips[gloves] = de and { { leftText = "Anlegen: Äxte +7." }, { leftText = "Anlegen: Dolche +7." }, { leftText = "Anlegen: Schwerter +7." } }
		or { { leftText = "Equip: Increased Axes +7." }, { leftText = "Equip: Increased Daggers +7." }, { leftText = "Equip: Increased Swords +7." } }
	GetInventoryItemLink = function(_, slot) return slot == 16 and dagger or nil end
	clear()
	local hit = upvalue(getW, "WEIGHTS").ROGUE[2].HIT
	assert(math.abs(scoreFn(gloves) - hit * 0.2 * 7) < 0.001, "seven dagger skill, axes and swords do not count")

	-- Undead and Demons: shown in the tooltip, not part of the rating.
	local seal = "markOfTheChampion"
	ITEMS[seal] = { "INVTYPE_TRINKET", 4, 0, {} }
	tips[seal] = { { leftText = de and "Anlegen: +150 Angriffskraft im Kampf gegen Untote und Dämonen. Ermöglicht das Einsammeln von Geißelsteinen."
		or "Equip: +150 Attack Power when fighting Undead and Demons.  It also allows the acquisition of Scourgestones." } }
	clear()
	assert(scoreFn(seal) == 0, "situational attack power stays out of the rating")
	lines = {}
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, seal)
	assert(lines[#lines] == ns.L.ITEMS_SCORE_CREATURE_LINE:format(de and "Untote und Dämonen" or "Undead and Demons", 150),
		"the tooltip shows the rating against Undead and Demons")

	-- Stormstrike's hit brings the imbue: the slower weapon's bigger Windfury hits count.
	profile("SHAMAN", 2)
	enchants = { [1] = 1669 }
	ns.ImbueHitDamage = function(id, speed, dps, ap) return id == 1669 and 0.2 * 2 * (dps + ap / 14) * speed or nil end
	clear()
	local stormstrike = 14 * 3 / 60 * (15.97 * (3.1 - 3.3) + 0.4 * (15.97 + 20) * (3.1 - 3.3))
	assert(math.abs(select(4, scoreFn(hammer)) - stormstrike) < 0.001, "Stormstrike adds the Windfury difference")

	Enum.WeaponSlot, C_Item.GetWeaponEnchantInfo, ns.ImbueHitDamage = savedSlot, savedEnchants, savedHit
	ITEMS[gloves], ITEMS[dagger], ITEMS[seal] = nil, nil, nil

	clear()
	for _, link in ipairs({ axe, hammer, thrash, ironfoe, demolisher, hand, slow, fast }) do ITEMS[link] = nil end
	ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, UnitAttackPower = savedLocation, savedExists, savedAP
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink, IsPlayerSpell = savedEquipped, savedTooltip, savedKnown
	CanDualWield, Enum.ItemWeaponSubclass = savedDual, savedSubclass
	setuv(getW, "playerClass", savedClass)
	setuv(getW, "weightsTree", savedTree)
	setuv(getW, "weights", savedProfile)
	print("weapon speed, extra attack and haste rating OK")
end)()
-- The imbue damage of one main-hand hit, from the spell text as in the DPS simulator.
;(function()
	local savedSpell, savedTalents, savedBonus = C_Spell, C_ClassTalents, rawget(_G, "GetSpellBonusDamage")
	local texts = { [16362] = "Imbue the Shaman's weapon with wind. Each hit has a 20% chance of dealing 2 additional attacks with 315 extra attack power.",
		[16342] = "Imbue the Shaman's weapon with fire. Each hit causes 30 to 92 additional Fire damage." }
	C_Spell = setmetatable({ GetSpellDescription = function(id) return texts[id] end }, { __index = savedSpell })
	C_ClassTalents = { GetActiveConfigID = function() return nil end }
	GetSpellBonusDamage = function() return 100 end
	local wind = ns.ImbueHitDamage(1669, 3.6, 50, 700)
	assert(math.abs(wind - 0.2 * 2 * (50 + (700 + 315) / 14) * 3.6) < 0.001, "Windfury: chance times extra attacks with extra attack power")
	local fire = ns.ImbueHitDamage(1666, 2.0, 50, 700)
	assert(math.abs(fire - (92 * 2.0 / 4 + 0.1 * 100)) < 0.001, "Flametongue: upper endpoint scaled from 4.0 s plus spell power")
	assert(ns.ImbueHitDamage(1664, 3.6, 50, 700) == nil, "Rockbiter brings no hit damage")
	C_Spell, C_ClassTalents, GetSpellBonusDamage = savedSpell, savedTalents, savedBonus
	print("imbue hit damage OK")
end)()
-- Upgrade toast: gain over the worn item, none for an empty slot
do
	local items = ns:GetModule("Items")
	assert(math.abs(items.UpgradeGain(15, 12) - 25) < 0.001, "25 % better")
	assert(items.UpgradeGain(5, 0) == nil and items.UpgradeGain(5, nil) == nil, "empty slot: no percent")
	-- usable now, only the level missing (a grey arrow), or not at all
	local red, white = { r = 1, g = 0.1, b = 0.1 }, { r = 1, g = 1, b = 1 }
	local level = ns.FormatToPattern("Benötigt Stufe %d", true).pattern
	assert(items.UseBlock({ { leftText = "Brust", leftColor = white } }, level) == "ok", "nothing red")
	assert(items.UseBlock({ { leftText = "Benötigt Stufe 18", leftColor = red } }, level) == "level", "only the level")
	assert(items.UseBlock({ { leftText = "Benötigt Stufe 18", leftColor = red }, { leftText = "Platte", leftColor = red } }, level) == "no",
		"level and armour type")
	assert(items.UseBlock(nil, level) == "no", "no tooltip data")
	print("upgrade gain OK")
end
-- Group finder: classes and missing roles
local gf = ns:GetModule("GroupFinder")
local updateEntry = uv(gf.OnOptionChanged, "RefreshAll") and uv(uv(gf.OnOptionChanged, "RefreshAll"), "UpdateEntry")
C_LFGList = {
	GetSearchResultInfo = function() return { numMembers = 3, activityIDs = { 1 }, hasSelf = false } end,
	GetActivityInfoTable = function() return { maxNumPlayers = 5 } end,
	GetSearchResultPlayerInfo = function(_, i) return ({ { classFilename = "WARRIOR", assignedRole = "TANK" }, { classFilename = "MAGE", assignedRole = "DAMAGER" }, { classFilename = "PRIEST", assignedRole = "NONE" } })[i] end,
}
CreateAtlasMarkup = function(a) return "{" .. a .. "}" end
GREEN_FONT_COLOR = { WrapTextInColorCode = function(_, t) return t end }
GRAY_FONT_COLOR = GREEN_FONT_COLOR
local texts = {}
local entry = { resultID = 1, DataDisplay = { SetAlpha = function(_, a) texts.alpha = a end } }
local displays = uv(updateEntry, "GetDisplay")
local gd = uv(displays, "displays")
gd[entry] = { Classes = { SetText = function(_, t) texts.classes = t end }, Missing = { SetText = function(_, t) texts.missing = t end }, SetAlpha = function() end, Show = function() end, Hide = function() end }
updateEntry(entry)
print("  gf", texts.classes, texts.missing, texts.alpha)
assert(texts.classes:find("warrior") < texts.classes:find("mage") and texts.missing:find("heal}1") and texts.missing:find("dps}2") and texts.alpha == 0, "group finder")
print("group finder OK")
-- QuestieDB: dungeon quests and pre-quests
local quests = { [100] = { zone = 1581 }, [101] = { zone = 40, pre = nil, next = 102 }, [102] = { zone = 40 }, [103] = { zone = 40, single = { 102 } }, [104] = { zone = 10029 }, [105] = { zone = 12 } }
-- 101 -> 102 (next) ; 103 requires 102 ; 102 does not lead to a dungeon, 106 requires 105 and is a dungeon quest
quests[106] = { zone = 1581, single = { 105 } }
LibQuestieDB = {
	Support = { Get = function() return { private = { dungeons = { [1581] = { "The Deadmines", { 10029 }, 40, {} } } } } end },
	Quest = {
		Exists = function(id) return quests[id] ~= nil end,
		Get = function(id, key) return quests[id] and key == "zoneOrSort" and quests[id].zone end,
		GetAllIds = function() local l = {} for id in pairs(quests) do l[#l + 1] = id end table.sort(l) return l end,
		GetAll = function(id) local q = quests[id] return q and { q.single, q.group, q.next or 0, 0, n = 4 } end,
	},
}
local qdb = ns.QuestieDB
do -- earlier reads cached the dungeon table of the real data mock
	local da = uv(qdb.IsDungeonQuest, "DungeonAreas")
	for i = 1, 20 do local n = debug.getupvalue(da, i) if n == "dungeonAreas" then debug.setupvalue(da, i, nil) break end end
	for i = 1, 30 do
		local n = debug.getupvalue(qdb.BuildChains, i)
		if n == "followers" or n == "building" then debug.setupvalue(qdb.BuildChains, i, nil) end
	end
end
assert(qdb.IsDungeonQuest(100) == true and qdb.IsDungeonQuest(104) == true and qdb.IsDungeonQuest(102) == false and qdb.IsDungeonQuest(999) == nil, "dungeon quests")
do
	local savedTicker = C_Timer.NewTicker
	C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
	local built = false
	qdb.BuildChains(function() built = true end)
	C_Timer.NewTicker = savedTicker
	assert(built, "chains built")
end
assert(qdb.LeadsToDungeon(105) == true and qdb.LeadsToDungeon(101) == false, "pre-quest leads to dungeon")
print("questiedb OK")
-- QuestieDB tooltips
local info = ns:GetModule("QuestieInfo")
local npcs = { [10] = { name = "Kobold", questStarts = { 200, 201, 202, 203 }, questEnds = { 204 } }, [11] = { name = "Gnoll" }, [12] = { name = "Händlerin" } }
local qdbItems = { [500] = { name = "Leinenstoff", npcDrops = { 10, 11, 10 }, vendors = { 12 } } }
local qs = { [200] = { name = "Offen", requiredLevel = 5 }, [201] = { name = "Zu hoch", requiredLevel = 30 }, [202] = { name = "Andere Klasse", requiredClasses = 128 }, [203] = { name = "Vorquest fehlt", preQuestSingle = { 199 } }, [204] = { name = "Abgabe" } }
local function entity(t) return {
	Exists = function(id) return t[id] ~= nil end,
	Get = function(id, key) return t[id] and t[id][key] end,
	GetAll = function(id, keys) local r = { n = #keys } for i, k in ipairs(keys) do r[i] = t[id] and t[id][k] end return r end,
	GetAllIds = function() return {} end } end
LibQuestieDB = { Support = { Get = function() return {} end }, Quest = entity(qs), Npc = entity(npcs), Item = entity(qdbItems), Object = entity({}), RequireContract = function() return false end }
UnitClass = function() return "Schamane", "SHAMAN", 7 end
UnitRace = function() return "Tauren", "Tauren", 6 end
UnitLevel = function() return 14 end
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
C_QuestLog.GetLogIndexForQuestID = function(id) return id == 204 and 3 or nil end
C_Item.GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 7, 0 end
local out = {}
local tt = { IsForbidden = function() return false end, AddLine = function(_, t) out[#out + 1] = t end, Show = function() end }
for _, section in ipairs(ns.itemSections) do
	if section.order == 40 then
		for _, l in ipairs(section.fn({ id = 500 }) or {}) do out[#out + 1] = l.left end
	end
end
GameTooltip = tt
uv(info.OnInitialize, "OnUnitTooltip")(tt, { guid = "Creature-0-1-2-3-10-0000" })
for _, l in ipairs(out) do print("  ", l) end
local all = table.concat(out, "\n")
assert(all:find("Kobold, Gnoll") and all:find("Händlerin") and all:find("Offen") and not all:find("Zu hoch") and not all:find("Andere Klasse") and not all:find("Vorquest fehlt") and all:find("Abgabe"), "questie tooltips")
print("questie info OK")
-- Chat: input history and chat log
local chatM = ns:GetModule("Chat")
local styleFrame = uv(uv(chatM.OnLogin, "StyleAll"), "StyleChatFrame")
local hookHistory = uv(styleFrame, "HookHistory")
local recordSent = uv(hookHistory, "RecordSent")
local onArrow = uv(hookHistory, "OnHistoryArrow")
chatM.cdb.sentHistory = {}
recordSent(nil, "/w Bob hallo"); recordSent(nil, "hi"); recordSent(nil, "hi")
local eb = { text = "", SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end, SetCursorPosition = function() end }
onArrow(eb, "UP"); assert(eb.text == "hi", "up 1")
onArrow(eb, "UP"); assert(eb.text == "/w Bob hallo", "up 2")
onArrow(eb, "DOWN"); onArrow(eb, "DOWN"); assert(eb.text == "", "down to empty")
local logLine = uv(uv(styleFrame, "HookLog"), "LogLine")
chatM.cdb.chatLog = {}
local cf = { GetID = function() return 1 end }
for i = 1, 250 do logLine(cf, "line " .. i, 1, 1, 1) end -- trimmed in steps of 50
assert(#chatM.cdb.chatLog[1] == 200 and chatM.cdb.chatLog[1][1][1] == "line 51", "log ring")
-- Chat edges: left/right/bottom reach the screen edge, the tabs keep room on top
do
local applyEdges = uv(uv(styleFrame, "HookEdges"), "ApplyEdges")
local edgeFrame = NewFrame("Frame")
edgeFrame.clamp = { -32, 25, 60, -32 }
chatM.db.chatEdges, chatM.db.hideButtons = true, true
applyEdges(edgeFrame)
assert(edgeFrame.clamp[1] == 0 and edgeFrame.clamp[2] == 0 and edgeFrame.clamp[3] == 30 and edgeFrame.clamp[4] == 0, "edges reach the border")
edgeFrame.clamp = { -32, 25, 60, -32 }
chatM.db.hideButtons = false
applyEdges(edgeFrame)
assert(edgeFrame.clamp[1] == -32 and edgeFrame.clamp[3] == 30, "button column stays while shown")
chatM.db.chatEdges = false
edgeFrame.clamp = { -32, 25, 60, -32 }
applyEdges(edgeFrame)
assert(edgeFrame.clamp[3] == 60, "off: Blizzard's values")
chatM.db.chatEdges, chatM.db.hideButtons = true, true
end
-- Bind prompts and delete text
do
	local items = ns:GetModule("Items")
	local equipped, confirmed = nil, false
	EquipPendingItem = function(slot) equipped = slot end
	ConfirmBindOnUse = function() confirmed = true end
	items:USE_BIND_CONFIRM()
	assert(confirmed, "use bind confirmed")
	local fill = uv(items.OnLogin, "FillDeleteText")
	local box = { SetText = function(self, t) self.text = t end }
	local dialog = { GetEditBox = function() return box end }
	StaticPopup_FindVisible = function() return dialog end
	DELETE_ITEM_CONFIRM_STRING = "DELETE"
	items.db.deleteText = false
	fill("DELETE_GOOD_ITEM"); assert(box.text == nil, "off: nothing typed")
	items.db.deleteText = true
	fill("DELETE_ITEM"); assert(box.text == nil, "simple delete has no text")
	fill("DELETE_GOOD_ITEM"); assert(box.text == "DELETE", "word entered")
end
-- Extra tooltip info only with Shift
do
	local tt = ns:GetModule("Tooltip")
	tt.db.shiftInfo = false
	IsShiftKeyDown = function() return false end
	assert(ns.ExtraInfoShown(), "option off: always")
	tt.db.shiftInfo = true
	assert(not ns.ExtraInfoShown(), "option on: hidden without Shift")
	IsShiftKeyDown = function() return true end
	assert(ns.ExtraInfoShown(), "option on: shown with Shift")
	tt.db.shiftInfo = false
end
;(function()
	local module = ns:GetModule("Tooltip")
	local onShift = uv(module.OnLogin, "OnShiftChanged")
	local savedTooltip, savedSecrets, savedSecret = GameTooltip, C_Secrets, issecretvalue
	local savedSecretTable, savedWorld = issecrettable, C_TooltipInfo.GetWorldCursor
	local savedShiftInfo = module.db.shiftInfo
	module.db.shiftInfo = true
	local refreshed, restrictedUnit = 0, nil
	local types = Enum.TooltipDataType
	local item = { tooltipData = { type = types.Item, lines = {} } }
	local world = { getterName = "GetWorldCursor", tooltipData = { type = types.Unit, lines = { { unitToken = "mouseover" } } } }
	local liveWorld, secretColor, restrictedLines = world.tooltipData, {}, {}
	C_TooltipInfo.GetWorldCursor = function() return liveWorld end
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.RefreshData = function() refreshed = refreshed + 1 end
	C_Secrets = { ShouldUnitIdentityBeSecret = function(unit) return unit == restrictedUnit end }
	issecretvalue = function(value) return value == "secret" or value == secretColor end
	issecrettable = function(value) return value == restrictedLines end

	GameTooltip.infoList = { item }
	onShift(nil, nil, "LCTRL")
	assert(refreshed == 0, "other modifiers do not refresh the tooltip")
	onShift(nil, nil, "LSHIFT")
	GameTooltip.infoList = { world }
	onShift(nil, nil, "RSHIFT")
	assert(refreshed == 2, "Shift rebuilds readable item and world tooltips")

	GameTooltip.infoList = { item, { tooltipData = { lines = { { unitToken = "secret" } } } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret unit line in appended data prevents the rebuild")

	GameTooltip.infoList = { item, { tooltipData = { lines = { { leftText = "name", leftColor = secretColor } } } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret line colour in appended data prevents the rebuild")

	GameTooltip.infoList = { item, { tooltipData = { lines = restrictedLines } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a table whose contents are secret prevents the rebuild")

	GameTooltip.infoList = { { getterName = "GetUnit", getterArgs = { "secret" }, tooltipData = world.tooltipData } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret getter argument prevents the rebuild")

	GameTooltip.infoList = { { tooltipData = { type = types.UnitAura, lines = {} } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a tooltip without Shift extras does not need to be rebuilt")

	GameTooltip.infoList = { world }
	restrictedUnit = "mouseover"
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a newly restricted mouseover prevents replaying the world cursor getter")
	restrictedUnit = nil
	liveWorld = { type = types.Unit, lines = { { leftText = "name", rightText = "level", rightColor = secretColor } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "newly restricted line colours prevent the rebuild even with readable cached data and identity")
	liveWorld = world.tooltipData
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 3, "normal refresh resumes when the unit is readable again")

	GameTooltip, C_Secrets, issecretvalue = savedTooltip, savedSecrets, savedSecret
	issecrettable, C_TooltipInfo.GetWorldCursor = savedSecretTable, savedWorld
	module.db.shiftInfo = savedShiftInfo
	print("Shift tooltip refresh OK")
end)()

(function()
	-- Buff reminder: a missing buff waits while the power for it is lacking.
	local buffs = ns:GetModule("Buffs")
	local update = uv(buffs.OnLogin, "Update")
	local evaluate = uv(uv(update, "EvaluateOwn"), "Evaluate")
	setuv(uv(evaluate, "PickSpell"), "classDB", {})
	local reminder = { key = "intellect", auras = { 1459 }, cast = { 1459 } }
	IsPlayerSpell = function() return true end
	C_SpellBook = C_SpellBook or {}
	C_SpellBook.IsSpellKnown = function() return true end
	setuv(evaluate, "FindAura", function() return nil end)
	local noPower = true
	C_Spell.IsSpellUsable = function() return false, noPower end
	local powerStates = {}
	assert(not evaluate(reminder, 60, powerStates) and powerStates.Spell1459 == true, "no mana: hidden, waits for power")
	noPower = false
	wipe(powerStates)
	assert(evaluate(reminder, 60, powerStates) and powerStates.Spell1459 == false, "mana back: shown and still watched")
	-- The target first, then oneself; the target's buff is read on the target
	assert(buffs.BuffUnit(true, true) == "target" and buffs.BuffUnit(true, false) == "player"
		and buffs.BuffUnit(false, false) == nil, "who the button buffs")
	local onUnit
	setuv(evaluate, "FindAura", function(_, unit) onUnit = unit return 30 end)
	local missing, expiring = buffs.EvaluateTarget(reminder, 60)
	assert(onUnit == "target" and missing and expiring, "target's buff runs out: shown faded")
	setuv(evaluate, "FindAura", function() return 0 end)
	assert(not buffs.EvaluateTarget(reminder, 60), "target has it: no button")
	-- Blessings per target: Might not for priests and hunters, Wisdom not for warriors, no second blessing of a
	-- kind, nothing while one's own is on the target
	local all = { kings = true, might = true, wisdom = true, salvation = true, light = true }
	local function pick(class, known, on)
		return (buffs.ChooseBlessing(class, false, known or all, on or {}, 60, 20))
	end
	assert(pick("PRIEST", { might = true, wisdom = true }) == "wisdom", "priest: Wisdom, never Might")
	assert(pick("PRIEST", { might = true }) == nil, "priest: no Might at all")
	assert(pick("WARRIOR", { might = true, wisdom = true }) == "might", "warrior: Might")
	assert(pick("WARRIOR", { wisdom = true }) == nil, "warrior: no Wisdom")
	assert(pick("HUNTER", { might = true, wisdom = true }) == "wisdom", "hunter: Might adds no ranged power")
	assert(pick("ROGUE") == "kings", "Kings first")
	assert(pick("ROGUE", nil, { kings = { remaining = 200 } }) == "might", "Kings from another paladin: Might")
	assert(pick("MAGE", nil, { kings = { remaining = 200 }, wisdom = { remaining = 200 } }) == "salvation", "next free kind")
	assert(pick("MAGE", nil, { might = { remaining = 200, mine = true } }) == nil, "own blessing on it: nothing")
	local kind, renew = buffs.ChooseBlessing("MAGE", false, all, { light = { remaining = 30, mine = true } }, 60, 20)
	assert(kind == "light" and renew, "own blessing runs out: renewed, same kind")
	assert(pick("DEATHKNIGHT", { might = true, wisdom = true }) == "might"
		and buffs.ChooseBlessing("DEATHKNIGHT", true, { might = true, wisdom = true }, {}, 60, 20) == "wisdom", "other class: by mana")
	assert(not buffs.HasMana("WARRIOR", true) and buffs.HasMana("HUNTER", false), "mana by class")
	-- One's own blessing: another paladin's blessing does not stand for it
	local function own(preferred, on)
		return buffs.ChooseBlessing("PALADIN", true, all, on or {}, 60, 20, false, preferred)
	end
	assert(own("wisdom", { might = { remaining = 200 } }) == "wisdom", "Might from another paladin, own Wisdom gone: Wisdom offered")
	assert(own("might", { might = { remaining = 200 } }) == "kings", "the chosen kind is on already: the next free one")
	assert(own("wisdom", { wisdom = { remaining = 200, mine = true }, might = { remaining = 200 } }) == nil, "own blessing on: nothing")
	local ownKind, ownRenew = own("wisdom", { wisdom = { remaining = 30, mine = true } })
	assert(ownKind == "wisdom" and ownRenew, "own blessing runs out: renewed")
	assert(own("wisdom", {}) == "wisdom", "nothing on: the chosen kind")
	-- The whole bar: a friendly player in the target lacks Intellect, the player has it
	local saved = { UnitExists, UnitIsPlayer, UnitIsUnit, UnitCanAssist, UnitIsDeadOrGhost, UnitIsConnected, UnitName }
	UnitExists, UnitIsPlayer = function() return true end, function() return true end
	UnitIsUnit = function(a, b) return a == b end
	UnitCanAssist, UnitIsConnected = function() return true end, function() return true end
	UnitIsDeadOrGhost, UnitName = function() return false end, function(unit) return unit == "target" and "Brann" or "Ich" end
	setuv(evaluate, "FindAura", function(_, unit) if unit == "target" then return nil end return 0 end)
	assert(uv(update, "bar"), "bar built at login")
	assert(rawget(_G, "ForeverPlusBuffButton1") and _G["BINDING_NAME_CLICK ForeverPlusBuffButton1:LeftButton"] == ns.L.BUFFS_BINDING,
		"first button exists for the key binding")
	-- In a rest area the same rule as for oneself: only with the option
	local savedResting, savedZones = IsResting, buffs.db.restingZones
	local savedTracking = C_Minimap.GetNumTrackingTypes
	C_Minimap.GetNumTrackingTypes = function() return 0 end
	buffs.db.restingZones = false
	update()
	local first = uv(update, "buttons")[1]
	assert(not (first and first.shown), "rest area without the option: no button for the target either")
	buffs.db.restingZones = true
	update()
	first = uv(update, "buttons")[1]
	assert(first and first.shown and first.targetName == "Brann", "rest area with the option: the target is buffed")
	buffs.db.restingZones = savedZones
	IsResting = function() return false end
	update()
	first = uv(update, "buttons")[1]
	assert(first and first.shown and first.targetName == "Brann", "button buffs the target, named below")

	local savedPower, savedCosts, savedPowerType = rawget(_G, "UnitPower"), C_Spell.GetSpellPowerCost, rawget(Enum, "PowerType")
	local events = uv(update, "events")
	local onEvent = events:GetScript("OnEvent")
	local eventRegistered = false
	events.RegisterUnitEvent = function(_, event, unit)
		if event == "UNIT_POWER_UPDATE" then eventRegistered = unit == "player" end
	end
	events.UnregisterEvent = function(_, event)
		if event == "UNIT_POWER_UPDATE" then eventRegistered = false end
	end
	Enum.PowerType = { Mana = 0 }
	local mana = 25
	UnitPower = function(unit, power)
		assert(unit == "player" and power == 0, "the caster pays the cost in mana")
		return mana
	end
	C_Spell.GetSpellPowerCost = function(spell)
		if spell == "Spell1459" then return { { type = 0, minCost = 80, cost = 100 } } end
	end
	update()
	assert(not first.shown and eventRegistered, "target-only reminder waits until the cast rank is affordable")
	mana = 80
	onEvent(events, "UNIT_POWER_UPDATE", "player", "MANA")
	assert(first.shown and first.targetName == "Brann" and eventRegistered, "target reminder returns at the minimum mana needed")
	mana = 79
	onEvent(events, "UNIT_POWER_UPDATE", "player", "MANA")
	assert(not first.shown and eventRegistered, "a visible reminder hides as mana drops below the cost")
	setuv(evaluate, "FindAura", function(_, unit) if unit == "target" then return 0 end end)
	assert(not evaluate(reminder, 60), "the caster's own reminder uses the same mana check")
	setuv(evaluate, "FindAura", function() return 0 end)
	update()
	assert(not eventRegistered, "mana is ignored while all buffs are active")
	events.RegisterUnitEvent, events.UnregisterEvent = nil, nil
	UnitPower, C_Spell.GetSpellPowerCost, Enum.PowerType = savedPower, savedCosts, savedPowerType

	local savedDescription, savedAura, savedClock = C_Spell.GetSpellDescription, C_UnitAuras.GetAuraDataBySpellName, GetServerTime
	local savedAfter, savedTimer, savedRange = ns.After, ns.NewTimer, buffs.db.targetRange
	local savedAttribute, attributes = first.SetAttribute, {}
	first.SetAttribute = function(_, key, value) attributes[key] = value end
	local now, targetMissing, auraDuration = 10000, true
	local scheduled, nextUpdate
	GetServerTime = function() return now end
	ns.After = function(_, _, fn) fn() end
	ns.NewTimer = function(_, delay, fn)
		scheduled, nextUpdate = delay, fn
		return { Cancel = function() end }
	end
	buffs.db.targetRange = false
	C_Spell.GetSpellDescription = function(id)
		if id == 1459 then
			return GetLocale() == "deDE" and "Hält 30 Min. lang an." or "Lasts 30 min."
		end
	end
	C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if name == "Spell1459" and auraDuration then return { duration = auraDuration } end
	end
	setuv(evaluate, "FindAura", function(_, unit)
		if unit == "target" and not targetMissing then return 0 end
	end)
	update()
	local click = first:GetScript("PostClick")
	click(first, "MiddleButton", false)
	assert(not next(buffs.cdb.mutedUntil) and attributes["*type3"] == nil, "target click does not mute")
	targetMissing = false
	update()
	assert(attributes.type == "spell" and attributes["*type3"] == "", "only the secure middle click action is blocked")
	click(first, "LeftButton", false)
	click(first, "MiddleButton", true)
	assert(first.spellID == 1459 and not next(buffs.cdb.mutedUntil), "mute only on middle button release")
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800 and scheduled == 1800.5, "mute for the full tooltip duration")
	assert(first.shown and first.spellID == 6117, "other self buffs still show")
	targetMissing = true
	update()
	assert(first.targetName == "Brann" and first.spellID == 1459 and scheduled == 1800.5,
		"target stays eligible and the own reminder's timer is still scheduled")
	targetMissing = false
	now = now + 1800
	nextUpdate()
	assert(first.shown and first.spellID == 1459 and not buffs.cdb.mutedUntil.intellect, "reminder returns at expiry")
	auraDuration = 3600
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 3600, "the active aura's full duration takes precedence")
	now = now + 3600
	nextUpdate()
	auraDuration = 0
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800, "an unlimited aura is muted for 30 minutes")
	now = now + 1800
	nextUpdate()
	auraDuration = nil
	C_Spell.GetSpellDescription = function() return "" end
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800 and first.spellID == 6117, "a buff without a duration is muted for 30 minutes")
	buffs.db.middleClickMute = false
	buffs:OnOptionChanged("middleClickMute")
	assert(first.spellID == 1459 and not next(buffs.cdb.mutedUntil), "disabling mute restores the reminder")
	assert(attributes["*type3"] == nil, "disabling mute restores the original middle click action")
	buffs.db.middleClickMute = true
	buffs.db.targetRange = savedRange
	first.SetAttribute = savedAttribute
	ns.After, ns.NewTimer = savedAfter, savedTimer
	C_Spell.GetSpellDescription, C_UnitAuras.GetAuraDataBySpellName, GetServerTime = savedDescription, savedAura, savedClock

	IsResting = savedResting
	C_Minimap.GetNumTrackingTypes = savedTracking
	UnitExists, UnitIsPlayer, UnitIsUnit, UnitCanAssist, UnitIsDeadOrGhost, UnitIsConnected, UnitName = unpack(saved)
	setuv(evaluate, "FindAura", function() return nil end)
	print("buff power OK")
end)()
;(function()
	local buffs = ns:GetModule("Buffs")
	local update = uv(buffs.OnLogin, "Update")
	local evaluate = uv(uv(update, "EvaluateOwn"), "Evaluate")
	local reminder = { key = "blessing", blessings = true, cast = { 19740, 19742, 20217 } }
	local choices = {}
	local pickSpell = uv(evaluate, "PickSpell")
	local savedClassDB = uv(pickSpell, "classDB")
	setuv(pickSpell, "classDB", choices)

	local savedLevel, savedRole, savedClass, savedTree = UnitLevel, rawget(_G, "UnitGroupRolesAssigned"), UnitClass, ns.TalentTreeOf
	local savedKnown, savedAura = C_SpellBook.IsSpellKnown, C_UnitAuras.GetAuraDataBySpellName
	local savedFindSlot, savedTrace = C_SpellBook.FindSpellBookSlotForSpell, buffs.lastBlessingTrace
	local level, role, tree, targetClass = 9, "NONE", 2, "PALADIN"
	local known = { [19740] = true, [19742] = true, [20217] = true, [19977] = true }
	local auras = {}
	UnitLevel = function() return level end
	UnitGroupRolesAssigned = function() return role end
	UnitClass = function(unit) return nil, unit == "target" and targetClass or "PALADIN" end
	ns.TalentTreeOf = function() return "Protection", nil, tree end
	C_SpellBook.IsSpellKnown = function(id) return known[id] or false end
	C_SpellBook.FindSpellBookSlotForSpell = function() return nil end
	C_UnitAuras.GetAuraDataBySpellName = function(unit, name) return unit == "target" and auras[name] or nil end

	local function targetSpell()
		return select(4, buffs.EvaluateTarget(reminder, 60))
	end
	local function ownSpell()
		return select(4, evaluate(reminder, 60))
	end
	for _, class in ipairs({ "WARRIOR", "ROGUE", "HUNTER", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN", "DRUID" }) do
		targetClass = class
		local fallback = (class == "WARRIOR" or class == "ROGUE") and 19740 or 19742
		for lowLevel = 1, 3 do
			level = lowLevel
			assert(targetSpell() == 19740, class .. ": levels 1 to 3 get rank 1 Might")
		end
		level = 4
		assert(targetSpell() == fallback, class .. ": first level eligible for rank 1 Wisdom")
		level = 9
		assert(targetSpell() == fallback, class .. ": level 9 gets a class-appropriate replacement")
		level = 10
		assert(targetSpell() == 20217, class .. ": level 10 can get Kings")
	end
	targetClass = "MAGE"
	level = 9
	known[19742] = nil
	assert(targetSpell() == 19740, "unknown Wisdom: low-level caster gets Might")
	known[19742] = true
	auras.Spell19742 = { expirationTime = GetTime() + 300, sourceUnit = "party1" }
	assert(targetSpell() == 19740, "Wisdom from another Paladin: low-level caster gets the other blessing")
	auras.Spell19740 = { expirationTime = GetTime() + 300, sourceUnit = "party2" }
	assert(not targetSpell(), "both replacements are active: no duplicate or higher-level blessing")
	auras.Spell19740, auras.Spell19742 = nil, nil

	local setupButton = uv(update, "SetupButton")
	local button, attributes = CreateFrame("CheckButton"), {}
	button.SetAttribute = function(_, key, value) attributes[key] = value end
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == 19742 and attributes.unit == "target", "the target button casts the exact low-level rank")
	level = 1
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == 19740 and attributes.unit == "target", "the other replacement also casts by rank ID")
	level = 10
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == "Spell20217", "regular target still casts by spell name")

	targetClass = "PALADIN"
	level = 9
	auras.Spell25898 = { expirationTime = GetTime() + 30, sourceUnit = "player" }
	assert(targetSpell() == 19742, "expiring Greater Kings on level 9 target: choose an eligible blessing")
	auras.Spell25898 = nil
	assert(ownSpell() == 19742, "own Protection tree: automatic Wisdom when Kings cannot be cast")
	choices.blessingChoice = 20217
	assert(ownSpell() == 19742, "manual Kings also respects the level gate")
	level = 20
	choices.blessingChoice = 0
	assert(ownSpell() == 20217, "own Protection tree: automatic Kings before Might")
	choices.blessingChoice = 19740
	assert(ownSpell() == 19740, "own manual Might is respected")

	known[20217], known[19742], known[19977] = nil, nil, nil
	choices.blessingChoice = 0
	assert(ownSpell() == nil, "automatic Protection skips Might when it is the only known blessing")
	tree = 3
	assert(ownSpell() == 19740, "automatic Retribution can still select Might")
	role = "TANK"
	assert(targetSpell() == nil, "assigned paladin tank does not get automatic Might")
	role = "NONE"
	auras.Spell25780 = { expirationTime = 0 }
	assert(targetSpell() == nil, "Righteous Fury identifies a tank without an assigned role")
	auras.Spell25780 = nil
	assert(targetSpell() == 19740, "other paladin still gets Might as a fallback")

	UnitLevel, UnitGroupRolesAssigned, UnitClass, ns.TalentTreeOf = savedLevel, savedRole, savedClass, savedTree
	C_SpellBook.IsSpellKnown, C_UnitAuras.GetAuraDataBySpellName = savedKnown, savedAura
	C_SpellBook.FindSpellBookSlotForSpell, buffs.lastBlessingTrace = savedFindSlot, savedTrace
	setuv(pickSpell, "classDB", savedClassDB)
	print("blessing eligibility and tank priority OK")
end)()
;(function()
	-- Trainer: train all from the last entry, as far as the money goes; new professions left out.
	local services = ns:GetModule("Services")
	local learnable = uv(uv(services.Apply, "UpdateTrainButton"), "Learnable")
	local trainAll = uv(uv(services.Apply, "CreateTrainButton"), "TrainAll")
	local entries = { { "available", 100 }, { "used", 50 }, { "available", 300, true }, { "available", 200 }, { "unavailable", 10 } }
	GetNumTrainerServices = function() return #entries end
	GetTrainerServiceInfo = function(i) return "x", entries[i][1] end
	GetTrainerServiceCost = function(i) return entries[i][2], entries[i][3] end
	local list, total = learnable()
	assert(#list == 2 and total == 300, "learnable without professions")
	local bought = {}
	BuyTrainerService = function(i) bought[#bought + 1] = i end
	GetMoney = function() return 250 end
	trainAll()
	assert(#bought == 1 and bought[1] == 4, "last first, stops at the money")
	GetMoney = function() return 1000 end
	bought = {}
	trainAll()
	assert(bought[1] == 4 and bought[2] == 1, "all affordable, from the end")
	-- Bank: reagents onto a bank stack with room, the rest stays.
	local deposit = uv(uv(uv(services.Apply, "CreateDepositButton"), "DepositReagents"), "Step")
	local depositOne = uv(deposit, "DepositOne")
	local bags = { [0] = { [1] = { itemID = 2589, stackCount = 15, hyperlink = "item:2589" }, [2] = { itemID = 118, stackCount = 3, hyperlink = "item:118" } },
		[6] = { [1] = { itemID = 2589, stackCount = 10 } } }
	C_Container.GetContainerNumSlots = function(bag) return bags[bag] and 2 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end
	C_Item.GetItemInfo = function(link) return "x", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, link == "item:2589" end
	C_Item.GetItemMaxStackSizeByID = function() return 20 end
	C_Bank = { CanUseBank = function() return true end, FetchPurchasedBankTabIDs = function() return { 6 } end }
	local calls = {}
	C_Container.SplitContainerItem = function(bag, slot, n) calls[#calls + 1] = ("split %d %d %d"):format(bag, slot, n) end
	C_Container.PickupContainerItem = function(bag, slot) calls[#calls + 1] = ("pickup %d %d"):format(bag, slot) end
	GetCursorInfo = function() return nil end
	ns:GetModule("Restock").cdb.items = {} -- the restock test marked linen
	setuv(depositOne, "run", { steps = 0, moved = 0, skip = {} })
	assert(depositOne(), "one move")
	print("  ", table.concat(calls, " | "))
	assert(calls[1] == "split 0 1 10" and calls[2] == "pickup 6 1", "10 linen onto the bank stack of 10; the potion stays")
	-- Shiny Fish Scales (17057) lack the client crafting-reagent flag, but are deposited too unless on the restock list.
	bags = { [0] = { [1] = { itemID = 17057, stackCount = 5, hyperlink = "item:17057" }, [2] = { itemID = 118, stackCount = 3, hyperlink = "item:118" } },
		[6] = { [1] = { itemID = 2589, stackCount = 10 } } }
	calls = {}
	setuv(depositOne, "run", { steps = 0, moved = 0, skip = {} })
	assert(depositOne(), "Shiny Fish Scales deposited despite missing crafting-reagent flag")
	assert(calls[1] == "pickup 0 1" and calls[2] == "pickup 6 2", "Shiny Fish Scales go into free bank slot")
	ns:GetModule("Restock").cdb.items = { [17057] = true }
	calls = {}
	setuv(depositOne, "run", { steps = 0, moved = 0, skip = {} })
	assert(not depositOne(), "Shiny Fish Scales on the restock list stay in the bags")
	assert(#calls == 0, "no move when Shiny Fish Scales are on the restock list")
	ns:GetModule("Restock").cdb.items = {}
	setuv(depositOne, "run", nil)
	print("services OK")
end)()
;(function()
	-- Loot summary: items and money in one line.
	local loot = ns:GetModule("Loot")
	local flush = uv(uv(loot.CHAT_MSG_LOOT, "Touch"), "Flush")
	local frames = uv(uv(flush, "Print"), "frames")
	local out = {}
	local chat = { AddMessage = function(_, text) out[#out + 1] = text end }
	frames.LOOT[chat], frames.MONEY[chat] = true, true
	ChatTypeInfo = { LOOT = { r = 0, g = 1, b = 0 }, MONEY = { r = 1, g = 1, b = 0 } }
	GetMoneyString = function(money) return money .. "c" end
	setuv(flush, "batch", { items = {}, order = {}, count = 6, money = 81, moneySources = {}, moneyOrder = {}, started = 0 })
	loot.db.combineMoney, loot.db.inlineQuality = true, "NONE"
	flush()
	print("  ", out[1])
	assert(#out == 1 and out[1]:find("6") and out[1]:find("81c"), "one line")
	print("loot money OK")
end)()
;(function()
	-- /fp schrift: font object and group of the texts under the mouse
	local fonts = ns:GetModule("Fonts")
	local function fs(text, object, visible)
		return { GetObjectType = function() return "FontString" end, IsVisible = function() return visible end,
			GetText = function() return text end, GetFontObject = function() return object end,
			GetFont = function() return "x", 12 end }
	end
	local tex = { GetObjectType = function() return "Texture" end }
	local frame = { GetRegions = function()
		return tex, fs("|cffff0000Schwert|r", GameTooltipText, true), fs("versteckt", GameTooltipText, false),
			fs("eigen", nil, true)
	end }
	GameTooltipText.GetName = function() return "GameTooltipText" end
	local lines = fonts.InspectLines({ frame, { GetRegions = function() error("restricted") end } })
	assert(#lines == 2, "visible texts only, restricted frame skipped: " .. #lines)
	assert(lines[1]:find("Schwert", 1, true) and not lines[1]:find("|c", 1, true)
		and lines[1]:find("GameTooltipText", 1, true) and lines[1]:find(ns.L.FONTS_GROUP_tooltip, 1, true), lines[1])
	assert(lines[2]:find(ns.L.FONTS_INSPECT_OWN, 1, true), lines[2])
	ns.db.fontInspect = nil
	for _ = 1, 12 do
		fonts.SaveInspect(lines)
	end
	assert(#ns.db.fontInspect == 10 and #ns.db.fontInspect[10] == 4, "keeps last 10 with time and settings")
	assert(ns.db.fontInspect[1][2]:find("tooltip=", 1, true) and ns.db.fontInspect[1][3] == lines[1], ns.db.fontInspect[1][2])
	print("font inspect OK")
end)()
;(function()
	-- Traces open in a window to copy
	local saved, shown = ns.ShowEditWindow, nil
	ns.ShowEditWindow = function(key, _, text) shown = { key, text } end
	local items = ns:GetModule("Items")
	local savedTrace = items.trace
	items.trace = { "1.00 a", "2.00 b" }
	items.PrintTrace()
	assert(shown and shown[1] == "Trace" and shown[2]:find("1.00 a\n2.00 b", 1, true), "bags trace in window")
	shown = nil
	ns:GetModule("Dialog").PrintTrace()
	assert(shown and shown[1] == "Trace", "bubble trace in window")
	assert(type(ns.db.bubbleTrace) == "table", "bubble trace kept in the saved variables")
	-- screen values in the trace say why there is no number
	local measure = ns:GetModule("Dialog").Measure
	local savedSecret = issecretvalue
	issecretvalue = function(value) return value == "secret" end
	assert(measure(true, 412.6) == "412" and measure(true, nil) == ns.L.TRACE_MISSING and measure(false, "boom") == ns.L.TRACE_ERROR
		and measure(true, "secret") == ns.L.TRACE_PROTECTED, "measured values")
	issecretvalue = savedSecret
	items.trace, ns.ShowEditWindow = savedTrace, saved
	print("trace window OK")
end)()
;(function()
	-- Greyed self buffs in combat: a removed aura ends its greying, an unreadable removal ends all
	local vis = ns:GetModule("Visuals")
	local forget = vis.ForgetRemovedAuras
	local function setup()
		local active, ids = { Seal = true, Aura = true }, { [11] = "Seal", [12] = "Aura" }
		for i = 1, 60 do
			local n = debug.getupvalue(forget, i)
			if not n then break end
			if n == "activeAuras" then debug.setupvalue(forget, i, active) end
			if n == "auraIDs" then debug.setupvalue(forget, i, ids) end
		end
		return active, ids
	end
	local active = setup()
	forget({ removedAuraInstanceIDs = { 11 } })
	assert(active.Seal == nil and active.Aura, "used-up seal no longer grey, other aura stays")
	forget({ addedAuras = {} })
	assert(active.Aura, "nothing removed: unchanged")
	active = setup()
	forget(nil)
	assert(next(active) == nil, "unknown change: all greying ends")
	active = setup()
	local savedSecret = issecretvalue
	issecretvalue = function(v) return v == 99 end
	forget({ removedAuraInstanceIDs = { 99 } })
	issecretvalue = savedSecret
	assert(next(active) == nil, "secret removal: all greying ends")
	print("active buff combat OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local savedClass, savedTree, savedSpellBook = UnitClass, ns.TalentTreeOf, C_SpellBook
	local savedAuras, savedSecrets, savedEvents = C_UnitAuras, C_Secrets, C_EventUtils
	local savedName, savedAction, savedMacro = C_Spell.GetSpellName, GetActionInfo, GetMacroSpell
	local savedFrames, savedStance, savedForms = ActionBarButtonEventsFrame.frames, StanceBar, GetNumShapeshiftForms
	local savedFormInfo = GetShapeshiftFormInfo
	local savedOption = visuals.db.paladinRecommendations
	local savedSealOption = visuals.db.paladinSealRecommendation
	local savedColors = visuals.db.actionColors
	local savedCombat, savedTime, savedNewTimer = InCombatLockdown, GetTime, C_Timer.NewTimer
	local inCombat, now, sealTimer = false, 100
	InCombatLockdown = function() return inCombat end
	GetTime = function() return now end
	C_Timer.NewTimer = function(delay, callback)
		sealTimer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
		return sealTimer
	end
	local tree = 1
	local names = {
		[19740] = "Might", [19742] = "Wisdom", [19854] = "Wisdom", [25894] = "Greater Wisdom",
		[20217] = "Kings", [1044] = "Freedom", [465] = "Devotion", [19746] = "Concentration",
		[7294] = "Retribution", [19876] = "Shadow Resistance",
		[20375] = "Seal of Command", [20166] = "Seal of Wisdom", [1311649] = "Seal of Fury",
		[20154] = "Seal of Righteousness", [20164] = "Seal of Justice",
	}
	local known = { [19740] = true, [19742] = true, [20217] = true, [465] = true, [19746] = true, [7294] = true }
	known[20375], known[20166], known[1311649], known[20154] = true, true, true, true
	local spells = { 19854, 19740, 20217, 25894, 20375, 20166, 1311649, 20154 }
	local forms = { 19746, 465, 7294 }
	local function Button(slot)
		local button = CreateFrame("Button")
		button.action = slot
		return button
	end
	local wisdom, might, kings, greater = Button(1), Button(2), Button(3), Button(4)
	local sealCommand, sealWisdom, sealFury, sealRight = Button(5), Button(6), Button(7), Button(8)
	local concentration, devotion, retribution = Button(), Button(), Button()
	ActionBarButtonEventsFrame.frames = { wisdom, might, kings, greater, sealCommand, sealWisdom, sealFury, sealRight }
	StanceBar = { actionButtons = { concentration, devotion, retribution } }
	GetNumShapeshiftForms = function() return #forms end
	GetShapeshiftFormInfo = function(index) return 1, true, true, forms[index] end
	C_Spell.GetSpellName = function(id) return names[id] end
	GetActionInfo = function(slot) return slot == 4 and "macro" or "spell", spells[slot] end
	GetMacroSpell = function(id) return id end
	C_SpellBook = { IsSpellKnown = function(id) return known[id] end, FindSpellBookSlotForSpell = function() end }
	local buffs = {}
	C_UnitAuras = { GetUnitAuras = function() return buffs end }
	C_Secrets = { ShouldAurasBeSecret = function() return false end }
	C_EventUtils = { IsEventValid = function() return true end }
	ns.TalentTreeOf = function() return nil, nil, tree end
	UnitClass = function() return "Paladin", "PALADIN" end
	assert(savedOption and savedSealOption, "paladin recommendations start enabled")
	visuals.db.actionColors = false
	visuals:OnOptionChanged("paladinRecommendations")
	local updateWatch = uv(visuals.OnLogin, "UpdatePaladinWatch")
	local watcher = uv(updateWatch, "paladinWatch")
	local glows = uv(uv(updateWatch, "UpdatePaladinHighlights"), "recommendationGlows")
	local auraWatcher = uv(uv(visuals.OnLogin, "UpdateAuraWatch"), "auraWatcher")
	local function Fire(event, spellID) watcher.scripts.OnEvent(watcher, event, "player", nil, spellID) end
	local function FireAura(event, updateInfo) auraWatcher.scripts.OnEvent(auraWatcher, event, "player", updateInfo) end
	local function Lit(button) return glows[button] and glows[button]:IsShown() end
	assert(Lit(wisdom) and Lit(greater) and Lit(concentration), "Holy highlights missing Wisdom and Concentration independently of action colors")
	assert(not Lit(might) and not Lit(devotion), "only the recommended spell families glow")
	assert(not Lit(sealWisdom), "no seal glow out of combat")
	buffs = { { name = "Seal", auraInstanceID = 1 } }
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(concentration), "an unrelated buff does not hide either recommendation")
	buffs[2] = { name = "Kings", auraInstanceID = 2, sourceUnit = "party1" }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and not Lit(greater) and Lit(concentration), "a different blessing from a party member hides only the blessing")
	buffs = { { name = "Shadow Resistance", auraInstanceID = 3, sourceUnit = "party1" } }
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(greater) and not Lit(concentration), "an active resistance aura hides only the aura")
	buffs[2] = { name = "Greater Wisdom", auraInstanceID = 4 }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and not Lit(greater) and not Lit(concentration), "both categories are covered by a greater blessing and an aura")
	buffs = { { name = "Freedom", auraInstanceID = 5 } }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and Lit(concentration), "a utility blessing counts while active")
	buffs = {}
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(concentration), "both recommendations return after the buffs end")
	C_Secrets = { ShouldAurasBeSecret = function() return true end }
	FireAura("PLAYER_REGEN_DISABLED")
	assert(not Lit(wisdom) and not Lit(concentration), "recommendations are hidden while buff data is protected")
	tree = 2
	Fire("TRAIT_CONFIG_UPDATED")
	C_Secrets = { ShouldAurasBeSecret = function() return false end }
	FireAura("PLAYER_REGEN_ENABLED")
	assert(Lit(kings) and Lit(devotion) and not Lit(wisdom) and not Lit(concentration), "the new talent tree is shown after buff data becomes readable")
	tree, known[7294] = 3, nil
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(might) and Lit(devotion) and not Lit(kings), "Retribution falls back to Devotion until its aura is learned")
	known[7294] = true
	Fire("SPELLS_CHANGED")
	assert(Lit(retribution) and not Lit(devotion), "newly learned aura replaces the fallback")
	might.action, wisdom.action = 1, 2
	Fire("ACTIONBAR_PAGE_CHANGED")
	assert(Lit(wisdom) and not Lit(might), "the glow follows the spell to the new button")
	buffs = { { name = "Seal of Justice", auraInstanceID = 6, expirationTime = 115 } }
	FireAura("UNIT_AURA")
	inCombat = true
	C_Secrets.ShouldAurasBeSecret = function() return true end
	FireAura("PLAYER_REGEN_DISABLED")
	Fire("PLAYER_REGEN_DISABLED")
	assert(not Lit(sealCommand) and sealTimer.delay == 15, "precombat seal remains active for its actual remaining time")
	FireAura("UNIT_AURA", { removedAuraInstanceIDs = { 6 } })
	assert(Lit(sealCommand) and sealTimer.cancelled, "an early seal removal restores the glow in combat")
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20164)
	assert(not Lit(sealCommand) and sealTimer.delay == 30, "casting any seal removes the glow even with hidden auras")
	local previousTimer = sealTimer
	now = 110
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20375)
	assert(previousTimer.cancelled and sealTimer.delay == 30, "refreshing or switching seals replaces the expiry timer")
	previousTimer = sealTimer
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20271) -- Judgement keeps the seal in Forever.
	assert(sealTimer == previousTimer and not Lit(sealCommand), "Judgement neither removes the seal nor restarts its timer")
	now = 140
	sealTimer.callback()
	assert(Lit(sealCommand) and not Lit(sealWisdom) and not Lit(sealFury), "expiry shows the Retribution recommendation")
	known[20375] = nil
	Fire("SPELLS_CHANGED")
	assert(Lit(sealRight) and not Lit(sealCommand), "Retribution falls back to Righteousness before learning Command")
	tree = 2
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(sealFury) and not Lit(sealRight), "Protection recommends Fury")
	visuals.db.paladinSealRecommendation = false
	visuals:OnOptionChanged("paladinSealRecommendation")
	assert(not Lit(sealFury), "the seal option clears the seal glow")
	inCombat = false
	C_Secrets.ShouldAurasBeSecret = function() return false end
	buffs = {}
	FireAura("PLAYER_REGEN_ENABLED")
	visuals.db.paladinSealRecommendation = savedSealOption
	visuals:OnOptionChanged("paladinSealRecommendation")
	assert(not Lit(sealFury), "the seal glow stays hidden after combat")
	tree, inCombat = 1, true
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(sealWisdom) and not Lit(sealFury), "Holy recommends Wisdom")
	inCombat = false
	Fire("PLAYER_REGEN_ENABLED")
	assert(not Lit(sealWisdom), "leaving combat immediately clears a missing seal glow")
	visuals.db.paladinSealRecommendation = false
	visuals.db.paladinRecommendations = false
	visuals:OnOptionChanged("paladinRecommendations")
	assert(not Lit(wisdom) and not Lit(retribution), "turning the option off clears all glows")
	visuals.db.paladinRecommendations = savedOption
	visuals.db.paladinSealRecommendation = savedSealOption
	visuals.db.actionColors = savedColors
	UnitClass, ns.TalentTreeOf, C_SpellBook = savedClass, savedTree, savedSpellBook
	C_UnitAuras, C_Secrets, C_EventUtils = savedAuras, savedSecrets, savedEvents
	C_Spell.GetSpellName, GetActionInfo, GetMacroSpell = savedName, savedAction, savedMacro
	ActionBarButtonEventsFrame.frames, StanceBar, GetNumShapeshiftForms = savedFrames, savedStance, savedForms
	GetShapeshiftFormInfo = savedFormInfo
	InCombatLockdown, GetTime, C_Timer.NewTimer = savedCombat, savedTime, savedNewTimer
	print("paladin action bar recommendations OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local oldClass, oldTree, oldCombat = UnitClass, ns.TalentTreeOf, InCombatLockdown
	local oldSpellbook, oldAuras, oldEvents = C_SpellBook, C_UnitAuras, C_EventUtils
	local oldName, oldAction, oldUsable = C_Spell.GetSpellName, GetActionInfo, C_ActionBar.IsUsableAction
	local oldButtons, oldOption = ActionBarButtonEventsFrame.frames, visuals.db.combatBuffRecommendation
	local class, tree, combat, protected = "SHAMAN", 3, false, false
	local ids, auras, usable = {}, {}, {}
	local spells = { 324, 408510, 6774, 6673 }
	local names = { [324] = "Lightning Shield", [408510] = "Water Shield", [5171] = "Slice and Dice",
		[6774] = "Slice and Dice", [6673] = "Battle Shout" }
	local known = { [324] = true, [409941] = true, [5171] = true, [6673] = true }
	local buttons = {}
	for slot = 1, #spells do
		buttons[slot] = CreateFrame("Button")
		buttons[slot].action = slot
	end
	ActionBarButtonEventsFrame.frames = buttons
	UnitClass = function() return class, class end
	ns.TalentTreeOf = function() return nil, nil, tree end
	InCombatLockdown = function() return combat end
	C_Spell.GetSpellName = function(id) return names[id] end
	GetActionInfo = function(slot) return "spell", spells[slot] end
	C_ActionBar.IsUsableAction = function(slot) return usable[slot] == true end
	C_SpellBook = { IsSpellKnown = function(id) return known[id] end, FindSpellBookSlotForSpell = function() end }
	C_EventUtils = { IsEventValid = function() return true end }
	C_UnitAuras = {
		GetAuraDataBySpellName = function(_, name)
			assert(not protected, "protected aura lookup")
			return auras[name]
		end,
		GetUnitAuraInstanceIDs = function() return ids end,
	}
	local updateWatch = uv(visuals.OnLogin, "UpdateCombatBuffWatch")
	local glows = uv(uv(updateWatch, "UpdateCombatBuffHighlights"), "recommendationGlows")
	local function Lit(slot) return glows[buttons[slot]] and glows[buttons[slot]]:IsShown() end
	local function Fire(event, updateInfo, spellID)
		local watcher = uv(updateWatch, "combatBuffWatch")
		watcher.scripts.OnEvent(watcher, event, "player", updateInfo, spellID)
	end
	assert(oldOption == false, "optional combat buffs start off")
	visuals.db.combatBuffRecommendation = true
	auras["Lightning Shield"] = { auraInstanceID = 10 }
	ids, usable[1], usable[2] = { 10 }, true, true
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(1) and not Lit(2), "combat buffs are hidden outside combat")
	combat, protected = true, true
	Fire("PLAYER_REGEN_DISABLED")
	assert(not Lit(2), "a different shield seen before combat still counts")
	ids = {}
	Fire("UNIT_AURA")
	assert(Lit(2) and not Lit(1), "an exhausted shield detected by instance ID recommends Water Shield for Restoration")
	Fire("UNIT_SPELLCAST_SUCCEEDED", nil, 408510)
	assert(not Lit(2), "an observed Water Shield cast clears the recommendation with protected auras")
	protected, auras = false, {}
	tree = 2
	Fire("TRAIT_CONFIG_UPDATED")
	assert(Lit(1) and not Lit(2), "Enhancement recommends Lightning Shield")
	class = "ROGUE"
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(1) and not Lit(3), "Slice and Dice does not glow when unusable")
	usable[3] = true
	Fire("ACTION_USABLE_CHANGED")
	assert(Lit(3), "when resources allow it the higher rank of Slice and Dice glows")
	auras["Slice and Dice"] = { auraInstanceID = 11 }
	Fire("UNIT_AURA")
	assert(not Lit(3), "active Slice and Dice clears its glow")
	class, usable[4] = "WARRIOR", true
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(Lit(4), "Warrior recommends Battle Shout")
	auras["Battle Shout"] = { auraInstanceID = 12, sourceUnit = "party1" }
	Fire("UNIT_AURA")
	assert(not Lit(4), "a group member's Battle Shout counts")
	auras["Battle Shout"] = nil
	Fire("UNIT_AURA")
	assert(Lit(4), "the shout glows again when it falls off")
	combat = false
	Fire("PLAYER_REGEN_ENABLED")
	assert(not Lit(4), "leaving combat clears the shout glow")
	combat = true
	Fire("PLAYER_REGEN_DISABLED")
	assert(Lit(4), "the glow is rebuilt at the next pull")
	visuals.db.combatBuffRecommendation = false
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(4), "disabling the option clears the glow")
	UnitClass, ns.TalentTreeOf, InCombatLockdown = oldClass, oldTree, oldCombat
	C_SpellBook, C_UnitAuras, C_EventUtils = oldSpellbook, oldAuras, oldEvents
	C_Spell.GetSpellName, GetActionInfo, C_ActionBar.IsUsableAction = oldName, oldAction, oldUsable
	ActionBarButtonEventsFrame.frames, visuals.db.combatBuffRecommendation = oldButtons, oldOption
	print("optional combat buff recommendations OK")
end)()
;(function()
	-- Casts left: mana divided by the spell's cost.
	local vis = ns:GetModule("Visuals")
	local update = uv(uv(vis.OnLogin, "UpdateCastWatch"), "UpdateAllCasts")
	local casts = uv(update, "UpdateCasts")
	vis.db.castsLeft = true
	GetActionInfo = function() return "spell", 403 end
	C_Spell.GetSpellPowerCost = function() return { { type = 0, cost = 25, minCost = 25 } } end
	Enum.PowerType = { Mana = 0 }
	UnitPower = function() return 110 end
	local shown
	local button = CreateFrame("Button")
	button.action = 1
	button.CreateFontString = function() local f = CreateFrame("FontString") f.SetText = function(_, t) shown = t end return f end
	casts(button)
	assert(shown == 4, "110 mana / 25 = 4 casts, got " .. tostring(shown))
	print("casts left OK")
end)()
;(function()
	-- Shared panel look: title, small close button, Escape.
	UISpecialFrames = {}
	local panel = ns.CreatePanel("ForeverPlusTestPanel", { close = true, movable = true })
	assert(panel.Title and panel.Close and not panel:IsShown(), "title, close, hidden")
	local listed
	for _, name in ipairs(UISpecialFrames) do listed = listed or name == "ForeverPlusTestPanel" end
	assert(listed, "Escape closes it")
	panel:Show()
	panel.Close.scripts.OnClick()
	assert(not panel:IsShown(), "close button hides")
	local quiet = ns.CreatePanel("ForeverPlusQuietPanel", { escape = false })
	listed = false
	for _, name in ipairs(UISpecialFrames) do listed = listed or name == "ForeverPlusQuietPanel" end
	assert(not listed and not rawget(quiet, "Close"), "tooltip-like panel")
	print("panel OK")
end)()
;(function()
	-- Local quest capture is opt-in and deduplicates unchanged snapshots.
	local capture = ns:GetModule("DataCapture")
	C_QuestLog.GetTitleForQuestID = function() return "Koboldlager" end
	C_QuestLog.GetQuestObjectives = function() return { { text = "Kobolde: 0/10", type = "monster", finished = false } } end
	capture.Clear()
	capture.SetEnabled(true)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	local rows = ForeverPlusDB.observations["33"]
	assert(rows and #rows == 1 and rows[1].title == "Koboldlager", "visible quest snapshot captured once")
	assert(rows[1].method == "QUEST_ACCEPTED" and rows[1].source == "client-visible quest log", "observation provenance")
	capture.SetEnabled(false)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	assert(#rows == 1, "disabled capture records nothing")
	capture.Clear()
	print("data capture OK")
end)()
-- Quest starts on the map: level gate, prerequisites, active quests
;(function()
	local available
	for _, source in ipairs(uv(uv(ns.MapSymbols.Count, "Collect"), "sources")) do
		local ok, found = pcall(uv, source, "QuestStartAvailable")
		if ok and found then available = found end
	end
	assert(available, "quest start source found")
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 7 end
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 8 and 1 or nil end
	UnitLevel = function() return 20 end
	UnitRace = function() return "Human", "Human", 1 end
	UnitClass = function() return "Mage", "MAGE", 8 end
	local lib = { Enum = {} }
	local function quest(fields) fields.id = fields.id or 1 return { data = fields } end
	assert(available(quest({ gate = 20 * 100000000000 }), lib), "level reached")
	assert(not available(quest({ gate = 30 * 100000000000 }), lib), "level too low")
	assert(not available(quest({ id = 7 }), lib), "completed quests are hidden")
	assert(not available(quest({ id = 8 }), lib), "active quests are hidden")
	assert(available(quest({ all = { 7 } }), lib) and not available(quest({ all = { 9 } }), lib), "all prerequisites needed")
	assert(not available(quest({ any = { 9 } }), lib) and available(quest({ any = { 9, 7 } }), lib), "one of the alternatives")
	assert(not available(quest({ excluded = { 8 } }), lib), "an active exclusive quest hides it")
	assert(not available(quest({ parent = 5 }), lib), "needs the parent quest in the log")
	print("quest starts OK")
end)()
-- Zeppelin and boat rides
;(function()
	local T = ns:GetModule("Transports")
	local function run(samples)
		local state, rides = {}, {}
		for _, sample in ipairs(samples) do
			local ride = T.Step(state, sample)
			if ride then rides[#rides + 1] = ride end
		end
		return rides
	end
	local function series(t0, count, make)
		local list = {}
		for i = 0, count - 1 do
			local sample = make(i)
			sample.time = t0 + i * 0.5
			list[#list + 1] = sample
		end
		return list
	end
	local function append(a, b) for _, v in ipairs(b) do a[#a + 1] = v end return a end
	local still = function() return { mapID = 1411, x = 0.5, y = 0.5, speed = 0 } end
	-- 60 s on a zeppelin: moves along while standing still, then stands still again
	local samples = series(0, 6, still)
	append(samples, series(3, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * (i + 1), y = 0.5, speed = 0 } end))
	append(samples, series(63, 8, function() return { mapID = 1411, x = 0.86, y = 0.5, speed = 0 } end))
	local rides = run(samples)
	assert(#rides == 1, "one ride recorded")
	assert(math.abs(rides[1].seconds - 60) <= 2, "duration about 60 s: " .. rides[1].seconds)
	assert(rides[1].from.x == 0.5 and rides[1].to.x > 0.85, "dock and arrival")
	assert(#rides[1].path > 5, "path sampled")
	-- walking, a short lift, and a taxi do not count
	local walking = series(0, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * i, y = 0.5, speed = 7 } end)
	assert(#run(walking) == 0, "own movement is no ride")
	local lift = series(0, 6, still)
	append(lift, series(3, 20, function(i) return { mapID = 1411, x = 0.5, y = 0.5 + 0.003 * (i + 1), speed = 0 } end))
	append(lift, series(13, 8, function() return { mapID = 1411, x = 0.5, y = 0.56, speed = 0 } end))
	assert(#run(lift) == 0, "a ride under 20 s is no transport")
	local taxi = series(0, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * i, y = 0.5, speed = 0, blocked = true } end)
	assert(#run(taxi) == 0, "taxi flights are excluded")
	-- a loading screen in the middle (boat between continents)
	local boat = series(0, 6, still)
	append(boat, series(3, 40, function(i) return { mapID = 1437, x = 0.5 + 0.003 * (i + 1), y = 0.5, speed = 0 } end))
	append(boat, series(23, 60, function(i) return { mapID = 1438, x = 0.2 + 0.003 * i, y = 0.4, speed = 0 } end))
	append(boat, series(53, 8, function() return { mapID = 1438, x = 0.38, y = 0.4, speed = 0 } end))
	rides = run(boat)
	assert(#rides == 1 and rides[1].crossed and rides[1].to.mapID == 1438, "crossing the map is one ride")
	-- docks: rides close together share a dock, routes collect the durations
	local docks = T.BuildDocks({ { 1411, 0.50, 0.50, 1420, 0.60, 0.40, 240 }, { 1411, 0.505, 0.5, 1420, 0.6, 0.4, 250 },
		{ 1411, 0.50, 0.50, 1437, 0.3, 0.3, 120 }, { "x" } })
	assert(#docks[1411] == 1 and #docks[1411][1].routes == 2, "one dock, two destinations")
	assert(#docks[1411][1].routes[1].seconds == 2, "the same route twice")
	local pathRides = T.PathRides(ns.TransportPaths)
	assert(#pathRides == 25, "shipped ship, zeppelin and airship legs")
	pathRides[#pathRides + 1] = { 1429, 0.055, 0.31, 1439, 0.31, 0.41, 123 }
	docks = T.BuildDocks(pathRides)
	local stormwind = docks[1453][1]
	assert(stormwind.kind == "ship" and #stormwind.routes == 1 and stormwind.routes[1].seconds[1] == 123 and not docks[1429],
		"recordings on the surrounding zone match the same harbor")
	local wetlands = docks[1437][2].routes[1]
	assert(wetlands.to.mapID == 1424 and wetlands.following[1][2][1] == 1439 and #wetlands.seconds == 0,
		"Menethil departs for Southshore, then Auberdine")
	local source
	for _, provider in ipairs(uv(uv(ns.MapSymbols.Count, "Collect"), "sources")) do
		if uv(provider, "DockTooltip") then source = provider break end
	end
	assert(source, "transport map source registered")
	local savedInfo, savedArea, savedDocks = C_Map.GetMapInfo, C_Map.GetAreaInfo, T.db.docks
	C_Map.GetMapInfo = function(id)
		return { mapID = id, mapType = id == 947 and 1 or (id == 1414 or id == 1415) and 2 or 3, name = tostring(id) }
	end
	local names = { [150] = "Hafen von Menethil", [271] = "Süderstade", [442] = "Auberdine" }
	C_Map.GetAreaInfo = function(id) return names[id] end
	T.db.docks, T.docks = true, nil
	local function MapDocks(mapID)
		local symbols = {}
		source(mapID, function(x, y, symbol)
			assert(x >= 0 and x <= 1 and y >= 0 and y <= 1 and not symbol.atlas, "transport uses its own texture")
			symbols[#symbols + 1] = symbol
		end)
		return symbols
	end
	local zone = MapDocks(1437)
	assert(#zone == 2 and zone[2].data.kind == "ship", "both piers show on the Wetlands zone map")
	local lines = {}
	zone[2].tooltip({ AddLine = function(_, line) lines[#lines + 1] = line end }, zone[2])
	assert(lines[1] == ns.L.TRANSPORTS_SHIP and lines[2] == names[150]
		and lines[3] == ns.L.TRANSPORTS_TO_KNOWN:format(names[271])
		and lines[4] == ns.L.TRANSPORTS_THEN:format(names[442]), "tooltip shows the type and the stops in order")
	local capital, zeppelins, island = MapDocks(1453), MapDocks(1411), MapDocks(2521)
	assert(#capital == 1 and #MapDocks(1429) == 1, "the harbor is on both city and zone maps")
	assert(#zeppelins == 1 and #zeppelins[1].routes == 2 and zeppelins[1].texture ~= capital[1].texture,
		"the Zeppelin tower shares its destinations and has a different icon")
	assert(#island == 2 and #MapDocks(1414) > 0 and #MapDocks(947) > 0, "island, continent and world map")
	local menethil
	for _, symbol in ipairs(MapDocks(1415)) do
		if symbol.data.area == 150 then menethil = symbol end
	end
	assert(menethil and #menethil.routes == 2, "overview groups both Menethil piers and lists both departures")
	T.db.docks = false
	assert(#MapDocks(1437) == 0, "transport filter hides docks")
	C_Map.GetMapInfo, C_Map.GetAreaInfo, T.db.docks, T.docks = savedInfo, savedArea, savedDocks, nil
	local text = T.ExportText({ { 1411, 0.5, 0.5, 1420, 0.6, 0.4, 240 } })
	assert(text:find("{ 1411, 0.5000, 0.5000, 1420, 0.6000, 0.4000, 240 },", 1, true), "export line")
	print("transports OK")
end)()

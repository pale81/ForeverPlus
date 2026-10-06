-- Buff reminder: clickable action-button style icons for missing class buffs.
-- Talent dependent buffs appear automatically once the spell is known; groups
-- with several options (armors, aspects, blessings, …) let the player choose.
local _, ns = ...
local L = ns.L

local Buffs = ns:NewModule("Buffs", {
	title = L.BUFFS_TITLE,
	order = 8,
	defaults = {
		enabled = true,
		direction = "RIGHT",
		scale = 0.8,
		threshold = 1,
		restingZones = false,
		expiringAlpha = 0.3,
		wheelCast = false,
		classes = {},
	},
})

local MAX_BUTTONS = 8
local SPACING = 4
local UPDATE_DELAY = 0.1

-- auras: spell IDs whose buff satisfies the reminder.
-- cast: spells offered for casting (first known one when set to automatic).
-- weapon: Enum.WeaponSlot checked for a temporary enchant instead of an aura.
-- items: { [label] = { itemIDs high to low rank } } for rogue poisons.
local REMINDERS = {
	MAGE = {
		{ key = "intellect", auras = { 1459, 23028 }, cast = { 1459, 23028 } },
		{ key = "armor", auras = { 6117, 7302, 168 }, cast = { 6117, 7302, 168 } },
	},
	PRIEST = {
		{ key = "fortitude", auras = { 1243, 21562 }, cast = { 1243, 21562 } },
		{ key = "innerFire", auras = { 588 }, cast = { 588 } },
		{ key = "spirit", auras = { 14752, 27681 }, cast = { 14752, 27681 } },
		{ key = "shadowform", auras = { 15473 }, cast = { 15473 } },
		{ key = "shadowProtection", auras = { 976, 27683 }, cast = { 976, 27683 }, default = false },
	},
	DRUID = {
		{ key = "wild", auras = { 1126, 21849 }, cast = { 1126, 21849 } },
		{ key = "thorns", auras = { 467 }, cast = { 467 } },
		{ key = "clarity", auras = { 16864 }, cast = { 16864 } },
	},
	PALADIN = {
		{ key = "blessing", auras = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 },
			cast = { 19740, 19742, 20217, 1038, 19977, 20911 } },
		{ key = "aura", auras = { 465, 7294, 19746, 19876, 19888, 19891, 20218 },
			cast = { 465, 7294, 19746, 20218, 19876, 19888, 19891 } },
		{ key = "righteousFury", auras = { 25780 }, cast = { 25780 }, default = false },
	},
	WARLOCK = {
		{ key = "armor", auras = { 706, 687 }, cast = { 706, 687 } },
		{ key = "soulLink", auras = { 19028 }, cast = { 19028 } },
	},
	HUNTER = {
		{ key = "aspect", auras = { 13165, 13163, 5118, 13159, 20043, 13161 }, cast = { 13165, 13163, 5118, 13159, 20043, 13161 } },
		{ key = "trueshot", auras = { 19506 }, cast = { 19506 } },
	},
	SHAMAN = {
		{ key = "shield", auras = { 324 }, cast = { 324 } },
		{ key = "weapon", weapon = "MainHand", cast = { 8232, 8024, 8017, 8033 } },
	},
	ROGUE = {
		{ key = "poisonMain", weapon = "MainHand", slot = INVSLOT_MAINHAND, items = "poisons" },
		{ key = "poisonOff", weapon = "OffHand", slot = INVSLOT_OFFHAND, items = "poisons" },
	},
	WARRIOR = {
		{ key = "battleShout", auras = { 6673 }, cast = { 6673 }, default = false },
	},
}

local POISONS = {
	{ "instant", { 8928, 8927, 8926, 6950, 6949, 6947 } },
	{ "deadly", { 20844, 8985, 8984, 2893, 2892 } },
	{ "wound", { 10922, 10921, 10920, 10918 } },
	{ "crippling", { 3776, 3775 } },
	{ "mindNumbing", { 9186, 6951, 5237 } },
}

local playerClass
local reminders = {}
local classDB

local bar, placeholder, wheelHandler
local buttons = {}
local updatePending, thresholdTimer

---------------------------------------------------------------------------
-- Spell / item helpers
---------------------------------------------------------------------------
local function SpellName(spellID)
	return C_Spell.GetSpellName(spellID)
end

local function IsKnown(spellID)
	if C_SpellBook.IsSpellKnown(spellID) then
		return true
	end
	local name = SpellName(spellID)
	return name and C_SpellBook.FindSpellBookSlotForSpell(name) ~= nil
end

-- Returns the remaining time (0 = permanent) of the first matching buff, or nil.
local function FindAura(spellIDs)
	for _, spellID in ipairs(spellIDs) do
		local name = SpellName(spellID)
		local aura = name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
		if aura and not (issecretvalue and issecretvalue(aura.expirationTime)) then
			if aura.expirationTime == 0 then
				return 0
			end
			return aura.expirationTime - GetTime()
		end
	end
end

local function WeaponEnchantTime(weapon)
	local enchants = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot[weapon])
	for _, enchant in pairs(enchants or {}) do
		if enchant.hasEnchant then
			return (enchant.timeLeft or 0) / 1000
		end
	end
end

local function HasWeapon(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then
		return false
	end
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	return classID == Enum.ItemClass.Weapon
end

local function ChoiceKey(reminder)
	return reminder.key .. "Choice"
end

local function PickSpell(reminder)
	local choice = classDB[ChoiceKey(reminder)]
	if choice and choice ~= 0 and IsKnown(choice) then
		return choice
	end
	for _, spellID in ipairs(reminder.cast) do
		if IsKnown(spellID) then
			return spellID
		end
	end
end

local function PickPoison(reminder)
	local choice = classDB[ChoiceKey(reminder)]
	for _, poison in ipairs(POISONS) do
		if not choice or choice == "auto" or choice == poison[1] then
			for _, itemID in ipairs(poison[2]) do
				if C_Item.GetItemCount(itemID) > 0 then
					return itemID
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.spellID then
		GameTooltip:SetSpellByID(self.spellID)
	elseif self.itemID then
		GameTooltip:SetItemByID(self.itemID)
	end
	GameTooltip:Show()
end

local function CreateButton(index)
	local button = CreateFrame("CheckButton", "ForeverPlusBuffButton" .. index, bar, "ActionButtonTemplate, SecureActionButtonTemplate")
	-- Act on press so the mouse wheel binding (which has no release) works too.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:HookScript("PostClick", function(self)
		self:SetChecked(false)
	end)
	button:SetScript("OnEnter", ButtonOnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	if button.HotKey then
		button.HotKey:SetText("")
	end
	-- Same yellow/white star glow as Blizzard's spell alerts (bug report button),
	-- created per button instead of going through the shared alert manager.
	local alert = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
	local width, height = button:GetSize()
	alert:SetSize(width * 1.4, height * 1.4)
	alert:SetPoint("CENTER")
	alert.animationPlaying = true -- restart the loop after the bar was hidden in combat
	button.Alert = alert
	button:Hide()
	buttons[index] = button
	return button
end

local OFFSETS = {
	RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 },
}

local function LayoutButtons()
	local offset = OFFSETS[Buffs.db.direction] or OFFSETS.RIGHT
	for index, button in ipairs(buttons) do
		local size = button:GetWidth() + SPACING
		button:ClearAllPoints()
		button:SetPoint("CENTER", bar, "CENTER", offset[1] * size * (index - 1), offset[2] * size * (index - 1))
	end
end

local function SetupButton(button, reminder)
	button.spellID, button.itemID = nil, nil
	if reminder.items then
		local itemID = PickPoison(reminder)
		if not itemID then
			return false
		end
		button:SetAttribute("type", "item")
		button:SetAttribute("item", "item:" .. itemID)
		button:SetAttribute("target-slot", reminder.slot)
		button:SetAttribute("spell", nil)
		button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
		button.itemID = itemID
	else
		local spellID = PickSpell(reminder)
		if not spellID then
			return false
		end
		button:SetAttribute("type", "spell")
		button:SetAttribute("spell", SpellName(spellID))
		button:SetAttribute("item", nil)
		button:SetAttribute("target-slot", nil)
		button:SetAttribute("unit", "player")
		button.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
		button.spellID = spellID
	end
	return true
end

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
local function IsEnabled(reminder)
	local value = classDB[reminder.key]
	if value == nil then
		return reminder.default ~= false
	end
	return value
end

-- Returns shown (bool), seconds until it should be re-checked and whether
-- the buff is only about to expire (not missing yet).
local function Evaluate(reminder, threshold)
	local remaining
	if reminder.weapon then
		if reminder.slot and not HasWeapon(reminder.slot) then
			return false
		end
		if reminder.weapon == "MainHand" and not HasWeapon(INVSLOT_MAINHAND) then
			return false
		end
		remaining = WeaponEnchantTime(reminder.weapon)
	else
		local spellID = PickSpell(reminder)
		if not spellID then
			return false
		end
		remaining = FindAura(reminder.auras)
	end
	if not remaining then
		return true
	end
	if remaining == 0 then
		return false
	end
	if remaining <= threshold then
		return true, nil, true
	end
	return false, remaining - threshold
end

local function Update()
	updatePending = false
	if InCombatLockdown() or not bar then
		return
	end
	if thresholdTimer then
		thresholdTimer:Cancel()
		thresholdTimer = nil
	end

	local count = 0
	local nextCheck
	-- In rest areas (inns, cities) only when wanted.
	local resting = IsResting() and not Buffs.db.restingZones
	if Buffs.db.enabled and not resting and not UnitIsDeadOrGhost("player") then
		local threshold = Buffs.db.threshold * 60
		for _, reminder in ipairs(reminders) do
			if IsEnabled(reminder) and count < MAX_BUTTONS then
				local missing, recheck, expiring = Evaluate(reminder, threshold)
				if missing then
					local button = buttons[count + 1] or CreateButton(count + 1)
					if SetupButton(button, reminder) then
						count = count + 1
						-- Buffs about to expire are shown faded, missing ones fully.
						button:SetAlpha(expiring and Buffs.db.expiringAlpha or 1)
						button:Show()
						if not button.Alert:IsShown() then
							button.Alert:Show()
							button.Alert.ProcStartAnim:Play()
						end
					end
				elseif recheck then
					nextCheck = nextCheck and min(nextCheck, recheck) or recheck
				end
			end
		end
	end
	for index = count + 1, #buttons do
		local button = buttons[index]
		button:Hide()
		button.Alert.ProcStartAnim:Stop()
		button.Alert:Hide()
	end
	LayoutButtons()
	placeholder:SetShown(ns:IsEditModeActive() and count == 0)

	-- The plain mouse wheel casts the first missing buff while a reminder is
	-- shown (camera zoom pauses meanwhile; Shift + wheel keeps its binding).
	ClearOverrideBindings(wheelHandler)
	if Buffs.db.wheelCast and count > 0 then
		SetOverrideBindingClick(wheelHandler, true, "MOUSEWHEELUP", buttons[1]:GetName())
		SetOverrideBindingClick(wheelHandler, true, "MOUSEWHEELDOWN", buttons[1]:GetName())
	end

	if nextCheck then
		thresholdTimer = C_Timer.NewTimer(nextCheck + 0.5, function()
			thresholdTimer = nil
			Update()
		end)
	end
end

local function RequestUpdate()
	if not updatePending then
		updatePending = true
		C_Timer.After(UPDATE_DELAY, Update)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function CreateBar()
	bar = CreateFrame("Frame", "ForeverPlusBuffBar", UIParent)
	bar:SetSize(45, 45)
	bar:SetScale(Buffs.db.scale)
	bar:SetClampedToScreen(true)
	RegisterStateDriver(bar, "visibility", "[combat] hide; show")

	-- Secure handler drops the wheel bindings the moment combat starts.
	wheelHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
	wheelHandler:SetAttribute("_onstate-combat", [=[
		if newstate == "1" then
			self:ClearBindings()
		end
	]=])
	RegisterStateDriver(wheelHandler, "combat", "[combat] 1; 0")

	placeholder = bar:CreateTexture(nil, "ARTWORK")
	placeholder:SetAllPoints()
	placeholder:SetTexture(134400) -- question mark icon
	placeholder:Hide()

	ns:RegisterEditFrame(bar, "BuffBar", L.BUFFS_TITLE, { "CENTER", UIParent, "CENTER", 0, -120 }, function()
		Update()
	end)

	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_UNGHOST")
	events:RegisterEvent("PLAYER_ALIVE")
	events:RegisterEvent("PLAYER_UPDATE_RESTING")
	if playerClass == "ROGUE" then
		events:RegisterEvent("BAG_UPDATE_DELAYED")
	end
	events:SetScript("OnEvent", RequestUpdate)
end

function Buffs:OnInitialize()
	playerClass = select(2, UnitClass("player"))
	reminders = REMINDERS[playerClass] or {}
	self.db.classes[playerClass] = self.db.classes[playerClass] or {}
	classDB = self.db.classes[playerClass]
end

function Buffs:OnLogin()
	if #reminders == 0 then
		return
	end
	CreateBar()
	Update()
end

function Buffs:OnOptionChanged(key)
	if not bar then
		return
	end
	ns.RunOutOfCombat(function()
		if key == "scale" then
			bar:SetScale(self.db.scale)
		end
		Update()
	end)
end

---------------------------------------------------------------------------
-- Options (built for the current class)
---------------------------------------------------------------------------
local function SpellChoices(reminder)
	return function()
		local values = { { 0, L.BUFFS_AUTO } }
		for _, spellID in ipairs(reminder.cast) do
			-- Spells the client does not have (no name) are left out.
			local name = SpellName(spellID)
			if name then
				values[#values + 1] = { spellID, name }
			end
		end
		return values
	end
end

local function PoisonChoices()
	local values = { { "auto", L.BUFFS_AUTO } }
	for _, poison in ipairs(POISONS) do
		local name = C_Item.GetItemNameByID(poison[2][#poison[2]])
		values[#values + 1] = { poison[1], name or L["BUFFS_POISON_" .. poison[1]] }
	end
	return values
end

function Buffs:options()
	local options = {
		{ key = "enabled", type = "toggle", name = L.BUFFS_ENABLE, desc = L.BUFFS_ENABLE_DESC },
		{ key = "direction", type = "dropdown", name = L.BUFFS_DIRECTION, parent = "enabled", values = {
			{ "RIGHT", L.DIRECTION_RIGHT }, { "LEFT", L.DIRECTION_LEFT }, { "UP", L.DIRECTION_UP }, { "DOWN", L.DIRECTION_DOWN },
		} },
		{ key = "scale", type = "slider", name = L.BUFFS_SCALE, parent = "enabled", min = 0.5, max = 1.5, step = 0.05,
			format = function(v) return ("%d%%"):format(v * 100 + 0.5) end },
		{ key = "wheelCast", type = "toggle", name = L.BUFFS_WHEEL, desc = L.BUFFS_WHEEL_DESC, parent = "enabled" },
		{ key = "restingZones", type = "toggle", name = L.BUFFS_RESTING, desc = L.BUFFS_RESTING_DESC, parent = "enabled" },
		{ key = "threshold", type = "slider", name = L.BUFFS_THRESHOLD, desc = L.BUFFS_THRESHOLD_DESC, parent = "enabled",
			min = 0, max = 10, step = 1, format = function(v) return ("%d min"):format(v) end },
		{ key = "expiringAlpha", type = "slider", name = L.BUFFS_EXPIRING_ALPHA, desc = L.BUFFS_EXPIRING_ALPHA_DESC, parent = "enabled",
			min = 0.1, max = 1, step = 0.05, format = function(v) return ("%d%%"):format(v * 100 + 0.5) end },
	}
	if #reminders > 0 then
		options[#options + 1] = { type = "header", name = LOCALIZED_CLASS_NAMES_MALE[playerClass] or playerClass, desc = L.BUFFS_CLASS_DESC }
	end
	for _, reminder in ipairs(reminders) do
		local label = L["BUFFS_" .. reminder.key] or reminder.key
		options[#options + 1] = {
			key = reminder.key, type = "toggle", name = label, db = classDB,
			default = reminder.default ~= false, variable = playerClass .. "_" .. reminder.key,
		}
		if reminder.items then
			options[#options + 1] = {
				key = ChoiceKey(reminder), type = "dropdown", name = L.BUFFS_CHOICE, db = classDB, parent = reminder.key,
				default = "auto", values = PoisonChoices, variable = playerClass .. "_" .. ChoiceKey(reminder),
			}
		elseif #reminder.cast > 1 then
			options[#options + 1] = {
				key = ChoiceKey(reminder), type = "dropdown", name = L.BUFFS_CHOICE, db = classDB, parent = reminder.key,
				default = 0, values = SpellChoices(reminder), variable = playerClass .. "_" .. ChoiceKey(reminder),
			}
		end
	end
	return options
end

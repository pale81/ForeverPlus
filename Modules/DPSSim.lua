-- Expected steady-state melee autoattack DPS. Sample only when asked, outside combat.
local _, ns = ...
local L = ns.L

local Sim = ns:NewModule("DPSSim", {
	title = L.DPSSIM_TITLE,
	order = 5.55,
	defaults = { enabled = true },
	charDefaults = { armor = 30 },
})

-- SpellItemEnchantment and SpellEffect (Forever build 1.60.1.70938).
-- Enchant IDs are distinct from the cast spell IDs and survive a reload.
local imbues = {}
local function AddImbues(kind, ids, spells)
	for rank, id in ipairs(ids) do
		imbues[id] = { kind = kind, spellID = spells[rank], rank = rank }
	end
end

AddImbues("rock", { 29, 6, 1, 503, 1663, 683, 1664 }, { 8017, 8018, 8019, 10399, 16314, 16315, 16316 })
AddImbues("fire", { 5, 4, 3, 523, 1665, 1666 }, { 8024, 8027, 8030, 16339, 16341, 16342 })
AddImbues("frost", { 2, 12, 524, 1667, 1668 }, { 8033, 8038, 10456, 16355, 16356 })
AddImbues("wind", { 283, 284, 525, 1669 }, { 8232, 8235, 10486, 16362 })
imbues[7566], imbues[7568], imbues[7569] = imbues[1668], imbues[1664], imbues[1669]

local FROST_PPM = 9 -- approximation: the server's enchant proc frequency is not exposed
local WIND_COOLDOWN = 1.5 -- SpellAuraOptions.ProcCategoryRecovery for 439431
local FIRE_COEFFICIENT, FROST_COEFFICIENT = 0.10, 0.10
local ARMOR_PRESETS = { [0] = 15, [15] = 30, [30] = 45, [45] = 0 }
local ELEMENTAL_WEAPONS = 16266
local MODEL = 1

local window, current, status

local function PlainString(value)
	return type(value) == "string" and not ns.Secret(value) and value ~= "" and value or nil
end

local function SortedKey(values)
	table.sort(values)
	return table.concat(values, ";")
end

local function EquipmentKey()
	local parts = {}
	for slot = 1, INVSLOT_RANGED do
		local id = GetInventoryItemID("player", slot)
		if ns.Secret(id) then return end
		if id then
			local link = PlainString(GetInventoryItemLink("player", slot))
			local item = link and link:match("|H(item:[^|]+)|h")
			if not item then return end
			parts[#parts + 1] = slot .. ":" .. item
		end
	end
	return table.concat(parts, ";")
end

local function BuffKey()
	local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
	if type(auras) ~= "table" or ns.Secret(auras) then return end
	local parts = {}
	for _, aura in ipairs(auras) do
		if ns.Secret(aura) then return end
		local id, stacks = ns.Number(aura.spellId), ns.Number(aura.applications)
		if not id or not stacks then return end
		parts[#parts + 1] = ("%d:%d"):format(id, stacks)
	end
	return SortedKey(parts)
end

local function ElementalWeaponsRank()
	local configID = ns.Number(C_ClassTalents.GetActiveConfigID())
	local config = configID and C_Traits.GetConfigInfo(configID)
	for _, treeID in ipairs(config and config.treeIDs or {}) do
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			local active = node and node.activeEntry
			local rank = node and ns.Number(node.activeRank, 0) or 0
			if active and rank > 0 then
				local entry = C_Traits.GetEntryInfo(configID, active.entryID)
				local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
				if definition and definition.spellID == ELEMENTAL_WEAPONS then
					return math.min(3, rank)
				end
			end
		end
	end
	return 0
end

local WIND_TALENT_BONUS = { 0.13, 0.27, 0.40 }

-- Current rank/level values come from the client spell text. The damage range,
-- Frostbrand's damage and Windfury's chance / attacks / AP are its first numbers.
local function ImbueValues(spellID)
	local description = PlainString(C_Spell.GetSpellDescription(spellID))
	local values = {}
	if description and not description:find("$", 1, true) then
		for value in description:gmatch("%d+") do
			values[#values + 1] = tonumber(value)
			if #values == 3 then break end
		end
	end
	return unpack(values)
end

local function ProcDPS(imbue, damage, interval, damageMultiplier, crit)
	if imbue.kind == "rock" then
		return 0, 0 -- attack power is already reflected in UnitDamage
	end
	local haste = ns.Number(GetMeleeHaste())
	if not haste or haste <= -100 then return end
	local baseSpeed = interval * (1 + haste / 100)
	local rank = ElementalWeaponsRank()
	local first, second, third = ImbueValues(imbue.spellID)
	if imbue.kind == "wind" then
		if not third or first > 100 or second < 1 or second > 5 then return end
		local chance = first / 100
		-- A proc skips the regular swings that would arrive during its cooldown.
		local skipped = math.max(0, math.ceil(WIND_COOLDOWN / interval - 1e-6) - 1)
		local activations = chance / ((1 + chance * skipped) * interval)
		local extraAP = third * (1 + (WIND_TALENT_BONUS[rank] or 0))
		local perAttack = damage + extraAP / 14 * baseSpeed * damageMultiplier
		return activations * second * perAttack * (1 + crit), 0
	end
	local school = imbue.kind == "fire" and 3 or 5
	local spellPower = ns.Number(GetSpellBonusDamage(school))
	local spellCrit = ns.Number(GetSpellCritChance(school))
	if not first or not spellPower or not spellCrit then return end
	local perHit, chance
	if imbue.kind == "fire" then
		if not second or second < first then return end
		-- The upper tooltip endpoint uses a 4.0 s weapon. Scale by unhasted weapon speed.
		perHit, chance = second * baseSpeed / 4 + FIRE_COEFFICIENT * spellPower, 1
	else
		perHit = first + FROST_COEFFICIENT * spellPower
		chance = math.min(1, FROST_PPM * baseSpeed / 60)
	end
	local bonus = math.max(0, perHit) * (1 + 0.05 * rank) * (1 + math.min(100, math.max(0, spellCrit)) / 200)
	return 0, bonus * chance / interval
end

local function ReadEnchants(slot, isMain, snapshot, other)
	local list = C_Item.GetWeaponEnchantInfo(slot)
	if type(list) ~= "table" or ns.Secret(list) then return false end
	for _, enchant in pairs(list) do
		if ns.Secret(enchant) or ns.Secret(enchant.hasEnchant) then return false end
		if enchant.hasEnchant then
			local id = ns.Number(enchant.enchantID)
			if not id then return false end
			if isMain and imbues[id] and not snapshot.imbue then
				snapshot.imbue = id
			else
				other[#other + 1] = ("%d:%d"):format(slot, id)
			end
		end
	end
	return true
end

local function Simulate()
	if InCombatLockdown() then return nil, L.DPSSIM_COMBAT end
	local item = ns.Number(GetInventoryItemID("player", INVSLOT_MAINHAND))
	if not item then return nil, L.DPSSIM_WEAPON_REQUIRED end
	local _, _, _, equipLoc, _, class, subclass = C_Item.GetItemInfoInstant(item)
	if ns.Secret(class) or ns.Secret(subclass) or ns.Secret(equipLoc) or not class then return nil, L.DPSSIM_UNAVAILABLE end
	if class ~= Enum.ItemClass.Weapon or subclass == Enum.ItemWeaponSubclass.Fishingpole
		or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" then
		return nil, L.DPSSIM_WEAPON_REQUIRED
	end

	local low, high, offLow, offHigh, _, _, multiplier = UnitDamage("player")
	local speed, offSpeed = UnitAttackSpeed("player")
	local crit = ns.Number(GetCritChance())
	low, high, speed, multiplier = ns.Number(low), ns.Number(high), ns.Number(speed), ns.Number(multiplier)
	if not low or not high or not speed or speed <= 0 or not crit or not multiplier or multiplier <= 0
		or ns.Secret(offSpeed) then
		return nil, L.DPSSIM_UNAVAILABLE
	end
	crit = math.min(100, math.max(0, crit)) / 100
	local damage = (low + high) / 2
	local white = damage / speed
	if offSpeed and offSpeed > 0 then
		offLow, offHigh = ns.Number(offLow), ns.Number(offHigh)
		if not offLow or not offHigh then return nil, L.DPSSIM_UNAVAILABLE end
		white = white + (offLow + offHigh) / (2 * offSpeed)
	end
	local snapshot = {
		model = MODEL, physical = white * (1 + crit), procPhysical = 0, procMagic = 0,
		equipment = EquipmentKey(), buffs = BuffKey(), level = ns.Number(UnitLevel("player")),
		weapon = PlainString(C_Item.GetItemNameByID(item)) or ("#%d"):format(item),
	}
	local other = {}
	local ranged = GetInventoryItemID("player", INVSLOT_RANGED)
	if not ReadEnchants(Enum.WeaponSlot.MainHand, true, snapshot, other)
		or (offSpeed and offSpeed > 0 and not ReadEnchants(Enum.WeaponSlot.OffHand, false, snapshot, other))
		or ns.Secret(ranged) or (ranged and not ReadEnchants(Enum.WeaponSlot.Ranged, false, snapshot, other)) then
		return nil, L.DPSSIM_UNAVAILABLE
	end
	snapshot.other = SortedKey(other)
	if snapshot.imbue then
		snapshot.procPhysical, snapshot.procMagic = ProcDPS(imbues[snapshot.imbue], damage, speed, multiplier, crit)
		if not snapshot.procPhysical then return nil, L.DPSSIM_SPELL_UNAVAILABLE end
	end
	return snapshot
end

local function Numbers(s, armor)
	local factor = 1 - armor / 100
	local proc = s.procPhysical * factor + s.procMagic
	return s.physical * factor + proc, proc
end

local function Baseline()
	local saved = Sim.cdb.baseline
	if type(saved) == "table" and saved.model == MODEL then return saved end
end

local function SetupLabel(snapshot)
	local imbue = imbues[snapshot.imbue]
	local text = L.DPSSIM_NO_IMBUE
	if imbue then
		local name = PlainString(C_Spell.GetSpellName(imbue.spellID)) or L.DPSSIM_UNKNOWN_IMBUE
		text = L.DPSSIM_IMBUE_RANK:format(name, imbue.rank)
		if imbue.kind == "frost" then text = text .. " " .. L.DPSSIM_FROST_APPROX end
	end
	if snapshot.other ~= "" then text = text .. " · " .. L.DPSSIM_OTHER_ENCHANT end
	return snapshot.weapon .. " · " .. text
end

local function Refresh()
	local armor, baseline = Sim.cdb.armor, Baseline()
	window.armor:SetText(L.DPSSIM_ARMOR:format(armor))
	window.save:SetEnabled(current ~= nil)
	window.clear:SetEnabled(baseline ~= nil)
	local total, proc, reference
	if current then total, proc = Numbers(current, armor) end
	if baseline then reference = Numbers(baseline, armor) end
	local title = total and L.DPSSIM_RESULT:format(total, proc) or L.DPSSIM_CURRENT
	window.current:SetText(title)
	window.currentSetup:SetText(current and SetupLabel(current) or status)
	window.baseline:SetText(reference and L.DPSSIM_BASELINE:format(reference) or L.DPSSIM_NO_BASELINE)
	window.baselineSetup:SetText(baseline and SetupLabel(baseline) or "")
	local delta, note
	if current and baseline then
		if current.other ~= baseline.other then
			note = L.DPSSIM_UNSUPPORTED_CHANGED
		else
			local diff = total - reference
			if math.abs(diff) < 0.005 then diff = 0 end
			delta = (reference > 0 and L.DPSSIM_DELTA_PCT or L.DPSSIM_DELTA):format(diff, reference > 0 and diff / reference * 100 or 0)
			if not current.equipment or not current.buffs or not baseline.equipment or not baseline.buffs then
				note = L.DPSSIM_CONTEXT_UNKNOWN
			elseif current.equipment ~= baseline.equipment or current.buffs ~= baseline.buffs or current.level ~= baseline.level then
				note = L.DPSSIM_CONTEXT_CHANGED
			end
			window.delta:SetTextColor(diff < 0 and 1 or 0.55, diff < 0 and 0.52 or 0.95, 0.55)
		end
	end
	window.delta:SetText(delta or "")
	window.note:SetText(note or "")
end

local function UpdateSample()
	current, status = Simulate()
	Refresh()
end

local function MakeLabel(frame, font, y)
	local label = frame:CreateFontString(nil, "ARTWORK", font)
	label:SetPoint("TOPLEFT", 16, y)
	label:SetPoint("RIGHT", -16, 0)
	label:SetJustifyH("LEFT")
	return label
end

local function MakeButton(frame, text, width, x, y, fn)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetPoint("TOPLEFT", x, y)
	button:SetText(text)
	button:SetScript("OnClick", ns.Measured("DPSSim: " .. text, fn))
	return button
end

local function CreateWindow()
	local frame = ns.CreatePanel("ForeverPlusDPSSimWindow", { close = true })
	frame:SetPoint("CENTER")
	frame:SetSize(532, 303)
	frame.Title:SetText(L.DPSSIM_TITLE)
	MakeLabel(frame, "GameFontHighlightSmall", -32):SetText(L.DPSSIM_INSTRUCTIONS)
	frame.run = MakeButton(frame, L.DPSSIM_RUN, 120, 16, -67, UpdateSample)
	frame.save = MakeButton(frame, L.DPSSIM_SAVE, 150, 144, -67, function()
		if current then
			Sim.cdb.baseline = current
			Refresh()
		end
	end)
	frame.clear = MakeButton(frame, L.DPSSIM_CLEAR, 150, 302, -67, function()
		Sim.cdb.baseline = nil
		Refresh()
	end)
	frame.current = MakeLabel(frame, "GameFontNormal", -104)
	frame.currentSetup = MakeLabel(frame, "GameFontHighlightSmall", -123)
	frame.baseline = MakeLabel(frame, "GameFontNormal", -151)
	frame.baselineSetup = MakeLabel(frame, "GameFontHighlightSmall", -170)
	frame.delta = MakeLabel(frame, "GameFontNormalLarge", -198)
	frame.note = MakeLabel(frame, "GameFontHighlightSmall", -218)
	frame.armor = MakeButton(frame, "", 150, 16, -266, function()
		Sim.cdb.armor = ARMOR_PRESETS[Sim.cdb.armor]
		Refresh()
	end)
	local assumptions = MakeLabel(frame, "GameFontHighlightSmall", -251)
	assumptions:ClearAllPoints()
	assumptions:SetPoint("TOPLEFT", 176, -251)
	assumptions:SetPoint("RIGHT", -16, 0)
	assumptions:SetText(L.DPSSIM_ASSUMPTIONS)
	return frame
end

Sim.Open = ns.Measured("DPSSim: Open", function()
	if not Sim.db.enabled then
		ns.PrintAlways(L.DPSSIM_DISABLED)
		return
	end
	window = window or CreateWindow()
	if not ARMOR_PRESETS[Sim.cdb.armor] then Sim.cdb.armor = 30 end
	UpdateSample()
	window:Show()
end)

function Sim:OnOptionChanged()
	if window and not self.db.enabled then window:Hide() end
end

Sim.options = {
	{ key = "enabled", type = "toggle", name = L.DPSSIM_TITLE, desc = L.DPSSIM_OPTION },
	{ type = "button", name = L.DPSSIM_TITLE, text = L.DPSSIM_OPEN, func = Sim.Open },
}

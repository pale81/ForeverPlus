-- Combat text: numbers that rise from the target (damage) and from the player (damage taken, healing). A
-- replacement for the game's floating numbers, which the invisible font of the experience display hides (RepFlash).
-- Fed by UNIT_COMBAT; the event does not say who dealt the damage, so damage of others on the target shows too.
local _, ns = ...
local L = ns.L

local CombatText = ns:NewModule("CombatText", {
	title = L.COMBATTEXT_TITLE,
	order = 5.85,
	defaults = {
		enabled = false,
		outgoing = true, -- damage on the target
		incoming = true, -- damage taken
		heals = true,    -- healing received
		scale = 1,
	},
})

local TEXT_SIZE = 22
local CRIT_FACTOR = 1.5
local RISE = 80          -- pixels over the lifetime
local LIFETIME = 1.4     -- seconds
local MAX_ACTIVE = 30
local PLAYER_X, PLAYER_Y = -140, 40 -- left of the screen centre, a little above: roughly beside the character

local COLORS = {
	outgoing = { 1, 0.82, 0.1 },
	crit = { 1, 0.5, 0.1 },
	incoming = { 1, 0.25, 0.25 },
	heal = { 0.25, 1, 0.35 },
	miss = { 0.8, 0.8, 0.8 },
}

-- Events of UNIT_COMBAT that are a plain word (miss, dodge …); the game has a text for each.
local MISSES = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, EVADE = true, IMMUNE = true,
	DEFLECT = true, ABSORB = true, RESIST = true, REFLECT = true }

local frame
local pool, active = {}, {}

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Acquire()
	local fs = table.remove(pool)
	if not fs then
		fs = frame:CreateFontString(nil, "OVERLAY")
	end
	return fs
end

local function Release(entry)
	entry.fs:Hide()
	entry.fs:ClearAllPoints()
	pool[#pool + 1] = entry.fs
	entry.fs = nil
end

local function Place(entry, rise)
	entry.fs:ClearAllPoints()
	if entry.plate then
		entry.fs:SetPoint("BOTTOM", entry.plate, "TOP", entry.x, 6 + rise)
	else
		entry.fs:SetPoint("CENTER", UIParent, "CENTER", entry.x, entry.y + rise)
	end
end

local function Update(_, delta)
	for index = #active, 1, -1 do
		local entry = active[index]
		entry.age = entry.age + delta
		local k = entry.age / LIFETIME
		if k >= 1 or (entry.plate and not entry.plate:IsShown()) then
			Release(entry)
			table.remove(active, index)
		else
			Place(entry, RISE * (1 - (1 - k) * (1 - k)))
			entry.fs:SetAlpha(k > 0.6 and 1 - (k - 0.6) / 0.4 or 1)
		end
	end
	if #active == 0 then
		ns.SetUpdate(frame, "Combat text", nil)
	end
end

-- text: what to show; kind: a key of COLORS; crit: larger; plate: the nameplate to rise from (or nil).
local function Spawn(text, kind, crit, plate)
	if not frame then
		frame = CreateFrame("Frame", nil, UIParent)
		frame:SetFrameStrata("HIGH")
		frame:SetAllPoints(UIParent)
		frame:EnableMouse(false)
	end
	if #active >= MAX_ACTIVE then
		Release(table.remove(active, 1))
	end
	local fs = Acquire()
	local size = TEXT_SIZE * ns.Number(CombatText.db.scale, 1) * (crit and CRIT_FACTOR or 1)
	fs:SetFont(ns.GetFontFace(), size, "OUTLINE")
	local color = COLORS[crit and kind == "outgoing" and "crit" or kind]
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetText(text)
	fs:SetAlpha(1)
	fs:Show()
	local entry = { fs = fs, age = 0, plate = plate, x = math.random(-25, 25), y = PLAYER_Y }
	if kind ~= "outgoing" then
		entry.x = PLAYER_X + entry.x
	end
	active[#active + 1] = entry
	Place(entry, 0)
	ns.SetUpdate(frame, "Combat text", Update)
end

-- One UNIT_COMBAT event: unit, event ("WOUND", "HEAL", "MISS" …), flag text ("CRITICAL" …), amount.
function CombatText.Handle(unit, event, flagText, amount)
	local db = CombatText.db
	if not db.enabled or type(unit) ~= "string" or Secret(unit) or Secret(event) then
		return
	end
	local mine = unit == "player"
	if not mine and unit ~= "target" then
		return
	end
	local plate
	if not mine then
		-- Damage on the target; not on friends, not on oneself.
		if not db.outgoing or not UnitCanAttack("player", "target") or UnitIsUnit("target", "player") then
			return
		end
		plate = C_NamePlate.GetNamePlateForUnit("target")
		if plate and plate:IsForbidden() then
			plate = nil
		end
	end
	local kind
	if event == "WOUND" then
		kind = mine and "incoming" or "outgoing"
		if mine and not db.incoming then
			return
		end
	elseif event == "HEAL" then
		if not (mine and db.heals) then
			return
		end
		kind = "heal"
	elseif MISSES[event] then
		if mine and not db.incoming then
			return
		end
		kind = "miss"
	else
		return
	end
	local text
	if kind == "miss" then
		text = _G["COMBAT_TEXT_" .. event] or event
	else
		local ok, formatted = pcall(string.format, "%d", amount)
		if not ok then
			return
		end
		text = kind == "heal" and "+" .. formatted or formatted
	end
	local crit = not Secret(flagText) and flagText == "CRITICAL"
	Spawn(text, kind, crit, plate)
end

function CombatText:Apply()
	self:ToggleEvent("UNIT_COMBAT", self.db.enabled, function(_, _, unit, event, flagText, amount)
		CombatText.Handle(unit, event, flagText, amount)
	end)
end

function CombatText:OnLogin()
	self:Apply()
end

function CombatText:OnOptionChanged()
	self:Apply()
end

CombatText.options = {
	{ key = "enabled", type = "toggle", name = L.COMBATTEXT_ENABLE, desc = L.COMBATTEXT_ENABLE_DESC, new = true },
	{ key = "outgoing", type = "toggle", name = L.COMBATTEXT_OUTGOING, desc = L.COMBATTEXT_OUTGOING_DESC, parent = "enabled", new = true },
	{ key = "incoming", type = "toggle", name = L.COMBATTEXT_INCOMING, desc = L.COMBATTEXT_INCOMING_DESC, parent = "enabled", new = true },
	{ key = "heals", type = "toggle", name = L.COMBATTEXT_HEALS, desc = L.COMBATTEXT_HEALS_DESC, parent = "enabled", new = true },
	{ key = "scale", type = "slider", name = L.COMBATTEXT_SCALE, parent = "enabled", min = 0.6, max = 2, step = 0.1,
		format = function(v) return ("%d%%"):format(v * 100 + 0.5) end, new = true },
	{ type = "button", name = L.COMBATTEXT_TEST, text = L.QUESTS_TEST, desc = L.COMBATTEXT_TEST_DESC, func = function()
		Spawn("1234", "outgoing", false)
		Spawn("2468", "outgoing", true)
		Spawn("312", "incoming", false)
		Spawn("+540", "heal", false)
	end },
}

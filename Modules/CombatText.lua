-- Combat text: numbers that rise from the target (damage) and beside the player (damage taken, healing). A
-- replacement for the game's floating numbers, which the invisible font of the experience display hides (RepFlash).
-- Fed by UNIT_COMBAT; the event does not say who dealt the damage, so damage of others on the target shows too.
-- The three places (target, damage taken, healing) are separate frames to place in Edit Mode.
local _, ns = ...
local L = ns.L

local CombatText = ns:NewModule("CombatText", {
	title = L.COMBATTEXT_TITLE,
	order = 5.85,
	defaults = {
		enabled = false,
		outgoing = true,     -- damage on the target
		targetPlate = true,  -- rising from the nameplate of the target (else from its own place)
		incoming = true,     -- damage taken
		heals = true,        -- healing received
		scale = 1,
		critBold = true,     -- critical hits large with a thick outline
		critShake = true,    -- and shaking at the start
		colorOutgoing = "YELLOW",
		colorCrit = "ORANGE",
		colorIncoming = "RED",
		colorHeal = "GREEN",
		colorMiss = "GREY",
	},
})

local TEXT_SIZE = 22
local CRIT_FACTOR = 1.5
local RISE = 80          -- pixels over the lifetime
local LIFETIME = 1.4     -- seconds
local MAX_ACTIVE = 30
local STAGGER = 26       -- pixels: texts of one place that appear within STAGGER_TIME start one above the other
local STAGGER_TIME = 0.7
local MAX_STAGGER = 4
local SHAKE_TIME = 0.5   -- seconds a critical hit shakes
local SHAKE_SIZE = 7     -- pixels

local COLOR_VALUES = {
	YELLOW = { 1, 0.82, 0.1 }, ORANGE = { 1, 0.5, 0.1 }, RED = { 1, 0.25, 0.25 }, GREEN = { 0.25, 1, 0.35 },
	WHITE = { 1, 1, 1 }, BLUE = { 0.4, 0.7, 1 }, PURPLE = { 0.75, 0.45, 1 }, GREY = { 0.8, 0.8, 0.8 },
}

local function ColorOf(key)
	if key == "CLASS" then
		local _, classFile = UnitClass("player")
		local color = classFile and C_ClassColor.GetClassColor(classFile)
		if color then
			return { ns.Number(color.r, 1), ns.Number(color.g, 1), ns.Number(color.b, 1) }
		end
		return COLOR_VALUES.WHITE
	end
	return COLOR_VALUES[key] or COLOR_VALUES.WHITE
end

-- Events of UNIT_COMBAT that are a plain word (miss, dodge …); the game has a text for each.
local MISSES = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, EVADE = true, IMMUNE = true,
	DEFLECT = true, ABSORB = true, RESIST = true, REFLECT = true }

-- The places: key -> { key in Edit Mode, label, default point of the frame }.
local PLACES = {
	target = { "CombatTextTarget", L.COMBATTEXT_PLACE_TARGET, { "CENTER", UIParent, "CENTER", 0, 80 } },
	incoming = { "CombatTextIncoming", L.COMBATTEXT_PLACE_INCOMING, { "CENTER", UIParent, "CENTER", -140, 40 } },
	heal = { "CombatTextHeal", L.COMBATTEXT_PLACE_HEAL, { "CENTER", UIParent, "CENTER", 140, 40 } },
}
local anchors = {}

local frame
local pool, active = {}, {}

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function CreateAnchors()
	for key, place in pairs(PLACES) do
		local anchor = CreateFrame("Frame", nil, UIParent)
		anchor:SetSize(90, 30)
		anchor:SetPoint(unpack(place[3]))
		anchors[key] = anchor
		ns:RegisterEditFrame(anchor, place[1], place[2], place[3])
	end
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
	local x, y = entry.x, entry.y + rise
	if entry.shake and entry.age < SHAKE_TIME then
		local strength = SHAKE_SIZE * (1 - entry.age / SHAKE_TIME)
		x, y = x + (math.random() - 0.5) * 2 * strength, y + (math.random() - 0.5) * 2 * strength
	end
	entry.fs:ClearAllPoints()
	if entry.plate then
		entry.fs:SetPoint("BOTTOM", entry.plate, "TOP", x, 6 + y)
	else
		entry.fs:SetPoint("CENTER", entry.anchor, "CENTER", x, y)
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

-- text: what to show; kind: outgoing, incoming, heal or miss; crit: large and shaking (options); plate: the
-- nameplate to rise from (or nil: the place of the kind).
local function Spawn(text, kind, crit, plate)
	local db = CombatText.db
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
	local bold = crit and db.critBold
	local size = TEXT_SIZE * ns.Number(db.scale, 1) * (bold and CRIT_FACTOR or 1)
	fs:SetFont(ns.GetFontFace(), size, bold and "THICKOUTLINE" or "OUTLINE")
	local colorKey
	if crit and kind == "outgoing" then
		colorKey = db.colorCrit
	elseif kind == "outgoing" then
		colorKey = db.colorOutgoing
	elseif kind == "heal" then
		colorKey = db.colorHeal
	elseif kind == "miss" then
		colorKey = db.colorMiss
	else
		colorKey = db.colorIncoming
	end
	local color = ColorOf(colorKey)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetText(text)
	fs:SetAlpha(1)
	fs:Show()
	-- Three places: the target, damage taken (and misses), healing.
	local group = kind == "outgoing" and "target" or kind == "heal" and "heal" or "incoming"
	local recent = 0
	for _, other in ipairs(active) do
		if other.group == group and other.plate == plate and other.age < STAGGER_TIME then
			recent = recent + 1
		end
	end
	local entry = { fs = fs, age = 0, plate = plate, group = group, anchor = anchors[group] or UIParent,
		x = math.random(-12, 12), y = math.min(recent, MAX_STAGGER) * STAGGER, shake = crit and db.critShake }
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
		if db.targetPlate then
			plate = C_NamePlate.GetNamePlateForUnit("target")
			if plate and plate:IsForbidden() then
				plate = nil
			end
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
	CreateAnchors()
	self:Apply()
end

function CombatText:OnOptionChanged()
	self:Apply()
end

local function ColorChoices()
	return {
		{ "YELLOW", L.CHAT_COLOR_YELLOW }, { "ORANGE", L.CHAT_COLOR_ORANGE }, { "RED", L.CHAT_COLOR_RED },
		{ "GREEN", L.CHAT_COLOR_GREEN }, { "BLUE", L.CHAT_COLOR_BLUE }, { "PURPLE", L.COMBATTEXT_COLOR_PURPLE },
		{ "WHITE", L.CHAT_COLOR_WHITE }, { "GREY", L.CHAT_COLOR_GREY }, { "CLASS", L.COMBATTEXT_COLOR_CLASS },
	}
end

CombatText.options = {
	{ key = "enabled", type = "toggle", name = L.COMBATTEXT_ENABLE, desc = L.COMBATTEXT_ENABLE_DESC, new = true },
	{ key = "outgoing", type = "toggle", name = L.COMBATTEXT_OUTGOING, desc = L.COMBATTEXT_OUTGOING_DESC, parent = "enabled", new = true },
	{ key = "targetPlate", type = "toggle", name = L.COMBATTEXT_TARGET_PLATE, desc = L.COMBATTEXT_TARGET_PLATE_DESC, parent = "outgoing", new = true },
	{ key = "incoming", type = "toggle", name = L.COMBATTEXT_INCOMING, desc = L.COMBATTEXT_INCOMING_DESC, parent = "enabled", new = true },
	{ key = "heals", type = "toggle", name = L.COMBATTEXT_HEALS, desc = L.COMBATTEXT_HEALS_DESC, parent = "enabled", new = true },
	{ key = "scale", type = "slider", name = L.COMBATTEXT_SCALE, parent = "enabled", min = 0.6, max = 2, step = 0.1,
		format = function(v) return ("%d%%"):format(v * 100 + 0.5) end, new = true },
	{ key = "critBold", type = "toggle", name = L.COMBATTEXT_CRIT_BOLD, desc = L.COMBATTEXT_CRIT_BOLD_DESC, parent = "enabled", new = true },
	{ key = "critShake", type = "toggle", name = L.COMBATTEXT_CRIT_SHAKE, desc = L.COMBATTEXT_CRIT_SHAKE_DESC, parent = "enabled", new = true },
	{ key = "colorOutgoing", type = "dropdown", name = L.COMBATTEXT_COLOR_OUTGOING, parent = "enabled", values = ColorChoices, new = true },
	{ key = "colorCrit", type = "dropdown", name = L.COMBATTEXT_COLOR_CRIT, parent = "enabled", values = ColorChoices, new = true },
	{ key = "colorIncoming", type = "dropdown", name = L.COMBATTEXT_COLOR_INCOMING, parent = "enabled", values = ColorChoices, new = true },
	{ key = "colorHeal", type = "dropdown", name = L.COMBATTEXT_COLOR_HEAL, parent = "enabled", values = ColorChoices, new = true },
	{ key = "colorMiss", type = "dropdown", name = L.COMBATTEXT_COLOR_MISS, parent = "enabled", values = ColorChoices, new = true },
	{ type = "button", name = L.COMBATTEXT_TEST, text = L.QUESTS_TEST, desc = L.COMBATTEXT_TEST_DESC, func = function()
		Spawn("1234", "outgoing", false)
		Spawn("2468", "outgoing", true)
		Spawn("312", "incoming", false)
		Spawn("+540", "heal", false)
		Spawn(_G.COMBAT_TEXT_MISS or "Miss", "miss", false)
	end },
}

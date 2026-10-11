-- Companion: a small model of the player (or the pet) that reacts to what
-- happens: ready stance in combat, sleeping while resting, dead when dead,
-- dancing on a level up, cheering for a finished quest. Movable like the other
-- displays; reactions only change on events, nothing runs per frame.
local _, ns = ...
local L = ns.L

local Companion = ns:NewModule("Companion", {
	title = L.COMPANION_TITLE,
	order = 15,
	defaults = {
		enabled = false,
		unit = "player",
		reactions = true,
	},
})

-- Model animations (the numbers of the game's animation table).
local ANIMATION = { idle = 0, combat = 25, rest = 71, dead = 6, levelUp = 69, quest = 68 }
local REACTION_SECONDS = { levelUp = 4, quest = 2.5 }

local frame, reaction

local function UnitToShow()
	local unit = Companion.db.unit
	if unit == "pet" and UnitExists("pet") then
		return "pet"
	end
	return "player"
end

-- What the companion does right now.
function Companion.State()
	if UnitIsDeadOrGhost("player") then
		return "dead"
	elseif reaction then
		return reaction
	elseif UnitAffectingCombat("player") then
		return "combat"
	elseif IsResting() then
		return "rest"
	end
	return "idle"
end

local function Update()
	if not frame or not frame:IsShown() then
		return
	end
	local state = Companion.db.reactions and Companion.State() or "idle"
	frame.state = state
	frame:SetAnimation(ANIMATION[state] or 0)
end

local function SetModel()
	if frame and frame:IsShown() then
		frame:SetUnit(UnitToShow())
		Update()
	end
end

local reactionToken = 0
local function React(name)
	if not Companion.db.reactions then
		return
	end
	reaction = name
	reactionToken = reactionToken + 1
	local token = reactionToken
	Update()
	C_Timer.After(REACTION_SECONDS[name] or 3, function()
		if token == reactionToken then
			reaction = nil
			Update()
		end
	end)
end

local function CreateFrameOnce()
	if frame then
		return
	end
	frame = CreateFrame("PlayerModel", "ForeverPlusCompanion", UIParent)
	frame:SetSize(90, 110)
	frame:SetFrameStrata("LOW")
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.COMPANION_TITLE)
		GameTooltip:AddLine(L["COMPANION_STATE_" .. (self.state or "idle"):upper()], 1, 1, 1)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	ns:RegisterDisplay(frame, "Companion", function(self)
		self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 170)
	end)
end

function Companion:Apply()
	local db = self.db
	if db.enabled then
		CreateFrameOnce()
		frame:Show()
		SetModel()
	elseif frame then
		frame:Hide()
	end
	local on = db.enabled
	self:ToggleEvent("PLAYER_REGEN_DISABLED", on, Update)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", on, Update)
	self:ToggleEvent("PLAYER_DEAD", on, Update)
	self:ToggleEvent("PLAYER_ALIVE", on, Update)
	self:ToggleEvent("PLAYER_UNGHOST", on, Update)
	self:ToggleEvent("PLAYER_UPDATE_RESTING", on, Update)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, SetModel)
	self:ToggleEvent("UNIT_PET", on, SetModel)
	self:ToggleEvent("UNIT_MODEL_CHANGED", on, SetModel)
	self:ToggleEvent("PLAYER_LEVEL_UP", on, function() React("levelUp") end)
	self:ToggleEvent("QUEST_TURNED_IN", on, function() React("quest") end)
end

function Companion:OnLogin()
	self:Apply()
end

function Companion:OnOptionChanged()
	self:Apply()
end

Companion.React = React

Companion.options = {
	{ key = "enabled", type = "toggle", name = L.COMPANION_ENABLE, desc = L.COMPANION_ENABLE_DESC },
	{ key = "unit", type = "dropdown", name = L.COMPANION_UNIT, desc = L.COMPANION_UNIT_DESC, parent = "enabled", values = {
		{ "player", L.COMPANION_UNIT_PLAYER }, { "pet", L.COMPANION_UNIT_PET },
	} },
	{ key = "reactions", type = "toggle", name = L.COMPANION_REACTIONS, desc = L.COMPANION_REACTIONS_DESC, parent = "enabled" },
}

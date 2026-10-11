-- Resets Blizzard's damage meter automatically: on a boss pull, at the start of
-- a Mythic+ run, at every combat start, or never.
local _, ns = ...
local L = ns.L

local MeterReset = ns:NewModule("MeterReset", {
	title = L.METER_TITLE,
	order = 5.5,
	defaults = {
		mode = "never",
	},
})

local function Reset()
	if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
		C_DamageMeter.ResetAllCombatSessions()
	end
end

local function OnEncounter()
	Reset()
end

local function OnChallengeStart()
	Reset()
end

local function OnCombat()
	Reset()
end

function MeterReset:Apply()
	local mode = self.db.mode
	self:ToggleEvent("ENCOUNTER_START", mode == "boss" or mode == "bossMplus", OnEncounter)
	self:ToggleEvent("CHALLENGE_MODE_START", mode == "mplus" or mode == "bossMplus", OnChallengeStart)
	self:ToggleEvent("PLAYER_REGEN_DISABLED", mode == "combat", OnCombat)
end

function MeterReset:OnLogin()
	self:Apply()
end

function MeterReset:OnOptionChanged()
	self:Apply()
end

MeterReset.options = {
	{ key = "mode", type = "dropdown", name = L.METER_MODE, desc = L.METER_MODE_DESC, values = {
		{ "never", L.METER_NEVER }, { "boss", L.METER_BOSS }, { "mplus", L.METER_MPLUS },
		{ "bossMplus", L.METER_BOSS_MPLUS }, { "combat", L.METER_COMBAT },
	} },
}

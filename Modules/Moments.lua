-- Moments: a screenshot when a boss dies and at a level-up, and a fanfare at a level-up.
local _, ns = ...
local L = ns.L

local SOUNDS = { "UI_RAID_BOSS_DEFEATED", "UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS", "UI_LEGENDARY_LOOT_TOAST",
	"UI_WORLDQUEST_COMPLETE", "UI_EPICLOOT_TOAST" }

local Moments = ns:NewModule("Moments", {
	title = L.MOMENTS_TITLE,
	order = 5.36,
	defaults = {
		shotBoss = false,
		shotLevel = false,
		levelSound = true,
		levelSoundKit = "UI_RAID_BOSS_DEFEATED",
	},
})

local SHOT_DELAY = 1 -- seconds: the message of the game (level reached, boss defeated) is on the screen by then
local SHOT_GAP = 5 -- a boss ends with two events (ENCOUNTER_END, BOSS_KILL): one picture
local lastShot

-- Whether a picture is due now (now: GetTime()); remembers it.
function Moments.ShotDue(now)
	if lastShot and now - lastShot < SHOT_GAP then
		return false
	end
	lastShot = now
	return true
end

local function Shoot()
	if Moments.ShotDue(GetTime()) then
		ns.After("Moments: screenshot", SHOT_DELAY, function()
			Screenshot()
		end)
	end
end

function Moments.PlayLevelSound()
	local kit = SOUNDKIT[Moments.db.levelSoundKit]
	if kit then
		PlaySound(kit, "Master")
	end
end

function Moments:Apply()
	local db = self.db
	self:ToggleEvent("PLAYER_LEVEL_UP", db.shotLevel or db.levelSound, function()
		if db.levelSound then
			Moments.PlayLevelSound()
		end
		if db.shotLevel then
			Shoot()
		end
	end)
	-- success: 1 when the boss died (0 after a wipe).
	self:ToggleEvent("ENCOUNTER_END", db.shotBoss, function(_, _, _, _, _, _, success)
		if not ns.Secret(success) and success == 1 then
			Shoot()
		end
	end)
	self:ToggleEvent("BOSS_KILL", db.shotBoss, Shoot)
end

function Moments:OnLogin()
	self:Apply()
end

function Moments:OnOptionChanged(key)
	self:Apply()
	if key == "levelSoundKit" then
		Moments.PlayLevelSound()
	end
end

Moments.options = {
	{ key = "shotBoss", type = "toggle", name = L.MOMENTS_SHOT_BOSS, desc = L.MOMENTS_SHOT_BOSS_DESC, new = true },
	{ key = "shotLevel", type = "toggle", name = L.MOMENTS_SHOT_LEVEL, desc = L.MOMENTS_SHOT_LEVEL_DESC, new = true },
	{ key = "levelSound", type = "toggle", name = L.MOMENTS_SOUND, desc = L.MOMENTS_SOUND_DESC, new = true },
	{ key = "levelSoundKit", type = "dropdown", name = L.MOMENTS_SOUND_KIT, parent = "levelSound", values = function()
		local values = {}
		for index, key in ipairs(SOUNDS) do
			values[#values + 1] = { key, L.MOMENTS_SOUND_NAME:format(index) }
		end
		return values
	end },
	{ type = "button", name = L.MOMENTS_SOUND_TEST, text = L.QUESTS_TEST, func = function()
		Moments.PlayLevelSound()
	end },
}

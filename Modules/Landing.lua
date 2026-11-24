-- Landing: a sound of the game when the character lands after a jump or a fall. The game has no event for it,
-- so the module watches IsFalling every frame and plays the sound when it turns from true to false.
local _, ns = ...
local L = ns.L

-- Sound files of the game (FileDataIDs, community listfile): small classic footsteps for a jump (the heavy ones
-- were too loud for every jump), a dull thud on dirt and grass for a longer fall.
local JUMP_SOUNDS = {
	540227, -- Sound/CHARACTER/FOOTSTEPS/mFootSmallDirtA.ogg
	540136, -- Sound/CHARACTER/FOOTSTEPS/mFootSmallDirtB.ogg
	540099, -- Sound/CHARACTER/FOOTSTEPS/mFootSmallDirtC.ogg
	540201, -- Sound/CHARACTER/FOOTSTEPS/mFootSmallDirtD.ogg
	540128, -- Sound/CHARACTER/FOOTSTEPS/mFootSmallDirtE.ogg
}
local FALL_SOUNDS = {
	950654, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_01.OGG
	950656, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_02.OGG
	950658, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_03.OGG
	950660, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_04.OGG
	950662, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_05.OGG
	950664, -- Sound/DOODAD/FX_DeathThud_DirtGrass_med_06.OGG
}
-- Seconds in the air: shorter is a step off an edge (no sound), longer than a normal jump is a fall.
local MIN_AIRTIME, FALL_AIRTIME = 0.15, 1.0

local Landing = ns:NewModule("Landing", {
	title = L.LANDING_TITLE,
	order = 5.38,
	defaults = {
		enabled = true,
	},
})

-- One frame of the watch: remembers when the fall began and on landing returns "jump", "fall" or nil.
-- blocked: landed in water, on a flight path or dead – no sound then.
function Landing.Step(state, falling, now, blocked)
	if falling then
		state.since = state.since or now
		return nil
	end
	local since = state.since
	state.since = nil
	if not since or blocked then
		return nil
	end
	local airtime = now - since
	if airtime < MIN_AIRTIME then
		return nil
	end
	return airtime < FALL_AIRTIME and "jump" or "fall"
end

local state, last = {}, {}

-- Start at a random variant and use each one before repeating it.
local function Play(kind)
	local pool = kind == "fall" and FALL_SOUNDS or JUMP_SOUNDS
	local index = last[kind] and last[kind] % #pool + 1 or math.random(#pool)
	last[kind] = index
	PlaySoundFile(pool[index], "SFX")
end

local function Blocked()
	return IsSwimming() or IsFlying() or UnitOnTaxi("player") or UnitIsDeadOrGhost("player")
end

local function OnUpdate()
	local falling = IsFalling()
	if not falling and not state.since then
		return
	end
	local kind = Landing.Step(state, falling, GetTime(), Blocked())
	if kind then
		Play(kind)
	end
end

local watcher

function Landing:Apply()
	watcher = watcher or CreateFrame("Frame")
	state.since = nil
	ns.SetUpdate(watcher, "Landing", self.db.enabled and OnUpdate or nil)
end

function Landing:OnLogin()
	self:Apply()
end

function Landing:OnOptionChanged()
	self:Apply()
end

Landing.options = {
	{ key = "enabled", type = "toggle", name = L.LANDING_ENABLE, desc = L.LANDING_ENABLE_DESC, new = true },
}

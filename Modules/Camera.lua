-- Cinematic camera: every situation (flight path, conversation, combat, mounted, indoors, resting) gets its own
-- camera setting, and the camera blends smoothly between them. Uses the game's action camera (test_camera*), which
-- only works with "keep character centered" off; every changed setting is put back when the option is turned off.
local _, ns = ...
local L = ns.L

local Camera = ns:NewModule("Camera", {
	title = L.CAMERA_TITLE,
	order = 9.1,
	defaults = {
		enabled = false,
		taxi = true,
		talk = true,
		combat = true,
		mounted = true,
		indoors = true,
		resting = true,
		saved = {}, -- cvar -> { original =, applied = } while the module controls it
	},
})

-- Highest priority first. zoom: distance in yards; shoulder: sideways offset; pad: how far the dynamic pitch
-- tilts the view; rotate: degrees per second around the character.
local SITUATIONS = {
	{ key = "taxi", zoom = 22, shoulder = 0, pad = 0.6, rotate = 4 },
	{ key = "talk", zoom = 5, shoulder = 1.2, pad = 0.2, interact = true },
	{ key = "combat", zoom = 14, shoulder = 0.6, pad = 0.4, enemy = true },
	{ key = "mounted", zoom = 16, shoulder = 0, pad = 0.5 },
	{ key = "indoors", zoom = 7, shoulder = 0.8, pad = 0.2 },
	{ key = "resting", zoom = 8, shoulder = 1, pad = 0.3 },
}
Camera.SITUATIONS = SITUATIONS

local SHOULDER, PAD = "test_cameraOverShoulder", "test_cameraDynamicPitchBaseFovPad"
local ENEMY, INTERACT = "test_cameraTargetFocusEnemyEnable", "test_cameraTargetFocusInteractEnable"
-- Set once while the module runs: without them the action camera does nothing.
local CONTROL = {
	{ "CameraKeepCharacterCentered", "0" },
	{ "CameraReduceUnexpectedMovement", "0" },
	{ "test_cameraDynamicPitch", "1" },
}
local DURATION = 1.2
local DEFAULT_YAW_SPEED = 180

local running, ticker, current
local zoomBefore -- the player's own distance before the first situation that zooms
local rotating = false
local blend -- { from = { shoulder, pad }, to = { shoulder, pad }, start }
local blender

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- The situation with the highest priority that is switched on and active, or nil (the player's own camera).
function Camera.Pick(state, db)
	for _, situation in ipairs(SITUATIONS) do
		if db[situation.key] and state[situation.key] then
			return situation
		end
	end
	return nil
end

-- Smoothstep: slow start, slow end.
function Camera.Ease(t)
	t = math.max(0, math.min(1, t))
	return t * t * (3 - 2 * t)
end

function Camera.Blend(from, to, t)
	return from + (to - from) * Camera.Ease(t)
end

---------------------------------------------------------------------------
-- Settings the module owns: the player's value is kept and put back later
---------------------------------------------------------------------------
local function Set(cvar, value)
	local saved = Camera.db.saved
	if not saved[cvar] then
		saved[cvar] = { original = GetCVar(cvar) }
	end
	value = tostring(value)
	if GetCVar(cvar) ~= value then
		SetCVar(cvar, value)
	end
	saved[cvar].applied = GetCVar(cvar)
end

-- The player's own value of a setting the module may have changed.
local function Original(cvar)
	local saved = Camera.db.saved[cvar]
	if saved then
		return saved.original
	end
	return GetCVar(cvar)
end

-- Puts every changed setting back, unless the player changed it in the meantime.
function Camera.Restore()
	for cvar, state in pairs(Camera.db.saved) do
		if state.original ~= nil and GetCVar(cvar) == state.applied then
			SetCVar(cvar, state.original)
		end
	end
	Camera.db.saved = {}
end

---------------------------------------------------------------------------
-- Moving the camera
---------------------------------------------------------------------------
local function Zoom()
	return ns.Number(GetCameraZoom and GetCameraZoom(), nil)
end

local function ZoomTo(distance)
	local now = Zoom()
	if not now or not distance then
		return
	end
	local delta = distance - now
	if delta > 0.1 then
		CameraZoomOut(delta)
	elseif delta < -0.1 then
		CameraZoomIn(-delta)
	end
end

local function Rotate(degrees)
	if rotating then
		MoveViewLeftStop()
		rotating = false
	end
	if degrees and degrees > 0 then
		local yawSpeed = tonumber(GetCVar("cameraYawMoveSpeed")) or DEFAULT_YAW_SPEED
		MoveViewLeftStart(degrees / (yawSpeed > 0 and yawSpeed or DEFAULT_YAW_SPEED))
		rotating = true
	end
end

local function Number(cvar, fallback)
	return tonumber(GetCVar(cvar)) or fallback
end

local function BlendStep()
	local t = (GetTime() - blend.start) / DURATION
	Set(SHOULDER, Camera.Blend(blend.from[1], blend.to[1], t))
	Set(PAD, Camera.Blend(blend.from[2], blend.to[2], t))
	if t >= 1 then
		blend = nil
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
end

local function BlendTo(shoulder, pad)
	blend = {
		from = { Number(SHOULDER, 0), Number(PAD, 0) },
		to = { shoulder, pad },
		start = GetTime(),
	}
	blender = blender or CreateFrame("Frame")
	ns.SetUpdate(blender, "Camera: blend", BlendStep)
	BlendStep()
end

-- Moves the camera to a situation (nil: back to the player's own camera).
function Camera.Apply(situation)
	if situation == current then
		return
	end
	current = situation
	if situation then
		zoomBefore = zoomBefore or Zoom()
		ZoomTo(situation.zoom)
		BlendTo(situation.shoulder, situation.pad)
		Set(ENEMY, situation.enemy and "1" or "0")
		Set(INTERACT, situation.interact and "1" or "0")
		Rotate(situation.rotate)
	else
		ZoomTo(zoomBefore)
		zoomBefore = nil
		BlendTo(tonumber(Original(SHOULDER)) or 0, tonumber(Original(PAD)) or 0)
		Set(ENEMY, Original(ENEMY) or "0")
		Set(INTERACT, Original(INTERACT) or "0")
		Rotate(nil)
	end
end

---------------------------------------------------------------------------
-- What is going on
---------------------------------------------------------------------------
local function Flag(value)
	return not ns.Secret(value) and value and true or false
end

function Camera.State()
	return {
		taxi = Flag(UnitOnTaxi("player")),
		talk = Flag(UnitExists("npc")),
		combat = Flag(InCombatLockdown()),
		mounted = Flag(IsMounted()),
		indoors = Flag(IsIndoors()),
		resting = Flag(IsResting()),
	}
end

function Camera.Update()
	if running then
		Camera.Apply(Camera.Pick(Camera.State(), Camera.db))
	end
end

-- Conversations open and close between two checks: these events check at once.
local FAST_EVENTS = {
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
	"QUEST_FINISHED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED",
	"PLAYER_UPDATE_RESTING", "ZONE_CHANGED_INDOORS",
}

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Camera.Start()
	if running then
		return
	end
	running = true
	for _, control in ipairs(CONTROL) do
		Set(control[1], control[2])
	end
	for _, event in ipairs(FAST_EVENTS) do
		Camera:RegisterEvent(event, Camera.Update)
	end
	ticker = ns.NewTicker("Camera: situation", 0.25, Camera.Update)
	Camera.Update()
end

function Camera.Stop()
	if not running then
		return
	end
	running = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, event in ipairs(FAST_EVENTS) do
		Camera:UnregisterEvent(event)
	end
	Rotate(nil)
	ZoomTo(zoomBefore)
	zoomBefore, current, blend = nil, nil, nil
	if blender then
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
	Camera.Restore()
end

function Camera:OnLogin()
	if self.db.enabled then
		Camera.Start()
	elseif next(self.db.saved) then
		-- Left over from a session that ended while it ran.
		Camera.Restore()
	end
end

function Camera:OnOptionChanged()
	if self.db.enabled then
		Camera.Start()
		Camera.Update()
	else
		Camera.Stop()
	end
end

Camera.options = {
	{ key = "enabled", type = "toggle", name = L.CAMERA_ENABLE, desc = L.CAMERA_ENABLE_DESC },
	{ key = "taxi", type = "toggle", name = L.CAMERA_TAXI, desc = L.CAMERA_TAXI_DESC, parent = "enabled" },
	{ key = "talk", type = "toggle", name = L.CAMERA_TALK, desc = L.CAMERA_TALK_DESC, parent = "enabled" },
	{ key = "combat", type = "toggle", name = L.CAMERA_COMBAT, desc = L.CAMERA_COMBAT_DESC, parent = "enabled" },
	{ key = "mounted", type = "toggle", name = L.CAMERA_MOUNTED, desc = L.CAMERA_MOUNTED_DESC, parent = "enabled" },
	{ key = "indoors", type = "toggle", name = L.CAMERA_INDOORS, desc = L.CAMERA_INDOORS_DESC, parent = "enabled" },
	{ key = "resting", type = "toggle", name = L.CAMERA_RESTING, desc = L.CAMERA_RESTING_DESC, parent = "enabled" },
}

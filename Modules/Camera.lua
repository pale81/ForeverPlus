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
		close = true,
		saved = {}, -- cvar -> { original =, applied = } while the module controls it
	},
})

-- Highest priority first. zoom: distance in yards; shoulder: sideways offset; pad: how far the dynamic pitch
-- tilts the view. A close, calm over-the-shoulder camera: the situations differ only a little from each other.
local SITUATIONS = {
	{ key = "taxi", zoom = 9, shoulder = 0.6, pad = 0.35 },
	{ key = "talk", zoom = 3.5, shoulder = 1.1, pad = 0.3, interact = true },
	{ key = "combat", zoom = 5.5, shoulder = 0.9, pad = 0.35 },
	{ key = "mounted", zoom = 7, shoulder = 0.7, pad = 0.35 },
	{ key = "indoors", zoom = 3.5, shoulder = 0.9, pad = 0.3 },
	{ key = "resting", zoom = 4, shoulder = 1, pad = 0.3 },
	{ key = "close", zoom = 4.5, shoulder = 1, pad = 0.3 }, -- always: no situation, still close
}
Camera.SITUATIONS = SITUATIONS

local SHOULDER, PAD = "test_cameraOverShoulder", "test_cameraDynamicPitchBaseFovPad"
local INTERACT = "test_cameraTargetFocusInteractEnable"
-- Set once while the module runs: without them the action camera does nothing.
local CONTROL = {
	{ "CameraKeepCharacterCentered", "0" },
	{ "CameraReduceUnexpectedMovement", "0" },
	{ "test_cameraDynamicPitch", "1" },
}
local DURATION = 2.5
local BACK_DURATION = 3 -- back to the player's own camera: slower
local HOLD = 0.6 -- a situation must hold this long before the camera follows (doorways, short flickers)
local MAX_ZOOM_PER_FACTOR = 15 -- the game's farthest distance is this times cameraDistanceMaxZoomFactor
-- An older version lowered the zoom speed for a while; a reload in that moment left it slow.
local OLD_ZOOM_SPEED = "cameraZoomSpeed"

local running, ticker, current
local zoomBefore -- the player's own distance before the first situation that zooms
-- Where the game's camera is headed. GetCameraZoom gives the distance on the way there, so it is only read
-- when the camera rests; the module's and the player's zoom steps are added up here instead.
local zoomTarget
local ownZoom = false -- the module zooms right now (the zoom hooks ignore it)
local blend -- { from = { shoulder, pad, zoom }, to = { shoulder, pad, zoom }, start, duration }
local blender
local hold = {} -- the situation waiting to be followed and since when

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

-- True once the same situation (nil: none) has been picked for HOLD seconds.
function Camera.Settled(waiting, situation, now)
	if not waiting.seen or waiting.situation ~= situation then
		waiting.seen, waiting.situation, waiting.since = true, situation, now
	end
	return now - waiting.since >= HOLD
end

-- The zoom target after a step, kept within the distances the game allows.
function Camera.StepZoom(target, delta, maxZoom)
	return math.max(0, math.min(maxZoom, target + delta))
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

local function MaxZoom()
	return MAX_ZOOM_PER_FACTOR * (tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1)
end

-- Moves the zoom target to a distance in one step (the game glides there at its own zoom speed).
local function ZoomTo(distance)
	if not zoomTarget or not distance then
		return
	end
	distance = Camera.StepZoom(distance, 0, MaxZoom())
	local delta = distance - zoomTarget
	if delta == 0 then
		return
	end
	ownZoom = true
	if delta > 0 then
		CameraZoomOut(delta)
	else
		CameraZoomIn(-delta)
	end
	ownZoom = false
	zoomTarget = distance
end

-- The player zooms (mouse wheel, keys): the target moves along, and a running zoom blend stops.
local function OnPlayerZoom(delta)
	if not running or ownZoom or not zoomTarget then
		return
	end
	zoomTarget = Camera.StepZoom(zoomTarget, delta, MaxZoom())
	if blend then
		blend.to[3] = nil
	end
end

local function Number(cvar, fallback)
	return tonumber(GetCVar(cvar)) or fallback
end

local function BlendStep()
	local t = (GetTime() - blend.start) / blend.duration
	Set(SHOULDER, Camera.Blend(blend.from[1], blend.to[1], t))
	Set(PAD, Camera.Blend(blend.from[2], blend.to[2], t))
	if blend.from[3] and blend.to[3] then
		ZoomTo(Camera.Blend(blend.from[3], blend.to[3], t))
	end
	if t >= 1 then
		blend = nil
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
end

local function BlendTo(shoulder, pad, zoom, duration)
	blend = {
		from = { Number(SHOULDER, 0), Number(PAD, 0), zoomTarget },
		to = { shoulder, pad, zoom },
		start = GetTime(),
		duration = duration,
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
		zoomBefore = zoomBefore or zoomTarget
		BlendTo(situation.shoulder, situation.pad, situation.zoom, DURATION)
		Set(INTERACT, situation.interact and "1" or "0")
	else
		BlendTo(tonumber(Original(SHOULDER)) or 0, tonumber(Original(PAD)) or 0, zoomBefore, BACK_DURATION)
		zoomBefore = nil
		Set(INTERACT, Original(INTERACT) or "0")
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
		close = true,
	}
end

function Camera.Update()
	if not running then
		return
	end
	local situation = Camera.Pick(Camera.State(), Camera.db)
	-- Always asked, so a short flicker back to the current situation starts the wait anew.
	local settled = Camera.Settled(hold, situation, GetTime())
	if situation ~= current and settled then
		Camera.Apply(situation)
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
	local stale = Camera.db.saved[OLD_ZOOM_SPEED]
	if stale then
		if stale.original ~= nil and GetCVar(OLD_ZOOM_SPEED) == stale.applied then
			SetCVar(OLD_ZOOM_SPEED, stale.original)
		end
		Camera.db.saved[OLD_ZOOM_SPEED] = nil
	end
	zoomTarget = Zoom()
	hold = {}
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
	ZoomTo(zoomBefore)
	zoomBefore, zoomTarget, current, blend = nil, nil, nil, nil
	if blender then
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
	Camera.Restore()
end

function Camera:OnLogin()
	hooksecurefunc("CameraZoomIn", ns.Measured("Camera: zoom in", function(amount)
		OnPlayerZoom(-(tonumber(amount) or 1))
	end))
	hooksecurefunc("CameraZoomOut", ns.Measured("Camera: zoom out", function(amount)
		OnPlayerZoom(tonumber(amount) or 1)
	end))
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
	{ key = "close", type = "toggle", name = L.CAMERA_CLOSE, desc = L.CAMERA_CLOSE_DESC, parent = "enabled" },
}

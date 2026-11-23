-- Cinematic camera: the camera stays over the shoulder at the player's own distance and changes only in a few
-- situations (conversation, indoors, flight path, teleport), blending smoothly. Uses the game's action camera
-- (test_camera*), which only works with "keep character centered" off; every changed setting is put back when the
-- option is turned off.
local _, ns = ...
local L = ns.L

local Camera = ns:NewModule("Camera", {
	title = L.CAMERA_TITLE,
	order = 9.1,
	defaults = {
		enabled = false,
		taxi = true,
		teleport = true,
		talk = true,
		combat = true,
		mounted = true,
		indoors = true,
		resting = true,
		close = false,
		move = false,
		warnOnce = true,
		-- style (no default, so older saved settings are recognised): 2 since the camera keeps the own distance
		saved = {}, -- cvar -> { original =, applied = } while the module controls it
	},
	charDefaults = {
		warningSeen = false, -- Blizzard's warning about experimental camera settings was shown to this character
	},
})

-- Highest priority first. zoom: distance in yards (nil: the player's own distance); shoulder: sideways offset;
-- pad: how far the dynamic pitch tilts the view; move: closer standing still, further while moving (option);
-- rotate: degrees per second around the character; always: no option, applies when nothing else does.
local SITUATIONS = {
	{ key = "taxi", zoom = 12, shoulder = 0, pad = 0.35 },
	{ key = "teleport", shoulder = 0, pad = 0.3, rotate = 45 },
	{ key = "talk", zoom = 7, shoulder = 1.6, pad = 0.3 },
	{ key = "combat", shoulder = 0.6, pad = 0.35 },
	{ key = "mounted", shoulder = 0.4, pad = 0.35 },
	{ key = "indoors", zoom = 5.5, shoulder = 1, pad = 0.3, move = true },
	{ key = "resting", shoulder = 1, pad = 0.3 },
	{ key = "close", zoom = 5, shoulder = 1, pad = 0.3, move = true },
	{ key = "outdoors", shoulder = 1, pad = 0.3, always = true },
}
Camera.SITUATIONS = SITUATIONS

-- Hearthstone, Astral Recall and the mage teleports: the camera circles the character while they are cast.
local TELEPORTS = { [8690] = true, [556] = true, [3561] = true, [3562] = true, [3563] = true, [3565] = true,
	[3566] = true, [3567] = true }

local SHOULDER, PAD = "test_cameraOverShoulder", "test_cameraDynamicPitchBaseFovPad"
-- Set once while the module runs: without them the action camera does nothing.
local CONTROL = {
	{ "CameraKeepCharacterCentered", "0" },
	{ "CameraReduceUnexpectedMovement", "0" },
	{ "test_cameraDynamicPitch", "1" },
}
local MANAGED = { [SHOULDER] = true, [PAD] = true }
for _, control in ipairs(CONTROL) do
	MANAGED[control[1]] = true
end
local DURATION = 2.5
local BACK_DURATION = 3 -- back to the player's own distance: slower
local MOVE_DURATION = 1.8 -- only the movement changed: the distance glides alone
local BLEND_INTERVAL = 0.05 -- 20 Hz: SetCVar fires CVAR_UPDATE and can stall when called every frame
local SHOULDER_STEP, PAD_STEP, ZOOM_STEP = 0.02, 0.01, 0.05
local STILL_IN, MOVE_OUT = -0.6, 0.9 -- distance standing still and while moving, against the situation's
local HOLD = 0.6 -- a situation must hold this long before the camera follows (doorways, short flickers)
local MAX_ZOOM_PER_FACTOR = 15 -- the game's farthest distance is this times cameraDistanceMaxZoomFactor
local DEFAULT_YAW_SPEED = 180

local running, ticker, current
local currentMoving = false
local playerZoom = 0 -- the player's own zoom steps since the situation began
local zoomBefore -- the player's own distance before the first situation that zooms
-- Where the game's camera is headed. GetCameraZoom gives the distance on the way there, so it is only read
-- when the module starts; the module's and the player's zoom steps are added up here instead.
local zoomTarget
local ownZoom = false -- the module zooms right now (the zoom hooks ignore it)
local rotating = false
local blend -- { from = { shoulder, pad, zoom }, to = { shoulder, pad, zoom }, start, duration }
local blender
local hold = {} -- the shot waiting to be followed and since when

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- The situation with the highest priority that is switched on and active, or nil.
function Camera.Pick(state, db)
	for _, situation in ipairs(SITUATIONS) do
		if situation.always or (db[situation.key] and state[situation.key]) then
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

-- Whether moving changes the distance in this situation.
local function Moves(situation, moveOn)
	return moveOn and situation.move and situation.zoom and true or false
end

-- The distance of a situation (nil: the player's own); with the option a little closer standing still and a
-- little further while moving.
function Camera.ZoomFor(situation, moving, moveOn)
	if not Moves(situation, moveOn) then
		return situation.zoom
	end
	return situation.zoom + (moving and MOVE_OUT or STILL_IN)
end

-- What the camera shows: the situation, and whether moving matters in it.
function Camera.ShotKey(situation, moving, moveOn)
	if not situation then
		return ""
	end
	return situation.key .. ((Moves(situation, moveOn) and moving) and ":moving" or "")
end

-- True once the same shot (see ShotKey) has been picked for HOLD seconds.
function Camera.Settled(waiting, shot, now)
	if not waiting.seen or waiting.shot ~= shot then
		waiting.seen, waiting.shot, waiting.since = true, shot, now
	end
	return now - waiting.since >= HOLD
end

-- The zoom target after a step, kept within the distances the game allows.
function Camera.StepZoom(target, delta, maxZoom)
	return math.max(0, math.min(maxZoom, target + delta))
end

function Camera.IsTeleport(spellID)
	return spellID ~= nil and TELEPORTS[spellID] == true
end

---------------------------------------------------------------------------
-- Settings the module owns: the player's value is kept and put back later
---------------------------------------------------------------------------
local function Set(cvar, value)
	local saved = Camera.db.saved
	local state = saved[cvar]
	if not state then
		state = { original = GetCVar(cvar) }
		saved[cvar] = state
	end
	value = tostring(value)
	if state.applied == value then
		return false
	end
	if GetCVar(cvar) ~= value then
		SetCVar(cvar, value)
	end
	state.applied = GetCVar(cvar)
	return true
end

-- The player's own value of a setting the module may have changed.
local function Original(cvar)
	local saved = Camera.db.saved[cvar]
	if saved then
		return saved.original
	end
	return GetCVar(cvar)
end

local function PutBack(cvar, state)
	if state.original ~= nil and GetCVar(cvar) == state.applied then
		SetCVar(cvar, state.original)
	end
end

-- Puts every changed setting back, unless the player changed it in the meantime.
function Camera.Restore()
	for cvar, state in pairs(Camera.db.saved) do
		PutBack(cvar, state)
	end
	Camera.db.saved = {}
end

-- Settings older versions changed and this one no longer does (zoom speed, turning towards targets).
local function RestoreUnmanaged()
	local saved = Camera.db.saved
	for cvar, state in pairs(saved) do
		if not MANAGED[cvar] then
			PutBack(cvar, state)
			saved[cvar] = nil
		end
	end
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
local function ZoomTo(distance, maxZoom)
	if not zoomTarget or not distance then
		return
	end
	distance = Camera.StepZoom(distance, 0, maxZoom or MaxZoom())
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
	playerZoom = playerZoom + delta
	if blend then
		blend.to[3] = nil
	end
end

local function Rotate(degrees)
	if rotating then
		MoveViewLeftStop()
		rotating = false
	end
	if degrees then
		local yawSpeed = tonumber(GetCVar("cameraYawMoveSpeed")) or DEFAULT_YAW_SPEED
		MoveViewLeftStart(degrees / (yawSpeed > 0 and yawSpeed or DEFAULT_YAW_SPEED))
		rotating = true
	end
end

local function Number(cvar, fallback)
	return tonumber(GetCVar(cvar)) or fallback
end

local function Quantize(value, step)
	return math.floor(value / step + 0.5) * step
end

local function BlendStep()
	local now = GetTime()
	local t = (now - blend.start) / blend.duration
	local done = t >= 1
	if not done and blend.last and now - blend.last < BLEND_INTERVAL then
		return
	end
	blend.last = now
	-- Stagger shoulder and pad writes on intermediate ticks so at most one SetCVar runs per frame.
	local wroteCVar = false
	if done or blend.from[1] ~= blend.to[1] then
		local value = done and blend.to[1] or Quantize(Camera.Blend(blend.from[1], blend.to[1], t), SHOULDER_STEP)
		if Set(SHOULDER, value) then
			wroteCVar = true
		end
	end
	if (done or blend.from[2] ~= blend.to[2]) and (done or not wroteCVar) then
		local value = done and blend.to[2] or Quantize(Camera.Blend(blend.from[2], blend.to[2], t), PAD_STEP)
		Set(PAD, value)
	end
	if blend.from[3] and blend.to[3] then
		local nextZoom = done and blend.to[3] or Camera.Blend(blend.from[3], blend.to[3], t)
		if done or not zoomTarget or math.abs(nextZoom - zoomTarget) >= ZOOM_STEP then
			ZoomTo(nextZoom, blend.maxZoom)
		end
	end
	if done then
		blend = nil
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
end

local function BlendTo(shoulder, pad, zoom, duration)
	local fromShoulder, fromPad = Number(SHOULDER, 0), Number(PAD, 0)
	local fromZoom = zoomTarget
	if fromShoulder == shoulder and fromPad == pad and (not zoom or zoom == fromZoom) then
		Set(SHOULDER, shoulder)
		Set(PAD, pad)
		blend = nil
		if blender then
			ns.SetUpdate(blender, "Camera: blend", nil)
		end
		return
	end
	blend = {
		from = { fromShoulder, fromPad, fromZoom },
		to = { shoulder, pad, zoom },
		start = GetTime(),
		last = GetTime(),
		duration = duration,
		maxZoom = MaxZoom(),
	}
	blender = blender or CreateFrame("Frame")
	ns.SetUpdate(blender, "Camera: blend", BlendStep)
end

-- Moves the camera to a situation (nil: back to the player's own camera).
function Camera.Apply(situation, moving)
	moving = moving and true or false
	local moveOn = Camera.db.move
	if situation == current then
		if not situation or not Moves(situation, moveOn) or moving == currentMoving then
			return
		end
		-- Only the movement changed: the distance glides, the player's own zoom steps stay.
		currentMoving = moving
		BlendTo(situation.shoulder, situation.pad, Camera.ZoomFor(situation, moving, moveOn) + playerZoom,
			MOVE_DURATION)
		return
	end
	current, currentMoving, playerZoom = situation, moving, 0
	if not situation then
		BlendTo(tonumber(Original(SHOULDER)) or 0, tonumber(Original(PAD)) or 0, zoomBefore, BACK_DURATION)
		zoomBefore = nil
		Rotate(nil)
		return
	end
	local zoom = Camera.ZoomFor(situation, moving, moveOn)
	local duration = DURATION
	if zoom then
		zoomBefore = zoomBefore or zoomTarget
	elseif zoomBefore then
		-- A situation at the player's own distance: back there, slowly.
		zoom, zoomBefore, duration = zoomBefore, nil, BACK_DURATION
	end
	BlendTo(situation.shoulder, situation.pad, zoom, duration)
	Rotate(situation.rotate)
end

---------------------------------------------------------------------------
-- What is going on
---------------------------------------------------------------------------
local function Flag(value)
	return not ns.Secret(value) and value and true or false
end

local function CastingTeleport()
	local spellID = select(9, UnitCastingInfo("player"))
	return Camera.IsTeleport(ns.Number(spellID, nil))
end

local stateCache = { close = true }

function Camera.State()
	stateCache.taxi = Flag(UnitOnTaxi("player"))
	stateCache.teleport = CastingTeleport()
	stateCache.talk = Flag(UnitExists("npc"))
	stateCache.combat = Flag(InCombatLockdown())
	stateCache.mounted = Flag(IsMounted())
	stateCache.indoors = Flag(IsIndoors())
	stateCache.resting = Flag(IsResting())
	stateCache.close = true
	stateCache.moving = ns.Number((GetUnitSpeed("player")), 0) > 0
	return stateCache
end

function Camera.Update()
	if not running then
		return
	end
	local state = Camera.State()
	local situation = Camera.Pick(state, Camera.db)
	-- Always asked, so a short flicker back to the current shot starts the wait anew.
	if Camera.Settled(hold, Camera.ShotKey(situation, state.moving, Camera.db.move), GetTime()) then
		Camera.Apply(situation, state.moving)
	end
end

-- Conversations and casts start and end between two checks: these events check at once.
local FAST_EVENTS = {
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
	"QUEST_FINISHED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_INDOORS", "UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
}

-- A loading screen (after a teleport) must not leave the camera turning.
local function OnLeavingWorld()
	Rotate(nil)
end

---------------------------------------------------------------------------
-- Blizzard's warning about experimental camera settings: once per character
---------------------------------------------------------------------------
local WARNING, WARNING_EVENT = "EXPERIMENTAL_CVAR_WARNING", "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
local silenced = {} -- frames of the game that no longer hear the event

-- "Accept" changes nothing in the game, so not showing the warning again is the same as accepting it. The game's
-- frame stops hearing the event instead of the popup being hidden: hiding it from addon code would taint it.
function Camera.SilenceWarning(silence)
	if silence then
		if next(silenced) or not GetFramesRegisteredForEvent then
			return
		end
		for _, frame in ipairs({ GetFramesRegisteredForEvent(WARNING_EVENT) }) do
			frame:UnregisterEvent(WARNING_EVENT)
			silenced[#silenced + 1] = frame
		end
	else
		for _, frame in ipairs(silenced) do
			frame:RegisterEvent(WARNING_EVENT)
		end
		wipe(silenced)
	end
end

function Camera.OnPopupShown(which)
	if which == WARNING then
		Camera.cdb.warningSeen = true
		Camera.SilenceWarning(Camera.db.warnOnce)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Camera.Start()
	if running then
		return
	end
	running = true
	RestoreUnmanaged()
	zoomTarget = Zoom()
	hold = {}
	for _, control in ipairs(CONTROL) do
		Set(control[1], control[2])
	end
	for _, event in ipairs(FAST_EVENTS) do
		Camera:RegisterEvent(event, Camera.Update)
	end
	Camera:RegisterEvent("PLAYER_LEAVING_WORLD", OnLeavingWorld)
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
	Camera:UnregisterEvent("PLAYER_LEAVING_WORLD")
	Rotate(nil)
	ZoomTo(zoomBefore)
	zoomBefore, zoomTarget, current, blend = nil, nil, nil, nil
	currentMoving, playerZoom = false, 0
	if blender then
		ns.SetUpdate(blender, "Camera: blend", nil)
	end
	Camera.Restore()
end

function Camera:OnInitialize()
	-- Before the camera settings are set at login, which is what brings the warning.
	Camera.SilenceWarning(self.db.warnOnce and self.cdb.warningSeen)
	hooksecurefunc("StaticPopup_Show", ns.Measured("Camera: popup", Camera.OnPopupShown))
end

function Camera:OnLogin()
	if (self.db.style or 1) < 2 then
		-- The first versions kept the camera close everywhere; now it keeps the player's own distance.
		self.db.close, self.db.style = false, 2
	end
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
	Camera.SilenceWarning(self.db.warnOnce and self.cdb.warningSeen)
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
	{ key = "teleport", type = "toggle", name = L.CAMERA_TELEPORT, desc = L.CAMERA_TELEPORT_DESC, parent = "enabled" },
	{ key = "talk", type = "toggle", name = L.CAMERA_TALK, desc = L.CAMERA_TALK_DESC, parent = "enabled" },
	{ key = "combat", type = "toggle", name = L.CAMERA_COMBAT, desc = L.CAMERA_COMBAT_DESC, parent = "enabled" },
	{ key = "mounted", type = "toggle", name = L.CAMERA_MOUNTED, desc = L.CAMERA_MOUNTED_DESC, parent = "enabled" },
	{ key = "indoors", type = "toggle", name = L.CAMERA_INDOORS, desc = L.CAMERA_INDOORS_DESC, parent = "enabled" },
	{ key = "resting", type = "toggle", name = L.CAMERA_RESTING, desc = L.CAMERA_RESTING_DESC, parent = "enabled" },
	{ key = "close", type = "toggle", name = L.CAMERA_CLOSE, desc = L.CAMERA_CLOSE_DESC, parent = "enabled" },
	{ key = "move", type = "toggle", name = L.CAMERA_MOVE, desc = L.CAMERA_MOVE_DESC, parent = "enabled" },
	{ key = "warnOnce", type = "toggle", name = L.CAMERA_WARN_ONCE, desc = L.CAMERA_WARN_ONCE_DESC },
}

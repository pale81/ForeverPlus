-- Guiding Wind: a subtle directional gust across the screen pointing toward the active waypoint (or corpse),
-- with zone-matched biome particles and an optional soft wind sound.
local _, ns = ...
local L = ns.L

local GuidingWind = ns:NewModule("GuidingWind", {
	title = L.WIND_TITLE,
	order = 5.36,
	defaults = {
		enabled = true,
		autoGusts = true,
		interval = 14,
		biomeParticles = true,
		sound = true,
		strength = 75,
	},
})

local TEXTURE = [[Interface\AddOns\ForeverPlus\Media\GuidingWind]]
local PIXEL = 1 / 256

-- UV tiles in Media/GuidingWind.tga (256x256) with 1px inset against bilinear bleed.
local WISP_PRIMARY = { PIXEL, 1 - PIXEL, PIXEL, 0.25 - PIXEL }
local WISP_TWIN = { PIXEL, 1 - PIXEL, 0.25 + PIXEL, 0.50 - PIXEL }
local WISP_CURL = { 0.50 + PIXEL, 1 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }
local TILE_LEAF = { PIXEL, 0.25 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_SNOW = { 0.25 + PIXEL, 0.50 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_DUST = { 0.50 + PIXEL, 0.75 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_EMBER = { 0.75 + PIXEL, 1 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_SPORE = { PIXEL, 0.25 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }
local TILE_PETAL = { 0.25 + PIXEL, 0.50 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }

-- Real WoW Forever wind-gust one-shots (Data/EmitterSounds.lua: fx_windgust_oneshot_01..07.ogg).
local WIND_SOUNDS = { 982361, 982363, 982365, 982367, 982369, 982371, 982373 }
local SOUND_COOLDOWN = 0.6

local BIOMES = {
	forest = {
		wind = { 0.90, 0.97, 0.88 },
		particle = { 0.54, 0.80, 0.36 },
		tile = TILE_LEAF,
		blend = "BLEND",
		spin = 2.4,
		lift = -0.025,
		size = 1.00,
		alpha = 0.88,
	},
	autumn = {
		wind = { 0.98, 0.93, 0.82 },
		particle = { 0.90, 0.60, 0.24 },
		tile = TILE_PETAL,
		blend = "BLEND",
		spin = 2.6,
		lift = -0.02,
		size = 0.95,
		alpha = 0.86,
	},
	snow = {
		wind = { 0.86, 0.94, 1.00 },
		particle = { 0.94, 0.98, 1.00 },
		tile = TILE_SNOW,
		blend = "ADD",
		spin = 1.1,
		lift = -0.035,
		size = 0.92,
		alpha = 0.82,
	},
	desert = {
		wind = { 0.98, 0.90, 0.74 },
		particle = { 0.88, 0.74, 0.50 },
		tile = TILE_DUST,
		blend = "BLEND",
		spin = 1.4,
		lift = 0.01,
		size = 1.15,
		alpha = 0.76,
	},
	volcanic = {
		wind = { 0.96, 0.76, 0.60 },
		particle = { 1.00, 0.56, 0.18 },
		tile = TILE_EMBER,
		blend = "ADD",
		spin = 0.7,
		lift = 0.10,
		size = 0.84,
		alpha = 0.92,
	},
	marsh = {
		wind = { 0.78, 0.95, 0.86 },
		particle = { 0.74, 1.00, 0.52 },
		tile = TILE_SPORE,
		blend = "ADD",
		spin = 0.4,
		lift = 0.055,
		size = 0.86,
		alpha = 0.84,
		pulse = true,
	},
	neutral = {
		wind = { 0.92, 0.96, 1.00 },
		particle = { 0.90, 0.95, 1.00 },
		tile = TILE_SPORE,
		blend = "ADD",
		spin = 0.3,
		lift = 0.02,
		size = 0.62,
		alpha = 0.58,
	},
}

-- UiMapID -> biome key (Classic & WoW Forever outdoor zones and capitals).
local ZONE_BIOMES = {
	-- Forests
	[1425] = "forest", -- The Hinterlands
	[1429] = "forest", -- Elwynn Forest
	[1434] = "forest", -- Stranglethorn Vale
	[1438] = "forest", -- Teldrassil
	[1440] = "forest", -- Ashenvale
	[1444] = "forest", -- Feralas
	[1457] = "forest", -- Darnassus
	[2482] = "forest", -- Mount Hyjal
	[2652] = "forest", -- Shen'dralas
	-- Meadows, valleys & autumn groves
	[1412] = "autumn", -- Mulgore
	[1417] = "autumn", -- Arathi Highlands
	[1424] = "autumn", -- Hillsbrad Foothills
	[1432] = "autumn", -- Loch Modan
	[1433] = "autumn", -- Redridge Mountains
	[1447] = "autumn", -- Azshara
	[1453] = "autumn", -- Stormwind City
	[1456] = "autumn", -- Thunder Bluff
	[2521] = "autumn", -- Zephras Isle
	[2548] = "autumn", -- Riverglades
	-- Snow & alpine peaks
	[1416] = "snow", -- Alterac Mountains
	[1426] = "snow", -- Dun Morogh
	[1452] = "snow", -- Winterspring
	[1455] = "snow", -- Ironforge
	-- Deserts, canyons & steppes
	[1411] = "desert", -- Durotar
	[1413] = "desert", -- The Barrens
	[1418] = "desert", -- Badlands
	[1436] = "desert", -- Westfall
	[1441] = "desert", -- Thousand Needles
	[1442] = "desert", -- Stonetalon Mountains
	[1443] = "desert", -- Desolace
	[1446] = "desert", -- Tanaris
	[1451] = "desert", -- Silithus
	[1454] = "desert", -- Orgrimmar
	-- Volcanic & scorched lands
	[1419] = "volcanic", -- Blasted Lands
	[1427] = "volcanic", -- Searing Gorge
	[1428] = "volcanic", -- Burning Steppes
	-- Marshes, shadowed woods & blighted zones
	[1420] = "marsh", -- Tirisfal Glades
	[1421] = "marsh", -- Silverpine Forest
	[1422] = "marsh", -- Western Plaguelands
	[1423] = "marsh", -- Eastern Plaguelands
	[1431] = "marsh", -- Duskwood
	[1435] = "marsh", -- Swamp of Sorrows
	[1437] = "marsh", -- Wetlands
	[1439] = "marsh", -- Darkshore
	[1445] = "marsh", -- Dustwallow Marsh
	[1448] = "marsh", -- Felwood
	[1449] = "marsh", -- Un'Goro Crater
	[1458] = "marsh", -- Undercity
}

-- Ribbon templates: { lane, delay, duration, length, thickness, amp, freq, phase, alpha, variant }
local RIBBON_SPECS = {
	{ -0.24, 0.00, 1.48, 280, 34, 0.026, 2.0, 0.2, 0.42, 1 },
	{  0.22, 0.11, 1.55, 310, 38, 0.030, 1.8, 1.5, 0.40, 2 },
	{ -0.10, 0.22, 1.42, 240, 28, 0.022, 2.2, 2.8, 0.36, 1 },
	{  0.12, 0.31, 1.52, 270, 32, 0.028, 1.9, 4.1, 0.38, 2 },
	{ -0.32, 0.39, 1.45, 225, 26, 0.024, 2.1, 0.9, 0.30, 1 },
	{  0.31, 0.48, 1.50, 235, 28, 0.025, 2.0, 3.3, 0.32, 2 },
}

-- Particle templates: { lane, delay, duration, size, amp, freq, phase, spinDir }
local PARTICLE_SPECS = {
	{ -0.27, 0.05, 1.62, 18, 0.035, 2.3, 0.4,  1 },
	{  0.25, 0.14, 1.68, 16, 0.032, 2.1, 1.9, -1 },
	{ -0.14, 0.23, 1.58, 15, 0.028, 2.5, 3.1,  1 },
	{  0.16, 0.30, 1.65, 19, 0.038, 1.9, 4.5, -1 },
	{ -0.33, 0.38, 1.55, 14, 0.030, 2.2, 1.1, -1 },
	{  0.30, 0.44, 1.60, 17, 0.034, 2.4, 2.6,  1 },
	{ -0.06, 0.52, 1.52, 13, 0.026, 2.6, 5.2,  1 },
	{  0.07, 0.58, 1.56, 15, 0.029, 2.0, 0.8, -1 },
}

local root, ribbons, particles
local gust -- { age, angle, worldBearing, biome, strength, manual, live }
local autoTimer
local soundVariants = {}
local lastSoundAt, lastSoundHandle = 0, nil

-- Normalizes an angle in radians into (-pi, pi].
function GuidingWind.NormalizeAngle(angle)
	angle = (angle or 0) % (2 * math.pi)
	if angle > math.pi then
		angle = angle - 2 * math.pi
	end
	return angle
end

-- Screen-space unit vector and coarse direction label from relative bearing angle:
-- 0 = straight ahead (up), +pi/2 = left, -pi/2 = right, +-pi = behind (down).
function GuidingWind.DirectionVector(angle)
	local norm = GuidingWind.NormalizeAngle(angle)
	local dx = -math.sin(norm)
	local dy = math.cos(norm)
	local absAngle = math.abs(norm)
	local mode
	if absAngle <= math.pi * 0.25 then
		mode = "ahead"
	elseif absAngle >= math.pi * 0.75 then
		mode = "behind"
	elseif norm > 0 then
		mode = "left"
	else
		mode = "right"
	end
	return dx, dy, mode, norm
end

-- Resolves the biome key for a UiMapID (walking up parentMapID for sub-maps/caves).
function GuidingWind.BiomeForMap(mapID)
	local id = ns.Number(mapID)
	local depth = 0
	while id and id > 0 and depth < 4 do
		local biome = ZONE_BIOMES[id]
		if biome then
			return biome
		end
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
		if type(info) ~= "table" or ns.Secret(info) then
			break
		end
		id = ns.Number(info.parentMapID)
		depth = depth + 1
	end
	return "neutral"
end

function GuidingWind.CurrentBiome()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	return GuidingWind.BiomeForMap(mapID)
end

function GuidingWind.HidesWaypointArrow()
	return GuidingWind.db and GuidingWind.db.enabled and true or false
end

local function DrawSoundIndex()
	local count = #WIND_SOUNDS
	local remaining = soundVariants.remaining
	local first = 1
	if not remaining then
		for index = 1, count do
			soundVariants[index] = index
		end
		remaining = count
	elseif remaining == 0 then
		remaining = count
		first = 2
	end
	local index = math.random(first, remaining)
	local choice = soundVariants[index]
	soundVariants[index], soundVariants[remaining] = soundVariants[remaining], choice
	soundVariants.remaining = remaining - 1
	return choice
end

local function StopGustSound()
	if lastSoundHandle and StopSound then
		StopSound(lastSoundHandle)
		lastSoundHandle = nil
	end
end

local function PlayWindSound()
	if not (GuidingWind.db and GuidingWind.db.sound) then
		return
	end
	local now = ns.Number(GetTime(), 0)
	if now - lastSoundAt < SOUND_COOLDOWN then
		return
	end
	lastSoundAt = now
	local fileID = WIND_SOUNDS[DrawSoundIndex()]
	if fileID and PlaySoundFile then
		local ok, handle = PlaySoundFile(fileID, "SFX")
		if ok then
			lastSoundHandle = handle
		end
	end
end

local function RootSize()
	if not root then
		return 1200, 800
	end
	local w, h = root:GetSize()
	w, h = ns.Number(w), ns.Number(h)
	if not w or w < 100 or not h or h < 100 then
		return 1200, 800
	end
	return w, h
end

-- Evaluates normalized screen coordinates (0..1, 0..1) and perspective scale along a gust path.
-- Ahead: streams rise from flanking sides toward a gentle upper horizon with depth foreshortening.
-- Left/Right: streams sweep gracefully across the viewport in target direction.
-- Behind: streams curve around the player on the nearer side and pull back downward.
local function EvaluateTrack(lane, amp, freq, phase, p, angle, extraLift)
	local dirX = -math.sin(angle)
	local dirY = math.cos(angle)
	local perpX = -dirY
	local perpY = dirX

	local forwardness = math.max(0, dirY)
	local backwardness = math.max(0, -dirY - 0.25) / 0.75

	local travel = 0.56 - 0.08 * forwardness
	local ease = p * (1.25 - 0.25 * p)
	local spread = 1.0 - 0.44 * forwardness * ease

	local centerX = 0.50
	local centerY = 0.48 - 0.05 * forwardness + 0.04 * backwardness

	local x = centerX + dirX * (ease - 0.50) * travel + perpX * (lane * spread)
	local y = centerY + dirY * (ease - 0.50) * travel + perpY * (lane * spread)

	-- Keep ahead gusts slightly out of the character's exact center while rising forward.
	if forwardness > 0 then
		local sideSign = lane < 0 and -1 or 1
		x = x + sideSign * 0.055 * forwardness * (1 - 0.55 * ease)
		y = y + (ease - 0.35) * 0.14 * forwardness
	end

	-- Curving return arc when the target lies behind the player.
	if backwardness > 0 then
		local turnSign = angle >= 0 and -1 or 1
		local arc = math.sin(ease * math.pi)
		x = x + turnSign * 0.17 * backwardness * arc
		y = y + 0.07 * backwardness * (1 - 2 * ease) * (1 - arc * 0.5)
	end

	local wave = math.sin(ease * freq * math.pi + phase) * amp
	x = x + perpX * wave
	y = y + perpY * wave + (extraLift or 0) * ease

	local scale = 1.0 - 0.34 * forwardness * ease + 0.08 * backwardness * ease
	return x, y, scale
end

local function HideGust()
	gust = nil
	if ribbons then
		for _, ribbon in ipairs(ribbons) do
			ribbon.texture:Hide()
		end
	end
	if particles then
		for _, particle in ipairs(particles) do
			particle.texture:Hide()
		end
	end
	if root then
		root:Hide()
	end
end

local function UpdateGust(_, delta)
	if not gust then
		HideGust()
		return
	end
	delta = math.min(ns.Number(delta, 0), 0.1)
	gust.age = gust.age + delta

	if gust.live and gust.worldBearing then
		local currentFacing = ns.Number(GetPlayerFacing())
		if currentFacing then
			gust.angle = GuidingWind.NormalizeAngle(gust.worldBearing - currentFacing)
		end
	end

	local w, h = RootSize()
	local uiScale = math.min(w / 1200, h / 800)
	local angle = gust.angle
	local strength = gust.strength
	local biome = gust.biome
	local active = false

	for _, ribbon in ipairs(ribbons) do
		local t = gust.age - ribbon.delay
		if t > 0 and t < ribbon.duration then
			active = true
			local p = t / ribbon.duration
			local x, y, depthScale = EvaluateTrack(ribbon.lane, ribbon.amp, ribbon.freq, ribbon.phase, p, angle, 0)
			local pNext = math.min(1, p + 0.025)
			local nx, ny = EvaluateTrack(ribbon.lane, ribbon.amp, ribbon.freq, ribbon.phase, pNext, angle, 0)
			local rot = math.atan2((ny - y) * h, (nx - x) * w)
			local envelope = math.sin(p * math.pi)
			local alpha = ribbon.alpha * strength * (envelope ^ 0.85)
			local scale = uiScale * depthScale

			ribbon.texture:SetSize(ribbon.length * scale, ribbon.thickness * scale)
			ribbon.texture:ClearAllPoints()
			ribbon.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
			ribbon.texture:SetRotation(rot)
			ribbon.texture:SetAlpha(alpha)
			ribbon.texture:Show()
		elseif t <= 0 then
			active = true
			ribbon.texture:Hide()
		else
			ribbon.texture:Hide()
		end
	end

	if gust.showParticles then
		for _, particle in ipairs(particles) do
			local t = gust.age - particle.delay
			if t > 0 and t < particle.duration then
				active = true
				local p = t / particle.duration
				local x, y, depthScale = EvaluateTrack(
					particle.lane, particle.amp, particle.freq, particle.phase, p, angle, biome.lift
				)
				local envelope = math.sin(p * math.pi)
				local pulse = biome.pulse and (0.65 + 0.35 * math.sin(t * 7 + particle.phase)) or 1
				local alpha = biome.alpha * strength * (envelope ^ 0.8) * pulse
				local size = particle.size * biome.size * uiScale * depthScale

				particle.texture:SetSize(size, size)
				particle.texture:ClearAllPoints()
				particle.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
				particle.texture:SetRotation(particle.startRot + t * biome.spin * particle.spinDir)
				particle.texture:SetAlpha(alpha)
				particle.texture:Show()
			elseif t <= 0 then
				active = true
				particle.texture:Hide()
			else
				particle.texture:Hide()
			end
		end
	end

	if not active then
		HideGust()
	end
end

local function EnsureOverlay()
	if root then
		return
	end
	-- Parent to WorldFrame so Guiding Wind stays visible while Wanderlust hides UIParent.
	local parent = WorldFrame or UIParent
	root = CreateFrame("Frame", "ForeverPlusGuidingWind", parent)
	root:SetAllPoints(parent)
	root:SetFrameStrata("LOW")
	root:EnableMouse(false)

	ribbons = {}
	for i, spec in ipairs(RIBBON_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(TEXTURE)
		tex:SetBlendMode("ADD")
		tex:Hide()
		ribbons[i] = {
			texture = tex,
			lane = spec[1],
			delay = spec[2],
			duration = spec[3],
			length = spec[4],
			thickness = spec[5],
			amp = spec[6],
			freq = spec[7],
			phase = spec[8],
			alpha = spec[9],
			variant = spec[10],
		}
	end

	particles = {}
	for i, spec in ipairs(PARTICLE_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 1)
		tex:SetTexture(TEXTURE)
		tex:Hide()
		particles[i] = {
			texture = tex,
			lane = spec[1],
			delay = spec[2],
			duration = spec[3],
			size = spec[4],
			amp = spec[5],
			freq = spec[6],
			phase = spec[7],
			spinDir = spec[8],
			startRot = 0,
		}
	end

	ns.SetUpdate(root, "GuidingWind: gust", UpdateGust)
	root:Hide()
end

local function StartGust(angle, options)
	options = options or {}
	EnsureOverlay()

	local normAngle = GuidingWind.NormalizeAngle(angle)
	local biomeKey = options.biome or GuidingWind.CurrentBiome()
	local biome = BIOMES[biomeKey] or BIOMES.neutral
	local strength = math.max(0.2, math.min(1.0, (GuidingWind.db.strength or 75) / 100))
	local showParticles = GuidingWind.db.biomeParticles and true or false
	local backward = math.cos(normAngle) < -0.35

	local worldBearing
	if options.live then
		local facing = ns.Number(GetPlayerFacing())
		if facing then
			worldBearing = normAngle + facing
		end
	end

	for i, ribbon in ipairs(ribbons) do
		local coords
		if backward and i % 3 == 0 then
			coords = WISP_CURL
		elseif ribbon.variant == 2 then
			coords = WISP_TWIN
		else
			coords = WISP_PRIMARY
		end
		ribbon.texture:SetTexCoord(unpack(coords))
		ribbon.texture:SetVertexColor(unpack(biome.wind))
		ribbon.texture:SetAlpha(0)
		ribbon.texture:Hide()
	end

	for _, particle in ipairs(particles) do
		particle.texture:SetTexCoord(unpack(biome.tile))
		particle.texture:SetBlendMode(biome.blend)
		particle.texture:SetVertexColor(unpack(biome.particle))
		particle.texture:SetAlpha(0)
		particle.texture:Hide()
		particle.startRot = math.random() * math.pi * 2
	end

	gust = {
		age = 0,
		angle = normAngle,
		worldBearing = worldBearing,
		biome = biome,
		biomeKey = biomeKey,
		strength = strength,
		showParticles = showParticles,
		manual = options.manual and true or false,
		live = options.live and true or false,
	}

	root:Show()
	UpdateGust(root, 0)
	if options.manual then
		PlayWindSound()
	end
	return true
end

local function CancelAutoTimer()
	if autoTimer then
		autoTimer:Cancel()
		autoTimer = nil
	end
end

local function IsBlockedForAuto()
	if InCombatLockdown() then
		return true
	end
	local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
	if not ns.Secret(onTaxi) and onTaxi then
		return true
	end
	if WorldMapFrame and not WorldMapFrame:IsForbidden() and WorldMapFrame:IsShown() then
		return true
	end
	return false
end

local function InInstanceWithoutDirection()
	local inInstance = IsInInstance and IsInInstance()
	if not ns.Secret(inInstance) and inInstance then
		return ns.Number(GetPlayerFacing()) == nil
	end
	return false
end

local ScheduleAutoGust

local function AutoGustTick()
	autoTimer = nil
	if not (GuidingWind.db.enabled and GuidingWind.db.autoGusts) then
		return
	end
	local waypoint = ns:GetModule("Waypoint")
	if not (waypoint and waypoint.HasGuidanceTarget and waypoint.HasGuidanceTarget()) then
		return
	end
	if not IsBlockedForAuto() and not InInstanceWithoutDirection() then
		GuidingWind.Summon(false)
	end
	ScheduleAutoGust()
end

ScheduleAutoGust = function()
	CancelAutoTimer()
	if not (GuidingWind.db and GuidingWind.db.enabled and GuidingWind.db.autoGusts) then
		return
	end
	if InCombatLockdown() then
		return
	end
	local waypoint = ns:GetModule("Waypoint")
	if not (waypoint and waypoint.HasGuidanceTarget and waypoint.HasGuidanceTarget()) then
		return
	end
	local seconds = math.max(6, math.min(45, ns.Number(GuidingWind.db.interval, 14)))
	local pending
	pending = ns.NewTimer("GuidingWind: auto gust", seconds, function()
		if autoTimer == pending then
			AutoGustTick()
		end
	end)
	autoTimer = pending
end

-- Summons a directional gust toward the active waypoint or corpse.
-- manual=true plays sound (when enabled) and prints clear status messages on failure.
function GuidingWind.Summon(manual)
	if not GuidingWind.db.enabled then
		if manual then
			ns.PrintAlways(L.WIND_DISABLED)
		end
		return false, "disabled"
	end
	local waypoint = ns:GetModule("Waypoint")
	if not (waypoint and waypoint.Guidance) then
		return false, "none"
	end
	local distance, goal, angle, kind, reason = waypoint.Guidance()
	if reason == "none" or not goal then
		if manual then
			ns.PrintAlways(L.WIND_NO_WAYPOINT)
		end
		return false, "none"
	end
	if reason == "no_facing" or InInstanceWithoutDirection() then
		if manual then
			ns.PrintAlways(L.WIND_NO_DIRECTION)
		end
		return false, "no_facing"
	end
	if reason == "elsewhere" then
		if manual then
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(goal.mapID)
			local zoneName = type(info) == "table" and not ns.Secret(info.name) and info.name or "?"
			ns.PrintAlways(L.WIND_ELSEWHERE, zoneName)
		end
		return false, "elsewhere"
	end
	if not distance or not angle then
		if manual then
			ns.PrintAlways(L.WIND_NO_DIRECTION)
		end
		return false, reason or "unknown"
	end
	if kind == "waypoint" and waypoint.CheckArrival and waypoint.CheckArrival(distance) then
		return false, "arrived"
	end
	StartGust(angle, { manual = manual, live = true })
	if manual then
		ScheduleAutoGust()
	end
	return true, kind
end

-- Plays a preview gust (defaults to straight ahead) in the current zone's biome.
function GuidingWind.Preview(angle, biomeKey)
	if not GuidingWind.db.enabled then
		ns.PrintAlways(L.WIND_DISABLED)
		return false
	end
	return StartGust(angle or 0, { manual = true, live = false, biome = biomeKey })
end

local DIRECTION_ARGS = {
	vorne = 0, vorn = 0, geradeaus = 0, front = 0, ahead = 0, forward = 0,
	links = math.pi * 0.5, left = math.pi * 0.5,
	rechts = -math.pi * 0.5, right = -math.pi * 0.5,
	hinten = math.pi, back = math.pi, behind = math.pi,
}

-- /fp wind [test [vorne|links|rechts|hinten|<grad>]]
function GuidingWind.Command(msg)
	local rest = strtrim((msg or ""):gsub("^%S+%s*", ""))
	if rest == "" then
		GuidingWind.Summon(true)
		return
	end
	local sub, arg = rest:match("^(%S+)%s*(.*)$")
	if sub == "test" or sub == "vorschau" or sub == "preview" then
		local angle = 0
		if arg and arg ~= "" then
			local named = DIRECTION_ARGS[arg]
			if named ~= nil then
				angle = named
			else
				local degrees = tonumber(arg)
				if degrees then
					angle = math.rad(degrees)
				end
			end
		end
		GuidingWind.Preview(angle)
		return
	end
	ns.PrintAlways(L.WIND_USAGE)
end

-- Called by Waypoint.Refresh when waypoints or corpse targets change.
function GuidingWind.OnWaypointChanged()
	if not (GuidingWind.db and GuidingWind.db.enabled) then
		CancelAutoTimer()
		return
	end
	local waypoint = ns:GetModule("Waypoint")
	if waypoint and waypoint.HasGuidanceTarget and waypoint.HasGuidanceTarget() then
		ScheduleAutoGust()
	else
		CancelAutoTimer()
	end
end

function GuidingWind.GetState()
	return {
		active = gust ~= nil,
		angle = gust and gust.angle or nil,
		biome = gust and gust.biomeKey or nil,
		timerActive = autoTimer ~= nil,
		rootShown = root and root:IsShown() or false,
	}
end

local function OnCombatStart()
	CancelAutoTimer()
end

local function OnCombatEnd()
	ScheduleAutoGust()
end

function GuidingWind:Apply()
	local enabled = self.db.enabled
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, self.OnWaypointChanged)
	self:ToggleEvent("USER_WAYPOINT_UPDATED", enabled, self.OnWaypointChanged)
	self:ToggleEvent("ZONE_CHANGED_NEW_AREA", enabled, self.OnWaypointChanged)
	self:ToggleEvent("PLAYER_ALIVE", enabled, self.OnWaypointChanged)
	self:ToggleEvent("PLAYER_UNGHOST", enabled, self.OnWaypointChanged)
	self:ToggleEvent("PLAYER_REGEN_DISABLED", enabled, OnCombatStart)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", enabled, OnCombatEnd)
	if enabled then
		ScheduleAutoGust()
	else
		CancelAutoTimer()
		StopGustSound()
		HideGust()
	end
	local waypoint = ns:GetModule("Waypoint")
	if waypoint and waypoint.Refresh then
		waypoint.Refresh()
	end
end

function GuidingWind:OnLogin()
	self:Apply()
end

function GuidingWind:OnOptionChanged(key)
	if key == "sound" then
		if not self.db.sound then
			StopGustSound()
		end
		return
	end
	if key == "strength" or key == "biomeParticles" then
		if gust then
			gust.strength = math.max(0.2, math.min(1.0, (self.db.strength or 75) / 100))
			gust.showParticles = self.db.biomeParticles and true or false
			if not gust.showParticles and particles then
				for _, particle in ipairs(particles) do
					particle.texture:Hide()
				end
			end
		end
		return
	end
	if key == "autoGusts" or key == "interval" then
		ScheduleAutoGust()
		return
	end
	self:Apply()
end

BINDING_NAME_FOREVERPLUS_GUIDINGWIND = L.WIND_BINDING

ForeverPlus_SummonGuidingWind = ns.Measured("GuidingWind: binding", function()
	GuidingWind.Summon(true)
end)

GuidingWind.options = {
	{ key = "enabled", type = "toggle", name = L.WIND_ENABLE, desc = L.WIND_ENABLE_DESC, new = true },
	{ key = "autoGusts", type = "toggle", name = L.WIND_AUTO, desc = L.WIND_AUTO_DESC, parent = "enabled", new = true },
	{ key = "interval", type = "slider", name = L.WIND_INTERVAL, desc = L.WIND_INTERVAL_DESC,
		min = 6, max = 45, step = 1, format = function(v) return L.WIND_INTERVAL_FMT:format(v) end,
		parent = "autoGusts", new = true },
	{ key = "biomeParticles", type = "toggle", name = L.WIND_BIOME, desc = L.WIND_BIOME_DESC, parent = "enabled", new = true },
	{ key = "sound", type = "toggle", name = L.WIND_SOUND, desc = L.WIND_SOUND_DESC, parent = "enabled", new = true },
	{ key = "strength", type = "slider", name = L.WIND_STRENGTH, desc = L.WIND_STRENGTH_DESC,
		min = 30, max = 100, step = 5, format = function(v) return ("%d %%"):format(v) end,
		parent = "enabled", new = true },
	{ type = "button", name = L.WIND_PREVIEW, text = L.WIND_PREVIEW_BUTTON, desc = L.WIND_PREVIEW_DESC,
		func = function() GuidingWind.Preview(0) end },
}

-- Guiding Wind: Ghost-of-Tsushima-inspired directional silk wind ribbons pointing toward the
-- active waypoint (or corpse), paired with zone-matched wind-blown leaves, blades and particles.
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

local RIBBON_TEXTURE = [[Interface\AddOns\ForeverPlus\Media\GuidingWindRibbon]]
local ATLAS_TEXTURE = [[Interface\AddOns\ForeverPlus\Media\GuidingWind]]
local PU = 1 / 512
local PV = 1 / 256

-- UV tiles in Media/GuidingWind.tga (512x256, 4x2 grid) with 1px inset against bilinear bleed.
local TILE_BLADE = { PU, 0.25 - PU, PV, 0.50 - PV }
local TILE_LEAF = { 0.25 + PU, 0.50 - PU, PV, 0.50 - PV }
local TILE_SNOW = { 0.50 + PU, 0.75 - PU, PV, 0.50 - PV }
local TILE_DUST = { 0.75 + PU, 1 - PU, PV, 0.50 - PV }
local TILE_EMBER = { PU, 0.25 - PU, 0.50 + PV, 1 - PV }
local TILE_SPORE = { 0.25 + PU, 0.50 - PU, 0.50 + PV, 1 - PV }
local TILE_PETAL = { 0.50 + PU, 0.75 - PU, 0.50 + PV, 1 - PV }
local TILE_MOTE = { 0.75 + PU, 1 - PU, 0.50 + PV, 1 - PV }

-- Real WoW Forever wind-gust one-shots (Data/EmitterSounds.lua: fx_windgust_oneshot_01..07.ogg).
local WIND_SOUNDS = { 982361, 982363, 982365, 982367, 982369, 982371, 982373 }
local SOUND_COOLDOWN = 0.6

-- Ghost-of-Tsushima palette: wind ribbons stay luminous silver-white with only a whisper
-- of ambient biome tint, while carried foliage/particles carry the vivid zone color.
local BIOMES = {
	forest = {
		wind = { 0.94, 0.98, 0.95 },
		glint = { 1.00, 1.00, 0.98 },
		particle = { 0.42, 0.74, 0.28 },
		particleAlt = { 0.68, 0.80, 0.30 },
		tile = TILE_LEAF,
		secondaryTile = TILE_BLADE,
		blend = "BLEND",
		spin = 2.4,
		tumble = 3.4,
		lift = 0.014,
		size = 1.02,
		alpha = 0.92,
	},
	autumn = {
		wind = { 0.99, 0.96, 0.90 },
		glint = { 1.00, 0.98, 0.92 },
		particle = { 0.90, 0.44, 0.16 },
		particleAlt = { 0.98, 0.76, 0.24 },
		tile = TILE_PETAL,
		secondaryTile = TILE_BLADE,
		blend = "BLEND",
		spin = 2.6,
		tumble = 3.6,
		lift = 0.018,
		size = 0.98,
		alpha = 0.92,
	},
	snow = {
		wind = { 0.92, 0.97, 1.00 },
		glint = { 0.98, 1.00, 1.00 },
		particle = { 0.94, 0.98, 1.00 },
		particleAlt = { 0.80, 0.92, 1.00 },
		tile = TILE_SNOW,
		blend = "ADD",
		spin = 1.1,
		tumble = 0,
		lift = -0.024,
		size = 0.90,
		alpha = 0.86,
	},
	desert = {
		wind = { 0.98, 0.94, 0.86 },
		glint = { 1.00, 0.97, 0.88 },
		particle = { 0.88, 0.74, 0.50 },
		particleAlt = { 0.78, 0.62, 0.40 },
		tile = TILE_DUST,
		blend = "BLEND",
		spin = 0.8,
		tumble = 0,
		lift = 0.020,
		size = 1.16,
		alpha = 0.74,
	},
	volcanic = {
		wind = { 0.96, 0.88, 0.80 },
		glint = { 1.00, 0.82, 0.56 },
		particle = { 1.00, 0.52, 0.14 },
		particleAlt = { 1.00, 0.80, 0.28 },
		tile = TILE_EMBER,
		blend = "ADD",
		spin = 0.5,
		tumble = 0,
		lift = 0.105,
		size = 0.96,
		alpha = 0.94,
	},
	marsh = {
		wind = { 0.90, 0.98, 0.94 },
		glint = { 0.94, 1.00, 0.96 },
		particle = { 0.72, 0.98, 0.50 },
		particleAlt = { 0.58, 0.95, 0.80 },
		tile = TILE_SPORE,
		blend = "ADD",
		spin = 0.4,
		tumble = 0,
		lift = 0.055,
		size = 0.88,
		alpha = 0.86,
		pulse = true,
	},
	neutral = {
		wind = { 0.95, 0.97, 1.00 },
		glint = { 1.00, 1.00, 1.00 },
		particle = { 0.92, 0.96, 1.00 },
		particleAlt = { 0.98, 0.99, 1.00 },
		tile = TILE_MOTE,
		blend = "ADD",
		spin = 0.2,
		tumble = 0,
		lift = 0.022,
		size = 0.86,
		alpha = 0.70,
		alignFlow = true,
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

-- Continuous silk wind ribbons rendered via connected SimpleLine segments.
-- Each ribbon has 16 seamless segments along its curved tail-to-head span, plus 6 fine ADD
-- glint segments hugging the leading crest.
local RIBBON_SEGMENTS = 16
local GLINT_FIRST_SEG = 10
local GLINT_LAST_SEG = 15

-- { lane, heightBias, delay, duration, span, thickness, amp, freq, phase, depthLayer, alpha, manualOnly }
local STREAM_SPECS = {
	-- Primary hero ribbons (sweeping left/right/upper-mid lanes with bold Tsushima S-curves)
	{ -0.24, -0.04, 0.00, 1.42, 0.56, 22.0, 0.068, 2.05, 0.25, 1.14, 0.84, false },
	{  0.22,  0.07, 0.11, 1.48, 0.54, 20.5, 0.072, 1.90, 2.05, 1.08, 0.80, false },
	{ -0.09,  0.17, 0.24, 1.38, 0.52, 17.5, 0.058, 2.20, 3.70, 0.96, 0.72, true  },
	-- Intertwined companion silk filaments (paired near the hero streams + airy outer wisps)
	{ -0.21, -0.01, 0.06, 1.38, 0.48, 11.5, 0.074, 2.15, 0.90, 1.02, 0.60, false },
	{  0.25,  0.10, 0.18, 1.44, 0.48, 11.0, 0.066, 2.00, 2.65, 0.94, 0.56, false },
	{  0.13, -0.14, 0.29, 1.34, 0.46, 10.5, 0.056, 2.30, 4.55, 0.88, 0.54, true  },
}

-- Biome particles (leaves, grass blades, petals, snow, dust, embers, spores):
-- { lane, heightBias, delay, duration, size, amp, freq, phase, spinDir, altColor, secondary, depthLayer, manualOnly }
local PARTICLE_SPECS = {
	{ -0.28, -0.05, 0.02, 1.54, 34, 0.072, 2.1, 0.3,  1, false, false, 1.18, false },
	{  0.26,  0.08, 0.08, 1.58, 30, 0.068, 1.9, 1.6, -1, true,  true,  1.12, false },
	{ -0.14,  0.16, 0.14, 1.50, 27, 0.060, 2.2, 2.9,  1, true,  false, 1.02, false },
	{  0.18, -0.11, 0.19, 1.60, 32, 0.070, 1.8, 4.1, -1, false, true,  1.14, false },
	{ -0.34,  0.05, 0.25, 1.48, 25, 0.064, 2.0, 0.9, -1, false, true,  0.96, false },
	{  0.32,  0.13, 0.30, 1.56, 28, 0.066, 2.2, 2.3,  1, true,  false, 0.98, false },
	{ -0.07, -0.13, 0.36, 1.46, 24, 0.054, 2.4, 5.0,  1, false, false, 0.90, false },
	{  0.10,  0.17, 0.41, 1.52, 26, 0.058, 1.9, 1.2, -1, true,  true,  0.88, false },
	{ -0.22,  0.20, 0.47, 1.48, 23, 0.052, 2.1, 3.7,  1, true,  false, 0.84, false },
	-- Extra dense swarm particles for manual summon
	{  0.21, -0.01, 0.05, 1.44, 32, 0.076, 2.0, 5.5, -1, false, false, 1.20, true  },
	{ -0.20, -0.15, 0.16, 1.52, 29, 0.064, 1.8, 2.0,  1, true,  true,  1.06, true  },
	{  0.05,  0.08, 0.28, 1.42, 24, 0.058, 2.4, 4.6, -1, false, true,  0.94, true  },
	{ -0.36, -0.01, 0.39, 1.50, 27, 0.068, 1.8, 0.5,  1, true,  false, 0.92, true  },
	{  0.36, -0.09, 0.50, 1.46, 24, 0.056, 2.2, 3.1, -1, false, true,  0.86, true  },
}

-- Fine directional wind-glint / air-spark needles (rotated along exact flow tangent):
-- { lane, heightBias, delay, duration, size, amp, freq, phase, depthLayer, alpha, manualOnly }
local MOTE_SPECS = {
	{ -0.30,  0.03, 0.03, 1.20, 42, 0.062, 2.0, 0.5, 1.10, 0.58, false },
	{  0.28, -0.07, 0.12, 1.24, 38, 0.058, 1.9, 2.1, 1.04, 0.54, false },
	{ -0.13,  0.17, 0.22, 1.16, 34, 0.052, 2.2, 3.6, 0.96, 0.50, false },
	{  0.15,  0.11, 0.31, 1.22, 40, 0.058, 1.8, 4.9, 0.98, 0.52, false },
	{ -0.24, -0.13, 0.40, 1.18, 32, 0.054, 2.1, 1.4, 0.90, 0.46, false },
	{  0.22,  0.19, 0.48, 1.20, 34, 0.050, 2.0, 3.9, 0.86, 0.46, true  },
	{ -0.04, -0.03, 0.17, 1.14, 36, 0.048, 2.3, 5.4, 1.00, 0.48, true  },
	{  0.34,  0.05, 0.35, 1.18, 32, 0.054, 1.9, 0.8, 0.88, 0.44, true  },
}

-- Precomputed ribbon taper profile across u in [0..1] (tail=0, leading tip=1).
-- Peaked smoothly at u ~ 0.64 for a calligraphic leading crest and long silk tail.
local function RibbonTaper(u)
	if u <= 0 or u >= 1 then
		return 0, 0
	end
	local width = ((u ^ 0.62) * ((1 - u) ^ 0.42)) / 0.505
	if width > 1 then
		width = 1
	end
	local tailFade = u < 0.38 and (u / 0.38) or 1
	tailFade = tailFade * tailFade * (3 - 2 * tailFade)
	local headFade = u > 0.82 and ((1 - u) / 0.18) or 1
	headFade = headFade * headFade * (3 - 2 * headFade)
	return width, tailFade * headFade
end

local root, streams, particles, motes
local gust -- { age, angle, worldBearing, biome, biomeKey, strength, showParticles, manual, live }
local autoTimer
local soundVariants = {}
local lastSoundAt, lastSoundHandle = 0, nil

-- Reusable scratch tables for polyline sampling (zero per-frame allocations).
local ptX, ptY, ptScale = {}, {}, {}

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

-- Evaluates normalized screen coordinates (0..1, 0..1) and perspective scale along a Tsushima gust path.
-- Ahead: ribbons sweep from wide foreground flanks past the player toward a distant upper horizon
--        with true perspective depth foreshortening.
-- Left/Right: long, sweeping silk ribbons whip gracefully across nearly the full viewport width.
-- Behind: ribbons curve around the player on the nearer turning side and pull back downward.
local function EvaluateTrack(lane, heightBias, amp, freq, phase, p, angle, extraLift, depthLayer)
	local dirX = -math.sin(angle)
	local dirY = math.cos(angle)
	local perpX = -dirY
	local perpY = dirX

	local forwardness = math.max(0, dirY)
	local backwardness = math.max(0, -dirY - 0.15) / 0.85
	local fBlend = forwardness * forwardness * (3 - 2 * forwardness)
	local layer = depthLayer or 1.0

	-- Snappy Ghost-of-Tsushima surge easing: accelerates fast, glides long into the distance.
	local ease = 1 - ((1 - p) ^ 1.55)

	-- 1. Wide sweeping track (left/right/diagonal/behind).
	local travel = 0.88 - 0.16 * backwardness
	local sweepCenterX = 0.50
	local sweepCenterY = 0.47 + heightBias * 0.55 - 0.05 * backwardness
	local sweepX = sweepCenterX + dirX * (ease - 0.50) * travel + perpX * lane
	local sweepY = sweepCenterY + dirY * (ease - 0.50) * travel + perpY * lane

	if backwardness > 0 then
		local turnSign = angle >= 0 and -1 or 1
		local arc = math.sin(ease * math.pi)
		sweepX = sweepX + turnSign * 0.22 * backwardness * arc
		sweepY = sweepY + 0.04 * backwardness * (1 - 2 * ease) * (1 - arc * 0.45)
	end

	-- 2. True 3D perspective depth track when blowing forward into the world.
	local invDepth = 1 / (1 + 2.05 * ease)
	local perspProgress = (1 - invDepth) / (1 - (1 / 3.05))
	local sideSign = lane < 0 and -1 or 1
	local startX = 0.50 + lane * 1.18 + sideSign * 0.075 - dirX * 0.24
	local startY = 0.14 + heightBias * 0.55 + math.abs(lane) * 0.12
	local vanishX = 0.50 + dirX * 0.30 + lane * 0.15
	local vanishY = 0.66 + heightBias * 0.18
	local perspX = startX + (vanishX - startX) * perspProgress
	local perspY = startY + (vanishY - startY) * perspProgress

	local x = sweepX + (perspX - sweepX) * fBlend
	local y = sweepY + (perspY - sweepY) * fBlend

	-- Perspective scale: bold in the foreground, fine and delicate toward the horizon.
	local depthScale = layer * ((1 - fBlend) + fBlend * (0.40 + 0.82 * invDepth))

	-- Expressive Ghost-of-Tsushima S-wave undulation (lateral + gentle vertical ripple).
	local waveAmp = amp * (0.55 + 0.45 * depthScale)
	local wave = math.sin(ease * freq * math.pi + phase) * waveAmp
	local vRipple = math.sin(ease * (freq * 1.15) * math.pi + phase + 1.3) * (waveAmp * 0.42)
	local crestLift = 0.045 * (ease * ease) * (1 - backwardness)
	x = x + perpX * wave
	y = y + perpY * wave + vRipple + crestLift + (extraLift or 0) * ease

	return x, y, depthScale
end

-- Exported pure track helper so regression tests can verify perspective and directional flow.
GuidingWind.EvaluateTrack = EvaluateTrack

local function HideTextureList(list)
	if not list then return end
	for _, entry in ipairs(list) do
		if entry.texture then
			entry.texture:Hide()
		end
	end
end

local function HideStream(stream)
	for _, seg in ipairs(stream.segments) do
		seg:Hide()
	end
	for _, glint in ipairs(stream.glints) do
		glint:Hide()
	end
end

local function HideGust()
	gust = nil
	HideTextureList(particles)
	HideTextureList(motes)
	if streams then
		for _, stream in ipairs(streams) do
			HideStream(stream)
		end
	end
	if root then
		root:Hide()
	end
end

local function TrackTangent(lane, heightBias, amp, freq, phase, p, angle, w, h, lift, depthLayer)
	local x, y, depthScale = EvaluateTrack(lane, heightBias, amp, freq, phase, p, angle, lift or 0, depthLayer)
	local pPrev = math.max(0, p - 0.014)
	local pNext = math.min(1, p + 0.018)
	local px, py = EvaluateTrack(lane, heightBias, amp, freq, phase, pPrev, angle, lift or 0, depthLayer)
	local nx, ny = EvaluateTrack(lane, heightBias, amp, freq, phase, pNext, angle, lift or 0, depthLayer)
	local rot = math.atan2((ny - py) * h, (nx - px) * w)
	return x, y, depthScale, rot
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
	local strength = gust.strength * (gust.manual and 1.0 or 0.78)
	local biome = gust.biome
	local active = false

	-- 1. Continuous curved Ghost-of-Tsushima silk wind ribbons (connected SimpleLine polylines).
	for _, stream in ipairs(streams) do
		if stream.manualOnly and not gust.manual then
			HideStream(stream)
		else
			local t = gust.age - stream.delay
			local totalDuration = stream.duration * (1 + stream.span)
			if t > 0 and t < totalDuration then
				active = true
				local pHeadRaw = t / stream.duration
				local pTailRaw = pHeadRaw - stream.span
				local pStart = math.max(0, pTailRaw)
				local pEnd = math.min(1, pHeadRaw)
				local visibleSpan = pEnd - pStart

				if visibleSpan > 0.008 then
					local lane = stream.lane + stream.laneJitter
					local heightBias = stream.heightBias + stream.heightJitter
					local phase = stream.phase + stream.phaseJitter

					-- Sample N+1 curve points once so adjacent line segments meet with zero gaps.
					for i = 0, RIBBON_SEGMENTS do
						local frac = i / RIBBON_SEGMENTS
						local ps = pStart + frac * visibleSpan
						local sx, sy, sScale = EvaluateTrack(
							lane, heightBias, stream.amp, stream.freq, phase, ps, angle, 0, stream.depthLayer
						)
						ptX[i] = sx * w
						ptY[i] = sy * h
						ptScale[i] = sScale
					end

					for s = 1, RIBBON_SEGMENTS do
						local line = stream.segments[s]
						local x1, y1 = ptX[s - 1], ptY[s - 1]
						local x2, y2 = ptX[s], ptY[s]
						local dx = x2 - x1
						local dy = y2 - y1
						if dx * dx + dy * dy > 0.25 then
							local midFrac = (s - 0.5) / RIBBON_SEGMENTS
							local pMid = pStart + midFrac * visibleSpan
							-- u in [0..1] along the full logical ribbon (0 = tail, 1 = leading tip).
							local u = (pMid - pTailRaw) / stream.span
							local wProf, aProf = RibbonTaper(u)
							local pathEnv = math.sin(pMid * math.pi) ^ 0.72
							local segScale = (ptScale[s - 1] + ptScale[s]) * 0.5
							local thick = math.max(1.2, stream.thickness * (0.14 + 0.86 * wProf) * segScale * uiScale)
							local alpha = stream.alpha * strength * aProf * pathEnv
							-- Extend each feathered segment by 18% along its tangent so joins cross-fade seamlessly.
							local ex1 = x1 - dx * 0.18
							local ey1 = y1 - dy * 0.18
							local ex2 = x2 + dx * 0.18
							local ey2 = y2 + dy * 0.18

							line:SetStartPoint("BOTTOMLEFT", root, ex1, ey1)
							line:SetEndPoint("BOTTOMLEFT", root, ex2, ey2)
							line:SetThickness(thick)
							line:SetAlpha(alpha)
							line:Show()

							if s >= GLINT_FIRST_SEG and s <= GLINT_LAST_SEG then
								local glint = stream.glints[s - GLINT_FIRST_SEG + 1]
								glint:SetStartPoint("BOTTOMLEFT", root, ex1, ey1)
								glint:SetEndPoint("BOTTOMLEFT", root, ex2, ey2)
								glint:SetThickness(math.max(1.0, thick * 0.52))
								glint:SetAlpha(alpha * 0.34)
								glint:Show()
							end
						else
							line:Hide()
							if s >= GLINT_FIRST_SEG and s <= GLINT_LAST_SEG then
								stream.glints[s - GLINT_FIRST_SEG + 1]:Hide()
							end
						end
					end
				else
					HideStream(stream)
				end
			elseif t <= 0 then
				active = true
				HideStream(stream)
			else
				HideStream(stream)
			end
		end
	end

	-- 2. Wind-carried biome particles (leaves, grass blades, petals, snow, dust, embers, spores)
	--    plus slender directional wind-glint needles.
	if gust.showParticles then
		local tumbleSpeed = biome.tumble or 0
		for _, particle in ipairs(particles) do
			if particle.manualOnly and not gust.manual then
				particle.texture:Hide()
			else
				local t = gust.age - particle.delay
				if t > 0 and t < particle.duration then
					active = true
					local p = t / particle.duration
					local lane = particle.lane + particle.laneJitter
					local heightBias = particle.heightBias + particle.heightJitter
					local phase = particle.phase + particle.phaseJitter
					local x, y, depthScale, rot = TrackTangent(
						lane, heightBias, particle.amp, particle.freq, phase, p, angle, w, h, biome.lift, particle.depthLayer
					)
					local envelope = math.sin(p * math.pi)
					local pulse = biome.pulse and (0.65 + 0.35 * math.sin(t * 7 + phase)) or 1
					local alpha = biome.alpha * strength * (envelope ^ 0.78) * pulse
					local size = particle.size * biome.size * uiScale * depthScale
					local height = tumbleSpeed > 0
						and size * (0.48 + 0.52 * math.abs(math.cos(t * tumbleSpeed + phase)))
						or size
					local spinAngle = biome.alignFlow and rot
						or (particle.startRot + t * biome.spin * particle.spinDir)

					particle.texture:SetSize(size, height)
					particle.texture:ClearAllPoints()
					particle.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
					particle.texture:SetRotation(spinAngle)
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

		for _, mote in ipairs(motes) do
			if mote.manualOnly and not gust.manual then
				mote.texture:Hide()
			else
				local t = gust.age - mote.delay
				if t > 0 and t < mote.duration then
					active = true
					local p = t / mote.duration
					local lane = mote.lane + mote.laneJitter
					local phase = mote.phase + mote.phaseJitter
					local x, y, depthScale, rot = TrackTangent(
						lane, mote.heightBias, mote.amp, mote.freq, phase, p, angle, w, h, biome.lift * 0.4, mote.depthLayer
					)
					local envelope = math.sin(p * math.pi)
					local size = mote.size * uiScale * depthScale
					-- Square texture frame keeps SetRotation(rot) crisp and unclipped at every angle.
					mote.texture:SetSize(size, size)
					mote.texture:ClearAllPoints()
					mote.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
					mote.texture:SetRotation(rot)
					mote.texture:SetAlpha(mote.alpha * strength * (envelope ^ 0.85))
					mote.texture:Show()
				elseif t <= 0 then
					active = true
					mote.texture:Hide()
				else
					mote.texture:Hide()
				end
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

	streams = {}
	for i, spec in ipairs(STREAM_SPECS) do
		local segs = {}
		for s = 1, RIBBON_SEGMENTS do
			local line = root:CreateLine(nil, "ARTWORK", nil, 0)
			line:SetTexture(RIBBON_TEXTURE, "CLAMP", "CLAMP")
			line:SetBlendMode("BLEND")
			line:Hide()
			segs[s] = line
		end
		local glints = {}
		for g = 1, (GLINT_LAST_SEG - GLINT_FIRST_SEG + 1) do
			local line = root:CreateLine(nil, "ARTWORK", nil, 1)
			line:SetTexture(RIBBON_TEXTURE, "CLAMP", "CLAMP")
			line:SetBlendMode("ADD")
			line:Hide()
			glints[g] = line
		end
		streams[i] = {
			segments = segs,
			glints = glints,
			lane = spec[1], heightBias = spec[2], delay = spec[3], duration = spec[4],
			span = spec[5], thickness = spec[6], amp = spec[7], freq = spec[8], phase = spec[9],
			depthLayer = spec[10], alpha = spec[11], manualOnly = spec[12],
			laneJitter = 0, heightJitter = 0, phaseJitter = 0,
		}
	end

	particles = {}
	for i, spec in ipairs(PARTICLE_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 2)
		tex:SetTexture(ATLAS_TEXTURE)
		tex:Hide()
		particles[i] = {
			texture = tex,
			lane = spec[1], heightBias = spec[2], delay = spec[3], duration = spec[4],
			size = spec[5], amp = spec[6], freq = spec[7], phase = spec[8],
			spinDir = spec[9], altColor = spec[10], secondary = spec[11],
			depthLayer = spec[12], manualOnly = spec[13],
			startRot = 0, laneJitter = 0, heightJitter = 0, phaseJitter = 0,
		}
	end

	motes = {}
	for i, spec in ipairs(MOTE_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 1)
		tex:SetTexture(ATLAS_TEXTURE)
		tex:SetTexCoord(unpack(TILE_MOTE))
		tex:SetBlendMode("ADD")
		tex:Hide()
		motes[i] = {
			texture = tex,
			lane = spec[1], heightBias = spec[2], delay = spec[3], duration = spec[4],
			size = spec[5], amp = spec[6], freq = spec[7], phase = spec[8],
			depthLayer = spec[9], alpha = spec[10], manualOnly = spec[11],
			laneJitter = 0, phaseJitter = 0,
		}
	end

	ns.SetUpdate(root, "GuidingWind: gust", UpdateGust)
	root:Hide()
end

local function StartGust(angle, options)
	options = options or {}
	EnsureOverlay()
	root:SetFrameStrata(options.preview and "FULLSCREEN_DIALOG" or "LOW")

	local normAngle = GuidingWind.NormalizeAngle(angle)
	local biomeKey = options.biome or GuidingWind.CurrentBiome()
	local biome = BIOMES[biomeKey] or BIOMES.neutral
	local strength = math.max(0.2, math.min(1.0, (GuidingWind.db.strength or 75) / 100))
	local showParticles = GuidingWind.db.biomeParticles and true or false

	local worldBearing
	if options.live then
		local facing = ns.Number(GetPlayerFacing())
		if facing then
			worldBearing = normAngle + facing
		end
	end

	for _, stream in ipairs(streams) do
		for _, line in ipairs(stream.segments) do
			line:SetVertexColor(unpack(biome.wind))
			line:SetAlpha(0)
			line:Hide()
		end
		for _, glint in ipairs(stream.glints) do
			glint:SetVertexColor(unpack(biome.glint))
			glint:SetAlpha(0)
			glint:Hide()
		end
		stream.laneJitter = (math.random() - 0.5) * 0.06
		stream.heightJitter = (math.random() - 0.5) * 0.05
		stream.phaseJitter = (math.random() - 0.5) * 0.9
	end

	for _, particle in ipairs(particles) do
		local tile = (particle.secondary and biome.secondaryTile) or biome.tile
		particle.texture:SetTexCoord(unpack(tile))
		particle.texture:SetBlendMode(biome.blend)
		local color = particle.altColor and biome.particleAlt or biome.particle
		particle.texture:SetVertexColor(unpack(color))
		particle.texture:SetAlpha(0)
		particle.texture:Hide()
		particle.startRot = math.random() * math.pi * 2
		particle.laneJitter = (math.random() - 0.5) * 0.08
		particle.heightJitter = (math.random() - 0.5) * 0.06
		particle.phaseJitter = (math.random() - 0.5) * 1.1
	end

	for _, mote in ipairs(motes) do
		mote.texture:SetVertexColor(unpack(biome.glint))
		mote.texture:SetAlpha(0)
		mote.texture:Hide()
		mote.laneJitter = (math.random() - 0.5) * 0.07
		mote.phaseJitter = (math.random() - 0.5) * 0.9
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
	local seconds = math.max(5, math.min(60, ns.Number(GuidingWind.db.interval, 14)))
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
-- Works even while Guiding Wind is disabled so preview buttons stay responsive without starting auto-gusts.
function GuidingWind.Preview(angle, biomeKey)
	return StartGust(angle or 0, { manual = true, live = false, preview = true, biome = biomeKey })
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
		manual = gust and gust.manual or false,
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
			if not gust.showParticles then
				HideTextureList(particles)
				HideTextureList(motes)
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
		min = 5, max = 60, step = 1, format = function(v) return L.WIND_INTERVAL_FMT:format(v) end,
		parent = "autoGusts", new = true },
	{ key = "biomeParticles", type = "toggle", name = L.WIND_BIOME, desc = L.WIND_BIOME_DESC, parent = "enabled", new = true },
	{ key = "sound", type = "toggle", name = L.WIND_SOUND, desc = L.WIND_SOUND_DESC, parent = "enabled", new = true },
	{ key = "strength", type = "slider", name = L.WIND_STRENGTH, desc = L.WIND_STRENGTH_DESC,
		min = 30, max = 100, step = 5, format = function(v) return ("%d %%"):format(v) end,
		parent = "enabled", new = true },
	{ type = "button", name = L.WIND_PREVIEW, text = L.WIND_PREVIEW_BUTTON, desc = L.WIND_PREVIEW_DESC,
		func = function() GuidingWind.Preview(0) end },
}

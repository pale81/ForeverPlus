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
local PIXEL = 1 / 512

-- UV tiles in Media/GuidingWind.tga (512x512) with 1px inset against bilinear bleed.
local WISP_BRUSH = { PIXEL, 1 - PIXEL, PIXEL, 0.25 - PIXEL }
local WISP_VEIL = { PIXEL, 1 - PIXEL, 0.25 + PIXEL, 0.50 - PIXEL }
local TILE_CURL = { PIXEL, 0.25 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_LEAF = { 0.25 + PIXEL, 0.50 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_SNOW = { 0.50 + PIXEL, 0.75 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_DUST = { 0.75 + PIXEL, 1 - PIXEL, 0.50 + PIXEL, 0.75 - PIXEL }
local TILE_EMBER = { PIXEL, 0.25 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }
local TILE_SPORE = { 0.25 + PIXEL, 0.50 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }
local TILE_PETAL = { 0.50 + PIXEL, 0.75 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }
local TILE_MOTE = { 0.75 + PIXEL, 1 - PIXEL, 0.75 + PIXEL, 1 - PIXEL }

-- Real WoW Forever wind-gust one-shots (Data/EmitterSounds.lua: fx_windgust_oneshot_01..07.ogg).
local WIND_SOUNDS = { 982361, 982363, 982365, 982367, 982369, 982371, 982373 }
local SOUND_COOLDOWN = 0.6

local BIOMES = {
	forest = {
		veil = { 0.74, 0.83, 0.70 },
		wind = { 0.87, 0.93, 0.81 },
		glint = { 0.96, 1.00, 0.88 },
		particle = { 0.44, 0.72, 0.28 },
		particleAlt = { 0.64, 0.78, 0.30 },
		tile = TILE_LEAF,
		blend = "BLEND",
		spin = 2.2,
		tumble = 3.2,
		lift = -0.028,
		size = 1.06,
		alpha = 0.92,
	},
	autumn = {
		veil = { 0.86, 0.75, 0.58 },
		wind = { 0.96, 0.88, 0.72 },
		glint = { 1.00, 0.95, 0.82 },
		particle = { 0.86, 0.48, 0.18 },
		particleAlt = { 0.95, 0.72, 0.24 },
		tile = TILE_PETAL,
		blend = "BLEND",
		spin = 2.4,
		tumble = 3.5,
		lift = -0.022,
		size = 1.00,
		alpha = 0.90,
	},
	snow = {
		veil = { 0.66, 0.78, 0.91 },
		wind = { 0.84, 0.92, 0.99 },
		glint = { 0.95, 0.99, 1.00 },
		particle = { 0.93, 0.97, 1.00 },
		particleAlt = { 0.78, 0.90, 1.00 },
		tile = TILE_SNOW,
		blend = "ADD",
		spin = 1.0,
		tumble = 0,
		lift = -0.036,
		size = 0.96,
		alpha = 0.84,
	},
	desert = {
		veil = { 0.80, 0.68, 0.48 },
		wind = { 0.93, 0.83, 0.64 },
		glint = { 1.00, 0.92, 0.74 },
		particle = { 0.86, 0.72, 0.48 },
		particleAlt = { 0.76, 0.60, 0.38 },
		tile = TILE_DUST,
		blend = "BLEND",
		spin = 1.2,
		tumble = 0,
		lift = 0.012,
		size = 1.22,
		alpha = 0.76,
	},
	volcanic = {
		veil = { 0.44, 0.36, 0.32 },
		wind = { 0.78, 0.56, 0.42 },
		glint = { 1.00, 0.66, 0.28 },
		particle = { 1.00, 0.52, 0.14 },
		particleAlt = { 1.00, 0.78, 0.28 },
		tile = TILE_EMBER,
		blend = "ADD",
		spin = 0.5,
		tumble = 0,
		lift = 0.105,
		size = 0.96,
		alpha = 0.94,
	},
	marsh = {
		veil = { 0.56, 0.72, 0.66 },
		wind = { 0.75, 0.90, 0.82 },
		glint = { 0.84, 1.00, 0.88 },
		particle = { 0.70, 0.98, 0.48 },
		particleAlt = { 0.56, 0.94, 0.78 },
		tile = TILE_SPORE,
		blend = "ADD",
		spin = 0.4,
		tumble = 0,
		lift = 0.055,
		size = 0.90,
		alpha = 0.86,
		pulse = true,
	},
	neutral = {
		veil = { 0.76, 0.83, 0.90 },
		wind = { 0.88, 0.93, 0.98 },
		glint = { 0.96, 0.99, 1.00 },
		particle = { 0.86, 0.92, 0.98 },
		particleAlt = { 0.94, 0.96, 1.00 },
		tile = TILE_MOTE,
		blend = "ADD",
		spin = 0.3,
		tumble = 0,
		lift = 0.02,
		size = 0.78,
		alpha = 0.64,
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

-- Wide, soft atmospheric air veils (BLEND background depth): { lane, delay, duration, length, thickness, amp, freq, phase, alpha }
local VEIL_SPECS = {
	{ -0.18, 0.00, 1.65, 310, 74, 0.022, 1.6, 0.3, 0.20 },
	{  0.16, 0.16, 1.72, 330, 80, 0.026, 1.5, 2.1, 0.18 },
	{ -0.02, 0.32, 1.58, 280, 66, 0.020, 1.7, 3.8, 0.16 },
}

-- Segmented wind streams: each stream bends organically along the curve using 4 overlapping painterly brush segments
-- plus 1 subtle ADD sunlit highlight near the leading crest.
-- { lane, delay, duration, segLength, segThickness, amp, freq, phase, alpha }
local STREAM_SPECS = {
	{ -0.23, 0.02, 1.52, 118, 30, 0.028, 2.0, 0.2, 0.56 },
	{  0.21, 0.13, 1.60, 126, 34, 0.032, 1.8, 1.6, 0.54 },
	{ -0.09, 0.26, 1.48, 108, 26, 0.024, 2.2, 2.9, 0.48 },
	{  0.11, 0.36, 1.56, 114, 28, 0.027, 1.9, 4.3, 0.50 },
}
local STREAM_SEGMENTS = {
	{ lag = 0.000, len = 0.86, thick = 0.80, alpha = 0.96 },
	{ lag = 0.078, len = 1.04, thick = 1.00, alpha = 0.86 },
	{ lag = 0.156, len = 1.08, thick = 1.04, alpha = 0.66 },
	{ lag = 0.234, len = 1.12, thick = 1.08, alpha = 0.40 },
}

-- Curling wind eddies that unfurl softly near the tail of the gust:
-- { lane, delay, duration, startSize, endSize, amp, freq, phase, spinDir, alpha }
local CURL_SPECS = {
	{ -0.22, 0.46, 1.08, 48, 86, 0.025, 1.8, 0.5,  1, 0.44 },
	{  0.24, 0.62, 1.04, 44, 78, 0.028, 1.7, 2.4, -1, 0.40 },
}

-- Biome particles (leaves, snow, dust, embers, spores, petals):
-- { lane, delay, duration, size, amp, freq, phase, spinDir, altColor }
local PARTICLE_SPECS = {
	{ -0.27, 0.05, 1.64, 20, 0.036, 2.3, 0.4,  1, false },
	{  0.25, 0.14, 1.70, 17, 0.033, 2.1, 1.9, -1, true  },
	{ -0.14, 0.23, 1.60, 16, 0.029, 2.5, 3.1,  1, true  },
	{  0.16, 0.30, 1.68, 21, 0.038, 1.9, 4.5, -1, false },
	{ -0.33, 0.38, 1.56, 15, 0.031, 2.2, 1.1, -1, false },
	{  0.30, 0.44, 1.62, 18, 0.034, 2.4, 2.6,  1, true  },
	{ -0.06, 0.52, 1.54, 14, 0.026, 2.6, 5.2,  1, false },
	{  0.08, 0.58, 1.58, 16, 0.030, 2.0, 0.8, -1, true  },
}

-- Fine drifting dust/pollen motes on a brisker parallax layer:
-- { lane, delay, duration, size, amp, freq, phase, alpha }
local MOTE_SPECS = {
	{ -0.30, 0.08, 1.38, 14, 0.040, 2.6, 0.7, 0.42 },
	{  0.28, 0.18, 1.42, 12, 0.036, 2.4, 2.2, 0.38 },
	{ -0.12, 0.29, 1.34, 11, 0.032, 2.8, 3.9, 0.36 },
	{  0.14, 0.39, 1.40, 13, 0.038, 2.5, 5.0, 0.40 },
	{ -0.24, 0.49, 1.36, 12, 0.034, 2.7, 1.4, 0.34 },
	{  0.22, 0.57, 1.38, 11, 0.035, 2.3, 4.1, 0.34 },
}

local root, veils, streams, curls, particles, motes
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

local function HideTextureList(list)
	if not list then return end
	for _, entry in ipairs(list) do
		if entry.texture then
			entry.texture:Hide()
		end
	end
end

local function HideGust()
	gust = nil
	HideTextureList(veils)
	HideTextureList(curls)
	HideTextureList(particles)
	HideTextureList(motes)
	if streams then
		for _, stream in ipairs(streams) do
			for _, seg in ipairs(stream.segments) do
				seg.texture:Hide()
			end
			stream.glint:Hide()
		end
	end
	if root then
		root:Hide()
	end
end

local function TrackTangent(lane, amp, freq, phase, p, angle, w, h, lift)
	local x, y, depthScale = EvaluateTrack(lane, amp, freq, phase, p, angle, lift or 0)
	local pPrev = math.max(0, p - 0.015)
	local pNext = math.min(1, p + 0.020)
	local px, py = EvaluateTrack(lane, amp, freq, phase, pPrev, angle, lift or 0)
	local nx, ny = EvaluateTrack(lane, amp, freq, phase, pNext, angle, lift or 0)
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
	local strength = gust.strength
	local biome = gust.biome
	local active = false

	-- 1. Soft atmospheric air veils (BLEND background depth).
	for _, veil in ipairs(veils) do
		local t = gust.age - veil.delay
		if t > 0 and t < veil.duration then
			active = true
			local p = t / veil.duration
			local x, y, depthScale, rot = TrackTangent(veil.lane, veil.amp, veil.freq, veil.phase, p, angle, w, h, 0)
			local envelope = math.sin(p * math.pi)
			local scale = uiScale * depthScale
			veil.texture:SetSize(veil.length * scale, veil.thickness * scale)
			veil.texture:ClearAllPoints()
			veil.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
			veil.texture:SetRotation(rot)
			veil.texture:SetAlpha(veil.alpha * strength * (envelope ^ 0.9))
			veil.texture:Show()
		elseif t <= 0 then
			active = true
			veil.texture:Hide()
		else
			veil.texture:Hide()
		end
	end

	-- 2. Segmented painterly wind streams that bend smoothly along the curve + subtle sunlit head glint.
	local maxLag = STREAM_SEGMENTS[#STREAM_SEGMENTS].lag
	for _, stream in ipairs(streams) do
		local t = gust.age - stream.delay
		local totalDuration = stream.duration * (1 + maxLag)
		if t > 0 and t < totalDuration then
			active = true
			local pHead = t / stream.duration
			for _, seg in ipairs(stream.segments) do
				local ps = pHead - seg.lag
				if ps > 0 and ps < 1 then
					local x, y, depthScale, rot = TrackTangent(
						stream.lane, stream.amp, stream.freq, stream.phase, ps, angle, w, h, 0
					)
					local envelope = math.sin(ps * math.pi)
					local scale = uiScale * depthScale
					seg.texture:SetSize(stream.segLength * seg.len * scale, stream.segThickness * seg.thick * scale)
					seg.texture:ClearAllPoints()
					seg.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
					seg.texture:SetRotation(rot)
					seg.texture:SetAlpha(stream.alpha * seg.alpha * strength * (envelope ^ 0.85))
					seg.texture:Show()
				else
					seg.texture:Hide()
				end
			end
			-- Subtle ADD shimmer hugging the leading crest (kept restrained so nothing blows out to neon white).
			local pg = pHead - 0.03
			if pg > 0.04 and pg < 0.96 then
				local x, y, depthScale, rot = TrackTangent(
					stream.lane, stream.amp, stream.freq, stream.phase, pg, angle, w, h, 0
				)
				local envelope = math.sin(pg * math.pi)
				local scale = uiScale * depthScale
				stream.glint:SetSize(stream.segLength * 1.15 * scale, stream.segThickness * 0.62 * scale)
				stream.glint:ClearAllPoints()
				stream.glint:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
				stream.glint:SetRotation(rot)
				stream.glint:SetAlpha(stream.alpha * 0.24 * strength * (envelope ^ 1.1))
				stream.glint:Show()
			else
				stream.glint:Hide()
			end
		elseif t <= 0 then
			active = true
			for _, seg in ipairs(stream.segments) do
				seg.texture:Hide()
			end
			stream.glint:Hide()
		else
			for _, seg in ipairs(stream.segments) do
				seg.texture:Hide()
			end
			stream.glint:Hide()
		end
	end

	-- 3. Unfurling wind-curl eddies near the tail of the gust.
	for _, curl in ipairs(curls) do
		local t = gust.age - curl.delay
		if t > 0 and t < curl.duration then
			active = true
			local p = t / curl.duration
			local trackP = 0.56 + p * 0.42
			local x, y, depthScale = EvaluateTrack(curl.lane, curl.amp, curl.freq, curl.phase, trackP, angle, 0.012)
			local envelope = math.sin(p * math.pi)
			local size = (curl.startSize + (curl.endSize - curl.startSize) * p) * uiScale * depthScale
			curl.texture:SetSize(size, size)
			curl.texture:ClearAllPoints()
			curl.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
			curl.texture:SetRotation(curl.startRot + p * 1.45 * curl.spinDir)
			curl.texture:SetAlpha(curl.alpha * strength * (envelope ^ 0.9))
			curl.texture:Show()
		elseif t <= 0 then
			active = true
			curl.texture:Hide()
		else
			curl.texture:Hide()
		end
	end

	-- 4. Biome particles (with pseudo-3D tumble for leaves/petals) + airy parallax motes.
	if gust.showParticles then
		local tumbleSpeed = biome.tumble or 0
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
				local height = tumbleSpeed > 0
					and size * (0.40 + 0.60 * math.abs(math.cos(t * tumbleSpeed + particle.phase)))
					or size

				particle.texture:SetSize(size, height)
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

		for _, mote in ipairs(motes) do
			local t = gust.age - mote.delay
			if t > 0 and t < mote.duration then
				active = true
				local p = t / mote.duration
				local x, y, depthScale = EvaluateTrack(
					mote.lane, mote.amp, mote.freq, mote.phase, p, angle, biome.lift * 0.5
				)
				local envelope = math.sin(p * math.pi)
				local size = mote.size * uiScale * depthScale
				mote.texture:SetSize(size, size)
				mote.texture:ClearAllPoints()
				mote.texture:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
				mote.texture:SetRotation(mote.startRot + t * 0.8)
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

	veils = {}
	for i, spec in ipairs(VEIL_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, -1)
		tex:SetTexture(TEXTURE)
		tex:SetTexCoord(unpack(WISP_VEIL))
		tex:SetBlendMode("BLEND")
		tex:Hide()
		veils[i] = {
			texture = tex,
			lane = spec[1], delay = spec[2], duration = spec[3],
			length = spec[4], thickness = spec[5],
			amp = spec[6], freq = spec[7], phase = spec[8], alpha = spec[9],
		}
	end

	streams = {}
	for i, spec in ipairs(STREAM_SPECS) do
		local segs = {}
		for s, segSpec in ipairs(STREAM_SEGMENTS) do
			local tex = root:CreateTexture(nil, "ARTWORK", nil, 0)
			tex:SetTexture(TEXTURE)
			tex:SetTexCoord(unpack(WISP_BRUSH))
			tex:SetBlendMode("BLEND")
			tex:Hide()
			segs[s] = {
				texture = tex,
				lag = segSpec.lag, len = segSpec.len, thick = segSpec.thick, alpha = segSpec.alpha,
			}
		end
		local glint = root:CreateTexture(nil, "ARTWORK", nil, 1)
		glint:SetTexture(TEXTURE)
		glint:SetTexCoord(unpack(WISP_BRUSH))
		glint:SetBlendMode("ADD")
		glint:Hide()
		streams[i] = {
			segments = segs,
			glint = glint,
			lane = spec[1], delay = spec[2], duration = spec[3],
			segLength = spec[4], segThickness = spec[5],
			amp = spec[6], freq = spec[7], phase = spec[8], alpha = spec[9],
		}
	end

	curls = {}
	for i, spec in ipairs(CURL_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 1)
		tex:SetTexture(TEXTURE)
		tex:SetTexCoord(unpack(TILE_CURL))
		tex:SetBlendMode("BLEND")
		tex:Hide()
		curls[i] = {
			texture = tex,
			lane = spec[1], delay = spec[2], duration = spec[3],
			startSize = spec[4], endSize = spec[5],
			amp = spec[6], freq = spec[7], phase = spec[8],
			spinDir = spec[9], alpha = spec[10], startRot = 0,
		}
	end

	particles = {}
	for i, spec in ipairs(PARTICLE_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 2)
		tex:SetTexture(TEXTURE)
		tex:Hide()
		particles[i] = {
			texture = tex,
			lane = spec[1], delay = spec[2], duration = spec[3],
			size = spec[4], amp = spec[5], freq = spec[6], phase = spec[7],
			spinDir = spec[8], altColor = spec[9], startRot = 0,
		}
	end

	motes = {}
	for i, spec in ipairs(MOTE_SPECS) do
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 2)
		tex:SetTexture(TEXTURE)
		tex:SetTexCoord(unpack(TILE_MOTE))
		tex:SetBlendMode("ADD")
		tex:Hide()
		motes[i] = {
			texture = tex,
			lane = spec[1], delay = spec[2], duration = spec[3],
			size = spec[4], amp = spec[5], freq = spec[6], phase = spec[7],
			alpha = spec[8], startRot = 0,
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

	for _, veil in ipairs(veils) do
		veil.texture:SetVertexColor(unpack(biome.veil))
		veil.texture:SetAlpha(0)
		veil.texture:Hide()
	end

	for _, stream in ipairs(streams) do
		for _, seg in ipairs(stream.segments) do
			seg.texture:SetVertexColor(unpack(biome.wind))
			seg.texture:SetAlpha(0)
			seg.texture:Hide()
		end
		stream.glint:SetVertexColor(unpack(biome.glint))
		stream.glint:SetAlpha(0)
		stream.glint:Hide()
	end

	for _, curl in ipairs(curls) do
		curl.texture:SetVertexColor(unpack(biome.wind))
		curl.texture:SetAlpha(0)
		curl.texture:Hide()
		curl.startRot = normAngle + math.random() * 1.2 - 0.6
	end

	for _, particle in ipairs(particles) do
		particle.texture:SetTexCoord(unpack(biome.tile))
		particle.texture:SetBlendMode(biome.blend)
		local color = particle.altColor and biome.particleAlt or biome.particle
		particle.texture:SetVertexColor(unpack(color))
		particle.texture:SetAlpha(0)
		particle.texture:Hide()
		particle.startRot = math.random() * math.pi * 2
	end

	for _, mote in ipairs(motes) do
		mote.texture:SetVertexColor(unpack(biome.glint))
		mote.texture:SetAlpha(0)
		mote.texture:Hide()
		mote.startRot = math.random() * math.pi * 2
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

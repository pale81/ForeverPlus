-- WorldReactions: subtle physical world and screen-edge reactions:
-- 1. Emerging from water: brief droplets running down the screen edges + wet splash/drip audio.
-- 2. Standing near a campfire: gentle rising embers and a warm amber shimmer along the bottom edge.
-- 3. Worn armor: subtle metallic clinking when armor durability drops below 30%.
local _, ns = ...
local L = ns.L

local WorldReactions = ns:NewModule("WorldReactions", {
	title = L.WORLD_REACTIONS_TITLE,
	order = 5.39,
	defaults = {
		enabled = true,
		waterDrops = true,
		campfireGlow = true,
		armorRattle = true,
		intensity = 75,
	},
})

local TEXTURE = [[Interface\AddOns\ForeverPlus\Media\WorldReactions]]
local PIXEL = 1 / 512

-- UV regions in Media/WorldReactions.tga (512x512) with 1px inset against bilinear bleed.
local UV_GLOW = { PIXEL, 1 - PIXEL, PIXEL, 0.25 - PIXEL }
local UV_RIVULETS = {
	{ PIXEL, 0.125 - PIXEL, 0.25 + PIXEL, 0.75 - PIXEL },        -- primary vertical water rivulet
	{ 0.125 + PIXEL, 0.25 - PIXEL, 0.25 + PIXEL, 0.75 - PIXEL }, -- slender meandering trickle
	{ 0.25 + PIXEL, 0.375 - PIXEL, 0.25 + PIXEL, 0.75 - PIXEL }, -- pinched wet trail with micro-runs
	{ 0.375 + PIXEL, 0.50 - PIXEL, 0.25 + PIXEL, 0.75 - PIXEL }, -- soft translucent water runnel
}
local UV_SHEET = { 0.50 + PIXEL, 1 - PIXEL, 0.25 + PIXEL, 0.75 - PIXEL }
local UV_EMBERS = {
	{ PIXEL, 0.25 - PIXEL, 0.75 + PIXEL, 1 - PIXEL },            -- rising spark with tail
	{ 0.25 + PIXEL, 0.50 - PIXEL, 0.75 + PIXEL, 1 - PIXEL },     -- glowing ash flake
	{ 0.50 + PIXEL, 0.75 - PIXEL, 0.75 + PIXEL, 1 - PIXEL },     -- paired twin embers
	{ 0.75 + PIXEL, 1 - PIXEL, 0.75 + PIXEL, 1 - PIXEL },        -- soft radial spark halo
}

-- Verified Forever 1.60.1.71037 sounds from Data/EmitterSounds.lua.
local WATER_SPLASH_SOUNDS = {
	4531307, 4531309, 4531311, 4531313, 4531315,
	4531317, 4531319, 4531321, 4531323, 4531325,
}
local WATER_DRIP_SOUNDS = {
	5744408, 5744410, 5744412, 5744414, 5744416, 5744418, 4505413,
}
local ARMOR_RATTLE_SOUNDS = {
	1561730, 1561731, 1561732, 1561733, 1561734,
	1561735, 1561736, 1561737, 1561738, 1561739,
}

-- Fallback campfire spell IDs if Minimap has not exposed ns.CAMPFIRE_SPELLS.
local DEFAULT_CAMPFIRE_SPELLS = {
	[1307227] = 15 * 60, -- Basic Campfire
	[1307252] = 15 * 60, -- Journeyman Campfire
	[1307237] = 15 * 60, -- Expert Campfire
}
local COZY_FIRE_SPELL_ID = 7353
local CAMPFIRE_RADIUS = 14
local CAMPFIRE_PREVIEW_DURATION = 4.2
local MAX_TRACKED_FIRES = 8

-- Equipment slots that represent worn armor (same set as Modules/Durability.lua minus weapons/shield).
local ARMOR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10 }
local ARMOR_THRESHOLD = 30
local ARMOR_COOLDOWN = 25.0
local ARMOR_MIN_AIRTIME = 0.15

local SUBMERGED_MIN = 0.35
local SWIM_MIN = 0.50
local WATER_COOLDOWN = 4.0
local WATER_DURATION = 2.55
local WATER_SHEET_DURATION = 0.72
local WATER_DRIP_DELAY = 0.28

local LOGIN_GRACE = 2.0
local POLL_INTERVAL = 0.15
local CAMPFIRE_POLL_INTERVAL = 0.50
local CAMPFIRE_FRAME_INTERVAL = 1 / 30

local mabs, mmax, mmin, mrandom, msin, mPI = math.abs, math.max, math.min, math.random, math.sin, math.pi
local TWO_PI = mPI * 2

local DROP_COUNT = 18
local EMBER_COUNT = 14
-- Stratified camera-lens lanes: { xCenter, xJitter, startYMin, startYMax, alphaBase, combatOnlyEdge }
-- Denser along the outer thirds and upper frame, sparser and lighter across the upper center.
local RIVULET_LANES = {
	{ 0.035, 0.020, 0.74, 1.02, 0.76, true },
	{ 0.075, 0.022, 0.62, 0.96, 0.72, true },
	{ 0.115, 0.024, 0.80, 1.03, 0.68, true },
	{ 0.165, 0.028, 0.84, 1.03, 0.64, false },
	{ 0.225, 0.030, 0.86, 1.03, 0.58, false },
	{ 0.295, 0.032, 0.88, 1.03, 0.52, false },
	{ 0.375, 0.034, 0.92, 1.04, 0.40, false },
	{ 0.460, 0.032, 0.93, 1.04, 0.34, false },
	{ 0.540, 0.032, 0.93, 1.04, 0.34, false },
	{ 0.625, 0.034, 0.92, 1.04, 0.40, false },
	{ 0.705, 0.032, 0.88, 1.03, 0.52, false },
	{ 0.775, 0.030, 0.86, 1.03, 0.58, false },
	{ 0.835, 0.028, 0.84, 1.03, 0.64, false },
	{ 0.885, 0.024, 0.80, 1.03, 0.68, true },
	{ 0.925, 0.022, 0.62, 0.96, 0.72, true },
	{ 0.965, 0.020, 0.74, 1.02, 0.76, true },
	{ 0.055, 0.024, 0.54, 0.84, 0.60, true },
	{ 0.945, 0.024, 0.54, 0.84, 0.60, true },
}

local waterState = {}
local armorState = {}
local soundLast = {}
local trackedFires = {}
local mapWorldSizeCache = {}

local overlay, watchTicker
local glowTexture, sheetTexture, dropPool, emberPool
local dropsActive = false
local dropsElapsed = 0
local dropsCombat = false
local campfireDesired = false
local campfireAlpha = 0
local campfireClock = 0
local campfirePreviewUntil = 0
local hasCozyFireAura = false
local inCombat = false
local campfirePollAt = 0
local animElapsed = 0
local cachedW, cachedH, cachedUiScale = 1280, 720, 1
local cachedIntensity = 0.75
local glowW, glowH, glowShown = 0, 0, false
local sheetShown = false
local audioGen = 0

local function Clamp(value, lo, hi)
	if value < lo then
		return lo
	end
	if value > hi then
		return hi
	end
	return value
end

local function RefreshIntensityCache()
	cachedIntensity = Clamp(ns.Number(WorldReactions.db and WorldReactions.db.intensity, 75) / 100, 0.30, 1.0)
	return cachedIntensity
end

local function RefreshOverlaySize()
	if not overlay then
		cachedW, cachedH, cachedUiScale = 1280, 720, 1
		return
	end
	local w, h = overlay:GetSize()
	w, h = ns.Number(w), ns.Number(h)
	if not w or w < 100 or not h or h < 100 then
		w, h = 1280, 720
	end
	cachedW, cachedH = w, h
	cachedUiScale = mmin(w / 1280, h / 720)
end

local function MapWorldSize(mapID)
	if not (mapID and C_Map and C_Map.GetMapWorldSize) then
		return 0, 0
	end
	local cached = mapWorldSizeCache[mapID]
	if cached then
		return cached[1], cached[2]
	end
	local width, height = C_Map.GetMapWorldSize(mapID)
	width, height = ns.Number(width, 0), ns.Number(height, 0)
	if width > 0 and height > 0 then
		mapWorldSizeCache[mapID] = { width, height }
	end
	return width, height
end

local function PlayFromPool(kind, pool, fallbackKit)
	if PlaySoundFile and pool and #pool > 0 then
		local index = soundLast[kind] and (soundLast[kind] % #pool + 1) or math.random(#pool)
		soundLast[kind] = index
		local ok = PlaySoundFile(pool[index], "SFX")
		if ok then
			return true
		end
	end
	if fallbackKit and PlaySound and SOUNDKIT and SOUNDKIT[fallbackKit] then
		PlaySound(SOUNDKIT[fallbackKit], "SFX")
		return true
	end
	return false
end

local function IsGroupUnit(unit)
	if type(unit) ~= "string" or ns.Secret(unit) then
		return false
	end
	return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local function CampfireSpells()
	return ns.CAMPFIRE_SPELLS or DEFAULT_CAMPFIRE_SPELLS
end

local function WaterBlocked()
	return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
		or (UnitOnTaxi and UnitOnTaxi("player"))
		or (IsFlying and IsFlying())
		or false
end

local function ArmorBlocked()
	return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
		or (UnitOnTaxi and UnitOnTaxi("player"))
		or (IsSwimming and IsSwimming())
		or (IsFlying and IsFlying())
		or false
end

---------------------------------------------------------------------------
-- Pure state transitions (exposed for deterministic unit tests)
---------------------------------------------------------------------------

-- Returns true when the player emerges from underwater or climbs out of swimming water.
function WorldReactions.StepWater(state, submerged, swimming, now, blocked)
	if blocked then
		state.submergedSince = nil
		state.swimmingSince = nil
		return false
	end
	if state.graceUntil and now < state.graceUntil then
		state.submergedSince = submerged and (state.submergedSince or now) or nil
		state.swimmingSince = swimming and (state.swimmingSince or now) or nil
		return false
	end
	local triggered = false
	if submerged then
		state.submergedSince = state.submergedSince or now
	elseif state.submergedSince then
		if now - state.submergedSince >= SUBMERGED_MIN then
			triggered = true
		end
		state.submergedSince = nil
	end
	if swimming then
		state.swimmingSince = state.swimmingSince or now
	elseif state.swimmingSince then
		if now - state.swimmingSince >= SWIM_MIN then
			triggered = true
		end
		state.swimmingSince = nil
	end
	if not triggered then
		return false
	end
	if state.lastTrigger and now - state.lastTrigger < WATER_COOLDOWN then
		return false
	end
	state.lastTrigger = now
	return true
end

-- Lowest durability percentage (0-100) across worn armor slots, or nil when none have durability.
function WorldReactions.LowestArmorDurability()
	if not GetInventoryItemDurability then
		return nil
	end
	local lowest
	for _, slot in ipairs(ARMOR_SLOTS) do
		local current, maximum = GetInventoryItemDurability(slot)
		current, maximum = ns.Number(current), ns.Number(maximum)
		if current and maximum and maximum > 0 then
			local percent = math.max(math.floor(current / maximum * 100 + 0.5), 0)
			if not lowest or percent < lowest then
				lowest = percent
			end
		end
	end
	return lowest
end

-- Triggers a metallic clink on first crossing below 30% armor durability or on landing while below 30%.
function WorldReactions.StepArmor(state, lowest, falling, now, blocked)
	local worn = lowest ~= nil and lowest < ARMOR_THRESHOLD
	if not state.initialized then
		state.initialized = true
		state.wasWorn = worn
		state.fallingSince = nil
		return false
	end
	if blocked then
		state.fallingSince = nil
		state.wasWorn = worn
		return false
	end
	if state.graceUntil and now < state.graceUntil then
		state.fallingSince = nil
		state.wasWorn = worn
		return false
	end
	local triggered = false
	if worn and not state.wasWorn then
		triggered = true
	end
	state.wasWorn = worn
	if worn then
		if falling then
			state.fallingSince = state.fallingSince or now
		elseif state.fallingSince then
			if now - state.fallingSince >= ARMOR_MIN_AIRTIME then
				triggered = true
			end
			state.fallingSince = nil
		end
	else
		state.fallingSince = nil
	end
	if not triggered then
		return false
	end
	if state.lastRattle and now - state.lastRattle < ARMOR_COOLDOWN then
		return false
	end
	state.lastRattle = now
	return true
end

---------------------------------------------------------------------------
-- Campfire detection (Cozy Fire aura 7353 + tracked campfire proximity)
---------------------------------------------------------------------------

local function AurasAreSecret()
	return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false
end

local function ScanCozyFireAura()
	if not C_UnitAuras or AurasAreSecret() then
		return nil
	end
	if C_UnitAuras.GetPlayerAuraBySpellID then
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(COZY_FIRE_SPELL_ID)
		if ns.Secret(aura) then
			return nil
		end
		return aura ~= nil
	end
	if C_UnitAuras.GetAuraDataByIndex then
		local index = 1
		while true do
			local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
			if ns.Secret(aura) then
				return nil
			end
			if not aura then
				break
			end
			local spellID = ns.Number(aura.spellId)
			if spellID == COZY_FIRE_SPELL_ID then
				return true
			end
			index = index + 1
		end
		return false
	end
	return false
end

local function RefreshCozyFireAura()
	local ok, found = pcall(ScanCozyFireAura)
	if ok and found ~= nil then
		hasCozyFireAura = found
	end
end

local function RecordTrackedCampfire(unit, duration)
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
		return
	end
	local mapID = C_Map.GetBestMapForUnit(unit)
	local playerMapID = C_Map.GetBestMapForUnit("player")
	if not mapID or mapID ~= playerMapID then
		return
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, unit)
	if not pos then
		return
	end
	local x, y = pos:GetXY()
	x, y = ns.Number(x), ns.Number(y)
	if not (x and y) then
		return
	end
	local now = ns.Number(GetTime(), 0)
	trackedFires[#trackedFires + 1] = { mapID = mapID, x = x, y = y, expires = now + duration }
	while #trackedFires > MAX_TRACKED_FIRES do
		table.remove(trackedFires, 1)
	end
end

local function HasLocalTrackedCampfireNearPlayer(now)
	if #trackedFires == 0 then
		return false
	end
	local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = currentMapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(currentMapID, "player")
	local width, height = MapWorldSize(currentMapID)
	local px, py
	if pos then
		px, py = pos:GetXY()
		px, py = ns.Number(px), ns.Number(py)
	end
	local limitSq = CAMPFIRE_RADIUS * CAMPFIRE_RADIUS
	local near = false
	for i = #trackedFires, 1, -1 do
		local fire = trackedFires[i]
		if fire.expires <= now then
			table.remove(trackedFires, i)
		elseif not near and px and py and width > 0 and height > 0 and fire.mapID == currentMapID then
			local dx = (fire.x - px) * width
			local dy = (py - fire.y) * height
			if dx * dx + dy * dy <= limitSq then
				near = true
			end
		end
	end
	return near
end

function WorldReactions.IsNearCampfire(now)
	now = now or ns.Number(GetTime(), 0)
	if campfirePreviewUntil > now then
		return true
	end
	if inCombat or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
		return false
	end
	if hasCozyFireAura then
		return true
	end
	if ns.HasCampfireNearPlayer and ns.HasCampfireNearPlayer(CAMPFIRE_RADIUS) then
		return true
	end
	return HasLocalTrackedCampfireNearPlayer(now)
end

---------------------------------------------------------------------------
-- Overlay creation & animation
---------------------------------------------------------------------------

local function ResetEmber(ember, stagger)
	ember.x = 0.08 + mrandom() * 0.84
	ember.y = mrandom() * 0.035
	ember.rise = 0.14 + mrandom() * 0.14
	ember.drift = (mrandom() - 0.5) * 0.065
	ember.swayAmp = 0.008 + mrandom() * 0.014
	ember.swayFreq = 2.0 + mrandom() * 2.5
	ember.phase = mrandom() * TWO_PI
	ember.duration = 2.2 + mrandom() * 2.0
	ember.age = stagger and (mrandom() * ember.duration) or 0
	ember.size = 10 + mrandom() * 14
	ember.alpha = 0.45 + mrandom() * 0.40
	ember.lastSize = nil
	local uv = UV_EMBERS[mrandom(#UV_EMBERS)]
	ember.texture:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
end

local function EnsureOverlay()
	if overlay then
		return overlay
	end
	overlay = CreateFrame("Frame", "ForeverPlusWorldReactions", UIParent)
	overlay:SetAllPoints()
	overlay:EnableMouse(false)
	overlay:SetFrameStrata("BACKGROUND")
	overlay:SetFrameLevel(1)
	overlay:SetScript("OnSizeChanged", RefreshOverlaySize)
	overlay:Hide()
	RefreshOverlaySize()

	glowTexture = overlay:CreateTexture(nil, "ARTWORK")
	glowTexture:SetTexture(TEXTURE)
	glowTexture:SetTexCoord(UV_GLOW[1], UV_GLOW[2], UV_GLOW[3], UV_GLOW[4])
	glowTexture:SetBlendMode("ADD")
	glowTexture:SetVertexColor(1.0, 0.48, 0.14, 1.0)
	glowTexture:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
	glowTexture:Hide()
	glowW, glowH, glowShown = 0, 0, false

	emberPool = {}
	for i = 1, EMBER_COUNT do
		local tex = overlay:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(TEXTURE)
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(1.0, 0.62, 0.20, 1.0)
		tex:Hide()
		local ember = { texture = tex, shown = false }
		ResetEmber(ember, true)
		emberPool[i] = ember
	end

	sheetTexture = overlay:CreateTexture(nil, "ARTWORK")
	sheetTexture:SetTexture(TEXTURE)
	sheetTexture:SetTexCoord(UV_SHEET[1], UV_SHEET[2], UV_SHEET[3], UV_SHEET[4])
	sheetTexture:SetBlendMode("BLEND")
	sheetTexture:SetVertexColor(0.90, 0.96, 1.0, 1.0)
	sheetTexture:Hide()
	sheetShown = false

	dropPool = {}
	for i = 1, DROP_COUNT do
		local tex = overlay:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(TEXTURE)
		tex:SetBlendMode("BLEND")
		tex:SetVertexColor(0.90, 0.96, 1.0, 1.0)
		tex:Hide()
		dropPool[i] = { texture = tex, shown = false }
	end

	return overlay
end

local function HideWaterTextures()
	if dropPool then
		for i = 1, #dropPool do
			local drop = dropPool[i]
			if drop.shown then
				drop.shown = false
				drop.texture:Hide()
			end
		end
	end
	if sheetTexture and sheetShown then
		sheetShown = false
		sheetTexture:Hide()
	end
end

local function HideCampfireTextures()
	if glowTexture and glowShown then
		glowShown = false
		glowTexture:Hide()
	end
	if emberPool then
		for i = 1, #emberPool do
			local ember = emberPool[i]
			if ember.shown then
				ember.shown = false
				ember.texture:Hide()
			end
		end
	end
end

local function StopOverlay()
	dropsActive = false
	dropsElapsed = 0
	campfireDesired = false
	campfireAlpha = 0
	campfirePreviewUntil = 0
	animElapsed = 0
	if overlay then
		overlay:SetScript("OnUpdate", nil)
		HideCampfireTextures()
		HideWaterTextures()
		overlay:Hide()
	end
end

local function AnimateOverlay(delta)
	local w, h, uiScale = cachedW, cachedH, cachedUiScale
	local intensity = cachedIntensity
	local stillRunning = false

	-- 1. Camera-lens water runoff: receding water film + vertical running rivulets
	if dropsActive then
		dropsElapsed = dropsElapsed + delta
		local combatFactor = dropsCombat and 0.35 or 1.0
		local anyDrop = false

		-- Brief receding water film gliding down from the top of the camera lens.
		if sheetTexture then
			local sp = dropsElapsed / WATER_SHEET_DURATION
			if sp < 1 then
				anyDrop = true
				local ease = 1.0 - (1.0 - sp) * (1.0 - sp)
				local sheetHeight = h * (0.46 + 0.14 * sp)
				-- Bottom edge starts near upper lens (y = 0.78) and slides cleanly down off-screen.
				local bottomY = (0.78 - 0.84 * ease) * h
				local fadeIn = msin(Clamp(sp / 0.16, 0, 1) * mPI * 0.5)
				local fadeOut = (1.0 - sp) ^ 1.15
				local sheetCombat = dropsCombat and 0.25 or 1.0
				sheetTexture:SetSize(w * 1.04, sheetHeight)
				sheetTexture:SetPoint("BOTTOM", overlay, "BOTTOM", 0, bottomY)
				sheetTexture:SetAlpha(0.62 * fadeIn * fadeOut * intensity * sheetCombat)
				if not sheetShown then
					sheetShown = true
					sheetTexture:Show()
				end
			elseif sheetShown then
				sheetShown = false
				sheetTexture:Hide()
			end
		end

		for i = 1, #dropPool do
			local drop = dropPool[i]
			if drop.active then
				local t = dropsElapsed - drop.delay
				if t >= 0 and t < drop.duration then
					anyDrop = true
					local p = t / drop.duration
					local fadeIn = Clamp(p / 0.10, 0, 1)
					local fadeOut = p > 0.66 and Clamp((1 - p) / 0.34, 0, 1) or 1
					local runT = mmax(0, t - drop.cling)
					local runNorm = runT / mmax(0.2, drop.duration - drop.cling)
					-- Brisk initial gravity runoff with subtle stick-slip hesitation.
					local gravity = 1.0 - (1.0 - runNorm) ^ 1.65
					local slip = 0.016 * msin(runNorm * drop.slipFreq * mPI + drop.phase) * (1.0 - runNorm)
					local fall = drop.travel * Clamp(gravity + slip, 0, 1.04)
					local headY = drop.startY - fall
					-- Top of the wet trail lingers near startY while the head runs ahead, then drains down.
					local tailLag = Clamp((runNorm - 0.12) / 0.88, 0, 1)
					local tailY = drop.startY - fall * (0.42 * tailLag * tailLag)
					local minLen = mmax(drop.maxLen * 0.38, drop.width * 3.2) * uiScale
					local maxLen = drop.maxLen * uiScale
					local streakLen = Clamp((tailY - headY) * h, minLen, maxLen)
					local width = drop.width * uiScale * (1.0 - 0.28 * p)
					local x = Clamp(drop.x + drop.drift * runNorm, 0.01, 0.99)

					drop.texture:SetSize(width, streakLen)
					drop.texture:SetPoint("BOTTOM", overlay, "BOTTOMLEFT", x * w, headY * h)
					drop.texture:SetAlpha(drop.alpha * fadeIn * fadeOut * intensity * combatFactor)
					if not drop.shown then
						drop.shown = true
						drop.texture:Show()
					end
				elseif t < 0 then
					anyDrop = true
					if drop.shown then
						drop.shown = false
						drop.texture:Hide()
					end
				elseif drop.shown then
					drop.shown = false
					drop.texture:Hide()
				end
			elseif drop.shown then
				drop.shown = false
				drop.texture:Hide()
			end
		end

		if anyDrop and dropsElapsed < WATER_DURATION + 0.6 then
			stillRunning = true
		else
			dropsActive = false
			HideWaterTextures()
		end
	end

	-- 2. Campfire warm bottom glow & rising embers
	local target = campfireDesired and 1 or 0
	if target > campfireAlpha then
		campfireAlpha = mmin(target, campfireAlpha + delta / 0.75)
	elseif target < campfireAlpha then
		campfireAlpha = mmax(target, campfireAlpha - delta / 0.40)
	end

	if campfireAlpha > 0.002 then
		stillRunning = true
		campfireClock = campfireClock + delta
		local breath = 0.5
			+ 0.32 * msin(campfireClock * 0.4 * TWO_PI)
			+ 0.18 * msin(campfireClock * 1.1 * TWO_PI + 1.3)
		local glowAlpha = (0.16 + 0.10 * breath) * campfireAlpha * intensity
		if w ~= glowW or h ~= glowH then
			glowW, glowH = w, h
			glowTexture:SetSize(w * 0.92, h * 0.165)
		end
		glowTexture:SetAlpha(glowAlpha)
		if not glowShown then
			glowShown = true
			glowTexture:Show()
		end

		local alphaScale = campfireAlpha * intensity
		for i = 1, #emberPool do
			local ember = emberPool[i]
			ember.age = ember.age + delta
			if ember.age >= ember.duration then
				if campfireDesired then
					ResetEmber(ember, false)
				elseif ember.shown then
					ember.shown = false
					ember.texture:Hide()
				end
			end
			if ember.age < ember.duration then
				local p = ember.age / ember.duration
				local fadeIn = Clamp(p / 0.18, 0, 1)
				local fadeOut = Clamp((1 - p) / 0.36, 0, 1)
				local flicker = 0.78 + 0.22 * msin(campfireClock * 7.5 + ember.phase)
				local x = ember.x + ember.drift * p + msin(p * ember.swayFreq * mPI + ember.phase) * ember.swayAmp
				local y = ember.y + ember.rise * (p * (1.15 - 0.15 * p))
				local size = ember.size * uiScale * (1.0 - 0.35 * p)

				if not ember.lastSize or mabs(size - ember.lastSize) >= 0.5 then
					ember.lastSize = size
					ember.texture:SetSize(size, size)
				end
				ember.texture:SetPoint("CENTER", overlay, "BOTTOMLEFT", Clamp(x, 0.02, 0.98) * w, Clamp(y, 0.01, 0.32) * h)
				ember.texture:SetAlpha(ember.alpha * fadeIn * fadeOut * flicker * alphaScale)
				if not ember.shown then
					ember.shown = true
					ember.texture:Show()
				end
			end
		end
	else
		campfireAlpha = 0
		HideCampfireTextures()
	end

	if not stillRunning then
		animElapsed = 0
		overlay:SetScript("OnUpdate", nil)
		overlay:Hide()
	end
end

local RunAnimateOverlay = ns.Measured("WorldReactions: animate", AnimateOverlay)

-- Throttle steady campfire shimmer/embers to 30 FPS and skip measurement on idle wait frames;
-- keep short water runoff at full frame rate for smooth downward streaks.
local function OnAnimateUpdate(_, elapsed)
	local delta = ns.Number(elapsed, 0)
	if dropsActive then
		local step = mmin(animElapsed + delta, 0.1)
		animElapsed = 0
		RunAnimateOverlay(step)
		return
	end
	animElapsed = animElapsed + delta
	if animElapsed < CAMPFIRE_FRAME_INTERVAL then
		return
	end
	local step = mmin(animElapsed, 0.1)
	animElapsed = 0
	RunAnimateOverlay(step)
end

local function EnsureAnimationRunning()
	local frame = EnsureOverlay()
	RefreshOverlaySize()
	RefreshIntensityCache()
	frame:Show()
	if not frame:GetScript("OnUpdate") then
		animElapsed = CAMPFIRE_FRAME_INTERVAL
		frame:SetScript("OnUpdate", OnAnimateUpdate)
	end
end

---------------------------------------------------------------------------
-- Trigger actions (live + menu preview)
---------------------------------------------------------------------------

function WorldReactions.TriggerWater(isPreview)
	EnsureOverlay()
	dropsCombat = (not isPreview) and inCombat
	dropsElapsed = 0
	dropsActive = true

	if sheetTexture then
		if mrandom() < 0.5 then
			sheetTexture:SetTexCoord(UV_SHEET[2], UV_SHEET[1], UV_SHEET[3], UV_SHEET[4])
		else
			sheetTexture:SetTexCoord(UV_SHEET[1], UV_SHEET[2], UV_SHEET[3], UV_SHEET[4])
		end
		if sheetShown then
			sheetShown = false
			sheetTexture:Hide()
		end
	end

	for i, drop in ipairs(dropPool) do
		local lane = RIVULET_LANES[i] or RIVULET_LANES[((i - 1) % #RIVULET_LANES) + 1]
		local edgeOnly = lane[6]
		drop.active = (not dropsCombat) or edgeOnly
		drop.x = Clamp(lane[1] + (mrandom() * 2 - 1) * lane[2], 0.015, 0.985)
		drop.startY = lane[3] + mrandom() * (lane[4] - lane[3])
		drop.delay = mrandom() * 0.22
		drop.cling = 0.02 + mrandom() * 0.12
		drop.duration = 1.70 + mrandom() * 0.75
		drop.travel = 0.52 + mrandom() * 0.34
		drop.width = 24 + mrandom() * 20
		drop.maxLen = 220 + mrandom() * 200
		drop.drift = (mrandom() - 0.5) * 0.014
		drop.slipFreq = 2.0 + mrandom() * 1.8
		drop.phase = mrandom() * TWO_PI
		drop.alpha = Clamp(lane[5] + (mrandom() - 0.5) * 0.18, 0.24, 0.95)
		local uv = UV_RIVULETS[((i - 1) % #UV_RIVULETS) + 1]
		if mrandom() < 0.5 then
			drop.texture:SetTexCoord(uv[2], uv[1], uv[3], uv[4])
		else
			drop.texture:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
		end
		if drop.shown then
			drop.shown = false
			drop.texture:Hide()
		end
	end

	EnsureAnimationRunning()

	audioGen = audioGen + 1
	local gen = audioGen
	PlayFromPool("waterSplash", WATER_SPLASH_SOUNDS)
	ns.After("WorldReactions: water drip", WATER_DRIP_DELAY, function()
		if gen ~= audioGen then
			return
		end
		if not isPreview and not (WorldReactions.db and WorldReactions.db.enabled and WorldReactions.db.waterDrops) then
			return
		end
		PlayFromPool("waterDrip", WATER_DRIP_SOUNDS)
	end)
end

function WorldReactions.SetCampfireActive(active)
	active = active and true or false
	if active == campfireDesired then
		return
	end
	campfireDesired = active
	if active then
		EnsureOverlay()
		EnsureAnimationRunning()
	end
end

function WorldReactions.PreviewCampfire()
	local now = ns.Number(GetTime(), 0)
	campfirePreviewUntil = now + CAMPFIRE_PREVIEW_DURATION
	WorldReactions.SetCampfireActive(true)
	ns.After("WorldReactions: campfire preview end", CAMPFIRE_PREVIEW_DURATION + 0.05, function()
		local current = ns.Number(GetTime(), 0)
		if campfirePreviewUntil <= current then
			campfirePreviewUntil = 0
			local want = WorldReactions.db and WorldReactions.db.enabled and WorldReactions.db.campfireGlow
				and WorldReactions.IsNearCampfire(current)
			WorldReactions.SetCampfireActive(want)
		end
	end)
end

function WorldReactions.PlayArmorRattle()
	return PlayFromPool("armorRattle", ARMOR_RATTLE_SOUNDS, "PUT_DOWN_SMALL_CHAIN")
end

---------------------------------------------------------------------------
-- Events & watcher
---------------------------------------------------------------------------

local function RefreshArmorDurability(now)
	if not (WorldReactions.db and WorldReactions.db.enabled and WorldReactions.db.armorRattle) then
		return
	end
	local lowest = WorldReactions.LowestArmorDurability()
	local falling = IsFalling and IsFalling() or false
	if WorldReactions.StepArmor(armorState, lowest, falling, now or ns.Number(GetTime(), 0), ArmorBlocked()) then
		WorldReactions.PlayArmorRattle()
	end
end

local function RefreshCampfireState(now)
	if not (WorldReactions.db and WorldReactions.db.enabled and WorldReactions.db.campfireGlow) then
		if campfirePreviewUntil <= (now or ns.Number(GetTime(), 0)) then
			WorldReactions.SetCampfireActive(false)
		end
		return
	end
	WorldReactions.SetCampfireActive(WorldReactions.IsNearCampfire(now))
end

local function OnWatch()
	local db = WorldReactions.db
	if not (db and db.enabled) then
		return
	end
	local now = ns.Number(GetTime(), 0)

	-- Landing check for worn armor only runs while armor is actually below 30%.
	if db.armorRattle and armorState.wasWorn and IsFalling then
		local falling = IsFalling()
		if falling or armorState.fallingSince then
			if WorldReactions.StepArmor(armorState, 0, falling, now, ArmorBlocked()) then
				WorldReactions.PlayArmorRattle()
			end
		end
	end

	if db.waterDrops then
		local submerged = IsSubmerged and IsSubmerged() or false
		local swimming = IsSwimming and IsSwimming() or false
		if submerged or swimming or waterState.submergedSince or waterState.swimmingSince then
			if WorldReactions.StepWater(waterState, submerged, swimming, now, WaterBlocked()) then
				WorldReactions.TriggerWater(false)
			end
		end
	end

	-- Cozy Fire aura is event-driven via UNIT_AURA; only poll distance when tracked fires or a preview exist.
	if db.campfireGlow and now >= campfirePollAt then
		local needPoll = campfirePreviewUntil > 0 or #trackedFires > 0
			or (ns.HasTrackedCampfires and ns.HasTrackedCampfires())
		if needPoll then
			campfirePollAt = now + CAMPFIRE_POLL_INTERVAL
			RefreshCampfireState(now)
		end
	end
end

local function ResetGrace()
	local now = ns.Number(GetTime(), 0)
	waterState.graceUntil = now + LOGIN_GRACE
	waterState.submergedSince = nil
	waterState.swimmingSince = nil
	armorState.graceUntil = now + LOGIN_GRACE
	armorState.initialized = nil
	armorState.fallingSince = nil
end

local function OnEnteringWorld()
	inCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
	ResetGrace()
	RefreshCozyFireAura()
	RefreshArmorDurability(ns.Number(GetTime(), 0))
	RefreshCampfireState(ns.Number(GetTime(), 0))
end

local function OnUnitAura(_, _, unit)
	if ns.Secret(unit) or unit ~= "player" then
		return
	end
	RefreshCozyFireAura()
	RefreshCampfireState(ns.Number(GetTime(), 0))
end

local function OnSpellcastSucceeded(_, _, unit, _, spellID)
	if type(spellID) ~= "number" or ns.Secret(spellID) then
		return
	end
	local duration = CampfireSpells()[spellID]
	if not duration or not IsGroupUnit(unit) then
		return
	end
	RecordTrackedCampfire(unit, duration)
	RefreshCampfireState(ns.Number(GetTime(), 0))
end

local function OnCombatStart()
	inCombat = true
	RefreshCampfireState(ns.Number(GetTime(), 0))
end

local function OnCombatEnd()
	inCombat = false
	RefreshCozyFireAura()
	RefreshCampfireState(ns.Number(GetTime(), 0))
end

local function OnDurabilityChanged()
	RefreshArmorDurability(ns.Number(GetTime(), 0))
end

function WorldReactions.GetState()
	return {
		dropsActive = dropsActive,
		campfireDesired = campfireDesired,
		campfireAlpha = campfireAlpha,
		hasCozyFireAura = hasCozyFireAura,
		inCombat = inCombat,
		armorWorn = armorState.wasWorn and true or false,
		watcherActive = watchTicker ~= nil,
		overlayShown = overlay and overlay:IsShown() or false,
	}
end

function WorldReactions:Apply()
	local db = self.db
	local on = db.enabled and true or false
	local needCampfire = on and db.campfireGlow
	local needArmor = on and db.armorRattle
	local needWatch = on and (db.waterDrops or db.campfireGlow or db.armorRattle)
	RefreshIntensityCache()

	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, OnEnteringWorld)
	self:ToggleEvent("PLAYER_REGEN_DISABLED", on, OnCombatStart)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", on, OnCombatEnd)
	self:ToggleEvent("UNIT_AURA", needCampfire, OnUnitAura)
	self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", needCampfire, OnSpellcastSucceeded)
	self:ToggleEvent("UPDATE_INVENTORY_DURABILITY", needArmor, OnDurabilityChanged)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", needArmor, OnDurabilityChanged)

	campfirePollAt = 0
	if needWatch then
		if not watchTicker then
			watchTicker = ns.NewTicker("WorldReactions: watch", POLL_INTERVAL, OnWatch)
		end
	elseif watchTicker then
		watchTicker:Cancel()
		watchTicker = nil
	end

	if not on then
		audioGen = audioGen + 1
		StopOverlay()
		return
	end

	inCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
	if needCampfire then
		RefreshCozyFireAura()
		RefreshCampfireState(ns.Number(GetTime(), 0))
	else
		campfirePreviewUntil = 0
		WorldReactions.SetCampfireActive(false)
	end
	if needArmor then
		RefreshArmorDurability(ns.Number(GetTime(), 0))
	else
		armorState.wasWorn = false
		armorState.fallingSince = nil
	end
	if not db.waterDrops then
		audioGen = audioGen + 1
		dropsActive = false
		dropsElapsed = 0
		waterState.submergedSince = nil
		waterState.swimmingSince = nil
		HideWaterTextures()
	end
end

function WorldReactions:OnLogin()
	ResetGrace()
	self:Apply()
end

function WorldReactions:OnOptionChanged()
	self:Apply()
end

WorldReactions.options = {
	{ key = "enabled", type = "toggle", name = L.WORLD_REACTIONS_ENABLE, desc = L.WORLD_REACTIONS_ENABLE_DESC, new = true },
	{ key = "waterDrops", type = "toggle", name = L.WORLD_REACTIONS_WATER, desc = L.WORLD_REACTIONS_WATER_DESC,
		parent = "enabled", new = true },
	{ type = "button", name = L.WORLD_REACTIONS_WATER_TEST, text = L.WORLD_REACTIONS_TEST_BUTTON,
		desc = L.WORLD_REACTIONS_WATER_TEST_DESC, func = function()
			WorldReactions.TriggerWater(true)
		end },
	{ key = "campfireGlow", type = "toggle", name = L.WORLD_REACTIONS_CAMPFIRE, desc = L.WORLD_REACTIONS_CAMPFIRE_DESC,
		parent = "enabled", new = true },
	{ type = "button", name = L.WORLD_REACTIONS_CAMPFIRE_TEST, text = L.WORLD_REACTIONS_TEST_BUTTON,
		desc = L.WORLD_REACTIONS_CAMPFIRE_TEST_DESC, func = function()
			WorldReactions.PreviewCampfire()
		end },
	{ key = "armorRattle", type = "toggle", name = L.WORLD_REACTIONS_ARMOR, desc = L.WORLD_REACTIONS_ARMOR_DESC,
		parent = "enabled", new = true },
	{ type = "button", name = L.WORLD_REACTIONS_ARMOR_TEST, text = L.WORLD_REACTIONS_TEST_BUTTON,
		desc = L.WORLD_REACTIONS_ARMOR_TEST_DESC, func = function()
			WorldReactions.PlayArmorRattle()
		end },
	{ key = "intensity", type = "slider", name = L.WORLD_REACTIONS_INTENSITY, desc = L.WORLD_REACTIONS_INTENSITY_DESC,
		min = 30, max = 100, step = 5, format = function(v) return ("%d %%"):format(v) end,
		parent = "enabled", new = true },
}

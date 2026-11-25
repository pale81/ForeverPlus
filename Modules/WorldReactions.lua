-- WorldReactions: subtle physical world and screen-edge reactions:
-- 1. Emerging from water: brief droplets running down the screen edges + wet splash/drip audio.
-- 2. Standing near a campfire: gentle rising embers and a warm amber shimmer along the bottom edge.
-- 3. Weapon drawing/sheathing & worn armor: weapon-type sound on sheath transitions and subtle
--    metallic clinking when armor durability drops below 30%.
local _, ns = ...
local L = ns.L

local WorldReactions = ns:NewModule("WorldReactions", {
	title = L.WORLD_REACTIONS_TITLE,
	order = 5.39,
	defaults = {
		enabled = true,
		waterDrops = true,
		campfireGlow = true,
		weaponSheathSound = true,
		armorRattle = true,
		intensity = 75,
	},
})

local TEXTURE = [[Interface\AddOns\ForeverPlus\Media\WorldReactions]]
local PIXEL = 1 / 256

-- UV regions in Media/WorldReactions.tga (256x256) with 1px inset against bilinear bleed.
local UV_GLOW = { PIXEL, 1 - PIXEL, PIXEL, 0.375 - PIXEL }
local UV_DROPS = {
	{ PIXEL, 0.25 - PIXEL, 0.375 + PIXEL, 0.625 - PIXEL }, -- running droplet with streak
	{ 0.25 + PIXEL, 0.50 - PIXEL, 0.375 + PIXEL, 0.625 - PIXEL }, -- round clinging bead
	{ 0.50 + PIXEL, 0.75 - PIXEL, 0.375 + PIXEL, 0.625 - PIXEL }, -- elongated side droplet
}
local UV_MIST = { 0.75 + PIXEL, 1 - PIXEL, 0.375 + PIXEL, 0.625 - PIXEL }
local UV_EMBERS = {
	{ PIXEL, 0.25 - PIXEL, 0.625 + PIXEL, 0.875 - PIXEL }, -- rising spark with tail
	{ 0.25 + PIXEL, 0.50 - PIXEL, 0.625 + PIXEL, 0.875 - PIXEL }, -- glowing ash flake
	{ 0.50 + PIXEL, 0.75 - PIXEL, 0.625 + PIXEL, 0.875 - PIXEL }, -- paired twin embers
	{ 0.75 + PIXEL, 1 - PIXEL, 0.625 + PIXEL, 0.875 - PIXEL }, -- soft radial spark halo
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

-- Classic / Forever interface sheath sounds (community listfile).
local SHEATH_SOUNDS = {
	metal = { unsheath = 567473, sheath = 567498 },
	wood = { unsheath = 567506, sheath = 567456 },
	shield = { unsheath = 567430, sheath = 567395 },
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
local WATER_DURATION = 2.45
local WATER_DRIP_DELAY = 0.28

local SHEATH_DEBOUNCE = 0.15
local SHEATH_COOLDOWN = 0.45
local LOGIN_GRACE = 2.0
local POLL_INTERVAL = 0.10

local DROP_COUNT = 14
local MIST_COUNT = 4
local EMBER_COUNT = 14
local MIST_ANCHORS = {
	{ 0.05, 0.88, 170 },
	{ 0.95, 0.88, 170 },
	{ 0.04, 0.52, 150 },
	{ 0.96, 0.52, 150 },
}

-- Weapon subclass classification (Enum.ItemWeaponSubclass values).
local WOOD_SUBCLASSES = {
	[2] = true, -- Bows
	[10] = true, -- Staff
	[16] = true, -- Thrown
	[18] = true, -- Crossbow
	[19] = true, -- Wand
	[20] = true, -- Fishingpole
}
local METAL_SUBCLASSES = {
	[0] = true, -- Axe1H
	[1] = true, -- Axe2H
	[3] = true, -- Guns
	[4] = true, -- Mace1H
	[5] = true, -- Mace2H
	[6] = true, -- Polearm
	[7] = true, -- Sword1H
	[8] = true, -- Sword2H
	[9] = true, -- Warglaive
	[11] = true, -- Bearclaw
	[12] = true, -- Catclaw
	[13] = true, -- Unarmed / Fist
	[15] = true, -- Dagger
}

local waterState = {}
local sheathState = {}
local armorState = {}
local soundLast = {}
local trackedFires = {}

local overlay, watcher
local glowTexture, dropPool, mistPool, emberPool
local dropsActive = false
local dropsElapsed = 0
local dropsCombat = false
local campfireDesired = false
local campfireAlpha = 0
local campfireClock = 0
local campfirePreviewUntil = 0
local hasCozyFireAura = false
local inCombat = false
local watchElapsed = 0
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

local function IntensityScale()
	return Clamp(ns.Number(WorldReactions.db and WorldReactions.db.intensity, 75) / 100, 0.30, 1.0)
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

local function PlaySingleSound(fileID, fallbackKit)
	if fileID and PlaySoundFile then
		local ok = PlaySoundFile(fileID, "SFX")
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

local function SheathBlocked()
	return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
		or (UnitOnTaxi and UnitOnTaxi("player"))
		or (IsMounted and IsMounted())
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

-- Tracks GetSheathState() transitions (1 = sheathed, 2 = melee, 3 = ranged).
-- Returns action ("unsheath" | "sheath") and mode ("melee" | "ranged"), or nil.
function WorldReactions.StepSheath(state, sheath, now, blocked)
	sheath = ns.Number(sheath)
	if not sheath or sheath < 1 or sheath > 3 then
		state.pending = nil
		return nil
	end
	if blocked then
		state.confirmed = sheath
		state.pending = nil
		return nil
	end
	if state.confirmed == nil or (state.graceUntil and now < state.graceUntil) then
		state.confirmed = sheath
		state.pending = nil
		return nil
	end
	if sheath == state.confirmed then
		state.pending = nil
		return nil
	end
	if state.pending ~= sheath then
		state.pending = sheath
		state.pendingSince = now
		return nil
	end
	if now - (state.pendingSince or now) < SHEATH_DEBOUNCE then
		return nil
	end
	local prev = state.confirmed
	state.confirmed = sheath
	state.pending = nil
	if state.lastSound and now - state.lastSound < SHEATH_COOLDOWN then
		return nil
	end
	state.lastSound = now
	local action = sheath == 1 and "sheath" or "unsheath"
	local mode = (sheath == 3 or (sheath == 1 and prev == 3)) and "ranged" or "melee"
	return action, mode
end

-- Classifies the equipped weapon for the given sheath mode ("melee" | "ranged").
-- Returns "metal", "wood", "shield", or nil when unarmed.
function WorldReactions.WeaponSoundKind(mode)
	local getID = GetInventoryItemID
	local getInfo = C_Item and C_Item.GetItemInfoInstant
	if not (getID and getInfo) then
		return nil
	end
	local function ClassifySlot(slot)
		local itemID = ns.Number(getID("player", slot))
		if not itemID then
			return nil
		end
		local _, _, _, _, _, classID, subClassID = getInfo(itemID)
		classID, subClassID = ns.Number(classID), ns.Number(subClassID)
		if classID == 2 then -- Enum.ItemClass.Weapon
			if WOOD_SUBCLASSES[subClassID] then
				return "wood"
			end
			if METAL_SUBCLASSES[subClassID] then
				return "metal"
			end
			return "metal"
		end
		if classID == 4 and subClassID == 6 then -- Enum.ItemClass.Armor / Shield
			return "shield"
		end
		return nil
	end

	if mode == "ranged" then
		local ranged = ClassifySlot(INVSLOT_RANGED or 18)
		if ranged then
			return ranged
		end
	end
	local main = ClassifySlot(INVSLOT_MAINHAND or 16)
	if main then
		return main
	end
	return ClassifySlot(INVSLOT_OFFHAND or 17)
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
	local width, height
	if currentMapID and C_Map.GetMapWorldSize then
		width, height = C_Map.GetMapWorldSize(currentMapID)
	end
	width, height = ns.Number(width, 0), ns.Number(height, 0)
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

local function RootSize()
	if not overlay then
		return 1280, 720
	end
	local w, h = overlay:GetSize()
	w, h = ns.Number(w), ns.Number(h)
	if not w or w < 100 or not h or h < 100 then
		return 1280, 720
	end
	return w, h
end

local function ResetEmber(ember, stagger)
	ember.x = 0.08 + math.random() * 0.84
	ember.y = math.random() * 0.035
	ember.rise = 0.14 + math.random() * 0.14
	ember.drift = (math.random() - 0.5) * 0.065
	ember.swayAmp = 0.008 + math.random() * 0.014
	ember.swayFreq = 2.0 + math.random() * 2.5
	ember.phase = math.random() * math.pi * 2
	ember.duration = 2.2 + math.random() * 2.0
	ember.age = stagger and (math.random() * ember.duration) or 0
	ember.size = 10 + math.random() * 14
	ember.alpha = 0.45 + math.random() * 0.40
	local uv = UV_EMBERS[math.random(#UV_EMBERS)]
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
	overlay:Hide()

	glowTexture = overlay:CreateTexture(nil, "ARTWORK")
	glowTexture:SetTexture(TEXTURE)
	glowTexture:SetTexCoord(UV_GLOW[1], UV_GLOW[2], UV_GLOW[3], UV_GLOW[4])
	glowTexture:SetBlendMode("ADD")
	glowTexture:SetVertexColor(1.0, 0.48, 0.14, 1.0)
	glowTexture:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
	glowTexture:Hide()

	emberPool = {}
	for i = 1, EMBER_COUNT do
		local tex = overlay:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(TEXTURE)
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(1.0, 0.62, 0.20, 1.0)
		tex:Hide()
		local ember = { texture = tex }
		ResetEmber(ember, true)
		emberPool[i] = ember
	end

	mistPool = {}
	for i = 1, MIST_COUNT do
		local tex = overlay:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(TEXTURE)
		tex:SetTexCoord(UV_MIST[1], UV_MIST[2], UV_MIST[3], UV_MIST[4])
		tex:SetBlendMode("BLEND")
		tex:SetVertexColor(0.84, 0.94, 1.0, 1.0)
		tex:Hide()
		mistPool[i] = { texture = tex }
	end

	dropPool = {}
	for i = 1, DROP_COUNT do
		local tex = overlay:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(TEXTURE)
		tex:SetBlendMode("BLEND")
		tex:SetVertexColor(0.88, 0.96, 1.0, 1.0)
		tex:Hide()
		dropPool[i] = { texture = tex }
	end

	return overlay
end

local function HideWaterTextures()
	if dropPool then
		for _, drop in ipairs(dropPool) do
			drop.texture:Hide()
		end
	end
	if mistPool then
		for _, mist in ipairs(mistPool) do
			mist.texture:Hide()
		end
	end
end

local function StopOverlay()
	dropsActive = false
	dropsElapsed = 0
	campfireDesired = false
	campfireAlpha = 0
	campfirePreviewUntil = 0
	if overlay then
		overlay:SetScript("OnUpdate", nil)
		if glowTexture then
			glowTexture:Hide()
		end
		HideWaterTextures()
		if emberPool then
			for _, ember in ipairs(emberPool) do
				ember.texture:Hide()
			end
		end
		overlay:Hide()
	end
end

local function AnimateOverlay(_, elapsed)
	local delta = math.min(ns.Number(elapsed, 0), 0.1)
	local w, h = RootSize()
	local uiScale = math.min(w / 1280, h / 720)
	local intensity = IntensityScale()
	local stillRunning = false

	-- 1. Water droplets & subtle damp edge mist
	if dropsActive then
		dropsElapsed = dropsElapsed + delta
		local combatFactor = dropsCombat and 0.35 or 1.0
		local anyDrop = false

		for _, drop in ipairs(dropPool) do
			local t = dropsElapsed - drop.delay
			if t >= 0 and t < drop.duration then
				anyDrop = true
				local p = t / drop.duration
				local fadeIn = Clamp(p / 0.12, 0, 1)
				local fadeOut = p > 0.65 and Clamp((1 - p) / 0.35, 0, 1) or 1
				local runT = math.max(0, t - drop.cling)
				local runNorm = runT / math.max(0.2, drop.duration - drop.cling)
				local fall = drop.travel * (runNorm * runNorm * 0.72 + runNorm * 0.28)
				local sway = math.sin(runNorm * drop.wobbleFreq * math.pi + drop.phase) * drop.wobbleAmp
				local x = Clamp(drop.x + sway, 0.01, 0.99)
				local y = Clamp(drop.y - fall, 0.02, 0.98)
				local stretch = 1.0 + 0.32 * runNorm
				local baseSize = drop.size * uiScale

				drop.texture:SetSize(baseSize * (1.0 - 0.08 * runNorm), baseSize * stretch)
				drop.texture:ClearAllPoints()
				drop.texture:SetPoint("CENTER", overlay, "BOTTOMLEFT", x * w, y * h)
				drop.texture:SetAlpha(drop.alpha * fadeIn * fadeOut * intensity * combatFactor)
				drop.texture:Show()
			elseif t < 0 then
				anyDrop = true
				drop.texture:Hide()
			else
				drop.texture:Hide()
			end
		end

		for _, mist in ipairs(mistPool) do
			local p = dropsElapsed / 1.45
			if p < 1 then
				anyDrop = true
				local env = math.sin(p * math.pi)
				mist.texture:SetSize(mist.size * uiScale, mist.size * uiScale * 0.72)
				mist.texture:ClearAllPoints()
				mist.texture:SetPoint("CENTER", overlay, "BOTTOMLEFT", mist.x * w, mist.y * h)
				mist.texture:SetAlpha(mist.alpha * env * intensity * combatFactor)
				mist.texture:Show()
			else
				mist.texture:Hide()
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
		campfireAlpha = math.min(target, campfireAlpha + delta / 0.75)
	elseif target < campfireAlpha then
		campfireAlpha = math.max(target, campfireAlpha - delta / 0.40)
	end

	if campfireAlpha > 0.002 then
		stillRunning = true
		campfireClock = campfireClock + delta
		local breath = 0.5
			+ 0.32 * math.sin(campfireClock * 0.4 * math.pi * 2)
			+ 0.18 * math.sin(campfireClock * 1.1 * math.pi * 2 + 1.3)
		local glowAlpha = (0.16 + 0.10 * breath) * campfireAlpha * intensity
		glowTexture:SetSize(w * 0.92, h * 0.165)
		glowTexture:SetAlpha(glowAlpha)
		glowTexture:Show()

		for _, ember in ipairs(emberPool) do
			ember.age = ember.age + delta
			if ember.age >= ember.duration then
				if campfireDesired then
					ResetEmber(ember, false)
				else
					ember.texture:Hide()
				end
			end
			if ember.age < ember.duration then
				local p = ember.age / ember.duration
				local fadeIn = Clamp(p / 0.18, 0, 1)
				local fadeOut = Clamp((1 - p) / 0.36, 0, 1)
				local flicker = 0.78 + 0.22 * math.sin(campfireClock * 7.5 + ember.phase)
				local x = ember.x + ember.drift * p + math.sin(p * ember.swayFreq * math.pi + ember.phase) * ember.swayAmp
				local y = ember.y + ember.rise * (p * (1.15 - 0.15 * p))
				local size = ember.size * uiScale * (1.0 - 0.35 * p)

				ember.texture:SetSize(size, size)
				ember.texture:ClearAllPoints()
				ember.texture:SetPoint("CENTER", overlay, "BOTTOMLEFT", Clamp(x, 0.02, 0.98) * w, Clamp(y, 0.01, 0.32) * h)
				ember.texture:SetAlpha(ember.alpha * fadeIn * fadeOut * flicker * campfireAlpha * intensity)
				ember.texture:Show()
			end
		end
	else
		campfireAlpha = 0
		if glowTexture then
			glowTexture:Hide()
		end
		if emberPool then
			for _, ember in ipairs(emberPool) do
				ember.texture:Hide()
			end
		end
	end

	if not stillRunning then
		overlay:SetScript("OnUpdate", nil)
		overlay:Hide()
	end
end

local function EnsureAnimationRunning()
	local frame = EnsureOverlay()
	frame:Show()
	if not frame:GetScript("OnUpdate") then
		ns.SetUpdate(frame, "WorldReactions: animate", AnimateOverlay)
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

	local edgeBand = dropsCombat and 0.06 or 0.105
	local topBand = dropsCombat and 0.07 or 0.14

	for i, drop in ipairs(dropPool) do
		local zone = i % 3
		if zone == 0 then
			-- Left outer edge
			drop.x = 0.018 + math.random() * edgeBand
			drop.y = 0.34 + math.random() * 0.60
		elseif zone == 1 then
			-- Right outer edge
			drop.x = 1.0 - (0.018 + math.random() * edgeBand)
			drop.y = 0.34 + math.random() * 0.60
		else
			-- Upper edge (leaving central vision clear)
			local side = (i % 2 == 0) and 0.12 or 0.56
			drop.x = side + math.random() * 0.32
			drop.y = 1.0 - (0.02 + math.random() * topBand)
		end
		drop.delay = math.random() * 0.24
		drop.cling = 0.14 + math.random() * 0.22
		drop.duration = 1.65 + math.random() * 0.70
		drop.travel = 0.14 + math.random() * 0.16
		drop.wobbleAmp = 0.003 + math.random() * 0.005
		drop.wobbleFreq = 1.5 + math.random() * 2.0
		drop.phase = math.random() * math.pi * 2
		drop.size = 16 + math.random() * 22
		drop.alpha = 0.55 + math.random() * 0.30
		local uv = UV_DROPS[((i - 1) % #UV_DROPS) + 1]
		drop.texture:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
		drop.texture:Hide()
	end

	for i, mist in ipairs(mistPool) do
		local a = MIST_ANCHORS[i]
		mist.x = a[1]
		mist.y = a[2]
		mist.size = a[3]
		mist.alpha = 0.26
		mist.texture:Hide()
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

function WorldReactions.PlayWeaponSound(action, mode, allowFallback)
	local kind = WorldReactions.WeaponSoundKind(mode or "melee")
	if not kind then
		if not allowFallback then
			return false
		end
		kind = "metal"
	end
	local pair = SHEATH_SOUNDS[kind] or SHEATH_SOUNDS.metal
	local fileID = action == "sheath" and pair.sheath or pair.unsheath
	return PlaySingleSound(fileID, "PUT_DOWN_SMALL_CHAIN")
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

local function OnWatch(_, elapsed)
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

	watchElapsed = watchElapsed + ns.Number(elapsed, 0)
	if watchElapsed < POLL_INTERVAL then
		return
	end
	watchElapsed = 0

	if db.waterDrops then
		local submerged = IsSubmerged and IsSubmerged() or false
		local swimming = IsSwimming and IsSwimming() or false
		if WorldReactions.StepWater(waterState, submerged, swimming, now, WaterBlocked()) then
			WorldReactions.TriggerWater(false)
		end
	end

	if db.weaponSheathSound and GetSheathState then
		local action, mode = WorldReactions.StepSheath(sheathState, GetSheathState(), now, SheathBlocked())
		if action then
			WorldReactions.PlayWeaponSound(action, mode, false)
		end
	end

	if db.campfireGlow then
		RefreshCampfireState(now)
	end
end

local function ResetGrace()
	local now = ns.Number(GetTime(), 0)
	waterState.graceUntil = now + LOGIN_GRACE
	waterState.submergedSince = nil
	waterState.swimmingSince = nil
	sheathState.graceUntil = now + LOGIN_GRACE
	sheathState.confirmed = GetSheathState and ns.Number(GetSheathState()) or nil
	sheathState.pending = nil
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
		watcherActive = watcher and watcher:GetScript("OnUpdate") ~= nil or false,
		overlayShown = overlay and overlay:IsShown() or false,
	}
end

function WorldReactions:Apply()
	local db = self.db
	local on = db.enabled and true or false
	local needCampfire = on and db.campfireGlow
	local needArmor = on and db.armorRattle
	local needWatch = on and (db.waterDrops or db.weaponSheathSound or db.campfireGlow or db.armorRattle)

	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, OnEnteringWorld)
	self:ToggleEvent("PLAYER_REGEN_DISABLED", on, OnCombatStart)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", on, OnCombatEnd)
	self:ToggleEvent("UNIT_AURA", needCampfire, OnUnitAura)
	self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", needCampfire, OnSpellcastSucceeded)
	self:ToggleEvent("UPDATE_INVENTORY_DURABILITY", needArmor, OnDurabilityChanged)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", needArmor, OnDurabilityChanged)

	watcher = watcher or CreateFrame("Frame")
	watchElapsed = 0
	if needWatch then
		ns.SetUpdate(watcher, "WorldReactions: watch", OnWatch)
	else
		watcher:SetScript("OnUpdate", nil)
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
	{ key = "weaponSheathSound", type = "toggle", name = L.WORLD_REACTIONS_WEAPON, desc = L.WORLD_REACTIONS_WEAPON_DESC,
		parent = "enabled", new = true },
	{ type = "button", name = L.WORLD_REACTIONS_WEAPON_TEST, text = L.WORLD_REACTIONS_TEST_BUTTON,
		desc = L.WORLD_REACTIONS_WEAPON_TEST_DESC, func = function()
			WorldReactions.PlayWeaponSound("unsheath", "melee", true)
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

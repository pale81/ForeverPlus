-- Local comic bursts for skill ranks, experience, critical hits, looted coins and large expenses.
local _, ns = ...
local L = ns.L

local SoloParty = ns:NewModule("SoloParty", {
	title = L.SOLO_PARTY_TITLE,
	order = 5.37,
	defaults = { enabled = false, sounds = true, effects = true, criticals = true },
})

local MEDIA = "Interface\\AddOns\\ForeverPlus\\Media\\"
local BURSTS = { MEDIA .. "SoloPartyBurst", MEDIA .. "SoloPartyCloud", MEDIA .. "SoloPartyBalloon" }
local SOUNDS = {
	reward = { "UI_MISSION_SUCCESS_CHEERS", "UI_RAID_BOSS_DEFEATED", "UI_SCENARIO_STAGE_END" },
	spent = { "UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_FAIL", "UI_ADVENTURES_ADVENTURE_FAILURE_COMPLETE",
		"UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER" },
	crit = { 1240622, 1324858, 1240623, 1324859, 1240624, 1324860 }, -- Two-handed sword / axe critical flesh impacts.
}
local INSCRIPTION = MEDIA .. "Fonts\\CinzelDecorative-Bold.ttf"
local SMALL_CAPS = MEDIA .. "Fonts\\AlegreyaSC-ExtraBold.ttf"
local STYLES = {
	skill = { font = INSCRIPTION, size = 39 },
	loot = { font = INSCRIPTION, size = 49 },
	spent = { font = SMALL_CAPS, size = 40 },
	xp = { font = INSCRIPTION, size = 44 },
	crit = { font = INSCRIPTION, size = 54 },
}

local STAR = [[Interface\Cooldown\star4]]
local WATER = MEDIA .. "SoloPartyWater"
local MOTIF_ART = MEDIA .. "SoloPartyMotifs"
local SOFT_MASK = MEDIA .. "SoloPartyEffectMask"
local SMOKE = { atlas = "BonusChest-OrangeSmoke-Wide", file = STAR }
local MIST = { atlas = "UF-DruidCP-Smoke", file = STAR }
local ARCANE = { atlas = "Cast_Channel_Sparkles_01", file = STAR }
local COIN = { file = [[Interface\MoneyFrame\UI-GoldIcon]], blend = "BLEND" }
local MOTES = { file = STAR }
local RIPPLE = { file = WATER, coords = { 0, 0.5, 0, 1 } }
local BUBBLE = { file = WATER, coords = { 0.5, 1, 0, 1 }, blend = "BLEND" }
local LEAF = { file = MOTIF_ART, coords = { 0, 0.5, 0, 0.5 }, blend = "BLEND" }
local FIBERS = { file = MOTIF_ART, coords = { 0.5, 1, 0, 0.5 } }
local STEAM = { file = MOTIF_ART, coords = { 0, 0.5, 0.5, 1 } }
local HEAL = { file = MOTIF_ART, coords = { 0.5, 1, 0.5, 1 } }
local THEMES = {
	skill = { paper = { 0.90, 0.87, 0.80 }, text = { 1, 0.94, 0.78 }, light = { 0.90, 0.78, 0.53 },
		particle = MOTES, lift = 0.33 },
	fishing = { paper = { 0.78, 0.91, 0.96 }, text = { 0.85, 0.98, 1 }, light = { 0.55, 0.83, 0.94 },
		font = SMALL_CAPS, aura = RIPPLE, particle = BUBBLE, lift = 0.65 },
	forge = { paper = { 0.95, 0.78, 0.61 }, text = { 1, 0.85, 0.64 }, light = { 1, 0.49, 0.20 },
		aura = SMOKE, particle = MOTES, lift = 0.62 },
	nature = { paper = { 0.87, 0.90, 0.70 }, text = { 0.91, 0.98, 0.75 }, light = { 0.60, 0.78, 0.34 },
		aura = MIST, particle = LEAF, accent = MOTES, lift = 0.26 },
	alchemy = { paper = { 0.88, 0.91, 0.74 }, text = { 0.94, 1, 0.78 }, light = { 0.65, 0.87, 0.49 },
		aura = MIST, particle = BUBBLE, lift = 0.55 },
	fibers = { paper = { 0.80, 0.90, 0.87 }, text = { 0.84, 0.96, 0.91 }, light = { 0.52, 0.86, 0.80 },
		particle = FIBERS, accent = MOTES, lift = 0.18 },
	cooking = { paper = { 0.95, 0.83, 0.69 }, text = { 1, 0.89, 0.72 }, light = { 0.87, 0.84, 0.78 },
		particle = STEAM, lift = 0.65 },
	firstAid = { paper = { 0.83, 0.91, 0.73 }, text = { 0.89, 1, 0.79 }, light = { 0.59, 0.89, 0.43 },
		particle = HEAL, accent = MOTES, lift = 0.35 },
	arcane = { paper = { 0.89, 0.82, 0.95 }, text = { 0.95, 0.88, 1 }, light = { 0.63, 0.49, 0.92 },
		aura = ARCANE, particle = MOTES, lift = 0.44 },
	loot = { paper = { 1, 0.93, 0.77 }, text = { 1, 0.89, 0.57 }, light = { 1, 0.79, 0.34 },
		particle = COIN, accent = MOTES, lift = 0.40 },
	xp = { paper = { 0.80, 0.85, 0.97 }, text = { 0.86, 0.93, 1 }, light = { 0.45, 0.62, 1 },
		aura = ARCANE, particle = MOTES, accent = MOTES, lift = 0.48 },
	crit = { paper = { 1, 0.83, 0.60 }, text = { 1, 0.87, 0.48 }, light = { 1, 0.52, 0.15 },
		particle = MOTES, lift = 0.66 },
	spent = { paper = { 0.89, 0.72, 0.62 }, text = { 1, 0.82, 0.68 }, light = { 0.80, 0.38, 0.23 },
		aura = SMOKE, particle = MOTES, lift = 0.12 },
}
local SKILL_EFFECTS = {
	[129] = "firstAid",
	[164] = "forge", [186] = "forge", [202] = "forge", -- Blacksmithing, Mining, Engineering
	[165] = "fibers", [197] = "fibers", [393] = "fibers", -- Leatherworking, Tailoring, Skinning
	[171] = "alchemy", [182] = "nature", [185] = "cooking",
	[333] = "arcane", [755] = "arcane", [773] = "arcane", -- Enchanting, Jewelcrafting, Inscription
	[356] = "fishing",
}
local skillEffectsByName = { [L.SOLO_PARTY_PREVIEW_SKILL] = SKILL_EFFECTS[356] }
local POSITIONS = { { 0.21, 0.66 }, { 0.79, 0.37 }, { 0.50, 0.67 }, { 0.21, 0.37 }, { 0.79, 0.66 }, { 0.50, 0.38 } }
local POP, HOLD, END = 0.22, 1.35, 1.78
-- Start on either side at different heights, then drift away from the lettering.
-- Each path gives x, y, outward drift, delay in seconds and size relative to the card.
local PARTICLE_PATHS = {
	{ -0.33, -0.24, -0.12, 0.00, 0.18 },
	{  0.25,  0.14,  0.09, 0.09, 0.15 },
	{  0.34, -0.30,  0.13, 0.18, 0.18 },
	{ -0.28,  0.20, -0.11, 0.28, 0.12 },
	{ -0.36, -0.04, -0.12, 0.38, 0.13 },
	{  0.30, -0.10,  0.12, 0.49, 0.11 },
}
local root, cards, nextSlot = nil, {}, 0
local lastBurst, lastSound = nil, {}
local balance, lootTimer, previewTimer
local lastXP
local lootAmounts, lootTotal = {}, 0

-- Start at a random variant and use each one before repeating it.
local function NextVariant(previous, count)
	return previous and previous % count + 1 or math.random(count)
end

local function PlayBurstSound(kind)
	if not SoloParty.db.sounds then
		return
	end
	local group = (kind == "crit" or kind == "spent") and kind or "reward"
	local pool = SOUNDS[group]
	local index = NextVariant(lastSound[group], #pool)
	lastSound[group] = index
	if group == "crit" then
		PlaySoundFile(pool[index], "SFX")
		return
	end
	local kit = SOUNDKIT[pool[index]]
	if kit then
		PlaySound(kit, "SFX")
	end
end

local function SetEffectArt(texture, art)
	if art.atlas and C_Texture.GetAtlasInfo(art.atlas) then
		texture:SetAtlas(art.atlas)
	else
		texture:SetTexture(art.file)
		if art.coords then
			texture:SetTexCoord(unpack(art.coords))
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
	texture:SetBlendMode(art.blend or "ADD")
end

local function AnimateEffects(card, age)
	local theme = card.effects
	if not theme then
		return
	end
	local progress = age / END
	local pulse = math.sin(math.pi * progress)
	if theme.aura then
		card.aura:SetSize(card.height * (0.55 + 0.61 * progress), card.height * (0.38 + 0.28 * progress))
		card.aura:SetAlpha(0.42 * pulse)
	end
	for i, path in ipairs(PARTICLE_PATHS) do
		local phase = math.max(0, (age - path[4]) / (END - path[4]))
		local arc = math.sin(math.pi * phase)
		local x = path[1] + path[3] * (phase + 0.30 * math.sin(phase * 2 * math.pi))
		local y = path[2] + phase * theme.lift + path[3] * arc
		local particle = card.particles[i]
		particle:SetPoint("CENTER", card.art, "CENTER", x * card.width, y * card.height)
		particle:SetAlpha(pulse * arc * 0.9)
	end
end

local function SetEffects(card, theme)
	card.effects = theme
	card.aura:SetShown(theme ~= nil and theme.aura ~= nil)
	for _, particle in ipairs(card.particles) do
		particle:SetShown(theme ~= nil)
	end
	if not theme then
		return
	end
	if theme.aura then
		SetEffectArt(card.aura, theme.aura)
		card.aura:SetVertexColor(unpack(theme.light))
	end
	for i, particle in ipairs(card.particles) do
		SetEffectArt(particle, i % 3 == 0 and theme.accent or theme.particle)
		particle:SetVertexColor(unpack(theme.light))
		local size = PARTICLE_PATHS[i][5] * card.height
		particle:SetSize(size, size)
	end
	AnimateEffects(card, 0)
end

local function Update(_, delta)
	local visible = false
	for _, card in pairs(cards) do
		if card.art:IsShown() then
			card.age = card.age + delta
			local t = card.age
			if t >= END then
				card.art:Hide()
			else
				visible = true
				if t < POP then
					local progress = t / POP - 1
					local pop = 1 + progress * progress * (2.9 * progress + 1.9)
					card.art:SetScale(card.fit * (0.34 + 0.66 * pop))
					card.art:SetAlpha(math.min(1, t * 26))
				else
					local fade = math.max(0, (t - HOLD) / (END - HOLD))
					card.art:SetScale(card.fit * (1 - 0.13 * fade))
					card.art:SetAlpha(1 - fade)
				end
				AnimateEffects(card, t)
			end
		end
	end
	if not visible then
		root:Hide()
	end
end

local function CreateCard()
	local anchor = CreateFrame("Frame", nil, root)
	anchor:SetSize(1, 1)
	local art = CreateFrame("Frame", nil, anchor)
	art:SetPoint("CENTER")
	art:EnableMouse(false)
	local burst = art:CreateTexture(nil, "BACKGROUND")
	burst:SetAllPoints()
	local aura = art:CreateTexture(nil, "ARTWORK")
	aura:SetPoint("CENTER", art, "CENTER", 0, -8)
	local auraMask = art:CreateMaskTexture()
	auraMask:SetTexture(SOFT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	auraMask:SetAllPoints(aura)
	aura:AddMaskTexture(auraMask)
	local particles = {}
	for i = 1, #PARTICLE_PATHS do
		particles[i] = art:CreateTexture(nil, "ARTWORK", nil, 1)
	end
	local label = art:CreateFontString(nil, "OVERLAY")
	local value = art:CreateFontString(nil, "OVERLAY")
	label:SetShadowOffset(1, -1)
	label:SetShadowColor(0.05, 0.03, 0.02, 0.85)
	value:SetShadowOffset(2, -2)
	return { anchor = anchor, art = art, burst = burst, aura = aura, particles = particles,
		label = label, value = value }
end

local function ShowBurst(kind, label, value, themeName)
	if not root then
		root = CreateFrame("Frame", nil, UIParent)
		root:SetAllPoints()
		root:SetFrameStrata("TOOLTIP")
		root:EnableMouse(false)
		ns.SetUpdate(root, "SoloParty: comic bursts", Update)
		nextSlot = math.random(#POSITIONS) - 1
	end
	nextSlot = nextSlot % #POSITIONS + 1
	local card = cards[nextSlot] or CreateCard()
	cards[nextSlot] = card
	local style = STYLES[kind]
	local theme = THEMES[themeName or kind]
	local size = style.size + math.random(-4, 4)
	lastBurst = NextVariant(lastBurst, #BURSTS)
	card.burst:SetTexture(BURSTS[lastBurst])
	if card.label:SetFont(SMALL_CAPS, 20, "") == false then
		card.label:SetFont(GameFontNormal:GetFont(), 20, "")
	end
	if card.value:SetFont(theme.font or style.font, size, "") == false then
		card.value:SetFont(GameFontNormal:GetFont(), size, "")
	end
	card.label:SetText(label)
	card.value:SetText(value)
	card.label:SetTextColor(0.94, 0.87, 0.72)
	card.value:SetTextColor(unpack(theme.text))
	card.value:SetShadowColor(0.05, 0.03, 0.02, 0.90)
	card.label:SetPoint("CENTER", card.art, "CENTER", 0, size * 0.43)
	card.value:SetPoint("CENTER", card.art, "CENTER", 0, -size * 0.24)
	card.burst:SetVertexColor(unpack(theme.paper))
	-- Critical damage may be secret. Its text and text width must stay out of layout calculations.
	local textWidth = kind == "crit" and 220 or math.max(card.label:GetStringWidth(), card.value:GetStringWidth())
	local width, height = math.max(225, textWidth * 1.50 + 30), 55 + size * 1.45
	card.width, card.height = width, height
	card.art:SetSize(width, height)
	SetEffects(card, SoloParty.db.effects and theme or nil)
	local w, h = root:GetSize()
	card.fit = math.min(1, w * 0.24 / width, h * 0.21 / height)
	local point = POSITIONS[nextSlot]
	local x, y = point[1] + math.random(-15, 15) / 1000, point[2] + math.random(-25, 25) / 1000
	card.anchor:SetPoint("CENTER", root, "BOTTOMLEFT", x * w, y * h)
	card.age = 0
	card.art:SetScale(card.fit * 0.34)
	card.art:SetAlpha(0)
	card.art:Show()
	root:Show()
	PlayBurstSound(kind)
end

local function ShowMoney(kind, amount)
	local label = kind == "loot" and L.SOLO_PARTY_LOOT or L.SOLO_PARTY_SPENT
	local sign = kind == "loot" and "+" or "−"
	ShowBurst(kind, label, sign .. GetMoneyString(amount, true))
end

local function ResetBaselines()
	balance = SoloParty.db.enabled and ns.Number(GetMoney()) or nil
	lastXP = SoloParty.db.enabled and { ns.Number(UnitXP("player")), ns.Number(UnitXPMax("player")) } or nil
	if lootTimer then
		lootTimer:Cancel()
		lootTimer = nil
	end
	wipe(lootAmounts)
	lootTotal = 0
end

function SoloParty:PLAYER_MONEY()
	local previous = balance
	balance = ns.Number(GetMoney())
	if previous and balance and balance < previous and (previous - balance) * 10 >= previous then
		ShowMoney("spent", previous - balance)
	end
end

local function FlushLoot()
	lootTimer = nil
	local current = ns.Number(GetMoney())
	if current then
		local previous = math.max(0, current - lootTotal)
		for _, amount in ipairs(lootAmounts) do
			if amount * 10 >= previous then
				ShowMoney("loot", amount)
			end
			previous = previous + amount
		end
	end
	wipe(lootAmounts)
	lootTotal = 0
end

function SoloParty:CHAT_MSG_MONEY(_, message)
	local amount = ns.ParseLootMoney(message)
	if amount then
		lootAmounts[#lootAmounts + 1] = amount
		lootTotal = lootTotal + amount
		-- Give both the chat messages and the associated balance updates time to arrive.
		lootTimer = lootTimer or ns.NewTimer("SoloParty: settle loot", 0.1, FlushLoot)
	end
end

-- Experience by the change of the experience points, whatever the source (kills, quests, discoveries).
-- Like money, it must reach 10% of what the level needed before the change.
function SoloParty:PLAYER_XP_UPDATE()
	local previous = lastXP
	local current, maximum = ns.Number(UnitXP("player")), ns.Number(UnitXPMax("player"))
	lastXP = { current, maximum }
	if previous and previous[1] and previous[2] and current then
		local gained = current - previous[1]
		if gained < 0 then
			gained = previous[2] - previous[1] + current -- a level up
		end
		if gained > 0 and gained * 10 >= previous[2] then
			ShowBurst("xp", L.SOLO_PARTY_XP, L.SOLO_PARTY_XP_VALUE:format(gained))
		end
	end
end

function SoloParty:CHAT_MSG_SKILL(_, message)
	local name, rank = ns.ParseSkillRankMessage(message)
	if name then
		ShowBurst("skill", name, L.SOLO_PARTY_RANK:format(rank), skillEffectsByName[name])
	end
end

function SoloParty:UNIT_COMBAT(_, unit, event, flagText, amount)
	if ns.Secret(unit) or ns.Secret(event) or ns.Secret(flagText)
		or unit ~= "target" or event ~= "WOUND" or flagText ~= "CRITICAL" then
		return
	end
	if type(amount) ~= "number" or (not ns.Secret(amount) and amount <= 0) then
		return
	end
	local hostile = UnitCanAttack("player", "target")
	if ns.Secret(hostile) or not hostile
		or not ns:GetModule("CombatText").TargetInvolved() then
		return
	end
	local ok, text = pcall(string.format, "%d", amount)
	if ok then
		ShowBurst("crit", L.SOLO_PARTY_CRIT, text)
	end
end

function SoloParty:OnOptionChanged(key)
	if key == "sounds" then
		return
	end
	if key == "criticals" then
		self:ToggleEvent("UNIT_COMBAT", self.db.enabled and self.db.criticals, self.UNIT_COMBAT)
		return
	end
	if key == "effects" then
		if not self.db.effects then
			for _, card in pairs(cards) do
				SetEffects(card)
			end
		end
		return
	end
	local enabled = self.db.enabled
	ResetBaselines()
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, ResetBaselines)
	self:ToggleEvent("PLAYER_MONEY", enabled, self.PLAYER_MONEY)
	self:ToggleEvent("PLAYER_XP_UPDATE", enabled, self.PLAYER_XP_UPDATE)
	self:ToggleEvent("CHAT_MSG_MONEY", enabled, self.CHAT_MSG_MONEY)
	self:ToggleEvent("CHAT_MSG_SKILL", enabled, self.CHAT_MSG_SKILL)
	self:ToggleEvent("UNIT_COMBAT", enabled and self.db.criticals, self.UNIT_COMBAT)
	if not enabled then
		if previewTimer then
			previewTimer:Cancel()
			previewTimer = nil
		end
		if root then
			for _, card in pairs(cards) do
				card.art:Hide()
			end
			root:Hide()
		end
	end
end

function SoloParty:OnLogin()
	if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		for skillLine, effect in pairs(SKILL_EFFECTS) do
			local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
			local name = info and info.professionName
			if type(name) == "string" and not ns.Secret(name) and name ~= "" then
				skillEffectsByName[name] = effect
			end
		end
	end
	self:OnOptionChanged()
end

local PREVIEW_STEPS = {
	function() ShowBurst("skill", L.SOLO_PARTY_PREVIEW_SKILL, L.SOLO_PARTY_RANK:format(75), SKILL_EFFECTS[356]) end,
	function() ShowMoney("loot", 12500) end,
	function() ShowMoney("spent", 3500) end,
	function() ShowBurst("xp", L.SOLO_PARTY_XP, L.SOLO_PARTY_XP_VALUE:format(450)) end,
	function() ShowBurst("crit", L.SOLO_PARTY_CRIT, "1234") end,
}

local function Preview()
	if previewTimer then
		previewTimer:Cancel()
	end
	local step = 1
	local function Advance()
		PREVIEW_STEPS[step]()
		step = step + 1
		previewTimer = PREVIEW_STEPS[step] and ns.NewTimer("SoloParty: next preview", 2.4, Advance) or nil
	end
	Advance()
end

SoloParty.options = {
	{ key = "enabled", type = "toggle", name = L.SOLO_PARTY_ENABLED, desc = L.SOLO_PARTY_DESC, new = true },
	{ key = "sounds", type = "toggle", name = L.SOLO_PARTY_SOUNDS, desc = L.SOLO_PARTY_SOUNDS_DESC, new = true },
	{ key = "effects", type = "toggle", name = L.SOLO_PARTY_EFFECTS, desc = L.SOLO_PARTY_EFFECTS_DESC, new = true },
	{ key = "criticals", type = "toggle", name = L.SOLO_PARTY_CRITICALS, desc = L.SOLO_PARTY_CRITICALS_DESC, parent = "enabled", new = true },
	{ type = "button", name = L.SOLO_PARTY_PREVIEW, text = L.SOLO_PARTY_PREVIEW_BUTTON, func = Preview },
}

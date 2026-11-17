-- Local comic bursts for skill ranks, looted coins and large expenses.
local _, ns = ...
local L = ns.L

local SoloParty = ns:NewModule("SoloParty", {
	title = L.SOLO_PARTY_TITLE,
	order = 5.37,
	defaults = { enabled = false, sounds = true, effects = true },
})

local MEDIA = "Interface\\AddOns\\ForeverPlus\\Media\\"
local BURSTS = { MEDIA .. "SoloPartyBurst", MEDIA .. "SoloPartyCloud", MEDIA .. "SoloPartyBalloon" }
local SOUNDS = {
	reward = { "UI_MISSION_SUCCESS_CHEERS", "UI_RAID_BOSS_DEFEATED", "UI_SCENARIO_STAGE_END" },
	spent = { "UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_FAIL", "UI_ADVENTURES_ADVENTURE_FAILURE_COMPLETE",
		"UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER" },
}
local INSCRIPTION = MEDIA .. "Fonts\\CinzelDecorative-Bold.ttf"
local SMALL_CAPS = MEDIA .. "Fonts\\AlegreyaSC-ExtraBold.ttf"
local STYLES = {
	skill = { font = INSCRIPTION, size = 39 },
	loot = { font = INSCRIPTION, size = 49 },
	spent = { font = SMALL_CAPS, size = 40 },
}

local STAR = [[Interface\Cooldown\star4]]
local WATER = MEDIA .. "SoloPartyWater"
local GLOW = { atlas = "ui-castingbar-full-glow-standard", file = STAR }
local SMOKE = { atlas = "BonusChest-OrangeSmoke-Wide", file = STAR }
local MIST = { atlas = "UF-DruidCP-Smoke", file = STAR }
local ARCANE = { atlas = "Cast_Channel_Sparkles_01", file = STAR }
local COIN = { file = [[Interface\MoneyFrame\UI-GoldIcon]], blend = "BLEND" }
local MOTES = { file = STAR }
local RIPPLE = { file = WATER, coords = { 0, 0.5, 0, 1 } }
local BUBBLE = { file = WATER, coords = { 0.5, 1, 0, 1 }, blend = "BLEND" }
local THEMES = {
	skill = { paper = { 0.90, 0.87, 0.80 }, text = { 1, 0.94, 0.78 }, light = { 0.90, 0.78, 0.53 },
		aura = GLOW, particle = MOTES, lift = 0.33 },
	fishing = { paper = { 0.78, 0.91, 0.96 }, text = { 0.85, 0.98, 1 }, light = { 0.55, 0.83, 0.94 },
		font = SMALL_CAPS, aura = RIPPLE, particle = BUBBLE, lift = 0.65 },
	forge = { paper = { 0.95, 0.78, 0.61 }, text = { 1, 0.85, 0.64 }, light = { 1, 0.49, 0.20 },
		aura = SMOKE, particle = MOTES, lift = 0.62 },
	nature = { paper = { 0.87, 0.90, 0.70 }, text = { 0.91, 0.98, 0.75 }, light = { 0.60, 0.78, 0.34 },
		aura = MIST, particle = MOTES, lift = 0.53 },
	arcane = { paper = { 0.89, 0.82, 0.95 }, text = { 0.95, 0.88, 1 }, light = { 0.63, 0.49, 0.92 },
		aura = ARCANE, particle = MOTES, lift = 0.44 },
	loot = { paper = { 1, 0.93, 0.77 }, text = { 1, 0.89, 0.57 }, light = { 1, 0.79, 0.34 },
		aura = GLOW, particle = COIN, lift = 0.40 },
	spent = { paper = { 0.89, 0.72, 0.62 }, text = { 1, 0.82, 0.68 }, light = { 0.80, 0.38, 0.23 },
		aura = SMOKE, particle = MOTES, lift = 0.12 },
}
local SKILL_EFFECTS = {
	[356] = "fishing", -- Fishing
	[164] = "forge", [186] = "forge", [202] = "forge", -- Blacksmithing, Mining, Engineering
	[171] = "nature", [182] = "nature", -- Alchemy, Herbalism
	[333] = "arcane", -- Enchanting
}
local skillThemes = { [L.SOLO_PARTY_PREVIEW_SKILL] = "fishing" }
local POSITIONS = { { 0.21, 0.66 }, { 0.79, 0.37 }, { 0.50, 0.67 }, { 0.21, 0.37 }, { 0.79, 0.66 }, { 0.50, 0.38 } }
local POP, HOLD, END = 0.22, 1.35, 1.78
local root, cards, nextSlot = nil, {}, 0
local lastBurst, lastSound = nil, {}
local balance, lootTimer, previewTimer
local lootAmounts, lootTotal = {}, 0

-- Start at a random variant and use each one before repeating it.
local function NextVariant(previous, count)
	return previous and previous % count + 1 or math.random(count)
end

local function PlayBurstSound(kind)
	if not SoloParty.db.sounds then
		return
	end
	local group = kind == "spent" and "spent" or "reward"
	local pool = SOUNDS[group]
	local index = NextVariant(lastSound[group], #pool)
	lastSound[group] = index
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
	card.aura:SetSize(card.width * (0.49 + 0.46 * progress), card.height * (0.46 + 0.25 * progress))
	card.aura:SetAlpha(0.56 * pulse)
	if card.wisp:IsShown() then
		card.wisp:SetAlpha(0.28 * pulse)
	end
	for i, particle in ipairs(card.particles) do
		local phase = (progress + (i - 1) * 0.19) % 1
		local side = i % 2 == 1 and -1 or 1
		local x = side * card.width * (0.24 + phase * 0.16)
		local y = card.height * (0.06 - i * 0.07 + phase * theme.lift)
		particle:SetPoint("CENTER", card.art, "CENTER", x, y)
		particle:SetAlpha(pulse * math.sin(math.pi * phase) * 0.85)
	end
end

local function SetEffects(card, theme)
	card.effects = theme
	card.aura:SetShown(theme ~= nil)
	card.wisp:Hide()
	for _, particle in ipairs(card.particles) do
		particle:SetShown(theme ~= nil)
	end
	if not theme then
		return
	end
	SetEffectArt(card.aura, theme.aura)
	card.aura:SetVertexColor(unpack(theme.light))
	for i, particle in ipairs(card.particles) do
		SetEffectArt(particle, theme.particle)
		particle:SetVertexColor(unpack(theme.light))
		local size = (9 + i * 3) * card.height / 120
		particle:SetSize(size, size)
	end
	if theme == THEMES.fishing and C_Texture.GetAtlasInfo("Cast_Channel_WispGlow") then
		card.wisp:SetAtlas("Cast_Channel_WispGlow")
		card.wisp:SetSize(card.width * 0.74, card.height * 0.36)
		card.wisp:Show()
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
	local wisp = art:CreateTexture(nil, "ARTWORK", nil, 1)
	wisp:SetBlendMode("ADD")
	wisp:SetPoint("CENTER", art, "CENTER", 0, -8)
	local particles = {}
	for i = 1, 3 do
		particles[i] = art:CreateTexture(nil, "ARTWORK", nil, 2)
	end
	local label = art:CreateFontString(nil, "OVERLAY")
	local value = art:CreateFontString(nil, "OVERLAY")
	label:SetShadowOffset(1, -1)
	label:SetShadowColor(0.05, 0.03, 0.02, 0.85)
	value:SetShadowOffset(2, -2)
	return { anchor = anchor, art = art, burst = burst, aura = aura, wisp = wisp, particles = particles,
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
	if card.label:SetFont(SMALL_CAPS, 20, "OUTLINE") == false then
		card.label:SetFontObject(GameFontNormal)
	end
	if card.value:SetFont(theme.font or style.font, size, "OUTLINE") == false then
		local face = GameFontNormal:GetFont()
		card.value:SetFont(face, size, "OUTLINE")
	end
	card.label:SetText(label)
	card.value:SetText(value)
	card.label:SetTextColor(0.94, 0.87, 0.72)
	card.value:SetTextColor(unpack(theme.text))
	local r, g, b = unpack(theme.light)
	card.value:SetShadowColor(r * 0.27, g * 0.27, b * 0.27, 0.95)
	card.label:SetPoint("CENTER", card.art, "CENTER", 0, size * 0.43)
	card.value:SetPoint("CENTER", card.art, "CENTER", 0, -size * 0.24)
	card.burst:SetVertexColor(unpack(theme.paper))
	local textWidth = math.max(card.label:GetStringWidth(), card.value:GetStringWidth())
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

local function ResetMoney()
	balance = SoloParty.db.enabled and ns.Number(GetMoney()) or nil
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

function SoloParty:CHAT_MSG_SKILL(_, message)
	local name, rank = ns.ParseSkillRankMessage(message)
	if name then
		ShowBurst("skill", name, L.SOLO_PARTY_RANK:format(rank), skillThemes[name])
	end
end

function SoloParty:OnOptionChanged(key)
	if key == "sounds" then
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
	ResetMoney()
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, ResetMoney)
	self:ToggleEvent("PLAYER_MONEY", enabled, self.PLAYER_MONEY)
	self:ToggleEvent("CHAT_MSG_MONEY", enabled, self.CHAT_MSG_MONEY)
	self:ToggleEvent("CHAT_MSG_SKILL", enabled, self.CHAT_MSG_SKILL)
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
		for skillLine, theme in pairs(SKILL_EFFECTS) do
			local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
			local name = info and info.professionName
			if type(name) == "string" and not ns.Secret(name) and name ~= "" then
				skillThemes[name] = theme
			end
		end
	end
	self:OnOptionChanged()
end

local PREVIEW_STEPS = {
	function() ShowBurst("skill", L.SOLO_PARTY_PREVIEW_SKILL, L.SOLO_PARTY_RANK:format(75), "fishing") end,
	function() ShowMoney("loot", 12500) end,
	function() ShowMoney("spent", 3500) end,
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
	{ type = "button", name = L.SOLO_PARTY_PREVIEW, text = L.SOLO_PARTY_PREVIEW_BUTTON, func = Preview },
}

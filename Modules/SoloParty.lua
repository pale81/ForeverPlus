-- Local comic bursts for skill ranks, looted coins and large expenses.
local _, ns = ...
local L = ns.L

local SoloParty = ns:NewModule("SoloParty", {
	title = L.SOLO_PARTY_TITLE,
	order = 5.37,
	defaults = { enabled = false },
})

local BURST = "Interface\\AddOns\\ForeverPlus\\Media\\SoloPartyBurst"
local BANGERS = "Interface\\AddOns\\ForeverPlus\\Media\\Fonts\\Bangers-Regular.ttf"
local BARLOW = "Interface\\AddOns\\ForeverPlus\\Media\\Fonts\\BarlowCondensed-Black.ttf"
local STYLES = {
	skill = { font = BANGERS, size = 39, colors = { { 0.36, 0.90, 1 }, { 1, 0.68, 0.92 }, { 0.72, 0.82, 1 } } },
	loot = { font = BANGERS, size = 49, colors = { { 1, 0.84, 0.28 }, { 0.71, 1, 0.51 } } },
	spent = { font = BARLOW, size = 40, colors = { { 1, 0.46, 0.48 }, { 1, 0.65, 0.38 } } },
}
local POSITIONS = { { 0.21, 0.66 }, { 0.79, 0.37 }, { 0.50, 0.67 }, { 0.21, 0.37 }, { 0.79, 0.66 }, { 0.50, 0.38 } }
local POP, HOLD, END = 0.22, 1.35, 1.78
local root, cards, nextSlot = nil, {}, 0
local balance, lootTimer
local lootAmounts, lootTotal = {}, 0

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
	burst:SetTexture(BURST)
	local label = art:CreateFontString(nil, "OVERLAY")
	local value = art:CreateFontString(nil, "OVERLAY")
	label:SetTextColor(0.11, 0.07, 0.17)
	value:SetTextColor(1, 1, 0.95)
	return { anchor = anchor, art = art, burst = burst, label = label, value = value }
end

local function ShowBurst(kind, label, value)
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
	local size = style.size + math.random(-4, 4)
	if card.label:SetFont(BARLOW, 18, "") == false then
		card.label:SetFontObject(GameFontNormal)
	end
	if card.value:SetFont(style.font, size, "THICKOUTLINE") == false then
		local face = GameFontNormal:GetFont()
		card.value:SetFont(face, size, "THICKOUTLINE")
	end
	card.label:SetText(label)
	card.value:SetText(value)
	card.label:SetPoint("CENTER", card.art, "CENTER", 0, size * 0.43)
	card.value:SetPoint("CENTER", card.art, "CENTER", 0, -size * 0.24)
	card.burst:SetVertexColor(unpack(style.colors[math.random(#style.colors)]))
	local textWidth = math.max(card.label:GetStringWidth(), card.value:GetStringWidth())
	local width, height = math.max(196, textWidth * 1.48 + 30), 64 + size * 1.62
	card.art:SetSize(width, height)
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
		ShowBurst("skill", name, L.SOLO_PARTY_RANK:format(rank))
	end
end

function SoloParty:OnOptionChanged()
	local enabled = self.db.enabled
	ResetMoney()
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, ResetMoney)
	self:ToggleEvent("PLAYER_MONEY", enabled, self.PLAYER_MONEY)
	self:ToggleEvent("CHAT_MSG_MONEY", enabled, self.CHAT_MSG_MONEY)
	self:ToggleEvent("CHAT_MSG_SKILL", enabled, self.CHAT_MSG_SKILL)
	if not enabled and root then
		for _, card in pairs(cards) do
			card.art:Hide()
		end
		root:Hide()
	end
end

SoloParty.OnLogin = SoloParty.OnOptionChanged

SoloParty.options = {
	{ key = "enabled", type = "toggle", name = L.SOLO_PARTY_ENABLED, desc = L.SOLO_PARTY_DESC, new = true },
	{ type = "button", name = L.SOLO_PARTY_PREVIEW, text = L.SOLO_PARTY_PREVIEW_BUTTON, func = function()
		ShowBurst("skill", L.SOLO_PARTY_PREVIEW_SKILL, L.SOLO_PARTY_RANK:format(75))
		ShowMoney("loot", 12500)
		ShowMoney("spent", 3500)
	end },
}

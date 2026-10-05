-- Visuals: quality glow on item buttons (oGlow), iSquidMod end caps,
-- action button state colouring and outlined fonts.
local addonName, ns = ...
local L = ns.L

local Visuals = ns:NewModule("Visuals", {
	title = L.VISUALS_TITLE,
	order = 9,
	defaults = {
		squid = "default",
		actionColors = true,
		colorRange = true,
		colorMana = true,
		colorUnusable = true,
	},
})

---------------------------------------------------------------------------
-- oGlow: thick glow in the quality colour from "uncommon" upwards
---------------------------------------------------------------------------
local glows = setmetatable({}, { __mode = "k" })

-- Two stacked additive layers: a single one lets the item frame shine through.
local GLOW_LAYERS = 2

-- The glow ring of UI-ActionButton-Border covers about 36 of its 64 pixels.
local GLOW_FACTOR = 64 / 36

local function GetGlow(button)
	local glow = glows[button]
	if not glow then
		glow = {}
		for layer = 1, GLOW_LAYERS do
			local texture = button:CreateTexture(nil, "OVERLAY", nil, 7)
			texture:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
			texture:SetBlendMode("ADD")
			texture:SetPoint("CENTER", button, "CENTER")
			glow[layer] = texture
		end
		glows[button] = glow
	end
	return glow
end

local function UpdateGlow(button, quality)
	if not button or (button.IsForbidden and button:IsForbidden()) then
		return
	end
	local glow = glows[button]
	if quality and quality >= Enum.ItemQuality.Uncommon then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		glow = glow or GetGlow(button)
		-- Size from the button itself (character slots, bags and loot differ).
		local width, height = button:GetSize()
		for _, texture in ipairs(glow) do
			texture:SetSize(width * GLOW_FACTOR, height * GLOW_FACTOR)
			texture:SetVertexColor(r, g, b)
			texture:Show()
		end
	elseif glow then
		for _, texture in ipairs(glow) do
			texture:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Player buffs get the action button frame and rounded icon corners
---------------------------------------------------------------------------
-- Like Blizzard's small action buttons: the icon mask is 1.5x the icon size.
local MASK_FACTOR = 1.5
local auraMasks = {}

local function SizeAuraMask(aura)
	local mask = auraMasks[aura]
	local width, height = aura.Icon:GetSize()
	mask:SetSize(width * MASK_FACTOR, height * MASK_FACTOR)
end

local function FrameAuraButton(aura)
	local icon = aura.Icon
	if not icon or auraMasks[aura] or aura:IsForbidden() then
		return
	end
	local mask = aura:CreateMaskTexture()
	mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
	mask:SetPoint("CENTER", icon, "CENTER")
	icon:AddMaskTexture(mask)
	auraMasks[aura] = mask
	SizeAuraMask(aura)
	local border = aura:CreateTexture(nil, "OVERLAY", nil, -1)
	border:SetAtlas("UI-HUD-ActionBar-IconFrame")
	border:SetPoint("TOPLEFT", icon, "TOPLEFT")
	border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
end

local function FrameBuffs()
	if not BuffFrame or not BuffFrame.auraFrames then
		return
	end
	for _, aura in ipairs(BuffFrame.auraFrames) do
		FrameAuraButton(aura)
	end
	-- Edit Mode can change the icon size.
	hooksecurefunc(BuffFrame, "UpdateSize", function()
		for aura in pairs(auraMasks) do
			SizeAuraMask(aura)
		end
	end)
end

---------------------------------------------------------------------------
-- iSquidMod end caps (textures by Ganders & Imithat, original author SAM)
---------------------------------------------------------------------------
local SQUID_PATH = ([[Interface\AddOns\%s\Media\iSquidMod\]]):format(addonName)
local SQUID_SKINS = {
	"griffon", "lion", "diablo1", "diablo1_roth", "diablo2", "diablo2_roth", "diablo3crest",
	"murloc", "murloc2", "crest", "hordecrest", "orccrest", "allianzcrest", "nightelfcrest",
	"undeadcrest", "pandacrest", "druidcrest", "huntercrest", "magecrest", "magecrest2",
	"palacrest", "priestcrest", "roguecrest", "shamancrest", "shamancrest2", "warlockcrest",
	"warriorcrest", "dkcrest", "monkcrest", "crusadercrest", "axecrest", "worg", "bfmage",
	"panda", "pandakind", "swking", "draenei", "druidtree", "druidbear", "lichking",
	"nightelf", "onyxia", "orc", "orc2", "ysera", "drake", "wowlogo", "orbdaemon",
	"yulon", "xuen", "niuzao", "minichi", "minidroplet", "miniporcupette", "minisha",
	"minixuen", "miniyulon",
}

local squidTextures = {}

local function ApplySquid()
	local caps = MainActionBar and MainActionBar.EndCaps
	if not caps then
		return
	end
	local skin = Visuals.db.squid
	for index, cap in ipairs({ caps.LeftEndCap, caps.RightEndCap }) do
		if cap and cap.Texture then
			local custom = squidTextures[index]
			if not custom then
				custom = cap:CreateTexture(nil, "OVERLAY", nil, 6)
				custom:SetAllPoints(cap)
				squidTextures[index] = custom
			end
			if skin == "default" then
				cap.Texture:SetAlpha(1)
				custom:Hide()
			elseif skin == "hide" then
				cap.Texture:SetAlpha(0)
				custom:Hide()
			else
				cap.Texture:SetAlpha(0)
				custom:SetTexture(SQUID_PATH .. skin)
				if index == 1 then
					custom:SetTexCoord(0, 1, 0.35, 1)
				else
					custom:SetTexCoord(1, 0, 0.35, 1)
				end
				custom:Show()
			end
		end
	end
end

local function SquidValues()
	local values = { { "default", L.VISUALS_SQUID_DEFAULT }, { "hide", L.VISUALS_SQUID_HIDE } }
	for _, skin in ipairs(SQUID_SKINS) do
		values[#values + 1] = { skin, skin }
	end
	return values
end

---------------------------------------------------------------------------
-- Action button colours: out of range red, no mana blue, unusable grey
---------------------------------------------------------------------------
local outOfRange = setmetatable({}, { __mode = "k" })

local function ColorButton(button)
	local icon = button.icon
	if not icon or not button.action then
		return
	end
	-- With the option disabled this reproduces Blizzard's own colouring.
	local db = Visuals.db
	local enabled = db.actionColors
	if enabled and db.colorRange and outOfRange[button] then
		icon:SetVertexColor(0.8, 0.1, 0.1)
		return
	end
	local isUsable, notEnoughMana = C_ActionBar.IsUsableAction(button.action)
	if isUsable then
		icon:SetVertexColor(1, 1, 1)
	elseif notEnoughMana and (not enabled or db.colorMana) then
		icon:SetVertexColor(0.5, 0.5, 1)
	elseif not notEnoughMana and (not enabled or db.colorUnusable) then
		icon:SetVertexColor(0.4, 0.4, 0.4)
	else
		icon:SetVertexColor(1, 1, 1)
	end
end

local actionButtons = {}

local function OnRangeUpdate(button, checksRange, inRange)
	if not actionButtons[button] then
		return
	end
	local out = checksRange and not inRange or nil
	if outOfRange[button] ~= out then
		outOfRange[button] = out
		ColorButton(button)
	end
end

local function HookActionButtons()
	if not (ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames) then
		return
	end
	for _, button in pairs(ActionBarButtonEventsFrame.frames) do
		if not actionButtons[button] and button.UpdateUsable then
			actionButtons[button] = true
			hooksecurefunc(button, "UpdateUsable", ColorButton)
		end
	end
	hooksecurefunc("ActionButton_UpdateRangeIndicator", OnRangeUpdate)
end

local function RecolorAll()
	for button in pairs(actionButtons) do
		ColorButton(button)
	end
end

---------------------------------------------------------------------------
-- Outline for all fonts (font objects; skips those already outlined)
---------------------------------------------------------------------------
local outlined = {}

local function OutlineFonts()
	for _, name in ipairs(GetFonts()) do
		if not outlined[name] then
			outlined[name] = true
			local font = _G[name]
			if type(font) == "table" and font.GetFont and not font:IsForbidden() then
				ns.ApplyOutline(font)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Visuals:OnInitialize()
	hooksecurefunc("SetItemButtonQuality", UpdateGlow)
	OutlineFonts()
	self:RegisterEvent("ADDON_LOADED", OutlineFonts)
end

function Visuals:OnLogin()
	OutlineFonts()
	if MainActionBar and MainActionBar.UpdateEndCaps then
		hooksecurefunc(MainActionBar, "UpdateEndCaps", ApplySquid)
	end
	ApplySquid()
	FrameBuffs()
	HookActionButtons()
	RecolorAll()
end

function Visuals:OnOptionChanged(key)
	if key == "squid" then
		ApplySquid()
	else
		RecolorAll()
	end
end

Visuals.options = {
	{ type = "header", name = L.VISUALS_SQUID_HEADER, desc = L.VISUALS_SQUID_CREDIT },
	{ key = "squid", type = "dropdown", name = L.VISUALS_SQUID, desc = L.VISUALS_SQUID_CREDIT, values = SquidValues },
	{ type = "header", name = L.VISUALS_ACTION_HEADER },
	{ key = "actionColors", type = "toggle", name = L.VISUALS_ACTION_COLORS, desc = L.VISUALS_ACTION_COLORS_DESC },
	{ key = "colorRange", type = "toggle", name = L.VISUALS_COLOR_RANGE, parent = "actionColors" },
	{ key = "colorMana", type = "toggle", name = L.VISUALS_COLOR_MANA, parent = "actionColors" },
	{ key = "colorUnusable", type = "toggle", name = L.VISUALS_COLOR_UNUSABLE, parent = "actionColors" },
}

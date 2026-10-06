-- Visuals: quality frame on item buttons, iSquidMod end caps,
-- action button state colouring, outlined fonts and unit frame bar textures.
local addonName, ns = ...
local L = ns.L

-- Blizzard's frame for action buttons without bar art, around buffs and
-- quest item buttons.
local ICON_FRAME_STYLE = "standalone"

local Visuals = ns:NewModule("Visuals", {
	title = L.VISUALS_TITLE,
	order = 9,
	defaults = {
		squid = "default",
		actionColors = true,
		colorRange = true,
		colorMana = true,
		colorUnusable = true,
		colorActiveBuff = true,
		activeBuffExceptions = {}, -- spell name -> true: never greyed out
		unitBars = true,
		playerDragon = "none",
		dragonScale = 100,
	},
})

---------------------------------------------------------------------------
-- Item quality frame (like the tooltip frame) from "uncommon" upwards
---------------------------------------------------------------------------
local borders = setmetatable({}, { __mode = "k" })

local function UpdateGlow(button, quality)
	if not button or (button.IsForbidden and button:IsForbidden()) then
		return
	end
	local border = borders[button]
	if quality and quality >= Enum.ItemQuality.Uncommon then
		-- Wide buttons (quest rewards: icon plus name) get the frame on the icon only.
		local icon = button.Icon or button.icon
		local anchor = button
		local iconWidth = icon and icon.GetWidth and ns.Number(icon:GetWidth(), 0) or 0
		if iconWidth > 0 and ns.Number(button:GetWidth(), 0) > iconWidth * 1.5 then
			anchor = icon
		end
		border = border or ns.CreatePixelBorder(button, anchor, 2, "OVERLAY", 7)
		borders[button] = border
		border:ShowColor(C_Item.GetItemQualityColor(quality))
	elseif border then
		border:Hide()
	end
end

---------------------------------------------------------------------------
-- Player buffs get the action button frame and rounded icon corners
---------------------------------------------------------------------------
local framedAuras = {}

local function FrameAuraButton(aura)
	if not aura.Icon or framedAuras[aura] or aura:IsForbidden() then
		return
	end
	framedAuras[aura] = true
	ns.ApplyActionFrame(aura, aura.Icon, ICON_FRAME_STYLE)
end

local function ResizeAuraFrames()
	for aura in pairs(framedAuras) do
		ns.SizeActionFrame(aura, ICON_FRAME_STYLE)
	end
end

local function FrameBuffs()
	if not BuffFrame or not BuffFrame.auraFrames then
		return
	end
	for _, aura in ipairs(BuffFrame.auraFrames) do
		FrameAuraButton(aura)
	end
	-- Edit Mode can change the icon size.
	hooksecurefunc(BuffFrame, "UpdateSize", ResizeAuraFrames)
end

---------------------------------------------------------------------------
-- Quest item buttons of the objective tracker get the same frame
---------------------------------------------------------------------------
local framedQuestItems = {}

local function FrameQuestItem(button)
	if framedQuestItems[button] or not button.icon then
		return
	end
	framedQuestItems[button] = true
	-- Blizzard's round quest item frame is replaced by the action button art.
	if button.NormalTexture then
		button.NormalTexture:SetAlpha(0)
	end
	local pushed = button:GetPushedTexture()
	if pushed then
		pushed:SetAlpha(0)
	end
	ns.ApplyActionFrame(button, button.icon, ICON_FRAME_STYLE)
end

-- Item icons of quest rewards and quest log rewards.
local function FrameQuestRewards()
	local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button.Icon and not framedQuestItems[button] then
			framedQuestItems[button] = true
			ns.ApplyActionFrame(button, button.Icon, ICON_FRAME_STYLE)
		end
	end
end

local function HookQuestItems()
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", FrameQuestRewards)
	end
	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", function()
		if QuestObjectiveItemButtonMixin and QuestObjectiveItemButtonMixin.SetUp then
			hooksecurefunc(QuestObjectiveItemButtonMixin, "SetUp", FrameQuestItem)
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

-- Self buffs that are active (seals, aspects, armors, shields): names of the
-- player's helpful auras, refreshed on UNIT_AURA for the player.
local activeAuras = {}
local selfBuffCache = {}
local desaturated = setmetatable({}, { __mode = "k" })

local function IsSelfBuff(spellID)
	local cached = selfBuffCache[spellID]
	if cached == nil then
		cached = C_Spell.IsSelfBuff and C_Spell.IsSelfBuff(spellID) and true or false
		selfBuffCache[spellID] = cached
	end
	return cached
end

local function IsActiveSelfBuff(action)
	local actionType, id = GetActionInfo(action)
	if actionType ~= "spell" or type(id) ~= "number" or not IsSelfBuff(id) then
		return false
	end
	local name = C_Spell.GetSpellName(id)
	return name and activeAuras[name] and not Visuals.db.activeBuffExceptions[name] or false
end

-- Self buffs on the action bars, for the exception menu (by name, sorted).
local MAX_ACTION_SLOT = 180
local function SelfBuffsOnBars()
	local names, seen = {}, {}
	for slot = 1, MAX_ACTION_SLOT do
		local actionType, id = GetActionInfo(slot)
		if actionType == "spell" and type(id) == "number" and IsSelfBuff(id) then
			local name = C_Spell.GetSpellName(id)
			if name and not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names
end

local function SetGreyed(button, icon, greyed)
	if greyed then
		icon:SetDesaturated(true)
		desaturated[button] = true
	elseif desaturated[button] then
		icon:SetDesaturated(false)
		desaturated[button] = nil
	end
end

local function ColorButton(button)
	local icon = button.icon
	if not icon or not button.action then
		return
	end
	-- With the option disabled this reproduces Blizzard's own colouring.
	local db = Visuals.db
	local enabled = db.actionColors
	if enabled and db.colorRange and outOfRange[button] then
		SetGreyed(button, icon, false)
		icon:SetVertexColor(0.8, 0.1, 0.1)
		return
	end
	local activeBuff = enabled and db.colorActiveBuff and IsActiveSelfBuff(button.action)
	SetGreyed(button, icon, activeBuff)
	if activeBuff then
		icon:SetVertexColor(0.7, 0.7, 0.7)
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

-- Rebuilds the aura name set; recolours only when it changed.
local auraWatcher
local function UpdateActiveAuras()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		return
	end
	local names = {}
	local index = 1
	while true do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
		if not aura then
			break
		end
		local name = aura.name
		if name and not (issecretvalue and issecretvalue(name)) then
			names[name] = true
		end
		index = index + 1
	end
	local changed = false
	for name in pairs(names) do
		if not activeAuras[name] then
			changed = true
			break
		end
	end
	if not changed then
		for name in pairs(activeAuras) do
			if not names[name] then
				changed = true
				break
			end
		end
	end
	if changed then
		activeAuras = names
		RecolorAll()
	end
end

local function UpdateAuraWatch()
	local enabled = Visuals.db.actionColors and Visuals.db.colorActiveBuff
	if enabled and not auraWatcher then
		auraWatcher = CreateFrame("Frame")
		auraWatcher:SetScript("OnEvent", ns.Measured("Visuals: active buffs", UpdateActiveAuras))
	end
	if auraWatcher then
		if enabled then
			auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
			UpdateActiveAuras()
		else
			auraWatcher:UnregisterEvent("UNIT_AURA")
			wipe(activeAuras)
		end
	end
end

---------------------------------------------------------------------------
-- Outline for all fonts (font objects; skips those already outlined)
---------------------------------------------------------------------------
local outlined = {}

-- Dark text on parchment (quests, gossip, books, letters) turns into black
-- blobs with an outline, so those fonts are kept (or made) outline free.
local function IsDarkFont(font)
	local r, g, b = font:GetTextColor()
	return r and r + g + b < 0.9
end

local function RemoveOutline(font)
	local face, size, flags = font:GetFont()
	if face and flags and flags:find("OUTLINE") then
		flags = flags:gsub("THICKOUTLINE", ""):gsub("OUTLINE", ""):gsub("^[,%s]+", ""):gsub("[,%s]+$", ""):gsub(",[,%s]*,", ",")
		font:SetFont(face, size, flags)
	end
end

-- Two passes: dark fonts may inherit from fonts outlined in the first pass.
local function OutlineFonts()
	local dark
	for _, name in ipairs(GetFonts()) do
		if not outlined[name] then
			outlined[name] = true
			local font = _G[name]
			if type(font) == "table" and font.GetFont and not font:IsForbidden() then
				if IsDarkFont(font) then
					dark = dark or {}
					dark[#dark + 1] = font
				else
					ns.ApplyOutline(font)
				end
			end
		end
	end
	for _, font in ipairs(dark or {}) do
		RemoveOutline(font)
	end
end

-- Some windows colour single texts dark instead of using a dark font (spell
-- book names on parchment). Those texts get their outline removed directly.
local MAX_DEPTH = 8

local function StripDarkOutlines(frame, depth)
	depth = depth or 0
	if depth > MAX_DEPTH or not frame or frame:IsForbidden() then
		return
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then
			local r, g, b = region:GetTextColor()
			if ns.Number(r) and r + g + b < 0.9 then
				local face, size, flags = region:GetFont()
				if face and flags and flags:find("OUTLINE") then
					region:SetFont(face, size, "")
				end
			end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		StripDarkOutlines(child, depth + 1)
	end
end

local function HookParchmentWindows()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
		if not book then
			return
		end
		local function Strip()
			StripDarkOutlines(book)
		end
		if book.OnPagedSpellsUpdate then
			hooksecurefunc(book, "OnPagedSpellsUpdate", Strip)
		end
		book:HookScript("OnShow", Strip)
	end)
	ns.OnAddOnLoaded("Blizzard_ProfessionsBook", function()
		if ProfessionsBookFrame then
			ProfessionsBookFrame:HookScript("OnShow", function(frame)
				StripDarkOutlines(frame)
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Experience, reputation and tooltip health bars with the unit frame texture
---------------------------------------------------------------------------
local BAR_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"

-- Blizzard's tracking bar atlases and the colour of the same bar (classic colours).
local TRACKING_COLORS = {
	["UI-HUD-ExperienceBar-Fill-Experience"] = { 0.58, 0, 0.55 },
	["UI-HUD-ExperienceBar-Fill-Rested"] = { 0, 0.39, 0.88 },
	["UI-HUD-ExperienceBar-Fill-Reputation-Faction-Red"] = { 0.8, 0.13, 0.13 },
	["UI-HUD-ExperienceBar-Fill-Reputation-Faction-Orange"] = { 0.85, 0.4, 0.05 },
	["UI-HUD-ExperienceBar-Fill-Reputation-Faction-Yellow"] = { 0.9, 0.7, 0 },
	["UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green"] = { 0, 0.6, 0.1 },
	["UI-HUD-ExperienceBar-Fill-Reputation-Faction-Blue"] = { 0, 0.39, 0.88 },
}

-- Grey version of the unit frame bar, tinted by the bar colour.
local function UseUnitBarTexture(statusBar)
	statusBar:SetStatusBarTexture(BAR_ATLAS)
	local texture = statusBar:GetStatusBarTexture()
	if texture then
		texture:SetDesaturated(true)
	end
end

local styling = false
local function StyleTrackingBar(statusBar, asset)
	local color = not styling and Visuals.db.unitBars and TRACKING_COLORS[asset]
	if not color then
		return
	end
	styling = true
	UseUnitBarTexture(statusBar)
	statusBar:SetStatusBarColor(color[1], color[2], color[3])
	styling = false
end

local barsHooked = false
local function StyleUnitBars()
	if not Visuals.db.unitBars or barsHooked then
		return
	end
	barsHooked = true
	if GameTooltip.StatusBar then
		UseUnitBarTexture(GameTooltip.StatusBar)
	end
	ns.OnAddOnLoaded("Blizzard_StatusTrackingBar", function()
		for _, container in ipairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
			for _, bar in pairs(container.bars or {}) do
				local statusBar = bar.StatusBar
				if statusBar then
					hooksecurefunc(statusBar, "SetStatusBarTexture", StyleTrackingBar)
					local texture = statusBar:GetStatusBarTexture()
					if texture then
						StyleTrackingBar(statusBar, texture:GetAtlas())
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Elite/rare dragon around the player portrait (target frame art, mirrored)
---------------------------------------------------------------------------
local BRONZE = { 0.86, 0.55, 0.28 }
local GOLD = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"
local GOLD_WINGED = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged"
local SILVER = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver"
-- Size and centre relative to the top left of the player frame container.
local SHAPES = {
	plain = { width = 100, height = 100, x = 50, y = -50 },
	winged = { width = 110, height = 91, x = 42, y = -50.5 },
}
-- key -> atlas, shape, desaturate, tint
local DRAGONS = {
	gold = { GOLD, "plain" },
	goldWinged = { GOLD_WINGED, "winged" },
	silver = { SILVER, "plain" },
	silverWinged = { GOLD_WINGED, "winged", true },
	bronze = { GOLD, "plain", true, BRONZE },
	bronzeWinged = { GOLD_WINGED, "winged", true, BRONZE },
}
local dragon

local function ApplyPlayerDragon()
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	if not container then
		return
	end
	local data = DRAGONS[Visuals.db.playerDragon]
	if not data then
		if dragon then
			dragon:Hide()
		end
		return
	end
	-- Above the frame art, like the dragon on the target frame.
	dragon = dragon or container:CreateTexture(nil, "OVERLAY", nil, 6)
	-- The target art faces right; mirror it for the portrait on the left
	-- (absolute atlas coordinates showed only part of the dragon).
	dragon:SetAtlas(data[1])
	dragon:SetTexCoord(1, 0, 0, 1)
	local shape = SHAPES[data[2]]
	local scale = Visuals.db.dragonScale / 100
	dragon:SetSize(shape.width * scale, shape.height * scale)
	dragon:ClearAllPoints()
	dragon:SetPoint("CENTER", container, "TOPLEFT", shape.x, shape.y)
	dragon:SetDesaturated(data[3] and true or false)
	local tint = data[4]
	if tint then
		dragon:SetVertexColor(tint[1], tint[2], tint[3])
	else
		dragon:SetVertexColor(1, 1, 1)
	end
	dragon:Show()
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
	HookParchmentWindows()
	if MainActionBar and MainActionBar.UpdateEndCaps then
		hooksecurefunc(MainActionBar, "UpdateEndCaps", ApplySquid)
	end
	ApplySquid()
	FrameBuffs()
	HookQuestItems()
	HookActionButtons()
	UpdateAuraWatch()
	RecolorAll()
	StyleUnitBars()
	ApplyPlayerDragon()
end

function Visuals:OnOptionChanged(key)
	if key == "squid" then
		ApplySquid()
	elseif key == "playerDragon" or key == "dragonScale" then
		ApplyPlayerDragon()
	elseif key == "unitBars" then
		if self.db.unitBars then
			StyleUnitBars()
		else
			ns.Print(L.RELOAD_REQUIRED)
		end
	else
		UpdateAuraWatch()
		RecolorAll()
	end
end

-- Checked spells are greyed out while active; a click toggles one spell.
function Visuals:ShowBuffExceptions()
	local exceptions = self.db.activeBuffExceptions
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle(L.VISUALS_ACTIVE_BUFF_EXCEPTIONS)
		local names = SelfBuffsOnBars()
		if #names == 0 then
			root:CreateTitle(L.VISUALS_ACTIVE_BUFF_NONE)
		end
		for _, name in ipairs(names) do
			root:CreateCheckbox(name, function()
				return not exceptions[name]
			end, function()
				exceptions[name] = not exceptions[name] or nil
				RecolorAll()
			end)
		end
	end)
end

Visuals.options = {
	{ type = "header", name = L.VISUALS_SQUID_HEADER, desc = L.VISUALS_SQUID_CREDIT },
	{ key = "squid", type = "dropdown", name = L.VISUALS_SQUID, desc = L.VISUALS_SQUID_CREDIT, values = SquidValues },
	{ type = "header", name = L.VISUALS_ACTION_HEADER },
	{ key = "actionColors", type = "toggle", name = L.VISUALS_ACTION_COLORS, desc = L.VISUALS_ACTION_COLORS_DESC },
	{ key = "colorRange", type = "toggle", name = L.VISUALS_COLOR_RANGE, parent = "actionColors" },
	{ key = "colorMana", type = "toggle", name = L.VISUALS_COLOR_MANA, parent = "actionColors" },
	{ key = "colorUnusable", type = "toggle", name = L.VISUALS_COLOR_UNUSABLE, parent = "actionColors" },
	{ key = "colorActiveBuff", type = "toggle", name = L.VISUALS_COLOR_ACTIVE_BUFF, desc = L.VISUALS_COLOR_ACTIVE_BUFF_DESC, parent = "actionColors" },
	{ type = "button", name = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS, text = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS_BUTTON, desc = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS_DESC, func = function()
		Visuals:ShowBuffExceptions()
	end },
	{ type = "header", name = L.VISUALS_PORTRAIT_HEADER },
	{ key = "playerDragon", type = "dropdown", name = L.VISUALS_DRAGON, desc = L.VISUALS_DRAGON_DESC, values = {
		{ "none", L.VISUALS_DRAGON_NONE }, { "gold", L.VISUALS_DRAGON_GOLD }, { "goldWinged", L.VISUALS_DRAGON_GOLD_WINGED },
		{ "silver", L.VISUALS_DRAGON_SILVER }, { "silverWinged", L.VISUALS_DRAGON_SILVER_WINGED },
		{ "bronze", L.VISUALS_DRAGON_BRONZE }, { "bronzeWinged", L.VISUALS_DRAGON_BRONZE_WINGED },
	} },
	{ key = "dragonScale", type = "slider", name = L.VISUALS_DRAGON_SCALE, min = 80, max = 130, step = 1, format = function(value)
		return ("%d %%"):format(value)
	end },
	{ type = "header", name = L.VISUALS_BARS_HEADER },
	{ key = "unitBars", type = "toggle", name = L.VISUALS_UNIT_BARS, desc = L.VISUALS_UNIT_BARS_DESC },
}

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
		paladinRecommendations = true,
		paladinSealRecommendation = true,
		combatBuffRecommendation = false,
		castsLeft = false,
		auraActionFrame = true,
		bagActionFrame = false, -- thin line on grey and white items (looked odd in the bags: off, once reset for all)
		bagFrameOff = false,
		activeBuffExceptions = {}, -- spell name -> true: never greyed out
		unitBars = true,
		playerDragon = "none",
		dragonScale = 100,
	},
})

---------------------------------------------------------------------------
-- Item quality frame (like the tooltip frame) from "uncommon" upwards, soft grey for grey and white items (option)
---------------------------------------------------------------------------
local borders = setmetatable({}, { __mode = "k" })

-- Grey and white items in the bags and on the character: no frame is laid over the game's own slot art, only a
-- thin, translucent line a little inside the picture (option); from green upwards the crisp quality frame.
local soft = setmetatable({}, { __mode = "k" })
local NEUTRAL = { [0] = { 0.6, 0.6, 0.6, 0.3 }, [1] = { 1, 1, 1, 0.3 } } -- poor, common

local function SoftBorder(button)
	local line = soft[button]
	if not line then
		local icon = button.Icon or button.icon or button
		local inner = CreateFrame("Frame", nil, button)
		inner:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
		inner:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
		inner:SetFrameLevel(button:GetFrameLevel() + 1)
		line = ns.CreatePixelBorder(inner, inner, 1, "OVERLAY", 7)
		soft[button] = line
	end
	return line
end

local function UpdateGlow(button, quality, forced)
	if not button or (button.IsForbidden and button:IsForbidden()) then
		return
	end
	local border = borders[button]
	local low = quality and quality <= Enum.ItemQuality.Common and (forced or button.GetBagID) and Visuals.db.bagActionFrame
	if low and not button.CircleMask then
		local color = NEUTRAL[quality] or NEUTRAL[1]
		SoftBorder(button):ShowColor(color[1], color[2], color[3], color[4])
		if border then
			border:Hide()
		end
		return
	elseif soft[button] then
		soft[button]:Hide()
	end
	-- Round buttons (profession output) already get Blizzard's round quality ring.
	if quality and quality >= Enum.ItemQuality.Uncommon and not button.CircleMask then
		-- Wide buttons (quest rewards: icon plus name) get the frame on the icon only.
		local icon = button.Icon or button.icon
		local anchor = button
		local iconWidth = icon and icon.GetWidth and ns.Number(icon:GetWidth(), 0) or 0
		if iconWidth > 0 and ns.Number(button:GetWidth(), 0) > iconWidth * 1.5 then
			anchor = icon
		end
		border = border or ns.CreatePixelBorder(button, anchor, 2, "OVERLAY", 7)
		borders[button] = border
		-- GetItemQualityColor also returns the colour as text: only the three numbers go on.
		local r, g, b = C_Item.GetItemQualityColor(quality)
		border:ShowColor(r, g, b)
	elseif border then
		border:Hide()
	end
end

-- For the bag buttons (Items.lua, called on every bag update) and the character slots (below).
function ns.FrameItemButton(button, quality)
	UpdateGlow(button, quality, true)
end

---------------------------------------------------------------------------
-- Player buffs get the action button frame and rounded icon corners
---------------------------------------------------------------------------
local framedAuras = setmetatable({}, { __mode = "k" })
local framedAuraContainers = setmetatable({}, { __mode = "k" })

local function SetAuraActionFrame(aura, icon, iconOwner)
	local state = framedAuras[aura]
	if not state then
		state = { icon = icon, borders = {}, applied = false }
		framedAuras[aura] = state
	end
	-- Blizzard adds a colored border for debuffs and an extra normal texture;
	-- leave the icon and countdown/count regions alone so the action-bar frame
	-- is the only frame around the image.
	for _, owner in ipairs({ aura, iconOwner }) do
		for _, key in ipairs({ "Border", "DebuffBorder", "NormalTexture", "normalTexture" }) do
			local region = owner[key]
			if region and region.SetAlpha and state.borders[region] == nil then
				local alpha = region.GetAlpha and region:GetAlpha()
				state.borders[region] = alpha == nil and 1 or alpha
			end
		end
	end
	if Visuals.db.auraActionFrame then
		for region in pairs(state.borders) do region:SetAlpha(0) end
		if not state.applied then
			ns.ApplyActionFrame(aura, icon, ICON_FRAME_STYLE, 7)
			state.applied = true
		end
		ns.SetActionFrameEnabled(aura, true)
	else
		for region, alpha in pairs(state.borders) do region:SetAlpha(alpha) end
		if state.applied then ns.SetActionFrameEnabled(aura, false) end
	end
end

local function FrameAuraButton(aura)
	if not aura or (aura.IsForbidden and aura:IsForbidden()) then
		return
	end
	local iconOwner = aura.Icon or aura.icon
	local icon = iconOwner
	if icon and type(icon.AddMaskTexture) ~= "function" then
		icon = icon.Icon or icon.Texture or icon.texture
	end
	if not icon or type(icon.AddMaskTexture) ~= "function" then return end
	SetAuraActionFrame(aura, icon, iconOwner)
end

local function FrameAuraButtons(container)
	if not container then return end
	for _, aura in ipairs(container.auraFrames or {}) do
		FrameAuraButton(aura)
	end
	-- Classic aura buttons may be named globals rather than stored in
	-- auraFrames; also catches buttons created after the initial login pass.
	for _, prefix in ipairs({ "BuffButton", "DebuffButton" }) do
		for index = 1, ns.Number(prefix == "BuffButton" and BUFF_MAX_DISPLAY or DEBUFF_MAX_DISPLAY, 40) do
			FrameAuraButton(_G[prefix .. index])
		end
	end
	for aura in pairs(framedAuras) do
		if aura.GetParent and aura:GetParent() == container then
			FrameAuraButton(aura)
			ns.SizeActionFrame(aura, ICON_FRAME_STYLE)
		end
	end
end

local function ResizeAuraFrames()
	for aura in pairs(framedAuras) do
		FrameAuraButton(aura)
		ns.SizeActionFrame(aura, ICON_FRAME_STYLE)
	end
end

local function FrameBuffs()
	for _, container in pairs({ BuffFrame, DebuffFrame }) do
		if container then
			FrameAuraButtons(container)
			if type(container.UpdateSize) == "function" and not framedAuraContainers[container] then
				framedAuraContainers[container] = true
				hooksecurefunc(container, "UpdateSize", function()
					FrameAuraButtons(container)
					ResizeAuraFrames()
				end)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quest item buttons of the objective tracker get the same frame
---------------------------------------------------------------------------
local framedQuestItems = {}

local function FrameQuestItem(button)
	if not button.icon then
		return
	end
	-- Blizzard's own art (the round quest item ring, the action button
	-- template frame) is replaced by the action button art. The client can
	-- show it again when the button updates, so it is hidden on every call.
	if button.NormalTexture then
		button.NormalTexture:SetAlpha(0)
	end
	local pushed = button:GetPushedTexture()
	if pushed then
		pushed:SetAlpha(0)
	end
	-- A standalone action button (no bar) does not show the empty slot art.
	if button.SlotArt then
		button.SlotArt:Hide()
	end
	if not framedQuestItems[button] then
		framedQuestItems[button] = true
		ns.ApplyActionFrame(button, button.icon, ICON_FRAME_STYLE)
	end
	-- The icon of a fresh action button has no size yet (the client anchors
	-- it during the first layout pass); only the repeated sizing, like the
	-- buffs get, lets the frame appear in every case.
	ns.SizeActionFrame(button, ICON_FRAME_STYLE)
end

-- ForeverPlus' own action-style buttons (quest item, openables) get the same frame.
function ns.FrameActionButton(button)
	FrameQuestItem(button)
end

-- Item icons of quest rewards and quest log rewards. Their frame lies above
-- the button's own overlays: Blizzard's icon border (same size as the icon)
-- otherwise covers most of it. Sized on every display, the buttons are
-- laid out anew each time.
local REWARD_FRAME_LEVEL = 3

local function FrameQuestRewards()
	local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button.Icon then
			if not framedQuestItems[button] then
				framedQuestItems[button] = true
				ns.ApplyActionFrame(button, button.Icon, ICON_FRAME_STYLE, REWARD_FRAME_LEVEL)
			end
			ns.SizeActionFrame(button)
			-- Quality colour of the item on the frame.
			local quality
			if button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
				local link = (QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink)(button.type, button:GetID())
				quality = link and not ns.Secret(link) and select(3, C_Item.GetItemInfo(link))
			end
			local r, g, b
			if quality and quality >= 1 then
				r, g, b = C_Item.GetItemQualityColor(quality)
			end
			ns.SetActionFrameColor(button, r, g, b)
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
local buffButtons = {}
local desaturated = setmetatable({}, { __mode = "k" })

-- Weapon imbues are self-buffs too, but the client does not classify every
-- rank of them through C_Spell.IsSelfBuff.
local WEAPON_ENCHANT_SPELLS = {
	[8017] = true, -- Rockbiter Weapon
	[8024] = true, -- Flametongue Weapon
	[8033] = true, -- Frostbrand Weapon
	[8232] = true, -- Windfury Weapon
	[51730] = true, -- Earthliving Weapon
}

-- Weapon imbues are no auras: they show up as weapon enchants. The enchant IDs and
-- cast spells of the shaman imbues come from DPSSim (ns.WeaponImbues, filled at load).
local imbueKinds, activeImbues, activeEnchantLines = {}, {}, {}

local function ImbueKind(spellID)
	if not next(imbueKinds) then
		for _, imbue in pairs(ns.WeaponImbues or {}) do
			imbueKinds[imbue.spellID] = imbue.kind
		end
	end
	return imbueKinds[spellID]
end

local function IsSelfBuff(spellID)
	local cached = selfBuffCache[spellID]
	if cached == nil then
		cached = ImbueKind(spellID) and true or WEAPON_ENCHANT_SPELLS[spellID] or (C_Spell.IsSelfBuff and C_Spell.IsSelfBuff(spellID)) and true or false
		selfBuffCache[spellID] = cached
	end
	return cached
end

local function ActiveAuraForItem(itemID)
	local spellName = C_Item.GetItemSpell(itemID)
	if spellName and activeAuras[spellName] then
		return spellName
	end
	-- Poison, oil and stone item names can match the applied aura even when
	-- the item's use spell is only named "Apply Poison" or similar.
	local itemName = C_Item.GetItemInfo(itemID)
	if itemName and activeAuras[itemName] then
		return itemName
	end
end

-- Poisons, oils and stones: the weapon tooltip names the applied enchant ("Name (30 min)"),
-- which starts with the item's own name.
local function ActiveEnchantForItem(itemID)
	if not next(activeEnchantLines) then
		return
	end
	local itemName = C_Item.GetItemInfo(itemID)
	if not itemName or ns.Secret(itemName) then
		return
	end
	for line in pairs(activeEnchantLines) do
		if line == itemName or line:sub(1, #itemName + 2) == itemName .. " (" then
			return itemName
		end
	end
end

local function IsActiveSelfBuff(button)
	local actionType, id = GetActionInfo(button.action)
	if type(id) ~= "number" then
		buffButtons[button] = nil
		return false
	end
	local name
	local imbueKind = actionType == "spell" and ImbueKind(id)
	if imbueKind then
		buffButtons[button] = true
		local spellName = C_Spell.GetSpellName(id)
		return activeImbues[imbueKind] and not (spellName and Visuals.db.activeBuffExceptions[spellName]) or false
	elseif actionType == "spell" and IsSelfBuff(id) then
		buffButtons[button] = true
		name = next(activeAuras) and C_Spell.GetSpellName(id)
	elseif actionType == "item" then
		-- Weapon oils, poisons and similar consumables are items on the bar;
		-- their active effect is exposed as a helpful player aura.
		buffButtons[button] = true
		name = next(activeAuras) and ActiveAuraForItem(id)
		if not name then
			local enchantName = ActiveEnchantForItem(id)
			return enchantName and not Visuals.db.activeBuffExceptions[enchantName] or false
		end
	else
		buffButtons[button] = nil
	end
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
		elseif actionType == "item" and type(id) == "number" then
			local name = ActiveAuraForItem(id) or ActiveEnchantForItem(id)
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
	local activeBuff = enabled and db.colorActiveBuff and IsActiveSelfBuff(button)
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

local function RecolorBuffButtons()
	for button in pairs(buffButtons) do
		if not (Visuals.db.colorRange and outOfRange[button]) then
			ColorButton(button)
		end
	end
end

local WEAPON_SLOTS = { { "MainHand", INVSLOT_MAINHAND }, { "OffHand", INVSLOT_OFFHAND } }

-- Enchant lines of a weapon's tooltip: "Name (30 min)".
local function EnchantLines(inventorySlot, lines)
	local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", inventorySlot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and not ns.Secret(text) then
			lines[text] = true
		end
	end
end

-- Kinds of imbue and enchant lines currently on the weapons. In combat the data may be
-- unreadable: the last known set is kept then.
local function ScanImbues()
	local kinds, lines = {}, {}
	for _, slot in ipairs(WEAPON_SLOTS) do
		local list = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot[slot[1]])
		if ns.Secret(list) then
			return nil
		end
		local enchanted = false
		for _, enchant in pairs(list or {}) do
			if ns.Secret(enchant) or ns.Secret(enchant.hasEnchant) then
				return nil
			end
			if enchant.hasEnchant then
				enchanted = true
				local imbue = (ns.WeaponImbues or {})[ns.Number(enchant.enchantID)]
				if imbue then
					kinds[imbue.kind] = true
				end
			end
		end
		if enchanted then
			EnchantLines(slot[2], lines)
		end
	end
	return kinds, lines
end

local function SameSet(a, b)
	for key in pairs(a) do
		if not b[key] then
			return false
		end
	end
	for key in pairs(b) do
		if not a[key] then
			return false
		end
	end
	return true
end

local function UpdateImbues()
	if not (C_Item and C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot) then
		return
	end
	local ok, kinds, lines = pcall(ScanImbues)
	if not ok or not kinds then
		return
	end
	if not (SameSet(kinds, activeImbues) and SameSet(lines, activeEnchantLines)) then
		activeImbues, activeEnchantLines = kinds, lines
		RecolorBuffButtons()
	end
end

---------------------------------------------------------------------------
-- Casts left: how often a spell on an action button can still be cast with
-- the current mana (small number at the bottom left).
---------------------------------------------------------------------------
local CASTS_COLOR = { 0.6, 0.8, 1 }
local CASTS_DELAY = 0.1
local castTexts = {}
local manaCosts = {} -- spellID -> mana cost or false

local function ManaCost(spellID)
	local cost = manaCosts[spellID]
	if cost == nil then
		cost = false
		for _, info in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
			local needed = ns.Number(info.minCost, 0) > 0 and info.minCost or ns.Number(info.cost, 0)
			if info.type == Enum.PowerType.Mana and needed > 0 then
				cost = needed
			end
		end
		manaCosts[spellID] = cost
	end
	return cost or nil
end

local function ActionSpell(action)
	local actionType, id = GetActionInfo(action)
	if actionType == "macro" then
		id = GetMacroSpell(id)
		actionType = id and "spell"
	end
	return actionType == "spell" and ns.Number(id) or nil
end

local function UpdateCasts(button)
	local count
	if Visuals.db.castsLeft and button.action then
		local spellID = ActionSpell(button.action)
		local cost = spellID and ManaCost(spellID)
		local mana = cost and ns.Number(UnitPower("player", Enum.PowerType.Mana))
		count = mana and math.floor(mana / cost)
	end
	local text = castTexts[button]
	if count and not text then
		text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		text:SetPoint("BOTTOMLEFT", 2, 2)
		text:SetTextColor(CASTS_COLOR[1], CASTS_COLOR[2], CASTS_COLOR[3])
		castTexts[button] = text
	end
	if text then
		text:SetText(count or "")
		text:SetShown(count ~= nil)
	end
end

local castsPending = false
local function UpdateAllCasts()
	castsPending = false
	for button in pairs(actionButtons) do
		UpdateCasts(button)
	end
end

local function QueueCasts()
	if not castsPending then
		castsPending = true
		ns.After("Visuals: UpdateAllCasts", CASTS_DELAY, UpdateAllCasts)
	end
end

local castWatcher
local function UpdateCastWatch()
	local enabled = Visuals.db.castsLeft
	if enabled and not castWatcher then
		castWatcher = CreateFrame("Frame")
		castWatcher:SetScript("OnEvent", ns.Measured("Visuals: cast event", function(_, event, _, powerType)
			-- Only mana decides how many casts are left.
			if event == "UNIT_POWER_UPDATE" and (ns.Secret(powerType) or powerType ~= "MANA") then
				return
			end
			if event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" then
				wipe(manaCosts)
			end
			QueueCasts()
		end))
	end
	if castWatcher then
		local events = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
			"PLAYER_LEVEL_UP", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }
		for _, event in ipairs(events) do
			if enabled then
				castWatcher:RegisterEvent(event)
			else
				castWatcher:UnregisterEvent(event)
			end
		end
		if enabled then
			castWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		else
			castWatcher:UnregisterEvent("UNIT_POWER_UPDATE")
		end
	end
	UpdateAllCasts()
end

-- Rebuilds the aura name set; recolours only when it changed.
local auraWatcher
local auraIDs = {} -- auraInstanceID -> name, from the last readable look at the auras
local auraReadable = false

local function AurasAreSecret()
	return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

---------------------------------------------------------------------------
-- Paladin self-buff recommendations on the action bars and the aura bar.
---------------------------------------------------------------------------
local MIGHT, WISDOM, KINGS = { 19740, 25782 }, { 19742, 25894 }, { 20217, 25898 }
local DEVOTION, RETRIBUTION, CONCENTRATION = { 465 }, { 7294 }, { 19746 }
local SEAL_WISDOM, SEAL_FURY, SEAL_COMMAND = { 20166 }, { 1311649 }, { 20375 }
local SEAL_LIGHT, SEAL_RIGHTEOUSNESS = { 20165 }, { 20154, 21084 }
local SEAL_DURATION = 30
local PALADIN_RECOMMENDATIONS = {
	{ blessings = { WISDOM, KINGS, MIGHT }, auras = { CONCENTRATION, DEVOTION },
		seals = { SEAL_WISDOM, SEAL_LIGHT, SEAL_RIGHTEOUSNESS } }, -- Holy
	{ blessings = { KINGS, WISDOM, MIGHT }, auras = { DEVOTION },
		seals = { SEAL_FURY, SEAL_RIGHTEOUSNESS } }, -- Protection
	{ blessings = { MIGHT, KINGS, WISDOM }, auras = { RETRIBUTION, DEVOTION },
		seals = { SEAL_COMMAND, SEAL_RIGHTEOUSNESS } }, -- Retribution
}
local PALADIN_BLESSINGS = { MIGHT, WISDOM, KINGS, { 1022, 1044, 6940 } } -- Protection, Freedom, Sacrifice
local PALADIN_AURAS = { DEVOTION, RETRIBUTION, CONCENTRATION, { 19876, 19888, 19891 } } -- Resistance auras
local PALADIN_SEALS = { SEAL_WISDOM, SEAL_FURY, SEAL_COMMAND, SEAL_LIGHT, SEAL_RIGHTEOUSNESS, { 21082, 20164 } } -- Crusader, Justice

local function BuffFamilyNames(families)
	local names = {}
	for _, family in ipairs(families) do
		for _, spellID in ipairs(family) do
			local name = C_Spell.GetSpellName(spellID)
			if name then
				names[name] = true
			end
		end
	end
	return names
end

local function HasPaladinBuff(names)
	for name in pairs(names) do
		if activeAuras[name] then
			return true
		end
	end
	return false
end

-- Names match all trained ranks and both versions of a blessing.
local function FirstKnownFamily(families)
	for _, family in ipairs(families) do
		local names, known = {}, false
		for _, spellID in ipairs(family) do
			local name = C_Spell.GetSpellName(spellID)
			if name then
				names[name] = true
				known = known or C_SpellBook.IsSpellKnown(spellID) or C_SpellBook.FindSpellBookSlotForSpell(name) ~= nil
			end
		end
		if known then
			return names
		end
	end
end

local recommendationGlows = setmetatable({}, { __mode = "k" })

local function HideRecommendationGlow(glow)
	if glow and glow:IsShown() then
		glow.pulse:Stop()
		glow:Hide()
	end
end

local function ShowRecommendationGlow(button)
	local glow = recommendationGlows[button]
	if glow and glow:IsShown() then
		return
	end
	if not glow then
		local icon = button.icon or button
		glow = CreateFrame("Frame", nil, button)
		glow:SetAllPoints(icon)
		glow:SetFrameLevel(button:GetFrameLevel() + 3)
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		texture:SetBlendMode("ADD")
		texture:SetVertexColor(0.2, 0.65, 1)
		texture:SetPoint("CENTER")
		local width, height = button:GetSize()
		texture:SetSize(width * 1.8, height * 1.8)
		glow.border = ns.CreatePixelBorder(glow, glow, 2)
		glow.pulse = texture:CreateAnimationGroup()
		glow.pulse:SetLooping("BOUNCE")
		local fade = glow.pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.55)
		fade:SetDuration(0.85)
		recommendationGlows[button] = glow
	end
	glow.border:ShowColor(0.2, 0.65, 1)
	glow:Show()
	glow.pulse:Play()
end

local paladinWatch, paladinUpdatePending
local paladinEnabled
local paladinBlessing, paladinAura, paladinSeal
local paladinBlessingNames, paladinAuraNames, paladinSealNames
local showPaladinBlessing, showPaladinAura, showPaladinSeal
local refreshPaladinSpells
local sealExpiration, sealAuraID, sealTimer -- nil = unknown, false = active with unknown expiry, 0 = absent
local UpdatePaladinHighlights

local function StopSealTimer()
	if sealTimer then
		sealTimer:Cancel()
		sealTimer = nil
	end
end

local function SetSealState(expiration, auraID)
	if sealExpiration ~= expiration then
		StopSealTimer()
	end
	sealExpiration, sealAuraID = expiration, auraID
end

local function SealMissingInCombat()
	if not (paladinEnabled and Visuals.db.paladinSealRecommendation and paladinSeal and InCombatLockdown()) then
		StopSealTimer()
		return false
	end
	if type(sealExpiration) ~= "number" then
		return false
	end
	local remaining = sealExpiration - GetTime()
	if remaining <= 0 then
		return true
	end
	if not sealTimer then
		sealTimer = ns.NewTimer("Visuals: seal expires", remaining, function()
			sealTimer = nil
			UpdatePaladinHighlights()
		end)
	end
	return false
end

function UpdatePaladinHighlights(force)
	if paladinEnabled and refreshPaladinSpells then
		local _, _, tree = ns.TalentTreeOf()
		local profile = PALADIN_RECOMMENDATIONS[tree] or PALADIN_RECOMMENDATIONS[3]
		paladinBlessing = FirstKnownFamily(profile.blessings)
		paladinAura = FirstKnownFamily(profile.auras)
		paladinSeal = FirstKnownFamily(profile.seals)
		paladinBlessingNames = BuffFamilyNames(PALADIN_BLESSINGS)
		paladinAuraNames = BuffFamilyNames(PALADIN_AURAS)
		refreshPaladinSpells = false
		force = true
	end
	local readable = paladinEnabled and Visuals.db.paladinRecommendations and auraReadable
	local blessing = readable and paladinBlessing ~= nil and not HasPaladinBuff(paladinBlessingNames)
	local aura = readable and paladinAura ~= nil and not HasPaladinBuff(paladinAuraNames)
	local seal = SealMissingInCombat()
	if not force and blessing == showPaladinBlessing and aura == showPaladinAura and seal == showPaladinSeal then
		return
	end
	showPaladinBlessing, showPaladinAura, showPaladinSeal = blessing, aura, seal
	for _, glow in pairs(recommendationGlows) do
		HideRecommendationGlow(glow)
	end
	if not (blessing or aura or seal) then
		return
	end
	for _, button in pairs(ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames or {}) do
		local slot = ns.Number(button.action)
		local spellID = slot and ActionSpell(slot)
		local name = spellID and C_Spell.GetSpellName(spellID)
		if name and ((blessing and paladinBlessing[name]) or (aura and paladinAura[name]) or (seal and paladinSeal[name])) then
			ShowRecommendationGlow(button)
		end
	end
	if aura and StanceBar and StanceBar.actionButtons then
		for index = 1, GetNumShapeshiftForms() do
			local button = StanceBar.actionButtons[index]
			local spellID = ns.Number(select(4, GetShapeshiftFormInfo(index)))
			local name = spellID and C_Spell.GetSpellName(spellID)
			if button and name and paladinAura[name] then
				ShowRecommendationGlow(button)
			end
		end
	end
end

local PALADIN_BUTTON_EVENTS = {
	"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
	"UPDATE_MACROS", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM",
}
local PALADIN_SPELL_EVENTS = {
	PLAYER_ENTERING_WORLD = true, SPELLS_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
	PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true, TRAIT_TREE_CURRENCY_INFO_UPDATED = true,
}

local function UpdatePaladinWatch()
	if select(2, UnitClass("player")) ~= "PALADIN" then
		return
	end
	paladinEnabled = Visuals.db.paladinRecommendations or Visuals.db.paladinSealRecommendation
	if Visuals.db.paladinSealRecommendation then
		paladinSealNames = BuffFamilyNames(PALADIN_SEALS)
	else
		paladinSealNames = nil
		SetSealState(nil)
	end
	if paladinEnabled then
		if not paladinWatch then
			paladinWatch = CreateFrame("Frame")
			paladinWatch:SetScript("OnEvent", ns.Measured("Visuals: paladin recommendation event", function(_, event, _, _, spellID)
				if event == "UNIT_SPELLCAST_SUCCEEDED" then
					local id = ns.Number(spellID)
					local name = id and C_Spell.GetSpellName(id)
					if name and paladinSealNames and paladinSealNames[name] then
						SetSealState(GetTime() + SEAL_DURATION)
						UpdatePaladinHighlights()
					elseif ns.Secret(spellID) and AurasAreSecret() then
						SetSealState(nil)
						UpdatePaladinHighlights()
					end
					return
				end
				refreshPaladinSpells = refreshPaladinSpells or PALADIN_SPELL_EVENTS[event]
				if not paladinUpdatePending then
					paladinUpdatePending = true
					ns.After("Visuals: paladin recommendations", 0, function()
						paladinUpdatePending = false
						UpdatePaladinHighlights(true)
					end)
				end
			end))
		end
		for _, event in ipairs(PALADIN_BUTTON_EVENTS) do
			if C_EventUtils.IsEventValid(event) then
				paladinWatch:RegisterEvent(event)
			end
		end
		for event in pairs(PALADIN_SPELL_EVENTS) do
			if C_EventUtils.IsEventValid(event) then
				paladinWatch:RegisterEvent(event)
			end
		end
		if paladinSealNames then
			paladinWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
			paladinWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
			paladinWatch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		else
			paladinWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
			paladinWatch:UnregisterEvent("PLAYER_REGEN_ENABLED")
			paladinWatch:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		end
	elseif paladinWatch then
		paladinWatch:UnregisterAllEvents()
	end
	refreshPaladinSpells = true
	UpdatePaladinHighlights(true)
end

---------------------------------------------------------------------------
-- Optional in-combat buff recommendations for the other supported classes.
---------------------------------------------------------------------------
local LIGHTNING_SHIELD, WATER_SHIELD = { 324 }, { 408510 }
local BATTLE_SHOUT_DURATION = 3 * 60
local COMBAT_BUFF_FAMILIES = {
	SHAMAN = { LIGHTNING_SHIELD, WATER_SHIELD },
	ROGUE = { { 5171, 6774 } }, -- Slice and Dice
	WARRIOR = { { 6673 } }, -- Battle Shout
}

local combatBuffWatch, combatBuffClass, combatBuffPending
local combatBuffChoice, combatBuffNames
local combatBuffExpiration, combatBuffAuraID, combatBuffTimer -- nil = unknown, false = active, 0 = absent
local refreshCombatChoice, refreshCombatAuras, refreshCombatButtons
local combatBuffButtons = {}

local function ReadCombatBuff()
	local readable = true
	for name in pairs(combatBuffNames) do
		-- Query only the relevant buffs. The client can deny the read or return secret data in combat.
		local ok, buff = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
		if not ok or ns.Secret(buff) then
			readable = false
		elseif buff then
			local expiration = ns.Number(buff.expirationTime, 0)
			return expiration > 0 and expiration or false, ns.Number(buff.auraInstanceID)
		end
	end
	return readable and 0 or nil
end

local function SetCombatBuffState(expiration, auraID)
	if combatBuffTimer and combatBuffExpiration ~= expiration then
		combatBuffTimer:Cancel()
		combatBuffTimer = nil
	end
	combatBuffExpiration, combatBuffAuraID = expiration, auraID
end

local function ReadCombatBuffInstance()
	if not combatBuffAuraID or not C_UnitAuras.GetUnitAuraInstanceIDs then
		return
	end
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, "player", "HELPFUL")
	if not ok or ns.Secret(ids) or type(ids) ~= "table" then
		return
	end
	for _, id in ipairs(ids) do
		if ns.Secret(id) or id == combatBuffAuraID then
			return
		end
	end
	return 0
end

local function ClearCombatBuffButtons()
	for button in pairs(combatBuffButtons) do
		HideRecommendationGlow(recommendationGlows[button])
	end
	wipe(combatBuffButtons)
end

local function UpdateCombatBuffHighlights()
	combatBuffPending = false
	if not combatBuffClass then
		SetCombatBuffState(nil)
		ClearCombatBuffButtons()
		return
	end
	if refreshCombatChoice then
		local families = COMBAT_BUFF_FAMILIES[combatBuffClass]
		local _, _, tree = ns.TalentTreeOf()
		local order = combatBuffClass == "SHAMAN" and tree == 3 and { WATER_SHIELD, LIGHTNING_SHIELD } or families
		-- The Restoration talent grants a separate spell for casting Water Shield.
		if order ~= families and C_SpellBook.IsSpellKnown(409941) then
			combatBuffChoice = BuffFamilyNames({ WATER_SHIELD })
		else
			combatBuffChoice = FirstKnownFamily(order)
		end
		combatBuffNames = BuffFamilyNames(families)
		refreshCombatChoice = false
		refreshCombatAuras, refreshCombatButtons = true, true
	end
	if refreshCombatAuras then
		local expiration, auraID = ReadCombatBuff()
		if expiration == nil then
			expiration = ReadCombatBuffInstance()
		end
		if expiration ~= nil or not InCombatLockdown() then
			SetCombatBuffState(expiration, auraID)
		end
		refreshCombatAuras = false
	end
	if not InCombatLockdown() then
		if combatBuffTimer then
			combatBuffTimer:Cancel()
			combatBuffTimer = nil
		end
		ClearCombatBuffButtons()
		return
	end
	local remaining = type(combatBuffExpiration) == "number" and (combatBuffExpiration - GetTime())
	local missing = remaining and remaining <= 0
	if remaining and remaining > 0 and not combatBuffTimer then
		combatBuffTimer = ns.NewTimer("Visuals: combat buff expires", remaining, function()
			combatBuffTimer = nil
			refreshCombatAuras = true
			UpdateCombatBuffHighlights()
		end)
	end
	if refreshCombatButtons then
		ClearCombatBuffButtons()
		if combatBuffChoice then
			for _, button in pairs(ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames or {}) do
				local slot = ns.Number(button.action)
				local id = slot and ActionSpell(slot)
				local name = id and C_Spell.GetSpellName(id)
				if name and combatBuffChoice[name] then
					combatBuffButtons[button] = slot
				end
			end
		end
		refreshCombatButtons = false
	end
	for button, slot in pairs(combatBuffButtons) do
		local usable = missing and C_ActionBar.IsUsableAction(slot)
		if not ns.Secret(usable) and usable then
			ShowRecommendationGlow(button)
		else
			HideRecommendationGlow(recommendationGlows[button])
		end
	end
end

local function UpdateCombatBuffWatch()
	local _, class = UnitClass("player")
	combatBuffClass = Visuals.db.combatBuffRecommendation and COMBAT_BUFF_FAMILIES[class] and class or nil
	if combatBuffClass then
		if not combatBuffWatch then
			combatBuffWatch = CreateFrame("Frame")
			combatBuffWatch:SetScript("OnEvent", ns.Measured("Visuals: combat buff event", function(_, event, _, updateInfo, spellID)
				if PALADIN_SPELL_EVENTS[event] then
					refreshCombatChoice = true
				elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
					local id = ns.Number(spellID)
					local name = id and C_Spell.GetSpellName(id)
					if not (name and combatBuffNames and combatBuffNames[name]) then
						return
					end
					-- An observed cast hides the hint even if the new aura cannot be read yet.
					SetCombatBuffState(combatBuffClass == "WARRIOR" and GetTime() + BATTLE_SHOUT_DURATION or false)
				elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
					if event == "UNIT_AURA" and combatBuffAuraID and not ns.Secret(updateInfo) then
						local removedIDs = updateInfo and updateInfo.removedAuraInstanceIDs
						if not ns.Secret(removedIDs) then
							for _, id in ipairs(removedIDs or {}) do
								if ns.Number(id) == combatBuffAuraID then
									SetCombatBuffState(0)
									break
								end
							end
						end
					end
					refreshCombatAuras = true
					refreshCombatButtons = refreshCombatButtons or event == "PLAYER_REGEN_DISABLED"
				elseif event ~= "ACTION_USABLE_CHANGED" and event ~= "ACTIONBAR_UPDATE_USABLE" then
					refreshCombatButtons = true
				end
				if not combatBuffPending then
					combatBuffPending = true
					ns.After("Visuals: combat buff recommendations", 0, UpdateCombatBuffHighlights)
				end
			end))
		end
		for _, event in ipairs(PALADIN_BUTTON_EVENTS) do
			if C_EventUtils.IsEventValid(event) then
				combatBuffWatch:RegisterEvent(event)
			end
		end
		for event in pairs(PALADIN_SPELL_EVENTS) do
			if C_EventUtils.IsEventValid(event) then
				combatBuffWatch:RegisterEvent(event)
			end
		end
		local usableEvent = C_EventUtils.IsEventValid("ACTION_USABLE_CHANGED") and "ACTION_USABLE_CHANGED" or "ACTIONBAR_UPDATE_USABLE"
		combatBuffWatch:RegisterEvent(usableEvent)
		combatBuffWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
		combatBuffWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
		combatBuffWatch:RegisterUnitEvent("UNIT_AURA", "player")
		combatBuffWatch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	elseif combatBuffWatch then
		combatBuffWatch:UnregisterAllEvents()
	end
	refreshCombatChoice = true
	UpdateCombatBuffHighlights()
end

-- In combat the auras are secret and the last set was kept: a seal used up by a judgement or run out stayed greyed
-- until the fight ended. A removed aura ends its greying; when the removal cannot be read, all greying ends
-- (a usable spell shown grey is worse than an active one shown normal).
local function ForgetRemovedAuras(updateInfo)
	if not next(activeAuras) then
		return
	end
	local ok, result = pcall(function()
		if not updateInfo or ns.Secret(updateInfo.isFullUpdate) or updateInfo.isFullUpdate then
			return "all"
		end
		local changed = false
		for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
			if ns.Secret(id) then
				return "all"
			end
			local name = auraIDs[id]
			if name then
				activeAuras[name], auraIDs[id] = nil, nil
				changed = true
			end
		end
		return changed and "some" or nil
	end)
	if not ok or result == "all" then
		wipe(activeAuras)
		wipe(auraIDs)
		RecolorBuffButtons()
	elseif result then
		RecolorBuffButtons()
	end
end

Visuals.ForgetRemovedAuras = ForgetRemovedAuras
local function ScanActiveAuras()
	local auras = C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuras("player", "HELPFUL")
	local names, ids = {}, {}
	local index, complete = 1, true
	local sealEnd, sealID
	while true do
		local aura
		if auras then
			aura = auras[index]
		else
			aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
		end
		if not aura then
			break
		end
		local name = aura.name
		local id = aura.auraInstanceID
		local knownName = name and not ns.Secret(name)
		if knownName then
			names[name] = true
			if paladinSealNames and paladinSealNames[name] then
				local expiration = ns.Number(aura.expirationTime, 0)
				sealEnd = expiration > 0 and expiration or false
				sealID = ns.Number(id)
			end
		end
		if knownName and id and not ns.Secret(id) then
			ids[id] = name
		else
			complete = false
		end
		index = index + 1
	end
	return names, ids, complete, sealEnd, sealID
end

local function WaitForReadableAuras()
	auraReadable = false
	auraWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	if paladinEnabled then
		UpdatePaladinHighlights()
	end
end

local function UpdateActiveAuras()
	UpdateImbues()
	if not (C_UnitAuras and (C_UnitAuras.GetUnitAuras or C_UnitAuras.GetAuraDataByIndex)) then
		return
	end
	-- Keep the last known set while auras are restricted.
	if AurasAreSecret() then
		WaitForReadableAuras()
		return
	end
	local ok, names, ids, complete, sealEnd, sealID = pcall(ScanActiveAuras)
	if not ok then
		WaitForReadableAuras()
		return
	end
	auraWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local readabilityChanged = auraReadable ~= complete
	auraReadable = complete
	auraIDs = ids
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
		RecolorBuffButtons()
	end
	local sealChanged = false
	if paladinSealNames and (sealEnd ~= nil or complete) then
		if sealEnd == nil then
			sealEnd = 0
		end
		sealChanged = sealExpiration ~= sealEnd
		SetSealState(sealEnd, sealID)
	end
	if paladinEnabled and (changed or readabilityChanged or sealChanged) then
		UpdatePaladinHighlights()
	end
end

local function CheckSealRemoval(updateInfo)
	for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
		if ns.Number(id) == sealAuraID then
			SetSealState(0)
			UpdatePaladinHighlights()
			return
		end
	end
end

-- Timer refreshes and stack changes keep the same aura instance and name.
-- Harmful additions and removals outside our helpful set can be ignored.
local function AuraNamesMayChange(updateInfo)
	if not updateInfo or ns.Secret(updateInfo.isFullUpdate) or updateInfo.isFullUpdate then
		return true
	end
	for _, aura in ipairs(updateInfo.addedAuras or {}) do
		local helpful = aura.isHelpful
		if ns.Secret(helpful) or helpful ~= false then
			return true
		end
	end
	for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
		if ns.Secret(id) or auraIDs[id] then
			return true
		end
	end
	return false
end

-- UNIT_AURA comes in bursts: one rebuild per frame.
local auraUpdatePending = false
local function QueueAuraUpdate()
	if not auraUpdatePending then
		auraUpdatePending = true
		ns.After("Visuals: QueueAuraUpdate (timer)", 0, function()
			auraUpdatePending = false
			if paladinEnabled or (Visuals.db.actionColors and Visuals.db.colorActiveBuff) then
				UpdateActiveAuras()
			end
		end)
	end
end

local function UpdateAuraWatch()
	local colorBuffs = Visuals.db.actionColors and Visuals.db.colorActiveBuff
	local enabled = paladinEnabled or colorBuffs
	if not colorBuffs then
		wipe(buffButtons)
	end
	if enabled and not auraWatcher then
		auraWatcher = CreateFrame("Frame")
		auraWatcher:SetScript("OnEvent", ns.Measured("Visuals: active buffs", function(_, event, _, updateInfo)
			if event == "UNIT_INVENTORY_CHANGED" then
				UpdateImbues()
			end
			if AurasAreSecret() then
				if event == "UNIT_AURA" then
					if sealAuraID and updateInfo then
						pcall(CheckSealRemoval, updateInfo)
					end
					ForgetRemovedAuras(updateInfo)
				end
				if auraReadable or not auraWatcher:IsEventRegistered("PLAYER_REGEN_ENABLED") then
					WaitForReadableAuras()
				end
				return
			end
			if event == "UNIT_AURA" and auraReadable then
				local ok, changed = pcall(AuraNamesMayChange, updateInfo)
				if ok and not changed then
					return
				end
			end
			QueueAuraUpdate()
		end))
	end
	if auraWatcher then
		if enabled then
			auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
			auraWatcher:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
			UpdateActiveAuras()
		else
			auraWatcher:UnregisterEvent("UNIT_AURA")
			auraWatcher:UnregisterEvent("UNIT_INVENTORY_CHANGED")
			auraWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
			auraReadable = false
			wipe(activeAuras)
			wipe(auraIDs)
			activeImbues, activeEnchantLines = {}, {}
		end
		if paladinEnabled then
			auraWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
			auraWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
		else
			auraWatcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
			auraWatcher:UnregisterEvent("PLAYER_REGEN_DISABLED")
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
			-- Name plates keep the game's font: set again with one file it loses the glyphs of other alphabets.
			local font = not name:find("NamePlate", 1, true) and _G[name]
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

local function StripDarkText(fontString)
	local r, g, b = fontString:GetTextColor()
	if ns.Number(r) and r + g + b < 0.9 then
		local face, size, flags = fontString:GetFont()
		if face and flags and flags:find("OUTLINE") then
			fontString:SetFont(face, size, "")
		end
	end
end

local function StripDarkOutlines(frame, depth)
	depth = depth or 0
	if depth > MAX_DEPTH or not frame or frame:IsForbidden() then
		return
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then
			StripDarkText(region)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		StripDarkOutlines(child, depth + 1)
	end
end

-- Spell book entries are created and refilled as pages change or more
-- ranks are shown; each one is checked when its texts are set.
local function StripSpellBookItem(item)
	for _, key in ipairs({ "Name", "SubName", "RequiredLevel" }) do
		local text = item[key]
		if text and text.GetFont then
			RemoveOutline(text)
		end
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
		book:HookScript("OnShow", Strip)
		-- Entries made from here on carry the hook (the mixin is copied into each).
		if SpellBookItemMixin and SpellBookItemMixin.UpdateVisuals then
			hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", StripSpellBookItem)
		end
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

local trackingBars = {}
local tooltipBarAppearance

local function RefreshTrackingBar(bar, state, textureChanged)
	local color = Visuals.db.unitBars and not ns.Secret(state.asset) and TRACKING_COLORS[state.asset]
	if color then
		local originalColor = state.color or { bar:GetStatusBarColor() }
		local originalDesaturation = state.desaturation or bar:GetStatusBarDesaturation()
		state.applying = true
		if bar:SetStatusBarTexture(BAR_ATLAS) then
			state.color, state.desaturation = originalColor, originalDesaturation
			bar:SetStatusBarDesaturation(1)
			bar:SetStatusBarColor(color[1], color[2], color[3], originalColor[4])
		end
		state.applying = false
	elseif state.color then
		if not textureChanged then
			state.applying = true
			bar:SetStatusBarTexture(state.asset)
			state.applying = false
		end
		bar:SetStatusBarDesaturation(state.desaturation)
		bar:SetStatusBarColor(unpack(state.color))
		state.color, state.desaturation = nil, nil
	end
end

local function RefreshUnitBars()
	for bar, state in pairs(trackingBars) do
		RefreshTrackingBar(bar, state)
	end
	local bar = GameTooltip.StatusBar
	local texture = bar and bar:GetStatusBarTexture()
	if not texture then
		return
	end
	if Visuals.db.unitBars and not tooltipBarAppearance then
		local asset = texture:GetAtlas() or texture:GetTexture()
		local desaturation = bar:GetStatusBarDesaturation()
		if asset and bar:SetStatusBarTexture(BAR_ATLAS) then
			tooltipBarAppearance = { asset = asset, desaturation = desaturation }
			bar:SetStatusBarDesaturation(1)
		end
	elseif not Visuals.db.unitBars and tooltipBarAppearance then
		bar:SetStatusBarTexture(tooltipBarAppearance.asset)
		bar:SetStatusBarDesaturation(tooltipBarAppearance.desaturation)
		tooltipBarAppearance = nil
	end
end

local function HookTrackingBars()
	for _, container in ipairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
		local indices = StatusTrackingBarInfo.BarsEnum
		for _, index in ipairs({ indices.Experience, indices.Reputation }) do
			local wrapper = container.bars and container.bars[index]
			local bar = wrapper and wrapper.StatusBar
			if bar and not trackingBars[bar] then
				local texture = bar:GetStatusBarTexture()
				local state = { asset = texture and texture:GetAtlas() }
				trackingBars[bar] = state
				hooksecurefunc(bar, "SetStatusBarTexture", ns.Measured("Visuals: tracking bar texture", function(_, asset)
					if not state.applying then
						state.asset = asset
						RefreshTrackingBar(bar, state, true)
					end
				end))
				RefreshTrackingBar(bar, state)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Elite/rare dragon around the player portrait (target frame art, mirrored)
---------------------------------------------------------------------------
-- Tint on the desaturated gold dragon: the bronze of the game's portrait frame (ratio green/blue to red about
-- 0.74 / 0.43). The game's own gold dragon is brighter (screenshot: lights 245/223/140 against 222/177/110), so a
-- second, additive copy lifts the tinted one a little (BRIGHTEN).
local BRONZE = { 1.0, 0.74, 0.43 }
local BRIGHTEN = 0.22
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
-- Rectangles on a 24 x 24 grid, from the alpha of the mirrored client atlases.
-- The thin tail in the lower right uses a lower alpha threshold.
-- Leave the transparent centre available for normal portrait clicks.
local DRAGON_HITS = {
	[GOLD] = {
		{10,0,11,1}, {16,0,17,1}, {4,1,19,2}, {6,2,20,3}, {22,2,23,3}, {5,3,23,4},
		{2,4,13,5}, {15,4,23,5}, {3,5,9,6}, {15,5,24,6}, {3,6,7,7}, {2,7,6,8},
		{1,8,5,9}, {2,9,5,11}, {1,11,5,14}, {2,14,5,16}, {2,16,6,17}, {2,17,7,18},
		{20,17,21,18}, {2,18,3,19}, {4,18,7,19}, {19,18,21,19}, {4,19,9,20}, {17,19,20,20},
		{5,20,11,21}, {12,20,19,21}, {5,21,6,22}, {8,21,19,22}, {9,22,16,23}, {13,23,16,24},
	},
	[SILVER] = {
		{10,0,12,1}, {14,0,15,1}, {16,0,17,1}, {3,1,19,2}, {6,2,21,3}, {22,2,23,3},
		{4,3,23,4}, {2,4,13,5}, {14,4,23,5}, {3,5,9,6}, {15,5,24,6}, {3,6,7,7},
		{2,7,6,8}, {1,8,5,9}, {2,9,5,11}, {1,11,5,14}, {2,14,5,16}, {2,16,6,17},
		{2,17,7,18}, {20,17,21,18}, {2,18,3,19}, {4,18,7,19}, {19,18,21,19}, {4,19,9,20},
		{17,19,20,20}, {4,20,11,21}, {12,20,19,21}, {5,21,6,22}, {8,21,19,22}, {9,22,16,23},
		{10,23,11,24}, {13,23,16,24},
	},
	[GOLD_WINGED] = {
		{8,1,11,2}, {13,1,19,2}, {9,2,21,3}, {9,3,23,4}, {4,4,15,5}, {16,4,23,5},
		{5,5,12,6}, {17,5,24,6}, {4,6,10,7}, {3,7,9,9}, {2,9,9,10}, {2,10,8,11},
		{1,11,8,12}, {1,12,4,13}, {5,12,8,14}, {1,13,3,19}, {6,14,9,17}, {6,17,10,18},
		{20,17,22,18}, {8,18,11,19}, {20,18,21,19}, {2,19,3,20}, {8,19,13,20}, {18,19,21,20},
		{8,20,20,21}, {11,21,20,22}, {12,22,17,23}, {12,23,14,24}, {16,23,17,24},
	},
}
local DRAGON_GRID = 24
local dragon, dragonButtons

local function CanUsePlayerDragon()
	local unit = PlayerFrame.unit
	return not ns.Secret(unit) and unit == "player" and not ns:IsEditModeActive()
end

local function DrawDragonHover(group)
	local progress = group.progress
	local eased = progress * progress * (3 - 2 * progress)
	dragon:SetPoint("CENTER", group:GetParent(), "TOPLEFT", group.x, group.y + 2.5 * eased)
	dragon.Bright:SetAlpha(group.baseShine + 0.18 * eased)
end

local function UpdateDragonHover(group, elapsed)
	local direction = group.hovered and 1 or -1
	group.progress = math.max(0, math.min(1, group.progress + direction * elapsed / 0.14))
	DrawDragonHover(group)
	if group.progress == 0 or group.progress == 1 then
		group.animating = false
		ns.SetUpdate(group, "Visuals: portrait dragon", nil)
	end
end

local function SetDragonHovered(button, hovered)
	local group = button:GetParent()
	if not group.baseShine then return end
	if hovered then
		if not CanUsePlayerDragon() then return end
		group.hovered = button
	elseif group.hovered == button then
		group.hovered = false
	end
	if not group.animating and group.progress ~= (group.hovered and 1 or 0) then
		group.animating = true
		ns.SetUpdate(group, "Visuals: portrait dragon", UpdateDragonHover)
	end
end

local function PlaceDragonButtons(container, atlas, shape, width, height, baseShine)
	local group = dragonButtons
	if not group then
		group = CreateFrame("Frame", "ForeverPlusPlayerDragonButtons", container)
		group:SetFrameLevel(PlayerFrame:GetFrameLevel() + 10)
		group.parts = {}
		group:SetScript("OnHide", ns.Measured("Visuals: hide portrait dragon controls", function(self)
			self.hovered, self.progress, self.animating = false, 0, false
			ns.SetUpdate(self, "Visuals: portrait dragon", nil)
			if self.baseShine then DrawDragonHover(self) end
		end))
		dragonButtons = group
	end
	group.hovered, group.animating = false, false
	group.x, group.y, group.baseShine, group.progress = shape.x, shape.y, baseShine or false, 0
	group:SetPoint("CENTER", container, "TOPLEFT", shape.x, shape.y)
	group:SetSize(width, height)
	local cellWidth, cellHeight = width / DRAGON_GRID, height / DRAGON_GRID
	local rects = DRAGON_HITS[atlas]
	for index, rect in ipairs(rects) do
		local button = group.parts[index]
		if not button then
			button = CreateFrame("Button", nil, group)
			button:RegisterForClicks("LeftButtonUp")
			button:SetPassThroughButtons("RightButton", "MiddleButton", "Button4", "Button5")
			button:SetScript("OnClick", ns.Measured("Roleplay: dragon click", function()
				if CanUsePlayerDragon() and not IsModifierKeyDown() then ns:GetModule("Roleplay").OpenEditor() end
			end))
			button:SetScript("OnEnter", ns.Measured("Visuals: dragon hover", function(self) SetDragonHovered(self, true) end))
			button:SetScript("OnLeave", ns.Measured("Visuals: dragon leave", function(self) SetDragonHovered(self, false) end))
			group.parts[index] = button
		end
		button:SetPoint("TOPLEFT", group, "TOPLEFT", rect[1] * cellWidth, -rect[2] * cellHeight)
		button:SetSize((rect[3] - rect[1]) * cellWidth, (rect[4] - rect[2]) * cellHeight)
		button:Show()
	end
	for index = #rects + 1, #group.parts do group.parts[index]:Hide() end
	group:Show()
end

function Visuals.ApplyPlayerDragon()
	if dragonButtons then dragonButtons:Hide() end
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	if not container then
		return
	end
	local data = DRAGONS[Visuals.db.playerDragon]
	local roleplay = ns:GetModule("Roleplay")
	local interactive = roleplay and roleplay.db and roleplay.db.playerPortraitClick
	local shape = SHAPES[data and data[2] or "plain"]
	local scale = Visuals.db.dragonScale / 100
	local width, height = shape.width * scale, shape.height * scale
	if not data then
		if dragon then
			dragon:Hide()
			dragon.Bright:Hide()
		end
		if interactive then
			PlaceDragonButtons(container, GOLD, shape, width, height)
		end
		return
	end
	-- Above the frame art, like the dragon on the target frame.
	if not dragon then
		dragon = container:CreateTexture(nil, "OVERLAY", nil, 6)
		dragon.Bright = container:CreateTexture(nil, "OVERLAY", nil, 7)
		dragon.Bright:SetAllPoints(dragon)
		dragon.Bright:SetBlendMode("ADD")
	end
	-- The target art faces right; mirror it for the portrait on the left
	-- (absolute atlas coordinates showed only part of the dragon).
	dragon:SetAtlas(data[1])
	dragon:SetTexCoord(1, 0, 0, 1)
	dragon:SetSize(width, height)
	dragon:SetPoint("CENTER", container, "TOPLEFT", shape.x, shape.y)
	local greyDragon = data[3] == true
	local tint = data[4]
	local r, g, b = 1, 1, 1
	if tint then r, g, b = unpack(tint) end
	dragon:SetDesaturated(greyDragon)
	dragon:SetVertexColor(r, g, b)
	dragon:Show()

	-- Bronze has a small amount of additive light even at rest. The same
	-- layer adds colour-matched shine when any of the dragons is hovered.
	local baseShine = tint and BRIGHTEN or 0
	local bright = dragon.Bright
	bright:SetAtlas(data[1])
	bright:SetTexCoord(1, 0, 0, 1)
	bright:SetDesaturated(greyDragon)
	bright:SetVertexColor(r, g, b)
	bright:SetAlpha(baseShine)
	bright:SetShown(tint ~= nil or interactive == true)
	if interactive then
		PlaceDragonButtons(container, data[1], shape, width, height, baseShine)
	end
end

-- The equipped items get the frame too (grey and white ones in the soft neutral colour).
local EQUIPMENT_SLOTS = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }

local function FrameCharacterSlot(button)
	if not button or (button.IsForbidden and button:IsForbidden()) then
		return
	end
	local slotID = button:GetID()
	local quality = slotID and GetInventoryItemQuality("player", slotID)
	UpdateGlow(button, quality, true)
end

local function FrameCharacterSlots()
	for _, name in ipairs(EQUIPMENT_SLOTS) do
		FrameCharacterSlot(_G["Character" .. name .. "Slot"])
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Visuals:OnInitialize()
	-- Once: the thin line on grey and white items is off for everybody (it can be switched on again).
	if not self.db.bagFrameOff then
		self.db.bagFrameOff = true
		self.db.bagActionFrame = false
	end
	hooksecurefunc("SetItemButtonQuality", UpdateGlow)
	OutlineFonts()
	self:RegisterEvent("ADDON_LOADED", OutlineFonts)
end

function Visuals:OnLogin()
	if PaperDollItemSlotButton_Update then
		hooksecurefunc("PaperDollItemSlotButton_Update", FrameCharacterSlot)
	end
	FrameCharacterSlots()
	OutlineFonts()
	HookParchmentWindows()
	if MainActionBar and MainActionBar.UpdateEndCaps then
		hooksecurefunc(MainActionBar, "UpdateEndCaps", ApplySquid)
	end
	ApplySquid()
	FrameBuffs()
	HookQuestItems()
	HookActionButtons()
	UpdatePaladinWatch()
	UpdateCombatBuffWatch()
	UpdateAuraWatch()
	RecolorAll()
	UpdateCastWatch()
	RefreshUnitBars()
	ns.OnAddOnLoaded("Blizzard_StatusTrackingBar", HookTrackingBars)
	Visuals.ApplyPlayerDragon()
end

-- All open bag buttons and character slots again (after switching the option).
local function RefreshBagFrames()
	FrameCharacterSlots()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		-- A closed bag reports its size but has no buttons yet (the combined bag before the first opening).
		if frame and frame.EnumerateValidItems and frame:IsShown() then
			for _, button in frame:EnumerateValidItems() do
				if button then
					local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
					UpdateGlow(button, info and info.quality, true)
				end
			end
		end
	end
end

function Visuals:OnOptionChanged(key)
	if key == "squid" then
		ApplySquid()
	elseif key == "auraActionFrame" then
		FrameBuffs()
	elseif key == "bagActionFrame" then
		RefreshBagFrames()
	elseif key == "playerDragon" or key == "dragonScale" then
		Visuals.ApplyPlayerDragon()
	elseif key == "castsLeft" then
		UpdateCastWatch()
	elseif key == "paladinRecommendations" or key == "paladinSealRecommendation" then
		UpdatePaladinWatch()
		UpdateAuraWatch()
	elseif key == "combatBuffRecommendation" then
		UpdateCombatBuffWatch()
	elseif key == "unitBars" then
		RefreshUnitBars()
	else
		UpdateAuraWatch()
		RecolorAll()
	end
end

-- Checked spells are greyed out while active; a click toggles one spell.
function Visuals:ShowBuffExceptions(owner)
	local exceptions = self.db.activeBuffExceptions
	ns.ShowPopupList(owner, function()
		local items = {}
		for _, name in ipairs(SelfBuffsOnBars()) do
			items[#items + 1] = {
				icon = C_Spell.GetSpellTexture(name),
				text = name,
				checked = not exceptions[name],
				onClick = function()
					exceptions[name] = not exceptions[name] or nil
					RecolorAll()
				end,
			}
		end
		return { title = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS, items = items, empty = L.VISUALS_ACTIVE_BUFF_NONE }
	end)
end

Visuals.options = {
	{ type = "header", name = L.VISUALS_SQUID_HEADER, desc = L.VISUALS_SQUID_CREDIT },
	{ key = "squid", type = "dropdown", name = L.VISUALS_SQUID, desc = L.VISUALS_SQUID_CREDIT, values = SquidValues },
	{ type = "header", name = L.VISUALS_ACTION_HEADER },
	{ key = "auraActionFrame", type = "toggle", name = L.VISUALS_AURA_ACTION_FRAME, desc = L.VISUALS_AURA_ACTION_FRAME_DESC, new = true },
	{ key = "bagActionFrame", type = "toggle", name = L.VISUALS_BAG_ACTION_FRAME, desc = L.VISUALS_BAG_ACTION_FRAME_DESC, new = true },
	{ key = "actionColors", type = "toggle", name = L.VISUALS_ACTION_COLORS, desc = L.VISUALS_ACTION_COLORS_DESC },
	{ key = "colorRange", type = "toggle", name = L.VISUALS_COLOR_RANGE, parent = "actionColors" },
	{ key = "colorMana", type = "toggle", name = L.VISUALS_COLOR_MANA, parent = "actionColors" },
	{ key = "colorUnusable", type = "toggle", name = L.VISUALS_COLOR_UNUSABLE, parent = "actionColors" },
	{ key = "colorActiveBuff", type = "toggle", name = L.VISUALS_COLOR_ACTIVE_BUFF, desc = L.VISUALS_COLOR_ACTIVE_BUFF_DESC, parent = "actionColors" },
	{ key = "castsLeft", type = "toggle", name = L.VISUALS_CASTS_LEFT, desc = L.VISUALS_CASTS_LEFT_DESC },
	{ key = "paladinRecommendations", type = "toggle", name = L.VISUALS_PALADIN_RECOMMENDATIONS,
		desc = L.VISUALS_PALADIN_RECOMMENDATIONS_DESC, new = true },
	{ key = "paladinSealRecommendation", type = "toggle", name = L.VISUALS_PALADIN_SEAL_RECOMMENDATION,
		desc = L.VISUALS_PALADIN_SEAL_RECOMMENDATION_DESC, new = true },
	{ key = "combatBuffRecommendation", type = "toggle", name = L.VISUALS_COMBAT_BUFF_RECOMMENDATION,
		desc = L.VISUALS_COMBAT_BUFF_RECOMMENDATION_DESC, new = true },
	{ key = "buffExceptions", type = "button", name = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS, text = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS_BUTTON, desc = L.VISUALS_ACTIVE_BUFF_EXCEPTIONS_DESC, func = function(button)
		Visuals:ShowBuffExceptions(button)
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

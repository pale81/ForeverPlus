-- Helpers: process bag items with Alt + right-click (disenchant, pick lock,
-- mill), a button that opens lootable items, fishing by double right-click
-- and greyed out recipes that are already known.
local _, ns = ...
local L = ns.L

local Helpers = ns:NewModule("Helpers", {
	title = L.HELPERS_TITLE,
	order = 4.8,
	defaults = {
		process = true,
		openButton = true,
		fishing = true,
		knownRecipes = true,
	},
})

local function IsRed(color)
	return color and color.r and color.r > 0.9 and color.g < 0.2 and color.b < 0.2
end

local function TooltipLines(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	return data and data.lines or {}
end

-- Locked lockbox the player can open right now (no red requirement line).
local function IsOpenableLock(bag, slot)
	local locked = false
	for _, line in ipairs(TooltipLines(bag, slot)) do
		local text = line.leftText
		if text == LOCKED then
			locked = true
		elseif IsRed(line.leftColor) then
			return false
		end
	end
	return locked
end

---------------------------------------------------------------------------
-- Processing: Alt makes processable items glow, Alt + right-click processes
---------------------------------------------------------------------------
local DISENCHANT, PICK_LOCK, MILLING = 13262, 1804, 51005
local HERB_SUBCLASS = 9
local COLORS = {
	[MILLING] = { 0.2, 1, 0.2 },
	[DISENCHANT] = { 0.75, 0.35, 1 },
	[PICK_LOCK] = { 1, 0.85, 0.1 },
}
local NO_DISENCHANT = { INVTYPE_TABARD = true, INVTYPE_BODY = true }

local function Known(spellID)
	return IsPlayerSpell and IsPlayerSpell(spellID)
end

-- Spell that processes the item in this slot, if any.
local function ProcessSpell(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.hyperlink then
		return
	end
	local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID, subClassID = C_Item.GetItemInfo(info.hyperlink)
	if not quality then
		return
	end
	if Known(DISENCHANT) and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
		and quality >= Enum.ItemQuality.Uncommon and quality <= Enum.ItemQuality.Epic and not NO_DISENCHANT[equipLoc] then
		return DISENCHANT
	end
	if Known(MILLING) and classID == Enum.ItemClass.Tradegoods and subClassID == HERB_SUBCLASS and (info.stackCount or 0) >= 5 then
		return MILLING
	end
	if Known(PICK_LOCK) and IsOpenableLock(bag, slot) then
		return PICK_LOCK
	end
end

local glows = {}

local function GetGlow(button)
	local glow = glows[button]
	if not glow then
		glow = button:CreateTexture(nil, "OVERLAY", nil, 6)
		glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		glow:SetBlendMode("ADD")
		glow:SetPoint("CENTER")
		local size = button:GetWidth() * 1.8
		glow:SetSize(size, size)
		local pulse = glow:CreateAnimationGroup()
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.35)
		fade:SetDuration(0.6)
		glow.pulse = pulse
		glows[button] = glow
	end
	return glow
end

local function BagButtons()
	local list = {}
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		if frame and frame:IsShown() and frame.EnumerateValidItems then
			for _, button in frame:EnumerateValidItems() do
				list[#list + 1] = button
			end
		end
	end
	return list
end

local function HideGlows()
	for _, glow in pairs(glows) do
		glow.pulse:Stop()
		glow:Hide()
	end
end

local function ShowGlows()
	HideGlows()
	for _, button in ipairs(BagButtons()) do
		local spellID = ProcessSpell(button:GetBagID(), button:GetID())
		if spellID then
			local glow = GetGlow(button)
			glow:SetVertexColor(unpack(COLORS[spellID]))
			glow:Show()
			glow.pulse:Play()
		end
	end
end

-- One secure button laid over the hovered bag item while Alt is held.
local overlay, hovered

local function HideOverlay()
	if overlay and overlay:IsShown() and not InCombatLockdown() then
		overlay:ClearAllPoints()
		overlay:Hide()
	end
end

local function ShowOverlay(button)
	if InCombatLockdown() or not Helpers.db.process or not IsAltKeyDown() then
		return
	end
	local bag, slot = button:GetBagID(), button:GetID()
	local spellID = ProcessSpell(bag, slot)
	if not spellID then
		HideOverlay()
		return
	end
	overlay.bag, overlay.slot = bag, slot
	overlay:SetAttribute("spell", spellID)
	overlay:SetAttribute("target-bag", bag)
	overlay:SetAttribute("target-slot", slot)
	overlay:ClearAllPoints()
	overlay:SetAllPoints(button)
	overlay:SetFrameStrata("DIALOG")
	overlay:Show()
end

local function CreateOverlay()
	overlay = CreateFrame("Button", "ForeverPlusProcessButton", UIParent, "SecureActionButtonTemplate")
	overlay:RegisterForClicks("RightButtonUp")
	overlay:SetAttribute("type2", "spell")
	overlay:Hide()
	overlay:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(self.bag, self.slot)
		GameTooltip:Show()
	end)
	overlay:SetScript("OnLeave", function()
		GameTooltip_Hide()
		hovered = nil
		HideOverlay()
	end)
	-- After processing the item may be gone; hide until the mouse enters again.
	overlay:HookScript("PostClick", HideOverlay)
end

local hookedButtons = {}

local function HookBagButtons()
	for _, button in ipairs(BagButtons()) do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnEnter", function(self)
				hovered = self
				ShowOverlay(self)
			end)
			button:HookScript("OnLeave", function(self)
				if hovered == self and not (overlay and overlay:IsMouseOver()) then
					hovered = nil
				end
			end)
		end
	end
end

function Helpers:MODIFIER_STATE_CHANGED(_, key, down)
	if key ~= "LALT" and key ~= "RALT" then
		return
	end
	if down == 1 then
		HookBagButtons()
		ShowGlows()
		if hovered then
			ShowOverlay(hovered)
		end
	else
		HideGlows()
		HideOverlay()
	end
end

---------------------------------------------------------------------------
-- Button for lootable items (clams, opened lockboxes, bags of loot)
---------------------------------------------------------------------------
local openButton

local function FindLootable()
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.hasLoot then
				local locked = false
				for _, line in ipairs(TooltipLines(bag, slot)) do
					if line.leftText == LOCKED then
						locked = true
						break
					end
				end
				if not locked then
					return bag, slot, info
				end
			end
		end
	end
end

local function UpdateOpenButton()
	if InCombatLockdown() then
		ns.RunOutOfCombat(UpdateOpenButton)
		return
	end
	local button = openButton
	local bag, slot, info
	if Helpers.db.openButton then
		bag, slot, info = FindLootable()
	end
	if not bag then
		button:SetAttribute("item", nil)
		if Helpers.db.openButton and ns:IsEditModeActive() then
			button.icon:SetTexture(134400)
			button.Count:SetText("")
			button:Show()
		else
			button:Hide()
		end
		return
	end
	button.bag, button.slot = bag, slot
	button:SetAttribute("item", bag .. " " .. slot)
	button.icon:SetTexture(info.iconFileID)
	local count = C_Item.GetItemCount(info.itemID)
	button.Count:SetText(count > 1 and count or "")
	button:Show()
end

local function CreateOpenButton()
	local button = CreateFrame("Button", "ForeverPlusOpenButton", UIParent, "SecureActionButtonTemplate, ActionButtonTemplate")
	button:SetSize(36, 36)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")
	button:SetScript("OnEnter", function(self)
		if self.bag then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(self.bag, self.slot)
			GameTooltip_AddInstructionLine(GameTooltip, L.HELPERS_OPEN_HINT)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	openButton = button
	ns:RegisterEditFrame(button, "OpenButton", L.HELPERS_OPEN_BUTTON, { "CENTER", UIParent, "CENTER", 60, -180 }, UpdateOpenButton)
end

---------------------------------------------------------------------------
-- Fishing: a double right-click on the world casts Fishing. After the first
-- click the second one is bound to a secure button for a moment.
---------------------------------------------------------------------------
local FISHING = { 131474, 33095, 18248, 7732, 7731, 7620 }
local DOUBLE_CLICK = 0.4
local fishButton, lastRightClick, bindingSet = nil, 0, false

local function FishingSpell()
	for _, spellID in ipairs(FISHING) do
		if Known(spellID) then
			return spellID
		end
	end
end

local function ClearFishBinding()
	if bindingSet and not InCombatLockdown() then
		ClearOverrideBindings(fishButton)
		bindingSet = false
	end
end

local function CreateFishButton()
	fishButton = CreateFrame("Button", "ForeverPlusFishButton", UIParent, "SecureActionButtonTemplate")
	fishButton:RegisterForClicks("AnyUp", "AnyDown")
	fishButton:SetAttribute("type", "spell")
	-- Only the press casts, so the release of the first click does nothing.
	fishButton:SetAttribute("useOnKeyDown", true)
	fishButton:HookScript("PostClick", function()
		C_Timer.After(0, ClearFishBinding)
	end)
end

function Helpers:GLOBAL_MOUSE_DOWN(_, mouseButton)
	if mouseButton ~= "RightButton" or InCombatLockdown() or IsMounted() then
		return
	end
	local focus = GetMouseFoci()[1]
	if (focus and focus ~= WorldFrame) or UnitExists("mouseover") then
		return
	end
	local spellID = FishingSpell()
	if not spellID then
		return
	end
	local now = GetTime()
	if bindingSet or now - lastRightClick < DOUBLE_CLICK then
		return
	end
	lastRightClick = now
	fishButton:SetAttribute("spell", spellID)
	SetOverrideBindingClick(fishButton, true, "BUTTON2", "ForeverPlusFishButton", "LeftButton")
	bindingSet = true
	C_Timer.After(DOUBLE_CLICK, ClearFishBinding)
end

---------------------------------------------------------------------------
-- Known recipes greyed out in the bags and at merchants
---------------------------------------------------------------------------
local knownCache = {}

local function IsKnownRecipe(link)
	if not link then
		return false
	end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
	if not itemID or classID ~= Enum.ItemClass.Recipe then
		return false
	end
	local cached = knownCache[itemID]
	if cached ~= nil then
		return cached
	end
	local data = C_TooltipInfo.GetHyperlink(link)
	local lines = data and data.lines
	if not lines or #lines < 2 then
		return false -- item data not loaded yet; ask again later
	end
	local known = false
	for _, line in ipairs(lines) do
		if line.leftText == ITEM_SPELL_KNOWN then
			known = true
			break
		end
	end
	knownCache[itemID] = known
	return known
end

local function MarkBagButton(button)
	if not Helpers.db.knownRecipes then
		return
	end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if info and IsKnownRecipe(info.hyperlink) then
		SetItemButtonDesaturated(button, true)
	end
end

local function PostUpdateItems(frame)
	for _, button in frame:EnumerateValidItems() do
		MarkBagButton(button)
	end
end

local function MarkMerchant()
	if not Helpers.db.knownRecipes or not MerchantFrame or MerchantFrame.selectedTab ~= 1 then
		return
	end
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	for i = 1, perPage do
		local index = ((MerchantFrame.page or 1) - 1) * perPage + i
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		local name = _G["MerchantItem" .. i .. "Name"]
		if button and button:IsShown() and IsKnownRecipe(GetMerchantItemLink(index)) then
			SetItemButtonDesaturated(button, true)
			if name then
				name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
			end
		end
	end
end

function Helpers:ClearKnownCache()
	wipe(knownCache)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Helpers:Update()
	local db = self.db
	self:ToggleEvent("MODIFIER_STATE_CHANGED", db.process)
	if not db.process then
		HideGlows()
		ns.RunOutOfCombat(HideOverlay)
	end
	self:ToggleEvent("GLOBAL_MOUSE_DOWN", db.fishing)
	ns.RunOutOfCombat(ClearFishBinding)
	UpdateOpenButton()
end

function Helpers:OnLogin()
	CreateOverlay()
	CreateOpenButton()
	CreateFishButton()
	self:RegisterEvent("BAG_UPDATE_DELAYED", function()
		if self.db.openButton then
			UpdateOpenButton()
		end
	end)
	for _, event in ipairs({ "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED" }) do
		self:RegisterEvent(event, self.ClearKnownCache)
	end
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", PostUpdateItems)
		end
	end
	if MerchantFrame_UpdateMerchantInfo then
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", MarkMerchant)
	end
	self:Update()
end

function Helpers:OnOptionChanged()
	self:Update()
end

Helpers.options = {
	{ key = "process", type = "toggle", name = L.HELPERS_PROCESS, desc = L.HELPERS_PROCESS_DESC },
	{ key = "openButton", type = "toggle", name = L.HELPERS_OPEN_BUTTON, desc = L.HELPERS_OPEN_BUTTON_DESC },
	{ key = "fishing", type = "toggle", name = L.HELPERS_FISHING, desc = L.HELPERS_FISHING_DESC },
	{ key = "knownRecipes", type = "toggle", name = L.HELPERS_KNOWN_RECIPES, desc = L.HELPERS_KNOWN_RECIPES_DESC },
}

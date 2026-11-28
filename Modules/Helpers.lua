-- Helpers: process bag items with Alt + right-click (disenchant, pick lock),
-- a button that opens lootable items, fishing by double right-click
-- and greyed out recipes that are already known.
local _, ns = ...
local L = ns.L

local Helpers = ns:NewModule("Helpers", {
	title = L.HELPERS_TITLE,
	order = 4.8,
	defaults = {
		process = true,
		feedPet = true,
		openButton = true,
		openButtonMute = true,
		fishing = true,
		fishingEquip = true,
		fishingRestore = true,
		fishingHideUI = false,
		fishingSound = false,
		fishingBear = true,
		fishingBearSound = true,
		knownRecipes = true,
	},
	charDefaults = { fishingWeapons = {} },
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
local DISENCHANT, PICK_LOCK, FEED_PET = 13262, 1804, 6991
local COLORS = {
	[DISENCHANT] = { 0.75, 0.35, 1 },
	[PICK_LOCK] = { 1, 0.85, 0.1 },
	[FEED_PET] = { 0.35, 1, 0.35 },
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
	local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(info.hyperlink)
	if not quality then
		return
	end
	if Known(DISENCHANT) and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
		and quality >= Enum.ItemQuality.Uncommon and quality <= Enum.ItemQuality.Epic and not NO_DISENCHANT[equipLoc] then
		return DISENCHANT
	end
	if Known(PICK_LOCK) and IsOpenableLock(bag, slot) then
		return PICK_LOCK
	end
	-- Food the current pet eats (hunters; the game itself knows its diet).
	if Helpers.db.feedPet and Known(FEED_PET) and C_PetInfo and C_PetInfo.CanPetEatItem and UnitExists("pet")
		and not UnitIsDead("pet") and not InCombatLockdown() and info.itemID and C_PetInfo.CanPetEatItem(info.itemID) then
		return FEED_PET
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
		local size = ns.Number(button:GetWidth(), 37) * 1.8
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
	if InCombatLockdown() then
		ns.RunOutOfCombat(function()
			if not (hovered and IsAltKeyDown()) then
				HideOverlay()
			end
		end)
		return
	end
	if overlay and overlay:IsShown() then
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
-- Button for lootable items and quests started by bag items.
---------------------------------------------------------------------------
local openButton
local openButtonPending, openButtonMuteTimer, bagHasQuestItem
local OPEN_BUTTON_MUTE_DURATION = 30 * 60

function Helpers.QuestForItem(bag, slot)
	if not C_Container.GetContainerItemQuestInfo then return end
	local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
	local id = quest and ns.Number(quest.questID, 0) or 0
	return id > 0 and id or nil, quest and quest.isActive
end

local function FindLootable()
	local sawQuestItem = false
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local questID, active
			if info and not info.isLocked then
				questID, active = Helpers.QuestForItem(bag, slot)
				if questID then
					sawQuestItem = true
				end
			end
			local startsQuest = questID and not active and not C_QuestLog.IsOnQuest(questID)
				and not C_QuestLog.IsQuestFlaggedCompleted(questID)
			if info and not info.isLocked and (info.hasLoot or startsQuest) then
				local locked = false
				for _, line in ipairs(TooltipLines(bag, slot)) do
					if line.leftText == LOCKED then
						locked = true
						break
					end
				end
				if not locked then
					bagHasQuestItem = sawQuestItem
					return bag, slot, info
				end
			end
		end
	end
	bagHasQuestItem = sawQuestItem
end

local function UpdateOpenButton()
	openButtonPending = nil
	if InCombatLockdown() then
		return
	end
	local button = openButton
	local muteAction = Helpers.db.openButtonMute and "" or nil
	if button:GetAttribute("*type3") ~= muteAction then
		button:SetAttribute("*type3", muteAction)
	end
	local deadline = Helpers.cdb.openButtonMutedUntil
	local remaining = Helpers.db.openButtonMute and deadline and deadline - GetServerTime() or 0
	if remaining > 0 then
		if not openButtonMuteTimer then
			openButtonMuteTimer = ns.NewTimer("Helpers: open button mute", remaining, function()
				openButtonMuteTimer = nil
				UpdateOpenButton()
			end)
		end
	else
		Helpers.cdb.openButtonMutedUntil = nil
		if openButtonMuteTimer then
			openButtonMuteTimer:Cancel()
			openButtonMuteTimer = nil
		end
	end
	local bag, slot, info
	if Helpers.db.openButton and remaining <= 0 then
		bag, slot, info = FindLootable()
	else
		bagHasQuestItem = false
	end
	if not bag then
		local editMode = Helpers.db.openButton and ns:IsEditModeActive() or false
		if button.bag ~= nil or button.slot ~= nil then
			button.bag, button.slot, button.itemID, button.shownCount = nil, nil, nil, nil
			button:SetAttribute("macrotext", nil)
		end
		if editMode then
			ns.FrameActionButton(button)
			button.icon:SetTexture(134400)
			button.Count:SetText("")
			button:Show()
		elseif button:IsShown() then
			button:Hide()
		end
		return
	end
	local count = C_Item.GetItemCount(info.itemID)
	if button.bag == bag and button.slot == slot and button.itemID == info.itemID
		and button.shownCount == count and button:IsShown() then
		return
	end
	-- Same as the quest item button: refresh the frame and hide template art.
	ns.FrameActionButton(button)
	button.bag, button.slot, button.itemID, button.shownCount = bag, slot, info.itemID, count
	button:SetAttribute("macrotext", "/use " .. bag .. " " .. slot)
	button.icon:SetTexture(info.iconFileID)
	button.Count:SetText(count > 1 and count or "")
	button:Show()
end

local function QueueOpenButton()
	if not openButtonPending then
		openButtonPending = true
		ns.After("Helpers: open button", 0.05, UpdateOpenButton)
	end
end

local function CreateOpenButton()
	-- Keep combat visibility separate from whether the bags contain an item to open.
	local visibility = CreateFrame("Frame", nil, UIParent)
	RegisterStateDriver(visibility, "visibility", "[combat] hide; show")
	local button = CreateFrame("Button", "ForeverPlusOpenButton", visibility, "ActionButtonTemplate, SecureActionButtonTemplate")
	button:SetSize(36, 36)
	button:RegisterForClicks("AnyUp", "AnyDown")
	-- Use /use bag slot via macrotext instead of type="item": Blizzard's SECURE_ACTIONS.item
	-- passes nil from SecureCmdItemParse into C_Item.IsEquippableItem when a slot empties.
	button:SetAttribute("type", "macro")
	button:HookScript("PreClick", ns.Measured("Helpers: open button verify", function(self, mouseButton)
		if mouseButton == "MiddleButton" or InCombatLockdown() or not self.bag then
			return
		end
		local info = C_Container.GetContainerItemInfo(self.bag, self.slot)
		if not info or info.itemID ~= self.itemID or info.isLocked then
			UpdateOpenButton()
		end
	end))
	button:HookScript("PostClick", ns.Measured("Helpers: open button middle click", function(self, mouseButton, down)
		if mouseButton == "MiddleButton" and not down and self.bag and Helpers.db.openButtonMute and not InCombatLockdown() then
			Helpers.cdb.openButtonMutedUntil = GetServerTime() + OPEN_BUTTON_MUTE_DURATION
			GameTooltip:Hide()
			UpdateOpenButton()
		end
	end))
	button:SetScript("OnEnter", ns.Measured("Helpers: open button tooltip", function(self)
		if self.bag then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(self.bag, self.slot)
			GameTooltip_AddInstructionLine(GameTooltip, L.HELPERS_OPEN_HINT)
			if Helpers.db.openButtonMute then
				GameTooltip:AddLine(L.HELPERS_OPEN_MUTE_HINT, 0.7, 0.7, 0.7)
			end
			GameTooltip:Show()
		end
	end))
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	ns.FrameActionButton(button)
	openButton = button
	ns:RegisterEditFrame(button, "OpenButton", L.HELPERS_OPEN_BUTTON, { "CENTER", UIParent, "CENTER", 60, -180 }, UpdateOpenButton)
end

---------------------------------------------------------------------------
-- Angler mode activation Nat Pagle flash and sounds
---------------------------------------------------------------------------
local BEAR_ART = [[Interface\AddOns\ForeverPlus\Media\AnglerNatPagle.tga]]
local BEAR_MAX_ALPHA = 0.50
local BEAR_FADE_IN = 0.22
local BEAR_HOLD = 0.50
local BEAR_SHRINK = 0.88
local BEAR_TOTAL = BEAR_FADE_IN + BEAR_HOLD + BEAR_SHRINK
local BEAR_START_SCALE = 0.94
local BEAR_MIN_SCALE = 0.04
-- Verified Forever 1.60.1.71037 fishing cast and bobber splash FileDataIDs.
local BEAR_CAST_SOUNDS = { 3610663, 3610665 }
local BEAR_SPLASH_SOUNDS = { 569285, 568970, 569044 }
local BEAR_SPLASH_DELAY = 0.35
local bearFrame, bearElapsed, bearBaseSize, lastFishing
local bearSoundGen, bearCastIndex, bearSplashIndex = 0, 0, 0
local bearCastHandle, bearSplashHandle

local function StopAnglerBearSounds()
	bearSoundGen = bearSoundGen + 1
	if bearCastHandle then
		if StopSound then
			StopSound(bearCastHandle)
		end
		bearCastHandle = nil
	end
	if bearSplashHandle then
		if StopSound then
			StopSound(bearSplashHandle)
		end
		bearSplashHandle = nil
	end
end

local function PlayAnglerBearSounds()
	StopAnglerBearSounds()
	if not (Helpers.db and Helpers.db.fishingBearSound and PlaySoundFile) then
		return
	end
	local gen = bearSoundGen
	bearCastIndex = (bearCastIndex % #BEAR_CAST_SOUNDS) + 1
	local ok, handle = PlaySoundFile(BEAR_CAST_SOUNDS[bearCastIndex], "SFX")
	if ok and handle then
		bearCastHandle = handle
	end
	ns.After("Helpers: angler splash", BEAR_SPLASH_DELAY, function()
		if gen ~= bearSoundGen or not (Helpers.db and Helpers.db.fishingBearSound and PlaySoundFile) then
			return
		end
		bearSplashIndex = (bearSplashIndex % #BEAR_SPLASH_SOUNDS) + 1
		local splashOk, splashHandle = PlaySoundFile(BEAR_SPLASH_SOUNDS[bearSplashIndex], "SFX")
		if splashOk and splashHandle then
			bearSplashHandle = splashHandle
		end
	end)
end

local function BearSize()
	local width = ns.Number(UIParent and UIParent:GetWidth(), 1280)
	local height = ns.Number(UIParent and UIParent:GetHeight(), 720)
	local size = math.min(width, height) * 0.96
	return size > 0 and size or 720
end

local function ApplyAnglerBearFrame(t)
	local alpha, scale
	if t < BEAR_FADE_IN then
		local p = t / BEAR_FADE_IN
		local eased = 1 - (1 - p) * (1 - p)
		alpha = BEAR_MAX_ALPHA * eased
		scale = BEAR_START_SCALE + (1 - BEAR_START_SCALE) * eased
	elseif t < BEAR_FADE_IN + BEAR_HOLD then
		alpha = BEAR_MAX_ALPHA
		scale = 1
	else
		local p = (t - BEAR_FADE_IN - BEAR_HOLD) / BEAR_SHRINK
		if p > 1 then
			p = 1
		end
		local eased = p * p * (0.4 + 0.6 * p)
		scale = 1 - (1 - BEAR_MIN_SCALE) * eased
		alpha = BEAR_MAX_ALPHA * (1 - p * p)
	end
	local size = bearBaseSize * scale
	bearFrame:SetSize(size, size)
	bearFrame:SetAlpha(alpha)
end

local function HideAnglerBear()
	bearElapsed = nil
	if bearFrame then
		ns.SetUpdate(bearFrame, "Helpers: angler bear", nil)
		bearFrame:SetAlpha(0)
		if bearFrame:IsShown() then
			bearFrame:Hide()
		end
	end
end

local function StopAnglerBear()
	StopAnglerBearSounds()
	HideAnglerBear()
end

local function UpdateAnglerBear(_, delta)
	if not bearElapsed then
		HideAnglerBear()
		return
	end
	bearElapsed = bearElapsed + (delta or 0)
	if bearElapsed >= BEAR_TOTAL then
		-- Let the cast and water-splash tail decay naturally instead of chopping it off.
		HideAnglerBear()
		return
	end
	ApplyAnglerBearFrame(bearElapsed)
end

local function EnsureAnglerBearFrame()
	if bearFrame then
		return bearFrame
	end
	local frame = CreateFrame("Frame", "ForeverPlusAnglerBear", UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(100)
	frame:EnableMouse(false)
	if frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame.art = frame:CreateTexture(nil, "OVERLAY")
	frame.art:SetAllPoints()
	frame.art:SetTexture(BEAR_ART)
	frame:SetScript("OnHide", ns.Measured("Helpers: angler bear hide", HideAnglerBear))
	frame:Hide()
	bearFrame = frame
	return frame
end

local function ShowAnglerBear()
	if ns.PortraitModes and ns.PortraitModes.StopFlash then
		ns.PortraitModes.StopFlash()
	end
	local frame = EnsureAnglerBearFrame()
	bearBaseSize = BearSize()
	bearElapsed = 0
	ApplyAnglerBearFrame(0)
	frame:Show()
	ns.SetUpdate(frame, "Helpers: angler bear", UpdateAnglerBear)
	PlayAnglerBearSounds()
end

function Helpers.StopBearFlash()
	StopAnglerBear()
end

function Helpers.PreviewBear()
	ShowAnglerBear()
end

---------------------------------------------------------------------------
-- Only a short, still right-click on the world arms the next click.
-- The secure button equips a pole, casts Fishing or restores the previous weapons.
---------------------------------------------------------------------------
local FISHING = { 18248, 7732, 7731, 7620 }
local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND = INVSLOT_OFFHAND or 17
local DOUBLE_CLICK = 0.30
local CLICK_TIME, CLICK_MOVE = 0.22, 6
local fishButton, bindingTimer, mouseTracker
local pressTime, pressX, pressY, pressShift
local mouseMovement
local weaponsTimer

local function FishingSpell()
	for _, spellID in ipairs(FISHING) do
		if Known(spellID) then
			return spellID
		end
	end
end

local function IsFishingChannel()
	local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
	if ns.Secret(spellID) or ns.Secret(name) then
		return false
	end
	for _, id in ipairs(FISHING) do
		if spellID == id then
			return true
		end
	end
	-- Some clients report the fishing channel's spell, not the learned rank.
	return name ~= nil and name == C_Spell.GetSpellName(7620)
end

local FISHING_SOUND_CVARS = { "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }
local fishingVolumes, fishingHidUI

local function SetFishingSound(active)
	if active and not fishingVolumes then
		fishingVolumes = {}
		for _, key in ipairs(FISHING_SOUND_CVARS) do
			local original = GetCVar(key)
			local volume = tonumber(original)
			if volume then
				local wanted = key == "Sound_SFXVolume" and math.max(0.65, volume) or volume * 0.25
				if wanted ~= volume then
					SetCVar(key, tostring(wanted))
					fishingVolumes[key] = { original = original, applied = GetCVar(key) }
				end
			end
		end
	elseif not active and fishingVolumes then
		for key, state in pairs(fishingVolumes) do
			if GetCVar(key) == state.applied then
				SetCVar(key, state.original)
			end
		end
		fishingVolumes = nil
	end
end

local function SetFishingPresentation(active)
	local hide = active and Helpers.db.fishingHideUI
	if hide and not fishingHidUI and UIParent:IsShown() then
		fishingHidUI = true
		SetUIVisibility(false)
	elseif not hide and fishingHidUI then
		fishingHidUI = nil
		if not UIParent:IsShown() then
			SetUIVisibility(true)
		end
	end
	SetFishingSound(active and Helpers.db.fishingSound)
end

local function RefreshFishingPresentation()
	local db = Helpers.db
	SetFishingPresentation(db.fishing and (db.fishingHideUI or db.fishingSound)
		and not InCombatLockdown() and not UnitIsDeadOrGhost("player") and IsFishingChannel())
end

local function FishingChannelChanged(_, _, unit)
	if not ns.Secret(unit) and unit == "player" then
		-- Let the game update the channel before reading it, including after a recast.
		ns.After("Helpers: refresh fishing presentation", 0, RefreshFishingPresentation)
	end
end

local function EndFishingPresentation()
	SetFishingPresentation(false)
end

local poleItems = {}
local cachedPole -- nil = dirty, false = none in bags, { itemID, bag, slot } = cached usable pole

local function IsFishingPole(itemID)
	if not itemID then
		return false
	end
	local cached = poleItems[itemID]
	if cached ~= nil then
		return cached
	end
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	local result = classID == Enum.ItemClass.Weapon and subClassID == (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20)
	poleItems[itemID] = result
	return result
end

local function HasFishingPole()
	return IsFishingPole(GetInventoryItemID("player", MAIN_HAND))
end

ns.HasFishingPole = HasFishingPole

local function CanRestoreOffHand(weapons)
	return weapons.off and C_Item.GetItemCount(weapons.off) >= (weapons.off == weapons.main and 2 or 1)
end

-- Keep the pre-fishing set even after the pole is removed or another weapon is equipped.
local recentMain, recentOff
local function RememberFishingWeapons()
	if not (Helpers.db.fishing and Helpers.db.fishingRestore) then
		recentMain, recentOff = nil, nil
		return
	end
	local main = GetInventoryItemID("player", MAIN_HAND)
	local off = GetInventoryItemID("player", OFF_HAND)
	if ns.Secret(main) or ns.Secret(off) or not main then
		return
	end
	local weapons = Helpers.cdb.fishingWeapons
	if IsFishingPole(main) then
		if recentMain then
			weapons.main, weapons.off = recentMain, recentOff
			recentMain, recentOff = nil, nil
		end
		weapons.pending = weapons.main and true or nil
	else
		recentMain, recentOff = main, off
		if not weapons.pending or (main == weapons.main and (off == weapons.off or not CanRestoreOffHand(weapons))) then
			weapons.main, weapons.off, weapons.pending = main, off, nil
		end
	end
end

function Helpers:PLAYER_EQUIPMENT_CHANGED(_, slot)
	if slot ~= MAIN_HAND and slot ~= OFF_HAND then
		return
	end
	cachedPole = nil
	if weaponsTimer then
		weaponsTimer:Cancel()
		weaponsTimer = nil
	end
	local main = GetInventoryItemID("player", MAIN_HAND)
	local off = GetInventoryItemID("player", OFF_HAND)
	if ns.Secret(main) or ns.Secret(off) then
		return
	end
	-- An empty off hand can be the first half of equipping a two-handed pole.
	if slot == MAIN_HAND or off or IsFishingPole(main) then
		RememberFishingWeapons()
		return
	end
	weaponsTimer = ns.NewTimer("Helpers: remember fishing weapons", 0.5, function()
		weaponsTimer = nil
		RememberFishingWeapons()
	end)
end

local function EquipLine(slot, itemID, modifier)
	return ("/equipslot [@mouseover,noexists,nocombat,nomounted,%s] %d item:%d"):format(modifier, slot, itemID)
end

local function RestoreWeaponsMacro(main, modifier)
	local weapons = Helpers.cdb.fishingWeapons
	local wantedMain, wantedOff = weapons.main, weapons.off
	if not wantedMain or (weaponsTimer and not weapons.pending) then
		return
	end
	local off = GetInventoryItemID("player", OFF_HAND)
	if ns.Secret(off) then
		return
	end
	local text
	if main ~= wantedMain then
		if C_Item.GetItemCount(wantedMain) == 0 then
			return
		end
		text = EquipLine(MAIN_HAND, wantedMain, modifier)
	end
	if off ~= wantedOff and CanRestoreOffHand(weapons) then
		local line = EquipLine(OFF_HAND, wantedOff, modifier)
		text = text and (text .. "\n" .. line) or line
	end
	return text
end

local function FindFishingPole()
	if cachedPole == false then
		return nil
	end
	if cachedPole then
		local info = C_Container.GetContainerItemInfo(cachedPole.bag, cachedPole.slot)
		if info and info.itemID == cachedPole.itemID and not info.isLocked then
			return cachedPole.itemID
		end
		cachedPole = nil
	end
	local sawLocked = false
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and IsFishingPole(info.itemID) then
				if info.isLocked then
					sawLocked = true
				else
					local usable = true
					for _, line in ipairs(TooltipLines(bag, slot)) do
						if IsRed(line.leftColor) then
							usable = false
							break
						end
					end
					if usable then
						cachedPole = { itemID = info.itemID, bag = bag, slot = slot }
						return info.itemID
					end
				end
			end
		end
	end
	if not sawLocked then
		cachedPole = false
	end
end

local function ClearFishBinding()
	if not bindingTimer then
		return
	end
	if InCombatLockdown() then
		ns.RunOutOfCombat(ClearFishBinding) -- the binding must not stay after the fight
		return
	end
	ClearOverrideBindings(fishButton)
	bindingTimer:Cancel()
	bindingTimer = nil
	ns.SetUpdate(mouseTracker, "Helpers: watch right click", nil)
end

local function TrackFishMouse()
	local dx, dy = GetCursorDelta()
	mouseMovement = mouseMovement + math.abs(dx) + math.abs(dy)
	if mouseMovement > CLICK_MOVE or (pressTime and GetTime() - pressTime > CLICK_TIME) then
		pressTime = nil
		ns.SetUpdate(mouseTracker, "Helpers: watch right click", nil)
		ClearFishBinding()
	end
end

local function CreateFishButton()
	mouseTracker = CreateFrame("Frame", "ForeverPlusFishingMotion", UIParent)
	fishButton = CreateFrame("Button", "ForeverPlusFishButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
	fishButton:RegisterForClicks("AnyUp", "AnyDown")
	-- Remove the binding even if combat starts between the two clicks.
	fishButton:SetAttribute("_onstate-fishingblocked", [=[
		if newstate == "1" then
			self:ClearBindings()
		end
	]=])
	RegisterStateDriver(fishButton, "fishingblocked", "[combat][mounted] 1; 0")
	fishButton:HookScript("PostClick", ns.Measured("Helpers: fish click", function(_, _, down)
		-- Keep the binding until a release can run the action.
		if down then
			return
		end
		local timer = bindingTimer
		ns.After("Helpers: ClearFishBinding", 0, function()
			if timer == bindingTimer then
				ClearFishBinding()
			end
		end)
	end))
end

local function CanArmFishing()
	if not Helpers.db.fishing or InCombatLockdown() or IsMounted() then
		return
	end
	local mouseover = UnitExists("mouseover")
	if ns.Secret(mouseover) or mouseover then
		return
	end
	local focus = GetMouseFoci()[1]
	return not focus or focus == WorldFrame
end

function Helpers:GLOBAL_MOUSE_DOWN(_, mouseButton)
	if mouseButton == "RightButton" and not bindingTimer and CanArmFishing() then
		pressTime = GetTime()
		pressX, pressY = GetCursorPosition()
		pressShift = IsShiftKeyDown()
		mouseMovement = 0
		ns.SetUpdate(mouseTracker, "Helpers: watch right click", TrackFishMouse)
	end
end

local function SetFishAttribute(key, value)
	if not fishButton.GetAttribute or fishButton:GetAttribute(key) ~= value then
		fishButton:SetAttribute(key, value)
	end
end

function Helpers:GLOBAL_MOUSE_UP(_, mouseButton)
	if mouseButton ~= "RightButton" or not pressTime or bindingTimer then
		return
	end
	local x, y = GetCursorPosition()
	local dx, dy = GetCursorDelta()
	local short = GetTime() - pressTime <= CLICK_TIME and math.abs(x - pressX) + math.abs(y - pressY) <= CLICK_MOVE
		and math.abs(dx) + math.abs(dy) <= CLICK_MOVE
	local shift = pressShift
	pressTime = nil
	ns.SetUpdate(mouseTracker, "Helpers: watch right click", nil)
	if not short or shift ~= IsShiftKeyDown() or not CanArmFishing() then
		return
	end
	-- After the release has been handled by the game.
	ns.After("Helpers: GLOBAL_MOUSE_UP (timer)", 0, function()
		if bindingTimer or IsMouseButtonDown("RightButton") or shift ~= IsShiftKeyDown() or not CanArmFishing() then
			return
		end
		if IsAltKeyDown() or IsControlKeyDown() then
			return
		end
		local main = GetInventoryItemID("player", MAIN_HAND)
		if ns.Secret(main) then
			return
		end
		local hasPole = IsFishingPole(main)
		if hasPole and not shift then
			local spellID = FishingSpell()
			if not spellID or IsFishingChannel() then
				return
			end
			SetFishAttribute("type", "spell")
			SetFishAttribute("spell", spellID)
		else
			if GetCursorInfo() then
				return
			end
			local macro
			if hasPole then
				if Helpers.db.fishingRestore then
					macro = RestoreWeaponsMacro(main, "mod:shift")
				end
			elseif shift and Helpers.db.fishingEquip and FishingSpell() then
				local pole = FindFishingPole()
				if pole then
					RememberFishingWeapons()
					macro = EquipLine(MAIN_HAND, pole, "mod:shift")
				end
			elseif not shift and Helpers.db.fishingRestore then
				macro = RestoreWeaponsMacro(main, "nomod")
			end
			if not macro then
				return
			end
			SetFishAttribute("type", "macro")
			SetFishAttribute("macrotext", macro)
		end
		SetFishAttribute("useOnKeyDown", false)
		SetOverrideBindingClick(fishButton, true, shift and "SHIFT-BUTTON2" or "BUTTON2", "ForeverPlusFishButton", "LeftButton")
		bindingTimer = ns.NewTimer("Helpers: ClearFishBinding", DOUBLE_CLICK, ClearFishBinding)
		mouseMovement = 0
		ns.SetUpdate(mouseTracker, "Helpers: watch right click", TrackFishMouse)
	end)
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
	self:ToggleEvent("GLOBAL_MOUSE_UP", db.fishing)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", db.fishing and db.fishingRestore)
	local presentFishing = db.fishing and (db.fishingHideUI or db.fishingSound)
	self:ToggleEvent("UNIT_SPELLCAST_CHANNEL_START", presentFishing, FishingChannelChanged)
	self:ToggleEvent("UNIT_SPELLCAST_CHANNEL_STOP", presentFishing, FishingChannelChanged)
	self:ToggleEvent("PLAYER_REGEN_DISABLED", presentFishing, EndFishingPresentation)
	self:ToggleEvent("PLAYER_DEAD", presentFishing, EndFishingPresentation)
	self:ToggleEvent("PLAYER_LEAVING_WORLD", presentFishing, EndFishingPresentation)
	self:ToggleEvent("PLAYER_LOGOUT", presentFishing, EndFishingPresentation)
	pressTime = nil
	if mouseTracker then
		ns.SetUpdate(mouseTracker, "Helpers: watch right click", nil)
	end
	ns.RunOutOfCombat(ClearFishBinding)
	UpdateOpenButton()
	RefreshFishingPresentation()
	lastFishing = db.fishing and true or false
end

function Helpers:OnLogin()
	CreateOverlay()
	CreateOpenButton()
	CreateFishButton()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateOpenButton)
	self:RegisterEvent("BAG_UPDATE_DELAYED", function()
		cachedPole = nil
		if self.db.openButton then
			QueueOpenButton()
		end
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function()
		cachedPole = nil
	end)
	for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
		self:RegisterEvent(event, function()
			if self.db.openButton and bagHasQuestItem ~= false then
				QueueOpenButton()
			end
		end)
	end
	for _, event in ipairs({ "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE", "SKILL_LINES_CHANGED" }) do
		self:RegisterEvent(event, function()
			cachedPole = nil
			self:ClearKnownCache()
		end)
	end
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", ns.Measured("Helpers: bag update", PostUpdateItems))
		end
	end
	if MerchantFrame_UpdateMerchantInfo then
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", ns.Measured("Helpers: merchant recipes", MarkMerchant))
	end
	self:Update()
	RememberFishingWeapons()
end

function Helpers:OnOptionChanged(key)
	if key == "openButtonMute" and not self.db.openButtonMute then
		self.cdb.openButtonMutedUntil = nil
	end
	local playBear = key == "fishing" and self.db.fishing and lastFishing == false and self.db.fishingBear
	if (key == "fishing" and not self.db.fishing) or (key == "fishingBear" and not self.db.fishingBear) then
		StopAnglerBear()
	elseif key == "fishingBearSound" and not self.db.fishingBearSound then
		StopAnglerBearSounds()
	end
	self:Update()
	if key == "fishing" or key == "fishingRestore" then
		RememberFishingWeapons()
	end
	if playBear then
		ShowAnglerBear()
	end
end

Helpers.options = {
	{ key = "process", type = "toggle", name = L.HELPERS_PROCESS, desc = L.HELPERS_PROCESS_DESC },
	{ key = "feedPet", type = "toggle", name = L.HELPERS_FEED_PET, desc = L.HELPERS_FEED_PET_DESC, parent = "process" },
	{ key = "openButton", type = "toggle", name = L.HELPERS_OPEN_BUTTON, desc = L.HELPERS_OPEN_BUTTON_DESC },
	{ key = "openButtonMute", type = "toggle", name = L.BUFFS_MUTE, desc = L.HELPERS_OPEN_MUTE_DESC, parent = "openButton" },
	{ key = "knownRecipes", type = "toggle", name = L.HELPERS_KNOWN_RECIPES, desc = L.HELPERS_KNOWN_RECIPES_DESC },
	{ type = "header", name = L.HELPERS_FISHING_MODE },
	{ key = "fishing", type = "toggle", name = L.HELPERS_FISHING, desc = L.HELPERS_FISHING_DESC },
	{ key = "fishingEquip", type = "toggle", name = L.HELPERS_FISHING_EQUIP, desc = L.HELPERS_FISHING_EQUIP_DESC, parent = "fishing" },
	{ key = "fishingRestore", type = "toggle", name = L.HELPERS_FISHING_RESTORE, desc = L.HELPERS_FISHING_RESTORE_DESC, parent = "fishing" },
	{ key = "fishingHideUI", type = "toggle", name = L.HELPERS_FISHING_HIDE_UI, desc = L.HELPERS_FISHING_HIDE_UI_DESC, parent = "fishing", new = true },
	{ key = "fishingSound", type = "toggle", name = L.HELPERS_FISHING_SOUND, desc = L.HELPERS_FISHING_SOUND_DESC, parent = "fishing", new = true },
	{ key = "fishingBear", type = "toggle", name = L.HELPERS_FISHING_BEAR, desc = L.HELPERS_FISHING_BEAR_DESC, parent = "fishing", new = true },
	{ key = "fishingBearSound", type = "toggle", name = L.HELPERS_FISHING_BEAR_SOUND, desc = L.HELPERS_FISHING_BEAR_SOUND_DESC,
		parent = "fishingBear", new = true },
	{ type = "button", name = L.HELPERS_FISHING_BEAR_PREVIEW, text = L.HELPERS_FISHING_BEAR_PREVIEW_BUTTON,
		desc = L.HELPERS_FISHING_BEAR_PREVIEW_DESC, func = Helpers.PreviewBear },
}

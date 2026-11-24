-- Hide the interface after a quiet minute; combat and abilities bring it back.
local _, ns = ...
local L = ns.L

local Wanderlust = ns:NewModule("Wanderlust", {
	title = L.WANDERLUST_TITLE,
	defaults = { enabled = false, showOnTarget = false, showProfessions = false, minimapMouseover = true,
		hoverText = true, showChat = true, showBags = true, showBubbles = true, hideTeleports = true },
})

local QUIET_SECONDS = 60
local timer, activityTicker, hidUI, hooked, restoring, blocked
local teleport
local MIN_TELEPORT_CAST_MS = 2000
local TELEPORT_TRANSITION = 0.5
local PEEK_INTERVAL = 0.1
local MINIMAP_LEAVE_GRACE = 0.25
local BAG_KEY_PEEK_SECONDS = 3
local peek, peekArea, peekKeepArea, bagsBarArea, bagKeyUntil, bagJustClosed, peekDriver
local lastMinimapHover
local UpdateHiddenUI, CheckPeek, SyncPeek
local peekDriverShown

local SetInterfaceVisibility = ns.Measured("Wanderlust: SetUIVisibility", function(visible)
	SetUIVisibility(visible)
end)

local function DialogModule()
	return ns:GetModule("Dialog")
end

local function DialogActive()
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	return dialog and dialog.IsBubbleActive and dialog.IsBubbleActive() or false
end

local function DialogOwnsWindow(frame)
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	return dialog and dialog.OwnsWindow and dialog.OwnsWindow(frame) or false
end

local function DialogHandlesEvent(event, interactionType)
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	return dialog and dialog.HandlesEvent and dialog.HandlesEvent(event, interactionType) or false
end

local function UpdateHiddenChat()
	local visible = hidUI and Wanderlust.db.enabled and Wanderlust.db.showChat or false
	ns:GetModule("Chat").SetWanderlustVisible(visible, visible and (peek and peek.alpha or UIParent:GetAlpha()))
end

-- Minimap, bag bar, open bags and the dialog bubble while Wanderlust hides the interface.
-- SetUIVisibility(false) stops drawing the minimap and hides nameplates/tooltips, and blocks Blizzard's
-- bag toggles. Instead the interface comes back see-through (UIParent alpha 0) while any of those are active;
-- only the active frames ignore that alpha.
local function FrameCursorRect(frame)
	if not (frame and frame.GetRect and frame.GetEffectiveScale) then return nil end
	local left, bottom, width, height = frame:GetRect()
	local scale = ns.Number(frame:GetEffectiveScale())
	left, bottom, width, height = ns.Number(left), ns.Number(bottom), ns.Number(width), ns.Number(height)
	return left and bottom and width and height and scale
		and { left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale } or nil
end

local function SavePeekArea()
	-- In cursor coordinates, read while the interface is still shown.
	peekArea = FrameCursorRect(Minimap)
	local clusterArea = FrameCursorRect(MinimapCluster)
	if peekArea and clusterArea then
		-- Keep the preview open across the cluster rim (clock, buttons, FPS/MS) to avoid repeated SetUIVisibility stalls.
		peekKeepArea = {
			math.min(peekArea[1], clusterArea[1]),
			math.min(peekArea[2], clusterArea[2]),
			math.max(peekArea[3], clusterArea[3]),
			math.max(peekArea[4], clusterArea[4]),
		}
	else
		peekKeepArea = peekArea
	end
	bagsBarArea = FrameCursorRect(BagsBar)
end

local function CursorInArea(area)
	if not area then return false end
	local x, y = GetCursorPosition()
	return x >= area[1] and x <= area[3] and y >= area[2] and y <= area[4]
end

local function CursorOverMinimap()
	if not Wanderlust.db.minimapMouseover or not MinimapCluster or MinimapCluster:IsForbidden() then
		lastMinimapHover = nil
		return false
	end
	if CursorInArea(peek and peekKeepArea or peekArea) then
		lastMinimapHover = GetTime()
		return true
	end
	-- A short excursion outside the rim should not hide and re-show all of UIParent.
	return peek and lastMinimapHover and GetTime() - lastMinimapHover < MINIMAP_LEAVE_GRACE
end

local function CursorOverBagsBar()
	return Wanderlust.db.showBags
		and BagsBar and not BagsBar:IsForbidden()
		and CursorInArea(bagsBarArea) or false
end

local function CanIgnoreParentAlpha(frame)
	return frame and (not frame.IsForbidden or not frame:IsForbidden())
		and frame.IsIgnoringParentAlpha and frame.SetIgnoreParentAlpha
end

local function AddPeekFrame(list, frame)
	if CanIgnoreParentAlpha(frame) then list[frame] = true end
end

local function AddTooltipFrames(list)
	AddPeekFrame(list, GameTooltip)
	AddPeekFrame(list, ShoppingTooltip1)
	AddPeekFrame(list, ShoppingTooltip2)
end

local function RestoreIgnored(ignored)
	ns.RunOutOfCombat(function()
		for frame, orig in pairs(ignored) do
			if not (peek and peek.ignored[frame]) and CanIgnoreParentAlpha(frame) then
				frame:SetIgnoreParentAlpha(orig)
			end
		end
	end)
end

local function EndPeek(hide)
	bagKeyUntil = nil
	lastMinimapHover = nil
	if not peek then return end
	local saved = peek
	peek = nil
	-- Hide first, then restore the alpha: nothing flashes.
	if hide and UIParent:IsShown() then SetInterfaceVisibility(false) end
	UIParent:SetAlpha(saved.alpha)
	RestoreIgnored(saved.ignored)
end

local WINDOW_NAMES = {
	"GossipFrame", "QuestFrame", "MerchantFrame", "ClassTrainerFrame", "WorldMapFrame", "SettingsPanel",
	"GameMenuFrame", "PlayerSpellsFrame", "ProfessionsFrame", "AuctionHouseFrame", "BankFrame", "GuildBankFrame",
	"MailFrame", "LootFrame", "TradeFrame", "TaxiFrame", "FlightMapFrame", "ForeverPlusReadable",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}

local function WindowShown(frame)
	return frame and (not frame.IsForbidden or not frame:IsForbidden()) and frame:IsShown()
end

-- Not IsAnyBagOpen(): it builds Blizzard's bag frame list on first use. Called from here (tainted, e.g. at login),
-- that list stays tainted; every later bag check, also in the bank's OnShow, then runs tainted and the bank
-- tab purchase is blocked (ADDON_ACTION_FORBIDDEN PurchaseBankTab). Reading the frames themselves writes nothing.
local function AnyBagOpen()
	if WindowShown(ContainerFrameCombinedBags) then return true end
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	if frames then
		for _, frame in ipairs(frames) do
			if WindowShown(frame) then return true end
		end
	end
	return false
end

-- Reuse the frame set instead of allocating a new table every 100 ms.
local desiredPeekFrames = {}
local function DesiredPeekFrames()
	wipe(desiredPeekFrames)
	local frames = desiredPeekFrames
	if not (hidUI and Wanderlust.db.enabled) then return frames end
	if bagKeyUntil and ns.Number(GetTime(), 0) >= bagKeyUntil then
		bagKeyUntil = nil
	end
	local overMinimap = CursorOverMinimap()
	local bagsOpen = Wanderlust.db.showBags and AnyBagOpen() or false
	if bagsOpen then bagKeyUntil = nil end
	local showBagsBar = Wanderlust.db.showBags and (bagsOpen or CursorOverBagsBar() or bagKeyUntil ~= nil) or false
	local bubbleActive = DialogActive()
	if overMinimap then
		AddPeekFrame(frames, MinimapCluster)
		AddPeekFrame(frames, GameTooltip)
	end
	if showBagsBar then
		AddPeekFrame(frames, BagsBar)
		AddPeekFrame(frames, GameTooltip)
	end
	if bagsOpen then
		AddPeekFrame(frames, ContainerFrameCombinedBags)
		AddPeekFrame(frames, ContainerFrameContainer)
		local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
		if list then
			for _, frame in ipairs(list) do
				if WindowShown(frame) then AddPeekFrame(frames, frame) end
			end
		end
		AddPeekFrame(frames, StackSplitFrame)
		AddTooltipFrames(frames)
	end
	if bubbleActive then
		local dialog = DialogModule()
		AddPeekFrame(frames, dialog and dialog.GetBubbleFrame and dialog.GetBubbleFrame())
		AddTooltipFrames(frames)
	end
	return frames
end

local function UpdatePeekDriver()
	local hidden = hidUI and Wanderlust.db.enabled or false
	local watchMinimap = hidden and Wanderlust.db.minimapMouseover
		and MinimapCluster and not MinimapCluster:IsForbidden() or false
	local watchBags = hidden and Wanderlust.db.showBags
		and BagsBar and not BagsBar:IsForbidden() or false
	local active = watchMinimap or watchBags or (hidden and peek ~= nil) or false
	if active and not peekDriver then
		peekDriver = CreateFrame("Frame")
		local elapsedSinceCheck = 0
		ns.SetUpdate(peekDriver, "Wanderlust: minimap mouseover", function(_, elapsed)
			elapsedSinceCheck = elapsedSinceCheck + elapsed
			if elapsedSinceCheck >= PEEK_INTERVAL then
				elapsedSinceCheck = 0
				CheckPeek()
			end
		end)
	end
	-- Only call the native setter when the driver changes state.
	if peekDriver and peekDriverShown ~= active then
		peekDriver:SetShown(active)
		peekDriverShown = active
	end
end

SyncPeek = function()
	if InCombatLockdown() then
		UpdatePeekDriver()
		return
	end
	if not (hidUI and Wanderlust.db.enabled) then
		EndPeek(true)
		UpdatePeekDriver()
		return
	end
	local desired = DesiredPeekFrames()
	if next(desired) then
		if not peek then
			if UIParent:IsShown() then return end
			peek = { alpha = UIParent:GetAlpha(), ignored = {} }
			for frame in pairs(desired) do
				peek.ignored[frame] = frame:IsIgnoringParentAlpha()
				frame:SetIgnoreParentAlpha(true)
			end
			UIParent:SetAlpha(0)
			SetInterfaceVisibility(true) -- OnUIShown leaves this reveal alone while peek is set
		else
			local removed
			for frame, orig in pairs(peek.ignored) do
				if not desired[frame] then
					removed = removed or {}
					removed[frame] = orig
					peek.ignored[frame] = nil
				end
			end
			if removed then RestoreIgnored(removed) end
			for frame in pairs(desired) do
				if peek.ignored[frame] == nil then
					peek.ignored[frame] = frame:IsIgnoringParentAlpha()
					frame:SetIgnoreParentAlpha(true)
				end
			end
		end
	elseif peek then
		EndPeek(true)
	end
	UpdatePeekDriver()
end

local function InteractionOpen()
	if (not Wanderlust.db.showBags and AnyBagOpen())
		or ns:IsEditModeActive() or WindowShown(ChatEdit_GetActiveWindow()) then
		return true
	end
	for _, name in ipairs(WINDOW_NAMES) do
		local frame = _G[name]
		if WindowShown(frame) and not DialogOwnsWindow(frame) then return true end
	end
	-- Include panels loaded later and addon windows registered for Escape.
	for name in pairs(UIPanelWindows) do
		local frame = _G[name]
		if WindowShown(frame) and not DialogOwnsWindow(frame) then return true end
	end
	for _, name in ipairs(UISpecialFrames) do
		local frame = _G[name]
		if WindowShown(frame) and not DialogOwnsWindow(frame) then return true end
	end
	return false
end

local function HardBlocked()
	if Wanderlust.db.showOnTarget then
		local target = UnitExists("target")
		if ns.Secret(target) or target then return true end
		local focus = UnitExists("focus")
		if ns.Secret(focus) or focus then return true end
	end
	return InteractionOpen()
end

local function SoftBlocked()
	return (Wanderlust.db.showBags and AnyBagOpen()) or DialogActive()
end

local function ActivityBlocked()
	return HardBlocked() or SoftBlocked()
end

local function CancelTimer()
	if timer then
		timer:Cancel()
		timer = nil
	end
end

local function ClearTeleport()
	if teleport then
		teleport.timer:Cancel()
		teleport = nil
	end
end

local function RestoreUI()
	ClearTeleport()
	EndPeek(false)
	if hidUI then
		hidUI = nil
		if not UIParent:IsShown() then
			-- Use the same native API as the game's Toggle UI binding, including in combat.
			restoring = true
			SetInterfaceVisibility(true)
			restoring = nil
		end
		-- Keep a focused chat input visible when it returns to UIParent.
		UpdateHiddenUI()
	end
end

local function HideUI()
	-- No open target or window is hidden, so its OnHide cannot play a close sound.
	hidUI = true
	SavePeekArea()
	UpdateHiddenChat()
	SetInterfaceVisibility(false)
	UpdateHiddenUI()
end

local function StartTimer()
	CancelTimer()
	-- hidUI: the interface is Wanderlust's, also while it is see-through over the minimap.
	if not Wanderlust.db.enabled or InCombatLockdown() or not UIParent:IsShown() or hidUI then
		return
	end
	blocked = ActivityBlocked()
	if blocked then return end
	if teleport then
		if not teleport.ending then HideUI() end
		return
	end
	local pending
	pending = ns.NewTimer("Wanderlust: hide interface", QUIET_SECONDS, function()
		if timer ~= pending then
			return
		end
		timer = nil
		if Wanderlust.db.enabled and not InCombatLockdown() and UIParent:IsShown() then
			blocked = ActivityBlocked()
			if not blocked then HideUI() end
		end
	end)
	timer = pending
end

local function OnUIShown()
	if peek then return end -- Wanderlust's own see-through reveal over the minimap
	-- Escape, Toggle UI and other features give the player another full minute.
	-- A later manual hide now belongs to the player, not to Wanderlust.
	ClearTeleport()
	hidUI = nil
	UpdateHiddenUI()
	if not restoring then
		StartTimer()
	end
end

local function Stop()
	CancelTimer()
	RestoreUI()
end

local function RefreshActivity()
	if not Wanderlust.db.enabled or InCombatLockdown() then return end
	if HardBlocked() then
		blocked = true
		if hidUI then Stop() else CancelTimer() end
	elseif SoftBlocked() then
		if hidUI then
			SyncPeek()
		else
			blocked = true
			CancelTimer()
		end
	elseif hidUI then
		if peek then SyncPeek() end
	elseif blocked then
		blocked = false
		StartTimer()
	end
end

CheckPeek = function()
	bagJustClosed = nil
	if InCombatLockdown() then return end -- the combat events bring the whole interface back
	if peek then
		-- RefreshActivity already synchronizes the preview. Calling it here
		-- doubled the frame scan and reconciliation on every active mouseover tick.
		-- A hard blocker must still restore the full interface immediately.
		if HardBlocked() then
			blocked = true
			Stop()
			return
		end
		if not UIParent:IsShown() then
			-- The player hid the interface: it stays hidden and is no longer Wanderlust's.
			EndPeek(false)
			ClearTeleport()
			hidUI = nil
			UpdateHiddenUI()
			return
		end
	end
	SyncPeek()
end

UpdateHiddenUI = function()
	local hidden = hidUI and Wanderlust.db.enabled
	UpdateHiddenChat()
	ns:GetModule("Tooltip").SetWanderlustHover(hidden and Wanderlust.db.hoverText or false)
	if not hidden or peek then
		SyncPeek()
	else
		UpdatePeekDriver()
	end
end

local function InteractionOpened()
	blocked = true
	Stop()
end

local function BagOpened()
	bagJustClosed = nil
	if Wanderlust.db.showBags then
		bagKeyUntil = nil
		if hidUI then
			SyncPeek()
		else
			blocked = true
			CancelTimer()
		end
	else
		InteractionOpened()
	end
end

local function BagKeyPressed()
	if bagJustClosed then
		bagJustClosed = nil
		return
	end
	if hidUI and Wanderlust.db.enabled and Wanderlust.db.showBags
		and not peek and not UIParent:IsShown() and not InCombatLockdown() then
		bagKeyUntil = ns.Number(GetTime(), 0) + BAG_KEY_PEEK_SECONDS
		SyncPeek()
	end
end

local function DialogOpened(_, event, interactionType)
	if Wanderlust.db.showBubbles and DialogHandlesEvent(event, interactionType) then
		if not hidUI then
			blocked = true
			CancelTimer()
		end
		ns.After("Wanderlust: dialog opened", 0, RefreshActivity)
	else
		InteractionOpened()
	end
end

function Wanderlust.OnDialogChanged()
	if not Wanderlust.db.enabled or InCombatLockdown() then return end
	RefreshActivity()
end

local function ChatInputOpened()
	if not hidUI then return end
	-- Let the edit box take focus before moving it back to the visible interface.
	ns.After("Wanderlust: chat input", 0, function()
		if hidUI and WindowShown(ChatEdit_GetActiveWindow()) then InteractionOpened() end
	end)
end

-- The bank's OnShow buys a free first tab (protected C_Bank.PurchaseBankTab). The interaction event reaches
-- Blizzard first: if Wanderlust's SetUIVisibility(true) only afterwards made the shown bank visible, that OnShow
-- ran tainted and the purchase was blocked. BankFrame_Open sets the portrait right before ShowUIPanel.
local function BankOpening()
	if Wanderlust.db.enabled then InteractionOpened() end
end

local professionSpells, professionNames
local nativeProfessions = {}

local function InvalidateProfessions()
	professionSpells, professionNames = nil, nil
end

local function ReadProfessions()
	professionSpells, professionNames = {}, {}
	for _, index in pairs({ GetProfessions() }) do
		local _, _, _, _, count, offset = GetProfessionInfo(index)
		if count and offset then
			for slot = offset + 1, offset + count do
				local spell = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
				if spell then
					local id = ns.Number(spell.spellID)
					if id then professionSpells[id] = true end
					if type(spell.name) == "string" and not ns.Secret(spell.name) then
						professionNames[spell.name] = true
					end
				end
			end
		end
	end
end

local function IsProfessionSpell(event, spellID)
	local tradeskill
	if event == "UNIT_SPELLCAST_START" then
		tradeskill = select(6, UnitCastingInfo("player"))
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		tradeskill = select(6, UnitChannelInfo("player"))
	end
	if tradeskill == true then
		-- Keep the native classification for SUCCEEDED, after cast info disappears.
		-- A skill-up can invalidate the spellbook cache before that event arrives.
		if spellID then nativeProfessions[spellID] = true end
		return true
	end
	if not spellID then return false end
	if nativeProfessions[spellID] then return true end
	if not professionSpells then ReadProfessions() end
	if professionSpells[spellID] == nil then
		local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(spellID)
		local name = C_Spell.GetSpellName(spellID)
		-- The cast can use a different rank ID than the spellbook (notably Fishing).
		professionSpells[spellID] = (info and ns.Number(info.professionID, 0) > 0)
			or (type(name) == "string" and not ns.Secret(name) and professionNames[name]) or false
	end
	return professionSpells[spellID]
end

local function FinishTeleport()
	RestoreUI()
	StartTimer()
end

local function ScheduleTeleportFinish(seconds)
	if teleport.timer then teleport.timer:Cancel() end
	local pending
	pending = ns.NewTimer("Wanderlust: teleport finish", seconds, function()
		if teleport and teleport.timer == pending then FinishTeleport() end
	end)
	teleport.timer = pending
end

local function AwaitTeleportArrival()
	if teleport.ending then return end
	-- STOP can precede success and the loading screen. Same-map arrivals also need a finish.
	teleport.ending = true
	ScheduleTeleportFinish(TELEPORT_TRANSITION)
end

local function StartTeleport(event, guid, spellID)
	if not Wanderlust.db.hideTeleports or not spellID or ns.Secret(guid) or not guid then return false end
	local channel = event == "UNIT_SPELLCAST_CHANNEL_START"
	local readCast = channel and UnitChannelInfo or UnitCastingInfo
	local _, _, _, startMS, endMS = readCast("player")
	startMS, endMS = ns.Number(startMS), ns.Number(endMS)
	if not startMS or not endMS or endMS - startMS < MIN_TELEPORT_CAST_MS
		or not ns:GetModule("Teleports").IsTravelSpell(spellID) then
		return false
	end
	ClearTeleport()
	teleport = { guid = guid, channel = channel }
	-- Recover at the end of the cast even if no terminal event arrives.
	ScheduleTeleportFinish((endMS - startMS) / 1000 + 1)
	StartTimer()
	return true
end

local function OnTeleportStopped(_, event, unit, guid)
	if not teleport or ns.Secret(unit) or unit ~= "player" or ns.Secret(guid) or guid ~= teleport.guid then return end
	if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if (event == "UNIT_SPELLCAST_CHANNEL_STOP") == teleport.channel then
			AwaitTeleportArrival()
		end
	else
		FinishTeleport()
	end
end

local function OnSpellCast(_, event, unit, guid, spellID)
	if ns.Secret(unit) or unit ~= "player" then return end
	if InCombatLockdown() then
		Stop()
		return
	end
	if not hidUI and not UIParent:IsShown() then return end
	spellID = ns.Number(spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if teleport then
			if not teleport.channel and not ns.Secret(guid) and guid == teleport.guid then
				AwaitTeleportArrival()
			end
			return
		end
	elseif StartTeleport(event, guid, spellID) then
		return
	end
	if not Wanderlust.db.showProfessions and IsProfessionSpell(event, spellID) then return end
	RestoreUI()
	StartTimer()
end

local function EnteringWorld()
	if teleport then RestoreUI() end
	StartTimer()
end

local function InteractionClosed(_, event)
	if event == "BAG_CLOSED" and hidUI and peek and Wanderlust.db.showBags then
		bagJustClosed = true
	end
	-- The closing event can precede the native frame's OnHide. Check next frame,
	-- also allowing a gossip-to-quest transition to open its replacement window.
	ns.After("Wanderlust: interaction closed", 0, function()
		if hidUI or blocked then
			RefreshActivity()
		else
			StartTimer()
		end
	end)
end

function Wanderlust:Apply()
	local enabled = self.db.enabled
	if teleport and not self.db.hideTeleports then Stop() end
	InvalidateProfessions()
	nativeProfessions = {}
	if enabled and not hooked then
		hooked = true
		UIParent:HookScript("OnShow", ns.Measured("Wanderlust: interface shown", OnUIShown))
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", ns.Measured("Wanderlust: chat opened", ChatInputOpened), self)
		if BankFrame and BankFrame.SetPortraitToUnit then
			hooksecurefunc(BankFrame, "SetPortraitToUnit", ns.Measured("Wanderlust: bank opening", BankOpening))
		end
		local onBagKey = ns.Measured("Wanderlust: bag key", BagKeyPressed)
		for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
			if _G[name] then hooksecurefunc(name, onBagKey) end
		end
	end
	self:ToggleEvent("PLAYER_REGEN_DISABLED", enabled, Stop)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", enabled, StartTimer)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, EnteringWorld)
	self:ToggleEvent("PLAYER_LEAVING_WORLD", enabled, Stop)
	self:ToggleEvent("PLAYER_LOGOUT", enabled, Stop)
	local watchTarget = enabled and self.db.showOnTarget
	self:ToggleEvent("PLAYER_TARGET_CHANGED", watchTarget, RefreshActivity)
	self:ToggleEvent("PLAYER_FOCUS_CHANGED", watchTarget, RefreshActivity)
	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
		self:ToggleEvent(event, enabled, OnSpellCast)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
		self:ToggleEvent(event, enabled and self.db.hideTeleports, OnTeleportStopped)
	end
	for _, event in ipairs({ "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }) do
		self:ToggleEvent(event, enabled and not self.db.showProfessions, InvalidateProfessions)
	end
	for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
		"MERCHANT_SHOW", "TRAINER_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
		self:ToggleEvent(event, enabled, DialogOpened)
	end
	self:ToggleEvent("BAG_OPEN", enabled, BagOpened)
	for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED", "GUILDBANKFRAME_OPENED",
		"MAIL_SHOW", "TRADE_SHOW", "LOOT_OPENED", "TAXIMAP_OPENED" }) do
		self:ToggleEvent(event, enabled, InteractionOpened)
	end
	for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "MERCHANT_CLOSED", "TRAINER_CLOSED", "BAG_CLOSED",
		"AUCTION_HOUSE_CLOSED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_CLOSED", "MAIL_CLOSED", "TRADE_CLOSED", "LOOT_CLOSED",
		"TAXIMAP_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
		self:ToggleEvent(event, enabled, InteractionClosed)
	end
	if enabled then
		-- Catch direct frame Show/Hide calls and newly created addon windows too.
		if not activityTicker then
			activityTicker = ns.NewTicker("Wanderlust: window activity", 1, RefreshActivity)
		end
		RefreshActivity()
		StartTimer()
	else
		if activityTicker then
			activityTicker:Cancel()
			activityTicker = nil
		end
		blocked = nil
		Stop()
	end
	UpdateHiddenUI()
end

function Wanderlust:OnLogin()
	self:Apply()
end

function Wanderlust:OnOptionChanged(key)
	if key == "hoverText" or key == "showChat" then
		UpdateHiddenUI()
	else
		self:Apply()
	end
end

Wanderlust.options = {
	{ key = "enabled", type = "toggle", name = L.WANDERLUST_TITLE, desc = L.WANDERLUST_DESC },
	{ key = "minimapMouseover", type = "toggle", name = L.WANDERLUST_MINIMAP, desc = L.WANDERLUST_MINIMAP_DESC, parent = "enabled" },
	{ key = "hoverText", type = "toggle", name = L.WANDERLUST_HOVER_TEXT, desc = L.WANDERLUST_HOVER_TEXT_DESC, parent = "enabled" },
	{ key = "showChat", type = "toggle", name = L.WANDERLUST_CHAT, desc = L.WANDERLUST_CHAT_DESC, parent = "enabled" },
	{ key = "showBags", type = "toggle", name = L.WANDERLUST_BAGS, desc = L.WANDERLUST_BAGS_DESC, parent = "enabled", new = true },
	{ key = "showBubbles", type = "toggle", name = L.WANDERLUST_BUBBLES, desc = L.WANDERLUST_BUBBLES_DESC, parent = "enabled", new = true },
	{ key = "hideTeleports", type = "toggle", name = L.WANDERLUST_TELEPORTS, desc = L.WANDERLUST_TELEPORTS_DESC, parent = "enabled" },
	{ key = "showOnTarget", type = "toggle", name = L.WANDERLUST_TARGET, desc = L.WANDERLUST_TARGET_DESC, parent = "enabled", new = true },
	{ key = "showProfessions", type = "toggle", name = L.WANDERLUST_PROFESSIONS, desc = L.WANDERLUST_PROFESSIONS_DESC, parent = "enabled" },
}

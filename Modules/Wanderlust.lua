-- Hide the interface after a quiet minute; combat and abilities bring it back.
local _, ns = ...
local L = ns.L

local Wanderlust = ns:NewModule("Wanderlust", {
	title = L.WANDERLUST_TITLE,
	defaults = { enabled = false, softHide = true, showOnTarget = false, showProfessions = false, minimapMouseover = true,
		hoverText = true, showChat = true, showBags = true, showBubbles = true, hideTeleports = true },
})

local QUIET_SECONDS = 60
local timer, activityTicker, hidUI, hooked, restoring, blocked
local teleport
local MIN_TELEPORT_CAST_MS = 2000
local TELEPORT_TRANSITION = 0.5
local PEEK_INTERVAL = 0.1
local SOFT_HARD_CHECK_INTERVAL = 0.3
local MINIMAP_LEAVE_GRACE = 0.25
local BAG_KEY_PEEK_SECONDS = 3
local peek, softHidden, peekArea, peekKeepArea, bagsBarArea, bagKeyUntil, bagJustClosed, peekDriver
local lastMinimapHover
local minimapHiddenByWanderlust = false
local escGuard, escHidingInternal, escRestoredAt, hidingUI, fishingHidden, uiHideHooked
local UpdateHiddenUI, CheckPeek, SyncPeek, RestoreUI, StartTimer, SoftBlocked, SyncEscGuard, SetMinimapHidden, EnsureUIHideHook
local peekDriverShown
local softHardCheckElapsed = 0

local SetInterfaceVisibility = ns.Measured("Wanderlust: SetUIVisibility", function(visible)
	hidingUI = not visible
	SetUIVisibility(visible)
	hidingUI = nil
end)

local function DialogModule()
	return ns:GetModule("Dialog")
end

local function QoLModule()
	return ns:GetModule("QoL")
end

local function DialogActive()
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	return dialog and dialog.IsBubbleActive and dialog.IsBubbleActive() or false
end

local function DialogHandlesEvent(event, interactionType)
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	return dialog and dialog.HandlesEvent and dialog.HandlesEvent(event, interactionType) or false
end

local function UpdateHiddenChat()
	-- In soft-hide mode UIParent stays shown, so chat frames stay in place without reparenting.
	local visible = hidUI and not softHidden and Wanderlust.db.enabled and Wanderlust.db.showChat or false
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
	local active = peek ~= nil or (softHidden and softHidden.minimapShown) or false
	if CursorInArea(active and peekKeepArea or peekArea) then
		lastMinimapHover = GetTime()
		return true
	end
	-- A short excursion outside the rim should not hide and re-show the minimap.
	return active and lastMinimapHover and GetTime() - lastMinimapHover < MINIMAP_LEAVE_GRACE or false
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
	if not softHidden then SetMinimapHidden(false) end
end

local WINDOW_NAMES = {
	"GossipFrame", "QuestFrame", "MerchantFrame", "ClassTrainerFrame", "WorldMapFrame", "SettingsPanel",
	"GameMenuFrame", "PlayerSpellsFrame", "ProfessionsFrame", "AuctionHouseFrame", "BankFrame", "GuildBankFrame",
	"MailFrame", "LootFrame", "TradeFrame", "TaxiFrame", "FlightMapFrame", "ForeverPlusReadable",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}
local WINDOW_NAME_SET = {}
for _, name in ipairs(WINDOW_NAMES) do
	WINDOW_NAME_SET[name] = true
end
local lastOpenWindow

local function IsForbiddenSafe(frame)
	if not frame or not frame.IsForbidden then return false end
	local forbidden = frame:IsForbidden()
	return ns.Secret(forbidden) or forbidden == true
end

local function IgnoresParentAlpha(object)
	if not object or not object.IsIgnoringParentAlpha then return false end
	local ignoring = object:IsIgnoringParentAlpha()
	return not ns.Secret(ignoring) and ignoring == true
end

local function WindowShown(frame)
	if not frame or IsForbiddenSafe(frame) or not frame.IsShown then return false end
	local shown = frame:IsShown()
	return not ns.Secret(shown) and shown == true
end

-- Blizzards minimap blips (nodes, quests, units) ignore alpha: hide the Minimap widget itself
-- while it should not be visible, without touching MinimapCluster's EditMode layout state.
SetMinimapHidden = function(hide)
	if not Minimap or IsForbiddenSafe(Minimap) or not Minimap.Hide or not Minimap.Show then
		minimapHiddenByWanderlust = false
		return
	end
	if hide then
		if not minimapHiddenByWanderlust and WindowShown(Minimap) then
			if not (Minimap.IsProtected and Minimap:IsProtected()) or not InCombatLockdown() then
				minimapHiddenByWanderlust = true
				Minimap:Hide()
			end
		end
	elseif minimapHiddenByWanderlust then
		minimapHiddenByWanderlust = false
		local function RestoreMinimap()
			if not minimapHiddenByWanderlust and Minimap and not IsForbiddenSafe(Minimap) and Minimap.Show then
				Minimap:Show()
			end
		end
		if Minimap.IsProtected and Minimap:IsProtected() and InCombatLockdown() then
			ns.RunOutOfCombat(RestoreMinimap)
		else
			RestoreMinimap()
		end
	end
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
	local hidden = hidUI and Wanderlust.db.enabled and not fishingHidden or false
	local watchMinimap = hidden and Wanderlust.db.minimapMouseover
		and MinimapCluster and not MinimapCluster:IsForbidden() or false
	local watchBags = hidden and Wanderlust.db.showBags
		and BagsBar and not BagsBar:IsForbidden() or false
	local active = watchMinimap or watchBags or (hidden and (peek ~= nil or softHidden ~= nil)) or false
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

---------------------------------------------------------------------------
-- Soft-hide mode: fade visible direct UIParent HUD children via SetAlpha(0)
-- instead of calling SetUIVisibility(false)/(true), avoiding 30-60 ms stalls.
---------------------------------------------------------------------------
local TRANSIENT_HUD_NAMES = {
	"PlayerFrame", "TargetFrame", "FocusFrame", "PlayerCastingBarFrame", "CastingBarFrame",
	"PetFrame", "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer",
	"BuffFrame", "DebuffFrame", "ForeverPlusBuffBar", "ForeverPlusWaypointArrow",
}

local function CanFadeFrame(frame)
	return frame and not IsForbiddenSafe(frame)
		and frame.GetAlpha and frame.SetAlpha
end

local function RecordSoftEntry(bucket, frame, qol)
	if not CanFadeFrame(frame) or bucket[frame] then return end
	local actual = ns.Number(frame:GetAlpha(), 1)
	local shown = qol and qol.ShownAlpha and qol.ShownAlpha(frame) or actual
	if shown <= 0.05 then shown = 1 end
	bucket[frame] = { restore = actual, show = shown }
end

local CollectIndependentOverlays

local function CollectIndependentRegions(bucket, qol, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if CanFadeFrame(region) and IgnoresParentAlpha(region) then
			RecordSoftEntry(bucket, region, qol)
		end
	end
end

local function CollectIndependentChildren(bucket, visited, qol, nextDepth, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		if CanFadeFrame(child) and IgnoresParentAlpha(child) then
			RecordSoftEntry(bucket, child, qol)
		end
		if not nextDepth or nextDepth > 0 then
			CollectIndependentOverlays(child, bucket, visited, qol, nextDepth)
		end
	end
end

CollectIndependentOverlays = function(parent, bucket, visited, qol, depth)
	if not parent or visited[parent] or IsForbiddenSafe(parent) then
		return
	end
	visited[parent] = true
	if parent.GetRegions then
		CollectIndependentRegions(bucket, qol, parent:GetRegions())
	end
	if depth and depth <= 0 then return end
	if not parent.GetChildren then return end
	local nextDepth = depth and (depth - 1) or nil
	CollectIndependentChildren(bucket, visited, qol, nextDepth, parent:GetChildren())
end

local function RecordDirectIndependent(state, ...)
	for i = 1, select("#", ...) do
		local obj = select(i, ...)
		if state.frames[obj] == nil and not state.minimap[obj]
			and CanFadeFrame(obj) and IgnoresParentAlpha(obj) then
			local orig = ns.Number(obj:GetAlpha(), 1)
			state.frames[obj] = orig
			if orig ~= 0 then obj:SetAlpha(0) end
		end
	end
end

local function RecordSoftFrameAndOverlays(state, frame)
	if not CanFadeFrame(frame) or state.frames[frame] ~= nil then return end
	local orig = ns.Number(frame:GetAlpha(), 1)
	state.frames[frame] = orig
	if orig ~= 0 then frame:SetAlpha(0) end
	-- Check only direct regions and direct children without crawling button/aura subtrees or allocating tables.
	if frame.GetRegions then
		RecordDirectIndependent(state, frame:GetRegions())
	end
	if frame.GetChildren then
		RecordDirectIndependent(state, frame:GetChildren())
	end
end

-- Cache derived chat frame names (Tab/EditBox/Minimized) to avoid repeated string allocations per UIParent child.
local chatNameCache, chatNameCount = {}, 0
local function ChatFrameNames()
	local list = CHAT_FRAMES
	local count = list and #list or 0
	if count ~= chatNameCount then
		wipe(chatNameCache)
		chatNameCount = count
		for i = 1, count do
			local name = list[i]
			local base = (i - 1) * 4
			chatNameCache[base + 1] = name
			chatNameCache[base + 2] = name .. "Tab"
			chatNameCache[base + 3] = name .. "EditBox"
			chatNameCache[base + 4] = name .. "Minimized"
		end
	end
	return chatNameCache
end

local function IsChatFrameObject(frame)
	if frame == GeneralDockManager then return true end
	local names = ChatFrameNames()
	for i = 1, #names do
		if frame == _G[names[i]] then
			return true
		end
	end
	return false
end

local softExcluded = {}
local softVisited = {}

local function BuildSoftExcluded()
	wipe(softExcluded)
	if escGuard then softExcluded[escGuard] = true end
	if GameTooltip then softExcluded[GameTooltip] = true end
	if ShoppingTooltip1 then softExcluded[ShoppingTooltip1] = true end
	if ShoppingTooltip2 then softExcluded[ShoppingTooltip2] = true end
	local anglerBear = _G.ForeverPlusAnglerBear
	if anglerBear then softExcluded[anglerBear] = true end
	local modeFlash = _G.ForeverPlusModeFlash
	if modeFlash then softExcluded[modeFlash] = true end
	if not fishingHidden then
		if Wanderlust.db.showChat then
			if GeneralDockManager then softExcluded[GeneralDockManager] = true end
			local names = ChatFrameNames()
			for i = 1, #names do
				local frame = _G[names[i]]
				if frame then softExcluded[frame] = true end
			end
		end
		if Wanderlust.db.showBags then
			if ContainerFrameCombinedBags then softExcluded[ContainerFrameCombinedBags] = true end
			if ContainerFrameContainer then
				softExcluded[ContainerFrameContainer] = true
				local list = ContainerFrameContainer.ContainerFrames
				if list then
					for i = 1, #list do
						local bagFrame = list[i]
						if bagFrame then softExcluded[bagFrame] = true end
					end
				end
			end
			if StackSplitFrame then softExcluded[StackSplitFrame] = true end
		end
		if Wanderlust.db.showBubbles then
			local dialog = DialogModule()
			local bubble = dialog and dialog.GetBubbleFrame and dialog.GetBubbleFrame()
			if bubble then softExcluded[bubble] = true end
		end
	end
	return softExcluded
end

local function RecordExtraSoftFrame(state, frame)
	if not CanFadeFrame(frame) or not WindowShown(frame)
		or state.frames[frame] ~= nil or state.extra[frame] ~= nil
		or state.minimap[frame] or (state.bags and state.bags.frame == frame) then
		return
	end
	local orig = ns.Number(frame:GetAlpha(), 1)
	state.extra[frame] = orig
	if orig ~= 0 then frame:SetAlpha(0) end
end

local function FadeFishingExtras(state)
	if not state then return end
	RecordExtraSoftFrame(state, GeneralDockManager)
	local names = ChatFrameNames()
	for i = 1, #names do
		RecordExtraSoftFrame(state, _G[names[i]])
	end
	RecordExtraSoftFrame(state, ContainerFrameCombinedBags)
	if ContainerFrameContainer then
		RecordExtraSoftFrame(state, ContainerFrameContainer)
		local list = ContainerFrameContainer.ContainerFrames
		if list then
			for i = 1, #list do
				RecordExtraSoftFrame(state, list[i])
			end
		end
	end
	RecordExtraSoftFrame(state, StackSplitFrame)
	local dialog = DialogModule()
	RecordExtraSoftFrame(state, dialog and dialog.GetBubbleFrame and dialog.GetBubbleFrame())
end

local function RestoreFishingExtras(state)
	if not (state and state.extra) then return end
	for frame, orig in pairs(state.extra) do
		if CanFadeFrame(frame) then
			frame:SetAlpha(orig)
		end
	end
	wipe(state.extra)
end

local function FadeUIParentChildren(state, excluded, ...)
	local bagsFrame = state.bags and state.bags.frame
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		if not excluded[child] and not state.minimap[child] and child ~= bagsFrame
			and CanFadeFrame(child) and WindowShown(child) then
			RecordSoftFrameAndOverlays(state, child)
		end
	end
end

local function SyncSoftChat()
	if not softHidden or fishingHidden then return end
	local showChat = Wanderlust.db.showChat
	if showChat then
		for frame, orig in pairs(softHidden.frames) do
			if IsChatFrameObject(frame) then
				softHidden.frames[frame] = nil
				if CanFadeFrame(frame) then
					frame:SetAlpha(orig)
				end
			end
		end
	else
		local function FadeChatFrame(frame)
			if CanFadeFrame(frame) and WindowShown(frame) and softHidden.frames[frame] == nil then
				local orig = ns.Number(frame:GetAlpha(), 1)
				softHidden.frames[frame] = orig
				if orig ~= 0 then frame:SetAlpha(0) end
			end
		end
		FadeChatFrame(GeneralDockManager)
		local names = ChatFrameNames()
		for i = 1, #names do
			FadeChatFrame(_G[names[i]])
		end
	end
end

local function SyncSoftPeek()
	if not softHidden then return end
	if bagKeyUntil and ns.Number(GetTime(), 0) >= bagKeyUntil then
		bagKeyUntil = nil
	end
	local overMinimap = not fishingHidden and CursorOverMinimap() or false
	if overMinimap ~= softHidden.minimapShown then
		softHidden.minimapShown = overMinimap
		if overMinimap then
			SetMinimapHidden(false)
		end
		for frame, info in pairs(softHidden.minimap) do
			if CanFadeFrame(frame) then
				frame:SetAlpha(overMinimap and info.show or 0)
			end
		end
		if not overMinimap then
			SetMinimapHidden(true)
		end
	end
	local bagsOpen
	if softHidden.bags then
		bagsOpen = not fishingHidden and Wanderlust.db.showBags and AnyBagOpen() or false
		if bagsOpen then bagKeyUntil = nil end
		local showBagsBar = not fishingHidden and Wanderlust.db.showBags
			and (bagsOpen or CursorOverBagsBar() or bagKeyUntil ~= nil) or false
		if showBagsBar ~= softHidden.bagsShown then
			softHidden.bagsShown = showBagsBar
			local bagBar = softHidden.bags.frame
			if CanFadeFrame(bagBar) then
				bagBar:SetAlpha(showBagsBar and softHidden.bags.show or 0)
			end
		end
	end
	SyncEscGuard(bagsOpen)
end

local function EnterSoftHide()
	if softHidden then return end
	EnsureUIHideHook()
	local qol = QoLModule()
	if qol and qol.SetWanderlustSuppressed then
		qol.SetWanderlustSuppressed(true)
	end
	local state = { frames = {}, extra = {}, minimap = {}, minimapShown = nil, bags = nil, bagsShown = nil }
	softHidden = state
	softHardCheckElapsed = 0

	-- Minimap cluster, backdrop and independent overlays (capped depth avoids crawling pin subtrees).
	RecordSoftEntry(state.minimap, MinimapCluster, qol)
	RecordSoftEntry(state.minimap, Minimap, qol)
	RecordSoftEntry(state.minimap, MinimapBackdrop, qol)
	wipe(softVisited)
	CollectIndependentOverlays(MinimapCluster, state.minimap, softVisited, qol, 2)
	CollectIndependentOverlays(Minimap, state.minimap, softVisited, qol, 2)
	wipe(softVisited)

	-- BagsBar toggles on hover / open bags when showBags is enabled.
	if CanFadeFrame(BagsBar) then
		local actual = ns.Number(BagsBar:GetAlpha(), 1)
		local shown = qol and qol.ShownAlpha and qol.ShownAlpha(BagsBar) or actual
		if shown <= 0.05 then shown = 1 end
		state.bags = { frame = BagsBar, restore = actual, show = shown }
	end

	local excluded = BuildSoftExcluded()
	if UIParent.GetChildren then
		FadeUIParentChildren(state, excluded, UIParent:GetChildren())
	end
	wipe(softExcluded)

	-- Also keep transient HUD frames (player portrait container, target/focus/castbar, buff bar, waypoint) transparent.
	for i = 1, #TRANSIENT_HUD_NAMES do
		local frame = _G[TRANSIENT_HUD_NAMES[i]]
		if CanFadeFrame(frame) and not state.minimap[frame] then
			RecordSoftFrameAndOverlays(state, frame)
		end
	end
	local playerContainer = PlayerFrame and PlayerFrame.PlayerFrameContainer
	if CanFadeFrame(playerContainer) and not state.minimap[playerContainer] then
		RecordSoftFrameAndOverlays(state, playerContainer)
	end
	if ns.PortraitModes and ns.PortraitModes.SetWanderlustHidden then
		ns.PortraitModes.SetWanderlustHidden(true)
	end
end

local function ExitSoftHide()
	if not softHidden then return end
	local saved = softHidden
	softHidden = nil
	bagKeyUntil = nil
	lastMinimapHover = nil
	SyncEscGuard()
	RestoreFishingExtras(saved)
	for frame, orig in pairs(saved.frames) do
		if CanFadeFrame(frame) then
			frame:SetAlpha(orig)
		end
	end
	for frame, info in pairs(saved.minimap) do
		if CanFadeFrame(frame) then
			frame:SetAlpha(info.restore)
		end
	end
	SetMinimapHidden(false)
	if saved.bags and CanFadeFrame(saved.bags.frame) then
		saved.bags.frame:SetAlpha(saved.bags.restore)
	end
	if ns.PortraitModes and ns.PortraitModes.SetWanderlustHidden then
		ns.PortraitModes.SetWanderlustHidden(false)
	end
	local qol = QoLModule()
	if qol and qol.SetWanderlustSuppressed then
		qol.SetWanderlustSuppressed(false)
	end
end

function Wanderlust.IsSoftHidden()
	return softHidden ~= nil
end

function Wanderlust.IsChatSoftHidden()
	return softHidden ~= nil and (fishingHidden == true or not Wanderlust.db.showChat)
end

local function EnterPeek(desired, reveal)
	peek = { alpha = UIParent:GetAlpha(), ignored = {} }
	SetMinimapHidden(not desired[MinimapCluster])
	for frame in pairs(desired) do
		peek.ignored[frame] = frame:IsIgnoringParentAlpha()
		frame:SetIgnoreParentAlpha(true)
	end
	UIParent:SetAlpha(0)
	if reveal then
		SetInterfaceVisibility(true) -- OnUIShown leaves this reveal alone while peek is set
	end
end

SyncPeek = function()
	if softHidden then
		if not ((hidUI and Wanderlust.db.enabled) or fishingHidden) then
			ExitSoftHide()
		elseif not InCombatLockdown() then
			SyncSoftPeek()
		end
		UpdatePeekDriver()
		return
	end
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
			EnterPeek(desired, true)
		else
			SetMinimapHidden(not desired[MinimapCluster])
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
	local dialog = Wanderlust.db.showBubbles and DialogModule()
	local ownsWindow = dialog and dialog.IsBubbleActive and dialog.IsBubbleActive() and dialog.OwnsWindow or nil
	if lastOpenWindow then
		if WindowShown(lastOpenWindow) and not (ownsWindow and ownsWindow(lastOpenWindow)) then
			return true
		end
		lastOpenWindow = nil
	end
	for _, name in ipairs(WINDOW_NAMES) do
		local frame = _G[name]
		if WindowShown(frame) and not (ownsWindow and ownsWindow(frame)) then
			lastOpenWindow = frame
			return true
		end
	end
	-- Include panels loaded later and addon windows registered for Escape.
	for name in pairs(UIPanelWindows) do
		if not WINDOW_NAME_SET[name] then
			local frame = _G[name]
			if WindowShown(frame) and not (ownsWindow and ownsWindow(frame)) then
				lastOpenWindow = frame
				return true
			end
		end
	end
	for _, name in ipairs(UISpecialFrames) do
		if not WINDOW_NAME_SET[name] and name ~= "ForeverPlusWanderlustEsc" then
			local frame = _G[name]
			if WindowShown(frame) and not (ownsWindow and ownsWindow(frame)) then
				lastOpenWindow = frame
				return true
			end
		end
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

SoftBlocked = function()
	return (Wanderlust.db.showBags and AnyBagOpen()) or DialogActive()
end

local function ActivityBlocked()
	return HardBlocked() or SoftBlocked()
end

local function EnsureEscGuard()
	if escGuard then return escGuard end
	escGuard = CreateFrame("Frame", "ForeverPlusWanderlustEsc", UIParent)
	if escGuard.SetSize then escGuard:SetSize(1, 1) end
	if escGuard.EnableMouse then escGuard:EnableMouse(false) end
	if escGuard.Hide then escGuard:Hide() end
	if escGuard.SetScript then
		escGuard:SetScript("OnHide", ns.Measured("Wanderlust: escape restore", function()
			if escHidingInternal or not softHidden then return end
			escRestoredAt = ns.Number(GetTime(), 0)
			RestoreUI()
			StartTimer()
		end))
	end
	if UISpecialFrames and not tContains(UISpecialFrames, "ForeverPlusWanderlustEsc") then
		tinsert(UISpecialFrames, "ForeverPlusWanderlustEsc")
	end
	return escGuard
end

SyncEscGuard = function(bagsOpen)
	local softBlocked
	if bagsOpen ~= nil then
		softBlocked = bagsOpen or DialogActive()
	else
		softBlocked = SoftBlocked()
	end
	local want = softHidden ~= nil and hidUI and Wanderlust.db.enabled
		and not fishingHidden and not softBlocked and not InCombatLockdown()
	if not want and not escGuard then return end
	local guard = EnsureEscGuard()
	if not guard or not guard.IsShown or not guard.SetShown then return end
	if guard:IsShown() ~= want then
		escHidingInternal = true
		guard:SetShown(want)
		escHidingInternal = nil
	end
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

RestoreUI = function()
	ClearTeleport()
	EndPeek(false)
	if not fishingHidden then
		ExitSoftHide()
	end
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
	if Wanderlust.db.softHide or fishingHidden then
		EnterSoftHide()
		UpdateHiddenUI(true)
		return
	end
	UpdateHiddenChat()
	-- If the cursor is already over a peekable area (e.g. Minimap/BagsBar), enter the
	-- see-through preview directly instead of hiding and immediately re-showing UIParent.
	local desired = DesiredPeekFrames()
	if next(desired) then
		EnterPeek(desired, false)
	else
		SetInterfaceVisibility(false)
	end
	UpdateHiddenUI()
end

-- Soft-hide lease for Helpers' angler mode: avoids 20-50 ms SetUIVisibility stalls
-- while preserving exact original alphas if Wanderlust is also active.
function Wanderlust.SetFishingHidden(active)
	if active then
		if fishingHidden then return true end
		if peek or (not softHidden and not UIParent:IsShown()) then
			return false
		end
		fishingHidden = true
		if softHidden then
			FadeFishingExtras(softHidden)
		else
			EnterSoftHide()
		end
		SyncSoftPeek()
		UpdatePeekDriver()
		return true
	end
	if not fishingHidden then return false end
	fishingHidden = nil
	if hidUI and Wanderlust.db.enabled then
		if Wanderlust.db.softHide then
			RestoreFishingExtras(softHidden)
			UpdateHiddenUI()
		else
			ExitSoftHide()
			HideUI()
		end
	else
		ExitSoftHide()
		UpdatePeekDriver()
	end
	return true
end

StartTimer = function()
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

local function OnUIHidden()
	if hidingUI then return end
	local now = ns.Number(GetTime(), 0)
	local fromSoftToggle = softHidden ~= nil or (escRestoredAt ~= nil and escRestoredAt == now)
	if not fromSoftToggle then return end
	escRestoredAt = nil
	fishingHidden = nil
	ClearTeleport()
	ExitSoftHide()
	hidUI = nil
	UpdateHiddenUI()
	if InCombatLockdown() then return end
	-- In soft-hide mode UIParent stayed shown, so pressing Alt+Z (TOGGLEUI) hid UIParent instead of
	-- revealing the interface. Bring UIParent back right away so one keypress restores the UI.
	ns.After("Wanderlust: toggle ui restore", 0, function()
		if not UIParent:IsShown() then
			restoring = true
			SetInterfaceVisibility(true)
			restoring = nil
			StartTimer()
		end
	end)
end

EnsureUIHideHook = function()
	if uiHideHooked then return end
	uiHideHooked = true
	UIParent:HookScript("OnHide", ns.Measured("Wanderlust: interface hidden", OnUIHidden))
end

local function Stop()
	CancelTimer()
	RestoreUI()
end

local function RefreshActivity()
	if not Wanderlust.db.enabled or InCombatLockdown() then return end
	if softHidden and not UIParent:IsShown() then
		-- The player manually hid UIParent (Alt+Z): hand visibility ownership back cleanly.
		fishingHidden = nil
		ExitSoftHide()
		ClearTeleport()
		hidUI = nil
		UpdateHiddenUI()
		return
	end
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
		if peek or softHidden then SyncPeek() end
	elseif blocked then
		blocked = false
		StartTimer()
	end
end

CheckPeek = function()
	bagJustClosed = nil
	if InCombatLockdown() then return end -- the combat events bring the whole interface back
	if peek or softHidden then
		if not UIParent:IsShown() then
			-- The player hid the interface: it stays hidden and is no longer Wanderlust's.
			fishingHidden = nil
			EndPeek(false)
			ExitSoftHide()
			ClearTeleport()
			hidUI = nil
			UpdateHiddenUI()
			return
		end
		-- Classic see-through peek checks hard blockers immediately; soft hide throttles the
		-- full panel scan (standard windows also trigger events and activityTicker runs every 1s).
		local checkHard = peek ~= nil
		if not checkHard then
			softHardCheckElapsed = softHardCheckElapsed + PEEK_INTERVAL
			if softHardCheckElapsed >= SOFT_HARD_CHECK_INTERVAL then
				softHardCheckElapsed = 0
				checkHard = true
			end
		end
		if checkHard and HardBlocked() then
			blocked = true
			Stop()
			return
		end
	end
	SyncPeek()
end

UpdateHiddenUI = function(skipSoftChat)
	local hidden = hidUI and Wanderlust.db.enabled
	UpdateHiddenChat()
	ns:GetModule("Tooltip").SetWanderlustHover(hidden and Wanderlust.db.hoverText or false)
	if softHidden then
		if hidden or fishingHidden then
			if not skipSoftChat then
				SyncSoftChat()
			end
			SyncSoftPeek()
			UpdatePeekDriver()
		else
			ExitSoftHide()
			UpdatePeekDriver()
		end
	elseif not hidden or peek then
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
		EnsureUIHideHook()
		if GameMenuFrame and GameMenuFrame.HookScript then
			GameMenuFrame:HookScript("OnShow", ns.Measured("Wanderlust: game menu shown", function()
				if Wanderlust.db.enabled and hidUI then InteractionOpened() end
			end))
		end
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
	elseif key == "softHide" then
		if hidUI and self.db.enabled and not InCombatLockdown() and not fishingHidden then
			local keepTeleport = teleport
			teleport = nil
			RestoreUI()
			teleport = keepTeleport
			if not ActivityBlocked() then
				HideUI()
			end
		end
	else
		self:Apply()
	end
end

Wanderlust.options = {
	{ key = "enabled", type = "toggle", name = L.WANDERLUST_TITLE, desc = L.WANDERLUST_DESC },
	{ key = "softHide", type = "toggle", name = L.WANDERLUST_SOFT_HIDE, desc = L.WANDERLUST_SOFT_HIDE_DESC, parent = "enabled", new = true },
	{ key = "minimapMouseover", type = "toggle", name = L.WANDERLUST_MINIMAP, desc = L.WANDERLUST_MINIMAP_DESC, parent = "enabled" },
	{ key = "hoverText", type = "toggle", name = L.WANDERLUST_HOVER_TEXT, desc = L.WANDERLUST_HOVER_TEXT_DESC, parent = "enabled" },
	{ key = "showChat", type = "toggle", name = L.WANDERLUST_CHAT, desc = L.WANDERLUST_CHAT_DESC, parent = "enabled" },
	{ key = "showBags", type = "toggle", name = L.WANDERLUST_BAGS, desc = L.WANDERLUST_BAGS_DESC, parent = "enabled", new = true },
	{ key = "showBubbles", type = "toggle", name = L.WANDERLUST_BUBBLES, desc = L.WANDERLUST_BUBBLES_DESC, parent = "enabled", new = true },
	{ key = "hideTeleports", type = "toggle", name = L.WANDERLUST_TELEPORTS, desc = L.WANDERLUST_TELEPORTS_DESC, parent = "enabled" },
	{ key = "showOnTarget", type = "toggle", name = L.WANDERLUST_TARGET, desc = L.WANDERLUST_TARGET_DESC, parent = "enabled", new = true },
	{ key = "showProfessions", type = "toggle", name = L.WANDERLUST_PROFESSIONS, desc = L.WANDERLUST_PROFESSIONS_DESC, parent = "enabled" },
}

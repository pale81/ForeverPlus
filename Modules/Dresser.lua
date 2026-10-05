-- Dressing room: undress / dress buttons and per-slot toggling in the outfit list.
local _, ns = ...
local L = ns.L

local Dresser = ns:NewModule("Dresser", {
	title = L.DRESSER_TITLE,
	order = 7,
})

local savedOutfit       -- transmog info list before "undress all"
local hiddenSlots = {}  -- slotID -> ItemTransmogInfo removed from the model
local hookedSlots = {}

local function GetActor()
	return DressUpFrame and DressUpFrame.ModelScene and DressUpFrame.ModelScene:GetPlayerActor()
end

local function CreateIconButton(parent, atlas, tooltip, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(24, 24)
	button:SetNormalAtlas(atlas)
	button:SetHighlightAtlas(atlas, "ADD")
	button:GetHighlightTexture():SetAlpha(0.4)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, tooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function Undress()
	local actor = GetActor()
	if not actor then
		return
	end
	-- Keep the first snapshot when clicked repeatedly; include slots hidden one by one.
	if not savedOutfit then
		savedOutfit = actor:GetItemTransmogInfoList()
		for slotID, info in pairs(hiddenSlots) do
			savedOutfit[slotID] = info
		end
	end
	wipe(hiddenSlots)
	actor:Undress()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function Dress()
	local actor = GetActor()
	if not actor then
		return
	end
	if not savedOutfit and not next(hiddenSlots) then
		actor:Dress()
	end
	if savedOutfit then
		for slotID, info in pairs(savedOutfit) do
			actor:SetItemTransmogInfo(info, slotID)
		end
		savedOutfit = nil
	end
	for slotID, info in pairs(hiddenSlots) do
		actor:SetItemTransmogInfo(info, slotID)
	end
	wipe(hiddenSlots)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function ToggleSlot(slotFrame, mouseButton)
	if mouseButton ~= "LeftButton" or IsModifiedClick() then
		return
	end
	local slotID = slotFrame.slotID
	local actor = GetActor()
	if not slotID or not actor then
		return
	end
	local stored = hiddenSlots[slotID]
	if stored then
		actor:SetItemTransmogInfo(stored, slotID)
		hiddenSlots[slotID] = nil
		slotFrame:SetAlpha(1)
	else
		local info = actor:GetItemTransmogInfo(slotID)
		if not info then
			return
		end
		hiddenSlots[slotID] = info
		actor:UndressSlot(slotID)
		slotFrame:SetAlpha(0.4)
	end
end

local function HookSlotFrames(panel)
	if not panel.slotPool then
		return
	end
	for slotFrame in panel.slotPool:EnumerateActive() do
		if not hookedSlots[slotFrame] then
			hookedSlots[slotFrame] = true
			slotFrame:HookScript("OnMouseUp", ToggleSlot)
		end
		slotFrame:SetAlpha(hiddenSlots[slotFrame.slotID] and 0.4 or 1)
	end
end

local setupDone = false

local function Setup()
	local frame = DressUpFrame
	if not frame or setupDone then
		return
	end
	setupDone = true
	local parent = frame.ModelScene or frame
	local undress = CreateIconButton(parent, "transmog-icon-hidden", L.DRESSER_UNDRESS, Undress)
	undress:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
	undress:SetFrameLevel(parent:GetFrameLevel() + 10)
	local dress = CreateIconButton(parent, "transmog-icon-tick", L.DRESSER_DRESS, Dress)
	dress:SetPoint("LEFT", undress, "RIGHT", 4, 0)
	dress:SetFrameLevel(parent:GetFrameLevel() + 10)

	-- A new preview (item link, reset) starts from a clean state.
	hooksecurefunc("DressUpFrame_Show", function()
		savedOutfit = nil
		wipe(hiddenSlots)
	end)

	local panel = frame.CustomSetDetailsPanel
	if panel and panel.Refresh then
		hooksecurefunc(panel, "Refresh", HookSlotFrames)
	end
end

function Dresser:OnLogin()
	Setup()
end

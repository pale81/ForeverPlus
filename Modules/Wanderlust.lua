-- Hide the interface after a quiet minute; combat and abilities bring it back.
local _, ns = ...
local L = ns.L

local Wanderlust = ns:NewModule("Wanderlust", {
	title = L.WANDERLUST_TITLE,
	defaults = { enabled = false, showProfessions = false, minimapMouseover = true },
})

local QUIET_SECONDS = 60
local timer, activityTicker, hidUI, hooked, restoring, blocked
local minimapHost, minimapParent, minimapDriver

local function UpdateMinimapFade(active)
	ns.WanderlustMinimapMouseover = active or nil
	ns:GetModule("QoL"):UpdateMouseover()
end

local function RestoreMinimap()
	if not minimapHost or not (ns.WanderlustMinimapMouseover or minimapHost:GetAttribute("detached")) then return end
	UpdateMinimapFade(false)
	if not InCombatLockdown() and minimapHost:GetAttribute("detached") then
		MinimapCluster:SetParent(minimapParent)
		minimapHost:SetAttribute("detached", false)
	end
	-- The secure handlers can restore the parent during combat; removing a driver waits.
	ns.RunOutOfCombat(function()
		if minimapDriver and not ns.WanderlustMinimapMouseover then
			UnregisterStateDriver(minimapHost, "combat")
			minimapDriver = nil
		end
	end)
end

local function DetachMinimap()
	if not Wanderlust.db.minimapMouseover or InCombatLockdown() or ns.WanderlustMinimapMouseover
		or not MinimapCluster or MinimapCluster:IsForbidden() then return end
	minimapParent = MinimapCluster:GetParent()
	if not minimapHost then
		minimapHost = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
		minimapHost:EnableMouse(false)
		minimapHost:SetFrameRef("minimap", MinimapCluster)
		minimapHost:SetAttribute("_onstate-combat", [=[
			if newstate == "1" and self:GetAttribute("detached") then
				self:GetFrameRef("minimap"):SetParent(self:GetFrameRef("parent"))
				self:SetAttribute("detached", false)
			end
		]=])
		-- Manual Toggle UI and combat must both restore the parent without waiting for Lua lockdown to end.
		minimapHost:WrapScript(UIParent, "OnShow", [=[
			if control:GetAttribute("detached") then
				control:GetFrameRef("minimap"):SetParent(control:GetFrameRef("parent"))
				control:SetAttribute("detached", false)
			end
		]=])
	end
	minimapHost:SetFrameRef("parent", minimapParent)
	minimapHost:SetScale(minimapParent:GetEffectiveScale())
	minimapHost:SetAllPoints(UIParent)
	MinimapCluster:SetParent(minimapHost)
	minimapHost:SetAttribute("detached", true)
	if not minimapDriver then
		RegisterStateDriver(minimapHost, "combat", "[combat] 1; 0")
		minimapDriver = true
	end
	UpdateMinimapFade(true)
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

local function InteractionOpen()
	if IsAnyBagOpen() or ns:IsEditModeActive() or WindowShown(ChatEdit_GetActiveWindow()) then return true end
	for _, name in ipairs(WINDOW_NAMES) do
		if WindowShown(_G[name]) then return true end
	end
	-- Include panels loaded later and addon windows registered for Escape.
	for name in pairs(UIPanelWindows) do
		if WindowShown(_G[name]) then return true end
	end
	for _, name in ipairs(UISpecialFrames) do
		if WindowShown(_G[name]) then return true end
	end
	return false
end

local function ActivityBlocked()
	local target = UnitExists("target")
	if ns.Secret(target) or target then return true end
	local focus = UnitExists("focus")
	return ns.Secret(focus) or focus or InteractionOpen()
end

local function CancelTimer()
	if timer then
		timer:Cancel()
		timer = nil
	end
end

local function RestoreUI()
	RestoreMinimap()
	if hidUI then
		hidUI = nil
		if not UIParent:IsShown() then
			-- Use the same native API as the game's Toggle UI binding, including in combat.
			restoring = true
			SetUIVisibility(true)
			restoring = nil
		end
	end
end

local function StartTimer()
	CancelTimer()
	if not Wanderlust.db.enabled or InCombatLockdown() or not UIParent:IsShown() then
		return
	end
	blocked = ActivityBlocked()
	if blocked then return end
	local pending
	pending = ns.NewTimer("Wanderlust: hide interface", QUIET_SECONDS, function()
		if timer ~= pending then
			return
		end
		timer = nil
		if Wanderlust.db.enabled and not InCombatLockdown() and UIParent:IsShown() then
			blocked = ActivityBlocked()
			if blocked then return end
			-- No open target or window is hidden, so its OnHide cannot play a close sound.
			hidUI = true
			DetachMinimap()
			SetUIVisibility(false)
		end
	end)
	timer = pending
end

local function OnUIShown()
	-- Escape, Toggle UI and other features give the player another full minute.
	-- A later manual hide now belongs to the player, not to Wanderlust.
	hidUI = nil
	RestoreMinimap()
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
	if ActivityBlocked() then
		blocked = true
		Stop()
	elseif blocked then
		blocked = false
		StartTimer()
	end
end

local function InteractionOpened()
	blocked = true
	Stop()
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

local function OnSpellCast(_, event, unit, _, spellID)
	if ns.Secret(unit) or unit ~= "player" then return end
	if InCombatLockdown() then
		Stop()
		return
	end
	if not hidUI and not UIParent:IsShown() then return end
	if not Wanderlust.db.showProfessions and IsProfessionSpell(event, ns.Number(spellID)) then return end
	RestoreUI()
	StartTimer()
end

local function InteractionClosed()
	-- The closing event can precede the native frame's OnHide. Check next frame,
	-- also allowing a gossip-to-quest transition to open its replacement window.
	ns.After("Wanderlust: interaction closed", 0, StartTimer)
end

function Wanderlust:Apply()
	local enabled = self.db.enabled
	if not enabled or not self.db.minimapMouseover then RestoreMinimap()
	elseif hidUI then DetachMinimap() end
	InvalidateProfessions()
	nativeProfessions = {}
	if enabled and not hooked then
		hooked = true
		UIParent:HookScript("OnShow", ns.Measured("Wanderlust: interface shown", OnUIShown))
	end
	self:ToggleEvent("PLAYER_REGEN_DISABLED", enabled, Stop)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", enabled, StartTimer)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, StartTimer)
	self:ToggleEvent("PLAYER_LEAVING_WORLD", enabled, Stop)
	self:ToggleEvent("PLAYER_LOGOUT", enabled, Stop)
	self:ToggleEvent("PLAYER_TARGET_CHANGED", enabled, RefreshActivity)
	self:ToggleEvent("PLAYER_FOCUS_CHANGED", enabled, RefreshActivity)
	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
		self:ToggleEvent(event, enabled, OnSpellCast)
	end
	for _, event in ipairs({ "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }) do
		self:ToggleEvent(event, enabled and not self.db.showProfessions, InvalidateProfessions)
	end
	for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
		"MERCHANT_SHOW", "TRAINER_SHOW", "BAG_OPEN", "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED", "GUILDBANKFRAME_OPENED",
		"MAIL_SHOW", "TRADE_SHOW", "LOOT_OPENED", "TAXIMAP_OPENED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
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
end

function Wanderlust:OnLogin()
	self:Apply()
end

function Wanderlust:OnOptionChanged()
	self:Apply()
end

Wanderlust.options = {
	{ key = "enabled", type = "toggle", name = L.WANDERLUST_TITLE, desc = L.WANDERLUST_DESC },
	{ key = "minimapMouseover", type = "toggle", name = L.WANDERLUST_MINIMAP, desc = L.WANDERLUST_MINIMAP_DESC, parent = "enabled" },
	{ key = "showProfessions", type = "toggle", name = L.WANDERLUST_PROFESSIONS, desc = L.WANDERLUST_PROFESSIONS_DESC, parent = "enabled" },
}

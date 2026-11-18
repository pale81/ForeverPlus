-- Hide the interface after a quiet minute; the next combat brings it back.
local _, ns = ...
local L = ns.L

local Wanderlust = ns:NewModule("Wanderlust", {
	title = L.WANDERLUST_TITLE,
	defaults = { enabled = false },
})

local QUIET_SECONDS = 60
local timer, hidUI, hooked, restoring

local function CancelTimer()
	if timer then
		timer:Cancel()
		timer = nil
	end
end

local function RestoreUI()
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
	local pending
	pending = ns.NewTimer("Wanderlust: hide interface", QUIET_SECONDS, function()
		if timer ~= pending then
			return
		end
		timer = nil
		if Wanderlust.db.enabled and not InCombatLockdown() and UIParent:IsShown() then
			hidUI = true
			SetUIVisibility(false)
		end
	end)
	timer = pending
end

local function OnUIShown()
	-- Escape, Toggle UI and other features give the player another full minute.
	-- A later manual hide now belongs to the player, not to Wanderlust.
	hidUI = nil
	if not restoring then
		StartTimer()
	end
end

local function Stop()
	CancelTimer()
	RestoreUI()
end

function Wanderlust:Apply()
	local enabled = self.db.enabled
	if enabled and not hooked then
		hooked = true
		UIParent:HookScript("OnShow", ns.Measured("Wanderlust: interface shown", OnUIShown))
	end
	self:ToggleEvent("PLAYER_REGEN_DISABLED", enabled, Stop)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", enabled, StartTimer)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", enabled, StartTimer)
	self:ToggleEvent("PLAYER_LEAVING_WORLD", enabled, Stop)
	self:ToggleEvent("PLAYER_LOGOUT", enabled, Stop)
	if enabled then
		StartTimer()
	else
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
}

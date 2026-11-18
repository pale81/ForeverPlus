-- Deterministic time and native visibility events, isolated from the other modules.
local root = (arg and arg[1]) or ".."
local now, combat, visibilityCalls, hooks = 0, false, 0, 0
local timers, events = {}, {}
local ui = { shown = true }
function ui:IsShown() return self.shown end
function ui:HookScript(script, fn)
	assert(script == "OnShow")
	hooks = hooks + 1
	self.onShow = fn
end

local function SetVisibility(shown)
	visibilityCalls = visibilityCalls + 1
	local changed = ui.shown ~= shown
	ui.shown = shown
	if changed and shown and ui.onShow then ui.onShow() end
end

local ns = { L = { WANDERLUST_TITLE = "Wanderlust", WANDERLUST_DESC = "description" } }
function ns:NewModule(name, spec)
	assert(name == "Wanderlust")
	self.module = spec
	spec.db = { enabled = spec.defaults.enabled }
	function spec:ToggleEvent(event, enabled, fn) events[event] = enabled and fn or nil end
	return spec
end
function ns.Measured(_, fn) return fn end
function ns.NewTimer(_, delay, fn)
	local timer = { at = now + delay, callback = fn }
	function timer:Cancel() self.cancelled = true end
	timers[#timers + 1] = timer
	return timer
end

local chunk = assert(loadfile(root .. "/Modules/Wanderlust.lua"))
setfenv(chunk, setmetatable({
	UIParent = ui,
	SetUIVisibility = SetVisibility,
	InCombatLockdown = function() return combat end,
}, { __index = _G }))
chunk("ForeverPlus", ns)
local module = ns.module
local function Enable(enabled)
	module.db.enabled = enabled
	module:OnOptionChanged("enabled", enabled)
end
local function Fire(event)
	if events[event] then events[event](module, event) end
end
local function Advance(seconds)
	now = now + seconds
	for _, timer in ipairs(timers) do
		if not timer.cancelled and not timer.fired and timer.at <= now then
			timer.fired = true
			timer.callback()
		end
	end
end
local function Pending()
	local count = 0
	for _, timer in ipairs(timers) do
		if not timer.cancelled and not timer.fired then count = count + 1 end
	end
	return count
end

module:OnLogin()
assert(not module.db.enabled and not next(events) and hooks == 0 and #timers == 0,
	"disabled by default, with no timer, hook or events")
Enable(true)
assert(hooks == 1 and Pending() == 1, "enabling starts a single timer")
Advance(59)
assert(ui.shown and visibilityCalls == 0, "the interface stays visible for the first 59 seconds")
Advance(1)
assert(not ui.shown and visibilityCalls == 1 and Pending() == 0, "one full quiet minute hides the interface once")
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(ui.shown and Pending() == 0, "combat restores the interface during lockdown without another timer")
Advance(120)
assert(ui.shown, "combat never hides the interface")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(30)
local interrupted = timers[#timers]
combat = true
Fire("PLAYER_REGEN_DISABLED")
interrupted.callback()
assert(ui.shown and interrupted.cancelled and Pending() == 0, "combat cancels the countdown and rejects stale callbacks")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(59)
assert(ui.shown, "a new fight resets the entire minute")
Advance(1)
assert(not ui.shown, "the new minute expires after combat")

SetVisibility(true)
Advance(59)
assert(ui.shown, "manual recovery gives the player a full minute")
Advance(1)
assert(not ui.shown, "manual recovery still permits the next automatic hide")
SetVisibility(true)
SetVisibility(false)
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(not ui.shown, "a later manual hide is not restored by Wanderlust")
Enable(false)
assert(not ui.shown and not next(events) and Pending() == 0, "disabling preserves a manually hidden interface")

combat = false
Enable(true)
Advance(60)
assert(not ui.shown and Pending() == 0, "enabling leaves an already-hidden interface alone")
SetVisibility(true)
Advance(60)
assert(not ui.shown, "another feature restoring the interface starts a fresh countdown")
Enable(false)
assert(ui.shown and Pending() == 0, "disabling restores only an automatic hide")
local calls = visibilityCalls
Advance(120)
assert(ui.shown and visibilityCalls == calls, "nothing runs after disabling")

combat = true
Enable(true)
assert(Pending() == 0 and ui.shown, "enabling during combat waits for combat to end")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(59)
Fire("PLAYER_ENTERING_WORLD")
Advance(59)
assert(ui.shown, "entering the world starts a fresh minute")
Advance(1)
assert(not ui.shown, "world entry countdown expires normally")
Fire("PLAYER_LEAVING_WORLD")
assert(ui.shown and Pending() == 0, "leaving the world restores the interface without restarting")
Fire("PLAYER_ENTERING_WORLD")
Advance(60)
Fire("PLAYER_LOGOUT")
assert(ui.shown and Pending() == 0, "logout restores the interface and stops the timer")
Enable(false)
Enable(true)
local pending = timers[#timers]
Enable(false)
pending.callback()
assert(ui.shown and pending.cancelled and Pending() == 0 and hooks == 1,
	"disabling cancels pending work, stale callbacks are harmless and the hook is installed once")

Enable(true)
combat = true
Advance(60)
assert(ui.shown, "a countdown callback checks lockdown even before the combat event arrives")
combat = false
Enable(false)
print("Wanderlust timing, combat, manual visibility and lifecycle OK")

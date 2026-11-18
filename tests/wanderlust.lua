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

local ns = { L = { WANDERLUST_TITLE = "Wanderlust", WANDERLUST_DESC = "description",
	WANDERLUST_PROFESSIONS = "Professions", WANDERLUST_PROFESSIONS_DESC = "description" } }
function ns:NewModule(name, spec)
	assert(name == "Wanderlust")
	self.module = spec
	spec.db = { enabled = spec.defaults.enabled, showProfessions = spec.defaults.showProfessions }
	function spec:ToggleEvent(event, enabled, fn) events[event] = enabled and fn or nil end
	return spec
end
function ns.Measured(_, fn) return fn end
function ns.After(_, _, fn) fn() end
function ns.NewTimer(_, delay, fn)
	local timer = { at = now + delay, callback = fn }
	function timer:Cancel() self.cancelled = true end
	timers[#timers + 1] = timer
	return timer
end

local globals = {}
local secret = {}
local castingTrade, channelTrade = false, false
local spellBook = { { spellID = 18248, name = "Fishing" }, { spellID = 8613, name = "Skinning" } }
local names = { [7620] = "Fishing", [8613] = "Skinning" }
local recipeReads, bookReads = 0, 0
function ns.Secret(value) return rawequal(value, secret) end
function ns.Number(value, fallback) return type(value) == "number" and value or fallback end
local chunk = assert(loadfile(root .. "/Modules/Wanderlust.lua"))
setfenv(chunk, setmetatable({
	_G = globals,
	UIParent = ui,
	SetUIVisibility = SetVisibility,
	InCombatLockdown = function() return combat end,
	UnitCastingInfo = function() return nil, nil, nil, nil, nil, castingTrade end,
	UnitChannelInfo = function() return nil, nil, nil, nil, nil, channelTrade end,
	GetProfessions = function() return nil, 2 end, -- absent profession slots must not end the scan
	GetProfessionInfo = function() return "Profession", nil, nil, nil, #spellBook, 0 end,
	Enum = { SpellBookSpellBank = { Player = 0 } },
	C_SpellBook = { GetSpellBookItemInfo = function(slot)
		bookReads = bookReads + 1
		return spellBook[slot]
	end },
	C_Spell = { GetSpellName = function(id) return names[id] end },
	C_TradeSkillUI = { GetProfessionInfoByRecipeID = function(id)
		recipeReads = recipeReads + 1
		return { professionID = id == 2001 and 171 or 0 }
	end },
}, { __index = _G }))
chunk("ForeverPlus", ns)
local module = ns.module
local function Enable(enabled)
	module.db.enabled = enabled
	module:OnOptionChanged("enabled", enabled)
end
local function Fire(event, ...)
	if events[event] then events[event](module, event, ...) end
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
assert(module.db.showProfessions == false, "profession abilities are excluded by default")
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

Enable(true)
Advance(60)
assert(not ui.shown, "automatic hiding still works before a conversation")
local questShown = true
globals.QuestFrame = { IsShown = function() return questShown end }
Fire("QUEST_DETAIL")
assert(ui.shown and Pending() == 0, "opening a quest restores the automatically hidden interface")
Advance(120)
assert(ui.shown, "an open quest keeps its interface visible")
questShown = false
Fire("QUEST_FINISHED")
Advance(59)
assert(ui.shown, "closing a quest gives another full minute")
Advance(1)
assert(not ui.shown, "automatic hiding resumes after the quest closes")
Fire("GOSSIP_SHOW")
assert(ui.shown, "opening gossip restores automatic hiding too")
questShown = true
Fire("QUEST_DETAIL")
Fire("GOSSIP_CLOSED")
Advance(120)
assert(ui.shown and Pending() == 0, "switching from gossip to a quest never starts a hide timer")
questShown = false
Fire("QUEST_FINISHED")
SetVisibility(false)
Fire("QUEST_DETAIL")
assert(not ui.shown, "a conversation does not undo a manual UI hide")
Enable(false)

SetVisibility(true)
Enable(true)
Advance(60)
for _, unit in ipairs({ "pet", "party1", "target", secret }) do
	Fire("UNIT_SPELLCAST_START", unit, "cast", 1001)
	Fire("UNIT_SPELLCAST_SUCCEEDED", unit, "cast", 1002)
end
assert(not ui.shown and bookReads == 0, "other units and secret unit tokens do not reveal the interface or scan professions")
Fire("UNIT_SPELLCAST_START", "player", "cast", 1001)
assert(ui.shown and Pending() == 1, "a player ability reveals the interface at cast start")
Advance(59)
assert(ui.shown, "casting resets the minute")
Advance(1)
assert(not ui.shown, "the interface hides again one minute after a cast")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant", 1002)
assert(ui.shown, "instant abilities reveal the interface without a cast-start event")
Advance(59)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant2", 1002)
Advance(59)
assert(ui.shown, "another ability while visible starts a fresh minute")
Advance(1)
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "channel", 1003)
assert(ui.shown, "ordinary channeled abilities reveal the interface at channel start")
Advance(60)

castingTrade = true
Fire("UNIT_SPELLCAST_START", "player", "craft", 2002)
castingTrade = false
Fire("SKILL_LINES_CHANGED")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "craft", 2002)
assert(not ui.shown, "native tradeskill completion stays excluded after a skill-up, even without recipe data")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "recipe", 2001)
assert(not ui.shown, "instant crafting recipes are excluded through profession data")
channelTrade = true
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "trade-channel", 2003)
channelTrade = false
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "trade-channel", 2003)
assert(not ui.shown, "native profession channels and their completion are excluded")
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "fish", 7620)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "fish", 7620)
Fire("UNIT_SPELLCAST_START", "player", "skin", 8613)
assert(not ui.shown, "learned gathering spells and fishing with a different rank ID are excluded")
local reads = recipeReads
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "fish2", 7620)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "recipe2", 2001)
assert(recipeReads == reads and bookReads == 4, "profession classification is cached instead of rescanning on each cast")

SetVisibility(true)
Advance(59)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "recipe3", 2001)
Advance(1)
assert(not ui.shown, "an excluded profession does not postpone automatic hiding while visible")
spellBook[#spellBook + 1] = { spellID = 3001, name = "New profession" }
Fire("SPELLS_CHANGED")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "learned", 3001)
assert(not ui.shown, "learning a profession refreshes the cached spell list")
spellBook[#spellBook + 1] = { spellID = 3002, name = "Another profession" }
Fire("SKILL_LINES_CHANGED")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "skill", 3002)
assert(not ui.shown, "skill-line updates refresh the cached professions too")

module.db.showProfessions = true
module:OnOptionChanged("showProfessions", true)
reads = recipeReads
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "fish-option", 7620)
assert(ui.shown and recipeReads == reads and not events.SPELLS_CHANGED,
	"the profession option reveals the interface without any classification work")
Advance(59)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "recipe-option", 2001)
Advance(59)
assert(ui.shown, "included profession abilities restart the full minute")
Advance(1)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", secret, secret)
assert(ui.shown, "secret cast GUIDs and spell IDs are not compared or passed into spell lookups")
SetVisibility(false)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "manual", 1002)
assert(not ui.shown, "abilities preserve a manually hidden interface")
SetVisibility(true)
Advance(60)
combat = true
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "combat", secret)
assert(ui.shown and Pending() == 0, "a combat cast reveals automatic hiding without classifying restricted IDs")
combat = false
Enable(false)
Fire("UNIT_SPELLCAST_START", "player", "disabled", 1001)
assert(not next(events) and Pending() == 0, "disabling unregisters all ability and profession events")
print("Wanderlust timing, abilities, professions, interactions and lifecycle OK")

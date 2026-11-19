-- Deterministic time and native visibility events, isolated from the other modules.
local root = (arg and arg[1]) or ".."
local now, combat, visibilityCalls, hooks = 0, false, 0, 0
local timers, tickers, events = {}, {}, {}
local globals = {}
local target, focus, bagsOpen, editMode, chatActive = false, false, false, false, nil
local closeSounds = 0
local panelWindows, specialFrames = {}, {}
local regenQueue, peekDriver = {}, nil
local cursorX, cursorY = 0, 0
local ui = { shown = true, alpha = 0.9 }
function ui:IsShown() return self.shown end
function ui:GetAlpha() return self.alpha end
function ui:SetAlpha(alpha) self.alpha = alpha end
function ui:HookScript(script, fn)
	assert(script == "OnShow")
	hooks = hooks + 1
	self.onShow = fn
end

-- The cluster stays in the interface; only its parent-alpha flag changes.
local cluster = { ignore = false }
function cluster:IsForbidden() return false end
function cluster:IsIgnoringParentAlpha() return self.ignore end
function cluster:SetIgnoreParentAlpha(ignore)
	assert(not combat, "the minimap's parent-alpha flag only changes outside combat")
	self.ignore = ignore
end
function cluster:SetParent() error("the minimap must stay in the interface") end
-- 100 x 100 at (1000, 600) with a UI scale of 0.8: (800, 480) to (880, 560) in cursor coordinates.
local map = {}
function map:GetRect() return 1000, 600, 100, 100 end
function map:GetEffectiveScale() return 0.8 end
local function Peeking() return ui.shown and ui.alpha == 0 and cluster.ignore end
-- BankFrame_Open sets the portrait, then shows the frame. Its OnShow buys a free first tab (protected); it only
-- stays Blizzard's own if the interface is already visible at Show, not revealed later by Wanderlust.
local bank = { shown = false, closeSound = true }
function bank:IsShown() return self.shown end
function bank:SetPortraitToUnit() end
local function OpenBank()
	bank:SetPortraitToUnit("npc")
	bank.shown = true
	return ui.shown
end

local function SetVisibility(shown)
	visibilityCalls = visibilityCalls + 1
	local changed = ui.shown ~= shown
	if changed and not shown then
		-- Model Blizzard's target-lost and window-close sounds on parent hiding.
		if target or focus or bagsOpen then closeSounds = closeSounds + 1 end
		for _, frame in pairs(globals) do
			if frame.closeSound and frame:IsShown() then closeSounds = closeSounds + 1 end
		end
	end
	ui.shown = shown
	if changed and shown and ui.onShow then ui.onShow() end
end

local ns = { L = { WANDERLUST_TITLE = "Wanderlust", WANDERLUST_DESC = "description",
	WANDERLUST_MINIMAP = "Minimap", WANDERLUST_MINIMAP_DESC = "description",
	WANDERLUST_PROFESSIONS = "Professions", WANDERLUST_PROFESSIONS_DESC = "description" } }
function ns:NewModule(name, spec)
	assert(name == "Wanderlust")
	self.module = spec
	spec.db = { enabled = spec.defaults.enabled, showProfessions = spec.defaults.showProfessions,
		minimapMouseover = spec.defaults.minimapMouseover }
	function spec:ToggleEvent(event, enabled, fn) events[event] = enabled and fn or nil end
	return spec
end
function ns.RunOutOfCombat(fn)
	if combat then regenQueue[#regenQueue + 1] = fn else fn() end
end
function ns.Measured(_, fn) return fn end
function ns.SetUpdate(frame, _, fn) frame.onUpdate = fn end
function ns:IsEditModeActive() return editMode end
function ns.After(_, _, fn) fn() end
function ns.NewTimer(_, delay, fn)
	local timer = { at = now + delay, callback = fn }
	function timer:Cancel() self.cancelled = true end
	timers[#timers + 1] = timer
	return timer
end

function ns.NewTicker(_, interval, fn)
	local ticker = { at = now + interval, interval = interval, callback = fn }
	function ticker:Cancel() self.cancelled = true end
	tickers[#tickers + 1] = ticker
	return ticker
end

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
	BankFrame = bank,
	hooksecurefunc = function(object, method, hook)
		local original = object[method]
		object[method] = function(...)
			original(...)
			hook(...)
		end
	end,
	MinimapCluster = cluster,
	Minimap = map,
	GetCursorPosition = function() return cursorX, cursorY end,
	CreateFrame = function(_, _, parent)
		assert(not parent and not peekDriver, "one parentless driver checks the cursor")
		peekDriver = { shown = true }
		function peekDriver:SetShown(shown) self.shown = shown end
		return peekDriver
	end,
	SetUIVisibility = SetVisibility,
	InCombatLockdown = function() return combat end,
	UnitExists = function(unit) return unit == "target" and target or unit == "focus" and focus end,
	IsAnyBagOpen = function() return bagsOpen end,
	ChatEdit_GetActiveWindow = function() return chatActive end,
	UIPanelWindows = panelWindows,
	UISpecialFrames = specialFrames,
	PlaySound = function() error("Wanderlust must not add any interface sound") end,
	SetCVar = function() error("Wanderlust must not mute game audio") end,
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
	if event == "PLAYER_REGEN_ENABLED" then
		local queue = regenQueue
		regenQueue = {}
		for _, fn in ipairs(queue) do fn() end
	end
	if events[event] then events[event](module, event, ...) end
end
local function Advance(seconds)
	local deadline = now + seconds
	while true do
		local nextTimer
		for _, list in ipairs({ timers, tickers }) do
			for _, pending in ipairs(list) do
				if not pending.cancelled and not pending.fired and pending.at <= deadline
					and (not nextTimer or pending.at < nextTimer.at) then nextTimer = pending end
			end
		end
		if not nextTimer then break end
		now = nextTimer.at
		if nextTimer.interval then nextTimer.at = now + nextTimer.interval
		else nextTimer.fired = true end
		nextTimer.callback()
	end
	now = deadline
end
local function Pending()
	local count = 0
	for _, timer in ipairs(timers) do
		if not timer.cancelled and not timer.fired then count = count + 1 end
	end
	return count
end
local function Tick()
	if peekDriver and peekDriver.shown then peekDriver.onUpdate(peekDriver, 0.1) end
end
local function Over(over)
	cursorX, cursorY = over and 840 or 900, over and 520 or 520
	Tick()
end

module:OnLogin()
assert(not module.db.enabled and not next(events) and hooks == 0 and #timers == 0,
	"disabled by default, with no timer, hook or events")
assert(module.db.showProfessions == false, "profession abilities are excluded by default")
assert(module.db.minimapMouseover == true, "Wanderlust enables minimap mouseover by default")
Enable(true)
assert(hooks == 1 and Pending() == 1, "enabling starts a single timer")
Advance(59)
assert(ui.shown and visibilityCalls == 0, "the interface stays visible for the first 59 seconds")
Advance(1)
assert(not ui.shown and visibilityCalls == 1 and Pending() == 0, "one full quiet minute hides the interface once")
assert(peekDriver and peekDriver.shown and not Peeking(), "a hidden interface watches the minimap area without showing anything")
Over(false)
assert(not ui.shown and visibilityCalls == 1, "the cursor away from the minimap leaves the interface hidden")
Over(true)
assert(Peeking() and visibilityCalls == 2 and Pending() == 0,
	"the cursor over the minimap brings the interface back see-through, only the minimap visible, without a new minute")
Over(true)
assert(Peeking() and visibilityCalls == 2, "staying over the minimap changes nothing")
Over(false)
assert(not ui.shown and ui.alpha == 0.9 and not cluster.ignore and visibilityCalls == 3,
	"leaving the minimap hides the interface again, then restores its alpha and the minimap's flag")
Over(true)
assert(Peeking(), "the minimap appears again on the next visit")
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(ui.shown and Pending() == 0, "combat restores the interface during lockdown without another timer")
assert(ui.alpha == 0.9 and not peekDriver.shown, "combat over the minimap makes the whole interface visible again")
Advance(120)
assert(ui.shown, "combat never hides the interface")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(not cluster.ignore, "the minimap's parent-alpha flag is restored once combat ends")
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
assert(ui.alpha == 0.9 and not peekDriver.shown, "manually revealing the interface ends the minimap watch")
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

Enable(true)
Advance(60)
target = true
Fire("PLAYER_TARGET_CHANGED")
assert(ui.shown and Pending() == 0, "selecting a target immediately restores automatic hiding")
Advance(120)
assert(ui.shown, "the interface never hides with a selected target")
target = false
Fire("PLAYER_TARGET_CHANGED")
Advance(59)
assert(ui.shown, "clearing the target begins a full new minute")
Advance(1)
assert(not ui.shown, "hiding resumes after clearing the target")
focus = true
Fire("PLAYER_FOCUS_CHANGED")
Advance(120)
assert(ui.shown and Pending() == 0, "a focus target also prevents its target-lost sound on parent hiding")
focus = false
Fire("PLAYER_FOCUS_CHANGED")
Advance(60)
target = secret
Fire("PLAYER_TARGET_CHANGED")
Advance(120)
assert(ui.shown, "a restricted target-existence result safely keeps the interface visible")
target = false
Fire("PLAYER_TARGET_CHANGED")
Advance(60)
Enable(false)

local function Window(name, registry)
	local frame = { shown = false, closeSound = true }
	function frame:IsShown() return self.shown end
	globals[name] = frame
	if registry == "panel" then panelWindows[name] = {}
	elseif registry == "special" then specialFrames[#specialFrames + 1] = name end
	return frame
end
local function CheckWindow(frame, openEvent, closeEvent)
	Enable(true)
	Advance(60)
	assert(not ui.shown, "the test window starts with an automatically hidden interface")
	frame.shown = true
	if openEvent then Fire(openEvent) else Advance(1) end
	assert(ui.shown and Pending() == 0, "opening a window restores and holds the interface")
	Advance(120)
	assert(ui.shown, "the interface remains visible for as long as the window is open")
	frame.shown = false
	if closeEvent then Fire(closeEvent) else Advance(1) end
	Advance(59)
	assert(ui.shown, "closing a window gives a full fresh minute")
	Advance(1)
	assert(not ui.shown, "hiding resumes one minute after the window closes")
	Enable(false)
end

local map = Window("WorldMapFrame")
CheckWindow(map)
CheckWindow(Window("AuctionHouseFrame", "panel"), "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED")
CheckWindow(Window("BankFrame", "panel"), "BANKFRAME_OPENED", "BANKFRAME_CLOSED")
CheckWindow(Window("MailFrame", "panel"), "MAIL_SHOW", "MAIL_CLOSED")
CheckWindow(Window("StaticPopup1"))
CheckWindow(Window("SettingsPanel"))
CheckWindow(Window("ForeverPlusReadable"))
Enable(true)
-- Register these after enabling: addon windows are often created only on first use.
Advance(60)
local latePanel = Window("TestLateLoadedPanel", "panel")
latePanel.shown = true
Advance(1)
assert(ui.shown and Pending() == 0, "a newly registered panel is discovered without reapplying settings")
latePanel.shown = false
Advance(1)
Advance(60)
local addonWindow = Window("TestAddonWindow", "special")
addonWindow.shown = true
Advance(1)
assert(ui.shown and Pending() == 0, "a newly created Escape-registered addon window is discovered too")
addonWindow.shown = false
Advance(1)
Enable(false)
CheckWindow(latePanel)
CheckWindow(addonWindow)

Enable(true)
Advance(60)
bagsOpen = true
Fire("BAG_OPEN", 0)
Advance(120)
assert(ui.shown and Pending() == 0, "open bags keep the interface visible")
Fire("BAG_CLOSED", 1)
Advance(120)
assert(ui.shown and Pending() == 0, "closing one bag cannot restart hiding while another is open")
bagsOpen = false
Fire("BAG_CLOSED", 0)
Advance(59)
assert(ui.shown, "closing the last bag starts a new minute")
Advance(1)
assert(not ui.shown, "the interface hides after the last bag closes")
Enable(false)

Enable(true)
Advance(59)
map.shown = true
Advance(1)
assert(ui.shown and Pending() == 0, "a window opened at the timer deadline is checked again before hiding")
addonWindow.shown = true
map.shown = false
Advance(120)
assert(ui.shown and Pending() == 0, "closing one window keeps another open window protected")
addonWindow.shown = false
Advance(1)
Advance(59)
assert(ui.shown, "the minute restarts only after all windows close")
Advance(1)
assert(not ui.shown, "hiding resumes after all windows are closed")
Enable(false)

chatActive = Window("TestChatInput")
CheckWindow(chatActive)
chatActive = nil
Enable(true)
Advance(60)
editMode = true
Advance(1)
Advance(120)
assert(ui.shown and Pending() == 0, "editing the interface keeps it visible")
editMode = false
Advance(1)
Advance(60)
assert(not ui.shown, "leaving edit mode resumes hiding after a new minute")
Enable(false)

local forbidden = Window("TestForbiddenPanel", "panel")
forbidden.shown, forbidden.closeSound = true, false
function forbidden:IsForbidden() return true end
function forbidden:IsShown() error("forbidden frames must not be inspected") end
Enable(true)
Advance(60)
assert(not ui.shown, "forbidden frames are skipped without accessing their visibility")
Enable(false)
assert(closeSounds == 0, "automatic hiding never triggers a target-lost or window-close sound")
for _, ticker in ipairs(tickers) do assert(ticker.cancelled, "disabling stops the window activity ticker") end

panelWindows.TestForbiddenPanel = nil
module.db.minimapMouseover = false
Enable(true)
Advance(60)
Over(true)
assert(not ui.shown and not peekDriver.shown, "turning minimap mouseover off hides the entire interface, minimap included")
module.db.minimapMouseover = true
module:OnOptionChanged("minimapMouseover", true)
Over(true)
assert(Peeking(), "the minimap option can be enabled while Wanderlust is already hidden")
module.db.minimapMouseover = false
module:OnOptionChanged("minimapMouseover", false)
assert(not ui.shown and ui.alpha == 0.9 and not cluster.ignore and not peekDriver.shown,
	"turning off minimap mouseover hides the see-through interface again and restores everything")
Enable(false)
assert(ui.shown and ui.alpha == 0.9, "disabling restores the interface")

module.db.minimapMouseover = true
Enable(true)
Advance(60)
Over(true)
local menu = Window("TestMenuPanel", "panel")
menu.shown = true -- Escape over the see-through interface opens a menu
Tick()
assert(ui.shown and ui.alpha == 0.9 and not cluster.ignore and not peekDriver.shown,
	"a window opened over the see-through interface brings the whole interface back at once")
menu.shown = false
panelWindows.TestMenuPanel, globals.TestMenuPanel = nil, nil
Advance(1)
Advance(60)
Over(true)
assert(Peeking(), "hiding resumes after the window closes")
SetVisibility(false) -- the player's own Toggle UI over the minimap
Over(true)
assert(not ui.shown and ui.alpha == 0.9 and not cluster.ignore and not peekDriver.shown,
	"a manual hide during the minimap view stays hidden and is no longer Wanderlust's")
Over(true)
assert(not ui.shown, "the minimap no longer reveals an interface the player hid")
SetVisibility(true)
Advance(60)
Over(true)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant", 1002)
assert(ui.shown and ui.alpha == 0.9 and not cluster.ignore and Pending() == 1,
	"an ability over the see-through interface restores it fully and starts a new minute")
Advance(60)
Over(true)
Enable(false)
assert(ui.shown and ui.alpha == 0.9 and not cluster.ignore and not peekDriver.shown,
	"disabling during the minimap view restores the interface")
;(function()
	globals.BankFrame = bank
	Enable(true)
	Advance(60)
	assert(not ui.shown, "the interface is hidden before talking to the banker")
	assert(OpenBank(), "the interface is back before the bank window is shown, so its OnShow stays untainted")
	Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	assert(ui.shown and Pending() == 0, "the open bank holds the interface")
	bank.shown = false
	Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
	assert(Pending() == 1, "closing the bank starts a new minute")
	Enable(false)
	SetVisibility(false)
	assert(not OpenBank(), "with Wanderlust off, the bank leaves the player's own hide alone")
	bank.shown = false
	SetVisibility(true)
	globals.BankFrame = nil
end)()
print("Wanderlust timing, minimap mouseover, abilities, targets, windows and lifecycle OK")

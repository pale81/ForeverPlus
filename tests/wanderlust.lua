-- Deterministic time and native visibility events, isolated from the other modules.
local root = (arg and arg[1]) or ".."
local now, combat, visibilityCalls, hooks = 0, false, 0, 0
local timers, tickers, events = {}, {}, {}
local globals, ns = {}, nil
local target, focus, bagsOpen, editMode, chatActive = false, false, false, false, nil
local closeSounds = 0
local panelWindows, specialFrames = {}, {}
local regenQueue, peekDriver = {}, nil
local cursorX, cursorY = 0, 0
local ui = { shown = true, alpha = 0.9, children = {} }
function ui:IsShown() return self.shown end
function ui:GetAlpha() return self.alpha end
function ui:GetEffectiveScale() return 0.8 end
function ui:SetAlpha(alpha) self.alpha = alpha end
function ui:GetChildren() return unpack(self.children) end
function ui:HookScript(script, fn)
	assert(script == "OnShow" or script == "OnHide")
	if script == "OnShow" then
		hooks = hooks + 1
		self.onShow = fn
	else
		self.onHide = fn
	end
end

local world = { GetEffectiveScale = function() return 1 end }
local function ChatFrame(parent, shown, protected)
	return { parent = parent, shown = shown, alpha = 1,
		GetParent = function(self) return self.parent end,
		IsShown = function(self) return self.shown end,
		IsProtected = function() return protected end,
		IsForbidden = function() return false end,
		GetAlpha = function(self) return self.alpha end,
		SetAlpha = function(self, a) self.alpha = a end }
end
local chatDock = ChatFrame(ui, true)
local chatFrame = ChatFrame(ui, true)
local floatingTab = ChatFrame(ui, true)
local chatEdit = ChatFrame(ui, false)
local chatHost, chatInputOpened
globals.ChatFrame1 = chatFrame
globals.ChatFrame1Tab = ChatFrame(chatDock, true)
globals.ChatFrame1EditBox = chatEdit
globals.ChatFrame2 = ChatFrame(ui, false)
globals.ChatFrame3Tab = floatingTab
globals.ChatFrame4 = ChatFrame(ui, true, true)
globals.FCF_MinimizeFrame = function() globals.ChatFrame3Minimized = ChatFrame(ui, true) end
local bagToggleCalls = 0
local function BlizzardToggleBags()
	bagToggleCalls = bagToggleCalls + 1
	if not ui.shown then return end
	bagsOpen = not bagsOpen
	if events[bagsOpen and "BAG_OPEN" or "BAG_CLOSED"] then
		events[bagsOpen and "BAG_OPEN" or "BAG_CLOSED"](ns.module, bagsOpen and "BAG_OPEN" or "BAG_CLOSED", 0)
	end
end
globals.ToggleAllBags = BlizzardToggleBags
globals.ToggleBackpack = BlizzardToggleBags
globals.ToggleBag = BlizzardToggleBags

-- The cluster stays in the interface; only its parent-alpha flag changes.
local function PeekableFrame(rect)
	local frame = { ignore = false, shown = false, alpha = 1, children = {} }
	function frame:IsForbidden() return false end
	function frame:IsShown() return self.shown end
	function frame:GetAlpha() return self.alpha end
	function frame:SetAlpha(a) self.alpha = a end
	function frame:GetChildren() return unpack(self.children) end
	function frame:IsIgnoringParentAlpha() return self.ignore end
	function frame:SetIgnoreParentAlpha(ignore)
		assert(not combat, "parent-alpha flags only change outside combat")
		self.ignore = ignore
	end
	function frame:SetParent() error("peekable frames must stay in the interface") end
	if rect then
		function frame:GetRect() return rect[1], rect[2], rect[3], rect[4] end
		function frame:GetEffectiveScale() return 0.8 end
	end
	return frame
end
local cluster = PeekableFrame()
-- 100 x 100 at (1000, 600) with a UI scale of 0.8: (800, 480) to (880, 560) in cursor coordinates.
local minimap = { shown = true }
function minimap:IsForbidden() return false end
function minimap:IsShown() return self.shown end
function minimap:Show() self.shown = true end
function minimap:Hide() self.shown = false end
function minimap:GetRect() return 1000, 600, 100, 100 end
function minimap:GetEffectiveScale() return 0.8 end
-- 150 x 40 at (1000, 100) with a UI scale of 0.8: (800, 80) to (920, 112) in cursor coordinates.
local bagsBar = PeekableFrame({ 1000, 100, 150, 40 })
local combinedBags = PeekableFrame()
local bagFrame1 = PeekableFrame()
local bagFrame2 = PeekableFrame()
function bagFrame2:IsShown() return bagsOpen end
local bagContainer = PeekableFrame()
bagContainer.ContainerFrames = { bagFrame1, bagFrame2 }
local gameTooltip = PeekableFrame()
local shopping1 = PeekableFrame()
local shopping2 = PeekableFrame()
local stackSplit = PeekableFrame()
local dialogBubble = PeekableFrame()
local dialogState = { enabled = false, merchant = false, trainer = false, active = false, owned = {} }
local dialogModule = {
	IsBubbleActive = function() return dialogState.active end,
	GetBubbleFrame = function() return dialogBubble end,
	OwnsWindow = function(frame) return dialogState.active and frame ~= nil and dialogState.owned[frame] == true end,
	HandlesEvent = function(event, interactionType)
		if not dialogState.enabled or combat then return false end
		if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" or event == "QUEST_DETAIL"
			or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then return true end
		if event == "MERCHANT_SHOW" then return dialogState.merchant end
		if event == "TRAINER_SHOW" then return dialogState.trainer end
		if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
			if interactionType == 3 or interactionType == 4 then return true end
			if interactionType == 5 then return dialogState.merchant end
			if interactionType == 7 then return dialogState.trainer end
		end
		return false
	end,
}
local function Peeking() return ui.shown and ui.alpha == 0 and cluster.ignore end
local function PeekingFrame(frame) return ui.shown and ui.alpha == 0 and frame.ignore end
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
			if type(frame) == "table" and frame.closeSound and frame:IsShown() then closeSounds = closeSounds + 1 end
		end
	end
	ui.shown = shown
	if changed and shown and ui.onShow then ui.onShow() end
	if changed and not shown and ui.onHide then ui.onHide() end
end

ns = { L = { WANDERLUST_TITLE = "Wanderlust", WANDERLUST_DESC = "description",
	WANDERLUST_SOFT_HIDE = "Soft hide", WANDERLUST_SOFT_HIDE_DESC = "description",
	WANDERLUST_MINIMAP = "Minimap", WANDERLUST_MINIMAP_DESC = "description",
	WANDERLUST_HOVER_TEXT = "Mouseover text", WANDERLUST_HOVER_TEXT_DESC = "description",
	WANDERLUST_CHAT = "Chat", WANDERLUST_CHAT_DESC = "description",
	WANDERLUST_BAGS = "Bags", WANDERLUST_BAGS_DESC = "description",
	WANDERLUST_BUBBLES = "Dialog bubble", WANDERLUST_BUBBLES_DESC = "description",
	WANDERLUST_TELEPORTS = "Teleports", WANDERLUST_TELEPORTS_DESC = "description",
	WANDERLUST_TARGET = "Target", WANDERLUST_TARGET_DESC = "description",
	WANDERLUST_PROFESSIONS = "Professions", WANDERLUST_PROFESSIONS_DESC = "description" } }
local hoverDetached = false
local tooltip = { SetWanderlustHover = function(active) hoverDetached = active end }
local qolSuppressed, qolShownAlphas = false, {}
local qolModule = {
	SetWanderlustSuppressed = function(s) qolSuppressed = s end,
	ShownAlpha = function(frame) return qolShownAlphas[frame] end,
}
function ns:GetModule(name)
	if name == "Chat" then return self.chat end
	if name == "Teleports" then return self.teleports end
	if name == "Dialog" then return dialogModule end
	if name == "QoL" then return qolModule end
	assert(name == "Tooltip")
	return tooltip
end
function ns:NewModule(name, spec)
	if name == "Chat" then
		self.chat = spec
		return spec
	end
	if name == "Teleports" then
		self.teleports = spec
		return spec
	end
	assert(name == "Wanderlust")
	self.module = spec
	spec.db = { enabled = spec.defaults.enabled, softHide = spec.defaults.softHide,
		showOnTarget = spec.defaults.showOnTarget,
		showProfessions = spec.defaults.showProfessions, minimapMouseover = spec.defaults.minimapMouseover,
		hoverText = spec.defaults.hoverText, showChat = spec.defaults.showChat,
		showBags = spec.defaults.showBags, showBubbles = spec.defaults.showBubbles,
		hideTeleports = spec.defaults.hideTeleports }
	function spec:ToggleEvent(event, enabled, fn) events[event] = enabled and fn or nil end
	return spec
end
function ns.FormatToPattern() end -- Loading Chat here does not exercise its message filters.
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
local castDurationMS
local travelItemSpells = {}
local spellBook = { { spellID = 18248, name = "Fishing" }, { spellID = 8613, name = "Skinning" } }
local names = { [7620] = "Fishing", [8613] = "Skinning" }
local recipeReads, bookReads = 0, 0
function ns.Secret(value) return rawequal(value, secret) end
function ns.Number(value, fallback) return type(value) == "number" and value or fallback end
local chunk = assert(loadfile(root .. "/Modules/Wanderlust.lua"))
local env = setmetatable({
	_G = globals,
	UIParent = ui,
	WorldFrame = world,
	GeneralDockManager = chatDock,
	CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame3", "ChatFrame4" },
	FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent)
		assert(not frame:IsProtected(), "protected chat frames are never moved")
		assert(frame ~= chatActive or parent ~= ui or ui.shown, "moving the active edit box must preserve its focus")
		frame.parent = parent
	end },
	EventRegistry = { RegisterCallback = function(_, event, callback)
		assert(event == "ChatFrame.OnEditBoxShow")
		chatInputOpened = callback
	end },
	BankFrame = bank,
	hooksecurefunc = function(object, method, hook)
		if type(object) == "string" then object, method, hook = globals, object, method end
		local original = object[method]
		object[method] = function(...)
			original(...)
			hook(...)
		end
	end,
	MinimapCluster = cluster,
	Minimap = minimap,
	BagsBar = bagsBar,
	GameTooltip = gameTooltip,
	ShoppingTooltip1 = shopping1,
	ShoppingTooltip2 = shopping2,
	StackSplitFrame = stackSplit,
	GetTime = function() return now end,
	GetCursorPosition = function() return cursorX, cursorY end,
	CreateFrame = function(_, name, parent)
		if parent == world then
			assert(not chatHost, "one host keeps the chat frames visible")
			chatHost = {
				SetAllPoints = function(self, frame) self.anchor = frame end,
				SetScale = function(self, scale) self.scale = scale end,
				SetAlpha = function(self, alpha) self.alpha = alpha end,
			}
			return chatHost
		end
		if name == "ForeverPlusWanderlustEsc" and parent == ui then
			local guard = { shown = false }
			function guard:IsShown() return self.shown end
			function guard:SetSize() end
			function guard:EnableMouse() end
			function guard:SetScript(script, fn) if script == "OnHide" then self.onHide = fn end end
			function guard:Show() self.shown = true end
			function guard:Hide()
				local was = self.shown
				self.shown = false
				if was and self.onHide then self.onHide(self) end
			end
			function guard:SetShown(shown)
				if shown then self:Show() else self:Hide() end
			end
			globals[name] = guard
			return guard
		end
		assert(not parent and not peekDriver, "one parentless driver checks the cursor")
		peekDriver = { shown = true, shownCalls = 0 }
		function peekDriver:SetShown(shown)
			self.shown = shown
			self.shownCalls = self.shownCalls + 1
		end
		return peekDriver
	end,
	tinsert = table.insert,
	tContains = function(list, item)
		for _, value in ipairs(list) do
			if value == item then return true end
		end
		return false
	end,
	SetUIVisibility = SetVisibility,
	InCombatLockdown = function() return combat end,
	UnitExists = function(unit) return unit == "target" and target or unit == "focus" and focus end,
	-- Blizzard's IsAnyBagOpen builds its bag frame list on first use; called from addon code, that list stays
	-- tainted and every later bag check, also the bank's OnShow, runs tainted (blocked bank tab purchase).
	IsAnyBagOpen = function() error("Wanderlust must read the bag frames itself, not call IsAnyBagOpen") end,
	ContainerFrameCombinedBags = combinedBags,
	ContainerFrameContainer = bagContainer,
	ChatEdit_GetActiveWindow = function() return chatActive end,
	UIPanelWindows = panelWindows,
	UISpecialFrames = specialFrames,
	PlaySound = function() error("Wanderlust must not add any interface sound") end,
	SetCVar = function() error("Wanderlust must not mute game audio") end,
	UnitName = function() return "Player" end,
	wipe = function(t) for key in pairs(t) do t[key] = nil end end,
	UnitCastingInfo = function() return nil, nil, nil, 1000, castDurationMS and 1000 + castDurationMS, castingTrade end,
	UnitChannelInfo = function() return nil, nil, nil, 1000, castDurationMS and 1000 + castDurationMS, channelTrade end,
	GetProfessions = function() return nil, 2 end, -- absent profession slots must not end the scan
	GetProfessionInfo = function() return "Profession", nil, nil, nil, #spellBook, 0 end,
	Enum = { SpellBookSpellBank = { Player = 0 } },
	C_SpellBook = { GetSpellBookItemInfo = function(slot)
		bookReads = bookReads + 1
		return spellBook[slot]
	end },
	C_Spell = { GetSpellName = function(id) return names[id] end },
	C_Item = { GetItemSpell = function(itemID) return nil, travelItemSpells[itemID] end },
	C_TradeSkillUI = { GetProfessionInfoByRecipeID = function(id)
		recipeReads = recipeReads + 1
		return { professionID = id == 2001 and 171 or 0 }
	end },
}, { __index = _G })
local chatChunk = assert(loadfile(root .. "/Modules/Chat.lua"))
setfenv(chatChunk, env)("ForeverPlus", ns)
local teleportChunk = assert(loadfile(root .. "/Modules/Teleports.lua"))
setfenv(teleportChunk, env)("ForeverPlus", ns)
setfenv(chunk, env)
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
assert(module.db.softHide == true, "Wanderlust uses stutter-free soft hide by default")
assert(module.db.showProfessions == false, "profession abilities are excluded by default")
-- Exercise classic SetUIVisibility (Alt+Z) mode first, then soft-hide mode below.
module.db.softHide = false
assert(module.db.showOnTarget == false, "target selection does not interrupt Wanderlust by default")
assert(module.db.minimapMouseover == true, "Wanderlust enables minimap mouseover by default")
assert(module.db.hoverText == true and not hoverDetached, "the default keeps mouseover text only during an automatic hide")
assert(module.db.showChat == true and chatFrame.parent == ui, "chat is kept by default only during an automatic hide")
assert(module.db.showBags == true, "bags stay visible during Wanderlust by default")
assert(module.db.showBubbles == true, "dialog bubbles stay visible during Wanderlust by default")
assert(module.db.hideTeleports == true, "Wanderlust hides during longer teleports by default")
Enable(true)
assert(hooks == 1 and Pending() == 1, "enabling starts a single timer")
Advance(59)
assert(ui.shown and visibilityCalls == 0, "the interface stays visible for the first 59 seconds")
Advance(1)
assert(not ui.shown and visibilityCalls == 1 and Pending() == 0, "one full quiet minute hides the interface once")
assert(hoverDetached, "an automatic hide keeps mouseover text available by default")
assert(chatFrame.parent == chatHost and chatDock.parent == chatHost and chatEdit.parent == chatHost
	and floatingTab.parent == chatHost and globals.ChatFrame1Tab.parent == chatDock,
	"an automatic hide keeps the chat windows, dock, floating tabs and input in place")
assert(chatHost.anchor == ui and chatHost.scale == 0.8 and chatHost.alpha == 0.9 and not chatEdit.shown,
	"detaching chat preserves its position, scale, opacity and the state of the input")
assert(not globals.ChatFrame2.shown and globals.ChatFrame4.parent == ui,
	"hidden tabs stay hidden and protected frames are not moved")
assert(peekDriver and peekDriver.shown and not Peeking(), "a hidden interface watches the minimap area without showing anything")
Over(false)
assert(not ui.shown and visibilityCalls == 1, "the cursor away from the minimap leaves the interface hidden")
Over(true)
assert(Peeking() and visibilityCalls == 2 and Pending() == 0,
	"the cursor over the minimap brings the interface back see-through, only the minimap visible, without a new minute")
Over(true)
assert(Peeking() and visibilityCalls == 2, "staying over the minimap changes nothing")
Over(false)
assert(Peeking() and visibilityCalls == 2, "briefly leaving the minimap keeps the preview open")
Advance(0.1)
Over(true)
assert(Peeking() and visibilityCalls == 2, "returning quickly avoids a native visibility cycle")
Over(false)
Advance(0.3)
Tick()
assert(not ui.shown and ui.alpha == 0.9 and not cluster.ignore and visibilityCalls == 3,
	"leaving the minimap hides the interface again, then restores its alpha and the minimap's flag")
Over(true)
assert(Peeking(), "the minimap appears again on the next visit")
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(ui.shown and Pending() == 0, "combat restores the interface during lockdown without another timer")
assert(ui.alpha == 0.9 and not peekDriver.shown, "combat over the minimap makes the whole interface visible again")
assert(chatFrame.parent == ui and chatDock.parent == ui and chatEdit.parent == ui,
	"combat restores the native chat hierarchy")
Advance(120)
assert(ui.shown, "combat never hides the interface")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(not cluster.ignore, "the minimap's parent-alpha flag is restored once combat ends")
Over(false)
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

;(function()
	assert(not ns.teleports.IsTravelSpell(10059), "creating a group portal does not count as travelling")
	assert(not ns.teleports.IsTravelSpell(99001), "uncached transport items can be resolved later")
	travelItemSpells[18986] = 99001
	assert(ns.teleports.IsTravelSpell(99001), "the item use spell is resolved through the teleport menu entry")
	travelItemSpells[18986] = nil
	assert(ns.teleports.IsTravelSpell(99001), "a resolved teleport item spell remains cached")

	Enable(true)
	castDurationMS = 10000
	Fire("UNIT_SPELLCAST_START", "player", "portal", 10059)
	assert(ui.shown, "a long cast that creates a portal uses normal Wanderlust behaviour")
	castDurationMS = 1500
	Fire("UNIT_SPELLCAST_START", "player", "short", 3561)
	assert(ui.shown, "short teleports do not trigger the special hide")
	castDurationMS = 10000
	Fire("UNIT_SPELLCAST_START", "player", "hearthstone", 8690)
	assert(not ui.shown and hoverDetached and chatFrame.parent == chatHost,
		"a hearthstone hides the interface at cast start and uses the regular Wanderlust display options")
	Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "stale", 8690)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "unrelated", 1002)
	assert(not ui.shown, "other cast GUIDs do not end the teleport hide")
	Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "hearthstone", 8690)
	assert(ui.shown and Pending() == 1, "interrupting a cast immediately restores the interface and starts the minute")

	bagsOpen = true
	Fire("UNIT_SPELLCAST_START", "player", "from-bag", 8690)
	assert(ui.shown, "a hearthstone used from the bag waits for the bag to close")
	bagsOpen = false
	Fire("BAG_CLOSED")
	assert(not ui.shown, "closing the bag during the cast hides the interface")
	Fire("UNIT_SPELLCAST_STOP", "player", "from-bag", 8690)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "from-bag", 8690)
	assert(not ui.shown, "STOP and success do not flash the interface before loading")
	Fire("PLAYER_LEAVING_WORLD")
	assert(ui.shown and Pending() == 0, "a loading screen releases the hide and all timers")
	Fire("PLAYER_ENTERING_WORLD")
	Advance(59)
	assert(ui.shown, "arrival starts a full minute")

	Fire("UNIT_SPELLCAST_START", "player", "recall", 556)
	assert(not ui.shown, "Astral Recall triggers the same hide")
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "recall", 556)
	Advance(1)
	assert(ui.shown, "a successful same-map teleport recovers without a loading screen")

	Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "transport", 99001)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "transport", 99001)
	Advance(1)
	assert(not ui.shown, "a channel's early success does not end a longer teleport")
	Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "transport", 99001)
	Advance(1)
	assert(ui.shown, "the interface returns when the transport channel ends")

	Fire("UNIT_SPELLCAST_START", "player", "no-event", 3561)
	Advance(11)
	assert(ui.shown, "the interface recovers if no terminal event arrives")
	Fire("UNIT_SPELLCAST_START", "player", "option", 18960)
	assert(not ui.shown, "the Moonglade spell triggers the hide")
	module.db.hideTeleports = false
	module:OnOptionChanged("hideTeleports", false)
	assert(ui.shown and not events.UNIT_SPELLCAST_STOP, "turning off the option restores the interface and unregisters cast stops")
	Fire("UNIT_SPELLCAST_START", "player", "opt-out", 8690)
	assert(ui.shown, "an opted-out teleport uses normal Wanderlust behaviour")
	module.db.hideTeleports = true
	module:OnOptionChanged("hideTeleports", true)
	Fire("UNIT_SPELLCAST_START", "player", "manual", 8690)
	SetVisibility(true)
	SetVisibility(false)
	Fire("UNIT_SPELLCAST_FAILED", "player", "manual", 8690)
	assert(not ui.shown, "a player manually taking over visibility keeps ownership after the teleport ends")
	SetVisibility(true)
	Enable(false)
	castDurationMS = nil
end)()

;(function()
	-- Default: targeting or focusing does not interrupt Wanderlust; combat and non-teleport casts still restore it.
	Enable(true)
	assert(not events.PLAYER_TARGET_CHANGED and not events.PLAYER_FOCUS_CHANGED,
		"target and focus events stay unregistered when showOnTarget is off")
	target = true
	Advance(60)
	assert(not ui.shown, "selecting a target does not block automatic hiding by default")
	focus = true
	Advance(5)
	assert(not ui.shown, "a focus target also keeps Wanderlust hidden by default")
	castDurationMS = 10000
	Fire("UNIT_SPELLCAST_START", "player", "target-hearth", 8690)
	assert(not ui.shown, "teleports keep Wanderlust hidden even with a target")
	Fire("UNIT_SPELLCAST_START", "player", "target-cast", 1001)
	assert(ui.shown and Pending() == 1, "starting a non-teleport cast still restores the interface with a target")
	Advance(60)
	assert(not ui.shown, "hiding resumes with the target still selected")
	combat = true
	Fire("PLAYER_REGEN_DISABLED")
	assert(ui.shown and Pending() == 0, "entering combat still restores the interface with a target")
	combat = false
	Fire("PLAYER_REGEN_ENABLED")
	target, focus, castDurationMS = false, false, nil
	closeSounds = 0
	Enable(false)
end)()

module.db.showOnTarget = true
Enable(true)
Advance(60)
target = true
Fire("PLAYER_TARGET_CHANGED")
assert(ui.shown and Pending() == 0, "selecting a target immediately restores automatic hiding when enabled")
Advance(120)
assert(ui.shown, "the interface never hides with a selected target when enabled")
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
module.db.showOnTarget = false

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

module.db.showBags = false
Enable(true)
Advance(60)
bagsOpen = true
Fire("BAG_OPEN", 0)
Advance(120)
assert(ui.shown and ui.alpha == 0.9 and Pending() == 0, "open bags restore the full interface when showBags is off")
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
module.db.showBags = true

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
assert(not ui.shown and chatEdit.parent == chatHost, "the chat input can open while the interface is hidden")
chatEdit.shown, chatActive = true, chatEdit
chatInputOpened()
assert(ui.shown and chatEdit.parent == ui and Pending() == 0, "opening the chat input restores the interface immediately")
chatEdit.shown, chatActive = false, nil
Advance(1)
Advance(59)
assert(ui.shown, "the minute starts after closing the chat input")
Advance(1)
assert(not ui.shown, "Wanderlust can hide again after using the chat")
Enable(false)

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
module.db.showBags = false
Enable(true)
Advance(60)
Over(true)
assert(not ui.shown and not peekDriver.shown, "turning minimap and bag previews off hides the entire interface and stops polling")
module.db.minimapMouseover = true
module:OnOptionChanged("minimapMouseover", true)
Over(true)
assert(Peeking(), "the minimap option can be enabled while Wanderlust is already hidden")
assert(hoverDetached, "mouse text remains available during the minimap preview")
module.db.showChat = false
module:OnOptionChanged("showChat", false)
assert(Peeking() and chatFrame.parent == ui, "disabling chat preserves the minimap preview")
module.db.showChat = true
module:OnOptionChanged("showChat", true)
assert(Peeking() and chatFrame.parent == chatHost and chatHost.alpha == 0.9,
	"reenabling chat during the preview uses the original UI opacity")
globals.FCF_MinimizeFrame()
assert(globals.ChatFrame3Minimized.parent == chatHost, "newly minimized floating chat is still visible")
floatingTab.parent = chatDock -- the game may move a tab back into the dock while Wanderlust is active
module.db.hoverText = false
module:OnOptionChanged("hoverText", false)
assert(Peeking() and not hoverDetached, "disabling mouseover text while hidden leaves the minimap preview in place")
module.db.hoverText = true
module:OnOptionChanged("hoverText", true)
assert(Peeking() and hoverDetached, "reenabling mouseover text works while the interface is already hidden")
module.db.minimapMouseover = false
module:OnOptionChanged("minimapMouseover", false)
assert(not ui.shown and ui.alpha == 0.9 and not cluster.ignore and not peekDriver.shown,
	"turning off minimap mouseover hides the see-through interface again and restores everything")
Enable(false)
module.db.showBags = true
assert(ui.shown and ui.alpha == 0.9, "disabling restores the interface")
assert(not hoverDetached, "disabling Wanderlust restores normal mouseover text")
assert(chatFrame.parent == ui and globals.ChatFrame3Minimized.parent == ui and floatingTab.parent == chatDock,
	"restoring chat leaves changes to its dock alone")

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
assert(not hoverDetached, "manual hiding during the minimap preview hides the mouseover text too")
assert(chatFrame.parent == ui, "manual hiding during the minimap preview also hides chat")
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
Over(false)
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
;(function()
	-- Moving from the minimap onto the wider MinimapCluster rim (clock/buttons) keeps the peek active
	-- without hiding and re-showing UIParent.
	function cluster:GetRect() return 980, 580, 140, 140 end
	function cluster:GetEffectiveScale() return 0.8 end
	Enable(true)
	Advance(60)
	local before = visibilityCalls
	Over(true)
	assert(Peeking() and visibilityCalls == before + 1, "entering the minimap opens the preview once")
	cursorX, cursorY = 790, 520 -- inside MinimapCluster (784..896), outside Minimap (800..880)
	local shownBefore = peekDriver.shownCalls
	local originalIsForbidden = gameTooltip.IsForbidden
	local peekFrameChecks = 0
	gameTooltip.IsForbidden = function(self)
		peekFrameChecks = peekFrameChecks + 1
		return originalIsForbidden(self)
	end
	Tick()
	gameTooltip.IsForbidden = originalIsForbidden
	assert(Peeking() and visibilityCalls == before + 1, "hovering the minimap rim keeps the preview without thrashing")
	assert(peekFrameChecks == 1, "an active mouseover tick evaluates the preview frames exactly once")
	assert(peekDriver.shownCalls == shownBefore, "steady mouseover ticks do not reset the frame driver")
	cursorX, cursorY = 700, 520 -- outside both
	Advance(0.3)
	Tick()
	assert(not Peeking() and not ui.shown and visibilityCalls == before + 2, "leaving the full cluster hides again")
	Enable(false)

	-- If the cursor is already over the minimap when the 60 s timer expires, enter peek directly
	-- without a SetUIVisibility(false) -> SetUIVisibility(true) round-trip.
	Enable(true)
	cursorX, cursorY = 840, 520 -- inside Minimap
	local beforeDirect = visibilityCalls
	Advance(60)
	assert(Peeking() and visibilityCalls == beforeDirect,
		"hiding while cursor is over the minimap enters see-through peek without toggling SetUIVisibility")
	cursorX, cursorY = 700, 520
	Advance(0.3)
	Tick()
	assert(not Peeking() and not ui.shown and visibilityCalls == beforeDirect + 1,
		"leaving the minimap after a direct peek hides the interface once")
	Enable(false)
	cluster.GetRect, cluster.GetEffectiveScale = nil, nil
end)()
;(function()
	-- Bags and bag bar during Wanderlust (default on): mouseover bag bar, bag key peek, open bags alone.
	Enable(true)
	Advance(60)
	assert(not ui.shown and peekDriver.shown, "hidden Wanderlust watches the bag bar area")
	cursorX, cursorY = 850, 95 -- inside BagsBar (800..920, 80..112)
	Tick()
	assert(PeekingFrame(bagsBar) and PeekingFrame(gameTooltip) and not cluster.ignore,
		"hovering the bag bar shows only the bag bar and tooltip")
	cursorX, cursorY = 500, 500
	Tick()
	assert(not ui.shown and not bagsBar.ignore and not gameTooltip.ignore,
		"leaving the bag bar hides the interface again and restores parent-alpha flags")

	-- Pressing the bag key while UIParent is hidden reveals the bag bar without calling Blizzard's toggle from addon code.
	local callsBefore = bagToggleCalls
	globals.ToggleAllBags()
	assert(bagToggleCalls == callsBefore + 1 and not bagsOpen and PeekingFrame(bagsBar),
		"first bag key press opens a see-through bag-bar preview without re-invoking Blizzard's toggle")
	Advance(4)
	Tick()
	assert(not ui.shown and not bagsBar.ignore, "an unused bag-key preview expires back to hidden")

	globals.ToggleAllBags()
	assert(PeekingFrame(bagsBar), "bag key again prepares the untainted Blizzard toggle")
	globals.ToggleAllBags()
	assert(bagsOpen and PeekingFrame(combinedBags) and PeekingFrame(bagContainer) and PeekingFrame(bagFrame2)
		and PeekingFrame(bagsBar) and PeekingFrame(gameTooltip) and PeekingFrame(shopping1)
		and PeekingFrame(shopping2) and PeekingFrame(stackSplit) and not cluster.ignore,
		"second press opens the bags alone with tooltips and stack split while the rest stays hidden")
	Advance(120)
	assert(PeekingFrame(bagContainer), "open bags remain visible without restoring the rest of the interface")

	-- Casting a hearthstone from the bag stays in Wanderlust; a regular spell restores the full interface.
	castDurationMS = 10000
	Fire("UNIT_SPELLCAST_START", "player", "bag-hearth", 8690)
	assert(PeekingFrame(bagContainer), "casting a teleport from an open Wanderlust bag keeps the rest hidden")
	Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "bag-hearth", 8690)
	assert(ui.shown and ui.alpha == 0.9 and not bagContainer.ignore and Pending() == 0,
		"interrupting the teleport restores the interface and pauses the minute while bags stay open")
	bagsOpen = false
	Fire("BAG_CLOSED", 0)
	Advance(60)
	assert(not ui.shown, "hiding resumes one minute after closing the bag")

	-- Opening via mouseover + click, then closing returns silently to hidden.
	cursorX, cursorY = 850, 95
	Tick()
	globals.ToggleBackpack()
	assert(bagsOpen and PeekingFrame(bagContainer), "clicking/toggling during bag-bar hover opens the bags alone")
	cursorX, cursorY = 500, 500
	Tick()
	assert(PeekingFrame(bagContainer), "moving the cursor off the bag bar keeps open bags visible")
	globals.ToggleBackpack()
	Tick()
	assert(not bagsOpen and not ui.shown and not bagContainer.ignore and not bagsBar.ignore,
		"closing the last bag returns directly to hidden Wanderlust")

	-- Combat during open Wanderlust bags restores the full interface and defers flag cleanup until combat ends.
	globals.ToggleAllBags()
	globals.ToggleAllBags()
	assert(bagsOpen and PeekingFrame(bagContainer))
	combat = true
	Fire("PLAYER_REGEN_DISABLED")
	assert(ui.shown and ui.alpha == 0.9 and not peekDriver.shown, "combat restores the full interface from open Wanderlust bags")
	combat = false
	Fire("PLAYER_REGEN_ENABLED")
	assert(not bagContainer.ignore and not bagsBar.ignore, "bag parent-alpha flags are restored after combat")
	bagsOpen, castDurationMS = false, nil
	Enable(false)
end)()
;(function()
	-- Dialog bubble during Wanderlust (default on): keeps NPC conversations alone, falls back to full UI when needed.
	local gossipFrame = Window("GossipFrame", "panel")
	local merchantFrame = Window("MerchantFrame", "panel")
	local trainerFrame = Window("ClassTrainerFrame", "panel")
	dialogState.enabled, dialogState.merchant, dialogState.trainer = true, true, true

	Enable(true)
	Advance(60)
	assert(not ui.shown, "hidden before talking to an NPC")
	gossipFrame.shown = true
	dialogState.active, dialogState.owned[gossipFrame] = true, true
	Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
	Fire("GOSSIP_SHOW")
	module.OnDialogChanged()
	assert(PeekingFrame(dialogBubble) and PeekingFrame(gameTooltip) and PeekingFrame(shopping1)
		and not cluster.ignore and not bagsBar.ignore,
		"a conversation handled by the dialog bubble appears alone without revealing the rest of the UI")

	-- Opening bags alongside a merchant bubble shows both without revealing the rest of the interface.
	gossipFrame.shown, dialogState.owned[gossipFrame] = false, nil
	merchantFrame.shown, dialogState.owned[merchantFrame] = true, true
	Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
	Fire("MERCHANT_SHOW")
	module.OnDialogChanged()
	globals.ToggleAllBags()
	assert(bagsOpen and PeekingFrame(dialogBubble) and PeekingFrame(bagContainer),
		"bags open on the first press while a dialog bubble peek is active and share the preview")
	globals.ToggleAllBags()
	assert(not bagsOpen and PeekingFrame(dialogBubble) and not bagContainer.ignore,
		"closing the bags leaves the dialog bubble alone")

	-- Falling back to Blizzard's original window immediately restores the whole interface.
	dialogState.active, dialogState.owned[merchantFrame] = false, nil
	module.OnDialogChanged()
	assert(ui.shown and ui.alpha == 0.9 and not dialogBubble.ignore and Pending() == 0,
		"falling back from the bubble to Blizzard's window immediately restores the whole interface")
	merchantFrame.shown = false
	Fire("MERCHANT_CLOSED")
	Advance(60)
	assert(not ui.shown, "hiding resumes one minute after closing the original window")

	-- Closing a bubble conversation returns directly to hidden Wanderlust.
	trainerFrame.shown, dialogState.active, dialogState.owned[trainerFrame] = true, true, true
	Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 7)
	Fire("TRAINER_SHOW")
	module.OnDialogChanged()
	assert(PeekingFrame(dialogBubble), "trainer bubble stays alone during Wanderlust")
	trainerFrame.shown, dialogState.active, dialogState.owned[trainerFrame] = false, false, nil
	Fire("TRAINER_CLOSED")
	module.OnDialogChanged()
	assert(not ui.shown and not dialogBubble.ignore, "closing the bubble returns directly to hidden Wanderlust")

	-- Starting a spell while a bubble is open restores the full interface.
	gossipFrame.shown, dialogState.active, dialogState.owned[gossipFrame] = true, true, true
	Fire("GOSSIP_SHOW")
	module.OnDialogChanged()
	assert(PeekingFrame(dialogBubble))
	Fire("UNIT_SPELLCAST_START", "player", "bubble-cast", 1001)
	assert(ui.shown and ui.alpha == 0.9 and Pending() == 0,
		"a cast restores the full interface and pauses the minute while the conversation remains open")
	gossipFrame.shown, dialogState.active, dialogState.owned[gossipFrame] = false, false, nil
	Fire("GOSSIP_CLOSED")
	module.OnDialogChanged()
	Advance(59)
	assert(ui.shown, "closing the bubble on a visible interface restarts a full minute")
	Advance(1)
	assert(not ui.shown, "the interface hides again one minute after the bubble closes")

	-- Disabling merchant in Dialog or disabling showBubbles restores the full interface immediately.
	dialogState.merchant = false
	merchantFrame.shown = true
	Fire("MERCHANT_SHOW")
	assert(ui.shown and ui.alpha == 0.9, "an unhandled merchant window restores the full interface immediately")
	merchantFrame.shown = false
	Fire("MERCHANT_CLOSED")
	Advance(60)
	module.db.showBubbles = false
	module:OnOptionChanged("showBubbles", false)
	gossipFrame.shown, dialogState.active, dialogState.owned[gossipFrame] = true, true, true
	Fire("GOSSIP_SHOW")
	assert(ui.shown and ui.alpha == 0.9, "disabling showBubbles restores the full interface for conversations")
	gossipFrame.shown, dialogState.active, dialogState.owned[gossipFrame] = false, false, nil
	Fire("GOSSIP_CLOSED")
	module.db.showBubbles = true
	dialogState.enabled, dialogState.merchant, dialogState.trainer = false, false, false
	Enable(false)
end)()
;(function()
	-- Soft-hide mode (default): fades visible HUD children via SetAlpha(0) with zero SetUIVisibility calls.
	local actionBar = PeekableFrame()
	actionBar.shown, actionBar.alpha = true, 0.85
	local independentRegion = PeekableFrame()
	independentRegion.ignore, independentRegion.alpha = true, 0.75
	actionBar.GetRegions = function() return independentRegion end
	local hiddenPanel = PeekableFrame()
	hiddenPanel.shown, hiddenPanel.alpha = false, 1
	local minimapOverlay = PeekableFrame()
	minimapOverlay.shown, minimapOverlay.ignore, minimapOverlay.alpha = true, true, 0.9
	cluster.children = { minimapOverlay }
	cluster.shown, cluster.alpha = true, 1
	bagsBar.shown, bagsBar.alpha = true, 0 -- managed by QoL mouseover (idle at 0, visible at 1)
	qolShownAlphas[bagsBar] = 1
	local targetFrame = PeekableFrame()
	targetFrame.shown, targetFrame.alpha = false, 1
	local secretAuraChild = PeekableFrame()
	secretAuraChild.IsIgnoringParentAlpha = function() return secret end
	targetFrame.children = { secretAuraChild }
	local playerContainer = PeekableFrame()
	playerContainer.shown, playerContainer.alpha = true, 1
	local playerFrame = PeekableFrame()
	playerFrame.shown, playerFrame.alpha, playerFrame.PlayerFrameContainer = true, 1, playerContainer
	local portraitHidden = false
	ns.PortraitModes = { SetWanderlustHidden = function(hidden) portraitHidden = hidden end }
	globals.TargetFrame = targetFrame
	globals.PlayerFrame = playerFrame
	env.PlayerFrame = playerFrame
	ui.children = { actionBar, hiddenPanel, cluster, bagsBar, playerFrame, chatFrame, chatDock, gameTooltip }

	module.db.softHide = true
	Over(false)
	local visBefore = visibilityCalls
	Enable(true)
	Advance(60)
	assert(ui.shown and ui.alpha == 0.9 and visibilityCalls == visBefore,
		"soft hide keeps UIParent shown and never calls SetUIVisibility or UIParent:SetAlpha")
	assert(qolSuppressed and portraitHidden and module.IsSoftHidden(),
		"soft hide pauses QoL mouseover, hides portrait mode emblem and reports IsSoftHidden()")
	assert(actionBar.alpha == 0 and independentRegion.alpha == 0 and playerFrame.alpha == 0
		and playerContainer.alpha == 0 and targetFrame.alpha == 0 and hiddenPanel.alpha == 1,
		"visible HUD, independent regions, player portrait container and transient target frames fade to 0 while hidden panels stay untouched")
	assert(cluster.alpha == 0 and minimapOverlay.alpha == 0 and bagsBar.alpha == 0 and not minimap.shown,
		"minimap widget (and its blips), overlays and bags bar start hidden")
	assert(chatFrame.alpha == 1 and chatFrame.parent == ui and gameTooltip.alpha == 1,
		"chat stays in UIParent at full alpha and tooltips stay visible")

	-- Minimap mouseover reveals minimap + independent overlay without touching SetUIVisibility.
	Over(true)
	assert(cluster.alpha == 1 and minimapOverlay.alpha == 0.9 and minimap.shown
		and actionBar.alpha == 0 and visibilityCalls == visBefore,
		"minimap mouseover in soft-hide mode restores minimap widget and overlays with 0 SetUIVisibility calls")
	Over(false)
	Advance(0.3)
	Tick()
	assert(cluster.alpha == 0 and minimapOverlay.alpha == 0 and not minimap.shown,
		"leaving minimap hides the minimap widget and its blips again after rim grace")

	-- One Escape keypress restores the interface in soft-hide mode without opening GameMenuFrame.
	local function CloseSpecialWindowsSim()
		local closed = false
		for _, name in ipairs(specialFrames) do
			local frame = globals[name]
			if frame and frame:IsShown() then
				frame:Hide()
				closed = true
			end
		end
		return closed
	end
	assert(globals.ForeverPlusWanderlustEsc and globals.ForeverPlusWanderlustEsc:IsShown(),
		"soft hide arms the Escape guard when no bag or bubble is open")
	assert(CloseSpecialWindowsSim(), "Escape is handled by the Wanderlust guard instead of opening GameMenuFrame")
	assert(ui.shown and actionBar.alpha == 0.85 and minimap.shown and not module.IsSoftHidden() and Pending() == 1,
		"one Escape restores the full interface and minimap immediately and restarts the minute")
	assert(not CloseSpecialWindowsSim(), "a second Escape is free to open Blizzard's GameMenuFrame")

	-- One Alt+Z (TOGGLEUI) keypress while softly hidden also restores the interface in one step.
	Advance(60)
	assert(module.IsSoftHidden() and not minimap.shown, "re-enters soft hide after a quiet minute")
	local function PressToggleUI()
		if ui.shown then
			CloseSpecialWindowsSim()
			SetVisibility(false)
		else
			SetVisibility(true)
		end
	end
	PressToggleUI()
	assert(ui.shown and actionBar.alpha == 0.85 and minimap.shown and not qolSuppressed and not module.IsSoftHidden()
		and Pending() == 1,
		"one Alt+Z restores the softly hidden interface in a single step")
	Advance(0.1)
	PressToggleUI()
	assert(not ui.shown, "a subsequent Alt+Z on the visible interface hides it manually for the player")
	SetVisibility(true)
	visBefore = visibilityCalls
	Advance(60)
	assert(module.IsSoftHidden() and not minimap.shown and visibilityCalls == visBefore)

	-- While bags are open in soft-hide mode, Escape closes the bags rather than restoring the whole HUD.
	bagsOpen = true
	Fire("BAG_OPEN", 0)
	assert(not globals.ForeverPlusWanderlustEsc:IsShown(), "open bags disarm the Escape guard so Escape closes the bag first")
	bagsOpen = false
	Fire("BAG_CLOSED", 0)
	Tick()
	assert(globals.ForeverPlusWanderlustEsc:IsShown(), "closing the bag re-arms the Escape guard")

	-- BagsBar hover uses QoL.ShownAlpha (1) even though BagsBar was idle at alpha 0 before hiding.
	cursorX, cursorY = 850, 95
	Tick()
	assert(bagsBar.alpha == 1 and actionBar.alpha == 0 and not minimap.shown,
		"hovering BagsBar in soft-hide mode uses QoL shownAlpha without showing minimap blips")
	cursorX, cursorY = 500, 500
	Tick()
	assert(bagsBar.alpha == 0, "leaving BagsBar fades it back to 0")

	-- Toggling showChat off/on updates chat alpha live while softly hidden.
	module.db.showChat = false
	module:OnOptionChanged("showChat", false)
	assert(chatFrame.alpha == 0 and chatDock.alpha == 0, "disabling showChat fades chat frames in soft-hide mode")
	module.db.showChat = true
	module:OnOptionChanged("showChat", true)
	assert(chatFrame.alpha == 1 and chatDock.alpha == 1, "reenabling showChat restores chat alpha in soft-hide mode")

	-- Combat restores all faded frames to their exact pre-hide alpha (0 for idle QoL BagsBar, no flash!) and resumes QoL.
	combat = true
	Fire("PLAYER_REGEN_DISABLED")
	assert(actionBar.alpha == 0.85 and independentRegion.alpha == 0.75 and playerFrame.alpha == 1
		and playerContainer.alpha == 1 and cluster.alpha == 1 and minimapOverlay.alpha == 0.9 and minimap.shown
		and targetFrame.alpha == 1 and bagsBar.alpha == 0 and not qolSuppressed and not portraitHidden
		and not module.IsSoftHidden() and visibilityCalls == visBefore,
		"combat restores exact original alphas, minimap and portrait emblem without flashing idle QoL frames or calling SetUIVisibility")
	combat = false
	Fire("PLAYER_REGEN_ENABLED")

	-- Switching softHide off while already hidden cleanly transitions to classic SetUIVisibility(false).
	Advance(60)
	assert(actionBar.alpha == 0 and ui.shown and not minimap.shown, "hides softly again after combat")
	module.db.softHide = false
	module:OnOptionChanged("softHide", false)
	assert(not ui.shown and actionBar.alpha == 0.85 and minimap.shown and not qolSuppressed,
		"turning softHide off while hidden restores frame alphas and minimap and enters classic Alt+Z mode")
	-- Classic peek for bags also hides the minimap widget so blips never float over the hidden HUD.
	cursorX, cursorY = 850, 95
	Tick()
	assert(PeekingFrame(bagsBar) and not minimap.shown, "classic non-minimap peek hides the minimap widget so blips stay hidden")
	cursorX, cursorY = 500, 500
	Tick()
	assert(not ui.shown and minimap.shown, "ending classic peek restores the minimap widget before next reveal")
	module.db.softHide = true
	module:OnOptionChanged("softHide", true)
	assert(ui.shown and actionBar.alpha == 0 and not minimap.shown and qolSuppressed,
		"turning softHide back on while hidden restores UIParent and enters soft-hide mode")

	Enable(false)
	assert(minimap.shown, "disabling restores the minimap widget")
	ui.children, cluster.children, globals.TargetFrame, globals.PlayerFrame, env.PlayerFrame = {}, {}, nil, nil, nil
	ns.PortraitModes, qolShownAlphas[bagsBar] = nil, nil
end)()
;(function()
	-- Soft-hide performance guards: bounded tree traversal, no SetAlpha(0) on already-transparent frames,
	-- and throttled hard-blocker checks on steady 100 ms soft-hide mouseover ticks.
	local deepButtonRegionScans = 0
	local actionButton = PeekableFrame()
	actionButton.shown, actionButton.alpha = true, 1
	actionButton.GetRegions = function()
		deepButtonRegionScans = deepButtonRegionScans + 1
	end
	local actionBar = PeekableFrame()
	actionBar.shown, actionBar.alpha = true, 1
	actionBar.children = { actionButton }

	local zeroAlphaBar = PeekableFrame()
	zeroAlphaBar.shown, zeroAlphaBar.alpha = true, 0
	local zeroAlphaWrites = 0
	zeroAlphaBar.SetAlpha = function(self, a)
		zeroAlphaWrites = zeroAlphaWrites + 1
		self.alpha = a
	end

	local deepPinScans = 0
	local deepPinLeaf = PeekableFrame()
	deepPinLeaf.GetRegions = function() deepPinScans = deepPinScans + 1 end
	local deepPinMid = PeekableFrame()
	deepPinMid.children = { deepPinLeaf }
	local deepPinRoot = PeekableFrame()
	deepPinRoot.children = { deepPinMid }
	local minimapOverlay = PeekableFrame()
	minimapOverlay.shown, minimapOverlay.ignore, minimapOverlay.alpha = true, true, 1
	cluster.children = { minimapOverlay, deepPinRoot }
	cluster.shown, cluster.alpha = true, 1
	ui.children = { actionBar, zeroAlphaBar, cluster, bagsBar, chatFrame, chatDock }

	module.db.softHide = true
	Over(false)
	Enable(true)
	Advance(60)
	assert(module.IsSoftHidden(), "soft hide active")
	assert(deepButtonRegionScans == 0, "soft hide does not crawl regions of nested HUD child buttons")
	assert(deepPinScans == 0, "soft hide bounds MinimapCluster overlay traversal instead of crawling deep pin subtrees")
	assert(zeroAlphaWrites == 0, "soft hide skips redundant SetAlpha(0) on already-transparent frames")

	-- Steady 100 ms soft-hide ticks throttle full UIPanelWindows scans to 300 ms, yet still restore promptly.
	local panelReads = 0
	local probePanel = { shown = false }
	function probePanel:IsShown()
		panelReads = panelReads + 1
		return self.shown
	end
	globals.TestSoftProbePanel = probePanel
	panelWindows.TestSoftProbePanel = {}
	Tick() -- 0.1 s: throttled
	Tick() -- 0.2 s: throttled
	assert(panelReads == 0, "steady 100 ms soft-hide ticks skip full UIPanelWindows scan before 300 ms")
	probePanel.shown = true
	Tick() -- 0.3 s: triggers hard-blocker check and restores full UI
	assert(panelReads >= 1 and not module.IsSoftHidden(), "opening a panel restores soft-hidden UI on the 300 ms check")

	probePanel.shown = false
	panelWindows.TestSoftProbePanel, globals.TestSoftProbePanel = nil, nil
	Enable(false)
	ui.children, cluster.children = {}, {}
end)()
print("Wanderlust timing, teleports, chat, bags, dialog bubbles, mouseover, abilities, targets, windows and lifecycle OK")

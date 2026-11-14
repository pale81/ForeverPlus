-- ForeverPlus core: namespace, event dispatch, saved variables and module registry.
local addonName, ns = ...

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
ns.modules = {}
ns.L = ns.L or {}

-- Hidden parent for Blizzard regions we want gone without touching their code paths.
ns.hider = CreateFrame("Frame")
ns.hider:Hide()


---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
-- Output of commands the player typed; never muted.
function ns.PrintAlways(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverPlus|r: " .. msg)
end

-- Every other message; "mute all messages" on the main settings page silences it.
function ns.Print(msg, ...)
	if ns.db and ns.db.quiet then
		return
	end
	ns.PrintAlways(msg, ...)
end

-- Returns font flags with an outline added (nil if an outline is already present).
function ns.OutlineFlags(flags)
	flags = flags or ""
	if flags:find("OUTLINE") then
		return nil
	end
	return flags == "" and "OUTLINE" or (flags .. ", OUTLINE")
end

-- Gives a font object or font string an outline unless it already has one.
function ns.ApplyOutline(object)
	local file, size, flags = object:GetFont()
	if not file then
		return
	end
	local newFlags = ns.OutlineFlags(flags)
	if newFlags then
		object:SetFont(file, size, newFlags)
	end
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
ns.CopyDefaults = CopyDefaults

-- Runs fn now or as soon as combat lockdown ends.
local regenQueue = {}
function ns.RunOutOfCombat(fn)
	if InCombatLockdown() then
		regenQueue[#regenQueue + 1] = fn
	else
		fn()
	end
end

-- Calls fn(…) once the given Blizzard addon is loaded (immediately if already).
function ns.OnAddOnLoaded(name, fn)
	EventUtil.ContinueOnAddOnLoaded(name, fn)
end

-- A plain number, or the fallback when the client hands out a protected value.
function ns.Number(value, fallback)
	if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then
		return fallback
	end
	return value
end

-- Whether the client hands out a protected value (no comparing, no arithmetic, no patterns on it).
function ns.Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- The page of a quest, an item, an NPC … on Wowhead (its WoW Forever part) in the language of the client.
function ns.WowheadURL(kind, id)
	local locale = ({ deDE = "de/", frFR = "fr/", esES = "es/", esMX = "mx/", ptBR = "pt/", ruRU = "ru/", koKR = "ko/",
		zhCN = "cn/", zhTW = "tw/", itIT = "it/" })[GetLocale()] or ""
	return ("https://www.wowhead.com/forever/%s%s=%d"):format(locale, kind, id)
end

-- The parts of a creature or object GUID: kind ("Creature", "GameObject", "Vehicle", ...) and the numeric id.
function ns.GuidParts(guid)
	if type(guid) ~= "string" or ns.Secret(guid) then
		return
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

-- Chat filters: Blizzard moved the functions into ChatFrameUtil.
function ns.AddChatFilter(event, filter)
	(ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter)(event, filter)
end

function ns.RemoveChatFilter(event, filter)
	(ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter)(event, filter)
end

-- A typed command in lower case; string.lower leaves the German capitals with umlaut as they are.
function ns.LowerCommand(text)
	return (text:lower():gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"))
end

-- What modules record for later updates (rides, book finds, innkeepers, loot):
-- ns.AddDataSection(text, clear) with text() returning the lines to export or
-- nil, and clear() removing the recording. /fp daten export and löschen use them.
ns.dataSections = {}

-- The first line of every exported section: a tag that does not depend on the
-- game language, so tools/contrib.py can tell the sections apart.
function ns.ExportTag(id)
	return "-- @fp " .. id
end

function ns.AddDataSection(text, clear)
	ns.dataSections[#ns.dataSections + 1] = { text = text, clear = clear }
end

-- Extra lines of item tooltips: modules register a section, Modules/Tooltip.lua
-- puts all sections together under one separator, in the order given. A section
-- is fn(data) returning lines { left =, right =, lc = {r, g, b}, rc = {r, g, b},
-- wrap = true } or nil.
ns.itemSections = {}

function ns.AddItemSection(order, fn)
	local sections = ns.itemSections
	sections[#sections + 1] = { order = order, fn = fn }
	table.sort(sections, function(a, b)
		return a.order < b.order
	end)
end

-- Entries of ForeverPlus in the world map's filter menu: modules register
-- fn(root) adding their checkboxes (Modules/WorldMap.lua builds the section).
ns.mapFilterEntries = {}

function ns.AddMapFilterEntry(fn)
	ns.mapFilterEntries[#ns.mapFilterEntries + 1] = fn
end

-- A checkbox in a menu that switches an option of a module; the setting
-- variable is the one of the settings page ("ForeverPlus_<module>_<key>").
-- Sets an option from our own menus and buttons. Settings.SetValue would run the game's evaluation of all settings in
-- our (tainted) path; it reaches protected functions of the game's own settings (ADDON_ACTION_FORBIDDEN:
-- IsUserOAuthed()). The option is written to the module's table, which the settings page reads when it is drawn.
function ns.SetOption(moduleName, key, value)
	local module = ns:GetModule(moduleName)
	if not (module and module.db) then
		return
	end
	module.db[key] = value
	if module.OnOptionChanged then
		module:OnOptionChanged(key, value)
	end
end

function ns.CreateOptionCheckbox(parent, text, moduleName, key, tooltip)
	local function IsOn()
		local module = ns:GetModule(moduleName)
		return module and module.db[key] and true or false
	end
	local checkbox = parent:CreateCheckbox(text, IsOn, function()
		ns.SetOption(moduleName, key, not IsOn())
	end)
	if tooltip and checkbox.SetTooltip then
		checkbox:SetTooltip(function(tip)
			GameTooltip_SetTitle(tip, text)
			GameTooltip_AddNormalLine(tip, tooltip)
		end)
	end
	return checkbox
end

-- A submenu with the sizes (percent) of a module's symbols as radio buttons; the setting is
-- "ForeverPlus_<module>_<key>" like on the settings page.
local SIZE_STEPS = { 50, 75, 100, 125, 150, 200 }

function ns.CreateSizeMenu(parent, text, moduleName, key)
	local menu = parent:CreateButton(text)
	if not menu or not menu.CreateRadio then
		return menu
	end
	for _, percent in ipairs(SIZE_STEPS) do
		menu:CreateRadio(("%d %%"):format(percent), function()
			local module = ns:GetModule(moduleName)
			return math.abs((module and module.db[key] or 100) - percent) < 12
		end, function()
			ns.SetOption(moduleName, key, percent)
		end)
	end
	return menu
end

-- Quest with objectives that are all fulfilled. The API also reports quests
-- without objectives (breadcrumbs, "talk to …") as complete; they are not.
function ns.IsQuestReady(questID, logIndex)
	if not (C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete)(questID) or C_QuestLog.IsFailed(questID) then
		return false
	end
	logIndex = logIndex or C_QuestLog.GetLogIndexForQuestID(questID)
	return logIndex and GetNumQuestLeaderBoards(logIndex) > 0 or false
end

---------------------------------------------------------------------------
-- Lua pattern from one of Blizzard's format strings ("%s", "%d", "%1$s"):
-- each placeholder becomes a capture; order[i] is the format argument of
-- capture i.
---------------------------------------------------------------------------
function ns.FormatToPattern(format, anchored)
	local order, count = {}, 0
	local marked = format:gsub("%%(%d*)%$?([sd])", function(index, kind)
		count = count + 1
		order[count] = tonumber(index) or count
		return kind == "d" and "\001" or "\002"
	end)
	marked = marked:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	marked = marked:gsub("\001", "(%%d+)"):gsub("\002", "(.-)")
	if anchored then
		marked = "^" .. marked .. "$"
	end
	return { pattern = marked, order = order }
end

---------------------------------------------------------------------------
-- Event dispatcher: one frame, events only registered while someone listens.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listeners = {}

function ns:RegisterEvent(event, owner, fn)
	-- Events that this client does not know are skipped instead of erroring.
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		return
	end
	local set = listeners[event]
	if not set then
		set = {}
		listeners[event] = set
		eventFrame:RegisterEvent(event)
	elseif set[owner] == nil then
		-- A new listener goes into a copy: the event may be running through the old table right now, and a new
		-- key during a traversal is undefined in Lua.
		local copy = {}
		for key, value in pairs(set) do
			copy[key] = value
		end
		set = copy
		listeners[event] = set
	end
	set[owner] = fn
end

function ns:UnregisterEvent(event, owner)
	local set = listeners[event]
	if not set then
		return
	end
	set[owner] = nil
	if next(set) == nil then
		listeners[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

---------------------------------------------------------------------------
-- Timing: detailed call statistics are opt-in. The CPU display also keeps
-- the longest instrumented call of each frame for its session peak.
---------------------------------------------------------------------------
ns.timings = {} -- name -> { max =, count =, slow = (calls over SLOW_MS) }
ns.measuring = false

-- Use the same threshold for individual calls and the game's addon frame times.
ns.SLOW_MS = 5
ns.spikes = { samples = 0, count = 0, worst = 0 }
local frameTop, frameTopTime, frameTopAt
local lastTop, lastTopTime, lastTopAt
local previousFrameAt
local sessionSampler
local SESSION_CALL_MIN = 0.25
local measureStartedAt

local function ActiveMeasurement()
	return ns.measuring and GetTime() > measureStartedAt and ns.spikes
end

-- Work done once while loading (OnInitialize, OnLogin, the settings pages): kept apart from the timings of play, so
-- the list of the longest calls shows what costs while playing.
ns.loadTimings = {} -- name -> ms

function ns.RecordLoad(name, elapsed)
	ns.loadTimings[name] = elapsed
end

local function RecordFrameCall(name, elapsed)
	local now = GetTime()
	if now ~= frameTopAt then
		lastTop, lastTopTime, lastTopAt = frameTop, frameTopTime, frameTopAt
		frameTop, frameTopTime, frameTopAt = nil, 0, now
	end
	if elapsed > frameTopTime then
		frameTop, frameTopTime = name, elapsed
	end
end

function ns.RecordTiming(name, elapsed)
	if ns.measuring or (sessionSampler and elapsed >= SESSION_CALL_MIN) then
		RecordFrameCall(name, elapsed)
	end
	local entry = ns.timings[name]
	if not entry then
		entry = { max = 0, count = 0, slow = 0 }
		ns.timings[name] = entry
	end
	entry.count = entry.count + 1
	if elapsed > entry.max then
		entry.max = elapsed
	end
	if elapsed > ns.SLOW_MS then
		entry.slow = entry.slow + 1
	end
end

-- Share the frame boundary between the session display and explicit measurements.
local spikeFrame = CreateFrame("Frame")
spikeFrame:Hide()
spikeFrame:SetScript("OnUpdate", function()
	local now = GetTime()
	local name, elapsed
	-- Events may already have run in the current tick when OnUpdate samples the previous one.
	if previousFrameAt then
		if frameTopAt == previousFrameAt then
			name, elapsed = frameTop, frameTopTime
		elseif lastTopAt == previousFrameAt then
			name, elapsed = lastTop, lastTopTime
		end
	end
	local total
	if sessionSampler then
		local start = debugprofilestop()
		total = sessionSampler(now, name, elapsed, previousFrameAt)
		local duration = debugprofilestop() - start
		if duration >= SESSION_CALL_MIN then
			RecordFrameCall("Info: CPU sampler", duration)
		end
	end
	local profiler = C_AddOnProfiler
	-- LastTime reports the previous frame. Start with the first complete frame after the click or command.
	if ns.measuring and previousFrameAt and previousFrameAt > measureStartedAt and profiler and profiler.IsEnabled() then
		total = total or profiler.GetAddOnMetric(addonName, Enum.AddOnProfilerMetric.LastTime)
		if type(total) == "number" then
			local spikes = ns.spikes
			spikes.samples = spikes.samples + 1
			if total > ns.SLOW_MS then
				spikes.count = spikes.count + 1
			end
			if total > spikes.worst then
				spikes.worst, spikes.name = total, name
			end
		end
	end
	previousFrameAt = now
end)

function ns.SetSessionProfiler(sample)
	sessionSampler = sample
	if not (sample or ns.measuring) then
		previousFrameAt = nil
	end
	spikeFrame:SetShown(ns.measuring or sample ~= nil)
end

-- Switches detailed measurement on (earlier values are cleared) or off.
function ns.SetMeasuring(on)
	ns.measuring = on and true or false
	if on then
		wipe(ns.timings)
		ns.spikes = { samples = 0, count = 0, worst = 0 }
		measureStartedAt = GetTime()
		if not sessionSampler then
			frameTop, frameTopTime, frameTopAt = nil, nil, nil
			lastTop, lastTopTime, lastTopAt = nil, nil, nil
		end
	end
	spikeFrame:SetShown(ns.measuring or sessionSampler ~= nil)
end

function ns.FormatMeasuredFrames(stats)
	if stats.samples == 0 then
		return ns.L.TIMINGS_FRAMES_UNAVAILABLE
	end
	return ns.L.TIMINGS_FRAMES:format(stats.worst, stats.count, stats.samples, ns.SLOW_MS)
end

local function OwnerName(owner)
	return type(owner) == "table" and owner.name or tostring(owner)
end

-- An error in one listener goes to the error handler; the others still run.
local function ErrorHandler(message)
	return geterrorhandler()(message)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local set = listeners[event]
	if set then
		if ns.measuring or sessionSampler then
			for owner, fn in pairs(set) do
				local measurement = ActiveMeasurement()
				local start = debugprofilestop()
				xpcall(fn, ErrorHandler, owner, event, ...)
				local elapsed = debugprofilestop() - start
				if measurement and measurement == ns.spikes and ns.measuring then
					ns.RecordTiming(OwnerName(owner) .. ": " .. event, elapsed)
				elseif elapsed >= SESSION_CALL_MIN then
					RecordFrameCall(OwnerName(owner) .. ": " .. event, elapsed)
				end
			end
			return
		end
		for owner, fn in pairs(set) do
			xpcall(fn, ErrorHandler, owner, event, ...)
		end
	end
end)

-- Sets an OnUpdate script that shows up in the measurement.
function ns.SetUpdate(frame, name, fn)
	frame:SetScript("OnUpdate", fn and ns.Measured(name, fn) or nil)
end

-- Wraps a hook or callback. Return values are dropped (hooks ignore them).
function ns.Measured(name, fn)
	return function(...)
		if not (ns.measuring or sessionSampler) then
			fn(...)
			return
		end
		local measurement = ActiveMeasurement()
		local start = debugprofilestop()
		fn(...)
		local elapsed = debugprofilestop() - start
		if measurement and measurement == ns.spikes and ns.measuring then
			ns.RecordTiming(name, elapsed)
		elseif elapsed >= SESSION_CALL_MIN then
			RecordFrameCall(name, elapsed)
		end
	end
end

-- Timers that show up in the measurement: like C_Timer.After, NewTimer and NewTicker, with the name first.
function ns.After(name, delay, fn)
	C_Timer.After(delay, ns.Measured(name, fn))
end

function ns.NewTimer(name, delay, fn)
	return C_Timer.NewTimer(delay, ns.Measured(name, fn))
end

function ns.NewTicker(name, delay, fn, iterations)
	return C_Timer.NewTicker(delay, ns.Measured(name, fn), iterations)
end

-- Calls fn(i) for i = 1..count, yielding after an entry if the frame budget is spent.
-- Calls onDone when finished and returns the ticker so callers can cancel stale scans.
local SLICE_BUDGET = 0.25

function ns.RunSliced(name, count, fn, onDone, budget)
	budget = budget or SLICE_BUDGET
	local index = 1
	return C_Timer.NewTicker(0, function(ticker)
		local start = debugprofilestop()
		-- A slow frame rate gets less of the work per frame.
		local frameBudget = ns.Number(GetFramerate(), 60) < 40 and budget / 2 or budget
		while index <= count do
			local current = index
			index = index + 1 -- before the call: an error must not repeat the same entry every frame
			fn(current)
			if debugprofilestop() - start >= frameBudget then
				ns.RecordTiming(name, debugprofilestop() - start)
				return
			end
		end
		ticker:Cancel()
		ns.RecordTiming(name, debugprofilestop() - start)
		if onDone then
			onDone()
		end
	end)
end

-- Measures for `seconds` from now on (earlier values are cleared), then
-- prints the result and calls onDone.
function ns.StartTimedMeasure(seconds, onDone)
	if ns.measureTimer then
		return
	end
	ns.SetMeasuring(true)
	ns.measureUntil = GetTime() + seconds
	ns.measureTimer = ns.NewTimer("Info: measurement results", seconds, function()
		ns.SetMeasuring(false)
		ns.measureTimer, ns.measureUntil = nil, nil
		ns.PrintTimings()
		if onDone then
			onDone()
		end
	end)
end

-- The longest entries, longest first.
function ns.TopTimings(count)
	local list = {}
	for name, entry in pairs(ns.timings) do
		list[#list + 1] = { name = name, entry = entry }
	end
	table.sort(list, function(a, b)
		return a.entry.max > b.entry.max
	end)
	for i = #list, count + 1, -1 do
		list[i] = nil
	end
	return list
end

local TIMING_COLORS = { green = "|cff00ff00", orange = "|cffff8800", red = "|cffff0000" }

function ns.PrintTimings()
	local list = ns.TopTimings(12)
	ns.PrintAlways(ns.L.TIMINGS_HEADER)
	ns.PrintAlways(ns.FormatMeasuredFrames(ns.spikes))
	if #list == 0 then
		ns.PrintAlways(ns.L.TIMINGS_EMPTY)
	end
	for i = 1, #list do
		local item = list[i]
		-- Same limits as the rows of the performance display (Info.PeakLevel).
		local max = item.entry.max
		local color = TIMING_COLORS[ns:GetModule("Info").PeakLevel(max)]
		ns.PrintAlways(color .. ns.L.TIMINGS_LINE .. "|r", item.name, max, item.entry.slow, item.entry.count)
	end
	local total, longest, longestName = 0, 0, nil
	for name, elapsed in pairs(ns.loadTimings) do
		total = total + elapsed
		if elapsed > longest then
			longest, longestName = elapsed, name
		end
	end
	if longestName then
		ns.PrintAlways(ns.L.TIMINGS_LOAD, total, longestName, longest)
	end
	local spikes = ns.spikes
	if spikes.count > 0 and spikes.name then
		ns.PrintAlways(ns.L.TIMINGS_SPIKES, spikes.name)
	end
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
local ModuleMixin = {}

function ModuleMixin:RegisterEvent(event, fn)
	ns:RegisterEvent(event, self, fn or self[event])
end

function ModuleMixin:UnregisterEvent(event)
	ns:UnregisterEvent(event, self)
end

-- Registers or unregisters an event depending on a condition.
function ModuleMixin:ToggleEvent(event, enabled, fn)
	if enabled then
		self:RegisterEvent(event, fn)
	else
		self:UnregisterEvent(event)
	end
end

-- spec: { title = string, order = number, defaults = table, options = table }
function ns:NewModule(name, spec)
	local module = CreateFromMixins(ModuleMixin, spec or {})
	module.name = name
	self.modules[#self.modules + 1] = module
	self.modules[name] = module
	return module
end

function ns:GetModule(name)
	return self.modules[name]
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DB_VERSION = 1

local function InitDatabase()
	ForeverPlusDB = ForeverPlusDB or {}
	ForeverPlusCharDB = ForeverPlusCharDB or {}
	local db, cdb = ForeverPlusDB, ForeverPlusCharDB

	db.version = db.version or DB_VERSION
	db.modules = db.modules or {}
	db.frames = db.frames or {}
	cdb.modules = cdb.modules or {}

	for _, module in ipairs(ns.modules) do
		db.modules[module.name] = CopyDefaults(module.defaults or {}, db.modules[module.name] or {})
		module.db = db.modules[module.name]
		if module.charDefaults then
			cdb.modules[module.name] = CopyDefaults(module.charDefaults, cdb.modules[module.name] or {})
			module.cdb = cdb.modules[module.name]
		end
	end

	ns.db, ns.cdb = db, cdb
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then
			return
		end
		InitDatabase()
		for _, module in ipairs(ns.modules) do
			if module.OnInitialize then
				local start = debugprofilestop()
				securecallfunction(module.OnInitialize, module)
				ns.RecordLoad(module.name .. ": OnInitialize", debugprofilestop() - start)
			end
		end
		local start = debugprofilestop()
		ns:BuildSettings()
		ns.RecordLoad("Settings", debugprofilestop() - start)
	elseif event == "PLAYER_LOGIN" then
		-- Select the installed data provider while the loading screen is up,
		-- instead of on the first tooltip.
		if ns.QuestieDB then
			local start = debugprofilestop()
			ns.QuestieDB.Get()
			ns.RecordLoad("Database: provider", debugprofilestop() - start)
		end
		for _, module in ipairs(ns.modules) do
			if module.OnLogin then
				local start = debugprofilestop()
				securecallfunction(module.OnLogin, module)
				ns.RecordLoad(module.name .. ": OnLogin", debugprofilestop() - start)
			end
		end
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PLAYER_REGEN_ENABLED" then
		local queue = regenQueue
		regenQueue = {}
		for i = 1, #queue do
			xpcall(queue[i], ErrorHandler)
		end
	end
end)

---------------------------------------------------------------------------
-- Mouse wheel check (/fp mausrad): for a minute, reports which frame takes
-- the wheel when Shift is pressed and whether the page commands run.
---------------------------------------------------------------------------
local WHEEL_CHECK_SECONDS = 60
local wheelCheckUntil, wheelCheckHooked
local wheelCheckFrame = CreateFrame("Frame")

local function WheelChecking()
	return wheelCheckUntil and GetTime() < wheelCheckUntil
end

local function FrameLabel(frame)
	local name = frame.GetDebugName and frame:GetDebugName() or frame:GetName()
	return name and name ~= "" and name or tostring(frame)
end

local function ReportWheelTarget()
	local foci = GetMouseFoci and GetMouseFoci() or {}
	for _, region in ipairs(foci) do
		local frame = region
		while frame do
			if frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then
				ns.PrintAlways(ns.L.WHEEL_CHECK_FRAME:format(FrameLabel(frame)))
				return
			end
			frame = frame.GetParent and frame:GetParent()
		end
	end
	-- Frames that take the wheel without taking the mouse are not in the
	-- focus list; look through all shown frames under the cursor.
	local found = {}
	local frame = EnumerateFrames()
	while frame and #found < 5 do
		if not frame:IsForbidden() and frame:IsVisible() and frame:IsMouseWheelEnabled() and frame:IsMouseOver() then
			found[#found + 1] = FrameLabel(frame)
		end
		frame = EnumerateFrames(frame)
	end
	if #found > 0 then
		ns.PrintAlways(ns.L.WHEEL_CHECK_FRAME:format(table.concat(found, ", ")))
	else
		ns.PrintAlways(ns.L.WHEEL_CHECK_WORLD)
	end
end

local function PageCommand(direction)
	return function()
		if WheelChecking() then
			ns.PrintAlways(ns.L.WHEEL_CHECK_COMMAND:format(direction, C_ActionBar.GetActionBarPage()))
		end
	end
end

wheelCheckFrame:SetScript("OnEvent", function(_, event, key, down)
	if event == "MODIFIER_STATE_CHANGED" then
		if (down == 1 or down == true) and (key == "LSHIFT" or key == "RSHIFT") then
			ReportWheelTarget()
			ns.PrintAlways(ns.L.WHEEL_CHECK_BINDINGS:format(
				tostring(GetBindingAction("SHIFT-MOUSEWHEELUP", true)),
				tostring(GetBindingAction("SHIFT-MOUSEWHEELDOWN", true)),
				InCombatLockdown() and YES or NO))
		end
	else
		ns.PrintAlways(ns.L.WHEEL_CHECK_PAGE:format(C_ActionBar.GetActionBarPage()))
	end
end)

function ns.StartWheelCheck()
	if not wheelCheckHooked then
		wheelCheckHooked = true
		hooksecurefunc("ActionBar_PageUp", PageCommand("+"))
		hooksecurefunc("ActionBar_PageDown", PageCommand("-"))
	end
	wheelCheckUntil = GetTime() + WHEEL_CHECK_SECONDS
	wheelCheckFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
	wheelCheckFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	ns.PrintAlways(ns.L.WHEEL_CHECK_START:format(WHEEL_CHECK_SECONDS))
	ns.After("Core: wheel check end", WHEEL_CHECK_SECONDS, function()
		if wheelCheckUntil and not WheelChecking() then
			wheelCheckUntil = nil
			wheelCheckFrame:UnregisterAllEvents()
			ns.PrintAlways(ns.L.WHEEL_CHECK_END)
		end
	end)
end

---------------------------------------------------------------------------
-- Slash command and addon compartment
---------------------------------------------------------------------------
SLASH_FOREVERPLUS1 = "/fp"
SLASH_FOREVERPLUS2 = "/foreverplus"
SlashCmdList.FOREVERPLUS = function(msg)
	msg = ns.LowerCommand(strtrim(msg or ""))
	if msg == "errors" or msg == "fehler" then
		local errors = ns:GetModule("Errors")
		if errors then
			errors:ShowMenu()
		end
	elseif msg == "messen" or msg == "profile" then
		-- A timed measurement (30 s from the performance display) ends here too, so its result does not come twice.
		if ns.measureTimer then
			ns.measureTimer:Cancel()
			ns.measureTimer, ns.measureUntil = nil, nil
		end
		ns.SetMeasuring(not ns.measuring)
		if ns.measuring then
			ns.PrintAlways(ns.L.TIMINGS_ON)
		else
			ns.PrintTimings()
		end
	elseif msg == "zeiten" or msg == "zeit" or msg == "timings" then
		ns.PrintTimings()
	elseif msg == "kopieren" or msg == "copy" then
		ns:GetModule("Chat"):CopyChat()
	elseif msg == "hilfe" or msg == "help" or msg == "?" then
		ns.PrintAlways(ns.L.SLASH_HELP)
	elseif msg:find("^radar zur") or msg == "radar reset" then
		ns:GetModule("RecipeRadar").ResetCollected()
	elseif msg == "radar" then
		ns:GetModule("RecipeRadar"):PrintStatus()
	elseif msg == "diagnose" or msg == "diagnosis" then
		ns:GetModule("DataCapture").Diagnose()
	elseif msg == "talente" or msg == "talents" then
		ns:GetModule("Talents"):PrintStatus()
	elseif msg:find("^geld") or msg:find("^money") then
		ns:GetModule("Items").MoneyCommand(msg:match("^%S+%s*(.*)"))
	elseif msg == "logo" then
		ns:GetModule("Quests").PrintLogoAtlases()
	elseif msg == "grundwerte" or msg == "basesettings" then
		ns:GetModule("QoL").ApplyBaseSettings()
	elseif msg == "welttext" or msg == "worldtext" then
		ns:GetModule("RepFlash").ResetWorldText(true)
	elseif msg == "haltbarkeit" or msg == "durability" then
		ns:GetModule("Durability"):PrintStatus()
	elseif msg == "beute" or msg == "loot" then
		ns:GetModule("Loot"):PrintStatus()
	elseif msg == "karte" or msg == "map" then
		ns:GetModule("WorldMap"):PrintStatus()
	elseif msg == "dungeon" or msg == "journal" then
		ns:GetModule("DungeonJournal").Toggle()
	elseif msg == "mausrad" or msg == "wheel" then
		ns.StartWheelCheck()
	elseif msg == "schrift" or msg == "font" then
		ns:GetModule("Fonts").Inspect()
	elseif msg == "taschen verlauf" or msg == "bags trace" then
		ns:GetModule("Items").PrintTrace()
	elseif msg == "aufwertung" or msg == "upgrade" then
		ns:GetModule("Items").PreviewUpgrade()
	elseif msg == "junk" or msg == "schrott" then
		ns:GetModule("Items"):ShowJunkMenu()
	elseif msg == "export" then
		ns:GetModule("DataCapture").Export()
	elseif msg:find("^daten") or msg:find("^data") then
		ns:GetModule("DataCapture").Command(msg)
	elseif msg == "ziele verlauf" or msg == "objectives trace" then
		ns:GetModule("Observations").PrintTrace()
	elseif msg == "buff verlauf" or msg == "buff trace" then
		ns:GetModule("Buffs").PrintTrace()
	elseif msg == "gruppenquests" or msg == "group quests" then
		ns:GetModule("GroupFinder").PrintQuests()
	elseif msg == "buch verlauf" or msg == "book trace" then
		ns:GetModule("Readable").PrintTrace()
	elseif msg == "blase verlauf" or msg == "bubble trace" then
		ns:GetModule("Dialog").PrintTrace()
	elseif msg == "blase" or msg == "bubble" then
		ns:GetModule("Dialog").PrintStatus()
	elseif msg:find("^weg") or msg:find("^way") then
		ns:GetModule("Waypoint").Command(msg)
	elseif msg:find("^nord") then
		ns:GetModule("Teleports").Command(msg)
	elseif msg:find("^bücher") or msg:find("^books") then
		ns:GetModule("Library").Command(msg)
	elseif msg:find("^gasthäuser") or msg:find("^inns") then
		ns:GetModule("Innkeepers").Command(msg)
	else
		ns:OpenSettings()
	end
end

-- Short reload command.
SLASH_FOREVERPLUSRL1 = "/rl"
SlashCmdList.FOREVERPLUSRL = ReloadUI

function ForeverPlus_OnAddonCompartmentClick()
	ns:OpenSettings()
end



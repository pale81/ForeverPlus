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

-- What modules record for later updates (rides, book finds, innkeepers, loot):
-- ns.AddDataSection(text, clear) with text() returning the lines to export or
-- nil, and clear() removing the recording. /fp daten export and löschen use them.
ns.dataSections = {}

function ns.AddDataSection(text, clear)
	ns.dataSections[#ns.dataSections + 1] = { text = text, clear = clear }
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
-- Timing: one-time work is always measured, events only while measuring is
-- switched on (/fp messen). The longest call per entry shows spikes.
---------------------------------------------------------------------------
ns.timings = {} -- name -> { max =, count =, slow = (calls over 1 ms) }
ns.measuring = false

function ns.RecordTiming(name, elapsed)
	local entry = ns.timings[name]
	if not entry then
		entry = { max = 0, count = 0, slow = 0 }
		ns.timings[name] = entry
	end
	entry.count = entry.count + 1
	if elapsed > entry.max then
		entry.max = elapsed
	end
	if elapsed > 1 then
		entry.slow = entry.slow + 1
	end
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
		if ns.measuring then
			for owner, fn in pairs(set) do
				local start = debugprofilestop()
				xpcall(fn, ErrorHandler, owner, event, ...)
				ns.RecordTiming(OwnerName(owner) .. ": " .. event, debugprofilestop() - start)
			end
			return
		end
		for owner, fn in pairs(set) do
			xpcall(fn, ErrorHandler, owner, event, ...)
		end
	end
end)

-- Wraps a hook or callback: measured while measuring is on, otherwise only
-- a flag check. Return values are dropped (hooks ignore them).
function ns.Measured(name, fn)
	return function(...)
		if not ns.measuring then
			fn(...)
			return
		end
		local start = debugprofilestop()
		fn(...)
		ns.RecordTiming(name, debugprofilestop() - start)
	end
end

-- Calls fn(i) for i = 1..count spread over frames, at most budget ms per
-- frame (default 0.25, below the 1 ms the game's addon profiler counts as
-- slow), then onDone. Used for large one-time scans.
local SLICE_BUDGET = 0.25

function ns.RunSliced(name, count, fn, onDone, budget)
	budget = budget or SLICE_BUDGET
	local index = 1
	C_Timer.NewTicker(0, function(ticker)
		local start = debugprofilestop()
		while index <= count do
			local current = index
			index = index + 1 -- before the call: an error must not repeat the same entry every frame
			fn(current)
			if debugprofilestop() - start >= budget then
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
	wipe(ns.timings)
	ns.measuring = true
	ns.measureUntil = GetTime() + seconds
	ns.measureTimer = C_Timer.NewTimer(seconds, function()
		ns.measuring = false
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

function ns.PrintTimings()
	local list = ns.TopTimings(12)
	ns.PrintAlways(ns.L.TIMINGS_HEADER)
	if #list == 0 then
		ns.PrintAlways(ns.L.TIMINGS_EMPTY)
	end
	for i = 1, #list do
		local item = list[i]
		ns.PrintAlways(ns.L.TIMINGS_LINE, item.name, item.entry.max, item.entry.slow, item.entry.count)
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

-- Resets one module to its defaults (requires a reload to undo hooks cleanly).
function ns:ResetModule(module)
	wipe(module.db)
	CopyDefaults(module.defaults or {}, module.db)
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
				ns.RecordTiming(module.name .. ": OnInitialize", debugprofilestop() - start)
			end
		end
		local start = debugprofilestop()
		ns:BuildSettings()
		ns.RecordTiming("Settings", debugprofilestop() - start)
	elseif event == "PLAYER_LOGIN" then
		-- Select the installed data provider while the loading screen is up,
		-- instead of on the first tooltip.
		if ns.QuestieDB then
			local start = debugprofilestop()
			ns.QuestieDB.Get()
			ns.RecordTiming("Database: provider", debugprofilestop() - start)
		end
		for _, module in ipairs(ns.modules) do
			if module.OnLogin then
				local start = debugprofilestop()
				securecallfunction(module.OnLogin, module)
				ns.RecordTiming(module.name .. ": OnLogin", debugprofilestop() - start)
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
	C_Timer.After(WHEEL_CHECK_SECONDS, function()
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
	msg = strtrim(msg or ""):lower()
	if msg == "errors" or msg == "fehler" then
		local errors = ns:GetModule("Errors")
		if errors then
			errors:ShowMenu()
		end
	elseif msg == "messen" or msg == "profile" then
		ns.measuring = not ns.measuring
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
	elseif msg == "radar" then
		ns:GetModule("RecipeRadar"):PrintStatus()
	elseif msg == "karte" or msg == "map" then
		ns:GetModule("WorldMap"):PrintStatus()
	elseif msg == "mausrad" or msg == "wheel" then
		ns.StartWheelCheck()
	elseif msg == "junk" or msg == "schrott" then
		ns:GetModule("Items"):ShowJunkMenu()
	elseif msg:find("^daten") or msg:find("^data") then
		ns:GetModule("DataCapture").Command(msg)
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



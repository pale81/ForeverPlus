-- Info module: played + perf tooltip
local info = ns:GetModule("Info")
TimeManagerClockButton = {}
GameTooltip.GetOwner = function() return TimeManagerClockButton end
local lines = {}
GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = tostring(l) .. " | " .. tostring(r) end
GameTooltip.AddLine = function(_, l) lines[#lines + 1] = tostring(l) end
GameTooltip_AddNormalLine = function(_, l) lines[#lines + 1] = tostring(l) end
GameTooltip_AddBlankLineToTooltip = function() end
GameTooltip_SetTitle = function(_, l) lines[#lines + 1] = "## " .. l end
C_ClassColor.GetClassColor = function() return { WrapTextInColorCode = function(_, t) return t end, GetRGB = function() return 1, 1, 1 end } end
info:TIME_PLAYED_MSG("TIME_PLAYED_MSG", 3600)
info.db.characters.Forever.Alt = { total = 7200, class = "WARRIOR", level = 30 }
uv = function(fn, name) for i = 1, 200 do local n, v = debug.getupvalue(fn, i) if not n then return end if n == name then return v end end end
local add = uv(info.OnLogin, "AddPlayedLines")
add()
;(function()
	local savedName, savedClass, savedRealm, savedLevel, savedTime = UnitName, UnitClass, GetRealmName, UnitLevel, time
	local realm = ""
	UnitName = function() return "Kazgrim" end
	UnitClass = function() return "Shaman", "SHAMAN" end
	GetRealmName = function() return realm end
	UnitLevel = function() return 19 end
	time = function() return 2002 end
	local clockInfo
	local fixture = setmetatable({ After = function() end, OnAddOnLoaded = function() end }, { __index = ns })
	function fixture:NewModule(_, module)
		clockInfo = module
		module.db = module.defaults
		module.RegisterEvent = function() end
		return module
	end
	assert(loadfile(root .. "/Modules/Info.lua"))("ForeverPlus", fixture)
	clockInfo.UpdatePerformance = function() end
	local characters = clockInfo.db.characters
	local newest = { total = 106885, time = 2000, class = "SHAMAN", level = 19, levelStart = 106426, levelStartLevel = 19 }
	characters[""] = { Kazgrim = newest }
	characters.Forever = {
		Kazgrim = { total = 77904, time = 1000, class = "SHAMAN", level = 16 },
		Thoradin = { total = 140251, class = "PALADIN", level = 21 },
	}
	clockInfo:OnLogin()
	assert(characters[""] == nil and characters.Forever.Kazgrim == newest and newest.levelStart == 106426,
		"the legacy duplicate is repaired before the realm is available, preserving the newer level data")
	local previousLines = lines
	lines = {}
	uv(clockInfo.OnLogin, "AddPlayedLines")()
	assert(#lines == 4 and lines[2]:find("Thoradin", 1, true) and lines[3]:find("Kazgrim", 1, true)
		and lines[4] == ns.L.INFO_PLAYED_TOTAL .. " | 247138s", "the clock counts exactly two characters and includes live time")
	lines = previousLines
	characters.Other = { Kazgrim = { total = 3600, class = "SHAMAN" } }
	characters[""] = { Kazgrim = { total = 1800, class = "SHAMAN" } }
	realm = "Forever"
	clockInfo:TIME_PLAYED_MSG("TIME_PLAYED_MSG", 106900, 474)
	assert(characters.Forever.Kazgrim.total == 106900 and characters.Other.Kazgrim.total == 3600
		and characters[""].Kazgrim.total == 1800, "the server reply updates the current realm and leaves an ambiguous record intact")
	UnitName, UnitClass, GetRealmName, UnitLevel, time = savedName, savedClass, savedRealm, savedLevel, savedTime
	print("clock played-time realm recovery OK")
end)()
local show = uv(uv(uv(info.UpdatePerformance, "CreatePerfFrame"), "RefreshCpuTooltip"), "fn")
show(UIParent)
for _, l in ipairs(lines) do print("  " .. l) end
print("info OK")
;(function()
	-- The CPU tooltip samples only after the world and loading screen are ready.
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local event = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local metrics = uv(show, "sessionMetrics")
	local row = metrics.Slow
	local savedTime, savedMetric = GetTime, C_AddOnProfiler.GetAddOnMetric
	local now, elapsed = 500, 40
	GetTime = function() return now end
	C_AddOnProfiler.GetAddOnMetric = function() return elapsed end
	sample()
	assert(row.recentCount == 0, "even a long login has no samples before world entry")

	event(sampler, "PLAYER_ENTERING_WORLD", true, false)
	now = 510
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 569
	sample()
	assert(row.recentCount == 0, "the first loading screen ends before the full startup grace")
	now, elapsed = 570, 3.3
	sample()
	elapsed = 0.07
	for _ = 1, 60 do sample() end
	assert(row.peak == 3.3 and row.peakAt == 570 and row.slow == 0 and math.abs(row.recentTotal / row.recentCount - 0.07) < 0.001,
		"the recent average ages out a peak below the slow-frame threshold")

	now, elapsed = 600, 40
	event(sampler, "LOADING_SCREEN_ENABLED")
	event(sampler, "PLAYER_ENTERING_WORLD", false, false)
	now = 625
	sample()
	assert(row.peak == 3.3, "a long zone loading screen suspends sampling")
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 644
	sample()
	assert(row.slow == 0, "zone grace runs from the end of the screen")
	now, elapsed = 645, 6
	sample()
	assert(row.peak == 6 and row.slow == 1, "real gameplay spikes still count")

	now, elapsed = 700, 40
	event(sampler, "LOADING_SCREEN_ENABLED")
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 705
	event(sampler, "PLAYER_ENTERING_WORLD", false, true)
	now = 764
	sample()
	assert(row.peak == 6 and row.slow == 1, "reload waits a full minute from world entry")
	now, elapsed = 765, 7
	sample()
	assert(row.peak == 7 and row.slow == 2, "sampling resumes after reload grace")

	-- The session remembers a spike before a later explicit measurement begins.
	event(sampler, "ADDON_LOADED", ns.name)
	local own = metrics[ns.name]
	local savedClock = debugprofilestop
	local clock = 0
	debugprofilestop = function() return clock end
	local slow = ns.Measured("Test: session spike", function() clock = clock + 31 end)
	slow() -- this frame was already sampled before the callback ran
	now, elapsed = 766, 33.3
	ns.Measured("Test: next frame", function() clock = clock + 40 end)()
	sample()
	assert(own.peak == 33.3 and own.peakCall == "Test: session spike" and own.peakCallTime == 31,
		"a larger callback from the current frame does not label the previous frame's spike")
	assert(not ns.timings["Test: session spike"], "session attribution does not collect detailed call statistics")
	debugprofilestop = savedClock

	local perf = uv(info.UpdatePerformance, "perfFrame")
	local added = GameTooltip.AddLine
	local peakLine = ns.L.INFO_CPU_PEAK_CALL:format("Test: session spike", 31)
	local sawPeak = false
	GameTooltip.AddLine = function(_, line) sawPeak = sawPeak or line == peakLine end
	perf:GetScript("OnEnter")(perf)
	GameTooltip.AddLine = added
	assert(sawPeak, "the session peak call is visible without starting a measurement")
	now, elapsed = 767, 0.4
	sample()
	now, elapsed = 768, 40
	sample()
	assert(own.peak == 40 and not own.peakCall and own.slowFrame == 33.3 and own.slowCall == "Test: session spike",
		"an unattributed peak retains the most recent attributed slow frame")
	local slowLine = ns.L.INFO_CPU_LAST_SLOW_CALL:format(33.3, "Test: session spike", 31)
	local sawSlow = false
	GameTooltip.AddLine = function(_, line) sawSlow = sawSlow or line == slowLine end
	perf:GetScript("OnEnter")(perf)
	GameTooltip.AddLine = added
	assert(sawSlow, "the tooltip still shows the last attributable spike")
	local mouseUp = perf:GetScript("OnMouseUp")
	local savedShift = IsShiftKeyDown
	local savedResult = info.lastMeasure
	info.lastMeasure = {}
	IsShiftKeyDown = function() return true end
	mouseUp(perf, "LeftButton")
	assert(row.peak == 0 and row.slow == 0 and row.recentCount == 0 and row.recentTotal == 0
		and own.peak == 0 and not own.peakAt and not own.peakCall and info.lastMeasure and not ns.measureUntil,
		"shift-left-click resets the session only")
	now = 769
	sample()
	assert(row.recentCount == 0 and own.peak == 0, "the last frame from before reset is discarded")
	now, elapsed = 770, 0.4
	sample()
	assert(row.recentCount == 1 and row.recentTotal == 0.4 and own.peak == 0.4, "sampling restarts immediately")
	IsShiftKeyDown, info.lastMeasure = savedShift, savedResult
	event(sampler, "LOADING_SCREEN_ENABLED")
	GetTime, C_AddOnProfiler.GetAddOnMetric = savedTime, savedMetric
	print("cpu sampling grace OK")
end)()
;(function()
	-- Collection of >5 ms moments: multi-call attribution, external addons, tooltip, copyable window, cap and reset.
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local event = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local perf = uv(info.UpdatePerformance, "perfFrame")
	local mouseUp = perf:GetScript("OnMouseUp")
	local savedTime, savedMetric = GetTime, C_AddOnProfiler.GetAddOnMetric
	local savedClock, savedDate, savedCombat = debugprofilestop, rawget(_G, "date"), InCombatLockdown
	local savedShift, savedEdit = IsShiftKeyDown, ns.ShowEditWindow
	local savedAddLine, savedAddDouble, savedAddNormal = GameTooltip.AddLine, GameTooltip.AddDoubleLine, GameTooltip_AddNormalLine

	local now, clock = 770.5, 0
	local perAddon = {}
	local combat = false
	local clockText = "19:00:01"
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	date = function() return clockText end
	InCombatLockdown = function() return combat end
	C_AddOnProfiler.GetAddOnMetric = function(name) return perAddon[name] or 0 end
	IsShiftKeyDown = function() return false end

	-- End loading screen + wait out zone grace (770.5 + 20 = 790.5).
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 791.0
	sample()
	assert(info.SpikesText(true) == nil, "no moments recorded before any >5 ms frame")

	-- Frame 1 (791.0): multiple ForeverPlus calls, including one repeated 3x (6.0 ms total > 2.2 ms single call).
	local fnRepeat = ns.Measured("Items: repeat", function() clock = clock + 2.0 end)
	local fnOther = ns.Measured("Quests: tracker", function() clock = clock + 2.2 end)
	fnRepeat()
	fnRepeat()
	fnRepeat()
	fnOther()
	-- Frame 2 (791.1): another slow call arrives BEFORE OnUpdate samples frame 791.0; must not leak into frame 791.0.
	now, combat, clockText = 791.1, true, "19:00:02"
	local fnNext = ns.Measured("Dialog: update", function() clock = clock + 8.5 end)
	fnNext()
	perAddon = { [ns.name] = 9.4, Slow = 0.2 }
	sample()

	-- Frame 3 (791.2): sample frame 791.1 (Dialog: update 8.5 ms) + external addon spike (Slow 7.3 ms).
	now, combat, clockText = 791.2, false, "19:00:03"
	local fnThird = ns.Measured("Tooltip: item", function() clock = clock + 0.4 end)
	fnThird()
	perAddon = { [ns.name] = 9.1, Slow = 7.3 }
	sample()

	-- Frame 4 (791.3): normal frame (<5 ms), must not add a moment.
	now, clockText = 791.3, "19:00:04"
	perAddon = { [ns.name] = 1.2, Slow = 0.5 }
	sample()

	-- Frame 5 (791.4): unattributed >5 ms frame for ForeverPlus (no call >= 0.25 ms in frame 791.3).
	now, clockText = 791.4, "19:00:05"
	perAddon = { [ns.name] = 5.6, Slow = 0.1 }
	sample()

	-- Frame 6 (791.5): second hit of Items: repeat (tests grouping count = 2).
	fnRepeat()
	fnRepeat()
	fnRepeat()
	now, clockText = 791.5, "19:00:06"
	perAddon = { [ns.name] = 6.5, Slow = 0.1 }
	sample()

	local report = info.SpikesText()
	assert(report:find(ns.L.INFO_SPIKES_SUMMARY:format(ns.SLOW_MS, 5), 1, true), "report counts all 5 >5 ms moments: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Items: repeat", 2, 6.0, 9.4), 1, true),
		"repeated calls aggregate per frame and group across moments: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Dialog: update", 1, 8.5, 9.1), 1, true),
		"second frame keeps its own call without leakage from frame 1: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_UNATTRIBUTED:format(ns.L.INFO_SPIKES_UNATTRIBUTED, 1, 5.6), 1, true),
		"unattributed >5 ms frames appear in summary: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_ADDON_LINE:format("Slow Addon", 1, 7.3), 1, true),
		"external addon >5 ms moments appear in other addons section: " .. report)
	assert(report:find("19:00:02 | " .. ns.name .. " | 9.4 ms | " .. ns.L.INFO_SPIKES_COMBAT
		.. " | Items: repeat (6.0 ms, 3×), Quests: tracker (2.2 ms)", 1, true),
		"moment line includes combat tag and all calls sorted by total ms: " .. report)
	assert(report:find("19:00:03 | Slow Addon | 7.3 ms", 1, true), "external addon moment line formatted cleanly")
	assert(not report:find("19:00:04", 1, true), "frames under 5 ms are not collected")

	-- Tooltip lists the collected >5 ms moments and their functions.
	local tipLines = {}
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	GameTooltip.AddDoubleLine = function(_, left, right) tipLines[#tipLines + 1] = tostring(left) .. " | " .. tostring(right) end
	GameTooltip_AddNormalLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	perf:GetScript("OnEnter")(perf)
	local tipJoined = table.concat(tipLines, "\n")
	assert(tipJoined:find(ns.L.INFO_SPIKES_HEADER:format(ns.SLOW_MS, 5), 1, true), "tooltip shows moments header")
	assert(tipJoined:find("Items: repeat (6.0 ms, 3×), Quests: tracker (2.2 ms)", 1, true), "tooltip shows captured calls")
	assert(tipJoined:find(ns.L.INFO_SPIKES_EXTERNAL_NOTE, 1, true), "tooltip notes external addon limitation")

	-- Diagnose includes >5 ms moments when present.
	local diag = ns:GetModule("DataCapture").DiagnoseText()
	assert(diag:find("== " .. ns.L.DIAG_SPIKES:format(ns.SLOW_MS) .. " ==", 1, true) and diag:find("Items: repeat", 1, true),
		"diagnose report includes collected >5 ms moments")

	-- Left-click on perfFrame opens the copyable window; slash commands also open it; Reset clears everything.
	local openedKey, openedText, openedExtras
	ns.ShowEditWindow = function(key, _, text, _, _, _, extras)
		openedKey, openedText, openedExtras = key, text, extras
	end
	mouseUp(perf, "LeftButton")
	assert(openedKey == "Spikes" and openedText == report and openedExtras and openedExtras[1],
		"left-click opens spikes window with reset button")
	openedKey = nil
	SlashCmdList.FOREVERPLUS("spitzen")
	assert(openedKey == "Spikes", "/fp spitzen opens spikes window")
	openedKey = nil
	SlashCmdList.FOREVERPLUS("spikes")
	assert(openedKey == "Spikes", "/fp spikes opens spikes window")

	local shortCall = ns.Measured("Minimap: coordinates update", function() clock = clock + 0.2 end)
	shortCall()
	now, clockText = 791.6, "19:00:07"
	perAddon = { [ns.name] = 78.5 }
	sample()
	report = info.SpikesText()
	local shortLabel = ns.L.INFO_SPIKES_SHORT_CALLS:format(ns.SLOW_MS)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_UNATTRIBUTED:format(shortLabel, 1, 78.5), 1, true)
		and not report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Minimap: coordinates update", 1, 0.2, 78.5), 1, true),
		"a short call does not get the large frame attributed to it in the summary")
	assert(report:find("78.5 ms | Minimap: coordinates update (0.2 ms)", 1, true),
		"the short call is still visible in frame details")

	-- Ring-buffer cap keeps latest 100 moments while tracking total count.
	for i = 1, 102 do
		now = 792.0 + i * 0.05
		perAddon = { [ns.name] = 0, Slow = 6.0 }
		sample()
	end
	local capped = info.SpikesText()
	assert(capped:find(ns.L.INFO_SPIKES_SUMMARY_CAPPED:format(ns.SLOW_MS, 108, 100), 1, true),
		"cap preserves total count and keeps last 100 moments: " .. capped:sub(1, 80))

	-- Reset button clears moments and session metrics.
	openedExtras[1].onClick()
	assert(info.SpikesText(true) == nil and openedText == ns.L.INFO_SPIKES_EMPTY:format(ns.SLOW_MS),
		"reset button clears collected moments and refreshes window")
	assert(not ns:GetModule("DataCapture").DiagnoseText():find("== " .. ns.L.DIAG_SPIKES:format(ns.SLOW_MS) .. " ==", 1, true),
		"diagnose omits moments section after reset")

	GameTooltip.AddLine, GameTooltip.AddDoubleLine, GameTooltip_AddNormalLine = savedAddLine, savedAddDouble, savedAddNormal
	IsShiftKeyDown, ns.ShowEditWindow = savedShift, savedEdit
	debugprofilestop, date, InCombatLockdown = savedClock, savedDate, savedCombat
	event(sampler, "LOADING_SCREEN_ENABLED")
	GetTime, C_AddOnProfiler.GetAddOnMetric = savedTime, savedMetric
	print("cpu spike moments OK")
end)()
-- Grey item keep exception
local itemsM = ns:GetModule("Items")
C_Container.GetContainerItemInfo = function() return { itemID = 99, hyperlink = "[grey]", quality = 0, stackCount = 1 } end
Enum.ItemQuality.Poor = 0
local isJunk = uv(uv(uv(uv(itemsM.MERCHANT_SHOW, "StartSelling"), "SellBatch"), "IsJunk"), "IsJunkItem")
assert(isJunk({ itemID = 99, quality = 0 }) == true, "grey is junk")
ForeverPlus_ToggleJunkUnderMouse()
assert(itemsM.db.keep[99], "grey kept")
assert(isJunk({ itemID = 99, quality = 0 }) == false, "kept grey not junk")
ForeverPlus_ToggleJunkUnderMouse()
assert(not itemsM.db.keep[99] and isJunk({ itemID = 99, quality = 0 }), "grey junk again")
print("keep OK")
-- Quests: progress then completion sounds
local quests = ns:GetModule("Quests")
local played = {}
PlaySound = function(kit) played[#played + 1] = tostring(kit) end
PlaySoundFile = function(path) played[#played + 1] = path return true end
SOUNDKIT = { MAP_PING = "ping", IG_QUEST_LIST_COMPLETE = "done", RAID_WARNING = "rw" }
local qstate = { done = 0, complete = false }
C_QuestLog.GetNumQuestLogEntries = function() return 1 end
C_QuestLog.GetInfo = function() return { questID = 5, isHeader = false } end
C_QuestLog.GetQuestObjectives = function() return { { numFulfilled = qstate.done } } end
C_QuestLog.GetNumQuestObjectives = function() return 1 end
GetQuestObjectiveInfo = function() return "", "monster", false, qstate.done, 2 end
C_QuestLog.IsComplete = function() return qstate.complete end
C_QuestLog.IsFailed = function() return false end
C_QuestLog.GetLogIndexForQuestID = function() return 1 end
GetNumQuestLeaderBoards = function() return 1 end
C_NamePlate = { GetNamePlates = function() return {} end }
local scan = uv(uv(quests.OnLogin, "QueueScan"), "ScanQuests")
scan(); qstate.done = 1; scan(); qstate.done = 2; qstate.complete = true; scan()
print("  sounds:", table.concat(played, ","))
assert(played[1] == 558137 or played[1] == "558137", "quest progress sound")
;(function()
	-- Quests: the log scan reads objectives without per-quest tables and keeps its own state tables.
	local questState = uv(scan, "state")
	local savedObjectives, savedInfo, savedNum = C_QuestLog.GetQuestObjectives, C_QuestLog.GetInfo, C_QuestLog.GetNumQuestLogEntries
	local savedChat, savedInGroup, savedInRaid = C_ChatInfo, IsInGroup, IsInRaid
	local objectiveTables = 0
	C_QuestLog.GetQuestObjectives = function() objectiveTables = objectiveTables + 1 return {} end
	local entries = { 5 }
	C_QuestLog.GetNumQuestLogEntries = function() return #entries end
	C_QuestLog.GetInfo = function(index) return { questID = entries[index], isHeader = false, title = "Kobolde" } end
	local sent = {}
	C_ChatInfo = { SendChatMessage = function(text, channel) sent[#sent + 1] = channel .. ":" .. text end }
	IsInGroup = function(category) return category == nil end
	IsInRaid = function() return false end
	quests.db.sharePartial = true
	qstate.done, qstate.complete = 0, false
	scan()
	local entry = questState[5]
	assert(entry and entry.done == 0, "the scan records the quest")
	qstate.done = 1
	scan()
	assert(questState[5] == entry and entry.done == 1 and entry.counts[1] == 1, "the scan updates the same state table")
	assert(#sent == 1 and sent[1]:find("^PARTY:") and sent[1]:find("Kobolde", 1, true), "a moved objective goes to the group")
	scan()
	assert(#sent == 1, "an unchanged objective is not shared again")
	assert(objectiveTables == 0, "the scan does not build objective tables")
	entries = {}
	scan()
	assert(questState[5] == nil, "a quest that left the log leaves the state")
	quests.db.sharePartial = false
	C_QuestLog.GetQuestObjectives, C_QuestLog.GetInfo, C_QuestLog.GetNumQuestLogEntries = savedObjectives, savedInfo, savedNum
	C_ChatInfo, IsInGroup, IsInRaid = savedChat, savedInGroup, savedInRaid
	print("quest scan state OK")
end)()
;(function()
	local bagOptions
	for _, page in ipairs(ns.SettingsPages) do
		for _, entry in ipairs(page) do
			if entry[1] == "Items" and entry.header == ns.L.ITEMS_BAGS then
				bagOptions = entry.keys
			end
		end
	end
	local preview, choices
	for _, opt in ipairs(itemsM.options) do
		if opt.type == "button" and opt.name == ns.L.ITEMS_FULL_SOUND_TEST then
			preview = opt
		elseif opt.key == "fullSoundChoice" then
			choices = opt.values()
		end
	end
	assert(preview and bagOptions and bagOptions[preview.key], "the Bags settings include the sound preview")
	local db = itemsM.db
	assert(db.fullSoundChoice == "warning" and choices[1][1] == "warning", "the warning is the default and first choice")
	local warning = 567459
	preview.func()
	assert(played[#played] == warning, "the preview plays the client's quest failure sound")
	local savedTime, last = GetTime, itemsM.fullState.last
	GetTime = function() return 100 end
	itemsM.fullState.last = 0
	local count = #played
	itemsM.PlayFullSound()
	itemsM.PlayFullSound()
	assert(#played == count + 1 and played[#played] == warning, "the bag event plays the same warning with its cooldown")
	GetTime, itemsM.fullState.last = savedTime, last
	local savedPlayFile = PlaySoundFile
	PlaySoundFile = function() return false end
	preview.func()
	assert(played[#played] == "rw", "the warning falls back to the client's raid warning")
	PlaySoundFile = savedPlayFile

	itemsM.db.fullSoundChoice = "complete"
	preview.func()
	itemsM.db.fullSoundChoice = "ping"
	preview.func()
	assert(played[#played - 1] == "done" and played[#played] == "ping", "the preview plays the selected bag sound")
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "ping", "a Ping selected after the update survives reload")
	db.fullSoundDefaultUpdated = nil
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "warning", "the legacy Ping default switches to the warning once")
	db.fullSoundDefaultUpdated, db.fullSoundChoice = nil, "none"
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "none", "a different saved choice survives the update")
	db.fullSoundChoice = "warning"
end)()
-- Keyword alert
local chat = ns:GetModule("Chat")
UnitClass = function() return "Schamane", "SHAMAN" end
chat.cdb = chat.cdb or {}
chat.cdb.keywords = nil; chat.db.keywords = "Ony, raid"; chat.db.keywordAlert = true
Ambiguate = function(n) return n end
chat:UpdateKeywordAlert()
played = {}
local onMsg = uv(chat.UpdateKeywordAlert, "OnChatMessage") or uv(uv(chat.UpdateKeywordAlert, "ParseKeywords"), "x")
onMsg(chat, "CHAT_MSG_GUILD", "wer kommt mit zu ONY?", "Someone")
assert(played[1] == "rw", "keyword sound")
print("  keywords:", chat.cdb.keywords)
assert(chat.cdb.keywords:find("Schamane") and chat.cdb.keywords:find("Ony"), "keyword defaults")
print("keyword OK")
-- Loot roll counts
items = ns:GetModule("Items")
Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local f = NewFrame("Frame", "GroupLootFrame1"); f.rollID = 7
f.LootButtonContainer = { NeedButton = NewFrame("B"), GreedButton = NewFrame("B"), PassButton = NewFrame("B") }
C_LootHistory = { GetSortedInfoForDrop = function() return { itemHyperlink = "item:1", rollInfos = {
	{ playerName = "A", playerClass = "MAGE", state = 0 }, { playerName = "B", playerClass = "MAGE", state = 3 }, { playerName = "C", playerClass = "MAGE", state = 5 } } } end }
GetLootRollItemLink = function() return "item:1" end
C_Item.GetItemInfoInstant = function() return 1 end
items:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 2)
print("roll OK")
-- XP text formats
xp = ns:GetModule("XPBar")
GetXPExhaustion = function() return 500 end
BreakUpLargeNumbers = function(n) return tostring(n) end
local barText = uv(uv(xp.OnLogin, "HookBars"), "UpdateBars")
local textFn = uv(barText, "UpdateText")
local bar = { currXP = 1250, maxBar = 5000, IsCapped = function() return false end, SetBarText = function(_, t) print("  xp:", t) end }
for _, f in ipairs({ "percent", "both", "remaining", "full" }) do xp.db.format = f; textFn(bar) end
-- XP per hour: level-ups count, no figure in the first two minutes
;(function()
	xp.ResetRate()
	xp.TrackXP(1000, 4000, 5000)
	xp.TrackXP(1060, 4600, 5000)
	assert(xp.Rate(1060) == nil, "no rate during the warm-up")
	xp.TrackXP(1200, 300, 6000)
	assert(xp.Rate(1200) == 1300 / 200 * 3600, "level-up adds the rest of the old level")
	local oldGetTime = GetTime
	GetTime = function() return 1200 end
	assert(xp.Rate(1200) and xp.RateText(2340):find("23400", 1, true) and xp.RateText(2340):find("0:06", 1, true),
		"rate and time to level")
	xp.db.xpRate = false
	assert(xp.RateText(2340) == nil, "option turns the rate off")
	xp.db.xpRate = true
	local text
	xp.db.format = "full"
	textFn({ currXP = 300, maxBar = 6000, IsCapped = function() return false end, SetBarText = function(_, t) text = t end })
	GetTime = oldGetTime
	assert(text:find(ns.L.XP_RATE:format("23400"), 1, true), "full text carries the rate")
	-- short bars: the least important parts go first, at the end only the percent
	local parts = { { text = "AAAA", keep = 6, short = "A" }, { text = "BB", keep = 5 }, { text = "CC", keep = 1 },
		{ text = "DD", keep = 4 } }
	local function Fits(limit) return function(t) return #t <= limit end end
	assert(xp.FitParts(parts, Fits(100)) == "AAAA – BB – CC – DD", "everything when there is room")
	assert(xp.FitParts(parts, Fits(#"AAAA – BB – DD")) == "AAAA – BB – DD", "rested goes first")
	assert(xp.FitParts(parts, Fits(#"AAAA – BB")) == "AAAA – BB", "then the lower parts")
	assert(xp.FitParts(parts, Fits(3)) == "A", "the short form last")
	assert(#parts == 4, "the parts stay as they were")
	local shown
	local label = { SetText = function(_, t) shown = t end, GetUnboundedStringWidth = function() return #shown * 6 end }
	textFn({ currXP = 300, maxBar = 6000, IsCapped = function() return false end, GetWidth = function() return 200 end,
		OverlayFrame = { Text = label }, SetBarText = function(_, t) text = t end })
	assert(#text * 6 <= 200 - 12 and text:find("300", 1, true), "the bar text fits the bar")
	xp.ResetRate()
	print("xp per hour OK")
end)()
-- Loot sparkle: set, kept against graphics presets, the earlier value comes back
;(function()
	local q = ns:GetModule("Quests")
	local cvars, sets = { outlineModeShowLootEffectWhenDisabled = "0" }, 0
	local oldGet, oldSet = GetCVar, SetCVar
	GetCVar = function(name) return cvars[name] end
	SetCVar = function(name, value) cvars[name] = value sets = sets + 1 end
	q.db.lootSparkle, q.db.sparkleBefore = true, nil
	q.ApplySparkle()
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "1" and q.db.sparkleBefore == "0", "option switches the sparkle on")
	cvars.outlineModeShowLootEffectWhenDisabled = "0"
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	eventFrame:GetScript("OnEvent")(eventFrame, "CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled", "0")
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "1" and q.db.sparkleBefore == "0", "a graphics preset cannot switch it off")
	q.db.lootSparkle = false
	q:OnOptionChanged("lootSparkle", false)
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "0" and q.db.sparkleBefore == nil, "turning off restores the earlier value")
	local before = sets
	cvars.outlineModeShowLootEffectWhenDisabled = nil
	q.ApplySparkle()
	assert(sets == before, "unknown setting is left alone")
	GetCVar, SetCVar = oldGet, oldSet
	print("loot sparkle OK")
end)()
-- Items owned by all characters: bags (with gear) and bank add up, the most first, the current character on ties
;(function()
	local bank = ns:GetModule("BankView")
	local inventories = {
		["Ana-Realm"] = { name = "Ana", class = "MAGE", bags = { [2589] = 3 }, bank = { [2589] = 2 } },
		["Bo-Realm"] = { name = "Bo", class = "WARRIOR", bags = { [2589] = 5 }, bank = {} },
		["Cy-Realm"] = { name = "Cy", bags = {}, bank = { [2589] = 5, [774] = 1 } },
		["Broken"] = "x",
	}
	local total, rows = bank.Owned(inventories, 2589, "Cy-Realm")
	assert(total == 15 and #rows == 3, "counts of all characters add up")
	assert(rows[1].key == "Cy-Realm" and rows[2].key == "Ana-Realm" and rows[3].key == "Bo-Realm",
		"most first, current character first on ties")
	assert(rows[2].bags == 3 and rows[2].bank == 2, "bags and bank stay apart")
	assert(bank.Owned(inventories, 999, "Ana-Realm") == 0 and bank.Owned(nil, 2589) == 0, "nothing owned")
	print("owned counts OK")
end)()
-- Profiles as text: round trip, damaged and foreign texts are refused, imports are cleaned and never overwrite
;(function()
	local profiles = ns:GetModule("Profiles")
	local value = { a = "x:y;T E", [3] = 1.25, nested = { flag = true, off = false, list = { "k1", "k2" } }, ["ü"] = "ä" }
	local text = profiles.Encode(value)
	local back = profiles.Decode("  " .. text .. "  ")
	assert(back and back.a == "x:y;T E" and back[3] == 1.25 and back.nested.flag == true and back.nested.off == false
		and back.nested.list[2] == "k2" and back["ü"] == "ä", "round trip keeps strings, numbers, booleans and nesting")
	assert(profiles.Decode(text:sub(1, -2)) == nil, "a cut text is refused")
	assert(profiles.Decode(text .. "x") == nil, "trailing rubbish is refused")
	assert(profiles.Decode("return os.exit()") == nil and profiles.Decode("FP1:s99:abc") == nil, "foreign texts are refused")
	local deep = "FP1:" .. ("Ts1:a"):rep(40) .. "b1" .. ("E"):rep(40)
	assert(profiles.Decode(deep) == nil, "nesting has a limit")
	local oldStore = ns.db.profiles
	ns.db.profiles = { Main = { time = 5, cvars = { a = "1" }, bindings = { JUMP = { "SPACE" } }, layouts = {}, addon = {} } }
	local exported = profiles.ExportText("Main")
	local evil = profiles.Encode({ name = "Main", profile = { cvars = { ok = "1", bad = 5, gxApi = "x" },
		bindings = { JUMP = { "SPACE", 7 }, X = "nope" }, layouts = { { name = "L", text = "t" }, { name = 1 } }, extra = "drop" } })
	local name = profiles.ImportText(evil)
	local kept = ns.db.profiles[name]
	assert(name == "Main (2)" and ns.db.profiles.Main.cvars.a == "1", "import never overwrites a profile")
	assert(kept.cvars.ok == "1" and kept.cvars.bad == nil and kept.cvars.gxApi == nil and kept.cvarCount == 1,
		"imported console settings are cleaned")
	assert(#kept.bindings.JUMP == 1 and kept.bindings.X == nil and #kept.layouts == 1 and kept.extra == nil
		and kept.automatic == false, "imported bindings and layouts are cleaned")
	assert(profiles.ImportText(exported) == "Main (3)", "an exported profile comes back")
	assert(profiles.ImportText("FP1:Tb1") == nil, "a broken text keeps nothing")
	ns.db.profiles = oldStore
	print("profile text OK")
end)()
-- Player notes: keys, menu, tooltip, warnings about marked enemies
;(function()
	local notes = ns:GetModule("PlayerNotes")
	assert(notes.Key("Thrall", "", "Die Aldor") == "thrall-diealdor" and notes.Key("Thrall-DieAldor") == "thrall-diealdor"
		and notes.Key("Jaina", "Kult der Verdammten", "X") == "jaina-kultderverdammten" and notes.Key("") == nil, "player keys")
	local last = {}
	assert(not notes.ShouldWarn({ tag = "friend" }, "a", 10, last), "friends give no warning")
	assert(notes.ShouldWarn({ tag = "enemy" }, "a", 10, last) and not notes.ShouldWarn({ tag = "enemy" }, "a", 200, last)
		and notes.ShouldWarn({ tag = "enemy" }, "a", 311, last), "enemy warnings pause for five minutes")
	local oldStore = ns.db.playerNotes
	ns.db.playerNotes = {}
	local saved = {}
	for _, key in ipairs({ "UnitIsPlayer", "UnitIsUnit", "UnitFullName", "GetRealmName", "PlaySound", "GameTooltip", "time" }) do
		saved[key] = rawget(_G, key)
	end
	UnitIsPlayer = function(unit) return unit ~= "npc" end
	UnitIsUnit = function() return false end
	UnitFullName = function(unit) if unit == "target" then return "Gank", "Andere Welt" end return "Bob", nil end
	GetRealmName = function() return "Heim" end
	local sounds, now = 0, 1000
	PlaySound = function() sounds = sounds + 1 end
	time = function() return now end
	-- menu: note window and marks
	local entries, root = {}, {}
	function root:CreateDivider() end
	function root:CreateTitle() end
	function root:CreateButton(text, fn) entries[#entries + 1] = { text = text, fn = fn } end
	function root:CreateCheckbox(text, isSet, toggle) entries[#entries + 1] = { text = text, isSet = isSet, toggle = toggle } end
	local add = uv(notes.OnLogin, "AddMenuEntries")
	add(nil, root, { unit = "target" })
	assert(#entries == 3 and entries[2].text == ns.L.NOTES_ENEMY and not entries[2].isSet(), "menu offers a note and two marks")
	entries[2].toggle()
	local key = notes.Key("Gank", "Andere Welt")
	assert(notes.Get(key).tag == "enemy" and entries[2].isSet() and not entries[3].isSet(), "enemy mark set from the menu")
	entries[3].toggle()
	assert(notes.Get(key).tag == "friend", "marks replace each other")
	entries[3].toggle()
	assert(notes.Get(key) == nil, "unmarked player without note is removed")
	local oldEdit = ns.ShowEditWindow
	ns.ShowEditWindow = function(_, _, _, _, accept) accept("Camps the flight master") end
	entries[1].fn()
	ns.ShowEditWindow = oldEdit
	assert(notes.Get(key).note == "Camps the flight master", "note saved from the window")
	wipe(entries)
	add(nil, root, { name = "Ally-Heim" })
	assert(#entries == 3, "chat names get the menu too")
	-- tooltip
	local lines = {}
	GameTooltip = { IsForbidden = function() return false end, GetUnit = function() return "Gank", "target" end,
		AddLine = function(_, text) lines[#lines + 1] = text end }
	notes.Set(key, "Gank", nil, "enemy")
	uv(notes.OnLogin, "OnUnitTooltip")(GameTooltip)
	assert(lines[1] == ns.L.NOTES_ENEMY .. ": Camps the flight master" and notes.Get(key).seen == now, "note in the tooltip")
	-- warning when a marked enemy shows up
	local printed = {}
	local oldPrint = ns.PrintAlways
	ns.PrintAlways = function(fmt, ...) printed[#printed + 1] = fmt:format(...) end
	notes:Apply()
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	eventFrame:GetScript("OnEvent")(eventFrame, "PLAYER_TARGET_CHANGED")
	eventFrame:GetScript("OnEvent")(eventFrame, "PLAYER_TARGET_CHANGED")
	assert(#printed == 1 and printed[1]:find("Gank", 1, true) and sounds == 1, "one warning with sound")
	notes.db.enabled = false
	notes:Apply()
	notes.db.enabled = true
	notes:Apply()
	ns.PrintAlways = oldPrint
	for k, v in pairs(saved) do _G[k] = v end
	ns.db.playerNotes = oldStore
	local hasChoice, hasTest
	for _, option in ipairs(notes.options) do
		if option.key == "enemySoundChoice" then hasChoice = #option.values() >= 3 end
		if option.type == "button" and option.func then hasTest = true end
	end
	assert(hasChoice and hasTest, "enemy sound: a choice of at least three and a test button")
	local played
	local oldPlay = ns.AlertSounds.play
	ns.AlertSounds.play = function(choice) played = choice end
	ns.AlertSounds.PlayWarning("ping")
	ns.AlertSounds.play = oldPlay
	assert(played == "ping", "a chosen sound is played")
	print("player notes OK")
end)()
-- Scout: node kinds, remembered spots, rare announcements
;(function()
	local scout = ns:GetModule("Scout")
	local list = {}
	scout.AddNode(list, 1731, "ore", 0.5, 0.5)
	scout.AddNode(list, 1731, "ore", 0.503, 0.498)
	scout.AddNode(list, 1731, "ore", 0.6, 0.5)
	scout.AddNode(list, 1617, "herb", 0.5, 0.5)
	assert(#list == 3 and list[1][5] == 2, "the same spot counts again, other spots and nodes are new")
	local last = {}
	assert(scout.ShouldAnnounce("g", 10, last) and not scout.ShouldAnnounce("g", 500, last)
		and scout.ShouldAnnounce("g", 611, last), "rares are announced again after ten minutes")
	-- gathering from a loot window
	local globals = { "C_Map", "UnitClassification", "UnitIsDead", "UnitGUID", "UnitName", "UnitLevel", "PlaySound",
		"GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSourceInfo", "IsFishingLoot" }
	local saved = {}
	for _, key in ipairs(globals) do
		saved[key] = rawget(_G, key)
	end
	local oldNodes, oldItem = ns.db.gatherNodes, C_Item
	local oldLootSlotTypes = Enum.LootSlotType
	local sources = ns:GetModule("LootSources")
	local oldSources, oldCount, oldMerged = ns.db.lootSources, sources.count, sources.merged
	local de = GetLocale() == "deDE"
	local copper, stone, herb = de and "Kupfererz" or "Copper Ore", de and "Rauer Stein" or "Rough Stone",
		de and "Friedensblume" or "Peacebloom"
	local oldHerb = { 0.1, 0.2, 1618, "herb", 3 }
	local oldVein = { 0.2, 0.3, 1731, "ore", 2 }
	local nodes = { oldHerb, oldVein }
	ns.db.gatherNodes = { [1429] = nodes }
	ns.db.lootSources, sources.count = { ["object:1618"] = { windows = 3, items = { [2447] = 3, [774] = 1 } } }, 1
	C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.4, y = 0.6 } end }
	local legacyName, requested = nil, nil
	C_Item = {
		GetItemInfoInstant = function(id)
			if id == 774 then return id, nil, nil, nil, nil, 3, 0 end
			return id, nil, nil, nil, nil, 7, id == 2447 and 9 or 7
		end,
		GetItemNameByID = function(id) if id == 2447 then return legacyName end end,
		RequestLoadItemDataByID = function(id) requested = id end,
	}
	local guid = "GameObject-0-1-2-3-1731-0042"
	local window = { { 774, "Malachite" }, { 2770, copper }, { 2835, stone }, { 2770, copper } }
	Enum.LootSlotType = { Item = 1, Money = 2, None = 0 }
	GetNumLootItems = function() return #window end
	GetLootSlotType = function() return Enum.LootSlotType.Item end
	GetLootSlotLink = function(slot) return ("|Hitem:%d|h[%s]|h"):format(unpack(window[slot])) end
	GetLootSourceInfo = function() return guid, 1 end
	IsFishingLoot = function() return false end
	UnitGUID = function() end
	sources.CaptureWindow()
	sources.CaptureWindow()
	local vein = nodes[3]
	assert(#nodes == 3 and vein[4] == "ore" and vein[5] == 1 and vein.items[2770] == copper and vein.items[2835] == stone
		and vein.items[774] == nil, "ore and stone names come from the loot window even without cached names")
	guid = "GameObject-0-1-2-3-1618-0043"
	window = { { 2447, herb } }
	C_Map.GetPlayerMapPosition = function() return { x = 0.1, y = 0.2 } end
	local symbols = {}
	for _, source in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		pcall(source, 1429, function(_, _, symbol) if symbol.kind == "gather" then symbols[#symbols + 1] = symbol end end)
	end
	assert(#symbols == 3 and symbols[3].texture:find("Ore", 1, true), "remembered vein on the world map")
	local function TooltipLines(symbol)
		local lines = {}
		symbol.tooltip({ AddLine = function(_, line) lines[#lines + 1] = line end }, symbol)
		return lines
	end
	local lines = TooltipLines(symbols[3])
	assert(#lines == 3 and lines[1] == copper and lines[2] == stone and lines[3] == ns.L.SCOUT_GATHERED:format(1),
		"the map shows the saved materials and the gathering count")
	assert(TooltipLines(symbols[1])[1] == ns.L.SCOUT_HERB and requested == 2447, "an uncached historical name is requested")
	legacyName = herb
	assert(TooltipLines(symbols[1])[1] == herb and TooltipLines(symbols[2])[1] == ns.L.SCOUT_ORE,
		"an old map marker gets a name only if the local history identifies one material")
	sources.CaptureWindow()
	assert(#nodes == 3 and oldHerb.items[2447] == herb and oldHerb[5] == 4, "gathering at an old marker saves the name in place")
	scout.db.gatherMap = false
	wipe(symbols)
	for _, source in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		pcall(source, 1429, function(_, _, symbol) if symbol.kind == "gather" then symbols[#symbols + 1] = symbol end end)
	end
	assert(#symbols == 0, "map option hides the symbols")
	scout.db.gatherMap = true
	-- rare nameplate
	local printed, sounds = {}, 0
	local oldPrint = ns.PrintAlways
	ns.PrintAlways = function(fmt, ...) printed[#printed + 1] = fmt:format(...) end
	UnitClassification = function(unit) return unit == "nameplate1" and "rareelite" or "normal" end
	UnitIsDead = function() return false end
	UnitGUID = function(unit) return "Creature-" .. unit end
	UnitName = function() return "Mor'Ladim" end
	UnitLevel = function() return 35 end
	PlaySound = function() sounds = sounds + 1 end
	local onNameplate = uv(scout.OnLogin, "OnNameplate")
	for _, unit in ipairs({ "nameplate1", "nameplate1", "nameplate2" }) do
		onNameplate(nil, "NAME_PLATE_UNIT_ADDED", unit)
	end
	assert(#printed == 1 and printed[1]:find("Mor'Ladim", 1, true) and printed[1]:find("35", 1, true) and sounds == 1,
		"a rare is announced once")
	ns.PrintAlways = oldPrint
	for _, key in ipairs(globals) do _G[key] = saved[key] end
	ns.db.gatherNodes, C_Item = oldNodes, oldItem
	Enum.LootSlotType = oldLootSlotTypes
	ns.db.lootSources, sources.count, sources.merged = oldSources, oldCount, oldMerged
	local rareChoice
	for _, option in ipairs(scout.options) do
		if option.key == "rareSoundChoice" then rareChoice = #option.values() >= 3 end
	end
	assert(rareChoice, "rare sound: a choice of at least three")
	print("scout OK")
end)()
-- Upgrades per slot: best upgrades of each slot, wearable now before "later", loading items are counted
;(function()
	local upgrades = ns:GetModule("Upgrades")
	local picked = upgrades.Pick({
		{ id = 1, slot = "INVTYPE_HEAD", gain = 5, state = true },
		{ id = 2, slot = "INVTYPE_HEAD", gain = 9, state = "later" },
		{ id = 3, slot = "INVTYPE_HEAD", gain = 7, state = true },
		{ id = 4, slot = "INVTYPE_HEAD", gain = 6, state = true },
		{ id = 5, slot = "INVTYPE_FEET", gain = 2, state = true },
		{ id = 6, slot = "INVTYPE_FEET", gain = 0, state = true },
		{ id = 7, slot = "INVTYPE_HAND", gain = 3, state = false },
	}, 3, upgrades.ORDER)
	assert(#picked == 2 and picked[1].slot == "INVTYPE_HEAD" and picked[2].slot == "INVTYPE_FEET", "slots in window order")
	assert(#picked[1].rows == 3 and picked[1].rows[1].id == 3 and picked[1].rows[2].id == 4 and picked[1].rows[3].id == 1,
		"wearable now first, by gain, three per slot")
	assert(#picked[2].rows == 1, "no gain is no upgrade")
	-- rating candidates from the loot data
	local oldData, oldItem, oldState, oldGain = ns.LootData, C_Item, ns.ItemLinkUpgradeState, ns.ItemUpgradeGain
	ns.LootData = { names = {}, items = { [100] = { { "npc:9", 1, 4 } }, [101] = {}, [102] = {} },
		encounters = { [2741] = { 4, { { 103, 2 } } } } }
	local loads = {}
	C_Item = setmetatable({
		GetItemInfoInstant = function(id) return id, nil, nil, id == 101 and "" or "INVTYPE_HEAD" end,
		GetItemInfo = function(id) if id ~= 102 then return "Item " .. id, "item:" .. id, 2, nil, 30 end end,
		RequestLoadItemDataByID = function(id) loads[#loads + 1] = id end,
		GetItemIconByID = function() return 1 end,
	}, { __index = oldItem })
	ns.ItemLinkUpgradeState = function(link) return link == "item:100" and true or link == "item:103" and "later" or false end
	ns.ItemUpgradeGain = function(link) return link == "item:100" and 4 or 8 end
	local rows, loading = upgrades.Rate()
	assert(#rows == 2 and loading == 1 and loads[1] == 102, "equippable candidates rated, missing data requested")
	local built = uv(upgrades.Open, "Build")()
	assert(built.items[1].text and built.items[2].text == "Item 100" and built.items[3].text:find("Item 103", 1, true)
		and built.items[3].right == "50%", "list with header, items and boss share")
	assert(built.title == ns.L.UPGRADES_LOADING:format(1), "title tells what is still loading")
	ns.LootData, C_Item, ns.ItemLinkUpgradeState, ns.ItemUpgradeGain = oldData, oldItem, oldState, oldGain
	-- the button lies above the character model scene
	local oldSlot, oldScene, oldPaper = rawget(_G, "CharacterMainHandSlot"), rawget(_G, "CharacterModelScene"), rawget(_G, "PaperDollFrame")
	CharacterMainHandSlot = { GetFrameLevel = function() return 12 end }
	CharacterModelScene = { GetFrameLevel = function() return 50 end }
	PaperDollFrame = CreateFrame("Frame")
	local level
	local oldCreate = CreateFrame
	CreateFrame = function(...)
		local f = oldCreate(...)
		f.SetFrameLevel = function(_, value) level = value end
		return f
	end
	local create = uv(upgrades.OnLogin, "CreateButton")
	for index = 1, 20 do
		if debug.getupvalue(create, index) == "button" then debug.setupvalue(create, index, nil) break end
	end
	create()
	CreateFrame = oldCreate
	assert(level == 55, "button above the model scene")
	CharacterMainHandSlot, CharacterModelScene, PaperDollFrame = oldSlot, oldScene, oldPaper
	print("upgrades per slot OK")
end)()
-- XP bar: extra shrinking
;(function()
	STATUS_BAR_SIZE_ADJUSTMENT = 3
	local w, h = xp.ScaledSize(1000, 17, 100, 100)
	assert(w == 1000 and h == 17, "100% leaves the size")
	w, h = xp.ScaledSize(1000, 17, 50, 50)
	assert(w == 500 and h == 8.5, "50% halves the size")
	w, h = xp.ScaledSize(1000, 17, 10, 30)
	assert(w == 100 and h == 5.1, "small sizes follow the percent")
	w, h = xp.ScaledSize(1000, 17, 0, 0)
	assert(w == 5 and h == 5, "never smaller than adjustment + 2")
	w, h = xp.ScaledSize(4, 4, 100, 100)
	assert(w == 4 and h == 4, "never larger than the standard size")
	local hookBars = uv(xp.OnLogin, "HookBars")
	local hookContainer, onSize, applySizes = uv(hookBars, "HookContainer"), uv(uv(hookBars, "HookContainer"), "OnContainerSize"), uv(xp.OnOptionChanged, "ApplySizes")
	assert(xp.SegmentCount(20, 1000, 1000) == 20, "full width keeps all section strokes")
	assert(xp.SegmentCount(20, 500, 1000) == 10, "half width keeps half the strokes at the same distance")
	assert(xp.SegmentCount(20, 10, 1000) == 1, "at least one segment")
	local function NewContainer(width)
		local c = { width = width, height = 17, resized = 0, dividers = 0, segments = nil, BarFrameTexture = { ClearAllPoints = function() end, SetPoint = function() end, GetAtlas = function() end } }
		function c:GetWidth() return self.width end
		function c:GetHeight() return self.height end
		function c:SetSize(a, b) self.width, self.height = a, b end
		function c:ResizeContainerBars() self.resized = self.resized + 1 end
		function c:UpdateDividers(n) self.dividers = self.dividers + 1; self.segments = n end
		function c:GetExpectedSegments() return 20 end
		return c
	end
	local container, second = NewContainer(600), NewContainer(600)
	SecondaryStatusTrackingBarContainer = second
	xp.db.bar1Width, xp.db.bar1Height, xp.db.bar2Width, xp.db.bar2Height = 50, 50, 100, 100
	hookContainer(container)
	hookContainer(second)
	assert(container.width == 300 and container.height == 8.5, "container 1 shrunk on hook")
	assert(second.width == 600 and second.height == 17, "container 2 keeps its own (standard) size")
	assert(container.segments == 10 and second.segments == 20, "strokes keep their distance on the narrower bar")
	container:SetSize(800, 17) -- Blizzard or Edit Mode sets a new standard size
	onSize(container)
	assert(container.width == 400 and container.height == 8.5 and container.segments == 10, "new standard size is shrunk again")
	-- The built-in Edit Mode width slider keeps the height already set by us.
	for _, width in ipairs({ 700, 900 }) do
		container:SetSize(width, container:GetHeight())
		onSize(container)
		assert(container.width == width / 2 and container.height == 8.5, "the native width slider does not rescale height")
	end
	xp.db.bar2Width, xp.db.bar2Height = 25, 100
	applySizes()
	assert(second.width == 150 and second.height == 17 and second.segments == 5, "container 2 follows its own setting")
	assert(container.width == 450 and container.segments == 10, "container 1 is not touched by setting 2")
	xp.db.bar1Width, xp.db.bar1Height, xp.db.bar2Width, xp.db.bar2Height = 100, 100, 100, 100
	applySizes()
	assert(container.width == 900 and container.height == 17 and container.segments == 20, "100% restores the standard size and strokes")
	assert(second.width == 600 and second.segments == 20, "100% restores container 2")
	SecondaryStatusTrackingBarContainer = nil
	print("xp bar size OK")
end)()

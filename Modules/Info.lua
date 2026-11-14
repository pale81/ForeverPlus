-- Info: played time of all characters in the clock tooltip, FPS and latency
-- inside the minimap with the CPU usage of all addons on mouseover.
local _, ns = ...
local L = ns.L

local Info = ns:NewModule("Info", {
	title = L.INFO_TITLE,
	order = 5.5,
	defaults = {
		played = true,
		performance = true,
		perfColors = true,
		levelTime = true,
		characters = {}, -- "Realm" -> { name -> { total, class, level, time } }
	},
})

local PERF_INTERVAL = 1
local CPU_TOOLTIP_INTERVAL = 2
local PLAYED_TIMEOUT = 10
local CPU_LOW, CPU_HIGH = 0.5, 2 -- ms per frame on average (total line): green below 0.5, orange 0.5-2, red from 2
-- Rows of the table (highest value, frames over 5 ms): red only for a real spike or many slow frames, orange between.
local PEAK_ORANGE, PEAK_RED = 1.5, 5
local SLOW_ORANGE, SLOW_RED = 3, 20

local _, playerClass = UnitClass("player")
local playerName, playerRealm = UnitName("player"), GetRealmName()

local function ClassColor(classFile)
	return C_ClassColor.GetClassColor(classFile) or NORMAL_FONT_COLOR
end

---------------------------------------------------------------------------
-- Played time
---------------------------------------------------------------------------
local mutedFrames = {}
local playedReceived = false

local function UnmuteChat()
	for frame in pairs(mutedFrames) do
		frame:RegisterEvent("TIME_PLAYED_MSG")
	end
	wipe(mutedFrames)
end

local function CharacterEntry()
	local realm = Info.db.characters[playerRealm] or {}
	Info.db.characters[playerRealm] = realm
	local entry = realm[playerName] or {}
	realm[playerName] = entry
	entry.class, entry.level = playerClass, UnitLevel("player")
	return entry
end

---------------------------------------------------------------------------
-- Time in the level that was just finished: below the level-up message in the middle of the screen.
-- The start of every level (total played time at its beginning) is kept per character; after a level-up
-- the time between the two starts is the duration of the finished level.
---------------------------------------------------------------------------
local LEVEL_WAIT = 30       -- seconds a reached level waits for the played time
local levelPending          -- { level, at } after a level-up, until the played time arrives
local levelText, levelTextAt -- the line for the toast
local levelLine

local function ShowLevelLine()
	local manager = EventToastManagerFrame
	local toast = manager and manager.currentDisplayingToast
	local isLevel = toast and toast.toastInfo and Enum and Enum.EventToastEventType
		and toast.toastInfo.eventType == Enum.EventToastEventType.LevelUp
	if levelLine and not (isLevel and levelText) then
		levelLine:Hide()
	end
	if not (isLevel and levelText and levelTextAt and GetTime() - levelTextAt < 60) then
		return false
	end
	if not levelLine then
		levelLine = manager:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	end
	levelLine:ClearAllPoints()
	levelLine:SetPoint("TOP", toast, "BOTTOM", 0, -34)
	levelLine:SetText(levelText)
	levelLine:Show()
	return true
end

local function LevelTimeKnown(level, seconds)
	levelText = L.INFO_LEVEL_TIME:format(level - 1, SecondsToTime(seconds, true, false, 3))
	levelTextAt = GetTime()
	if not ShowLevelLine() then
		-- The message may come a little later (or not exist in this client): the line goes to the chat then.
		ns.After("Info: LevelTimeKnown (timer)", 8, function()
			if levelText and levelTextAt and GetTime() - levelTextAt >= 8 and not (levelLine and levelLine:IsShown()) then
				ns.Print(levelText)
			end
		end)
	end
end

function Info:TIME_PLAYED_MSG(_, total, levelTime)
	local entry = CharacterEntry()
	entry.total, entry.time = total, time()
	playedReceived = true
	if type(total) == "number" and type(levelTime) == "number" then
		local start = total - levelTime
		if levelPending and GetTime() - levelPending.at < LEVEL_WAIT then
			local reached = levelPending.level
			if self.db.levelTime and entry.levelStart and entry.levelStartLevel == reached - 1 and start > entry.levelStart then
				LevelTimeKnown(reached, start - entry.levelStart)
			end
		end
		levelPending = nil
		entry.levelStart, entry.levelStartLevel = start, UnitLevel("player")
	end
	-- The chat frames receive the event before this handler; unmute afterwards.
	ns.After("Info: UnmuteChat", 0, UnmuteChat)
end

-- Asks the server once per session without the chat message.
local function RequestPlayedSilently()
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if frame and frame:IsEventRegistered("TIME_PLAYED_MSG") then
			frame:UnregisterEvent("TIME_PLAYED_MSG")
			mutedFrames[frame] = true
		end
	end
	RequestTimePlayed()
	ns.After("Info: RequestPlayedSilently (timer)", PLAYED_TIMEOUT, function()
		UnmuteChat()
		-- The server sometimes ignores the first request right after login.
		if not playedReceived and not Info.retried then
			Info.retried = true
			RequestPlayedSilently()
		end
	end)
end

local function CurrentTotal(entry, isPlayer)
	if isPlayer and entry.total and entry.time then
		return entry.total + (time() - entry.time)
	end
	return entry.total
end

local function AddPlayedLines()
	if not Info.db.played or GameTooltip:GetOwner() ~= TimeManagerClockButton then
		return
	end
	local realms = {}
	for realm in pairs(Info.db.characters) do
		realms[#realms + 1] = realm
	end
	table.sort(realms)

	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddNormalLine(GameTooltip, L.INFO_PLAYED)
	local sum = 0
	for _, realm in ipairs(realms) do
		local list = {}
		for name, entry in pairs(Info.db.characters[realm]) do
			local total = CurrentTotal(entry, realm == playerRealm and name == playerName)
			if total then
				list[#list + 1] = { name = name, entry = entry, total = total }
				sum = sum + total
			end
		end
		table.sort(list, function(a, b)
			return a.total > b.total
		end)
		if #realms > 1 and #list > 0 then
			GameTooltip:AddLine(realm, 0.6, 0.6, 0.6)
		end
		for _, char in ipairs(list) do
			local label = ("%s |cff999999%d|r"):format(ClassColor(char.entry.class):WrapTextInColorCode(char.name), char.entry.level or 0)
			GameTooltip:AddDoubleLine(label, SecondsToTime(char.total, true, false, 3), 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddDoubleLine(L.INFO_PLAYED_TOTAL, SecondsToTime(sum, true, false, 3),
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- FPS / latency inside the minimap, addon CPU usage on mouseover
---------------------------------------------------------------------------
local perfFrame, perfTicker
local lastCpuTooltipUpdate = 0
local profilerSampler
local sampledAddons = {}
local tooltipRows = {}
local sessionMetrics = {}
local resetAt

local function ResetMetrics(entry)
	entry.peak, entry.slow = 0, 0
	entry.peakAt, entry.peakCall, entry.peakCallTime = nil, nil, nil
	entry.slowAt, entry.slowFrame, entry.slowCall, entry.slowCallTime = nil, nil, nil, nil
	entry.recentIndex, entry.recentCount, entry.recentTotal = 1, 0, 0
end

local function TrackAddon(name, title)
	if name and not sessionMetrics[name] then
		local label = title or name
		local entry = { name = name, title = (label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),
			own = name == ns.name, recent = {} }
		ResetMetrics(entry)
		sessionMetrics[name] = entry
		sampledAddons[#sampledAddons + 1] = entry
		tooltipRows[#tooltipRows + 1] = entry
	end
end

local LOGIN_GRACE, ZONE_GRACE = 60, 20 -- seconds
local ignoreUntil -- starts with the first PLAYER_ENTERING_WORLD, not when the file loads
local loadingScreen = false
local screenGrace = LOGIN_GRACE

local function OnProfilerEvent(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		TrackAddon(C_AddOns.GetAddOnInfo(arg1))
	elseif event == "LOADING_SCREEN_ENABLED" then
		loadingScreen = true
		screenGrace = ignoreUntil and ZONE_GRACE or LOGIN_GRACE
	elseif event == "LOADING_SCREEN_DISABLED" then
		loadingScreen = false
		if ignoreUntil then
			ignoreUntil = math.max(ignoreUntil, GetTime() + screenGrace)
		end
		screenGrace = ZONE_GRACE
	elseif event == "PLAYER_ENTERING_WORLD" then
		local grace = (not ignoreUntil or arg1 or arg2) and LOGIN_GRACE or ZONE_GRACE
		ignoreUntil = math.max(ignoreUntil or 0, GetTime() + grace)
		if loadingScreen then
			screenGrace = math.max(screenGrace, grace)
		end
	end
end

local function SampleAddonMetrics(now, peakCall, peakCallTime, previousFrameAt)
	if resetAt and (not previousFrameAt or previousFrameAt <= resetAt) then
		return
	end
	if loadingScreen or not ignoreUntil or now < ignoreUntil
		or not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then
		return
	end
	local lastTime = Enum.AddOnProfilerMetric.LastTime
	local ownElapsed
	local readMetric = C_AddOnProfiler.GetAddOnMetric
	for _, entry in ipairs(sampledAddons) do
		local elapsed = readMetric(entry.name, lastTime) or 0
		local own = entry.own
		if own then
			ownElapsed = elapsed
		end
		local index = entry.recentIndex
		if entry.recentCount == 60 then
			entry.recentTotal = entry.recentTotal - entry.recent[index]
		else
			entry.recentCount = entry.recentCount + 1
		end
		entry.recent[index] = elapsed
		entry.recentTotal = entry.recentTotal + elapsed
		entry.recentIndex = index % 60 + 1
		if elapsed > entry.peak then
			entry.peak = elapsed
			entry.peakAt = now
			if own then
				entry.peakCall, entry.peakCallTime = peakCall, peakCallTime
			end
		end
		if elapsed > ns.SLOW_MS then
			entry.slow = entry.slow + 1
			if own and peakCall then
				entry.slowAt, entry.slowFrame = now, elapsed
				entry.slowCall, entry.slowCallTime = peakCall, peakCallTime
			end
		end
	end
	return ownElapsed
end

local function SetupProfilerSampler(enabled)
	if not profilerSampler then
		profilerSampler = CreateFrame("Frame")
		profilerSampler:RegisterEvent("ADDON_LOADED")
		profilerSampler:RegisterEvent("PLAYER_ENTERING_WORLD")
		profilerSampler:RegisterEvent("LOADING_SCREEN_ENABLED")
		profilerSampler:RegisterEvent("LOADING_SCREEN_DISABLED")
		profilerSampler:SetScript("OnEvent", OnProfilerEvent)
		for i = 1, C_AddOns.GetNumAddOns() do
			if C_AddOns.IsAddOnLoaded(i) then
				TrackAddon(C_AddOns.GetAddOnInfo(i))
			end
		end
	end
	ns.SetSessionProfiler(enabled and SampleAddonMetrics or nil)
end

local function CpuColor(ms)
	if ms < CPU_LOW then
		return GREEN_FONT_COLOR
	elseif ms < CPU_HIGH then
		return ORANGE_FONT_COLOR
	end
	return RED_FONT_COLOR
end

-- "green", "orange" or "red" for a row of the table.
function Info.PeakLevel(peak, slow)
	slow = slow or 0
	if peak >= PEAK_RED or slow >= SLOW_RED then
		return "red"
	elseif peak >= PEAK_ORANGE or slow >= SLOW_ORANGE then
		return "orange"
	end
	return "green"
end

local LEVEL_COLORS = { green = GREEN_FONT_COLOR, orange = ORANGE_FONT_COLOR, red = RED_FONT_COLOR }

local function PeakColor(peak, slow)
	return LEVEL_COLORS[Info.PeakLevel(peak, slow)]
end

local function HigherPeak(a, b)
	if a.peak == b.peak then
		return a.title < b.title
	end
	return a.peak > b.peak
end

-- ForeverPlus self measurement (30 s), started from the display.
local MEASURE_SECONDS = 30
local MEASURE_LINES = 5

local function AddMeasureLines()
	if ns.measureUntil then
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddNormalLine(GameTooltip, L.INFO_MEASURE_RUNNING:format(math.max(0, ns.measureUntil - GetTime())))
		return
	end
	local result = Info.lastMeasure
	if not result then
		return
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddNormalLine(GameTooltip, L.INFO_MEASURE_RESULT)
	local stats = result.frames
	local frameColor = PeakColor(stats.worst, stats.count)
	GameTooltip:AddLine(ns.FormatMeasuredFrames(stats), frameColor.r, frameColor.g, frameColor.b, true)
	if stats.count > 0 and stats.name then
		GameTooltip:AddLine(L.TIMINGS_SPIKES:format(stats.name), 0.62, 0.62, 0.62, true)
	end
	local list = result.calls
	if #list == 0 then
		GameTooltip_AddHighlightLine(GameTooltip, L.TIMINGS_EMPTY)
	else
		GameTooltip:AddLine(L.INFO_MEASURE_CALLS, 0.62, 0.62, 0.62, true)
	end
	for _, item in ipairs(list) do
		local color = PeakColor(item.entry.max)
		GameTooltip:AddDoubleLine(item.name, ("%.1f ms (%d)"):format(item.entry.max, item.entry.count), 1, 1, 1, color.r, color.g, color.b)
	end
end

local function StartMeasure()
	if ns.measureUntil then
		return
	end
	ns.StartTimedMeasure(MEASURE_SECONDS, function()
		Info.lastMeasure = { calls = ns.TopTimings(MEASURE_LINES), frames = ns.spikes }
	end)
end

local function ShowCpuTooltip(owner)
	local now = GetTime()
	lastCpuTooltipUpdate = now
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip_SetTitle(GameTooltip, L.INFO_CPU_TITLE)
	if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then
		GameTooltip_AddNormalLine(GameTooltip, L.INFO_CPU_DISABLED)
		AddMeasureLines()
		GameTooltip:Show()
		return
	end
	table.sort(tooltipRows, HigherPeak)
	-- Sections: explanation, table (names white, values coloured), total, measurement, hints.
	GameTooltip:AddLine(L.INFO_CPU_COLUMNS, 0.62, 0.62, 0.62, true)
	if loadingScreen or not ignoreUntil then
		GameTooltip_AddInstructionLine(GameTooltip, L.INFO_CPU_WAIT_WORLD)
	elseif now < ignoreUntil then
		GameTooltip_AddInstructionLine(GameTooltip, L.INFO_CPU_WARMUP:format(math.ceil(ignoreUntil - now)))
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip:AddDoubleLine(L.INFO_CPU_HEADER_ADDON, L.INFO_CPU_HEADER_VALUES, 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
	local total = 0
	for _, addon in ipairs(tooltipRows) do
		local ms = addon.recentCount > 0 and max(0, addon.recentTotal / addon.recentCount) or 0
		total = total + ms
		local color = PeakColor(addon.peak, addon.slow)
		local own = addon.own
		GameTooltip:AddDoubleLine(addon.title, L.INFO_CPU_LINE:format(ms, addon.peak, addon.slow),
			own and NORMAL_FONT_COLOR.r or 1, own and NORMAL_FONT_COLOR.g or 1, own and NORMAL_FONT_COLOR.b or 1,
			color.r, color.g, color.b)
	end
	local own = sessionMetrics[ns.name]
	if own and own.peakAt then
		GameTooltip:AddLine(L.INFO_CPU_PEAK_AGE:format(SecondsToTime(now - own.peakAt)), 0.62, 0.62, 0.62, true)
		if own.peak >= ns.SLOW_MS then
			local line = own.peakCall and L.INFO_CPU_PEAK_CALL:format(own.peakCall, own.peakCallTime)
				or L.INFO_CPU_PEAK_UNATTRIBUTED
			GameTooltip:AddLine(line, 0.62, 0.62, 0.62, true)
			if own.slowAt and own.slowAt ~= own.peakAt then
				GameTooltip:AddLine(L.INFO_CPU_LAST_SLOW_CALL:format(own.slowFrame, own.slowCall, own.slowCallTime),
					0.62, 0.62, 0.62, true)
			end
		end
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	local color = CpuColor(total)
	GameTooltip:AddDoubleLine(L.INFO_CPU_TOTAL, ("%.2f ms"):format(total),
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, color.r, color.g, color.b)
	AddMeasureLines()
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
	GameTooltip_AddInstructionLine(GameTooltip, L.INFO_MEASURE_HINT)
	GameTooltip:Show()
end

-- FPS and latency in the colour of the class while they are good; orange when they get poor, red when bad.
local FPS_POOR, FPS_BAD = 30, 15
local MS_POOR, MS_BAD = 150, 300

local function ValueColor(value, poor, bad, lowIsBad)
	if not Info.db.perfColors then
		return ClassColor(playerClass)
	end
	local isBad, isPoor
	if lowIsBad then
		isBad, isPoor = value < bad, value < poor
	else
		isBad, isPoor = value > bad, value > poor
	end
	if isBad then
		return RED_FONT_COLOR
	elseif isPoor then
		return ORANGE_FONT_COLOR
	end
	return ClassColor(playerClass)
end

local RefreshCpuTooltip = ns.Measured("Info: CPU tooltip", ShowCpuTooltip)
local lastFPS, lastMS, lastColorSetting

local function UpdatePerformance()
	local _, _, latencyHome, latencyWorld = GetNetStats()
	local label = NORMAL_FONT_COLOR
	local fps = math.floor(ns.Number(GetFramerate(), 0))
	local ms = math.floor(max(ns.Number(latencyHome, 0), ns.Number(latencyWorld, 0)))
	if fps ~= lastFPS or ms ~= lastMS or Info.db.perfColors ~= lastColorSetting then
		lastFPS, lastMS, lastColorSetting = fps, ms, Info.db.perfColors
		perfFrame.Text:SetFormattedText("%s %s   %s %s",
			label:WrapTextInColorCode("FPS"), ValueColor(fps, FPS_POOR, FPS_BAD, true):WrapTextInColorCode(("%d"):format(fps)),
			label:WrapTextInColorCode("MS"), ValueColor(ms, MS_POOR, MS_BAD, false):WrapTextInColorCode(("%d"):format(ms)))
		perfFrame:SetSize(perfFrame.Text:GetStringWidth() + 6, perfFrame.Text:GetStringHeight() + 4)
	end
	if GameTooltip:GetOwner() == perfFrame and GetTime() - lastCpuTooltipUpdate >= CPU_TOOLTIP_INTERVAL then
		RefreshCpuTooltip(perfFrame)
	end
end

local function CreatePerfFrame()
	local frame = CreateFrame("Frame", nil, Minimap)
	frame:SetSize(120, 16)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	frame.Text = frame:CreateFontString(nil, "OVERLAY")
	frame.Text:SetPoint("CENTER")
	frame:SetScript("OnEnter", RefreshCpuTooltip)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame:SetScript("OnMouseUp", ns.Measured("Info: performance click", function(self, button)
		if button == "MiddleButton" then
			StartMeasure()
		elseif button == "LeftButton" and IsShiftKeyDown() then
			for _, entry in pairs(sessionMetrics) do
				ResetMetrics(entry)
			end
			resetAt = GetTime()
			if GameTooltip:GetOwner() == self then
				RefreshCpuTooltip(self)
			end
		end
	end))
	ns:RegisterDisplay(frame, "Performance", function(self)
		self:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 14)
	end, Minimap)
	return frame
end

function Info:UpdateFont()
	if perfFrame then
		perfFrame.Text:SetFont(ns.GetFontFace(), 12, "OUTLINE")
		lastFPS = nil -- measure the new font on the next update
	end
end

function Info:UpdatePerformance()
	-- Track world entry even if the display is only enabled later.
	SetupProfilerSampler(self.db.performance)
	if self.db.performance then
		perfFrame = perfFrame or CreatePerfFrame()
		self:UpdateFont()
		perfFrame:Show()
		perfTicker = perfTicker or ns.NewTicker("Info: UpdatePerformance", PERF_INTERVAL, UpdatePerformance)
		UpdatePerformance()
	elseif perfFrame then
		perfFrame:Hide()
		if perfTicker then
			perfTicker:Cancel()
			perfTicker = nil
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Info:OnLogin()
	CharacterEntry()
	self:RegisterEvent("TIME_PLAYED_MSG")
	self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, level)
		CharacterEntry().level = level
		if self.db.levelTime and type(level) == "number" then
			levelPending = { level = level, at = GetTime() }
			levelText = nil
			-- A moment later, so the server has counted the new level.
			ns.After("Info: RequestPlayedSilently", 1, RequestPlayedSilently)
		end
	end)
	if EventToastManagerFrame and EventToastManagerFrame.DisplayToast then
		hooksecurefunc(EventToastManagerFrame, "DisplayToast", ns.Measured("Info: level time", ShowLevelLine))
	end
	ns.After("Info: RequestPlayedSilently", 3, RequestPlayedSilently)
	ns.OnAddOnLoaded("Blizzard_TimeManager", function()
		if TimeManagerClockButton_UpdateTooltip then
			hooksecurefunc("TimeManagerClockButton_UpdateTooltip", AddPlayedLines)
			-- Blizzard fills the tooltip only on its next once-per-second update;
			-- build it right away so the list is there immediately.
			TimeManagerClockButton:HookScript("OnEnter", function()
				TimeManagerClockButton_UpdateTooltip()
			end)
		end
	end)
	self:UpdatePerformance()
end

function Info:OnOptionChanged(key)
	if key == "performance" then
		self:UpdatePerformance()
	end
end

Info.options = {
	{ key = "played", type = "toggle", name = L.INFO_PLAYED_OPT, desc = L.INFO_PLAYED_DESC },
	{ key = "performance", type = "toggle", name = L.INFO_PERF, desc = L.INFO_PERF_DESC },
	{ key = "perfColors", type = "toggle", name = L.INFO_PERF_COLORS, desc = L.INFO_PERF_COLORS_DESC, parent = "performance", new = true },
	{ key = "levelTime", type = "toggle", name = L.INFO_LEVEL_TIME_OPT, desc = L.INFO_LEVEL_TIME_DESC, new = true },
}

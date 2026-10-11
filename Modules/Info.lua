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
		characters = {}, -- "Realm" -> { name -> { total, class, level, time } }
	},
})

local PERF_INTERVAL = 1
local CPU_TOOLTIP_INTERVAL = 2
local PLAYED_TIMEOUT = 10
local CPU_LOW, CPU_HIGH = 0.5, 2 -- ms per frame: green below 0.5, orange 0.5-2, red from 2

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

function Info:TIME_PLAYED_MSG(_, total)
	local entry = CharacterEntry()
	entry.total, entry.time = total, time()
	playedReceived = true
	-- The chat frames receive the event before this handler; unmute afterwards.
	C_Timer.After(0, UnmuteChat)
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
	C_Timer.After(PLAYED_TIMEOUT, function()
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
local sessionMetrics = {}

local function TrackAddon(name)
	if name and not sessionMetrics[name] then
		sampledAddons[#sampledAddons + 1] = name
		sessionMetrics[name] = {
			peak = 0, slow = 0, average = 0,
			recent = {}, recentIndex = 1, recentCount = 0, recentTotal = 0,
		}
	end
end

-- Loading peaks (login, loading screens) are not counted: the list should show
-- what the addons cost while playing, not how long they took to load.
local LOGIN_GRACE, ZONE_GRACE = 60, 20 -- seconds
local ignoreUntil = GetTime() + LOGIN_GRACE

local function SampleAddonMetrics()
	if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) or GetTime() < ignoreUntil then
		return
	end
	local lastTime = Enum.AddOnProfilerMetric.LastTime
	for _, name in ipairs(sampledAddons) do
		local elapsed = C_AddOnProfiler.GetAddOnMetric(name, lastTime) or 0
		local entry = sessionMetrics[name]
		local index = entry.recentIndex
		if entry.recentCount == 60 then
			entry.recentTotal = entry.recentTotal - entry.recent[index]
		else
			entry.recentCount = entry.recentCount + 1
		end
		entry.recent[index] = elapsed
		entry.recentTotal = entry.recentTotal + elapsed
		entry.average = entry.recentTotal / entry.recentCount
		entry.recentIndex = index % 60 + 1
		if elapsed > entry.peak then
			entry.peak = elapsed
		end
		if elapsed > 1 then
			entry.slow = entry.slow + 1
		end
	end
end

local function SetupProfilerSampler(enabled)
	if not profilerSampler then
		profilerSampler = CreateFrame("Frame")
		profilerSampler:RegisterEvent("ADDON_LOADED")
		profilerSampler:RegisterEvent("PLAYER_ENTERING_WORLD")
		profilerSampler:SetScript("OnEvent", function(_, event, name)
			if event == "PLAYER_ENTERING_WORLD" then
				ignoreUntil = math.max(ignoreUntil, GetTime() + ZONE_GRACE)
			else
				TrackAddon(name)
			end
		end)
		for i = 1, C_AddOns.GetNumAddOns() do
			if C_AddOns.IsAddOnLoaded(i) then
				TrackAddon(C_AddOns.GetAddOnInfo(i))
			end
		end
	end
	profilerSampler:SetScript("OnUpdate", enabled and SampleAddonMetrics or nil)
end

local function CpuColor(ms)
	if ms < CPU_LOW then
		return GREEN_FONT_COLOR
	elseif ms < CPU_HIGH then
		return ORANGE_FONT_COLOR
	end
	return RED_FONT_COLOR
end

local function StripColors(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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
	local list = Info.lastMeasure
	if not list then
		return
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddNormalLine(GameTooltip, L.INFO_MEASURE_RESULT)
	if #list == 0 then
		GameTooltip_AddHighlightLine(GameTooltip, L.TIMINGS_EMPTY)
	end
	for _, item in ipairs(list) do
		local color = CpuColor(item.entry.max)
		GameTooltip:AddDoubleLine(item.name, ("%.1f ms (%d)"):format(item.entry.max, item.entry.count), 1, 1, 1, color.r, color.g, color.b)
	end
end

local function StartMeasure()
	if ns.measureUntil then
		return
	end
	ns.PrintAlways(L.INFO_MEASURE_STARTED:format(MEASURE_SECONDS))
	ns.StartTimedMeasure(MEASURE_SECONDS, function()
		Info.lastMeasure = ns.TopTimings(MEASURE_LINES)
	end)
end

local function ShowCpuTooltip(owner)
	lastCpuTooltipUpdate = GetTime()
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip_SetTitle(GameTooltip, L.INFO_CPU_TITLE)
	if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then
		GameTooltip_AddNormalLine(GameTooltip, L.INFO_CPU_DISABLED)
		GameTooltip:Show()
		return
	end
	-- Sample LastTime locally so all three values start fresh after /reload.
	local list = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local name, title = C_AddOns.GetAddOnInfo(i)
			list[#list + 1] = {
				title = StripColors(title or name),
				ms = sessionMetrics[name] and sessionMetrics[name].average or 0,
				peak = sessionMetrics[name] and sessionMetrics[name].peak or 0,
				slow = sessionMetrics[name] and sessionMetrics[name].slow or 0,
			}
		end
	end
	table.sort(list, function(a, b)
		return a.peak > b.peak
	end)
	GameTooltip_AddNormalLine(GameTooltip, L.INFO_CPU_COLUMNS)
	if GetTime() < ignoreUntil then
		GameTooltip_AddInstructionLine(GameTooltip, L.INFO_CPU_WARMUP:format(math.ceil(ignoreUntil - GetTime())))
	end
	local total = 0
	for _, addon in ipairs(list) do
		total = total + addon.ms
		local color = CpuColor(addon.peak)
		GameTooltip:AddDoubleLine(addon.title, L.INFO_CPU_LINE:format(addon.ms, addon.peak, addon.slow),
			color.r, color.g, color.b, color.r, color.g, color.b)
	end
	local color = CpuColor(total)
	GameTooltip:AddDoubleLine(L.INFO_CPU_TOTAL, ("%.2f ms"):format(total),
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, color.r, color.g, color.b)
	AddMeasureLines()
	GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
	GameTooltip_AddInstructionLine(GameTooltip, L.INFO_MEASURE_HINT)
	GameTooltip:Show()
end

local function UpdatePerformance()
	local _, _, latencyHome, latencyWorld = GetNetStats()
	local color = ClassColor(playerClass)
	local label = NORMAL_FONT_COLOR
	perfFrame.Text:SetFormattedText("%s %s   %s %s",
		label:WrapTextInColorCode("FPS"), color:WrapTextInColorCode(("%d"):format(GetFramerate())),
		label:WrapTextInColorCode("MS"), color:WrapTextInColorCode(("%d"):format(max(latencyHome, latencyWorld))))
	perfFrame:SetSize(perfFrame.Text:GetStringWidth() + 6, perfFrame.Text:GetStringHeight() + 4)
	if GameTooltip:GetOwner() == perfFrame and GetTime() - lastCpuTooltipUpdate >= CPU_TOOLTIP_INTERVAL then
		ShowCpuTooltip(perfFrame)
	end
end

local function CreatePerfFrame()
	local frame = CreateFrame("Frame", nil, Minimap)
	frame:SetSize(120, 16)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	frame.Text = frame:CreateFontString(nil, "OVERLAY")
	frame.Text:SetPoint("CENTER")
	frame:SetScript("OnEnter", ShowCpuTooltip)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	-- Middle click or Shift + left click: 30 s measurement of ForeverPlus.
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "MiddleButton" or (button == "LeftButton" and IsShiftKeyDown()) then
			StartMeasure()
		end
	end)
	ns:RegisterDisplay(frame, "Performance", function(self)
		self:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 14)
	end, Minimap)
	return frame
end

function Info:UpdateFont()
	if perfFrame then
		perfFrame.Text:SetFont(ns.GetFontFace(), 12, "OUTLINE")
	end
end

function Info:UpdatePerformance()
	if self.db.performance then
		SetupProfilerSampler(true)
		perfFrame = perfFrame or CreatePerfFrame()
		self:UpdateFont()
		perfFrame:Show()
		perfTicker = perfTicker or C_Timer.NewTicker(PERF_INTERVAL, UpdatePerformance)
		UpdatePerformance()
	elseif perfFrame then
		SetupProfilerSampler(false)
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
	end)
	C_Timer.After(3, RequestPlayedSilently)
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
}

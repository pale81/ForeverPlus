-- Opt-in snapshots of quest information the client visibly exposes.
-- These are local observations, not replacements for the bundled baseline.
local _, ns = ...

local L = ns.L

local Capture = ns:NewModule("DataCapture", {
	title = L.DATA_TITLE,
	order = 11,
	defaults = { enabled = false },
})

local MAX_QUESTS, MAX_SNAPSHOTS = 200, 20

-- Where players send their export to (an issue form of the project).
ns.SUBMIT_URL = "https://github.com/pale81/ForeverPlus/issues/new?template=data.yml"

local function IsVisibleString(value)
	return type(value) == "string" and value ~= "" and not (issecretvalue and issecretvalue(value))
end

local function Timestamp()
	if type(GetServerTime) == "function" then return GetServerTime() end
	if type(time) == "function" then return time() end
	return 0
end

local function Snapshot(questID, method)
	questID = ns.Number(questID)
	if not questID or questID <= 0 then return end
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	local row = { observedAt = Timestamp(), method = method, source = "client-visible quest log" }
	if IsVisibleString(title) then row.title = title end
	local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
	if type(objectives) == "table" then
		row.objectives = {}
		for _, objective in ipairs(objectives) do
			if type(objective) == "table" then
				local item = {}
				if IsVisibleString(objective.text) then item.text = objective.text end
				if IsVisibleString(objective.type) then item.type = objective.type end
				if type(objective.finished) == "boolean" then item.finished = objective.finished end
				if next(item) then row.objectives[#row.objectives + 1] = item end
			end
		end
	end
	return row
end

local function Count(rows)
	local count = 0
	for _ in pairs(rows) do count = count + 1 end
	return count
end

local function SameObservation(left, right)
	if left.title ~= right.title then return false end
	local a, b = left.objectives or {}, right.objectives or {}
	if #a ~= #b then return false end
	for index, item in ipairs(a) do
		local other = b[index]
		if item.text ~= other.text or item.type ~= other.type or item.finished ~= other.finished then return false end
	end
	return true
end

function Capture.RecordQuest(questID, method)
	if not (Capture.db and Capture.db.enabled) then return false end
	local observation = Snapshot(questID, method or "manual snapshot")
	if not observation then return false end
	ForeverPlusDB.observations = ForeverPlusDB.observations or {}
	local rows = ForeverPlusDB.observations
	local key = tostring(questID)
	if not rows[key] and Count(rows) >= MAX_QUESTS then return false end
	local history = rows[key]
	if not history then history = {}; rows[key] = history end
	if history[#history] and SameObservation(history[#history], observation) then return true end
	history[#history + 1] = observation
	while #history > MAX_SNAPSHOTS do table.remove(history, 1) end
	return true
end

function Capture.SnapshotLog(method)
	if not (Capture.db and Capture.db.enabled) then return end
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		local questID = type(info) == "table" and info.questID
		if questID and questID > 0 then Capture.RecordQuest(questID, method) end
	end
end

function Capture.OnInitialize(self)
	ForeverPlusDB.observations = ForeverPlusDB.observations or {}
	if self.db.enabled then
		self:RegisterEvent("QUEST_ACCEPTED", self.OnEvent)
		self:RegisterEvent("QUEST_LOG_UPDATE", self.OnEvent)
	end
end

function Capture.OnEvent(_, event, questID)
	if event == "QUEST_ACCEPTED" then
		Capture.RecordQuest(questID, event)
	elseif event == "QUEST_LOG_UPDATE" and not Capture.logPending then
		-- The event comes in bursts: one snapshot after they settle.
		Capture.logPending = true
		C_Timer.After(2, function()
			Capture.logPending = false
			Capture.SnapshotLog(event)
		end)
	end
end

function Capture.SetEnabled(enabled)
	Capture.db.enabled = enabled and true or false
	if Capture.db.enabled then
		Capture:RegisterEvent("QUEST_ACCEPTED", Capture.OnEvent)
		Capture:RegisterEvent("QUEST_LOG_UPDATE", Capture.OnEvent)
		Capture.SnapshotLog("manual enable snapshot")
	else
		Capture:UnregisterEvent("QUEST_ACCEPTED")
		Capture:UnregisterEvent("QUEST_LOG_UPDATE")
	end
end

function Capture.Clear()
	ForeverPlusDB.observations = {}
end

local function ObservedQuests()
	local count = 0
	for _ in pairs(ForeverPlusDB.observations or {}) do
		count = count + 1
	end
	return count
end

-- Everything modules recorded, as one text.
function Capture.ExportText()
	local parts = {}
	for _, section in ipairs(ns.dataSections) do
		local text = section.text()
		if text then
			parts[#parts + 1] = text
		end
	end
	if #parts == 0 then
		return nil
	end
	-- The header says where the text goes and which client it comes from (the
	-- tool that merges submissions needs the language: names are taken from English ones only).
	local build = select(2, GetBuildInfo())
	local header = ("-- @fp-export 1 build=%s locale=%s\n%s"):format(tostring(build), GetLocale(), L.DATA_SUBMIT_LINE:format(ns.SUBMIT_URL))
	return header .. "\n\n" .. table.concat(parts, "\n\n")
end

function Capture.Export()
	local text = Capture.ExportText()
	if not text then
		ns.PrintAlways(L.DATA_EXPORT_NONE)
		return
	end
	ns.ShowEditWindow("DataExport", L.DATA_TITLE, text, CLOSE, function() end, L.DATA_EXPORT_HINT)
end

---------------------------------------------------------------------------
-- /fp diagnose: one text with everything needed to find a problem
---------------------------------------------------------------------------
-- Runs fn and returns what it printed with ns.PrintAlways (the status commands).
local function CapturePrints(fn)
	local original, lines = ns.PrintAlways, {}
	ns.PrintAlways = function(msg, ...)
		if select("#", ...) > 0 then
			msg = msg:format(...)
		end
		lines[#lines + 1] = (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local ok = pcall(fn)
	ns.PrintAlways = original
	return ok and table.concat(lines, "\n") or "(failed)"
end

local function OptionsChanged()
	local lines = {}
	for _, module in ipairs(ns.modules) do
		local keys = {}
		for key, value in pairs(module.db or {}) do
			local default = (module.defaults or {})[key]
			if type(value) ~= "table" and value ~= default then
				keys[#keys + 1] = ("%s=%s"):format(key, tostring(value))
			end
		end
		table.sort(keys)
		if #keys > 0 then
			lines[#lines + 1] = ("%s: %s"):format(module.name, table.concat(keys, ", "))
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or "(all defaults)"
end

local function ProfilerLine()
	local profiler = C_AddOnProfiler
	if not (profiler and profiler.IsEnabled and profiler.IsEnabled()) then
		return "profiler off"
	end
	local metrics = Enum.AddOnProfilerMetric
	local parts = {}
	for _, name in ipairs({ "PeakTime", "SessionAverageTime", "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms" }) do
		parts[#parts + 1] = ("%s=%.2f"):format(name, profiler.GetAddOnMetric(ns.name, metrics[name]) or 0)
	end
	return table.concat(parts, ", ")
end

function Capture.DiagnoseText()
	local out = {}
	local function Section(title, body)
		out[#out + 1] = ("== %s =="):format(title)
		out[#out + 1] = body ~= "" and body or "-"
		out[#out + 1] = ""
	end
	local version, build = GetBuildInfo()
	local _, className = UnitClass("player")
	Section("ForeverPlus", ("version %s, client %s (%s), locale %s, %s level %s, %s"):format(
		tostring(ns.version), tostring(version), tostring(build), GetLocale(), tostring(className), tostring(UnitLevel("player")), date("%Y-%m-%d %H:%M")))
	local errors = ns:GetModule("Errors")
	local count, report = 0, ""
	if errors and errors.Report then
		count, report = errors.Report(5)
	end
	Section(("Errors (%d)"):format(count), report)
	Section("Options that differ from the defaults", OptionsChanged())
	Section("CPU of the addon (ms)", ProfilerLine())
	local timings = {}
	for _, item in ipairs(ns.TopTimings(12)) do
		timings[#timings + 1] = ("%s: %.1f ms (%d / %d)"):format(item.name, item.entry.max, item.entry.slow, item.entry.count)
	end
	if ns.spikes and ns.spikes.count > 0 then
		timings[#timings + 1] = ("frames over 4 ms: %d, worst %.1f ms (measured %.1f ms, %s)"):format(
			ns.spikes.count, ns.spikes.worst, ns.spikes.measured, tostring(ns.spikes.name))
	end
	Section("Longest calls", table.concat(timings, "\n"))
	local status = {}
	for _, entry in ipairs({ { "Loot", "Loot" }, { "Talents", "Talents" }, { "RecipeRadar", "RecipeRadar" }, { "WorldMap", "WorldMap" } }) do
		local module = ns:GetModule(entry[2])
		if module and module.PrintStatus then
			status[#status + 1] = ("%s: %s"):format(entry[1], CapturePrints(function()
				module:PrintStatus()
			end))
		end
	end
	Section("Status", table.concat(status, "\n"))
	local addons = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local name = C_AddOns.GetAddOnInfo(i)
			if name and not name:find("^Blizzard_") then
				addons[#addons + 1] = name
			end
		end
	end
	Section("Other addons loaded", table.concat(addons, ", "))
	return table.concat(out, "\n")
end

function Capture.Diagnose()
	ns.ShowEditWindow("Diagnose", L.DIAG_TITLE, Capture.DiagnoseText(), CLOSE, function() end, L.DIAG_HINT)
end

-- /fp daten [an|aus|export|löschen], /fp datenbank
function Capture.Command(msg)
	if msg == "daten an" or msg == "data on" then
		Settings.SetValue("ForeverPlus_DataCapture_enabled", true)
		ns.PrintAlways(L.DATA_ON)
	elseif msg == "daten aus" or msg == "data off" then
		Settings.SetValue("ForeverPlus_DataCapture_enabled", false)
		ns.PrintAlways(L.DATA_OFF)
	elseif msg == "daten export" or msg == "data export" then
		Capture.Export()
	elseif msg == "daten löschen" or msg == "data clear" then
		Capture.Clear()
		for _, section in ipairs(ns.dataSections) do
			section.clear()
		end
		ns.PrintAlways(L.DATA_CLEARED)
	elseif msg == "datenbank" or msg == "database" then
		local meta = ns.BundledDatabase and ns.BundledDatabase.meta or {}
		local counts = meta.counts or {}
		ns.PrintAlways(L.DATA_DATABASE, counts.Quest or 0, meta.snapshotDate or "?", meta.clientBuild or "?")
	else
		ns.PrintAlways(L.DATA_STATUS, Capture.db.enabled and YES or NO, ObservedQuests())
	end
end

function Capture:OnOptionChanged(key, value)
	if key == "enabled" then
		Capture.SetEnabled(value)
	end
end

Capture.options = {
	{ key = "enabled", type = "toggle", name = L.DATA_CAPTURE, desc = L.DATA_CAPTURE_DESC },
}

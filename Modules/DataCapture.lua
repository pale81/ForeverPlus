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

-- /fp daten [an|aus|löschen], /fp datenbank
function Capture.Command(msg)
	if msg == "daten an" or msg == "data on" then
		Settings.SetValue("ForeverPlus_DataCapture_enabled", true)
		ns.PrintAlways(L.DATA_ON)
	elseif msg == "daten aus" or msg == "data off" then
		Settings.SetValue("ForeverPlus_DataCapture_enabled", false)
		ns.PrintAlways(L.DATA_OFF)
	elseif msg == "daten löschen" or msg == "data clear" then
		Capture.Clear()
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

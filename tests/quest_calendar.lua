local ns, uv, setuv = ...
local calendar, symbols = ns.MapQuestCalendar, ns.MapSymbols
local rules = ns.BundledDatabase.questHolidays
assert(rules[6961][1] == 12 and rules[8744][2] == 1225 and rules[8744][3] == 102, "Winter Veil assignments and gift window")
assert(rules[8193][1] == 13 and not rules[844], "fishing contest assignment and regular quest")

local function Time(month, day, hour, minute, year)
	return { year = year or 2026, month = month, monthDay = day, hour = hour, minute = minute or 0 }
end

local savedCalendar, savedClock = rawget(_G, "C_Calendar"), rawget(_G, "C_DateAndTime")
local now, month, offset = Time(12, 15, 5, 59), Time(11, 1, 0), 1
local december = { name = "Winterhauchfest", startTime = Time(12, 15, 6), endTime = Time(1, 2, 6, 0, 2027), texture = 235484 }
local faire = { startTime = Time(12, 7, 4), endTime = Time(12, 14, 4), texture = 235450 }
local preparation = { name = "", startTime = Time(11, 15, 6), endTime = Time(1, 15, 6, 0, 2027), texture = 235484 }
local holidays = { december, faire, preparation }
local scans = 0
C_DateAndTime = { GetCurrentCalendarTime = function() return now end }
C_Calendar = {
	GetMonthInfo = function(index) assert(index == 0) return month end,
	GetNumDayEvents = function(index, day)
		assert(index == offset and day == now.monthDay, "scan today's events relative to the calendar page")
		scans = scans + 1
		return #holidays + 1
	end,
	GetDayEvent = function(_, _, index)
		return { calendarType = index <= #holidays and "HOLIDAY" or "PLAYER" }
	end,
	GetHolidayInfo = function(_, _, index)
		return assert(holidays[index], "player events are skipped")
	end,
}

local function Allowed(id, map) return calendar.Allows(calendar.Read(), id, map) end
calendar.Invalidate()
assert(not Allowed(6961) and Allowed(844), "holiday hidden before start, regular quest visible")
assert(scans == 1, "one calendar scan per minute")
calendar.MarkDrawn()
now.minute, now.hour = 0, 6
assert(Allowed(6961) and not Allowed(8744) and calendar.HasChanged(), "the event begins before the gift unlocks")
calendar.MarkDrawn()
assert(not calendar.HasChanged(), "no redraw for an unchanged calendar")
now = Time(12, 25, 0)
assert(Allowed(8744) and calendar.HasChanged(), "gift window opens on the 25th")
now, offset = Time(1, 1, 0, 0, 2027), 2
assert(Allowed(8744), "gift window continues across New Year")
now = Time(1, 2, 6, 0, 2027)
assert(not Allowed(6961) and not Allowed(8744), "event end is exclusive")
now, offset = Time(12, 8, 12), 1
assert(Allowed(7881, 1412) and not Allowed(7881, 1429) and Allowed(7926, 1454), "current Darkmoon venue and city breadcrumb")
faire.texture = 235447
calendar.Invalidate()
assert(Allowed(7881, 1429) and not Allowed(7881, 1412), "same-minute calendar update changes the Darkmoon venue")
local secretCheck = ns.Secret
ns.Secret = function(v) return v == faire or secretCheck(v) end
calendar.Invalidate()
assert(not Allowed(7881, 1429) and Allowed(844), "unreadable holiday data leaves normal quests visible")
ns.Secret = secretCheck

local db = ns:GetModule("WorldMap").db
local collect = uv(symbols.Count, "Collect")
local starts
for _, source in ipairs(uv(collect, "sources")) do
	if uv(source, "QuestStartAvailable") then starts = source break end
end
local savedStarts, savedLog, savedReady, savedCVar = uv(starts, "questStarts"), C_QuestLog, ns.IsQuestReady, GetCVarBool
local savedStartOption, savedEndOption, savedDiscoveryOption = db.questStarts, db.questTurnIns, db.discoveries
setuv(starts, "questStarts", { [1436] = {
	{ x = 30, y = 40, data = { id = 6961 } }, { x = 30, y = 40, data = { id = 844 } },
} })
C_QuestLog = {
	IsQuestFlaggedCompleted = function() return false end,
	GetLogIndexForQuestID = function() return nil end,
	GetNumQuestLogEntries = function() return 1 end,
	GetInfo = function() return { questID = 6964, title = "Winter Veil" } end,
	GetQuestsOnMap = function() return { { questID = 6964, x = 0.4, y = 0.4 } } end,
}
ns.IsQuestReady = function() return true end
GetCVarBool = function() return false end
db.questStarts, db.questTurnIns, db.discoveries = true, true, false
local function CheckPins(map, expectedStarts, expectedTurnIns)
	local startCount, turnInCount = 0, 0
	for _, pin in ipairs(collect(map)) do
		if pin.kind == "questStart" then startCount = startCount + #pin.data end
		if pin.kind == "questTurnIn" then turnInCount = turnInCount + 1 end
	end
	assert(startCount == expectedStarts and turnInCount == expectedTurnIns, "seasonal quest pins on map " .. map)
end
CheckPins(1436, 1, 0)
CheckPins(1415, 1, 0)
now = Time(12, 15, 6)
CheckPins(1436, 2, 1)
CheckPins(1415, 2, 1)

now, faire.texture = Time(12, 8, 12), 235450
C_QuestLog.GetInfo = function() return { questID = 7905, title = "Darkmoon Faire" } end
C_QuestLog.GetQuestsOnMap = function() return { { questID = 7905, mapID = 1429, x = 0.4, y = 0.4 } } end
CheckPins(1415, 1, 1)
for _, pin in ipairs(collect(1415)) do
	if pin.kind == "questTurnIn" then
		assert(math.abs(pin.x - 0.53815) < 1e-9, "use the bundled Mulgore hand-in instead of the client POI at the inactive site")
	end
end
now = Time(12, 15, 6)
db.questStarts, db.questTurnIns = false, false
CheckPins(1436, 0, 0)

local checkTimer = uv(symbols.Refresh, "CheckCalendarWhileShown")
local stopTimer = uv(checkTimer, "StopCalendarTimer")
local savedTimer, savedShown, savedDraw = ns.NewTimer, WorldMapFrame.IsShown, uv(checkTimer, "Draw")
local timer, created, draws = nil, 0, 0
stopTimer()
WorldMapFrame.IsShown = function() return true end
ns.NewTimer = function(_, delay, callback)
	assert(delay == 30)
	created = created + 1
	timer = { fire = callback, Cancel = function(self) self.cancelled = true end }
	return timer
end
setuv(checkTimer, "Draw", function()
	draws = draws + 1
	calendar.MarkDrawn()
end)
db.questStarts = true
calendar.Read()
calendar.MarkDrawn()
checkTimer()
checkTimer()
assert(created == 1, "one timer for the open map")
timer.fire()
assert(draws == 0 and created == 2, "unchanged calendar does not redraw the open map")
now, offset = Time(1, 2, 6, 0, 2027), 2
timer.fire()
assert(draws == 1 and created == 3, "event end redraws the open map")
WorldMapFrame:GetScript("OnHide")(WorldMapFrame)
assert(timer.cancelled, "closing the map cancels the calendar timer")
ns.NewTimer, WorldMapFrame.IsShown = savedTimer, savedShown
setuv(checkTimer, "Draw", savedDraw)

setuv(starts, "questStarts", savedStarts)
C_QuestLog, ns.IsQuestReady, GetCVarBool = savedLog, savedReady, savedCVar
db.questStarts, db.questTurnIns, db.discoveries = savedStartOption, savedEndOption, savedDiscoveryOption
C_Calendar, C_DateAndTime = savedCalendar, savedClock
calendar.Read()
calendar.MarkDrawn()
print("seasonal quest calendar and world map markers OK")

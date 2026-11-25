local _, ns = ...

local Calendar = {}
ns.MapQuestCalendar = Calendar

local rules = ns.BundledDatabase and ns.BundledDatabase.questHolidays or {}
local DARKMOON, WINTER_VEIL, FISHING_CONTEST = 3, 12, 13
local ELWYNN, MULGORE = 1429, 1412
-- Holidays / HolidayDescriptions, Forever 1.60.1.71037. The three textures
-- are the calendar banners for start, ongoing days and end. Event numbers
-- match the imported quest table. The Darkmoon banners identify each venue.
local eventByTexture = {
	[235443] = 2, [235444] = 2, [235445] = 2, -- Children's Week
	[235446] = ELWYNN, [235447] = ELWYNN, [235448] = ELWYNN,
	[235449] = MULGORE, [235450] = MULGORE, [235451] = MULGORE,
	[235458] = FISHING_CONTEST,
	[235460] = 5, [235461] = 5, [235462] = 5, -- Hallow's End
	[235463] = 6, [235464] = 6, [235465] = 6, -- Harvest Festival
	[235466] = 7, [235467] = 7, [235468] = 7, -- Love is in the Air
	[235469] = 8, [235470] = 8, [235471] = 8, -- Lunar Festival
	[235472] = 9, [235473] = 9, [235474] = 9, -- Midsummer
	[235475] = 10, [235476] = 10, [235477] = 10, -- Noblegarden
	[235482] = WINTER_VEIL, [235484] = WINTER_VEIL, [235485] = WINTER_VEIL,
}

local empty = {}
local minute, active, drawn = nil, empty, empty

local function ReadableTable(value)
	return type(value) == "table" and not ns.Secret(value)
end

local function CalendarMinute(value)
	if not ReadableTable(value) then return end
	local year, month, day = ns.Number(value.year), ns.Number(value.month), ns.Number(value.monthDay)
	local hour, min = ns.Number(value.hour), ns.Number(value.minute)
	if year and month and day and hour and min then
		return (((year * 100 + month) * 100 + day) * 24 + hour) * 60 + min
	end
end

local function Scan(now, time)
	local month = C_Calendar.GetMonthInfo(0)
	if not ReadableTable(month) then return empty end
	local year, number = ns.Number(month.year), ns.Number(month.month)
	if not (year and number) then return empty end
	-- Day queries are relative to the month the player is browsing.
	local offset = (now.year - year) * 12 + now.month - number
	local day = now.monthDay
	local found = {}
	for i = 1, ns.Number(C_Calendar.GetNumDayEvents(offset, day), 0) do
		local event = C_Calendar.GetDayEvent(offset, day, i)
		if ReadableTable(event) and not ns.Secret(event.calendarType) and event.calendarType == "HOLIDAY" then
			local holiday = C_Calendar.GetHolidayInfo(offset, day, i)
			holiday = ReadableTable(holiday) and holiday or empty
			local id = eventByTexture[ns.Number(holiday.texture)] or eventByTexture[ns.Number(event.iconTexture)]
			local first = CalendarMinute(holiday.startTime) or CalendarMinute(event.startTime)
			local last = CalendarMinute(holiday.endTime) or CalendarMinute(event.endTime)
			-- The client data also has an unnamed, calendar-hidden Winter Veil phase with these banners.
			local name = holiday.name
			local named = type(name) == "string" and not ns.Secret(name) and name ~= ""
			if id and (id ~= WINTER_VEIL or named) and first and last and time >= first and time < last then
				found[id] = true
			end
		end
	end
	found[DARKMOON] = found[ELWYNN] or found[MULGORE]
	if found[WINTER_VEIL] then found.day = now.month * 100 + day end
	return found
end

function Calendar.Read()
	if not (C_DateAndTime and type(C_DateAndTime.GetCurrentCalendarTime) == "function"
		and C_Calendar and type(C_Calendar.GetMonthInfo) == "function" and type(C_Calendar.GetNumDayEvents) == "function"
		and type(C_Calendar.GetDayEvent) == "function" and type(C_Calendar.GetHolidayInfo) == "function") then
		active, minute = empty, nil
		return active
	end
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local time = CalendarMinute(now)
	if not time then
		active, minute = empty, nil
	elseif minute ~= time then
		active, minute = Scan(now, time), time
	end
	return active
end

function Calendar.Invalidate()
	minute = nil
end

function Calendar.MarkDrawn()
	drawn = active
end

function Calendar.HasChanged()
	local current = Calendar.Read()
	if drawn == current then return false end
	for event, value in pairs(drawn) do if current[event] ~= value then return true end end
	for event, value in pairs(current) do if drawn[event] ~= value then return true end end
	return false
end

function Calendar.Allows(state, questID, mapID)
	local rule = rules[questID]
	if not rule then return true end
	local event, first, last = unpack(rule)
	if event == DARKMOON and (mapID == ELWYNN or mapID == MULGORE) then
		event = mapID
	end
	if not state[event] then return false end
	if not first then return true end
	if not state.day then return false end
	if first <= last then return state.day >= first and state.day <= last end
	return state.day >= first or state.day <= last
end

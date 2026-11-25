-- Travel chronicle: a journal that writes itself (per character) from moments of the journey: a level reached,
-- the first arrival in a zone or instance, a boss defeated for the first time, epic loot, a death, the first
-- flight to a place, a text read for the first time. Read as an open book (/fp chronik), newest spread first.
local _, ns = ...
local L = ns.L

local Chronicle = ns:NewModule("Chronicle", {
	title = L.CHRONICLE_TITLE,
	order = 5.361,
	defaults = {
		enabled = true,
	},
	charDefaults = {
		entries = {}, -- { t = time(), k = kind, v = value, z = place, l = level }, oldest first
		seen = { zones = {}, bosses = {}, flights = {}, books = {} },
	},
})

Chronicle.MAX_ENTRIES = 2000 -- the oldest go first; a long life stays readable and the saved file small
-- Room on a page in lines: a day heading takes two, an entry one (longer ones wrap, the page then scrolls).
-- The first page carries the title.
local PAGE_LINES, FIRST_PAGE_LINES, HEADING_LINES = 12, 9, 2

local function Text(value)
	return type(value) == "string" and not ns.Secret(value) and value ~= "" and value or nil
end

-- The saved tables of this character; fields of older saves are added.
function Chronicle.Store()
	local cdb = Chronicle.cdb
	cdb.entries = type(cdb.entries) == "table" and cdb.entries or {}
	cdb.seen = type(cdb.seen) == "table" and cdb.seen or {}
	for _, key in ipairs({ "zones", "bosses", "flights", "books" }) do
		cdb.seen[key] = type(cdb.seen[key]) == "table" and cdb.seen[key] or {}
	end
	return cdb
end

-- Where the player is: "Subzone, Zone" or the zone alone.
function Chronicle.Place()
	local zone = Text(GetRealZoneText())
	local sub = Text(GetSubZoneText())
	if zone and sub and sub ~= zone then
		return sub .. ", " .. zone
	end
	return zone or sub
end

-- Adds an entry (kind, value) at the current time, place and level.
function Chronicle.Add(kind, value, place)
	local entries = Chronicle.Store().entries
	entries[#entries + 1] = {
		t = time(),
		k = kind,
		v = value,
		z = place or Chronicle.Place(),
		l = ns.Number(UnitLevel("player")),
	}
	while #entries > Chronicle.MAX_ENTRIES do
		table.remove(entries, 1)
	end
	return entries[#entries]
end

-- Adds an entry only the first time `key` is seen in the list `list` (zones, bosses, flights, books).
function Chronicle.AddFirst(list, key, kind, value, place)
	local seen = Chronicle.Store().seen[list]
	if key == nil or seen[key] then
		return nil
	end
	seen[key] = true
	return Chronicle.Add(kind, value, place)
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local LINES = {
	start = "CHRONICLE_START",
	level = "CHRONICLE_LEVEL",
	zone = "CHRONICLE_ZONE",
	instance = "CHRONICLE_INSTANCE",
	boss = "CHRONICLE_BOSS",
	loot = "CHRONICLE_LOOT",
	death = "CHRONICLE_DEATH",
	flight = "CHRONICLE_FLIGHT",
	book = "CHRONICLE_BOOK",
}

local function Escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- One entry as a line: "14:32 · Reached level 12 in Westfall."
function Chronicle.Line(entry)
	local key = LINES[entry.k]
	if not key then
		return nil
	end
	local place = entry.z or L.CHRONICLE_SOMEWHERE
	local text
	if entry.k == "start" then
		text = L[key]:format(entry.l or 1, place)
	elseif entry.k == "level" then
		text = L[key]:format(entry.v or entry.l or 1, place)
	elseif entry.k == "death" then
		text = L[key]:format(place)
	elseif entry.k == "boss" then
		text = L[key]:format(entry.v or "?", place)
	else
		text = L[key]:format(entry.v or "?")
	end
	return date(L.CHRONICLE_TIME, entry.t or 0) .. " · " .. text
end

-- The entries as pages of HTML (day headings, one paragraph per entry); a day going on on a new page gets its
-- heading again.
function Chronicle.Pages(entries)
	local pages, body, used, day = {}, {}, 0, nil
	local function Room()
		return #pages == 0 and FIRST_PAGE_LINES or PAGE_LINES
	end
	local function Finish()
		if #body > 0 then
			pages[#pages + 1] = "<html><body>" .. table.concat(body) .. "</body></html>"
		end
		body, used = {}, 0
	end
	local function Heading(t)
		body[#body + 1] = "<h3>" .. Escape(date(L.CHRONICLE_DATE, t)) .. "</h3>"
		used = used + HEADING_LINES
	end
	for _, entry in ipairs(entries) do
		local line = Chronicle.Line(entry)
		if line then
			local entryDay = date("%Y-%m-%d", entry.t or 0)
			local newDay = entryDay ~= day
			if used + (newDay and HEADING_LINES or 0) + 1 > Room() then
				Finish()
			end
			if newDay or used == 0 then
				Heading(entry.t or 0)
			end
			day = entryDay
			body[#body + 1] = "<p>" .. Escape(line) .. "</p>"
			used = used + 1
		end
	end
	Finish()
	return pages
end

-- The left page of the last spread (pages 1–2, 3–4, …).
function Chronicle.LastSpread(count)
	if count <= 1 then
		return 1
	end
	return count % 2 == 1 and count or count - 1
end

function Chronicle.Open()
	local pages = Chronicle.Pages(Chronicle.Store().entries)
	if #pages == 0 then
		ns.PrintAlways(L.CHRONICLE_EMPTY)
		return
	end
	local name = Text(UnitName("player")) or ""
	ns:GetModule("Readable").ShowBook({
		title = L.CHRONICLE_BOOK_TITLE:format(name),
		pages = pages,
		first = Chronicle.LastSpread(#pages),
	})
end

---------------------------------------------------------------------------
-- Moments of the journey
---------------------------------------------------------------------------
-- The zone (or instance) the player is in; a first arrival is written down. The very first call of a character
-- opens the chronicle instead (the zone counts as seen).
function Chronicle.Arrive()
	local zone = Text(GetRealZoneText())
	if not zone then
		return
	end
	local store = Chronicle.Store()
	if #store.entries == 0 then
		store.seen.zones[zone] = true
		Chronicle.Add("start", nil, zone)
		return
	end
	local inInstance = IsInInstance()
	Chronicle.AddFirst("zones", zone, inInstance and "instance" or "zone", zone, zone)
end

function Chronicle.LevelUp(_, _, level)
	level = ns.Number(level)
	if level then
		Chronicle.Add("level", level)
	end
end

-- A boss defeated for the first time by this character (ENCOUNTER_END with success, or BOSS_KILL).
function Chronicle.BossKilled(id, name)
	id, name = ns.Number(id), Text(name)
	if id and name then
		Chronicle.AddFirst("bosses", id, "boss", name)
	end
end

local lootPatterns = {} -- format of the game -> compiled pattern
-- The item link of the player's own loot in a loot message, or nil.
function Chronicle.OwnLootLink(text)
	if not Text(text) then
		return nil
	end
	for _, format in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
		if Text(format) then
			local compiled = lootPatterns[format] or ns.FormatToPattern(format, true)
			lootPatterns[format] = compiled
			local captures = { text:match(compiled.pattern) }
			for index, value in ipairs(captures) do
				if compiled.order[index] == 1 and value:find("|Hitem:", 1, true) then
					return value
				end
			end
		end
	end
	return nil
end

function Chronicle.Loot(_, _, text)
	local link = Chronicle.OwnLootLink(text)
	local quality = link and ns.Number(C_Item.GetItemQualityByID(link))
	if quality and quality >= Enum.ItemQuality.Epic then
		Chronicle.Add("loot", link)
	end
end

function Chronicle.Died()
	Chronicle.Add("death")
end

-- TakeTaxiNode: the first flight of this character to a flight point.
function Chronicle.TakeTaxi(index)
	local destination = Text(TaxiNodeName(index))
	if destination then
		Chronicle.AddFirst("flights", destination, "flight", destination)
	end
end

-- ITEM_TEXT_READY: the first page of a book, letter or plaque read for the first time.
function Chronicle.Read()
	if ns.Number(ItemTextGetPage()) ~= 1 then
		return
	end
	local title = Text(ItemTextGetItem())
	if title then
		Chronicle.AddFirst("books", title, "book", title)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local taxiHooked = false

function Chronicle:Apply()
	local on = self.db.enabled
	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, Chronicle.Arrive)
	self:ToggleEvent("ZONE_CHANGED_NEW_AREA", on, Chronicle.Arrive)
	self:ToggleEvent("PLAYER_LEVEL_UP", on, Chronicle.LevelUp)
	-- success: 1 when the boss died (0 after a wipe); BOSS_KILL comes as well, the boss counts once.
	self:ToggleEvent("ENCOUNTER_END", on, function(_, _, id, name, _, _, success)
		if not ns.Secret(success) and success == 1 then
			Chronicle.BossKilled(id, name)
		end
	end)
	self:ToggleEvent("BOSS_KILL", on, function(_, _, id, name)
		Chronicle.BossKilled(id, name)
	end)
	self:ToggleEvent("CHAT_MSG_LOOT", on, Chronicle.Loot)
	self:ToggleEvent("PLAYER_DEAD", on, Chronicle.Died)
	self:ToggleEvent("ITEM_TEXT_READY", on, Chronicle.Read)
	if on and not taxiHooked then
		taxiHooked = true
		hooksecurefunc("TakeTaxiNode", ns.Measured("Chronicle: flight", function(index)
			if Chronicle.db.enabled then
				Chronicle.TakeTaxi(index)
			end
		end))
	end
	if on then
		Chronicle.Arrive()
	end
end

function Chronicle:OnLogin()
	self:Apply()
end

function Chronicle:OnOptionChanged()
	self:Apply()
end

Chronicle.options = {
	{ key = "enabled", type = "toggle", name = L.CHRONICLE_ENABLE, desc = L.CHRONICLE_ENABLE_DESC, new = true },
	{ type = "button", name = L.CHRONICLE_OPEN, text = L.CHRONICLE_OPEN_BUTTON, func = function()
		Chronicle.Open()
	end },
}

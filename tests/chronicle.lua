-- Travel chronicle: what is written down (once or always), the lines, the pages and the open book.
local _, ns, uv = ...
local chronicle = ns:GetModule("Chronicle")
local readable = ns:GetModule("Readable")
local L = ns.L

local saved = { GetRealZoneText, GetSubZoneText, UnitLevel, IsInInstance, time, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE,
	LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, C_Item.GetItemQualityByID, TaxiNodeName, ItemTextGetPage,
	ItemTextGetItem, issecretvalue, UnitName, readable.ShowBook }
local savedCdb, savedEnabled = chronicle.cdb, chronicle.db.enabled
local zone, sub, level, instance, now = "Elwynn Forest", "", 5, false, 1700000000
local secret = {}
GetRealZoneText = function() return zone end
GetSubZoneText = function() return sub end
UnitLevel = function() return level end
IsInInstance = function() return instance end
time = function() return now end
issecretvalue = function(value) return value == secret end
UnitName = function() return "Helaku" end

chronicle.cdb = {} -- an older save without the fields
chronicle.db.enabled = true
local entries = chronicle.Store().entries
local function Last() return entries[#entries] end

-- Start, arrivals: the first call opens the chronicle, each zone and instance once.
chronicle.Arrive()
assert(#entries == 1 and Last().k == "start" and Last().z == "Elwynn Forest" and Last().l == 5, "the first call opens the chronicle")
chronicle.Arrive()
assert(#entries == 1, "the start zone counts as seen")
zone = "Westfall"
chronicle.Arrive()
assert(#entries == 2 and Last().k == "zone" and Last().v == "Westfall", "first arrival in a zone")
zone = "Elwynn Forest"
chronicle.Arrive()
zone = "Westfall"
chronicle.Arrive()
assert(#entries == 2, "known zones are not written again")
zone, instance = "The Deadmines", true
chronicle.Arrive()
assert(#entries == 3 and Last().k == "instance", "an instance is entered")
zone = secret
chronicle.Arrive()
zone = nil
chronicle.Arrive()
assert(#entries == 3, "no zone or a protected one: nothing")
zone, instance = "The Deadmines", true

-- Events through the dispatcher: level, boss once (both events, wipe ignored, protected values ignored).
local eventFrame = uv(ns.RegisterEvent, "eventFrame")
local function Fire(event, ...)
	eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
end
chronicle:Apply()
local count = #entries
Fire("PLAYER_LEVEL_UP", 18)
assert(#entries == count + 1 and Last().k == "level" and Last().v == 18, "level reached")
Fire("ENCOUNTER_END", 7, "Edwin VanCleef", 1, 5, 0)
assert(#entries == count + 1, "a wipe is no victory")
Fire("ENCOUNTER_END", 7, "Edwin VanCleef", 1, 5, secret)
Fire("ENCOUNTER_END", 7, secret, 1, 5, 1)
assert(#entries == count + 1, "protected values are skipped")
Fire("ENCOUNTER_END", 7, "Edwin VanCleef", 1, 5, 1)
Fire("BOSS_KILL", 7, "Edwin VanCleef")
assert(#entries == count + 2 and Last().k == "boss" and Last().z == "The Deadmines", "a boss counts once for both events")
Fire("BOSS_KILL", 7, "Edwin VanCleef")
assert(#entries == count + 2, "a boss defeated again is not written")

-- Epic loot of the player only.
LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
local epic = "|cffa335ee|Hitem:2000::::::::18:::::::|h[Archlich's Staff]|h|r"
local rare = "|cff0070dd|Hitem:1000::::::::18:::::::|h[Cruel Barb]|h|r"
C_Item.GetItemQualityByID = function(link) return link == epic and 4 or 3 end
count = #entries
assert(chronicle.OwnLootLink("You receive loot: " .. epic .. ".") == epic, "own loot link")
assert(chronicle.OwnLootLink("You receive loot: " .. epic .. "x2.") == epic, "own loot of several")
assert(chronicle.OwnLootLink("Mugrim receives loot: " .. epic .. ".") == nil, "loot of others")
assert(chronicle.OwnLootLink(secret) == nil, "protected message")
Fire("CHAT_MSG_LOOT", "You receive loot: " .. rare .. ".")
assert(#entries == count, "rare loot is not written")
Fire("CHAT_MSG_LOOT", "You receive item: " .. epic .. ".")
assert(#entries == count + 1 and Last().k == "loot" and Last().v == epic, "epic loot is written")

-- Death with the subzone, first flights, first texts read.
zone, sub, instance = "Westfall", "Moonbrook", false
Fire("PLAYER_DEAD")
assert(Last().k == "death" and Last().z == "Moonbrook, Westfall", "death with its place")
count = #entries
TaxiNodeName = function(index) return index == 1 and "Sentinel Hill, Westfall" or secret end
chronicle.TakeTaxi(1)
chronicle.TakeTaxi(1)
chronicle.TakeTaxi(2)
assert(#entries == count + 1 and Last().k == "flight", "first flight to a place, once")
local page = 1
ItemTextGetPage = function() return page end
ItemTextGetItem = function() return "The <Green> Hills" end
Fire("ITEM_TEXT_READY")
page = 2
Fire("ITEM_TEXT_READY")
page = 1
Fire("ITEM_TEXT_READY")
assert(#entries == count + 2 and Last().k == "book", "a text read for the first time, once")

-- Off: nothing is written.
chronicle.db.enabled = false
chronicle:Apply()
count = #entries
Fire("PLAYER_LEVEL_UP", 19)
Fire("PLAYER_DEAD")
assert(#entries == count, "off: nothing written")
chronicle.db.enabled = true
chronicle:Apply()

-- Lines: time, then the text; places and values in the line.
local line = chronicle.Line({ t = now, k = "level", v = 12, z = "Westfall" })
assert(line == date(L.CHRONICLE_TIME, now) .. " · " .. L.CHRONICLE_LEVEL:format(12, "Westfall"), "level line: " .. line)
assert(chronicle.Line({ t = now, k = "death" }):find(L.CHRONICLE_SOMEWHERE, 1, true), "a death without a place")
assert(chronicle.Line({ t = now, k = "unknown" }) == nil, "unknown kinds are skipped")

-- Pages: day headings, room per page (the first carries the title), a day going on gets its heading again.
local many = {}
for index = 1, 30 do
	many[index] = { t = now + index * 60, k = "level", v = index, z = "Westfall" }
end
many[#many + 1] = { t = now + 2 * 86400, k = "book", v = "A <b> & c" }
local pages = chronicle.Pages(many)
local function Count(text, pattern)
	return select(2, text:gsub(pattern, ""))
end
assert(Count(pages[1], "<p>") == 7 and Count(pages[1], "<h3>") == 1, "first page: heading and 7 entries (" .. pages[1] .. ")")
assert(Count(pages[2], "<p>") == 10 and Count(pages[2], "<h3>") == 1, "later page: the day's heading again and 10 entries")
local total = 0
for _, text in ipairs(pages) do
	assert(text:find("^<html><body>") and text:find("</body></html>$"), "each page is HTML")
	total = total + Count(text, "<p>")
end
assert(total == 31, "every entry is on a page")
assert(pages[#pages]:find("A &lt;b&gt; &amp; c", 1, true), "text is escaped")
assert(#chronicle.Pages({}) == 0, "no entries: no pages")
assert(chronicle.LastSpread(1) == 1 and chronicle.LastSpread(2) == 1 and chronicle.LastSpread(3) == 3
	and chronicle.LastSpread(4) == 3, "the last spread opens")

-- The oldest entries go when the chronicle is full.
local savedMax = chronicle.MAX_ENTRIES
chronicle.MAX_ENTRIES = 3
for index = 1, 5 do
	chronicle.Add("level", 30 + index)
end
assert(#entries == 3 and entries[1].v == 33 and Last().v == 35, "only the newest entries stay")
chronicle.MAX_ENTRIES = savedMax

-- Open: the book with the title, the last spread; /fp chronik routes here.
local shown
readable.ShowBook = function(book) shown = book end
SlashCmdList.FOREVERPLUS("chronik")
assert(shown and shown.title == L.CHRONICLE_BOOK_TITLE:format("Helaku") and #shown.pages >= 1
	and shown.first == chronicle.LastSpread(#shown.pages), "the chronicle opens as a book")
shown = nil
SlashCmdList.FOREVERPLUS("chronicle")
assert(shown, "/fp chronicle")
readable.ShowBook = saved[16]

-- Own pages in the reader: turning by spreads, closing.
readable.ShowBook({ title = "T", pages = { "<html><body><p>1</p></body></html>", "2", "3" }, first = 1 })
local view = _G.ForeverPlusReadable
assert(view and view:IsShown(), "the book is shown")
assert(readable.CanTurn(true) and not readable.CanTurn(false), "first spread: only forward")
readable.Turn(true)
assert(not readable.CanTurn(true) and readable.CanTurn(false), "last spread: only back")
readable.Turn(false)
assert(readable.CanTurn(true), "back on the first spread")
readable.Close()
assert(not view:IsShown() and not readable.CanTurn(true), "closed: no own pages left")
readable.ShowBook({ title = "T", pages = { "1", "2", "3" }, first = 3 })
view:Hide() -- Esc (special frame); the harness does not run OnHide itself
view:GetScript("OnHide")(view)
assert(not readable.CanTurn(false), "hidden by Esc: the own pages are gone")

chronicle.cdb, chronicle.db.enabled = savedCdb, savedEnabled
GetRealZoneText, GetSubZoneText, UnitLevel, IsInInstance, time, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE,
	LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, C_Item.GetItemQualityByID, TaxiNodeName, ItemTextGetPage,
	ItemTextGetItem, issecretvalue, UnitName = unpack(saved, 1, 15)
chronicle:Apply()
print("travel chronicle OK")

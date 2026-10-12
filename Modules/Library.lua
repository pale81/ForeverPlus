-- Library books (Friend of the Library): the 40 books are items looted from
-- objects in the world and handed in at the librarian. Books not yet collected
-- show on the world map; the client has no list of collected books, so a book
-- counts once it has been in the bags, when its hand-in quest is done (known
-- for 16 of the books) or when marked by hand (right click on its symbol). Where a book was looted is remembered and can be exported
-- (/fp bücher export) to complete the positions in a later update.
local _, ns = ...
local L = ns.L

local Library = ns:NewModule("Library", {
	title = L.LIBRARY_TITLE,
	order = 11.6,
	defaults = {
		symbols = true,
		record = true,
	},
	charDefaults = {
		owned = {},
	},
})

local books = ns.LibraryBooks or {}
local ready = false -- after the first scan: new books are finds of this session

local function BookName(book)
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(book[1])
	return type(name) == "string" and name or book[5]
end

---------------------------------------------------------------------------
-- Collected books
---------------------------------------------------------------------------
local function PlayerPosition()
	local mapID = ns.Number(C_Map.GetBestMapForUnit("player"))
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return
	end
	local x, y = position:GetXY()
	x, y = ns.Number(x), ns.Number(y)
	if x and y and (x ~= 0 or y ~= 0) then
		return mapID, x * 100, y * 100
	end
end

local function IsOwned(book)
	return Library.cdb.owned[book[1]] or book[6] and C_QuestLog.IsQuestFlaggedCompleted(book[6]) or false
end

local function Scan()
	local owned = Library.cdb.owned
	local changed
	for _, book in ipairs(books) do
		local id = book[1]
		if IsOwned(book) then
			changed = changed or not owned[id]
			owned[id] = true
		elseif C_Item.GetItemCount(id, true) > 0 and not owned[id] then
			owned[id], changed = true, true
			-- Looted this session and still in the bags: the player stands at the book.
			if ready and Library.db.record and C_Item.GetItemCount(id) > 0 and not ns.db.libraryFinds[id] then
				local mapID, x, y = PlayerPosition()
				if mapID then
					ns.db.libraryFinds[id] = { mapID, x, y }
				end
			end
		end
	end
	ready = true
	if changed then
		ns.MapSymbols.Refresh()
	end
end

Library.Scan = Scan

local function Counts()
	local have = 0
	for _, book in ipairs(books) do
		if IsOwned(book) then
			have = have + 1
		end
	end
	return have, #books
end

---------------------------------------------------------------------------
-- Map symbols
---------------------------------------------------------------------------
local function Tooltip(tooltip, symbol)
	local book = symbol.data
	tooltip:AddLine(BookName(book), 1, 1, 1)
	tooltip:AddLine(symbol.exact and L.LIBRARY_FOUND or L.LIBRARY_APPROX, 0.8, 0.8, 0.8)
	tooltip:AddLine(L.LIBRARY_MARK, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
end

local function Click(symbol, button)
	if button == "RightButton" then
		Library.cdb.owned[symbol.data[1]] = true
		ns.MapSymbols.Refresh()
	end
end

-- Positions of a book: the own find when there is one, else the guide's.
local function Positions(book)
	local find = ns.db.libraryFinds[book[1]]
	if find then
		return { { find[1], find[2], find[3], true } }
	end
	local list = {}
	for _, entry in ipairs(books) do
		if entry[1] == book[1] and entry[2] then
			list[#list + 1] = { entry[2], entry[3], entry[4], false }
		end
	end
	return list
end

ns.MapSymbols.AddSource(function(mapID, add)
	if not Library.db.symbols then
		return
	end
	ns.MapSymbols.ForZones(mapID, function(zoneMapID, toMap)
		local seen = {}
		for _, book in ipairs(books) do
			local id = book[1]
			if not IsOwned(book) and not seen[id] then
				seen[id] = true
				for _, position in ipairs(Positions(book)) do
					if position[1] == zoneMapID then
						local x, y = toMap(position[2], position[3])
						local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
						add(x, y, { kind = "book", texture = icon or 134939, round = true, size = 18,
							data = book, exact = position[4], tooltip = Tooltip, click = Click })
					end
				end
			end
		end
	end)
end)

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
function Library.ExportText(finds)
	local lines = { ns.ExportTag("books"), L.LIBRARY_EXPORT_HEADER }
	local ids = {}
	for id in pairs(finds) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local find = finds[id]
		lines[#lines + 1] = ("{ %d, %d, %.1f, %.1f },"):format(id, find[1], find[2], find[3])
	end
	return table.concat(lines, "\n")
end

ns.AddDataSection(function()
	return next(ns.db.libraryFinds) ~= nil and Library.ExportText(ns.db.libraryFinds) or nil
end, function()
	ns.db.libraryFinds = {}
end)

ns.AddMapFilterEntry(function(root)
	ns.CreateOptionCheckbox(root, L.LIBRARY_SYMBOLS, "Library", "symbols", L.LIBRARY_SYMBOLS_DESC)
end)

-- /fp bücher [export|zurück]
function Library.Command(msg)
	if msg:find("export", 1, true) then
		ns:GetModule("DataCapture").Export()
	elseif msg:find("zur", 1, true) or msg:find("reset", 1, true) then
		wipe(Library.cdb.owned)
		ns.PrintAlways(L.LIBRARY_RESET)
		ns.MapSymbols.Refresh()
	else
		local have, total = Counts()
		ns.PrintAlways(L.LIBRARY_STATUS, have, total)
		for _, book in ipairs(books) do
			if not IsOwned(book) then
				ns.PrintAlways("  " .. BookName(book))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Library:Apply()
	self:ToggleEvent("BAG_UPDATE_DELAYED", true, Scan)
	self:ToggleEvent("QUEST_TURNED_IN", true, Scan)
	if self.db.symbols then
		ns.MapSymbols.Setup()
	end
	ns.MapSymbols.Refresh()
end

function Library:OnInitialize()
	ns.db.libraryFinds = ns.db.libraryFinds or {}
end

function Library:OnLogin()
	ns.AddTrackingEntry(function(root)
		root:CreateCheckbox(L.LIBRARY_TRACKING, function()
			return Library.db.symbols
		end, function()
			Settings.SetValue("ForeverPlus_Library_symbols", not Library.db.symbols)
		end)
	end)
	self:Apply()
	-- Item data may not be loaded yet at login.
	C_Timer.After(5, Scan)
end

function Library:OnOptionChanged()
	self:Apply()
end

Library.options = {
	{ key = "symbols", type = "toggle", name = L.LIBRARY_SYMBOLS, desc = L.LIBRARY_SYMBOLS_DESC },
	{ key = "record", type = "toggle", name = L.LIBRARY_RECORD, desc = L.LIBRARY_RECORD_DESC },
}

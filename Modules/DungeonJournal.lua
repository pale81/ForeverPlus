-- The journal owns its frames and draws client textures without Blizzard's pin system.
local _, ns = ...
local L = ns.L
local Journal = ns:NewModule("DungeonJournal", {
	title = L.JOURNAL_TITLE, order = 12, defaults = { enabled = true },
})

local data = ns.DungeonJournalData.instances
local german = GetLocale() == "deDE"
local GOLD = { 0.96, 0.76, 0.43 }
local MUTED = { 0.68, 0.73, 0.81 }
local WHITE = { 0.96, 0.94, 0.90 }
local DARK = { 0.037, 0.049, 0.071, 0.97 }
local INK = { 0.077, 0.098, 0.135, 1 }
local EDGE = { 0.37, 0.29, 0.18, 0.85 }
local WIDTH, HEIGHT = 944, 566
local ROW = 40
local ICON = { boss = [[Interface\TargetingFrame\UI-RaidTargetingIcon_8]], quest = 132049, done = 136814 }
local STATES = {
	ready = { 1, 0.82, 0.35 }, active = { 0.50, 0.80, 1 }, done = { 0.51, 0.82, 0.57 }, missing = MUTED,
}
local STATUS = {
	ready = L.JOURNAL_READY, active = L.JOURNAL_ACTIVE, done = L.JOURNAL_DONE, missing = L.JOURNAL_MISSING,
}
local frame, catalog, selection, mapPage, selectedTab
local kind, characterOnly = "dungeon", true
local requested = {}
local tabs = { { "map", L.JOURNAL_MAP }, { "bosses", L.JOURNAL_BOSSES }, { "quests", L.JOURNAL_QUESTS } }

local function Text(value)
	return not ns.Secret(value) and type(value) == "string" and value ~= "" and value or nil
end

local function Name(id, entry)
	return Text(GetRealZoneText(id)) or german and entry.name[2] or entry.name[1]
end

local function Less(a, b)
	if strcmputf8i then
		return strcmputf8i(a, b) < 0
	end
	return a:lower() < b:lower()
end

local function Catalog()
	if catalog then return catalog end
	catalog = {}
	for id, entry in pairs(data) do
		local title = Name(id, entry)
		catalog[#catalog + 1] = { id = id, title = title, key = ns.LowerCommand(title), data = entry }
	end
	table.sort(catalog, function(a, b)
		if a.data.min ~= b.data.min then return a.data.min < b.data.min end
		return Less(a.title, b.title)
	end)
	return catalog
end

local function FormatLevel(low, high)
	if not low or low == 0 then return "" end
	return L.JOURNAL_LEVEL:format(high > low and (low .. "–" .. high) or low)
end

local function CurrentInstance()
	local _, instanceType, _, _, _, _, _, id = GetInstanceInfo()
	if instanceType == "party" or instanceType == "raid" then
		return ns.Number(id)
	end
end

local function QuestState(id)
	if C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
	local index = ns.Number(C_QuestLog.GetLogIndexForQuestID(id))
	if index and index > 0 then
		return ns.IsQuestReady(id, index) and "ready" or "active"
	end
	return "missing"
end

local function QuestTitle(id, bundled, fallback)
	local title = Text(C_QuestLog.GetTitleForQuestID(id))
	if title then return title end
	if not requested[id] and C_QuestLog.RequestLoadQuestByID then
		requested[id] = true
		C_QuestLog.RequestLoadQuestByID(id)
	end
	return bundled and Text(bundled.Quest.Get(id, "name")) or fallback or L.JOURNAL_QUEST_ID:format(id)
end

-- Add live quests only when the quest-log header names this instance. An
-- unrelated Dungeon-tagged quest could belong to any other instance.
local function ActiveQuests(id, into)
	local names = { [data[id].name[1]] = true }
	names[Name(id, data[id])] = true
	if data[id].name[2] then names[data[id].name[2]] = true end
	local header
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not ns.Secret(info.isHeader) then
			if info.isHeader then
				header = Text(info.title)
			elseif names[header] then
				local questID = ns.Number(info.questID)
				if questID and questID > 0 and not into[questID] then
					into[questID] = { questID }
				end
			end
		end
	end
end

local function QuestRows(id, forCharacter)
	local faction = UnitFactionGroup("player")
	local _, _, class = UnitClass("player")
	local bundled = ns.QuestieDB.Bundled()
	local list, unique = {}, {}
	for _, quest in ipairs(data[id].quests or {}) do
		unique[quest[1]] = quest
	end
	ActiveQuests(id, unique)
	for questID, quest in pairs(unique) do
		local side, matchesClass = quest[2], not quest[4]
		for _, classID in ipairs(quest[4] or {}) do
			matchesClass = matchesClass or class == classID
		end
		local matchesSide = not side or side == "-" or side == "A" and faction == "Alliance"
			or side == "H" and faction == "Horde"
		if not forCharacter or matchesSide and matchesClass then
			list[#list + 1] = {
				id = questID, name = QuestTitle(questID, bundled, quest[5]), state = QuestState(questID), level = quest[3], side = side,
			}
		end
	end
	local order = { ready = 1, active = 2, missing = 3, done = 4 }
	table.sort(list, function(a, b)
		if a.state ~= b.state then return order[a.state] < order[b.state] end
		if a.name ~= b.name then return Less(a.name, b.name) end
		return a.id < b.id
	end)
	return list
end

local function Fill(parent, layer, color, sublayer)
	local region = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublayer or 0)
	region:SetColorTexture(unpack(color))
	region:SetAllPoints()
	return region
end

local function Line(parent, left, right, y, color)
	local line = parent:CreateTexture(nil, "BORDER")
	line:SetColorTexture(unpack(color))
	line:SetPoint("TOPLEFT", left, y)
	line:SetPoint("TOPRIGHT", right, y)
	line:SetHeight(1)
end

local function Label(frameOwner, size, color, font)
	local label = frameOwner:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	label:SetFont(label:GetFont(), size)
	label:SetTextColor(unpack(color))
	label:SetJustifyH("LEFT")
	return label
end

local function StyleButton(button, selected)
	if selected then
		button.bg:SetColorTexture(0.25, 0.17, 0.09, 1)
		button.text:SetTextColor(unpack(GOLD))
	elseif button.hover then
		button.bg:SetColorTexture(0.17, 0.20, 0.25, 1)
		button.text:SetTextColor(unpack(WHITE))
	else
		button.bg:SetColorTexture(unpack(INK))
		button.text:SetTextColor(unpack(WHITE))
	end
	button.selected = selected
end

local function Button(parent, width, height, title, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button.bg = Fill(button, "BACKGROUND", INK)
	button.text = Label(button, 12, WHITE)
	button.text:SetPoint("CENTER")
	button.text:SetText(title)
	button:SetScript("OnEnter", ns.Measured("DungeonJournal: hover", function(self)
		self.hover = true
		StyleButton(self, self.selected)
	end))
	button:SetScript("OnLeave", ns.Measured("DungeonJournal: leave", function(self)
		self.hover = nil
		StyleButton(self, self.selected)
		GameTooltip:Hide()
	end))
	button:SetScript("OnClick", ns.Measured("DungeonJournal: click", onClick))
	return button
end

local function SetThumb(scroll, offset)
	local y = scroll.range > 0 and offset / scroll.range * (scroll:GetHeight() - scroll.thumb:GetHeight()) or 0
	scroll.thumb:ClearAllPoints()
	scroll.thumb:SetPoint("TOP", scroll.track, "TOP", 0, -y)
end

-- Scroll by rows so a long dungeon/quest list keeps the same readable spacing.
local function List(parent, width, height, rowHeight)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetSize(width, height)
	scroll:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, height)
	scroll:SetScrollChild(child)
	scroll.content, scroll.rows, scroll.step = child, {}, rowHeight
	local track = CreateFrame("Frame", nil, parent)
	track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, 0)
	track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 0)
	track:SetWidth(3)
	Fill(track, "BACKGROUND", INK)
	scroll.track = track
	scroll.thumb = track:CreateTexture(nil, "ARTWORK")
	scroll.thumb:SetColorTexture(unpack(EDGE))
	scroll.thumb:SetWidth(3)
	scroll:SetScript("OnMouseWheel", ns.Measured("DungeonJournal: scroll", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * self.step * 2, self.range or 0)))
	end))
	scroll:SetScript("OnVerticalScroll", ns.Measured("DungeonJournal: scroll thumb", SetThumb))
	scroll.range = 0
	return scroll
end

local function ShowRows(scroll, count, reset)
	for index = count + 1, #scroll.rows do scroll.rows[index]:Hide() end
	local height = scroll:GetHeight()
	local contentHeight = math.max(height, count * scroll.step)
	local scrollTo = reset and 0 or ns.Number(scroll:GetVerticalScroll(), 0)
	scroll.range = contentHeight - height
	scroll.thumb:SetHeight(math.max(16, height * height / contentHeight))
	scroll.track:SetShown(scroll.range > 0)
	scroll.content:SetHeight(contentHeight)
	scroll:UpdateScrollChildRect()
	local offset = math.min(scrollTo, scroll.range)
	scroll:SetVerticalScroll(offset)
	SetThumb(scroll, offset)
end

local function Row(scroll, index, width, onClick)
	local row = scroll.rows[index]
	if not row then
		row = Button(scroll.content, width, scroll.step - 3, "", onClick)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * scroll.step)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetSize(23, 23)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 9, 6)
		row.text:SetPoint("RIGHT", -8, 0)
		row.text:SetWordWrap(false)
		row.sub = Label(row, 10, MUTED)
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		row.sub:SetPoint("RIGHT", -8, 0)
		row.sub:SetWordWrap(false)
		scroll.rows[index] = row
	end
	row:Show()
	return row
end

local function Tooltip(button, title, note)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 1, 1, true)
	if note then GameTooltip:AddLine(note, unpack(MUTED)) end
end

local function QuestTooltip(row)
	local quest = row.quest
	if not quest then return end
	Tooltip(row, quest.name, STATUS[quest.state])
	for _, objective in ipairs((quest.state == "active" or quest.state == "ready")
		and C_QuestLog.GetQuestObjectives(quest.id) or {}) do
		local text = Text(objective.text)
		if text then GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true) end
	end
	local lib = ns.QuestieDB.Bundled()
	local starts = lib and lib.Quest.Get(quest.id, "startPoints")
	local point = starts and starts[1]
	if point and point[1] then
		local map = C_Map.GetMapInfo(point[1])
		if map and Text(map.name) then
			GameTooltip:AddLine(L.JOURNAL_PICKUP:format(map.name, point[2], point[3]), unpack(GOLD))
		end
	end
	GameTooltip:AddLine(L.JOURNAL_QUEST_LINK, 0.68, 0.73, 0.81, true)
	GameTooltip:Show()
end

local function OpenQuest(row)
	local quest = row.quest
	if not quest then return end
	GameTooltip:Hide()
	if (quest.state == "active" or quest.state == "ready") and QuestMapFrame_OpenToQuestDetails and not InCombatLockdown() then
		frame:Hide()
		QuestMapFrame_OpenToQuestDetails(quest.id)
	else
		ns.ShowEditWindow("JournalQuest", quest.name, ns.WowheadURL("quest", quest.id), CLOSE, function() end)
	end
end

local function Entrance(id)
	if frame.entrance and frame.entrance.id == id then
		return frame.entrance.mapID, frame.entrance.x, frame.entrance.y
	end
	return ns.MapSymbols.GetEntrance(id)
end

local function EntranceArt(id)
	local mapID, x, y = Entrance(id)
	local layers = mapID and C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	local textures = layer and C_Map.GetMapArtLayerTextures(mapID, 1)
	if not textures or #textures == 0 or not x or not y or layer.layerWidth <= 0 or layer.layerHeight <= 0
		or layer.tileWidth <= 0 or layer.tileHeight <= 0 then return end
	return layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight, textures, x, y
end

local function DrawTile(image, index, file, x, y, tileW, tileH, width, height, scale)
	local tile = image.tiles[index]
	if not tile then
		tile = image.canvas:CreateTexture(nil, "ARTWORK")
		image.tiles[index] = tile
	end
	local left, top = math.max(0, x), math.max(0, y)
	local right, bottom = math.min(x + tileW, width), math.min(y + tileH, height)
	tile:SetTexture(file, "CLAMP", "CLAMP")
	tile:SetTexCoord((left - x) / tileW, (right - x) / tileW, (top - y) / tileH, (bottom - y) / tileH)
	tile:SetSize((right - left) * scale, (bottom - top) * scale)
	tile:ClearAllPoints()
	tile:SetPoint("TOPLEFT", image.canvas, "TOPLEFT", left * scale, -top * scale)
	tile:Show()
end

local function DrawMap(id, entry)
	local image = frame.mapImage
	local width, height, tileW, tileH, tiles, x, y
	local pageCount, cropped = 0, false
	local label
	if mapPage ~= 0 and entry.floors then
		pageCount = #entry.floors
		tiles = entry.floors[mapPage]
		width, height, tileW, tileH = 1002, 668, 256, 256
		label = L.JOURNAL_FLOOR:format(mapPage, pageCount)
	elseif mapPage ~= 0 and entry.minimap then
		pageCount = #entry.minimap
		local region = entry.minimap[mapPage]
		tileW, tileH = 256, 256
		width, height, tiles = region[1], region[2], region[3]
		cropped = true
		label = pageCount == 1 and L.JOURNAL_INTERIOR or L.JOURNAL_SECTION:format(mapPage, pageCount)
	else
		width, height, tileW, tileH, tiles, x, y = EntranceArt(id)
		label = L.JOURNAL_ENTRANCE
	end

	frame.mapLabel:SetText(label)
	frame.mapCaption:SetText(mapPage == 0 and (tiles and L.JOURNAL_ENTRANCE_NOTE or "")
		or entry.floors and L.JOURNAL_LEGACY_NOTE or L.JOURNAL_MINIMAP_NOTE)
	frame.prev:SetShown(pageCount > 1)
	frame.next:SetShown(pageCount > 1)
	frame.entranceButton:SetShown(Entrance(id) ~= nil and (entry.floors ~= nil or entry.minimap ~= nil))
	frame.entranceButton.text:SetText(mapPage == 0 and L.JOURNAL_INTERIOR or L.JOURNAL_ENTRANCE)
	image.empty:SetShown(tiles == nil)
	image.pin:Hide()
	local used = 0
	if tiles and width > 0 and height > 0 and tileW > 0 and tileH > 0 then
		local scale = math.min(image:GetWidth() / width, image:GetHeight() / height)
		image.canvas:SetSize(width * scale, height * scale)
		local columns = math.ceil(width / tileW)
		local count = cropped and #tiles or math.min(#tiles, columns * math.ceil(height / tileH))
		for index = 1, count do
			local file, left, top
			if cropped then
				file, left, top = unpack(tiles[index])
			else
				file = tiles[index]
				left, top = (index - 1) % columns * tileW, math.floor((index - 1) / columns) * tileH
			end
			if file > 0 then
				used = used + 1
				DrawTile(image, used, file, left, top, tileW, tileH, width, height, scale)
			end
		end
		if x and y then
			image.pin:ClearAllPoints()
			image.pin:SetPoint("CENTER", image.canvas, "TOPLEFT", x * width * scale, -y * height * scale)
			image.pin:Show()
		end
	end
	for i = used + 1, #image.tiles do image.tiles[i]:Hide() end
end

local Render, RenderCatalog, Select

Render = function(reset)
	local entry = data[selection]
	local map = selectedTab == "map"
	local quests = selectedTab == "quests"
	for key, button in pairs(frame.tabs) do StyleButton(button, key == selectedTab) end
	frame.map:SetShown(map)
	frame.entries:SetShown(not map)
	frame.listTitle:SetShown(not map)
	frame.listNote:SetShown(not map)
	frame.character:SetShown(quests)
	frame.empty:Hide()
	frame.art:SetTexture(entry.art ~= 0 and entry.art or nil)
	frame.name:SetText(Name(selection, entry))
	frame.subtitle:SetText((entry.kind == "raid" and L.JOURNAL_RAID or L.JOURNAL_DUNGEON)
		.. "  ·  " .. FormatLevel(entry.min, entry.max))
	frame.counts:SetText(L.JOURNAL_BOSS_COUNT:format(#entry.bosses))
	if map then
		DrawMap(selection, entry)
		return
	end

	local rows = quests and QuestRows(selection, characterOnly) or entry.bosses
	frame.listTitle:SetText(quests and L.JOURNAL_QUEST_COUNT:format(#rows) or L.JOURNAL_BOSS_COUNT:format(#rows))
	frame.listNote:SetText(quests and L.JOURNAL_QUEST_NOTE or L.JOURNAL_BOSS_NOTE)
	for index, record in ipairs(rows) do
		local row = Row(frame.entries, index, 676, OpenQuest)
		row.quest = quests and record or nil
		if not row.tooltipHook then
			row.tooltipHook = true
			row:HookScript("OnEnter", ns.Measured("DungeonJournal: quest tooltip", QuestTooltip))
		end
		StyleButton(row, false)
		if quests then
			row.icon:SetTexture(record.state == "done" and ICON.done or ICON.quest)
			row.icon:SetDesaturated(record.state == "done")
			row.text:SetText(record.name)
			local level = record.level and record.level > 0 and L.JOURNAL_MIN_LEVEL:format(record.level) or ""
			local side = record.side == "A" and L.JOURNAL_ALLIANCE or record.side == "H" and L.JOURNAL_HORDE
			row.sub:SetText(STATUS[record.state] .. (level ~= "" and "  ·  " .. level or "") .. (side and "  ·  " .. side or ""))
			row.sub:SetTextColor(unpack(STATES[record.state]))
		else
			row.icon:SetTexture(ICON.boss)
			row.icon:SetDesaturated(false)
			row.text:SetText(german and record[3] or record[2])
			row.sub:SetText(L.JOURNAL_ENCOUNTER:format(index))
			row.sub:SetTextColor(unpack(MUTED))
		end
	end
	ShowRows(frame.entries, #rows, reset)
	if #rows == 0 then
		frame.empty:SetText(quests and (characterOnly and L.JOURNAL_NO_FILTERED_QUESTS or L.JOURNAL_NO_QUESTS)
			or L.JOURNAL_NO_BOSSES)
		frame.empty:Show()
	end
end

RenderCatalog = function(reset, reveal)
	local query = ns.LowerCommand(strtrim(frame.search:GetText() or ""))
	local count, selectedIndex = 0, nil
	for _, entry in ipairs(Catalog()) do
		if entry.data.kind == kind and (query == "" or entry.key:find(query, 1, true)
			or entry.data.name[1]:lower():find(query, 1, true)) then
			count = count + 1
			if selection == entry.id then selectedIndex = count end
			local row = Row(frame.browser, count, 210, function(button) Select(button.id) end)
			row.id = entry.id
			row.icon:SetAtlas(kind)
			row.text:SetText(entry.title)
			row.sub:SetText(FormatLevel(entry.data.min, entry.data.max))
			StyleButton(row, selection == entry.id)
		end
	end
	frame.noSearch:SetShown(count == 0)
	ShowRows(frame.browser, count, reset)
	if reveal and selectedIndex then
		frame.browser:SetVerticalScroll(math.min(frame.browser.range, (selectedIndex - 1) * ROW))
	end
end

Select = function(id)
	if not data[id] then return end
	selection, kind = id, data[id].kind
	mapPage = (data[id].floors or data[id].minimap) and 1 or 0
	StyleButton(frame.dungeons, kind == "dungeon")
	StyleButton(frame.raids, kind == "raid")
	RenderCatalog(false)
	Render(true)
end

local function SelectKind(target)
	for _, entry in ipairs(Catalog()) do
		if entry.data.kind == target then
			frame.search:SetText("")
			Select(entry.id)
			RenderCatalog(true)
			return
		end
	end
end

local function AnchoredLabel(parent, size, color, x, y, title)
	local label = Label(parent, size, color)
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(title)
	return label
end

local function MovePage(delta)
	local entry = data[selection]
	local count = #(entry.floors or entry.minimap)
	mapPage = (mapPage - 1 + delta) % count + 1
	DrawMap(selection, entry)
end

local function CreateMap(parent)
	local map = CreateFrame("Frame", nil, parent)
	map:SetPoint("TOPLEFT", 246, -184)
	map:SetSize(682, 369)
	local image = CreateFrame("Frame", nil, map)
	image:SetPoint("TOPLEFT", 0, -35)
	image:SetSize(682, 305)
	Fill(image, "BACKGROUND", EDGE)
	local matte = image:CreateTexture(nil, "BACKGROUND", nil, 1)
	matte:SetPoint("TOPLEFT", 1, -1)
	matte:SetPoint("BOTTOMRIGHT", -1, 1)
	matte:SetColorTexture(0.019, 0.028, 0.044, 1)
	image.canvas = CreateFrame("Frame", nil, image)
	image.canvas:SetPoint("CENTER")
	image.tiles = {}
	image.pin = image.canvas:CreateTexture(nil, "OVERLAY")
	image.pin:SetSize(26, 26)
	image.pin:SetAtlas("dungeon")
	image.empty = Label(image, 14, MUTED)
	image.empty:SetPoint("CENTER")
	image.empty:SetText(L.JOURNAL_NO_MAP)
	parent.mapImage = image
	parent.mapLabel = AnchoredLabel(map, 15, GOLD, 0, -7, "")
	parent.mapCaption = AnchoredLabel(map, 11, MUTED, 0, -347, "")
	parent.mapCaption:SetWidth(682)
	parent.mapCaption:SetWordWrap(true)
	parent.prev = Button(map, 28, 25, "‹", function() MovePage(-1) end)
	parent.prev:SetPoint("TOPRIGHT", -36, 0)
	parent.next = Button(map, 28, 25, "›", function() MovePage(1) end)
	parent.next:SetPoint("TOPRIGHT")
	parent.entranceButton = Button(map, 132, 25, "", function()
		mapPage = mapPage == 0 and 1 or 0
		DrawMap(selection, data[selection])
	end)
	parent.entranceButton:SetPoint("TOPRIGHT", -76, 0)
	return map
end

local function RefreshQuests()
	if frame and frame:IsShown() and selectedTab == "quests" and not frame.questRefresh then
		frame.questRefresh = true
		ns.After("DungeonJournal: refresh quests", 0.15, function()
			frame.questRefresh = nil
			if frame:IsShown() and selectedTab == "quests" then Render(false) end
		end)
	end
end

local function CreateJournal()
	local panel = ns.CreatePanel("ForeverPlusDungeonJournal", { close = true })
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetPoint("CENTER")
	local screenWidth = ns.Number(UIParent:GetWidth(), WIDTH + 24)
	local screenHeight = ns.Number(UIParent:GetHeight(), HEIGHT + 24)
	panel:SetScale(math.min(1, screenWidth / (WIDTH + 24), screenHeight / (HEIGHT + 24)))
	local background = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
	background:SetColorTexture(unpack(DARK))
	background:SetPoint("TOPLEFT", 5, -5)
	background:SetPoint("BOTTOMRIGHT", -5, 5)
	panel.Title:SetFont(panel.Title:GetFont(), 18)
	panel.Title:SetTextColor(unpack(GOLD))
	panel.Title:SetText(L.JOURNAL_TITLE)
	panel.Title:ClearAllPoints()
	panel.Title:SetPoint("TOPLEFT", 16, -14)
	Line(panel, 16, -16, -41, EDGE)

	panel.dungeons = Button(panel, 102, 25, L.JOURNAL_DUNGEONS, function() SelectKind("dungeon") end)
	panel.dungeons:SetPoint("TOPLEFT", 16, -54)
	panel.raids = Button(panel, 102, 25, L.JOURNAL_RAIDS, function() SelectKind("raid") end)
	panel.raids:SetPoint("LEFT", panel.dungeons, "RIGHT", 6, 0)
	panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	panel.search:SetPoint("TOPLEFT", 21, -89)
	panel.search:SetSize(202, 24)
	panel.search:SetAutoFocus(false)
	panel.search:SetMaxLetters(80)
	panel.search.Instructions:SetText(L.JOURNAL_SEARCH)
	panel.search:HookScript("OnTextChanged", ns.Measured("DungeonJournal: search", function()
		RenderCatalog(true)
	end))
	panel.browser = List(panel, 210, 425, ROW)
	panel.browser:SetPoint("TOPLEFT", 16, -124)
	panel.noSearch = AnchoredLabel(panel, 12, MUTED, 28, -140, L.JOURNAL_NO_SEARCH)

	local hero = CreateFrame("Frame", nil, panel)
	hero:SetPoint("TOPLEFT", 246, -54)
	hero:SetSize(682, 87)
	Fill(hero, "BACKGROUND", INK)
	panel.art = hero:CreateTexture(nil, "ARTWORK")
	panel.art:SetPoint("TOPRIGHT")
	panel.art:SetPoint("BOTTOMRIGHT")
	panel.art:SetWidth(341)
	panel.art:SetTexCoord(0, 1, 0.22, 0.70)
	panel.art:SetVertexColor(0.65, 0.65, 0.65, 0.72)
	local fade = hero:CreateTexture(nil, "OVERLAY")
	fade:SetPoint("TOPLEFT", panel.art)
	fade:SetPoint("BOTTOMLEFT", panel.art)
	fade:SetWidth(155)
	fade:SetColorTexture(1, 1, 1, 1)
	fade:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], 1), CreateColor(INK[1], INK[2], INK[3], 0))
	panel.subtitle = AnchoredLabel(hero, 11, GOLD, 14, -12, "")
	panel.name = AnchoredLabel(hero, 23, WHITE, 14, -30, "")
	panel.name:SetPoint("RIGHT", -12, 0)
	panel.name:SetWordWrap(false)
	panel.counts = AnchoredLabel(hero, 11, MUTED, 14, -63, "")

	panel.tabs = {}
	for index, tab in ipairs(tabs) do
		local key = tab[1]
		local button = Button(panel, 106, 28, tab[2], function()
			selectedTab = key
			Render(true)
		end)
		button:SetPoint("TOPLEFT", 246 + (index - 1) * 112, -147)
		panel.tabs[key] = button
	end
	panel.map = CreateMap(panel)
	panel.character = Button(panel, 158, 28, L.JOURNAL_MY_QUESTS, function(button)
		characterOnly = not characterOnly
		StyleButton(button, characterOnly)
		button.text:SetText(characterOnly and L.JOURNAL_MY_QUESTS or L.JOURNAL_ALL_QUESTS)
		Render(true)
	end)
	panel.character:SetPoint("TOPRIGHT", -16, -147)
	StyleButton(panel.character, characterOnly)
	panel.entries = List(panel, 676, 311, ROW)
	panel.entries:SetPoint("TOPLEFT", 246, -214)
	panel.listTitle = AnchoredLabel(panel, 15, GOLD, 246, -191, "")
	panel.listNote = AnchoredLabel(panel, 11, MUTED, 246, -538, "")
	panel.listNote:SetWidth(682)
	panel.listNote:SetWordWrap(true)
	panel.empty = AnchoredLabel(panel, 14, MUTED, 256, -236, "")
	panel.empty:SetWidth(645)
	panel.empty:SetWordWrap(true)
	panel:SetScript("OnHide", ns.Measured("DungeonJournal: close", function()
		panel.search:ClearFocus()
		panel.art:SetTexture(nil)
		for _, tile in ipairs(panel.mapImage.tiles) do tile:SetTexture(nil) end
		GameTooltip:Hide()
		Journal:UnregisterEvent("QUEST_LOG_UPDATE")
		Journal:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
	end))
	return panel
end

function Journal.IsEnabled()
	return Journal.db and Journal.db.enabled
end

function Journal.Open(id, mapID, x, y)
	if not Journal.IsEnabled() then
		ns.PrintAlways(L.JOURNAL_DISABLED)
		return
	end
	frame = frame or CreateJournal()
	local explicit = id and data[id]
	local current = CurrentInstance()
	local target = explicit and id or data[current] and current or selection or Catalog()[1].id
	frame.entrance = mapID and { id = target, mapID = mapID, x = x, y = y } or nil
	if not frame:IsShown() then
		Journal:RegisterEvent("QUEST_LOG_UPDATE", RefreshQuests)
		Journal:RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, _, questID, success)
			if success and requested[questID] then RefreshQuests() end
		end)
	end
	if explicit or target ~= selection then
		selectedTab = "map"
		frame.search:SetText("")
		Select(target)
		RenderCatalog(true, true)
	else
		Render(false)
	end
	frame:Show()
end

function Journal.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Journal.Open()
	end
end

function Journal:OnOptionChanged()
	if not self.db.enabled and frame then frame:Hide() end
	ns.MapSymbols.Refresh()
end

ns.AddMapFilterEntry(function(root)
	if Journal.IsEnabled() then
		root:CreateButton(L.JOURNAL_TITLE, Journal.Toggle)
	end
end)

Journal.options = {
	{ key = "enabled", type = "toggle", name = L.JOURNAL_TITLE, desc = L.JOURNAL_OPTION, new = true },
	{ type = "button", name = L.JOURNAL_TITLE, text = L.JOURNAL_OPEN, func = function() Journal.Open() end },
}

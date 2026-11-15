-- The journal owns its frames and draws client textures without Blizzard's pin system.
local _, ns = ...
local L = ns.L
local Journal = ns:NewModule("DungeonJournal", {
	title = L.JOURNAL_TITLE, order = 12,
	defaults = { enabled = true, bookButton = true, questWaypoint = true },
})

local data = ns.DungeonJournalData.instances
local german = GetLocale() == "deDE"
local WIDTH, HEIGHT = 872, 570
local DETAIL_X, RIGHT_MARGIN = 249, 14
local DETAIL_WIDTH = WIDTH - DETAIL_X - RIGHT_MARGIN
local DETAIL_TOP = -158
local ROW = 36
local PORTRAIT = [[Interface\EncounterJournal\UI-EJ-PortraitIcon]]
local ROW_HIGHLIGHT = [[Interface\QuestFrame\UI-QuestTitleHighlight]]
local ICON = { boss = [[Interface\TargetingFrame\UI-RaidTargetingIcon_8]], quest = 132049, done = 136814 }
local STATES = {
	ready = { 1, 0.82, 0.35 }, active = { 0.50, 0.80, 1 }, done = { 0.51, 0.82, 0.57 },
}
local STATUS = {
	ready = L.JOURNAL_READY, active = L.JOURNAL_ACTIVE, done = L.JOURNAL_DONE, missing = L.JOURNAL_MISSING,
}
local frame, bookButton, catalog, selection, mapPage, selectedTab
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

local function Label(parent, font, point, x, y, title)
	local label = parent:CreateFontString(nil, "OVERLAY", font)
	label:SetPoint(point, x, y)
	label:SetText(title)
	label:SetJustifyH("LEFT")
	return label
end

local function PanelButton(parent, width, title, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(title)
	button:SetScript("OnClick", ns.Measured("DungeonJournal: click", onClick))
	return button
end

local function Tab(parent, title, onClick)
	local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
	tab:SetText(title)
	tab:SetScript("OnClick", ns.Measured("DungeonJournal: tab", onClick))
	return tab
end

local function SelectTab(tab, selected)
	if selected then
		PanelTemplates_SelectTab(tab)
	else
		PanelTemplates_DeselectTab(tab)
	end
end

local function PageButton(parent, direction, onClick)
	local button = CreateFrame("Button", nil, parent)
	local texture = [[Interface\Buttons\UI-SpellbookIcon-]] .. direction .. "Page"
	button:SetSize(26, 26)
	button:SetNormalTexture(texture .. "-Up")
	button:SetPushedTexture(texture .. "-Down")
	button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	button:SetScript("OnClick", ns.Measured("DungeonJournal: page", onClick))
	return button
end

local function List(parent, width, height)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	scroll:SetSize(width, height)
	scroll:EnableMouseWheel(true)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	scroll:SetPanExtent(ROW)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, height)
	scroll:SetScrollChild(child)
	scroll.content, scroll.rows, scroll.range = child, {}, 0
	return scroll
end

local function ShowRows(scroll, count, reset)
	for index = count + 1, #scroll.rows do scroll.rows[index]:Hide() end
	local height = scroll:GetHeight()
	local contentHeight = math.max(height, count * ROW)
	local offset = reset and 0 or ns.Number(scroll:GetVerticalScroll(), 0)
	scroll.range = contentHeight - height
	scroll.content:SetHeight(contentHeight)
	scroll:UpdateScrollChildRect()
	scroll:SetVerticalScroll(math.min(offset, scroll.range))
end

local function Row(scroll, index, onClick)
	local row = scroll.rows[index]
	if not row then
		row = CreateFrame("Button", nil, scroll.content)
		row:SetSize(scroll:GetWidth(), ROW)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
		row:SetHighlightTexture(ROW_HIGHLIGHT, "ADD")
		row.selectedArt = row:CreateTexture(nil, "ARTWORK")
		row.selectedArt:SetTexture(ROW_HIGHLIGHT)
		row.selectedArt:SetBlendMode("ADD")
		row.selectedArt:SetAlpha(0.48)
		row.selectedArt:SetAllPoints()
		row.selectedArt:Hide()
		local line = row:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.65, 0.48, 0.28, 0.22)
		line:SetPoint("BOTTOMLEFT", 4, 0)
		line:SetPoint("BOTTOMRIGHT", -4, 0)
		line:SetHeight(1)

		row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetSize(23, 23)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 6)
		row.text:SetPoint("RIGHT", -8, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		row.sub:SetPoint("RIGHT", -8, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)
		row:SetScript("OnClick", ns.Measured("DungeonJournal: row", onClick))
		row:SetScript("OnLeave", GameTooltip_Hide)
		scroll.rows[index] = row
	end
	row:Show()
	return row
end

local function Tooltip(button, title, note)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 1, 1, true)
	if note then GameTooltip:AddLine(note, GRAY_FONT_COLOR:GetRGB()) end
end

-- Keep the known pickup location in the tooltip even if the game cannot put a pin there.
local function PickupPoint(id)
	local lib = ns.QuestieDB.Bundled()
	local starts = lib and lib.Quest.Get(id, "startPoints")
	local current = ns.Number(C_Map.GetBestMapForUnit("player"))
	local best, bestRank, canSet
	for _, point in ipairs(starts or {}) do
		local mapID, x, y = unpack(point)
		if mapID > 0 and x >= 0 and x <= 100 and y >= 0 and y <= 100 and (x > 0 or y > 0) then
			local supported = C_Map.CanSetUserWaypointOnMap(mapID)
			local rank = supported and (mapID == current and 3 or 2) or 1
			if not bestRank or rank > bestRank then
				best, bestRank, canSet = point, rank, supported
				if rank == 3 then break end
			end
		end
	end
	return best, canSet
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
	local point, canSet = PickupPoint(quest.id)
	if point then
		local map = C_Map.GetMapInfo(point[1])
		if map and Text(map.name) then
			GameTooltip:AddLine(L.JOURNAL_PICKUP:format(map.name, point[2], point[3]), NORMAL_FONT_COLOR:GetRGB())
		end
	end
	if Journal.db.questWaypoint then
		local hint = canSet and L.JOURNAL_PICKUP_CLICK or point and L.JOURNAL_PICKUP_UNAVAILABLE or L.JOURNAL_PICKUP_UNKNOWN
		GameTooltip:AddLine(hint, 0.68, 0.73, 0.81, true)
	end
	GameTooltip:AddLine(Journal.db.questWaypoint and L.JOURNAL_QUEST_RIGHT_CLICK or L.JOURNAL_QUEST_LINK, 0.68, 0.73, 0.81, true)
	GameTooltip:Show()
end

local function OpenQuest(row, button)
	local quest = row.quest
	if not quest then return end
	GameTooltip:Hide()
	if Journal.db.questWaypoint and button ~= "RightButton" then
		local point, canSet = PickupPoint(quest.id)
		if not point then
			ns.PrintAlways(L.JOURNAL_PICKUP_UNKNOWN)
		elseif not canSet or not ns:GetModule("Waypoint").SetOnMap(point[1], point[2], point[3], quest.name) then
			ns.PrintAlways(L.JOURNAL_PICKUP_UNAVAILABLE)
		end
		return
	end
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
	frame.entranceButton:SetText(mapPage == 0 and L.JOURNAL_INTERIOR or L.JOURNAL_ENTRANCE)
	image.empty:SetShown(tiles == nil)
	image.pin:Hide()
	local used = 0
	if tiles and width > 0 and height > 0 and tileW > 0 and tileH > 0 then
		local scale = math.min((image:GetWidth() - 8) / width, (image:GetHeight() - 8) / height)
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
	for key, button in pairs(frame.tabs) do SelectTab(button, key == selectedTab) end
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
		local row = Row(frame.entries, index, OpenQuest)
		row.quest = quests and record or nil
		if not row.tooltipHook then
			row.tooltipHook = true
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:HookScript("OnEnter", ns.Measured("DungeonJournal: quest tooltip", QuestTooltip))
		end
		if quests then
			row.icon:SetTexture(record.state == "done" and ICON.done or ICON.quest)
			row.icon:SetDesaturated(record.state == "done")
			row.text:SetText(record.name)
			local level = record.level and record.level > 0 and L.JOURNAL_MIN_LEVEL:format(record.level) or ""
			local side = record.side == "A" and L.JOURNAL_ALLIANCE or record.side == "H" and L.JOURNAL_HORDE
			row.sub:SetText(STATUS[record.state] .. (level ~= "" and "  ·  " .. level or "") .. (side and "  ·  " .. side or ""))
			local color = STATES[record.state]
			if color then
				row.sub:SetTextColor(unpack(color))
			else
				row.sub:SetTextColor(GRAY_FONT_COLOR:GetRGB())
			end
		else
			row.icon:SetTexture(ICON.boss)
			row.icon:SetDesaturated(false)
			row.text:SetText(german and record[3] or record[2])
			row.sub:SetText(L.JOURNAL_ENCOUNTER:format(index))
			row.sub:SetTextColor(GRAY_FONT_COLOR:GetRGB())
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
			local row = Row(frame.browser, count, function(button) Select(button.id) end)
			row.id = entry.id
			row.icon:SetAtlas(kind)
			row.text:SetText(entry.title)
			row.sub:SetText(FormatLevel(entry.data.min, entry.data.max))
			row.selectedArt:SetShown(selection == entry.id)
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
	SelectTab(frame.dungeons, kind == "dungeon")
	SelectTab(frame.raids, kind == "raid")
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

local function MovePage(delta)
	local entry = data[selection]
	local count = #(entry.floors or entry.minimap)
	mapPage = (mapPage - 1 + delta) % count + 1
	DrawMap(selection, entry)
end

local function CreateMap(panel, parent)
	local map = CreateFrame("Frame", nil, parent)
	map:SetAllPoints()
	local image = CreateFrame("Frame", nil, map, "InsetFrameTemplate")
	image:SetPoint("TOPLEFT", 9, -39)
	image:SetSize(DETAIL_WIDTH - 18, 331)
	image.Bg:SetVertexColor(0.37, 0.34, 0.31)
	image.canvas = CreateFrame("Frame", nil, image)
	image.canvas:SetPoint("CENTER")
	image.tiles = {}
	image.pin = image.canvas:CreateTexture(nil, "OVERLAY")
	image.pin:SetSize(26, 26)
	image.pin:SetAtlas("dungeon")
	image.empty = Label(image, "GameFontDisable", "CENTER", 0, 0, L.JOURNAL_NO_MAP)
	panel.mapImage = image
	panel.mapLabel = Label(map, "GameFontNormal", "TOPLEFT", 12, -15)
	panel.mapCaption = Label(map, "GameFontHighlightSmall", "TOPLEFT", 12, -379)
	panel.mapCaption:SetWidth(DETAIL_WIDTH - 24)
	panel.mapCaption:SetWordWrap(true)
	panel.prev = PageButton(map, "Prev", function() MovePage(-1) end)
	panel.prev:SetPoint("TOPRIGHT", -35, -6)
	panel.next = PageButton(map, "Next", function() MovePage(1) end)
	panel.next:SetPoint("TOPRIGHT", -9, -6)
	panel.entranceButton = PanelButton(map, 132, "", function()
		mapPage = mapPage == 0 and 1 or 0
		DrawMap(selection, data[selection])
	end)
	panel.entranceButton:SetPoint("TOPRIGHT", -68, -8)
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
	local panel = CreateFrame("Frame", "ForeverPlusDungeonJournal", UIParent, "PortraitFrameTemplate")
	panel:Hide()
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetTitle(L.JOURNAL_TITLE)
	panel:SetPortraitToAsset(PORTRAIT)
	panel.tabPadding = 16
	panel.CloseButton:SetScript("OnClick", ns.Measured("DungeonJournal: close button", function() panel:Hide() end))
	tinsert(UISpecialFrames, panel:GetName())
	ns.FadeIn(panel)

	local screenWidth = ns.Number(UIParent:GetWidth(), WIDTH + 24)
	local screenHeight = ns.Number(UIParent:GetHeight(), HEIGHT + 24)
	panel:SetScale(math.min(1, screenWidth / (WIDTH + 24), screenHeight / (HEIGHT + 24)))

	local sidebar = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	sidebar:SetPoint("TOPLEFT", 11, -86)
	sidebar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", DETAIL_X - 10, 12)
	panel.dungeons = Tab(panel, L.JOURNAL_DUNGEONS, function() SelectKind("dungeon") end)
	panel.dungeons:SetPoint("BOTTOMLEFT", sidebar, "TOPLEFT", 5, -2)
	panel.raids = Tab(panel, L.JOURNAL_RAIDS, function() SelectKind("raid") end)
	panel.raids:SetPoint("LEFT", panel.dungeons, "RIGHT", 6, 0)
	panel.search = CreateFrame("EditBox", nil, sidebar, "SearchBoxTemplate")
	panel.search:SetPoint("TOPLEFT", 12, -10)
	panel.search:SetSize(198, 22)
	panel.search:SetAutoFocus(false)
	panel.search:SetMaxLetters(80)
	panel.search.Instructions:SetText(L.JOURNAL_SEARCH)
	panel.search:HookScript("OnTextChanged", ns.Measured("DungeonJournal: search", function()
		RenderCatalog(true)
	end))
	panel.browser = List(sidebar, DETAIL_X - 54, 421)
	panel.browser:SetPoint("TOPLEFT", 7, -39)
	panel.noSearch = Label(sidebar, "GameFontDisable", "TOPLEFT", 14, -46, L.JOURNAL_NO_SEARCH)

	local header = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	header:SetPoint("TOPLEFT", DETAIL_X, -32)
	header:SetSize(DETAIL_WIDTH, 94)
	panel.art = header:CreateTexture(nil, "ARTWORK")
	panel.art:SetPoint("TOPRIGHT", -4, -4)
	panel.art:SetPoint("BOTTOMRIGHT", -4, 4)
	panel.art:SetWidth(330)
	panel.art:SetTexCoord(0, 1, 0.30, 0.57)
	panel.art:SetVertexColor(0.82, 0.75, 0.62)
	local fade = header:CreateTexture(nil, "ARTWORK", nil, 1)
	fade:SetPoint("TOPLEFT", panel.art)
	fade:SetPoint("BOTTOMRIGHT", panel.art, "BOTTOMLEFT", 160, 0)
	fade:SetColorTexture(1, 1, 1, 1)
	fade:SetGradient("HORIZONTAL", CreateColor(0.08, 0.074, 0.067, 1), CreateColor(0.08, 0.074, 0.067, 0))
	panel.name = Label(header, "GameFontNormalLarge", "TOPLEFT", 13, -16)
	panel.name:SetPoint("RIGHT", -13, 0)
	panel.name:SetWordWrap(false)
	panel.subtitle = Label(header, "GameFontHighlight", "TOPLEFT", 13, -43)
	panel.counts = Label(header, "GameFontHighlightSmall", "TOPLEFT", 13, -65)

	local detail = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	detail:SetPoint("TOPLEFT", DETAIL_X, DETAIL_TOP)
	detail:SetPoint("BOTTOMRIGHT", -RIGHT_MARGIN, 12)
	panel.tabs = {}
	local previousTab
	for _, spec in ipairs(tabs) do
		local key = spec[1]
		local tab = Tab(panel, spec[2], function()
			selectedTab = key
			Render(true)
		end)
		if previousTab then
			tab:SetPoint("LEFT", previousTab, "RIGHT", 6, 0)
		else
			tab:SetPoint("BOTTOMLEFT", detail, "TOPLEFT", 5, -2)
		end
		panel.tabs[key] = tab
		previousTab = tab
	end
	panel.map = CreateMap(panel, detail)
	panel.character = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
	panel.character:SetPoint("TOPLEFT", DETAIL_WIDTH - 185, -5)
	panel.character:SetSize(26, 26)
	panel.character.Text:SetText(L.JOURNAL_MY_QUESTS)
	panel.character:SetHitRectInsets(0, -panel.character.Text:GetStringWidth(), 0, 0)
	panel.character:SetChecked(characterOnly)
	panel.character:SetScript("OnClick", ns.Measured("DungeonJournal: character filter", function(button)
		characterOnly = button:GetChecked()
		Render(true)
	end))
	panel.entries = List(detail, DETAIL_WIDTH - 33, 326)
	panel.entries:SetPoint("TOPLEFT", 8, -41)
	panel.listTitle = Label(detail, "GameFontNormal", "TOPLEFT", 12, -15)
	panel.listNote = Label(detail, "GameFontHighlightSmall", "TOPLEFT", 12, -379)
	panel.listNote:SetWidth(DETAIL_WIDTH - 24)
	panel.listNote:SetWordWrap(true)
	panel.empty = Label(detail, "GameFontDisable", "TOPLEFT", 16, -62)
	panel.empty:SetWidth(DETAIL_WIDTH - 40)
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

function Journal.HasDungeon(id)
	return data[id] and data[id].kind == "dungeon"
end

function Journal.InstanceName(id)
	return Name(id, data[id])
end

function Journal.OpenDungeons()
	if Journal.HasDungeon(selection) then
		Journal.Open(selection)
		return
	end
	for _, entry in ipairs(Catalog()) do
		if entry.data.kind == "dungeon" then
			Journal.Open(entry.id)
			return
		end
	end
end

local function UpdateBookButton()
	if bookButton then
		bookButton:SetShown(Journal.IsEnabled() and Journal.db.bookButton and not WorldMapFrame:IsMaximized())
	end
end

function Journal:OnLogin()
	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		local border = WorldMapFrame and WorldMapFrame.BorderFrame
		local portrait = border and border.GetPortrait and border:GetPortrait()
		if not portrait then return end
		bookButton = CreateFrame("Button", "ForeverPlusMapBookJournalButton", border.PortraitContainer)
		bookButton:SetPoint("TOPLEFT", portrait, "TOPLEFT", 9, -9)
		bookButton:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -9, 9)
		bookButton:SetScript("OnClick", ns.Measured("DungeonJournal: map book", function()
			GameTooltip:Hide()
			Journal.Toggle()
		end))
		bookButton:SetScript("OnEnter", ns.Measured("DungeonJournal: book tooltip", function(button)
			Tooltip(button, L.JOURNAL_TITLE, L.JOURNAL_BOOK_CLICK)
			GameTooltip:Show()
		end))
		bookButton:SetScript("OnLeave", GameTooltip_Hide)
		local update = ns.Measured("DungeonJournal: map book visibility", UpdateBookButton)
		hooksecurefunc(border, "SetPortraitShown", update)
		WorldMapFrame:HookScript("OnShow", update)
		UpdateBookButton()
	end)
end

function Journal:OnOptionChanged()
	if not self.db.enabled and frame then frame:Hide() end
	UpdateBookButton()
	local finder = ns:GetModule("GroupFinder")
	if finder and finder.RefreshJournalButtons then finder.RefreshJournalButtons() end
	ns.MapSymbols.Refresh()
end

ns.AddMapFilterEntry(function(root)
	if Journal.IsEnabled() then
		root:CreateButton(L.JOURNAL_TITLE, Journal.Toggle)
	end
end)

Journal.options = {
	{ key = "enabled", type = "toggle", name = L.JOURNAL_TITLE, desc = L.JOURNAL_OPTION, new = true },
	{ key = "bookButton", type = "toggle", name = L.JOURNAL_BOOK_OPTION, parent = "enabled", new = true },
	{ key = "questWaypoint", type = "toggle", name = L.JOURNAL_PICKUP_OPTION, parent = "enabled", new = true },
	{ type = "button", name = L.JOURNAL_TITLE, text = L.JOURNAL_OPEN, func = function() Journal.Open() end },
}

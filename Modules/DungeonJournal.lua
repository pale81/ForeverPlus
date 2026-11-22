-- The journal owns its frames and draws client textures without Blizzard's pin system.
local _, ns = ...
local L = ns.L
local Journal = ns:NewModule("DungeonJournal", {
	title = L.JOURNAL_TITLE, order = 12,
	defaults = { enabled = true, bookButton = true, questWaypoint = true, mapZoom = true, bossDetails = true, bossLoot = true,
		lootUpgradesOnly = false },
})

local data = ns.DungeonJournalData.instances
local bossData = ns.DungeonJournalBosses
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
local frame, bookButton, catalog, selection, mapPage, selectedTab, selectedBoss
local Render, RenderCatalog, Select
local kind, characterOnly = "dungeon", true
local requested, requestedItems = {}, {}
local lootBoss, lootIndex
local tabs = {
	{ "map", L.JOURNAL_MAP }, { "bosses", L.JOURNAL_BOSSES }, { "quests", L.JOURNAL_QUESTS }, { "loot", L.JOURNAL_LOOT },
}

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
		if onClick then row:SetScript("OnClick", ns.Measured("DungeonJournal: row", onClick)) end
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

local function BossName(boss)
	return german and boss[3] or boss[2]
end

local function BossPage(entry, info)
	local tile = info and info.position and info.position[1]
	if not tile then return end
	for index, floor in ipairs(entry.floors or {}) do
		if floor[1] == tile then return index end
	end
	for index, section in ipairs(entry.minimap or {}) do
		if section[3][1][1] == tile then return index end
	end
end

local function BossSpellName(id)
	return Text(C_Spell.GetSpellName(id)) or L.JOURNAL_SPELL_ID:format(id)
end

local function BossPositionSource(info)
	if info then
		if info.classic then return L.JOURNAL_CLASSIC_BOSS end
		if info.approximate then return L.JOURNAL_APPROX_BOSS end
	end
end

local function BossTooltip(button)
	if not button.boss or not Journal.db.bossDetails then return end
	if button.overlaps then
		Tooltip(button, L.JOURNAL_BOSSES, L.JOURNAL_SHARED_BOSS_POINT)
		for _, entry in ipairs(button.overlaps) do
			GameTooltip:AddLine(BossName(entry[1]), 1, 0.82, 0.35, true)
		end
		GameTooltip:AddLine(L.JOURNAL_SHARED_BOSS_CLICK, 0.68, 0.73, 0.81, true)
		GameTooltip:Show()
		return
	end
	local info = bossData[button.boss[1]]
	Tooltip(button, BossName(button.boss), L.JOURNAL_ENCOUNTER:format(button.bossIndex))
	if info and info.note then
		GameTooltip:AddLine(info.note[german and 2 or 1], 0.85, 0.85, 0.85, true)
	end
	local spells = info and info.spells or {}
	for index = 1, math.min(#spells, 5) do
		GameTooltip:AddLine(BossSpellName(spells[index]), 1, 0.82, 0.35, true)
	end
	local source = BossPositionSource(info)
	if source then
		GameTooltip:AddLine(source, 0.68, 0.73, 0.81, true)
	end
	GameTooltip:AddLine(L.JOURNAL_BOSS_CLICK, 0.68, 0.73, 0.81, true)
	GameTooltip:Show()
end

local function SelectBoss(index)
	selectedBoss, selectedTab = index, "bosses"
	Render(true)
end

-- Creature name (lower case) -> set of "npc:<id>" keys, from the shipped loot data and the player's own
-- loot windows; own names are in the client language, so German boss names find them too.
local function AddLootName(index, name, key)
	if type(name) ~= "string" or name == "" or name == "?" or key:sub(1, 4) ~= "npc:" then return end
	local lower = name:lower()
	index[lower] = index[lower] or {}
	index[lower][key] = true
end

local function LootIndex()
	if lootIndex then return lootIndex end
	lootIndex = {}
	for key, name in pairs(ns.LootData and ns.LootData.names or {}) do AddLootName(lootIndex, name, key) end
	for key, entry in pairs(ns.db.lootSources or {}) do AddLootName(lootIndex, entry.name, key) end
	for key, name in pairs(ns.db.lootNames or {}) do AddLootName(lootIndex, name, key) end
	return lootIndex
end

-- Loot of a boss: { { id, drops, windows }, ... }, highest share first. Group loot rolls of the encounter
-- (windows = recorded kills) come first; items seen on corpses of creatures with the boss's English or
-- German name are added when the rolls do not list them.
function Journal.BossLoot(boss)
	local index, sources = LootIndex(), ns:GetModule("LootSources")
	local keys = {}
	for field = 2, 3 do
		for key in pairs(boss[field] and index[boss[field]:lower()] or {}) do keys[key] = true end
	end
	local drops, windows, list = {}, 0, {}
	for key in pairs(keys) do
		local rows = sources.CreatureDrops(key)
		if rows then
			windows = windows + rows.windows
			for _, row in ipairs(rows) do drops[row.id] = (drops[row.id] or 0) + row.drops end
		end
	end
	local listed = {}
	local rolls = ns.LootData and ns.LootData.encounters and ns.LootData.encounters[boss[1]]
	for _, row in ipairs(rolls and rolls[2] or {}) do
		list[#list + 1] = { id = row[1], drops = row[2], windows = rolls[1] }
		listed[row[1]] = true
	end
	for id, count in pairs(drops) do
		if not listed[id] then list[#list + 1] = { id = id, drops = count, windows = windows } end
	end
	table.sort(list, function(a, b)
		local shareA, shareB = a.drops / a.windows, b.drops / b.windows
		if shareA ~= shareB then return shareA > shareB end
		return a.id < b.id
	end)
	return list
end

local function LootRows(entry)
	local rows = {}
	for index, boss in ipairs(entry.bosses) do
		if not lootBoss or lootBoss == index then
			for _, item in ipairs(Journal.BossLoot(boss)) do
				item.boss = boss
				rows[#rows + 1] = item
			end
		end
	end
	return rows
end

local function ItemInfo(id)
	local name, link, quality = C_Item.GetItemInfo(id)
	if type(name) ~= "string" or ns.Secret(name) or name == "" then
		if not requestedItems[id] then
			requestedItems[id] = true
			C_Item.RequestLoadItemDataByID(id)
		end
		return L.LOOTSRC_UNIT_ITEM:format(id)
	end
	return name, not ns.Secret(link) and link or nil, ns.Number(quality)
end

-- Same comparison as in the bags. The list refreshes when pending item data arrives.
local function UpgradeState(id)
	local _, link = ItemInfo(id)
	local state = link and ns.ItemLinkUpgradeState and ns.ItemLinkUpgradeState(link)
	if state == nil and not requestedItems[id] then
		requestedItems[id] = true
		C_Item.RequestLoadItemDataByID(id)
	end
	return state
end

local function UpgradesAvailable()
	local items = ns:GetModule("Items")
	return items and items.db and items.db.upgradeArrow
end

local function ItemTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(row.item.id)
	GameTooltip:Show()
end

local function OpenItem(row)
	local _, link = ItemInfo(row.item.id)
	if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

local function RefreshLoot()
	if frame and frame:IsShown() and selectedTab == "loot" and not frame.lootRefresh then
		frame.lootRefresh = true
		ns.After("DungeonJournal: refresh loot", 0.15, function()
			frame.lootRefresh = nil
			if frame:IsShown() and selectedTab == "loot" then Render(false) end
		end)
	end
end

local function OpenBoss(button)
	if not button.boss or not Journal.db.bossDetails then return end
	GameTooltip:Hide()
	if not button.overlaps then
		SelectBoss(button.bossIndex)
		return
	end
	MenuUtil.CreateContextMenu(button, function(_, root)
		for _, entry in ipairs(button.overlaps) do
			local boss, index = unpack(entry)
			root:CreateButton(BossName(boss), ns.Measured("DungeonJournal: select boss", function() SelectBoss(index) end))
		end
	end)
end

local function PositionMap(image)
	local canvas, view = image.canvas, image.viewport
	local vw, vh = view:GetSize()
	local width, height = canvas:GetWidth() * image.zoom, canvas:GetHeight() * image.zoom
	local limitX, limitY = math.max(0, (width - vw) / 2), math.max(0, (height - vh) / 2)
	image.panX = math.max(-limitX, math.min(limitX, image.panX))
	image.panY = math.max(-limitY, math.min(limitY, image.panY))
	canvas:SetScale(image.zoom)
	canvas:ClearAllPoints()
	canvas:SetPoint("CENTER", view, "CENTER", image.panX / image.zoom, image.panY / image.zoom)
	for i = 1, image.pinCount do
		local pin = image.bossPins[i]
		local x = image.panX + (pin.x - 0.5) * width
		local y = image.panY + (0.5 - pin.y) * height
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", view, "CENTER", x, y)
		pin:SetShown(math.abs(x) + pin:GetWidth() / 2 <= vw / 2 and math.abs(y) + pin:GetHeight() / 2 <= vh / 2)
	end
end

local function StopMapDrag(image)
	image.dragX, image.dragY = false, nil
	ns.SetUpdate(image.viewport, "DungeonJournal: pan map", nil)
end

local function ResetMapView(image)
	StopMapDrag(image)
	image.zoom, image.panX, image.panY = 1, 0, 0
end

local function ZoomMap(image, delta)
	if not Journal.db.mapZoom or not image.hasArt or image.dragX or delta == 0 then return end
	local zoom = math.max(1, math.min(4, image.zoom * (delta > 0 and math.sqrt(2) or 1 / math.sqrt(2))))
	if math.abs(zoom - 1) < 0.001 then zoom = 1 end
	if math.abs(zoom - 4) < 0.001 then zoom = 4 end
	if zoom == image.zoom then return end
	local view = image.viewport
	local scale = view:GetEffectiveScale()
	local centerX, centerY = view:GetCenter()
	local x, y = GetCursorPosition()
	x, y = x / scale - centerX, y / scale - centerY
	local ratio = zoom / image.zoom
	image.panX = x + (image.panX - x) * ratio
	image.panY = y + (image.panY - y) * ratio
	image.zoom = zoom
	PositionMap(image)
end

local function PanMap(view)
	local image = view:GetParent()
	local x, y = GetCursorPosition()
	if x == image.dragX and y == image.dragY then return end
	local scale = view:GetEffectiveScale()
	image.panX = image.panX + (x - image.dragX) / scale
	image.panY = image.panY + (y - image.dragY) / scale
	image.dragX, image.dragY = x, y
	PositionMap(image)
end

local function BossPin(image, index)
	local pin = image.bossPins[index]
	if not pin then
		pin = CreateFrame("Button", nil, image.viewport)
		pin:SetSize(20, 20)
		pin:SetNormalTexture(ICON.boss)
		pin:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
		pin:SetScript("OnClick", ns.Measured("DungeonJournal: open boss", OpenBoss))
		pin:SetScript("OnEnter", ns.Measured("DungeonJournal: boss tooltip", BossTooltip))
		pin:SetScript("OnLeave", GameTooltip_Hide)
		pin:EnableMouseWheel(true)
		pin:SetScript("OnMouseWheel", image.viewport:GetScript("OnMouseWheel"))
		image.bossPins[index] = pin
	end
	return pin
end

local function DrawBossPins(image, entry)
	local count, locations = 0, {}
	if mapPage ~= 0 and image.hasArt and Journal.db.bossDetails then
		for index, boss in ipairs(entry.bosses) do
			local info = bossData[boss[1]]
			local position = info and info.position
			if position and BossPage(entry, info) == mapPage then
				local x, y = position[2], position[3]
				local key = x .. ":" .. y
				local pin = locations[key]
				if pin then
					pin.overlaps = pin.overlaps or { { pin.boss, pin.bossIndex } }
					pin.overlaps[#pin.overlaps + 1] = { boss, index }
				else
					count = count + 1
					pin = BossPin(image, count)
					pin.boss, pin.bossIndex, pin.x, pin.y, pin.overlaps = boss, index, x, y, false
					locations[key] = pin
					pin:UnlockHighlight()
					pin:SetFrameLevel(image.viewport:GetFrameLevel() + 2)
				end
				if selectedBoss == index then
					pin:LockHighlight()
					pin:SetFrameLevel(image.viewport:GetFrameLevel() + 3)
				end
			end
		end
	end
	for index = count + 1, #image.bossPins do image.bossPins[index]:Hide() end
	image.pinCount = count
end

local function DrawMap(id, entry)
	local image = frame.mapImage
	if image.instance ~= id or image.page ~= mapPage or not Journal.db.mapZoom then
		ResetMapView(image)
		GameTooltip:Hide()
		image.instance, image.page = id, mapPage
	end
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
	local caption = mapPage == 0 and L.JOURNAL_ENTRANCE_NOTE
		or entry.floors and L.JOURNAL_LEGACY_NOTE or L.JOURNAL_MINIMAP_NOTE
	frame.prev:SetShown(pageCount > 1)
	frame.next:SetShown(pageCount > 1)
	frame.entranceButton:SetShown(Entrance(id) ~= nil and (entry.floors ~= nil or entry.minimap ~= nil))
	frame.entranceButton:SetText(mapPage == 0 and L.JOURNAL_INTERIOR or L.JOURNAL_ENTRANCE)
	image.pin:Hide()
	local used = 0
	if tiles and width > 0 and height > 0 and tileW > 0 and tileH > 0 then
		local scale = math.min(image.viewport:GetWidth() / width, image.viewport:GetHeight() / height)
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
	image.hasArt = used > 0
	image.empty:SetShown(not image.hasArt)
	DrawBossPins(image, entry)
	PositionMap(image)
	local zoomEnabled = image.hasArt and Journal.db.mapZoom
	frame.resetZoom:SetShown(zoomEnabled)
	frame.mapCaption:SetText(image.hasArt and (caption .. (zoomEnabled and "\n" .. L.JOURNAL_ZOOM_HINT or "")) or "")
end

local function OpenEntry(row, button)
	if row.item then
		OpenItem(row)
	elseif row.quest then
		OpenQuest(row, button)
	elseif button == "LeftButton" then
		OpenBoss(row)
	end
end

local function EntryTooltip(row)
	if row.item then ItemTooltip(row) elseif row.quest then QuestTooltip(row) else BossTooltip(row) end
end

local function SpellTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not GameTooltip:SetSpellByID(row.spellID) then
		GameTooltip:AddLine(BossSpellName(row.spellID), 1, 1, 1)
		GameTooltip:Show()
	end
end

local function DrawBossDetails(entry)
	local boss = entry.bosses[selectedBoss]
	local info = bossData[boss[1]]
	local details = frame.bossDetails
	details.title:SetText(BossName(boss))
	details.order:SetText(L.JOURNAL_ENCOUNTER:format(selectedBoss))
	details.mapButton:SetShown(BossPage(entry, info) ~= nil)
	details.lootButton:SetShown(Journal.db.bossLoot)
	local note = info and info.note
	details.note:SetText(note and note[german and 2 or 1] or "")
	local noteHeight = note and details.note:GetStringHeight() + 12 or 0
	details.heading:SetPoint("TOPLEFT", 12, -124 - noteHeight)
	local spells = info and info.spells or {}
	details.empty:SetShown(#spells == 0)
	details.spells:SetShown(#spells > 0)
	details.spells:SetHeight(222 - noteHeight)
	for index, id in ipairs(spells) do
		local row = Row(details.spells, index)
		if not row:GetScript("OnEnter") then
			row:SetScript("OnEnter", ns.Measured("DungeonJournal: ability tooltip", SpellTooltip))
		end
		row.spellID = id
		row.icon:SetTexture(C_Spell.GetSpellTexture(id) or 134400)
		row.text:SetText(BossSpellName(id))
	end
	ShowRows(details.spells, #spells, true)
	details.source:SetText(BossPositionSource(info) or "")
end

Render = function(reset)
	local entry = data[selection]
	if selectedTab == "loot" and not Journal.db.bossLoot then selectedTab, lootBoss = "bosses", nil end
	local map = selectedTab == "map"
	local quests = selectedTab == "quests"
	local loot = selectedTab == "loot"
	local bossDetails = not (map or quests or loot) and selectedBoss ~= nil and Journal.db.bossDetails
	for key, button in pairs(frame.tabs) do SelectTab(button, key == selectedTab) end
	frame.tabs.loot:SetShown(Journal.db.bossLoot)
	frame.map:SetShown(map)
	frame.bossDetails:SetShown(bossDetails)
	frame.entries:SetShown(not (map or bossDetails))
	frame.listTitle:SetShown(not (map or bossDetails))
	frame.listNote:SetShown(not (map or bossDetails))
	frame.character:SetShown(quests)
	frame.upgradesOnly:SetShown(loot and UpgradesAvailable() and true or false)
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
	if bossDetails then
		DrawBossDetails(entry)
		return
	end

	local rows = loot and LootRows(entry) or quests and QuestRows(selection, characterOnly) or entry.bosses
	local upgradesOnly = loot and UpgradesAvailable() and Journal.db.lootUpgradesOnly
	if loot then
		local shown = {}
		for _, record in ipairs(rows) do
			record.upgrade = UpgradesAvailable() and UpgradeState(record.id)
			if not upgradesOnly or record.upgrade == true or record.upgrade == "later" then
				shown[#shown + 1] = record
			end
		end
		rows = shown
	end
	if loot then
		local boss = lootBoss and entry.bosses[lootBoss]
		frame.listTitle:SetText(boss and L.JOURNAL_LOOT_BOSS:format(BossName(boss), #rows) or L.JOURNAL_LOOT_COUNT:format(#rows))
		frame.listNote:SetText(L.JOURNAL_LOOT_NOTE)
	else
		frame.listTitle:SetText(quests and L.JOURNAL_QUEST_COUNT:format(#rows) or L.JOURNAL_BOSS_COUNT:format(#rows))
		frame.listNote:SetText(quests and L.JOURNAL_QUEST_NOTE
			or Journal.db.bossDetails and L.JOURNAL_BOSS_CLICK or L.JOURNAL_BOSS_NOTE)
	end
	local sources = ns:GetModule("LootSources")
	for index, record in ipairs(rows) do
		local row = Row(frame.entries, index, OpenEntry)
		row.item = loot and record
		row.quest = quests and record
		row.boss, row.bossIndex, row.overlaps = not (quests or loot) and record, index, false
		if not row:GetScript("OnEnter") then
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:HookScript("OnEnter", ns.Measured("DungeonJournal: entry tooltip", EntryTooltip))
		end
		row.text:SetTextColor(1, 0.82, 0)
		local state = loot and record.upgrade
		if state and not row.upgrade then
			row.upgrade = row:CreateTexture(nil, "OVERLAY", nil, 7)
			row.upgrade:SetAtlas("bags-greenarrow")
			row.upgrade:SetSize(14, 14)
			row.upgrade:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 4, 4)
		end
		if row.upgrade then
			ns.SetItemComparisonArrow(row.upgrade, state)
		end
		if loot then
			local name, _, quality = ItemInfo(record.id)
			local color = quality and ITEM_QUALITY_COLORS[quality]
			row.icon:SetTexture(C_Item.GetItemIconByID(record.id) or 134400)
			row.icon:SetDesaturated(false)
			row.text:SetText(name)
			if color then row.text:SetTextColor(color.r, color.g, color.b) end
			row.sub:SetText(BossName(record.boss) .. "  ·  " .. sources.DropRate(record.drops, record.windows))
			row.sub:SetTextColor(GRAY_FONT_COLOR:GetRGB())
		elseif quests then
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
			row.text:SetText(BossName(record))
			row.sub:SetText(L.JOURNAL_ENCOUNTER:format(index))
			row.sub:SetTextColor(GRAY_FONT_COLOR:GetRGB())
		end
	end
	ShowRows(frame.entries, #rows, reset)
	if #rows == 0 then
		frame.empty:SetText(upgradesOnly and L.JOURNAL_NO_UPGRADES or loot and L.JOURNAL_NO_LOOT
			or quests and (characterOnly and L.JOURNAL_NO_FILTERED_QUESTS or L.JOURNAL_NO_QUESTS)
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
	selectedBoss, lootBoss = nil, nil
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
	local view = CreateFrame("Frame", nil, image)
	view:SetPoint("TOPLEFT", 4, -4)
	view:SetPoint("BOTTOMRIGHT", -4, 4)
	view:SetClipsChildren(true)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:RegisterForDrag("LeftButton")
	view:SetScript("OnMouseWheel", ns.Measured("DungeonJournal: zoom map", function(_, delta)
		ZoomMap(image, delta)
	end))
	view:SetScript("OnDragStart", ns.Measured("DungeonJournal: start map drag", function()
		if image.zoom <= 1 or not image.hasArt then return end
		image.dragX, image.dragY = GetCursorPosition()
		ns.SetUpdate(view, "DungeonJournal: pan map", PanMap)
	end))
	local stop = ns.Measured("DungeonJournal: stop map drag", function() StopMapDrag(image) end)
	view:SetScript("OnDragStop", stop)
	view:SetScript("OnHide", stop)
	image.viewport = view
	image.canvas = CreateFrame("Frame", nil, view)
	image.canvas:SetSize(1, 1)
	image.canvas:SetPoint("CENTER")
	image.tiles, image.bossPins, image.pinCount = {}, {}, 0
	ResetMapView(image)
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
	panel.resetZoom = PanelButton(map, 123, L.JOURNAL_RESET_ZOOM, function()
		ResetMapView(image)
		PositionMap(image)
	end)
	panel.resetZoom:SetPoint("RIGHT", panel.entranceButton, "LEFT", -6, 0)
	return map
end

local function CreateBossDetails(parent)
	local details = CreateFrame("Frame", nil, parent)
	details:SetAllPoints()
	local back = PanelButton(details, 123, L.JOURNAL_BOSSES_BACK, function()
		GameTooltip:Hide()
		selectedBoss = nil
		Render(true)
	end)
	back:SetPoint("TOPLEFT", 9, -8)
	details.mapButton = PanelButton(details, 132, L.JOURNAL_BOSS_SHOW_MAP, function()
		local entry = data[selection]
		selectedTab, mapPage = "map", BossPage(entry, bossData[entry.bosses[selectedBoss][1]])
		ResetMapView(frame.mapImage)
		Render(true)
	end)
	details.mapButton:SetPoint("TOPRIGHT", -9, -8)
	details.lootButton = PanelButton(details, 123, L.JOURNAL_LOOT, function()
		GameTooltip:Hide()
		selectedTab, lootBoss = "loot", selectedBoss
		Render(true)
	end)
	details.lootButton:SetPoint("RIGHT", details.mapButton, "LEFT", -6, 0)
	details.title = Label(details, "GameFontNormalLarge", "TOPLEFT", 12, -44)
	details.order = Label(details, "GameFontHighlightSmall", "TOPLEFT", 12, -70)
	details.note = Label(details, "GameFontHighlight", "TOPLEFT", 12, -96)
	details.note:SetWidth(DETAIL_WIDTH - 24)
	details.note:SetWordWrap(true)
	details.heading = Label(details, "GameFontNormal", "TOPLEFT", 12, -124, L.JOURNAL_ABILITIES)
	details.spells = List(details, DETAIL_WIDTH - 33, 222)
	details.spells:SetPoint("TOPLEFT", details.heading, "BOTTOMLEFT", -4, -7)
	details.empty = Label(details, "GameFontDisable", "TOPLEFT", 0, 0, L.JOURNAL_NO_ABILITIES)
	details.empty:ClearAllPoints()
	details.empty:SetPoint("TOPLEFT", details.heading, "BOTTOMLEFT", 0, -10)
	details.source = Label(details, "GameFontHighlightSmall", "TOPLEFT", 12, -379)
	details.source:SetWidth(DETAIL_WIDTH - 24)
	details.source:SetWordWrap(true)
	return details
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
			selectedTab, lootBoss = key, nil
			if key == "bosses" then selectedBoss = nil end
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
	panel.bossDetails = CreateBossDetails(detail)
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
	panel.upgradesOnly = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
	panel.upgradesOnly:SetPoint("TOPLEFT", DETAIL_WIDTH - 185, -5)
	panel.upgradesOnly:SetSize(26, 26)
	panel.upgradesOnly.Text:SetText(L.JOURNAL_UPGRADES_ONLY)
	panel.upgradesOnly:SetHitRectInsets(0, -panel.upgradesOnly.Text:GetStringWidth(), 0, 0)
	panel.upgradesOnly:SetChecked(Journal.db.lootUpgradesOnly)
	panel.upgradesOnly:SetScript("OnClick", ns.Measured("DungeonJournal: upgrades filter", function(button)
		Journal.db.lootUpgradesOnly = button:GetChecked() and true or false
		Render(true)
	end))
	panel.upgradesOnly:SetScript("OnEnter", ns.Measured("DungeonJournal: upgrades filter tooltip", function(button)
		Tooltip(button, L.JOURNAL_UPGRADES_ONLY, L.JOURNAL_UPGRADES_ONLY_DESC)
		GameTooltip:Show()
	end))
	panel.upgradesOnly:SetScript("OnLeave", GameTooltip_Hide)
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
		lootIndex = nil
		Journal:UnregisterEvent("QUEST_LOG_UPDATE")
		Journal:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
		Journal:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
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
		Journal:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, _, itemID, success)
			if ns.Number(itemID) and requestedItems[itemID] and not ns.Secret(success) and success then RefreshLoot() end
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
	if frame and frame:IsShown() then
		if self.db.enabled then Render(false) else frame:Hide() end
	end
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
	{ key = "mapZoom", type = "toggle", name = L.JOURNAL_ZOOM_OPTION, parent = "enabled", new = true },
	{ key = "bossDetails", type = "toggle", name = L.JOURNAL_BOSS_OPTION, parent = "enabled", new = true },
	{ key = "bossLoot", type = "toggle", name = L.JOURNAL_LOOT_OPTION, desc = L.JOURNAL_LOOT_OPTION_DESC, parent = "enabled" },
	{ type = "button", name = L.JOURNAL_TITLE, text = L.JOURNAL_OPEN, func = function() Journal.Open() end },
}

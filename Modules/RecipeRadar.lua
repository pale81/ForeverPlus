-- Recipe radar: vendors selling recipes the player does not know yet, shown on
-- the world map and/or minimap; clicking sets a waypoint. Recipe items also get
-- their sources (vendors, quests, drops) in the tooltip.
--
-- Vendors and recipes come from the bundled Forever data (Data/Radar.lua,
-- generated from AllTheThings, MIT); QuestieDB, when installed, adds what it
-- knows beyond that (quest rewards, more vendors, localised NPC names).
local _, ns = ...
local L = ns.L

local Radar = ns:NewModule("RecipeRadar", {
	title = L.RADAR_TITLE,
	order = 10,
	defaults = {
		enabled = true,
		worldMap = true,
		minimap = true,
		showLowSkill = true,
		tooltipSources = true,
		waypointMessage = true,
	},
})

-- Repositioning every 50 ms repeatedly calls map APIs and resets each pin's
-- anchors. Ten updates per second remain smooth on the minimap and halve the
-- work while moving or turning.
local MINIMAP_UPDATE_INTERVAL = 0.1
local RECIPE_CLASS = 9           -- Enum.ItemClass.Recipe
local TOOLTIP_MAX_VENDORS = 3
local TOOLTIP_MAX_QUESTS = 2

-- Recipe item subclass -> profession skill line.
local RECIPE_SKILL = {
	[1] = 165, -- Leatherworking
	[2] = 197, -- Tailoring
	[3] = 202, -- Engineering
	[4] = 164, -- Blacksmithing
	[5] = 185, -- Cooking
	[6] = 171, -- Alchemy
	[7] = 129, -- First Aid
	[8] = 333, -- Enchanting
	[9] = 356, -- Fishing
	[10] = 755, -- Jewelcrafting
}

local DB                -- LibQuestieDB (optional)
local bundled           -- ns.RadarData
local bundledVendors = {} -- npcID -> { name =, title =, team =, maps = { uiMapID, … } }
Radar.bundledVendors = bundledVendors
local recipes = {}      -- itemID -> { skill =, vendors =, drops =, quests = }
local vendorsByMap = {} -- uiMapID -> { { npc =, team =, x =, y =, items = {} }, ... }
local indexReady = false
local skills = {}       -- skillLineID -> current rank
local statusCache = {}  -- itemID -> "known" | "ok" | "low"
local playerTeam
local waitingForItems = false

---------------------------------------------------------------------------
-- QuestieDB index (built once per session, spread over frames)
---------------------------------------------------------------------------
-- Summoned helpers that sell (Forever's Reagent Bot) are recorded wherever
-- players called them; an NPC seen in more zones than this has no fixed place.
local MAX_VENDOR_ZONES = 3
local mobile = {} -- npcID -> true

local function NpcName(npc)
	local vendor = bundledVendors[npc]
	return vendor and vendor.name or DB and DB.Npc.Get(npc, "name")
end

local function NpcTitle(npc)
	local vendor = bundledVendors[npc]
	if vendor then
		return vendor.title
	end
	return DB and DB.Npc.Get(npc, "subName")
end

-- "A", "H" or "N" (both), nil without a fixed place.
local function NpcTeam(npc)
	local vendor = bundledVendors[npc]
	if vendor then
		return vendor.team
	end
	if mobile[npc] or not DB then
		return nil
	end
	local faction = DB.Npc.Get(npc, "friendlyToFaction")
	return faction == "AH" and "N" or faction
end

local function AddVendorPoint(uiMapID, npc, team, x, y, items)
	local list = vendorsByMap[uiMapID]
	if not list then
		list = {}
		vendorsByMap[uiMapID] = list
	end
	list[#list + 1] = { npc = npc, team = team, x = x, y = y, items = items }
end

local function AddVendorSpawns(npc, items)
	local spawns = DB.Npc.Get(npc, "spawns")
	local faction = DB.Npc.Get(npc, "friendlyToFaction")
	if not spawns or not faction then
		return -- hostile to both factions or no known position
	end
	local zones = 0
	for _ in pairs(spawns) do
		zones = zones + 1
	end
	if zones > MAX_VENDOR_ZONES then
		mobile[npc] = true
		return
	end
	local team = faction == "AH" and "N" or faction
	for areaID, points in pairs(spawns) do
		local uiMapID = ns.QuestieDB.UiMapForArea(DB, areaID)
		local point = points[1]
		if uiMapID and point and point[1] and point[1] >= 0 then
			AddVendorPoint(uiMapID, npc, team, point[1], point[2], items)
		end
	end
end

local indexError -- first error while indexing, for /fp radar

-- Recipe item subclass -> profession skill line of an item the client knows.
local function RecipeSkill(itemID)
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	return classID == RECIPE_CLASS and RECIPE_SKILL[subClassID] or nil
end

-- The bundled data: small enough to index at once.
local function IndexBundled()
	for npc, row in pairs(bundled.vendors) do
		local items = {}
		for _, itemID in ipairs(row[5]) do
			local skill = recipes[itemID] and recipes[itemID].skill or RecipeSkill(itemID)
			if skill then
				recipes[itemID] = recipes[itemID] or { skill = skill, vendors = {}, dropCount = bundled.drops[itemID] }
				tinsert(recipes[itemID].vendors, npc)
				items[#items + 1] = itemID
			end
		end
		if #items > 0 then
			local maps = {}
			for _, point in ipairs(row[4]) do
				AddVendorPoint(point[1], npc, row[3], point[2], point[3], items)
				maps[#maps + 1] = point[1]
			end
			bundledVendors[npc] = { name = row[1], title = row[2] or nil, team = row[3], maps = maps, items = items }
		end
	end
end

local function BuildQuestieIndex(onDone)
	local ids = DB.Item.GetAllIds() or {}
	local npcItems = {}
	local function IndexItem(id)
		if DB.Item.Get(id, "class") == RECIPE_CLASS then
			local skill = RECIPE_SKILL[DB.Item.Get(id, "subClass")]
			if skill then
				local vendors = DB.Item.Get(id, "vendors")
				local recipe = recipes[id]
				if not recipe then
					recipe = { skill = skill, vendors = {} }
					recipes[id] = recipe
				end
				recipe.drops = DB.Item.Get(id, "npcDrops")
				recipe.quests = DB.Item.Get(id, "questRewards")
				for _, npc in ipairs(vendors or {}) do
					local known = bundledVendors[npc]
					if known then
						-- Positions come from the bundled data; add what only QuestieDB lists.
						local listed
						for _, item in ipairs(known.items) do
							listed = listed or item == id
						end
						if not listed then
							tinsert(known.items, id)
							tinsert(recipe.vendors, npc)
						end
					else
						tinsert(recipe.vendors, npc)
						npcItems[npc] = npcItems[npc] or {}
						tinsert(npcItems[npc], id)
					end
				end
			end
		end
	end
	-- One faulty entry must not stop the index.
	ns.RunSliced("RecipeRadar: recipes", #ids, function(i)
		local ok, message = pcall(IndexItem, ids[i])
		if not ok and not indexError then
			indexError = tostring(message)
		end
	end, function()
		local npcs = {}
		for npc in pairs(npcItems) do
			npcs[#npcs + 1] = npc
		end
		ns.RunSliced("RecipeRadar: vendors", #npcs, function(i)
			local ok, message = pcall(AddVendorSpawns, npcs[i], npcItems[npcs[i]])
			if not ok and not indexError then
				indexError = tostring(message)
			end
		end, onDone)
	end)
end

local function BuildIndex(onDone)
	if bundled then
		local ok, message = pcall(IndexBundled)
		if not ok then
			indexError = tostring(message)
		end
	end
	if DB then
		BuildQuestieIndex(function()
			indexReady = true
			onDone()
		end)
	else
		indexReady = true
		onDone()
	end
end

---------------------------------------------------------------------------
-- Player state
---------------------------------------------------------------------------
local function UpdateSkills()
	wipe(skills)
	wipe(statusCache)
	for _, index in pairs({ GetProfessions() }) do
		if index then
			local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				skills[skillLine] = rank or 0
			end
		end
	end
end

local failedItems = {} -- items the client could not load (not in this client's data): never wait for them

-- Item data arrives later: scan again then.
local function OnItemInfo(_, _, itemID, success)
	if success == false and itemID then
		failedItems[itemID] = true
	end
	wipe(statusCache)
	Radar:RequestRefresh()
end

local function IsRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

-- Reads "already known" and "skill too low" from the item's tooltip data.
local function ScanRecipe(itemID)
	if failedItems[itemID] then
		return nil
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		waitingForItems = true
		return nil
	end
	local status = "ok"
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	for _, line in ipairs(tooltip and tooltip.lines or {}) do
		if line.type == Enum.TooltipDataLineType.UsageRequirement then
			if line.requirementType == Enum.TooltipDataUsageRequirementType.NotAlreadyKnown then
				return "known"
			elseif line.requirementType == Enum.TooltipDataUsageRequirementType.Skill and IsRed(line.leftColor) then
				status = "low"
			end
		elseif line.leftText == ITEM_SPELL_KNOWN then
			return "known"
		end
	end
	return status
end

-- Returns "ok" (learnable now), "low" (skill too low) or nil (irrelevant / known).
local function RecipeStatus(itemID)
	local recipe = recipes[itemID]
	if not recipe or not skills[recipe.skill] then
		return nil
	end
	local status = statusCache[itemID]
	if not status then
		status = ScanRecipe(itemID)
		statusCache[itemID] = status
	end
	if status == "ok" or (status == "low" and Radar.db.showLowSkill) then
		return status
	end
end

local function GetVendors(mapID)
	local list = indexReady and mapID and vendorsByMap[mapID]
	if not list then
		return nil
	end
	local result
	for _, vendor in ipairs(list) do
		if vendor.team == "N" or vendor.team == playerTeam then
			local open
			for _, itemID in ipairs(vendor.items) do
				local status = RecipeStatus(itemID)
				if status then
					open = open or {}
					open[#open + 1] = { itemID, status }
				end
			end
			if open then
				result = result or {}
				result[#result + 1] = { vendor = vendor, recipes = open }
			end
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Shared pin behaviour (tooltip, waypoint)
---------------------------------------------------------------------------
local function FillVendorTooltip(tooltip, entry)
	local vendor = entry.vendor
	GameTooltip_SetTitle(tooltip, NpcName(vendor.npc) or "?")
	local subName = NpcTitle(vendor.npc)
	if subName then
		GameTooltip_AddNormalLine(tooltip, subName)
	end
	GameTooltip_AddNormalLine(tooltip, ("%.1f, %.1f"):format(vendor.x, vendor.y))
	for _, recipe in ipairs(entry.recipes) do
		local itemID, status = recipe[1], recipe[2]
		local name = C_Item.GetItemNameByID(itemID) or DB and DB.Item.Get(itemID, "name") or ("item:" .. itemID)
		local color = status == "ok" and GREEN_FONT_COLOR or ORANGE_FONT_COLOR
		tooltip:AddLine(name, color.r, color.g, color.b)
	end
	GameTooltip_AddInstructionLine(tooltip, L.RADAR_CLICK_WAYPOINT)
end

local function ShowVendorTooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	FillVendorTooltip(GameTooltip, entry)
	GameTooltip:Show()
end

local function SetWaypoint(mapID, vendor)
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, vendor.x / 100, vendor.y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	if Radar.db.waypointMessage then
		ns.Print(L.RADAR_WAYPOINT_SET, NpcName(vendor.npc) or "?")
	end
end

local function PinIcon(entry)
	return C_Item.GetItemIconByID(entry.recipes[1][1]) or 134939
end

---------------------------------------------------------------------------
-- Recipe sources in item tooltips
---------------------------------------------------------------------------
local function ZoneName(npc)
	local vendor = bundledVendors[npc]
	if vendor then
		local info = C_Map.GetMapInfo(vendor.maps[1])
		return info and info.name or ""
	end
	local spawns = DB and DB.Npc.Get(npc, "spawns")
	for areaID in pairs(spawns or {}) do
		local uiMapID = ns.QuestieDB.UiMapForArea(DB, areaID)
		local info = uiMapID and C_Map.GetMapInfo(uiMapID)
		if info then
			return info.name
		end
	end
	return ""
end

-- A section of the extra block of item tooltips.
ns.AddItemSection(30, function(data)
	if not (indexReady and Radar.db.enabled and Radar.db.tooltipSources) then
		return
	end
	local recipe = data and data.id and recipes[data.id]
	if not recipe then
		return
	end
	local gold = { 1, 0.82, 0 }
	local lines, shown = {}, 0
	for _, npc in ipairs(recipe.vendors or {}) do
		local team = NpcTeam(npc)
		if team and (team == "N" or team == playerTeam) then
			shown = shown + 1
			if shown > TOOLTIP_MAX_VENDORS then
				lines[#lines + 1] = { left = L.RADAR_MORE_VENDORS, lc = { 0.7, 0.7, 0.7 } }
				break
			end
			lines[#lines + 1] = { left = L.RADAR_SOURCE_VENDOR:format(NpcName(npc) or "?"), right = ZoneName(npc), lc = gold }
		end
	end
	for i, questID in ipairs(recipe.quests or {}) do
		if i > TOOLTIP_MAX_QUESTS then
			break
		end
		lines[#lines + 1] = { left = L.RADAR_SOURCE_QUEST:format(ns.QuestieDB.QuestName(DB, questID) or questID), lc = gold }
	end
	local drops = recipe.dropCount or recipe.drops and #recipe.drops
	if drops and drops > 0 then
		lines[#lines + 1] = { left = L.RADAR_SOURCE_DROP:format(drops), lc = gold }
	end
	return lines
end)

---------------------------------------------------------------------------
-- World map (symbols on ForeverPlus' own map layer, Modules/MapSymbols.lua)
---------------------------------------------------------------------------
local WORLD_MAP_PIN_SIZE = 20

local function WorldMapTooltip(tooltip, symbol)
	FillVendorTooltip(tooltip, symbol.data)
end

local function WorldMapClick(symbol, button)
	if button == "LeftButton" then
		SetWaypoint(symbol.mapID, symbol.data.vendor)
	end
end

ns.MapSymbols.AddSource(function(mapID, add)
	local db = Radar.db
	if not (db and db.enabled and db.worldMap) then
		return
	end
	for _, entry in ipairs(GetVendors(mapID) or {}) do
		add(entry.vendor.x / 100, entry.vendor.y / 100, { kind = "radar", texture = PinIcon(entry), size = WORLD_MAP_PIN_SIZE,
			round = true, data = entry, mapID = mapID, tooltip = WorldMapTooltip, click = WorldMapClick })
	end
	-- Browsing to another zone can find recipes whose data is not loaded yet.
	if waitingForItems then
		Radar:ToggleEvent("GET_ITEM_INFO_RECEIVED", true, OnItemInfo)
	end
end)

local function RefreshWorldMap()
	ns.MapSymbols.Refresh()
end


---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local minimapPins = {}
local activePins = {}
local minimapHolder
local currentMapID
local currentMapWidth, currentMapHeight, minimapRadius

local function CreateMinimapPin(index)
	local pin = CreateFrame("Button", nil, minimapHolder)
	pin:SetSize(14, 14)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetAllPoints()
	local mask = pin:CreateMaskTexture()
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints()
	pin.Icon:AddMaskTexture(mask)
	pin:SetScript("OnEnter", function(self)
		ShowVendorTooltip(self, self.entry)
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", function(self)
		SetWaypoint(currentMapID, self.entry.vendor)
	end)
	minimapPins[index] = pin
	return pin
end

local function PositionMinimapPins()
	if #activePins == 0 then
		return
	end
	local position = currentMapID and C_Map.GetPlayerMapPosition(currentMapID, "player")
	local width, height = currentMapWidth, currentMapHeight
	local radius = minimapRadius
	if not position or not width or width == 0 or not height or height == 0 or not radius or radius == 0 then
		for _, pin in ipairs(activePins) do
			pin:Hide()
		end
		return
	end
	local px, py = position:GetXY()
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local facing = GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
	local sin, cos = math.sin(facing), math.cos(facing)

	for _, pin in ipairs(activePins) do
		local vendor = pin.entry.vendor
		-- Yards in screen orientation (x east, y north).
		local sx = (vendor.x / 100 - px) * width
		local sy = (py - vendor.y / 100) * height
		if facing ~= 0 then
			sx, sy = sx * cos + sy * sin, -sx * sin + sy * cos
		end
		local distance = math.sqrt(sx * sx + sy * sy)
		local onEdge = distance > radius
		if onEdge then
			sx, sy = sx * radius / distance, sy * radius / distance
		end
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", Minimap, "CENTER", sx / radius * halfWidth, sy / radius * halfHeight)
		pin:SetAlpha(onEdge and 0.6 or 1)
		pin:Show()
	end
end

local moving, turning = false, false
local elapsedSinceUpdate = 0

local function UpdateMinimapDriver()
	minimapHolder:SetScript("OnUpdate", (#activePins > 0 and (moving or turning)) and function(_, elapsed)
		elapsedSinceUpdate = elapsedSinceUpdate + elapsed
		if elapsedSinceUpdate >= MINIMAP_UPDATE_INTERVAL then
			elapsedSinceUpdate = 0
			PositionMinimapPins()
		end
	end or nil)
end

local function RefreshMinimap()
	wipe(activePins)
	for _, pin in ipairs(minimapPins) do
		pin:Hide()
	end
	local db = Radar.db
	currentMapID = C_Map.GetBestMapForUnit("player")
	if currentMapID then
		currentMapWidth, currentMapHeight = C_Map.GetMapWorldSize(currentMapID)
	else
		currentMapWidth, currentMapHeight = nil, nil
	end
	minimapRadius = C_Minimap.GetViewRadius()
	if db.enabled and db.minimap and currentMapID then
		for index, entry in ipairs(GetVendors(currentMapID) or {}) do
			local pin = minimapPins[index] or CreateMinimapPin(index)
			pin.entry = entry
			pin:SetScale(ns.MinimapSymbolScale and ns.MinimapSymbolScale() or 1)
			pin.Icon:SetTexture(PinIcon(entry))
			activePins[index] = pin
		end
	end
	PositionMinimapPins()
	UpdateMinimapDriver()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local refreshPending = false

local function Refresh()
	refreshPending = false
	waitingForItems = false
	RefreshMinimap()
	RefreshWorldMap()
	Radar:ToggleEvent("GET_ITEM_INFO_RECEIVED", waitingForItems, OnItemInfo)
end

function Radar:RequestRefresh()
	if not refreshPending then
		refreshPending = true
		C_Timer.After(0.5, Refresh)
	end
end

local function OnSkillsChanged()
	UpdateSkills()
	Radar:RequestRefresh()
end

local function SetMoving(_, event)
	if event == "PLAYER_STARTED_MOVING" then
		moving = true
	elseif event == "PLAYER_STOPPED_MOVING" then
		moving = false
	elseif event == "PLAYER_STARTED_TURNING" then
		turning = GetCVarBool("rotateMinimap")
	elseif event == "PLAYER_STOPPED_TURNING" then
		turning = false
	end
	UpdateMinimapDriver()
	PositionMinimapPins()
end

function Radar:Apply()
	local enabled = self.db.enabled and DB ~= nil
	local events = {
		ZONE_CHANGED_NEW_AREA = Radar.RequestRefresh,
		ZONE_CHANGED = Radar.RequestRefresh,
		ZONE_CHANGED_INDOORS = Radar.RequestRefresh,
		PLAYER_ENTERING_WORLD = Radar.RequestRefresh,
		SKILL_LINES_CHANGED = OnSkillsChanged,
		NEW_RECIPE_LEARNED = OnSkillsChanged,
		LEARNED_SPELL_IN_SKILL_LINE = OnSkillsChanged,
		PLAYER_STARTED_MOVING = SetMoving,
		PLAYER_STOPPED_MOVING = SetMoving,
		PLAYER_STARTED_TURNING = SetMoving,
		PLAYER_STOPPED_TURNING = SetMoving,
		MINIMAP_UPDATE_ZOOM = function()
			minimapRadius = C_Minimap.GetViewRadius()
			PositionMinimapPins()
		end,
	}
	for event, handler in pairs(events) do
		self:ToggleEvent(event, enabled, handler)
	end
	if enabled then
		UpdateSkills() -- a skill event before the registration above is lost
	end
	if enabled and not indexReady and not self.indexing then
		self.indexing = true
		BuildIndex(Refresh)
	end
	Refresh()
end

-- The quest data library with the entity reads used here.
local function FindQuestieDB()
	local lib = ns.QuestieDB.Get()
	if lib and type(lib.Item) == "table" and type(lib.Item.Get) == "function"
		and type(lib.Npc) == "table" and type(lib.Npc.Get) == "function" then
		return lib
	end
end

local started

local function Start()
	if started then
		return true
	end
	DB = FindQuestieDB()
	bundled = ns.RadarData
	if not (DB or bundled) then
		return false
	end
	started = true
	UpdateSkills()
	ns.OnAddOnLoaded("Blizzard_WorldMap", ns.MapSymbols.Setup)
	-- Index after the login burst; it only runs while the radar is enabled.
	C_Timer.After(5, function()
		Radar:Apply()
	end)
	return true
end

-- Recipe vendors in the filter menu of the world map.
ns.AddMapFilterEntry(function(root)
	local radar = root:CreateCheckbox(L.RADAR_TITLE, function()
		return Radar.db.enabled and Radar.db.worldMap
	end, function()
		local on = not (Radar.db.enabled and Radar.db.worldMap)
		if on then
			ns.SetOption("RecipeRadar", "enabled", true)
		end
		ns.SetOption("RecipeRadar", "worldMap", on)
	end)
	ns.CreateOptionCheckbox(radar, L.RADAR_MINIMAP, "RecipeRadar", "minimap")
	ns.CreateOptionCheckbox(radar, L.RADAR_LOW_SKILL, "RecipeRadar", "showLowSkill", L.RADAR_LOW_SKILL_DESC)
	ns.CreateOptionCheckbox(radar, L.RADAR_TOOLTIP, "RecipeRadar", "tooltipSources", L.RADAR_TOOLTIP_DESC)
end)

function Radar:OnLogin()
	-- Recipe vendors in the minimap tracking menu.
	ns.AddTrackingEntry(function(root)
		root:CreateCheckbox(L.RADAR_TRACKING, function()
			return Radar.db.enabled and Radar.db.minimap
		end, function()
			local on = not (Radar.db.enabled and Radar.db.minimap)
			if on then
				ns.SetOption("RecipeRadar", "enabled", true)
			end
			ns.SetOption("RecipeRadar", "minimap", on)
		end)
	end)
	playerTeam = UnitFactionGroup("player") == "Horde" and "H" or "A"
	minimapHolder = CreateFrame("Frame", nil, Minimap)
	minimapHolder:SetAllPoints()
	minimapHolder:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	Start()
	-- QuestieDB may still be loading at login: add it a little later.
	if not DB then
		C_Timer.After(10, function()
			DB = FindQuestieDB()
			if DB and indexReady then
				BuildQuestieIndex(Refresh)
			end
		end)
	end
end

-- /fp radar: state of the radar for troubleshooting.
function Radar:PrintStatus()
	if not (DB or bundled) then
		ns.PrintAlways(L.RADAR_STATUS_NO_DB)
		return
	end
	local recipeCount, vendorCount = 0, 0
	for _ in pairs(recipes) do
		recipeCount = recipeCount + 1
	end
	for _, list in pairs(vendorsByMap) do
		vendorCount = vendorCount + #list
	end
	ns.PrintAlways(L.RADAR_STATUS_INDEX, indexReady and L.RADAR_STATUS_READY or L.RADAR_STATUS_BUILDING, recipeCount, vendorCount)
	if indexError then
		ns.PrintAlways(L.RADAR_STATUS_ERROR, indexError)
	end
	local professions = {}
	for skillLine, rank in pairs(skills) do
		professions[#professions + 1] = ("%d (%d)"):format(skillLine, rank)
	end
	ns.PrintAlways(L.RADAR_STATUS_SKILLS, #professions > 0 and table.concat(professions, ", ") or "-")
	local mapID = C_Map.GetBestMapForUnit("player")
	local all = mapID and vendorsByMap[mapID]
	ns.PrintAlways(L.RADAR_STATUS_MAP, mapID or 0, all and #all or 0, #(GetVendors(mapID) or {}))
	-- Why recipes of the vendors here are shown or not.
	local counts = { ok = 0, low = 0, known = 0, other = 0, loading = 0, foreign = 0 }
	for _, vendor in ipairs(all or {}) do
		local own = vendor.team == "N" or vendor.team == playerTeam
		for _, itemID in ipairs(vendor.items) do
			local status
			if not own then
				status = "foreign"
			elseif not skills[recipes[itemID].skill] then
				status = "other"
			else
				status = statusCache[itemID] or ScanRecipe(itemID)
				statusCache[itemID] = status
			end
			status = status or "loading"
			counts[status] = counts[status] + 1
		end
	end
	ns.PrintAlways(L.RADAR_STATUS_RECIPES, counts.ok, counts.low, counts.known, counts.other, counts.loading, counts.foreign)
	local db = self.db
	ns.PrintAlways(L.RADAR_STATUS_OPTIONS, db.enabled and YES or NO, db.worldMap and YES or NO, db.minimap and YES or NO, db.showLowSkill and YES or NO)
end

function Radar:OnOptionChanged()
	if started then
		self:Apply()
	end
end

Radar.options = {
	{ type = "header", name = L.RADAR_TITLE },
	{ key = "enabled", type = "toggle", name = L.RADAR_ENABLE, desc = L.RADAR_ENABLE_DESC },
	{ key = "worldMap", type = "toggle", name = L.RADAR_WORLDMAP, parent = "enabled" },
	{ key = "minimap", type = "toggle", name = L.RADAR_MINIMAP, parent = "enabled" },
	{ key = "showLowSkill", type = "toggle", name = L.RADAR_LOW_SKILL, desc = L.RADAR_LOW_SKILL_DESC, parent = "enabled" },
	{ key = "tooltipSources", type = "toggle", name = L.RADAR_TOOLTIP, desc = L.RADAR_TOOLTIP_DESC, parent = "enabled" },
	{ key = "waypointMessage", type = "toggle", name = L.RADAR_WAYPOINT_MESSAGE, desc = L.MESSAGE_DESC, parent = "enabled" },
}

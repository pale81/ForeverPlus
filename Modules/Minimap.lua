-- Minimap: player coordinates below the north marker. Updates only while the
-- player (or a taxi) is moving. World map: Blizzard's coordinates movable.
local _, ns = ...
local L = ns.L

local MinimapCoords = ns:NewModule("Minimap", {
	title = L.MINIMAP_TITLE,
	order = 3,
	defaults = {
		worldMapCoords = true,
		wholeCoords = false, -- coordinates without the decimal place
		trackingIcons = true,
		trackingEntries = true,
		emitterSoundMenu = true,
		nearbyEmitters = true,
		emitterSoundKind = "all",
		emitterSoundCategory = "all",
		emitterSoundRadius = 0,
		mutedEmitters = {},
		campfires = false,
		symbolScale = 100,
		zoomReset = true,
		zoomDelay = 10,
		restoreMailIcon = true,
	},
})

-- WoW Forever reports campfire placement through its item-effect spell casts,
-- but does not expose a list of nearby world objects to addons. Track exact
-- positions when the player or a group member places one.
local CAMPFIRE_SPELLS = {
	[1307227] = 15 * 60, -- Basic Campfire
	[1307252] = 15 * 60, -- Journeyman Campfire
	[1307237] = 15 * 60, -- Expert Campfire
}
ns.CAMPFIRE_SPELLS = CAMPFIRE_SPELLS
local campfires, campfireHolder = {}, nil
local campfireTicker, campfireTickerInterval, campfireMoving = nil, nil, false
local mapWorldSizeCache = {}
local CAMPFIRE_ICON = [[Interface\Icons\INV_Misc_BBQFire_01]]
local CAMPFIRE_MOVE_INTERVAL = 0.25
local CAMPFIRE_IDLE_INTERVAL = 1.0

local function MapWorldSize(mapID)
	if not (mapID and C_Map and C_Map.GetMapWorldSize) then
		return 0, 0
	end
	local cached = mapWorldSizeCache[mapID]
	if cached then
		return cached[1], cached[2]
	end
	local width, height = C_Map.GetMapWorldSize(mapID)
	width, height = ns.Number(width, 0), ns.Number(height, 0)
	if width > 0 and height > 0 then
		mapWorldSizeCache[mapID] = { width, height }
	end
	return width, height
end

function ns.HasTrackedCampfires()
	return #campfires > 0
end

-- Read-only distance check for modules such as WorldReactions: true when any tracked campfire
-- on the player's current map is within maxDistance yards.
function ns.HasCampfireNearPlayer(maxDistance)
	if #campfires == 0 then
		return false
	end
	local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local position = currentMapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(currentMapID, "player")
	if not position then
		return false
	end
	local width, height = MapWorldSize(currentMapID)
	if width <= 0 or height <= 0 then
		return false
	end
	local px, py = position:GetXY()
	px, py = ns.Number(px), ns.Number(py)
	if not (px and py) then
		return false
	end
	local limitSq = (maxDistance or 14) * (maxDistance or 14)
	local now = ns.Number(GetTime(), 0)
	for _, fire in ipairs(campfires) do
		if fire.expires > now and fire.mapID == currentMapID then
			local dx = (fire.x - px) * width
			local dy = (py - fire.y) * height
			if dx * dx + dy * dy <= limitSq then
				return true
			end
		end
	end
	return false
end

-- Symbol size from the options (percent); 1 is the size the symbols were
-- designed at. RecipeRadar reads it the same way for its pins.
local function SymbolScale()
	return (MinimapCoords.db.symbolScale or 100) / 100
end


function ns.MinimapSymbolScale()
	return SymbolScale()
end

local function IsGroupUnit(unit)
	if type(unit) ~= "string" or ns.Secret(unit) then
		return false
	end
	return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local function AddCampfire(unit, duration)
	local mapID = C_Map.GetBestMapForUnit(unit)
	local playerMapID = C_Map.GetBestMapForUnit("player")
	if not mapID or mapID ~= playerMapID then
		return
	end
	local position = C_Map.GetPlayerMapPosition(mapID, unit)
	if not position then
		return
	end
	local x, y = position:GetXY()
	local name, realm = UnitName(unit)
	local fire = {
		mapID = mapID,
		x = x,
		y = y,
		owner = realm and realm ~= "" and (name .. " - " .. realm) or name,
		expires = GetTime() + duration,
	}
	local pin = CreateFrame("Button", nil, campfireHolder)
	pin:SetSize(26, 28)
	pin:SetScale(SymbolScale())
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetSize(18, 18)
	pin.Icon:SetPoint("TOP", pin, "TOP")
	pin.Icon:SetTexture(CAMPFIRE_ICON)
	pin.Timer = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pin.Timer:SetPoint("TOP", pin.Icon, "BOTTOM", 0, 1)
	pin.Timer:SetJustifyH("CENTER")
	pin.Timer:SetTextColor(1, 0.85, 0.3)
	pin.Timer:SetShadowOffset(1, -1)
	pin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_CAMPFIRE)
		GameTooltip:AddLine(L.MINIMAP_CAMPFIRE_OWNER:format(fire.owner), 1, 1, 1)
		GameTooltip:AddLine(L.MINIMAP_CAMPFIRE_REMAINING:format(pin.Timer:GetText()), 1, 0.85, 0.3)
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	fire.pin = pin
	campfires[#campfires + 1] = fire
	return fire
end

local function FormatRemaining(seconds)
	return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

local PositionCampfires

local function SyncCampfireTicker(rotateMinimap)
	if not campfireHolder or not MinimapCoords.db.campfires or #campfires == 0 then
		if campfireTicker then
			campfireTicker:Cancel()
			campfireTicker = nil
			campfireTickerInterval = nil
		end
		return
	end
	local interval = (campfireMoving or rotateMinimap) and CAMPFIRE_MOVE_INTERVAL or CAMPFIRE_IDLE_INTERVAL
	if campfireTicker and campfireTickerInterval == interval then
		return
	end
	if campfireTicker then
		campfireTicker:Cancel()
	end
	campfireTickerInterval = interval
	campfireTicker = ns.NewTicker("Minimap: campfire update", interval, PositionCampfires)
end

PositionCampfires = function()
	if not campfireHolder or not MinimapCoords.db.campfires then
		SyncCampfireTicker(false)
		for _, fire in ipairs(campfires) do
			if fire.shown ~= false then
				fire.shown = false
				fire.pin:Hide()
			end
		end
		return
	end
	if #campfires == 0 then
		SyncCampfireTicker(false)
		return
	end
	local currentMapID = C_Map.GetBestMapForUnit("player")
	local position = currentMapID and C_Map.GetPlayerMapPosition(currentMapID, "player")
	local width, height = MapWorldSize(currentMapID)
	local radius = C_Minimap.GetViewRadius()
	local rotateMinimap = GetCVarBool("rotateMinimap")
	if not position or width <= 0 or height <= 0 or not radius or radius == 0 then
		for _, fire in ipairs(campfires) do
			if fire.shown ~= false then
				fire.shown = false
				fire.pin:Hide()
			end
		end
		SyncCampfireTicker(rotateMinimap)
		return
	end
	local px, py = position:GetXY()
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local facing = rotateMinimap and (GetPlayerFacing() or 0) or 0
	local sin, cos = math.sin(facing), math.cos(facing)
	local now = GetTime()
	for index = #campfires, 1, -1 do
		local fire = campfires[index]
		if fire.expires <= now then
			fire.shown = false
			fire.pin:Hide()
			table.remove(campfires, index)
		elseif fire.mapID == currentMapID then
			local sx = (fire.x - px) * width
			local sy = (py - fire.y) * height
			if facing ~= 0 then
				sx, sy = sx * cos + sy * sin, -sx * sin + sy * cos
			end
			local distance = math.sqrt(sx * sx + sy * sy)
			local onEdge = distance > radius
			if onEdge then
				sx, sy = sx * radius / distance, sy * radius / distance
			end
			local pinX = sx / radius * halfWidth
			local pinY = sy / radius * halfHeight
			if not fire.lastX or math.abs(pinX - fire.lastX) >= 0.25 or math.abs(pinY - fire.lastY) >= 0.25 then
				fire.lastX, fire.lastY = pinX, pinY
				fire.pin:SetPoint("CENTER", Minimap, "CENTER", pinX, pinY)
			end
			local alpha = onEdge and 0.6 or 1
			if fire.lastAlpha ~= alpha then
				fire.lastAlpha = alpha
				fire.pin:SetAlpha(alpha)
			end
			local remaining = math.max(0, math.ceil(fire.expires - now))
			if fire.lastRemaining ~= remaining then
				fire.lastRemaining = remaining
				fire.pin.Timer:SetText(FormatRemaining(remaining))
			end
			if not fire.shown then
				fire.shown = true
				fire.pin:Show()
			end
		elseif fire.shown ~= false then
			fire.shown = false
			fire.pin:Hide()
		end
	end
	SyncCampfireTicker(rotateMinimap)
end

function MinimapCoords:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
	if type(spellID) ~= "number" or ns.Secret(spellID) then
		return
	end
	local duration = CAMPFIRE_SPELLS[spellID]
	if not self.db.campfires or not IsGroupUnit(unit) or not duration then
		return
	end
	AddCampfire(unit, duration)
	PositionCampfires()
end

-- Coordinates in percent of the map, with one decimal place or (option) whole numbers.
function MinimapCoords.Format(x, y)
	if MinimapCoords.db.wholeCoords then
		return ("%d, %d"):format(floor(x + 0.5), floor(y + 0.5))
	end
	return ("%.1f, %.1f"):format(x, y)
end

local UPDATE_INTERVAL = 0.2
local text, ticker, lastX, lastY

local function Update()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		if lastX then
			text:SetText("")
			lastX, lastY = nil, nil
		end
		return
	end
	local x, y = position:GetXY()
	x, y = floor(x * 1000 + 0.5), floor(y * 1000 + 0.5)
	if x ~= lastX or y ~= lastY then
		lastX, lastY = x, y
		text:SetText(MinimapCoords.Format(x / 10, y / 10))
	end
end

local function StartTicker()
	campfireMoving = true
	if #campfires > 0 then
		PositionCampfires()
	end
	if not ticker then
		ticker = ns.NewTicker("Minimap: Update", UPDATE_INTERVAL, Update)
	end
end

local function StopTicker()
	campfireMoving = UnitOnTaxi("player") and true or false
	if #campfires > 0 then
		PositionCampfires()
	end
	if ticker and not UnitOnTaxi("player") then
		ticker:Cancel()
		ticker = nil
	end
	Update()
end

---------------------------------------------------------------------------
-- World map: own coordinate display of fixed size (Blizzard's panel changes
-- size whenever the cursor leaves the map, so it cannot be grabbed). Blizzard's
-- panel is only made invisible.
---------------------------------------------------------------------------
local MAP_INTERVAL = 0.05
local mapCoords, blizzardPanel

local function FindCoordsPanel()
	for _, frame in ipairs(WorldMapFrame.overlayFrames or {}) do
		if frame.PlayerCoords and frame.CursorCoords then
			return frame
		end
	end
end

local function FormatCoords(x, y)
	if not x or not y then
		return "–"
	end
	return MinimapCoords.Format(x * 100, y * 100)
end

local lastCursorText, lastPlayerText

local function UpdateMapCoords()
	local map = WorldMapFrame
	local cursorX, cursorY
	if map:IsCanvasMouseFocusOrPinFocus() then
		cursorX, cursorY = map:GetNormalizedCursorPosition()
	end
	local mapID = map:GetMapID()
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local playerX, playerY
	if position then
		playerX, playerY = position:GetXY()
	end
	local cursorText = FormatCoords(cursorX, cursorY)
	if cursorText ~= lastCursorText then
		lastCursorText = cursorText
		mapCoords.Cursor:SetText(L.MAP_CURSOR:format(cursorText))
	end
	local playerText = FormatCoords(playerX, playerY)
	if playerText ~= lastPlayerText then
		lastPlayerText = playerText
		mapCoords.Player:SetText(L.MAP_PLAYER:format(playerText))
	end
end

local function CreateMapCoords()
	local container = WorldMapFrame:GetCanvasContainer()
	local frame = CreateFrame("Frame", nil, WorldMapFrame)
	frame:SetSize(170, 32)
	frame:SetFrameStrata("HIGH")
	frame.Cursor = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Cursor:SetPoint("TOPLEFT", 4, -3)
	frame.Cursor:SetJustifyH("LEFT")
	frame.Player = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Player:SetPoint("TOPLEFT", frame.Cursor, "BOTTOMLEFT", 0, -2)
	frame.Player:SetJustifyH("LEFT")
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_WORLDMAP_COORDS)
		GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	local elapsed = 0
	ns.SetUpdate(frame, "Minimap: coordinates update", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= MAP_INTERVAL then
			elapsed = 0
			UpdateMapCoords()
		end
	end)
	ns:RegisterDisplay(frame, "MapCoords", function(self)
		self:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 6)
	end, container)
	mapCoords = frame
end

function MinimapCoords:UpdateWorldMapCoords()
	if not WorldMapFrame then
		return
	end
	blizzardPanel = blizzardPanel or FindCoordsPanel()
	local enabled = self.db.worldMapCoords
	if enabled and not mapCoords then
		CreateMapCoords()
	end
	if mapCoords then
		mapCoords:SetShown(enabled)
	end
	if blizzardPanel then
		blizzardPanel:SetAlpha(enabled and 0 or 1)
	end
end

function MinimapCoords:UpdateFont()
	if text then
		text:SetFont(ns.GetFontFace(), 14, "OUTLINE")
	end
end

---------------------------------------------------------------------------
-- Tracking menu: spell icons fill their whole square, the other symbols
-- have empty margins. Spell icons get the visible size of the others.
---------------------------------------------------------------------------
local MENU_ICON_SIZE = 20 -- Blizzard's size in the tracking menu
local SPELL_ICON_SIZE = 15

local function ShrinkTrackingIcon(button, description)
	local info = description:GetData()
	if not MinimapCoords.db.trackingIcons or type(info) ~= "table" or info.type ~= "spell" then
		return
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:IsObjectType("Texture") and region:GetNumPoints() == 1 then
			local point, relativeTo = region:GetPoint(1)
			if point == "RIGHT" and relativeTo == button then
				region:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
				region:SetPoint("RIGHT", button, "RIGHT", -(MENU_ICON_SIZE - SPELL_ICON_SIZE) / 2, 0)
			end
		end
	end
end

local function AddIconInitializers(description)
	for _, element in description:EnumerateElementDescriptions() do
		element:AddInitializer(ShrinkTrackingIcon)
		AddIconInitializers(element)
	end
end

-- Hunter tracking (Find Beasts, Find Humanoids, …): the game keeps only one of them active. Blizzard's menu
-- remembers its own state and does not read the game again while it is open, so a second check mark stayed
-- and the next click switched the wrong way. These entries read the live state instead and remember what
-- was clicked until the menu is built again.
local forced = {} -- tracking index -> shown as checked (true) or unchecked (false)

local function IsHunterTracking(info)
	local _, class = UnitClass("player")
	return class == "HUNTER" and type(info) == "table" and info.subType == (HUNTER_TRACKING or 1)
end

local function HunterSelected(info)
	local value = forced[info.index]
	if value ~= nil then
		return value
	end
	local live = C_Minimap.GetTrackingInfo(info.index)
	return type(live) == "table" and live.active == true
end

local function HunterClicked(info)
	local selected = not HunterSelected(info)
	forced[info.index] = selected
	if selected then
		for index = 1, C_Minimap.GetNumTrackingTypes() do
			if index ~= info.index and IsHunterTracking(C_Minimap.GetTrackingInfo(index)) then
				forced[index] = false
			end
		end
	end
	MinimapUtil.SetTrackingFilterByFilterIndex(info.index, selected)
end

-- The check mark itself is drawn by Blizzard's own initializer from its remembered state; this one runs after
-- it (and again on every refresh) and draws the mark the way it should be.
local function DrawHunterCheck(button, description)
	local info = description:GetData()
	local base = button.leftTexture1
	if type(info) ~= "table" or not base then
		return
	end
	local mark = button.leftTexture2
	if HunterSelected(info) then
		if not mark then
			mark = button:AttachTexture()
			local layer, level = base:GetDrawLayer()
			mark:SetDrawLayer(layer, level + 1)
			mark:SetAtlas("common-dropdown-icon-checkmark-yellow", true)
			mark:SetPoint("CENTER", base, "CENTER", 2, 1)
			button.leftTexture2 = mark
		end
		mark:Show()
	elseif mark then
		mark:Hide()
	end
end

local function FixHunterTracking(description)
	for _, element in description:EnumerateElementDescriptions() do
		local info = element:GetData()
		if type(info) == "table" and info.index and IsHunterTracking(info) then
			element:SetIsSelected(HunterSelected)
			element:SetResponder(HunterClicked)
			element:AddInitializer(function(button, desc)
				pcall(DrawHunterCheck, button, desc)
			end)
		end
		FixHunterTracking(element)
	end
end

-- Entries of ForeverPlus functions in the tracking menu: ns.AddTrackingEntry(fn)
-- with fn(rootDescription) adding its checkbox or submenu.
local trackingEntries = {}

function ns.AddTrackingEntry(fn)
	trackingEntries[#trackingEntries + 1] = fn
end

-- The size of the minimap symbols can also be chosen in the tracking menu.
ns.AddTrackingEntry(function(root)
	ns.CreateSizeMenu(root, L.MINIMAP_SYMBOL_SCALE, "Minimap", "symbolScale")
end)

local function AddForeverPlusEntries(rootDescription)
	if not MinimapCoords.db.trackingEntries or #trackingEntries == 0 then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle(L.MENU_EXTRAS)
	for _, fn in ipairs(trackingEntries) do
		fn(rootDescription)
	end
end

---------------------------------------------------------------------------
-- Emitter sounds: right-click the tracking button.
---------------------------------------------------------------------------
local emitterWindow, emitterButton
local previewID, previewHandle
local allEmittersProvider, emitterFilterTicker
local emitterBulkInProgress
local emitterFilterToken, emitterDebounceToken = 0, 0
local EMITTER_SEARCH_DELAY = 0.12
local EMITTER_SLICE_BUDGET = 0.5
local EMITTER_DISTANCE_MARGIN = 100
local EMITTER_KINDS = {
	{ "all", L.MINIMAP_EMITTER_FILTER_ALL },
	{ "source", L.MINIMAP_EMITTER_FILTER_SOURCES },
	{ "background", L.MINIMAP_EMITTER_AMBIENCE },
	{ "detail", L.MINIMAP_EMITTER_AMBIENCE_DETAIL },
	{ "rain", L.MINIMAP_EMITTER_FILTER_RAIN },
}
local EMITTER_CATEGORIES = {
	{ "all", L.MINIMAP_EMITTER_CATEGORY_ALL },
	{ "water", L.MINIMAP_EMITTER_CATEGORY_WATER },
	{ "wind", L.MINIMAP_EMITTER_CATEGORY_WIND },
	{ "rain", L.MINIMAP_EMITTER_FILTER_RAIN },
	{ "thunder", L.MINIMAP_EMITTER_CATEGORY_THUNDER },
	{ "fire", L.MINIMAP_EMITTER_CATEGORY_FIRE },
	{ "snow", L.MINIMAP_EMITTER_CATEGORY_SNOW },
	{ "animals", L.MINIMAP_EMITTER_CATEGORY_ANIMALS },
	{ "voices", L.MINIMAP_EMITTER_CATEGORY_VOICES },
	{ "objects", L.MINIMAP_EMITTER_CATEGORY_OBJECTS },
	{ "magic", L.MINIMAP_EMITTER_CATEGORY_MAGIC },
	{ "combat", L.MINIMAP_EMITTER_CATEGORY_COMBAT },
	{ "environment", L.MINIMAP_EMITTER_CATEGORY_ENVIRONMENT },
	{ "unknown", L.MINIMAP_EMITTER_CATEGORY_UNKNOWN },
}
local CATEGORY_NAMES = {}
for _, entry in ipairs(EMITTER_CATEGORIES) do CATEGORY_NAMES[entry[1]] = entry[2] end
local EMITTER_RADII = { 0, 25, 50, 100, 250, 500 }
local RAIN_NAMES = {
	light = L.MINIMAP_EMITTER_RAIN_LIGHT,
	medium = L.MINIMAP_EMITTER_RAIN_MEDIUM,
	heavy = L.MINIMAP_EMITTER_RAIN_HEAVY,
}
local emitterFilesByID
local emitterFilesByKind = {}

local function CanMuteEmitters()
	return type(MuteSoundFile) == "function" and type(UnmuteSoundFile) == "function"
end

local function StopEmitterPreview()
	if previewHandle then StopSound(previewHandle) end
	previewID, previewHandle = nil, nil
	if emitterWindow then emitterWindow.StopPreview:Disable() end
end

local function SetEmitterMuted(id, mute)
	local muted = MinimapCoords.db.mutedEmitters
	if (muted[id] == true) == mute then return end
	if mute then
		if previewID == id then StopEmitterPreview() end
		MuteSoundFile(id)
	else
		UnmuteSoundFile(id)
	end
	muted[id] = mute and true or nil
end

local function UpdateEmitterBulkButton()
	local matches = emitterWindow.Matches
	local button = emitterWindow.BulkMute
	if emitterBulkInProgress or not matches or #matches == 0 then
		button:Disable()
		return
	end
	local muted = MinimapCoords.db.mutedEmitters
	button.mute = false
	for _, file in ipairs(matches) do
		if not muted[file[1]] then
			button.mute = true
			break
		end
	end
	button:SetText(button.mute and L.MINIMAP_EMITTER_MUTE_ALL or L.MINIMAP_EMITTER_UNMUTE_ALL)
	button:Enable()
end

local function CancelEmitterFilter()
	emitterFilterToken = emitterFilterToken + 1
	if emitterFilterTicker then
		emitterFilterTicker:Cancel()
		emitterFilterTicker = nil
	end
	emitterWindow.Matches = nil
	emitterWindow.BulkMute:Disable()
end

-- CreateDataProvider(tbl) fires TriggerEvent("OnInsert") per row.
-- Attach the pre-built array directly to a fresh unsubscribed provider instead.
local function MakeEmitterProvider(entries)
	local provider = CreateDataProvider()
	if type(provider) == "table" and type(provider.collection) == "table" then
		provider.collection = entries
		return provider
	end
	return CreateDataProvider(entries)
end

local function ApplyEmitterMatches(matches, retainScroll)
	if not emitterWindow then return end
	emitterWindow.Empty:SetShown(#matches == 0)
	emitterWindow.Count:SetText(L.MINIMAP_EMITTER_COUNT:format(#matches))
	local provider
	if matches == ns.EmitterSounds then
		allEmittersProvider = allEmittersProvider or MakeEmitterProvider(ns.EmitterSounds)
		provider = allEmittersProvider
	else
		provider = MakeEmitterProvider(matches)
	end
	emitterWindow.List:SetDataProvider(provider, retainScroll and ScrollBoxConstants.RetainScrollPosition)
	emitterWindow.Matches = matches
	UpdateEmitterBulkButton()
end

local function EmitterFilesByID()
	if not emitterFilesByID then
		emitterFilesByID = {}
		for _, file in ipairs(ns.EmitterSounds) do emitterFilesByID[file[1]] = file end
	end
	return emitterFilesByID
end

local function EmitterFilesOfKind(kind)
	if kind == "rain" then return ns.EmitterRainSounds end
	if not emitterFilesByKind[kind] then
		local files = {}
		if kind == "source" then
			for _, kit in pairs(ns.EmitterKitFiles) do
				for _, id in ipairs(kit) do files[id] = true end
			end
		else
			local index = kind == "background" and 1 or 2
			for _, groups in pairs(ns.EmitterAmbienceFiles) do
				for _, id in ipairs(groups[index]) do files[id] = true end
			end
		end
		emitterFilesByKind[kind] = files
	end
	return emitterFilesByKind[kind]
end

local function EmitterFileTitle(file)
	return file[3] or RAIN_NAMES[ns.EmitterRainSounds[file[1]]]
		or (file[2] and file[2]:match("[^/]+$")) or L.MINIMAP_EMITTER_UNKNOWN
end

local function EmitterCategory(file)
	if file[6] then return file[6], true end
	local category = ns.EmitterSoundCategories[file[1]]
	if category then return category[1], category[2] end
	return "unknown", false
end

local function EmitterCategoryLabel(file)
	local category, inferred = EmitterCategory(file)
	local name = CATEGORY_NAMES[category]
	return inferred and L.MINIMAP_EMITTER_CATEGORY_INFERRED:format(name) or name
end

local function NormalizeEmitterText(value)
	return ns.LowerCommand(value):gsub("[%s/_.%-]+", " ")
end

local function MatchesEmitter(file, words, category)
	if category ~= "all" and EmitterCategory(file) ~= category then return false end
	if #words == 0 then return true end
	local haystack = " " .. NormalizeEmitterText((file[2] or "") .. " " .. EmitterFileTitle(file) .. " "
		.. (file[4] or "") .. " " .. EmitterCategoryLabel(file))
	for _, word in ipairs(words) do
		if word == "wind" then
			if not (haystack:find(" wind", 1, true) or haystack:find(" breeze", 1, true) or haystack:find(" gust", 1, true)) then
				return false
			end
		elseif not haystack:find(word, 1, true) then
			return false
		end
	end
	return true
end

local function EmitterPlayerLocation()
	local map = C_Map.GetBestMapForUnit("player")
	if ns.Secret(map) then return end
	local zone = map
	local assignment
	for _ = 1, 8 do
		if not zone then break end
		assignment = ns.EmitterMapAreas[zone]
		if assignment then break end
		local info = C_Map.GetMapInfo(zone)
		zone = type(info) == "table" and ns.Number(info.parentMapID) or nil
	end
	local _, instanceType, _, _, _, _, _, instanceMap = GetInstanceInfo()
	local inInstance = not ns.Secret(instanceType) and type(instanceType) == "string" and instanceType ~= "none"
	local worldMap = assignment and assignment[1] or (inInstance and ns.Number(instanceMap))
	local position = map and C_Map.GetPlayerMapPosition(map, "player")
	local x, y
	if not ns.Secret(position) and position and worldMap then
		local positionMap, world = C_Map.GetWorldPosFromMapPos(map, position)
		if not ns.Secret(world) and world and not ns.Secret(positionMap) and positionMap == worldMap then
			x, y = world:GetXY()
			x, y = ns.Number(x), ns.Number(y)
		end
	end
	return assignment and assignment[2], worldMap, x, y, inInstance
end

local function EmitterDistance(x, y, coords)
	local startX, startY = coords[1], coords[2]
	local closest = (startX - x)^2 + (startY - y)^2
	for i = 3, #coords, 2 do
		local nextX, nextY = coords[i], coords[i + 1]
		local dx, dy = nextX - startX, nextY - startY
		local lengthSquared = dx * dx + dy * dy
		if lengthSquared > 0 then
			local fraction = max(0, min(1, ((x - startX) * dx + (y - startY) * dy) / lengthSquared))
			closest = min(closest, (startX + fraction * dx - x)^2 + (startY + fraction * dy - y)^2)
		end
		startX, startY = nextX, nextY
	end
	return math.sqrt(closest)
end

local function CollectZoneAmbience(root, kind, add)
	local areas = root and ns.EmitterAmbience[root]
	if not areas then return end
	local area = root
	local subzone = GetSubZoneText()
	if not ns.Secret(subzone) and type(subzone) == "string" and subzone ~= "" then
		for id in pairs(areas) do
			local name = C_Map.GetAreaInfo(id)
			if not ns.Secret(name) and name == subzone then
				area = id
				break
			end
		end
	end
	local submerged = IsSubmerged()
	submerged = not ns.Secret(submerged) and submerged == true
	local function AddArea(id, offset)
		local data = ns.EmitterAmbienceFiles[areas[id][submerged and 2 or 1]]
		if not data then return end
		if kind ~= "detail" then
			for _, fileID in ipairs(data[1]) do
				add(fileID, 400 + offset, false, L.MINIMAP_EMITTER_AMBIENCE)
			end
		end
		if kind ~= "background" then
			for _, fileID in ipairs(data[2]) do
				add(fileID, 2000 + offset, false, L.MINIMAP_EMITTER_AMBIENCE_DETAIL)
			end
		end
	end
	AddArea(area, 0)
	if area ~= root then AddArea(root, 1) end
end

local function IsEmitterRainScope(db)
	return db.emitterSoundKind == "rain" or (db.emitterSoundKind == "all" and db.emitterSoundCategory == "rain")
end

local function RefreshEmitters(retainScroll)
	if not emitterWindow then return end
	CancelEmitterFilter()
	local query = emitterWindow.Search:GetText():match("^%s*(.-)%s*$")
	local id = tonumber(query)
	if id and (id <= 0 or id > 2147483647 or id ~= floor(id)) then id = nil end
	local mutedOnly = emitterWindow.MutedOnly:GetChecked()
	local db = MinimapCoords.db
	local kind = db.emitterSoundKind
	local category = db.emitterSoundCategory
	local rainScope = IsEmitterRainScope(db)
	local nearbyOnly = db.nearbyEmitters and not mutedOnly and not id and not rainScope
	local muted = db.mutedEmitters
	local showSources = kind == "all" or kind == "source"
	local root, map, x, y, inInstance
	if nearbyOnly then root, map, x, y, inInstance = EmitterPlayerLocation() end
	local radiusAvailable = showSources and x ~= nil and y ~= nil
	local radius = radiusAvailable and db.emitterSoundRadius or 0
	emitterWindow.RadiusAvailable = radiusAvailable
	local activeFilters = (kind ~= "all" and 1 or 0) + (category ~= "all" and 1 or 0) + (radius > 0 and 1 or 0)
	emitterWindow.Filter:SetText(activeFilters > 0 and L.MINIMAP_EMITTER_FILTER_ACTIVE:format(activeFilters) or L.MINIMAP_EMITTER_FILTER)
	emitterWindow.Nearby:SetEnabled(not mutedOnly and not rainScope)
	local zoneName = nearbyOnly and GetRealZoneText()
	emitterWindow.Scope:SetText(not ns.Secret(zoneName) and type(zoneName) == "string" and zoneName or L.MINIMAP_EMITTER_FOREVER)
	emitterWindow.Empty:SetText(nearbyOnly and L.MINIMAP_EMITTER_EMPTY_HERE or L.MINIMAP_EMITTER_EMPTY)
	if query == "" and not mutedOnly and not nearbyOnly and kind == "all" and category == "all" then
		ApplyEmitterMatches(ns.EmitterSounds, retainScroll)
		return
	end
	local byID = EmitterFilesByID()
	local kindFiles = not nearbyOnly and kind ~= "all" and EmitterFilesOfKind(kind)
	if id then
		local files = {}
		if (not kindFiles or kindFiles[id]) and (not mutedOnly or muted[id]) then
			local file = byID[id] or (muted[id] and { id } or nil)
			if file and (category == "all" or EmitterCategory(file) == category) then files[1] = file end
		end
		ApplyEmitterMatches(files, retainScroll)
		return
	end
	local words = {}
	for word in NormalizeEmitterText(query):gmatch("%S+") do words[#words + 1] = word end
	local matches = {}
	if mutedOnly then
		for fileID, isMuted in pairs(muted) do
			if isMuted and (not kindFiles or kindFiles[fileID]) then
				local file = byID[fileID] or { fileID }
				if MatchesEmitter(file, words, category) then matches[#matches + 1] = file end
			end
		end
		table.sort(matches, function(a, b) return a[1] < b[1] end)
		ApplyEmitterMatches(matches, retainScroll)
		return
	end

	local token = emitterFilterToken
	local function Done()
		emitterFilterTicker = nil
		if token == emitterFilterToken and emitterWindow and emitterWindow:IsShown() then
			ApplyEmitterMatches(matches, retainScroll)
		end
	end
	if not nearbyOnly then
		emitterFilterTicker = ns.RunSliced("Minimap: filter emitters", #ns.EmitterSounds, function(index)
			local file = ns.EmitterSounds[index]
			if (not kindFiles or kindFiles[file[1]]) and MatchesEmitter(file, words, category) then
				matches[#matches + 1] = file
			end
		end, Done, EMITTER_SLICE_BUDGET)
		return
	end

	local placements = showSources and (x and y or inInstance) and ns.EmitterLocations[map] or {}
	local candidates = {}
	local function AddCandidate(fileID, rank, title, source, placementCategory)
		local file = byID[fileID]
		local existing = candidates[fileID]
		if file and (not existing or rank < existing[5]) then
			local assigned = ns.EmitterSoundCategories[fileID]
			local localCategory
			if placementCategory and placementCategory ~= "environment" and (not assigned or assigned[2]) then
				localCategory = placementCategory
			end
			local candidate = { fileID, file[2], title, source, rank, localCategory }
			if MatchesEmitter(candidate, words, category) then candidates[fileID] = candidate end
		end
	end
	if kind ~= "source" then CollectZoneAmbience(root, kind, AddCandidate) end
	emitterFilterTicker = ns.RunSliced("Minimap: find nearby emitters", #placements, function(index)
		if token ~= emitterFilterToken then return end
		local placement = placements[index]
		local distance = x and y and EmitterDistance(x, y, placement[4])
		if not distance or (distance <= placement[2] + EMITTER_DISTANCE_MARGIN and (radius == 0 or distance <= radius)) then
			local detail = distance and L.MINIMAP_EMITTER_DISTANCE:format(floor(distance + 0.5)) or L.MINIMAP_EMITTER_PLACED
			for _, fileID in ipairs(ns.EmitterKitFiles[placement[3]]) do
				AddCandidate(fileID, distance or 0, placement[1], detail, placement[5])
			end
		end
	end, function()
		for _, file in pairs(candidates) do matches[#matches + 1] = file end
		table.sort(matches, function(a, b)
			if a[5] ~= b[5] then return a[5] < b[5] end
			local first, second = EmitterFileTitle(a), EmitterFileTitle(b)
			if first ~= second then return first < second end
			return a[1] < b[1]
		end)
		Done()
	end, EMITTER_SLICE_BUDGET)
end

local function OpenEmitterFilterMenu(button)
	local db = MinimapCoords.db
	MenuUtil.CreateContextMenu(button, function(_, menu)
		local categories = menu:CreateButton(L.MINIMAP_EMITTER_CATEGORY_MENU)
		local function SetCategory(category)
			db.emitterSoundCategory = category
			RefreshEmitters(false)
		end
		for _, entry in ipairs(EMITTER_CATEGORIES) do
			categories:CreateRadio(entry[2], function(category) return db.emitterSoundCategory == category end, SetCategory, entry[1])
		end
		menu:CreateDivider()
		menu:CreateTitle(L.MINIMAP_EMITTER_FILTER_KIND)
		local function SetKind(kind)
			db.emitterSoundKind = kind
			RefreshEmitters(false)
		end
		for _, entry in ipairs(EMITTER_KINDS) do
			menu:CreateRadio(entry[2], function(kind) return db.emitterSoundKind == kind end, SetKind, entry[1])
		end
		menu:CreateDivider()
		menu:CreateTitle(L.MINIMAP_EMITTER_FILTER_RADIUS)
		if not emitterWindow.RadiusAvailable then
			menu:CreateTitle(L.MINIMAP_EMITTER_FILTER_RADIUS_HINT)
		end
		local function SetRadius(radius)
			if emitterWindow.RadiusAvailable then
				db.emitterSoundRadius = radius
				RefreshEmitters(false)
			end
		end
		for _, radius in ipairs(EMITTER_RADII) do
			local label = radius == 0 and L.MINIMAP_EMITTER_FILTER_RADIUS_DEFAULT or L.MINIMAP_EMITTER_FILTER_RADIUS_LIMIT:format(radius)
			local radio = menu:CreateRadio(label, function(value) return db.emitterSoundRadius == value end, SetRadius, radius)
			radio:SetEnabled(emitterWindow.RadiusAvailable == true)
		end
		menu:CreateDivider()
		menu:CreateButton(L.RESET, function()
			db.emitterSoundKind, db.emitterSoundCategory, db.emitterSoundRadius = "all", "all", 0
			RefreshEmitters(false)
		end):SetEnabled(db.emitterSoundKind ~= "all" or db.emitterSoundCategory ~= "all" or db.emitterSoundRadius ~= 0)
	end)
end

local function ToggleEmitterMatches(button)
	local matches = emitterWindow.Matches
	if emitterBulkInProgress or not matches or #matches == 0 then return end
	local mute = button.mute
	emitterBulkInProgress = true
	button:Disable()
	ns.RunSliced("Minimap: set mute for emitter results", #matches, function(index)
		SetEmitterMuted(matches[index][1], mute)
	end, function()
		emitterBulkInProgress = false
		if not emitterWindow:IsShown() then return end
		if emitterWindow.MutedOnly:GetChecked() then
			RefreshEmitters(true)
		else
			emitterWindow.List:ReinitializeFrames()
			UpdateEmitterBulkButton()
		end
	end, EMITTER_SLICE_BUDGET)
end

local function QueueEmitterSearch()
	CancelEmitterFilter()
	emitterDebounceToken = emitterDebounceToken + 1
	local token = emitterDebounceToken
	ns.After("Minimap: filter emitters (debounce)", EMITTER_SEARCH_DELAY, function()
		if token == emitterDebounceToken and emitterWindow and emitterWindow:IsShown() then
			RefreshEmitters(false)
		end
	end)
end

local function InitEmitterRow(row, file)
	if not row.Mute then
		local mute = CreateFrame("CheckButton", nil, row, "UICheckButtonArtTemplate")
		mute:SetSize(24, 24)
		mute:SetPoint("LEFT")
		row.Mute = mute

		local preview = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		preview:SetSize(78, 20)
		preview:SetPoint("RIGHT", -2, 0)
		preview:SetText(L.MINIMAP_EMITTER_PREVIEW)
		row.Preview = preview

		local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		name:SetPoint("LEFT", mute, "RIGHT", 2, 7)
		name:SetPoint("RIGHT", preview, "LEFT", -6, 7)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		row.Label = name

		local detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		detail:SetPoint("LEFT", mute, "RIGHT", 2, -7)
		detail:SetPoint("RIGHT", preview, "LEFT", -6, -7)
		detail:SetJustifyH("LEFT")
		detail:SetWordWrap(false)
		row.Detail = detail
		row:EnableMouse(true)
		row:SetMouseClickEnabled(false)
		row:SetScript("OnEnter", ns.Measured("Minimap: emitter file tooltip", function()
			GameTooltip:SetOwner(row, "ANCHOR_LEFT")
			local sound = row.file
			GameTooltip:SetText(EmitterFileTitle(sound), 1, 0.82, 0, 1, true)
			GameTooltip:AddLine(EmitterCategoryLabel(sound))
			GameTooltip:AddLine(("FileDataID %d"):format(sound[1]))
			if sound[2] then GameTooltip:AddLine(sound[2], 1, 1, 1, true) end
			GameTooltip:Show()
		end))
		row:SetScript("OnLeave", GameTooltip_Hide)
		mute:SetScript("OnClick", ns.Measured("Minimap: mute emitter", function(self)
			local id = row.file[1]
			if emitterBulkInProgress then
				self:SetChecked(MinimapCoords.db.mutedEmitters[id] == true)
				return
			end
			local checked = self:GetChecked() == true
			SetEmitterMuted(id, checked)
			preview:SetEnabled(not checked)
			if emitterWindow.MutedOnly:GetChecked() then
				RefreshEmitters(true)
			else
				UpdateEmitterBulkButton()
			end
		end))
		preview:SetScript("OnClick", ns.Measured("Minimap: preview emitter", function()
			if emitterBulkInProgress then return end
			StopEmitterPreview()
			local id = row.file[1]
			local played, handle = PlaySoundFile(id, "SFX")
			if played then
				previewID, previewHandle = id, handle
				if handle then emitterWindow.StopPreview:Enable() end
			end
		end))
	end
	row.file = file
	row.Label:SetText(EmitterFileTitle(file))
	local filename = file[2] and file[2]:match("[^/]+$")
	local source = file[4] or ((file[3] or ns.EmitterRainSounds[file[1]]) and filename)
	local category = EmitterCategoryLabel(file)
	row.Detail:SetText(source and ("%s   ·   %s   ·   %d"):format(category, source, file[1])
		or ("%s   ·   %d"):format(category, file[1]))
	local muted = MinimapCoords.db.mutedEmitters[file[1]]
	row.Mute:SetChecked(muted == true)
	row.Preview:SetEnabled(not muted)
end

local function CreateEmitterWindow()
	local window = CreateFrame("Frame", "ForeverPlusEmitterSounds", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(window)
	window:SetTitle(L.MINIMAP_EMITTER_TITLE)
	window:SetSize(595, 414)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:Hide()
	tinsert(UISpecialFrames, window:GetName())

	local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	search:SetSize(205, 24)
	search:SetPoint("TOPLEFT", 16, -29)
	search:SetMaxLetters(100)
	window.Search = search

	local nearby = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	nearby:SetSize(26, 26)
	nearby:SetPoint("LEFT", search, "RIGHT", 10, 0)
	nearby.Text:SetText(L.MINIMAP_EMITTER_NEARBY)
	nearby:SetChecked(MinimapCoords.db.nearbyEmitters)
	window.Nearby = nearby

	local mutedOnly = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	mutedOnly:SetSize(26, 26)
	mutedOnly:SetPoint("LEFT", nearby, "LEFT", 112, 0)
	mutedOnly.Text:SetText(L.MINIMAP_EMITTER_MUTED_ONLY)
	window.MutedOnly = mutedOnly

	local filter = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	filter:SetSize(94, 20)
	filter:SetPoint("TOPRIGHT", -16, -31)
	filter:SetText(L.MINIMAP_EMITTER_FILTER)
	filter:SetScript("OnClick", ns.Measured("Minimap: open ambient sound filters", OpenEmitterFilterMenu))
	window.Filter = filter

	local scope = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scope:SetPoint("LEFT", window, "BOTTOMLEFT", 14, 14)
	window.Scope = scope
	local count = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count:SetPoint("RIGHT", window, "BOTTOMRIGHT", -14, 14)
	window.Count = count
	local bulk = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	bulk:SetSize(158, 20)
	bulk:SetPoint("BOTTOM", -45, 4)
	bulk:SetText(L.MINIMAP_EMITTER_MUTE_ALL)
	bulk:Disable()
	bulk:SetScript("OnClick", ns.Measured("Minimap: toggle emitter results", ToggleEmitterMatches))
	window.BulkMute = bulk
	scope:SetPoint("RIGHT", bulk, "LEFT", -8, 0)
	scope:SetJustifyH("LEFT")
	scope:SetWordWrap(false)
	local stop = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	stop:SetSize(82, 20)
	stop:SetPoint("LEFT", bulk, "RIGHT", 8, 0)
	stop:SetText(L.MINIMAP_EMITTER_STOP)
	stop:Disable()
	stop:SetScript("OnClick", ns.Measured("Minimap: stop emitter preview", StopEmitterPreview))
	window.StopPreview = stop

	local list = CreateFrame("Frame", nil, window, "WowScrollBoxList")
	list:SetPoint("TOPLEFT", window.Inset, "TOPLEFT", 4, -3)
	list:SetPoint("BOTTOMRIGHT", window.Inset, "BOTTOMRIGHT", -25, 3)
	local scrollbar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
	scrollbar:SetPoint("TOPLEFT", list, "TOPRIGHT", 5, 0)
	scrollbar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 5, 0)
	scrollbar:SetHideIfUnscrollable(true)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(33)
	view:SetElementInitializer("Frame", ns.Measured("Minimap: init emitter row", InitEmitterRow))
	ScrollUtil.InitScrollBoxListWithScrollBar(list, scrollbar, view)
	window.List = list

	local empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", window.Inset)
	empty:SetText(L.MINIMAP_EMITTER_EMPTY)
	window.Empty = empty
	local refresh = ns.Measured("Minimap: filter emitters", function() RefreshEmitters(false) end)
	search:HookScript("OnTextChanged", QueueEmitterSearch)
	mutedOnly:SetScript("OnClick", refresh)
	nearby:SetScript("OnClick", ns.Measured("Minimap: toggle nearby sounds", function(self)
		MinimapCoords.db.nearbyEmitters = self:GetChecked() == true
		RefreshEmitters(false)
	end))
	window:HookScript("OnShow", ns.Measured("Minimap: watch emitter location", function(self)
		self:RegisterEvent("ZONE_CHANGED")
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("ZONE_CHANGED_INDOORS")
		self:RegisterEvent("PLAYER_STOPPED_MOVING")
	end))
	window:SetScript("OnEvent", ns.Measured("Minimap: refresh emitter location", function()
		if MinimapCoords.db.nearbyEmitters and not IsEmitterRainScope(MinimapCoords.db)
			and not mutedOnly:GetChecked() and not tonumber(search:GetText()) then
			QueueEmitterSearch()
		end
	end))
	window:HookScript("OnHide", ns.Measured("Minimap: stop emitter preview", function()
		window:UnregisterAllEvents()
		CancelEmitterFilter()
		emitterDebounceToken = emitterDebounceToken + 1
		search:ClearFocus()
		StopEmitterPreview()
	end))
	return window
end

local function UpdateEmitterButton()
	local tracking = MinimapCluster and MinimapCluster.Tracking
	local button = tracking and tracking.Button
	local enabled = MinimapCoords.db.emitterSoundMenu and CanMuteEmitters()
	if enabled and button and not emitterButton then
		-- The native DropdownButton opens tracking on left mouse down. Give
		-- right clicks their own hit area without changing its mouse registration.
		emitterButton = CreateFrame("Button", nil, button)
		emitterButton:SetAllPoints()
		emitterButton:SetFrameLevel(button:GetFrameLevel() + 1)
		emitterButton:RegisterForClicks("RightButtonUp")
		emitterButton:SetPassThroughButtons("LeftButton", "MiddleButton", "Button4", "Button5")
		emitterButton:SetMouseClickEnabled(true)
		emitterButton:SetMouseMotionEnabled(false)
		emitterButton:SetScript("OnClick", ns.Measured("Minimap: open emitter sounds", function(self)
			if emitterWindow and emitterWindow:IsShown() then
				emitterWindow:Hide()
				return
			end
			local created = not emitterWindow
			emitterWindow = emitterWindow or CreateEmitterWindow()
			emitterWindow:ClearAllPoints()
			emitterWindow:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", -4, -4)
			emitterWindow:Show()
			if created then
				-- Split initial ScrollBox population from window creation so both do not land in one frame.
				ns.After("Minimap: populate emitters", 0, function()
					if emitterWindow and emitterWindow:IsShown() then
						RefreshEmitters(false)
					end
				end)
			else
				RefreshEmitters(false)
			end
		end))
	end
	if emitterButton then emitterButton:SetShown(enabled) end
	if emitterWindow and not enabled then emitterWindow:Hide() end
end

---------------------------------------------------------------------------
-- Zoom back out: after zooming in, the minimap returns to the level it had
-- before once nobody zoomed for a few seconds.
---------------------------------------------------------------------------
local zoomRest, zoomLast, zoomTimer, zoomOwn

local function ZoomBack()
	zoomTimer = nil
	if MinimapCoords.db.zoomReset and zoomRest and Minimap:GetZoom() > zoomRest then
		zoomOwn = true
		Minimap:SetZoom(zoomRest)
		zoomOwn = false
		zoomLast = Minimap:GetZoom()
	end
end

local function OnZoomChanged()
	if #campfires > 0 then
		PositionCampfires()
	end
	if zoomOwn or not MinimapCoords.db.zoomReset then
		return
	end
	local zoom = Minimap:GetZoom()
	if not zoomTimer then
		zoomRest = zoomLast or zoom
	end
	zoomLast = zoom
	if zoomTimer then
		zoomTimer:Cancel()
		zoomTimer = nil
	end
	if zoom > zoomRest then
		zoomTimer = ns.NewTimer("Minimap: ZoomBack", MinimapCoords.db.zoomDelay, ZoomBack)
	else
		zoomRest = zoom
	end
end

-- Hiding a parent runs Blizzard's mail OnHide, which hides the texture but
-- leaves the mail frame shown. The frame has no OnShow to restore the texture.
local mailFrame, mailFallback
local RefreshMailIcon = ns.Measured("Minimap: restore mail icon", function()
	local icon = mailFrame.MailIcon
	local hasMail = MinimapCoords.db.restoreMailIcon and mailFrame:IsShown() and not icon:IsShown() and HasNewMail()
	local show = not ns.Secret(hasMail) and hasMail == true
	if show and not mailFallback then
		local atlas = icon:GetAtlas()
		if not atlas then
			return
		end
		mailFallback = mailFrame:CreateTexture(nil, "ARTWORK")
		mailFallback:SetAtlas(atlas)
		mailFallback:SetAllPoints(icon)
	end
	if mailFallback then
		mailFallback:SetShown(show)
	end
end)

local function UpdateMailIcon()
	if not mailFrame and MinimapCoords.db.restoreMailIcon and type(HasNewMail) == "function" then
		local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
		local frame = indicator and indicator.MailFrame
		-- The animated mail indicator intentionally hides its icon while it plays.
		if frame and frame.MailIcon and not frame.NewMailAnim and not frame.MailReminderAnim and not frame:IsForbidden() then
			mailFrame = frame
			frame:HookScript("OnShow", RefreshMailIcon)
			frame:HookScript("OnEvent", RefreshMailIcon)
		end
	end
	if mailFrame then
		RefreshMailIcon()
	end
end

function MinimapCoords:OnLogin()
	ns.OnAddOnLoaded("Blizzard_Minimap", UpdateMailIcon)
	if CanMuteEmitters() then
		for id, muted in pairs(self.db.mutedEmitters) do
			if muted then MuteSoundFile(id) end
		end
		ns.OnAddOnLoaded("Blizzard_Minimap", UpdateEmitterButton)
	end
	ns.AddTrackingEntry(function(root)
		local displays = root:CreateButton(L.MINIMAP_DISPLAYS)
		ns.CreateOptionCheckbox(displays, L.INFO_PERF, "Info", "performance", L.INFO_PERF_DESC)
		ns.CreateOptionCheckbox(displays, L.MINIMAP_CAMPFIRES, "Minimap", "campfires", L.MINIMAP_CAMPFIRES_DESC)
		ns.CreateOptionCheckbox(displays, L.MINIMAP_ZOOM_RESET, "Minimap", "zoomReset", L.MINIMAP_ZOOM_RESET_DESC)
	end)
	zoomLast = Minimap:GetZoom()
	hooksecurefunc(Minimap, "SetZoom", OnZoomChanged)
	campfireHolder = CreateFrame("Frame", nil, Minimap)
	campfireHolder:SetAllPoints()
	campfireHolder:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", self.db.campfires)
	if C_Minimap.ClearAllTracking then
		hooksecurefunc(C_Minimap, "ClearAllTracking", function()
			wipe(forced)
		end)
	end
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_MINIMAP_TRACKING", function(_, rootDescription)
			wipe(forced)
			pcall(FixHunterTracking, rootDescription)
			AddIconInitializers(rootDescription)
			AddForeverPlusEntries(rootDescription)
		end)
	end
	-- Small frame around the text: movable and lockable like a window.
	local holder = CreateFrame("Frame", nil, Minimap)
	holder:SetSize(100, 18)
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	text = holder:CreateFontString(nil, "OVERLAY")
	self:UpdateFont()
	text:SetPoint("CENTER")
	holder:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.MINIMAP_COORDS)
		GameTooltip_AddInstructionLine(GameTooltip, L.DISPLAY_HINT)
		GameTooltip:Show()
	end)
	holder:SetScript("OnLeave", GameTooltip_Hide)
	ns:RegisterDisplay(holder, "MinimapCoords", function(frame)
		frame:SetPoint("TOP", Minimap, "TOP", 0, -12)
	end, Minimap)
	local _, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	if color then
		text:SetTextColor(color:GetRGB())
	end

	ns.OnAddOnLoaded("Blizzard_WorldMap", function()
		self:UpdateWorldMapCoords()
	end)

	self:RegisterEvent("PLAYER_STARTED_MOVING", StartTicker)
	self:RegisterEvent("PLAYER_STOPPED_MOVING", StopTicker)
	self:RegisterEvent("PLAYER_CONTROL_LOST", StartTicker)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", StopTicker)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		Update()
		if #campfires > 0 then PositionCampfires() end
	end)
	self:RegisterEvent("ZONE_CHANGED", Update)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", Update)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		Update()
		if #campfires > 0 then PositionCampfires() end
	end)
	Update()
end

function MinimapCoords:OnOptionChanged(key)
	if key == "wholeCoords" then
		lastX, lastY, lastCursorText, lastPlayerText = nil, nil, nil, nil
		if text then
			Update()
		end
	elseif key == "campfires" then
		self:ToggleEvent("UNIT_SPELLCAST_SUCCEEDED", self.db.campfires)
		PositionCampfires()
	elseif key == "symbolScale" then
		for _, fire in ipairs(campfires) do
			fire.pin:SetScale(SymbolScale())
		end
		local radar = ns:GetModule("RecipeRadar")
		if radar and radar.RequestRefresh then
			radar:RequestRefresh()
		end
	elseif key == "zoomReset" or key == "zoomDelay" then
		if zoomTimer then
			zoomTimer:Cancel()
			zoomTimer = nil
		end
		zoomLast = Minimap:GetZoom()
	elseif key == "restoreMailIcon" then
		UpdateMailIcon()
	elseif key == "emitterSoundMenu" then
		ns.RunOutOfCombat(UpdateEmitterButton)
	else
		self:UpdateWorldMapCoords()
	end
end

MinimapCoords.options = {
	{ key = "worldMapCoords", type = "toggle", name = L.MINIMAP_WORLDMAP_COORDS, desc = L.MINIMAP_WORLDMAP_COORDS_DESC },
	{ key = "wholeCoords", type = "toggle", name = L.MINIMAP_WHOLE_COORDS, desc = L.MINIMAP_WHOLE_COORDS_DESC, new = true },
	{ key = "trackingIcons", type = "toggle", name = L.MINIMAP_TRACKING_ICONS, desc = L.MINIMAP_TRACKING_ICONS_DESC },
	{ key = "trackingEntries", type = "toggle", name = L.MINIMAP_TRACKING_ENTRIES, desc = L.MINIMAP_TRACKING_ENTRIES_DESC },
	{ key = "emitterSoundMenu", type = "toggle", name = L.MINIMAP_EMITTER_TITLE, desc = L.MINIMAP_EMITTER_DESC },
	{ key = "restoreMailIcon", type = "toggle", name = L.MINIMAP_RESTORE_MAIL_ICON, desc = L.MINIMAP_RESTORE_MAIL_ICON_DESC },
	{ key = "zoomReset", type = "toggle", name = L.MINIMAP_ZOOM_RESET, desc = L.MINIMAP_ZOOM_RESET_DESC },
	{ key = "zoomDelay", type = "slider", name = L.MINIMAP_ZOOM_DELAY, desc = L.MINIMAP_ZOOM_DELAY_DESC, parent = "zoomReset", min = 5, max = 60, step = 5,
		format = function(value)
			return ("%d s"):format(value)
		end },
	{ key = "campfires", type = "toggle", name = L.MINIMAP_CAMPFIRES, desc = L.MINIMAP_CAMPFIRES_DESC, new = true },
	{ key = "symbolScale", type = "slider", name = L.MINIMAP_SYMBOL_SCALE, desc = L.MINIMAP_SYMBOL_SCALE_DESC, min = 50, max = 200, step = 10, new = true,
		format = function(value)
			return ("%d %%"):format(value)
		end },
}

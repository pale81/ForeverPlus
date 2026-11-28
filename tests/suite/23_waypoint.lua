-- WorldMap: unexplored area core outlines (HitRect) and center target markers
(function()
	local wm = ns:GetModule("WorldMap")
	assert(wm.db.revealAreas == true, "revealAreas defaults to true")
	local opt
	for _, entry in ipairs(wm.options) do
		if entry.key == "revealAreas" then opt = entry end
	end
	assert(opt and opt.new == true and opt.parent == "reveal", "revealAreas option has new = true and parent reveal")

	-- Shipped Data/MapOverlays.lua integrity: ns.MapOverlayAreas matches ns.MapOverlays 1:1
	-- (re-read original table before line 5152 replaced ns.MapOverlays with test data)
	local origOverlays, origAreas
	do
		local env = {}
		assert(loadfile("../Data/MapOverlays.lua"))("ForeverPlus", env)
		origOverlays, origAreas = env.MapOverlays, env.MapOverlayAreas
	end
	assert(origOverlays and origAreas, "Data/MapOverlays.lua exports MapOverlays and MapOverlayAreas")
	local totalAreas = 0
	for art, raw in pairs(origOverlays) do
		local rawAreas = origAreas[art]
		assert(type(rawAreas) == "string", "missing MapOverlayAreas for art " .. art)
		local nOverlays, nAreas = 0, 0
		for _ in raw:gmatch("[^;]+") do nOverlays = nOverlays + 1 end
		for part in rawAreas:gmatch("[^;]+") do
			local nums = {}
			for num in part:gmatch("-?%d+") do nums[#nums + 1] = tonumber(num) end
			assert(#nums == 5, "5 numbers per MapOverlayAreas entry in art " .. art)
			nAreas = nAreas + 1
			totalAreas = totalAreas + 1
		end
		assert(nOverlays == nAreas, "overlay/area count mismatch in art " .. art)
	end
	assert(totalAreas >= 1000, "shipped area entries present: " .. totalAreas)

	-- CoreRect unit tests: valid HitRect, zero HitRect fallback, and clamping
	local l, t, r, b, aid = wm.CoreRect({ 256, 256, 208, 375 }, { 260, 420, 365, 510, 921 }, 1002, 668)
	assert(l == 260 and t == 420 and r == 365 and b == 510 and aid == 921, "uses HitRect when valid")
	l, t, r, b, aid = wm.CoreRect({ 200, 100, 100, 200 }, { 0, 0, 0, 0, 161 }, 1002, 668)
	assert(l == 150 and t == 225 and r == 250 and b == 275 and aid == 161, "falls back to centered inner 50% when HitRect is zero")
	l, t, r, b = wm.CoreRect({ 200, 200, 900, 600 }, { 950, 620, 1200, 700, 1 }, 1002, 668)
	assert(l == 950 and t == 620 and r == 1002 and b == 668, "clamps CoreRect to map layer bounds")

	-- End-to-end rendering, hover tooltip, waypoint click, Paint(), and toggle off
	local saved = {
		ns.MapOverlays, ns.MapOverlayAreas, C_Map.GetMapArtID, C_Map.GetMapArtLayers, C_Map.GetAreaInfo,
		C_MapExplorationInfo, WorldMapFrame.GetCanvas, WorldMapFrame.GetCanvasScale,
		wm.db.reveal, wm.db.revealTint, wm.db.revealAreas, wm.db.revealColor,
		ns:GetModule("Waypoint").SetOnMap,
	}
	local drawFn = uv(wm.Apply, "Draw")
	local paintFn = uv(wm.ChooseTint, "Paint")
	local pinObj = uv(wm.Apply, "pin")
	local origCreateTex = pinObj.CreateTexture
	local origGetMap = pinObj.GetMap
	local areaTexMade = {}
	pinObj.CreateTexture = function(self, name, layer, tmpl, sub)
		local tex = origCreateTex(self, name, layer, tmpl, sub)
		if sub == 2 then areaTexMade[#areaTexMade + 1] = tex end
		return tex
	end
	local mockMap = { GetMapID = function() return 1436 end, IsShown = function() return true end,
		GetCanvasContainer = function() return { GetCurrentLayerIndex = function() return 1 end } end }
	pinObj.GetMap = function() return mockMap end

	local canvas = NewFrame("Frame")
	canvas.GetWidth = function() return 1002 end
	canvas.GetHeight = function() return 668 end
	WorldMapFrame.GetCanvas = function() return canvas end
	WorldMapFrame.GetCanvasScale = function() return 2 end

	ns.MapOverlays = { [2165] = "256,256,208,375,5001;256,256,317,331,5002" }
	ns.MapOverlayAreas = { [2165] = "260,420,365,510,921;390,370,495,505,20" }
	C_Map.GetMapArtID = function(id) return id == 1436 and 2165 or nil end
	C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256, layerWidth = 1002, layerHeight = 668 } } end
	C_Map.GetAreaInfo = function(id) return id == 921 and "Demonts Platz" or nil end
	-- 5002 (Moonbrook) is already explored; only 5001 (Demonts Platz) is unexplored!
	C_MapExplorationInfo = { GetExploredMapTextures = function() return { { fileDataIDs = { 5002 } } } end }

	wm.db.reveal, wm.db.revealTint, wm.db.revealAreas = true, false, true
	wm.db.revealColor = { r = 0.2, g = 0.9, b = 0.4 }
	drawFn()

	local shownCore = 0
	for _, tex in ipairs(areaTexMade) do
		if tex.shown then
			shownCore = shownCore + 1
			assert(tex.r == 0.2 and tex.g == 0.9 and tex.b == 0.4, "core texture keeps chosen color even when revealTint is off")
		end
	end
	assert(shownCore == 5, "1 fill + 4 border edges for the single unexplored area, got " .. shownCore)

	local markers = uv(paintFn, "areaMarkers")
	local usedMarkers = uv(paintFn, "usedAreaMarkers")
	assert(usedMarkers == 1 and markers[1]:IsShown(), "one center target marker shown for unexplored area")
	local m = markers[1]
	assert(math.abs(m.nx - (260 + 365) / 2 / 1002) < 1e-6 and math.abs(m.ny - (420 + 510) / 2 / 668) < 1e-6, "marker centered in HitRect")

	-- Hover tooltip shows localized area name and hint
	local tipTitle, tipNormal
	local savedTitle, savedNormal = GameTooltip_SetTitle, GameTooltip_AddNormalLine
	GameTooltip_SetTitle = function(_, text) tipTitle = text end
	GameTooltip_AddNormalLine = function(_, text) tipNormal = text end
	m:GetScript("OnEnter")(m)
	GameTooltip_SetTitle, GameTooltip_AddNormalLine = savedTitle, savedNormal
	assert(tipTitle == "Demonts Platz" and tipNormal == ns.L.WORLDMAP_UNEXPLORED_AREA_HINT, "hover tooltip shows localized subzone name and hint")

	-- Left-click sets waypoint at HitRect center with localized area name
	local wpCall
	ns:GetModule("Waypoint").SetOnMap = function(mapID, x, y, name)
		wpCall = { mapID = mapID, x = x, y = y, name = name }
		return true
	end
	m:GetScript("OnClick")(m, "LeftButton")
	assert(wpCall and wpCall.mapID == 1436 and wpCall.name == "Demonts Platz"
		and math.abs(wpCall.x - (260 + 365) / 2 / 1002 * 100) < 1e-4, "click sets waypoint on HitRect center")

	-- Live Paint() updates core textures and dot color
	wm.db.revealColor = { r = 1, g = 0.4, b = 0.1 }
	paintFn()
	assert(areaTexMade[1].r == 1 and areaTexMade[1].g == 0.4 and areaTexMade[1].b == 0.1, "Paint updates core outline color")

	-- Turning revealAreas off hides core outlines and markers
	wm.db.revealAreas = false
	drawFn()
	local afterOff = 0
	for _, tex in ipairs(areaTexMade) do if tex.shown then afterOff = afterOff + 1 end end
	assert(afterOff == 0 and not m:IsShown(), "revealAreas off hides core outlines and markers")

	-- Restore
	pinObj.CreateTexture = origCreateTex
	pinObj.GetMap = origGetMap
	ns.MapOverlays, ns.MapOverlayAreas = saved[1], saved[2]
	C_Map.GetMapArtID, C_Map.GetMapArtLayers, C_Map.GetAreaInfo = saved[3], saved[4], saved[5]
	C_MapExplorationInfo, WorldMapFrame.GetCanvas, WorldMapFrame.GetCanvasScale = saved[6], saved[7], saved[8]
	wm.db.reveal, wm.db.revealTint, wm.db.revealAreas, wm.db.revealColor = saved[9], saved[10], saved[11], saved[12]
	ns:GetModule("Waypoint").SetOnMap = saved[13]
	print("worldmap unexplored core areas OK")
end)()

;(function()
	-- Helpers: ForeverPlusOpenButton uses type="macro" + macrotext "/use bag slot" (avoids Blizzard's
	-- C_Item.IsEquippableItem(nil) crash in SECURE_ACTIONS.item when a bag slot empties) and verifies
	-- the slot in PreClick out of combat.
	local helpers = ns:GetModule("Helpers")
	local button = ForeverPlusOpenButton
	assert(button, "ForeverPlusOpenButton exists")
	assert(button:GetAttribute("type") == "macro", "open button uses secure macro type")

	local saved = {
		helpers.db.openButton,
		helpers.db.openButtonMute,
		helpers.cdb.openButtonMutedUntil,
		C_Container.GetContainerNumSlots,
		C_Container.GetContainerItemInfo,
		C_Container.GetContainerItemQuestInfo,
		C_TooltipInfo.GetBagItem,
		C_Item.GetItemCount,
		InCombatLockdown,
		ns.IsEditModeActive,
	}

	local bagState = {}
	local slotScans = 0
	C_Container.GetContainerNumSlots = function(bag)
		return bag == 3 and 8 or 0
	end
	C_Container.GetContainerItemInfo = function(bag, slot)
		slotScans = slotScans + 1
		return bagState[bag .. ":" .. slot]
	end
	C_Container.GetContainerItemQuestInfo = function() return nil end
	C_TooltipInfo.GetBagItem = function() return { lines = {} } end
	C_Item.GetItemCount = function() return 1 end
	InCombatLockdown = function() return false end
	ns.IsEditModeActive = function() return false end

	helpers.db.openButton = true
	helpers.db.openButtonMute = true
	helpers.cdb.openButtonMutedUntil = nil

	-- Populate bag 3 slot 7 with a lootable clam (itemID 5523) and slot 8 with a second clam.
	bagState["3:7"] = { itemID = 5523, iconFileID = 134432, hasLoot = true, isLocked = false }
	bagState["3:8"] = { itemID = 5523, iconFileID = 134432, hasLoot = true, isLocked = false }
	helpers:Update()

	assert(button:IsShown(), "open button shown for lootable item")
	assert(button:GetAttribute("type") == "macro", "open button keeps macro action type")
	assert(button:GetAttribute("macrotext") == "/use 3 7", "open button sets /use bag slot macrotext")
	assert(button:GetAttribute("item") == nil, "open button does not set deprecated item attribute")
	assert(button:GetAttribute("*type3") == "", "open button keeps middle-click mute suppression")

	-- PreClick with unchanged item does a single slot check without rescanning all bags.
	slotScans = 0
	button.scripts.PreClick(button, "LeftButton", true)
	assert(slotScans == 1 and button:GetAttribute("macrotext") == "/use 3 7",
		"PreClick keeps macrotext without rescanning when slot is still valid")

	-- If slot 3:7 empties before the debounced bag update runs, PreClick refreshes immediately to 3:8.
	bagState["3:7"] = nil
	button.scripts.PreClick(button, "LeftButton", true)
	assert(button.bag == 3 and button.slot == 8 and button:GetAttribute("macrotext") == "/use 3 8",
		"PreClick refreshes open button to next lootable slot when previous slot emptied")

	-- If a different item was moved into 3:8 before the click, PreClick clears macrotext and hides the button.
	bagState["3:8"] = { itemID = 6948, iconFileID = 134414, hasLoot = false, isLocked = false }
	button.scripts.PreClick(button, "LeftButton", true)
	assert(not button:IsShown() and button:GetAttribute("macrotext") == nil and rawget(button, "bag") == nil,
		"PreClick clears macrotext and hides button when slot now holds a different non-lootable item")

	-- Locked item in slot also triggers PreClick refresh, while MiddleButton and combat skip attribute changes.
	bagState["3:7"] = { itemID = 5523, iconFileID = 134432, hasLoot = true, isLocked = false }
	helpers:Update()
	assert(button:GetAttribute("macrotext") == "/use 3 7", "open button restored to 3:7")

	bagState["3:7"] = nil
	button.scripts.PreClick(button, "MiddleButton", true)
	assert(button:GetAttribute("macrotext") == "/use 3 7", "PreClick ignores MiddleButton")

	InCombatLockdown = function() return true end
	button.scripts.PreClick(button, "LeftButton", true)
	assert(button:GetAttribute("macrotext") == "/use 3 7", "PreClick skips attribute changes in combat")

	InCombatLockdown = function() return false end
	bagState["3:7"] = { itemID = 5523, iconFileID = 134432, hasLoot = true, isLocked = true }
	button.scripts.PreClick(button, "LeftButton", true)
	assert(not button:IsShown() and button:GetAttribute("macrotext") == nil,
		"PreClick clears macrotext when slot item becomes locked")

	-- Restore
	helpers.db.openButton = saved[1]
	helpers.db.openButtonMute = saved[2]
	helpers.cdb.openButtonMutedUntil = saved[3]
	C_Container.GetContainerNumSlots = saved[4]
	C_Container.GetContainerItemInfo = saved[5]
	C_Container.GetContainerItemQuestInfo = saved[6]
	C_TooltipInfo.GetBagItem = saved[7]
	C_Item.GetItemCount = saved[8]
	InCombatLockdown = saved[9]
	ns.IsEditModeActive = saved[10]
	helpers:Update()
	print("helpers open button macrotext and preclick OK")
end)()

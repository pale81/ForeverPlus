(function()
	-- Runtime stutter optimizations: lazy/incremental LootSources cache, single-pass nameplate scans,
	-- Blizzard_* exclusion in Info sampler, non-player Camera spellcast filtering, PortraitModes batching,
	-- SoloParty font reuse, and Waypoint unchanged-state skip.

	-- 1. LootSources: Record updates cache incrementally without rebuilding untouched items, DropsFrom stays lazy.
	local loot = ns:GetModule("LootSources")
	local savedSources, savedCount, savedMerged = ns.db.lootSources, loot.count, loot.merged
	ns.db.lootSources, loot.count, loot.merged = {}, 0, nil
	local itemA, itemB
	for id in pairs(ns.LootData.items) do
		if not itemA then itemA = id elseif not itemB then itemB = id break end
	end
	assert(itemA and itemB, "shipped loot table has at least two items")
	local rowA = ns.LootData.items[itemA][1]
	assert(loot.DropsFrom(itemA, rowA[1]), "lazy shipped drop lookup finds item")
	assert(loot.merged == nil, "DropsFrom does not eagerly build the full merge table")
	loot.Sources(itemA)
	loot.Sources(itemB)
	local cacheBefore = loot.merged
	local cachedB = cacheBefore.byItem[itemB]
	assert(cacheBefore and cacheBefore.byItem[itemA] and cachedB, "Sources caches only queried items")
	loot.Record("perf-g1", rowA[1], { itemA }, "Perf Mob")
	assert(loot.merged == cacheBefore, "Record keeps merge cache instance alive instead of wiping it")
	assert(cacheBefore.byItem[itemA] == nil and cacheBefore.byItem[itemB] == cachedB,
		"Record invalidates only the looted item and keeps untouched item caches")
	local updatedA
	for _, s in ipairs(loot.Sources(itemA)) do
		if s.key == rowA[1] then updatedA = s end
	end
	assert(updatedA and updatedA.drops == rowA[2] + 1 and updatedA.windows == rowA[3] + 1,
		"incremental Record update reflects new drop and window counts")
	ns.db.lootSources, loot.count, loot.merged = savedSources, savedCount, savedMerged

	-- 2. Quests: UpdateNameplate scans the unit tooltip at most once per nameplate.
	local quests = ns:GetModule("Quests")
	local updatePlate = uv(quests.RefreshNameplates, "UpdateNameplate")
	local qSaved = { C_NamePlate.GetNamePlateForUnit, C_QuestLog.UnitIsRelatedToActiveQuest, C_TooltipInfo.GetUnit,
		UnitIsPlayer, UnitCanAttack, quests.db.nameplateIcons }
	local tipCalls = 0
	local fakePlate = CreateFrame("Frame")
	C_NamePlate.GetNamePlateForUnit = function() return fakePlate end
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	C_TooltipInfo.GetUnit = function()
		tipCalls = tipCalls + 1
		return { lines = { { type = Enum.TooltipDataLineType.QuestObjective, leftText = "Felle: 2/5" } } }
	end
	UnitIsPlayer = function() return false end
	UnitCanAttack = function() return true end
	quests.db.nameplateIcons = true
	updatePlate("nameplate1")
	assert(tipCalls == 1, "UpdateNameplate scans the unit tooltip once instead of twice: " .. tipCalls)
	C_NamePlate.GetNamePlateForUnit, C_QuestLog.UnitIsRelatedToActiveQuest, C_TooltipInfo.GetUnit,
		UnitIsPlayer, UnitCanAttack, quests.db.nameplateIcons = unpack(qSaved, 1, 6)

	-- 3. Info: TrackAddon ignores Blizzard_* internal load-on-demand addons.
	local info = ns:GetModule("Info")
	local trackAddon = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "TrackAddon")
	local metrics = uv(trackAddon, "sessionMetrics")
	trackAddon("Blizzard_Professions", "Blizzard_Professions")
	assert(metrics["Blizzard_Professions"] == nil, "Blizzard_* LoD addons are not added to per-frame profiler sampling")

	-- 4. Camera: OnFastEvent ignores non-player UNIT_SPELLCAST_START / STOP.
	local camera = ns:GetModule("Camera")
	local onFast = uv(camera.Start, "OnFastEvent")
	local savedCamUpdate = camera.Update
	local camCalls = 0
	camera.Update = function() camCalls = camCalls + 1 end
	onFast(camera, "UNIT_SPELLCAST_START", "nameplate1")
	onFast(camera, "UNIT_SPELLCAST_STOP", "target")
	assert(camCalls == 0, "Camera ignores non-player spellcast events")
	onFast(camera, "UNIT_SPELLCAST_START", "player")
	assert(camCalls == 1, "Camera handles player spellcast events")
	camera.Update = savedCamUpdate

	-- 5. PortraitModes: non-Shift modifier events do not call native input setters.
	local pm = ns.PortraitModes
	local wheelFrame = _G.ForeverPlusPlayerPortraitWheel
	if wheelFrame then
		local updateInput = uv(pm.Refresh, "UpdatePortraitInput")
		local savedEnableWheel = wheelFrame.EnableMouseWheel
		local wheelCalls = 0
		wheelFrame.EnableMouseWheel = function(self, on)
			wheelCalls = wheelCalls + 1
			return savedEnableWheel(self, on)
		end
		updateInput(nil, "MODIFIER_STATE_CHANGED", "LCTRL")
		updateInput(nil, "MODIFIER_STATE_CHANGED", "LALT")
		assert(wheelCalls == 0, "PortraitModes ignores Ctrl/Alt modifier events")
		wheelFrame.EnableMouseWheel = savedEnableWheel
	end

	-- 6. Visuals: UpdateImbues skips C_TooltipInfo.GetInventoryItem when weapon enchant signature is unchanged.
	local visuals = ns:GetModule("Visuals")
	local updateActiveAuras = uv(uv(uv(visuals.OnLogin, "UpdateAuraWatch"), "QueueAuraUpdate"), "UpdateActiveAuras")
	local updateImbues = uv(updateActiveAuras, "UpdateImbues")
	local scanImbues = uv(updateImbues, "ScanImbues")
	local savedWeaponEnchant, savedWeaponSlot, savedInvTip = C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot, C_TooltipInfo.GetInventoryItem
	local invTipCalls = 0
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	C_Item.GetWeaponEnchantInfo = function(slot)
		if slot == 1 then return { { hasEnchant = true, enchantID = 29 } } end
		return {}
	end
	C_TooltipInfo.GetInventoryItem = function()
		invTipCalls = invTipCalls + 1
		return { lines = { { leftText = "Felsbeißer 3 (30 Min.)" } } }
	end
	setuv(scanImbues, "lastImbueSig", nil)
	updateImbues(false)
	assert(invTipCalls == 1, "first UpdateImbues reads weapon tooltip once")
	updateImbues(false)
	assert(invTipCalls == 1, "unchanged weapon enchants skip C_TooltipInfo.GetInventoryItem on UNIT_AURA")
	updateImbues(true)
	assert(invTipCalls == 2, "forced UpdateImbues (UNIT_INVENTORY_CHANGED) rescans weapon tooltip")
	C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot, C_TooltipInfo.GetInventoryItem = savedWeaponEnchant, savedWeaponSlot, savedInvTip

	-- 7. Quests: ScanQuests defers RefreshNameplates off the quest log scan frame.
	local scanQuests = uv(uv(quests.OnLogin, "QueueScan"), "ScanQuests")
	local savedAfter, savedRefreshPlates, savedNumEntries = C_Timer.After, quests.RefreshNameplates, C_QuestLog.GetNumQuestLogEntries
	local deferredPlates, plateRefreshes = {}, 0
	C_Timer.After = function(_, fn) deferredPlates[#deferredPlates + 1] = fn end
	quests.RefreshNameplates = function() plateRefreshes = plateRefreshes + 1 end
	C_QuestLog.GetNumQuestLogEntries = function() return 0 end
	quests.db.nameplateIcons = true
	scanQuests()
	assert(plateRefreshes == 0 and #deferredPlates == 1, "ScanQuests defers RefreshNameplates to the next frame")
	deferredPlates[1]()
	assert(plateRefreshes == 1, "deferred nameplate refresh runs on the next tick")
	C_Timer.After, quests.RefreshNameplates, C_QuestLog.GetNumQuestLogEntries = savedAfter, savedRefreshPlates, savedNumEntries

	-- 8. Minimap: MakeEmitterProvider attaches collection directly without InsertTable per row.
	local minimap = ns:GetModule("Minimap")
	local updateEmitterBtn = uv(minimap.OnOptionChanged, "UpdateEmitterButton")
	local refreshEmitters = uv(updateEmitterBtn, "RefreshEmitters")
	local applyMatches = uv(refreshEmitters, "ApplyEmitterMatches")
	local makeProvider = uv(applyMatches, "MakeEmitterProvider")
	local savedCreateDP = CreateDataProvider
	local insertCalls = 0
	CreateDataProvider = function(tbl)
		if tbl then insertCalls = insertCalls + #tbl end
		return { collection = tbl or {} }
	end
	local sample = { { 1, "a" }, { 2, "b" } }
	local dp = makeProvider(sample)
	assert(dp.collection == sample and insertCalls == 0, "MakeEmitterProvider attaches entries directly without per-row InsertTable")
	CreateDataProvider = savedCreateDP

	-- 9. Quests: QueueDistanceSort skips QueueSort when the player has not moved.
	local queueDistSort = uv(quests.UpdateTrackerSort, "QueueDistanceSort")
	local savedMapBest, savedMapPos = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition
	local savedQueueSort = uv(queueDistSort, "QueueSort")
	local distSorts, px, py = 0, 0.5, 0.5
	setuv(queueDistSort, "QueueSort", function() distSorts = distSorts + 1 end)
	setuv(queueDistSort, "lastDistMap", nil)
	C_Map.GetBestMapForUnit = function() return 1453 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end
	queueDistSort()
	queueDistSort()
	assert(distSorts == 1, "QueueDistanceSort skips repeated sort ticks while standing still: " .. distSorts)
	px = 0.51
	queueDistSort()
	assert(distSorts == 2, "QueueDistanceSort runs again once the player moves")
	setuv(queueDistSort, "QueueSort", savedQueueSort)
	C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = savedMapBest, savedMapPos

	-- 10. Landing: OnUpdate skips GetTime and Blocked checks while grounded.
	local landing = ns:GetModule("Landing")
	local landingUpdate = uv(landing.Apply, "OnUpdate")
	local savedFalling, savedSwimming = IsFalling, IsSwimming
	local swimCalls = 0
	IsFalling = function() return false end
	IsSwimming = function() swimCalls = swimCalls + 1 return false end
	landingUpdate()
	assert(swimCalls == 0, "Landing skips Blocked() checks when not falling")
	IsFalling, IsSwimming = savedFalling, savedSwimming

	-- 11. Mover: UpdateCatcherTarget skips GetMouseFoci when the cursor has not moved.
	local moverMod = ns:GetModule("Mover")
	local updateCatcherTarget = uv(moverMod.UpdateCatcher, "UpdateCatcherTarget")
	local savedCursor, savedFoci = GetCursorPosition, GetMouseFoci
	local fociCalls = 0
	GetCursorPosition = function() return 400, 300 end
	GetMouseFoci = function() fociCalls = fociCalls + 1 return {} end
	updateCatcherTarget(true)
	updateCatcherTarget(false)
	assert(fociCalls == 1, "Mover skips GetMouseFoci when cursor coordinates have not changed")
	GetCursorPosition, GetMouseFoci = savedCursor, savedFoci

	-- 12. Buffs: SyncWheelBindings skips ClearOverrideBindings / SetOverrideBindingClick when unchanged.
	local buffsMod = ns:GetModule("Buffs")
	local buffsUpdate = uv(buffsMod.OnLogin, "Update")
	local syncWheel = uv(buffsUpdate, "SyncWheelBindings")
	local savedClearBind, savedSetBind = ClearOverrideBindings, SetOverrideBindingClick
	local clearCalls, setCalls = 0, 0
	ClearOverrideBindings = function() clearCalls = clearCalls + 1 end
	SetOverrideBindingClick = function() setCalls = setCalls + 1 end
	setuv(syncWheel, "wheelBoundName", nil)
	syncWheel("ForeverPlusBuffButton1")
	syncWheel("ForeverPlusBuffButton1")
	assert(clearCalls == 1 and setCalls == 2, "Buffs updates wheel override bindings only when target changes")
	syncWheel(nil)
	syncWheel(nil)
	assert(clearCalls == 2 and setCalls == 2, "Buffs clears wheel override bindings only once")
	ClearOverrideBindings, SetOverrideBindingClick = savedClearBind, savedSetBind

	-- 13. Info: SampleAddonMetrics skips per-addon queries for foreign addons when GetOverallMetric shows no foreign work.
	local sampleMetrics = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "SampleAddonMetrics")
	local savedRead, savedOverall = C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric
	local savedIgnore = uv(sampleMetrics, "ignoreUntil")
	local savedReset = uv(sampleMetrics, "resetAt")
	local savedLoading = uv(sampleMetrics, "loadingScreen")
	local foreignReads = 0
	C_AddOnProfiler.GetAddOnMetric = function(name)
		if name ~= ns.name then foreignReads = foreignReads + 1 end
		return name == ns.name and 0.4 or 0
	end
	C_AddOnProfiler.GetOverallMetric = function() return 0.41 end
	setuv(sampleMetrics, "ignoreUntil", 0)
	setuv(sampleMetrics, "resetAt", nil)
	setuv(sampleMetrics, "loadingScreen", false)
	sampleMetrics(100, nil, nil, 99, nil, nil, nil, false)
	assert(foreignReads == 0, "SampleAddonMetrics skips foreign GetAddOnMetric calls on quiet frames: " .. foreignReads)
	C_AddOnProfiler.GetOverallMetric = function() return 3.5 end
	sampleMetrics(101, nil, nil, 100, nil, nil, nil, false)
	assert(foreignReads > 0, "SampleAddonMetrics queries foreign addons when overall time exceeds ForeverPlus")
	setuv(sampleMetrics, "ignoreUntil", savedIgnore)
	setuv(sampleMetrics, "resetAt", savedReset)
	setuv(sampleMetrics, "loadingScreen", savedLoading)
	C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric = savedRead, savedOverall

	-- 14. ChatIndent: OnSizeChanged skips height-only resizes (e.g. ChatMinimize folding) and re-wraps on width changes.
	local indentMod = ns:GetModule("ChatIndent")
	local onIndentResize = uv(uv(indentMod.Apply, "Hook"), "OnSizeChanged")
	local savedAfterIndent, savedIndentEnabled = C_Timer.After, indentMod.db.enabled
	local indentTimers, indentTransforms = 0, 0
	local fakeChat = {
		width = 320,
		GetWidth = function(self) return self.width end,
		TransformMessages = function() indentTransforms = indentTransforms + 1 end,
	}
	C_Timer.After = function(_, fn) indentTimers = indentTimers + 1 fn() end
	indentMod.db.enabled = true
	onIndentResize(fakeChat, 320, 120) -- first recorded width
	local afterFirst = indentTransforms
	onIndentResize(fakeChat, 320, 28)  -- height-only fold: must not re-wrap
	onIndentResize(fakeChat, 320, 120) -- height-only unfold: must not re-wrap
	assert(indentTimers == 1 and indentTransforms == afterFirst,
		"ChatIndent skips height-only OnSizeChanged events: " .. indentTimers .. "/" .. indentTransforms)
	fakeChat.width = 400
	onIndentResize(fakeChat, 400, 120) -- real width change: must re-wrap
	assert(indentTimers == 2, "ChatIndent still re-wraps when chat width changes: " .. indentTimers)
	C_Timer.After, indentMod.db.enabled = savedAfterIndent, savedIndentEnabled

	-- 15. GroupFinder: QueueLogUpdate coalesces bursts of QuestLogQuests_Update into one deferred pass.
	local gfMod = ns:GetModule("GroupFinder")
	local queueLog = uv(gfMod.OnLogin, "QueueLogUpdate")
	local savedAfterGF = C_Timer.After
	local gfQueued, gfTimers = nil, 0
	C_Timer.After = function(_, fn) gfQueued, gfTimers = fn, gfTimers + 1 end
	queueLog()
	queueLog()
	queueLog()
	assert(gfTimers == 1 and gfQueued ~= nil, "GroupFinder coalesces multiple QuestLogQuests_Update calls into one timer")
	gfQueued()
	queueLog()
	assert(gfTimers == 2, "GroupFinder accepts a new coalesced pass after the previous one runs")
	gfQueued()
	C_Timer.After = savedAfterGF

	-- 16. MapSymbols: DRAW_SYNC_LIMIT stays compact (<= 10) to avoid >5 ms synchronous bursts on map open.
	local drawFn = uv(ns.MapSymbols.Refresh, "Draw")
	assert(uv(drawFn, "DRAW_SYNC_LIMIT") <= 10, "MapSymbols keeps synchronous initial draw batch <= 10 symbols")

	print("runtime stutter optimizations OK")
end)()
;(function()
	-- CPU display accuracy: nested ns.Measured self-time, per-column colors, and ignoring <5 ms calls as peak/slow culprits.
	local info = ns:GetModule("Info")
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local onEvent = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local metrics = uv(uv(setup, "SampleAddonMetrics"), "sessionMetrics")
	local perf = uv(info.UpdatePerformance, "perfFrame")
	local resetSession = uv(info.ShowSpikes, "ResetSession")

	local savedTime, savedClock = GetTime, debugprofilestop
	local savedMetric, savedOverall = C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric
	local savedAddLine, savedAddDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine

	local now, clock = 3000, 0
	local ownMs = 0
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	C_AddOnProfiler.GetAddOnMetric = function(name) return name == ns.name and ownMs or 0 end
	C_AddOnProfiler.GetOverallMetric = function() return ownMs end

	onEvent(sampler, "LOADING_SCREEN_DISABLED")
	now = 3030
	resetSession()
	sample()

	-- 1. Nested ns.Measured calls record exclusive (self) time so an outer wrapper does not hide or double-count an inner spike.
	local inner = ns.Measured("Wanderlust: SetUIVisibility", function() clock = clock + 68.0 end)
	local outer = ns.Measured("Wanderlust: window activity", function()
		clock = clock + 0.1
		inner()
	end)
	now = 3031
	sample()
	outer()
	now, ownMs = 3032, 68.2
	sample()
	local own = metrics[ns.name]
	assert(own.peakCall == "Wanderlust: SetUIVisibility" and math.abs(own.peakCallTime - 68.0) < 0.01,
		"nested inner call is credited as peakCall instead of outer wrapper: " .. tostring(own.peakCall))
	assert(own.slowCall == "Wanderlust: SetUIVisibility", "inner call is credited as slowCall")

	-- 2. A short (<5 ms) call inside a later >5 ms frame must not replace slowCall or look like the culprit in the tooltip.
	local tiny = ns.Measured("Wanderlust: window activity", function() clock = clock + 0.2 end)
	tiny()
	now, ownMs = 3033, 15.5
	sample()
	assert(own.slowCall == "Wanderlust: SetUIVisibility" and own.slowFrame == 68.2,
		"a 0.2 ms call does not overwrite the last real >=5 ms slowCall")

	-- 3. Per-column coloring: low Avg stays green while high Max is red, and >5 ms scales with session rate (per minute).
	local savedG, savedO, savedR = GREEN_FONT_COLOR, ORANGE_FONT_COLOR, RED_FONT_COLOR
	GREEN_FONT_COLOR = { r = 0, g = 1, b = 0, WrapTextInColorCode = function(_, t) return "[G:" .. t .. "]" end }
	ORANGE_FONT_COLOR = { r = 1, g = 0.5, b = 0, WrapTextInColorCode = function(_, t) return "[O:" .. t .. "]" end }
	RED_FONT_COLOR = { r = 1, g = 0, b = 0, WrapTextInColorCode = function(_, t) return "[R:" .. t .. "]" end }
	own.recentTotal, own.recentCount, own.slow = 0.07 * 60, 60, 19
	local doubleLines, singleLines = {}, {}
	GameTooltip.AddDoubleLine = function(_, left, right)
		doubleLines[#doubleLines + 1] = { left = tostring(left), right = tostring(right) }
	end
	GameTooltip.AddLine = function(_, line)
		singleLines[#singleLines + 1] = tostring(line)
	end
	-- After 41 minutes, 19 spikes (~0.46/min) are green; in a 10-minute session (~1.9/min) they are orange;
	-- in a 3-minute session (~6.3/min) they are red.
	local function OwnCpuRow(atNow)
		wipe(doubleLines)
		now = atNow
		perf:GetScript("OnEnter")(perf)
		for _, row in ipairs(doubleLines) do
			if row.left == own.title then return row.right end
		end
	end
	assert(OwnCpuRow(3032 + 41 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[G:19×]"),
		"41-minute session keeps sparse >5 ms count green")
	assert(OwnCpuRow(3032 + 10 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[O:19×]"),
		"10-minute session flags 1.9/min >5 ms rate as orange")
	assert(OwnCpuRow(3032 + 3 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[R:19×]"),
		"3-minute session flags 6.3/min >5 ms rate as red")
	GREEN_FONT_COLOR, ORANGE_FONT_COLOR, RED_FONT_COLOR = savedG, savedO, savedR

	local joinedSingle = table.concat(singleLines, "\n")
	local shortPrefix = ns.L.INFO_SPIKES_SHORT_CALLS:format(ns.SLOW_MS)
	assert(joinedSingle:find(shortPrefix .. " (Wanderlust: window activity (0.2 ms))", 1, true),
		"tooltip moment marks sub-5 ms captured calls clearly instead of blaming them")

	resetSession()
	onEvent(sampler, "LOADING_SCREEN_ENABLED")
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = savedAddLine, savedAddDouble
	C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric = savedMetric, savedOverall
	GetTime, debugprofilestop = savedTime, savedClock
	print("cpu display accuracy OK")
end)()
;(function()
	-- Guiding Wind: bearing/direction vectors, biome mapping, instance & combat guards,
	-- waypoint arrow suppression, sound rules, idle cleanup, bindings/commands and PortraitModes.
	local wind = ns:GetModule("GuidingWind")
	local way = ns:GetModule("Waypoint")
	local pm = ns.PortraitModes
	assert(wind and way, "GuidingWind and Waypoint modules loaded")

	-- 1. Options, defaults, NEU flags and settings page registration.
	assert(wind.db.enabled == true and wind.db.autoGusts == true
		and wind.db.biomeParticles == true and wind.db.sound == true and wind.db.interval == 14
		and wind.db.strength == 75, "GuidingWind defaults are sensible and non-breaking")
	local foundOwnPage = false
	for _, page in ipairs(ns.SettingsPages) do
		if page.title == ns.L.WIND_TITLE and #page == 1 and page[1][1] == "GuidingWind" then
			foundOwnPage = true
		end
	end
	assert(foundOwnPage, "GuidingWind has its own dedicated settings page")
	local intervalOpt
	for _, opt in ipairs(wind.options) do
		if opt.key then
			assert(opt.new == true, "new GuidingWind option carries new=true: " .. tostring(opt.key))
		end
		if opt.key == "interval" then intervalOpt = opt end
	end
	assert(intervalOpt and intervalOpt.min == 5 and intervalOpt.max == 60, "interval slider covers 5..60 s")
	assert(type(ForeverPlus_SummonGuidingWind) == "function"
		and BINDING_NAME_FOREVERPLUS_GUIDINGWIND == ns.L.WIND_BINDING, "key binding hook and label registered")

	-- 2. Angle normalization and screen-space direction vector.
	local function near(a, b) return math.abs(a - b) < 1e-6 end
	local dx, dy, mode = wind.DirectionVector(0)
	assert(near(dx, 0) and near(dy, 1) and mode == "ahead", "0 rad points straight ahead (up)")
	dx, dy, mode = wind.DirectionVector(math.pi / 2)
	assert(near(dx, -1) and near(dy, 0) and mode == "left", "+pi/2 points left")
	dx, dy, mode = wind.DirectionVector(-math.pi / 2)
	assert(near(dx, 1) and near(dy, 0) and mode == "right", "-pi/2 points right")
	dx, dy, mode = wind.DirectionVector(math.pi)
	assert(near(dx, 0) and near(dy, -1) and mode == "behind", "pi points behind (down)")
	assert(near(wind.NormalizeAngle(3 * math.pi), math.pi)
		and near(wind.NormalizeAngle(-3 * math.pi / 2), math.pi / 2), "angle wraps into (-pi, pi]")

	-- 2b. Perspective and sweeping ribbon tracks (EvaluateTrack):
	-- Ahead converges toward the upper horizon and shrinks depthScale with distance.
	local ax0, ay0, as0 = wind.EvaluateTrack(-0.24, 0, 0, 1, 0, 0.08, 0, 0, 1.0)
	local ax1, ay1, as1 = wind.EvaluateTrack(-0.24, 0, 0, 1, 0, 0.92, 0, 0, 1.0)
	assert(ay1 > ay0 + 0.25 and math.abs(ax1 - 0.5) < math.abs(ax0 - 0.5) and as1 < as0 * 0.7,
		"ahead wind converges toward upper horizon with perspective foreshortening")
	-- Right sweeps wide across the viewport from left toward right.
	local rx0, _, _ = wind.EvaluateTrack(0, 0, 0, 1, 0, 0.05, -math.pi / 2, 0, 1.0)
	local rx1, _, _ = wind.EvaluateTrack(0, 0, 0, 1, 0, 0.95, -math.pi / 2, 0, 1.0)
	assert(rx1 - rx0 > 0.65, "sideways wind sweeps wide across the viewport")

	-- 3. Biome mapping (direct zones, parentMapID sub-map walk, unknown fallback).
	local savedMapInfo = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(id)
		if id == 9901 then return { mapID = 9901, parentMapID = 1426, name = "Coldridge Cave" } end
		if id == 9999 then return { mapID = 9999, parentMapID = 0, name = "Unknown" } end
		return { mapID = id, parentMapID = 0, name = "Zone " .. tostring(id) }
	end
	assert(wind.BiomeForMap(1429) == "forest", "Elwynn Forest -> forest")
	assert(wind.BiomeForMap(1447) == "autumn", "Azshara -> autumn")
	assert(wind.BiomeForMap(1452) == "snow", "Winterspring -> snow")
	assert(wind.BiomeForMap(1446) == "desert", "Tanaris -> desert")
	assert(wind.BiomeForMap(1428) == "volcanic", "Burning Steppes -> volcanic")
	assert(wind.BiomeForMap(1431) == "marsh", "Duskwood -> marsh")
	assert(wind.BiomeForMap(9901) == "snow", "sub-map inherits parent zone biome (Dun Morogh -> snow)")
	assert(wind.BiomeForMap(9999) == "neutral" and wind.BiomeForMap(nil) == "neutral", "unknown maps fall back to neutral")

	-- 4. Live waypoint guidance, WorldFrame parent, sound rules, idle stop and arrow suppression.
	local savedBestMap, savedPlayerPos, savedWorldSize = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize
	local savedHasWp, savedGetWp, savedSetWp, savedClearWp, savedCanWp =
		C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, C_Map.CanSetUserWaypointOnMap
	local savedFacing, savedInstance, savedCombat, savedTaxi = GetPlayerFacing, rawget(_G, "IsInInstance"), InCombatLockdown, rawget(_G, "UnitOnTaxi")
	local savedPlaySoundFile, savedStopSound, savedTimer, savedTime, savedPrintAlways, savedPrint =
		PlaySoundFile, rawget(_G, "StopSound"), C_Timer.NewTimer, GetTime, ns.PrintAlways, ns.Print
	local savedUiMapPoint, savedSuperTrack = UiMapPoint, C_SuperTrack

	local currentMap, playerX, playerY, facing = 1429, 0.5, 0.5, 0
	local inInstance, inCombat, onTaxi, nowTime = false, false, false, 500
	local userWp, soundsPlayed, timers, printed = nil, {}, {}, {}

	C_Map.GetBestMapForUnit = function() return currentMap end
	C_Map.GetPlayerMapPosition = function(mapID)
		if mapID == currentMap then return { GetXY = function() return playerX, playerY end } end
		return nil
	end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.HasUserWaypoint = function() return userWp ~= nil end
	C_Map.GetUserWaypoint = function() return userWp end
	C_Map.SetUserWaypoint = function(pt) userWp = pt return true end
	C_Map.ClearUserWaypoint = function() userWp = nil end
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
	GetPlayerFacing = function() return facing end
	IsInInstance = function() return inInstance, inInstance and "party" or "none" end
	InCombatLockdown = function() return inCombat end
	UnitOnTaxi = function() return onTaxi end
	GetTime = function() return nowTime end
	PlaySoundFile = function(id, channel)
		soundsPlayed[#soundsPlayed + 1] = { id = id, channel = channel }
		return true, #soundsPlayed
	end
	StopSound = function() end
	C_Timer.NewTimer = function(delay, fn)
		local t = { delay = delay, fn = fn, cancelled = false }
		function t:Cancel() self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end
	ns.PrintAlways = function(msg, ...) printed[#printed + 1] = select("#", ...) > 0 and msg:format(...) or msg end
	ns.Print = ns.PrintAlways
	WorldMapFrame:Hide()

	-- No waypoint yet: manual summon reports clearly, plays no sound and leaves overlay idle.
	local ok, reason = wind.Summon(true)
	assert(not ok and reason == "none" and #soundsPlayed == 0 and not wind.GetState().active,
		"manual summon without waypoint prints hint and stays idle")
	assert(printed[#printed] == ns.L.WIND_NO_WAYPOINT, "no-waypoint hint shown")

	-- Set waypoint to the east (right when facing north = -pi/2).
	way.Set(80, 50, "Goldhain")
	local arrow = _G.ForeverPlusWaypointArrow
	assert(wind.HidesWaypointArrow() and (not arrow or not arrow:IsShown()),
		"GuidingWind always replaces and hides the waypoint arrow while enabled")
	assert(wind.GetState().timerActive, "auto gust timer starts once a waypoint exists")

	-- Manual summon triggers gust pointing right (-pi/2), forest biome, and plays a real wind sound.
	ok, reason = wind.Summon(true)
	assert(ok and reason == "waypoint", "manual summon succeeds for active waypoint")
	local state = wind.GetState()
	local overlay = _G.ForeverPlusGuidingWind
	assert(state.active and state.rootShown and state.manual and state.biome == "forest" and near(state.angle, -math.pi / 2),
		"gust runs toward east (-pi/2) with forest biome")
	assert(#soundsPlayed == 1 and soundsPlayed[1].channel == "SFX", "manual summon plays wind sound")
	-- Advancing mid-gust (0.7 s in 0.1 s frames, respecting delta clamping) renders connected SimpleLine ribbon segments.
	local onUpdate = overlay:GetScript("OnUpdate")
	for _ = 1, 7 do
		onUpdate(overlay, 0.1)
	end
	local activeLines = 0
	for _, line in ipairs(overlay.lines or {}) do
		if line:IsShown() then
			assert(line.startPoint and line.endPoint and (line.thickness or 0) >= 1.0,
				"visible ribbon segment has start/end points and positive thickness")
			activeLines = activeLines + 1
		end
	end
	assert(activeLines >= 100, "manual gust renders all 6 multi-ribbon silk streams: " .. tostring(activeLines))

	-- Advancing past the gust duration hides the overlay and all ribbon lines cleanly (no idle OnUpdate).
	for _ = 1, 35 do
		if not overlay:IsShown() then break end
		onUpdate(overlay, 0.1)
	end
	assert(not overlay:IsShown() and not wind.GetState().active, "overlay hides itself after gust completes")
	for _, line in ipairs(overlay.lines or {}) do
		assert(not line:IsShown(), "all ribbon lines hide cleanly once gust ends")
	end

	-- Automatic gust fires silently (no sound) out of combat, uses calmer subset of ribbons, and respects guards.
	nowTime = nowTime + 5
	local latestTimer = timers[#timers]
	assert(latestTimer and not latestTimer.cancelled and latestTimer.delay == 14, "auto gust scheduled for configured interval")
	latestTimer.fn()
	assert(wind.GetState().active and not wind.GetState().manual and #soundsPlayed == 1,
		"automatic gust runs silently in calmer mode without playing sound")
	for _ = 1, 7 do
		onUpdate(overlay, 0.1)
	end
	local autoLines = 0
	for _, line in ipairs(overlay.lines or {}) do
		if line:IsShown() then autoLines = autoLines + 1 end
	end
	assert(autoLines > 0 and autoLines < activeLines, "automatic gust uses calmer subset of ribbons than manual summon")
	for _ = 1, 35 do
		if not overlay:IsShown() then break end
		onUpdate(overlay, 0.1)
	end

	-- Combat guard blocks automatic gusts.
	inCombat = true
	timers[#timers].fn()
	assert(not wind.GetState().active, "automatic gust does not fire during combat")
	inCombat = false

	-- Instance / nil facing guard catches missing GetPlayerFacing cleanly.
	inInstance = true
	facing = nil
	ok, reason = wind.Summon(true)
	assert(not ok and reason == "no_facing" and not wind.GetState().active, "nil facing in instance is caught safely")
	assert(printed[#printed] == ns.L.WIND_NO_DIRECTION, "instance/no-facing message shown")
	-- Preview (/fp wind test links) still works even without facing.
	nowTime = nowTime + 5
	SlashCmdList.FOREVERPLUS("wind test links")
	assert(wind.GetState().active and near(wind.GetState().angle, math.pi / 2) and #soundsPlayed == 2,
		"/fp wind test links runs preview gust to the left with sound")
	inInstance = false
	facing = 0

	-- Waypoint arrow suppression & clean restore on disable.
	assert(wind.HidesWaypointArrow() and (not arrow or not arrow:IsShown()), "GuidingWind suppresses the waypoint arrow")
	ns.SetOption("GuidingWind", "enabled", false)
	arrow = _G.ForeverPlusWaypointArrow
	assert(not wind.HidesWaypointArrow() and arrow and arrow:IsShown(), "disabling GuidingWind restores the waypoint arrow")
	assert(not wind.GetState().active and not wind.GetState().timerActive and not overlay:IsShown(),
		"disabling GuidingWind stops active gust and cancels auto timer")

	-- Re-enable and verify arrival clears the waypoint even while arrow is hidden.
	ns.SetOption("GuidingWind", "enabled", true)
	assert(not arrow:IsShown(), "re-enabling GuidingWind hides the waypoint arrow again")
	playerX, playerY = 0.799, 0.5
	ok, reason = wind.Summon(true)
	assert(not ok and reason == "arrived" and way.Target() == nil, "arrival check clears waypoint when close")

	-- PortraitModes: guidingWind has its own dedicated mode slot with WoW gale icon.
	assert(pm.FeatureMode("guidingWind") == "guidingWind" and pm.IsFeatureSelected("guidingWind"),
		"GuidingWind is registered in its own portrait mode and selected by default")
	assert(pm.ModeIcon("guidingWind") == 236154, "GuidingWind mode uses verified WoW gale icon 236154")
	assert(pm.MoveFeature("guidingWind", "wanderlust") and pm.FeatureMode("guidingWind") == "wanderlust",
		"GuidingWind can be reassigned onto Wanderlust mode")
	pm.ResetAssignments()
	assert(pm.FeatureMode("guidingWind") == "guidingWind" and pm.IsFeatureSelected("guidingWind"),
		"ResetAssignments restores GuidingWind to its own portrait mode")

	-- Restore state cleanly.
	way.Clear()
	ns.SetOption("GuidingWind", "enabled", true)
	C_Map.GetMapInfo, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize =
		savedMapInfo, savedBestMap, savedPlayerPos, savedWorldSize
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, C_Map.CanSetUserWaypointOnMap =
		savedHasWp, savedGetWp, savedSetWp, savedClearWp, savedCanWp
	GetPlayerFacing, IsInInstance, InCombatLockdown, UnitOnTaxi = savedFacing, savedInstance, savedCombat, savedTaxi
	PlaySoundFile, StopSound, C_Timer.NewTimer, GetTime, ns.PrintAlways, ns.Print =
		savedPlaySoundFile, savedStopSound, savedTimer, savedTime, savedPrintAlways, savedPrint
	UiMapPoint, C_SuperTrack = savedUiMapPoint, savedSuperTrack
	print("guiding wind OK")
end)()
;(function()
	local tooltip = ns:GetModule("Tooltip")
	local showHover = uv(tooltip.OnLogin, "ShowHoverName")
	local objectCall = uv(tooltip.OnInitialize, "OnObjectTooltip")
	local frame = uv(showHover, "GetHover")()

	local saved = {
		rawget(_G, "UnitEffectiveLevel"), rawget(_G, "UnitLevel"), rawget(_G, "UnitIsCorpse"),
		rawget(_G, "UnitIsWildBattlePet"), rawget(_G, "UnitIsBattlePetCompanion"),
		rawget(_G, "UnitExists"), rawget(_G, "UnitName"), rawget(_G, "UnitIsPlayer"),
		rawget(_G, "issecretvalue"), C_Texture.GetAtlasInfo,
		frame.SetSize, frame.Level.SetText, frame.Skull.SetSize,
		tooltip.db.hoverLevel, tooltip.db.hoverName, tooltip.db.hoverObjects,
	}

	local effectiveLevel, rawLevel, corpse, wildPet, companionPet = 13, 13, false, false, false
	local exists, unitName, secretVal = true, "Onyxia", nil
	local atlasInfo = { width = 16, height = 20 }
	local levelText, frameW, skullW, skullH

	UnitEffectiveLevel = function() return effectiveLevel end
	UnitLevel = function() return rawLevel end
	UnitIsCorpse = function() return corpse end
	UnitIsWildBattlePet = function() return wildPet end
	UnitIsBattlePetCompanion = function() return companionPet end
	UnitExists = function() return exists end
	UnitName = function() return unitName end
	UnitIsPlayer = function() return false end
	issecretvalue = function(v) return secretVal ~= nil and v == secretVal end
	C_Texture.GetAtlasInfo = function(atlas) return atlas == "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon" and atlasInfo or nil end
	frame.SetSize = function(self, w, h) frameW = w; self.w, self.h = w, h end
	frame.Level.SetText = function(_, text) levelText = text end
	frame.Skull.SetSize = function(_, w, h) skullW, skullH = w, h end
	tooltip.db.hoverName, tooltip.db.hoverLevel, tooltip.db.hoverObjects = true, true, true

	-- 1. Effective level overrides raw UnitLevel (matches TargetFrameMixin:CheckLevel).
	effectiveLevel, rawLevel = 25, 40
	local lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == 25 and not isSkull, "effective level is used instead of raw UnitLevel")
	showHover()
	assert(levelText == 25 and frame.Level:IsShown() and not frame.Skull:IsShown(),
		"normal effective level shows text and hides skull")

	-- 2. Skull target: UnitEffectiveLevel <= 0 shows skull even when UnitLevel returns a positive number.
	effectiveLevel, rawLevel = -1, 63
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "negative effective level marks skull despite positive UnitLevel")
	showHover()
	assert(not frame.Level:IsShown() and levelText == "" and frame.Skull:IsShown(),
		"skull target hides level text and shows skull texture")
	assert(skullW == 11 and skullH == 14 and frameW == 82 + 11 + 4,
		"skull texture keeps atlas aspect ratio and reserves layout width")

	-- 3. Zero effective level also shows skull.
	effectiveLevel, rawLevel = 0, 60
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "zero effective level shows skull")

	-- 4. Corpse shows skull even when effective level is positive (matches TargetFrameMixin:CheckLevel).
	effectiveLevel, rawLevel, corpse = 18, 18, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "corpse shows skull even with positive effective level")
	showHover()
	assert(frame.Skull:IsShown() and not frame.Level:IsShown(), "corpse renders skull on hover frame")
	corpse = false

	-- 5. Battle pets hide level and skull (matches Camelot CheckBattlePet).
	effectiveLevel, wildPet = 1, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "wild battle pet shows neither level nor skull")
	showHover()
	assert(not frame.Level:IsShown() and not frame.Skull:IsShown(), "wild battle pet hides level and skull")
	wildPet, companionPet = false, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "companion battle pet shows neither level nor skull")
	companionPet = false

	-- 6. Missing atlas falls back cleanly to "??".
	effectiveLevel, atlasInfo = -1, nil
	showHover()
	assert(frame.Level:IsShown() and levelText == "??" and not frame.Skull:IsShown(),
		"missing skull atlas falls back to ?? text")
	atlasInfo = { width = 16, height = 20 }

	-- 7. Secret values on level or flags hide level and skull without error.
	secretVal = "SECRET_LEVEL"
	effectiveLevel = secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret effective level hides level safely")
	effectiveLevel, corpse = 20, secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret corpse flag hides level safely")
	corpse, wildPet = false, secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret battle pet flag hides level safely")
	wildPet, secretVal = false, nil

	-- 8. Toggling hoverLevel off hides skull immediately; switching to object hides skull too.
	effectiveLevel = -1
	showHover()
	assert(frame.Skull:IsShown(), "skull shown before option toggle")
	tooltip.db.hoverLevel = false
	tooltip:OnOptionChanged("hoverLevel")
	assert(not frame.Skull:IsShown() and not frame.Level:IsShown(), "disabling hoverLevel hides skull immediately")
	tooltip.db.hoverLevel = true
	tooltip:OnOptionChanged("hoverLevel")
	assert(frame.Skull:IsShown(), "reenabling hoverLevel restores skull immediately")
	exists = false
	objectCall(GameTooltip)
	assert(not frame.Skull:IsShown() and not frame.Level:IsShown(), "object hover hides skull texture")

	UnitEffectiveLevel, UnitLevel, UnitIsCorpse, UnitIsWildBattlePet, UnitIsBattlePetCompanion,
		UnitExists, UnitName, UnitIsPlayer, issecretvalue, C_Texture.GetAtlasInfo,
		frame.SetSize, frame.Level.SetText, frame.Skull.SetSize,
		tooltip.db.hoverLevel, tooltip.db.hoverName, tooltip.db.hoverObjects = unpack(saved, 1, 16)
	print("hover skull level OK")
end)()
-- Auction house: total profit/loss for quantities > 1 (sell summary, cells, quick buy)
;(function()
	local A = ns:GetModule("Auction")
	local savedMoney = GetMoneyString
	local savedIsCached, savedGetInfo = C_Item.IsItemDataCachedByID, C_Item.GetItemInfo
	local savedDoesExist, savedGetItemID, savedGetStack = C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetStackCount
	local savedAddLine, savedOwner = GameTooltip.AddLine, GameTooltip.SetOwner
	local savedProfit, savedWarning, savedQty = A.db.vendorProfit, A.db.vendorWarning, A.db.vendorQuickBuyQty
	GetMoneyString = function(v) return tostring(v) .. "c" end

	-- SellSummary: quantity == 1 stays compact without repetition
	local s1 = A.SellSummary(306, 400, true, true, 1)
	assert(s1.text == ns.L.AUCTION_SELL_PROFIT:format("+74c") and s1.subtext == nil and #s1.lines == 4,
		"quantity 1 remains compact without total line")

	-- SellSummary: quantity > 1 shows per-item + total profit and full stack calculation
	local s20 = A.SellSummary(306, 400, true, true, 20)
	assert(s20.text == ns.L.AUCTION_SELL_PROFIT:format("+74c"), "quantity 20 per-item text")
	assert(s20.subtext == ns.L.AUCTION_SELL_PROFIT_TOTAL:format("+1480c", 20) and s20.total == 1480,
		"quantity 20 total profit subtext: " .. tostring(s20.subtext))
	if GetLocale() == "deDE" then
		assert(s20.text == "Gewinn: +74c pro Stück" and s20.subtext == "Gewinn: +1480c pro 20",
			"deDE sell profit wording: " .. s20.text .. " / " .. s20.subtext)
	else
		assert(s20.text == "Profit: +74c per item" and s20.subtext == "Profit: +1480c per 20",
			"enUS sell profit wording: " .. s20.text .. " / " .. s20.subtext)
	end
	assert(#s20.lines == 5, "quantity 20 tooltip has 5 calculation lines")
	assert(s20.lines[1]:find("6120c", 1, true), "merchant total in tooltip")
	assert(s20.lines[2]:find("8000c", 1, true), "gross total in tooltip")
	assert(s20.lines[3]:find("7600c", 1, true), "net total after 5% cut in tooltip")
	assert(s20.lines[5] == ns.L.AUCTION_SELL_RESULT_TOTAL:format(20, "+1480c"), "result total line")

	-- 5% fee rounding on total vs per-unit: 10 * 31c = 310c -> floor(310 * 0.95) = 294c, vendor 250c -> +44c
	local sRound = A.SellSummary(25, 31, true, true, 10)
	assert(sRound.text == ns.L.AUCTION_SELL_PROFIT:format("+4c"), "unit profit 29-25=+4c")
	assert(sRound.total == 44 and sRound.subtext == ns.L.AUCTION_SELL_PROFIT_TOTAL:format("+44c", 10),
		"total profit uses exact 5% fee on total gross (294 - 250 = 44)")

	-- Below vendor warning with quantity > 1
	local sWarn = A.SellSummary(306, 300, true, true, 5)
	assert(sWarn.text == ns.L.AUCTION_SELL_BELOW:format("−21c"), "warning per item")
	assert(sWarn.subtext == ns.L.AUCTION_SELL_LOSS_TOTAL:format("−105c", 5) and #sWarn.lines == 6,
		"warning total loss and below-vendor note")

	-- Loss without warning option and quantity > 1
	local sLoss = A.SellSummary(306, 300, true, false, 4)
	assert(sLoss.text == ns.L.AUCTION_SELL_LOSS:format("−21c") and sLoss.subtext == ns.L.AUCTION_SELL_LOSS_TOTAL:format("−84c", 4),
		"loss total without warning option")
	if GetLocale() == "deDE" then
		assert(sLoss.text == "Verlust: −21c pro Stück" and sLoss.subtext == "Verlust: −84c pro 4",
			"deDE sell loss wording: " .. sLoss.text .. " / " .. sLoss.subtext)
	else
		assert(sLoss.text == "Loss: −21c per item" and sLoss.subtext == "Loss: −84c per 4",
			"enUS sell loss wording: " .. sLoss.text .. " / " .. sLoss.subtext)
	end

	-- No price entered with quantity > 1: still shows total merchant value, no fake total profit
	local sNoPrice = A.SellSummary(306, nil, true, true, 10)
	assert(sNoPrice.text == ns.L.AUCTION_SELL_NO_PRICE and sNoPrice.subtext == nil and sNoPrice.lines[1]:find("3060c", 1, true),
		"no price keeps prompt and shows total merchant value")

	-- Commodity unit price cell & buyout cell: quantity > 1 carries total profit, quantity == 1 does not
	A.db.vendorProfit, A.db.vendorWarning = true, true
	local vendors = { [99001] = 300, [99002] = 60 }
	C_Item.IsItemDataCachedByID = function(id) return vendors[id] ~= nil end
	C_Item.GetItemInfo = function(id)
		if vendors[id] then return "Item", nil, nil, nil, nil, nil, nil, nil, nil, nil, vendors[id] end
	end
	local onUnit = uv(A.OnLogin, "OnUnitPriceCell")
	local onMin = uv(A.OnLogin, "OnMinPriceCell")
	local onBuyout = uv(A.OnLogin, "OnBuyoutCell")
	local unitCell1 = NewFrame("Frame")
	onUnit(unitCell1, { itemID = 99001, unitPrice = 200, quantity = 15 })
	assert(unitCell1.foreverPlusVendorProfit and unitCell1.foreverPlusVendorProfit.unit == 100
		and unitCell1.foreverPlusVendorProfit.quantity == 15 and unitCell1.foreverPlusVendorProfit.total == 1500,
		"commodity unit price cell computes total profit for quantity > 1")
	local unitCellSingle = NewFrame("Frame")
	onUnit(unitCellSingle, { itemID = 99001, unitPrice = 200, quantity = 1 })
	assert(unitCellSingle.foreverPlusVendorProfit and unitCellSingle.foreverPlusVendorProfit.unit == 100
		and unitCellSingle.foreverPlusVendorProfit.total == nil,
		"commodity unit price cell omits total for quantity == 1")
	local minCellEmpty = NewFrame("Frame")
	onMin(minCellEmpty, { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 0 })
	assert(rawget(minCellEmpty, "foreverPlusVendorProfit") == nil, "min price cell ignores totalQuantity == 0")
	local buyoutCell = NewFrame("Frame")
	onBuyout(buyoutCell, { itemKey = { itemID = 99002 }, buyoutAmount = 101, quantity = 2 })
	assert(buyoutCell.foreverPlusVendorProfit and buyoutCell.foreverPlusVendorProfit.unit == 10
		and buyoutCell.foreverPlusVendorProfit.total == 19,
		"buyout cell uses exact total (2*60 - 101 = 19)")

	-- Quick buy tooltip: count == 1 stays single profit line, count > 1 adds per-item and total
	local tipLines = {}
	GameTooltip.SetOwner = function() wipe(tipLines) end
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	local onQuickCell = uv(A.OnLogin, "OnQuickBuyCell")
	local showQuickTip = uv(onQuickCell, "ShowQuickBuyTooltip")
	A.db.vendorQuickBuyQty = 1
	showQuickTip({ rowData = { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 10 } })
	assert(#tipLines == 2 and tipLines[2] == ns.L.AUCTION_QUICK_BUY_PROFIT:format("100c"),
		"quick buy qty 1 shows compact single profit line")
	A.db.vendorQuickBuyQty = 5
	showQuickTip({ rowData = { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 10 } })
	assert(#tipLines == 3 and tipLines[2] == ns.L.AUCTION_VENDOR_PROFIT:format("100c")
		and tipLines[3] == ns.L.AUCTION_QUICK_BUY_PROFIT_TOTAL:format(5, "500c"),
		"quick buy qty > 1 shows per-item and total profit")

	-- UpdateSellWarning on multisell ItemSellFrame (GetTotalPrice == price * quantity) keeps per-item price
	local updateSell = uv(uv(A.OnLogin, "HookSellFrames"), "UpdateSellWarning")
	C_Item.DoesItemExist = function() return true end
	C_Item.GetItemID = function() return 99001 end
	C_Item.GetStackCount = function() return 1 end
	local itemSellFrame = NewFrame("Frame")
	itemSellFrame.PostButton = NewFrame("Button")
	itemSellFrame.GetItem = function() return {} end
	itemSellFrame.GetQuantity = function() return 3 end
	itemSellFrame.GetPrice = function() return nil, 400 end
	itemSellFrame.GetTotalPrice = function() return 1200 end
	local shownText
	itemSellFrame.CreateFontString = function()
		local fs = NewFrame("FontString")
		fs.SetText = function(_, t) shownText = t end
		return fs
	end
	updateSell(itemSellFrame, 400)
	assert(shownText and shownText:find("+80c", 1, true) and shownText:find("+240c", 1, true),
		"multisell item frame preserves unit price and displays per-item + total: " .. tostring(shownText))

	GetMoneyString = savedMoney
	C_Item.IsItemDataCachedByID, C_Item.GetItemInfo = savedIsCached, savedGetInfo
	C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetStackCount = savedDoesExist, savedGetItemID, savedGetStack
	GameTooltip.AddLine, GameTooltip.SetOwner = savedAddLine, savedOwner
	A.db.vendorProfit, A.db.vendorWarning, A.db.vendorQuickBuyQty = savedProfit, savedWarning, savedQty
	print("auction stack profit OK")
end)()

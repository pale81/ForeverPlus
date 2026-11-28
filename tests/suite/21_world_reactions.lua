(function()
	-- WorldReactions: surfacing water droplets, campfire warmth/embers, worn armor clinking.
	local wr = ns:GetModule("WorldReactions")
	assert(wr, "WorldReactions module loaded")
	assert(wr.db.enabled == true and wr.db.waterDrops == true and wr.db.campfireGlow == true
		and wr.db.weaponSheathSound == nil and wr.db.armorRattle == true and wr.db.intensity == 75,
		"WorldReactions sensible defaults without weapon sheath sound")
	assert(wr.StepSheath == nil and wr.WeaponSoundKind == nil and wr.PlayWeaponSound == nil,
		"weapon sheath sound helpers removed")

	-- Registered on a settings page under Roleplay & every keyed option carries new = true.
	local foundOnPage = false
	for _, page in ipairs(ns.SettingsPages or {}) do
		for _, entry in ipairs(page) do
			if entry[1] == "WorldReactions" then foundOnPage = true end
		end
	end
	assert(foundOnPage, "WorldReactions is registered on a settings page")
	local buttonCount = 0
	for _, opt in ipairs(wr.options or {}) do
		assert(opt.key ~= "weaponSheathSound", "weaponSheathSound option removed")
		if opt.key then
			assert(opt.new == true, "new WorldReactions option carries new=true: " .. tostring(opt.key))
		elseif opt.type == "button" then
			buttonCount = buttonCount + 1
		end
	end
	assert(buttonCount == 3, "WorldReactions provides preview/test buttons for all three reactions")

	-- 1. Water emergence state machine
	local ws = { graceUntil = 5 }
	assert(not wr.StepWater(ws, true, true, 1.0, false), "water suppressed during login grace")
	assert(not wr.StepWater(ws, false, false, 4.0, false), "emerging during login grace stays silent")
	assert(not wr.StepWater(ws, true, true, 10.0, false), "diving down does not trigger yet")
	assert(not wr.StepWater(ws, false, true, 10.2, false), "brief dip below 0.35s does not trigger")
	assert(not wr.StepWater(ws, true, true, 11.0, false), "submerge again")
	assert(wr.StepWater(ws, false, true, 11.6, false), "surfacing after >= 0.35s triggers droplets")
	assert(not wr.StepWater(ws, false, false, 12.2, false), "climbing out within 4s cooldown does not double-trigger")
	assert(not wr.StepWater(ws, false, true, 17.0, false), "start surface swim after cooldown")
	assert(wr.StepWater(ws, false, false, 17.8, false), "exiting swim after >= 0.5s triggers droplets")
	assert(not wr.StepWater(ws, true, true, 25.0, false), "submerge before death")
	assert(not wr.StepWater(ws, false, false, 26.0, true), "blocked state (dead/taxi/flying) suppresses water trigger")

	-- 2. Worn armor durability & clinking state machine
	local savedDurability = GetInventoryItemDurability
	local slotDura = { [1] = { 40, 100 }, [5] = { 25, 100 }, [7] = { 80, 100 } }
	GetInventoryItemDurability = function(slot)
		local pair = slotDura[slot]
		if pair then return pair[1], pair[2] end
	end
	assert(wr.LowestArmorDurability() == 25, "lowest armor durability picks minimum across armor slots")
	local as = { graceUntil = 2 }
	assert(not wr.StepArmor(as, 20, false, 1.0, false), "login with already worn armor does not rattle immediately")
	assert(not wr.StepArmor(as, 50, false, 5.0, false), "repaired armor does not rattle")
	assert(wr.StepArmor(as, 28, false, 10.0, false), "dropping below 30% rattles once")
	assert(not wr.StepArmor(as, 25, false, 15.0, false), "further drop within 25s cooldown stays silent")
	assert(not wr.StepArmor(as, 25, true, 40.0, false), "jumping while worn starts fall timer")
	assert(wr.StepArmor(as, 25, false, 40.5, false), "landing after >= 0.15s while worn rattles after cooldown")
	assert(not wr.StepArmor(as, 60, true, 70.0, false) and not wr.StepArmor(as, 60, false, 70.6, false),
		"landing with healthy armor never rattles")

	-- 4. Overlay visuals, audio playback, campfire aura/proximity & combat fade
	local savedPlayFile, savedPlaySound, savedAfter = PlaySoundFile, PlaySound, ns.After
	local savedSecrets, savedUnitAuras, savedCombat = C_Secrets, C_UnitAuras, UnitAffectingCombat
	local savedGetTime, savedMapBest, savedMapPos, savedMapSize = GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize
	local playedFiles, playedKits, pendingAfter = {}, {}, {}
	local nowTime = 100
	GetTime = function() return nowTime end
	PlaySoundFile = function(id) playedFiles[#playedFiles + 1] = id return true, #playedFiles end
	PlaySound = function(kit) playedKits[#playedKits + 1] = kit return true end
	ns.After = function(_, _, fn) pendingAfter[#pendingAfter + 1] = fn end
	local combatFlag = false
	UnitAffectingCombat = function() return combatFlag end

	-- Trigger water runoff preview & verify receding lens meniscus, running droplets with stationary trails & clinging beads
	wr.TriggerWater(true)
	local ov = _G.ForeverPlusWorldReactions
	assert(ov and ov:IsShown() and wr.GetState().dropsActive, "water trigger shows click-through overlay")
	assert(#playedFiles == 1, "splash sound played immediately")
	assert(#pendingAfter == 1, "drip sound scheduled")
	pendingAfter[1]()
	assert(#playedFiles == 2, "drip follow-up sound played")

	local dropPoolRef = uv(wr.TriggerWater, "dropPool")
	local beadPoolRef = uv(wr.TriggerWater, "beadPool")
	local sheetTexRef = uv(wr.TriggerWater, "sheetTexture")
	assert(sheetTexRef, "receding lens water meniscus texture created")
	assert(beadPoolRef and #beadPoolRef > 0, "clinging lens bead pool created")
	local recordedSize, recordedY = {}, {}
	local recordedTrailTopY, recordedTrailH, recordedTrailVEnd = {}, {}, {}
	for i, d in ipairs(dropPoolRef) do
		assert(d.trailTexture, "each running droplet has a paired stationary wet trail texture")
		d.texture.SetSize = function(_, w, h) recordedSize[i] = { w = w, h = h } end
		d.texture.SetPoint = function(_, _, _, _, _, y) recordedY[i] = y end
		d.trailTexture.SetSize = function(_, _, h) recordedTrailH[i] = h end
		d.trailTexture.SetPoint = function(_, _, _, _, _, y) recordedTrailTopY[i] = y end
		d.trailTexture.SetTexCoord = function(_, _, _, _, vEnd) recordedTrailVEnd[i] = vEnd end
	end
	local sheetY = nil
	sheetTexRef.SetPoint = function(_, _, _, _, _, y) sheetY = y end

	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(ov:IsShown() and sheetTexRef:IsShown(), "receding water meniscus is visible right after surfacing")
	local firstSheetY = sheetY
	local shownBeads = 0
	for _, b in ipairs(beadPoolRef) do
		if b.texture:IsShown() then shownBeads = shownBeads + 1 end
	end
	assert(shownBeads > 0, "clinging camera-lens water beads appear right after surfacing")

	-- Advance slightly so running droplets are well underway and leaving revealed trails
	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(sheetY and firstSheetY and sheetY < firstSheetY, "receding water meniscus slides downward across the lens")
	local firstY, firstTrailTop, firstTrailV = {}, {}, {}
	local shownCount, shownTrails = 0, 0
	for i, d in ipairs(dropPoolRef) do
		if d.texture:IsShown() then
			shownCount = shownCount + 1
			firstY[i] = recordedY[i]
			assert(recordedSize[i] and recordedSize[i].h > recordedSize[i].w * 1.4 and recordedSize[i].h < recordedSize[i].w * 2.8,
				"running droplet head keeps natural lens-droplet proportions rather than an overstretched needle")
		end
		if d.trailTexture:IsShown() then
			shownTrails = shownTrails + 1
			firstTrailTop[i] = recordedTrailTopY[i]
			firstTrailV[i] = recordedTrailVEnd[i]
		end
	end
	assert(shownCount > 0, "at least one running droplet is visible after 0.6s")

	-- Advance another 0.3s: sheet has hidden (> 0.60s), running droplets move strictly downward and trails stay anchored at startY
	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(not sheetTexRef:IsShown(), "receding water meniscus finishes and hides before droplets end")
	local movedDown, trailAnchoredAndRevealed = false, false
	for i, prevY in pairs(firstY) do
		if dropPoolRef[i].texture:IsShown() and recordedY[i] then
			assert(recordedY[i] <= prevY + 1e-4, "stick-slip running droplet never climbs upward")
			if recordedY[i] < prevY - 0.5 then
				movedDown = true
			end
		end
		if dropPoolRef[i].trailTexture:IsShown() and firstTrailTop[i] and recordedTrailTopY[i] then
			assert(math.abs(recordedTrailTopY[i] - firstTrailTop[i]) < 1e-4,
				"wet trail top remains stationary on the camera lens while droplet runs down")
			if firstTrailV[i] and recordedTrailVEnd[i] and recordedTrailVEnd[i] > firstTrailV[i] then
				trailAnchoredAndRevealed = true
			end
		end
	end
	assert(movedDown, "running water droplets move downward over time")
	assert(shownTrails > 0 and trailAnchoredAndRevealed,
		"stationary wet trails reveal progressively via SetTexCoord behind running droplets")

	for _ = 1, 35 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end
	assert(not wr.GetState().dropsActive and not ov:IsShown() and not ov:GetScript("OnUpdate"),
		"overlay hides and clears OnUpdate once water runoff finishes")

	-- Surfacing in combat restricts both running droplets and clinging beads to the outer screen edges
	combatFlag = true
	wr:Apply()
	wr.TriggerWater(false)
	local activeCombatDrops, activeCombatBeads = 0, 0
	for _, d in ipairs(dropPoolRef) do
		if d.active then
			activeCombatDrops = activeCombatDrops + 1
			assert(d.x <= 0.16 or d.x >= 0.84, "combat surfacing keeps running droplets near outer edges: x=" .. tostring(d.x))
		end
	end
	for _, b in ipairs(beadPoolRef) do
		if b.active then
			activeCombatBeads = activeCombatBeads + 1
			assert(b.x <= 0.16 or b.x >= 0.84, "combat surfacing keeps clinging beads near outer edges: x=" .. tostring(b.x))
		end
	end
	assert(activeCombatDrops > 0 and activeCombatDrops < #dropPoolRef,
		"combat surfacing uses a reduced outer-edge subset of running droplets")
	assert(activeCombatBeads > 0 and activeCombatBeads < #beadPoolRef,
		"combat surfacing uses a reduced outer-edge subset of clinging beads")
	combatFlag = false
	wr:Apply()
	for _ = 1, 40 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end

	-- Campfire via Cozy Fire aura 7353 & combat suppression + secret aura safety
	local cozyAura = { spellId = 7353 }
	local secretAuras = false
	C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end }
	C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return id == 7353 and cozyAura or nil end }
	wr:Apply()
	assert(wr.GetState().hasCozyFireAura and wr.GetState().campfireDesired, "Cozy Fire buff activates campfire glow")
	assert(ov:IsShown(), "campfire glow shows overlay")
	for _ = 1, 5 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(wr.GetState().campfireAlpha > 0.5, "campfire glow fades in smoothly")

	-- Secret aura restriction & secret UNIT_AURA unit/aura values keep last known state without throwing
	local evFrame = uv(ns.RegisterEvent, "eventFrame")
	local function FireEvent(event, ...)
		evFrame:GetScript("OnEvent")(evFrame, event, ...)
	end
	secretAuras = true
	assert(upvalue(ns.RegisterEvent, "listeners").UNIT_AURA[wr], "UNIT_AURA registered for campfire aura tracking")
	FireEvent("UNIT_AURA", "player")
	assert(wr.GetState().hasCozyFireAura, "restricted auras preserve last known Cozy Fire state safely")
	secretAuras = false
	local savedSecret = ns.Secret
	local secretToken = {}
	ns.Secret = function(v) return v == secretToken or savedSecret(v) end
	FireEvent("UNIT_AURA", secretToken)
	assert(wr.GetState().hasCozyFireAura, "secret UNIT_AURA unit token is ignored without comparing")
	cozyAura = secretToken
	FireEvent("UNIT_AURA", "player")
	assert(wr.GetState().hasCozyFireAura, "secret aura returned by GetPlayerAuraBySpellID preserves state safely")
	cozyAura = { spellId = 7353 }
	ns.Secret = savedSecret

	-- Disabling waterDrops while water runoff and campfire glow are both active hides all water textures immediately
	pendingAfter = {}
	playedFiles = {}
	wr.TriggerWater(false)
	for _ = 1, 4 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(wr.GetState().dropsActive and wr.GetState().campfireDesired, "both water runoff and campfire active together")
	local anyDropShown, anyBeadShown = false, false
	for _, d in ipairs(dropPoolRef) do
		if d.texture:IsShown() then anyDropShown = true break end
	end
	for _, b in ipairs(beadPoolRef) do
		if b.texture:IsShown() then anyBeadShown = true break end
	end
	assert(anyDropShown and anyBeadShown and sheetTexRef:IsShown(),
		"running droplets, clinging beads and water meniscus visible during animation")
	ns.SetOption("WorldReactions", "waterDrops", false)
	assert(not sheetTexRef:IsShown(), "disabling waterDrops hides receding water meniscus immediately")
	for _, d in ipairs(dropPoolRef) do
		assert(not d.texture:IsShown() and not d.trailTexture:IsShown(),
			"disabling waterDrops hides all running droplet and wet trail textures immediately while campfire stays active")
	end
	for _, b in ipairs(beadPoolRef) do
		assert(not b.texture:IsShown(), "disabling waterDrops hides all clinging bead textures immediately")
	end
	if pendingAfter[1] then pendingAfter[1]() end
	assert(#playedFiles == 1, "disabling waterDrops cancels scheduled follow-up drip sound")
	ns.SetOption("WorldReactions", "waterDrops", true)

	-- Combat suppresses campfire glow cleanly
	combatFlag = true
	FireEvent("PLAYER_REGEN_DISABLED")
	assert(not wr.GetState().campfireDesired, "entering combat fades out campfire glow")
	for _ = 1, 6 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end
	assert(wr.GetState().campfireAlpha == 0 and not ov:IsShown(), "campfire glow fully hidden in combat")
	combatFlag = false
	FireEvent("PLAYER_REGEN_ENABLED")
	assert(wr.GetState().campfireDesired, "leaving combat near campfire restores glow")

	-- Campfire proximity via UNIT_SPELLCAST_SUCCEEDED (works even with Minimap campfires disabled)
	cozyAura = nil
	FireEvent("UNIT_AURA", "player")
	assert(not wr.GetState().campfireDesired, "losing Cozy Fire turns off campfire glow")
	local playerX, playerY = 0.50, 0.50
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	assert(upvalue(ns.RegisterEvent, "listeners").UNIT_SPELLCAST_SUCCEEDED[wr],
		"UNIT_SPELLCAST_SUCCEEDED registered for campfire proximity")
	FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1307227)
	assert(wr.GetState().campfireDesired, "placing a Basic Campfire activates glow when nearby")
	playerX = 0.55 -- 50 yards away (> 14 yd radius)
	assert(not wr.IsNearCampfire(nowTime), "walking 50 yards away deactivates campfire proximity")

	-- ns.HasCampfireNearPlayer safely handles nil GetXY / missing GetMapWorldSize
	local savedCampfires = uv(ns.HasCampfireNearPlayer, "campfires")
	savedCampfires[#savedCampfires + 1] = { mapID = 1429, x = 0.50, y = 0.50, expires = nowTime + 60 }
	playerX, playerY = 0.50, 0.50
	assert(ns.HasCampfireNearPlayer(14), "Minimap campfire helper detects nearby fire")
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return nil, nil end } end
	assert(not ns.HasCampfireNearPlayer(14), "Minimap campfire helper handles nil GetXY safely")
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end
	C_Map.GetMapWorldSize = nil
	assert(not ns.HasCampfireNearPlayer(14), "Minimap campfire helper handles missing GetMapWorldSize safely")
	table.remove(savedCampfires)
	C_Map.GetMapWorldSize = function() return 1000, 1000 end

	-- PLAYER_EQUIPMENT_CHANGED clears worn armor flag when damaged piece is swapped out
	slotDura = { [1] = { 20, 100 } }
	FireEvent("UPDATE_INVENTORY_DURABILITY")
	assert(wr.GetState().armorWorn, "UPDATE_INVENTORY_DURABILITY marks armor as worn below 30%")
	slotDura = { [1] = { 100, 100 } }
	FireEvent("PLAYER_EQUIPMENT_CHANGED")
	assert(not wr.GetState().armorWorn, "PLAYER_EQUIPMENT_CHANGED clears worn flag after swapping armor")

	-- Armor test sound with fallback
	playedFiles, playedKits = {}, {}
	PlaySoundFile = function() return false end
	SOUNDKIT = SOUNDKIT or {}
	local savedChainKit = SOUNDKIT.PUT_DOWN_SMALL_CHAIN
	SOUNDKIT.PUT_DOWN_SMALL_CHAIN = 1212
	assert(wr.PlayArmorRattle() and playedKits[1] == 1212, "armor rattle falls back to PUT_DOWN_SMALL_CHAIN when PlaySoundFile fails")

	-- Disabling WorldReactions stops overlay and clears watcher OnUpdate
	local savedWrTicker = ns.NewTicker
	ns.NewTicker = function() return { Cancel = function() end } end
	ns.SetOption("WorldReactions", "enabled", false)
	local st = wr.GetState()
	assert(not st.watcherActive and not st.overlayShown and not st.campfireDesired and not st.dropsActive,
		"disabling WorldReactions stops watcher and hides overlay")
	ns.SetOption("WorldReactions", "enabled", true)

	-- Restore mocked globals
	SOUNDKIT.PUT_DOWN_SMALL_CHAIN = savedChainKit
	GetInventoryItemDurability = savedDurability
	PlaySoundFile, PlaySound, ns.After = savedPlayFile, savedPlaySound, savedAfter
	C_Secrets, C_UnitAuras, UnitAffectingCombat = savedSecrets, savedUnitAuras, savedCombat
	GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize = savedGetTime, savedMapBest, savedMapPos, savedMapSize
	wr:Apply()
	ns.NewTicker = savedWrTicker
	print("world reactions OK")
end)()

-- Worse soulbound quest rewards: automatically added to the junk/sell list on turn-in.
;(function()
	local items = ns:GetModule("Items")
	assert(items.db.markWorseReward == true, "markWorseReward defaults to true")
	local opt
	for _, entry in ipairs(items.options) do
		if entry.key == "markWorseReward" then opt = entry end
	end
	assert(opt and opt.new == true, "markWorseReward option has new = true")

	local saved = {
		C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.IsEquippableItem, C_Item.GetItemStats,
		C_Item.IsItemDataCachedByID, C_Item.GetItemSpell, C_Item.RequestLoadItemDataByID,
		C_TooltipInfo.GetHyperlink, GetInventoryItemLink, ItemLocation, C_Item.DoesItemExist,
		GetQuestID, GetNumQuestChoices, GetNumQuestRewards, GetQuestItemLink, GetTime,
		issecretvalue, ns.After, items.db.markWorseReward, items.db.upgradeArrow,
		items.db.rewardUpgrade, items.db.junkPerCharacter, items.db.markMessage,
	}

	local wornCloak = "|cff1eff00|Hitem:91001::::::::60:::::::|h[Strong Cloak]|h|r"
	local worseBoP = "|cff1eff00|Hitem:91002::::::::60:::::::|h[Weak BoP Cloak]|h|r"
	local worseBoE = "|cff1eff00|Hitem:91003::::::::60:::::::|h[Weak BoE Cloak]|h|r"
	local betterBoP = "|cff1eff00|Hitem:91004::::::::60:::::::|h[Great BoP Cloak]|h|r"
	local worseGuaranteed = "|cff1eff00|Hitem:91005::::::::60:::::::|h[Weak BoP Guaranteed Cloak]|h|r"
	local unsellableBoP = "|cff1eff00|Hitem:91006::::::::60:::::::|h[No-Value BoP Cloak]|h|r"
	local greyBoP = "|cff9d9d9d|Hitem:91007::::::::60:::::::|h[Grey BoP Cloak]|h|r"
	local onUseBoP = "|cff1eff00|Hitem:91008::::::::60:::::::|h[Utility OnUse Cloak]|h|r"
	local wornTrinket = "|cff1eff00|Hitem:91009::::::::60:::::::|h[Stat Trinket]|h|r"
	local utilityTrinket = "|cff1eff00|Hitem:91010::::::::60:::::::|h[Carrot Trinket]|h|r"
	local worseStatTrinket = "|cff1eff00|Hitem:91011::::::::60:::::::|h[Weak Stat Trinket]|h|r"
	local delayedBoP = "|cff1eff00|Hitem:91012::::::::60:::::::|h[Delayed BoP Cloak]|h|r"
	local lootBoP = "|cff1eff00|Hitem:91013::::::::60:::::::|h[Loot BoP Cloak]|h|r"
	local secretLink = "|cff1eff00|Hitem:91014::::::::60:::::::|h[Secret Cloak]|h|r"

	local itemDefs = {
		[91001] = { name = "Strong Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 500, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 20 } },
		[91002] = { name = "Weak BoP Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 400, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 5 } },
		[91003] = { name = "Weak BoE Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 400, bind = 2, stats = { ITEM_MOD_INTELLECT_SHORT = 5 } },
		[91004] = { name = "Great BoP Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 400, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 40 } },
		[91005] = { name = "Weak BoP Guaranteed Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 300, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 3 } },
		[91006] = { name = "No-Value BoP Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 0, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 3 } },
		[91007] = { name = "Grey BoP Cloak", quality = 0, loc = "INVTYPE_CLOAK", price = 100, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 2 } },
		[91008] = { name = "Utility OnUse Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 300, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 2 }, spell = "Slow Fall" },
		[91009] = { name = "Stat Trinket", quality = 2, loc = "INVTYPE_TRINKET", price = 500, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 20 } },
		[91010] = { name = "Carrot Trinket", quality = 2, loc = "INVTYPE_TRINKET", price = 500, bind = 1, stats = {} },
		[91011] = { name = "Weak Stat Trinket", quality = 2, loc = "INVTYPE_TRINKET", price = 500, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 4 } },
		[91012] = { name = "Delayed BoP Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 350, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 2 } },
		[91013] = { name = "Loot BoP Cloak", quality = 2, loc = "INVTYPE_CLOAK", price = 350, bind = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 2 } },
	}
	local delayedReady, requestedIDs, timers = false, {}, {}

	local function ItemIDFrom(link)
		if type(link) == "number" then return link end
		return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	end

	C_Item.GetItemInfoInstant = function(link)
		local id = ItemIDFrom(link)
		local def = id and itemDefs[id]
		if def then
			local sub = def.loc == "INVTYPE_TRINKET" and 0 or Enum.ItemArmorSubclass.Cloth
			return id, "Armor", "Cloth", def.loc, 1337, Enum.ItemClass.Armor, sub
		end
		return saved[2](link)
	end
	C_Item.GetItemInfo = function(link)
		local id = ItemIDFrom(link)
		if id == 91012 and not delayedReady then return nil end
		local def = id and itemDefs[id]
		if def then
			local sub = def.loc == "INVTYPE_TRINKET" and 0 or Enum.ItemArmorSubclass.Cloth
			return def.name, link, def.quality, 40, 1, "Armor", "Cloth", 1, def.loc, 1337,
				def.price, Enum.ItemClass.Armor, sub, def.bind
		end
		return nil
	end
	C_Item.IsEquippableItem = function(link)
		local id = ItemIDFrom(link)
		return id ~= nil and itemDefs[id] ~= nil
	end
	C_Item.GetItemStats = function(link)
		local id = ItemIDFrom(link)
		return id and itemDefs[id] and itemDefs[id].stats or {}
	end
	C_Item.IsItemDataCachedByID = function(link)
		local id = ItemIDFrom(link)
		if id == 91012 and not delayedReady then return false end
		return id ~= nil and itemDefs[id] ~= nil
	end
	C_Item.GetItemSpell = function(link)
		local id = ItemIDFrom(link)
		return id and itemDefs[id] and itemDefs[id].spell or nil
	end
	C_Item.RequestLoadItemDataByID = function(link)
		requestedIDs[#requestedIDs + 1] = ItemIDFrom(link)
	end
	C_TooltipInfo.GetHyperlink = function() return { lines = {} } end
	ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
	C_Item.DoesItemExist = function(loc) return loc and (loc.slot == 15 or loc.slot == 13 or loc.slot == 14) end
	GetInventoryItemLink = function(_, slot)
		if slot == 15 then return wornCloak end
		if slot == 13 or slot == 14 then return wornTrinket end
		return nil
	end
	issecretvalue = function(v) return v == secretLink end
	ns.After = function(_, _, fn) timers[#timers + 1] = fn end

	local now = 500
	GetTime = function() return now end
	local curQuest, curChoices, curRewards = 0, {}, {}
	GetQuestID = function() return curQuest end
	GetNumQuestChoices = function() return #curChoices end
	GetNumQuestRewards = function() return #curRewards end
	GetQuestItemLink = function(kind, idx)
		return kind == "choice" and curChoices[idx] or curRewards[idx]
	end

	local evFrame = uv(ns.RegisterEvent, "eventFrame")
	local function FireEvent(event, ...)
		evFrame:GetScript("OnEvent")(evFrame, event, ...)
	end

	-- Clear caches and reset junk lists for clean assertions.
	items.db.junkPerCharacter = false
	items.db.markMessage = false
	items.db.markWorseReward = true
	items.db.upgradeArrow = false
	items.db.rewardUpgrade = false
	items:Refresh()
	FireEvent("PLAYER_EQUIPMENT_CHANGED")
	for id = 91001, 91014 do items.db.junk[id] = nil; items.cdb.junk[id] = nil end

	-- 1. Standard turn-in: choice #1 (worse BoP) + guaranteed (worse BoP), even when live offer clears before post-hook.
	curQuest = 8801
	curChoices = { worseBoP, worseBoE, betterBoP }
	curRewards = { worseGuaranteed }
	FireEvent("QUEST_COMPLETE")
	-- Simulate client clearing the offer before hook runs: snapshot fallback must supply the links.
	curChoices, curRewards = {}, {}
	items.OnGetQuestReward(1)
	assert(not items.db.junk[91002] and not items.db.junk[91005], "not marked before QUEST_TURNED_IN")
	-- Wrong quest ID must not consume/mark the pending reward.
	FireEvent("QUEST_TURNED_IN", 9999)
	assert(not items.db.junk[91002], "wrong quest ID does not mark reward")
	-- Matching quest ID marks both chosen worse BoP and guaranteed worse BoP, even with upgradeArrow/rewardUpgrade off.
	FireEvent("QUEST_TURNED_IN", 8801)
	assert(items.db.junk[91002] == true, "worse BoP choice marked on sell list")
	assert(items.db.junk[91005] == true, "worse BoP guaranteed reward marked on sell list")
	assert(not items.db.junk[91003] and not items.db.junk[91004], "unchosen rewards not marked")

	-- 2. Single choice with choice == 0 (auto-resolved to 1) & BoE / upgrade / unsellable / grey / on-use / utility trinket filtering.
	curQuest = 8802
	curChoices = { worseBoE }
	curRewards = { betterBoP, unsellableBoP, greyBoP, onUseBoP, utilityTrinket, worseStatTrinket }
	FireEvent("QUEST_COMPLETE")
	items.OnGetQuestReward(0)
	FireEvent("QUEST_TURNED_IN", 8802)
	assert(not items.db.junk[91003], "BoE quest reward is NOT marked")
	assert(not items.db.junk[91004], "upgrade quest reward is NOT marked")
	assert(not items.db.junk[91006], "unsellable quest reward is NOT marked")
	assert(not items.db.junk[91007], "grey quest reward is NOT added to junk list")
	assert(not items.db.junk[91008], "on-use quest reward is NOT marked")
	assert(not items.db.junk[91010], "zero-score utility trinket is NOT marked")
	assert(items.db.junk[91011] == true, "worse stat trinket IS marked")

	-- 3. QUEST_LOOT_RECEIVED path + secret value safety.
	FireEvent("QUEST_LOOT_RECEIVED", 8803, secretLink, 1)
	FireEvent("QUEST_LOOT_RECEIVED", 8803, lootBoP, 1)
	assert(items.db.junk[91013] == true and not items.db.junk[91014], "QUEST_LOOT_RECEIVED marks worse BoP and skips secret links")

	-- 4. Uncached item retries after data loads.
	timers, requestedIDs = {}, {}
	FireEvent("QUEST_LOOT_RECEIVED", 8804, delayedBoP, 1)
	assert(not items.db.junk[91012] and requestedIDs[1] == 91012 and #timers == 1, "uncached reward requests load and schedules retry")
	delayedReady = true
	timers[1]()
	assert(items.db.junk[91012] == true, "retried reward is marked once item data loads")

	-- 5. Option off disables marking; per-character junk list is respected when on.
	items.db.junk[91002] = nil
	items.db.markWorseReward = false
	items:Refresh()
	curQuest = 8805
	curChoices = { worseBoP }
	curRewards = {}
	FireEvent("QUEST_COMPLETE")
	items.OnGetQuestReward(1)
	FireEvent("QUEST_TURNED_IN", 8805)
	FireEvent("QUEST_LOOT_RECEIVED", 8805, worseBoP, 1)
	assert(not items.db.junk[91002], "option off does not mark quest rewards")

	items.db.markWorseReward = true
	items.db.junkPerCharacter = true
	items:Refresh()
	FireEvent("QUEST_LOOT_RECEIVED", 8806, worseBoP, 1)
	assert(items.cdb.junk[91002] == true and not items.db.junk[91002], "per-character junk list receives marked reward")

	-- Restore state
	for id = 91001, 91014 do items.db.junk[id] = nil; items.cdb.junk[id] = nil end
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.IsEquippableItem, C_Item.GetItemStats = saved[1], saved[2], saved[3], saved[4]
	C_Item.IsItemDataCachedByID, C_Item.GetItemSpell, C_Item.RequestLoadItemDataByID = saved[5], saved[6], saved[7]
	C_TooltipInfo.GetHyperlink, GetInventoryItemLink, ItemLocation, C_Item.DoesItemExist = saved[8], saved[9], saved[10], saved[11]
	GetQuestID, GetNumQuestChoices, GetNumQuestRewards, GetQuestItemLink, GetTime = saved[12], saved[13], saved[14], saved[15], saved[16]
	issecretvalue, ns.After = saved[17], saved[18]
	items.db.markWorseReward, items.db.upgradeArrow, items.db.rewardUpgrade, items.db.junkPerCharacter, items.db.markMessage =
		saved[19], saved[20], saved[21], saved[22], saved[23]
	items:Refresh()
	FireEvent("PLAYER_EQUIPMENT_CHANGED")
	print("worse soulbound quest rewards OK")
end)()

-- Campfire performance guards (WorldReactions glow/embers + Minimap campfire pins)
;(function()
	local wr = ns:GetModule("WorldReactions")
	local mm = ns:GetModule("Minimap")
	local evFrame = uv(ns.RegisterEvent, "eventFrame")
	local function fire(event, ...)
		evFrame:GetScript("OnEvent")(evFrame, event, ...)
	end
	local saved = {
		GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize,
		C_Minimap.GetViewRadius, GetCVarBool, GetPlayerFacing, UnitName, UnitOnTaxi,
		C_Secrets, C_UnitAuras, UnitAffectingCombat, ns.NewTicker,
		wr.db.enabled, wr.db.campfireGlow, mm.db.campfires,
	}

	local now = 500
	local px, py = 0.50, 0.50
	local mapReads = 0
	local tickers = {}
	GetTime = function() return now end
	C_Map.GetBestMapForUnit = function() mapReads = mapReads + 1 return 1429 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	C_Minimap.GetViewRadius = function() return 100 end
	GetCVarBool = function() return false end
	GetPlayerFacing = function() return 0 end
	UnitName = function() return "Tester", "" end
	UnitOnTaxi = function() return false end
	C_Secrets = { ShouldAurasBeSecret = function() return false end }
	local cozyAura = { spellId = 7353 }
	C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return id == 7353 and cozyAura or nil end }
	UnitAffectingCombat = function() return false end
	ns.NewTicker = function(name, interval, fn)
		local entry = { name = name, interval = interval, fn = fn, cancelled = false }
		function entry:Cancel() self.cancelled = true end
		tickers[#tickers + 1] = entry
		return entry
	end

	-- 1. WorldReactions campfire animation: no ClearAllPoints, 30 FPS throttle on campfire-only frames,
	-- cached glow SetSize, and event-driven watcher (no map polls when no campfire is tracked).
	wr.db.enabled = false
	wr:Apply()
	wr.db.enabled = true
	wr.db.campfireGlow = true
	wr:Apply()
	local ov = _G.ForeverPlusWorldReactions
	assert(ov and ov:IsShown() and wr.GetState().campfireDesired, "Cozy Fire shows overlay")
	local ensureOverlay = uv(wr.TriggerWater, "EnsureOverlay")
	local emberPoolRef = uv(ensureOverlay, "emberPool")
	local glowTexRef = uv(ensureOverlay, "glowTexture")
	local clearCalls, emberSetPoints, glowSetSizes = 0, 0, 0
	local origGlowSize = glowTexRef.SetSize
	glowTexRef.SetSize = function(self, w, h)
		glowSetSizes = glowSetSizes + 1
		if origGlowSize then origGlowSize(self, w, h) end
	end
	for _, ember in ipairs(emberPoolRef) do
		local origClear = ember.texture.ClearAllPoints
		local origPoint = ember.texture.SetPoint
		ember.texture.ClearAllPoints = function(self)
			clearCalls = clearCalls + 1
			if origClear then origClear(self) end
		end
		ember.texture.SetPoint = function(self, ...)
			emberSetPoints = emberSetPoints + 1
			if origPoint then origPoint(self, ...) end
		end
	end

	-- First tick renders immediately; subsequent sub-33ms ticks are skipped until 1/30 s accumulates.
	local onUpdate = ov:GetScript("OnUpdate")
	onUpdate(ov, 0.01)
	local firstPoints = emberSetPoints
	assert(firstPoints == #emberPoolRef, "first campfire tick positions all embers")
	assert(clearCalls == 0, "campfire embers update points without ClearAllPoints")
	onUpdate(ov, 0.01)
	onUpdate(ov, 0.01)
	assert(emberSetPoints == firstPoints, "campfire-only animation throttles sub-33ms frames")
	onUpdate(ov, 0.02)
	assert(emberSetPoints == firstPoints * 2, "accumulated >= 1/30 s runs the next campfire animation step")
	assert(glowSetSizes <= 1, "glow texture SetSize is cached across campfire ticks")

	-- Watcher skips map queries when no tracked campfires or preview exist.
	local watchFn
	for i = #tickers, 1, -1 do
		if tickers[i].name == "WorldReactions: watch" and not tickers[i].cancelled then
			watchFn = tickers[i].fn
			break
		end
	end
	assert(watchFn, "WorldReactions watcher runs via ns.NewTicker instead of per-frame OnUpdate")
	mapReads = 0
	watchFn()
	assert(mapReads == 0, "watcher skips map queries when no campfires are tracked")

	-- Clean up campfire glow
	cozyAura = nil
	fire("UNIT_AURA", "player")
	for _ = 1, 6 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end

	-- 2. Minimap campfires: adaptive ticker (1.0 s idle, 0.25 s moving), no OnUpdate, and dirty-checked pin setters.
	mm.db.campfires = true
	mm:OnOptionChanged("campfires")
	tickers = {}
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cf-guid", 1307227)
	assert(ns.HasTrackedCampfires(), "placing a campfire tracks it on Minimap")
	local holder = uv(mm.OnLogin, "campfireHolder")
	assert(holder and not holder:GetScript("OnUpdate"), "Minimap campfire uses ticker instead of per-frame OnUpdate")
	local cfTicker = tickers[#tickers]
	assert(cfTicker and cfTicker.name == "Minimap: campfire update" and cfTicker.interval == 1.0,
		"stationary Minimap campfire uses 1.0 s countdown ticker")

	local list = uv(ns.HasCampfireNearPlayer, "campfires")
	local fireObj = list[#list]
	local pinClear, pinPoint, pinAlpha, pinText = 0, 0, 0, 0
	local origPinClear, origPinPoint, origPinAlpha, origTimerText =
		fireObj.pin.ClearAllPoints, fireObj.pin.SetPoint, fireObj.pin.SetAlpha, fireObj.pin.Timer.SetText
	fireObj.pin.ClearAllPoints = function(self) pinClear = pinClear + 1; if origPinClear then origPinClear(self) end end
	fireObj.pin.SetPoint = function(self, ...) pinPoint = pinPoint + 1; if origPinPoint then origPinPoint(self, ...) end end
	fireObj.pin.SetAlpha = function(self, ...) pinAlpha = pinAlpha + 1; if origPinAlpha then origPinAlpha(self, ...) end end
	fireObj.pin.Timer.SetText = function(self, ...) pinText = pinText + 1; if origTimerText then origTimerText(self, ...) end end

	-- Same position and same remaining second: zero layout/text updates.
	cfTicker.fn()
	assert(pinClear == 0 and pinPoint == 0 and pinAlpha == 0 and pinText == 0,
		"unchanged campfire tick performs zero redundant SetPoint/SetAlpha/SetText/ClearAllPoints calls")

	-- Advancing by 1 second updates only the countdown text, not pin position or alpha.
	now = now + 1
	cfTicker.fn()
	assert(pinText == 1 and pinPoint == 0 and pinAlpha == 0 and pinClear == 0,
		"countdown tick updates timer text without moving or clearing pin points")

	-- Moving switches ticker to 0.25 s and updates pin point without ClearAllPoints.
	local function LatestTicker(name)
		for i = #tickers, 1, -1 do
			if tickers[i].name == name then return tickers[i] end
		end
	end
	fire("PLAYER_STARTED_MOVING")
	local moveTicker = LatestTicker("Minimap: campfire update")
	assert(moveTicker and moveTicker.interval == 0.25 and cfTicker.cancelled,
		"starting movement switches campfire ticker to 0.25 s")
	px = 0.51
	moveTicker.fn()
	assert(pinPoint == 1 and pinClear == 0, "movement repositions campfire pin in-place without ClearAllPoints")

	-- Stopping movement returns to 1.0 s idle ticker; expiring cancels ticker cleanly.
	fire("PLAYER_STOPPED_MOVING")
	local idleTicker = LatestTicker("Minimap: campfire update")
	assert(idleTicker and idleTicker.interval == 1.0 and moveTicker.cancelled,
		"stopping movement restores 1.0 s idle campfire ticker")
	now = now + 20 * 60
	idleTicker.fn()
	assert(not ns.HasTrackedCampfires() and idleTicker.cancelled, "expired campfire cancels ticker cleanly")

	-- Restore mocked globals and state
	GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize =
		saved[1], saved[2], saved[3], saved[4]
	C_Minimap.GetViewRadius, GetCVarBool, GetPlayerFacing, UnitName, UnitOnTaxi =
		saved[5], saved[6], saved[7], saved[8], saved[9]
	C_Secrets, C_UnitAuras, UnitAffectingCombat =
		saved[10], saved[11], saved[12]
	wr.db.enabled, wr.db.campfireGlow, mm.db.campfires = saved[14], saved[15], saved[16]
	mm:OnOptionChanged("campfires")
	wr:Apply()
	ns.NewTicker = saved[13]
	print("campfire performance OK")
end)()
;(function()
	-- Bubble anchor nameplates: temporarily enabled friendly NPC plates and the bubble's own plate stay invisible
	-- across QoL fade updates, target changes, Blizzard CompactUnitFrame alpha resets, and pooled UnitFrame release.
	local qol = ns:GetModule("QoL")
	local saved = {
		GetCVar, SetCVar, C_NamePlate, UnitExists, UnitIsFriend, UnitIsPlayer, UnitCanAttack, UnitIsUnit,
		InCombatLockdown, issecretvalue, qol.db.nameplatesFade, qol.db.nameplatesFadeAmount,
		qol.db.nameplatesTargetFull, qol.db.nameplatesFadeCombat,
	}
	local function MakePlate(unit, startAlpha)
		local sel = { a = 0.25 }
		function sel:GetAlpha() return self.a end
		function sel:SetAlpha(a) self.a = a end
		function sel:IsForbidden() return false end
		local uf = { unit = unit, a = startAlpha or 1, selectionHighlight = sel }
		function uf:GetAlpha() return self.a end
		function uf:SetAlpha(a) self.a = a end
		function uf:IsForbidden() return false end
		local plate = { unitToken = unit, UnitFrame = uf }
		function plate:IsForbidden() return false end
		return plate, uf, sel
	end

	local speakerPlate, speakerUF, speakerSel = MakePlate("nameplate1", 1)
	local gnomePlate, gnomeUF, gnomeSel = MakePlate("nameplate2", 1)
	local enemyPlate, enemyUF = MakePlate("nameplate3", 1)
	local playerPlate, playerUF = MakePlate("nameplate4", 1)
	local units = {
		nameplate1 = { plate = speakerPlate, friend = true, player = false, attack = false },
		nameplate2 = { plate = gnomePlate, friend = true, player = false, attack = false },
		nameplate3 = { plate = enemyPlate, friend = false, player = false, attack = true },
		nameplate4 = { plate = playerPlate, friend = true, player = true, attack = false },
	}
	local targetUnit = "nameplate1"
	local inCombat = false
	local secretVal = nil
	local cvars = { nameplateShowFriendlyNpcs = "1", nameplateShowAll = "0" }

	GetCVar = function(k) return cvars[k] end
	SetCVar = function(k, v) cvars[k] = v end
	InCombatLockdown = function() return inCombat end
	issecretvalue = function(v) return secretVal ~= nil and v == secretVal end
	UnitExists = function(u) return u == "target" and targetUnit ~= nil or units[u] ~= nil end
	UnitIsFriend = function(_, u) return units[u] and units[u].friend or false end
	UnitIsPlayer = function(u) return units[u] and units[u].player or false end
	UnitCanAttack = function(_, u) return units[u] and units[u].attack or false end
	UnitIsUnit = function(a, b) return (b == "target" and a == targetUnit) or (a == "target" and b == targetUnit) or a == b end
	C_NamePlate = {
		GetNamePlates = function()
			local list = {}
			for _, info in pairs(units) do
				list[#list + 1] = info.plate
			end
			return list
		end,
		GetNamePlateForUnit = function(u)
			if u == "target" then u = targetUnit end
			return units[u] and units[u].plate or nil
		end,
	}

	local listeners = uv(ns.RegisterEvent, "listeners")
	local onAdded = listeners.NAME_PLATE_UNIT_ADDED["NPC bubble nameplates"]
	local onRemoved = listeners.NAME_PLATE_UNIT_REMOVED["NPC bubble nameplates"]
	local onTarget = listeners.PLAYER_TARGET_CHANGED["NPC bubble nameplates"]

	-- 1. User has nameplateShowFriendlyNpcs=1, nameplateShowAll=0: opening a bubble enables nameplateShowAll=1,
	-- hides both the speaker anchor plate and nearby untargeted friendly NPCs, leaving enemies & players untouched.
	qol.db.nameplatesFade, qol.db.nameplatesFadeAmount = true, 60
	qol.db.nameplatesTargetFull, qol.db.nameplatesFadeCombat = true, true
	qol:UpdateNameplates()

	ns.ShowFriendlyPlates(true, "dialog")
	ns.SetBubblePlate(speakerPlate, "dialog", true)
	assert(cvars.nameplateShowAll == "1", "bubble turns nameplateShowAll on temporarily")
	assert(speakerUF.a == 0 and speakerSel.a == 0, "speaker anchor plate and Classic selection highlight are hidden")
	assert(gnomeUF.a == 0 and gnomeSel.a == 0, "nearby untargeted friendly NPC plate is hidden automatically")
	assert(math.abs(enemyUF.a - 0.4) < 1e-6 and math.abs(playerUF.a - 0.4) < 1e-6,
		"enemy and friendly player plates stay unaffected by bubble plate hiding")

	-- 2. QoL FadeAllPlates / target change must not un-hide hidden anchor or temporary friendly NPC plates.
	targetUnit = nil
	onTarget()
	uv(qol.UpdateNameplates, "FadeAllPlates")()
	assert(speakerUF.a == 0 and gnomeUF.a == 0, "QoL nameplate fade and target clear do not unhide hidden plates")

	-- 3. Blizzard CompactUnitFrame_UpdateCenterStatusIcon resetting alpha to 1 is immediately reverted to 0.
	speakerUF:SetAlpha(1)
	gnomeUF:SetAlpha(1)
	ns.EnforceHiddenUnitFrame(speakerUF)
	ns.EnforceHiddenUnitFrame(gnomeUF)
	assert(speakerUF.a == 0 and gnomeUF.a == 0, "CompactUnitFrame hook keeps hidden UnitFrames at alpha 0")

	-- 4. Newly spawned friendly NPC plate while bubble is open is hidden on NAME_PLATE_UNIT_ADDED (before QoL).
	local latePlate, lateUF = MakePlate("nameplate5", 1)
	units.nameplate5 = { plate = latePlate, friend = true, player = false, attack = false }
	onAdded(nil, "NAME_PLATE_UNIT_ADDED", "nameplate5")
	uv(qol.UpdateNameplates, "OnPlateAdded")(nil, "NAME_PLATE_UNIT_ADDED", "nameplate5")
	assert(lateUF.a == 0 and ns.IsPlateHidden(latePlate), "late-arriving friendly NPC plate stays hidden after QoL OnPlateAdded")

	-- 5. Pooled UnitFrame release: even when Blizzard clears plate.UnitFrame = nil before NAME_PLATE_UNIT_REMOVED,
	-- the released UnitFrame still gets its alpha restored so it does not stay invisible in Blizzard's pool.
	latePlate.UnitFrame = nil
	onRemoved(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate5")
	assert(math.abs(lateUF.a - 0.4) < 1e-6 and not ns.IsPlateHidden(latePlate),
		"released pooled UnitFrame gets its alpha restored cleanly: " .. tostring(lateUF.a))
	units.nameplate5 = nil

	-- 6. Closing the bubble in combat keeps temporary plates hidden until combat ends and CVars restore.
	inCombat = true
	ns.SetBubblePlate(nil, "dialog")
	ns.ShowFriendlyPlates(false, "dialog")
	assert(cvars.nameplateShowAll == "1" and gnomeUF.a == 0,
		"temporary friendly NPC plates stay hidden during combat until CVars can restore")
	inCombat = false
	local queue = uv(ns.RunOutOfCombat, "regenQueue")
	assert(#queue > 0, "combat lockdown queues CVar restore")
	while #queue > 0 do
		table.remove(queue, 1)()
	end
	assert(cvars.nameplateShowAll == "0", "CVars restored out of combat")
	assert(math.abs(gnomeUF.a - 0.4) < 1e-6 and math.abs(gnomeSel.a - 0.25) < 1e-6,
		"temporary plate alpha and highlight restored after CVar restore")
	assert(math.abs(speakerUF.a - 0.4) < 1e-6 and math.abs(speakerSel.a - 0.25) < 1e-6,
		"speaker plate alpha and highlight restored cleanly")

	-- 7. When nameplateShowFriendlyNpcs was 0, even a targeted friendly NPC is hidden unless hidePlate=false keeps it visible.
	cvars.nameplateShowFriendlyNpcs, cvars.nameplateShowAll = "0", "0"
	targetUnit = "nameplate1"
	ns.ShowFriendlyPlates(true, "dialog")
	assert(speakerUF.a == 0 and gnomeUF.a == 0, "all friendly NPC plates hidden when nameplateShowFriendlyNpcs was off")
	ns.SetBubblePlate(speakerPlate, "dialog", false)
	assert(speakerUF.a > 0 and gnomeUF.a == 0, "explicit hidePlate=false shows only the speaker plate, keeping nearby NPCs hidden")
	ns.SetBubblePlate(nil, "dialog")
	ns.ShowFriendlyPlates(false, "dialog")
	assert(cvars.nameplateShowFriendlyNpcs == "0" and cvars.nameplateShowAll == "0", "both CVars restored")

	-- 8. Secret values from UnitIsFriend / UnitIsPlayer / UnitIsUnit do not raise errors.
	secretVal = "SECRET_FLAG"
	units.nameplate2.friend = secretVal
	ns.ShowFriendlyPlates(true, "dialog")
	onAdded(nil, "NAME_PLATE_UNIT_ADDED", "nameplate2")
	ns.ShowFriendlyPlates(false, "dialog")
	secretVal = nil

	GetCVar, SetCVar, C_NamePlate, UnitExists, UnitIsFriend, UnitIsPlayer, UnitCanAttack, UnitIsUnit,
		InCombatLockdown, issecretvalue, qol.db.nameplatesFade, qol.db.nameplatesFadeAmount,
		qol.db.nameplatesTargetFull, qol.db.nameplatesFadeCombat = unpack(saved, 1, 14)
	qol:UpdateNameplates()
	print("bubble anchor nameplate hiding OK")
end)()

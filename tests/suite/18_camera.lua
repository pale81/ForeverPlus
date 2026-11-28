(function()
	-- Persistent account-wide ignore list in Chat: save, restore after restart, explicit removal, chat filter and editor
	local chat = ns:GetModule("Chat")
	local saved = {
		C_FriendList = C_FriendList,
		GetNormalizedRealmName = GetNormalizedRealmName,
		GetRealmName = GetRealmName,
		RegionalUniqueNamesEnabled = RegionalUniqueNamesEnabled,
		UnitFullName = UnitFullName,
		GetTime = GetTime,
		hooksecurefunc = hooksecurefunc,
		issecretvalue = issecretvalue,
		ShowEditWindow = ns.ShowEditWindow,
		ERR_IGNORE_ADDED_S = ERR_IGNORE_ADDED_S,
		ERR_IGNORE_ALREADY_S = ERR_IGNORE_ALREADY_S,
		ERR_IGNORE_NOT_FOUND = ERR_IGNORE_NOT_FOUND,
		ERR_IGNORE_SELF = ERR_IGNORE_SELF,
		keepIgnore = chat.db.keepIgnore,
		ignoredPlayers = ns.db.ignoredPlayers,
	}

	local now = 100
	GetTime = function() return now end
	GetNormalizedRealmName = function() return "Everlook" end
	GetRealmName = function() return "Everlook" end
	local regional = false
	RegionalUniqueNamesEnabled = function() return regional end
	UnitFullName = function() return "OwnHero", "Everlook" end
	local secretVal = {}
	issecretvalue = function(v) return v == secretVal end
	ERR_IGNORE_ADDED_S = "%s is now being ignored."
	ERR_IGNORE_ALREADY_S = "%s is already being ignored."
	ERR_IGNORE_NOT_FOUND = "Player not found."
	ERR_IGNORE_SELF = "You can't ignore yourself."

	hooksecurefunc = function(object, method, hook)
		local original = object[method]
		object[method] = function(...)
			local r1, r2 = original(...)
			hook(...)
			return r1, r2
		end
	end

	-- Name normalisation: own realm stripped, foreign realm kept, Forever internal realm stripped.
	assert(chat.IgnoreCanonical("Spammer-Everlook") == "Spammer", "own realm stripped")
	assert(chat.IgnoreCanonical("Troll-OtherRealm") == "Troll-OtherRealm", "foreign realm kept")
	assert(chat.IgnoreCanonical(secretVal) == nil, "secret value ignored")
	regional = true
	assert(chat.IgnoreCanonical("Bob Smith-CAMWOWEU5Realm10RP") == "Bob Smith", "Forever regional name keeps surname and strips internal realm")
	regional = false

	local serverList = { "Spammer-Everlook", "Troll-OtherRealm" }
	local addedCalls, deletedCalls = {}, {}
	C_FriendList = {
		GetNumIgnores = function() return #serverList end,
		GetIgnoreName = function(i) return serverList[i] end,
		AddIgnore = function(name)
			addedCalls[#addedCalls + 1] = name
			return true
		end,
		DelIgnore = function(name)
			deletedCalls[#deletedCalls + 1] = name
			return true
		end,
		DelIgnoreByIndex = function(index)
			local name = serverList[index]
			if name then
				deletedCalls[#deletedCalls + 1] = name
			end
			return true
		end,
		AddOrDelIgnore = function() return true end,
	}

	ns.db.ignoredPlayers = {}
	chat.db.keepIgnore = true
	chat.ResetIgnoreSession()
	chat:UpdateIgnoreList(true)
	assert(ns.db.ignoredPlayers["spammer"] == "Spammer", "server ignore saved")
	assert(ns.db.ignoredPlayers["troll-otherrealm"] == "Troll-OtherRealm", "cross-realm server ignore saved")
	assert(#addedCalls == 0, "already present entries not re-added")

	-- Simulate restart: server returns empty list, saved entries (except own character) are restored once.
	ns.db.ignoredPlayers["ownhero"] = "OwnHero"
	ns.db.ignoredPlayers["offlineguy"] = "OfflineGuy"
	serverList = {}
	addedCalls = {}
	chat.ResetIgnoreSession()
	chat.SyncIgnoreList(true)
	assert(#addedCalls == 3, "three missing entries restored (own character skipped)")
	assert(addedCalls[1] == "OfflineGuy" and addedCalls[2] == "Spammer" and addedCalls[3] == "Troll-OtherRealm", "restored in deterministic order")

	-- Restore system messages suppressed during window, normal system messages allowed, after window allowed again.
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Spammer is now being ignored.") == true, "restore added message suppressed")
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Player not found.") == true, "restore not-found message suppressed")
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "You have gained a level.") == false, "unrelated system message kept")
	now = 105
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Spammer is now being ignored.") == false, "system messages allowed after window")

	-- Second sync in same session does not loop AddIgnore for names still missing on server.
	addedCalls = {}
	chat.SyncIgnoreList(true)
	assert(#addedCalls == 0, "no repeated AddIgnore attempts in the same session")

	-- Chat filter blocks saved names (even while missing on server) and tolerates secret senders.
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_WHISPER", "hi", "OfflineGuy-Everlook") == true, "chat filter blocks saved name")
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", "Friendly-Everlook") == false, "chat filter allows non-ignored sender")
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", secretVal) == false, "chat filter skips secret sender")

	-- Explicit removals via DelIgnore, DelIgnoreByIndex and AddOrDelIgnore remove from backup too.
	serverList = { "Spammer", "Troll-OtherRealm", "OfflineGuy" }
	chat.SyncIgnoreList(false)
	C_FriendList.DelIgnore("Spammer")
	assert(ns.db.ignoredPlayers["spammer"] == nil, "DelIgnore removes entry from backup")
	-- Stale IGNORELIST_UPDATE right after removal must not re-add the removed name.
	chat.SyncIgnoreList(false)
	assert(ns.db.ignoredPlayers["spammer"] == nil, "stale update within grace window does not re-add removed name")
	-- Explicit re-add clears the removal guard so the next server sync records it again.
	C_FriendList.AddIgnore("Spammer")
	chat.SyncIgnoreList(false)
	assert(ns.db.ignoredPlayers["spammer"] == "Spammer", "explicit re-add clears guard and saves again")

	C_FriendList.DelIgnoreByIndex(2)
	assert(ns.db.ignoredPlayers["troll-otherrealm"] == nil, "DelIgnoreByIndex removes indexed entry from backup")
	C_FriendList.AddOrDelIgnore("OfflineGuy")
	assert(ns.db.ignoredPlayers["offlineguy"] == nil, "AddOrDelIgnore on ignored player removes entry from backup")

	-- Editor window: shows sorted list, removes deleted names from server+backup and adds new ones.
	serverList = { "Spammer" }
	chat.SyncIgnoreList(false)
	deletedCalls, addedCalls = {}, {}
	local editInitial, editAccept
	ns.ShowEditWindow = function(_, _, initial, _, accept)
		editInitial, editAccept = initial, accept
	end
	chat:EditIgnoreList()
	assert(editInitial:find("Spammer", 1, true), "editor prefilled with saved names")
	editAccept("NewBaddie\nOtherBaddie-RealmTwo")
	assert(ns.db.ignoredPlayers["spammer"] == nil and ns.db.ignoredPlayers["newbaddie"] == "NewBaddie"
		and ns.db.ignoredPlayers["otherbaddie-realmtwo"] == "OtherBaddie-RealmTwo", "editor updates saved list")
	assert(deletedCalls[1] == "Spammer", "editor removes deleted server ignore")
	assert(#addedCalls == 2, "editor adds newly typed ignores to server")

	-- Turning option off disables chat filter without wiping saved names.
	chat.db.keepIgnore = false
	chat:OnOptionChanged("keepIgnore", false)
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", "NewBaddie") == false, "chat filter inactive when option is off")
	assert(ns.db.ignoredPlayers["newbaddie"] == "NewBaddie", "saved list kept when option is toggled off")

	-- Restore environment.
	chat.ResetIgnoreSession()
	C_FriendList = saved.C_FriendList
	GetNormalizedRealmName = saved.GetNormalizedRealmName
	GetRealmName = saved.GetRealmName
	RegionalUniqueNamesEnabled = saved.RegionalUniqueNamesEnabled
	UnitFullName = saved.UnitFullName
	GetTime = saved.GetTime
	hooksecurefunc = saved.hooksecurefunc
	issecretvalue = saved.issecretvalue
	ns.ShowEditWindow = saved.ShowEditWindow
	ERR_IGNORE_ADDED_S = saved.ERR_IGNORE_ADDED_S
	ERR_IGNORE_ALREADY_S = saved.ERR_IGNORE_ALREADY_S
	ERR_IGNORE_NOT_FOUND = saved.ERR_IGNORE_NOT_FOUND
	ERR_IGNORE_SELF = saved.ERR_IGNORE_SELF
	chat.db.keepIgnore = saved.keepIgnore
	ns.db.ignoredPlayers = saved.ignoredPlayers
	chat:UpdateIgnoreList(false)
	print("chat ignore list OK")
end)()
;(function()
	-- Performance regression tests: Camera CVar throttling/staggering, Helpers coalescing/quest-item gating,
	-- BankView incremental bag scans, and Quests prefix/suffix preservation + instance-quest cache.
	local camera = ns:GetModule("Camera")
	local saved = {
		GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, GetTime, ns.NewTicker,
		camera.State, camera.db.saved, camera.db.enabled,
	}
	local cvars = {
		CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0", test_cameraDynamicPitch = "0",
		test_cameraOverShoulder = "1", test_cameraDynamicPitchBaseFovPad = "0.3",
		cameraDistanceMaxZoomFactor = "2", cameraYawMoveSpeed = "180",
	}
	local setCalls, now, state, zoom = 0, 100, {}, 10
	GetCVar = function(k) return cvars[k] end
	SetCVar = function(k, v) setCalls = setCalls + 1; cvars[k] = tostring(v) end
	GetCameraZoom = function() return zoom end
	CameraZoomOut = function(d) zoom = zoom + d end
	CameraZoomIn = function(d) zoom = zoom - d end
	GetTime = function() return now end
	ns.NewTicker = function() return { Cancel = function() end } end
	camera.State = function() return state end
	camera.db.saved, camera.db.enabled = {}, true
	camera:OnOptionChanged("enabled", true)
	local blender = uv(uv(camera.Apply, "BlendTo"), "blender")
	local function Go(nextState)
		state = nextState
		camera.Update()
		now = now + 0.7
		camera.Update()
	end
	-- Start settled outdoors (shoulder=1, pad=0.3); indoors keeps shoulder=1, pad=0.3 -> 0 SetCVar calls during zoom blend.
	Go({})
	setCalls = 0
	Go({ indoors = true })
	for _ = 1, 10 do
		now = now + 0.1
		if blender and blender.scripts.OnUpdate then blender.scripts.OnUpdate(blender, 0.1) end
	end
	assert(setCalls == 0, "camera blend with unchanged shoulder/pad never calls SetCVar: " .. setCalls)

	-- Switch to combat (both shoulder 1->0.6 and pad 0.3->0.35 change): throttled (<0.05s = 0 calls) and staggered (<=1 per tick).
	Go({ combat = true })
	blender = uv(uv(camera.Apply, "BlendTo"), "blender")
	setCalls = 0
	for _ = 1, 5 do
		now = now + 0.008
		blender.scripts.OnUpdate(blender, 0.008)
	end
	assert(setCalls == 0, "camera blend skips SetCVar inside the 50 ms throttle window")
	now = now + 0.5
	setCalls = 0
	blender.scripts.OnUpdate(blender, 0.5)
	assert(setCalls <= 1, "camera blend staggers shoulder and pad to at most one SetCVar per intermediate frame: " .. setCalls)
	now = now + 3
	blender.scripts.OnUpdate(blender, 3)
	assert(cvars.test_cameraOverShoulder == "0.6" and cvars.test_cameraDynamicPitchBaseFovPad == "0.35",
		"camera blend still lands on exact targets at completion")
	camera.db.enabled = false
	camera:OnOptionChanged("enabled", false)
	GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, GetTime, ns.NewTicker = unpack(saved, 1, 7)
	camera.State, camera.db.saved, camera.db.enabled = saved[8], saved[9], saved[10]

	-- Helpers: QUEST_LOG_UPDATE skips scanning bags when bags contain no quest-starting item; bursts coalesce.
	local helpers = ns:GetModule("Helpers")
	local savedAfter, savedSlots, savedItem, savedQuestInfo = C_Timer.After, C_Container.GetContainerNumSlots,
		C_Container.GetContainerItemInfo, C_Container.GetContainerItemQuestInfo
	local savedOpenOpt = helpers.db.openButton
	local deferred, slotScans = {}, 0
	C_Timer.After = function(_, fn) deferred[#deferred + 1] = fn end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(_, slot)
		slotScans = slotScans + 1
		return slot == 1 and { itemID = 10, hasLoot = false, isLocked = false } or nil
	end
	C_Container.GetContainerItemQuestInfo = function() return nil end
	helpers.db.openButton = true
	local listeners = uv(ns.RegisterEvent, "listeners")
	local onBag = listeners.BAG_UPDATE_DELAYED[helpers]
	local onQuest = listeners.QUEST_LOG_UPDATE[helpers]
	onBag(helpers, "BAG_UPDATE_DELAYED")
	onQuest(helpers, "QUEST_LOG_UPDATE")
	assert(#deferred == 1 and slotScans == 0, "BAG_UPDATE_DELAYED + QUEST_LOG_UPDATE coalesce into one deferred scan")
	deferred[1]()
	assert(slotScans == 2, "coalesced scan runs once")
	deferred, slotScans = {}, 0
	onQuest(helpers, "QUEST_LOG_UPDATE")
	assert(#deferred == 0 and slotScans == 0, "QUEST_LOG_UPDATE skips bag scan when bags have no quest item")
	helpers.db.openButton = savedOpenOpt
	C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo,
		C_Container.GetContainerItemQuestInfo = savedAfter, savedSlots, savedItem, savedQuestInfo

	-- BankView: BAG_UPDATE(1) + BAG_UPDATE_DELAYED scans only bag 1 on the deferred tick, not all bags or gear.
	local bankView = ns:GetModule("BankView")
	local bvSaved = { C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, GetInventoryItemID }
	local scannedBags, gearScans, bvDeferred = {}, 0, {}
	C_Timer.After = function(_, fn) bvDeferred[#bvDeferred + 1] = fn end
	C_Container.GetContainerNumSlots = function(bag)
		scannedBags[bag] = (scannedBags[bag] or 0) + 1
		return 1
	end
	C_Container.GetContainerItemInfo = function(bag, slot)
		if bag == 1 and slot == 1 then return { itemID = 4242, stackCount = 7 } end
	end
	GetInventoryItemID = function() gearScans = gearScans + 1 return nil end
	listeners.BAG_UPDATE[bankView](bankView, "BAG_UPDATE", 1)
	listeners.BAG_UPDATE_DELAYED[bankView](bankView, "BAG_UPDATE_DELAYED")
	assert(#bvDeferred == 1 and not next(scannedBags), "BankView defers owned-count scan off BAG_UPDATE_DELAYED")
	bvDeferred[1]()
	assert(scannedBags[1] == 1 and not scannedBags[0] and not scannedBags[2] and gearScans == 0,
		"BankView only rescans the dirty bag and skips unchanged bags and gear")
	C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo,
		GetInventoryItemID = unpack(bvSaved, 1, 4)

	-- Quests: WriteWatches preserves unchanged suffix/prefix after order verification.
	local quests = ns:GetModule("Quests")
	local qSort = uv(uv(quests.UpdateTrackerSort, "QueueSort"), "SortTracker")
	local writeWatches = uv(qSort, "WriteWatches")
	local qSaved = { C_QuestLog.RemoveQuestWatch, C_QuestLog.AddQuestWatch, C_SuperTrack.GetSuperTrackedQuestID }
	local removed, added = 0, 0
	C_QuestLog.RemoveQuestWatch = function() removed = removed + 1 end
	C_QuestLog.AddQuestWatch = function() added = added + 1 end
	C_SuperTrack.GetSuperTrackedQuestID = function() return 0 end
	local savedAddsOnTop = uv(writeWatches, "addsOnTop")
	local savedVerified = uv(writeWatches, "orderVerified")
	setuv(writeWatches, "addsOnTop", false)
	setuv(writeWatches, "orderVerified", true)
	writeWatches({ 11, 12, 13 }, { 11, 12, 13, 14 })
	assert(removed == 0 and added == 1, "WriteWatches keeps matching prefix and only adds the new bottom watch")
	removed, added = 0, 0
	setuv(writeWatches, "addsOnTop", true)
	writeWatches({ 11, 12, 13 }, { 14, 11, 12, 13 })
	assert(removed == 0 and added == 1, "WriteWatches keeps matching suffix when new watches land on top")
	setuv(writeWatches, "addsOnTop", savedAddsOnTop)
	setuv(writeWatches, "orderVerified", savedVerified)
	C_QuestLog.RemoveQuestWatch, C_QuestLog.AddQuestWatch, C_SuperTrack.GetSuperTrackedQuestID = unpack(qSaved, 1, 3)

	print("performance spike fixes OK")
end)()
;(function()
	-- Item rating: passive stat conversions and percentage stat multipliers scale with the character's learned talent ranks.
	local items = ns:GetModule("Items")
	local getW = ns.StatWeights
	local weightsTable = upvalue(getW, "WEIGHTS")
	local bearBase = upvalue(getW, "FERAL_BEAR")
	local function near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-4 end

	-- Warrior and Rogue have no passive stat-conversion or percentage stat-multiplier talents.
	for _, cls in ipairs({ "WARRIOR", "ROGUE" }) do
		for p = 1, 3 do
			assert(items.AdjustWeights(weightsTable[cls][p], cls, p, {}) == weightsTable[cls][p], cls .. " unchanged")
		end
	end

	-- Shaman: Mental Dexterity (415140), Mental Quickness (30812), Ancestral Knowledge (17485), Toughness (16252), Improved Reincarnation (16184).
	local enh = weightsTable.SHAMAN[2]
	assert(items.AdjustWeights(enh, "SHAMAN", 2, { [17485] = 3, [415140] = 3, [30812] = 2 }) == enh, "Enhancement reference identity")
	local enh0 = items.AdjustWeights(enh, "SHAMAN", 2, {})
	local enh1 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 1 })
	local enh2 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 2 })
	local enh3 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 3 })
	local enh3mq = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 3, [30812] = 2 })
	local enhMax = items.AdjustWeights(enh, "SHAMAN", 2, { [17485] = 5, [415140] = 3, [30812] = 2, [16252] = 5, [16184] = 2 })
	assert(near(enh0.INT, 0.25) and enh0.INT < enh1.INT and enh1.INT < enh2.INT and enh2.INT < enh3.INT
		and enh3.INT < enh3mq.INT and enh3mq.INT < enh.INT and enh.INT < enhMax.INT, "Enhancement INT scales cleanly per rank")
	assert(near(enhMax.STA, enh.STA * 1.10 * 1.04), "Shaman Toughness and Improved Reincarnation stack on STA")
	local restoMQ = items.AdjustWeights(weightsTable.SHAMAN[3], "SHAMAN", 3, { [17485] = 5, [30812] = 2, [415140] = 3 })
	assert(near(restoMQ.INT, weightsTable.SHAMAN[3].INT + 1.10 * 0.30 * weightsTable.SHAMAN[3].HEAL),
		"Restoration Shaman gains Mental Quickness healing conversion, ignores Mental Dexterity AP")

	-- Paladin: Champion of the Light (1311084), Divine Intellect (20257), Divine Strength (20262), Toughness (20143), Shield Specialization (20150).
	local ret = weightsTable.PALADIN[3]
	assert(items.AdjustWeights(ret, "PALADIN", 3, { [20262] = 5, [20257] = 5, [1311084] = 5 }) == ret, "Retribution reference identity")
	local ret0 = items.AdjustWeights(ret, "PALADIN", 3, {})
	assert(near(ret0.STR, ret.STR / 1.10) and near(ret0.INT, ret.INT / 1.10 - 0.60 * ret.SP), "Retribution at 0 ranks")
	local prot = weightsTable.PALADIN[2]
	local prot0 = items.AdjustWeights(prot, "PALADIN", 2, {})
	assert(near(prot0.BVAL, prot.BVAL / 1.30) and near(prot0.ARMOR, prot.ARMOR / 1.06), "Protection Paladin BVAL and ARMOR at 0 ranks")
	local protCotL = items.AdjustWeights(prot, "PALADIN", 2, { [20143] = 3, [20150] = 2, [1311084] = 5 })
	assert(near(protCotL.INT, prot.INT + 0.60 * prot.SP), "Protection Paladin benefits from Champion of the Light")
	local holyCotL = items.AdjustWeights(weightsTable.PALADIN[1], "PALADIN", 1, { [20257] = 5, [20143] = 5, [1311084] = 5 })
	assert(holyCotL == weightsTable.PALADIN[1], "Holy Paladin ignores damage-only Champion of the Light")

	-- Hunter: Careful Aim (1223984), Lightning Reflexes (19168), Survivalist (19255).
	local bm0 = items.AdjustWeights(weightsTable.HUNTER[1], "HUNTER", 1, {})
	assert(near(bm0.INT, weightsTable.HUNTER[1].INT - (weightsTable.HUNTER[1].AP + weightsTable.HUNTER[1].RAP)), "BM Hunter without Careful Aim")
	local sv0 = items.AdjustWeights(weightsTable.HUNTER[3], "HUNTER", 3, {})
	assert(near(sv0.AGI, weightsTable.HUNTER[3].AGI / 1.15) and near(sv0.INT, weightsTable.HUNTER[3].INT - 0.7), "Survival Hunter at 0 ranks")
	local bmSurv = items.AdjustWeights(weightsTable.HUNTER[1], "HUNTER", 1, { [1223984] = 5, [19255] = 5 })
	assert(near(bmSurv.STA, weightsTable.HUNTER[1].STA * 1.10), "Hunter Survivalist scales STA")

	-- Priest: Mental Strength (18551), Spiritual Guidance (14901).
	local holy0 = items.AdjustWeights(weightsTable.PRIEST[2], "PRIEST", 2, {})
	assert(near(holy0.SPI, weightsTable.PRIEST[2].SPI - 0.25) and near(holy0.INT, weightsTable.PRIEST[2].INT / 1.10), "Holy Priest at 0 ranks")
	local discSG = items.AdjustWeights(weightsTable.PRIEST[1], "PRIEST", 1, { [18551] = 5, [14901] = 5 })
	assert(near(discSG.SPI, weightsTable.PRIEST[1].SPI + 0.25), "Discipline Priest with Spiritual Guidance")
	local shadowSG = items.AdjustWeights(weightsTable.PRIEST[3], "PRIEST", 3, { [18551] = 3, [14901] = 5 })
	assert(near(shadowSG.SPI, weightsTable.PRIEST[3].SPI + 0.08), "Shadow Priest gets spell-damage portion of Spiritual Guidance")

	-- Mage: Arcane Mind (11232), Arcane Resilience (28574).
	local arcane0 = items.AdjustWeights(weightsTable.MAGE[1], "MAGE", 1, {})
	assert(near(arcane0.INT, weightsTable.MAGE[1].INT / 1.10), "Arcane Mage without Arcane Mind")
	local frost0 = items.AdjustWeights(weightsTable.MAGE[3], "MAGE", 3, {})
	assert(near(frost0.INT, weightsTable.MAGE[3].INT - 0.75 * weightsTable.MAGE[3].ARMOR), "Frost Mage without Arcane Resilience")

	-- Warlock: Demonic Embrace (18697).
	local aff0 = items.AdjustWeights(weightsTable.WARLOCK[1], "WARLOCK", 1, {})
	assert(near(aff0.STA, weightsTable.WARLOCK[1].STA / 1.15), "Affliction Warlock without Demonic Embrace")
	local demoDE = items.AdjustWeights(weightsTable.WARLOCK[2], "WARLOCK", 2, { [18697] = 5 })
	assert(near(demoDE.STA, weightsTable.WARLOCK[2].STA * 1.15), "Demonology Warlock with Demonic Embrace")

	-- Druid: Heart of the Wild (17003), Living Spirit (1309631), Natural Instinct (1223242), Thick Hide (16929).
	local cat0 = items.AdjustWeights(weightsTable.DRUID[2], "DRUID", 2, {})
	assert(near(cat0.STR, weightsTable.DRUID[2].STR / 1.10) and cat0.STA == weightsTable.DRUID[2].STA, "Cat Druid HotW scales STR only")
	local bear0 = items.AdjustWeights(bearBase, "DRUID", 4, {})
	assert(near(bear0.STA, bearBase.STA / 1.20) and near(bear0.DEF, bearBase.DEF - 2.0 * bearBase.ARMOR)
		and bear0.STR == bearBase.STR, "Bear Druid HotW STA and Thick Hide DEF->ARMOR")
	local restoDruid = items.AdjustWeights(weightsTable.DRUID[3], "DRUID", 3, { [17003] = 5, [1309631] = 3, [1223242] = 2, [16929] = 3 })
	assert(near(restoDruid.INT, weightsTable.DRUID[3].INT + 1.10 * 0.25 * weightsTable.DRUID[3].HEAL)
		and restoDruid.DEF == nil, "Resto Druid gains Natural Instinct HEAL, ignores form-only Thick Hide")

	-- End-to-end C_Traits integration in ns.StatWeights() (including Bear profile and fallback on missing/secret data).
	local saved = {
		class = upvalue(getW, "playerClass"), weights = upvalue(getW, "weights"),
		tree = upvalue(getW, "weightsTree"), name = upvalue(getW, "weightsName"), preset = upvalue(getW, "weightsPreset"),
		traits = C_Traits, ct = C_ClassTalents, level = UnitLevel, spec = items.cdb.scoreSpec,
	}
	local activeRanks = {}
	local nodeMap = { [1] = 415140, [2] = 30812, [3] = 17485, [4] = 17003, [5] = 16929 }
	C_ClassTalents = { GetActiveConfigID = function() return 42 end }
	C_Traits = {
		GetConfigInfo = function(id) return id == 42 and { treeIDs = { 99 } } or nil end,
		GetGroupDisplayInfoByTreeID = function()
			return {
				{ groupID = 1, orderIndex = 0, displayName = "Tree1" },
				{ groupID = 2, orderIndex = 1, displayName = "Tree2" },
				{ groupID = 3, orderIndex = 2, displayName = "Tree3" },
			}
		end,
		GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 2, currencyInfos = { { spent = 10 } } } } end,
		GetTreeNodes = function(tid) return tid == 99 and { 1, 2, 3, 4, 5 } or {} end,
		GetNodeInfo = function(_, nid)
			local r = activeRanks[nodeMap[nid]] or 0
			return { activeRank = r, activeEntry = r > 0 and { entryID = nid } or nil }
		end,
		GetEntryInfo = function(_, eid) return { definitionID = eid } end,
		GetDefinitionInfo = function(did) return { spellID = nodeMap[did] } end,
	}
	UnitLevel = function() return 60 end
	setuv(getW, "playerClass", "SHAMAN")
	items.cdb.scoreSpec = 2
	setuv(getW, "weights", nil)
	local w0 = ns.StatWeights()
	assert(near(w0.INT, 0.25), "live StatWeights lowers Enhancement INT when Mental Dexterity is 0/3")
	activeRanks[415140], activeRanks[30812], activeRanks[17485] = 3, 2, 3
	setuv(getW, "weights", nil)
	local wRef = ns.StatWeights()
	assert(wRef == weightsTable.SHAMAN[2], "live StatWeights matches reference table at reference ranks")
	setuv(getW, "playerClass", "DRUID")
	items.cdb.scoreSpec = 4
	activeRanks = { [17003] = 0, [16929] = 0 }
	setuv(getW, "weights", nil)
	local wBear0 = ns.StatWeights()
	assert(near(wBear0.STA, bearBase.STA / 1.20) and near(wBear0.DEF, bearBase.DEF - 2.0 * bearBase.ARMOR),
		"live StatWeights adjusts Bear profile via C_Traits")
	setuv(getW, "playerClass", saved.class)
	setuv(getW, "weights", saved.weights)
	setuv(getW, "weightsTree", saved.tree)
	setuv(getW, "weightsName", saved.name)
	setuv(getW, "weightsPreset", saved.preset)
	C_Traits, C_ClassTalents, UnitLevel, items.cdb.scoreSpec = saved.traits, saved.ct, saved.level, saved.spec
	print("talent stat weights OK")
end)()
;(function()
	-- ProfessionPlan ScanTrainer: skip tooltip builds for known/cached recipes and respect per-visit tooltip budget.
	local plan = ns:GetModule("ProfessionPlan")
	local scan = uv(plan.OnLogin, "ScanTrainer")
	local saved = {
		C_Trainer, Enum.TrainerType, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter,
		GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceSkillLine,
		GetTrainerServiceLevelReq, GetTrainerServiceCost, GetTrainerServiceItemLink, C_TooltipInfo,
		C_Spell, C_TradeSkillUI, debugprofilestop, plan.cdb.trainers,
	}
	local clock, tooltipReads = 0, 0
	local services = {
		{ name = "Known Recipe", kind = "used", skill = "Schmiedekunst", rank = 10 },
		{ name = "Cached Recipe", kind = "available", skill = "Schmiedekunst", rank = 25 },
		{ name = "Direct Link", kind = "available", skill = "Schmiedekunst", rank = 40, link = "|Hitem:1234|h[Sword]|h" },
		{ name = "Uncached One", kind = "available", skill = "Schmiedekunst", rank = 50, tipID = 5001 },
		{ name = "Over Budget", kind = "available", skill = "Schmiedekunst", rank = 60, tipID = 5002 },
	}
	Enum.TrainerType = { Tradeskills = 1 }
	C_Trainer = { GetTrainerType = function() return 1 end }
	GetTrainerServiceTypeFilter = function() return true end
	SetTrainerServiceTypeFilter = function() end
	GetNumTrainerServices = function() return #services end
	GetTrainerServiceInfo = function(i) return services[i].name, services[i].kind, 134400 end
	GetTrainerServiceSkillReq = function(i) return services[i].skill, services[i].rank end
	GetTrainerServiceSkillLine = function(i) return services[i].skill end
	GetTrainerServiceLevelReq = function() return 1 end
	GetTrainerServiceCost = function() return 100 end
	GetTrainerServiceItemLink = function(i) return services[i].link end
	C_Spell = { GetSpellIDForSpellIdentifier = function() return nil end }
	C_TradeSkillUI = { GetProfessionInfoByRecipeID = function() return nil end }
	C_TooltipInfo = { GetTrainerService = function(i)
		tooltipReads = tooltipReads + 1
		clock = clock + 2.0 -- first uncached tooltip exhausts the 1.5 ms budget
		return { id = services[i].tipID, type = Enum.TooltipDataType.Spell }
	end }
	debugprofilestop = function() return clock end
	plan.cdb.trainers = { ["Schmiedekunst"] = { { name = "Cached Recipe", recipeID = 4242 } } }
	scan()
	local savedList = plan.cdb.trainers["Schmiedekunst"]
	assert(tooltipReads == 1, "ScanTrainer skips known/cached/linked entries and stops after tooltip budget: " .. tooltipReads)
	assert(savedList[2].recipeID == 4242 and savedList[3].link == "|Hitem:1234|h[Sword]|h"
		and savedList[4].recipeID == 5001 and savedList[5].recipeID == nil,
		"ScanTrainer preserves cached IDs, direct links and budgeted tooltip IDs")
	-- Second visit reuses newly saved IDs without rebuilding tooltips for them.
	tooltipReads, clock = 0, 0
	scan()
	assert(tooltipReads == 1 and plan.cdb.trainers["Schmiedekunst"][5].recipeID == 5002,
		"next trainer visit fills only the remaining uncached entry")
	C_Trainer, Enum.TrainerType, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = unpack(saved, 1, 4)
	GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceSkillLine = unpack(saved, 5, 8)
	GetTrainerServiceLevelReq, GetTrainerServiceCost, GetTrainerServiceItemLink, C_TooltipInfo = unpack(saved, 9, 12)
	C_Spell, C_TradeSkillUI, debugprofilestop, plan.cdb.trainers = unpack(saved, 13, 16)

	-- Instrumentation: ns.OnAddOnLoaded and /fp slash commands record timings into session/measuring stats.
	local savedEventUtil, savedClock2, savedTime = EventUtil, debugprofilestop, GetTime
	local tClock, tNow = 0, 2000
	GetTime = function() return tNow end
	debugprofilestop = function() return tClock end
	EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
	ns.SetMeasuring(true)
	tNow = 2001
	ns.OnAddOnLoaded("Blizzard_TestLoad", function() tClock = tClock + 6.0 end)
	assert(ns.timings["OnAddOnLoaded: Blizzard_TestLoad"] and ns.timings["OnAddOnLoaded: Blizzard_TestLoad"].max == 6.0,
		"ns.OnAddOnLoaded callbacks are measured")
	local savedPrint = ns.PrintAlways
	ns.PrintAlways = function() tClock = tClock + 7.5 end
	SlashCmdList.FOREVERPLUS("hilfe")
	ns.PrintAlways = savedPrint
	assert(ns.timings["Slash: /fp hilfe"] and ns.timings["Slash: /fp hilfe"].max == 7.5,
		"slash commands are measured")
	ns.SetMeasuring(false)
	EventUtil, debugprofilestop, GetTime = savedEventUtil, savedClock2, savedTime
	print("trainer scan and instrumentation OK")
end)()
;(function()
	-- Compact group loot roll frames (Modules/LootRoll.lua)
	local lr = ns:GetModule("LootRoll")
	assert(lr and lr.db.enabled == true, "LootRoll module loaded and enabled by default")
	for _, opt in ipairs(lr.options) do
		if opt.type ~= "button" then
			assert(opt.new == true, "LootRoll option marked NEW: " .. tostring(opt.key))
		end
	end
	lr._ResetStateForTests()

	local saved = {
		GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot, ConfirmLootRoll,
		IsShiftKeyDown, C_LootHistory, C_ClassColor, Enum.EncounterLootDropRollState,
		LOOT_ROLL_INELIGIBLE_REASON1, LOOT_ROLL_NEED, LOOT_ROLL_PASSED,
		C_Item.GetItemInfoInstant, ns.RewardComparisonState,
	}
	C_Item.GetItemInfoInstant = function(link)
		return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	end
	ns.RewardComparisonState = function(link)
		return type(link) == "string" and link:find("item:17182", 1, true) and "better" or nil
	end
	local rolls = {
		[101] = {
			tex = 135328, name = "Sulfuras Shard", count = 1, quality = 4, bop = true,
			canNeed = true, canGreed = true, canDE = false, rNeed = nil, rGreed = nil, rDE = nil, deSkill = nil, canTransmog = false,
			link = "|cffa335ee|Hitem:17182::::::::60:::::::|h[Sulfuras Shard]|h|r", left = 45000,
		},
		[102] = {
			tex = 134414, name = "Sapphire Ring", count = 2, quality = 3, bop = false,
			canNeed = false, canGreed = true, canDE = true, rNeed = 1, rGreed = nil, rDE = nil, deSkill = nil, canTransmog = true,
			link = "|cff0070dd|Hitem:20001::::::::60:::::::|h[Sapphire Ring]|h|r", left = 30000,
		},
	}
	LOOT_ROLL_INELIGIBLE_REASON1 = "Cannot roll need"
	LOOT_ROLL_NEED = "%s has selected Need for: %s"
	LOOT_ROLL_PASSED = "%s passed on: %s"
	GetLootRollItemInfo = function(id)
		local r = rolls[id]
		if not r then return nil end
		return r.tex, r.name, r.count, r.quality, r.bop, r.canNeed, r.canGreed, r.canDE, r.rNeed, r.rGreed, r.rDE, r.deSkill, r.canTransmog
	end
	GetLootRollItemLink = function(id) return rolls[id] and rolls[id].link end
	GetLootRollTimeLeft = function(id) return rolls[id] and rolls[id].left or 0 end
	local rolled, confirmed = {}, {}
	RollOnLoot = function(id, rt) rolled[#rolled + 1] = { id, rt } end
	ConfirmLootRoll = function(id, rt) confirmed[#confirmed + 1] = { id, rt } end
	local shiftDown = false
	IsShiftKeyDown = function() return shiftDown end
	Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
	C_ClassColor = {
		GetClassColor = function(cls)
			if cls == "WARRIOR" then
				return { WrapTextInColorCode = function(_, s) return "|cffc69b6d" .. s .. "|r" end }
			end
		end,
	}

	-- Open two rolls and verify BoP/BoE, Transmog/DE buttons and disabled reason.
	lr:START_LOOT_ROLL("START_LOOT_ROLL", 101, 60000)
	lr:START_LOOT_ROLL("START_LOOT_ROLL", 102, 60000)
	assert(#lr._activeBars == 2, "two compact loot roll bars opened")
	local b1, b2 = lr._activeBars[1], lr._activeBars[2]
	assert(b1.rollID == 101 and b1.bop == true and not b1.showTransmog and not b1.showDisenchant, "bar 1 BoP standard buttons")
	assert(b1.UpgradeArrow:IsShown() and not b2.UpgradeArrow:IsShown(), "upgrade arrow shown only for better gear")
	assert(b2.rollID == 102 and b2.bop == false and b2.showTransmog and b2.showDisenchant, "bar 2 BoE transmog + DE buttons")
	assert(b2.buttons.need.reason == "Cannot roll need", "disabled need button stores ineligible reason")

	-- Clicks: normal uses RollOnLoot, Shift uses ConfirmLootRoll for non-pass rolls.
	b1.buttons.need:GetScript("OnClick")(b1.buttons.need)
	assert(#rolled == 1 and rolled[1][1] == 101 and rolled[1][2] == 1, "normal click calls RollOnLoot")
	shiftDown = true
	b1.buttons.need:GetScript("OnClick")(b1.buttons.need)
	assert(#confirmed == 1 and confirmed[1][1] == 101 and confirmed[1][2] == 1, "shift-click calls ConfirmLootRoll")
	b1.buttons.pass:GetScript("OnClick")(b1.buttons.pass)
	assert(#rolled == 2 and rolled[2][1] == 101 and rolled[2][2] == 0, "shift-click on pass still uses RollOnLoot")
	shiftDown = false

	-- Chat fallback updates counts on rolls without C_LootHistory.
	lr:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Thrall has selected Need for: " .. rolls[101].link)
	assert(#b1.voters.need == 1 and b1.voters.need[1] == "Thrall", "chat fallback tracks non-boss roll votes")

	-- C_LootHistory updates counts with class colors and roll numbers, and takes precedence over chat.
	C_LootHistory = {
		GetSortedInfoForDrop = function()
			return {
				itemHyperlink = rolls[101].link,
				rollInfos = {
					{ playerName = "Arthas", playerClass = "WARRIOR", state = 0, roll = 92 },
					{ playerName = "Jaina", playerClass = "MAGE", state = 5 },
				},
			}
		end,
	}
	lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
	assert(#b1.voters.need == 1 and b1.voters.need[1] == "|cffc69b6dArthas|r (92)", "C_LootHistory sets class-colored roll voter")
	assert(#b1.voters.pass == 1 and b1.voters.pass[1] == "Jaina", "C_LootHistory sets pass voter")

	-- Cancel removes the roll bar cleanly; preview toggles and dismisses without calling RollOnLoot.
	lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 101)
	assert(#lr._activeBars == 1 and lr._activeBars[1].rollID == 102, "CANCEL_LOOT_ROLL removes only matching roll")
	lr:CANCEL_ALL_LOOT_ROLLS()
	assert(#lr._activeBars == 0, "CANCEL_ALL_LOOT_ROLLS clears active rolls")

	local rolledBefore = #rolled
	lr.TogglePreview()
	assert(#lr._activeBars == 3, "preview shows 3 sample bars")
	lr._activeBars[1].buttons.pass:GetScript("OnClick")(lr._activeBars[1].buttons.pass)
	assert(#lr._activeBars == 2 and #rolled == rolledBefore, "clicking preview bar dismisses it without RollOnLoot")
	lr.TogglePreview()
	assert(#lr._activeBars == 0, "second TogglePreview hides remaining preview bars")

	-- Height, width, scale and Edit Mode options panel integration.
	assert(lr.db.height == 28, "LootRoll height defaults to 28")
	local editEntry = ns.editFrames and ns.editFrames.LootRoll
	assert(editEntry and type(editEntry.onClick) == "function", "LootRoll registers Edit Mode click handler")
	local anchor = lr._GetAnchor()
	local anchorW, anchorH, barW, barH, barScale, barStrata
	local origAnchorSize = anchor.SetSize
	anchor.SetSize = function(_, w, h) anchorW, anchorH = w, h end
	local origBarSize, origBarScale, origBarStrata = b1.SetSize, b1.SetScale, b1.SetFrameStrata
	b1.SetSize = function(_, w, h) barW, barH = w, h end
	b1.SetScale = function(_, s) barScale = s end
	b1.SetFrameStrata = function(_, st) barStrata = st end

	ns.SetOption("LootRoll", "width", 400)
	ns.SetOption("LootRoll", "height", 36)
	ns.SetOption("LootRoll", "scale", 1.25)
	assert(anchorW == 500 and anchorH == 45, "anchor tracks scaled width and height")
	assert(barW == 400 and barH == 36 and barScale == 1.25, "bars apply width, height and scale")

	-- Edit Mode shows preview bars at LOW strata and opens the options panel with 3 sliders (scale, width, height).
	local savedIsEdit = ns.IsEditModeActive
	ns.IsEditModeActive = function() return true end
	editEntry.onEditMode(true)
	assert(#lr._activeBars == 2 and barStrata == "LOW", "Edit Mode shows preview bars behind selection frame")
	editEntry.onClick(anchor)
	local panel = lr._GetEditPanel()
	assert(panel and panel:IsShown() and #panel.refreshers == 3 and panel.growCheck,
		"Edit Mode options panel opens with scale, width, height sliders and growUp toggle")
	ns.IsEditModeActive = function() return false end
	editEntry.onEditMode(false)
	assert(not panel:IsShown() and #lr._activeBars == 0, "exiting Edit Mode hides options panel and preview bars")

	ns.IsEditModeActive = savedIsEdit
	anchor.SetSize = origAnchorSize
	b1.SetSize, b1.SetScale, b1.SetFrameStrata = origBarSize, origBarScale, origBarStrata
	ns.SetOption("LootRoll", "width", 328)
	ns.SetOption("LootRoll", "height", 28)
	ns.SetOption("LootRoll", "scale", 1)

	lr._ResetStateForTests()
	GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot, ConfirmLootRoll = unpack(saved, 1, 5)
	IsShiftKeyDown, C_LootHistory, C_ClassColor, Enum.EncounterLootDropRollState = unpack(saved, 6, 9)
	LOOT_ROLL_INELIGIBLE_REASON1, LOOT_ROLL_NEED, LOOT_ROLL_PASSED = unpack(saved, 10, 12)
	C_Item.GetItemInfoInstant, ns.RewardComparisonState = saved[13], saved[14]
	print("compact loot roll frames OK")
end)()
;(function()
	-- MapSymbols slicing, RecipeRadar targeted invalidation + scan budget, Camera state reuse,
	-- MeasuredReturn chat filters and frame-level GC tagging.
	local camera = ns:GetModule("Camera")
	local s1, s2 = camera.State(), camera.State()
	assert(s1 == s2, "Camera.State reuses its table instead of allocating every tick")

	-- MeasuredReturn preserves multiple return values (including nils) and records timings.
	local savedClock, savedTime = debugprofilestop, GetTime
	local clock, now = 0, 2100
	debugprofilestop = function() return clock end
	GetTime = function() return now end
	ns.SetMeasuring(true)
	now = 2101
	local wrapped = ns.MeasuredReturn("Test: multi return", function(a, b)
		clock = clock + 1.2
		return false, a, nil, b
	end)
	local r1, r2, r3, r4 = wrapped("msg", "sender")
	assert(r1 == false and r2 == "msg" and r3 == nil and r4 == "sender",
		"MeasuredReturn preserves all return values including false and nil")
	assert(ns.timings["Test: multi return"] and ns.timings["Test: multi return"].max == 1.2,
		"MeasuredReturn records call duration")
	ns.SetMeasuring(false)
	debugprofilestop, GetTime = savedClock, savedTime

	-- RecipeRadar OnItemInfo keeps cached entries for other recipes and ignores unrelated items.
	local radar = ns:GetModule("RecipeRadar")
	local refresh = uv(radar.RequestRefresh, "Refresh")
	local onItemInfo = uv(refresh, "OnItemInfo")
	local statusCache = uv(onItemInfo, "statusCache")
	local recipes = uv(onItemInfo, "recipes")
	local anyID = next(recipes)
	assert(anyID, "radar has recipe entries")
	local savedRefreshReq = radar.RequestRefresh
	local reqCount = 0
	radar.RequestRefresh = function() reqCount = reqCount + 1 end
	statusCache[anyID] = "ok"
	statusCache[999999] = "ok"
	onItemInfo(radar, "GET_ITEM_INFO_RECEIVED", 888888, true)
	assert(reqCount == 0 and statusCache[anyID] == "ok" and statusCache[999999] == "ok",
		"non-recipe GET_ITEM_INFO_RECEIVED does not wipe statusCache or schedule refresh")
	onItemInfo(radar, "GET_ITEM_INFO_RECEIVED", anyID, true)
	assert(reqCount == 1 and statusCache[anyID] == nil and statusCache[999999] == "ok",
		"recipe GET_ITEM_INFO_RECEIVED invalidates only the affected recipe")
	statusCache[999999] = nil
	radar.RequestRefresh = savedRefreshReq

	-- Unattributed >5 ms moment with frame-level GC drop gets the (GC) tag.
	local info = ns:GetModule("Info")
	local record = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "SampleAddonMetrics")
	record = uv(record, "RecordSpikeMoment")
	record(2102, { name = ns.name, title = ns.name, own = true }, 9.5, nil, nil, nil, nil, nil, true)
	local text = info.SpikesText()
	assert(text:find(ns.L.INFO_SPIKES_UNATTRIBUTED_GC, 1, true), "unattributed GC spike is labelled with (GC)")
	uv(info.ShowSpikes, "ResetSession")()
	assert(info.SpikesText(true) == nil, "ResetSession clears the recorded GC moment")
	print("map/radar/gc optimization OK")
end)()

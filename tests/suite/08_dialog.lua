(function()
	-- Targeting a player can remove the NPC's plate and leave a stale alias or token behind.
	local dialog = ns:GetModule("Dialog")
	local show, hide = uv(dialog.GoBack, "Show"), uv(dialog.Apply, "Hide")
	hide()
	local bubble = uv(show, "bubble")
	local anchored
	local savedPoint, savedClear = bubble.SetPoint, bubble.ClearAllPoints
	bubble.SetPoint = function(_, _, to) anchored = to end
	bubble.ClearAllPoints = function() anchored = nil end
	local plateA, plateB, playerPlate = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
	local guid = { npc = "Creature-NPC", target = "Creature-NPC", nameplate1 = "Creature-NPC", nameplate3 = "Player-Self" }
	local plates = { npc = plateA, nameplate1 = plateA, nameplate3 = playerPlate }
	local saved = { C_NamePlate, UnitExists, UnitGUID, dialog.db.plates, dialog.db.hidePlate, dialog.db.enabled, dialog.db.style,
		dialog.db.fallback }
	local savedGet, savedSet = GetCVar, SetCVar
	local cvars = { nameplateShowAll = "0", nameplateShowFriendlyNpcs = "1" }
	GetCVar = function(cvar) return cvars[cvar] end
	SetCVar = function(cvar, value) cvars[cvar] = value end
	UnitExists = function(unit) return guid[unit] ~= nil end
	UnitGUID = function(unit) return guid[unit] end
	C_NamePlate = { GetNamePlates = function() return { plateA, playerPlate } end,
		GetNamePlateForUnit = function(unit)
			if guid[unit] == "Creature-NPC" and guid.target ~= guid[unit] and cvars.nameplateShowAll == "0" then
				return nil
			end
			return plates[unit]
		end }
	local savedGossip = GossipFrame
	GossipFrame = CreateFrame("Frame")
	local scale = 1
	GossipFrame.GetScale = function() return scale end
	GossipFrame.SetScale = function(_, value) scale = value end
	dialog.db.plates, dialog.db.hidePlate = true, false
	dialog.db.fallback = false
	dialog.db.enabled, dialog.db.style = true, "PLAYER"
	dialog:OnConversation("GOSSIP_SHOW")
	assert(anchored == plateA and bubble.Tail:IsShown(), "on the NPC's plate")
	assert(cvars.nameplateShowAll == "1" and scale == 0.001, "keeps all enabled plates available from opening")
	guid.target, plates.npc = "Player-Other", playerPlate
	dialog.WatchPlate()
	assert(anchored == plateA and bubble:IsShown(), "the NPC keeps its plate when a player is selected")
	dialog.OnPlateRemoved("nameplate1")
	assert(anchored == nil and dialog.anchorPlate == nil and not bubble:IsShown(), "off the plate that goes away")
	assert(scale == 0.001, "the native window stays collapsed during the brief wait")
	dialog.WatchPlate()
	assert(anchored == nil, "does not reattach while the removed token still reports the NPC")
	guid.nameplate1 = "Player-Other"
	dialog.OnPlateAdded("nameplate1")
	assert(anchored == nil, "does not attach to the selected player's recycled frame")
	guid.nameplate2, plates.nameplate2 = "Creature-NPC", plateB
	dialog.OnPlateAdded("nameplate2")
	assert(anchored == plateB, "back on the NPC")
	assert(bubble:IsShown() and bubble:GetAlpha() == 1 and bubble.Tail:IsShown(), "seen again on the plate")
	guid.nameplate2 = "Player-Other"
	dialog.WatchPlate()
	assert(anchored == nil and not bubble:IsShown(), "leaves a recycled plate even without a removal event")
	local savedTime = GetTime
	GetTime = function() return savedTime() + 1 end
	dialog.WatchPlate()
	GetTime = savedTime
	assert(not bubble:IsShown() and anchored == nil and GossipFrame:IsShown() and scale == 1
		and GossipFrame:GetAlpha() == 1, "the native dialog takes over after the wait")
	assert(cvars.nameplateShowAll == "0", "restores always-show setting after handoff")
	guid.npc = nil
	dialog:OnConversation("GOSSIP_SHOW")
	assert(anchored == nil and not bubble:IsShown(), "an already selected player cannot be captured as the speaker")
	guid.target, guid.nameplate2 = "Creature-NPC", "Creature-NPC"
	dialog.WatchPlate()
	assert(anchored == nil, "selecting an NPC later cannot change the speaker either")
	hide()
	bubble.SetPoint, bubble.ClearAllPoints = savedPoint, savedClear
	GossipFrame, GetCVar, SetCVar = savedGossip, savedGet, savedSet
	C_NamePlate, UnitExists, UnitGUID = unpack(saved, 1, 3)
	dialog.db.plates, dialog.db.hidePlate, dialog.db.enabled, dialog.db.style = unpack(saved, 4, 7)
	dialog.db.fallback = saved[8]
	print("dialog plate reuse OK")
end)()
;(function()
	-- Missing NPC nameplates must not prevent opening or retaining a quest reward.
	local dialog = ns:GetModule("Dialog")
	local hide = uv(dialog.Apply, "Hide")
	hide()
	local bubble = uv(uv(dialog.GoBack, "Show"), "bubble")
	local saved = { C_NamePlate, UnitExists, UnitGUID, GetTime, C_Timer.After, GetQuestID,
		dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic, dialog.db.style }
	local savedPoint, anchored = bubble.SetPoint
	bubble.SetPoint = function(_, _, target) anchored = target end
	local clock, plate, npc = 0, nil, CreateFrame("Frame")
	GetTime = function() return clock end
	C_Timer.After = function() end
	GetQuestID = function() return 78 end
	UnitExists = function(unit) return unit == "questnpc" or unit == "npc" or unit == "nameplate1" end
	UnitGUID = function() return "Creature-NPC" end
	C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return plate end }
	dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic = true, true, false
	dialog.db.style = "PLAYER"
	dialog:Apply()
	dialog:OnConversation("QUEST_COMPLETE")
	assert(not bubble:IsShown(), "briefly wait for the NPC nameplate")
	clock = 0.5
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == UIParent and not bubble.Tail:IsShown(),
		"the quest bubble opens at screen centre without an NPC nameplate")
	local choice = bubble.pools.item[2]
	choice:GetScript("OnClick")(choice)
	assert(choice.Chosen:IsShown(), "quest reward selection works without a nameplate")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(bubble:IsShown() and choice.Chosen:IsShown() and anchored == UIParent,
		"refreshing the same quest keeps the floating bubble and its selected reward")
	plate = npc
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == npc and bubble.Tail:IsShown() and choice.Chosen:IsShown(),
		"a returning NPC nameplate reattaches the same quest bubble")
	plate = nil
	dialog.WatchPlate()
	clock = 1.1
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == UIParent and choice.Chosen:IsShown(),
		"losing the nameplate preserves the bubble and reward choice")
	hide()
	bubble.SetPoint = savedPoint
	C_NamePlate, UnitExists, UnitGUID, GetTime, C_Timer.After, GetQuestID = unpack(saved, 1, 6)
	dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic = unpack(saved, 7, 9)
	dialog.db.style = saved[10]
	dialog:Apply()
	print("dialog quest without nameplate OK")
end)()
;(function()
	-- A plate frame given to another unit still names the old unit token in its field: only the game's answer counts.
	local dialog = ns:GetModule("Dialog")
	local find = uv(dialog.WatchPlate, "NpcNameplate")
	local saved = { UnitExists, UnitGUID, C_NamePlate, UnitIsUnit }
	local stale = { unitToken = "nameplate1", IsForbidden = function() return false end }
	local right = { IsForbidden = function() return false end }
	UnitExists = function(token) return token == "nameplate1" or token == "nameplate2" end
	UnitGUID = function(token) return token == "nameplate2" and "Creature-NPC" or "Creature-Other" end
	UnitIsUnit = function() return false end
	C_NamePlate = { GetNamePlates = function() return { stale, right } end,
		GetNamePlateForUnit = function(token) return token == "nameplate2" and right or token == "nameplate1" and stale or nil end }
	setuv(find, "npcGuid", "Creature-NPC")
	assert(find() == right, "the plate the game names for the NPC")
	UnitGUID = function() return "Creature-Other" end
	assert(find() == nil, "no plate of another unit")
	setuv(find, "npcGuid", nil)
	UnitExists, UnitGUID, C_NamePlate, UnitIsUnit = saved[1], saved[2], saved[3], saved[4]
	print("dialog plate of the npc OK")
end)()
;(function()
	-- Merchant: wares all hidden by the filter are said to be hidden; special prices show in the basket.
	local dialog = ns:GetModule("Dialog")
	local saved = { GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair,
		GetNumBuybackItems, GetMerchantItemCostInfo, GetMerchantItemCostItem, ns.MerchantTools, dialog.db.merchantHide }
	ns.MerchantTools = nil
	GetMerchantNumItems = function() return 2 end
	local usable = false
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = i == 2 and 30 or 0, stackCount = 1,
		numAvailable = -1, isPurchasable = true, isUsable = usable, hasExtendedCost = true } end }
	GetMerchantItemLink = function() return nil end
	GetMoney = function() return 150 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	GetMerchantItemCostInfo = function() return 1 end
	GetMerchantItemCostItem = function(index) return "Ticket", index * 5 end
	local function Blocks()
		local view = dialog.MerchantView()
		local rows, texts = nil, {}
		for _, block in ipairs(view.blocks) do
			rows = block.rows or rows
			texts[#texts + 1] = block.text or block.money
			texts[#texts + 1] = block.right
		end
		return rows, table.concat(texts, "\n"), view
	end
	dialog.db.merchantHide = true
	local rows, text = Blocks()
	assert(rows == nil and text:find(ns.L.DIALOG_MERCHANT_HIDDEN:format(2), 1, true), "all hidden: said so")
	assert(not text:find(ns.L.DIALOG_MERCHANT_NONE, 1, true), "not: nothing to offer")
	dialog.db.merchantHide = false
	usable = true
	rows = Blocks()
	assert(#rows == 2 and rows[1].reserve == nil, "no free column while nothing is in the basket")
	local picked = uv(dialog.MerchantView, "merchantPicked")
	local qty = uv(dialog.MerchantView, "merchantQty")
	picked[1], qty[1], picked[2], qty[2] = true, 2, true, 1
	local view
	rows, text, view = Blocks()
	assert(rows[1].reserve == 48, "room for the quantity field of a ware in the basket")
	picked[2], qty[2] = nil, nil
	rows = Blocks()
	assert(rows[2].reserve == 48, "every row leaves the room while the basket has wares: prices stay in one column")
	picked[2], qty[2] = true, 1
	assert(text:find("20 |TTicket:14:14|t 30c", 1, true), "special prices summed (2 x 5 + 1 x 10) and the money: " .. text)
	assert(view.buttons[2].enabled == true, "payable")
	GetMoney = function() return 20 end
	rows, text, view = Blocks()
	assert(view.buttons[2].enabled == false, "the money of a ware with a special price counts")
	picked[1], qty[1], picked[2], qty[2] = nil, nil, nil, nil
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair, GetNumBuybackItems,
		GetMerchantItemCostInfo, GetMerchantItemCostItem, ns.MerchantTools, dialog.db.merchantHide = unpack(saved, 1, 11)
	-- The glow of a chosen row keeps the icons of the text (same width, same line breaks) and drops the colours.
	assert(dialog.GlowText("|cff9a9a9a1.|r |cff1eff00Umhang|r 32 |TCoin:14:14|t |A:x:14:14|a") == "1. Umhang 32 |TCoin:14:14|t |A:x:14:14|a",
		"glow text")
	local talents = ns:GetModule("Talents")
	assert(talents.CounterText(9, false) == "" and talents.CounterText(0, true) == "", "no plan, no counter")
	assert(talents.CounterText(9, true):find("9/", 1, true), "a plan shows its points")
	print("merchant hidden and special prices OK")
end)()
;(function()
	-- Flight: the time of a route is remembered when the player is off the taxi, also when the game still
	-- reports "on taxi" at the moment control comes back.
	local flight = ns:GetModule("Flight")
	local saved = { UnitOnTaxi, GetTime, ns.After, uv(flight.Finish, "current"), flight.db.times }
	flight.db.times = {}
	local onTaxi, now, again = true, 100, nil
	UnitOnTaxi = function() return onTaxi end
	GetTime = function() return now end
	ns.After = function(_, _, fn) again = fn end
	setuv(flight.Finish, "current", { route = "A -> B", start = 40 })
	flight:PLAYER_CONTROL_GAINED()
	assert(again and next(flight.db.times) == nil and uv(flight.Finish, "current"), "still on the taxi: asked again")
	flight:PLAYER_CONTROL_GAINED()
	onTaxi, now = false, 101
	again()
	assert(flight.db.times["A -> B"] == 61 and uv(flight.Finish, "current") == nil, "remembered after landing")
	assert(flight.Record("A -> C", 3) == false and flight.db.times["A -> C"] == nil, "too short: no flight")
	assert(flight.Record(nil, 60) == false, "no route, no time")
	UnitOnTaxi, GetTime, ns.After = saved[1], saved[2], saved[3]
	setuv(flight.Finish, "current", saved[4])
	flight.db.times = saved[5]
	print("flight time OK")
end)()
;(function()
	-- Flight bar: a middle-click hides it for this flight only, the flight is still timed.
	local flight = ns:GetModule("Flight")
	local savedBar, savedCurrent = uv(flight.OnBarClick, "bar"), uv(flight.Finish, "current")
	local shown = true
	local fake = { Hide = function() shown = false end }
	setuv(flight.OnBarClick, "bar", fake)
	local flying = { route = "A -> B", start = 0 }
	setuv(flight.Finish, "current", flying)
	flight.OnBarClick("LeftButton")
	flight.OnBarClick("RightButton")
	assert(shown, "other buttons leave the bar alone")
	flight.OnBarClick("MiddleButton")
	assert(not shown and uv(flight.Finish, "current") == flying, "hidden, the flight goes on being timed")
	setuv(flight.OnBarClick, "bar", savedBar)
	setuv(flight.Finish, "current", savedCurrent)
	print("flight bar middle-click OK")
end)()
;(function()
	-- Group finder: the roles chosen in the options are set, only while the option is on
	local finder = ns:GetModule("GroupFinder")
	assert(finder.PresetRoles({ presetRoles = false, roleTank = true }) == nil, "off: nothing set")
	assert(finder.PresetRoles({ presetRoles = true }) == nil, "no role chosen: nothing set")
	local roles = finder.PresetRoles({ presetRoles = true, roleTank = true, roleDps = true })
	assert(roles.tank == true and roles.healer == false and roles.dps == true, "several roles")
	local savedRoles, savedDB, set, limit = C_LFGListRoles, { finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps }, nil, nil
	C_LFGListRoles = { SetRoles = function(given, classOnly) set, limit = given, classOnly end }
	finder.db.presetRoles = false
	finder.ApplyRoles()
	assert(set == nil, "the game's roles stay while the option is off")
	finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps = true, true, false
	finder.ApplyRoles()
	assert(set and set.healer == true and set.dps == false and set.leader == nil and limit == true, "set, limited to the roles of the class")
	-- the dungeon finder: the same roles and the leader flag
	local lfg
	local savedLFG = SetLFGRoles
	SetLFGRoles = function(...) lfg = { ... } end
	finder.db.roleLeader = true
	finder.ApplyRoles()
	assert(lfg and lfg[1] == true and lfg[2] == false and lfg[3] == true and lfg[4] == false, "dungeon finder with the leader flag")
	finder.db.roleLeader = false
	finder.ApplyRoles()
	assert(lfg[1] == false, "without the leader flag")
	SetLFGRoles = savedLFG
	C_LFGListRoles = savedRoles
	finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps = savedDB[1], savedDB[2], savedDB[3]
	print("group finder roles OK")
end)()
;(function()
	-- Waypoint from coordinates: what is read, what is linked in the chat, what is set
	local way = ns:GetModule("Waypoint")
	local x, y, name = way.Parse("23, 34")
	assert(x == 23 and y == 34 and name == nil, "comma")
	x, y, name = way.Parse(" 23.5 34.2 Schmied ")
	assert(x == 23.5 and y == 34.2 and name == "Schmied", "decimals, blank and a name")
	x, y = way.Parse("23,5 / 34,2")
	assert(x == 23.5 and y == 34.2, "comma as the decimal sign")
	assert(way.Parse("123 45") == nil and way.Parse("hallo") == nil and way.Parse("") == nil and way.Parse(nil) == nil, "not coordinates")
	local linked = way.Linkify("Komm zu 45.2, 61 bitte")
	assert(linked:find("|Haddon:ForeverPlus:way:45.2:61|h[45.2, 61]|h", 1, true), "link in the chat: " .. linked)
	assert(way.Linkify("Ich habe 1,5 Gold und 120, 300 Punkte") == "Ich habe 1,5 Gold und 120, 300 Punkte", "a decimal number and big numbers stay text")
	assert(way.Linkify("Stufe 250, 300") == "Stufe 250, 300", "numbers above 100 are no coordinates")
	local saved = { C_Map.GetBestMapForUnit, C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, UiMapPoint, C_SuperTrack, ns.Print }
	local savedHasWaypoint, savedGetWaypoint = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint
	local set, tracked, cleared, can = nil, nil, nil, true
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.CanSetUserWaypointOnMap = function() return can end
	C_Map.SetUserWaypoint = function(point) set = point end
	C_Map.ClearUserWaypoint = function() set, cleared = nil, true end
	C_Map.HasUserWaypoint = function() return set ~= nil end
	C_Map.GetUserWaypoint = function() return set end
	UiMapPoint = { CreateFromCoordinates = function(mapID, px, py) return { uiMapID = mapID, position = { x = px, y = py } } end }
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) tracked = on end }
	ns.Print = function() end
	way.Command("way 23 34 Schmied")
	assert(set and set.uiMapID == 1429 and set.position.x == 0.23 and set.position.y == 0.34 and tracked == true, "set on the player's map, tracked")
	assert(way.Target().name == "Schmied", "reading the game waypoint preserves the name")
	assert(way.SetOnMap(1436, 42, 71, "Quest") and set.uiMapID == 1436 and set.position.y == 0.71,
		"the journal pin goes on the quest giver's map, not the player's map")
	can = false
	assert(not way.SetOnMap(1436, 30, 40) and set.position.x == 0.42, "an unsupported destination leaves the existing pin alone")
	can = true
	set = nil
	way.Command("way quatsch")
	assert(set == nil, "no numbers: nothing set")
	can = false
	assert(way.Set(10, 20) == true and set == nil and way.Target().mapID == 1429 and way.Target().y == 0.2, "a map without the game's waypoints: only our own")
	way.Command("weg")
	assert(cleared and way.Target() == nil, "without numbers the waypoint goes")
	-- direction and distance: north is up, the game's facing turns to the west
	local function near(a, b) return math.abs(a - b) < 1e-6 end
	local distance, angle = way.Bearing(0.5, 0.5, 0.5, 0.4, 1000, 1000, 0)
	assert(near(distance, 100) and near(angle, 0), "100 yards to the north, straight ahead")
	distance, angle = way.Bearing(0.5, 0.5, 0.4, 0.5, 1000, 1000, 0)
	assert(near(angle, math.pi / 2), "to the west: turned to the left")
	distance, angle = way.Bearing(0.5, 0.5, 0.6, 0.5, 1000, 500, math.pi / 2)
	assert(near(distance, 100) and near(angle, -math.pi), "facing west, the target in the east: behind")
	distance = way.Bearing(0.5, 0.5, 0.5, 0.6, 1000, 500, 0)
	assert(near(distance, 50), "the height of the map counts for north and south")
	-- the game's waypoint (map, recipe radar) is followed; the player on another map gets no direction
	local mapPos = { 0.5, 0.5 }
	set = { uiMapID = 1411, position = { x = 0.3, y = 0.4 } }
	C_Map.GetPlayerMapPosition = function(mapID) return mapID == 1411 and mapPos and { GetXY = function() return mapPos[1], mapPos[2] end } or nil end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	GetPlayerFacing = function() return 0 end
	distance = way.Where()
	assert(way.Target().mapID == 1411 and way.Target().x == 0.3 and near(distance, math.sqrt(0.2 ^ 2 + 0.1 ^ 2) * 1000), "the game's waypoint")
	mapPos = nil
	local _, goal = way.Where()
	assert(way.Where() == nil and goal.mapID == 1411, "another map: no distance")
	way.Clear()
	assert(way.Target() == nil, "cleared")
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint = savedHasWaypoint, savedGetWaypoint
	C_Map.GetBestMapForUnit, C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, UiMapPoint, C_SuperTrack, ns.Print = unpack(saved, 1, 7)
	print("waypoint OK")
end)()
;(function()
	local way = ns:GetModule("Waypoint")
	local wind = ns:GetModule("GuidingWind")
	local savedWindEnabled = wind and wind.db and wind.db.enabled
	if wind and wind.db then wind.db.enabled = false end
	way.Preview(false)
	local arrow = _G.ForeverPlusWaypointArrow
	local savedAPI, savedGhost, savedFacing = rawget(_G, "C_DeathInfo"), rawget(_G, "UnitIsGhost"), GetPlayerFacing
	local savedMap, savedMapInfo, savedPosition = C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition
	local savedHasWaypoint, savedGetWaypoint, savedClear = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint
	local savedNameText, savedText, savedFormat = arrow.Name.SetText, arrow.Text.SetText, arrow.Text.SetFormattedText
	local ghost, corpse
	local point = { uiMapID = 1429, position = { x = 0.8, y = 0.5 } }
	local function Vector(x, y)
		return { GetXY = function() return x, y end }
	end
	UnitIsGhost = function() return ghost end
	GetPlayerFacing = function() return 0 end
	C_DeathInfo = { GetCorpseMapPosition = function(mapID) return mapID == 1415 and corpse or nil end }
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(mapID) return mapID == 1429 and { mapType = 3, parentMapID = 1415 } or nil end
	C_Map.GetPlayerMapPosition = function() return Vector(0.5, 0.5) end
	C_Map.HasUserWaypoint = function() return point ~= nil end
	C_Map.GetUserWaypoint = function() return point end
	C_Map.ClearUserWaypoint = function() point = nil end
	arrow.Name.SetText = function(self, value) self.value = value end
	arrow.Text.SetText = arrow.Name.SetText
	arrow.Text.SetFormattedText = function(self, format, ...) self:SetText(format:format(...)) end

	local listeners = uv(ns.RegisterEvent, "listeners")
	local function Fire(event)
		listeners[event][way](way, event)
	end
	local function Update()
		assert(arrow:IsShown(), "the navigation display is active")
		arrow:GetScript("OnUpdate")(arrow, 0.3)
	end
	assert(way.db.corpseArrow, "corpse guidance is on by default")
	ghost = true
	Fire("PLAYER_ALIVE")
	Update()
	assert(not arrow.Arrow:IsShown() and arrow.Text.value == ns.L.WAYPOINT_CORPSE_UNKNOWN, "missing corpse data stays pending")
	corpse = Vector(0.375, 0.5)
	Update()
	assert(arrow.Arrow:IsShown() and arrow.Name.value == ns.L.WAYPOINT_CORPSE_NAME
		and math.abs(arrow.Arrow.rotation - math.pi / 2) < 1e-6
		and arrow.Text.value == ns.L.WAYPOINT_DISTANCE:format(125), "the corpse on the shared map is west, 125 yards away")
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	corpse = Vector(0.5, 0.5)
	Update()
	assert(arrow:IsShown() and point, "arrival and middle-click keep the saved waypoint in corpse mode")

	ghost = false
	Fire("PLAYER_UNGHOST")
	Update()
	assert(arrow.Arrow:IsShown() and arrow.Name.value ~= ns.L.WAYPOINT_CORPSE_NAME and way.Target().x == 0.8,
		"resurrection restores the original waypoint")
	way.db.arrow = false
	ghost = true
	Fire("PLAYER_ENTERING_WORLD")
	Update()
	assert(arrow.Name.value == ns.L.WAYPOINT_CORPSE_NAME, "reloading while a ghost works with the regular waypoint arrow disabled")
	way.db.corpseArrow = false
	way:OnOptionChanged("corpseArrow")
	assert(not arrow:IsShown(), "the corpse arrow can be disabled independently")

	way.Clear()
	way.db.arrow, way.db.corpseArrow = true, true
	if wind and wind.db then wind.db.enabled = savedWindEnabled end
	C_DeathInfo, UnitIsGhost, GetPlayerFacing = savedAPI, savedGhost, savedFacing
	C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition = savedMap, savedMapInfo, savedPosition
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint = savedHasWaypoint, savedGetWaypoint, savedClear
	arrow.Name.SetText, arrow.Text.SetText, arrow.Text.SetFormattedText = savedNameText, savedText, savedFormat
	print("corpse arrow OK")
end)()
;(function()
	-- Level ranges of the zones: Forever's own, after the name of the zone under the mouse, coloured like the game's
	local worldMap = ns:GetModule("WorldMap")
	assert(ns.ZoneLevels[1412][1] == 1 and ns.ZoneLevels[1412][2] == 14, "Mulgore is a starter zone")
	assert(ns.ZoneLevels[1434][1] == 28 and ns.ZoneLevels[1434][2] == 50, "Stranglethorn covers the full questing range")
	assert(ns.ZoneLevels[1446] and ns.ZoneLevels[2482] and ns.ZoneLevels[2548] and ns.ZoneLevels[2652], "late-game and new questing zones")
	assert(not ns.ZoneLevels[1414] and not ns.ZoneLevels[1415] and not ns.ZoneLevels[1453], "no ranges for continents and capitals")
	for mapID, range in pairs(ns.ZoneLevels) do
		assert(type(mapID) == "number" and range[1] >= 1 and range[1] <= range[2] and range[2] <= 60, "a range per zone")
	end
	local saved = { GetQuestDifficultyColor, QuestDifficultyColors, C_Map.GetMapInfoAtPosition, C_Map.GetMapLevels, worldMap.db.zoneLevels }
	local savedMapInfo, savedProviders = C_Map.GetMapInfo, WorldMapFrame.dataProviders
	GetQuestDifficultyColor = function(level) return { r = level, g = 0, b = 0 } end
	QuestDifficultyColors = { difficult = { r = 1, g = 1, b = 0 } }
	local text, color = worldMap.LevelText(10, 20, 5)
	assert(text == "(10-20)" and color.r == 10, "below: the colour of the lowest level")
	text, color = worldMap.LevelText(10, 20, 15)
	assert(color.r == 1 and color.g == 1, "within: yellow")
	text, color = worldMap.LevelText(10, 20, 30)
	assert(color.r == 18, "above: the highest level less two")
	assert(worldMap.LevelText(7, 7, 1) == "(7)", "one level")
	local focus, mapID = true, 1415
	local map = {
		IsCanvasMouseFocus = function() return focus end,
		GetMapID = function() return mapID end,
		GetNormalizedCursorPosition = function() return 0.4, 0.6 end,
	}
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1429, name = "Wald von Elwynn" } end
	C_Map.GetMapLevels = function() return 0, 0, 0, 0 end
	worldMap.db.zoneLevels = true
	local range, name = worldMap.HoveredRange(map)
	assert(range == ns.ZoneLevels[1429] and name == "Wald von Elwynn", "the zone under the mouse")
	C_Map.GetMapLevels = function() return 5, 10 end
	assert(worldMap.HoveredRange(map) == nil, "the game shows a range itself: none of ours")
	C_Map.GetMapLevels = function() return 5, 0 end
	assert(worldMap.HoveredRange(map) == ns.ZoneLevels[1429], "a partial client range is not displayed by the game")
	C_Map.GetMapLevels = function() return 0, 0 end
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1415, name = "Östliche Königreiche" } end
	assert(worldMap.HoveredRange(map) == nil, "the map itself is no zone under the mouse")
	focus = false
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1429, name = "Wald von Elwynn" } end
	assert(worldMap.HoveredRange(map) == nil, "mouse not on the map")
	focus = true
	mapID = 2521
	C_Map.GetMapInfoAtPosition = function() return nil end
	C_Map.GetMapInfo = function(id) return { mapID = id, name = "Zephras Isle" } end
	local label = NewFrame("Frame")
	local labelName = ""
	label.Name.GetText = function() return labelName end
	label.labelInfoByType, label.fpLevels = {}, false
	label.dataProvider = { GetMap = function() return map end }
	WorldMapFrame.dataProviders = { [label.dataProvider] = true }
	label.dataProvider.Label = label
	assert(worldMap.HookAreaLabel() == label, "the world map provider is hooked")
	local levels = label.fpLevels
	levels.SetText = function(self, value) self.text = value end
	local update = label:GetScript("OnUpdate")
	update(label)
	assert(levels:IsShown() and levels.text == "Zephras Isle (1-12)", "the opened zone has a label on empty map space")
	labelName = "Valanaar"
	update(label)
	assert(not levels:IsShown(), "an area's own label does not get the whole zone's range")
	labelName = "Zephras Isle"
	update(label)
	assert(levels:IsShown() and levels.text == "(1-12)", "add just the range when the game displays the zone name")
	worldMap.db.zoneLevels = false
	update(label)
	assert(not levels:IsShown(), "option off")
	C_Map.GetMapInfo, WorldMapFrame.dataProviders = savedMapInfo, savedProviders
	GetQuestDifficultyColor, QuestDifficultyColors, C_Map.GetMapInfoAtPosition, C_Map.GetMapLevels, worldMap.db.zoneLevels = unpack(saved, 1, 5)
	print("zone levels OK")
end)()
;(function()
	-- Moments: one picture per boss (two events), a picture and a sound at a level-up, each only with its option
	local moments = ns:GetModule("Moments")
	assert(moments.ShotDue(1000) == true and moments.ShotDue(1002) == false and moments.ShotDue(1010) == true, "one picture per boss")
	local saved = { Screenshot, PlaySound, ns.After, GetTime, moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound }
	local shots, sounds, now = 0, 0, 2000
	Screenshot = function() shots = shots + 1 end
	-- Other modules listen to a level-up too: only this module's sound is counted.
	local savedLevelSound = moments.PlayLevelSound
	local kit
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = "fanfare"
	PlaySound = function(given) if given == "fanfare" then kit = given end end
	moments.PlayLevelSound = function() sounds = sounds + 1 savedLevelSound() end
	ns.After = function(_, _, fn) fn() end
	GetTime = function() return now end
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = false, false, false
	moments:Apply()
	Fire("PLAYER_LEVEL_UP", 20)
	Fire("BOSS_KILL", 1, "Boss")
	assert(shots == 0 and sounds == 0, "all off: nothing")
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = true, true, true
	moments:Apply()
	Fire("ENCOUNTER_END", 1, "Boss", 1, 5, 0)
	assert(shots == 0, "a wipe is no picture")
	Fire("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
	Fire("BOSS_KILL", 1, "Boss")
	assert(shots == 1, "boss dead: one picture for both events")
	now = 2100
	Fire("PLAYER_LEVEL_UP", 21)
	assert(shots == 2 and sounds == 1, "level-up: picture and fanfare (" .. shots .. ", " .. sounds .. ")")
	assert(kit == "fanfare" and moments.db.levelSoundKit == "UI_RAID_BOSS_DEFEATED", "the chosen sound of the game")
	assert(moments.SoundKey("UI_EPICLOOT_TOAST") == "UI_RAID_BOSS_DEFEATED" and moments.SoundKey("UI_SCENARIO_ENDING") == "UI_SCENARIO_ENDING", "a removed short sound falls back to the first")
	-- Without the interface: UIParent see-through for the picture, the level-up toast and the boss banner stay,
	-- everything back afterwards (by the timer here, by the screenshot event in the game).
	local savedFrames = { UIParent, EventToastManagerFrame, BossBanner, moments.db.shotHideUI }
	local function Fake(alpha, ignore)
		return { alpha = alpha, ignore = ignore,
			GetAlpha = function(self) return self.alpha end, SetAlpha = function(self, a) self.alpha = a end,
			IsIgnoringParentAlpha = function(self) return self.ignore end,
			SetIgnoreParentAlpha = function(self, i) self.ignore = i end }
	end
	UIParent, EventToastManagerFrame, BossBanner = Fake(0.9), Fake(1, false), Fake(1, true)
	local seen
	Screenshot = function()
		seen = { UIParent.alpha, EventToastManagerFrame.ignore, BossBanner.ignore }
	end
	moments.db.shotHideUI = true
	moments:Apply()
	now = 2200
	Fire("PLAYER_LEVEL_UP", 22)
	assert(seen and seen[1] == 0 and seen[2] == true and seen[3] == true, "picture: interface hidden, messages kept")
	assert(UIParent.alpha == 0.9 and EventToastManagerFrame.ignore == false and BossBanner.ignore == true, "interface back as before")
	moments.HideUI()
	Fire("SCREENSHOT_SUCCEEDED")
	assert(UIParent.alpha == 0.9 and EventToastManagerFrame.ignore == false, "back at the screenshot event")
	BossBanner = nil
	moments.HideUI()
	assert(UIParent.alpha == 0 and EventToastManagerFrame.ignore == true, "a missing banner is no error")
	moments.ShowUI()
	moments.db.shotHideUI = false
	seen = nil
	now = 2300
	Fire("PLAYER_LEVEL_UP", 23)
	assert(seen and seen[1] == 0.9 and seen[2] == false, "option off: picture with the interface")
	UIParent, EventToastManagerFrame, BossBanner, moments.db.shotHideUI = savedFrames[1], savedFrames[2], savedFrames[3], savedFrames[4]
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = nil
	moments.PlayLevelSound = savedLevelSound
	Screenshot, PlaySound, ns.After, GetTime = saved[1], saved[2], saved[3], saved[4]
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = saved[5], saved[6], saved[7]
	moments:Apply()
	print("moments OK")
end)()

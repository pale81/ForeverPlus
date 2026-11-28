(function()
	-- Talent planner in Blizzard's window: right-click plans, Shift + right-click removes, classic rules.
	local talents = ns:GetModule("Talents")
	talents.db.enabled, talents.db.planner = true, true
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	assert(onClick, "planner click handler")
	GameTooltip = { GetOwner = function() return nil end }
	do
	local plannerButtons = {}
	PlayerSpellsFrame = { TalentsFrame = { GetConfigID = function() return 1 end, EnumerateAllTalentButtons = function() return pairs(plannerButtons) end } }
	PlayerUtil = { GetCurrentSpecID = function() return 1 end }
	C_Traits = { GetNodeInfo = function() return { maxRanks = 3, ranksPurchased = 0 } end }
	IsShiftKeyDown = function() return false end
	IsControlKeyDown = function() return false end
	local btn = { GetNodeID = function() return 77 end, CanRefundRank = function() return false end }
	plannerButtons[btn] = true
	onClick(nil, btn, "RightButton"); onClick(nil, btn, "RightButton")
	local plan = uv(onClick, "CurrentPlan")()
	assert(plan[77] == 2, "planned 2 ranks")
	IsShiftKeyDown = function() return true end
	onClick(nil, btn, "RightButton")
	assert(plan[77] == 1, "shift removes")
	-- Tooltip shows the planned rank
	plan[77] = 3
	local lines = {}
	GameTooltip = { GetOwner = function() return btn end, Show = function() end }
	GameTooltip_AddBlankLineToTooltip = function() end
	GameTooltip_AddHighlightLine = function(_, text) lines[#lines + 1] = text end
	C_Traits.GetTraitDescription = function(entryID, rank) return "GetTraitEntry:" .. entryID .. ":" .. rank end
	GameTooltip_AddColoredLine = function(_, text) lines[#lines + 1] = text end
	C_Traits.GetNodeInfo = function() return { maxRanks = 3, ranksPurchased = 1, activeEntry = { entryID = 500, rank = 1 } } end
	uv(uv(uv(onClick, "RefreshTooltip"), "HookPlanTooltip"), "AddPlanTooltip")(btn)
	print("  plan tooltip", table.concat(lines, " | "))
	assert(lines[#lines] == "GetTraitEntry:500:3", "planned rank values")
	-- Row rule and arrows: node 2 in row 2 needs 5 points, node 3 needs node 1 at full rank
	local plan2 = uv(onClick, "CurrentPlan")()
	for k in pairs(plan2) do plan2[k] = nil end
	local defs = {
		[1] = { ID = 1, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = { { targetNode = 3, type = Enum.TraitEdgeType.RequiredForAvailability } } },
		[2] = { ID = 2, posY = 200, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {} },
		[3] = { ID = 3, posY = 100, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {} },
	}
	C_Traits.GetNodeInfo = function(_, id) local d = defs[id] local c = {} for k, v in pairs(d) do c[k] = v end return c end
	for k in pairs(plannerButtons) do plannerButtons[k] = nil end
	local bs = {}
	for id = 1, 3 do bs[id] = { GetNodeID = function() return id end, CanRefundRank = function() return false end, GetName = function() return "T" .. id end } plannerButtons[bs[id]] = true end
	IsShiftKeyDown = function() return false end
	local printed
	local oldPrint = ns.Print
	ns.Print = function(msg) printed = msg end
	talents:QueuePlanUpdate() -- another tree: in the game its events ask for a new reading
	onClick(nil, bs[3], "RightButton")
	assert(not plan2[3], "row 1 needs 5 points")
	-- the restriction shows in the tooltip of that talent, in the colour of the plan
	lines = {}
	GameTooltip = { GetOwner = function() return bs[3] end, Show = function() end }
	uv(uv(uv(onClick, "RefreshTooltip"), "HookPlanTooltip"), "AddPlanTooltip")(bs[3])
	print("  restriction tooltip", table.concat(lines, " | "))
	assert(#lines >= 1 and lines[#lines]:find("Plan:") and lines[#lines]:find("5"), "restriction in the tooltip")
	for _ = 1, 4 do onClick(nil, bs[1], "RightButton") end
	onClick(nil, bs[3], "RightButton")
	assert(not plan2[3], "needs node 1 at full rank / 5 points")
	onClick(nil, bs[1], "RightButton")
	onClick(nil, bs[3], "RightButton")
	assert(plan2[3] == 1, "row 1 unlocked with 5 points and arrow source maxed")
	IsShiftKeyDown = function() return true end
	onClick(nil, bs[1], "RightButton")
	assert(plan2[1] == 5, "removal blocked while node 3 depends on it")
	ns.Print = oldPrint
	print("  planner rules ok, last message:", printed)
	print("planner OK")
	end
end)()
;(function()
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local buildList, active = uv(menu, "BuildList"), uv(menu, "ActiveBuild")
	local key = uv(buildList, "PlanKey")()
	local class = key:match("^[^:]+")
	local list, original = buildList(), active()
	local savedCount, savedSeq, savedActive = #list, talents.db.buildSeq, talents.cdb.activeBuild[key]
	local savedNext = talents.db.planNext
	local savedFrame, savedTraits, savedSpell, savedLocale, savedStat = PlayerSpellsFrame, C_Traits, C_Spell, GetLocale, UnitStat
	local savedWeights, savedPresets, savedPrint, savedMenu = ns.StatWeights, ns.TalentPresets, ns.Print, MenuUtil.CreateContextMenu
	talents.db.planNext = false
	local buttons, defs = {}, {}
	local function Add(id, tree, row, column, maxRanks, learned)
		defs[id] = { ID = id, posX = tree * 1000 + column * 50, posY = row * 100, maxRanks = maxRanks,
			ranksPurchased = learned or 0, entryIDs = { id }, groupIDs = { tree } }
		local button = CreateFrame("Button")
		button.GetNodeID = function() return id end
		button.GetName = function() return "Talent " .. id end
		buttons[button] = true
	end
	local preset = {}
	for row = 0, 5 do
		Add(11 + row, 2, row, row % 3, 5)
		preset[#preset + 1] = (11 + row) .. ":5"
	end
	for row = 0, 3 do
		Add(1 + row, 1, row, row % 3, 5)
		preset[#preset + 1] = (1 + row) .. ":5"
	end
	Add(17, 2, 6, 0, 1)
	preset[#preset + 1] = "17:1"
	defs[11].visibleEdges = { { targetNode = 17, type = Enum.TraitEdgeType.RequiredForAvailability } }
	Add(18, 2, 0, 1, 5)
	Add(19, 2, 1, 2, 5)
	Add(31, 3, 0, 0, 2, 2)
	Add(32, 3, 0, 0, 5)
	defs[32].isVisible, defs[32].posX, defs[32].posY = false, 102800, -100
	defs[17].posX = 9000
	ns.TalentPresets = { [class] = {
		{ de = "Andere", en = "Other", points = "", ranks = "" },
		{ de = "Schutz", en = "Protection", points = "20/31/0", ranks = table.concat(preset, ",") },
		{ de = "Dritter Baum", en = "Third tree", points = "", ranks = "" },
		{ de = "Bär", en = "Bear", points = "20/31/0", ranks = table.concat(preset, ","):gsub("12:5", "19:5") },
	} }
	PlayerSpellsFrame = { TalentsFrame = {
		GetConfigID = function() return 1 end, IsVisible = function() return true end,
		EnumerateAllTalentButtons = function() return pairs(buttons) end,
	} }
	C_Traits = {
		GetConfigInfo = function() return { treeIDs = { 1117 } } end,
		GetGroupDisplayInfoByTreeID = function()
			return { { groupID = 3, orderIndex = 3 }, { groupID = 1, orderIndex = 1 }, { groupID = 2, orderIndex = 2 } }
		end,
		GetNodeInfo = function(_, id) return CopyTable(defs[id]) end,
		GetEntryInfo = function(_, id) return { definitionID = id } end,
		GetDefinitionInfo = function(id) return { spellID = id } end,
		GetTraitDescription = function(id, rank)
			if id == 11 or id == 12 then return ("Increases your Defense Skill by %d."):format(rank * 4) end
			if id == 18 or id == 19 then return ("Increases your chance to dodge by %d%%."):format(rank) end
			return "Grants a new ability."
		end,
	}
	C_Spell = { IsSpellPassive = function(id) return id ~= 17 end }
	GetLocale = function() return "enUS" end
	UnitStat = function() return 50, 50 end
	local weights = { DODGE = 12, DEF = 1.5 }
	ns.StatWeights = function() return weights, "Protection", 2 end
	ns.Print = function() end
	MenuUtil.CreateContextMenu = function(owner, generate)
		generate(owner, {
			CreateTitle = function() end, CreateRadio = function() end, CreateDivider = function() end,
			CreateButton = function(_, title, action) if title == ns.L.TALENTS_RECOMMEND then action() end end,
		})
	end
	talents:QueuePlanUpdate()
	menu({})
	local build = active()
	assert(build ~= original and ns.TalentBuilds.Points(build) == 51 and #build.order == 49 and build.ranks[31] == 2,
		"create a full plan with earned points included, leaving the original plan intact")
	assert(build.ranks[17] == 1 and build.ranks[11] == 5 and not build.ranks[18],
		"keep the unscored capstone and its required talent")
	assert(build.ranks[19] == 5 and not build.ranks[12], "prefer the higher-scoring eligible alternative in the same row")
	local replay = { [31] = 2 }
	for _, id in ipairs(build.order) do
		local node, above = defs[id], 0
		for previous, rank in pairs(replay) do
			if defs[previous].groupIDs[1] == node.groupIDs[1] and defs[previous].posY < node.posY then
				above = above + rank
			end
		end
		assert(above >= node.posY / 100 * 5 and (id ~= 17 or replay[11] == 5), "every step can be learned in order")
		replay[id] = (replay[id] or 0) + 1
		assert(replay[id] <= node.maxRanks, "respect the talent rank cap")
	end
	weights = { DEF = 1.5 }
	menu({})
	assert(active().ranks[12] == 5 and not active().ranks[19] and build.ranks[19] == 5,
		"changing the gear weights changes the recommended allocation")
	defs[31].ranksPurchased = 0
	weights = { DODGE = 12, DEF = 1.5 }
	talents:QueuePlanUpdate()
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 51 and active().ranks[17] == 1
		and active().ranks[12] == 5 and not active().ranks[19] and not active().ranks[32],
		"keep the complete tested allocation when learned ranks fit it, regardless of alternative gear gains")
	defs[31].ranksPurchased = 2
	talents:QueuePlanUpdate()
	C_Traits.GetTraitDescription = function() return "Grants a new ability." end
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 49 and active().ranks[17] == 1,
		"complete the plan from the template when no effects are directly scoreable")
	ns.StatWeights = function() return weights, "Bear", 2, 4 end
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 49 and active().ranks[19] == 5
		and not active().ranks[12], "use the selected bear template for the same talent tree")
	for index = #list, savedCount + 1, -1 do list[index] = nil end
	talents.db.buildSeq, talents.cdb.activeBuild[key], talents.db.planNext = savedSeq, savedActive, savedNext
	PlayerSpellsFrame, C_Traits, C_Spell, GetLocale, UnitStat = savedFrame, savedTraits, savedSpell, savedLocale, savedStat
	ns.StatWeights, ns.TalentPresets, ns.Print, MenuUtil.CreateContextMenu = savedWeights, savedPresets, savedPrint, savedMenu
	talents:QueuePlanUpdate()
	print("talent recommendations OK")
end)()
;(function()
	-- Order of the talent plan: steps per point, kept in line with the plan and the rules.
	local order = ns.TalentOrder
	local kept, missing = order.Reconcile({ 1, 1, 2, 1, 3 }, { [1] = 2, [2] = 1, [4] = 2 })
	assert(table.concat(kept, ",") == "1,2,1" and missing[4] == 2 and missing[1] == nil and missing[2] == nil,
		"learned points drop the earliest steps, a talent no longer planned drops all: " .. table.concat(kept, ","))
	local steps = { 1, 2, 1, 3 }
	assert(order.RemoveLast(steps, 1) and table.concat(steps, ",") == "1,2,3" and not order.RemoveLast(steps, 9), "the last step of a talent goes")
	-- talent 3 needs two points in the others first
	local ranks = { [1] = 1 }
	local repaired = order.Repair({ 3, 2, 1, 3 }, function(id, state)
		return id ~= 3 or (state[1] or 0) + (state[2] or 0) >= 2
	end, ranks)
	assert(table.concat(repaired, ",") == "2,3,1,3" and ranks[3] == 2, "first step the rules allow: " .. table.concat(repaired, ","))
	repaired = order.Repair({ 3, 1 }, function(id) return id == 1 end, {})
	assert(table.concat(repaired, ",") == "1,3", "a step nothing unlocks stays at the end")
	local texts = order.LevelTexts({ 1, 1, 1, 2, 1, 3 }, 14)
	assert(texts[1] == "14–16, 18" and texts[2] == "17" and texts[3] == "19" and texts[4] == nil, "levels of the steps: " .. tostring(texts[1]))

	-- In the planner: clicks keep their order, taking a rank back repairs it, "apply" buys in that order.
	local talents = ns:GetModule("Talents")
	talents.db.enabled, talents.db.planner, talents.db.planNext = true, true, true
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	local savedTraits, savedCT, savedSpec, savedSpell = C_Traits, C_ClassTalents, C_SpecializationInfo, C_Spell
	local defs = {
		[1] = { ID = 1, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 501 } },
		[2] = { ID = 2, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 502 } },
		[3] = { ID = 3, posY = 100, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 503 } },
		[4] = { ID = 4, posY = 200, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 504 } },
	}
	local bought, points = {}, 99
	C_Traits = {
		GetNodeInfo = function(_, id) local c = {} for k, v in pairs(defs[id]) do c[k] = v end return c end,
		PurchaseRank = function(_, id)
			if #bought >= points then return false end
			bought[#bought + 1] = id
			return true
		end,
		GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1000 } end,
		GetDefinitionInfo = function(definitionID) return { spellID = definitionID + 1000 } end,
		GetConfigInfo = function() return nil end,
	}
	C_Spell = { GetSpellName = function(spellID) return "Zauber " .. spellID end }
	C_ClassTalents = { GetActiveConfigID = function() return 1 end }
	C_SpecializationInfo = { HasPlayerEarnedATalentPoint = function() return true end }
	InCombatLockdown = function() return false end
	PlayerUtil = { GetCurrentSpecID = function() return 1 end }
	IsControlKeyDown = function() return false end
	local buttons, bs = {}, {}
	for id = 1, 4 do
		bs[id] = { GetNodeID = function() return id end, CanRefundRank = function() return false end, GetName = function() return "T" .. id end }
		buttons[bs[id]] = true
	end
	PlayerSpellsFrame = { TalentsFrame = { GetConfigID = function() return 1 end, EnumerateAllTalentButtons = function() return pairs(buttons) end } }
	GameTooltip = { GetOwner = function() return nil end }
	local plan, stored = uv(onClick, "CurrentPlan")(), uv(onClick, "CurrentOrder")()
	wipe(plan); wipe(stored)
	talents:QueuePlanUpdate()
	local oldPrint = ns.Print
	ns.Print = function() end
	local function Applied()
		bought = {}
		talents:ApplyPlan()
		return table.concat(bought, ",")
	end
	IsShiftKeyDown = function() return false end
	for _ = 1, 5 do onClick(nil, bs[1], "RightButton") end
	onClick(nil, bs[3], "RightButton")
	for _ = 1, 5 do onClick(nil, bs[2], "RightButton") end
	assert(Applied() == "1,1,1,1,1,3,2,2,2,2,2", "the order of the clicks: " .. Applied())
	assert(talents.NextPlanned() == "Zauber 2501", "the next talent of the plan by name: " .. tostring(talents.NextPlanned()))
	-- one rank of the first talent taken back: the talent of the second row has to wait for a fifth point
	IsShiftKeyDown = function() return true end
	onClick(nil, bs[1], "RightButton")
	assert(plan[1] == 4 and Applied() == "1,1,1,1,2,3,2,2,2,2", "repaired after taking a rank back: " .. Applied())
	points = 3
	assert(Applied() == "1,1,1", "as far as the points go")
	points = 99
	-- a plan without steps (template, import, older plan): row by row; learned ranks need no step
	wipe(plan); wipe(stored)
	plan[4], plan[3], plan[2], plan[1] = 1, 1, 5, 5
	defs[1].ranksPurchased = 2
	talents:QueuePlanUpdate()
	assert(Applied() == "1,1,1,2,2,2,2,2,3,4", "derived order: " .. Applied())
	assert(talents.NextPlanned() == "Zauber 2501", "next: the first talent still short of its planned rank")
	defs[1].ranksPurchased = 5
	assert(talents.NextPlanned() == "Zauber 2502", "learned steps are passed over")
	talents.db.planNext = false
	assert(talents.NextPlanned() == nil, "option off: no hint")
	talents.db.planNext = true
	wipe(plan); wipe(stored)
	ns.Print = oldPrint
	C_Traits, C_ClassTalents, C_SpecializationInfo, C_Spell = savedTraits, savedCT, savedSpec, savedSpell
	print("talent plan order OK")
end)()
;(function()
	-- Talent plans by name: the list, what was stored before, and the plan a character works with.
	local builds = ns.TalentBuilds
	local ranks = builds.ParseRanks("11:5,12:2,x,13:0")
	assert(ranks[11] == 5 and ranks[12] == 2 and ranks[13] == 0 and builds.ParseRanks(nil)[1] == nil, "ranks of a stored template")
	local list, counter = {}, {}
	local first = builds.Add(list, counter, "Plan")
	local second = builds.Add(list, counter, "Plan", { [1] = 3, [2] = 1 })
	assert(first.id == 1 and second.id == 2 and second.name == "Plan (2)" and builds.Points(second) == 4 and builds.Points(first) == 0, "ids and names of their own")
	assert(builds.UniqueName(list, "Plan (2)", second) == "Plan (2)" and builds.UniqueName(list, "Plan") == "Plan (3)", "a plan keeps its own name")
	assert(builds.Find(list, 2) == second and builds.Find(list, 9) == nil and builds.Find(list, nil) == nil, "found by id")
	assert(builds.Remove(list, 1) and #list == 1 and not builds.Remove(list, 1) and builds.Add(list, counter, "X").id == 3, "removed; ids are not used again")
	list, counter = {}, { buildSeq = 4 }
	builds.Migrate(list, counter, { [7] = 2 }, { 7, 7 }, { { name = "Tank", points = 3, ranks = "7:1,8:2" }, { name = "leer", ranks = "" }, "kaputt" }, "Plan")
	assert(#list == 2 and list[1].name == "Plan" and list[1].ranks[7] == 2 and #list[1].order == 2 and list[1].id == 5
		and list[2].name == "Tank" and list[2].ranks[8] == 2 and #list[2].order == 0, "the old plan first, then the templates with talents")
	assert(#builds.Migrate({}, {}, {}, nil, nil, "Plan") == 0, "nothing stored: nothing added")

	local talents = ns:GetModule("Talents")
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local BuildList, ActiveBuild = uv(menu, "BuildList"), uv(menu, "ActiveBuild")
	local key = uv(BuildList, "PlanKey")()
	local savedDB, savedSeq, savedActive = talents.db.builds[key], talents.db.buildSeq, talents.cdb.activeBuild[key]
	local savedPrint, savedEdit, savedMenu, savedLocale = ns.Print, ns.ShowEditWindow, MenuUtil.CreateContextMenu, GetLocale
	ns.Print = function() end
	-- what an older version stored is taken over once, the old plan is the active one
	talents.db.builds[key], talents.cdb.activeBuild[key] = nil, nil
	talents.db.plans, talents.db.planOrder = { [key] = { [7] = 2 } }, { [key] = { 7, 7 } }
	talents.db.templates = { [key:match("^[^:]+")] = { { name = "Tank", ranks = "7:1,8:2" } } }
	assert(#BuildList() == 2 and next(talents.db.plans) == nil and next(talents.db.planOrder) == nil and next(talents.db.templates) == nil, "taken over, the old fields emptied")
	assert(#BuildList() == 2 and talents:CurrentPlan()[7] == 2 and ActiveBuild().name == ns.L.TALENTS_PLAN, "once only; the old plan is active")
	talents.db.plans, talents.db.planOrder, talents.db.templates = nil, nil, nil
	-- menu: the plans as a choice, then what can be done
	local radios, entries = {}, {}
	MenuUtil.CreateContextMenu = function(owner, gen)
		local root = {}
		function root.CreateTitle() end
		function root.CreateDivider() end
		function root.CreateRadio(_, text, isSelected, onSelect) radios[#radios + 1] = { text = text, isSelected = isSelected, onSelect = onSelect } end
		function root.CreateButton(_, text, fn) entries[text] = fn end
		gen(owner, root)
	end
	talents.db.planner = true
	menu({})
	assert(#radios == 2 and radios[1].text == ns.L.TALENTS_PLAN .. " (2)" and radios[2].text == "Tank (3)" and radios[1].isSelected() and not radios[2].isSelected(), "plans with their points, the active one marked")
	radios[2].onSelect()
	assert(ActiveBuild().name == "Tank" and talents:CurrentPlan()[8] == 2 and radios[2].isSelected(), "another plan chosen")
	-- new, rename, save a copy, remove
	local typed
	ns.ShowEditWindow = function(_, _, _, _, onAccept) onAccept(typed) end
	typed = "  Tank "
	entries[ns.L.TALENTS_PLAN_NEW]()
	assert(#BuildList() == 3 and ActiveBuild().name == "Tank (2)" and next(talents:CurrentPlan()) == nil, "a new, empty plan is the active one")
	typed = "Heiler"
	entries[ns.L.TALENTS_PLAN_RENAME]()
	assert(ActiveBuild().name == "Heiler", "renamed")
	typed = ""
	entries[ns.L.TALENTS_PLAN_RENAME]()
	assert(ActiveBuild().name == "Heiler", "no name: the plan keeps its own")
	-- a plan from outside takes the empty active plan, otherwise it becomes a plan of its own
	local StorePlan = uv(uv(menu, "ImportPlan"), "StorePlan")
	StorePlan("Link", { [7] = 1 })
	assert(#BuildList() == 3 and ActiveBuild().name == "Link" and talents:CurrentPlan()[7] == 1, "the empty plan is used")
	StorePlan("Link", { [8] = 1 })
	assert(#BuildList() == 4 and ActiveBuild().name == "Link (2)" and talents:CurrentPlan()[8] == 1 and BuildList()[3].ranks[7] == 1, "beside a plan with talents")
	entries[ns.L.TALENTS_PLAN_REMOVE]()
	assert(#BuildList() == 3 and ActiveBuild().name == ns.L.TALENTS_PLAN, "removed: the first plan is active")
	for _ = 1, 3 do entries[ns.L.TALENTS_PLAN_REMOVE]() end
	assert(#BuildList() == 0 and next(talents:CurrentPlan()) == nil and #BuildList() == 1, "without any plan there is an empty one as soon as it is asked for")
	-- planner off: the menu still exports
	radios, entries = {}, {}
	talents.db.planner = false
	menu({})
	assert(#radios == 0 and entries[ns.L.TALENTS_EXPORT_PLAN] and not entries[ns.L.TALENTS_PLAN_NEW], "planner off: export only")
	talents.db.planner = true
	assert(onClick, "planner reachable")
	talents.db.builds[key], talents.db.buildSeq, talents.cdb.activeBuild[key] = savedDB, savedSeq, savedActive
	ns.Print, ns.ShowEditWindow, MenuUtil.CreateContextMenu, GetLocale = savedPrint, savedEdit, savedMenu, savedLocale
	print("talent plans by name OK")
end)()
;(function()
	-- Time in the finished level: the difference of the level starts (total played time minus time in the level).
	local info = ns:GetModule("Info")
	info.db.levelTime = true
	UnitLevel = function() return 11 end
	SecondsToTime = function(seconds) return tostring(seconds) .. "s" end
	local handler = info.TIME_PLAYED_MSG
	local known = uv(handler, "LevelTimeKnown")
	assert(known, "level time reachable")
	-- level 10 began at 600 s (total 1000, 400 in the level)
	UnitLevel = function() return 10 end
	handler(info, "TIME_PLAYED_MSG", 1000, 400)
	-- level-up to 11: the request arrives with total 2600 and 5 s in the new level
	local index
	for i = 1, 60 do local name = debug.getupvalue(handler, i) if name == "levelPending" then index = i end end
	assert(index, "levelPending upvalue")
	debug.setupvalue(handler, index, { level = 11, at = GetTime() })
	UnitLevel = function() return 11 end
	handler(info, "TIME_PLAYED_MSG", 2600, 5)
	local text = uv(known, "levelText")
	assert(text and text:find("10") and text:find("1995"), "time of level 10: " .. tostring(text))
	print("level time OK")
end)()
;(function()
	-- Trainer in the bubble: affordable services are selectable rows, the rest follows dimmed.
	local dialog = ns:GetModule("Dialog")
	GetNumTrainerServices = function() return 3 end
	GetTrainerServiceInfo = function(i)
		local data = { { "Erste Hilfe", "available", 1, 1, "Lehrling" }, { "Zweiter", "unavailable", 2, 20, "" }, { "Alt", "used", 3, 1, "" } }
		return unpack(data[i])
	end
	GetTrainerServiceCost = function(i) return i == 1 and 100 or 500 end
	GetMoney = function() return 1000 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	UnitLevel = function() return 10 end
	-- recipes: the product of the first is better equipment (arrow), the second only at a higher level (grey arrow)
	local savedLink, savedState = GetTrainerServiceItemLink, ns.RecipeUpgradeState
	GetTrainerServiceItemLink = function(i) return i <= 2 and ("item:" .. (100 + i)) or nil end
	ns.RecipeUpgradeState = function(link) return link == "item:101" or (link == "item:102" and "later") end
	dialog.showLocked = true
	local preview = dialog.TrainerView()
	local previewRows
	for _, block in ipairs(preview.blocks) do if block.rows then previewRows = block.rows end end
	assert(previewRows[1].link == "item:101" and previewRows[1].upgrade == true and previewRows[1].arrowSlot, "recipe row: link and arrow")
	assert(previewRows[2].upgrade == "later", "only the level missing: grey arrow")
	ns:GetModule("ProfessionPlan").db.preview = false
	preview = dialog.TrainerView()
	for _, block in ipairs(preview.blocks) do if block.rows then previewRows = block.rows end end
	assert(not previewRows[1].upgrade, "preview switched off: no arrow")
	ns:GetModule("ProfessionPlan").db.preview = true
	dialog.showLocked = false
	GetTrainerServiceItemLink, ns.RecipeUpgradeState = function() return nil end, savedState
	local view = dialog.TrainerView()
	local rows
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows and #rows == 1 and rows[1].action, "only what can be learned by default")
	assert(view.tools and view.tools.locked == false, "the symbol for later levels is off")
	dialog.showLocked = true
	view = dialog.TrainerView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows and #rows == 2 and rows[1].action and not rows[2].action and rows[2].dim, "available first, locked dimmed, used left out")
	dialog.showLocked = false
	assert(dialog.ToolClickable("locked", false) and dialog.ToolClickable("repair", true) and not dialog.ToolClickable("repair", false), "the switch for locked wares can be clicked while off, a dim repair cannot")
	local alpha, grey = dialog.ToolAppearance("locked", false, false)
	assert(alpha == 0.6 and grey, "locked switch off: grey, not faint")
	alpha, grey = dialog.ToolAppearance("locked", true, false)
	assert(alpha == 1 and not grey, "locked switch on: in colour")
	alpha = dialog.ToolAppearance("repair", false, false)
	assert(alpha == 0.3, "repair without money stays faint")
	assert(view.buttons[2].enabled == false and view.buttons[3].enabled == true, "train needs a selection, train all is possible (button 1 says goodbye)")
	GetTrainerServiceItemLink = savedLink
	-- Try on only with the modifier.
	local savedModified, savedDress, tried = IsModifiedClick, DressUpItemLink, nil
	DressUpItemLink = function(link) tried = link return true end
	IsModifiedClick = function() return false end
	assert(not ns.TryOnRecipe("item:101") and tried == nil, "plain click: no try-on")
	IsModifiedClick = function(kind) return kind == "DRESSUP" end
	assert(ns.TryOnRecipe("item:101") and tried == "item:101", "Ctrl + click tries the product on")
	assert(not ns.TryOnRecipe("spell:5"), "no item: nothing")
	IsModifiedClick, DressUpItemLink = savedModified, savedDress
	print("trainer view OK")
end)()
;(function()
	-- Recipe radar: ticked-off or bagged recipes count as collected; a right click ticks off all a vendor shows.
	local radar = ns:GetModule("RecipeRadar")
	assert(radar.IsCollected(5, { [5] = true }, 0) and radar.IsCollected(6, {}, 1) and not radar.IsCollected(7, {}, 0), "collected by mark or by count")
	local marked = {}
	radar.MarkCollected({ recipes = { { 11, "ok" }, { 12, "low" } } }, marked)
	assert(marked[11] and marked[12], "right click marks every recipe of the vendor")
	local savedLocale = GetLocale
	GetLocale = function() return "deDE" end
	assert(radar.WowheadText({ recipes = { { 11, "ok" }, { 12, "low" } } }) == "https://www.wowhead.com/forever/de/item=11\nhttps://www.wowhead.com/forever/de/item=12", "one Wowhead page per recipe")
	GetLocale = function() return "enUS" end
	assert(ns.WowheadURL("quest", 5) == "https://www.wowhead.com/forever/quest=5", "without a language part in English")
	GetLocale = savedLocale
	-- the world map symbol: click opens the links, Shift + click sets the waypoint
	local click = uv(ns.MapSymbols.AddSource, "sources")
	local symbol
	for _, source in ipairs(click or {}) do
		source(1429, function(_, _, given) if given.kind == "radar" then symbol = given end end)
	end
	if symbol then
		local shown, waypoint
		local savedEdit, savedShift, savedCan = ns.ShowEditWindow, IsShiftKeyDown, C_Map.CanSetUserWaypointOnMap
		ns.ShowEditWindow = function(_, _, text) shown = text end
		C_Map.CanSetUserWaypointOnMap = function() waypoint = true return false end
		IsShiftKeyDown = function() return false end
		symbol.click(symbol, "LeftButton")
		assert(shown and shown:find("item=", 1, true) and not waypoint, "click: Wowhead")
		shown = nil
		IsShiftKeyDown = function() return true end
		symbol.click(symbol, "LeftButton")
		assert(waypoint and not shown, "Shift + click: waypoint")
		ns.ShowEditWindow, IsShiftKeyDown, C_Map.CanSetUserWaypointOnMap = savedEdit, savedShift, savedCan
	else
		print("  (no radar symbol on the test map: click checked by WowheadText only)")
	end
	print("radar collected OK")
end)()
;(function()
	-- Buff reminder for the target: only within reach (false or 0 from the game); unknown or secret keeps it.
	local buffs = ns:GetModule("Buffs")
	assert(buffs.OutOfRange(false) and buffs.OutOfRange(0), "out of reach")
	assert(not buffs.OutOfRange(true) and not buffs.OutOfRange(1) and not buffs.OutOfRange(nil), "within reach or unknown")
	print("buff range OK")
end)()
;(function()
	-- Performance table (60 FPS = 16.7 ms budget): Peak red from 15 ms, orange 5-15 ms; session >5 ms rate 1 / 4 per min.
	local info = ns:GetModule("Info")
	assert(ns.SLOW_MS == 5, "slow from 5 ms")
	assert(info.PeakLevel(4.5, 2) == "green" and info.PeakLevel(5.0, 2) == "orange" and info.PeakLevel(4.5, 3) == "orange", "orange between")
	assert(info.PeakLevel(15.0, 0) == "red" and info.PeakLevel(1, 20) == "red" and info.PeakLevel(12) == "orange", "red only for real spikes")
	assert(info.SlowRateLevel(0, 60) == "green" and info.SlowRateLevel(19, 41 * 60) == "green", "sparse session spikes stay green")
	assert(info.SlowRateLevel(6, 180) == "orange" and info.SlowRateLevel(12, 180) == "red", "dense per-minute spikes turn orange/red")
	assert(info.SlowRateLevel(1, 10) == "orange" and info.SlowRateLevel(4, 10) == "red", "first-minute burst still flags immediately")
	print("cpu colours OK")
end)()
;(function()
	-- Rating: a chosen talent tree wins over the automatic one, if the class has it.
	local items = ns:GetModule("Items")
	assert(items.PickTree(0, 2, 3) == 2 and items.PickTree(3, 2, 3) == 3 and items.PickTree(3, 1, 1) == 1 and items.PickTree(nil, 1, 3) == 1, "chosen or automatic tree")
	local choices = upvalue(getW, "WEIGHTS")
	local profileOptions
	for _, option in ipairs(items.options) do
		if option.key == "scoreSpec" then profileOptions = option.values end
	end
	local savedClass, savedProfile, savedLevel = upvalue(getW, "playerClass"), upvalue(getW, "weights"), UnitLevel
	local savedTraits, savedChoice = C_Traits, items.cdb.scoreSpec
	local state, treeName = upvalue(getW, "weightsTree"), upvalue(getW, "weightsName")
	local preset = upvalue(getW, "weightsPreset")
	local automatic = 0
	C_Traits = {
		GetConfigInfo = function() return { treeIDs = { 77 } } end,
		GetGroupDisplayInfoByTreeID = function() return { trees[3], trees[1], trees[2] } end,
		GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 10 + automatic, currencyInfos = { { spent = 5 } } } } end,
	}
	UnitLevel = function() return 60 end
	for class, profiles in pairs(choices) do
		setuv(getW, "playerClass", class)
		assert(#profiles == 3 and #profileOptions() == (class == "DRUID" and 5 or 4), "each tree is selectable for " .. class)
		assert(profiles[1] ~= profiles[2] and profiles[2] ~= profiles[3] and profiles[1] ~= profiles[3], "one profile per " .. class .. " tree")
		for index = 1, 3 do
			automatic = index
			items.cdb.scoreSpec = 0
			setuv(getW, "weights", nil)
			local weights, _, tree, plan = ns.StatWeights()
			assert(weights == profiles[index] and tree == index and plan == index, "automatic profile for " .. class)
			local override = index % 3 + 1
			items.cdb.scoreSpec = override
			setuv(getW, "weights", nil)
			weights, _, tree, plan = ns.StatWeights()
			assert(weights == profiles[override] and tree == override and plan == override, "explicit profile for " .. class)
		end
	end
	assert(choices.MAGE[1].INT > choices.MAGE[3].INT and choices.HUNTER[3].DPS > choices.HUNTER[1].DPS
		and choices.SHAMAN[2].STR > choices.SHAMAN[2].INT, "key Forever specialization differences")
	setuv(getW, "playerClass", "DRUID")
	setuv(getW, "weights", nil)
	items.cdb.scoreSpec = 4
	local bear, _, bearTree, bearPlan = ns.StatWeights()
	assert(bear.STA > choices.DRUID[2].STA and bear.ARMOR > choices.DRUID[2].ARMOR and bearTree == 2 and bearPlan == 4,
		"bear shares the feral tree and uses its own template")
	setuv(getW, "playerClass", savedClass)
	setuv(getW, "weights", savedProfile)
	setuv(getW, "weightsTree", state)
	setuv(getW, "weightsName", treeName)
	setuv(getW, "weightsPreset", preset)
	C_Traits, UnitLevel, items.cdb.scoreSpec = savedTraits, savedLevel, savedChoice
	print("score tree OK")
end)()
;(function()
	-- Books: plain text becomes one paragraph (the game takes fonts only per tag), HTML stays.
	local R = ns:GetModule("Readable")
	assert(R.AsHTML("a < b & c\nd") == "<html><body><p>a &lt; b &amp; c<br/>d</p></body></html>", R.AsHTML("a < b & c\nd"))
	assert(R.AsHTML(" <HTML><body>x</body></HTML>") == " <HTML><body>x</body></HTML>", "HTML unchanged")
	print("readable plain text OK")
end)()
;(function()
	-- Settings: a module listed with chosen keys shows only those; every option with a key must be on some page.
	local listed, keyed = {}, {}
	for _, page in ipairs(ns.SettingsPages) do
		for _, entry in ipairs(page) do
			local name = entry[1]
			if entry.keys then
				keyed[name] = keyed[name] or {}
				for key in pairs(entry.keys) do keyed[name][key] = true end
			else
				listed[name] = true
			end
		end
	end
	local missing = {}
	for name, keys in pairs(keyed) do
		if not listed[name] then
			local module = ns:GetModule(name)
			local options = type(module.options) == "function" and module:options() or module.options or {}
			for _, opt in ipairs(options) do
				if opt.key and opt.type ~= "header" and opt.type ~= "button" and not keys[opt.key] then
					missing[#missing + 1] = name .. "." .. opt.key
				end
			end
		end
	end
	table.sort(missing)
	assert(#missing == 0, "options on no settings page: " .. table.concat(missing, ", "))
	print("settings pages OK")
end)()
;(function()
	-- Merchant list in columns: whole rows only, a thin bar for the position, groups for long lists.
	local dialog = ns:GetModule("Dialog")
	assert(dialog.ListVisible(100, 19) == 100, "a short list shows whole")
	assert(dialog.ListVisible(40 * 19 - 3, 19) == 8 * 19 - 3, "a long list shows only whole rows (8 of 19 points in 150)")
	local top, height = dialog.ScrollThumb(0, 400, 100)
	assert(top == 0 and height == 25, "thumb at the top, as tall as the visible share")
	top = dialog.ScrollThumb(300, 400, 100)
	assert(top == 75, "thumb at the bottom at the end of the list")
	assert(dialog.ScrollThumb(0, 50, 100) == 0, "nothing to scroll")
	local grouped = dialog.GroupWares({ { k = "a" }, { k = "b" }, { k = "a" } }, function(e) return e.k, "H" .. e.k end)
	assert(#grouped == 5 and grouped[1].header == "Ha" and grouped[3].k == "a" and grouped[4].header == "Hb",
		"groups in the order first met, merchant's order kept inside")
	local single = { { k = "a" }, { k = "a" } }
	assert(dialog.GroupWares(single, function(e) return e.k, "H" end) == single, "one group: no heading")
	local saved = { GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair,
		GetNumBuybackItems, ns.MerchantTools, C_Item.GetItemInfoInstant, rawget(_G, "INVTYPE_CHEST"), rawget(_G, "INVTYPE_HAND"),
		dialog.db.merchantGroups, ns.RewardComparisonState }
	ns.MerchantTools, ns.RewardComparisonState = nil, nil
	GetMerchantNumItems = function() return 10 end
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = 10, stackCount = 1, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantItemLink = function(i) return "item:" .. i end
	C_Item.GetItemInfoInstant = function(link)
		local i = tonumber(link:match("%d+"))
		return i, nil, nil, i % 2 == 0 and "INVTYPE_HAND" or "INVTYPE_ROBE", nil, 4
	end
	INVTYPE_CHEST, INVTYPE_HAND = "Brust", "Hände"
	GetMoney = function() return 1000 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	dialog.db.merchantGroups = true
	local function Rows()
		for _, block in ipairs(dialog.MerchantView().blocks) do if block.rows then return block.rows end end
	end
	local rows = Rows()
	assert(#rows == 12 and rows[1].header == "Brust" and rows[7].header == "Hände", "robe counts as chest, two headings")
	assert(rows[2].number == 1 and rows[2].text:find("Ware1", 1, true) and rows[8].number == 6 and rows[8].text:find("Ware2", 1, true),
		"key numbers follow the wares as shown, headings have none")
	assert(rows[1].action == nil and rows[1].number == nil, "a heading is no ware")
	dialog.db.merchantGroups = false
	rows = Rows()
	assert(#rows == 10 and not rows[1].header, "option off: no groups")
	dialog.db.merchantGroups = true
	GetMerchantNumItems = function() return 8 end
	rows = Rows()
	assert(#rows == 8 and not rows[1].header, "a short list stays without groups")
	-- Drawn: no error, the chosen row has the warm background and keeps the size of the others.
	GetMerchantNumItems = function() return 10 end
	local wasOn, wasMerchant = dialog.db.enabled, dialog.db.merchant
	dialog.db.enabled, dialog.db.merchant, dialog.reported = true, true, nil
	dialog:OnConversation("MERCHANT_SHOW")
	for line = math.max(1, #ns.db.bubbleTrace - 15), #ns.db.bubbleTrace do
		assert(not ns.db.bubbleTrace[line]:find(ns.L.DIALOG_TRACE_DRAW_ERROR:format(""), 1, true), ns.db.bubbleTrace[line])
	end
	local bubble = uv(dialog.Rerender, "bubble")
	local drawn = bubble.pools.row
	assert(drawn[2].Selected:IsShown() and not drawn[3].Selected:IsShown() and not drawn[1].Selected:IsShown(),
		"the first ware is lit, not the heading")
	assert(drawn[2]:GetHeight() == drawn[3]:GetHeight() and drawn[1]:GetHeight() == drawn[2]:GetHeight(), "all rows one height")
	assert(drawn[2].Num:IsShown() and drawn[2].Price:IsShown() and not drawn[1].Num:IsShown() and not drawn[1].Price:IsShown(),
		"wares show number and price, the heading neither")
	-- The basket gets a fixed line even when empty. Model wrapping when the price outgrows its line.
	local basket = bubble.pools.text[bubble.lastUsed.text - 2]
	local buy = bubble.pools.button[2]
	local setHeight, setPoint = rawget(bubble, "SetHeight"), rawget(buy, "SetPoint")
	bubble.SetHeight = function(self, height) self.testHeight = height end
	buy.SetPoint = function(self, _, _, _, _, y) self.testY = y end
	local priceWidth, basketText, basketWidth, wraps, lineHeight = 0
	basket.SetWidth = function(_, width) basketWidth = width end
	basket.SetText = function(_, text) basketText = text end
	basket.SetHeight = function(_, height) lineHeight = height end
	basket.SetWordWrap = function(_, value) wraps = value end
	basket.GetStringHeight = function() return wraps and priceWidth > basketWidth and 24 or 12 end
	basket.IsTruncated = function() return priceWidth > basketWidth end
	local coinPrice = "2 |TSilver:14:14|t 25 |TCopper:14:14|t"
	GetMoneyString = function(copper) return copper == 50 and coinPrice or tostring(copper) .. "c" end
	dialog:OnConversation("MERCHANT_UPDATE")
	local height, buttonY = bubble.testHeight, buy.testY
	assert(basketText == "" and height and buttonY, "the empty basket has its own line above the buttons")
	priceWidth = 100
	drawn[2].action("LeftButton")
	assert(basketText == ns.L.DIALOG_MERCHANT_CHOSEN:format(1, "10c"), "the selected ware appears in the basket")
	assert(bubble.testHeight == height and buy.testY == buttonY, "selecting a ware keeps the layout")
	priceWidth = 180
	drawn[2].onQuantity(5)
	assert(basketText == ns.L.DIALOG_MERCHANT_CHOSEN:format(5, coinPrice) and priceWidth <= basketWidth and not wraps
		and lineHeight >= 14, "the total and both coin icons fit on their own line")
	assert(bubble.testHeight == height and buy.testY == buttonY, "adding a denomination keeps the layout")
	priceWidth = 500
	drawn[2].onQuantity(99)
	assert(bubble.testHeight == height and buy.testY == buttonY, "an overflowing total keeps the layout")
	assert(bubble.BasketOverflow:IsShown() and bubble.BasketOverflow.total == basketText, "the tooltip has the full total")
	priceWidth = 0
	drawn[2].onQuantity(0)
	assert(basketText == "" and bubble.testHeight == height and buy.testY == buttonY and not bubble.BasketOverflow:IsShown(),
		"emptying the basket keeps the layout and removes the tooltip")
	basket.SetWidth, basket.SetText, basket.SetHeight, basket.SetWordWrap, basket.GetStringHeight, basket.IsTruncated =
		nil, nil, nil, nil, nil, nil
	bubble.SetHeight, buy.SetPoint = setHeight, setPoint
	dialog.db.enabled, dialog.db.merchant = wasOn, wasMerchant
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair, GetNumBuybackItems,
		ns.MerchantTools, C_Item.GetItemInfoInstant, INVTYPE_CHEST, INVTYPE_HAND, dialog.db.merchantGroups, ns.RewardComparisonState = unpack(saved, 1, 13)
	print("merchant columns OK")
end)()
;(function()
	-- Switching the thin line on grey items with the combined bag never opened: size without buttons.
	local saved = ContainerFrameCombinedBags
	local function Empty(_, index) index = index + 1 if index <= 2 then return index, nil end end
	ContainerFrameCombinedBags = { IsShown = function() return true end, EnumerateValidItems = function(self) return Empty, self, 0 end }
	local ok, err = pcall(ns:GetModule("Visuals").OnOptionChanged, ns:GetModule("Visuals"), "bagActionFrame")
	ContainerFrameCombinedBags = saved
	assert(ok, err)
	print("bag frame refresh OK")
end)()
;(function()
	-- Merchant in the bubble: rows with prices, Buy needs a selection that can be paid; keys: Tab moves the light.
	local dialog = ns:GetModule("Dialog")
	local tools = ns.MerchantTools
	ns.MerchantTools = nil
	GetMerchantNumItems = function() return 2 end
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = i * 100, stackCount = 1, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantItemLink = function() return nil end
	GetMoney = function() return 150 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	local view = dialog.MerchantView()
	local rows
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	-- Name and price in columns of their own; a price above the player's money is red.
	assert(rows and #rows == 2 and rows[1].text:find("Ware1", 1, true) and not rows[1].text:find("100c", 1, true)
		and rows[1].price == "100c" and rows[2].price == "|cffff4040200c|r", "two wares, prices in their own column")
	local listBlock
	for _, block in ipairs(view.blocks) do if block.rows then listBlock = block end end
	assert(listBlock.columns, "the merchant list is drawn in columns")
	local money, keys = view.blocks[#view.blocks - 1], view.blocks[#view.blocks]
	assert(money.money == "" and money.right == ns.L.DIALOG_MONEY:format("150c"), "money at the right, no basket at the left")
	assert(keys.text == ns.L.DIALOG_MERCHANT_KEYS and keys.small, "what the mouse does in one small line below")
	assert(view.buttons[2].enabled == false, "nothing selected: no purchase")
	-- The whole list is drawn and scrolls in the bubble (no pages of 14): every ware, the list marked to scroll.
	local many = GetMerchantNumItems
	GetMerchantNumItems = function() return 40 end
	local long = dialog.MerchantView()
	for _, block in ipairs(long.blocks) do if block.rows then assert(#block.rows == 40 and block.scroll, "all 40 wares, scrolling") end end
	local wasOn, wasMerchant = dialog.db.enabled, dialog.db.merchant
	dialog.db.enabled, dialog.db.merchant, dialog.reported = true, true, nil
	dialog:OnConversation("MERCHANT_SHOW")
	dialog.db.enabled, dialog.db.merchant = wasOn, wasMerchant
	local drawn
	local drawPattern = ns.L.DIALOG_TRACE_DRAWN:format(-1, -1, 40, -1):gsub("%-1", "%%d+")
	for line = math.max(1, #ns.db.bubbleTrace - 15), #ns.db.bubbleTrace do
		assert(not ns.db.bubbleTrace[line]:find(ns.L.DIALOG_TRACE_DRAW_ERROR:format(""), 1, true), ns.db.bubbleTrace[line])
		drawn = drawn or ns.db.bubbleTrace[line]:find(drawPattern)
	end
	assert(drawn and not dialog.reported, "the long list draws: " .. table.concat(ns.db.bubbleTrace, "\n", math.max(1, #ns.db.bubbleTrace - 15)))
	GetMerchantNumItems = many
	assert(dialog.ListOffset(30, nil, nil, 150) == 30, "stays where it was scrolled")
	assert(dialog.ListOffset(30, 10, 16, 150) == 10, "lit row above: up to it")
	assert(dialog.ListOffset(0, 200, 16, 150) == 66, "lit row below: just into view")
	assert(dialog.ListOffset(30, 60, 16, 150) == 30, "lit row in view: no move")
	-- A ware in the basket: Space and the number keys never buy (they are jump and action bar); the button does,
	-- and the basket is empty afterwards.
	rows[1].action("LeftButton")
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows[1].picked and view.buttons[2].enabled and view.buttons[2].spends, "picked ware can be bought, button marked as spending")
	local bought = {}
	BuyMerchantItem = function(index, quantity) bought[#bought + 1] = index .. "x" .. quantity end
	GetMerchantItemMaxStack = function() return 20 end
	local bubble = uv(dialog.Rerender, "bubble")
	local current = uv(dialog.Rerender, "current")
	if bubble and bubble.scripts and bubble.scripts.OnKeyDown and current then
		local saved = current.view
		current.view = view
		bubble.scripts.OnKeyDown(bubble, "SPACE")
		bubble.scripts.OnKeyDown(bubble, "1")
		current.view = saved
		assert(#bought == 0, "keys do not buy")
	end
	view.buttons[2].action()
	assert(bought[1] == "1x1" and #bought == 1, "button buys once: " .. table.concat(bought, ","))
	view = dialog.MerchantView()
	assert(view.buttons[2].enabled == false, "basket empty after buying")
	-- A pack of 200: quantity 2 means two packs, 400 items, bought pack by pack.
	local savedMerchant = C_MerchantFrame
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Pfeil", texture = 1, price = 10, stackCount = 200, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantNumItems = function() return 1 end
	GetMoney = function() return 150 end
	local savedShift = IsShiftKeyDown
	IsShiftKeyDown = function() return false end
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	rows[1].action("LeftButton")
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	rows[1].action("LeftButton") -- counts up to 2
	view = dialog.MerchantView()
	wipe(bought)
	view.buttons[2].action()
	assert(#bought == 2 and bought[1] == "1x200" and bought[2] == "1x200", "two packs of 200: " .. table.concat(bought, ","))
	IsShiftKeyDown = savedShift
	C_MerchantFrame = savedMerchant
	GetMerchantNumItems = function() return 2 end
	-- Restock at the merchant: a marked item sold singly is bought up to a full stack, capped by the purse.
	local restock = ns:GetModule("Restock")
	local savedDb, savedCdb = restock.db, restock.cdb
	restock.db, restock.cdb = { enabled = true, message = false }, { items = { [777] = true, [888] = "bank" } }
	GetMerchantItemLink = function(i) return i == 1 and "item:777" or nil end
	local savedItem = C_Item
	C_Item = setmetatable({ GetItemInfoInstant = function(link) return tonumber(tostring(link):match("item:(%d+)")) end,
		GetItemMaxStackSizeByID = function() return 20 end, GetItemCount = function() return 15 end }, { __index = savedItem })
	local plan, planCost = restock.MerchantPlan()
	assert(#plan == 1 and plan[1].index == 1 and plan[1].amount == 1, "restock buys the one missing item (money 150, price 100): " .. tostring(plan[1] and plan[1].amount))
	assert(planCost == 100, "restock cost")
	C_Item = savedItem
	restock.db, restock.cdb = savedDb, savedCdb
	GetMerchantItemLink = function() return nil end
	ns.MerchantTools = tools
	print("merchant view OK")
end)()
;(function()
	-- Drawing the bubble fails halfway: no empty bubble stays, Blizzard's window takes the step.
	local dialog = ns:GetModule("Dialog")
	local render = uv(dialog.Rerender, "Render")
	local body = uv(render, "RenderView")
	local printed = ns.Print
	ns.Print = function() end
	setuv(render, "RenderView", function() error("kaputt") end)
	setuv(dialog.Rerender, "current", { view = { kind = "GOSSIP_SHOW" } })
	render({ kind = "GOSSIP_SHOW" })
	assert(uv(dialog.Rerender, "current") == nil, "after a drawing error the bubble lets go of the step")
	setuv(render, "RenderView", body)
	ns.Print = printed
	dialog.reported = nil
	print("dialog render error OK")
end)()
;(function()
	-- The NPC's plate whose fields Blizzard has not filled yet is found by its unit token.
	local dialog = ns:GetModule("Dialog")
	local find = uv(dialog.WatchPlate, "NpcNameplate")
	local saved = { UnitExists, UnitGUID, C_NamePlate, UnitIsUnit }
	local plate = { IsForbidden = function() return false end } -- no unitToken yet
	UnitExists = function(token) return token == "nameplate3" end
	UnitGUID = function(token) return token == "nameplate3" and "Creature-NPC" or nil end
	UnitIsUnit = function() return false end
	C_NamePlate = { GetNamePlates = function() return { plate } end,
		GetNamePlateForUnit = function(token) return token == "nameplate3" and plate or nil end }
	setuv(find, "npcGuid", "Creature-NPC")
	assert(find() == plate, "plate found by its unit token")
	setuv(find, "npcGuid", nil)
	UnitExists, UnitGUID, C_NamePlate, UnitIsUnit = saved[1], saved[2], saved[3], saved[4]
	print("dialog plate by token OK")
end)()
;(function()
	-- The bubble stays wholly on the screen while the option "on screen" is on
	local dialog = ns:GetModule("Dialog")
	local place = uv(dialog.WatchPlate, "Place")
	local clamped
	local bubble = { ClearAllPoints = function() end, SetPoint = function() end, IsShown = function() return false end,
		SetClampedToScreen = function(_, on) clamped = on end }
	local savedBubble = uv(place, "bubble")
	setuv(place, "bubble", bubble)
	local savedScreen, savedHidePlate = dialog.db.onScreen, dialog.db.hidePlate
	dialog.db.onScreen, dialog.db.hidePlate = true, false
	local plate = CreateFrame("Frame")
	place(plate)
	assert(clamped == true, "clamped with the option")
	dialog.db.onScreen = false
	place(plate)
	assert(clamped == false, "free without it")
	dialog.db.onScreen, dialog.db.hidePlate = savedScreen, savedHidePlate
	dialog.anchorPlate = nil
	setuv(place, "bubble", savedBubble)
	print("dialog clamp OK")
end)()

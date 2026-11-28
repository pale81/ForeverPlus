(function()
	-- Upcoming recipes: what is not known yet, by skill, learnable now when skill and level allow it
	local P = ns:GetModule("ProfessionPlan")
	local list = {
		{ name = "Grobes Schleifmittel", skill = 75 },
		{ name = "Bronzestab", skill = 50, known = true },
		{ name = "Kupferkettenhose", skill = 1 },
		{ name = "Geselle", skill = 50, level = 10 },
		{ name = "Experte", skill = 125, level = 20 },
	}
	local rows = P.Upcoming(list, { ["Kupferkettenhose"] = true }, 60, 12)
	local names = {}
	for _, row in ipairs(rows) do names[#names + 1] = row.entry.name .. (row.now and "+" or "") end
	assert(table.concat(names, ",") == "Geselle+,Grobes Schleifmittel,Experte", table.concat(names, ","))
	assert(#P.Upcoming(nil, {}, 0, 1) == 0, "no list")
	-- Blizzard sorts the divider and the native skill headers with the learned categories.
	local roots = {}
	local function Node(data)
		return { data = data, children = {}, GetData = function(self) return self.data end,
			SetCollapsed = function(self, value) self.collapsed = value end,
			Insert = function(self, childData)
				local child = Node(childData)
				self.children[#self.children + 1] = child
				return child
			end }
	end
	local function SortRoot(lhs, rhs)
		local left, right = lhs:GetData(), rhs:GetData()
		if left.group ~= right.group then
			return left.group < right.group
		end
		return left.categoryInfo.uiOrder < right.categoryInfo.uiOrder
	end
	roots[1] = Node({ group = 2, categoryInfo = { uiOrder = 1 } })
	roots[2] = Node({ group = 1, categoryInfo = { uiOrder = 2 } })
	local provider = {
		Insert = function(_, data)
			local node = Node(data)
			roots[#roots + 1] = node
			table.sort(roots, SortRoot)
			return node
		end,
		Remove = function(_, node)
			for i, root in ipairs(roots) do
				if root == node then return table.remove(roots, i) end
			end
		end,
	}
	local savedFrame, savedTradeSkill, savedLevel = ProfessionsFrame, C_TradeSkillUI, UnitLevel
	local searching, collapses = false, {}
	ProfessionsFrame = { CraftingPage = { GetCollapses = function() return collapses end,
		RecipeList = { ScrollBox = { GetDataProvider = function() return provider end },
			SearchBox = { HasText = function() return searching end } } } }
	local recipeScans = 0
	C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Schmiedekunst", skillLevel = 60 } end,
		GetAllRecipeIDs = function() recipeScans = recipeScans + 1 return { 1 } end,
		GetRecipeInfo = function() return { name = "Kupferkettenhose", learned = true } end }
	UnitLevel = function() return 12 end
	P.cdb.trainers["Schmiedekunst"] = list
	P.db.upcoming = true
	P.Inject()
	assert(recipeScans == 1, "check learned recipes for a saved trainer list")
	assert(#roots == 6 and roots[3].data.isDivider, "divider and three skill categories after the learned categories")
	local requirements = { 50, 75, 125 }
	for i, required in ipairs(requirements) do
		local category = roots[3 + i]
		local children = category.children
		assert(category.data.categoryInfo.name == ns.L.PROFPLAN_SKILL:format(required), "native categories in skill order")
		assert(#children == 3 and children[1].data.topPadding and children[3].data.bottomPadding, "native category spacing")
		assert(children[2].data.fpPlan == "recipe" and not children[2].data.recipeInfo, "upcoming recipes stay out of crafting selection")
	end
	assert(roots[4].children[2].data.right == ns.L.PROFPLAN_NOW, "learnable recipe keeps its status")
	assert(roots[6].children[2].data.right == ns.L.PROFPLAN_LEVEL:format(20), "level requirement stays visible")
	collapses[roots[4].data.categoryInfo.categoryID] = true
	P.Inject()
	assert(#roots == 6 and roots[4].collapsed, "refresh restores collapsed categories without duplicates")
	searching = true
	P.Inject()
	assert(#roots == 2 and recipeScans == 2, "search removes all upcoming categories without scanning")
	searching = false
	P.cdb.trainers["Schmiedekunst"] = nil
	P.Inject()
	assert(#roots == 3 and roots[3].children[1].data.fpPlan == "note" and recipeScans == 2,
		"no trainer list yet: show a note without scanning")
	P.db.upcoming = false
	P.Inject()
	assert(#roots == 2, "taken out when switched off")
	-- Hover a future recipe from an old saved trainer list, which had neither an item link nor a recipe ID.
	local savedSpell, savedTooltip, savedTitle, savedLine = C_Spell, GameTooltip, GameTooltip_SetTitle, GameTooltip_AddNormalLine
	local savedPreview, frame, shown, title = P.db.preview, NewFrame("Frame"), nil, nil
	local savedTimer, savedTicker, savedUpgrade = C_Timer.NewTimer, C_Timer.NewTicker, ns.RecipeUpgradeState
	local savedTooltipInfo = C_TooltipInfo
	local tooltipTimer, arrowTicker, schematicReads = nil, nil, 0
	C_Timer.NewTimer = function(delay, fn)
		tooltipTimer = { delay = delay, Run = fn, Cancel = function(self) self.cancelled = true end }
		return tooltipTimer
	end
	C_Timer.NewTicker = function(_, fn)
		arrowTicker = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return arrowTicker
	end
	local lines = {}
	frame.GetObjectType = function() return "Frame" end
	setmetatable(frame, { __index = function(self, key)
		if key:sub(1, 2) ~= "fp" then return frameMeta.__index(self, key) end
	end })
	C_Spell = { GetSpellIDForSpellIdentifier = function(name) return name == "Bronzener Kriegshammer" and 9985 or nil end }
	C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { parentProfessionName = "Schmiedekunst" } end
	C_TradeSkillUI.GetRecipeSchematic = function(id)
		schematicReads = schematicReads + 1
		return id == 9985 and { outputItemID = 7958 } or {}
	end
	local cachedItemData = { lines = {} }
	C_TooltipInfo = { GetHyperlink = function(link)
		assert(link == "item:7958")
		return cachedItemData
	end }
	GameTooltip = NewFrame("Tooltip")
	GameTooltip.SetOwner = function(self, owner) self.owner = owner end
	GameTooltip.IsOwned = function(self, owner) return self.owner == owner end
	GameTooltip.ProcessInfo = function(self, info)
		shown = info
		info.tooltipPostCall(self)
		return true
	end
	GameTooltip_SetTitle = function(_, name) title = name end
	GameTooltip_AddNormalLine = function(_, line) lines[#lines + 1] = line end
	P.db.preview = false
	local acquired = uv(P.HookList, "OnAcquired")
	local function hover(entry)
		shown, title, lines = nil, nil, {}
		acquired(nil, frame, Node({ fpPlan = "recipe", entry = entry, profession = "Schmiedekunst" }))
		frame:GetScript("OnEnter")(frame)
	end
	local hammer = { name = "Bronzener Kriegshammer", skill = 100, cost = 250 }
	hover(hammer)
	assert(tooltipTimer.delay > 0)
	frame:GetScript("OnLeave")(frame)
	assert(tooltipTimer.cancelled and schematicReads == 0 and not shown, "passing over a row skips the tooltip and schematic")
	hover(hammer)
	tooltipTimer:Run()
	assert(not shown and tooltipTimer.delay == 0, "tooltip data is prepared before rendering")
	tooltipTimer:Run()
	assert(shown and shown.getterName == "GetHyperlink" and shown.getterArgs[1] == "item:7958" and title == nil,
		"an old entry shows the native item tooltip even with recipe preview disabled")
	assert(shown.tooltipData == cachedItemData, "the renderer reuses the data read in the previous frame")
	assert(lines[1] == ns.L.PROFPLAN_SKILL:format(100) and lines[2] == GetMoneyString(250, true), "training details follow the item stats")
	hover(hammer)
	tooltipTimer:Run()
	tooltipTimer:Run()
	assert(schematicReads == 1, "repeated item tooltips reuse the output link")
	hover({ name = "Verzauberung", skill = 120, recipeID = 2000 })
	tooltipTimer:Run()
	tooltipTimer:Run()
	assert(shown and shown.getterName == "GetSpellByID" and shown.getterArgs[1] == 2000, "a recipe with no output item shows its spell")
	hover({ name = "Unbekannt", skill = 125 })
	tooltipTimer:Run()
	assert(shown == nil and title == "Unbekannt" and lines[1] == ns.L.PROFPLAN_SKILL:format(125), "no match: show the saved training details")
	P.db.preview = true
	ns.RecipeUpgradeState = function(link) return link == "item:7958" end
	hover(hammer)
	assert(not frame.fpArrow, "the list can draw before an arrow is checked")
	arrowTicker:Run()
	assert(frame.fpArrow:IsShown() and schematicReads == 2, "the deferred arrow uses the same cached output link")
	tooltipTimer:Run()
	acquired(nil, frame, Node({ bottomPadding = true }))
	assert(tooltipTimer.cancelled and not shown and not frame.fpText:IsShown() and not frame.fpArrow:IsShown()
		and not frame.fpHighlight:IsShown() and not frame.fpData,
		"a recipe frame recycled as padding clears its visuals and tooltip data")
	if not arrowTicker.cancelled then arrowTicker:Run() end
	P.db.preview = savedPreview
	C_Timer.NewTimer, C_Timer.NewTicker, ns.RecipeUpgradeState = savedTimer, savedTicker, savedUpgrade
	C_TooltipInfo = savedTooltipInfo
	C_Spell, GameTooltip, GameTooltip_SetTitle, GameTooltip_AddNormalLine = savedSpell, savedTooltip, savedTitle, savedLine
	ProfessionsFrame, C_TradeSkillUI, UnitLevel = savedFrame, savedTradeSkill, savedLevel
	print("profession plan OK")
end)()
;(function()
	local plan, auction = ns:GetModule("ProfessionPlan"), ns:GetModule("Auction")
	local savedAuction, savedVendor = ns.db.auctionPrices, auction.cdb.vendorBuyPrices
	local savedCount, savedMerchant, savedItemID = GetMerchantNumItems, C_MerchantFrame, GetMerchantItemID
	ns.db.auctionPrices = { [101] = { 10, 1 }, [102] = { 55, 1 }, [105] = { 60, 1 } }
	auction.cdb.vendorBuyPrices = {}
	local offers = {
		{ price = 250, stackCount = 5, numAvailable = -1, isPurchasable = true },
		{ price = 1, stackCount = 1, numAvailable = 1, isPurchasable = true },
		{ price = 1, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = true },
	}
	GetMerchantNumItems = function() return #offers end
	GetMerchantItemID = function(index) return ({ 105, 104, 103 })[index] end
	C_MerchantFrame = { GetItemInfo = function(index) return offers[index] end }
	uv(auction.OnLogin, "RecordMerchantPrices")()
	assert(auction.ReagentPrice(105) == 50 and not auction.ReagentPrice(104) and not auction.ReagentPrice(103),
		"only unlimited gold offers count and merchant stacks are priced per unit")
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemID = savedCount, savedMerchant, savedItemID

	local attached, redraws = true, 0
	local function Redraw()
		if attached then redraws = redraws + 1 end
	end
	local provider
	local function Node(data)
		local node = { data = data, children = {}, GetData = function(self) return self.data end }
		function node:GetNodes() return self.children end
		function node:GetParent() return self.parent end
		function node:InsertNode(child, index)
			child.parent = self
			table.insert(self.children, index or #self.children + 1, child)
			if provider then provider:Invalidate() else Redraw() end
			return child
		end
		function node:Insert(childData) return self:InsertNode(Node(childData)) end
		function node:Remove(child, skipInvalidation)
			for index, current in ipairs(self.children) do
				if child == current then
					local removed = table.remove(self.children, index)
					if not skipInvalidation then
						if provider then provider:Invalidate() else Redraw() end
					end
					return removed
				end
			end
		end
		return node
	end
	local root = Node()
	local linearized
	local function CollectNodes(excludeCollapsed)
		local nodes = {}
		local function Add(parent)
			for _, node in ipairs(parent.children) do
				nodes[#nodes + 1] = node
				if not (excludeCollapsed and node.collapsed) then Add(node) end
			end
		end
		Add(root)
		return nodes
	end
	provider = {
		GetRootNode = function() return root end,
		GetChildrenNodes = function() return root.children end,
		Insert = function(_, data) return root:Insert(data) end,
		Remove = function(_, node) return node.parent:Remove(node) end,
		IsEmpty = function() return #root.children == 0 end,
		Invalidate = function()
			linearized = nil
			Redraw()
		end,
		GetLinearized = function()
			if not linearized then
				linearized = CollectNodes(true)
			end
			return linearized
		end,
		GetSize = function(self, excludeCollapsed)
			if excludeCollapsed then
				return #self:GetLinearized()
			end
			return #CollectNodes(false)
		end,
		Enumerate = function(self, _, _, excludeCollapsed)
			if excludeCollapsed then
				return ipairs(self:GetLinearized())
			end
			return ipairs(CollectNodes(false))
		end,
	}
	function provider:EnumerateEntireRange() return self:Enumerate(nil, nil, false) end
	function provider:FindElementDataByPredicate(predicate, excludeCollapsed)
		for _, node in self:Enumerate(nil, nil, excludeCollapsed) do
			if predicate(node) then return node end
		end
	end
	local savedFrame, savedAPI, savedProfessions = ProfessionsFrame, C_TradeSkillUI, Professions
	local savedDifficulty, savedOption = Enum.TradeskillRelativeDifficulty, plan.db.efficientSkillUps
	local savedTicker, savedProfile, savedAfter = C_Timer.NewTicker, debugprofilestop, C_Timer.After
	local scan, clock, selectRecommended
	C_Timer.After = function(_, fn) selectRecommended = fn end
	C_Timer.NewTicker = function(_, fn)
		scan = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return scan
	end
	clock = 0
	debugprofilestop = function() clock = clock + 0.3 return clock end
	local function FinishScan()
		for _ = 1, 20 do
			if scan.cancelled then return end
			scan:Run()
		end
		error("recipe scan did not finish")
	end
	local noResults, skill, skillUpOnly = NewFrame("FontString"), 25, true
	local selected
	local view = {
		DetachDataProviderCallbacks = function() assert(attached) attached = false end,
		AttachDataProviderCallbacks = function() assert(not attached) attached = true end,
		DataProviderContentsChanged = Redraw,
	}
	ProfessionsFrame = { CraftingPage = { RecipeList = { NoResultsText = noResults,
		ScrollBox = { GetDataProvider = function() return provider end, GetView = function() return view end },
		selectionBehavior = {
			GetFirstSelectedElementData = function() return selected end,
			DeselectElementData = function(_, node) assert(selected == node) selected = nil end,
		},
		SelectRecipe = function(_, info)
			for _, node in provider:EnumerateEntireRange() do
				if node.data.recipeInfo == info then selected = node return node end
			end
		end,
	} } }
	local rankedReads = 0
	Professions = { InLocalCraftingMode = function() return true end, GetHighestLearnedRecipe = function(recipe)
		assert(recipe.recipeID == 3)
		rankedReads = rankedReads + 1
		return { recipeID = 7, canSkillUp = true, numSkillUps = 1, relativeDifficulty = 2 }
	end }
	Enum.TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 }
	local category = root:Insert({ group = 1, categoryInfo = { uiOrder = 1 } })
	for id = 1, 6 do
		category:Insert({ recipeInfo = { recipeID = id, learned = true, canSkillUp = id ~= 3, numSkillUps = 1,
			relativeDifficulty = 0, nextRecipeID = id == 3 and 7 or nil, disabled = id == 6 } })
	end
	local reads = 0
	C_TradeSkillUI = {
		GetOnlyShowSkillUpRecipes = function() return skillUpOnly end,
		GetBaseProfessionInfo = function() return { skillLevel = skill, maxSkillLevel = 75 } end,
		GetRecipeSchematic = function(id)
			reads = reads + 1
			assert(id ~= 3, "use the highest learned rank's schematic")
			id = id == 7 and 3 or id
			local quantity = ({ 8, 2, 1, 1, 1 })[id]
			return { reagentSlotSchematics = {
				{ required = true, quantityRequired = quantity, reagents = { { itemID = id == 3 and 102 or id + 100 } } },
				{ required = false, quantityRequired = 10, reagents = {} },
			} }
		end,
	}
	local function Recommendations()
		return root.children[1].children
	end
	plan.db.efficientSkillUps = true
	selected, redraws = category.children[6], 0
	plan.Inject()
	assert(reads == 0 and root.children[1] == category, "the list hook leaves expensive recipe reads for later frames")
	scan:Run()
	assert(reads == 1 and root.children[1] == category and redraws == 0, "a scan slice yields before changing the visible list")
	FinishScan()
	local rows = Recommendations()
	assert(attached and redraws == 1 and not selected and selectRecommended, "the list redraws once before loading a new recipe")
	selectRecommended()
	assert(selected == rows[1], "the first available recipe is selected after the redraw")
	assert(#rows == 3 and rows[1].data.recipeInfo.recipeID == 5 and rows[2].data.recipeInfo.recipeID == 2
		and rows[3].data.recipeInfo.recipeID == 1, "top three balance reagent cost, reagent count and skill chance")
	assert(rows[1].data.fpSkillUp.cost == 50 and rows[2].data.fpSkillUp.units == 2 and reads == 5,
		"optional reagents and disabled recipes do not affect the ranking")
	assert(rankedReads == 1, "rank lookup is reserved for recipes with ranks")

	ns.db.auctionPrices = {}
	plan.Inject()
	FinishScan()
	rows = Recommendations()
	assert(rows[2].data.recipeInfo.recipeID == 4 and rows[2].data.fpSkillUp.cost == nil,
		"missing prices fall back to materials per skill point")

	selected, skillUpOnly = rows[1], false
	plan.Inject()
	assert(root.children[1] == category and #category.children == 6, "turning off the native filter restores the original tree")
	assert(selected == category.children[5], "the selected recipe is restored to its original row")
	skillUpOnly = true
	plan.Inject()
	scan:Run()
	local obsoleteScan = scan
	skillUpOnly = false
	plan.Inject()
	assert(obsoleteScan.cancelled and root.children[1] == category, "changing the filter cancels a pending scan")

	selected, skillUpOnly, skill = nil, true, 75
	root:Remove(category)
	noResults:Show()
	reads = 0
	plan.Inject()
	assert(reads == 0 and Recommendations()[1].data.text == ns.L.PROFPLAN_SKILL_CAP and not noResults:IsShown(),
		"at the cap the empty list shows a single message without reading recipes")
	plan.db.efficientSkillUps = false
	plan.Inject()
	assert(provider:IsEmpty() and noResults:IsShown(), "turning off the addon filter restores Blizzard's empty state")
	print("profession skill-up filter OK")

	local savedItemUtil = rawget(_G, "ItemUtil")
	local makeable, inventory = false, { [101] = 1, [102] = 4, [103] = 1, [104] = 2 }
	local inventoryReads = {}
	ItemUtil = { GetCraftingReagentCount = function(id)
		inventoryReads[id] = (inventoryReads[id] or 0) + 1
		return inventory[id] or 0
	end }
	C_TradeSkillUI.GetOnlyShowMakeableRecipes = function() return makeable end
	C_TradeSkillUI.GetRecipeSchematic = function(id)
		assert(id ~= 3, "material filter uses the highest learned rank")
		local reagents = { [1] = { { itemID = 101 } }, [2] = { { itemID = 102 } },
			[7] = { { itemID = 107 }, { itemID = 103 } }, [4] = { { itemID = 104 } },
			[5] = { { itemID = 107 } } }
		return { reagentSlotSchematics = reagents[id] and {
			{ required = id ~= 4, quantityRequired = 4, reagents = reagents[id] },
		} or {} }
	end
	root:InsertNode(category)
	local favorites = root:Insert({ categoryInfo = { uiOrder = 0 } })
	local favoriteInfo = { recipeID = 1, learned = true, favoritesInstance = true }
	local favorite = favorites:Insert({ recipeInfo = favoriteInfo })
	local empty = root:Insert({ categoryInfo = { uiOrder = 2 } })
	empty:Insert({ recipeInfo = { recipeID = 4, learned = true } })
	local unlearned = root:Insert({ categoryInfo = { uiOrder = 3 } })
	unlearned:Insert({ recipeInfo = { recipeID = 1, learned = false } })
	category.collapsed = true
	local padding = category:Insert({ bottomPadding = true })
	local before = { unpack(category.children) }
	local events = uv(ns.RegisterEvent, "listeners")
	assert(not plan.db.withMaterials, "material filtering is off by default")
	-- Populate LinearizedTreeDataProviderMixin's cache just like ScrollBox:SetDataProvider does.
	assert(provider:GetSize(true) == 7, "unfiltered linearized cache contains all visible rows")
	selected, redraws = favorite, 0
	ns.SetOption("ProfessionPlan", "withMaterials", true)
	FinishScan()
	assert(redraws == 1 and provider:GetSize(true) == 3,
		"material filter invalidates the linearized tree cache and redraws once")
	assert(#root.children == 2 and root.children[1] == category and root.children[2] == favorites
		and selected == favorite and category.collapsed, "material filter keeps matching categories, favorites and selection")
	assert(#category.children == 4 and category.children[1] == before[1] and category.children[2] == before[2]
		and category.children[3] == before[3] and category.children[4] == padding,
		"partial stacks, full stacks and alternative reagents match; optional or absent reagents do not")
	assert(inventoryReads[101] == 1 and inventoryReads[107] == 1 and not inventoryReads[104],
		"each reagent count is read once and optional reagents are skipped")

	category.collapsed = false
	provider:Invalidate()
	assert(provider:GetSize(true) == 7, "expanding category refreshes linearized cache before bag update")
	inventory = { [107] = 1 }
	events.BAG_UPDATE_DELAYED[plan]()
	assert(selected == favorite and root.children[2] == favorites, "the old result stays visible during a bag refresh")
	FinishScan()
	selectRecommended()
	assert(provider:GetSize(true) == 4 and #root.children == 1 and #category.children == 3
		and category.children[1] == before[3] and category.children[2] == before[5] and selected == before[3],
		"bag changes remove depleted recipes, refresh linearized cache and select the first visible match")
	inventory = {}
	events.PLAYERBANKSLOTS_CHANGED[plan]()
	FinishScan()
	assert(provider:IsEmpty() and provider:GetSize(true) == 0 and noResults:IsShown(),
		"an empty result clears linearized cache and uses the native empty state")

	makeable = true
	plan.Inject()
	assert(provider:GetSize(true) == 7 + #before and #root.children == 4 and #category.children == #before
		and not noResults:IsShown(),
		"the native makeable filter takes precedence and restores the native list")
	for index, node in ipairs(before) do assert(category.children[index] == node, "restored recipe order") end

	makeable, skill, inventory = false, 25, { [101] = 1, [102] = 4 }
	plan.db.efficientSkillUps = true
	plan.Inject()
	FinishScan()
	rows = Recommendations()
	assert(#rows == 2 and rows[1].data.fpSkillUp and rows[2].data.fpSkillUp,
		"the top skill-up recommendations respect available materials")
	plan.db.efficientSkillUps = false
	ns.SetOption("ProfessionPlan", "withMaterials", false)
	assert(#root.children == 4 and #category.children == #before and not (events.BAG_UPDATE_DELAYED or {})[plan],
		"switching off restores all native rows and stops bag monitoring")
	ItemUtil = savedItemUtil
	plan.db.efficientSkillUps = savedOption
	C_Timer.NewTicker, debugprofilestop, C_Timer.After = savedTicker, savedProfile, savedAfter
	Enum.TradeskillRelativeDifficulty, ProfessionsFrame, C_TradeSkillUI, Professions = savedDifficulty, savedFrame, savedAPI, savedProfessions
	ns.db.auctionPrices, auction.cdb.vendorBuyPrices = savedAuction, savedVendor
	print("profession material filter OK")
end)()
;(function()
	-- Core helpers
	local savedSecret = issecretvalue
	issecretvalue = function(value) return value == "geheim" end
	assert(ns.Secret("geheim") == true and ns.Secret("offen") == false and ns.Secret(nil) == false, "Secret")
	local kind, id = ns.GuidParts("Creature-0-1-2-3-1689-0000")
	assert(kind == "Creature" and id == 1689, "GuidParts")
	assert(ns.GuidParts("geheim") == nil and ns.GuidParts(nil) == nil and ns.GuidParts(5) == nil, "GuidParts: nothing usable")
	issecretvalue = savedSecret
	assert(ns.LowerCommand("BÜCHER Ärger ÖL") == "bücher ärger öl", "commands with capital umlauts")
	-- A listener registering another one for the same event while it runs: no error, the new one hears the next event
	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	local a, b, heard = {}, {}, 0
	for i = 1, 20 do
		ns:RegisterEvent("FP_TEST_EVENT", { name = "filler" .. i }, function() end)
	end
	ns:RegisterEvent("FP_TEST_EVENT", a, function()
		ns:RegisterEvent("FP_TEST_EVENT", b, function() heard = heard + 1 end)
	end)
	onEvent(nil, "FP_TEST_EVENT")
	local first = heard
	onEvent(nil, "FP_TEST_EVENT")
	assert(first <= 1 and heard == first + 1, "listener added during an event")
	-- An error names the listener and the event: the game's stack ends at the dispatcher's xpcall
	local savedHandler, reported = geterrorhandler, {}
	geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
	ns:RegisterEvent("FP_TEST_ERROR", { name = "Faulty" }, function() error("boom", 0) end)
	ns:RegisterEvent("FP_TEST_ERROR", { name = "Healthy" }, function() heard = heard + 1 end)
	heard = 0
	onEvent(nil, "FP_TEST_ERROR")
	geterrorhandler = savedHandler
	assert(#reported == 1 and reported[1] == "boom (ForeverPlus listener Faulty: FP_TEST_ERROR)" and heard == 1,
		"listener errors name the listener, the others still run: " .. tostring(reported[1]))
	-- Timers run through the measurement
	local savedAfter, savedTimer, savedTicker = C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker
	C_Timer.After = function(_, fn) fn() end
	C_Timer.NewTimer = function(_, fn) fn() return {} end
	C_Timer.NewTicker = function(_, fn, n) fn("ticker") return { n = n } end
	local savedTime = GetTime
	local now = savedTime()
	GetTime = function() return now end
	ns.SetMeasuring(true)
	now = now + 1
	local ran, got = 0, nil
	ns.After("Test: after", 1, function() ran = ran + 1 end)
	ns.NewTimer("Test: timer", 1, function() ran = ran + 1 end)
	local ticker = ns.NewTicker("Test: ticker", 1, function(t) got = t end, 3)
	assert(ran == 2 and got == "ticker" and ticker.n == 3, "timers call through")
	assert(ns.timings["Test: after"].count == 1 and ns.timings["Test: timer"].count == 1 and ns.timings["Test: ticker"].count == 1,
		"timers are measured")
	local spikeFrame = uv(ns.SetMeasuring, "spikeFrame")
	assert(spikeFrame.shown == true or spikeFrame:IsShown() == true, "spike counter runs while measuring")
	ns.SetMeasuring(false)
	GetTime = savedTime
	assert(not ns.measuring and spikeFrame:IsShown(), "session sampling continues after detailed measurement stops")
	C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker = savedAfter, savedTimer, savedTicker
	-- No timer bypasses the measurement
	for line in io.lines(root .. "/ForeverPlus.toc") do
		if not line:match("^##") and line:match("%.lua$") and not line:match("Core.Core%.lua$") then
			local path = line:gsub("\\", "/")
			local text = io.open(root .. "/" .. path):read("*a")
			for call in text:gmatch("C_Timer%.%a+%([^\n]*") do
				assert(call:find("ns.Measured", 1, true) or call:find("CheckRange", 1, true), path .. ": timer outside the measurement: " .. call)
			end
		end
	end
	-- The setup never overwrites existing local rules
	for line in io.lines(root .. "/tools/setup-local.sh") do
		if line:find("cp tools/local/rules.md", 1, true) then
			assert(line:find("[ -e CLAUDE.md ] ||", 1, true), "setup-local.sh: overwrites the local rules: " .. line)
		end
	end
	print("core helpers OK")
end)()
;(function()
	-- Talent tree after the class: the class line gets it once; others are asked for by inspection and kept
	local T = ns:GetModule("Tooltip")
	assert(T.db.talentTree == true and T.db.hoverTalentIcon == false, "defaults: tree on, symbol off")
	assert(T.WithTree("Stufe 20 Krieger (Spieler)", "Krieger", "Waffen") == "Stufe 20 Krieger (Waffen) (Spieler)", "after the class")
	assert(T.WithTree("Stufe 20 Krieger (Waffen)", "Krieger", "Waffen") == nil, "not twice")
	assert(T.WithTree("Gilde", "Krieger", "Waffen") == nil, "no class in the line")
	local saved = { UnitIsUnit, UnitGUID, CanInspect, NotifyInspect, InCombatLockdown, GetTime, ns.TalentTreeOf, InspectFrame }
	local asked = 0
	UnitIsUnit = function() return false end
	UnitGUID = function(unit) return unit == "mouseover" and "Player-1-0002" or "Player-1-0001" end
	CanInspect = function() return true end
	NotifyInspect = function() asked = asked + 1 end
	InCombatLockdown = function() return false end
	InspectFrame = { IsShown = function() return false end }
	ClearInspectPlayer = function() end
	local now = 100
	GetTime = function() return now end
	assert(T.TreeOf("target") == nil and asked == 1, "unknown player: inspected")
	assert(T.TreeOf("target") == nil and asked == 1, "not again within 1.5 s")
	ns.TalentTreeOf = function(configID) return configID == -1 and "Furor" or nil, 132347 end
	T.OnInspectReady(nil, "INSPECT_READY", "Player-1-0001")
	local tree = T.TreeOf("target")
	assert(tree and tree.name == "Furor" and tree.icon == 132347 and asked == 1, "kept after the inspection")
	now = 200
	InCombatLockdown = function() return true end
	T.TreeOf("focus")
	assert(asked == 1, "no inspection in combat")
	UnitIsUnit, UnitGUID, CanInspect, NotifyInspect, InCombatLockdown, GetTime, ns.TalentTreeOf, InspectFrame = unpack(saved, 1, 8)
	T.trees = {}
	print("talent tree tooltip OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local oldHook, oldTooltip = hooksecurefunc, GameTooltip
	local oldManager, oldInfo = StatusTrackingBarManager, StatusTrackingBarInfo
	local oldOption = visuals.db.unitBars
	local unitAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
	local xpAtlas, restedAtlas = "UI-HUD-ExperienceBar-Fill-Experience", "UI-HUD-ExperienceBar-Fill-Rested"
	local repAtlas = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green"
	local tooltipFile = [[Interface\TargetingFrame\UI-TargetingFrame-BarFill]]

	local function MakeBar(atlas, file)
		local bar = { atlas = atlas, file = file, color = { 1, 1, 1, 0.85 }, desaturation = 0.25 }
		function bar:GetStatusBarTexture()
			return { GetAtlas = function() return self.atlas end, GetTexture = function() return self.file end }
		end
		function bar:SetStatusBarTexture(asset)
			self.atlas, self.file = nil, nil
			if asset == tooltipFile then self.file = asset else self.atlas = asset end
			return true
		end
		function bar:GetStatusBarColor() return unpack(self.color) end
		function bar:SetStatusBarColor(...) self.color = { ... } end
		function bar:GetStatusBarDesaturation() return self.desaturation end
		function bar:SetStatusBarDesaturation(value) self.desaturation = value end
		return bar
	end

	local xp, rep, tooltip = MakeBar(xpAtlas), MakeBar(nil), MakeBar(nil, tooltipFile)
	hooksecurefunc = function(frame, key, callback)
		local original = assert(frame[key])
		frame[key] = function(self, asset)
			local result = original(self, asset)
			callback(self, asset)
			return result
		end
	end
	GameTooltip = { StatusBar = tooltip }
	StatusTrackingBarManager = { barContainers = { { bars = { { StatusBar = xp }, { StatusBar = rep } } } } }
	StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
	ns.SetOption("Visuals", "unitBars", false)
	uv(visuals.OnLogin, "HookTrackingBars")()
	assert(xp.atlas == xpAtlas and tooltip.file == tooltipFile, "loading with the option off leaves default textures")
	ns.SetOption("Visuals", "unitBars", true)
	assert(xp.atlas == unitAtlas and xp.color[1] == 0.58 and xp.color[4] == 0.85
		and xp.desaturation == 1 and tooltip.atlas == unitAtlas and tooltip.desaturation == 1, "enabling styles visible bars immediately")
	xp:SetStatusBarTexture(restedAtlas)
	rep:SetStatusBarTexture(repAtlas)
	assert(xp.atlas == unitAtlas and xp.color[3] == 0.88 and rep.atlas == unitAtlas and rep.color[2] == 0.6,
		"native rested and reputation texture updates keep the style and change the tint")
	ns.SetOption("Visuals", "unitBars", false)
	assert(xp.atlas == restedAtlas and rep.atlas == repAtlas and tooltip.file == tooltipFile
		and xp.color[1] == 1 and xp.desaturation == 0.25 and tooltip.desaturation == 0.25, "disabling restores current native appearances")
	xp:SetStatusBarTexture(xpAtlas)
	assert(xp.atlas == xpAtlas, "the hook allows native textures while off")
	ns.SetOption("Visuals", "unitBars", true)
	assert(xp.atlas == unitAtlas and xp.color[1] == 0.58, "re-enabling uses the current native XP state")
	ns.SetOption("Visuals", "unitBars", false)
	local tracked = uv(uv(visuals.OnLogin, "HookTrackingBars"), "trackingBars")
	tracked[xp], tracked[rep] = nil, nil
	hooksecurefunc, GameTooltip, StatusTrackingBarManager, StatusTrackingBarInfo = oldHook, oldTooltip, oldManager, oldInfo
	visuals.db.unitBars = oldOption
	print("unit bar textures OK")
end)()

-- Recipes still to come, per profession, like "spells at the trainer": a visit to a profession trainer keeps
-- their whole list (also what needs more skill); the filter menu of the profession window switches them on below
-- the learned recipes in the window's own list, grouped by required skill.
-- Recipes that come from drops or merchants are not in a trainer's list and do not appear.
local _, ns = ...
local L = ns.L

local ProfessionPlan = ns:NewModule("ProfessionPlan", {
	title = L.PROFPLAN_TITLE,
	order = 6.1,
	defaults = {
		upcoming = false, -- the unlearned section in the profession window (switched in its filter menu)
		preview = true,   -- recipes: Ctrl + click tries the product on, green arrow and rating for better equipment
		efficientSkillUps = false,
		extraTabs = true,
	},
	charDefaults = {
		trainers = {}, -- profession name -> { { name, icon, skill, level, cost, known }, ... }
	},
})

local TRAINER_FILTERS = { "available", "unavailable", "used" }

local function Plain(value)
	return not ns.Secret(value) and value or nil
end

---------------------------------------------------------------------------
-- Skill-up filter
---------------------------------------------------------------------------
local SKILL_UP_GROUP = -1
local SKILL_UP_LIMIT = 3

local function SkillUpFilterOn()
	return C_TradeSkillUI and C_TradeSkillUI.GetOnlyShowSkillUpRecipes
		and C_TradeSkillUI.GetOnlyShowSkillUpRecipes() and Professions.InLocalCraftingMode()
end

local function ReagentCosts(schematic, priceFor)
	local units, cost, complete = 0, 0, true
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local quantity = slot.quantityRequired
		if slot.required and quantity > 0 then
			units = units + quantity
			local best
			for _, reagent in ipairs(slot.reagents) do
				local price = reagent.itemID and priceFor(reagent.itemID)
				if price and (not best or price < best) then
					best = price
				end
			end
			if best then
				cost = cost + best * quantity
			else
				complete = false
			end
		end
	end
	return units, complete and cost or nil
end

local function BetterSkillUp(a, b)
	if a.score ~= b.score then
		if not a.score or not b.score then
			return a.score ~= nil
		end
		return a.score < b.score
	end
	if a.unitsPerPoint ~= b.unitsPerPoint then
		return a.unitsPerPoint < b.unitsPerPoint
	end
	return a.recipeInfo.recipeID < b.recipeInfo.recipeID
end

local function SkillUpScan(provider, remaining)
	-- Blizzard exposes difficulty bands. Use approximate odds for yellow and green.
	local difficulty = Enum.TradeskillRelativeDifficulty
	local odds = { [difficulty.Optimal] = 1, [difficulty.Medium] = 0.75, [difficulty.Easy] = 0.25 }
	local seen, recipes, prices, rows = {}, {}, {}, {}
	local auction = ns:GetModule("Auction")
	local function PriceFor(itemID)
		if prices[itemID] == nil then
			prices[itemID] = auction.ReagentPrice(itemID) or false
		end
		return prices[itemID]
	end
	for _, node in provider:EnumerateEntireRange() do
		local base = node:GetData().recipeInfo
		if base and base.learned and not base.favoritesInstance and not seen[base.recipeID] then
			seen[base.recipeID] = true
			recipes[#recipes + 1] = base
		end
	end
	local function Scan(index)
		local base = recipes[index]
		local ranked = base.nextRecipeID or base.previousRecipeID
		local recipe = ranked and Professions.GetHighestLearnedRecipe(base) or base
		local chance = odds[recipe.relativeDifficulty]
		if not chance or not recipe.canSkillUp or recipe.craftable == false or recipe.disabled
			or recipe.isRecraft or recipe.isGatheringRecipe then
			return
		end
		local schematic = C_TradeSkillUI.GetRecipeSchematic(recipe.recipeID, false)
		if not (schematic and schematic.reagentSlotSchematics) then
			return
		end
		local units, cost = ReagentCosts(schematic, PriceFor)
		local points = chance * math.min(remaining, math.max(1, recipe.numSkillUps or 1))
		local unitsPerPoint = units / points
		local row = {
			recipeInfo = base, units = units, cost = cost,
			unitsPerPoint = unitsPerPoint,
			-- Fewer materials can offset a higher price, while cost remains the main factor.
			score = cost and cost / points * math.sqrt(math.max(1, unitsPerPoint)),
		}
		local position = #rows + 1
		while position > 1 and BetterSkillUp(row, rows[position - 1]) do
			position = position - 1
		end
		if position <= SKILL_UP_LIMIT then
			table.insert(rows, position, row)
			rows[SKILL_UP_LIMIT + 1] = nil
		end
	end
	return #recipes, Scan, rows
end

local function AddSkillUpRows(provider, remaining, rows)
	local root = provider:GetRootNode()
	local originals = {}
	local nodes = provider:GetChildrenNodes()
	for i = #nodes, 1, -1 do
		originals[i] = root:Remove(nodes[i], true)
	end
	local top = provider:Insert({ fpPlan = "title", group = SKILL_UP_GROUP, dividerHeight = 24, text = L.PROFPLAN_EFFICIENT })
	if #rows == 0 then
		top:Insert({ fpPlan = "skillNote", dividerHeight = 36, text = remaining <= 0 and L.PROFPLAN_SKILL_CAP or L.PROFPLAN_SKILL_NONE })
	else
		for _, row in ipairs(rows) do
			top:Insert({ recipeInfo = row.recipeInfo, fpSkillUp = row })
		end
	end
	return top, originals
end

---------------------------------------------------------------------------
-- Recipe preview: what a recipe makes can be tried on with Ctrl + click (trainer, profession window, the list of
-- recipes to come), and better equipment gets the arrow and rating of the bags.
---------------------------------------------------------------------------
function ns.RecipePreviewOn()
	return ProfessionPlan.db and ProfessionPlan.db.preview and true or false
end

-- An item link usable for the preview, or nil.
function ns.RecipeLink(link)
	return type(link) == "string" and not ns.Secret(link) and link:find("item:", 1, true) and link or nil
end

local outputLinks = {}

local function RecipeOutputLink(recipeID)
	if not recipeID then
		return
	end
	local link = outputLinks[recipeID]
	if not link then
		local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
		local itemID = schematic and ns.Number(schematic.outputItemID)
		if itemID and itemID > 0 then
			link = "item:" .. itemID
			outputLinks[recipeID] = link
		end
	end
	return link
end

-- Old trainer lists have only the name. Check the spell's profession before using a name match.
local function RecipeID(entry, profession)
	if entry.recipeID then
		return entry.recipeID
	end
	local spellID = C_Spell.GetSpellIDForSpellIdentifier and ns.Number(C_Spell.GetSpellIDForSpellIdentifier(entry.name))
	local info = spellID and C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(spellID)
	if info and (Plain(info.professionName) == profession or Plain(info.parentProfessionName) == profession) then
		return spellID
	end
end

local function UpcomingRecipeLink(data)
	local entry = data.entry
	data.fpRecipeID = data.fpRecipeID or RecipeID(entry, data.profession)
	return RecipeOutputLink(data.fpRecipeID) or ns.RecipeLink(entry.link), data.fpRecipeID
end

local function PreviewLink(frame)
	if frame.fpData then
		return UpcomingRecipeLink(frame.fpData)
	end
	return RecipeOutputLink(frame.fpPreviewRecipeID)
end

-- Ctrl + click (the game's "try on" modifier): shows the item in the dressing room. true when it did.
function ns.TryOnRecipe(link)
	if not (ns.RecipePreviewOn() and ns.RecipeLink(link) and IsModifiedClick("DRESSUP")) then
		return false
	end
	local dressUp = DressUpItemLink or DressUpLink
	return dressUp and dressUp(link) and true or (dressUp ~= nil)
end

local function CreateRecipeArrow(frame, label)
	local arrow = frame:CreateTexture(nil, "OVERLAY")
	arrow:SetAtlas("bags-greenarrow", true)
	arrow:SetScale(0.8)
	arrow:SetPoint("RIGHT", label, "LEFT", -1, 0)
	return arrow
end

local previewQueue, previewTicker = {}, nil
local PREVIEW_BUDGET = 0.25

local function UpdateRecipeArrows(ticker)
	local start = debugprofilestop()
	repeat
		local frame, label = next(previewQueue)
		if not frame then
			ticker:Cancel()
			previewTicker = nil
			return
		end
		previewQueue[frame] = nil
		if ns.RecipePreviewOn() and frame:IsVisible() then
			local link = PreviewLink(frame)
			local state = link and ns.RecipeUpgradeState and ns.RecipeUpgradeState(link)
			if state then
				local arrow = frame.fpArrow or CreateRecipeArrow(frame, label)
				frame.fpArrow = arrow
				arrow:SetDesaturated(state == "later")
				arrow:Show()
			elseif frame.fpArrow then
				frame.fpArrow:Hide()
			end
		end
	until debugprofilestop() - start >= PREVIEW_BUDGET
end

local function QueueRecipeArrow(frame, label)
	local source = ns.RecipePreviewOn() and (frame.fpData or frame.fpPreviewRecipeID) or nil
	if frame.fpArrow and source ~= frame.fpArrowSource then
		frame.fpArrow:Hide()
	end
	frame.fpArrowSource = source
	previewQueue[frame] = source and label or nil
	if source then
		previewTicker = previewTicker or ns.NewTicker("ProfessionPlan: recipe arrows", 0, UpdateRecipeArrows)
	end
end

-- Reads the whole list of a profession trainer (all filters on for the moment), per profession.
local function ScanTrainer()
	local trainerType = C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType()
	if trainerType ~= Enum.TrainerType.Tradeskills then
		return
	end
	local saved = {}
	for _, filter in ipairs(TRAINER_FILTERS) do
		saved[filter] = GetTrainerServiceTypeFilter(filter)
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, true)
		end
	end
	local found = {}
	for index = 1, GetNumTrainerServices() do
		local name, serviceType, icon = GetTrainerServiceInfo(index)
		if Plain(name) and serviceType ~= "header" then
			local skillName, skillRank = GetTrainerServiceSkillReq(index)
			local line = GetTrainerServiceSkillLine and Plain(GetTrainerServiceSkillLine(index))
			local profession = line or Plain(skillName)
			if profession then
				local tooltip = C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(index)
				local serviceID = tooltip and ns.Number(tooltip.id)
				local recipeID, link = serviceID, GetTrainerServiceItemLink and ns.RecipeLink(GetTrainerServiceItemLink(index))
				if serviceID and Plain(tooltip.type) == Enum.TooltipDataType.Item then
					recipeID, link = nil, link or ("item:" .. serviceID)
				end
				found[profession] = found[profession] or {}
				table.insert(found[profession], {
					name = name, icon = icon, skill = Plain(skillRank) or 0,
					level = GetTrainerServiceLevelReq and Plain(GetTrainerServiceLevelReq(index)) or 0,
					cost = GetTrainerServiceCost and Plain((GetTrainerServiceCost(index))) or 0,
					known = serviceType == "used" or nil,
						recipeID = recipeID, link = link,
				})
			end
		end
	end
	for _, filter in ipairs(TRAINER_FILTERS) do
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, false)
		end
	end
	for profession, list in pairs(found) do
		ProfessionPlan.cdb.trainers[profession] = list
	end
end

-- What is still to come: entries not known (by the trainer's mark or a learned recipe of that name), by skill
-- needed and name, each with whether skill and level allow it now.
function ProfessionPlan.Upcoming(list, knownNames, skill, level)
	local rows = {}
	for _, entry in ipairs(list or {}) do
		if not entry.known and not knownNames[entry.name] then
			local requiredSkill = entry.skill or 0
			rows[#rows + 1] = { entry = entry, skill = requiredSkill, now = requiredSkill <= skill and (entry.level or 0) <= level }
		end
	end
	table.sort(rows, function(a, b)
		if a.skill ~= b.skill then
			return a.skill < b.skill
		end
		return a.entry.name < b.entry.name
	end)
	return rows
end

local function AddTrainingLines(tooltip, entry)
	GameTooltip_AddNormalLine(tooltip, L.PROFPLAN_SKILL:format(entry.skill or 0))
	if (entry.level or 0) > 0 then
		GameTooltip_AddNormalLine(tooltip, L.PROFPLAN_LEVEL:format(entry.level))
	end
	if (entry.cost or 0) > 0 then
		GameTooltip_AddNormalLine(tooltip, GetMoneyString(entry.cost, true))
	end
end

local function ShowRecipeTooltip(owner, entry, info)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if info then
		if GameTooltip:ProcessInfo(info) then
			return
		end
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	end
	GameTooltip_SetTitle(GameTooltip, entry.name)
	AddTrainingLines(GameTooltip, entry)
	GameTooltip:Show()
end

local function PrepareRecipeTooltip(frame)
	local data = frame.fpData
	local entry = data.entry
	local link, recipeID = UpcomingRecipeLink(data)
	local value = link or recipeID
	if not value then
		ShowRecipeTooltip(frame, entry)
		return
	end
	local getterName = link and "GetHyperlink" or "GetSpellByID"
	local getter = C_TooltipInfo[getterName]
	local info = {
		-- Keep the getter so Blizzard can rebuild the tooltip when its data changes.
		getterName = getterName,
		getterArgs = { value },
		tooltipPostCall = function(tooltip)
			tooltip:AddLine(" ")
			AddTrainingLines(tooltip, entry)
		end,
	}
	-- Uncached items must be requested while the tooltip is open so it receives their data updates.
	if getter and (not link or C_Item.IsItemDataCachedByID(link)) then
		info.tooltipData = getter(value)
	end
	frame.fpTooltipTimer = ns.NewTimer("ProfessionPlan: recipe tooltip", 0, function()
		frame.fpTooltipTimer = nil
		if frame.fpData == data and frame:IsVisible() then
			ShowRecipeTooltip(frame, entry, info)
		end
	end)
end

local TOOLTIP_DELAY = 0.12

local function HideRecipeTooltip(frame)
	if frame.fpTooltipTimer then
		frame.fpTooltipTimer:Cancel()
		frame.fpTooltipTimer = nil
	end
	if GameTooltip:IsOwned(frame) then
		GameTooltip:Hide()
	end
end

local function StartRecipeTooltip(frame)
	if not frame.fpData or frame.fpTooltipTimer then
		return
	end
	frame.fpText:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
	frame.fpTooltipTimer = ns.NewTimer("ProfessionPlan: recipe tooltip data", TOOLTIP_DELAY, function()
		frame.fpTooltipTimer = nil
		if frame.fpData and frame:IsVisible() then
			PrepareRecipeTooltip(frame)
		end
	end)
end

-- Draws one of our elements on the plain frame Blizzard's list gives it; the same frames also serve the list's
-- own padding, which gets them back empty.
local Decorate = ns.Measured("ProfessionPlan: list row", function(frame, data)
	if not frame.fpText then
		frame.fpText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		frame.fpText:SetJustifyH("LEFT")
		frame.fpRight = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		frame.fpRight:SetPoint("RIGHT", -8, 0)
		frame.fpHighlight = frame:CreateTexture(nil, "HIGHLIGHT")
		frame.fpHighlight:SetAtlas("Professions_Recipe_Hover", true)
		frame.fpHighlight:SetPoint("CENTER", 0, -1)
		frame.fpHighlight:SetAlpha(0.5)
		frame:SetScript("OnEnter", StartRecipeTooltip)
		frame:SetScript("OnLeave", function(self)
			if self.fpRecipeColor then
				self.fpText:SetTextColor(self.fpRecipeColor:GetRGB())
			end
			HideRecipeTooltip(self)
		end)
		frame:SetScript("OnHide", HideRecipeTooltip)
		frame:SetScript("OnMouseUp", ns.Measured("ProfessionPlan: recipe preview", function(self, mouseButton)
			if self.fpData and mouseButton == "LeftButton" and ns.RecipePreviewOn() and IsModifiedClick("DRESSUP") then
				ns.TryOnRecipe(PreviewLink(self))
			end
		end))
	end
	local kind = data and data.fpPlan
	frame.fpPlanKind = kind
	local isRecipe = kind == "recipe"
	local right = isRecipe and data.right or nil
	if frame.fpData and frame.fpData ~= data then
		HideRecipeTooltip(frame)
	end
	frame.fpData = isRecipe and data or nil
	frame.fpRecipeColor = isRecipe and (data.now and PROFESSION_RECIPE_COLOR or DISABLED_FONT_COLOR) or nil
	frame:EnableMouse(isRecipe)
	frame.fpHighlight:SetShown(isRecipe)
	frame.fpText:SetShown(kind ~= nil)
	frame.fpRight:SetShown(right ~= nil)
	QueueRecipeArrow(frame, frame.fpText)
	if not kind then
		return
	end
	frame.fpText:SetFontObject(isRecipe and "GameFontHighlight_NoShadow" or "GameFontHighlightSmall")
	frame.fpText:ClearAllPoints()
	-- The learned recipe label starts after the 26 px skill-up region at x = -9 plus a 4 px gap.
	frame.fpText:SetPoint("LEFT", isRecipe and 21 or (kind == "title" and 4 or 10), 0)
	frame.fpText:SetPoint("RIGHT", right and frame.fpRight or frame, right and "LEFT" or "RIGHT", -4, 0)
	frame.fpText:SetWordWrap(kind == "skillNote" or kind == "note")
	if isRecipe then
		frame.fpText:SetText(data.entry.name)
		frame.fpText:SetTextColor(frame.fpRecipeColor:GetRGB())
		frame.fpRight:SetText(right or "")
		local statusColor = data.now and GREEN_FONT_COLOR or DISABLED_FONT_COLOR
		frame.fpRight:SetTextColor(statusColor:GetRGB())
	else
		frame.fpText:SetText(data.text or "")
		local color = kind == "title" and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR
		frame.fpText:SetTextColor(color:GetRGB())
	end
end)

local injected = {}
local pendingScan, refreshOnShow

local function CraftingList()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList, page
end

-- At the root Blizzard sorts by group and then by category. Give the divider its own group.
local PLAN_GROUP = 1000

local function AddUpcomingRows(provider, profession, skill, known, collapses)
	local divider = provider:Insert({ isDivider = true, dividerHeight = 30, group = PLAN_GROUP })
	local nodes = { divider }
	local list = ProfessionPlan.cdb.trainers[profession]
	local level = ns.Number(UnitLevel("player"), 1)
	local rows = ProfessionPlan.Upcoming(list, known, skill, level)
	if #rows == 0 then
		local note = list and L.PROFPLAN_ALL_KNOWN or L.PROFPLAN_VISIT_TRAINER:format(profession)
		divider:Insert({ fpPlan = "note", dividerHeight = 36, text = note })
		return nodes
	end
	local category, lastSkill
	for _, row in ipairs(rows) do
		if row.skill ~= lastSkill then
			if category then
				category:Insert({ bottomPadding = true })
			end
			local id = "ForeverPlus:Upcoming:" .. profession .. ":" .. row.skill
			category = provider:Insert({ group = PLAN_GROUP + 1, categoryInfo = {
				categoryID = id, name = L.PROFPLAN_SKILL:format(row.skill), uiOrder = row.skill,
			} })
			if collapses and collapses[id] then
				category:SetCollapsed(true)
			end
			category:Insert({ topPadding = true })
			nodes[#nodes + 1] = category
			lastSkill = row.skill
		end
		local entry = row.entry
		category:Insert({ fpPlan = "recipe", dividerHeight = 20, entry = entry, profession = profession, now = row.now,
			right = row.now and L.PROFPLAN_NOW or ((entry.level or 0) > level and L.PROFPLAN_LEVEL:format(entry.level) or nil) })
	end
	category:Insert({ bottomPadding = true })
	return nodes
end

-- Insert/Remove normally redraw the attached ScrollBox after every mutation.
local function BatchListChanges(box, change)
	local view = box.GetView and box:GetView()
	if not (view and view.DetachDataProviderCallbacks and view.AttachDataProviderCallbacks and view.DataProviderContentsChanged) then
		change()
		return
	end
	view:DetachDataProviderCallbacks()
	local ok, message = pcall(change)
	view:AttachDataProviderCallbacks()
	view:DataProviderContentsChanged()
	if not ok then
		error(message, 0)
	end
end

local function FindSelectedRecipe(provider, selection)
	if provider.FindElementDataByPredicate and selection.IsElementDataSelected then
		return provider:FindElementDataByPredicate(function(node)
			return selection:IsElementDataSelected(node)
		end, false)
	end
	return selection:GetFirstSelectedElementData()
end

local function UpdateList(recipeList, provider, replacesRecipes, change, fallbackRecipe)
	local selection = replacesRecipes and recipeList.selectionBehavior
	local selected = selection and FindSelectedRecipe(provider, selection)
	local selectedRecipe = selected and selected:GetData().recipeInfo
	if selected then
		selection:DeselectElementData(selected)
	end
	local box = recipeList.ScrollBox
	BatchListChanges(box, change)
	if recipeList.NoResultsText then
		recipeList.NoResultsText:SetShown(#provider:GetChildrenNodes() == 0)
	end
	if selectedRecipe and recipeList:SelectRecipe(selectedRecipe, false) then
		return
	end
	if fallbackRecipe and selection then
		local current = injected
		-- Selecting a different recipe can rebuild the schematic. Give the list its own frame.
		ns.After("ProfessionPlan: select recommended recipe", 0, function()
			if injected == current and box:GetDataProvider() == provider and (not box.IsVisible or box:IsVisible())
				and not FindSelectedRecipe(provider, selection) then
				recipeList:SelectRecipe(fallbackRecipe, false)
			end
		end)
	end
end

local function RestoreList(recipeList, provider)
	UpdateList(recipeList, provider, injected.skillUps, function()
		for _, node in ipairs(injected.upcoming or {}) do
			provider:Remove(node)
		end
		if injected.skillUps then
			provider:Remove(injected.skillUps)
			local root = provider:GetRootNode()
			for _, node in ipairs(injected.originals) do
				root:InsertNode(node)
			end
		end
	end)
end

local function TrainerRecipeNames(profession)
	local names = {}
	for _, entry in ipairs(ProfessionPlan.cdb.trainers[profession] or {}) do
		if not entry.known then
			names[entry.name] = true
		end
	end
	return names
end

local function CancelScan()
	if pendingScan then
		pendingScan:Cancel()
		pendingScan = nil
		return true
	end
end

-- Blizzard builds a new provider on filter changes. Only the current list can receive scan results.
local function Inject()
	CancelScan()
	refreshOnShow = false
	local recipeList, page = CraftingList()
	local box = recipeList and recipeList.ScrollBox
	local provider = box and box.GetDataProvider and box:GetDataProvider()
	if provider and injected.provider == provider and (injected.skillUps or injected.upcoming) then
		RestoreList(recipeList, provider)
	end
	injected = { provider = provider }
	if not provider then
		return
	end
	local search = recipeList.SearchBox
	local upcoming = ProfessionPlan.db.upcoming and not (search and search.HasText and search:HasText())
	local filterOn = ProfessionPlan.db.efficientSkillUps and SkillUpFilterOn()
	if not (upcoming or filterOn) then
		return
	end
	if box.IsVisible and not box:IsVisible() then
		refreshOnShow = true
		return
	end
	local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	if not info then
		return
	end
	local profession = upcoming and Plain(info.professionName)
	local skill = ns.Number(info.skillLevel)
	local maxSkill = filterOn and ns.Number(info.maxSkillLevel)
	local remaining = skill and maxSkill and maxSkill > 0 and maxSkill - skill
	if not (profession or remaining) then
		return
	end
	local names = profession and TrainerRecipeNames(profession)
	local ids = names and next(names) and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}
	local known, rows = {}, {}
	local recipeCount, scanRecipe = 0, nil
	if remaining and remaining > 0 then
		recipeCount, scanRecipe, rows = SkillUpScan(provider, remaining)
	end
	local function ApplyRows()
		pendingScan = nil
		if box:GetDataProvider() ~= provider then
			return
		end
		UpdateList(recipeList, provider, remaining, function()
			if remaining then
				injected.skillUps, injected.originals = AddSkillUpRows(provider, remaining, rows)
			end
			if profession then
				injected.upcoming = AddUpcomingRows(provider, profession, skill or 0, known, page.GetCollapses and page:GetCollapses())
			end
		end, rows[1] and rows[1].recipeInfo)
	end
	if recipeCount + #ids == 0 then
		ApplyRows()
		return
	end
	pendingScan = ns.RunSliced("ProfessionPlan: scan recipes", recipeCount + #ids, function(index)
		if index <= recipeCount then
			scanRecipe(index)
			return
		end
		local recipe = C_TradeSkillUI.GetRecipeInfo(ids[index - recipeCount])
		local name = recipe and recipe.learned and Plain(recipe.name)
		if name and names[name] then
			known[name] = true
		end
	end, ns.Measured("ProfessionPlan: apply rows", ApplyRows))
end
ProfessionPlan.Inject = Inject

local function OnAcquired(_, frame, node)
	local data = node and node.GetData and node:GetData()
	if (frame.fpPlanKind or (data and data.fpPlan)) and not (data and data.isDivider) and frame:GetObjectType() == "Frame" then
		Decorate(frame, data)
	end
end

function ProfessionPlan.HookList()
	local recipeList = CraftingList()
	local box = recipeList and recipeList.ScrollBox
	if not box or ProfessionPlan.listHooked then
		return
	end
	ProfessionPlan.listHooked = true
	-- Blizzard builds a new list on every change (learned recipe, filter, skill): ours is added to each.
	hooksecurefunc(box, "SetDataProvider", ns.Measured("ProfessionPlan: list", Inject))
	ScrollUtil.AddAcquiredFrameCallback(box, OnAcquired, ProfessionPlan)
	box:HookScript("OnHide", function()
		if CancelScan() then
			refreshOnShow = true
		end
	end)
	box:HookScript("OnShow", function()
		if refreshOnShow then
			Inject()
		end
	end)
	Inject()
end

-- The rows of the profession window's recipe list: arrow at the name for better equipment, Ctrl + click tries the
-- product on (Blizzard's own Ctrl + click only links the recipe).
local function OnSkillUpRowEnter(button)
	local node = button.GetElementData and button:GetElementData()
	local row = node and node:GetData().fpSkillUp
	if not row then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, button.Label:GetText())
	if row.cost then
		GameTooltip_AddNormalLine(GameTooltip, L.PROFPLAN_SKILL_COST:format(GetMoneyString(math.floor(row.cost + 0.5), true)))
	else
		GameTooltip_AddNormalLine(GameTooltip, L.PROFPLAN_SKILL_NO_PRICE)
	end
	GameTooltip_AddNormalLine(GameTooltip, L.PROFPLAN_SKILL_MATERIALS:format(row.units, row.unitsPerPoint))
	GameTooltip:Show()
end

local function OnRecipeRowInit(button, node)
	local data = node and node.GetData and node:GetData()
	local recipe = data and data.recipeInfo
	button.fpPreviewRecipeID = recipe and Plain(recipe.recipeID) or nil
	if ns.RecipePreviewOn() and not button.fpPreviewHooked then
		button.fpPreviewHooked = true
		button:HookScript("OnMouseUp", function(self, mouseButton)
			if mouseButton == "LeftButton" and ns.RecipePreviewOn() and IsModifiedClick("DRESSUP") then
				ns.TryOnRecipe(PreviewLink(self))
			end
		end)
	end
	QueueRecipeArrow(button, button.Label)
end

function ProfessionPlan.HookRecipeRows()
	local mixin = ProfessionsRecipeListRecipeMixin
	if mixin and mixin.Init and not ProfessionPlan.rowsHooked then
		ProfessionPlan.rowsHooked = true
		hooksecurefunc(mixin, "Init", ns.Measured("ProfessionPlan: recipe row", OnRecipeRowInit))
		hooksecurefunc(mixin, "OnEnter", ns.Measured("ProfessionPlan: skill-up tooltip", OnSkillUpRowEnter))
	end
end

---------------------------------------------------------------------------
-- Shortcuts for learned profession spells outside the built-in tabs.
---------------------------------------------------------------------------
local MINING, SMELTING = 186, 2656
local extraTabs = {}
local professionFrame

local function MissingProfessionSpells(nativeSpells, nativeNames, bank)
	-- The three gathering searches may be available before the tracking menu has refreshed.
	local tracking = { [2383] = true, [2580] = true, [43308] = true }
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if info then
			tracking[info.name] = true
			if info.spellID then
				tracking[info.spellID] = true
			end
		end
	end
	local crafting, actions, seen = {}, {}, {}
	local function Add(spell, skillLine, seenNames)
		local id, name = spell.spellID, spell.name
		if tracking[id] or tracking[spell.actionID] or tracking[name] then
			return
		end
		-- Some abilities (such as Fishing) share a display name with their profession tab despite having different IDs.
		if seen[id] or seenNames[name] or nativeNames[skillLine] == name then
			return
		end
		-- A tab labeled Mining can already cast Smelting. Give it a shortcut under its own spell name as well.
		if nativeSpells[id] and id ~= SMELTING then
			return
		end
		seen[id] = true
		seenNames[name] = true
		local opensCrafting = C_TradeSkillUI.CanTradeSkillShowCraftingUI(id)
		local list = opensCrafting and crafting or actions
		list[#list + 1] = { spell = spell, skillLine = skillLine, opensCrafting = opensCrafting }
	end
	local indices = { GetProfessions() }
	for i = 1, 7 do
		if indices[i] then
			local _, _, _, _, count, offset, skillLine = GetProfessionInfo(indices[i])
			local seenNames = {}
			if count and offset then
				for slot = offset + 1, offset + count do
					local spell = C_SpellBook.GetSpellBookItemInfo(slot, bank)
					if spell and spell.spellID and spell.itemType == Enum.SpellBookItemType.Spell and not spell.isPassive then
						Add(spell, skillLine, seenNames)
					end
				end
			end
			-- Also handle clients that know Smelting but don't list it in the Mining spell slots.
			if skillLine == MINING and not seen[SMELTING] and C_SpellBook.IsSpellKnown(SMELTING, bank) then
				local smelting = C_Spell.GetSpellInfo(SMELTING)
				if smelting then
					Add(smelting, skillLine, seenNames)
				end
			end
		end
	end
	for _, action in ipairs(actions) do
		crafting[#crafting + 1] = action
	end
	return crafting
end

local function CreateProfessionTab(frame)
	-- The Blizzard action template casts on hardware clicks outside combat without protecting the profession window.
	local tab = CreateFrame("Button", nil, frame, "LargeSideTabButtonTemplate, InsecureActionButtonTemplate")
	tab:SetFillToInterior(true)
	tab.smartNavigationIgnored = true
	tab:RegisterForClicks("LeftButtonUp")
	tab:SetAttribute("useOnKeyDown", false)
	tab.GetTooltipTextSetupFunction = function(button)
		return function(tooltip)
			return tooltip:SetSpellByID(button:GetAttribute("spell"))
		end
	end
	tab:SetScript("PreClick", ns.Measured("ProfessionPlan: profession shortcut", function(button)
		if InCombatLockdown() then
			return
		end
		local alreadyOpen = button.opensCrafting and Professions.InLocalCraftingMode()
			and Professions.IsSelectedProfession(button.skillLine)
		button:SetAttribute("type", not alreadyOpen and "spell" or nil)
		if alreadyOpen then
			EventRegistry:TriggerEvent("Professions.ShowSelectedCraftingPage")
		end
	end))
	return tab
end

local function RefreshProfessionTabs()
	local frame = professionFrame
	local count = 0
	if ProfessionPlan.db.extraTabs and frame:IsShown() then
		local overview = frame.ProfessionsOverviewTab
		local bank = Enum.SpellBookSpellBank.Player
		local nativeSpells, nativeNames = {}, {}
		local nativeCount = 0
		for _, tab in ipairs(frame.rightProfessionTabs) do
			if tab:IsShown() and tab.skillLine and tab.spellOffsetIndex then
				nativeCount = nativeCount + 1
				nativeNames[tab.skillLine] = tab.tooltipText
				local spell = C_SpellBook.GetSpellBookItemInfo(tab.spellOffsetIndex + 1, bank)
				if spell and spell.spellID then
					nativeSpells[spell.spellID] = true
				end
			end
		end
		local activeSkill = not frame.BookPage:IsShown() and Professions.InLocalCraftingMode() and Professions.GetEffectiveSkillLineID()
		local width, height = overview:GetSize()
		local _, _, _, _, topOffset = overview:GetPoint()
		local step = height + 2
		local rows = math.max(nativeCount + 1, math.floor((frame:GetHeight() + topOffset + 2) / step))
		for i, entry in ipairs(MissingProfessionSpells(nativeSpells, nativeNames, bank)) do
			local tab = extraTabs[i] or CreateProfessionTab(frame)
			extraTabs[i] = tab
			local spell = entry.spell
			tab.Icon:SetTexture(spell.iconID)
			tab.tooltipText = spell.name
			tab.skillLine, tab.opensCrafting = entry.skillLine, entry.opensCrafting
			tab:SetAttribute("spell", spell.spellID)
			local selected = entry.opensCrafting and entry.skillLine == activeSkill and not nativeNames[activeSkill]
			tab:SetChecked(selected)
			if selected then
				activeSkill = nil
			end
			local index = nativeCount + i
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", overview, "TOPLEFT", math.floor(index / rows) * (width + 2), -(index % rows) * step)
			tab:Show()
			count = i
		end
	end
	for i = count + 1, #extraTabs do
		extraTabs[i]:Hide()
	end
end

function ProfessionPlan:OnLogin()
	self:RegisterEvent("TRAINER_SHOW", function()
		ns.After("ProfessionPlan: ScanTrainer", 0.3, ScanTrainer)
	end)
	-- The switch in the filter menu of the profession window (as the retail filter for unlearned recipes).
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", function(_, rootDescription)
			rootDescription:CreateDivider()
			local skillUps = ns.CreateOptionCheckbox(rootDescription, L.PROFPLAN_EFFICIENT, "ProfessionPlan", "efficientSkillUps",
				L.PROFPLAN_EFFICIENT_DESC)
			skillUps:SetEnabled(SkillUpFilterOn)
			ns.CreateOptionCheckbox(rootDescription, L.PROFPLAN_FILTER, "ProfessionPlan", "upcoming", L.PROFPLAN_FILTER_DESC)
		end)
	end
	ns.OnAddOnLoaded("Blizzard_Professions", function()
		ProfessionPlan.HookRecipeRows()
		ProfessionPlan.HookList()
		local frame = ProfessionsFrame
		if frame and type(frame.RefreshRightTabs) == "function" and frame.ProfessionsOverviewTab then
			professionFrame = frame
			local refresh = ns.Measured("ProfessionPlan: profession tabs", RefreshProfessionTabs)
			hooksecurefunc(frame, "RefreshRightTabs", refresh)
			hooksecurefunc(frame, "SelectBookPage", refresh)
			self:RegisterEvent("SPELLS_CHANGED", refresh)
			self:RegisterEvent("MINIMAP_UPDATE_TRACKING", refresh)
			refresh()
		end
	end)
end

function ProfessionPlan:OnOptionChanged(key)
	if key == "extraTabs" then
		if professionFrame then
			RefreshProfessionTabs()
		end
	else
		Inject()
	end
end

ProfessionPlan.options = {
	{ key = "extraTabs", type = "toggle", name = L.PROFPLAN_TABS, desc = L.PROFPLAN_TABS_DESC, new = true },
	{ key = "upcoming", type = "toggle", name = L.PROFPLAN_FILTER, desc = L.PROFPLAN_FILTER_DESC, new = true },
	{ key = "efficientSkillUps", type = "toggle", name = L.PROFPLAN_EFFICIENT, desc = L.PROFPLAN_EFFICIENT_DESC, new = true },
	{ key = "preview", type = "toggle", name = L.PROFPLAN_PREVIEW, desc = L.PROFPLAN_PREVIEW_DESC, new = true },
}

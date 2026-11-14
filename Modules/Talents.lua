-- Talents: spells by level, and a talent planner on Blizzard's talent window: plan builds, import
-- (into the plan) and export them in Blizzard's loadout string format.
local _, ns = ...
local L = ns.L

local Talents = ns:NewModule("Talents", {
	title = L.TALENTS_TITLE,
	order = 8.5,
	defaults = {
		enabled = true,
		planner = true,
		unspentBadge = true,
		planNext = true,
		-- "classFile:specID" -> { { id =, name =, ranks = { [nodeID] = planned rank }, order = { nodeID, … } }, … }:
		-- the plans by name; order holds the points not learned yet, one talent per point, in the order to learn
		-- them. Before that: plans (one per key), planOrder and templates (per class), taken over by BuildList.
		builds = {},
		buildSeq = 0, -- the id of the plan added last
		trainer = {}, -- classFile -> { { name, rank, icon, level, line }, ... } from the class trainer
		petTrainer = {}, -- classFile -> { { name, rank, icon, level, known }, ... } from the pet trainer (hunters)
	},
	charDefaults = {
		seenSpells = {}, -- learnable spells already shown to the player
		activeBuild = {}, -- "classFile:specID" -> id of the plan this character works with
	},
})

local _, playerClass = UnitClass("player")

---------------------------------------------------------------------------
-- Trainer spells: what the game lists per level and the spell book, plus the
-- class trainer's list (stored at each visit), which also holds the spells
-- of later levels.
---------------------------------------------------------------------------
local function IsKnown(spellID)
	return C_SpellBook.IsSpellKnown(spellID) or (IsPlayerSpell and IsPlayerSpell(spellID))
end

local function SpellKey(name, rank)
	return (name or "") .. "|" .. (rank or "")
end

local function SpellBookLines()
	local lines = {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID and not info.isGuild then
			lines[line] = info
		end
	end
	return lines
end

local function TrainerList()
	local lists = Talents.db.trainer
	lists[playerClass] = lists[playerClass] or {}
	return lists[playerClass]
end

-- Reads the whole service list of a class trainer, all filters switched on.
local function PetTrainerList()
	local lists = Talents.db.petTrainer
	lists[playerClass] = lists[playerClass] or {}
	return lists[playerClass]
end

local TRAINER_FILTERS = { "available", "unavailable", "used" }

local function ScanTrainer()
	local trainerType = C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType()
	if trainerType == Enum.TrainerType.Tradeskills then
		return
	end
	local isPet = trainerType == Enum.TrainerType.Pet
	local classLines = {}
	for _, info in pairs(SpellBookLines()) do
		classLines[info.name] = true
	end
	local saved = {}
	for _, filter in ipairs(TRAINER_FILTERS) do
		saved[filter] = GetTrainerServiceTypeFilter(filter)
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, true)
		end
	end
	local list = isPet and PetTrainerList() or TrainerList()
	local found = {}
	for index = 1, GetNumTrainerServices() do
		local name, serviceType, icon, level, rank = GetTrainerServiceInfo(index)
		local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(index)
		if name and serviceType ~= "header" and level and level > 0 and (isPet or not line or classLines[line]) then
			found[#found + 1] = { name = name, rank = rank ~= "" and rank or nil, icon = icon, level = level, line = line,
				known = isPet and serviceType == "used" or nil }
		end
	end
	for _, filter in ipairs(TRAINER_FILTERS) do
		if not saved[filter] then
			SetTrainerServiceTypeFilter(filter, false)
		end
	end
	if #found > 0 then
		wipe(list)
		for i, entry in ipairs(found) do
			list[i] = entry
		end
	end
end

local function SortTrainerSpells(items)
	table.sort(items, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		elseif a.name ~= b.name then
			return a.name < b.name
		end
		return (a.rank or "") < (b.rank or "")
	end)
end

-- Only fill gaps in the client data. A native future slot already has its own
-- level, tooltip and trainer highlight, even if the current filters hide it.
local function CollectTrainerSpells(onDone)
	local bank = Enum.SpellBookSpellBank.Player
	local byID, byKey, lineByName, lineByLabel = {}, {}, {}, {}
	local slots, visibleLines = {}, {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID and not info.isGuild then
			if not info.shouldHide then
				lineByLabel[info.name] = line
			end
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				slots[#slots + 1] = slot
				visibleLines[#slots] = not info.shouldHide and line or false
			end
		end
	end

	local missing = {}
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	local function Scan(index)
		if index <= #slots then
			local item = C_SpellBook.GetSpellBookItemInfo(slots[index], bank)
			if item and item.spellID and item.name then
				byID[item.spellID] = true
				byKey[SpellKey(item.name, item.subName)] = true
				local line = visibleLines[index]
				if line and (not lineByName[item.name] or line < lineByName[item.name]) then
					lineByName[item.name] = line
				end
			end
			return
		end
		local level = index - #slots
		for _, spellID in ipairs(C_SpellBook.GetCurrentLevelSpells(level) or {}) do
			if not byID[spellID] then
				local name = C_Spell.GetSpellName(spellID)
				local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
				local key = SpellKey(name, rank)
				if name then
					if IsKnown(spellID) then
						byKey[key], missing[key] = true, nil
					elseif not byKey[key] and not missing[key] then
						missing[key] = { name = name, rank = rank ~= "" and rank or nil, level = level,
							icon = C_Spell.GetSpellTexture(spellID), spellID = spellID }
					end
				end
			end
		end
	end
	local function Finish()
		for _, entry in ipairs(TrainerList()) do
			local key = SpellKey(entry.name, entry.rank)
			if not byKey[key] then
				local fromAPI = missing[key]
				missing[key] = { name = entry.name, rank = entry.rank, level = entry.level, line = entry.line,
					icon = entry.icon or (fromAPI and fromAPI.icon), spellID = fromAPI and fromAPI.spellID }
			end
		end

		local byLine = {}
		for key, entry in pairs(missing) do
			local line = lineByLabel[entry.line] or lineByName[entry.name] or Enum.SpellBookSkillLineIndex.General
			entry.key = key
			byLine[line] = byLine[line] or {}
			tinsert(byLine[line], entry)
		end
		for _, items in pairs(byLine) do
			SortTrainerSpells(items)
		end
		onDone(byLine)
	end
	return ns.RunSliced("Talents: scan trainer spells", #slots + maxLevel, Scan, Finish)
end

local function CollectPetTrainerSpells()
	local items = {}
	if playerClass ~= "HUNTER" then
		return items
	end
	local present = {}
	for slot = 1, C_SpellBook.HasPetSpells() or 0 do
		local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Pet)
		if item and item.name then
			present[SpellKey(item.name, item.subName)] = true
		end
	end
	for _, entry in ipairs(PetTrainerList()) do
		local key = SpellKey(entry.name, entry.rank)
		if not (entry.known or present[key]) then
			items[#items + 1] = { name = entry.name, rank = entry.rank, level = entry.level,
				icon = entry.icon, key = "pet|" .. key, pet = true }
			present[key] = true
		end
	end
	SortTrainerSpells(items)
	return items
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
local function TalentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local ApplyPlan, ClearPlan, ImportPlan, ExportPlan, SavePlanTemplate, ApplyTemplate -- planner, defined below
local BuildList, ActiveBuild, ActivatePlan, NewPlan, RenamePlan, RemovePlan, RecommendPlan
-- Parses a loadout string into node purchases using Blizzard's own reader.
local function ParseBuild(frame, text)
	local stream = ExportUtil.MakeImportDataStream(text)
	local valid, version, specID = frame:ReadLoadoutHeader(stream)
	if not valid then
		return nil, L.TALENTS_ERROR_STRING
	end
	if version ~= C_Traits.GetLoadoutSerializationVersion() then
		return nil, L.TALENTS_ERROR_VERSION
	end
	if specID ~= PlayerUtil.GetCurrentSpecID() then
		return nil, L.TALENTS_ERROR_SPEC
	end
	local configID, treeID = frame:GetConfigID(), frame:GetTreeInfo().ID
	local content = frame:ReadLoadoutContent(stream, treeID)
	return frame:ConvertToImportLoadoutEntryInfo(configID, treeID, content), nil, configID, treeID
end

local PLAN_BUTTON_SIZE = 26

-- The plans by name (the active one marked), the standard distributions, and what can be done with a plan.
local function ShowBuildMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if Talents.db.planner then
			root:CreateTitle(L.TALENTS_BUILDS)
			for _, build in ipairs(BuildList()) do
				root:CreateRadio(("%s (%d)"):format(build.name, ns.TalentBuilds.Points(build)), function()
					return ActiveBuild() == build
				end, function()
					ActivatePlan(build.id)
				end)
			end
			local presets = ns.TalentPresets and ns.TalentPresets[playerClass]
			if presets and #presets > 0 then
				root:CreateTitle(L.TALENTS_TEMPLATE_STANDARD)
				for _, preset in ipairs(presets) do
					local name = GetLocale() == "deDE" and preset.de or preset.en
					root:CreateButton(("%s (%s)"):format(name, preset.points), function()
						ApplyTemplate(preset, name)
					end)
				end
			end
			root:CreateDivider()
			root:CreateButton(L.TALENTS_RECOMMEND, RecommendPlan)
			root:CreateButton(L.TALENTS_PLAN_NEW, NewPlan)
			root:CreateButton(L.TALENTS_PLAN_RENAME, RenamePlan)
			root:CreateButton(L.TALENTS_SAVE_TEMPLATE, SavePlanTemplate)
			root:CreateButton(L.TALENTS_PLAN_REMOVE, RemovePlan)
			root:CreateDivider()
			root:CreateButton(L.TALENTS_IMPORT_CODE, ImportPlan)
		end
		root:CreateButton(L.TALENTS_EXPORT_PLAN, ExportPlan)
	end)
end

---------------------------------------------------------------------------
-- Planner: right-click plans a rank (blue), Shift + right-click removes it.
-- Plans go up to the points of level 60 and are bought with "apply plan".
---------------------------------------------------------------------------
local PLAN_COLOR = CreateColor(0.3, 0.65, 1)
local FIRST_TALENT_LEVEL, PLAN_MAX_LEVEL = 10, 60
local PLAN_POINTS = PLAN_MAX_LEVEL - FIRST_TALENT_LEVEL + 1
local planBar

local function PlanKey()
	return ("%s:%s"):format(playerClass, PlayerUtil.GetCurrentSpecID() or 0)
end

-- The plans of this class and specialisation. What was stored before plans had names (the one plan with its
-- order, the own templates of the class) is taken over once.
function BuildList()
	local key, db = PlanKey(), Talents.db
	local list = db.builds[key]
	if not list then
		list = {}
		db.builds[key] = list
	end
	-- The templates belong to the class: they wait until the game names the specialisation.
	local plan, templates = db.plans and db.plans[key], PlayerUtil.GetCurrentSpecID() and db.templates and db.templates[playerClass]
	if plan or templates then
		ns.TalentBuilds.Migrate(list, db, plan, db.planOrder and db.planOrder[key], templates, L.TALENTS_PLAN)
		if db.plans then
			db.plans[key] = nil
		end
		if db.planOrder then
			db.planOrder[key] = nil
		end
		if templates then
			db.templates[playerClass] = nil
		end
	end
	return list
end

-- The plan this character works with; without a choice the first one, without any plan an empty one.
function ActiveBuild()
	local list, key = BuildList(), PlanKey()
	local build = ns.TalentBuilds.Find(list, Talents.cdb.activeBuild[key])
	if not build then
		build = list[1] or ns.TalentBuilds.Add(list, Talents.db, L.TALENTS_PLAN)
		Talents.cdb.activeBuild[key] = build.id
	end
	return build
end

local function CurrentPlan()
	return ActiveBuild().ranks
end

-- The planned points that are not learned yet, one talent per point, in the order to learn them.
local function CurrentOrder()
	return ActiveBuild().order
end

local function PlanOverlay(button)
	local overlay = button.fpPlan
	if not overlay then
		overlay = {}
		overlay.Tint = button:CreateTexture(nil, "OVERLAY", nil, 6)
		overlay.Tint:SetAllPoints(button.Icon or button)
		overlay.Tint:SetColorTexture(PLAN_COLOR.r, PLAN_COLOR.g, PLAN_COLOR.b, 0.4)
		overlay.Tint:SetBlendMode("ADD")
		-- Above the button, so Blizzard's own rank number stays visible.
		overlay.Text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		overlay.Text:SetPoint("BOTTOM", button, "TOP", 0, -6)
		overlay.Text:SetTextColor(PLAN_COLOR:GetRGB())
		-- Below the button: the levels at which the planned ranks are due.
		overlay.Level = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		overlay.Level:SetPoint("TOP", button, "BOTTOM", 0, 5)
		overlay.Level:SetTextColor(PLAN_COLOR:GetRGB())
		-- Around the button: the talent the next free point belongs to, pulsing.
		overlay.Next = button:CreateTexture(nil, "OVERLAY", nil, 7)
		overlay.Next:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		overlay.Next:SetBlendMode("ADD")
		overlay.Next:SetVertexColor(PLAN_COLOR:GetRGB())
		overlay.Next:SetPoint("CENTER", button, "CENTER", 0, 0)
		overlay.Next:SetSize(ns.Number(button:GetWidth(), 40) * 1.8, ns.Number(button:GetHeight(), 40) * 1.8)
		overlay.Next:Hide()
		overlay.Pulse = overlay.Next:CreateAnimationGroup()
		overlay.Pulse:SetLooping("BOUNCE")
		local fade = overlay.Pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.35)
		fade:SetDuration(0.8)
		button.fpPlan = overlay
	end
	return overlay
end

-- Rules of the classic talent trees: each row needs 5 points in rows above
-- it in the same tree, and a talent behind an arrow needs its source talent
-- at full rank. Rows come from the node positions of the whole tree.
local POINTS_PER_ROW = 5
local ROW_TOLERANCE = 50 -- node positions of one row may differ by a few units
local SUFFICIENT_EDGE, REQUIRED_EDGE = Enum.TraitEdgeType.SufficientForAvailability, Enum.TraitEdgeType.RequiredForAvailability

local function BuildTreeState(frame, configID)
	local nodes, rowsY, names = {}, {}, {}
	for button in frame:EnumerateAllTalentButtons() do
		local nodeID = button.GetNodeID and button:GetNodeID()
		local node = nodeID and C_Traits.GetNodeInfo(configID, nodeID)
		if node and node.maxRanks and node.maxRanks > 0 then
			node.ID = node.ID or nodeID
			node.posY = node.posY or 0
			nodes[nodeID] = node
			rowsY[node.posY] = true
			names[nodeID] = button.GetName and button:GetName()
		end
	end
	local sorted = {}
	for y in pairs(rowsY) do
		sorted[#sorted + 1] = y
	end
	table.sort(sorted)
	-- Positions that differ by a few units belong to one row (some trees have 2120 next to 2130).
	local rowOf, row, previous = {}, -1, nil
	for _, y in ipairs(sorted) do
		if not previous or y - previous > ROW_TOLERANCE then
			row = row + 1
		end
		rowOf[y] = row
		previous = y
	end
	-- The specialisation of a talent: the three columns of the tree are far apart. This does
	-- not depend on the order the game lists the groups of a node in.
	local xs = {}
	for _, node in pairs(nodes) do
		xs[ns.Number(node.posX, 0)] = true
	end
	local sortedX = {}
	for x in pairs(xs) do
		sortedX[#sortedX + 1] = x
	end
	table.sort(sortedX)
	local gaps = {}
	for i = 2, #sortedX do
		gaps[#gaps + 1] = sortedX[i] - sortedX[i - 1]
	end
	local ordered = { unpack(gaps) }
	table.sort(ordered)
	local median = ordered[math.ceil(#ordered / 2)] or 0
	-- Split at the (at most two) biggest gaps that are far above the usual column distance.
	local limit = math.max(ordered[#ordered - 1] or 0, median * 2.5)
	local specOf, spec = {}, 1
	for i, x in ipairs(sortedX) do
		if i > 1 and gaps[i - 1] >= limit and gaps[i - 1] > median * 2.5 then
			spec = spec + 1
		end
		specOf[x] = spec
	end
	for _, node in pairs(nodes) do
		node.fpSpec = specOf[ns.Number(node.posX, 0)]
	end
	return nodes, rowOf, names
end

-- The tree is read once per change: every event that changes ranks or the plan bumps planStamp
-- (QueuePlanUpdate), tooltips and updates in between reuse the same reading.
local planStamp = 0
local treeCache

local function TreeState(frame, configID)
	local cache = treeCache
	if cache and cache.stamp == planStamp and cache.configID == configID and cache.frame == frame then
		return cache.nodes, cache.rowOf, cache.names
	end
	local nodes, rowOf, names = BuildTreeState(frame, configID)
	treeCache = { stamp = planStamp, configID = configID, frame = frame, nodes = nodes, rowOf = rowOf, names = names }
	return nodes, rowOf, names
end

local function Effective(node, plan)
	return math.max(node.ranksPurchased or 0, plan[node.ID] or 0)
end

local function RankDescription(entryID, rank)
	local ok, description = pcall(C_Traits.GetTraitDescription, entryID, rank)
	if ok and type(description) == "string" and not ns.Secret(description) then
		return description
	end
end

-- Points of the whole plan: what is learned already counts with the planned ranks.
local function TotalPoints(nodes, plan)
	local total = 0
	for _, node in pairs(nodes) do
		total = total + Effective(node, plan)
	end
	return total
end

-- Something planned that is not learned yet.
local function HasPending(nodes, plan)
	for nodeID, ranks in pairs(plan) do
		local node = nodes[nodeID]
		if node and ranks > (node.ranksPurchased or 0) then
			return true
		end
	end
	return false
end

-- Points in the rows above a row, per tree, and the arrows that lead to a node: worked out once per
-- reading of the tree and state of the plan, not for every talent that is checked.
local spentContext = setmetatable({}, { __mode = "k" })
local incomingContext = setmetatable({}, { __mode = "k" })

local function GroupOf(candidate)
	return candidate.fpSpec or (candidate.groupIDs and candidate.groupIDs[1])
end

-- A cheap fingerprint of a plan: changes whenever a rank is added, removed or changed.
local function PlanSignature(plan)
	local signature = 0
	for nodeID, ranks in pairs(plan) do
		signature = signature + nodeID * (ranks + 1)
	end
	return signature
end

local function SpentAbove(nodes, rowOf, plan, group, row)
	local context = spentContext[nodes]
	local signature = PlanSignature(plan)
	if not context or context.plan ~= plan or context.signature ~= signature then
		context = { plan = plan, signature = signature, perRow = {} }
		for _, other in pairs(nodes) do
			local otherGroup = GroupOf(other)
			local rows = context.perRow[otherGroup]
			if not rows then
				rows = {}
				context.perRow[otherGroup] = rows
			end
			local otherRow = rowOf[other.posY] or 0
			rows[otherRow] = (rows[otherRow] or 0) + Effective(other, plan)
		end
		spentContext[nodes] = context
	end
	local total = 0
	for otherRow, points in pairs(context.perRow[group] or {}) do
		if otherRow < row then
			total = total + points
		end
	end
	return total
end

local function IncomingEdges(nodes, nodeID)
	local map = incomingContext[nodes]
	if not map then
		map = {}
		for _, source in pairs(nodes) do
			for _, edge in ipairs(source.visibleEdges or {}) do
				local list = map[edge.targetNode]
				if not list then
					list = {}
					map[edge.targetNode] = list
				end
				list[#list + 1] = { source = source, type = edge.type }
			end
		end
		incomingContext[nodes] = map
	end
	return map[nodeID]
end

-- nil if the node may carry `rank` with the given plan, else a message.
local function CheckNode(nodes, rowOf, names, plan, node, rank)
	if rank <= 0 then
		return nil
	end
	local group = GroupOf(nodes[node.ID] or node)
	local row = rowOf[node.posY] or 0
	local spent = SpentAbove(nodes, rowOf, plan, group, row)
	if spent < row * POINTS_PER_ROW then
		return L.TALENTS_PLAN_NEED_POINTS:format(row * POINTS_PER_ROW - spent)
	end
	-- Arrows: every "required" source needs its full rank, of the "sufficient" ones one is enough
	-- (some trees have an arrow in both directions between two talents).
	local hasSufficient, satisfied, firstSource = false, false, nil
	for _, incoming in ipairs(IncomingEdges(nodes, node.ID) or {}) do
		local source = incoming.source
		local full = Effective(source, plan) >= source.maxRanks
		if incoming.type == REQUIRED_EDGE and not full then
			return L.TALENTS_PLAN_NEED_TALENT:format(names[source.ID] or "?")
		elseif incoming.type == SUFFICIENT_EDGE then
			hasSufficient = true
			satisfied = satisfied or full
			-- The one a player means is the talent above.
			if not firstSource or (source.posY or 0) < (firstSource.posY or 0) then
				firstSource = source
			end
		end
	end
	if hasSufficient and not satisfied then
		return L.TALENTS_PLAN_NEED_TALENT:format(names[firstSource.ID] or "?")
	end
	return nil
end

local function CheckPlan(nodes, rowOf, names, plan)
	for nodeID, node in pairs(nodes) do
		local planned = plan[nodeID]
		if planned and planned > (node.ranksPurchased or 0) then
			local problem = CheckNode(nodes, rowOf, names, plan, node, planned)
			if problem then
				return problem
			end
		end
	end
	return nil
end

-- The steps of the plan in an order the rules allow, and the level of the first step. Steps the player
-- clicked keep their order; planned ranks without a step (a template, an import, a plan from before the
-- order was kept) are added tree by tree (most planned points first), row by row, from the left.
local orderSynced = setmetatable({}, { __mode = "k" })

local function PlanOrder(nodes, rowOf, names, plan)
	local order = CurrentOrder()
	local signature = PlanSignature(plan)
	local synced = orderSynced[nodes]
	if synced and synced.order == order and synced.signature == signature then
		return order, synced.firstLevel
	end
	local wanted, ranks, perTree, learnedPoints = {}, {}, {}, 0
	for nodeID, node in pairs(nodes) do
		local learned = node.ranksPurchased or 0
		if learned > 0 then
			ranks[nodeID] = learned
			learnedPoints = learnedPoints + learned
		end
		if (plan[nodeID] or 0) > learned then
			wanted[nodeID] = plan[nodeID] - learned
			local tree = GroupOf(node) or 0
			perTree[tree] = (perTree[tree] or 0) + plan[nodeID]
		end
	end
	local steps, missing = ns.TalentOrder.Reconcile(order, wanted)
	local added = {}
	for nodeID in pairs(missing) do
		added[#added + 1] = nodeID
	end
	table.sort(added, function(a, b)
		local nodeA, nodeB = nodes[a], nodes[b]
		local treeA, treeB = GroupOf(nodeA) or 0, GroupOf(nodeB) or 0
		if treeA ~= treeB then
			if perTree[treeA] ~= perTree[treeB] then
				return perTree[treeA] > perTree[treeB]
			end
			return treeA < treeB
		end
		local rowA, rowB = rowOf[nodeA.posY] or 0, rowOf[nodeB.posY] or 0
		if rowA ~= rowB then
			return rowA < rowB
		end
		local xA, xB = ns.Number(nodeA.posX, 0), ns.Number(nodeB.posX, 0)
		if xA ~= xB then
			return xA < xB
		end
		return a < b
	end)
	for _, nodeID in ipairs(added) do
		for _ = 1, missing[nodeID] do
			steps[#steps + 1] = nodeID
		end
	end
	steps = ns.TalentOrder.Repair(steps, function(nodeID, state)
		return CheckNode(nodes, rowOf, names, state, nodes[nodeID], (state[nodeID] or 0) + 1) == nil
	end, ranks)
	wipe(order)
	for index, nodeID in ipairs(steps) do
		order[index] = nodeID
	end
	local firstLevel = FIRST_TALENT_LEVEL + learnedPoints
	orderSynced[nodes] = { order = order, signature = signature, firstLevel = firstLevel }
	return order, firstLevel
end

-- A talent Blizzard still shows as locked (row or arrow) that the plan has
-- unlocked: the next rank may be planned.
local function UnlockedByPlan(node, nodes, rowOf, names, plan)
	if node.isAvailable ~= false and node.meetsEdgeRequirements ~= false then
		return false
	end
	local target = math.max(plan[node.ID] or 0, node.ranksPurchased or 0) + 1
	return target <= node.maxRanks and CheckNode(nodes, rowOf, names, plan, node, target) == nil
end

-- Why the last right-click did nothing: { nodeID =, text = }, shown in that talent's tooltip.
local blocked

-- Tooltip of a talent while planning: the values of the planned rank below
-- Blizzard's own text, and what stops the next planned rank (with the plan
-- counted in), all in the colour of the plan.
local function AddPlanTooltip(button)
	if not (Talents.db.enabled and Talents.db.planner) or GameTooltip:GetOwner() ~= button then
		return
	end
	local frame = TalentsFrame()
	local configID = frame and frame:GetConfigID()
	local nodeID = button.GetNodeID and button:GetNodeID()
	local node = nodeID and configID and C_Traits.GetNodeInfo(configID, nodeID)
	if not node or not node.maxRanks or node.maxRanks == 0 then
		return
	end
	local plan = CurrentPlan()
	local planned = plan[nodeID]
	local blank = false
	local entry = node.activeEntry or node.nextEntry
	local entryID = entry and entry.entryID or (node.entryIDs and node.entryIDs[1])
	if planned and planned > (node.ranksPurchased or 0) and entryID then
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		blank = true
		GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_PLAN_RANK:format(planned, node.maxRanks), PLAN_COLOR)
		if Talents.db.planNext then
			local nodes, rowOf, names = TreeState(frame, configID)
			local levels = ns.TalentOrder.LevelTexts(PlanOrder(nodes, rowOf, names, plan))[nodeID]
			if levels then
				GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_PLAN_LEVELS:format(levels), PLAN_COLOR)
			end
		end
		-- Plain lines: appended tooltip data would pile up with every change of the plan.
		local description = RankDescription(entryID, planned)
		if description then
			GameTooltip_AddHighlightLine(GameTooltip, description, true)
		end
	end
	local notes = {}
	local target = math.max(planned or 0, node.ranksPurchased or 0) + 1
	if target <= node.maxRanks then
		node.ID = node.ID or nodeID
		node.posY = node.posY or 0
		local nodes, rowOf, names = TreeState(frame, configID)
		local problem = CheckNode(nodes, rowOf, names, plan, node, target)
		if problem then
			notes[#notes + 1] = problem
		elseif UnlockedByPlan(node, nodes, rowOf, names, plan) then
			notes[#notes + 1] = L.TALENTS_PLAN_UNLOCKED
		end
	end
	if blocked and blocked.nodeID == nodeID and blocked.text ~= notes[1] then
		notes[#notes + 1] = blocked.text
	end
	if #notes > 0 then
		if not blank then
			GameTooltip_AddBlankLineToTooltip(GameTooltip)
		end
		for _, note in ipairs(notes) do
			GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_PLAN_NOTE:format(note), PLAN_COLOR, true)
		end
	end
	if blank or #notes > 0 then
		GameTooltip:Show()
	end
end

local tooltipHooked = {}

local function HookPlanTooltip(button)
	if not tooltipHooked[button] and button.SetTooltipInternal then
		tooltipHooked[button] = true
		hooksecurefunc(button, "SetTooltipInternal", AddPlanTooltip)
	end
end

-- Builds the open tooltip of a talent again (new planned rank, reason for a refusal). Hidden first: Blizzard
-- appends the descriptions of the ranks as tooltip data, and on a tooltip that stayed open they piled up (the
-- same two descriptions once more with every click).
local function RefreshTooltip(button)
	if GameTooltip:GetOwner() == button and button.SetTooltipInternal then
		HookPlanTooltip(button)
		GameTooltip:Hide()
		button:SetTooltipInternal()
	end
end

-- The counter beside the plan buttons: only while something is planned (it counted the learned talents as a plan).
function Talents.CounterText(points, hasPlan)
	if not hasPlan or points <= 0 then
		return ""
	end
	return L.TALENTS_PLAN_COUNTER:format(points, PLAN_POINTS, FIRST_TALENT_LEVEL - 1 + points)
end

local function UpdatePlan()
	local frame = TalentsFrame()
	if not frame or not frame:IsVisible() or not frame.EnumerateAllTalentButtons then
		if planBar then
			planBar:Hide()
		end
		return
	end
	local configID = frame:GetConfigID()
	local plan = CurrentPlan()
	local enabled = Talents.db.enabled and Talents.db.planner
	local nodes, levels, nextID
	if enabled and configID then
		local rowOf, names
		nodes, rowOf, names = TreeState(frame, configID)
		local order, firstLevel = PlanOrder(nodes, rowOf, names, plan)
		if Talents.db.planNext then
			levels = ns.TalentOrder.LevelTexts(order, firstLevel)
			nextID = order[1] and Talents.UnspentPoints() > 0 and order[1] or nil
		end
	end
	local pending = nodes and HasPending(nodes, plan) or false
	for button in frame:EnumerateAllTalentButtons() do
		HookPlanTooltip(button)
		local nodeID = button.GetNodeID and button:GetNodeID()
		local planned = enabled and nodeID and plan[nodeID]
		if planned or button.fpPlan then
			local overlay = PlanOverlay(button)
			local node = planned and configID and C_Traits.GetNodeInfo(configID, nodeID)
			if node and planned then
				overlay.Text:SetFormattedText("%d/%d", planned, node.maxRanks)
				overlay.Text:Show()
				overlay.Tint:SetShown(planned > node.ranksPurchased)
			else
				overlay.Text:Hide()
				overlay.Tint:Hide()
			end
			overlay.Level:SetText(levels and levels[nodeID] or "")
			local isNext = nextID ~= nil and nodeID == nextID
			overlay.Next:SetShown(isNext)
			if isNext then
				overlay.Pulse:Play()
			else
				overlay.Pulse:Stop()
			end
		end
	end
	if planBar then
		local points = nodes and TotalPoints(nodes, plan) or 0
		local planner = enabled and true or false
		-- Without the planner the bar is only the menu, which then still exports.
		planBar:SetShown(Talents.db.enabled and true or false)
		planBar.Menu:SetText(planner and ActiveBuild().name or L.TALENTS_EXPORT)
		local menuWidth = ns.Number(planBar.Menu:GetTextWidth(), 60) + 24
		planBar.Menu:SetWidth(menuWidth)
		planBar.Apply:SetShown(planner)
		planBar.Clear:SetShown(planner)
		planBar.Counter:SetText(planner and Talents.CounterText(points, next(plan) ~= nil) or "")
		planBar:SetWidth(menuWidth + 4 + PLAN_BUTTON_SIZE * 2 + 14 + ns.Number(planBar.Counter:GetStringWidth(), 0))
		planBar.Apply:SetEnabled(pending)
		planBar.Clear:SetEnabled(next(plan) ~= nil)
	end
end

-- What is planned or learned, saved as a plan of its own under a name (the active plan stays the active one).
local function StoreTemplate(name, ranks, order)
	if name == "" then
		name = date("%d.%m. %H:%M")
	end
	local build = ns.TalentBuilds.Add(BuildList(), Talents.db, name, ns.TalentBuilds.ParseRanks(ranks), order)
	ns.Print(L.TALENTS_TEMPLATE_SAVED:format(build.name, ns.TalentBuilds.Points(build)))
end

function SavePlanTemplate()
	local frame = TalentsFrame()
	local configID = frame and frame:IsVisible() and frame.GetConfigID and frame:GetConfigID()
	if not configID then
		ns.Print(L.TALENTS_TEMPLATE_BAD:format(L.TALENTS_TEMPLATE_CLOSED))
		return
	end
	local nodes = TreeState(frame, configID)
	local plan, parts = CurrentPlan(), {}
	for nodeID, node in pairs(nodes) do
		local rank = Effective(node, plan)
		if rank > 0 then
			parts[#parts + 1] = { nodeID, rank }
		end
	end
	if #parts == 0 then
		ns.Print(L.TALENTS_TEMPLATE_EMPTY)
		return
	end
	table.sort(parts, function(a, b)
		return a[1] < b[1]
	end)
	for index, part in ipairs(parts) do
		parts[index] = part[1] .. ":" .. part[2]
	end
	local ranks = table.concat(parts, ",")
	local order = { unpack(CurrentOrder()) }
	ns.ShowEditWindow("TemplateName", L.TALENTS_TEMPLATE_SAVE, "", SAVE, function(name)
		StoreTemplate(name, ranks, order)
	end, L.TALENTS_NAME_HINT)
end

-- Blizzard's loadout text for the learned ranks plus the plan: the game's own writer reads only
-- what is learned, so the same bit stream is written here from the wanted ranks (format:
-- Blizzard_ClassTalentImportExport.lua). Granted nodes stay granted, choice nodes keep their
-- active entry.
local function LoadoutString(frame, plan)
	local configID, treeID = frame:GetConfigID(), frame:GetTreeInfo().ID
	local stream = ExportUtil.MakeExportDataStream()
	stream:AddValue(8, C_Traits.GetLoadoutSerializationVersion())
	stream:AddValue(16, PlayerUtil.GetCurrentSpecID() or frame:GetSpecID())
	for _, value in ipairs(C_Traits.GetTreeHash(treeID)) do
		stream:AddValue(8, value)
	end
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		local maxRanks = node and node.maxRanks or 0
		local granted = node and (node.activeRank or 0) - (node.ranksPurchased or 0) > 0
		local ranks = math.min(math.max(node and node.ranksPurchased or 0, plan[nodeID] or 0), maxRanks)
		stream:AddValue(1, (granted or ranks > 0) and 1 or 0)
		if granted or ranks > 0 then
			stream:AddValue(1, ranks > 0 and 1 or 0)
			if ranks > 0 then
				local partial = ranks ~= maxRanks
				stream:AddValue(1, partial and 1 or 0)
				if partial then
					stream:AddValue(6, ranks)
				end
				local choice = node.type == Enum.TraitNodeType.Selection or node.type == Enum.TraitNodeType.SubTreeSelection
				stream:AddValue(1, choice and 1 or 0)
				if choice then
					local index = 1
					for i, entryID in ipairs(node.entryIDs or {}) do
						if node.activeEntry and entryID == node.activeEntry.entryID then
							index = i
						end
					end
					stream:AddValue(2, math.min(index, 4) - 1)
				end
			end
		end
	end
	return stream:GetExportString()
end

-- The plan (and what is learned) as Blizzard's loadout text.
function ExportPlan()
	local frame = TalentsFrame()
	if not frame or not frame.GetConfigID or not frame:GetConfigID() then
		ns.Print(L.TALENTS_ERROR_CLOSED)
		return
	end
	local ok, text = pcall(LoadoutString, frame, Talents.db.planner and CurrentPlan() or {})
	if not ok or type(text) ~= "string" then
		ns.Print(L.TALENTS_EXPORT_FAILED, tostring(text))
		return
	end
	ns.ShowEditWindow("BuildExport", L.TALENTS_EXPORT_PLAN, text, CLOSE, nil, L.TALENTS_EXPORT_HINT)
end

local updatePending = false
local function QueuePlanUpdate()
	planStamp = planStamp + 1
	if not updatePending then
		updatePending = true
		ns.After("Talents: QueuePlanUpdate (timer)", 0, function()
			updatePending = false
			UpdatePlan()
		end)
	end
end

function ActivatePlan(id)
	Talents.cdb.activeBuild[PlanKey()] = id
	QueuePlanUpdate()
end

local function Trimmed(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function NewPlan()
	ns.ShowEditWindow("TemplateName", L.TALENTS_PLAN_NEW, "", SAVE, function(name)
		name = Trimmed(name)
		ActivatePlan(ns.TalentBuilds.Add(BuildList(), Talents.db, name ~= "" and name or date("%d.%m. %H:%M")).id)
	end, L.TALENTS_NAME_HINT)
end

function RenamePlan()
	local build = ActiveBuild()
	ns.ShowEditWindow("TemplateName", L.TALENTS_PLAN_RENAME, build.name, SAVE, function(name)
		name = Trimmed(name)
		if name ~= "" then
			build.name = ns.TalentBuilds.UniqueName(BuildList(), name, build)
			QueuePlanUpdate()
		end
	end)
end

-- Takes the active plan out of the list; the first of the others becomes the active one.
function RemovePlan()
	local build = ActiveBuild()
	ns.TalentBuilds.Remove(BuildList(), build.id)
	ns.Print(L.TALENTS_PLAN_REMOVED:format(build.name))
	QueuePlanUpdate()
end

-- A plan from outside (standard distribution, link, import code) becomes a plan of its own and the active
-- one. An active plan with nothing in it is used for it instead of being left behind.
local function StorePlan(name, ranks, order)
	local list, build = BuildList(), ActiveBuild()
	if next(build.ranks) == nil then
		build.name = ns.TalentBuilds.UniqueName(list, name, build)
		build.ranks, build.order = ranks, order or {}
	else
		ActivatePlan(ns.TalentBuilds.Add(list, Talents.db, name, ranks, order).id)
	end
end

-- Makes a plan of a template (standard distribution, link):
-- only when all its talents exist in this tree and the rules allow it.
function ApplyTemplate(preset, name)
	local frame = TalentsFrame()
	local configID = frame and frame:IsVisible() and frame.GetConfigID and frame:GetConfigID()
	if not configID then
		ns.Print(L.TALENTS_TEMPLATE_BAD:format(L.TALENTS_TEMPLATE_CLOSED))
		return
	end
	local nodes, rowOf, names = TreeState(frame, configID)
	local plan, points = {}, 0
	for nodeText, rankText in preset.ranks:gmatch("(%d+):(%d+)") do
		local nodeID, rank = tonumber(nodeText), tonumber(rankText)
		local node = nodes[nodeID]
		if not node then
			ns.Print(L.TALENTS_TEMPLATE_BAD:format(L.TALENTS_TEMPLATE_OTHER_TREE))
			return
		end
		plan[nodeID] = math.min(rank, node.maxRanks)
		points = points + plan[nodeID]
	end
	local problem = CheckPlan(nodes, rowOf, names, plan)
	if problem then
		ns.Print(L.TALENTS_TEMPLATE_BAD:format(problem))
		return
	end
	StorePlan(name, plan)
	QueuePlanUpdate()
	ns.Print(L.TALENTS_TEMPLATE_DONE:format(name, points))
end


---------------------------------------------------------------------------
-- Links of the talent calculators on the web (Forever has no import code of its own).
-- Wowhead: …/forever/talent-calc/paladin/vkndmh511-1-01_t0/0ab…: after six letters one digit per talent (its
-- rank), the talents of a tree row by row from the left, the trees separated by "-", zeros at the end left out.
-- Icy Veins: …/wow-forever/paladin-talent-calculator#tc-33Oy1~70888-…: one character per point spent; which
-- character stands for which talent is the site's own choice (LINK_IDS: per class and tree the characters of the
-- talents, row by row from the left; read from the site's calculator, data version 70888-0650090c).
---------------------------------------------------------------------------
local LINK_IDS = {
	DRUID = { "0123456789abcdef", "ghijklmnopsrqtvwyxzu", "ABCDEFGHIJKLMNOP" },
	HUNTER = { "0123546789abcdef", "ghijklmnopqrstuv", "wxyzABCDEFGHIJKLMN" },
	MAGE = { "023456789abcdefghi", "klmnopqrjstuvwxyz", "ABCDEFGHIJKLMNOPQR" },
	PALADIN = { "3O2748baAc96edPfg", "1ijkptsohqnl0wuvm", "xyzBDC5EFGHIQKJLN" },
	PRIEST = { "0123456789abcdefgh", "ijklmnopqrstuvwxy", "zABCDEFGHIJKLMNOP" },
	ROGUE = { "0123754c89abRgefd", "hijklmpno6qrvwStusx", "BzALyEDFJKCGOIMNPQ" },
	SHAMAN = { "0123456789abcdef", "ghijkmnopqrsltuvwx", "yzABCDEFGHIJKLMN" },
	WARLOCK = { "0123456789abcdefg", "hijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOP" },
	WARRIOR = { "0123456789abcdefg", "hijklmnqoQrstwupvx", "yzABCDEFGHIJKLMNOP" },
}

-- Whether a text is a link of one of the calculators.
function Talents.IsLink(text)
	return type(text) == "string" and (text:find("talent%-calc/", 1) or text:find("%-talent%-calculator", 1)) and true or false
end

-- Reads a link for a class (file name, "PALADIN"): the ranks by place, trees[tree][place in the tree] = rank.
-- Without a result the reason: "class" (another class), "format" (not readable).
function Talents.ParseLink(text, class)
	local trees = { {}, {}, {} }
	local slug, code = text:match("talent%-calc/(%a+)/([^/%s%?#]+)")
	if slug then
		if slug:upper() ~= class then
			return nil, "class"
		end
		local digits = code:gsub("_.*$", ""):match("^%a*([%d%-]*)$")
		if not digits or digits == "" then
			return nil, "format"
		end
		local tree = 0
		for part in (digits .. "-"):gmatch("(%d*)%-") do
			tree = tree + 1
			if tree > 3 then
				return nil, "format"
			end
			for place = 1, #part do
				trees[tree][place] = tonumber(part:sub(place, place))
			end
		end
		return trees
	end
	local points
	slug, points = text:match("(%a+)%-talent%-calculator#tc%-(%w+)")
	if not slug then
		return nil, "format"
	elseif slug:upper() ~= class then
		return nil, "class"
	end
	local ids = LINK_IDS[class]
	for index = 1, #points do
		local found = false
		for tree = 1, 3 do
			local place = ids and ids[tree]:find(points:sub(index, index), 1, true)
			if place then
				trees[tree][place] = (trees[tree][place] or 0) + 1
				found = true
				break
			end
		end
		if not found then
			return nil, "format"
		end
	end
	return trees
end

-- The ranks by place onto the talents of the game: ordered[tree] = { { nodeID, maxRanks }, … } row by row from the
-- left. The text "nodeID:rank,…" of a template, or nil when the link does not fit these trees (a place that does
-- not exist, more ranks than the talent has).
function Talents.LinkRanks(trees, ordered)
	local parts = {}
	for tree = 1, 3 do
		for place, rank in pairs(trees[tree]) do
			local entry = ordered[tree] and ordered[tree][place]
			if rank > 0 then
				if not entry or rank > entry[2] then
					return nil
				end
				parts[#parts + 1] = ("%d:%d"):format(entry[1], rank)
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- The talents of the open window by tree (left to right), row and column.
local function OrderedNodes(nodes, rowOf)
	local ordered = { {}, {}, {} }
	for nodeID, node in pairs(nodes) do
		local list = ordered[node.fpSpec or 0]
		if list then
			list[#list + 1] = { nodeID, node.maxRanks, row = rowOf[node.posY] or 0, x = ns.Number(node.posX, 0) }
		end
	end
	for _, list in ipairs(ordered) do
		table.sort(list, function(a, b)
			if a.row ~= b.row then
				return a.row < b.row
			end
			return a.x < b.x
		end)
	end
	return ordered
end

local function ImportLink(frame, configID, text)
	local trees, reason = Talents.ParseLink(text, playerClass)
	if not trees then
		ns.Print(reason == "class" and L.TALENTS_LINK_CLASS or L.TALENTS_LINK_FORMAT)
		return
	end
	local nodes, rowOf = TreeState(frame, configID)
	local ranks = Talents.LinkRanks(trees, OrderedNodes(nodes, rowOf))
	if not ranks or ranks == "" then
		ns.Print(L.TALENTS_TEMPLATE_BAD:format(L.TALENTS_TEMPLATE_OTHER_TREE))
		return
	end
	ApplyTemplate({ ranks = ranks }, L.TALENTS_LINK_NAME)
end

-- Blizzard's loadout text into the plan (nothing is learned yet): the ✓ button learns what the
-- points allow, from the top row down and in a row from left to right; the rest stays in the plan.
function ImportPlan()
	local frame = TalentsFrame()
	local configID = frame and frame.GetConfigID and frame:GetConfigID()
	if not configID then
		ns.Print(L.TALENTS_ERROR_CLOSED)
		return
	end
	ns.ShowEditWindow("BuildImport", L.TALENTS_IMPORT_CODE, "", L.TALENTS_IMPORT, function(text)
		text = ((text or ""):gsub("%s+", ""))
		if text == "" then
			return
		end
		if Talents.IsLink(text) then
			ImportLink(frame, configID, text)
			return
		end
		local ok, entries, err = pcall(ParseBuild, frame, text)
		if not ok then
			ns.Print(L.TALENTS_IMPORT_FAILED, tostring(entries))
			return
		elseif not entries then
			ns.Print(err)
			return
		end
		local imported = {}
		for _, entry in ipairs(entries) do
			if entry.ranksPurchased and entry.ranksPurchased > 0 then
				imported[entry.nodeID] = (imported[entry.nodeID] or 0) + entry.ranksPurchased
			end
		end
		local current, points, count = {}, 0, 0
		for nodeID, rank in pairs(imported) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			local maxRanks = node and node.maxRanks or 0
			if maxRanks > 0 then
				current[nodeID] = math.min(rank, maxRanks)
				points, count = points + current[nodeID], count + 1
			end
		end
		if count == 0 then
			ns.Print(L.TALENTS_IMPORT_EMPTY)
		else
			StorePlan(L.TALENTS_IMPORT_NAME, current)
			QueuePlanUpdate()
			ns.Print(L.TALENTS_IMPORT_DONE, points, count, FIRST_TALENT_LEVEL - 1 + points)
		end
	end, L.TALENTS_IMPORT_HINT)
end

local function AddPlanRank(nodes, rowOf, names, plan, node)
	local target = Effective(node, plan) + 1
	if target > node.maxRanks then
		return false
	end
	if TotalPoints(nodes, plan) >= PLAN_POINTS then
		return false, L.TALENTS_PLAN_FULL:format(PLAN_POINTS, PLAN_MAX_LEVEL)
	end
	local problem = CheckNode(nodes, rowOf, names, plan, node, target)
	if problem then
		return false, problem
	end
	-- The new point is the last step; what was planned before gets its steps first.
	local order = PlanOrder(nodes, rowOf, names, plan)
	order[#order + 1] = node.ID
	plan[node.ID] = target
	return true
end

local PRIMARY_STATS = { "STR", "AGI", "STA", "INT", "SPI" }

local function RecommendationGains(configID, nodes, weights)
	local stats, gains = {}, {}
	local german = GetLocale() == "deDE"
	for index, stat in ipairs(PRIMARY_STATS) do
		stats[stat] = ns.Number(select(2, UnitStat("player", index)), 0)
	end
	for _, node in ipairs(nodes) do
		local entryID = node.entryIDs and #node.entryIDs == 1 and node.entryIDs[1]
		local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
		local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
		if definition and definition.spellID and C_Spell.IsSpellPassive(definition.spellID) then
			local previous, scores = nil, {}
			for rank = 1, node.maxRanks do
				local description = RankDescription(entryID, rank)
				if description and (rank == 1 or previous) then
					scores[rank] = ns.TalentSummary.RankGain(previous, description, weights, stats, german)
				end
				previous = description
			end
			if next(scores) then
				gains[node.ID] = scores
			end
		end
	end
	return gains
end

-- Keep the role's template ahead of filler. Within each priority, prefer the higher
-- marginal stat score, then use the ordered nodes to break ties.
local function FillRecommendation(nodes, rowOf, names, ordered, targets, gains, tree, targetsOnly)
	local plan, order = {}, {}
	for id, node in pairs(nodes) do
		local learned = node.ranksPurchased or 0
		if learned > 0 then
			plan[id] = learned
		end
	end
	local points = TotalPoints(nodes, plan)
	while points < PLAN_POINTS do
		local best, bestRank, bestPriority, bestGain = nil, nil, -1, 0
		for _, node in ipairs(ordered) do
			local id = node.ID
			local rank = (plan[id] or 0) + 1
			local inTemplate = rank <= (targets[id] or 0)
			if rank <= node.maxRanks and (inTemplate or not targetsOnly) then
				local priority = (inTemplate and 2 or 0) + (GroupOf(node) == tree and 1 or 0)
				local gain = gains[id] and gains[id][rank] or 0
				if (priority > bestPriority or (priority == bestPriority and gain > bestGain))
					and not CheckNode(nodes, rowOf, names, plan, node, rank) then
					best, bestRank, bestPriority, bestGain = id, rank, priority, gain
				end
			end
		end
		if not best then
			break
		end
		plan[best] = bestRank
		order[#order + 1] = best
		points = points + 1
	end
	if points == PLAN_POINTS then
		return plan, order
	end
end

-- Trade measured bonuses in the same row and tree. This preserves the tree split,
-- the points available to unlock later rows, and talents whose effects need the template.
local function ImproveRecommendation(nodes, rowOf, names, ordered, plan, gains)
	local scored = {}
	for _, node in ipairs(ordered) do
		if gains[node.ID] then
			scored[#scored + 1] = node
		end
	end
	local changed = false
	for _ = 1, PLAN_POINTS do
		local take, give, improvement = nil, nil, 0
		for _, to in ipairs(scored) do
			local toRank = plan[to.ID] or 0
			local nextGain = gains[to.ID][toRank + 1]
			if nextGain and nextGain > 0 then
				for _, from in ipairs(scored) do
					local fromRank = plan[from.ID] or 0
					local oldGain = gains[from.ID][fromRank]
					if from ~= to and oldGain and nextGain - oldGain > improvement and fromRank > (from.ranksPurchased or 0)
						and GroupOf(from) == GroupOf(to) and rowOf[from.posY] == rowOf[to.posY] then
						local oldTarget = plan[to.ID]
						plan[to.ID], plan[from.ID] = toRank + 1, fromRank - 1
						if not CheckPlan(nodes, rowOf, names, plan) then
							take, give, improvement = to.ID, from.ID, nextGain - oldGain
						end
						plan[to.ID], plan[from.ID] = oldTarget, fromRank
					end
				end
			end
		end
		if not take then
			break
		end
		local remaining = plan[give] - 1
		plan[take], plan[give] = (plan[take] or 0) + 1, remaining > 0 and remaining or nil
		changed = true
	end
	return changed
end

function RecommendPlan()
	local frame = TalentsFrame()
	local configID = frame and frame:IsVisible() and frame:GetConfigID()
	if not (Talents.db.enabled and Talents.db.planner and configID) then
		return
	end
	local weights, treeName, tree, presetIndex = ns.StatWeights()
	local nodes, rowOf, names = TreeState(frame, configID)
	local ordered = {}
	for _, node in pairs(nodes) do
		if node.isVisible ~= false then
			ordered[#ordered + 1] = node
		end
	end
	table.sort(ordered, function(a, b)
		local aRow, bRow = rowOf[a.posY] or 0, rowOf[b.posY] or 0
		if aRow ~= bRow then
			return aRow > bRow
		end
		return a.ID < b.ID
	end)

	local presets = ns.TalentPresets and ns.TalentPresets[playerClass]
	local preset = presets and presets[presetIndex or tree]
	local targets = ns.TalentBuilds.ParseRanks(preset and preset.ranks)
	local gains = RecommendationGains(configID, ordered, weights)
	local plan, order = FillRecommendation(nodes, rowOf, names, ordered, targets, gains, tree)
	if not plan then
		ns.Print(L.TALENTS_RECOMMEND_INCOMPLETE:format(PLAN_POINTS))
		return
	end
	local improved = CopyTable(plan)
	if ImproveRecommendation(nodes, rowOf, names, ordered, improved, gains) then
		local revised, revisedOrder = FillRecommendation(nodes, rowOf, names, ordered, improved, gains, tree, true)
		if revised then
			plan, order = revised, revisedOrder
		end
	end

	local label = preset and (GetLocale() == "deDE" and preset.de or preset.en) or treeName
	local name = L.TALENTS_RECOMMEND_NAME:format(PLAN_MAX_LEVEL)
	if label and not ns.Secret(label) then
		name = name .. " (" .. label .. ")"
	end
	StorePlan(name, plan, order)
	QueuePlanUpdate()
	ns.Print(L.TALENTS_TEMPLATE_DONE:format(ActiveBuild().name, PLAN_POINTS))
end

local function OnTalentClick(_, button, mouseButton)
	if mouseButton ~= "RightButton" or IsControlKeyDown() or not (Talents.db.enabled and Talents.db.planner) then
		return
	end
	local frame = TalentsFrame()
	local nodeID = button.GetNodeID and button:GetNodeID()
	local configID = frame and frame:GetConfigID()
	local node = nodeID and configID and C_Traits.GetNodeInfo(configID, nodeID)
	if not node or not node.maxRanks or node.maxRanks == 0 then
		return
	end
	node.ID = node.ID or nodeID
	local plan = CurrentPlan()
	local planned = plan[nodeID] or 0
	local nodes, rowOf, names = TreeState(frame, configID)
	blocked = nil
	local function Refuse(text)
		-- The reason shows in the talent's tooltip, rebuilt below.
		blocked = { nodeID = nodeID, text = text }
		RefreshTooltip(button)
	end
	local learned = node.ranksPurchased or 0
	if IsShiftKeyDown() then
		-- Learned ranks stay: only what is planned on top of them can be taken back.
		if math.max(planned, learned) <= learned then
			if learned > 0 then
				Refuse(L.TALENTS_PLAN_LEARNED)
			end
			plan[nodeID] = nil
			QueuePlanUpdate()
			return
		end
		planned = math.max(planned, learned) - 1
		local old = plan[nodeID]
		plan[nodeID] = planned > learned and planned or nil
		-- Removing must not leave a talent above without its requirement.
		local problem = CheckPlan(nodes, rowOf, names, plan)
		plan[nodeID] = old
		if problem then
			Refuse(L.TALENTS_PLAN_REMOVE_BLOCKED)
			return
		end
		ns.TalentOrder.RemoveLast(CurrentOrder(), nodeID)
		plan[nodeID] = planned > learned and planned or nil
	elseif button.CanRefundRank and button:CanRefundRank() then
		return -- Blizzard refunds a staged rank with this click
	else
		local added, problem = AddPlanRank(nodes, rowOf, names, plan, node)
		if not added then
			if problem then
				Refuse(problem)
			end
			return
		end
	end
	QueuePlanUpdate()
	-- Rebuild the open tooltip with the new planned rank.
	RefreshTooltip(button)
end

-- Buys the planned ranks the points allow, in the order of the plan; Blizzard's talent window shows
-- them as pending until they are confirmed with its button.
function ApplyPlan()
	local configID = C_ClassTalents.GetActiveConfigID()
	local frame = TalentsFrame()
	if InCombatLockdown() or not configID or not C_SpecializationInfo.HasPlayerEarnedATalentPoint()
		or (frame and frame.IsLocked and frame:IsLocked()) then
		ns.Print(L.TALENTS_ERROR_FRAME)
		return
	end
	if not (frame and frame.EnumerateAllTalentButtons) then
		ns.Print(L.TALENTS_ERROR_CLOSED)
		return
	end
	-- Point by point in the order of the plan, as far as the points go.
	local nodes, rowOf, names = TreeState(frame, configID)
	for _, nodeID in ipairs(PlanOrder(nodes, rowOf, names, CurrentPlan())) do
		if not C_Traits.PurchaseRank(configID, nodeID) then
			break
		end
	end
	ns.Print(L.TALENTS_PLAN_STAGED)
	QueuePlanUpdate()
end

function Talents:CurrentPlan()
	return CurrentPlan()
end

function Talents:QueuePlanUpdate()
	QueuePlanUpdate()
end

function Talents:ApplyPlan()
	ApplyPlan()
end

function ClearPlan()
	wipe(CurrentPlan())
	wipe(CurrentOrder())
	QueuePlanUpdate()
end

-- Small buttons in the game's own look: the golden arrow of the spell book
-- ("apply") and the red close cross ("clear"), with a tooltip.
local function AddButtonTip(button, title, text)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_AddColoredLine(GameTooltip, title, PLAN_COLOR)
		GameTooltip_AddNormalLine(GameTooltip, text)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	hooksecurefunc(button, "SetEnabled", function(self, enabled)
		self:SetAlpha(enabled and 1 or 0.45)
	end)
end

-- Both buttons are the same square button of the game's UI with a symbol on it.
local function CreatePlanButton(parent, atlas, title, tooltip, onClick)
	local ok, button = pcall(CreateFrame, "Button", nil, parent, "SquareIconButtonTemplate")
	if not ok then
		button = CreateFrame("Button", nil, parent)
		button:SetNormalTexture([[Interface\Buttons\UI-SquareButton-Up]])
		button:SetPushedTexture([[Interface\Buttons\UI-SquareButton-Down]])
		button:SetDisabledTexture([[Interface\Buttons\UI-SquareButton-Disabled]])
		button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
		button.Icon = button:CreateTexture(nil, "OVERLAY")
		button.Icon:SetPoint("CENTER", -1, 0)
	end
	button:SetSize(PLAN_BUTTON_SIZE, PLAN_BUTTON_SIZE)
	button.Icon:SetAtlas(atlas)
	button.Icon:SetSize(16, 16)
	button:SetScript("OnClick", onClick)
	AddButtonTip(button, title, tooltip)
	hooksecurefunc(button, "SetEnabled", function(self, enabled)
		self.Icon:SetDesaturated(not enabled)
	end)
	return button
end

-- Mouse-over on the plan bar: the effects of everything planned and learned, added up per kind.
local function ShowPlanSummary(owner)
	local frame = TalentsFrame()
	local configID = frame and frame.GetConfigID and frame:GetConfigID()
	if not configID then
		return
	end
	local nodes = TreeState(frame, configID)
	local plan = CurrentPlan()
	local descriptions, talents, points = {}, 0, 0
	for _, node in pairs(nodes) do
		local rank = Effective(node, plan)
		local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
		if rank > 0 and entryID then
			talents, points = talents + 1, points + rank
			local description = RankDescription(entryID, rank)
			if description then
				descriptions[#descriptions + 1] = description
			end
		end
	end
	local lines, other = ns.TalentSummary.Build(descriptions, GetLocale() == "deDE")
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_SUMMARY_TITLE:format(talents, points), PLAN_COLOR)
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line.text, 0.55, 1, 0.55)
	end
	if #lines == 0 then
		GameTooltip_AddNormalLine(GameTooltip, L.TALENTS_SUMMARY_NONE)
	end
	if other > 0 then
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip:AddLine(L.TALENTS_SUMMARY_OTHER:format(other), 0.62, 0.62, 0.62, true)
	end
	GameTooltip:Show()
end

-- Top centre of the talent window, between the title and the tabs: the name of the active plan (a button
-- that opens the menu of the plans), two small symbol buttons ("apply" tick, "clear" cross) and the counter,
-- in the colour of the plan.
local PLAN_BAR_POINT = { "TOP", nil, "TOP", 0, -62 }

local function CreatePlanBar(frame)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetSize(330, 24)
	bar:SetFrameLevel(ns.Number(frame:GetFrameLevel(), 0) + 1010)
	bar:SetFrameStrata("HIGH")
	bar.Apply = CreatePlanButton(bar, "common-icon-checkmark", L.TALENTS_PLAN_BUTTON_APPLY, L.TALENTS_PLAN_BUTTON_APPLY_DESC, function()
		ApplyPlan()
	end)
	bar.Menu = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	bar.Menu:SetSize(84, 22)
	bar.Menu:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.Menu:SetScript("OnClick", ShowBuildMenu)
	AddButtonTip(bar.Menu, L.TALENTS_BUILDS, L.TALENTS_PLAN_MENU_DESC)
	bar.Apply:SetPoint("LEFT", bar.Menu, "RIGHT", 4, 0)
	bar.Clear = CreatePlanButton(bar, "common-icon-redx", L.TALENTS_PLAN_BUTTON_CLEAR, L.TALENTS_PLAN_BUTTON_CLEAR_DESC, function()
		ClearPlan()
	end)
	bar.Clear:SetPoint("LEFT", bar.Apply, "RIGHT", 4, 0)
	bar.Counter = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.Counter:SetPoint("LEFT", bar.Clear, "RIGHT", 10, 0)
	bar.Counter:SetJustifyH("LEFT")
	bar.Counter:SetTextColor(PLAN_COLOR:GetRGB())
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", ShowPlanSummary)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	return bar
end

local function SetupPlanner(frame)
	-- On the outer window (visible whatever the talent frame is clipped by); it
	-- follows the talent tab: UpdatePlan shows it only while that is open.
	local parent = PlayerSpellsFrame or frame
	planBar = CreatePlanBar(parent)
	planBar:SetPoint(PLAN_BAR_POINT[1], parent, PLAN_BAR_POINT[3], PLAN_BAR_POINT[4], PLAN_BAR_POINT[5])
	planBar:Hide()
	ns:RegisterEditFrame(planBar, "TalentPlan", L.TALENTS_PLAN, { PLAN_BAR_POINT[1], parent, PLAN_BAR_POINT[3], PLAN_BAR_POINT[4], PLAN_BAR_POINT[5] })
	frame:HookScript("OnHide", function()
		planBar:Hide()
	end)
	EventRegistry:RegisterCallback("TalentButton.OnClick", OnTalentClick, Talents)
	frame:HookScript("OnShow", QueuePlanUpdate)
	if frame.SetTab then
		hooksecurefunc(frame, "SetTab", QueuePlanUpdate)
	end
	for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
		Talents:RegisterEvent(event, QueuePlanUpdate)
	end
end

---------------------------------------------------------------------------
-- Trainer spells in the spell book
---------------------------------------------------------------------------
local function SetTrainerSpellRequirement(row, entry, playerLevel)
	local trainable = entry.level <= playerLevel
	local isNew = trainable and not Talents.cdb.seenSpells[entry.key]
	local state = row.fpTrainerState
	if state.level == entry.level and state.trainable == trainable and state.isNew == isNew then
		return
	end
	state.level, state.trainable, state.isNew = entry.level, trainable, isNew
	local requirement = trainable and SPELLBOOK_TRAINABLE or SPELLBOOK_AVAILABLE_AT:format(entry.level)
	row.RequiredLevel:SetText(isNew and (requirement .. " · " .. L.TALENTS_NEW) or requirement)
	row.Button.TrainableShadow:SetShown(isNew)
	row.Button.TrainableBackplate:SetShown(trainable)
	row:UpdateTextContainer()
end

local function ShowTrainerSpellTooltip(button)
	local row = button:GetParent()
	local entry = row.fpTrainerEntry
	local playerLevel = UnitLevel("player")
	if entry.level <= playerLevel and not Talents.cdb.seenSpells[entry.key] then
		Talents.cdb.seenSpells[entry.key] = true
		SetTrainerSpellRequirement(row, entry, playerLevel)
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if not (entry.spellID and GameTooltip:SetSpellByID(entry.spellID)) then
		local name = entry.rank and ("%s (%s)"):format(entry.name, entry.rank) or entry.name
		GameTooltip_SetTitle(GameTooltip, name)
	end
	if entry.pet then
		GameTooltip_AddNormalLine(GameTooltip, L.TALENTS_PET_HEADER)
	end
	GameTooltip_AddNormalLine(GameTooltip, L.TALENTS_LEVEL:format(entry.level))
	GameTooltip:Show()
end

local function InitTrainerSpell(row, entry, playerLevel)
	local changed = row.fpTrainerEntry ~= entry
	if changed and GameTooltip:IsOwned(row.Button) then
		GameTooltip:Hide()
	end
	row.fpTrainerEntry = entry
	local button = row.Button
	if not row.fpTrainerState then
		row.fpTrainerState = {}
		-- This pool uses Blizzard's artwork. Its entries have no native slot or
		-- action data, so the original click and drag handlers have no action.
		local art = SpellBookItemMixin.ArtSet.Square
		row:ApplyBorderArt(art.inactiveBorder, art.inactiveBorderAnchors)
		button.IconMask:SetAtlas(art.iconMask)
		button.IconMask:Show()
		button.TrainableBackplate:SetAtlas(art.trainableBackplate)
		button.Icon:SetDesaturated(true)
		button.Icon:SetAlpha(row.unlearnedIconAlpha)
		button:HookScript("OnEnter", ns.Measured("Talents: trainer spell tooltip", ShowTrainerSpellTooltip))
		local function HideTooltip(owner)
			if GameTooltip:IsOwned(owner) then
				GameTooltip:Hide()
			end
		end
		button:HookScript("OnLeave", HideTooltip)
		button:HookScript("OnHide", HideTooltip)
		for _, text in ipairs({ row.Name, row.SubName, row.RequiredLevel }) do
			local face, size = text:GetFont()
			if face then
				text:SetFont(face, size, "")
			end
			text:SetShadowOffset(0, 0)
			text:SetAlpha(row.unlearnedTextAlpha)
		end
	end
	if changed then
		button.Icon:SetTexture(entry.icon or 134400)
		row.Name:SetText(entry.name)
		row.SubName:SetText(entry.rank or "")
		row.fpTrainerState.level = nil -- a new name may need different text anchors even at the same level
	end
	SetTrainerSpellRequirement(row, entry, playerLevel)
end

local SPELL_BOOK_ROW_HEIGHT = 60

-- Blizzard's pager supplies the occupied cells, including full-width header
-- and spacer rows. Read its layout so the previews only use empty space.
local function FreeSpellBookCells(pager, view, width, height, layout)
	local rows, cells = {}, {}
	local columns = pager.columnsPerRow
	local columnWidth = (width - (columns - 1) * pager.xPadding) / columns
	for _, cell in ipairs(layout or {}) do
		local index = cell.gridRow
		local row = rows[index] or {}
		rows[index] = row
		row[cell.gridColumn] = true
		if cell.isHeader or cell.isSpacer then
			row.full = true
		end
		if cell.isSpacer then
			row.height = pager.spacerSize
		end
	end

	local rowIndex, offset = 1, 0
	while offset + SPELL_BOOK_ROW_HEIGHT <= height do
		local row = rows[rowIndex]
		if not row or not row.full then
			for column = 1, columns do
				if not row or not row[column] then
					cells[#cells + 1] = {
						x = (column - 1) * (columnWidth + pager.xPadding), y = -offset,
						width = columnWidth, view = view,
					}
				end
			end
		end
		offset = offset + (row and row.height or SPELL_BOOK_ROW_HEIGHT) + pager.yPadding
		rowIndex = rowIndex + 1
	end
	return cells
end

local function SpellBookLayout(pager, nativePages, previous)
	local views = pager.viewsPerPage
	local geometry = { nativePages, views, pager.columnsPerRow, pager.xPadding, pager.yPadding, pager.spacerSize or 0 }
	local widths, heights = {}, {}
	for index = 1, views do
		local view = pager.ViewFrames[index]
		widths[index], heights[index] = view:GetWidth(), view:GetHeight()
		geometry[#geometry + 1] = widths[index]
		geometry[#geometry + 1] = heights[index]
	end
	local signature = table.concat(geometry, ":")
	if previous and previous.source == pager.viewDataList and previous.signature == signature then
		return previous
	end
	local layout = { source = pager.viewDataList, signature = signature, emptyPage = {}, pages = {}, capacity = 0 }
	for index = 1, views do
		for _, cell in ipairs(FreeSpellBookCells(pager, pager.ViewFrames[index], widths[index], heights[index])) do
			layout.emptyPage[#layout.emptyPage + 1] = cell
		end
	end
	for page = 1, nativePages do
		local cells = {}
		layout.pages[page] = { firstItem = layout.capacity + 1, cells = cells }
		for index = 1, views do
			local occupied = pager.viewDataList[(page - 1) * views + index]
			for _, cell in ipairs(FreeSpellBookCells(pager, pager.ViewFrames[index], widths[index], heights[index], occupied)) do
				cells[#cells + 1] = cell
			end
		end
		layout.capacity = layout.capacity + #cells
	end
	return layout
end

local function TrainerSpellsForCategory(book, category, playerSpells, petSpells)
	local petBank = Enum.SpellBookSpellBank.Pet
	if category:GetSpellBank() == petBank then
		return petSpells
	end
	local items = playerSpells[category.skillLineIndex] or {}
	if category.skillLineIndex ~= Enum.SpellBookSkillLineIndex.General or #petSpells == 0 then
		return items
	end
	for _, tab in ipairs(book.categoryMixins) do
		if tab:GetSpellBank() == petBank and tab:IsAvailable() then
			return items
		end
	end
	local combined = {}
	for _, entry in ipairs(items) do combined[#combined + 1] = entry end
	for _, entry in ipairs(petSpells) do combined[#combined + 1] = entry end
	SortTrainerSpells(combined)
	return combined
end

local function CreateContinuationCover(parent, book)
	local cover = CreateFrame("Frame", nil, parent)
	cover:SetAllPoints()
	cover:SetClipsChildren(true)
	cover:SetFrameLevel(parent:GetFrameLevel() + 1)
	cover:EnableMouse(true)
	cover:EnableMouseWheel(true)
	cover:Hide()
	-- Crop the original parchment to the paged area. The search and tabs above
	-- it remain usable while showing a continuation page.
	local art = CreateFrame("Frame", nil, cover)
	art:SetAllPoints(book)
	local compact = art:CreateTexture(nil, "BACKGROUND")
	compact:SetAllPoints()
	compact:SetAtlas("spellbook-Page-Right-C60")
	local left = art:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", art, "BOTTOM")
	left:SetAtlas("spellbook-Page-Left-C60")
	local right = art:CreateTexture(nil, "BACKGROUND")
	right:SetPoint("TOPLEFT", art, "TOP")
	right:SetPoint("BOTTOMRIGHT")
	right:SetAtlas("spellbook-Page-Right-C60")
	return cover, function()
		local minimized = book.isMinimized == true
		compact:SetShown(minimized)
		left:SetShown(not minimized)
		right:SetShown(not minimized)
	end
end

local queueTrainerBook
local function SetupSpellsBook(book)
	local pager = book.PagedSpellsFrame
	if not (pager and type(pager.ViewFrames) == "table" and type(pager.columnsPerRow) == "number") then
		return
	end

	local layer = CreateFrame("Frame", nil, book)
	layer:SetAllPoints(pager)
	layer:SetFrameLevel(ns.Number(pager:GetFrameLevel(), 0) + 50)
	local cover, UpdateParchment = CreateContinuationCover(layer, book)
	local rows = {}
	local nativeControls = pager.PagingControls
	local nextPage = CreateFrame("Button", nil, layer, "PagingControlsNextPageButtonTemplate")
	nextPage:SetPoint("CENTER", nativeControls.NextPageButton)
	nextPage:SetFrameLevel(layer:GetFrameLevel() + 5)
	local footer = CreateFrame("Frame", nil, layer)
	footer:SetAllPoints()
	footer:SetFrameLevel(layer:GetFrameLevel() + 4)
	local previousPage = CreateFrame("Button", nil, footer, "PagingControlsPrevPageButtonTemplate")
	previousPage:SetPoint("CENTER", nativeControls.PrevPageButton)
	local pageNumber = footer:CreateFontString(nil, "ARTWORK", "SystemFont_Med3")
	pageNumber:SetPoint("RIGHT", nativeControls.PageText, "RIGHT")
	pageNumber:SetTextColor(SPELLBOOK_FONT_COLOR:GetRGB())
	local face, size = pageNumber:GetFont()
	if face then
		pageNumber:SetFont(face, size, "")
	end
	pageNumber:SetShadowOffset(0, 0)

	local extraPage, extraPages, queued = 0, 0, false
	local playerSpells, petSpells, spellScan
	local layout, coveringPage, rowUpdate
	local function RefreshTrainerBook()
		queued = false
		local category = book:IsVisible() and book:GetActiveCategoryMixin()
		if not (Talents.db.enabled and category and pager.viewDataList) then
			layer:Hide()
			return
		end
		if not playerSpells then
			if not spellScan then
				local ticker = CollectTrainerSpells(function(spells)
					spellScan, playerSpells = nil, spells
					queueTrainerBook()
				end)
				if not playerSpells then
					spellScan = ticker
				end
			end
			return
		end
		petSpells = petSpells or CollectPetTrainerSpells()
		local items = TrainerSpellsForCategory(book, category, playerSpells, petSpells)
		if #items == 0 then
			layer:Hide()
			return
		end

		local nativePage, nativePages = nativeControls:GetCurrentPage(), nativeControls:GetMaxPages()
		layout = SpellBookLayout(pager, nativePages, layout)
		local fullPage = layout.emptyPage
		extraPages = #fullPage > 0 and math.max(0, math.ceil((#items - layout.capacity) / #fullPage)) or 0
		extraPage = math.min(extraPage, extraPages)

		layer:Show()
		local pageCells, firstItem
		if extraPage > 0 then
			pageCells = fullPage
			firstItem = layout.capacity + (extraPage - 1) * #fullPage + 1
		else
			local page = layout.pages[nativePage]
			pageCells, firstItem = page.cells, page.firstItem
		end
		if extraPages > 0 then
			local continuation = extraPage > 0
			if continuation ~= coveringPage then
				coveringPage = continuation
				cover:ClearAllPoints()
				if continuation then
					cover:SetAllPoints(layer)
				else
					cover:SetPoint("TOPLEFT", nativeControls.PageText, "TOPLEFT", -1, 1)
					cover:SetPoint("BOTTOMRIGHT", nativeControls.PageText, "BOTTOMRIGHT", 1, -1)
				end
				cover:EnableMouse(continuation)
				cover:EnableMouseWheel(continuation)
			end
			local page = extraPage > 0 and nativePages + extraPage or nativePage
			pageNumber:SetFormattedText(PAGE_NUMBER_WITH_MAX, page, nativePages + extraPages)
			UpdateParchment()
		end
		cover:SetShown(extraPages > 0)
		footer:SetShown(extraPages > 0)
		previousPage:SetShown(extraPage > 0)
		nextPage:SetShown(extraPage > 0 or (nativePage == nativePages and extraPages > 0))
		nextPage:SetEnabled(extraPage < extraPages)

		local count = math.max(0, math.min(#pageCells, #items - firstItem + 1))
		local playerLevel = UnitLevel("player")
		for index, row in ipairs(rows) do
			if index > count or row.fpTrainerCell ~= pageCells[index] or row.fpTrainerEntry ~= items[firstItem + index - 1] then
				row:Hide()
			end
		end
		if count == 0 then
			return
		end
		local function UpdateRow(index)
			local row = rows[index]
			if not row then
				row = CreateFrame("Frame", nil, layer, "SpellBookItemTemplate")
				row.fpTrainerState = false
				row:SetFrameLevel(layer:GetFrameLevel() + 3)
				rows[index] = row
			end
			local cell = pageCells[index]
			if row.fpTrainerCell ~= cell then
				row.fpTrainerCell = cell
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", cell.view, "TOPLEFT", cell.x, cell.y)
				row:SetSize(cell.width, SPELL_BOOK_ROW_HEIGHT)
			end
			InitTrainerSpell(row, items[firstItem + index - 1], playerLevel)
			row:Show()
		end
		local finished = false
		local ticker = ns.RunSliced("Talents: draw spellbook rows", count, UpdateRow, function()
			rowUpdate, finished = nil, true
		end)
		if not finished then
			rowUpdate = ticker
		end
	end

	local function ChangeContinuationPage(delta)
		local page = math.min(extraPages, math.max(0, extraPage + delta))
		if page == extraPage then
			return
		end
		extraPage = page
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
		queueTrainerBook()
	end
	nextPage:SetScript("OnClick", ns.Measured("Talents: next spellbook page", function()
		ChangeContinuationPage(1)
	end))
	previousPage:SetScript("OnClick", ns.Measured("Talents: previous spellbook page", function()
		ChangeContinuationPage(-1)
	end))
	cover:SetScript("OnMouseWheel", ns.Measured("Talents: turn spellbook page", function(_, delta)
		if delta > 0 then
			ChangeContinuationPage(-1)
		elseif nextPage:IsEnabled() then
			ChangeContinuationPage(1)
		end
	end))

	queueTrainerBook = function(invalidate)
		if invalidate then
			if spellScan then
				spellScan:Cancel()
				spellScan = nil
			end
			playerSpells, petSpells = nil, nil
		end
		if rowUpdate then
			rowUpdate:Cancel()
			rowUpdate = nil
		end
		if not queued and book:IsVisible() then
			queued = true
			ns.After("Talents: refresh trainer spells", 0, RefreshTrainerBook)
		end
	end

	local function NativePageChanged()
		extraPage = 0
		queueTrainerBook()
	end
	EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
		ns.Measured("Talents: spellbook page changed", NativePageChanged), Talents)
	hooksecurefunc(book, "OnActiveCategoryChanged", ns.Measured("Talents: spellbook category changed", NativePageChanged))
	book:HookScript("OnShow", ns.Measured("Talents: spellbook opened", function()
		extraPage = 0
		queueTrainerBook()
	end))
	book:HookScript("OnHide", ns.Measured("Talents: spellbook closed", function()
		extraPage = 0
		if rowUpdate then
			rowUpdate:Cancel()
			rowUpdate = nil
		end
		if spellScan then
			spellScan:Cancel()
			spellScan = nil
		end
		layer:Hide()
	end))
	layer:Hide()
end

function Talents:Update()
	if queueTrainerBook then
		queueTrainerBook(true)
	end
end

function Talents:OnLogin()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		if PlayerSpellsFrame then
			if PlayerSpellsFrame.SpellBookFrame then
				SetupSpellsBook(PlayerSpellsFrame.SpellBookFrame)
				self:Update()
			end
			if TalentsFrame() then
				SetupPlanner(TalentsFrame())
			end
		end
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", self.Update)
	self:RegisterEvent("TRAINER_SHOW", function()
		ns.After("Talents: OnLogin (timer)", 0.3, function()
			ScanTrainer()
			self:Update()
		end)
	end)
	self:RegisterEvent("SPELLS_CHANGED", self.Update)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, _, unit)
		if unit == "player" then
			self:Update()
		end
	end)
	if playerClass == "HUNTER" then
		self:RegisterEvent("UNIT_PET", function(_, _, unit)
			if unit == "player" then
				self:Update()
			end
		end)
	end
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
		"ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		ns:RegisterEvent(event, Talents.UpdateUnspent, Talents.QueueUnspent)
	end
	Talents.QueueUnspent()
end

---------------------------------------------------------------------------
-- Unspent talent points: a number on the talent button of the micro menu
---------------------------------------------------------------------------
-- Points the player can still spend: the currencies of the active talent tree (the game's own count).
function Talents.UnspentPoints()
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	local info = configID and C_Traits.GetConfigInfo(configID)
	local treeID = info and info.treeIDs and info.treeIDs[1]
	if not treeID then
		return 0
	end
	local points = 0
	for _, currency in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
		points = points + math.max(ns.Number(currency.quantity, 0), 0)
	end
	return points
end

-- The name of the talent the plan gives the next free point to, or nil.
function Talents.NextPlanned()
	if not (Talents.db.enabled and Talents.db.planner and Talents.db.planNext) then
		return nil
	end
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	if not configID then
		return nil
	end
	local plan = CurrentPlan()
	for _, nodeID in ipairs(CurrentOrder()) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		if node and ns.Number(node.ranksPurchased, 0) < (plan[nodeID] or 0) then
			local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
			local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
			local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local name = definition and (definition.overrideName or (definition.spellID and C_Spell.GetSpellName(definition.spellID)))
			return type(name) == "string" and name ~= "" and name or nil
		end
	end
	return nil
end

-- Tooltip of the talent button in the micro menu: with a free point, the talent the plan names next.
local function AddNextToTooltip(self)
	local name = GameTooltip:GetOwner() == self and Talents.UnspentPoints() > 0 and Talents.NextPlanned()
	if name then
		GameTooltip_AddColoredLine(GameTooltip, L.TALENTS_PLAN_NEXT:format(name), PLAN_COLOR)
		GameTooltip:Show()
	end
end

function Talents.UpdateUnspent()
	local button = PlayerSpellsMicroButton or TalentMicroButton
	if not button then
		return
	end
	if Talents.nextHooked ~= button then
		Talents.nextHooked = button
		button:HookScript("OnEnter", ns.Measured("Talents: next planned talent (tooltip)", AddNextToTooltip))
	end
	local points = Talents.db.unspentBadge and Talents.UnspentPoints() or 0
	local badge = Talents.unspentBadge
	if points <= 0 then
		if badge then
			badge:Hide()
		end
		return
	end
	if not badge then
		badge = CreateFrame("Frame", nil, button)
		badge:SetSize(18, 18)
		badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 4, 2)
		badge:SetFrameLevel(button:GetFrameLevel() + 5)
		badge.Back = badge:CreateTexture(nil, "ARTWORK")
		badge.Back:SetAllPoints()
		badge.Back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		badge.Back:SetVertexColor(0.75, 0.05, 0.05)
		badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		badge.Text:SetPoint("CENTER", 0, 0)
		badge.Pulse = badge:CreateAnimationGroup()
		badge.Pulse:SetLooping("BOUNCE")
		local fade = badge.Pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.55)
		fade:SetDuration(0.8)
		badge:EnableMouse(false) -- clicks and the tooltip stay with the button
		Talents.unspentBadge = badge
	end
	badge.Text:SetText(points)
	badge:Show()
	badge.Pulse:Play()
end

function Talents.QueueUnspent()
	if not Talents.unspentPending then
		Talents.unspentPending = true
		ns.After("Talents: QueueUnspent (timer)", 0.5, function()
			Talents.unspentPending = false
			Talents.UpdateUnspent()
		end)
	end
end

-- /fp talente: where the plan bar is and whether it shows.
function Talents:PrintStatus()
	local treeFrame = TalentsFrame()
	local treeConfig = treeFrame and treeFrame:IsVisible() and treeFrame.GetConfigID and treeFrame:GetConfigID()
	if treeConfig then
		local nodes, rowOf = TreeState(treeFrame, treeConfig)
		local count, rowSet, specSet = 0, {}, {}
		for _, node in pairs(nodes) do
			count = count + 1
			rowSet[rowOf[node.posY] or 0] = true
			specSet[node.fpSpec or 0] = true
		end
		local rowsN, specsN = 0, 0
		for _ in pairs(rowSet) do rowsN = rowsN + 1 end
		for _ in pairs(specSet) do specsN = specsN + 1 end
		ns.PrintAlways(L.TALENTS_STATUS_TREE, count, rowsN, specsN)
	end
	local frame = TalentsFrame()
	local bar = planBar
	local point, relativeTo, relative, x, y
	if bar then
		point, relativeTo, relative, x, y = bar:GetPoint(1)
	end
	ns.PrintAlways(L.TALENTS_STATUS, frame and "ja" or "nein", frame and frame:IsVisible() and "ja" or "nein", bar and "ja" or "nein",
		bar and bar:IsShown() and "ja" or "nein", bar and bar:GetParent() and bar:GetParent():GetName() or "?",
		tostring(point), tostring(relativeTo and relativeTo:GetName() or relative), ns.Number(x, 0), ns.Number(y, 0), Talents.db.planner and "ja" or "nein")
end

function Talents:OnOptionChanged()
	self:Update()
	Talents.UpdateUnspent()
	QueuePlanUpdate()
end

Talents.options = {
	{ key = "enabled", type = "toggle", name = L.TALENTS_ENABLE, desc = L.TALENTS_ENABLE_DESC },
	{ key = "planner", type = "toggle", name = L.TALENTS_PLANNER, desc = L.TALENTS_PLANNER_DESC },
	{ key = "planNext", type = "toggle", name = L.TALENTS_PLAN_ORDER, desc = L.TALENTS_PLAN_ORDER_DESC },
	{ key = "unspentBadge", type = "toggle", name = L.TALENTS_UNSPENT, desc = L.TALENTS_UNSPENT_DESC },
}

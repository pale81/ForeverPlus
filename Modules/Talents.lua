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
		trainer = {}, -- classFile -> { { name, rank, icon, level }, ... } from the class trainer
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
			lines[#lines + 1] = info
		end
	end
	return lines
end

-- name|rank of every spell the player knows.
local function KnownSpellKeys()
	local known = {}
	local bank = Enum.SpellBookSpellBank.Player
	for _, info in ipairs(SpellBookLines()) do
		for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
			local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
			if item and item.spellID and IsKnown(item.spellID) then
				known[SpellKey(item.name, item.subName)] = true
			end
		end
	end
	return known
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
	for _, info in ipairs(SpellBookLines()) do
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
			found[#found + 1] = { name = name, rank = rank ~= "" and rank or nil, icon = icon, level = level,
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

-- All entries: { key, level, name, rank, icon, known }, by level.
local function CollectSpells()
	local byLevel, seen = {}, {}
	local function Add(level, key, name, rank, icon, known)
		if level and level > 0 and not seen[key] then
			seen[key] = true
			byLevel[level] = byLevel[level] or {}
			tinsert(byLevel[level], { key = key, level = level, name = name, rank = rank, icon = icon, known = known })
		end
	end
	local function AddSpell(level, spellID)
		if not spellID then
			return
		end
		local name = C_Spell.GetSpellName(spellID) or ("spell:" .. spellID)
		local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
		rank = rank ~= "" and rank or nil
		Add(level, SpellKey(name, rank), name, rank, C_Spell.GetSpellTexture(spellID), IsKnown(spellID))
	end
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	for level = 1, maxLevel do
		for _, spellID in ipairs(C_SpellBook.GetCurrentLevelSpells(level) or {}) do
			AddSpell(level, spellID)
		end
	end
	local bank = Enum.SpellBookSpellBank.Player
	for _, info in ipairs(SpellBookLines()) do
		for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
			local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
			if item and item.spellID then
				AddSpell(C_SpellBook.GetSpellBookItemLevelLearned(index, bank), item.spellID)
			end
		end
	end
	local known = KnownSpellKeys()
	for _, entry in ipairs(TrainerList()) do
		local key = SpellKey(entry.name, entry.rank)
		Add(entry.level, key, entry.name, entry.rank, entry.icon, known[key] or false)
	end
	return byLevel
end

-- Spells the player could learn at the trainer right now.
local function LearnableSpells(byLevel)
	local playerLevel = UnitLevel("player")
	local list = {}
	for level, spells in pairs(byLevel or CollectSpells()) do
		if level <= playerLevel then
			for _, entry in ipairs(spells) do
				if not entry.known then
					list[#list + 1] = entry.key
				end
			end
		end
	end
	return list
end

local spellsButton

-- The button sparkles while there is something new to learn.
local function UpdateSpellsGlow()
	if not spellsButton then
		return
	end
	if not Talents.db.enabled then
		spellsButton.Alert:SetShown(false)
		return
	end
	local seen = Talents.cdb.seenSpells
	local new = false
	for _, key in ipairs(LearnableSpells()) do
		if not seen[key] then
			new = true
			break
		end
	end
	spellsButton.Alert:SetShown(new and Talents.db.enabled)
end

-- The abilities of the hunter's pet by level, from the pet trainer's list
-- (stored at each visit) and the pet's own spell book while it is out.
local function PetKnownKeys()
	local known = {}
	local bank = Enum.SpellBookSpellBank.Pet
	if C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() then
		for index = 1, C_SpellBook.HasPetSpells() or 0 do
			local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
			if item and item.spellID and item.name then
				known[SpellKey(item.name, item.subName)] = true
			end
		end
	end
	return known
end

local function SpellRow(entry, known, isNew, level)
	local name = entry.rank and ("%s (%s)"):format(entry.name, entry.rank) or entry.name
	return {
		icon = entry.icon or 134400,
		text = known and GRAY_FONT_COLOR:WrapTextInColorCode(name) or name,
		right = isNew and GREEN_FONT_COLOR:WrapTextInColorCode(L.TALENTS_NEW) or nil,
		-- A row is only there to be looked at: pointing at it counts as seen.
		onClick = function() end,
		tooltip = function(tooltip)
			if isNew and entry.key then
				Talents.cdb.seenSpells[entry.key] = true
				UpdateSpellsGlow()
			end
			GameTooltip_SetTitle(tooltip, name)
			GameTooltip_AddNormalLine(tooltip, L.TALENTS_LEVEL:format(level))
		end,
	}
end

local function AddPetAbilities(items)
	items[#items + 1] = { text = L.TALENTS_PET_HEADER }
	local list = PetTrainerList()
	if #list == 0 then
		items[#items + 1] = { text = L.TALENTS_VISIT_PET_TRAINER, line = false }
		return
	end
	local known = PetKnownKeys()
	local byLevel, levels = {}, {}
	for _, entry in ipairs(list) do
		if not byLevel[entry.level] then
			byLevel[entry.level] = {}
			levels[#levels + 1] = entry.level
		end
		tinsert(byLevel[entry.level], entry)
	end
	table.sort(levels)
	for _, level in ipairs(levels) do
		items[#items + 1] = { text = L.TALENTS_LEVEL:format(level), line = false }
		table.sort(byLevel[level], function(a, b)
			return a.name < b.name
		end)
		for _, entry in ipairs(byLevel[level]) do
			items[#items + 1] = SpellRow(entry, entry.known or known[SpellKey(entry.name, entry.rank)], false, level)
		end
	end
end

-- The spells by level as a list: spells that can be learned now and were not seen yet are marked
-- "new"; the button of the window sparkles until they were pointed at or learned.
local function SpellItems()
	local byLevel = CollectSpells()
	local seen = Talents.cdb.seenSpells
	local playerLevel = UnitLevel("player")
	local items = {}
	if #TrainerList() == 0 then
		items[#items + 1] = { text = L.TALENTS_VISIT_TRAINER, line = false }
	end
	local levels = {}
	for level in pairs(byLevel) do
		levels[#levels + 1] = level
	end
	table.sort(levels)
	for _, level in ipairs(levels) do
		items[#items + 1] = { text = L.TALENTS_LEVEL:format(level) }
		table.sort(byLevel[level], function(a, b)
			return a.name < b.name
		end)
		for _, entry in ipairs(byLevel[level]) do
			local isNew = not entry.known and level <= playerLevel and not seen[entry.key]
			items[#items + 1] = SpellRow(entry, entry.known, isNew, level)
		end
	end
	if #levels == 0 then
		items[#items + 1] = { text = L.TALENTS_NO_SPELLS, line = false }
	end
	if playerClass == "HUNTER" then
		AddPetAbilities(items)
	end
	return items
end

local function ShowSpellsByLevel(owner)
	ns.ShowPopupList(owner, function()
		return { title = L.TALENTS_SPELLS, items = SpellItems(), width = 340, maxRows = 22 }
	end, "Spells")
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
local function TalentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local ApplyPlan, ClearPlan, ImportPlan, ExportPlan, SavePlanTemplate, ApplyTemplate -- planner, defined below
local BuildList, ActiveBuild, ActivatePlan, NewPlan, RenamePlan, RemovePlan
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
		local ok, description = pcall(C_Traits.GetTraitDescription, entryID, planned)
		if ok and type(description) == "string" and not ns.Secret(description) then
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
local function StorePlan(name, ranks)
	local list, build = BuildList(), ActiveBuild()
	if next(build.ranks) == nil then
		build.name = ns.TalentBuilds.UniqueName(list, name, build)
		build.ranks, build.order = ranks, {}
	else
		ActivatePlan(ns.TalentBuilds.Add(list, Talents.db, name, ranks).id)
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
	local plan = CurrentPlan()
	local planned = plan[nodeID] or 0
	local nodes, rowOf, names = TreeState(frame, configID)
	local problem
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
		problem = CheckPlan(nodes, rowOf, names, plan)
		plan[nodeID] = old
		if problem then
			Refuse(L.TALENTS_PLAN_REMOVE_BLOCKED)
			return
		end
		ns.TalentOrder.RemoveLast(CurrentOrder(), nodeID)
	elseif button.CanRefundRank and button:CanRefundRank() then
		return -- Blizzard refunds a staged rank with this click
	else
		local target = math.max(planned, node.ranksPurchased or 0) + 1
		if target > node.maxRanks then
			return
		end
		-- The plan counts the learned points too.
		if TotalPoints(nodes, plan) - math.max(planned, learned) + target > PLAN_POINTS then
			Refuse(L.TALENTS_PLAN_FULL:format(PLAN_POINTS, PLAN_MAX_LEVEL))
			return
		end
		problem = CheckNode(nodes, rowOf, names, plan, node, target)
		if problem then
			Refuse(problem)
			return
		end
		planned = target
		-- The new point is the last step; what was planned before gets its steps first.
		local order = PlanOrder(nodes, rowOf, names, plan)
		order[#order + 1] = nodeID
	end
	plan[nodeID] = planned > learned and planned or nil
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
			local ok, description = pcall(C_Traits.GetTraitDescription, entryID, rank)
			if ok and type(description) == "string" and not ns.Secret(description) then
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
-- Buttons below the talent window
---------------------------------------------------------------------------
local buttons
local bookButton

-- Below level 10 the game hides the talent tab; the spell list then sits at the top of the window instead.
local function UpdateBookButton()
	local frame = PlayerSpellsFrame
	if not bookButton or not frame then
		return
	end
	local ok, available = pcall(frame.IsTabAvailable, frame, frame.talentTabID)
	bookButton:SetShown(Talents.db.enabled and ok and not available and true or false)
end

local function CreateButtons()
	-- Inside the talent window, on the bottom bar right of Blizzard's buttons.
	local parent = TalentsFrame() or PlayerSpellsFrame
	local anchor = parent.Background or parent
	local spells = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	spells:SetSize(150, 22)
	spells:SetFrameLevel(ns.Number(parent:GetFrameLevel(), 0) + 1010)
	spells:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -24, 8)
	spells:SetText(L.TALENTS_SPELLS)
	spells:SetScript("OnClick", ShowSpellsByLevel)
	-- The button glows (a soft pulse) while there is something new to learn.
	local alert = CreateFrame("Frame", nil, spells)
	alert:SetAllPoints(spells)
	alert:SetFrameLevel(spells:GetFrameLevel() + 2)
	alert:EnableMouse(false)
	local glow = alert:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	glow:SetTexture([[Interface\Buttons\UI-Common-MouseHilight]])
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.82, 0.1)
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.2)
	fade:SetToAlpha(1)
	fade:SetDuration(0.8)
	fade:SetSmoothing("IN_OUT")
	alert:SetScript("OnShow", function()
		pulse:Play()
	end)
	alert:SetScript("OnHide", function()
		pulse:Stop()
	end)
	alert:Hide()
	spells.Alert = alert
	spellsButton = spells
	buttons = { spells }

	local topButton = PlayerSpellsFrame.MaximizeMinimizeButton or PlayerSpellsFrame.CloseButton
	bookButton = CreateFrame("Button", nil, PlayerSpellsFrame, "UIPanelButtonTemplate")
	bookButton:SetSize(150, 22)
	bookButton:SetFrameLevel(ns.Number(PlayerSpellsFrame:GetFrameLevel(), 0) + 5600)
	if topButton then
		bookButton:SetPoint("RIGHT", topButton, "LEFT", -8, 0)
	else
		bookButton:SetPoint("TOPRIGHT", PlayerSpellsFrame, "TOPRIGHT", -60, -4)
	end
	bookButton:SetText(L.TALENTS_SPELLS)
	bookButton:SetScript("OnClick", ShowSpellsByLevel)
	bookButton:Hide()
end

function Talents:Update()
	for _, button in ipairs(buttons or {}) do
		button:SetShown(self.db.enabled)
	end
	UpdateSpellsGlow()
	UpdateBookButton()
end

local glowPending = false
local function QueueGlowUpdate()
	if not glowPending then
		glowPending = true
		ns.After("Talents: QueueGlowUpdate (timer)", 1, function()
			glowPending = false
			UpdateSpellsGlow()
			UpdateBookButton()
		end)
	end
end

function Talents:OnLogin()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		if PlayerSpellsFrame then
			CreateButtons()
			self:Update()
			PlayerSpellsFrame:HookScript("OnShow", UpdateSpellsGlow)
			PlayerSpellsFrame:HookScript("OnShow", UpdateBookButton)
			if PlayerSpellsFrame.SetTab then
				hooksecurefunc(PlayerSpellsFrame, "SetTab", UpdateBookButton)
			end
			if TalentsFrame() then
				SetupPlanner(TalentsFrame())
			end
		end
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", QueueGlowUpdate)
	self:RegisterEvent("TRAINER_SHOW", function()
		ns.After("Talents: OnLogin (timer)", 0.3, function()
			ScanTrainer()
			QueueGlowUpdate()
		end)
	end)
	self:RegisterEvent("SPELLS_CHANGED", QueueGlowUpdate)
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

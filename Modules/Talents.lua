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
		templates = {}, -- classFile -> { { name =, points =, ranks = "nodeID:rank,…" }, ... } own templates
		plans = {}, -- "classFile:specID" -> { [nodeID] = planned ranks }
		trainer = {}, -- classFile -> { { name, rank, icon, level }, ... } from the class trainer
		petTrainer = {}, -- classFile -> { { name, rank, icon, level, known }, ... } from the pet trainer (hunters)
	},
	charDefaults = {
		seenSpells = {}, -- learnable spells already shown to the player
	},
})

local MAX_APPLY_PASSES = 10
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

-- Buys ranks until every node has its wanted ranks or nothing changes;
-- prerequisites need several passes. Nodes higher up the tree go first.
local function PurchaseTowards(configID, wanted, selection, groupOf)
	-- One tree after the other (groupOf: node -> position of its tree, 1 = the tree with the most
	-- planned points), in a tree from the top row down and in a row from left to right.
	local groups, keys = {}, {}
	for nodeID in pairs(wanted) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		local key = groupOf and groupOf[nodeID] or 0
		if not groups[key] then
			groups[key] = {}
			keys[#keys + 1] = key
		end
		table.insert(groups[key], { nodeID = nodeID, y = node and node.posY or 0, x = node and node.posX or 0 })
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local order = groups[key]
		table.sort(order, function(a, b)
			if a.y ~= b.y then
				return a.y < b.y
			end
			return a.x < b.x
		end)
		-- Several passes: a talent behind an arrow or a row only opens after the ones before it.
		for _ = 1, MAX_APPLY_PASSES do
			local progress = false
			for _, entry in ipairs(order) do
				local nodeID, ranks = entry.nodeID, wanted[entry.nodeID]
				local node = C_Traits.GetNodeInfo(configID, nodeID)
				if node and node.ranksPurchased < ranks then
					if node.type == Enum.TraitNodeType.Selection and selection and selection[nodeID] then
						if C_Traits.SetSelection(configID, nodeID, selection[nodeID]) then
							progress = true
						end
					else
						while node.ranksPurchased < ranks and C_Traits.PurchaseRank(configID, nodeID) do
							progress = true
							node = C_Traits.GetNodeInfo(configID, nodeID)
						end
					end
				end
			end
			if not progress then
				break
			end
		end
	end
end

local PLAN_BUTTON_SIZE = 26

-- Import (templates or an import code), export (as an import code) and saving the plan as a template.
local function ShowBuildMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L.TALENTS_BUILDS)
		local import = root:CreateButton(L.TALENTS_IMPORT)
		local presets = ns.TalentPresets and ns.TalentPresets[playerClass]
		if presets and #presets > 0 then
			import:CreateTitle(L.TALENTS_TEMPLATE_STANDARD)
			for _, preset in ipairs(presets) do
				local name = GetLocale() == "deDE" and preset.de or preset.en
				import:CreateButton(("%s (%s)"):format(name, preset.points), function()
					ApplyTemplate(preset, name)
				end)
			end
		end
		local own = Talents.db.templates[playerClass] or {}
		if #own > 0 then
			import:CreateDivider()
			import:CreateTitle(L.TALENTS_TEMPLATE_OWN)
			for index, template in ipairs(own) do
				local item = import:CreateButton(("%s (%d)"):format(template.name, template.points))
				item:CreateButton(L.TALENTS_TEMPLATE_USE, function()
					ApplyTemplate(template, template.name)
				end)
				item:CreateButton(DELETE, function()
					tremove(own, index)
				end)
			end
		end
		import:CreateDivider()
		import:CreateButton(L.TALENTS_IMPORT_CODE, ImportPlan)
		root:CreateButton(L.TALENTS_EXPORT_PLAN, ExportPlan)
		root:CreateButton(L.TALENTS_SAVE_TEMPLATE, SavePlanTemplate)
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

local function CurrentPlan()
	local key = ("%s:%s"):format(playerClass, PlayerUtil.GetCurrentSpecID() or 0)
	local plans = Talents.db.plans
	plans[key] = plans[key] or {}
	return plans[key]
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
		-- Ring around a talent the plan has unlocked (Blizzard still shows it locked).
		overlay.Ring = button:CreateTexture(nil, "OVERLAY", nil, 5)
		overlay.Ring:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		overlay.Ring:SetBlendMode("ADD")
		overlay.Ring:SetPoint("CENTER", button.Icon or button, "CENTER", 0, 0)
		overlay.Ring:SetSize(70, 70)
		overlay.Ring:SetVertexColor(PLAN_COLOR.r, PLAN_COLOR.g, PLAN_COLOR.b, 0.85)
		overlay.Ring:Hide()
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
		-- Plain lines: appended tooltip data would pile up with every change of the plan.
		local ok, description = pcall(C_Traits.GetTraitDescription, entryID, planned)
		if ok and type(description) == "string" and not (issecretvalue and issecretvalue(description)) then
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
	local nodes, rowOf, names
	if enabled and configID then
		nodes, rowOf, names = TreeState(frame, configID)
	end
	for button in frame:EnumerateAllTalentButtons() do
		HookPlanTooltip(button)
		local nodeID = button.GetNodeID and button:GetNodeID()
		local planned = enabled and nodeID and plan[nodeID]
		local unlocked = nodes and nodeID and nodes[nodeID] and UnlockedByPlan(nodes[nodeID], nodes, rowOf, names, plan)
		if planned or unlocked or button.fpPlan then
			local overlay = PlanOverlay(button)
			local node = (planned or unlocked) and configID and C_Traits.GetNodeInfo(configID, nodeID)
			if node and planned then
				overlay.Text:SetFormattedText("%d/%d", planned, node.maxRanks)
				overlay.Text:Show()
				overlay.Tint:SetShown(planned > node.ranksPurchased)
			else
				overlay.Text:Hide()
				overlay.Tint:Hide()
			end
			overlay.Ring:SetShown(unlocked and true or false)
		end
	end
	if planBar then
		local points = nodes and TotalPoints(nodes, plan) or 0
		local pending = nodes and HasPending(nodes, plan) or false
		planBar:SetShown(enabled and true or false)
		planBar.Counter:SetText(points > 0 and L.TALENTS_PLAN_COUNTER:format(points, PLAN_POINTS, FIRST_TALENT_LEVEL - 1 + points) or "")
		planBar:SetWidth(PLAN_BUTTON_SIZE * 2 + 14 + ns.Number(planBar.Counter:GetStringWidth(), 0))
		planBar.Apply:SetEnabled(pending)
		planBar.Clear:SetEnabled(next(plan) ~= nil)
	end
end

-- Own templates: the plan (what is planned or learned) saved under a name.
local function TemplateList()
	local list = Talents.db.templates[playerClass]
	if not list then
		list = {}
		Talents.db.templates[playerClass] = list
	end
	return list
end

local function StoreTemplate(name, ranks)
	local points = 0
	for rank in ranks:gmatch("%d+:(%d+)") do
		points = points + tonumber(rank)
	end
	if name == "" then
		name = date("%d.%m. %H:%M")
	end
	local list = TemplateList()
	list[#list + 1] = { name = name, points = points, ranks = ranks }
	ns.Print(L.TALENTS_TEMPLATE_SAVED:format(name, points))
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
	ns.ShowEditWindow("TemplateName", L.TALENTS_TEMPLATE_SAVE, "", SAVE, function(name)
		StoreTemplate(name, ranks)
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
		C_Timer.After(0, function()
			updatePending = false
			UpdatePlan()
		end)
	end
end

-- Puts a template (standard distribution or own) into the plan of the current specialisation:
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
	local current = CurrentPlan()
	wipe(current)
	for nodeID, rank in pairs(plan) do
		current[nodeID] = rank
	end
	QueuePlanUpdate()
	ns.Print(L.TALENTS_TEMPLATE_DONE:format(name, points))
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
		local current, points, count = CurrentPlan(), 0, 0
		wipe(current)
		for nodeID, rank in pairs(imported) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			local maxRanks = node and node.maxRanks or 0
			if maxRanks > 0 then
				current[nodeID] = math.min(rank, maxRanks)
				points, count = points + current[nodeID], count + 1
			end
		end
		QueuePlanUpdate()
		if count == 0 then
			ns.Print(L.TALENTS_IMPORT_EMPTY)
		else
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
		if GameTooltip:GetOwner() == button and button.SetTooltipInternal then
			HookPlanTooltip(button)
			button:SetTooltipInternal()
		end
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
	end
	plan[nodeID] = planned > learned and planned or nil
	QueuePlanUpdate()
	-- Rebuild the open tooltip with the new planned rank.
	if GameTooltip:GetOwner() == button and button.SetTooltipInternal then
		HookPlanTooltip(button)
		button:SetTooltipInternal()
	end
end

-- Buys the planned ranks the points allow; Blizzard's talent window shows
-- them as pending until they are confirmed with its button.
function ApplyPlan()
	local configID = C_ClassTalents.GetActiveConfigID()
	local frame = TalentsFrame()
	if InCombatLockdown() or not configID or not C_SpecializationInfo.HasPlayerEarnedATalentPoint()
		or (frame and frame.IsLocked and frame:IsLocked()) then
		ns.Print(L.TALENTS_ERROR_FRAME)
		return
	end
	-- The tree with the most planned points first, then the next one with what is left.
	local plan, groupOf = CurrentPlan(), {}
	if frame and frame.EnumerateAllTalentButtons then
		local nodes = TreeState(frame, configID)
		local totals, specs = {}, {}
		for nodeID, ranks in pairs(plan) do
			local spec = nodes[nodeID] and nodes[nodeID].fpSpec or 0
			totals[spec] = (totals[spec] or 0) + ranks
		end
		for spec in pairs(totals) do
			specs[#specs + 1] = spec
		end
		table.sort(specs, function(a, b)
			if totals[a] ~= totals[b] then
				return totals[a] > totals[b]
			end
			return a < b
		end)
		local position = {}
		for index, spec in ipairs(specs) do
			position[spec] = index
		end
		for nodeID in pairs(plan) do
			groupOf[nodeID] = position[nodes[nodeID] and nodes[nodeID].fpSpec or 0] or 0
		end
	end
	PurchaseTowards(configID, plan, nil, groupOf)
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
			if ok and type(description) == "string" and not (issecretvalue and issecretvalue(description)) then
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

-- Top centre of the talent window, between the title and the tabs: two small
-- symbol buttons ("apply" tick, "clear" cross) and the counter, in the colour of the plan.
local PLAN_BAR_POINT = { "TOP", nil, "TOP", 0, -62 }

local function CreatePlanBar(frame)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetSize(330, 24)
	bar:SetFrameLevel(ns.Number(frame:GetFrameLevel(), 0) + 1010)
	bar:SetFrameStrata("HIGH")
	bar.Apply = CreatePlanButton(bar, "common-icon-checkmark", L.TALENTS_PLAN_BUTTON_APPLY, L.TALENTS_PLAN_BUTTON_APPLY_DESC, function()
		ApplyPlan()
	end)
	bar.Apply:SetPoint("LEFT", bar, "LEFT", 0, 0)
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

local function CreateButtons()
	-- Inside the talent window, on the bottom bar right of Blizzard's buttons.
	local parent = TalentsFrame() or PlayerSpellsFrame
	local anchor = parent.Background or parent
	local builds = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	builds:SetSize(120, 22)
	builds:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -24, 8)
	builds:SetFrameLevel(ns.Number(parent:GetFrameLevel(), 0) + 1010)
	builds:SetText(L.TALENTS_BUILDS)
	builds:SetScript("OnClick", ShowBuildMenu)

	local spells = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	spells:SetSize(150, 22)
	spells:SetFrameLevel(builds:GetFrameLevel())
	spells:SetPoint("RIGHT", builds, "LEFT", -6, 0)
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
	buttons = { builds, spells }
end

function Talents:Update()
	for _, button in ipairs(buttons or {}) do
		button:SetShown(self.db.enabled)
	end
	UpdateSpellsGlow()
end

local glowPending = false
local function QueueGlowUpdate()
	if not glowPending then
		glowPending = true
		C_Timer.After(1, function()
			glowPending = false
			UpdateSpellsGlow()
		end)
	end
end

function Talents:OnLogin()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		if PlayerSpellsFrame then
			CreateButtons()
			self:Update()
			PlayerSpellsFrame:HookScript("OnShow", UpdateSpellsGlow)
			if TalentsFrame() then
				SetupPlanner(TalentsFrame())
			end
		end
	end)
	self:RegisterEvent("PLAYER_LEVEL_UP", QueueGlowUpdate)
	self:RegisterEvent("TRAINER_SHOW", function()
		C_Timer.After(0.3, function()
			ScanTrainer()
			QueueGlowUpdate()
		end)
	end)
	self:RegisterEvent("SPELLS_CHANGED", QueueGlowUpdate)
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
	QueuePlanUpdate()
end

Talents.options = {
	{ key = "enabled", type = "toggle", name = L.TALENTS_ENABLE, desc = L.TALENTS_ENABLE_DESC },
	{ key = "planner", type = "toggle", name = L.TALENTS_PLANNER, desc = L.TALENTS_PLANNER_DESC },
}

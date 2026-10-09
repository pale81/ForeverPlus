-- Talent planner window (like the classic talent calculators): the three
-- trees side by side, left click plans a rank, right click takes it back.
-- Rules of the classic trees: each row needs 5 points in the rows above it
-- in the same tree, a talent behind an arrow needs its source at full rank,
-- 51 points up to level 60. The plan is shown in Blizzard's talent window
-- too and bought there ("Builds" → "Apply plan").
--
-- The window is ForeverPlus' own: Blizzard's talent window is never opened
-- from addon code (that would taint the action bars, whose grid it shows).
local _, ns = ...
local L = ns.L

local Planner = {}
ns.TalentPlanner = Planner

local FIRST_TALENT_LEVEL, PLAN_MAX_LEVEL = 10, 60
local PLAN_POINTS = PLAN_MAX_LEVEL - FIRST_TALENT_LEVEL + 1
local POINTS_PER_ROW = 5
local VIEW_CONFIG = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID or -3
local REQUIRED_EDGES = {
	[Enum.TraitEdgeType.SufficientForAvailability] = true,
	[Enum.TraitEdgeType.RequiredForAvailability] = true,
}

local ICON_SIZE, CELL = 36, 46
local TREE_PADDING, HEADER_HEIGHT = 12, 46
local FRAME_TOP, FRAME_BOTTOM, FRAME_SIDE = 64, 44, 14
local COLOR_AVAILABLE = CreateColor(0.1, 1, 0.1)
local COLOR_MAXED = CreateColor(1, 0.82, 0)
local COLOR_LOCKED = CreateColor(0.5, 0.5, 0.5)
local LINE_DONE, LINE_OPEN = CreateColor(1, 0.82, 0, 0.9), CreateColor(0.45, 0.45, 0.45, 0.8)

---------------------------------------------------------------------------
-- Model: nodes of the player's tree with position, ranks and arrows
---------------------------------------------------------------------------
local function Talents()
	return ns:GetModule("Talents")
end

-- Config to read the tree from: the player's own (ranks already learnt), or
-- before the first talent point Blizzard's view config at level 60.
local function TreeConfig(specID)
	local configID = C_ClassTalents.GetActiveConfigID()
	if configID then
		return configID, true
	end
	C_ClassTalents.InitializeViewLoadout(specID, PLAN_MAX_LEVEL)
	return VIEW_CONFIG, false
end

local function Rounded(value)
	return math.floor(value + 0.5)
end

-- Smallest distance between two different values (the grid step).
local function Step(values)
	local sorted = {}
	for value in pairs(values) do
		sorted[#sorted + 1] = value
	end
	table.sort(sorted)
	local step
	for i = 2, #sorted do
		local delta = sorted[i] - sorted[i - 1]
		if delta > 0 and (not step or delta < step) then
			step = delta
		end
	end
	return step or 1, sorted
end

function Planner.BuildModel()
	local specID = PlayerUtil.GetCurrentSpecID()
	local treeID = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
	if not treeID then
		return nil
	end
	local configID, own = TreeConfig(specID)
	local model = { configID = configID, own = own, nodes = {}, groups = {}, specID = specID }
	local xs, ys = {}, {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		local entryID = info and info.entryIDs and info.entryIDs[1]
		if info and info.isVisible ~= false and (info.maxRanks or 0) > 0 and entryID then
			local entry = C_Traits.GetEntryInfo(configID, entryID)
			local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spellID = definition and definition.spellID
			model.nodes[nodeID] = {
				ID = nodeID, entryID = entryID, posX = info.posX, posY = info.posY,
				maxRanks = info.maxRanks, purchased = info.ranksPurchased or 0,
				group = info.groupIDs and info.groupIDs[1] or 0, edges = info.visibleEdges or {},
				spellID = spellID,
				name = definition and definition.overrideName or (spellID and C_Spell.GetSpellName(spellID)) or "?",
				icon = definition and definition.overrideIcon or (spellID and C_Spell.GetSpellTexture(spellID)) or 134400,
			}
			xs[info.posX] = true
			ys[info.posY] = true
		end
	end
	-- Rows across the whole tree, columns on a common grid.
	local _, sortedY = Step(ys)
	model.rowOf = {}
	for index, y in ipairs(sortedY) do
		model.rowOf[y] = index - 1
	end
	model.rows = #sortedY
	local stepX = Step(xs)
	-- Trees in Blizzard's order, then any group without display info.
	local byID = {}
	for _, display in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		local group = { id = display.groupID, name = display.displayName, icon = display.icon, nodes = {} }
		model.groups[#model.groups + 1] = group
		byID[group.id] = group
	end
	for _, node in pairs(model.nodes) do
		local group = byID[node.group]
		if not group then
			group = { id = node.group, name = "", nodes = {} }
			model.groups[#model.groups + 1] = group
			byID[node.group] = group
		end
		group.nodes[#group.nodes + 1] = node
		node.row = model.rowOf[node.posY]
	end
	for _, group in ipairs(model.groups) do
		local minX
		for _, node in ipairs(group.nodes) do
			minX = math.min(minX or node.posX, node.posX)
		end
		group.columns = 0
		for _, node in ipairs(group.nodes) do
			node.column = Rounded((node.posX - minX) / stepX)
			group.columns = math.max(group.columns, node.column + 1)
		end
	end
	-- Arrows: required sources of each node.
	for _, node in pairs(model.nodes) do
		for _, edge in ipairs(node.edges) do
			local target = model.nodes[edge.targetNode]
			if target and REQUIRED_EDGES[edge.type] then
				target.sources = target.sources or {}
				target.sources[#target.sources + 1] = node
			end
		end
	end
	return model
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local function Rank(plan, node)
	return math.max(node.purchased, plan[node.ID] or 0)
end
Planner.Rank = Rank

function Planner.Spent(model, plan, group)
	local total = 0
	for _, node in pairs(model.nodes) do
		if not group or node.group == group then
			total = total + Rank(plan, node)
		end
	end
	return total
end

-- Points spent in the rows above `row` of the node's tree.
local function PointsAbove(model, plan, node)
	local points = 0
	for _, other in pairs(model.nodes) do
		if other.group == node.group and other.row < node.row then
			points = points + Rank(plan, other)
		end
	end
	return points
end

-- nil if the node may have its rank, else the reason.
local function Problem(model, plan, node)
	local needed = node.row * POINTS_PER_ROW - PointsAbove(model, plan, node)
	if needed > 0 then
		return L.TALENTS_PLAN_NEED_POINTS:format(needed)
	end
	for _, source in ipairs(node.sources or {}) do
		if Rank(plan, source) < source.maxRanks then
			return L.TALENTS_PLAN_NEED_TALENT:format(source.name)
		end
	end
end
Planner.Problem = Problem

-- nil if one more rank can be planned, else the reason.
function Planner.AddProblem(model, plan, node)
	if Rank(plan, node) >= node.maxRanks then
		return ""
	end
	if Planner.Spent(model, plan) >= PLAN_POINTS then
		return L.TALENTS_PLAN_NO_POINTS
	end
	return Problem(model, plan, node)
end

function Planner.Add(model, plan, node)
	if Planner.AddProblem(model, plan, node) then
		return false
	end
	plan[node.ID] = Rank(plan, node) + 1
	return true
end

-- Taking a rank back must leave every other planned talent valid.
function Planner.Remove(model, plan, node)
	local rank = Rank(plan, node)
	if rank <= node.purchased then
		return false
	end
	local old = plan[node.ID]
	plan[node.ID] = rank - 1 > node.purchased and rank - 1 or nil
	for _, other in pairs(model.nodes) do
		if Rank(plan, other) > other.purchased and Problem(model, plan, other) then
			plan[node.ID] = old
			return false, L.TALENTS_PLAN_REMOVE_BLOCKED
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame, model
local buttons, lines, headers = {}, {}, {}

local function CurrentPlan()
	return Talents():CurrentPlan()
end

local function Line(index)
	local line = lines[index]
	if not line then
		line = frame.Canvas:CreateTexture(nil, "BORDER")
		lines[index] = line
	end
	return line
end

local function ButtonCenter(button)
	return button.x + ICON_SIZE / 2, button.y - ICON_SIZE / 2
end

-- Arrow from source to target: down from the source, then across.
local function DrawArrows()
	local plan, count = CurrentPlan(), 0
	for _, button in pairs(buttons) do
		local node = button:IsShown() and button.node
		for _, source in ipairs(node and node.sources or {}) do
			local from = buttons[source.ID]
			if from then
				local color = Rank(plan, source) >= source.maxRanks and LINE_DONE or LINE_OPEN
				local x1, y1 = ButtonCenter(from)
				local x2, y2 = ButtonCenter(button)
				local segments = {}
				if x1 == x2 then
					segments[1] = { x1 - 2, y1 - ICON_SIZE / 2, 4, (y1 - y2) - ICON_SIZE }
				elseif y1 == y2 then
					local left, right = math.min(x1, x2), math.max(x1, x2)
					segments[1] = { left + ICON_SIZE / 2, y1 + 2, (right - left) - ICON_SIZE, 4 }
				else
					-- Down to the target's middle, then across to its edge.
					segments[1] = { x1 - 2, y1 - ICON_SIZE / 2, 4, y1 - ICON_SIZE / 2 - y2 }
					if x2 > x1 then
						segments[2] = { x1, y2 + 2, x2 - x1 - ICON_SIZE / 2, 4 }
					else
						segments[2] = { x2 + ICON_SIZE / 2, y2 + 2, x1 - x2 - ICON_SIZE / 2, 4 }
					end
				end
				for _, segment in ipairs(segments) do
					count = count + 1
					local line = Line(count)
					line:ClearAllPoints()
					line:SetPoint("TOPLEFT", frame.Canvas, "TOPLEFT", segment[1], segment[2])
					line:SetSize(math.max(segment[3], 1), math.max(segment[4], 1))
					line:SetColorTexture(color:GetRGBA())
					line:Show()
				end
			end
		end
	end
	for i = count + 1, #lines do
		lines[i]:Hide()
	end
end

local function UpdateButton(button)
	local plan, node = CurrentPlan(), button.node
	local rank = Rank(plan, node)
	local open = not Planner.AddProblem(model, plan, node)
	local color = rank >= node.maxRanks and COLOR_MAXED or ((open or rank > 0) and COLOR_AVAILABLE or COLOR_LOCKED)
	button.Icon:SetDesaturated(not open and rank == 0)
	button.Border:ShowColor(color:GetRGB())
	button.Rank:SetText(("%d/%d"):format(rank, node.maxRanks))
	button.Rank:SetTextColor(color:GetRGB())
	button.Planned:SetShown(rank > node.purchased)
end

function Planner.Refresh()
	if not (frame and frame:IsShown() and model) then
		return
	end
	local plan = CurrentPlan()
	for _, button in pairs(buttons) do
		if button:IsShown() then
			UpdateButton(button)
		end
	end
	for _, header in ipairs(headers) do
		if header:IsShown() then
			header.Points:SetText(Planner.Spent(model, plan, header.group))
		end
	end
	local spent = Planner.Spent(model, plan)
	frame.Footer:SetText(L.TALENTS_PLANNER_FOOTER:format(spent, PLAN_POINTS, FIRST_TALENT_LEVEL - 1 + math.max(spent, 1)))
	frame.Apply:SetEnabled(model.own and not InCombatLockdown())
	DrawArrows()
	Talents():QueuePlanUpdate()
end

local function ShowTooltip(button)
	local plan, node = CurrentPlan(), button.node
	local rank = Rank(plan, node)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, node.name)
	GameTooltip_AddHighlightLine(GameTooltip, L.TALENTS_PLANNER_RANK:format(rank, node.maxRanks))
	if rank > 0 then
		GameTooltip_AddNormalLine(GameTooltip, C_Traits.GetTraitDescription(node.entryID, rank), true)
	end
	if rank < node.maxRanks then
		if rank > 0 then
			GameTooltip_AddBlankLineToTooltip(GameTooltip)
			GameTooltip_AddHighlightLine(GameTooltip, L.TALENTS_PLANNER_NEXT)
		end
		GameTooltip_AddNormalLine(GameTooltip, C_Traits.GetTraitDescription(node.entryID, rank + 1), true)
		local problem = Planner.AddProblem(model, plan, node)
		if problem and problem ~= "" then
			GameTooltip_AddErrorLine(GameTooltip, problem, true)
		end
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.TALENTS_PLANNER_CLICK)
	GameTooltip:Show()
end

local function OnButtonClick(button, mouseButton)
	local plan = CurrentPlan()
	if mouseButton == "RightButton" then
		local _, problem = Planner.Remove(model, plan, button.node)
		if problem then
			ns.Print(problem)
		end
	else
		Planner.Add(model, plan, button.node)
	end
	Planner.Refresh()
	if GameTooltip:GetOwner() == button then
		ShowTooltip(button)
	end
end

local function CreateNodeButton()
	local button = CreateFrame("Button", nil, frame.Canvas)
	button:SetSize(ICON_SIZE, ICON_SIZE)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Border = ns.CreatePixelBorder(button, button, 2, "OVERLAY", 1)
	local rankBg = button:CreateTexture(nil, "OVERLAY", nil, 2)
	rankBg:SetColorTexture(0, 0, 0, 0.75)
	rankBg:SetPoint("BOTTOMRIGHT", 4, -4)
	rankBg:SetSize(26, 13)
	button.Rank = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.Rank:SetDrawLayer("OVERLAY", 3)
	button.Rank:SetPoint("CENTER", rankBg, "CENTER", 0, 0)
	-- Planned beyond what is learnt: a soft blue glow.
	button.Planned = button:CreateTexture(nil, "OVERLAY", nil, 4)
	button.Planned:SetAllPoints()
	button.Planned:SetColorTexture(0.3, 0.65, 1, 0.25)
	button.Planned:SetBlendMode("ADD")
	button:SetScript("OnClick", OnButtonClick)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function CreateHeader()
	local header = CreateFrame("Frame", nil, frame.Canvas)
	header:SetHeight(HEADER_HEIGHT - 8)
	header.Background = frame.Canvas:CreateTexture(nil, "BACKGROUND")
	header.Background:SetColorTexture(0, 0, 0, 0.45)
	header.Icon = header:CreateTexture(nil, "ARTWORK")
	header.Icon:SetSize(28, 28)
	header.Icon:SetPoint("LEFT", 6, 0)
	header.Name = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header.Name:SetPoint("LEFT", header.Icon, "RIGHT", 8, 0)
	header.Points = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	header.Points:SetPoint("RIGHT", -8, 0)
	return header
end

-- Places trees, headers and buttons for the current model.
local function Layout()
	for _, button in pairs(buttons) do
		button:Hide()
	end
	for _, header in ipairs(headers) do
		header:Hide()
		header.Background:Hide()
	end
	local x = 0
	local height = HEADER_HEIGHT + model.rows * CELL
	for index, group in ipairs(model.groups) do
		local width = math.max(group.columns, 4) * CELL + 2 * TREE_PADDING
		local header = headers[index] or CreateHeader()
		headers[index] = header
		header.group = group.id
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", frame.Canvas, "TOPLEFT", x, 0)
		header:SetWidth(width - 6)
		header.Background:ClearAllPoints()
		header.Background:SetPoint("TOPLEFT", frame.Canvas, "TOPLEFT", x, 0)
		header.Background:SetSize(width - 6, height)
		header.Icon:SetTexture(group.icon or 134400)
		header.Name:SetText(group.name)
		header:Show()
		header.Background:Show()
		for _, node in ipairs(group.nodes) do
			local button = buttons[node.ID] or CreateNodeButton()
			buttons[node.ID] = button
			button.node = node
			button.Icon:SetTexture(node.icon)
			button.x = x + TREE_PADDING + node.column * CELL + (CELL - ICON_SIZE) / 2
			button.y = -(HEADER_HEIGHT + node.row * CELL + (CELL - ICON_SIZE) / 2)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame.Canvas, "TOPLEFT", button.x, button.y)
			button:Show()
		end
		x = x + width
	end
	frame.Canvas:SetSize(math.max(x - 6, 200), height)
	frame:SetSize(math.max(x - 6, 200) + 2 * FRAME_SIDE, height + FRAME_TOP + FRAME_BOTTOM)
end

local function CreateWindow()
	frame = CreateFrame("Frame", "ForeverPlusTalentPlanner", UIParent, "ButtonFrameTemplate")
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	if frame.Inset then
		frame.Inset:Hide()
	end
	frame.Canvas = CreateFrame("Frame", nil, frame)
	frame.Canvas:SetPoint("TOPLEFT", FRAME_SIDE, -FRAME_TOP + 8)
	frame.Footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Footer:SetPoint("BOTTOMLEFT", 16, 10)
	local apply = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	apply:SetSize(150, 22)
	apply:SetPoint("BOTTOMRIGHT", -8, 6)
	apply:SetText(L.TALENTS_PLAN_APPLY)
	apply:SetScript("OnClick", function()
		Talents():ApplyPlan()
	end)
	frame.Apply = apply
	local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetPoint("RIGHT", apply, "LEFT", -6, 0)
	reset:SetText(RESET)
	reset:SetScript("OnClick", function()
		wipe(CurrentPlan())
		Planner.Refresh()
	end)
	frame:SetScript("OnShow", Planner.Refresh)
	tinsert(UISpecialFrames, frame:GetName())
	ns.HookSavedWindow(frame)
	frame:Hide()
end

function Planner.Show()
	model = Planner.BuildModel()
	if not model or not next(model.nodes) then
		ns.Print(L.TALENTS_EARLY_FAILED)
		return
	end
	if not frame then
		CreateWindow()
	end
	Layout()
	local _, classFile = UnitClass("player")
	frame:SetTitle(L.TALENTS_PLANNER_TITLE:format(UnitClass("player")))
	if frame.SetPortraitToClassIcon then
		frame:SetPortraitToClassIcon(classFile)
	end
	frame:Show()
	Planner.Refresh()
end

function Planner.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Planner.Show()
	end
end

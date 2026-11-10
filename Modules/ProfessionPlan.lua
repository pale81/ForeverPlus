-- Recipes still to come, per profession, like "spells at the trainer": a visit to a profession trainer keeps
-- their whole list (also what needs more skill); the filter menu of the profession window switches them on below
-- the recipes of the window's own list (as the unlearned recipes of retail), sorted by the skill needed, with what
-- can be learned now in green.
-- Recipes that come from drops or merchants are not in a trainer's list and do not appear.
local _, ns = ...
local L = ns.L

local ProfessionPlan = ns:NewModule("ProfessionPlan", {
	title = L.PROFPLAN_TITLE,
	order = 6.1,
	defaults = {
		upcoming = false, -- the list beside the profession window (switched in its filter menu)
		preview = true,   -- recipes: Ctrl + click tries the product on, green arrow and rating for better equipment
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

-- Ctrl + click (the game's "try on" modifier): shows the item in the dressing room. true when it did.
function ns.TryOnRecipe(link)
	if not (ns.RecipePreviewOn() and ns.RecipeLink(link) and IsModifiedClick("DRESSUP")) then
		return false
	end
	local dressUp = DressUpItemLink or DressUpLink
	return dressUp and dressUp(link) and true or (dressUp ~= nil)
end

-- The arrow in front of a name in a list: green for a better item, grey when only the level is missing.
function ProfessionPlan.ArrowMarkup(state)
	if state == true then
		return "|A:bags-greenarrow:14:14|a "
	elseif state == "later" then
		return "|A:bags-greenarrow:14:14:0:0:120:120:120|a "
	end
	return ""
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
				found[profession] = found[profession] or {}
				table.insert(found[profession], {
					name = name, icon = icon, skill = Plain(skillRank) or 0,
					level = GetTrainerServiceLevelReq and Plain(GetTrainerServiceLevelReq(index)) or 0,
					cost = GetTrainerServiceCost and Plain((GetTrainerServiceCost(index))) or 0,
					known = serviceType == "used" or nil,
					link = GetTrainerServiceItemLink and ns.RecipeLink(GetTrainerServiceItemLink(index)) or nil,
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
			rows[#rows + 1] = { entry = entry, now = (entry.skill or 0) <= skill and (entry.level or 0) <= level }
		end
	end
	table.sort(rows, function(a, b)
		if a.entry.skill ~= b.entry.skill then
			return (a.entry.skill or 0) < (b.entry.skill or 0)
		end
		return a.entry.name < b.entry.name
	end)
	return rows
end

-- The profession on show and the names of its learned recipes.
local function CurrentProfession()
	local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	if not info then
		return nil
	end
	local known = {}
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.learned and Plain(recipe.name) then
			known[recipe.name] = true
		end
	end
	return Plain(info.professionName), ns.Number(info.skillLevel, 0), known
end

-- The elements below the recipes of the profession window: a divider like the game's "unlearned" one, a title, then
-- per skill needed a small heading and the recipes (what can be learned now in green, the rest grey). Each is a
-- plain element of Blizzard's list (no recipe of the game: a click does not select anything there); dividerHeight
-- gives its height.
function ProfessionPlan.Elements(profession, list, known, skill, level)
	local elements = { { isDivider = true, dividerHeight = 30, fpPlan = true } }
	elements[#elements + 1] = { fpPlan = "title", dividerHeight = 22, text = L.PROFPLAN_LIST:format(profession or "") }
	if not list then
		elements[#elements + 1] = { fpPlan = "note", dividerHeight = 20, text = L.PROFPLAN_VISIT_TRAINER:format(profession or "?") }
		return elements
	end
	local lastSkill
	local rows = ProfessionPlan.Upcoming(list, known, skill, level)
	for _, row in ipairs(rows) do
		local entry = row.entry
		if entry.skill ~= lastSkill then
			lastSkill = entry.skill
			elements[#elements + 1] = { fpPlan = "skill", dividerHeight = 18, text = L.PROFPLAN_SKILL:format(entry.skill or 0) }
		end
		elements[#elements + 1] = { fpPlan = "recipe", dividerHeight = 20, entry = entry, now = row.now,
			right = row.now and L.PROFPLAN_NOW or ((entry.level or 0) > level and L.PROFPLAN_LEVEL:format(entry.level) or nil) }
	end
	if #rows == 0 then
		elements[#elements + 1] = { fpPlan = "note", dividerHeight = 20, text = L.PROFPLAN_ALL_KNOWN }
	end
	return elements
end

local function RecipeTooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if entry.link and ns.RecipePreviewOn() then
		GameTooltip:SetHyperlink(entry.link)
		ns.AddRecipeScoreLine(GameTooltip, entry.link)
		GameTooltip:AddLine(" ")
	end
	GameTooltip_SetTitle(GameTooltip, entry.name)
	GameTooltip_AddNormalLine(GameTooltip, L.PROFPLAN_SKILL:format(entry.skill or 0))
	if (entry.level or 0) > 0 then
		GameTooltip_AddNormalLine(GameTooltip, L.PROFPLAN_LEVEL:format(entry.level))
	end
	if (entry.cost or 0) > 0 then
		GameTooltip_AddNormalLine(GameTooltip, GetMoneyString(entry.cost, true))
	end
	GameTooltip:Show()
end

-- Draws one of our elements on the plain frame Blizzard's list gives it; the same frames also serve the list's
-- own padding, which gets them back empty.
local function Decorate(frame, data)
	if not frame.fpText then
		frame.fpIcon = frame:CreateTexture(nil, "ARTWORK")
		frame.fpIcon:SetSize(16, 16)
		frame.fpIcon:SetPoint("LEFT", 14, 0)
		frame.fpText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		frame.fpText:SetJustifyH("LEFT")
		frame.fpText:SetWordWrap(false)
		frame.fpRight = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		frame.fpRight:SetPoint("RIGHT", -8, 0)
		frame.fpHighlight = frame:CreateTexture(nil, "HIGHLIGHT")
		frame.fpHighlight:SetAllPoints()
		frame.fpHighlight:SetColorTexture(1, 1, 1, 0.08)
	end
	local kind = data and data.fpPlan
	local isRecipe = kind == "recipe"
	local shown = kind ~= nil and kind ~= true
	frame.fpData = isRecipe and data.entry or nil
	frame:EnableMouse(isRecipe)
	frame.fpHighlight:SetShown(isRecipe)
	frame.fpIcon:SetShown(isRecipe)
	frame.fpText:SetShown(shown)
	frame.fpRight:SetShown(isRecipe and data.right ~= nil)
	if not shown then
		return
	end
	frame.fpText:ClearAllPoints()
	frame.fpText:SetPoint("LEFT", isRecipe and 34 or (kind == "title" and 4 or 10), 0)
	frame.fpText:SetPoint("RIGHT", isRecipe and frame.fpRight or frame, isRecipe and "LEFT" or "RIGHT", -4, 0)
	if isRecipe then
		local entry = data.entry
		frame.fpIcon:SetTexture(entry.icon or 134400)
		frame.fpIcon:SetDesaturated(not data.now)
		local arrow = ns.RecipePreviewOn() and entry.link and ns.RecipeUpgradeState
			and ProfessionPlan.ArrowMarkup(ns.RecipeUpgradeState(entry.link)) or ""
		frame.fpText:SetText(arrow .. entry.name)
		local color = data.now and GREEN_FONT_COLOR or DISABLED_FONT_COLOR
		frame.fpText:SetTextColor(color:GetRGB())
		frame.fpRight:SetText(data.right or "")
	else
		frame.fpText:SetText(data.text or "")
		local color = kind == "title" and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR
		frame.fpText:SetTextColor(color:GetRGB())
	end
	if not frame.fpScripts then
		frame.fpScripts = true
		frame:SetScript("OnEnter", function(self)
			if self.fpData then
				RecipeTooltip(self, self.fpData)
			end
		end)
		frame:SetScript("OnLeave", GameTooltip_Hide)
		frame:SetScript("OnMouseUp", function(self, mouseButton)
			if self.fpData and mouseButton == "LeftButton" then
				ns.TryOnRecipe(self.fpData.link)
			end
		end)
	end
end

local injected = { provider = nil, nodes = {} }

local function CraftingList()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList
end

-- Takes our elements out of the list and, while the option is on and nothing is searched, adds them anew.
local function Inject()
	local recipeList = CraftingList()
	local box = recipeList and recipeList.ScrollBox
	local provider = box and box.GetDataProvider and box:GetDataProvider()
	if injected.provider and injected.provider == provider then
		for _, node in ipairs(injected.nodes) do
			provider:Remove(node)
		end
	end
	injected.provider, injected.nodes = provider, {}
	if not (provider and ProfessionPlan.db.upcoming) then
		return
	end
	local search = recipeList.SearchBox
	if search and search.HasText and search:HasText() then
		return
	end
	local profession, skill, known = CurrentProfession()
	if not profession then
		return
	end
	local elements = ProfessionPlan.Elements(profession, ProfessionPlan.cdb.trainers[profession], known, skill,
		ns.Number(UnitLevel("player"), 1))
	for _, data in ipairs(elements) do
		injected.nodes[#injected.nodes + 1] = provider:Insert(data)
	end
end
ProfessionPlan.Inject = Inject

local function OnAcquired(_, frame, node)
	local data = node and node.GetData and node:GetData()
	if data and data.isDivider then
		return -- Blizzard's divider, ours too, is drawn by its template
	end
	if frame.GetObjectType and frame:GetObjectType() == "Frame" and (frame.fpText or (data and data.fpPlan)) then
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
	ScrollUtil.AddAcquiredFrameCallback(box, ns.Measured("ProfessionPlan: list row", OnAcquired), ProfessionPlan)
	Inject()
end

-- The rows of the profession window's recipe list: arrow at the name for better equipment, Ctrl + click tries the
-- product on (Blizzard's own Ctrl + click only links the recipe).
local rowArrows = setmetatable({}, { __mode = "k" })

local function RecipeOutputLink(recipeID)
	local schematic = recipeID and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	local itemID = schematic and Plain(schematic.outputItemID)
	return itemID and ("item:" .. itemID) or nil
end

local function OnRecipeRowInit(button, node)
	local data = node and node.GetData and node:GetData()
	local recipe = data and data.recipeInfo
	button.fpPreviewLink = recipe and ns.RecipePreviewOn() and RecipeOutputLink(Plain(recipe.recipeID)) or nil
	if not rowArrows[button] then
		local arrow = button:CreateTexture(nil, "OVERLAY")
		arrow:SetAtlas("bags-greenarrow", true)
		arrow:SetScale(0.8)
		arrow:SetPoint("RIGHT", button.Label, "LEFT", -1, 0)
		rowArrows[button] = arrow
		button:HookScript("OnMouseUp", function(self, mouseButton)
			if mouseButton == "LeftButton" then
				ns.TryOnRecipe(self.fpPreviewLink)
			end
		end)
	end
	local state = button.fpPreviewLink and ns.RecipeUpgradeState and ns.RecipeUpgradeState(button.fpPreviewLink)
	local arrow = rowArrows[button]
	arrow:SetShown(state and true or false)
	arrow:SetDesaturated(state == "later")
end

function ProfessionPlan.HookRecipeRows()
	local mixin = ProfessionsRecipeListRecipeMixin
	if mixin and mixin.Init and not ProfessionPlan.rowsHooked then
		ProfessionPlan.rowsHooked = true
		hooksecurefunc(mixin, "Init", ns.Measured("ProfessionPlan: recipe row", OnRecipeRowInit))
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
			ns.CreateOptionCheckbox(rootDescription, L.PROFPLAN_FILTER, "ProfessionPlan", "upcoming", L.PROFPLAN_FILTER_DESC)
		end)
	end
	ns.OnAddOnLoaded("Blizzard_Professions", function()
		ProfessionPlan.HookRecipeRows()
		ProfessionPlan.HookList()
	end)
end

function ProfessionPlan:OnOptionChanged()
	Inject()
end

ProfessionPlan.options = {
	{ key = "upcoming", type = "toggle", name = L.PROFPLAN_FILTER, desc = L.PROFPLAN_FILTER_DESC, new = true },
	{ key = "preview", type = "toggle", name = L.PROFPLAN_PREVIEW, desc = L.PROFPLAN_PREVIEW_DESC, new = true },
}

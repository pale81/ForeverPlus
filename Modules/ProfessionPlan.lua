-- Recipes still to come, per profession, like "spells at the trainer": a visit to a profession trainer keeps
-- their whole list (also what needs more skill); the filter menu of the profession window switches a list
-- beside the window on, sorted by the skill needed, with what can be learned now in green.
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

local function Items()
	local profession, skill, known = CurrentProfession()
	local list = profession and ProfessionPlan.cdb.trainers[profession]
	local items = {}
	if not list then
		items[#items + 1] = { text = L.PROFPLAN_VISIT_TRAINER:format(profession or "?"), line = false }
		return items, profession
	end
	local level = UnitLevel("player")
	local lastSkill
	for _, row in ipairs(ProfessionPlan.Upcoming(list, known, skill, level)) do
		local entry = row.entry
		if entry.skill ~= lastSkill then
			lastSkill = entry.skill
			items[#items + 1] = { text = L.PROFPLAN_SKILL:format(entry.skill or 0) }
		end
		local cost = (entry.cost or 0) > 0 and GetMoneyString(entry.cost, true) or nil
		local arrow = ns.RecipePreviewOn() and entry.link and ns.RecipeUpgradeState
			and ProfessionPlan.ArrowMarkup(ns.RecipeUpgradeState(entry.link)) or ""
		items[#items + 1] = {
			icon = entry.icon or 134400,
			text = arrow .. (row.now and GREEN_FONT_COLOR:WrapTextInColorCode(entry.name) or entry.name),
			right = row.now and L.PROFPLAN_NOW or ((entry.level or 0) > level and L.PROFPLAN_LEVEL:format(entry.level) or nil),
			onClick = function()
				ns.TryOnRecipe(entry.link)
			end,
			tooltip = function(tooltip)
				if entry.link and ns.RecipePreviewOn() then
					tooltip:SetHyperlink(entry.link)
					ns.AddRecipeScoreLine(tooltip, entry.link)
					tooltip:AddLine(" ")
				end
				GameTooltip_SetTitle(tooltip, entry.name)
				GameTooltip_AddNormalLine(tooltip, L.PROFPLAN_SKILL:format(entry.skill or 0))
				if (entry.level or 0) > 0 then
					GameTooltip_AddNormalLine(tooltip, L.PROFPLAN_LEVEL:format(entry.level))
				end
				if cost then
					GameTooltip_AddNormalLine(tooltip, cost)
				end
			end,
		}
	end
	if #items == 0 then
		items[#items + 1] = { text = L.PROFPLAN_ALL_KNOWN, line = false }
	end
	return items, profession
end

local anchor

local function Popup()
	return _G.ForeverPlusPopupProfessionPlan
end

-- The list beside the profession window while it is open and the filter is on.
local function UpdateList()
	local frame = ProfessionsFrame
	local popup = Popup()
	if not (ProfessionPlan.db.upcoming and frame and frame:IsShown()) then
		if popup then
			popup:Hide()
		end
		return
	end
	if popup and popup:IsShown() then
		popup:Refresh()
		return
	end
	if not anchor then
		anchor = CreateFrame("Frame", nil, frame)
		anchor:SetSize(1, 1)
		anchor:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	end
	ns.ShowPopupList(anchor, function()
		local items, profession = Items()
		return { title = L.PROFPLAN_LIST:format(profession or ""), items = items, width = 320, maxRows = 22 }
	end, "ProfessionPlan")
	-- Below the 1-point anchor means beside the window, at its top.
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
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", ns.Measured("ProfessionPlan: list", UpdateList))
	self:RegisterEvent("TRADE_SKILL_CLOSE", ns.Measured("ProfessionPlan: list", UpdateList))
	-- The switch in the filter menu of the profession window (as the retail filter for unlearned recipes).
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", function(_, rootDescription)
			rootDescription:CreateDivider()
			ns.CreateOptionCheckbox(rootDescription, L.PROFPLAN_FILTER, "ProfessionPlan", "upcoming", L.PROFPLAN_FILTER_DESC)
		end)
	end
	ns.OnAddOnLoaded("Blizzard_Professions", function()
		ProfessionPlan.HookRecipeRows()
		if ProfessionsFrame then
			ProfessionsFrame:HookScript("OnShow", ns.Measured("ProfessionPlan: list", UpdateList))
			ProfessionsFrame:HookScript("OnHide", ns.Measured("ProfessionPlan: list", UpdateList))
		end
	end)
end

function ProfessionPlan:OnOptionChanged()
	UpdateList()
end

ProfessionPlan.options = {
	{ key = "upcoming", type = "toggle", name = L.PROFPLAN_FILTER, desc = L.PROFPLAN_FILTER_DESC, new = true },
	{ key = "preview", type = "toggle", name = L.PROFPLAN_PREVIEW, desc = L.PROFPLAN_PREVIEW_DESC, new = true },
}

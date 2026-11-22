-- Search box in the macro icon picker: finds icons by file name and by the English and German names
-- of the spells and items that use them (Data/MacroIcons.lua). Results show in their own grid over
-- Blizzard's; a click selects the icon in Blizzard's picker through its own selection call.
local _, ns = ...
local L = ns.L

local MacroIcons = ns:NewModule("MacroIcons", {
	title = L.MACROICONS_TITLE,
	order = 5.4,
	defaults = {
		enabled = true,
	},
})

local UMLAUTS = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }

-- Lower case as in the data: ASCII, the German capital umlauts, and "_" as a space.
local function Normalize(text)
	return (text:lower():gsub("\195[\132\150\156]", UMLAUTS):gsub("_", " "))
end
MacroIcons.Normalize = Normalize

local function Words(query)
	local words = {}
	for word in Normalize(query):gmatch("[^%s|]+") do
		words[#words + 1] = word
	end
	return words
end

local function HasAll(text, words)
	for i = 1, #words do
		if not text:find(words[i], 1, true) then return false end
	end
	return true
end

-- File IDs whose search text contains every word of the query; nil for an empty query.
function MacroIcons.Find(data, query)
	local words = Words(query)
	if #words == 0 then return nil, words end
	local found = {}
	for text, id in data:gmatch("([^\t\n]+)\t(%d+)") do
		if HasAll(text, words) then found[tonumber(id)] = true end
	end
	return found, words
end

-- The picker's icons (in its order, without repeats) that match: file IDs from the data, loose icons
-- ("INTERFACE\ICONS\name") by their file name.
function MacroIcons.Collect(getIcon, count, found, words)
	local results, seen = {}, {}
	for index = 1, count do
		local icon = getIcon(index)
		if icon ~= nil and not seen[icon] then
			local match
			if type(icon) == "number" then
				match = found[icon]
			elseif type(icon) == "string" then
				match = HasAll(Normalize(icon:match("[^\\/]+$") or icon), words)
			end
			if match then
				seen[icon] = true
				results[#results + 1] = { icon = icon, index = index }
			end
		end
	end
	return results
end

local search, grid, emptyText
local results = {}
local pending = 0

local function Popup()
	return MacroPopupFrame
end

local function ShowResults(shown)
	grid:SetShown(shown)
	emptyText:SetShown(shown and #results == 0)
end

local function Run()
	local popup = Popup()
	local data = ns.MacroIconNames
	if not (popup and popup:IsShown() and type(data) == "string") then return end
	local found, words = MacroIcons.Find(data, search:GetText() or "")
	if not found then
		results = {}
		ShowResults(false)
		return
	end
	results = MacroIcons.Collect(function(index) return popup:GetIconByIndex(index) end, popup:GetNumIcons(), found, words)
	grid:SetSelectedIndex(nil)
	grid:SetSelectionsDataProvider(function(index) return results[index] and results[index].icon end, function() return #results end)
	ShowResults(true)
end

-- Typing waits a moment so that a long word is searched once.
local function Schedule()
	pending = pending + 1
	local token = pending
	ns.After("MacroIcons.Search", 0.2, function()
		if token == pending then Run() end
	end)
end

local function Clear()
	pending = pending + 1
	if search then search:SetText("") end
	results = {}
	if grid then ShowResults(false) end
end

-- Selects the icon in Blizzard's picker as a click there would.
local function Pick(index)
	local entry = results[index]
	local popup = Popup()
	if not (entry and popup) then return end
	local selector = popup.IconSelector
	selector:OnSelection(entry.index)
	selector:ScrollToSelectedIndex()
end

local function Build(popup)
	local border = popup.BorderBox
	search = CreateFrame("EditBox", nil, border, "SearchBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("RIGHT", border.IconTypeDropdown, "LEFT", -12, 0)
	search:SetAutoFocus(false)
	search.Instructions:SetText(L.MACROICONS_SEARCH)
	search:HookScript("OnTextChanged", Schedule)
	search:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
	search:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.MACROICONS_SEARCH_TIP, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	search:HookScript("OnLeave", GameTooltip_Hide)

	-- Own grid in Blizzard's place, opaque so that the picker's icons do not shine through.
	grid = CreateFrame("Frame", nil, popup, "ScrollBoxSelectorTemplate")
	grid:SetAllPoints(popup.IconSelector)
	grid:SetFrameStrata(popup.IconSelector:GetFrameStrata())
	grid:SetFrameLevel((tonumber(popup.IconSelector:GetFrameLevel()) or 1) + 10)
	grid:EnableMouse(true)
	grid:AdjustScrollBarOffsets(-14, -4, 6)
	local background = grid:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", -4, 4)
	background:SetPoint("BOTTOMRIGHT", 4, -4)
	background:SetColorTexture(0, 0, 0, 1)
	grid:SetSetupCallback(function(button, _, icon)
		button:SetIconTexture(icon)
	end)
	grid:SetSelectedCallback(function(index) Pick(index) end)
	emptyText = grid:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("TOP", 0, -40)
	emptyText:SetText(L.MACROICONS_NONE)
	grid:Hide()

	popup:HookScript("OnShow", Clear)
	popup:HookScript("OnHide", Clear)
	-- Blizzard's spell/item filter changes the list: search it again.
	hooksecurefunc(popup, "SetIconFilterInternal", function()
		if search:IsShown() and (search:GetText() or "") ~= "" then Schedule() end
	end)
end

function MacroIcons:Apply()
	local popup = Popup()
	if not popup then return end
	if not search then
		if not self.db.enabled then return end
		Build(popup)
	end
	search:SetShown(self.db.enabled)
	Clear()
end

function MacroIcons:OnLogin()
	ns.OnAddOnLoaded("Blizzard_MacroUI", function() self:Apply() end)
end

function MacroIcons:OnOptionChanged()
	self:Apply()
end

MacroIcons.options = {
	{ key = "enabled", type = "toggle", name = L.MACROICONS_ENABLE, desc = L.MACROICONS_ENABLE_DESC, new = true },
}

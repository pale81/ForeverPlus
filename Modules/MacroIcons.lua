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
local SEARCH_BUDGET = 0.8 -- ms per frame slice
local FIND_CHECK_STEP = 32
local INDEX_CHECK_STEP = 64
local COLLECT_CHECK_STEP = 256
local DIRECT_COLLECT_LIMIT = 400 -- below this, hash lookup + sort beats scanning every picker icon

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

local function HasAll(text, words, skipIndex)
	for i = 1, #words do
		if i ~= skipIndex and not text:find(words[i], 1, true) then return false end
	end
	return true
end

local function PickAnchor(words)
	local anchor, anchorIndex = words[1], 1
	for i = 2, #words do
		if #words[i] > #anchor then
			anchor, anchorIndex = words[i], i
		end
	end
	return anchor, anchorIndex
end

-- Start of the line containing `hit`, stepping backwards down to `floor` (a line start).
local function LineStart(data, floor, hit)
	local limit = hit
	local start = limit - 256
	if start < floor then start = floor end
	local nl = data:find("\n", start, true)
	while not nl or nl >= limit do
		if start <= floor then return floor end
		limit = start
		start = limit - 256
		if start < floor then start = floor end
		nl = data:find("\n", start, true)
	end
	while true do
		local nextNl = data:find("\n", nl + 1, true)
		if not nextNl or nextNl >= limit then
			return nl + 1
		end
		nl = nextNl
	end
end

-- Incremental scan over Data/MacroIcons.lua using C plain-string search for the longest word.
function MacroIcons.StartFind(data, query)
	local words = type(query) == "table" and query or Words(query)
	if #words == 0 then return nil, words end
	local anchor, anchorIndex = PickAnchor(words)
	return {
		data = data,
		words = words,
		anchor = anchor,
		anchorIndex = anchorIndex,
		pos = 1,
		found = {},
		count = 0,
		done = false,
	}, words
end

function MacroIcons.StepFind(state, deadline)
	if state.done then return true end
	local data, words = state.data, state.words
	local anchor, anchorIndex = state.anchor, state.anchorIndex
	local found, count = state.found, state.count
	local pos, multi = state.pos, #words > 1
	local len, checks = #data, 0
	while true do
		local hit = data:find(anchor, pos, true)
		if not hit then
			state.pos, state.count, state.done = len + 1, count, true
			return true
		end
		local lineEnd = data:find("\n", hit, true) or (len + 1)
		local tab = data:find("\t", hit, true)
		if tab and tab < lineEnd then
			local ok = true
			if multi then
				local text = data:sub(LineStart(data, pos, hit), tab - 1)
				ok = HasAll(text, words, anchorIndex)
			end
			if ok then
				local id = tonumber(data:sub(tab + 1, lineEnd - 1))
				if id and not found[id] then
					found[id] = true
					count = count + 1
				end
			end
		end
		pos = lineEnd + 1
		if deadline then
			checks = checks + 1
			if checks >= FIND_CHECK_STEP then
				checks = 0
				if debugprofilestop() >= deadline then
					state.pos, state.count = pos, count
					return false
				end
			end
		end
	end
end

-- File IDs whose search text contains every word of the query; nil for an empty query.
function MacroIcons.Find(data, query)
	local state, words = MacroIcons.StartFind(data, query)
	if not state then return nil, words end
	MacroIcons.StepFind(state)
	return state.found, words
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

local function CompareEntryIndex(a, b)
	return a.index < b.index
end

-- Reusable picker index built incrementally in frame slices so repeated searches do not call
-- GetIconByIndex tens of thousands of times.
function MacroIcons.NewIndex(getIcon, count)
	return {
		getIcon = getIcon,
		count = count,
		nextIndex = 1,
		ready = false,
		seen = {},
		byId = {},
		loose = {},
		icons = {},
		indices = {},
		names = {},
	}
end

function MacroIcons.StepIndex(index, deadline)
	if index.ready then return true end
	local getIcon, count = index.getIcon, index.count
	local seen, byId, loose = index.seen, index.byId, index.loose
	local icons, indices, names = index.icons, index.indices, index.names
	local i, n, checks = index.nextIndex, #icons, 0
	while i <= count do
		local icon = getIcon(i)
		if icon ~= nil and not seen[icon] then
			seen[icon] = true
			local kind = type(icon)
			if kind == "number" then
				byId[icon] = i
				n = n + 1
				icons[n], indices[n] = icon, i
			elseif kind == "string" then
				local name = Normalize(icon:match("[^\\/]+$") or icon)
				loose[#loose + 1] = { icon = icon, index = i, name = name }
				n = n + 1
				icons[n], indices[n], names[n] = icon, i, name
			end
		end
		i = i + 1
		if deadline then
			checks = checks + 1
			if checks >= INDEX_CHECK_STEP then
				checks = 0
				if debugprofilestop() >= deadline then
					index.nextIndex = i
					return false
				end
			end
		end
	end
	index.nextIndex = i
	index.seen = nil
	index.ready = true
	return true
end

function MacroIcons.StepCollect(index, state, deadline)
	if state.collected then return true end
	local found, words = state.find.found, state.words
	local out = state.results
	if not out then
		out = {}
		state.results = out
	end
	if state.find.count <= DIRECT_COLLECT_LIMIT and state.collectPos == 1 then
		local byId, loose = index.byId, index.loose
		for id in pairs(found) do
			local pickerIndex = byId[id]
			if pickerIndex then
				out[#out + 1] = { icon = id, index = pickerIndex }
			end
		end
		for i = 1, #loose do
			local entry = loose[i]
			if HasAll(entry.name, words) then
				out[#out + 1] = { icon = entry.icon, index = entry.index }
			end
		end
		if #out > 1 then
			table.sort(out, CompareEntryIndex)
		end
		state.collected = true
		return true
	end
	local icons, indices, names = index.icons, index.indices, index.names
	local total, k, checks = #icons, state.collectPos, 0
	while k <= total do
		local icon, name = icons[k], names[k]
		if (not name and found[icon]) or (name and HasAll(name, words)) then
			out[#out + 1] = { icon = icon, index = indices[k] }
		end
		k = k + 1
		if deadline then
			checks = checks + 1
			if checks >= COLLECT_CHECK_STEP then
				checks = 0
				if debugprofilestop() >= deadline then
					state.collectPos = k
					return false
				end
			end
		end
	end
	state.collectPos = k
	state.collected = true
	return true
end

local search, grid, emptyText
local results = {}
local debounceTimer, scanTicker
local pickerCache, searchState
local searchToken = 0

local function Popup()
	return MacroPopupFrame
end

local function ResultIcon(index)
	return results[index] and results[index].icon
end

local function ResultCount()
	return #results
end

local function ShowResults(shown)
	grid:SetShown(shown)
	emptyText:SetShown(shown and #results == 0)
end

local function CancelScan()
	searchToken = searchToken + 1
	if scanTicker then
		scanTicker:Cancel()
		scanTicker = nil
	end
	searchState = nil
end

local function CancelDebounce()
	if debounceTimer then
		debounceTimer:Cancel()
		debounceTimer = nil
	end
end

local function StepSearch(ticker, token)
	local popup = Popup()
	if not (popup and popup:IsShown() and pickerCache and searchState and searchState.token == token) then
		ticker:Cancel()
		if scanTicker == ticker then scanTicker = nil end
		return
	end
	local deadline = debugprofilestop() + SEARCH_BUDGET
	if not pickerCache.ready then
		if not MacroIcons.StepIndex(pickerCache, deadline) or debugprofilestop() >= deadline then
			return
		end
	end
	if not searchState.find.done then
		if not MacroIcons.StepFind(searchState.find, deadline) or debugprofilestop() >= deadline then
			return
		end
	end
	if not searchState.collected then
		if not MacroIcons.StepCollect(pickerCache, searchState, deadline) or debugprofilestop() >= deadline then
			return
		end
	end
	results = searchState.results
	ticker:Cancel()
	if scanTicker == ticker then scanTicker = nil end
	searchState = nil
	grid:SetSelectedIndex(nil)
	grid:SetSelectionsDataProvider(ResultIcon, ResultCount)
	ShowResults(true)
end

local function StartSearch()
	debounceTimer = nil
	CancelScan()
	local popup = Popup()
	local data = ns.MacroIconNames
	if not (popup and popup:IsShown() and type(data) == "string") then return end
	local findState, words = MacroIcons.StartFind(data, search:GetText() or "")
	if not findState then
		results = {}
		ShowResults(false)
		return
	end
	local count = popup:GetNumIcons()
	if not pickerCache or pickerCache.popup ~= popup or pickerCache.count ~= count then
		pickerCache = MacroIcons.NewIndex(function(index) return popup:GetIconByIndex(index) end, count)
		pickerCache.popup = popup
	end
	searchToken = searchToken + 1
	local token = searchToken
	searchState = { token = token, find = findState, words = words, collectPos = 1, collected = false }
	scanTicker = ns.NewTicker("MacroIcons.Search", 0, function(ticker)
		StepSearch(ticker, token)
	end)
	if not searchState then scanTicker = nil end
end

-- Typing waits a moment so that a long word is searched once; clearing hides results immediately.
local function Schedule()
	CancelDebounce()
	CancelScan()
	if not (search and search:IsShown()) then return end
	local text = search:GetText() or ""
	if text:match("^%s*$") then
		results = {}
		if grid then ShowResults(false) end
		return
	end
	debounceTimer = ns.NewTimer("MacroIcons.Search", 0.2, StartSearch)
end

local function Clear()
	CancelDebounce()
	CancelScan()
	pickerCache = nil
	if search and (search:GetText() or "") ~= "" then
		search:SetText("")
	end
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
	-- Blizzard's spell/item filter changes the list: rebuild index and search it again.
	hooksecurefunc(popup, "SetIconFilterInternal", function()
		pickerCache = nil
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

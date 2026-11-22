-- Emote tab: a tab of its own to the right of the last chat tab (normally the combat log). A click shows every emote
-- of the game over the chat window, a click on an emote performs it, as in the game's chat menu (speech bubble).
-- The tab is an own button in the clean look of ForeverPlus's chat tabs, not a chat window: Blizzard's dock, tabs and
-- chat windows stay untouched (only read). Parented to GENERAL_CHAT_DOCK so it fades with ChatMinimize and is never
-- clipped or dimmed by an unselected tab.
local _, ns = ...
local L = ns.L

local Emotes = ns:NewModule("ChatEmotes", {
	title = L.CHATEMOTES_TITLE,
	order = 5.97,
	defaults = {
		enabled = true,
	},
})

local CELL_WIDTH = 96 -- smallest width of a column
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 20
local SECTION_GAP = 6
local INSET = 5
local SEARCH_HEIGHT = 20
local MAX_CMD_ALIAS = 6
local OPEN_BUDGET = 1.2   -- ms for first tab click (panel setup + initial visible rows)
local RENDER_BUDGET = 0.8 -- ms per frame slice while creating or updating visible rows

local tab, panel, searchBox, clearButton, scroll, content, emptyText
local allSections, visibleSections
local buttons, headers = {}, {}
local layoutRows, layoutSections = {}, nil
local layoutWidth, layoutHeight, layoutTotalHeight = nil, nil, 0
local layoutCell, layoutVersion = CELL_WIDTH, 0
local renderedVersion, renderedFirst, renderedLast = -1, 1, 0
local activeHeaders, activeButtons = 0, 0
local pendingRender, renderTicker
local renderToken = 0
local suppressSizeLayout, suppressScroll = false, false
local placedOn -- the tab or overflow button the emote tab is anchored to
local hovered = false

local function CompareCommands(left, right)
	local a = left.lower or left.command:lower()
	local b = right.lower or right.command:lower()
	local order = type(strcmputf8i) == "function" and strcmputf8i(a, b)
	if type(order) == "number" then
		if order ~= 0 then
			return order < 0
		end
	elseif a ~= b then
		return a < b
	end
	return left.token < right.token
end

local function FactionTokens()
	local alliance = type(EMOTE454_TOKEN) == "string" and EMOTE454_TOKEN or "FORTHEALLIANCE"
	local horde = type(EMOTE455_TOKEN) == "string" and EMOTE455_TOKEN or "FORTHEHORDE"
	return alliance, horde
end

local function OppositeFactionToken(faction)
	local alliance, horde = FactionTokens()
	if faction == "Alliance" then
		return horde
	elseif faction == "Horde" then
		return alliance
	end
end

-- The emotes in three sections: the ones with an animation and the spoken ones as in the game's chat menu, then every
-- emote of the game sorted by its command. lookup(name) reads EMOTE<n>_TOKEN / EMOTE<n>_CMD<k>; animated and voiced
-- are the game's lists of tokens; faction optionally hides the opposite faction's battle cry.
function Emotes.BuildSections(lookup, animated, voiced, maxIndex, faction)
	local byToken, all = {}, {}
	local skipToken = OppositeFactionToken(faction)
	for index = 1, ns.Number(maxIndex, 0) do
		local token = lookup("EMOTE" .. index .. "_TOKEN")
		local command = lookup("EMOTE" .. index .. "_CMD1")
		if type(token) == "string" and token ~= "" and token ~= "UNUSED" and token ~= skipToken
			and type(command) == "string" and command ~= "" and not byToken[token] then
			local lower = command:lower()
			local searchParts = { lower, token:lower() }
			local aliases, seen = {}, { [lower] = true }
			for aliasIndex = 2, MAX_CMD_ALIAS do
				local alias = lookup("EMOTE" .. index .. "_CMD" .. aliasIndex)
				if type(alias) ~= "string" or alias == "" then
					break
				end
				local aliasLower = alias:lower()
				if not seen[aliasLower] then
					seen[aliasLower] = true
					aliases[#aliases + 1] = alias
					searchParts[#searchParts + 1] = aliasLower
				end
			end
			local entry = {
				token = token,
				command = command,
				lower = lower,
				aliases = aliases,
				search = table.concat(searchParts, "\0"),
			}
			byToken[token] = entry
			all[#all + 1] = entry
		end
	end
	table.sort(all, CompareCommands)
	local function Pick(list)
		local out = {}
		for _, token in ipairs(type(list) == "table" and list or {}) do
			if type(token) == "string" and token ~= "" and token ~= "UNUSED" and token ~= skipToken then
				local fallback = byToken[token]
				if not fallback then
					local lower = token:lower()
					fallback = { token = token, command = token, lower = lower, aliases = {}, search = lower }
				end
				out[#out + 1] = fallback
			end
		end
		return out
	end
	return {
		{ title = L.CHATEMOTES_ANIMATED, entries = Pick(animated) },
		{ title = L.CHATEMOTES_VOICE, entries = Pick(voiced) },
		{ title = L.CHATEMOTES_ALL, entries = all },
	}
end

local function MatchesQuery(entry, needle)
	if entry.search then
		return entry.search:find(needle, 1, true) ~= nil
	end
	if entry.command:lower():find(needle, 1, true) or entry.token:lower():find(needle, 1, true) then
		return true
	end
	for _, alias in ipairs(entry.aliases or {}) do
		if alias:lower():find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- Empty query keeps the three sections; a non-empty query searches the full deduplicated list (matching command,
-- aliases and token, with or without leading slash).
function Emotes.FilterSections(sections, query)
	local trimmed = type(query) == "string" and strtrim(query) or ""
	if trimmed == "" then
		return sections
	end
	local needle = trimmed:gsub("^/+", ""):lower()
	if needle == "" then
		return sections
	end
	local source = sections[3] and sections[3].entries or {}
	local matches = {}
	for _, entry in ipairs(source) do
		if MatchesQuery(entry, needle) then
			matches[#matches + 1] = entry
		end
	end
	if #matches == 0 then
		return {}
	end
	return {
		{ title = L.CHATEMOTES_MATCHES:format(#matches), entries = matches },
	}
end

-- "For the Alliance/Horde" follows the player's own faction, as in Blizzard's chat menu.
function Emotes.ResolveToken(token, faction)
	local alliance, horde = FactionTokens()
	if token == alliance or token == horde then
		if faction == "Alliance" then
			return alliance
		elseif faction == "Horde" then
			return horde
		end
	end
	return token
end

local function Perform(token)
	local faction = UnitFactionGroup and UnitFactionGroup("player", true)
	C_ChatInfo.PerformEmote(Emotes.ResolveToken(token, faction))
end

local function Lookup(name)
	return _G[name]
end

local function IsOpen()
	return panel and panel:IsShown() or false
end

local function SelectedChatFrame()
	return (GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK))
		or DEFAULT_CHAT_FRAME
end

local function TabFadeEnabled()
	local chat = ns:GetModule("Chat")
	return chat and chat.db and chat.db.tabFade or false
end

local function SyncTabAppearance()
	if not tab then
		return
	end
	local open = IsOpen()
	local selected = SelectedChatFrame()
	local chatFadedIn = selected and selected.hasBeenFaded or false
	local color = NORMAL_FONT_COLOR
	if open or hovered then
		tab.Text:SetTextColor(1, 1, 1)
	elseif color then
		tab.Text:SetTextColor(color.r, color.g, color.b)
	else
		tab.Text:SetTextColor(1, 0.82, 0)
	end
	if tab.ActiveLine then
		tab.ActiveLine:SetShown(open)
	end
	if open then
		tab:SetAlpha((chatFadedIn or hovered) and 1 or 0.8)
		tab.Text:SetAlpha(1)
	elseif hovered then
		tab:SetAlpha(1)
		tab.Text:SetAlpha(1)
	elseif chatFadedIn then
		tab:SetAlpha(ns.Number(CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA, 0.6))
		tab.Text:SetAlpha(1)
	else
		tab:SetAlpha(ns.Number(CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA, 0.2))
		tab.Text:SetAlpha(TabFadeEnabled() and 0 or 1)
	end
end

local function OnEmoteClick(button)
	if button.token then
		Perform(button.token)
	end
end

local function OnEmoteEnter(button)
	local entry = button.entry
	if not entry then
		return
	end
	local truncated = button.Text and button.Text.IsTruncated and button.Text:IsTruncated()
	local aliases = entry.aliases
	if not truncated and (not aliases or #aliases == 0) then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip_SetTitle(GameTooltip, entry.command)
	if aliases and #aliases > 0 then
		GameTooltip:AddLine(table.concat(aliases, ", "), 0.75, 0.75, 0.75, true)
	end
	GameTooltip:Show()
end

local function OnEmoteLeave()
	GameTooltip_Hide()
end

local measuredEmoteClick = ns.Measured("ChatEmotes: emote", OnEmoteClick)

-- Builds the flat row list (headers + grid rows) for the visible sections and column count.
function Emotes.BuildRows(sections, columns)
	columns = math.max(1, columns or 1)
	local rows = {}
	local y, totalEntries = 0, 0
	for _, section in ipairs(sections or {}) do
		local entries = section.entries
		local count = entries and #entries or 0
		if count > 0 then
			totalEntries = totalEntries + count
			rows[#rows + 1] = {
				header = section.title,
				y = y,
				height = HEADER_HEIGHT,
			}
			y = y + HEADER_HEIGHT
			local rowCount = math.ceil(count / columns)
			for row = 0, rowCount - 1 do
				local first = row * columns + 1
				local last = math.min(count, first + columns - 1)
				rows[#rows + 1] = {
					entries = entries,
					first = first,
					last = last,
					y = y,
					height = ROW_HEIGHT,
				}
				y = y + ROW_HEIGHT
			end
			y = y + SECTION_GAP
		end
	end
	return rows, y, totalEntries
end

-- First and last row indices intersecting the scroll viewport (plus one buffer row on each side).
function Emotes.VisibleRange(rows, offset, viewHeight)
	local count = #rows
	if count == 0 or viewHeight <= 0 then
		return 1, 0
	end
	local top = math.max(0, offset - ROW_HEIGHT)
	local bottom = offset + viewHeight + ROW_HEIGHT
	local lo, hi = 1, count
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if rows[mid].y + rows[mid].height <= top then
			lo = mid + 1
		else
			hi = mid
		end
	end
	if rows[lo].y + rows[lo].height <= top or rows[lo].y >= bottom then
		return 1, 0
	end
	local first = lo
	local last = first
	while last < count and rows[last + 1].y < bottom do
		last = last + 1
	end
	return first, last
end

local function AcquireHeader(index)
	local header = headers[index]
	if not header then
		header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		header:SetJustifyH("LEFT")
		headers[index] = header
	end
	return header
end

local function AcquireButton(index)
	local button = buttons[index]
	if not button then
		button = CreateFrame("Button", nil, content)
		button:SetHeight(ROW_HEIGHT)
		button:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		text:SetPoint("LEFT", INSET, 0)
		text:SetPoint("RIGHT", -2, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		button.Text = text
		button:SetScript("OnClick", measuredEmoteClick)
		button:SetScript("OnEnter", OnEmoteEnter)
		button:SetScript("OnLeave", OnEmoteLeave)
		buttons[index] = button
	end
	return button
end

local function HideUnused(usedHeaders, usedButtons)
	for index = usedHeaders + 1, activeHeaders do
		local header = headers[index]
		header:Hide()
		header.shown = false
	end
	activeHeaders = usedHeaders
	for index = usedButtons + 1, activeButtons do
		local button = buttons[index]
		button:Hide()
		button.shown = false
	end
	activeButtons = usedButtons
end

local function PlaceHeader(index, title, y, width)
	local header = AcquireHeader(index)
	if header.title ~= title then
		header:SetText(title)
		header.title = title
	end
	if header.y ~= y then
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", content, "TOPLEFT", INSET, -y - 3)
		header.y = y
	end
	local headerWidth = math.max(1, width - INSET * 2)
	if header.width ~= headerWidth then
		header:SetWidth(headerWidth)
		header.width = headerWidth
	end
	if not header.shown then
		header:Show()
		header.shown = true
	end
end

local function PlaceButton(index, entry, x, y, cell)
	local button = AcquireButton(index)
	button.entry = entry
	button.token = entry.token
	if button.command ~= entry.command then
		button.Text:SetText(entry.command)
		button.command = entry.command
	end
	if button.x ~= x or button.y ~= y then
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		button.x, button.y = x, y
	end
	if button.width ~= cell then
		button:SetWidth(cell)
		button.width = cell
	end
	if not button.shown then
		button:Show()
		button.shown = true
	end
end

local function CancelRender()
	renderToken = renderToken + 1
	if renderTicker then
		renderTicker:Cancel()
		renderTicker = nil
	end
	pendingRender = nil
end

local function ScrollViewHeight()
	local height = ns.Number(scroll and scroll:GetHeight(), 0)
	if height <= 0 and panel then
		height = math.max(0, ns.Number(panel:GetHeight(), 0) - (SEARCH_HEIGHT + INSET + 6))
	end
	return height
end

local RenderVisible

local function ScheduleRender()
	if renderTicker then
		return
	end
	renderToken = renderToken + 1
	local token = renderToken
	renderTicker = ns.NewTicker("ChatEmotes: render", 0, function(ticker)
		if token ~= renderToken or not IsOpen() or not pendingRender then
			ticker:Cancel()
			if renderTicker == ticker then
				renderTicker = nil
			end
			return
		end
		RenderVisible(false, debugprofilestop() + RENDER_BUDGET)
		if not pendingRender then
			ticker:Cancel()
			if renderTicker == ticker then
				renderTicker = nil
			end
		end
	end)
	if not pendingRender then
		renderTicker = nil
	end
end

-- Renders only the rows currently visible in the scroll viewport, yielding across frames when
-- creating new pooled buttons would exceed the frame budget.
RenderVisible = function(force, deadline)
	if not (panel and scroll and visibleSections) then
		return
	end
	local viewHeight = ScrollViewHeight()
	local offset = ns.Number(scroll:GetVerticalScroll(), 0)
	local first, last = Emotes.VisibleRange(layoutRows, offset, viewHeight)

	if not force and not pendingRender
		and renderedVersion == layoutVersion and renderedFirst == first and renderedLast == last then
		return
	end

	local rowIndex, usedHeaders, usedButtons
	if pendingRender and not force
		and pendingRender.version == layoutVersion and pendingRender.first == first and pendingRender.last == last then
		rowIndex = pendingRender.row
		usedHeaders = pendingRender.usedHeaders
		usedButtons = pendingRender.usedButtons
	else
		CancelRender()
		rowIndex, usedHeaders, usedButtons = first, 0, 0
	end

	local width, cell = layoutWidth or 0, layoutCell
	for r = rowIndex, last do
		local row = layoutRows[r]
		if row.header then
			usedHeaders = usedHeaders + 1
			PlaceHeader(usedHeaders, row.header, row.y, width)
		else
			local entries = row.entries
			local column = 0
			for position = row.first, row.last do
				usedButtons = usedButtons + 1
				PlaceButton(usedButtons, entries[position], column * cell, row.y, cell)
				column = column + 1
			end
		end
		if deadline and r < last and debugprofilestop() >= deadline then
			HideUnused(usedHeaders, usedButtons)
			pendingRender = {
				version = layoutVersion,
				first = first,
				last = last,
				row = r + 1,
				usedHeaders = usedHeaders,
				usedButtons = usedButtons,
			}
			ScheduleRender()
			return
		end
	end

	HideUnused(usedHeaders, usedButtons)
	pendingRender = nil
	renderedVersion, renderedFirst, renderedLast = layoutVersion, first, last
end

local function Layout(deadline)
	if not panel or not visibleSections or not IsOpen() then
		return
	end
	local width = ns.Number(scroll:GetWidth(), 0)
	if width <= 0 then
		return
	end
	local viewHeight = ScrollViewHeight()
	local sameWidth = layoutWidth == width
	local sameSections = layoutSections == visibleSections
	if sameWidth and layoutHeight == viewHeight and sameSections
		and (renderedVersion == layoutVersion or (pendingRender and pendingRender.version == layoutVersion)) then
		return
	end
	layoutHeight = viewHeight
	if not (sameWidth and sameSections) then
		local columns = math.max(1, math.floor(width / CELL_WIDTH))
		local rows, totalHeight, totalEntries = Emotes.BuildRows(visibleSections, columns)
		layoutRows = rows
		layoutSections = visibleSections
		layoutWidth = width
		layoutCell = width / columns
		layoutTotalHeight = totalHeight
		layoutVersion = layoutVersion + 1
		if emptyText then
			emptyText:SetShown(totalEntries == 0)
		end
		content:SetSize(width, math.max(totalHeight, 1))
		if scroll.UpdateScrollChildRect then
			scroll:UpdateScrollChildRect()
		end
	end
	local maxScroll = math.max(0, layoutTotalHeight - viewHeight)
	local offset = ns.Number(scroll:GetVerticalScroll(), 0)
	if offset > maxScroll and scroll.SetVerticalScroll then
		suppressScroll = true
		scroll:SetVerticalScroll(maxScroll)
		suppressScroll = false
	end
	RenderVisible(not (sameWidth and sameSections), deadline or (debugprofilestop() + RENDER_BUDGET))
end

local function ApplyFilter()
	if not allSections then
		return
	end
	local query = searchBox and searchBox:GetText() or ""
	if clearButton then
		clearButton:SetShown(query ~= "")
	end
	if searchBox and searchBox.Placeholder then
		searchBox.Placeholder:SetShown(query == "")
	end
	visibleSections = Emotes.FilterSections(allSections, query)
	if scroll and scroll.SetVerticalScroll then
		suppressScroll = true
		scroll:SetVerticalScroll(0)
		suppressScroll = false
	end
	Layout(debugprofilestop() + RENDER_BUDGET)
end

local function BuildPanel()
	if panel then
		return
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player", true)
	allSections = Emotes.BuildSections(Lookup, EmoteList, TextEmoteSpeechList, MAXEMOTEINDEX, faction)
	visibleSections = allSections

	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("MEDIUM")
	panel:EnableMouse(true)
	panel:Hide()

	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.85)
	if ns.CreatePixelBorder then
		ns.CreatePixelBorder(panel, panel, 1, "BORDER")
	end

	-- Compact search bar at the top; never steals keyboard focus when opened.
	local searchBg = CreateFrame("Frame", nil, panel)
	searchBg:SetPoint("TOPLEFT", INSET, -INSET)
	searchBg:SetPoint("TOPRIGHT", -INSET, -INSET)
	searchBg:SetHeight(SEARCH_HEIGHT)
	local searchFill = searchBg:CreateTexture(nil, "BACKGROUND")
	searchFill:SetAllPoints()
	searchFill:SetColorTexture(1, 1, 1, 0.08)

	searchBox = CreateFrame("EditBox", nil, searchBg)
	searchBox:SetPoint("TOPLEFT", 5, 0)
	searchBox:SetPoint("BOTTOMRIGHT", -18, 0)
	searchBox:SetFontObject("GameFontHighlightSmall")
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(40)
	searchBox.Placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	searchBox.Placeholder:SetPoint("LEFT", 1, 0)
	searchBox.Placeholder:SetText(L.CHATEMOTES_SEARCH)
	searchBox:SetScript("OnTextChanged", ns.Measured("ChatEmotes: search", ApplyFilter))
	searchBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	clearButton = CreateFrame("Button", nil, searchBg)
	clearButton:SetSize(16, 16)
	clearButton:SetPoint("RIGHT", -2, 0)
	clearButton.Text = clearButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	clearButton.Text:SetPoint("CENTER")
	clearButton.Text:SetText("x")
	clearButton:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
	end)
	clearButton:SetScript("OnEnter", function(self)
		self.Text:SetTextColor(1, 1, 1)
	end)
	clearButton:SetScript("OnLeave", function(self)
		local color = NORMAL_FONT_COLOR
		if color then
			self.Text:SetTextColor(color.r, color.g, color.b)
		end
	end)
	clearButton:Hide()

	scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 2, -(SEARCH_HEIGHT + INSET + 3))
	scroll:SetPoint("BOTTOMRIGHT", -18, 3)
	scroll:EnableMouseWheel(true)
	if scroll.SetPanExtent then
		scroll:SetPanExtent(ROW_HEIGHT * 3)
	end
	if scroll.ScrollBar then
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
		if scroll.ScrollBar.SetHideIfUnscrollable then
			scroll.ScrollBar:SetHideIfUnscrollable(true)
		end
	end

	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local onScroll = ns.Measured("ChatEmotes: scroll", function()
		if not suppressScroll and IsOpen() then
			RenderVisible(false, debugprofilestop() + RENDER_BUDGET)
		end
	end)
	if scroll.GetScript and scroll:GetScript("OnVerticalScroll") and scroll.HookScript then
		scroll:HookScript("OnVerticalScroll", onScroll)
	else
		scroll:SetScript("OnVerticalScroll", onScroll)
	end

	emptyText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	emptyText:SetPoint("CENTER", scroll, "CENTER")
	emptyText:SetText(L.CHATEMOTES_EMPTY)
	emptyText:Hide()

	panel:SetScript("OnSizeChanged", ns.Measured("ChatEmotes: layout", function()
		if not suppressSizeLayout then
			Layout()
		end
	end))
end

local function Close()
	CancelRender()
	if searchBox and searchBox.ClearFocus then
		searchBox:ClearFocus()
	end
	if panel then
		panel:Hide()
	end
	SyncTabAppearance()
end

-- Over the background of the chat window that is shown in the dock.
local function Open()
	local deadline = debugprofilestop() + OPEN_BUDGET
	BuildPanel()
	local chatFrame = SelectedChatFrame()
	local area = chatFrame and (chatFrame.Background or chatFrame)
	if not area then
		return
	end
	panel:SetFrameLevel(math.max(ns.Number(chatFrame:GetFrameLevel(), 5) + 20, 30))
	suppressSizeLayout = true
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", area, "TOPLEFT")
	panel:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	panel:Show()
	suppressSizeLayout = false
	Layout(deadline)
	SyncTabAppearance()
end

local function Toggle()
	PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	if IsOpen() then
		Close()
	else
		Open()
	end
end

-- The anchor right of the docked tabs: the overflow arrow if tabs overflow, otherwise the rightmost visible tab
-- (by default the combat log).
local function DockAnchor()
	if not GENERAL_CHAT_DOCK then
		return nil, false
	end
	local overflow = GENERAL_CHAT_DOCK.overflowButton
	if overflow and overflow:IsShown() then
		return overflow, true
	end
	local frames = GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
	if type(frames) ~= "table" then
		return nil, false
	end
	for index = #frames, 1, -1 do
		local name = frames[index] and frames[index]:GetName()
		local chatTab = name and _G[name .. "Tab"]
		if chatTab and chatTab:IsShown() then
			return chatTab, false
		end
	end
end

local function CreateTab()
	tab = CreateFrame("Button", "ForeverPlusEmotesTab", GENERAL_CHAT_DOCK or UIParent)
	tab:SetHeight(32)
	tab.Text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	tab.Text:SetPoint("CENTER", 0, -5)
	tab.Text:SetText(L.CHATEMOTES_TAB)
	local width = math.max(56, ns.Number(tab.Text:GetStringWidth(), 40) + 20)
	tab:SetWidth(width)

	-- Subtle active underline matching ForeverPlus's borderless tab style.
	tab.ActiveLine = tab:CreateTexture(nil, "ARTWORK")
	tab.ActiveLine:SetHeight(1)
	tab.ActiveLine:SetPoint("TOPLEFT", tab.Text, "BOTTOMLEFT", -2, -2)
	tab.ActiveLine:SetPoint("TOPRIGHT", tab.Text, "BOTTOMRIGHT", 2, -2)
	local color = NORMAL_FONT_COLOR
	if color then
		tab.ActiveLine:SetColorTexture(color.r, color.g, color.b, 0.9)
	else
		tab.ActiveLine:SetColorTexture(1, 0.82, 0, 0.9)
	end
	tab.ActiveLine:Hide()

	tab:RegisterForClicks("LeftButtonUp")
	tab:SetScript("OnClick", ns.Measured("ChatEmotes: tab", Toggle))
	tab:SetScript("OnEnter", function(self)
		hovered = true
		SyncTabAppearance()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.CHATEMOTES_TAB)
		if GREEN_FONT_COLOR then
			GameTooltip_AddColoredLine(GameTooltip, L.CHATEMOTES_TIP, GREEN_FONT_COLOR)
		else
			GameTooltip:AddLine(L.CHATEMOTES_TIP, 0.1, 1, 0.1)
		end
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		hovered = false
		SyncTabAppearance()
		GameTooltip_Hide()
	end)
end

local function Place()
	local anchor, isOverflow
	if Emotes.db.enabled then
		anchor, isOverflow = DockAnchor()
	end
	if not anchor then
		if tab then
			tab:Hide()
		end
		placedOn = nil
		Close()
		return
	end
	if not tab then
		CreateTab()
	end
	if GENERAL_CHAT_DOCK and tab:GetParent() ~= GENERAL_CHAT_DOCK then
		tab:SetParent(GENERAL_CHAT_DOCK)
	end
	if anchor ~= placedOn then
		placedOn = anchor
		tab:ClearAllPoints()
		if isOverflow then
			tab:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 2, -6)
		else
			tab:SetPoint("LEFT", anchor, "RIGHT", 1, 0)
		end
	end
	tab:Show()
	SyncTabAppearance()
end

function Emotes:OnLogin()
	if _G.FCFDock_UpdateTabs then
		hooksecurefunc("FCFDock_UpdateTabs", ns.Measured("ChatEmotes: place", function(dock)
			if dock == GENERAL_CHAT_DOCK then
				Place()
			end
		end))
	end
	-- Selecting another chat tab closes the emote list.
	if _G.FCF_Tab_OnClick then
		hooksecurefunc("FCF_Tab_OnClick", function(_, mouseButton)
			if mouseButton == "LeftButton" then
				Close()
			end
		end)
	end
	if _G.FCF_SelectDockFrame then
		hooksecurefunc("FCF_SelectDockFrame", Close)
	end
	for _, name in ipairs({ "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame", "FCFTab_UpdateAlpha" }) do
		if _G[name] then
			hooksecurefunc(name, SyncTabAppearance)
		end
	end
	local chat = ns:GetModule("Chat")
	if chat and chat.UpdateTabFade then
		hooksecurefunc(chat, "UpdateTabFade", SyncTabAppearance)
	end
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", Place)
	Place()
end

function Emotes:OnOptionChanged()
	Place()
end

Emotes.options = {
	{ key = "enabled", type = "toggle", name = L.CHATEMOTES, desc = L.CHATEMOTES_DESC },
}

-- Emote tab: a tab of its own to the right of the last chat tab (normally the combat log). A click shows every emote
-- of the game over the chat window, a click on an emote performs it, as in the game's chat menu (speech bubble).
-- The tab is an own button in the look of the chat tabs, it is not a chat window: Blizzard's dock, tabs and chat
-- windows stay untouched (only read). It hangs on the last tab, so it fades and hides with it.
local _, ns = ...
local L = ns.L

local Emotes = ns:NewModule("ChatEmotes", {
	title = L.CHATEMOTES_TITLE,
	order = 5.97,
	defaults = {
		enabled = true,
	},
})

local CELL_WIDTH = 100 -- smallest width of a column
local ROW_HEIGHT = 16
local HEADER_HEIGHT = 20
local SECTION_GAP = 6
local INSET = 4

local tab, panel, scroll, content
local sections
local buttons, headers = {}, {}
local placedOn -- the tab the emote tab hangs on

-- The emotes in three sections: the ones with an animation and the spoken ones as in the game's chat menu, then every
-- emote of the game sorted by its command. lookup(name) reads one of the game's EMOTE<n>_TOKEN / EMOTE<n>_CMD1
-- strings; animated and voiced are the game's lists of tokens.
function Emotes.BuildSections(lookup, animated, voiced, maxIndex)
	local commands, all = {}, {}
	for index = 1, ns.Number(maxIndex, 0) do
		local token, command = lookup("EMOTE" .. index .. "_TOKEN"), lookup("EMOTE" .. index .. "_CMD1")
		if type(token) == "string" and type(command) == "string" and not commands[token] then
			commands[token] = command
			all[#all + 1] = { token = token, command = command }
		end
	end
	table.sort(all, function(a, b)
		local left, right = a.command:lower(), b.command:lower()
		if left ~= right then
			return left < right
		end
		return a.token < b.token
	end)
	local function Pick(list)
		local out = {}
		for _, token in ipairs(type(list) == "table" and list or {}) do
			if type(token) == "string" then
				out[#out + 1] = { token = token, command = commands[token] or token }
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

-- "For the Alliance/Horde" follows the own faction, as in the game's menu.
local function Perform(token)
	if token == EMOTE454_TOKEN or token == EMOTE455_TOKEN then
		local faction = UnitFactionGroup("player", true)
		if faction == "Alliance" then
			token = EMOTE454_TOKEN
		elseif faction == "Horde" then
			token = EMOTE455_TOKEN
		end
	end
	C_ChatInfo.PerformEmote(token)
end

local function Lookup(name)
	return _G[name]
end

local function SetSelected(selected)
	for _, key in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do
		local texture = tab[key]
		if texture then
			texture:SetShown(selected)
		end
	end
end

local function Layout()
	if not panel or not sections then
		return
	end
	local width = ns.Number(scroll:GetWidth(), 0)
	if width <= 0 then
		return
	end
	local columns = math.max(1, math.floor(width / CELL_WIDTH))
	local cell = width / columns
	local y, used = 0, 0
	for index, section in ipairs(sections) do
		local header = headers[index]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", content, "TOPLEFT", INSET, -y - 4)
		y = y + HEADER_HEIGHT
		for position, _ in ipairs(section.entries) do
			used = used + 1
			local button = buttons[used]
			local column, row = (position - 1) % columns, math.floor((position - 1) / columns)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", content, "TOPLEFT", column * cell, -(y + row * ROW_HEIGHT))
			button:SetWidth(cell)
		end
		y = y + math.ceil(#section.entries / columns) * ROW_HEIGHT + SECTION_GAP
	end
	content:SetSize(width, math.max(y, 1))
end

local function OnEmoteClick(button)
	Perform(button.token)
end

local function CreateEmoteButton(entry)
	local button = CreateFrame("Button", nil, content)
	button:SetHeight(ROW_HEIGHT)
	button:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
	local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", INSET, 0)
	text:SetPoint("RIGHT", -2, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetText(entry.command)
	button.token = entry.token
	button:SetScript("OnClick", ns.Measured("ChatEmotes: emote", OnEmoteClick))
	return button
end

local function BuildPanel()
	if panel then
		return
	end
	sections = Emotes.BuildSections(Lookup, EmoteList, TextEmoteSpeechList, MAXEMOTEINDEX)
	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("MEDIUM")
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:Hide()
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.85)
	scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 2, -2)
	scroll:SetPoint("BOTTOMRIGHT", -22, 2)
	scroll:EnableMouseWheel(true)
	scroll:SetPanExtent(ROW_HEIGHT * 3)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	for index, section in ipairs(sections) do
		local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		header:SetText(section.title)
		headers[index] = header
		for _, entry in ipairs(section.entries) do
			buttons[#buttons + 1] = CreateEmoteButton(entry)
		end
	end
	panel:SetScript("OnSizeChanged", ns.Measured("ChatEmotes: layout", Layout))
end

local function Close()
	if panel then
		panel:Hide()
	end
	if tab then
		SetSelected(false)
	end
end

-- Over the background of the chat window that is shown in the dock.
local function Open()
	BuildPanel()
	local chatFrame = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or DEFAULT_CHAT_FRAME
	local area = chatFrame and (chatFrame.Background or chatFrame)
	if not area then
		return
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", area, "TOPLEFT")
	panel:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	panel:Show()
	Layout()
	SetSelected(true)
end

local function Toggle()
	if panel and panel:IsShown() then
		Close()
	else
		Open()
	end
end

-- The tab furthest right in the dock that is shown.
local function LastTab()
	local frames = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
	if type(frames) ~= "table" then
		return nil
	end
	for index = #frames, 1, -1 do
		local name = frames[index] and frames[index]:GetName()
		local chatTab = name and _G[name .. "Tab"]
		if chatTab and chatTab:IsShown() then
			return chatTab
		end
	end
end

local function LabelOf(chatTab)
	return chatTab and (chatTab.Text or _G[(chatTab:GetName() or "") .. "Text"])
end

-- The chat module can fade the tab labels; the label of the emote tab follows the tab it hangs on.
local function SyncLabel()
	local label = LabelOf(placedOn)
	if tab and label and label.GetAlpha then
		tab.Text:SetAlpha(label:GetAlpha())
	end
end

local function CreateTab()
	tab = CreateFrame("Button", nil, UIParent, "ChatTabArtTemplate")
	tab:SetAlpha(1)
	tab.Text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	tab.Text:SetPoint("CENTER", 0, -5)
	tab.Text:SetText(L.CHATEMOTES_TAB)
	tab:SetWidth(math.max(64, ns.Number(tab.Text:GetStringWidth(), 40) + 28))
	local color = DEFAULT_TAB_SELECTED_COLOR_TABLE
	if type(color) == "table" then
		for _, key in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
			if tab[key] then
				tab[key]:SetVertexColor(color.r, color.g, color.b)
			end
		end
	end
	tab:RegisterForClicks("LeftButtonUp")
	tab:SetScript("OnClick", ns.Measured("ChatEmotes: tab", Toggle))
	SetSelected(false)
end

local function Place()
	local anchor = Emotes.db.enabled and LastTab()
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
	if anchor ~= placedOn then
		placedOn = anchor
		tab:SetParent(anchor)
		tab:ClearAllPoints()
		tab:SetPoint("LEFT", anchor, "RIGHT", 1, 0)
	end
	tab:Show()
	SyncLabel()
end

function Emotes:OnLogin()
	hooksecurefunc("FCFDock_UpdateTabs", ns.Measured("ChatEmotes: place", function(dock)
		if dock == GENERAL_CHAT_DOCK then
			Place()
		end
	end))
	-- Another tab selected: back to the chat.
	hooksecurefunc("FCF_Tab_OnClick", function(_, mouseButton)
		if mouseButton == "LeftButton" then
			Close()
		end
	end)
	for _, name in ipairs({ "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame", "FCFTab_UpdateAlpha" }) do
		hooksecurefunc(name, SyncLabel)
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

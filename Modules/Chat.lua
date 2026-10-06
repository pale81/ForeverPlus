-- Chat: cleaner chat frame that keeps the original look.
local _, ns = ...
local L = ns.L

local Chat = ns:NewModule("Chat", {
	title = L.CHAT_TITLE,
	order = 1,
	defaults = {
		hideButtons = true,
		transparent = true,
		languageClick = true,
		languageMessage = true,
		tabFade = true,
		keywordAlert = false,
		keywordSound = "RAID_WARNING",
		keywordHighlight = false,
		keywordColor = "ORANGE",
		channelShort = false,
		timestampColor = false,
		timestampColorValue = "GREY",
		mouseScroll = true,
		inputHistory = true,
		chatLog = true,
		chatLogLines = 200,
		copyButton = true,
	},
	charDefaults = {
		transparencyApplied = false,
		sentHistory = {}, -- lines typed into the chat, newest last
		chatLog = {},     -- chat window ID -> { { text, r, g, b }, ... }
	},
})

local styled = {}
local buttonParents = {}

local TAB_TEXTURES = {
	"Left", "Middle", "Right",
	"ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}

local function ChatButtons()
	return ChatFrameMenuButton, ChatFrameChannelButton, QuickJoinToastButton
end

function Chat:UpdateButtons()
	local hide = self.db.hideButtons
	for _, button in ipairs({ ChatButtons() }) do
		if hide then
			if button:GetParent() ~= ns.hider then
				buttonParents[button] = buttonParents[button] or button:GetParent()
				button:SetParent(ns.hider)
			end
		elseif buttonParents[button] then
			button:SetParent(buttonParents[button])
			buttonParents[button] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Middle-click on a chat tab switches to the next language. Uses the same
-- call as Blizzard's language menu; the value it stores comes from addon code.
---------------------------------------------------------------------------
local function NextLanguage()
	local editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
	local count = GetNumLanguages and GetNumLanguages() or 0
	if not editBox or count < 2 then
		return
	end
	local current = editBox.languageID
	local nextIndex = 1
	for i = 1, count do
		local _, languageID = GetLanguageByIndex(i)
		if languageID == current then
			nextIndex = i % count + 1
			break
		end
	end
	local language, languageID = GetLanguageByIndex(nextIndex)
	editBox:SetGameLanguage(language, languageID)
	if Chat.db.languageMessage then
		ns.Print(L.CHAT_LANGUAGE_NOW:format(language))
	end
end

local hookedTabs = {}

local function HookTab(tab)
	if not tab or hookedTabs[tab] then
		return
	end
	hookedTabs[tab] = true
	tab:HookScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "MiddleButton" and Chat.db.languageClick then
			NextLanguage()
		end
	end)
end

---------------------------------------------------------------------------
-- Tab labels fade with the chat: visible while the mouse is over the chat
-- (or a tab alerts), like the background. Only the label alpha is changed;
-- Blizzard's own tab alpha values stay untouched.
---------------------------------------------------------------------------
local function TabLabel(tab)
	return tab and (tab.Text or _G[tab:GetName() .. "Text"])
end

local function SetTabsShown(chatFrame, shown)
	if not Chat.db.tabFade then
		return
	end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if frame == chatFrame or (chatFrame.isDocked and frame.isDocked) then
			local tab = _G[name .. "Tab"]
			local label = TabLabel(tab)
			if label then
				local alerting = ChatFrameUtil.IsTabAlerting and ChatFrameUtil.IsTabAlerting(tab)
				label:SetAlpha((shown or alerting) and 1 or 0)
			end
		end
	end
end

function Chat:UpdateTabFade()
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		local label = TabLabel(_G[name .. "Tab"])
		if label then
			label:SetAlpha((not self.db.tabFade or frame.hasBeenFaded) and 1 or 0)
		end
	end
end

local function StyleTab(tab)
	if not tab then
		return
	end
	for _, key in ipairs(TAB_TEXTURES) do
		local texture = tab[key]
		if texture then
			texture:SetTexture(nil)
		end
	end
end

local function StyleEditBox(chatFrame)
	local editBox = chatFrame.editBox
	if not editBox then
		return
	end
	local name = editBox:GetName()
	for _, suffix in ipairs({ "Left", "Mid", "Right" }) do
		local texture = _G[name .. suffix]
		if texture then
			texture:SetAlpha(0)
		end
	end
	editBox.focusLeft:SetAlpha(0)
	editBox.focusMid:SetAlpha(0)
	editBox.focusRight:SetAlpha(0)

	-- Move above the tabs (the tab dock is 26px high on top of the background).
	local anchor = chatFrame.Background or chatFrame
	editBox:ClearAllPoints()
	editBox:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -5, 22)
	editBox:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 5, 22)

	-- Up/Down browse the sent history without holding Alt.
	editBox:SetAltArrowKeyMode(false)
end

---------------------------------------------------------------------------
-- Mouse wheel: Blizzard wires it only if the CVar chatMouseScroll was on
-- when the chat frame loaded. Shift + wheel jumps to the top or bottom.
---------------------------------------------------------------------------
local wheelHooked = {}

local function OnChatWheel(chatFrame, delta)
	if not Chat.db.mouseScroll then
		return
	end
	if IsShiftKeyDown() then
		if delta > 0 then
			chatFrame:ScrollToTop()
		else
			chatFrame:ScrollToBottom()
		end
	elseif chatFrame.ScrollByAmount then
		chatFrame:ScrollByAmount(delta * 3)
	elseif delta > 0 then
		chatFrame:ScrollUp()
	else
		chatFrame:ScrollDown()
	end
end

local function EnableWheel(chatFrame)
	if wheelHooked[chatFrame] or chatFrame:IsMouseWheelEnabled() then
		return
	end
	wheelHooked[chatFrame] = true
	chatFrame:EnableMouseWheel(true)
	chatFrame:HookScript("OnMouseWheel", OnChatWheel)
end

---------------------------------------------------------------------------
-- Input history: Up/Down step through the lines sent before, also those of
-- the last sessions (kept per character).
---------------------------------------------------------------------------
local MAX_SENT = 50
local historyHooked = {}
local historyPos = {}

local function RecordSent(_, text)
	if type(text) ~= "string" or text == "" or (issecretvalue and issecretvalue(text)) then
		return
	end
	local list = Chat.cdb.sentHistory
	if list[#list] ~= text then
		list[#list + 1] = text
		if #list > MAX_SENT then
			table.remove(list, 1)
		end
	end
end

local function OnHistoryArrow(editBox, key)
	if not Chat.db.inputHistory or (key ~= "UP" and key ~= "DOWN") then
		return
	end
	local list = Chat.cdb.sentHistory
	if #list == 0 then
		return
	end
	local pos = historyPos[editBox] or (#list + 1)
	pos = key == "UP" and math.max(1, pos - 1) or math.min(#list + 1, pos + 1)
	historyPos[editBox] = pos
	editBox:SetText(list[pos] or "")
	editBox:SetCursorPosition(#editBox:GetText())
end

local function HookHistory(editBox)
	if not editBox or historyHooked[editBox] then
		return
	end
	historyHooked[editBox] = true
	-- Our list replaces the built-in one, so both do not step at once.
	editBox:SetHistoryLines(1)
	hooksecurefunc(editBox, "AddHistoryLine", RecordSent)
	editBox:HookScript("OnArrowPressed", OnHistoryArrow)
	editBox:HookScript("OnShow", function(self)
		historyPos[self] = nil
	end)
end

---------------------------------------------------------------------------
-- Chat of the last session: the lines of the chat windows are kept per
-- character and shown again after logging in.
---------------------------------------------------------------------------
local logHooked = {}
local restoring = false

local function LogLine(chatFrame, text, r, g, b)
	if restoring or not Chat.db.chatLog or type(text) ~= "string" or text == ""
		or (issecretvalue and (issecretvalue(text) or issecretvalue(r))) then
		return
	end
	local id = chatFrame:GetID()
	local logs = Chat.cdb.chatLog
	local log = logs[id]
	if not log then
		log = {}
		logs[id] = log
	end
	log[#log + 1] = { text, r, g, b }
	local limit = Chat.db.chatLogLines
	while #log > limit do
		table.remove(log, 1)
	end
end

local function RestoreLog()
	local logs = Chat.cdb.chatLog
	restoring = true
	for id, log in pairs(logs) do
		local chatFrame = _G["ChatFrame" .. id]
		if chatFrame and #log > 0 then
			for _, line in ipairs(log) do
				chatFrame:AddMessage(line[1], line[2], line[3], line[4])
			end
			chatFrame:AddMessage(L.CHAT_LOG_SEPARATOR, 0.5, 0.5, 0.5)
		end
	end
	restoring = false
end

local function HookLog(chatFrame)
	if logHooked[chatFrame] or chatFrame:GetID() > Constants.ChatFrameConstants.MaxChatWindows then
		return
	end
	logHooked[chatFrame] = true
	hooksecurefunc(chatFrame, "AddMessage", LogLine)
end

local function StyleFont(chatFrame)
	ns.ApplyOutline(chatFrame)
end

---------------------------------------------------------------------------
-- Copy: the last lines of a chat window as plain text in a window with the
-- text selected (Ctrl+C). Links keep their visible text; colours, icons and
-- protected parts (Battle.net names) are removed.
---------------------------------------------------------------------------
local COPY_LINES = 50
local copyButtons = {}

local function PlainText(text)
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|K.-|k", "?")
	return (text:gsub("||", "|"))
end

function Chat:CopyChat(chatFrame)
	chatFrame = chatFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	local count = chatFrame:GetNumMessages()
	local lines = {}
	for index = math.max(1, count - COPY_LINES + 1), count do
		local text = chatFrame:GetMessageInfo(index)
		if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
			lines[#lines + 1] = PlainText(text)
		end
	end
	ns.ShowEditWindow("ChatCopy", L.CHAT_COPY, table.concat(lines, "\n"), CLOSE, nil, L.CHAT_COPY_HINT)
end

local function CreateCopyButton(chatFrame)
	local button = CreateFrame("Button", nil, chatFrame)
	button:SetSize(18, 18)
	button:SetPoint("TOPRIGHT", chatFrame.Background or chatFrame, "TOPRIGHT", -24, -2)
	button:SetFrameLevel(chatFrame:GetFrameLevel() + 5)
	if C_Texture.GetAtlasInfo("friends-icon-battlenet-copy") then
		button:SetNormalAtlas("friends-icon-battlenet-copy")
	else
		button:SetNormalTexture([[Interface\Buttons\UI-GuildButton-PublicNote-Up]])
	end
	button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	button:SetScript("OnClick", function()
		Chat:CopyChat(chatFrame)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.CHAT_COPY)
		GameTooltip_AddInstructionLine(GameTooltip, L.CHAT_COPY_CLICK)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetAlpha(0)
	copyButtons[chatFrame] = button
	return button
end

-- Visible like the tab labels: while the mouse is over the chat.
local function SetCopyShown(chatFrame, shown)
	local button = copyButtons[chatFrame]
	if button then
		button:SetShown(Chat.db.copyButton)
		button:SetAlpha(shown and 1 or 0)
	end
end

local function StyleChatFrame(chatFrame)
	if not chatFrame or styled[chatFrame] then
		return
	end
	styled[chatFrame] = true
	StyleFont(chatFrame)
	StyleTab(_G[chatFrame:GetName() .. "Tab"])
	HookTab(_G[chatFrame:GetName() .. "Tab"])
	StyleEditBox(chatFrame)
	EnableWheel(chatFrame)
	HookHistory(chatFrame.editBox)
	HookLog(chatFrame)
	if chatFrame.GetMessageInfo then
		CreateCopyButton(chatFrame)
		SetCopyShown(chatFrame, chatFrame.hasBeenFaded)
	end
end

local function StyleAll()
	for _, name in ipairs(CHAT_FRAMES) do
		StyleChatFrame(_G[name])
	end
end

function Chat:ApplyTransparency(force)
	if not self.db.transparent then
		return
	end
	if self.cdb.transparencyApplied and not force then
		return
	end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if frame and frame:GetID() <= Constants.ChatFrameConstants.MaxChatWindows then
			FCF_SetWindowAlpha(frame, 0)
		end
	end
	self.cdb.transparencyApplied = true
	self.appliedThisSession = true
end

---------------------------------------------------------------------------
-- Message filters run through Blizzard's filter registry, which calls them
-- with securecallfunction and skips messages that addons cannot read.
---------------------------------------------------------------------------
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

local function SetFilter(events, enabled, filter)
	for _, event in ipairs(events) do
		RemoveFilter(event, filter)
		if enabled then
			AddFilter(event, filter)
		end
	end
end

local COLORS = { "GREY", "ORANGE", "YELLOW", "BLUE", "GREEN", "RED", "WHITE" }
local COLOR_CODES = {
	GREY = "a0a0a0", ORANGE = "ff8000", YELLOW = "ffd100", BLUE = "40c0ff",
	GREEN = "40ff40", RED = "ff4040", WHITE = "ffffff",
}

local function ColorValues()
	local values = {}
	for _, key in ipairs(COLORS) do
		values[#values + 1] = { key, ("|cff%s%s|r"):format(COLOR_CODES[key], L["CHAT_COLOR_" .. key]) }
	end
	return values
end

---------------------------------------------------------------------------
-- Keyword alert: a sound when a chat message contains one of the keywords as
-- a whole word, optionally the word coloured in the chat.
---------------------------------------------------------------------------
local KEYWORD_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}
local KEYWORD_SOUNDS = { "RAID_WARNING", "READY_CHECK", "TELL_MESSAGE", "ALARM_CLOCK_WARNING_3", "MAP_PING" }
local SOUND_THROTTLE = 2
-- Letters, digits and the bytes of UTF-8 characters (umlauts) form words.
local WORD_START = "%f[%w\128-\255]"
local WORD_END = "%f[^%w\128-\255]"
local keywordList = {} -- Lua patterns
local lastAlert = 0
local playerName = UnitName("player")

local function PlayKeywordSound()
	local kit = SOUNDKIT[Chat.db.keywordSound]
	if kit then
		PlaySound(kit, "Master")
	end
end

-- Keywords are kept per character and start with its name and class.
local function Keywords()
	local cdb = Chat.cdb
	if cdb.keywords == nil then
		local list = { playerName, (UnitClass("player")) }
		local old = Chat.db.keywords -- former account wide list
		if old and old ~= "" then
			list[#list + 1] = old
		end
		cdb.keywords = table.concat(list, ", ")
	end
	return cdb.keywords
end

local function KeywordPattern(word)
	local pattern = word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	if word:find("^[%w\128-\255]") then
		pattern = WORD_START .. pattern
	end
	if word:find("[%w\128-\255]$") then
		pattern = pattern .. WORD_END
	end
	return pattern
end

local function ParseKeywords()
	wipe(keywordList)
	for word in Keywords():gmatch("[^,;]+") do
		word = strtrim(word):lower()
		if word ~= "" then
			keywordList[#keywordList + 1] = KeywordPattern(word)
		end
	end
end

-- Calls fn on every part of the text outside of hyperlinks; returns the
-- reassembled text.
local function MapPlainText(text, fn)
	if not text:find("|H", 1, true) then
		return fn(text)
	end
	local parts, pos = {}, 1
	while true do
		local first, last = text:find("|H.-|h.-|h", pos)
		if not first then
			break
		end
		parts[#parts + 1] = fn(text:sub(pos, first - 1))
		parts[#parts + 1] = text:sub(first, last)
		pos = last + 1
	end
	parts[#parts + 1] = fn(text:sub(pos))
	return table.concat(parts)
end

local function ContainsKeyword(text)
	local found = false
	MapPlainText(text, function(part)
		if not found then
			local lower = part:lower()
			for _, pattern in ipairs(keywordList) do
				if lower:find(pattern) then
					found = true
					break
				end
			end
		end
		return ""
	end)
	return found
end

local hits = {}
local function SortHits(a, b)
	return a[1] < b[1]
end

local function HighlightPart(part)
	local lower = part:lower()
	wipe(hits)
	for _, pattern in ipairs(keywordList) do
		local init = 1
		while true do
			local first, last = lower:find(pattern, init)
			if not first or last < first then
				break
			end
			hits[#hits + 1] = { first, last }
			init = last + 1
		end
	end
	if #hits == 0 then
		return part
	end
	table.sort(hits, SortHits)
	local color = "|cff" .. (COLOR_CODES[Chat.db.keywordColor] or COLOR_CODES.ORANGE)
	local out, pos = {}, 1
	for _, hit in ipairs(hits) do
		if hit[1] >= pos then
			out[#out + 1] = part:sub(pos, hit[1] - 1)
			out[#out + 1] = color .. part:sub(hit[1], hit[2]) .. "|r"
			pos = hit[2] + 1
		end
	end
	out[#out + 1] = part:sub(pos)
	return table.concat(out)
end

local function IsOwnMessage(sender)
	return sender and Ambiguate(sender, "short") == playerName
end

local function OnChatMessage(_, _, text, sender)
	if #keywordList == 0 or type(text) ~= "string" or (issecretvalue and (issecretvalue(text) or issecretvalue(sender))) then
		return
	end
	if IsOwnMessage(sender) or not ContainsKeyword(text) then
		return
	end
	local now = GetTime()
	if now - lastAlert >= SOUND_THROTTLE then
		lastAlert = now
		PlayKeywordSound()
	end
end

local function HighlightFilter(_, _, text, sender, ...)
	if #keywordList == 0 or type(text) ~= "string" or IsOwnMessage(sender) or not ContainsKeyword(text) then
		return false
	end
	return false, MapPlainText(text, HighlightPart), sender, ...
end

function Chat:UpdateKeywordAlert()
	ParseKeywords()
	local enabled = self.db.keywordAlert and #keywordList > 0
	for _, event in ipairs(KEYWORD_EVENTS) do
		self:ToggleEvent(event, enabled, OnChatMessage)
	end
	SetFilter(KEYWORD_EVENTS, self.db.keywordHighlight and #keywordList > 0, HighlightFilter)
end

---------------------------------------------------------------------------
-- Short channel names: [2. Handel - Stadt] becomes [2. H]. Blizzard's code
-- needs the number in front and compares the length of the channel string
-- with the joined channel names, so the short name is padded with "|r"
-- (invisible) to the original length.
---------------------------------------------------------------------------
local shortNames = {}

local function ShortName(baseName)
	local short = shortNames[baseName]
	if not short then
		local letters = {}
		for word in baseName:gmatch("[^%s%-%(%)%.:/]+") do
			-- First character (UTF-8 aware) plus inner capitals (LokaleVerteidigung).
			letters[#letters + 1] = word:match("^[%z\1-\127\194-\244][\128-\191]*"):upper()
			for capital in word:sub(2):gmatch("%u") do
				letters[#letters + 1] = capital
			end
		end
		short = table.concat(letters)
		if short == "" then
			short = baseName
		end
		shortNames[baseName] = short
	end
	return short
end

local function ChannelFilter(_, _, a1, a2, a3, a4, a5, a6, a7, a8, a9, ...)
	if type(a4) ~= "string" or type(a8) ~= "number" or type(a9) ~= "string" or a9 == "" then
		return false
	end
	local short = ("%d. %s"):format(a8, ShortName(a9))
	if #short < #a4 then
		short = short .. ("|r"):rep(math.ceil((#a4 - #short) / 2))
	end
	return false, a1, a2, a3, short, a5, a6, a7, a8, a9, ...
end

function Chat:UpdateChannelNames()
	SetFilter({ "CHAT_MSG_CHANNEL" }, self.db.channelShort, ChannelFilter)
end

---------------------------------------------------------------------------
-- Coloured timestamps: the colour code is written into Blizzard's timestamp
-- format (CVar showTimestamps). Switching off restores the plain format.
---------------------------------------------------------------------------
local settingTimestamp

local function PlainTimestamp(value)
	return (value:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Chat:UpdateTimestampColor()
	local current = GetCVar("showTimestamps")
	if not current or current == "" or current == "none" then
		return
	end
	local wanted = PlainTimestamp(current)
	if self.db.timestampColor then
		local body, space = wanted:match("^(.-)(%s*)$")
		wanted = ("|cff%s%s|r%s"):format(COLOR_CODES[self.db.timestampColorValue] or COLOR_CODES.GREY, body, space)
	end
	if wanted ~= current then
		settingTimestamp = true
		SetCVar("showTimestamps", wanted)
		settingTimestamp = nil
	end
	self:ToggleEvent("CVAR_UPDATE", self.db.timestampColor, function(_, _, name)
		if name == "showTimestamps" and not settingTimestamp then
			self:UpdateTimestampColor()
		end
	end)
end

function Chat:EditKeywords()
	ns.ShowEditWindow("Keywords", L.CHAT_KEYWORDS, Keywords(), SAVE, function(text)
		self.cdb.keywords = text
		self:UpdateKeywordAlert()
	end, L.CHAT_KEYWORDS_HINT)
end

function Chat:OnLogin()
	-- The saved lines come first, then this session's lines are recorded.
	if self.db.chatLog then
		RestoreLog()
	else
		wipe(self.cdb.chatLog)
	end
	StyleAll()
	self:UpdateButtons()
	hooksecurefunc("FCF_FadeInChatFrame", function(chatFrame)
		SetTabsShown(chatFrame, true)
		SetCopyShown(chatFrame, true)
	end)
	hooksecurefunc("FCF_FadeOutChatFrame", function(chatFrame)
		SetTabsShown(chatFrame, false)
		SetCopyShown(chatFrame, false)
	end)
	if FCFTab_UpdateAlpha then
		hooksecurefunc("FCFTab_UpdateAlpha", function(chatFrame)
			SetTabsShown(chatFrame, chatFrame.hasBeenFaded)
		end)
	end
	self:UpdateTabFade()

	-- Font size changes keep the flags; reapply in case something reset them.
	hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame)
		StyleFont(chatFrame or FCF_GetCurrentChatFrame())
	end)
	-- Whisper/temporary windows are created on demand.
	hooksecurefunc("FCF_OpenTemporaryWindow", StyleAll)
	hooksecurefunc("FCF_OpenNewWindow", StyleAll)

	-- Chat window settings arrive from the server after login and may overwrite
	-- the first application, so apply once more when they do.
	self:UpdateKeywordAlert()
	self:UpdateChannelNames()
	self:UpdateTimestampColor()
	self:ApplyTransparency()
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", function()
		self:UnregisterEvent("UPDATE_CHAT_WINDOWS")
		if self.appliedThisSession then
			self:ApplyTransparency(true)
		end
	end)
end

function Chat:OnOptionChanged(key, value)
	if key == "keywordAlert" or key == "keywordHighlight" then
		self:UpdateKeywordAlert()
	elseif key == "channelShort" then
		self:UpdateChannelNames()
	elseif key == "copyButton" then
		for chatFrame in pairs(copyButtons) do
			SetCopyShown(chatFrame, chatFrame.hasBeenFaded)
		end
	elseif key == "chatLog" and not value then
		wipe(self.cdb.chatLog)
	elseif key == "timestampColor" or key == "timestampColorValue" then
		self:UpdateTimestampColor()
	elseif key == "hideButtons" then
		self:UpdateButtons()
	elseif key == "tabFade" then
		self:UpdateTabFade()
	elseif key == "transparent" then
		if value then
			self:ApplyTransparency(true)
		else
			self.cdb.transparencyApplied = false
			for _, name in ipairs(CHAT_FRAMES) do
				local frame = _G[name]
				if frame and frame:GetID() <= Constants.ChatFrameConstants.MaxChatWindows then
					FCF_SetWindowAlpha(frame, DEFAULT_CHATFRAME_ALPHA)
				end
			end
		end
	end
end

Chat.options = {
	{ key = "hideButtons", type = "toggle", name = L.CHAT_HIDE_BUTTONS, desc = L.CHAT_HIDE_BUTTONS_DESC },
	{ key = "tabFade", type = "toggle", name = L.CHAT_TAB_FADE, desc = L.CHAT_TAB_FADE_DESC },
	{ key = "languageClick", type = "toggle", name = L.CHAT_LANGUAGE_CLICK, desc = L.CHAT_LANGUAGE_CLICK_DESC },
	{ key = "languageMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "languageClick" },
	{ key = "transparent", type = "toggle", name = L.CHAT_TRANSPARENT, desc = L.CHAT_TRANSPARENT_DESC },
	{ key = "mouseScroll", type = "toggle", name = L.CHAT_MOUSE_SCROLL, desc = L.CHAT_MOUSE_SCROLL_DESC },
	{ key = "inputHistory", type = "toggle", name = L.CHAT_INPUT_HISTORY, desc = L.CHAT_INPUT_HISTORY_DESC },
	{ key = "chatLog", type = "toggle", name = L.CHAT_LOG, desc = L.CHAT_LOG_DESC },
	{ key = "chatLogLines", type = "slider", name = L.CHAT_LOG_LINES, parent = "chatLog", min = 50, max = 500, step = 50 },
	{ key = "copyButton", type = "toggle", name = L.CHAT_COPY_BUTTON, desc = L.CHAT_COPY_BUTTON_DESC },
	{ type = "header", name = L.CHAT_MESSAGES_HEADER },
	{ key = "channelShort", type = "toggle", name = L.CHAT_CHANNEL_SHORT, desc = L.CHAT_CHANNEL_SHORT_DESC },
	{ key = "timestampColor", type = "toggle", name = L.CHAT_TIMESTAMP_COLOR, desc = L.CHAT_TIMESTAMP_COLOR_DESC },
	{ key = "timestampColorValue", type = "dropdown", name = L.CHAT_COLOR, parent = "timestampColor", values = ColorValues },
	{ type = "header", name = L.CHAT_KEYWORD_HEADER },
	{ key = "keywordAlert", type = "toggle", name = L.CHAT_KEYWORD_ALERT, desc = L.CHAT_KEYWORD_ALERT_DESC },
	{ type = "button", name = L.CHAT_KEYWORDS, text = L.CHAT_KEYWORDS_EDIT, func = function()
		Chat:EditKeywords()
	end },
	{ key = "keywordSound", type = "dropdown", name = L.CHAT_KEYWORD_SOUND, values = function()
		local values = {}
		for _, key in ipairs(KEYWORD_SOUNDS) do
			values[#values + 1] = { key, L["CHAT_SOUND_" .. key] }
		end
		return values
	end },
	{ type = "button", name = L.CHAT_KEYWORD_TEST, text = L.QUESTS_TEST, func = PlayKeywordSound },
	{ key = "keywordHighlight", type = "toggle", name = L.CHAT_KEYWORD_HIGHLIGHT, desc = L.CHAT_KEYWORD_HIGHLIGHT_DESC },
	{ key = "keywordColor", type = "dropdown", name = L.CHAT_COLOR, parent = "keywordHighlight", values = ColorValues },
}

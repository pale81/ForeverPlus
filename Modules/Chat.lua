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
	},
	charDefaults = {
		transparencyApplied = false,
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

local function StyleFont(chatFrame)
	ns.ApplyOutline(chatFrame)
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
-- Keyword alert: a sound when a chat message contains one of the keywords
---------------------------------------------------------------------------
local KEYWORD_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}
local KEYWORD_SOUNDS = { "RAID_WARNING", "READY_CHECK", "TELL_MESSAGE", "ALARM_CLOCK_WARNING_3", "MAP_PING" }
local SOUND_THROTTLE = 2
local keywordList = {}
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

local function ParseKeywords()
	wipe(keywordList)
	for word in Keywords():gmatch("[^,;]+") do
		word = strtrim(word):lower()
		if word ~= "" then
			keywordList[#keywordList + 1] = word
		end
	end
end

local function OnChatMessage(_, _, text, sender)
	if #keywordList == 0 or type(text) ~= "string" or (issecretvalue and (issecretvalue(text) or issecretvalue(sender))) then
		return
	end
	if sender and Ambiguate(sender, "short") == playerName then
		return
	end
	local lower = text:lower()
	for _, word in ipairs(keywordList) do
		if lower:find(word, 1, true) then
			local now = GetTime()
			if now - lastAlert >= SOUND_THROTTLE then
				lastAlert = now
				PlayKeywordSound()
			end
			return
		end
	end
end

function Chat:UpdateKeywordAlert()
	ParseKeywords()
	local enabled = self.db.keywordAlert and #keywordList > 0
	for _, event in ipairs(KEYWORD_EVENTS) do
		self:ToggleEvent(event, enabled, OnChatMessage)
	end
end

function Chat:EditKeywords()
	ns.ShowEditWindow("Keywords", L.CHAT_KEYWORDS, Keywords(), SAVE, function(text)
		self.cdb.keywords = text
		self:UpdateKeywordAlert()
	end, L.CHAT_KEYWORDS_HINT)
end

function Chat:OnLogin()
	StyleAll()
	self:UpdateButtons()
	hooksecurefunc("FCF_FadeInChatFrame", function(chatFrame)
		SetTabsShown(chatFrame, true)
	end)
	hooksecurefunc("FCF_FadeOutChatFrame", function(chatFrame)
		SetTabsShown(chatFrame, false)
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
	self:ApplyTransparency()
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", function()
		self:UnregisterEvent("UPDATE_CHAT_WINDOWS")
		if self.appliedThisSession then
			self:ApplyTransparency(true)
		end
	end)
end

function Chat:OnOptionChanged(key, value)
	if key == "keywordAlert" then
		self:UpdateKeywordAlert()
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
	{ key = "transparent", type = "toggle", name = L.CHAT_TRANSPARENT, desc = L.CHAT_TRANSPARENT_DESC },
}

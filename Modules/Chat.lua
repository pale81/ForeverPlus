-- Chat: cleaner chat frame that keeps the original look.
local _, ns = ...
local L = ns.L

local Chat = ns:NewModule("Chat", {
	title = L.CHAT_TITLE,
	order = 1,
	defaults = {
		hideButtons = true,
		transparent = true,
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
				buttonParents[button] = button:GetParent()
				button:SetParent(ns.hider)
			end
		elseif buttonParents[button] then
			button:SetParent(buttonParents[button])
			buttonParents[button] = nil
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

function Chat:OnLogin()
	StyleAll()
	self:UpdateButtons()

	-- Font size changes keep the flags; reapply in case something reset them.
	hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame)
		StyleFont(chatFrame or FCF_GetCurrentChatFrame())
	end)
	-- Whisper/temporary windows are created on demand.
	hooksecurefunc("FCF_OpenTemporaryWindow", StyleAll)
	hooksecurefunc("FCF_OpenNewWindow", StyleAll)

	-- Chat window settings arrive from the server after login and may overwrite
	-- the first application, so apply once more when they do.
	self:ApplyTransparency()
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", function()
		self:UnregisterEvent("UPDATE_CHAT_WINDOWS")
		if self.appliedThisSession then
			self:ApplyTransparency(true)
		end
	end)
end

function Chat:OnOptionChanged(key, value)
	if key == "hideButtons" then
		self:UpdateButtons()
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
	{ key = "transparent", type = "toggle", name = L.CHAT_TRANSPARENT, desc = L.CHAT_TRANSPARENT_DESC },
}

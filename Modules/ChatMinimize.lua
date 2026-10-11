-- Minimize the chat: a small button above the chat window folds it away with a smooth fade (and lets it back in
-- the same way), a little like the chat addon Glass. While minimized, new messages are counted on the button and
-- make it pulse. The chat window itself keeps its size, position and settings; only its transparency (and its
-- mouse) is changed, so Blizzard's layout is not touched. Nothing is copied from Glass.
local _, ns = ...
local L = ns.L

local Minimize = ns:NewModule("ChatMinimize", {
	title = L.CHATMIN_TITLE,
	order = 5.96,
	defaults = {
		enabled = false,
	},
	charDefaults = {
		minimized = false,
	},
})

local DURATION = 0.28 -- seconds of the fade

local button, driver
local progress = 0       -- 0: chat shown, 1: chat folded away
local target = 0
local unread = 0

-- The parts of the chat that fold away: the window with its text and buttons, and the row of tabs.
local function Parts()
	return { ChatFrame1, GeneralDockManager }
end

local function Ease(t) -- slow end
	return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function Apply()
	local alpha = 1 - Ease(progress)
	for _, part in ipairs(Parts()) do
		if part and part.SetAlpha then
			part:SetAlpha(alpha)
		end
	end
	local hidden = progress >= 1
	for _, part in ipairs(Parts()) do
		if part and part.SetMouseClickEnabled then
			part:SetMouseClickEnabled(not hidden)
			part:SetMouseMotionEnabled(not hidden)
		end
	end
end

local function UpdateButton()
	if not button then
		return
	end
	local folded = target >= 1
	button.Icon:SetTexture(folded and [[Interface\Buttons\UI-PlusButton-Up]] or [[Interface\Buttons\UI-MinusButton-Up]])
	button.Count:SetText(folded and unread > 0 and tostring(unread) or "")
	button.Chat:SetShown(folded)
end

local function Step(_, elapsed)
	local step = elapsed / DURATION
	if progress < target then
		progress = math.min(target, progress + step)
	elseif progress > target then
		progress = math.max(target, progress - step)
	end
	Apply()
	if progress == target then
		driver:SetScript("OnUpdate", nil)
	end
end

local function SetFolded(folded, instant)
	target = folded and 1 or 0
	Minimize.cdb.minimized = folded and true or false
	if not folded then
		unread = 0
	end
	UpdateButton()
	if instant or not Minimize.db.enabled then
		progress = target
		Apply()
		driver:SetScript("OnUpdate", nil)
	else
		ns.SetUpdate(driver, "ChatMinimize: fade", Step)
	end
end

local function Create()
	driver = CreateFrame("Frame")
	button = CreateFrame("Button", "ForeverPlusChatMinimizeButton", UIParent)
	button:SetSize(18, 18)
	button:SetFrameStrata("MEDIUM")
	button:RegisterForClicks("LeftButtonUp")
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.Highlight:SetAllPoints()
	button.Highlight:SetTexture([[Interface\Buttons\UI-Common-MouseHilight]])
	button.Highlight:SetBlendMode("ADD")
	-- While folded away: a chat bubble beside the button and the number of new messages.
	button.Chat = button:CreateTexture(nil, "ARTWORK")
	button.Chat:SetTexture([[Interface\ChatFrame\UI-ChatIcon-Chat-Up]])
	button.Chat:SetSize(18, 18)
	button.Chat:SetPoint("LEFT", button, "RIGHT", 2, 0)
	button.Count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.Count:SetPoint("LEFT", button.Chat, "RIGHT", 2, 0)
	button.Pulse = button.Chat:CreateAnimationGroup()
	local up = button.Pulse:CreateAnimation("Alpha")
	up:SetFromAlpha(1)
	up:SetToAlpha(0.25)
	up:SetDuration(0.25)
	up:SetOrder(1)
	local down = button.Pulse:CreateAnimation("Alpha")
	down:SetFromAlpha(0.25)
	down:SetToAlpha(1)
	down:SetDuration(0.25)
	down:SetOrder(2)
	button:SetScript("OnClick", function()
		SetFolded(target < 1)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, target >= 1 and L.CHATMIN_SHOW or L.CHATMIN_HIDE)
		if target >= 1 and unread > 0 then
			GameTooltip_AddNormalLine(GameTooltip, L.CHATMIN_UNREAD:format(unread))
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- Above the row of tabs, at its left end.
	button:SetPoint("BOTTOMLEFT", GeneralDockManager or ChatFrame1, "TOPLEFT", 0, 2)
	if ChatFrame1 and ChatFrame1.AddMessage then
		hooksecurefunc(ChatFrame1, "AddMessage", ns.Measured("ChatMinimize: message", function()
			if Minimize.db.enabled and target >= 1 then
				unread = unread + 1
				UpdateButton()
				button.Pulse:Stop()
				button.Pulse:Play()
			end
		end))
	end
end

function Minimize:Apply()
	if not ChatFrame1 then
		return
	end
	if not button then
		Create()
	end
	button:SetShown(self.db.enabled and true or false)
	if self.db.enabled then
		SetFolded(self.cdb.minimized, true)
	else
		-- Off: the chat is shown again.
		target, progress, unread = 0, 0, 0
		Apply()
		UpdateButton()
	end
end

function Minimize:OnLogin()
	self:Apply()
end

function Minimize:OnOptionChanged()
	self:Apply()
end

Minimize.options = {
	{ key = "enabled", type = "toggle", name = L.CHATMIN_ENABLE, desc = L.CHATMIN_DESC, new = true },
}

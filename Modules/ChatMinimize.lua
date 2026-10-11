-- Chat that folds away by itself: when nothing was written for a few seconds and the mouse is not over it, the
-- chat window and its tabs fade out smoothly; a new message, the mouse over the chat or typing brings it back the
-- same way, a little like the chat addon Glass. The window keeps its size, position and settings; only its
-- transparency (and its mouse) changes, so Blizzard's layout is untouched. Nothing is copied from Glass.
local _, ns = ...
local L = ns.L

local Minimize = ns:NewModule("ChatMinimize", {
	title = L.CHATMIN_TITLE,
	order = 5.96,
	defaults = {
		enabled = false,
		delay = 8, -- seconds without a message before the chat folds away
	},
})

local FADE_OUT, FADE_IN = 0.6, 0.2 -- seconds
local CHECK = 0.25                 -- seconds between looks at the mouse and the idle time

local driver, ticker
local alpha = 1          -- shown alpha, 1 = chat fully shown
local target = 1
local lastActivity = 0

-- The windows that fold: every chat window and the row of tabs.
local function Parts()
	local parts = { GeneralDockManager }
	for index = 1, ns.Number(NUM_CHAT_WINDOWS, 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and frame ~= COMBATLOG then
			parts[#parts + 1] = frame
		end
	end
	return parts
end

local function Apply()
	local folded = alpha <= 0.01
	for _, part in ipairs(Parts()) do
		part:SetAlpha(alpha)
		-- Folded away the chat does not catch the mouse (clicks reach the world); the mouse over the place it
		-- covers is still noticed by looking at the geometry.
		if part.SetMouseClickEnabled then
			part:SetMouseClickEnabled(not folded)
		end
	end
end

local function Step(_, elapsed)
	local change = elapsed / (target > alpha and FADE_IN or FADE_OUT)
	if alpha < target then
		alpha = math.min(target, alpha + change)
	else
		alpha = math.max(target, alpha - change)
	end
	Apply()
	if alpha == target then
		ns.SetUpdate(driver, "ChatMinimize: fade", nil)
	end
end

local function FadeTo(value)
	if target == value then
		return
	end
	target = value
	ns.SetUpdate(driver, "ChatMinimize: fade", Step)
end

local function Wake()
	lastActivity = GetTime()
	FadeTo(1)
end

local function MouseOverChat()
	if GeneralDockManager and GeneralDockManager:IsMouseOver() then
		return true
	end
	for _, part in ipairs(Parts()) do
		if part:IsShown() and part:IsMouseOver() then
			return true
		end
	end
	return false
end

local function Check()
	if not Minimize.db.enabled then
		return
	end
	-- Typing keeps it open.
	local getActive = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
	local editing = getActive and getActive()
	if editing or MouseOverChat() then
		Wake()
	elseif target >= 1 and GetTime() - lastActivity >= Minimize.db.delay then
		FadeTo(0)
	end
end

local hooked = {}

local function HookFrames()
	for index = 1, ns.Number(NUM_CHAT_WINDOWS, 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and frame ~= COMBATLOG and not hooked[frame] and type(frame.AddMessage) == "function" then
			hooked[frame] = true
			hooksecurefunc(frame, "AddMessage", ns.Measured("ChatMinimize: message", function()
				if Minimize.db.enabled then
					Wake()
				end
			end))
		end
	end
end

function Minimize:Apply()
	if not ChatFrame1 then
		return
	end
	driver = driver or CreateFrame("Frame")
	HookFrames()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if self.db.enabled then
		lastActivity = GetTime()
		ticker = C_Timer.NewTicker(CHECK, Check)
	else
		-- Off: the chat is shown again at once.
		target, alpha = 1, 1
		ns.SetUpdate(driver, "ChatMinimize: fade", nil)
		Apply()
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
	{ key = "delay", type = "slider", name = L.CHATMIN_DELAY, parent = "enabled", min = 3, max = 60, step = 1,
		format = function(value)
			return ("%d s"):format(value)
		end },
}

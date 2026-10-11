-- Chat that makes room by itself, two independent steps, each with its own waiting time (a little like the chat
-- addon Glass): the chat can fade out smoothly when nothing was written for a while, and it can shrink smoothly to
-- one line, the last message. The mouse over the chat or typing brings it back to full size and visibility; a new
-- message makes a faded chat visible again (a shrunken one stays shrunken, its line is the new message). Only the
-- transparency and the height of the windows change, and the own height is given back exactly (also when the game
-- is left); position, width and settings are not touched. Nothing is copied from Glass.
local _, ns = ...
local L = ns.L

local Minimize = ns:NewModule("ChatMinimize", {
	title = L.CHATMIN_TITLE,
	order = 5.96,
	defaults = {
		enabled = false, -- shrink to one line
		delay = 20,      -- seconds before it shrinks
		fade = false,    -- fade out
		fadeDelay = 10,  -- seconds before it fades
	},
})

local FADE_OUT, FADE_IN = 0.8, 0.2    -- seconds
local FOLD_TIME, OPEN_TIME = 0.5, 0.2 -- seconds
local CHECK = 0.25                    -- seconds between looks at the mouse and the idle time

local driver, ticker
local fade, fadeTarget = 0, 0 -- 0: shown, 1: faded away
local fold, foldTarget = 0, 0 -- 0: own height, 1: one line
local lastMouse, lastMessage = 0, 0
local heights = {}            -- chat window -> its own height, taken when it starts to shrink

local function WindowCount()
	return ns.Number(NUM_CHAT_WINDOWS, 10)
end

local function Windows(onlyShown)
	local list = {}
	for index = 1, WindowCount() do
		local frame = _G["ChatFrame" .. index]
		if frame and frame ~= COMBATLOG and (not onlyShown or frame:IsShown()) then
			list[#list + 1] = frame
		end
	end
	return list
end

local function Ease(t) -- slow end
	return 1 - (1 - t) * (1 - t) * (1 - t)
end

-- Height of exactly one line (font plus the spacing between lines), so no part of the line above shows.
local function LineHeight(frame)
	local _, size = frame:GetFont()
	local spacing = frame.GetSpacing and ns.Number(frame:GetSpacing(), 0) or 0
	return math.ceil(ns.Number(size, 14) + spacing)
end

local function Apply()
	local alpha = 1 - Ease(fade)
	local hidden = fade >= 1
	for _, frame in ipairs(Windows()) do
		frame:SetAlpha(alpha)
		if frame.SetMouseClickEnabled then
			frame:SetMouseClickEnabled(not hidden)
		end
	end
	if GeneralDockManager then
		GeneralDockManager:SetAlpha(alpha)
		if GeneralDockManager.SetMouseClickEnabled then
			GeneralDockManager:SetMouseClickEnabled(not hidden)
		end
	end
	local eased = Ease(fold)
	for frame, full in pairs(heights) do
		local line = math.min(full, LineHeight(frame))
		frame:SetHeight(full + (line - full) * eased)
		frame:ScrollToBottom()
	end
end

local function Move(value, target, timeUp, timeDown, elapsed)
	local change = elapsed / (target > value and timeUp or timeDown)
	if value < target then
		return math.min(target, value + change)
	end
	return math.max(target, value - change)
end

local function Step(_, elapsed)
	fade = Move(fade, fadeTarget, FADE_OUT, FADE_IN, elapsed)
	fold = Move(fold, foldTarget, FOLD_TIME, OPEN_TIME, elapsed)
	Apply()
	if fade == fadeTarget and fold == foldTarget then
		ns.SetUpdate(driver, "ChatMinimize: animation", nil)
		if foldTarget == 0 then
			wipe(heights)
		end
	end
end

local function Animate()
	ns.SetUpdate(driver, "ChatMinimize: animation", Step)
end

local function SetFade(value)
	if fadeTarget ~= value then
		fadeTarget = value
		Animate()
	end
end

local function SetFold(value)
	if foldTarget == value then
		return
	end
	if value == 1 and not next(heights) then
		-- Own height of every shown window, taken now.
		for _, frame in ipairs(Windows(true)) do
			heights[frame] = frame:GetHeight()
		end
		if not next(heights) then
			return
		end
	end
	foldTarget = value
	Animate()
end

local function MouseOverChat()
	if GeneralDockManager and GeneralDockManager:IsMouseOver() then
		return true
	end
	for _, frame in ipairs(Windows(true)) do
		if frame:IsMouseOver() then
			return true
		end
	end
	return false
end

local function Check()
	local db = Minimize.db
	local now = GetTime()
	-- Typing and the mouse over the chat bring everything back.
	local getActive = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
	if (getActive and getActive()) or MouseOverChat() then
		lastMouse = now
		SetFade(0)
		SetFold(0)
		return
	end
	local idle = now - math.max(lastMouse, lastMessage)
	if db.fade and fadeTarget == 0 and idle >= db.fadeDelay then
		SetFade(1)
	end
	if db.enabled and foldTarget == 0 and idle >= db.delay then
		SetFold(1)
	end
end

local hooked = {}

local function HookFrames()
	for _, frame in ipairs(Windows()) do
		if not hooked[frame] and type(frame.AddMessage) == "function" then
			hooked[frame] = true
			hooksecurefunc(frame, "AddMessage", ns.Measured("ChatMinimize: message", function()
				lastMessage = GetTime()
				-- A new message shows a faded chat again; a shrunken one stays one line (showing that message).
				if fadeTarget == 1 then
					SetFade(0)
				end
			end))
		end
	end
end

-- Own height and full visibility back at once: when the game is left or the options are switched off.
local function Restore()
	fade, fadeTarget, fold, foldTarget = 0, 0, 0, 0
	ns.SetUpdate(driver, "ChatMinimize: animation", nil)
	for frame, full in pairs(heights) do
		frame:SetHeight(full)
	end
	wipe(heights)
	Apply()
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
	if self.db.enabled or self.db.fade then
		lastMouse, lastMessage = GetTime(), GetTime()
		ticker = C_Timer.NewTicker(CHECK, Check)
		self:RegisterEvent("PLAYER_LOGOUT", Restore)
		self:RegisterEvent("PLAYER_LEAVING_WORLD", Restore)
	else
		self:UnregisterEvent("PLAYER_LOGOUT")
		self:UnregisterEvent("PLAYER_LEAVING_WORLD")
		Restore()
		return
	end
	-- A step that was switched off gives its change back.
	if not self.db.enabled and foldTarget == 1 then
		SetFold(0)
	end
	if not self.db.fade and fadeTarget == 1 then
		SetFade(0)
	end
end

function Minimize:OnLogin()
	self:Apply()
end

function Minimize:OnOptionChanged()
	self:Apply()
end

local function Seconds(value)
	return ("%d s"):format(value)
end

Minimize.options = {
	{ key = "fade", type = "toggle", name = L.CHATMIN_FADE, desc = L.CHATMIN_FADE_DESC, new = true },
	{ key = "fadeDelay", type = "slider", name = L.CHATMIN_FADE_DELAY, parent = "fade", min = 3, max = 120, step = 1, format = Seconds },
	{ key = "enabled", type = "toggle", name = L.CHATMIN_ENABLE, desc = L.CHATMIN_DESC, new = true },
	{ key = "delay", type = "slider", name = L.CHATMIN_DELAY, parent = "enabled", min = 3, max = 300, step = 1, format = Seconds },
}

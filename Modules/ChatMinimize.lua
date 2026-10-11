-- Chat that makes room by itself, two independent steps, each with its own waiting time (a little like the chat
-- addon Glass): the chat can fade out smoothly when nothing was written for a while, and it can shrink smoothly to
-- the last message (as many lines as that message takes in the window, one to four). The mouse over the chat or typing brings it back to full size and visibility; a new
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

local MAX_LINES = 4
local MARGIN = 6 -- pixels of the width not used by the text (as in the indented chat)
local meter

-- Timestamp the window puts in front of a line (nil when it shows none).
local function TimestampSample()
	local format = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
	if not format or not TimeUtil or not TimeUtil.BetterDate then
		return nil
	end
	local sample = TimeUtil.BetterDate(format, time())
	if type(sample) == "string" and sample ~= "" then
		return (sample:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
end

-- The last message in this window, measured with the font and width of the window: how many lines it takes and how
-- high that is (the height the font itself gives it, so it fits exactly).
local function LastMessageSize(frame)
	local count = frame.GetNumMessages and ns.Number(frame:GetNumMessages(), 0) or 0
	local text = count > 0 and frame.GetMessageInfo and frame:GetMessageInfo(count)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return 1, LineHeight(frame)
	end
	local file, size, flags = frame:GetFont()
	if not file then
		return 1, LineHeight(frame)
	end
	meter = meter or ns.hider:CreateFontString(nil, "ARTWORK")
	meter:SetFont(file, ns.Number(size, 14), flags or "")
	if meter.SetSpacing and frame.GetSpacing then
		meter:SetSpacing(ns.Number(frame:GetSpacing(), 0))
	end
	meter:SetWidth(math.max(50, ns.Number(frame:GetWidth(), 300) - MARGIN))
	meter:SetWordWrap(true)
	meter:SetText((TimestampSample() or "") .. text)
	local height = ns.Number(meter:GetStringHeight(), 0)
	local lines = math.max(1, math.floor(height / math.max(1, ns.Number(size, 14)) + 0.5))
	if lines > MAX_LINES then
		height = height / lines * MAX_LINES
		lines = MAX_LINES
	end
	return lines, math.max(height, LineHeight(frame))
end

local foldHeights = {} -- chat window -> height it takes when folded (the lines of its last message)
local shown = {}       -- chat window -> height set at the moment

local function FoldHeight(frame)
	local _, height = LastMessageSize(frame)
	return math.ceil(height)
end

local function ApplyAlpha()
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
	return Ease(fold)
end

-- The heights move towards where they should be (own height, one message), so a new message of another length
-- changes the folded height smoothly too. True while something still moves.
local function MoveHeights(elapsed, eased)
	local moving = false
	for frame, full in pairs(heights) do
		local goal = math.min(full, foldHeights[frame] or LineHeight(frame))
		goal = full + (goal - full) * eased
		local current = shown[frame] or full
		if math.abs(goal - current) > 0.5 then
			current = current + (goal - current) * math.min(1, elapsed * 14)
			moving = true
		else
			current = goal
		end
		shown[frame] = current
		frame:SetHeight(current)
		frame:ScrollToBottom()
	end
	return moving
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
	local moving = MoveHeights(elapsed, ApplyAlpha())
	if fade == fadeTarget and fold == foldTarget and not moving then
		ns.SetUpdate(driver, "ChatMinimize: animation", nil)
		if foldTarget == 0 then
			wipe(heights)
			wipe(foldHeights)
			wipe(shown)
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
			foldHeights[frame] = FoldHeight(frame)
			shown[frame] = heights[frame]
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
			hooksecurefunc(frame, "AddMessage", ns.Measured("ChatMinimize: message", function(window)
				lastMessage = GetTime()
				-- A new message shows a faded chat again; a shrunken one stays shrunken and takes the height of that
				-- message.
				if fadeTarget == 1 then
					SetFade(0)
				end
				if foldTarget == 1 and heights[window] then
					foldHeights[window] = FoldHeight(window)
					Animate()
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
	wipe(foldHeights)
	wipe(shown)
	ApplyAlpha()
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

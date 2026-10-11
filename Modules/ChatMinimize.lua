-- Chat that folds down to one line by itself: when nothing was written for a few seconds and the mouse is not over
-- it, the chat window shrinks smoothly to a single line, the last message; the mouse over the chat or typing lets it
-- grow back the same way, a little like the chat addon Glass. (The fading out of old lines is the game's own
-- option and is left to it.) The window is only made lower while folded and gets its own height back exactly,
-- also when the game is left; position, width and settings are not touched. Nothing is copied from Glass.
local _, ns = ...
local L = ns.L

local Minimize = ns:NewModule("ChatMinimize", {
	title = L.CHATMIN_TITLE,
	order = 5.96,
	defaults = {
		enabled = false,
		delay = 8, -- seconds without a message or the mouse before the chat folds down
	},
})

local FOLD_TIME, OPEN_TIME = 0.5, 0.2 -- seconds
local CHECK = 0.25                    -- seconds between looks at the mouse and the idle time

local driver, ticker
local progress = 0       -- 0: window at its full height, 1: one line
local target = 0
local lastActivity = 0
local heights = {}       -- chat window -> its own height, taken when it starts to fold

local function Windows()
	local list = {}
	for index = 1, ns.Number(NUM_CHAT_WINDOWS, 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and frame ~= COMBATLOG and frame:IsShown() then
			list[#list + 1] = frame
		end
	end
	return list
end

local function Ease(t) -- slow end
	return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function LineHeight(frame)
	local _, size = frame:GetFont()
	return ns.Number(size, 14) + 8
end

-- The windows at the given progress between their own height and one line.
local function Apply()
	local eased = Ease(progress)
	for frame, full in pairs(heights) do
		local line = math.min(full, LineHeight(frame))
		frame:SetHeight(full + (line - full) * eased)
		frame:ScrollToBottom()
	end
end

local function Step(_, elapsed)
	local change = elapsed / (target > progress and FOLD_TIME or OPEN_TIME)
	if progress < target then
		progress = math.min(target, progress + change)
	else
		progress = math.max(target, progress - change)
	end
	Apply()
	if progress == target then
		ns.SetUpdate(driver, "ChatMinimize: fold", nil)
		if target == 0 then
			wipe(heights)
		end
	end
end

local function FoldTo(value)
	if target == value then
		return
	end
	if value == 1 and not next(heights) then
		-- Own height of every shown window, taken now.
		for _, frame in ipairs(Windows()) do
			heights[frame] = frame:GetHeight()
		end
		if not next(heights) then
			return
		end
	end
	target = value
	ns.SetUpdate(driver, "ChatMinimize: fold", Step)
end

local function Wake()
	lastActivity = GetTime()
	FoldTo(0)
end

local function MouseOverChat()
	if GeneralDockManager and GeneralDockManager:IsMouseOver() then
		return true
	end
	for index = 1, ns.Number(NUM_CHAT_WINDOWS, 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and frame:IsShown() and frame:IsMouseOver() then
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
	if (getActive and getActive()) or MouseOverChat() then
		Wake()
	elseif target == 0 and GetTime() - lastActivity >= Minimize.db.delay then
		FoldTo(1)
	end
end

-- Own height back at once: when the game is left or the option is switched off.
local function Restore()
	target, progress = 0, 0
	ns.SetUpdate(driver, "ChatMinimize: fold", nil)
	for frame, full in pairs(heights) do
		frame:SetHeight(full)
	end
	wipe(heights)
end

function Minimize:Apply()
	if not ChatFrame1 then
		return
	end
	driver = driver or CreateFrame("Frame")
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if self.db.enabled then
		lastActivity = GetTime()
		ticker = C_Timer.NewTicker(CHECK, Check)
		self:RegisterEvent("PLAYER_LOGOUT", Restore)
		self:RegisterEvent("PLAYER_LEAVING_WORLD", Restore)
	else
		self:UnregisterEvent("PLAYER_LOGOUT")
		self:UnregisterEvent("PLAYER_LEAVING_WORLD")
		Restore()
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

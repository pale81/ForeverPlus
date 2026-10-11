-- Reputation flash: a reputation change shows as large text in the middle of
-- the screen, pops up, holds for a moment and then shrinks and flies down onto
-- the experience bar, like an icon landing in the macOS dock.
local _, ns = ...
local L = ns.L

local RepFlash = ns:NewModule("RepFlash", {
	title = L.REPFLASH_TITLE,
	order = 5.8,
	defaults = {
		enabled = false, -- reputation
		xp = false,
		honor = false,
		hideChat = true, -- the chat line of a kind that flashes is hidden
	},
})

local TEXT_SIZE = 26
local START_Y = 110          -- above the screen centre
local POP_END = 0.22         -- seconds: pop-up finished
local HOLD_END = 1.25        -- seconds: hold finished, the flight begins
local DOCK_END = 1.95        -- seconds: landed
local BIG, SMALL = 1.7, 0.6  -- scale while holding, scale on the bar
local MAX_LINES = 3

local root, holder, text
local changes = {}           -- { name, total } in order of arrival
local elapsed = 0
local targetX, targetY

local function Ease(t) -- slow start, fast end
	return t * t
end

local function BackOut(t) -- overshoots a little, then settles
	local c = 1.9
	t = t - 1
	return 1 + t * t * ((c + 1) * t + c)
end

-- Centre of the experience bar relative to the screen centre (UIParent units).
local function TargetOffset()
	local bar = MainStatusTrackingBarContainer
	local cx, cy
	if bar and bar.GetCenter then
		cx, cy = bar:GetCenter()
	end
	cx, cy = ns.Number(cx), ns.Number(cy)
	local px, py = UIParent:GetCenter()
	px, py = ns.Number(px), ns.Number(py)
	if not (cx and cy and px and py) then
		return 0, -(ns.Number(UIParent:GetHeight(), 800) / 2) + 20
	end
	local scale = ns.Number(bar:GetEffectiveScale(), 1) / ns.Number(UIParent:GetEffectiveScale(), 1)
	return cx * scale - px, cy * scale - py
end

local function BuildText()
	local lines = {}
	for i = 1, math.min(#changes, MAX_LINES) do
		local change = changes[i]
		local color = change.total >= 0 and "ff40ff40" or "ffff4040"
		lines[i] = ("%s |c%s%+d|r"):format(change.name, color, change.total)
	end
	if #changes > MAX_LINES then
		lines[#lines + 1] = L.REPFLASH_MORE:format(#changes - MAX_LINES)
	end
	return table.concat(lines, "\n")
end

local function Finish()
	root:Hide()
	wipe(changes)
end

local function Update(_, delta)
	elapsed = elapsed + delta
	local t = elapsed
	local scale, alpha, x, y
	if t < POP_END then
		local k = t / POP_END
		scale, alpha, x, y = 0.4 + (BIG - 0.4) * BackOut(k), math.min(1, k * 3), 0, START_Y
	elseif t < HOLD_END then
		local k = (t - POP_END) / (HOLD_END - POP_END)
		scale, alpha, x, y = BIG - 0.15 * k, 1, 0, START_Y
	elseif t < DOCK_END then
		local k = Ease((t - HOLD_END) / (DOCK_END - HOLD_END))
		if not targetX then
			targetX, targetY = TargetOffset()
		end
		scale = (BIG - 0.15) + (SMALL - (BIG - 0.15)) * k
		x, y = targetX * k, START_Y + (targetY - START_Y) * k
		alpha = 1 - math.max(0, (k - 0.55) / 0.45)
	else
		Finish()
		return
	end
	holder:SetScale(math.max(scale, 0.05))
	holder:SetAlpha(alpha)
	root:ClearAllPoints()
	root:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function Create()
	root = CreateFrame("Frame", nil, UIParent)
	root:SetSize(1, 1)
	root:SetFrameStrata("FULLSCREEN_DIALOG")
	root:SetPoint("CENTER", UIParent, "CENTER", 0, START_Y)
	root:Hide()
	holder = CreateFrame("Frame", nil, root)
	holder:SetSize(1, 1)
	holder:SetPoint("CENTER")
	text = holder:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	ns.SetUpdate(root, "Reputation flash", Update)
end

-- Adds a change (signed amount) and starts or refreshes the flash.
function RepFlash:Add(name, amount)
	if not root then
		Create()
	end
	text:SetFont(ns.GetFontFace(), TEXT_SIZE, "OUTLINE")
	-- Late changes during the flight start a fresh flash.
	if root:IsShown() and elapsed >= HOLD_END then
		wipe(changes)
	end
	local entry
	for _, change in ipairs(changes) do
		if change.name == name then
			entry = change
		end
	end
	if not entry then
		entry = { name = name, total = 0 }
		changes[#changes + 1] = entry
	end
	entry.total = entry.total + amount
	text:SetText(BuildText())
	-- A running flash pops once more; a new one starts at the beginning.
	elapsed = root:IsShown() and 0.06 or 0
	targetX, targetY = nil, nil
	root:Show()
end

local function OnReputation(_, _, message)
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
		return
	end
	local name, amount = ns.ParseReputationMessage(message)
	if name and amount and amount ~= 0 then
		RepFlash:Add(name, amount)
	end
end

-- Experience: the change of the experience points, whatever the source (kills, quests, discoveries).
local lastXP, lastMax

local function OnExperience()
	local current, maximum = UnitXP("player"), UnitXPMax("player")
	current, maximum = ns.Number(current), ns.Number(maximum)
	if current and maximum then
		if lastXP then
			local gained = current - lastXP
			if gained < 0 and lastMax then
				gained = (lastMax - lastXP) + current -- a level up
			end
			if gained > 0 then
				RepFlash:Add(L.REPFLASH_XP, gained)
			end
		end
		lastXP, lastMax = current, maximum
	end
end

-- Honor: the number of the honor message of the game.
local honorPatterns = {}

local function OnHonor(_, _, message)
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
		return
	end
	for _, entry in ipairs(honorPatterns) do
		local captures = { message:match(entry.pattern) }
		if captures[1] then
			for i, value in ipairs(captures) do
				if entry.order[i] == entry.numberArg then
					RepFlash:Add(L.REPFLASH_HONOR, tonumber(value) or 0)
					return
				end
			end
		end
	end
end

local function BuildHonorPatterns()
	for _, format in ipairs({ _G.COMBATLOG_HONORGAIN, _G.COMBATLOG_HONORAWARD }) do
		if type(format) == "string" then
			local entry = ns.FormatToPattern(format, true)
			local position = 0
			for index, placeholder in format:gmatch("%%(%d*)%$?([sd])") do
				position = position + 1
				if placeholder == "d" then
					entry.numberArg = tonumber(index) or position
				end
			end
			if entry.numberArg then
				honorPatterns[#honorPatterns + 1] = entry
			end
		end
	end
end

-- Chat lines of the kinds that flash (reputation, experience, honor) are hidden when wanted: the
-- flash shows the same information.
local CHAT_EVENTS = {
	CHAT_MSG_COMBAT_FACTION_CHANGE = "enabled",
	CHAT_MSG_COMBAT_XP_GAIN = "xp",
	CHAT_MSG_COMBAT_HONOR_GAIN = "honor",
}

-- Filter: hides a line when its kind flashes.
local function HideFilter(_, event, message)
	if issecretvalue and issecretvalue(message) then
		return false
	end
	local db = RepFlash.db
	return db.hideChat and db[CHAT_EVENTS[event]] and true or false
end

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

function RepFlash:Apply()
	for event in pairs(CHAT_EVENTS) do
		RemoveFilter(event, HideFilter)
		if self.db.hideChat and (self.db.enabled or self.db.xp or self.db.honor) then
			AddFilter(event, HideFilter)
		end
	end
	self:ToggleEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", self.db.enabled, OnReputation)
	self:ToggleEvent("PLAYER_XP_UPDATE", self.db.xp, OnExperience)
	self:ToggleEvent("CHAT_MSG_COMBAT_HONOR_GAIN", self.db.honor, OnHonor)
	if self.db.xp then
		lastXP, lastMax = ns.Number(UnitXP("player")), ns.Number(UnitXPMax("player"))
	end
	if not (self.db.enabled or self.db.xp or self.db.honor) and root then
		Finish()
	end
end

function RepFlash:OnLogin()
	BuildHonorPatterns()
	self:Apply()
end

function RepFlash:OnOptionChanged()
	self:Apply()
end

RepFlash.options = {
	{ key = "enabled", type = "toggle", name = L.REPFLASH_ENABLE, desc = L.REPFLASH_ENABLE_DESC, new = true },
	{ key = "xp", type = "toggle", name = L.REPFLASH_XP_OPTION, desc = L.REPFLASH_XP_OPTION_DESC, new = true },
	{ key = "honor", type = "toggle", name = L.REPFLASH_HONOR_OPTION, desc = L.REPFLASH_HONOR_OPTION_DESC, new = true },
	{ key = "hideChat", type = "toggle", name = L.REPFLASH_HIDE_CHAT, desc = L.REPFLASH_HIDE_CHAT_DESC, new = true },
}

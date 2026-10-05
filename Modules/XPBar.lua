-- Experience bar: text always visible (Blizzard's own setting), text formats
-- and the experience of completed quests as a darker part of the bar.
local _, ns = ...
local L = ns.L

local XPBar = ns:NewModule("XPBar", {
	title = L.XP_TITLE,
	order = 9.2,
	defaults = {
		alwaysText = true,
		format = "full",
		questXP = true,
	},
})

local QUEST_COLOR = { 0.58 * 0.55, 0, 0.55 * 0.55, 0.9 }
local SCAN_DELAY = 0.3

local expBars = {}
local overlays = {}
local questXP = 0

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

local function BarText(current, maximum)
	local format = XPBar.db.format
	local percent = maximum > 0 and current / maximum * 100 or 0
	local remaining = maximum - current
	if format == "percent" then
		return ("%.1f%%"):format(percent)
	elseif format == "both" then
		return ("%s / %s (%.1f%%)"):format(Number(current), Number(maximum), percent)
	elseif format == "remaining" then
		return L.XP_REMAINING:format(Number(remaining))
	end
	local text = ("%s / %s (%.1f%%) – %s"):format(Number(current), Number(maximum), percent, L.XP_REMAINING:format(Number(remaining)))
	local rested = GetXPExhaustion()
	if rested and rested > 0 then
		text = text .. " – " .. L.XP_RESTED:format(Number(rested))
	end
	if questXP > 0 then
		text = text .. " – " .. L.XP_QUESTS:format(Number(questXP))
	end
	return text
end

local function UpdateText(bar)
	if XPBar.db.format == "blizzard" or not bar.currXP or not bar.maxBar or bar:IsCapped() then
		return
	end
	bar:SetBarText(BarText(bar.currXP, bar.maxBar))
end

local function UpdateOverlay(bar)
	local overlay = overlays[bar]
	if not overlay then
		-- Above the bar background, below the fill (the fill is in the BORDER layer).
		overlay = bar.StatusBar:CreateTexture(nil, "BACKGROUND", nil, 2)
		overlay:SetColorTexture(1, 1, 1)
		overlay:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT")
		overlay:SetPoint("BOTTOMLEFT", bar.StatusBar, "BOTTOMLEFT")
		overlays[bar] = overlay
	end
	local current, maximum = UnitXP("player"), UnitXPMax("player")
	if not XPBar.db.questXP or questXP <= 0 or maximum <= 0 or bar:IsCapped() then
		overlay:Hide()
		return
	end
	local fraction = min(current + questXP, maximum) / maximum
	overlay:SetVertexColor(unpack(QUEST_COLOR))
	overlay:SetWidth(max(1, bar.StatusBar:GetWidth() * fraction))
	overlay:Show()
end

local function UpdateBars()
	for bar in pairs(expBars) do
		UpdateText(bar)
		UpdateOverlay(bar)
	end
end

-- Experience of quests in the log that are ready to be turned in.
local scanPending = false
local function ScanQuestXP()
	scanPending = false
	local total = 0
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
			total = total + (GetQuestLogRewardXP(info.questID) or 0)
		end
	end
	questXP = total
	UpdateBars()
end

local function QueueScan()
	if not scanPending then
		scanPending = true
		C_Timer.After(SCAN_DELAY, ScanQuestXP)
	end
end

local function HookBars()
	for _, container in ipairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
		local bar = container.bars and container.bars[StatusTrackingBarInfo.BarsEnum.Experience]
		if bar and not expBars[bar] then
			expBars[bar] = true
			hooksecurefunc(bar, "UpdateCurrentText", UpdateText)
			hooksecurefunc(bar, "Update", UpdateOverlay)
		end
	end
	UpdateBars()
end

function XPBar:ApplyTextSetting()
	if self.db.alwaysText then
		SetCVar("xpBarText", "1")
	end
end

function XPBar:OnLogin()
	self:ApplyTextSetting()
	ns.OnAddOnLoaded("Blizzard_StatusTrackingBar", HookBars)
	self:RegisterEvent("QUEST_LOG_UPDATE", QueueScan)
	self:RegisterEvent("PLAYER_XP_UPDATE", UpdateBars)
	QueueScan()
end

function XPBar:OnOptionChanged(key)
	if key == "alwaysText" then
		SetCVar("xpBarText", self.db.alwaysText and "1" or "0")
	end
	UpdateBars()
	for bar in pairs(expBars) do
		bar:Update()
	end
end

XPBar.options = {
	{ key = "alwaysText", type = "toggle", name = L.XP_ALWAYS_TEXT, desc = L.XP_ALWAYS_TEXT_DESC },
	{ key = "format", type = "dropdown", name = L.XP_FORMAT, desc = L.XP_FORMAT_DESC, values = {
		{ "blizzard", L.XP_FORMAT_BLIZZARD }, { "percent", L.XP_FORMAT_PERCENT }, { "both", L.XP_FORMAT_BOTH },
		{ "remaining", L.XP_FORMAT_REMAINING }, { "full", L.XP_FORMAT_FULL },
	} },
	{ key = "questXP", type = "toggle", name = L.XP_QUEST_OVERLAY, desc = L.XP_QUEST_OVERLAY_DESC },
}

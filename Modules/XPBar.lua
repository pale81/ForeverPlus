-- Experience and reputation bar: text always visible (Blizzard's own setting),
-- text formats and the experience of completed quests as a darker part of the bar.
local _, ns = ...
local L = ns.L

local XPBar = ns:NewModule("XPBar", {
	title = L.XP_TITLE,
	order = 9.2,
	defaults = {
		textMode = "mouseover",
		format = "full",
		repFormat = "full",
		questXP = true,
	},
})

local QUEST_DARKEN = 0.5
local SCAN_DELAY = 0.3

local expBars = {}
local overlays = {}
local questXP = 0

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

local function BarText(current, maximum, format, extras)
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
	if not extras then
		return text
	end
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
	bar:SetBarText(BarText(bar.currXP, bar.maxBar, XPBar.db.format, true))
end

-- Reputation: Blizzard stores "Name %d / %d" while the standing is not capped.
local repBars = {}

local function UpdateRepText(bar)
	local format = XPBar.db.repFormat
	if format == "blizzard" or type(bar.name) ~= "string" or not bar.name:find("%%d") or not bar.value or not bar.max then
		return
	end
	local name = bar.name:gsub("%s*%%d%s*/%s*%%d", "")
	bar:SetBarText(("%s: %s"):format(name, BarText(bar.value, bar.max, format, false)))
end

local function UpdateOverlay(bar)
	local overlay = overlays[bar]
	if not overlay then
		-- Above the bar background, below the fill (the fill is in the BORDER layer).
		overlay = bar.StatusBar:CreateTexture(nil, "BACKGROUND", nil, 2)
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
	-- Same texture as the fill (purple normally, blue while rested), darker.
	local fill = bar.StatusBar:GetStatusBarTexture()
	local atlas = fill and fill:GetAtlas()
	if atlas then
		overlay:SetAtlas(atlas)
	elseif fill and fill:GetTexture() then
		overlay:SetTexture(fill:GetTexture())
	else
		overlay:SetColorTexture(1, 1, 1)
	end
	local r, g, b = bar.StatusBar:GetStatusBarColor()
	local vr, vg, vb = 1, 1, 1
	if fill then
		vr, vg, vb = fill:GetVertexColor()
	end
	overlay:SetVertexColor((r or 1) * vr * QUEST_DARKEN, (g or 1) * vg * QUEST_DARKEN, (b or 1) * vb * QUEST_DARKEN, 1)
	local width = ns.Number(bar.StatusBar:GetWidth())
	if not width then
		overlay:Hide()
		return
	end
	overlay:SetWidth(max(1, width * fraction))
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
		if info and not info.isHeader and info.questID and ns.IsQuestReady(info.questID, index) then
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
			if bar.UpdateStatusBarTextures then
				hooksecurefunc(bar, "UpdateStatusBarTextures", UpdateOverlay)
			end
		end
		local repBar = container.bars and container.bars[StatusTrackingBarInfo.BarsEnum.Reputation]
		if repBar and not repBars[repBar] then
			repBars[repBar] = true
			hooksecurefunc(repBar, "Update", UpdateRepText)
			hooksecurefunc(repBar, "UpdateCurrentText", UpdateRepText)
		end
	end
	UpdateBars()
end

-- Blizzard's own setting: numbers always or only on mouseover. Set at every
-- login, so an older "always" setting does not stick.
function XPBar:ApplyTextSetting()
	SetCVar("xpBarText", self.db.textMode == "always" and "1" or "0")
end

function XPBar:OnInitialize()
	if self.db.alwaysText ~= nil then
		self.db.textMode = self.db.alwaysText and "always" or "mouseover"
		self.db.alwaysText = nil
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
	if key == "textMode" then
		self:ApplyTextSetting()
	end
	UpdateBars()
	for bar in pairs(expBars) do
		bar:Update()
	end
	for bar in pairs(repBars) do
		bar:Update()
	end
end

XPBar.options = {
	{ key = "textMode", type = "dropdown", name = L.XP_TEXT_MODE, desc = L.XP_TEXT_MODE_DESC, values = {
		{ "mouseover", L.XP_TEXT_MOUSEOVER }, { "always", L.XP_TEXT_ALWAYS },
	} },
	{ key = "format", type = "dropdown", name = L.XP_FORMAT, desc = L.XP_FORMAT_DESC, values = {
		{ "blizzard", L.XP_FORMAT_BLIZZARD }, { "percent", L.XP_FORMAT_PERCENT }, { "both", L.XP_FORMAT_BOTH },
		{ "remaining", L.XP_FORMAT_REMAINING }, { "full", L.XP_FORMAT_FULL },
	} },
	{ key = "repFormat", type = "dropdown", name = L.XP_REP_FORMAT, desc = L.XP_REP_FORMAT_DESC, values = {
		{ "blizzard", L.XP_FORMAT_BLIZZARD }, { "percent", L.XP_FORMAT_PERCENT }, { "both", L.XP_FORMAT_BOTH },
		{ "remaining", L.XP_FORMAT_REMAINING }, { "full", L.XP_REP_FORMAT_FULL },
	} },
	{ key = "questXP", type = "toggle", name = L.XP_QUEST_OVERLAY, desc = L.XP_QUEST_OVERLAY_DESC },
}

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
		xpRate = true,
		restedShimmer = true,
		bar1Width = 100,
		bar1Height = 100,
		bar2Width = 100,
		bar2Height = 100,
	},
})

local function Percent(value)
	return ("%d%%"):format(value + 0.5)
end

-- Each status bar container (1 = main, 2 = secondary, as in Edit Mode) has its own size.
local SIZE_OPTIONS = {}
local SIZE_KEYS = {}
for index = 1, 2 do
	local width, height = "bar" .. index .. "Width", "bar" .. index .. "Height"
	SIZE_KEYS[width], SIZE_KEYS[height] = true, true
	SIZE_OPTIONS[index] = {
		{ key = width, name = L.XP_BAR_WIDTH, desc = L.XP_BAR_WIDTH_DESC, min = 10, max = 100, step = 5, format = Percent },
		{ key = height, name = L.XP_BAR_HEIGHT, desc = L.XP_BAR_HEIGHT_DESC, min = 30, max = 100, step = 5, format = Percent },
	}
end

local function ContainerIndex(container)
	return container == SecondaryStatusTrackingBarContainer and 2 or 1
end

local QUEST_COLOR = { 0.4, 0.24, 0.09 } -- a dark, muted orange: apart from the purple fill and the blue of the rested bonus, but not in front
local QUEST_ALPHA = 0.6 -- see-through, so the bar below shows a little
local SCAN_DELAY = 0.45 -- staggered from Quests: quest log scan (0.3 s) so both do not land in one frame

local expBars = {}
local overlays = {}
local questXP = 0

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- Experience per hour since login (or /reload), level-ups included. No figure for the first two minutes.
local RATE_WARMUP = 120
local session = {}

function XPBar.TrackXP(now, current, maximum)
	now, current, maximum = ns.Number(now), ns.Number(current), ns.Number(maximum)
	if not (now and current and maximum) then return end
	if not session.start then
		session.start, session.gained, session.last, session.lastMax = now, 0, current, maximum
		return
	end
	if current >= session.last then
		session.gained = session.gained + current - session.last
	else
		session.gained = session.gained + (session.lastMax - session.last) + current
	end
	session.last, session.lastMax = current, maximum
end

function XPBar.ResetRate()
	wipe(session)
end

function XPBar.Rate(now)
	local elapsed = session.start and now - session.start or 0
	if elapsed < RATE_WARMUP or session.gained <= 0 then return end
	return session.gained / elapsed * 3600
end

local function Duration(hours)
	local minutes = math.floor(hours * 60 + 0.5)
	return L.XP_DURATION:format(math.floor(minutes / 60), minutes % 60)
end

local function RateText(remaining)
	local rate = XPBar.db.xpRate and XPBar.Rate(GetTime())
	if not rate then return end
	return L.XP_RATE:format(Number(math.floor(rate + 0.5))) .. " – " .. L.XP_TO_LEVEL:format(Duration(remaining / rate))
end

XPBar.RateText = RateText

-- The parts of the full text in reading order; keep: the higher, the longer a part stays on a short bar.
local function FullParts(current, maximum, percent, remaining, extras)
	local parts = {
		{ text = ("%s / %s (%.1f%%)"):format(Number(current), Number(maximum), percent), keep = 6,
			short = ("%.1f%%"):format(percent) },
		{ text = L.XP_REMAINING:format(Number(remaining)), keep = 5 },
	}
	if not extras then return parts end
	local rested = GetXPExhaustion()
	if rested and rested > 0 then
		parts[#parts + 1] = { text = L.XP_RESTED:format(Number(rested)), keep = 1 }
	end
	if questXP > 0 then
		parts[#parts + 1] = { text = L.XP_QUESTS:format(Number(questXP)), keep = 2 }
	end
	local rate = XPBar.db.xpRate and XPBar.Rate(GetTime())
	if rate then
		parts[#parts + 1] = { text = L.XP_RATE:format(Number(math.floor(rate + 0.5))), keep = 3 }
		parts[#parts + 1] = { text = L.XP_TO_LEVEL:format(Duration(remaining / rate)), keep = 4 }
	end
	return parts
end

local function Join(parts)
	local texts = {}
	for index, part in ipairs(parts) do texts[index] = part.text end
	return table.concat(texts, " – ")
end

-- The longest text that fits(text): the part with the lowest keep goes first; at the end only the short form.
function XPBar.FitParts(parts, fits)
	local list = {}
	for index, part in ipairs(parts) do list[index] = part end
	local text = Join(list)
	while not fits(text) and #list > 1 do
		local lowest = 1
		for index, part in ipairs(list) do
			if part.keep < list[lowest].keep then lowest = index end
		end
		table.remove(list, lowest)
		text = Join(list)
	end
	if not fits(text) and list[1].short then text = list[1].short end
	return text
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
	local parts = FullParts(current, maximum, percent, remaining, extras)
	return Join(parts), parts
end

local TEXT_PADDING = 12

local function UpdateText(bar)
	if XPBar.db.format == "blizzard" or not bar.currXP or not bar.maxBar or bar:IsCapped() then
		return
	end
	local text, parts = BarText(bar.currXP, bar.maxBar, XPBar.db.format, true)
	local label = bar.OverlayFrame and bar.OverlayFrame.Text
	local width = ns.Number(bar.GetWidth and bar:GetWidth())
	if parts and label and width then
		-- Shrunk bars (Edit Mode) cut a long text off: drop the least important parts instead.
		text = XPBar.FitParts(parts, function(candidate)
			label:SetText(candidate)
			local used = ns.Number(label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth())
			return not used or used <= width - TEXT_PADDING
		end)
	end
	bar:SetBarText(text)
end

-- Reputation: Blizzard stores "Name %d / %d" while the standing is not capped.
local repBars = {}

local function UpdateRepText(bar)
	local format = XPBar.db.repFormat
	if format == "blizzard" or type(bar.name) ~= "string" or not bar.name:find("%%d") or not bar.value or not bar.max then
		return
	end
	local name = bar.name:gsub("%s*%%d%s*/%s*%%d", "")
	bar:SetBarText(("%s: %s"):format(name, (BarText(bar.value, bar.max, format, false))))
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
	-- A plain dark purple (the fill's own colour changes with rested state and, on
	-- the reputation bar, is green).
	overlay:SetColorTexture(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3], QUEST_ALPHA)
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
	if not XPBar.db.questXP then
		if questXP ~= 0 then
			questXP = 0 -- no scan of the quest log while the option is off
			UpdateBars()
		end
		return
	end
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID and ns.IsQuestReady(info.questID, index) then
			total = total + (GetQuestLogRewardXP(info.questID) or 0)
		end
	end
	if total ~= questXP then
		questXP = total
		UpdateBars()
	end
end

local function QueueScan()
	if not scanPending then
		scanPending = true
		ns.After("XPBar: ScanQuestXP", SCAN_DELAY, ScanQuestXP)
	end
end

-- The little pin of the rested bonus glints (a star that turns slowly and breathes) while the mouse is over
-- the bar: like the shimmer that Blizzard puts on new buttons.
local shimmers = {}

local function GetShimmer(tick)
	local shimmer = shimmers[tick]
	if not shimmer then
		shimmer = CreateFrame("Frame", nil, tick)
		shimmer:SetSize(46, 46)
		shimmer:SetPoint("CENTER", tick, "CENTER")
		shimmer:EnableMouse(false)
		local glow = shimmer:CreateTexture(nil, "OVERLAY")
		glow:SetAllPoints()
		glow:SetTexture([[Interface\Cooldown\star4]])
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.65, 0.88, 1)
		local turn = glow:CreateAnimationGroup()
		turn:SetLooping("REPEAT")
		local spin = turn:CreateAnimation("Rotation")
		spin:SetDegrees(-90)
		spin:SetDuration(2.4)
		local breathe = glow:CreateAnimationGroup()
		breathe:SetLooping("BOUNCE")
		local fade = breathe:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.15)
		fade:SetToAlpha(0.95)
		fade:SetDuration(0.7)
		fade:SetSmoothing("IN_OUT")
		shimmer:SetScript("OnShow", function()
			turn:Play()
			breathe:Play()
		end)
		shimmer:SetScript("OnHide", function()
			turn:Stop()
			breathe:Stop()
		end)
		shimmer:Hide()
		shimmers[tick] = shimmer
	end
	return shimmer
end

local function ShimmerOn(bar)
	local tick = bar.ExhaustionTick
	if XPBar.db.restedShimmer and tick and tick:IsShown() then
		GetShimmer(tick):Show()
	end
end

-- A short glint when the game is entered or reloaded (3 seconds), as a hint that there is rested bonus.
local function ShimmerPulse(bar, seconds)
	local tick = bar.ExhaustionTick
	if not (XPBar.db.restedShimmer and tick and tick:IsShown()) then
		return
	end
	GetShimmer(tick):Show()
	ns.After("XPBar: ShimmerPulse (timer)", seconds, function()
		if shimmers[tick] and not bar:IsMouseOver() then
			shimmers[tick]:Hide()
		end
	end)
end

local function ShimmerOff(bar)
	local tick = bar.ExhaustionTick
	if tick and shimmers[tick] then
		shimmers[tick]:Hide()
	end
end

-- Extra shrinking of the bars (percent of the standard size, which Edit Mode may already have changed).
-- baseSizes keeps that standard size per container: every SetSize that is not ours (Blizzard, Edit Mode) renews it.
local MIN_INNER = 2 -- smallest height or width of the bar inside the frame
local baseSizes = {}
local hookedContainers = {}
local sizing = false
local fitted = {}

local function ScaledSize(baseWidth, baseHeight, widthPercent, heightPercent)
	local smallest = (STATUS_BAR_SIZE_ADJUSTMENT or 0) + MIN_INNER
	return min(baseWidth, max(baseWidth * widthPercent / 100, smallest)), min(baseHeight, max(baseHeight * heightPercent / 100, smallest))
end
XPBar.ScaledSize = ScaledSize

-- The frame picture has the size of its atlas; on a smaller bar it is stretched over the whole container.
local function FitFrame(container, shrunk)
	local frame = container.BarFrameTexture
	if not frame or fitted[container] == shrunk then
		return
	end
	if not shrunk and fitted[container] == nil then
		return
	end
	fitted[container] = shrunk
	frame:ClearAllPoints()
	if shrunk then
		frame:SetPoint("TOPLEFT", container, "TOPLEFT")
		frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT")
	else
		frame:SetPoint("CENTER", container, "CENTER")
		local atlas = frame:GetAtlas()
		if atlas then
			frame:SetAtlas(atlas, true)
		end
	end
end

-- The section strokes keep their distance and size: a narrower bar gets fewer of them instead of squeezed ones.
local function SegmentCount(expected, width, baseWidth)
	return max(1, floor(expected * width / baseWidth + 0.5))
end
XPBar.SegmentCount = SegmentCount

local dividing = false

local function LayoutDividers(container)
	local base = baseSizes[container]
	local width = ns.Number(container:GetWidth())
	if not (base and width and container.UpdateDividers and container.GetExpectedSegments) then
		return
	end
	dividing = true
	container:UpdateDividers(SegmentCount(container:GetExpectedSegments(), width, base[1]))
	dividing = false
end

local function ApplySize(container)
	local base = baseSizes[container]
	if not base then
		return
	end
	local index = ContainerIndex(container)
	local width, height = ScaledSize(base[1], base[2], XPBar.db["bar" .. index .. "Width"], XPBar.db["bar" .. index .. "Height"])
	sizing = true
	container:SetSize(width, height)
	sizing = false
	base[3] = ns.Number(container:GetHeight())
	FitFrame(container, width < base[1] or height < base[2])
	if container.ResizeContainerBars then
		container:ResizeContainerBars()
	end
	LayoutDividers(container)
end

local function OnContainerSize(container)
	if sizing then
		return
	end
	local width, height = ns.Number(container:GetWidth()), ns.Number(container:GetHeight())
	if width and height then
		local base = baseSizes[container]
		-- The native width slider passes GetHeight() back to SetSize. In that case the height is already scaled.
		baseSizes[container] = { width, (base and height == base[3]) and base[2] or height }
	end
	ApplySize(container)
end

local function HookContainer(container)
	if hookedContainers[container] then
		return
	end
	hookedContainers[container] = true
	OnContainerSize(container)
	hooksecurefunc(container, "SetSize", ns.Measured("XPBar: track native size", OnContainerSize))
	if container.UpdateDividers then
		-- The game lays the strokes out again for the current width (layout changes); keep the distance.
		hooksecurefunc(container, "UpdateDividers", ns.Measured("XPBar: keep stroke distance", function(self, numSegments)
			if not dividing and baseSizes[self] and numSegments ~= SegmentCount(numSegments, ns.Number(self:GetWidth(), 0), baseSizes[self][1]) then
				LayoutDividers(self)
			end
		end))
	end
end

local function ApplySizes()
	for container in pairs(baseSizes) do
		ApplySize(container)
	end
end

local function SetupEditSizeControls()
	local dialog = EditModeSystemSettingsDialog
	if not (dialog and dialog.Settings and dialog.UpdateSettings) then
		return
	end
	local controls, refresh = {}, {}
	hooksecurefunc(dialog, "UpdateSettings", ns.Measured("XPBar: show Edit Mode size controls", function(self, system)
		if system ~= self.attachedToSystem then
			return
		end
		local shown = hookedContainers[system] == true and self.Settings:IsShown()
		if shown and not controls[system] then
			local frame = CreateFrame("Frame", nil, self.Settings)
			frame.layoutIndex = 100
			frame:SetSize(330, 72)
			frame:Hide()
			local sync = {}
			local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			hint:SetPoint("TOPLEFT", 4, -3)
			hint:SetText(L.XP_BAR_SIZE_HINT)
			for index, option in ipairs(SIZE_OPTIONS[ContainerIndex(system)]) do
				local y = -15 - (index - 1) * 27
				local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
				label:SetPoint("LEFT", frame, "TOPLEFT", 4, y - 13)
				label:SetText(option.name)
				local slider, refreshSlider = ns.CreateEditSlider(frame, XPBar, option)
				slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 125, y - 2)
				slider:SetSize(146, 24)
				sync[index] = refreshSlider
			end
			controls[system], refresh[system] = frame, sync
		end
		if shown then
			for _, sync in ipairs(refresh[system]) do sync() end
		end
		local changed
		for owner, frame in pairs(controls) do
			local visible = shown and owner == system
			if frame:IsShown() ~= visible then
				frame:SetShown(visible)
				changed = true
			end
		end
		-- UpdateSettings lays out the native rows first; include our rows before the dialog sizes itself.
		if changed and self.Settings:IsShown() then
			self.Settings:Layout()
		end
	end))
end

local function HookBars()
	for _, container in ipairs(StatusTrackingBarManager and StatusTrackingBarManager.barContainers or {}) do
		HookContainer(container)
		local updateText = ns.Measured("XPBar: UpdateText", UpdateText)
		local updateOverlay = ns.Measured("XPBar: UpdateOverlay", UpdateOverlay)
		local updateRepText = ns.Measured("XPBar: UpdateRepText", UpdateRepText)
		local bar = container.bars and container.bars[StatusTrackingBarInfo.BarsEnum.Experience]
		if bar and not expBars[bar] then
			expBars[bar] = true
			hooksecurefunc(bar, "UpdateCurrentText", updateText)
			hooksecurefunc(bar, "Update", updateOverlay)
			bar:HookScript("OnEnter", ShimmerOn)
			bar:HookScript("OnLeave", ShimmerOff)
			if bar.UpdateStatusBarTextures then
				hooksecurefunc(bar, "UpdateStatusBarTextures", updateOverlay)
			end
		end
		local repBar = container.bars and container.bars[StatusTrackingBarInfo.BarsEnum.Reputation]
		if repBar and not repBars[repBar] then
			repBars[repBar] = true
			hooksecurefunc(repBar, "Update", updateRepText)
			hooksecurefunc(repBar, "UpdateCurrentText", updateRepText)
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
	-- Until now one size applied to both bars.
	if self.db.barWidth ~= nil or self.db.barHeight ~= nil then
		for index = 1, 2 do
			self.db["bar" .. index .. "Width"] = self.db.barWidth or self.db["bar" .. index .. "Width"]
			self.db["bar" .. index .. "Height"] = self.db.barHeight or self.db["bar" .. index .. "Height"]
		end
		self.db.barWidth, self.db.barHeight = nil, nil
	end
	if self.db.alwaysText ~= nil then
		self.db.textMode = self.db.alwaysText and "always" or "mouseover"
		self.db.alwaysText = nil
	end
end

function XPBar:OnLogin()
	self:ApplyTextSetting()
	-- After the bars had their first update: a glint on the rested pin.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin, isReloadingUi)
		if isInitialLogin or isReloadingUi then
			ns.After("XPBar: OnLogin (timer)", 2, function()
				for bar in pairs(expBars) do
					ShimmerPulse(bar, 3)
				end
			end)
		end
	end)
	ns.OnAddOnLoaded("Blizzard_StatusTrackingBar", HookBars)
	ns.OnAddOnLoaded("Blizzard_EditMode", SetupEditSizeControls)
	self:RegisterEvent("QUEST_LOG_UPDATE", QueueScan)
	XPBar.TrackXP(GetTime(), UnitXP("player"), UnitXPMax("player"))
	self:RegisterEvent("PLAYER_XP_UPDATE", function()
		XPBar.TrackXP(GetTime(), UnitXP("player"), UnitXPMax("player"))
		UpdateBars()
	end)
	QueueScan()
end

function XPBar:OnOptionChanged(key)
	if key == "textMode" then
		self:ApplyTextSetting()
	elseif key == "questXP" then
		QueueScan()
	elseif SIZE_KEYS[key] then
		ApplySizes()
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
	{ key = "restedShimmer", type = "toggle", name = L.XP_SHIMMER, desc = L.XP_SHIMMER_DESC, new = true },
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
	{ key = "xpRate", type = "toggle", name = L.XP_RATE_OPTION, desc = L.XP_RATE_OPTION_DESC },
}

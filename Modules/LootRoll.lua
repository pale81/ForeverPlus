-- Compact group loot roll frames: replaces Blizzard's default group roll toasts
-- with slim, stacked quality-coloured bars showing a live countdown bar, spark,
-- item tooltip/comparison, upgrade arrow, Need/Greed/Transmog/Disenchant/Pass
-- buttons with voter counts and class-coloured player lists, BoP/BoE tag, and
-- Shift-click confirmation bypass. Positioned in Edit Mode.
local _, ns = ...
local L = ns.L

local LootRoll = ns:NewModule("LootRoll", {
	title = L.LOOTROLL_TITLE,
	order = 2.65,
	defaults = {
		enabled = true,
		width = 328,
		height = 28,
		scale = 1,
		growUp = false,
		showUpgrade = true,
	},
})

local BAR_GAP = 4
local DEFAULT_ANCHOR = { "BOTTOM", UIParent, "BOTTOM", 0, 221 }

local BAR_BACKDROP = {
	bgFile = [[Interface\Buttons\WHITE8X8]],
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local ICON_BACKDROP = {
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function RollKeyForState(state)
	local states = Enum and Enum.EncounterLootDropRollState
	if not states then
		return nil
	end
	if state == states.NeedMainSpec or state == states.NeedOffSpec then
		return "need"
	elseif state == states.Greed then
		return "greed"
	elseif state == states.Transmog then
		return "transmog"
	elseif state == states.Pass then
		return "pass"
	end
end

local ROLL_KEYS = { "need", "greed", "transmog", "disenchant", "pass" }

local anchor
local editPanel
local updateFrame
local barPool = {}       -- all created bars
local activeBars = {}    -- currently visible bars in display order
local activeByRollID = {} -- rollID -> bar
local cancelledRolls = {}
local active = false     -- true once Blizzard's START_LOOT_ROLL has been detached
local previewActive = false
local editPreview = false

local LayoutBars, RefreshTimerLoop, ApplyBarSize, ApplySingleBarSize, ShowEditOptions

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	if quality and ColorManager and ColorManager.GetColorDataForItemQuality then
		local data = ColorManager.GetColorDataForItemQuality(quality)
		if data then
			return data.r, data.g, data.b
		end
	end
	return 1, 1, 1
end

local function ItemIDOfLink(link)
	if type(link) ~= "string" or ns.Secret(link) then
		return nil
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local id = C_Item.GetItemInfoInstant(link)
		if id then
			return id
		end
	end
	return tonumber(link:match("item:(%d+)"))
end

local function SetButtonTexture(button, kind, atlas, file)
	local useAtlas = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if kind == "Normal" then
		if useAtlas then
			button:SetNormalAtlas(atlas)
		else
			button:SetNormalTexture(file)
		end
	elseif kind == "Pushed" then
		if useAtlas then
			button:SetPushedAtlas(atlas)
		else
			button:SetPushedTexture(file)
		end
	elseif kind == "Highlight" then
		if useAtlas then
			button:SetHighlightAtlas(atlas, "ADD")
		else
			button:SetHighlightTexture(file, "ADD")
		end
	end
end

local function FormatTimeLeft(seconds)
	if seconds <= 0 then
		return ""
	elseif seconds >= 60 then
		return ("%dm"):format(math.ceil(seconds / 60))
	end
	return ("%ds"):format(math.ceil(seconds))
end

local function ClearRollCounts(bar)
	for _, key in ipairs(ROLL_KEYS) do
		wipe(bar.voters[key])
		local btn = bar.buttons[key]
		if btn and btn.Count then
			btn.Count:SetText("")
		end
	end
	wipe(bar.chatVoters)
	bar.hasHistory = false
end

local function UpdateButtonCount(bar, key)
	local btn = bar.buttons[key]
	if not btn or not btn.Count then
		return
	end
	local count = #bar.voters[key]
	btn.Count:SetText(count > 0 and tostring(count) or "")
end

local function RefreshBarUpgrade(bar)
	if not bar.UpgradeArrow then
		return
	end
	if not (LootRoll.db.showUpgrade and bar.link and ns.RewardComparisonState and ns.SetItemComparisonArrow) then
		bar.UpgradeArrow:Hide()
		return
	end
	local link = bar.link
	local state = ns.RewardComparisonState(link, function()
		if bar:IsShown() and bar.link == link then
			RefreshBarUpgrade(bar)
		end
	end)
	ns.SetItemComparisonArrow(bar.UpgradeArrow, state, 0.75)
end

---------------------------------------------------------------------------
-- Chat roll parsing (fallback for dungeon trash / world drops without C_LootHistory)
---------------------------------------------------------------------------
local chatRollPatterns

local function BuildChatRollPatterns()
	if chatRollPatterns then
		return chatRollPatterns
	end
	chatRollPatterns = {}
	local FormatToPattern = ns.FormatToPattern
	if not FormatToPattern then
		return chatRollPatterns
	end
	local defs = {
		{ _G.LOOT_ROLL_NEED, "need", false },
		{ _G.LOOT_ROLL_NEED_SELF, "need", true },
		{ _G.LOOT_ROLL_GREED, "greed", false },
		{ _G.LOOT_ROLL_GREED_SELF, "greed", true },
		{ _G.LOOT_ROLL_TRANSMOG, "transmog", false },
		{ _G.LOOT_ROLL_TRANSMOG_SELF, "transmog", true },
		{ _G.LOOT_ROLL_DISENCHANT, "disenchant", false },
		{ _G.LOOT_ROLL_DISENCHANT_SELF, "disenchant", true },
		{ _G.LOOT_ROLL_PASSED_AUTO, "pass", false },
		{ _G.LOOT_ROLL_PASSED_AUTO_FEMALE, "pass", false },
		{ _G.LOOT_ROLL_PASSED_SELF_AUTO, "pass", true },
		{ _G.LOOT_ROLL_PASSED, "pass", false },
		{ _G.LOOT_ROLL_PASSED_SELF, "pass", true },
	}
	for _, def in ipairs(defs) do
		local fmt = def[1]
		if type(fmt) == "string" and fmt ~= "" then
			local compiled = FormatToPattern(fmt, true)
			if compiled and compiled.pattern then
				chatRollPatterns[#chatRollPatterns + 1] = {
					pattern = compiled.pattern,
					order = compiled.order,
					rollKey = def[2],
					isSelf = def[3],
				}
			end
		end
	end
	return chatRollPatterns
end

local function ParseChatRoll(text)
	if type(text) ~= "string" or ns.Secret(text) then
		return nil
	end
	for _, entry in ipairs(BuildChatRollPatterns()) do
		local captures = { text:match(entry.pattern) }
		if captures[1] then
			local args = {}
			for i, value in ipairs(captures) do
				args[entry.order[i]] = value
			end
			local player, link
			if entry.isSelf then
				player = UnitName("player")
				link = args[1]
			else
				player = args[1]
				link = args[2]
			end
			if link and link:find("|Hitem:", 1, true) then
				return entry.rollKey, player, link
			end
		end
	end
end

local function ApplyChatVoters(bar)
	for _, key in ipairs(ROLL_KEYS) do
		wipe(bar.voters[key])
	end
	for player, key in pairs(bar.chatVoters) do
		local list = bar.voters[key]
		if list then
			list[#list + 1] = player
		end
	end
	for _, key in ipairs(ROLL_KEYS) do
		table.sort(bar.voters[key])
		UpdateButtonCount(bar, key)
	end
end

---------------------------------------------------------------------------
-- Roll button configuration & bar layout
---------------------------------------------------------------------------
local function SetButtonEnabled(button, enabled, reason)
	button.reason = not enabled and reason or nil
	local tex = button:GetNormalTexture()
	if enabled then
		button:Enable()
		button:SetAlpha(1)
		if tex and tex.SetDesaturated then
			tex:SetDesaturated(false)
		end
	else
		button:Disable()
		button:SetAlpha(0.35)
		if tex and tex.SetDesaturated then
			tex:SetDesaturated(true)
		end
	end
end

local function PositionBarControls(bar)
	local prev = bar.IconButton
	local order = {
		bar.buttons.need,
		bar.showTransmog and bar.buttons.transmog or bar.buttons.greed,
		bar.showDisenchant and bar.buttons.disenchant or nil,
		bar.buttons.pass,
	}
	bar.buttons.greed:SetShown(not bar.showTransmog)
	bar.buttons.transmog:SetShown(bar.showTransmog)
	bar.buttons.disenchant:SetShown(bar.showDisenchant)
	for index, btn in ipairs(order) do
		btn:ClearAllPoints()
		local xOff = index == 1 and 5 or 1
		local yOff = btn.yOffset or 0
		btn:SetPoint("LEFT", prev, "RIGHT", xOff, yOff)
		prev = btn
	end
	bar.BindText:ClearAllPoints()
	bar.BindText:SetPoint("LEFT", prev, "RIGHT", 4, 0)
end

---------------------------------------------------------------------------
-- Tooltips and clicks
---------------------------------------------------------------------------
local function ShowRollButtonTooltip(button)
	local bar = button.bar
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if GameTooltip_SetTitle then
		GameTooltip_SetTitle(GameTooltip, button.tooltipText)
	else
		GameTooltip:SetText(button.tooltipText)
	end
	if not button:IsEnabled() and button.reason and button.reason ~= "" then
		GameTooltip:AddLine(button.reason, 1, 0.2, 0.2, true)
	end
	local voters = bar.voters[button.rollKey]
	if voters and #voters > 0 then
		for _, line in ipairs(voters) do
			GameTooltip:AddLine(line, 1, 1, 1)
		end
	end
	if button:IsEnabled() and button.rollType ~= 0 and bar.bop then
		GameTooltip:AddLine(" ")
		if GameTooltip_AddInstructionLine then
			GameTooltip_AddInstructionLine(GameTooltip, L.LOOTROLL_SHIFT_HINT)
		else
			GameTooltip:AddLine(L.LOOTROLL_SHIFT_HINT, 0, 1, 0)
		end
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local OnIconUpdate

local function ShowItemTooltip(iconBtn)
	local bar = iconBtn.bar
	if not (bar.rollID or bar.link) then
		return
	end
	GameTooltip:SetOwner(iconBtn, "ANCHOR_TOPLEFT")
	if bar.rollID and not bar.preview and GameTooltip.SetLootRollItem then
		GameTooltip:SetLootRollItem(bar.rollID)
	elseif bar.link then
		GameTooltip:SetHyperlink(bar.link)
	end
	if IsShiftKeyDown() and GameTooltip_ShowCompareItem then
		GameTooltip_ShowCompareItem()
	end
	if IsModifiedClick("DRESSUP") and ShowInspectCursor then
		ShowInspectCursor()
	elseif ResetCursor then
		ResetCursor()
	end
	GameTooltip:Show()
	ns.SetUpdate(iconBtn, "LootRoll: item tooltip", OnIconUpdate)
end

local function HideItemTooltip(iconBtn)
	ns.SetUpdate(iconBtn, "LootRoll: item tooltip", nil)
	GameTooltip:Hide()
	if ResetCursor then
		ResetCursor()
	end
end

OnIconUpdate = function(iconBtn)
	if GameTooltip:IsOwned(iconBtn) then
		if IsShiftKeyDown() and GameTooltip_ShowCompareItem then
			GameTooltip_ShowCompareItem()
		end
		if CursorOnUpdate then
			CursorOnUpdate(iconBtn)
		end
	else
		ns.SetUpdate(iconBtn, "LootRoll: item tooltip", nil)
	end
end

local function OnIconClick(iconBtn)
	local bar = iconBtn.bar
	local link = bar.link or (bar.rollID and not bar.preview and GetLootRollItemLink(bar.rollID))
	if link and HandleModifiedItemClick then
		HandleModifiedItemClick(link)
	end
end

local function RemoveBar(bar)
	if bar.rollID and activeByRollID[bar.rollID] == bar then
		activeByRollID[bar.rollID] = nil
	end
	bar.rollID = nil
	bar.duration = nil
	bar.link = nil
	bar.itemID = nil
	bar.bop = nil
	bar.preview = nil
	bar.previewLeft = nil
	if bar.IconButton then
		ns.SetUpdate(bar.IconButton, "LootRoll: item tooltip", nil)
	end
	bar:Hide()
	for i = #activeBars, 1, -1 do
		if activeBars[i] == bar then
			table.remove(activeBars, i)
			break
		end
	end
	-- Keep previewActive in sync if the user manually dismissed the last preview bar.
	if previewActive then
		local anyPreview = false
		for _, entry in ipairs(activeBars) do
			if entry.preview then
				anyPreview = true
				break
			end
		end
		if not anyPreview then
			previewActive = false
		end
	end
	LayoutBars()
	RefreshTimerLoop()
end

local function OnRollButtonClick(button)
	local bar = button.bar
	if bar.preview then
		RemoveBar(bar)
		return
	end
	if not bar.rollID then
		return
	end
	if IsShiftKeyDown() and button.rollType ~= 0 and ConfirmLootRoll then
		ConfirmLootRoll(bar.rollID, button.rollType)
	elseif RollOnLoot then
		RollOnLoot(bar.rollID, button.rollType)
	end
end

---------------------------------------------------------------------------
-- Bar creation
---------------------------------------------------------------------------
local function CreateRollButton(parent, bar, rollKey, rollType, tooltipText, atlasPrefix, filePrefix, yOffset)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(24, 24)
	SetButtonTexture(btn, "Normal", atlasPrefix and (atlasPrefix .. "-up"), filePrefix .. "-Up")
	SetButtonTexture(btn, "Pushed", atlasPrefix and (atlasPrefix .. "-down"), filePrefix .. "-Down")
	SetButtonTexture(btn, "Highlight", atlasPrefix and (atlasPrefix .. "-highlight"), filePrefix .. "-Highlight")
	btn.bar = bar
	btn.rollKey = rollKey
	btn.rollType = rollType
	btn.tooltipText = tooltipText
	btn.yOffset = yOffset or 0
	btn:SetMotionScriptsWhileDisabled(true)
	btn:SetScript("OnEnter", ns.Measured("LootRoll: button tooltip", ShowRollButtonTooltip))
	btn:SetScript("OnLeave", HideTooltip)
	btn:SetScript("OnClick", ns.Measured("LootRoll: roll click", OnRollButtonClick))

	local count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	count:SetPoint("CENTER", 0, rollType == 2 and 1 or rollType == 0 and -1 or 0)
	btn.Count = count
	return btn
end

local function CreateRollBar()
	local bar = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	bar:SetFrameStrata("DIALOG")
	bar:SetBackdrop(BAR_BACKDROP)
	bar:SetBackdropColor(0.06, 0.07, 0.10, 0.92)
	bar:Hide()

	-- Subtle vertical gloss matching the compact bar look.
	local sheen = bar:CreateTexture(nil, "BORDER")
	sheen:SetPoint("TOPLEFT", 3, -3)
	sheen:SetPoint("BOTTOMRIGHT", -3, 3)
	sheen:SetColorTexture(1, 1, 1, 1)
	sheen:SetBlendMode("ADD")
	if sheen.SetGradient and CreateColor then
		sheen:SetGradient("VERTICAL", CreateColor(0.08, 0.08, 0.08, 0), CreateColor(0.24, 0.24, 0.24, 0.32))
	end

	-- Item icon button on the left.
	local iconBtn = CreateFrame("Button", nil, bar)
	iconBtn:SetPoint("LEFT", 4, 0)
	iconBtn:SetSize(24, 24)
	iconBtn:SetFrameLevel(bar:GetFrameLevel() + 3)
	iconBtn.bar = bar
	iconBtn:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	iconBtn:SetScript("OnEnter", ns.Measured("LootRoll: item tooltip", ShowItemTooltip))
	iconBtn:SetScript("OnLeave", HideItemTooltip)
	iconBtn:SetScript("OnClick", ns.Measured("LootRoll: item click", OnIconClick))

	local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	bar.Icon = iconTex

	local iconBorder = CreateFrame("Frame", nil, iconBtn, "BackdropTemplate")
	iconBorder:SetPoint("TOPLEFT", -2, 2)
	iconBorder:SetPoint("BOTTOMRIGHT", 2, -2)
	iconBorder:SetBackdrop(ICON_BACKDROP)
	bar.IconBorder = iconBorder

	local stackText = iconBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	stackText:SetPoint("BOTTOMRIGHT", -1, 1)
	stackText:SetJustifyH("RIGHT")
	bar.StackCount = stackText

	local arrow = iconBtn:CreateTexture(nil, "OVERLAY", nil, 2)
	arrow:SetAtlas("bags-greenarrow", true)
	arrow:SetPoint("TOPLEFT", -2, 2)
	arrow:Hide()
	bar.UpgradeArrow = arrow
	bar.IconButton = iconBtn

	-- Timer status bar spanning the area to the right of the icon.
	local status = CreateFrame("StatusBar", nil, bar)
	status:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 1, -1)
	status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -3, 3)
	status:SetFrameLevel(bar:GetFrameLevel() + 1)
	status:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
	status:SetStatusBarColor(0.8, 0.8, 0.8, 0.65)
	bar.Status = status

	-- Dark bottom gradient overlay over the status bar (replaces DarkBottom.tga).
	local shade = status:CreateTexture(nil, "ARTWORK")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 1)
	if shade.SetGradient and CreateColor then
		shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
	end

	local spark = status:CreateTexture(nil, "OVERLAY")
	spark:SetSize(14, LootRoll.db.height + 6)
	spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
	spark:SetBlendMode("ADD")
	bar.Spark = spark

	-- Overlay container above the status bar for buttons and labels.
	local content = CreateFrame("Frame", nil, bar)
	content:SetAllPoints()
	content:SetFrameLevel(bar:GetFrameLevel() + 2)
	bar.Content = content

	bar.buttons = {
		need = CreateRollButton(content, bar, "need", 1, NEED, "lootroll-toast-icon-need", [[Interface\Buttons\UI-GroupLoot-Dice]], 0),
		greed = CreateRollButton(content, bar, "greed", 2, GREED, "lootroll-toast-icon-greed", [[Interface\Buttons\UI-GroupLoot-Coin]], -1),
		transmog = CreateRollButton(content, bar, "transmog", 4, TRANSMOGRIFICATION or GREED, "lootroll-toast-icon-transmog", [[Interface\Buttons\UI-GroupLoot-Coin]], -1),
		disenchant = CreateRollButton(content, bar, "disenchant", 3, ROLL_DISENCHANT or "Disenchant", nil, [[Interface\Buttons\UI-GroupLoot-DE]], 0),
		pass = CreateRollButton(content, bar, "pass", 0, PASS, "lootroll-toast-icon-pass", [[Interface\Buttons\UI-GroupLoot-Pass]], 1),
	}

	local bind = content:CreateFontString(nil, "OVERLAY")
	bind:SetFont(ns.GetFontFace and ns.GetFontFace() or [[Fonts\FRIZQT__.TTF]], 11, "OUTLINE")
	bar.BindText = bind

	local timeText = content:CreateFontString(nil, "OVERLAY")
	timeText:SetFont(ns.GetFontFace and ns.GetFontFace() or [[Fonts\FRIZQT__.TTF]], 10, "OUTLINE")
	timeText:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	timeText:SetJustifyH("RIGHT")
	timeText:SetTextColor(0.85, 0.85, 0.85)
	bar.TimeText = timeText

	local name = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("LEFT", bind, "RIGHT", 4, 0)
	name:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
	name:SetHeight(16)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	bar.ItemName = name

	bar.voters = {}
	for _, key in ipairs(ROLL_KEYS) do
		bar.voters[key] = {}
	end
	bar.chatVoters = {}
	bar.showTransmog = false
	bar.showDisenchant = false

	ApplySingleBarSize(bar)
	barPool[#barPool + 1] = bar
	return bar
end

local function AcquireBar()
	for _, bar in ipairs(barPool) do
		if not bar:IsShown() then
			return bar
		end
	end
	return CreateRollBar()
end

---------------------------------------------------------------------------
-- Layout and timer loop
---------------------------------------------------------------------------
ApplySingleBarSize = function(bar)
	local width = LootRoll.db.width
	local height = LootRoll.db.height
	local scale = LootRoll.db.scale
	local iconSize = math.max(16, height - 4)
	local btnSize = math.max(16, math.min(34, height - 4))
	bar:SetSize(width, height)
	bar:SetScale(scale)
	if bar.IconButton then
		bar.IconButton:SetSize(iconSize, iconSize)
	end
	if bar.Spark then
		bar.Spark:SetSize(14, height + 6)
	end
	if bar.ItemName then
		bar.ItemName:SetHeight(math.max(14, height - 10))
	end
	if bar.buttons then
		for _, btn in pairs(bar.buttons) do
			btn:SetSize(btnSize, btnSize)
		end
	end
end

LayoutBars = function()
	if not anchor then
		return
	end
	local growUp = LootRoll.db.growUp
	local anchorPoint = growUp and "BOTTOMLEFT" or "TOPLEFT"
	local stepPoint = growUp and "TOPLEFT" or "BOTTOMLEFT"
	local gap = growUp and BAR_GAP or -BAR_GAP
	local prev
	for _, bar in ipairs(activeBars) do
		bar:SetFrameStrata((editPreview and bar.preview) and "LOW" or "DIALOG")
		bar:ClearAllPoints()
		if not prev then
			bar:SetPoint(anchorPoint, anchor, anchorPoint, 0, 0)
		else
			bar:SetPoint(anchorPoint, prev, stepPoint, 0, gap)
		end
		prev = bar
	end
end

ApplyBarSize = function()
	local width = LootRoll.db.width
	local height = LootRoll.db.height
	local scale = LootRoll.db.scale
	if anchor then
		anchor:SetSize(width * scale, height * scale)
	end
	for _, bar in ipairs(barPool) do
		ApplySingleBarSize(bar)
	end
	LayoutBars()
end

local function UpdateBarTimer(bar, left, duration)
	if not duration or duration <= 0 then
		bar.Status:SetMinMaxValues(0, 1)
		bar.Status:SetValue(0)
		bar.Spark:Hide()
		bar.TimeText:SetText("")
		return
	end
	left = math.max(0, math.min(duration, ns.Number(left, 0)))
	local perc = left / duration
	bar.Status:SetMinMaxValues(0, duration)
	bar.Status:SetValue(left)
	local statusWidth = ns.Number(bar.Status:GetWidth(), 0)
	if perc > 0.01 and statusWidth > 0 then
		bar.Spark:ClearAllPoints()
		bar.Spark:SetPoint("CENTER", bar.Status, "LEFT", perc * statusWidth, 0)
		bar.Spark:Show()
	else
		bar.Spark:Hide()
	end
	local secs = left / 1000
	bar.TimeText:SetText(FormatTimeLeft(secs))
	if secs > 0 and secs <= 10 then
		bar.TimeText:SetTextColor(1, 0.35, 0.25)
	else
		bar.TimeText:SetTextColor(0.85, 0.85, 0.85)
	end
end

local function OnTimerUpdate(_, elapsed)
	for i = #activeBars, 1, -1 do
		local bar = activeBars[i]
		if bar.preview then
			bar.previewLeft = (bar.previewLeft or bar.duration) - elapsed * 1000
			if bar.previewLeft <= 0 then
				bar.previewLeft = bar.duration
			end
			UpdateBarTimer(bar, bar.previewLeft, bar.duration)
		elseif bar.rollID then
			local left = ns.Number(GetLootRollTimeLeft(bar.rollID), 0)
			UpdateBarTimer(bar, left, bar.duration)
		end
	end
end

RefreshTimerLoop = function()
	if not updateFrame then
		return
	end
	if #activeBars > 0 then
		ns.SetUpdate(updateFrame, "LootRoll: timer", OnTimerUpdate)
	else
		ns.SetUpdate(updateFrame, "LootRoll: timer", nil)
	end
end

---------------------------------------------------------------------------
-- Roll history sync (C_LootHistory + CHAT_MSG_LOOT)
---------------------------------------------------------------------------
local function ApplyDropInfo(bar, dropInfo)
	if not (bar and dropInfo) then
		return
	end
	bar.hasHistory = true
	for _, key in ipairs(ROLL_KEYS) do
		wipe(bar.voters[key])
	end
	for _, roll in ipairs(dropInfo.rollInfos or {}) do
		local key = RollKeyForState(roll.state)
		if key and not ns.Secret(roll.playerName) and type(roll.playerName) == "string" then
			local color = roll.playerClass and C_ClassColor and C_ClassColor.GetClassColor(roll.playerClass)
			local label = color and color:WrapTextInColorCode(roll.playerName) or roll.playerName
			local num = ns.Number(roll.roll)
			if num and num > 0 then
				label = ("%s (%d)"):format(label, num)
			end
			local list = bar.voters[key]
			list[#list + 1] = label
		end
	end
	for _, key in ipairs(ROLL_KEYS) do
		UpdateButtonCount(bar, key)
	end
end

local function SyncBarFromHistory(bar)
	if not (bar and bar.itemID and C_LootHistory and C_LootHistory.GetAllEncounterInfos and C_LootHistory.GetSortedDropsForEncounter) then
		return
	end
	local encounters = C_LootHistory.GetAllEncounterInfos()
	if type(encounters) ~= "table" or #encounters == 0 then
		return
	end
	local latest = encounters[#encounters]
	local drops = latest and latest.encounterID and C_LootHistory.GetSortedDropsForEncounter(latest.encounterID)
	if type(drops) ~= "table" then
		return
	end
	for _, drop in ipairs(drops) do
		if ItemIDOfLink(drop.itemHyperlink) == bar.itemID then
			ApplyDropInfo(bar, drop)
			return
		end
	end
end

local function FindBarByItem(link)
	local itemID = ItemIDOfLink(link)
	if not itemID then
		return nil
	end
	for _, bar in ipairs(activeBars) do
		if not bar.preview and bar.link and bar.link == link then
			return bar
		end
	end
	for _, bar in ipairs(activeBars) do
		if not bar.preview and bar.itemID == itemID then
			return bar
		end
	end
end

---------------------------------------------------------------------------
-- Roll lifecycle (real rolls & preview)
---------------------------------------------------------------------------
local function PopulateBar(bar, info)
	ClearRollCounts(bar)
	bar.rollID = info.rollID
	bar.duration = info.duration or 60000
	bar.link = info.link
	bar.itemID = ItemIDOfLink(info.link)
	bar.bop = info.bop and true or false
	bar.preview = info.preview and true or false
	bar.previewLeft = info.previewLeft

	bar.Icon:SetTexture(info.texture or 134400)
	local count = ns.Number(info.count, 1)
	bar.StackCount:SetText(count > 1 and tostring(count) or "")
	bar.StackCount:SetShown(count > 1)

	bar.showTransmog = info.canTransmog and true or false
	bar.showDisenchant = info.canDisenchant and true or false

	SetButtonEnabled(bar.buttons.need, info.canNeed, info.reasonNeed)
	if bar.showTransmog then
		SetButtonEnabled(bar.buttons.transmog, true)
	else
		SetButtonEnabled(bar.buttons.greed, info.canGreed, info.reasonGreed)
	end
	if bar.showDisenchant then
		SetButtonEnabled(bar.buttons.disenchant, true)
	else
		SetButtonEnabled(bar.buttons.disenchant, false, info.reasonDisenchant)
	end
	SetButtonEnabled(bar.buttons.pass, true)
	PositionBarControls(bar)

	bar.BindText:SetText(bar.bop and L.LOOTROLL_BOP or L.LOOTROLL_BOE)
	if bar.bop then
		bar.BindText:SetTextColor(1, 0.35, 0.15)
	else
		bar.BindText:SetTextColor(0.35, 0.95, 0.35)
	end

	local r, g, b = QualityColor(info.quality)
	bar.ItemName:SetText(info.name or "")
	bar.ItemName:SetTextColor(r, g, b)
	bar:SetBackdropBorderColor(r, g, b, 1)
	bar.IconBorder:SetBackdropBorderColor(r, g, b, 1)
	bar.Status:SetStatusBarColor(r, g, b, 0.65)

	local initialLeft = info.previewLeft or (info.rollID and not info.preview and ns.Number(GetLootRollTimeLeft(info.rollID))) or bar.duration
	UpdateBarTimer(bar, initialLeft, bar.duration)
	RefreshBarUpgrade(bar)
	bar:Show()
end

local function OpenRoll(rollID, rollTime)
	if not rollID or cancelledRolls[rollID] then
		return
	end
	if activeByRollID[rollID] then
		return
	end
	local texture, name, count, quality, bop, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired, canTransmog =
		GetLootRollItemInfo(rollID)
	if not name then
		return
	end
	local duration = ns.Number(rollTime) or (C_Loot and C_Loot.GetLootRollDuration and ns.Number(C_Loot.GetLootRollDuration(rollID))) or 60000
	local deReason
	if reasonDisenchant and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reasonDisenchant] then
		local raw = _G["LOOT_ROLL_INELIGIBLE_REASON" .. reasonDisenchant]
		deReason = deSkillRequired and raw:format(deSkillRequired) or raw
	end
	local bar = AcquireBar()
	activeBars[#activeBars + 1] = bar
	activeByRollID[rollID] = bar
	PopulateBar(bar, {
		rollID = rollID,
		duration = duration,
		texture = texture,
		name = name,
		count = count,
		quality = quality,
		bop = bop,
		link = GetLootRollItemLink(rollID),
		canNeed = canNeed,
		canGreed = canGreed,
		canDisenchant = canDisenchant,
		canTransmog = canTransmog,
		reasonNeed = reasonNeed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reasonNeed],
		reasonGreed = reasonGreed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reasonGreed],
		reasonDisenchant = deReason,
	})
	SyncBarFromHistory(bar)
	LayoutBars()
	RefreshTimerLoop()
end

local function HideBlizzardGroupLootFrames()
	for i = 1, 4 do
		local frame = _G["GroupLootFrame" .. i]
		if frame and frame.IsShown and frame:IsShown() then
			frame:Hide()
		end
	end
end

local function AdoptActiveRolls()
	if not GetActiveLootRollIDs then
		return
	end
	local ids = GetActiveLootRollIDs()
	if type(ids) ~= "table" then
		return
	end
	for _, rollID in ipairs(ids) do
		local duration = C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(rollID)
		OpenRoll(rollID, duration)
	end
	HideBlizzardGroupLootFrames()
end

---------------------------------------------------------------------------
-- Preview / Test mode (for settings button, /fp würfel, and Edit Mode)
---------------------------------------------------------------------------
local PREVIEW_ITEMS = {
	{
		texture = 135328,
		nameKey = "LOOTROLL_SAMPLE_EPIC",
		quality = 4,
		bop = true,
		count = 1,
		canNeed = true,
		canGreed = true,
		duration = 60000,
		previewLeft = 48000,
		voters = { need = { "|cffc69b6dArthas (84)|r", "|cfff48cbaUther (41)|r" }, pass = { "|cff3fc7ebJaina|r" } },
	},
	{
		texture = 134414,
		nameKey = "LOOTROLL_SAMPLE_RARE",
		quality = 3,
		bop = false,
		count = 2,
		canNeed = false,
		reasonNeed = "LOOTROLL_SAMPLE_INELIGIBLE",
		canGreed = true,
		duration = 60000,
		previewLeft = 32000,
		voters = { greed = { "|cffabd473Sylvanas|r" } },
	},
	{
		texture = 132763,
		nameKey = "LOOTROLL_SAMPLE_UNCOMMON",
		quality = 2,
		bop = false,
		count = 1,
		canNeed = true,
		canGreed = true,
		duration = 60000,
		previewLeft = 9000,
		voters = { greed = { "|cfffff468Valeera|r", "|cffffffffAnduin|r" }, pass = { "|cff0070ddThrall|r" } },
	},
}

local function ClearPreviewBars()
	for i = #activeBars, 1, -1 do
		if activeBars[i].preview then
			RemoveBar(activeBars[i])
		end
	end
end

local function ShowPreviewBars(count)
	ClearPreviewBars()
	local total = count or #PREVIEW_ITEMS
	for i = 1, math.min(total, #PREVIEW_ITEMS) do
		local sample = PREVIEW_ITEMS[i]
		local bar = AcquireBar()
		activeBars[#activeBars + 1] = bar
		PopulateBar(bar, {
			preview = true,
			duration = sample.duration,
			previewLeft = sample.previewLeft,
			texture = sample.texture,
			name = L[sample.nameKey],
			count = sample.count,
			quality = sample.quality,
			bop = sample.bop,
			canNeed = sample.canNeed,
			canGreed = sample.canGreed,
			reasonNeed = sample.reasonNeed and L[sample.reasonNeed],
		})
		for key, list in pairs(sample.voters) do
			for _, label in ipairs(list) do
				bar.voters[key][#bar.voters[key] + 1] = label
			end
			UpdateButtonCount(bar, key)
		end
	end
	LayoutBars()
	RefreshTimerLoop()
end

function LootRoll.TogglePreview()
	if not anchor then
		return
	end
	if previewActive then
		previewActive = false
		if not editPreview then
			ClearPreviewBars()
		end
	else
		previewActive = true
		ShowPreviewBars(#PREVIEW_ITEMS)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function LootRoll:START_LOOT_ROLL(_, rollID, rollTime)
	OpenRoll(rollID, rollTime)
end

function LootRoll:CANCEL_LOOT_ROLL(_, rollID)
	cancelledRolls[rollID] = true
	local bar = activeByRollID[rollID]
	if bar then
		RemoveBar(bar)
	end
end

function LootRoll:CANCEL_ALL_LOOT_ROLLS()
	for i = #activeBars, 1, -1 do
		local bar = activeBars[i]
		if not bar.preview then
			RemoveBar(bar)
		end
	end
end

function LootRoll:LOOT_HISTORY_UPDATE_DROP(_, encounterID, lootListKey)
	if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then
		return
	end
	local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
	if not (info and info.itemHyperlink) then
		return
	end
	local itemID = ItemIDOfLink(info.itemHyperlink)
	if not itemID then
		return
	end
	for _, bar in ipairs(activeBars) do
		if not bar.preview and bar.itemID == itemID then
			ApplyDropInfo(bar, info)
		end
	end
end

function LootRoll:CHAT_MSG_LOOT(_, text)
	if #activeBars == 0 then
		return
	end
	local rollKey, player, link = ParseChatRoll(text)
	if not (rollKey and player and link) then
		return
	end
	local bar = FindBarByItem(link)
	if not bar or bar.hasHistory then
		return
	end
	bar.chatVoters[player] = rollKey
	ApplyChatVoters(bar)
end

function LootRoll:PLAYER_ENTERING_WORLD()
	if active then
		AdoptActiveRolls()
	end
end

---------------------------------------------------------------------------
-- Activation and lifecycle
---------------------------------------------------------------------------
local function DetachBlizzardRolls()
	if GameEvent and GameEvent.UnregisterInternalEvent then
		GameEvent.UnregisterInternalEvent("START_LOOT_ROLL")
	elseif UIParent and UIParent.UnregisterEvent then
		UIParent:UnregisterEvent("START_LOOT_ROLL")
	end
	HideBlizzardGroupLootFrames()
end

local function Activate()
	if active then
		return
	end
	active = true
	DetachBlizzardRolls()
	LootRoll:RegisterEvent("START_LOOT_ROLL")
	LootRoll:RegisterEvent("CANCEL_LOOT_ROLL")
	LootRoll:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
	LootRoll:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
	LootRoll:RegisterEvent("CHAT_MSG_LOOT")
	LootRoll:RegisterEvent("PLAYER_ENTERING_WORLD")
	AdoptActiveRolls()
end

local SCALE_OPTION = {
	key = "scale", type = "slider", name = L.LOOTROLL_SCALE, desc = L.LOOTROLL_SCALE_DESC, parent = "enabled",
	min = 0.7, max = 1.5, step = 0.05, new = true,
	format = function(v)
		return ("%d%%"):format(math.floor(v * 100 + 0.5))
	end,
}
local WIDTH_OPTION = {
	key = "width", type = "slider", name = L.LOOTROLL_WIDTH, desc = L.LOOTROLL_WIDTH_DESC, parent = "enabled",
	min = 240, max = 460, step = 8, new = true,
	format = function(v)
		return ("%d px"):format(v)
	end,
}
local HEIGHT_OPTION = {
	key = "height", type = "slider", name = L.LOOTROLL_HEIGHT, desc = L.LOOTROLL_HEIGHT_DESC, parent = "enabled",
	min = 20, max = 48, step = 2, new = true,
	format = function(v)
		return ("%d px"):format(v)
	end,
}

local function CreateEditOptions()
	local panel = ns.CreatePanel("ForeverPlusLootRollEditOptions", { close = true, movable = true })
	panel.Title:SetText(L.LOOTROLL_TITLE)

	local sliders = { SCALE_OPTION, WIDTH_OPTION, HEIGHT_OPTION }
	local refreshers = {}
	local y = -40
	for index, option in ipairs(sliders) do
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("TOPLEFT", 12, y - 5)
		label:SetText(option.name)
		local slider, refreshSlider = ns.CreateEditSlider(panel, LootRoll, option)
		slider:SetPoint("TOPRIGHT", -56, y)
		slider:SetSize(154, 24)
		refreshers[index] = refreshSlider
		y = y - 30
	end

	local growCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	growCheck:SetPoint("TOPLEFT", 9, y - 2)
	growCheck:SetSize(24, 24)
	growCheck.Text:SetText(L.LOOTROLL_GROW_UP)
	growCheck:SetHitRectInsets(0, -growCheck.Text:GetStringWidth(), 0, 0)
	growCheck:SetScript("OnClick", ns.Measured("LootRoll: Edit Mode growUp", function(self)
		ns.SetOption("LootRoll", "growUp", self:GetChecked())
	end))
	ns.SetEditTooltip(growCheck, L.LOOTROLL_GROW_UP, L.LOOTROLL_GROW_UP_DESC)

	panel:SetSize(350, -y + 38)
	panel.refreshers = refreshers
	panel.growCheck = growCheck
	panel:HookScript("OnShow", ns.Measured("LootRoll: refresh Edit Mode options", function()
		for _, refresh in ipairs(refreshers) do
			refresh()
		end
		growCheck:SetChecked(LootRoll.db.growUp)
	end))
	return panel
end

ShowEditOptions = function(anchorFrame)
	if not ns:IsEditModeActive() then
		return
	end
	editPanel = editPanel or CreateEditOptions()
	editPanel:ClearAllPoints()
	local target = anchorFrame or anchor
	local right = target and ns.Number(target:GetRight(), 0) or 0
	if target and UIParent:GetWidth() - right >= editPanel:GetWidth() + 16 then
		editPanel:SetPoint("TOPLEFT", target, "TOPRIGHT", 12, 8)
	elseif target then
		editPanel:SetPoint("TOPRIGHT", target, "TOPLEFT", -12, 8)
	else
		editPanel:SetPoint("CENTER")
	end
	editPanel:Show()
	editPanel:Raise()
end

EventRegistry:RegisterCallback("EditMode.Exit", ns.Measured("LootRoll: close Edit Mode options", function()
	if editPanel then
		editPanel:Hide()
	end
end), LootRoll)

local function OnEditMode(inEditMode)
	editPreview = inEditMode and true or false
	if not inEditMode and editPanel then
		editPanel:Hide()
	end
	if not anchor then
		return
	end
	anchor:SetShown(inEditMode and LootRoll.db.enabled)
	if inEditMode and LootRoll.db.enabled then
		ShowPreviewBars(2)
	elseif not previewActive then
		ClearPreviewBars()
	else
		LayoutBars()
	end
end

function LootRoll:OnLogin()
	anchor = CreateFrame("Frame", "ForeverPlusLootRollAnchor", UIParent)
	anchor:SetSize(self.db.width * self.db.scale, self.db.height * self.db.scale)
	anchor:SetClampedToScreen(true)
	anchor:Hide()

	updateFrame = CreateFrame("Frame")

	ns:RegisterEditFrame(anchor, "LootRoll", L.LOOTROLL_TITLE, DEFAULT_ANCHOR, OnEditMode, ShowEditOptions)

	if self.db.enabled then
		Activate()
	end
end

function LootRoll:OnOptionChanged(key, value)
	if key == "enabled" then
		if value then
			Activate()
		elseif active then
			-- Keep handling active rolls until /reload so no rolls are dropped and Blizzard's event table stays untainted.
			ns.Print(L.RELOAD_REQUIRED)
		end
		if editPreview and anchor then
			anchor:SetShown(value and true or false)
		end
		if not value and editPanel then
			editPanel:Hide()
		end
	elseif key == "width" or key == "height" or key == "scale" then
		ApplyBarSize()
	elseif key == "growUp" then
		LayoutBars()
	elseif key == "showUpgrade" then
		for _, bar in ipairs(activeBars) do
			RefreshBarUpgrade(bar)
		end
	end
end

function LootRoll.Command()
	if not LootRoll.db.enabled then
		ns.Print(L.LOOTROLL_DISABLED)
		return
	end
	LootRoll.TogglePreview()
end

-- Exposed for unit tests.
LootRoll._activeBars = activeBars
LootRoll._barPool = barPool
LootRoll._ParseChatRoll = ParseChatRoll
LootRoll._ShowEditOptions = ShowEditOptions
LootRoll._GetAnchor = function()
	return anchor
end
LootRoll._GetEditPanel = function()
	return editPanel
end
LootRoll._ResetStateForTests = function()
	ClearPreviewBars()
	for i = #activeBars, 1, -1 do
		RemoveBar(activeBars[i])
	end
	if editPanel then
		editPanel:Hide()
	end
	wipe(cancelledRolls)
	chatRollPatterns = nil
	previewActive = false
	editPreview = false
end

LootRoll.options = {
	{ key = "enabled", type = "toggle", name = L.LOOTROLL_ENABLE, desc = L.LOOTROLL_ENABLE_DESC, new = true },
	SCALE_OPTION,
	WIDTH_OPTION,
	HEIGHT_OPTION,
	{ key = "growUp", type = "toggle", name = L.LOOTROLL_GROW_UP, desc = L.LOOTROLL_GROW_UP_DESC, parent = "enabled", new = true },
	{ key = "showUpgrade", type = "toggle", name = L.LOOTROLL_UPGRADE, desc = L.LOOTROLL_UPGRADE_DESC, parent = "enabled", new = true },
	{ key = "test", type = "button", name = L.LOOTROLL_TEST, text = L.LOOTROLL_TEST_BTN, desc = L.LOOTROLL_TEST_DESC, func = function()
		LootRoll.TogglePreview()
	end },
}

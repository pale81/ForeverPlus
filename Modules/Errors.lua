-- Interface errors: suppress the popup, collect errors behind the minimap's
-- day/night indicator, which glows while unseen errors exist.
local _, ns = ...
local L = ns.L

local Errors = ns:NewModule("Errors", {
	title = L.ERRORS_TITLE,
	order = 6,
	defaults = {
		enabled = true,
		sound = false,
		soundKit = "UI_BNET_TOAST",
		issueButton = true,
	},
	charDefaults = {},
})

local MAX_MENU_ENTRIES = 50

local entries = {}     -- { kind, message, details, time, count, last }
local luaIndex = {}    -- ScriptErrorsFrame error index -> entry
local unseen = 0
local button, window

local SOUNDS = { "UI_BNET_TOAST", "IG_PLAYER_INVITE", "TELL_MESSAGE", "READY_CHECK", "ALARM_CLOCK_WARNING_1", "ALARM_CLOCK_WARNING_2", "MAP_PING" }
local SOUND_THROTTLE = 5
local lastSound = 0

local function PlayErrorSound(force)
	local now = GetTime()
	if not force and (not Errors.db.sound or now - lastSound < SOUND_THROTTLE) then
		return
	end
	lastSound = now
	local kit = SOUNDKIT[Errors.db.soundKit]
	if kit then
		PlaySound(kit, "Master")
	end
end

local function MarkUnseen(quiet)
	if not quiet then
		PlayErrorSound()
	end
	unseen = unseen + 1
	if button and Errors.db.enabled then
		button.Glow:Show()
		button.Pulse:Play()
	end
end

local function MarkSeen()
	unseen = 0
	if button then
		button.Pulse:Stop()
		button.Glow:Hide()
	end
end

local function Safe(text)
	if text == nil then
		return ""
	end
	if issecretvalue and issecretvalue(text) then
		return L.ERRORS_SECRET
	end
	return tostring(text)
end

---------------------------------------------------------------------------
-- Collection
---------------------------------------------------------------------------
-- Lua errors and warnings are recorded by Blizzard's ScriptErrorsFrame even when
-- the popup is disabled; we only follow its data.
local function OnScriptError(frame, message, _, stack)
	local key = ("%s\n%s"):format(message, stack or "")
	local index = (issecretvalue and issecretvalue(key)) and frame:GetCount() or frame.seen[key] or frame:GetCount()
	local data = frame:GetErrorData(index)
	if not data then
		return
	end
	local entry = luaIndex[index]
	if not entry then
		entry = { kind = "lua", index = index }
		luaIndex[index] = entry
		entries[#entries + 1] = entry
	end
	entry.count = data.count
	entry.last = time()
	MarkUnseen()
end

local function AddBlocked(event, addon, func)
	local message = ("%s: %s (%s)"):format(event, Safe(func), Safe(addon))
	for _, entry in ipairs(entries) do
		if entry.kind == "blocked" and entry.message == message then
			entry.count = entry.count + 1
			entry.last = time()
			MarkUnseen()
			return
		end
	end
	entries[#entries + 1] = {
		kind = "blocked",
		message = message,
		details = message,
		count = 1,
		first = date(),
		last = time(),
	}
	MarkUnseen()
end

local function EntryMessage(entry)
	if entry.kind == "lua" then
		local data = ScriptErrorsFrame:GetErrorData(entry.index)
		return data and Safe(data.message) or "?"
	end
	return entry.message
end

local function EntryDetails(entry)
	if entry.kind == "lua" then
		local data = ScriptErrorsFrame:GetErrorData(entry.index)
		if not data then
			return ""
		end
		return ("Message: %s\nTime: %s\nCount: %d\n\nStack:\n%s\n\nLocals:\n%s"):format(
			Safe(data.message), Safe(data.time), data.count or 1, Safe(data.stack), Safe(data.locals))
	end
	return ("Time: %s\nCount: %d\n\n%s"):format(entry.first, entry.count, entry.details)
end

---------------------------------------------------------------------------
-- Detail window with copyable text
---------------------------------------------------------------------------
local function SortedEntries()
	local sorted = {}
	for _, entry in ipairs(entries) do
		sorted[#sorted + 1] = entry
	end
	table.sort(sorted, function(a, b)
		return a.last > b.last
	end)
	return sorted
end

-- The newest errors as text for /fp diagnose: message, count and the first
-- lines of the stack (no locals, they are long).
function Errors.Report(maxEntries)
	local lines = {}
	for index, entry in ipairs(SortedEntries()) do
		if index > (maxEntries or 5) then
			break
		end
		local details = EntryDetails(entry):gsub("\nLocals:.*$", "")
		local shown = {}
		for line in details:gmatch("[^\n]+") do
			shown[#shown + 1] = line
			if #shown >= 12 then
				break
			end
		end
		lines[#lines + 1] = ("#%d %s"):format(index, table.concat(shown, "\n   "))
	end
	return #entries, table.concat(lines, "\n")
end

local function CreateNavButton(parent, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(26, 26)
	b:SetNormalTexture(([[Interface\Buttons\UI-SpellbookIcon-%sPage-Up]]):format(kind))
	b:SetPushedTexture(([[Interface\Buttons\UI-SpellbookIcon-%sPage-Down]]):format(kind))
	b:SetDisabledTexture(([[Interface\Buttons\UI-SpellbookIcon-%sPage-Disabled]]):format(kind))
	b:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	return b
end

local function SelectAll()
	window.EditBox:SetFocus()
	window.EditBox:HighlightText()
end

local function ShowIndex(index)
	local list = window.list
	index = Clamp(index, 1, max(#list, 1))
	window.index = index
	local entry = list[index]
	window.Scroll:SetText(entry and EntryDetails(entry) or L.ERRORS_NONE)
	window.IndexLabel:SetFormattedText("%d / %d", entry and index or 0, #list)
	window.Prev:SetEnabled(index > 1)
	window.Next:SetEnabled(index < #list)
	SelectAll()
end

-- Prepared GitHub issue: an addon cannot send anything or open a browser, so the finished link is shown to copy
-- (Ctrl + C) and paste into the browser. The text is cut so the link stays short enough for the browser.
local ISSUE_URL = "https://github.com/pale81/ForeverPlus/issues/new"
local MAX_URL = 6000

local function UrlEncode(text)
	return (text:gsub("[^%w%-_%.~]", function(char)
		return ("%%%02X"):format(char:byte())
	end))
end

local function IssueUrl(entry)
	local details = EntryDetails(entry):gsub("\nLocals:.*$", "")
	local first = (details:match("[^\n]+") or "?"):sub(1, 90)
	local title = "Lua error: " .. first
	local function Build(text)
		local build = select(2, GetBuildInfo())
		local body = ("**ForeverPlus** %s, client build %s, locale %s\n\n```\n%s\n```\n"):format(ns.version, tostring(build), GetLocale(), text)
		return ("%s?title=%s&body=%s"):format(ISSUE_URL, UrlEncode(title), UrlEncode(body))
	end
	local url = Build(details)
	while #url > MAX_URL and #details > 200 do
		details = details:sub(1, math.floor(#details * 0.8)) .. "\n[...]"
		url = Build(details)
	end
	return url
end

local function CreateWindow()
	local frame = ns.CreatePanel("ForeverPlusErrorFrame", { close = true, movable = true })
	window = frame
	frame:SetSize(560, 400)
	frame:SetPoint("CENTER")
	frame.Title:SetText(L.ERRORS_TITLE)

	-- Navigation row at the top: previous / index / next, copy on the right.
	frame.IndexLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.IndexLabel:SetPoint("TOP", frame, "TOP", 0, -34)
	frame.Prev = CreateNavButton(frame, "Prev")
	frame.Prev:SetPoint("RIGHT", frame.IndexLabel, "LEFT", -6, 0)
	frame.Prev:SetScript("OnClick", function()
		ShowIndex(frame.index - 1)
	end)
	frame.Next = CreateNavButton(frame, "Next")
	frame.Next:SetPoint("LEFT", frame.IndexLabel, "RIGHT", 6, 0)
	frame.Next:SetScript("OnClick", function()
		ShowIndex(frame.index + 1)
	end)

	local copy = CreateFrame("Button", nil, frame)
	copy:SetSize(22, 22)
	copy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
	ns.StyleCopyButton(copy)
	copy:SetScript("OnClick", SelectAll)
	copy:SetScript("OnEnter", function(self)
		ns.SetCopyHot(self, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.ERRORS_COPY)
		GameTooltip_AddNormalLine(GameTooltip, L.ERRORS_COPY_DESC)
		GameTooltip:Show()
	end)
	copy:SetScript("OnLeave", function(self)
		ns.SetCopyHot(self, false)
		GameTooltip_Hide()
	end)

	-- Report as a GitHub issue (option): shows the prepared link to copy.
	local issue = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	issue:SetSize(120, 22)
	issue:SetPoint("RIGHT", copy, "LEFT", -6, 0)
	issue:SetText(L.ERRORS_ISSUE)
	issue:SetScript("OnClick", function()
		local entry = frame.list and frame.list[frame.index]
		if entry then
			ns.ShowEditWindow("ErrorIssue", L.ERRORS_ISSUE_TITLE, IssueUrl(entry), CLOSE, function() end, L.ERRORS_ISSUE_HINT)
		end
	end)
	issue:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.ERRORS_ISSUE)
		GameTooltip_AddNormalLine(GameTooltip, L.ERRORS_ISSUE_DESC)
		GameTooltip:Show()
	end)
	issue:SetScript("OnLeave", GameTooltip_Hide)
	frame.Issue = issue

	local scroll = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -60)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 28)
	ns.AddPanelInset(frame, scroll)
	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 9)
	hint:SetText(L.ERRORS_WINDOW_HINT)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(scroll:GetScrollBox(), scrollBar)
	frame.EditBox = scroll:GetEditBox()
	frame.EditBox:SetFontObject("GameFontHighlightSmall")
	frame.Scroll = scroll
	return frame
end

local function ShowDetails(entry, list)
	if not window then
		CreateWindow()
	end
	window.list = list or SortedEntries()
	local index = 1
	for i, candidate in ipairs(window.list) do
		if candidate == entry then
			index = i
			break
		end
	end
	window.Issue:SetShown(Errors.db.issueButton and true or false)
	window:Show()
	ShowIndex(index)
end

---------------------------------------------------------------------------
-- Menu (newest first)
---------------------------------------------------------------------------
function Errors:ShowMenu(owner)
	MarkSeen()
	local sorted = SortedEntries()

	MenuUtil.CreateContextMenu(owner or button or UIParent, function(_, root)
		root:SetScrollMode(400)
		root:CreateTitle(L.ERRORS_TITLE)
		if #sorted == 0 then
			root:CreateTitle(L.ERRORS_NONE)
			return
		end
		for i = 1, min(#sorted, MAX_MENU_ENTRIES) do
			local entry = sorted[i]
			local message = EntryMessage(entry):gsub("\n.*", "")
			if #message > 90 then
				message = message:sub(1, 87) .. "..."
			end
			local label = ("|cffffd200%s|r  %s |cff999999(x%d)|r"):format(date("%H:%M:%S", entry.last), message, entry.count or 1)
			root:CreateButton(label, function()
				ShowDetails(entry, sorted)
			end)
		end
		root:CreateDivider()
		root:CreateButton(L.ERRORS_CLEAR, function()
			Errors:ClearAll()
		end)
	end)
end

function Errors:ClearAll()
	wipe(entries)
	wipe(luaIndex)
	MarkSeen()
	if window then
		window:Hide()
	end
	if GameTooltip:GetOwner() == button then
		button:GetScript("OnEnter")(button)
	end
end

---------------------------------------------------------------------------
-- Day/night indicator becomes the error button
---------------------------------------------------------------------------
local function CreateButton()
	local diel = MinimapCluster and MinimapCluster.DielFrame
	local anchor = diel or Minimap
	local b = CreateFrame("Button", "ForeverPlusErrorButton", anchor)
	if diel then
		b:SetAllPoints(diel)
	else
		b:SetSize(24, 24)
		b:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
	end
	b:SetFrameLevel(anchor:GetFrameLevel() + 2)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
	-- Round glow matching the circular day/night indicator.
	glow:SetAtlas("GarrLanding-CircleGlow")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.25, 0.15)
	glow:SetPoint("TOPLEFT", b, "TOPLEFT", -8, 8)
	glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 8, -8)
	glow:Hide()
	b.Glow = glow

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.8)
	b.Pulse = pulse

	b:SetScript("OnClick", function(self, mouseButton)
		if IsShiftKeyDown() then
			ReloadUI()
		elseif mouseButton == "RightButton" then
			Errors:ClearAll()
		else
			Errors:ShowMenu(self)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.ERRORS_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, L.ERRORS_COUNT:format(#entries))
		GameTooltip_AddInstructionLine(GameTooltip, L.ERRORS_LIST_HINT)
		GameTooltip_AddInstructionLine(GameTooltip, L.ERRORS_CLEAR_HINT)
		GameTooltip_AddInstructionLine(GameTooltip, L.ERRORS_RELOAD_HINT)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Errors:Apply()
	local enabled = self.db.enabled
	if enabled then
		-- The CVar is the same for every character, so its original value is kept account-wide.
		if ns.db.previousScriptErrors == nil then
			ns.db.previousScriptErrors = self.cdb.previousCVar or GetCVar("scriptErrors")
		end
		SetCVar("scriptErrors", "0")
	elseif ns.db.previousScriptErrors ~= nil then
		SetCVar("scriptErrors", ns.db.previousScriptErrors)
		ns.db.previousScriptErrors = nil
	end
	self.cdb.previousCVar = nil
	button:SetShown(enabled)
	self:ToggleEvent("ADDON_ACTION_BLOCKED", enabled, function(_, event, addon, func)
		AddBlocked(event, addon, func)
	end)
	self:ToggleEvent("ADDON_ACTION_FORBIDDEN", enabled, function(_, event, addon, func)
		AddBlocked(event, addon, func)
	end)
end

function Errors:OnLogin()
	button = CreateButton()
	if ScriptErrorsFrame and ScriptErrorsFrame.DisplayMessageInternal then
		hooksecurefunc(ScriptErrorsFrame, "DisplayMessageInternal", function(frame, message, messageType, stack)
			if self.db.enabled then
				OnScriptError(frame, message, messageType, stack)
			end
		end)
		-- Errors that happened before we were loaded.
		for index = 1, ScriptErrorsFrame:GetCount() do
			if not luaIndex[index] then
				local data = ScriptErrorsFrame:GetErrorData(index)
				local entry = { kind = "lua", index = index, count = data.count, last = time() }
				luaIndex[index] = entry
				entries[#entries + 1] = entry
				MarkUnseen(true)
			end
		end
	end
	self:Apply()
end

function Errors:OnOptionChanged()
	self:Apply()
end

Errors.options = {
	{ key = "enabled", type = "toggle", name = L.ERRORS_ENABLE, desc = L.ERRORS_ENABLE_DESC },
	{ type = "button", name = L.ERRORS_SHOW, text = L.ERRORS_SHOW_BUTTON, func = function()
		Errors:ShowMenu()
	end },
	{ key = "sound", type = "toggle", name = L.ERRORS_SOUND, desc = L.ERRORS_SOUND_DESC, parent = "enabled" },
	{ key = "soundKit", type = "dropdown", name = L.ERRORS_SOUND_KIT, parent = "sound", values = function()
		local values = {}
		for _, key in ipairs(SOUNDS) do
			values[#values + 1] = { key, L["ERRORS_SOUND_" .. key] }
		end
		return values
	end },
	{ key = "issueButton", type = "toggle", name = L.ERRORS_ISSUE_OPTION, desc = L.ERRORS_ISSUE_DESC, parent = "enabled", new = true },
	{ type = "button", name = L.ERRORS_SOUND_TEST, text = L.QUESTS_TEST, func = function()
		PlayErrorSound(true)
	end },
}

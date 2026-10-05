-- Interface errors: suppress the popup, collect errors behind the minimap's
-- day/night indicator, which glows while unseen errors exist.
local _, ns = ...
local L = ns.L

local Errors = ns:NewModule("Errors", {
	title = L.ERRORS_TITLE,
	order = 6,
	defaults = {
		enabled = true,
	},
	charDefaults = {},
})

local MAX_MENU_ENTRIES = 50

local entries = {}     -- { kind, message, details, time, count, last }
local luaIndex = {}    -- ScriptErrorsFrame error index -> entry
local unseen = 0
local button, window

local function MarkUnseen()
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
local function CreateWindow()
	local frame = CreateFrame("Frame", "ForeverPlusErrorFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(560, 380)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText(L.ERRORS_TITLE)
	tinsert(UISpecialFrames, frame:GetName())

	local scroll = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
	scroll:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", frame.InsetBg or frame, "BOTTOMRIGHT", -24, 6)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(scroll:GetScrollBox(), scrollBar)
	frame.EditBox = scroll:GetEditBox()
	frame.EditBox:SetFontObject("GameFontHighlightSmall")
	frame.Scroll = scroll
	frame:Hide()
	return frame
end

local function ShowDetails(entry)
	window = window or CreateWindow()
	local text = EntryDetails(entry)
	window.Scroll:SetText(text)
	window:Show()
	window.EditBox:SetFocus()
	window.EditBox:HighlightText()
end

---------------------------------------------------------------------------
-- Menu (newest first)
---------------------------------------------------------------------------
function Errors:ShowMenu(owner)
	MarkSeen()
	local sorted = {}
	for _, entry in ipairs(entries) do
		sorted[#sorted + 1] = entry
	end
	table.sort(sorted, function(a, b)
		return a.last > b.last
	end)

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
				ShowDetails(entry)
			end)
		end
		root:CreateDivider()
		root:CreateButton(L.ERRORS_CLEAR, function()
			wipe(entries)
			wipe(luaIndex)
			MarkSeen()
		end)
	end)
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

	b:SetScript("OnClick", function(self)
		Errors:ShowMenu(self)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.ERRORS_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, L.ERRORS_COUNT:format(#entries))
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
		if self.cdb.previousCVar == nil then
			self.cdb.previousCVar = GetCVar("scriptErrors")
		end
		SetCVar("scriptErrors", "0")
	elseif self.cdb.previousCVar ~= nil then
		SetCVar("scriptErrors", self.cdb.previousCVar)
		self.cdb.previousCVar = nil
	end
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
				MarkUnseen()
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
}

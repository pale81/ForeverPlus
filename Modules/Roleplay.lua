local _, ns = ...
local L = ns.L
local Roleplay = ns:NewModule("Roleplay", {
	title = L.RP_TITLE, order = 16,
	defaults = { enabled = true, hoverTargetProfile = true, playerPortraitClick = true },
	charDefaults = { shared = false, profile = {} },
})

local FIELDS = {
	{ key = "name", label = L.RP_NAME, bytes = 80 },
	{ key = "occupation", label = L.RP_OCCUPATION, bytes = 80 },
	{ key = "birthplace", label = L.RP_BIRTHPLACE, bytes = 80 },
	{ key = "residence", label = L.RP_RESIDENCE, bytes = 80 },
	{ key = "story", label = L.RP_STORY, bytes = 1100, multiline = true },
}
local BOOK_ICON = [[Interface\Icons\INV_Misc_Book_09]]
local PREFIX = "ForeverPlusRP1"
local SEPARATOR = "\031"
local CHUNK_BYTES, MAX_CHUNKS, TIMEOUT = 220, 9, 8
local HOVER_DELAY, LEAVE_DELAY = 0.2, 0.35
local editor, viewer, targetButton, pending
local hoverTimer, hoverPreview, leaveElapsed
local chatReady, realm
local serial = math.random(0, 0xFFFFFF)
local sendBudget, budgetTime = 10, 0

local function CleanText(value, field)
	if type(value) ~= "string" then return "" end
	value = value:gsub("\r\n?", "\n"):gsub("[%z\001-\008\011-\031\127]", ""):gsub("\t", " ")
	if not field.multiline then value = value:gsub("\n", " ") end
	value = strtrim(value)
	if #value <= field.bytes then return value end
	local last = field.bytes
	-- Keep the whole UTF-8 character or leave it out.
	while last > 0 and value:byte(last + 1) >= 128 and value:byte(last + 1) < 192 do
		last = last - 1
	end
	return strtrim(value:sub(1, last))
end

local function ProfileData(profile)
	local values, hasText = {}, false
	for index, field in ipairs(FIELDS) do
		local value = CleanText(profile[field.key], field)
		values[index] = value
		hasText = hasText or value ~= ""
	end
	if hasText then return table.concat(values, SEPARATOR) end
end

local function ReadProfile(data)
	local ok, decoded = pcall(C_EncodingUtil.DecodeBase64, data)
	if not ok or type(decoded) ~= "string" then return end
	local values = { strsplit(SEPARATOR, decoded) }
	if #values ~= #FIELDS then return end
	local profile, hasText = {}, false
	for index, field in ipairs(FIELDS) do
		if #values[index] > field.bytes then return end
		local value = CleanText(values[index], field)
		profile[field.key] = value
		hasText = hasText or value ~= ""
	end
	return hasText and profile or nil
end

local function PlainText(value)
	return (value:gsub("|", "||"))
end

-- Use realm-qualified names for whispers and for matching incoming senders.
local function Address(name, server)
	if server == "" then server = realm end
	if not server or server == "" then return end
	return name .. "-" .. server:gsub("%s", "")
end

local function Target()
	local player, friendly = UnitIsPlayer("target"), UnitIsFriend("player", "target")
	if ns.Secret(player) or ns.Secret(friendly) or player ~= true or friendly ~= true then return end
	local name, server = UnitFullName("target")
	if ns.Secret(name) or ns.Secret(server) or type(name) ~= "string" or name == "" then return end
	local own = UnitIsUnit("player", "target")
	if not ns.Secret(own) and own == true then return nil, name, true end
	if chatReady then return Address(name, server or ""), name end
end

local function ReserveMessages(count)
	-- A profile can fit in one burst even at the maximum field lengths.
	local now = GetTime()
	sendBudget = math.min(10, sendBudget + now - budgetTime)
	budgetTime = now
	if sendBudget < count then return false end
	sendBudget = sendBudget - count
	return true
end

local function Whisper(target, text)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "WHISPER", target)
	return ok and result == Enum.SendAddonMessageResult.Success
end

local function Reply(target, id)
	local profile = Roleplay.cdb.shared and ProfileData(Roleplay.cdb.profile)
	if not profile then
		if ReserveMessages(1) then Whisper(target, "N:" .. id) end
		return
	end
	local encoded = C_EncodingUtil.EncodeBase64(profile)
	if not encoded then return end
	local count = math.ceil(#encoded / CHUNK_BYTES)
	if count > MAX_CHUNKS or not ReserveMessages(count) then return end
	for index = 1, count do
		local first = (index - 1) * CHUNK_BYTES + 1
		local text = ("P:%s:%d:%d:%s"):format(id, index, count, encoded:sub(first, first + CHUNK_BYTES - 1))
		if not Whisper(target, text) then return end
	end
end

local function Panel(name, width, height)
	local panel = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
	panel:Hide()
	panel:SetSize(width, height)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel.CloseButton:SetScript("OnClick", ns.Measured("Roleplay: close", function() panel:Hide() end))
	tinsert(UISpecialFrames, name)
	ns.FadeIn(panel)
	return panel
end

local function Label(parent, text, x, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(text)
end

local function CreateEditor()
	local panel = Panel("ForeverPlusRoleplayEditor", 424, 454)
	panel:SetPoint("CENTER")
	panel:SetTitle(L.RP_EDIT)
	local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 11, -65)
	inset:SetPoint("BOTTOMRIGHT", -11, 40)

	panel.Fields = {}
	for index, field in ipairs(FIELDS) do
		local y = -13 - (index - 1) * 46
		Label(inset, field.label, 14, y)
		local box
		if field.multiline then
			local input = CreateFrame("ScrollFrame", nil, inset, "ForeverPlusRoleplayStoryInputTemplate")
			input:SetPoint("TOPLEFT", 18, y - 21)
			box = input.EditBox
			box:SetFontObject(GameFontHighlight)
		else
			box = CreateFrame("EditBox", nil, inset, "InputBoxTemplate")
			box:SetPoint("TOPLEFT", 18, y - 16)
			box:SetSize(364, 22)
			box:SetScript("OnEnterPressed", ns.Measured("Roleplay: clear focus", function(self) self:ClearFocus() end))
		end
		box:SetAutoFocus(false)
		box:SetMaxBytes(field.bytes)
		panel.Fields[field.key] = box
	end
	for index, field in ipairs(FIELDS) do
		local box = panel.Fields[field.key]
		box.previousEditBox = panel.Fields[FIELDS[(index - 2) % #FIELDS + 1].key]
		box.nextEditBox = panel.Fields[FIELDS[index % #FIELDS + 1].key]
	end

	local share = CreateFrame("CheckButton", nil, inset, "UICheckButtonTemplate")
	share:SetSize(24, 24)
	share:SetPoint("BOTTOMLEFT", 11, 10)
	share.Text:SetText(L.RP_SHARE)
	share:SetHitRectInsets(0, -share.Text:GetStringWidth(), 0, 0)
	panel.Share = share

	local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	save:SetSize(128, 23)
	save:SetPoint("BOTTOMRIGHT", -12, 10)
	save:SetText(SAVE)
	save:SetScript("OnClick", ns.Measured("Roleplay: save profile", function()
		local profile = {}
		for _, field in ipairs(FIELDS) do
			profile[field.key] = CleanText(panel.Fields[field.key]:GetText(), field)
		end
		Roleplay.cdb.profile = profile
		Roleplay.cdb.shared = share:GetChecked() == true
		panel:Hide()
	end))
	return panel
end

function Roleplay.OpenEditor()
	if not editor then editor = CreateEditor() end
	if editor:IsShown() then editor:Raise() return end
	for _, field in ipairs(FIELDS) do
		local box = editor.Fields[field.key]
		box:SetText(CleanText(Roleplay.cdb.profile[field.key], field))
		box:SetCursorPosition(0)
	end
	editor.Share:SetChecked(Roleplay.cdb.shared)
	editor:SetPortraitToUnit("player")
	editor:Show()
end

local function CancelHoverOpening()
	if hoverTimer then
		hoverTimer:Cancel()
		hoverTimer = nil
	end
end

local function WatchPreview(self, elapsed)
	-- A small grace period lets the pointer cross the gap from the book and back.
	if not targetButton:IsVisible() then
		self:Hide()
	elseif self:IsMouseOver() or targetButton:IsMouseOver() then
		leaveElapsed = 0
	else
		leaveElapsed = leaveElapsed + elapsed
		if leaveElapsed >= LEAVE_DELAY then self:Hide() end
	end
end

local function SetHoverPreview(active)
	hoverPreview, leaveElapsed = active, 0
	ns.SetUpdate(viewer, "Roleplay: hover preview", active and WatchPreview or nil)
end

local function CreateViewer()
	local panel = Panel("ForeverPlusRoleplayViewer", 348, 310)
	local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 11, -65)
	inset:SetPoint("BOTTOMRIGHT", -11, 11)
	local scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 11, -10)
	scroll:SetSize(286, 214)
	scroll:EnableMouseWheel(true)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(286, 214)
	scroll:SetScrollChild(content)
	local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT")
	text:SetWidth(286)
	text:SetJustifyH("LEFT")
	text:SetNonSpaceWrap(true)
	text:SetSpacing(3)
	panel.Text, panel.Scroll, panel.Content = text, scroll, content
	panel:SetScript("OnHide", ns.Measured("Roleplay: close target profile", function()
		pending = nil
		SetHoverPreview(false)
	end))
	return panel
end

local function ShowText(text)
	viewer.Text:SetText(text)
	viewer.Content:SetHeight(math.max(viewer.Scroll:GetHeight(), viewer.Text:GetStringHeight() + 4))
	viewer.Scroll:UpdateScrollChildRect()
	viewer.Scroll:SetVerticalScroll(0)
end

local function ShowProfile(profile)
	local lines = {}
	for _, field in ipairs(FIELDS) do
		local text = CleanText(profile[field.key], field)
		if text ~= "" then
			lines[#lines + 1] = "|cffffd100" .. field.label .. "|r\n" .. PlainText(text)
		end
	end
	ShowText(#lines > 0 and table.concat(lines, "\n\n") or L.RP_EMPTY)
end

local function OpenTargetProfile(preview)
	local address, name, own = Target()
	if not (own or address) then return end
	if not viewer then viewer = CreateViewer() end
	if viewer:IsShown() then return end

	viewer:ClearAllPoints()
	local x = targetButton:GetCenter()
	if x and x * targetButton:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
		viewer:SetPoint("TOPRIGHT", targetButton, "BOTTOMLEFT", -5, -4)
	else
		viewer:SetPoint("TOPLEFT", targetButton, "BOTTOMRIGHT", 5, -4)
	end
	viewer:SetTitle(L.RP_PROFILE .. " – " .. PlainText(name))
	viewer:SetPortraitToUnit("target")
	SetHoverPreview(preview)
	viewer:Show()
	if own then ShowProfile(Roleplay.cdb.profile) return end

	if not ReserveMessages(1) then ShowText(L.RP_SEND_FAILED) return end
	serial = (serial + 1) % 0x1000000
	local request = { address = address, id = ("%06x"):format(serial), parts = {}, received = 0 }
	pending = request
	ShowText(L.RP_LOADING)
	if not Whisper(address, "Q:" .. request.id) then
		pending = nil
		ShowText(L.RP_SEND_FAILED)
		return
	end
	ns.After("Roleplay: request timeout", TIMEOUT, function()
		if pending == request then
			pending = nil
			ShowText(L.RP_NO_REPLY)
		end
	end)
end

function Roleplay:CHAT_MSG_ADDON(_, prefix, message, channel, sender)
	if not self.db.enabled or ns.Secret(prefix) or ns.Secret(message) or ns.Secret(channel) or ns.Secret(sender)
		or prefix ~= PREFIX or channel ~= "WHISPER" or type(message) ~= "string" or #message > 234
		or type(sender) ~= "string" then return end
	local name, server = sender:match("^([^-]+)%-?(.*)$")
	local address = name and Address(name, server)
	if not address then return end

	local id = message:match("^Q:([%da-f]+)$")
	if id and #id == 6 then Reply(address, id) return end

	local request = pending
	if not request or strcmputf8i(address, request.address) ~= 0 then return end
	if message == "N:" .. request.id then
		pending = nil
		ShowText(L.RP_PRIVATE)
		return
	end
	local index, count, chunk = message:match("^P:" .. request.id .. ":([1-9]):([1-9]):([%w+/=]+)$")
	index, count = tonumber(index), tonumber(count)
	if not index or index > count or #chunk > CHUNK_BYTES or (index < count and #chunk ~= CHUNK_BYTES)
		or (request.count and request.count ~= count) or request.parts[index] then return end
	request.count, request.parts[index] = count, chunk
	request.received = request.received + 1
	if request.received == count then
		pending = nil
		local profile = ReadProfile(table.concat(request.parts))
		if profile then ShowProfile(profile) else ShowText(L.RP_NO_REPLY) end
	end
end

local function RefreshTarget()
	if not targetButton then return end
	local address, _, own = Target()
	targetButton:SetShown(Roleplay.db.enabled and (address ~= nil or own == true))
end

function Roleplay:PLAYER_TARGET_CHANGED()
	CancelHoverOpening()
	if viewer then viewer:Hide() end
	RefreshTarget()
end

local function CreateTargetButton()
	local button = CreateFrame("Button", "ForeverPlusRoleplayTargetButton", TargetFrame)
	button:SetSize(22, 22)
	button:SetPoint("LEFT", TargetFrame:GetPortrait(), "RIGHT", 4, 6)
	button:SetFrameLevel(TargetFrame:GetFrameLevel() + 15)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("CENTER")
	icon:SetTexture(BOOK_ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetAllPoints()
	border:SetTexture([[Interface\Buttons\UI-Quickslot2]])
	border:SetTexCoord(0.16, 0.84, 0.16, 0.84)
	button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	button:SetScript("OnClick", ns.Measured("Roleplay: click target book", function()
		CancelHoverOpening()
		if not (viewer and viewer:IsShown()) then
			OpenTargetProfile(false)
		elseif hoverPreview then
			SetHoverPreview(false)
		else
			viewer:Hide()
		end
	end))
	button:SetScript("OnEnter", ns.Measured("Roleplay: hover target book", function(self)
		if Roleplay.db.hoverTargetProfile then
			if viewer and viewer:IsShown() then return end
			CancelHoverOpening()
			hoverTimer = ns.NewTimer("Roleplay: open hover preview", HOVER_DELAY, function()
				hoverTimer = nil
				if self:IsVisible() and self:IsMouseOver() then OpenTargetProfile(true) end
			end)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L.RP_PROFILE)
			GameTooltip:Show()
		end
	end))
	button:SetScript("OnLeave", ns.Measured("Roleplay: leave target book", function(self)
		CancelHoverOpening()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end))
	button:SetScript("OnHide", ns.Measured("Roleplay: hide target book", CancelHoverOpening))
	return button
end

function Roleplay:OnOptionChanged(key)
	if key == "playerPortraitClick" then
		ns:GetModule("Visuals").ApplyPlayerDragon()
		return
	end
	if not self.db.enabled or not self.db.hoverTargetProfile then
		CancelHoverOpening()
		if viewer and (hoverPreview or not self.db.enabled) then viewer:Hide() end
	end
	if key == "hoverTargetProfile" then return end
	if self.db.enabled and not chatReady then
		local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		local status = Enum.RegisterAddonMessagePrefixResult
		chatReady = result == status.Success or result == status.DuplicatePrefix
	end
	self:ToggleEvent("CHAT_MSG_ADDON", self.db.enabled and chatReady)
	self:ToggleEvent("PLAYER_TARGET_CHANGED", self.db.enabled)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", self.db.enabled, RefreshTarget)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", self.db.enabled, RefreshTarget)
	self:ToggleEvent("UNIT_NAME_UPDATE", self.db.enabled, function(_, _, unit)
		if unit == "target" then RefreshTarget() end
	end)
	RefreshTarget()
end

function Roleplay:OnLogin()
	realm = GetNormalizedRealmName()
	if TargetFrame and type(TargetFrame.GetPortrait) == "function" then targetButton = CreateTargetButton() end
	self:OnOptionChanged()
end

Roleplay.options = {
	{ key = "enabled", type = "toggle", name = L.RP_ENABLE, desc = L.RP_ENABLE_DESC, new = true },
	{ key = "hoverTargetProfile", type = "toggle", name = L.RP_HOVER_TARGET, parent = "enabled", new = true },
	{ key = "playerPortraitClick", type = "toggle", name = L.RP_PLAYER_PORTRAIT_CLICK, new = true },
	{ type = "button", name = L.RP_PROFILE, text = L.RP_EDIT, func = Roleplay.OpenEditor },
}

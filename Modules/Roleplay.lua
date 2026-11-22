local _, ns = ...
local L = ns.L
local MSP = ns.RoleplayMSP
local Roleplay = ns:NewModule("Roleplay", {
	title = L.RP_TITLE, order = 16,
	defaults = { enabled = true, hoverTargetProfile = true, playerPortraitClick = true,
		compatibleProfiles = true, profileTooltip = true },
	charDefaults = { shared = false, profile = {} },
})

local FIELDS = {
	{ key = "name", label = L.RP_NAME, bytes = 80 },
	{ key = "occupation", label = L.RP_OCCUPATION, bytes = 80 },
	{ key = "birthplace", label = L.RP_BIRTHPLACE, bytes = 80 },
	{ key = "residence", label = L.RP_RESIDENCE, bytes = 80 },
	{ key = "story", label = L.RP_STORY, bytes = 1100, multiline = true },
}
local MSP_FIELDS = {
	{ key = "name", code = "NA", label = L.RP_NAME, bytes = 256 },
	{ key = "occupation", code = "NT", label = L.RP_OCCUPATION, bytes = 256 },
	{ key = "shortTitle", code = "PX", label = L.RP_SHORT_TITLE, bytes = 120 },
	{ key = "class", code = "RC", label = L.RP_CLASS, bytes = 120 },
	{ key = "race", code = "RA", label = L.RP_RACE, bytes = 120 },
	{ key = "nickname", code = "NI", label = L.RP_NICKNAME, bytes = 120 },
	{ key = "pronouns", code = "PN", label = L.RP_PRONOUNS, bytes = 120 },
	{ key = "house", code = "NH", label = L.RP_HOUSE, bytes = 120 },
	{ key = "age", code = "AG", label = L.RP_AGE, bytes = 120 },
	{ key = "eyes", code = "AE", label = L.RP_EYES, bytes = 120 },
	{ key = "height", code = "AH", label = L.RP_HEIGHT, bytes = 120 },
	{ key = "weight", code = "AW", label = L.RP_WEIGHT, bytes = 120 },
	{ key = "birthplace", code = "HB", label = L.RP_BIRTHPLACE, bytes = 256 },
	{ key = "residence", code = "HH", label = L.RP_RESIDENCE, bytes = 256 },
	{ key = "motto", code = "MO", label = L.RP_MOTTO, bytes = 480 },
	{ key = "currently", code = "CU", label = L.RP_CURRENTLY, bytes = 2048, multiline = true },
	{ key = "ooc", code = "CO", label = L.RP_OOC, bytes = 2048, multiline = true },
	{ key = "glances", code = "PE", label = L.RP_GLANCES, bytes = 4096, multiline = true },
	{ key = "description", code = "DE", label = L.RP_DESCRIPTION, bytes = 16384, multiline = true },
	{ key = "story", code = "HI", label = L.RP_STORY, bytes = 16384, multiline = true },
}
local mspFullQuery = { "?TT" }
for _, field in ipairs(MSP_FIELDS) do mspFullQuery[#mspFullQuery + 1] = "?" .. field.code end
mspFullQuery = table.concat(mspFullQuery, "`")

local BOOK_ICON = [[Interface\Icons\INV_Misc_Book_09]]
local PREFIX = "ForeverPlusRP1"
local SEPARATOR = "\031"
local CHUNK_BYTES, MAX_CHUNKS = 220, 9
local DISPLAY_TIMEOUT, NATIVE_TIMEOUT, MSP_TIMEOUT = 3, 8, 20
local HOVER_DELAY, LEAVE_DELAY = 0.2, 0.35
local editor, viewer, targetButton, pending
local viewerPeer, viewerNative
local hoverTimer, hoverPreview, leaveElapsed
local chatReady, mspReady, realm, regionalNames
local surnameSeparator, realmSeparator = " ", "-"
local serial = math.random(0, 0xFFFFFF)
local sendBudget, mspSendBudget, budgetTime = 10, 20, 0
local peers, peerCount = {}, 0
local CACHE_LIMIT, RETRY_KNOWN, RETRY_UNKNOWN = 128, 30, 300

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

local function StripMarkup(value)
	return (value:gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|[TA][^|]*|[ta]", "")
		:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"):gsub("||", "|")
		:gsub("{col:%x+}", ""):gsub("{/?col}", ""):gsub("{icon:[^}]*}", ""))
end

-- Forever whispers use the regional character name. Addon events can still append a realm.
local function Address(name, qualifier)
	if regionalNames then
		local realmStart = realmSeparator ~= surnameSeparator and name:find(realmSeparator, 1, true)
		if realmStart then name = name:sub(1, realmStart - 1) end
		if name:find(surnameSeparator, 1, true) then return name end
		if name ~= "" and type(qualifier) == "string" and qualifier ~= "" then
			return name .. surnameSeparator .. qualifier
		end
		return
	end
	if qualifier == "" then qualifier = realm end
	if type(qualifier) ~= "string" or qualifier == "" then return end
	return name .. "-" .. qualifier:gsub("[%s.%-]", "")
end

local function UnitAddress(unit)
	if ns.Secret(unit) or type(unit) ~= "string" then return end
	local player, friendly = UnitIsPlayer(unit), UnitIsFriend("player", unit)
	if ns.Secret(player) or ns.Secret(friendly) or player ~= true or friendly ~= true then return end
	local name, server = UnitFullName(unit)
	if ns.Secret(name) or ns.Secret(server) or type(name) ~= "string" or name == "" then return end
	local own = UnitIsUnit("player", unit)
	if ns.Secret(own) then return end
	local address = Address(name, server or "")
	if regionalNames and address then name = address end
	if own == true then return nil, name, true end
	return address, name
end

local function CanUseMSP()
	return mspReady and Roleplay.db.compatibleProfiles
end

local function Target()
	if chatReady or CanUseMSP() then return UnitAddress("target") end
	local _, name, own = UnitAddress("target")
	if own then return nil, name, true end
end

local function PeerKey(address)
	return C_Intl and type(C_Intl.FoldCase) == "function" and C_Intl.FoldCase(address) or address:lower()
end

local function GetPeer(address)
	local key, now = PeerKey(address), GetTime()
	local peer = peers[key]
	if not peer then
		if peerCount >= CACHE_LIMIT then
			local oldestKey, oldestTime
			for candidate, entry in pairs(peers) do
				if entry ~= viewerPeer and (not oldestTime or entry.touched < oldestTime) then
					oldestKey, oldestTime = candidate, entry.touched
				end
			end
			peers[oldestKey] = nil
		else
			peerCount = peerCount + 1
		end
		peer = { address = address }
		peers[key] = peer
	end
	peer.touched = now
	return peer
end

local function ReserveMessages(count)
	-- A profile can fit in one burst even at the maximum field lengths.
	local now = GetTime()
	sendBudget = math.min(10, sendBudget + now - budgetTime)
	mspSendBudget = math.min(20, mspSendBudget + now - budgetTime)
	budgetTime = now
	if sendBudget < count then return false end
	sendBudget = sendBudget - count
	return true
end

local function ReserveMSPReply(count)
	-- Quoting special characters can make a valid profile larger than the native packet budget.
	if count <= 10 then return ReserveMessages(count) end
	local now = GetTime()
	local available = math.min(20, mspSendBudget + now - budgetTime)
	if available < count or not ReserveMessages(10) then return false end
	mspSendBudget = available - count
	return true
end

local function Whisper(target, text)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "WHISPER", target)
	return ok and result == Enum.SendAddonMessageResult.Success
end

local function RequestMSP(peer, full)
	local now = GetTime()
	local retry = peer.mspSummaryRetry
	if full then retry = peer.mspFullRetry end
	if retry and now < retry and (not full or peer.mspAnswered or now < peer.mspUntil) then return end
	if not MSP.Request(peer.address, full and mspFullQuery or "?TT`?PX`?RC", ReserveMessages) then return false end
	if not peer.mspUntil or now >= peer.mspUntil then peer.fragments = {} end
	peer.mspUntil = now + MSP_TIMEOUT
	local nextRequest = now + (peer.mspAnswered and RETRY_KNOWN or RETRY_UNKNOWN)
	peer.mspSummaryRetry = nextRequest
	if full then peer.mspFullRetry = nextRequest end
	return true
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
		pending, viewerPeer, viewerNative = nil, nil, nil
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

local function ShowProfile(profile, fields)
	local lines = {}
	for _, field in ipairs(fields or FIELDS) do
		local text = CleanText(profile[field.key], field)
		if text ~= "" then
			lines[#lines + 1] = "|cffffd100" .. field.label .. "|r\n" .. PlainText(text)
		end
	end
	ShowText(#lines > 0 and table.concat(lines, "\n\n") or L.RP_EMPTY)
end

local function TooltipUnit()
	if GameTooltip:IsForbidden() then return end
	local _, unit = GameTooltip:GetUnit()
	return UnitAddress(unit)
end

local function RefreshProfileTooltip(address)
	if not (Roleplay.db.profileTooltip and GameTooltip:IsShown()) then return end
	local shown = TooltipUnit()
	if shown and strcmputf8i(shown, address) == 0 then ns.RefreshGameTooltip() end
end

local function NewRequest(address)
	if not (chatReady and ReserveMessages(1)) then return end
	serial = (serial + 1) % 0x1000000
	local id = ("%06x"):format(serial)
	if Whisper(address, "Q:" .. id) then
		return { address = address, id = id, parts = {}, received = 0, deadline = GetTime() + NATIVE_TIMEOUT }
	end
end

local function OnProfileTooltip(tooltip)
	if tooltip ~= GameTooltip or not (Roleplay.db.enabled and Roleplay.db.profileTooltip) then return end
	local address, _, own = TooltipUnit()
	local profile = own and Roleplay.cdb.profile
	if address then
		local peer = GetPeer(address)
		if CanUseMSP() then
			RequestMSP(peer, false)
		elseif chatReady then
			local now = GetTime()
			local waiting = pending and pending.address == address and pending.deadline and now < pending.deadline
			if not waiting and (not peer.nativeRetry or now >= peer.nativeRetry) then
				peer.nativeProbe = NewRequest(address)
				if peer.nativeProbe then
					peer.nativeRetry = now + (peer.nativeAnswered and RETRY_KNOWN or RETRY_UNKNOWN)
				end
			end
		end
		profile = peer.native or (CanUseMSP() and peer.msp)
	end
	if not profile then return end
	local name = CleanText(profile.name, MSP_FIELDS[1])
	local title = CleanText(profile.occupation, MSP_FIELDS[2])
	if title == "" or title == name then
		title = CleanText(profile.shortTitle, MSP_FIELDS[3])
		if title == "" or title == name or name:sub(1, #title + 1) == title .. " " then
			title = CleanText(profile.class, MSP_FIELDS[4])
		end
	end
	if name ~= "" then tooltip:AddLine(PlainText(name), 1, 0.82, 0, true) end
	if title ~= "" and title ~= name then tooltip:AddLine(PlainText(title), 1, 1, 1, true) end
end

local function ShowMSPProfile(peer)
	if CanUseMSP() and peer.msp and next(peer.msp) then
		ShowProfile(peer.msp, MSP_FIELDS)
		return true
	end
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

	local peer = GetPeer(address)
	viewerPeer, viewerNative = peer, nil
	local request = NewRequest(address) or { address = address }
	pending = request
	local mspResult
	if CanUseMSP() then mspResult = RequestMSP(peer, true) end
	if ShowMSPProfile(peer) then return end
	if not request.id and (not CanUseMSP() or mspResult == false) then
		pending = nil
		ShowText(L.RP_SEND_FAILED)
		return
	end
	ShowText(L.RP_LOADING)
	-- Stop showing the loading message while the transports can still deliver a reply.
	ns.After("Roleplay: profile loading status", DISPLAY_TIMEOUT, function()
		if viewerPeer ~= peer or pending ~= request then return end
		if not viewerNative and not (CanUseMSP() and peer.msp and next(peer.msp)) then ShowText(L.RP_NO_REPLY) end
	end)
end

local function ReceiveNative(message, address)
	if not chatReady or #message > 234 then return end
	local id = message:match("^Q:([%da-f]+)$")
	if id and #id == 6 then Reply(address, id) return end

	local peer = peers[PeerKey(address)]
	if not peer then return end
	local responding = message:match("^[NP]:(%x%x%x%x%x%x)")
	local request = pending
	local forViewer = responding and request and responding == request.id and viewerPeer == peer
	if not forViewer then request = peer.nativeProbe end
	if not request or responding ~= request.id or GetTime() >= request.deadline then return end
	local isPrivate = message == "N:" .. request.id
	local index, count, chunk = message:match("^P:" .. request.id .. ":([1-9]):([1-9]):([%w+/=]+)$")
	index, count = tonumber(index), tonumber(count)
	local profile
	if not isPrivate then
		if not index or index > count or #chunk > CHUNK_BYTES or (index < count and #chunk ~= CHUNK_BYTES)
			or (request.count and request.count ~= count) or request.parts[index] then return end
		request.count, request.parts[index] = count, chunk
		request.received = request.received + 1
		if request.received ~= count then return end
		profile = ReadProfile(table.concat(request.parts))
	end
	peer.native, peer.nativeAnswered, peer.nativeRetry = profile, true, GetTime() + RETRY_KNOWN
	if forViewer then
		pending = nil
		viewerNative = profile ~= nil
		if profile then
			ShowProfile(profile)
		elseif not ShowMSPProfile(peer) then
			ShowText(isPrivate and L.RP_PRIVATE or L.RP_NO_REPLY)
		end
	else
		peer.nativeProbe = nil
	end
	RefreshProfileTooltip(address)
end

local nativeCodes = { name = "NA", occupation = "NT", birthplace = "HB", residence = "HH", story = "HI" }
local function CanPublishMSP(profile)
	return Roleplay.db.enabled and CanUseMSP() and Roleplay.cdb.shared and Roleplay.cdb.profile == profile
		and not rawget(_G, "msp_RPAddOn")
end

local function LocalMSPFields(profile)
	local fields = {}
	for _, field in ipairs(FIELDS) do
		local text = profile[field.key]
		local value = type(text) == "string" and CleanText(StripMarkup(text):gsub("`", "'"), field) or ""
		if value ~= "" then fields[nativeCodes[field.key]] = value end
	end
	if not next(fields) then return end
	fields.VA, fields.VP = "ForeverPlus/" .. ns.version, "3"
	return fields
end

local function ReceiveMSP(message, logged, address)
	if not CanUseMSP() then return end
	local peer = peers[PeerKey(address)]
	local awaiting = peer and peer.mspUntil and GetTime() < peer.mspUntil
	local payload = MSP.Packet(message, logged, awaiting and peer.fragments)
	if not payload then return end
	local requests, fields = MSP.Commands(payload, logged)
	local own = Roleplay.cdb.profile
	if next(requests) and CanPublishMSP(own) then
		local ownFields = LocalMSPFields(own)
		if ownFields then
			MSP.Reply(address, requests, ownFields, ReserveMSPReply, function() return CanPublishMSP(own) end)
		end
	end
	if not (awaiting and next(fields)) then return end
	local profile = peer.msp or {}
	local changed = false
	for _, field in ipairs(MSP_FIELDS) do
		if fields[field.code] then
			local value = CleanText(StripMarkup(fields[field.code]), field)
			if value == "" then value = nil end
			changed = changed or profile[field.key] ~= value
			profile[field.key] = value
		end
	end
	peer.msp, peer.mspAnswered = profile, true
	local nextRequest = GetTime() + RETRY_KNOWN
	peer.mspSummaryRetry = nextRequest
	if peer.mspFullRetry then peer.mspFullRetry = nextRequest end
	if changed then
		if viewerPeer == peer and not viewerNative then
			if not ShowMSPProfile(peer) then ShowText(L.RP_NO_REPLY) end
		end
		RefreshProfileTooltip(address)
	end
end

function Roleplay:CHAT_MSG_ADDON(event, prefix, message, channel, sender)
	if not self.db.enabled or ns.Secret(prefix) or ns.Secret(message) or ns.Secret(channel) or ns.Secret(sender)
		or (prefix ~= PREFIX and prefix ~= MSP.prefix) or channel ~= "WHISPER"
		or type(message) ~= "string" or type(sender) ~= "string" or #sender > 128 then return end
	local name, server
	if regionalNames then name = sender else name, server = sender:match("^([^-]+)%-?(.*)$") end
	local address = name and Address(name, server)
	if not address then return end
	local logged = event == "CHAT_MSG_ADDON_LOGGED"
	if prefix == MSP.prefix then
		ReceiveMSP(message, logged, address)
	elseif not logged then
		ReceiveNative(message, address)
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
	if key == "profileTooltip" then
		ns.RefreshGameTooltip()
		return
	end
	if key == "compatibleProfiles" then
		for _, peer in pairs(peers) do
			peer.msp, peer.mspUntil, peer.fragments = nil, nil, nil
			peer.mspAnswered, peer.mspSummaryRetry, peer.mspFullRetry = nil, nil, nil
		end
		if viewerPeer and not viewerNative then viewer:Hide() end
	end
	if self.db.enabled and not chatReady then
		local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		local status = Enum.RegisterAddonMessagePrefixResult
		chatReady = result == status.Success or result == status.DuplicatePrefix
	end
	if self.db.enabled and self.db.compatibleProfiles and not mspReady and type(C_ChatInfo.SendAddonMessageLogged) == "function" then
		local result = C_ChatInfo.RegisterAddonMessagePrefix(MSP.prefix)
		local status = Enum.RegisterAddonMessagePrefixResult
		mspReady = result == status.Success or result == status.DuplicatePrefix
	end
	local useMSP = self.db.enabled and CanUseMSP()
	self:ToggleEvent("CHAT_MSG_ADDON", self.db.enabled and (chatReady or useMSP))
	self:ToggleEvent("CHAT_MSG_ADDON_LOGGED", useMSP, self.CHAT_MSG_ADDON)
	self:ToggleEvent("PLAYER_TARGET_CHANGED", self.db.enabled)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", self.db.enabled, RefreshTarget)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", self.db.enabled, RefreshTarget)
	self:ToggleEvent("UNIT_NAME_UPDATE", self.db.enabled, function(_, _, unit)
		if unit == "target" then RefreshTarget() end
	end)
	RefreshTarget()
	if key == "enabled" or key == "compatibleProfiles" then ns.RefreshGameTooltip() end
end

function Roleplay:OnLogin()
	realm = GetNormalizedRealmName()
	regionalNames = type(RegionalUniqueNamesEnabled) == "function" and RegionalUniqueNamesEnabled()
	local separators = Constants and Constants.CharacterNameSeparatorConsts
	if separators then
		surnameSeparator = separators.CHARACTERNAME_SURNAME_SEPARATOR or surnameSeparator
		realmSeparator = separators.CHARACTERNAME_REALMNAME_SEPARATOR or realmSeparator
	end
	if TargetFrame and type(TargetFrame.GetPortrait) == "function" then targetButton = CreateTargetButton() end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Measured("Roleplay: profile tooltip", OnProfileTooltip))
	self:OnOptionChanged()
end

Roleplay.options = {
	{ key = "enabled", type = "toggle", name = L.RP_ENABLE, desc = L.RP_ENABLE_DESC, new = true },
	{ key = "hoverTargetProfile", type = "toggle", name = L.RP_HOVER_TARGET, parent = "enabled", new = true },
	{ key = "compatibleProfiles", type = "toggle", name = L.RP_COMPATIBILITY, desc = L.RP_COMPATIBILITY_DESC, parent = "enabled" },
	{ key = "profileTooltip", type = "toggle", name = L.RP_TOOLTIP, parent = "enabled" },
	{ key = "playerPortraitClick", type = "toggle", name = L.RP_PLAYER_PORTRAIT_CLICK, new = true },
	{ type = "button", name = L.RP_PROFILE, text = L.RP_EDIT, func = Roleplay.OpenEditor },
}

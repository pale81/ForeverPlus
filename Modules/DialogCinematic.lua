-- The separate subtitles for quest and gossip windows with the reader set to voice only.
local _, ns = ...
local Cinematic = {}
ns.DialogCinematic = Cinematic

local styleCommands = { none = "voice", minimal = "small", classic = "large", subtitle = "subtitles", dialogueui = "dialogueui" }

local function PlayerStyle(spoken)
	local ok, style = pcall(spoken.GetPlayerStyle, spoken)
	return ok and style or nil
end

function Cinematic.Configure(enabled, db)
	if not enabled and not db.spokenStyleBeforeCinematic then return false end
	local spoken = _G.Spoken
	if type(spoken) ~= "table" or type(spoken.GetPlayerStyle) ~= "function" or type(spoken.IsPlaying) ~= "function"
		or type(spoken.GetNowPlaying) ~= "function" then
		return false
	end
	local style = PlayerStyle(spoken)
	if not styleCommands[style] then return false end
	local command = SlashCmdList and SlashCmdList.SPOKEN
	if enabled then
		if style == "none" then return true end
		if type(command) == "function" and pcall(command, "style voice") and PlayerStyle(spoken) == "none" then
			db.spokenStyleBeforeCinematic = style
			return true
		end
	elseif db.spokenStyleBeforeCinematic then
		local restore = styleCommands[db.spokenStyleBeforeCinematic]
		if style == "none" and restore then
			if type(command) ~= "function" or not pcall(command, "style " .. restore) then return false end
			if PlayerStyle(spoken) == "none" then return false end
		end
		db.spokenStyleBeforeCinematic = nil
	end
	return false
end

local function ScrollSubtitle(frame, delta)
	local offset = frame:GetVerticalScroll() - delta * 32
	offset = math.max(0, math.min(offset, frame.range))
	frame:SetVerticalScroll(offset)
	frame.More:SetShown(offset < frame.range - 1)
end

local function CreateSubtitle(parent)
	local frame = CreateFrame("ScrollFrame", "ForeverPlusDialogSubtitles", parent)
	frame:SetPoint("BOTTOM", parent, "TOP", 0, 18)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", ns.Measured("Dialog: scroll subtitles", ScrollSubtitle))
	frame.Back = frame:CreateTexture(nil, "BACKGROUND")
	frame.Back:SetAllPoints()
	frame.Back:SetColorTexture(0, 0, 0, 0.62)
	frame.More = frame:CreateTexture(nil, "OVERLAY")
	frame.More:SetTexture([[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up]])
	frame.More:SetPoint("BOTTOMRIGHT", -3, 2)
	frame.More:SetSize(16, 16)
	frame.Body = CreateFrame("Frame", nil, frame)
	frame:SetScrollChild(frame.Body)
	frame.Text = frame.Body:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	frame.Text:SetPoint("TOP", 0, -6)
	frame.Text:SetJustifyH("CENTER")
	frame.Text:SetNonSpaceWrap(true)
	frame.Text:SetShadowOffset(1, -1)
	frame:Hide()
	return frame
end

function Cinematic.ShowSubtitle(parent, text)
	local frame = parent.Subtitles
	if not text or text == "" then
		if frame then frame:Hide() end
		return
	end
	if not frame then
		frame = CreateSubtitle(parent)
		parent.Subtitles = frame
	end
	local width = math.max(200, math.min(610, ns.Number(UIParent:GetWidth(), 640) - 40))
	local offset = frame.text == text and frame:GetVerticalScroll() or 0
	frame.text = text
	frame.Body:SetWidth(width)
	frame.Text:SetWidth(width - 30)
	frame.Text:SetText(text)
	local full = frame.Text:GetStringHeight() + 12
	local visible = math.min(116, full)
	frame.Body:SetHeight(full)
	frame:SetSize(width, visible)
	frame.range = full - visible
	frame:Show()
	frame:SetVerticalScroll(math.min(offset, frame.range))
	ScrollSubtitle(frame, 0)
end

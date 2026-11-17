-- The experimental presentation for quest and gossip windows: voice only in the reader,
-- separate subtitles, and a temporary animated overlay inside the game's target portrait.
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

local overlay, playing
local TALK_ANIMATION = 60
local function Animate(self, elapsed)
	self.clock = self.clock + elapsed
	if self.clock < self.nextCheck then return end
	self.nextCheck = self.clock + 0.15
	local model = self.Head
	if ns.Number(model:GetModelFileID(), 0) <= 0 then return end
	if self.ready then
		model:SetAnimation(TALK_ANIMATION)
	else
		model:SetPortraitZoom(1)
		model:SetModelScale(1)
		model:SetAnimation(TALK_ANIMATION)
		model:SetAlpha(1)
		self.Back:Show()
		self.ready = true
	end
	self.nextCheck = self.clock + 2
end

function Cinematic.StopPortrait()
	if playing then
		playing = nil
		overlay:Hide()
		ns.SetUpdate(overlay, "Dialog: talking portrait", nil)
		overlay.Head:ClearModel()
	end
end

local function CreateOverlay(portrait, width, height)
	local container = portrait:GetParent()
	local frame = CreateFrame("Frame", "ForeverPlusDialogTargetPortrait", container)
	frame:Hide()
	frame:SetAllPoints(portrait)
	frame:EnableMouse(false)
	frame.Back = frame:CreateTexture(nil, "BACKGROUND")
	frame.Back:SetAllPoints()
	frame.Back:SetColorTexture(0.025, 0.025, 0.03, 1)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	frame.Back:AddMaskTexture(mask)
	local head = CreateFrame("PlayerModel", nil, frame)
	head:SetPoint("CENTER")
	-- A model cannot take a texture mask. Keep its viewport inside the round portrait.
	head:SetSize(width * 0.70, height * 0.70)
	head:EnableMouse(false)
	frame.Head = head
	return frame
end

local function StartPortrait(clip)
	local portrait = TargetFrame:GetPortrait()
	if not portrait or not portrait:IsVisible() then return end
	if not overlay then
		local width, height = portrait:GetSize()
		width, height = ns.Number(width, 0), ns.Number(height, 0)
		if width <= 0 or height <= 0 then return end
		overlay = CreateOverlay(portrait, width, height)
	end
	if not overlay.Head:SetUnit("target", false) then return end
	playing = clip
	overlay.clock, overlay.nextCheck, overlay.ready = 0, 0, false
	overlay.Head:SetAlpha(0)
	overlay.Back:Hide()
	overlay:Show()
	ns.SetUpdate(overlay, "Dialog: talking portrait", Animate)
end

function Cinematic.UpdatePortrait(clip, guid)
	if not clip or not guid or InCombatLockdown()
		or not TargetFrame or type(TargetFrame.GetPortrait) ~= "function" then
		Cinematic.StopPortrait()
		return
	end
	local target = UnitGUID("target")
	if ns.Secret(target) or target ~= guid then
		Cinematic.StopPortrait()
	elseif playing ~= clip then
		Cinematic.StopPortrait()
		local ok = pcall(StartPortrait, clip)
		if not ok then Cinematic.StopPortrait() end
	end
end

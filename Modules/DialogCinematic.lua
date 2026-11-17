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
local portraitStatus = "idle"
local TALK_ANIMATION = 60

function Cinematic.PortraitStatus()
	return portraitStatus
end

local function LoadFallback(frame)
	local model = frame.Head
	model:ClearModel()
	if frame.displayID then
		model:SetDisplayInfo(frame.displayID)
	elseif frame.creatureID then
		model:SetCreature(frame.creatureID)
	else
		return false
	end
	return true
end

local function Animate(self, elapsed)
	if self.endAt and GetTime() >= self.endAt then
		Cinematic.StopPortrait("finished")
		return
	end
	self.clock = self.clock + elapsed
	if self.clock < self.nextCheck then return end
	self.nextCheck = self.clock + 0.15
	local model = self.Head
	if ns.Number(model:GetModelFileID(), 0) <= 0 then
		if not self.fallback and self.clock >= 0.4 then
			self.fallback = true
			if not LoadFallback(self) then Cinematic.StopPortrait("no model") end
		elseif self.clock >= 2 then
			Cinematic.StopPortrait("model did not load")
		end
		return
	end
	if not self.ready then
		model:SetPortraitZoom(1)
		model:SetModelScale(1)
		model:SetAlpha(1)
		self.Back:Show()
		self.ready = true
		portraitStatus = "animating"
	end
	model:SetAnimation(TALK_ANIMATION)
	self.nextCheck = self.clock + 2
end

function Cinematic.StopPortrait(status)
	portraitStatus = status or "idle"
	if playing then
		playing = nil
		overlay:Hide()
		ns.SetUpdate(overlay, "Dialog: talking portrait", nil)
		overlay.Head:ClearModel()
	end
end

local function CreateOverlay(portrait)
	local frame = CreateFrame("Frame", "ForeverPlusDialogTargetPortrait", TargetFrame)
	frame:Hide()
	frame:SetFrameLevel(TargetFrame:GetFrameLevel() + 10)
	-- Anchor by reference. Reading a protected portrait's dimensions can fail.
	frame:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, -2)
	frame:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 2)
	frame:EnableMouse(false)
	frame.Back = frame:CreateTexture(nil, "BACKGROUND")
	frame.Back:SetAllPoints()
	frame.Back:SetColorTexture(0.025, 0.025, 0.03, 1)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	frame.Back:AddMaskTexture(mask)
	local head = CreateFrame("DressUpModel", nil, frame)
	-- A model cannot take a texture mask. Keep its viewport inside the round portrait.
	head:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	head:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	head:EnableMouse(false)
	frame.Head = head
	return frame
end

local function StartPortrait(clip, guid, interaction)
	local portrait = TargetFrame:GetPortrait()
	if not portrait then return "no target portrait" end
	if not overlay then
		overlay = CreateOverlay(portrait)
	end
	playing = clip
	local spec = clip.present and clip.present.portrait
	local kind, creatureID = ns.GuidParts(guid)
	overlay.creatureID = kind == "Creature" and creatureID or nil
	overlay.displayID = spec and spec.kind == "model" and ns.Number(spec.displayID) or nil
	overlay.endAt = ns.Number(clip.spokenAt) or false
	overlay.fallback = false
	overlay.clock, overlay.nextCheck, overlay.ready = 0, 0, false
	overlay.Head:SetAlpha(0)
	overlay.Back:Hide()
	overlay:Show()
	-- The client can refuse SetUnit on a restricted unit. The recorded display or creature
	-- is safe to load here because the caller has already confirmed the speaker is the target.
	local ok, accepted = pcall(overlay.Head.SetUnit, overlay.Head, interaction or "target", false)
	if not ok or accepted == false then
		overlay.fallback = true
		if not LoadFallback(overlay) then
			Cinematic.StopPortrait("unit refused and no model")
			return portraitStatus
		end
	end
	ns.SetUpdate(overlay, "Dialog: talking portrait", function(frame, elapsed)
		local animated, err = pcall(Animate, frame, elapsed)
		if not animated then Cinematic.StopPortrait("model animation: " .. tostring(err)) end
	end)
	return "loading"
end

function Cinematic.UpdatePortrait(clip, guid, interaction)
	if InCombatLockdown() then return Cinematic.StopPortrait("combat") end
	if not TargetFrame or type(TargetFrame.GetPortrait) ~= "function" then
		return Cinematic.StopPortrait("no target frame")
	end
	local target = UnitGUID("target")
	local isTarget = guid and not ns.Secret(target) and target == guid
	if not isTarget and interaction and (not guid or ns.Secret(target) or target == nil) then
		local same = UnitIsUnit(interaction, "target")
		isTarget = not ns.Secret(same) and same == true
	end
	if not isTarget then
		Cinematic.StopPortrait("speaker is not the target")
	elseif playing ~= clip then
		Cinematic.StopPortrait()
		local ok, status = pcall(StartPortrait, clip, guid or target, interaction)
		if ok then
			portraitStatus = status
		else
			Cinematic.StopPortrait("model setup: " .. tostring(status))
		end
	end
end

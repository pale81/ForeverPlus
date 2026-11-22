-- Use the narrator's supported portrait renderer in our own bubble.
local _, ns = ...
local Portrait = {}
ns.DialogPortrait = Portrait

-- The bronze baked into Media/Bubble/bubble.tga by tools/build_bubble.py.
local PLAYER_BORDER = { 214 / 255, 168 / 255, 104 / 255 }
Portrait.PLAYER_BORDER = PLAYER_BORDER

local function CreateCover(holder)
	-- A model cannot take a texture mask. Cover its square corners above the model
	-- instead of shrinking the viewport and cutting off the speaker's beard.
	local cover = CreateFrame("Frame", nil, holder)
	cover:SetAllPoints(holder)
	cover:EnableMouse(false)
	local cutout = cover:CreateMaskTexture()
	cutout:SetAllPoints()
	cutout:SetTexture([[Interface\AddOns\ForeverPlus\Media\Bubble\portrait-cutout]],
		"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	cover.Fill = cover:CreateTexture(nil, "ARTWORK", nil, 0)
	cover.Fill:SetAllPoints()
	cover.Fill:AddMaskTexture(cutout)
	cover.Rim = cover:CreateTexture(nil, "ARTWORK", nil, 1)
	cover.Rim:SetAllPoints()
	cover.Rim:AddMaskTexture(cutout)
	local round = cover:CreateMaskTexture()
	round:SetAllPoints()
	round:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	cover.Rim:AddMaskTexture(round)
	cover:Hide()
	return cover
end

local function UpdateColors(holder)
	local border = holder.dark and ns.PANEL_BORDER or PLAYER_BORDER
	if holder.Rim then holder.Rim:SetColorTexture(unpack(border)) end
	if not holder.Cover then return end
	holder.Cover.Rim:SetColorTexture(unpack(border))
	if holder.dark then
		holder.Cover.Fill:SetColorTexture(0.08, 0.08, 0.1, 1)
	else
		holder.Cover.Fill:SetColorTexture(14 / 255, 13 / 255, 17 / 255, 1)
	end
end

function Portrait.Stop(holder)
	if not holder then return end
	local model, renderer = holder.talkingModel, holder.renderer
	holder.talkingModel, holder.renderer, holder.clip = nil, nil, nil
	holder.Face:Show()
	if holder.Cover then holder.Cover:Hide() end
	if holder.Scene then ns.SetUpdate(holder.Scene, "Dialog: portrait loading", nil) end
	if model then
		pcall(renderer.Release, model)
		model:Hide()
	end
end

function Portrait.Update(holder, clip, enabled)
	UpdateColors(holder)
	if not enabled or not clip or clip.textOnly then
		Portrait.Stop(holder)
		return
	end
	if holder.clip == clip or holder.failedClip == clip then return end
	Portrait.Stop(holder)
	local spoken, spec = _G.Spoken, clip.present and clip.present.portrait
	if type(spoken) ~= "table" or type(spoken.GetPortraitRenderer) ~= "function" or type(spec) ~= "table"
		or spec.kind ~= "model" or ns.Number(spec.creatureID, 0) <= 0 then return end
	local ok, renderer = pcall(spoken.GetPortraitRenderer, spoken, "model")
	if not ok or type(renderer) ~= "table" or type(renderer.Acquire) ~= "function"
		or type(renderer.Update) ~= "function" or type(renderer.Release) ~= "function" then return end
	if not holder.Scene then
		holder.Scene = CreateFrame("Frame", nil, holder)
		holder.Scene:SetPoint("CENTER")
		holder.Scene:SetSize(holder.Face:GetWidth(), holder.Face:GetHeight())
	end
	local acquired, model = pcall(renderer.Acquire, holder.Scene, clip)
	if not acquired or not model then return end
	holder.talkingModel, holder.renderer, holder.clip = model, renderer, clip
	if not holder.Cover then holder.Cover = CreateCover(holder) end
	holder.Cover:SetFrameLevel(model:GetFrameLevel() + 1)
	UpdateColors(holder)
	-- The renderer owns its model and animation scripts. Observe loading from our own
	-- frame, so its secure script hooks remain intact across release and reuse.
	model:SetAlpha(0)
	local updated = pcall(renderer.Update, model, clip, spec)
	if not updated then
		holder.failedClip = clip
		Portrait.Stop(holder)
		return
	end
	local age, tick = 0, 0
	ns.SetUpdate(holder.Scene, "Dialog: portrait loading", function(_, elapsed)
		age, tick = age + elapsed, tick + elapsed
		if tick < 0.1 then return end
		tick = 0
		local loaded, file = pcall(model.GetModelFileID, model)
		if loaded and ns.Number(file, 0) > 0 then
			holder.Face:Hide()
			model:SetAlpha(1)
			holder.Cover:Show()
			ns.SetUpdate(holder.Scene, "Dialog: portrait loading", nil)
			return
		elseif age < 2 then
			return
		end
		holder.failedClip = clip
		Portrait.Stop(holder)
	end)
end

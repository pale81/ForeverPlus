-- Use the narrator's supported portrait renderer in our own bubble.
local _, ns = ...
local Portrait = {}
ns.DialogPortrait = Portrait

function Portrait.Stop(holder)
	if not holder then return end
	local model, renderer = holder.talkingModel, holder.renderer
	holder.talkingModel, holder.renderer, holder.clip = nil, nil, nil
	holder.Face:Show()
	if holder.Scene then ns.SetUpdate(holder.Scene, "Dialog: portrait loading", nil) end
	if model then
		pcall(renderer.Release, model)
		model:Hide()
	end
end

function Portrait.Update(holder, clip, enabled)
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
	-- Models cannot take a texture mask. Keep the viewport inside the round face.
	if not holder.Scene then
		holder.Scene = CreateFrame("Frame", nil, holder)
		holder.Scene:SetPoint("CENTER")
		holder.Scene:SetSize(holder.Face:GetWidth() * 0.7, holder.Face:GetHeight() * 0.7)
	end
	local acquired, model = pcall(renderer.Acquire, holder.Scene, clip)
	if not acquired or not model then return end
	holder.talkingModel, holder.renderer, holder.clip = model, renderer, clip
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
			ns.SetUpdate(holder.Scene, "Dialog: portrait loading", nil)
			return
		elseif age < 2 then
			return
		end
		holder.failedClip = clip
		Portrait.Stop(holder)
	end)
end

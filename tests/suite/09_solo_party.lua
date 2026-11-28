(function()
	-- Solo Party uses independent events, even with the chat summaries disabled.
	local solo = ns:GetModule("SoloParty")
	local saved = { CreateFrame, GetMoney, issecretvalue, ns.NewTimer, GetMoneyString, SOUNDKIT, PlaySound, C_TradeSkillUI, PlaySoundFile }
	local money, timers, printed, visuals, positions = 1000, {}, {}, {}, {}
	local frames, played, effects = {}, {}, {}
	local bloodTextures, bloodLayer = {}, nil
	local fontSettings = ns:GetModule("Fonts").db
	local savedFace = fontSettings.face
	fontSettings.face = "Fonts\\FRIZQT__.TTF"
	C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(skill)
		local names = { [356] = "Fischfang", [186] = "Bergbau", [393] = "Kürschnerei",
			[182] = "Kräuterkunde", [185] = "Kochkunst", [129] = "Erste Hilfe", [165] = "Lederverarbeitung" }
		return { professionName = names[skill] }
	end }
	solo:OnLogin()
	SOUNDKIT = ns.CopyDefaults(SOUNDKIT, {})
	SOUNDKIT.UI_MISSION_SUCCESS_CHEERS = 74702
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = 50111
	SOUNDKIT.UI_SCENARIO_STAGE_END = 31757
	SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_FAIL = 43501
	SOUNDKIT.UI_ADVENTURES_ADVENTURE_FAILURE_COMPLETE = 165976
	SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER = 43503
	local reward = { [74702] = true, [50111] = true, [31757] = true }
	local expense = { [43501] = true, [165976] = true, [43503] = true }
	local impacts = {}
	for _, id in ipairs({ 1240622, 1324858, 1240623, 1324859, 1240624, 1324860 }) do
		impacts[("Interface\\AddOns\\ForeverPlus\\Media\\LocalCrit\\%d.mp3"):format(id)] = id
	end
	local impactFiles = {}
	local rejectImpact, fallbackID
	PlaySoundFile = function(file, channel)
		assert(channel == "SFX", "critical sounds respect the effects channel")
		if rejectImpact and impacts[file] then
			assert(not fallbackID, "the fallback follows a single failed attempt")
			fallbackID = impacts[file]
			return false
		end
		if rejectImpact then
			assert(file == fallbackID, "the fallback plays the exact same sound by FileDataID")
		else
			assert(impacts[file], "successful clips do not play a fallback")
		end
		impactFiles[#impactFiles + 1] = file
		played[#played + 1] = file
		return true
	end
	PlaySound = function(kit, channel)
		if reward[kit] or expense[kit] then
			assert(channel == "SFX", "party sounds use the game's effects channel")
			played[#played + 1] = kit
		end
	end
	local layer
	GetMoney = function() return money end
	GetMoneyString = function(amount) return amount .. "c" end
	local secretCrit, secretMetrics = false, false
	issecretvalue = function(value)
		return value == "protected" or (secretCrit and (value == 4000 or value == "4000"))
			or (secretMetrics and value == 9999)
	end
	ns.NewTimer = function(_, _, fn)
		local timer = { fn = fn, Cancel = function(self) self.cancelled = true end }
		timers[#timers + 1] = timer
		return timer
	end
	local lastArtWidth, lastCardArt
	CreateFrame = function(kind, name, parent)
		local frame = NewFrame(kind, name)
		if parent == UIParent then
			frame.w, frame.h = 1400, 800
			frame.GetSize = function(self)
				if secretMetrics then
					return 9999, 9999
				end
				return self.w, self.h
			end
			layer = frame
		elseif layer and parent == layer then
			frame.SetPoint = function(_, _, _, _, x, y) positions[#positions + 1] = { x, y } end
		else
			frame.SetSize = function(self, w, h)
				self.w, self.h = w, h
				lastArtWidth = w
			end
			frame.SetScale = function(self, scale) self.scale = scale end
		end
		frame.CreateTexture = function(_, _, drawLayer)
			local texture = NewFrame("Texture")
			if drawLayer == "BACKGROUND" then
				texture.SetTexture = function(_, path)
					frames[#frames + 1], lastCardArt = path, frame
				end
			else
				local function Record(self, path)
					assert(not path:find("Skillbar_", 1, true), "the card does not draw profession-bar art")
					effects[#frames] = effects[#frames] or {}
					effects[#frames][self] = path
					if path:find("SoloPartyBloodSplats", 1, true) then
						bloodTextures[#bloodTextures + 1], bloodLayer = self, frame
					end
				end
				texture.SetTexture, texture.SetAtlas = Record, Record
				texture.SetTexCoord = function(self, left, _, top) self.u, self.v = left, top end
				texture.SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end
				texture.SetRotation = function(self, angle) self.rotation = angle end
				texture.SetSize = function(self, w, h) self.w, self.h = w, h end
				texture.AddMaskTexture = function(self, mask) self.mask = mask end
			end
			return texture
		end
		frame.CreateMaskTexture = function()
			local mask = NewFrame("Mask")
			mask.SetTexture = function(self, path) self.path = path end
			return mask
		end
		frame.CreateFontString = function()
			local region = NewFrame("FontString")
			region.secretText = false
			region.SetText = function(self, value)
				self.secretText = self.secretText or issecretvalue(value)
				printed[#printed + 1] = value
			end
			region.GetStringWidth = function(self)
				assert(not self.secretText, "protected damage text must not be measured for layout")
				return secretMetrics and 9999 or 80
			end
			region.SetFont = function(_, font, size, flags)
				visuals[#visuals + 1] = { font, size, flags }
				return true
			end
			return region
		end
		return frame
	end
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end
	local skill = "Eure Fertigkeit 'Kürschnerei' hat sich auf 51 erhöht."
	local function SetEnabled(value)
		solo.db.enabled = value
		solo:OnOptionChanged("enabled", value)
	end
	local function EnterWorld(value)
		money = value
		-- Other modules' world-entry callbacks need unrelated live data.
		local listeners = uv(ns.RegisterEvent, "listeners")
		listeners.PLAYER_ENTERING_WORLD[solo](solo, "PLAYER_ENTERING_WORLD")
	end
	local function Effect(index, name, left, top)
		for texture, path in pairs(effects[index] or {}) do
			if path:find(name, 1, true) and (left == nil or texture.u == left) and (top == nil or texture.v == top) then
				return texture
			end
		end
	end
	local random = math.random
	math.random = function(...)
		local first, last = ...
		-- Control variant draws while leaving positions and animation random.
		if last and last <= 6 then
			if first == 1 then return last end
			if first == 2 then return first end
		end
		return random(...)
	end
	assert(not solo.db.enabled and solo.db.sounds, "Solo Party defaults to off with sound available when enabled")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not layer and #played == 0, "disabled: no party frame or sound")
	SetEnabled(true)
	Fire("CHAT_MSG_SKILL", "protected")
	Fire("CHAT_MSG_SKILL", "Unrelated skill message")
	assert(not layer, "only readable skill increases qualify")
	Fire("CHAT_MSG_SKILL", skill)
	assert(printed[1] == "Kürschnerei" and printed[2] == ns.L.SOLO_PARTY_RANK:format(51), "the new skill rank pops: " .. table.concat(printed, ", "))

	money = 1099
	Fire("PLAYER_MONEY")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 99 Kupfer")
	timers[1].fn()
	assert(#printed == 2, "just below 10% of 1000c is quiet")
	EnterWorld(1000)
	Fire("CHAT_MSG_MONEY", "Ihr plündert 1 Silber")
	money = 1100
	Fire("PLAYER_MONEY")
	timers[2].fn()
	assert(printed[3] == ns.L.SOLO_PARTY_LOOT and printed[4] == "+100c", "exactly +10% of the purse before loot qualifies")
	money = 1500
	Fire("PLAYER_MONEY")
	money = 1351
	Fire("PLAYER_MONEY")
	assert(#printed == 4, "non-loot credits and spending below 10% are quiet")
	EnterWorld(1000)
	money = 900
	Fire("PLAYER_MONEY")
	assert(printed[5] == ns.L.SOLO_PARTY_SPENT and printed[6] == "−100c", "exactly -10% of the purse before spending qualifies")
	assert(#played == 3 and reward[played[1]] and reward[played[2]] and expense[played[3]], "each qualifying burst gets a sound from its pool")
	assert(#frames == 3 and frames[1] ~= frames[2] and frames[2] ~= frames[3] and frames[1] ~= frames[3], "all three card variants appear")
	assert(Effect(1, "SoloPartyMotifs", 0.5, 0), "skinning has strands")
	assert(Effect(2, "UI-GoldIcon") and Effect(3, "BonusChest-OrangeSmoke-Wide"), "loot has coins and spending has smoke")
	assert(visuals[1][3] == "" and visuals[2][3] == "", "card text uses a shadow without an outline")
	for _, path in ipairs(frames) do
		local asset = assert(io.open(root .. "/Media/" .. path:match("[^\\]+$") .. ".tga", "rb"))
		asset:close()
	end
	assert(positions[1][1] ~= positions[2][1] and positions[2][1] ~= positions[3][1], "consecutive bursts use different places")
	assert(visuals[4][1] == ns.GetFontFace() and visuals[6][1] == ns.GetFontFace() and visuals[4][2] ~= visuals[6][2],
		"cards use the selected interface typeface with different sizes")
	layer:GetScript("OnUpdate")(layer, 2)
	assert(not layer:IsShown(), "animation releases the overlay")

	EnterWorld(0)
	money = 11
	Fire("PLAYER_MONEY")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 10 Kupfer")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 1 Kupfer")
	timers[3].fn()
	assert(printed[8] == "+10c" and printed[10] == "+1c", "cash from zero and a second loot line in the same tick")
	assert(reward[played[4]] and played[1] ~= played[2] and played[4] ~= played[1] and played[4] ~= played[2]
		and played[5] == played[2], "the reward sound order changes after all three are used")
	assert(frames[4] == frames[2] and frames[5] == frames[1], "the card order changes after all three are used")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer")
	SetEnabled(false)
	assert(timers[4].cancelled and not layer:IsShown(), "switching off clears pending loot and active effects")
	Fire("CHAT_MSG_SKILL", skill)
	assert(#printed == 10 and #played == 5, "switching off unregisters the events")
	local preview = solo.options[#solo.options].func
	preview()
	assert(#printed == 12 and #played == 6, "preview starts with one effect and one sound")
	local bubble = assert(Effect(6, "SoloPartyWater", 0.5), "fishing has bubble particles")
	local ripple = assert(Effect(6, "SoloPartyWater", 0), "fishing keeps its ripples")
	assert(ripple.mask.path:find("SoloPartyEffectMask", 1, true), "ripples taper softly")
	local bubbleY = bubble.y
	layer:GetScript("OnUpdate")(layer, 0.7)
	assert(bubble.y > bubbleY and bubble:GetAlpha() > 0, "fishing bubbles rise and become visible")
	local left, right, low, high = false, false, math.huge, -math.huge
	for texture, path in pairs(effects[6]) do
		if texture.u == 0.5 and path:find("SoloPartyWater", 1, true) then
			left, right = left or texture.x < 0, right or texture.x > 0
			low, high = math.min(low, texture.y), math.max(high, texture.y)
		end
	end
	assert(left and right and high - low > 4, "bubbles drift at different heights on both sides")
	timers[#timers].fn()
	assert(#printed == 14 and #played == 7, "preview plays the second effect separately")
	timers[#timers].fn()
	assert(#printed == 16 and #played == 8 and expense[played[8]], "preview plays the expense sound separately")
	timers[#timers].fn()
	assert(#printed == 18 and #played == 9 and printed[18] == ns.L.SOLO_PARTY_XP_VALUE:format(450), "preview includes experience")
	timers[#timers].fn()
	assert(#printed == 20 and #played == 10 and printed[19] == ns.L.SOLO_PARTY_CRIT and printed[20] == "1234"
		and #impactFiles == 1, "preview ends with a critical hit and a weapon impact sound")
	assert(not solo.db.enabled and money == 11, "preview leaves the mode and wallet alone")

	SetEnabled(true)
	for _ = 1, 2 do
		EnterWorld(1000)
		money = 900
		Fire("PLAYER_MONEY")
	end
	assert(expense[played[11]] and played[11] ~= played[8] and played[8] ~= played[3] and played[11] ~= played[3]
		and played[12] == played[8], "the expense sound order changes after all three are used")
	solo.db.sounds = false
	solo:OnOptionChanged("sounds")
	money = 810
	Fire("PLAYER_MONEY")
	assert(#printed == 26 and #played == 12 and solo.db.enabled, "muting keeps qualifying pop-ups active")
	Fire("CHAT_MSG_SKILL", "Eure Fertigkeit 'Fischfang' hat sich auf 51 erhöht.")
	assert(Effect(#frames, "SoloPartyWater", 0.5), "the fishing effect follows the client-localized skill name")
	Fire("CHAT_MSG_SKILL", "Eure Fertigkeit 'Bergbau' hat sich auf 51 erhöht.")
	local smoke = assert(Effect(#frames, "BonusChest-OrangeSmoke-Wide"), "mining gets the forge effect")
	for _, profession in ipairs({ { "Kräuterkunde", 0, 0 }, { "Kochkunst", 0, 0.5 }, { "Erste Hilfe", 0.5, 0.5 },
		{ "Lederverarbeitung", 0.5, 0 } }) do
		Fire("CHAT_MSG_SKILL", "Eure Fertigkeit '" .. profession[1] .. "' hat sich auf 51 erhöht.")
		assert(Effect(#frames, "SoloPartyMotifs", profession[2], profession[3]), "individual motif for " .. profession[1])
	end
	solo.db.effects = false
	solo:OnOptionChanged("effects")
	assert(not smoke:IsShown() and not bubble:IsShown(), "disabling effects clears active art")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not effects[#frames] and printed[#printed - 1] == "Kürschnerei", "the frame and text continue without effects")

	-- Experience: 10% of the level's need before the gain, level-ups counted across the boundary.
	local savedXP = { UnitXP, UnitXPMax }
	local xp, xpMax = 0, 1000
	UnitXP, UnitXPMax = function() return xp end, function() return xpMax end
	solo.db.sounds = true
	EnterWorld(1000)
	local shown, sounds = #printed, #played
	xp = 99
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown, "just below 10% of the level is quiet")
	xp = 199
	Fire("PLAYER_XP_UPDATE", "player")
	assert(printed[shown + 1] == ns.L.SOLO_PARTY_XP and printed[shown + 2] == ns.L.SOLO_PARTY_XP_VALUE:format(100),
		"exactly 10% of the level qualifies: " .. tostring(printed[shown + 2]))
	assert(#played == sounds + 1 and reward[played[#played]], "experience uses the reward sounds")
	xp, xpMax = 50, 1200
	Fire("PLAYER_XP_UPDATE", "player")
	assert(printed[shown + 4] == ns.L.SOLO_PARTY_XP_VALUE:format(851), "a level-up counts the rest of the old level: " .. tostring(printed[shown + 4]))
	xp = "protected"
	Fire("PLAYER_XP_UPDATE", "player")
	xp = 400
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown + 4, "a protected value is ignored and restarts the baseline")
	solo.db.sounds = false
	SetEnabled(false)
	xp = 900
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown + 4, "switching off unregisters the experience event")
	UnitXP, UnitXPMax = unpack(savedXP, 1, 2)

	-- Critical hits work while the independent combat-text module is off.
	local combat = ns:GetModule("CombatText")
	local savedCombat = { UnitCanAttack, UnitIsUnit, UnitThreatSituation, combat.db.enabled }
	local hostile, selfTarget, threat, aimed = true, false, 1, false
	UnitCanAttack = function() return hostile and selfTarget ~= true end
	UnitIsUnit = function(a) return a == "targettarget" and aimed or selfTarget end
	UnitThreatSituation = function() return threat end
	combat.db.enabled = false
	solo.db.effects, solo.db.sounds = true, true
	shown, sounds = #printed, #played
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	assert(#printed == shown, "disabled Solo Party ignores critical hits")
	SetEnabled(true)
	for _, args in ipairs({ { "target", "WOUND", "", 1234 }, { "player", "WOUND", "CRITICAL", 50 },
		{ "target", "HEAL", "CRITICAL", 1234 }, { "target", "WOUND", "protected", 1234 },
		{ "target", "WOUND", "CRITICAL", "protected" }, { "target", "WOUND", "CRITICAL", 0 } }) do
		Fire("UNIT_COMBAT", unpack(args))
	end
	hostile = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	hostile, selfTarget = true, true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	selfTarget, threat = false, nil
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	assert(#printed == shown and #played == sounds, "only critical damage on an involved hostile target qualifies")
	threat = 1
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1000)
	assert(printed[shown + 1] == ns.L.SOLO_PARTY_CRIT and printed[shown + 2] == "1000"
		and #played == sounds + 1 and impacts[played[#played]], "every critical gets its card and weapon impact sound")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 999)
	assert(printed[shown + 4] == "999" and #played == sounds + 2, "smaller criticals are shown too")
	assert(Effect(#frames, "star4"), "critical damage has sparks")
	solo.db.criticals = false
	solo:OnOptionChanged("criticals")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2000)
	assert(#printed == shown + 4, "critical-hit option unregisters the listener")
	solo.db.criticals = true
	solo:OnOptionChanged("criticals")
	threat, aimed = nil, true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2500)
	assert(printed[shown + 6] == "2500", "a target aiming at the player counts as involvement")
	for i = 1, 4 do
		Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2500 + i * 100)
	end
	local unique = {}
	for i = 1, 6 do
		assert(not unique[impactFiles[i]], "all six critical impact sounds play before a repeat")
		unique[impactFiles[i]] = true
	end
	assert(impactFiles[7] == impactFiles[5], "the impact sound order changes after all six are used")
	math.random = random
	local beforeCrit = #impactFiles
	solo.db.critSound = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2900)
	assert(#impactFiles == beforeCrit and printed[#printed] == "2900", "the critical sound can be disabled on its own")
	local beforeReward = #played
	Fire("CHAT_MSG_SKILL", skill)
	assert(#played == beforeReward + 1 and reward[played[#played]], "the critical sound switch preserves other rewards")
	solo.db.critSound = true
	solo.db.sounds = false
	solo:OnOptionChanged("sounds")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 3000)
	assert(#impactFiles == 8 and printed[#printed] == "3000", "muting suppresses the impact while still showing the card")
	secretCrit = true
	solo.db.sounds = true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	assert(printed[#printed] == "4000" and #impactFiles == 9,
		"protected damage, as the client always sends it, is shown without being compared or measured")
	secretCrit = false
	selfTarget = "protected"
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 3500)
	assert(#impactFiles == 10, "restricted identity comparisons do not suppress criticals")
	assert(not solo.db.bloody and not bloodLayer, "Bloody defaults to off")
	solo.db.bloody = true
	solo:OnOptionChanged("bloody")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	assert(frames[#frames]:find("SoloPartyBloody", 1, true) and #bloodTextures == 8 and bloodLayer:IsShown(),
		"Bloody swaps the critical card and scatters eight splashes")
	local previousSplashes = {}
	for i, texture in ipairs(bloodTextures) do
		assert(texture.x > 0 and texture.x < 1400 and texture.y > 0 and texture.y < 800, "blood splashes stay on screen")
		previousSplashes[i] = { texture.x, texture.u, texture.v }
	end
	layer:GetScript("OnUpdate")(layer, 0.3)
	assert(bloodTextures[1]:GetAlpha() > 0 and bloodTextures[8]:GetAlpha() > 0, "blood splashes become visible")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4100)
	assert(#bloodTextures == 8, "consecutive bloody criticals reuse the eight textures")
	for i, texture in ipairs(bloodTextures) do
		local previous = previousSplashes[i]
		assert(texture.x ~= previous[1] and (texture.u ~= previous[2] or texture.v ~= previous[3]),
			"each consecutive bloody critical changes the splash motif and position")
	end
	layer:GetScript("OnUpdate")(layer, 2.1)
	assert(not bloodLayer:IsShown() and not layer:IsShown(), "blood splashes and the overlay expire together")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not frames[#frames]:find("SoloPartyBloody", 1, true) and not bloodLayer:IsShown(),
		"ordinary events keep their existing cards")
	secretCrit = true
	for _ = 1, 6 do
		Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	end
	secretCrit = false
	for _ = 1, 6 do
		Fire("CHAT_MSG_SKILL", skill)
		assert(lastArtWidth == 225, "reused slots measure clean skill text on the uncontaminated FontString")
	end
	secretMetrics = true
	Fire("CHAT_MSG_SKILL", skill)
	assert(lastArtWidth == 360, "secret text widths fall back to 220 instead of entering layout math")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4150)
	secretMetrics = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4200)
	solo.db.bloody = false
	solo:OnOptionChanged("bloody")
	assert(not bloodLayer:IsShown() and not frames[#frames]:find("SoloPartyBloody", 1, true),
		"switching off Bloody clears splashes and restores the active card")
	solo.db.bloody = true
	solo:OnOptionChanged("bloody")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4300)
	SetEnabled(false)
	assert(not bloodLayer:IsShown(), "switching off Solo Party clears the blood overlay")
	solo.db.bloody = false
	local bloodyPreview
	for _, option in ipairs(solo.options) do
		if option.name == ns.L.SOLO_PARTY_BLOODY_PREVIEW then bloodyPreview = option.func end
	end
	assert(bloodyPreview and bloodyPreview ~= preview, "Bloody has its own test button alongside the unchanged general preview")
	shown, sounds = #printed, #played
	local timerCount = #timers
	bloodyPreview()
	assert(#printed == shown + 2 and printed[#printed - 1] == ns.L.SOLO_PARTY_CRIT and printed[#printed] == "1234"
		and #played == sounds + 1 and frames[#frames]:find("SoloPartyBloody", 1, true) and bloodLayer:IsShown(),
		"the Bloody test immediately shows only its critical card, splashes and impact sound")
	assert(not solo.db.enabled and not solo.db.bloody and #timers == timerCount,
		"the Bloody test changes no settings and schedules no preview sequence")
	rejectImpact = true
	bloodyPreview()
	assert(fallbackID and impactFiles[#impactFiles] == fallbackID, "missing local audio still plays the original in the preview")
	rejectImpact = false
	preview()
	local pendingPreview = timers[#timers]
	bloodyPreview()
	assert(pendingPreview.cancelled and #timers == timerCount + 1,
		"testing Bloody stops a pending general preview instead of mixing later preview steps into the test")
	for _, viewport in ipairs({ { 1400, 800 }, { 2200, 800 }, { 650, 900 } }) do
		local w, h = unpack(viewport)
		layer.w, layer.h = w, h
		local centerX, centerY, radius = w * 0.5, h * 0.45, math.min(w, h) * 0.12
		local smallSplash = 60 * math.min(w / 1200, h / 800)
		for _ = 1, 6 do
			bloodyPreview()
			layer:GetScript("OnUpdate")(layer, 0.124) -- Close to the maximum pop scale.
			local x, y = unpack(positions[#positions])
			local halfWidth = lastCardArt.w * lastCardArt.scale / 2
			local halfHeight = lastCardArt.h * lastCardArt.scale / 2
			local dx = math.max(0, math.abs(x - centerX) - halfWidth)
			local dy = math.max(0, math.abs(y - centerY) - halfHeight)
			assert(dx * dx + dy * dy >= radius * radius, "the whole Bloody card stays outside the circle at peak scale")
			assert(x - halfWidth >= 0 and x + halfWidth <= w and y - halfHeight >= 0 and y + halfHeight <= h,
				"the Bloody card remains on screen")
			local hasSmallCenterSplash = false
			for _, texture in ipairs(bloodTextures) do
				local sx, sy = texture.x - centerX, texture.y - centerY
				local distance = math.sqrt(sx * sx + sy * sy)
				if texture.w > smallSplash then
					assert(distance >= radius + texture.w / math.sqrt(2), "even rotated large splashes stay outside the circle")
				elseif distance < radius then
					hasSmallCenterSplash = true
				end
			end
			assert(hasSmallCenterSplash, "a small blood splash remains inside the circle")
		end
	end
	SetEnabled(false)
	UnitCanAttack, UnitIsUnit, UnitThreatSituation, combat.db.enabled = unpack(savedCombat, 1, 4)
	solo.db.sounds, solo.db.effects = true, true
	CreateFrame, GetMoney, issecretvalue, ns.NewTimer, GetMoneyString, SOUNDKIT, PlaySound, C_TradeSkillUI, PlaySoundFile = unpack(saved, 1, 9)
	fontSettings.face = savedFace
	print("solo party OK")
end)()
;(function()
	local globals = { "CreateFrame", "MinimapCluster", "MuteSoundFile", "UnmuteSoundFile", "PlaySoundFile", "StopSound",
		"CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "UISpecialFrames", "ForeverPlusEmitterSounds",
		"C_Map", "GetRealZoneText", "GetSubZoneText", "GetInstanceInfo", "IsSubmerged", "MenuUtil" }
	local saved = {}
	for _, key in ipairs(globals) do saved[key] = rawget(_G, key) end
	local tracking, trigger, initialize, results, visibleRow = NewFrame("DropdownButton")
	local muted, playing = {}, nil
	local currentMap, x, y = 1453, -8990, 478
	C_Map = setmetatable({
		GetBestMapForUnit = function() return currentMap end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.4 end } end,
		GetWorldPosFromMapPos = function() return 0, { GetXY = function() return x, y end } end,
	}, { __index = saved.C_Map })
	GetRealZoneText = function() return "Stormwind" end
	GetSubZoneText = function() return "" end
	GetInstanceInfo = function() return "", "none" end
	IsSubmerged = function() return false end
	MinimapCluster = { Tracking = { Button = tracking } }
	MuteSoundFile = function(id) muted[id] = true end
	UnmuteSoundFile = function(id) muted[id] = nil end
	PlaySoundFile = function(id, channel)
		assert(not muted[id] and channel == "SFX")
		playing = id
		return true, id
	end
	StopSound = function(handle) assert(handle == playing) playing = nil end
	CreateScrollBoxListLinearView = function()
		return { SetElementExtent = function() end, SetElementInitializer = function(_, _, fn) initialize = fn end }
	end
	CreateDataProvider = function(entries) return entries end
	ScrollUtil = { InitScrollBoxListWithScrollBar = function(list)
		list.SetDataProvider = function(_, entries) results = entries end
		list.ReinitializeFrames = function()
			if visibleRow then initialize(visibleRow, visibleRow.file) end
		end
	end }
	local filterEntries, categoryEntries
	MenuUtil = { CreateContextMenu = function(button, generator)
		filterEntries, categoryEntries = {}, {}
		local function AddRadioTo(entries)
			return function(_, _, selected, action, value)
				local entry = { selected = selected, action = action, enabled = true }
				entry.SetEnabled = function(self, enabled) self.enabled = enabled end
				entries[value] = entry
				return entry
			end
		end
		generator(button, {
			CreateTitle = function() end,
			CreateDivider = function() end,
			CreateRadio = AddRadioTo(filterEntries),
			CreateButton = function(_, name, action)
				local entry = { action = action, CreateRadio = AddRadioTo(categoryEntries) }
				entry.SetEnabled = function(self, enabled) self.enabled = enabled end
				filterEntries[name] = entry
				return entry
			end,
		})
	end }
	UISpecialFrames = {}
	CreateFrame = function(kind, name, parent)
		local frame = NewFrame(kind, name)
		frame.SetText = function(self, value) self.text = value end
		frame.GetText = function(self) return rawget(self, "text") or "" end
		frame.SetChecked = function(self, value) self.checked = value end
		frame.GetChecked = function(self) return rawget(self, "checked") end
		frame.Enable = function(self) self.enabled = true end
		frame.Disable = function(self) self.enabled = false end
		if parent == tracking then
			trigger = frame
			frame.RegisterForClicks = function(_, click) assert(click == "RightButtonUp") end
			frame.SetPassThroughButtons = function(_, first) assert(first == "LeftButton") end
		end
		return frame
	end
	local module
	local fixture = setmetatable({
		NewModule = function(_, _, spec)
			module = spec
			module.ToggleEvent = function() end
			module.RegisterEvent = function() end
			module.db = ns.CopyDefaults(spec.defaults, {})
			return module
		end,
		OnAddOnLoaded = function(name, fn) if name == "Blizzard_Minimap" then fn() end end,
		RegisterDisplay = function() end,
	}, { __index = ns })
	assert(loadfile(root .. "/Modules/Minimap.lua"))("ForeverPlus", fixture)
	module.db.mutedEmitters[7079224] = true
	module:OnLogin()
	assert(trigger:IsShown() and muted[7079224], "login installs the right-click trigger and reapplies saved mutes")
	trigger:GetScript("OnClick")(trigger, "RightButton")
	local window = ForeverPlusEmitterSounds
	local function FindSound(id)
		for _, sound in ipairs(results) do
			if sound[1] == id then return sound end
		end
	end
	local function Search(query)
		window.Search:SetText(query)
		window.Search:GetScript("OnTextChanged")(window.Search)
	end
	local function OpenFilters()
		window.Filter:GetScript("OnClick")(window.Filter)
		return filterEntries
	end
	local function SelectFilter(value)
		local entry = OpenFilters()[value]
		assert(entry and entry.enabled, "filter is selectable")
		entry.action(value)
	end
	local function SelectCategory(value)
		OpenFilters()
		assert(categoryEntries[value], "category is selectable in its own submenu")
		categoryEntries[value].action(value)
	end
	assert(window:IsShown() and window.Nearby:GetChecked() and #results > 0 and #results < 600,
		"right-click opens a short list of local sources and ambience")
	Search("wind")
	local bridge = assert(FindSound(4524098), "wind near the Stormwind entrance includes the bridge source")
	assert(bridge[3]:find("Bridge Wind", 1, true) and bridge[2]:find("ambience/", 1, true),
		"placement labels identify the source even for reused audio in a different archive folder")
	assert(not FindSound(7386632) and not FindSound(7139274), "unrelated Retail and Westfall files stay out of the local results")
	SelectCategory("wind")
	assert(module.db.emitterSoundCategory == "wind" and FindSound(4524098),
		"category filtering finds a wind source whose filename gives no clue")
	SelectCategory("water")
	assert(not FindSound(4524098), "water does not match the wind source")
	SelectCategory("all")
	local row = NewFrame("Frame")
	row.CreateFontString = function()
		local label = NewFrame("FontString")
		label.SetText = function(self, value) self.text = value end
		return label
	end
	row.Mute = false
	visibleRow = row
	initialize(row, bridge)
	local guessedWind = ns.L.MINIMAP_EMITTER_CATEGORY_INFERRED:format(ns.L.MINIMAP_EMITTER_CATEGORY_WIND)
	assert(row.Detail.text:find(guessedWind, 1, true), "a category inferred from the placement is marked as a guess")
	row.Preview:GetScript("OnClick")(row.Preview)
	local bulk = window.BulkMute
	local toggleBulk = bulk:GetScript("OnClick")
	local windResults = results
	assert(#windResults > 1 and bulk.enabled and bulk:GetText() == ns.L.MINIMAP_EMITTER_MUTE_ALL)
	toggleBulk(bulk)
	assert(not playing and row.Mute:GetChecked() and bulk:GetText() == ns.L.MINIMAP_EMITTER_UNMUTE_ALL)
	for _, sound in ipairs(windResults) do
		assert(muted[sound[1]] and module.db.mutedEmitters[sound[1]], "bulk mute saves every result, including off-screen rows")
	end
	toggleBulk(bulk)
	assert(not row.Mute:GetChecked() and bulk:GetText() == ns.L.MINIMAP_EMITTER_MUTE_ALL)
	for _, sound in ipairs(windResults) do
		assert(not muted[sound[1]] and not module.db.mutedEmitters[sound[1]], "bulk unmute frees every result")
	end
	assert(muted[7079224] and module.db.mutedEmitters[7079224], "bulk actions preserve mutes outside the active search")
	local runSearch
	fixture.After = function(_, _, callback) runSearch = callback end
	Search("no matching sound")
	assert(not bulk.enabled, "new search input invalidates the old bulk target before debounce ends")
	toggleBulk(bulk)
	assert(not muted[bridge[1]], "a pending search cannot mute stale results")
	runSearch()
	assert(#results == 0 and not bulk.enabled, "bulk action is unavailable on an empty list")
	fixture.After = nil
	x, y = -8990, 420
	Search("bridge wind")
	assert(FindSound(4524098), "default source range includes the bridge near the gate")
	SelectFilter("source")
	SelectFilter(25)
	assert(not FindSound(4524098), "a smaller radius removes the bridge source")
	SelectFilter(100)
	assert(FindSound(4524098), "the type and radius filter combine with the text search")
	assert(window.Filter:GetText() == ns.L.MINIMAP_EMITTER_FILTER_ACTIVE:format(2))
	SelectFilter("background")
	local radios = OpenFilters()
	assert(radios.background.selected("background") and not radios[100].enabled and not FindSound(4524098),
		"background filter hides placed sources and disables the radius")
	assert(module.db.emitterSoundRadius == 100, "switching categories remembers the radius")
	SelectFilter(ns.L.RESET)
	assert(FindSound(4524098) and module.db.emitterSoundRadius == 0 and module.db.emitterSoundKind == "all",
		"reset restores the default range and all categories")
	Search("")
	SelectFilter("rain")
	local rainResults = results
	assert(module.db.nearbyEmitters and #rainResults == 7 and not OpenFilters()[25].enabled,
		"rain finds the build's variants at any location without changing the saved local filter")
	assert(FindSound(538982) and FindSound(2057626) and FindSound(2057628) and not FindSound(4524098),
		"rain includes the loud loops and excludes other ambient sounds")
	Search(ns.L.MINIMAP_EMITTER_RAIN_HEAVY)
	assert(#results == 3 and FindSound(538982), "localized intensity labels can be searched")
	Search("")
	toggleBulk(bulk)
	for _, sound in ipairs(rainResults) do
		assert(muted[sound[1]] and module.db.mutedEmitters[sound[1]], "all rain loops can be muted together")
	end
	assert(not muted[4524098] and muted[7079224], "the rain filter leaves other files out of the bulk operation")
	toggleBulk(bulk)
	for _, sound in ipairs(rainResults) do
		assert(not muted[sound[1]] and not module.db.mutedEmitters[sound[1]], "all rain loops can be unmuted together")
	end
	SelectFilter(ns.L.RESET)
	x, y = -8600, 860
	Search("bridge wind")
	assert(not FindSound(4524098), "a bridge emitter leaves the results when out of range")
	currentMap, x, y = 1429, -9462, 60
	Search("")
	local forest = assert(FindSound(539108), "the current zone's background plays outside the emitters folder")
	assert(forest[4] == ns.L.MINIMAP_EMITTER_AMBIENCE, "the list identifies the source as zone background")
	SelectFilter("detail")
	assert(FindSound(648331) and not FindSound(539108), "other zone sounds can be filtered separately")
	SelectFilter("background")
	assert(FindSound(539108) and not FindSound(648331), "background excludes the secondary ambience of the zone")
	toggleBulk(bulk)
	assert(muted[539108] and not muted[648331], "bulk mute respects the selected sound category")
	toggleBulk(bulk)
	assert(not muted[539108], "bulk unmute respects the selected sound category")
	window.Nearby:SetChecked(false)
	window.Nearby:GetScript("OnClick")(window.Nearby)
	Search("")
	SelectFilter("source")
	assert(FindSound(7139274) and not FindSound(539108) and not OpenFilters()[50].enabled,
		"the kind filter works across Forever and only local sources have a radius")
	SelectFilter(ns.L.RESET)
	assert(FindSound(7139274) and not FindSound(7386632), "the global list includes Forever-linked files and omits unrelated Retail files")
	SelectCategory("water")
	local waterfall = assert(FindSound(566760), "the catalog has an explicit waterfall in the water category")
	assert(not FindSound(4524098) and not FindSound(604807), "bridge wind and windmills are excluded from water")
	initialize(row, waterfall)
	assert(row.Detail.text:find(ns.L.MINIMAP_EMITTER_CATEGORY_WATER .. "   ·", 1, true) == 1,
		"an explicit filename is displayed without a guess marker")
	Search(ns.L.MINIMAP_EMITTER_CATEGORY_WATER)
	assert(FindSound(566760), "localized category names are searchable")
	SelectFilter(ns.L.RESET)
	assert(module.db.emitterSoundCategory == "all", "reset clears the category selection")
	Search("  7079224  ")
	assert(#results == 1 and results[1][1] == 7079224, "search finds an exact FileDataID")
	initialize(row, results[1])
	assert(row.Mute:GetChecked(), "saved mutes are visibly checked")
	window.MutedOnly:SetChecked(true)
	row.Mute:SetChecked(false)
	row.Mute:GetScript("OnClick")(row.Mute)
	assert(not muted[7079224] and next(module.db.mutedEmitters) == nil and #results == 0,
		"unmuting updates the client, saved selection and muted-only list")
	module.db.mutedEmitters[7386632] = true
	Search("")
	SelectCategory("unknown")
	assert(#results == 1 and results[1][1] == 7386632, "previously muted files outside the new catalog can still be unmuted")
	toggleBulk(bulk)
	assert(#results == 0 and not module.db.mutedEmitters[7386632], "bulk unmute refreshes the muted-only list")
	SelectFilter(ns.L.RESET)
	window.MutedOnly:SetChecked(false)
	Search("EXT-29_51 LOOPA")
	assert(FindSound(7139274), "search accepts multiple terms and mixed filename punctuation")
	Search("7139274")
	initialize(row, results[1])
	row.Preview:GetScript("OnClick")(row.Preview)
	assert(playing == 7139274, "reused rows preview the current file")
	window.StopPreview:GetScript("OnClick")(window.StopPreview)
	assert(not playing, "the stop button ends the audition")
	row.Preview:GetScript("OnClick")(row.Preview)
	row.Mute:SetChecked(true)
	row.Mute:GetScript("OnClick")(row.Mute)
	assert(not playing and muted[7139274] and module.db.mutedEmitters[7139274], "muting stops the preview and saves the selected file")
	module.db.emitterSoundMenu = false
	module:OnOptionChanged("emitterSoundMenu")
	assert(not trigger:IsShown() and not window:IsShown() and muted[7139274], "disabling the menu keeps active mutes")
	for _, key in ipairs(globals) do _G[key] = saved[key] end
	print("emitter sounds OK")
end)()
;(function()
	-- The stats pane rebuilds a provider from its original rows and reuses frames for new rows.
	local rank = ns:GetModule("StatRank")
	local savedWeights, savedEnabled = ns.StatWeights, rank.db.enabled
	local savedPane, savedScrollUtil, savedHook = CharacterStatsPaneScrollBox, ScrollUtil, hooksecurefunc
	local weights = CopyTable(upvalue(savedWeights, "WEIGHTS").PALADIN[2])
	weights.HIT, weights.CRIT = 8, 4
	ns.StatWeights = function() return weights end

	local function Stat(name, index)
		return { name = name, unit = "player", statIndex = index }
	end
	local health, strength, agility, stamina = Stat("HEALTH", 1), Stat("STRENGTH", 1), Stat("AGILITY", 2), Stat("STAMINA", 3)
	local intellect, spirit = Stat("INTELLECT", 4), Stat("SPIRIT", 5)
	local hit, crit, spell = Stat("HITCHANCE", 1), Stat("CRITCHANCE", 2), Stat("SPELLPOWER", 3)
	local defense, dodge, parry = Stat("DEFENSE", 1), Stat("DODGE", 2), Stat("PARRY", 3)
	local block, armor = Stat("BLOCK", 4), Stat("ARMOR", 5)
	local rows = {
		{ isHeader = true }, health,
		{ isHeader = true }, strength, agility, stamina, intellect, spirit,
		{ isHeader = true }, hit, crit, spell,
		{ isHeader = true }, defense, dodge, parry, block, armor,
	}
	local frames, initialized, provider = {}, nil, nil
	local function NewRow()
		local row = { color = { 1, 0.82, 0 }, value = "76", labelX = 11 }
		row.Label = {
			GetPoint = function() return "LEFT", row, "LEFT", row.labelX, 0 end,
			SetPoint = function(_, _, _, _, x) row.labelX = x end,
			GetTextColor = function() return unpack(row.color) end,
			SetTextColor = function(_, ...) row.color = { ... } end,
		}
		row.Background = { SetShown = function(_, on) row.stripe = on end }
		row.CreateFontString = function()
			return {
				SetPoint = function() end,
				SetFormattedText = function(_, f, n) row.number = f:format(n) end,
				SetTextColor = function(_, ...) row.numberColor = { ... } end,
				SetShown = function(_, on) row.numberShown = on end,
			}
		end
		return row
	end
	local box = {
		GetDataProvider = function() return provider end,
		ForEachFrame = function(_, fn)
			for index, data in ipairs(provider.collection) do
				fn(frames[index], data)
			end
		end,
	}
	local function Draw()
		for index, data in ipairs(provider.collection) do
			frames[index] = frames[index] or (data.isHeader and {} or NewRow())
			initialized(nil, frames[index], data)
		end
	end
	function box:SetDataProvider(new)
		provider = new
		Draw()
	end
	hooksecurefunc = function(object, method, fn)
		local original = object[method]
		object[method] = function(...)
			original(...)
			fn(...)
		end
	end
	ScrollUtil = { AddInitializedFrameCallback = function(_, fn) initialized = fn end }
	CharacterStatsPaneScrollBox = { ScrollBox = box, elementData = rows }
	rank.db.enabled = true
	rank:OnLogin()
	local function Rebuild()
		local collection = {}
		for index, data in ipairs(rows) do collection[index] = data end
		box:SetDataProvider({
			collection = collection,
			GetCollection = function() return collection end,
			Sort = function(_, cmp) table.sort(collection, cmp); Draw() end,
		})
	end
	Rebuild()
	local collection = provider.collection
	assert(rows[4] == strength and collection[4] == stamina and collection[5] == strength and collection[6] == agility,
		"sort the visible primary stats, preserving Blizzard's order for ties")
	assert(frames[4].number == "1." and frames[5].number == "2." and frames[6].number == "2." and frames[7].number == "4.",
		"equal positive weights share a place")
	assert(frames[4].labelX == 19 and frames[7].labelX == 19 and frames[8].labelX == 19 and frames[2].labelX == 11,
		"leave room before the labels for the rank numbers and align unweighted attributes")
	assert(frames[4].color[1] < 0.5 and frames[4].color[3] == 1 and frames[4].numberColor[1] == frames[4].color[1],
		"highest tier and its number use the same turquoise")
	assert(frames[5].color[1] == 1 and frames[7].color[1] < 1 and not frames[8].numberShown and frames[8].color[1] == frames[8].color[3],
		"separate colours for useful, minor and unweighted stats")
	assert(frames[4].stripe and not frames[5].stripe and frames[6].stripe and frames[4].value == "76",
		"row striping follows the new order and the stat value is untouched")
	assert(frames[10].number == "1." and frames[11].number == "2.", "rank visible hit and crit independently of hidden variants")
	assert(collection[15] == block and collection[16] == dodge and collection[17] == parry
		and frames[15].number == "1." and frames[16].number == "2." and frames[17].number == "2.",
		"rank block ahead of dodge and parry using the protection paladin item weights")
	assert(not frames[14].numberShown and frames[14].color[3] == 0 and frames[14].labelX == 19
		and not frames[18].numberShown and frames[18].color[3] == 0 and frames[18].labelX == 19,
		"weighted defense and armor are aligned and use the original label color")

	local items = ns:GetModule("Items")
	local onTalentChange = upvalue(ns.RegisterEvent, "listeners").TRAIT_CONFIG_UPDATED[items]
	local savedAfter = ns.After
	ns.After = function(_, _, fn) fn() end
	weights = { INT = 1, SPI = 0.6, STA = 0.3, SP = 0.8 }
	onTalentChange()
	ns.After = savedAfter
	assert(collection[4] == intellect and collection[5] == spirit and collection[6] == stamina and collection[7] == strength,
		"changing the talent weights reorders the open pane")
	assert(collection[9].isHeader and collection[12] == spell and not frames[7].numberShown,
		"categories and incomparable rows retain their slots")

	Rebuild()
	assert(provider.collection[4] == intellect, "a newly built provider is also sorted")
	rank.db.enabled = false
	rank:OnOptionChanged()
	assert(provider.collection[4] == strength and provider.collection[6] == stamina and frames[4].color[1] == 1
		and frames[4].color[3] == 0 and not frames[4].numberShown and frames[4].stripe and frames[4].labelX == 11,
		"disabling restores the stock rows")
	ns.StatWeights, rank.db.enabled = savedWeights, savedEnabled
	CharacterStatsPaneScrollBox, ScrollUtil, hooksecurefunc = savedPane, savedScrollUtil, savedHook
	print("stat rank OK")
end)()

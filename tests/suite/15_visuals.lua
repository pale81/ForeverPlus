(function()
	local visuals = ns:GetModule("Visuals")
	local pm = ns.PortraitModes
	local wanderlust = ns:GetModule("Wanderlust")
	local helpers = ns:GetModule("Helpers")
	local roleplay = ns:GetModule("Roleplay")
	local dialog = ns:GetModule("Dialog")
	local speech = ns:GetModule("SpeechBubbles")
	local emotes = ns:GetModule("ChatEmotes")
	local camera = ns:GetModule("Camera")
	local solo = ns:GetModule("SoloParty")
	local landing = ns:GetModule("Landing")
	local combatText = ns:GetModule("CombatText")
	local wind = ns:GetModule("GuidingWind")
	local oldCreate, oldPlayer, oldHook = CreateFrame, PlayerFrame, hooksecurefunc
	local oldShift, oldMod, oldEdit, oldRegistry = IsShiftKeyDown, IsModifierKeyDown, EditModeManagerFrame, EventRegistry
	local oldCursor, oldTicker = GetCursorPosition, C_Timer.NewTicker
	C_Timer.NewTicker = function() return { Cancel = function() end } end
	local shift, modDown, edit = false, false, false
	local callbacks, textures = {}, {}
	local unitChanged, wheel, menuFrame, pickerFrame, ghostFrame
	local frame, container, original, mask = NewFrame("Button"), NewFrame("Frame"), NewFrame("Texture"), NewFrame("Mask")
	frame.unit, frame.PlayerFrameContainer = "player", container
	container.PlayerPortrait, container.PlayerPortraitMask = original, mask
	container.CreateTexture = function()
		local texture = NewFrame("Texture")
		texture.SetAllPoints = function(self, region) self.bounds = region end
		texture.AddMaskTexture = function(self, region) self.mask = region end
		texture.SetTexture = function(self, file) self.asset = file return true end
		texture.SetDesaturated = function(self, flag) self.desaturated = flag and true or false end
		textures[#textures + 1] = texture
		return texture
	end
	PlayerFrame = frame
	hooksecurefunc = function(name, fn)
		if name == "UnitFrame_SetUnit" then unitChanged = fn end
	end
	EventRegistry = { RegisterCallback = function(_, event, fn, owner) callbacks[event] = function() fn(owner) end end }
	IsShiftKeyDown = function() return shift end
	IsModifierKeyDown = function() return modDown end
	EditModeManagerFrame = { IsEditModeActive = function() return edit end }
	GetCursorPosition = function() return 200, 300 end
	CreateFrame = function(kind, name, parent, template)
		local region = oldCreate(kind, name, parent, template)
		region.EnableMouseWheel = function(self, enabled) self.wheelEnabled = enabled end
		region.SetAllPoints = function(self, bounds) self.bounds = bounds end
		region.SetMouseClickEnabled = function(self, enabled) self.clickEnabled = enabled end
		region.SetMouseMotionEnabled = function(self, enabled) self.motionEnabled = enabled end
		region.GetParent = function() return parent end
		if name == "ForeverPlusPlayerPortraitWheel" then
			assert(parent == container, "the portrait wheel belongs to the player portrait container")
			wheel = region
		elseif name == "ForeverPlusPortraitModeMenu" then
			menuFrame = region
		elseif name == "ForeverPlusPortraitModeIconPicker" then
			pickerFrame = region
		elseif template == "TooltipBackdropTemplate" and not name then
			ghostFrame = region
		end
		return region
	end

	-- Save module states so the test restores everything cleanly.
	local saved = {
		mode = visuals.cdb.playerPortraitMode,
		wl = wanderlust.db.enabled, wlBags = wanderlust.db.showBags,
		fish = helpers.db.fishing,
		rp = roleplay.db.enabled, dlg = dialog.db.enabled, sb = speech.db.enabled,
		em = emotes.db.enabled, cam = camera.db.enabled,
		spOn = solo.db.enabled, spCrit = solo.db.criticals, spBloody = solo.db.bloody,
		land = landing.db.enabled, ct = combatText.db.enabled,
		windOn = wind.db.enabled, windInt = wind.db.interval, windStr = wind.db.strength,
	}
	ns.SetOption("Wanderlust", "enabled", false)
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("SoloParty", "enabled", false)
	ns.SetOption("SoloParty", "bloody", false)
	ns.SetOption("Landing", "enabled", true)
	ns.SetOption("CombatText", "enabled", false)
	ns.SetOption("GuidingWind", "enabled", false)

	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	assert(visuals.db.playerPortraitWheel and saved.mode == 1, "new characters start with their standard portrait")
	pm.Setup()
	local background, icon, shade, shine = unpack(textures)
	assert(wheel.bounds == original and wheel.clickEnabled == false and wheel.motionEnabled == false)
	assert(background.bounds == original and background.mask == mask and icon.mask == mask and shade.mask == mask and shine.mask == mask)
	assert(original:IsShown() and not background:IsShown() and not icon:IsShown() and not shade:IsShown())

	local scroll = wheel:GetScript("OnMouseWheel")
	local click = wheel:GetScript("OnClick")
	assert(not wheel.wheelEnabled)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 1 and not icon:IsShown(), "plain scrolling does not switch modes")

	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	assert(wheel.wheelEnabled)
	-- Slot 2: Wanderlust
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 2 and icon:IsShown() and background:IsShown())
	assert(icon.asset == 237386 and icon.rotation and icon.rotation < 0)
	assert(icon.desaturated == true and wheel.clickEnabled == true and wheel.motionEnabled == true)
	-- Left-click enables Wanderlust and lights up the emblem.
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	click(wheel, "LeftButton")
	assert(wanderlust.db.enabled == true and pm.IsModeActive("wanderlust") and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(wanderlust.db.enabled == false and not pm.IsModeActive("wanderlust") and icon.desaturated == true)

	-- External option change updates the portrait live.
	ns.SetOption("Wanderlust", "enabled", true)
	assert(icon.desaturated == false, "external option change refreshes portrait icon")
	ns.SetOption("Wanderlust", "enabled", false)
	assert(icon.desaturated == true)

	-- Slot 3: Angler
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 3 and icon.asset == 643874 and icon.rotation == 0)
	shift = false
	click(wheel, "LeftButton")
	assert(helpers.db.fishing == true and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(helpers.db.fishing == false and icon.desaturated == true)

	-- Slot 4: RP mode
	shift = true
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 4 and icon.asset == 133740)
	shift = false
	click(wheel, "LeftButton")
	assert(roleplay.db.enabled and dialog.db.enabled and speech.db.enabled and emotes.db.enabled and camera.db.enabled)
	assert(pm.IsModeActive("rp") and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(not roleplay.db.enabled and not dialog.db.enabled and not speech.db.enabled and not emotes.db.enabled and not camera.db.enabled)
	assert(not pm.IsModeActive("rp") and icon.desaturated == true)

	-- Slot 5: Berserker mode (Bloody crits + Landing jump sounds + CombatText)
	shift = true
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 5 and icon.asset == 132400)
	assert(not pm.IsModeActive("berserker"), "partial default state shows Berserker as inactive")
	shift = false
	click(wheel, "LeftButton")
	assert(solo.db.enabled and solo.db.criticals and solo.db.bloody and landing.db.enabled and combatText.db.enabled)
	assert(pm.IsModeActive("berserker") and icon.desaturated == false)
	-- Unchecking one feature while mode is active turns that feature off immediately while keeping the mode active.
	pm.SetFeatureSelected("combatText", false)
	assert(not combatText.db.enabled and solo.db.bloody and landing.db.enabled and pm.IsModeActive("berserker"))
	-- Turning the mode off turns off remaining checked features while preserving the saved checkmarks.
	click(wheel, "LeftButton")
	assert(not solo.db.bloody and not solo.db.enabled and not landing.db.enabled and not pm.IsModeActive("berserker"))
	assert(pm.IsFeatureSelected("bloody") and pm.IsFeatureSelected("landing") and not pm.IsFeatureSelected("combatText"))
	-- Re-checking while mode is off only saves the choice without enabling it yet.
	pm.SetFeatureSelected("combatText", true)
	assert(pm.IsFeatureSelected("combatText") and not combatText.db.enabled)

	-- Right-click opens the WoW-style PortraitFrameTemplate mode menu on the current mode tab.
	click(wheel, "RightButton")
	assert(menuFrame and menuFrame:IsShown(), "right-click opens the portrait mode menu")
	-- Tooltip uses WoW atlas markup instead of unsupported Unicode glyphs and lists sub-options indented.
	-- Feature lines stay unwrapped and never green; the green hints follow after a blank line.
	local tooltipLines, tipCalls = {}, {}
	local oldAddColored, oldBlank, oldInstr = GameTooltip_AddColoredLine, GameTooltip_AddBlankLineToTooltip,
		GameTooltip_AddInstructionLine
	local oldGreen, oldGray, oldWhite = GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR
	local function FakeColor() return { WrapTextInColorCode = function(_, text) return text end } end
	local green = FakeColor()
	GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = green, FakeColor(), FakeColor()
	GameTooltip_AddColoredLine = function(_, text, color, wrap, leftOffset)
		tooltipLines[#tooltipLines + 1] = { text = text, color = color, wrap = wrap, offset = leftOffset }
		tipCalls[#tipCalls + 1] = "line"
	end
	GameTooltip_AddBlankLineToTooltip = function() tipCalls[#tipCalls + 1] = "blank" end
	GameTooltip_AddInstructionLine = function(_, _, wrap) tipCalls[#tipCalls + 1] = wrap == false and "hint" or "wrapped hint" end
	wheel:GetScript("OnEnter")(wheel)
	GameTooltip_AddColoredLine, GameTooltip_AddBlankLineToTooltip, GameTooltip_AddInstructionLine = oldAddColored, oldBlank,
		oldInstr
	GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = oldGreen, oldGray, oldWhite
	local sawSubSound, sawSubEffect = false, false
	for _, line in ipairs(tooltipLines) do
		assert(not line.text:find("\226\156\147") and not line.text:find("\226\151\139"), "tooltip avoids missing glyph symbols")
		assert(line.color ~= green and line.wrap == false, "portrait tooltip feature lines are unwrapped and not green")
		local indented = (line.offset or 0) > 0
		if indented and line.text:find(ns.L.SOLO_PARTY_SOUNDS, 1, true) then sawSubSound = true end
		if indented and line.text:find(ns.L.SOLO_PARTY_EFFECTS, 1, true) then sawSubEffect = true end
	end
	assert(#tooltipLines == 5 and sawSubSound and sawSubEffect, "portrait tooltip includes indented sub-options")
	assert(table.concat(tipCalls, ",", #tipCalls - 3) == "blank,hint,hint,hint", "portrait tooltip separates unwrapped hints")
	local landingRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "feature" and row.entry.feature.key == "landing" then
			landingRow = row
			break
		end
	end
	assert(landingRow, "Berserker menu lists the landing sound feature")
	-- Drag 'landing' from Berserker onto the Wanderlust tab (tabs[1]).
	local wanderlustTab = menuFrame.tabs[1]
	wanderlustTab.IsMouseOver = function() return true end
	landingRow:GetScript("OnDragStart")(landingRow)
	assert(ghostFrame and ghostFrame:IsShown(), "dragging shows the floating ghost label")
	landingRow:GetScript("OnDragStop")(landingRow)
	assert(not ghostFrame:IsShown())
	assert(pm.FeatureMode("landing") == "wanderlust", "dropping on a mode tab reassigns the feature")
	-- Drag a sub-option ('SoloParty:sounds') from Berserker onto Wanderlust.
	local soundRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "sub" and row.entry.sub.id == "SoloParty:sounds" then
			soundRow = row
			break
		end
	end
	assert(soundRow, "Berserker menu displays the SoloParty sounds sub-option")
	local oldSounds = solo.db.sounds
	ns.SetOption("SoloParty", "sounds", false)
	wanderlustTab.IsMouseOver = function() return true end
	soundRow:GetScript("OnDragStart")(soundRow)
	assert(ghostFrame and ghostFrame:IsShown(), "dragging a sub-option shows the floating ghost")
	soundRow:GetScript("OnDragStop")(soundRow)
	assert(not ghostFrame:IsShown())
	assert(pm.FeatureMode("SoloParty:sounds") == "wanderlust", "dropping a sub-option on a tab moves it there")
	-- Turning Wanderlust on now toggles Wanderlust, Landing and the moved SoloParty:sounds together.
	pm.ToggleMode("wanderlust")
	assert(wanderlust.db.enabled and landing.db.enabled and solo.db.sounds and pm.IsModeActive("wanderlust"))
	pm.ToggleMode("wanderlust")
	assert(not wanderlust.db.enabled and not landing.db.enabled and not solo.db.sounds)
	-- Moving the sub-option back onto its parent's mode re-attaches it as a sub-option.
	assert(pm.MoveFeature("SoloParty:sounds", "berserker"))
	assert(pm.FeatureMode("SoloParty:sounds") == "berserker")
	ns.SetOption("SoloParty", "sounds", oldSounds)
	-- Open icon picker, pick a custom Blizzard icon, and verify live update + reset.
	menuFrame.IconButton:GetScript("OnClick")(menuFrame.IconButton)
	assert(pickerFrame and pickerFrame:IsShown(), "Icon button opens the WoW icon picker")
	assert(pickerFrame.cells[2] and pickerFrame.cells[2].iconID == 132397, "picker starts with Berserker icon presets")
	pickerFrame.cells[2]:GetScript("OnClick")(pickerFrame.cells[2])
	assert(pm.ModeIcon("berserker") == 132397 and icon.asset == 132397, "picking an icon updates the portrait live")
	-- Reset restores default assignments, checkmarks and icons.
	pm.ResetAssignments()
	assert(pm.FeatureMode("landing") == "berserker" and pm.IsFeatureSelected("combatText"))
	assert(pm.ModeIcon("berserker") == 132400 and icon.asset == 132400)
	menuFrame:Hide()

	-- Slot 6: Guiding Wind mode with its own WoW icon and menu controls.
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 6 and icon.asset == 236154, "slot 6 is Guiding Wind with gale icon")
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	click(wheel, "LeftButton")
	assert(wind.db.enabled == true and pm.IsModeActive("guidingWind") and icon.desaturated == false)
	-- Right-click opens Guiding Wind tab with interval and strength controls.
	click(wheel, "RightButton")
	assert(menuFrame and menuFrame:IsShown() and #menuFrame.tabs == 5, "portrait menu has 5 mode tabs")
	local intervalRow, strengthRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "control" then
			if row.entry.control.key == "interval" then intervalRow = row end
			if row.entry.control.key == "strength" then strengthRow = row end
		end
	end
	assert(intervalRow and strengthRow, "Guiding Wind tab exposes interval and strength controls")
	local startInt = wind.db.interval
	intervalRow.Plus:GetScript("OnClick")(intervalRow.Plus)
	assert(wind.db.interval == startInt + 1, "interval + button increases gust interval")
	intervalRow.Minus:GetScript("OnClick")(intervalRow.Minus)
	assert(wind.db.interval == startInt, "interval - button decreases gust interval")
	-- Moving all three sub-options away still leaves the interval & strength controls expandable and visible.
	assert(pm.MoveFeature("GuidingWind:autoGusts", "wanderlust")
		and pm.MoveFeature("GuidingWind:biomeParticles", "wanderlust")
		and pm.MoveFeature("GuidingWind:sound", "wanderlust"))
	local stillHasInterval = false
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "control" and row.entry.control.key == "interval" then
			stillHasInterval = true
			break
		end
	end
	assert(stillHasInterval, "Guiding Wind controls stay visible even after moving all sub-options")
	pm.ResetAssignments()
	assert(pm.PreviewFlash("guidingWind") == true and wind.GetState().active, "Guiding Wind header preview triggers a gust")
	menuFrame:Hide()
	click(wheel, "LeftButton")
	assert(wind.db.enabled == false and not wind.GetState().active and not pm.IsModeActive("guidingWind") and icon.desaturated == true)
	-- Preview still works when Guiding Wind is disabled (without re-enabling it or starting auto-gusts).
	assert(pm.PreviewFlash("guidingWind") == true and wind.GetState().active
		and wind.db.enabled == false and not wind.GetState().timerActive,
		"Guiding Wind preview works while mode is disabled")
	ns.SetOption("GuidingWind", "enabled", false)

	-- Wrap forward to normal and backward to slot 6.
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 1 and not icon:IsShown() and not background:IsShown())
	assert(wheel.clickEnabled == false and wheel.motionEnabled == false, "normal portrait passes clicks through")
	scroll(wheel, -1)
	assert(visuals.cdb.playerPortraitMode == 6 and icon:IsShown(), "reverse scrolling also wraps to slot 6")

	-- Vehicle, Edit Mode and disabling the option hide the overlay cleanly.
	frame.unit = "vehicle"
	unitChanged(frame)
	scroll(wheel, -1)
	assert(not wheel.wheelEnabled and not icon:IsShown() and visuals.cdb.playerPortraitMode == 6)
	frame.unit = "player"
	unitChanged(frame)
	assert(wheel.wheelEnabled and icon:IsShown())
	edit = true
	callbacks["EditMode.Enter"]()
	scroll(wheel, -1)
	assert(not wheel.wheelEnabled and not wheel.clickEnabled and visuals.cdb.playerPortraitMode == 6)
	edit = false
	callbacks["EditMode.Exit"]()
	assert(wheel.wheelEnabled and wheel.clickEnabled)
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	assert(not wheel.wheelEnabled)
	ns.SetOption("Visuals", "playerPortraitWheel", false)
	assert(not icon:IsShown() and not background:IsShown() and visuals.cdb.playerPortraitMode == 6)
	ns.SetOption("Visuals", "playerPortraitWheel", true)
	assert(icon:IsShown() and icon.asset == 236154)

	-- Restore state cleanly.
	ns.SetOption("Visuals", "playerPortraitWheel", false)
	visuals.db.playerPortraitWheel, visuals.cdb.playerPortraitMode = true, saved.mode
	pm.ResetAssignments()
	ns.SetOption("GuidingWind", "enabled", saved.windOn)
	ns.SetOption("GuidingWind", "interval", saved.windInt)
	ns.SetOption("GuidingWind", "strength", saved.windStr)
	ns.SetOption("Wanderlust", "enabled", saved.wl)
	ns.SetOption("Wanderlust", "showBags", saved.wlBags)
	ns.SetOption("Helpers", "fishing", saved.fish)
	ns.SetOption("Roleplay", "enabled", saved.rp)
	ns.SetOption("Dialog", "enabled", saved.dlg)
	ns.SetOption("SpeechBubbles", "enabled", saved.sb)
	ns.SetOption("ChatEmotes", "enabled", saved.em)
	ns.SetOption("Camera", "enabled", saved.cam)
	ns.SetOption("SoloParty", "enabled", saved.spOn)
	ns.SetOption("SoloParty", "criticals", saved.spCrit)
	ns.SetOption("SoloParty", "bloody", saved.spBloody)
	ns.SetOption("Landing", "enabled", saved.land)
	ns.SetOption("CombatText", "enabled", saved.ct)
	setuv(pm.Setup, "portraitWheel", nil)
	setuv(pm.Setup, "portraitBackground", nil)
	setuv(pm.Setup, "portraitIcon", nil)
	setuv(pm.Setup, "portraitShade", nil)
	setuv(pm.Setup, "portraitShine", nil)
	setuv(uv(pm.Setup, "OpenModeMenu"), "menu", nil)
	setuv(uv(uv(pm.Setup, "OpenModeMenu"), "CreateModeMenu"), "iconPicker", nil)
	CreateFrame, PlayerFrame, hooksecurefunc = oldCreate, oldPlayer, oldHook
	IsShiftKeyDown, IsModifierKeyDown, EditModeManagerFrame, EventRegistry = oldShift, oldMod, oldEdit, oldRegistry
	GetCursorPosition, C_Timer.NewTicker = oldCursor, oldTicker
	print("player portrait modes OK")
end)()
;(function()
	local rp = ns:GetModule("Roleplay")
	local now, player, friendly, own = 10000, true, true, false
	local messages, timeout, save, encodedFixtures = {}, nil, nil, {}
	local oldCreate = CreateFrame
	local targetFrame = NewFrame("Frame")
	targetFrame.GetPortrait = function() return NewFrame("Texture") end
	local visuals = ns:GetModule("Visuals")
	local oldDragon, oldScale = visuals.db.playerDragon, visuals.db.dragonScale
	local oldGroup, oldArt = uv(visuals.ApplyPlayerDragon, "dragonButtons"), uv(visuals.ApplyPlayerDragon, "dragon")
	setuv(visuals.ApplyPlayerDragon, "dragonButtons", nil)
	setuv(visuals.ApplyPlayerDragon, "dragon", nil)
	local modified, editMode = false, false
	local playerFrame = NewFrame("Button")
	playerFrame.unit = "player"
	local dragonArt = {}
	local function RecordLayout(frame)
		frame.SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end
		frame.SetSize = function(self, width, height) self.w, self.h = width, height end
	end
	playerFrame.PlayerFrameContainer.CreateTexture = function()
		local texture = NewFrame("Texture")
		RecordLayout(texture)
		texture.SetVertexColor = function(self, ...) self.color = { ... } end
		tinsert(dragonArt, texture)
		return texture
	end
	local testGlobals = {
		TargetFrame = targetFrame,
		PlayerFrame = playerFrame,
		IsModifierKeyDown = function() return modified end,
		UnitIsPlayer = function() return player end,
		UnitIsFriend = function() return friendly end,
		UnitIsUnit = function() return own end,
		UnitFullName = function() return "Aelwyn", "Test Realm" end,
		GetNormalizedRealmName = function() return "LocalRealm" end,
		GetTime = function() return now end,
		C_ChatInfo = {
			RegisterAddonMessagePrefix = function(prefix) assert(prefix == "ForeverPlusRP1") return 0 end,
			SendAddonMessage = function(prefix, text, channel, target)
				assert(prefix == "ForeverPlusRP1" and channel == "WHISPER" and #prefix + #text < 255)
				messages[#messages + 1] = { text = text, target = target }
				return 0
			end,
		},
		C_EncodingUtil = {
			EncodeBase64 = function(data)
				local encoded = ("a"):rep(math.ceil(#data / 3) * 4)
				encodedFixtures[encoded] = data
				return encoded
			end,
			DecodeBase64 = function(encoded) return encodedFixtures[encoded] end,
		},
		CreateFrame = function(kind, name, parent, template)
			local frame = oldCreate(kind, name)
			if name == "ForeverPlusPlayerDragonButtons" then
				frame.GetParent = function() return parent end
				frame.Hide = function(self)
					self.shown = false
					self:GetScript("OnHide")(self)
				end
			elseif parent and parent == rawget(_G, "ForeverPlusPlayerDragonButtons") then
				frame.GetParent = function() return parent end
				RecordLayout(frame)
			elseif parent and parent == rawget(_G, "ForeverPlusRoleplayEditor") and template == "UIPanelButtonTemplate" then
				save = frame
			elseif kind == "EditBox" or template == "ForeverPlusRoleplayStoryInputTemplate" then
				local box = kind == "EditBox" and frame or frame.EditBox
				box.GetText = function(self) return self.value or "" end
				box.SetText = function(self, value) self.value = value end
			end
			return frame
		end,
	}
	local originals = {}
	for key, value in pairs(testGlobals) do
		originals[key], _G[key] = _G[key], value
	end
	local oldAfter, oldEditMode = C_Timer.After, ns.IsEditModeActive
	ns.IsEditModeActive = function() return editMode end
	local timeoutDelay
	C_Timer.After = function(delay, fn) timeoutDelay, timeout = delay, fn end
	local oldRegister, oldSend = Enum.RegisterAddonMessagePrefixResult, Enum.SendAddonMessageResult
	Enum.RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1 }
	Enum.SendAddonMessageResult = { Success = 0 }

	rp:OnLogin()
	local profileTooltip = TEST_POSTCALLS[#TEST_POSTCALLS]
	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	local function Deliver(text, sender, channel)
		onEvent(nil, "CHAT_MSG_ADDON", "ForeverPlusRP1", text, channel or "WHISPER", sender)
	end
	local button = ForeverPlusRoleplayTargetButton
	button.GetCenter = function() return 15 end
	local click = button:GetScript("OnClick")
	assert(button:IsShown() and not rp.cdb.shared, "friendly player has a portrait button and sharing starts off")
	assert(#messages == 0, "selecting a target does not send a request")
	Deliver("Q:aca123", "Reader")
	assert(messages[1].text == "N:aca123" and messages[1].target == "Reader-LocalRealm", "private profile returns no data")

	ns.SetOption("Visuals", "dragonScale", 100)
	ns.SetOption("Visuals", "playerDragon", "none")
	local group = ForeverPlusPlayerDragonButtons
	local function DragonButtonAt(x, y)
		for _, part in ipairs(group.parts) do
			if part:IsShown() and x >= part.x and x < part.x + part.w and y <= part.y and y > part.y - part.h then
				return part
			end
		end
	end
	local hiddenButton = assert(DragonButtonAt(12, -49), "the hidden dragon has the plain hit area on first login")
	assert(#dragonArt == 0 and not DragonButtonAt(53, -48), "the fallback creates no art and leaves the portrait centre free")
	hiddenButton:GetScript("OnEnter")(hiddenButton)
	assert(not group:GetScript("OnUpdate"), "the invisible dragon needs no hover animation")

	ns.SetOption("Visuals", "playerDragon", "bronze")
	local dragonButton = assert(DragonButtonAt(12, -49), "the dragon's body is clickable")
	assert(not DragonButtonAt(53, -48), "the transparent portrait centre has no RP hit area")
	assert(DragonButtonAt(85, -73) and not DragonButtonAt(90, -73), "the plain dragon reacts at the thin tail tip")
	assert(not playerFrame:GetScript("PostClick"), "the normal player portrait has no RP hook")
	local art, shine = unpack(dragonArt)
	local restY, restShine = art.y, shine:GetAlpha()
	dragonButton:GetScript("OnEnter")(dragonButton)
	group:GetScript("OnUpdate")(group, 0.2)
	assert(art.y > restY and shine:GetAlpha() > restShine and shine.color[2] == art.color[2], "hover lifts the dragon and adds matching shine")
	assert(not group:GetScript("OnUpdate"), "the animation stops at the raised position")
	dragonButton:GetScript("OnLeave")(dragonButton)
	group:GetScript("OnUpdate")(group, 0.2)
	assert(art.y == restY and shine:GetAlpha() == restShine, "leaving restores the original dragon")
	modified = true
	dragonButton:GetScript("OnClick")(dragonButton)
	modified, editMode = false, true
	dragonButton:GetScript("OnClick")(dragonButton)
	editMode = false
	assert(not rawget(_G, "ForeverPlusRoleplayEditor"), "modified clicks and Edit Mode do not open the editor")
	rp.db.playerPortraitClick = false
	rp:OnOptionChanged("playerPortraitClick")
	assert(not group:IsShown() and art:IsShown(), "disabling the RP shortcut keeps the dragon as decoration")
	rp.db.playerPortraitClick = true
	visuals.db.playerDragon = "none"
	visuals.ApplyPlayerDragon()
	assert(group:IsShown() and not art:IsShown() and not shine:IsShown(), "hiding the dragon keeps only the shortcut")
	hiddenButton:GetScript("OnClick")(hiddenButton)
	assert(ForeverPlusRoleplayEditor:IsShown(), "the invisible dragon opens the RP editor")
	ForeverPlusRoleplayEditor:Hide()
	ns.SetOption("Roleplay", "playerPortraitClick", false)
	assert(not group:IsShown(), "the RP option also disables the invisible shortcut")
	ns.SetOption("Roleplay", "playerPortraitClick", true)
	visuals.db.playerDragon, visuals.db.dragonScale = "silverWinged", 120
	visuals.ApplyPlayerDragon()
	assert(group:IsShown() and DragonButtonAt(12, -70) and not DragonButtonAt(70, -54), "the winged silhouette scales with the art")
	assert(DragonButtonAt(118, -80) and not DragonButtonAt(124, -80), "the scaled winged dragon reacts at the thin tail tip")
	dragonButton = DragonButtonAt(12, -70)
	dragonButton:GetScript("OnClick")(dragonButton)
	local editor = ForeverPlusRoleplayEditor
	assert(editor:IsShown(), "left-clicking the portrait dragon opens the RP editor")
	editor:Hide()
	SlashCmdList.FOREVERPLUS("rp")
	assert(editor:IsShown(), "the slash command still opens the editor")
	local story = "Über den Pass.\n|Hitem:1|h[Text]|h\n" .. ("é"):rep(540)
	editor.Fields.name:SetText("  Émeline  ")
	editor.Fields.occupation:SetText("Bergführerin " .. ("x"):rep(80))
	editor.Fields.birthplace:SetText("Dun Morogh " .. ("x"):rep(80))
	editor.Fields.residence:SetText("Eisenschmiede " .. ("x"):rep(80))
	editor.Fields.story:SetText(story)
	editor.Share.GetChecked = function() return true end
	save:GetScript("OnClick")()
	assert(not editor:IsShown() and rp.cdb.shared and rp.cdb.profile.name == "Émeline", "the editor saves per character")
	assert(rp.cdb.profile.story:sub(-2) == "é" and #rp.cdb.profile.story <= 1100, "UTF-8 story is trimmed to whole characters")

	click()
	local viewer = ForeverPlusRoleplayViewer
	local loading, reads = ns.L.RP_LOADING, {}
	viewer.Text.SetText = function(_, text) reads[#reads + 1] = text end
	viewer.Hide = function(self)
		self.shown = false
		self:GetScript("OnHide")()
	end
	local query = messages[2]
	assert(query.text:match("^Q:%x+$") and query.target == "Aelwyn-TestRealm", "portrait queries the full target name")
	Deliver("N:" .. query.text:sub(3), "Aelwyn-LocalRealm")
	Deliver("N:" .. query.text:sub(3), "Aelwyn-TestRealm", "GUILD")
	assert(#reads == 0, "wrong realm or channel cannot answer")
	Deliver(query.text, "Reader-LocalRealm")
	assert(#messages == 2, "a response waits for enough budget to send every piece")
	now = now + 1
	Deliver(query.text, "Reader-LocalRealm")
	assert(#messages == 11, "long profile fits in nine pieces")
	for index = #messages, 3, -1 do
		Deliver(messages[index].text, "Aelwyn-TestRealm")
		if index > 3 then
			assert(#reads == 0, "response waits for all pieces")
			Deliver(messages[index].text, "Aelwyn-TestRealm")
		end
	end
	assert(#reads == 1 and reads[1]:find("Dun Morogh", 1, true)
		and reads[1]:find("Eisenschmiede", 1, true)
		and reads[1]:find("\n||Hitem:1||h[Text]||h\n", 1, true), "profile renders UTF-8, line breaks and literal markup")
	timeout()
	assert(#reads == 1, "a completed response cancels its timeout")

	now = now + 10
	click()
	click()
	assert(reads[#reads] == loading, "reopening fetches a fresh profile")
	local stale = messages[#messages].text:sub(3)
	player = false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	Deliver("N:" .. stale, "Aelwyn-TestRealm")
	timeout()
	assert(not button:IsShown() and not viewer:IsShown() and reads[#reads] == loading, "target change cancels the request")

	player, friendly = true, false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	assert(not button:IsShown(), "hostile players have no portrait button")
	friendly = true
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	click()
	local lateID = messages[#messages].text:sub(3)
	assert(timeoutDelay == 3, "a silent native target stops showing the loading message after three seconds")
	now = now + timeoutDelay
	timeout()
	assert(reads[#reads] == ns.L.RP_NO_REPLY, "an unanswered native request shows its status")
	now = now + 1
	for index = 3, 11 do
		local packet = messages[index].text:gsub("^P:%x+:", "P:" .. lateID .. ":")
		Deliver(packet, "Aelwyn-TestRealm")
	end
	assert(reads[#reads]:find("Dun Morogh", 1, true), "a native reply still replaces the status after four seconds")

	own, rp.cdb.shared = true, false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	local sent = #messages
	click()
	assert(viewer:IsShown() and not editor:IsShown() and #messages == sent
		and reads[#reads]:find("Émeline", 1, true), "self target opens a read-only preview of the saved private profile")
	local profile = rp.cdb.profile
	rp.cdb.profile = {}
	click()
	click()
	assert(viewer:IsShown() and reads[#reads] == ns.L.RP_EMPTY and #messages == sent, "empty self profile stays in the viewer")
	rp.cdb.profile, rp.cdb.shared = profile, true

	local oldNewTimer = C_Timer.NewTimer
	local hoverTimer, overBook, overViewer
	C_Timer.NewTimer = function(_, callback)
		hoverTimer = { Fire = callback, Cancel = function(self) self.cancelled = true end }
		return hoverTimer
	end
	button.IsMouseOver = function() return overBook end
	viewer.IsMouseOver = function() return overViewer end
	local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
	own, overBook = false, true
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	enter(button)
	leave(button)
	assert(hoverTimer.cancelled and not viewer:IsShown() and #messages == sent, "passing over the book sends no request")
	enter(button)
	hoverTimer:Fire()
	assert(viewer:IsShown() and reads[#reads] == loading and #messages == sent + 1, "hover requests and opens the target profile")
	local update = viewer:GetScript("OnUpdate")
	overBook = false
	update(viewer, 0.15)
	overViewer = true
	update(viewer, 0.5)
	assert(viewer:IsShown(), "the preview stays open while crossing into and reading the window")
	click()
	assert(viewer:IsShown() and not viewer:GetScript("OnUpdate") and #messages == sent + 1, "click pins the existing preview without requesting it again")
	click()
	assert(not viewer:IsShown(), "the pinned preview closes with a second click")
	overBook, overViewer = true, false
	enter(button)
	hoverTimer:Fire()
	overBook = false
	viewer:GetScript("OnUpdate")(viewer, 0.4)
	assert(not viewer:IsShown() and not viewer:GetScript("OnUpdate"), "the preview closes after the pointer leaves the book and window")
	C_Timer.NewTimer = oldNewTimer

	rp.db.enabled = false
	rp:OnOptionChanged()
	local before = #messages
	Deliver("Q:aca456", "Reader-LocalRealm")
	assert(not button:IsShown() and not viewer:IsShown() and #messages == before, "disabling hides the UI and stops sharing")

	local oldTipUnit, oldTipAdd, oldRefresh = GameTooltip.GetUnit, GameTooltip.AddLine, ns.RefreshGameTooltip
	local oldBit, oldOwner = rawget(_G, "bit"), rawget(_G, "msp_RPAddOn")
	local function Bitwise(a, b, xor)
		local result, place = 0, 1
		while a > 0 or b > 0 do
			local left, right = a % 2, b % 2
			if (xor and left ~= right) or (not xor and left == 1 and right == 1) then result = result + place end
			a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
		end
		return result
	end
	bit = { band = Bitwise, bxor = function(a, b) return Bitwise(a, b, true) end,
		rshift = function(a, count) return math.floor(a / 2 ^ count) end }
	local actor, unit, refreshes, tipLines = "Wren", "mouseover", 0, {}
	local wasShown = GameTooltip:IsShown()
	GameTooltip:Show()
	UnitFullName = function() return actor, "Test Realm" end
	GameTooltip.GetUnit = function() return actor, unit end
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = line end
	ns.RefreshGameTooltip = function() refreshes = refreshes + 1 end
	local mspOut = {}
	local function SendMSP(logged, prefix, text, channel, target)
		assert(prefix == "MSP2" and #text <= 255 and channel == "WHISPER")
		assert(text:find("^00A%x%x%x%x%x%x%x%x%x"))
		mspOut[#mspOut + 1] = { text = text, logged = logged, target = target }
		return 0
	end
	local registerNative, sendNative = C_ChatInfo.RegisterAddonMessagePrefix, C_ChatInfo.SendAddonMessage
	C_ChatInfo.RegisterAddonMessagePrefix = function(prefix)
		if prefix == "MSP2" then return 0 end
		return registerNative(prefix)
	end
	C_ChatInfo.SendAddonMessage = function(prefix, ...)
		if prefix == "MSP2" then return SendMSP(false, prefix, ...) end
		return sendNative(prefix, ...)
	end
	C_ChatInfo.SendAddonMessageLogged = function(...) return SendMSP(true, ...) end
	local function MSPMessage(text, logged, sender, seq, length)
		local event = logged and "CHAT_MSG_ADDON_LOGGED" or "CHAT_MSG_ADDON"
		onEvent(nil, event, "MSP2", ("00ABCD%03X%03X%s"):format(seq or 1, length or 1, text),
			"WHISPER", sender or "Wren-TestRealm")
	end

	rp.db.enabled, rp.cdb.shared = true, false
	rp:OnOptionChanged()
	now = now + 20
	MSPMessage("?TT", false)
	assert(#mspOut == 0, "MSP never publishes a private profile")
	own = true
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Émeline" and tipLines[2]:find("Bergführerin", 1, true) and #mspOut == 0,
		"the own tooltip shows the saved name and occupation even for a private profile")
	own, tipLines = false, {}
	profileTooltip(GameTooltip)
	profileTooltip(GameTooltip)
	assert(#tipLines == 0 and #mspOut == 1 and not mspOut[1].logged
		and mspOut[1].target == "Wren-TestRealm" and mspOut[1].text:sub(13) == "?TT`?PX`?RC",
		"the player tooltip sends a throttled request for MSP summary fields")

	MSPMessage("NA:Unsolicited", true, "Wren-LocalRealm")
	MSPMessage("NA:Unlogged", false)
	assert(refreshes == 0, "a wrong-realm or unlogged MSP response cannot refresh the tooltip")
	MSPMessage("NA:~7Ccfffafa00Sire Élan~7Cr`PX:Sire`RC:Waldläufer`TT1234", true)
	assert(refreshes == 1, "the MSP response refreshes the current player tooltip")
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Sire Élan" and tipLines[2] == "Waldläufer",
		"the tooltip strips colour codes and uses the RP class if the short title is already part of the name")

	click()
	assert(#mspOut == 2 and mspOut[2].text:find("?HI", 13, true), "the target book also requests the full external profile")
	local prior = #reads
	MSPMessage("~7CLink~7C", true, nil, 2, 2)
	assert(#reads == prior, "profile waits for all parts")
	MSPMessage("NT:Hüterin`HB:Westfall`HH:Stormwind`DE:Beschreibung`PE:Silberner Ring`HI8AB1:Zeile~0A", true, nil, 1, 2)
	assert(reads[#reads]:find("Hüterin", 1, true) and reads[#reads]:find("Westfall", 1, true)
		and reads[#reads]:find("Stormwind", 1, true) and reads[#reads]:find("Beschreibung", 1, true)
		and reads[#reads]:find("Silberner Ring", 1, true)
		and reads[#reads]:find("Zeile\n||Link||", 1, true),
		"the target book maps external fields and displays escaped UTF-8 text")
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[2] == "Hüterin", "the long title takes precedence over the RP class")
	actor = "SomeoneElse"
	local beforeRefresh = refreshes
	MSPMessage("NT:New Title", true)
	assert(refreshes == beforeRefresh, "an answer never refreshes another player's tooltip")
	click()

	rp.cdb.shared = true
	local savedStory = rp.cdb.profile.story
	rp.cdb.profile.story = ("é~\\\n"):rep(175) .. "Ende"
	now = now + 20
	local first = #mspOut + 1
	MSPMessage("?VA`?NA`?NT`?HB`?HH`?HI", false)
	local wire = ns.RoleplayMSP
	local payload, fragments = nil, {}
	for index = first, #mspOut do
		local packet = mspOut[index]
		assert(packet.logged and packet.target == "Wren-TestRealm")
		payload = wire.Packet(packet.text, true, fragments) or payload
	end
	assert(#mspOut > first and payload, "the logged profile response is split into Chomp packets")
	local _, fields = wire.Commands(payload, true)
	assert(fields.VP == "3" and fields.VA == "ForeverPlus/" .. ns.version and fields.NA == "Émeline"
		and fields.NT == rp.cdb.profile.occupation and fields.HB == rp.cdb.profile.birthplace
		and fields.HH == rp.cdb.profile.residence and fields.HI == rp.cdb.profile.story,
		"other RP addons receive all five enabled fields, including multiline UTF-8 and codec characters")
	msp_RPAddOn = "Other RP"
	first = #mspOut
	MSPMessage("?TT", false)
	assert(#mspOut == first, "another local MSP addon owns the MSP answers")
	msp_RPAddOn = oldOwner
	local sendLogged = C_ChatInfo.SendAddonMessageLogged
	Enum.SendAddonMessageResult.AddonMessageThrottle = 3
	C_ChatInfo.SendAddonMessageLogged = function() return 3 end
	now, timeout = now + 20, nil
	MSPMessage("?TT", false)
	assert(timeout, "a throttled MSP reply schedules a retry")
	local retry = timeout
	C_ChatInfo.SendAddonMessageLogged = sendLogged
	rp.cdb.shared = false
	retry()
	assert(#mspOut == first, "an already queued reply stops when profile sharing is turned off")
	rp.cdb.shared = true
	rp.cdb.profile.story = savedStory

	rp.db.compatibleProfiles = false
	rp:OnOptionChanged("compatibleProfiles")
	MSPMessage("?TT", false)
	assert(#mspOut == first, "the compatibility toggle stops MSP replies")
	now = now + 20
	local nativeBefore = #messages
	profileTooltip(GameTooltip)
	assert(#messages == nativeBefore + 1 and #mspOut == first, "the tooltip uses native queries when MSP is off")
	local id = messages[#messages].text:sub(3)
	Deliver("Q:" .. id, "Reader")
	for index = nativeBefore + 2, #messages do Deliver(messages[index].text, "SomeoneElse-TestRealm") end
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Émeline", "the tooltip displays a native ForeverPlus profile")
	rp.db.profileTooltip = false
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(#tipLines == 0, "the tooltip option switches off both RP lines")
	rp.db.profileTooltip, rp.db.compatibleProfiles = true, true

	-- Forever units return a surname, while a message can append an internal realm to its sender.
	setuv(rp.OnLogin, "regionalNames", true)
	UnitFullName = function() return "Wren", "Stonefist" end
	rp:OnOptionChanged("compatibleProfiles")
	now = now + 20
	click()
	assert(mspOut[#mspOut].target == "Wren Stonefist" and messages[#messages].target == "Wren Stonefist",
		"Forever whispers address the full regional character name")
	local displayed = #reads
	MSPMessage("NA:Other profile", true, "Wren Birch-CAMWOW EU4 Realm 7 PvE")
	assert(#reads == displayed, "another character with the same first name cannot answer")
	MSPMessage("NA:Élan of Westfall`NT:Hüterin`HB:Westfall", true, "Wren Stonefist-CAMWOW EU4 Realm 7 PvE")
	assert(reads[#reads]:find("Élan of Westfall", 1, true), "a realm-decorated Forever reply matches the open profile")
	UnitFullName = function() return "Wren Stonefist", "CAMWOW EU4 Realm 7 PvE" end
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Élan of Westfall" and tipLines[2] == "Hüterin",
		"the tooltip uses the same regional character key as the profile response")
	now = now + 20
	MSPMessage("?TT", false, "Reader Oak-CAMWOW EU4 Realm 7 PvE")
	assert(mspOut[#mspOut].logged and mspOut[#mspOut].target == "Reader Oak", "MSP replies strip the sender's internal realm")
	local activeProfile = rp.cdb.profile
	rp.cdb.profile = { name = "Émeline" }
	Deliver("Q:abc123", "Reader Oak-CAMWOW EU4 Realm 7 PvE")
	assert(messages[#messages].target == "Reader Oak" and messages[#messages].text:find("^P:abc123:"),
		"native replies also use the regional whisper name")
	rp.cdb.profile = activeProfile
	click()

	UnitFullName = function() return "Doran", "Amber" end
	now = now + 20
	local beforeProbe = #mspOut
	click()
	assert(timeoutDelay == 3, "a silent MSP target stops showing the loading message after three seconds")
	now = now + timeoutDelay
	timeout()
	assert(#mspOut == beforeProbe + 1 and reads[#reads] == ns.L.RP_NO_REPLY, "an unanswered MSP request shows its status")
	click()
	now = now + 16
	click()
	assert(#mspOut == beforeProbe + 1, "manual reopening does not resend during the response window")
	click()
	now = now + 1
	click()
	assert(#mspOut == beforeProbe + 2, "manual reopening can retry an unanswered MSP query once the response window ends")
	now = now + timeoutDelay
	timeout()
	assert(reads[#reads] == ns.L.RP_NO_REPLY)
	now = now + 7
	MSPMessage("NA:Doran of Ironforge", true, "Doran Amber")
	assert(reads[#reads]:find("Doran of Ironforge", 1, true), "an MSP reply still replaces the status after ten seconds")
	click()

	local workingSend = C_ChatInfo.SendAddonMessage
	C_ChatInfo.SendAddonMessage = function() return 7 end
	UnitFullName = function() return "Aldren", "Ash" end
	now = now + 20
	click()
	assert(reads[#reads] == ns.L.RP_SEND_FAILED, "the book reports a client send failure on both transports immediately")
	click()
	C_ChatInfo.SendAddonMessage = workingSend
	setuv(rp.OnLogin, "regionalNames", false)

	GameTooltip.GetUnit, GameTooltip.AddLine, ns.RefreshGameTooltip = oldTipUnit, oldTipAdd, oldRefresh
	GameTooltip:SetShown(wasShown)
	bit = oldBit

	visuals.db.playerDragon, visuals.db.dragonScale = oldDragon, oldScale
	setuv(visuals.ApplyPlayerDragon, "dragonButtons", oldGroup)
	setuv(visuals.ApplyPlayerDragon, "dragon", oldArt)
	visuals.ApplyPlayerDragon()
	for key, value in pairs(originals) do _G[key] = value end
	C_Timer.After, ns.IsEditModeActive = oldAfter, oldEditMode
	Enum.RegisterAddonMessagePrefixResult, Enum.SendAddonMessageResult = oldRegister, oldSend
	rp.db.enabled, rp.cdb.shared, rp.cdb.profile = true, false, {}
	print("roleplay editor, native and MSP profile exchange, and player tooltip OK")
end)()

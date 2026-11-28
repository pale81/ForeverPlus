(function()
	-- dialog bubble: views and rendering
	local dialog = ns:GetModule("Dialog")
	dialog.db.enabled = true
	issecretvalue = function() return false end
	UnitName = function() return "Torwächter" end
	UnitExists = function() return false end
	InCombatLockdown = function() return false end
	C_GossipInfo = {
		GetText = function() return "Seid gegrüßt, Reisender." end,
		GetOptions = function() return { { gossipOptionID = 5, name = "Ich möchte reisen.", icon = 1 } } end,
		GetActiveQuests = function() return { { title = "Fertig", questID = 1, isComplete = true } } end,
		GetAvailableQuests = function() return { { title = "Neu", questID = 2 } } end,
	}
	local view = dialog.GossipView()
	assert(view.name == "Torwächter" and #view.blocks == 2 and #view.blocks[2].rows == 3, "gossip view rows " .. tostring(view.name) .. " " .. #view.blocks)
	GetTitleText = function() return "Die Jagd" end
	GetQuestText = function() return "Erlegt zehn Eber." end
	GetObjectiveText = function() return "Tötet 10 Eber." end
	GetProgressText = function() return "Habt Ihr sie?" end
	GetRewardText = function() return "Gut gemacht." end
	GetNumQuestChoices = function() return 2 end
	GetNumQuestRewards = function() return 1 end
	GetNumQuestItems = function() return 1 end
	GetQuestItemInfo = function() return "Ding", 134400, 2, 2 end
	GetRewardMoney = function() return 250 end
	GetRewardXP = function() return 100 end
	GetQuestMoneyToGet = function() return 0 end
	IsQuestCompletable = function() return true end
	QuestFlagsPVP = function() return false end
	QuestGetAutoAccept = function() return false end
	C_Item.GetItemQualityColor = function() return 0, 1, 0 end
	for event in pairs({ GOSSIP_SHOW = 1, QUEST_DETAIL = 1, QUEST_PROGRESS = 1, QUEST_COMPLETE = 1 }) do
		local ok, err = pcall(dialog.OnConversation, dialog, event)
		assert(ok, event .. ": " .. tostring(err))
	end
	-- back: gossip first, then a quest detail; "back" shows the gossip step again
	dialog:OnConversation("GOSSIP_SHOW")
	local bubble = ForeverPlusDialogBubble
	local rows = bubble.pools.row
	assert(rows[1].Glow and not rows[2].Glow and not rows[1].Qty and not rows[2].Qty,
		"fresh gossip rows only create the selected glow and no quantity fields")
	bubble.selectedRow = 2
	dialog.Rerender()
	assert(not rows[1].Glow[1]:IsShown() and rows[2].Glow[1]:IsShown(), "selection moves the glow")
	local active = uv(dialog.Rerender, "current").view.blocks[2].rows[2]
	active.counter = 2
	dialog.Rerender()
	local quantity = rows[2].Qty
	assert(quantity and quantity:IsShown(), "a row creates its quantity field when needed")
	active.counter = nil
	dialog.Rerender()
	assert(rows[2].Qty == quantity and not quantity:IsShown(), "a reused row hides the quantity field")
	dialog:OnConversation("QUEST_DETAIL")
	assert(pcall(dialog.GoBack), "back runs")
	GetQuestID = function() return 77 end
	assert(pcall(dialog.OnConversation, dialog, "QUEST_PROGRESS"), "progress with abandon")
	assert(pcall(dialog.AbandonQuest, 77), "abandon runs")
	local reward = dialog.RewardView()
	assert(#reward.buttons == 2 and reward.blocks[3].choose, "reward choice")
	-- A long reward page must survive clicks, late item data, and a repeated event for that quest.
	local savedHeight, savedBest, savedReward, savedQuestID =
		bubble.pools.text[2].GetStringHeight, ns.BestQuestChoice, GetQuestReward, GetQuestID
	local refreshReward, claimed
	bubble.pools.text[2].GetStringHeight = function() return 260 end
	ns.BestQuestChoice = function(onLoaded) refreshReward = onLoaded end
	GetQuestReward = function(choice) claimed = choice end
	dialog:OnConversation("QUEST_COMPLETE")
	bubble:Show() -- the harness does not create a nameplate for the quest giver
	bubble:GetScript("OnMouseWheel")(bubble, -20)
	local offset = bubble.Scroll:GetVerticalScroll()
	assert(offset > 0, "long reward page scrolls")
	local choice = bubble.pools.item[2]
	choice:GetScript("OnClick")(choice)
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "choosing keeps the rewards in view")
	refreshReward()
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "late item data preserves position")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "reopening the same reward page keeps the choice")
	uv(dialog.Rerender, "current").view.buttons[1].action()
	assert(claimed == 2, "completing the refreshed quest hands in with the selected reward")
	GetQuestID = function() return 78 end
	dialog:OnConversation("QUEST_COMPLETE")
	assert(not choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == 0, "a different quest starts fresh")
	bubble.pools.text[2].GetStringHeight, ns.BestQuestChoice, GetQuestReward, GetQuestID =
		savedHeight, savedBest, savedReward, savedQuestID
	dialog.db.style = "DARK"
	assert(pcall(dialog.OnConversation, dialog, "QUEST_DETAIL"), "dark style")
	dialog.db.enabled = false
	print("dialog OK")
end)()
;(function()
	-- Voiced lines stay compact after completion, even in voice-only mode.
	local dialog = ns:GetModule("Dialog")
	local blocks = { { title = "Die Jagd" }, { text = "Worte", speech = true }, { text = "Ziel", objective = true },
		{ text = "Noch nicht", dim = true }, { rows = {} }, { items = {} }, { money = "5s" } }
	local kept = dialog.WithoutWords(blocks)
	assert(#kept == 4 and kept[1].dim and kept[2].rows and kept[3].items and kept[4].money, "title, words and objective dropped")
	assert(#blocks == 7, "the view's own blocks stay whole")
	local saved = _G.Spoken
	local clip, notifyAudio, notifyStopped, paused
	_G.Spoken = {
		IsCompatible = function() return true end,
		ShowsNarratorFor = function() return false end, -- "voice only"
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil and not paused end,
		IsPaused = function() return paused == true end,
		RegisterCallback = function(_, event, fn)
			if event == "AUDIO_CHANGED" then
				assert(not notifyAudio, "subscribe once to playback changes")
				notifyAudio = fn
			elseif event == "CLIP_STOPPED" then
				notifyStopped = fn
			end
		end,
	}
	local wasExists, wasEnabled, wasPortrait, savedDraw = UnitExists, dialog.db.enabled, dialog.db.portrait, SetPortraitTexture
	local faceUnit
	SetPortraitTexture = function(_, unit) faceUnit = unit end
	UnitExists = function(unit) return unit == "npc" end
	UnitGUID = function() return "Creature-0-0-0-0-1-0" end
	UnitName = function() return "Torwächter" end
	issecretvalue = function() return false end
	InCombatLockdown = function() return false end
	C_GossipInfo = {
		GetText = function() return "Seid gegrüßt, Reisender." end,
		GetOptions = function() return { { gossipOptionID = 5, name = "Ich möchte reisen.", icon = 1 } } end,
		GetActiveQuests = function() return { { title = "Fertig", questID = 1, isComplete = true } } end,
		GetAvailableQuests = function() return { { title = "Neu", questID = 2 } } end,
	}
	dialog.db.enabled, dialog.db.portrait = true, true
	dialog:OnConversation("GOSSIP_SHOW")
	local bubble = ForeverPlusDialogBubble
	assert(not bubble.Portrait:IsShown() and bubble.lastUsed.text == 2, "the words remain while no clip is playing")
	clip = { source = { key = "gossip" }, text = "Different dialogue.", unitGUID = UnitGUID("npc") }
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "an unrelated voiceover keeps the text visible")
	clip.text = C_GossipInfo.GetText()
	notifyAudio()
	assert(bubble.Portrait:IsShown() and faceUnit == "npc", "voice-only playback shows the speaker's face")
	assert(bubble.lastUsed.text == 0 and bubble.lastUsed.row == 3, "the three choices stay visible")
	paused = true
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and bubble.lastUsed.text == 2, "a paused clip leaves the words visible")
	paused = false
	clip.textOnly = true
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "a silent clip without a narrator does not replace the words")
	clip.textOnly = false
	dialog.db.portrait = false
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "option off: full bubble")
	dialog.db.portrait = true
	UnitExists = function(unit) return unit == "questnpc" end
	dialog:OnConversation("QUEST_COMPLETE")
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText(), unitGUID = UnitGUID("questnpc") }
	notifyAudio()
	assert(bubble.Portrait:IsShown() and faceUnit == "questnpc" and bubble.lastUsed.item == 3, "quest portrait preserves rewards")
	local item = bubble.pools.item[2]
	item:GetScript("OnClick")(item)
	local height = bubble.pools.text[2].GetStringHeight
	bubble.pools.text[2].GetStringHeight = function() return 260 end
	notifyStopped(clip, true)
	clip = nil
	notifyAudio()
	assert(bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.wordsHidden,
		"completed speech stays hidden and preserves the selected reward")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.wordsHidden,
		"refreshing the same reward page does not restore completed speech")
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText() }
	notifyStopped(clip, false)
	clip = nil
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() > 0,
		"interrupted speech remains readable and the selected reward stays in view")
	bubble.pools.text[2].GetStringHeight = height
	UnitExists = function() return false end
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText() }
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and bubble.wordsHidden, "a missing portrait does not repeat spoken words")
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	UnitExists, SetPortraitTexture = wasExists, savedDraw
	_G.Spoken = saved
	print("dialog portrait OK")
end)()
;(function()
	-- Resolve automatic speech before drawing, including delayed and failed starts.
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedReader, savedAfter = _G.Spoken, _G.VoiceOver, C_Timer.After
	local savedGossip, savedExists, savedGUID = C_GossipInfo, UnitExists, UnitGUID
	local wasEnabled, wasPortrait = dialog.db.enabled, dialog.db.portrait
	local clip, queue, startup, lookup, autoplay, available = nil, {}, nil, 0, true, true
	local lineText = "Diese Zeile kommt gleich."
	local callbacks = {}
	local guid = "Creature-0-1-1-1-1-1"
	local function Voice(text)
		return { source = { key = "gossip" }, text = text or C_GossipInfo.GetText(), unitGUID = guid }
	end
	_G.Spoken = {
		GetNowPlaying = function() return clip end,
		GetQueue = function() return queue end,
		IsPlaying = function() return clip ~= nil end,
		RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
	}
	_G.VoiceOver = { Addon = {
		IsAutoplayOn = function() return autoplay end,
		GetVisibleLine = function(_, event)
			lookup = lookup + 1
			if event == "QUEST_COMPLETE" then
				return { text = GetRewardText(), questID = GetQuestID(), unitGUID = guid }
			end
			assert(event == "GOSSIP_SHOW")
			return available and Voice() or nil
		end,
	} }
	C_Timer.After = function(delay, fn) if delay == 1.5 then startup = fn end end
	UnitExists = function(unit) return unit == "npc" end
	UnitGUID = function() return guid end
	C_GossipInfo = {
		GetText = function() return lineText end,
		GetOptions = function() return { { name = "Weiter.", gossipOptionID = 11 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
	}
	dialog.db.enabled, dialog.db.portrait = true, true
	dialog:OnConversation("GOSSIP_SHOW")
	local frame = ForeverPlusDialogBubble
	assert(frame.wordsHidden and frame.lastUsed.row == 1 and startup, "no text flash before automatic speech")
	dialog.Rerender()
	assert(lookup == 1, "recording lookup runs once per page")
	queue = { Voice() }
	startup()
	assert(frame.wordsHidden, "a queued line remains hidden beyond the startup timeout")
	clip = Voice("Eine andere Zeile.")
	callbacks.AUDIO_CHANGED()
	assert(frame.wordsHidden, "another playing line does not reveal the queued page")
	queue = {}
	clip = Voice()
	callbacks.AUDIO_CHANGED()
	callbacks.CLIP_STOPPED(clip, true)
	clip = nil
	callbacks.AUDIO_CHANGED()
	assert(frame.wordsHidden and frame.lastUsed.row == 1, "no text returns after successful playback")
	dialog:OnConversation("GOSSIP_SHOW")
	assert(frame.wordsHidden and lookup == 1, "a duplicate gossip event does not repeat completed speech")
	available = false
	lineText = "Eine andere Seite ohne Aufnahme."
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not frame.wordsHidden and frame.lastUsed.text == 2, "a missing recording remains readable immediately")
	available, autoplay = true, false
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not frame.wordsHidden, "autoplay off keeps the text readable")
	autoplay = true
	dialog:OnConversation("GOSSIP_SHOW")
	startup()
	assert(not frame.wordsHidden, "a resolved recording that never starts falls back to text")
	dialog:OnConversation("GOSSIP_SHOW")
	callbacks.CLIP_DROPPED(Voice(), "missing")
	callbacks.AUDIO_CHANGED()
	assert(not frame.wordsHidden, "a dropped recording restores text immediately")
	dialog:OnConversation("QUEST_COMPLETE")
	local rewardStartup = startup
	assert(frame.wordsHidden, "a resolved quest recording is hidden before starting")
	dialog:OnConversation("QUEST_COMPLETE")
	rewardStartup()
	assert(not frame.wordsHidden, "refreshing a reward page does not leave its startup timeout stuck")
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	_G.Spoken, _G.VoiceOver, C_Timer.After = savedSpoken, savedReader, savedAfter
	C_GossipInfo, UnitExists, UnitGUID = savedGossip, savedExists, savedGUID
	print("dialog voice lifecycle OK")
end)()
;(function()
	-- Small book button in portrait mode: toggles the NPC's words below the face,
	-- analogous to unvoiced bubbles (including textSpeed reveal and scroll layout).
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedExists, savedGUID = _G.Spoken, UnitExists, UnitGUID
	local savedGossip = C_GossipInfo
	local wasEnabled, wasPortrait = dialog.db.enabled, dialog.db.portrait
	local wasPortraitText, wasSpeed = dialog.db.portraitText, dialog.db.textSpeed
	local clip, notifyAudio
	_G.Spoken = {
		IsCompatible = function() return true end,
		ShowsNarratorFor = function() return false end,
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil end,
		IsPaused = function() return false end,
		RegisterCallback = function(_, event, fn)
			if event == "AUDIO_CHANGED" then notifyAudio = fn end
		end,
	}
	local guid = "Creature-0-1-1-1-9-1"
	UnitExists = function(unit) return unit == "npc" or unit == "questnpc" end
	UnitGUID = function() return guid end
	C_GossipInfo = {
		GetText = function() return "Willkommen in Sturmwind, Abenteurer." end,
		GetOptions = function() return { { gossipOptionID = 7, name = "Zeigt mir den Weg.", icon = 1 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
	}
	dialog.db.enabled, dialog.db.portrait, dialog.db.portraitText, dialog.db.textSpeed = true, true, false, "INSTANT"
	local bubble = ForeverPlusDialogBubble
	local scrollPoint, bookDesat
	local origScrollSetPoint = rawget(bubble.Scroll, "SetPoint")
	local origIconDesat = rawget(bubble.TextToggle.Icon, "SetDesaturated")
	bubble.Scroll.SetPoint = function(_, ...) scrollPoint = { ... } end
	bubble.TextToggle.Icon.SetDesaturated = function(_, v) bookDesat = v end
	-- Without Spoken clip: text is already shown, portrait and book button stay hidden.
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not bubble.Portrait:IsShown() and not bubble.TextToggle:IsShown(), "no book button without voice")
	assert(not bubble.wordsHidden and bubble.lastUsed.text == 2, "unvoiced bubble shows name and speech")
	-- Spoken starts reading: portrait and book button appear, text hidden by default.
	clip = { source = { key = "gossip" }, text = C_GossipInfo.GetText(), unitGUID = guid }
	notifyAudio()
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown(), "voiced bubble shows portrait and book button")
	assert(bubble.wordsHidden and bubble.lastUsed.text == 0 and bookDesat == true, "text hidden and book grey initially")
	assert(scrollPoint and scrollPoint[5] == -78, "scroll sits directly under the portrait")
	-- Clicking the book button displays the text below the face while keeping the portrait.
	bubble.TextToggle:GetScript("OnClick")(bubble.TextToggle)
	assert(dialog.db.portraitText == true and not bubble.wordsHidden, "book click enables portrait text")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and bookDesat == false,
		"portrait stays visible and book lights up in colour")
	assert(bubble.lastUsed.text == 2 and bubble.lastUsed.row == 1, "name, speech and choice render under the face")
	assert(scrollPoint and scrollPoint[5] == -78, "text area remains anchored under the portrait")
	-- Slow text reveal works on a fresh voiced step with portraitText enabled, analogous to without Spoken.
	dialog.db.textSpeed = "SLOW"
	local speechText
	local text2 = bubble.pools.text[2]
	local origSetText = rawget(text2, "SetText")
	text2.SetText = function(_, t) speechText = t end
	local freshLine = "Dies ist ein neuer gesprochener Satz fuer den Test."
	C_GossipInfo.GetText = function() return freshLine end
	clip = { source = { key = "gossip" }, text = freshLine, unitGUID = guid }
	dialog:OnConversation("GOSSIP_SHOW")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"fresh voiced gossip keeps portrait and shows text when book is active")
	assert(speechText == "", "slow reveal starts empty on fresh step, analogous to unvoiced mode")
	local onUpdate = bubble:GetScript("OnUpdate")
	assert(onUpdate, "slow reveal update is active")
	onUpdate(bubble, 1)
	assert(type(speechText) == "string" and #speechText > 0, "slow reveal advances words below portrait")
	text2.SetText = origSetText
	-- Quest detail also renders title, speech and objectives below the portrait when active.
	dialog.db.textSpeed = "INSTANT"
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetQuestText(), unitGUID = guid }
	dialog:OnConversation("QUEST_DETAIL")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"quest detail keeps portrait and shows text when book is active")
	assert(bubble.lastUsed.text >= 3, "quest name, title and speech render below portrait")
	-- Clicking the book button again hides the text, keeping the portrait.
	bubble.TextToggle:GetScript("OnClick")(bubble.TextToggle)
	assert(dialog.db.portraitText == false and bubble.wordsHidden, "second click hides text again")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and bookDesat == true,
		"portrait remains and book returns to grey")
	-- When Spoken stops (not reading), portrait and book button hide and text returns.
	clip = nil
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and not bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"book button hides when voice stops")
	bubble.Scroll.SetPoint = origScrollSetPoint
	bubble.TextToggle.Icon.SetDesaturated = origIconDesat
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	dialog.db.portraitText, dialog.db.textSpeed = wasPortraitText, wasSpeed
	_G.Spoken, UnitExists, UnitGUID, C_GossipInfo = savedSpoken, savedExists, savedGUID, savedGossip
	print("dialog portrait text book OK")
end)()
;(function()
	-- Exercise the narrator renderer contract and bounded asynchronous model loading.
	local portrait, saved = ns.DialogPortrait, _G.Spoken
	local holder = { Face = NewFrame("Texture"), Scene = false }
	holder.Face.w, holder.Face.h = 64, 64
	local savedCreate = CreateFrame
	CreateFrame = function(...)
		local frame = savedCreate(...)
		frame.SetSize = function(self, width, height) self.w, self.h = width, height end
		return frame
	end
	local model = NewFrame("DressUpModel")
	local file, acquired, updated, released, animated = nil, 0, 0, 0, 0
	model.GetModelFileID = function() return file end
	model:SetScript("OnUpdate", function() animated = animated + 1 end)
	local renderer = {
		Acquire = function() acquired = acquired + 1 model:Show() return model end,
		Update = function(_, _, spec) updated = updated + 1 assert(spec.creatureID == 1) return file ~= nil end,
		Release = function() released = released + 1 model:Hide() end,
	}
	_G.Spoken = { GetPortraitRenderer = function(_, kind) assert(kind == "model") return renderer end }
	local clip = { present = { portrait = { kind = "model", creatureID = 1 } } }
	local animate = model:GetScript("OnUpdate")
	portrait.Update(holder, clip, true)
	local tick = holder.Scene:GetScript("OnUpdate")
	assert(holder.Scene:GetWidth() == 64 and holder.Scene:GetHeight() == 64,
		"use the entire face viewport instead of cropping the beard in an inscribed square")
	assert(holder.Face:IsShown() and model:GetAlpha() == 0 and not holder.Cover:IsShown(),
		"keep the still portrait while the model loads")
	tick(model, 0.5)
	assert(updated == 1 and model:GetScript("OnUpdate") == animate, "load once and retain the renderer's animation script")
	file = 119563
	tick(model, 0.1)
	model:GetScript("OnUpdate")(model, 0.1)
	assert(not holder.Face:IsShown() and model:GetAlpha() == 1 and animated == 1 and holder.Cover:IsShown(),
		"animate a loaded model with its circular cover above it")
	portrait.Update(holder, clip, true)
	assert(acquired == 1 and updated == 1, "redrawing the same clip does not reload the model")
	portrait.Update(holder, nil, true)
	assert(holder.Face:IsShown() and not model:IsShown() and not holder.Cover:IsShown()
		and not holder.Scene:GetScript("OnUpdate") and released == 1,
		"finishing or pausing releases the model and stops its updates")
	file = nil
	portrait.Update(holder, clip, true)
	holder.Scene:GetScript("OnUpdate")(holder.Scene, 2.1)
	assert(not model:IsShown() and holder.Face:IsShown() and released == 2, "abandon an unloaded model after two seconds")
	portrait.Update(holder, clip, true)
	assert(acquired == 2, "a failed clip is not retried by every redraw")
	local other = { present = clip.present }
	portrait.Update(holder, other, false)
	assert(acquired == 2, "the animation option prevents model acquisition")
	portrait.Update(holder, other, true)
	portrait.Stop(holder)
	assert(not model:IsShown() and not holder.Scene:GetScript("OnUpdate") and released == 3, "closing stops a pending load")
	_G.Spoken, CreateFrame = saved, savedCreate
	print("dialog portrait renderer OK")
end)()
;(function()
	-- Voice-only dialogue keeps choices and only provides subtitles for unread speech.
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedCommand, savedCreate = _G.Spoken, SlashCmdList.SPOKEN, CreateFrame
	local savedGUID, savedExists, savedGossip = UnitGUID, UnitExists, C_GossipInfo
	local wasEnabled, wasCinematic = dialog.db.enabled, dialog.db.cinematic
	local guid = "Creature-0-1-1-1-1-1"
	local clip, selected, modelCreated
	local callbacks = {}
	local style = "subtitle"
	_G.Spoken = {
		GetPlayerStyle = function() return style end,
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil end,
		RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
	}
	SlashCmdList.SPOKEN = function(command)
		assert(command == "style voice" or command == "style subtitles", command)
		style = command == "style voice" and "none" or "subtitle"
	end
	CreateFrame = function(kind, name, ...)
		if kind == "DressUpModel" or kind == "PlayerModel" or kind == "ModelScene" or kind == "Model" then
			modelCreated = true
		end
		return savedCreate(kind, name, ...)
	end
	UnitExists = function(unit) return unit == "npc" or unit == "target" end
	UnitGUID = function(unit) return UnitExists(unit) and guid or nil end
	C_GossipInfo = {
		GetText = function() return "Ein Text ohne Aufnahme." end,
		GetOptions = function() return { { name = "Weiter.", gossipOptionID = 17 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
		SelectOption = function(id) selected = id end,
	}
	dialog.db.enabled, dialog.db.cinematic = true, true
	dialog:Apply()
	dialog:OnConversation("GOSSIP_SHOW")
	local frame = ForeverPlusDialogBubble
	assert(style == "none" and frame:IsShown() and not frame.Dark:IsShown() and not frame.Portrait:IsShown(),
		"voice only and floating controls without a nameplate or bubble")
	assert(frame.Subtitles:IsShown() and frame.Subtitles.text:find(C_GossipInfo.GetText(), 1, true),
		"unvoiced text stays visible in a separate subtitle")
	assert(frame.pools.row[1].ButtonBack:IsShown() and #frame.rowActions == 1, "the dialogue choice is a separate button")
	local voice = { source = { key = "gossip" }, unitGUID = guid, text = C_GossipInfo.GetText(),
		present = { portrait = { kind = "model", displayID = 123 } } }
	clip = voice
	callbacks.AUDIO_CHANGED()
	assert(not frame.Subtitles:IsShown() and frame.pools.row[1]:IsShown(), "while speaking, only the choices remain")
	clip = nil
	callbacks.AUDIO_CHANGED()
	assert(frame.Subtitles:IsShown(), "an interrupted voice restores the unread text")
	clip = voice
	callbacks.AUDIO_CHANGED()
	clip = nil
	callbacks.CLIP_STOPPED(voice, true)
	callbacks.AUDIO_CHANGED()
	assert(not frame.Subtitles:IsShown(), "a fully read page keeps only the choices")
	assert(not modelCreated, "dialogue playback never creates a 3D model")
	local row = frame.pools.row[1]
	row:GetScript("OnClick")(row, "LeftButton")
	assert(selected == 17, "the floating button selects the same dialogue option")
	dialog.db.cinematic = false
	dialog:Apply()
	assert(style == "subtitle" and not frame.Subtitles:IsShown() and not frame.pools.row[1].ButtonBack:IsShown(),
		"disabling restores the reader style and ordinary dialogue layout")
	dialog.db.enabled, dialog.db.cinematic = wasEnabled, wasCinematic
	dialog:Apply()
	_G.Spoken, SlashCmdList.SPOKEN, CreateFrame = savedSpoken, savedCommand, savedCreate
	UnitGUID, UnitExists, C_GossipInfo = savedGUID, savedExists, savedGossip
	print("dialog subtitles without 3D models OK")
end)()
;(function()
	-- reputation flash and trivial messages
	local flash = ns:GetModule("RepFlash")
	local ok, err = pcall(flash.Add, flash, "Eisenschmiede", 25)
	assert(ok, tostring(err))
	assert(pcall(flash.Add, flash, "Orgrimmar", -10), "second change merges")
	for index = 1, 5 do
		assert(pcall(flash.Add, flash, "Fraktion" .. index, 10 * index), "more than three lines make pages")
	end
	-- the colour of the numbers: class colour for gains, red for losses
	flash.db.classColor = true
	flash.db.xp = true
	assert(pcall(flash.Add, flash, "Eisenschmiede", 25), "rep in class colour")
	assert(pcall(flash.Add, flash, "EP", 40, "xp"), "xp in class colour")
	local combat = ns:GetModule("CombatText")
	combat.db.enabled = false
	issecretvalue = function() return false end
	UnitCanAttack = function() return true end
	UnitIsUnit = function() return false end
	assert(pcall(combat.Handle, "target", "WOUND", "CRITICAL", 120), "own damage off: nothing happens")
	combat.db.enabled = true
	for _, args in ipairs({ { "target", "WOUND", "CRITICAL", 120 }, { "target", "MISS", "", 0 }, { "player", "WOUND", "", 15 },
		{ "player", "HEAL", "", 30 }, { "party1", "WOUND", "", 5 }, { "player", "ENERGIZE", "", 5 } }) do
		local ok, err = pcall(combat.Handle, unpack(args))
		assert(ok, tostring(err))
	end
	-- options: no thick or shaking crits, colours by name, the place of the target instead of its plate
	combat.db.critBold, combat.db.critShake, combat.db.targetPlate, combat.db.colorCrit = false, false, false, "CLASS"
	assert(pcall(combat.Handle, "target", "WOUND", "CRITICAL", 99), "crit with the options off")
	local items = ns:GetModule("Items")
	assert(items.FreeSlots and items.CheckFull and items.PlayFullSound, "bag full sound functions")
	assert(pcall(items.CheckFull), "bags full check runs")
	combat.db.enabled = false
	local trivial = ns:GetModule("Trivial")
	DRUNK_MESSAGE_SELF1 = "Ihr fühlt Euch ein wenig beschwipst."
	MARKED_AFK = "Ihr seid jetzt AFK."
	trivial:OnLogin()
	local filter = uv(trivial.Apply, "Filter")
	trivial.db.enabled, trivial.db.shown = true, { afk = true }
	issecretvalue = function() return false end
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == true, "rested hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr fühlt Euch ein wenig beschwipst.") == true, "drunk hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == false, "afk kept while off")
	trivial.db.shown.afk = nil
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == true, "afk hidden when on")
	trivial.db.shown.rested = true
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == false, "rested kept when off")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Etwas ganz anderes.") == false, "other lines pass")
	assert(filter(nil, "CHAT_MSG_MONSTER_EMOTE", "%s versucht zu flüchten.") == true, "fleeing emote hidden")
	trivial.db.shown.flee = true
	assert(filter(nil, "CHAT_MSG_MONSTER_EMOTE", "%s versucht zu flüchten.") == false, "fleeing emote kept as exception")
	trivial.db.shown.flee = nil
	print("trivial OK")
end)()
;(function()
	-- durability on the character window
	local dura = ns:GetModule("Durability")
	issecretvalue = function() return false end
	GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 elseif slot == 2 then return 100, 100 end end
	assert(dura.db.threshold == 60, "threshold default 60 %")
	assert(dura.Percent(1) == 50, "half")
	assert(dura.Percent(2) == nil, "full hidden")
	assert(dura.Percent(3) == nil, "no durability")
	GetInventoryItemDurability = function(slot) if slot == 1 then return 70, 100 elseif slot == 2 then return 100, 100 end end
	assert(dura.Percent(1) == nil and not dura.FigureShown(), "70 %: above the threshold, nothing and no figure")
	dura.db.threshold = 80
	assert(dura.Percent(1) == 70 and dura.FigureShown(), "below a higher threshold: number and figure")
	dura.db.threshold = 60
	dura.db.showFull = true
	assert(dura.Percent(1) == 70 and dura.Percent(2) == 100 and dura.FigureShown(), "everything with the option")
	dura.db.showFull = false
	GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 elseif slot == 2 then return 100, 100 end end
	assert(pcall(dura.Update), "update runs")
	assert(dura.Raw(2) == 100 and dura.Raw(3) == nil, "raw percent")
	-- pet food
	local helpers = ns:GetModule("Helpers")
	assert(helpers.db.feedPet == true, "feed pet default")
	print("durability OK")
end)()
;(function()
	-- talent plan summary and the suggested distributions
	local lines, other = ns.TalentSummary.Build({
		"Erhöht Eure Chance, einen kritischen Treffer zu erzielen, um 3%.",
		"Erhöht die Chance auf kritische Treffer um 2%. Erhöht Eure Bewegungsgeschwindigkeit um 3%.",
		"Erhöht Eure Ausdauer um 10. Verringert die Abklingzeit um 15 Sek.",
	}, true)
	local text = {}
	for _, line in ipairs(lines) do text[#text + 1] = line.text end
	assert(table.concat(text, "|") == "+5 % Kritische Trefferchance|+3 % Bewegungsgeschwindigkeit|+10 Ausdauer", table.concat(text, "|"))
	assert(other == 1, "the cooldown sentence is only counted: " .. other)
	lines = ns.TalentSummary.Build({ "Increases your attack speed by 5%. Reduces threat caused by 10%." }, false)
	assert(#lines == 2 and lines[1].text == "+5 % Attack speed" and lines[2].text == "-10 % Threat", lines[1].text .. " / " .. lines[#lines].text)
	local gain = ns.TalentSummary.RankGain
	local weights = { STA = 1.5, DODGE = 12, DEF = 1.5 }
	assert(gain("Increases your Defense Skill by 4.", "Increases your Defense Skill by 8.", weights, {}, false) == 6,
		"score the next rank's increase")
	assert(gain(nil, "Erhöht Eure Ausdauer um 2%.", weights, { STA = 76 }, true) == 76 * 0.02 * 1.5,
		"estimate a percentage of the current attribute")
	local ret = upvalue(getW, "WEIGHTS").PALADIN[3]
	local stats = { INT = 100, STR = 100 }
	local intellectGain = gain("Increases your total Intellect by 2%.", "Increases your total Intellect by 4%.", ret, stats, false)
	assert(intellectGain == 2 * ret.INT and intellectGain > gain(nil, "Increases your Strength by 2%.", ret, stats, false),
		"recognize Divine Intellect and compare it with Divine Strength using the Retribution weights")
	assert(gain("Erhöht Eure gesamte Intelligenz um 2%.", "Erhöht deine gesamte Intelligenz um 4%.", ret, stats, true) == intellectGain
		and gain(nil, "Erhöht deine Stärke um 2%.", ret, stats, true) == 2 * ret.STR,
		"recognize the localized direct attribute bonuses")
	assert(gain(nil, "Increases your chance to dodge by an additional 2%.", weights, {}, false) == 24,
		"score a change in chance in percentage points")
	assert(gain(nil, "Increases your Parry chance by 1%.", { PARRY = 9 }, {}, false) == 9,
		"recognize the parry talent's description")
	local healer = { SP = 0.85, HEAL = 1, HASTE = 2, SHASTE = 6, SCRIT = 7 }
	assert(gain(nil, "Increases your spell power by 10.", healer, {}, false) == 10,
		"generic spell power has the same value in talents and in gear")
	assert(gain(nil, "Increases your melee attack speed by 2%.", healer, {}, false) == 4
		and gain(nil, "Erhöht Euer Zaubertempo um 2%.", healer, {}, true) == 12,
		"keep explicitly melee and spell haste talents separate")
	assert(gain(nil, "Erhöht Eure kritische Trefferchance mit allen Zaubern und Angriffen um 2%.", healer, {}, true) == 14,
		"use the profile's spell crit weight for a shared crit talent")
	assert(gain(nil, "Improves your chance to get a critical strike with all spells and attacks by 1%.", healer, {}, false) == 7,
		"recognize the shared crit talent's English description")
	assert(not gain(nil, "Increases your chance to dodge by 2% for 10 sec.", weights, {}, false)
		and not gain(nil, "Increases your Stamina by 2% while in Bear Form.", weights, { STA = 76 }, false),
		"temporary and conditional effects are outside the item model")
	local classes = 0
	for class, builds in pairs(ns.TalentPresets) do
		classes = classes + 1
		assert(#builds >= 4, class .. " has at least three standards and one special")
		for _, build in ipairs(builds) do
			local points, count = 0, 0
			for rank in build.ranks:gmatch("%d+:(%d+)") do points, count = points + tonumber(rank), count + 1 end
			assert(points == 51 and count > 10, class .. " " .. build.en .. " " .. points)
		end
	end
	assert(classes == 9, "all nine classes")
	local retPreset = ns.TalentPresets.PALADIN[3]
	local retRanks = ns.TalentBuilds.ParseRanks(retPreset.ranks)
	assert(retPreset.points == "12/8/31" and retRanks[105332] == 5 and retRanks[105638] == 3
		and retRanks[113630] == 5 and retRanks[105334] == 5 and retRanks[105704] == 2,
		"use the simulated Retribution secondary talents in Holy and Protection")
	print("talent summary and presets OK")
end)()
;(function()
	local tp = ns:GetModule("Teleports")
	IsPlayerSpell = function(id) return id == 18960 or id == 10059 end
	C_Item.GetItemCount = function(id) return id == 6948 and 1 or 0 end
	C_Item.GetItemNameByID = function(id) return "Item" .. id end
	C_Item.GetItemIconByID = function() return 1 end
	C_Container.GetItemCooldown = function() return 0, 0, 1 end
	C_Spell.GetSpellName = function(id) return "Spell" .. id end
	C_Spell.GetSpellTexture = function() return 2 end
	C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
	tp.db.portals = true
	local list = tp:Collect()
	assert(#list == 3 and list[1].hearth and list[2].id == 18960 and list[3].portal, "teleports found")
	tp.db.portals = false
	assert(#tp:Collect() == 2, "portals optional")
	tp.db.portals = true
	InCombatLockdown = function() return false end
	GetBindLocation = function() return "Orgrimmar" end
	local ok, err = pcall(tp.ShowMenu, tp) assert(ok, tostring(err))
	print("teleports OK")
end)()
;(function()
	local items = ns:GetModule("Items")
	local built, original = nil, ns.ShowPopupList
	ns.ShowPopupList = function(_, build) built = build() end
	items:ShowBagMenu({})
	ns.ShowPopupList = original
	assert(built and #built.items > 8, "bag menu items")
	local toggle
	for _, item in ipairs(built.items) do
		if item.checked ~= nil and item.text == ns.L.ITEMS_AUTOSORT then toggle = item end
	end
	assert(toggle, "autoSort entry")
	local before = items.db.autoSort
	toggle.onClick()
	assert(items.db.autoSort == not before, "toggle flips option")
	toggle.onClick()
	print("bag menu OK")
end)()
;(function()
	SKILL_RANK_UP = "Eure Fertigkeit '%s' hat sich auf %d erhöht."
	FACTION_STANDING_INCREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert."
	FACTION_STANDING_DECREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verschlechtert."
	ERR_LEARN_SPELL_S = "Ihr habt den Zauber %s erlernt."
	ERR_LEARN_ABILITY_S = "Ihr habt die Fähigkeit %s erlernt."
	ERR_LEARN_PASSIVE_S = "Ihr habt den passiven Zauber %s erlernt."
	local chunk = assert(loadfile(root .. "/Modules/Chat.lua"))
	ns.modules.Chat = nil
	chunk("ForeverPlus", ns)
	local chat = ns.modules.Chat
	chat.db = { repeatSummary = true, repeatDelay = 30 }
	local filter = uv(chat.UpdateRepeatSummary, "RepeatFilter")
	local flush = uv(filter, "FlushRepeat")
	local pending = uv(filter, "repeatPending")
	local timers = {}
	C_Timer.NewTimer = function(_, fn) local t = { Cancel = function(self) self.cancelled = true end, fn = fn } timers[#timers + 1] = t return t end
	ChatTypeInfo = { SKILL = { r = 0.3, g = 0.3, b = 1, id = 9 }, COMBAT_FACTION_CHANGE = { r = 0.5, g = 0.5, b = 1, id = 10 } }
	local out = {}
	local frameA = { AddMessage = function(_, t) out[#out + 1] = "A:" .. t end }
	local frameB = { AddMessage = function(_, t) out[#out + 1] = "B:" .. t end }
	local now = 0
	GetTime = function() return now end
	for rank = 4, 11 do
		now = now + 10
		assert(filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Kürschnerei' hat sich auf %d erhöht."):format(rank)) == true)
		filter(frameB, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Kürschnerei' hat sich auf %d erhöht."):format(rank))
	end
	for i = 1, 3 do
		now = now + 1
		filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Eisenschmiede' hat sich um 25 verbessert.")
	end
	assert(filter(frameA, "CHAT_MSG_SAY", "hallo") == false)
	for key in pairs(pending) do flush(key) end
	table.sort(out)
	for _, l in ipairs(out) do print("  ", l) end
	assert(#out == 3, "three lines")
	print("repeat summary OK")
	-- skills combined into one line
	chat.db.skillLine = true
	out = {}
	for rank = 31, 40 do filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Verteidigung' hat sich auf %d erhöht."):format(rank)) end
	for rank = 34, 36 do filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Äxte' hat sich auf %d erhöht."):format(rank)) end
	for key in pairs(pending) do flush(key) end
	assert(#out == 1 and out[1] == "A:" .. ns.L.CHAT_SKILL_LINE_TEXT:format("Verteidigung 30->40, Äxte 33->36"), out[1])
	print("skill line OK")
	-- reputation and new spells in one line each
	chat.db.repLine, chat.db.learnLine = true, true
	out = {}
	for i = 1, 3 do filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Eisenschmiede' hat sich um 25 verbessert.") end
	filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Orgrimmar' hat sich um 10 verschlechtert.")
	assert(ns.ParseReputationMessage("Euer Ruf bei der Fraktion 'Orgrimmar' hat sich um 10 verschlechtert.") == "Orgrimmar", "rep parse")
	assert(filter(frameA, "CHAT_MSG_SYSTEM", "Ihr habt den Zauber |Hspell:133|h[Feuerball]|h erlernt.") == true, "learn caught")
	filter(frameA, "CHAT_MSG_SYSTEM", "Ihr habt die Fähigkeit |Hspell:116|h[Frostblitz]|h erlernt.")
	assert(filter(frameA, "CHAT_MSG_SYSTEM", "Etwas anderes.") == false, "other system lines pass")
	for key in pairs(pending) do flush(key) end
	table.sort(out)
	assert(#out == 2, "two lines: " .. #out)
	assert(out[1] == "A:Eisenschmiede +75, Orgrimmar -10", out[1])
	assert(out[2] == "A:" .. ns.L.CHAT_LEARN_LINE:format("|Hspell:133|h[Feuerball]|h, |Hspell:116|h[Frostblitz]|h"), out[2])
	print("rep and learn lines OK")
end)()
;(function()
	local q = ns:GetModule("Quests")
	local markLog
	-- hooksecurefunc in the harness may not keep the function; find it via OnLogin upvalues
	markLog = uv(q.OnLogin, "MarkQuestLog")
	q.db.foreverMark, q.db.foreverMarkStyle = true, "ICON"
	local function fs(t) return { t = t, GetText = function(self) return self.t end, SetText = function(self, v) self.t = v end, SetTextColor = function(self, r) self.r = r end } end
	local a, b = { questID = 99160, Text = fs("Neue Quest") }, { questID = 783, Text = fs("Alte Quest") }
	QuestScrollFrame = { titleFramePool = { EnumerateActive = function() local l, i = { a, b }, 0 return function() i = i + 1 return l[i] end end } }
	markLog()
	markLog()
	print("  marks", a.Text.t, "|", b.Text.t)
	assert(a.Text.t:find("auctionhouse%-icon%-favorite") and select(2, a.Text.t:gsub("favorite", "")) == 1 and b.Text.t == "Alte Quest", "icon mark once")
	q.db.foreverMarkStyle = "COLOR"
	a.HookScript = function() end
	markLog()
	assert(a.Text.r ~= nil and not b.Text.r, "color mark")
	print("forever marks OK")
end)()
;(function()
	-- World map: unexplored parts from the data, explored and mismatching maps skipped.
	local wm = ns:GetModule("WorldMap")
	-- Shipped data: every part has the tiles its size needs (256 pixel tiles).
	local parts = 0
	for art, raw in pairs(ns.MapOverlays) do
		for part in raw:gmatch("[^;]+") do
			local n = {}
			for number in part:gmatch("-?%d+") do n[#n + 1] = tonumber(number) end
			assert(#n - 4 == math.ceil(n[1] / 256) * math.ceil(n[2] / 256), "tiles of a part in art " .. art)
			parts = parts + 1
		end
	end
	print("  map data", ns.MapOverlayBuild, parts, "parts")
	local made = {}
	local function NewTexture(layer, sub)
		local t = { layer = layer, sub = sub, shown = true }
		function t:SetSize(w, h) self.w, self.h = w, h end
		function t:SetTexCoord(...) self.coord = { ... } end
		function t:ClearAllPoints() end
		function t:SetPoint(point, x, y) self.point, self.x, self.y = point, x, y end
		function t:SetTexture(file, _, _, filter) self.file, self.filter = file, filter end
		function t:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
		function t:SetAlpha(a) self.alpha = a end
		function t:Show() self.shown = true end
		function t:Hide() self.shown = false end
		made[#made + 1] = t
		return t
	end
	local layerIndex = 1
	local map = { GetMapID = function() return 1429 end, IsShown = function() return true end,
		GetCanvasContainer = function() return { GetCurrentLayerIndex = function() return layerIndex end } end }
	local pin = { GetMap = function() return map end, RefreshOverlays = function() end, RemoveAllData = function() end,
		CreateTexture = function(_, _, layer, _, sub) return NewTexture(layer, sub) end }
	WorldMapFrame.EnumeratePinsByTemplate = function(_, template)
		assert(template == "MapExplorationPinTemplate")
		local done
		return function() if not done then done = true return pin end end
	end
	WorldMapFrame.GetMapID = function() return 1429 end
	WorldMapFrame.GetCanvas = function() return CreateFrame("Frame") end
	WorldMapFrame.GetCanvasScale = function() return 1 end
	ns.MapOverlays, ns.MapOverlayBuild = { [15] = "300,200,10,20,1001,1002;100,100,400,5,2001;300,300,0,0,3001" }, "test"
	local explored = { { fileDataIDs = { 2001 } }, { fileDataIDs = {} } }
	C_Map.GetMapArtID = function(id) return id == 1429 and 15 or nil end
	C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end
	C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end }
	local function shown()
		local list = {}
		for _, t in ipairs(made) do if t.shown then list[#list + 1] = t end end
		return list
	end
	wm.db.reveal, wm.db.revealAlpha, wm.db.revealTint = true, 60, true
	wm:Apply()
	local list = shown()
	-- 300 x 200 in two tiles; the explored part and the one with a missing tile are left out.
	assert(#list == 2, "two tiles, got " .. #list)
	local a, b = list[1], list[2]
	assert(a.layer == "ARTWORK" and a.sub == -1, "below Blizzard's parts")
	assert(a.file == 1001 and a.w == 256 and a.h == 200 and a.x == 10 and a.y == -20, "first tile")
	assert(a.coord[2] == 1 and a.coord[4] == 200 / 256, "first tile coords")
	assert(b.file == 1002 and b.w == 44 and b.x == 266 and b.coord[2] == 44 / 64, "edge tile")
	assert(a.alpha == 0.6 and a.r == 0.75 and a.g == 1 and a.filter == "TRILINEAR", "faded and tinted")
	wm.db.revealTint = false
	wm:OnOptionChanged("revealTint", false)
	assert(#shown() == 2 and shown()[1].r == 1 and #made == 2, "untinted, textures reused")
	-- a colour of one's own from Blizzard's colour picker, on the map at once; Cancel restores
	local info
	local picked = { r = 1, g = 0.5, b = 0, a = 0.8 }
	ColorPickerFrame = { SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return picked.r, picked.g, picked.b end, GetColorAlpha = function() return picked.a end }
	wm.ChooseTint()
	assert(info.r == 0.75 and info.g == 1 and info.b == 0.75 and info.opacity == 0.6 and info.hasOpacity, "starts at the current colour and opacity")
	info.swatchFunc()
	local t = shown()[1]
	assert(wm.db.revealTint and wm.db.revealAlpha == 80 and t.r == 1 and t.g == 0.5 and t.b == 0 and t.alpha == 0.8 and #made == 2,
		"the chosen colour turns the tint on and shows without drawing again")
	info.cancelFunc()
	t = shown()[1]
	assert(not wm.db.revealTint and wm.db.revealAlpha == 60 and t.r == 1 and t.g == 1 and t.alpha == 0.6, "cancel restores")
	wm.ChooseTint()
	info.swatchFunc()
	wm:Apply()
	assert(shown()[1].g == 0.5 and wm.db.revealColor.r == 1, "kept and used when drawn again")
	picked.a = 0.02
	info.opacityFunc()
	assert(wm.db.revealAlpha == 10, "opacity at least 10 %")
	wm.db.revealColor = { r = "x", g = 2 }
	local r, g, b = wm.TintColor(wm.db)
	assert(r == 0.75 and g == 1 and b == 0.75, "damaged colour: defaults, values clamped")
	wm.db.revealColor = nil
	assert(select(3, wm.TintColor(wm.db)) == 0.75 and wm.TintColor({ revealTint = false }) == 1, "missing colour: green; tint off: white")
	wm.db.revealColor, wm.db.revealAlpha, wm.db.revealTint = { r = 0.75, g = 1, b = 0.75 }, 60, false
	explored = { { fileDataIDs = { 2001 } }, { fileDataIDs = { 9999 } } }
	wm:Apply()
	assert(#shown() == 0, "unknown explored part: map left alone")
	explored = {}
	layerIndex = 2
	wm:Apply()
	assert(#shown() == 0, "other art layer")
	layerIndex = 1
	wm:Apply()
	assert(#shown() == 3, "nothing explored: all complete parts")
	wm.db.reveal = false
	wm:OnOptionChanged("reveal", false)
	assert(#shown() == 0, "switched off")
	local printed = {}
	local printAlways = ns.PrintAlways
	ns.PrintAlways = function(msg, ...) printed[#printed + 1] = msg:format(...) end
	wm:PrintStatus()
	C_Map.GetMapArtID = function() return 99 end
	wm:PrintStatus()
	ns.PrintAlways = printAlways
	for _, line in ipairs(printed) do print("  ", line) end
	assert(#printed == 4 and printed[1]:find("1429") and printed[2]:find("0") and printed[3]:find("test"), "status lines")
	print("world map OK")
end)()

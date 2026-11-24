-- German speech for the male dwarf's silent emotes, plus rare German and English
-- situational voice lines triggered by genuine gameplay moments.
-- Playback follows confirmed chat/game events with zero idle OnUpdate polling.
-- Native commands, targets and animations are handled by the game.
local _, ns = ...
local L = ns.L

local Voice = ns:NewModule("EmoteVoice", {
	title = L.EMOTEVOICE_TITLE,
	order = 5.975,
	defaults = {
		enabled = true,
		situational = true,
		situationalCooldown = 90,
	},
})

local MEDIA = [[Interface\AddOns\ForeverPlus\Media\EmoteVoice\deDE\DwarfMale\]]
local SITUATIONAL_MEDIA = [[Interface\AddOns\ForeverPlus\Media\SituationalVoice\]]
local SITUATIONAL_LOCALES = { deDE = true, enUS = true }
local LOGIN_GRACE = 5
local INN_MIN_AWAY = 120
local FLIGHT_MIN_DURATION = 60
local BREATH_LOW_RATIO = 0.25
local FISHING_DRY_TARGET = 10

local SITUATIONAL_CATEGORIES = {
	INN = { cooldown = 300, clips = { "INN_1", "INN_2", "INN_3" } },
	BREATH = { cooldown = 60, clips = { "BREATH_1", "BREATH_2", "BREATH_3" } },
	BAGS_FULL = { cooldown = 300, clips = { "BAGS_FULL_1", "BAGS_FULL_2", "BAGS_FULL_3" } },
	FLIGHT_END = { cooldown = 300, clips = { "FLIGHT_END_1", "FLIGHT_END_2", "FLIGHT_END_3" } },
	EPIC_LOOT = { cooldown = 60, clips = { "EPIC_LOOT_1", "EPIC_LOOT_2", "EPIC_LOOT_3" } },
	RESURRECT = { cooldown = 300, clips = { "RESURRECT_1", "RESURRECT_2", "RESURRECT_3" } },
	FISHING_DRY = { cooldown = 300, clips = { "FISHING_DRY_1", "FISHING_DRY_2", "FISHING_DRY_3" } },
}

local SITUATIONAL_ORDER = {
	"INN",
	"BREATH",
	"BAGS_FULL",
	"FLIGHT_END",
	"EPIC_LOOT",
	"RESURRECT",
	"FISHING_DRY",
}

local COMMAND_ALIASES = {
	taverne = "INN",
	gasthaus = "INN",
	inn = "INN",
	luft = "BREATH",
	atem = "BREATH",
	breath = "BREATH",
	taschen = "BAGS_FULL",
	rucksack = "BAGS_FULL",
	bags = "BAGS_FULL",
	flug = "FLIGHT_END",
	flight = "FLIGHT_END",
	episch = "EPIC_LOOT",
	beute = "EPIC_LOOT",
	epic = "EPIC_LOOT",
	tod = "RESURRECT",
	wiederbelebung = "RESURRECT",
	revive = "RESURRECT",
	resurrect = "RESURRECT",
	angeln = "FISHING_DRY",
	fischen = "FISHING_DRY",
	fishing = "FISHING_DRY",
}

local FISHING_SPELLS = {
	[7620] = true,
	[7731] = true,
	[7732] = true,
	[18248] = true,
	[33095] = true,
}

local SITUATIONAL_EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_UPDATE_RESTING",
	"MIRROR_TIMER_START",
	"MIRROR_TIMER_STOP",
	"UI_ERROR_MESSAGE",
	"PLAYER_CONTROL_LOST",
	"PLAYER_CONTROL_GAINED",
	"UNIT_FLAGS",
	"CHAT_MSG_LOOT",
	"PLAYER_DEAD",
	"PLAYER_ALIVE",
	"PLAYER_UNGHOST",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"LOOT_OPENED",
}

Voice.SITUATIONAL_CATEGORIES = SITUATIONAL_CATEGORIES
Voice.SITUATIONAL_LOCALES = SITUATIONAL_LOCALES

local exact, patterns, noChat = {}, {}, {}
local known = {}
local soundHandle

local loginAt
local wasResting, notRestingSince
local breath
local wasOnTaxi, taxiStartedAt
local wasDead
local fishingDryCount, fishingChannel, fishingLooted, fishingToken = 0, false, false, 0
local lastSituationalAt
local lastCategoryAt = {}
local lastVariant = {}
local lootPatternCache = {}
local previewIndex = 0

local function IsMaleDwarf()
	local _, race = UnitRace("player")
	local sex = UnitSex("player")
	return not ns.Secret(race) and not ns.Secret(sex) and race == "Dwarf" and sex == 2
end

function Voice.IsSupported()
	return GetLocale() == "deDE" and IsMaleDwarf()
end

function Voice.IsSituationalSupported()
	return SITUATIONAL_LOCALES[GetLocale()] == true and IsMaleDwarf()
end

local function SafeBool(value)
	if ns.Secret(value) then
		return nil
	end
	return value and true or false
end

local function IsPlayerDead()
	if not UnitIsDeadOrGhost then
		return false
	end
	return SafeBool(UnitIsDeadOrGhost("player")) == true
end

local function Build()
	wipe(exact)
	wipe(patterns)
	wipe(noChat)
	wipe(known)
	for _, entry in ipairs(ns.EmoteVoiceData) do
		local token = entry[1]
		known[token] = true
		noChat[token] = #entry == 1 or nil
		for index = 2, #entry do
			local text = entry[index]
			if text:find("%%s") then
				patterns[#patterns + 1] = { ns.FormatToPattern(text, true).pattern, token }
			else
				-- GAZE and STARE share one untargeted native sentence.
				exact[text] = exact[text] or token
			end
		end
	end
	-- A short format such as "Ihr grüßt %s." can also match a longer salute.
	-- Prefer the format with the most literal text around the target name.
	table.sort(patterns, function(left, right)
		return #left[1] > #right[1]
	end)
end

function Voice.Match(text)
	if type(text) ~= "string" or ns.Secret(text) then
		return
	end
	if exact[text] then
		return exact[text]
	end
	for _, entry in ipairs(patterns) do
		if text:match(entry[1]) then
			return entry[2]
		end
	end
end

local function Stop()
	if soundHandle then
		StopSound(soundHandle)
		soundHandle = nil
	end
end

local function Play(token)
	if not known[token] then
		return false
	end
	Stop()
	local playing, handle = PlaySoundFile(MEDIA .. token .. ".mp3", "Dialog")
	if playing then
		soundHandle = handle
	end
	return playing
end

local function PickVariant(category)
	local info = SITUATIONAL_CATEGORIES[category]
	if not info or #info.clips == 0 then
		return nil
	end
	local clips = info.clips
	if #clips == 1 then
		return clips[1]
	end
	local previous = lastVariant[category]
	local index = math.random(1, #clips - (previous and 1 or 0))
	if previous and index >= previous then
		index = index + 1
	end
	lastVariant[category] = index
	return clips[index]
end

local function PlaySituational(category, force)
	local info = SITUATIONAL_CATEGORIES[category]
	if not info or not Voice.IsSituationalSupported() then
		return false
	end
	if not force and not Voice.db.situational then
		return false
	end
	local now = GetTime()
	if not force then
		local globalCooldown = tonumber(Voice.db.situationalCooldown) or 90
		if lastSituationalAt and (now - lastSituationalAt) < globalCooldown then
			return false
		end
		local categoryCooldown = info.cooldown or 300
		if lastCategoryAt[category] and (now - lastCategoryAt[category]) < categoryCooldown then
			return false
		end
	end
	local clip = PickVariant(category)
	if not clip then
		return false
	end
	Stop()
	local path = SITUATIONAL_MEDIA .. GetLocale() .. [[\DwarfMale\]] .. clip .. ".mp3"
	local playing, handle = PlaySoundFile(path, "Dialog")
	if playing then
		soundHandle = handle
		if not force then
			lastSituationalAt = now
			lastCategoryAt[category] = now
		end
	end
	return playing, clip
end

local function SyncInitialState(resetGrace)
	local now = GetTime()
	if resetGrace or not loginAt then
		loginAt = now
	end
	local resting = IsResting and SafeBool(IsResting())
	if resting ~= nil then
		wasResting = resting
		if resting then
			notRestingSince = nil
		elseif not notRestingSince then
			notRestingSince = now
		end
	end
	local onTaxi = UnitOnTaxi and SafeBool(UnitOnTaxi("player"))
	if onTaxi ~= nil then
		wasOnTaxi = onTaxi
		if onTaxi and not taxiStartedAt then
			taxiStartedAt = now
		elseif not onTaxi then
			taxiStartedAt = nil
		end
	end
	if IsPlayerDead() then
		wasDead = true
	end
end

local function MatchSelfLootLink(text)
	local formats = {
		[1] = LOOT_ITEM_SELF_MULTIPLE,
		[2] = LOOT_ITEM_SELF,
		[3] = LOOT_ITEM_PUSHED_SELF_MULTIPLE,
		[4] = LOOT_ITEM_PUSHED_SELF,
	}
	for index = 1, 4 do
		local fmt = formats[index]
		if type(fmt) == "string" and not ns.Secret(fmt) then
			local compiled = lootPatternCache[fmt]
			if not compiled then
				compiled = ns.FormatToPattern(fmt, true)
				lootPatternCache[fmt] = compiled
			end
			local captures = { text:match(compiled.pattern) }
			if captures[1] then
				for capIndex, value in ipairs(captures) do
					if compiled.order[capIndex] == 1 and type(value) == "string" and value:find("|Hitem:", 1, true) then
						return value
					end
				end
			end
		end
	end
end

local function IsEpicOrHigher(link)
	local lower = link:lower()
	if lower:find("|cffa335ee", 1, true) or lower:find("|cffff8000", 1, true) or lower:find("|cffe6cc80", 1, true) then
		return true
	end
	if C_Item then
		if type(C_Item.GetItemQualityByID) == "function" then
			local quality = ns.Number(C_Item.GetItemQualityByID(link))
			if quality then
				return quality >= 4
			end
		end
		if type(C_Item.GetItemInfo) == "function" then
			local _, _, quality = C_Item.GetItemInfo(link)
			quality = ns.Number(quality)
			if quality then
				return quality >= 4
			end
		end
	end
	return false
end

local function IsFishingSpell(spellID)
	local id = ns.Number(spellID)
	return id ~= nil and FISHING_SPELLS[id] == true
end

local function IsFishingChannelActive()
	if not UnitChannelInfo then
		return false
	end
	local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
	if IsFishingSpell(spellID) then
		return true
	end
	if type(name) == "string" and not ns.Secret(name) and C_Spell and type(C_Spell.GetSpellName) == "function" then
		local fishingName = C_Spell.GetSpellName(7620)
		if type(fishingName) == "string" and not ns.Secret(fishingName) and name == fishingName then
			return true
		end
	end
	return false
end

local function RecordDryFishingCast()
	fishingDryCount = fishingDryCount + 1
	if fishingDryCount >= FISHING_DRY_TARGET then
		fishingDryCount = 0
		PlaySituational("FISHING_DRY")
	end
end

local function UpdateTaxiState()
	if not Voice.db.situational or not Voice.IsSituationalSupported() then
		return
	end
	local onTaxi = UnitOnTaxi and SafeBool(UnitOnTaxi("player"))
	if onTaxi == nil then
		return
	end
	local now = GetTime()
	if onTaxi and not wasOnTaxi then
		wasOnTaxi = true
		taxiStartedAt = now
	elseif not onTaxi and wasOnTaxi then
		wasOnTaxi = false
		local started = taxiStartedAt
		taxiStartedAt = nil
		if started and (now - started) >= FLIGHT_MIN_DURATION and not IsPlayerDead() then
			PlaySituational("FLIGHT_END")
		end
	end
end

local function CheckResurrect()
	if not Voice.db.situational or not Voice.IsSituationalSupported() then
		return
	end
	if wasDead and not IsPlayerDead() then
		wasDead = false
		PlaySituational("RESURRECT")
	end
end

function Voice:CHAT_MSG_TEXT_EMOTE(_, text, ...)
	if not self.db.enabled or not self.IsSupported() then
		return
	end
	-- GUID is argument 12 of CHAT_MSG_TEXT_EMOTE. Forever may leave the author
	-- name empty. Other players' emotes must never be mistaken for our own.
	local guid = select(11, ...)
	local playerGUID = UnitGUID("player")
	if type(guid) ~= "string" or ns.Secret(guid) or ns.Secret(playerGUID) or guid ~= playerGUID then
		return
	end
	local token = self.Match(text)
	if token then
		Play(token)
	else
		Stop()
	end
end

function Voice:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
	local initial = not ns.Secret(isInitialLogin) and isInitialLogin
	local reload = not ns.Secret(isReloadingUi) and isReloadingUi
	if (isInitialLogin == nil and isReloadingUi == nil) or initial or reload then
		SyncInitialState(true)
	elseif self.db.situational and self.IsSituationalSupported() then
		-- Hearthstoning into an inn transitions resting without an initial login grace reset.
		self:PLAYER_UPDATE_RESTING()
	end
end

function Voice:PLAYER_UPDATE_RESTING()
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	local resting = IsResting and SafeBool(IsResting())
	if resting == nil then
		return
	end
	local now = GetTime()
	if resting and not wasResting then
		wasResting = true
		local away = notRestingSince and (now - notRestingSince) or 0
		notRestingSince = nil
		if loginAt and (now - loginAt) >= LOGIN_GRACE and away >= INN_MIN_AWAY and not IsPlayerDead() then
			PlaySituational("INN")
		end
	elseif not resting then
		if wasResting or not notRestingSince then
			notRestingSince = now
		end
		wasResting = false
	end
end

function Voice:MIRROR_TIMER_START(_, timerName, value, maxValue, scale, paused)
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	if type(timerName) ~= "string" or ns.Secret(timerName) or timerName ~= "BREATH" then
		return
	end
	local val = ns.Number(value)
	local maxVal = ns.Number(maxValue)
	local rate = ns.Number(scale, -1)
	if not val or not maxVal or maxVal <= 0 then
		return
	end
	local low = (breath and breath.low) or (val / maxVal) < BREATH_LOW_RATIO
	breath = {
		value = val,
		maxValue = maxVal,
		scale = rate,
		paused = not ns.Secret(paused) and paused and paused ~= 0 or false,
		startedAt = GetTime(),
		low = low,
	}
end

function Voice:MIRROR_TIMER_STOP(_, timerName)
	if not self.db.situational or not self.IsSituationalSupported() then
		breath = nil
		return
	end
	if type(timerName) ~= "string" or ns.Secret(timerName) or timerName ~= "BREATH" then
		return
	end
	local state = breath
	breath = nil
	if not state or state.maxValue <= 0 then
		return
	end
	local low = state.low
	if not low then
		local elapsed = math.max(0, GetTime() - state.startedAt)
		local unitScale = state.maxValue >= 1000 and 1000 or 1
		local estimated = state.value + (state.paused and 0 or (state.scale * elapsed * unitScale))
		local progress = GetMirrorTimerProgress and ns.Number(GetMirrorTimerProgress("BREATH"))
		local remaining
		if progress and progress > 0 and progress <= state.maxValue then
			remaining = progress
		elseif progress == 0 and estimated <= state.maxValue * BREATH_LOW_RATIO then
			remaining = 0
		else
			remaining = estimated
		end
		low = (remaining / state.maxValue) < BREATH_LOW_RATIO
	end
	if low and not IsPlayerDead() then
		PlaySituational("BREATH")
	end
end

function Voice:UI_ERROR_MESSAGE(_, _, message)
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	if type(message) ~= "string" or ns.Secret(message) then
		return
	end
	if type(ERR_INV_FULL) == "string" and message == ERR_INV_FULL then
		PlaySituational("BAGS_FULL")
	elseif (type(ERR_FISH_ESCAPED) == "string" and message == ERR_FISH_ESCAPED)
		or (type(ERR_FISH_NOT_HOOKED) == "string" and message == ERR_FISH_NOT_HOOKED) then
		fishingChannel = false
		fishingLooted = false
		fishingToken = fishingToken + 1
		RecordDryFishingCast()
	end
end

function Voice:PLAYER_CONTROL_LOST()
	UpdateTaxiState()
end

function Voice:PLAYER_CONTROL_GAINED()
	UpdateTaxiState()
end

function Voice:UNIT_FLAGS(_, unit)
	if not ns.Secret(unit) and unit == "player" then
		UpdateTaxiState()
	end
end

function Voice:CHAT_MSG_LOOT(_, text)
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	if type(text) ~= "string" or ns.Secret(text) then
		return
	end
	local link = MatchSelfLootLink(text)
	if link and IsEpicOrHigher(link) then
		PlaySituational("EPIC_LOOT")
	end
end

function Voice:PLAYER_DEAD()
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	wasDead = true
end

function Voice:PLAYER_ALIVE()
	CheckResurrect()
end

function Voice:PLAYER_UNGHOST()
	CheckResurrect()
end

function Voice:UNIT_SPELLCAST_CHANNEL_START(_, unit, _, spellID)
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	if ns.Secret(unit) or unit ~= "player" then
		return
	end
	if IsFishingSpell(spellID) or IsFishingChannelActive() then
		fishingChannel = true
		fishingLooted = false
		fishingToken = fishingToken + 1
	end
end

function Voice:UNIT_SPELLCAST_CHANNEL_STOP(_, unit, _, spellID)
	if not self.db.situational or not self.IsSituationalSupported() then
		return
	end
	if ns.Secret(unit) or unit ~= "player" then
		return
	end
	local wasFishing = fishingChannel or IsFishingSpell(spellID)
	fishingChannel = false
	if fishingLooted then
		fishingLooted = false
		return
	end
	if not wasFishing then
		return
	end
	fishingToken = fishingToken + 1
	local token = fishingToken
	ns.After("EmoteVoice: fishing dry check", 0.5, function()
		if token == fishingToken and Voice.db.situational and Voice.IsSituationalSupported() then
			RecordDryFishingCast()
		end
	end)
end

function Voice:LOOT_OPENED()
	fishingDryCount = 0
	if fishingChannel then
		fishingLooted = true
		fishingChannel = false
	end
	fishingToken = fishingToken + 1
end

function Voice.OnPerformed(token)
	if Voice.db.enabled and Voice.IsSupported() and type(token) == "string" and not ns.Secret(token) then
		token = token:upper()
		if noChat[token] then
			Play(token)
		elseif not known[token] then
			Stop()
		end
	end
end

function Voice.Preview()
	if not Voice.IsSupported() then
		ns.PrintAlways(L.EMOTEVOICE_UNSUPPORTED)
	elseif not Play("WAVE") then
		ns.PrintAlways(L.EMOTEVOICE_MISSING)
	end
end

function Voice.PreviewSituational(category)
	if not Voice.IsSituationalSupported() then
		ns.PrintAlways(L.EMOTEVOICE_SITUATIONAL_UNSUPPORTED)
		return false
	end
	if type(category) ~= "string" then
		previewIndex = (previewIndex % #SITUATIONAL_ORDER) + 1
		category = SITUATIONAL_ORDER[previewIndex]
	end
	local playing = PlaySituational(category, true)
	if not playing then
		ns.PrintAlways(L.EMOTEVOICE_MISSING)
	end
	return playing
end

function Voice.Command(msg)
	local arg = (msg or ""):match("^%S+%s*(.*)$")
	arg = arg and strtrim(arg) or ""
	if arg == "" then
		Voice.PreviewSituational()
		return
	end
	local category = COMMAND_ALIASES[arg]
	if not category then
		ns.PrintAlways(L.EMOTEVOICE_SITUATIONAL_USAGE)
		return
	end
	Voice.PreviewSituational(category)
end

function Voice.ResetSituationalState()
	loginAt = nil
	wasResting, notRestingSince = nil, nil
	breath = nil
	wasOnTaxi, taxiStartedAt = nil, nil
	wasDead = nil
	fishingDryCount, fishingChannel, fishingLooted, fishingToken = 0, false, false, 0
	lastSituationalAt = nil
	wipe(lastCategoryAt)
	wipe(lastVariant)
	previewIndex = 0
	SyncInitialState(true)
end

function Voice:Apply()
	self:ToggleEvent("CHAT_MSG_TEXT_EMOTE", self.db.enabled and self.IsSupported())
	local sitOn = self.db.situational and self.IsSituationalSupported() or false
	for _, event in ipairs(SITUATIONAL_EVENTS) do
		self:ToggleEvent(event, sitOn)
	end
	if not sitOn then
		breath = nil
		fishingChannel = false
		fishingLooted = false
		fishingToken = fishingToken + 1
	end
	Stop()
end

function Voice:OnLogin()
	Build()
	SyncInitialState(true)
	if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
		hooksecurefunc(C_ChatInfo, "PerformEmote", ns.Measured("EmoteVoice: posture", self.OnPerformed))
	end
	self:Apply()
end

function Voice:OnOptionChanged()
	self:Apply()
end

Voice.options = {
	{ key = "enabled", type = "toggle", name = L.EMOTEVOICE_ENABLE, desc = L.EMOTEVOICE_DESC },
	{ type = "button", name = L.EMOTEVOICE_PREVIEW, text = L.QUESTS_TEST, func = Voice.Preview },
	{ key = "situational", type = "toggle", name = L.EMOTEVOICE_SITUATIONAL, desc = L.EMOTEVOICE_SITUATIONAL_DESC, new = true },
	{ key = "situationalCooldown", type = "slider", name = L.EMOTEVOICE_SITUATIONAL_COOLDOWN,
		desc = L.EMOTEVOICE_SITUATIONAL_COOLDOWN_DESC, min = 30, max = 300, step = 15,
		format = function(v) return L.EMOTEVOICE_SITUATIONAL_COOLDOWN_FMT:format(v) end,
		parent = "situational", new = true },
	{ type = "button", name = L.EMOTEVOICE_SITUATIONAL_PREVIEW, text = L.QUESTS_TEST, func = function()
		Voice.PreviewSituational()
	end },
}

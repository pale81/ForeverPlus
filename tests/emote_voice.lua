-- Exercise native macro/menu calls, confirmed chat events, and situational voice triggers.
local root, shared = ...
local locale, race, sex = "deDE", "Dwarf", 2
local ownGUID, otherGUID, secret = "Player-1-Mugrim", "Player-1-Other", {}
local played, stopped, registered = {}, {}, {}
local nativeCalls, nativeFunction = 0
local available = true
local now, resting, onTaxi, dead = 1000, false, false, false
local mirrorProgress, channelName, channelSpellID, itemQualityOverride
local notices = {}
local env = setmetatable({}, { __index = _G })
env._G = env
env.GetLocale = function() return locale end
env.UnitRace = function() return "Zwerg", race end
env.UnitSex = function() return sex end
env.UnitGUID = function() return ownGUID end
env.GetTime = function() return now end
env.IsResting = function() return resting end
env.UnitOnTaxi = function() return onTaxi end
env.UnitIsDeadOrGhost = function() return dead end
env.GetMirrorTimerProgress = function(name) return name == "BREATH" and mirrorProgress or nil end
env.UnitChannelInfo = function(unit)
	if unit == "player" and (channelName or channelSpellID) then
		return channelName, nil, nil, nil, nil, nil, nil, channelSpellID
	end
end
env.C_Spell = {
	GetSpellName = function(id) return id == 7620 and "Angeln" or nil end,
}
env.C_Item = {
	GetItemQualityByID = function() return itemQualityOverride end,
}
env.ERR_INV_FULL = "Inventar ist voll."
env.ERR_FISH_ESCAPED = "Euer Fisch ist entkommen!"
env.ERR_FISH_NOT_HOOKED = "Es hat kein Fisch angebissen."
env.LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
env.LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
env.LOOT_ITEM_PUSHED_SELF = "Ihr erhaltet Gegenstand: %s."
env.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "Ihr erhaltet Gegenstand: %sx%d."
env.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
env.PlaySoundFile = function(path, channel)
	assert(channel == "Dialog", "emote and situational speech use the Dialog volume")
	if not available then return false end
	played[#played + 1] = path
	return true, #played
end
env.StopSound = function(handle) stopped[#stopped + 1] = handle end
env.C_ChatInfo = {
	PerformEmote = function() nativeCalls = nativeCalls + 1 return true end,
}
nativeFunction = env.C_ChatInfo.PerformEmote
env.hooksecurefunc = function(object, method, callback)
	assert(object == env.C_ChatInfo and method == "PerformEmote", "only the native emote API is observed")
	local original = object[method]
	object[method] = function(...)
		local result = original(...)
		callback(...)
		return result
	end
end
local fixture = {
	L = shared.L,
	FormatToPattern = shared.FormatToPattern,
	Secret = function(value) return value == secret end,
	Number = function(value, fallback)
		if type(value) ~= "number" or value == secret then return fallback end
		return value
	end,
	Measured = function(_, callback) return callback end,
	After = function(_, _, callback) callback() end,
	PrintAlways = function(msg) notices[#notices + 1] = msg end,
}
function fixture:NewModule(_, spec)
	spec.db = {}
	for k, v in pairs(spec.defaults or {}) do
		spec.db[k] = v
	end
	spec.ToggleEvent = function(_, event, enabled) registered[event] = enabled and true or nil end
	self.voice = spec
	return spec
end
for _, file in ipairs({ "Data/EmoteVoice.lua", "Modules/EmoteVoice.lua" }) do
	local chunk = assert(loadfile(root .. "/" .. file))
	setfenv(chunk, env)("ForeverPlus", fixture)
end
local voice = fixture.voice
voice:OnLogin()
assert(voice.db.enabled and registered.CHAT_MSG_TEXT_EMOTE, "supported characters start with speech enabled")
assert(voice.db.situational and voice.db.situationalCooldown == 90, "situational defaults start enabled with 90 s cooldown")
assert(registered.PLAYER_UPDATE_RESTING and registered.MIRROR_TIMER_START and registered.CHAT_MSG_LOOT,
	"supported characters register situational listeners")
assert(nativeFunction ~= env.C_ChatInfo.PerformEmote, "test fixture installs the post-hook")

-- Verify new options carry new = true for the Settings NEW badge.
local optionByKey = {}
for _, opt in ipairs(voice.options) do
	if opt.key then optionByKey[opt.key] = opt end
end
assert(optionByKey.enabled and not optionByKey.enabled.new, "existing enabled key stays unchanged")
assert(optionByKey.situational and optionByKey.situational.new == true, "situational toggle carries new = true")
assert(optionByKey.situationalCooldown and optionByKey.situationalCooldown.new == true,
	"situationalCooldown slider carries new = true")

local function Emit(text, guid)
	local args = { [1] = text, [2] = "", [12] = guid }
	voice:CHAT_MSG_TEXT_EMOTE("CHAT_MSG_TEXT_EMOTE", unpack(args, 1, 12))
end

local seen = {}
for _, entry in ipairs(fixture.EmoteVoiceData) do
	local token = entry[1]
	assert(not seen[token], "one voice entry per emote")
	seen[token] = true
	for index = 2, #entry do
		local text = entry[index]:gsub("%%s", function() return "|cffffffff|Hplayer:Brann|h[Brann]|h|r" end)
		local before = #played
		assert(env.C_ChatInfo.PerformEmote(token), "native return value remains intact")
		assert(#played == before, "text emotes wait for their confirmed native chat event")
		Emit(text, ownGUID)
		assert(#played == before + 1, token .. " plays for its own localized emote text")
		local actual = played[#played]:match("([A-Z]+)%.mp3$")
		assert(actual == token or (token == "STARE" and actual == "GAZE"), token .. " selects " .. tostring(actual) .. " for " .. text)
	end
end
assert(#fixture.EmoteVoiceData == 217, "complete silent-emote catalogue")
for _, token in ipairs({ "THANK", "HELLO", "BYE", "CHEER", "LAUGH", "JOKE", "FLIRT", "CRY" }) do
	assert(not seen[token], "native voiced emotes are excluded")
end

local before = #played
Emit("Ihr winkt.", otherGUID)
Emit("Ihr winkt.", nil)
Emit("Ihr winkt.", secret)
Emit(secret, ownGUID)
Emit("Ihr bedankt Euch bei allen.", ownGUID)
Emit("Ein eigener Emote-Text.", ownGUID)
assert(#played == before, "other players, secret data and unrelated/native voiced messages remain quiet")
for _, token in ipairs({ "SIT", "STAND" }) do
	assert(env.C_ChatInfo.PerformEmote(token:lower()))
	before = before + 1
	assert(#played == before and played[before]:find(token .. ".mp3", 1, true), "posture emotes work without a chat event")
end
local stoppedBefore = #stopped
env.C_ChatInfo.PerformEmote("THANK")
assert(#played == before and #stopped == stoppedBefore + 1, "a native voiced emote stops the previous added line")

-- EmoteVoice remains deDE-only, while situational voice supports deDE AND enUS male dwarves.
locale, race, sex = "enUS", "Dwarf", 2
voice:Apply()
assert(not voice.IsSupported() and not registered.CHAT_MSG_TEXT_EMOTE, "enUS does not register German emote chat listener")
assert(voice.IsSituationalSupported() and registered.PLAYER_UPDATE_RESTING, "enUS male dwarf registers situational listeners")

for _, unsupported in ipairs({ { "frFR", "Dwarf", 2 }, { "deDE", "Dwarf", 3 }, { "deDE", "Human", 2 },
	{ "deDE", secret, 2 }, { "deDE", "Dwarf", secret } }) do
	locale, race, sex = unpack(unsupported)
	voice:Apply()
	assert(not registered.CHAT_MSG_TEXT_EMOTE, "unsupported characters do not register the chat listener")
	assert(not registered.PLAYER_UPDATE_RESTING and not registered.CHAT_MSG_LOOT,
		"unsupported characters do not register situational listeners")
	Emit("Ihr winkt.", ownGUID)
	env.C_ChatInfo.PerformEmote("SIT")
	voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL)
	assert(#played == before, "unsupported locale/race/sex never plays the dwarf recordings")
end
locale, race, sex = "deDE", "Dwarf", 2
voice.db.enabled = false
voice:OnOptionChanged()
assert(not registered.CHAT_MSG_TEXT_EMOTE, "disabling unregisters the listener")
Emit("Ihr winkt.", ownGUID)
env.C_ChatInfo.PerformEmote("SIT")
assert(#played == before, "disabling silences chat and posture playback")
voice.Preview()
assert(#played == before + 1 and #stopped > 0, "preview works while disabled and previous speech is stopped")
available = false
voice.Preview()
assert(#notices == 1, "missing audio gives a restart message in the preview")
assert(nativeCalls > 200, "the native entry point is exercised across the catalogue")

---------------------------------------------------------------------------
-- Situational voice tests (deDE & enUS, all 7 triggers, cooldowns, secrets)
---------------------------------------------------------------------------
available = true
voice.db.enabled = true
voice.db.situational = true
voice.db.situationalCooldown = 90
locale, race, sex = "deDE", "Dwarf", 2
now, resting, onTaxi, dead = 2000, false, false, false
mirrorProgress, channelName, channelSpellID, itemQualityOverride = nil, nil, nil, nil
voice:Apply()
voice.ResetSituationalState()

local function LastClip()
	return played[#played] and played[#played]:match("([A-Z_]+_%d+)%.mp3$")
end

-- 1. INN: login grace (5 s) and minimum away time (120 s).
before = #played
now = 2003
resting = true
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
assert(#played == before, "INN suppressed during 5 s login grace and < 120 s away")
resting = false
now = 2010
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
now = 2100 -- only 90 s outside
resting = true
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
assert(#played == before, "INN suppressed when away < 120 s")
resting = false
now = 2110
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
now = 2235 -- 125 s outside (>= 120 s)
resting = true
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
assert(#played == before + 1 and LastClip():find("^INN_%d$"), "INN plays after >= 120 s away and login grace")
assert(played[#played]:find([[SituationalVoice\deDE\DwarfMale\]], 1, true), "deDE situational path used")
-- Repeat while already resting does not re-trigger.
now = 3000
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
assert(#played == before + 1, "INN does not fire when already resting")
-- Login grace after PLAYER_ENTERING_WORLD blocks immediate inn entry even after long session.
resting = false
now = 3100
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
now = 3300
voice:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)
now = 3303
resting = true
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
assert(#played == before + 1, "INN suppressed during 5 s PLAYER_ENTERING_WORLD login grace")
-- Secret IsResting return is ignored.
resting = secret
voice:PLAYER_UPDATE_RESTING("PLAYER_UPDATE_RESTING")
resting = false

-- 2. BREATH: < 25 % when surfacing alive; ignored when plenty of breath, non-BREATH, dead, or secret.
now = 4000
before = #played
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "FATIGUE", 1000, 180000, -1, 0)
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "FATIGUE")
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", secret, 1000, 180000, -1, 0)
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", secret)
assert(#played == before, "non-BREATH and secret mirror timers are ignored")
-- Shallow dive (only 10 s spent, client clears GetMirrorTimerProgress to 0 on stop): must NOT trigger!
mirrorProgress = 0
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0)
now = 4010
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "BREATH")
assert(#played == before, "surfacing with high breath does not trigger even if GetMirrorTimerProgress clears to 0")
-- Deep dive to < 25 % while dead: must NOT trigger!
dead = true
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0)
now = 4160
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "BREATH")
assert(#played == before, "drowning (dead) does not trigger BREATH")
dead = false
-- Deep dive to < 25 % alive (via elapsed time): triggers!
now = 4200
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0)
now = 4350 -- 30000 / 180000 = 16.7 % < 25 %
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "BREATH")
assert(#played == before + 1 and LastClip():find("^BREATH_%d$"), "BREATH plays when surfacing below 25 % alive")
-- Category cooldown (60 s for BREATH) + global cooldown test:
voice.db.situationalCooldown = 30
now = 4395 -- 45 s since last BREATH (> 30 s global, < 60 s BREATH category cooldown)
mirrorProgress = 20000
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0)
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "BREATH")
assert(#played == before + 1, "BREATH respects its 60 s category cooldown")
now = 4415 -- 65 s since last BREATH (>= 60 s)
voice:MIRROR_TIMER_START("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0)
voice:MIRROR_TIMER_STOP("MIRROR_TIMER_STOP", "BREATH")
assert(#played == before + 2 and LastClip():find("^BREATH_%d$"), "BREATH triggers via GetMirrorTimerProgress after 60 s")
mirrorProgress = nil
voice.db.situationalCooldown = 90

-- 3. BAGS_FULL + Global Cooldown + 300 s Category Cooldown.
before = #played
now = 4460 -- only 45 s after BREATH (< 90 s global cooldown)
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL)
assert(#played == before, "global 90 s cooldown suppresses BAGS_FULL")
now = 4510 -- 95 s after BREATH (>= 90 s global cooldown)
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, secret)
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, "Nicht genug Mana.")
assert(#played == before, "secret and unrelated UI errors are ignored")
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL)
assert(#played == before + 1 and LastClip():find("^BAGS_FULL_%d$"), "BAGS_FULL plays on ERR_INV_FULL")
now = 4700 -- 190 s after BAGS_FULL (> 90 s global, < 300 s BAGS_FULL category cooldown)
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL)
assert(#played == before + 1, "BAGS_FULL respects 300 s category cooldown")
now = 4820 -- 310 s after BAGS_FULL (>= 300 s)
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_INV_FULL)
assert(#played == before + 2 and LastClip():find("^BAGS_FULL_%d$"), "BAGS_FULL plays again after 300 s")

-- 4. FLIGHT_END: >= 60 s taxi ride.
before = #played
now = 5000
onTaxi = true
voice:PLAYER_CONTROL_LOST("PLAYER_CONTROL_LOST")
now = 5045 -- 45 s (< 60 s)
onTaxi = false
voice:PLAYER_CONTROL_GAINED("PLAYER_CONTROL_GAINED")
assert(#played == before, "short taxi flight < 60 s does not trigger FLIGHT_END")
now = 5100
onTaxi = true
voice:UNIT_FLAGS("UNIT_FLAGS", "target") -- ignored
assert(#played == before)
voice:UNIT_FLAGS("UNIT_FLAGS", "player")
now = 5170 -- 70 s (>= 60 s)
onTaxi = false
voice:UNIT_FLAGS("UNIT_FLAGS", "player")
assert(#played == before + 1 and LastClip():find("^FLIGHT_END_%d$"), "long flight >= 60 s triggers FLIGHT_END")
onTaxi = secret
voice:UNIT_FLAGS("UNIT_FLAGS", "player")
onTaxi = false

-- 5. EPIC_LOOT: own epic/legendary loot (DE and EN), ignores others, blue items, and secrets.
before = #played
now = 5300
voice:CHAT_MSG_LOOT("CHAT_MSG_LOOT", secret)
voice:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Brann erhält Beute: |cffa335ee|Hitem:19019::::::::60:::::::|h[Donnerzorn]|h|r.")
voice:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Ihr erhaltet Beute: |cff0070dd|Hitem:12345::::::::60:::::::|h[Blaues Schwert]|h|r.")
assert(#played == before, "other players, non-epic loot and secret chat are ignored")
voice:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Ihr erhaltet Beute: |cffa335ee|Hitem:17182::::::::60:::::::|h[Sulfuras]|h|r.")
assert(#played == before + 1 and LastClip():find("^EPIC_LOOT_%d$"), "own epic loot triggers EPIC_LOOT")
-- Test enUS locale + LOOT_ITEM_PUSHED_SELF + quality API fallback.
locale = "enUS"
env.LOOT_ITEM_SELF = "You receive loot: %s."
env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
env.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
env.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
voice:Apply()
now = 5400 -- 100 s later (>= 90 s global and >= 60 s EPIC_LOOT cooldown)
itemQualityOverride = 4
voice:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:19364::::::::60:::::::|h[Ashkandi]|h|r.")
itemQualityOverride = nil
assert(#played == before + 2 and LastClip():find("^EPIC_LOOT_%d$"), "enUS pushed epic item triggers EPIC_LOOT")
assert(played[#played]:find([[SituationalVoice\enUS\DwarfMale\]], 1, true), "enUS situational path used")

-- 6. RESURRECT: PLAYER_DEAD -> ghost PLAYER_ALIVE (ignored) -> alive PLAYER_UNGHOST (plays).
before = #played
now = 5600
voice:PLAYER_ALIVE("PLAYER_ALIVE") -- without prior PLAYER_DEAD
assert(#played == before, "PLAYER_ALIVE without prior death does not trigger")
dead = true
voice:PLAYER_DEAD("PLAYER_DEAD")
voice:PLAYER_ALIVE("PLAYER_ALIVE") -- still ghost
assert(#played == before, "releasing spirit while still dead/ghost does not trigger RESURRECT")
dead = false
voice:PLAYER_UNGHOST("PLAYER_UNGHOST")
assert(#played == before + 1 and LastClip():find("^RESURRECT_%d$"), "returning to life after death triggers RESURRECT")

-- 7. FISHING_DRY: 10 dry casts in a row (error messages or empty channel stops), reset by LOOT_OPENED.
before = #played
now = 5800
for _ = 1, 9 do
	voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_FISH_ESCAPED)
end
assert(#played == before, "9 dry fishing casts do not trigger yet")
voice:LOOT_OPENED("LOOT_OPENED")
for _ = 1, 9 do
	voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_FISH_NOT_HOOKED)
end
assert(#played == before, "LOOT_OPENED resets dry fishing counter")
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_FISH_ESCAPED)
assert(#played == before + 1 and LastClip():find("^FISHING_DRY_%d$"), "10th dry fishing cast triggers FISHING_DRY")
voice:UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 1, env.ERR_FISH_ESCAPED)
assert(#played == before + 1, "dry fishing counter resets after triggering")

-- Channel-based fishing dry detection (and loot reset before channel stop).
now = 6200
voice:LOOT_OPENED("LOOT_OPENED")
channelName, channelSpellID = "Angeln", 7620
for _ = 1, 5 do
	voice:UNIT_SPELLCAST_CHANNEL_START("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
	voice:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
end
-- Catch one fish (LOOT_OPENED during channel before CHANNEL_STOP): resets to 0.
voice:UNIT_SPELLCAST_CHANNEL_START("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
voice:LOOT_OPENED("LOOT_OPENED")
voice:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
-- Non-fishing channel and secret unit are ignored.
voice:UNIT_SPELLCAST_CHANNEL_START("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 12345)
voice:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 12345)
voice:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", secret, nil, 7620)
for _ = 1, 10 do
	voice:UNIT_SPELLCAST_CHANNEL_START("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
	voice:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
end
channelName, channelSpellID = nil, nil
assert(#played == before + 2 and LastClip():find("^FISHING_DRY_%d$"),
	"10 empty fishing channels without loot trigger FISHING_DRY")

-- Variant rotation: never plays the same variant twice in a row.
local seenVariants = {}
local prevClip
for _ = 1, 30 do
	assert(voice.PreviewSituational("INN"), "preview plays INN")
	local clip = LastClip()
	assert(clip ~= prevClip, "situational voice never repeats the same variant twice in a row")
	prevClip = clip
	seenVariants[clip] = true
end
assert(seenVariants.INN_1 and seenVariants.INN_2 and seenVariants.INN_3, "all 3 variants are reachable")

-- Shared sound handle between emote and situational clips.
locale = "deDE"
voice:Apply()
assert(voice.PreviewSituational("INN"), "play situational clip before emote")
stoppedBefore = #stopped
Emit("Ihr winkt.", ownGUID)
assert(#stopped == stoppedBefore + 1, "emote clip stops active situational clip")
stoppedBefore = #stopped
voice.PreviewSituational("EPIC_LOOT")
assert(#stopped == stoppedBefore + 1, "situational clip stops active emote clip")

-- Slash commands and preview while disabled.
voice.db.situational = false
voice:OnOptionChanged()
assert(not registered.PLAYER_UPDATE_RESTING and not registered.CHAT_MSG_LOOT,
	"disabling situational unregisters all situational listeners")
before = #played
voice.Command("stimme taverne")
assert(#played == before + 1 and LastClip():find("^INN_%d$"), "/fp stimme taverne plays INN while disabled")
voice.Command("voice fishing")
assert(#played == before + 2 and LastClip():find("^FISHING_DRY_%d$"), "/fp voice fishing plays FISHING_DRY")
voice.Command("stimme")
assert(#played == before + 3, "/fp stimme with no argument plays next preview category")
local noticesBefore = #notices
voice.Command("stimme ungueltig")
assert(#notices == noticesBefore + 1 and notices[#notices] == shared.L.EMOTEVOICE_SITUATIONAL_USAGE,
	"unknown category prints usage")

-- Verify every rendered situational MP3 exists on disk for both deDE and enUS.
local clipCount = 0
for loc in pairs(voice.SITUATIONAL_LOCALES) do
	for _, info in pairs(voice.SITUATIONAL_CATEGORIES) do
		for _, clip in ipairs(info.clips) do
			local path = root .. "/Media/SituationalVoice/" .. loc .. "/DwarfMale/" .. clip .. ".mp3"
			local file = assert(io.open(path, "rb"), "missing situational audio clip: " .. path)
			local size = file:seek("end")
			file:close()
			assert(size and size > 1000, "situational audio clip is unexpectedly small: " .. path)
			clipCount = clipCount + 1
		end
	end
end
assert(clipCount == 42, "all 42 situational MP3 clips (21 deDE + 21 enUS) exist and are non-empty")

print("German male-dwarf emote speech + DE/EN situational voice OK: 217 emotes, 7 triggers, 42 clips, cooldowns, secrets and settings")

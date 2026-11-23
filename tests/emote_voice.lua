-- Exercise native macro/menu calls and confirmed chat events with the shipped data.
local root, shared = ...
local locale, race, sex = "deDE", "Dwarf", 2
local ownGUID, otherGUID, secret = "Player-1-Mugrim", "Player-1-Other", {}
local played, stopped, registered = {}, {}, {}
local nativeCalls, nativeFunction = 0
local available = true
local env = setmetatable({}, { __index = _G })
env._G = env
env.GetLocale = function() return locale end
env.UnitRace = function() return "Zwerg", race end
env.UnitSex = function() return sex end
env.UnitGUID = function() return ownGUID end
env.PlaySoundFile = function(path, channel)
	assert(channel == "Dialog", "emote speech uses the Dialog volume")
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
local notices = 0
local fixture = {
	L = shared.L,
	FormatToPattern = shared.FormatToPattern,
	Secret = function(value) return value == secret end,
	Measured = function(_, callback) return callback end,
	PrintAlways = function() notices = notices + 1 end,
}
function fixture:NewModule(_, spec)
	spec.db = { enabled = spec.defaults.enabled }
	spec.ToggleEvent = function(_, event, enabled) registered[event] = enabled end
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
assert(nativeFunction ~= env.C_ChatInfo.PerformEmote, "test fixture installs the post-hook")
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
for _, unsupported in ipairs({ { "enUS", "Dwarf", 2 }, { "deDE", "Dwarf", 3 }, { "deDE", "Human", 2 },
	{ "deDE", secret, 2 }, { "deDE", "Dwarf", secret } }) do
	locale, race, sex = unpack(unsupported)
	voice:Apply()
	assert(not registered.CHAT_MSG_TEXT_EMOTE, "unsupported characters do not register the chat listener")
	Emit("Ihr winkt.", ownGUID)
	env.C_ChatInfo.PerformEmote("SIT")
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
assert(notices == 1, "missing audio gives a restart message in the preview")
assert(nativeCalls > 200, "the native entry point is exercised across the catalogue")
print("German male-dwarf emote speech OK: 217 emotes, native calls, localization, targets, GUIDs and settings")

-- German speech for the male dwarf's silent emotes. Playback follows confirmed
-- self-emote chat events. Native commands, targets and animations are handled by
-- the game. SIT and STAND have no chat line and use a read-only post-hook.
local _, ns = ...
local L = ns.L

local Voice = ns:NewModule("EmoteVoice", {
	title = L.EMOTEVOICE_TITLE,
	order = 5.975,
	defaults = {
		enabled = true,
	},
})

local MEDIA = [[Interface\AddOns\ForeverPlus\Media\EmoteVoice\deDE\DwarfMale\]]
local exact, patterns, noChat = {}, {}, {}
local known = {}
local soundHandle

function Voice.IsSupported()
	if GetLocale() ~= "deDE" then
		return false
	end
	local _, race = UnitRace("player")
	local sex = UnitSex("player")
	return not ns.Secret(race) and not ns.Secret(sex) and race == "Dwarf" and sex == 2
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

function Voice:Apply()
	self:ToggleEvent("CHAT_MSG_TEXT_EMOTE", self.db.enabled and self.IsSupported())
	Stop()
end

function Voice:OnLogin()
	Build()
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
}

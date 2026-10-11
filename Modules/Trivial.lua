-- Trivial messages: system lines nobody needs (no longer rested, drunkenness,
-- AFK/DND status, trade results) can be hidden from the chat, each kind on
-- its own. The patterns come from the game's own message formats where it has
-- them; the rested message is matched by its text.
local _, ns = ...
local L = ns.L

local Trivial = ns:NewModule("Trivial", {
	title = L.TRIVIAL_TITLE,
	order = 5.9,
	defaults = {
		enabled = true,
		rested = true,
		drunk = true,
		afk = false,
		trade = false,
		explore = false,
		quest = true,
	},
})

local EVENTS = { "CHAT_MSG_SYSTEM", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_COMBAT_XP_GAIN" }

-- Names of the game's format strings per kind; unknown names are skipped.
local FORMATS = {
	drunk = {
		"DRUNK_MESSAGE_ITEM_SELF1", "DRUNK_MESSAGE_ITEM_SELF2", "DRUNK_MESSAGE_ITEM_SELF3", "DRUNK_MESSAGE_ITEM_SELF4",
		"DRUNK_MESSAGE_SELF1", "DRUNK_MESSAGE_SELF2", "DRUNK_MESSAGE_SELF3", "DRUNK_MESSAGE_SELF4",
		"DRUNK_MESSAGE_ITEM_OTHER1", "DRUNK_MESSAGE_ITEM_OTHER2", "DRUNK_MESSAGE_ITEM_OTHER3", "DRUNK_MESSAGE_ITEM_OTHER4",
		"DRUNK_MESSAGE_OTHER1", "DRUNK_MESSAGE_OTHER2", "DRUNK_MESSAGE_OTHER3", "DRUNK_MESSAGE_OTHER4",
	},
	afk = { "MARKED_AFK", "MARKED_AFK_MESSAGE", "MARKED_DND", "CLEARED_AFK", "CLEARED_DND" },
	trade = { "ERR_TRADE_COMPLETE", "ERR_TRADE_CANCELLED" },
	explore = { "ERR_ZONE_EXPLORED", "ERR_ZONE_EXPLORED_XP" },
	quest = { "ERR_QUEST_ACCEPTED_S" },
}

-- Plain texts (lower case) for lines the game has no named format for.
local TEXTS = {
	rested = { L.TRIVIAL_RESTED_TEXT, "no longer rested", "nicht mehr erholt" },
	explore = { "entdeckt: " }, -- "Höhle der Frostmane entdeckt: 65 Erfahrung erhalten."
}

local matchers = {} -- kind -> list of Lua patterns (anchored) or plain texts

local function Build()
	for kind, names in pairs(FORMATS) do
		local list = {}
		for _, name in ipairs(names) do
			local format = _G[name]
			if type(format) == "string" and format ~= "" then
				list[#list + 1] = { pattern = ns.FormatToPattern(format, true).pattern }
			end
		end
		matchers[kind] = list
	end
	for kind, texts in pairs(TEXTS) do
		local list = matchers[kind] or {}
		for _, plain in ipairs(texts) do
			if type(plain) == "string" and plain ~= "" then
				list[#list + 1] = { plain = plain:lower() }
			end
		end
		matchers[kind] = list
	end
end

local hidden = 0

local function IsTrivial(text)
	local lower
	for kind, list in pairs(matchers) do
		if Trivial.db[kind] then
			for _, matcher in ipairs(list) do
				if matcher.pattern then
					if text:find(matcher.pattern) then
						return true
					end
				else
					lower = lower or text:lower()
					if lower:find(matcher.plain, 1, true) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function Filter(_, _, text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if IsTrivial(text) then
		hidden = hidden + 1
		return true
	end
	return false
end

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

function Trivial:Apply()
	-- Filtered only while at least one kind is on.
	local any = self.db.enabled and (self.db.rested or self.db.drunk or self.db.afk or self.db.trade or self.db.explore or self.db.quest)
	for _, event in ipairs(EVENTS) do
		RemoveFilter(event, Filter)
		if any then
			AddFilter(event, Filter)
		end
	end
end

function Trivial:OnLogin()
	Build()
	self:Apply()
end

function Trivial:OnOptionChanged()
	self:Apply()
end

-- Exposed for /fp diagnose and tests.
function Trivial.Hidden()
	return hidden
end

Trivial.options = {
	{ key = "enabled", type = "toggle", name = L.TRIVIAL_ENABLE, desc = L.TRIVIAL_ENABLE_DESC, new = true },
	{ key = "rested", type = "toggle", name = L.TRIVIAL_RESTED, desc = L.TRIVIAL_RESTED_DESC, parent = "enabled", new = true },
	{ key = "drunk", type = "toggle", name = L.TRIVIAL_DRUNK, desc = L.TRIVIAL_DRUNK_DESC, parent = "enabled", new = true },
	{ key = "afk", type = "toggle", name = L.TRIVIAL_AFK, desc = L.TRIVIAL_AFK_DESC, parent = "enabled", new = true },
	{ key = "trade", type = "toggle", name = L.TRIVIAL_TRADE, desc = L.TRIVIAL_TRADE_DESC, parent = "enabled", new = true },
	{ key = "explore", type = "toggle", name = L.TRIVIAL_EXPLORE, desc = L.TRIVIAL_EXPLORE_DESC, parent = "enabled", new = true },
	{ key = "quest", type = "toggle", name = L.TRIVIAL_QUEST, desc = L.TRIVIAL_QUEST_DESC, parent = "enabled", new = true },
}

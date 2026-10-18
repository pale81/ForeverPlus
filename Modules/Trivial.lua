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
		shown = {}, -- kinds that stay visible although the rest is hidden (exceptions)
		migrated = false,
	},
})

-- The kinds, in the order of the exception list.
local KINDS = { "rested", "drunk", "afk", "trade", "explore", "quest", "flee" }

local EVENTS = { "CHAT_MSG_SYSTEM", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_MONSTER_EMOTE" }

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
	-- "Kobold versucht zu flüchten." (a creature at low health runs away; the text of the emote has the name as %s)
	flee = { "versucht zu flüchten", "versucht zu fliehen", "attempts to run away", "tries to run away", "flees in terror" },
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
		if not Trivial.db.shown[kind] then
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
	local any = self.db.enabled
	if any then
		any = false
		for _, kind in ipairs(KINDS) do
			any = any or not self.db.shown[kind]
		end
	end
	for _, event in ipairs(EVENTS) do
		RemoveFilter(event, Filter)
		if any then
			AddFilter(event, Filter)
		end
	end
end

-- Everything is hidden now; what was switched off before is an exception (once).
function Trivial:OnInitialize()
	local db = self.db
	db.shown = db.shown or {}
	if not db.migrated then
		db.migrated = true
		for _, kind in ipairs(KINDS) do
			if db[kind] == false then
				db.shown[kind] = true
			end
			db[kind] = nil
		end
	end
end

local KIND_NAMES = {
	rested = "TRIVIAL_RESTED", drunk = "TRIVIAL_DRUNK", afk = "TRIVIAL_AFK", trade = "TRIVIAL_TRADE",
	explore = "TRIVIAL_EXPLORE", quest = "TRIVIAL_QUEST", flee = "TRIVIAL_FLEE",
}

-- List of the kinds: checked = hidden; a click makes the kind an exception (shown) and back.
function Trivial:ShowExceptions(owner)
	ns.ShowPopupList(owner, function()
		local items = {}
		for _, kind in ipairs(KINDS) do
			items[#items + 1] = {
				text = L[KIND_NAMES[kind]],
				checked = not self.db.shown[kind],
				onClick = function()
					self.db.shown[kind] = not self.db.shown[kind] or nil
					self:Apply()
				end,
			}
		end
		return { title = L.TRIVIAL_EXCEPTIONS, items = items }
	end, "Trivial")
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
	{ type = "button", name = L.TRIVIAL_EXCEPTIONS, text = L.TRIVIAL_EXCEPTIONS_BUTTON, desc = L.TRIVIAL_EXCEPTIONS_DESC, func = function(button)
		Trivial:ShowExceptions(button)
	end },
}

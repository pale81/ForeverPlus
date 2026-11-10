-- Waypoints from coordinates: "/fp weg 23 34" (or "/way 23 34" as it is written on many web pages; paste it into
-- the chat line) sets the game's own waypoint on the map the player is on, and coordinates written in the chat
-- become a link that does the same. The game shows its waypoint on the world map, on the minimap and, while it is
-- tracked, as a marker with the distance on the screen.
local _, ns = ...
local L = ns.L

local Waypoint = ns:NewModule("Waypoint", {
	title = L.WAYPOINT_TITLE,
	order = 5.35,
	defaults = {
		enabled = true,
		chatLinks = true, -- coordinates in the chat can be clicked
		message = true,
	},
})

local LINK_PREFIX = "addon:ForeverPlus:way:"

-- Two coordinates between 0 and 100 in a text: "23, 34", "23.5 34.2", "23,5 / 34,2" (comma as the decimal sign
-- only with / or ; between the numbers). Returns x, y and what follows them (a name), or nil.
function Waypoint.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local x, y, rest
	local a, b, c, d, tail = text:match("^%s*(%d+),(%d+)%s*[/;]%s*(%d+),(%d+)%s*(.-)%s*$")
	if a then
		x, y, rest = tonumber(a .. "." .. b), tonumber(c .. "." .. d), tail
	else
		a, b, tail = text:match("^%s*(%d+%.?%d*)%s*[,;/%s]%s*(%d+%.?%d*)%s*(.-)%s*$")
		x, y, rest = tonumber(a), tonumber(b), tail
	end
	if not x or not y or x > 100 or y > 100 then
		return nil
	end
	return x, y, rest ~= "" and rest or nil
end

-- Coordinates in a chat line become links: "12.3, 45.6" or "12, 45", a comma and a blank between them ("1,5"
-- without the blank is a German decimal number, not a place).
function Waypoint.Linkify(text)
	return (text:gsub("(%f[%d]%d%d?%.?%d?%d?), (%d%d?%.?%d?%d?%f[^%d%.])", function(first, second)
		local x, y = tonumber(first), tonumber(second)
		if not x or not y or x > 100 or y > 100 then
			return nil
		end
		return ("|cff71d5ff|H%s%s:%s|h[%s, %s]|h|r"):format(LINK_PREFIX, first, second, first, second)
	end))
end

-- Sets the game's waypoint on the map the player is on. Returns whether it worked.
function Waypoint.Set(x, y, name)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print(L.WAYPOINT_NOT_HERE)
		return false
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	if Waypoint.db.message then
		ns.Print(L.WAYPOINT_SET, x, y, name and (" " .. name) or "")
	end
	return true
end

-- /fp weg 23 34 [name], /fp weg (nothing or "weg"/"clear"): removes the waypoint.
function Waypoint.Command(text)
	text = text:gsub("^%S+%s*", "")
	if text == "" or text == "weg" or text == "clear" or text == "löschen" then
		C_Map.ClearUserWaypoint()
		ns.Print(L.WAYPOINT_CLEARED)
		return
	end
	local x, y, name = Waypoint.Parse(text)
	if not x then
		ns.Print(L.WAYPOINT_USAGE)
		return
	end
	Waypoint.Set(x, y, name)
end

local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL" }

local function ChatFilter(_, _, message, ...)
	if type(message) ~= "string" or ns.Secret(message) or not message:find("%d, %d") then
		return false
	end
	local linked = Waypoint.Linkify(message)
	if linked == message then
		return false
	end
	return false, linked, ...
end

local filtering = false

function Waypoint:Apply()
	local on = self.db.enabled and self.db.chatLinks
	if on ~= filtering then
		filtering = on
		for _, event in ipairs(CHAT_EVENTS) do
			(on and ns.AddChatFilter or ns.RemoveChatFilter)(event, ChatFilter)
		end
	end
end

function Waypoint:OnLogin()
	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then
			return
		end
		local x, y = link:sub(#LINK_PREFIX + 1):match("^([%d%.]+):([%d%.]+)$")
		x, y = tonumber(x), tonumber(y)
		if x and y and Waypoint.db.enabled then
			Waypoint.Set(x, y)
		end
	end, self)
	-- "/way 23 34" as web pages give it, unless another addon owns that command.
	if not SlashCmdList.TOMTOM_WAY and not _G.SLASH_FOREVERPLUSWAY1 then
		_G.SLASH_FOREVERPLUSWAY1 = "/way"
		SlashCmdList.FOREVERPLUSWAY = function(text)
			if Waypoint.db.enabled then
				Waypoint.Command("way " .. (text or ""))
			end
		end
	end
	self:Apply()
end

function Waypoint:OnOptionChanged()
	self:Apply()
end

Waypoint.options = {
	{ key = "enabled", type = "toggle", name = L.WAYPOINT_ENABLE, desc = L.WAYPOINT_ENABLE_DESC, new = true },
	{ key = "chatLinks", type = "toggle", name = L.WAYPOINT_CHAT, desc = L.WAYPOINT_CHAT_DESC, parent = "enabled", new = true },
	{ key = "message", type = "toggle", name = L.WAYPOINT_MESSAGE, desc = L.MESSAGE_DESC, parent = "enabled" },
}

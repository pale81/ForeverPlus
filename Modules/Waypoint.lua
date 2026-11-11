-- Waypoints from coordinates: "/fp weg 23 34" (or "/way 23 34" as it is written on many web pages; paste it into
-- the chat line) sets the game's own waypoint on the map the player is on, and coordinates written in the chat
-- become a link that does the same. The game shows its waypoint on the world map and the minimap; the marker on the
-- screen needs the game's navigation frame, which Forever does not create. An arrow of our own points the way
-- instead (to our own waypoint and to the game's, however that was set), with the distance below it.
local _, ns = ...
local L = ns.L

local Waypoint = ns:NewModule("Waypoint", {
	title = L.WAYPOINT_TITLE,
	order = 5.35,
	defaults = {
		enabled = true,
		chatLinks = true, -- coordinates in the chat can be clicked
		message = true,
		arrow = true, -- the arrow on the screen
		clearOnArrival = true, -- the waypoint goes when the player is there
	},
})

local ARRIVAL_YARDS = 5
local target -- { mapID =, x =, y = (0–1), name = } the waypoint the arrow points to

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

-- Distance (yards) and direction from the player to a point on the same map. Map positions run from 0 to 1 (x to
-- the east, y to the south), width and height are the size of the map in yards. facing is the game's (radians,
-- 0 = north, growing to the west); the angle is the turn of an arrow pointing up (counter-clockwise, radians).
function Waypoint.Bearing(px, py, tx, ty, width, height, facing)
	local east, south = (tx - px) * width, (ty - py) * height
	local distance = math.sqrt(east * east + south * south)
	local angle = math.atan2(-east, -south) - (facing or 0)
	return distance, angle
end

local Refresh -- below

-- Sets the waypoint on the map the player is on: our own (for the arrow) and the game's, where the map allows it.
-- Returns whether it worked.
function Waypoint.Set(x, y, name)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		ns.Print(L.WAYPOINT_NOT_HERE)
		return false
	end
	target = { mapID = mapID, x = x / 100, y = y / 100, name = name }
	if C_Map.CanSetUserWaypointOnMap(mapID) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	Refresh()
	if Waypoint.db.message then
		ns.Print(L.WAYPOINT_SET, x, y, name and (" " .. name) or "")
	end
	return true
end

function Waypoint.Clear()
	target = nil
	C_Map.ClearUserWaypoint()
	Refresh()
end

-- /fp weg 23 34 [name], /fp weg (nothing or "weg"/"clear"): removes the waypoint.
function Waypoint.Command(text)
	text = text:gsub("^%S+%s*", "")
	if text == "" or text == "weg" or text == "clear" or text == "löschen" then
		Waypoint.Clear()
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

-- The waypoint the arrow follows: ours, or the game's (set on the map, by the recipe radar …) when that is newer.
function Waypoint.Target()
	local point = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
	if point and point.uiMapID and point.position then
		local x, y = point.position:GetXY()
		if not (target and target.mapID == point.uiMapID and math.abs(target.x - x) < 0.0005 and math.abs(target.y - y) < 0.0005) then
			target = { mapID = point.uiMapID, x = x, y = y }
		end
	end
	return target
end

-- Distance and direction to the waypoint, or nil when the player is not on its map (another zone, an instance).
function Waypoint.Where()
	local goal = Waypoint.Target()
	if not goal then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(goal.mapID, "player")
	local width, height = C_Map.GetMapWorldSize(goal.mapID)
	if not position or not width or width <= 0 or not height or height <= 0 then
		return nil, goal
	end
	local px, py = position:GetXY()
	local distance, angle = Waypoint.Bearing(px, py, goal.x, goal.y, width, height, GetPlayerFacing())
	return distance, goal, angle
end

local arrow
local ARROW_ATLAS, ARROW_FILE = "Navigation-Tracked-Arrow", [[Interface\Minimap\MiniMap-QuestArrow]]

local function UpdateArrow(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait > 0 then
		return
	end
	self.wait = 0.05
	local distance, goal, angle = Waypoint.Where()
	if not goal then
		self:Hide()
		return
	end
	if distance and distance <= ARRIVAL_YARDS and Waypoint.db.clearOnArrival then
		ns.Print(L.WAYPOINT_ARRIVED)
		Waypoint.Clear()
		return
	end
	self.Arrow:SetShown(distance ~= nil)
	if distance then
		self.Arrow:SetRotation(angle)
		self.Text:SetFormattedText(L.WAYPOINT_DISTANCE, distance)
	else
		local info = C_Map.GetMapInfo(goal.mapID)
		self.Text:SetFormattedText(L.WAYPOINT_ELSEWHERE, info and info.name or "?")
	end
	self.Name:SetText(goal.name or ("%.1f, %.1f"):format(goal.x * 100, goal.y * 100))
end

local function CreateArrow()
	arrow = CreateFrame("Frame", "ForeverPlusWaypointArrow", UIParent)
	arrow:SetSize(64, 84)
	arrow:SetFrameStrata("MEDIUM")
	arrow.Arrow = arrow:CreateTexture(nil, "ARTWORK")
	arrow.Arrow:SetSize(48, 48)
	arrow.Arrow:SetPoint("TOP", 0, 0)
	if C_Texture.GetAtlasInfo(ARROW_ATLAS) then
		arrow.Arrow:SetAtlas(ARROW_ATLAS)
	else
		arrow.Arrow:SetTexture(ARROW_FILE)
	end
	arrow.Name = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	arrow.Name:SetPoint("TOP", arrow.Arrow, "BOTTOM", 0, -2)
	arrow.Text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow.Text:SetPoint("TOP", arrow.Name, "BOTTOM", 0, -1)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.WAYPOINT_ARROW)
		GameTooltip_AddInstructionLine(GameTooltip, L.WAYPOINT_ARROW_HINT)
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", GameTooltip_Hide)
	arrow:SetScript("OnMouseUp", function(_, button)
		if button == "MiddleButton" then
			Waypoint.Clear()
			ns.Print(L.WAYPOINT_CLEARED)
		end
	end)
	ns.SetUpdate(arrow, "Waypoint: arrow", UpdateArrow)
	ns:RegisterDisplay(arrow, "WaypointArrow", function(self)
		self:SetPoint("TOP", UIParent, "TOP", 0, -110)
	end)
	arrow:Hide()
end

-- Shows the arrow while there is a waypoint (it hides itself when there is none any more).
function Refresh()
	local db = Waypoint.db
	if not (db.enabled and db.arrow) then
		if arrow then
			arrow:Hide()
		end
		return
	end
	if Waypoint.Target() then
		if not arrow then
			CreateArrow()
		end
		arrow.wait = 0
		arrow:Show()
	elseif arrow then
		arrow:Hide()
	end
end
Waypoint.Refresh = Refresh

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
	self:RegisterEvent("USER_WAYPOINT_UPDATED", Refresh)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", Refresh)
	self:Apply()
end

function Waypoint:OnOptionChanged()
	self:Apply()
	Refresh()
end

Waypoint.options = {
	{ key = "enabled", type = "toggle", name = L.WAYPOINT_ENABLE, desc = L.WAYPOINT_ENABLE_DESC, new = true },
	{ key = "chatLinks", type = "toggle", name = L.WAYPOINT_CHAT, desc = L.WAYPOINT_CHAT_DESC, parent = "enabled", new = true },
	{ key = "message", type = "toggle", name = L.WAYPOINT_MESSAGE, desc = L.MESSAGE_DESC, parent = "enabled" },
	{ key = "arrow", type = "toggle", name = L.WAYPOINT_ARROW, desc = L.WAYPOINT_ARROW_DESC, parent = "enabled", new = true },
	{ key = "clearOnArrival", type = "toggle", name = L.WAYPOINT_ARRIVAL, desc = L.WAYPOINT_ARRIVAL_DESC, parent = "enabled", new = true },
}

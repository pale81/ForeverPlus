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
		arrowStyle = "standard",
		clickArrowStyle = true,
		arrowColor = "DEFAULT",
		arrowCustomColor = { r = 1, g = 0.82, b = 0 },
		corpseArrow = true,
		clearOnArrival = true, -- the waypoint goes when the player is there
		questWaypoint = true, -- clicking a Blizzard quest objective (questPOI) sets a waypoint
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
local EndPreview -- below

local function SetPoint(mapID, x, y, name, allowArrowOnly, keepSuperTrack, questID)
	local canSet = C_Map.CanSetUserWaypointOnMap(mapID)
	if not canSet and not allowArrowOnly then
		return false
	end
	if canSet then
		local wasSet = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		if wasSet == false and not allowArrowOnly then
			return false
		end
		if wasSet ~= false and not keepSuperTrack then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end
	if EndPreview then
		EndPreview(true)
	end
	target = { mapID = mapID, x = x / 100, y = y / 100, name = name, questID = questID }
	Refresh()
	if Waypoint.db.message then
		ns.Print(L.WAYPOINT_SET, x, y, name and (" " .. name) or "")
	end
	return true
end

-- The journal already knows the destination map, which can be a different zone.
function Waypoint.SetOnMap(mapID, x, y, name)
	return SetPoint(mapID, x, y, name, false)
end

-- Sets the waypoint on the map the player is on: our own (for the arrow) and the game's, where the map allows it.
-- Returns whether it worked.
function Waypoint.Set(x, y, name)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		ns.Print(L.WAYPOINT_NOT_HERE)
		return false
	end
	return SetPoint(mapID, x, y, name, true)
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
		-- The waypoint's nested position has x and y, but no vector methods.
		local x, y = point.position.x, point.position.y
		if not (target and target.mapID == point.uiMapID and math.abs(target.x - x) < 0.0005 and math.abs(target.y - y) < 0.0005) then
			target = { mapID = point.uiMapID, x = x, y = y }
		end
	end
	return target
end

local function BearingOnMap(mapID, x, y)
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if ns.Secret(position) or not position then
		return nil
	end
	local width, height = C_Map.GetMapWorldSize(mapID)
	if ns.Number(width, 0) <= 0 or ns.Number(height, 0) <= 0 then
		return nil
	end
	local px, py = position:GetXY()
	if not ns.Number(px) or not ns.Number(py) then
		return nil
	end
	return Waypoint.Bearing(px, py, x, y, width, height, ns.Number(GetPlayerFacing(), 0))
end

-- Distance and direction to the waypoint, or nil when the player is not on its map (another zone, an instance).
function Waypoint.Where()
	local goal = Waypoint.Target()
	if not goal then
		return nil
	end
	local distance, angle = BearingOnMap(goal.mapID, goal.x, goal.y)
	return distance, goal, angle
end

local function CorpseRun()
	if not (Waypoint.db.enabled and Waypoint.db.corpseArrow and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
		return false
	end
	local ghost = UnitIsGhost("player")
	return not ns.Secret(ghost) and ghost == true
end

local function CorpseBearing()
	local mapID = ns.Number(C_Map.GetBestMapForUnit("player"))
	while mapID and mapID > 0 do
		local position = C_DeathInfo.GetCorpseMapPosition(mapID)
		if not ns.Secret(position) and position then
			local x, y = position:GetXY()
			if ns.Number(x) and ns.Number(y) then
				local distance, angle = BearingOnMap(mapID, x, y)
				if distance then
					return distance, angle
				end
			end
		end
		-- A graveyard and its corpse can be in different zones. Try their shared map.
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType == Enum.UIMapType.Continent then
			break
		end
		mapID = info.parentMapID
	end
end

function Waypoint.CheckArrival(distance)
	if distance and distance <= ARRIVAL_YARDS and Waypoint.db.clearOnArrival then
		ns.Print(L.WAYPOINT_ARRIVED)
		Waypoint.Clear()
		return true
	end
	return false
end

function Waypoint.HasGuidanceTarget()
	return CorpseRun() or (Waypoint.Target() ~= nil)
end

-- Shared guidance query (corpse first, then active waypoint) with explicit facing check and same-continent fallback.
-- Returns: distance, goal, angle, kind ("corpse"|"waypoint"|nil), reason ("none"|"no_facing"|"unknown"|"elsewhere"|nil)
function Waypoint.Guidance()
	local facing = ns.Number(GetPlayerFacing())
	if CorpseRun() then
		local corpseGoal = { name = L.WAYPOINT_CORPSE_NAME }
		if not facing then
			return nil, corpseGoal, nil, "corpse", "no_facing"
		end
		local distance, angle = CorpseBearing()
		return distance, corpseGoal, angle, "corpse", distance and nil or "unknown"
	end
	local goal = Waypoint.Target()
	if not goal then
		return nil, nil, nil, nil, "none"
	end
	if not facing then
		return nil, goal, nil, "waypoint", "no_facing"
	end
	local distance, angle = BearingOnMap(goal.mapID, goal.x, goal.y)
	if distance then
		return distance, goal, angle, "waypoint", nil
	end
	if CreateVector2D and C_Map.GetWorldPosFromMapPos then
		local playerMap = ns.Number(C_Map.GetBestMapForUnit("player"))
		local playerPos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
		if playerPos and not ns.Secret(playerPos) then
			local playerContinent, playerWorld = C_Map.GetWorldPosFromMapPos(playerMap, playerPos)
			local goalContinent, goalWorld = C_Map.GetWorldPosFromMapPos(goal.mapID, CreateVector2D(goal.x, goal.y))
			if playerContinent and goalContinent and not ns.Secret(playerContinent) and not ns.Secret(goalContinent)
				and playerContinent == goalContinent and playerWorld and goalWorld
				and not ns.Secret(playerWorld) and not ns.Secret(goalWorld) then
				local px, py = playerWorld:GetXY()
				local gx, gy = goalWorld:GetXY()
				px, py, gx, gy = ns.Number(px), ns.Number(py), ns.Number(gx), ns.Number(gy)
				if px and py and gx and gy then
					local north, west = gx - px, gy - py
					return math.sqrt(north * north + west * west), goal, math.atan2(west, north) - facing, "waypoint", nil
				end
			end
		end
	end
	return nil, goal, nil, "waypoint", "elsewhere"
end

local function ArrowSuppressed()
	local wind = ns:GetModule("GuidingWind")
	return wind and wind.HidesWaypointArrow and wind.HidesWaypointArrow() or false
end

local arrow
local ARROW_ATLAS, ARROW_FILE = "Navigation-Tracked-Arrow", [[Interface\Minimap\MiniMap-QuestArrow]]
local ARROW_SHEET = [[Interface\AddOns\ForeverPlus\Media\WaypointArrows.tga]]
local UV_INSET = 1 / 256
local CORPSE_COLOR = { r = 0.40, g = 0.85, b = 1.00 }
local PREVIEW_SECONDS = 4

local ARROW_STYLES = {
	{ key = "standard", label = "WAYPOINT_STYLE_STANDARD" },
	{ key = "classic", label = "WAYPOINT_STYLE_CLASSIC", col = 0, row = 0 },
	{ key = "compass", label = "WAYPOINT_STYLE_COMPASS", col = 1, row = 0 },
	{ key = "chevron", label = "WAYPOINT_STYLE_CHEVRON", col = 0, row = 1 },
	{ key = "rune", label = "WAYPOINT_STYLE_RUNE", col = 1, row = 1 },
}
local ARROW_STYLES_BY_KEY = {}
for _, entry in ipairs(ARROW_STYLES) do
	ARROW_STYLES_BY_KEY[entry.key] = entry
end

local ARROW_COLORS = {
	{ key = "DEFAULT", label = "WAYPOINT_COLOR_DEFAULT", hex = "ffd100", r = 1.00, g = 0.82, b = 0.00 },
	{ key = "WHITE", label = "WAYPOINT_COLOR_WHITE", hex = "f2f5ff", r = 0.95, g = 0.96, b = 1.00 },
	{ key = "BLUE", label = "WAYPOINT_COLOR_BLUE", hex = "45c8ff", r = 0.27, g = 0.78, b = 1.00 },
	{ key = "ORANGE", label = "WAYPOINT_COLOR_ORANGE", hex = "ff8426", r = 1.00, g = 0.52, b = 0.15 },
	{ key = "GREEN", label = "WAYPOINT_COLOR_GREEN", hex = "4dff6a", r = 0.30, g = 1.00, b = 0.42 },
	{ key = "RED", label = "WAYPOINT_COLOR_RED", hex = "ff4242", r = 1.00, g = 0.26, b = 0.26 },
	{ key = "PURPLE", label = "WAYPOINT_COLOR_PURPLE", hex = "c46bff", r = 0.77, g = 0.42, b = 1.00 },
	{ key = "CUSTOM", label = "WAYPOINT_COLOR_CUSTOM" },
}
local ARROW_COLORS_BY_KEY = {}
for _, entry in ipairs(ARROW_COLORS) do
	ARROW_COLORS_BY_KEY[entry.key] = entry
end

Waypoint.ARROW_STYLES = ARROW_STYLES
Waypoint.ARROW_COLORS = ARROW_COLORS

local previewActive = false
local previewHold = false
local previewTimer
local previewPanel
local settingsHideHooked = false

local function ClampChannel(value, fallback)
	local number = tonumber(value)
	return number and math.min(1, math.max(0, number)) or fallback
end

function Waypoint.CustomColor(db)
	local source = db and db.arrowCustomColor
	local default = Waypoint.defaults.arrowCustomColor
	if type(source) ~= "table" then
		return default.r, default.g, default.b
	end
	return ClampChannel(source.r, default.r), ClampChannel(source.g, default.g), ClampChannel(source.b, default.b)
end

local function ColorHex(r, g, b)
	return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function ColorLabel(db)
	db = db or Waypoint.db
	local color = ARROW_COLORS_BY_KEY[db and db.arrowColor] or ARROW_COLORS[1]
	local hex = color.hex
	if not hex then
		local r, g, b = Waypoint.CustomColor(db)
		hex = ColorHex(r, g, b)
	end
	return ("|cff%s%s|r"):format(hex, L[color.label])
end

function Waypoint.ArrowAppearance(isCorpse, db)
	db = db or Waypoint.db
	local style = ARROW_STYLES_BY_KEY[db and db.arrowStyle] or ARROW_STYLES[1]
	local isStandard = style.key == "standard"
	if isCorpse then
		return style, CORPSE_COLOR.r, CORPSE_COLOR.g, CORPSE_COLOR.b, isStandard
	end
	local colorKey = db and db.arrowColor
	if colorKey == "CUSTOM" then
		local r, g, b = Waypoint.CustomColor(db)
		return style, r, g, b, isStandard
	end
	local color = ARROW_COLORS_BY_KEY[colorKey] or ARROW_COLORS[1]
	if isStandard and color.key == "DEFAULT" then
		return style, 1, 1, 1, false
	end
	return style, color.r, color.g, color.b, isStandard
end

function Waypoint.StyleMarkup(styleKey, db)
	db = db or Waypoint.db
	local style = ARROW_STYLES_BY_KEY[styleKey] or ARROW_STYLES[1]
	if style.col ~= nil then
		local _, r, g, b = Waypoint.ArrowAppearance(false, {
			arrowStyle = style.key,
			arrowColor = db and db.arrowColor,
			arrowCustomColor = db and db.arrowCustomColor,
		})
		local left = style.col * 128 + 1
		local right = (style.col + 1) * 128 - 1
		local top = style.row * 128 + 1
		local bottom = (style.row + 1) * 128 - 1
		local cr = math.floor(r * 255 + 0.5)
		local cg = math.floor(g * 255 + 0.5)
		local cb = math.floor(b * 255 + 0.5)
		return ("|T%s:18:18:0:0:256:256:%d:%d:%d:%d:%d:%d:%d|t "):format(
			ARROW_SHEET, left, right, top, bottom, cr, cg, cb)
	end
	if C_Texture.GetAtlasInfo(ARROW_ATLAS) and type(CreateAtlasMarkup) == "function" then
		return CreateAtlasMarkup(ARROW_ATLAS, 18, 18) .. " "
	end
	return ("|T%s:18:18|t "):format(ARROW_FILE)
end

local function ApplyArrowAppearance(self, isCorpse)
	if not (self and self.Arrow) then
		return
	end
	local style, r, g, b, desaturate = Waypoint.ArrowAppearance(isCorpse)
	local tex = self.Arrow
	if self.lastStyleKey ~= style.key then
		self.lastStyleKey = style.key
		self.lastAngle = nil
		if style.col ~= nil then
			tex:SetTexture(ARROW_SHEET, nil, nil, "TRILINEAR")
			local left = style.col * 0.5 + UV_INSET
			local right = (style.col + 1) * 0.5 - UV_INSET
			local top = style.row * 0.5 + UV_INSET
			local bottom = (style.row + 1) * 0.5 - UV_INSET
			tex:SetTexCoord(left, right, top, bottom)
		elseif C_Texture.GetAtlasInfo(ARROW_ATLAS) then
			tex:SetAtlas(ARROW_ATLAS)
		else
			tex:SetTexture(ARROW_FILE)
			tex:SetTexCoord(0, 1, 0, 1)
		end
	end
	if self.lastDesat ~= desaturate then
		self.lastDesat = desaturate
		if tex.SetDesaturated then
			tex:SetDesaturated(desaturate)
		end
	end
	if self.lastR ~= r or self.lastG ~= g or self.lastB ~= b then
		self.lastR, self.lastG, self.lastB = r, g, b
		tex:SetVertexColor(r, g, b)
	end
end

local function CancelPreviewTimer()
	if previewTimer then
		previewTimer:Cancel()
		previewTimer = nil
	end
end

function EndPreview(silent)
	CancelPreviewTimer()
	if previewPanel then
		previewPanel:Hide()
	end
	if not previewActive then
		previewHold = false
		return
	end
	previewActive = false
	previewHold = false
	if not silent then
		Refresh()
	end
end

local function UpdatePreviewPanel(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait > 0 then
		return
	end
	self.wait = 0.15
	if previewHold and not (ColorPickerFrame and ColorPickerFrame:IsShown()) then
		previewHold = false
		CancelPreviewTimer()
		previewTimer = ns.NewTimer("Waypoint: preview", PREVIEW_SECONDS, function()
			EndPreview(false)
		end)
	end
end

local function EnsurePreviewPanel()
	if previewPanel then
		return previewPanel
	end
	previewPanel = ns.CreatePanel("ForeverPlusWaypointPreview", { strata = "DIALOG", close = true, escape = false })
	previewPanel:SetSize(186, 152)
	previewPanel.Title:SetText(L.WAYPOINT_ARROW)
	previewPanel.Arrow = previewPanel:CreateTexture(nil, "ARTWORK")
	previewPanel.Arrow:SetSize(64, 64)
	previewPanel.Arrow:SetPoint("TOP", 0, -34)
	previewPanel.StyleName = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewPanel.StyleName:SetPoint("TOP", previewPanel.Arrow, "BOTTOM", 0, -8)
	previewPanel.ColorName = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewPanel.ColorName:SetPoint("TOP", previewPanel.StyleName, "BOTTOM", 0, -3)
	if previewPanel.Close then
		previewPanel.Close:SetScript("OnClick", ns.Measured("Waypoint: close preview", function()
			EndPreview(false)
		end))
	end
	ns.SetUpdate(previewPanel, "Waypoint: preview panel", UpdatePreviewPanel)
	return previewPanel
end

local function HookSettingsPanelHide()
	if settingsHideHooked then
		return
	end
	if SettingsPanel and type(SettingsPanel.HookScript) == "function" then
		settingsHideHooked = true
		SettingsPanel:HookScript("OnHide", ns.Measured("Waypoint: hide preview with settings", function()
			EndPreview(false)
		end))
	end
end

local function SettingsVisible()
	return SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() or false
end

local function ShowPreviewPanel()
	HookSettingsPanelHide()
	local panel = EnsurePreviewPanel()
	local style = Waypoint.ArrowAppearance(false)
	ApplyArrowAppearance(panel, false)
	panel.StyleName:SetText(L[style.label])
	panel.ColorName:SetText(ColorLabel(Waypoint.db))
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", SettingsPanel, "TOPRIGHT", 8, -40)
	panel.wait = 0
	panel:Show()
end

local function StyleValues()
	local values = {}
	for _, entry in ipairs(ARROW_STYLES) do
		values[#values + 1] = { entry.key, Waypoint.StyleMarkup(entry.key) .. L[entry.label] }
	end
	return values
end

local function ColorValues()
	local values = {}
	for _, entry in ipairs(ARROW_COLORS) do
		local hex = entry.hex
		if not hex then
			local r, g, b = Waypoint.CustomColor(Waypoint.db)
			hex = ColorHex(r, g, b)
		end
		values[#values + 1] = { entry.key, ("|cff%s%s|r"):format(hex, L[entry.label]) }
	end
	return values
end

local function SetArrowDisplay(self, name, showArrow, angle, distText, distYards)
	if self.lastName ~= name then
		self.lastName = name
		self.Name:SetText(name)
	end
	if self.lastArrowShown ~= showArrow then
		self.lastArrowShown = showArrow
		self.Arrow:SetShown(showArrow)
	end
	if showArrow and angle then
		local quant = math.floor(angle * 100 + 0.5)
		if self.lastAngle ~= quant then
			self.lastAngle = quant
			self.Arrow:SetRotation(angle)
		end
	end
	if distYards ~= nil then
		local rounded = math.floor(distYards + 0.5)
		if self.lastDistYards ~= rounded or self.lastDistText ~= nil then
			self.lastDistYards, self.lastDistText = rounded, nil
			self.Text:SetFormattedText(L.WAYPOINT_DISTANCE, distYards)
		end
	elseif self.lastDistText ~= distText then
		self.lastDistYards, self.lastDistText = nil, distText
		self.Text:SetText(distText)
	end
end

local function UpdateArrow(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait > 0 then
		return
	end
	self.wait = 0.05
	if ArrowSuppressed() then
		self:Hide()
		return
	end
	if CorpseRun() then
		if not (previewPanel and previewPanel:IsShown()) then
			EndPreview(true)
		end
		ApplyArrowAppearance(self, true)
		local distance, angle = CorpseBearing()
		if distance then
			SetArrowDisplay(self, L.WAYPOINT_CORPSE_NAME, distance > 0, angle, nil, distance)
		else
			SetArrowDisplay(self, L.WAYPOINT_CORPSE_NAME, false, nil, L.WAYPOINT_CORPSE_UNKNOWN, nil)
			self.wait = 0.25
		end
		return
	end
	if not Waypoint.db.arrow then
		EndPreview(true)
		self:Hide()
		return
	end
	local distance, goal, angle = Waypoint.Where()
	if not goal then
		if previewActive and not (previewPanel and previewPanel:IsShown()) then
			if previewHold and not (ColorPickerFrame and ColorPickerFrame:IsShown()) then
				previewHold = false
				CancelPreviewTimer()
				previewTimer = ns.NewTimer("Waypoint: preview", PREVIEW_SECONDS, function()
					EndPreview(false)
				end)
			end
			ApplyArrowAppearance(self, false)
			SetArrowDisplay(self, L.WAYPOINT_ARROW, true, 0, nil, 42)
			return
		end
		self:Hide()
		return
	end
	if not (previewPanel and previewPanel:IsShown()) then
		EndPreview(true)
	end
	ApplyArrowAppearance(self, false)
	if Waypoint.CheckArrival(distance) then
		return
	end
	local goalName = goal.name or ("%.1f, %.1f"):format(goal.x * 100, goal.y * 100)
	if distance then
		SetArrowDisplay(self, goalName, true, angle, nil, distance)
	else
		local info = C_Map.GetMapInfo(goal.mapID)
		SetArrowDisplay(self, goalName, false, nil, L.WAYPOINT_ELSEWHERE:format(info and info.name or "?"), nil)
	end
end

local function SelectArrowStyle(key)
	ns.SetOption("Waypoint", "arrowStyle", key)
	if not SettingsVisible() then
		return
	end
	-- Refresh just our visible dropdown label after changing its backing value.
	local list = SettingsPanel:GetSettingsList()
	local setting = Settings.GetSetting("ForeverPlus_Waypoint_arrowStyle")
	if list and list.ScrollBox and setting then
		list.ScrollBox:ForEachFrame(function(row)
			if row.GetSetting and row:GetSetting() == setting then
				local dropdown = row.Control.Dropdown
				dropdown:UpdateToMenuSelections(dropdown:GetMenuDescription())
			end
		end)
	end
end

local function CycleArrowStyle()
	local current = ARROW_STYLES_BY_KEY[Waypoint.db.arrowStyle] or ARROW_STYLES[1]
	for i, style in ipairs(ARROW_STYLES) do
		if style == current then
			SelectArrowStyle(ARROW_STYLES[i % #ARROW_STYLES + 1].key)
			return
		end
	end
end

local function CreateArrow()
	arrow = CreateFrame("Button", "ForeverPlusWaypointArrow", UIParent)
	arrow:RegisterForClicks("LeftButtonUp")
	arrow:SetScript("OnClick", ns.Measured("Waypoint: cycle arrow design", function(_, button)
		if button == "LeftButton" and Waypoint.db.clickArrowStyle then
			CycleArrowStyle()
		end
	end))
	arrow:SetScript("OnDoubleClick", ns.Measured("Waypoint: reset arrow design", function(_, button)
		if button == "LeftButton" and Waypoint.db.clickArrowStyle then
			SelectArrowStyle(Waypoint.defaults.arrowStyle)
		end
	end))
	arrow:SetSize(64, 84)
	arrow:SetFrameStrata("MEDIUM")
	arrow.Arrow = arrow:CreateTexture(nil, "ARTWORK")
	arrow.Arrow:SetSize(48, 48)
	arrow.Arrow:SetPoint("TOP", 0, 0)
	ApplyArrowAppearance(arrow, false)
	arrow.Name = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	arrow.Name:SetPoint("TOP", arrow.Arrow, "BOTTOM", 0, -2)
	arrow.Text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow.Text:SetPoint("TOP", arrow.Name, "BOTTOM", 0, -1)
	arrow:SetScript("OnEnter", ns.Measured("Waypoint: arrow tooltip", function(self)
		local corpse = CorpseRun()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, corpse and L.WAYPOINT_CORPSE or L.WAYPOINT_ARROW)
		if Waypoint.db.clickArrowStyle then
			GameTooltip_AddInstructionLine(GameTooltip, L.WAYPOINT_STYLE_CLICK_HINT)
		end
		GameTooltip_AddInstructionLine(GameTooltip, corpse and L.WAYPOINT_CORPSE_HINT or L.WAYPOINT_ARROW_HINT)
		GameTooltip:Show()
	end))
	arrow:SetScript("OnLeave", GameTooltip_Hide)
	arrow:SetScript("OnMouseUp", ns.Measured("Waypoint: arrow click", function(_, button)
		if button == "MiddleButton" and not CorpseRun() then
			if previewActive and not (previewPanel and previewPanel:IsShown()) then
				EndPreview(false)
				return
			end
			Waypoint.Clear()
			ns.Print(L.WAYPOINT_CLEARED)
		end
	end))
	ns.SetUpdate(arrow, "Waypoint: arrow", UpdateArrow)
	ns:RegisterDisplay(arrow, "WaypointArrow", function(self)
		self:SetPoint("TOP", UIParent, "TOP", 0, -110)
	end)
	arrow:Hide()
end

-- The corpse temporarily takes priority over any existing waypoint.
function Refresh()
	local db = Waypoint.db
	local corpse = CorpseRun()
	local arrowPreview = previewActive and not (previewPanel and previewPanel:IsShown())
	local hasGoal = db.enabled and db.arrow and (Waypoint.Target() ~= nil or arrowPreview)
	if not ArrowSuppressed() and (corpse or hasGoal) then
		if not arrow then
			CreateArrow()
		end
		ApplyArrowAppearance(arrow, corpse)
		arrow.wait = 0
		arrow:Show()
	elseif arrow then
		arrow:Hide()
	end
	local wind = ns:GetModule("GuidingWind")
	if wind and wind.OnWaypointChanged then
		wind.OnWaypointChanged()
	end
end
Waypoint.Refresh = Refresh

function Waypoint.Preview(keepOpen)
	local db = Waypoint.db
	if not (db and db.enabled and db.arrow) then
		EndPreview(true)
		Refresh()
		return
	end
	local inSettings = SettingsVisible()
	if not inSettings and (ArrowSuppressed() or CorpseRun() or Waypoint.Target()) then
		EndPreview(true)
		Refresh()
		return
	end
	CancelPreviewTimer()
	previewActive = true
	previewHold = keepOpen and true or false
	if inSettings then
		ShowPreviewPanel()
		Refresh()
	else
		if previewPanel then
			previewPanel:Hide()
		end
		if not arrow then
			CreateArrow()
		end
		ApplyArrowAppearance(arrow, false)
		SetArrowDisplay(arrow, L.WAYPOINT_ARROW, true, 0, nil, 42)
		arrow.wait = 0
		arrow:Show()
	end
	if not previewHold then
		previewTimer = ns.NewTimer("Waypoint: preview", PREVIEW_SECONDS, function()
			EndPreview(false)
		end)
	end
end

local syncingColor = false
local function SyncColorSetting(value)
	local setting = Settings and Settings.GetSetting and Settings.GetSetting("ForeverPlus_Waypoint_arrowColor")
	if setting and type(setting.SetValue) == "function"
		and (type(setting.GetValue) ~= "function" or setting:GetValue() ~= value) then
		syncingColor = true
		local ok, err = pcall(setting.SetValue, setting, value)
		syncingColor = false
		if not ok then
			error(err, 0)
		end
	end
end

function Waypoint.ChooseColor()
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
		return
	end
	local db = Waypoint.db
	local r, g, b = Waypoint.CustomColor(db)
	local before = { key = db.arrowColor, color = { r = r, g = g, b = b } }
	local function ApplyPicked()
		local newR, newG, newB = ColorPickerFrame:GetColorRGB()
		db.arrowCustomColor = {
			r = ClampChannel(newR, r),
			g = ClampChannel(newG, g),
			b = ClampChannel(newB, b),
		}
		db.arrowColor = "CUSTOM"
		SyncColorSetting("CUSTOM")
		Waypoint.Preview(true)
	end
	Waypoint.Preview(true)
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, hasOpacity = false,
		swatchFunc = ApplyPicked,
		cancelFunc = function()
			db.arrowCustomColor = before.color
			db.arrowColor = before.key
			SyncColorSetting(before.key)
			if previewActive then
				Waypoint.Preview(false)
			else
				Refresh()
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Blizzard quest objectives (questPOI): clicking a quest objective sets a
-- waypoint and shows the arrow without replacing Blizzard's quest tracking.
---------------------------------------------------------------------------
local function ValidCoord(x, y)
	x, y = ns.Number(x), ns.Number(y)
	if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		return x, y
	end
end

local function FindQuestOnMap(mapID, questID, refX, refY)
	local quests = C_QuestLog and C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID)
	if type(quests) == "table" and not ns.Secret(quests) then
		local bestX, bestY, bestDist
		for _, info in ipairs(quests) do
			if type(info) == "table" and not ns.Secret(info) and ns.Number(info.questID) == questID then
				local x, y = ValidCoord(info.x, info.y)
				if x then
					if not refX then
						return x, y
					end
					local dx, dy = x - refX, y - refY
					local dist = dx * dx + dy * dy
					if not bestDist or dist < bestDist then
						bestX, bestY, bestDist = x, y, dist
					end
				end
			end
		end
		if bestX then
			return bestX, bestY
		end
	end
	if C_QuestLog and C_QuestLog.GetNextWaypointForMap then
		local wx, wy = C_QuestLog.GetNextWaypointForMap(questID, mapID)
		wx, wy = ValidCoord(wx, wy)
		if wx then
			return wx, wy
		end
	end
end

local function NextWaypointForQuest(questID)
	if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then
		return nil
	end
	local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
	mapID = ns.Number(mapID)
	x, y = ValidCoord(x, y)
	if mapID and mapID > 0 and x then
		return mapID, x, y
	end
end

function Waypoint.QuestPoint(questID, pin)
	questID = ns.Number(questID)
	if not questID or questID <= 0 then
		return nil
	end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if type(title) ~= "string" or ns.Secret(title) or title == "" then
		title = nil
	end
	if type(pin) == "table" then
		local map = type(pin.GetMap) == "function" and pin:GetMap()
		local pinMapID = map and type(map.GetMapID) == "function" and ns.Number(map:GetMapID())
		local px, py
		if type(pin.GetPosition) == "function" then
			px, py = pin:GetPosition()
		else
			px, py = pin.normalizedX, pin.normalizedY
		end
		px, py = ValidCoord(px, py)
		if pinMapID and pinMapID > 0 then
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pinMapID)
			local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent
			if info and continentType and info.mapType == continentType then
				local wMap, wx, wy = NextWaypointForQuest(questID)
				if wMap then
					return wMap, wx, wy, title
				end
			end
			local fx, fy = FindQuestOnMap(pinMapID, questID, px, py)
			if fx then
				return pinMapID, fx, fy, title
			end
			if px then
				return pinMapID, px, py, title
			end
		end
	end
	local wMap, wx, wy = NextWaypointForQuest(questID)
	if wMap then
		return wMap, wx, wy, title
	end
	local playerMap = C_Map and C_Map.GetBestMapForUnit and ns.Number(C_Map.GetBestMapForUnit("player"))
	if playerMap and playerMap > 0 then
		local fx, fy = FindQuestOnMap(playerMap, questID)
		if fx then
			return playerMap, fx, fy, title
		end
	end
	local openMap = WorldMapFrame and WorldMapFrame:IsShown() and type(WorldMapFrame.GetMapID) == "function"
		and ns.Number(WorldMapFrame:GetMapID())
	if openMap and openMap > 0 and openMap ~= playerMap then
		local fx, fy = FindQuestOnMap(openMap, questID)
		if fx then
			return openMap, fx, fy, title
		end
	end
end

local function OnQuestPOIClick(pin, button)
	if button ~= "LeftButton" or not (Waypoint.db.enabled and Waypoint.db.questWaypoint and GetCVarBool("questPOI")) then
		return
	end
	if IsShiftKeyDown and IsShiftKeyDown() then
		return
	end
	local questID = pin and type(pin.GetQuestID) == "function" and ns.Number(pin:GetQuestID())
	if not questID or questID <= 0 then
		return
	end
	local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and ns.Number(C_SuperTrack.GetSuperTrackedQuestID())
	if superTracked == questID then
		local mapID, x, y, title = Waypoint.QuestPoint(questID, pin)
		if mapID and x and y then
			SetPoint(mapID, x * 100, y * 100, title, true, true, questID)
		end
	elseif not superTracked or superTracked == 0 then
		if target and target.questID == questID then
			Waypoint.Clear()
		end
	end
end

local function OnQuestPinEnter(_, pin, questID)
	if not (Waypoint.db.enabled and Waypoint.db.questWaypoint and GetCVarBool("questPOI")) then
		return
	end
	if not (GameTooltip and GameTooltip:IsShown() and ns.Number(questID)) then
		return
	end
	if pin and type(GameTooltip.GetOwner) == "function" and GameTooltip:GetOwner() ~= pin then
		return
	end
	GameTooltip_AddInstructionLine(GameTooltip, L.WAYPOINT_QUEST_CLICK)
	GameTooltip:Show()
end

local function OnQuestEnded(_, _, questID)
	if target and target.questID and ns.Number(questID) == target.questID then
		Waypoint.Clear()
	end
end

local poiHooked = false
local function HookQuestPOI()
	if poiHooked then
		return
	end
	local mixin = rawget(_G, "POIButtonMixin")
	if type(mixin) == "table" and type(mixin.OnClick) == "function" then
		poiHooked = true
		hooksecurefunc(mixin, "OnClick", ns.Measured("Waypoint: quest POI click", OnQuestPOIClick))
	end
end
Waypoint.HookQuestPOI = HookQuestPOI
Waypoint.OnQuestPOIClick = OnQuestPOIClick
Waypoint.OnQuestPinEnter = OnQuestPinEnter

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

function Waypoint:OnInitialize()
	ns.OnAddOnLoaded("Blizzard_POIButton", HookQuestPOI)
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
	EventRegistry:RegisterCallback("MapCanvas.QuestPin.OnEnter", ns.Measured("Waypoint: quest pin tooltip", OnQuestPinEnter), self)
	ns.OnAddOnLoaded("Blizzard_POIButton", HookQuestPOI)
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
	self:RegisterEvent("PLAYER_ALIVE", Refresh)
	self:RegisterEvent("PLAYER_UNGHOST", Refresh)
	self:RegisterEvent("QUEST_TURNED_IN", OnQuestEnded)
	self:RegisterEvent("QUEST_REMOVED", OnQuestEnded)
	self:Apply()
end

function Waypoint:OnOptionChanged(key)
	if syncingColor then
		return
	end
	self:Apply()
	if not (self.db.enabled and self.db.arrow) then
		EndPreview(true)
		Refresh()
		return
	end
	if key == "arrowStyle" or key == "arrowColor" then
		Waypoint.Preview(false)
		return
	end
	Refresh()
end

Waypoint.options = {
	{ key = "enabled", type = "toggle", name = L.WAYPOINT_ENABLE, desc = L.WAYPOINT_ENABLE_DESC, new = true },
	{ key = "chatLinks", type = "toggle", name = L.WAYPOINT_CHAT, desc = L.WAYPOINT_CHAT_DESC, parent = "enabled", new = true },
	{ key = "questWaypoint", type = "toggle", name = L.WAYPOINT_QUEST, desc = L.WAYPOINT_QUEST_DESC, parent = "enabled", new = true },
	{ key = "message", type = "toggle", name = L.WAYPOINT_MESSAGE, desc = L.MESSAGE_DESC, parent = "enabled" },
	{ key = "arrow", type = "toggle", name = L.WAYPOINT_ARROW, desc = L.WAYPOINT_ARROW_DESC, parent = "enabled", new = true },
	{ key = "arrowStyle", type = "dropdown", name = L.WAYPOINT_STYLE, desc = L.WAYPOINT_STYLE_DESC, parent = "arrow", values = StyleValues, new = true },
	{ key = "clickArrowStyle", type = "toggle", name = L.WAYPOINT_STYLE_CLICK, desc = L.WAYPOINT_STYLE_CLICK_HINT, parent = "arrow" },
	{ key = "arrowColor", type = "dropdown", name = L.WAYPOINT_COLOR, desc = L.WAYPOINT_COLOR_DESC, parent = "arrow", values = ColorValues, new = true },
	{ type = "button", name = L.WAYPOINT_CUSTOM_COLOR, text = L.WAYPOINT_CUSTOM_COLOR_BTN, desc = L.WAYPOINT_CUSTOM_COLOR_DESC, func = Waypoint.ChooseColor },
	{ key = "corpseArrow", type = "toggle", name = L.WAYPOINT_CORPSE, desc = L.WAYPOINT_CORPSE_DESC, parent = "enabled" },
	{ key = "clearOnArrival", type = "toggle", name = L.WAYPOINT_ARRIVAL, desc = L.WAYPOINT_ARRIVAL_DESC, parent = "enabled", new = true },
}

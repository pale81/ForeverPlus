-- Player notes: a note and a mark (enemy or friend) for other players, set from their right-click menu. The note
-- stands in their tooltip with the time they were last seen; marked enemies give a warning when they come close
-- (nameplate, target or mouseover), at most once every few minutes per player.
local _, ns = ...
local L = ns.L

local Notes = ns:NewModule("PlayerNotes", {
	title = L.NOTES_TITLE,
	order = 11.9,
	defaults = { enabled = true, tooltip = true, enemyWarn = true, enemySound = true },
})

local WARN_PAUSE = 300 -- seconds between two warnings about the same player
local MENUS = { "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "CHAT_ROSTER", "TARGET", "FOCUS",
	"COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER", "GUILD" }
local COLORS = { enemy = { 1, 0.35, 0.3 }, friend = { 0.4, 0.9, 0.4 } }
local warned = {}

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- "name-realm" in lower case; an empty realm is the player's own.
function Notes.Key(name, realm, ownRealm)
	if type(name) ~= "string" or name == "" then return end
	local base, inName = name:match("^([^%-]+)%-(.+)$")
	if base then name, realm = base, inName end
	realm = type(realm) == "string" and realm ~= "" and realm or ownRealm or ""
	realm = realm:gsub("[%s'%-]", "")
	local key = name .. "-" .. realm
	return C_Intl and type(C_Intl.FoldCase) == "function" and C_Intl.FoldCase(key) or key:lower()
end

-- Whether a marked enemy is worth a warning now (and the next allowed time is remembered).
function Notes.ShouldWarn(entry, key, now, last)
	if type(entry) ~= "table" or entry.tag ~= "enemy" then return false end
	if last[key] and now - last[key] < WARN_PAUSE then return false end
	last[key] = now
	return true
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function Store()
	if type(ns.db.playerNotes) ~= "table" then ns.db.playerNotes = {} end
	return ns.db.playerNotes
end

local function OwnRealm()
	local realm = GetRealmName()
	return type(realm) == "string" and not ns.Secret(realm) and realm or ""
end

function Notes.Get(key)
	local entry = key and Store()[key]
	return type(entry) == "table" and entry or nil
end

-- Sets the note and/or the mark; an entry without both is removed.
function Notes.Set(key, display, note, tag)
	if not key then return end
	local store = Store()
	local entry = Notes.Get(key) or { name = display }
	if note ~= nil then entry.note = note ~= "" and note or nil end
	if tag ~= nil then entry.tag = tag ~= false and tag or nil end
	entry.name = display or entry.name
	store[key] = (entry.note or entry.tag) and entry or nil
end

-- The key and display name of a player unit, nil for anything else or while the game keeps it secret.
local function UnitKey(unit)
	if type(unit) ~= "string" or ns.Secret(unit) then return end
	local player, own = UnitIsPlayer(unit), UnitIsUnit(unit, "player")
	if ns.Secret(player) or ns.Secret(own) or player ~= true or own == true then return end
	local name, realm = UnitFullName(unit)
	if ns.Secret(name) or ns.Secret(realm) or type(name) ~= "string" then return end
	return Notes.Key(name, realm, OwnRealm()), name
end

---------------------------------------------------------------------------
-- Right-click menu, note window
---------------------------------------------------------------------------
local function EditNote(key, display)
	local entry = Notes.Get(key)
	ns.ShowEditWindow("PlayerNote", L.NOTES_EDIT_TITLE:format(display), entry and entry.note or "", SAVE, function(text)
		Notes.Set(key, display, text)
	end, L.NOTES_EDIT_HINT)
end

local function AddMenuEntries(_, root, context)
	if not (Notes.db.enabled and context) then return end
	local key, display
	if context.unit then
		key, display = UnitKey(context.unit)
	elseif type(context.name) == "string" and not ns.Secret(context.name) then
		key, display = Notes.Key(context.name, context.server, OwnRealm()), context.name
	end
	if not key then return end
	root:CreateDivider()
	root:CreateTitle(L.NOTES_TITLE)
	root:CreateButton(L.NOTES_EDIT, function() EditNote(key, display) end)
	for _, tag in ipairs({ "enemy", "friend" }) do
		root:CreateCheckbox(tag == "enemy" and L.NOTES_ENEMY or L.NOTES_FRIEND, function()
			local entry = Notes.Get(key)
			return entry ~= nil and entry.tag == tag
		end, function()
			local entry = Notes.Get(key)
			Notes.Set(key, display, nil, not (entry and entry.tag == tag) and tag or false)
		end)
	end
end

---------------------------------------------------------------------------
-- Tooltip and warnings
---------------------------------------------------------------------------
local function OnUnitTooltip(tooltip)
	if tooltip ~= GameTooltip or tooltip:IsForbidden() or not (Notes.db.enabled and Notes.db.tooltip) then return end
	local _, unit = tooltip:GetUnit()
	local key = UnitKey(unit)
	local entry = Notes.Get(key)
	if not entry then return end
	local color = COLORS[entry.tag] or { 1, 0.82, 0 }
	local label = entry.tag == "enemy" and L.NOTES_ENEMY or entry.tag == "friend" and L.NOTES_FRIEND or L.NOTES_TITLE
	tooltip:AddLine(entry.note and (label .. ": " .. entry.note) or label, color[1], color[2], color[3], true)
	if entry.seen then
		tooltip:AddLine(L.NOTES_SEEN:format(date(L.NOTES_DATE, entry.seen)), 0.7, 0.7, 0.7)
	end
	entry.seen = time()
end

local function Sighted(unit)
	local key, display = UnitKey(unit)
	local entry = Notes.Get(key)
	if not entry then return end
	entry.seen = time()
	if Notes.db.enemyWarn and Notes.ShouldWarn(entry, key, GetTime(), warned) then
		ns.PrintAlways(entry.note and L.NOTES_ENEMY_NEAR_NOTE or L.NOTES_ENEMY_NEAR, display, entry.note)
		if Notes.db.enemySound then PlaySound(SOUNDKIT.RAID_WARNING) end
	end
end

function Notes:Apply()
	local on = self.db.enabled
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", on, function(_, _, unit) Sighted(unit) end)
	self:ToggleEvent("PLAYER_TARGET_CHANGED", on, function() Sighted("target") end)
	self:ToggleEvent("UPDATE_MOUSEOVER_UNIT", on, function() Sighted("mouseover") end)
end

function Notes:OnLogin()
	if Menu and Menu.ModifyMenu then
		for _, which in ipairs(MENUS) do
			Menu.ModifyMenu("MENU_UNIT_" .. which, ns.Measured("PlayerNotes: menu", AddMenuEntries))
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Measured("PlayerNotes: tooltip", OnUnitTooltip))
	self:Apply()
end

function Notes:OnOptionChanged()
	self:Apply()
end

Notes.options = {
	{ key = "enabled", type = "toggle", name = L.NOTES_ENABLE, desc = L.NOTES_ENABLE_DESC },
	{ key = "tooltip", type = "toggle", name = L.NOTES_TOOLTIP, desc = L.NOTES_TOOLTIP_DESC, parent = "enabled" },
	{ key = "enemyWarn", type = "toggle", name = L.NOTES_WARN, desc = L.NOTES_WARN_DESC, parent = "enabled" },
	{ key = "enemySound", type = "toggle", name = L.NOTES_WARN_SOUND, parent = "enemyWarn" },
}

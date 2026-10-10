-- Innkeepers: the client has no list of who can set the hearthstone. When the
-- player binds at an innkeeper (CONFIRM_BINDER, the innkeeper is the unit
-- "npc") the NPC and the player's position are remembered; the world map shows
-- them with the inns. /fp gasthäuser export shows the list as text to pass on
-- so it can ship with a later update (Data/Inns.lua).
local _, ns = ...
local L = ns.L

local Innkeepers = ns:NewModule("Innkeepers", {
	title = L.INNS_TITLE,
	order = 11.7,
	defaults = {
		record = true,
	},
})

-- NPC ID of a creature GUID ("Creature-0-realm-instance-zone-npcID-spawn").
function Innkeepers.NpcID(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
		return
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind == "Creature" and tonumber(id) or nil
end

local function PlayerPosition()
	local mapID = ns.Number(C_Map.GetBestMapForUnit("player"))
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return
	end
	local x, y = position:GetXY()
	x, y = ns.Number(x), ns.Number(y)
	if x and y and (x ~= 0 or y ~= 0) then
		return mapID, x * 100, y * 100
	end
end

local function OnConfirmBinder()
	local id = Innkeepers.NpcID(UnitGUID("npc"))
	local mapID, x, y = PlayerPosition()
	if not (id and mapID) then
		return
	end
	local name = UnitName("npc")
	local faction = UnitFactionGroup("player")
	local team = faction == "Alliance" and "A" or faction == "Horde" and "H" or "N"
	local known = ns.db.innkeepers[id]
	-- Another faction binding at the same NPC makes it neutral.
	if known and known[5] ~= team then
		team = "N"
	end
	ns.db.innkeepers[id] = { type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name or "?",
		mapID, tonumber(("%.1f"):format(x)), tonumber(("%.1f"):format(y)), team }
	ns.MapSymbols.Refresh()
end

Innkeepers.Record = OnConfirmBinder

function Innkeepers.ExportText(list)
	local lines = { L.INNS_EXPORT_HEADER }
	local ids = {}
	for id in pairs(list) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local inn = list[id]
		lines[#lines + 1] = ("{ %d, %d, %.1f, %.1f, %q, %q },"):format(id, inn[2], inn[3], inn[4], inn[5], inn[1])
	end
	return table.concat(lines, "\n")
end

function Innkeepers.Export()
	if next(ns.db.innkeepers) == nil then
		ns.PrintAlways(L.INNS_EXPORT_NONE)
		return
	end
	ns.ShowEditWindow("InnkeeperExport", L.INNS_TITLE, Innkeepers.ExportText(ns.db.innkeepers), CLOSE, function() end,
		L.INNS_EXPORT_HINT)
end

-- /fp gasthäuser [export|löschen]
function Innkeepers.Command(msg)
	if msg:find("export", 1, true) then
		Innkeepers.Export()
	elseif msg:find("l\195\182sch", 1, true) or msg:find("clear", 1, true) then
		ns.db.innkeepers = {}
		ns.PrintAlways(L.INNS_CLEARED)
		ns.MapSymbols.Refresh()
	else
		local count = 0
		for _ in pairs(ns.db.innkeepers) do
			count = count + 1
		end
		ns.PrintAlways(L.INNS_STATUS, count)
	end
end

function Innkeepers:Apply()
	self:ToggleEvent("CONFIRM_BINDER", self.db.record, OnConfirmBinder)
end

function Innkeepers:OnInitialize()
	ns.db.innkeepers = ns.db.innkeepers or {}
end

function Innkeepers:OnLogin()
	self:Apply()
end

function Innkeepers:OnOptionChanged()
	self:Apply()
end

Innkeepers.options = {
	{ key = "record", type = "toggle", name = L.INNS_RECORD, desc = L.INNS_RECORD_DESC },
}

-- How often you went through a dungeon or raid and how often you died in it, counted per character and shown in the
-- tooltip of the entrance symbol on the world map. The game keeps no such count (it only knows the lockouts), so
-- ForeverPlus counts itself: a run is one entry into the instance from outside (a reload or a login inside does not
-- count), a death is the player's death while inside.
local _, ns = ...
local L = ns.L

local Stats = ns:NewModule("InstanceStats", {
	title = L.INSTSTATS_TITLE,
	order = 3.6,
	defaults = {
		enabled = true,
	},
	charDefaults = {
		runs = {}, -- instance map ID -> { n = runs, deaths = deaths }
	},
})

local inside -- instance map ID of the instance the player is in, nil outside

local function Entry(instanceID)
	local runs = Stats.cdb.runs
	runs[instanceID] = runs[instanceID] or { n = 0, deaths = 0 }
	return runs[instanceID]
end

local function OnEnteringWorld(_, _, isInitialLogin, isReloadingUi)
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	instanceID = ns.Number(instanceID)
	if (instanceType == "party" or instanceType == "raid") and instanceID then
		if inside ~= instanceID and not isInitialLogin and not isReloadingUi then
			Entry(instanceID).n = Entry(instanceID).n + 1
		end
		inside = instanceID
	else
		inside = nil
	end
end

local function OnDead()
	if inside then
		Entry(inside).deaths = Entry(inside).deaths + 1
	end
end

-- Runs and deaths of an instance (nil when none was counted or the function is off).
function Stats.Get(instanceID)
	if not Stats.db or not Stats.db.enabled or not Stats.cdb then
		return nil
	end
	local entry = instanceID and Stats.cdb.runs[instanceID]
	if entry and (entry.n > 0 or entry.deaths > 0) then
		return entry.n, entry.deaths
	end
end

function Stats:Apply()
	self:ToggleEvent("PLAYER_ENTERING_WORLD", self.db.enabled, OnEnteringWorld)
	self:ToggleEvent("PLAYER_DEAD", self.db.enabled, OnDead)
end

function Stats:OnLogin()
	self:Apply()
end

function Stats:OnOptionChanged()
	self:Apply()
end

Stats.options = {
	{ key = "enabled", type = "toggle", name = L.INSTSTATS_ENABLE, desc = L.INSTSTATS_DESC, new = true },
}

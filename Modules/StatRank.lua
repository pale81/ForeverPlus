-- Attributes by importance: the rows of the character window show which values matter for the talent tree in
-- use: a number before the name (its place within its group), the most important ones bright, the useless grey. The weights and the
-- tree are those of the item rating (option "rating by talent tree"), so a tree chosen there counts here too.
local _, ns = ...
local L = ns.L

local StatRank = ns:NewModule("StatRank", {
	title = L.STATRANK_TITLE,
	order = 5.37,
	defaults = {
		enabled = true,
	},
})

-- Row of the character window (PAPERDOLL_STATINFO) -> the weights it stands for (the largest counts).
local ROW_KEYS = {
	STRENGTH = { "STR" }, AGILITY = { "AGI" }, STAMINA = { "STA" }, INTELLECT = { "INT" }, SPIRIT = { "SPI" },
	ATTACK_AP = { "AP" }, RANGED_ATTACK_AP = { "RAP" }, SPELLPOWER = { "SP" }, SPELLHEALING = { "HEAL" },
	CRITCHANCE = { "CRIT", "SCRIT" }, HITCHANCE = { "HIT", "SHIT" }, HITCHANCE_MELEE = { "HIT" },
	HITCHANCE_RANGED = { "HIT" }, HITCHANCE_SPELL = { "SHIT" }, DODGE = { "DODGE" }, PARRY = { "PARRY" }, BLOCK = { "BLOCK" },
	MANAREGEN = { "MP5" }, DEFENSE = { "DEF" }, ARMOR = { "ARMOR" },
}
-- The weights count per point of very different things (one point of strength, one percent to hit): rows are
-- only compared within a group, against the largest weight of the group.
local GROUPS = {
	{ "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" },
	{ "ATTACK_AP", "RANGED_ATTACK_AP", "SPELLPOWER", "SPELLHEALING" },
	{ "CRITCHANCE", "HITCHANCE", "HITCHANCE_MELEE", "HITCHANCE_RANGED", "HITCHANCE_SPELL", "DODGE", "PARRY", "BLOCK" },
}
-- Rows that stand alone: the weight from which they are important (3) or of some use (2); below that minor.
local ALONE = { MANAREGEN = { 1.5, 1 }, DEFENSE = { 1, 0.5 }, ARMOR = { 0.05, 0.02 } }
local TOP_SHARE, MID_SHARE = 0.8, 0.4

local function RowWeight(weights, row)
	local best = 0
	for _, key in ipairs(ROW_KEYS[row]) do
		best = math.max(best, weights[key] or 0)
	end
	return best
end

-- Importance per row for a set of weights: 3 most important, 2 useful, 1 minor, 0 useless.
function StatRank.Tiers(weights)
	local tiers = {}
	for _, group in ipairs(GROUPS) do
		local top = 0
		for _, row in ipairs(group) do
			top = math.max(top, RowWeight(weights, row))
		end
		for _, row in ipairs(group) do
			local weight = RowWeight(weights, row)
			tiers[row] = (weight <= 0 or top <= 0) and 0 or (weight >= top * TOP_SHARE and 3) or (weight >= top * MID_SHARE and 2) or 1
		end
	end
	for row, limits in pairs(ALONE) do
		local weight = RowWeight(weights, row)
		tiers[row] = weight <= 0 and 0 or (weight >= limits[1] and 3) or (weight >= limits[2] and 2) or 1
	end
	return tiers
end

-- Place per row within its group (1 = the largest weight; equal weights share a place); rows without weight and
-- the rows that stand alone get none.
function StatRank.Places(weights)
	local places = {}
	for _, group in ipairs(GROUPS) do
		local rows = {}
		for _, row in ipairs(group) do
			if RowWeight(weights, row) > 0 then
				rows[#rows + 1] = row
			end
		end
		table.sort(rows, function(a, b)
			local wa, wb = RowWeight(weights, a), RowWeight(weights, b)
			if wa ~= wb then
				return wa > wb
			end
			return a < b
		end)
		local place, last = 0, nil
		for index, row in ipairs(rows) do
			local weight = RowWeight(weights, row)
			if weight ~= last then
				place, last = index, weight
			end
			places[row] = place
		end
	end
	return places
end

local BRIGHT, GREY = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }

local tiersFor, tiers, places -- the weights the tiers were worked out for

local function CurrentTiers()
	local weights = ns.StatWeights and ns.StatWeights()
	if not weights then
		return nil
	end
	if weights ~= tiersFor then
		tiersFor, tiers, places = weights, StatRank.Tiers(weights), StatRank.Places(weights)
	end
	return tiers, places
end

-- One row of the list: Blizzard's frames are reused for other rows, so a row that is not ranked gets its look back.
local function OnRow(_, frame, data)
	local label = frame and frame.Label
	if not label or type(data) ~= "table" then
		return
	end
	local current, place
	if StatRank.db.enabled and not data.isHeader and data.unit == "player" then
		current, place = CurrentTiers()
	end
	local tier = current and current[data.name]
	place = place and place[data.name]
	if frame.fpPlace then
		frame.fpPlace:SetShown(place ~= nil)
	end
	if not tier then
		if frame.fpRanked then
			frame.fpRanked = nil
			label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
		end
		return
	end
	frame.fpRanked = true
	if place then
		if not frame.fpPlace then
			frame.fpPlace = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			frame.fpPlace:SetPoint("RIGHT", label, "LEFT", -2, 0)
		end
		frame.fpPlace:SetFormattedText("%d.", place)
		frame.fpPlace:Show()
	end
	if tier == 3 then
		label:SetTextColor(unpack(BRIGHT))
	elseif tier == 0 then
		label:SetTextColor(unpack(GREY))
	else
		label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	end
end
StatRank.OnRow = OnRow

local hooked = false

function StatRank.Refresh()
	local pane = CharacterStatsPaneScrollBox
	local box = pane and pane.ScrollBox
	if not box or not box.ForEachFrame then
		return
	end
	if not hooked then
		hooked = true
		ScrollUtil.AddAcquiredFrameCallback(box, ns.Measured("StatRank: row", OnRow), StatRank)
	end
	box:ForEachFrame(function(frame, data)
		OnRow(nil, frame, data)
	end)
end

function StatRank:OnLogin()
	if CharacterFrame then
		CharacterFrame:HookScript("OnShow", ns.Measured("StatRank: window", StatRank.Refresh))
	end
	-- Another tree (talents spent, or chosen for the rating): the open window follows.
	for _, event in ipairs({ "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP" }) do
		self:RegisterEvent(event, function()
			ns.After("StatRank: refresh", 0.2, StatRank.Refresh)
		end)
	end
end

function StatRank:OnOptionChanged()
	StatRank.Refresh()
end

StatRank.options = {
	{ key = "enabled", type = "toggle", name = L.STATRANK_ENABLE, desc = L.STATRANK_ENABLE_DESC, new = true },
}

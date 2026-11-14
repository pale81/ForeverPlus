-- Rank the visible character stats using the same talent-tree weights as item scoring.
local _, ns = ...
local L = ns.L

local StatRank = ns:NewModule("StatRank", {
	title = L.STATRANK_TITLE,
	order = 5.37,
	defaults = {
		enabled = true,
	},
})

-- Character-window row -> the item weights it represents (the largest counts for combined rows).
local ROW_KEYS = {
	STRENGTH = { "STR" }, AGILITY = { "AGI" }, STAMINA = { "STA" }, INTELLECT = { "INT" }, SPIRIT = { "SPI" },
	MAINHAND_DAMAGE = { "DPS" }, OFFHAND_DAMAGE = { "DPS" }, RANGED_DAMAGE = { "RDPS" },
	ATTACK_AP = { "AP" }, RANGED_ATTACK_AP = { "RAP" }, SPELLPOWER = { "SP" }, SPELLHEALING = { "HEAL" },
	CRITCHANCE = { "CRIT", "SCRIT" }, HITCHANCE = { "HIT", "SHIT" }, HITCHANCE_MELEE = { "HIT" },
	HITCHANCE_RANGED = { "HIT" }, HITCHANCE_SPELL = { "SHIT" }, DODGE = { "DODGE" }, PARRY = { "PARRY" }, BLOCK = { "BLOCK" },
	HASTE = { "HASTE", "SHASTE" }, EXPERTISE = { "EXPERTISE" }, ARMORPEN = { "ARP" },
	MANAREGEN = { "MP5" }, DEFENSE = { "DEF" }, ARMOR = { "ARMOR" },
}

-- Compare like units within each Blizzard section. Weapon damage uses the weight for weapon DPS.
local GROUPS = {
	{ "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" },
	{ "MAINHAND_DAMAGE", "OFFHAND_DAMAGE", "RANGED_DAMAGE" },
	{ "ATTACK_AP", "RANGED_ATTACK_AP" },
	{ "SPELLPOWER", "SPELLHEALING" },
	{ "CRITCHANCE", "HITCHANCE", "HITCHANCE_MELEE", "HITCHANCE_RANGED", "HITCHANCE_SPELL", "HASTE", "EXPERTISE" },
	{ "DODGE", "PARRY", "BLOCK" },
}
local ROW_GROUP = {}
for group, rows in ipairs(GROUPS) do
	for _, name in ipairs(rows) do
		ROW_GROUP[name] = group
	end
end

local TOP_SHARE, MID_SHARE = 0.8, 0.4
local COLORS = {
	[0] = { 0.58, 0.58, 0.58 },
	{ 0.76, 0.68, 0.52 },
	{ 1, 0.82, 0.28 },
	{ 0.35, 0.9, 1 },
}

local function RowWeight(weights, keys)
	local best = 0
	for _, key in ipairs(keys) do
		best = math.max(best, weights[key] or 0)
	end
	return best
end

local function Tier(weight, high, medium)
	return weight <= 0 and 0 or (weight >= high and 3) or (weight >= medium and 2) or 1
end

local function RankGroup(rows, order, styles, group)
	local slots = {}
	for index, entry in ipairs(group) do
		slots[index] = entry.index
	end
	table.sort(group, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.index < b.index
	end)
	local top, last, place = group[1].weight
	for index, entry in ipairs(group) do
		if entry.weight ~= last then
			last, place = entry.weight, index
		end
		local data, slot = rows[entry.index], slots[index]
		order[data] = slot
		styles[data] = {
			tier = Tier(entry.weight, top * TOP_SHARE, top * MID_SHARE),
			place = entry.weight > 0 and place or nil,
			statIndex = rows[slot].statIndex,
		}
	end
end

local function Presentation(rows, weights)
	local order, styles = {}, {}
	local groups, section = {}, {}
	for index, data in ipairs(rows) do
		order[data] = index
		if data.isHeader then
			section = {}
		elseif weights and data.unit == "player" and ROW_KEYS[data.name] then
			local weight = RowWeight(weights, ROW_KEYS[data.name])
			local groupID = ROW_GROUP[data.name]
			if groupID then
				if not section[groupID] then
					section[groupID] = {}
					groups[#groups + 1] = section[groupID]
				end
				local group = section[groupID]
				group[#group + 1] = { index = index, weight = weight }
			else
				-- Keep standalone rows aligned with ranked rows and reserve priority colors for ranks.
				styles[data] = { tier = weight == 0 and 0 or nil }
			end
		end
	end
	for _, group in ipairs(groups) do
		RankGroup(rows, order, styles, group)
	end
	return order, styles
end

local styles = {}
local RANK_LABEL_INSET = 8

-- Blizzard reuses the row frames. Restore the label and stripe when ranking no longer applies.
local function OnRow(_, frame, data)
	local label = frame.Label
	if not label or type(data) ~= "table" or data.isHeader then
		return
	end
	local style = styles[data]
	local place = style and style.place
	if place and not frame.fpPlace then
		frame.fpPlace = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		frame.fpPlace:SetPoint("RIGHT", label, "LEFT", -2, 0)
	end
	if frame.fpPlace then
		frame.fpPlace:SetShown(place ~= nil)
	end
	if style then
		if not frame.fpRankColor then
			frame.fpRankColor = { label:GetTextColor() }
			local point, relative, relativePoint, x, y = label:GetPoint(1)
			if point then
				frame.fpRankLabelPoint = { point, relative, relativePoint, x, y }
				label:SetPoint(point, relative, relativePoint, x + RANK_LABEL_INSET, y)
			end
		end
		local color = COLORS[style.tier]
		label:SetTextColor(unpack(color or frame.fpRankColor))
		if place then
			frame.fpPlace:SetFormattedText("%d.", place)
			frame.fpPlace:SetTextColor(unpack(color))
		end
	elseif frame.fpRankColor then
		label:SetTextColor(unpack(frame.fpRankColor))
		frame.fpRankColor = nil
		if frame.fpRankLabelPoint then
			label:SetPoint(unpack(frame.fpRankLabelPoint, 1, 5))
			frame.fpRankLabelPoint = nil
		end
	end
	local rankedIndex = style and style.statIndex
	if frame.Background and (rankedIndex or frame.fpRankStripe) then
		local statIndex = rankedIndex or data.statIndex
		frame.Background:SetShown(statIndex % 2 == 1)
		frame.fpRankStripe = rankedIndex ~= nil
	end
end

local rankedProvider, rankedWeights

function StatRank.Refresh()
	local pane = CharacterStatsPaneScrollBox
	local box = pane and pane.ScrollBox
	if not box or not box.GetDataProvider then
		return
	end
	local provider = box:GetDataProvider()
	if not provider then
		return
	end
	local collection = provider:GetCollection()
	if #collection == 0 then
		return
	end
	local weights = StatRank.db.enabled and ns.StatWeights() or nil
	if provider == rankedProvider and weights == rankedWeights then
		return
	end

	-- Blizzard keeps the original section order in elementData and gives the provider its own collection.
	local order
	order, styles = Presentation(pane.elementData, weights)
	rankedProvider, rankedWeights = provider, weights
	for index, data in ipairs(collection) do
		if order[data] ~= index then
			provider:Sort(function(a, b)
				return order[a] < order[b]
			end)
			break
		end
	end
	box:ForEachFrame(function(frame, data)
		OnRow(nil, frame, data)
	end)
end

function StatRank:OnLogin()
	ns.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
		local pane = CharacterStatsPaneScrollBox
		local box = pane and pane.ScrollBox
		if not box or not box.GetDataProvider then
			return
		end
		hooksecurefunc(box, "SetDataProvider", ns.Measured("StatRank: list", StatRank.Refresh))
		ScrollUtil.AddInitializedFrameCallback(box, ns.Measured("StatRank: row", OnRow), StatRank)
		StatRank.Refresh()
	end)
end

function StatRank:OnOptionChanged()
	StatRank.Refresh()
end

StatRank.options = {
	{ key = "enabled", type = "toggle", name = L.STATRANK_ENABLE, desc = L.STATRANK_ENABLE_DESC, new = true },
}

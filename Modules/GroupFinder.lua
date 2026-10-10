-- Group finder: dungeon groups for 5 and 10 players show the classes already
-- in the group and the roles still missing in the browse list.
local _, ns = ...
local L = ns.L

local GroupFinder = ns:NewModule("GroupFinder", {
	title = L.GROUPFINDER_TITLE,
	order = 5.25,
	defaults = {
		composition = true,
		tank5 = 1, healer5 = 1, dps5 = 3,
		tank10 = 2, healer10 = 2, dps10 = 6,
	},
})

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLAS = {
	TANK = "groupfinder-icon-role-micro-tank",
	HEALER = "groupfinder-icon-role-micro-heal",
	DAMAGER = "groupfinder-icon-role-micro-dps",
}
local ROLE_SORT = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local ICON_SIZE = 16
local displays = {} -- search entry -> our display

local function GroupSize(activityIDs)
	local size = 0
	for _, activityID in ipairs(activityIDs or {}) do
		local info = C_LFGList.GetActivityInfoTable(activityID)
		if info and info.maxNumPlayers and info.maxNumPlayers > size then
			size = info.maxNumPlayers
		end
	end
	return size
end

local function Expected(size)
	local db = GroupFinder.db
	if size == 5 then
		return { TANK = db.tank5, HEALER = db.healer5, DAMAGER = db.dps5 }
	elseif size == 10 then
		return { TANK = db.tank10, HEALER = db.healer10, DAMAGER = db.dps10 }
	end
end

local function GetDisplay(entry)
	local display = displays[entry]
	if not display then
		display = CreateFrame("Frame", nil, entry)
		display:SetSize(200, 34)
		display:SetPoint("RIGHT", entry, "RIGHT", -8, -1)
		display.Classes = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		display.Classes:SetPoint("TOPRIGHT")
		display.Classes:SetJustifyH("RIGHT")
		display.Missing = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		display.Missing:SetPoint("BOTTOMRIGHT")
		display.Missing:SetJustifyH("RIGHT")
		displays[entry] = display
	end
	return display
end

local function Hide(entry)
	if displays[entry] then
		displays[entry]:Hide()
	end
	if entry.DataDisplay then
		entry.DataDisplay:SetAlpha(1)
	end
end

local function SortMembers(a, b)
	if a.sort ~= b.sort then
		return a.sort < b.sort
	end
	return a.class < b.class
end

local seen = setmetatable({}, { __mode = "k" }) -- every list entry that was built, also with the option off

local function UpdateEntry(entry)
	seen[entry] = true
	local info = GroupFinder.db.composition and entry.resultID and C_LFGList.GetSearchResultInfo(entry.resultID)
	-- Results can be protected while chat messaging is locked down.
	if info and (issecretvalue(info.numMembers) or issecretvalue(info.hasSelf)) then
		info = nil
	end
	local expected = info and not info.hasSelf and info.numMembers > 1 and Expected(GroupSize(info.activityIDs))
	if not expected then
		Hide(entry)
		return
	end

	local members, counts = {}, { TANK = 0, HEALER = 0, DAMAGER = 0 }
	for i = 1, info.numMembers do
		local member = C_LFGList.GetSearchResultPlayerInfo(entry.resultID, i)
		if member and member.classFilename and not issecretvalue(member.classFilename)
			and not issecretvalue(member.assignedRole) then
			local role = member.assignedRole
			if counts[role] then
				counts[role] = counts[role] + 1
			end
			members[#members + 1] = { class = member.classFilename, sort = ROLE_SORT[role] or 4 }
		end
	end
	table.sort(members, SortMembers)

	local icons = {}
	for _, member in ipairs(members) do
		icons[#icons + 1] = CreateAtlasMarkup("groupfinder-icon-class-" .. member.class:lower(), ICON_SIZE, ICON_SIZE)
	end

	local missing = {}
	for _, role in ipairs(ROLES) do
		local count = expected[role] - counts[role]
		if count > 0 then
			missing[#missing + 1] = CreateAtlasMarkup(ROLE_ATLAS[role], ICON_SIZE, ICON_SIZE) .. count
		end
	end
	local unassigned = #members - counts.TANK - counts.HEALER - counts.DAMAGER

	local display = GetDisplay(entry)
	display.Classes:SetText(table.concat(icons, ""))
	local text
	if #missing > 0 then
		text = L.GROUPFINDER_MISSING .. " " .. table.concat(missing, " ")
	else
		text = GREEN_FONT_COLOR:WrapTextInColorCode(L.GROUPFINDER_COMPLETE)
	end
	if unassigned > 0 then
		text = text .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode(L.GROUPFINDER_NO_ROLE:format(unassigned))
	end
	display.Missing:SetText(text)
	local alpha = info.isDelisted and 0.4 or 1
	display:SetAlpha(alpha)
	display:Show()
	if entry.DataDisplay then
		entry.DataDisplay:SetAlpha(0)
	end
end

local function RefreshAll()
	for entry in pairs(seen) do
		if entry:IsShown() then
			UpdateEntry(entry)
		end
	end
end

function GroupFinder:OnLogin()
	ns.OnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function()
		if LFGBrowseSearchEntry_Update then
			hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateEntry)
		end
	end)
end

function GroupFinder:OnOptionChanged()
	RefreshAll()
end

local function Count(key, name, max)
	return { key = key, type = "slider", name = name, parent = "composition", min = 0, max = max, step = 1 }
end

GroupFinder.options = {
	{ key = "composition", type = "toggle", name = L.GROUPFINDER_COMPOSITION, desc = L.GROUPFINDER_COMPOSITION_DESC },
	{ type = "header", name = L.GROUPFINDER_FIVE },
	Count("tank5", TANK, 5), Count("healer5", HEALER, 5), Count("dps5", DAMAGER, 5),
	{ type = "header", name = L.GROUPFINDER_TEN },
	Count("tank10", TANK, 10), Count("healer10", HEALER, 10), Count("dps10", DAMAGER, 10),
}

-- Group finder: dungeon groups for 5 and 10 players show the classes already
-- in the group and the roles still missing in the browse list.
local _, ns = ...
local L = ns.L

local GroupFinder = ns:NewModule("GroupFinder", {
	title = L.GROUPFINDER_TITLE,
	order = 5.25,
	defaults = {
		composition = true,
		questButton = true, -- a small button at group, elite and dungeon quests: lists the player for it
		tank5 = 1, healer5 = 1, dps5 = 3,
		tank10 = 2, healer10 = 2, dps10 = 6,
		presetRoles = false, -- the own roles are chosen in the group finder from the start
		roleTank = false, roleHealer = false, roleDps = true,
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
	if info and (ns.Secret(info.numMembers) or ns.Secret(info.hasSelf)) then
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
		if member and member.classFilename and not ns.Secret(member.classFilename)
			and not ns.Secret(member.assignedRole) then
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

---------------------------------------------------------------------------
-- Group quests: a small button at elite, group and dungeon quests (tracker and quest log) lists the player
-- in the group finder for the place of the quest, with the roles chosen there last. The place is found by
-- name: the dungeon (all its wings: "Scarlet Monastery" lists Graveyard, Library, Armory and Cathedral) or,
-- for an elite quest outside, its zone under "Quests & Zones".
---------------------------------------------------------------------------
local DUNGEON_CATEGORY, RAID_CATEGORY, QUEST_CATEGORY = 2, 114, 116
local CATEGORIES = { dungeon = { DUNGEON_CATEGORY, RAID_CATEGORY }, raid = { RAID_CATEGORY, DUNGEON_CATEGORY },
	elite = { QUEST_CATEGORY, DUNGEON_CATEGORY } }
local DUNGEON_TAGS = { [81] = true, [85] = true }
local RAID_TAGS = { [62] = true, [88] = true, [89] = true }
local GROUP_TAG = 1

-- What kind of group a quest wants (nil: none). tag: C_QuestLog.GetQuestTagInfo; isDungeon: from the quest data.
function GroupFinder.QuestKind(tag, suggestedGroup, isDungeon)
	local tagID = tag and tag.tagID
	if RAID_TAGS[tagID] then
		return "raid"
	elseif isDungeon or DUNGEON_TAGS[tagID] then
		return "dungeon"
	elseif tagID == GROUP_TAG or (tag and tag.isElite) or (suggestedGroup or 0) > 1 then
		return "elite"
	end
end

local function Contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local function Normal(text)
	return type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
end

-- The activities for a quest: names are the places it may belong to (quest log header, area of the quest),
-- activities { id, fullName, shortName, categoryID }. An exact name first; else every activity whose name begins
-- with the place and goes on with a dash, bracket or colon (the wings of one dungeon).
function GroupFinder.MatchActivities(names, activities, kind)
	for _, categoryID in ipairs(CATEGORIES[kind] or {}) do
		for _, exact in ipairs({ true, false }) do
			local found = {}
			for _, name in ipairs(names) do
				local place = Normal(name)
				if place and place ~= "" then
					for _, activity in ipairs(activities) do
						if activity.categoryID == categoryID then
							local full, short = Normal(activity.fullName), Normal(activity.shortName)
							local hit
							if exact then
								hit = full == place or short == place
							else
								local rest = full and full:sub(1, #place) == place and full:sub(#place + 1) or nil
								hit = rest and rest:find("^%s*[%-%(:]") ~= nil
							end
							if hit and not Contains(found, activity.id) then
								found[#found + 1] = activity.id
							end
						end
					end
				end
			end
			if #found > 0 then
				return found
			end
		end
	end
	return {}
end

-- A listing that runs already keeps its activities; the new ones are added.
function GroupFinder.MergeActivities(old, new)
	local merged = {}
	for _, list in ipairs({ old or {}, new }) do
		for _, id in ipairs(list) do
			if not Contains(merged, id) then
				merged[#merged + 1] = id
			end
		end
	end
	return merged
end

local activityList -- all activities of the client, read once

local function Activities()
	if activityList and #activityList > 0 then
		return activityList
	end
	activityList = {}
	if not (C_LFGList and C_LFGList.GetAvailableCategories) then
		return activityList
	end
	for _, categoryID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
		for _, id in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
			local info = C_LFGList.GetActivityInfoTable(id)
			if info then
				activityList[#activityList + 1] = { id = id, fullName = info.fullName, shortName = info.shortName,
					categoryID = info.categoryID or categoryID }
			end
		end
	end
	return activityList
end

-- The quest log header above each quest (the zone or dungeon it is sorted under) and its group size.
local function LogFacts()
	local facts, header = {}, nil
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and info.isHeader then
			header = info.title
		elseif info and info.questID then
			facts[info.questID] = { header = header, suggestedGroup = info.suggestedGroup }
		end
	end
	return facts
end

-- The activities for a quest and its kind (nil when it wants no group or no activity fits).
local function QuestActivities(questID, facts)
	local fact = facts[questID] or {}
	local qdb = ns.QuestieDB
	local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
	local kind = GroupFinder.QuestKind(tag, fact.suggestedGroup, qdb and qdb.IsDungeonQuest and qdb.IsDungeonQuest(questID))
	if not kind then
		return nil
	end
	local names = { fact.header }
	local lib = qdb and qdb.Get and qdb.Get()
	local area = lib and lib.Quest.Exists(questID) and lib.Quest.Get(questID, "zoneOrSort")
	if type(area) == "number" and area > 0 and C_Map.GetAreaInfo then
		names[#names + 1] = C_Map.GetAreaInfo(area)
	end
	local ids = GroupFinder.MatchActivities(names, Activities(), kind)
	return #ids > 0 and ids or nil, kind
end

local function ActivityNames(ids)
	local names = {}
	for _, id in ipairs(ids) do
		local info = C_LFGList.GetActivityInfoTable(id)
		names[#names + 1] = info and info.fullName or tostring(id)
	end
	return table.concat(names, ", ")
end

local function RoleText()
	local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
	local names = {}
	if roles and roles.tank then names[#names + 1] = TANK end
	if roles and roles.healer then names[#names + 1] = HEALER end
	if roles and roles.dps then names[#names + 1] = DAMAGER end
	return #names > 0 and table.concat(names, ", ") or nil
end

-- The click: lists the player (or the group they lead) for the quest's place.
function GroupFinder.SignUp(questID)
	local ids = QuestActivities(questID, LogFacts())
	local title = C_QuestLog.GetTitleForQuestID(questID) or tostring(questID)
	if not ids then
		ns.Print(L.GROUPQUEST_NONE:format(title))
		return
	end
	if IsInGroup() and not UnitIsGroupLeader("player") then
		ns.Print(L.GROUPQUEST_LEADER)
		return
	end
	local roles = RoleText()
	if not IsInGroup() and not roles then
		ns.Print(L.GROUPQUEST_NO_ROLE)
		return
	end
	local ok
	if C_LFGList.HasActiveEntryInfo() then
		local entry = C_LFGList.GetActiveEntryInfo() or {}
		ids = GroupFinder.MergeActivities(entry.activityIDs, ids)
		ok = C_LFGList.UpdateListing({ activityIDs = ids, newPlayerFriendly = entry.newPlayerFriendly or false,
			voiceMode = entry.voiceMode, generalPlaystyle = entry.generalPlaystyle })
	else
		ok = C_LFGList.CreateListing({ activityIDs = ids })
	end
	if ok then
		ns.Print(L.GROUPQUEST_LISTED:format(ActivityNames(ids), roles or GROUP))
	else
		ns.Print(L.GROUPQUEST_FAILED:format(ActivityNames(ids)))
	end
end

-- /fp gruppenquests: every group quest in the log with the activities found for it, and how many the client has.
function GroupFinder.PrintQuests()
	local facts, lines = LogFacts(), {}
	lines[#lines + 1] = L.GROUPQUEST_COUNT:format(#Activities(), RoleText() or NONE)
	for questID, fact in pairs(facts) do
		local ids, kind = QuestActivities(questID, facts)
		if kind then
			lines[#lines + 1] = ("%s [%d] %s, %s: %s"):format(C_QuestLog.GetTitleForQuestID(questID) or "?", questID, kind,
				tostring(fact.header), ids and ActivityNames(ids) or "-")
		end
	end
	ns.ShowTrace(L.GROUPQUEST_TITLE, lines)
end

local questButtons = {} -- parent frame (tracker block, quest log title) -> our button

local function QuestButton(parent)
	local button = questButtons[parent]
	if button then
		return button
	end
	button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	button:SetFrameLevel(parent:GetFrameLevel() + 5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if C_Texture.GetAtlasInfo("groupfinder-eye-single") then
		icon:SetAtlas("groupfinder-eye-single")
	else
		icon:SetTexture([[Interface\Icons\INV_Misc_GroupNeedMore]])
	end
	button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	button:SetScript("OnClick", function(self)
		GroupFinder.SignUp(self.questID)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.GROUPQUEST_TIP_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, ActivityNames(self.activities or {}))
		GameTooltip_AddHighlightLine(GameTooltip, L.GROUPQUEST_TIP_ROLES:format(RoleText() or NONE))
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	questButtons[parent] = button
	return button
end

-- Shows or hides the button on a parent for a quest; anchor: where it sits on the parent.
local function ShowQuestButton(parent, questID, facts, point, x, y)
	local ids = GroupFinder.db.questButton and questID and QuestActivities(questID, facts)
	local button = questButtons[parent]
	if not ids then
		if button then
			button:Hide()
		end
		return
	end
	button = QuestButton(parent)
	button.questID, button.activities = questID, ids
	button:ClearAllPoints()
	button:SetPoint(point, parent, point, x, y)
	button:Show()
end

local function UpdateTracker()
	if not (QuestObjectiveTracker and QuestObjectiveTracker.EnumerateActiveBlocks) then
		return
	end
	local facts = LogFacts()
	QuestObjectiveTracker:EnumerateActiveBlocks(function(block)
		ShowQuestButton(block, block.poiQuestID or block.id, facts, "TOPRIGHT", 0, 0)
	end)
end

local function UpdateLog()
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	local facts = LogFacts()
	for title in pool:EnumerateActive() do
		ShowQuestButton(title, title.questID, facts, "RIGHT", -22, 0)
	end
end

function GroupFinder:OnLogin()
	ns.OnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function()
		if LFGBrowseSearchEntry_Update then
			hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateEntry)
		end
		-- The window sets the roles saved by the game when it loads: ours after it.
		GroupFinder.ApplyRoles()
	end)
	GroupFinder.ApplyRoles()
	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", function()
		if QuestObjectiveTracker and QuestObjectiveTracker.Update then
			hooksecurefunc(QuestObjectiveTracker, "Update", ns.Measured("GroupFinder: quest buttons (tracker)", UpdateTracker))
		end
	end)
	if QuestLogQuests_Update then
		hooksecurefunc("QuestLogQuests_Update", ns.Measured("GroupFinder: quest buttons (log)", UpdateLog))
	end
end

-- The roles chosen in the options, as the group finder takes them; nil while the option is off or none is chosen.
function GroupFinder.PresetRoles(db)
	if not db.presetRoles or not (db.roleTank or db.roleHealer or db.roleDps) then
		return nil
	end
	return { tank = db.roleTank and true or false, healer = db.roleHealer and true or false, dps = db.roleDps and true or false }
end

-- Sets the own roles of the group finder (the ticks under "list yourself"); roles the class cannot fill are left
-- out by the game. The window reads them when it shows.
function GroupFinder.ApplyRoles()
	local roles = GroupFinder.PresetRoles(GroupFinder.db)
	if roles and C_LFGListRoles and C_LFGListRoles.SetRoles and not InCombatLockdown() then
		C_LFGListRoles.SetRoles(roles, true)
	end
end

function GroupFinder:OnOptionChanged(key)
	RefreshAll()
	GroupFinder.ApplyRoles()
	if key == "questButton" then
		UpdateTracker()
		UpdateLog()
	end
end

local function Count(key, name, max)
	return { key = key, type = "slider", name = name, parent = "composition", min = 0, max = max, step = 1 }
end

GroupFinder.options = {
	{ key = "composition", type = "toggle", name = L.GROUPFINDER_COMPOSITION, desc = L.GROUPFINDER_COMPOSITION_DESC },
	{ key = "questButton", type = "toggle", name = L.GROUPQUEST_OPTION, desc = L.GROUPQUEST_OPTION_DESC, new = true },
	{ key = "presetRoles", type = "toggle", name = L.GROUPFINDER_ROLES, desc = L.GROUPFINDER_ROLES_DESC, new = true },
	{ key = "roleTank", type = "toggle", name = TANK, parent = "presetRoles" },
	{ key = "roleHealer", type = "toggle", name = HEALER, parent = "presetRoles" },
	{ key = "roleDps", type = "toggle", name = DAMAGER, parent = "presetRoles" },
	{ type = "header", name = L.GROUPFINDER_FIVE },
	Count("tank5", TANK, 5), Count("healer5", HEALER, 5), Count("dps5", DAMAGER, 5),
	{ type = "header", name = L.GROUPFINDER_TEN },
	Count("tank10", TANK, 10), Count("healer10", HEALER, 10), Count("dps10", DAMAGER, 10),
}

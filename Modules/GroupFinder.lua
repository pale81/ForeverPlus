-- Group finder: dungeon groups for 5 and 10 players show the classes already
-- in the group and the roles still missing in the browse list.
local _, ns = ...
local L = ns.L

local GroupFinder = ns:NewModule("GroupFinder", {
	title = L.GROUPFINDER_TITLE,
	order = 5.25,
	defaults = {
		composition = true,
		dungeonLevels = true,
		journalButton = true,
		journalTab = true,
		questButton = true, -- a small button at group, elite and dungeon quests: lists the player for it
		tank5 = 1, healer5 = 1, dps5 = 3,
		tank10 = 2, healer10 = 2, dps10 = 6,
		presetRoles = false, -- the own roles are chosen in the group finder from the start
		roleTank = false, roleHealer = false, roleDps = true,
		roleLeader = false, -- the leader flag of the dungeon finder
	},
})

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLAS = {
	TANK = "groupfinder-icon-role-micro-tank",
	HEALER = "groupfinder-icon-role-micro-heal",
	DAMAGER = "groupfinder-icon-role-micro-dps",
}
local ROLE_SORT = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local DUNGEON_CATEGORY, RAID_CATEGORY, QUEST_CATEGORY = 2, 114, 116
local ICON_SIZE = 20
local MAX_CLASS_ICONS_WIDTH = 160
local displays = {} -- search entry -> our display
local levelLabels = setmetatable({}, { __mode = "k" })

local function DungeonLevels(activity)
	if not activity or activity.categoryID ~= DUNGEON_CATEGORY then
		return
	end
	local low, high = activity.minLevelSuggestion or 0, activity.maxLevelSuggestion or 0
	if low <= 0 then
		low = activity.minLevel or 0
	end
	if low <= 0 or high < low then
		return
	end
	return low == high and ("(%d)"):format(low) or ("(%d–%d)"):format(low, high)
end

local function SetLevelText(label, name, levels)
	label:SetFontObject(name:GetFontObject())
	label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	label:SetText(levels)
end

local function InitActivityLevel(button, description)
	if not GroupFinder.db.dungeonLevels or not button.fontString then
		return
	end
	local activityID = ns.Number(description:GetData())
	local levels = activityID and DungeonLevels(C_LFGList.GetActivityInfoTable(activityID))
	if levels then
		local label = button:AttachFontString()
		label:SetPoint("LEFT", button.fontString, "RIGHT", 5, 0)
		label:SetSize(0, button.fontString:GetHeight())
		SetLevelText(label, button.fontString, levels)
	end
end

local initActivityLevel = ns.Measured("GroupFinder: dungeon selection row", InitActivityLevel)

local function AddActivityLevels(_, menu)
	for _, description in menu:EnumerateElementDescriptions() do
		if description:IsCheckbox() then
			description:AddInitializer(initActivityLevel)
		end
		AddActivityLevels(nil, description)
	end
end

local function ResultDungeonLevels(info, text)
	if not info or info.hasSelf or ns.Secret(text) or not text then
		return
	end
	-- Blizzard can show one matching activity even when a listing covers several.
	for _, id in ipairs(info.activityIDs or {}) do
		local activityID = ns.Number(id)
		local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
		if activity and text == LFGUtil_GetActivityInfoName(activity) then
			return DungeonLevels(activity)
		end
	end
end

local function UpdateResultLevel(entry, info)
	local label = levelLabels[entry]
	local name = entry.ActivityName
	local levels = GroupFinder.db.dungeonLevels and name and ResultDungeonLevels(info, name:GetText())
	if not levels then
		if label then
			label:Hide()
		end
		return
	end
	if not label then
		label = entry:CreateFontString(nil, "OVERLAY")
		label:SetPoint("LEFT", name, "RIGHT", 5, 0)
		levelLabels[entry] = label
	end
	SetLevelText(label, name, levels)
	local nameRight = name:GetRight()
	local limit = entry.DataDisplay and entry.DataDisplay:GetLeft()
	label:SetShown(not nameRight or not limit or nameRight + 5 + label:GetStringWidth() <= limit)
end

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
		display:SetSize(200, 2 * ICON_SIZE + 2)
		display:SetPoint("RIGHT", entry, "RIGHT", -8, -1)
		display.Classes = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		display.Classes:SetPoint("TOPRIGHT")
		display.Classes:SetJustifyH("RIGHT")
		display.Missing = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
	local db = GroupFinder.db
	local info = (db.composition or db.dungeonLevels) and entry.resultID and C_LFGList.GetSearchResultInfo(entry.resultID)
	-- Results can be protected while chat messaging is locked down.
	if ns.Secret(info) or (info and (ns.Secret(info.numMembers) or ns.Secret(info.hasSelf) or ns.Secret(info.activityIDs))) then
		info = nil
	end
	UpdateResultLevel(entry, info)
	local expected = db.composition and info and not info.hasSelf and info.numMembers > 1 and Expected(GroupSize(info.activityIDs))
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
	local classIconSize = math.min(ICON_SIZE, math.floor(MAX_CLASS_ICONS_WIDTH / math.max(1, #members)))
	for _, member in ipairs(members) do
		icons[#icons + 1] = CreateAtlasMarkup("groupfinder-icon-class-" .. member.class:lower(), classIconSize, classIconSize)
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

local JOURNAL_TAB_ICON = [[Interface\Icons\INV_Misc_Book_09]]
local journalButtons = {}
local journalTab

function GroupFinder.RefreshJournalButtons()
	local journal = ns:GetModule("DungeonJournal")
	local enabled = journal and journal.IsEnabled() or false
	for _, button in ipairs(journalButtons) do
		button:SetShown(GroupFinder.db.journalButton and enabled
			and ns.Number(button.getCategory()) == DUNGEON_CATEGORY)
	end
	if journalTab then
		journalTab:SetShown(GroupFinder.db.journalTab and enabled)
		if journalTab.SetChecked then
			journalTab:SetChecked(enabled and journal.IsOpen and journal.IsOpen() or false)
		end
	end
end

local function BrowseJournalActivities()
	local selection = LFGBrowseFrame and LFGBrowseFrame.selectionBehavior
	local selectedList = selection and selection:GetSelectedElementData()
	local selected = selectedList and selectedList[1]
	local node = selected and not ns.Secret(selected) and selected.data
	local id = node and not ns.Secret(node) and ns.Number(node.resultID)
	local result = id and C_LFGList.GetSearchResultInfo(id)
	if not ns.Secret(result) and result and not ns.Secret(result.activityIDs) then
		return result.activityIDs
	end
	return LFGBrowseFrame and LFGBrowseFrame.ActivityDropdown and LFGBrowseFrame.ActivityDropdown.selectedValues
end

local function ListingJournalActivities()
	local ids = {}
	for id, selected in pairs(LFGListingFrame and LFGListingFrame.activities or {}) do
		if selected then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

local function JournalMaps(journal, activities, dungeonsOnly)
	local maps, seenMaps = {}, {}
	for _, value in ipairs(activities or {}) do
		local id = ns.Number(value)
		local activity = id and C_LFGList.GetActivityInfoTable(id)
		local mapID = not ns.Secret(activity) and activity and ns.Number(activity.mapID)
		local matches = mapID and not seenMaps[mapID] and (dungeonsOnly and journal.HasDungeon(mapID)
			or not dungeonsOnly and (journal.HasInstance and journal.HasInstance(mapID) or journal.HasDungeon(mapID)))
		if matches then
			seenMaps[mapID] = true
			maps[#maps + 1] = mapID
		end
	end
	return maps
end

local function OpenJournal(button, activities)
	local journal = ns:GetModule("DungeonJournal")
	if not journal.IsEnabled() then return end
	local maps = JournalMaps(journal, activities, true)
	if #maps == 0 then
		journal.OpenDungeons()
	elseif #maps == 1 then
		journal.Open(maps[1])
	else
		MenuUtil.CreateContextMenu(button, function(_, root)
			for _, mapID in ipairs(maps) do
				root:CreateButton(journal.InstanceName(mapID), journal.Open, mapID)
			end
		end)
	end
end

local function TabJournalActivities()
	if LFGBrowseFrame and LFGBrowseFrame:IsShown() then
		return BrowseJournalActivities()
	elseif LFGListingFrame and LFGListingFrame:IsShown() then
		return ListingJournalActivities()
	end
end

local function ToggleJournalTab()
	local journal = ns:GetModule("DungeonJournal")
	if not (journal and journal.IsEnabled()) then
		return
	end
	if journal.IsOpen and journal.IsOpen() then
		journal.Toggle()
		return
	end
	local maps = JournalMaps(journal, TabJournalActivities(), false)
	if #maps == 1 then
		journal.Open(maps[1])
	else
		journal.Open()
	end
end

local function CreateJournalButton(parent, name, anchor, category, activities)
	local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	button:SetSize(142, 28)
	button:SetPoint("BOTTOM", anchor:GetParent(), "BOTTOM", 0, 16)
	button:SetText(L.JOURNAL_TITLE)
	button.getCategory = category
	button:SetScript("OnClick", ns.Measured("GroupFinder: open dungeon journal", function(self)
		OpenJournal(self, activities())
	end))
	journalButtons[#journalButtons + 1] = button
end

local function SetupJournalTab(update)
	if journalTab or LFGVANILLA_SETTING_MODERN_STYLE == false then
		return
	end
	local parent = LFGParentFrame
	local anchor = parent and (parent.WhoListingTab or parent.BrowsingTab or parent.ListingTab)
	if not anchor then
		return
	end
	local tab = CreateFrame("Frame", "ForeverPlusLFGJournalTab", parent, "LargeSideTabButtonTemplate")
	tab:EnableMouse(true)
	tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	tab.tooltipText = L.JOURNAL_TITLE
	if tab.Icon then
		tab.Icon:SetTexture(JOURNAL_TAB_ICON)
	end
	if tab.SetFillToInterior then
		tab:SetFillToInterior(true)
	end
	local onMouseUp = ns.Measured("GroupFinder: journal tab", function(_, button, upInside)
		if button == "LeftButton" and upInside then
			ToggleJournalTab()
		end
	end)
	if tab.SetCustomOnMouseUpHandler then
		tab:SetCustomOnMouseUpHandler(onMouseUp)
	else
		tab:SetScript("OnMouseUp", onMouseUp)
	end
	parent:HookScript("OnShow", update)
	journalTab = tab
end

local function SetupJournalButtons()
	local update = ns.Measured("GroupFinder: journal button visibility", GroupFinder.RefreshJournalButtons)
	local browse = LFGBrowseFrame
	if browse and browse.CategoryDropdown and browse.SendMessageButton then
		CreateJournalButton(browse, "ForeverPlusBrowseJournalButton", browse.SendMessageButton,
			function() return browse.CategoryDropdown:GetValue() end, BrowseJournalActivities)
		hooksecurefunc(browse.CategoryDropdown, "SetValue", update)
		browse:HookScript("OnShow", update)
	end
	local listing = LFGListingFrame
	if listing and listing.ActivityView and listing.PostButton then
		CreateJournalButton(listing.ActivityView, "ForeverPlusListingJournalButton", listing.PostButton,
			function() return listing:GetCategorySelection() end, ListingJournalActivities)
		listing.ActivityView:HookScript("OnShow", update)
	end
	SetupJournalTab(update)
	GroupFinder.RefreshJournalButtons()
end

---------------------------------------------------------------------------
-- Group quests: a small button at elite, group and dungeon quests (tracker and quest log) lists the player
-- in the group finder for the place of the quest, with the roles chosen there last. The place is found by
-- name: the dungeon (all its wings: "Scarlet Monastery" lists Graveyard, Library, Armory and Cathedral) or,
-- for an elite quest outside, its zone under "Quests & Zones".
---------------------------------------------------------------------------
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

-- MatchActivities, remembered for one activity list: the tracker asks for every group quest on each of its updates,
-- and one match goes through all activities with string work. The lists returned are shared: read them only.
local matchCache, matchList = {}, nil

function GroupFinder.CachedMatch(names, activities, kind)
	if matchList ~= activities then
		matchCache, matchList = {}, activities
	end
	local key = kind .. "\1" .. tostring(names[1]) .. "\1" .. tostring(names[2])
	local ids = matchCache[key]
	if not ids then
		ids = GroupFinder.MatchActivities(names, activities, kind)
		matchCache[key] = ids
	end
	return ids
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
	local ids = GroupFinder.CachedMatch(names, Activities(), kind)
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

local logUpdateQueued = false

local function UpdateLog()
	logUpdateQueued = false
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	local facts = LogFacts()
	for title in pool:EnumerateActive() do
		ShowQuestButton(title, title.questID, facts, "RIGHT", -22, 0)
	end
end

local function QueueLogUpdate()
	if logUpdateQueued then
		return
	end
	logUpdateQueued = true
	ns.After("GroupFinder: quest buttons (log)", 0, UpdateLog)
end

function GroupFinder:OnLogin()
	ns.OnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function()
		SetupJournalButtons()
		if Menu and Menu.ModifyMenu then
			Menu.ModifyMenu("MENU_LFG_BROWSE_ACTIVITY", ns.Measured("GroupFinder: dungeon selection", AddActivityLevels))
		end
		if LFGBrowseSearchEntry_Update then
			hooksecurefunc("LFGBrowseSearchEntry_Update", ns.Measured("GroupFinder: search results", UpdateEntry))
		end
		-- The window sets the roles saved by the game when it loads: ours after it.
		GroupFinder.ApplyRoles()
	end)
	ns.OnAddOnLoaded("Blizzard_GroupFinder", GroupFinder.ApplyRoles)
	GroupFinder.ApplyRoles()
	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", function()
		if QuestObjectiveTracker and QuestObjectiveTracker.Update then
			hooksecurefunc(QuestObjectiveTracker, "Update", ns.Measured("GroupFinder: quest buttons (tracker)", UpdateTracker))
		end
	end)
	if QuestLogQuests_Update then
		hooksecurefunc("QuestLogQuests_Update", QueueLogUpdate)
	end
end

-- The roles chosen in the options, as the group finder takes them; nil while the option is off or none is chosen.
function GroupFinder.PresetRoles(db)
	if not db.presetRoles or not (db.roleTank or db.roleHealer or db.roleDps) then
		return nil
	end
	return { tank = db.roleTank and true or false, healer = db.roleHealer and true or false, dps = db.roleDps and true or false,
		leader = db.roleLeader and true or false }
end

-- Sets the own roles of the group finder (the ticks under "list yourself") and of the dungeon finder (with the
-- leader flag); roles the class cannot fill are left out by the game. The windows read them when they show.
function GroupFinder.ApplyRoles()
	local roles = GroupFinder.PresetRoles(GroupFinder.db)
	if not roles or InCombatLockdown() then
		return
	end
	if C_LFGListRoles and C_LFGListRoles.SetRoles then
		C_LFGListRoles.SetRoles({ tank = roles.tank, healer = roles.healer, dps = roles.dps }, true)
	end
	if SetLFGRoles then
		SetLFGRoles(roles.leader, roles.tank, roles.healer, roles.dps)
	end
end

function GroupFinder:OnOptionChanged(key)
	if key == "journalButton" or key == "journalTab" then
		GroupFinder.RefreshJournalButtons()
		return
	end
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
	{ key = "dungeonLevels", type = "toggle", name = L.GROUPFINDER_DUNGEON_LEVELS, desc = L.GROUPFINDER_DUNGEON_LEVELS_DESC, new = true },
	{ key = "journalButton", type = "toggle", name = L.GROUPFINDER_JOURNAL, desc = L.GROUPFINDER_JOURNAL_DESC, new = true },
	{ key = "journalTab", type = "toggle", name = L.GROUPFINDER_JOURNAL_TAB, desc = L.GROUPFINDER_JOURNAL_TAB_DESC, new = true },
	{ key = "questButton", type = "toggle", name = L.GROUPQUEST_OPTION, desc = L.GROUPQUEST_OPTION_DESC, new = true },
	{ key = "presetRoles", type = "toggle", name = L.GROUPFINDER_ROLES, desc = L.GROUPFINDER_ROLES_DESC, new = true },
	{ key = "roleTank", type = "toggle", name = TANK, parent = "presetRoles" },
	{ key = "roleHealer", type = "toggle", name = HEALER, parent = "presetRoles" },
	{ key = "roleDps", type = "toggle", name = DAMAGER, parent = "presetRoles" },
	{ key = "roleLeader", type = "toggle", name = L.GROUPFINDER_LEADER, desc = L.GROUPFINDER_LEADER_DESC, parent = "presetRoles", new = true },
	{ type = "header", name = L.GROUPFINDER_FIVE },
	Count("tank5", TANK, 5), Count("healer5", HEALER, 5), Count("dps5", DAMAGER, 5),
	{ type = "header", name = L.GROUPFINDER_TEN },
	Count("tank10", TANK, 10), Count("healer10", HEALER, 10), Count("dps10", DAMAGER, 10),
}

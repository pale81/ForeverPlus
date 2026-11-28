-- Items: quest rewards, fast loot, full bags, binding and deleting, group loot.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local CompareScores, LinkComparisonState = P.CompareScores, P.LinkComparisonState

---------------------------------------------------------------------------
-- Quest rewards: highlight the most valuable choice
---------------------------------------------------------------------------
local rewardMarks = {}

local function GetRewardMark(button)
	local mark = rewardMarks[button]
	if not mark then
		mark = CreateFrame("Frame", nil, button)
		mark:SetAllPoints(button.Icon or button.icon or button)
		mark:SetFrameLevel(button:GetFrameLevel() + 5)
		-- The coin of the junk mark in the bags marks the most valuable reward.
		local coin = mark:CreateTexture(nil, "OVERLAY", nil, 2)
		coin:SetAtlas("bags-junkcoin", true)
		coin:SetPoint("TOPLEFT", 1, 0)
		rewardMarks[button] = mark
	end
	return mark
end

local function HideRewardMarks()
	for _, mark in pairs(rewardMarks) do
		mark:Hide()
	end
end

-- Index of the most valuable choice (by vendor price) of the open quest; nil with fewer than two
-- choices, with the option off, or while item data is still loading (onLoaded runs then).
function ns.BestQuestChoice(onLoaded)
	if not Items.db or not Items.db.questReward or (GetNumQuestChoices() or 0) < 2 then
		return nil
	end
	local bestIndex, bestValue, waiting = nil, 0, false
	for i = 1, GetNumQuestChoices() do
		local link = GetQuestItemLink("choice", i)
		if link then
			local price = select(11, C_Item.GetItemInfo(link))
			if price == nil then
				waiting = true
				if onLoaded then
					Item:CreateFromItemLink(link):ContinueOnItemLoad(onLoaded)
				end
			else
				local _, _, count = GetQuestItemInfo("choice", i)
				local value = price * max(count or 1, 1)
				if value > bestValue then
					bestIndex, bestValue = i, value
				end
			end
		end
	end
	return not waiting and bestIndex or nil
end

local function MarkBestReward()
	HideRewardMarks()
	if not Items.db.questReward or QuestInfoFrame.questLog then
		return
	end
	local numChoices = GetNumQuestChoices()
	if numChoices < 2 then
		return
	end
	local bestIndex, bestValue, waiting = nil, 0, false
	for i = 1, numChoices do
		local link = GetQuestItemLink("choice", i)
		if link then
			local price = select(11, C_Item.GetItemInfo(link))
			if price == nil then
				waiting = true
				Item:CreateFromItemLink(link):ContinueOnItemLoad(MarkBestReward)
			else
				local _, _, count = GetQuestItemInfo("choice", i)
				local value = price * max(count or 1, 1)
				if value > bestValue then
					bestIndex, bestValue = i, value
				end
			end
		end
	end
	if waiting or not bestIndex then
		return
	end
	local rewardsFrame = QuestInfoFrame.rewardsFrame
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button:IsShown() and button.type == "choice" and button.objectType == "item" and button:GetID() == bestIndex then
			GetRewardMark(button):Show()
			break
		end
	end
end

-- Comparison arrow on offered and guaranteed quest rewards, also in the quest log.
local rewardArrows = {}

local function GetRewardArrow(button)
	local arrow = rewardArrows[button]
	if not arrow then
		arrow = CreateFrame("Frame", nil, button)
		arrow:SetAllPoints(button.Icon or button.icon or button)
		arrow:SetFrameLevel(button:GetFrameLevel() + 6)
		arrow.texture = arrow:CreateTexture(nil, "OVERLAY", nil, 3)
		arrow.texture:SetAtlas("bags-greenarrow", true)
		arrow.texture:SetPoint("TOPRIGHT", 0, 0)
		rewardArrows[button] = arrow
	end
	return arrow
end

local function MarkRewardUpgrades()
	for _, arrow in pairs(rewardArrows) do
		arrow:Hide()
	end
	if not Items.db.rewardUpgrade then
		return
	end
	local rewardsFrame = QuestInfoFrame.rewardsFrame
	local getLink = QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink
	for _, button in ipairs(rewardsFrame and rewardsFrame.RewardButtons or {}) do
		if button:IsShown() and button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
			local state = ns.RewardComparisonState(getLink(button.type, button:GetID()), MarkRewardUpgrades)
			if state then
				local arrow = GetRewardArrow(button)
				ns.SetItemComparisonArrow(arrow.texture, state)
				arrow:Show()
			end
		end
	end
end

-- Automatically mark soulbound quest rewards for sale when they are strictly worse than
-- equipped gear (same rating as the red arrow, independent of arrow visibility).
do
	local BIND_ON_PICKUP = Enum.ItemBind and Enum.ItemBind.OnAcquire or 1
	local onUseLineType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemSpellTriggerOnUse
	local offeredQuest, pendingQuestReward

	local function HasOnUseEffect(link)
		local spell = type(C_Item.GetItemSpell) == "function" and C_Item.GetItemSpell(link)
		if type(spell) == "string" and not ns.Secret(spell) and spell ~= "" then
			return true
		end
		if onUseLineType and type(C_TooltipInfo.GetHyperlink) == "function" then
			local data = C_TooltipInfo.GetHyperlink(link)
			for _, line in ipairs(data and data.lines or {}) do
				if line.type == onUseLineType then
					return true
				end
			end
		end
		return false
	end

	local function CheckWorseQuestReward(link, attempt)
		if not Items.db or not Items.db.markWorseReward or type(link) ~= "string" or ns.Secret(link)
			or not C_Item.IsEquippableItem(link) then
			return false
		end
		local _, _, quality, _, _, _, _, _, equipLoc, _, sellPrice, _, _, bindType = C_Item.GetItemInfo(link)
		if quality == nil or sellPrice == nil or bindType == nil then
			if (attempt or 0) < 3 then
				C_Item.RequestLoadItemDataByID(link)
				ns.After("Items: worse quest reward retry", 0.5, function()
					CheckWorseQuestReward(link, (attempt or 0) + 1)
				end)
			end
			return nil
		end
		if quality == Enum.ItemQuality.Poor or sellPrice <= 0 or bindType ~= BIND_ON_PICKUP then
			return false
		end
		local state = LinkComparisonState(link)
		if state == nil then
			if (attempt or 0) < 3 then
				C_Item.RequestLoadItemDataByID(link)
				ns.After("Items: worse quest reward retry", 0.5, function()
					CheckWorseQuestReward(link, (attempt or 0) + 1)
				end)
			end
			return nil
		end
		if state ~= "worse" then
			return false
		end
		if equipLoc == "INVTYPE_TRINKET" then
			local score = CompareScores(link)
			if not score or score <= 0 then
				return false
			end
		end
		if HasOnUseEffect(link) then
			return false
		end
		Items.MarkLinkJunk(link)
		return true
	end

	local function SnapshotOfferedQuest()
		local questID = type(GetQuestID) == "function" and ns.Number(GetQuestID()) or nil
		local choices, rewards = {}, {}
		for i = 1, ns.Number(GetNumQuestChoices(), 0) do
			choices[i] = GetQuestItemLink("choice", i)
		end
		for i = 1, ns.Number(GetNumQuestRewards(), 0) do
			rewards[i] = GetQuestItemLink("reward", i)
		end
		offeredQuest = { questID = questID, choices = choices, rewards = rewards }
	end

	local function OnGetQuestReward(choice)
		pendingQuestReward = nil
		if not Items.db or not Items.db.markWorseReward then
			return
		end
		local questID = type(GetQuestID) == "function" and ns.Number(GetQuestID()) or nil
		local snapshot = offeredQuest
			and (not questID or questID == 0 or not offeredQuest.questID or offeredQuest.questID == questID)
			and offeredQuest or nil
		if (not questID or questID == 0) and snapshot then
			questID = snapshot.questID
		end
		local liveChoices = ns.Number(GetNumQuestChoices(), 0)
		local numChoices = liveChoices > 0 and liveChoices or (snapshot and #snapshot.choices or 0)
		local picked = ns.Number(choice)
		if (not picked or picked == 0) and numChoices == 1 then
			picked = 1
		end
		local links = {}
		if picked and picked >= 1 and picked <= numChoices then
			local link = (liveChoices > 0 and GetQuestItemLink("choice", picked))
				or (snapshot and snapshot.choices[picked])
			if type(link) == "string" and not ns.Secret(link) then
				links[#links + 1] = link
			end
		end
		local liveRewards = ns.Number(GetNumQuestRewards(), 0)
		if liveRewards > 0 then
			for i = 1, liveRewards do
				local link = GetQuestItemLink("reward", i) or (snapshot and snapshot.rewards[i])
				if type(link) == "string" and not ns.Secret(link) then
					links[#links + 1] = link
				end
			end
		elseif snapshot then
			for _, link in ipairs(snapshot.rewards) do
				if type(link) == "string" and not ns.Secret(link) then
					links[#links + 1] = link
				end
			end
		end
		if #links > 0 then
			pendingQuestReward = { questID = questID, links = links, time = GetTime() }
		end
	end

	local function OnQuestTurnedIn(_, _, questID)
		offeredQuest = nil
		local pending = pendingQuestReward
		if not pending then
			return
		end
		if GetTime() - pending.time > 10 then
			pendingQuestReward = nil
			return
		end
		if pending.questID and pending.questID ~= 0 and questID and pending.questID ~= questID then
			return
		end
		pendingQuestReward = nil
		for _, link in ipairs(pending.links) do
			CheckWorseQuestReward(link)
		end
	end

	local function OnQuestLootReceived(_, _, _, itemLink)
		CheckWorseQuestReward(itemLink)
	end

	Items.questRewardJunk = {
		Snapshot = SnapshotOfferedQuest,
		OnReward = OnGetQuestReward,
		OnTurnIn = OnQuestTurnedIn,
		OnLoot = OnQuestLootReceived,
		Reset = function()
			offeredQuest, pendingQuestReward = nil, nil
		end,
	}
	Items.OnGetQuestReward = OnGetQuestReward
	Items.CheckWorseQuestReward = CheckWorseQuestReward
end

---------------------------------------------------------------------------
-- Fast loot: take every slot as soon as the loot window is ready
---------------------------------------------------------------------------
local lastLoot = 0

function Items:LOOT_READY()
	ns:GetModule("LootSources").CaptureWindow()
	local now = GetTime()
	if now - lastLoot < 0.3 then
		return
	end
	lastLoot = now
	if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
		for i = GetNumLootItems(), 1, -1 do
			LootSlot(i)
		end
	end
end

---------------------------------------------------------------------------
-- Full bags: offer the cheapest item for destruction. The item is only picked
-- up; Blizzard's own delete confirmation does the rest (deleting is
-- restricted for addons).
---------------------------------------------------------------------------
local PROMPT_COOLDOWN = 60
local lastPrompt = 0
local destroyDialog

local function FindCheapestItem()
	local best
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			-- Only grey (poor) items are offered for destruction.
			if info and not info.hasNoValue and not info.isLocked and info.quality == Enum.ItemQuality.Poor then
				local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 and not (quest and (quest.isQuestItem or quest.questID)) then
					local value = price * info.stackCount
					if not best or value < best.value then
						best = { bag = bag, slot = slot, value = value, link = info.hyperlink, icon = info.iconFileID, count = info.stackCount }
					end
				end
			end
		end
	end
	return best
end

local function CreateDestroyDialog()
	local frame = ns.CreatePanel("ForeverPlusDestroyDialog", { close = true })
	frame:SetSize(360, 150)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
	frame.Title:SetText(L.ITEMS_BAGS_FULL)

	frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	frame.Icon:SetSize(36, 36)
	frame.Icon:SetPoint("TOPLEFT", ns.PANEL_PADDING + 2, -36)
	frame.Item = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.Item:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 10, -2)
	frame.Item:SetPoint("RIGHT", -16, 0)
	frame.Item:SetJustifyH("LEFT")
	frame.Value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Value:SetPoint("TOPLEFT", frame.Item, "BOTTOMLEFT", 0, -4)
	frame.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Hint:SetPoint("TOPLEFT", frame.Icon, "BOTTOMLEFT", 0, -8)
	frame.Hint:SetPoint("RIGHT", -16, 0)
	frame.Hint:SetJustifyH("LEFT")
	frame.Hint:SetText(L.ITEMS_DESTROY_HINT)

	frame.Accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Accept:SetSize(150, 22)
	frame.Accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
	frame.Accept:SetText(L.ITEMS_DESTROY_PICKUP)
	frame.Accept:SetScript("OnClick", function()
		local entry = frame.entry
		frame:Hide()
		-- Only if that slot still holds the offered item (the bags may have changed).
		local info = entry and C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if info and info.hyperlink == entry.link and not InCombatLockdown() then
			ClearCursor()
			C_Container.PickupContainerItem(entry.bag, entry.slot)
		end
	end)
	frame.Cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Cancel:SetSize(150, 22)
	frame.Cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
	frame.Cancel:SetText(CANCEL)
	frame.Cancel:SetScript("OnClick", function()
		frame:Hide()
	end)
	return frame
end

-- Vendor value of the most valuable item still in the open loot window
-- (math.huge for quest items); nil without loot window or item prices.
local function IncomingValue()
	local best
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local _, _, quantity, _, _, _, isQuestItem = GetLootSlotInfo(slot)
			local link = GetLootSlotLink(slot)
			local price = link and select(11, C_Item.GetItemInfo(link))
			local value = isQuestItem and math.huge or (price and price * math.max(quantity or 1, 1))
			if value and (not best or value > best) then
				best = value
			end
		end
	end
	return best
end

local function OfferDestroy()
	local now = GetTime()
	if now - lastPrompt < PROMPT_COOLDOWN or InCombatLockdown() then
		return
	end
	local entry = FindCheapestItem()
	if not entry then
		return
	end
	-- Never offer something worth more than what is waiting to be looted.
	local incoming = IncomingValue()
	if incoming and entry.value >= incoming then
		lastPrompt = now
		ns.Print(L.ITEMS_DESTROY_NOT_WORTH)
		return
	end
	lastPrompt = now
	destroyDialog = destroyDialog or CreateDestroyDialog()
	destroyDialog.entry = entry
	destroyDialog.Icon:SetTexture(entry.icon)
	destroyDialog.Item:SetText(entry.count > 1 and ("%s x%d"):format(entry.link, entry.count) or entry.link)
	destroyDialog.Value:SetText(L.ITEMS_DESTROY_VALUE:format(GetMoneyString(entry.value, true)))
	destroyDialog:Show()
end

-- A sound when the bags have just become full (the last free slot taken) or an item found no room.
Items.fullState = { last = 0 }
local QUEST_FAILED_SOUND = 567459 -- sound/interface/igquestfailed.ogg in the client

local function PlaySelectedFullSound()
	local choice = Items.db.fullSoundChoice
	if choice == "warning" then
		if not PlaySoundFile(QUEST_FAILED_SOUND, "Master") and SOUNDKIT and SOUNDKIT.RAID_WARNING then
			PlaySound(SOUNDKIT.RAID_WARNING, "Master")
		end
	elseif ns.AlertSounds then
		ns.AlertSounds.play(choice)
	end
end

function Items.PlayFullSound()
	local state = Items.fullState
	local now = GetTime()
	if now - state.last < 3 then
		return
	end
	state.last = now
	PlaySelectedFullSound()
end

-- Free slots of the bags that take any item (not those of special bags).
function Items.FreeSlots()
	local free = 0
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			free = free + ns.Number(slots, 0)
		end
	end
	return free
end

function Items.CheckFull()
	local state = Items.fullState
	local full = Items.FreeSlots() == 0
	if full and state.wasFull == false then
		Items.PlayFullSound()
	end
	state.wasFull = full
end

function Items:UpdateFullSound()
	local state = self.fullState
	if not state.frame then
		state.frame = CreateFrame("Frame")
		state.frame:SetScript("OnEvent", ns.Measured("Items: bags full", function(_, event, _, message)
			if event == "UI_ERROR_MESSAGE" then
				if not ns.Secret(message) and message == ERR_INV_FULL then
					Items.PlayFullSound()
				end
			else
				Items.CheckFull()
			end
		end))
	end
	if self.db.fullSound then
		state.frame:RegisterEvent("BAG_UPDATE_DELAYED")
		state.frame:RegisterEvent("UI_ERROR_MESSAGE")
		if state.wasFull == nil then
			state.wasFull = Items.FreeSlots() == 0 -- the state now, so there is no sound at login with full bags
		end
	else
		state.frame:UnregisterAllEvents()
		state.wasFull = nil
	end
end

function Items:UI_ERROR_MESSAGE(_, _, message)
	if ns.Secret(message) then
		return
	end
	if message == ERR_INV_FULL then
		OfferDestroy()
	end
end

---------------------------------------------------------------------------
-- Bind on pickup: confirm automatically (loot window and group rolls)
---------------------------------------------------------------------------
local function HidePopup(which)
	ns.After("Items: HidePopup (timer)", 0, function()
		StaticPopup_Hide(which)
	end)
end

function Items:LOOT_BIND_CONFIRM(_, slot)
	ConfirmLootSlot(slot)
	HidePopup("LOOT_BIND")
end

function Items:CONFIRM_LOOT_ROLL(_, rollID, rollType)
	ConfirmLootRoll(rollID, rollType)
	HidePopup("CONFIRM_LOOT_ROLL")
end

-- Equipping or using an item that binds.
local function EquipBound(self, _, slot)
	EquipPendingItem(slot)
	HidePopup("EQUIP_BIND")
	HidePopup("EQUIP_BIND_REFUNDABLE")
	HidePopup("EQUIP_BIND_TRADEABLE")
end

function Items:USE_BIND_CONFIRM()
	ConfirmBindOnUse()
	HidePopup("USE_BIND")
end

-- Deleting valuable items asks to type the word; the text is entered, the
-- confirming click stays with the player (deleting is closed to addons).
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local function FillDeleteText(which)
	if not DELETE_POPUPS[which] or not Items.db.deleteText then
		return
	end
	local dialog = StaticPopup_FindVisible(which)
	local editBox = dialog and dialog:GetEditBox()
	if editBox and DELETE_ITEM_CONFIRM_STRING then
		editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
	end
end

---------------------------------------------------------------------------
-- Group loot: number of need/greed/pass choices on the buttons, names on hover
---------------------------------------------------------------------------
local ROLL_BUTTONS = {
	NeedButton = { [Enum.EncounterLootDropRollState.NeedMainSpec] = true, [Enum.EncounterLootDropRollState.NeedOffSpec] = true },
	GreedButton = { [Enum.EncounterLootDropRollState.Greed] = true },
	TransmogButton = { [Enum.EncounterLootDropRollState.Transmog] = true },
	PassButton = { [Enum.EncounterLootDropRollState.Pass] = true },
}
local rollNames = {}  -- button -> { names }
local rollLabels = {} -- button -> font string
local rollHooked = {}

local function ItemIDOfLink(link)
	return link and not ns.Secret(link) and C_Item.GetItemInfoInstant(link)
end

local function ShowRollNames(button)
	local names = rollNames[button]
	if not Items.db.rollCounts or not names or #names == 0 or GameTooltip:GetOwner() ~= button then
		return
	end
	for _, name in ipairs(names) do
		GameTooltip:AddLine(name, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function SetRollCount(button, names)
	if not rollHooked[button] then
		rollHooked[button] = true
		button:HookScript("OnEnter", ShowRollNames)
	end
	local label = rollLabels[button]
	if not label then
		label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
		rollLabels[button] = label
	end
	rollNames[button] = names
	label:SetText(#names > 0 and #names or "")
	label:SetShown(Items.db.rollCounts)
end

local function ResetRollFrame(frame)
	local container = frame.LootButtonContainer or frame
	for key in pairs(ROLL_BUTTONS) do
		local button = container[key]
		if button then
			SetRollCount(button, {})
		end
	end
end

function Items:LOOT_HISTORY_UPDATE_DROP(_, encounterID, lootListKey)
	local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)
	local itemID = info and ItemIDOfLink(info.itemHyperlink)
	if not itemID then
		return
	end
	for index = 1, 4 do
		local frame = _G["GroupLootFrame" .. index]
		if frame and frame:IsShown() and frame.rollID and ItemIDOfLink(GetLootRollItemLink(frame.rollID)) == itemID then
			local container = frame.LootButtonContainer or frame
			for key, states in pairs(ROLL_BUTTONS) do
				local button = container[key]
				if button then
					local names = {}
					for _, roll in ipairs(info.rollInfos or {}) do
						if states[roll.state] and not ns.Secret(roll.playerName) then
							local color = C_ClassColor.GetClassColor(roll.playerClass)
							names[#names + 1] = color and color:WrapTextInColorCode(roll.playerName) or roll.playerName
						end
					end
					SetRollCount(button, names)
				end
			end
		end
	end
end

local function HookRollFrames()
	for index = 1, 4 do
		local frame = _G["GroupLootFrame" .. index]
		if frame then
			frame:HookScript("OnShow", ResetRollFrame)
		end
	end
end

-- For the Items*.lua files loaded after this one.
P.EquipBound = EquipBound
P.FillDeleteText = FillDeleteText
P.HookRollFrames = HookRollFrames
P.MarkBestReward = MarkBestReward
P.MarkRewardUpgrades = MarkRewardUpgrades
P.PlaySelectedFullSound = PlaySelectedFullSound

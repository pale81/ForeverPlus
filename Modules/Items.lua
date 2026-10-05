-- Items: junk selling and marking, auto repair, quest reward value,
-- upgrade arrows in bags and fast looting.
local _, ns = ...
local L = ns.L

local Items = ns:NewModule("Items", {
	title = L.ITEMS_TITLE,
	order = 4,
	defaults = {
		autoSell = true,
		autoRepair = true,
		repairGuild = true,
		questReward = true,
		upgradeArrow = true,
		fastLoot = true,
		junk = {},
	},
})

local SELL_BATCH = 10
local SELL_INTERVAL = 0.2

---------------------------------------------------------------------------
-- Junk marking (double click in bags)
---------------------------------------------------------------------------
local function IsMarked(itemID)
	return itemID and Items.db.junk[itemID] or false
end

local function IsJunk(info)
	if not info or info.hasNoValue or info.isLocked then
		return false
	end
	return info.quality == Enum.ItemQuality.Poor or IsMarked(info.itemID)
end

---------------------------------------------------------------------------
-- Upgrade arrows
---------------------------------------------------------------------------
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_2HWEAPON = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONMAINHAND = { INVSLOT_MAINHAND }, INVTYPE_WEAPONOFFHAND = { INVSLOT_OFFHAND },
	INVTYPE_SHIELD = { INVSLOT_OFFHAND }, INVTYPE_HOLDABLE = { INVSLOT_OFFHAND },
	INVTYPE_RANGED = { INVSLOT_RANGED }, INVTYPE_RANGEDRIGHT = { INVSLOT_RANGED },
	INVTYPE_THROWN = { INVSLOT_RANGED }, INVTYPE_RELIC = { INVSLOT_RANGED },
}
local ONE_HAND_SLOTS = { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
local MAIN_HAND_SLOT = { INVSLOT_MAINHAND }

local equippedLevel = {}   -- slot -> item level (0 when empty)
local upgradeCache = {}    -- hyperlink -> bool

local function UpdateEquippedLevels()
	for slot = 1, 19 do
		local location = ItemLocation:CreateFromEquipmentSlot(slot)
		equippedLevel[slot] = C_Item.DoesItemExist(location) and C_Item.GetCurrentItemLevel(location) or 0
	end
	wipe(upgradeCache)
end

local function IsRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

-- Red lines in the item tooltip mean the player cannot use it (class, armor type, level).
local function CanUse(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	if not data or not data.lines then
		return false
	end
	for _, line in ipairs(data.lines) do
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			return false
		end
	end
	return true
end

local function IsUpgrade(bag, slot, link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end
	local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
	local slots = EQUIP_SLOTS[equipLoc]
	if equipLoc == "INVTYPE_WEAPON" then
		slots = CanDualWield() and ONE_HAND_SLOTS or MAIN_HAND_SLOT
	end
	local result = false
	if slots then
		local level = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, slot))
		if level then
			local lowest
			for _, invSlot in ipairs(slots) do
				local equipped = equippedLevel[invSlot] or 0
				lowest = lowest and min(lowest, equipped) or equipped
			end
			result = level > lowest and CanUse(bag, slot)
		end
	end
	-- Only cache once the item data is complete.
	if C_Item.IsItemDataCachedByID(link) then
		upgradeCache[link] = result
	end
	return result
end

---------------------------------------------------------------------------
-- Bag button decoration
---------------------------------------------------------------------------
local function UpdateButton(button)
	local bag, slot = button:GetBagID(), button:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)

	if button.JunkIcon and info and IsMarked(info.itemID) then
		button.JunkIcon:Show()
	end

	if button.UpgradeIcon then
		local show = false
		if Items.db.upgradeArrow and info and info.hyperlink and C_Item.IsEquippableItem(info.hyperlink) then
			show = IsUpgrade(bag, slot, info.hyperlink)
		end
		button.UpgradeIcon:SetShown(show)
	end
end

local function UpdateContainerFrame(frame)
	if not frame:IsShown() then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		UpdateButton(button)
	end
end

local function UpdateAllBags()
	if ContainerFrameCombinedBags then
		UpdateContainerFrame(ContainerFrameCombinedBags)
	end
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		UpdateContainerFrame(frame)
	end
end

local hookedButtons = {}

local function OnItemDoubleClick(button, mouseButton)
	if mouseButton ~= "LeftButton" then
		return
	end
	-- The first click picked the item up; put it back.
	if CursorHasItem() then
		ClearCursor()
	end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if not info or not info.itemID then
		return
	end
	local junk = Items.db.junk
	if junk[info.itemID] then
		junk[info.itemID] = nil
		ns.Print(L.ITEMS_UNMARKED, info.hyperlink)
	else
		junk[info.itemID] = true
		ns.Print(L.ITEMS_MARKED, info.hyperlink)
	end
	UpdateAllBags()
end

local function PostUpdateItems(frame)
	for _, button in frame:EnumerateValidItems() do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnDoubleClick", OnItemDoubleClick)
		end
		UpdateButton(button)
	end
end

local function HookContainerFrames()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", PostUpdateItems)
		end
	end
end

---------------------------------------------------------------------------
-- Merchant: sell junk and repair
---------------------------------------------------------------------------
local sellTicker, soldValue

local function StopSelling()
	if sellTicker then
		sellTicker:Cancel()
		sellTicker = nil
	end
	if soldValue and soldValue > 0 then
		ns.Print(L.ITEMS_SOLD, GetMoneyString(soldValue, true))
	end
	soldValue = nil
end

local function SellBatch()
	if not MerchantFrame:IsShown() then
		StopSelling()
		return
	end
	local sold = 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsJunk(info) then
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 then
					C_Container.UseContainerItem(bag, slot)
					soldValue = soldValue + price * info.stackCount
					sold = sold + 1
					if sold >= SELL_BATCH then
						return
					end
				end
			end
		end
	end
	StopSelling()
end

local function Repair()
	if not CanMerchantRepair() then
		return
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost <= 0 then
		return
	end
	if Items.db.repairGuild and IsInGuild() and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney()
		if limit == -1 or limit >= cost then
			RepairAllItems(true)
			ns.Print(L.ITEMS_REPAIRED_GUILD, GetMoneyString(cost, true))
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems(false)
		ns.Print(L.ITEMS_REPAIRED, GetMoneyString(cost, true))
	else
		ns.Print(L.ITEMS_REPAIR_NO_MONEY)
	end
end

function Items:MERCHANT_SHOW()
	if self.db.autoRepair then
		Repair()
	end
	if self.db.autoSell and not sellTicker then
		soldValue = 0
		SellBatch()
		if soldValue then
			sellTicker = C_Timer.NewTicker(SELL_INTERVAL, SellBatch)
		end
	end
end

function Items:MERCHANT_CLOSED()
	StopSelling()
end

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
		local glow = mark:CreateTexture(nil, "OVERLAY")
		glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1, 0.82, 0)
		glow:SetPoint("CENTER")
		glow:SetSize(button:GetHeight() * 1.9, button:GetHeight() * 1.9)
		local coin = mark:CreateTexture(nil, "OVERLAY", nil, 2)
		coin:SetAtlas("coin-gold")
		coin:SetSize(16, 16)
		coin:SetPoint("TOPLEFT", -4, 4)
		rewardMarks[button] = mark
	end
	return mark
end

local function HideRewardMarks()
	for _, mark in pairs(rewardMarks) do
		mark:Hide()
	end
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

---------------------------------------------------------------------------
-- Fast loot (same approach as Leatrix Plus)
---------------------------------------------------------------------------
local lastLoot = 0

function Items:LOOT_READY()
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
-- Lifecycle
---------------------------------------------------------------------------
function Items:Refresh()
	local db = self.db
	local merchant = db.autoSell or db.autoRepair
	self:ToggleEvent("MERCHANT_SHOW", merchant)
	self:ToggleEvent("MERCHANT_CLOSED", merchant)
	self:ToggleEvent("LOOT_READY", db.fastLoot)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", db.upgradeArrow, function()
		UpdateEquippedLevels()
		UpdateAllBags()
	end)
	self:ToggleEvent("PLAYER_LEVEL_UP", db.upgradeArrow, function()
		wipe(upgradeCache)
	end)
end

function Items:OnLogin()
	UpdateEquippedLevels()
	HookContainerFrames()
	hooksecurefunc("QuestInfo_Display", MarkBestReward)
	self:Refresh()
end

function Items:OnOptionChanged()
	self:Refresh()
	UpdateAllBags()
	if QuestInfoFrame:IsVisible() then
		MarkBestReward()
	end
end

Items.options = {
	{ type = "header", name = L.ITEMS_MERCHANT },
	{ key = "autoSell", type = "toggle", name = L.ITEMS_AUTOSELL, desc = L.ITEMS_AUTOSELL_DESC },
	{ key = "autoRepair", type = "toggle", name = L.ITEMS_AUTOREPAIR, desc = L.ITEMS_AUTOREPAIR_DESC },
	{ key = "repairGuild", type = "toggle", name = L.ITEMS_REPAIR_GUILD, desc = L.ITEMS_REPAIR_GUILD_DESC, parent = "autoRepair" },
	{ type = "button", name = L.ITEMS_CLEAR_JUNK, text = L.RESET, desc = L.ITEMS_CLEAR_JUNK_DESC, func = function()
		wipe(Items.db.junk)
		UpdateAllBags()
	end },
	{ type = "header", name = L.ITEMS_DISPLAY },
	{ key = "questReward", type = "toggle", name = L.ITEMS_QUEST_REWARD, desc = L.ITEMS_QUEST_REWARD_DESC },
	{ key = "upgradeArrow", type = "toggle", name = L.ITEMS_UPGRADE, desc = L.ITEMS_UPGRADE_DESC },
	{ type = "header", name = L.ITEMS_LOOT },
	{ key = "fastLoot", type = "toggle", name = L.ITEMS_FASTLOOT, desc = L.ITEMS_FASTLOOT_DESC },
}

-- Restock list: Alt + middle click on a bag item marks it (small bag symbol
-- at the bottom left, with an arrow down). At the bank, marked items are
-- topped up to a full stack from the bank; at the guild bank from the tab on
-- display, as far as the withdrawal rights allow. A second click turns the
-- mark around (arrow up): such an item is put from the bags into the bank
-- instead; a third click removes the mark. One move at a time, each waits
-- until the client has confirmed the previous one.
local _, ns = ...
local L = ns.L

local Restock = ns:NewModule("Restock", {
	title = L.RESTOCK_TITLE,
	order = 4.6,
	defaults = {
		enabled = true,
		message = true,
	},
	charDefaults = {
		items = {}, -- itemID -> true (from the bank into the bags) or "bank" (from the bags into the bank)
	},
})

local ICON = [[Interface\Icons\INV_Misc_Bag_08]]
local ICON_SIZE = 14
local STEP_INTERVAL = 0.3
local MAX_STEPS = 200
local GUILD_SLOTS = 98 -- slots per guild bank tab
local GUILD_DELAY = 0.5 -- the tab contents arrive after switching tabs
local NORMAL_BAGS_LAST = 4 -- the reagent bag (5) takes only reagents

local TO_BANK = "bank"
local ARROW = { [true] = "NPE_ArrowDown", [TO_BANK] = "NPE_ArrowUp" }
local ARROW_COLOR = { [true] = { 0.3, 1, 0.3 }, [TO_BANK] = { 1, 0.6, 0.15 } }
local ARROW_SIZE = 11

local icons = {}  -- bag button -> texture
local arrows = {} -- bag button -> arrow texture
local hooked = {}
local run         -- { ticker, steps, moved = { itemID -> count }, wait = { bag, slot }, skip = { itemID -> true } }
local atBank, atGuild = false, false

local function Report(...)
	if Restock.db.message then
		ns.Print(...)
	end
end

local function MaxStack(itemID)
	return ns.Number(C_Item.GetItemMaxStackSizeByID(itemID), 0)
end

local function BagCount(itemID)
	return ns.Number(C_Item.GetItemCount(itemID), 0)
end

---------------------------------------------------------------------------
-- Marks in the bags
---------------------------------------------------------------------------
local function UpdateButton(button)
	local icon = icons[button]
	if not Restock.db.enabled and not icon then
		return
	end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	local mode = Restock.db.enabled and info and info.itemID and Restock.cdb.items[info.itemID] or nil
	local show = mode and true or false
	if show and not icon then
		icon = button:CreateTexture(nil, "OVERLAY", nil, 2)
		icon:SetTexture(ICON)
		icon:SetSize(ICON_SIZE, ICON_SIZE)
		icon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
		icons[button] = icon
		local arrow = button:CreateTexture(nil, "OVERLAY", nil, 3)
		arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
		arrow:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", -2, 0)
		arrows[button] = arrow
	end
	if icon then
		icon:SetShown(show)
		local arrow = arrows[button]
		arrow:SetShown(show)
		if show then
			arrow:SetAtlas(ARROW[mode])
			arrow:SetVertexColor(unpack(ARROW_COLOR[mode]))
		end
	end
end

local function ContainerFrames()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	return frames
end

local function UpdateAllButtons()
	for _, frame in ipairs(ContainerFrames()) do
		if frame and frame:IsShown() then
			for _, button in frame:EnumerateValidItems() do
				UpdateButton(button)
			end
		end
	end
end

local function Toggle(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then
		return
	end
	local list = Restock.cdb.items
	local mode = list[info.itemID]
	if mode == TO_BANK then
		list[info.itemID] = nil
		Report(L.RESTOCK_UNMARKED, info.hyperlink)
	elseif mode or MaxStack(info.itemID) <= 1 then
		-- second click (or an item that does not stack: no topping up): the other way round
		list[info.itemID] = TO_BANK
		Report(L.RESTOCK_MARKED_BANK, info.hyperlink)
	else
		list[info.itemID] = true
		Report(L.RESTOCK_MARKED, info.hyperlink)
	end
	UpdateAllButtons()
end

local function OnItemMouseUp(button, mouseButton)
	if mouseButton == "MiddleButton" and IsAltKeyDown() and Restock.db.enabled and button:IsMouseOver() then
		Toggle(button:GetBagID(), button:GetID())
	end
end

local function PostUpdateItems(frame)
	for _, button in frame:EnumerateValidItems() do
		if not hooked[button] then
			hooked[button] = true
			button:HookScript("OnMouseUp", OnItemMouseUp)
		end
		UpdateButton(button)
	end
end

-- Alt + middle click belongs to the restock list (the junk mark skips it).
function Restock:ClaimsAltMiddleClick()
	return self.db.enabled
end

---------------------------------------------------------------------------
-- Topping up
---------------------------------------------------------------------------
-- Slot in the bags that takes `amount`: a stack of the item with room, else
-- an empty slot of an ordinary bag.
local function FindTarget(itemID, amount, maxStack)
	local free
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				if info.itemID == itemID and not info.isLocked and maxStack - info.stackCount >= amount then
					return bag, slot
				end
			elseif not free and bag <= NORMAL_BAGS_LAST and bagFamily == 0 then
				free = { bag, slot }
			end
		end
	end
	if free then
		return free[1], free[2]
	end
end

local function BankBags(characterOnly)
	local bags = {}
	for _, bankType in ipairs(characterOnly and { Enum.BankType.Character } or { Enum.BankType.Character, Enum.BankType.Account }) do
		if C_Bank.CanUseBank(bankType) then
			for _, bag in ipairs(C_Bank.FetchPurchasedBankTabIDs(bankType) or {}) do
				bags[#bags + 1] = bag
			end
		end
	end
	return bags
end

-- Source of the item: bank slot { bag, slot, count } or guild slot { tab, slot, count }.
local function FindInBank(itemID)
	for _, bag in ipairs(BankBags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked then
				return { bag = bag, slot = slot, count = info.stackCount }
			end
		end
	end
end

local function FindInGuild(itemID)
	local tab = GetCurrentGuildBankTab()
	local _, _, viewable, _, _, remaining = GetGuildBankTabInfo(tab)
	if not viewable or remaining == 0 then
		return nil
	end
	for slot = 1, GUILD_SLOTS do
		local link = GetGuildBankItemLink(tab, slot)
		if link and C_Item.GetItemInfoInstant(link) == itemID then
			local _, count, locked = GetGuildBankItemInfo(tab, slot)
			if not locked and (count or 0) > 0 then
				return { tab = tab, slot = slot, count = count }
			end
		end
	end
end

-- Slot in the bank that takes `count` of the item: a stack with room, else an empty slot.
local function FindBankTarget(itemID, count, maxStack)
	local free
	for _, bag in ipairs(BankBags(true)) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				if info.itemID == itemID and not info.isLocked and maxStack - info.stackCount >= count then
					return bag, slot
				end
			elseif not free then
				free = { bag, slot }
			end
		end
	end
	if free then
		return free[1], free[2]
	end
end

-- A stack of the item in the bags.
local function FindInBags(itemID)
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked then
				return bag, slot, info.stackCount
			end
		end
	end
end

local warnedFull = {}

local function Finish()
	if not run then
		return
	end
	run.ticker:Cancel()
	for _, kind in ipairs({ "moved", "stored" }) do
		local parts = {}
		for itemID, count in pairs(run[kind]) do
			parts[#parts + 1] = ("%s %d"):format(C_Item.GetItemNameByID(itemID) or ("item:" .. itemID), count)
		end
		if #parts > 0 then
			table.sort(parts)
			Report(kind == "moved" and L.RESTOCK_DONE or L.RESTOCK_STORED, table.concat(parts, ", "))
		end
	end
	run = nil
end

-- One move per call; nil when nothing is left to do.
local function MoveOne()
	for itemID, mode in pairs(Restock.cdb.items) do
		local maxStack = MaxStack(itemID)
		local need = maxStack - BagCount(itemID)
		if mode == TO_BANK then
			if atBank and not run.skip[itemID] then
				local bag, slot, count = FindInBags(itemID)
				if not bag then
					run.skip[itemID] = true
				else
					local bankBag, bankSlot = FindBankTarget(itemID, count, maxStack)
					if not bankBag then
						run.skip[itemID] = true
						if not warnedFull[itemID] then
							warnedFull[itemID] = true
							ns.Print(L.RESTOCK_BANK_FULL, C_Item.GetItemNameByID(itemID) or itemID)
						end
					else
						C_Container.PickupContainerItem(bag, slot)
						C_Container.PickupContainerItem(bankBag, bankSlot)
						if GetCursorInfo() then
							ClearCursor()
							run.skip[itemID] = true
						else
							run.stored[itemID] = (run.stored[itemID] or 0) + count
							run.wait = { bankBag, bankSlot }
						end
						return true
					end
				end
			end
		elseif need > 0 and not run.skip[itemID] then
			local source = atBank and FindInBank(itemID) or atGuild and FindInGuild(itemID)
			if not source then
				run.skip[itemID] = true -- not in the bank: no rescan every step
			else
				local amount = math.min(need, source.count)
				local bag, slot = FindTarget(itemID, amount, maxStack)
				if not bag then
					run.skip[itemID] = true
					if not warnedFull[itemID] then
						warnedFull[itemID] = true -- once per session, not with every bank change
						ns.Print(L.RESTOCK_BAGS_FULL, C_Item.GetItemNameByID(itemID) or itemID)
					end
				else
					if source.tab then
						if amount == source.count then
							PickupGuildBankItem(source.tab, source.slot)
						else
							SplitGuildBankItem(source.tab, source.slot, amount)
						end
					elseif amount == source.count then
						C_Container.PickupContainerItem(source.bag, source.slot)
					else
						C_Container.SplitContainerItem(source.bag, source.slot, amount)
					end
					C_Container.PickupContainerItem(bag, slot)
					if GetCursorInfo() then
						ClearCursor() -- not taken: back to where it came from
						run.skip[itemID] = true
					else
						run.moved[itemID] = (run.moved[itemID] or 0) + amount
						run.wait = { bag, slot }
					end
					return true
				end
			end
		end
	end
end

local function Step()
	if not run then
		return
	end
	run.steps = run.steps + 1
	if InCombatLockdown() or not (atBank or atGuild) or run.steps > MAX_STEPS then
		Finish()
		return
	end
	if GetCursorInfo() then
		return -- the player is holding something
	end
	-- The previous move counts once its target slot is no longer locked.
	if run.wait then
		local info = C_Container.GetContainerItemInfo(run.wait[1], run.wait[2])
		if info and info.isLocked then
			return
		end
		run.wait = nil
	end
	if not MoveOne() then
		Finish()
	end
end

local function Start()
	if run or not Restock.db.enabled or InCombatLockdown() or not next(Restock.cdb.items) then
		return
	end
	run = { steps = 0, moved = {}, stored = {}, skip = {} }
	run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
end

local guildQueued = false
local function QueueGuild()
	if not guildQueued then
		guildQueued = true
		C_Timer.After(GUILD_DELAY, function()
			guildQueued = false
			if atGuild then
				Start()
			end
		end)
	end
end

---------------------------------------------------------------------------
-- List popup and setup
---------------------------------------------------------------------------
function Restock:ShowList(owner)
	ns.ShowPopupList(owner, function()
		local items = {}
		for itemID, mode in pairs(self.cdb.items) do
			items[#items + 1] = {
				icon = C_Item.GetItemIconByID(itemID),
				text = (mode == TO_BANK and L.RESTOCK_LIST_TO_BANK or L.RESTOCK_LIST_FROM_BANK):format(C_Item.GetItemNameByID(itemID) or ("item:" .. itemID)),
				onClick = function()
					self.cdb.items[itemID] = nil
					UpdateAllButtons()
				end,
				tooltip = function(tooltip)
					tooltip:SetItemByID(itemID)
					GameTooltip_AddInstructionLine(tooltip, L.RESTOCK_REMOVE_HINT)
				end,
			}
		end
		table.sort(items, function(a, b)
			return a.text < b.text
		end)
		return { title = L.RESTOCK_LIST, items = items, empty = L.RESTOCK_NONE }
	end)
end

function Restock:Apply()
	local enabled = self.db.enabled
	if not enabled then
		atBank, atGuild = false, false
		Finish()
	end
	self:ToggleEvent("BANKFRAME_OPENED", enabled, function()
		atBank = true
		Start()
	end)
	self:ToggleEvent("BANKFRAME_CLOSED", enabled, function()
		atBank = false
	end)
	self:ToggleEvent("GUILDBANKFRAME_OPENED", enabled, function()
		atGuild = true
		QueueGuild()
	end)
	self:ToggleEvent("GUILDBANKFRAME_CLOSED", enabled, function()
		atGuild = false
	end)
	self:ToggleEvent("GUILDBANKBAGSLOTS_CHANGED", enabled, function()
		if atGuild and not run then
			QueueGuild()
		end
	end)
	UpdateAllButtons()
end

function Restock:OnLogin()
	for _, frame in ipairs(ContainerFrames()) do
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", ns.Measured("Restock: bag update", PostUpdateItems))
		end
	end
	self:Apply()
end

function Restock:OnOptionChanged()
	self:Apply()
end

Restock.options = {
	{ key = "enabled", type = "toggle", name = L.RESTOCK_ENABLE, desc = L.RESTOCK_ENABLE_DESC },
	{ key = "message", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "enabled" },
	{ type = "button", name = L.RESTOCK_LIST, text = L.ITEMS_JUNK_SHOW, desc = L.RESTOCK_LIST_DESC, func = function(button)
		Restock:ShowList(button)
	end },
}

-- Services at trainers and the bank: "Train all" with the total cost in the
-- trainer window, "Deposit reagents" in the bank (crafting reagents from the
-- bags onto the bank's stacks or free slots, as in later expansions).
local _, ns = ...
local L = ns.L

local Services = ns:NewModule("Services", {
	title = L.SERVICES_TITLE,
	order = 4.7,
	defaults = {
		trainAll = true,
		depositReagents = true,
	},
})

local STEP_INTERVAL = 0.2
local MAX_STEPS = 300
local LAST_BAG = 5 -- backpack, four bags and the reagent bag

---------------------------------------------------------------------------
-- Trainer: train all
---------------------------------------------------------------------------
local trainButton

-- Services the player can learn now (no new professions, they need a
-- confirmation) and their total cost.
local function Learnable()
	local list, total = {}, 0
	for index = 1, GetNumTrainerServices() do
		local _, serviceType = GetTrainerServiceInfo(index)
		if serviceType == "available" then
			local cost, isProfession = GetTrainerServiceCost(index)
			if not isProfession then
				list[#list + 1] = index
				total = total + ns.Number(cost, 0)
			end
		end
	end
	return list, total
end

-- Pet trainers charge training points, not money.
local function IsPetTrainer()
	return C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType
		and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
end

local function UpdateTrainButton()
	if not trainButton then
		return
	end
	if not Services.db.trainAll or IsPetTrainer() then
		trainButton:Hide()
		return
	end
	if not ClassTrainerFrame:IsVisible() then
		return
	end
	local list, total = Learnable()
	trainButton:Show()
	trainButton:SetEnabled(#list > 0)
	trainButton.Cost:SetText(#list > 0 and L.SERVICES_TRAIN_COST:format(GetMoneyString(total, true)) or "")
	trainButton.Cost:SetTextColor((total > GetMoney() and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
end

-- From the last entry to the first, so learning one does not move the
-- ones still to come; stops where the money runs out.
local function TrainAll()
	if IsPetTrainer() then
		return
	end
	local money = GetMoney()
	local list = Learnable()
	for i = #list, 1, -1 do
		local index = list[i]
		local cost = ns.Number(GetTrainerServiceCost(index), 0)
		if cost <= money then
			BuyTrainerService(index)
			money = money - cost
		end
	end
end

local function CreateTrainButton()
	local frame = ClassTrainerFrame
	local anchor = frame and frame.TrainButton
	if trainButton or not anchor then
		return
	end
	trainButton = CreateFrame("Button", nil, frame, "MagicButtonTemplate")
	trainButton:SetText(L.SERVICES_TRAIN_ALL)
	trainButton:SetWidth(ns.Number(trainButton:GetTextWidth(), 80) + 30)
	trainButton:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
	trainButton:SetScript("OnClick", TrainAll)
	trainButton.Cost = trainButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	trainButton.Cost:SetPoint("BOTTOMRIGHT", trainButton, "TOPRIGHT", 0, 3)
	if ClassTrainerFrame_Update then
		hooksecurefunc("ClassTrainerFrame_Update", UpdateTrainButton)
	end
	frame:HookScript("OnShow", UpdateTrainButton)
	UpdateTrainButton()
end

---------------------------------------------------------------------------
-- Bank: deposit reagents
---------------------------------------------------------------------------
local depositButton
local run -- { ticker, steps, wait = { bag, slot }, skip = { [itemID] = true }, moved = 0 }

local function IsReagent(info)
	local restock = ns:GetModule("Restock")
	-- Items on the restock list belong in the bags.
	if restock and restock.db and restock.db.enabled and restock.cdb.items[info.itemID] then
		return false
	end
	return select(17, C_Item.GetItemInfo(info.hyperlink or info.itemID)) == true
end

local function BankBags()
	local bags = {}
	if C_Bank.CanUseBank(Enum.BankType.Character) then
		for _, bag in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) or {}) do
			bags[#bags + 1] = bag
		end
	end
	return bags
end

-- Bank slot for the item: a stack with room (and how much fits), else an empty slot.
local function FindBankSlot(itemID, maxStack)
	local free
	for _, bag in ipairs(BankBags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				if info.itemID == itemID and not info.isLocked and info.stackCount < maxStack then
					return bag, slot, maxStack - info.stackCount
				end
			elseif not free then
				free = { bag, slot }
			end
		end
	end
	if free then
		return free[1], free[2], maxStack
	end
end

local function Finish()
	if run then
		run.ticker:Cancel()
		if run.moved > 0 then
			ns.Print(L.SERVICES_DEPOSITED, run.moved)
		end
		if run.full then
			ns.Print(L.SERVICES_BANK_FULL)
		end
		run = nil
	end
end

-- One move per call; nil when nothing is left to do.
local function DepositOne()
	for bag = BACKPACK_CONTAINER, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isLocked and not run.skip[info.itemID] and IsReagent(info) then
				local maxStack = ns.Number(C_Item.GetItemMaxStackSizeByID(info.itemID), 1)
				local targetBag, targetSlot, room = FindBankSlot(info.itemID, maxStack)
				if not targetBag then
					-- No room for this one; others may still stack onto partial stacks.
					run.skip[info.itemID] = true
					run.full = true
					return true
				end
				if room < info.stackCount then
					C_Container.SplitContainerItem(bag, slot, room)
				else
					C_Container.PickupContainerItem(bag, slot)
				end
				C_Container.PickupContainerItem(targetBag, targetSlot)
				if GetCursorInfo() then
					ClearCursor() -- not taken: back to where it came from
					run.skip[info.itemID] = true
				else
					run.moved = run.moved + 1
					run.wait = { targetBag, targetSlot }
				end
				return true
			end
		end
	end
end

local function Step()
	if not run then
		return
	end
	run.steps = run.steps + 1
	if InCombatLockdown() or not (BankFrame and BankFrame:IsShown()) or run.steps > MAX_STEPS then
		Finish()
		return
	end
	if GetCursorInfo() then
		return -- the player is holding something
	end
	if run.wait then
		local info = C_Container.GetContainerItemInfo(run.wait[1], run.wait[2])
		if info and info.isLocked then
			return
		end
		run.wait = nil
	end
	if not DepositOne() then
		Finish()
	end
end

local function DepositReagents()
	if run or InCombatLockdown() then
		return
	end
	run = { steps = 0, moved = 0, skip = {} }
	run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
end

local function CreateDepositButton()
	local panel = BankFrame and BankFrame.BankPanel
	if depositButton or not panel then
		return
	end
	depositButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	depositButton:SetText(L.SERVICES_DEPOSIT)
	depositButton:SetSize(ns.Number(depositButton:GetTextWidth(), 120) + 24, 22)
	local sort = panel.AutoSortButton
	if sort then
		depositButton:SetPoint("LEFT", sort, "RIGHT", 6, 0)
	else
		depositButton:SetPoint("TOPRIGHT", BankFrame, "TOPRIGHT", -30, -30)
	end
	depositButton:SetScript("OnClick", DepositReagents)
	depositButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.SERVICES_DEPOSIT)
		GameTooltip_AddNormalLine(GameTooltip, L.SERVICES_DEPOSIT_TOOLTIP)
		GameTooltip:Show()
	end)
	depositButton:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Services:Apply()
	if self.db.trainAll then
		ns.OnAddOnLoaded("Blizzard_TrainerUI", CreateTrainButton)
	end
	UpdateTrainButton()
	if self.db.depositReagents then
		CreateDepositButton()
	end
	if depositButton then
		depositButton:SetShown(self.db.depositReagents)
	end
end

function Services:OnLogin()
	self:Apply()
	self:RegisterEvent("TRAINER_UPDATE", UpdateTrainButton)
	self:RegisterEvent("PLAYER_MONEY", UpdateTrainButton)
	self:RegisterEvent("BANKFRAME_CLOSED", Finish)
end

function Services:OnOptionChanged()
	self:Apply()
end

Services.options = {
	{ key = "trainAll", type = "toggle", name = L.SERVICES_TRAIN_ALL_OPT, desc = L.SERVICES_TRAIN_ALL_DESC },
	{ key = "depositReagents", type = "toggle", name = L.SERVICES_DEPOSIT_OPT, desc = L.SERVICES_DEPOSIT_DESC },
}

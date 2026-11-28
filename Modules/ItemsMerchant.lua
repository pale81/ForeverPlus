-- Items: backpack money pickup, junk selling and repair at the merchant.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local BagExcludesJunk, HookBagFrameMenu, IsJunk, PostUpdateItems = P.BagExcludesJunk, P.HookBagFrameMenu, P.IsJunk, P.PostUpdateItems
local Report, SELL_BATCH, SELL_INTERVAL = P.Report, P.SELL_BATCH, P.SELL_INTERVAL

-- Money of the backpack: Blizzard's click opens the currency tab; here a click takes up coins again
-- (a window asks for the amount, then the coins hang on the cursor like an item), Shift + click
-- opens the currency tab as before. Own click areas lie on the coin buttons.
local moneyAreas = {}
local hookedMoney = setmetatable({}, { __mode = "k" })

-- "12g 5s 3k", "12 g", "5s" or a bare number (gold) in copper; nil when it cannot be read.
local function ParseMoney(text)
	local total, found = 0, false
	for number, unit in (text or ""):lower():gsub(",", "."):gmatch("(%d+%.?%d*)%s*([gsk]?)") do
		local value = tonumber(number)
		if value then
			found = true
			total = total + value * (unit == "s" and 100 or unit == "k" and 1 or 10000)
		end
	end
	return found and math.floor(total + 0.5) or nil
end

-- Own window for the amount, when Blizzard's window does not come up.
local function AskMoney()
	ns.ShowEditWindow("MoneyPickup", L.ITEMS_MONEY_TIP, "", ACCEPT, function(text)
		local copper = ParseMoney(text)
		if not copper or copper <= 0 then
			return
		end
		if copper > GetMoney() then
			ns.Print(L.ITEMS_MONEY_TOO_MUCH)
			return
		end
		local ok, err = pcall(PickupPlayerMoney, copper)
		if not ok then
			ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
		end
	end, L.ITEMS_MONEY_HINT)
end

local lastMoneyClick, characterWasShown = 0, false

local function MoneyClick(moneyFrame, afterBlizzard)
	-- A click can arrive twice (our area and the hook on the game's button): once is enough.
	if GetTime() - lastMoneyClick < 0.3 then
		return
	end
	lastMoneyClick = GetTime()
	if afterBlizzard then
		-- The game's own button already ran: Shift + click is meant to open the currency tab; otherwise that tab
		-- (opened by the click, not before it) closes again.
		if IsShiftKeyDown() then
			return
		end
		if CharacterFrame and CharacterFrame:IsShown() and not characterWasShown and not InCombatLockdown() then
			HideUIPanel(CharacterFrame)
		end
	end
	if GetCursorMoney() > 0 then
		local ok, err = pcall(DropCursorMoney)
		if not ok then
			ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
		end
		return
	end
	if IsShiftKeyDown() or not (MoneyInputFrame_OpenPopup and MoneyTypeInfo and MoneyTypeInfo.PLAYER) then
		-- Blizzard's own behaviour (currency tab).
		if MoneyInputFrame_OpenPopup then
			MoneyInputFrame_OpenPopup(moneyFrame)
		end
		return
	end
	-- A stand-in without the currency flag: Blizzard's window asks how much to take up.
	local ok, err = pcall(MoneyInputFrame_OpenPopup, { info = MoneyTypeInfo.PLAYER })
	if not ok then
		ns.Print(L.ITEMS_MONEY_ERROR, tostring(err))
	end
	-- If the window did not come up, the own one does.
	ns.After("Items: MoneyClick (timer)", 0.3, function()
		if not (StaticPopup_Visible and StaticPopup_Visible("PICKUP_MONEY")) then
			AskMoney()
		end
	end)
end

local function HookMoneyFrame(moneyFrame)
	if not moneyFrame then
		return
	end
	for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
		local button = moneyFrame[key]
		if button and not moneyAreas[button] then
			local area = CreateFrame("Button", nil, button)
			area:SetAllPoints(button)
			area:SetFrameLevel(button:GetFrameLevel() + 3)
			area:SetScript("OnClick", function()
				MoneyClick(moneyFrame)
			end)
			area:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(L.ITEMS_MONEY_TIP, 1, 1, 1)
				GameTooltip:AddLine(L.ITEMS_MONEY_TIP_PICK, nil, nil, nil, true)
				GameTooltip:AddLine(L.ITEMS_MONEY_TIP_CURRENCY, 0.7, 0.7, 0.7, true)
				GameTooltip:Show()
			end)
			area:SetScript("OnLeave", GameTooltip_Hide)
			moneyAreas[button] = area
		end
		if moneyAreas[button] then
			moneyAreas[button]:SetShown(Items.db.moneyPickup and true or false)
		end
		-- Safety net: if the click does not reach our area (covered, other geometry), the game's own button
		-- still tells us (hooks only add, nothing of the game's click is changed).
		if button and not hookedMoney[button] then
			hookedMoney[button] = true
			button:HookScript("OnMouseDown", function()
				characterWasShown = CharacterFrame and CharacterFrame:IsShown() or false
			end)
			for _, script in ipairs({ "OnClick", "OnMouseUp" }) do
				button:HookScript(script, function(_, mouseButton)
					if Items.db.moneyPickup and (mouseButton == nil or mouseButton == "LeftButton") then
						MoneyClick(moneyFrame, true)
					end
				end)
			end
		end
	end
end

-- /fp geld: without an amount the state of the click areas and the amount window; with an amount ("12g 5s")
-- the coins are taken up directly, which shows whether the game lets an addon do that.
function Items.MoneyCommand(argument)
	argument = strtrim(argument or "")
	if argument ~= "" then
		local copper = ParseMoney(argument)
		if not copper or copper <= 0 or copper > GetMoney() then
			ns.PrintAlways(L.ITEMS_MONEY_TOO_MUCH)
			return
		end
		local ok, err = pcall(PickupPlayerMoney, copper)
		ns.PrintAlways(ok and L.ITEMS_MONEY_TRIED or L.ITEMS_MONEY_ERROR, ok and GetCursorMoney() or tostring(err))
		return
	end
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		local moneyFrame = frame and frame.MoneyFrame
		if moneyFrame then
			for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
				local button = moneyFrame[key]
				local area = button and moneyAreas[button]
				ns.PrintAlways(L.ITEMS_MONEY_STATUS, frame:GetName() or "?", key, tostring(area ~= nil), tostring(area and area:IsShown()),
					tostring(area and area:IsMouseEnabled()), ns.Number(area and area:GetWidth(), 0), ns.Number(area and area:GetHeight(), 0),
					tostring(button and button:IsShown()), ns.Number(area and area:GetFrameLevel(), 0))
			end
		end
	end
	AskMoney()
end

local function HookContainerFrames()
	local frames = { ContainerFrameCombinedBags }
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		frames[#frames + 1] = frame
	end
	for _, frame in ipairs(frames) do
		HookBagFrameMenu(frame)
		HookMoneyFrame(frame.MoneyFrame)
		if frame and frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", ns.Measured("Items: bag update", PostUpdateItems))
		end
	end
end

---------------------------------------------------------------------------
-- Merchant: sell junk and repair
---------------------------------------------------------------------------
local soldValue
P.merchantOpen = false

local function StopSelling()
	if P.sellTicker then
		P.sellTicker:Cancel()
		P.sellTicker = nil
	end
	if soldValue and soldValue > 0 then
		Report("sellMessage", L.ITEMS_SOLD, GetMoneyString(soldValue, true))
	end
	soldValue = nil
end

local function SellBatch()
	-- MERCHANT_SHOW can arrive before the merchant window is shown.
	if not P.merchantOpen then
		StopSelling()
		return
	end
	local sold = 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local slots = BagExcludesJunk(bag) and 0 or ns.Number(C_Container.GetContainerNumSlots(bag), 0)
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsJunk(info, bag, slot) then
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
			Report("repairMessage", L.ITEMS_REPAIRED_GUILD, GetMoneyString(cost, true))
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems(false)
		Report("repairMessage", L.ITEMS_REPAIRED, GetMoneyString(cost, true))
	else
		Report("repairMessage", L.ITEMS_REPAIR_NO_MONEY)
	end
end

local function StartSelling()
	if P.sellTicker then
		return
	end
	soldValue = 0
	SellBatch()
	if soldValue then
		P.sellTicker = ns.NewTicker("Items: SellBatch", SELL_INTERVAL, SellBatch)
	end
end

-- Count and value of the junk in the bags (same rules as selling).
local function JunkValue()
	local count, value = 0, 0
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local slots = BagExcludesJunk(bag) and 0 or ns.Number(C_Container.GetContainerNumSlots(bag), 0)
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsJunk(info, bag, slot) then
				local price = select(11, C_Item.GetItemInfo(info.itemID))
				if price and price > 0 then
					count = count + 1
					value = value + price * info.stackCount
				end
			end
		end
	end
	return count, value
end

-- For the merchant list in the dialog bubble (Modules/Dialog.lua).
ns.MerchantTools = { SellJunk = StartSelling, JunkValue = JunkValue, Repair = Repair }

-- Blizzard's sell-junk button sells every grey item, including kept ones.
-- A button of our own lies on top and sells by the junk rules instead.

local function UpdateSellButton()
	-- MerchantFrame updates on every bag change, also with the window closed.
	if not P.sellButton or not P.sellButton:IsVisible() then
		return
	end
	local count = JunkValue()
	P.sellButton:GetParent().Icon:SetDesaturated(count == 0)
	P.sellButton:SetEnabled(count > 0)
end

local function CreateSellButton()
	local parent = _G.MerchantSellAllJunkButton
	if P.sellButton or not parent then
		return
	end
	P.sellButton = CreateFrame("Button", nil, parent)
	P.sellButton:SetAllPoints()
	P.sellButton:SetFrameLevel(parent:GetFrameLevel() + 2)
	P.sellButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	P.sellButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	-- Disabled buttons get no OnEnter; keep the tooltip anyway.
	P.sellButton:SetMotionScriptsWhileDisabled(true)
	P.sellButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	P.sellButton:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			if Items.db.bagMenu then
				Items:ShowMerchantMenu(self)
			end
		elseif P.merchantOpen then
			StartSelling()
		end
	end)
	P.sellButton:SetScript("OnEnter", function(self)
		local count, value = JunkValue()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(SELL_ALL_JUNK_ITEMS)
		GameTooltip:AddLine(L.ITEMS_SELL_BUTTON_TIP, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		if count > 0 then
			GameTooltip:AddDoubleLine(L.ITEMS_SELL_BUTTON_COUNT:format(count), GetMoneyString(value, true), 1, 1, 1, 1, 1, 1)
		end
		if Items.db.bagMenu then
			GameTooltip_AddInstructionLine(GameTooltip, L.ITEMS_MERCHANT_MENU_HINT)
		end
		GameTooltip:Show()
	end)
	P.sellButton:SetScript("OnLeave", GameTooltip_Hide)
	P.sellButton:SetScript("OnShow", UpdateSellButton)
	hooksecurefunc("MerchantFrame_Update", ns.Measured("Items: sell button", UpdateSellButton))
end

function Items:MERCHANT_SHOW()
	P.merchantOpen = true
	if self.db.autoRepair then
		Repair()
	end
	if self.db.autoSell then
		StartSelling()
	end
end

function Items:MERCHANT_CLOSED()
	P.merchantOpen = false
	StopSelling()
end

-- For the Items*.lua files loaded after this one.
P.CreateSellButton = CreateSellButton
P.HookContainerFrames = HookContainerFrames
P.moneyAreas = moneyAreas

-- Auction house: warns when an auction price per unit is not above the
-- merchant's price. Only reads Blizzard's data and adds own regions, so the
-- restricted buy and post functions stay untainted.
local _, ns = ...
local L = ns.L

local Auction = ns:NewModule("Auction", {
	title = L.AUCTION_TITLE,
	order = 4.5,
	defaults = {
		vendorWarning = true,
		vendorProfit = false,
		duration24 = true,
		startTab = "buy",
	},
})

local WARNING_ICON = [[Interface\DialogFrame\UI-Dialog-Icon-AlertNew]]
local AUCTION_HOUSE_CUT = 0.05

-- C_Item.GetItemInfo is costly and the result lists ask for the same items
-- again and again: a known merchant price is kept per item (an item whose data
-- is not loaded yet is asked again).
local vendorPriceCache = {}

local function VendorPrice(itemID)
	if not itemID then
		return nil
	end
	local cached = vendorPriceCache[itemID]
	if cached then
		return cached
	end
	local price = select(11, C_Item.GetItemInfo(itemID))
	if price then
		vendorPriceCache[itemID] = price
	end
	return price
end

-- True when the unit price is at or below what a merchant pays.
local function IsBelowVendor(itemID, unitPrice)
	local vendor = VendorPrice(itemID)
	return vendor and vendor > 0 and unitPrice and unitPrice > 0 and unitPrice <= vendor
end

local function NetAuctionPrice(grossPrice)
	return grossPrice and grossPrice > 0 and floor(grossPrice * (1 - AUCTION_HOUSE_CUT)) or nil
end

---------------------------------------------------------------------------
-- Result lists: warning icon in the price cell
---------------------------------------------------------------------------
local icons = setmetatable({}, { __mode = "k" })
local profitHooks = setmetatable({}, { __mode = "k" })

local function SetCellWarning(cell, show)
	local icon = icons[cell]
	if not icon then
		if not show then
			return
		end
		icon = cell:CreateTexture(nil, "OVERLAY")
		icon:SetTexture(WARNING_ICON)
		icon:SetSize(14, 14)
		icon:SetPoint("RIGHT", cell, "LEFT", 2, 0)
		icons[cell] = icon
	end
	icon:SetShown(show)
end

local function ItemIDOf(rowData)
	return rowData.itemID or (rowData.itemKey and rowData.itemKey.itemID)
end

local function ShowVendorProfit(cell)
	local profit = cell.foreverPlusVendorProfit
	if not profit then
		return
	end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L.AUCTION_VENDOR_PROFIT:format(GetMoneyString(profit.unit, true)),
		GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, true)
	if profit.total then
		GameTooltip:AddLine(L.AUCTION_VENDOR_PROFIT_TOTAL:format(profit.quantity, GetMoneyString(profit.total, true)),
			GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, true)
	end
	GameTooltip:Show()
end

local function SetCellProfit(cell, itemID, unitPrice, quantity)
	if not profitHooks[cell] then
		cell:HookScript("OnEnter", ShowVendorProfit)
		cell:HookScript("OnLeave", function(self)
			if GameTooltip:GetOwner() == self then
				GameTooltip_Hide()
			end
		end)
		profitHooks[cell] = true
	end
	cell.foreverPlusVendorProfit = nil
	if not Auction.db.vendorProfit or not itemID or not unitPrice then
		return
	end
	local vendor = VendorPrice(itemID)
	if not vendor or vendor <= unitPrice then
		return
	end
	local perItem = vendor - unitPrice
	quantity = quantity and quantity > 1 and quantity or nil
	cell.foreverPlusVendorProfit = {
		unit = perItem,
		quantity = quantity,
		total = quantity and perItem * quantity or nil,
	}
end

local function OnUnitPriceCell(cell, rowData)
	local show = Auction.db.vendorWarning and rowData and IsBelowVendor(ItemIDOf(rowData), rowData.unitPrice)
	SetCellWarning(cell, show and true or false)
	SetCellProfit(cell, rowData and ItemIDOf(rowData), rowData and rowData.unitPrice)
end

local function OnMinPriceCell(cell, rowData)
	local show = Auction.db.vendorWarning and rowData and rowData.totalQuantity ~= 0
		and IsBelowVendor(ItemIDOf(rowData), rowData.minPrice)
	SetCellWarning(cell, show and true or false)
	SetCellProfit(cell, rowData and ItemIDOf(rowData), rowData and rowData.minPrice)
end

local function OnBuyoutCell(cell, rowData)
	local show = false
	if rowData and rowData.buyoutAmount and not rowData.isVirtualEntry then
		local quantity = rowData.quantity and rowData.quantity > 0 and rowData.quantity or 1
		local unitPrice = floor(rowData.buyoutAmount / quantity)
		show = Auction.db.vendorWarning and IsBelowVendor(ItemIDOf(rowData), unitPrice)
		SetCellProfit(cell, ItemIDOf(rowData), unitPrice, quantity)
	else
		SetCellProfit(cell, rowData and ItemIDOf(rowData), nil)
	end
	SetCellWarning(cell, show and true or false)
end

---------------------------------------------------------------------------
-- Sell frames: warning text above the post button
---------------------------------------------------------------------------
local sellWarnings = {}
local sellVendorInfo = {}

local function UpdateSellWarning(frame, unitPrice)
	local text = sellWarnings[frame]
	if not text then
		text = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
		text:SetPoint("BOTTOM", frame.PostButton, "TOP", 0, 6)
		sellWarnings[frame] = text
	end
	local location = frame:GetItem()
	local itemID = location and C_Item.DoesItemExist(location) and C_Item.GetItemID(location)
	local vendor = VendorPrice(itemID)
	local quantity = 1
	if frame.GetQuantity then
		quantity = frame:GetQuantity() or 1
	elseif location and C_Item.DoesItemExist(location) then
		quantity = C_Item.GetStackCount(location) or 1
	end
	-- Item auctions enter a total stack price; commodity auctions enter a
	-- per-item price. Normalize both before comparing with the merchant value.
	local unitGross = unitPrice
	if frame.GetPrice and not frame.GetUnitPrice and quantity > 1 then
		unitGross = unitPrice and floor(unitPrice / quantity) or nil
	end
	local unitNet = NetAuctionPrice(unitGross)
	local unitProfit = vendor and unitNet and (unitNet - vendor) or nil
	if Auction.db.vendorWarning and vendor and unitProfit and unitProfit <= 0 then
		text:SetText(L.AUCTION_BELOW_VENDOR:format(GetMoneyString(vendor, true)))
		text:Show()
	else
		text:Hide()
	end

	local info = sellVendorInfo[frame]
	if not info then
		info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		info:SetPoint("BOTTOM", frame.PostButton, "TOP", 0, 25)
		sellVendorInfo[frame] = info
	end
	if (Auction.db.vendorProfit or Auction.db.vendorWarning) and vendor then
		local sign = unitProfit and (unitProfit >= 0 and "+" or "−") or ""
		local result = unitProfit and (sign .. GetMoneyString(math.abs(unitProfit), true)) or L.AUCTION_SELL_NO_PRICE
		info:SetText(L.AUCTION_SELL_VENDOR_INFO:format(GetMoneyString(vendor, true),
			unitNet and GetMoneyString(unitNet, true) or L.AUCTION_SELL_NO_PRICE, result))
		if unitProfit and unitProfit > 0 then
			info:SetTextColor(0.2, 1, 0.2)
		elseif unitProfit and unitProfit < 0 then
			info:SetTextColor(1, 0.25, 0.25)
		else
			info:SetTextColor(1, 0.82, 0)
		end
		info:Show()
	else
		info:Hide()
	end
end

local function HookSellFrames()
	local frame = AuctionHouseFrame
	if frame.CommoditiesSellFrame and frame.CommoditiesSellFrame.PostButton then
		hooksecurefunc(frame.CommoditiesSellFrame, "UpdatePostState", function(self)
			UpdateSellWarning(self, self:GetUnitPrice())
		end)
	end
	if frame.ItemSellFrame and frame.ItemSellFrame.PostButton then
		hooksecurefunc(frame.ItemSellFrame, "UpdatePostState", function(self)
			local _, buyout = self:GetPrice()
			UpdateSellWarning(self, buyout)
		end)
	end
end

---------------------------------------------------------------------------
-- Duration: Blizzard's sell frames start each session with the duration
-- stored in a CVar and keep the last choice afterwards. Only the CVar is set,
-- the frames themselves stay untouched.
---------------------------------------------------------------------------
local DURATION_CVAR = "auctionHouseDurationDropdown"

local function ApplyStartTab()
	if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
		return
	end
	local mode = Auction.db.startTab
	if mode == "sell" then
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.ItemSell)
	elseif mode == "auctions" then
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Auctions)
	else
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	end
end

function Auction:ApplyDuration()
	if not self.db.duration24 then
		return
	end
	for index, text in ipairs({ AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE }) do
		if type(text) == "string" and text:find("24", 1, true) then
			SetCVar(DURATION_CVAR, index)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Auction:OnLogin()
	self:ApplyDuration()
	ns.OnAddOnLoaded("Blizzard_AuctionHouseUI", function()
		-- Cells are created from these mixins after the addon loaded.
		local hooks = {
			AuctionHouseTableCellUnitPriceMixin = OnUnitPriceCell,
			AuctionHouseTableCellMinPriceMixin = OnMinPriceCell,
			AuctionHouseTableCellBuyoutMixin = OnBuyoutCell,
		}
		for mixinName, fn in pairs(hooks) do
			local mixin = _G[mixinName]
			if mixin and mixin.Populate then
				hooksecurefunc(mixin, "Populate", fn)
			end
		end
		if AuctionHouseFrame then
			HookSellFrames()
			hooksecurefunc(AuctionHouseFrame, "OnShow", ApplyStartTab)
		end
	end)
end

function Auction:OnOptionChanged(key)
	if key == "duration24" then
		self:ApplyDuration()
	elseif key == "startTab" then
		ApplyStartTab()
	end
end

Auction.options = {
	{ key = "vendorWarning", type = "toggle", name = L.AUCTION_VENDOR_WARNING, desc = L.AUCTION_VENDOR_WARNING_DESC },
	{ key = "vendorProfit", type = "toggle", name = L.AUCTION_VENDOR_PROFIT_OPTION, desc = L.AUCTION_VENDOR_PROFIT_DESC, new = true },
	{ key = "duration24", type = "toggle", name = L.AUCTION_DURATION_24, desc = L.AUCTION_DURATION_24_DESC },
	{ key = "startTab", type = "dropdown", name = L.AUCTION_START_TAB, desc = L.AUCTION_START_TAB_DESC, new = true, values = {
		{ "buy", L.AUCTION_TAB_BUY },
		{ "sell", L.AUCTION_TAB_SELL },
		{ "auctions", L.AUCTION_TAB_AUCTIONS },
	} },
}

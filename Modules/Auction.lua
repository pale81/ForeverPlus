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
	},
})

local WARNING_ICON = [[Interface\DialogFrame\UI-Dialog-Icon-AlertNew]]

local function VendorPrice(itemID)
	return itemID and select(11, C_Item.GetItemInfo(itemID)) or nil
end

-- True when the unit price is at or below what a merchant pays.
local function IsBelowVendor(itemID, unitPrice)
	local vendor = VendorPrice(itemID)
	return vendor and vendor > 0 and unitPrice and unitPrice > 0 and unitPrice <= vendor
end

---------------------------------------------------------------------------
-- Result lists: warning icon in the price cell
---------------------------------------------------------------------------
local icons = setmetatable({}, { __mode = "k" })

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

local function OnUnitPriceCell(cell, rowData)
	local show = Auction.db.vendorWarning and rowData and IsBelowVendor(ItemIDOf(rowData), rowData.unitPrice)
	SetCellWarning(cell, show and true or false)
end

local function OnMinPriceCell(cell, rowData)
	local show = Auction.db.vendorWarning and rowData and rowData.totalQuantity ~= 0
		and IsBelowVendor(ItemIDOf(rowData), rowData.minPrice)
	SetCellWarning(cell, show and true or false)
end

local function OnBuyoutCell(cell, rowData)
	local show = false
	if Auction.db.vendorWarning and rowData and rowData.buyoutAmount and not rowData.isVirtualEntry then
		local quantity = rowData.quantity and rowData.quantity > 0 and rowData.quantity or 1
		show = IsBelowVendor(ItemIDOf(rowData), floor(rowData.buyoutAmount / quantity))
	end
	SetCellWarning(cell, show and true or false)
end

---------------------------------------------------------------------------
-- Sell frames: warning text above the post button
---------------------------------------------------------------------------
local sellWarnings = {}

local function UpdateSellWarning(frame, unitPrice)
	local text = sellWarnings[frame]
	if not text then
		text = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
		text:SetPoint("BOTTOM", frame.PostButton, "TOP", 0, 6)
		sellWarnings[frame] = text
	end
	local location = frame:GetItem()
	local itemID = location and C_Item.DoesItemExist(location) and C_Item.GetItemID(location)
	if Auction.db.vendorWarning and IsBelowVendor(itemID, unitPrice) then
		text:SetText(L.AUCTION_BELOW_VENDOR:format(GetMoneyString(VendorPrice(itemID), true)))
		text:Show()
	else
		text:Hide()
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
-- Lifecycle
---------------------------------------------------------------------------
function Auction:OnLogin()
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
		end
	end)
end

Auction.options = {
	{ key = "vendorWarning", type = "toggle", name = L.AUCTION_VENDOR_WARNING, desc = L.AUCTION_VENDOR_WARNING_DESC },
}

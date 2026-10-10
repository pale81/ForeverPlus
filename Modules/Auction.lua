-- Auction house: warns when an auction price per unit is not above the
-- merchant's price, filters the buy list for offers below the merchant's
-- price and sets start tab and duration. Reads Blizzard's data and adds own
-- regions; only the filter swaps the buy list's data provider, and only while
-- it is switched on.
local _, ns = ...
local L = ns.L

local Auction = ns:NewModule("Auction", {
	title = L.AUCTION_TITLE,
	order = 4.5,
	defaults = {
		vendorWarning = true,
		vendorProfit = false,
		vendorBuyFilter = false,
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
-- Profit filter: the buy list shows only items whose cheapest offer costs
-- less than a merchant pays (buy at the auction, sell to the merchant; the
-- 5 % auction cut does not apply to a merchant sale). Blizzard's list keeps
-- its own results; only its data provider is swapped for a view onto them.
-- The view grows with the pages that arrive and asks for more pages while it
-- holds less than a screenful or the list is scrolled to its end.
---------------------------------------------------------------------------
local FILTER_WANTED = 30      -- profitable rows to collect before paging stops by itself
local FILTER_AUTO_PAGES = 40  -- pages requested by itself per search
local FILTER_NEAR_END = 8     -- rows before the end of the view that ask for more
local FILTER_RETRY = 2        -- seconds until a request without an answer is repeated

local filter = {
	list = {},         -- profitable rows in the order of Blizzard's list
	source = nil,      -- Blizzard's results table the view was built from
	scanned = 0,       -- rows of the source already judged
	requests = 0,      -- pages requested by itself for this search
	requestedAt = -1,  -- row count at the last request
	requestTime = 0,
	capped = false,    -- no further pages are requested by itself
	missing = {},      -- items whose merchant price was not known yet
}
local originalProvider

local function Profitable(rowData)
	if rowData.isVirtualEntry or rowData.totalQuantity == 0 then
		return false
	end
	local price = rowData.minPrice
	if type(price) ~= "number" or price <= 0 then
		return false
	end
	local itemID = ItemIDOf(rowData)
	local vendor = VendorPrice(itemID)
	if not vendor then
		if itemID and not filter.missing[itemID] then
			filter.missing[itemID] = true
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return false
	end
	return vendor > price
end

local function ResetFilter()
	filter.list, filter.scanned = {}, 0
	filter.requests, filter.requestedAt, filter.capped = 0, -1, false
end

-- Judges the rows that arrived since the last call.
local function SyncFilter(browseFrame)
	local rows = browseFrame.browseResults
	if type(rows) ~= "table" then
		return
	end
	if rows ~= filter.source or #rows < filter.scanned then
		-- a new search or a new sort order
		filter.source = rows
		ResetFilter()
	end
	for i = filter.scanned + 1, #rows do
		if Profitable(rows[i]) then
			filter.list[#filter.list + 1] = rows[i]
		end
	end
	filter.scanned = #rows
end

local function SetFilterProvider(browseFrame, on)
	local itemList = browseFrame and browseFrame.ItemList
	if not itemList or not itemList.SetDataProvider or not itemList.getNumEntries then
		return
	end
	if on then
		if not originalProvider then
			originalProvider = {
				itemList.searchStartedFunc, itemList.getEntry, itemList.getNumEntries, itemList.hasFullResultsFunc,
			}
		end
		itemList:SetDataProvider(originalProvider[1],
			function(index)
				SyncFilter(browseFrame)
				return filter.list[index]
			end,
			function()
				SyncFilter(browseFrame)
				return #filter.list
			end,
			-- with no profitable row yet the list shows "searching" until the search is complete or given up
			function()
				return filter.capped or C_AuctionHouse.HasFullBrowseResults()
			end)
	elseif originalProvider then
		itemList:SetDataProvider(unpack(originalProvider, 1, 4))
	end
end

-- Asks for the next page when the view is short or scrolled to its end.
local function PageFilter(browseFrame)
	if not Auction.db.vendorBuyFilter or not browseFrame:IsShown() or C_AuctionHouse.HasFullBrowseResults() then
		return
	end
	SyncFilter(browseFrame)
	local itemList = browseFrame.ItemList
	local shown = itemList and itemList.ScrollBox and itemList.ScrollBox.GetDataIndexEnd and itemList.ScrollBox:GetDataIndexEnd() or 0
	local atEnd = #filter.list > 0 and shown >= #filter.list - FILTER_NEAR_END
	local short = #filter.list < FILTER_WANTED
	if not (short or atEnd) then
		return
	end
	if short and not atEnd and filter.requests >= FILTER_AUTO_PAGES then
		if not filter.capped then
			filter.capped = true
			itemList:RefreshScrollFrame()
		end
		return
	end
	-- one request at a time: wait for new rows, repeat after a while
	local count = #browseFrame.browseResults
	if count == filter.requestedAt and GetTime() - filter.requestTime < FILTER_RETRY then
		return
	end
	filter.requestedAt, filter.requestTime = count, GetTime()
	filter.requests = filter.requests + 1
	C_AuctionHouse.RequestMoreBrowseResults()
end

local function ApplyBuyFilter()
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	if not browseFrame then
		return
	end
	local on = Auction.db.vendorBuyFilter
	filter.source = nil
	ResetFilter()
	SetFilterProvider(browseFrame, on)
	Auction:ToggleEvent("GET_ITEM_INFO_RECEIVED", on, function(_, itemID)
		-- a merchant price arrived: judge the rows again, in the same order
		if filter.missing[itemID] and not filter.rescan then
			filter.missing[itemID] = nil
			filter.rescan = true
			C_Timer.After(0.3, function()
				filter.rescan = nil
				ApplyBuyFilter()
			end)
		end
	end)
	if browseFrame.ItemList and browseFrame.ItemList.RefreshScrollFrame then
		browseFrame.ItemList:RefreshScrollFrame()
	end
	if on then
		PageFilter(browseFrame)
	end
end

Auction.Filter = { Profitable = Profitable, Sync = SyncFilter, Provider = SetFilterProvider, Page = PageFilter, Apply = ApplyBuyFilter }

local function HookBuyFilter()
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	if not browseFrame or not browseFrame.UpdateBrowseResults then
		return
	end
	-- Instance hooks: the frame was built from the mixins before this ran.
	hooksecurefunc(browseFrame, "UpdateBrowseResults", function(frame)
		PageFilter(frame)
	end)
	if browseFrame.ItemList and browseFrame.ItemList.CallRefreshCallback then
		hooksecurefunc(browseFrame.ItemList, "CallRefreshCallback", function()
			PageFilter(browseFrame)
		end)
	end
	if Auction.db.vendorBuyFilter then
		ApplyBuyFilter()
	end
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
	-- The filter's switch in Blizzard's search filter menu.
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_AUCTION_HOUSE_SEARCH_FILTER", function(_, rootDescription)
			rootDescription:CreateDivider()
			ns.CreateOptionCheckbox(rootDescription, L.AUCTION_VENDOR_BUY_FILTER, "Auction", "vendorBuyFilter",
				L.AUCTION_VENDOR_BUY_FILTER_DESC)
		end)
	end
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
			HookBuyFilter()
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
	elseif key == "vendorBuyFilter" then
		ApplyBuyFilter()
	end
end

Auction.options = {
	{ key = "vendorWarning", type = "toggle", name = L.AUCTION_VENDOR_WARNING, desc = L.AUCTION_VENDOR_WARNING_DESC },
	{ key = "vendorProfit", type = "toggle", name = L.AUCTION_VENDOR_PROFIT_OPTION, desc = L.AUCTION_VENDOR_PROFIT_DESC, new = true },
	{ key = "vendorBuyFilter", type = "toggle", name = L.AUCTION_VENDOR_BUY_FILTER, desc = L.AUCTION_VENDOR_BUY_FILTER_DESC, new = true },
	{ key = "duration24", type = "toggle", name = L.AUCTION_DURATION_24, desc = L.AUCTION_DURATION_24_DESC },
	{ key = "startTab", type = "dropdown", name = L.AUCTION_START_TAB, desc = L.AUCTION_START_TAB_DESC, new = true, values = {
		{ "buy", L.AUCTION_TAB_BUY },
		{ "sell", L.AUCTION_TAB_SELL },
		{ "auctions", L.AUCTION_TAB_AUCTIONS },
	} },
}

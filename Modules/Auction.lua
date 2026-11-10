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
		vendorMinMargin = 10,
		duration24 = true,
		startTab = "buy",
		craftPrices = true, -- merchant and last known auction price in the tooltip of what one can make
	},
	charDefaults = {
		crafted = {}, -- itemID -> true: made by a recipe this character knows (read when a profession is opened)
	},
})

local WARNING_ICON = [[Interface\DialogFrame\UI-Dialog-Icon-AlertNew]]
local AUCTION_HOUSE_CUT = 0.05

-- C_Item.GetItemInfo is costly and the result lists ask for the same items
-- again and again: a known merchant price is kept per item (an item whose data
-- is not loaded yet is asked again).
local vendorPriceCache = {}
local loadRequested = {}

-- nil while the item data is not loaded: that is asked for once and not
-- queried again and again (the query itself is the costly call).
local function VendorPrice(itemID)
	if not itemID then
		return nil
	end
	local cached = vendorPriceCache[itemID]
	if cached then
		return cached
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		if not loadRequested[itemID] then
			loadRequested[itemID] = true
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return nil
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
local FILTER_AUTO_PAGES = 20  -- pages requested by itself per search
local FILTER_AUTO_SECONDS = 10 -- seconds after which the search for the first hits is given up
local FILTER_NEAR_END = 8     -- rows before the end of the view that ask for more
local FILTER_RETRY = 2        -- seconds until a request without an answer is repeated
local FILTER_BATCH = 150      -- rows judged per call at most; the rest follows on the next frame
local FILTER_BUDGET = 3       -- milliseconds per call

local filter = {
	source = nil,      -- Blizzard's results table the view was built from
	verdict = {},      -- [row index] = true/false once judged
	judged = 0,        -- rows of the source judged so far (rows waiting for item data included)
	list = {},         -- profitable rows in the order of Blizzard's list
	rebuild = false,   -- the list must be rebuilt from the verdicts (a late verdict landed inside)
	waiting = {},      -- [item ID] = row indexes waiting for the merchant price
	requests = 0,      -- pages requested by itself for this search
	requestedAt = -1,  -- row count at the last request
	requestTime = 0,
	capped = false,    -- no further pages are requested by itself
}
local originalProvider

-- The merchant price; 0 for an item that is loaded but has none, nil until its data is there.
local function KnownVendorPrice(itemID)
	if not itemID then
		return 0
	end
	return VendorPrice(itemID) or (C_Item.IsItemDataCachedByID(itemID) and 0 or nil)
end

-- true/false, or nil while the merchant price of the item is not known.
local function Profitable(rowData)
	if rowData.isVirtualEntry or rowData.totalQuantity == 0 then
		return false
	end
	local price = rowData.minPrice
	if type(price) ~= "number" or price <= 0 then
		return false
	end
	local itemID = ItemIDOf(rowData)
	local vendor = KnownVendorPrice(itemID)
	if not vendor then
		return nil, itemID
	end
	local margin = (Auction.db.vendorMinMargin or 0) / 100
	return vendor > price and price <= vendor * (1 - margin)
end

local function ResetFilter()
	filter.source, filter.verdict, filter.judged, filter.list = nil, {}, 0, {}
	filter.rebuild, filter.waiting = false, {}
	filter.requests, filter.requestedAt, filter.capped = 0, -1, false
	filter.searchId, filter.timerStarted = (filter.searchId or 0) + 1, false
end

local refreshQueued = false
local UpdateFilterStatus -- below, after the paging

-- Redraws Blizzard's list from the view, a moment later so that several
-- changes (arriving item data, remaining rows) cost one redraw.
local function QueueRefresh(delay)
	if refreshQueued then
		return
	end
	refreshQueued = true
	ns.After("Auction: QueueRefresh (timer)", delay, function()
		refreshQueued = false
		local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
		local itemList = browseFrame and browseFrame.ItemList
		if Auction.db.vendorBuyFilter and itemList and itemList.RefreshScrollFrame then
			itemList:RefreshScrollFrame()
		end
		UpdateFilterStatus(browseFrame)
	end)
end

-- Judges the rows that arrived since the last call (a part of them per call).
local function SyncFilter(browseFrame)
	local rows = browseFrame.browseResults
	if type(rows) ~= "table" then
		return
	end
	if rows ~= filter.source then
		-- A new table: a new search (the query hook resets before) or Blizzard's
		-- copy of the same list; the verdicts stay when it is at least as long.
		if #rows < filter.judged then
			ResetFilter()
		end
		filter.source = rows
		filter.rebuild = true
	end
	local last = min(#rows, filter.judged + FILTER_BATCH)
	local started = debugprofilestop()
	for i = filter.judged + 1, last do
		if i % 10 == 0 and debugprofilestop() - started > FILTER_BUDGET then
			last = i - 1
			break
		end
		local verdict, itemID = Profitable(rows[i])
		if verdict == nil then
			local waiting = filter.waiting[itemID]
			if not waiting then
				waiting = {}
				filter.waiting[itemID] = waiting
			end
			waiting[#waiting + 1] = i
		else
			filter.verdict[i] = verdict
			if verdict and not filter.rebuild then
				filter.list[#filter.list + 1] = rows[i]
			end
		end
	end
	filter.judged = last
	if filter.rebuild then
		local list = {}
		for i = 1, last do
			if filter.verdict[i] then
				list[#list + 1] = rows[i]
			end
		end
		filter.list, filter.rebuild = list, false
	end
	if last < #rows then
		QueueRefresh(0)
	end
end

-- Item data arrived: the rows waiting for it are judged now.
local function OnItemInfo(_, _, itemID)
	local waiting = filter.waiting[itemID]
	local rows = filter.source
	if not waiting or not rows then
		return
	end
	filter.waiting[itemID] = nil
	local changed = false
	for _, i in ipairs(waiting) do
		local verdict = rows[i] and Profitable(rows[i]) or false
		filter.verdict[i] = verdict
		changed = changed or verdict
	end
	if changed then
		filter.rebuild = true
		QueueRefresh(0.25)
	end
end

local MeasuredSync = ns.Measured("Auction: filter sync", SyncFilter)

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
				return filter.list[index]
			end,
			function()
				MeasuredSync(browseFrame)
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

-- The line under the turning symbol while the filter has no hit yet: how far the search is, so a long search does
-- not look stuck; after it ended without hits, how much was searched.
function Auction.FilterStatusText(pages, hits, done)
	if hits > 0 then
		return nil
	elseif done then
		return L.AUCTION_FILTER_STATUS_DONE:format(pages)
	end
	return L.AUCTION_FILTER_STATUS:format(pages, FILTER_AUTO_PAGES, FILTER_AUTO_SECONDS)
end

function UpdateFilterStatus(browseFrame)
	local itemList = browseFrame and browseFrame.ItemList
	if not (itemList and itemList.CreateFontString) then
		return
	end
	local status = itemList.fpFilterStatus
	if not status then
		status = itemList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		status:SetPoint("TOP", itemList.LoadingSpinner or itemList, itemList.LoadingSpinner and "BOTTOM" or "CENTER", 0, -24)
		status:SetWidth(360)
		itemList.fpFilterStatus = status
	end
	local text = Auction.db.vendorBuyFilter and Auction.FilterStatusText(filter.requests + 1, #filter.list,
		filter.capped or C_AuctionHouse.HasFullBrowseResults())
	status:SetText(text or "")
	status:SetShown(text ~= nil)
end

-- Asks for the next page when the view is short or scrolled to its end.
local PageFilterStep

local function PageFilter(browseFrame)
	PageFilterStep(browseFrame)
	UpdateFilterStatus(browseFrame)
end

function PageFilterStep(browseFrame)
	if not Auction.db.vendorBuyFilter or not browseFrame:IsShown() or C_AuctionHouse.HasFullBrowseResults() then
		return
	end
	SyncFilter(browseFrame)
	if filter.judged < #browseFrame.browseResults then
		return -- the rest is judged first (a redraw is queued)
	end
	local itemList = browseFrame.ItemList
	local shown = itemList and itemList.ScrollBox and itemList.ScrollBox.GetDataIndexEnd and itemList.ScrollBox:GetDataIndexEnd() or 0
	local atEnd = #filter.list > 0 and shown >= #filter.list - FILTER_NEAR_END
	local short = #filter.list < FILTER_WANTED
	if not (short or atEnd) then
		return
	end
	if short and not atEnd then
		if not filter.timerStarted then
			-- the spinner must not turn for ever (a slow server, a search with few hits)
			filter.timerStarted = true
			local searchId = filter.searchId
			ns.After("Auction: PageFilter (timer)", FILTER_AUTO_SECONDS, function()
				if searchId == filter.searchId and not filter.capped and Auction.db.vendorBuyFilter then
					filter.capped = true
					QueueRefresh(0)
				end
			end)
		end
		if filter.capped or filter.requests >= FILTER_AUTO_PAGES then
			if not filter.capped then
				filter.capped = true
				QueueRefresh(0)
			end
			return
		end
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
	ResetFilter()
	SetFilterProvider(browseFrame, on)
	Auction:ToggleEvent("GET_ITEM_INFO_RECEIVED", on, OnItemInfo)
	if browseFrame.ItemList and browseFrame.ItemList.RefreshScrollFrame then
		browseFrame.ItemList:RefreshScrollFrame()
	end
	if on then
		PageFilter(browseFrame)
	else
		UpdateFilterStatus(browseFrame)
	end
end

Auction.Filter = { Profitable = Profitable, Sync = SyncFilter, Provider = SetFilterProvider, Page = PageFilter,
	Apply = ApplyBuyFilter, ItemInfo = OnItemInfo, State = filter }

local function HookBuyFilter()
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	if not browseFrame or not browseFrame.UpdateBrowseResults then
		return
	end
	-- Instance hooks: the frame was built from the mixins before this ran.
	hooksecurefunc(browseFrame, "UpdateBrowseResults", ns.Measured("Auction: filter paging", function(frame)
		PageFilter(frame)
	end))
	if browseFrame.ItemList and browseFrame.ItemList.CallRefreshCallback then
		hooksecurefunc(browseFrame.ItemList, "CallRefreshCallback", ns.Measured("Auction: filter paging", function()
			PageFilter(browseFrame)
		end))
	end
	-- Every query (new search, new sort order) starts the view and the page budget afresh.
	for _, name in ipairs({ "SendBrowseQuery", "SearchForFavorites" }) do
		if C_AuctionHouse[name] then
			hooksecurefunc(C_AuctionHouse, name, function()
				if Auction.db.vendorBuyFilter then
					ResetFilter()
				end
			end)
		end
	end
	if Auction.db.vendorBuyFilter then
		ApplyBuyFilter()
	end
end

---------------------------------------------------------------------------
-- Sell frames: merchant comparison and warning below the post button (above it sits the game's total price, which
-- the lines covered)
---------------------------------------------------------------------------
local sellVendorInfo = {}

-- What the sell frame shows below the post button: one large line (warning, profit or loss per item) and, for the
-- tooltip, the calculation behind it. nil when nothing is shown.
function Auction.SellSummary(vendor, unitGross, profitOn, warningOn)
	if not vendor or not (profitOn or warningOn) then
		return nil
	end
	local unitNet = NetAuctionPrice(unitGross)
	local profit = unitNet and (unitNet - vendor) or nil
	local money = function(value)
		return GetMoneyString(value, true)
	end
	local summary = { lines = {
		L.AUCTION_SELL_MERCHANT:format(money(vendor)),
		L.AUCTION_SELL_PRICE:format(unitGross and unitGross > 0 and money(unitGross) or L.AUCTION_SELL_NO_PRICE),
		L.AUCTION_SELL_NET:format(unitNet and money(unitNet) or L.AUCTION_SELL_NO_PRICE),
	} }
	if not profit then
		summary.text, summary.color = L.AUCTION_SELL_NO_PRICE, { 1, 0.82, 0 }
		return summary
	end
	local amount = (profit >= 0 and "+" or "−") .. money(math.abs(profit))
	summary.lines[#summary.lines + 1] = L.AUCTION_SELL_RESULT:format(amount)
	if warningOn and profit <= 0 then
		summary.text, summary.color = L.AUCTION_SELL_BELOW:format(amount), { 1, 0.25, 0.25 }
		summary.lines[#summary.lines + 1] = L.AUCTION_BELOW_VENDOR:format(money(vendor))
	elseif not profitOn then
		return nil
	elseif profit > 0 then
		summary.text, summary.color = L.AUCTION_SELL_PROFIT:format(amount), { 0.2, 1, 0.2 }
	elseif profit < 0 then
		summary.text, summary.color = L.AUCTION_SELL_LOSS:format(amount), { 1, 0.25, 0.25 }
	else
		summary.text, summary.color = L.AUCTION_SELL_PROFIT:format(amount), { 1, 0.82, 0 }
	end
	return summary
end

local function ShowSellTooltip(hover)
	local summary = hover.summary
	if not summary then
		return
	end
	GameTooltip:SetOwner(hover, "ANCHOR_TOP")
	GameTooltip:AddLine(summary.text, unpack(summary.color))
	for _, line in ipairs(summary.lines) do
		GameTooltip:AddLine(line, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function UpdateSellWarning(frame, unitPrice)
	local location = frame:GetItem()
	local itemID = location and C_Item.DoesItemExist(location) and C_Item.GetItemID(location)
	local vendor = VendorPrice(itemID)
	if vendor and vendor <= 0 then
		vendor = nil -- cannot be sold to a merchant
	end
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
	local info = sellVendorInfo[frame]
	if not info then
		info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		info:SetPoint("TOP", frame.PostButton, "BOTTOM", 0, -6)
		-- A font string takes no mouse: a frame over it carries the tooltip with the calculation.
		info.hover = CreateFrame("Frame", nil, frame)
		info.hover:SetAllPoints(info)
		info.hover:SetScript("OnEnter", ShowSellTooltip)
		info.hover:SetScript("OnLeave", GameTooltip_Hide)
		sellVendorInfo[frame] = info
	end
	local summary = Auction.SellSummary(vendor, unitGross, Auction.db.vendorProfit, Auction.db.vendorWarning)
	info.hover.summary = summary
	if summary then
		info:SetText(summary.text)
		info:SetTextColor(unpack(summary.color))
		info:Show()
		info.hover:Show()
		if GameTooltip:GetOwner() == info.hover then
			ShowSellTooltip(info.hover)
		end
	else
		info:Hide()
		info.hover:Hide()
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
-- Auction prices: the lowest buyout seen per item (per unit for stacks), with the time it was seen, kept for
-- the whole account. A new visit replaces what an older one found; within one visit the lowest price counts.
-- Shown in the tooltip of the items a recipe of this character makes, next to the merchant's price.
---------------------------------------------------------------------------
local VISIT = 1800 -- seconds within which prices count as one look at the auction house

-- store: itemID -> { price, time }. Returns whether the entry changed.
function Auction.RecordPrice(store, itemID, price, now)
	if not itemID or type(price) ~= "number" or price <= 0 then
		return false
	end
	local entry = store[itemID]
	if entry and now - entry[2] < VISIT and entry[1] <= price then
		return false
	end
	store[itemID] = { price, now }
	return true
end

-- How old a price is, in words.
function Auction.PriceAge(seconds)
	seconds = math.max(0, seconds)
	if seconds < 3600 then
		return L.AUCTION_AGE_NOW
	elseif seconds < 86400 then
		return L.AUCTION_AGE_HOURS:format(math.floor(seconds / 3600))
	end
	return L.AUCTION_AGE_DAYS:format(math.floor(seconds / 86400))
end

local function PriceStore()
	if type(ns.db.auctionPrices) ~= "table" then
		ns.db.auctionPrices = {}
	end
	return ns.db.auctionPrices
end

local function Plain(value)
	return not ns.Secret(value) and value or nil
end

local function OnBrowseResults()
	local store, now = PriceStore(), time()
	for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local key = result.itemKey
		Auction.RecordPrice(store, key and Plain(key.itemID), Plain(result.minPrice), now)
	end
end

local function OnCommodityResults(_, _, itemID)
	local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
	Auction.RecordPrice(PriceStore(), itemID, info and Plain(info.unitPrice), time())
end

local function OnItemResults(_, _, itemKey)
	if not itemKey then
		return
	end
	local lowest
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		local buyout = info and Plain(info.buyoutAmount)
		if buyout and buyout > 0 then
			local unit = math.floor(buyout / math.max(1, info.quantity or 1))
			lowest = lowest and math.min(lowest, unit) or unit
		end
	end
	Auction.RecordPrice(PriceStore(), Plain(itemKey.itemID), lowest, time())
end

-- What the recipes of this character make (a profession window lists them while it is open).
local lastCraftedRead = {} -- profession -> time of the last read (the list updates with every craft)

local function ReadCrafted()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
		return
	end
	local profession = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	local key = profession and Plain(profession.professionID) or "?"
	if lastCraftedRead[key] and GetTime() - lastCraftedRead[key] < 300 then
		return
	end
	lastCraftedRead[key] = GetTime()
	local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
	local crafted = Auction.cdb.crafted
	ns.RunSliced("Auction: crafted items", #ids, function(index)
		local recipeID = ids[index]
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned then
			local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			local itemID = schematic and schematic.outputItemID
			if itemID then
				crafted[itemID] = true
			end
		end
	end)
end

-- The tooltip line: merchant price and the last known auction price (or that none is known).
function Auction.CraftPriceText(vendor, entry, now)
	local parts = {}
	if vendor and vendor > 0 then
		parts[#parts + 1] = L.AUCTION_CRAFT_VENDOR:format(GetMoneyString(vendor, true))
	end
	if entry then
		parts[#parts + 1] = L.AUCTION_CRAFT_AUCTION:format(GetMoneyString(entry[1], true), Auction.PriceAge(now - entry[2]))
	else
		parts[#parts + 1] = L.AUCTION_CRAFT_UNKNOWN
	end
	return table.concat(parts, "  ")
end

-- Whether the price line goes into an item's tooltip: what this character makes (also with no price yet), and
-- every other item once an auction price of it is known (it is sold at the auction house). With "extra lines
-- only with Shift" only while Shift is held.
function Auction.ShowsPriceLine(crafted, known, extraShown)
	return extraShown and (crafted or known) and true or false
end

local function OnCraftTooltip(tooltip, data)
	if tooltip:IsForbidden() or not Auction.db.craftPrices then
		return
	end
	local itemID = data and Plain(data.id)
	if not itemID then
		return
	end
	local entry = PriceStore()[itemID]
	if not Auction.ShowsPriceLine(Auction.cdb.crafted[itemID], entry ~= nil, ns.ExtraInfoShown()) then
		return
	end
	tooltip:AddLine(Auction.CraftPriceText(VendorPrice(itemID), entry, time()), 1, 0.82, 0)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Auction:OnLogin()
	self:ApplyDuration()
	-- Auction prices are noted on every look (also with the tooltip line switched off: they are there when it is on).
	self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", ns.Measured("Auction: note prices", OnBrowseResults))
	self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", ns.Measured("Auction: note prices", OnBrowseResults))
	self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", ns.Measured("Auction: note prices", OnCommodityResults))
	self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", ns.Measured("Auction: note prices", OnItemResults))
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", ns.Measured("Auction: crafted items", ReadCrafted))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Auction: craft prices", OnCraftTooltip))
	-- The filter's switch in Blizzard's search filter menu.
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_AUCTION_HOUSE_SEARCH_FILTER", function(_, rootDescription)
			rootDescription:CreateDivider()
			ns.CreateOptionCheckbox(rootDescription, L.AUCTION_VENDOR_BUY_FILTER_MENU:format(Auction.db.vendorMinMargin or 0),
				"Auction", "vendorBuyFilter",
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
				hooksecurefunc(mixin, "Populate", ns.Measured("Auction: " .. mixinName, fn))
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
	elseif key == "vendorBuyFilter" or key == "vendorMinMargin" then
		ApplyBuyFilter()
	end
end

Auction.options = {
	{ key = "vendorWarning", type = "toggle", name = L.AUCTION_VENDOR_WARNING, desc = L.AUCTION_VENDOR_WARNING_DESC },
	{ key = "vendorProfit", type = "toggle", name = L.AUCTION_VENDOR_PROFIT_OPTION, desc = L.AUCTION_VENDOR_PROFIT_DESC, new = true },
	{ key = "vendorBuyFilter", type = "toggle", name = L.AUCTION_VENDOR_BUY_FILTER, desc = L.AUCTION_VENDOR_BUY_FILTER_DESC, new = true },
	{ key = "vendorMinMargin", type = "slider", name = L.AUCTION_VENDOR_MIN_MARGIN, desc = L.AUCTION_VENDOR_MIN_MARGIN_DESC, parent = "vendorBuyFilter",
		min = 0, max = 90, step = 1, format = function(v) return ("%d%%"):format(v) end },
	{ key = "craftPrices", type = "toggle", name = L.AUCTION_CRAFT_PRICES, desc = L.AUCTION_CRAFT_PRICES_DESC, new = true },
	{ key = "duration24", type = "toggle", name = L.AUCTION_DURATION_24, desc = L.AUCTION_DURATION_24_DESC },
	{ key = "startTab", type = "dropdown", name = L.AUCTION_START_TAB, desc = L.AUCTION_START_TAB_DESC, new = true, values = {
		{ "buy", L.AUCTION_TAB_BUY },
		{ "sell", L.AUCTION_TAB_SELL },
		{ "auctions", L.AUCTION_TAB_AUCTIONS },
	} },
}

-- Auction house: warns when an auction price per unit is not above the
-- merchant's price, filters the buy list for offers below the merchant's
-- price and sets start tab and duration. Reads Blizzard's data and adds own
-- regions; only the filter and the sorting swap the buy list's data provider,
-- and only while they are switched on.
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
		vendorQuickBuy = false,
		vendorQuickBuyQty = 1,
		vendorProfitSort = true, -- profitable offers with the highest merchant profit first
		scoreSort = false, -- the buy list by the rating of the items against what is worn
		scoreOnlyBetter = true, -- with the rating sort: only items better than what is worn
		scoreValueSort = false, -- with the rating sort: the most rating per gold first
		hideVendorItems = false, -- the buy list without goods a merchant sells freely for gold
		duration24 = true,
		startTab = "buy",
		craftPrices = true, -- merchant and last known auction price in the tooltip of what one can make
	},
	charDefaults = {
		crafted = {}, -- itemID -> true: made by a recipe this character knows (read when a profession is opened)
		vendorBuyPrices = {}, -- itemID -> observed unit purchase price at a merchant with unlimited stock
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
	cell.foreverPlusVendorProfit = nil
	if not Auction.db.vendorProfit or not itemID or not unitPrice then
		return
	end
	local vendor = VendorPrice(itemID)
	if not vendor or vendor <= unitPrice then
		return
	end
	if not profitHooks[cell] then
		cell:HookScript("OnEnter", ShowVendorProfit)
		cell:HookScript("OnLeave", function(self)
			if GameTooltip:GetOwner() == self then
				GameTooltip_Hide()
			end
		end)
		profitHooks[cell] = true
	end
	local perItem = vendor - unitPrice
	quantity = quantity and quantity > 1 and quantity or nil
	cell.foreverPlusVendorProfit = {
		unit = perItem,
		quantity = quantity,
		total = quantity and perItem * quantity or nil,
	}
end

-- Link of the item a result row shows: the auction's own link, else the sample link of its item key.
-- Nothing for pets and other rows that are no item.
function Auction.RowLink(rowData, itemKey)
	local link = rowData and rowData.itemLink
	if not link and itemKey and C_AuctionHouse and C_AuctionHouse.GetItemKeySampleLink then
		link = C_AuctionHouse.GetItemKeySampleLink(itemKey)
	end
	if type(link) == "string" and not ns.Secret(link) and link:find("item:", 1, true) then
		return link
	end
end

-- The upgrade arrow of bags and loot on the icon of an item in the browse list (grey if only the level is missing).
local itemArrows = setmetatable({}, { __mode = "k" })
-- With the list sorted by rating: the gain over what is worn at the right end of the name cell.
local gainLabels = setmetatable({}, { __mode = "k" })
local RowGain -- below, with the sorted view

-- The label text (with the rating per gold when that sorts) and whether it is a gain; nil for no rated equipment.
function Auction.GainText(gain, perGold)
	if type(gain) ~= "number" then
		return nil
	end
	local text = ("%+.1f"):format(gain)
	if perGold and Auction.db.scoreValueSort then
		local digits = perGold >= 10 and "%.0f" or perGold >= 0.1 and "%.1f" or "%.2f"
		text = text .. " · " .. L.AUCTION_PER_GOLD:format(digits:format(perGold))
	end
	return text, gain > 0.01
end

local function UpdateGainLabel(cell)
	local gain, perGold
	if not cell.Prefix and Auction.db.scoreSort then
		gain, perGold = RowGain(cell.rowData)
	end
	local text, better = Auction.GainText(gain, perGold)
	local label = gainLabels[cell]
	if not label and text then
		label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
		gainLabels[cell] = label
	end
	if not label then
		return
	end
	label:SetText(text or "")
	if better then
		label:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
	else
		label:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
	end
	-- a name that runs into the label wins: no number over its letters
	local room = cell:GetWidth() - (cell.Icon and cell.Icon:GetWidth() or 0) - 12
	local nameWidth = cell.Text and cell.Text:GetStringWidth() or 0
	label:SetShown(text ~= nil and nameWidth + label:GetStringWidth() <= room)
end

local function OnItemCell(cell, itemKey)
	local state = false
	-- Not in the list of one's own auctions (its cells have a prefix).
	if not cell.Prefix and cell.Icon and cell.Icon:IsShown() and ns.ItemLinkUpgradeState then
		local link = Auction.RowLink(cell.rowData, itemKey)
		state = link and ns.ItemLinkUpgradeState(link) or false
	end
	local arrow = itemArrows[cell]
	if not arrow and state then
		arrow = cell:CreateTexture(nil, "OVERLAY", nil, 7)
		arrow:SetAtlas("bags-greenarrow")
		-- on the icon: left of it lies outside the cell, where the list clips it
		arrow:SetSize(10, 10)
		arrow:SetPoint("TOPRIGHT", cell.Icon, "TOPRIGHT", 3, 3)
		itemArrows[cell] = arrow
	end
	if arrow then
		arrow:SetDesaturated(state == "later")
		arrow:SetShown(state and true or false)
	end
	UpdateGainLabel(cell)
end

local function OnItemCellCleared(cell)
	if itemArrows[cell] then
		itemArrows[cell]:Hide()
	end
	if gainLabels[cell] then
		gainLabels[cell]:Hide()
	end
end

local function OnUnitPriceCell(cell, rowData)
	local itemID = rowData and ItemIDOf(rowData)
	local show = Auction.db.vendorWarning and rowData and IsBelowVendor(itemID, rowData.unitPrice)
	SetCellWarning(cell, show and true or false)
	SetCellProfit(cell, itemID, rowData and rowData.unitPrice)
end

local function OnMinPriceCell(cell, rowData)
	local itemID = rowData and ItemIDOf(rowData)
	local show = Auction.db.vendorWarning and rowData and rowData.totalQuantity ~= 0
		and IsBelowVendor(itemID, rowData.minPrice)
	SetCellWarning(cell, show and true or false)
	SetCellProfit(cell, itemID, rowData and rowData.minPrice)
end

local function OnBuyoutCell(cell, rowData)
	local show = false
	if rowData and rowData.buyoutAmount and not rowData.isVirtualEntry then
		local quantity = rowData.quantity and rowData.quantity > 0 and rowData.quantity or 1
		local unitPrice = floor(rowData.buyoutAmount / quantity)
		local itemID = ItemIDOf(rowData)
		show = Auction.db.vendorWarning and IsBelowVendor(itemID, unitPrice)
		SetCellProfit(cell, itemID, unitPrice, quantity)
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
local FILTER_BATCH = 150      -- rows judged per slice at most; the rest follows on the next frame
local FILTER_BUDGET = 0.5     -- milliseconds per slice

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
	keys = {},         -- [row] = { rank, value, index }: place of a shown row in the view
	unrated = false,   -- a shown row waits for item data to be rated
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

-- The view is Blizzard's list filtered for profit or without merchant goods, and/or sorted by rating.
local function ViewActive()
	return Auction.db.vendorBuyFilter or Auction.db.hideVendorItems or (Auction.db.scoreSort and ns.ItemLinkRating ~= nil)
end

local function OnlyBetter()
	return Auction.db.scoreSort and Auction.db.scoreOnlyBetter and ns.ItemLinkRating ~= nil
end

-- The view leaves rows out: it pages by itself, since Blizzard asks for more only near the end of its own list.
local function Hiding()
	return Auction.db.vendorBuyFilter or Auction.db.hideVendorItems or OnlyBetter()
end

-- Goods a merchant sells for gold: the bundled list, the recipes of the recipe vendors (Data/Radar.lua) and what this
-- character saw at merchants.
local merchantGoods

function Auction.IsMerchantGood(itemID)
	if not itemID then
		return false
	end
	if not merchantGoods then
		merchantGoods = {}
		for _, id in ipairs(ns.VendorItemsEG or {}) do
			merchantGoods[id] = true
		end
		for _, vendor in pairs(ns.RadarData and ns.RadarData.vendors or {}) do
			for _, id in ipairs(type(vendor[5]) == "table" and vendor[5] or {}) do
				merchantGoods[id] = true
			end
		end
	end
	return merchantGoods[itemID] or (Auction.cdb and Auction.cdb.vendorBuyPrices[itemID] ~= nil) or false
end

-- Ranks by rating: better and wearable now, better once the level is reached, other equipment, nothing to compare,
-- rating not known yet (item data loading).
local RANK_UPGRADE, RANK_LATER, RANK_WORSE, RANK_NONE, RANK_LOADING = 1, 2, 3, 4, 5

-- Key of a rated row: by gain, or with the value sort by the item's rating per gold of the cheapest offer.
-- Also keeps gain and rating per gold for the label.
local function RatedKey(rank, gain, score, rowData, index)
	local perGold
	local price = rowData.minPrice
	if type(score) == "number" and type(price) == "number" and price > 0 then
		perGold = score / (price / 10000)
	end
	if Auction.db.scoreValueSort then
		return { rank, perGold or 0, index, gain, perGold }
	end
	return { rank, gain, index, gain, perGold }
end

-- Place of a shown row: rank first (lower first), then value (higher first), then Blizzard's order.
function Auction.SortKey(rowData, index)
	if Auction.db.scoreSort and ns.ItemLinkRating then
		local itemID = ItemIDOf(rowData)
		local link = Auction.RowLink(rowData, rowData.itemKey)
		if not link and itemID and C_Item.IsItemDataCachedByID(itemID) then
			link = select(2, C_Item.GetItemInfo(itemID))
		end
		local gain, block, score = ns.ItemLinkRating(link)
		if gain == nil or (not link and itemID and not C_Item.IsItemDataCachedByID(itemID)) then
			VendorPrice(itemID) -- asks for the item data once
			return { RANK_LOADING, 0, index }
		elseif not gain then
			return { RANK_NONE, 0, index }
		elseif block == "ok" then
			return RatedKey(RANK_UPGRADE, gain, score, rowData, index)
		elseif block == "level" then
			return RatedKey(RANK_LATER, gain, score, rowData, index)
		elseif block then
			return { RANK_NONE, 0, index } -- better, but never wearable (class, profession)
		end
		return RatedKey(RANK_WORSE, gain, score, rowData, index)
	elseif Auction.db.vendorBuyFilter and Auction.db.vendorProfitSort then
		return { 0, (KnownVendorPrice(ItemIDOf(rowData)) or 0) - rowData.minPrice, index }
	end
	return { 0, 0, index }
end

-- Gain and rating per gold of a rated row of the sorted view; nil for rows without a comparison or not rated yet.
function RowGain(rowData)
	local key = rowData and filter.keys[rowData]
	if key and (key[1] == RANK_UPGRADE or key[1] == RANK_LATER or key[1] == RANK_WORSE) then
		return key[4], key[5]
	end
end

local function Before(a, b)
	local ka, kb = filter.keys[a], filter.keys[b]
	if ka[1] ~= kb[1] then
		return ka[1] < kb[1]
	elseif ka[2] ~= kb[2] then
		return ka[2] > kb[2]
	end
	return ka[3] < kb[3]
end

-- Whether the view shows a row (nil while its merchant price is not known, with the item ID); notes its place.
local function Judge(rowData, index)
	if Auction.db.hideVendorItems and Auction.IsMerchantGood(ItemIDOf(rowData)) then
		return false
	end
	if Auction.db.vendorBuyFilter then
		local verdict, itemID = Profitable(rowData)
		if not verdict then
			return verdict, itemID
		end
	end
	local key = Auction.SortKey(rowData, index)
	filter.keys[rowData] = key
	filter.unrated = filter.unrated or key[1] == RANK_LOADING
	return true
end

-- A row that passed the filters, if only better items are wanted: rated better than what is worn.
local function Visible(rowData)
	if not OnlyBetter() then
		return true
	end
	local key = filter.keys[rowData]
	return key ~= nil and key[1] <= RANK_LATER
end

-- Adds a shown row at its place in the sorted view.
local function Insert(list, rowData)
	local low, high = 1, #list + 1
	while low < high do
		local mid = floor((low + high) / 2)
		if Before(rowData, list[mid]) then
			high = mid
		else
			low = mid + 1
		end
	end
	tinsert(list, low, rowData)
end

local function ResetFilter()
	filter.source, filter.verdict, filter.judged, filter.list = nil, {}, 0, {}
	filter.rebuild, filter.waiting, filter.keys, filter.unrated = false, {}, {}, false
	filter.scanPending = false
	filter.requests, filter.requestedAt, filter.capped = 0, -1, false
	filter.searchId, filter.timerStarted = (filter.searchId or 0) + 1, false
end

local QueueRefresh -- below, after the paging

-- Judges the rows that arrived since the last call (a part of them per call).
local function SyncFilter(browseFrame, applyLateVerdicts)
	local rows = browseFrame.browseResults
	if type(rows) ~= "table" then
		return
	end
	if rows ~= filter.source then
		-- Blizzard replaces the table on an update and appends to it on paging.
		-- Verdicts and waiting indexes belong to the original table.
		if #rows < filter.judged then
			ResetFilter()
		else
			filter.verdict, filter.waiting, filter.list, filter.judged = {}, {}, {}, 0
			filter.rebuild, filter.scanPending, filter.keys, filter.unrated = false, false, {}, false
		end
		filter.source = rows
	end
	if not filter.scanPending and filter.judged < #rows then
		local last = min(#rows, filter.judged + FILTER_BATCH)
		local deadline = debugprofilestop() + FILTER_BUDGET
		for i = filter.judged + 1, last do
			local verdict, itemID = Judge(rows[i], i)
			if verdict == nil then
				local waiting = filter.waiting[itemID]
				if not waiting then
					waiting = {}
					filter.waiting[itemID] = waiting
				end
				waiting[#waiting + 1] = i
			else
				filter.verdict[i] = verdict
				if verdict and not filter.rebuild and Visible(rows[i]) then
					Insert(filter.list, rows[i])
				end
			end
			if debugprofilestop() >= deadline then
				last = i
				break
			end
		end
		filter.judged = last
	end
	if filter.rebuild then
		if applyLateVerdicts then
			local list = {}
			local rerate = filter.unrated
			filter.unrated = false
			for i = 1, filter.judged do
				if filter.verdict[i] then
					local key = filter.keys[rows[i]]
					if rerate and key[1] == RANK_LOADING then
						key = Auction.SortKey(rows[i], i)
						filter.keys[rows[i]] = key
						filter.unrated = filter.unrated or key[1] == RANK_LOADING
					end
					if Visible(rows[i]) then
						list[#list + 1] = rows[i]
					end
				end
			end
			table.sort(list, Before)
			filter.list, filter.rebuild = list, false
		else
			QueueRefresh(0.25)
		end
	end
	if filter.judged < #rows and not filter.scanPending then
		filter.scanPending = true
		QueueRefresh(0)
	end
end

-- Item data arrived: the rows waiting for it are judged now.
local function OnItemInfo(_, _, itemID)
	local waiting = filter.waiting[itemID]
	local rows = filter.source
	if not rows or not (waiting or filter.unrated) then
		return
	end
	filter.waiting[itemID] = nil
	-- an unrated row may wait for this item or for a worn one: the rebuild rates them again
	local changed = filter.unrated
	for _, i in ipairs(waiting or {}) do
		local verdict = rows[i] and Judge(rows[i], i) or false
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
function Auction.FilterStatusText(pages, hits, done, other)
	if hits > 0 then
		return nil
	elseif done then
		return (other and L.AUCTION_FILTER_STATUS_OTHER_DONE or L.AUCTION_FILTER_STATUS_DONE):format(pages)
	end
	return (other and L.AUCTION_FILTER_STATUS_OTHER or L.AUCTION_FILTER_STATUS):format(pages, FILTER_AUTO_PAGES,
		FILTER_AUTO_SECONDS)
end

local function UpdateFilterStatus(browseFrame)
	local itemList = browseFrame and browseFrame.ItemList
	if not (itemList and itemList.CreateFontString) then
		return
	end
	local status = itemList.fpFilterStatus
	local text = Hiding() and Auction.FilterStatusText(filter.requests + 1, #filter.list,
		filter.capped or C_AuctionHouse.HasFullBrowseResults(), not Auction.db.vendorBuyFilter) or nil
	if itemList.fpFilterStatusText == text then
		return
	end
	itemList.fpFilterStatusText = text
	if not status then
		status = itemList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		status:SetPoint("TOP", itemList.LoadingSpinner or itemList, itemList.LoadingSpinner and "BOTTOM" or "CENTER", 0, -24)
		status:SetWidth(360)
		itemList.fpFilterStatus = status
	end
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
	if not Hiding() or not browseFrame:IsShown() or C_AuctionHouse.HasFullBrowseResults() then
		return
	end
	SyncFilter(browseFrame)
	if not filter.source or filter.judged < #filter.source then
		return -- the next slice finishes judging the rows first
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
				if searchId == filter.searchId and not filter.capped and Hiding() then
					filter.capped = true
					QueueRefresh(0, #filter.list == 0)
				end
			end)
		end
		if filter.capped or filter.requests >= FILTER_AUTO_PAGES then
			if not filter.capped then
				filter.capped = true
				QueueRefresh(0, #filter.list == 0)
			end
			return
		end
	end
	-- one request at a time: wait for new rows, repeat after a while
	local count = #filter.source
	if count == filter.requestedAt and GetTime() - filter.requestTime < FILTER_RETRY then
		return
	end
	filter.requestedAt, filter.requestTime = count, GetTime()
	filter.requests = filter.requests + 1
	C_AuctionHouse.RequestMoreBrowseResults()
end

local refreshQueued, refreshNeeded = false, false

-- Continue the scan independently of Blizzard's redraw. A slice with no new
-- hits can keep paging without rebuilding the scroll box.
function QueueRefresh(delay, redraw)
	refreshNeeded = refreshNeeded or redraw
	if refreshQueued then
		return
	end
	refreshQueued = true
	ns.After("Auction: QueueRefresh (timer)", delay, function()
		refreshQueued = false
		local needsRedraw = refreshNeeded
		refreshNeeded = false
		filter.scanPending = false
		local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
		if not (ViewActive() and browseFrame) then
			return
		end
		if not browseFrame:IsShown() then
			UpdateFilterStatus(browseFrame)
			return
		end
		local list, count = filter.list, #filter.list
		SyncFilter(browseFrame, true)
		local itemList = browseFrame.ItemList
		-- If Blizzard has already scheduled a refresh, let it pick up the new view.
		if itemList and itemList.RefreshScrollFrame and not itemList.scrollFrameDirty
			and (needsRedraw or list ~= filter.list or count ~= #filter.list) then
			itemList:RefreshScrollFrame()
		end
		PageFilter(browseFrame)
	end)
end

local function ApplyBuyFilter()
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	if not browseFrame then
		return
	end
	local on = ViewActive()
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
	Apply = ApplyBuyFilter, ItemInfo = OnItemInfo, State = filter, ItemCell = OnItemCell }

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
				if ViewActive() then
					ResetFilter()
				end
			end)
		end
	end
	if ViewActive() then
		ApplyBuyFilter()
	end
end

---------------------------------------------------------------------------
-- Quick buy: a button in the price cell of a profitable commodity row starts Blizzard's own purchase for the
-- cheapest offer (the buy dialog with its confirmation stays; it shows the real total). One click, one purchase.
-- Item auctions (gear) need an auction ID from a search of their own: their row opens Blizzard's buy view as before.
---------------------------------------------------------------------------
-- itemID, quantity, unit price and expected total of a quick buy; nil for a row that cannot be bought this way.
function Auction.QuickBuyPlan(rowData, quantity)
	if not rowData or rowData.isVirtualEntry then
		return nil
	end
	local unitPrice, available, itemID = rowData.minPrice, rowData.totalQuantity, ItemIDOf(rowData)
	if not itemID or type(unitPrice) ~= "number" or unitPrice <= 0 or type(available) ~= "number" or available <= 0 then
		return nil
	end
	local count = min(max(floor(quantity or 1), 1), available)
	return itemID, count, unitPrice, unitPrice * count
end

local quickButtons = setmetatable({}, { __mode = "k" })

local function ShowQuickBuyTooltip(button)
	local row = button.rowData
	local itemID, count, unitPrice = Auction.QuickBuyPlan(row, Auction.db.vendorQuickBuyQty)
	if not itemID then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L.AUCTION_QUICK_BUY_TOOLTIP:format(count, GetMoneyString(unitPrice, true)), 1, 1, 1, true)
	local vendor = VendorPrice(itemID)
	if vendor and vendor > unitPrice then
		GameTooltip:AddLine(L.AUCTION_QUICK_BUY_PROFIT:format(GetMoneyString((vendor - unitPrice) * count, true)),
			GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, true)
	end
	GameTooltip:Show()
end

-- Only from a real click: the purchase functions need a hardware event.
local function OnQuickBuyClick(button)
	local row, frame = button.rowData, AuctionHouseFrame
	if not row or not frame or not frame.StartCommoditiesPurchase or not Profitable(row) then
		return
	end
	local itemID, count, unitPrice, total = Auction.QuickBuyPlan(row, Auction.db.vendorQuickBuyQty)
	if itemID then
		frame:StartCommoditiesPurchase(itemID, count, unitPrice, total)
	end
end

local function IsCommodityRow(rowData)
	local info = rowData.itemKey and C_AuctionHouse.GetItemKeyInfo(rowData.itemKey)
	return info and info.isCommodity and true or false
end

local function OnQuickBuyCell(cell, rowData)
	local button = quickButtons[cell]
	local show = Auction.db.vendorBuyFilter and Auction.db.vendorQuickBuy and rowData
		and Auction.QuickBuyPlan(rowData, 1) ~= nil and IsCommodityRow(rowData)
	if not button then
		if not show then
			return
		end
		button = CreateFrame("Button", nil, cell, "UIPanelButtonTemplate")
		button:SetSize(52, 18)
		button:SetPoint("LEFT", cell, "LEFT", 0, 0)
		button:SetText(L.AUCTION_QUICK_BUY)
		button:SetScript("OnClick", OnQuickBuyClick)
		button:SetScript("OnEnter", ShowQuickBuyTooltip)
		button:SetScript("OnLeave", GameTooltip_Hide)
		quickButtons[cell] = button
	end
	button.rowData = show and rowData or nil
	button:SetShown(show and true or false)
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

function Auction.ReagentPrice(itemID)
	local store = ns.db.auctionPrices
	local entry = type(store) == "table" and store[itemID]
	local auction = type(entry) == "table" and ns.Number(entry[1])
	local vendor = ns.Number(Auction.cdb.vendorBuyPrices[itemID])
	if auction and auction > 0 then
		return vendor and math.min(auction, vendor) or auction
	end
	return vendor
end

local function RecordMerchantPrices()
	local prices = Auction.cdb.vendorBuyPrices
	for index = 1, GetMerchantNumItems() or 0 do
		local info = C_MerchantFrame.GetItemInfo(index)
		if info and info.isPurchasable and not info.hasExtendedCost and not info.currencyID and info.numAvailable == -1 then
			local price, count = ns.Number(info.price, 0), ns.Number(info.stackCount, 0)
			if price > 0 and count > 0 then
				local itemID = ns.Number(GetMerchantItemID(index))
				if itemID and itemID > 0 then
					local unit = price / count
					prices[itemID] = math.min(prices[itemID] or unit, unit)
				end
			end
		end
	end
end

local function Plain(value)
	return not ns.Secret(value) and value or nil
end

local PRICE_BATCH = 150
local PRICE_BUDGET = 0.4 -- milliseconds per slice
local priceBatches, firstBatch, lastBatch = {}, 1, 0

-- Keep snapshots in event order, even if the next search starts before the
-- first one has been saved. At logout, finish before saved variables are written.
local function SaveQueuedPrices(flush)
	if firstBatch > lastBatch then
		return
	end
	local deadline = not flush and debugprofilestop() + PRICE_BUDGET
	local store = PriceStore()
	local remaining = PRICE_BATCH
	while true do
		local batch = priceBatches[firstBatch]
		local itemID, price = batch.read(batch.index)
		Auction.RecordPrice(store, itemID, price, batch.now)
		if batch.index < batch.count then
			batch.index = batch.index + 1
		else
			priceBatches[firstBatch] = nil
			if firstBatch == lastBatch then
				firstBatch, lastBatch = 1, 0
				return
			end
			firstBatch = firstBatch + 1
		end
		if not flush then
			remaining = remaining - 1
			if remaining == 0 or debugprofilestop() >= deadline then
				return
			end
		end
	end
end

local function SavePriceSlice()
	SaveQueuedPrices(false)
	if firstBatch <= lastBatch then
		ns.After("Auction: note prices", 0, SavePriceSlice)
	end
end

local function QueuePrices(count, read)
	if count == 0 then
		return
	end
	lastBatch = lastBatch + 1
	priceBatches[lastBatch] = { count = count, read = read, index = 1, now = time() }
	if firstBatch == lastBatch then
		ns.After("Auction: note prices", 0, SavePriceSlice)
	end
end

local function QueueBrowsePrices(rows)
	if rows then
		QueuePrices(#rows, function(index)
			local result = rows[index]
			local key = result.itemKey
			return key and Plain(key.itemID), Plain(result.minPrice)
		end)
	end
end

local function OnBrowseResults(_, _, addedResults)
	QueueBrowsePrices(addedResults or C_AuctionHouse.GetBrowseResults())
end

local function HookBrowsePrices(frame)
	if not (frame and frame.UpdateBrowseResults) then
		return
	end
	-- Blizzard already fetched the full snapshot, or received just the new page.
	hooksecurefunc(frame, "UpdateBrowseResults", ns.Measured("Auction: queue browse prices", function(browseFrame, addedResults)
		QueueBrowsePrices(addedResults or browseFrame.browseResults)
	end))
	Auction:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	Auction:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
end

local function QueuePrice(itemID, price)
	if itemID and price then
		QueuePrices(1, function() return itemID, price end)
	end
end

local function OnCommodityResults(_, _, itemID)
	local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
	QueuePrice(Plain(itemID), info and Plain(info.unitPrice))
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
	QueuePrice(Plain(itemKey.itemID), lowest)
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
	self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseResults)
	self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseResults)
	self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
	self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
	self:RegisterEvent("PLAYER_LOGOUT", function() SaveQueuedPrices(true) end)
	local recordMerchant = ns.Measured("Auction: merchant prices", RecordMerchantPrices)
	self:RegisterEvent("MERCHANT_SHOW", recordMerchant)
	self:RegisterEvent("MERCHANT_UPDATE", recordMerchant)
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", ns.Measured("Auction: crafted items", ReadCrafted))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Auction: craft prices", OnCraftTooltip))
	-- The filter's switch in Blizzard's search filter menu.
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_AUCTION_HOUSE_SEARCH_FILTER", function(_, rootDescription)
			rootDescription:CreateDivider()
			ns.CreateOptionCheckbox(rootDescription, L.AUCTION_VENDOR_BUY_FILTER_MENU:format(Auction.db.vendorMinMargin or 0),
				"Auction", "vendorBuyFilter",
				L.AUCTION_VENDOR_BUY_FILTER_DESC)
			if ns.ItemLinkRating then
				ns.CreateOptionCheckbox(rootDescription, L.AUCTION_SCORE_SORT, "Auction", "scoreSort", L.AUCTION_SCORE_SORT_DESC)
			end
			if ns.ItemLinkRating then
				ns.CreateOptionCheckbox(rootDescription, L.AUCTION_SCORE_ONLY_BETTER, "Auction", "scoreOnlyBetter",
					L.AUCTION_SCORE_ONLY_BETTER_DESC)
				ns.CreateOptionCheckbox(rootDescription, L.AUCTION_SCORE_VALUE_SORT, "Auction", "scoreValueSort",
					L.AUCTION_SCORE_VALUE_SORT_DESC)
			end
			ns.CreateOptionCheckbox(rootDescription, L.AUCTION_HIDE_VENDOR_ITEMS, "Auction", "hideVendorItems",
				L.AUCTION_HIDE_VENDOR_ITEMS_DESC)
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
		local minPriceCell = _G.AuctionHouseTableCellMinPriceMixin
		if minPriceCell and minPriceCell.Populate then
			hooksecurefunc(minPriceCell, "Populate", ns.Measured("Auction: quick buy", OnQuickBuyCell))
		end
		local itemCell = _G.AuctionHouseTableCellItemDisplayMixin
		if itemCell and itemCell.UpdateDisplay then
			hooksecurefunc(itemCell, "UpdateDisplay", ns.Measured("Auction: upgrade arrow", OnItemCell))
			if itemCell.ClearDisplay then
				hooksecurefunc(itemCell, "ClearDisplay", ns.Measured("Auction: upgrade arrow", OnItemCellCleared))
			end
		end
		if AuctionHouseFrame then
			HookBrowsePrices(AuctionHouseFrame.BrowseResultsFrame)
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
	elseif key == "vendorBuyFilter" or key == "vendorMinMargin" or key == "vendorProfitSort" or key == "scoreSort"
		or key == "hideVendorItems" or key == "scoreOnlyBetter" or key == "scoreValueSort" then
		ApplyBuyFilter()
	elseif key == "vendorQuickBuy" then
		local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
		if browseFrame and browseFrame.ItemList and browseFrame.ItemList.RefreshScrollFrame then
			browseFrame.ItemList:RefreshScrollFrame()
		end
	end
end

Auction.options = {
	{ key = "vendorWarning", type = "toggle", name = L.AUCTION_VENDOR_WARNING, desc = L.AUCTION_VENDOR_WARNING_DESC },
	{ key = "vendorProfit", type = "toggle", name = L.AUCTION_VENDOR_PROFIT_OPTION, desc = L.AUCTION_VENDOR_PROFIT_DESC, new = true },
	{ key = "vendorBuyFilter", type = "toggle", name = L.AUCTION_VENDOR_BUY_FILTER, desc = L.AUCTION_VENDOR_BUY_FILTER_DESC, new = true },
	{ key = "vendorMinMargin", type = "slider", name = L.AUCTION_VENDOR_MIN_MARGIN, desc = L.AUCTION_VENDOR_MIN_MARGIN_DESC, parent = "vendorBuyFilter",
		min = 0, max = 90, step = 1, format = function(v) return ("%d%%"):format(v) end },
	{ key = "vendorProfitSort", type = "toggle", name = L.AUCTION_PROFIT_SORT, desc = L.AUCTION_PROFIT_SORT_DESC, parent = "vendorBuyFilter", new = true },
	{ key = "vendorQuickBuy", type = "toggle", name = L.AUCTION_QUICK_BUY_OPTION, desc = L.AUCTION_QUICK_BUY_DESC, parent = "vendorBuyFilter", new = true },
	{ key = "vendorQuickBuyQty", type = "slider", name = L.AUCTION_QUICK_BUY_QTY, desc = L.AUCTION_QUICK_BUY_QTY_DESC, parent = "vendorQuickBuy",
		min = 1, max = 200, step = 1 },
	{ key = "scoreSort", type = "toggle", name = L.AUCTION_SCORE_SORT, desc = L.AUCTION_SCORE_SORT_DESC, new = true },
	{ key = "scoreOnlyBetter", type = "toggle", name = L.AUCTION_SCORE_ONLY_BETTER, desc = L.AUCTION_SCORE_ONLY_BETTER_DESC,
		parent = "scoreSort", new = true },
	{ key = "scoreValueSort", type = "toggle", name = L.AUCTION_SCORE_VALUE_SORT, desc = L.AUCTION_SCORE_VALUE_SORT_DESC,
		parent = "scoreSort", new = true },
	{ key = "hideVendorItems", type = "toggle", name = L.AUCTION_HIDE_VENDOR_ITEMS, desc = L.AUCTION_HIDE_VENDOR_ITEMS_DESC, new = true },
	{ key = "craftPrices", type = "toggle", name = L.AUCTION_CRAFT_PRICES, desc = L.AUCTION_CRAFT_PRICES_DESC, new = true },
	{ key = "duration24", type = "toggle", name = L.AUCTION_DURATION_24, desc = L.AUCTION_DURATION_24_DESC },
	{ key = "startTab", type = "dropdown", name = L.AUCTION_START_TAB, desc = L.AUCTION_START_TAB_DESC, new = true, values = {
		{ "buy", L.AUCTION_TAB_BUY },
		{ "sell", L.AUCTION_TAB_SELL },
		{ "auctions", L.AUCTION_TAB_AUCTIONS },
	} },
}

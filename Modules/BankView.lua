-- The character bank can be inspected from the bags after a bank visit.
local _, ns = ...
local L = ns.L

local BankView = ns:NewModule("BankView", {
	title = L.BANKVIEW_TITLE,
	defaults = { enabled = true },
	charDefaults = {},
	options = {
		{ key = "enabled", type = "toggle", name = L.BANKVIEW_ENABLE, desc = L.BANKVIEW_ENABLE_DESC },
	},
})

local bankType = Enum.BankType.Character
local firstBankBag, lastBankBag = Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9
local BANK_ICON = [[Interface\Icons\INV_SideTab_Bank_c60]]
local COLUMNS, PAGE_SIZE, SLOT_SIZE = 8, 88, 37
local COLUMN_STEP, ROW_STEP = SLOT_SIZE + 13, SLOT_SIZE + 10
local WINDOW_WIDTH, WINDOW_HEIGHT = 480, 460
local TAB_MARGIN = 55
local buttons, window, owner = {}
local bankOpen, redrawPending

local function SearchText(text)
	return text:lower():gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):gsub("ẞ", "ß")
end

local function HideOwnedTooltip(frame)
	if GameTooltip:GetOwner() == frame then
		GameTooltip_Hide()
	end
end

local function CreateSlot(parent, backgroundAtlas)
	local slot = CreateFrame("ItemButton", nil, parent)
	local background = slot:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetAtlas(backgroundAtlas)
	slot:SetScript("OnEnter", ns.Measured("BankView: Slot tooltip", function(self)
		if self.link or self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.link then
				GameTooltip:SetHyperlink(self.link)
			else
				GameTooltip:SetText(self.tooltipText)
			end
			GameTooltip:Show()
		end
	end))
	slot:SetScript("OnLeave", HideOwnedTooltip)
	slot:HookScript("OnHide", HideOwnedTooltip)
	return slot
end

local function SetSlot(slot, item, matches, frameAtlas)
	local link = item and item.link or nil
	if slot.link ~= link then
		HideOwnedTooltip(slot)
	end
	slot.link = link
	slot:SetItemButtonTexture(item and item.icon or nil)
	slot:SetItemButtonCount(item and item.count or 0)
	slot:SetItemButtonQuality(item and item.quality or nil)
	slot:SetMatchesSearch(matches)
	slot:GetNormalTexture():SetAtlas(frameAtlas)
end

local function RefreshBankBags(snapshot)
	local count = snapshot and snapshot.maxBags or 1
	for i = 2, count do
		local slot = window.BankBags[i]
		if not slot then
			slot = CreateSlot(window.BagBar, "bank-frame-bag-slot-bg")
			slot:SetScale(0.75)
			slot.Lock = slot:CreateTexture(nil, "ARTWORK", nil, 1)
			slot.Lock:SetAllPoints()
			slot.Lock:SetAtlas("bankslot-icon-lock")
			window.BankBags[i] = slot
		end
		slot:SetPoint("CENTER", window.BagBar, "CENTER", (i - 2 - (count - 2) / 2) * 64, 0)
		local bag = firstBankBag + i - 1
		local purchased = snapshot.sizes[bag] ~= nil
		slot.tooltipText = purchased and L.BANKVIEW_BAG or L.BANKVIEW_BAG_LOCKED
		slot.Lock:SetShown(not purchased)
		SetSlot(slot, snapshot.equipped[bag], true, "bank-frame-bag-slotframe")
		slot:Show()
	end
	for i = count + 1, lastBankBag - firstBankBag + 1 do
		if window.BankBags[i] then
			window.BankBags[i]:Hide()
		end
	end
	window.BagBar:SetShown(count > 1)
end

local function RefreshView(findMatchingPage)
	local snapshot = BankView.cdb.snapshot
	local query = SearchText(strtrim(window.Search:GetText()))
	local slots, matches, firstMatchPage, currentPageMatches = {}, {}
	local hasItems = false
	if snapshot then
		for _, bag in ipairs(snapshot.bags) do
			local items = snapshot.items[bag]
			-- Old snapshots contain a compact list. Its order is usable until the next visit saves the empty slots.
			local size = snapshot.sizes and snapshot.sizes[bag] or #items
			for index = 1, size do
				local item = items[index]
				local position = #slots + 1
				slots[position] = item or false
				if item then
					hasItems = true
					if query ~= "" and SearchText(item.name):find(query, 1, true) then
						matches[position] = true
						local page = math.ceil(position / PAGE_SIZE)
						firstMatchPage = firstMatchPage or page
						currentPageMatches = currentPageMatches or page == window.page
					end
				end
			end
		end
	end

	local pages = math.ceil(#slots / PAGE_SIZE)
	if findMatchingPage and firstMatchPage and not currentPageMatches then
		window.page = firstMatchPage
	end
	window.page = math.min(window.page, math.max(1, pages))
	local offset = (window.page - 1) * PAGE_SIZE
	local visible = math.min(PAGE_SIZE, #slots - offset)
	for i = 1, visible do
		local slot = window.Slots[i]
		if not slot then
			slot = CreateSlot(window.Grid, "bags-item-bankslot64")
			slot:SetSize(SLOT_SIZE, SLOT_SIZE)
			local column, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
			slot:SetPoint("TOPLEFT", window.Grid, "TOPLEFT", 47 + column * COLUMN_STEP, -63 - row * ROW_STEP)
			window.Slots[i] = slot
		end
		local item = slots[offset + i]
		local atlas = item and "bank-frame-bag-slotframe" or "bank-frame-item-slotframe"
		SetSlot(slot, item, not item or query == "" or matches[offset + i] == true, atlas)
		slot:Show()
	end
	for i = visible + 1, #window.Slots do
		window.Slots[i]:Hide()
	end

	window:SetHeight(WINDOW_HEIGHT + math.max(0, math.ceil(visible / COLUMNS) - 6) * ROW_STEP)
	for page = 1, pages do
		local tab = window.Tabs[page]
		if not tab then
			tab = CreateFrame("Frame", nil, window, "BankPageTabTemplate")
			tab:EnableMouse(true)
			tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -60 - (page - 1) * (tab:GetHeight() + 2))
			tab:SetCustomOnMouseUpHandler(ns.Measured("BankView: Select page", function(_, button, upInside)
				if button == "LeftButton" and upInside then
					window.page = page
					RefreshView()
				end
			end))
			window.Tabs[page] = tab
		end
		tab:SetPageInfo(bankType, page, window.page)
		tab:Show()
	end
	for page = pages + 1, #window.Tabs do
		window.Tabs[page]:Hide()
	end

	window.Empty:SetText(not snapshot and L.BANKVIEW_NO_SNAPSHOT or not hasItems and L.BANKVIEW_EMPTY or "")
	window.SearchStatus:SetText(query ~= "" and hasItems and not firstMatchPage and L.BANKVIEW_NO_RESULTS or "")
	window.Updated:SetText(snapshot and L.BANKVIEW_UPDATED:format(date(L.BANKVIEW_DATE, snapshot.updated)) or "")
	window.LayoutHint:SetShown(snapshot ~= nil and snapshot.sizes == nil)
	RefreshBankBags(snapshot)
end

local function QueueRedraw()
	if not redrawPending and window and window:IsShown() then
		redrawPending = true
		ns.After("BankView: Refresh visible bank", 0, function()
			redrawPending = nil
			if window:IsShown() then
				RefreshView()
			end
		end)
	end
end

local function ReadItem(info)
	local id, count = ns.Number(info.itemID), ns.Number(info.stackCount)
	if not id or not count then
		return
	end
	local link = not ns.Secret(info.hyperlink) and info.hyperlink
	local name = link and link:match("|h%[(.-)%]|h")
	if not name and not ns.Secret(info.itemName) and info.itemName and info.itemName ~= "" then
		name = info.itemName
	end
	return {
		name = name or ("item:%d"):format(id),
		link = link and link ~= "" and link or ("item:%d"):format(id),
		icon = ns.Number(info.iconFileID, 134400),
		quality = ns.Number(info.quality, 1),
		count = count,
	}
end

local function ReadBankBag(bag)
	local size = ns.Number(C_Container.GetContainerNumSlots(bag))
	if not size or (size == 0 and bag == firstBankBag) then
		return -- The main bank has not loaded. Other slots may have no bag equipped.
	end
	local items = {}
	for slot = 1, size do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			items[slot] = ReadItem(info)
			if not items[slot] then
				return -- Keep the previous snapshot if the slot data is unavailable.
			end
		end
	end
	return items, size
end

local function SaveBank()
	if not C_Bank.CanViewBank(bankType) then
		return
	end
	local bags = C_Bank.FetchPurchasedBankTabIDs(bankType)
	if not bags or #bags == 0 then
		return
	end
	local items, sizes, equipped = {}, {}, {}
	for _, bag in ipairs(bags) do
		items[bag], sizes[bag] = ReadBankBag(bag)
		if not items[bag] then
			return
		end
		if bag > firstBankBag then
			local info = C_Container.GetContainerItemInfo(Enum.BagIndex.Characterbanktab, bag - firstBankBag + 1)
			equipped[bag] = info and ReadItem(info) or nil
		end
	end
	BankView.cdb.snapshot = {
		bags = bags, items = items, sizes = sizes, equipped = equipped,
		maxBags = ns.Number(C_Bank.FetchMaxNumBankTabs(bankType), #bags), updated = time(),
	}
	QueueRedraw()
end

local function OnBagUpdate(_, _, bag)
	if bag == Enum.BagIndex.Characterbanktab then
		SaveBank()
		return
	end
	if bag < firstBankBag or bag > lastBankBag or not C_Bank.CanViewBank(bankType) then
		return
	end
	local snapshot = BankView.cdb.snapshot
	if not (snapshot and snapshot.sizes and snapshot.items[bag]) then
		SaveBank()
		return
	end
	local items, size = ReadBankBag(bag)
	if items then
		snapshot.items[bag], snapshot.sizes[bag], snapshot.updated = items, size, time()
		QueueRedraw()
	end
end

local function OnBankTabsChanged(_, _, changedBankType)
	if changedBankType == bankType then
		SaveBank()
	end
end

local function CreateWindow()
	window = CreateFrame("Frame", "ForeverPlusBankView", UIParent, "PortraitFrameTemplate")
	window:Hide()
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:SetClampRectInsets(-13, TAB_MARGIN, 16, -3)
	window:EnableMouse(true)
	window:SetTitle(L.BANKVIEW_TITLE)
	window:SetPortraitToAsset(BANK_ICON)
	window.CloseButton:SetScript("OnClick", ns.Measured("BankView: Close", function() window:Hide() end))
	window.Slots, window.Tabs, window.BankBags = {}, {}, {}
	tinsert(UISpecialFrames, window:GetName())

	local background = window:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("bank-frame-background")
	background:SetHorizTile(true)
	background:SetVertTile(true)
	background:SetPoint("TOPLEFT", 0, -20)
	background:SetPoint("BOTTOMRIGHT", 0, 30)

	local grid = CreateFrame("Frame", nil, window)
	grid:SetAllPoints()
	grid.layoutType = "InsetFrameTemplate"
	local rim = CreateFrame("Frame", nil, grid, "NineSlicePanelTemplate")
	rim:ClearAllPoints()
	rim:SetPoint("TOPLEFT", 0, -20)
	rim:SetPoint("BOTTOMRIGHT", 0, 30)
	local shadows = CreateFrame("Frame", nil, grid, "BankPanelEdgeShadowTemplate")
	shadows:ClearAllPoints()
	shadows:SetPoint("TOPLEFT")
	shadows:SetPoint("BOTTOMRIGHT", rim)
	window.Grid = grid

	local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	search:SetSize(160, 20)
	search:SetPoint("TOPRIGHT", -38, -33)
	search:SetMaxLetters(80)
	window.Search = search

	local bagBar = CreateFrame("Frame", nil, window)
	bagBar:SetPoint("BOTTOMLEFT", 16, 45)
	bagBar:SetPoint("BOTTOMRIGHT", -16, 45)
	bagBar:SetHeight(42)
	local divider = bagBar:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("bank-divider", true)
	divider:SetScale(0.48)
	divider:SetPoint("BOTTOM", bagBar, "TOP", 0, 6)
	window.BagBar = bagBar

	window.Empty = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.Empty:SetPoint("TOP", 0, -86)
	window.Empty:SetWidth(WINDOW_WIDTH - 80)
	window.SearchStatus = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.SearchStatus:SetPoint("RIGHT", search, "LEFT", -12, 0)
	window.LayoutHint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.LayoutHint:SetPoint("BOTTOMLEFT", 16, 34)
	window.LayoutHint:SetText(L.BANKVIEW_LEGACY_LAYOUT)
	window.Updated = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	window.Updated:SetPoint("BOTTOMLEFT", 16, 10)

	search:HookScript("OnTextChanged", ns.Measured("BankView: Search", function()
		if window:IsShown() then
			RefreshView(true)
		end
	end))
	window:HookScript("OnHide", ns.Measured("BankView: Reset search", function()
		search:ClearFocus()
		search:SetText("")
		owner = nil
	end))
	ns.HookSavedWindow(window)
end

local function ToggleView(button)
	if window and window:IsShown() then
		window:Hide()
		return
	end
	if not window then
		CreateWindow()
	end
	owner = button
	window.page = 1
	window:ClearAllPoints()
	window:SetPoint("TOPRIGHT", button:GetParent(), "TOPLEFT", -TAB_MARGIN - 8, 0)
	window:Show()
	RefreshView()
end

local function CreateBagButton(parent)
	if not parent or not parent.CloseButton then
		return
	end
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(18, 18)
	button:SetPoint("RIGHT", parent.CloseButton, "LEFT", -1, 0)
	button:SetFrameLevel(parent.TitleContainer:GetFrameLevel() + 2)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(BANK_ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetNormalTexture(icon)
	button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	button:SetScript("OnClick", ns.Measured("BankView: Toggle", ToggleView))
	button:SetScript("OnEnter", ns.Measured("BankView: Button tooltip", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L.BANKVIEW_TITLE)
		GameTooltip:Show()
	end))
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnHide", function(self)
		HideOwnedTooltip(self)
		if self == owner then
			window:Hide()
		end
	end)
	buttons[#buttons + 1] = button
end

function BankView:WatchBank()
	local watching = bankOpen and self.db.enabled
	self:ToggleEvent("BAG_UPDATE", watching, OnBagUpdate)
	self:ToggleEvent("BANK_TABS_CHANGED", watching, OnBankTabsChanged)
	self:ToggleEvent("BAG_CONTAINER_UPDATE", watching, SaveBank)
	if watching then
		SaveBank()
	end
end

function BankView:OnOptionChanged()
	for _, button in ipairs(buttons) do
		button:SetShown(self.db.enabled)
	end
	self:WatchBank()
end

function BankView:OnLogin()
	CreateBagButton(_G.ContainerFrame1)
	CreateBagButton(ContainerFrameCombinedBags)
	self:RegisterEvent("BANKFRAME_OPENED", function()
		bankOpen = true
		self:WatchBank()
	end)
	self:RegisterEvent("BANKFRAME_CLOSED", function()
		bankOpen = false
		self:WatchBank()
	end)
	self:OnOptionChanged()
end

-- Auction house: fallback sell price (3x vendor, ending in 99c from 1s up) when no listing exists
(function()
	local A = ns:GetModule("Auction")
	local saved = {
		C_AuctionHouse, C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetItemLink,
		C_Item.IsItemDataCachedByID, C_Item.GetItemInfo, AuctionHouseFrame, issecretvalue,
		A.db.vendorFallbackPrice, hooksecurefunc, GetMoneyString,
	}
	GetMoneyString = function(v) return tostring(v) .. "c" end

	-- Option & NEU badge metadata
	assert(A.defaults.vendorFallbackPrice == true, "vendorFallbackPrice defaults to true")
	local opt
	for _, entry in ipairs(A.options) do
		if entry.key == "vendorFallbackPrice" then
			opt = entry
			break
		end
	end
	assert(opt and opt.new == true and type(opt.name) == "string" and opt.name ~= ""
		and type(opt.desc) == "string" and opt.desc ~= "", "vendorFallbackPrice option registered with new = true")

	-- Pure formula checks
	assert(A.FallbackSellPrice(nil, true) == nil, "nil vendor -> nil")
	assert(A.FallbackSellPrice(0, true) == nil, "0 vendor -> nil")
	assert(A.FallbackSellPrice(-10, true) == nil, "negative vendor -> nil")
	assert(A.FallbackSellPrice(1, true) == 3, "1c vendor -> 3c (<1s exact)")
	assert(A.FallbackSellPrice(10, true) == 30, "10c vendor -> 30c (<1s exact)")
	assert(A.FallbackSellPrice(25, true) == 75, "25c vendor -> 75c (<1s exact)")
	assert(A.FallbackSellPrice(33, true) == 99, "33c vendor -> 99c (<1s exact)")
	assert(A.FallbackSellPrice(34, true) == 99, "34c vendor -> 102c -> 99c")
	assert(A.FallbackSellPrice(50, true) == 199, "50c vendor -> 150c -> 1s 99c")
	assert(A.FallbackSellPrice(100, true) == 299, "1s vendor -> 3s -> 2s 99c")
	assert(A.FallbackSellPrice(1070, true) == 3199, "10s 70c -> 32s 10c -> 31s 99c")
	assert(A.FallbackSellPrice(1090, true) == 3299, "10s 90c -> 32s 70c -> 32s 99c")
	assert(A.FallbackSellPrice(1100, true) == 3299, "11s -> 33s -> 32s 99c")
	assert(A.FallbackSellPrice(10000, true) == 29999, "1g -> 3g -> 2g 99s 99c")
	assert(A.FallbackSellPrice(10, false) == 100, "no copper support: min 1s")
	assert(A.FallbackSellPrice(1100, false) == 3300, "no copper support: 33s")
	assert(A.FallbackSellPrice(1070, false) == 3200, "no copper support: 32s")

	-- Hooked sell frames end-to-end simulation
	local vendors = { [88101] = 1100, [88102] = 20, [88103] = 0, [88201] = 1090 }
	local secretVal
	issecretvalue = function(v) return secretVal ~= nil and v == secretVal end
	C_Item.DoesItemExist = function(loc) return type(loc) == "table" and loc.id ~= nil end
	C_Item.GetItemID = function(loc) return loc and loc.id end
	C_Item.GetItemLink = function(loc) return loc and ("|Hitem:%d|h[Test]|h"):format(loc.id) end
	C_Item.IsItemDataCachedByID = function(id) return vendors[id] ~= nil end
	C_Item.GetItemInfo = function(arg)
		local id = type(arg) == "number" and arg or tonumber(tostring(arg):match("item:(%d+)"))
		if id and vendors[id] ~= nil then
			return "Test", "|Hitem:" .. id .. "|h[Test]|h", 1, 1, 1, "", "", 20, "", 0, vendors[id]
		end
	end

	local commResults, commFull = {}, true
	local itemResults, itemFull, itemKeyInfoPresent = {}, true, true
	C_AuctionHouse = {
		SupportsCopperValues = function() return true end,
		GetNumCommoditySearchResults = function(id) return #(commResults[id] or {}) end,
		GetCommoditySearchResultInfo = function(id, idx) return commResults[id] and commResults[id][idx] or nil end,
		HasFullCommoditySearchResults = function() return commFull end,
		GetNumItemSearchResults = function(key) return #(itemResults[key and key.itemID] or {}) end,
		HasFullItemSearchResults = function() return itemFull end,
		GetItemKeyInfo = function() return itemKeyInfoPresent and { isPet = false } or nil end,
	}

	local function MakePriceInput(onChanged)
		local amount = 0
		return {
			GetAmount = function() return amount end,
			SetAmount = function(_, v) amount = v; if onChanged then onChanged() end end,
		}
	end

	local commFrame = NewFrame("Frame")
	commFrame.PostButton = NewFrame("Button")
	commFrame.UpdatePostState = function() end
	commFrame.PriceInput = MakePriceInput(function() commFrame:UpdatePostState() end)
	commFrame.GetItem = function(self) return self.itemLocation end
	commFrame.GetUnitPrice = function(self) return self.PriceInput:GetAmount() end
	commFrame.GetDefaultPrice = function(self)
		local v = self.itemLocation and vendors[self.itemLocation.id] or 0
		return v > 0 and (floor(v * 1.5 / 100) + 1) * 100 or 100
	end
	commFrame.SetItem = function(self, loc)
		self.itemLocation = loc
		self.PriceInput:SetAmount(loc and self:GetDefaultPrice() or 0)
	end
	commFrame:SetScript("OnEvent", function(self, event)
		if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and self.itemLocation then
			local first = C_AuctionHouse.GetCommoditySearchResultInfo(self.itemLocation.id, 1)
			if first and self:GetUnitPrice() == self:GetDefaultPrice() then
				self.PriceInput:SetAmount(first.unitPrice)
			end
		end
	end)

	local itemFrame = NewFrame("Frame")
	itemFrame.PostButton = NewFrame("Button")
	itemFrame.UpdatePostState = function() end
	itemFrame.PriceInput = MakePriceInput(function() itemFrame:UpdatePostState() end)
	local secShown, secAmount = false, 0
	itemFrame.SecondaryPriceInput = {
		IsShown = function() return secShown end,
		GetAmount = function() return secAmount end,
	}
	itemFrame.GetItem = function(self) return self.itemLocation end
	itemFrame.GetPrice = function(self)
		local b = self.PriceInput:GetAmount()
		return (secShown and secAmount > 0) and secAmount or nil, b > 0 and b or nil
	end
	itemFrame.GetDefaultPrice = function(self)
		local v = self.itemLocation and vendors[self.itemLocation.id] or 0
		return v > 0 and (floor(v * 1.5 / 100) + 1) * 100 or 100
	end
	local itemBestEntry = nil
	itemFrame.GetBestEntry = function() return itemBestEntry end
	itemFrame.SetItem = function(self, loc)
		self.itemLocation = loc
		self.listDisplayedItemKey = loc and { itemID = loc.id } or nil
		self.PriceInput:SetAmount(loc and self:GetDefaultPrice() or 0)
	end
	itemFrame:SetScript("OnEvent", function(self, event)
		if event == "ITEM_SEARCH_RESULTS_UPDATED" and self.itemLocation then
			local best = self:GetBestEntry()
			if best and self.PriceInput:GetAmount() == self:GetDefaultPrice() then
				self.PriceInput:SetAmount(best.buyoutAmount or 0)
			end
		end
	end)

	AuctionHouseFrame = { CommoditiesSellFrame = commFrame, ItemSellFrame = itemFrame }
	A.db.vendorFallbackPrice = true
	hooksecurefunc = function(a, b, c)
		if type(a) == "table" then
			local orig = assert(a[b], "hooksecurefunc: table lacks " .. tostring(b))
			a[b] = function(...)
				orig(...)
				c(...)
			end
		end
	end
	uv(A.OnLogin, "HookSellFrames")()

	-- 1. Commodity with 0 listings (>= 1s): 11s vendor -> 32s 99c (3299)
	commResults[88101], commFull = {}, true
	commFrame:SetItem({ id = 88101 })
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "SetItem waits for search results before changing price")
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == 3299, "empty commodity search sets 32s 99c fallback: " .. tostring(commFrame:GetUnitPrice()))

	-- 2. Subsequent refresh does not overwrite user edit (even if user typed defaultPrice or 0)
	commFrame.PriceInput:SetAmount(commFrame:GetDefaultPrice())
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "refresh does not overwrite user price after fallback ran")

	-- 3. Commodity < 1s: 20c vendor -> exact 60c
	commResults[88102], commFull = {}, true
	commFrame:SetItem({ id = 88102 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88102)
	assert(commFrame:GetUnitPrice() == 60, "below 1s keeps exact 3x price (60c): " .. tostring(commFrame:GetUnitPrice()))

	-- 4. Commodity WITH existing listings: Blizzard's cheapest listing wins
	commResults[88101] = { { unitPrice = 5432 } }
	commFrame:SetItem({ id = 88101 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == 5432, "existing commodity listing is kept untouched")

	-- 5. User already typed custom price before results arrive: preserved
	commResults[88101] = {}
	commFrame:SetItem({ id = 88101 })
	commFrame.PriceInput:SetAmount(9999)
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == 9999, "manual price entered before results is not overwritten")

	-- 6. Stale event for other itemID & incomplete results wait for real full event
	commResults[88101], commFull = {}, false
	commFrame:SetItem({ id = 88101 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88102)
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "stale event for other itemID ignored")
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "incomplete empty search does not fire early")
	commFull = true
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == 3299, "full empty search then applies fallback")

	-- 7. Vendor price 0 (unsellable/pet) and option disabled and secret value
	commResults[88103], commFull = {}, true
	commFrame:SetItem({ id = 88103 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88103)
	assert(commFrame:GetUnitPrice() == 100, "item with 0 vendor price keeps Blizzard default")

	A.db.vendorFallbackPrice = false
	commResults[88101], commFull = {}, true
	commFrame:SetItem({ id = 88101 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", 88101)
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "option disabled leaves Blizzard default")
	A.db.vendorFallbackPrice = true

	secretVal = "SECRET_ID"
	commFrame:SetItem({ id = 88101 })
	commFrame:GetScript("OnEvent")(commFrame, "COMMODITY_SEARCH_RESULTS_UPDATED", secretVal)
	assert(commFrame:GetUnitPrice() == commFrame:GetDefaultPrice(), "secret commodity event payload ignored safely")
	secretVal = nil

	-- 8. ItemSellFrame: 0 results -> 32s 99c (10s 90c vendor -> 32s 70c -> 32s 99c)
	itemResults[88201], itemFull, itemBestEntry = {}, true, nil
	itemFrame:SetItem({ id = 88201 })
	itemFrame:GetScript("OnEvent")(itemFrame, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 88201 })
	assert(itemFrame.PriceInput:GetAmount() == 3299, "empty item search sets 32s 99c fallback: " .. tostring(itemFrame.PriceInput:GetAmount()))

	-- 9. ItemSellFrame: other itemLevel exists -> virtual noneAvailableEntry clears price to 0 -> fallback fills 32s 99c
	itemResults[88201] = { { buyoutAmount = 8000 } }
	itemBestEntry = { isVirtualEntry = true }
	itemFrame:SetItem({ id = 88201 })
	itemFrame:GetScript("OnEvent")(itemFrame, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 88201 })
	assert(itemFrame.PriceInput:GetAmount() == 3299, "virtual noneAvailableEntry triggers fallback: " .. tostring(itemFrame.PriceInput:GetAmount()))

	-- 10. ItemSellFrame: real matching listing exists -> Blizzard's buyout is kept
	itemResults[88201] = { { buyoutAmount = 4500 } }
	itemBestEntry = { buyoutAmount = 4500 }
	itemFrame:SetItem({ id = 88201 })
	itemFrame:GetScript("OnEvent")(itemFrame, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 88201 })
	assert(itemFrame.PriceInput:GetAmount() == 4500, "real item listing price is kept untouched")

	-- 11. ItemSellFrame: manual bid in SecondaryPriceInput prevents overwriting
	itemResults[88201], itemBestEntry = {}, nil
	secShown, secAmount = true, 1500
	itemFrame:SetItem({ id = 88201 })
	itemFrame:GetScript("OnEvent")(itemFrame, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 88201 })
	assert(itemFrame.PriceInput:GetAmount() == itemFrame:GetDefaultPrice(), "manual bid in SecondaryPriceInput is respected")
	secShown, secAmount = false, 0

	-- 12. Secret itemKey in ITEM_SEARCH_RESULTS_UPDATED ignored safely
	secretVal = { itemID = 88201 }
	itemFrame:SetItem({ id = 88201 })
	itemFrame:GetScript("OnEvent")(itemFrame, "ITEM_SEARCH_RESULTS_UPDATED", secretVal)
	assert(itemFrame.PriceInput:GetAmount() == itemFrame:GetDefaultPrice(), "secret itemKey ignored safely")
	secretVal = nil

	C_AuctionHouse, C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetItemLink,
		C_Item.IsItemDataCachedByID, C_Item.GetItemInfo, AuctionHouseFrame, issecretvalue,
		A.db.vendorFallbackPrice, hooksecurefunc, GetMoneyString = unpack(saved, 1, 11)
	print("auction fallback sell price OK")
end)()

;(function()
	-- Quality pixel border suppresses Blizzard's yellow IconQuestTexture inner border (and 1 px bottom
	-- overhang) on uncommon+ items, keeps a clean "!" badge for unaccepted quest starters, and restores
	-- IconQuestTexture on poor/common/empty slots.
	local vis = ns:GetModule("Visuals")
	local updateGlow = uv(vis.OnInitialize, "UpdateGlow")
	local questBangs = uv(uv(updateGlow, "SyncQuestOverlay"), "questBangs")
	assert(updateGlow and questBangs, "Visuals UpdateGlow / questBangs upvalues found")

	local savedQuestInfo = C_Container.GetContainerItemQuestInfo
	local savedLootInfo = GetLootSlotInfo
	local savedSecret = issecretvalue
	local savedCommon = Enum.ItemQuality.Common
	Enum.ItemQuality.Common = savedCommon or 1
	local questBySlot = {}
	local lootBySlot = {}
	local secretVal

	C_Container.GetContainerItemQuestInfo = function(bag, slot)
		return questBySlot[bag .. ":" .. slot]
	end
	GetLootSlotInfo = function(slotIndex)
		local row = lootBySlot[slotIndex]
		if row then
			return nil, nil, 1, nil, row.quality, false, row.isQuestItem, row.questID, row.isActive
		end
	end
	issecretvalue = function(v) return v ~= nil and v == secretVal end

	local function MakeTex()
		local t = { alpha = 1, shown = false }
		function t:SetAlpha(a) self.alpha = a end
		function t:GetAlpha() return self.alpha end
		function t:Show() self.shown = true end
		function t:Hide() self.shown = false end
		function t:SetShown(s) self.shown = not not s end
		function t:IsShown() return self.shown end
		function t:SetTexture(tex) self.tex = tex end
		function t:GetTexture() return self.tex end
		function t:SetColorTexture(...) self.color = { ... } end
		function t:SetVertexColor(...) self.vc = { ... } end
		function t:ClearAllPoints() end
		function t:SetPoint(...) end
		function t:SetSize(...) end
		function t:SetWidth(...) end
		function t:SetHeight(...) end
		return t
	end

	local function MakeButton(opts)
		opts = opts or {}
		local b = {
			IconQuestTexture = not opts.noQuestTex and MakeTex() or nil,
			textures = {},
		}
		function b:IsForbidden() return false end
		function b:GetWidth() return 37 end
		function b:GetEffectiveScale() return 1 end
		function b:GetFrameLevel() return 10 end
		function b:GetParent() return opts.parent end
		if opts.bag then
			function b:GetBagID() return opts.bag end
			function b:GetID() return opts.slot end
		end
		if opts.bankTab then
			function b:GetBankTabID() return opts.bankTab end
			function b:GetContainerSlotID() return opts.bankSlot end
		end
		function b:CreateTexture()
			local t = MakeTex()
			self.textures[#self.textures + 1] = t
			return t
		end
		return b
	end

	-- 1. Rare active/regular quest item in bag: IconQuestTexture silenced, no "!" badge
	local bagBtn = MakeButton({ bag = 0, slot = 3 })
	bagBtn.IconQuestTexture:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBorder")
	bagBtn.IconQuestTexture:Show()
	questBySlot["0:3"] = { isQuestItem = true, questID = 100, isActive = true }
	updateGlow(bagBtn, 3, true)
	assert(bagBtn.IconQuestTexture:GetAlpha() == 0, "rare quest item hides yellow IconQuestTexture")
	assert(not (questBangs[bagBtn] and questBangs[bagBtn]:IsShown()), "active quest item shows no bang")

	-- 2. Rare unaccepted quest starter in bag (same quality = 3): IconQuestTexture stays 0, clean "!" shown
	questBySlot["0:3"] = { isQuestItem = false, questID = 200, isActive = false }
	updateGlow(bagBtn, 3, true)
	assert(bagBtn.IconQuestTexture:GetAlpha() == 0, "rare quest starter keeps yellow border hidden")
	assert(questBangs[bagBtn] and questBangs[bagBtn]:IsShown(), "rare quest starter shows clean bang")
	assert(questBangs[bagBtn]:GetTexture() == [[Interface\GossipFrame\AvailableQuestIcon]], "uses clean quest bang icon")

	-- 3. Player accepts quest (still quality = 3): bang hides even when quality state is unchanged
	questBySlot["0:3"] = { isQuestItem = true, questID = 200, isActive = true }
	updateGlow(bagBtn, 3, true)
	assert(bagBtn.IconQuestTexture:GetAlpha() == 0, "accepted quest keeps yellow border hidden")
	assert(not questBangs[bagBtn]:IsShown(), "accepted quest hides bang badge")

	-- 4. Slot changes to white (common) quest item: Blizzard's IconQuestTexture restored to alpha 1
	questBySlot["0:3"] = { isQuestItem = true, questID = 300, isActive = true }
	updateGlow(bagBtn, 1, true)
	assert(bagBtn.IconQuestTexture:GetAlpha() == 1, "common quest item restores IconQuestTexture alpha")
	assert(not questBangs[bagBtn]:IsShown(), "common item hides addon bang badge")

	-- 5. Bank button using cached questItemInfo (starter -> active -> empty)
	local bankBtn = MakeButton({ bankTab = 6, bankSlot = 1 })
	bankBtn.IconQuestTexture:Show()
	bankBtn.questItemInfo = { isQuestItem = false, questID = 400, isActive = false }
	updateGlow(bankBtn, 4)
	assert(bankBtn.IconQuestTexture:GetAlpha() == 0, "epic bank quest starter hides yellow border")
	assert(questBangs[bankBtn] and questBangs[bankBtn]:IsShown(), "epic bank quest starter shows clean bang")
	bankBtn.questItemInfo = nil
	updateGlow(bankBtn, nil)
	assert(bankBtn.IconQuestTexture:GetAlpha() == 1, "empty bank slot restores IconQuestTexture alpha")
	assert(not questBangs[bankBtn]:IsShown(), "empty bank slot hides bang")

	-- 6. Loot row: IconQuestTexture sits on parent row alongside row.Item
	local lootRow = { IconQuestTexture = MakeTex() }
	function lootRow:GetSlotIndex() return 2 end
	local lootItem = MakeButton({ noQuestTex = true, parent = lootRow })
	lootRow.Item = lootItem
	lootRow.IconQuestTexture:Show()
	lootBySlot[2] = { quality = 3, isQuestItem = true, questID = 500, isActive = false }
	updateGlow(lootItem, 3)
	assert(lootRow.IconQuestTexture:GetAlpha() == 0, "loot row hides yellow quest border on rare item")
	assert(questBangs[lootItem] and questBangs[lootItem]:IsShown(), "loot row shows clean bang for starter")
	updateGlow(lootItem, 1)
	assert(lootRow.IconQuestTexture:GetAlpha() == 1, "loot row restores quest border on common item")
	assert(not questBangs[lootItem]:IsShown(), "loot row hides addon bang on common item")

	-- 7. Secret quest info handled safely without error
	local secBtn = MakeButton({ bag = 0, slot = 4 })
	secretVal = { questID = 999, isActive = false }
	questBySlot["0:4"] = secretVal
	updateGlow(secBtn, 3, true)
	assert(secBtn.IconQuestTexture:GetAlpha() == 0, "secret quest info still hides yellow border safely")
	assert(not (questBangs[secBtn] and questBangs[secBtn]:IsShown()), "secret quest info does not error or show bogus bang")
	secretVal = nil

	C_Container.GetContainerItemQuestInfo = savedQuestInfo
	GetLootSlotInfo = savedLootInfo
	issecretvalue = savedSecret
	Enum.ItemQuality.Common = savedCommon
	print("visuals quality quest border suppression OK")
end)()
;(function()
	-- GroupFinder: right-side Dungeon Journal tab on LFGParentFrame
	local gf = ns:GetModule("GroupFinder")
	local journal = ns:GetModule("DungeonJournal")
	assert(gf.defaults.journalTab == true, "journalTab defaults to true")
	local opt
	for _, entry in ipairs(gf.options) do
		if entry.key == "journalTab" then opt = entry end
	end
	assert(opt and opt.new == true and opt.name and opt.desc, "journalTab option has new badge and localized texts")

	local setupButtons = uv(gf.OnLogin, "SetupJournalButtons")
	local setupTab = uv(setupButtons, "SetupJournalTab")
	local function setUV(fn, name, val)
		for i = 1, 200 do
			local n, old = debug.getupvalue(fn, i)
			if not n then return end
			if n == name then debug.setupvalue(fn, i, val) return old end
		end
	end
	local savedJournalTab = setUV(setupTab, "journalTab", nil)
	local savedCreate, savedParent = CreateFrame, LFGParentFrame
	local savedBrowse, savedListing = LFGBrowseFrame, LFGListingFrame
	local savedModern, savedLFGList = LFGVANILLA_SETTING_MODERN_STYLE, C_LFGList
	local savedSecret = issecretvalue
	local savedTabOpt, savedJournalEnabled = gf.db.journalTab, journal.db.enabled
	local savedOpen, savedToggle, savedIsOpen, savedHasInst = journal.Open, journal.Toggle, journal.IsOpen, journal.HasInstance

	local createdTab
	local function MakeMockFrame()
		local f = { shown = true, hooks = {}, scripts = {} }
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		function f:SetShown(v) self.shown = v and true or false end
		function f:IsShown() return self.shown end
		function f:EnableMouse(v) self.mouse = v end
		function f:SetPoint(...) self.point = { ... } end
		function f:HookScript(event, fn) self.hooks[event] = fn end
		function f:SetScript(event, fn) self.scripts[event] = fn end
		return f
	end

	local parent = MakeMockFrame()
	parent.WhoListingTab = MakeMockFrame()
	local parentKeyCount = 0
	for _ in pairs(parent) do parentKeyCount = parentKeyCount + 1 end
	LFGParentFrame = parent
	LFGVANILLA_SETTING_MODERN_STYLE = true

	CreateFrame = function(frameType, name, p, template)
		if name == "ForeverPlusLFGJournalTab" then
			local tab = MakeMockFrame()
			tab.frameType, tab.name, tab.parent, tab.template = frameType, name, p, template
			tab.Icon = { SetTexture = function(self, tex) self.texture = tex end }
			function tab:SetFillToInterior(v) self.fillToInterior = v end
			function tab:SetChecked(v) self.checked = v and true or false end
			function tab:SetCustomOnMouseUpHandler(fn) self.mouseUp = fn end
			createdTab = tab
			return tab
		end
		return savedCreate(frameType, name, p, template)
	end

	local isOpen, openedWith, toggled = false, nil, 0
	journal.IsOpen = function() return isOpen end
	journal.Open = function(id)
		isOpen = true
		openedWith = id or "default"
		gf.RefreshJournalButtons()
	end
	journal.Toggle = function()
		isOpen = not isOpen
		toggled = toggled + 1
		gf.RefreshJournalButtons()
	end
	journal.HasInstance = function(id) return id == 36 or id == 409 end

	local browseShown, listingShown = true, false
	local browseSelected, browseDropdown, listingActivities = nil, nil, {}
	LFGBrowseFrame = {
		IsShown = function() return browseShown end,
		selectionBehavior = { GetSelectedElementData = function() return browseSelected or {} end },
		ActivityDropdown = { selectedValues = nil },
	}
	LFGListingFrame = {
		IsShown = function() return listingShown end,
		activities = listingActivities,
	}
	local secretResult = { secret = true }
	issecretvalue = function(v) return v == secretResult end
	C_LFGList = {
		GetSearchResultInfo = function(id)
			if id == 1 then return { activityIDs = { 101 } }
			elseif id == 2 then return { activityIDs = { 202 } }
			elseif id == 3 then return secretResult end
		end,
		GetActivityInfoTable = function(id)
			if id == 101 then return { mapID = 36 } -- Deadmines (dungeon)
			elseif id == 202 then return { mapID = 409 } -- Molten Core (raid)
			elseif id == 303 then return { mapID = 999 } end
		end,
	}

	gf.db.journalTab = true
	journal.db.enabled = true
	setupTab(gf.RefreshJournalButtons)
	gf.RefreshJournalButtons()

	assert(createdTab ~= nil, "side tab created on LFGParentFrame")
	assert(createdTab.template == "LargeSideTabButtonTemplate", "uses LargeSideTabButtonTemplate")
	assert(createdTab.point[1] == "TOPLEFT" and createdTab.point[2] == parent.WhoListingTab
		and createdTab.point[3] == "BOTTOMLEFT" and createdTab.point[4] == 0 and createdTab.point[5] == -2,
		"anchored right below WhoListingTab with -2 gap")
	assert(createdTab.Icon.texture == [[Interface\Icons\INV_Misc_Book_09]], "uses book icon texture")
	assert(createdTab.fillToInterior == true, "fills tab interior like Blizzard tabs")
	assert(createdTab.tooltipText == ns.L.JOURNAL_TITLE, "tooltip matches Dungeon Journal title")
	assert(createdTab:IsShown() and createdTab.checked == false, "initially visible and unchecked")
	local afterKeyCount = 0
	for _ in pairs(parent) do afterKeyCount = afterKeyCount + 1 end
	assert(afterKeyCount == parentKeyCount, "does not write tainting keys onto LFGParentFrame")

	-- Right-click or release outside does nothing
	createdTab.mouseUp(createdTab, "RightButton", true)
	createdTab.mouseUp(createdTab, "LeftButton", false)
	assert(not isOpen and openedWith == nil, "ignores right-click and mouse-up outside")

	-- Browse tab with 1 selected raid opens that raid directly and checks the tab
	browseSelected = { { data = { resultID = 2 } } }
	createdTab.mouseUp(createdTab, "LeftButton", true)
	assert(isOpen and openedWith == 409 and createdTab.checked == true, "opens selected raid directly and checks tab")

	-- Clicking again while open closes the journal and unchecks the tab
	createdTab.mouseUp(createdTab, "LeftButton", true)
	assert(not isOpen and toggled == 1 and createdTab.checked == false, "second click closes journal and unchecks tab")

	-- Secret search result falls back safely without error
	browseSelected = { { data = { resultID = 3 } } }
	LFGBrowseFrame.ActivityDropdown.selectedValues = browseDropdown
	createdTab.mouseUp(createdTab, "LeftButton", true)
	assert(isOpen and openedWith == "default", "secret browse result falls back cleanly to default journal open")
	isOpen = false
	gf.RefreshJournalButtons()
	assert(createdTab.checked == false, "refresh unchecks tab after external close")

	-- Listing tab with 1 dungeon opens it; with 2 instances opens default view directly
	browseShown, listingShown = false, true
	listingActivities[101] = true
	createdTab.mouseUp(createdTab, "LeftButton", true)
	assert(isOpen and openedWith == 36, "listing with one dungeon opens that dungeon")
	isOpen = false
	listingActivities[202] = true
	createdTab.mouseUp(createdTab, "LeftButton", true)
	assert(isOpen and openedWith == "default", "listing with multiple instances opens journal directly")

	-- Options hide and show the tab
	gf.db.journalTab = false
	gf:OnOptionChanged("journalTab")
	assert(not createdTab:IsShown(), "disabling journalTab hides the side tab")
	gf.db.journalTab = true
	journal.db.enabled = false
	gf.RefreshJournalButtons()
	assert(not createdTab:IsShown(), "disabling DungeonJournal hides the side tab")
	journal.db.enabled = true
	gf.RefreshJournalButtons()
	assert(createdTab:IsShown(), "re-enabling shows the side tab again")

	-- Restore
	setUV(setupTab, "journalTab", savedJournalTab)
	CreateFrame, LFGParentFrame = savedCreate, savedParent
	LFGBrowseFrame, LFGListingFrame = savedBrowse, savedListing
	LFGVANILLA_SETTING_MODERN_STYLE, C_LFGList = savedModern, savedLFGList
	issecretvalue = savedSecret
	gf.db.journalTab, journal.db.enabled = savedTabOpt, savedJournalEnabled
	journal.Open, journal.Toggle, journal.IsOpen, journal.HasInstance = savedOpen, savedToggle, savedIsOpen, savedHasInst
	print("group finder journal side tab OK")
end)()

-- Never-usable soulbound armor and weapons directly on the sell list
;(function()
	local items = ns:GetModule("Items")
	assert(items.db.markUnusableBound == true, "markUnusableBound defaults to true")
	local opt
	for _, entry in ipairs(items.options) do
		if entry.key == "markUnusableBound" then opt = entry end
	end
	assert(opt and opt.new == true, "markUnusableBound option has new = true")

	local saved = {
		UnitClass, C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemQualityByID,
		C_Item.IsBoundToAccountUntilEquip, C_Item.DoesItemExist, ItemLocation,
		C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo,
		C_Container.GetContainerItemQuestInfo, C_Container.GetContainerItemPurchaseInfo,
		C_Container.GetBackpackSellJunkDisabled, C_Container.GetBagSlotFlag,
		C_Container.UseContainerItem, C_TooltipInfo.GetBagItem,
		ITEM_CLASSES_ALLOWED, ITEM_RACES_ALLOWED, BIND_TRADE_TIME_REMAINING,
		Enum.TooltipDataLineType, issecretvalue, ns.ShowPopupList,
		items.db.markUnusableBound, items.db.junkPerCharacter, items.db.markMessage,
		items.classRestrictionPattern, items.raceRestrictionPattern, items.tradeTimePattern,
	}

	ITEM_CLASSES_ALLOWED = "Classes: %s"
	ITEM_RACES_ALLOWED = "Races: %s"
	BIND_TRADE_TIME_REMAINING = "You may trade this item with players that were also eligible to loot this item for the next %s (including time offline)."
	Enum.TooltipDataLineType = { TradeTimeRemaining = 36 }
	items.classRestrictionPattern, items.raceRestrictionPattern, items.tradeTimePattern = nil, nil, nil

	-- 1. Pure proficiency matrix (including Forever trainer-learnable skills)
	local red = { r = 1, g = 0.1, b = 0.1 }
	-- Level-40 learnable armor must NEVER be marked as never-usable:
	assert(not items.IsNeverUsableEquip(4, 4, "WARRIOR"), "Warrior can learn Plate")
	assert(not items.IsNeverUsableEquip(4, 4, "PALADIN"), "Paladin can learn Plate")
	assert(not items.IsNeverUsableEquip(4, 3, "HUNTER"), "Hunter can learn Mail")
	assert(not items.IsNeverUsableEquip(4, 3, "SHAMAN"), "Shaman can learn Mail")
	-- Never-learnable armor types ARE marked:
	assert(items.IsNeverUsableEquip(4, 4, "HUNTER"), "Hunter can never wear Plate")
	assert(items.IsNeverUsableEquip(4, 4, "SHAMAN"), "Shaman can never wear Plate")
	assert(items.IsNeverUsableEquip(4, 3, "ROGUE"), "Rogue can never wear Mail")
	assert(items.IsNeverUsableEquip(4, 3, "DRUID"), "Druid can never wear Mail")
	assert(items.IsNeverUsableEquip(4, 2, "MAGE"), "Mage can never wear Leather")
	assert(items.IsNeverUsableEquip(4, 2, "PRIEST"), "Priest can never wear Leather")
	assert(items.IsNeverUsableEquip(4, 2, "WARLOCK"), "Warlock can never wear Leather")
	assert(not items.IsNeverUsableEquip(4, 1, "MAGE"), "Cloth is usable by Mage")
	assert(not items.IsNeverUsableEquip(4, 0, "MAGE"), "Generic armor (rings/trinkets/offhands) is usable")
	assert(not items.IsNeverUsableEquip(4, 5, "MAGE"), "Cosmetic armor is usable")
	-- Shields and relics:
	assert(not items.IsNeverUsableEquip(4, 6, "SHAMAN"), "Shaman can wear Shields")
	assert(items.IsNeverUsableEquip(4, 6, "HUNTER"), "Hunter can never wear Shields")
	assert(items.IsNeverUsableEquip(4, 6, "ROGUE"), "Rogue can never wear Shields")
	assert(items.IsNeverUsableEquip(4, 7, "WARRIOR") and not items.IsNeverUsableEquip(4, 7, "PALADIN"), "Libram is Paladin only")
	assert(items.IsNeverUsableEquip(4, 8, "SHAMAN") and not items.IsNeverUsableEquip(4, 8, "DRUID"), "Idol is Druid only")
	assert(items.IsNeverUsableEquip(4, 9, "PALADIN") and not items.IsNeverUsableEquip(4, 9, "SHAMAN"), "Totem is Shaman only")
	-- Forever weapon proficiencies (including trainable at weapon masters):
	assert(not items.IsNeverUsableEquip(2, 0, "ROGUE"), "Rogue can learn 1H Axes in Forever")
	assert(not items.IsNeverUsableEquip(2, 6, "DRUID"), "Druid can learn Polearms in Forever")
	assert(not items.IsNeverUsableEquip(2, 7, "MAGE"), "Mage can learn 1H Swords")
	assert(not items.IsNeverUsableEquip(2, 2, "WARRIOR"), "Warrior can learn Bows")
	assert(items.IsNeverUsableEquip(2, 19, "WARRIOR"), "Warrior can never use Wands")
	assert(not items.IsNeverUsableEquip(2, 19, "PRIEST"), "Priest can use Wands")
	assert(items.IsNeverUsableEquip(2, 15, "PALADIN"), "Paladin can never use Daggers")
	assert(items.IsNeverUsableEquip(2, 8, "ROGUE"), "Rogue can never use 2H Swords")
	assert(items.IsNeverUsableEquip(2, 1, "MAGE"), "Mage can never use 2H Axes")
	assert(not items.IsNeverUsableEquip(2, 14, "MAGE"), "Misc weapons (tools) are never marked")
	assert(not items.IsNeverUsableEquip(2, 20, "MAGE"), "Fishing poles are never marked")
	assert(not items.IsNeverUsableEquip(7, 0, "MAGE"), "Non-armor/weapon items are ignored")
	assert(not items.IsNeverUsableEquip(4, 4, "UNKNOWN_CLASS"), "Unknown class fails safe")
	-- Class/race restriction lines vs level/profession red lines and trade timers:
	assert(items.IsNeverUsableEquip(4, 1, "MAGE", { { leftText = "Classes: Priest", leftColor = red } }), "wrong-class Cloth is never usable")
	assert(items.IsNeverUsableEquip(4, 4, "WARRIOR", { { leftText = "Classes: Paladin", leftColor = red } }), "wrong-class Plate is never usable")
	assert(items.IsNeverUsableEquip(4, 0, "MAGE", { { leftText = "Races: Dwarf", leftColor = red } }), "wrong-race trinket is never usable")
	assert(not items.IsNeverUsableEquip(4, 1, "MAGE", { { leftText = "Requires Level 60", leftColor = red } }), "level-gated item is NOT marked")
	assert(not items.IsNeverUsableEquip(4, 1, "MAGE", { { leftText = "Requires Engineering (250)", leftColor = red } }), "profession-gated item is NOT marked")
	assert(not items.IsNeverUsableEquip(4, 4, "MAGE", { { type = 36, leftText = "You may trade..." } }), "group-tradeable BoP is NOT marked")

	-- 2. End-to-end bag integration: JunkIcon, JunkValue, SellBatch, ToggleJunk, ShowJunkMenu, cross-char safety
	local curClass = "MAGE"
	UnitClass = function() return curClass, curClass end
	local bagItems = {
		[1] = { itemID = 92001, hyperlink = "|cff0070dd|Hitem:92001::::::::60:::::::|h[BoP Plate Chest]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[2] = { itemID = 92002, hyperlink = "|cff1eff00|Hitem:92002::::::::60:::::::|h[BoE Plate Helm]|h|r", quality = 2, stackCount = 1, isBound = false, hasNoValue = false },
		[3] = { itemID = 92003, hyperlink = "|cff0070dd|Hitem:92003::::::::60:::::::|h[BoP Mage 1H Sword]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[4] = { itemID = 92004, hyperlink = "|cff0070dd|Hitem:92004::::::::60:::::::|h[BoP Priest Cloth]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[5] = { itemID = 92005, hyperlink = "|cff0070dd|Hitem:92005::::::::60:::::::|h[BoP Tradeable Plate]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[6] = { itemID = 92006, hyperlink = "|cff0070dd|Hitem:92006::::::::60:::::::|h[BoP Refundable Plate]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[7] = { itemID = 92007, hyperlink = "|cff0070dd|Hitem:92007::::::::60:::::::|h[BoP Quest Plate]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[8] = { itemID = 92008, hyperlink = "|cff0070dd|Hitem:92008::::::::60:::::::|h[BoP NoPrice Plate]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[9] = { itemID = 92009, hyperlink = "|cff0070dd|Hitem:92009::::::::60:::::::|h[BoA Plate]|h|r", quality = 3, stackCount = 1, isBound = true, hasNoValue = false },
		[10] = { itemID = 92010, hyperlink = "|cff0070dd|Hitem:92010::::::::60:::::::|h[Secret Bound Plate]|h|r", quality = 3, stackCount = 1, isBound = "SECRET_BOUND", hasNoValue = false },
	}
	local defs = {
		[92001] = { class = 4, sub = 4, price = 1500, quality = 3 },
		[92002] = { class = 4, sub = 4, price = 1200, quality = 2 },
		[92003] = { class = 2, sub = 7, price = 2000, quality = 3 },
		[92004] = { class = 4, sub = 1, price = 1800, quality = 3, lines = { { leftText = "Classes: Priest", leftColor = red } } },
		[92005] = { class = 4, sub = 4, price = 1600, quality = 3, lines = { { type = 36, leftText = "You may trade..." } } },
		[92006] = { class = 4, sub = 4, price = 1700, quality = 3, refund = 3600 },
		[92007] = { class = 4, sub = 4, price = 1100, quality = 3, quest = true },
		[92008] = { class = 4, sub = 4, price = 0, quality = 3 },
		[92009] = { class = 4, sub = 4, price = 1400, quality = 3, boa = true },
		[92010] = { class = 4, sub = 4, price = 1300, quality = 3 },
	}
	local function IDOf(x) return type(x) == "number" and x or (type(x) == "string" and tonumber(x:match("item:(%d+)"))) end
	C_Item.GetItemInfoInstant = function(x)
		local id = IDOf(x)
		local d = id and defs[id]
		if d then return id, nil, nil, nil, nil, d.class, d.sub end
		return saved[2](x)
	end
	C_Item.GetItemInfo = function(x)
		local id = IDOf(x)
		local d = id and defs[id]
		if d then return "Item" .. id, nil, d.quality, 60, 1, nil, nil, 1, nil, nil, d.price, d.class, d.sub, 1 end
		return saved[3](x)
	end
	C_Item.GetItemQualityByID = function(id) return defs[id] and defs[id].quality or saved[4](id) end
	ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
	C_Item.DoesItemExist = function(loc) return loc and loc.bag == 0 and bagItems[loc.slot] ~= nil end
	C_Item.IsBoundToAccountUntilEquip = function(loc)
		local info = loc and loc.bag == 0 and bagItems[loc.slot]
		return info and defs[info.itemID] and defs[info.itemID].boa or false
	end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bag == 0 and bagItems[slot] or nil end
	C_Container.GetContainerItemQuestInfo = function(bag, slot)
		local info = bag == 0 and bagItems[slot]
		return info and defs[info.itemID] and defs[info.itemID].quest and { isQuestItem = true } or nil
	end
	C_Container.GetContainerItemPurchaseInfo = function(bag, slot)
		local info = bag == 0 and bagItems[slot]
		return info and defs[info.itemID] and defs[info.itemID].refund and { refundSeconds = defs[info.itemID].refund } or nil
	end
	C_Container.GetBackpackSellJunkDisabled = function() return false end
	C_Container.GetBagSlotFlag = function() return false end
	C_TooltipInfo.GetBagItem = function(bag, slot)
		local info = bag == 0 and bagItems[slot]
		return { lines = (info and defs[info.itemID] and defs[info.itemID].lines) or {} }
	end
	issecretvalue = function(v) return v == "SECRET_BOUND" end

	items.db.markUnusableBound = true
	items.db.junkPerCharacter = false
	items.db.markMessage = false
	for id = 92001, 92010 do items.db.junk[id] = nil; items.db.keep[id] = nil end

	-- Only slot 1 (BoP Plate) and slot 4 (BoP Priest Cloth) count as junk for Mage!
	local count, value = ns.MerchantTools.JunkValue()
	assert(count == 2 and value == 3300, ("expected 2 unusable bound items worth 3300, got %d / %d"):format(count, value))
	assert(not items.db.junk[92001] and not items.db.junk[92004], "account-wide db.junk is NOT polluted")

	-- Cross-character safety: switching to Warrior immediately stops treating BoP Plate (92001) as junk,
	-- while wrong-class Priest Cloth (92004) remains unusable!
	curClass = "WARRIOR"
	local wCount, wValue = ns.MerchantTools.JunkValue()
	assert(wCount == 1 and wValue == 1800, ("Warrior keeps Plate, sells Priest Cloth: got %d / %d"):format(wCount, wValue))
	curClass = "MAGE"

	-- ShowJunkMenu lists the two currently-carried unusable items; clicking one exempts it via keep!
	local popupData
	ns.ShowPopupList = function(_, build) popupData = build() end
	items:ShowJunkMenu()
	local clickedEntry
	for _, entry in ipairs(popupData.items) do
		if entry.onClick and entry.text and entry.text:find("92001") then clickedEntry = entry end
	end
	assert(clickedEntry, "ShowJunkMenu includes never-usable bound bag item 92001")
	clickedEntry.onClick()
	assert(items.db.keep[92001] == true, "clicking unusable item in ShowJunkMenu moves it to keep")
	local cAfterKeep, vAfterKeep = ns.MerchantTools.JunkValue()
	assert(cAfterKeep == 1 and vAfterKeep == 1800, "kept unusable item is excluded from selling")

	-- Middle-click (ToggleJunk) on slot 4 unmarks it into keep; second toggle re-enables selling!
	local toggleJunk = uv(ForeverPlus_ToggleJunkUnderMouse, "ToggleJunk")
	toggleJunk(0, 4)
	assert(items.db.keep[92004] == true, "ToggleJunk exempts unusable bound item via keep")
	assert(select(1, ns.MerchantTools.JunkValue()) == 0, "both exempted -> 0 junk")
	toggleJunk(0, 4)
	assert(not items.db.keep[92004], "second ToggleJunk removes exemption")
	assert(select(1, ns.MerchantTools.JunkValue()) == 1, "re-enabled unusable item counts again")

	-- Disabling the option immediately stops treating unusable bound gear as junk!
	items.db.markUnusableBound = false
	assert(select(1, ns.MerchantTools.JunkValue()) == 0, "option off disables automatic unusable bound selling")

	-- Restore
	for id = 92001, 92010 do items.db.junk[id] = nil; items.db.keep[id] = nil end
	UnitClass, C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemQualityByID = saved[1], saved[2], saved[3], saved[4]
	C_Item.IsBoundToAccountUntilEquip, C_Item.DoesItemExist, ItemLocation = saved[5], saved[6], saved[7]
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = saved[8], saved[9]
	C_Container.GetContainerItemQuestInfo, C_Container.GetContainerItemPurchaseInfo = saved[10], saved[11]
	C_Container.GetBackpackSellJunkDisabled, C_Container.GetBagSlotFlag = saved[12], saved[13]
	C_Container.UseContainerItem, C_TooltipInfo.GetBagItem = saved[14], saved[15]
	ITEM_CLASSES_ALLOWED, ITEM_RACES_ALLOWED, BIND_TRADE_TIME_REMAINING = saved[16], saved[17], saved[18]
	Enum.TooltipDataLineType, issecretvalue, ns.ShowPopupList = saved[19], saved[20], saved[21]
	items.db.markUnusableBound, items.db.junkPerCharacter, items.db.markMessage = saved[22], saved[23], saved[24]
	items.classRestrictionPattern, items.raceRestrictionPattern, items.tradeTimePattern = saved[25], saved[26], saved[27]
	print("never-usable soulbound gear OK")
end)()


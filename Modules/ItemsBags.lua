-- Items: bag and loot button decoration, junk marking, junk list and bag menu.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local BagComparisonState, BagExcludesJunk, ClearWeighCaches = P.BagComparisonState, P.BagExcludesJunk, P.ClearWeighCaches
local ClearWeights, IsJunkItem, IsKept, JunkKey, JunkLists = P.ClearWeights, P.IsJunkItem, P.IsKept, P.JunkKey, P.JunkLists
local LinkUpgradeState, Report = P.LinkUpgradeState, P.Report

---------------------------------------------------------------------------
-- Bag and loot button decoration
---------------------------------------------------------------------------
local function SetUpgradeArrow(arrow, state)
	if not state then
		if not arrow.IsShown or arrow:IsShown() then
			arrow:SetShown(false)
		end
		return
	end
	if arrow.fpState ~= state then
		arrow.fpState = state
		arrow:SetDesaturated(state == "later")
		arrow:SetAlpha(state == "later" and 0.75 or 1)
	end
	if not arrow.IsShown or not arrow:IsShown() then
		arrow:SetShown(true)
	end
end

-- Rotate and tint the same atlas on addon-owned textures. Recycled rows restore the original
-- color and orientation when they next show an upgrade.
function ns.SetItemComparisonArrow(arrow, state, laterAlpha)
	if state and arrow.fpComparisonState ~= state then
		arrow.fpComparisonState = state
		local worse = state == "worse"
		local accent = worse and 0.12 or 1
		arrow:SetDesaturated(worse or state == "later")
		arrow:SetVertexColor(1, accent, accent)
		arrow:SetRotation(worse and math.pi or 0)
		if laterAlpha then
			arrow:SetAlpha(state == "later" and laterAlpha or 1)
		end
	end
	arrow:SetShown(not not state)
end

local bagDowngradeArrows = setmetatable({}, { __mode = "k" })

local function UpdateButton(button, excludedBags)
	local bag, slot = button:GetBagID(), button:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)

	-- Grey and white items: the action button frame (Visuals, option); the hook on the quality alone does not
	-- reach the bag buttons, this loop does.
	if ns.FrameItemButton then
		ns.FrameItemButton(button, info and info.quality)
	end

	if button.JunkIcon then
		-- Coin on everything that will be sold: grey items, never-usable bound gear (unless kept) and marked items.
		local show = false
		if info and not info.hasNoValue and IsJunkItem(info, bag, slot) then
			local excluded = excludedBags and excludedBags[bag]
			if excluded == nil then
				excluded = BagExcludesJunk(bag) and true or false
				if excludedBags then
					excludedBags[bag] = excluded
				end
			end
			show = not excluded
		end
		if not button.JunkIcon.IsShown or button.JunkIcon:IsShown() ~= show then
			button.JunkIcon:SetShown(show)
		end
	end

	if button.UpgradeIcon then
		-- Top right, so it does not cover the junk coin at the top left.
		if not button.fpUpgradeMoved then
			button.fpUpgradeMoved = true
			button.UpgradeIcon:ClearAllPoints()
			button.UpgradeIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		end
		local show = false
		if Items.db.upgradeArrow and info and info.hyperlink and C_Item.IsEquippableItem(info.hyperlink) then
			show = BagComparisonState(bag, slot, info.hyperlink)
		end
		local worse = show == "worse"
		SetUpgradeArrow(button.UpgradeIcon, not worse and show)
		local arrow = bagDowngradeArrows[button]
		if worse and not arrow then
			arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
			arrow:SetAtlas("bags-greenarrow", true)
			arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT")
			bagDowngradeArrows[button] = arrow
		end
		if arrow then
			ns.SetItemComparisonArrow(arrow, worse and show)
		end
	end
end

local function UpdateContainerFrame(frame)
	if not frame:IsShown() then
		return
	end
	local excludedBags = {}
	P.weighStart, P.weighDone, P.weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		UpdateButton(button, excludedBags)
	end
	P.weighActive = false
	if P.weighDeferred then
		P.weighDeferred = false
		ns.After("Items: UpdateContainerFrame (timer)", 0.05, function()
			UpdateContainerFrame(frame)
		end)
	end
end

local function UpdateAllBags()
	if ContainerFrameCombinedBags then
		UpdateContainerFrame(ContainerFrameCombinedBags)
	end
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		UpdateContainerFrame(frame)
	end
end

local lootArrows = {}
local lootWaitingForData = false

local function UpdateLootRow(row, data)
	local state = false
	if Items.db.upgradeArrow and row.Item and GetLootSlotType(data.slotIndex) == Enum.LootSlotType.Item then
		local link = GetLootSlotLink(data.slotIndex)
		state = LinkUpgradeState(link)
		if state == nil then
			lootWaitingForData = true
			if not C_Item.IsItemDataCachedByID(link) then
				C_Item.RequestLoadItemDataByID(link)
			end
		end
	end
	local arrow = lootArrows[row]
	if state and not arrow then
		arrow = row.Item:CreateTexture(nil, "OVERLAY", nil, 7)
		arrow:SetAtlas("bags-greenarrow", true)
		arrow:SetPoint("TOPRIGHT", row.Item, "TOPRIGHT")
		lootArrows[row] = arrow
	end
	if arrow then
		ns.SetItemComparisonArrow(arrow, state, 0.75)
	end
end

local function UpdateLootUpgrades()
	lootWaitingForData = false
	if LootFrame and LootFrame.ScrollBox and LootFrame:IsShown() then
		LootFrame.ScrollBox:ForEachFrame(UpdateLootRow)
	end
end

local function OnLootItemData(_, _, _, success)
	if success and lootWaitingForData then
		UpdateLootUpgrades()
	end
end

local function UsesGearScores()
	local db = Items.db
	return db.upgradeArrow or db.upgradePopup or db.upgradeScore or db.rewardUpgrade or db.markWorseReward
end

-- Coalesce bursts of talent and level changes.
local weighRefreshQueued = false
local function QueueWeighRefresh()
	if weighRefreshQueued then
		return
	end
	weighRefreshQueued = true
	ns.After("Items: QueueWeighRefresh (timer)", 0.5, function()
		weighRefreshQueued = false
		ClearWeights()
		ClearWeighCaches()
		local statRank = ns:GetModule("StatRank")
		if statRank and statRank.db.enabled then
			statRank.Refresh()
		end
		if UsesGearScores() then
			UpdateAllBags()
		end
		UpdateLootUpgrades()
	end)
end

local hookedButtons = {}

local function ToggleJunk(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then
		return
	end
	-- Grey items and never-usable bound gear are junk by default: toggling stores an exception instead.
	local junk, keep = JunkLists()
	local isAuto = info.quality == Enum.ItemQuality.Poor or Items.IsNeverUsableBoundGear(info, bag, slot)
	local list = isAuto and keep or junk
	local key, value = JunkKey(info)
	if list[key] then
		list[key] = nil
	else
		list[key] = value
	end
	if isAuto then
		junk[key] = nil
	end
	Report("markMessage", IsJunkItem(info, bag, slot) and L.ITEMS_MARKED or L.ITEMS_UNMARKED, info.hyperlink)
	UpdateAllBags()
end

-- Marks an item (by link) for sale, e.g. the item an upgrade replaced; grey items are junk anyway.
function Items.MarkLinkJunk(link)
	local itemID = link and C_Item.GetItemInfoInstant(link)
	local quality = itemID and select(3, C_Item.GetItemInfo(link))
	if not itemID or quality == Enum.ItemQuality.Poor then
		return
	end
	local junk = JunkLists()
	local key, value = JunkKey({ itemID = itemID, hyperlink = link })
	if not junk[key] then
		junk[key] = value
		Report("markMessage", L.ITEMS_MARKED, link)
		UpdateAllBags()
	end
end

-- Marks/unmarks junk with the configured mouse button (middle button by default).
-- OnMouseUp also fires for buttons the item button is not registered to click with.
local function OnItemMouseUp(button, mouseButton)
	-- Alt + middle click marks for the restock list instead.
	local restock = mouseButton == "MiddleButton" and IsAltKeyDown() and ns:GetModule("Restock")
	if restock and restock:ClaimsAltMiddleClick() then
		return
	end
	if mouseButton == Items.db.junkButton and button:IsMouseOver() then
		ToggleJunk(button:GetBagID(), button:GetID())
	end
end

-- Key binding (Bindings.xml): toggles the bag item under the mouse.
function ForeverPlus_ToggleJunkUnderMouse()
	local frame = GetMouseFoci()[1]
	while frame and not frame:IsForbidden() do
		-- Item buttons only (bag windows have GetBagID too).
		if frame.JunkIcon and frame.GetBagID then
			local bag = frame:GetBagID()
			if bag then
				ToggleJunk(bag, frame:GetID())
			end
			return
		end
		frame = frame:GetParent()
	end
end

---------------------------------------------------------------------------
-- Junk list: every marked item, click removes the mark
---------------------------------------------------------------------------
local function KeyItemID(key)
	return tonumber(key) or tonumber(tostring(key):match("^(%d+)"))
end

-- Icon, coloured name and sort name of a junk list entry.
local function JunkEntry(key, value)
	local itemID = KeyItemID(key)
	local icon = itemID and C_Item.GetItemIconByID(itemID)
	if type(value) == "string" then
		-- Suffix items: the stored link carries the full coloured name.
		local name = value:match("%[(.-)%]") or value
		return icon, value:gsub("|H.-|h(.-)|h", "%1"), name
	end
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		name = ("item:%d"):format(itemID)
	end
	local sortName = name
	local quality = C_Item.GetItemQualityByID(itemID)
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		name = CreateColor(r, g, b):WrapTextInColorCode(name)
	end
	return icon, name, sortName
end

local function AddJunkItems(items, list, onRemove)
	local entries = {}
	for key, value in pairs(list) do
		local icon, text, sortName = JunkEntry(key, value)
		entries[#entries + 1] = { id = key, value = value, icon = icon, text = text, sortName = sortName }
	end
	table.sort(entries, function(a, b)
		return a.sortName < b.sortName
	end)
	for _, entry in ipairs(entries) do
		items[#items + 1] = {
			icon = entry.icon,
			text = entry.text,
			onClick = function()
				list[entry.id] = nil
				onRemove(entry.id, entry.value)
			end,
			tooltip = function(tooltip)
				if type(entry.value) == "string" then
					tooltip:SetHyperlink(entry.value)
				else
					tooltip:SetItemByID(KeyItemID(entry.id))
				end
				GameTooltip_AddInstructionLine(tooltip, L.ITEMS_JUNK_REMOVE_HINT)
			end,
		}
	end
	return #entries
end

-- Popup at the owner (settings button) or at the cursor (/fp schrott).
do
	-- Collects currently carried never-usable soulbound armor/weapons (excluding kept items and bags
	-- excluded from junk selling) as key -> value entries for the junk list popup.
	local function CollectUnusableBagJunk()
		local list = {}
		if not (Items.db and Items.db.markUnusableBound) then
			return list
		end
		for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
			local slots = BagExcludesJunk(bag) and 0 or ns.Number(C_Container.GetContainerNumSlots(bag), 0)
			for slot = 1, slots do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and not info.hasNoValue and Items.IsNeverUsableBoundGear(info, bag, slot) and not IsKept(info) then
					local key, value = JunkKey(info)
					if not list[key] then
						list[key] = value
					end
				end
			end
		end
		return list
	end

	function Items:ShowJunkMenu(owner)
		ns.ShowPopupList(owner, function()
			local items = {}
			local junk, keep = JunkLists()
			local allUnusable = CollectUnusableBagJunk()
			-- A grey or currently carried never-usable bound item taken off the junk list would still be
			-- sold automatically; it moves to the kept list instead.
			local marked = AddJunkItems(items, junk, function(key, value)
				if C_Item.GetItemQualityByID(KeyItemID(key)) == Enum.ItemQuality.Poor or allUnusable[key] then
					keep[key] = value
				end
				UpdateAllBags()
			end)
			local unusableOnly = {}
			for key, value in pairs(allUnusable) do
				if not junk[key] then
					unusableOnly[key] = value
				end
			end
			if next(unusableOnly) then
				items[#items + 1] = { text = L.ITEMS_JUNK_UNUSABLE }
				AddJunkItems(items, unusableOnly, function(key, value)
					keep[key] = value
					UpdateAllBags()
				end)
			end
			if next(keep) then
				items[#items + 1] = { text = L.ITEMS_JUNK_KEPT }
			end
			local kept = AddJunkItems(items, keep, UpdateAllBags)
			local footer
			if marked + kept > 0 then
				footer = { { text = L.ITEMS_CLEAR_JUNK, onClick = function()
					wipe(junk)
					wipe(keep)
					UpdateAllBags()
				end } }
			end
			return { title = L.ITEMS_JUNK_LIST, items = items, empty = L.ITEMS_JUNK_NONE, footer = footer }
		end)
	end
end

---------------------------------------------------------------------------
-- Right-click on the bag symbol (portrait) of an open bag: menu with the
-- settings that concern the bags.
---------------------------------------------------------------------------
local MENU_SECTIONS_BAG = {
	{ L.ITEMS_BAGS, { { "Items", "autoSort", "ITEMS_AUTOSORT" }, { "Items", "moneyPickup", "ITEMS_MONEY_PICKUP" },
		{ "BankView", "enabled", "BANKVIEW_ENABLE" } } },
	{ L.ITEMS_DISPLAY, {
		{ "Items", "upgradeArrow", "ITEMS_UPGRADE" }, { "Items", "rewardUpgrade", "ITEMS_REWARD_UPGRADE" }, { "Items", "upgradeScore", "ITEMS_SCORE" },
		{ "Items", "upgradePopup", "ITEMS_UPGRADE_POPUP" },
	} },
	{ L.ITEMS_MERCHANT, {
		{ "Items", "autoSell", "ITEMS_AUTOSELL" }, { "Items", "sellButton", "ITEMS_SELL_BUTTON" },
		{ "Items", "autoRepair", "ITEMS_AUTOREPAIR" },
	} },
}

local MENU_SECTIONS_MERCHANT = {
	{ L.ITEMS_MERCHANT, {
		{ "Items", "autoSell", "ITEMS_AUTOSELL" }, { "Items", "autoRepair", "ITEMS_AUTOREPAIR" },
		{ "Items", "repairGuild", "ITEMS_REPAIR_GUILD" }, { "Items", "sellButton", "ITEMS_SELL_BUTTON" },
		{ "Items", "junkPerCharacter", "ITEMS_JUNK_PER_CHAR" },
	} },
}

local function MenuItems(sections, owner, menuKey)
	local items = {}
	for _, section in ipairs(sections) do
		items[#items + 1] = { text = section[1] }
		for _, entry in ipairs(section[2]) do
			local module = ns:GetModule(entry[1])
			local key, name, desc = entry[2], L[entry[3]], L[entry[3] .. "_DESC"]
			if module and module.db and name then
				items[#items + 1] = {
					text = name,
					checked = module.db[key] and true or false,
					onClick = function()
						module.db[key] = not module.db[key]
						if module.OnOptionChanged then
							module:OnOptionChanged(key, module.db[key])
						end
					end,
					tooltip = desc and function(tooltip)
						tooltip:SetText(name, 1, 1, 1)
						tooltip:AddLine(desc, nil, nil, nil, true)
					end,
				}
			end
		end
	end
	items[#items + 1] = { text = L.ITEMS_JUNK_LIST }
	items[#items + 1] = { text = L.ITEMS_JUNK_SHOW, onClick = function()
		local menu = _G["ForeverPlusPopup" .. menuKey]
		if menu then
			menu:Hide()
		end
		ns.After("Items: onClick (timer)", 0, function()
			Items:ShowJunkMenu(owner)
		end)
	end }
	items[#items + 1] = { text = L.ITEMS_BAG_MENU_ALL, onClick = function()
		ns:OpenSettings(Items)
	end }
	return items
end

function Items:ShowBagMenu(owner)
	ns.ShowPopupList(owner, function()
		return { title = L.ITEMS_BAG_MENU_TITLE, items = MenuItems(MENU_SECTIONS_BAG, owner, "BagMenu"), width = 340 }
	end, "BagMenu")
end

function Items:ShowMerchantMenu(owner)
	ns.ShowPopupList(owner, function()
		return { title = L.ITEMS_MERCHANT_MENU_TITLE, items = MenuItems(MENU_SECTIONS_MERCHANT, owner, "MerchantMenu"), width = 340 }
	end, "MerchantMenu")
end

local bagMenuHooked = {}

local function HookBagMenu(owner, frame)
	if not owner or bagMenuHooked[owner] then
		return
	end
	bagMenuHooked[owner] = true
	owner:HookScript("OnMouseDown", function(self, button)
		if button ~= "RightButton" or not Items.db.bagMenu then
			return
		end
		-- Blizzard's own menu (opened by any button on the title bar) makes room for ours.
		if frame.PortraitButton and frame.PortraitButton.CloseMenu then
			frame.PortraitButton:CloseMenu()
		end
		Items:ShowBagMenu(frame.PortraitButton or self)
	end)
end

local function HookBagFrameMenu(frame)
	if not frame or not frame.PortraitButton then
		return
	end
	HookBagMenu(frame.PortraitButton, frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.routeToSibling == "PortraitButton" then
			HookBagMenu(child, frame)
		end
	end
end

local function PostUpdateItems(frame)
	local excludedBags = {}
	P.weighStart, P.weighDone, P.weighActive = debugprofilestop(), 0, true
	for _, button in frame:EnumerateValidItems() do
		if not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnMouseUp", OnItemMouseUp)
		end
		UpdateButton(button, excludedBags)
	end
	P.weighActive = false
	if P.weighDeferred then
		P.weighDeferred = false
		ns.After("Items: PostUpdateItems (timer)", 0.05, function()
			UpdateContainerFrame(frame)
		end)
	end
end

-- For the Items*.lua files loaded after this one.
P.HookBagFrameMenu = HookBagFrameMenu
P.OnLootItemData = OnLootItemData
P.PostUpdateItems = PostUpdateItems
P.QueueWeighRefresh = QueueWeighRefresh
P.UpdateAllBags = UpdateAllBags
P.UpdateLootRow = UpdateLootRow
P.UpdateLootUpgrades = UpdateLootUpgrades
P.UsesGearScores = UsesGearScores

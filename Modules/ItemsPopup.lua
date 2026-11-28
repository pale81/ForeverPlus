-- Items: upgrade popup (loot toast) for new items in the bags.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local CanUse, CompareScores, EquippedScore = P.CanUse, P.CompareScores, P.EquippedScore

---------------------------------------------------------------------------
-- Upgrade popup: a new item in the bags (loot, quest reward, purchase) that
-- is better than the equipped one is offered for equipping, one at a time.
---------------------------------------------------------------------------
local offered = {}      -- item GUID or link -> true once checked
local upgradeQueue = {} -- { link, score, equippedScore, invSlot }
local bagsSeen = false  -- the first scan after login only records the items


-- Equipped slot the item would replace: the weaker of two (rings, trinkets).
local function TargetSlot(link)
	local slots = ns.EquipSlots(select(4, C_Item.GetItemInfoInstant(link)))
	if not slots then
		return nil
	end
	local target, lowest = slots[1], nil
	for _, invSlot in ipairs(slots) do
		local value = EquippedScore(invSlot)
		if value and (not lowest or value < lowest) then
			target, lowest = invSlot, value
		end
	end
	return target
end

local ShowNextUpgrade

-- The window is the game's loot toast (its artwork, item border, glow, sheen and rising arrows) with the gain big
-- between heading and name; the two buttons sit under it.
local TOAST_BORDER = { [0] = "gray", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }

-- The gain over the worn item in percent (nil for an empty slot) and the title line of the toast.
function Items.UpgradeGain(score, equippedScore)
	if equippedScore and equippedScore > 0 then
		return (score / equippedScore - 1) * 100
	end
end

local function SetAtlasOr(texture, atlas, fallback)
	if C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, true)
		return true
	end
	if fallback then
		fallback()
	end
	return false
end

local TOAST_FILE = [[Interface\LootFrame\LootToast]]

local function CreateUpgradeFrame()
	-- The size and artwork of the game's loot toast (276 x 96), a little bigger.
	local frame = CreateFrame("Button", "ForeverPlusUpgradeFrame", UIParent)
	frame:SetSize(276, 96)
	frame:SetScale(1.25)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("RightButtonUp")
	frame:Hide()
	-- Escape closes it like the panel before.
	tinsert(UISpecialFrames, "ForeverPlusUpgradeFrame")

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints()
	frame.Background:SetTexture(TOAST_FILE)
	frame.Background:SetTexCoord(0.28222656, 0.55175781, 0.578125, 0.953125)

	frame.Icon = frame:CreateTexture(nil, "BORDER", nil, 1)
	frame.Icon:SetSize(50, 50)
	frame.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -23)
	frame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.Border = frame:CreateTexture(nil, "BORDER", nil, 2)
	frame.Border:SetPoint("CENTER", frame.Icon, "CENTER")
	frame.Glow = frame:CreateTexture(nil, "BORDER", nil, 4)
	frame.Glow:SetPoint("CENTER", frame.Icon, "CENTER")
	frame.Glow:SetBlendMode("ADD")
	frame.Glow:SetAlpha(0)
	SetAtlasOr(frame.Glow, "loottoast-itemborder-glow")

	-- Pointing at the icon shows the item and the rating comparison.
	local hit = CreateFrame("Frame", nil, frame)
	hit:SetAllPoints(frame.Icon)
	hit:SetScript("OnEnter", function(self)
		local entry = upgradeQueue[1]
		if entry then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(entry.link)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(entry.equippedScore and entry.equippedScore > 0
				and L.ITEMS_UPGRADE_POPUP_SCORE:format(entry.score, entry.equippedScore)
				or L.ITEMS_UPGRADE_POPUP_SCORE_NEW:format(entry.score), 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	hit:SetScript("OnLeave", GameTooltip_Hide)

	-- Like the game's toast: a yellow heading, the item name under it, both centred next to the icon.
	frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 8, 8)
	frame.Title:SetPoint("RIGHT", -18, 0)
	frame.Title:SetJustifyH("CENTER")
	frame.Title:SetWordWrap(false)
	-- The gain sits between heading and name, big and green, and pops up with a little overshoot; it has its own frame
	-- so it can scale.
	frame.GainBox = CreateFrame("Frame", nil, frame)
	frame.GainBox:SetHeight(24)
	frame.GainBox:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -1)
	frame.GainBox:SetPoint("RIGHT", -18, 0)
	frame.Gain = frame.GainBox:CreateFontString(nil, "OVERLAY")
	frame.Gain:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
	frame.Gain:SetPoint("CENTER")
	frame.Gain:SetTextColor(0.3, 1, 0.3)
	frame.Gain:SetShadowColor(0, 0, 0, 0.8)
	frame.Gain:SetShadowOffset(1, -1)
	frame.Name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	frame.Name:SetJustifyH("CENTER")
	frame.Name:SetWordWrap(false)
	-- Like the game's upgrade toast, the name flashes white once.
	frame.NameFlash = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	frame.NameFlash:SetJustifyH("CENTER")
	frame.NameFlash:SetWordWrap(false)
	frame.NameFlash:SetTextColor(1, 1, 1)
	frame.NameFlash:SetAlpha(0)
	frame.Replaces = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.Replaces:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -3)
	frame.Replaces:SetPoint("RIGHT", -18, 0)
	frame.Replaces:SetJustifyH("CENTER")
	frame.Replaces:SetWordWrap(false)
	frame.GainPop = frame.GainBox:CreateAnimationGroup()
	frame.GainPop:SetToFinalAlpha(true)
	local popFade = frame.GainPop:CreateAnimation("Alpha")
	popFade:SetFromAlpha(0)
	popFade:SetToAlpha(1)
	popFade:SetDuration(0.15)
	popFade:SetStartDelay(0.25)
	popFade:SetOrder(1)
	for order, step in ipairs({ { 0.4, 1.3, 0.2 }, { 1.3, 1, 0.14 } }) do
		local from, to, duration = step[1], step[2], step[3]
		local pop = frame.GainPop:CreateAnimation("Scale")
		pop:SetOrigin("CENTER", 0, 0)
		if pop.SetScaleFrom then
			pop:SetScaleFrom(from, from)
			pop:SetScaleTo(to, to)
		else
			pop:SetFromScale(from, from)
			pop:SetToScale(to, to)
		end
		pop:SetDuration(duration)
		pop:SetOrder(order)
		if order == 1 then
			pop:SetStartDelay(0.25)
		end
	end

	-- The game's flash over the toast and the sheen that sweeps across it.
	frame.Flash = frame:CreateTexture(nil, "OVERLAY")
	frame.Flash:SetPoint("CENTER")
	frame.Flash:SetBlendMode("ADD")
	frame.Flash:SetAlpha(0)
	SetAtlasOr(frame.Flash, "loottoast-glow")
	frame.Sheen = frame:CreateTexture(nil, "OVERLAY")
	frame.Sheen:SetPoint("BOTTOMLEFT", -10, 12)
	frame.Sheen:SetBlendMode("ADD")
	frame.Sheen:SetAlpha(0)
	SetAtlasOr(frame.Sheen, "loottoast-sheen", function()
		frame.Sheen:SetSize(171, 75)
		frame.Sheen:SetTexture(TOAST_FILE)
		frame.Sheen:SetTexCoord(0.56347656, 0.73046875, 0.57421875, 0.86718750)
	end)
	-- Sparkles in the quality colour: small stars that twinkle one after another at random places on the toast.
	frame.Sparkles = {}
	for index = 1, 10 do
		local star = frame:CreateTexture(nil, "OVERLAY", nil, 2)
		star:SetTexture([[Interface\Cooldown\star4]])
		star:SetBlendMode("ADD")
		star:SetSize(14 + (index % 3) * 6, 14 + (index % 3) * 6)
		star:SetAlpha(0)
		frame.Sparkles[index] = star
	end

	-- In: fades in while sliding up a little; the arrows rise over the icon one after another, the border glows.
	frame.In = frame:CreateAnimationGroup()
	frame.In:SetToFinalAlpha(true)
	local fade = frame.In:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.25)
	local slide = frame.In:CreateAnimation("Translation")
	slide:SetOffset(0, 12)
	slide:SetDuration(0.25)
	slide:SetSmoothing("OUT")
	frame.Celebrate = frame:CreateAnimationGroup()
	frame.Celebrate:SetToFinalAlpha(true)
	local glowIn = frame.Celebrate:CreateAnimation("Alpha")
	glowIn:SetTarget(frame.Glow)
	glowIn:SetStartDelay(0.2)
	glowIn:SetFromAlpha(0)
	glowIn:SetToAlpha(1)
	glowIn:SetDuration(0.6)
	glowIn:SetSmoothing("IN")
	local glowOut = frame.Celebrate:CreateAnimation("Alpha")
	glowOut:SetTarget(frame.Glow)
	glowOut:SetStartDelay(0.9)
	glowOut:SetFromAlpha(1)
	glowOut:SetToAlpha(0)
	glowOut:SetDuration(0.8)
	local nameIn = frame.Celebrate:CreateAnimation("Alpha")
	nameIn:SetTarget(frame.NameFlash)
	nameIn:SetStartDelay(0.2)
	nameIn:SetSmoothing("IN")
	nameIn:SetFromAlpha(0)
	nameIn:SetToAlpha(0.9)
	nameIn:SetDuration(0.5)
	local nameOut = frame.Celebrate:CreateAnimation("Alpha")
	nameOut:SetTarget(frame.NameFlash)
	nameOut:SetStartDelay(0.7)
	nameOut:SetFromAlpha(0.9)
	nameOut:SetToAlpha(0)
	nameOut:SetDuration(0.7)
	for index, star in ipairs(frame.Sparkles) do
		local delay = 0.3 + (index - 1) * 0.13
		local show = frame.Celebrate:CreateAnimation("Alpha")
		show:SetTarget(star)
		show:SetStartDelay(delay)
		show:SetFromAlpha(0)
		show:SetToAlpha(1)
		show:SetDuration(0.15)
		local hide = frame.Celebrate:CreateAnimation("Alpha")
		hide:SetTarget(star)
		hide:SetStartDelay(delay + 0.15)
		hide:SetFromAlpha(1)
		hide:SetToAlpha(0)
		hide:SetDuration(0.35)
		local turn = frame.Celebrate:CreateAnimation("Rotation")
		turn:SetTarget(star)
		turn:SetStartDelay(delay)
		turn:SetDegrees(-70)
		turn:SetDuration(0.5)
	end
	local flashIn = frame.Celebrate:CreateAnimation("Alpha")
	flashIn:SetTarget(frame.Flash)
	flashIn:SetFromAlpha(0)
	flashIn:SetToAlpha(1)
	flashIn:SetDuration(0.2)
	local flashOut = frame.Celebrate:CreateAnimation("Alpha")
	flashOut:SetTarget(frame.Flash)
	flashOut:SetFromAlpha(1)
	flashOut:SetToAlpha(0)
	flashOut:SetStartDelay(0.2)
	flashOut:SetDuration(0.5)
	local sheenIn = frame.Celebrate:CreateAnimation("Alpha")
	sheenIn:SetTarget(frame.Sheen)
	sheenIn:SetStartDelay(0.1)
	sheenIn:SetFromAlpha(0)
	sheenIn:SetToAlpha(1)
	sheenIn:SetDuration(0.1)
	local sheenMove = frame.Celebrate:CreateAnimation("Translation")
	sheenMove:SetTarget(frame.Sheen)
	sheenMove:SetStartDelay(0.1)
	sheenMove:SetOffset(165, 0)
	sheenMove:SetDuration(0.5)
	local sheenOut = frame.Celebrate:CreateAnimation("Alpha")
	sheenOut:SetTarget(frame.Sheen)
	sheenOut:SetStartDelay(0.3)
	sheenOut:SetFromAlpha(1)
	sheenOut:SetToAlpha(0)
	sheenOut:SetDuration(0.25)
	frame.Arrows = {}
	for index, x in ipairs({ 0, 16, -16, 5, -12 }) do
		local arrow = frame:CreateTexture(nil, "ARTWORK")
		arrow:SetPoint("CENTER", frame.Icon, "CENTER", x, -8)
		arrow:SetAlpha(0)
		frame.Arrows[index] = arrow
		local delay = 0.4 + (index - 1) * 0.12
		local show = frame.Celebrate:CreateAnimation("Alpha")
		show:SetTarget(arrow)
		show:SetStartDelay(delay)
		show:SetFromAlpha(0)
		show:SetToAlpha(1)
		show:SetDuration(0.2)
		local hide = frame.Celebrate:CreateAnimation("Alpha")
		hide:SetTarget(arrow)
		hide:SetStartDelay(delay + 0.3)
		hide:SetFromAlpha(1)
		hide:SetToAlpha(0)
		hide:SetDuration(0.2)
		local rise = frame.Celebrate:CreateAnimation("Translation")
		rise:SetTarget(arrow)
		rise:SetStartDelay(delay)
		rise:SetOffset(0, 50)
		rise:SetDuration(0.5)
	end

	local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	equip:SetSize(132, 24)
	equip:SetPoint("TOPLEFT", frame, "BOTTOM", 3, 2)
	equip:SetText(L.ITEMS_UPGRADE_POPUP_EQUIP)
	equip:SetScript("OnClick", function()
		local entry = table.remove(upgradeQueue, 1)
		-- Only if the item is still in the bags (sorting may have moved it).
		if entry and not InCombatLockdown() and C_Item.GetItemCount(entry.link) > 0 then
			local old = Items.db.upgradeMarkOld and entry.invSlot and GetInventoryItemLink("player", entry.invSlot)
			C_Item.EquipItemByName(entry.link, TargetSlot(entry.link))
			-- The replaced item goes to the bags; with the option it is marked for sale right away.
			if old then
				Items.MarkLinkJunk(old)
			end
		end
		ShowNextUpgrade()
	end)
	local later = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	later:SetSize(132, 24)
	later:SetPoint("TOPRIGHT", frame, "BOTTOM", -3, 2)
	later:SetText(L.ITEMS_UPGRADE_POPUP_LATER)
	local function Later()
		table.remove(upgradeQueue, 1)
		ShowNextUpgrade()
	end
	later:SetScript("OnClick", Later)
	-- A right click on the toast is "not now".
	frame:SetScript("OnClick", Later)

	-- Escape closes it; the offers stay declined for this session. Hiding for combat keeps them.
	frame:SetScript("OnHide", function(self)
		if not self.combatHide then
			wipe(upgradeQueue)
		end
		self.combatHide = nil
	end)
	return frame
end

function ShowNextUpgrade()
	local entry = upgradeQueue[1]
	if not entry or InCombatLockdown() or not Items.db.upgradePopup then
		if P.upgradeFrame and not entry then
			P.upgradeFrame:Hide()
		end
		return
	end
	P.upgradeFrame = P.upgradeFrame or CreateUpgradeFrame()
	local frame = P.upgradeFrame
	local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(entry.link)
	local border = TOAST_BORDER[quality or 2] or "gold"
	frame.Icon:SetTexture(texture)
	SetAtlasOr(frame.Border, "loottoast-itemborder-" .. border)
	for _, arrow in ipairs(frame.Arrows) do
		SetAtlasOr(arrow, "loottoast-arrow-" .. ((border == "gray" or border == "white") and "green" or border))
	end
	local color = quality and ITEM_QUALITY_COLORS[quality]
	frame.Name:SetText(itemName or entry.link)
	if color then
		frame.Name:SetTextColor(color.r, color.g, color.b)
	end
	local gain = Items.UpgradeGain(entry.score, entry.equippedScore)
	frame.Title:SetText(L.ITEMS_UPGRADE_POPUP_HEAD)
	frame.Gain:SetText(gain and L.ITEMS_UPGRADE_POPUP_GAIN:format(gain) or "")
	frame.GainBox:SetShown(gain ~= nil)
	frame.Name:ClearAllPoints()
	frame.Name:SetPoint("TOPLEFT", gain and frame.GainBox or frame.Title, "BOTTOMLEFT", 0, gain and 0 or -6)
	frame.Name:SetPoint("RIGHT", -18, 0)
	frame.NameFlash:SetText(itemName or entry.link)
	frame.NameFlash:ClearAllPoints()
	frame.NameFlash:SetPoint("TOPLEFT", frame.Name, "TOPLEFT")
	frame.NameFlash:SetPoint("TOPRIGHT", frame.Name, "TOPRIGHT")
	-- The sparkle, glow and sheen take the quality colour (green for grey and white items).
	local tr, tg, tb = 0.3, 1, 0.3
	if color and quality >= 2 then
		tr, tg, tb = color.r, color.g, color.b
	end
	frame.Glow:SetVertexColor(tr, tg, tb)
	frame.Flash:SetVertexColor(tr, tg, tb)
	frame.Sheen:SetVertexColor(0.5 + tr / 2, 0.5 + tg / 2, 0.5 + tb / 2)
	for _, star in ipairs(frame.Sparkles) do
		star:SetVertexColor(0.4 + tr * 0.6, 0.4 + tg * 0.6, 0.4 + tb * 0.6)
		star:ClearAllPoints()
		star:SetPoint("CENTER", frame, "TOPLEFT", math.random(18, 258), -math.random(14, 82))
	end
	local equipped = entry.invSlot and GetInventoryItemLink("player", entry.invSlot)
	local equippedName = equipped and C_Item.GetItemInfo(equipped)
	frame.Replaces:SetText(equippedName and L.ITEMS_UPGRADE_POPUP_REPLACES:format(equippedName) or L.ITEMS_UPGRADE_POPUP_EMPTY)
	local wasShown = frame:IsShown()
	frame:Show()
	if not wasShown then
		frame.In:Stop()
		frame.In:Play()
	end
	frame.Celebrate:Stop()
	frame.GainPop:Stop()
	frame.GainBox:SetAlpha(1)
	if Items.db.upgradeCelebrate then
		frame.Celebrate:Play()
		frame.GainBox:SetAlpha(0)
		frame.GainPop:Play()
		if SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then
			PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
		end
	end
end

-- /fp aufwertung: the toast with the first piece of equipment in the bags, to see how it looks.
function Items.PreviewUpgrade()
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and C_Item.IsEquippableItem(link) then
				local score, equippedScore = CompareScores(link)
				if score then
					table.insert(upgradeQueue, 1, { link = link, score = score, equippedScore = equippedScore, invSlot = TargetSlot(link) })
					ShowNextUpgrade()
					return true
				end
			end
		end
	end
	ns.PrintAlways(L.ITEMS_UPGRADE_PREVIEW_NONE)
	return false
end

local function ItemKey(bag, slot, link)
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	local guid = C_Item.DoesItemExist(location) and C_Item.GetItemGUID(location)
	return guid or link
end

-- New items in the bags: checked once each; data still loading is retried
-- on the next bag update.
local function ScanNewItems()
	local record = not bagsSeen
	bagsSeen = true
	local added = false
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			-- The cheap question first: only new items are looked at further.
			local info = C_NewItems.IsNewItem(bag, slot) and C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and C_Item.IsEquippableItem(link) then
				local key = ItemKey(bag, slot, link)
				if not offered[key] then
					local score, equippedScore = CompareScores(link)
					if record or score == false then
						offered[key] = true
					elseif score ~= nil then
						offered[key] = true
						if score > equippedScore + 0.01 and CanUse(bag, slot) then
							upgradeQueue[#upgradeQueue + 1] = {
								link = link, score = score, equippedScore = equippedScore, invSlot = TargetSlot(link),
							}
							added = true
						end
					end
				end
			end
		end
	end
	if added and not (P.upgradeFrame and P.upgradeFrame:IsShown()) then
		ShowNextUpgrade()
	end
end

-- For the Items*.lua files loaded after this one.
P.ScanNewItems = ScanNewItems
P.ShowNextUpgrade = ShowNextUpgrade
P.upgradeQueue = upgradeQueue

-- Tooltip: health bar inside the tooltip, unit price for stacks, quality border.
local _, ns = ...
local L = ns.L

local Tooltip = ns:NewModule("Tooltip", {
	title = L.TOOLTIP_TITLE,
	order = 2,
	defaults = {
		unitPrice = true,
	},
})

local BAR_HEIGHT = 6
local BAR_INSET = 10

---------------------------------------------------------------------------
-- Health bar inside the bottom of the tooltip
---------------------------------------------------------------------------
local function SetupHealthBar()
	local bar = GameTooltip.StatusBar
	if not bar then
		return
	end
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", BAR_INSET, BAR_INSET - 2)
	bar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET - 2)
	bar:SetHeight(BAR_HEIGHT)
end

-- Reserve room for the bar with an empty last line. Done after Show, because
-- Blizzard adds lines (e.g. the right click hint) after the unit data.
local spacerLine = {}
local addingSpacer = false

local function ReserveHealthBarSpace(tooltip)
	if addingSpacer or tooltip:IsForbidden() then
		return
	end
	local bar = tooltip.StatusBar
	if not bar or not bar:IsShown() or spacerLine[tooltip] == tooltip:NumLines() then
		return
	end
	addingSpacer = true
	tooltip:AddLine(" ")
	spacerLine[tooltip] = tooltip:NumLines()
	tooltip:Show()
	addingSpacer = false
end

local function ClearSpacer(tooltip)
	spacerLine[tooltip] = nil
end

---------------------------------------------------------------------------
-- Unit price for stacks
---------------------------------------------------------------------------
local stackCountGetters = {
	GetBagItem = function(bag, slot)
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount
	end,
	GetInventoryItem = function(unit, slot)
		return GetInventoryItemCount(unit, slot)
	end,
	GetMerchantItem = function(index)
		local info = C_MerchantFrame.GetItemInfo(index)
		return info and info.stackCount, info and info.price
	end,
	GetLootItem = function(slot)
		local _, _, quantity = GetLootSlotInfo(slot)
		return quantity
	end,
}

local function AddUnitPrice(tooltip, data)
	if not Tooltip.db.unitPrice or tooltip.isShopping then
		return
	end
	local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
	local getter = info and info.getterName and stackCountGetters[info.getterName]
	if not getter then
		return
	end
	local count, stackPrice = getter(unpack(info.getterArgs or {}))
	if not count or count <= 1 then
		return
	end

	local unitPrice
	if stackPrice then
		unitPrice = floor(stackPrice / count)
	else
		local itemID = data and data.id
		local sellPrice = itemID and select(11, C_Item.GetItemInfo(itemID))
		unitPrice = sellPrice
	end
	if unitPrice and unitPrice > 0 then
		tooltip:AddDoubleLine(L.TOOLTIP_UNIT_PRICE, GetMoneyString(unitPrice, true), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Border coloured by item quality
---------------------------------------------------------------------------
local defaultBorder = {}
local borderFrames = {}

local BORDER_PIXELS = 2

-- Crisp solid frame in quality colour along the tooltip edge. The corners are
-- cut by one pixel step so they look slightly rounded.
local function GetBorderFrame(tooltip)
	local frame = borderFrames[tooltip]
	if not frame then
		frame = CreateFrame("Frame", nil, tooltip)
		frame:SetAllPoints(tooltip.NineSlice)
		frame:SetFrameLevel(tooltip:GetFrameLevel() + 1)
		frame.parts = {}
		for i = 1, 8 do
			local part = frame:CreateTexture(nil, "OVERLAY")
			part:SetColorTexture(1, 1, 1)
			frame.parts[i] = part
		end
		borderFrames[tooltip] = frame
	end
	return frame
end

local function LayoutBorder(frame, size)
	local top, bottom, left, right, tl, tr, bl, br = unpack(frame.parts)
	local half = size / 2
	for _, part in ipairs(frame.parts) do
		part:ClearAllPoints()
	end
	top:SetPoint("TOPLEFT", size, 0)
	top:SetPoint("TOPRIGHT", -size, 0)
	top:SetHeight(size)
	bottom:SetPoint("BOTTOMLEFT", size, 0)
	bottom:SetPoint("BOTTOMRIGHT", -size, 0)
	bottom:SetHeight(size)
	left:SetPoint("TOPLEFT", 0, -size)
	left:SetPoint("BOTTOMLEFT", 0, size)
	left:SetWidth(size)
	right:SetPoint("TOPRIGHT", 0, -size)
	right:SetPoint("BOTTOMRIGHT", 0, size)
	right:SetWidth(size)
	-- Corner pieces moved half a line inwards close the gap diagonally.
	tl:SetPoint("TOPLEFT", half, -half)
	tr:SetPoint("TOPRIGHT", -half, -half)
	bl:SetPoint("BOTTOMLEFT", half, half)
	br:SetPoint("BOTTOMRIGHT", -half, half)
	for i = 5, 8 do
		frame.parts[i]:SetSize(size, size)
	end
end

local function ShowBorderFrame(tooltip, r, g, b)
	local frame = GetBorderFrame(tooltip)
	-- Exactly BORDER_PIXELS screen pixels at any UI or tooltip scale.
	local size = PixelUtil.GetNearestPixelSize(BORDER_PIXELS, frame:GetEffectiveScale(), BORDER_PIXELS)
	if frame.size ~= size then
		frame.size = size
		LayoutBorder(frame, size)
	end
	for _, part in ipairs(frame.parts) do
		part:SetVertexColor(r, g, b, 1)
	end
	frame:Show()
end

local function ResetBorder(tooltip)
	local color = defaultBorder[tooltip]
	if color and tooltip.NineSlice then
		tooltip.NineSlice:SetBorderColor(color[1], color[2], color[3], color[4])
	end
	if borderFrames[tooltip] then
		borderFrames[tooltip]:Hide()
	end
end

local function ColorBorder(tooltip, data)
	local nineSlice = tooltip.NineSlice
	if not nineSlice or not data or not data.id then
		return
	end
	if not defaultBorder[tooltip] then
		defaultBorder[tooltip] = { nineSlice:GetBorderColor() }
		tooltip:HookScript("OnTooltipCleared", ResetBorder)
	end
	local quality = C_Item.GetItemQualityByID(data.hyperlink or data.id)
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		-- Blizzard's rounded border takes the background colour so its
		-- corners do not show inside the quality frame.
		local bgR, bgG, bgB = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
		nineSlice:SetBorderColor(bgR, bgG, bgB, 1)
		ShowBorderFrame(tooltip, r, g, b)
	end
end

local function OnItemTooltip(tooltip, data)
	if tooltip:IsForbidden() then
		return
	end
	ColorBorder(tooltip, data)
	AddUnitPrice(tooltip, data)
end

function Tooltip:OnInitialize()
	SetupHealthBar()
	hooksecurefunc(GameTooltip, "Show", ReserveHealthBarSpace)
	GameTooltip:HookScript("OnTooltipCleared", ClearSpacer)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

Tooltip.options = {
	{ key = "unitPrice", type = "toggle", name = L.TOOLTIP_UNIT_PRICE_OPT, desc = L.TOOLTIP_UNIT_PRICE_DESC },
}

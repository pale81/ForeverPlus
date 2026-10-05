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

-- Reserve room for the bar with an empty line once Blizzard decided to show it.
local function ReserveHealthBarSpace(tooltip)
	if tooltip == GameTooltip and tooltip.StatusBar and tooltip.StatusBar:IsShown() then
		tooltip:AddLine(" ")
	end
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

-- Crisp solid frame in quality colour along the tooltip edge.
local function GetBorderFrame(tooltip)
	local frame = borderFrames[tooltip]
	if not frame then
		frame = CreateFrame("Frame", nil, tooltip)
		frame:SetAllPoints(tooltip.NineSlice)
		frame:SetFrameLevel(tooltip:GetFrameLevel() + 1)
		frame.lines = {}
		for i = 1, 4 do
			local line = frame:CreateTexture(nil, "OVERLAY")
			line:SetColorTexture(1, 1, 1)
			frame.lines[i] = line
		end
		local top, bottom, left, right = unpack(frame.lines)
		top:SetPoint("TOPLEFT")
		top:SetPoint("TOPRIGHT")
		bottom:SetPoint("BOTTOMLEFT")
		bottom:SetPoint("BOTTOMRIGHT")
		left:SetPoint("TOPLEFT")
		left:SetPoint("BOTTOMLEFT")
		right:SetPoint("TOPRIGHT")
		right:SetPoint("BOTTOMRIGHT")
		borderFrames[tooltip] = frame
	end
	return frame
end

local function ShowBorderFrame(tooltip, r, g, b)
	local frame = GetBorderFrame(tooltip)
	-- Exactly BORDER_PIXELS screen pixels at any UI or tooltip scale.
	local size = PixelUtil.GetNearestPixelSize(BORDER_PIXELS, frame:GetEffectiveScale(), BORDER_PIXELS)
	local top, bottom, left, right = unpack(frame.lines)
	top:SetHeight(size)
	bottom:SetHeight(size)
	left:SetWidth(size)
	right:SetWidth(size)
	for _, line in ipairs(frame.lines) do
		line:SetVertexColor(r, g, b, 1)
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
		nineSlice:SetBorderColor(r, g, b, 1)
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
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ReserveHealthBarSpace)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, ReserveHealthBarSpace)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

Tooltip.options = {
	{ key = "unitPrice", type = "toggle", name = L.TOOLTIP_UNIT_PRICE_OPT, desc = L.TOOLTIP_UNIT_PRICE_DESC },
}

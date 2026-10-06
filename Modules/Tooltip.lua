-- Tooltip: health bar inside the tooltip, unit price for stacks, quality border.
local _, ns = ...
local L = ns.L

local Tooltip = ns:NewModule("Tooltip", {
	title = L.TOOLTIP_TITLE,
	order = 2,
	defaults = {
		unitPrice = true,
		hoverName = true,
		hoverLevel = true,
		classColors = true,
		qualityBorder = true,
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

local SELL_PREFIX = SELL_PRICE .. ":"

local function AppendToSellLine(tooltip, suffix)
	local name = tooltip:GetName()
	if not name then
		return false
	end
	for i = tooltip:NumLines(), 1, -1 do
		local line = _G[name .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and not (issecretvalue and issecretvalue(text)) and text:find(SELL_PREFIX, 1, true) == 1 then
			if not text:find(suffix, 1, true) then
				line:SetText(text .. " " .. suffix)
			end
			return true
		end
	end
	return false
end

local function OnTooltipAddMoney(tooltip)
	if tooltip.fpUnitSuffix and AppendToSellLine(tooltip, tooltip.fpUnitSuffix) then
		tooltip.fpUnitSuffix = nil
	end
end

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
	if not unitPrice or unitPrice <= 0 then
		return
	end
	if stackPrice then
		-- Merchant: the shown price is the buying price, so a line of its own.
		tooltip:AddDoubleLine(L.TOOLTIP_UNIT_PRICE, GetMoneyString(unitPrice, true), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
		return
	end
	-- Behind the sell price: "Sell price: 40c (20c / each)". The sell price line
	-- may come after this call; the money hook appends it then.
	tooltip.fpUnitSuffix = L.TOOLTIP_UNIT_PRICE_SUFFIX:format(GetMoneyString(unitPrice, true))
	if AppendToSellLine(tooltip, tooltip.fpUnitSuffix) then
		tooltip.fpUnitSuffix = nil
	end
end

---------------------------------------------------------------------------
-- Border coloured by item quality
---------------------------------------------------------------------------
local defaultBorder = {}
local borderFrames = {}

-- Crisp frame in quality colour along the tooltip edge (Core/Widgets.lua).
local function ShowBorderFrame(tooltip, r, g, b)
	local frame = borderFrames[tooltip]
	if not frame then
		frame = CreateFrame("Frame", nil, tooltip)
		-- One pixel inside the edge, thinner than the item frames.
		frame:SetPoint("TOPLEFT", tooltip.NineSlice, "TOPLEFT", 1, -1)
		frame:SetPoint("BOTTOMRIGHT", tooltip.NineSlice, "BOTTOMRIGHT", -1, 1)
		frame:SetFrameLevel(tooltip:GetFrameLevel() + 1)
		frame.border = ns.CreatePixelBorder(frame, frame, 1)
		borderFrames[tooltip] = frame
	end
	frame.border:ShowColor(r, g, b)
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
	if not Tooltip.db.qualityBorder or not nineSlice or not data or not data.id then
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

---------------------------------------------------------------------------
-- Name and level of the unit under the mouse, centred above the cursor
---------------------------------------------------------------------------
local hover

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Only for units in the 3D world (or their nameplates), not unit frames.
local function OverWorld()
	local focus = GetMouseFoci()[1]
	if not focus or focus == WorldFrame or focus:IsForbidden() then
		return true
	end
	local nameplate = C_NamePlate.GetNamePlateForUnit("mouseover")
	return nameplate and not nameplate:IsForbidden() and DoesAncestryInclude(nameplate, focus) or false
end

local function ColorCode(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function HoverText(unit)
	local name, level = UnitName(unit), UnitLevel(unit)
	if Secret(name) then
		return nil
	end
	local text = ColorCode(GameTooltip_UnitColor(unit)) .. (name or "") .. "|r"
	if Tooltip.db.hoverLevel and not Secret(level) then
		text = ("%s |cffcccccc%s|r"):format(text, level and level > 0 and level or "??")
	end
	return text
end

-- Runs while a mouseover unit exists; the text hides over other frames.
local function UpdateHover(frame, elapsed)
	if not UnitExists("mouseover") then
		frame:Hide()
		return
	end
	frame.Text:SetShown(OverWorld())
	frame.sinceText = (frame.sinceText or 0) + (elapsed or 0)
	if frame.sinceText >= 0.1 then
		frame.sinceText = 0
		local text = HoverText("mouseover")
		if text and text ~= frame.lastText then
			frame.lastText = text
			frame.Text:SetText(text)
		end
	end
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / scale, y / scale + 18)
end

local function ShowHoverName()
	if not Tooltip.db.hoverName or not UnitExists("mouseover") then
		return
	end
	if not hover then
		hover = CreateFrame("Frame", nil, UIParent)
		hover:SetFrameStrata("TOOLTIP")
		hover:SetSize(1, 1)
		hover.Text = hover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		hover.Text:SetPoint("BOTTOM")
		hover:SetScript("OnUpdate", UpdateHover)
	end
	hover.Text:SetFont(ns.GetFontFace(), 13, "OUTLINE")
	local text = HoverText("mouseover")
	hover.lastText = text
	if text then
		hover.Text:SetText(text)
	else
		-- Protected name: shown as it is, in the unit colour.
		hover.Text:SetText(UnitName("mouseover"))
		hover.Text:SetTextColor(GameTooltip_UnitColor("mouseover"))
	end
	hover:Show()
	UpdateHover(hover, 0)
end

---------------------------------------------------------------------------
-- Players in the tooltip: name and class in class colour
---------------------------------------------------------------------------
local function OnUnitTooltip(tooltip)
	if not Tooltip.db.classColors or tooltip:IsForbidden() or tooltip ~= GameTooltip then
		return
	end
	local _, unit = tooltip:GetUnit()
	if not unit or Secret(unit) or not UnitIsPlayer(unit) then
		return
	end
	local className, classFile = UnitClass(unit)
	local color = classFile and not Secret(classFile) and C_ClassColor.GetClassColor(classFile)
	if not color then
		return
	end
	local first = GameTooltipTextLeft1
	if first then
		first:SetTextColor(color:GetRGB())
	end
	if not className or Secret(className) then
		return
	end
	for i = 2, tooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text and not Secret(text) then
			local from, to = text:find(className, 1, true)
			if from then
				line:SetText(text:sub(1, from - 1) .. color:WrapTextInColorCode(className) .. text:sub(to + 1))
				break
			end
		end
	end
end

local function OnItemTooltip(tooltip, data)
	if tooltip:IsForbidden() then
		return
	end
	ColorBorder(tooltip, data)
	AddUnitPrice(tooltip, data)
end

function Tooltip:OnLogin()
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", ShowHoverName)
end

function Tooltip:OnInitialize()
	SetupHealthBar()
	hooksecurefunc(GameTooltip, "Show", ReserveHealthBarSpace)
	GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
		ClearSpacer(tooltip)
		tooltip.fpUnitSuffix = nil
	end)
	GameTooltip:HookScript("OnTooltipAddMoney", OnTooltipAddMoney)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

Tooltip.options = {
	{ key = "hoverName", type = "toggle", name = L.TOOLTIP_HOVER_NAME, desc = L.TOOLTIP_HOVER_NAME_DESC },
	{ key = "hoverLevel", type = "toggle", name = L.TOOLTIP_HOVER_LEVEL, parent = "hoverName" },
	{ key = "classColors", type = "toggle", name = L.TOOLTIP_CLASS_COLORS, desc = L.TOOLTIP_CLASS_COLORS_DESC },
	{ key = "unitPrice", type = "toggle", name = L.TOOLTIP_UNIT_PRICE_OPT, desc = L.TOOLTIP_UNIT_PRICE_DESC },
	{ key = "qualityBorder", type = "toggle", name = L.TOOLTIP_QUALITY_BORDER, desc = L.TOOLTIP_QUALITY_BORDER_DESC },
}

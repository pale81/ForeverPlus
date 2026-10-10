-- Tooltip: health bar inside the tooltip, unit price for stacks, quality border.
local _, ns = ...
local L = ns.L

local Tooltip = ns:NewModule("Tooltip", {
	title = L.TOOLTIP_TITLE,
	order = 2,
	defaults = {
		unitPrice = true,
		stackSize = true,
		trainerCompare = true,
		hoverName = true,
		hoverLevel = true,
		hoverHealth = true,
		hoverFullName = false,
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

-- Comparison tooltips next to an item tooltip.
function ns.IsShoppingTooltip(tooltip)
	return tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2
		or tooltip == ItemRefShoppingTooltip1 or tooltip == ItemRefShoppingTooltip2
end

local function OnTooltipAddMoney(tooltip)
	if tooltip.fpUnitSuffix and AppendToSellLine(tooltip, tooltip.fpUnitSuffix) then
		tooltip.fpUnitSuffix = nil
	end
end

local function AddUnitPrice(tooltip, data)
	if not Tooltip.db.unitPrice or ns.IsShoppingTooltip(tooltip) then
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
		-- One pixel inside the edge, 2 pixels wide like the item frames.
		frame:SetPoint("TOPLEFT", tooltip.NineSlice, "TOPLEFT", 1, -1)
		frame:SetPoint("BOTTOMRIGHT", tooltip.NineSlice, "BOTTOMRIGHT", -1, 1)
		frame:SetFrameLevel(tooltip:GetFrameLevel() + 1)
		frame.border = ns.CreatePixelBorder(frame, frame, 2)
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
	if not Tooltip.db.qualityBorder or not nineSlice or not data or not data.id or tooltip.IsEmbedded then
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

-- The name is drawn twice: desaturated underneath and in the unit colour on
-- top, clipped to the health share. The share comes from a status bar fed
-- with the protected health value: display widgets accept protected values,
-- only Lua cannot calculate with them.
local MIN_GREY = 0.6
local NAME_SIZE = 13

local function UpdateHealthMask(frame)
	if Tooltip.db.hoverHealth and frame.masked then
		frame.Bar:SetValue(UnitHealthPercent("mouseover", true))
	end
end

local function Layout(frame)
	local name, level = UnitName("mouseover"), UnitLevel("mouseover")
	-- First name and surname, as Blizzard's own unit display does.
	if Tooltip.db.hoverFullName and not Secret(name) and NameUtil and NameUtil.FormatUnitNameForDisplay then
		local ok, full = pcall(NameUtil.FormatUnitNameForDisplay, "mouseover")
		if ok and full and not Secret(full) then
			name = full
		end
	end
	local ok, r, g, b = pcall(GameTooltip_UnitColor, "mouseover")
	if not ok then
		r, g, b = NORMAL_FONT_COLOR:GetRGB()
	end
	frame.Name:SetText(name)
	frame.Name:SetTextColor(r, g, b)
	local showLevel = Tooltip.db.hoverLevel and not Secret(level)
	frame.Level:SetText(showLevel and (level and level > 0 and level or "??") or "")
	-- Clipping needs the width of the name; a protected name is shown plainly.
	frame.masked = not Secret(name)
	if not frame.masked then
		frame.Level:SetText("") -- the box is 1 px wide then; the level would cover the name
	end
	frame.Clip:ClearAllPoints()
	frame.Clip:SetClipsChildren(frame.masked and Tooltip.db.hoverHealth)
	if frame.masked then
		local width, height = frame.Name:GetStringWidth() + 2, frame.Name:GetStringHeight() + 2
		frame.Box:SetSize(width, height)
		frame.Grey:SetText(name)
		local grey = max(MIN_GREY, 0.3 * r + 0.59 * g + 0.11 * b)
		frame.Grey:SetTextColor(grey, grey, grey)
		frame.Grey:SetShown(Tooltip.db.hoverHealth)
		frame.Clip:SetPoint("TOPLEFT", frame.Box, "TOPLEFT")
		if Tooltip.db.hoverHealth then
			frame.Clip:SetPoint("BOTTOMRIGHT", frame.Bar:GetStatusBarTexture(), "BOTTOMRIGHT")
		else
			frame.Clip:SetPoint("BOTTOMRIGHT", frame.Box, "BOTTOMRIGHT")
		end
		frame:SetSize(width + (showLevel and frame.Level:GetStringWidth() + 4 or 0), height)
	else
		frame.Grey:Hide()
		frame.Box:SetSize(1, NAME_SIZE)
		frame.Clip:SetAllPoints(frame.Box)
		frame:SetSize(1, NAME_SIZE)
	end
	UpdateHealthMask(frame)
end

local function CreateHover()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame.Box = CreateFrame("Frame", nil, frame)
	frame.Box:SetPoint("BOTTOMLEFT")
	frame.Grey = frame.Box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Grey:SetPoint("LEFT", frame.Box, "LEFT", 1, 0)
	frame.Bar = CreateFrame("StatusBar", nil, frame.Box)
	frame.Bar:SetAllPoints(frame.Box)
	frame.Bar:SetStatusBarTexture([[Interface\Buttons\WHITE8X8]])
	frame.Bar:SetStatusBarColor(0, 0, 0, 0)
	frame.Bar:SetMinMaxValues(0, 1)
	frame.Clip = CreateFrame("Frame", nil, frame)
	frame.Clip:SetFrameLevel(frame.Box:GetFrameLevel() + 2)
	frame.Name = frame.Clip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Name:SetPoint("LEFT", frame.Box, "LEFT", 1, 0)
	frame.Level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Level:SetPoint("LEFT", frame.Box, "RIGHT", 3, 0)
	frame.Level:SetTextColor(0.8, 0.8, 0.8)
	return frame
end

local sinceMaskUpdate = 0

-- Runs while a mouseover unit exists; the text hides over other frames.
local function UpdateHover(frame, elapsed)
	if not UnitExists("mouseover") then
		frame:Hide()
		return
	end
	sinceMaskUpdate = sinceMaskUpdate + (elapsed or 0)
	if sinceMaskUpdate >= 0.1 or elapsed == 0 then
		sinceMaskUpdate = 0
		frame:SetAlpha(OverWorld() and 1 or 0)
		UpdateHealthMask(frame)
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
		hover = CreateHover()
		hover:SetScript("OnUpdate", UpdateHover)
	end
	local face = ns.GetFontFace()
	for _, text in ipairs({ hover.Name, hover.Grey, hover.Level }) do
		text:SetFont(face, NAME_SIZE, "OUTLINE")
	end
	Layout(hover)
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

-- Maximum stack size of stackable items.
local function AddStackSize(tooltip, data)
	if not Tooltip.db.stackSize or ns.IsShoppingTooltip(tooltip) then
		return
	end
	local itemID = data and data.id
	if type(itemID) ~= "number" or Secret(itemID) then
		return
	end
	local stackSize = select(8, C_Item.GetItemInfo(itemID))
	if type(stackSize) == "number" and stackSize > 1 then
		tooltip:AddDoubleLine(L.TOOLTIP_STACK_SIZE, stackSize, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
	end
end

local function OnItemTooltip(tooltip, data)
	if tooltip:IsForbidden() then
		return
	end
	ColorBorder(tooltip, data)
	AddUnitPrice(tooltip, data)
	AddStackSize(tooltip, data)
end

---------------------------------------------------------------------------
-- Trainer: the item a recipe makes is compared with the equipped items, in
-- tooltips of our own (Blizzard's comparison tooltips stay untouched).
---------------------------------------------------------------------------
local compareTips = {}
local MAX_NAME_LINES = 12

local function CompareTip(index)
	local tip = compareTips[index]
	if not tip then
		tip = CreateFrame("GameTooltip", "ForeverPlusCompareTooltip" .. index, UIParent, "ShoppingTooltipTemplate")
		compareTips[index] = tip
	end
	return tip
end

local function HideCompareTips()
	for _, tip in ipairs(compareTips) do
		tip:Hide()
	end
end

-- Item made by the trainer service: the item link where the client offers
-- one, else an item named in the tooltip that is known to the client.
local function TrainerItem(index)
	local getLink = _G.GetTrainerServiceItemLink
	if getLink then
		local ok, link = pcall(getLink, index)
		if ok and type(link) == "string" and link:find("|Hitem:", 1, true) then
			return link
		end
	end
	local data = GameTooltip:GetPrimaryTooltipData()
	if type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	if type(data.id) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
		local ok, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, data.id)
		if ok and type(output) == "table" and (output.hyperlink or output.itemID) then
			return output.hyperlink or output.itemID
		end
	end
	for i = 2, math.min(#data.lines, MAX_NAME_LINES) do
		local text = data.lines[i].leftText
		if type(text) == "string" and text ~= "" and not Secret(text) then
			local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(text)
			if itemID and equipLoc and equipLoc ~= "" then
				return itemID
			end
		end
	end
end

local function ShowTrainerCompare(tooltip, index)
	HideCompareTips()
	if not Tooltip.db.trainerCompare or tooltip:IsForbidden() or type(index) ~= "number" then
		return
	end
	local item = TrainerItem(index)
	local equipLoc = item and select(4, C_Item.GetItemInfoInstant(item))
	local slots = equipLoc and ns.EquipSlots and ns.EquipSlots(equipLoc)
	if not slots then
		return
	end
	local shown = {}
	for _, slot in ipairs(slots) do
		if GetInventoryItemLink("player", slot) then
			local tip = CompareTip(#shown + 1)
			tip:SetOwner(tooltip, "ANCHOR_NONE")
			tip:SetScale(tooltip:GetScale())
			tip:SetInventoryItem("player", slot)
			tip.CompareHeader.Label:SetText(EQUIPPED)
			tip.CompareHeader:SetWidth(tip.CompareHeader.Label:GetWidth() + 20)
			tip.CompareHeader:Show()
			shown[#shown + 1] = tip
		end
	end
	if #shown == 0 then
		return
	end
	-- Beside the tooltip, on the side with room; a second one goes further out.
	local width = 0
	for _, tip in ipairs(shown) do
		width = width + ns.Number(tip:GetWidth(), 0)
	end
	local right = ns.Number(tooltip:GetRight(), 0) * tooltip:GetEffectiveScale()
	local toRight = right + width * tooltip:GetEffectiveScale() <= ns.Number(GetScreenWidth(), 0) * ns.Number(UIParent:GetEffectiveScale(), 1)
	local previous = tooltip
	for _, tip in ipairs(shown) do
		tip:ClearAllPoints()
		if toRight then
			tip:SetPoint("TOPLEFT", previous, "TOPRIGHT")
		else
			tip:SetPoint("TOPRIGHT", previous, "TOPLEFT")
		end
		tip:Show()
		previous = tip
	end
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
		HideCompareTips()
	end)
	GameTooltip:HookScript("OnHide", HideCompareTips)
	if GameTooltip.SetTrainerService then
		hooksecurefunc(GameTooltip, "SetTrainerService", ns.Measured("Tooltip: trainer compare", ShowTrainerCompare))
	end
	-- The sell price line comes from a tooltip line rule that calls this global.
	if GameTooltip_OnTooltipAddMoney then
		hooksecurefunc("GameTooltip_OnTooltipAddMoney", OnTooltipAddMoney)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Tooltip: item", OnItemTooltip))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Measured("Tooltip: unit", OnUnitTooltip))
end

Tooltip.options = {
	{ key = "hoverName", type = "toggle", name = L.TOOLTIP_HOVER_NAME, desc = L.TOOLTIP_HOVER_NAME_DESC },
	{ key = "hoverLevel", type = "toggle", name = L.TOOLTIP_HOVER_LEVEL, parent = "hoverName" },
	{ key = "hoverFullName", type = "toggle", name = L.TOOLTIP_HOVER_FULL_NAME, desc = L.TOOLTIP_HOVER_FULL_NAME_DESC, parent = "hoverName" },
	{ key = "hoverHealth", type = "toggle", name = L.TOOLTIP_HOVER_HEALTH, desc = L.TOOLTIP_HOVER_HEALTH_DESC, parent = "hoverName" },
	{ key = "classColors", type = "toggle", name = L.TOOLTIP_CLASS_COLORS, desc = L.TOOLTIP_CLASS_COLORS_DESC },
	{ key = "unitPrice", type = "toggle", name = L.TOOLTIP_UNIT_PRICE_OPT, desc = L.TOOLTIP_UNIT_PRICE_DESC },
	{ key = "stackSize", type = "toggle", name = L.TOOLTIP_STACK_SIZE_OPT, desc = L.TOOLTIP_STACK_SIZE_DESC },
	{ key = "trainerCompare", type = "toggle", name = L.TOOLTIP_TRAINER_COMPARE, desc = L.TOOLTIP_TRAINER_COMPARE_DESC },
	{ key = "qualityBorder", type = "toggle", name = L.TOOLTIP_QUALITY_BORDER, desc = L.TOOLTIP_QUALITY_BORDER_DESC },
}

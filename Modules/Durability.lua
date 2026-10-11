-- Durability on the equipment slots of the character window: a small figure
-- at the bottom of each item, in a colour from green over yellow to red.
-- Items at 100 % show nothing.
local _, ns = ...
local L = ns.L

local Durability = ns:NewModule("Durability", {
	title = L.DURABILITY_TITLE,
	order = 4.9,
	defaults = {
		enabled = true,
		figure = true,
	},
})

local SLOT_BUTTONS = {
	"CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot", "CharacterChestSlot",
	"CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
	"CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot",
	"CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

local texts = {} -- slot button -> text

-- Green at full, yellow at half, red when nearly broken.
local function Color(fraction)
	if fraction >= 0.5 then
		return (1 - fraction) * 2, 1, 0.1
	end
	return 1, fraction * 2, 0.1
end

local function GetText(button)
	local text = texts[button]
	if not text then
		text = button:CreateFontString(nil, "OVERLAY")
		text:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
		texts[button] = text
	end
	text:SetFont(ns.GetFontFace(), 11, "OUTLINE")
	return text
end

-- Percent of a slot (0-100), or nil when it holds no item with durability.
function Durability.Raw(slot)
	local current, maximum = GetInventoryItemDurability(slot)
	current, maximum = ns.Number(current), ns.Number(maximum)
	if not current or not maximum or maximum <= 0 then
		return nil
	end
	return math.max(math.floor(current / maximum * 100 + 0.5), 0)
end

-- The same below 100, nil for whole items (nothing to show on them).
function Durability.Percent(slot)
	local percent = Durability.Raw(slot)
	return percent and percent < 100 and percent or nil
end

local function UpdateSlot(button)
	local show = false
	if Durability.db.enabled then
		local percent = Durability.Percent(button:GetID())
		if percent then
			local text = GetText(button)
			text:SetTextColor(Color(percent / 100))
			text:SetText(percent .. "%")
			text:Show()
			show = true
		end
	end
	if not show and texts[button] then
		texts[button]:Hide()
	end
end

---------------------------------------------------------------------------
-- The armour figure of the repair warning, in the character window: every
-- part has the colour of its piece (green over yellow to red), grey when the
-- function is off. A click switches colours and numbers on and off.
---------------------------------------------------------------------------
-- name, width, height, point, relative part, relative point, x, y, texture coordinates, inventory slot.
local PARTS = {
	{ "Head", 18, 22, "TOPRIGHT", nil, "TOPRIGHT", -31, 0, 0, 0.140625, 0, 0.171875, 1 },
	{ "Shoulders", 48, 22, "TOP", "Head", "BOTTOM", 0, 16, 0.140625, 0.515625, 0, 0.171875, 3 },
	{ "Chest", 20, 22, "TOP", "Shoulders", "TOP", 0, -7, 0.515625, 0.6640625, 0, 0.171875, 5 },
	{ "Wrists", 44, 22, "TOP", "Shoulders", "BOTTOM", 0, 7, 0.6640625, 1, 0, 0.171875, 9 },
	{ "Hands", 42, 18, "TOP", "Wrists", "BOTTOM", 0, 15, 0, 0.328125, 0.171875, 0.3046875, 10 },
	{ "Waist", 16, 5, "TOP", "Chest", "BOTTOM", 0, 6, 0.328125, 0.46875, 0.171875, 0.203125, 6 },
	{ "Legs", 29, 20, "TOP", "Waist", "BOTTOM", 0, 2, 0.46875, 0.6875, 0.171875, 0.3203125, 7 },
	{ "Feet", 41, 32, "TOP", "Legs", "BOTTOM", 0, 8, 0.6875, 1, 0.171875, 0.4140625, 8 },
	{ "Weapon", 20, 45, "RIGHT", "Wrists", "LEFT", 0, -6, 0, 0.140625, 0.3203125, 0.6640625, 16 },
	{ "Shield", 25, 31, "LEFT", "Wrists", "RIGHT", 0, 10, 0.1875, 0.375, 0.3203125, 0.5546875, 17 },
	{ "OffWeapon", 20, 45, "LEFT", "Wrists", "RIGHT", 0, -6, 0, 0.140625, 0.3203125, 0.6640625, 17 },
	{ "Ranged", 28, 38, "TOP", "Shield", "BOTTOM", 0, 5, 0.1875, 0.3984375, 0.5546875, 0.84375, 18 },
}
local FIGURE_TEXTURE = [[Interface\Durability\UI-Durability-Icons]]
local FIGURE_SCALE = 0.55 -- the figure of the repair warning is far bigger than an item slot
local figure

local function CreateFigure(parent)
	local frame = CreateFrame("Button", nil, parent)
	frame:SetSize(80, 80)
	frame:SetScale(FIGURE_SCALE)
	-- Far above the slots, the model and the stats, which cover the area right of the weapon row.
	frame:SetFrameLevel(ns.Number(parent:GetFrameLevel(), 0) + 200)
	frame.parts = {}
	for _, part in ipairs(PARTS) do
		local name, width, height, point, relative, relativePoint, x, y = unpack(part, 1, 8)
		local texture = frame:CreateTexture(nil, "ARTWORK")
		texture:SetTexture(FIGURE_TEXTURE)
		texture:SetTexCoord(part[9], part[10], part[11], part[12])
		texture:SetSize(width, height)
		texture:SetPoint(point, relative and frame.parts[relative].texture or frame, relativePoint, x, y)
		frame.parts[name] = { texture = texture, slot = part[13] }
	end
	frame:RegisterForClicks("LeftButtonUp")
	frame:SetScript("OnClick", function()
		Settings.SetValue("ForeverPlus_Durability_enabled", not Durability.db.enabled)
	end)
	frame:SetScript("OnEnter", function(self)
		local lowest, sum, count = 100, 0, 0
		for _, part in pairs(self.parts) do
			local percent = Durability.Raw(part.slot)
			if percent then
				lowest, sum, count = math.min(lowest, percent), sum + percent, count + 1
			end
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.DURABILITY_TITLE)
		if count > 0 then
			GameTooltip:AddDoubleLine(L.DURABILITY_AVERAGE, ("%d %%"):format(sum / count + 0.5), 1, 1, 1, Color(sum / count / 100))
			GameTooltip:AddDoubleLine(L.DURABILITY_LOWEST, ("%d %%"):format(lowest), 1, 1, 1, Color(lowest / 100))
		end
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddInstructionLine(GameTooltip, Durability.db.enabled and L.DURABILITY_CLICK_OFF or L.DURABILITY_CLICK_ON)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	return frame
end

-- Right of the rightmost slot of the weapon row (the ammunition slot), vertically centred on it. The
-- place is worked out from the rectangles of the slots and set relative to the character window itself,
-- so it does not depend on how the slot buttons are anchored or clipped.
local placedAt -- last result, for /fp haltbarkeit

local function PlaceFigure()
	figure:ClearAllPoints()
	local best, right
	for _, name in ipairs({ "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterAmmoSlot" }) do
		local slot = _G[name]
		local edge = slot and slot:IsShown() and ns.Number(slot:GetRight())
		if edge and (not right or edge > right) then
			best, right = slot, edge
		end
	end
	local left, bottom = ns.Number(PaperDollFrame:GetLeft()), ns.Number(PaperDollFrame:GetBottom())
	local top, slotBottom = best and ns.Number(best:GetTop()), best and ns.Number(best:GetBottom())
	if best and left and bottom and top and slotBottom then
		-- The rectangles are in the scale of their frame; the offsets are in the scale of the figure.
		local toFigure = ns.Number(best:GetEffectiveScale(), 1) / ns.Number(PaperDollFrame:GetEffectiveScale(), 1) / FIGURE_SCALE
		local x = (right - left) * toFigure + 10 / FIGURE_SCALE
		local y = ((top + slotBottom) / 2 - bottom) * toFigure
		figure:SetPoint("LEFT", PaperDollFrame, "BOTTOMLEFT", x, y)
		placedAt = { best:GetName(), x, y }
		return true
	end
	figure:SetPoint("BOTTOMRIGHT", PaperDollFrame, "BOTTOMRIGHT", -14, 14)
	placedAt = nil
	return false
end

-- The slots have no place yet while the window opens: try again a few times.
local function PlaceFigureLater(tries)
	if not PlaceFigure() and tries > 0 then
		C_Timer.After(0.1, function()
			PlaceFigureLater(tries - 1)
		end)
	end
end

local function UpdateFigure()
	if not figure then
		return
	end
	local show = Durability.db.figure
	figure:SetShown(show and PaperDollFrame and PaperDollFrame:IsShown() or false)
	if not show then
		return
	end
	local offhandWeapon = C_PaperDollInfo and C_PaperDollInfo.OffhandHasWeapon and C_PaperDollInfo.OffhandHasWeapon()
	local on = Durability.db.enabled
	for name, part in pairs(figure.parts) do
		local hidden = (name == "Shield" and offhandWeapon) or (name == "OffWeapon" and not offhandWeapon)
		part.texture:SetShown(not hidden)
		local percent = Durability.Raw(part.slot)
		part.texture:SetDesaturated(not on)
		if not on then
			part.texture:SetVertexColor(0.6, 0.6, 0.6, 0.6)
		elseif percent then
			local r, g, b = Color(percent / 100)
			part.texture:SetVertexColor(r, g, b, 1)
		else
			part.texture:SetVertexColor(1, 1, 1, 0.25)
		end
	end
end

local function UpdateAll()
	for _, name in ipairs(SLOT_BUTTONS) do
		local button = _G[name]
		if button then
			UpdateSlot(button)
		end
	end
	UpdateFigure()
end

function Durability:Apply()
	local on = self.db.enabled or self.db.figure
	self:ToggleEvent("UPDATE_INVENTORY_DURABILITY", on, UpdateAll)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", on, UpdateAll)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, UpdateAll)
	UpdateAll()
end

function Durability:OnLogin()
	if PaperDollFrame then
		figure = CreateFigure(PaperDollFrame)
		figure:Hide()
		PaperDollFrame:HookScript("OnShow", function()
			PlaceFigureLater(20)
			UpdateAll()
		end)
		PaperDollFrame:HookScript("OnHide", UpdateFigure)
	end
	self:Apply()
end

-- /fp haltbarkeit: where the figure is and why it might not show.
function Durability:PrintStatus()
	if not figure then
		ns.PrintAlways(L.DURABILITY_STATUS_NONE)
		return
	end
	local point, relativeTo, _, x, y = figure:GetPoint(1)
	ns.PrintAlways(L.DURABILITY_STATUS, tostring(self.db.figure), tostring(figure:IsShown()), tostring(PaperDollFrame and PaperDollFrame:IsShown()),
		tostring(figure:GetFrameStrata()), ns.Number(figure:GetFrameLevel(), 0), tostring(point), tostring(relativeTo and relativeTo:GetName()),
		ns.Number(x, 0), ns.Number(y, 0), placedAt and placedAt[1] or "?", ns.Number(figure:GetLeft(), -1), ns.Number(figure:GetBottom(), -1))
end

function Durability:OnOptionChanged()
	self:Apply()
end

Durability.Update = UpdateAll

Durability.options = {
	{ key = "enabled", type = "toggle", name = L.DURABILITY_ENABLE, desc = L.DURABILITY_ENABLE_DESC, new = true },
	{ key = "figure", type = "toggle", name = L.DURABILITY_FIGURE, desc = L.DURABILITY_FIGURE_DESC, new = true },
}

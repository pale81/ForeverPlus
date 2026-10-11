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

-- Percent of a slot (0-99), or nil when the item has no durability or is whole.
function Durability.Percent(slot)
	local current, maximum = GetInventoryItemDurability(slot)
	current, maximum = ns.Number(current), ns.Number(maximum)
	if not current or not maximum or maximum <= 0 then
		return nil
	end
	local percent = math.floor(current / maximum * 100 + 0.5)
	if percent >= 100 then
		return nil
	end
	return math.max(percent, 0)
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

local function UpdateAll()
	for _, name in ipairs(SLOT_BUTTONS) do
		local button = _G[name]
		if button then
			UpdateSlot(button)
		end
	end
end

function Durability:Apply()
	local on = self.db.enabled
	self:ToggleEvent("UPDATE_INVENTORY_DURABILITY", on, UpdateAll)
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", on, UpdateAll)
	self:ToggleEvent("PLAYER_ENTERING_WORLD", on, UpdateAll)
	UpdateAll()
end

function Durability:OnLogin()
	if PaperDollFrame then
		PaperDollFrame:HookScript("OnShow", UpdateAll)
	end
	self:Apply()
end

function Durability:OnOptionChanged()
	self:Apply()
end

Durability.Update = UpdateAll

Durability.options = {
	{ key = "enabled", type = "toggle", name = L.DURABILITY_ENABLE, desc = L.DURABILITY_ENABLE_DESC, new = true },
}

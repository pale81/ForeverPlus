-- Small shared windows: a scrolling text view and a text input with a button.
local _, ns = ...

local windows = {}

local function CreateWindow(key, width, height)
	local frame = CreateFrame("Frame", "ForeverPlus" .. key .. "Window", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	tinsert(UISpecialFrames, frame:GetName())
	frame:Hide()
	windows[key] = frame
	return frame
end

local function AddScrollBar(frame, scroll)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(scroll:GetScrollBox(), scrollBar)
end

-- Read-only scrolling text.
function ns.ShowTextWindow(key, title, text)
	local frame = windows[key]
	if not frame then
		frame = CreateWindow(key, 420, 480)
		frame.Scroll = CreateFrame("Frame", nil, frame, "ForeverPlusScrollingFontTemplate")
		frame.Scroll:SetPoint("TOPLEFT", 16, -34)
		frame.Scroll:SetPoint("BOTTOMRIGHT", -30, 12)
		AddScrollBar(frame, frame.Scroll)
	end
	frame.TitleText:SetText(title)
	frame.Scroll:SetText(text)
	frame:Show()
	return frame
end

-- Text input; onAccept(text) is called by the button. The text starts
-- selected, so Ctrl+C copies it right away.
function ns.ShowEditWindow(key, title, text, buttonText, onAccept, hint)
	local frame = windows[key]
	if not frame then
		frame = CreateWindow(key, 460, 260)
		frame.Scroll = CreateFrame("Frame", nil, frame, "ScrollingEditBoxTemplate")
		frame.Scroll:SetPoint("TOPLEFT", 16, -34)
		frame.Scroll:SetPoint("BOTTOMRIGHT", -30, 66)
		AddScrollBar(frame, frame.Scroll)
		frame.EditBox = frame.Scroll:GetEditBox()
		frame.EditBox:SetFontObject("GameFontHighlightSmall")
		frame.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		frame.Hint:SetPoint("BOTTOMLEFT", 16, 44)
		frame.Hint:SetPoint("RIGHT", -16, 0)
		frame.Hint:SetJustifyH("LEFT")
		frame.Button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.Button:SetSize(160, 22)
		frame.Button:SetPoint("BOTTOM", 0, 14)
		frame.Button:SetScript("OnClick", function()
			local callback = frame.onAccept
			frame:Hide()
			if callback then
				callback(strtrim(frame.EditBox:GetText() or ""))
			end
		end)
	end
	frame.TitleText:SetText(title)
	frame.Hint:SetText(hint or "")
	frame.Button:SetText(buttonText or OKAY)
	frame.onAccept = onAccept
	frame:Show()
	frame.EditBox:SetText(text or "")
	frame.EditBox:SetFocus()
	frame.EditBox:HighlightText()
	return frame
end

---------------------------------------------------------------------------
-- Crisp pixel border with slightly rounded (stepped) corners
---------------------------------------------------------------------------
local BorderMixin = {}

local function LayoutBorder(border, size)
	local top, bottom, left, right, tl, tr, bl, br = unpack(border.parts)
	local half = size / 2
	local anchor = border.anchor
	for _, part in ipairs(border.parts) do
		part:ClearAllPoints()
	end
	top:SetPoint("TOPLEFT", anchor, "TOPLEFT", size, 0)
	top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -size, 0)
	top:SetHeight(size)
	bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", size, 0)
	bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -size, 0)
	bottom:SetHeight(size)
	left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -size)
	left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, size)
	left:SetWidth(size)
	right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -size)
	right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, size)
	right:SetWidth(size)
	-- Corner pieces moved half a line inwards close the gap diagonally.
	tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", half, -half)
	tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -half, -half)
	bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", half, half)
	br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -half, half)
	for i = 5, 8 do
		border.parts[i]:SetSize(size, size)
	end
end

-- Shows the border in the given colour, exactly `pixels` screen pixels wide.
function BorderMixin:ShowColor(r, g, b)
	local size = PixelUtil.GetNearestPixelSize(self.pixels, self.anchor:GetEffectiveScale(), self.pixels)
	if self.size ~= size then
		self.size = size
		LayoutBorder(self, size)
	end
	for _, part in ipairs(self.parts) do
		part:SetVertexColor(r, g, b, 1)
		part:Show()
	end
end

function BorderMixin:Hide()
	for _, part in ipairs(self.parts) do
		part:Hide()
	end
end

-- owner: frame that gets the textures; anchor: region the border follows.
function ns.CreatePixelBorder(owner, anchor, pixels, layer, subLevel)
	local border = Mixin({ anchor = anchor or owner, pixels = pixels or 2, parts = {} }, BorderMixin)
	for i = 1, 8 do
		local part = owner:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 7)
		part:SetColorTexture(1, 1, 1)
		part:Hide()
		border.parts[i] = part
	end
	return border
end

---------------------------------------------------------------------------
-- Action button art (rounded icon mask + frame) for any icon
---------------------------------------------------------------------------
-- Blizzard's art is drawn for 45 px icons: frame 46x45 (bar) or 51x51
-- (standalone "AddRow" variant), both anchored at the icon's top left.
local FRAME_STYLES = {
	bar = { atlas = "UI-HUD-ActionBar-IconFrame", width = 46 / 45, height = 1 },
	-- Blizzard anchors this art at the top left too; its shadow lies bottom right.
	standalone = { atlas = "UI-HUD-ActionBar-IconFrame-AddRow", width = 51 / 45, height = 51 / 45 },
}
local MASK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mask"
local maskRatio

local function MaskRatio()
	if not maskRatio then
		local info = C_Texture.GetAtlasInfo(MASK_ATLAS)
		maskRatio = info and info.width and info.width > 0 and info.width / 45 or 1.5
	end
	return maskRatio
end

local actionFrames = setmetatable({}, { __mode = "k" })

-- Resizes mask and frame to the current icon size (and style).
function ns.SizeActionFrame(owner, style)
	local art = actionFrames[owner]
	if not art then
		return
	end
	local data = FRAME_STYLES[style or art.style] or FRAME_STYLES.bar
	art.style = style or art.style
	local width, height = art.icon:GetSize()
	art.mask:SetSize(width * MaskRatio(), height * MaskRatio())
	art.frame:SetAtlas(data.atlas)
	art.frame:ClearAllPoints()
	art.frame:SetSize(width * data.width, height * data.height)
	if data.centered then
		art.frame:SetPoint("CENTER", art.icon, "CENTER")
	else
		art.frame:SetPoint("TOPLEFT", art.icon, "TOPLEFT")
	end
end

function ns.ApplyActionFrame(owner, icon, style)
	if actionFrames[owner] or not icon then
		return actionFrames[owner]
	end
	local mask = owner:CreateMaskTexture()
	mask:SetAtlas(MASK_ATLAS)
	mask:SetPoint("CENTER", icon, "CENTER")
	icon:AddMaskTexture(mask)
	local frame = owner:CreateTexture(nil, "OVERLAY", nil, -1)
	actionFrames[owner] = { icon = icon, mask = mask, frame = frame, style = style or "bar" }
	ns.SizeActionFrame(owner)
	return actionFrames[owner]
end

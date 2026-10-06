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

-- Read-only list of lines; item links show their tooltip on mouse over and
-- work like chat links when clicked (Shift-click inserts them).
function ns.ShowLinkWindow(key, title, lines)
	local frame = windows[key]
	if not frame then
		frame = CreateWindow(key, 460, 420)
		local list = CreateFrame("ScrollingMessageFrame", nil, frame)
		list:SetPoint("TOPLEFT", 16, -34)
		list:SetPoint("BOTTOMRIGHT", -16, 12)
		list:SetFontObject(GameFontHighlight)
		list:SetJustifyH("LEFT")
		list:SetIndentedWordWrap(true)
		list:SetFading(false)
		list:SetMaxLines(1000)
		list:SetHyperlinksEnabled(true)
		-- Newest line on top: lines are added in reverse, so the first line
		-- sits at the top and scroll offset 0 shows the start of the list.
		list:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP)
		list:EnableMouseWheel(true)
		list:SetScript("OnMouseWheel", function(self, delta)
			self:ScrollByAmount(-delta * 3)
		end)
		list:SetScript("OnHyperlinkEnter", function(self, link)
			if link:find("^item:") then
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
				GameTooltip:SetHyperlink(link)
				GameTooltip:Show()
			end
		end)
		list:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
		list:SetScript("OnHyperlinkClick", function(_, link, text, button)
			SetItemRef(link, text, button)
		end)
		frame.List = list
	end
	frame.TitleText:SetText(title)
	frame.List:Clear()
	for i = #lines, 1, -1 do
		frame.List:AddMessage(lines[i])
	end
	frame.List:ScrollToBottom()
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
	-- With a radius the edges stop that many line widths before the corner
	-- and a diagonal of squares closes the gap (rounder corners).
	local radius = border.radius
	local inset = radius and radius * size or size
	top:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, 0)
	top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, 0)
	top:SetHeight(size)
	bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, 0)
	bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, 0)
	bottom:SetHeight(size)
	left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -inset)
	left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, inset)
	left:SetWidth(size)
	right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -inset)
	right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, inset)
	right:SetWidth(size)
	if radius then
		local index = 4
		for step = 1, radius - 1 do
			local x, y = step * size, (radius - step) * size
			for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
				index = index + 1
				local part = border.parts[index]
				part:SetPoint(corner[1], anchor, corner[1], corner[2] * x, corner[3] * y)
				part:SetSize(size, size)
			end
		end
		return
	end
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
-- radius (optional, >= 2): corner rounding in line widths.
function ns.CreatePixelBorder(owner, anchor, pixels, layer, subLevel, radius)
	local border = Mixin({ anchor = anchor or owner, pixels = pixels or 2, parts = {}, radius = radius }, BorderMixin)
	local count = radius and 4 + 4 * (radius - 1) or 8
	for i = 1, count do
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
	-- During some layout passes the client reports protected sizes; keep the
	-- previous sizing then (the mask is only attached once it has a size).
	if issecretvalue and (issecretvalue(width) or issecretvalue(height)) or not width or width <= 0 then
		return
	end
	art.mask:SetSize(width * MaskRatio(), height * MaskRatio())
	if not art.masked then
		art.masked = true
		art.icon:AddMaskTexture(art.mask)
	end
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
	local frame = owner:CreateTexture(nil, "OVERLAY", nil, -1)
	actionFrames[owner] = { icon = icon, mask = mask, frame = frame, style = style or "bar" }
	ns.SizeActionFrame(owner)
	return actionFrames[owner]
end

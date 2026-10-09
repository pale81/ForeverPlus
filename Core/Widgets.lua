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
-- Soft popup list at its owner (e.g. a settings button): rows with icon and
-- text, optional check mark and tooltip. A click runs the row's action and
-- rebuilds the list in place. Closes with Escape, a click elsewhere or when
-- the owner disappears. build() returns { title, items, empty, footer }.
---------------------------------------------------------------------------
local POPUP_WIDTH, ROW_HEIGHT, MAX_ROWS, POPUP_PAD = 300, 22, 14, 8
local popups = {} -- frame name -> popup

local function PopupRow(popup, index)
	local row = popup.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, popup)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", popup.Title, "BOTTOMLEFT", 0, -6 - (index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", popup, "RIGHT", -POPUP_PAD, 0)
	local highlight = row:CreateTexture()
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row:SetHighlightTexture(highlight)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(18, 18)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetSize(16, 16)
	row.Check:SetPoint("RIGHT", -2, 0)
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
	row.Text:SetPoint("RIGHT", row.Check, "LEFT", -4, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		local item = self.item
		if item and item.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			item.tooltip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self)
		local item = self.item
		if item and item.onClick then
			GameTooltip_Hide()
			item.onClick()
			popup:Refresh()
		end
	end)
	popup.rows[index] = row
	return row
end

local function PopupFooter(popup, index)
	local button = popup.footer[index]
	if not button then
		button = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		button:SetSize(120, 20)
		button:SetScript("OnClick", function(self)
			if self.action then
				self.action()
				popup:Refresh()
			end
		end)
		popup.footer[index] = button
	end
	return button
end

local function CreatePopup(name)
	local popup = CreateFrame("Frame", name, UIParent, "TooltipBackdropTemplate")
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetToplevel(true)
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	popup:EnableMouseWheel(true)
	popup:SetWidth(POPUP_WIDTH)
	popup.rows, popup.footer, popup.offset = {}, {}, 0
	popup.Title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popup.Title:SetPoint("TOPLEFT", POPUP_PAD + 2, -POPUP_PAD - 2)
	popup.Title:SetPoint("RIGHT", -POPUP_PAD, 0)
	popup.Title:SetJustifyH("LEFT")
	popup.Info = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	popup.Info:SetPoint("TOPRIGHT", -POPUP_PAD - 2, -POPUP_PAD - 3)
	popup.Empty = popup:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	popup.Empty:SetPoint("TOPLEFT", popup.Title, "BOTTOMLEFT", 2, -8)
	local fade = popup:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.12)
	popup.Fade = fade
	tinsert(UISpecialFrames, popup:GetName())
	popup:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta * 3
		self:Refresh()
	end)
	popup:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	popup:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	popup:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		self.owner, self.build = nil, nil
	end)
	popup:SetScript("OnUpdate", function(self)
		if self.owner and not self.owner:IsVisible() then
			self:Hide()
		end
	end)

	function popup:Refresh()
		local data = self.build and self.build() or {}
		local items = data.items or {}
		self:SetWidth(data.width or POPUP_WIDTH)
		self.Title:SetText(data.title or "")
		local visible = math.min(#items, MAX_ROWS)
		self.offset = math.max(0, math.min(self.offset, #items - visible))
		for i = 1, math.max(visible, #self.rows) do
			local item = i <= visible and items[i + self.offset]
			local row = (item or self.rows[i]) and PopupRow(self, i)
			if row then
				row.item = item or nil
				row:SetShown(item and true or false)
				if item then
					-- Rows without an action are section titles.
					row:SetEnabled(item.onClick ~= nil)
					row.Text:SetText(item.onClick and (item.text or "") or NORMAL_FONT_COLOR:WrapTextInColorCode(item.text or ""))
					row.Icon:SetShown(item.icon ~= nil)
					if item.icon then
						row.Icon:SetTexture(item.icon)
					end
					row.Check:SetShown(item.checked ~= nil)
					if item.checked ~= nil then
						row.Check:SetAtlas(item.checked and "common-icon-checkmark" or "common-icon-redx")
					end
				end
			end
		end
		self.Info:SetText(#items > visible and ("%d-%d / %d"):format(self.offset + 1, self.offset + visible, #items) or "")
		self.Empty:SetText(#items == 0 and (data.empty or "") or "")
		local height = POPUP_PAD * 2 + 20 + math.max(visible, #items == 0 and 1 or 0) * ROW_HEIGHT
		local footer = data.footer or {}
		for _, button in ipairs(self.footer) do
			button:Hide()
		end
		for i, entry in ipairs(footer) do
			local button = PopupFooter(self, i)
			button:SetText(entry.text)
			button.action = entry.onClick
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", POPUP_PAD + (i - 1) * 126, POPUP_PAD)
			button:Show()
		end
		if #footer > 0 then
			height = height + 28
		end
		self:SetHeight(height)
	end
	-- Moved once (Alt + right-click unlocks, then drag), it opens there.
	if ns.HookSavedWindow then
		ns.HookSavedWindow(popup)
	end
	return popup
end

-- key: own frame with its own saved position (e.g. "Loot"); without it the
-- shared list frame is used.
function ns.ShowPopupList(owner, build, key)
	local name = key and ("ForeverPlusPopup" .. key) or "ForeverPlusPopupList"
	local popup = popups[name]
	if not popup then
		popup = CreatePopup(name)
		popups[name] = popup
	end
	if owner and popup:IsShown() and popup.owner == owner then
		popup:Hide()
		return
	end
	popup.owner, popup.build, popup.offset = owner, build, 0
	popup:ClearAllPoints()
	if owner then
		popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
	else
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
		if ns.ApplySavedWindow then
			ns.ApplySavedWindow(popup)
		end
	end
	popup:Refresh()
	popup:Show()
	popup.Fade:Play()
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

-- subLevel: draw level of the frame within OVERLAY (default -1, below the
-- owner's own overlays).
function ns.ApplyActionFrame(owner, icon, style, subLevel)
	if actionFrames[owner] or not icon then
		return actionFrames[owner]
	end
	local mask = owner:CreateMaskTexture()
	mask:SetAtlas(MASK_ATLAS)
	mask:SetPoint("CENTER", icon, "CENTER")
	local frame = owner:CreateTexture(nil, "OVERLAY", nil, subLevel or -1)
	actionFrames[owner] = { icon = icon, mask = mask, frame = frame, style = style or "bar" }
	ns.SizeActionFrame(owner)
	return actionFrames[owner]
end

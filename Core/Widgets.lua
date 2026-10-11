-- Small shared windows: a scrolling text view and a text input with a button.
local _, ns = ...

---------------------------------------------------------------------------
-- Panel: the one look of all ForeverPlus popups and windows, taken from the
-- quest preview at the tracker: tooltip background and border, the title in
-- the tooltip header font at the top left, 10 px padding, a short fade-in.
-- options: strata, close (small X at the top right), movable (drag),
-- escape (false: Escape does not close it; needs a name).
---------------------------------------------------------------------------
local PADDING = 10
ns.PANEL_PADDING = PADDING

local function OnCloseEnter(button)
	button.Icon:SetVertexColor(1, 1, 1)
end

local function OnCloseLeave(button)
	button.Icon:SetVertexColor(0.7, 0.7, 0.7)
end

-- Soft fade-in every time the frame is shown (one switch in the main options; nil counts as on).
function ns.FadeIn(frame, duration)
	local group = frame:CreateAnimationGroup()
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(duration or 0.25)
	alpha:SetSmoothing("OUT")
	group:SetToFinalAlpha(true)
	frame:HookScript("OnShow", function()
		group:Stop()
		if not (ns.db and ns.db.fadeIn == false) then
			group:Play()
		end
	end)
	return group
end

-- The bronze of the game's portrait frame (measured on a screenshot: mid tones 162/117/70 to 180/133/77, lights up
-- to 231/192/132), the same colour as the bronze dragon; the border art is light grey, so the tint is a little
-- brighter than the colour that shows.
ns.PANEL_BORDER = { 0.88, 0.65, 0.40 }

function ns.CreatePanel(name, options)
	options = options or {}
	local panel = CreateFrame("Frame", name, UIParent, "TooltipBackdropTemplate")
	panel:SetFrameStrata(options.strata or "DIALOG")
	-- Bronze border and a blue-grey ground as bright as the game's own tooltips (measured on a screenshot: about 38/43/59
	-- under the 0.96 alpha), not the grey default and not darker than the other tooltips.
	if panel.NineSlice then
		if panel.NineSlice.SetBorderColor then
			panel.NineSlice:SetBorderColor(ns.PANEL_BORDER[1], ns.PANEL_BORDER[2], ns.PANEL_BORDER[3], 1)
		end
		if panel.NineSlice.SetCenterColor then
			panel.NineSlice:SetCenterColor(0.15, 0.17, 0.23, 0.96)
		end
	end
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
	panel.Title:SetPoint("TOPLEFT", PADDING, -PADDING)
	panel.Title:SetPoint("RIGHT", -(PADDING + (options.close and 18 or 0)), 0)
	panel.Title:SetJustifyH("LEFT")
	if options.close then
		local close = CreateFrame("Button", nil, panel)
		close:SetSize(16, 16)
		close:SetPoint("TOPRIGHT", -7, -7)
		close.Icon = close:CreateTexture(nil, "ARTWORK")
		close.Icon:SetAllPoints()
		close.Icon:SetAtlas("uitools-icon-close")
		close:SetScript("OnClick", function()
			panel:Hide()
		end)
		close:SetScript("OnEnter", OnCloseEnter)
		close:SetScript("OnLeave", OnCloseLeave)
		OnCloseLeave(close)
		panel.Close = close
	end
	if options.movable then
		panel:SetMovable(true)
		panel:RegisterForDrag("LeftButton")
		panel:SetScript("OnDragStart", panel.StartMoving)
		panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	end
	if name and options.escape ~= false then
		tinsert(UISpecialFrames, name)
	end
	panel.Fade = ns.FadeIn(panel)
	return panel
end

-- A small round grey game icon on a button (like the buttons at the minimap), dull until the mouse is over it:
-- button.Icon and button.Mask.
function ns.SetRoundGreyIcon(button, texture)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:SetTexture(texture)
	button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.Icon:SetDesaturated(true)
	button.Icon:SetAlpha(0.6)
	button.Mask = button:CreateMaskTexture()
	button.Mask:SetAllPoints(button.Icon)
	button.Mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	button.Icon:AddMaskTexture(button.Mask)
end

-- A small bright yellow "NEW" label with rays turning slowly behind it and a soft pulse; parent: the button or tab it
-- marks. Shown or hidden by the caller.
function ns.CreateNewBadge(parent, label)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(30, 14)
	badge:SetFrameLevel(parent:GetFrameLevel() + 10)
	badge:EnableMouse(false)
	badge.Rays = badge:CreateTexture(nil, "BACKGROUND")
	badge.Rays:SetTexture([[Interface\Cooldown\star4]])
	badge.Rays:SetBlendMode("ADD")
	badge.Rays:SetVertexColor(1, 0.9, 0.2)
	badge.Rays:SetSize(40, 40)
	badge.Rays:SetPoint("CENTER")
	badge.Text = badge:CreateFontString(nil, "OVERLAY")
	badge.Text:SetFont(ns.GetFontFace(), 10, "THICKOUTLINE")
	badge.Text:SetPoint("CENTER")
	badge.Text:SetTextColor(1, 0.92, 0.15)
	badge.Text:SetText(label or "NEW")
	badge.Turn = badge.Rays:CreateAnimationGroup()
	badge.Turn:SetLooping("REPEAT")
	local turn = badge.Turn:CreateAnimation("Rotation")
	turn:SetDegrees(-360)
	turn:SetDuration(6)
	badge.Pulse = badge:CreateAnimationGroup()
	badge.Pulse:SetLooping("BOUNCE")
	local pulse = badge.Pulse:CreateAnimation("Alpha")
	pulse:SetFromAlpha(1)
	pulse:SetToAlpha(0.6)
	pulse:SetDuration(0.8)
	pulse:SetSmoothing("IN_OUT")
	badge:SetScript("OnShow", function(self)
		self.Turn:Play()
		self.Pulse:Play()
	end)
	badge:SetScript("OnHide", function(self)
		self.Turn:Stop()
		self.Pulse:Stop()
	end)
	badge:Hide()
	return badge
end

-- Copy symbol in the colour of the tab labels (gold), white while hovered;
-- the symbol itself is drawn desaturated so it matches the rest of the UI.
function ns.StyleCopyButton(button)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if C_Texture.GetAtlasInfo("friends-icon-battlenet-copy") then
		icon:SetAtlas("friends-icon-battlenet-copy")
	else
		icon:SetTexture([[Interface\Buttons\UI-GuildButton-PublicNote-Up]])
	end
	icon:SetDesaturated(true)
	button.Icon = icon
	ns.SetCopyHot(button, false)
end

function ns.SetCopyHot(button, hot)
	if hot then
		button.Icon:SetVertexColor(1, 1, 1)
	else
		button.Icon:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())
	end
end

-- Darker area behind scrolling texts inside a panel.
function ns.AddPanelInset(panel, region)
	local inset = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
	inset:SetColorTexture(0, 0, 0, 0.3)
	inset:SetPoint("TOPLEFT", region, "TOPLEFT", -4, 4)
	inset:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 4, -4)
	return inset
end

local windows = {}

local function CreateWindow(key, width, height)
	local frame = ns.CreatePanel("ForeverPlus" .. key .. "Window", { close = true, movable = true })
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame.TitleText = frame.Title
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
		frame.Scroll:SetPoint("TOPLEFT", PADDING + 4, -40)
		frame.Scroll:SetPoint("BOTTOMRIGHT", -30, PADDING + 4)
		ns.AddPanelInset(frame, frame.Scroll)
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
		frame.Scroll:SetPoint("TOPLEFT", PADDING + 4, -40)
		frame.Scroll:SetPoint("BOTTOMRIGHT", -30, 70)
		ns.AddPanelInset(frame, frame.Scroll)
		AddScrollBar(frame, frame.Scroll)
		frame.EditBox = frame.Scroll:GetEditBox()
		frame.EditBox:SetFontObject("GameFontHighlightSmall")
		frame.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		frame.Hint:SetPoint("BOTTOMLEFT", PADDING + 4, 44)
		frame.Hint:SetPoint("RIGHT", -PADDING - 4, 0)
		frame.Hint:SetJustifyH("LEFT")
		frame.Button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.Button:SetSize(160, 22)
		frame.Button:SetPoint("BOTTOM", 0, PADDING + 2)
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
local POPUP_WIDTH, ROW_HEIGHT, MAX_ROWS, POPUP_PAD = 300, 22, 14, PADDING
local SECTION_GAP = 8
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
	-- Thin line under a section title.
	row.Line = row:CreateTexture(nil, "ARTWORK")
	row.Line:SetColorTexture(1, 0.82, 0, 0.35)
	row.Line:SetHeight(1)
	row.Line:SetPoint("BOTTOMLEFT", 0, 0)
	row.Line:SetPoint("BOTTOMRIGHT", 0, 0)
	row.Stripe = row:CreateTexture(nil, "BACKGROUND")
	row.Stripe:SetAllPoints()
	row.Stripe:SetColorTexture(1, 1, 1, 0.05)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(18, 18)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.IconBorder = ns.CreatePixelBorder(row, row.Icon, 1, "OVERLAY", 6)
	row.Value = row:CreateFontString(nil, "OVERLAY", "GameTooltipText")
	row.Value:SetPoint("RIGHT", -4, 0)
	row.Value:SetJustifyH("RIGHT")
	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetSize(16, 16)
	row.Check:SetPoint("RIGHT", -2, 0)
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameTooltipText")
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
	local popup = ns.CreatePanel(name, { strata = "FULLSCREEN_DIALOG" })
	popup:EnableMouseWheel(true)
	popup:SetWidth(POPUP_WIDTH)
	popup.rows, popup.footer, popup.offset = {}, {}, 0
	popup.Info = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	popup.Info:SetPoint("TOPRIGHT", -POPUP_PAD, -POPUP_PAD - 1)
	popup.TotalsLine = popup:CreateTexture(nil, "ARTWORK")
	popup.TotalsLine:SetColorTexture(1, 1, 1, 0.18)
	popup.TotalsLine:SetHeight(1)
	popup.totals = {}
	popup.Empty = popup:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	popup.Empty:SetPoint("TOPLEFT", popup.Title, "BOTTOMLEFT", 2, -8)
	popup:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta * 3
		self:Refresh()
	end)
	popup:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	popup:HookScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	popup:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		self.owner, self.build = nil, nil
	end)
	ns.SetUpdate(popup, "Popup: update", function(self)
		if self.owner and not self.owner:IsVisible() then
			self:Hide()
		end
	end)

	function popup:Refresh()
		local data = self.build and self.build() or {}
		local items = data.items or {}
		self:SetWidth(data.width or POPUP_WIDTH)
		self.Title:SetText(data.title or "")
		local visible = math.min(#items, data.maxRows or MAX_ROWS)
		self.offset = math.max(0, math.min(self.offset, #items - visible))
		local rowsHeight = 0
		for i = 1, math.max(visible, #self.rows) do
			local item = i <= visible and items[i + self.offset]
			local row = (item or self.rows[i]) and PopupRow(self, i)
			if row then
				row.item = item or nil
				row:SetShown(item and true or false)
				if item then
					-- Rows without an action are section titles: a gap above (not for the
					-- first one), a thin line below.
					local isHeader = item.onClick == nil
					local gap = isHeader and rowsHeight > 0 and SECTION_GAP or 0
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -6 - rowsHeight - gap)
					row:SetPoint("RIGHT", self, "RIGHT", -POPUP_PAD, 0)
					row.Line:SetShown(isHeader and item.line ~= false)
					rowsHeight = rowsHeight + gap + ROW_HEIGHT + (isHeader and 2 or 0)
					row:SetEnabled(item.onClick ~= nil)
					row.Text:SetText(item.onClick and (item.text or "") or NORMAL_FONT_COLOR:WrapTextInColorCode(item.text or ""))
					row.Icon:SetShown(item.icon ~= nil)
					if item.icon then
						row.Icon:SetTexture(item.icon)
					end
					-- Optional: coloured icon border, value column, striped background.
					local r, g, b
					if item.quality then
						r, g, b = C_Item.GetItemQualityColor(item.quality)
					end
					if item.icon and r and item.quality > 1 then
						row.IconBorder:ShowColor(r, g, b)
					else
						row.IconBorder:Hide()
					end
					row.Stripe:SetShown(data.striped and (i + self.offset) % 2 == 0 or false)
					row.Value:SetShown(item.right ~= nil)
					row.Text:ClearAllPoints()
					row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
					if item.right ~= nil then
						row.Value:SetText(item.right)
						row.Text:SetPoint("RIGHT", row.Value, "LEFT", -8, 0)
					else
						row.Text:SetPoint("RIGHT", row.Check, "LEFT", -4, 0)
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
		local height = POPUP_PAD * 2 + 20 + (#items == 0 and ROW_HEIGHT or rowsHeight)
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
		-- Summary block at the bottom (above the footer buttons): { label, value, big }.
		local totals = data.totals or {}
		local base = POPUP_PAD + (#footer > 0 and 28 or 0)
		self.TotalsLine:SetShown(#totals > 0)
		for _, line in ipairs(self.totals) do
			line.Label:Hide()
			line.Value:Hide()
		end
		if #totals > 0 then
			local lineHeight, y = 18, base
			self.TotalsLine:ClearAllPoints()
			self.TotalsLine:SetPoint("BOTTOMLEFT", POPUP_PAD, base + #totals * lineHeight + 4)
			self.TotalsLine:SetPoint("BOTTOMRIGHT", -POPUP_PAD, base + #totals * lineHeight + 4)
			for i = #totals, 1, -1 do
				local line = self.totals[i]
				if not line then
					line = {
						Label = self:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
						Value = self:CreateFontString(nil, "OVERLAY", "GameTooltipText"),
					}
					line.Label:SetJustifyH("LEFT")
					line.Value:SetJustifyH("RIGHT")
					self.totals[i] = line
				end
				local entry = totals[i]
				line.Label:ClearAllPoints()
				line.Label:SetPoint("BOTTOMLEFT", POPUP_PAD + 2, y)
				line.Value:ClearAllPoints()
				line.Value:SetPoint("BOTTOMRIGHT", -POPUP_PAD - 2, y)
				line.Label:SetText(entry[1])
				line.Value:SetText(entry[2])
				line.Label:SetFontObject(entry[3] and "GameFontNormal" or "GameFontHighlightSmall")
				line.Label:Show()
				line.Value:Show()
				y = y + lineHeight
			end
			height = height + #totals * lineHeight + 10
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
end

---------------------------------------------------------------------------
-- Art of the players' chat bubbles (dark rounded box, light border, tail):
-- a nine-slice frame around `frame`, `inset` pixels outside it, drawn under
-- the frame's own texts. Returns art, tail (nil when the client lacks the art).
---------------------------------------------------------------------------
function ns.CreateBubbleArt(frame, inset, tailOffsetX, tint)
	local layout = NineSliceLayouts and NineSliceLayouts.ChatBubble
	if not layout then
		return nil
	end
	local art = CreateFrame("Frame", nil, frame, "NineSliceCodeTemplate")
	art:SetPoint("TOPLEFT", -inset, inset)
	art:SetPoint("BOTTOMRIGHT", inset, -inset)
	art:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	if not pcall(NineSliceUtil.ApplyLayout, art, layout) then
		art:Hide()
		return nil
	end
	local tail = art:CreateTexture(nil, "ARTWORK", nil, 7)
	if pcall(tail.SetAtlas, tail, "ChatBubble-Tail", true) then
		tail:SetPoint("TOP", frame, "BOTTOM", tailOffsetX or -10, -inset + 3)
	else
		tail = nil
	end
	-- Tinted (the border of the dialog bubble in bronze): every piece but the dark centre, and the tail.
	if tint then
		for _, region in ipairs({ art:GetRegions() }) do
			if region ~= art.Center and region.SetVertexColor then
				region:SetVertexColor(tint[1], tint[2], tint[3], 1)
			end
		end
		if tail then
			tail:SetVertexColor(tint[1], tint[2], tint[3], 1)
		end
	end
	return art, tail
end

---------------------------------------------------------------------------
-- Friendly NPC nameplates, switched on only while a bubble needs one to hang
-- on (the NPC the player talks to has no plate otherwise) and restored after.
---------------------------------------------------------------------------
local PLATES_CVAR = "nameplateShowFriendlyNpcs"
local platesRestore -- nil: untouched; false: was on already; string: previous value

function ns.ShowFriendlyPlates(on)
	if on then
		if platesRestore == nil and not InCombatLockdown() then
			local current = GetCVar(PLATES_CVAR)
			if current == "1" then
				platesRestore = false
			elseif current then
				platesRestore = current
				SetCVar(PLATES_CVAR, "1")
			end
		end
	elseif platesRestore ~= nil then
		local restore = platesRestore
		platesRestore = nil
		if restore then
			ns.RunOutOfCombat(function()
				if platesRestore == nil then
					SetCVar(PLATES_CVAR, restore)
				end
			end)
		end
	end
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
function BorderMixin:ShowColor(r, g, b, a)
	local size = PixelUtil.GetNearestPixelSize(self.pixels, self.anchor:GetEffectiveScale(), self.pixels)
	if self.size ~= size then
		self.size = size
		LayoutBorder(self, size)
	end
	for _, part in ipairs(self.parts) do
		part:SetVertexColor(r, g, b, type(a) == "number" and a or 1)
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

-- Tints the frame (item quality); nil gives the neutral frame back. A coloured frame is drawn
-- desaturated first so the colour is not dulled by the metal of the art.
function ns.SetActionFrameColor(owner, r, g, b)
	local art = actionFrames[owner]
	if not art then return end
	art.frame:SetDesaturated(r ~= nil)
	art.frame:SetVertexColor(r or 1, g or 1, b or 1)
end

-- Lets an optional visual style be switched off again without discarding the
-- reusable art or leaving its rounded mask on the icon.
function ns.SetActionFrameEnabled(owner, enabled)
	local art = actionFrames[owner]
	if not art then return end
	if enabled then
		if not art.masked then
			art.masked = true
			art.icon:AddMaskTexture(art.mask)
		end
		ns.SizeActionFrame(owner)
		art.frame:Show()
	else
		if art.masked then
			art.icon:RemoveMaskTexture(art.mask)
			art.masked = false
		end
		art.frame:Hide()
	end
end

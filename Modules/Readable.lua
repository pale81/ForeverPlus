-- Readable texts (books, letters, plaques, stone tablets) on their own material in the middle of the screen
-- instead of Blizzard's window: a book lies open with two pages, a single sheet is aged parchment, stone and
-- metal plates carry engraved letters. The art is drawn by tools/build_readable.py (Media/Readable).
-- Blizzard's window stays open (it carries the reading, paging and closing) but collapsed.
local _, ns = ...
local L = ns.L

local Readable = ns:NewModule("Readable", {
	title = L.READABLE_TITLE,
	order = 5.65,
	defaults = {
		enabled = true,
		dim = true, -- darken the screen around the text
	},
})

local MEDIA = [[Interface\AddOns\ForeverPlus\Media\Readable\]]

-- Geometry in frame units. `coords`: the used part of the texture. Text areas: left, top, right, bottom inset.
local LOOKS = {
	-- The open book of the game's spell book (two painted pages with gold corners and a ribbon, 806 + 807 x 805);
	-- without these atlases our own drawn book (BOOK_OWN).
	BOOK = {
		atlases = { "spellbook-background-evergreen-left", "spellbook-background-evergreen-right" },
		width = 1000, height = 499,
		pages = { { 50, 52, 530, 70 }, { 532, 52, 46, 54 } }, -- left page, right page
	},
	BOOK_OWN = {
		art = "book", width = 1000, height = 656, coords = { 0, 1, 0, 672 / 1024 },
		pages = { { 82, 62, 533, 74 }, { 533, 62, 82, 74 } },
	},
	SHEET = {
		art = "parchment", width = 478, height = 589, coords = { 48 / 512, 464 / 512, 0, 1 },
		pages = { { 58, 62, 58, 66 } },
	},
}

-- Colours per material: tint of the art, text, title, engraved light edge (shadow), divider.
local STYLES = {
	Parchment = { art = "parchment", tint = { 1, 1, 1 }, text = { 0.33, 0.21, 0.09 }, title = { 0.47, 0.17, 0.05 },
		divider = { 0.45, 0.28, 0.12, 0.85 } },
	Stone = { art = "stone", tint = { 0.70, 0.69, 0.66 }, text = { 0.15, 0.14, 0.13 }, title = { 0.12, 0.11, 0.10 },
		shadow = { 1, 1, 1, 0.30 }, divider = { 0.18, 0.17, 0.16, 0.75 } },
	Marble = { art = "stone", tint = { 1, 0.985, 0.95 }, text = { 0.22, 0.20, 0.18 }, title = { 0.18, 0.16, 0.14 },
		shadow = { 1, 1, 1, 0.55 }, divider = { 0.30, 0.27, 0.24, 0.7 } },
	Bronze = { art = "metal", tint = { 0.74, 0.54, 0.32 }, text = { 0.20, 0.10, 0.03 }, title = { 0.16, 0.08, 0.02 },
		shadow = { 1, 0.88, 0.65, 0.35 }, divider = { 0.25, 0.13, 0.04, 0.75 } },
	Silver = { art = "metal", tint = { 0.84, 0.86, 0.90 }, text = { 0.13, 0.14, 0.17 }, title = { 0.10, 0.11, 0.14 },
		shadow = { 1, 1, 1, 0.5 }, divider = { 0.18, 0.19, 0.22, 0.7 } },
}
-- Text without tags (most books) has no font of its own in a SimpleHTML made in Lua and looked odd or was not drawn:
-- it is set as a paragraph (Readable.AsHTML), so the font of P applies. The game takes no font without a tag.
local FONTS = { P = "QuestFont_Large", H1 = "Fancy32Font", H2 = "Fancy24Font",
	H3 = "Fancy22Font" }
local WHEEL_STEP = 40

-- What the text is printed on: an open book (several pages, or the game's large parchment) or a single plate
-- of its material (parchment, stone, marble, bronze, silver; others on parchment).
function Readable.Look(material, page, hasNext)
	material = type(material) == "string" and STYLES[material] and material
		or material == "ParchmentLarge" and material or "Parchment"
	if material == "ParchmentLarge" or material == "Parchment" and (ns.Number(page, 1) > 1 or hasNext) then
		return "BOOK", material
	end
	return "SHEET", material
end

---------------------------------------------------------------------------
-- Blizzard's window: open but without room
---------------------------------------------------------------------------
local savedScale -- the window's scale while it is collapsed
local holding = false

local function Collapse()
	local window = ItemTextFrame
	if not window or window:IsForbidden() then
		return
	end
	savedScale = savedScale or ns.Number(window:GetScale(), 1)
	holding = true
	window:SetScale(0.001)
	window:SetAlpha(0)
	holding = false
end

local function Release()
	local window = ItemTextFrame
	if not savedScale or not window or window:IsForbidden() then
		return
	end
	local scale = savedScale
	savedScale = nil -- first: the hook below must not take the window back
	holding = true
	window:SetScale(scale)
	window:SetAlpha(1)
	holding = false
end

-- The game gives size and opacity back to its window (panel layout): taken back at once.
local function KeepCollapsed(window)
	for _, method in ipairs({ "SetScale", "SetAlpha" }) do
		hooksecurefunc(window, method, ns.Measured("Readable: keep collapsed", function(self)
			if holding or not savedScale or InCombatLockdown() then
				return
			end
			if ns.Number(self:GetScale(), 0) > 0.01 or ns.Number(self:GetAlpha(), 0) > 0 then
				Collapse()
			end
		end))
	end
end

---------------------------------------------------------------------------
-- Pages of a book: two at a time. The game holds one page; the right one is fetched after the left one came,
-- going back fetches page by page down to the left page of the spread before.
---------------------------------------------------------------------------
-- left/right: { page = number, text = string, hasNext = bool }; fetching: waiting for the right page;
-- target: page to go back to.
Readable.spread = {}

function Readable.ResetSpread()
	Readable.spread = {}
end

-- One page arrived. Returns what to do: "draw", "wait" (another page was asked for), or nil (not a book).
function Readable.TakePage(page, text, hasNext, look)
	local spread = Readable.spread
	if look ~= "BOOK" then
		Readable.ResetSpread()
		return nil
	end
	if spread.target and page > spread.target then
		ItemTextPrevPage()
		return "wait"
	end
	if spread.fetching and spread.left and page == spread.left.page + 1 then
		spread.fetching = nil
		spread.right = { page = page, text = text, hasNext = hasNext }
		return "draw"
	end
	spread.target, spread.fetching = nil, nil
	spread.left = { page = page, text = text, hasNext = hasNext }
	spread.right = nil
	if hasNext then
		spread.fetching = true
		ItemTextNextPage()
	end
	return "draw"
end

function Readable.CanTurn(forward)
	local spread = Readable.spread
	if spread.fetching or spread.target or not spread.left then
		return false
	end
	if forward then
		local last = spread.right or spread.left
		return last.hasNext and true or false
	end
	return spread.left.page > 1
end

function Readable.Turn(forward)
	local spread = Readable.spread
	-- A plate with several pages (not a book) turns one page at a time.
	if not spread.left then
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if forward then
			ItemTextNextPage()
		else
			ItemTextPrevPage()
		end
		return
	end
	if not Readable.CanTurn(forward) then
		return
	end
	PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if forward then
		ItemTextNextPage()
	else
		spread.target = math.max(1, spread.left.page - 2)
		ItemTextPrevPage()
	end
end

---------------------------------------------------------------------------
-- The material
---------------------------------------------------------------------------
local view

local function PageButton(parent, forward)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(32, 32)
	local name = forward and "NextPage" or "PrevPage"
	button:SetNormalTexture([[Interface\Buttons\UI-SpellbookIcon-]] .. name .. "-Up")
	button:SetPushedTexture([[Interface\Buttons\UI-SpellbookIcon-]] .. name .. "-Down")
	button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	button:SetScript("OnClick", function()
		Readable.Turn(forward)
	end)
	return button
end

-- A page: scrollable text, running head on later pages, page number below; fades in when its text changes.
local function CreateTextPage(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder.Scroll = CreateFrame("ScrollFrame", nil, holder)
	holder.Scroll:EnableMouseWheel(true)
	holder.Scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = ns.Number(self:GetVerticalScrollRange(), 0)
		local offset = ns.Number(self:GetVerticalScroll(), 0) - delta * WHEEL_STEP
		self:SetVerticalScroll(math.max(0, math.min(range, offset)))
	end)
	holder.Text = CreateFrame("SimpleHTML", nil, holder.Scroll)
	holder.Scroll:SetScrollChild(holder.Text)
	holder.Head = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	holder.Head:SetPoint("TOP", 0, 22)
	holder.Head:SetWordWrap(false)
	holder.Number = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	holder.Number:SetPoint("TOP", holder, "BOTTOM", 0, -12)
	holder.Fade = holder:CreateAnimationGroup()
	local alpha = holder.Fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.2)
	return holder
end

local function CreateView()
	-- The screen around the text darkens a little (option), without catching the mouse.
	local dim = CreateFrame("Frame", nil, UIParent)
	dim:SetFrameStrata("HIGH")
	dim:SetAllPoints(UIParent)
	dim:EnableMouse(false)
	dim:Hide()
	dim.Texture = dim:CreateTexture(nil, "BACKGROUND")
	dim.Texture:SetAllPoints()
	dim.Texture:SetTexture(MEDIA .. "vignette")
	ns.FadeIn(dim, 0.35)

	local frame = CreateFrame("Frame", "ForeverPlusReadable", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(dim:GetFrameLevel() + 5)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	frame:EnableMouse(true)
	frame:Hide()
	frame.Dim = dim
	ns.FadeIn(frame, 0.25)
	frame.Shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.Shadow:SetTexture(MEDIA .. "shadow")
	frame.Shadow:SetPoint("TOPLEFT", -34, 22)
	frame.Shadow:SetPoint("BOTTOMRIGHT", 40, -50)
	frame.Shadow:SetAlpha(0.8)
	frame.Art = frame:CreateTexture(nil, "BACKGROUND")
	frame.Art:SetAllPoints()
	-- The game's open book: two pages side by side, a soft shadow in the fold, the ribbon over it.
	frame.PageLeft = frame:CreateTexture(nil, "BACKGROUND")
	frame.PageLeft:SetPoint("TOPLEFT")
	frame.PageLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOM")
	frame.PageRight = frame:CreateTexture(nil, "BACKGROUND")
	frame.PageRight:SetPoint("TOPLEFT", frame, "TOP")
	frame.PageRight:SetPoint("BOTTOMRIGHT")
	frame.Fold = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	frame.Fold:SetTexture([[Interface\Buttons\WHITE8X8]])
	frame.Fold:SetSize(60, 1)
	frame.Fold:SetPoint("TOP", 0, -4)
	frame.Fold:SetPoint("BOTTOM", 0, 4)
	frame.Fold:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.28))
	frame.FoldRight = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	frame.FoldRight:SetTexture([[Interface\Buttons\WHITE8X8]])
	frame.FoldRight:SetPoint("TOPLEFT", frame.Fold, "TOPRIGHT")
	frame.FoldRight:SetPoint("BOTTOMLEFT", frame.Fold, "BOTTOMRIGHT")
	frame.FoldRight:SetWidth(60)
	frame.FoldRight:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.28), CreateColor(0, 0, 0, 0))
	frame.Ribbon = frame:CreateTexture(nil, "BORDER")
	frame.Ribbon:SetPoint("TOP", 0, 0)

	frame.Title = frame:CreateFontString(nil, "ARTWORK", "Fancy24Font")
	frame.Title:SetJustifyH("CENTER")
	frame.Title:SetWordWrap(true)
	frame.Divider = frame:CreateTexture(nil, "ARTWORK")
	frame.Divider:SetTexture(MEDIA .. "divider")
	frame.Divider:SetSize(220, 28)

	frame.Pages = { CreateTextPage(frame), CreateTextPage(frame) }
	frame.Prev = PageButton(frame, false)
	frame.Next = PageButton(frame, true)
	frame.Close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.Close:SetPoint("TOPRIGHT", -2, -2)
	frame.Close:SetScript("OnClick", function()
		CloseItemText()
	end)
	-- Right click closes; in a book a click on the left page turns back, on the right page forward.
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			CloseItemText()
		elseif self.look == "BOOK" then
			local x = ns.Number(GetCursorPosition(), 0) / ns.Number(self:GetEffectiveScale(), 1)
			local center = ns.Number(self:GetCenter(), 0)
			Readable.Turn(x > center)
		end
	end)
	return frame
end

-- Fonts and colours of one page's text, engraved on stone and metal (light lower edge).
local function StyleText(text, style)
	for tag, font in pairs(FONTS) do
		local object = _G[font]
		if object then
			text:SetFontObject(tag, object)
		end
		local color = tag == "P" and style.text or style.title
		text:SetTextColor(tag, color[1], color[2], color[3])
		local shadow = style.shadow or { 0, 0, 0, 0 }
		text:SetShadowColor(tag, shadow[1], shadow[2], shadow[3], shadow[4])
		text:SetShadowOffset(tag, 1, -1)
	end
	text:SetSpacing("P", 3)
end

-- Plain text as one HTML paragraph (line breaks kept, &, < and > escaped); HTML stays as it is.
function Readable.AsHTML(text)
	text = text or ""
	if text:find("^%s*<[Hh][Tt][Mm][Ll]") then
		return text
	end
	text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\r?\n", "<br/>")
	return "<html><body><p>" .. text .. "</p></body></html>"
end

-- The last steps of drawing a page (/fp buch verlauf, kept after /rl): to see why a text looks odd or goes away.
local function Trace(text, ...)
	if type(ns.db.readableTrace) ~= "table" then
		ns.db.readableTrace = {}
	end
	local trace = ns.db.readableTrace
	if #trace >= 60 then
		table.remove(trace, 1)
	end
	trace[#trace + 1] = ("%.2f %s"):format(ns.Number(GetTime(), 0) % 1000, text:format(...))
end

function Readable.PrintTrace()
	local trace = type(ns.db.readableTrace) == "table" and ns.db.readableTrace or {}
	ns.ShowTrace(L.READABLE_TRACE:format(#trace), trace)
end

-- One measured value for the trace: the number, or why there is none.
local function Value(fn)
	local ok, value = pcall(fn)
	if not ok then
		return "Fehler"
	end
	value = ns.Number(value, nil)
	return value and ("%d"):format(value) or "fehlt"
end

local function WatchPage(holder, label)
	for _, delay in ipairs({ 0.1, 0.5, 2 }) do
		ns.After("Readable: WatchPage (timer)", delay, function()
			Trace("%s +%.1f: sichtbar %s, Deckkraft %s, Höhe %s, Inhalt %s", label, delay,
				tostring(holder:IsVisible()), Value(function() return holder:GetEffectiveAlpha() * 100 end),
				Value(function() return holder.Text:GetHeight() end),
				Value(function() return holder.Text:GetContentHeight() end))
		end)
	end
end

-- The text keeps the height of its page (it vanished when it was set to a height measured before the text was
-- laid out); a longer text grows to its own height a picture later, then the page scrolls.
function Readable.TextHeight(page, content)
	content = ns.Number(content, 0)
	return content > page and content + 10 or page
end

local function SetPageText(holder, text, width, height)
	text = Readable.AsHTML(text)
	holder.Text:SetWidth(width)
	holder.Text:SetHeight(height)
	holder.Text:SetText(text)
	holder.Scroll:SetVerticalScroll(0)
	holder.Fade:Play()
	ns.After("Readable: SetPageText (timer)", 0, function()
		if holder.Text.GetContentHeight then
			local wanted = Readable.TextHeight(height, holder.Text:GetContentHeight())
			if wanted ~= height then
				-- A SimpleHTML lays its text out when the text is set, not when its size changes: set again.
				holder.Text:SetHeight(wanted)
				holder.Text:SetText(text)
				Trace("Seite länger als Platz: Höhe %d statt %d", wanted, height)
			end
		end
	end)
end

local function WithCreator(text)
	text = text or ""
	local creator = ItemTextGetCreator()
	if type(creator) == "string" and creator ~= "" then
		text = text .. "\n\n" .. ITEM_TEXT_FROM .. "\n" .. creator .. "\n"
	end
	return text
end

-- Lays out the look: art, title with divider (first page), text pages, numbers and arrows.
local function Draw(look, material, pages)
	view = view or CreateView()
	local frame = view
	local gameBook = look == "BOOK" and C_Texture.GetAtlasInfo(LOOKS.BOOK.atlases[1]) ~= nil
		and C_Texture.GetAtlasInfo(LOOKS.BOOK.atlases[2]) ~= nil
	local geometry = LOOKS[look == "BOOK" and not gameBook and "BOOK_OWN" or look]
	local style = STYLES[material] or STYLES.Parchment
	frame.look = look
	frame:SetSize(geometry.width, geometry.height)
	local room = ns.Number(UIParent:GetHeight(), 768) * 0.9
	frame:SetScale(math.min(1, room / geometry.height))
	frame.Art:SetShown(not gameBook)
	for _, part in ipairs({ frame.PageLeft, frame.PageRight, frame.Fold, frame.FoldRight, frame.Ribbon }) do
		part:SetShown(gameBook)
	end
	if gameBook then
		frame.PageLeft:SetAtlas(geometry.atlases[1])
		frame.PageRight:SetAtlas(geometry.atlases[2])
		local ribbon = C_Texture.GetAtlasInfo("spellbook-background-evergreen-ribbon")
		frame.Ribbon:SetShown(ribbon ~= nil)
		if ribbon then
			frame.Ribbon:SetAtlas("spellbook-background-evergreen-ribbon")
			frame.Ribbon:SetSize(102 * geometry.height / 805, 557 * geometry.height / 805)
		end
	else
		frame.Art:SetTexture(MEDIA .. (look == "BOOK" and geometry.art or style.art))
		frame.Art:SetTexCoord(unpack(geometry.coords))
		frame.Art:SetVertexColor(style.tint[1], style.tint[2], style.tint[3])
	end
	local title = ItemTextGetItem() or ""
	local first = pages[1] and pages[1].page == 1
	for index, holder in ipairs(frame.Pages) do
		local area = geometry.pages[index]
		local page = pages[index]
		holder:SetShown(area ~= nil and page ~= nil)
		if area and page then
			local top = area[2] + (index == 1 and first and 70 or 0)
			holder:ClearAllPoints()
			holder:SetPoint("TOPLEFT", area[1], -top)
			holder:SetPoint("BOTTOMRIGHT", -area[3], area[4])
			holder.Scroll:SetAllPoints()
			StyleText(holder.Text, style)
			local font = _G[FONTS.P]
			local file, size, flags
			if font then
				file, size, flags = font:GetFont()
			end
			Trace("Seite %d (%s, %s): %s, %d Zeichen, Schrift %s %s %s", page.page, look, tostring(material),
				(page.text or ""):find("^%s*<[Hh][Tt][Mm][Ll]") and "HTML" or "Text", #(page.text or ""),
				tostring(file), Value(function() return size end), tostring(flags))
			WatchPage(holder, ("Seite %d"):format(page.page))
			SetPageText(holder, WithCreator(page.text), geometry.width - area[1] - area[3],
				math.max(1, geometry.height - top - area[4]))
			local several = look == "BOOK" or page.hasNext or page.page > 1
			holder.Number:SetText(several and L.READABLE_PAGE:format(page.page) or "")
			holder.Number:SetTextColor(style.divider[1], style.divider[2], style.divider[3])
			holder.Head:SetText(not first and title or "")
			holder.Head:SetTextColor(style.divider[1], style.divider[2], style.divider[3])
		end
	end
	-- Title and divider above the first page.
	local area = geometry.pages[1]
	frame.Title:SetShown(first)
	frame.Divider:SetShown(first)
	if first then
		frame.Title:ClearAllPoints()
		frame.Title:SetPoint("TOPLEFT", area[1], -area[2] + 4)
		frame.Title:SetPoint("TOPRIGHT", frame, "TOPLEFT", geometry.width - area[3], -area[2] + 4)
		frame.Title:SetText(title)
		frame.Title:SetTextColor(style.title[1], style.title[2], style.title[3])
		frame.Title:SetShadowColor(unpack(style.shadow or { 0, 0, 0, 0 }))
		frame.Divider:ClearAllPoints()
		frame.Divider:SetPoint("TOP", frame.Title, "BOTTOM", 0, -4)
		frame.Divider:SetVertexColor(unpack(style.divider))
	end
	frame.Prev:ClearAllPoints()
	frame.Prev:SetPoint("BOTTOMLEFT", area[1] - 10, area[4] - 52)
	frame.Next:ClearAllPoints()
	frame.Next:SetPoint("BOTTOMRIGHT", -(geometry.pages[2] or area)[3] + 10, area[4] - 52)
	frame.Prev:SetShown(look == "BOOK" and Readable.CanTurn(false) or look ~= "BOOK" and pages[1].page > 1)
	frame.Next:SetShown(look == "BOOK" and Readable.CanTurn(true) or look ~= "BOOK" and pages[1].hasNext)
	frame.Dim:SetShown(Readable.db.dim)
	frame:Show()
end

-- ITEM_TEXT_READY: the page (also after turning) on its material.
function Readable.Show()
	if not Readable.db.enabled then
		return
	end
	local number, hasNext = ns.Number(ItemTextGetPage(), 1), ItemTextHasNextPage() and true or false
	local text = ItemTextGetText() or ""
	local look, material = Readable.Look(ItemTextGetMaterial(), number, hasNext)
	local action = Readable.TakePage(number, text, hasNext, look)
	if action == "wait" then
		return
	end
	if look == "BOOK" then
		local spread = Readable.spread
		if spread.fetching then
			-- The right page usually follows at once: one picture with both pages, the left one alone only
			-- when the right one does not come.
			local left = spread.left
			ns.After("Readable: Show (timer)", 0.4, function()
				if spread == Readable.spread and spread.fetching and spread.left == left then
					Draw(look, material, { left })
					Collapse()
				end
			end)
			Collapse()
			return
		end
		Draw(look, material, { spread.left, spread.right })
	else
		Draw(look, material, { { page = number, text = text, hasNext = hasNext } })
	end
	Collapse()
end

function Readable.Hide()
	if view then
		view:Hide()
		view.Dim:Hide()
	end
	Readable.ResetSpread()
	Release()
end

function Readable:Apply()
	local on = self.db.enabled
	self:ToggleEvent("ITEM_TEXT_READY", on, Readable.Show)
	self:ToggleEvent("ITEM_TEXT_CLOSED", on, Readable.Hide)
	if not on then
		Readable.Hide()
	elseif view then
		view.Dim:SetShown(self.db.dim and view:IsShown())
	end
end

function Readable:OnLogin()
	if ItemTextFrame then
		KeepCollapsed(ItemTextFrame)
		-- Blizzard shows its window after the page arrived: it is taken back as it shows.
		ItemTextFrame:HookScript("OnShow", ns.Measured("Readable: window shown", function()
			if Readable.db.enabled then
				Collapse()
			end
		end))
		ItemTextFrame:HookScript("OnHide", ns.Measured("Readable: window hidden", Readable.Hide))
	end
	self:Apply()
end

function Readable:OnOptionChanged()
	self:Apply()
end

Readable.options = {
	{ key = "enabled", type = "toggle", name = L.READABLE_ENABLE, desc = L.READABLE_ENABLE_DESC, new = true },
	{ key = "dim", type = "toggle", name = L.READABLE_DIM, desc = L.READABLE_DIM_DESC, parent = "enabled", new = true },
}

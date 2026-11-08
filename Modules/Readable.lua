-- Readable texts (books, letters, plaques, stone tablets) on their own material in the middle of the screen
-- instead of Blizzard's window: a book on a book page, a single page on parchment, stone and metal on their
-- plate. Blizzard's window stays open (it carries the reading, paging and closing) but collapsed.
local _, ns = ...
local L = ns.L

local Readable = ns:NewModule("Readable", {
	title = L.READABLE_TITLE,
	order = 5.65,
	defaults = {
		enabled = true,
	},
})

-- Design sizes of the materials (the frame is scaled up for reading).
local LOOKS = {
	BOOK = { width = 520, height = 560, scale = 1.15, left = 52, right = 52, top = 64, bottom = 56 },
	PAGE = { width = 299, height = 357, scale = 1.35, left = 24, right = 24, top = 46, bottom = 40 },
	MATERIAL = { width = 299, height = 357, scale = 1.35, left = 26, right = 26, top = 48, bottom = 42 },
}
local WHEEL_STEP = 40

-- What the text is printed on: a book (several pages, or the game's large parchment), a single page, or the
-- material's own plate (stone, marble, bronze, silver ...).
function Readable.Look(material, page, hasNext)
	material = type(material) == "string" and material ~= "" and material or "Parchment"
	if material == "ParchmentLarge" or material == "Parchment" and (ns.Number(page, 1) > 1 or hasNext) then
		return "BOOK", material
	elseif material == "Parchment" then
		return "PAGE", material
	end
	return "MATERIAL", material
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
-- The page
---------------------------------------------------------------------------
local page

local function Turn(forward)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if forward then
		ItemTextNextPage()
	else
		ItemTextPrevPage()
	end
end

local function PageButton(parent, forward)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(32, 32)
	local name = forward and "NextPage" or "PrevPage"
	button:SetNormalTexture([[Interface\Buttons\UI-SpellbookIcon-]] .. name .. "-Up")
	button:SetPushedTexture([[Interface\Buttons\UI-SpellbookIcon-]] .. name .. "-Down")
	button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	button:SetScript("OnClick", function()
		Turn(forward)
	end)
	return button
end

local function CreatePage()
	local frame = CreateFrame("Frame", "ForeverPlusReadable", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	frame:EnableMouse(true)
	frame:Hide()
	ns.FadeIn(frame, 0.25)
	-- A soft shadow lifts the material off the world.
	frame.Shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.Shadow:SetTexture([[Interface\Tooltips\UI-Tooltip-Background]])
	frame.Shadow:SetVertexColor(0, 0, 0, 0.35)
	frame.Shadow:SetPoint("TOPLEFT", 6, -8)
	frame.Shadow:SetPoint("BOTTOMRIGHT", 8, -10)
	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints()
	-- The plate of a material comes in four parts (256 + 64 wide, 256 + 128 high), as in Blizzard's window.
	frame.Parts = {}
	local parts = { { "TopLeft", 256, 256 }, { "TopRight", 64, 256 }, { "BotLeft", 256, 128 }, { "BotRight", 64, 128 } }
	for index, info in ipairs(parts) do
		local texture = frame:CreateTexture(nil, "BACKGROUND")
		texture:SetSize(info[2], info[3])
		texture.part = info[1]
		frame.Parts[index] = texture
	end
	frame.Parts[1]:SetPoint("TOPLEFT")
	frame.Parts[2]:SetPoint("TOPLEFT", frame.Parts[1], "TOPRIGHT")
	frame.Parts[3]:SetPoint("TOPLEFT", frame.Parts[1], "BOTTOMLEFT")
	frame.Parts[4]:SetPoint("TOPLEFT", frame.Parts[1], "BOTTOMRIGHT")

	frame.Title = frame:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	frame.Title:SetJustifyH("CENTER")
	frame.Title:SetWordWrap(false)

	frame.Scroll = CreateFrame("ScrollFrame", nil, frame)
	frame.Scroll:EnableMouseWheel(true)
	frame.Scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = ns.Number(self:GetVerticalScrollRange(), 0)
		local offset = ns.Number(self:GetVerticalScroll(), 0) - delta * WHEEL_STEP
		self:SetVerticalScroll(math.max(0, math.min(range, offset)))
	end)
	frame.Text = CreateFrame("SimpleHTML", nil, frame.Scroll)
	frame.Scroll:SetScrollChild(frame.Text)

	frame.Number = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Prev = PageButton(frame, false)
	frame.Next = PageButton(frame, true)
	frame.Close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.Close:SetScript("OnClick", function()
		CloseItemText()
	end)
	return frame
end

local function Paint(frame, look, material)
	local atlas = look == "BOOK" and "Book-bg"
		or look == "PAGE" and (QuestTextContrast and QuestTextContrast.GetDefaultBackgroundAtlas() or "QuestBG-Parchment")
	frame.Background:SetShown(atlas and true or false)
	if atlas then
		frame.Background:SetAtlas(atlas)
	end
	for _, texture in ipairs(frame.Parts) do
		texture:SetShown(not atlas)
		if not atlas then
			texture:SetTexture([[Interface\ItemTextFrame\ItemText-]] .. material .. "-" .. texture.part)
		end
	end
	-- Text colours of the material, as Blizzard's window takes them (light text when the player chose it).
	local textColor, titleColor = GetMaterialTextColors(material)
	if look == "PAGE" and QuestTextContrast and QuestTextContrast.UseLightText() then
		textColor, titleColor = GetMaterialTextColors("Stone")
	end
	local fonts = ITEM_TEXT_FONTS and (ITEM_TEXT_FONTS[material] or ITEM_TEXT_FONTS.default) or {}
	for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do
		if fonts[tag] then
			frame.Text:SetFontObject(tag, fonts[tag])
		end
		local color = (tag == "P" or material ~= "ParchmentLarge") and textColor or titleColor
		frame.Text:SetTextColor(tag, color[1], color[2], color[3])
	end
	frame.Title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
end

local function Arrange(frame, look)
	local size = LOOKS[look]
	frame:SetScale(size.scale)
	frame:SetSize(size.width, size.height)
	frame.Title:ClearAllPoints()
	frame.Title:SetPoint("TOPLEFT", size.left, -size.top + 30)
	frame.Title:SetPoint("TOPRIGHT", -size.right, -size.top + 30)
	frame.Scroll:ClearAllPoints()
	frame.Scroll:SetPoint("TOPLEFT", size.left, -size.top)
	frame.Scroll:SetPoint("BOTTOMRIGHT", -size.right, size.bottom)
	frame.Text:SetWidth(size.width - size.left - size.right)
	frame.Number:ClearAllPoints()
	frame.Number:SetPoint("BOTTOM", 0, size.bottom - 28)
	frame.Prev:ClearAllPoints()
	frame.Prev:SetPoint("BOTTOMLEFT", size.left - 8, size.bottom - 36)
	frame.Next:ClearAllPoints()
	frame.Next:SetPoint("BOTTOMRIGHT", -size.right + 8, size.bottom - 36)
	frame.Close:ClearAllPoints()
	frame.Close:SetPoint("TOPRIGHT", -4, -4)
end

-- ITEM_TEXT_READY: the page (also after turning it) on its material.
function Readable.Show()
	if not Readable.db.enabled then
		return
	end
	local number, hasNext = ns.Number(ItemTextGetPage(), 1), ItemTextHasNextPage() and true or false
	local look, material = Readable.Look(ItemTextGetMaterial(), number, hasNext)
	page = page or CreatePage()
	Arrange(page, look)
	Paint(page, look, material)
	page.Title:SetText(ItemTextGetItem() or "")
	local text = ItemTextGetText() or ""
	local creator = ItemTextGetCreator()
	if type(creator) == "string" and creator ~= "" then
		text = text .. "\n\n" .. ITEM_TEXT_FROM .. "\n" .. creator .. "\n"
	end
	page.Text:SetHeight(1)
	page.Text:SetText(text)
	local height = page.Text.GetContentHeight and ns.Number(page.Text:GetContentHeight()) or nil
	page.Text:SetHeight(math.max(height or 1000, 1) + 10)
	page.Scroll:SetVerticalScroll(0)
	local several = hasNext or number > 1
	page.Number:SetText(several and L.READABLE_PAGE:format(number) or "")
	page.Prev:SetShown(number > 1)
	page.Next:SetShown(hasNext)
	page:Show()
	Collapse()
end

function Readable.Hide()
	if page then
		page:Hide()
	end
	Release()
end

function Readable:Apply()
	local on = self.db.enabled
	self:ToggleEvent("ITEM_TEXT_READY", on, Readable.Show)
	self:ToggleEvent("ITEM_TEXT_CLOSED", on, Readable.Hide)
	if not on then
		Readable.Hide()
	end
end

function Readable:OnLogin()
	if ItemTextFrame then
		KeepCollapsed(ItemTextFrame)
		-- Blizzard shows its window after the page arrived: it is taken back as it shows.
		ItemTextFrame:HookScript("OnShow", ns.Measured("Readable: window shown", function()
			if Readable.db.enabled and page and page:IsShown() then
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
}

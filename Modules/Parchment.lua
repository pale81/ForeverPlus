-- Quest, gossip and book windows as a parchment page (quest option "Nur
-- Pergament"): Blizzard's frame, portrait, title bar, backgrounds, close
-- button and scroll bars are hidden. One parchment with a paper shadow
-- carries the name at the top, the text and the buttons as text links at
-- the bottom; an arrow there shows that the text goes on (mouse wheel
-- scrolls). Blizzard's quest buttons are only restyled and moved, their
-- clicks stay Blizzard's. Escape still closes.
local _, ns = ...

local Parchment = { name = "Parchment" }
ns.Parchment = Parchment

local CHROME = { "NineSlice", "PortraitContainer", "Bg", "TopTileStreaks", "Inset", "TitleContainer", "Background" }
local PAGE_LEFT, PAGE_TOP, PAGE_BOTTOM = 3, -22, 2
local BOOK_RIGHT = -28 -- the book window changes its size; the page follows it
local PARCHMENT_WIDTH = 299 -- Blizzard's parchment atlas, if it cannot be read
local PAGE_MARGIN = 8 -- wider than Blizzard's parchment: the text runs close to its edge
local PAGE_TEXT = { 0.18, 0.1, 0.04 }
-- Paper shadow: the parchment itself in black, offset (x, y, alpha).
local SHADOWS = { { 6, -7, 0.18 }, { 3, -4, 0.3 } }
local LINK_SIZE = 15
local LINK_PADDING = 12
local BOOK_TEXT_BOTTOM, BOOK_FOOTER = 6, 30 -- Blizzard's text bottom, room for the links
local ARROW_INTERVAL = 0.1

local enabled = false
local pages = {}    -- window frame -> page
local restyled = {} -- Blizzard button -> original look and anchors
local linkFonts

local function LinkFont(name, r, g, b)
	local font = CreateFont(name)
	font:CopyFontObject(QuestTitleFont)
	local face = font:GetFont()
	font:SetFont(face, LINK_SIZE, "")
	font:SetShadowOffset(0, 0)
	font:SetTextColor(r, g, b)
	return font
end

-- Dark colours only: light ones would get the general outline.
local function LinkFonts()
	if not linkFonts then
		linkFonts = {
			normal = LinkFont("ForeverPlusParchmentLink", unpack(PAGE_TEXT)),
			highlight = LinkFont("ForeverPlusParchmentLinkHover", 0.55, 0.1, 0),
			disabled = LinkFont("ForeverPlusParchmentLinkDisabled", 0.38, 0.3, 0.18),
		}
	end
	return linkFonts
end

-- The book symbol in the top left corner of the book window (no name).
local function BookIcon(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") then
			local layer, subLevel = region:GetDrawLayer()
			if layer == "OVERLAY" and subLevel == -1 then
				return region
			end
		end
	end
end

-- Parts of the windows: frame, regions to hide, scroll areas, buttons.
local function Windows()
	local windows = {}
	if QuestFrame then
		windows[#windows + 1] = {
			frame = QuestFrame,
			hide = { QuestFramePortrait, QuestFrameRewardPanel and QuestFrameRewardPanel.Bg, QuestFrameProgressPanel and QuestFrameProgressPanel.Bg,
				QuestFrameDetailPanel and QuestFrameDetailPanel.Bg, QuestFrameGreetingPanel and QuestFrameGreetingPanel.Bg },
			scrolls = { QuestDetailScrollFrame, QuestProgressScrollFrame, QuestRewardScrollFrame, QuestGreetingScrollFrame },
			left = { QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton },
			right = { QuestFrameDeclineButton, QuestFrameGoodbyeButton, QuestFrameGreetingGoodbyeButton },
		}
	end
	local greeting = GossipFrame and GossipFrame.GreetingPanel
	if greeting then
		windows[#windows + 1] = {
			frame = GossipFrame,
			hide = {},
			scrolls = { greeting.ScrollBox },
			bars = { greeting.ScrollBar },
			left = {},
			right = { greeting.GoodbyeButton },
		}
	end
	if ItemTextFrame then
		windows[#windows + 1] = {
			frame = ItemTextFrame,
			book = true,
			hide = { ItemTextFramePageBg, ItemTextCurrentPage, BookIcon(ItemTextFrame), ItemTextPrevPageButton, ItemTextNextPageButton },
			noMouse = { ItemTextPrevPageButton, ItemTextNextPageButton },
			scrolls = { ItemTextScrollFrame },
			left = {},
			right = {},
		}
	end
	return windows
end

-- Direction in which the visible text goes on: "down", "up" or nil.
local function ScrollState(area)
	if not area or not area:IsVisible() then
		return nil
	end
	if area.GetVerticalScrollRange then
		local range = ns.Number(area:GetVerticalScrollRange(), 0)
		if range <= 1 then
			return nil
		end
		return ns.Number(area:GetVerticalScroll(), 0) < range - 1 and "down" or "up"
	end
	if area.HasScrollableExtent and area:HasScrollableExtent() then
		return ns.Number(area:GetScrollPercentage(), 0) < 0.99 and "down" or "up"
	end
end

local function UpdateArrow(page)
	local direction
	for _, area in ipairs(page.window.scrolls) do
		direction = direction or ScrollState(area)
	end
	if direction ~= page.direction then
		page.direction = direction
		page.Arrow:SetShown(direction ~= nil)
		if direction then
			page.Arrow:SetAtlas(direction == "down" and "minimal-scrollbar-arrow-bottom" or "minimal-scrollbar-arrow-top", true)
		end
	end
end

-- The NPC or book name may be a protected value; it is only handed on, never tested.
local function UpdateName(page)
	local title = page.window.frame.GetTitleText and page.window.frame:GetTitleText()
	page.Name:SetText(title and title:GetText())
end

local function SetParchment(texture)
	if not texture:SetAtlas("QuestBG-Parchment") then
		texture:SetColorTexture(0.84, 0.74, 0.55)
	end
end

-- Text link of ForeverPlus (book pages).
local function PageLink(page, text, point, x, onClick)
	local fonts = LinkFonts()
	local link = CreateFrame("Button", nil, page)
	link:SetNormalFontObject(fonts.normal)
	link:SetHighlightFontObject(fonts.highlight)
	link:SetText(text)
	link:SetSize(ns.Number(link:GetTextWidth(), 0) + LINK_PADDING, 22)
	link:SetPoint(point, page, point, x, 5)
	link:SetScript("OnClick", onClick)
	link:Hide()
	return link
end

-- Book pages: own links and page number instead of Blizzard's buttons.
local function UpdatePaging(page)
	local number = ns.Number(ItemTextGetPage(), 1)
	local hasNext = ItemTextHasNextPage()
	page.Prev:SetShown(number > 1)
	page.Next:SetShown(hasNext and true or false)
	page.Number:SetText((number > 1 or hasNext) and number or "")
end

local function TurnPage(turn)
	return function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		turn()
	end
end

-- Blizzard puts the book text down to the bottom on every page; the links
-- need the space below it.
local function PlaceBookText()
	ItemTextScrollFrame:SetPoint("BOTTOMLEFT", ItemTextFrame, "BOTTOMLEFT", 6, BOOK_TEXT_BOTTOM + (enabled and BOOK_FOOTER or 0))
end

local function CreatePage(window)
	local frame = window.frame
	local page = CreateFrame("Frame", nil, frame)
	page:SetUsingParentLevel(true)
	page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, PAGE_TOP)
	if window.book then
		page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", BOOK_RIGHT, PAGE_BOTTOM)
	else
		local bg = QuestFrameDetailPanel and QuestFrameDetailPanel.Bg
		local width = bg and ns.Number(bg:GetWidth(), 0) or 0
		width = (width > 0 and width or PARCHMENT_WIDTH) + PAGE_MARGIN
		page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PAGE_LEFT + width, PAGE_BOTTOM)
	end

	for i, shadow in ipairs(SHADOWS) do
		local texture = page:CreateTexture(nil, "BACKGROUND", nil, i - 1 - #SHADOWS)
		texture:SetPoint("TOPLEFT", shadow[1], shadow[2])
		texture:SetPoint("BOTTOMRIGHT", shadow[1], shadow[2])
		SetParchment(texture)
		texture:SetVertexColor(0, 0, 0, shadow[3])
	end
	local parchment = page:CreateTexture(nil, "BACKGROUND")
	parchment:SetAllPoints()
	SetParchment(parchment)

	local name = page:CreateFontString(nil, "ARTWORK")
	local face, size = QuestTitleFont:GetFont()
	name:SetFont(face, size, "")
	name:SetTextColor(unpack(PAGE_TEXT))
	name:SetPoint("TOPLEFT", 20, -12)
	name:SetPoint("TOPRIGHT", -20, -12)
	name:SetMaxLines(1)
	page.Name = name

	local divider = page:CreateTexture(nil, "ARTWORK")
	divider:SetTexture("Interface\\QuestFrame\\UI-HorizontalBreak")
	divider:SetSize(256, 32)
	divider:SetPoint("TOP", 0, -22)

	page.Arrow = page:CreateTexture(nil, "ARTWORK")
	page.Arrow:Hide()

	if window.book then
		page.Arrow:SetPoint("BOTTOM", 0, 22)
		page.Number = page:CreateFontString(nil, "ARTWORK", "QuestFont")
		page.Number:SetTextColor(unpack(PAGE_TEXT))
		page.Number:SetPoint("BOTTOM", 0, 9)
		page.Prev = PageLink(page, PREV, "BOTTOMLEFT", 8, TurnPage(ItemTextPrevPage))
		page.Next = PageLink(page, NEXT, "BOTTOMRIGHT", -8, TurnPage(ItemTextNextPage))
		hooksecurefunc(frame, "HandlePagingDisplay", function()
			UpdatePaging(page)
		end)
		frame:HookScript("OnEvent", function(_, event)
			if event == "ITEM_TEXT_READY" and enabled then
				PlaceBookText()
			end
		end)
	else
		page.Arrow:SetPoint("BOTTOM", 0, 11)
	end

	page.window = window
	local elapsed = 0
	page:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		if elapsed >= ARROW_INTERVAL then
			elapsed = 0
			UpdateArrow(self)
		end
	end)
	page:SetScript("OnShow", UpdateName)
	for _, method in ipairs({ "SetTitle", "SetTitleFormatted" }) do
		if frame[method] then
			hooksecurefunc(frame, method, function()
				UpdateName(page)
			end)
		end
	end
	pages[frame] = page
	return page
end

-- Blizzard button as a text link in a bottom corner of the page, or back.
local function StyleButton(button, page, side, plain)
	if not button then
		return
	end
	local saved = restyled[button]
	local highlight = button:GetHighlightTexture()
	if plain then
		if not saved then
			saved = { width = button:GetWidth(), points = {},
				normal = button:GetNormalFontObject(), highlight = button:GetHighlightFontObject(), disabled = button:GetDisabledFontObject() }
			for i = 1, button:GetNumPoints() do
				saved.points[i] = { button:GetPoint(i) }
			end
			restyled[button] = saved
		end
		local fonts = LinkFonts()
		button:SetNormalFontObject(fonts.normal)
		button:SetHighlightFontObject(fonts.highlight)
		button:SetDisabledFontObject(fonts.disabled)
		button:SetWidth(button:GetTextWidth() + LINK_PADDING)
		button:ClearAllPoints()
		if side == "left" then
			button:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 5)
		else
			button:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 5)
		end
	elseif saved then
		button:SetNormalFontObject(saved.normal)
		button:SetHighlightFontObject(saved.highlight)
		button:SetDisabledFontObject(saved.disabled)
		button:SetWidth(saved.width)
		button:ClearAllPoints()
		for _, point in ipairs(saved.points) do
			button:SetPoint(unpack(point))
		end
		restyled[button] = nil
	else
		return
	end
	for _, key in ipairs({ "Left", "Middle", "Right" }) do
		if button[key] then
			button[key]:SetAlpha(plain and 0 or 1)
		end
	end
	if highlight then
		highlight:SetAlpha(plain and 0 or 1)
	end
end

-- Invisible and out of the mouse's way; scrolling keeps working through it.
local function SetBarShown(bar, shown)
	if not bar then
		return
	end
	bar:SetAlpha(shown and 1 or 0)
	local track = bar.Track
	for _, part in ipairs({ track, track and track.Thumb, bar.Back, bar.Forward }) do
		part:EnableMouse(shown)
	end
end

---------------------------------------------------------------------------
-- Space continues the quest dialog (accept, continue, complete) like the
-- text link at the bottom left. The quest functions are called directly:
-- Blizzard's buttons may open confirmation dialogs, which must not be run
-- from addon code; those cases (PvP quest, quest costing money, reward not
-- chosen yet) stay with the mouse. Not in combat: key handling cannot be
-- changed there.
---------------------------------------------------------------------------
local function ContinueQuest()
	if QuestFrameDetailPanel:IsVisible() then
		if not QuestFrameAcceptButton:IsEnabled() or QuestFlagsPVP() then
			return false
		end
		if QuestFrame.autoQuest then
			AcknowledgeAutoAcceptQuest()
		else
			AcceptQuest()
		end
		return true
	elseif QuestFrameProgressPanel:IsVisible() then
		if not QuestFrameCompleteButton:IsEnabled() then
			return false
		end
		CompleteQuest()
		PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN)
		return true
	elseif QuestFrameRewardPanel:IsVisible() then
		local choices = GetNumQuestChoices()
		local choice = choices == 1 and 1 or ns.Number(QuestInfoFrame.itemChoice, 0)
		local money = GetQuestMoneyToGet()
		if not QuestFrameCompleteQuestButton:IsEnabled() or (choices > 1 and choice == 0) or (money and money > 0) then
			return false
		end
		GetQuestReward(choice)
		return true
	end
	return false
end

local questKeys

local function CreateQuestKeys()
	questKeys = CreateFrame("Frame", nil, QuestFrame)
	questKeys:EnableKeyboard(true)
	questKeys:SetPropagateKeyboardInput(true)
	questKeys:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		self:SetPropagateKeyboardInput(not (key == "SPACE" and ContinueQuest()))
	end)
	questKeys:SetScript("OnKeyUp", function(self)
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	-- Hidden in combat, where the key handling cannot be changed.
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", Parchment, function()
		questKeys:Hide()
	end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", Parchment, function()
		questKeys:SetShown(enabled)
	end)
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------
function Parchment.Update(plain)
	enabled = plain and true or false
	if QuestFrame and (plain or questKeys) and not InCombatLockdown() then
		if not questKeys then
			CreateQuestKeys()
		end
		questKeys:SetShown(plain)
	end
	for _, window in ipairs(Windows()) do
		local frame = window.frame
		local page = pages[frame] or (plain and CreatePage(window))
		for _, key in ipairs(CHROME) do
			local region = frame[key]
			if region and region.SetAlpha then
				region:SetAlpha(plain and 0 or 1)
			end
		end
		for _, region in pairs(window.hide) do
			region:SetAlpha(plain and 0 or 1)
		end
		for _, button in ipairs(window.noMouse or {}) do
			button:EnableMouse(not plain)
		end
		if frame.CloseButton then
			frame.CloseButton:SetShown(not plain)
		end
		for _, area in ipairs(window.scrolls) do
			SetBarShown(area.ScrollBar, not plain)
		end
		for _, bar in ipairs(window.bars or {}) do
			SetBarShown(bar, not plain)
		end
		if window.book and page then
			PlaceBookText()
			if plain then
				UpdatePaging(page)
			end
		end
		if page then
			page:SetShown(plain)
			for _, button in ipairs(window.left) do
				StyleButton(button, page, "left", plain)
			end
			for _, button in ipairs(window.right) do
				StyleButton(button, page, "right", plain)
			end
			if plain then
				UpdateName(page)
			end
		end
	end
end

-- Dialog bubble: the whole conversation with an NPC (gossip text and options,
-- quests on offer and in progress, quest text, objectives, rewards, buttons)
-- in one speech bubble above its head, in the look of the players' chat
-- bubbles. As an option it replaces Blizzard's gossip and quest windows: they
-- stay open but shrink to nothing (Escape still closes them). Steps that need
-- a Blizzard confirmation (PvP quests, quests with costs, auto-accepted
-- quests) show Blizzard's own window instead.
local _, ns = ...
local L = ns.L

local Dialog = ns:NewModule("Dialog", {
	title = L.DIALOG_TITLE,
	order = 5.6,
	defaults = {
		enabled = false,
		style = "PLAYER",
		plates = true,
		textSpeed = "INSTANT", -- INSTANT, NORMAL, SLOW: how fast the text appears
		trainer = true,        -- the trainer's list in the bubble too
		merchant = false,      -- the merchant's wares as a list in the bubble (test)
		merchantHide = false,  -- hide wares that cannot be used or are known already
		hidePlate = true,      -- the plate of the NPC is hidden while the bubble covers it
		onScreen = true,       -- a big bubble slides down or aside so that it stays on the screen
	},
})

local WIDTH = 340
local INSET = 16 -- the border art of the bubble lies this far around the content
local ROW_GAP, BLOCK_GAP = 3, 8
local ITEM_SIZE = 34

local PALETTES = {
	PLAYER = {
		text = { 1, 1, 1 }, name = { 1, 0.82, 0 }, title = { 1, 0.82, 0 },
		row = { 0.55, 0.8, 1 }, marker = "ffffd100", dim = { 0.65, 0.65, 0.65 },
	},
	DARK = {
		text = { 1, 1, 1 }, name = { 1, 0.82, 0 }, title = { 1, 0.82, 0 },
		row = { 0.45, 0.78, 1 }, marker = "ffffd100", dim = { 0.62, 0.62, 0.62 },
	},
}

local bubble
local current -- { view, selected }
local history = {} -- earlier gossip and greeting steps of this conversation, for "back"
local showToken = 0 -- counts the steps shown (a closing event only counts when no new step followed)
local collapsed = {} -- Blizzard window -> original scale

-- The last steps of the bubble with their time (/fp blase verlauf), to see in what order things happened when a
-- text shows up too early.
local trace = {}
local function Trace(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	if #trace >= 60 then
		table.remove(trace, 1)
	end
	trace[#trace + 1] = ("%.2f %s"):format(ns.Number(GetTime(), 0) % 1000, text)
end

local function WindowState(window)
	if not window then
		return "-"
	end
	local name = window:GetName()
	return ("%s:%s/%.3f/%.1f"):format(type(name) == "string" and name or "?", window:IsShown() and "an" or "aus", ns.Number(window:GetScale(), 0), ns.Number(window:GetAlpha(), 0))
end

local function Readable(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then
		return nil
	end
	return value
end

local function Palette()
	return PALETTES[Dialog.db.style] or PALETTES.PLAYER
end

---------------------------------------------------------------------------
-- Text that appears letter by letter, like a story being read aloud: the whole text is laid out at once
-- (so the bubble does not change size) and an alpha gradient uncovers it from the front.
---------------------------------------------------------------------------
local REVEAL_SPEEDS = { NORMAL = 70, SLOW = 28 } -- letters per second
local REVEAL_SOFT = 4                              -- letters of the soft edge
local reveal = { list = {}, index = 1, position = 0, active = false }

local function FinishReveal()
	Trace("Lesen beendet (aktiv %s, %d Absätze)", tostring(reveal.active), #reveal.list)
	for _, fontString in ipairs(reveal.list) do
		fontString:SetAlpha(1)
		fontString:SetAlphaGradient(100000, 1)
	end
	reveal.active = false
	wipe(reveal.list)
	if bubble then
		ns.SetUpdate(bubble, "Dialog: text reveal", nil)
	end
end

local function RevealStep(_, elapsed)
	local speed = REVEAL_SPEEDS[Dialog.db.textSpeed]
	local fontString = reveal.list[reveal.index]
	if not speed or not fontString then
		FinishReveal()
		return
	end
	reveal.position = reveal.position + elapsed * speed
	local length = reveal.lengths[reveal.index]
	fontString:SetAlphaGradient(reveal.position, REVEAL_SOFT)
	fontString:SetAlpha(1) -- only after the gradient is set: no frame with the whole text
	if reveal.position >= length + REVEAL_SOFT then
		fontString:SetAlphaGradient(100000, 1)
		reveal.index = reveal.index + 1
		reveal.position = 0
		local nextOne = reveal.list[reveal.index]
		if nextOne then
			nextOne:SetAlphaGradient(0, REVEAL_SOFT)
		else
			FinishReveal()
		end
	end
end

-- The state of the reveal on the font strings again (after the step was drawn anew): read paragraphs stay
-- whole, the one being read keeps its place, the rest is hidden.
local function ApplyReveal()
	for index, fontString in ipairs(reveal.list) do
		if index < reveal.index then
			fontString:SetAlphaGradient(100000, 1)
			fontString:SetAlpha(1)
		elseif index == reveal.index then
			fontString:SetAlphaGradient(reveal.position, REVEAL_SOFT)
			fontString:SetAlpha(1)
		else
			fontString:SetAlpha(0)
			fontString:SetAlphaGradient(0, REVEAL_SOFT)
		end
	end
end

-- texts: the font strings of the paragraphs, in reading order. Each view is revealed once.
local function StartReveal(view, texts)
	-- The same step drawn again while it is being read (a list refreshed itself, rewards arrived): the reading goes
	-- on where it was instead of showing the whole text for a moment.
	Trace("Lesen: %s, %d Absätze, gelesen %s, aktiv %s", view.kind or "?", #texts, tostring(view.revealed), tostring(reveal.active))
	if view.revealed and reveal.active and #texts == #reveal.list then
		for index, fontString in ipairs(texts) do
			reveal.list[index] = fontString
		end
		ApplyReveal()
		return
	end
	if reveal.active then
		FinishReveal()
	end
	if view.revealed or not REVEAL_SPEEDS[Dialog.db.textSpeed] or #texts == 0 then
		return
	end
	view.revealed = true
	reveal.active, reveal.index, reveal.position = true, 1, 0
	reveal.lengths = {}
	for index, fontString in ipairs(texts) do
		reveal.list[index] = fontString
		reveal.lengths[index] = strlenutf8 and strlenutf8(fontString:GetText() or "") or #(fontString:GetText() or "")
		fontString:SetAlpha(0)
		fontString:SetAlphaGradient(0, REVEAL_SOFT)
	end
	ns.SetUpdate(bubble, "Dialog: text reveal", RevealStep)
end

---------------------------------------------------------------------------
-- The bubble
---------------------------------------------------------------------------
-- Digits typed one after the other make one number (1 then 4 within half a second is 14). The row is taken at once
-- when no longer number can follow, else when the half second is over.
local TYPE_WAIT = 0.5

function Dialog.TypeNumber(frame, digit)
	frame.typed = (frame.typed or "") .. digit
	frame.typedToken = (frame.typedToken or 0) + 1
	local token = frame.typedToken
	local function Take()
		if frame.typedToken ~= token then
			return
		end
		local number = tonumber(frame.typed)
		frame.typed = nil
		local index = number and frame.numberIndex[number]
		local action = index and frame.rowActions[index]
		if action then
			action()
		end
	end
	if tonumber(frame.typed) * 10 > frame.maxRowNumber or #frame.typed >= 3 then
		Take()
	else
		C_Timer.After(TYPE_WAIT, Take)
	end
end

local function CreateBubble()
	local frame = CreateFrame("Frame", "ForeverPlusDialogBubble", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(true)
	frame:SetScript("OnMouseDown", function()
		if reveal.active then
			FinishReveal()
		end
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		if current and current.view.kind == "MERCHANT_SHOW" then
			Dialog.MerchantScroll(delta)
		elseif current and current.view.kind == "TRAINER_SHOW" then
			Dialog.TrainerScroll(delta)
		end
	end)
	frame:SetWidth(WIDTH)
	frame:Hide()
	ns.FadeIn(frame, 0.25)
	-- Dark variant: one plain pane.
	frame.Dark = frame:CreateTexture(nil, "BACKGROUND")
	frame.Dark:SetPoint("TOPLEFT", -INSET / 2, INSET / 2)
	frame.Dark:SetPoint("BOTTOMRIGHT", INSET / 2, -INSET / 2)
	frame.Dark:SetTexture([[Interface\Tooltips\UI-Tooltip-Background]])
	frame.Dark:SetVertexColor(0.08, 0.08, 0.1, 0.94)
	frame.DarkBorder = ns.CreatePixelBorder(frame, frame.Dark, 1, "BORDER")
	-- Player variant: the nine-slice art and tail of the chat bubbles.
	frame.Art, frame.Tail = ns.CreateBubbleArt(frame, INSET, -10, ns.PANEL_BORDER)
	frame.hasArt = frame.Art ~= nil
	frame.hasTail = frame.Tail ~= nil
	frame.Abandon = CreateFrame("Button", nil, frame)
	frame.Abandon:SetSize(16, 16)
	frame.Abandon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 10, 10)
	frame.Abandon.Icon = frame.Abandon:CreateTexture(nil, "ARTWORK")
	frame.Abandon.Icon:SetAllPoints()
	frame.Abandon.Icon:SetAtlas("common-icon-redx")
	frame.Abandon:SetScript("OnEnter", function(self)
		self.Icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.DIALOG_ABANDON)
		GameTooltip_AddNormalLine(GameTooltip, self.armed and L.DIALOG_ABANDON_CONFIRM or L.DIALOG_ABANDON_HINT)
		GameTooltip:Show()
	end)
	frame.Abandon:SetScript("OnLeave", function(self)
		self.Icon:SetVertexColor(self.armed and 1 or 0.8, self.armed and 0.4 or 0.8, self.armed and 0.4 or 0.8)
		GameTooltip_Hide()
	end)
	frame.Abandon:SetScript("OnClick", function(self)
		if not self.armed then
			self.armed = true
			self.Icon:SetVertexColor(1, 0.4, 0.4)
			GameTooltip:Hide()
			C_Timer.After(3, function()
				self.armed = false
			end)
			return
		end
		Dialog.AbandonQuest(self.questID)
	end)
	-- Space takes the main step (accept, continue, complete), like in the parchment windows.
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(true)
	frame:SetScript("OnKeyDown", function(self, key)
		-- In combat the game does not let an addon change what a key does (SetPropagateKeyboardInput): the keys
		-- stay with the game, and each key that was taken is given back when it is released (OnKeyUp below).
		if InCombatLockdown() then
			return
		end
		local action
		if current and not InCombatLockdown() and (key == "TAB" or not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown())) then
			-- Lists that spend money (merchant, trainer) are never bought from with a key: Space is also the jump
			-- key and the number keys are the action bar. There Space only takes a row the cursor was moved to.
			local spends = current.view.kind == "MERCHANT_SHOW" or current.view.kind == "TRAINER_SHOW"
			if key == "SPACE" then
				for _, info in ipairs(current.view.buttons or {}) do
					if info.primary and info.enabled ~= false and not info.spends then
						action = info.action
					end
				end
				-- Otherwise the chosen option (the first one, or the one picked with Tab).
				if not action and (not spends or self.cursorMoved) then
					action = self.rowActions[self.selectedRow or 1]
				end
				-- Only a "goodbye" to choose: Space says it.
				if not action and not spends and #self.rowActions == 0 and #(current.view.buttons or {}) == 1 then
					local only = current.view.buttons[1]
					action = only.enabled ~= false and only.action or nil
				end
			elseif key == "TAB" or key == "UP" or key == "DOWN" then
				local count = #self.rowActions
				if count > 1 then
					local step = (key == "UP" or (key == "TAB" and IsShiftKeyDown())) and -1 or 1
					self.selectedRow = ((self.selectedRow or 1) - 1 + step) % count + 1
					self.cursorMoved = true
					Dialog.Rerender()
					self:SetPropagateKeyboardInput(false)
					return
				end
			else
				-- The digits (also on the number block) choose the numbered options; for lists with more than nine rows
				-- two digits in a row (14) make one number. Choosing never buys or learns, that is the button's.
				local digit = tonumber(key:match("^NUMPAD(%d)$") or key:match("^(%d)$"))
				if digit and digit <= (self.maxRowNumber or 0) then
					action = function()
						Dialog.TypeNumber(self, digit)
					end
				end
			end
		end
		self:SetPropagateKeyboardInput(not action)
		if action then
			action()
		end
	end)
	frame:SetScript("OnKeyUp", function(self)
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	frame.pools = { text = {}, row = {}, item = {}, button = {} }
	-- Merchant list: a small grey book icon of the game (round, like the buttons at the minimap) at the lower right
	-- corner, mirror image of the x at the top right (same size, same distance); a small red x over it while
	-- unusable and known wares are hidden.
	local filter = CreateFrame("Button", nil, frame)
	filter:SetSize(14, 14)
	filter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
	ns.SetRoundGreyIcon(filter, [[Interface\Icons\INV_Misc_Book_09]])
	filter.Cross = filter:CreateTexture(nil, "OVERLAY")
	filter.Cross:SetAtlas("common-icon-redx")
	filter.Cross:SetSize(10, 10)
	filter.Cross:SetPoint("CENTER")
	filter:SetScript("OnEnter", function(self)
		self.hover = true
		Dialog.UpdateFilter()
	end)
	filter:SetScript("OnLeave", function(self)
		self.hover = nil
		Dialog.UpdateFilter()
	end)
	filter:SetScript("OnClick", function()
		ns.SetOption("Dialog", "merchantHide", not Dialog.db.merchantHide)
		Dialog.OnConversation(Dialog, "MERCHANT_UPDATE")
	end)
	filter:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.DIALOG_MERCHANT_HIDE)
		GameTooltip_AddNormalLine(GameTooltip, Dialog.db.merchantHide and L.DIALOG_FILTER_ON or L.DIALOG_FILTER_OFF)
		GameTooltip:Show()
	end)
	filter:HookScript("OnLeave", GameTooltip_Hide)
	filter:Hide()
	frame.Filter = filter
	-- Beside the book, same style and size: repair, sell junk, restock (each only where the merchant can do it).
	frame.Tools = {}
	local function Tool(key, texture, onClick, onTip)
		local tool = CreateFrame("Button", nil, frame)
		tool:SetSize(14, 14)
		ns.SetRoundGreyIcon(tool, texture)
		tool:SetScript("OnEnter", function(self)
			self.hover = true
			self.Icon:SetAlpha(1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			onTip(GameTooltip)
			GameTooltip:Show()
		end)
		tool:SetScript("OnLeave", function(self)
			self.hover = nil
			self.Icon:SetAlpha(self.enabledLook and 0.6 or 0.3)
			GameTooltip_Hide()
		end)
		tool:SetScript("OnClick", function(self)
			if self.enabledLook then
				onClick()
			end
		end)
		tool:Hide()
		frame.Tools[key] = tool
	end
	Tool("locked", [[Interface\Icons\INV_Misc_Book_09]], function()
		Dialog.ToggleTrainerLocked()
	end, function(tooltip)
		GameTooltip_SetTitle(tooltip, L.DIALOG_TOOL_LOCKED)
		GameTooltip_AddNormalLine(tooltip, Dialog.showLocked and L.DIALOG_TOOL_LOCKED_ON or L.DIALOG_TOOL_LOCKED_OFF)
	end)
	Tool("repair", [[Interface\Icons\Trade_BlackSmithing]], function()
		local tools = ns.MerchantTools
		if tools then
			Dialog.repairDone = true
			tools.Repair()
		end
	end, function(tooltip)
		local cost = GetRepairAllCost()
		GameTooltip_SetTitle(tooltip, L.DIALOG_REPAIR)
		GameTooltip_AddNormalLine(tooltip, GetMoneyString(cost or 0, true))
	end)
	Tool("sell", [[Interface\Icons\INV_Misc_Coin_01]], function()
		local tools = ns.MerchantTools
		if tools then
			tools.SellJunk()
		end
	end, function(tooltip)
		local tools = ns.MerchantTools
		local count, value = 0, 0
		if tools then
			count, value = tools.JunkValue()
		end
		GameTooltip_SetTitle(tooltip, L.DIALOG_SELL_JUNK:format(count))
		GameTooltip_AddNormalLine(tooltip, GetMoneyString(value or 0, true))
	end)
	Tool("restock", [[Interface\Icons\INV_Misc_Bag_08]], function()
		local restock = ns:GetModule("Restock")
		restock.MerchantBuy()
	end, function(tooltip)
		local restock = ns:GetModule("Restock")
		local plan, cost = restock.MerchantPlan()
		GameTooltip_SetTitle(tooltip, L.DIALOG_TOOL_RESTOCK)
		GameTooltip_AddNormalLine(tooltip, L.DIALOG_TOOL_RESTOCK_TIP)
		for _, entry in ipairs(plan) do
			tooltip:AddLine(("%d x %s"):format(entry.amount, entry.name), 1, 1, 1)
		end
		tooltip:AddLine(GetMoneyString(cost, true), 1, 1, 1)
	end)
	-- Merchant list: what the mouse does, as small symbols at the top right (where the x used to be): left button
	-- plus (more), right button minus (fewer), Shift + left button several wares; the words are in the tooltip.
	frame.Help = CreateFrame("Frame", nil, frame)
	frame.Help:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 1)
	frame.Help:SetHeight(14)
	frame.Help:EnableMouse(true)
	frame.Help.Text = frame.Help:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Help.Text:SetPoint("RIGHT")
	frame.Help.Text:SetJustifyH("RIGHT")
	frame.Help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip_SetTitle(GameTooltip, L.DIALOG_MERCHANT_HELP_TITLE)
		GameTooltip_AddNormalLine(GameTooltip, L.DIALOG_MERCHANT_HELP)
		GameTooltip:Show()
	end)
	frame.Help:SetScript("OnLeave", GameTooltip_Hide)
	frame.Help:Hide()
	frame.rowActions = {} -- the options of the step on show, in the order of their numbers
	frame.numberIndex = {} -- number shown in front of a row -> its place in rowActions
	frame.maxRowNumber = 0
	frame.selectedRow = 1
	return frame
end

local function Pooled(frame, kind, index, create)
	local pool = frame.pools[kind]
	local object = pool[index]
	if not object then
		object = create(frame)
		pool[index] = object
	end
	return object
end

local function TextFont()
	return _G.ChatBubbleFont and "ChatBubbleFont" or "GameFontNormal"
end

local function CreateText(frame)
	local text = frame:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(TextFont())
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetNonSpaceWrap(true)
	return text
end

local function CreateRow(frame)
	local row = CreateFrame("Button", nil, frame)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("TOPLEFT", 0, -1)
	-- Small green arrow between the icon and the number: the ware beats what is worn.
	row.Arrow = row:CreateTexture(nil, "OVERLAY")
	row.Arrow:SetAtlas("bags-greenarrow")
	row.Arrow:SetSize(12, 12)
	row.Arrow:SetPoint("TOPLEFT", 21, -2)
	row.Arrow:Hide()
	row.Text = row:CreateFontString(nil, "OVERLAY")
	row.Text:SetFontObject(TextFont())
	row.Text:SetJustifyH("LEFT")
	row.Text:SetJustifyV("TOP")
	row.Text:SetNonSpaceWrap(true)
	row.Highlight = row:CreateTexture(nil, "BACKGROUND")
	row.Highlight:SetPoint("TOPLEFT", -3, 1)
	row.Highlight:SetPoint("BOTTOMRIGHT", 3, -1)
	row.Highlight:SetColorTexture(0, 0, 0, 0.1)
	row.Highlight:Hide()
	-- In the basket / chosen: a soft green tint, and the counter of the quantity (a click types a number).
	row.Picked = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.Picked:SetPoint("TOPLEFT", -4, 2)
	row.Picked:SetPoint("BOTTOMRIGHT", 4, -2)
	row.Picked:SetColorTexture(0.25, 0.9, 0.35, 0.16)
	row.Picked:Hide()
	-- The quantity of a ware in the basket: the game's own input field right of the row (left clicks on the row
	-- count up, right clicks down; the number can be typed too).
	row.Qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.Qty:SetSize(40, 20)
	row.Qty:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.Qty:SetAutoFocus(false)
	row.Qty:SetNumeric(true)
	row.Qty:SetMaxLetters(3)
	row.Qty:SetJustifyH("CENTER")
	row.Qty:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local number = tonumber(self:GetText())
		if number and row.onQuantity then
			row.onQuantity(number)
		end
	end)
	row.Qty:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	row.Qty:Hide()
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta)
		if bubble and current and current.view.kind == "MERCHANT_SHOW" then
			Dialog.MerchantScroll(delta)
		elseif bubble and current and current.view.kind == "TRAINER_SHOW" then
			Dialog.TrainerScroll(delta)
		end
	end)
	-- The chosen text is a little fuller: warm copies of it one pixel around it (eight directions), very faint, under
	-- the text itself; no wider halo, so it reads as weight, not as shine.
	row.Glow = {}
	for _, direction in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 }, { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }) do
		local glow = row:CreateFontString(nil, "ARTWORK", nil)
		glow:SetPoint("TOPLEFT", row.Text, "TOPLEFT", direction[1], direction[2])
		glow:SetPoint("BOTTOMRIGHT", row.Text, "BOTTOMRIGHT", direction[1], direction[2])
		glow:SetJustifyH("LEFT")
		glow:SetJustifyV("TOP")
		glow:SetNonSpaceWrap(true)
		glow:SetTextColor(1, 0.72, 0.2, 0.1)
		glow:Hide()
		row.Glow[#row.Glow + 1] = glow
	end
	row:SetScript("OnEnter", function(button)
		button.Highlight:Show()
		if button.tooltip then
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			button.tooltip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(button)
		button.Highlight:Hide()
		GameTooltip_Hide()
	end)
	row:SetScript("OnClick", function(button, mouseButton)
		-- A click moves the arrow to the row, then does what the row does.
		if button.number and bubble and bubble.selectedRow ~= button.number then
			bubble.selectedRow = button.number
			Dialog.Rerender()
		end
		if button.action then
			button.action(mouseButton)
		end
	end)
	return row
end

local function CreateItem(frame)
	local item = CreateFrame("Button", nil, frame)
	item:SetSize(ITEM_SIZE, ITEM_SIZE)
	item.Icon = item:CreateTexture(nil, "ARTWORK")
	item.Icon:SetAllPoints()
	item.Count = item:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	item.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	-- Action button frame, tinted in the item quality; green arrow when it beats the worn item.
	ns.ApplyActionFrame(item, item.Icon, "standalone", 3)
	-- The coin of the junk mark: the choice that sells for the most.
	item.Coin = item:CreateTexture(nil, "OVERLAY", nil, 6)
	item.Coin:SetAtlas("bags-junkcoin", true)
	item.Coin:SetPoint("TOPLEFT", 1, 0)
	item.Coin:Hide()
	item.Upgrade = item:CreateTexture(nil, "OVERLAY", nil, 6)
	item.Upgrade:SetAtlas("bags-greenarrow", true)
	item.Upgrade:SetPoint("TOPRIGHT", 0, 0)
	item.Upgrade:Hide()
	-- The chosen item glows like the buttons the game points out (the classic gold glow around an action button,
	-- added on top of the picture, breathing softly); no square behind it.
	item.Chosen = item:CreateTexture(nil, "OVERLAY", nil, 7)
	item.Chosen:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
	item.Chosen:SetBlendMode("ADD")
	item.Chosen:SetPoint("CENTER")
	item.Chosen:SetSize(ITEM_SIZE * 1.75, ITEM_SIZE * 1.75)
	item.Chosen:SetVertexColor(1, 0.85, 0.4)
	item.Chosen.Pulse = item.Chosen:CreateAnimationGroup()
	item.Chosen.Pulse:SetLooping("BOUNCE")
	local pulse = item.Chosen.Pulse:CreateAnimation("Alpha")
	pulse:SetFromAlpha(1)
	pulse:SetToAlpha(0.45)
	pulse:SetDuration(0.8)
	pulse:SetSmoothing("IN_OUT")
	item.Chosen:Hide()
	item:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tooltip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	item:SetScript("OnLeave", GameTooltip_Hide)
	item:SetScript("OnClick", function(self)
		if self.action then
			self.action()
		end
	end)
	return item
end

local function CreateButton(frame)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetHeight(22)
	button:SetScript("OnClick", function(self)
		if self.action then
			self.action()
		end
	end)
	-- Some buttons explain themselves (the total price of "train all").
	button:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tooltip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local Render

-- Blocks: { text }, { title }, { rows }, { items, header, choose }, { money }.
-- buttons: { text, action, enabled }.
Render = function(view)
	local frame = bubble
	local palette = Palette()
	local usePlayer = Dialog.db.style == "PLAYER" and frame.hasArt
	frame.Dark:SetShown(not usePlayer)
	if usePlayer then
		frame.DarkBorder:Hide()
	else
		frame.DarkBorder:ShowColor(unpack(ns.PANEL_BORDER))
	end
	if frame.Art then
		frame.Art:SetShown(usePlayer)
	end
	if frame.Tail then
		frame.Tail:SetShown(usePlayer)
	end
	local used = { text = 0, row = 0, item = 0, button = 0 }
	local bestChoice, bestChecked -- most valuable quest choice, looked up once per display
	for _, pool in pairs(frame.pools) do
		for _, object in pairs(pool) do
			object:Hide()
		end
	end
	local y = 0
	local paragraphs = {}
	wipe(frame.rowActions)
	wipe(frame.numberIndex)
	frame.maxRowNumber = 0
	local function AddText(text, color, font)
		used.text = used.text + 1
		local fs = Pooled(frame, "text", used.text, CreateText)
		fs:SetFontObject(font or TextFont())
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
		fs:SetWidth(WIDTH)
		fs:SetTextColor(unpack(color))
		fs:SetText(text)
		fs:SetAlpha(1)
		fs:SetAlphaGradient(100000, 1)
		fs:Show()
		y = y + fs:GetStringHeight() + BLOCK_GAP
		return fs
	end

	if view.name and view.name ~= "" then
		AddText(view.name, palette.name)
	end
	for _, block in ipairs(view.blocks) do
		if block.title then
			AddText(block.title, palette.title, _G.GameFontNormalLarge and "GameFontNormalLarge" or nil)
		elseif block.text then
			paragraphs[#paragraphs + 1] = AddText(block.text, block.dim and palette.dim or palette.text)
		elseif block.rows then
			for _, info in ipairs(block.rows) do
				used.row = used.row + 1
				local row = Pooled(frame, "row", used.row, CreateRow)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
				row:SetWidth(WIDTH)
				local iconWidth = (info.icon and 20 or 0) + (info.arrowSlot and 14 or 0)
				row.Arrow:SetShown(info.upgrade and true or false)
				row.Icon:SetShown(info.icon ~= nil)
				if info.icon then
					row.Icon:SetTexture(info.icon)
				end
				row.Text:ClearAllPoints()
				row.Text:SetPoint("TOPLEFT", iconWidth, 0)
				row.Text:SetWidth(WIDTH - iconWidth)
				row.Text:SetTextColor(unpack(info.dim and palette.dim or palette.row))
				-- Every option that can be chosen has a number (key 1 to 9).
				local label = info.text
				if info.action then
					frame.rowActions[#frame.rowActions + 1] = info.action
					-- The number of a row is its place in the whole list (a scrolled list goes on counting).
					local number = info.number or #frame.rowActions
					frame.numberIndex[number] = #frame.rowActions
					frame.maxRowNumber = math.max(frame.maxRowNumber, number)
					label = ("|cff9a9a9a%d.|r %s"):format(number, info.text)
				end
				-- The row that is chosen (clicked or lit with Tab): a little larger and bold, as under a magnifying glass.
				local emphasised = info.action and #frame.rowActions == frame.selectedRow
				-- Always set the font itself: a font object set again would not undo an earlier size.
				local baseFont = _G[TextFont()]
				local file, size, flags
				if baseFont then
					file, size, flags = baseFont:GetFont()
				end
				if file and size then
					row.Text:SetFont(file, emphasised and size * 1.2 or size, emphasised and "" or flags or "")
				else
					row.Text:SetFontObject(TextFont())
				end
				-- In the basket: a tick in front (the others get a blank of the same width).
				label = (info.picked and "|A:common-icon-checkmark:14:14|a " or "|TInterface\\Common\\Spacer:14:14|t ") .. label
				row.Text:SetText(label)
				row.Picked:SetShown(info.picked and true or false)
				row.onQuantity = info.onQuantity
				row.Qty:SetShown(info.counter ~= nil)
				if info.counter and not row.Qty:HasFocus() then
					row.Qty:SetText(tostring(info.counter))
				end
				-- Lists with a quantity field keep one line and a free column on the right: nothing wraps or shifts.
				row.Text:SetWordWrap(not info.reserve)
				row.Text:SetWidth(WIDTH - iconWidth - (info.reserve or 0))
				-- The chosen text stands out: brighter and warm next to the rest.
				row.Text:SetTextColor(unpack(emphasised and { 1, 0.97, 0.78 } or (info.dim and palette.dim or palette.row)))
				row.number = info.action and #frame.rowActions or nil
				for _, glow in ipairs(row.Glow) do
					glow:SetShown(emphasised and true or false)
					if emphasised then
						if file and size then
							glow:SetFont(file, size * 1.2, "")
						end
						glow:SetWordWrap(not info.reserve)
						-- No colour codes (the glow has its own colour) and no icons (blank spaces of the same size).
						glow:SetText((label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "|TInterface\\Common\\Spacer:14:14|t")
							:gsub("|A[^|]*|a", "|TInterface\\Common\\Spacer:14:14|t")))
					end
				end

				local height = math.max(row.Text:GetStringHeight(), 16)
				row:SetHeight(height)
				row.action, row.tooltip = info.action, info.tooltip
				row:Show()
				y = y + height + ROW_GAP
			end
			y = y + BLOCK_GAP - ROW_GAP
		elseif block.items then
			if block.header then
				AddText(block.header, palette.name)
			end
			local x = 0
			for _, info in ipairs(block.items) do
				used.item = used.item + 1
				local item = Pooled(frame, "item", used.item, CreateItem)
				item:ClearAllPoints()
				item:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
				item.Icon:SetTexture(info.icon)
				item.Count:SetText((info.count or 1) > 1 and info.count or "")
				local r, g, b
				if info.quality and info.quality >= 1 then
					r, g, b = C_Item.GetItemQualityColor(info.quality)
				end
				ns.SizeActionFrame(item)
				ns.SetActionFrameColor(item, r, g, b)
				if info.choice and bestChoice == nil and not bestChecked then
					bestChecked = true
					bestChoice = ns.BestQuestChoice and ns.BestQuestChoice(function()
						if bubble:IsShown() and current then
							Render(current.view)
						end
					end) or false
				end
				item.Coin:SetShown(info.choice ~= nil and bestChoice == info.choice)
				item.Upgrade:SetShown(ns.IsRewardUpgrade and ns.IsRewardUpgrade(info.link, function()
					if bubble:IsShown() and current then
						Render(current.view)
					end
				end) and true or false)
				item.tooltip = info.tooltip
				local chosen = block.choose and current and current.selected == info.choice or false
				item.Chosen:SetShown(chosen)
				if chosen then
					item.Chosen.Pulse:Play()
				else
					item.Chosen.Pulse:Stop()
				end
				item.action = block.choose and function()
					current.selected = info.choice
					Render(view)
				end or nil
				item:Show()
				x = x + ITEM_SIZE + 6
				if x + ITEM_SIZE > WIDTH then
					x = 0
					y = y + ITEM_SIZE + 6
				end
			end
			if x > 0 then
				y = y + ITEM_SIZE + 6
			end
			y = y + BLOCK_GAP - 6
		elseif block.money then
			AddText(block.money, palette.text)
		end
	end
	if frame.selectedRow > #frame.rowActions and not frame.reclamped then
		-- The arrow row no longer exists: once more with the last one chosen, so the fonts match.
		frame.selectedRow = math.max(1, #frame.rowActions)
		frame.reclamped = true
		Render(view)
		frame.reclamped = nil
		return
	end
	-- Buttons side by side at the bottom: main step, "back" (when there is a step before), close.
	local buttons = {}
	for _, info in ipairs(view.buttons or {}) do
		buttons[#buttons + 1] = info
	end
	if #history > 0 then
		table.insert(buttons, math.max(#buttons, 1), { text = L.DIALOG_BACK, action = Dialog.GoBack })
	end
	-- Abandon the quest of this step (progress): a small cross at the top right, two clicks.
	frame.Filter:SetShown(view.filter and true or false)
	local helpOn = view.kind == "MERCHANT_SHOW" and view.filter and true or false
	frame.Help:SetShown(helpOn)
	if helpOn then
		-- Two clear symbols: the mouse buttons of the game's tutorials; without them the letters L and R.
		local function Mouse(atlas, letter)
			return C_Texture.GetAtlasInfo(atlas) and ("|A:%s:15:15|a"):format(atlas) or letter
		end
		local left, right = Mouse("NPE_LeftClick", "L"), Mouse("NPE_RightClick", "R")
		frame.Help.Text:SetText(("%s +   %s -   Shift + %s ++"):format(left, right, left))
		frame.Help:SetWidth(frame.Help.Text:GetStringWidth() + 2)
	end
	Dialog.UpdateTools(view)
	Dialog.UpdateFilter()
	frame.Abandon:SetShown(view.abandonQuestID ~= nil)
	frame.Abandon.questID = view.abandonQuestID
	frame.Abandon.armed = false
	frame.Abandon.Icon:SetVertexColor(0.8, 0.8, 0.8)
	if #buttons > 0 then
		local x = 0
		for _, info in ipairs(buttons) do
			used.button = used.button + 1
			local button = Pooled(frame, "button", used.button, CreateButton)
			button:SetText(info.text)
			button:SetWidth(math.max(80, (button:GetTextWidth() or 56) + 24))
			button:ClearAllPoints()
			-- A new line when the next button does not fit.
			if x > 0 and x + button:GetWidth() > WIDTH then
				x = 0
				y = y + 22 + 4
			end
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
			button:SetEnabled(info.enabled ~= false)
			button.action = info.action
			button.tooltip = info.tooltip
			button:Show()
			x = x + button:GetWidth() + 6
		end
		y = y + 22 + 2
	else
		y = y - BLOCK_GAP
	end
	frame:SetHeight(math.max(y, 20))
	StartReveal(view, paragraphs)
end

---------------------------------------------------------------------------
-- Placement and Blizzard's windows
---------------------------------------------------------------------------
-- Who the talk is with, remembered when the bubble opens: the target changes during the talk and the plate of
-- the NPC must not be taken for another one (nor a plate frame the game gave to another unit).
local npcGuid

-- The unit the talk is with: "npc", else (some NPCs, guards for one, give no "npc" unit) the target or the soft
-- interaction target, if it is not the player.
local function TalkUnit()
	for _, token in ipairs({ "npc", "softinteract", "target" }) do
		if UnitExists(token) and not UnitIsUnit(token, "player") then
			return token
		end
	end
end

local function NpcNameplate()
	local unit = TalkUnit()
	if not unit and not npcGuid then
		return
	end
	local function Matches(token)
		local guid = UnitGUID(token)
		return guid and not (issecretvalue and issecretvalue(guid)) and guid == npcGuid
	end
	if npcGuid then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local token = plate.namePlateUnitToken
			if token and not plate:IsForbidden() and Matches(token) then
				return plate
			end
		end
		return nil
	end
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	if nameplate and not nameplate:IsForbidden() then
		return nameplate
	end
end

-- The bubble sits on the lower edge of the plate and covers it: the plate is made invisible meanwhile.
local hiddenPlate, hiddenAlpha

local function RestorePlate()
	if hiddenPlate and hiddenPlate.UnitFrame and not hiddenPlate:IsForbidden() then
		hiddenPlate.UnitFrame:SetAlpha(hiddenAlpha or 1)
	end
	hiddenPlate, hiddenAlpha = nil, nil
end

local function HidePlate(plate)
	if hiddenPlate and hiddenPlate ~= plate then
		RestorePlate()
	end
	if plate and plate.UnitFrame and not plate:IsForbidden() then
		if hiddenPlate ~= plate then
			hiddenAlpha = ns.Number(plate.UnitFrame:GetAlpha(), 1)
			hiddenPlate = plate
		end
		plate.UnitFrame:SetAlpha(0)
	end
end

local function Place()
	bubble:ClearAllPoints()
	local nameplate = NpcNameplate()
	if nameplate then
		bubble:SetPoint("BOTTOM", nameplate, "BOTTOM", 0, INSET + 6)
		if Dialog.db.hidePlate then
			HidePlate(nameplate)
		else
			RestorePlate()
		end
	else
		RestorePlate()
		bubble:SetPoint("TOP", UIParent, "TOP", 0, -140)
		-- The NPC has no plate: its plate is switched on for the talk, the bubble moves there.
		if Dialog.db.plates then
			ns.ShowFriendlyPlates(true)
		end
	end
end

-- Blizzard's window stays open (it carries the conversation) but takes no room.
local function Collapse(window, on)
	if not window or window:IsForbidden() then
		return
	end
	if on then
		if not window:IsShown() then
			return
		end
		if not collapsed[window] then
			collapsed[window] = window:GetScale()
		end
		window:SetScale(0.001)
		window:SetAlpha(0)
	elseif collapsed[window] then
		local scale = collapsed[window]
		collapsed[window] = nil -- first: the hook below must not take the window back
		window:SetScale(scale)
		window:SetAlpha(1)
	end
end

-- The game gives size and opacity back to its windows after they show (panel layout, fitting to the screen): a
-- window the bubble holds is taken back at once, so there is no picture with the game's window (and its text) in
-- between.
local keepingCollapsed = false

local function KeepCollapsed(window)
	for _, method in ipairs({ "SetScale", "SetAlpha" }) do
		hooksecurefunc(window, method, function(self)
			-- Not while it is being taken back (the calls below run this hook again).
			if keepingCollapsed or not collapsed[self] or InCombatLockdown() then
				return
			end
			if ns.Number(self:GetScale(), 0) > 0.01 or ns.Number(self:GetAlpha(), 0) > 0 then
				Trace("Spiel gab Größe oder Deckkraft zurück: %s", WindowState(self))
				keepingCollapsed = true
				self:SetScale(0.001)
				self:SetAlpha(0)
				keepingCollapsed = false
			end
		end)
	end
end

local function CollapseAll(on)
	Collapse(GossipFrame, on)
	Collapse(QuestFrame, on)
	Collapse(ClassTrainerFrame, on)
	Collapse(MerchantFrame, on)
end

-- The game's windows are made invisible the moment they show (their own OnShow, before the next picture), not
-- only when our step arrives: no frame with the window of the game at full size in between.
local hookedWindows = {}

-- handled: tells whether the bubble takes this window over at the moment (else it stays as the game shows it).
local function HideWindowAtOnce(window, handled)
	if hookedWindows[window] or not window or window:IsForbidden() then
		return
	end
	hookedWindows[window] = true
	KeepCollapsed(window)
	window:HookScript("OnShow", function(self)
		Trace("Fenster zeigt sich: %s", WindowState(self))
		if Dialog.db.enabled and handled() and not InCombatLockdown() then
			Collapse(self, true)
		end
	end)
	window:HookScript("OnHide", function(self)
		Collapse(self, false)
	end)
end

local function HookWindows()
	HideWindowAtOnce(GossipFrame, function() return true end)
	HideWindowAtOnce(QuestFrame, function() return true end)
	HideWindowAtOnce(MerchantFrame, function() return Dialog.db.merchant end)
	HideWindowAtOnce(ClassTrainerFrame, function() return Dialog.db.trainer end)
end

-- The nameplate of the NPC cannot be measured or clamped by an addon (it is a restricted region), but
-- the game keeps plates inside the screen by its own settings: while a bubble is open the upper inset
-- is raised by the height of the bubble, so the plate (and the bubble on it) stays low enough.
local PLATE_CVARS = { "nameplateOtherTopInset", "nameplateLargeTopInset", "clampTargetNameplateToScreen" }
local savedPlateCVars

local function KeepOnScreen(on)
	if on and bubble and not InCombatLockdown() then
		if not savedPlateCVars then
			savedPlateCVars = {}
			for _, name in ipairs(PLATE_CVARS) do
				savedPlateCVars[name] = GetCVar(name)
			end
		end
		local fraction = math.min(0.85, (bubble:GetHeight() + INSET * 2 + 22 + 24) / math.max(UIParent:GetHeight(), 1))
		SetCVar("nameplateOtherTopInset", fraction)
		SetCVar("nameplateLargeTopInset", fraction)
		SetCVar("clampTargetNameplateToScreen", "1")
	elseif not on and savedPlateCVars and not InCombatLockdown() then
		for name, value in pairs(savedPlateCVars) do
			SetCVar(name, value)
		end
		savedPlateCVars = nil
	end
end

local function Hide()
	Trace("Blase weg")
	KeepOnScreen(false)
	RestorePlate()
	if bubble then
		bubble:Hide()
		if reveal.active then
			FinishReveal()
		end
	end
	current = nil
	npcGuid = nil
	wipe(history)
	CollapseAll(false)
	ns.ShowFriendlyPlates(false)
end

-- Blizzard's window shows instead of the bubble (confirmation needed).
local function UseBlizzard()
	Trace("Blizzards Fenster statt Blase")
	KeepOnScreen(false)
	RestorePlate()
	showToken = showToken + 1
	if bubble then
		bubble:Hide()
	end
	current = nil
	npcGuid = nil
	CollapseAll(false)
	ns.ShowFriendlyPlates(false)
end

-- The small grey book at the lower right of the merchant list: dull, brighter under the mouse, a red x over it
-- while unusable and known wares are hidden.
function Dialog.UpdateFilter()
	local filter = bubble and bubble.Filter
	if not filter then
		return
	end
	local on = Dialog.db.merchantHide
	filter.Icon:SetAlpha(filter.hover and 1 or 0.6)
	filter.Cross:SetShown(on and true or false)
end

-- Repair, sell junk and restock symbols beside the book: only those the merchant offers, packed to the left.
function Dialog.UpdateTools(view)
	local frame = bubble
	if not frame then
		return
	end
	-- Worked out once per view (MerchantView), not again here: the bags are not scanned twice.
	local available = view and ((view.kind == "MERCHANT_SHOW" and view.filter) or view.kind == "TRAINER_SHOW") and view.tools or {}
	local x = 2 - 18
	for _, key in ipairs({ "locked", "repair", "sell", "restock" }) do
		local tool = frame.Tools[key]
		local state = available[key]
		tool:SetShown(state ~= nil)
		if state ~= nil then
			tool.enabledLook = state
			tool:ClearAllPoints()
			tool:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, -2)
			tool.Icon:SetAlpha(tool.hover and 1 or (state and 0.6 or 0.3))
			x = x - 18
		end
	end
end

-- Builds the step on show again (the option lit with Tab changes the look of its row).
function Dialog.Rerender()
	if current and bubble and bubble:IsShown() then
		Render(current.view)
	end
end

-- The grey x at the top right: closes the merchant or trainer window and with it the bubble.
function Dialog.CloseCurrent()
	local kind = current and current.view.kind
	if kind == "MERCHANT_SHOW" and CloseMerchant then
		CloseMerchant()
	elseif kind == "TRAINER_SHOW" and CloseTrainer then
		CloseTrainer()
	end
end

-- Lights the option Space takes.
function Dialog.ShowSelection()
	if not bubble then
		return
	end
	Dialog.Rerender()
end

local function Show(view, fromBack)
	if not bubble then
		bubble = CreateBubble()
	end
	-- Lists that refresh themselves (trainer, merchant) keep the arrow where it was.
	local keepCursor = current and current.view.kind == view.kind and (view.kind == "TRAINER_SHOW" or view.kind == "MERCHANT_SHOW")
	if not keepCursor then
		bubble.selectedRow = 1
		bubble.cursorMoved = false
	end
	showToken = showToken + 1
	-- Gossip is over once a merchant or trainer is open: "back" would lead to options that no longer work.
	if view.kind == "MERCHANT_SHOW" or view.kind == "TRAINER_SHOW" then
		wipe(history)
	end
	if not current then
		wipe(history)
	elseif not fromBack and current.view ~= view and (current.view.kind == "GOSSIP_SHOW" or current.view.kind == "QUEST_GREETING") then
		history[#history + 1] = current.view
		if #history > 8 then
			table.remove(history, 1)
		end
	end
	local talkUnit = not current and TalkUnit()
	if talkUnit then
		local guid = UnitGUID(talkUnit)
		npcGuid = guid and not (issecretvalue and issecretvalue(guid)) and guid or nil
	end
	Trace("Schritt %s, Blase sichtbar %s, %s, %s", view.kind or "?", tostring(bubble:IsShown()), WindowState(GossipFrame), WindowState(QuestFrame))
	current = { view = view }
	Render(view)
	KeepOnScreen(Dialog.db.onScreen)
	Place()
	bubble:Show()
	CollapseAll(true)
	-- Blizzard's own scripts may restore size and position after the event.
	C_Timer.After(0, function()
		if current and bubble:IsShown() then
			CollapseAll(true)
		end
	end)
end

---------------------------------------------------------------------------
-- Views for each step of a conversation
---------------------------------------------------------------------------
local function NpcName()
	return Readable(UnitName("npc")) or ""
end

local function CloseConversation()
	if C_GossipInfo and C_GossipInfo.CloseGossip and GossipFrame and GossipFrame:IsShown() then
		C_GossipInfo.CloseGossip()
	elseif CloseQuest then
		CloseQuest()
	end
end

local function GoodbyeButton()
	return { text = GOODBYE or CLOSE, action = CloseConversation }
end

-- The game's own quest symbols in front of the quests of a gossip or greeting step: ! available, ? to hand in,
-- grey ? not finished yet.
local QUEST_ICON = {
	available = [[Interface\GossipFrame\AvailableQuestIcon]],
	turnin = [[Interface\GossipFrame\ActiveQuestIcon]],
	incomplete = [[Interface\GossipFrame\IncompleteQuestIcon]],
}

function Dialog.GossipView()
	local blocks, rows = {}, {}
	local text = Readable(C_GossipInfo.GetText())
	if text and text ~= "" then
		blocks[#blocks + 1] = { text = text }
	end
	for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		rows[#rows + 1] = {
			text = Readable(info.title) or "",
			icon = info.isComplete and QUEST_ICON.turnin or QUEST_ICON.incomplete,
			dim = not info.isComplete,
			action = function()
				C_GossipInfo.SelectActiveQuest(info.questID)
			end,
		}
	end
	for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		rows[#rows + 1] = {
			text = Readable(info.title) or "",
			icon = QUEST_ICON.available,
			dim = info.isTrivial,
			action = function()
				C_GossipInfo.SelectAvailableQuest(info.questID)
			end,
		}
	end
	-- Like Blizzard's window: sorted the same way, chosen by the order index.
	local options = C_GossipInfo.GetOptions() or {}
	if GossipOptionSort then
		pcall(table.sort, options, GossipOptionSort)
	end
	for _, info in ipairs(options) do
		rows[#rows + 1] = {
			text = Readable(info.name) or "",
			icon = info.overrideIconID or info.icon,
			action = function()
				if C_GossipInfo.SelectOptionByIndex and info.orderIndex then
					C_GossipInfo.SelectOptionByIndex(info.orderIndex)
				else
					C_GossipInfo.SelectOption(info.gossipOptionID)
				end
			end,
		}
	end
	if #rows > 0 then
		blocks[#blocks + 1] = { rows = rows }
	end
	return { name = NpcName(), blocks = blocks, buttons = { GoodbyeButton() } }
end

function Dialog.GreetingView()
	local blocks, rows = {}, {}
	local text = Readable(GetGreetingText())
	if text and text ~= "" then
		blocks[#blocks + 1] = { text = text }
	end
	for i = 1, GetNumActiveQuests() do
		local title, isComplete = GetActiveTitle(i)
		rows[#rows + 1] = {
			text = Readable(title) or "",
			icon = isComplete and QUEST_ICON.turnin or QUEST_ICON.incomplete,
			dim = not isComplete,
			action = function()
				SelectActiveQuest(i)
			end,
		}
	end
	for i = 1, GetNumAvailableQuests() do
		local isTrivial = GetAvailableQuestInfo(i)
		rows[#rows + 1] = {
			text = Readable(GetAvailableTitle(i)) or "",
			icon = QUEST_ICON.available,
			dim = isTrivial,
			action = function()
				SelectAvailableQuest(i)
			end,
		}
	end
	if #rows > 0 then
		blocks[#blocks + 1] = { rows = rows }
	end
	return { name = NpcName(), blocks = blocks, buttons = { GoodbyeButton() } }
end

-- Item blocks (rewards, choices, required items) of the open quest dialog.
local function ItemInfos(kind, count, choiceOffset)
	local infos = {}
	for i = 1, count do
		local name, texture, number, quality = GetQuestItemInfo(kind, i)
		infos[#infos + 1] = {
			icon = texture, count = number, quality = quality, choice = choiceOffset and i or nil,
			link = GetQuestItemLink(kind, i),
			tooltip = function(tooltip)
				tooltip:SetQuestItem(kind, i)
			end,
			name = name,
		}
	end
	return infos
end

local function AddRewards(blocks, withChoice)
	local choices = GetNumQuestChoices() or 0
	if choices > 0 then
		blocks[#blocks + 1] = {
			header = choices > 1 and withChoice and (REWARD_CHOOSE or L.DIALOG_CHOOSE) or (REWARD_ITEMS or L.DIALOG_REWARDS),
			items = ItemInfos("choice", choices, true), choose = withChoice and choices > 1,
		}
	end
	local rewards = GetNumQuestRewards() or 0
	if rewards > 0 then
		blocks[#blocks + 1] = { header = choices > 0 and (REWARD_ITEMS or L.DIALOG_REWARDS) or (REWARD_ITEMS_ONLY or L.DIALOG_REWARDS), items = ItemInfos("reward", rewards) }
	end
	local money, xp = GetRewardMoney(), GetRewardXP and GetRewardXP() or 0
	local parts = {}
	if xp and xp > 0 then
		parts[#parts + 1] = L.DIALOG_XP:format(xp)
	end
	if money and money > 0 then
		parts[#parts + 1] = GetMoneyString(money, true)
	end
	if #parts > 0 then
		blocks[#blocks + 1] = { money = table.concat(parts, "   ") }
	end
end

function Dialog.DetailView()
	local blocks = { { title = Readable(GetTitleText()) }, { text = Readable(GetQuestText()) or "" } }
	local objective = Readable(GetObjectiveText())
	if objective and objective ~= "" then
		blocks[#blocks + 1] = { text = objective }
	end
	AddRewards(blocks, false)
	return {
		name = NpcName(), blocks = blocks,
		buttons = {
			{ text = ACCEPT, primary = true, action = function()
				AcceptQuest()
			end },
			{ text = DECLINE, action = function()
				CloseQuest()
			end },
		},
	}
end

function Dialog.ProgressView()
	local blocks = { { title = Readable(GetTitleText()) }, { text = Readable(GetProgressText()) or "" } }
	local required = GetNumQuestItems() or 0
	if required > 0 then
		blocks[#blocks + 1] = { header = L.DIALOG_REQUIRED, items = ItemInfos("required", required) }
	end
	local money = GetQuestMoneyToGet()
	if money and money > 0 then
		blocks[#blocks + 1] = { money = GetMoneyString(money, true) }
	end
	return {
		name = NpcName(), blocks = blocks,
		buttons = {
			{ text = CONTINUE, primary = true, enabled = IsQuestCompletable(), action = function()
				CompleteQuest()
			end },
			{ text = CANCEL, action = function()
				CloseQuest()
			end },
		},
	}
end

function Dialog.RewardView()
	local blocks = { { title = Readable(GetTitleText()) }, { text = Readable(GetRewardText()) or "" } }
	AddRewards(blocks, true)
	local choices = GetNumQuestChoices() or 0
	local view
	view = {
		name = NpcName(), blocks = blocks,
		buttons = {
			{ text = COMPLETE_QUEST, primary = true, action = function()
				local choice = current and current.selected or (choices == 1 and 1) or 0
				if choices > 1 and choice == 0 then
					ns.Print(L.DIALOG_CHOOSE_FIRST)
					return
				end
				GetQuestReward(choice)
			end },
			{ text = CANCEL, action = function()
				CloseQuest()
			end },
		},
	}
	return view
end

---------------------------------------------------------------------------
-- Trainer: the list of what can be learned, as rows; a click selects, the buttons train.
---------------------------------------------------------------------------
local TRAINER_ROWS = 12 -- rows in the bubble; more are scrolled with the mouse wheel
local trainerSelected
local trainerOffset = 0
Dialog.showLocked = false -- what cannot be learned yet is shown only on request

local function TrainerServices()
	local available, locked = {}, {}
	for index = 1, GetNumTrainerServices() or 0 do
		local name, kind, icon, level, subText = GetTrainerServiceInfo(index)
		if name and not (issecretvalue and issecretvalue(name)) then
			local cost = GetTrainerServiceCost(index) or 0
			local entry = { index = index, name = name, icon = icon, level = level, subText = subText, cost = cost }
			if kind == "available" then
				available[#available + 1] = entry
			elseif kind == "unavailable" then
				locked[#locked + 1] = entry
			end
		end
	end
	return available, locked
end

function Dialog.TrainerScroll(delta)
	trainerOffset = math.max(0, trainerOffset - delta * 3)
	Dialog:OnConversation("TRAINER_UPDATE")
end

function Dialog.ToggleTrainerLocked()
	Dialog.showLocked = not Dialog.showLocked
	trainerOffset = 0
	Dialog:OnConversation("TRAINER_UPDATE")
end

function Dialog.TrainerView()
	local available, locked = TrainerServices()
	local money = GetMoney()
	local rows = {}
	local function AddRow(entry, isAvailable)
		local label = entry.name
		if entry.subText and entry.subText ~= "" then
			label = ("%s (%s)"):format(label, entry.subText)
		end
		local parts = { label }
		if entry.cost > 0 then
			parts[#parts + 1] = GetMoneyString(entry.cost, true)
		end
		if not isAvailable and entry.level and entry.level > UnitLevel("player") then
			parts[#parts + 1] = L.DIALOG_TRAIN_LEVEL:format(entry.level)
		end
		local selected = isAvailable and trainerSelected == entry.index
		rows[#rows + 1] = {
			text = table.concat(parts, "   "),
			picked = selected,
			icon = entry.icon,
			dim = not isAvailable,
			action = isAvailable and function()
				trainerSelected = entry.index
				Dialog:OnConversation("TRAINER_UPDATE")
			end or nil,
			tooltip = function(tooltip)
				if tooltip.SetTrainerService then
					tooltip:SetTrainerService(entry.index)
				end
			end,
		}
	end
	-- What can be learned now; what is still too high only while the symbol at the lower right is switched on.
	local entries = {}
	for _, entry in ipairs(available) do
		entries[#entries + 1] = { entry = entry, isAvailable = true }
	end
	if Dialog.showLocked then
		for _, entry in ipairs(locked) do
			entries[#entries + 1] = { entry = entry, isAvailable = false }
		end
	end
	local listed = #entries
	trainerOffset = math.max(0, math.min(trainerOffset, math.max(0, listed - TRAINER_ROWS)))
	for position = trainerOffset + 1, math.min(listed, trainerOffset + TRAINER_ROWS) do
		AddRow(entries[position].entry, entries[position].isAvailable)
	end
	local blocks = {}
	local greeting = Readable(GetTrainerGreetingText and GetTrainerGreetingText())
	if greeting and greeting ~= "" then
		blocks[#blocks + 1] = { text = greeting }
	end
	if #rows == 0 then
		blocks[#blocks + 1] = { text = L.DIALOG_TRAIN_NONE, dim = true }
	else
		blocks[#blocks + 1] = { rows = rows }
	end
	if listed > TRAINER_ROWS then
		blocks[#blocks + 1] = { text = L.DIALOG_MERCHANT_RANGE:format(trainerOffset + 1, math.min(listed, trainerOffset + TRAINER_ROWS), listed), dim = true }
	end
	blocks[#blocks + 1] = { money = L.DIALOG_MONEY:format(GetMoneyString(money, true)) }
	-- Keep a selection only while it can still be trained and paid.
	local selection
	for _, entry in ipairs(available) do
		if entry.index == trainerSelected and entry.cost <= money then
			selection = entry
		end
	end
	local affordable = 0
	for _, entry in ipairs(available) do
		if entry.cost <= money then
			affordable = affordable + 1
		end
	end
	return {
		name = NpcName(), blocks = blocks, revealed = true,
		tools = #locked > 0 and { locked = Dialog.showLocked } or {},
		buttons = {
			{ text = GOODBYE or CLOSE, action = Dialog.CloseCurrent },
			{ text = TRAIN or L.DIALOG_TRAIN, primary = true, spends = true, enabled = selection ~= nil, action = function()
				BuyTrainerService(selection.index)
			end },
			{ text = L.DIALOG_TRAIN_ALL, enabled = affordable > 0, tooltip = function(tooltip)
				-- What "train all" would buy and cost: from the top down, as long as the money lasts.
				local left, total, count = money, 0, 0
				local names = {}
				for _, entry in ipairs(available) do
					if entry.cost <= left then
						left = left - entry.cost
						total, count = total + entry.cost, count + 1
						names[#names + 1] = entry.subText and entry.subText ~= "" and ("%s (%s)"):format(entry.name, entry.subText) or entry.name
					end
				end
				GameTooltip_SetTitle(tooltip, L.DIALOG_TRAIN_ALL)
				if count == 0 then
					GameTooltip_AddNormalLine(tooltip, L.DIALOG_TRAIN_ALL_NONE)
					return
				end
				GameTooltip_AddNormalLine(tooltip, L.DIALOG_TRAIN_ALL_TOTAL:format(count, GetMoneyString(total, true)))
				for index, name in ipairs(names) do
					if index > 12 then
						tooltip:AddLine(L.DIALOG_TRAIN_ALL_MORE:format(count - 12), 0.7, 0.7, 0.7)
						break
					end
					tooltip:AddLine(name, 1, 1, 1)
				end
			end, action = function()
				-- Most expensive last: what was bought first changes what the list shows, so go from the top
				-- and count the money down.
				local left = GetMoney()
				for _, entry in ipairs(available) do
					if entry.cost <= left then
						left = left - entry.cost
						BuyTrainerService(entry.index)
					end
				end
			end },
		},
	}
end

---------------------------------------------------------------------------
-- Merchant: the wares as a list (scrolled with the mouse wheel); a click selects, "Buy" buys one.
-- Hides what cannot be used and what is known already when wanted; buy-back is a list of its own.
---------------------------------------------------------------------------
local MERCHANT_ROWS = 14
local merchantPicked, merchantOffset, merchantMode, merchantSaying = {}, 0, "wares", nil
local repairSeen -- the last repair cost seen at this merchant (Dialog.repairDone: the player repaired since)
local REPAIR_GRACE = 2
local merchantQty = {} -- ware index -> how many "Buy" takes of it (counted with the mouse wheel over the row)
local knownWares = {} -- ware index -> known already (read from the tooltip once per visit)

local function IsKnownWare(index)
	local cached = knownWares[index]
	if cached ~= nil then
		return cached
	end
	local known = false
	local link = GetMerchantItemLink and GetMerchantItemLink(index)
	if link then
		local classID = select(6, C_Item.GetItemInfoInstant(link))
		if classID == Enum.ItemClass.Recipe or classID == Enum.ItemClass.Miscellaneous then
			local data = C_TooltipInfo and C_TooltipInfo.GetMerchantItem and C_TooltipInfo.GetMerchantItem(index)
			for _, line in ipairs(data and data.lines or {}) do
				local text = line.leftText
				if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text == ITEM_SPELL_KNOWN then
					known = true
					break
				end
			end
		end
	end
	knownWares[index] = known
	return known
end

local function WareName(info, link)
	local color = "ffffffff"
	local quality = link and select(3, C_Item.GetItemInfo(link))
	if quality and C_Item.GetItemQualityColor then
		local _, _, _, hex = C_Item.GetItemQualityColor(quality)
		color = hex or color
	end
	if info.isUsable == false then
		color = "ffff4040"
	end
	local text = ("|c%s%s|r"):format(color, info.name or "?")
	if (info.stackCount or 1) > 1 then
		text = text .. " x" .. info.stackCount
	end
	return text
end

local function MerchantRowText(info, index)
	local parts = { WareName(info, GetMerchantItemLink and GetMerchantItemLink(index)) }
	if info.hasExtendedCost then
		-- Special price (honor, currencies, items): the icons and amounts of the game's own cost list.
		local costs = {}
		for item = 1, GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0 do
			local texture, value = GetMerchantItemCostItem(index, item)
			if texture and value and value > 0 then
				costs[#costs + 1] = ("%d |T%s:14:14|t"):format(value, tostring(texture))
			end
		end
		if (info.price or 0) > 0 then
			costs[#costs + 1] = GetMoneyString(info.price, true)
		end
		parts[#parts + 1] = #costs > 0 and table.concat(costs, " ") or L.DIALOG_MERCHANT_SPECIAL
	elseif (info.price or 0) > 0 then
		parts[#parts + 1] = GetMoneyString(info.price, true)
	end
	if (info.numAvailable or -1) >= 0 then
		parts[#parts + 1] = L.DIALOG_MERCHANT_LEFT:format(info.numAvailable)
	end
	return table.concat(parts, "   ")
end

-- What the merchant says: a random saying per visit, shown on the page of the wares or before it.
local function PickSaying()
	return L["DIALOG_MERCHANT_SAY" .. math.random(1, 8)]
end

local function MerchantEntries()
	local entries = {}
	local hide = Dialog.db.merchantHide
	for index = 1, GetMerchantNumItems() or 0 do
		local info = C_MerchantFrame.GetItemInfo(index)
		if info and info.name and not (hide and (info.isUsable == false or IsKnownWare(index))) then
			entries[#entries + 1] = { index = index, info = info }
		end
	end
	return entries
end

local function BuybackEntries()
	local entries = {}
	for index = 1, GetNumBuybackItems and GetNumBuybackItems() or 0 do
		local name, texture, price, quantity, _, isUsable = GetBuybackItemInfo(index)
		if name then
			entries[#entries + 1] = { index = index, info = {
				name = name, texture = texture, price = price, stackCount = quantity, numAvailable = -1, isUsable = isUsable,
				isPurchasable = true,
			} }
		end
	end
	return entries
end

local function RefreshMerchant()
	Dialog:OnConversation("MERCHANT_UPDATE")
end

function Dialog.MerchantScroll(delta)
	if merchantMode ~= "wares" then
		return
	end
	merchantOffset = math.max(0, merchantOffset - delta * 3)
	RefreshMerchant()
end

function Dialog.MerchantView()
	local money = GetMoney()
	local buyback = merchantMode == "buyback"
	local entries = buyback and BuybackEntries() or MerchantEntries()
	local total = #entries
	merchantOffset = math.max(0, math.min(merchantOffset, math.max(0, total - MERCHANT_ROWS)))
	-- Several wares can be chosen: a click on a row picks it or puts it back.
	local byIndex = {}
	for _, entry in ipairs(entries) do
		byIndex[entry.index] = entry.info
	end
	-- A pick belongs to the ware it was made on: when the list shifted (sold out), the pick is dropped.
	for index, mark in pairs(merchantPicked) do
		if not byIndex[index] or (not buyback and type(mark) == "string" and mark ~= GetMerchantItemLink(index)) then
			merchantPicked[index], merchantQty[index] = nil, nil
		end
	end
	local function Mark(index)
		return not buyback and GetMerchantItemLink and GetMerchantItemLink(index) or true
	end
	local function QuantityOf(index)
		return buyback and 1 or math.max(1, merchantQty[index] or 1)
	end
	local picks, cost, payable = {}, 0, true
	for index in pairs(merchantPicked) do
		local info = byIndex[index]
		picks[#picks + 1] = index
		local amount = QuantityOf(index)
		if info.isPurchasable == false or (info.numAvailable or -1) == 0 then
			payable = false
		elseif not info.hasExtendedCost then
			cost = cost + (info.price or 0) * amount
		end
	end
	table.sort(picks)
	local rows = {}
	-- All rows leave room for the arrow when the option for upgrade arrows is on (so the texts stay aligned).
	local arrowSlot = not buyback and ns.IsRewardUpgrade ~= nil and ns:GetModule("Items").db.rewardUpgrade
	for position = merchantOffset + 1, math.min(total, merchantOffset + MERCHANT_ROWS) do
		local entry = entries[position]
		local index, info = entry.index, entry.info
		local isPicked = merchantPicked[index] and true or false
		local limit = (info.numAvailable or -1) >= 0 and info.numAvailable or 999
		rows[#rows + 1] = {
			text = (buyback and (WareName(info) .. "   " .. GetMoneyString(info.price or 0, true)) or MerchantRowText(info, index)),
			icon = info.texture,
			number = position,
			arrowSlot = arrowSlot,
			upgrade = not buyback and info.isUsable ~= false and ns.IsRewardUpgrade
				and ns.IsRewardUpgrade(GetMerchantItemLink(index), RefreshMerchant) or false,
			dim = info.isPurchasable == false,
			picked = isPicked, -- in the basket: a tick, a green tint, a glitter frame and the quantity field
			counter = isPicked and not buyback and QuantityOf(index) or nil,
			reserve = 48,
			-- A click chooses this ware alone; on a chosen ware left clicks count up, right clicks down (the last
			-- one takes it out). Shift + click adds a ware to the choice or takes it out (several wares at once).
			action = function(mouseButton)
				if IsShiftKeyDown() then
					if isPicked then
						merchantPicked[index], merchantQty[index] = nil, nil
					else
						merchantPicked[index], merchantQty[index] = Mark(index), 1
					end
				elseif isPicked and not buyback then
					local quantity = QuantityOf(index) + (mouseButton == "RightButton" and -1 or 1)
					if quantity < 1 then
						merchantPicked[index], merchantQty[index] = nil, nil
					else
						merchantQty[index] = math.min(quantity, limit)
					end
				elseif isPicked then
					merchantPicked[index] = nil
				else
					wipe(merchantPicked)
					wipe(merchantQty)
					merchantPicked[index], merchantQty[index] = Mark(index), 1
				end
				RefreshMerchant()
			end,
			onQuantity = isPicked and not buyback and function(number)
				if number < 1 then
					merchantPicked[index], merchantQty[index] = nil, nil
				else
					merchantQty[index] = math.min(math.floor(number), limit)
				end
				RefreshMerchant()
			end or nil,
			tooltip = function(tooltip)
				if buyback then
					if tooltip.SetBuybackItem then
						tooltip:SetBuybackItem(index)
					end
				elseif tooltip.SetMerchantItem then
					tooltip:SetMerchantItem(index)
					-- The game's hint ("Shift-click to buy another quantity") does not fit here: what a click does now.
					local hint = isPicked and L.DIALOG_CLICK_PICKED or L.DIALOG_CLICK_FREE
					local stackHint = _G.ITEM_VENDOR_STACK_BUY
					for line = 1, tooltip:NumLines() do
						local left = _G[tooltip:GetName() .. "TextLeft" .. line]
						local text = left and left:GetText()
						if type(text) == "string" and not (issecretvalue and issecretvalue(text))
							and ((stackHint and text == stackHint) or text:lower():find("umschalt", 1, true) or text:lower():find("shift", 1, true)) then
							left:SetText(hint)
						end
					end
					tooltip:Show()
				end
			end,
		}
	end
	local blocks = {}
	if merchantSaying and not buyback then
		blocks[#blocks + 1] = { text = merchantSaying, dim = true }
	end
	blocks[#blocks + 1] = #rows == 0 and { text = L.DIALOG_MERCHANT_NONE, dim = true } or { rows = rows }
	if total > MERCHANT_ROWS then
		blocks[#blocks + 1] = { text = L.DIALOG_MERCHANT_RANGE:format(merchantOffset + 1, math.min(total, merchantOffset + MERCHANT_ROWS), total), dim = true }
	end
	local moneyText = L.DIALOG_MONEY:format(GetMoneyString(money, true))
	if #picks > 0 then
		local pieces = 0
		for _, index in ipairs(picks) do
			pieces = pieces + QuantityOf(index)
		end
		moneyText = moneyText .. "   " .. L.DIALOG_MERCHANT_CHOSEN:format(#picks, pieces, GetMoneyString(cost, true))
	end
	blocks[#blocks + 1] = { money = moneyText }
	local canBuy = #picks > 0 and payable and cost <= money
	local available = {} -- the symbols beside the book: repair, sell, restock
	local buttons = {
		{ text = buyback and L.DIALOG_BUYBACK_DO or L.DIALOG_BUY, primary = true, spends = true, enabled = canBuy, action = function()
			if buyback then
				-- Buy-back numbers shift with every purchase: from the back to the front.
				for position = #picks, 1, -1 do
					BuybackItem(picks[position])
				end
			else
				for _, index in ipairs(picks) do
					-- The quantity counts packs as the merchant sells them (a pack of 200 arrows is one), the game's
					-- BuyMerchantItem counts items: packs times the pack size, in portions of whole packs of at most
					-- the maximum the game takes at once.
					local pack = math.max(1, byIndex[index].stackCount or 1)
					local wanted = QuantityOf(index) * pack
					local remaining = wanted
					local chunk = math.max(pack, math.floor(math.max(1, GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or 1) / pack) * pack)
					while remaining > 0 do
						BuyMerchantItem(index, math.min(remaining, chunk))
						remaining = remaining - chunk
					end
					-- Said in the chat so a purchase can be checked against what was meant.
					ns.Print(L.DIALOG_BOUGHT, wanted, byIndex[index].name or "?")
				end
			end
			-- The basket is empty after a purchase: nothing is bought a second time by accident.
			wipe(merchantPicked)
			wipe(merchantQty)
			RefreshMerchant()
		end },
	}
	if buyback then
		buttons[#buttons + 1] = { text = L.DIALOG_WARES, action = function()
			merchantMode, merchantOffset = "wares", 0
			wipe(merchantPicked)
			RefreshMerchant()
		end }
	else
		if GetNumBuybackItems and GetNumBuybackItems() > 0 then
			buttons[#buttons + 1] = { text = L.DIALOG_BUYBACK, action = function()
				merchantMode, merchantOffset = "buyback", 0
				wipe(merchantPicked)
				RefreshMerchant()
			end }
		end
		local tools = ns.MerchantTools
		if tools then
			local junkCount = tools.JunkValue()
			if junkCount > 0 then
				buttons[#buttons + 1] = { text = L.DIALOG_SELL_JUNK:format(junkCount), action = tools.SellJunk }
				available.sell = true
			end
		end
		-- Only the symbol beside the book (no button with text), and only while something is worn. The list is
		-- rebuilt often and the game briefly reports nothing to repair while items move: a symbol seen a moment
		-- ago stays.
		if CanMerchantRepair and CanMerchantRepair() then
			local repairCost, canRepair = GetRepairAllCost()
			if canRepair and repairCost > 0 then
				repairSeen = { time = GetTime(), cost = repairCost }
			elseif repairSeen and GetTime() - repairSeen.time < REPAIR_GRACE and not Dialog.repairDone then
				repairCost, canRepair = repairSeen.cost, true
			end
			if canRepair and repairCost > 0 then
				available.repair = repairCost <= money -- false: shown dim
			end
		end
		local restock = ns:GetModule("Restock")
		if restock and restock.MerchantPlan and #restock.MerchantPlan() > 0 then
			available.restock = true
		end
	end
	-- Lists refresh often: their text does not appear letter by letter (only the first page of the merchant).
	-- "Goodbye" at the lower left (the first button), like at every other step.
	table.insert(buttons, 1, { text = GOODBYE or CLOSE, action = Dialog.CloseCurrent })
	return { name = NpcName(), blocks = blocks, buttons = buttons, revealed = true, filter = not buyback, tools = available }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local VIEWS = {
	GOSSIP_SHOW = "GossipView", QUEST_GREETING = "GreetingView", QUEST_DETAIL = "DetailView",
	QUEST_PROGRESS = "ProgressView", QUEST_COMPLETE = "RewardView",
	TRAINER_SHOW = "TrainerView", TRAINER_UPDATE = "TrainerView",
	MERCHANT_SHOW = "MerchantView", MERCHANT_UPDATE = "MerchantView",
}

-- Steps Blizzard has to confirm itself (the confirmation windows cannot be opened by addon code).
local function NeedsBlizzard(event)
	if event == "QUEST_DETAIL" then
		return QuestFlagsPVP() or QuestGetAutoAccept()
	elseif event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then
		local money = GetQuestMoneyToGet()
		return money and money > 0
	end
	return false
end

-- Back to the step before (gossip and greeting steps are kept); the game's own
-- state is not changed, a choice made there is made again.
function Dialog.GoBack()
	local previous = table.remove(history)
	if previous then
		Show(previous, true)
	end
end

function Dialog.AbandonQuest(questID)
	if not questID or InCombatLockdown() then
		return
	end
	local selected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	pcall(function()
		C_QuestLog.SetSelectedQuest(questID)
		C_QuestLog.SetAbandonQuest()
		C_QuestLog.AbandonQuest()
	end)
	if selected and selected ~= questID then
		C_QuestLog.SetSelectedQuest(selected)
	end
	if CloseQuest then
		CloseQuest()
	end
end

function Dialog:OnConversation(event)
	if not self.db.enabled or InCombatLockdown() then
		return
	end
	Trace("Ereignis %s", event)
	if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		-- Updates (stock, money, bags) only refresh the list that is on show.
		if not self.db.merchant or (event == "MERCHANT_UPDATE" and not (current and current.view.kind == "MERCHANT_SHOW")) then
			return
		end
		if event == "MERCHANT_SHOW" then
			repairSeen, Dialog.repairDone = nil, nil
			wipe(merchantPicked)
			wipe(merchantQty)
			merchantOffset, merchantSaying = 0, PickSaying()
			merchantMode = "wares"
			wipe(knownWares)
		end
		event = "MERCHANT_SHOW"
	end
	if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		-- Only while the trainer is open and its list is the step on show (updates alone do not open it).
		if not self.db.trainer or (event == "TRAINER_UPDATE" and not (current and current.view.kind == "TRAINER_SHOW")) then
			return
		end
		if event == "TRAINER_SHOW" then
			trainerSelected, trainerOffset = nil, 0
		end
		event = "TRAINER_SHOW"
	end
	if NeedsBlizzard(event) then
		UseBlizzard()
		return
	end
	local ok, view = pcall(Dialog[VIEWS[event]])
	if ok and view then
		view.kind = event
		if event == "QUEST_PROGRESS" and GetQuestID then
			local id = GetQuestID()
			view.abandonQuestID = type(id) == "number" and id > 0 and id or nil
		end
		Show(view)
	else
		-- Blizzard's window shows instead; the reason is reported once.
		if not ok and not Dialog.reported then
			Dialog.reported = true
			ns.Print(L.DIALOG_ERROR:format(tostring(view)))
		end
		UseBlizzard()
	end
end

function Dialog:Apply()
	local on = self.db.enabled
	ns.dialogBubbles = on
	for event in pairs(VIEWS) do
		self:ToggleEvent(event, on, self.OnConversation)
	end
	-- The plate of the NPC appears after the start of the talk: the bubble moves onto it.
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", on, function()
		if current and bubble and bubble:IsShown() and NpcNameplate() then
			Place()
		end
	end)
	-- A plate that goes away may be given to another unit: the bubble is placed again (on the plate of the NPC,
	-- else at the top of the screen) instead of staying on a frame that now belongs to someone else.
	self:ToggleEvent("NAME_PLATE_UNIT_REMOVED", on, function()
		if current and bubble and bubble:IsShown() then
			Place()
		end
	end)
	-- Selecting a quest in the gossip closes the gossip and opens the quest: only a
	-- close with no new step right after ends the bubble.
	for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "TRAINER_CLOSED", "MERCHANT_CLOSED" }) do
		self:ToggleEvent(event, on, function()
			local token = showToken
			C_Timer.After(0.15, function()
				if token == showToken then
					Hide()
				end
			end)
		end)
	end
	if not on then
		Hide()
	elseif current and bubble then
		Render(current.view)
	end
end

-- The bubble is meant to be the conversation window: on once, then the player's choice stays.
function Dialog:OnInitialize()
	if self.db.onByDefault == nil then
		self.db.onByDefault = true
		self.db.enabled = true
	end
end

-- /fp blase verlauf: the last steps with their time.
function Dialog.PrintTrace()
	ns.PrintAlways(L.DIALOG_TRACE, #trace)
	for _, line in ipairs(trace) do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
	end
end

-- /fp blase: state of the bubble and of what the conversation offers.
function Dialog.PrintStatus()
	local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
	local available = C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
	local active = C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}
	local point, relativeTo, relativePoint, x, y
	if bubble then
		point, relativeTo, relativePoint, x, y = bubble:GetPoint(1)
	end
	ns.PrintAlways(L.DIALOG_STATUS, Dialog.db.enabled and "ja" or "nein", bubble and "ja" or "nein",
		bubble and bubble:IsShown() and "ja" or "nein", bubble and ns.Number(bubble:GetHeight(), 0) or 0,
		tostring(point), tostring(relativeTo and relativeTo.GetName and relativeTo:GetName() or relativeTo),
		tostring(relativePoint), ns.Number(x, 0), ns.Number(y, 0), #options, #available, #active,
		GossipFrame and GossipFrame:IsShown() and "ja" or "nein", GossipFrame and ns.Number(GossipFrame:GetScale(), 0) or 0)
end

function Dialog:OnLogin()
	for _, window in ipairs({ GossipFrame, QuestFrame }) do
		if window then
			window:HookScript("OnHide", function(shown)
				Collapse(shown, false)
			end)
			window:HookScript("OnShow", function(shown)
				if Dialog.db.enabled and current and bubble and bubble:IsShown() then
					Collapse(shown, true)
				end
			end)
		end
	end
	HookWindows()
	ns.OnAddOnLoaded("Blizzard_TrainerUI", HookWindows)
	self:Apply()
end

function Dialog:OnOptionChanged()
	self:Apply()
end

Dialog.options = {
	{ key = "enabled", type = "toggle", name = L.DIALOG_ENABLE, desc = L.DIALOG_ENABLE_DESC, new = true },
	{ key = "plates", type = "toggle", name = L.DIALOG_PLATES, desc = L.DIALOG_PLATES_DESC, parent = "enabled" },
	{ key = "style", type = "dropdown", name = L.DIALOG_STYLE, desc = L.DIALOG_STYLE_DESC, parent = "enabled", values = {
		{ "PLAYER", L.DIALOG_STYLE_PLAYER }, { "DARK", L.DIALOG_STYLE_DARK },
	} },
	{ key = "hidePlate", type = "toggle", name = L.DIALOG_HIDE_PLATE, desc = L.DIALOG_HIDE_PLATE_DESC, parent = "enabled", new = true },
	{ key = "onScreen", type = "toggle", name = L.DIALOG_ONSCREEN, desc = L.DIALOG_ONSCREEN_DESC, parent = "enabled", new = true },
	{ key = "textSpeed", type = "dropdown", name = L.DIALOG_SPEED, desc = L.DIALOG_SPEED_DESC, parent = "enabled", values = {
		{ "INSTANT", L.DIALOG_SPEED_INSTANT }, { "NORMAL", L.DIALOG_SPEED_NORMAL }, { "SLOW", L.DIALOG_SPEED_SLOW },
	}, new = true },
	{ key = "merchant", type = "toggle", name = L.DIALOG_MERCHANT, desc = L.DIALOG_MERCHANT_DESC, parent = "enabled", new = true },
	{ key = "merchantHide", type = "toggle", name = L.DIALOG_MERCHANT_HIDE, desc = L.DIALOG_MERCHANT_HIDE_DESC, parent = "merchant", new = true },
	{ key = "trainer", type = "toggle", name = L.DIALOG_TRAINER, desc = L.DIALOG_TRAINER_DESC, parent = "enabled", new = true },
}

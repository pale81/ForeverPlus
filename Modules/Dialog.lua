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
-- The bubble
---------------------------------------------------------------------------
local function CreateBubble()
	local frame = CreateFrame("Frame", "ForeverPlusDialogBubble", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetWidth(WIDTH)
	frame:Hide()
	-- Dark variant: one plain pane.
	frame.Dark = frame:CreateTexture(nil, "BACKGROUND")
	frame.Dark:SetPoint("TOPLEFT", -INSET / 2, INSET / 2)
	frame.Dark:SetPoint("BOTTOMRIGHT", INSET / 2, -INSET / 2)
	frame.Dark:SetTexture([[Interface\Tooltips\UI-Tooltip-Background]])
	frame.Dark:SetVertexColor(0.08, 0.08, 0.1, 0.94)
	-- Player variant: the nine-slice art and tail of the chat bubbles.
	frame.Art, frame.Tail = ns.CreateBubbleArt(frame, INSET, -10)
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
		local action
		if key == "SPACE" and current and not InCombatLockdown() then
			for _, info in ipairs(current.view.buttons or {}) do
				if info.primary and info.enabled ~= false then
					action = info.action
				end
			end
		end
		self:SetPropagateKeyboardInput(not action)
		if action then
			action()
		end
	end)
	frame.pools = { text = {}, row = {}, item = {}, button = {} }
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
	row:SetScript("OnClick", function(button)
		if button.action then
			button.action()
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
	item.Upgrade = item:CreateTexture(nil, "OVERLAY", nil, 6)
	item.Upgrade:SetAtlas("bags-greenarrow", true)
	item.Upgrade:SetPoint("TOPRIGHT", 0, 0)
	item.Upgrade:Hide()
	item.Chosen = item:CreateTexture(nil, "OVERLAY", nil, 7)
	item.Chosen:SetPoint("TOPLEFT", -3, 3)
	item.Chosen:SetPoint("BOTTOMRIGHT", 3, -3)
	item.Chosen:SetColorTexture(1, 0.82, 0, 0.35)
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
	if frame.Art then
		frame.Art:SetShown(usePlayer)
	end
	if frame.Tail then
		frame.Tail:SetShown(usePlayer)
	end
	local used = { text = 0, row = 0, item = 0, button = 0 }
	for _, pool in pairs(frame.pools) do
		for _, object in pairs(pool) do
			object:Hide()
		end
	end
	local y = 0
	local function AddText(text, color, font)
		used.text = used.text + 1
		local fs = Pooled(frame, "text", used.text, CreateText)
		fs:SetFontObject(font or TextFont())
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
		fs:SetWidth(WIDTH)
		fs:SetTextColor(unpack(color))
		fs:SetText(text)
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
			AddText(block.text, block.dim and palette.dim or palette.text)
		elseif block.rows then
			for _, info in ipairs(block.rows) do
				used.row = used.row + 1
				local row = Pooled(frame, "row", used.row, CreateRow)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
				row:SetWidth(WIDTH)
				local iconWidth = info.icon and 20 or 0
				row.Icon:SetShown(info.icon ~= nil)
				if info.icon then
					row.Icon:SetTexture(info.icon)
				end
				row.Text:ClearAllPoints()
				row.Text:SetPoint("TOPLEFT", iconWidth, 0)
				row.Text:SetWidth(WIDTH - iconWidth)
				row.Text:SetTextColor(unpack(info.dim and palette.dim or palette.row))
				row.Text:SetText(info.text)
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
				item.Upgrade:SetShown(ns.IsRewardUpgrade and ns.IsRewardUpgrade(info.link, function()
					if bubble:IsShown() and current then
						Render(current.view)
					end
				end) and true or false)
				item.tooltip = info.tooltip
				item.Chosen:SetShown(block.choose and current and current.selected == info.choice or false)
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
	-- Buttons side by side at the bottom: main step, "back" (when there is a step before), close.
	local buttons = {}
	for _, info in ipairs(view.buttons or {}) do
		buttons[#buttons + 1] = info
	end
	if #history > 0 then
		table.insert(buttons, math.max(#buttons, 1), { text = L.DIALOG_BACK, action = Dialog.GoBack })
	end
	-- Abandon the quest of this step (progress): a small cross at the top right, two clicks.
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
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
			button:SetEnabled(info.enabled ~= false)
			button.action = info.action
			button:Show()
			x = x + button:GetWidth() + 6
		end
		y = y + 22 + 2
	else
		y = y - BLOCK_GAP
	end
	frame:SetHeight(math.max(y, 20))
end

---------------------------------------------------------------------------
-- Placement and Blizzard's windows
---------------------------------------------------------------------------
local function NpcNameplate()
	if UnitExists("npc") then
		local nameplate = C_NamePlate.GetNamePlateForUnit("npc")
		if nameplate and not nameplate:IsForbidden() then
			return nameplate
		end
	end
end

local function Place()
	bubble:ClearAllPoints()
	local nameplate = NpcNameplate()
	if nameplate then
		bubble:SetPoint("BOTTOM", nameplate, "TOP", 0, INSET + 22)
	else
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
		window:SetScale(collapsed[window])
		window:SetAlpha(1)
		collapsed[window] = nil
	end
end

local function CollapseAll(on)
	Collapse(GossipFrame, on)
	Collapse(QuestFrame, on)
end

local function Hide()
	if bubble then
		bubble:Hide()
	end
	current = nil
	wipe(history)
	CollapseAll(false)
	ns.ShowFriendlyPlates(false)
end

-- Blizzard's window shows instead of the bubble (confirmation needed).
local function UseBlizzard()
	showToken = showToken + 1
	if bubble then
		bubble:Hide()
	end
	current = nil
	CollapseAll(false)
	ns.ShowFriendlyPlates(false)
end

local function Show(view, fromBack)
	if not bubble then
		bubble = CreateBubble()
	end
	showToken = showToken + 1
	if not current then
		wipe(history)
	elseif not fromBack and current.view ~= view and (current.view.kind == "GOSSIP_SHOW" or current.view.kind == "QUEST_GREETING") then
		history[#history + 1] = current.view
		if #history > 8 then
			table.remove(history, 1)
		end
	end
	current = { view = view }
	Render(view)
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

local function Marker(symbol)
	return ("|c%s%s|r "):format(Palette().marker, symbol)
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

function Dialog.GossipView()
	local blocks, rows = {}, {}
	local text = Readable(C_GossipInfo.GetText())
	if text and text ~= "" then
		blocks[#blocks + 1] = { text = text }
	end
	for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		rows[#rows + 1] = {
			text = Marker(info.isComplete and "?" or "…") .. (Readable(info.title) or ""),
			dim = not info.isComplete,
			action = function()
				C_GossipInfo.SelectActiveQuest(info.questID)
			end,
		}
	end
	for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		rows[#rows + 1] = {
			text = Marker("!") .. (Readable(info.title) or ""),
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
			text = Marker(isComplete and "?" or "…") .. (Readable(title) or ""),
			dim = not isComplete,
			action = function()
				SelectActiveQuest(i)
			end,
		}
	end
	for i = 1, GetNumAvailableQuests() do
		local isTrivial = GetAvailableQuestInfo(i)
		rows[#rows + 1] = {
			text = Marker("!") .. (Readable(GetAvailableTitle(i)) or ""),
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
-- Events
---------------------------------------------------------------------------
local VIEWS = {
	GOSSIP_SHOW = "GossipView", QUEST_GREETING = "GreetingView", QUEST_DETAIL = "DetailView",
	QUEST_PROGRESS = "ProgressView", QUEST_COMPLETE = "RewardView",
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
	-- Selecting a quest in the gossip closes the gossip and opens the quest: only a
	-- close with no new step right after ends the bubble.
	for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
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
}

-- Loot summary: the own loot and money lines are collected and shown as one
-- clickable line each after a quiet moment. A click opens the list with the
-- origin of every item and every amount of money.
local _, ns = ...
local L = ns.L

local Loot = ns:NewModule("Loot", {
	title = L.LOOT_TITLE,
	order = 1.1,
	defaults = {
		summary = false,
		delay = 20,
		inlineQuality = "UNCOMMON",
	},
})

local MAX_SUMMARIES = 20
local SOURCE_GRACE = 3 -- seconds after the loot window closed
local CAST_WINDOW = 6 -- gathering, skinning, fishing: cast sent before the loot
local CONTAINER_WINDOW = 2
local INLINE_QUALITY = { NONE = false, UNCOMMON = 2, RARE = 3, EPIC = 4 }
local LINK_PREFIX = "addon:ForeverPlus:loot:"

local function Accessible(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then
		return nil
	end
	return value
end

---------------------------------------------------------------------------
-- Message patterns built from Blizzard's own format strings
---------------------------------------------------------------------------
-- "%s", "%d" and positional "%1$s" become captures; order[i] is the format
-- argument of capture i.
local function FormatToPattern(format, anchored)
	local order, count = {}, 0
	local marked = format:gsub("%%(%d*)%$?([sd])", function(index, kind)
		count = count + 1
		order[count] = tonumber(index) or count
		return kind == "d" and "\001" or "\002"
	end)
	marked = marked:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	marked = marked:gsub("\001", "(%%d+)"):gsub("\002", "(.-)")
	if anchored then
		marked = "^" .. marked .. "$"
	end
	return { pattern = marked, order = order }
end

local function Patterns(...)
	local list = {}
	for i = 1, select("#", ...) do
		local format = select(i, ...)
		if type(format) == "string" and format ~= "" then
			list[#list + 1] = FormatToPattern(format, true)
		end
	end
	return list
end

-- Returns the format arguments of the first matching pattern.
local function MatchAny(list, text)
	for _, entry in ipairs(list) do
		local captures = { text:match(entry.pattern) }
		if captures[1] then
			local args = {}
			for i, value in ipairs(captures) do
				args[entry.order[i]] = value
			end
			return args
		end
	end
end

-- Multiple first: "%s." would also match "[Item]x3.".
local itemPatterns = Patterns(LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF)
local createdPatterns = Patterns(LOOT_ITEM_CREATED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF)
local moneyPatterns = Patterns(YOU_LOOT_MONEY_GUILD, LOOT_MONEY_SPLIT_GUILD, YOU_LOOT_MONEY, LOOT_MONEY_SPLIT)
local splitPatterns = Patterns(LOOT_MONEY_SPLIT_GUILD, LOOT_MONEY_SPLIT)

local MONEY_UNITS = {}
for _, unit in ipairs({ { GOLD_AMOUNT, "Gold", 10000 }, { SILVER_AMOUNT, "Silver", 100 }, { COPPER_AMOUNT, "Copper", 1 } }) do
	MONEY_UNITS[#MONEY_UNITS + 1] = {
		text = type(unit[1]) == "string" and FormatToPattern(unit[1]).pattern,
		icon = "(%d+)%s*|T[^|]-" .. unit[2] .. "Icon",
		factor = unit[3],
	}
end

-- Link, count and whether the item was crafted ("You create: ...").
local function ParseItem(text)
	local created = false
	local args = MatchAny(itemPatterns, text)
	if not args then
		args, created = MatchAny(createdPatterns, text), true
	end
	if args and args[1] and args[1]:find("|Hitem:", 1, true) then
		return args[1], tonumber(args[2]) or 1, created
	end
end

local function MoneyValue(text)
	local total = 0
	for _, unit in ipairs(MONEY_UNITS) do
		local amount = (unit.text and text:match(unit.text)) or text:match(unit.icon)
		if amount then
			total = total + tonumber(amount) * unit.factor
		end
	end
	return total
end

local function ParseMoney(text)
	local args = MatchAny(moneyPatterns, text)
	local amount = args and args[1] and MoneyValue(args[1])
	if amount and amount > 0 then
		return amount
	end
end

---------------------------------------------------------------------------
-- Origin of the loot: the unit clicked or targeted, the node or fish a cast
-- went to, or the bag item that was opened.
---------------------------------------------------------------------------
local lastCast, lastContainer
local currentSource, lootOpen, closedAt

local function DeadUnitName(unit)
	if not Accessible(UnitExists(unit)) or not Accessible(UnitIsDead(unit)) then
		return nil
	end
	return Accessible(UnitName(unit))
end

local function DetermineSource()
	local now = GetTime()
	if lastContainer and now - lastContainer.time <= CONTAINER_WINDOW then
		return lastContainer.name
	end
	local name = DeadUnitName("mouseover")
	if name then
		return name
	end
	if lastCast and now - lastCast.time <= CAST_WINDOW then
		return lastCast.name
	end
	return DeadUnitName("target")
end

local function CurrentSource()
	if lootOpen or (closedAt and GetTime() - closedAt <= SOURCE_GRACE) then
		return currentSource
	end
end

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------
local summaries, nextID = {}, 1
local batch, flushTimer
local frames = { LOOT = {}, MONEY = {} }

local function NewBatch()
	return { items = {}, order = {}, count = 0, money = 0, moneySources = {}, moneyOrder = {}, started = time() }
end

local function AddSource(sources, order, name, amount)
	if not sources[name] then
		sources[name] = 0
		order[#order + 1] = name
	end
	sources[name] = sources[name] + amount
end

local function ItemQuality(link)
	local itemID = tonumber(link:match("item:(%d+)"))
	return itemID and C_Item.GetItemQualityByID(itemID) or 0
end

local function SummaryLink(id, text)
	return ("|H%s%d|h[%s]|h"):format(LINK_PREFIX, id, text)
end

local function Print(group, text)
	local info = ChatTypeInfo[group]
	for chatFrame in pairs(frames[group]) do
		chatFrame:AddMessage(text, info.r, info.g, info.b, info.id)
	end
	wipe(frames[group])
end

local function Flush()
	if flushTimer then
		flushTimer:Cancel()
		flushTimer = nil
	end
	local record = batch
	batch = nil
	if not record then
		return
	end
	record.ended = time()
	local id = nextID
	nextID = nextID + 1
	summaries[id] = record
	summaries[id - MAX_SUMMARIES] = nil

	if record.count > 0 then
		local text = SummaryLink(id, record.count == 1 and L.LOOT_ITEM_ONE or L.LOOT_ITEMS:format(record.count))
		local minQuality = INLINE_QUALITY[Loot.db.inlineQuality]
		if minQuality then
			local notable = {}
			for _, link in ipairs(record.order) do
				if ItemQuality(link) >= minQuality then
					local count = record.items[link].count
					notable[#notable + 1] = count > 1 and (link .. "x" .. count) or link
				end
			end
			if #notable > 0 then
				text = text .. " " .. table.concat(notable, ", ")
			end
		end
		Print("LOOT", text)
	end
	if record.money > 0 then
		Print("MONEY", SummaryLink(id, L.LOOT_MONEY:format(GetMoneyString(record.money, true))))
	end
end

local function Touch()
	if not batch then
		batch = NewBatch()
	end
	if flushTimer then
		flushTimer:Cancel()
	end
	flushTimer = C_Timer.NewTimer(Loot.db.delay, Flush)
end

function Loot:CHAT_MSG_LOOT(_, text)
	if not Accessible(text) then
		return
	end
	local link, count, created = ParseItem(text)
	if not link then
		return
	end
	Touch()
	local entry = batch.items[link]
	if not entry then
		entry = { count = 0, sources = {}, order = {} }
		batch.items[link] = entry
		batch.order[#batch.order + 1] = link
	end
	entry.count = entry.count + count
	batch.count = batch.count + count
	local source = created and L.LOOT_CRAFTED or CurrentSource() or L.LOOT_UNKNOWN
	AddSource(entry.sources, entry.order, source, count)
end

function Loot:CHAT_MSG_MONEY(_, text)
	if not Accessible(text) then
		return
	end
	local amount = ParseMoney(text)
	if not amount then
		return
	end
	Touch()
	batch.money = batch.money + amount
	local source = CurrentSource() or (MatchAny(splitPatterns, text) and L.LOOT_SHARE) or L.LOOT_UNKNOWN
	AddSource(batch.moneySources, batch.moneyOrder, source, amount)
end

function Loot:LOOT_READY()
	currentSource = DetermineSource()
	lootOpen = true
end

function Loot:LOOT_CLOSED()
	lootOpen = false
	closedAt = GetTime()
end

function Loot:UNIT_SPELLCAST_SENT(_, unit, target, _, spellID)
	if unit ~= "player" then
		return
	end
	local name = Accessible(target)
	if not name or name == "" then
		name = Accessible(C_Spell.GetSpellName(spellID))
	end
	if name then
		lastCast = { name = name, time = GetTime() }
	end
end

---------------------------------------------------------------------------
-- Chat filters: hide the single lines and remember which chat windows
-- would have shown them.
---------------------------------------------------------------------------
local function LootFilter(chatFrame, _, text)
	if type(text) == "string" and ParseItem(text) then
		frames.LOOT[chatFrame] = true
		return true
	end
	return false
end

local function MoneyFilter(chatFrame, _, text)
	if type(text) == "string" and ParseMoney(text) then
		frames.MONEY[chatFrame] = true
		return true
	end
	return false
end

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

---------------------------------------------------------------------------
-- Details window
---------------------------------------------------------------------------
local GREY = "|cff9d9d9d%s|r"

local function SourceText(sources, order, format)
	local parts = {}
	for _, name in ipairs(order) do
		parts[#parts + 1] = format(name, sources[name])
	end
	return table.concat(parts, ", ")
end

local function ItemSource(name, count)
	return count > 1 and ("%s (%d)"):format(name, count) or name
end

local function MoneySource(name, amount)
	return ("%s: %s"):format(name, GetMoneyString(amount, true))
end

local POPUP_WIDTH = 380

local function ItemIcon(link)
	local itemID = tonumber(link:match("item:(%d+)"))
	return itemID and C_Item.GetItemIconByID(itemID)
end

-- Soft popup at the cursor: items with icon, count and origin, then money.
-- Shift-click on an item puts its link into the chat.
local function ShowSummary(id)
	local record = summaries[id]
	if not record then
		ns.Print(L.LOOT_EXPIRED)
		return
	end
	ns.ShowPopupList(nil, function()
		local items = {}
		if record.count > 0 then
			items[#items + 1] = { text = L.LOOT_ITEMS_HEADER }
			for _, link in ipairs(record.order) do
				local entry = record.items[link]
				items[#items + 1] = {
					icon = ItemIcon(link),
					text = ("%s x%d  " .. GREY):format(link:gsub("|H.-|h(.-)|h", "%1"), entry.count, SourceText(entry.sources, entry.order, ItemSource)),
					tooltip = function(tooltip)
						tooltip:SetHyperlink(link)
						GameTooltip_AddInstructionLine(tooltip, L.LOOT_LINK_HINT)
					end,
					onClick = function()
						if IsModifiedClick("CHATLINK") then
							ChatFrameUtil.TryInsertChatLink(link)
						end
					end,
				}
			end
		end
		if record.money > 0 then
			items[#items + 1] = { text = L.LOOT_MONEY_HEADER .. " " .. GetMoneyString(record.money, true) }
			for _, name in ipairs(record.moneyOrder) do
				items[#items + 1] = { text = MoneySource(name, record.moneySources[name]), onClick = function() end }
			end
		end
		local title = ("%s  " .. GREY):format(L.LOOT_TITLE, ("%s - %s"):format(date("%H:%M", record.started), date("%H:%M", record.ended)))
		return { title = title, items = items, width = POPUP_WIDTH }
	end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Loot:Update()
	local enabled = self.db.summary
	for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "LOOT_READY", "LOOT_CLOSED", "UNIT_SPELLCAST_SENT" }) do
		self:ToggleEvent(event, enabled)
	end
	RemoveFilter("CHAT_MSG_LOOT", LootFilter)
	RemoveFilter("CHAT_MSG_MONEY", MoneyFilter)
	if enabled then
		AddFilter("CHAT_MSG_LOOT", LootFilter)
		AddFilter("CHAT_MSG_MONEY", MoneyFilter)
	else
		Flush()
	end
end

function Loot:OnLogin()
	hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
		if self.db.summary then
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link then
				lastContainer = { name = link, time = GetTime() }
			end
		end
	end)
	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		local id = type(link) == "string" and link:sub(1, #LINK_PREFIX) == LINK_PREFIX and tonumber(link:sub(#LINK_PREFIX + 1))
		if id then
			ShowSummary(id)
		end
	end, self)
	self:Update()
end

function Loot:OnOptionChanged(key)
	if key == "summary" then
		self:Update()
	end
end

Loot.options = {
	{ key = "summary", type = "toggle", name = L.LOOT_SUMMARY, desc = L.LOOT_SUMMARY_DESC },
	{ key = "delay", type = "slider", name = L.LOOT_DELAY, desc = L.LOOT_DELAY_DESC, parent = "summary", min = 5, max = 120, step = 5,
		format = function(value)
			return ("%d s"):format(value)
		end },
	{ key = "inlineQuality", type = "dropdown", name = L.LOOT_INLINE, desc = L.LOOT_INLINE_DESC, parent = "summary", values = function()
		local values = { { "NONE", NONE } }
		for _, key in ipairs({ "UNCOMMON", "RARE", "EPIC" }) do
			local quality = INLINE_QUALITY[key]
			values[#values + 1] = { key, ITEM_QUALITY_COLORS[quality].hex .. _G["ITEM_QUALITY" .. quality .. "_DESC"] .. "|r" }
		end
		return values
	end },
}

-- Items: sorting the bags when they open.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate

---------------------------------------------------------------------------
-- Bags: sorted by the game's own cleanup when they open
---------------------------------------------------------------------------
-- The last steps of sorting with their time (/fp taschen verlauf): who sorted, when the layout counted as settled. For seeing in what order things happen when the bags look odd.
Items.trace = {}
function Items.Trace(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	if #Items.trace >= 80 then
		table.remove(Items.trace, 1)
	end
	Items.trace[#Items.trace + 1] = ("%.2f %s"):format(ns.Number(GetTime(), 0) % 1000, text)
end

function Items.PrintTrace()
	ns.ShowTrace(L.ITEMS_TRACE:format(#Items.trace), Items.trace)
end

local SORT_PAUSE = 3 -- seconds between automatic sorts
local SORT_CHECK = 0.4 -- seconds between looks at the bags while a sort runs
local SETTLE = 1.5 -- seconds the layout of the bags must stay the same (and unlocked) for a sort to count as over
local SORT_MAX = 15 -- seconds after which a sort counts as over whatever the bags show
local lastSort, sortQueued, sorting = 0, false, false
-- Layout of the bags after the last finished sort (items and counts). While it is unchanged, opening the bags sorts
-- nothing.
local sortedLayout, sortedRevision
local bagRevision = 0
local RecordLayout -- below

local function OnBagLayoutChanged(_, _, bag)
	if type(bag) == "number" and bag >= BACKPACK_CONTAINER and bag <= NUM_TOTAL_EQUIPPED_BAG_SLOTS then
		bagRevision = bagRevision + 1
	end
end

local function InvalidateBagLayout()
	bagRevision = bagRevision + 1
end

-- Windows in which items are moved by other things: no sorting in them.
local TRADE_WINDOWS = { "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame",
	"ScrappingMachineFrame", "ItemSocketingFrame" }

local function OtherWindowOpen()
	for _, name in ipairs(TRADE_WINDOWS) do
		local frame = _G[name]
		if frame and frame.IsShown and frame:IsShown() then
			return true
		end
	end
	return false
end

-- Read locks and, when needed, the layout in a single pass over the bags.
local function ReadBagLayout(withSignature, stopWhenLocked)
	local parts = withSignature and {} or nil
	local locked = false
	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then
				if stopWhenLocked then
					return nil, true
				end
				locked = true
			end
			if parts then
				parts[#parts + 1] = info and (tostring(info.itemID) .. "x" .. tostring(info.stackCount)) or "-"
			end
		end
	end
	return parts and table.concat(parts, ","), locked
end

-- The game's cleanup works in bursts with pauses (the server moves the items); "no bag update for a moment" took
-- such a pause for the end and the marked items were placed in a half-finished layout, which the rest of the cleanup
-- then undid a few seconds later. A layout counts as settled when it has not changed for SETTLE seconds and no
-- item is locked.
local settle = {}

local function ResetSettle()
	settle.signature, settle.since, settle.revision = nil, GetTime(), nil
end

local function LayoutSettled()
	local now = GetTime()
	-- Bag and lock events invalidate the observation. Recheck once more before accepting a quiet layout.
	if settle.revision == bagRevision and now - (settle.locked and settle.checked or settle.since) < SETTLE then
		return false
	end
	local signature, locked = ReadBagLayout(true)
	settle.revision, settle.locked, settle.checked = bagRevision, locked, now
	if signature ~= settle.signature then
		settle.signature, settle.since = signature, now
	end
	return now - settle.since >= SETTLE and not locked
end

-- The game sorts in steps over a while. A new sort before it is over (or
-- while items are still locked) would work against the first and leave
-- the items locked, so a sort counts as running until the bags have been
-- quiet for a moment.
local function WatchSort()
	sorting = true
	local waited = 0
	ResetSettle()
	ns.NewTicker("Items: WatchSort (timer)", SORT_CHECK, function(ticker)
		waited = waited + SORT_CHECK
		local settled = LayoutSettled()
		if settled or waited >= SORT_MAX then
			Items.Trace(L.ITEMS_TRACE_SORT_END, waited, waited >= SORT_MAX and L.ITEMS_TRACE_SORT_TIMEOUT or L.ITEMS_TRACE_SORT_SETTLED)
			sorting = false
			lastSort = GetTime()
			ticker:Cancel()
			RecordLayout(settle.signature)
		end
	end)
end

local function CanSortOnOpen()
	return Items.db.autoSort and not InCombatLockdown() and not P.sellTicker and not GetCursorInfo() and not sorting and not OtherWindowOpen()
end

local function StartAutomaticSort(revision)
	if revision ~= bagRevision or not CanSortOnOpen() then
		return
	end
	lastSort = GetTime()
	Items.sortSource = L.ITEMS_TRACE_SORT_AUTO
	C_Container.SortBags()
	Items.sortSource = nil
	WatchSort()
end

local function SortOnOpen()
	sortQueued = false
	-- Not while selling, in combat, with an item on the cursor, in a window that moves items or during a sort.
	if not CanSortOnOpen() then
		return
	end
	local now = GetTime()
	if now - lastSort < SORT_PAUSE then
		Items.Trace(L.ITEMS_TRACE_SORT_PAUSE)
		return
	end
	local compare = Items.db.sortSkip and sortedLayout
	if compare and sortedRevision == bagRevision then
		Items.Trace(L.ITEMS_TRACE_SORT_UNCHANGED)
		return
	end
	local signature, locked = ReadBagLayout(compare, true)
	if locked then
		Items.Trace(L.ITEMS_TRACE_SORT_LOCKED)
		return
	end
	if signature and sortedLayout == signature then
		sortedRevision = bagRevision
		Items.Trace(L.ITEMS_TRACE_SORT_UNCHANGED)
		return
	end
	local revision = bagRevision
	sortQueued = true
	ns.After("Items: start game bag sort", 0, function()
		sortQueued = false
		StartAutomaticSort(revision)
	end)
end

function Items.LayoutSignature()
	return (ReadBagLayout(true))
end

-- Called when a sort is over.
function RecordLayout(signature)
	if not sorting and not InCombatLockdown() then
		Items.Trace(L.ITEMS_TRACE_SORT_SAVED)
		sortedLayout = signature or Items.LayoutSignature()
		sortedRevision = bagRevision
	end
end

-- Marked junk is not moved after a sort any more: the game's cleanup puts each item back in its place, so the marked
-- items jumped to and fro on every sort. They keep their coin and are sold with the greys.
local function OnSortStarted()
	Items.Trace(L.ITEMS_TRACE_SORT_START, Items.sortSource or L.ITEMS_TRACE_SORT_EXTERNAL)
end

-- The game's cleanup button: while nothing changed since the last finished sort it does nothing.
local sortOverlay

local function BagsUnchanged()
	if not (Items.db.sortSkip and sortedLayout and not sorting and not InCombatLockdown()) then
		return false
	end
	if sortedRevision == bagRevision then
		return true
	end
	if sortedLayout == Items.LayoutSignature() then
		sortedRevision = bagRevision
		return true
	end
	return false
end

local function UpdateSortOverlay()
	local parent = _G.BagItemAutoSortButton
	if not parent then
		return
	end
	if not sortOverlay then
		sortOverlay = CreateFrame("Button", nil, parent)
		sortOverlay:SetAllPoints()
		sortOverlay:SetFrameLevel(ns.Number(parent:GetFrameLevel(), 1) + 2)
		sortOverlay:RegisterForClicks("LeftButtonUp")
		sortOverlay:SetScript("OnClick", function()
			if BagsUnchanged() then
				return
			end
			PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			Items.sortSource = L.ITEMS_TRACE_SORT_BUTTON
			C_Container.SortBags()
			Items.sortSource = nil
		end)
		sortOverlay:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self)
			GameTooltip_SetTitle(GameTooltip, BAG_CLEANUP_BAGS, HIGHLIGHT_FONT_COLOR)
			GameTooltip_AddNormalLine(GameTooltip, BAG_CLEANUP_BAGS_DESCRIPTION)
			if BagsUnchanged() then
				GameTooltip_AddInstructionLine(GameTooltip, L.ITEMS_SORT_DONE)
			end
			GameTooltip:Show()
		end)
		sortOverlay:SetScript("OnLeave", GameTooltip_Hide)
	end
	sortOverlay:SetShown(Items.db.sortSkip and true or false)
end

-- Opening all bags opens each frame; one sort after the last of them.
local function QueueSort()
	if Items.db.autoSort and not sortQueued then
		sortQueued = true
		ns.After("Items: SortOnOpen", 0, SortOnOpen)
	end
end

-- For the Items*.lua files loaded after this one.
P.InvalidateBagLayout = InvalidateBagLayout
P.OnBagLayoutChanged = OnBagLayoutChanged
P.OnSortStarted = OnSortStarted
P.QueueSort = QueueSort
P.UpdateSortOverlay = UpdateSortOverlay

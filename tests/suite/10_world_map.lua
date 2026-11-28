(function()
	-- Talent links of the calculators on the web: read by place, put onto the talents of the game
	local talents = ns:GetModule("Talents")
	assert(talents.IsLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/0ab1a2b0aaaac")
		and talents.IsLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-33Oy1~70888-0650090c")
		and not talents.IsLink("CYGAAAAAAAAAAAAAAAAAAAAAAA"), "what is a link")
	-- the two links made on the sites with the same clicks: Holy 5/1/1, Protection 1, Retribution second talent 1
	local trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/0ab1a2b0aaaac", "PALADIN")
	assert(trees[1][1] == 5 and trees[1][2] == 1 and trees[1][3] == 1 and trees[2][1] == 1 and trees[3][1] == 0 and trees[3][2] == 1, "Wowhead: digits by place")
	trees = talents.ParseLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-33Oy1~70888-0650090c", "PALADIN")
	assert(trees[1][1] == 2 and trees[1][2] == 1 and trees[2][1] == 1 and trees[3][2] == 1 and trees[3][1] == nil, "Icy Veins: one character per point")
	local _, reason = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/mage/vkndmh2_t0/0A", "PALADIN")
	assert(reason == "class", "another class")
	_, reason = talents.ParseLink("https://www.icy-veins.com/wow-forever/mage-talent-calculator#tc-33~70888-0650090c", "PALADIN")
	assert(reason == "class", "another class (Icy Veins)")
	_, reason = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkn_dmh", "PALADIN")
	assert(reason == "format", "no ranks in it")
	_, reason = talents.ParseLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-3Z", "PALADIN")
	assert(reason == "format", "a character that stands for no talent of the class")
	trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/mage/vkndmh2-05-003_t0/0A", "MAGE")
	assert(trees[1][1] == 2 and trees[2][2] == 5 and trees[3][3] == 3, "three trees")
	local ordered = { { { 11, 5 }, { 12, 5 }, { 13, 3 } }, { { 21, 5 } }, { { 31, 5 }, { 32, 5 } } }
	trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/x", "PALADIN")
	assert(talents.LinkRanks(trees, ordered) == "11:5,12:1,13:1,21:1,32:1", "ranks on the talents of the game: " .. tostring(talents.LinkRanks(trees, ordered)))
	assert(talents.LinkRanks({ { 5, 5, 5 }, {}, {} }, ordered) == nil, "more ranks than the talent has: does not fit")
	assert(talents.LinkRanks({ {}, { 0, 1 }, {} }, ordered) == nil, "a place the tree does not have: does not fit")
	print("talent links OK")
end)()
;(function()
	-- Import the published Shaman path with the first three rows of the applicable client trees.
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local import = uv(menu, "ImportPlan")
	local importLink = uv(import, "ImportLink")
	local playerClass, playerClassName = uv(importLink, "playerClass"), uv(importLink, "playerClassName")
	local active = uv(menu, "ActiveBuild")
	local key = uv(uv(menu, "BuildList"), "PlanKey")
	local savedFrame, savedTraits, savedClassTalents, savedSpec = PlayerSpellsFrame, C_Traits, C_ClassTalents, C_SpecializationInfo
	local savedGroups, savedEdit, savedPrint = ns.TalentGroups, ns.ShowEditWindow, ns.Print
	local queue = uv(talents.QueuePlanUpdate, "QueuePlanUpdate")
	local savedAfter, savedPending = ns.After, uv(queue, "updatePending")
	setuv(queue, "updatePending", false)
	ns.After = function(_, _, fn) fn() end
	local savedSeq = talents.db.buildSeq
	local className = GetLocale() == "deDE" and "Schamane" or "Shaman"
	setuv(importLink, "playerClass", "SHAMAN")
	setuv(importLink, "playerClassName", className)
	local planKey = key()
	local savedPlans, savedActive = talents.db.builds[planKey], talents.cdb.activeBuild[planKey]
	talents.db.builds[planKey], talents.cdb.activeBuild[planKey] = nil, nil
	local buttons, nodes, groups = {}, {}, { { groupID = 1 }, { groupID = 2 }, { groupID = 3 } }
	for tree, layout in pairs({
		[2] = { { 104757, 0, 0, 2 }, { 104753, 0, 1, 5 }, { 104756, 0, 2, 5 }, { 104754, 1, 0, 2 },
			{ 104755, 1, 1, 3 }, { 104751, 1, 2, 3 }, { 104750, 2, 0, 3 }, { 104749, 2, 2, 1 } },
		[3] = { { 104739, 0, 1, 5 }, { 104729, 0, 2, 5 }, { 104734, 1, 0, 3 }, { 104736, 1, 1, 3 },
			{ 104735, 1, 2, 5 }, { 104737, 1, 3, 2 }, { 104731, 2, 0, 3 }, { 104733, 2, 1, 3 }, { 104732, 2, 2, 1 } },
	}) do
		for _, slot in ipairs(layout) do
			local id, row, col, maxRanks = unpack(slot)
			nodes[id] = { ID = id, posY = row * 600, posX = col * 600 + tree * 4000, maxRanks = maxRanks,
				ranksPurchased = 0, groupIDs = { tree } }
			local button = CreateFrame("Button")
			button.GetNodeID = function() return id end
			buttons[button] = true
		end
	end
	local bought, message = {}
	C_Traits = {
		GetNodeInfo = function(_, id) return nodes[id] end,
		GetConfigInfo = function() return nil end,
		PurchaseRank = function(_, id) bought[#bought + 1] = id; return true end,
	}
	C_ClassTalents = { GetActiveConfigID = function() return 1 end }
	C_SpecializationInfo = { HasPlayerEarnedATalentPoint = function() return true end }
	ns.TalentGroups = function() return groups end
	PlayerSpellsFrame = { TalentsFrame = {
		GetConfigID = function() return 1 end,
		IsVisible = function() return true end,
		EnumerateAllTalentButtons = function() return pairs(buttons) end,
	} }
	local url = "https://www.wowhead.com/forever/it/talent-calc/shaman/vkndmh-05203001-053020001_t0/"
	local function Import(suffix)
		ns.ShowEditWindow = function(_, _, _, _, accept) accept(url .. suffix) end
		ns.Print = function(text) message = text end
		import()
		return active()
	end
	local expected = "104729,104729,104729,104729,104729,104734,104734,104734,104735,104735,104732,"
		.. "104753,104753,104753,104753,104753,104755,104755,104755,104756,104756,104749"
	local plan = Import("2BCeej1BEcch?test=1#main")
	local name = className .. " (0/11/11)"
	assert(plan.name == name, "the import is named for the localized class and the point totals by tree")
	assert(ns.TalentBuilds.Points(plan) == 22 and table.concat(plan.order, ",") == expected and #bought == 0,
		"the exact Wowhead level order is stored, without buying any points")
	talents:ApplyPlan()
	assert(table.concat(bought, ",") == expected, "apply follows the Wowhead order")
	nodes[104729].ranksPurchased = 2
	plan = Import("2BCeej1BEcch")
	assert(plan.name == name .. " (2)", "reimporting keeps both plans and uses the full point distribution in the name")
	local remaining = expected:gsub("^104729,104729,", "")
	assert(table.concat(plan.order, ",") == remaining, "the first two ranks were already learned: " .. table.concat(plan.order, ","))
	nodes[104729].ranksPurchased = 0
	local inferred = table.concat(Import("").order, ",")
	assert(inferred ~= expected, "a rank-only link still gets an inferred order")
	assert(Import("2B").order[1] == 104729, "valid steps of a partial order precede inferred steps")
	assert(table.concat(Import("2Bbb").order, ",") == inferred and message == ns.L.TALENTS_LINK_ORDER_BAD,
		"an order exceeding the link's ranks falls back with a message")
	talents.db.builds[planKey], talents.cdb.activeBuild[planKey], talents.db.buildSeq = savedPlans, savedActive, savedSeq
	setuv(importLink, "playerClass", playerClass)
	setuv(importLink, "playerClassName", playerClassName)
	PlayerSpellsFrame, C_Traits, C_ClassTalents, C_SpecializationInfo = savedFrame, savedTraits, savedClassTalents, savedSpec
	ns.TalentGroups, ns.ShowEditWindow, ns.Print = savedGroups, savedEdit, savedPrint
	ns.After = savedAfter
	setuv(queue, "updatePending", savedPending)
	talents:QueuePlanUpdate()
	print("Wowhead talent order OK")
end)()
;(function()
	-- A choice on a step reached with "back" that gets no answer: the step comes again soon and says why.
	local dialog = ns:GetModule("Dialog")
	local savedCurrent, savedBubble = uv(dialog.Pending, "current"), uv(dialog.Pending, "bubble")
	local savedAfter, savedGossip, savedRerender = ns.After, GossipFrame, dialog.Rerender
	local waited, fire, redrawn
	ns.After = function(_, delay, fn) waited, fire = delay, fn end
	dialog.Rerender = function() redrawn = true end
	GossipFrame = { IsShown = function() return true end }
	local view = { kind = "GOSSIP_SHOW", stale = true, blocks = {} }
	setuv(dialog.Pending, "current", { view = view })
	setuv(dialog.Pending, "bubble", { pools = {}, IsShown = function() return true end })
	dialog.Pending()
	assert(waited and waited < 1, "a step from before comes back soon")
	fire()
	assert(redrawn and view.blocks[1].text == ns.L.DIALOG_NO_ANSWER, "it says that the choice got no answer")
	dialog.Pending()
	fire()
	assert(#view.blocks == 1, "said once")
	local live = { kind = "GOSSIP_SHOW", blocks = {} }
	setuv(dialog.Pending, "current", { view = live })
	dialog.Pending()
	assert(waited > 1, "the step the game is at waits as before")
	fire()
	assert(#live.blocks == 0, "and gets no note")
	ns.After, GossipFrame, dialog.Rerender = savedAfter, savedGossip, savedRerender
	setuv(dialog.Pending, "current", savedCurrent)
	setuv(dialog.Pending, "bubble", savedBubble)
	print("dialog choice without answer OK")
end)()
;(function()
	-- New ability: first free slot of the bars in order; none when all are full
	local qol = ns:GetModule("QoL")
	local used = { [1] = true, [2] = true, [61] = true }
	local has = function(slot) return used[slot] end
	assert(qol.FirstFreeSlot({ { 1, 2, 3 }, { 61, 62 } }, has) == 3, "main bar first")
	assert(qol.FirstFreeSlot({ { 1, 2 }, { 61, 62 } }, has) == 62, "then bar 2")
	assert(qol.FirstFreeSlot({ { 1, 2 }, { 61 } }, has) == nil, "all full")
	print("auto place slot OK")
end)()
;(function()
	-- Chat at the left edge: after Blizzard's insets pushed it, it goes back to its Edit Mode place
	local chat = ns:GetModule("Chat")
	local apply = uv(uv(uv(chat.OnLogin, "StyleAll"), "StyleChatFrame"), "HookEdges")
	apply = apply and uv(apply, "ApplyEdges")
	assert(apply, "ApplyEdges reachable")
	local insets = { -40, 0, 50, 0 }
	local anchored = 0
	local frame = { systemInfo = {}, GetLeft = function() return 0 end,
		GetClampRectInsets = function() return unpack(insets) end,
		SetClampRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end,
		ApplySystemAnchor = function() anchored = anchored + 1 end }
	local db = chat.db
	local saved = { db.chatEdges, db.hideButtons, InCombatLockdown }
	db.chatEdges, db.hideButtons = true, true
	InCombatLockdown = function() return false end
	apply(frame)
	assert(insets[1] == 0 and anchored == 1, "own insets, placed again")
	apply(frame)
	assert(anchored == 1, "unchanged insets: not placed again")
	db.chatEdges, db.hideButtons, InCombatLockdown = saved[1], saved[2], saved[3]
	print("chat edges reanchor OK")
end)()
;(function()
	-- Input line: a header Blizzard once narrowed to half the line gets its own width back
	local chat = ns:GetModule("Chat")
	local fix = uv(uv(uv(chat.OnLogin, "StyleAll"), "StyleChatFrame"), "StyleEditBox")
	fix = fix and uv(fix, "FixHeaderWidth")
	assert(fix, "FixHeaderWidth reachable")
	local width, textWidth, suffixShown, insets = 220, 40, false, nil
	local header = { GetWidth = function() return width end, GetStringWidth = function() return textWidth end,
		SetWidth = function(_, w) width = w == 0 and textWidth or w end }
	local box = { header = header, GetWidth = function() return 440 end,
		headerSuffix = { IsShown = function() return suffixShown end, Hide = function() suffixShown = false end },
		SetTextInsets = function(_, l) insets = l end }
	fix(box)
	assert(width == 40 and insets == 55, "header freed, text right after it")
	insets, width, suffixShown = nil, 221, true
	fix(box)
	assert(width == 40 and not suffixShown and insets == 55, "short text with stuck suffix: freed too")
	insets, width, textWidth, suffixShown = nil, 220, 300, true
	fix(box)
	assert(width == 220 and suffixShown and insets == nil, "really long header keeps Blizzard's shortening")
	textWidth, width, suffixShown = 40, 40, false
	fix(box)
	assert(insets == nil, "fitting header untouched")
	print("chat input header OK")
end)()
;(function()
	-- Auction sell frame: one large line, the calculation for the tooltip
	local A = ns:GetModule("Auction")
	local saved = GetMoneyString
	GetMoneyString = function(v) return tostring(v) .. "c" end
	local s = A.SellSummary(306, 400, true, true)
	assert(s.text == ns.L.AUCTION_SELL_PROFIT:format("+74c"), "profit: " .. s.text)
	assert(#s.lines == 4 and s.lines[3]:find("380c", 1, true), "formula with net price")
	s = A.SellSummary(306, 300, true, true)
	assert(s.text == ns.L.AUCTION_SELL_BELOW:format("−21c") and #s.lines == 5, "warning large, details in tooltip")
	s = A.SellSummary(306, 300, true, false)
	assert(s.text == ns.L.AUCTION_SELL_LOSS:format("−21c"), "loss without warning option")
	assert(A.SellSummary(306, 400, false, true) == nil, "only warning option, price fine: nothing")
	assert(A.SellSummary(306, nil, true, false).text == ns.L.AUCTION_SELL_NO_PRICE, "no price yet")
	assert(A.SellSummary(nil, 400, true, true) == nil, "no merchant price")
	GetMoneyString = saved
	print("auction sell summary OK")
end)()
;(function()
	-- Chat with hanging indent: continuation lines start with blanks as wide as the timestamp.
	local indent = ns:GetModule("ChatIndent")
	assert(indent and indent.Wrap, "chat indent module")
	local measureBefore, fn = indent.measure, uv(indent.Wrap, "PrepareMeter")
	indent.measure = function(text) return #(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
	-- meter is created on demand from the hider frame; the mock is lenient, so only the key matters here
	local frame = { GetWidth = function() return 60 end, GetFontObject = function() return nil end }
	ChatFrameUtil = { GetTimestampFormat = function() return "%H:%M " end }
	TimeUtil = { BetterDate = function(format, t) return os.date(format, t) end }
	local message = "12:34 aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll"
	local ok, wrapped = pcall(indent.Wrap, frame, message)
	assert(ok, tostring(wrapped))
	if wrapped then
		local first, second = wrapped:match("^(.-)\n(.*)$")
		assert(first and second:sub(1, 6) == "      ", "continuation indented by the timestamp: " .. wrapped)
		assert(not indent.Wrap({ GetWidth = function() return 400 end, GetFontObject = function() return nil end }, message), "short text unchanged")
		local savedAfter, enabled = C_Timer.After, indent.db.enabled
		local nextMessage = message .. " mmmm nnnn oooo"
		local history, queued, timers, scans = { message, nextMessage, message }, nil, 0, 0
		C_Timer.After = function(_, fn) queued, timers = fn, timers + 1 end
		frame.TransformMessages = function(_, predicate, transform)
			scans = scans + 1
			for i, text in ipairs(history) do
				if predicate(text) then
					history[i] = transform(text)
				end
			end
		end
		local add = uv(uv(indent.Apply, "Hook"), "OnAddMessage")
		indent.db.enabled = true
		for _, text in ipairs(history) do add(frame, text) end
		assert(timers == 1 and scans == 0, "the burst queues one history pass")
		queued()
		assert(scans == 1 and history[1] == wrapped and history[3] == wrapped and history[2] == indent.Wrap(frame, nextMessage),
			"the single history pass wraps both distinct messages and the duplicate")
		C_Timer.After, indent.db.enabled = savedAfter, enabled
		print("chat indent OK")
	else
		error("chat indent: no wrap")
	end
	indent.measure = measureBefore
	assert(fn, "meter set-up reachable")
end)()
;(function()
	-- Talent plan as Blizzard's loadout text: same bit layout the game reads back.
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local ExportPlan = menu and uv(menu, "ExportPlan")
	local LoadoutString = ExportPlan and uv(ExportPlan, "LoadoutString")
	assert(LoadoutString, "loadout writer reachable")
	local bits = {}
	ExportUtil = { MakeExportDataStream = function()
		return { AddValue = function(_, width, value) bits[#bits + 1] = { width, value } end, GetExportString = function() return "ok" end }
	end }
	C_Traits = { GetLoadoutSerializationVersion = function() return 2 end, GetTreeHash = function() return { 1, 2 } end,
		GetTreeNodes = function() return { 10, 11, 12, 13 } end,
		GetNodeInfo = function(_, id)
			local nodes = {
				[10] = { maxRanks = 5, ranksPurchased = 0, activeRank = 1 },   -- granted
				[11] = { maxRanks = 5, ranksPurchased = 0, activeRank = 0 },   -- wanted 5: full
				[12] = { maxRanks = 3, ranksPurchased = 0, activeRank = 0 },   -- wanted 2: partial
				[13] = { maxRanks = 1, ranksPurchased = 0, activeRank = 0 },   -- not wanted
			}
			return nodes[id]
		end }
	PlayerUtil = { GetCurrentSpecID = function() return 7 end }
	local frame = { GetConfigID = function() return 1 end, GetTreeInfo = function() return { ID = 77 } end, GetSpecID = function() return 7 end }
	assert(LoadoutString(frame, { [11] = 5, [12] = 2 }) == "ok")
	-- header: version, spec, two hash bytes; then per node: selected [purchased [partial [ranks] choice]]
	local flat = {}
	for _, bit in ipairs(bits) do flat[#flat + 1] = bit[1] .. ":" .. bit[2] end
	local text = table.concat(flat, " ")
	assert(text == "8:2 16:7 8:1 8:2 1:1 1:0 1:1 1:1 1:0 1:0 1:1 1:1 1:1 6:2 1:0 1:0", text)
	-- Import: the build lands in the plan (granted ranks are not counted), nothing is learned.
	local ImportPlan = uv(menu, "ImportPlan")
	assert(ImportPlan, "import reachable")
	local callback
	local oldShow, oldPrint = ns.ShowEditWindow, ns.Print
	ns.ShowEditWindow = function(_, _, _, _, onAccept) callback = onAccept end
	local printed
	ns.Print = function(...) printed = { ... } end
	for i = 1, 60 do
		local name = debug.getupvalue(ImportPlan, i)
		if name == "ParseBuild" then
			debug.setupvalue(ImportPlan, i, function()
				return { { nodeID = 11, ranksPurchased = 3 }, { nodeID = 11, ranksPurchased = 4 }, { nodeID = 10, ranksPurchased = 0, ranksGranted = 1 }, { nodeID = 12, ranksPurchased = 2 } }
			end)
		end
	end
	PlayerSpellsFrame = { TalentsFrame = frame }
	ImportPlan()
	assert(callback, "import window")
	talents.db.planner = true
	callback("  abc  ")
	local plan = talents:CurrentPlan()
	assert(plan[11] == 5 and plan[12] == 2 and plan[10] == nil, "plan from the import (capped at the maximum ranks)")
	assert(printed and printed[2] == 7 and printed[3] == 2 and printed[4] == 16, "report: points, talents, level")
	ns.ShowEditWindow, ns.Print = oldShow, oldPrint
	print("talent loadout string OK")
end)()
;(function()
	-- Restock: tops up a marked item to a full stack from the bank.
	local r = ns:GetModule("Restock")
	r.cdb.items = { [2589] = true }
	local bags = { [0] = { [1] = { itemID = 2589, stackCount = 7 } }, [6] = { [3] = { itemID = 2589, stackCount = 30 } } }
	C_Container.GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end
	C_Container.GetContainerNumFreeSlots = function() return 3, 0 end
	local calls = {}
	C_Container.SplitContainerItem = function(bag, slot, n) calls[#calls + 1] = ("split %d %d %d"):format(bag, slot, n) end
	C_Container.PickupContainerItem = function(bag, slot) calls[#calls + 1] = ("pickup %d %d"):format(bag, slot) end
	C_Item.GetItemMaxStackSizeByID = function() return 20 end
	C_Item.GetItemCount = function() return 7 end
	C_Bank = { CanUseBank = function(t) return t == 0 end, FetchPurchasedBankTabIDs = function() return { 6 } end }
	Enum.BankType = { Character = 0, Account = 2 }
	GetCursorInfo = function() return nil end
	local Step = uv(uv(r.Apply, "Start"), "Step")
	local MoveOne = uv(Step, "MoveOne")
	setuv(MoveOne, "atBank", true)
	setuv(MoveOne, "run", { skip = {}, moved = {}, steps = 0 })
	assert(MoveOne(), "one move")
	print("  ", table.concat(calls, " | "))
	assert(calls[1] == "split 6 3 13" and calls[2] == "pickup 0 1", "13 from the bank onto the stack of 7")
	C_Item.GetItemCount = function() return 20 end
	assert(not MoveOne(), "full stack: nothing left")
	-- the other way round: marked for the bank, the bag stack goes onto the bank stack with room
	r.cdb.items = { [2589] = "bank" }
	bags[6][3] = { itemID = 2589, stackCount = 5 }
	calls = {}
	setuv(MoveOne, "run", { skip = {}, moved = {}, stored = {}, steps = 0 })
	assert(MoveOne() and calls[1] == "pickup 0 1" and calls[2] == "pickup 6 3", "bag stack onto the bank stack")
	r.cdb.items = {}
	setuv(MoveOne, "run", nil)
	setuv(MoveOne, "atBank", false)
	local update = uv(r.OnLogin, "PostUpdateItems")
	local savedItemID, itemIDReads = C_Container.GetContainerItemID, 0
	C_Container.GetContainerItemID = function()
		itemIDReads = itemIDReads + 1
		return 2589
	end
	local textures, atlasUpdates = {}, 0
	local button = NewFrame("Button")
	button.GetBagID, button.GetID = function() return 0 end, function() return 1 end
	button.CreateTexture = function()
		local texture = NewFrame("Texture")
		texture.SetAtlas = function() atlasUpdates = atlasUpdates + 1 end
		textures[#textures + 1] = texture
		return texture
	end
	local frame = { EnumerateValidItems = function() return ipairs({ button }) end }
	update(frame)
	assert(itemIDReads == 0 and button:GetScript("OnMouseUp"), "empty restock list still hooks marking without reading slots")
	r.cdb.items[2589] = true
	update(frame)
	update(frame)
	assert(itemIDReads == 2 and textures[1]:IsShown() and atlasUpdates == 1, "the same mark keeps its existing texture")
	r.cdb.items[2589] = nil
	update(frame)
	assert(itemIDReads == 2 and not textures[1]:IsShown() and not textures[2]:IsShown(), "removing the last mark clears its textures")
	C_Container.GetContainerItemID = savedItemID
	print("restock OK")
end)()
;(function()
	-- Quest preview: open objectives on the map, turn-in once they are done.
	local spawns = { [6] = { [12] = { { 40, 80 } } }, [7] = { [12] = { { 30, 30 }, { 31, 31 } } }, [20] = { [40] = { { 50, 50 } } },
		[30] = { [12] = { { 60, 60 } } } }
	local quest = { objectives = { { { 6, nil, 0 } }, nil, { { 750, nil, 0 } }, nil, { { { 20, 21 }, 22, nil, 0 } } },
		finishedBy = { { 30 } } }
	LibQuestieDB = {
		Support = { Get = function() return { private = { areaIdToUiMapId = { [12] = 1429, [40] = 1436 } } } end },
		Quest = { Exists = function(id) return id == 33 end, Get = function(_, key) return quest[key] end, GetAll = function() end, GetAllIds = function() return {} end },
		Npc = { Get = function(id, key) if key == "spawns" then return spawns[id] end if key == "name" then return id == 30 and "Marschall" end end },
		Item = { Get = function(id, key) return id == 750 and key == "npcDrops" and { 7 } or nil end },
		Object = { Get = function() end },
	}
	setuv(ns.QuestieDB.UiMapForArea, "areaToUiMap", nil)
	local objectives = { { type = "monster", text = "Kobold: 10/10", finished = true }, { type = "item", text = "Kerze: 0/8", finished = false },
		{ type = "monster", text = "Mine erkundet: 0/1", finished = false } }
	C_QuestLog.GetQuestObjectives = function() return objectives end
	C_QuestLog.GetTitleForQuestID = function() return "Koboldlager" end
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(id) return { name = id == 1429 and "Wald von Elwynn" or "Westfall" } end
	C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
	C_Map.GetMapArtLayerTextures = function() local t = {} for i = 1, 12 do t[i] = 100 + i end return t end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	C_MapExplorationInfo = { GetExploredMapTextures = function() return {} end }
	GameTooltip = CreateFrame("GameTooltip")
	ns:GetModule("WorldMap").db.reveal = false
	local P = ns.QuestPreview
	local build, bodyText = uv(P.Show, "Build"), uv(P.Show, "BodyText")
	local model = build(33)
	assert(#model.maps[1429] == 2 and #model.maps[1436] == 1 and not model.turnIn, "item drops in Elwynn, kill credit in Westfall")
	assert(uv(P.Show, "ChooseMap")(model.maps) == 1429, "player's map first")
	local text = bodyText(model, 1429)
	print("  ", (text:gsub("\n", " / ")))
	assert(text:find("Kerze") and text:find("Westfall"), "objectives and other zone")
	P.Show(CreateFrame("Frame"), 33)
	local release = uv(P.Show, "ReleaseAll")
	assert(uv(release, "mapUsed") == 12 and uv(release, "markUsed") == 5, "12 map tiles, 2 dots with rings, player arrow")
	for _, objective in ipairs(objectives) do objective.finished = true end
	model = build(33)
	assert(model.turnIn and #model.maps[1429] == 1 and model.turnInName == "Marschall", "turn-in")
	assert(bodyText(model, 1429):find("Marschall"), "turn-in line")
	P.Hide()
	print("quest preview OK")
end)()

;(function()
	-- World map symbols: instance entrances from the group finder list, flight masters and inns of the own faction,
	-- town and city names, recipe vendors.
	local wm = ns:GetModule("WorldMap")
	local S = ns.MapSymbols
	ns:GetModule("Library").db.symbols = false
	local dungeons = { [1581] = { "The Deadmines", nil, 40, { { 40, 42.5, 71.7 } } }, [1584] = { "Blackrock Depths", nil, 51, { { 51, 34.8, 85.3 } } },
		[2717] = { "Molten Core", nil, 51, { { 51, 35, 85 } } }, [2366] = { "The Black Morass", nil, 440, { { 440, 65.7, 49.8 } } } }
	local npcs = { [523] = { name = "Thor", subName = "Greifenmeister", npcFlags = 11, friendlyToFaction = "A", spawns = { [40] = { { 56.6, 52.6 } } } },
		[2995] = { name = "Tal", npcFlags = 11, friendlyToFaction = "H", spawns = { [40] = { { 10, 10 } } } },
		[100] = { name = "Händler", npcFlags = 4, friendlyToFaction = "A", spawns = { [40] = { { 20, 20 } } } },
		[8931] = { name = "Gastwirtin Heather", subName = "Gastwirtin", raw = "Innkeeper", npcFlags = 135, friendlyToFaction = "A", spawns = { [40] = { { 52.9, 53.7 } } } },
		[1460] = { name = "Unger Statforth", subName = "Pferdezüchter", raw = "Horse Breeder", npcFlags = 135, friendlyToFaction = "A", spawns = { [40] = { { 30, 30 } } } } }
	LibQuestieDB = {
		Support = { Get = function() return { private = { dungeons = dungeons, areaIdToUiMapId = { [40] = 1436, [51] = 1427, [440] = 1446 } },
			instanceIdToAreaId = { [36] = 1581, [230] = 1584, [409] = 2717, [269] = 2366 } } end },
		Quest = { Exists = function() return false end, Get = function() end, GetAll = function() end, GetAllIds = function() return {} end },
		Npc = { GetAllIds = function() return { 100, 523, 2995, 8931, 1460 } end, Get = function(id, key) return npcs[id] and npcs[id][key] end,
			GetRaw = function(id, key) return key == "subName" and npcs[id] and npcs[id].raw end },
	}
	setuv(ns.QuestieDB.UiMapForArea, "areaToUiMap", nil)
	ns.Instances = { [36] = "dungeon", [230] = "dungeon", [409] = "raid" }
	ns.Places = { { 0, -9480, 63, 87, "Goldshire", "town", 1429 }, { 0, -9154, 364, 1519, "Stormwind", "city", 1453 },
		{ 1, 1, 1, 0, "Razor Hill", "town", 1411 } }
	GetRealZoneText = function(id) return id == 36 and "Die Todesminen" or "" end
	UnitFactionGroup = function() return "Alliance" end
	CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
	local savedMapTicker = C_Timer.NewTicker
	C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
	local canvas = CreateFrame("Frame")
	canvas.GetWidth = function() return 1000 end
	canvas.GetHeight = function() return 600 end
	local mapID = 1436
	WorldMapFrame = CreateFrame("Frame")
	WorldMapFrame.GetCanvas = function() return canvas end
	WorldMapFrame.GetCanvasScale = function() return 2 end
	WorldMapFrame.GetMapID = function() return mapID end
	WorldMapFrame.EnumeratePinsByTemplate = function() return function() end end
	C_Map.GetMapInfo = function(id) return { mapType = id == 1415 and 2 or 3 } end
	C_Map.GetMapChildrenInfo = function() return { { mapID = 1436 }, { mapID = 1427 }, { mapID = 1429 } } end
	C_Map.GetMapRectOnMap = function(child) if child == 1436 then return 0.4, 0.5, 0.7, 0.8 end return 0.5, 0.6, 0.5, 0.6 end
	C_Map.GetWorldPosFromMapPos = function() return 0, CreateVector2D(0, 0) end
	-- Without a map the client answers with the continent (seen in the game: towns were missing).
	C_Map.GetMapPosFromWorldPos = function(_, pos, override)
		if override == 1429 then return 1429, CreateVector2D(pos.x == -9480 and 0.42 or 0.2, pos.x == -9480 and 0.66 or 0.2) end
		if override == 1415 then return 1415, CreateVector2D(0.45, 0.75) end
		if override == 1453 then return 1453, CreateVector2D(0.5, 0.5) end
		return override or 1415, CreateVector2D(1.5, 1.5) -- outside the map
	end
	C_Map.GetAreaInfo = function(id) return id == 87 and "Goldhain" or id == 1519 and "Sturmwind" or "" end
	Enum.UIMapType = { World = 1, Continent = 2, Zone = 3 }
	ns:GetModule("RecipeRadar").db.worldMap = false
	-- The earlier world map test set up the layer on its own map mock.
	local refresh = S.Refresh
	local draw = uv(refresh, "Draw")
	setuv(refresh, "layer", nil)
	setuv(refresh, "entrances", nil)
	setuv(uv(refresh, "BuildNpcs"), "npcs", nil)
	for _, source in ipairs(uv(uv(S.Count, "Collect"), "sources")) do
		local continent, place = uv(source, "Continent"), uv(source, "PlacePosition")
		if continent then setuv(continent, "continents", {}) end
		if place then setuv(place, "positions", {}) end
	end
	for k in pairs({ entrances = 1, flightPoints = 1, inns = 1, places = 1 }) do wm.db[k] = true end
	wm:Apply()
	local function active()
		local list, frames = {}, uv(draw, "frames")
		for i = 1, uv(draw, "used") do list[#list + 1] = frames[i].symbol end
		return list
	end
	local function kinds(list)
		local count = {}
		for _, symbol in ipairs(list) do count[symbol.kind] = (count[symbol.kind] or 0) + 1 end
		return count
	end
	local list = active()
	local count = kinds(list)
	assert(#list == 3 and count.entrance == 1 and count.flight == 1 and count.inn == 1, "Westfall: Deadmines, Thor, inn; got " .. #list)
	assert(list[1].data.names[1][1] == "Die Todesminen", "client name")
	assert(list[2].data.name == "Thor" and math.abs(list[2].x - 0.566) < 1e-9, "own faction only")
	assert(list[3].data.name == "Gastwirtin Heather", "innkeeper by base title, not the horse breeder")
	mapID = 1415
	draw()
	list = active()
	count = kinds(list)
	assert(count.entrance == 2 and count.flight == 2 and not count.inn and count.place == 1, "continent: zones' symbols, the capital, no inns")
	for _, symbol in ipairs(list) do
		if symbol.kind == "place" then assert(symbol.label == "Sturmwind" and symbol.x == 0.45, "capital on the continent") end
		if symbol.kind == "flight" and symbol.data.name == "Thor" then assert(math.abs(symbol.x - (0.4 + 0.566 * 0.1)) < 1e-9, "zone rect on continent") end
		if symbol.kind == "entrance" and #symbol.data.names == 2 then
			local k = {}
			for _, entry in ipairs(symbol.data.names) do k[entry[2]] = true end
			assert(k.raid and k.dungeon and symbol.atlas == "dungeon", "Blackrock Depths and Molten Core share a symbol")
		end
	end
	local savedLocale, savedLocales = GetLocale, {}
	for _, key in ipairs({ "WORLDMAP_FLIGHT", "WORLDMAP_FLIGHT_LOCATION", "WORLDMAP_FLIGHT_PLACES",
		"WORLDMAP_FLIGHT_TITLES", "WORLDMAP_FLIGHT_MASTERS" }) do
		savedLocales[key] = ns.L[key]
	end
	local german = { L = {} }
	GetLocale = function() return "deDE" end
	assert(loadfile(root .. "/Locales/deDE.lua"))("ForeverPlus", german)
	for key in pairs(savedLocales) do ns.L[key] = german.L[key] end
	local savedMapInfo, savedAreaInfo = C_Map.GetMapInfo, C_Map.GetAreaInfo
	C_Map.GetMapInfo = function(id) return id == 1425 and { name = "Hinterland", mapType = 3 } or savedMapInfo(id) end
	C_Map.GetAreaInfo = function(id) return id == 348 and "Nistgipfel" or savedAreaInfo(id) end
	local bundledFlights = uv(uv(refresh, "BuildNpcs"), "BundledFlights")
	local guthrum = bundledFlights("A")[1425][1]
	assert(guthrum.name == "Guthrum Thunderfist" and guthrum.title == "Greifenmeister"
		and guthrum.node == "Nistgipfel, Hinterland", "German flight tooltip uses localized role, settlement and zone")
	assert(bundledFlights("H")[1441][1].title == "Windreitermeisterin", "German title for Nyse")
	GetLocale, C_Map.GetMapInfo, C_Map.GetAreaInfo = savedLocale, savedMapInfo, savedAreaInfo
	for key, value in pairs(savedLocales) do ns.L[key] = value end
	mapID = 1429
	draw()
	list = active()
	local labels = {}
	for _, symbol in ipairs(list) do if symbol.label then labels[symbol.label] = symbol end end
	assert(labels.Goldhain and labels.Sturmwind and labels.Sturmwind.x == 0.2, "town and capital names on the zone map")
	mapID = 1453
	draw()
	assert(kinds(active()).place == nil, "no capital name on its own city map")
	wm.db.flightPoints, wm.db.inns, wm.db.places = false, false, false
	wm:OnOptionChanged("flightPoints", false)
	mapID = 1436
	draw()
	assert(#active() == 1, "flight points and inns off")
	local counts = S.Count(1436)
	assert(counts.entrance == 1, "count")
	-- Recipe vendors: round icons with their own click (waypoint).
	local radar = ns:GetModule("RecipeRadar")
	radar.db.worldMap = true
	local itemCount = C_Item.GetItemCount
	C_Item.GetItemCount = function() return 0 end -- earlier tests leave a count; a recipe in the bags counts as collected
	local getVendors
	for _, source in ipairs(uv(uv(S.Count, "Collect"), "sources")) do
		local ok, found = pcall(uv, source, "GetVendors")
		if ok and found then getVendors = source end
	end
	local vendorMap
	for id, list in pairs(uv(uv(getVendors, "GetVendors"), "vendorsByMap")) do if #list > 0 then vendorMap = id break end end
	mapID = vendorMap
	draw()
	local radarSymbol
	for _, symbol in ipairs(active()) do if symbol.kind == "radar" then radarSymbol = symbol end end
	print("  radar symbols on map", vendorMap, S.Count(vendorMap).radar)
	assert(radarSymbol and radarSymbol.round and radarSymbol.click and radarSymbol.mapID == vendorMap, "radar symbol")
	local fillTooltip = uv(radarSymbol.tooltip, "FillVendorTooltip")
	local npcTitle = uv(fillTooltip, "NpcTitle")
	local npcName = uv(fillTooltip, "NpcName")
	local savedDB = uv(npcTitle, "DB")
	setuv(npcTitle, "DB", nil)
	assert(npcName(5494) == "Catherine Leland", "bundled name without QuestieDB")
	local isGerman = GetLocale() == "deDE"
	local fishingTitle = isGerman and "Angelbedarf" or "Fishing Supplier"
	assert(npcTitle(5494) == fishingTitle, "local fishing supplier title")
	assert(npcTitle(4223) == (isGerman and "Kochbedarf" or "Cooking Supplies"), "later era title excluded")
	setuv(npcTitle, "DB", { Npc = { Get = function(id, field)
		if id == 5494 and field == "name" then return "Localised vendor name" end
		if id == -1 and field == "subName" then return "Fishing Supplier" end
	end } })
	assert(npcName(5494) == "Localised vendor name", "prefer QuestieDB's localised name")
	assert(npcName(4223) == "Fyldan", "use the bundled name when QuestieDB has none")
	assert(npcTitle(-1) == fishingTitle, "QuestieDB's English title can also be translated")
	setuv(npcTitle, "DB", savedDB)
	C_Item.GetItemCount = itemCount
	C_Timer.NewTicker = savedMapTicker
	radar.db.worldMap = false
	print("world map symbols OK")
end)()
;(function()
	local map = ns:GetModule("WorldMap")
	local collect = uv(ns.MapSymbols.Count, "Collect")
	local savedLog, savedCVar, savedBundled = C_QuestLog, GetCVarBool, ns.QuestieDB.Bundled
	local blizzard, open, ready = false, true, true
	local quests = {
		{ questID = 1, title = "Ready A" }, { questID = 2, title = "Ready B" }, { questID = 3, title = "In progress" },
		{ questID = 4, title = "Failed" }, { questID = 5, title = "Fallback" }, { questID = 6, title = "Talk to someone" },
		{ questID = 7, title = "Remote turn-in", isAutoComplete = true },
	}
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #quests end,
		GetInfo = function(index) if index ~= 1 or open then return quests[index] end end,
		ReadyForTurnIn = function(id) return id ~= 3 and (id ~= 1 or ready) end,
		IsFailed = function(id) return id == 4 end,
		GetQuestsOnMap = function(mapID)
			if mapID == 1436 then
				return {
					{ questID = 1, x = 0.3, y = 0.4 }, { questID = 2, x = 0.3, y = 0.4 },
					{ questID = 3, x = 0.5, y = 0.4 }, { questID = 4, x = 0.5, y = 0.4 },
					{ questID = 5, x = 0, y = 0 }, { questID = 6, x = 0.6, y = 0.6 },
					{ questID = 7, x = 0.5, y = 0.4 }, { questID = 2, x = 0.5, y = 0.4, isQuestStart = true },
					{ questID = 2, x = 0.5, y = 0.4, isMapIndicatorQuest = true },
				}
			end
		end,
		IsQuestFlaggedCompleted = function() return false end,
		GetLogIndexForQuestID = function() return nil end,
	}
	ns.QuestieDB.Bundled = function()
		return { Quest = { Get = function(id, field)
			assert(field == "turnInPoint", "only hand-in data may supply the fallback")
			if id == 1 or id == 5 then return { { 1436, 70, 80 }, { 1436, 70, 80 } } end
		end } }
	end
	GetCVarBool = function(key) return key == "questPOI" and blizzard end
	local savedBoards, savedOption = GetNumQuestLeaderBoards, map.db.questTurnIns
	GetNumQuestLeaderBoards = function(index) return index ~= 6 and 1 or 0 end
	local function pins(mapID)
		local result = {}
		for _, pin in ipairs(collect(mapID)) do
			if pin.kind == "questTurnIn" then result[#result + 1] = pin end
		end
		table.sort(result, function(a, b) return a.x < b.x end)
		return result
	end
	assert(savedOption, "the filter is on by default")
	local list = pins(1436)
	assert(#list == 2 and list[1].atlas == "QuestTurnin" and list[1].x == 0.3 and list[1].y == 0.4
		and table.concat(list[1].data, ", ") == "Ready A, Ready B", "client coordinates and one pin per shared hand-in location")
	assert(list[2].x == 0.7 and list[2].y == 0.8 and table.concat(list[2].data) == "Fallback", "only the missing client point uses the bundled fallback")
	list = pins(1415)
	assert(#list == 1 and math.abs(list[1].x - 0.47) < 1e-9 and math.abs(list[1].y - 0.78) < 1e-9, "zone point on continent map")
	ready = false
	assert(table.concat(pins(1436)[1].data) == "Ready B", "the pin clears when the objectives are no longer complete")
	ready, open = true, false
	assert(table.concat(pins(1436)[1].data) == "Ready B", "the pin clears when the quest leaves the log")
	blizzard = true
	assert(#pins(1436) == 0, "Blizzard's quest filter avoids a duplicate overlay")
	blizzard, map.db.questTurnIns = false, false
	assert(#pins(1436) == 0, "the hand-in filter can be turned off independently")
	map.db.questTurnIns, GetNumQuestLeaderBoards = savedOption, savedBoards
	C_QuestLog, GetCVarBool, ns.QuestieDB.Bundled = savedLog, savedCVar, savedBundled
	print("quest turn-in pins OK")
end)()
assert(loadfile("quest_calendar.lua"))(ns, uv, setuv)
;(function()
	local wm, symbols = ns:GetModule("WorldMap"), ns.MapSymbols
	local db, collect = wm.db, uv(symbols.Count, "Collect")
	local savedFaction, savedComplete, savedLib = UnitFactionGroup, C_QuestLog.IsQuestFlaggedCompleted, ns.QuestieDB.Get
	local savedCount, savedJournal, savedRefresh = C_Item.GetItemCount, rawget(_G, "C_PetJournal"), symbols.Refresh
	local savedMarks = wm.cdb.collectedDiscoveries
	local marks, faction, completed, items, pets, redraws = {}, "Alliance", {}, {}, {}, 0
	wm.cdb.collectedDiscoveries = marks
	UnitFactionGroup = function() return faction end
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return completed[id] end
	C_Item.GetItemCount = function(id) return items[id] and 1 or 0 end
	C_PetJournal = { GetNumPetsInJournal = function(id) return 3, pets[id] and 1 or 0 end }
	symbols.Refresh = function() redraws = redraws + 1 end
	ns.QuestieDB.Get = function() return nil end
	local events = uv(ns.RegisterEvent, "listeners")
	local function fire(event, id) events[event][wm](wm, event, id) end
	local function pins(mapID)
		local result = {}
		for _, pin in ipairs(collect(mapID)) do
			if pin.kind == "discovery" then result[#result + 1] = pin end
		end
		return result
	end
	assert(db.discoveries == false, "discoveries are opt-in")
	for mapID in pairs(ns.MapDiscoveries) do
		assert(#pins(mapID) == 0, "the default filter hides every discovery")
	end
	db.discoveries = true
	local loch = pins(1432)
	assert(#loch == 7 and loch[1].x == 0.457 and loch[1].y == 0.433, "the toolbox, dam and hatchling, without QuestieDB")
	local lines = {}
	local tooltip = { AddLine = function(_, line) lines[#lines + 1] = line end }
	local savedInstruction = GameTooltip_AddInstructionLine
	GameTooltip_AddInstructionLine = tooltip.AddLine
	loch[1].tooltip(tooltip, loch[1])
	assert(lines[1] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER and lines[2] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER_TOOLBOX
		and lines[3] == ns.L.WORLDMAP_DISCOVERY_POSSIBLE:format(45.7, 43.3), "localized hint and possible coordinates")
	assert(lines[4] == ns.L.WORLDMAP_DISCOVERY_WAYPOINT_CLICK and lines[5] == ns.L.WORLDMAP_DISCOVERY_MARK,
		"the tooltip shows both mouse actions")
	assert(#pins(1415) == 0 and #pins(1447) == 1 and #pins(2521) == 3, "discoveries appear on their own zone maps")
	local waypoint = ns:GetModule("Waypoint")
	local savedSetOnMap, savedPrint = waypoint.SetOnMap, ns.PrintAlways
	local goal, message
	waypoint.SetOnMap = function(mapID, x, y, name)
		goal = { mapID, x, y, name }
		return true
	end
	loch[2].click(loch[2], "LeftButton")
	assert(goal and goal[1] == 1432 and goal[2] == 48 and goal[3] == 40 and goal[4] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER,
		"left click sets a named waypoint at the selected possible location")
	assert(#pins(1432) == 7 and redraws == 0, "setting a waypoint leaves the discovery open")
	waypoint.SetOnMap = function() return false end
	ns.PrintAlways = function(text) message = text end
	loch[1].click(loch[1], "LeftButton")
	assert(message == ns.L.WAYPOINT_NOT_HERE and not marks.silver, "an unavailable waypoint reports the failure without marking the find")
	db.discoveryWaypoint = false
	message, lines = nil, {}
	loch[1].click(loch[1], "LeftButton")
	loch[1].tooltip(tooltip, loch[1])
	assert(not message and #lines == 4 and lines[4] == ns.L.WORLDMAP_DISCOVERY_MARK,
		"turning off discovery waypoints disables left click and its tooltip hint")
	loch[1].click(loch[1], "RightButton")
	assert(marks.silver == "manual" and #pins(1432) == 3 and redraws == 1, "right click hides all alternative positions")
	db.discoveryWaypoint = true
	waypoint.SetOnMap, ns.PrintAlways, GameTooltip_AddInstructionLine = savedSetOnMap, savedPrint, savedInstruction
	symbols.ResetDiscoveryMarks()
	assert(#pins(1432) == 7 and not marks.silver, "manual marks can be cleared")
	faction = "Horde"
	assert(#pins(1432) == 3 and #pins(1431) == 8 and #pins(1441) == 3 and #pins(1438) == 0, "faction applies to special quests and nests")
	fire("QUEST_TURNED_IN", 4821)
	assert(marks.alienEgg == true and #pins(1441) == 0, "the turn-in marks the egg even if it has already left the bags")
	fire("QUEST_ACCEPTED", 79007)
	assert(#pins(1413) == 0 and pins(1436)[1].data.id == "bagWestfall", "a Horde quest pickup marks only its own sleeping bag stop")
	completed[99267] = true
	faction = "Alliance"
	fire("PLAYER_ENTERING_WORLD")
	assert(#pins(1431) == 0, "existing completion of a quest variant is recognized")
	fire("QUEST_ACCEPTED", 86614)
	assert(marks.silver == true and #pins(1432) == 3, "the toolbox is collected as soon as the quest begins")
	local darkshore = pins(1439)
	darkshore[1].click(darkshore[1], "RightButton")
	pets[274334] = true
	fire("PET_JOURNAL_LIST_UPDATE")
	symbols.ResetDiscoveryMarks()
	assert(marks.tallstriderHatchling == true and #pins(1439) == 0, "learning the pet preserves a previously manual mark")
	db.discoveries, items[5167] = false, true
	fire("BAG_UPDATE_DELAYED")
	items[5167], db.discoveries = false, true
	assert(marks.webwoodEgg == true and #pins(1438) == 0, "looted nest items are remembered even with the filter off")
	local elwynn = pins(1429)
	assert(#elwynn == 2 and elwynn[1].data.id == "applejackStill" and elwynn[1].point[1] == 24.5,
		"the Applejack Still and its follow-up are marked in Elwynn")
	items[247824] = true
	fire("BAG_UPDATE_DELAYED")
	assert(marks.applejackStill == true and #pins(1429) == 1 and pins(1429)[1].data.id == "applejackTreat",
		"obtaining the Applejack leaves the follow-up visible")
	fire("QUEST_TURNED_IN", 91738)
	assert(marks.applejackTreat == true and #pins(1429) == 0, "the follow-up hides once turned in")
	assert(#pins(1453) == 1 and #pins(1454) == 0 and #pins(1434) == 1, "Alliance and neutral Alcaz contacts")
	faction = "Horde"
	marks.applejackStill, marks.applejackTreat = nil, nil
	assert(#pins(1429) == 0 and #pins(1453) == 0 and #pins(1454) == 1 and #pins(1434) == 1,
		"Horde and neutral Alcaz contacts, no Applejack quests")
	fire("QUEST_TURNED_IN", 96379)
	assert(#pins(1434) == 0 and #pins(1454) == 0, "the neutral turn-in also finishes the Horde route")
	faction = "Alliance"
	fire("QUEST_TURNED_IN", 96377)
	assert(#pins(1453) == 0, "the faction turn-in finishes the Alliance route")
	assert(#pins(1417) == 1 and #pins(1420) == 1 and #pins(1435) == 1 and #pins(1445) == 2, "all four Scarlet Echo stops")
	items[215427] = true
	fire("BAG_UPDATE_DELAYED")
	assert(marks.scarletArathi == true and not marks.scarletTheramore and #pins(1417) == 0,
		"one echo hides only its own marker")
	items[215427], items[278030] = false, true
	fire("PLAYER_ENTERING_WORLD")
	assert(marks.scarletGraveyard == true and marks.scarletSwamp == true and marks.scarletTheramore == true
		and #pins(1445) == 1 and pins(1445)[1].data.id == "alcazPrison", "owning the banner hides the remaining echo markers")
	local ids = {}
	for _, entries in pairs(ns.MapDiscoveries) do
		for _, entry in ipairs(entries) do
			assert(entry.id and not ids[entry.id] and (entry.items or entry.quests or entry.pet), "each discovery has a stable ID and detection data")
			assert(ns.L.WORLDMAP_DISCOVERY_TEXT[entry.name] and ns.L.WORLDMAP_DISCOVERY_TEXT[entry.hint], "each discovery has localized text")
			ids[entry.id] = true
		end
	end
	local questSource
	for _, source in ipairs(uv(collect, "sources")) do
		if uv(source, "QuestStartAvailable") then questSource = source end
	end
	local savedStarts, savedActive, savedOption = uv(questSource, "questStarts"), C_QuestLog.GetLogIndexForQuestID, db.questStarts
	setuv(questSource, "questStarts", { [1432] = { { x = 50.6, y = 53.4, data = { id = 86614 } } } })
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	ns.QuestieDB.Get = function() return {} end
	db.questStarts = true
	questSource(1432, function() error("a discovery replaces its ordinary quest start pin") end)
	db.discoveries = false
	local starts = 0
	questSource(1432, function() starts = starts + 1 end)
	assert(starts == 1, "the ordinary quest start is restored when discoveries are disabled")
	setuv(questSource, "questStarts", savedStarts)
	C_QuestLog.GetLogIndexForQuestID, db.questStarts = savedActive, savedOption
	UnitFactionGroup, C_QuestLog.IsQuestFlaggedCompleted, ns.QuestieDB.Get = savedFaction, savedComplete, savedLib
	C_Item.GetItemCount, C_PetJournal, symbols.Refresh = savedCount, savedJournal, savedRefresh
	wm.cdb.collectedDiscoveries = savedMarks
	print("map discoveries OK")
end)()

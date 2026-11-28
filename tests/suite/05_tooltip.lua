(function()
	local module = ns:GetModule("Tooltip")
	local enter, leave = uv(module.OnLogin, "OnChatItemLinkEnter"), uv(module.OnLogin, "OnChatItemLinkLeave")
	local shiftChanged = uv(module.OnLogin, "OnShiftChanged")
	local onItem = uv(module.OnInitialize, "OnItemTooltip")
	local savedTooltip, savedUtil, savedCompare = GameTooltip, TooltipUtil, GameTooltip_ShowCompareItem
	local savedShift, savedSections, savedArrow = IsShiftKeyDown, ns.itemSections, ns.ItemLinkUpgradeState
	local savedGetter, savedEquippable = C_TooltipInfo.GetHyperlink, C_Item.IsEquippableItem
	local savedColoredLine = GameTooltip_AddColoredLine
	local savedFlag, savedCalls = module.db.shiftInfo, #TEST_POSTCALLS
	local armor, food = "item:1234:0:0:0", "item:5678:0:0:0"
	local shift, compared, lines, arrow = false, false, {}
	local tip = NewFrame("GameTooltip")
	GameTooltip, module.db.shiftInfo = tip, true
	module:OnInitialize()
	for i = #TEST_POSTCALLS, savedCalls + 1, -1 do TEST_POSTCALLS[i] = nil end
	tip:Hide()
	tip.SetOwner = function(self, owner) self.owner = owner end
	tip.GetOwner = function(self) return self.owner end
	tip.GetPrimaryTooltipInfo = function(self) return self.infoList and self.infoList[1] end
	tip.AddLine = function(_, line) lines[line] = true end
	GameTooltip_AddColoredLine = function(_, line, color) lines[line] = color end
	tip.CreateTexture = function()
		arrow = NewFrame("Texture")
		arrow.SetDesaturated = function(self, value) self.desaturated = value end
		return arrow
	end
	tip.Hide = function(self)
		self.shown, compared = false, false
		self:GetScript("OnHide")(self)
	end
	TooltipUtil = { ShouldDoItemComparison = function() return false end }
	GameTooltip_ShowCompareItem = function() compared = true end
	IsShiftKeyDown = function() return shift end
	ns.itemSections = { { fn = function() return { { left = "Shift item info" } } end } }
	ns.ItemLinkUpgradeState = function() return "later" end
	C_Item.IsEquippableItem = function(link) return link == armor end
	C_TooltipInfo.GetHyperlink = function(link)
		return { hyperlink = link, type = Enum.TooltipDataType.Item, lines = {} }
	end
	tip.SetHyperlink = function(self, link)
		lines, compared = {}, false
		self:GetScript("OnTooltipCleared")(self)
		local data = C_TooltipInfo.GetHyperlink(link)
		self.infoList = { { getterName = "GetHyperlink", getterArgs = { link }, tooltipData = data } }
		onItem(self, data)
		self:Show()
	end
	tip.RefreshData = function(self) self:SetHyperlink(self.infoList[1].getterArgs[1]) end

	enter(nil, ChatFrame1, "spell:1234")
	assert(not tip:IsShown(), "non-item chat links have no item preview")
	enter(nil, ChatFrame1, armor)
	assert(tip:IsShown() and compared and arrow:IsShown() and arrow.desaturated and not lines["Shift item info"],
		"chat equipment shows comparison and the level-gated upgrade arrow without opening a separate window")
	shift = true
	shiftChanged(nil, nil, "LSHIFT")
	assert(lines["Shift item info"] and compared and arrow:IsShown(), "pressing Shift updates the open chat preview")
	shift = false
	shiftChanged(nil, nil, "LSHIFT")
	assert(not lines["Shift item info"] and compared, "releasing Shift removes extras and keeps the comparison")
	ns.ItemLinkUpgradeState = function() return "worse" end
	tip:RefreshData()
	assert(lines[ns.L.ITEMS_DOWNGRADE] == RED_FONT_COLOR and arrow:IsShown()
		and arrow.rotation == math.pi and arrow.vertexColor[2] < 0.2,
		"chat previews label downgrades and show the red down arrow")
	leave(nil, ChatFrame1)
	assert(not tip:IsShown() and not compared and not arrow:IsShown(), "leaving the link closes the preview")
	enter(nil, ChatFrame1, food)
	assert(tip:IsShown() and not compared and not arrow:IsShown(), "non-equipment only shows the item tooltip")
	tip:SetOwner(UIParent)
	leave(nil, ChatFrame1)
	assert(tip:IsShown(), "chat leave does not close a tooltip taken over by another frame")
	enter(nil, ChatFrame1, armor)
	module.db.chatItemLinks = false
	module:OnOptionChanged("chatItemLinks")
	enter(nil, ChatFrame1, armor)
	assert(not tip:IsShown(), "disabling the option dismisses and prevents the hover preview")

	GameTooltip, TooltipUtil, GameTooltip_ShowCompareItem = savedTooltip, savedUtil, savedCompare
	IsShiftKeyDown, ns.itemSections, ns.ItemLinkUpgradeState = savedShift, savedSections, savedArrow
	C_TooltipInfo.GetHyperlink, C_Item.IsEquippableItem = savedGetter, savedEquippable
	GameTooltip_AddColoredLine = savedColoredLine
	module.db.shiftInfo, module.db.chatItemLinks = savedFlag, true
	print("Chat item hover, comparison and Shift OK")
end)()
-- Quest links in chat: hover preview with the quest level in the difficulty colour
;(function()
	local module = ns:GetModule("Tooltip")
	local enter, leave = uv(module.OnLogin, "OnChatItemLinkEnter"), uv(module.OnLogin, "OnChatItemLinkLeave")
	local savedTooltip, savedAdd, savedDiff = GameTooltip, GameTooltip_AddColoredLine, GetQuestDifficultyColor
	local savedGet, savedLevel, savedCalls = ns.QuestieDB.Get, UnitLevel, #TEST_POSTCALLS
	local added, color = {}, nil
	local quests = { [100] = { 12, 10 }, [200] = { 0, 15 }, [300] = { 30, 28 } }
	local tip = NewFrame("GameTooltip")
	GameTooltip = tip
	module:OnInitialize()
	for i = #TEST_POSTCALLS, savedCalls + 1, -1 do TEST_POSTCALLS[i] = nil end
	tip:Hide()
	tip.SetOwner = function(self, owner) self.owner = owner end
	tip.GetOwner = function(self) return self.owner end
	tip.GetPrimaryTooltipInfo = function(self) return self.infoList and self.infoList[1] end
	tip.Hide = function(self)
		self.shown = false
		self:GetScript("OnHide")(self)
	end
	tip.SetHyperlink = function(self, link)
		added, color = {}, nil
		self:GetScript("OnTooltipCleared")(self)
		self.infoList = { { getterName = "GetHyperlink", getterArgs = { link } } }
		self:Show()
	end
	GameTooltip_AddColoredLine = function(_, text, c) added[#added + 1], color = text, c end
	GetQuestDifficultyColor = function(level) return { difficulty = level } end
	UnitLevel = function() return 14 end
	ns.QuestieDB.Get = function()
		return { Quest = { GetAll = function(id) local q = quests[id]; return q and { q[1], q[2] } end } }
	end

	enter(nil, ChatFrame1, "quest:100:12")
	assert(tip:IsShown() and added[1] == ns.L.TOOLTIP_QUEST_LEVEL:format(12) and color.difficulty == 12,
		"quest link shows its tooltip with the level in the difficulty colour")
	enter(nil, ChatFrame1, "quest:100:12")
	assert(#added == 1, "the level line is added only once per tooltip")
	enter(nil, ChatFrame1, "quest:300:-1")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL_REQUIRED:format(30, 28) and color == RED_FONT_COLOR,
		"a quest the player cannot accept yet shows level and required level in red")
	enter(nil, ChatFrame1, "quest:200")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL_REQUIRED:format(15, 15), "without a quest level the required level is used")
	enter(nil, ChatFrame1, "quest:999:7")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL:format(7) and color.difficulty == 7, "unknown quests use the link level")
	enter(nil, ChatFrame1, "quest:998:0")
	assert(tip:IsShown() and #added == 0, "without any level the quest tooltip stays without a level line")
	leave(nil, ChatFrame1)
	assert(not tip:IsShown(), "leaving the quest link closes the preview")
	enter(nil, ChatFrame1, "quest:100:12")
	module.db.chatQuestLinks = false
	module:OnOptionChanged("chatQuestLinks")
	assert(not tip:IsShown(), "disabling the option dismisses the quest preview")
	enter(nil, ChatFrame1, "quest:100:12")
	assert(not tip:IsShown(), "disabled quest previews stay hidden")
	module.db.chatItemLinks = false
	module.db.chatQuestLinks = true
	enter(nil, ChatFrame1, "quest:100:12")
	assert(tip:IsShown(), "quest previews do not depend on the item option")

	GameTooltip, GameTooltip_AddColoredLine, GetQuestDifficultyColor = savedTooltip, savedAdd, savedDiff
	ns.QuestieDB.Get, UnitLevel = savedGet, savedLevel
	module.db.chatItemLinks, module.db.chatQuestLinks = true, true
	print("Chat quest hover with level OK")
end)()
-- Tracking menu entries
do
	local mm = ns:GetModule("Minimap")
	local add = uv(mm.OnLogin, "AddForeverPlusEntries")
	local radar = ns:GetModule("RecipeRadar")
	local created, titles, checkboxes = 0, 0, {}
	local root = { CreateDivider = function() created = created + 1 end, CreateTitle = function() titles = titles + 1 end,
		CreateCheckbox = function(_, name, isOn, set) checkboxes[#checkboxes + 1] = { name = name, isOn = isOn, set = set } end,
		CreateButton = function() return { CreateCheckbox = function() return {} end } end }
	mm.db.trackingEntries = false
	add(root); assert(#checkboxes == 0, "option off: no entries")
	mm.db.trackingEntries = true
	radar.db.enabled, radar.db.minimap = true, true
	local values = {}
	Settings.SetValue = function(var, value) values[var] = value end
	local setOption = ns.SetOption
	ns.SetOption = function(moduleName, key, value) values["ForeverPlus_" .. moduleName .. "_" .. key] = value end
	add(root)
	assert(titles == 1 and #checkboxes >= 1, "radar entry added under a title") -- the harness runs OnLogin more than once
	checkboxes = { checkboxes[#checkboxes] }
	assert(checkboxes[1].isOn() == true, "on while the radar is shown on the minimap")
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_minimap == false, "click switches the minimap pins off")
	radar.db.minimap = false
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_minimap == true, "click switches them on")
	ns.SetOption = setOption
end
-- Flight popup: destinations by price, hovered one kept when the list is cut
do
	local flight = ns:GetModule("Flight")
	local nodes = {
		{ "Hier", "CURRENT", 0 }, { "Zeta", "REACHABLE", 300 }, { "Alpha", "REACHABLE", 300 }, { "Nah", "REACHABLE", 50 },
		{ "Fern", "REACHABLE", 900 }, { "Gesperrt", "UNREACHABLE", 0 },
	}
	NumTaxiNodes = function() return #nodes end
	TaxiNodeGetType = function(i) return nodes[i][2] end
	TaxiNodeName = function(i) return nodes[i][1] end
	TaxiNodeCost = function(i) return nodes[i][3] end
	flight.db.times["Hier -> Nah"] = 95
	local destinations = uv(uv(flight.OnLogin, "ShowRoutes"), "Destinations")
	local list, hidden = destinations(4, 10)
	assert(#list == 4 and hidden == 0, "four reachable destinations")
	assert(list[1].name == "Nah" and list[1].time == 95 and list[1].hovered, "cheapest first, time known, hovered")
	assert(list[2].name == "Alpha" and list[3].name == "Zeta" and list[4].name == "Fern", "price, then name")
	list, hidden = destinations(5, 2)
	assert(#list == 2 and hidden == 2, "cut to two, two hidden")
	local kept = false
	for _, entry in ipairs(list) do kept = kept or entry.name == "Fern" end
	assert(kept, "the hovered destination stays in the cut list")
end
print("chat history OK")
-- Sliced runner and timings
do
	local sum, done = 0, false
	local savedTicker = C_Timer.NewTicker
	C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
	ns.RunSliced("Test: slices", 1000, function(i) sum = sum + i end, function() done = true end, 0.001)
	C_Timer.NewTicker = savedTicker
	assert(done and sum == 500500, "sliced run")
	assert(ns.timings["Test: slices"].count > 1, "ran in several slices")
end
local printed = {}
ns.PrintAlways = function(msg, ...) printed[#printed + 1] = select("#", ...) > 0 and msg:format(...) or msg end
ns.PrintTimings()
print("  " .. printed[1]); print("  " .. printed[2])
print("timings OK")
-- Chat copy: plain text of the last lines
local chatC = ns:GetModule("Chat")
local shown
ns.ShowEditWindow = function(_, _, text) shown = text end
local msgs = {}
for i = 1, 60 do msgs[i] = "line " .. i end
msgs[60] = "|cff1eff00|Hitem:1::|h[Leinenstoff]|h|r von |Kq12|k |TInterface\\X:0|t ok"
local frame = { GetNumMessages = function() return #msgs end, GetMessageInfo = function(_, i) return msgs[i] end }
chatC:CopyChat(frame)
local lines = {}
for l in shown:gmatch("[^\n]+") do lines[#lines + 1] = l end
print("  copy last:", lines[#lines], #lines)
assert(#lines == 50 and lines[1] == "line 11" and lines[50] == "[Leinenstoff] von ?  ok", "chat copy")
print("chat copy OK")
-- Active self buffs greyed out
local vis = ns:GetModule("Visuals")
local updateWatch = uv(vis.OnOptionChanged, "UpdateAuraWatch")
local updateAuras = uv(updateWatch, "UpdateActiveAuras")
local colorBtn = uv(uv(updateAuras, "RecolorBuffButtons"), "ColorButton")
vis.db.actionColors, vis.db.colorActiveBuff, vis.db.colorRange = true, true, true
local auras = { { name = "Siegel der Rechtschaffenheit", auraInstanceID = 11 } }
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_Spell.IsSelfBuff = function(id) return id == 20154 end
C_Spell.GetSpellName = function(id) return id == 20154 and "Siegel der Rechtschaffenheit" or "Heiliges Licht" end
GetActionInfo = function(slot) return "spell", slot == 1 and 20154 or 635 end
C_ActionBar.IsUsableAction = function() return true end
local function mkBtn(slot) local b = { action = slot, icon = { SetVertexColor = function(self, r) self.r = r end, SetDesaturated = function(self, d) self.d = d end } } return b end
local seal, light = mkBtn(1), mkBtn(2)
updateWatch()
colorBtn(seal); colorBtn(light)
assert(seal.icon.d == true and not light.icon.d, "active seal greyed")
do
	local savedAfter, queued, scheduled, scans = C_Timer.After, nil, 0, 0
	C_Timer.After = function(_, fn) queued, scheduled = fn, scheduled + 1 end
	C_UnitAuras.GetUnitAuras = function() scans = scans + 1 return auras end
	local watcher = uv(updateWatch, "auraWatcher")
	local onEvent = watcher:GetScript("OnEvent")
	onEvent(watcher, "UNIT_AURA", "player", { updatedAuraInstanceIDs = { 11 } })
	onEvent(watcher, "UNIT_AURA", "player", { addedAuras = { { isHelpful = false } }, removedAuraInstanceIDs = { 22 } })
	assert(scheduled == 0, "refreshes and harmful auras skip the scan")
	local saved = auras
	auras = {}
	onEvent(watcher, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 11 } })
	onEvent(watcher, "UNIT_AURA", "player", { isFullUpdate = true })
	assert(scheduled == 1, "helpful removal and full update share a scan")
	light.icon.r = 0.25
	queued()
	assert(scans == 1 and seal.icon.d == false and light.icon.r == 0.25, "one batch read updates the buff button only")
	C_UnitAuras.GetUnitAuras = nil
	auras, C_Timer.After = saved, savedAfter
	updateAuras()
end
do
	C_Secrets.ShouldAurasBeSecret = function() return true end
	local saved = auras
	auras = {}
	updateAuras()
	colorBtn(seal)
	assert(seal.icon.d == true, "secret keeps last set")
	C_Secrets.ShouldAurasBeSecret = function() return false end
	C_UnitAuras.GetAuraDataByIndex = function() error("secret") end
	updateAuras()
	colorBtn(seal)
	assert(seal.icon.d == true, "error keeps last set")
	C_UnitAuras.GetAuraDataByIndex = function(_, i) return auras[i] end
	auras = saved
	print("secret auras OK")
end
auras = {}
updateAuras(); colorBtn(seal)
assert(seal.icon.d == false and seal.icon.r == 1, "seal back to normal")
print("active buff OK")
-- Weapon imbues are no auras: greyed by the weapon enchant that matches the spell
;(function()
	local savedImbues, savedSlot, savedItem, savedInfo = ns.WeaponImbues, Enum.WeaponSlot, C_Item, GetActionInfo
	local savedName, savedSelf = C_Spell.GetSpellName, C_Spell.IsSelfBuff
	ns.WeaponImbues = { [283] = { kind = "wind", spellID = 8232 }, [5] = { kind = "fire", spellID = 8024 } }
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	local enchants = { [1] = { { hasEnchant = true, enchantID = 283 } }, [2] = {} }
	C_Item = setmetatable({ GetWeaponEnchantInfo = function(slot) return enchants[slot] end }, { __index = savedItem })
	C_Spell.IsSelfBuff = function() return false end
	C_Spell.GetSpellName = function(id) return "Imbue " .. id end
	GetActionInfo = function(slot) return "spell", slot == 1 and 8232 or 8024 end
	local wind, fire = mkBtn(1), mkBtn(2)
	updateAuras()
	colorBtn(wind); colorBtn(fire)
	assert(wind.icon.d == true and not fire.icon.d, "active windfury imbue greyed, fire imbue not")
	enchants[1] = {}
	updateAuras()
	colorBtn(wind)
	assert(wind.icon.d == false, "imbue back to normal once the enchant is gone")
	enchants[1] = { { hasEnchant = true, enchantID = 283 } }
	updateAuras()
	vis.db.activeBuffExceptions = { ["Imbue 8232"] = true }
	colorBtn(wind)
	assert(not wind.icon.d, "exception keeps imbue normal")
	vis.db.activeBuffExceptions = {}
	-- Poisons and oils: the weapon tooltip carries the enchant line "Name (30 min)"
	local savedTip = C_TooltipInfo.GetInventoryItem
	local tip = { lines = { { leftText = "Sofort wirkendes Gift VII (30 Min.)" } } }
	C_TooltipInfo.GetInventoryItem = function() return tip end
	enchants[1], enchants[2] = { { hasEnchant = true, enchantID = 9999 } }, {}
	C_Item.GetItemInfo = function(id) return id == 100 and "Sofort wirkendes Gift VII" or id == 101 and "Sofort wirkendes Gift" or "Anderes" end
	C_Item.GetItemSpell = function() return nil end
	GetActionInfo = function(slot) return "item", 100 + slot - 1 end
	local poison, other = mkBtn(1), mkBtn(2)
	updateAuras()
	colorBtn(poison); colorBtn(other)
	assert(poison.icon.d == true and not other.icon.d, "applied poison greyed, other item not")
	enchants[1] = {}
	updateAuras()
	colorBtn(poison)
	assert(poison.icon.d == false, "poison back to normal once the enchant is gone")
	C_TooltipInfo.GetInventoryItem = savedTip
	ns.WeaponImbues, Enum.WeaponSlot, C_Item, GetActionInfo = savedImbues, savedSlot, savedItem, savedInfo
	C_Spell.GetSpellName, C_Spell.IsSelfBuff = savedName, savedSelf
	auras = {}
	updateAuras()
	print("weapon imbue OK")
end)()
;(function()
	-- A slow call during which the Lua memory went down carries "(GC)"; fast calls and growing memory do not.
	local savedTime, savedClock, savedGC = GetTime, debugprofilestop, collectgarbage
	local now, clock, memory = 900, 0, 1000
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	collectgarbage = function(option)
		if option == "count" then
			return memory
		end
		return savedGC(option)
	end
	ns.SetMeasuring(true)
	now = 901
	ns.Measured("Test: slow with GC", function() clock, memory = clock + 8, memory - 200 end)()
	ns.Measured("Test: slow, memory grows", function() clock, memory = clock + 8, memory + 50 end)()
	ns.Measured("Test: fast with GC", function() clock, memory = clock + 1, memory - 200 end)()
	assert(ns.timings["Test: slow with GC (GC)"] and not ns.timings["Test: slow with GC"], "slow call with GC is marked")
	assert(ns.timings["Test: slow, memory grows"] and ns.timings["Test: fast with GC"], "others keep their name")
	ns.SetMeasuring(false)
	GetTime, debugprofilestop, collectgarbage = savedTime, savedClock, savedGC
	print("GC mark OK")
end)()
-- Exceptions and timed measure
vis.db.activeBuffExceptions = { ["Siegel der Rechtschaffenheit"] = true }
auras = { { name = "Siegel der Rechtschaffenheit" } }
updateAuras(); colorBtn(seal)
assert(not seal.icon.d, "exception keeps seal normal")
vis.db.activeBuffExceptions = {}
;(function()
	local timerFn
	C_Timer.NewTimer = function(_, fn) timerFn = fn return { Cancel = function() end } end
	local savedTime = GetTime
	local now = 800
	GetTime = function() return now end
	ns.timings["old"] = { max = 1, count = 1, slow = 0 }
	local info = ns:GetModule("Info")
	local savedResult = info.lastMeasure
	local perf = uv(info.UpdatePerformance, "perfFrame")
	perf:GetScript("OnMouseUp")(perf, "MiddleButton")
	assert(ns.measuring and not ns.timings.old, "measuring, old values cleared")
	local lateStart = ns.Measured("Test: measurement start", function() ns.SetMeasuring(true) end)
	lateStart()
	assert(not ns.timings["Info: performance click"] and not ns.timings["Test: measurement start"], "startup calls stay outside the results")
	local sampleFrame = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local savedMetric = C_AddOnProfiler.GetAddOnMetric
	C_AddOnProfiler.GetAddOnMetric = function() return 35 end
	sampleFrame()
	assert(ns.spikes.samples == 0, "ignore the profiler value from before the current measurement")
	now = 801
	C_AddOnProfiler.GetAddOnMetric = function() return 5 end
	sampleFrame()
	assert(ns.spikes.samples == 0, "the frame containing the click stays outside the results")
	ns.RecordTiming("X: y", 0.9)
	ns.RecordTiming("Y: x", 0.4)
	now = 802
	C_AddOnProfiler.GetAddOnMetric = function() return 35 end
	sampleFrame()
	assert(ns.spikes.samples == 1 and ns.spikes.count == 1 and ns.spikes.worst == 35 and ns.spikes.name == "X: y",
		"one slow frame can occur even when every individual call is short")
	timerFn()
	assert(info.lastMeasure.frames == ns.spikes and not ns.measuring and ns.TopTimings(5)[1].name == "X: y", "timed measure")
	local oldFrames = ns.spikes
	ns.SetMeasuring(true)
	sampleFrame()
	now = 803
	sampleFrame()
	now = 804
	C_AddOnProfiler.GetAddOnMetric = function() return 0.7 end
	sampleFrame()
	assert(ns.spikes.worst == 0.7 and ns.spikes.count == 0 and oldFrames.worst == 35,
		"the next measurement shows a peak below the threshold without overwriting the previous result")
	ns.SetMeasuring(false)
	C_AddOnProfiler.GetAddOnMetric = savedMetric
	local captured = {}
	local savedTooltip = GameTooltip
	GameTooltip = NewFrame("Tooltip")
	GameTooltip.AddLine = function(_, line) captured[line] = true end
	GameTooltip.AddDoubleLine = function(_, label, value) captured[label] = value end
	local createPerfFrame = uv(info.UpdatePerformance, "CreatePerfFrame")
	uv(createPerfFrame, "RefreshCpuTooltip")(UIParent)
	assert(captured[ns.FormatMeasuredFrames(oldFrames)] and captured["X: y"] == "0.9 ms (1)",
		"the tooltip shows the finished measurement's frame peak alongside its individual calls")
	GameTooltip = savedTooltip
	info.lastMeasure = savedResult
	GetTime = savedTime
	print("exceptions/measure OK")
end)()
-- Popup list smoke test (layout logic)
local owner = NewFrame("Button")
local built = 0
ns.ShowPopupList(owner, function()
	built = built + 1
	local list = { { text = "Abschnitt" } }
	for i = 1, 20 do list[#list + 1] = { text = "Eintrag " .. i, icon = 1, checked = i % 2 == 0, onClick = function() end } end
	return { title = "Test", items = list, footer = { { text = "Alle", onClick = function() end } } }
end)
assert(built == 1, "popup built")
print("popup OK")
;(function()
	local profiles = ns:GetModule("Profiles")
	local savedShow, savedPrint, savedSnapshot, savedAfter = ns.ShowEditWindow, ns.PrintAlways, profiles.Snapshot, ns.After
	local savedStore, savedLastAuto, savedTime, savedDate = ns.db.profiles, profiles.db.lastAuto, time, date
	local now = 1784000000
	time, date = function() return now end, os.date
	ns.db.profiles = {}
	local store = ns.db.profiles
	local editor, message
	ns.ShowEditWindow = function(_, title, initial, _, accept) editor = { title = title, initial = initial, accept = accept } end
	ns.PrintAlways = function(text) message = text end
	profiles.Snapshot = function() return { time = now, cvars = { example = "1" }, bindings = {}, layouts = {}, addon = {} } end
	local owner = NewFrame("Button")
	profiles.ShowList(owner)
	local popup = ForeverPlusPopupProfiles
	local function Click(label)
		for index, entry in ipairs(popup.build().footer) do
			if entry.text == label then
				local button = popup.footer[index]
				button:GetScript("OnClick")(button)
				return
			end
		end
		error("profile action missing: " .. label)
	end
	Click(ns.L.PROFILES_CREATE)
	assert(not popup:IsShown() and editor.title == ns.L.PROFILES_CREATE_TITLE, "create is available in an empty list")
	editor.accept("  Original  ")
	local snapshot = assert(store.Original, "create saves current settings under the trimmed name")
	assert(popup:IsShown() and popup.build().items[1].checked, "created profile is selected")
	Click(ns.L.PROFILES_CREATE)
	editor.accept("Original")
	assert(message == ns.L.PROFILES_NAME_EXISTS and store.Original == snapshot, "create cannot overwrite an existing profile")
	assert(profiles.Save("Taken"), "save a second profile for the rename conflict")
	local target = store.Taken
	Click(ns.L.PROFILES_RENAME)
	assert(editor.initial == "Original", "rename starts with the selected profile name")
	editor.accept(" Taken ")
	assert(message == ns.L.PROFILES_NAME_EXISTS and store.Original == snapshot and store.Taken == target, "rename conflict keeps both profiles")
	Click(ns.L.PROFILES_RENAME)
	editor.accept(" ")
	assert(message == ns.L.PROFILES_NAME_REQUIRED and store.Original == snapshot, "rename requires a name")
	Click(ns.L.PROFILES_RENAME)
	editor.accept("  Main  ")
	assert(not store.Original and store.Main == snapshot and snapshot.cvars.example == "1", "rename keeps the same snapshot")
	assert(popup.build().items[1].checked and popup.build().items[1].text:find("^Main "), "renamed profile stays selected")
	Click(ns.L.PROFILES_LOAD)
	Click(ns.L.PROFILES_DELETE)
	popup:Hide()

	local prefix = ns.L.PROFILES_AUTO_PREFIX
	local legacy = prefix .. date("%Y-%m-%d %H:%M", now - 86400)
	store[legacy] = { time = now - 86400 }
	local custom = prefix .. date("%Y-%m-%d %H:%M", now)
	assert(profiles.Rename(legacy, custom), "an older automatic backup can be renamed")
	local retained = store[custom]
	ns.After = function(_, _, backup) backup() end
	profiles.db.lastAuto = 0
	profiles:OnLogin()
	assert(store[custom] == retained and store[custom .. " (2)"].automatic, "the new backup uses a free name")
	for _ = 2, 4 do
		now = now + 86400
		profiles:OnLogin()
	end
	local autoCount = 0
	for _, profile in pairs(store) do
		if profile.automatic then autoCount = autoCount + 1 end
	end
	assert(store[custom] == retained and autoCount == 3, "rotation protects renamed backups and keeps three automatic copies")
	assert(profiles.Save("Main") and store.Main ~= snapshot, "direct save can still refresh an existing profile")
	ns.ShowEditWindow, ns.PrintAlways, profiles.Snapshot, ns.After = savedShow, savedPrint, savedSnapshot, savedAfter
	ns.db.profiles, profiles.db.lastAuto, time, date = savedStore, savedLastAuto, savedTime, savedDate
	print("profile management and automatic backup rotation OK")
end)()

;(function()
	local savedSettings, savedPanel, savedHook = Settings, SettingsPanel, hooksecurefunc
	local main, childCategory = NewFrame("Frame"), NewFrame("Frame")
	local tab = NewFrame("Button")
	local inits = {}
	local function Init() return { InitFrame = function() end } end
	Settings = setmetatable({
		RegisterVerticalLayoutCategory = function() return main end,
		RegisterVerticalLayoutSubcategory = function() return childCategory end,
		CreateElementInitializer = Init,
		CreateCheckbox = function(category, setting)
			local initializer = Init()
			if setting.variable then
				inits[setting.variable] = { initializer = initializer, category = category }
			end
			return initializer
		end,
		RegisterAddOnSetting = function(_, variable) return { variable = variable, SetValueChangedCallback = function() end } end,
	}, { __index = savedSettings })
	SettingsPanel = { AddOnsTab = tab, GetLayout = savedPanel.GetLayout }
	hooksecurefunc = function(object, method, hook)
		local original = object[method]
		object[method] = function(...) original(...) hook(...) end
	end
	local mover = { name = "Mover", options = {
		{ type = "button", name = "Mover 1" }, { type = "button", name = "Mover 2" }, { type = "button", name = "Mover 3" },
	} }
	local profiles = { name = "Profiles", db = {}, defaults = { auto = true }, options = ns:GetModule("Profiles").options }
	local chat = { name = "Chat", db = {}, defaults = { tabFade = true, existing = false }, options = {
		{ key = "tabFade", type = "toggle", new = true },
		{ key = "existing", type = "toggle" },
	} }
	local modules = { Mover = mover, Profiles = profiles, Chat = chat }
	local tabBadge
	local settingsNS = setmetatable({
		db = {}, modules = {},
		GetModule = function(_, name) return modules[name] end,
		CreateNewBadge = function(owner, text)
			local badge = ns.CreateNewBadge(owner, text)
			if owner == tab then tabBadge = badge end
			return badge
		end,
	}, { __index = ns })
	assert(loadfile(root .. "/Core/Settings.lua"))("ForeverPlus", settingsNS)
	settingsNS:BuildSettings()
	local auto, other = inits.ForeverPlus_Profiles_auto, inits.ForeverPlus_Chat_tabFade
	assert(auto.category == main and other.category ~= main and auto.initializer.fpNewID, "both main page and subpage options have stable IDs")
	assert(not inits.ForeverPlus_Chat_existing.initializer.fpNewID, "the initial build treats existing unmarked settings as the baseline")
	-- Simulate a row with a label tooltip and a nested control, as in the settings list.
	local row, label, control = NewFrame("Frame"), NewFrame("Frame"), NewFrame("Button")
	row.fpNewBadge = false
	row.fpNewHooked, label.fpNewHooked, control.fpNewHooked = false, false, false
	row.fpNewMouseID = false
	row.GetChildren = function() return label end
	label.GetChildren = function() return control end
	local over = true
	row.IsMouseOver = function() return over end
	local function Show(initializer)
		row.GetElementData = function() return initializer end
		initializer:InitFrame(row)
	end
	local function TwoPasses(initializer)
		Show(initializer)
		assert(row.fpNewBadge:IsShown(), "unseen row is marked NEW")
		label:GetScript("OnEnter")(label)
		label:GetScript("OnLeave")(label)
		control:GetScript("OnEnter")(control)
		assert(row.fpNewBadge:IsShown() and settingsNS.db.settingsNewSeen[initializer.fpNewID] == 1, "moving within the row counts once")
		over = false
		control:GetScript("OnLeave")(control)
		over = true
		control:GetScript("OnEnter")(control)
		assert(not row.fpNewBadge:IsShown() and settingsNS.db.settingsNewSeen[initializer.fpNewID] == 2, "second mouseover clears NEW")
		row:GetScript("OnHide")(row)
		Show(initializer)
		assert(not row.fpNewBadge:IsShown(), "dismissal survives row recycling")
	end
	TwoPasses(other.initializer)
	assert(tabBadge:IsShown(), "main page still has an unseen option")
	TwoPasses(auto.initializer)
	assert(not tabBadge:IsShown(), "dismissing the last new option clears the tab badge")
	settingsNS.db.settingsNewSeen[auto.initializer.fpNewID] = 3
	Show(auto.initializer)
	assert(not row.fpNewBadge:IsShown(), "previously dismissed rows stay dismissed")

	chat.defaults.added, chat.defaults.classOption = false, false
	chat.options[#chat.options + 1] = { key = "added", type = "toggle" }
	chat.options[#chat.options + 1] = { key = "classOption", type = "toggle", newScope = "TestClass" }
	settingsNS:BuildSettings()
	local added = inits.ForeverPlus_Chat_added.initializer
	assert(added.fpNewID and tabBadge:IsShown(), "an option added in an update is marked without an explicit new flag")
	assert(not inits.ForeverPlus_Chat_classOption.initializer.fpNewID, "a class visited for the first time starts with a baseline")
	TwoPasses(added)
	settingsNS:BuildSettings()
	Show(inits.ForeverPlus_Chat_added.initializer)
	assert(not row.fpNewBadge:IsShown() and not tabBadge:IsShown(), "automatic dismissal survives rebuilding after a reload")
	Settings, SettingsPanel, hooksecurefunc = savedSettings, savedPanel, savedHook
	print("two mouseovers dismiss NEW on main and subpages OK")
end)()

-- Loot summary popup
local lootM = ns:GetModule("Loot")
local showSummary = uv(lootM.OnLogin, "ShowSummary")
local summariesT = uv(showSummary, "summaries")
summariesT[99] = { count = 2, order = { link }, items = { [link] = { count = 2, sources = { Kobold = 2 }, order = { "Kobold" } } }, money = 50, moneySources = { Kobold = 50 }, moneyOrder = { "Kobold" }, started = 0, ended = 60 }
C_Item.GetItemIconByID = function() return 123 end
date = os.date
local popupData
ns.ShowPopupList = function(_, build) popupData = build() end
showSummary(99)
for _, it in ipairs(popupData.items) do print("  loot popup:", it.text) end
assert(#popupData.items == 4 and popupData.items[2].icon == 123 and popupData.items[2].text:find("x2"), "loot popup")
-- Destroy only when cheaper than incoming loot
local itemsD = ns:GetModule("Items")
local offer = uv(itemsD.UI_ERROR_MESSAGE, "OfferDestroy")
local incoming = uv(offer, "IncomingValue")
GetNumLootItems = function() return 1 end
GetLootSlotType = function() return Enum.LootSlotType and Enum.LootSlotType.Item or 1 end
Enum.LootSlotType = { Item = 1 }
GetLootSlotType = function() return 1 end
GetLootSlotInfo = function() return nil, nil, 2, nil, nil, nil, false end
GetLootSlotLink = function() return "x" end
C_Item.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 30 end
assert(incoming() == 60, "incoming value")
GetLootSlotInfo = function() return nil, nil, 1, nil, nil, nil, true end
assert(incoming() == math.huge, "quest item")
print("loot popup/destroy OK")
-- sell button + stack size
do
	local Items = ns:GetModule("Items")
	local kids = {}
	print("sell button created", Items.db.sellButton)
	local Tooltip = ns:GetModule("Tooltip")
	-- the item tooltip's extra block: stack size section, all under one separator
	;(function()
	local Tooltip, uv = Tooltip, uv
	local orig = C_Item.GetItemInfo
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 20 end
	local stack
	for _, section in ipairs(ns.itemSections) do
		if section.order == 10 then stack = section end
	end
	assert(stack, "stack size section registered")
	local lines = stack.fn({ id = 2589 })
	assert(lines and #lines == 1 and lines[1].left == ns.L.TOOLTIP_STACK_SIZE and lines[1].right == "20", "stack size line")
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 1 end
	assert(stack.fn({ id = 1 }) == nil, "no line for single items")
	C_Item.GetItemInfo = orig
	-- composed: one separator, then the lines of the sections in order
	local order, added = {}, {}
	for _, section in ipairs(ns.itemSections) do order[#order + 1] = section.order end
	for i = 2, #order do assert(order[i - 1] <= order[i], "sections sorted") end
	local composed = {}
	local tipFake = { IsForbidden = function() return false end, AddLine = function(_, t) composed[#composed + 1] = t end,
		AddDoubleLine = function(_, a, b) composed[#composed + 1] = a .. "=" .. tostring(b) end, Show = function() end }
	ns.itemSections[#ns.itemSections + 1] = { order = 99, fn = function() return { { left = "last" } } end }
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 20 end
	local OnItem = uv(Tooltip.OnInitialize, "OnItemTooltip")
	if OnItem then OnItem(tipFake, { id = 2589 }) end
	C_Item.GetItemInfo = orig
	table.remove(ns.itemSections)
	print("extra block:", table.concat(composed, " | "))
	end)()
	local jv = uv(uv(Items.Refresh, "CreateSellButton"), "UpdateSellButton")
	jv = uv(jv, "JunkValue")
	print("junk value with kept grey", jv())
end
do
	C_ActionBar = C_ActionBar or {}
	C_ActionBar.GetActionBarPage = function() return 1 end
	ActionBar_PageUp = function() end
	ActionBar_PageDown = function() end
	ns.StartWheelCheck()
	ActionBar_PageUp()
	print("wheel check OK")
	local vis = ns:GetModule("Visuals")
	local glow = uv(vis.OnLogin or vis.OnInitialize, "UpdateGlow")
	print("glow fn", glow ~= nil)
end
do
	local tt = ns:GetModule("Tooltip")
	local show = uv(tt.OnInitialize, "ShowTrainerCompare")
	print("trainer compare fn", show ~= nil)
	if show then
		_G.GetTrainerServiceItemLink = function() return "|cff1eff00|Hitem:3846::::|h[Stiefel]|h|r" end
		C_Item.GetItemInfoInstant = function() return 3846, "Rüstung", "Platte", "INVTYPE_FEET" end
		GetInventoryItemLink = function(_, slot) return slot == 8 and "|Hitem:1|h[Alt]|h" or nil end
		local tip = setmetatable({ IsForbidden = function() return false end, GetRight = function() return 500 end,
			GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end }, { __index = function() return function() end end })
		local ok, err = pcall(show, tip, 3)
		print("trainer compare run", ok, err)
		-- In the bubble at a nameplate the tooltip cannot be measured (error): the comparison still shows.
		tip.GetRight = function() error("Can't measure restricted regions") end
		GetCursorPosition = function() return 400, 300 end
		ok, err = pcall(show, tip, 3)
		assert(ok, "restricted tooltip: " .. tostring(err))
		print("trainer compare restricted OK")
		;(function()
			-- Critical hits pop up like the experience: small, past their size, back to exactly 1
			local ct = ns:GetModule("CombatText")
			local s0, a0 = ct.CritPop(0)
			assert(math.abs(s0 - 0.4) < 1e-9 and a0 == 0, "starts small and invisible")
			local peak = 0
			for t = 0, 0.75, 0.005 do peak = math.max(peak, (ct.CritPop(t))) end
			assert(peak > 1.6 and peak < 2, "clearly larger, like the experience: " .. peak)
			assert(ct.CritPop(0.4) == 1.6 and select(2, ct.CritPop(0.04)) > 0.9, "stays large a moment, visible at once")
			local s1, a1 = ct.CritPop(0.75)
			assert(s1 == 1 and a1 == 1, "ends at its size")
			print("crit pop OK")
		end)()
	end
end
do
	-- nearest anchor point
	local mover = ns:GetModule("Mover")
	local save = uv(uv(mover.GLOBAL_MOUSE_UP, "StopMoving"), "Save")
	local nearest = uv(save, "NearestPoint")
	local function region(l, b, w, h, es)
		return { GetLeft = function() return l end, GetRight = function() return l + w end, GetBottom = function() return b end,
			GetTop = function() return b + h end, GetCenter = function() return l + w / 2, b + h / 2 end, GetEffectiveScale = function() return es or 1 end }
	end
	local rel = region(0, 0, 1000, 600)
	local p, x, y = nearest(region(950, 560, 40, 20), rel)
	print("nearest topright", p, x, y)
	assert(p == "TOPRIGHT" and x == -10 and y == -20, "top right")
	p, x, y = nearest(region(480, 290, 40, 20), rel)
	assert(p == "CENTER" and x == 0 and y == 0, "center")
	p, x, y = nearest(region(10, 10, 40, 20, 2), region(0, 0, 1000, 600, 1))
	print("nearest scaled", p, x, y)
	-- nameplate fade
	local qol = ns:GetModule("QoL")
	local plates = { { IsForbidden = function() return false end, UnitFrame = { SetAlpha = function(self, a) self.a = a end } } }
	C_NamePlate = { GetNamePlates = function() return plates end, GetNamePlateForUnit = function() return plates[1] end }
	qol.db.nameplatesFade, qol.db.nameplatesFadeAmount = true, 70
	qol.db.nameplatesTargetFull, qol.db.nameplatesFadeCombat = true, false
	InCombatLockdown = function() return false end
	UnitExists = function() return false end -- no target
	qol:UpdateNameplates()
	print("plate alpha", plates[1].UnitFrame.a)
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "faded")
	uv(qol.UpdateNameplates, "OnCombatStart")()
	assert(plates[1].UnitFrame.a == 1, "combat full (old behaviour)")
	uv(qol.UpdateNameplates, "OnCombatEnd")()
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "faded again")
	-- new: the other units stay transparent in combat, the target never is
	qol.db.nameplatesFadeCombat = true
	uv(qol.UpdateNameplates, "OnCombatStart")()
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "others faded in combat")
	UnitExists = function() return true end -- the harness returns this plate for "target"
	uv(qol.UpdateNameplates, "FadeAllPlates")()
	assert(plates[1].UnitFrame.a == 1, "target fully visible")
	uv(qol.UpdateNameplates, "OnCombatEnd")()
	UnitExists = function() return false end
	qol.db.nameplatesFade = false
	qol:UpdateNameplates()
	assert(plates[1].UnitFrame.a == 1, "off full")
	print("new features OK")
end
do
	local items = ns:GetModule("Items")
	local scan = uv(items.Refresh, "ScanNewItems")
	print("scan fn", scan ~= nil)
	local showNext = uv(scan, "ShowNextUpgrade")
	local queue = uv(showNext, "upgradeQueue")
	items.db.upgradePopup = true
	InCombatLockdown = function() return false end
	queue[1] = { link = "|cff1eff00|Hitem:3846::::|h[Stiefel]|h|r", score = 15.8, equippedScore = 12.3, invSlot = 8 }
	C_Item.GetItemInfo = function() return "Stiefel", nil, 2, nil, nil, nil, nil, nil, nil, 133 end
	ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
	GetInventoryItemLink = function() return "|Hitem:1|h[Alt]|h" end
	local ok, err = pcall(showNext)
	assert(ok, "show upgrade: " .. tostring(err))
	queue[1] = { link = "x", score = 5, equippedScore = 0 }
	ok, err = pcall(showNext)
	assert(ok, "show upgrade empty slot: " .. tostring(err))
end
(function()
	-- Wowhead link in the right-click menus of tracker and quest log
	local quests = ns:GetModule("Quests")
	local savedMenu, savedLocale, savedEdit = Menu, GetLocale, ns.ShowEditWindow
	local modifiers, shown = {}, nil
	Menu = { ModifyMenu = function(tag, fn) modifiers[tag] = fn end }
	GetLocale = function() return "deDE" end
	ns.ShowEditWindow = function(key, _, text) shown = { key, text } end
	assert(quests.WowheadURL(783) == "https://www.wowhead.com/forever/de/quest=783", quests.WowheadURL(783))
	local function Root()
		local root = { buttons = {} }
		root.CreateDivider = function() end
		root.CreateButton = function(_, text, fn) root.buttons[#root.buttons + 1] = { text, fn } end
		return root
	end
	quests.db.wowheadLink = true
	quests.HookWowheadMenus()
	quests.hoveredQuest = 783
	local root = Root()
	modifiers.MENU_QUEST_OBJECTIVE_TRACKER(nil, root)
	assert(#root.buttons == 1 and root.buttons[1][1] == ns.L.QUESTS_WOWHEAD, "tracker entry")
	root.buttons[1][2]()
	assert(shown and shown[1] == "Wowhead" and shown[2]:find("quest=783", 1, true), "link window")
	root = Root()
	modifiers.MENU_QUEST_MAP_LOG_TITLE({ questID = 42 }, root)
	root.buttons[1][2]()
	assert(shown[2]:find("quest=42", 1, true), "quest log entry")
	root = Root()
	modifiers.MENU_QUEST_MAP_LOG_TITLE({}, root)
	assert(#root.buttons == 0, "waypoint menu without quest: no entry")
	quests.db.wowheadLink = false
	root = Root()
	modifiers.MENU_QUEST_OBJECTIVE_TRACKER(nil, root)
	assert(#root.buttons == 0, "option off")
	quests.db.wowheadLink, quests.hoveredQuest = true, nil
	Menu, GetLocale, ns.ShowEditWindow = savedMenu, savedLocale, savedEdit
	print("wowhead link OK")
end)()
;(function()
	-- unspent talent points: the currencies of the active tree, shown on the micro button
	local talents = ns:GetModule("Talents")
	local savedCT, savedTraits = C_ClassTalents, C_Traits
	C_ClassTalents = { GetActiveConfigID = function() return 7 end }
	C_Traits = { GetConfigInfo = function() return { treeIDs = { 3 } } end,
		GetTreeCurrencyInfo = function(configID, treeID) return configID == 7 and treeID == 3 and { { quantity = 2 }, { quantity = -1 } } or {} end }
	assert(talents.UnspentPoints() == 2, "unspent points " .. talents.UnspentPoints())
	PlayerSpellsMicroButton = CreateFrame("Button")
	talents.db.unspentBadge = true
	talents.UpdateUnspent()
	assert(talents.unspentBadge and talents.unspentBadge:IsShown() == true, "badge shown")
	C_Traits.GetTreeCurrencyInfo = function() return { { quantity = 0 } } end
	talents.UpdateUnspent()
	assert(talents.unspentBadge:IsShown() ~= true, "badge hidden without points")
	C_ClassTalents = { GetActiveConfigID = function() return nil end }
	assert(talents.UnspentPoints() == 0, "no tree, no points")
	C_ClassTalents, C_Traits, PlayerSpellsMicroButton = savedCT, savedTraits, nil
	print("unspent talents OK")
end)()
;(function()
	-- a sort only leaves a trace: marked junk is not moved (the game's cleanup would put it back)
	local items = ns:GetModule("Items")
	local onSort = uv(uv(items.OnLogin, "QueueSort") and items.OnLogin, "OnSortStarted")
	Enum.ItemQuality.Poor = 0
	items.db.junkPerCharacter = false
	items.db.junk = { [500] = true, [501] = true }
	local picked, savedPickup = 0, C_Container.PickupContainerItem
	C_Container.PickupContainerItem = function() picked = picked + 1 end
	local before = #items.trace
	onSort()
	C_Container.PickupContainerItem = savedPickup
	assert(picked == 0 and #items.trace == math.min(before + 1, 80), "only traced")
	assert(uv(onSort, "PlacingStep") == nil, "no placing left")
	print("junk placement OK")
end)()
;(function()
	-- real popup list with value column, quality border, stripes and sums
	C_Item.GetItemQualityColor = function() return 0, 0.44, 0.87 end
	local ok, err = pcall(realPopup, nil, function()
		return {
			title = "Beute", width = 460, striped = true,
			items = {
				{ text = "Gegenstände (2)" },
				{ text = "[Test] x1", icon = 1, quality = 3, right = "1g", onClick = function() end },
				{ text = "[Grau] x2", icon = 2, quality = 0, right = "-", onClick = function() end },
				{ text = "Geld" },
				{ text = "Quelle", right = "5s", onClick = function() end },
			},
			totals = { { "Händlerwert", "1g" }, { "Geld", "5s" }, { "Gesamt", "1g 5s", true } },
		}
	end, "TestLoot")
	assert(ok, tostring(err))
	print("loot popup OK")
end)()

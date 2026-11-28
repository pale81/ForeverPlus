(function()
	local journal = ns:GetModule("DungeonJournal")
	local matchingBosses = {}
	for _, entry in pairs(ns.DungeonJournalData.instances) do
		for _, boss in ipairs(entry.bosses) do
			local id = boss[1]
			assert(not matchingBosses[id], "each encounter ID belongs to a single instance")
			matchingBosses[id] = true
			local info = ns.DungeonJournalBosses[id]
			local point = info and info.position
			if point then
				local found = false
				for _, floor in ipairs(entry.floors or {}) do found = found or floor[1] == point[1] end
				for _, pane in ipairs(entry.minimap or {}) do found = found or pane[3][1][1] == point[1] end
				assert(found and point[2] > 0 and point[2] < 1 and point[3] > 0 and point[3] < 1, "valid boss location " .. id)
			end
		end
	end
	for id in pairs(ns.DungeonJournalBosses) do assert(matchingBosses[id], "known boss details") end

	local saved = {}
	for _, key in ipairs({ "CreateFrame", "GetCursorPosition", "GetRealZoneText", "UISpecialFrames", "GRAY_FONT_COLOR",
		"C_Spell", "GameTooltip", "MenuUtil" }) do
		saved[key] = _G[key]
	end
	local cursorX, cursorY = 280, 160
	GetCursorPosition = function() return cursorX, cursorY end
	GetRealZoneText = function() end
	UISpecialFrames = {}
	GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
	C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function() return 1 end }
	local tip, tipSpell = {}
	GameTooltip = NewFrame("Tooltip")
	GameTooltip.SetOwner = function() wipe(tip) end
	GameTooltip.AddLine = function(_, line) tip[#tip + 1] = line end
	GameTooltip.SetSpellByID = function(_, id) tipSpell = id return true end
	CreateFrame = function(kind, name, parent, template)
		local f = saved.CreateFrame(kind, name, parent, template)
		f.SetSize = function(self, w, h) self.w, self.h = w, h end
		f.SetHeight = function(self, h) self.h = h end
		f.SetScale = function(self, scale) self.testScale = scale end
		f.SetPoint = function(self, ...) self.anchor = { ... } end
		f.SetClipsChildren = function(self) self.w, self.h = 583, 323 end
		f.GetEffectiveScale = function() return 0.8 end
		f.GetCenter = function() return 350, 200 end
		f.GetParent = function() return parent end
		f.GetText = function() return "" end
		f.CreateFontString = function()
			local label = NewFrame("FontString")
			label.SetText = function(self, value) self.testText = value end
			return label
		end
		return f
	end

	journal.Open(36, 52, 0.4, 0.6)
	local panel = ForeverPlusDungeonJournal
	local view = panel.mapImage
	local pin = assert(view.bossPins[1])
	assert(view.zoom == 1 and view.pinCount > 0 and pin:IsShown(), "inner map starts fitted with boss markers")
	local firstX, firstY = pin.anchor[4], pin.anchor[5]
	pin:GetScript("OnMouseWheel")(pin, 1)
	assert(view.zoom > 1 and view.canvas.testScale == view.zoom and math.abs(view.panX) < 0.001
		and math.abs(view.panY) < 0.001, "centered map zoom")
	assert(math.abs(pin.anchor[4] - firstX * view.zoom) < 0.001 and math.abs(pin.anchor[5] - firstY * view.zoom) < 0.001,
		"boss markers follow the zoomed tiles")
	for _ = 1, 8 do view.viewport:GetScript("OnMouseWheel")(view.viewport, 1) end
	assert(view.zoom == 4, "maximum zoom")
	view.viewport:GetScript("OnDragStart")()
	cursorX, cursorY = 3000, -3000
	view.viewport:GetScript("OnUpdate")(view.viewport)
	assert(view.panX == (view.canvas:GetWidth() * 4 - view.viewport:GetWidth()) / 2 and view.panY < 0, "panning stops at map edges")
	assert(not pin:IsShown(), "pins outside the clip cannot take clicks")
	view.viewport:GetScript("OnDragStop")()
	assert(not view.viewport:GetScript("OnUpdate"), "panning does not leave a per-frame callback")
	panel.resetZoom:GetScript("OnClick")()
	assert(view.zoom == 1 and pin:IsShown(), "reset restores the map and marker")
	pin:GetScript("OnEnter")(pin)
	assert(tip[1] == "Rhahk'Zor" and table.concat(tip):find("6304", 1, true), "boss tooltip includes known abilities")
	pin:GetScript("OnClick")(pin)
	assert(panel.bossDetails:IsShown() and not panel.map:IsShown(), "marker opens the boss details")
	local spell = panel.bossDetails.spells.rows[1]
	spell:GetScript("OnEnter")(spell)
	assert(tipSpell == 6304, "ability hover asks the game for its spell tooltip")
	panel.bossDetails.mapButton:GetScript("OnClick")()
	assert(panel.map:IsShown() and not panel.bossDetails:IsShown() and view.page == 1, "boss details return to the correct map")
	panel.next:GetScript("OnClick")()
	assert(view.page == 2 and view.pinCount > 0 and view.bossPins[1].boss[1] ~= 2741, "floor changes replace the marker set")
	panel.entranceButton:GetScript("OnClick")()
	assert(view.page == 0 and view.pinCount == 0 and view.zoom == 1, "entrance map does not inherit floor markers")

	journal.Open(209)
	local group
	for index = 1, view.pinCount do
		local marker = view.bossPins[index]
		if marker.overlaps then group = marker end
	end
	assert(group and #group.overlaps == 2, "one marker can represent encounters at the same spot")
	local choices = {}
	MenuUtil = { CreateContextMenu = function(_, callback)
		callback(nil, { CreateButton = function(_, _, action) choices[#choices + 1] = action end })
	end }
	group:GetScript("OnClick")(group)
	assert(#choices == 2, "a shared marker lets the player choose either boss")
	choices[2]()
	assert(panel.bossDetails:IsShown() and panel.bossDetails.mapButton:IsShown(), "both choices retain their map link")

	journal.Open(3065)
	assert(view.pinCount == 4 and view.zoom == 1, "Forever minimap positions appear on the matching section")
	panel.tabs.bosses:GetScript("OnClick")()
	panel.entries.rows[1]:GetScript("OnClick")(panel.entries.rows[1], "LeftButton")
	assert(panel.bossDetails:IsShown() and panel.bossDetails.title.testText == "Faldrim Anvilmar", "boss list opens the same view")

	-- Boss loot: shipped records by the English name, own loot windows by the German name.
	local loot = ns:GetModule("LootSources")
	local savedSources, savedNames, savedCount = ns.db.lootSources, ns.db.lootNames, loot.count
	local savedItem, savedColors, savedClick = C_Item, ITEM_QUALITY_COLORS, HandleModifiedItemClick
	local savedState, items = ns.ItemLinkUpgradeState, ns:GetModule("Items")
	ns.ItemLinkUpgradeState = function() return false end
	ns.db.lootSources, ns.db.lootNames, loot.count = {}, {}, 0
	loot.Record("Creature-0-1-2-3-990001-0", "npc:990001", { 777001, 777001 }, "Rotkralle")
	local loads, linked, tipItem = {}, nil, nil
	C_Item = setmetatable({
		GetItemInfo = function(id) if id == 777001 then return "Testklinge", "|Hitem:777001|h[Testklinge]|h", 2 end end,
		GetItemIconByID = function() return 135 end,
		RequestLoadItemDataByID = function(id) loads[id] = (loads[id] or 0) + 1 end,
	}, { __index = savedItem })
	ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
	HandleModifiedItemClick = function(link) linked = link end
	GameTooltip.SetItemByID = function(_, id) tipItem = id end

	local rethilgore = { 2748, "Rethilgore", "Rotkralle" }
	local rows = journal.BossLoot(rethilgore)
	local own, shipped = false, 0
	for index, row in ipairs(rows) do
		if row.id == 777001 then own = row else shipped = shipped + 1 end
		assert(row.windows > 0 and (index == 1 or rows[index - 1].drops / rows[index - 1].windows >= row.drops / row.windows),
			"loot sorted by share")
	end
	assert(own and own.drops == 1 and shipped > 0, "own window under the German name joins the shipped records")
	assert(#journal.BossLoot({ 1, "Nobody", "Niemand" }) == 0, "unknown boss has no loot")
	local savedEncounters = ns.LootData.encounters
	ns.LootData.encounters = { [2748] = { 4, { { 777001, 3 }, { 777002, 1 } } } }
	local rolled = journal.BossLoot(rethilgore)
	assert(rolled[1].id == 777001 and rolled[1].drops == 3 and rolled[1].windows == 4, "encounter rolls count per kill")
	local seen = {}
	for _, row in ipairs(rolled) do
		assert(not seen[row.id], "an item from the rolls is not listed again from corpses")
		seen[row.id] = true
	end
	assert(seen[777002] and #rolled > 2, "rolls and corpse records together")
	ns.LootData.encounters = savedEncounters
	local encounterRows = 0
	for id, entry in pairs(savedEncounters) do
		assert(type(id) == "number" and entry[1] > 0 and #entry[2] > 0, "shipped encounter loot is well formed")
		encounterRows = encounterRows + 1
	end
	assert(encounterRows > 0, "encounter loot is shipped")

	journal.Open(36)
	panel.tabs.loot:GetScript("OnClick")()
	local first = panel.entries.rows[1]
	assert(panel.entries:IsShown() and first:IsShown() and first.item and not panel.empty:IsShown(), "loot tab lists Deadmines items")
	assert(next(loads), "unknown item names are requested")
	first:GetScript("OnEnter")(first)
	assert(tipItem == first.item.id, "item rows show the item tooltip")
	journal.Open(33)
	panel.tabs.bosses:GetScript("OnClick")()
	panel.entries.rows[1]:GetScript("OnClick")(panel.entries.rows[1], "LeftButton")
	assert(panel.bossDetails.lootButton:IsShown(), "boss details offer the loot button")
	panel.bossDetails.lootButton:GetScript("OnClick")()
	local bossName = GetLocale() == "deDE" and rethilgore[3] or rethilgore[2]
	assert(panel.listTitle.testText:find(bossName, 1, true), "loot button filters to the selected boss")
	local ownRow
	for _, row in ipairs(panel.entries.rows) do if row:IsShown() and row.item.id == 777001 then ownRow = row end end
	assert(ownRow and ownRow.text.testText == "Testklinge", "own item appears with its name")
	ownRow:GetScript("OnClick")(ownRow, "LeftButton")
	assert(linked == "|Hitem:777001|h[Testklinge]|h", "clicks pass the item link to the game")

	-- Comparison arrows and the upgrade-only filter use the bag ratings.
	local state = true
	ns.ItemLinkUpgradeState = function(link) return link:find("777001", 1, true) and state or false end
	panel.tabs.loot:GetScript("OnClick")()
	assert(panel.upgradesOnly:IsShown(), "the loot tab offers the upgrade filter")
	local function ShownItems()
		local list = {}
		for _, row in ipairs(panel.entries.rows) do
			if row:IsShown() then list[#list + 1] = row end
		end
		return list
	end
	local arrows, plain = 0, 0
	for _, row in ipairs(ShownItems()) do
		if row.item.id == 777001 then
			assert(row.upgrade and row.upgrade:IsShown(), "upgrade row has the green arrow")
			arrows = arrows + 1
		elseif not (row.upgrade and row.upgrade:IsShown()) then
			plain = plain + 1
		end
	end
	assert(arrows == 1 and plain > 0, "only the rated item gets an arrow")
	state = "worse"
	panel.tabs.loot:GetScript("OnClick")()
	for _, row in ipairs(ShownItems()) do
		if row.item.id == 777001 then
			assert(row.upgrade:IsShown() and row.upgrade.rotation == math.pi, "worse loot has a down arrow")
		end
	end
	panel.upgradesOnly.GetChecked = function() return true end
	panel.upgradesOnly:GetScript("OnClick")(panel.upgradesOnly)
	assert(#ShownItems() == 0 and panel.empty:IsShown() and panel.empty.testText == ns.L.JOURNAL_NO_UPGRADES,
		"the upgrade filter excludes worse gear")
	state = true
	panel.tabs.loot:GetScript("OnClick")()
	local filtered = ShownItems()
	assert(journal.db.lootUpgradesOnly and #filtered == 1 and filtered[1].item.id == 777001, "filter keeps only upgrades")
	panel.tabs.bosses:GetScript("OnClick")()
	assert(not panel.upgradesOnly:IsShown(), "the filter belongs to the loot tab")
	items.db.upgradeArrow = false
	panel.tabs.loot:GetScript("OnClick")()
	assert(not panel.upgradesOnly:IsShown() and #ShownItems() > 0, "without upgrade arrows the filter is off")
	items.db.upgradeArrow = true
	panel.upgradesOnly.GetChecked = function() return false end
	panel.upgradesOnly:GetScript("OnClick")(panel.upgradesOnly)
	panel.tabs.bosses:GetScript("OnClick")()
	panel.entries.rows[1]:GetScript("OnClick")(panel.entries.rows[1], "LeftButton")
	panel.bossDetails.lootButton:GetScript("OnClick")()
	journal.db.bossLoot = false
	journal:OnOptionChanged()
	assert(not panel.tabs.loot:IsShown() and panel.bossDetails:IsShown() and not panel.bossDetails.lootButton:IsShown(),
		"turning off boss loot returns to the boss")
	journal.db.bossLoot = true
	panel:GetScript("OnHide")()
	C_Item, ITEM_QUALITY_COLORS, HandleModifiedItemClick = savedItem, savedColors, savedClick
	ns.ItemLinkUpgradeState = savedState
	ns.db.lootSources, ns.db.lootNames, loot.count, loot.merged = savedSources, savedNames, savedCount, nil

	journal.db.bossDetails = false
	journal:OnOptionChanged()
	assert(panel.entries:IsShown() and not panel.bossDetails:IsShown(), "turning off boss details restores the list")
	panel.tabs.map:GetScript("OnClick")()
	assert(view.pinCount == 0, "turning off boss details removes map markers")
	journal.db.mapZoom = false
	journal:OnOptionChanged()
	view.viewport:GetScript("OnMouseWheel")(view.viewport, 1)
	assert(view.zoom == 1 and not panel.resetZoom:IsShown(), "turning off zoom also removes the reset action")

	panel:GetScript("OnHide")()
	panel:Hide()
	journal.db.mapZoom, journal.db.bossDetails = true, true
	for key, value in pairs(saved) do _G[key] = value end
	print("dungeon journal map and boss details OK")
end)()
;(function()
	local L = ns.L
	local sim = ns:GetModule("DPSSim")
	local armor = sim.cdb.armor
	local mainID, enchant, extraEnchant, aura, speed, damage, inCombat = 7717, 29, nil, 6673, 2, 120, false
	local unreadableSpell = false
	local fakeSlots = { MainHand = 0, OffHand = 1, Ranged = 2 }
	local old = {}
	local function MockGlobals(fields)
		for key, value in pairs(fields) do
			old[key] = { rawget(_G, key) }
			_G[key] = value
		end
	end
	local function RecordText(self, text) self.testText = text end
	local createFrame = CreateFrame
	MockGlobals({
		InCombatLockdown = function() return inCombat end,
		GetInventoryItemID = function(_, slot) return slot == INVSLOT_MAINHAND and mainID or nil end,
		GetInventoryItemLink = function(_, slot)
			if slot == INVSLOT_MAINHAND then return "|Hitem:" .. mainID .. ":0|h[Test weapon]|h" end
		end,
		UnitDamage = function() return damage - 10, damage + 10, 0, 0, 0, 0, 1 end,
		UnitAttackSpeed = function() return speed end,
		GetCritChance = function() return 10 end,
		GetMeleeHaste = function() return 25 end,
		GetSpellBonusDamage = function() return 50 end,
		GetSpellCritChance = function() return 20 end,
		C_ClassTalents = { GetActiveConfigID = function() return nil end },
		C_UnitAuras = { GetUnitAuras = function() return { { spellId = aura, applications = 0 } } end },
		C_Item = {
			GetItemInfoInstant = function()
				return mainID, nil, nil, "INVTYPE_2HWEAPON", nil, Enum.ItemClass.Weapon, 1
			end,
			GetItemNameByID = function() return "Test weapon" end,
			GetWeaponEnchantInfo = function(slot)
				assert(slot == fakeSlots.MainHand)
				return {
					{ hasEnchant = enchant ~= nil, enchantID = enchant },
					{ hasEnchant = extraEnchant ~= nil, enchantID = extraEnchant },
				}
			end,
		},
		C_Spell = {
			GetSpellName = function(id) return "Imbue " .. id end,
			GetSpellDescription = function(id)
				if unreadableSpell then return nil end
				if GetLocale() == "deDE" then
					return ({
						[8024] = "Jeder Treffer fügt 5 bis 20 zusätzlichen Feuerschaden zu. Hält 60 Minuten lang an.",
						[8033] = "Eine Chance, zusätzlich 32 Frostschaden zu verursachen und die Bewegung um 25% zu verlangsamen.",
						[8232] = "Eine Chance von 20%, dass Ihr 2 zusätzliche Angriffe mit 46 zusätzlicher Nahkampfangriffskraft erhaltet.",
					})[id]
				end
				return ({
					[8024] = "Each hit causes 5 to 20 additional Fire damage. Lasts for 60 minutes.",
					[8033] = "A chance of causing 32 additional Frost damage and slowing movement speed by 25%.",
					[8232] = "A 20% chance of granting you 2 extra attacks with 46 extra melee attack power.",
				})[id]
			end,
		},
		CreateFrame = function(kind, name, ...)
			local frame = createFrame(kind, name, ...)
			frame.SetText = RecordText
			frame.SetEnabled = function(self, on) self.enabled = on end
			frame.CreateFontString = function()
				local label = NewFrame("FontString")
				label.SetText = RecordText
				return label
			end
			return frame
		end,
	})
	local originalSlots = rawget(Enum, "WeaponSlot")
	Enum.WeaponSlot = fakeSlots
	SlashCmdList.FOREVERPLUS("dps")
	local panel = ForeverPlusDPSSimWindow
	local function Click(button) button:GetScript("OnClick")(button) end
	assert(panel:IsShown() and panel.current.testText == L.DPSSIM_RESULT:format(46.20, 0),
		"Rockbiter is present in the live weapon damage and must not be applied a second time")
	Click(panel.save)
	local reference = sim.cdb.baseline
	assert(reference.imbue == 29 and panel.baseline.testText == L.DPSSIM_BASELINE:format(46.20), "save the current run")
	enchant, damage = 5, 100
	Click(panel.run)
	assert(panel.currentSetup.testText:find("8024", 1, true), "loaded enchant identifies the spell rank")
	assert(panel.current.testText == L.DPSSIM_RESULT:format(48.125, 9.625) and panel.delta.testText:find("+4.2%%"),
		"Flametongue accounts for unhasted weapon speed, spell damage and crit")
	assert(sim.cdb.baseline == reference and panel.note.testText == "", "repeat preserves the same reference and other inputs")
	Click(panel.armor) -- 45% for both runs
	assert(panel.baseline.testText == L.DPSSIM_BASELINE:format(36.30)
		and panel.current.testText == L.DPSSIM_RESULT:format(39.875, 9.625), "armor affects both runs and only physical damage")
	enchant = 2
	Click(panel.run)
	assert(panel.current.testText == L.DPSSIM_RESULT:format(30.25 + 37 * 1.1 * 0.375 / 2, 37 * 1.1 * 0.375 / 2)
		and panel.currentSetup.testText:find(L.DPSSIM_FROST_APPROX, 1, true), "Frostbrand is a chance per swing and labeled as an estimate")
	enchant, speed, aura = 283, 1, 1719
	Click(panel.run)
	assert(panel.current.testText == L.DPSSIM_RESULT:format(81.49, 20.99),
		"Windfury adds two attacks with bonus AP and cannot proc on the next one-second swing")
	assert(panel.note.testText == L.DPSSIM_CONTEXT_CHANGED, "notify when another buff also changed")
	extraEnchant = 9999
	Click(panel.run)
	assert(panel.delta.testText == "" and panel.note.testText == L.DPSSIM_UNSUPPORTED_CHANGED,
		"unmodeled changes do not produce a misleading comparison")
	unreadableSpell = true
	Click(panel.run)
	assert(panel.currentSetup.testText == L.DPSSIM_SPELL_UNAVAILABLE and not panel.save.enabled)
	inCombat = true
	Click(panel.run)
	assert(panel.currentSetup.testText == L.DPSSIM_COMBAT and panel.delta.testText == "" and not panel.save.enabled,
		"combat errors clear the transient result without discarding the saved run")
	assert(sim.cdb.baseline == reference)
	Click(panel.clear)
	assert(not sim.cdb.baseline and panel.baseline.testText == L.DPSSIM_NO_BASELINE)
	sim.cdb.armor = armor
	Enum.WeaponSlot = originalSlots
	for key, value in pairs(old) do _G[key] = value[1] end
	print("DPS simulator results and comparison OK")
end)()
;(function()
	local module = ns:GetModule("Tooltip")
	local itemLinkOf = uv(uv(module.OnInitialize, "UpdateCompareArrows"), "ItemLinkOf")
	local link = "item:1234:0:0:0"
	local function tip(extra)
		local t = { IsForbidden = function() return false end, IsShown = function() return true end }
		for key, value in pairs(extra) do t[key] = value end
		return t
	end
	assert(itemLinkOf(tip({ GetItem = function() return "Hose", link end })) == link, "link from GetItem")
	assert(itemLinkOf(tip({ GetTooltipData = function() return { hyperlink = link } end })) == link, "link from tooltip data without GetItem")
	local savedGuid = C_Item.GetItemLinkByGUID
	C_Item.GetItemLinkByGUID = function(guid) return guid == "Item-1" and link or nil end
	assert(itemLinkOf(tip({ GetTooltipData = function() return { guid = "Item-1" } end })) == link, "worn item by GUID")
	C_Item.GetItemLinkByGUID = savedGuid
	assert(itemLinkOf(tip({})) == nil, "no link source: no error")
	-- Comparison tooltips that reveal nothing: worn items come from the slots, in order
	local update = uv(module.OnInitialize, "UpdateCompareArrows")
	local savedWinner, savedSlots, savedWorn, savedInfo = ns.CompareWinner, ns.EquipSlots, GetInventoryItemLink, C_Item.GetItemInfoInstant
	local savedState = ns.ItemLinkUpgradeState
	local seen
	ns.CompareWinner = function(_, worn) seen = worn return "worn", 2 end
	ns.ItemLinkUpgradeState = function() return "worse" end
	ns.EquipSlots = function() return { 11, 12 } end
	GetInventoryItemLink = function(_, slot) return "item:" .. slot .. ":0:0:0" end
	C_Item.GetItemInfoInstant = function() return 1, nil, nil, "INVTYPE_FINGER" end
	local function shopping(extra)
		local shown = tip(extra or {})
		shown.CreateTexture = function(self)
			self.arrow = NewFrame("Texture")
			return self.arrow
		end
		shown.GetLeftLine = function() return { GetStringWidth = function() return 10 end } end
		shown.GetWidth = function() return 200 end
		return shown
	end
	local first, second = shopping(), shopping()
	local main = shopping({ GetItem = function() return "Ring", link end, shoppingTooltips = { first, second } })
	update({ tooltip = main })
	assert(seen and seen[1] == "item:11:0:0:0" and seen[2] == "item:12:0:0:0", "worn items by slot order")
	assert(main.arrow:IsShown() and main.arrow.rotation == math.pi and main.arrow.vertexColor[2] < 0.2
		and second.arrow:IsShown() and second.arrow.rotation == 0,
		"the hovered item shows a red down arrow beside the better worn item's green up arrow")
	ns.CompareWinner = function() return "hovered", true end
	update({ tooltip = main })
	assert(not second.arrow:IsShown() and main.arrow:IsShown() and main.arrow.rotation == 0
		and main.arrow.vertexColor[2] == 1, "the hovered tooltip restores the green up arrow for better gear")
	ns.ItemLinkUpgradeState = savedState
	ns.CompareWinner, ns.EquipSlots, GetInventoryItemLink, C_Item.GetItemInfoInstant = savedWinner, savedSlots, savedWorn, savedInfo
	print("compare tooltip without GetItem OK")
end)()
;(function()
	-- Narrow comparison tooltips are widened via right padding so the arrow fits inside top-right;
	-- repeated updates stay idempotent, existing padding is preserved, and Clear/Show keep it consistent.
	local module = ns:GetModule("Tooltip")
	local update = uv(module.OnInitialize, "UpdateCompareArrows")
	local hide = uv(module.OnInitialize, "HideCompareArrows")
	local layout = uv(uv(update, "ShowCompareArrow"), "LayoutCompareArrow")
	local savedWinner, savedState = ns.CompareWinner, ns.ItemLinkUpgradeState
	local savedSecret = issecretvalue
	local link, wornLink = "item:2234:0:0:0", "item:2235:0:0:0"
	local function makeTip(baseWidth, titleWidth, initPad)
		local pad = { initPad and initPad[1] or 0, initPad and initPad[2] or 0,
			initPad and initPad[3] or 0, initPad and initPad[4] or 0 }
		local tip = {
			baseWidth = baseWidth, titleWidth = titleWidth, pad = pad,
			setCalls = 0, clearCalls = 0,
			IsForbidden = function() return false end,
			IsShown = function() return true end,
			CreateTexture = function(self)
				local tex = NewFrame("Texture")
				tex.points = {}
				tex.ClearAllPoints = function(t) t.points = {} end
				tex.SetPoint = function(t, ...) t.points[#t.points + 1] = { ... } end
				self.arrow = tex
				return tex
			end,
			GetLeftLine = function(self) return { GetStringWidth = function() return self.titleWidth end } end,
			GetWidth = function(self) return self.baseWidth + self.pad[1] end,
			GetPadding = function(self) return self.pad[1], self.pad[2], self.pad[3], self.pad[4] end,
			SetPadding = function(self, r, b, l, t)
				self.setCalls = self.setCalls + 1
				self.pad[1], self.pad[2], self.pad[3], self.pad[4] = r or 0, b or 0, l or 0, t or 0
			end,
			ClearPadding = function(self)
				self.clearCalls = self.clearCalls + 1
				self.pad[1], self.pad[2], self.pad[3], self.pad[4] = 0, 0, 0, 0
			end,
		}
		return tip
	end
	local worn = makeTip(200, 180)
	worn.GetItem = function() return "Schimmernder Umhang des Affen", wornLink end
	local main = makeTip(280, 120)
	main.GetItem = function() return "Volksmiliz-Umhang", link end
	main.shoppingTooltips = { worn }
	ns.CompareWinner = function() return "worn", 1 end
	ns.ItemLinkUpgradeState = function() return "worse" end
	update({ tooltip = main })
	-- neededWidth = 10 + 180 + 6 + 22 + 6 = 224 -> +24 right padding on narrow worn tooltip
	assert(worn.pad[1] == 24 and worn:GetWidth() == 224 and worn.setCalls == 1, "narrow worn tooltip widened by exact deficit")
	assert(worn.arrow.points[1][1] == "TOPRIGHT" and worn.arrow.points[1][3] == "TOPRIGHT", "arrow sits inside top-right corner")
	assert(main.pad[1] == 0 and main.setCalls == 0 and main.arrow.points[1][1] == "TOPRIGHT", "already wide tooltip gets no extra padding")
	-- Repeated RefreshItems ticks on the same hovered item must be idempotent (no padding drift or churn).
	update({ tooltip = main })
	assert(worn.pad[1] == 24 and worn.setCalls == 1 and worn.clearCalls == 0, "repeated refresh does not add or thrash padding")
	-- Hiding clears our added padding cleanly via ClearPadding.
	hide()
	assert(worn.pad[1] == 0 and worn.clearCalls == 1, "hide resets added padding")
	-- Pre-existing Blizzard padding (e.g. ItemRef CloseButton right=16, bottom=12) is preserved on widen and restore.
	local ref = makeTip(200, 180, { 16, 12, 0, 0 })
	ref.GetItem = function() return "Langer Gegenstandsname", link end
	ref.shoppingTooltips = { worn }
	ns.CompareWinner = function() return "hovered", true end
	update({ tooltip = ref })
	-- baseWidth = 216, neededWidth = 224 -> +8 on top of existing 16 => right=24, bottom=12 preserved
	assert(ref.pad[1] == 24 and ref.pad[2] == 12 and ref.arrow.points[1][1] == "TOPRIGHT", "widens on top of existing padding")
	hide()
	assert(ref.pad[1] == 16 and ref.pad[2] == 12 and ref.clearCalls == 0, "restore preserves existing right and bottom padding")
	-- GameTooltip:Show post-layout: if GameTooltip_CalculatePadding wiped padding while still narrow, re-apply;
	-- if post-calls widened GameTooltip enough, drop our extra padding.
	local narrowMain = makeTip(200, 180)
	narrowMain.GetItem = function() return "Langer Umhang", link end
	narrowMain.shoppingTooltips = { worn }
	update({ tooltip = narrowMain })
	assert(narrowMain.pad[1] == 24)
	narrowMain:ClearPadding()
	layout(narrowMain)
	assert(narrowMain.pad[1] == 24, "re-applies padding after Blizzard OnShow ClearPadding")
	narrowMain.baseWidth = 300
	layout(narrowMain)
	assert(narrowMain.pad[1] == 0, "drops extra padding once post-call lines widen the tooltip")
	hide()
	-- Secret padding values or tooltips without SetPadding fall back safely to the top edge without error.
	local noPad = makeTip(200, 180)
	noPad.SetPadding = nil
	noPad.GetItem = function() return "Ohne Padding", wornLink end
	main.shoppingTooltips = { noPad }
	ns.CompareWinner = function() return "worn", 1 end
	update({ tooltip = main })
	assert(noPad.arrow.points[1][1] == "BOTTOMRIGHT" and noPad.arrow.points[1][3] == "TOPRIGHT",
		"fallback to top edge when SetPadding is unavailable")
	local secretTag = 999999
	issecretvalue = function(v) return v == secretTag end
	local secretTip = makeTip(200, 180, { secretTag, 0, 0, 0 })
	secretTip.GetWidth = function() return 200 end
	secretTip.GetItem = function() return "Geheimer Tooltip", wornLink end
	main.shoppingTooltips = { secretTip }
	update({ tooltip = main })
	assert(secretTip.setCalls == 0 and secretTip.arrow.points[1][1] == "BOTTOMRIGHT",
		"secret padding is never touched and falls back to top edge")
	hide()
	issecretvalue = savedSecret
	ns.CompareWinner, ns.ItemLinkUpgradeState = savedWinner, savedState
	print("compare tooltip widening OK")
end)()
;(function()
	-- Quest starters must be offered alongside containers, and disappear once accepted.
	local H, R, D = ns:GetModule("Helpers"), ns:GetModule("Readable"), ns:GetModule("Dialog")
	local savedLocked = LOCKED
	LOCKED = "Locked"
	local savedContainer, savedTooltip, savedLog = C_Container, C_TooltipInfo, C_QuestLog
	local savedCombat, savedNpc, savedID = InCombatLockdown, UnitExists, GetQuestID
	local savedPVP, savedAuto = QuestFlagsPVP, QuestGetAutoAccept
	local savedDetail, savedAccept, savedClose = D.DetailView, AcceptQuest, CloseQuest
	local savedEnabled, savedDialog = R.db.enabled, D.db.enabled
	local savedAfter = C_Timer.After
	local savedQuestFrame = QuestFrame
	QuestFrame = NewFrame("Frame")
	local active, complete, combat, npc, pvp = false, false, false, false, false
	local bagItems = { { itemID = 10, hasLoot = true }, { itemID = 20 }, { itemID = 30, hasLoot = true } }
	C_Container = {
		GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end,
		GetContainerItemInfo = function(_, slot) return bagItems[slot] end,
		GetContainerItemQuestInfo = function(_, slot)
			return { questID = slot == 2 and 123 or nil, isActive = active, isQuestItem = slot == 2 }
		end,
	}
	local locked = true
	C_TooltipInfo = { GetBagItem = function(_, slot)
		return { lines = locked and slot == 1 and { { leftText = LOCKED } } or {} }
	end }
	C_QuestLog = { IsOnQuest = function() return active end, IsQuestFlaggedCompleted = function() return complete end }
	InCombatLockdown = function() return combat end
	UnitExists = function() return npc end
	GetQuestID = function() return 123 end
	QuestFlagsPVP = function() return pvp end
	QuestGetAutoAccept = function() return false end
	local find = uv(uv(H.Update, "UpdateOpenButton"), "FindLootable")
	local bag, slot = find()
	assert(bag == 0 and slot == 2, "quest starter appears even though it has no loot")
	active = true
	assert(select(2, find()) == 3, "accepted quest starter skipped")
	active, complete = false, true
	assert(select(2, find()) == 3, "completed quest starter skipped")
	complete = false
	bagItems[2].isLocked = true
	assert(select(2, find()) == 3, "locked slot skipped")
	bagItems[2].isLocked, locked = false, false
	assert(select(2, find()) == 1, "existing loot containers remain available")
	R.db.enabled, D.db.enabled = true, false
	assert(R.CanShowQuest(20) and R.CanShowQuest(), "event item or matching bag quest identifies the offer")
	npc = true
	assert(not R.CanShowQuest() and R.CanShowQuest(20), "NPC quests stay with the dialog, explicit item payload wins")
	npc, pvp = false, true
	assert(not R.CanShowQuest(20), "PvP confirmation stays with Blizzard")
	pvp, combat = false, true
	assert(not R.CanShowQuest(20), "no custom quest opening in combat")
	combat = false
	local accepted, closed = 0, 0
	AcceptQuest = function() accepted = accepted + 1 end
	CloseQuest = function() closed = closed + 1 end
	D.DetailView = function() return {
		blocks = { { title = "A dropped letter" }, { text = "Read this letter." }, { text = "Find the sender." },
			{ header = "Reward", items = { { name = "Ring", count = 2 } } }, { money = "100 XP" } },
		buttons = { { text = "Accept", action = function() AcceptQuest() end },
			{ text = "Decline", action = function() CloseQuest() end } },
	} end
	C_Timer.After = function() end
	local scale = 0.8
	local savedScale, savedGetScale = QuestFrame.SetScale, QuestFrame.GetScale
	QuestFrame.SetScale = function(_, value) scale = value end
	QuestFrame.GetScale = function() return scale end
	assert(R.ShowQuest(nil, "QUEST_DETAIL", 20) and R.HasQuest(), "item quest book works with dialog disabled")
	assert(scale == 0.001 and QuestFrame.alpha == 0, "quest window carries the offer while collapsed")
	local book = ForeverPlusReadable
	assert(book.look == "BOOK" and not book.Prev:IsShown() and not book.Next:IsShown(), "quest is a two-page book without item paging")
	local pages = R.QuestPages(D.DetailView())
	assert(pages[1].text == "Read this letter." and pages[2].text:find("Find the sender.", 1, true)
		and pages[2].text:find("Ring × 2", 1, true) and pages[2].text:find("100 XP", 1, true), "text, objectives and rewards retained")
	book.QuestButtons[1]:GetScript("OnClick")()
	assert(accepted == 1, "accept action reaches the quest API")
	book.QuestButtons[2]:GetScript("OnClick")()
	R.Close()
	assert(closed == 2, "decline and close reach the quest API")
	-- Both modules may receive QUEST_DETAIL, in either order.
	D.db.enabled = true
	D:OnConversation("QUEST_DETAIL", 20)
	assert(R.HasQuest() and scale == 0.001, "dialog event delegates to the book")
	R.ShowQuest(nil, "QUEST_DETAIL", 20)
	R.Hide()
	assert(scale == 0.8 and QuestFrame.alpha == 1 and not R.HasQuest(), "closing restores the original quest window scale")
	local listeners = uv(ns.RegisterEvent, "listeners")
	for _, dialogFirst in ipairs({ true, false }) do
		local function bookEvent() listeners.QUEST_DETAIL[R](R, "QUEST_DETAIL", 20) end
		if dialogFirst then D:OnConversation("QUEST_DETAIL", 20); bookEvent()
		else bookEvent(); D:OnConversation("QUEST_DETAIL", 20) end
		assert(R.HasQuest() and scale == 0.001, "both event orders keep the book and collapsed quest window")
		listeners.QUEST_ITEM_UPDATE[R](R, "QUEST_ITEM_UPDATE")
		assert(R.HasQuest() and scale == 0.001, "reward data updates keep the quest book")
		listeners.QUEST_FINISHED[R](R, "QUEST_FINISHED")
		assert(not R.HasQuest() and scale == 0.8, "quest finish releases the window")
	end
	R.db.enabled = false
	assert(not R.ShowQuest(nil, "QUEST_DETAIL", 20), "existing readable setting disables item quest books")
	QuestFrame.SetScale, QuestFrame.GetScale = savedScale, savedGetScale
	QuestFrame = savedQuestFrame
	C_Container, C_TooltipInfo, C_QuestLog = savedContainer, savedTooltip, savedLog
	InCombatLockdown, UnitExists, GetQuestID = savedCombat, savedNpc, savedID
	QuestFlagsPVP, QuestGetAutoAccept = savedPVP, savedAuto
	D.DetailView, AcceptQuest, CloseQuest = savedDetail, savedAccept, savedClose
	R.db.enabled, D.db.enabled, C_Timer.After = savedEnabled, savedDialog, savedAfter
	LOCKED = savedLocked
	print("quest starter open button and book OK")
end)()
;(function()
	-- Cinematic camera: over the shoulder at the player's own distance, a few situations with their own distance,
	-- each after it has held a moment, every move glides; the zoom never drifts; switched off, everything comes back.
	local camera = ns:GetModule("Camera")
	local db = { taxi = true, teleport = true, talk = true, combat = true, mounted = true, indoors = true,
		resting = true, close = false }
	assert(camera.Pick({}, db).key == "outdoors", "nothing going on: over the shoulder at the own distance")
	assert(camera.Pick({ talk = true, combat = true }, db).key == "talk", "talk before combat")
	assert(camera.Pick({ taxi = true, teleport = true }, db).key == "taxi", "flight path first")
	assert(camera.Pick({ teleport = true, talk = true }, db).key == "teleport", "teleport before talk")
	assert(camera.Pick({ close = true }, db).key == "outdoors", "close is off unless chosen")
	db.talk = false
	assert(camera.Pick({ talk = true }, db).key == "outdoors", "switched-off situation skipped")
	local situations = {}
	for _, situation in ipairs(camera.SITUATIONS) do situations[situation.key] = situation end
	local indoors, talk, outdoors = situations.indoors, situations.talk, situations.outdoors
	assert(camera.ZoomFor(outdoors, true, true) == nil and camera.ZoomFor(talk, true, true) == 7, "own and fixed")
	assert(camera.ZoomFor(indoors, true, false) == 5.5, "without the option moving does not count")
	assert(math.abs(camera.ZoomFor(indoors, false, true) - 4.9) < 1e-9 and camera.ZoomFor(indoors, true, true) == 6.4,
		"with the option: closer standing still, further while moving")
	assert(camera.ShotKey(indoors, true, false) == "indoors" and camera.ShotKey(indoors, true, true) == "indoors:moving",
		"moving only counts with the option")
	assert(camera.ShotKey(outdoors, true, true) == "outdoors" and camera.ShotKey(nil, true, true) == "", "shot keys")
	assert(camera.IsTeleport(8690) and camera.IsTeleport(3561) and not camera.IsTeleport(133) and
		not camera.IsTeleport(nil), "hearthstone and teleports")
	assert(camera.Ease(-1) == 0 and camera.Ease(0.5) == 0.5 and camera.Ease(2) == 1, "ease stays between 0 and 1")
	assert(camera.Blend(2, 4, 0) == 2 and camera.Blend(2, 4, 1) == 4, "blend from start to end")
	local waiting = {}
	assert(not camera.Settled(waiting, "a", 0) and camera.Settled(waiting, "a", 0.6), "settled after holding")
	assert(not camera.Settled(waiting, "b", 1) and not camera.Settled(waiting, "a", 1.2), "a change starts anew")
	assert(camera.Settled(waiting, "a", 1.8), "settled again")
	assert(camera.StepZoom(4, 3, 30) == 7 and camera.StepZoom(29, 5, 30) == 30 and camera.StepZoom(1, -5, 30) == 0,
		"zoom target stays within the game's distances")

	local saved = { GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, MoveViewLeftStart, MoveViewLeftStop,
		GetTime, ns.NewTicker, camera.State, camera.db.saved, camera.db.enabled, camera.db.close, camera.db.style,
		camera.db.move }
	local cvars = {
		CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0", test_cameraDynamicPitch = "0",
		test_cameraOverShoulder = "0", test_cameraDynamicPitchBaseFovPad = "0.4", test_cameraTargetFocusEnemyEnable = "1",
		cameraZoomSpeed = "1", cameraDistanceMaxZoomFactor = "2", cameraYawMoveSpeed = "180",
	}
	local zoom, now, state, spinning = 10, 0, {}, nil
	GetCVar = function(key) return cvars[key] end
	SetCVar = function(key, value) cvars[key] = tostring(value) end
	-- The game reports the distance on the way, not where the camera is headed: here it lags behind for good.
	GetCameraZoom = function() return 10 end
	CameraZoomOut = function(delta) zoom = zoom + delta end
	CameraZoomIn = function(delta) zoom = zoom - delta end
	MoveViewLeftStart = function(speed) spinning = speed end
	MoveViewLeftStop = function() spinning = nil end
	GetTime = function() return now end
	ns.NewTicker = function() return { Cancel = function() end } end
	camera.State = function() return state end

	-- Saved settings from the close camera of the first versions: close is switched off once.
	camera.db.enabled, camera.db.close, camera.db.style, camera.db.saved = false, true, nil, {}
	camera:OnLogin()
	assert(camera.db.close == false and camera.db.style == 2, "close camera switched off once")
	camera.db.close = true
	camera:OnLogin()
	assert(camera.db.close == true, "chosen again later: stays")
	camera.db.close, camera.db.move = false, false

	-- Left by older versions: a slow zoom speed and turning towards enemies.
	camera.db.saved = { cameraZoomSpeed = { original = "20", applied = "1" },
		test_cameraTargetFocusEnemyEnable = { original = "0", applied = "1" } }
	camera.db.enabled = true
	camera:OnOptionChanged("enabled", true)
	assert(cvars.CameraKeepCharacterCentered == "0" and cvars.test_cameraDynamicPitch == "1", "action camera on")
	assert(cvars.cameraZoomSpeed == "20" and cvars.test_cameraTargetFocusEnemyEnable == "0", "old settings back")
	assert(camera.db.saved.cameraZoomSpeed == nil and camera.db.saved.test_cameraTargetFocusEnemyEnable == nil,
		"old settings no longer kept")
	local PlayerZoom = uv(camera.OnLogin, "OnPlayerZoom")
	local function Near(a, b) return math.abs(a - b) < 1e-9 end
	local function Go(situation)
		state = situation
		camera.Update()
		now = now + 0.7
		camera.Update()
	end
	local function Step(seconds)
		local blender = uv(uv(camera.Apply, "BlendTo"), "blender")
		now = now + seconds
		blender.scripts.OnUpdate(blender, 0)
	end

	Go({})
	Step(5)
	assert(zoom == 10 and cvars.test_cameraOverShoulder == "1", "own distance, over the shoulder")
	Go({ talk = true })
	Step(1.25)
	assert(Near(zoom, 8.5), "talk: the distance glides, halfway after half the time")
	Step(5)
	assert(zoom == 7 and cvars.test_cameraOverShoulder == "1.6", "talk: both in view")
	Go({})
	Step(1.5)
	assert(Near(zoom, 8.5), "back to the own distance in 3 s")
	Step(5)
	assert(zoom == 10, "own distance again")

	state = { talk = true }
	camera.Update()
	now = now + 0.3
	Go({})
	assert(zoom == 10 and uv(camera.Apply, "current").key == "outdoors", "a short flicker does not move the camera")

	Go({ indoors = true })
	Step(1.25)
	assert(Near(zoom, 7.75), "on the way indoors")
	Go({ talk = true })
	Step(5)
	assert(zoom == 7, "changed mid-move: lands exactly, no drift")
	Go({})
	Step(5)
	assert(zoom == 10, "the own distance from before both")

	Go({ talk = true })
	Step(5)
	zoom = zoom - 2
	PlayerZoom(-2)
	Go({})
	Step(5)
	assert(zoom == 10, "after zooming in a conversation: back to the own distance")
	Go({ talk = true })
	Step(1)
	zoom = zoom - 1
	PlayerZoom(-1)
	local held = zoom
	Step(5)
	assert(zoom == held, "the player zooms: the module stops zooming")
	Go({})
	Step(5)
	assert(zoom == 10, "own distance again")

	camera.db.move = true
	Go({ indoors = true })
	Step(5)
	assert(Near(zoom, 4.9), "option: closer standing still")
	Go({ indoors = true, moving = true })
	Step(5)
	assert(Near(zoom, 6.4), "option: further while moving")
	camera.db.move = false
	Go({})
	Step(5)
	assert(Near(zoom, 10), "own distance again")

	Go({ teleport = true })
	assert(spinning and Near(spinning, 45 / 180) and Near(zoom, 10), "teleport: circling at the own distance")
	Go({})
	assert(spinning == nil, "cast over: circling stops")
	Go({ teleport = true })
	uv(camera.Start, "OnLeavingWorld")()
	assert(spinning == nil, "loading screen: circling stops")

	Go({ talk = true })
	Step(1)
	cvars.test_cameraDynamicPitch = "2" -- the player changes it meanwhile
	camera.db.enabled = false
	camera:OnOptionChanged("enabled", false)
	assert(Near(zoom, 10) and next(camera.db.saved) == nil, "switched off: distance back, nothing kept")
	assert(cvars.CameraKeepCharacterCentered == "1" and cvars.test_cameraOverShoulder == "0", "settings back")
	assert(cvars.test_cameraDynamicPitchBaseFovPad == "0.4" and spinning == nil, "tilt back, no turning")
	assert(cvars.test_cameraDynamicPitch == "2", "the player's own change stays")
	PlayerZoom(5)
	assert(Near(zoom, 10), "switched off: the player's zoom is not followed")

	GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, MoveViewLeftStart, MoveViewLeftStop = unpack(saved, 1, 7)
	GetTime, ns.NewTicker, camera.State, camera.db.saved, camera.db.enabled = unpack(saved, 8, 12)
	camera.db.close, camera.db.style, camera.db.move = saved[13], saved[14], saved[15]
	print("cinematic camera OK")
end)()
;(function()
	-- Blizzard's warning about experimental camera settings: shown once per character, then the game's frame no
	-- longer hears its event (the popup itself is never touched).
	local camera = ns:GetModule("Camera")
	local saved = { GetFramesRegisteredForEvent, camera.db.warnOnce, camera.db.enabled, camera.cdb.warningSeen }
	local EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
	local listening = {}
	local frame = {
		RegisterEvent = function(_, event) listening[event] = true end,
		UnregisterEvent = function(_, event) listening[event] = nil end,
	}
	frame:RegisterEvent(EVENT)
	GetFramesRegisteredForEvent = function(event)
		if listening[event] then
			return frame
		end
	end
	camera.db.warnOnce, camera.db.enabled, camera.cdb.warningSeen = true, false, false
	camera.OnPopupShown("TRADE")
	assert(listening[EVENT] and not camera.cdb.warningSeen, "other popups change nothing")
	camera.OnPopupShown("EXPERIMENTAL_CVAR_WARNING")
	assert(camera.cdb.warningSeen and not listening[EVENT], "shown once: the game no longer hears the event")
	camera.SilenceWarning(true)
	assert(not listening[EVENT], "silenced twice: still silent")
	camera.db.warnOnce = false
	camera:OnOptionChanged("warnOnce", false)
	assert(listening[EVENT], "option off: the warning comes again")
	camera.db.warnOnce = true
	camera:OnOptionChanged("warnOnce", true)
	assert(not listening[EVENT], "option on again: silent, the character has seen it")
	camera.cdb.warningSeen = false
	camera:OnOptionChanged("warnOnce", true)
	assert(listening[EVENT], "a character that has not seen it gets the warning")
	camera.db.warnOnce = false
	camera.OnPopupShown("EXPERIMENTAL_CVAR_WARNING")
	assert(camera.cdb.warningSeen and listening[EVENT], "option off: seen is noted, the warning stays")

	GetFramesRegisteredForEvent, camera.db.warnOnce, camera.db.enabled, camera.cdb.warningSeen = unpack(saved, 1, 4)
	print("camera warning once per character OK")
end)()
;(function()
	-- Landing: a sound when IsFalling turns false, a step after a jump, a thud after a fall, silence when blocked or off
	local landing = ns:GetModule("Landing")
	local Step = landing.Step
	local st = {}
	assert(Step(st, true, 10, false) == nil and Step(st, true, 10.3, false) == nil, "in the air: nothing yet")
	assert(Step(st, false, 10.6, false) == "jump", "short airtime is a jump")
	assert(Step(st, false, 10.7, false) == nil, "on the ground without a fall: nothing")
	Step(st, true, 20, false)
	assert(Step(st, false, 21.5, false) == "fall", "long airtime is a fall")
	Step(st, true, 30, false)
	assert(Step(st, false, 30.1, false) == nil, "a step off an edge is silent")
	Step(st, true, 40, false)
	assert(Step(st, false, 41, true) == nil and st.since == nil, "landing in water or on a flight path is silent")

	local saved = { IsFalling, IsSwimming, IsFlying, UnitOnTaxi, UnitIsDeadOrGhost, GetTime, PlaySoundFile, landing.db.enabled }
	local falling, swimming, now, played = false, false, 0, {}
	IsFalling = function() return falling end
	IsSwimming = function() return swimming end
	IsFlying = function() return false end
	UnitOnTaxi = function() return false end
	UnitIsDeadOrGhost = function() return false end
	GetTime = function() return now end
	PlaySoundFile = function(file, channel) played[#played + 1] = { file, channel } return true end
	landing.db.enabled = true
	landing:Apply()
	local watcher = uv(landing.Apply, "watcher")
	local function Tick(isFalling, t)
		falling, now = isFalling, t
		watcher:GetScript("OnUpdate")(watcher, 0.016)
	end
	Tick(true, 100) Tick(true, 100.4) Tick(false, 100.6)
	assert(#played == 1 and played[1][2] == "SFX", "a jump plays one sound on the effects channel")
	local jumpFile = played[1][1]
	Tick(true, 200) Tick(false, 201.4)
	assert(#played == 2 and played[2][1] ~= jumpFile and played[2][1] >= 950654, "a fall plays a thud")
	swimming = true
	Tick(true, 300) Tick(false, 301)
	assert(#played == 2, "into the water: silent")
	swimming = false
	landing.db.enabled = false
	landing:OnOptionChanged("enabled", false)
	assert(watcher:GetScript("OnUpdate") == nil, "option off: nothing watched")

	IsFalling, IsSwimming, IsFlying, UnitOnTaxi, UnitIsDeadOrGhost, GetTime, PlaySoundFile, landing.db.enabled = unpack(saved, 1, 8)
	print("landing OK")
end)()

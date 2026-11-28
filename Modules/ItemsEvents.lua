-- Items: lifecycle and events.
local _, ns = ...
local L = ns.L
local Items = ns:GetModule("Items")
local P = ns.ItemsPrivate
local AddScoreLine, ClearWeighCaches, CreateSellButton = P.AddScoreLine, P.ClearWeighCaches, P.CreateSellButton
local EquipBound, FillDeleteText, HookContainerFrames = P.EquipBound, P.FillDeleteText, P.HookContainerFrames
local HookRollFrames, InvalidateBagLayout, MarkBestReward = P.HookRollFrames, P.InvalidateBagLayout, P.MarkBestReward
local MarkRewardUpgrades, OnBagLayoutChanged, OnLootItemData = P.MarkRewardUpgrades, P.OnBagLayoutChanged, P.OnLootItemData
local OnSortStarted, PlaySelectedFullSound, QueueSort = P.OnSortStarted, P.PlaySelectedFullSound, P.QueueSort
local QueueWeighRefresh, ScanNewItems, ScoreSpecValues = P.QueueWeighRefresh, P.ScanNewItems, P.ScoreSpecValues
local ShowNextUpgrade, UpdateAllBags, UpdateLootRow = P.ShowNextUpgrade, P.UpdateAllBags, P.UpdateLootRow
local UpdateLootUpgrades, UpdateSortOverlay, UsesGearScores = P.UpdateLootUpgrades, P.UpdateSortOverlay, P.UsesGearScores
local moneyAreas, upgradeQueue = P.moneyAreas, P.upgradeQueue

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Items:Refresh()
	local db = self.db
	local merchant = db.autoSell or db.autoRepair or db.sellButton
	if db.sellButton then
		CreateSellButton()
	end
	if P.sellButton then
		P.sellButton:SetShown(db.sellButton)
		if not db.sellButton and MerchantFrame:IsShown() then
			P.sellButton:GetParent().Icon:SetDesaturated(C_MerchantFrame.GetNumJunkItems() == 0)
		end
	end
	self:ToggleEvent("MERCHANT_SHOW", merchant)
	self:ToggleEvent("MERCHANT_CLOSED", merchant)
	if not merchant then
		P.merchantOpen = false
	end
	self:ToggleEvent("LOOT_READY", db.fastLoot)
	self:ToggleEvent("LOOT_SLOT_CHANGED", db.upgradeArrow, UpdateLootUpgrades)
	self:ToggleEvent("ITEM_DATA_LOAD_RESULT", db.upgradeArrow, OnLootItemData)
	-- Fast loot builds on the game's auto loot; switch that on with it.
	if db.fastLoot and not GetCVarBool("autoLootDefault") then
		SetCVar("autoLootDefault", "1")
	end
	self:ToggleEvent("UI_ERROR_MESSAGE", db.destroyPrompt)
	self:UpdateFullSound()
	self:ToggleEvent("EQUIP_BIND_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("EQUIP_BIND_TRADEABLE_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("EQUIP_BIND_REFUNDABLE_CONFIRM", db.autoEquipBind, EquipBound)
	self:ToggleEvent("USE_BIND_CONFIRM", db.autoEquipBind)
	self:ToggleEvent("LOOT_BIND_CONFIRM", db.autoBind)
	self:ToggleEvent("CONFIRM_LOOT_ROLL", db.autoBind)
	self:ToggleEvent("LOOT_HISTORY_UPDATE_DROP", db.rollCounts)
	self:ToggleEvent("BAG_UPDATE_DELAYED", db.upgradePopup, ns.Measured("Items: upgrade popup", ScanNewItems))
	-- Equipping is not possible in combat: hidden meanwhile, shown again after.
	self:ToggleEvent("PLAYER_REGEN_DISABLED", db.upgradePopup, function()
		if P.upgradeFrame and P.upgradeFrame:IsShown() then
			P.upgradeFrame.combatHide = true
			P.upgradeFrame:Hide()
		end
	end)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", db.upgradePopup, ShowNextUpgrade)
	if not db.upgradePopup then
		wipe(upgradeQueue)
		if P.upgradeFrame then
			P.upgradeFrame:Hide()
		end
	end
	self:ToggleEvent("PLAYER_EQUIPMENT_CHANGED", UsesGearScores(), function()
		ClearWeighCaches()
		UpdateAllBags()
		UpdateLootUpgrades()
	end)
	self:ToggleEvent("QUEST_COMPLETE", db.markWorseReward, ns.Measured("Items: offered quest rewards", Items.questRewardJunk.Snapshot))
	self:ToggleEvent("QUEST_TURNED_IN", db.markWorseReward, ns.Measured("Items: worse quest rewards", Items.questRewardJunk.OnTurnIn))
	self:ToggleEvent("QUEST_LOOT_RECEIVED", db.markWorseReward, ns.Measured("Items: quest loot reward", Items.questRewardJunk.OnLoot))
	if not db.markWorseReward then
		Items.questRewardJunk.Reset()
	end
end

function Items:OnInitialize()
	-- The old default was persisted even if the player never chose it.
	if not self.db.fullSoundDefaultUpdated then
		if self.db.fullSoundChoice == "ping" then
			self.db.fullSoundChoice = self.defaults.fullSoundChoice
		end
		self.db.fullSoundDefaultUpdated = true
	end
	-- Former single switch for all messages of this module.
	if self.db.messages == false then
		self.db.sellMessage, self.db.repairMessage, self.db.markMessage = false, false, false
	end
	self.db.messages = nil
	-- Marked junk is no longer moved after a sort (the option is gone).
	self.db.sortMarkedJunk = nil
	-- The choice of the rating belongs to the character.
	for _, opt in ipairs(Items.options) do
		if opt.key == "scoreSpec" then
			opt.db = self.cdb
		end
	end
end

function Items:OnLogin()
	HookContainerFrames()
	ns.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
		if LootFrame and LootFrame.ScrollBox then
			ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, ns.Measured("Items: loot arrow", function(_, row, data)
				UpdateLootRow(row, data)
			end), self)
			UpdateLootUpgrades()
		end
	end)
	hooksecurefunc("StaticPopup_Show", ns.Measured("Items: delete popup", FillDeleteText))
	HookRollFrames()
	if C_Container.SortBags then
		hooksecurefunc(C_Container, "SortBags", ns.Measured("Items: sort started", OnSortStarted))
	end
	UpdateSortOverlay()
	local queueSort = ns.Measured("Items: open bag sort", QueueSort)
	EventRegistry:RegisterCallback("ContainerFrame.OpenBag", queueSort, self)
	EventRegistry:RegisterCallback("ContainerFrame.OpenAllBags", queueSort, self)
	self:RegisterEvent("BAG_UPDATE", OnBagLayoutChanged)
	self:RegisterEvent("ITEM_LOCK_CHANGED", InvalidateBagLayout)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", InvalidateBagLayout)
	hooksecurefunc("QuestInfo_Display", ns.Measured("Items: best reward", MarkBestReward))
	hooksecurefunc("QuestInfo_Display", ns.Measured("Items: reward upgrades", MarkRewardUpgrades))
	hooksecurefunc("GetQuestReward", ns.Measured("Items: quest reward turn-in", Items.questRewardJunk.OnReward))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Measured("Items: tooltip rating", AddScoreLine))
	-- The character window also uses these weights, even with all item ratings switched off.
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
		"TRAIT_TREE_CURRENCY_INFO_UPDATED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
		self:RegisterEvent(event, QueueWeighRefresh)
	end
	self:Refresh()
end

function Items:OnOptionChanged(key)
	if key == "sortSkip" then
		UpdateSortOverlay()
	elseif key == "scoreSpec" then
		QueueWeighRefresh()
	end
	-- A character list starts as a copy of the account list.
	if key == "junkPerCharacter" and self.db.junkPerCharacter
		and next(self.cdb.junk) == nil and next(self.cdb.keep) == nil then
		self.cdb.junk = CopyTable(self.db.junk)
		self.cdb.keep = CopyTable(self.db.keep)
	end
	self:Refresh()
	UpdateAllBags()
	if key == "upgradeArrow" then
		UpdateLootUpgrades()
	end
	if key == "moneyPickup" then
		for _, area in pairs(moneyAreas) do
			area:SetShown(self.db.moneyPickup and true or false)
		end
	end
	if QuestInfoFrame:IsVisible() then
		MarkBestReward()
		MarkRewardUpgrades()
	end
end

Items.options = {
	{ type = "header", name = L.ITEMS_MERCHANT },
	{ key = "autoSell", type = "toggle", name = L.ITEMS_AUTOSELL, desc = L.ITEMS_AUTOSELL_DESC },
	{ key = "sellMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "autoSell" },
	{ key = "sellButton", type = "toggle", name = L.ITEMS_SELL_BUTTON, desc = L.ITEMS_SELL_BUTTON_DESC },
	{ key = "autoRepair", type = "toggle", name = L.ITEMS_AUTOREPAIR, desc = L.ITEMS_AUTOREPAIR_DESC },
	{ key = "repairGuild", type = "toggle", name = L.ITEMS_REPAIR_GUILD, desc = L.ITEMS_REPAIR_GUILD_DESC, parent = "autoRepair" },
	{ key = "repairMessage", type = "toggle", name = L.MESSAGE_IN_CHAT, desc = L.MESSAGE_DESC, parent = "autoRepair" },
	{ key = "junkButton", type = "dropdown", name = L.ITEMS_JUNK_BUTTON, desc = L.ITEMS_JUNK_BUTTON_DESC, values = {
		{ "MiddleButton", L.ITEMS_MOUSE_MIDDLE }, { "Button4", L.ITEMS_MOUSE_4 }, { "Button5", L.ITEMS_MOUSE_5 },
		{ "None", L.ITEMS_MOUSE_NONE },
	} },
	{ key = "markMessage", type = "toggle", name = L.ITEMS_MARK_MESSAGE, desc = L.MESSAGE_DESC },
	{ key = "junkPerCharacter", type = "toggle", name = L.ITEMS_JUNK_PER_CHAR, desc = L.ITEMS_JUNK_PER_CHAR_DESC },
	{ key = "markWorseReward", type = "toggle", name = L.ITEMS_MARK_WORSE_REWARD, desc = L.ITEMS_MARK_WORSE_REWARD_DESC, new = true },
	{ key = "markUnusableBound", type = "toggle", name = L.ITEMS_MARK_UNUSABLE_BOUND, desc = L.ITEMS_MARK_UNUSABLE_BOUND_DESC, new = true },
	{ key = "junkList", type = "button", name = L.ITEMS_JUNK_LIST, text = L.ITEMS_JUNK_SHOW, desc = L.ITEMS_JUNK_LIST_DESC, func = function(button)
		Items:ShowJunkMenu(button)
	end },
	{ type = "header", name = L.ITEMS_BAGS },
	{ key = "autoSort", type = "toggle", name = L.ITEMS_AUTOSORT, desc = L.ITEMS_AUTOSORT_DESC },
	{ key = "sortSkip", type = "toggle", name = L.ITEMS_SORT_SKIP, desc = L.ITEMS_SORT_SKIP_DESC, new = true },
	{ key = "bagMenu", type = "toggle", name = L.ITEMS_BAG_MENU, desc = L.ITEMS_BAG_MENU_DESC },
	{ key = "moneyPickup", type = "toggle", name = L.ITEMS_MONEY_PICKUP, desc = L.ITEMS_MONEY_PICKUP_DESC, new = true },
	{ key = "fullSound", type = "toggle", name = L.ITEMS_FULL_SOUND, desc = L.ITEMS_FULL_SOUND_DESC, new = true },
	{ key = "fullSoundChoice", type = "dropdown", name = L.ITEMS_FULL_SOUND_CHOICE, parent = "fullSound", new = true, values = function()
		local choices = { { "warning", L.ITEMS_FULL_SOUND_WARNING } }
		for _, entry in ipairs(ns.AlertSounds and ns.AlertSounds.choices or {}) do
			choices[#choices + 1] = entry
		end
		return choices
	end },
	{ key = "fullSoundTest", type = "button", name = L.ITEMS_FULL_SOUND_TEST, text = L.QUESTS_TEST, func = PlaySelectedFullSound },
	{ type = "header", name = L.ITEMS_DISPLAY },
	{ key = "questReward", type = "toggle", name = L.ITEMS_QUEST_REWARD, desc = L.ITEMS_QUEST_REWARD_DESC },
	{ key = "upgradeArrow", type = "toggle", name = L.ITEMS_UPGRADE, desc = L.ITEMS_UPGRADE_DESC },
	{ key = "rewardUpgrade", type = "toggle", name = L.ITEMS_REWARD_UPGRADE, desc = L.ITEMS_REWARD_UPGRADE_DESC, new = true },
	{ key = "scoreSpec", type = "dropdown", name = L.ITEMS_SCORE_SPEC, desc = L.ITEMS_SCORE_SPEC_DESC, default = 0,
		values = ScoreSpecValues, new = true },
	{ key = "upgradeScore", type = "toggle", name = L.ITEMS_SCORE, desc = L.ITEMS_SCORE_DESC },
	{ key = "upgradePopup", type = "toggle", name = L.ITEMS_UPGRADE_POPUP, desc = L.ITEMS_UPGRADE_POPUP_DESC },
	{ key = "upgradeCelebrate", type = "toggle", name = L.ITEMS_UPGRADE_CELEBRATE, desc = L.ITEMS_UPGRADE_CELEBRATE_DESC, parent = "upgradePopup", new = true },
	{ key = "upgradeMarkOld", type = "toggle", name = L.ITEMS_UPGRADE_MARK_OLD, desc = L.ITEMS_UPGRADE_MARK_OLD_DESC, parent = "upgradePopup", new = true },
	{ type = "header", name = L.ITEMS_LOOT },
	{ key = "fastLoot", type = "toggle", name = L.ITEMS_FASTLOOT, desc = L.ITEMS_FASTLOOT_DESC },
	{ key = "destroyPrompt", type = "toggle", name = L.ITEMS_DESTROY, desc = L.ITEMS_DESTROY_DESC },
	{ key = "autoBind", type = "toggle", name = L.ITEMS_AUTOBIND, desc = L.ITEMS_AUTOBIND_DESC },
	{ key = "autoEquipBind", type = "toggle", name = L.ITEMS_AUTOEQUIPBIND, desc = L.ITEMS_AUTOEQUIPBIND_DESC },
	{ key = "deleteText", type = "toggle", name = L.ITEMS_DELETETEXT, desc = L.ITEMS_DELETETEXT_DESC },
	{ key = "rollCounts", type = "toggle", name = L.ITEMS_ROLL_COUNTS, desc = L.ITEMS_ROLL_COUNTS_DESC },

}

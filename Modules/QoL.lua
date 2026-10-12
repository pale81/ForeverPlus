-- Quality of life: mouseover bars, quest counter, action button texts, bag slots.
local _, ns = ...
local L = ns.L

local QoL = ns:NewModule("QoL", {
	title = L.PAGE_BARS,
	order = 5,
	defaults = {
		mouseover = true,
		mouseoverMicro = true,
		mouseoverTracker = true,
		mouseoverBags = true,
		mouseoverMainBar = false,
		mouseoverBar2 = false,
		mouseoverBar3 = false,
		mouseoverBar4 = false,
		mouseoverBar5 = false,
		mouseoverBar6 = false,
		mouseoverBar7 = false,
		mouseoverBar8 = false,
		mouseoverStance = false,
		mouseoverPet = false,
		mouseoverXP = false,
		mouseoverRep = false,
		mouseoverPlayer = false,
		mouseoverTarget = false,
		mouseoverMinimap = false,
		mouseoverCombat = false,
		nameplatesCombat = false,
		nameplatesFade = false,
		nameplatesFadeAmount = 70, -- transparency in percent out of combat
		nameplatesFadeCombat = true, -- the plates of units that are not the target stay transparent in combat too
		nameplatesTargetFull = true, -- the plate of the target is always fully visible
		hideErrors = true,
		actionText = true,
		hideHotkeys = true,
		hideMacroNames = true,
		hideMinimapButtons = true,
		rankUp = true,
	},
})

---------------------------------------------------------------------------
-- Mouseover fading
---------------------------------------------------------------------------
local CHECK_INTERVAL = 0.1
local FADE_SPEED = 4 -- alpha per second

local fadeTargets = {} -- frame -> true while managed
local driver = CreateFrame("Frame")
driver:Hide()

local elapsedSinceCheck = 0
local fading = true
ns.SetUpdate(driver, "QoL: fade update", function(_, elapsed)
	elapsedSinceCheck = elapsedSinceCheck + elapsed
	if elapsedSinceCheck >= CHECK_INTERVAL then
		elapsedSinceCheck = 0
		-- Edit Mode and (optionally) combat show everything.
		local forcedShown = ns:IsEditModeActive() or (QoL.db.mouseoverCombat and InCombatLockdown())
		for frame, state in pairs(fadeTargets) do
			local hoverFrame = state.hoverFrame or frame
			local target = (forcedShown or hoverFrame:IsMouseOver()) and state.shownAlpha or 0
			if target ~= state.target then
				state.target = target
				fading = true
			elseif ns.Number(frame:GetAlpha(), target) ~= target then
				fading = true -- Blizzard set its own alpha (e.g. status bars fade in on login)
			end
		end
	end
	if not fading then
		return
	end
	-- Fade every frame only while a transition is running.
	fading = false
	local step = elapsed * FADE_SPEED
	for frame, state in pairs(fadeTargets) do
		local alpha = frame:GetAlpha()
		local target = state.target
		if alpha ~= target then
			if target > alpha then
				alpha = min(target, alpha + step)
			else
				alpha = max(target, alpha - step)
			end
			frame:SetAlpha(alpha)
			fading = fading or alpha ~= target
		end
	end
end)

local function SetFaded(frame, enabled, hoverFrame)
	if not frame then
		return
	end
	if enabled then
		local state = fadeTargets[frame]
		if not state then
			-- The visible opacity is the frame's own (Edit Mode); a frame that is
			-- faded out right now (alpha 0) counts as fully visible.
			local own = ns.Number(frame:GetAlpha(), 1)
			state = { target = 0, shownAlpha = own > 0.05 and own or 1 }
			fadeTargets[frame] = state
		end
		state.hoverFrame = hoverFrame
		fading = true
	elseif fadeTargets[frame] then
		local state = fadeTargets[frame]
		fadeTargets[frame] = nil
		frame:SetAlpha(state.shownAlpha or 1)
	end
	driver:SetShown(next(fadeTargets) ~= nil)
end

-- A few minimap pin overlays ignore their parent alpha, so fading Minimap
-- alone leaves those icons visible. Track only frames that opt out of alpha
-- inheritance and drive them from the minimap's own mouseover state.
local function UpdateIndependentMinimapOverlays(enabled)
	local visited = {}
	local function Scan(parent)
		if not parent or visited[parent] then
			return
		end
		if parent.IsForbidden and parent:IsForbidden() then
			return
		end
		visited[parent] = true
		for _, child in ipairs({ parent:GetChildren() }) do
			if (not child.IsForbidden or not child:IsForbidden()) and child.IsIgnoringParentAlpha and child:IsIgnoringParentAlpha() then
				SetFaded(child, enabled, Minimap)
			end
			Scan(child)
		end
	end
	Scan(MinimapCluster)
	Scan(Minimap)
end

-- Action bars 2–8 in Blizzard's numbering.
local MULTI_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }

function QoL:UpdateMouseover()
	local db = self.db
	SetFaded(MicroMenuContainer, db.mouseover and db.mouseoverMicro)
	SetFaded(BagsBar, db.mouseover and db.mouseoverBags)
	SetFaded(ObjectiveTrackerFrame, db.mouseover and db.mouseoverTracker)
	SetFaded(MainActionBar, db.mouseover and db.mouseoverMainBar)
	for index, name in ipairs(MULTI_BARS) do
		SetFaded(_G[name], db.mouseover and db["mouseoverBar" .. (index + 1)])
	end
	SetFaded(StanceBar, db.mouseover and db.mouseoverStance)
	SetFaded(PetActionBar, db.mouseover and db.mouseoverPet)
	-- Blizzard's status bars 1 and 2 (experience, at the level cap reputation).
	SetFaded(MainStatusTrackingBarContainer, db.mouseover and db.mouseoverXP)
	SetFaded(SecondaryStatusTrackingBarContainer, db.mouseover and db.mouseoverRep)
	SetFaded(PlayerFrame, db.mouseover and db.mouseoverPlayer)
	SetFaded(TargetFrame, db.mouseover and db.mouseoverTarget)
	SetFaded(FocusFrame, db.mouseover and db.mouseoverTarget)
	local fadeMinimap = db.mouseover and db.mouseoverMinimap
	SetFaded(MinimapCluster, fadeMinimap)
	-- Some minimap overlays ignore their parent's alpha and otherwise remain
	-- visible when the cluster fades (notably the map backdrop and minimap).
	SetFaded(Minimap, fadeMinimap)
	SetFaded(MinimapBackdrop, fadeMinimap)
	UpdateIndependentMinimapOverlays(fadeMinimap)
end

---------------------------------------------------------------------------
-- Red error messages in the middle of the screen (yellow info stays)
---------------------------------------------------------------------------
function QoL:UpdateErrorMessages()
	if not UIErrorsFrame then
		return
	end
	if self.db.hideErrors then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	elseif not UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE") then
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

---------------------------------------------------------------------------
-- Enemy nameplates only in combat. The CVar can still be changed while the
-- combat start event is handled, before the lockdown begins.
---------------------------------------------------------------------------
local NAMEPLATE_CVAR = "nameplateShowEnemies"

---------------------------------------------------------------------------
-- Nameplates out of combat: transparent (the unit frame inside the plate;
-- the plate itself is the game's).
---------------------------------------------------------------------------
local inCombat = false

-- The plate of the target (when it is in range and has one).
local function TargetPlate()
	if QoL.db.nameplatesTargetFull and UnitExists("target") then
		local plate = C_NamePlate.GetNamePlateForUnit("target")
		return plate and not plate:IsForbidden() and plate or nil
	end
end

local function PlateAlpha(plate)
	local db = QoL.db
	if not db.nameplatesFade or (plate and plate == TargetPlate()) or (inCombat and not db.nameplatesFadeCombat) then
		return 1
	end
	return 1 - db.nameplatesFadeAmount / 100
end

local function FadePlate(plate, alpha)
	if plate and not plate:IsForbidden() and plate.UnitFrame then
		plate.UnitFrame:SetAlpha(alpha)
	end
end

local function FadeAllPlates()
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		FadePlate(plate, PlateAlpha(plate))
	end
end

local function OnPlateAdded(_, _, unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	FadePlate(plate, PlateAlpha(plate))
end

---------------------------------------------------------------------------
-- Combat start/end
---------------------------------------------------------------------------
local function OnCombatStart()
	inCombat = true
	-- Setting the CVar makes the engine rebuild its nameplates: only when it changes.
	if QoL.db.nameplatesCombat and not InCombatLockdown() and GetCVar(NAMEPLATE_CVAR) ~= "1" then
		SetCVar(NAMEPLATE_CVAR, "1")
	end
	if QoL.db.nameplatesFade then
		FadeAllPlates()
	end
end

local function OnCombatEnd()
	inCombat = false
	if QoL.db.nameplatesCombat and GetCVar(NAMEPLATE_CVAR) ~= "0" then
		SetCVar(NAMEPLATE_CVAR, "0")
	end
	if QoL.db.nameplatesFade then
		FadeAllPlates()
	end
end

function QoL:UpdateNameplates()
	local db = self.db
	inCombat = InCombatLockdown()
	local combatEvents = db.nameplatesCombat or db.nameplatesFade
	self:ToggleEvent("PLAYER_REGEN_DISABLED", combatEvents, OnCombatStart)
	self:ToggleEvent("PLAYER_REGEN_ENABLED", combatEvents, OnCombatEnd)
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", db.nameplatesFade, OnPlateAdded)
	self:ToggleEvent("PLAYER_TARGET_CHANGED", db.nameplatesFade, FadeAllPlates)
	FadeAllPlates()
	if db.nameplatesCombat then
		if db.nameplatesOriginal == nil then
			db.nameplatesOriginal = GetCVar(NAMEPLATE_CVAR)
		end
		if not InCombatLockdown() then
			SetCVar(NAMEPLATE_CVAR, "0")
		end
	elseif db.nameplatesOriginal ~= nil then
		ns.RunOutOfCombat(function()
			SetCVar(NAMEPLATE_CVAR, db.nameplatesOriginal)
			db.nameplatesOriginal = nil
		end)
	end
end

---------------------------------------------------------------------------
-- Quest counter in the tracker header ("Quests 7/25")
---------------------------------------------------------------------------
local lastQuestText

local function UpdateQuestHeader()
	local header = QuestObjectiveTracker and QuestObjectiveTracker.Header
	if not header or not header.Text then
		return
	end
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	local text = ("%s %d/%d"):format(TRACKER_HEADER_QUESTS, numQuests, C_QuestLog.GetMaxNumQuestsCanAccept())
	if text ~= lastQuestText or header.Text:GetText() ~= text then
		lastQuestText = text
		header.Text:SetText(text)
	end
end

---------------------------------------------------------------------------
-- Action button texts
---------------------------------------------------------------------------
local function ForEachActionButton(fn)
	if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames then
		for _, button in pairs(ActionBarButtonEventsFrame.frames) do
			fn(button)
		end
	end
	for _, bar in ipairs({ PetActionBar, StanceBar }) do
		if bar and bar.actionButtons then
			for _, button in ipairs(bar.actionButtons) do
				fn(button)
			end
		end
	end
end

function QoL:UpdateActionText()
	local db = self.db
	local hotkeyAlpha = (db.actionText and db.hideHotkeys) and 0 or 1
	local nameAlpha = (db.actionText and db.hideMacroNames) and 0 or 1
	ForEachActionButton(function(button)
		if button.HotKey then
			button.HotKey:SetAlpha(hotkeyAlpha)
		end
		if button.Name then
			button.Name:SetAlpha(nameAlpha)
		end
	end)
end

---------------------------------------------------------------------------
-- Hide addon minimap buttons (LibDBIcon and other non-Blizzard buttons)
---------------------------------------------------------------------------
local minimapButtons = {} -- button -> was shown when first hidden

local function IsAddonMinimapButton(frame)
	if frame:IsForbidden() or not frame:IsObjectType("Button") then
		return false
	end
	local name = frame:GetName()
	if not name or name:find("^ForeverPlus") then
		return false
	end
	if name:find("^LibDBIcon10_") then
		return true
	end
	-- Frames created by Blizzard's code are secure globals, addon buttons are not.
	-- Map pins of other addons (gathering nodes, quests, notes) must stay visible.
	local lower = name:lower()
	if lower:find("pin") or not (lower:find("minimap") or lower:find("button")) then
		return false
	end
	return issecurevariable ~= nil and not issecurevariable(name)
end

local function KeepHidden(button)
	if QoL.db.hideMinimapButtons then
		button:Hide()
	end
end

function QoL:UpdateMinimapButtons()
	local hide = self.db.hideMinimapButtons
	for _, parent in ipairs({ Minimap, MinimapBackdrop }) do
		for _, child in ipairs({ parent:GetChildren() }) do
			if IsAddonMinimapButton(child) then
				if minimapButtons[child] == nil then
					minimapButtons[child] = child:IsShown()
					hooksecurefunc(child, "Show", KeepHidden)
				end
				if hide then
					child:Hide()
				elseif minimapButtons[child] then
					child:Show()
				end
			end
		end
	end
end

-- Blizzard's own coordinates below the minimap: switched off once by default,
-- afterwards the game's own setting (Options > Minimap) decides.
function QoL:DisableBlizzardCoordsOnce()
	if self.db.blizzardCoordsDefaulted or GetCVar("minimapShowPlayerCoords") == nil then
		return
	end
	SetCVar("minimapShowPlayerCoords", "0")
	self.db.blizzardCoordsDefaulted = true
end

-- /fp grundwerte: the game settings ForeverPlus starts with, set again (after the console command that puts every
-- setting back to its default, for example): Blizzard's coordinates below the minimap off, auto loot on (fast
-- loot builds on it), the old scrolling combat text off.
function QoL.ApplyBaseSettings()
	local changed = {}
	local function Set(name, value, label)
		if GetCVar(name) ~= nil then
			SetCVar(name, value)
			changed[#changed + 1] = label
		end
	end
	Set("minimapShowPlayerCoords", "0", L.QOL_BASE_COORDS)
	Set("enableFloatingCombatText", "0", L.QOL_BASE_FCT)
	local items = ns:GetModule("Items")
	if items and items.db and items.db.fastLoot then
		Set("autoLootDefault", "1", L.QOL_BASE_LOOT)
	end
	QoL.db.blizzardCoordsDefaulted = true
	ns.PrintAlways(L.QOL_BASE_DONE, table.concat(changed, ", "))
end

---------------------------------------------------------------------------
-- Rank up: a newly learned rank replaces the rank directly below it on the
-- action bars. Lower ranks placed on purpose (e.g. to save mana) stay.
---------------------------------------------------------------------------
local MAX_ACTION_SLOT = 180

local function SpellRank(spellID)
	local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
	return subtext and tonumber(subtext:match("(%d+)"))
end

local function RankUp(newID)
	local name, rank = C_Spell.GetSpellName(newID), SpellRank(newID)
	if not name or not rank or rank < 2 then
		return
	end
	local slots = {}
	for slot = 1, MAX_ACTION_SLOT do
		if HasAction(slot) then
			local actionType, id = GetActionInfo(slot)
			if actionType == "spell" and id ~= newID and C_Spell.GetSpellName(id) == name and SpellRank(id) == rank - 1 then
				slots[#slots + 1] = slot
			end
		end
	end
	for _, slot in ipairs(slots) do
		ClearCursor()
		C_Spell.PickupSpell(newID)
		PlaceAction(slot)
		ClearCursor()
	end
end

function QoL:UpdateRankUp()
	self:ToggleEvent("LEARNED_SPELL_IN_SKILL_LINE", self.db.rankUp, function(_, _, spellID)
		-- A short delay lets the spell book know the new rank first.
		C_Timer.After(0.5, function()
			ns.RunOutOfCombat(function()
				RankUp(spellID)
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function QoL:OnInitialize()
	-- Former combined options for bars 2–8 and stance/pet bar.
	local db = self.db
	if db.mouseoverMultiBars ~= nil then
		for bar = 2, 8 do
			db["mouseoverBar" .. bar] = db.mouseoverMultiBars
		end
		db.mouseoverMultiBars = nil
	end
	if db.mouseoverStancePet ~= nil then
		db.mouseoverStance, db.mouseoverPet = db.mouseoverStancePet, db.mouseoverStancePet
		db.mouseoverStancePet = nil
	end
end

function QoL:OnLogin()
	-- The former option "tiny floating numbers" lived here: its saved values go back once (RepFlash does it now).
	if self.db.worldTextOld then
		for name, value in pairs(self.db.worldTextOld) do
			SetCVar(name, value)
		end
		self.db.worldTextOld, self.db.hideWorldText = nil, nil
	end
	self:UpdateRankUp()
	-- Addons create their minimap buttons during their own login handling.
	local function ScanMinimapButtons()
		self:UpdateMinimapButtons()
		self:UpdateMouseover()
	end
	self:RegisterEvent("ADDON_LOADED", ScanMinimapButtons)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(2, ScanMinimapButtons)
	end)

	self:UpdateActionText()
	self:DisableBlizzardCoordsOnce()
	self:UpdateNameplates()
	self:UpdateErrorMessages()

	ns.OnAddOnLoaded("Blizzard_ObjectiveTracker", function()
		self:UpdateMouseover()
		self:RegisterEvent("QUEST_LOG_UPDATE", UpdateQuestHeader)
		if QuestObjectiveTracker then
			hooksecurefunc(QuestObjectiveTracker, "Update", UpdateQuestHeader)
		end
		UpdateQuestHeader()
	end)
	self:UpdateMouseover()
end

function QoL:OnOptionChanged(key)
	if key:find("^mouseover") then
		self:UpdateMouseover()
	elseif key == "actionText" or key == "hideHotkeys" or key == "hideMacroNames" then
		self:UpdateActionText()
	elseif key == "hideErrors" then
		self:UpdateErrorMessages()
	elseif key == "nameplatesCombat" or key == "nameplatesFade" or key == "nameplatesFadeAmount"
		or key == "nameplatesFadeCombat" or key == "nameplatesTargetFull" then
		self:UpdateNameplates()
	elseif key == "hideMinimapButtons" then
		self:UpdateMinimapButtons()
	elseif key == "rankUp" then
		self:UpdateRankUp()
	end
end

QoL.options = {
	{ type = "header", name = L.QOL_MOUSEOVER_HEADER },
	{ key = "mouseover", type = "toggle", name = L.QOL_MOUSEOVER, desc = L.QOL_MOUSEOVER_DESC },
	{ key = "mouseoverCombat", type = "toggle", name = L.QOL_MOUSEOVER_COMBAT, desc = L.QOL_MOUSEOVER_COMBAT_DESC, parent = "mouseover" },
	{ key = "mouseoverMicro", type = "toggle", name = L.QOL_MOUSEOVER_MICRO, parent = "mouseover" },
	{ key = "mouseoverTracker", type = "toggle", name = L.QOL_MOUSEOVER_TRACKER, parent = "mouseover" },
	{ key = "mouseoverBags", type = "toggle", name = L.QOL_MOUSEOVER_BAGS, parent = "mouseover" },
	{ key = "mouseoverMainBar", type = "toggle", name = L.QOL_MOUSEOVER_MAINBAR, parent = "mouseover" },
	{ key = "mouseoverBar2", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(2), parent = "mouseover" },
	{ key = "mouseoverBar3", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(3), parent = "mouseover" },
	{ key = "mouseoverBar4", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(4), parent = "mouseover" },
	{ key = "mouseoverBar5", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(5), parent = "mouseover" },
	{ key = "mouseoverBar6", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(6), parent = "mouseover" },
	{ key = "mouseoverBar7", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(7), parent = "mouseover" },
	{ key = "mouseoverBar8", type = "toggle", name = L.QOL_MOUSEOVER_BAR:format(8), parent = "mouseover" },
	{ key = "mouseoverStance", type = "toggle", name = L.QOL_MOUSEOVER_STANCE, parent = "mouseover" },
	{ key = "mouseoverPet", type = "toggle", name = L.QOL_MOUSEOVER_PET, parent = "mouseover" },
	{ key = "mouseoverXP", type = "toggle", name = L.QOL_MOUSEOVER_XP, desc = L.QOL_MOUSEOVER_STATUS_DESC, parent = "mouseover" },
	{ key = "mouseoverRep", type = "toggle", name = L.QOL_MOUSEOVER_REP, desc = L.QOL_MOUSEOVER_STATUS_DESC, parent = "mouseover" },
	{ key = "mouseoverPlayer", type = "toggle", name = L.QOL_MOUSEOVER_PLAYER, parent = "mouseover" },
	{ key = "mouseoverTarget", type = "toggle", name = L.QOL_MOUSEOVER_TARGET, parent = "mouseover" },
	{ key = "mouseoverMinimap", type = "toggle", name = L.QOL_MOUSEOVER_MINIMAP, desc = L.QOL_MOUSEOVER_MINIMAP_DESC, parent = "mouseover" },
	{ type = "header", name = L.QOL_ERRORS_HEADER },
	{ key = "hideErrors", type = "toggle", name = L.QOL_HIDE_ERRORS, desc = L.QOL_HIDE_ERRORS_DESC },
	{ type = "header", name = L.QOL_NAMEPLATES_HEADER },
	{ key = "nameplatesCombat", type = "toggle", name = L.QOL_NAMEPLATES_COMBAT, desc = L.QOL_NAMEPLATES_COMBAT_DESC },
	{ key = "nameplatesFade", type = "toggle", name = L.QOL_NAMEPLATES_FADE, desc = L.QOL_NAMEPLATES_FADE_DESC },
	{ key = "nameplatesTargetFull", type = "toggle", name = L.QOL_NAMEPLATES_TARGET_FULL, desc = L.QOL_NAMEPLATES_TARGET_FULL_DESC, parent = "nameplatesFade" },
	{ key = "nameplatesFadeCombat", type = "toggle", name = L.QOL_NAMEPLATES_FADE_COMBAT, desc = L.QOL_NAMEPLATES_FADE_COMBAT_DESC, parent = "nameplatesFade" },
	{ key = "nameplatesFadeAmount", type = "slider", name = L.QOL_NAMEPLATES_FADE_AMOUNT, parent = "nameplatesFade", min = 10, max = 90, step = 5,
		format = function(value)
			return ("%d %%"):format(value)
		end },
	{ type = "header", name = L.QOL_ACTIONBAR_HEADER },
	{ key = "actionText", type = "toggle", name = L.QOL_ACTION_TEXT, desc = L.QOL_ACTION_TEXT_DESC },
	{ key = "hideHotkeys", type = "toggle", name = L.QOL_HIDE_HOTKEYS, parent = "actionText" },
	{ key = "hideMacroNames", type = "toggle", name = L.QOL_HIDE_MACRO_NAMES, parent = "actionText" },
	{ key = "rankUp", type = "toggle", name = L.QOL_RANK_UP, desc = L.QOL_RANK_UP_DESC },
	{ type = "header", name = L.QOL_BAGS_HEADER },
	{ type = "header", name = L.QOL_MINIMAP_HEADER },
	{ key = "hideMinimapButtons", type = "toggle", name = L.QOL_HIDE_MINIMAP_BUTTONS, desc = L.QOL_HIDE_MINIMAP_BUTTONS_DESC },
}

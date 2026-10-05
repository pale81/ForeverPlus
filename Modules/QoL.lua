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
		nameplatesCombat = false,
		timeToDeath = false,
		hideErrors = true,
		actionText = true,
		hideHotkeys = true,
		hideMacroNames = true,
		bagSlots = true,
		hideMinimapButtons = true,
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
driver:SetScript("OnUpdate", function(_, elapsed)
	elapsedSinceCheck = elapsedSinceCheck + elapsed
	if elapsedSinceCheck >= CHECK_INTERVAL then
		elapsedSinceCheck = 0
		local editMode = ns:IsEditModeActive()
		for frame, state in pairs(fadeTargets) do
			local target = (editMode or frame:IsMouseOver()) and 1 or 0
			if target ~= state.target then
				state.target = target
				fading = true
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
		if alpha ~= state.target then
			if state.target > alpha then
				alpha = min(state.target, alpha + step)
			else
				alpha = max(state.target, alpha - step)
			end
			frame:SetAlpha(alpha)
			fading = fading or alpha ~= state.target
		end
	end
end)

local function SetFaded(frame, enabled)
	if not frame then
		return
	end
	if enabled then
		fadeTargets[frame] = fadeTargets[frame] or { target = 0 }
		fading = true
	elseif fadeTargets[frame] then
		fadeTargets[frame] = nil
		frame:SetAlpha(1)
	end
	driver:SetShown(next(fadeTargets) ~= nil)
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
-- Time to death behind the name on nameplates: from the health lost since
-- the unit was first damaged in this fight. Health that the client hands out
-- as a secret value cannot be read; such units show nothing.
---------------------------------------------------------------------------
local TTD_INTERVAL = 0.5
local TTD_MIN_SAMPLE = 1.5
local TTD_MAX = 600
local ttdTexts, samples = {}, {}
local ttdTicker

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function TTDText(nameplate)
	local text = ttdTexts[nameplate]
	if not text then
		local name = nameplate.UnitFrame and nameplate.UnitFrame.name
		if not name then
			return
		end
		text = nameplate.UnitFrame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
		text:SetPoint("LEFT", name, "RIGHT", 3, 0)
		text:SetTextColor(1, 0.82, 0)
		ttdTexts[nameplate] = text
	end
	return text
end

local function TimeToDeath(unit, now)
	local health, guid = UnitHealth(unit), UnitGUID(unit)
	if not guid or Secret(health) or Secret(guid) or not health or health <= 0 then
		return
	end
	local sample = samples[guid]
	if not sample or health > sample.health then
		samples[guid] = { time = now, health = health }
		return
	end
	local elapsed = now - sample.time
	if elapsed < TTD_MIN_SAMPLE or sample.health <= health then
		return
	end
	local seconds = health / ((sample.health - health) / elapsed)
	return seconds < TTD_MAX and seconds or nil
end

local function UpdateTimeToDeath()
	local now = GetTime()
	for _, nameplate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = nameplate.unitToken or (nameplate.UnitFrame and nameplate.UnitFrame.unit)
		if unit and not nameplate:IsForbidden() then
			local text = TTDText(nameplate)
			if text then
				local seconds = TimeToDeath(unit, now)
				text:SetText(seconds and ("%d:%02d"):format(floor(seconds / 60), floor(seconds % 60)) or "")
			end
		end
	end
end

local function StopTimeToDeath()
	if ttdTicker then
		ttdTicker:Cancel()
		ttdTicker = nil
	end
	wipe(samples)
	for _, text in pairs(ttdTexts) do
		text:SetText("")
	end
end

---------------------------------------------------------------------------
-- Combat start/end for both nameplate features
---------------------------------------------------------------------------
local function OnCombatStart()
	if QoL.db.nameplatesCombat then
		SetCVar(NAMEPLATE_CVAR, "1")
	end
	if QoL.db.timeToDeath and not ttdTicker then
		ttdTicker = C_Timer.NewTicker(TTD_INTERVAL, UpdateTimeToDeath)
	end
end

local function OnCombatEnd()
	if QoL.db.nameplatesCombat then
		SetCVar(NAMEPLATE_CVAR, "0")
	end
	StopTimeToDeath()
end

function QoL:UpdateNameplates()
	local db = self.db
	if db.nameplatesCombat or db.timeToDeath then
		self:RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatStart)
		self:RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
	else
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
	if not db.timeToDeath then
		StopTimeToDeath()
	end
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
-- Free / total bag slots on the backpack button
---------------------------------------------------------------------------
local function UpdateBagSlots(button)
	if not QoL.db.bagSlots then
		return
	end
	local free, total = 0, 0
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local numFree, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		if bagFamily == 0 then
			free = free + numFree
			total = total + C_Container.GetContainerNumSlots(bag)
		end
	end
	button.FreeSlots:SetFormattedText("%d/%d", free, total)
	button.FreeSlots:Show()
end

function QoL:UpdateBagSlotsOption()
	local button = MainMenuBarBackpackButton
	if not button or not button.FreeSlots then
		return
	end
	if self.db.bagSlots then
		UpdateBagSlots(button)
	else
		button:UpdateFreeSlots()
		button:SetCountShown(GetCVar("displayFreeBagSlots") == "1")
	end
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
	-- Addons create their minimap buttons during their own login handling.
	local function ScanMinimapButtons()
		self:UpdateMinimapButtons()
	end
	self:RegisterEvent("ADDON_LOADED", ScanMinimapButtons)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(2, ScanMinimapButtons)
	end)

	self:UpdateActionText()
	self:DisableBlizzardCoordsOnce()
	self:UpdateNameplates()
	self:UpdateErrorMessages()

	local backpack = MainMenuBarBackpackButton
	if backpack and backpack.UpdateFreeSlots then
		hooksecurefunc(backpack, "UpdateFreeSlots", UpdateBagSlots)
		hooksecurefunc(backpack, "SetCountShown", UpdateBagSlots)
		self:UpdateBagSlotsOption()
	end

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
	elseif key == "bagSlots" then
		self:UpdateBagSlotsOption()
	elseif key == "hideErrors" then
		self:UpdateErrorMessages()
	elseif key == "nameplatesCombat" or key == "timeToDeath" then
		self:UpdateNameplates()
	elseif key == "hideMinimapButtons" then
		self:UpdateMinimapButtons()
	end
end

QoL.options = {
	{ type = "header", name = L.QOL_MOUSEOVER_HEADER },
	{ key = "mouseover", type = "toggle", name = L.QOL_MOUSEOVER, desc = L.QOL_MOUSEOVER_DESC },
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
	{ type = "header", name = L.QOL_ERRORS_HEADER },
	{ key = "hideErrors", type = "toggle", name = L.QOL_HIDE_ERRORS, desc = L.QOL_HIDE_ERRORS_DESC },
	{ type = "header", name = L.QOL_NAMEPLATES_HEADER },
	{ key = "nameplatesCombat", type = "toggle", name = L.QOL_NAMEPLATES_COMBAT, desc = L.QOL_NAMEPLATES_COMBAT_DESC },
	{ key = "timeToDeath", type = "toggle", name = L.QOL_TTD, desc = L.QOL_TTD_DESC },
	{ type = "header", name = L.QOL_ACTIONBAR_HEADER },
	{ key = "actionText", type = "toggle", name = L.QOL_ACTION_TEXT, desc = L.QOL_ACTION_TEXT_DESC },
	{ key = "hideHotkeys", type = "toggle", name = L.QOL_HIDE_HOTKEYS, parent = "actionText" },
	{ key = "hideMacroNames", type = "toggle", name = L.QOL_HIDE_MACRO_NAMES, parent = "actionText" },
	{ type = "header", name = L.QOL_BAGS_HEADER },
	{ key = "bagSlots", type = "toggle", name = L.QOL_BAG_SLOTS, desc = L.QOL_BAG_SLOTS_DESC },
	{ type = "header", name = L.QOL_MINIMAP_HEADER },
	{ key = "hideMinimapButtons", type = "toggle", name = L.QOL_HIDE_MINIMAP_BUTTONS, desc = L.QOL_HIDE_MINIMAP_BUTTONS_DESC },
}

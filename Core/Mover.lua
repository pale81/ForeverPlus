-- Window mover (Alt + drag, Ctrl + mouse wheel to scale, like BlizzMove) and
-- Edit Mode integration for frames created by ForeverPlus.
local _, ns = ...
local L = ns.L

local Mover = ns:NewModule("Mover", {
	title = L.MOVER_TITLE,
	order = 100,
	defaults = {
		enabled = true,
		scaling = true,
		multiWindow = true,
	},
})

local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.0, 0.05

-- Frames handled elsewhere (chat has its own movement, tooltips follow the cursor).
local blocked = {
	UIParent = true,
	WorldFrame = true,
	GameTooltip = true,
	ItemRefTooltip = true,
}

local saved          -- ForeverPlusDB.frames
local hooked = {}    -- frames with an OnShow re-apply hook
local moving         -- frame currently dragged
local startLeft, startTop
local pending = {}   -- frames to re-apply after combat

local function IsChatFrame(name)
	return name:find("^ChatFrame") or name:find("^GeneralDockManager")
end

-- Walks from the region under the cursor up to the top level window.
local function FindWindow(region)
	local frame = region
	while frame do
		if frame:IsForbidden() then
			return
		end
		if not frame.GetParent then
			return
		end
		local parent = frame:GetParent()
		if not parent or parent == UIParent then
			break
		end
		frame = parent
	end
	if not frame or not frame.IsObjectType or not frame:IsObjectType("Frame") then
		return
	end
	local name = frame:GetName()
	if not name or blocked[name] or IsChatFrame(name) then
		return
	end
	-- Edit Mode systems (action bars, unit frames, minimap, …) are positioned by Edit Mode.
	if frame.system or frame.isManagedFrame or frame.fpEditFrame then
		return
	end
	if InCombatLockdown() and frame:IsProtected() then
		return
	end
	return frame
end

local function Apply(frame)
	local data = saved[frame:GetName()]
	if not data then
		return
	end
	if InCombatLockdown() and frame:IsProtected() then
		if not pending[frame] then
			pending[frame] = true
			ns.RunOutOfCombat(function()
				pending[frame] = nil
				Apply(frame)
			end)
		end
		return
	end
	if data.scale then
		frame:SetScale(data.scale)
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", data.x, data.y)
end

local function HookWindow(frame)
	if hooked[frame] then
		return
	end
	hooked[frame] = true
	frame:HookScript("OnShow", Apply)
end

local function Save(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then
		return
	end
	local name = frame:GetName()
	local data = saved[name] or {}
	data.x, data.y = left, top
	data.scale = data.scale or (frame:GetScale() ~= 1 and frame:GetScale() or nil)
	saved[name] = data
	HookWindow(frame)
end

local function ApplyAllShown()
	for name in pairs(saved) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsShown and not frame:IsForbidden() and frame:IsShown() then
			Apply(frame)
		end
	end
end

---------------------------------------------------------------------------
-- Alt + drag
---------------------------------------------------------------------------
local function StartMoving(frame)
	if not frame:IsMovable() then
		frame:SetMovable(true)
	end
	frame:SetClampedToScreen(true)
	startLeft, startTop = frame:GetLeft(), frame:GetTop()
	frame:StartMoving()
	moving = frame
end

local function StopMoving()
	local frame = moving
	moving = nil
	if not frame then
		return
	end
	frame:StopMovingOrSizing()
	-- Our own database restores the position; keep the client layout cache out of it.
	if frame:IsUserPlaced() and not (InCombatLockdown() and frame:IsProtected()) then
		frame:SetUserPlaced(false)
	end
	-- A plain Alt-click must not pin the window to its current position.
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and startLeft and math.abs(left - startLeft) < 1 and math.abs(top - startTop) < 1 then
		return
	end
	Save(frame)
end

function Mover:GLOBAL_MOUSE_DOWN(_, button)
	if button ~= "LeftButton" or not IsAltKeyDown() or moving then
		return
	end
	local foci = GetMouseFoci()
	local frame = foci and FindWindow(foci[1])
	if frame then
		StartMoving(frame)
	end
end

function Mover:GLOBAL_MOUSE_UP(_, button)
	if button == "LeftButton" and moving then
		StopMoving()
	end
end

---------------------------------------------------------------------------
-- Ctrl + mouse wheel scaling: an invisible wheel catcher follows the window
-- under the cursor, but only while Ctrl is held.
---------------------------------------------------------------------------
local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetFrameStrata("TOOLTIP")
catcher:EnableMouse(false)
catcher:Hide()

local ticker
local function UpdateCatcherTarget()
	local foci = GetMouseFoci()
	local region = foci and foci[1]
	if region == catcher then
		region = foci[2]
	end
	local frame = region and FindWindow(region)
	if frame ~= catcher.target then
		catcher.target = frame
		catcher:ClearAllPoints()
		if frame then
			catcher:SetAllPoints(frame)
			catcher:EnableMouseWheel(true)
			catcher:Show()
		else
			catcher:EnableMouseWheel(false)
			catcher:Hide()
		end
	end
end

catcher:SetScript("OnMouseWheel", function(self, delta)
	local frame = self.target
	if not frame or (InCombatLockdown() and frame:IsProtected()) then
		return
	end
	local oldScale = frame:GetScale()
	local newScale = Clamp(oldScale + delta * SCALE_STEP, MIN_SCALE, MAX_SCALE)
	if newScale == oldScale then
		return
	end
	local left, top = frame:GetLeft(), frame:GetTop()
	frame:SetScale(newScale)
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * oldScale / newScale, top * oldScale / newScale)
	end
	local name = frame:GetName()
	saved[name] = saved[name] or {}
	saved[name].scale = newScale
	Save(frame)
end)

local function StopCatcher()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	catcher.target = nil
	catcher:EnableMouseWheel(false)
	catcher:Hide()
end

function Mover:MODIFIER_STATE_CHANGED(_, key, down)
	if key ~= "LCTRL" and key ~= "RCTRL" then
		return
	end
	if down == 1 then
		if not ticker then
			UpdateCatcherTarget()
			ticker = C_Timer.NewTicker(0.1, UpdateCatcherTarget)
		end
	else
		StopCatcher()
	end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Mover:Refresh()
	local enabled = self.db.enabled
	self:ToggleEvent("GLOBAL_MOUSE_DOWN", enabled)
	self:ToggleEvent("GLOBAL_MOUSE_UP", enabled)
	self:ToggleEvent("MODIFIER_STATE_CHANGED", enabled and self.db.scaling)
	if not (enabled and self.db.scaling) then
		StopCatcher()
	end
end

function Mover:OnInitialize()
	saved = ns.db.frames
	self:Refresh()
end

---------------------------------------------------------------------------
-- Several windows at once: selected panels leave Blizzard's panel manager, so
-- opening one no longer closes or pushes the others (and bags can open next
-- to them). Escape still closes them. Protected frames and taint sensitive
-- windows (game menu, settings, spell book, collections, LFG, …) stay managed.
---------------------------------------------------------------------------
local FREE_WINDOWS = {
	"CharacterFrame", "FriendsFrame", "MerchantFrame", "GossipFrame", "QuestFrame",
	"TradeFrame", "MailFrame", "DressUpFrame", "ItemTextFrame", "TabardFrame",
	"PetitionFrame", "GuildRegistrarFrame", "HelpFrame", "ChatConfigFrame",
	"QuestLogPopupDetailFrame", "BankFrame", "TaxiFrame", "AddonList",
	"EncounterJournal", "AchievementFrame", "ClassTrainerFrame", "InspectFrame",
	"MacroFrame", "TimeManagerFrame", "ProfessionsBookFrame",
}
local freed = {}

local function PlaceFreeWindow(frame)
	if frame:GetNumPoints() == 0 and not saved[frame:GetName()] then
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
end

local function FreeWindow(name)
	local frame = _G[name]
	if type(frame) ~= "table" or freed[frame] or not frame.SetAttributeNoHandler
		or frame:IsForbidden() or frame:IsProtected() or InCombatLockdown() then
		return
	end
	freed[frame] = true
	frame:SetAttributeNoHandler("UIPanelLayout-defined", true)
	frame:SetAttributeNoHandler("UIPanelLayout-area", nil)
	if not tContains(UISpecialFrames, name) then
		tinsert(UISpecialFrames, name)
	end
	frame:HookScript("OnShow", PlaceFreeWindow)
end

local function FreeWindows()
	if Mover.db.multiWindow then
		for _, name in ipairs(FREE_WINDOWS) do
			FreeWindow(name)
		end
	end
end

function Mover:OnLogin()
	-- The panel manager's delegate frame is local and forbidden; its public entry
	-- points position the panels synchronously, so re-apply right after them.
	for _, func in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions", "UpdateContainerFrameAnchors" }) do
		if type(_G[func]) == "function" then
			hooksecurefunc(func, ApplyAllShown)
		end
	end
	for name in pairs(saved) do
		local frame = _G[name]
		if type(frame) == "table" and frame.HookScript then
			HookWindow(frame)
		end
	end
	FreeWindows()
	-- Load-on-demand windows appear later.
	self:RegisterEvent("ADDON_LOADED", function()
		ns.RunOutOfCombat(FreeWindows)
		for name in pairs(saved) do
			local frame = _G[name]
			if type(frame) == "table" and frame.HookScript and not hooked[frame] then
				HookWindow(frame)
				if frame:IsShown() then
					Apply(frame)
				end
			end
		end
	end)
end

function Mover:OnOptionChanged(key, value)
	self:Refresh()
	if key == "multiWindow" then
		if value then
			ns.RunOutOfCombat(FreeWindows)
		else
			ns.Print(L.RELOAD_REQUIRED)
		end
	end
end

---------------------------------------------------------------------------
-- Movable displays (coordinates, FPS/MS, …): drag to move, right-click locks
---------------------------------------------------------------------------
local displays = {}

local function DisplayLocked(entry)
	return entry.module.db[entry.lockKey] and true or false
end

local function ApplyDisplayPosition(entry)
	local frame = entry.frame
	local pos = saved[entry.key]
	frame:ClearAllPoints()
	if pos then
		local scale = frame:GetEffectiveScale()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / scale, pos.y / scale)
	else
		entry.applyDefault(frame)
	end
end

-- Locks or unlocks a display; goes through the setting so the options page follows.
function ns:SetDisplayLocked(entry, locked)
	local variable = ("ForeverPlus_%s_%s"):format(entry.module.name, entry.lockKey)
	if Settings.GetSetting and Settings.GetSetting(variable) then
		Settings.SetValue(variable, locked)
	else
		entry.module.db[entry.lockKey] = locked
	end
end

-- frame: mouse enabled frame; module.db[lockKey] holds the lock state.
function ns:RegisterDisplay(frame, key, module, lockKey, applyDefault)
	local entry = { frame = frame, key = "D:" .. key, module = module, lockKey = lockKey, applyDefault = applyDefault }
	displays[#displays + 1] = entry
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(display)
		if not DisplayLocked(entry) then
			display:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(display)
		display:StopMovingOrSizing()
		display:SetUserPlaced(false)
		local x, y = display:GetCenter()
		local scale = display:GetEffectiveScale()
		saved[entry.key] = { x = x * scale, y = y * scale }
		ApplyDisplayPosition(entry)
	end)
	frame:HookScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			local locked = not DisplayLocked(entry)
			ns:SetDisplayLocked(entry, locked)
			if entry.module.db.lockMessage then
				ns.Print(locked and L.DISPLAY_LOCKED or L.DISPLAY_UNLOCKED)
			end
		end
	end)
	ApplyDisplayPosition(entry)
	return entry
end

function ns:LockAllDisplays()
	for _, entry in ipairs(displays) do
		ns:SetDisplayLocked(entry, true)
	end
	ns.Print(L.DISPLAY_ALL_LOCKED)
end

function ns:ResetFramePositions()
	wipe(saved)
	for _, data in pairs(ns.editFrames or {}) do
		data.reset()
	end
	for _, entry in ipairs(displays) do
		ApplyDisplayPosition(entry)
	end
	ns.Print(L.MOVER_RESET_DONE)
end

Mover.options = {
	{ key = "enabled", type = "toggle", name = L.MOVER_ENABLE, desc = L.MOVER_ENABLE_DESC },
	{ key = "scaling", type = "toggle", name = L.MOVER_SCALE, desc = L.MOVER_SCALE_DESC, parent = "enabled" },
	{ key = "multiWindow", type = "toggle", name = L.MOVER_MULTI, desc = L.MOVER_MULTI_DESC },
	{ type = "button", name = L.MOVER_RESET, text = L.RESET, desc = L.MOVER_RESET_DESC, func = function()
		ns:ResetFramePositions()
	end },
}

---------------------------------------------------------------------------
-- Edit Mode integration for ForeverPlus frames
---------------------------------------------------------------------------
local SelectionLayout = {
	["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
	["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

ns.editFrames = {}
local editModeActive = false

local function ApplyEditPosition(entry)
	local frame, pos = entry.frame, entry.db
	frame:ClearAllPoints()
	if pos.x then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
	else
		frame:SetPoint(unpack(entry.defaultPoint))
	end
end

local function CreateSelection(entry)
	local frame = entry.frame
	local sel = CreateFrame("Frame", nil, frame, "NineSliceCodeTemplate")
	sel:SetAllPoints()
	sel:SetFrameStrata("MEDIUM")
	sel:SetFrameLevel(1000)
	sel:EnableMouse(true)
	sel:RegisterForDrag("LeftButton")
	sel:SetIgnoreParentAlpha(true)
	NineSliceUtil.ApplyLayout(sel, SelectionLayout, "editmode-actionbar-highlight")
	sel.Label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sel.Label:SetPoint("CENTER")
	sel.Label:SetText(entry.label)
	sel:SetScript("OnDragStart", function()
		if InCombatLockdown() and frame:IsProtected() then
			return
		end
		frame:SetMovable(true)
		frame:StartMoving()
	end)
	sel:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
		entry.db.x, entry.db.y = frame:GetLeft(), frame:GetTop()
		ApplyEditPosition(entry)
	end)
	sel:SetScript("OnMouseDown", function(self)
		NineSliceUtil.ApplyLayout(self, SelectionLayout, "editmode-actionbar-selected")
	end)
	sel:SetScript("OnMouseUp", function(self)
		NineSliceUtil.ApplyLayout(self, SelectionLayout, "editmode-actionbar-highlight")
	end)
	sel:Hide()
	entry.selection = sel
end

local function SetEditMode(active)
	editModeActive = active
	for _, entry in pairs(ns.editFrames) do
		if active and not entry.selection then
			CreateSelection(entry)
		end
		if entry.selection then
			ns.RunOutOfCombat(function()
				entry.selection:SetShown(editModeActive)
				if entry.onEditMode then
					entry.onEditMode(editModeActive)
				end
			end)
		end
	end
end

function ns:IsEditModeActive()
	return editModeActive
end

-- Registers a ForeverPlus frame for Edit Mode dragging and Alt-drag exclusion.
-- defaultPoint: { point, relativeTo, relativePoint, x, y }
function ns:RegisterEditFrame(frame, key, label, defaultPoint, onEditMode)
	local positions = ns.db.frames
	positions["FP:" .. key] = positions["FP:" .. key] or {}
	local entry = {
		frame = frame,
		label = label,
		defaultPoint = defaultPoint,
		db = positions["FP:" .. key],
		onEditMode = onEditMode,
	}
	entry.reset = function()
		positions["FP:" .. key] = {}
		entry.db = positions["FP:" .. key]
		ns.RunOutOfCombat(function()
			ApplyEditPosition(entry)
		end)
	end
	frame.fpEditFrame = true
	ns.editFrames[key] = entry
	ApplyEditPosition(entry)
	if editModeActive then
		SetEditMode(true)
	end
	return entry
end

EventRegistry:RegisterCallback("EditMode.Enter", function()
	SetEditMode(true)
end, Mover)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	SetEditMode(false)
end, Mover)

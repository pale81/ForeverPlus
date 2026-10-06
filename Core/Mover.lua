-- Window mover (Alt + drag, Ctrl + mouse wheel to scale, Alt + right-click to
-- lock) for windows and ForeverPlus displays, and Edit Mode integration for
-- frames created by ForeverPlus.
local _, ns = ...
local L = ns.L

local Mover = ns:NewModule("Mover", {
	title = L.MOVER_TITLE,
	order = 100,
	defaults = {
		enabled = true,
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
local displays = {}  -- ForeverPlus displays (coordinates, FPS/MS, …)
local displayOf = {} -- display frame -> entry
local movingKey

-- Everything starts locked; Alt + right-click unlocks single elements and
-- one switch locks everything again.
local function IsLocked(key)
	return ns.db.lockAll or not ns.db.unlocked[key]
end

local RefreshDisplays

local function ToggleLock(key)
	if ns.db.lockAll then
		ns.Print(L.LOCK_ALL_ACTIVE)
		return
	end
	local locked = not IsLocked(key)
	ns.db.unlocked[key] = not locked or nil
	if ns.db.lockMessage then
		ns.Print(locked and L.DISPLAY_LOCKED or L.DISPLAY_UNLOCKED)
	end
	RefreshDisplays()
end

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

local function FindDisplay(region)
	local frame = region
	while frame do
		if displayOf[frame] then
			return displayOf[frame]
		end
		if frame:IsForbidden() or not frame.GetParent then
			return
		end
		frame = frame:GetParent()
	end
end

-- Movable element under the cursor: frame and the key of its saved position.
local function FindTarget(region)
	if not region then
		return
	end
	local entry = FindDisplay(region)
	if entry then
		return entry.frame, entry.key
	end
	local frame = FindWindow(region)
	if frame then
		return frame, frame:GetName()
	end
end

local function ApplyDisplay(entry)
	local frame, data = entry.frame, saved[entry.key]
	frame:SetScale(data and data.scale or 1)
	frame:ClearAllPoints()
	if data and data.x then
		frame:SetPoint("TOPLEFT", entry.relativeTo, "BOTTOMLEFT", data.x, data.y)
	else
		entry.placeDefault(frame)
	end
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

local function Save(frame, key)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then
		return
	end
	local entry = displayOf[frame]
	if entry then
		-- Displays keep their offset to the frame they belong to (e.g. the map).
		local relativeTo = entry.relativeTo
		local factor = relativeTo:GetEffectiveScale() / frame:GetEffectiveScale()
		left, top = left - (relativeTo:GetLeft() or 0) * factor, top - (relativeTo:GetBottom() or 0) * factor
	end
	local data = saved[key] or {}
	data.x, data.y = left, top
	data.scale = data.scale or (frame:GetScale() ~= 1 and frame:GetScale() or nil)
	saved[key] = data
	if entry then
		ApplyDisplay(entry)
	else
		HookWindow(frame)
	end
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
local function StartMoving(frame, key)
	if not frame:IsMovable() then
		frame:SetMovable(true)
	end
	frame:SetClampedToScreen(true)
	startLeft, startTop = frame:GetLeft(), frame:GetTop()
	frame:StartMoving()
	moving, movingKey = frame, key
end

local function StopMoving()
	local frame = moving
	moving = nil
	if not frame then
		return
	end
	frame:StopMovingOrSizing()
	-- Our own database restores the position; keep the client layout cache out of it.
	if frame:GetName() and frame:IsUserPlaced() and not (InCombatLockdown() and frame:IsProtected()) then
		frame:SetUserPlaced(false)
	end
	-- A plain Alt-click must not pin the window to its current position.
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and startLeft and math.abs(left - startLeft) < 1 and math.abs(top - startTop) < 1 then
		return
	end
	Save(frame, movingKey)
end

-- Windows also without Alt, but only on their own background or title area:
-- clicks on buttons, items, lists and other child frames stay untouched.
local wheelWindows = {} -- window -> true when ForeverPlus handles its wheel
local ScaleFrame -- below

-- The plain wheel scales an unlocked window. Locked windows leave the wheel
-- alone, so it keeps its key bindings (camera zoom, action bar paging).
-- Windows that already use the wheel themselves (e.g. merchant pages) keep it.
local function UpdateWindowWheel(frame, key)
	if InCombatLockdown() and frame:IsProtected() then
		return
	end
	if wheelWindows[frame] == nil then
		if frame:IsMouseWheelEnabled() then
			wheelWindows[frame] = false
			return
		end
		wheelWindows[frame] = true
		frame:HookScript("OnMouseWheel", function(self, delta)
			local name = self:GetName()
			if Mover.db.enabled and name and not IsLocked(name) and GetMouseFoci()[1] == self then
				ScaleFrame(self, name, delta)
			end
		end)
	end
	if wheelWindows[frame] then
		frame:EnableMouseWheel(Mover.db.enabled and not IsLocked(key))
	end
end

local function UpdateAllWindowWheels()
	for frame, handled in pairs(wheelWindows) do
		if handled then
			UpdateWindowWheel(frame, frame:GetName())
		end
	end
end

function Mover:GLOBAL_MOUSE_DOWN(_, button)
	if moving then
		return
	end
	local foci = GetMouseFoci()
	local region = foci and foci[1]
	local frame, key = FindTarget(region)
	if not frame then
		return
	end
	local isWindow = not displayOf[frame]
	if isWindow then
		UpdateWindowWheel(frame, key)
	end
	if not IsAltKeyDown() then
		-- Displays handle plain clicks themselves; windows only on their background.
		if not isWindow or region ~= frame then
			return
		end
	end
	if button == "RightButton" then
		ToggleLock(key)
	elseif button == "LeftButton" and not IsLocked(key) then
		StartMoving(frame, key)
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
	local frame, key = FindTarget(region)
	if frame and IsLocked(key) then
		frame = nil
	end
	if frame ~= catcher.target then
		catcher.target, catcher.key = frame, key
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

function ScaleFrame(frame, key, delta)
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
	saved[key] = saved[key] or {}
	saved[key].scale = newScale
	Save(frame, key)
end

catcher:SetScript("OnMouseWheel", function(self, delta)
	ScaleFrame(self.target, self.key, delta)
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
	RefreshDisplays()
	self:ToggleEvent("GLOBAL_MOUSE_DOWN", enabled)
	self:ToggleEvent("GLOBAL_MOUSE_UP", enabled)
	self:ToggleEvent("MODIFIER_STATE_CHANGED", enabled)
	if not enabled then
		StopCatcher()
	end
end

-- Former per-display lock options and display positions.
local LEGACY_LOCKS = {
	{ "Minimap", "lockCoords", "M:MinimapCoords" },
	{ "Minimap", "lockWorldMap", "M:MapCoords" },
	{ "Info", "lockPerformance", "M:Performance" },
}

local function Migrate()
	local db = ns.db
	for _, legacy in ipairs(LEGACY_LOCKS) do
		local moduleDB = db.modules[legacy[1]]
		if moduleDB then
			if moduleDB.lockMessage == false then
				db.lockMessage = false
			end
			moduleDB[legacy[2]], moduleDB.lockMessage = nil, nil
		end
	end
	saved["D:MinimapCoords"], saved["D:Performance"], saved.WorldMapCoords = nil, nil, nil
	-- Blizzard's world map panel was replaced by an own display.
	saved["M:WorldMapCoords"] = nil
end

function Mover:OnInitialize()
	saved = ns.db.frames
	-- Former list of locked elements: everything starts locked now.
	ns.db.locked = nil
	ns.db.unlocked = ns.db.unlocked or {}
	if ns.db.lockAll == nil then
		ns.db.lockAll = false
	end
	if ns.db.lockMessage == nil then
		ns.db.lockMessage = true
	end
	Migrate()
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
	"QuestLogPopupDetailFrame", "TaxiFrame", "AddonList",
	"EncounterJournal", "AchievementFrame", "ClassTrainerFrame", "InspectFrame",
	"MacroFrame", "TimeManagerFrame", "ProfessionsBookFrame",
}
local freed = {}

-- Freed windows that the player has not moved line up to the right of the
-- panels Blizzard still manages, in the order they were opened, so no
-- window covers another whichever opens first.
local MANAGED_AREAS = { "left", "center", "right", "doublewide", "fullscreen" }
local WINDOW_TOP, WINDOW_GAP = -116, 8
local freeOrder = {}

local function RightEdge(frame)
	local right = frame:GetRight()
	if not right then
		return nil
	end
	return right * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function LayoutFreeWindows()
	if not Mover.db.multiWindow or not GetUIPanel then
		return
	end
	local x = 16
	for _, area in ipairs(MANAGED_AREAS) do
		local panel = GetUIPanel(area)
		local right = panel and panel:IsShown() and RightEdge(panel)
		if right then
			x = math.max(x, right + WINDOW_GAP)
		end
	end
	for _, frame in ipairs(freeOrder) do
		if frame:IsShown() and not saved[frame:GetName()] and not (InCombatLockdown() and frame:IsProtected()) then
			local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x * ratio, WINDOW_TOP * ratio)
			x = x + frame:GetWidth() * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() + WINDOW_GAP
		end
	end
end

local function PlaceFreeWindow(frame)
	for i = #freeOrder, 1, -1 do
		if freeOrder[i] == frame then
			table.remove(freeOrder, i)
		end
	end
	freeOrder[#freeOrder + 1] = frame
	LayoutFreeWindows()
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
	-- A managed panel opening or closing moves the freed windows beside it.
	for _, func in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if type(_G[func]) == "function" then
			hooksecurefunc(func, LayoutFreeWindows)
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
-- Movable displays (coordinates, FPS/MS, …): handled like windows
---------------------------------------------------------------------------

-- Own displays also work without Alt: drag moves, right-click locks, the
-- mouse wheel scales. The wheel is only taken while unlocked, so a locked
-- display inside the minimap leaves zooming to the minimap.
function RefreshDisplays()
	local enabled = Mover.db.enabled
	for _, entry in ipairs(displays) do
		entry.frame:EnableMouseWheel(enabled and not IsLocked(entry.key) or false)
	end
	UpdateAllWindowWheels()
end

-- placeDefault(frame) sets the default point; the saved position is kept
-- relative to relativeTo (default UIParent).
function ns:RegisterDisplay(frame, key, placeDefault, relativeTo)
	local entry = { frame = frame, key = "M:" .. key, placeDefault = placeDefault, relativeTo = relativeTo or UIParent }
	displays[#displays + 1] = entry
	displayOf[frame] = entry
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(display)
		if Mover.db.enabled and not moving and not IsLocked(entry.key) then
			StartMoving(display, entry.key)
		end
	end)
	frame:SetScript("OnDragStop", StopMoving)
	frame:HookScript("OnMouseUp", function(_, mouseButton)
		-- Alt + right-click is handled by the global mouse handler.
		if mouseButton == "RightButton" and Mover.db.enabled and not IsAltKeyDown() then
			ToggleLock(entry.key)
		end
	end)
	frame:SetScript("OnMouseWheel", function(display, delta)
		if not IsLocked(entry.key) then
			ScaleFrame(display, entry.key, delta)
		end
	end)
	ApplyDisplay(entry)
	RefreshDisplays()
	return entry
end

function ns:ApplyDisplay(entry)
	ApplyDisplay(entry)
end

function ns:HasSavedPosition(entry)
	local data = saved[entry.key]
	return data and data.x ~= nil
end

function ns:SetAllLocked(locked)
	RefreshDisplays()
	ns.Print(locked and L.LOCK_ALL_DONE or L.UNLOCK_ALL_DONE)
end

function ns:ResetFramePositions()
	for key, data in pairs(saved) do
		local frame = _G[key]
		if data.scale and type(frame) == "table" and frame.SetScale and not frame:IsForbidden()
			and not (InCombatLockdown() and frame:IsProtected()) then
			frame:SetScale(1)
		end
	end
	wipe(saved)
	wipe(ns.db.unlocked)
	RefreshDisplays()
	for _, data in pairs(ns.editFrames or {}) do
		data.reset()
	end
	for _, entry in ipairs(displays) do
		ApplyDisplay(entry)
	end
	ns.Print(L.MOVER_RESET_DONE)
end

Mover.options = {
	{ key = "enabled", type = "toggle", name = L.MOVER_ENABLE, desc = L.MOVER_ENABLE_DESC },
	{ key = "multiWindow", type = "toggle", name = L.MOVER_MULTI, desc = L.MOVER_MULTI_DESC },
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

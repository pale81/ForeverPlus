-- ForeverPlus core: namespace, event dispatch, saved variables and module registry.
local addonName, ns = ...

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
ns.modules = {}
ns.L = ns.L or {}

-- Hidden parent for Blizzard regions we want gone without touching their code paths.
ns.hider = CreateFrame("Frame")
ns.hider:Hide()


---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns.Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverPlus|r: " .. msg)
end

-- Returns font flags with an outline added (nil if an outline is already present).
function ns.OutlineFlags(flags)
	flags = flags or ""
	if flags:find("OUTLINE") then
		return nil
	end
	return flags == "" and "OUTLINE" or (flags .. ", OUTLINE")
end

-- Gives a font object or font string an outline unless it already has one.
function ns.ApplyOutline(object)
	local file, size, flags = object:GetFont()
	if not file then
		return
	end
	local newFlags = ns.OutlineFlags(flags)
	if newFlags then
		object:SetFont(file, size, newFlags)
	end
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
ns.CopyDefaults = CopyDefaults

-- Runs fn now or as soon as combat lockdown ends.
local regenQueue = {}
function ns.RunOutOfCombat(fn)
	if InCombatLockdown() then
		regenQueue[#regenQueue + 1] = fn
	else
		fn()
	end
end

-- Calls fn(…) once the given Blizzard addon is loaded (immediately if already).
function ns.OnAddOnLoaded(name, fn)
	EventUtil.ContinueOnAddOnLoaded(name, fn)
end

---------------------------------------------------------------------------
-- Event dispatcher: one frame, events only registered while someone listens.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listeners = {}

function ns:RegisterEvent(event, owner, fn)
	local set = listeners[event]
	if not set then
		set = {}
		listeners[event] = set
		eventFrame:RegisterEvent(event)
	end
	set[owner] = fn
end

function ns:UnregisterEvent(event, owner)
	local set = listeners[event]
	if not set then
		return
	end
	set[owner] = nil
	if next(set) == nil then
		listeners[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local set = listeners[event]
	if set then
		for owner, fn in pairs(set) do
			fn(owner, event, ...)
		end
	end
end)

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
local ModuleMixin = {}

function ModuleMixin:RegisterEvent(event, fn)
	ns:RegisterEvent(event, self, fn or self[event])
end

function ModuleMixin:UnregisterEvent(event)
	ns:UnregisterEvent(event, self)
end

-- Registers or unregisters an event depending on a condition.
function ModuleMixin:ToggleEvent(event, enabled, fn)
	if enabled then
		self:RegisterEvent(event, fn)
	else
		self:UnregisterEvent(event)
	end
end

-- spec: { title = string, order = number, defaults = table, options = table }
function ns:NewModule(name, spec)
	local module = CreateFromMixins(ModuleMixin, spec or {})
	module.name = name
	self.modules[#self.modules + 1] = module
	self.modules[name] = module
	return module
end

function ns:GetModule(name)
	return self.modules[name]
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DB_VERSION = 1

local function InitDatabase()
	ForeverPlusDB = ForeverPlusDB or {}
	ForeverPlusCharDB = ForeverPlusCharDB or {}
	local db, cdb = ForeverPlusDB, ForeverPlusCharDB

	db.version = db.version or DB_VERSION
	db.modules = db.modules or {}
	db.frames = db.frames or {}
	cdb.modules = cdb.modules or {}

	for _, module in ipairs(ns.modules) do
		db.modules[module.name] = CopyDefaults(module.defaults or {}, db.modules[module.name] or {})
		module.db = db.modules[module.name]
		if module.charDefaults then
			cdb.modules[module.name] = CopyDefaults(module.charDefaults, cdb.modules[module.name] or {})
			module.cdb = cdb.modules[module.name]
		end
	end

	ns.db, ns.cdb = db, cdb
end

-- Resets one module to its defaults (requires a reload to undo hooks cleanly).
function ns:ResetModule(module)
	wipe(module.db)
	CopyDefaults(module.defaults or {}, module.db)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then
			return
		end
		InitDatabase()
		for _, module in ipairs(ns.modules) do
			if module.OnInitialize then
				securecallfunction(module.OnInitialize, module)
			end
		end
		ns:BuildSettings()
	elseif event == "PLAYER_LOGIN" then
		for _, module in ipairs(ns.modules) do
			if module.OnLogin then
				securecallfunction(module.OnLogin, module)
			end
		end
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PLAYER_REGEN_ENABLED" then
		local queue = regenQueue
		regenQueue = {}
		for i = 1, #queue do
			queue[i]()
		end
	end
end)

---------------------------------------------------------------------------
-- Slash command and addon compartment
---------------------------------------------------------------------------
SLASH_FOREVERPLUS1 = "/fp"
SLASH_FOREVERPLUS2 = "/foreverplus"
SlashCmdList.FOREVERPLUS = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "errors" or msg == "fehler" then
		local errors = ns:GetModule("Errors")
		if errors then
			errors:ShowMenu()
		end
	else
		ns:OpenSettings()
	end
end

function ForeverPlus_OnAddonCompartmentClick()
	ns:OpenSettings()
end



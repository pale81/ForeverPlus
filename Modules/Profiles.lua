-- Profiles: a snapshot of the settings of the game (every console setting that differs from its default), the key
-- bindings, the layouts of the Edit Mode and the settings of ForeverPlus, to keep, to bring back and to hand to
-- another character or installation. An automatic backup is made at the first login of a day (the three latest are
-- kept), so a lost setup can be brought back.
local _, ns = ...
local L = ns.L

local Profiles = ns:NewModule("Profiles", {
	title = L.PROFILES_TITLE,
	order = 102,
	defaults = {
		auto = true,
		lastAuto = 0,
	},
})

local MAX_AUTO = 3

-- Console settings that belong to the machine, the account or the client and are not taken along.
local SKIP_EXACT = { portal = true, textLocale = true, audioLocale = true, Sound_OutputDriverName = true,
	cursorSizePreferred = true }
local SKIP_PREFIX = { "CACHE-", "gx", "Gx", "GX" }

local function Skipped(name)
	if SKIP_EXACT[name] then
		return true
	end
	for _, prefix in ipairs(SKIP_PREFIX) do
		if name:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Taking a snapshot
---------------------------------------------------------------------------
local function CollectCVars()
	local result, count = {}, 0
	local get = C_Console and C_Console.GetAllCommands
	local ok, list = pcall(get or function() end)
	local info = C_CVar and C_CVar.GetCVarInfo
	if not (ok and type(list) == "table" and info) then
		return result, 0
	end
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
	for _, entry in ipairs(list) do
		local name = type(entry) == "table" and entry.command
		if type(name) == "string" and not Skipped(name) and (cvarType == nil or entry.commandType == cvarType) then
			local value, default, _, _, locked, secure, readOnly = info(name)
			if value ~= nil and value ~= default and not locked and not secure and not readOnly then
				result[name] = tostring(value)
				count = count + 1
			end
		end
	end
	return result, count
end

local function CollectBindings()
	local result = {}
	if not (GetNumBindings and GetBinding) then
		return result
	end
	for index = 1, ns.Number(GetNumBindings(), 0) do
		local command, _, key1, key2, key3 = GetBinding(index)
		if type(command) == "string" and type(key1) == "string" then
			local keys = { key1 }
			for _, key in ipairs({ key2, key3 }) do
				if type(key) == "string" then
					keys[#keys + 1] = key
				end
			end
			result[command] = keys
		end
	end
	return result
end

local function CollectLayouts()
	local result = {}
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertLayoutInfoToString) then
		return result
	end
	local ok, data = pcall(C_EditMode.GetLayouts)
	if not (ok and type(data) == "table" and type(data.layouts) == "table") then
		return result
	end
	local presets = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Preset
	for index, layout in ipairs(data.layouts) do
		if type(layout) == "table" and (presets == nil or layout.layoutType ~= presets) then
			local done, text = pcall(C_EditMode.ConvertLayoutInfoToString, layout)
			if done and type(text) == "string" then
				result[#result + 1] = { name = layout.layoutName or tostring(index), text = text }
			end
		end
	end
	return result
end

-- The settings of ForeverPlus: its modules, the places of the windows, the locks and the plain switches. What the
-- addon recorded (innkeepers, books, loot, rides …) is data, not settings, and stays out.
local function CollectAddon()
	local db = ns.db
	local copy = { modules = CopyTable(db.modules or {}), frames = CopyTable(db.frames or {}),
		unlocked = CopyTable(db.unlocked or {}), plain = {} }
	for key, value in pairs(db) do
		local kind = type(value)
		if kind == "boolean" or kind == "number" or kind == "string" then
			if key ~= "version" then
				copy.plain[key] = value
			end
		end
	end
	return copy
end

function Profiles.Snapshot()
	local cvars, count = CollectCVars()
	return { time = time(), cvars = cvars, bindings = CollectBindings(), layouts = CollectLayouts(), addon = CollectAddon(),
		build = select(2, GetBuildInfo()), cvarCount = count }
end

---------------------------------------------------------------------------
-- Keeping and listing
---------------------------------------------------------------------------
local function Store()
	ns.db.profiles = ns.db.profiles or {}
	return ns.db.profiles
end

local function ValidateName(name, store, replace)
	name = type(name) == "string" and strtrim(name) or ""
	if name == "" then
		ns.PrintAlways(L.PROFILES_NAME_REQUIRED)
	elseif store[name] and not replace then
		ns.PrintAlways(L.PROFILES_NAME_EXISTS, name)
	else
		return name
	end
end

function Profiles.Save(name, createOnly)
	local store = Store()
	name = ValidateName(name, store, not createOnly)
	if not name then
		return false
	end
	local profile = Profiles.Snapshot()
	profile.automatic = false
	store[name] = profile
	ns.PrintAlways(L.PROFILES_SAVED, name)
	return true, name
end

function Profiles.Rename(oldName, name)
	local store = Store()
	local profile = store[oldName]
	if not profile then
		return false
	end
	name = ValidateName(name, store, type(name) == "string" and strtrim(name) == oldName)
	if not name then
		return false
	end
	if name ~= oldName then
		profile.automatic = false -- A backup kept under a custom name is no longer rotated.
		store[name], store[oldName] = profile, nil
		ns.PrintAlways(L.PROFILES_RENAMED, oldName, name)
	end
	return true, name
end

-- Names, newest first.
function Profiles.List()
	local names = {}
	for name in pairs(Store()) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		local ta, tb = Store()[a].time or 0, Store()[b].time or 0
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	return names
end

function Profiles.Delete(name)
	Store()[name] = nil
end

local function AutoBackup()
	local db = Profiles.db
	if not db.auto or InCombatLockdown() then
		return
	end
	local now = time()
	if now - (db.lastAuto or 0) < 20 * 3600 then
		return
	end
	db.lastAuto = now
	local store, prefix = Store(), L.PROFILES_AUTO_PREFIX
	local autos = {}
	for _, name in ipairs(Profiles.List()) do
		local automatic = store[name].automatic
		if automatic or (automatic == nil and name:sub(1, #prefix) == prefix) then
			autos[#autos + 1] = name
		end
	end
	for index = MAX_AUTO, #autos do
		Profiles.Delete(autos[index])
	end
	local base = prefix .. date("%Y-%m-%d %H:%M", now)
	local name, suffix = base, 2
	while store[name] do
		name = ("%s (%d)"):format(base, suffix)
		suffix = suffix + 1
	end
	local profile = Profiles.Snapshot()
	profile.automatic = true
	store[name] = profile
end

---------------------------------------------------------------------------
-- As text, to take to another installation: "FP1:" and a compact encoding read by a small parser (never run as
-- code, the text may come from someone else). T…E a table of key/value pairs, s<length>:<bytes> a string,
-- n<number>; a number, b1/b0 a boolean. Keys are strings or numbers.
---------------------------------------------------------------------------
local PREFIX, MAX_DEPTH, MAX_TEXT = "FP1:", 32, 4 * 1024 * 1024

local function EncodeValue(value, out)
	local kind = type(value)
	if kind == "table" then
		out[#out + 1] = "T"
		for key, item in pairs(value) do
			local keyKind, itemKind = type(key), type(item)
			if (keyKind == "string" or keyKind == "number")
				and (itemKind == "table" or itemKind == "string" or itemKind == "number" or itemKind == "boolean") then
				EncodeValue(key, out)
				EncodeValue(item, out)
			end
		end
		out[#out + 1] = "E"
	elseif kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		out[#out + 1] = ("n%.17g;"):format(value)
	elseif kind == "boolean" then
		out[#out + 1] = value and "b1" or "b0"
	end
end

function Profiles.Encode(value)
	local out = { PREFIX }
	EncodeValue(value, out)
	return table.concat(out)
end

local function DecodeValue(text, pos, depth)
	local tag = text:sub(pos, pos)
	if tag == "T" then
		if depth >= MAX_DEPTH then return end
		local result = {}
		pos = pos + 1
		while text:sub(pos, pos) ~= "E" do
			if pos > #text then return end
			local key
			key, pos = DecodeValue(text, pos, depth + 1)
			if type(key) ~= "string" and type(key) ~= "number" then return end
			local item
			item, pos = DecodeValue(text, pos, depth + 1)
			if item == nil then return end
			result[key] = item
		end
		return result, pos + 1
	elseif tag == "s" then
		local length, stop = text:match("^(%d+)():", pos + 1)
		length = tonumber(length)
		if not length or stop + length > #text then return end
		return text:sub(stop + 1, stop + length), stop + length + 1
	elseif tag == "n" then
		local digits, stop = text:match("^([%d%.eE%+%-]+);()", pos + 1)
		local number = tonumber(digits)
		if not number or number ~= number or number == math.huge or number == -math.huge then return end
		return number, stop
	elseif tag == "b" then
		local flag = text:sub(pos + 1, pos + 1)
		if flag == "1" or flag == "0" then return flag == "1", pos + 2 end
	end
end

-- The table of an encoded text, or nil if the text is not one (or is damaged).
function Profiles.Decode(text)
	if type(text) ~= "string" then return end
	text = strtrim(text)
	if #text > MAX_TEXT or text:sub(1, #PREFIX) ~= PREFIX then return end
	local value, stop = DecodeValue(text, #PREFIX + 1, 0)
	if type(value) == "table" and stop == #text + 1 then return value end
end

-- Only the parts a profile has, with the expected kinds; everything else of an imported text is dropped.
local function CleanProfile(profile)
	if type(profile) ~= "table" then return end
	local clean = { time = ns.Number(profile.time, time()), build = type(profile.build) == "string" and profile.build or nil,
		cvars = {}, bindings = {}, layouts = {}, cvarCount = 0, automatic = false }
	for name, value in pairs(type(profile.cvars) == "table" and profile.cvars or {}) do
		if type(name) == "string" and type(value) == "string" and not Skipped(name) then
			clean.cvars[name] = value
			clean.cvarCount = clean.cvarCount + 1
		end
	end
	for command, keys in pairs(type(profile.bindings) == "table" and profile.bindings or {}) do
		if type(command) == "string" and type(keys) == "table" then
			local list = {}
			for _, key in ipairs(keys) do
				if type(key) == "string" then list[#list + 1] = key end
			end
			if #list > 0 then clean.bindings[command] = list end
		end
	end
	for _, layout in ipairs(type(profile.layouts) == "table" and profile.layouts or {}) do
		if type(layout) == "table" and type(layout.name) == "string" and type(layout.text) == "string" then
			clean.layouts[#clean.layouts + 1] = { name = layout.name, text = layout.text }
		end
	end
	local addon = profile.addon
	if type(addon) == "table" then
		clean.addon = {}
		for _, part in ipairs({ "modules", "frames", "unlocked", "plain" }) do
			clean.addon[part] = type(addon[part]) == "table" and addon[part] or {}
		end
	end
	return clean
end

function Profiles.ExportText(name)
	local profile = Store()[name]
	return profile and Profiles.Encode({ name = name, profile = profile })
end

-- Keeps the profile of a text under its name (with a number if the name is taken); returns the name or nil.
function Profiles.ImportText(text)
	local data = Profiles.Decode(text)
	local profile = data and CleanProfile(data.profile)
	if not profile then
		ns.PrintAlways(L.PROFILES_IMPORT_INVALID)
		return
	end
	local store = Store()
	local base = type(data.name) == "string" and strtrim(data.name) ~= "" and strtrim(data.name) or L.PROFILES_IMPORT_NAME
	local name, suffix = base, 2
	while store[name] do
		name = ("%s (%d)"):format(base, suffix)
		suffix = suffix + 1
	end
	store[name] = profile
	ns.PrintAlways(L.PROFILES_IMPORTED, name)
	return name
end

---------------------------------------------------------------------------
-- Bringing back
---------------------------------------------------------------------------
local function RestoreCVars(cvars)
	local count = 0
	for name, value in pairs(cvars or {}) do
		if not Skipped(name) and pcall(SetCVar, name, value) then
			count = count + 1
		end
	end
	return count
end

local function RestoreBindings(bindings)
	if not (SetBinding and GetNumBindings and GetBinding and SaveBindings and GetCurrentBindingSet) or InCombatLockdown() then
		return 0
	end
	-- Every key that is bound now is freed first, so no old key stays on a command of the profile.
	for index = 1, ns.Number(GetNumBindings(), 0) do
		local _, _, key1, key2, key3 = GetBinding(index)
		for _, key in ipairs({ key1 or false, key2 or false, key3 or false }) do
			if key then
				SetBinding(key)
			end
		end
	end
	local count = 0
	for command, keys in pairs(bindings or {}) do
		for _, key in ipairs(keys) do
			if SetBinding(key, command) then
				count = count + 1
			end
		end
	end
	SaveBindings(GetCurrentBindingSet())
	return count
end

local function RestoreAddon(saved)
	local db = ns.db
	if type(saved) ~= "table" then
		return
	end
	db.modules = CopyTable(saved.modules or {})
	db.frames = CopyTable(saved.frames or {})
	db.unlocked = CopyTable(saved.unlocked or {})
	for key, value in pairs(saved.plain or {}) do
		db[key] = value
	end
end

-- Puts the layouts of a profile on the clipboard one after the other (the game's own import takes them).
function Profiles.ShowLayouts(owner, name)
	local profile = Store()[name]
	if not profile or #(profile.layouts or {}) == 0 then
		ns.PrintAlways(L.PROFILES_NO_LAYOUTS)
		return
	end
	ns.ShowPopupList(owner, function()
		local items = {}
		for _, layout in ipairs(profile.layouts) do
			items[#items + 1] = {
				text = layout.name,
				onClick = function()
					ns.ShowEditWindow("LayoutText", layout.name, layout.text, CLOSE, nil, L.EDITLAYOUT_HINT)
				end,
			}
		end
		return { title = L.PROFILES_LAYOUTS, items = items }
	end, "ProfileLayouts")
end

local function Load(name)
	local profile = Store()[name]
	if not profile or InCombatLockdown() then
		return
	end
	local cvars = RestoreCVars(profile.cvars)
	local keys = RestoreBindings(profile.bindings)
	RestoreAddon(profile.addon)
	ns.PrintAlways(L.PROFILES_LOADED, name, cvars, keys, #(profile.layouts or {}))
	if #(profile.layouts or {}) > 0 then
		ns.PrintAlways(L.PROFILES_LAYOUTS_HINT)
	end
	ReloadUI()
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
StaticPopupDialogs["FOREVERPLUS_PROFILE_LOAD"] = {
	text = L.PROFILES_CONFIRM_LOAD,
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, name)
		Load(name)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["FOREVERPLUS_PROFILE_DELETE"] = {
	text = L.PROFILES_CONFIRM_DELETE,
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, name)
		Profiles.Delete(name)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local selected

function Profiles.ShowSave()
	local default = date("%Y-%m-%d")
	ns.ShowEditWindow("ProfileName", L.PROFILES_SAVE_TITLE, default, L.PROFILES_SAVE, function(text)
		Profiles.Save(text)
	end, L.PROFILES_SAVE_HINT)
end

function Profiles.ShowList(owner)
	local popup
	local function EditName(oldName)
		popup:Hide()
		local title = oldName and L.PROFILES_RENAME_TITLE or L.PROFILES_CREATE_TITLE
		local action = oldName and L.PROFILES_RENAME or L.PROFILES_CREATE
		ns.ShowEditWindow("ProfileName", title, oldName, action, function(name)
			local ok, savedName
			if oldName then
				ok, savedName = Profiles.Rename(oldName, name)
			else
				ok, savedName = Profiles.Save(name, true)
			end
			if ok then
				selected = savedName
			end
			if owner and owner:IsVisible() then
				Profiles.ShowList(owner)
			end
		end, L.PROFILES_UNIQUE_NAME_HINT)
	end
	popup = ns.ShowPopupList(owner, function()
		local items = {}
		for _, name in ipairs(Profiles.List()) do
			local profile = Store()[name]
			items[#items + 1] = {
				text = ("%s  |cff999999%s · %d|r"):format(name, date("%Y-%m-%d %H:%M", profile.time or 0), profile.cvarCount or 0),
				checked = selected == name or nil,
				onClick = function()
					selected = name
				end,
			}
		end
		return { title = L.PROFILES_LIST, items = items, empty = L.PROFILES_NONE, width = 600,
			footer = { { text = L.PROFILES_CREATE, onClick = function()
				EditName()
			end }, { text = L.PROFILES_LOAD, onClick = function()
				if selected and Store()[selected] then
					StaticPopup_Show("FOREVERPLUS_PROFILE_LOAD", selected, nil, selected)
				end
			end }, { text = L.PROFILES_LAYOUTS, onClick = function()
				if selected then
					Profiles.ShowLayouts(owner, selected)
				end
			end }, { text = L.PROFILES_TEXT, onClick = function()
				popup:Hide()
				local text = selected and Profiles.ExportText(selected) or ""
				ns.ShowEditWindow("ProfileText", L.PROFILES_TEXT_TITLE, text, L.PROFILES_IMPORT, function(pasted)
					if pasted ~= "" and pasted ~= text then
						selected = Profiles.ImportText(pasted) or selected
					end
					if owner and owner:IsVisible() then
						Profiles.ShowList(owner)
					end
				end, L.PROFILES_TEXT_HINT)
			end }, { text = L.PROFILES_RENAME, onClick = function()
				if selected and Store()[selected] then
					EditName(selected)
				end
			end }, { text = L.PROFILES_DELETE, onClick = function()
				if selected and Store()[selected] then
					StaticPopup_Show("FOREVERPLUS_PROFILE_DELETE", selected, nil, selected)
				end
			end } } }
	end, "Profiles")
end

function Profiles:OnLogin()
	ns.After("Profiles: AutoBackup", 15, AutoBackup)
end

Profiles.options = {
	{ key = "auto", type = "toggle", name = L.PROFILES_AUTO, desc = L.PROFILES_AUTO_DESC, new = true },
}

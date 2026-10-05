-- Fonts: global font face and size plus face/size per group of UI fonts.
-- Works on Blizzard's font objects, so every text that uses them follows.
local _, ns = ...
local L = ns.L

local GROUPS = { "small", "normal", "large", "number", "tooltip", "quest", "chat" }
-- Chat window sizes stay with Blizzard's own chat setting.
local NO_SIZE = { chat = true }

local defaults = { face = "", size = 100 }
for _, group in ipairs(GROUPS) do
	defaults["face_" .. group] = ""
	if not NO_SIZE[group] then
		defaults["size_" .. group] = 100
	end
end

local Fonts = ns:NewModule("Fonts", {
	title = L.FONTS_TITLE,
	order = 9.5,
	defaults = defaults,
})

local FACES = {
	{ "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
	{ "Fonts\\ARIALN.TTF", "Arial Narrow" },
	{ "Fonts\\skurri.ttf", "Skurri" },
	{ "Fonts\\MORPHEUS.TTF", "Morpheus" },
}

local originals = {} -- font object name -> { font, face, size, group }
local fontsChanged = false

local function GroupOf(name, size)
	if name:find("Tooltip") then
		return "tooltip"
	elseif name:find("^Chat") then
		return "chat"
	elseif name:find("Number") then
		return "number"
	elseif name:find("^Quest") then
		return "quest"
	elseif size < 11 then
		return "small"
	elseif size < 15 then
		return "normal"
	end
	return "large"
end

-- Remembers face and size of font objects the first time they are seen.
local function Collect()
	local added
	for _, name in ipairs(GetFonts()) do
		if not originals[name] then
			local font = _G[name]
			if type(font) == "table" and font.GetFont and not font:IsForbidden() then
				local face, size = font:GetFont()
				if face and size and size > 0 then
					local entry = { font = font, face = face, size = size, group = GroupOf(name, size) }
					originals[name] = entry
					added = added or {}
					added[#added + 1] = entry
				end
			end
		end
	end
	return added
end

local function IsDefault()
	for key, value in pairs(defaults) do
		if Fonts.db[key] ~= value then
			return false
		end
	end
	return true
end

local function FaceFor(group, originalFace)
	local db = Fonts.db
	local face = db["face_" .. group]
	if face == "" then
		face = db.face
	end
	return face ~= "" and face or originalFace
end

local function Apply(entry)
	local db = Fonts.db
	local scale = db.size / 100 * (db["size_" .. entry.group] or 100) / 100
	local size = floor(entry.size * scale * 2 + 0.5) / 2
	local face = FaceFor(entry.group, entry.face)
	local currentFace, currentSize, flags = entry.font:GetFont()
	if face == currentFace and size == currentSize then
		return
	end
	-- Flags stay untouched (outline from the appearance module).
	if not entry.font:SetFont(face, size, flags or "") then
		entry.font:SetFont(entry.face, size, flags or "")
	end
end

local function ApplyChatWindows()
	local original = originals.ChatFontNormal
	if not original then
		return
	end
	local face = FaceFor("chat", original.face)
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		local currentFace, size, flags = frame:GetFont()
		if currentFace and currentFace ~= face then
			frame:SetFont(face, size, flags or "")
		end
	end
end

-- Face for ForeverPlus' own texts.
function ns.GetFontFace()
	local face = Fonts.db and Fonts.db.face
	return face and face ~= "" and face or STANDARD_TEXT_FONT
end

function Fonts:ApplyAll()
	Collect()
	if IsDefault() and not fontsChanged then
		return
	end
	fontsChanged = true
	for _, entry in pairs(originals) do
		Apply(entry)
	end
	ApplyChatWindows()
	local minimap = ns:GetModule("Minimap")
	if minimap and minimap.UpdateFont then
		minimap:UpdateFont()
	end
end

-- Sliders fire on every step; apply once the value settles.
local applyPending
function Fonts:QueueApply()
	if applyPending then
		return
	end
	applyPending = true
	C_Timer.After(0.2, function()
		applyPending = false
		self:ApplyAll()
	end)
end

function Fonts:OnInitialize()
	self:ApplyAll()
	-- Load on demand addons bring new font objects.
	self:RegisterEvent("ADDON_LOADED", function()
		local added = Collect()
		if added and fontsChanged then
			for _, entry in ipairs(added) do
				Apply(entry)
			end
		end
	end)
end

function Fonts:OnLogin()
	if fontsChanged then
		ApplyChatWindows()
	end
	local function OnNewWindow()
		if fontsChanged then
			ApplyChatWindows()
		end
	end
	hooksecurefunc("FCF_OpenTemporaryWindow", OnNewWindow)
	hooksecurefunc("FCF_OpenNewWindow", OnNewWindow)
end

function Fonts:OnOptionChanged()
	self:QueueApply()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function FaceValues(firstLabel)
	return function()
		local values = { { "", firstLabel } }
		local known = {}
		for _, entry in ipairs(FACES) do
			values[#values + 1] = entry
			known[entry[1]:lower()] = true
		end
		-- Fonts registered by shared media libraries of other addons.
		local media = LibStub and LibStub("LibSharedMedia-3.0", true)
		if media then
			local extra = {}
			for name, path in pairs(media:HashTable("font")) do
				if not known[path:lower()] then
					extra[#extra + 1] = { path, name }
				end
			end
			table.sort(extra, function(a, b)
				return a[2] < b[2]
			end)
			for _, entry in ipairs(extra) do
				values[#values + 1] = entry
			end
		end
		return values
	end
end

local function Percent(value)
	return ("%d %%"):format(value)
end

function Fonts:options()
	local options = {
		{ type = "header", name = L.FONTS_GLOBAL, desc = L.FONTS_GLOBAL_DESC },
		{ key = "face", type = "dropdown", name = L.FONTS_FACE, values = FaceValues(L.FONTS_ORIGINAL) },
		{ key = "size", type = "slider", name = L.FONTS_SIZE, min = 50, max = 200, step = 5, format = Percent },
	}
	for _, group in ipairs(GROUPS) do
		options[#options + 1] = { type = "header", name = L["FONTS_GROUP_" .. group], desc = L["FONTS_GROUP_" .. group .. "_DESC"] }
		options[#options + 1] = { key = "face_" .. group, type = "dropdown", name = L.FONTS_FACE, values = FaceValues(L.FONTS_USE_GLOBAL) }
		if not NO_SIZE[group] then
			options[#options + 1] = { key = "size_" .. group, type = "slider", name = L.FONTS_SIZE, min = 50, max = 200, step = 5, format = Percent }
		end
	end
	return options
end

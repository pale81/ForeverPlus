-- Minimal WoW API mock: unknown globals become permissive mocks.
local Mock
local mockMeta = {}
mockMeta.__index = function(t, k)
	local m = Mock(rawget(t, "__name") .. "." .. tostring(k))
	rawset(t, k, m)
	return m
end
mockMeta.__call = function(self, ...) return Mock(rawget(self, "__name") .. "()") end
mockMeta.__tostring = function(t) return "Mock<" .. rawget(t, "__name") .. ">" end
function Mock(name) return setmetatable({ __name = name }, mockMeta) end

-- Frames
frameMeta = {}
function NewFrame(kind, name)
	local f = setmetatable({ __name = "Frame:" .. tostring(name), scripts = {}, shown = true, alpha = 1, w = 40, h = 40 }, frameMeta)
	if name then _G[name] = f end
	return f
end
frameMeta.__index = function(t, k)
	local methods = {
		SetScript = function(self, s, fn) self.scripts[s] = fn end,
		GetScript = function(self, s) return self.scripts[s] end,
		HookScript = function(self, s, fn)
			local previous = self.scripts[s]
			self.scripts[s] = previous and function(...) previous(...) fn(...) end or fn
		end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		SetShown = function(self, v) self.shown = v and true or false end,
		IsShown = function(self) return self.shown end, IsVisible = function(self) return self.shown end,
		GetAlpha = function(self) return self.alpha end, SetAlpha = function(self, a) self.alpha = a end,
		SetRotation = function(self, angle) self.rotation = angle end,
		SetVertexColor = function(self, r, g, b) self.vertexColor = { r, g, b } end,
		GetWidth = function(self) return self.w end, GetHeight = function(self) return self.h end,
		GetSize = function(self) return self.w, self.h end,
		GetVerticalScroll = function(self) return rawget(self, "verticalScroll") or 0 end,
		SetVerticalScroll = function(self, offset) self.verticalScroll = offset end,
		CreateTexture = function(self) return NewFrame("Texture") end,
		CreateLine = function(self)
			local line = NewFrame("Line")
			self.lines = rawget(self, "lines") or {}
			self.lines[#self.lines + 1] = line
			return line
		end,
		SetStartPoint = function(self, ...) self.startPoint = { ... } end,
		SetEndPoint = function(self, ...) self.endPoint = { ... } end,
		SetThickness = function(self, t) self.thickness = t end,
		CreateFontString = function(self) return NewFrame("FontString") end,
		CreateMaskTexture = function(self) return NewFrame("Mask") end,
		CreateAnimationGroup = function(self) return NewFrame("AG") end,
		CreateAnimation = function(self) return NewFrame("Anim") end,
		GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
		GetStringWidth = function() return 80 end, GetStringHeight = function() return 12 end,
		GetName = function(self) return rawget(self, "__name") end,
		GetFrameLevel = function() return 1 end, GetScale = function() return 1 end, GetEffectiveScale = function() return 1 end,
		IsForbidden = function() return false end, IsProtected = function() return false end,
		GetLeft = function() return 10 end, GetTop = function() return 500 end,
		GetHighlightTexture = function() return NewFrame("Texture") end,
		GetBorderColor = function() return 1, 1, 1, 1 end,
		GetID = function() return 1 end,
		IsObjectType = function() return true end,
		IsMovable = function() return false end,
		EnumerateValidItems = function() return ipairs({}) end,
		GetCount = function() return 0 end,
		GetChildren = function() return end,
		GetClampRectInsets = function(self) return rawget(self, 'clamp') and unpack(self.clamp) or -32, 25, 60, -32 end,
		SetClampRectInsets = function(self, ...) self.clamp = { ... } end,
		SetAttribute = function(self, key, value)
			local attrs = rawget(self, "attributes")
			if not attrs then
				attrs = {}
				rawset(self, "attributes", attrs)
			end
			attrs[key] = value
		end,
		GetAttribute = function(self, key)
			local attrs = rawget(self, "attributes")
			return attrs and attrs[key] or nil
		end,
	}
	if methods[k] then return methods[k] end
	local child = NewFrame("child", nil)
	rawset(t, k, child)
	return child
end
frameMeta.__call = function() return nil end

CreateFrame = function(kind, name) return NewFrame(kind, name) end

-- Known API stubs
UnitClass = function() return "Mage", "MAGE", 8 end
ShowUIPanel, HideUIPanel, UpdateUIPanelPositions = function() end, function() end, function() end
UnitFactionGroup = function() return "Alliance" end
GetLocale = function() return os.getenv("LOC") or "enUS" end
InCombatLockdown = function() return false end
hooksecurefunc = function(a, b, c)
	if type(a) == "table" then assert(a[b] ~= nil, "hooksecurefunc: table lacks " .. tostring(b)) end
	if type(a) == "string" then assert(type(_G[a]) ~= "nil", "hooksecurefunc missing global " .. a) end
end
securecallfunction = function(fn, ...) return fn(...) end
local plainXpcall = xpcall
xpcall = function(fn, handler, ...) -- the game's xpcall passes arguments on
	local args, n = { ... }, select("#", ...)
	return plainXpcall(function() return fn(unpack(args, 1, n)) end, handler)
end
geterrorhandler = function() return function(e) io.stderr:write("ERROR: " .. tostring(e) .. "\n" .. debug.traceback() .. "\n") os.exit(1) end end
function NewFont(name, size)
	local f = { face = "Fonts\\FRIZQT__.TTF", size = size, flags = "" }
	function f:GetFont() return self.face, self.size, self.flags end
	function f:SetFont(face, sz, flags) assert(type(face) == "string" and type(sz) == "number" and type(flags) == "string", "SetFont args") self.face, self.size, self.flags = face, sz, flags return true end
	function f:IsForbidden() return false end
	function f:GetTextColor() return self.r or 1, self.g or 1, self.b or 1 end
	_G[name] = f
	return f
end
NewFont("GameFontNormal", 12); NewFont("GameFontNormalSmall", 10); NewFont("GameFontNormalHuge", 20)
NewFont("GameTooltipText", 12); QuestFont = nil NewFont("NumberFontNormal", 14); NewFont("ChatFontNormal", 14); NewFont("QuestFont", 13); QuestFont.r, QuestFont.g, QuestFont.b = 0, 0, 0; QuestFont.flags = "OUTLINE"
GetFonts = function() return { "GameFontNormal", "GameFontNormalSmall", "GameFontNormalHuge", "GameTooltipText", "NumberFontNormal", "ChatFontNormal", "QuestFont" } end
PixelUtil = { GetNearestPixelSize = function(s) return s end }
MenuResponse = { Refresh = 2, CloseAll = 4 }
local postCalls = {}
TooltipDataProcessor = {
	itemPostCalls = {},
	AddTooltipPostCall = function(t, fn)
		postCalls[#postCalls + 1] = fn
		if t == Enum.TooltipDataType.Item then
			local callbacks = TooltipDataProcessor.itemPostCalls
			callbacks[#callbacks + 1] = fn
		end
	end,
}
_G.TEST_POSTCALLS = postCalls
CHAT_FRAMES = { "ChatFrame1" }
ChatFrame1 = NewFrame("ScrollingMessageFrame", "ChatFrame1")
ChatFrame1.editBox = NewFrame("EditBox", "ChatFrame1EditBox")
ChatFrame1.editBox.focusLeft = NewFrame("T"); ChatFrame1.editBox.focusMid = NewFrame("T"); ChatFrame1.editBox.focusRight = NewFrame("T")
ChatFrame1.Background = NewFrame("T")
NewFrame("Button", "ChatFrame1Tab")
for _, n in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "Minimap", "MinimapCluster",
	"ScriptErrorsFrame", "DressUpFrame", "MainMenuBarBackpackButton", "MicroMenuContainer", "BagsBar", "ObjectiveTrackerFrame",
	"QuestObjectiveTracker", "UIParent", "WorldMapFrame", "GameTooltip", "MainActionBar", "QuestInfoFrame", "MerchantFrame",
	"ContainerFrame1", "ContainerFrameCombinedBags", "FramePositionDelegate", "ActionBarButtonEventsFrame", "BuffFrame", "MinimapBackdrop" }) do NewFrame("Frame", n) end
NewFrame("Button", "PlayerFrame").unit = "player"
PlayerFrame.PlayerFrameContainer = NewFrame("Frame")
PlayerFrame.PlayerFrameContainer.PlayerPortrait = false
ContainerFrameContainer = { ContainerFrames = {} }
WorldMapFrame.EnumeratePinsByTemplate = function() return function() end end
ActionBarButtonEventsFrame.frames = {}
BuffFrame.auraFrames = { NewFrame("Aura") }
BuffFrame.auraFrames[1].Icon = NewFrame("Icon")
MainMenuBarBackpackButton.FreeSlots = NewFrame("FS")
MinimapCluster.DielFrame = NewFrame("Frame")
ScriptErrorsFrame.seen = {}
GameTooltip.StatusBar = NewFrame("StatusBar")
QuestObjectiveTracker.Header = { Text = NewFrame("FS") }
QuestScrollFrame = { titleFramePool = { EnumerateActive = function() return function() end end } } -- empty quest log (the mock iterates forever)
ObjectiveTrackerFrame.Header = { Text = NewFrame("FS") }
MainActionBar.EndCaps = { LeftEndCap = NewFrame("F"), RightEndCap = NewFrame("F") }
MainActionBar.EndCaps.LeftEndCap.Texture = NewFrame("T"); MainActionBar.EndCaps.RightEndCap.Texture = NewFrame("T")
DressUpFrame.ModelScene = NewFrame("MS"); DressUpFrame.CustomSetDetailsPanel = NewFrame("P")
MinimapCluster.DielFrame = NewFrame("Diel")
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
C_Timer = { NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } if rawget(_G, "RUN_TICKERS") then repeat fn(t) until t.dead end return t end, After = function() end, NewTimer = function() return { Cancel = function() end } end }
C_Map = { GetBestMapForUnit = function() return 1453 end, GetPlayerMapPosition = function() return nil end,
	GetMapInfo = function(id) return { mapType = 3, name = "x", mapID = id } end, GetMapChildrenInfo = function() return {} end,
	GetAreaInfo = function() return nil end,
	GetMapWorldSize = function() return 1000, 700 end, GetWorldPosFromMapPos = function() return nil end,
	GetMapPosFromWorldPos = function() return nil end, GetMapRectOnMap = function() return nil end }
C_ClassColor = { GetClassColor = function(c, t) assert(t == nil, "GetClassColor extra arg") return { GetRGB = function() return 1, 1, 1 end, WrapTextInColorCode = function(_, x) return x end } end }
Enum = Mock("Enum"); Enum.ItemArmorSubclass = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }; Enum.UIMapType = { Zone = 3 }; Enum.ItemQuality = { Poor = 0, Uncommon = 2 }
Enum.ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4 }
Enum.BankType = { Character = 0, Account = 2 }
Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9 = 6, 14
Enum.BagIndex.Characterbanktab = -2
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i) return "Prof", 1, 150, 300, 0, 0, i == 1 and 171 or 185 end
C_Item = Mock("C_Item"); C_Item.IsItemDataCachedByID = function() return true end
C_Item.GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 9, 5 end
C_TooltipInfo = { GetItemByID = function() return { lines = {} } end, GetBagItem = function() return { lines = {} } end,
	GetUnit = function() return { lines = {} } end }
Enum.TooltipDataLineType = { ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46 }
C_Minimap = { GetViewRadius = function() return 200 end }
GetCVarBool = function() return false end
GetCVar = function() return "1" end
debugprofilestop = function() return os.clock() * 1000 end
SetCVar = function() end
ITEM_SPELL_KNOWN = "Already known"
YES, NO = "Yes", "No"
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED = 16, 17, 18
Settings = Mock("Settings"); Settings.VarType = { Boolean = "boolean", Number = "number", String = "string" }
Settings.RegisterAddOnSetting = function(cat, var, key, tbl, t, name, def)
	assert(type(tbl) == "table" and tbl[key] ~= nil, "setting value nil " .. var)
	assert(type(tbl[key]) == t, "type mismatch " .. var .. " " .. type(tbl[key]) .. " vs " .. t)
	return Mock("setting")
end
SettingsPanel = { GetLayout = function() return { AddInitializer = function(_, i) assert(i, "nil initializer") end } end }
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
MapCanvasPinMixin = {}
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage" }
select = select
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
DEFAULT_CHATFRAME_ALPHA = 0.25
BACKPACK_CONTAINER, NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0, 4, 5
C_Container = { GetContainerNumFreeSlots = function() return 3, 0 end, GetContainerNumSlots = function() return 16 end, GetContainerItemInfo = function() return nil end, UseContainerItem = function() end, GetContainerItemLink = function() end, SortBags = function() end, GetBagSlotFlag = function() return false end, GetBackpackSellJunkDisabled = function() return false end, GetBackpackAutosortDisabled = function() return false end, PickupContainerItem = function() end }
GetQuestLogSpecialItemInfo = function() end
C_QuestLog = { GetQuestWatchType = function() return nil end, IsOnQuest = function() return false end, GetNumQuestWatches = function() return 0 end, GetInfo = function() return nil end, IsComplete = function() return false end, GetNumQuestLogEntries = function() return 9, 7 end, GetMaxNumQuestsCanAccept = function() return 25 end }
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
TRACKER_HEADER_QUESTS = "Quests"
C_Spell = { GetSpellName = function(id) return "Spell"..id end, GetSpellTexture = function() return 1 end }
C_SpellBook = { IsSpellKnown = function() return true end, FindSpellBookSlotForSpell = function() return 1 end }
C_UnitAuras = { GetAuraDataBySpellName = function() return nil end }
GetTime = function() return 100 end
UnitIsDeadOrGhost = function() return false end
min, max, floor = math.min, math.max, math.floor
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetMouseFoci = function() return {} end
GetCursorDelta = function() return 0, 0 end
IsMouseButtonDown = function() return false end
UnitChannelInfo = function() end
UnitOnTaxi = function() return false end
IsFlying = function() return false end
GetNumTrainerServices = function() return 0 end
GetMoney = function() return 0 end
local function Color(r, g, b) return { r = r, g = g, b = b, GetRGB = function() return r, g, b end, WrapTextInColorCode = function(_, t) return "<" .. t .. ">" end } end
NORMAL_FONT_COLOR, GREEN_FONT_COLOR, ORANGE_FONT_COLOR, RED_FONT_COLOR = Color(1, .82, 0), Color(0, 1, 0), Color(1, .5, 0), Color(1, 0, 0)
DISABLED_FONT_COLOR, HIGHLIGHT_FONT_COLOR = Color(.5, .5, .5), Color(1, 1, 1)
UnitName = function() return "Helaku" end
time = os.time
C_Texture = { GetAtlasInfo = function() return { width = 64, height = 64, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
GetRealmName = function() return "Forever" end
GetNetStats = function() return 0, 0, 30, 45 end
GetFramerate = function() return 59.7 end
RequestTimePlayed = function() end
SecondsToTime = function(s) return tostring(s) .. "s" end
C_AddOnProfiler = { IsEnabled = function() return true end, GetAddOnMetric = function(n) return n == "Slow" and 6.2 or 0.4 end }
C_AddOns.GetNumAddOns = function() return 2 end
C_AddOns.IsAddOnLoaded = function() return true end
C_AddOns.GetAddOnInfo = function(i)
	if i == 1 then return "Slow", "|cffff0000Slow|r Addon" end
	if i == 2 then return "Fast", "Fast" end
	return i, i
end
issecretvalue = function() return false end
issecrettable = function() return false end
MerchantSellAllJunkButton = CreateFrame("Button"); MerchantSellAllJunkButton.Icon = MerchantSellAllJunkButton:CreateTexture()
ProfessionsFrame = false -- profession tests install their own frame
SlashCmdList = {}
setmetatable(_G, { __index = function(_, k) return Mock(k) end })

dofile("qdb.lua")
-- Load files from the TOC
root = arg[1]
tinsert, tremove = table.insert, table.remove
SELL_PRICE = "Verkaufspreis"
strsplit = function(sep, str)
	local out, pos = {}, 1
	while true do
		local a, b = str:find(sep, pos, true)
		if not a then out[#out + 1] = str:sub(pos) break end
		out[#out + 1] = str:sub(pos, a - 1)
		pos = b + 1
	end
	return unpack(out)
end
GetMaxLevelForPlayerExpansion = function() return 60 end
C_SpellBook = { GetCurrentLevelSpells = function(l) if l == 10 then return { 101, 102 } end return {} end, GetNumSpellBookSkillLines = function() return 0 end, IsSpellKnown = function(id) return id == 101 end }
IsPlayerSpell = function(id) return id == 101 end
UnitLevel = function() return 20 end
ns = {}
local events = {}
for line in io.lines(root .. "/ForeverPlus.toc") do
	if not line:match("^##") and line:match("%.lua$") then
		local path = root .. "/" .. line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("ForeverPlus", ns)
	end
end
;(function()
	local savedLocale = GetLocale
	local english, german = {}, {}
	assert(loadfile(root .. "/Locales/enUS.lua"))("ForeverPlus", english)
	german.L = {}
	GetLocale = function() return "deDE" end
	assert(loadfile(root .. "/Locales/deDE.lua"))("ForeverPlus", german)
	GetLocale = savedLocale
	for key, value in pairs(english.L) do
		assert(type(german.L[key]) == type(value), "missing or mismatched German locale key: " .. key)
	end
	for key in pairs(german.L) do
		assert(rawget(english.L, key) ~= nil, "missing English locale key: " .. key)
	end
	for id, vendor in pairs(ns.RadarData.vendors) do
		if vendor[2] then
			local title = strtrim(vendor[2]:match("^(.-)> %[") or vendor[2])
			assert(german.L.RADAR_VENDOR_TITLES[title], "missing German title for recipe vendor " .. id .. ": " .. title)
		end
	end
	print("locale coverage OK")
end)()
-- ADDON_LOADED + PLAYER_LOGIN
local loader
for k, v in pairs(_G) do end
-- find the loader frame: the one with ADDON_LOADED script is created in Core; call modules directly
ForeverPlusDB, ForeverPlusCharDB = nil, nil
local f = io.open(root .. "/Core/Core.lua"):read("*a")
-- Simulate the loader
ForeverPlusDB = {}
ForeverPlusCharDB = {}
ForeverPlusDB.modules, ForeverPlusDB.frames, ForeverPlusCharDB.modules = {}, {}, {}
for _, m in ipairs(ns.modules) do
	ForeverPlusDB.modules[m.name] = ns.CopyDefaults(m.defaults or {}, {})
	m.db = ForeverPlusDB.modules[m.name]
	if m.charDefaults then ForeverPlusCharDB.modules[m.name] = ns.CopyDefaults(m.charDefaults, {}); m.cdb = ForeverPlusCharDB.modules[m.name] end
end
ns.db, ns.cdb = ForeverPlusDB, ForeverPlusCharDB
for _, m in ipairs(ns.modules) do if m.OnInitialize then m:OnInitialize() end end
ns:BuildSettings()
for _, m in ipairs(ns.modules) do if m.OnLogin then m:OnLogin() end end
for _, m in ipairs(ns.modules) do
	if m.OnOptionChanged and m.db then
		for k, v in pairs(m.db) do if type(v) ~= "table" then m:OnOptionChanged(k, v, {}) end end
	end
end
print("OK: " .. #ns.modules .. " modules initialised")
;(function()
	local tooltip = ns:GetModule("Tooltip")
	local german = GetLocale() == "deDE"
	local use = german and "Benutzen: Stellt im Verlauf von 18 Sek. 58 Punkt(e) Gesundheit wieder her. Ihr müsst beim Essen sitzen bleiben."
		or "Use: Restores 58 health over 18 sec. Must remain seated while eating."
	local buff = german and "Wenn Ihr mindestens 10 Sek. mit Essen verbringt, werdet Ihr satt und erhaltet 15 Min. lang 3 Angelfertigkeit."
		or "If you spend at least 10 seconds eating, you will become well fed and gain 3 Fishing Skill for 15 min."
	local extra = german and "Außerdem wird die durch Siege erhaltene Erfahrung um 5% erhöht. (1 Sek. Abklingzeit)"
		or "Also increases experience gained from victories by 5%. (1 Sec Cooldown)"
	local tip = { GetName = function() return "FoodTestTooltip" end, NumLines = function() return 2 end,
		IsForbidden = function() return false end }
	local data = { lines = { { type = 22, leftText = "Lochfrenzy Supreme" }, { type = 0 } } }
	local function Render(text)
		_G.FoodTestTooltipTextLeft2 = { GetText = function() return text end, SetText = function(_, value) text = value end }
		for _, callback in ipairs(TooltipDataProcessor.itemPostCalls) do
			callback(tip, data)
		end
		_G.FoodTestTooltipTextLeft2 = nil
		return text
	end
	local plain = use .. " " .. buff .. " " .. extra
	local expectedBonus = german and "Satt: <+3 Angelfertigkeit> (<15 Min.>)" or "Well Fed: <+3 Fishing Skill> (<15 min.>)"
	local expectedExtra = german and "Außerdem wird die <durch Siege erhaltene Erfahrung um 5%> erhöht. (1 Sek. Abklingzeit)"
		or "Also increases <experience gained from victories by 5%>. (1 Sec Cooldown)"
	assert(Render(plain) == table.concat({ use, expectedBonus, expectedExtra }, "\n"),
		"item callback highlights the displayed buff and its duration, omitting the standard eating time")
	local customWait = german and "Nach mindestens 20 Sek. Essen." or "After at least 20 seconds of eating."
	assert(Render(use .. " " .. buff:gsub("10 ", "20 ")) == table.concat({ use, expectedBonus, customWait }, "\n"),
		"an unusual eating time remains visible")
	local green = "|cnGREEN_FONT_COLOR:"
	local marked = green .. use .. "|n" .. buff:gsub("10 ", "10\194\160"):gsub("15 ", "15\226\128\175") .. "|r"
	local markedResult = green .. use .. "\n" .. expectedBonus:gsub(">", ">" .. green) .. "|r"
	assert(Render(marked) == markedResult, "named colour, encoded newline and nonbreaking spaces do not prevent formatting")
	local hex = "|cff00ff00"
	assert(Render(hex .. use .. " " .. buff:gsub("%.$", "") .. "|r") == markedResult:gsub(green, hex):gsub("(min)%.", "%1"),
		"hex colour and food text without final punctuation are supported")
	assert(Render(use) == use, "plain recovery stays with the native tooltip")
	tooltip.db.foodBuffs = false
	assert(Render(plain) == plain, "setting disables the replacement")
	tooltip.db.foodBuffs = true
	print("food tooltip layout OK")
end)()
-- Exercise minimap pin positioning with a player position in Stormwind.
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.45, 0.6 end } end
GetPlayerFacing = function() return 1.0 end
GetCVarBool = function(k) return k == "rotateMinimap" end
local radar = ns:GetModule("RecipeRadar")
radar:Apply()
-- Buff reminder with a present aura (permanent) and a timed one
C_UnitAuras.GetAuraDataBySpellName = function(_, name) return { expirationTime = name == "Spell1459" and 0 or 400 } end
ns:GetModule("Buffs"):OnOptionChanged("threshold")
-- Errors menu
MenuUtil = { CreateContextMenu = function(owner, gen)
	local root = setmetatable({}, { __index = function() return function() return {} end end })
	gen(owner, root)
end }
ns:GetModule("Errors"):ShowMenu()
-- Tooltip unit price path
local tt = ns:GetModule("Tooltip")
-- Tooltip quality border
C_Item.GetItemQualityByID = function() return 4 end
C_Item.GetItemQualityColor = function() return 0.6, 0.2, 1, "ffa335ee" end
for _, fn in ipairs(TEST_POSTCALLS) do fn(GameTooltip, { id = 1234, hyperlink = "item:1234" }) end
assert(QuestFont.flags == "", "dark font outline removed: " .. QuestFont.flags)
assert(GameFontNormal.flags == "OUTLINE", "light font outlined")
-- Fonts
local fonts = ns:GetModule("Fonts")
fonts.db.face = "Fonts\\ARIALN.TTF"; fonts.db.size = 120; fonts.db.size_tooltip = 150; fonts.db.face_chat = "Fonts\\skurri.ttf"
fonts:ApplyAll()
assert(GameFontNormal.size == 14.5 and GameFontNormal.face == "Fonts\\ARIALN.TTF", "global font " .. GameFontNormal.size)
assert(GameTooltipText.size == 21.5, "tooltip size " .. GameTooltipText.size)
assert(ChatFontNormal.face == "Fonts\\skurri.ttf", "chat face")
for k, v in pairs(fonts.defaults) do fonts.db[k] = v end
fonts:ApplyAll()
assert(GameFontNormal.size == 12 and GameFontNormal.face == "Fonts\\FRIZQT__.TTF", "restore")
do
-- Blizzard's text size manager scales tooltip text by 1.2 and set its height back: ours comes again, scale included
local savedManager = TextSizeManager
TextSizeManager = { GetFonts = function() return { GameTooltipText = { baseHeight = 12 } } end, GetScale = function() return 1.2 end }
fonts.db.size_tooltip = 150
fonts:ApplyAll()
assert(GameTooltipText.size == 21.5, "tooltip with Blizzard's scale " .. GameTooltipText.size)
GameTooltipText:SetFont(GameTooltipText.face, 14.4, "")
fonts:ApplyAll()
assert(GameTooltipText.size == 21.5, "set again after Blizzard's update " .. GameTooltipText.size)
assert(GameFontNormal.size == 12, "fonts outside Blizzard's list unscaled")
for k, v in pairs(fonts.defaults) do fonts.db[k] = v end
fonts:ApplyAll()
TextSizeManager = savedManager
end
print("fonts OK")
-- Junk list + key binding
items = ns:GetModule("Items")
items.db.junk[5] = true; items.db.junk[6] = true
C_Item.GetItemNameByID = function(id) return id == 5 and "Bbb" or nil end
C_Item.RequestLoadItemDataByID = function() end
C_Item.GetItemIconByID = function() return 123 end
CreateColor = function() return { WrapTextInColorCode = function(_, t) return "|cff" .. t end } end
local clicked
MenuUtil.CreateContextMenu = function(owner, gen)
	local root = {}
	function root.SetScrollMode() end
	function root.CreateTitle() end
	function root.CreateDivider() end
	function root.CreateButton(_, text, cb) print("  menu:", text) clicked = clicked or cb return { SetTooltip = function() end } end
	gen(owner, root)
end
realPopup = ns.ShowPopupList
ns.ShowPopupList = function(_, build)
	local data = build()
	for _, item in ipairs(data.items) do print("  popup:", item.text) end
	clicked = data.items[1].onClick
end
items:ShowJunkMenu()
clicked()
ns.ShowPopupList = realPopup
local n = 0 for _ in pairs(items.db.junk) do n = n + 1 end
assert(n == 1, "junk removed")
local btn = NewFrame("Button")
btn.GetBagID = function() return 0 end
GetMouseFoci = function() return { btn } end
C_Container.GetContainerItemInfo = function() return { itemID = 77, hyperlink = "[x]" } end
ns.Print = function() end
ForeverPlus_ToggleJunkUnderMouse()
assert(items.db.junk[77], "binding marks")
ForeverPlus_ToggleJunkUnderMouse()
assert(not items.db.junk[77], "binding unmarks")
print("junk OK")
print("all paths OK")
-- Recipe radar against real QuestieDB Forever data
RUN_TICKERS = true; local perfTicker = nil
C_Timer.After = function(_, fn) fn() end
C_Item.GetItemNameByID = function(id) return "Item" .. id end
C_Item.GetItemIconByID = function() return 1 end
C_TooltipInfo.GetItemByID = function() return { lines = {} } end
Enum.TooltipDataLineType = { UsageRequirement = 43 }
Enum.TooltipDataUsageRequirementType = { NotAlreadyKnown = 14, Skill = 2 }
local radar = ns:GetModule("RecipeRadar")
radar.indexing = nil
radar:OnLogin()
radar:Apply()
local counted = 0
for _, id in ipairs({ 1453, 1454, 1455, 1413, 1446 }) do
	local n = 0
	C_Map.GetBestMapForUnit = function() return id end
	radar:Apply()
end
do
	local function uv(fn, name) for i = 1, 200 do local n, v = debug.getupvalue(fn, i) if not n then return end if n == name then return v end end end
	local refresh = uv(radar.Apply, "Refresh")
	local rm = uv(refresh, "RefreshMinimap")
	local gv = uv(rm, "GetVendors")
	local vbm = uv(gv, "vendorsByMap")
	local maps, total = 0, 0
	for _, list in pairs(vbm) do maps = maps + 1 total = total + #list end
	print("radar vendors", maps, total, "ready", uv(gv, "indexReady"))
	-- bundled data: Heldan Galesong (4307) sells in Darkshore, for the Alliance only
	local bundledVendors = radar.bundledVendors
	assert(bundledVendors[4307] and bundledVendors[4307].team == "A" and bundledVendors[4307].name == "Heldan Galesong", "bundled vendor")
	assert(radar.bundledVendors[3005] and radar.bundledVendors[3005].team == "H", "vendor from the Efficient Games data")
	local found
	for _, v in ipairs(vbm[1439] or {}) do if v.npc == 4307 then found = v end end
	assert(found and found.x == 37 and found.y == 56.4 and #found.items == 4, "bundled vendor on the Darkshore map")
	local fixtureMap, itemID = 99999, found.items[1]
	local skill = uv(gv, "RecipeStatus")
	local skills, recipes = uv(skill, "skills"), uv(skill, "recipes")
	local profession = recipes[itemID].skill
	local savedRank, savedMap, savedCount = skills[profession], C_Map.GetBestMapForUnit, C_Item.GetItemCount
	local savedRefresh, reads = ns.MapSymbols.Refresh, 0
	vbm[fixtureMap] = {
		{ npc = 1, team = "N", x = 25, y = 25, items = { itemID } },
		{ npc = 2, team = "N", x = 50, y = 50, items = { itemID } },
	}
	skills[profession] = 60
	C_Map.GetBestMapForUnit = function() return fixtureMap end
	local owned = 0
	C_Item.GetItemCount = function(id)
		if id == itemID then reads = reads + 1 return owned end
		return savedCount(id)
	end
	local counts
	local radarSource
	for _, source in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		if uv(source, "GetVendors") == gv then
			radarSource = source
			break
		end
	end
	assert(radarSource, "the world map has a radar source")
	ns.MapSymbols.Refresh = function()
		counts = 0
		radarSource(fixtureMap, function() counts = counts + 1 end)
	end
	refresh()
	assert(reads == 1 and counts == 2, "the minimap and world map share one inventory check per recipe")
	owned = 1
	refresh()
	assert(reads == 2 and counts == 0, "the next refresh sees the newly collected recipe")
	vbm[fixtureMap], skills[profession] = nil, savedRank
	C_Map.GetBestMapForUnit, C_Item.GetItemCount, ns.MapSymbols.Refresh = savedMap, savedCount, savedRefresh
	refresh()
end
local P = ns.PrintAlways; ns.PrintAlways = function(m, ...) print("  " .. m:format(...)) end; radar:PrintStatus(); ns.PrintAlways = P
print("radar OK")
-- Upgrade arrow logic (Shaman level 20, enhancement)
function upvalue(fn, name)
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if not n then return end
		if n == name then return v end
	end
end
;(function()
	local bankView = ns:GetModule("BankView")
	local listeners = upvalue(ns.RegisterEvent, "listeners")
	local buttons = upvalue(bankView.OnOptionChanged, "buttons")
	local savedBank, savedSlots, savedInfo = C_Bank, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
	local available, loaded, scans = true, false, 0
	local content = {
		[6] = { itemID = 2589, stackCount = 19, hyperlink = "|Hitem:2589|h[Leinenstoff]|h", iconFileID = 132889 },
		[7] = { itemID = 2592, stackCount = 4, itemName = "Wollstoff" },
		[8] = { itemID = 4306, stackCount = 2, itemName = "Seidenstoff" },
	}
	C_Bank = {
		CanViewBank = function(bankType) return available and bankType == Enum.BankType.Character end,
		FetchPurchasedBankTabIDs = function() return loaded and { 6, 7, 8 } or { 6, 7 } end,
		FetchMaxNumBankTabs = function() return 4 end,
	}
	C_Container.GetContainerNumSlots = function(bag)
		scans = scans + 1
		if bag == 6 then return 88 end
		return loaded and 4 or 0
	end
	C_Container.GetContainerItemInfo = function(bag, slot)
		if bag == Enum.BagIndex.Characterbanktab and slot == 2 and loaded then
			return { itemID = 4498, stackCount = 1, itemName = "Brauner Lederranzen" }
		end
		return slot == (bag == 6 and 3 or 1) and content[bag] or nil
	end
	local function Send(event, ...)
		local callback = listeners[event] and listeners[event][bankView]
		if callback then callback(bankView, event, ...) end
	end

	assert(#buttons == 2 and buttons[1]:IsShown() and buttons[2]:IsShown(), "button in both bag modes")
	assert(not bankView.cdb.snapshot, "first visit needed")
	Send("BANKFRAME_OPENED")
	assert(bankView.cdb.snapshot.items[6][3].count == 19 and not bankView.cdb.snapshot.items[6][1], "main bank preserves empty slots")
	assert(bankView.cdb.snapshot.sizes[7] == 0, "unequipped bank bag")
	loaded = true
	Send("BAG_CONTAINER_UPDATE")
	assert(bankView.cdb.snapshot.items[7][1].name == "Wollstoff", "equipped bank bag")
	local before = scans
	Send("BAG_UPDATE", 0)
	Send("BAG_UPDATE", 15)
	assert(scans == before, "bag and account bank changes do not read the character bank")
	content[6] = nil
	Send("BAG_UPDATE", 6)
	assert(scans == before + 1 and #bankView.cdb.snapshot.items[6] == 0, "update only the affected bank bag")
	available = false
	Send("BAG_CONTAINER_UPDATE")
	Send("BANKFRAME_CLOSED")
	content[7] = nil
	Send("BAG_UPDATE", 7)
	assert(bankView.cdb.snapshot.items[7][1].link == "item:2592", "keep the saved contents away from the bank")

	local savedFrame, savedDate = CreateFrame, rawget(_G, "date")
	local query = ""
	CreateFrame = function(kind, name, parent, template)
		local frame = savedFrame(kind, name, parent, template)
		if template == "SearchBoxTemplate" then
			frame.GetText = function() return query end
		elseif template == "BankPageTabTemplate" then
			frame.SetCustomOnMouseUpHandler = function(self, fn) self.select = fn end
		elseif kind == "ItemButton" then
			local normal = frame:CreateTexture()
			frame.GetNormalTexture = function() return normal end
			frame.SetMatchesSearch = function(self, matches) self.matches = matches end
			frame.SetItemButtonCount = function(self, count) self.count = count end
		end
		return frame
	end
	date = os.date
	local click = buttons[2]:GetScript("OnClick")
	local snapshot = bankView.cdb.snapshot
	bankView.cdb.snapshot = { bags = { 7 }, items = { [7] = snapshot.items[7] }, updated = snapshot.updated }
	click(buttons[2])
	local window = ForeverPlusBankView
	assert(window:IsShown() and window.Slots[1].count == 4, "legacy snapshot still opens")
	click(buttons[2])
	bankView.cdb.snapshot = snapshot
	click(buttons[2])
	assert(window:IsShown() and window.page == 1 and window.Slots[3].count == 0, "button opens the first page with empty slots")
	assert(window.Tabs[2]:IsShown() and window.BankBags[4]:IsShown(), "page tabs and bank bag bar")
	assert(window.BankBags[2].link == "item:4498" and window.BankBags[4].Lock:IsShown(), "equipped bag and locked bag slot")
	local search = window.Search:GetScript("OnTextChanged")
	query = " WOLL "
	search()
	assert(window.page == 2 and window.Slots[1].matches and window.Slots[1].count == 4, "search goes to the matching page")
	assert(not window.Slots[5].matches and window.Slots[5].count == 2, "search dims nonmatches in their original slots")
	window.Tabs[1]:select("LeftButton", true)
	assert(window.page == 1, "clicking a tab selects its page while searching")
	click(buttons[2])
	assert(not window:IsShown(), "button closes the bank view")
	CreateFrame, date = savedFrame, savedDate

	bankView.db.enabled = false
	bankView:OnOptionChanged()
	assert(not buttons[1]:IsShown() and not buttons[2]:IsShown(), "option hides both buttons")
	available = true
	Send("BANKFRAME_OPENED")
	assert(#bankView.cdb.snapshot.items[7] == 1, "disabled option stops recording")
	bankView.db.enabled = true
	bankView:OnOptionChanged()
	assert(#bankView.cdb.snapshot.items[7] == 0, "enabling at the bank refreshes the snapshot")
	Send("BANKFRAME_CLOSED")
	bankView.cdb.snapshot = nil
	C_Bank, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = savedBank, savedSlots, savedInfo
	print("character bank snapshot OK")
end)()
itemsMod = ns:GetModule("Items")
local UpdateAllBags = upvalue(itemsMod.OnOptionChanged, "UpdateAllBags")
local UpdateContainerFrame = upvalue(UpdateAllBags, "UpdateContainerFrame")
local UpdateButton = upvalue(UpdateContainerFrame, "UpdateButton")
BagComparisonState = upvalue(UpdateButton, "BagComparisonState")
assert(BagComparisonState, "BagComparisonState found")
Enum.ItemClass = { Armor = 4, Weapon = 2 }
local cache = upvalue(BagComparisonState, "upgradeCache")
ITEMS = {
	["equippedBelt"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 25 } },
	["clothBelt"] = { "INVTYPE_WAIST", 4, 1, { RESISTANCE0_NAME = 9, ITEM_MOD_INTELLECT_SHORT = 5 } },
	["leatherAgi"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 30, ITEM_MOD_AGILITY_SHORT = 3 } },
	["leatherInt"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 20, ITEM_MOD_INTELLECT_SHORT = 3 } },
	["mailBelt"] = { "INVTYPE_WAIST", 4, 3, { RESISTANCE0_NAME = 60, ITEM_MOD_STRENGTH_SHORT = 5 } },
}
C_Item.GetItemInfoInstant = function(link) local d = ITEMS[link] return 1, nil, nil, d[1], nil, d[2], d[3] end
C_Item.GetItemStats = function(link) return ITEMS[link][4] end
C_Item.IsItemDataCachedByID = function() return true end
C_Item.DoesItemExist = function() return true end
ItemLocation = { CreateFromEquipmentSlot = function() return {} end }
GetInventoryItemLink = function(_, slot) return slot == 6 and "equippedBelt" or nil end
C_Item.DoesItemExist = function(loc) return true end
GetInventoryItemLink = function(_, slot) return slot == 6 and "equippedBelt" or (slot == 16 and "equippedBelt") or nil end
C_TooltipInfo.GetBagItem = function() return { lines = {} } end
C_SpecializationInfo = { GetSpecialization = function() return 2 end, GetSpecializationInfo = function() return 263, "Enh", nil, nil, "DAMAGER" end }
UnitLevel = function() return 20 end
local _, cls = UnitClass("player")
compare = upvalue(BagComparisonState, "CompareScores")
local up = upvalue(compare, "IsBestArmorType")
-- player class in harness is MAGE; force shaman
for i = 1, 200 do local n = debug.getupvalue(up, i) if not n then break end if n == "playerClass" then debug.setupvalue(up, i, "SHAMAN") end end
local GetWeights = upvalue(upvalue(compare, "EquippedScore"), "Score")
local function check(link, expect)
	for k in pairs(cache) do cache[k] = nil end
	for k in pairs(upvalue(GetWeights, "scoreCache")) do upvalue(GetWeights, "scoreCache")[k] = nil end
	for k in pairs(upvalue(upvalue(compare, "EquippedScore"), "equippedCache")) do upvalue(upvalue(compare, "EquippedScore"), "equippedCache")[k] = nil end
	local r = BagComparisonState(0, 1, link)
	print("  upgrade", link, r)
	assert(r == expect, link)
end
check("clothBelt", false)
check("leatherAgi", true)
check("leatherInt", true)
GetInventoryItemLink = function(_, slot) return slot == 6 and "leatherAgi" or nil end
check("leatherInt", "worse")
check("leatherAgi", false)
check("mailBelt", false) -- level 20: mail not best type
;(function()
	local savedInfo = C_Container.GetContainerItemInfo
	local button = NewFrame("Button")
	button.GetBagID = function() return 0 end
	button.JunkIcon = false
	button.UpgradeIcon = NewFrame("Texture")
	local link = "leatherInt"
	C_Container.GetContainerItemInfo = function() return link and { hyperlink = link } end
	UpdateButton(button)
	local arrow = upvalue(UpdateButton, "bagDowngradeArrows")[button]
	assert(arrow:IsShown() and arrow.rotation == math.pi and arrow.vertexColor[2] < 0.2
		and not button.UpgradeIcon:IsShown(), "a worse item shows the red down arrow in the bag slot")
	link = "leatherAgi"
	UpdateButton(button)
	assert(not arrow:IsShown() and not button.UpgradeIcon:IsShown(), "the bag slot clears both arrows for equal gear")
	C_Container.GetContainerItemInfo = savedInfo
end)()
UnitLevel = function() return 40 end
print("dbg", up(4, 3, "INVTYPE_WAIST"), upvalue(up, "ARMOR_TYPE").SHAMAN[2], UnitLevel())
check("mailBelt", true)
print("upgrade OK")
;(function()
	local savedLoot, savedScrollUtil = rawget(_G, "LootFrame"), rawget(_G, "ScrollUtil")
	local savedType, savedLink, savedTypes = rawget(_G, "GetLootSlotType"), rawget(_G, "GetLootSlotLink"), Enum.LootSlotType
	local savedEquippable, savedCached, savedRequest = C_Item.IsEquippableItem, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	local savedTooltip, savedPattern, savedEquipped = C_TooltipInfo.GetHyperlink, itemsMod.levelPattern, GetInventoryItemLink
	local arrow, initialized, request
	local row, data = { Item = NewFrame("Button") }, { slotIndex = 1 }
	local slots = { "mailBelt", "clothBelt", "money", "clothBelt" }
	local cached, canUse = false, false
	LootFrame = NewFrame("Frame")
	LootFrame.ScrollBox = { ForEachFrame = function(_, visit) visit(row, data) end }
	LootFrame:Hide()
	ScrollUtil = { AddInitializedFrameCallback = function(box, callback, owner)
		if box == LootFrame.ScrollBox then
			initialized = function() callback(owner, row, data) end
		end
	end }
	row.Item.CreateTexture = function()
		assert(not arrow, "reuse the existing arrow")
		arrow = NewFrame("Texture")
		arrow.SetDesaturated = function(self, value) self.grey = value end
		arrow.SetAtlas = function(self, value) self.atlas = value end
		arrow.SetPoint = function(self, point, anchor) self.point, self.anchor = point, anchor end
		return arrow
	end
	Enum.LootSlotType = { Item = 1, Money = 2 }
	GetLootSlotType = function(slot) return slot == 3 and Enum.LootSlotType.Money or Enum.LootSlotType.Item end
	GetLootSlotLink = function(slot)
		assert(slot ~= 3, "do not read item links for money")
		return slots[slot]
	end
	C_Item.IsEquippableItem = function(link) return ITEMS[link] ~= nil end
	C_Item.IsItemDataCachedByID = function(link) return link ~= "mailBelt" or cached end
	C_Item.RequestLoadItemDataByID = function(link) request = link end
	C_TooltipInfo.GetHyperlink = function()
		return { lines = canUse and {} or { { leftText = "Benötigt Stufe 41", leftColor = { r = 1, g = 0, b = 0 } } } }
	end
	itemsMod.levelPattern = "Benötigt Stufe %d+"
	itemsMod:OnLogin()
	LootFrame:Show()
	local listeners = upvalue(ns.RegisterEvent, "listeners")
	local function Send(event, ...)
		listeners[event][itemsMod](itemsMod, event, ...)
	end
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	initialized()
	assert(request == "mailBelt" and not arrow, "wait for uncached loot without showing the arrow")
	cached = true
	Send("ITEM_DATA_LOAD_RESULT", 1, true)
	assert(arrow:IsShown() and arrow.grey and arrow:GetAlpha() == 0.75, "a level requirement shows the grey arrow after loading")
	assert(arrow.atlas == "bags-greenarrow" and arrow.point == "TOPRIGHT" and arrow.anchor == row.Item, "use the bag arrow on the loot icon")

	data = { slotIndex = 2 }
	initialized()
	assert(not arrow:IsShown(), "a recycled row clears the previous arrow for unsuitable gear")
	data = { slotIndex = 3 }
	initialized()
	assert(not arrow:IsShown(), "money has no arrow")
	data = { slotIndex = 4 }
	initialized()
	canUse = true
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	slots[4] = "mailBelt"
	Send("LOOT_SLOT_CHANGED", 4)
	assert(arrow:IsShown() and not arrow.grey and arrow:GetAlpha() == 1, "an equippable upgrade shows the green arrow")
	GetInventoryItemLink = function(_, slot) return slot == 6 and "mailBelt" or nil end
	ITEMS.weakerMailBelt = { "INVTYPE_WAIST", 4, 3, { RESISTANCE0_NAME = 20 } }
	slots[4] = "weakerMailBelt"
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	assert(arrow:IsShown() and arrow.rotation == math.pi and arrow.vertexColor[2] < 0.2,
		"an equippable downgrade shows the red down arrow on the same loot row")
	canUse = false
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	assert(not arrow:IsShown(), "a level-gated downgrade has no arrow")
	slots[4], canUse = "mailBelt", true
	ITEMS.weakerMailBelt = nil
	GetInventoryItemLink = function(_, slot) return slot == 6 and "mailBelt" or nil end
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	assert(not arrow:IsShown(), "equipping equivalent gear updates the open window")
	GetInventoryItemLink = savedEquipped
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	assert(arrow:IsShown() and arrow.rotation == 0 and arrow.vertexColor[2] == 1 and not arrow.grey,
		"recycling a red loot arrow for an upgrade restores green and the upward direction")
	itemsMod.db.upgradeArrow = false
	itemsMod:OnOptionChanged("upgradeArrow")
	assert(not arrow:IsShown(), "the existing option hides loot arrows")
	itemsMod.db.upgradeArrow = true
	itemsMod:OnOptionChanged("upgradeArrow")
	assert(arrow:IsShown(), "turning the option back on refreshes the open window")

	LootFrame, ScrollUtil = savedLoot, savedScrollUtil
	GetLootSlotType, GetLootSlotLink, Enum.LootSlotType = savedType, savedLink, savedTypes
	C_Item.IsEquippableItem, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = savedEquippable, savedCached, savedRequest
	C_TooltipInfo.GetHyperlink, itemsMod.levelPattern = savedTooltip, savedPattern
	Send("PLAYER_EQUIPMENT_CHANGED", 6)
	print("loot upgrade arrows OK")
end)()

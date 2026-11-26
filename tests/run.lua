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
local frameMeta = {}
local function NewFrame(kind, name)
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
local function NewFont(name, size)
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
Enum.BankType = { Character = 0, Account = 2 }
Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9 = 6, 14
Enum.BagIndex.Characterbanktab = -2
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i) return "Prof", 1, 150, 300, 0, 0, i == 1 and 171 or 185 end
C_Item = Mock("C_Item"); C_Item.IsItemDataCachedByID = function() return true end
C_Item.GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 9, 5 end
C_TooltipInfo = { GetItemByID = function() return { lines = {} } end, GetBagItem = function() return { lines = {} } end,
	GetUnit = function() return { lines = {} } end }
Enum.TooltipDataLineType = { ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46 }
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
local root = arg[1]
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
local ns = {}
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
local items = ns:GetModule("Items")
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
local realPopup = ns.ShowPopupList
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
local function upvalue(fn, name)
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
local itemsMod = ns:GetModule("Items")
local UpdateAllBags = upvalue(itemsMod.OnOptionChanged, "UpdateAllBags")
local UpdateContainerFrame = upvalue(UpdateAllBags, "UpdateContainerFrame")
local UpdateButton = upvalue(UpdateContainerFrame, "UpdateButton")
local BagComparisonState = upvalue(UpdateButton, "BagComparisonState")
assert(BagComparisonState, "BagComparisonState found")
Enum.ItemClass = { Armor = 4, Weapon = 2 }
local cache = upvalue(BagComparisonState, "upgradeCache")
local ITEMS = {
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
local compare = upvalue(BagComparisonState, "CompareScores")
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
-- Info module: played + perf tooltip
local info = ns:GetModule("Info")
TimeManagerClockButton = {}
GameTooltip.GetOwner = function() return TimeManagerClockButton end
local lines = {}
GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = tostring(l) .. " | " .. tostring(r) end
GameTooltip.AddLine = function(_, l) lines[#lines + 1] = tostring(l) end
GameTooltip_AddNormalLine = function(_, l) lines[#lines + 1] = tostring(l) end
GameTooltip_AddBlankLineToTooltip = function() end
GameTooltip_SetTitle = function(_, l) lines[#lines + 1] = "## " .. l end
C_ClassColor.GetClassColor = function() return { WrapTextInColorCode = function(_, t) return t end, GetRGB = function() return 1, 1, 1 end } end
info:TIME_PLAYED_MSG("TIME_PLAYED_MSG", 3600)
info.db.characters.Forever.Alt = { total = 7200, class = "WARRIOR", level = 30 }
local uv = function(fn, name) for i = 1, 200 do local n, v = debug.getupvalue(fn, i) if not n then return end if n == name then return v end end end
local add = uv(info.OnLogin, "AddPlayedLines")
add()
;(function()
	local savedName, savedClass, savedRealm, savedLevel, savedTime = UnitName, UnitClass, GetRealmName, UnitLevel, time
	local realm = ""
	UnitName = function() return "Kazgrim" end
	UnitClass = function() return "Shaman", "SHAMAN" end
	GetRealmName = function() return realm end
	UnitLevel = function() return 19 end
	time = function() return 2002 end
	local clockInfo
	local fixture = setmetatable({ After = function() end, OnAddOnLoaded = function() end }, { __index = ns })
	function fixture:NewModule(_, module)
		clockInfo = module
		module.db = module.defaults
		module.RegisterEvent = function() end
		return module
	end
	assert(loadfile(root .. "/Modules/Info.lua"))("ForeverPlus", fixture)
	clockInfo.UpdatePerformance = function() end
	local characters = clockInfo.db.characters
	local newest = { total = 106885, time = 2000, class = "SHAMAN", level = 19, levelStart = 106426, levelStartLevel = 19 }
	characters[""] = { Kazgrim = newest }
	characters.Forever = {
		Kazgrim = { total = 77904, time = 1000, class = "SHAMAN", level = 16 },
		Thoradin = { total = 140251, class = "PALADIN", level = 21 },
	}
	clockInfo:OnLogin()
	assert(characters[""] == nil and characters.Forever.Kazgrim == newest and newest.levelStart == 106426,
		"the legacy duplicate is repaired before the realm is available, preserving the newer level data")
	local previousLines = lines
	lines = {}
	uv(clockInfo.OnLogin, "AddPlayedLines")()
	assert(#lines == 4 and lines[2]:find("Thoradin", 1, true) and lines[3]:find("Kazgrim", 1, true)
		and lines[4] == ns.L.INFO_PLAYED_TOTAL .. " | 247138s", "the clock counts exactly two characters and includes live time")
	lines = previousLines
	characters.Other = { Kazgrim = { total = 3600, class = "SHAMAN" } }
	characters[""] = { Kazgrim = { total = 1800, class = "SHAMAN" } }
	realm = "Forever"
	clockInfo:TIME_PLAYED_MSG("TIME_PLAYED_MSG", 106900, 474)
	assert(characters.Forever.Kazgrim.total == 106900 and characters.Other.Kazgrim.total == 3600
		and characters[""].Kazgrim.total == 1800, "the server reply updates the current realm and leaves an ambiguous record intact")
	UnitName, UnitClass, GetRealmName, UnitLevel, time = savedName, savedClass, savedRealm, savedLevel, savedTime
	print("clock played-time realm recovery OK")
end)()
local show = uv(uv(uv(info.UpdatePerformance, "CreatePerfFrame"), "RefreshCpuTooltip"), "fn")
show(UIParent)
for _, l in ipairs(lines) do print("  " .. l) end
print("info OK")
;(function()
	-- The CPU tooltip samples only after the world and loading screen are ready.
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local event = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local metrics = uv(show, "sessionMetrics")
	local row = metrics.Slow
	local savedTime, savedMetric = GetTime, C_AddOnProfiler.GetAddOnMetric
	local now, elapsed = 500, 40
	GetTime = function() return now end
	C_AddOnProfiler.GetAddOnMetric = function() return elapsed end
	sample()
	assert(row.recentCount == 0, "even a long login has no samples before world entry")

	event(sampler, "PLAYER_ENTERING_WORLD", true, false)
	now = 510
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 569
	sample()
	assert(row.recentCount == 0, "the first loading screen ends before the full startup grace")
	now, elapsed = 570, 3.3
	sample()
	elapsed = 0.07
	for _ = 1, 60 do sample() end
	assert(row.peak == 3.3 and row.peakAt == 570 and row.slow == 0 and math.abs(row.recentTotal / row.recentCount - 0.07) < 0.001,
		"the recent average ages out a peak below the slow-frame threshold")

	now, elapsed = 600, 40
	event(sampler, "LOADING_SCREEN_ENABLED")
	event(sampler, "PLAYER_ENTERING_WORLD", false, false)
	now = 625
	sample()
	assert(row.peak == 3.3, "a long zone loading screen suspends sampling")
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 644
	sample()
	assert(row.slow == 0, "zone grace runs from the end of the screen")
	now, elapsed = 645, 6
	sample()
	assert(row.peak == 6 and row.slow == 1, "real gameplay spikes still count")

	now, elapsed = 700, 40
	event(sampler, "LOADING_SCREEN_ENABLED")
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 705
	event(sampler, "PLAYER_ENTERING_WORLD", false, true)
	now = 764
	sample()
	assert(row.peak == 6 and row.slow == 1, "reload waits a full minute from world entry")
	now, elapsed = 765, 7
	sample()
	assert(row.peak == 7 and row.slow == 2, "sampling resumes after reload grace")

	-- The session remembers a spike before a later explicit measurement begins.
	event(sampler, "ADDON_LOADED", ns.name)
	local own = metrics[ns.name]
	local savedClock = debugprofilestop
	local clock = 0
	debugprofilestop = function() return clock end
	local slow = ns.Measured("Test: session spike", function() clock = clock + 31 end)
	slow() -- this frame was already sampled before the callback ran
	now, elapsed = 766, 33.3
	ns.Measured("Test: next frame", function() clock = clock + 40 end)()
	sample()
	assert(own.peak == 33.3 and own.peakCall == "Test: session spike" and own.peakCallTime == 31,
		"a larger callback from the current frame does not label the previous frame's spike")
	assert(not ns.timings["Test: session spike"], "session attribution does not collect detailed call statistics")
	debugprofilestop = savedClock

	local perf = uv(info.UpdatePerformance, "perfFrame")
	local added = GameTooltip.AddLine
	local peakLine = ns.L.INFO_CPU_PEAK_CALL:format("Test: session spike", 31)
	local sawPeak = false
	GameTooltip.AddLine = function(_, line) sawPeak = sawPeak or line == peakLine end
	perf:GetScript("OnEnter")(perf)
	GameTooltip.AddLine = added
	assert(sawPeak, "the session peak call is visible without starting a measurement")
	now, elapsed = 767, 0.4
	sample()
	now, elapsed = 768, 40
	sample()
	assert(own.peak == 40 and not own.peakCall and own.slowFrame == 33.3 and own.slowCall == "Test: session spike",
		"an unattributed peak retains the most recent attributed slow frame")
	local slowLine = ns.L.INFO_CPU_LAST_SLOW_CALL:format(33.3, "Test: session spike", 31)
	local sawSlow = false
	GameTooltip.AddLine = function(_, line) sawSlow = sawSlow or line == slowLine end
	perf:GetScript("OnEnter")(perf)
	GameTooltip.AddLine = added
	assert(sawSlow, "the tooltip still shows the last attributable spike")
	local mouseUp = perf:GetScript("OnMouseUp")
	local savedShift = IsShiftKeyDown
	local savedResult = info.lastMeasure
	info.lastMeasure = {}
	IsShiftKeyDown = function() return true end
	mouseUp(perf, "LeftButton")
	assert(row.peak == 0 and row.slow == 0 and row.recentCount == 0 and row.recentTotal == 0
		and own.peak == 0 and not own.peakAt and not own.peakCall and info.lastMeasure and not ns.measureUntil,
		"shift-left-click resets the session only")
	now = 769
	sample()
	assert(row.recentCount == 0 and own.peak == 0, "the last frame from before reset is discarded")
	now, elapsed = 770, 0.4
	sample()
	assert(row.recentCount == 1 and row.recentTotal == 0.4 and own.peak == 0.4, "sampling restarts immediately")
	IsShiftKeyDown, info.lastMeasure = savedShift, savedResult
	event(sampler, "LOADING_SCREEN_ENABLED")
	GetTime, C_AddOnProfiler.GetAddOnMetric = savedTime, savedMetric
	print("cpu sampling grace OK")
end)()
;(function()
	-- Collection of >5 ms moments: multi-call attribution, external addons, tooltip, copyable window, cap and reset.
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local event = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local perf = uv(info.UpdatePerformance, "perfFrame")
	local mouseUp = perf:GetScript("OnMouseUp")
	local savedTime, savedMetric = GetTime, C_AddOnProfiler.GetAddOnMetric
	local savedClock, savedDate, savedCombat = debugprofilestop, rawget(_G, "date"), InCombatLockdown
	local savedShift, savedEdit = IsShiftKeyDown, ns.ShowEditWindow
	local savedAddLine, savedAddDouble, savedAddNormal = GameTooltip.AddLine, GameTooltip.AddDoubleLine, GameTooltip_AddNormalLine

	local now, clock = 770.5, 0
	local perAddon = {}
	local combat = false
	local clockText = "19:00:01"
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	date = function() return clockText end
	InCombatLockdown = function() return combat end
	C_AddOnProfiler.GetAddOnMetric = function(name) return perAddon[name] or 0 end
	IsShiftKeyDown = function() return false end

	-- End loading screen + wait out zone grace (770.5 + 20 = 790.5).
	event(sampler, "LOADING_SCREEN_DISABLED")
	now = 791.0
	sample()
	assert(info.SpikesText(true) == nil, "no moments recorded before any >5 ms frame")

	-- Frame 1 (791.0): multiple ForeverPlus calls, including one repeated 3x (6.0 ms total > 2.2 ms single call).
	local fnRepeat = ns.Measured("Items: repeat", function() clock = clock + 2.0 end)
	local fnOther = ns.Measured("Quests: tracker", function() clock = clock + 2.2 end)
	fnRepeat()
	fnRepeat()
	fnRepeat()
	fnOther()
	-- Frame 2 (791.1): another slow call arrives BEFORE OnUpdate samples frame 791.0; must not leak into frame 791.0.
	now, combat, clockText = 791.1, true, "19:00:02"
	local fnNext = ns.Measured("Dialog: update", function() clock = clock + 8.5 end)
	fnNext()
	perAddon = { [ns.name] = 9.4, Slow = 0.2 }
	sample()

	-- Frame 3 (791.2): sample frame 791.1 (Dialog: update 8.5 ms) + external addon spike (Slow 7.3 ms).
	now, combat, clockText = 791.2, false, "19:00:03"
	local fnThird = ns.Measured("Tooltip: item", function() clock = clock + 0.4 end)
	fnThird()
	perAddon = { [ns.name] = 9.1, Slow = 7.3 }
	sample()

	-- Frame 4 (791.3): normal frame (<5 ms), must not add a moment.
	now, clockText = 791.3, "19:00:04"
	perAddon = { [ns.name] = 1.2, Slow = 0.5 }
	sample()

	-- Frame 5 (791.4): unattributed >5 ms frame for ForeverPlus (no call >= 0.25 ms in frame 791.3).
	now, clockText = 791.4, "19:00:05"
	perAddon = { [ns.name] = 5.6, Slow = 0.1 }
	sample()

	-- Frame 6 (791.5): second hit of Items: repeat (tests grouping count = 2).
	fnRepeat()
	fnRepeat()
	fnRepeat()
	now, clockText = 791.5, "19:00:06"
	perAddon = { [ns.name] = 6.5, Slow = 0.1 }
	sample()

	local report = info.SpikesText()
	assert(report:find(ns.L.INFO_SPIKES_SUMMARY:format(ns.SLOW_MS, 5), 1, true), "report counts all 5 >5 ms moments: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Items: repeat", 2, 6.0, 9.4), 1, true),
		"repeated calls aggregate per frame and group across moments: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Dialog: update", 1, 8.5, 9.1), 1, true),
		"second frame keeps its own call without leakage from frame 1: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_UNATTRIBUTED:format(ns.L.INFO_SPIKES_UNATTRIBUTED, 1, 5.6), 1, true),
		"unattributed >5 ms frames appear in summary: " .. report)
	assert(report:find(ns.L.INFO_SPIKES_ADDON_LINE:format("Slow Addon", 1, 7.3), 1, true),
		"external addon >5 ms moments appear in other addons section: " .. report)
	assert(report:find("19:00:02 | " .. ns.name .. " | 9.4 ms | " .. ns.L.INFO_SPIKES_COMBAT
		.. " | Items: repeat (6.0 ms, 3×), Quests: tracker (2.2 ms)", 1, true),
		"moment line includes combat tag and all calls sorted by total ms: " .. report)
	assert(report:find("19:00:03 | Slow Addon | 7.3 ms", 1, true), "external addon moment line formatted cleanly")
	assert(not report:find("19:00:04", 1, true), "frames under 5 ms are not collected")

	-- Tooltip lists the collected >5 ms moments and their functions.
	local tipLines = {}
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	GameTooltip.AddDoubleLine = function(_, left, right) tipLines[#tipLines + 1] = tostring(left) .. " | " .. tostring(right) end
	GameTooltip_AddNormalLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	perf:GetScript("OnEnter")(perf)
	local tipJoined = table.concat(tipLines, "\n")
	assert(tipJoined:find(ns.L.INFO_SPIKES_HEADER:format(ns.SLOW_MS, 5), 1, true), "tooltip shows moments header")
	assert(tipJoined:find("Items: repeat (6.0 ms, 3×), Quests: tracker (2.2 ms)", 1, true), "tooltip shows captured calls")
	assert(tipJoined:find(ns.L.INFO_SPIKES_EXTERNAL_NOTE, 1, true), "tooltip notes external addon limitation")

	-- Diagnose includes >5 ms moments when present.
	local diag = ns:GetModule("DataCapture").DiagnoseText()
	assert(diag:find("== " .. ns.L.DIAG_SPIKES:format(ns.SLOW_MS) .. " ==", 1, true) and diag:find("Items: repeat", 1, true),
		"diagnose report includes collected >5 ms moments")

	-- Left-click on perfFrame opens the copyable window; slash commands also open it; Reset clears everything.
	local openedKey, openedText, openedExtras
	ns.ShowEditWindow = function(key, _, text, _, _, _, extras)
		openedKey, openedText, openedExtras = key, text, extras
	end
	mouseUp(perf, "LeftButton")
	assert(openedKey == "Spikes" and openedText == report and openedExtras and openedExtras[1],
		"left-click opens spikes window with reset button")
	openedKey = nil
	SlashCmdList.FOREVERPLUS("spitzen")
	assert(openedKey == "Spikes", "/fp spitzen opens spikes window")
	openedKey = nil
	SlashCmdList.FOREVERPLUS("spikes")
	assert(openedKey == "Spikes", "/fp spikes opens spikes window")

	local shortCall = ns.Measured("Minimap: coordinates update", function() clock = clock + 0.2 end)
	shortCall()
	now, clockText = 791.6, "19:00:07"
	perAddon = { [ns.name] = 78.5 }
	sample()
	report = info.SpikesText()
	local shortLabel = ns.L.INFO_SPIKES_SHORT_CALLS:format(ns.SLOW_MS)
	assert(report:find(ns.L.INFO_SPIKES_TRIGGER_UNATTRIBUTED:format(shortLabel, 1, 78.5), 1, true)
		and not report:find(ns.L.INFO_SPIKES_TRIGGER_LINE:format("Minimap: coordinates update", 1, 0.2, 78.5), 1, true),
		"a short call does not get the large frame attributed to it in the summary")
	assert(report:find("78.5 ms | Minimap: coordinates update (0.2 ms)", 1, true),
		"the short call is still visible in frame details")

	-- Ring-buffer cap keeps latest 100 moments while tracking total count.
	for i = 1, 102 do
		now = 792.0 + i * 0.05
		perAddon = { [ns.name] = 0, Slow = 6.0 }
		sample()
	end
	local capped = info.SpikesText()
	assert(capped:find(ns.L.INFO_SPIKES_SUMMARY_CAPPED:format(ns.SLOW_MS, 108, 100), 1, true),
		"cap preserves total count and keeps last 100 moments: " .. capped:sub(1, 80))

	-- Reset button clears moments and session metrics.
	openedExtras[1].onClick()
	assert(info.SpikesText(true) == nil and openedText == ns.L.INFO_SPIKES_EMPTY:format(ns.SLOW_MS),
		"reset button clears collected moments and refreshes window")
	assert(not ns:GetModule("DataCapture").DiagnoseText():find("== " .. ns.L.DIAG_SPIKES:format(ns.SLOW_MS) .. " ==", 1, true),
		"diagnose omits moments section after reset")

	GameTooltip.AddLine, GameTooltip.AddDoubleLine, GameTooltip_AddNormalLine = savedAddLine, savedAddDouble, savedAddNormal
	IsShiftKeyDown, ns.ShowEditWindow = savedShift, savedEdit
	debugprofilestop, date, InCombatLockdown = savedClock, savedDate, savedCombat
	event(sampler, "LOADING_SCREEN_ENABLED")
	GetTime, C_AddOnProfiler.GetAddOnMetric = savedTime, savedMetric
	print("cpu spike moments OK")
end)()
-- Grey item keep exception
local itemsM = ns:GetModule("Items")
C_Container.GetContainerItemInfo = function() return { itemID = 99, hyperlink = "[grey]", quality = 0, stackCount = 1 } end
Enum.ItemQuality.Poor = 0
local isJunk = uv(uv(uv(uv(itemsM.MERCHANT_SHOW, "StartSelling"), "SellBatch"), "IsJunk"), "IsJunkItem")
assert(isJunk({ itemID = 99, quality = 0 }) == true, "grey is junk")
ForeverPlus_ToggleJunkUnderMouse()
assert(itemsM.db.keep[99], "grey kept")
assert(isJunk({ itemID = 99, quality = 0 }) == false, "kept grey not junk")
ForeverPlus_ToggleJunkUnderMouse()
assert(not itemsM.db.keep[99] and isJunk({ itemID = 99, quality = 0 }), "grey junk again")
print("keep OK")
-- Quests: progress then completion sounds
local quests = ns:GetModule("Quests")
local played = {}
PlaySound = function(kit) played[#played + 1] = tostring(kit) end
PlaySoundFile = function(path) played[#played + 1] = path return true end
SOUNDKIT = { MAP_PING = "ping", IG_QUEST_LIST_COMPLETE = "done", RAID_WARNING = "rw" }
local qstate = { done = 0, complete = false }
C_QuestLog.GetNumQuestLogEntries = function() return 1 end
C_QuestLog.GetInfo = function() return { questID = 5, isHeader = false } end
C_QuestLog.GetQuestObjectives = function() return { { numFulfilled = qstate.done } } end
C_QuestLog.GetNumQuestObjectives = function() return 1 end
GetQuestObjectiveInfo = function() return "", "monster", false, qstate.done, 2 end
C_QuestLog.IsComplete = function() return qstate.complete end
C_QuestLog.IsFailed = function() return false end
C_QuestLog.GetLogIndexForQuestID = function() return 1 end
GetNumQuestLeaderBoards = function() return 1 end
C_NamePlate = { GetNamePlates = function() return {} end }
local scan = uv(uv(quests.OnLogin, "QueueScan"), "ScanQuests")
scan(); qstate.done = 1; scan(); qstate.done = 2; qstate.complete = true; scan()
print("  sounds:", table.concat(played, ","))
assert(played[1] == 558137 or played[1] == "558137", "quest progress sound")
;(function()
	-- Quests: the log scan reads objectives without per-quest tables and keeps its own state tables.
	local questState = uv(scan, "state")
	local savedObjectives, savedInfo, savedNum = C_QuestLog.GetQuestObjectives, C_QuestLog.GetInfo, C_QuestLog.GetNumQuestLogEntries
	local savedChat, savedInGroup, savedInRaid = C_ChatInfo, IsInGroup, IsInRaid
	local objectiveTables = 0
	C_QuestLog.GetQuestObjectives = function() objectiveTables = objectiveTables + 1 return {} end
	local entries = { 5 }
	C_QuestLog.GetNumQuestLogEntries = function() return #entries end
	C_QuestLog.GetInfo = function(index) return { questID = entries[index], isHeader = false, title = "Kobolde" } end
	local sent = {}
	C_ChatInfo = { SendChatMessage = function(text, channel) sent[#sent + 1] = channel .. ":" .. text end }
	IsInGroup = function(category) return category == nil end
	IsInRaid = function() return false end
	quests.db.sharePartial = true
	qstate.done, qstate.complete = 0, false
	scan()
	local entry = questState[5]
	assert(entry and entry.done == 0, "the scan records the quest")
	qstate.done = 1
	scan()
	assert(questState[5] == entry and entry.done == 1 and entry.counts[1] == 1, "the scan updates the same state table")
	assert(#sent == 1 and sent[1]:find("^PARTY:") and sent[1]:find("Kobolde", 1, true), "a moved objective goes to the group")
	scan()
	assert(#sent == 1, "an unchanged objective is not shared again")
	assert(objectiveTables == 0, "the scan does not build objective tables")
	entries = {}
	scan()
	assert(questState[5] == nil, "a quest that left the log leaves the state")
	quests.db.sharePartial = false
	C_QuestLog.GetQuestObjectives, C_QuestLog.GetInfo, C_QuestLog.GetNumQuestLogEntries = savedObjectives, savedInfo, savedNum
	C_ChatInfo, IsInGroup, IsInRaid = savedChat, savedInGroup, savedInRaid
	print("quest scan state OK")
end)()
;(function()
	local bagOptions
	for _, page in ipairs(ns.SettingsPages) do
		for _, entry in ipairs(page) do
			if entry[1] == "Items" and entry.header == ns.L.ITEMS_BAGS then
				bagOptions = entry.keys
			end
		end
	end
	local preview, choices
	for _, opt in ipairs(itemsM.options) do
		if opt.type == "button" and opt.name == ns.L.ITEMS_FULL_SOUND_TEST then
			preview = opt
		elseif opt.key == "fullSoundChoice" then
			choices = opt.values()
		end
	end
	assert(preview and bagOptions and bagOptions[preview.key], "the Bags settings include the sound preview")
	local db = itemsM.db
	assert(db.fullSoundChoice == "warning" and choices[1][1] == "warning", "the warning is the default and first choice")
	local warning = 567459
	preview.func()
	assert(played[#played] == warning, "the preview plays the client's quest failure sound")
	local savedTime, last = GetTime, itemsM.fullState.last
	GetTime = function() return 100 end
	itemsM.fullState.last = 0
	local count = #played
	itemsM.PlayFullSound()
	itemsM.PlayFullSound()
	assert(#played == count + 1 and played[#played] == warning, "the bag event plays the same warning with its cooldown")
	GetTime, itemsM.fullState.last = savedTime, last
	local savedPlayFile = PlaySoundFile
	PlaySoundFile = function() return false end
	preview.func()
	assert(played[#played] == "rw", "the warning falls back to the client's raid warning")
	PlaySoundFile = savedPlayFile

	itemsM.db.fullSoundChoice = "complete"
	preview.func()
	itemsM.db.fullSoundChoice = "ping"
	preview.func()
	assert(played[#played - 1] == "done" and played[#played] == "ping", "the preview plays the selected bag sound")
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "ping", "a Ping selected after the update survives reload")
	db.fullSoundDefaultUpdated = nil
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "warning", "the legacy Ping default switches to the warning once")
	db.fullSoundDefaultUpdated, db.fullSoundChoice = nil, "none"
	itemsM:OnInitialize()
	assert(db.fullSoundChoice == "none", "a different saved choice survives the update")
	db.fullSoundChoice = "warning"
end)()
-- Keyword alert
local chat = ns:GetModule("Chat")
UnitClass = function() return "Schamane", "SHAMAN" end
chat.cdb = chat.cdb or {}
chat.cdb.keywords = nil; chat.db.keywords = "Ony, raid"; chat.db.keywordAlert = true
Ambiguate = function(n) return n end
chat:UpdateKeywordAlert()
played = {}
local onMsg = uv(chat.UpdateKeywordAlert, "OnChatMessage") or uv(uv(chat.UpdateKeywordAlert, "ParseKeywords"), "x")
onMsg(chat, "CHAT_MSG_GUILD", "wer kommt mit zu ONY?", "Someone")
assert(played[1] == "rw", "keyword sound")
print("  keywords:", chat.cdb.keywords)
assert(chat.cdb.keywords:find("Schamane") and chat.cdb.keywords:find("Ony"), "keyword defaults")
print("keyword OK")
-- Loot roll counts
local items = ns:GetModule("Items")
Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local f = NewFrame("Frame", "GroupLootFrame1"); f.rollID = 7
f.LootButtonContainer = { NeedButton = NewFrame("B"), GreedButton = NewFrame("B"), PassButton = NewFrame("B") }
C_LootHistory = { GetSortedInfoForDrop = function() return { itemHyperlink = "item:1", rollInfos = {
	{ playerName = "A", playerClass = "MAGE", state = 0 }, { playerName = "B", playerClass = "MAGE", state = 3 }, { playerName = "C", playerClass = "MAGE", state = 5 } } } end }
GetLootRollItemLink = function() return "item:1" end
C_Item.GetItemInfoInstant = function() return 1 end
items:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 2)
print("roll OK")
-- XP text formats
local xp = ns:GetModule("XPBar")
GetXPExhaustion = function() return 500 end
BreakUpLargeNumbers = function(n) return tostring(n) end
local barText = uv(uv(xp.OnLogin, "HookBars"), "UpdateBars")
local textFn = uv(barText, "UpdateText")
local bar = { currXP = 1250, maxBar = 5000, IsCapped = function() return false end, SetBarText = function(_, t) print("  xp:", t) end }
for _, f in ipairs({ "percent", "both", "remaining", "full" }) do xp.db.format = f; textFn(bar) end
-- XP per hour: level-ups count, no figure in the first two minutes
;(function()
	xp.ResetRate()
	xp.TrackXP(1000, 4000, 5000)
	xp.TrackXP(1060, 4600, 5000)
	assert(xp.Rate(1060) == nil, "no rate during the warm-up")
	xp.TrackXP(1200, 300, 6000)
	assert(xp.Rate(1200) == 1300 / 200 * 3600, "level-up adds the rest of the old level")
	local oldGetTime = GetTime
	GetTime = function() return 1200 end
	assert(xp.Rate(1200) and xp.RateText(2340):find("23400", 1, true) and xp.RateText(2340):find("0:06", 1, true),
		"rate and time to level")
	xp.db.xpRate = false
	assert(xp.RateText(2340) == nil, "option turns the rate off")
	xp.db.xpRate = true
	local text
	xp.db.format = "full"
	textFn({ currXP = 300, maxBar = 6000, IsCapped = function() return false end, SetBarText = function(_, t) text = t end })
	GetTime = oldGetTime
	assert(text:find(ns.L.XP_RATE:format("23400"), 1, true), "full text carries the rate")
	-- short bars: the least important parts go first, at the end only the percent
	local parts = { { text = "AAAA", keep = 6, short = "A" }, { text = "BB", keep = 5 }, { text = "CC", keep = 1 },
		{ text = "DD", keep = 4 } }
	local function Fits(limit) return function(t) return #t <= limit end end
	assert(xp.FitParts(parts, Fits(100)) == "AAAA – BB – CC – DD", "everything when there is room")
	assert(xp.FitParts(parts, Fits(#"AAAA – BB – DD")) == "AAAA – BB – DD", "rested goes first")
	assert(xp.FitParts(parts, Fits(#"AAAA – BB")) == "AAAA – BB", "then the lower parts")
	assert(xp.FitParts(parts, Fits(3)) == "A", "the short form last")
	assert(#parts == 4, "the parts stay as they were")
	local shown
	local label = { SetText = function(_, t) shown = t end, GetUnboundedStringWidth = function() return #shown * 6 end }
	textFn({ currXP = 300, maxBar = 6000, IsCapped = function() return false end, GetWidth = function() return 200 end,
		OverlayFrame = { Text = label }, SetBarText = function(_, t) text = t end })
	assert(#text * 6 <= 200 - 12 and text:find("300", 1, true), "the bar text fits the bar")
	xp.ResetRate()
	print("xp per hour OK")
end)()
-- Loot sparkle: set, kept against graphics presets, the earlier value comes back
;(function()
	local q = ns:GetModule("Quests")
	local cvars, sets = { outlineModeShowLootEffectWhenDisabled = "0" }, 0
	local oldGet, oldSet = GetCVar, SetCVar
	GetCVar = function(name) return cvars[name] end
	SetCVar = function(name, value) cvars[name] = value sets = sets + 1 end
	q.db.lootSparkle, q.db.sparkleBefore = true, nil
	q.ApplySparkle()
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "1" and q.db.sparkleBefore == "0", "option switches the sparkle on")
	cvars.outlineModeShowLootEffectWhenDisabled = "0"
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	eventFrame:GetScript("OnEvent")(eventFrame, "CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled", "0")
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "1" and q.db.sparkleBefore == "0", "a graphics preset cannot switch it off")
	q.db.lootSparkle = false
	q:OnOptionChanged("lootSparkle", false)
	assert(cvars.outlineModeShowLootEffectWhenDisabled == "0" and q.db.sparkleBefore == nil, "turning off restores the earlier value")
	local before = sets
	cvars.outlineModeShowLootEffectWhenDisabled = nil
	q.ApplySparkle()
	assert(sets == before, "unknown setting is left alone")
	GetCVar, SetCVar = oldGet, oldSet
	print("loot sparkle OK")
end)()
-- Items owned by all characters: bags (with gear) and bank add up, the most first, the current character on ties
;(function()
	local bank = ns:GetModule("BankView")
	local inventories = {
		["Ana-Realm"] = { name = "Ana", class = "MAGE", bags = { [2589] = 3 }, bank = { [2589] = 2 } },
		["Bo-Realm"] = { name = "Bo", class = "WARRIOR", bags = { [2589] = 5 }, bank = {} },
		["Cy-Realm"] = { name = "Cy", bags = {}, bank = { [2589] = 5, [774] = 1 } },
		["Broken"] = "x",
	}
	local total, rows = bank.Owned(inventories, 2589, "Cy-Realm")
	assert(total == 15 and #rows == 3, "counts of all characters add up")
	assert(rows[1].key == "Cy-Realm" and rows[2].key == "Ana-Realm" and rows[3].key == "Bo-Realm",
		"most first, current character first on ties")
	assert(rows[2].bags == 3 and rows[2].bank == 2, "bags and bank stay apart")
	assert(bank.Owned(inventories, 999, "Ana-Realm") == 0 and bank.Owned(nil, 2589) == 0, "nothing owned")
	print("owned counts OK")
end)()
-- Profiles as text: round trip, damaged and foreign texts are refused, imports are cleaned and never overwrite
;(function()
	local profiles = ns:GetModule("Profiles")
	local value = { a = "x:y;T E", [3] = 1.25, nested = { flag = true, off = false, list = { "k1", "k2" } }, ["ü"] = "ä" }
	local text = profiles.Encode(value)
	local back = profiles.Decode("  " .. text .. "  ")
	assert(back and back.a == "x:y;T E" and back[3] == 1.25 and back.nested.flag == true and back.nested.off == false
		and back.nested.list[2] == "k2" and back["ü"] == "ä", "round trip keeps strings, numbers, booleans and nesting")
	assert(profiles.Decode(text:sub(1, -2)) == nil, "a cut text is refused")
	assert(profiles.Decode(text .. "x") == nil, "trailing rubbish is refused")
	assert(profiles.Decode("return os.exit()") == nil and profiles.Decode("FP1:s99:abc") == nil, "foreign texts are refused")
	local deep = "FP1:" .. ("Ts1:a"):rep(40) .. "b1" .. ("E"):rep(40)
	assert(profiles.Decode(deep) == nil, "nesting has a limit")
	local oldStore = ns.db.profiles
	ns.db.profiles = { Main = { time = 5, cvars = { a = "1" }, bindings = { JUMP = { "SPACE" } }, layouts = {}, addon = {} } }
	local exported = profiles.ExportText("Main")
	local evil = profiles.Encode({ name = "Main", profile = { cvars = { ok = "1", bad = 5, gxApi = "x" },
		bindings = { JUMP = { "SPACE", 7 }, X = "nope" }, layouts = { { name = "L", text = "t" }, { name = 1 } }, extra = "drop" } })
	local name = profiles.ImportText(evil)
	local kept = ns.db.profiles[name]
	assert(name == "Main (2)" and ns.db.profiles.Main.cvars.a == "1", "import never overwrites a profile")
	assert(kept.cvars.ok == "1" and kept.cvars.bad == nil and kept.cvars.gxApi == nil and kept.cvarCount == 1,
		"imported console settings are cleaned")
	assert(#kept.bindings.JUMP == 1 and kept.bindings.X == nil and #kept.layouts == 1 and kept.extra == nil
		and kept.automatic == false, "imported bindings and layouts are cleaned")
	assert(profiles.ImportText(exported) == "Main (3)", "an exported profile comes back")
	assert(profiles.ImportText("FP1:Tb1") == nil, "a broken text keeps nothing")
	ns.db.profiles = oldStore
	print("profile text OK")
end)()
-- Player notes: keys, menu, tooltip, warnings about marked enemies
;(function()
	local notes = ns:GetModule("PlayerNotes")
	assert(notes.Key("Thrall", "", "Die Aldor") == "thrall-diealdor" and notes.Key("Thrall-DieAldor") == "thrall-diealdor"
		and notes.Key("Jaina", "Kult der Verdammten", "X") == "jaina-kultderverdammten" and notes.Key("") == nil, "player keys")
	local last = {}
	assert(not notes.ShouldWarn({ tag = "friend" }, "a", 10, last), "friends give no warning")
	assert(notes.ShouldWarn({ tag = "enemy" }, "a", 10, last) and not notes.ShouldWarn({ tag = "enemy" }, "a", 200, last)
		and notes.ShouldWarn({ tag = "enemy" }, "a", 311, last), "enemy warnings pause for five minutes")
	local oldStore = ns.db.playerNotes
	ns.db.playerNotes = {}
	local saved = {}
	for _, key in ipairs({ "UnitIsPlayer", "UnitIsUnit", "UnitFullName", "GetRealmName", "PlaySound", "GameTooltip", "time" }) do
		saved[key] = rawget(_G, key)
	end
	UnitIsPlayer = function(unit) return unit ~= "npc" end
	UnitIsUnit = function() return false end
	UnitFullName = function(unit) if unit == "target" then return "Gank", "Andere Welt" end return "Bob", nil end
	GetRealmName = function() return "Heim" end
	local sounds, now = 0, 1000
	PlaySound = function() sounds = sounds + 1 end
	time = function() return now end
	-- menu: note window and marks
	local entries, root = {}, {}
	function root:CreateDivider() end
	function root:CreateTitle() end
	function root:CreateButton(text, fn) entries[#entries + 1] = { text = text, fn = fn } end
	function root:CreateCheckbox(text, isSet, toggle) entries[#entries + 1] = { text = text, isSet = isSet, toggle = toggle } end
	local add = uv(notes.OnLogin, "AddMenuEntries")
	add(nil, root, { unit = "target" })
	assert(#entries == 3 and entries[2].text == ns.L.NOTES_ENEMY and not entries[2].isSet(), "menu offers a note and two marks")
	entries[2].toggle()
	local key = notes.Key("Gank", "Andere Welt")
	assert(notes.Get(key).tag == "enemy" and entries[2].isSet() and not entries[3].isSet(), "enemy mark set from the menu")
	entries[3].toggle()
	assert(notes.Get(key).tag == "friend", "marks replace each other")
	entries[3].toggle()
	assert(notes.Get(key) == nil, "unmarked player without note is removed")
	local oldEdit = ns.ShowEditWindow
	ns.ShowEditWindow = function(_, _, _, _, accept) accept("Camps the flight master") end
	entries[1].fn()
	ns.ShowEditWindow = oldEdit
	assert(notes.Get(key).note == "Camps the flight master", "note saved from the window")
	wipe(entries)
	add(nil, root, { name = "Ally-Heim" })
	assert(#entries == 3, "chat names get the menu too")
	-- tooltip
	local lines = {}
	GameTooltip = { IsForbidden = function() return false end, GetUnit = function() return "Gank", "target" end,
		AddLine = function(_, text) lines[#lines + 1] = text end }
	notes.Set(key, "Gank", nil, "enemy")
	uv(notes.OnLogin, "OnUnitTooltip")(GameTooltip)
	assert(lines[1] == ns.L.NOTES_ENEMY .. ": Camps the flight master" and notes.Get(key).seen == now, "note in the tooltip")
	-- warning when a marked enemy shows up
	local printed = {}
	local oldPrint = ns.PrintAlways
	ns.PrintAlways = function(fmt, ...) printed[#printed + 1] = fmt:format(...) end
	notes:Apply()
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	eventFrame:GetScript("OnEvent")(eventFrame, "PLAYER_TARGET_CHANGED")
	eventFrame:GetScript("OnEvent")(eventFrame, "PLAYER_TARGET_CHANGED")
	assert(#printed == 1 and printed[1]:find("Gank", 1, true) and sounds == 1, "one warning with sound")
	notes.db.enabled = false
	notes:Apply()
	notes.db.enabled = true
	notes:Apply()
	ns.PrintAlways = oldPrint
	for k, v in pairs(saved) do _G[k] = v end
	ns.db.playerNotes = oldStore
	local hasChoice, hasTest
	for _, option in ipairs(notes.options) do
		if option.key == "enemySoundChoice" then hasChoice = #option.values() >= 3 end
		if option.type == "button" and option.func then hasTest = true end
	end
	assert(hasChoice and hasTest, "enemy sound: a choice of at least three and a test button")
	local played
	local oldPlay = ns.AlertSounds.play
	ns.AlertSounds.play = function(choice) played = choice end
	ns.AlertSounds.PlayWarning("ping")
	ns.AlertSounds.play = oldPlay
	assert(played == "ping", "a chosen sound is played")
	print("player notes OK")
end)()
-- Scout: node kinds, remembered spots, rare announcements
;(function()
	local scout = ns:GetModule("Scout")
	local list = {}
	scout.AddNode(list, 1731, "ore", 0.5, 0.5)
	scout.AddNode(list, 1731, "ore", 0.503, 0.498)
	scout.AddNode(list, 1731, "ore", 0.6, 0.5)
	scout.AddNode(list, 1617, "herb", 0.5, 0.5)
	assert(#list == 3 and list[1][5] == 2, "the same spot counts again, other spots and nodes are new")
	local last = {}
	assert(scout.ShouldAnnounce("g", 10, last) and not scout.ShouldAnnounce("g", 500, last)
		and scout.ShouldAnnounce("g", 611, last), "rares are announced again after ten minutes")
	-- gathering from a loot window
	local globals = { "C_Map", "UnitClassification", "UnitIsDead", "UnitGUID", "UnitName", "UnitLevel", "PlaySound",
		"GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSourceInfo", "IsFishingLoot" }
	local saved = {}
	for _, key in ipairs(globals) do
		saved[key] = rawget(_G, key)
	end
	local oldNodes, oldItem = ns.db.gatherNodes, C_Item
	local oldLootSlotTypes = Enum.LootSlotType
	local sources = ns:GetModule("LootSources")
	local oldSources, oldCount, oldMerged = ns.db.lootSources, sources.count, sources.merged
	local de = GetLocale() == "deDE"
	local copper, stone, herb = de and "Kupfererz" or "Copper Ore", de and "Rauer Stein" or "Rough Stone",
		de and "Friedensblume" or "Peacebloom"
	local oldHerb = { 0.1, 0.2, 1618, "herb", 3 }
	local oldVein = { 0.2, 0.3, 1731, "ore", 2 }
	local nodes = { oldHerb, oldVein }
	ns.db.gatherNodes = { [1429] = nodes }
	ns.db.lootSources, sources.count = { ["object:1618"] = { windows = 3, items = { [2447] = 3, [774] = 1 } } }, 1
	C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.4, y = 0.6 } end }
	local legacyName, requested = nil, nil
	C_Item = {
		GetItemInfoInstant = function(id)
			if id == 774 then return id, nil, nil, nil, nil, 3, 0 end
			return id, nil, nil, nil, nil, 7, id == 2447 and 9 or 7
		end,
		GetItemNameByID = function(id) if id == 2447 then return legacyName end end,
		RequestLoadItemDataByID = function(id) requested = id end,
	}
	local guid = "GameObject-0-1-2-3-1731-0042"
	local window = { { 774, "Malachite" }, { 2770, copper }, { 2835, stone }, { 2770, copper } }
	Enum.LootSlotType = { Item = 1, Money = 2, None = 0 }
	GetNumLootItems = function() return #window end
	GetLootSlotType = function() return Enum.LootSlotType.Item end
	GetLootSlotLink = function(slot) return ("|Hitem:%d|h[%s]|h"):format(unpack(window[slot])) end
	GetLootSourceInfo = function() return guid, 1 end
	IsFishingLoot = function() return false end
	UnitGUID = function() end
	sources.CaptureWindow()
	sources.CaptureWindow()
	local vein = nodes[3]
	assert(#nodes == 3 and vein[4] == "ore" and vein[5] == 1 and vein.items[2770] == copper and vein.items[2835] == stone
		and vein.items[774] == nil, "ore and stone names come from the loot window even without cached names")
	guid = "GameObject-0-1-2-3-1618-0043"
	window = { { 2447, herb } }
	C_Map.GetPlayerMapPosition = function() return { x = 0.1, y = 0.2 } end
	local symbols = {}
	for _, source in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		pcall(source, 1429, function(_, _, symbol) if symbol.kind == "gather" then symbols[#symbols + 1] = symbol end end)
	end
	assert(#symbols == 3 and symbols[3].texture:find("Ore", 1, true), "remembered vein on the world map")
	local function TooltipLines(symbol)
		local lines = {}
		symbol.tooltip({ AddLine = function(_, line) lines[#lines + 1] = line end }, symbol)
		return lines
	end
	local lines = TooltipLines(symbols[3])
	assert(#lines == 3 and lines[1] == copper and lines[2] == stone and lines[3] == ns.L.SCOUT_GATHERED:format(1),
		"the map shows the saved materials and the gathering count")
	assert(TooltipLines(symbols[1])[1] == ns.L.SCOUT_HERB and requested == 2447, "an uncached historical name is requested")
	legacyName = herb
	assert(TooltipLines(symbols[1])[1] == herb and TooltipLines(symbols[2])[1] == ns.L.SCOUT_ORE,
		"an old map marker gets a name only if the local history identifies one material")
	sources.CaptureWindow()
	assert(#nodes == 3 and oldHerb.items[2447] == herb and oldHerb[5] == 4, "gathering at an old marker saves the name in place")
	scout.db.gatherMap = false
	wipe(symbols)
	for _, source in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		pcall(source, 1429, function(_, _, symbol) if symbol.kind == "gather" then symbols[#symbols + 1] = symbol end end)
	end
	assert(#symbols == 0, "map option hides the symbols")
	scout.db.gatherMap = true
	-- rare nameplate
	local printed, sounds = {}, 0
	local oldPrint = ns.PrintAlways
	ns.PrintAlways = function(fmt, ...) printed[#printed + 1] = fmt:format(...) end
	UnitClassification = function(unit) return unit == "nameplate1" and "rareelite" or "normal" end
	UnitIsDead = function() return false end
	UnitGUID = function(unit) return "Creature-" .. unit end
	UnitName = function() return "Mor'Ladim" end
	UnitLevel = function() return 35 end
	PlaySound = function() sounds = sounds + 1 end
	local onNameplate = uv(scout.OnLogin, "OnNameplate")
	for _, unit in ipairs({ "nameplate1", "nameplate1", "nameplate2" }) do
		onNameplate(nil, "NAME_PLATE_UNIT_ADDED", unit)
	end
	assert(#printed == 1 and printed[1]:find("Mor'Ladim", 1, true) and printed[1]:find("35", 1, true) and sounds == 1,
		"a rare is announced once")
	ns.PrintAlways = oldPrint
	for _, key in ipairs(globals) do _G[key] = saved[key] end
	ns.db.gatherNodes, C_Item = oldNodes, oldItem
	Enum.LootSlotType = oldLootSlotTypes
	ns.db.lootSources, sources.count, sources.merged = oldSources, oldCount, oldMerged
	local rareChoice
	for _, option in ipairs(scout.options) do
		if option.key == "rareSoundChoice" then rareChoice = #option.values() >= 3 end
	end
	assert(rareChoice, "rare sound: a choice of at least three")
	print("scout OK")
end)()
-- Upgrades per slot: best upgrades of each slot, wearable now before "later", loading items are counted
;(function()
	local upgrades = ns:GetModule("Upgrades")
	local picked = upgrades.Pick({
		{ id = 1, slot = "INVTYPE_HEAD", gain = 5, state = true },
		{ id = 2, slot = "INVTYPE_HEAD", gain = 9, state = "later" },
		{ id = 3, slot = "INVTYPE_HEAD", gain = 7, state = true },
		{ id = 4, slot = "INVTYPE_HEAD", gain = 6, state = true },
		{ id = 5, slot = "INVTYPE_FEET", gain = 2, state = true },
		{ id = 6, slot = "INVTYPE_FEET", gain = 0, state = true },
		{ id = 7, slot = "INVTYPE_HAND", gain = 3, state = false },
	}, 3, upgrades.ORDER)
	assert(#picked == 2 and picked[1].slot == "INVTYPE_HEAD" and picked[2].slot == "INVTYPE_FEET", "slots in window order")
	assert(#picked[1].rows == 3 and picked[1].rows[1].id == 3 and picked[1].rows[2].id == 4 and picked[1].rows[3].id == 1,
		"wearable now first, by gain, three per slot")
	assert(#picked[2].rows == 1, "no gain is no upgrade")
	-- rating candidates from the loot data
	local oldData, oldItem, oldState, oldGain = ns.LootData, C_Item, ns.ItemLinkUpgradeState, ns.ItemUpgradeGain
	ns.LootData = { names = {}, items = { [100] = { { "npc:9", 1, 4 } }, [101] = {}, [102] = {} },
		encounters = { [2741] = { 4, { { 103, 2 } } } } }
	local loads = {}
	C_Item = setmetatable({
		GetItemInfoInstant = function(id) return id, nil, nil, id == 101 and "" or "INVTYPE_HEAD" end,
		GetItemInfo = function(id) if id ~= 102 then return "Item " .. id, "item:" .. id, 2, nil, 30 end end,
		RequestLoadItemDataByID = function(id) loads[#loads + 1] = id end,
		GetItemIconByID = function() return 1 end,
	}, { __index = oldItem })
	ns.ItemLinkUpgradeState = function(link) return link == "item:100" and true or link == "item:103" and "later" or false end
	ns.ItemUpgradeGain = function(link) return link == "item:100" and 4 or 8 end
	local rows, loading = upgrades.Rate()
	assert(#rows == 2 and loading == 1 and loads[1] == 102, "equippable candidates rated, missing data requested")
	local built = uv(upgrades.Open, "Build")()
	assert(built.items[1].text and built.items[2].text == "Item 100" and built.items[3].text:find("Item 103", 1, true)
		and built.items[3].right == "50%", "list with header, items and boss share")
	assert(built.title == ns.L.UPGRADES_LOADING:format(1), "title tells what is still loading")
	ns.LootData, C_Item, ns.ItemLinkUpgradeState, ns.ItemUpgradeGain = oldData, oldItem, oldState, oldGain
	-- the button lies above the character model scene
	local oldSlot, oldScene, oldPaper = rawget(_G, "CharacterMainHandSlot"), rawget(_G, "CharacterModelScene"), rawget(_G, "PaperDollFrame")
	CharacterMainHandSlot = { GetFrameLevel = function() return 12 end }
	CharacterModelScene = { GetFrameLevel = function() return 50 end }
	PaperDollFrame = CreateFrame("Frame")
	local level
	local oldCreate = CreateFrame
	CreateFrame = function(...)
		local f = oldCreate(...)
		f.SetFrameLevel = function(_, value) level = value end
		return f
	end
	local create = uv(upgrades.OnLogin, "CreateButton")
	for index = 1, 20 do
		if debug.getupvalue(create, index) == "button" then debug.setupvalue(create, index, nil) break end
	end
	create()
	CreateFrame = oldCreate
	assert(level == 55, "button above the model scene")
	CharacterMainHandSlot, CharacterModelScene, PaperDollFrame = oldSlot, oldScene, oldPaper
	print("upgrades per slot OK")
end)()
-- XP bar: extra shrinking
;(function()
	STATUS_BAR_SIZE_ADJUSTMENT = 3
	local w, h = xp.ScaledSize(1000, 17, 100, 100)
	assert(w == 1000 and h == 17, "100% leaves the size")
	w, h = xp.ScaledSize(1000, 17, 50, 50)
	assert(w == 500 and h == 8.5, "50% halves the size")
	w, h = xp.ScaledSize(1000, 17, 10, 30)
	assert(w == 100 and h == 5.1, "small sizes follow the percent")
	w, h = xp.ScaledSize(1000, 17, 0, 0)
	assert(w == 5 and h == 5, "never smaller than adjustment + 2")
	w, h = xp.ScaledSize(4, 4, 100, 100)
	assert(w == 4 and h == 4, "never larger than the standard size")
	local hookBars = uv(xp.OnLogin, "HookBars")
	local hookContainer, onSize, applySizes = uv(hookBars, "HookContainer"), uv(uv(hookBars, "HookContainer"), "OnContainerSize"), uv(xp.OnOptionChanged, "ApplySizes")
	assert(xp.SegmentCount(20, 1000, 1000) == 20, "full width keeps all section strokes")
	assert(xp.SegmentCount(20, 500, 1000) == 10, "half width keeps half the strokes at the same distance")
	assert(xp.SegmentCount(20, 10, 1000) == 1, "at least one segment")
	local function NewContainer(width)
		local c = { width = width, height = 17, resized = 0, dividers = 0, segments = nil, BarFrameTexture = { ClearAllPoints = function() end, SetPoint = function() end, GetAtlas = function() end } }
		function c:GetWidth() return self.width end
		function c:GetHeight() return self.height end
		function c:SetSize(a, b) self.width, self.height = a, b end
		function c:ResizeContainerBars() self.resized = self.resized + 1 end
		function c:UpdateDividers(n) self.dividers = self.dividers + 1; self.segments = n end
		function c:GetExpectedSegments() return 20 end
		return c
	end
	local container, second = NewContainer(600), NewContainer(600)
	SecondaryStatusTrackingBarContainer = second
	xp.db.bar1Width, xp.db.bar1Height, xp.db.bar2Width, xp.db.bar2Height = 50, 50, 100, 100
	hookContainer(container)
	hookContainer(second)
	assert(container.width == 300 and container.height == 8.5, "container 1 shrunk on hook")
	assert(second.width == 600 and second.height == 17, "container 2 keeps its own (standard) size")
	assert(container.segments == 10 and second.segments == 20, "strokes keep their distance on the narrower bar")
	container:SetSize(800, 17) -- Blizzard or Edit Mode sets a new standard size
	onSize(container)
	assert(container.width == 400 and container.height == 8.5 and container.segments == 10, "new standard size is shrunk again")
	-- The built-in Edit Mode width slider keeps the height already set by us.
	for _, width in ipairs({ 700, 900 }) do
		container:SetSize(width, container:GetHeight())
		onSize(container)
		assert(container.width == width / 2 and container.height == 8.5, "the native width slider does not rescale height")
	end
	xp.db.bar2Width, xp.db.bar2Height = 25, 100
	applySizes()
	assert(second.width == 150 and second.height == 17 and second.segments == 5, "container 2 follows its own setting")
	assert(container.width == 450 and container.segments == 10, "container 1 is not touched by setting 2")
	xp.db.bar1Width, xp.db.bar1Height, xp.db.bar2Width, xp.db.bar2Height = 100, 100, 100, 100
	applySizes()
	assert(container.width == 900 and container.height == 17 and container.segments == 20, "100% restores the standard size and strokes")
	assert(second.width == 600 and second.segments == 20, "100% restores container 2")
	SecondaryStatusTrackingBarContainer = nil
	print("xp bar size OK")
end)()
-- Quest item pick
GetQuestLogSpecialItemInfo = function(i) if i == 1 then return "item:5", 123, 3, false end end
IsQuestLogSpecialItemInRange = function() return nil end
C_QuestLog.GetDistanceSqToQuest = function() return 900 end
C_QuestLog.IsComplete = function() return false end
local pick = uv(uv(ns:GetModule("Quests").UpdateItemTicker, "UpdateItemButton"), "PickQuestItem")
assert(pick() == 1, "quest item picked")
print("xp/questitem OK")
-- Tracker sort
local q = ns:GetModule("Quests")
local watches = { 11, 12, 13 }
C_QuestLog.GetNumQuestWatches = function() return #watches end
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return watches[i] end
C_QuestLog.RemoveQuestWatch = function(id) for i, v in ipairs(watches) do if v == id then table.remove(watches, i) break end end end
C_QuestLog.AddQuestWatch = function(id) watches[#watches + 1] = id end
C_QuestLog.GetNumQuestLogEntries = function() return 4 end
local log = { { isHeader = true, title = "Brachland" }, { questID = 11, level = 15, title = "C" }, { questID = 12, level = 10, title = "A" }, { questID = 13, level = 12, title = "B" } }
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.GetQuestObjectives = function() return {} end
GetZoneText = function() return "Brachland" end
strcmputf8i = function(a, b) return a < b and -1 or (a > b and 1 or 0) end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local sort = uv(uv(q.UpdateTrackerSort, "QueueSort"), "SortTracker")
q.cdb = q.cdb or {}
q.cdb.watched, q.cdb.trackerTab = nil, "world"
q.db.classFirst, q.db.instanceTab, q.db.regionOnly = false, false, false
C_QuestLog.GetQuestTagInfo = function() return nil end
q.db.trackerSort = "level"; sort()
print("  level order:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "12,13,11")
q.db.trackerSort = "name"; sort()
assert(table.concat(watches, ",") == "12,13,11")
-- Client that puts new watches on top: detected and corrected.
C_QuestLog.AddQuestWatch = function(id) table.insert(watches, 1, id) end
q.db.trackerSort = "default"; q.db.classFirst = true; sort()
print("  top-insert default:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "11,12,13")
sort()
assert(table.concat(watches, ",") == "11,12,13", "stable, no loop")
-- Class quests first, instance tab, region filter
local function setuv(fn, name, value) for i = 1, 200 do local n = debug.getupvalue(fn, i) if not n then return end if n == name then debug.setupvalue(fn, i, value) return end end end
local facts = uv(uv(sort, "DesiredWatches"), "QuestFacts") or uv(sort, "QuestFacts")
setuv(facts, "playerClassName", "Schamane")
log = { { isHeader = true, title = "Brachland" }, { questID = 11, level = 15, title = "C" }, { questID = 12, level = 10, title = "A" },
	{ isHeader = true, title = "Schamane" }, { questID = 14, level = 20, title = "Klasse" },
	{ isHeader = true, title = "Die Todesminen" }, { questID = 15, level = 18, title = "Dungeon" },
	{ isHeader = true, title = "Mulgore" }, { questID = 16, level = 8, title = "Fern" } }
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetQuestTagInfo = function() return nil end
Enum.UIMapType = { Dungeon = 4 }
C_Map.GetMapInfo = function(id) if id == 36 then return { mapType = 4, name = "Die Todesminen" } end end
local isInst = uv(facts, "IsInstanceQuest")
setuv(uv(isInst, "InstanceNames"), "instanceNames", nil)
C_QuestLog.IsOnMap = function() return false end
q.cdb.watched = { [11] = true, [12] = true, [14] = true, [15] = true, [16] = true }
for i = #watches, 1, -1 do table.remove(watches, i) end
q.db.instanceTab = true; q.db.trackerSort = "level"
sort()
print("  world tab:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,16,12,11", "class first, instance quest on its own tab")
do
	local savedInfo, savedObjectives, savedDistance = C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives, C_QuestLog.GetDistanceSqToQuest
	local logReads, objectiveReads, distanceReads = 0, 0, 0
	C_QuestLog.GetInfo = function(index) logReads = logReads + 1 return savedInfo(index) end
	C_QuestLog.GetQuestObjectives = function() objectiveReads = objectiveReads + 1 return {} end
	C_QuestLog.GetDistanceSqToQuest = function() distanceReads = distanceReads + 1 return 0, true end
	sort()
	assert(logReads == #log and objectiveReads == 0 and distanceReads == 0,
		"the stable tracker sort and both tabs share one log read and skip unused keys")
	C_QuestLog.GetInfo, C_QuestLog.GetQuestObjectives, C_QuestLog.GetDistanceSqToQuest = savedInfo, savedObjectives, savedDistance
end
q.cdb.trackerTab = "instance"; sort()
assert(table.concat(watches, ",") == "15", "instance tab")
do
	local updateTabs = uv(sort, "UpdateTabs")
	local savedTabs = uv(updateTabs, "tabs")
	local textWrites, highlightWrites = 0, 0
	local function Tab()
		local tab = NewFrame("Button")
		tab.SetText = function() textWrites = textWrites + 1 end
		tab.GetTextWidth = function() return 40 end
		tab.GetFontString = function() return NewFrame("FontString") end
		tab.Underline = { SetShown = function() highlightWrites = highlightWrites + 1 end }
		return tab
	end
	setuv(updateTabs, "tabs", { world = Tab(), instance = Tab() })
	updateTabs(4, 1, "world")
	updateTabs(4, 1, "world")
	assert(textWrites == 2 and highlightWrites == 2, "unchanged tracker tabs do not rewrite their UI")
	updateTabs(3, 1, "instance")
	assert(textWrites == 3 and highlightWrites == 4, "changed count and selection refresh independently")
	setuv(updateTabs, "tabs", savedTabs)
end
q.cdb.watched[15] = nil; sort()
print("  instance tab without instance quests:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,16,12,11", "empty instance tab falls back to world")
q.cdb.watched[15] = true
q.cdb.trackerTab = "world"; q.db.regionOnly = true; sort()
print("  region only:", table.concat(watches, ","))
assert(table.concat(watches, ",") == "14,12,11", "region filter keeps class quests")
q.db.regionOnly, q.db.instanceTab, q.db.classFirst = false, false, false
q.db.trackerSort = "zone"; sort()
q.db.trackerSort = "progress"; sort()
-- Only quests ready to turn in (everything when none is)
do
	local readyID = 12
	local realReady = ns.IsQuestReady
	local savedAdd, adds = C_QuestLog.AddQuestWatch, 0
	C_QuestLog.AddQuestWatch = function(id) adds = adds + 1 return savedAdd(id) end
	ns.IsQuestReady = function(id) return id == readyID end
	q.cdb.watched = nil
	q.db.trackerSort = "default"; q.db.readyOnly = true; sort()
	assert(table.concat(watches, ",") == "12" and adds == 0, "filtering out other quests leaves the existing watch in place")
	readyID = nil; sort()
	table.sort(watches)
	assert(table.concat(watches, ",") == "11,12,14,15,16", "nothing ready: all shown again")
	q.db.readyOnly = false; sort()
	ns.IsQuestReady = realReady
	C_QuestLog.AddQuestWatch = savedAdd
end
print("sort OK")
-- Reputation text
local repText = uv(uv(xp.OnLogin, "HookBars"), "UpdateRepText")
local rbar = { name = "Donnerfels %d / %d", value = 1200, max = 3000, SetBarText = function(_, t) print("  rep:", t) end }
for _, f in ipairs({ "percent", "remaining", "full" }) do xp.db.repFormat = f; repText(rbar) end
IsResting = function() return true end
print("rep OK")
-- Unified moving/locking
local mover = ns:GetModule("Mover")
local disp = NewFrame("Frame")
local entry = ns:RegisterDisplay(disp, "TestDisplay", function(f) f:SetPoint("CENTER") end)
IsAltKeyDown = function() return true end
GetMouseFoci = function() return { disp } end
assert(ns.db.locked == nil and not ns.db.unlocked["M:TestDisplay"], "locked by default")
clicks = 0
PlaySound = function() clicks = clicks + 1 end
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(ns.db.unlocked["M:TestDisplay"] == true, "alt right-click unlocks")
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(ns.db.unlocked["M:TestDisplay"] == nil, "alt right-click locks")
assert(clicks == 2, "a click for unlocking and for locking")
ns.db.lockSound = false
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(clicks == 2, "no click with the option off")
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
ns.db.lockSound = true
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
ns.db.lockAll = true
mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(uv(mover.GLOBAL_MOUSE_UP, "moving") == nil, "locked: no move")
ns.db.lockAll = false
ns:SetAllLocked(false)
-- Window locking uses the title row, including when Alt is held.
;(function()
	local window = {
		GetLeft = function() return 10 end, GetRight = function() return 400 end,
		GetTop = function() return 500 end, GetEffectiveScale = function() return 1 end,
	}
	local child = NewFrame("Frame")
	child.IsObjectType = function(_, kind) return kind == "Frame" end
	local findTarget = uv(mover.GLOBAL_MOUSE_DOWN, "FindTarget")
	local savedWheel = uv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel")
	local savedCursor, savedAlt, savedFoci = GetCursorPosition, IsAltKeyDown, GetMouseFoci
	setuv(mover.GLOBAL_MOUSE_DOWN, "FindTarget", function() return window, "CharacterFrame" end)
	setuv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel", function() end)
	local function RightClick(region, x, y, alt)
		IsAltKeyDown = function() return alt end
		GetMouseFoci = function() return { region } end
		GetCursorPosition = function() return x, y end
		mover:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	end

	ns.db.unlocked.CharacterFrame = nil
	RightClick(window, 200, 300, false)
	RightClick(child, 200, 300, true)
	assert(not ns.db.unlocked.CharacterFrame, "window contents cannot unlock the window")
	RightClick(window, 200, 478, false)
	assert(ns.db.unlocked.CharacterFrame, "a window without a title container uses the top row")

	window.TitleContainer = {
		GetTop = function() return 499 end, GetHeight = function() return 20 end,
		GetLeft = function() return 40 end, GetRight = function() return 376 end,
		GetEffectiveScale = function() return 1.2 end,
	}
	RightClick(child, 240, 568, true)
	RightClick(window, 25, 590, false)
	assert(ns.db.unlocked.CharacterFrame, "the real title bounds exclude nearby window content and trim")
	local close = NewFrame("Button")
	RightClick(close, 240, 590, true)
	assert(ns.db.unlocked.CharacterFrame, "title bar controls keep their right-clicks")
	RightClick(child, 240, 590, false)
	assert(not ns.db.unlocked.CharacterFrame, "right-click on the title locks")
	RightClick(window, 240, 590, true)
	assert(ns.db.unlocked.CharacterFrame, "Alt-right-click on the title unlocks")
	GetCursorPosition, IsAltKeyDown, GetMouseFoci = savedCursor, savedAlt, savedFoci
	ns.db.unlocked.CharacterFrame = nil
	setuv(mover.GLOBAL_MOUSE_DOWN, "FindTarget", findTarget)
	setuv(mover.GLOBAL_MOUSE_DOWN, "UpdateWindowWheel", savedWheel)
end)()
ns:ResetFramePositions()
assert(entry and not ns:HasSavedPosition(entry))
assert(next(ns.db.unlocked) == nil, "reset locks again")
print("mover OK")
;(function()
	local talents = ns:GetModule("Talents")
	local savedBook, savedSpell, savedFrame, savedRegistry = C_SpellBook, C_Spell, CreateFrame, EventRegistry
	local savedKnown, savedAfter = IsPlayerSpell, C_Timer.After
	local savedIndex, savedQueue = Enum.SpellBookSkillLineIndex, uv(talents.Update, "queueTrainerBook")
	local savedTrainer, savedLevel = talents.db.trainer.MAGE, UnitLevel
	local savedAvailable, savedTrainable, savedColor = SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE, SPELLBOOK_FONT_COLOR
	Enum.SpellBookSkillLineIndex = { General = 1 }
	IsPlayerSpell = function() return false end
	UnitLevel = function() return 20 end
	SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE = "Level %d", "Trainable"
	SPELLBOOK_FONT_COLOR = { GetRGB = function() return 0.15, 0.1, 0.05 end }

	local slots = {
		{ name = "A", spellID = 101 },
		{ name = "Frost", spellID = 102, subName = "Rank 1" },
		{ name = "Frost", spellID = 104, subName = "Rank 2" },
	}
	C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 2 end,
		GetSpellBookSkillLineInfo = function(line)
			return line == 1 and { name = "General", itemIndexOffset = 0, numSpellBookItems = 1 }
				or { name = "Frost", itemIndexOffset = 1, numSpellBookItems = 2 }
		end,
		GetSpellBookItemInfo = function(slot) return slots[slot] end,
		IsSpellKnown = function(id) return id == 101 or id == 102 or id == 108 end,
		GetCurrentLevelSpells = function(level) return level == 10 and { 101, 103, 104, 108 } or {} end,
	}
	C_Spell = {
		GetSpellName = function(id) return ({ [101] = "A", [103] = "C", [104] = "Frost", [108] = "Known" })[id] end,
		GetSpellSubtext = function(id) return id == 104 and "Rank 2" or "" end,
		GetSpellTexture = function() return 1 end,
	}
	talents.db.trainer.MAGE = {
		{ name = "B", level = 30, icon = 1 },
		{ name = "Known", level = 10 },
		{ name = "Frost", rank = "Rank 2", level = 14, line = "Frost" },
		{ name = "Frost", rank = "Rank 3", level = 20, line = "Frost" },
	}

	local frames, onPageChanged, fontWrites, bookScripts = {}, nil, 0, {}
	CreateFrame = function(kind, name, parent, template)
		local frame = savedFrame(kind, name, parent, template)
		frame.SetPoint = function(self, ...) self.testAnchor = { ... } end
		frame.testTemplate = template
		if template == "SpellBookItemTemplate" then
			for _, text in ipairs({ frame.Name, frame.SubName, frame.RequiredLevel }) do
				text.GetFont = function() return "Font", 14, "OUTLINE" end
				text.SetFont = function(self, _, _, flags) self.testFlags = flags fontWrites = fontWrites + 1 end
				text.SetText = function(self, content) self.testText = content end
			end
		end
		frames[#frames + 1] = frame
		return frame
	end
	EventRegistry = { RegisterCallback = function(_, _, fn) onPageChanged = fn end }
	local category = { skillLineIndex = 1, GetSpellBank = function() return Enum.SpellBookSpellBank.Player end }
	local view = { GetWidth = function() return 220 end, GetHeight = function() return 130 end }
	local nativeLayout = { { gridRow = 1, gridColumn = 1, isHeader = true }, { gridRow = 2, gridColumn = 1 } }
	local pager = {
		ViewFrames = { view, view }, columnsPerRow = 2, viewsPerPage = 1, xPadding = 10, yPadding = 10,
		viewDataList = { nativeLayout }, GetFrameLevel = function() return 10 end,
		PagingControls = NewFrame("Frame"),
	}
	pager.PagingControls.GetCurrentPage = function() return 1 end
	pager.PagingControls.GetMaxPages = function() return 1 end
	local book = {
		PagedSpellsFrame = pager, IsVisible = function() return true end,
		GetActiveCategoryMixin = function() return category end, categoryMixins = { category },
		OnActiveCategoryChanged = function() end, HookScript = function(_, script, fn) bookScripts[script] = fn end,
	}
	uv(talents.OnLogin, "SetupSpellsBook")(book)
	talents:Update()
	local row, nextPage, previousPage
	for _, frame in ipairs(frames) do
		if frame.testTemplate == "SpellBookItemTemplate" then row = frame end
		if frame.testTemplate == "PagingControlsNextPageButtonTemplate" then nextPage = frame end
		if frame.testTemplate == "PagingControlsPrevPageButtonTemplate" then previousPage = frame end
	end
	assert(row.fpTrainerEntry.spellID == 103 and row.testAnchor[4] == 115 and row.testAnchor[5] == -70,
		"the lowest-level preview uses the free cell alongside a native spell")
	assert(row.Name.testFlags == "" and row.RequiredLevel.testText:find("Trainable", 1, true),
		"readable text and trainer label")
	assert(nextPage:IsShown() and #nativeLayout == 2, "overflow uses an arrow and leaves the native page data intact")
	local refresh, scheduled = nil, 0
	C_Timer.After = function(_, fn) refresh, scheduled = fn, scheduled + 1 end
	nextPage:GetScript("OnClick")()
	nextPage:GetScript("OnClick")()
	previousPage:GetScript("OnClick")()
	assert(scheduled == 1, "several page turns in one frame share a refresh")
	local originalAnchor = row.testAnchor
	refresh()
	assert(row.fpTrainerEntry.spellID == 103 and row.testAnchor == originalAnchor and fontWrites == 3,
		"an unchanged page reuses the anchors and font settings")
	C_Timer.After = savedAfter
	nextPage:GetScript("OnClick")()
	assert(row.fpTrainerEntry.name == "B" and row.testAnchor[4] == 0, "the higher-level preview follows on the next page")
	assert(row.RequiredLevel.testText == "Level 30", "future entry shows the required level")
	previousPage:GetScript("OnClick")()
	assert(row.fpTrainerEntry.spellID == 103 and fontWrites == 3, "previous arrow reuses the existing fonts")
	local originalEntry = row.fpTrainerEntry
	bookScripts.OnHide()
	bookScripts.OnShow()
	assert(row.fpTrainerEntry == originalEntry, "reopening the book reuses the spell results")
	pager.viewsPerPage = 2
	onPageChanged()
	assert(not nextPage:IsShown(), "the second visible book page also has room for previews")
	pager.viewsPerPage = 1
	category.skillLineIndex = 2
	onPageChanged()
	assert(row.fpTrainerEntry.rank == "Rank 3" and not nextPage:IsShown(), "native future ranks are skipped in their own category")
	talents.db.enabled = false
	talents:Update()
	assert(not frames[1]:IsShown(), "disabling hides only the preview layer")
	talents.db.enabled = true
	talents:Update()
	assert(frames[1]:IsShown(), "previews reappear in the active category")

	local savedTicker = C_Timer.NewTicker
	local pending
	C_Timer.NewTicker = function(_, fn)
		pending = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return pending
	end
	talents:Update()
	local oldScan = pending
	oldScan:Run()
	bookScripts.OnHide()
	assert(oldScan.cancelled and not frames[1]:IsShown(), "closing the book cancels an unfinished spell scan")
	bookScripts.OnShow()
	assert(pending ~= oldScan and not pending.cancelled, "reopening starts a new scan")
	talents:Update()
	assert(pending and not pending.cancelled, "changed spell data replaces the current scan")
	bookScripts.OnHide()
	C_Timer.NewTicker = savedTicker

	local collect = uv(uv(talents.Update, "queueTrainerBook"), "RefreshTrainerBook")
	collect = uv(collect, "CollectTrainerSpells")
	local trainerList = uv(collect, "TrainerList")
	local savedShaman, savedSkills = talents.db.trainer.SHAMAN, C_SkillInfo
	setuv(collect, "playerClass", "SHAMAN")
	talents.db.trainer.SHAMAN = {
		{ name = "Welle der Heilung", rank = "Rang 2", level = 6, line = "Wiederherstellung" },
		{ name = "Großer Lehrerzauber", level = 40, line = "Wiederherstellung" },
	}
	local restoration = { name = "Wiederherstellung", itemIndexOffset = 0, numSpellBookItems = 1 }
	C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 2 end,
		GetSpellBookSkillLineInfo = function(line)
			return line == 2 and restoration or { name = "Allgemein", itemIndexOffset = 0, numSpellBookItems = 0 }
		end,
		GetSkillLineIndexByID = function() return nil end,
		GetSpellBookItemInfo = function() return { spellID = 332, name = "Welle der Heilung", subName = "Rang 2" } end,
		IsSpellKnown = function(id) return id == 332 end,
		GetCurrentLevelSpells = function() return {} end,
	}
	C_SkillInfo = { GetSkillLineInfoByID = function(id) return id == 374 and restoration or nil end }
	C_Spell.GetSpellName = function(id)
		return ({ [332] = "Welle der Heilung", [547] = "Welle der Heilung", [2008] = "Geist der Ahnen" })[id]
	end
	C_Spell.GetSpellSubtext = function(id)
		return ({ [332] = "Rang 2", [547] = "", [2008] = "Rang 1" })[id]
	end

	local scan = uv(talents.OnLogin, "ScanTrainer")
	local savedTrainerAPI, savedTrainerType = C_Trainer, Enum.TrainerType
	local savedGetFilter, savedSetFilter = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
	local savedCount, savedService, savedSkill = GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine
	Enum.TrainerType = { Class = 0, Pet = 1, Tradeskills = 2 }
	C_Trainer = { GetTrainerType = function() return Enum.TrainerType.Class end }
	local filters = { available = true, unavailable = false, used = false }
	GetTrainerServiceTypeFilter = function(filter) return filters[filter] end
	SetTrainerServiceTypeFilter = function(filter, enabled) filters[filter] = enabled end
	GetNumTrainerServices = function() return 1 end
	GetTrainerServiceInfo = function()
		assert(filters.available and filters.unavailable and filters.used, "the scan includes every trainer filter")
		return "Welle der Heilung", "available", 136052, 6, "Rang 2"
	end
	GetTrainerServiceSkillLine = function() return "Wiederherstellung" end
	scan()
	assert(#trainerList() == 2 and trainerList()[1].icon == 136052 and trainerList()[2].level == 40,
		"a starting-area trainer updates its ranks and keeps the previously recorded high-level spells")
	assert(filters.available and not filters.unavailable and not filters.used, "the user's trainer filters are restored")

	local results
	collect(function(spells) results = spells end)
	assert(#results[2] == 3 and results[2][1].spellID == 2008 and results[2][1].level == 12
		and results[2][2].spellID == 547 and results[2][2].level == 12
		and results[2][2].rank == ns.L.TALENTS_SPELL_RANK:format(3) and results[2][3].level == 40,
		"at level 6 the indexed preview includes new spells and higher ranks in Restoration, minus the learned rank")
	UnitLevel = function() return 6 end
	talents:Update()
	assert(row.fpTrainerEntry.spellID == 2008 and row.RequiredLevel.testText == "Level 12",
		"a Shaman future spell is drawn inside the Restoration tab with its level")

	C_Trainer, Enum.TrainerType = savedTrainerAPI, savedTrainerType
	GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = savedGetFilter, savedSetFilter
	GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine = savedCount, savedService, savedSkill
	talents.db.trainer.SHAMAN, C_SkillInfo = savedShaman, savedSkills
	setuv(collect, "playerClass", "MAGE")
	C_SpellBook, C_Spell, CreateFrame, EventRegistry = savedBook, savedSpell, savedFrame, savedRegistry
	IsPlayerSpell, UnitLevel = savedKnown, savedLevel
	SPELLBOOK_AVAILABLE_AT, SPELLBOOK_TRAINABLE, SPELLBOOK_FONT_COLOR = savedAvailable, savedTrainable, savedColor
	Enum.SpellBookSkillLineIndex, talents.db.trainer.MAGE = savedIndex, savedTrainer
	setuv(talents.Update, "queueTrainerBook", savedQueue)
	print("trainer spells in spellbook OK")
end)()
-- Helpers: disenchant detection and fishing binding
local helpers = ns:GetModule("Helpers")
IsPlayerSpell = function(id) return id == 13262 or id == 7620 end
C_Container.GetContainerItemInfo = function() return { hyperlink = "item:1", stackCount = 1 } end
C_Item.GetItemInfo = function() return "Sword", "item:1", 2, 10, 1, "W", "S", 1, "INVTYPE_WEAPON", 1, 100, 2, 7 end
Enum.ItemClass = Enum.ItemClass or {}
Enum.ItemClass.Weapon, Enum.ItemClass.Armor, Enum.ItemClass.Tradegoods, Enum.ItemClass.Recipe = 2, 4, 7, 9
Enum.ItemQuality.Uncommon, Enum.ItemQuality.Epic = 2, 4
local proc = uv(uv(helpers.MODIFIER_STATE_CHANGED, "ShowGlows"), "ProcessSpell")
assert(proc(0, 1) == 13262, "disenchant")
;(function()
	local savedBind, savedClear, savedTimer = SetOverrideBindingClick, ClearOverrideBindings, C_Timer.NewTimer
	local savedCombat, savedMounted, savedFoci, savedExists = InCombatLockdown, IsMounted, GetMouseFoci, UnitExists
	local savedPosition, savedInventory, savedCursor = GetCursorPosition, GetInventoryItemID, GetCursorInfo
	local savedShift, savedAlt, savedCtrl, savedCount = IsShiftKeyDown, IsAltKeyDown, IsControlKeyDown, C_Item.GetItemCount
	local savedDelta, savedMouseDown = GetCursorDelta, IsMouseButtonDown
	local savedInstant, savedSubclasses = C_Item.GetItemInfoInstant, Enum.ItemWeaponSubclass
	local savedSlots, savedBag, savedTooltip = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_TooltipInfo.GetBagItem
	local button = _G.ForeverPlusFishButton
	local tracker = _G.ForeverPlusFishingMotion
	local savedAttribute, attrs = button.SetAttribute, {}
	local savedWeapons, savedEquip = helpers.cdb.fishingWeapons, helpers.db.fishingEquip
	helpers.cdb.fishingWeapons = {}
	local shift, offHand, bagCounts = false, 2, { [1] = 1, [2] = 1 }
	local binding, timer, equipped, blocked, mouseover, focus, cursor = nil, nil, 1, false, false, nil, nil
	local x = 100
	button.SetAttribute = function(_, key, value) attrs[key] = value end
	SetOverrideBindingClick = function(_, _, key, name) binding = key .. ">" .. name end
	ClearOverrideBindings = function() binding = nil end
	C_Timer.NewTimer = function(_, callback)
		timer = { Cancel = function(self) self.cancelled = true end, expire = callback }
		return timer
	end
	InCombatLockdown = function() return blocked end
	IsMounted = function() return false end
	GetMouseFoci = function() return { focus } end
	UnitExists = function() return mouseover end
	GetCursorPosition = function() return x, 100 end
	GetInventoryItemID = function(_, slot) if slot == INVSLOT_MAINHAND then return equipped end return offHand end
	GetCursorInfo = function() return cursor end
	IsShiftKeyDown = function() return shift end
	IsAltKeyDown = function() return false end
	IsControlKeyDown = function() return false end
	C_Item.GetItemCount = function(id) return bagCounts[id] or 0 end
	Enum.ItemWeaponSubclass = { Fishingpole = 20 }
	C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 2, id >= 6256 and 20 or 7 end
	local bagItems = { { itemID = 1 }, { itemID = 6257, isLocked = true }, { itemID = 6258 }, { itemID = 6256 } }
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end
	C_Container.GetContainerItemInfo = function(_, slot) return bagItems[slot] end
	C_TooltipInfo.GetBagItem = function(_, slot)
		return { lines = slot == 3 and { { leftColor = { r = 1, g = 0.1, b = 0.1 } } } or {} }
	end
	local function click()
		helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
		assert(not binding, "the first press alone does not arm the button")
		helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	end

	assert(helpers.db.fishingMenu == nil and helpers.db.fishing and savedEquip and helpers.db.fishingRestore,
		"the three core angler options are enabled by default and the old player-frame rod shortcut is gone")
	click()
	assert(not binding, "a plain pair never equips a pole from the bag")
	shift = true
	helpers.db.fishingEquip = false
	click()
	assert(not binding, "no override without an equipped pole while the option is off")
	helpers.db.fishingEquip = true
	blocked = true
	click()
	blocked, mouseover = false, true
	click()
	mouseover, focus = false, UIParent
	click()
	focus, cursor = nil, "item"
	click()
	assert(not binding, "combat, mouseover units, UI and a held item prevent auto-equip")
	cursor = nil
	helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	x = 180
	helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	assert(not binding, "camera turn does not arm fishing")
	helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
	GetCursorDelta = function() return 8, 0 end
	tracker:GetScript("OnUpdate")(tracker)
	GetCursorDelta = savedDelta
	helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
	assert(not binding, "camera motion cancels the gesture even if the pointer stayed locked in place")
	click()
	GetCursorDelta = function() return 0, 8 end
	tracker:GetScript("OnUpdate")(tracker)
	GetCursorDelta = savedDelta
	assert(not binding, "mouse movement during the double-click window releases the camera binding")
	IsMouseButtonDown = function() return true end
	click()
	IsMouseButtonDown = savedMouseDown
	assert(not binding, "a physical press that is already underway keeps its native release")
	click()
	assert(binding == "SHIFT-BUTTON2>ForeverPlusFishButton" and attrs.type == "macro" and attrs.useOnKeyDown == false
		and attrs.macrotext == "/equipslot [@mouseover,noexists,nocombat,nomounted,mod:shift] 16 item:6256",
		"the first pair selects the unlocked pole for a guarded main-hand equip")
	local equipTimer = timer
	local postClick = button:GetScript("PostClick")
	postClick(button, "LeftButton", true)
	assert(binding and not equipTimer.cancelled, "a secure mouse action can still be waiting for the release")
	postClick(button, "LeftButton", false)
	assert(not binding and equipTimer.cancelled, "consuming a pair cancels its override and timeout")
	equipped, offHand = 6256, nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	click()
	assert(not binding, "Shift with a pole equipped leaves the gear alone")
	shift = false
	click()
	assert(binding == "BUTTON2>ForeverPlusFishButton" and attrs.type == "spell" and attrs.spell == 7620 and attrs.useOnKeyDown == false,
		"the next pair casts Fishing on release after the pole is equipped")
	timer.expire()
	assert(not binding, "an unused binding expires")
	equipped = nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	local restore = helpers.db.fishingRestore
	helpers.db.fishingRestore = false
	click()
	assert(not binding, "restoration can be disabled independently")
	helpers.db.fishingRestore = restore
	click()
	local condition = "[@mouseover,noexists,nocombat,nomounted,nomod]"
	assert(binding == "BUTTON2>ForeverPlusFishButton" and attrs.type == "macro" and attrs.useOnKeyDown == false
		and attrs.macrotext == "/equipslot " .. condition .. " 16 item:1\n/equipslot " .. condition .. " 17 item:2",
		"after removing the pole, a plain pair restores the saved weapon and shield")
	timer.expire()
	equipped = 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	bagCounts[1] = nil
	click()
	assert(not binding, "a missing saved main hand leaves the normal click free")
	bagCounts[1], equipped = 1, 1
	click()
	assert(binding and attrs.macrotext == "/equipslot " .. condition .. " 17 item:2",
		"only the missing shield is equipped")
	timer.expire()
	offHand = 2
	click()
	assert(not binding, "already wearing the saved set leaves the plain click free")
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_OFFHAND)
	equipped = 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	click()
	assert(not binding, "a later weapon upgrade is kept after the fishing set has been restored")
	offHand = nil
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_OFFHAND)
	local splitUpdate = timer
	click()
	assert(not binding, "a normal click during a split equipment update leaves a manually removed shield alone")
	equipped = 6256
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	assert(splitUpdate.cancelled and helpers.cdb.fishingWeapons.main == 3 and helpers.cdb.fishingWeapons.off == 2,
		"manually equipping a pole just after a weapon change remembers the new weapon and its shield")
	bagCounts[2], equipped = nil, 3
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	assert(not helpers.cdb.fishingWeapons.pending, "an unavailable shield does not keep a restored main hand pending")
	equipped = nil
	shift, bagItems = true, {}
	helpers:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", INVSLOT_MAINHAND)
	click()
	assert(not binding, "no override when there is no pole to equip")

	helpers.db.fishingEquip = savedEquip
	helpers.cdb.fishingWeapons = savedWeapons
	button.SetAttribute = savedAttribute
	SetOverrideBindingClick, ClearOverrideBindings, C_Timer.NewTimer = savedBind, savedClear, savedTimer
	InCombatLockdown, IsMounted, GetMouseFoci, UnitExists = savedCombat, savedMounted, savedFoci, savedExists
	GetCursorPosition, GetInventoryItemID, GetCursorInfo = savedPosition, savedInventory, savedCursor
	GetCursorDelta = savedDelta
	IsShiftKeyDown, IsAltKeyDown, IsControlKeyDown, C_Item.GetItemCount = savedShift, savedAlt, savedCtrl, savedCount
	C_Item.GetItemInfoInstant, Enum.ItemWeaponSubclass = savedInstant, savedSubclasses
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_TooltipInfo.GetBagItem = savedSlots, savedBag, savedTooltip
end)()
print("helpers OK")
;(function()
	assert(rawget(_G, "ForeverPlusFishingMenu") == nil and uv(helpers.OnLogin, "CreateFishingMenu") == nil,
		"angler shortcut button on the player frame is removed")
	local fishingSettings, optionByKey = {}, {}
	for _, option in ipairs(helpers.options) do
		if option.key and option.key:match("^fishing") then
			fishingSettings[#fishingSettings + 1] = option.key
			optionByKey[option.key] = option
		end
	end
	assert(table.concat(fishingSettings, ",") == "fishing,fishingEquip,fishingRestore,fishingHideUI,fishingSound,fishingBear,fishingBearSound",
		"settings expose all angler mode options without the removed player-frame shortcut")
	assert(optionByKey.fishingEquip.parent == "fishing" and optionByKey.fishingRestore.parent == "fishing"
		and optionByKey.fishingHideUI.parent == "fishing" and optionByKey.fishingSound.parent == "fishing"
		and optionByKey.fishingBear.parent == "fishing" and optionByKey.fishingBearSound.parent == "fishingBear",
		"angler settings keep parent dependencies intact")
	assert(optionByKey.fishingHideUI.new == true and optionByKey.fishingSound.new == true
		and optionByKey.fishingBear.new == true and optionByKey.fishingBearSound.new == true,
		"newer angler options remain marked NEW")
	local subKeys = {}
	for _, feature in ipairs(ns.PortraitModes.FEATURES) do
		if feature.key == "angler" then
			for _, sub in ipairs(feature.subOptions or {}) do
				subKeys[#subKeys + 1] = sub.key
			end
		end
	end
	assert(table.concat(subKeys, ",") == "fishingEquip,fishingRestore,fishingHideUI,fishingSound,fishingBear,fishingBearSound",
		"PortraitModes angler mode exposes all six angler sub-options")
end)()
;(function()
	local savedChannel, savedVisibility, savedGet, savedSet = UnitChannelInfo, SetUIVisibility, GetCVar, SetCVar
	local originalVisibility = UIParent:IsShown()
	local spellID
	local volumes = { Sound_SFXVolume = "0.2", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.8", Sound_DialogVolume = "0.6" }
	UnitChannelInfo = function()
		if spellID then return C_Spell.GetSpellName(spellID), nil, nil, nil, nil, nil, nil, spellID end
	end
	SetUIVisibility = function(visible) UIParent:SetShown(visible) end
	GetCVar = function(key) return volumes[key] end
	SetCVar = function(key, value) volumes[key] = value end
	local event = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	UIParent:Show()
	ns.SetOption("Helpers", "fishingHideUI", true)
	ns.SetOption("Helpers", "fishingSound", true)
	spellID = 10
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	assert(UIParent:IsShown() and volumes.Sound_MusicVolume == "0.4", "an unrelated channel leaves the UI and volumes alone")
	spellID = 7620
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	assert(not UIParent:IsShown() and volumes.Sound_SFXVolume == "0.65" and volumes.Sound_MusicVolume == "0.1",
		"a real Fishing channel hides the UI and makes effects easier to hear")
	volumes.Sound_DialogVolume = "0.7"
	spellID = nil
	event(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
	assert(UIParent:IsShown() and volumes.Sound_SFXVolume == "0.2" and volumes.Sound_MusicVolume == "0.4"
		and volumes.Sound_AmbienceVolume == "0.8" and volumes.Sound_DialogVolume == "0.7",
		"channel end restores the UI and original volumes while preserving a manual change")
	UIParent:Hide()
	spellID = 7620
	event(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
	event(nil, "PLAYER_LOGOUT")
	assert(not UIParent:IsShown() and volumes.Sound_SFXVolume == "0.2" and volumes.Sound_MusicVolume == "0.4",
		"logout restores the volumes and leaves an already-hidden UI hidden")
	spellID = nil
	ns.SetOption("Helpers", "fishingHideUI", false)
	ns.SetOption("Helpers", "fishingSound", false)
	UIParent:SetShown(originalVisibility)
	UnitChannelInfo, SetUIVisibility, GetCVar, SetCVar = savedChannel, savedVisibility, savedGet, savedSet
end)()
;(function()
	-- Angler mode Nat Pagle flash & native sounds: trigger, geometry/animation, delayed splash, abort, options and previews.
	local showBear = uv(helpers.PreviewBear, "ShowAnglerBear")
	local ensureBear = uv(showBear, "EnsureAnglerBearFrame")
	local savedBearFrame = uv(ensureBear, "bearFrame")
	local savedGlobalBear = ForeverPlusAnglerBear
	local savedCreate, savedPlay, savedStop, savedAfter =
		CreateFrame, PlaySoundFile, rawget(_G, "StopSound"), C_Timer.After
	local savedW, savedH = UIParent.w, UIParent.h
	local savedFishing, savedBearOpt, savedBearSoundOpt =
		helpers.db.fishing, helpers.db.fishingBear, helpers.db.fishingBearSound
	local bear, strata, mouseEnabled, ignoreAlpha, texturePath, anchorPoint
	local played, stopped, pendingAfter, nextHandle = {}, {}, {}, 100
	local CAST_IDS = { [3610663] = true, [3610665] = true }
	local SPLASH_IDS = { [569285] = true, [568970] = true, [569044] = true }

	UIParent.w, UIParent.h = 1920, 1080
	setuv(ensureBear, "bearFrame", nil)
	PlaySoundFile = function(id, channel)
		nextHandle = nextHandle + 1
		played[#played + 1] = { id = id, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	StopSound = function(handle)
		stopped[#stopped + 1] = handle
	end
	C_Timer.After = function(delay, fn)
		pendingAfter[#pendingAfter + 1] = { delay = delay, fn = fn }
	end
	CreateFrame = function(kind, name, parent)
		local frame = savedCreate(kind, name, parent)
		if name == "ForeverPlusAnglerBear" then
			bear = frame
			frame.SetFrameStrata = function(_, value) strata = value end
			frame.EnableMouse = function(_, value) mouseEnabled = value end
			frame.SetIgnoreParentAlpha = function(_, value) ignoreAlpha = value end
			frame.SetPoint = function(_, point, relative) anchorPoint = { point, relative } end
			frame.SetSize = function(self, width, height) self.w, self.h = width, height end
			local origCreateTexture = frame.CreateTexture
			frame.CreateTexture = function(self, ...)
				local tex = origCreateTexture(self, ...)
				tex.SetTexture = function(_, path) texturePath = path end
				return tex
			end
		end
		return frame
	end

	-- Settings expose fishingBear + fishingBearSound with new = true and a preview button; PortraitModes lists both.
	local bearOpt, soundOpt, previewOpt
	for _, opt in ipairs(helpers.options) do
		if opt.key == "fishingBear" then bearOpt = opt end
		if opt.key == "fishingBearSound" then soundOpt = opt end
		if opt.type == "button" and opt.name == ns.L.HELPERS_FISHING_BEAR_PREVIEW then previewOpt = opt end
	end
	assert(bearOpt and bearOpt.new == true and helpers.db.fishingBear == true, "fishingBear option defaults on and is marked NEW")
	assert(soundOpt and soundOpt.new == true and soundOpt.parent == "fishingBear" and helpers.db.fishingBearSound == true,
		"fishingBearSound option defaults on, depends on fishingBear and is marked NEW")
	assert(previewOpt and type(previewOpt.func) == "function", "Nat Pagle preview button is present in settings")
	assert(ns.L.SLASH_HELP:find("/fp nat", 1, true), "slash help documents /fp nat")
	local pmBearFound, pmSoundFound = false, false
	for _, feature in ipairs(ns.PortraitModes.FEATURES) do
		if feature.key == "angler" then
			for _, sub in ipairs(feature.subOptions or {}) do
				if sub.module == "Helpers" and sub.key == "fishingBear" then pmBearFound = true end
				if sub.module == "Helpers" and sub.key == "fishingBearSound" then pmSoundFound = true end
			end
		end
	end
	assert(pmBearFound and pmSoundFound, "PortraitModes angler sub-options include fishingBear and fishingBearSound")

	-- Staying on or turning off does not flash Nat Pagle or play sounds.
	ns.SetOption("Helpers", "fishing", true)
	assert(not bear and #played == 0, "re-enabling an already active fishing mode does not trigger Nat Pagle")
	ns.SetOption("Helpers", "fishing", false)
	assert(not bear and #played == 0, "disabling fishing mode does not trigger Nat Pagle")

	-- Turning off -> on triggers Nat Pagle overlay, immediate cast sound and delayed splash.
	ns.SetOption("Helpers", "fishing", true)
	assert(bear and bear:IsShown(), "off -> on fishing transition shows Nat Pagle")
	assert(strata == "FULLSCREEN_DIALOG" and mouseEnabled == false and ignoreAlpha == true,
		"Nat Pagle uses non-interactive fullscreen overlay ignoring parent alpha")
	assert(anchorPoint and anchorPoint[1] == "CENTER" and anchorPoint[2] == UIParent, "Nat Pagle is centered on UIParent")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\AnglerNatPagle.tga]], "Nat Pagle loads AnglerNatPagle.tga")
	assert(#played == 1 and CAST_IDS[played[1].id] and played[1].channel == "SFX",
		"activation plays a verified fishing cast sound immediately on SFX")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.35) < 0.001,
		"bobber splash is scheduled 0.35 s after cast via ns.After")
	local firstCastID, firstCastHandle = played[1].id, played[1].handle
	pendingAfter[1].fn()
	assert(#played == 2 and SPLASH_IDS[played[2].id] and played[2].channel == "SFX",
		"delayed timer plays a verified bobber splash sound on SFX")
	local firstSplashID, firstSplashHandle = played[2].id, played[2].handle

	local update = bear:GetScript("OnUpdate")
	assert(type(update) == "function", "Nat Pagle starts an OnUpdate handler while active")
	update(bear, 0.40)
	local holdSize, holdAlpha = bear:GetWidth(), bear:GetAlpha()
	assert(holdSize > 900 and math.abs(holdAlpha - 0.50) < 0.01, "during hold Nat Pagle fills screen height at half transparency")
	update(bear, 0.70)
	local midSize, midAlpha = bear:GetWidth(), bear:GetAlpha()
	assert(midSize < holdSize and midAlpha < holdAlpha, "during shrink Nat Pagle starts shrinking and fading")
	update(bear, 0.40)
	assert(bear:GetWidth() < holdSize * 0.35 and bear:GetWidth() < midSize and bear:GetAlpha() < midAlpha,
		"accelerated in-easing rapidly shrinks Nat Pagle toward the screen center")
	update(bear, 0.15)
	assert(not bear:IsShown() and bear:GetAlpha() == 0 and bear:GetScript("OnUpdate") == nil,
		"after completion Nat Pagle hides cleanly and stops OnUpdate (0 CPU idle)")
	assert(#stopped == 0,
		"normal completion lets cast and bobber splash sounds finish decaying naturally")

	-- PortraitModes ToggleMode off -> on triggers Nat Pagle and alternates cast/splash sounds.
	played, stopped, pendingAfter = {}, {}, {}
	ns.PortraitModes.ToggleMode("angler")
	assert(not helpers.db.fishing and not bear:IsShown(), "PortraitModes turns angler mode off")
	assert(stopped[1] == firstCastHandle and stopped[2] == firstSplashHandle,
		"turning fishing off stops any still-active cast and splash handles")
	stopped = {}
	ns.PortraitModes.ToggleMode("angler")
	assert(helpers.db.fishing and bear:IsShown() and bear:GetScript("OnUpdate") ~= nil,
		"PortraitModes off -> on transition plays Nat Pagle")
	assert(#played == 1 and CAST_IDS[played[1].id] and played[1].id ~= firstCastID,
		"consecutive casts alternate between the two verified cast sounds")
	local pendingSplash = pendingAfter[1]
	-- Turning fishingBear off stops an active animation, stops sound handles and cancels the pending splash.
	local activeCastHandle = played[1].handle
	ns.SetOption("Helpers", "fishingBear", false)
	assert(not bear:IsShown() and bear:GetScript("OnUpdate") == nil, "disabling fishingBear stops an active flash")
	assert(stopped[1] == activeCastHandle, "disabling fishingBear stops active sound handle")
	pendingSplash.fn()
	assert(#played == 1, "cancelled splash timer does not fire after StopAnglerBear")
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("Helpers", "fishing", true)
	assert(not bear:IsShown() and #played == 1, "fishingBear = false suppresses the flash and sound on activation")

	-- Re-triggering preview stops previous handles and cancels stale splash timer; new timer plays alternate splash.
	played, stopped, pendingAfter = {}, {}, {}
	SlashCmdList.FOREVERPLUS("nat")
	assert(bear:IsShown() and bear:GetScript("OnUpdate") ~= nil and #played == 1 and #pendingAfter == 1,
		"/fp nat previews Nat Pagle with cast sound and scheduled splash")
	local staleCastHandle, staleSplash = played[1].handle, pendingAfter[1]
	SlashCmdList.FOREVERPLUS("pagle")
	assert(stopped[1] == staleCastHandle and #played == 2 and #pendingAfter == 2,
		"/fp pagle stops previous sound handle and restarts preview")
	staleSplash.fn()
	assert(#played == 2, "stale splash timer from previous start is ignored")
	pendingAfter[2].fn()
	assert(#played == 3 and SPLASH_IDS[played[3].id] and played[3].id ~= firstSplashID,
		"active splash timer plays the next bobber splash variant")
	-- Disabling fishingBearSound mid-flash stops active sounds without hiding the portrait.
	local countBeforeMute = #stopped
	ns.SetOption("Helpers", "fishingBearSound", false)
	assert(bear:IsShown() and #stopped > countBeforeMute, "disabling fishingBearSound stops active sounds immediately")
	bear:GetScript("OnUpdate")(bear, 2.0)

	-- With fishingBearSound = false, activation and all preview commands/aliases stay completely silent.
	played, stopped, pendingAfter = {}, {}, {}
	ns.SetOption("Helpers", "fishingBear", true)
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("Helpers", "fishing", true)
	assert(bear:IsShown() and #played == 0 and #pendingAfter == 0, "fishingBearSound = false stays silent on activation")
	bear:GetScript("OnUpdate")(bear, 2.0)
	for _, cmd in ipairs({ "nat", "pagle", "angler", "bär", "anglerbär", "bear", "anglerbear" }) do
		SlashCmdList.FOREVERPLUS(cmd)
		assert(bear:IsShown() and bear:GetScript("OnUpdate") ~= nil, "/fp " .. cmd .. " previews Nat Pagle")
		bear:GetScript("OnUpdate")(bear, 2.0)
		assert(not bear:IsShown() and bear:GetScript("OnUpdate") == nil, "preview finishes and stops OnUpdate")
	end
	previewOpt.func()
	assert(bear:IsShown() and #played == 0 and #pendingAfter == 0, "settings preview stays silent when fishingBearSound is off")
	bear:GetScript("OnUpdate")(bear, 2.0)

	ns.SetOption("Helpers", "fishingBearSound", savedBearSoundOpt)
	ns.SetOption("Helpers", "fishingBear", savedBearOpt)
	ns.SetOption("Helpers", "fishing", savedFishing)
	UIParent.w, UIParent.h = savedW, savedH
	CreateFrame, PlaySoundFile, StopSound, C_Timer.After = savedCreate, savedPlay, savedStop, savedAfter
	ForeverPlusAnglerBear = savedGlobalBear
	setuv(ensureBear, "bearFrame", savedBearFrame)
end)()
print("ttd OK")
-- Junk marks tell random suffixes apart
local isJunk = uv(uv(items.LOOT_READY or items.OnLogin, "UpdateAllBags") or function() end, "x")
local junkKey = nil
local itemsMod = ns:GetModule("Items")
itemsMod.db.junk, itemsMod.db.keep = {}, {}
local IsJunkItemFn
for i = 1, 200 do
	local n, v = debug.getupvalue(itemsMod.ShowJunkMenu, i)
	if not n then break end
end
-- find IsJunkItem via UpdateButton upvalue chain
local updateAll = uv(itemsMod.ShowJunkMenu, "UpdateAllBags")
local updateFrame = uv(updateAll, "UpdateContainerFrame")
local updateButton = uv(updateFrame, "UpdateButton")
IsJunkItemFn = uv(updateButton, "IsJunkItem")
local jkey = uv(uv(IsJunkItemFn, "IsMarked"), "JunkKey")
local monkey = { itemID = 100, quality = 2, hyperlink = "|cff1eff00|Hitem:100::::::612:::::|h[Hose des Affen]|h|r" }
local frost = { itemID = 100, quality = 2, hyperlink = "|cff1eff00|Hitem:100::::::1401:::::|h[Hose des Frostschutzes]|h|r" }
local k = jkey(monkey)
itemsMod.db.junk[k] = monkey.hyperlink
print("  keys", k, jkey(frost), IsJunkItemFn(monkey), IsJunkItemFn(frost), strsplit)
assert(IsJunkItemFn(monkey) and not IsJunkItemFn(frost), "suffix items told apart")
print("junk suffix OK", k)
-- Unit price behind the sell price
local tt = { lines = { "Hose", "Verkaufspreis: 40" }, GetName = function() return "TT" end, NumLines = function(self) return #self.lines end }
for i, text in ipairs(tt.lines) do _G["TTTextLeft" .. i] = { GetText = function() return tt.lines[i] end, SetText = function(_, t) tt.lines[i] = t end } end
local append = uv(uv(ns:GetModule("Tooltip").OnInitialize, "OnItemTooltip"), "AddUnitPrice")
local appendLine = uv(append, "AppendToSellLine")
assert(appendLine(tt, "(20 / Stück)") and tt.lines[2] == "Verkaufspreis: 40 (20 / Stück)", "unit price appended")
print("unit price OK")
-- Hover name with health mask (smoke test)
GetMouseFoci = function() return {} end
GetCursorPosition = function() return 180, 100 end
UnitExists = function() return true end
UnitName = function() return "Helaku" end
UnitLevel = function() return 13 end
UnitHealthPercent = function() return 0.3 end
GameTooltip_UnitColor = function() return 0.2, 0.6, 1 end
local show = uv(ns:GetModule("Tooltip").OnLogin, "ShowHoverName")
if show then show() end
do
	local Tip = ns:GetModule("Tooltip")
	local objectCall = uv(Tip.OnInitialize, "OnObjectTooltip")
	assert(objectCall, "object tooltip handler")
	UnitExists = function() return false end
	GameTooltipTextLeft1 = { GetText = function() return "Briefkasten" end, GetTextColor = function() return 1, 0.82, 0 end }
	GameTooltip.IsForbidden = function() return false end
	objectCall(GameTooltip)
	do
		-- An opened text keeps its grey name over the cursor, also without the read status option.
		local readable, hoverName = ns:GetModule("Readable"), uv(show, "GetHover")().Name
		local oldTitles, oldStatus, oldGray, oldColor = readable.cdb.openedTitles, readable.db.readStatus, GRAY_FONT_COLOR,
			hoverName.SetTextColor
		local red
		hoverName.SetTextColor = function(_, r) red = r end
		GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
		readable.cdb.openedTitles, readable.db.readStatus = {}, false
		objectCall(GameTooltip)
		assert(red == 1, "unopened object keeps its colour over the cursor")
		readable.cdb.openedTitles.Briefkasten = true
		objectCall(GameTooltip)
		assert(red == 0.5, "opened text is grey over the cursor")
		readable.cdb.openedTitles, readable.db.readStatus, GRAY_FONT_COLOR, hoverName.SetTextColor = oldTitles, oldStatus,
			oldGray, oldColor
	end

	-- A readable name can still have secret font measurements after hovering a unit.
	local frame = uv(show, "GetHover")()
	local savedSecret, savedSetSize = issecretvalue, frame.SetSize
	local savedWidth, savedHeight, savedLevelWidth = frame.Name.GetStringWidth, frame.Name.GetStringHeight, frame.Level.GetStringWidth
	local savedGreyWidth, savedGreyHeight = frame.Grey.GetStringWidth, frame.Grey.GetStringHeight
	local secret = 9999
	issecretvalue = function(value) return value == secret end
	frame.SetSize = function(self, width, height) self.w, self.h = width, height end
	frame.Name.GetStringWidth = function() return secret end
	frame.Name.GetStringHeight = function() return secret end
	objectCall(GameTooltip)
	assert(frame:IsShown() and not frame.masked and frame.w == 82 and frame.h == 14, "object uses unclipped text measurements")

	UnitExists = function() return true end
	show()
	assert(frame.masked and frame.w == 166 and frame.h == 14, "health mask works with secret dimensions on the clipped copy")
	frame.Grey.GetStringWidth = function() return secret end
	show()
	assert(frame:IsShown() and not frame.masked and not frame.Level:IsShown() and frame.w == 1 and frame.h == 13,
		"secret name width falls back to an unclipped label")
	frame.Grey.GetStringWidth = savedGreyWidth
	frame.Grey.GetStringHeight = function() return secret end
	show()
	assert(not frame.masked and not frame.Level:IsShown() and frame.w == 1 and frame.h == 13,
		"secret name height falls back to an unclipped label")
	frame.Grey.GetStringHeight = savedGreyHeight
	frame.Level.GetStringWidth = function() return secret end
	show()
	assert(frame.masked and not frame.Level:IsShown() and frame.w == 82 and frame.h == 14,
		"secret level width is excluded from layout")
	frame.Level.GetStringWidth = savedLevelWidth
	show()
	assert(frame.masked and frame.Level:IsShown() and frame.w == 166 and frame.h == 14,
		"regular layout returns with readable measurements")
	frame.Name.GetStringWidth, frame.Name.GetStringHeight = savedWidth, savedHeight
	issecretvalue, frame.SetSize = savedSecret, savedSetSize

	-- the name stays while the tooltip comes and shows, and goes when the game starts fading it out
	local stays, peak = Tip.ObjectNameStays(false, 0, nil, 0.05)
	assert(stays, "tooltip not shown yet right after its data: name stays")
	stays, peak = Tip.ObjectNameStays(true, 1, peak, 0.5)
	assert(stays and peak == 1, "full tooltip: name stays")
	stays = Tip.ObjectNameStays(true, 0.7, peak, 0.8)
	assert(not stays, "fading tooltip: name goes")
	stays = Tip.ObjectNameStays(false, 1, 1, 0.5)
	assert(not stays, "tooltip gone: name goes")
	stays, peak = Tip.ObjectNameStays(true, 0.3, 0.3, 0.3)
	assert(stays and peak == 0.3, "taken over while fading: stays")
	stays, peak = Tip.ObjectNameStays(true, 1, peak, 0.4)
	assert(stays and peak == 1, "comes back up: stays")
end
print("hover OK")
;(function()
	local tooltip = ns:GetModule("Tooltip")
	local frame = uv(show, "GetHover")()
	local savedUnit, savedWorld, savedFoci, savedCursor = UnitExists, WorldFrame, GetMouseFoci, C_TooltipInfo.GetWorldCursor
	local savedParent, savedScale = frame.SetParent, frame.SetScale
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local unit, data, parent, scale = true
	WorldFrame = { GetEffectiveScale = function() return 0.5 end }
	GetMouseFoci = function() return { WorldFrame } end
	UnitExists = function(token) return token == "mouseover" and unit end
	C_TooltipInfo.GetWorldCursor = function() return data end
	frame.SetParent = function(_, value) parent = value end
	frame.SetScale = function(_, value) scale = value end

	tooltip.SetWanderlustHover(true)
	assert(frame:IsShown() and not frame.object and parent == WorldFrame and scale == 2,
		"Wanderlust moves the existing unit label outside the hidden interface and preserves its scale")
	unit = false
	data = { type = Enum.TooltipDataType.Object, lines = { { leftText = "Copper Vein" } } }
	local function CursorChanged() eventFrame.scripts.OnEvent(eventFrame, "WORLD_CURSOR_TOOLTIP_UPDATE") end
	CursorChanged()
	assert(frame:IsShown() and frame.object, "Wanderlust shows the object from world cursor data")
	GameTooltip.scripts.OnTooltipCleared(GameTooltip)
	frame.scripts.OnUpdate(frame, 0.1)
	assert(frame:IsShown(), "GameTooltip clearing and fading do not hide the independent object label")
	tooltip.db.hoverObjects = false
	tooltip:OnOptionChanged("hoverObjects")
	assert(not frame:IsShown(), "the normal object option is respected during Wanderlust")
	tooltip.db.hoverObjects = true
	tooltip:OnOptionChanged("hoverObjects")
	assert(frame:IsShown(), "reenabling object text refreshes the current cursor")
	data = nil
	CursorChanged()
	assert(not frame:IsShown(), "leaving the object hides the label")

	unit = true
	tooltip.db.hoverName = false
	tooltip:OnOptionChanged("hoverName")
	show()
	assert(not frame:IsShown(), "the normal mouseover option also controls the Wanderlust unit label")
	tooltip.db.hoverName = true
	tooltip:OnOptionChanged("hoverName")
	tooltip.SetWanderlustHover(false)
	assert(frame:IsShown() and parent == UIParent and scale == 1, "restoring the interface returns the unit label to its normal parent")
	assert(not uv(ns.RegisterEvent, "listeners").WORLD_CURSOR_TOOLTIP_UPDATE,
		"restoring the interface stops reading world cursor data for Wanderlust")
	UnitExists, WorldFrame, GetMouseFoci, C_TooltipInfo.GetWorldCursor = savedUnit, savedWorld, savedFoci, savedCursor
	frame.SetParent, frame.SetScale = savedParent, savedScale
end)()
-- Rank up: rank 2 replaced by rank 3, rank 1 kept
local qolMod = ns:GetModule("QoL")
local rankUp = uv(qolMod.UpdateRankUp, "RankUp")
local bars = { [1] = 101, [2] = 102 }
local names = { [101] = "Welle", [102] = "Welle", [103] = "Welle" }
local ranks = { [101] = "Rang 1", [102] = "Rang 2", [103] = "Rang 3" }
C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellSubtext = function(id) return ranks[id] end
HasAction = function(slot) return bars[slot] ~= nil end
GetActionInfo = function(slot) return "spell", bars[slot] end
local cursor
C_Spell.PickupSpell = function(id) cursor = id end
ClearCursor = function() cursor = nil end
PlaceAction = function(slot) bars[slot] = cursor end
rankUp(103)
assert(bars[1] == 101 and bars[2] == 103, "rank up")
print("rank up OK")
-- Chat: whole word keywords, highlight, short channels
local chatMod = ns:GetModule("Chat")
chatMod.cdb.keywords = "it, Müller"
local parse = uv(chatMod.UpdateKeywordAlert, "ParseKeywords")
parse()
local contains = uv(uv(chatMod.UpdateKeywordAlert, "HighlightFilter"), "ContainsKeyword")
assert(not contains("bitte invite mich"), "invite no match")
assert(contains("IT geht"), "it match")
assert(contains("wer ist müller?") == false or true)
assert(not contains("|cff1eff00|Hitem:1|h[it]|h|r"), "link ignored")
local highlight = uv(chatMod.UpdateKeywordAlert, "HighlightFilter")
chatMod.db.keywordColor = "ORANGE"
local _, text = highlight(nil, "CHAT_MSG_SAY", "it is it, invite it", "Other")
print("  hl", text)
assert(text == "|cffff8000it|r is |cffff8000it|r, invite |cffff8000it|r", "highlight")
local short = uv(uv(chatMod.UpdateChannelNames, "ChannelFilter"), "ShortName")
assert(short("Allgemein") == "A" and short("Handel") == "H" and short("LokaleVerteidigung") == "LV" and short("Handel lokal") == "HL", "short names")
local cf = uv(chatMod.UpdateChannelNames, "ChannelFilter")
local r = { cf(nil, "CHAT_MSG_CHANNEL", "hi", "X", "", "2. Handel - Stadt", "", "", 2, 2, "Handel") }
print("  chan", r[5], #r[5])
assert(r[5]:sub(1, 4) == "2. H" and #r[5] >= #"2. Handel - Stadt" and r[10] == "Handel", "channel filter")
print("chat OK")
-- Loot summary
LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
LOOT_ITEM_CREATED_SELF = "Ihr stellt her: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "Ihr stellt her: %sx%d."
YOU_LOOT_MONEY = "Ihr plündert %s"
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silber", "%d Kupfer"
local lootMod = ns:GetModule("Loot")
-- rebuild patterns by reloading the file with the globals set
local chunk = assert(loadfile(root .. "/Modules/Loot.lua"))
ns.modules.Loot = nil
chunk("ForeverPlus", ns)
lootMod = ns.modules.Loot
lootMod.db = { summary = true, delay = 20, inlineQuality = "UNCOMMON" }
local onLoot = lootMod.CHAT_MSG_LOOT
local parseItem = uv(onLoot, "ParseItem")
local link = "|cff1eff00|Hitem:100::::|h[Hose]|h|r"
local l1, c1 = parseItem("Ihr erhaltet Beute: " .. link .. "x3.")
assert(l1 == link and c1 == 3, "multiple parse")
local l2, c2 = parseItem("Ihr erhaltet Beute: " .. link .. ".")
assert(l2 == link and c2 == 1, "single parse")
assert(not parseItem("Helaku erhält Beute: " .. link .. "."), "other player")
do
	local l3, c3, cr3 = parseItem("Ihr stellt her: " .. link .. "x4.")
	assert(l3 == link and c3 == 4 and cr3 == true, "created multiple")
	local l4, c4, cr4 = parseItem("Ihr stellt her: " .. link .. ".")
	assert(l4 == link and c4 == 1 and cr4 == true, "created single")
end
assert(select(3, parseItem("Ihr erhaltet Beute: " .. link .. ".")) == false, "looted not created")
local parseMoney = uv(lootMod.CHAT_MSG_MONEY, "ParseMoney")
assert(parseMoney("Ihr plündert 1 Gold, 2 Silber, 3 Kupfer") == 10203, "money parse")
print("loot OK")
-- Loot flow: filter hides, event collects, flush prints one line per group
ChatTypeInfo = { LOOT = { r = 0, g = 1, b = 0, id = 1 }, MONEY = { r = 1, g = 1, b = 0, id = 2 } }
GetMoneyString = function(v) return tostring(v) .. "c" end
C_Item.GetItemQualityByID = function() return 2 end
local out = {}
local fakeFrame = { AddMessage = function(_, t) out[#out + 1] = t end }
local lootFilter = uv(lootMod.Update, "LootFilter")
local moneyFilter = uv(lootMod.Update, "MoneyFilter")
local msg = "Ihr erhaltet Beute: " .. link .. "x2."
assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", msg) == true, "filter hides")
assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", "Helaku erhält Beute: x.") == false, "filter keeps others")
lootMod:CHAT_MSG_LOOT("CHAT_MSG_LOOT", msg)
lootMod:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link .. ".")
assert(moneyFilter(fakeFrame, "CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer") == true)
-- Chat filters leave protected text alone (patterns and comparisons on it are errors in the game)
;(function()
	local savedSecret = issecretvalue
	local secret = {}
	issecretvalue = function(value) return secret[value] == true end
	secret[msg] = true
	assert(lootFilter(fakeFrame, "CHAT_MSG_LOOT", msg) == false, "loot filter: protected text stays")
	secret["Ihr plündert 5 Kupfer"] = true
	assert(moneyFilter(fakeFrame, "CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer") == false, "money filter: protected text stays")
	secret["it is it"] = true
	assert(select("#", highlight(nil, "CHAT_MSG_SAY", "it is it", "Other")) == 1, "highlight: protected text unchanged")
	secret["it is it"] = nil
	secret["Geheim"] = true
	assert(select("#", highlight(nil, "CHAT_MSG_SAY", "it is it", "Geheim")) == 1, "highlight: protected sender")
	secret["Handel"] = true
	assert(select("#", cf(nil, "CHAT_MSG_CHANNEL", "hi", "X", "", "2. Handel - Stadt", "", "", 2, 2, "Handel")) == 1,
		"channel filter: protected name unchanged")
	issecretvalue = savedSecret
	print("chat filters with protected text OK")
end)()
lootMod:CHAT_MSG_MONEY("CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer")
uv(lootMod.Update, "Flush")()
for _, t in ipairs(out) do print("  ", t) end
assert(#out == 2 and out[1]:find(" 3 ", 1, true) and out[1]:find(link .. "x3", 1, true) and out[2]:find("5c", 1, true), "summary lines")
print("loot flow OK")

-- Upgrade: Forever talent trees, shaman hammer from the screenshot
local scoreFn = upvalue(upvalue(compare, "EquippedScore"), "Score")
local getW = upvalue(scoreFn, "GetWeights")
local function resetWeights()
	local scoreFn = upvalue(upvalue(compare, "EquippedScore"), "Score")
	for k in pairs(upvalue(scoreFn, "scoreCache")) do upvalue(scoreFn, "scoreCache")[k] = nil end
	for k in pairs(upvalue(upvalue(compare, "EquippedScore"), "equippedCache")) do upvalue(upvalue(compare, "EquippedScore"), "equippedCache")[k] = nil end
	for i = 1, 200 do local n = debug.getupvalue(getW, i) if not n then break end if n == "weights" then debug.setupvalue(getW, i, nil) end if n == "playerClass" then debug.setupvalue(getW, i, "SHAMAN") end end end
local trees = { { groupID = 11, orderIndex = 0, displayName = "Elementar" }, { groupID = 12, orderIndex = 1, displayName = "Verstärkung" }, { groupID = 13, orderIndex = 2, displayName = "Wiederherstellung" } }
local spent = { [11] = 0, [12] = 0, [13] = 0 }
C_ClassTalents = { GetActiveConfigID = function() return 5 end }
C_Traits = rawget(_G, "C_Traits") or {}
C_Traits.GetConfigInfo = function() return { treeIDs = { 77 } } end
C_Traits.GetGroupDisplayInfoByTreeID = function() return { trees[3], trees[1], trees[2] } end
C_Traits.GetGroupCurrencyInfo = function(_, ids) local r = {} for _, id in ipairs(ids) do r[#r + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = spent[id] } } } end return r end
CopyTable = CopyTable or function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
ITEMS["talk"] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6.1, ITEM_MOD_STAMINA_SHORT = 1 } }
ITEMS["hammer"] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 7.3, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1 } }
CanDualWield = function() return false end
GetInventoryItemLink = function(_, slot) return slot == 16 and "talk" or nil end
UnitLevel = function() return 10 end
resetWeights()
C_Item.GetItemInfoInstant = function(link) local d = ITEMS[link] return 1, nil, nil, d[1], nil, d[2], d[3] end
C_Item.GetItemStats = function(link) return ITEMS[link][4] end
C_Item.IsItemDataCachedByID = function() return true end
C_Item.DoesItemExist = function() return true end
local s1, e1 = compare("hammer")
print("  no points", s1, e1, select(2, getW()))
assert(s1 > e1 and select(3, getW()) == 2, "hammer better without points, enhancement weights by default")
spent[11] = 1
resetWeights()
local s2, e2 = compare("hammer")
print("  elemental lvl10", s2, e2, select(2, getW()))
assert(select(2, getW()) == "Elementar" and select(3, getW()) == 1 and s2 > e2, "hammer better for levelling elemental")
UnitLevel = function() return 60 end
resetWeights()
local s3, e3 = compare("hammer")
print("  elemental lvl60", s3, e3)
assert(s3 < e3, "weapon dps irrelevant for elemental at 60")
-- DPS from the tooltip when stats lack it
DPS_TEMPLATE = "(%.1f Schaden pro Sekunde)"
local chunk = assert(loadfile(root .. "/Modules/Items.lua"))
local pat = "^" .. DPS_TEMPLATE:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%%%%.1f", "([%%d%%.,]+)") .. "$"
print("  pattern", pat, ("(7,3 Schaden pro Sekunde)"):match(pat))
assert(("(7,3 Schaden pro Sekunde)"):match(pat) == "7,3")
print("upgrade trees OK")
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedStats, savedInfo = C_Item.GetItemStats, C_Item.GetItemInfoInstant
	local savedRating = GetCombatRatingBonusForCombatRatingValue
	local serial = 0
	local function CheckScore(stats, expected)
		C_Item.GetItemStats = function() return stats end
		serial = serial + 1
		local score = scoreFn("rating-test:" .. serial)
		assert(math.abs(score - expected) < 0.0001, ("expected %.2f, got %.2f"):format(expected, score))
	end
	C_Item.GetItemInfoInstant = function() return nil, nil, nil, nil, nil, Enum.ItemClass.Armor end
	GetCombatRatingBonusForCombatRatingValue = nil
	local shared = { ITEM_MOD_HIT_RATING_SHORT = 4, ITEM_MOD_CRIT_RATING_SHORT = 14 }
	setuv(getW, "weights", { HIT = 15, SHIT = 14, CRIT = 10, SCRIT = 12 })
	CheckScore(shared, 18)
	setuv(getW, "weights", { SHIT = 14, SCRIT = 12 })
	CheckScore(shared, 17.6)
	CheckScore({ ITEM_MOD_HIT_RANGED_RATING_SHORT = 4 }, 0)
	setuv(getW, "weights", { SP = 0.85, HEAL = 1, SHASTE = 12 })
	CheckScore({ ITEM_MOD_HASTE_RATING_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 20, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 }, 34.5)
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").MAGE[2])
	CheckScore({ ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 10, ITEM_MOD_FROST_DAMAGE_DONE_SHORT = 20 }, 9)

	setuv(getW, "weights", upvalue(getW, "WEIGHTS").PALADIN[2])
	CheckScore({
		ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 4, ITEM_MOD_BLOCK_VALUE_SHORT = 3,
		ITEM_MOD_BLOCK_RATING_SHORT = 5, ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_PARRY_RATING_SHORT = 15,
		ITEM_MOD_EXPERTISE_RATING_SHORT = 10, ITEM_MOD_HASTE_RATING_SHORT = 10,
	}, 53.1)
	local index, value
	GetCombatRatingBonusForCombatRatingValue = function(ratingIndex, raw)
		index, value = ratingIndex, raw
		return 0.2
	end
	setuv(getW, "weights", { HIT = 15 })
	CheckScore({ ITEM_MOD_HIT_RATING_SHORT = 4 }, 3)
	assert(index == 6 and value == 4, "prefer the client's conversion for the actual rating amount")
	setuv(getW, "weights", savedProfile)
	C_Item.GetItemStats, C_Item.GetItemInfoInstant = savedStats, savedInfo
	GetCombatRatingBonusForCombatRatingValue = savedRating
	print("forever item rating units OK")
end)()
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip = GetInventoryItemLink, C_TooltipInfo.GetHyperlink
	local savedEquippable, savedEnabled = C_Item.IsEquippableItem, itemsMod.db.upgradeScore
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local flat = de and "Anlegen: +3 Angriffskraft" or "Equip: +3 Attack Power"
	local against = de and "Anlegen: +4 Angriffskraft gegen Humanoide." or "Equip: +4 Attack Power against Humanoids."
	local baseStats = { RESISTANCE0_NAME = 15, ITEM_MOD_STAMINA_SHORT = 2 }
	local cloak, defender, situational = "catacombCloak", "shadowDefenderCloak", "situationalCloak"
	ITEMS[cloak] = { "INVTYPE_CLOAK", 4, 1, baseStats }
	ITEMS[defender] = { "INVTYPE_CLOAK", 4, 1, { RESISTANCE0_NAME = 17, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE5_NAME = 2 } }
	ITEMS[situational] = { "INVTYPE_CLOAK", 4, 1, { RESISTANCE0_NAME = 14, ITEM_MOD_STAMINA_SHORT = 2 } }
	local equipped = cloak
	GetInventoryItemLink = function(_, slot) return slot == 15 and equipped or nil end
	C_Item.IsEquippableItem = function() return true end
	C_TooltipInfo.GetHyperlink = function(link)
		local effects = {}
		if link == cloak then
			effects = {
				{ leftText = flat },
				{ type = 45, leftText = "|cff00ff00" .. against .. "|r" },
				{ leftText = de and "Benutzen: +99 Angriffskraft" or "Use: +99 Attack Power" },
			}
		elseif link == situational then
			effects = { { type = 45, leftText = against:match(": (.+)") } }
		end
		return { lines = effects }
	end
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").PALADIN[2])
	clear()
	local score, worn, humanoid, wornHumanoid = compare(defender)
	assert(math.abs(score - 4.7) < 0.001 and math.abs(worn - 5.55) < 0.001, "flat attack power beats two additional armor")
	assert(humanoid == score and math.abs(wornHumanoid - 6.95) < 0.001, "equipped cloak gains only four more AP against Humanoids")
	assert(BagComparisonState(0, 1, defender) == "worse", "the Defender Cloak is worse than the Catacomb Cloak")

	local lines = {}
	local tip = { AddLine = function(_, line) lines[#lines + 1] = line end }
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine(tip, defender)
	assert(#lines == 2 and lines[2] == ns.L.ITEMS_SCORE_HUMANOID_LINE:format(humanoid, wornHumanoid),
		"the tooltip shows both items' rating against Humanoids even if only the equipped one has the bonus")

	clear()
	baseStats.ITEM_MOD_ATTACK_POWER_SHORT = 3
	local apiScore, apiBonus = scoreFn(cloak)
	assert(apiScore == worn and math.abs(apiBonus - 1.4) < 0.001, "do not double count flat AP reported by the client")
	equipped = defender
	local conditional, normal, againstHumanoid, wornAgainst = compare(situational)
	assert(conditional < normal and againstHumanoid > wornAgainst, "a situational cloak can win the Humanoid comparison")
	assert(BagComparisonState(0, 1, situational) == "worse", "the generic arrow uses the base rating")

	-- Comparison tooltips: the arrow goes to the better of the hovered and the worn item.
	clear()
	equipped = cloak
	local winner, which = ns.CompareWinner(defender, { cloak })
	assert(winner == "worn" and which == 1, "the better worn cloak gets the arrow")
	assert(ns.RewardComparisonState(defender) == "worse", "a worse quest reward uses the same rating")
	equipped = defender
	clear()
	winner, which = ns.CompareWinner(cloak, { defender })
	assert(winner == "hovered" and which == true, "the better hovered cloak gets the arrow")
	equipped = cloak
	clear()
	assert(ns.CompareWinner(cloak, { cloak }) == nil, "equal items: no arrow")
	itemsMod.db.upgradeArrow = false
	assert(ns.CompareWinner(cloak, { defender }) == nil, "option off: no arrow")
	-- the rating for sorted lists: gain over the worn item, independent of the arrow option
	equipped = defender
	clear()
	local gain, block = ns.ItemLinkRating(cloak)
	assert(gain > 0.01 and block == "ok", "the better cloak gains and can be worn")
	equipped = cloak
	clear()
	gain, block = ns.ItemLinkRating(defender)
	assert(gain < 0 and block == nil, "the worse cloak loses, no tooltip read")
	itemsMod.db.upgradeArrow = true

	clear()
	ITEMS[cloak], ITEMS[defender], ITEMS[situational] = nil, nil, nil
	itemsMod.db.upgradeScore = savedEnabled
	C_Item.IsEquippableItem = savedEquippable
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink = savedEquipped, savedTooltip
	setuv(getW, "weights", savedProfile)
	print("protection paladin attack power and humanoid cloak comparison OK")
end)()
-- "Chance on hit" damage counts at 1 proc per minute (screenshot: axe against Ironforge great hammer).
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip = GetInventoryItemLink, C_TooltipInfo.GetHyperlink
	local savedLocation, savedExists, savedEnabled = ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, itemsMod.db.upgradeScore
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local procText = de and "Trefferchance: Fügt einem Ziel 42 Feuerschaden zu." or "Chance on hit: Blasts a target for 42 Fire damage."
	local R = ns.ProcRateDefault
	assert(R == 1.95 and ns.ProcRates[17705][1] == 1, "bundled rates: default is the Forever median, Thrash Blade measured")
	assert(itemsMod.ProcDamage(de and "Schleudert einen Feuerball, der 155 bis 197 Feuerschaden verursacht."
		or "Hurls a fiery ball that causes 155 to 197 Fire damage.") == 176, "a damage range counts with its average")
	assert(itemsMod.ProcDamage(de and "Verursacht 30 Schaden." or "Deals 30 damage.") == 30, "plain damage without a school")
	assert(itemsMod.ProcDamage(de and "Betäubt das Ziel 3 Sek. lang." or "Stuns target for 3 sec.") == 0, "no damage, no value")
	assert(itemsMod.ProcDamage("Schleudert eine glühende Kugel hinaus, die 155 bis 197 Punkt(e) Feuerschaden sowie zusätzlich 6 Sek. lang 24 Punkt(e) Schaden verursacht.") == 176
		or not de, "German damage with Punkt(e)")
	local axe, hammer = "excavationAxe", "ironforgeHammer"
	ITEMS[axe] = { "INVTYPE_2HWEAPON", 2, 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.5, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 8 } }
	ITEMS[hammer] = { "INVTYPE_2HWEAPON", 2, 5, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.97 } }
	GetInventoryItemLink = function(_, slot) return slot == 16 and axe or nil end
	ItemLocation.CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end
	C_Item.DoesItemExist = function(location) return location.slot == 16 end
	C_TooltipInfo.GetHyperlink = function(link)
		return { lines = link == hammer and { { type = 46, leftText = "|cff00ff00" .. procText .. "|r" } } or {} }
	end
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").SHAMAN[2])
	clear()
	local score, worn = compare(hammer)
	assert(math.abs(worn - 262.8) < 0.001, "equipped axe: 17.5 DPS, 7 strength, 8 stamina")
	assert(math.abs(score - (15.97 * 14 + R * 42 / 60 * 14)) < 0.001, "the hammer's proc counts at the default rate")
	assert(BagComparisonState(0, 1, hammer) == "worse", "the proc does not make up for the axe's stats")
	local lines = {}
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(#lines == 2 and lines[2] == ns.L.ITEMS_SCORE_PROC_LINE:format(R * 42 / 60 * 14, R, ns.L.ITEMS_PROC_RATE_0),
		"the tooltip names the counted proc rating and the default rate")
	-- A weapon with a measured rate uses it (the harness gives every item ID 1).
	ns.ProcRates[1] = { 0.95, 1 }
	clear()
	assert(math.abs(scoreFn(hammer) - (15.97 * 14 + 0.95 * 42 / 60 * 14)) < 0.001, "measured rate")
	lines = {}
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(lines[2] == ns.L.ITEMS_SCORE_PROC_LINE:format(0.95 * 42 / 60 * 14, 0.95, ns.L.ITEMS_PROC_RATE_1), "the tooltip names a measured rate")
	ns.ProcRates[1] = nil
	setuv(getW, "weights", upvalue(getW, "WEIGHTS").MAGE[1])
	clear()
	assert(select(3, scoreFn(hammer)) == 0, "casters do not count melee procs")

	clear()
	ITEMS[axe], ITEMS[hammer] = nil, nil
	itemsMod.db.upgradeScore = savedEnabled
	ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist = savedLocation, savedExists
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink = savedEquipped, savedTooltip
	setuv(getW, "weights", savedProfile)
	print("chance on hit damage rating OK")
end)()
-- Weapon speed through known instant attacks, extra attacks, attack speed procs and Hand of Justice.
;(function()
	local savedProfile = upvalue(getW, "weights")
	local savedEquipped, savedTooltip, savedKnown = GetInventoryItemLink, C_TooltipInfo.GetHyperlink, IsPlayerSpell
	local savedLocation, savedExists, savedAP = ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, rawget(_G, "UnitAttackPower")
	local savedDual, savedSubclass = rawget(_G, "CanDualWield"), Enum.ItemWeaponSubclass
	local savedClass, savedTree = upvalue(getW, "playerClass"), upvalue(getW, "weightsTree")
	local clear = uv(uv(itemsMod.OnOptionChanged, "QueueWeighRefresh"), "ClearWeighCaches")
	local de = GetLocale() == "deDE"
	local function speedLine(speed) return { leftText = "1 - 2", rightText = (de and "Tempo " or "Speed ") .. speed } end
	local axe, hammer, thrash, ironfoe, demolisher, hand = "speedAxe", "speedHammer", "thrashBlade", "ironfoe", "demolisher", "handOfJustice"
	ITEMS[axe] = { "INVTYPE_2HWEAPON", 2, 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.5, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 8 } }
	ITEMS[hammer] = { "INVTYPE_2HWEAPON", 2, 5, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15.97 } }
	ITEMS[thrash] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[ironfoe] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[demolisher] = { "INVTYPE_WEAPON", 2, 4, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[hand] = { "INVTYPE_TRINKET", 4, 0, {} }
	local tips = {
		[axe] = { speedLine("2,40") },
		[hammer] = { speedLine("3,10"), { type = 46, leftText = de and "Trefferchance: Fügt einem Ziel 42 Feuerschaden zu." or "Chance on hit: Blasts a target for 42 Fire damage." } },
		[thrash] = { speedLine("2.70"), { leftText = de and "Trefferchance: Gewährt Euch einen zusätzlichen Angriff bei Eurem nächsten Schwung."
			or "Chance on hit: Grants an extra attack on your next swing." } },
		[ironfoe] = { speedLine("2.40"), { leftText = de and "Trefferchance: Gewährt Euch 2 zusätzliche Angriffe bei Eurem nächsten Schwung."
			or "Chance on hit: Grants 2 extra attacks on your next swing." } },
		[demolisher] = { speedLine("2.40"), { leftText = de and "Trefferchance: Erhöht Euer Angriffstempo 10 Sek. lang um 20%."
			or "Chance on hit: Increases your attack speed by 20% for 10 sec." } },
		[hand] = { { leftText = de and "Anlegen: Chance von 2%, bei einem Nahkampftreffer einen zusätzlichen Angriff zu erhalten."
			or "Equip: 2% chance on melee hit to gain 1 extra attack." } },
	}
	C_TooltipInfo.GetHyperlink = function(link) return { lines = tips[link] or {} } end
	local mainHand = axe
	GetInventoryItemLink = function(_, slot) return slot == 16 and mainHand or nil end
	ItemLocation.CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end
	C_Item.DoesItemExist = function(location) return location.slot == 16 end
	UnitAttackPower = function() return 0, 0, 0 end
	Enum.ItemWeaponSubclass = { Dagger = 15, Fishingpole = 20 }
	local known = {}
	IsPlayerSpell = function(id) return known[id] == true end
	local function profile(class, tree)
		setuv(getW, "weights", upvalue(getW, "WEIGHTS")[class][tree])
		setuv(getW, "weightsTree", tree)
		setuv(getW, "playerClass", class)
		clear()
	end

	-- Level 15 Enhancement shaman without Stormstrike: the weapon speed does not count.
	profile("SHAMAN", 2)
	local _, _, proc, speed = scoreFn(hammer)
	local R = ns.ProcRateDefault
	assert(speed == 0 and math.abs(proc - R * 42 / 60 * 14) < 0.001, "no Stormstrike, no speed rating")
	-- With Stormstrike (3 per minute, normalized): the slower weapon loses less against 3.3 s.
	known[17364] = true
	clear()
	local hammerScore, _, _, hammerSpeed = scoreFn(hammer)
	local axeScore, _, _, axeSpeed = scoreFn(axe)
	assert(math.abs(hammerSpeed - 14 * 3 / 60 * 15.97 * (3.1 - 3.3)) < 0.001, "hammer speed rating")
	assert(math.abs(axeSpeed - 14 * 3 / 60 * 17.5 * (2.4 - 3.3)) < 0.001, "axe speed rating")
	assert(axeScore > hammerScore, "the axe stays better with Stormstrike")
	local lines = {}
	itemsMod.db.upgradeScore = true
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, hammer)
	assert(lines[#lines] == ns.L.ITEMS_SCORE_SPEED_LINE:format(hammerSpeed), "the tooltip names the speed rating")
	-- Attack power counts for swing attacks (Seal of Command) but not for normalized ones.
	UnitAttackPower = function() return 700, 0, 0 end
	clear()
	assert(math.abs(select(4, scoreFn(hammer)) - hammerSpeed) < 0.001, "normalized attacks ignore attack power")
	profile("PALADIN", 3)
	known[20375] = true
	assert(math.abs(select(4, scoreFn(hammer)) - 0.8 * 14 * 4.9 / 60 * (15.97 + 50) * (3.1 - 3.3)) < 0.001,
		"Seal of Command scales attack power with the weapon speed")

	-- Extra attacks: one proc per minute adds a whole swing with attack power.
	profile("ROGUE", 2)
	UnitAttackPower = function() return 280, 0, 0 end
	local thrashProc = select(3, scoreFn(thrash))
	assert(math.abs(thrashProc - 1 * 14 * (R / 60) * (40 + 20) * 2.7) < 0.001, "one extra attack per proc")
	assert(math.abs(select(3, scoreFn(ironfoe)) - 1 * 14 * (2 * R / 60) * (40 + 20) * 2.4) < 0.001, "two extra attacks per proc")
	-- Attack speed: 20% for 10 s of every minute.
	local haste = upvalue(getW, "WEIGHTS").ROGUE[2].HASTE
	assert(math.abs(select(3, scoreFn(demolisher)) - haste * 20 * R * 10 / 60) < 0.001, "attack speed proc uses the haste weight")
	-- Hand of Justice: 2% of the main hand's white damage per second.
	mainHand = thrash
	clear()
	assert(math.abs(select(3, scoreFn(hand)) - 1 * 14 * 0.02 * (40 + 20)) < 0.001, "Equip chance of an extra attack")

	-- Dual wield: Sinister Strike rates the main hand speed, the off hand has none.
	known[1752] = true
	CanDualWield = function() return true end
	C_Item.DoesItemExist = function(location) return location.slot == 16 or location.slot == 17 end
	local slow, fast = "slowSword", "fastSword"
	ITEMS[slow] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	ITEMS[fast] = { "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	tips[slow], tips[fast] = { speedLine("2.90") }, { speedLine("1.50") }
	GetInventoryItemLink = function(_, slot) return (slot == 16 or slot == 17) and fast or nil end
	clear()
	assert(select(4, scoreFn(slow, false, true)) == 0, "no speed rating in the off hand")
	local score, worn = compare(slow)
	assert(math.abs(worn - 40 * 14 - 14 * 10 / 60 * 40 * (1.5 - 2.4)) < 0.001, "the slow sword replaces the fast main hand")
	assert(score > worn, "a slow main hand is an upgrade for Sinister Strike")

	-- Instant Poison VI on both hands: a faster weapon procs it more often, in either hand.
	local savedSlot, savedEnchants, savedHit = Enum.WeaponSlot, C_Item.GetWeaponEnchantInfo, ns.ImbueHitDamage
	local enchants = { [1] = 625, [2] = 625 }
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	C_Item.GetWeaponEnchantInfo = function(slot) return { { hasEnchant = true, enchantID = enchants[slot] } } end
	clear()
	local poison = function(speed) return 0.2 * (88 + 0.01 * 280) * (1 / speed - 1 / 2.4) end
	assert(math.abs(select(4, scoreFn(slow, false, true)) - 14 * poison(2.9)) < 0.001, "slow off hand: less poison")
	assert(math.abs(select(4, scoreFn(fast, false, true)) - 14 * poison(1.5)) < 0.001, "fast off hand: more poison")
	enchants = {}
	clear()
	assert(select(4, scoreFn(fast, false, true)) == 0, "no poison, no speed rating in the off hand")

	-- Weapon skill counts for the weapon in hand only: Edgemaster's Handguards with a dagger.
	local gloves, dagger = "edgemaster", "dagger"
	ITEMS[gloves] = { "INVTYPE_HAND", 4, 2, {} }
	ITEMS[dagger] = { "INVTYPE_WEAPON", 2, 15, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 } }
	tips[gloves] = de and { { leftText = "Anlegen: Äxte +7." }, { leftText = "Anlegen: Dolche +7." }, { leftText = "Anlegen: Schwerter +7." } }
		or { { leftText = "Equip: Increased Axes +7." }, { leftText = "Equip: Increased Daggers +7." }, { leftText = "Equip: Increased Swords +7." } }
	GetInventoryItemLink = function(_, slot) return slot == 16 and dagger or nil end
	clear()
	local hit = upvalue(getW, "WEIGHTS").ROGUE[2].HIT
	assert(math.abs(scoreFn(gloves) - hit * 0.2 * 7) < 0.001, "seven dagger skill, axes and swords do not count")

	-- Undead and Demons: shown in the tooltip, not part of the rating.
	local seal = "markOfTheChampion"
	ITEMS[seal] = { "INVTYPE_TRINKET", 4, 0, {} }
	tips[seal] = { { leftText = de and "Anlegen: +150 Angriffskraft im Kampf gegen Untote und Dämonen. Ermöglicht das Einsammeln von Geißelsteinen."
		or "Equip: +150 Attack Power when fighting Undead and Demons.  It also allows the acquisition of Scourgestones." } }
	clear()
	assert(scoreFn(seal) == 0, "situational attack power stays out of the rating")
	lines = {}
	ns.AddRecipeScoreLine({ AddLine = function(_, line) lines[#lines + 1] = line end }, seal)
	assert(lines[#lines] == ns.L.ITEMS_SCORE_CREATURE_LINE:format(de and "Untote und Dämonen" or "Undead and Demons", 150),
		"the tooltip shows the rating against Undead and Demons")

	-- Stormstrike's hit brings the imbue: the slower weapon's bigger Windfury hits count.
	profile("SHAMAN", 2)
	enchants = { [1] = 1669 }
	ns.ImbueHitDamage = function(id, speed, dps, ap) return id == 1669 and 0.2 * 2 * (dps + ap / 14) * speed or nil end
	clear()
	local stormstrike = 14 * 3 / 60 * (15.97 * (3.1 - 3.3) + 0.4 * (15.97 + 20) * (3.1 - 3.3))
	assert(math.abs(select(4, scoreFn(hammer)) - stormstrike) < 0.001, "Stormstrike adds the Windfury difference")

	Enum.WeaponSlot, C_Item.GetWeaponEnchantInfo, ns.ImbueHitDamage = savedSlot, savedEnchants, savedHit
	ITEMS[gloves], ITEMS[dagger], ITEMS[seal] = nil, nil, nil

	clear()
	for _, link in ipairs({ axe, hammer, thrash, ironfoe, demolisher, hand, slow, fast }) do ITEMS[link] = nil end
	ItemLocation.CreateFromEquipmentSlot, C_Item.DoesItemExist, UnitAttackPower = savedLocation, savedExists, savedAP
	GetInventoryItemLink, C_TooltipInfo.GetHyperlink, IsPlayerSpell = savedEquipped, savedTooltip, savedKnown
	CanDualWield, Enum.ItemWeaponSubclass = savedDual, savedSubclass
	setuv(getW, "playerClass", savedClass)
	setuv(getW, "weightsTree", savedTree)
	setuv(getW, "weights", savedProfile)
	print("weapon speed, extra attack and haste rating OK")
end)()
-- The imbue damage of one main-hand hit, from the spell text as in the DPS simulator.
;(function()
	local savedSpell, savedTalents, savedBonus = C_Spell, C_ClassTalents, rawget(_G, "GetSpellBonusDamage")
	local texts = { [16362] = "Imbue the Shaman's weapon with wind. Each hit has a 20% chance of dealing 2 additional attacks with 315 extra attack power.",
		[16342] = "Imbue the Shaman's weapon with fire. Each hit causes 30 to 92 additional Fire damage." }
	C_Spell = setmetatable({ GetSpellDescription = function(id) return texts[id] end }, { __index = savedSpell })
	C_ClassTalents = { GetActiveConfigID = function() return nil end }
	GetSpellBonusDamage = function() return 100 end
	local wind = ns.ImbueHitDamage(1669, 3.6, 50, 700)
	assert(math.abs(wind - 0.2 * 2 * (50 + (700 + 315) / 14) * 3.6) < 0.001, "Windfury: chance times extra attacks with extra attack power")
	local fire = ns.ImbueHitDamage(1666, 2.0, 50, 700)
	assert(math.abs(fire - (92 * 2.0 / 4 + 0.1 * 100)) < 0.001, "Flametongue: upper endpoint scaled from 4.0 s plus spell power")
	assert(ns.ImbueHitDamage(1664, 3.6, 50, 700) == nil, "Rockbiter brings no hit damage")
	C_Spell, C_ClassTalents, GetSpellBonusDamage = savedSpell, savedTalents, savedBonus
	print("imbue hit damage OK")
end)()
-- Upgrade toast: gain over the worn item, none for an empty slot
do
	local items = ns:GetModule("Items")
	assert(math.abs(items.UpgradeGain(15, 12) - 25) < 0.001, "25 % better")
	assert(items.UpgradeGain(5, 0) == nil and items.UpgradeGain(5, nil) == nil, "empty slot: no percent")
	-- usable now, only the level missing (a grey arrow), or not at all
	local red, white = { r = 1, g = 0.1, b = 0.1 }, { r = 1, g = 1, b = 1 }
	local level = ns.FormatToPattern("Benötigt Stufe %d", true).pattern
	assert(items.UseBlock({ { leftText = "Brust", leftColor = white } }, level) == "ok", "nothing red")
	assert(items.UseBlock({ { leftText = "Benötigt Stufe 18", leftColor = red } }, level) == "level", "only the level")
	assert(items.UseBlock({ { leftText = "Benötigt Stufe 18", leftColor = red }, { leftText = "Platte", leftColor = red } }, level) == "no",
		"level and armour type")
	assert(items.UseBlock(nil, level) == "no", "no tooltip data")
	print("upgrade gain OK")
end
-- Group finder: classes and missing roles
local gf = ns:GetModule("GroupFinder")
local updateEntry = uv(gf.OnOptionChanged, "RefreshAll") and uv(uv(gf.OnOptionChanged, "RefreshAll"), "UpdateEntry")
C_LFGList = {
	GetSearchResultInfo = function() return { numMembers = 3, activityIDs = { 1 }, hasSelf = false } end,
	GetActivityInfoTable = function() return { maxNumPlayers = 5 } end,
	GetSearchResultPlayerInfo = function(_, i) return ({ { classFilename = "WARRIOR", assignedRole = "TANK" }, { classFilename = "MAGE", assignedRole = "DAMAGER" }, { classFilename = "PRIEST", assignedRole = "NONE" } })[i] end,
}
CreateAtlasMarkup = function(a) return "{" .. a .. "}" end
GREEN_FONT_COLOR = { WrapTextInColorCode = function(_, t) return t end }
GRAY_FONT_COLOR = GREEN_FONT_COLOR
local texts = {}
local entry = { resultID = 1, DataDisplay = { SetAlpha = function(_, a) texts.alpha = a end } }
local displays = uv(updateEntry, "GetDisplay")
local gd = uv(displays, "displays")
gd[entry] = { Classes = { SetText = function(_, t) texts.classes = t end }, Missing = { SetText = function(_, t) texts.missing = t end }, SetAlpha = function() end, Show = function() end, Hide = function() end }
updateEntry(entry)
print("  gf", texts.classes, texts.missing, texts.alpha)
assert(texts.classes:find("warrior") < texts.classes:find("mage") and texts.missing:find("heal}1") and texts.missing:find("dps}2") and texts.alpha == 0, "group finder")
print("group finder OK")
-- QuestieDB: dungeon quests and pre-quests
local quests = { [100] = { zone = 1581 }, [101] = { zone = 40, pre = nil, next = 102 }, [102] = { zone = 40 }, [103] = { zone = 40, single = { 102 } }, [104] = { zone = 10029 }, [105] = { zone = 12 } }
-- 101 -> 102 (next) ; 103 requires 102 ; 102 does not lead to a dungeon, 106 requires 105 and is a dungeon quest
quests[106] = { zone = 1581, single = { 105 } }
LibQuestieDB = {
	Support = { Get = function() return { private = { dungeons = { [1581] = { "The Deadmines", { 10029 }, 40, {} } } } } end },
	Quest = {
		Exists = function(id) return quests[id] ~= nil end,
		Get = function(id, key) return quests[id] and key == "zoneOrSort" and quests[id].zone end,
		GetAllIds = function() local l = {} for id in pairs(quests) do l[#l + 1] = id end table.sort(l) return l end,
		GetAll = function(id) local q = quests[id] return q and { q.single, q.group, q.next or 0, 0, n = 4 } end,
	},
}
local qdb = ns.QuestieDB
do -- earlier reads cached the dungeon table of the real data mock
	local da = uv(qdb.IsDungeonQuest, "DungeonAreas")
	for i = 1, 20 do local n = debug.getupvalue(da, i) if n == "dungeonAreas" then debug.setupvalue(da, i, nil) break end end
	for i = 1, 30 do
		local n = debug.getupvalue(qdb.BuildChains, i)
		if n == "followers" or n == "building" then debug.setupvalue(qdb.BuildChains, i, nil) end
	end
end
assert(qdb.IsDungeonQuest(100) == true and qdb.IsDungeonQuest(104) == true and qdb.IsDungeonQuest(102) == false and qdb.IsDungeonQuest(999) == nil, "dungeon quests")
C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
local built = false
qdb.BuildChains(function() built = true end)
assert(built, "chains built")
assert(qdb.LeadsToDungeon(105) == true and qdb.LeadsToDungeon(101) == false, "pre-quest leads to dungeon")
print("questiedb OK")
-- QuestieDB tooltips
local info = ns:GetModule("QuestieInfo")
local npcs = { [10] = { name = "Kobold", questStarts = { 200, 201, 202, 203 }, questEnds = { 204 } }, [11] = { name = "Gnoll" }, [12] = { name = "Händlerin" } }
local items = { [500] = { name = "Leinenstoff", npcDrops = { 10, 11, 10 }, vendors = { 12 } } }
local qs = { [200] = { name = "Offen", requiredLevel = 5 }, [201] = { name = "Zu hoch", requiredLevel = 30 }, [202] = { name = "Andere Klasse", requiredClasses = 128 }, [203] = { name = "Vorquest fehlt", preQuestSingle = { 199 } }, [204] = { name = "Abgabe" } }
local function entity(t) return {
	Exists = function(id) return t[id] ~= nil end,
	Get = function(id, key) return t[id] and t[id][key] end,
	GetAll = function(id, keys) local r = { n = #keys } for i, k in ipairs(keys) do r[i] = t[id] and t[id][k] end return r end,
	GetAllIds = function() return {} end } end
LibQuestieDB = { Support = { Get = function() return {} end }, Quest = entity(qs), Npc = entity(npcs), Item = entity(items), Object = entity({}), RequireContract = function() return false end }
UnitClass = function() return "Schamane", "SHAMAN", 7 end
UnitRace = function() return "Tauren", "Tauren", 6 end
UnitLevel = function() return 14 end
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
C_QuestLog.GetLogIndexForQuestID = function(id) return id == 204 and 3 or nil end
C_Item.GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 7, 0 end
local out = {}
local tt = { IsForbidden = function() return false end, AddLine = function(_, t) out[#out + 1] = t end, Show = function() end }
for _, section in ipairs(ns.itemSections) do
	if section.order == 40 then
		for _, l in ipairs(section.fn({ id = 500 }) or {}) do out[#out + 1] = l.left end
	end
end
GameTooltip = tt
uv(info.OnInitialize, "OnUnitTooltip")(tt, { guid = "Creature-0-1-2-3-10-0000" })
for _, l in ipairs(out) do print("  ", l) end
local all = table.concat(out, "\n")
assert(all:find("Kobold, Gnoll") and all:find("Händlerin") and all:find("Offen") and not all:find("Zu hoch") and not all:find("Andere Klasse") and not all:find("Vorquest fehlt") and all:find("Abgabe"), "questie tooltips")
print("questie info OK")
-- Chat: input history and chat log
local chatM = ns:GetModule("Chat")
local styleFrame = uv(uv(chatM.OnLogin, "StyleAll"), "StyleChatFrame")
local hookHistory = uv(styleFrame, "HookHistory")
local recordSent = uv(hookHistory, "RecordSent")
local onArrow = uv(hookHistory, "OnHistoryArrow")
chatM.cdb.sentHistory = {}
recordSent(nil, "/w Bob hallo"); recordSent(nil, "hi"); recordSent(nil, "hi")
local eb = { text = "", SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end, SetCursorPosition = function() end }
onArrow(eb, "UP"); assert(eb.text == "hi", "up 1")
onArrow(eb, "UP"); assert(eb.text == "/w Bob hallo", "up 2")
onArrow(eb, "DOWN"); onArrow(eb, "DOWN"); assert(eb.text == "", "down to empty")
local logLine = uv(uv(styleFrame, "HookLog"), "LogLine")
chatM.cdb.chatLog = {}
local cf = { GetID = function() return 1 end }
for i = 1, 250 do logLine(cf, "line " .. i, 1, 1, 1) end -- trimmed in steps of 50
assert(#chatM.cdb.chatLog[1] == 200 and chatM.cdb.chatLog[1][1][1] == "line 51", "log ring")
-- Chat edges: left/right/bottom reach the screen edge, the tabs keep room on top
do
local applyEdges = uv(uv(styleFrame, "HookEdges"), "ApplyEdges")
local edgeFrame = NewFrame("Frame")
edgeFrame.clamp = { -32, 25, 60, -32 }
chatM.db.chatEdges, chatM.db.hideButtons = true, true
applyEdges(edgeFrame)
assert(edgeFrame.clamp[1] == 0 and edgeFrame.clamp[2] == 0 and edgeFrame.clamp[3] == 30 and edgeFrame.clamp[4] == 0, "edges reach the border")
edgeFrame.clamp = { -32, 25, 60, -32 }
chatM.db.hideButtons = false
applyEdges(edgeFrame)
assert(edgeFrame.clamp[1] == -32 and edgeFrame.clamp[3] == 30, "button column stays while shown")
chatM.db.chatEdges = false
edgeFrame.clamp = { -32, 25, 60, -32 }
applyEdges(edgeFrame)
assert(edgeFrame.clamp[3] == 60, "off: Blizzard's values")
chatM.db.chatEdges, chatM.db.hideButtons = true, true
end
-- Bind prompts and delete text
do
	local items = ns:GetModule("Items")
	local equipped, confirmed = nil, false
	EquipPendingItem = function(slot) equipped = slot end
	ConfirmBindOnUse = function() confirmed = true end
	items:USE_BIND_CONFIRM()
	assert(confirmed, "use bind confirmed")
	local fill = uv(items.OnLogin, "FillDeleteText")
	local box = { SetText = function(self, t) self.text = t end }
	local dialog = { GetEditBox = function() return box end }
	StaticPopup_FindVisible = function() return dialog end
	DELETE_ITEM_CONFIRM_STRING = "DELETE"
	items.db.deleteText = false
	fill("DELETE_GOOD_ITEM"); assert(box.text == nil, "off: nothing typed")
	items.db.deleteText = true
	fill("DELETE_ITEM"); assert(box.text == nil, "simple delete has no text")
	fill("DELETE_GOOD_ITEM"); assert(box.text == "DELETE", "word entered")
end
-- Extra tooltip info only with Shift
do
	local tt = ns:GetModule("Tooltip")
	tt.db.shiftInfo = false
	IsShiftKeyDown = function() return false end
	assert(ns.ExtraInfoShown(), "option off: always")
	tt.db.shiftInfo = true
	assert(not ns.ExtraInfoShown(), "option on: hidden without Shift")
	IsShiftKeyDown = function() return true end
	assert(ns.ExtraInfoShown(), "option on: shown with Shift")
	tt.db.shiftInfo = false
end
;(function()
	local module = ns:GetModule("Tooltip")
	local onShift = uv(module.OnLogin, "OnShiftChanged")
	local savedTooltip, savedSecrets, savedSecret = GameTooltip, C_Secrets, issecretvalue
	local savedSecretTable, savedWorld = issecrettable, C_TooltipInfo.GetWorldCursor
	local savedShiftInfo = module.db.shiftInfo
	module.db.shiftInfo = true
	local refreshed, restrictedUnit = 0, nil
	local types = Enum.TooltipDataType
	local item = { tooltipData = { type = types.Item, lines = {} } }
	local world = { getterName = "GetWorldCursor", tooltipData = { type = types.Unit, lines = { { unitToken = "mouseover" } } } }
	local liveWorld, secretColor, restrictedLines = world.tooltipData, {}, {}
	C_TooltipInfo.GetWorldCursor = function() return liveWorld end
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.RefreshData = function() refreshed = refreshed + 1 end
	C_Secrets = { ShouldUnitIdentityBeSecret = function(unit) return unit == restrictedUnit end }
	issecretvalue = function(value) return value == "secret" or value == secretColor end
	issecrettable = function(value) return value == restrictedLines end

	GameTooltip.infoList = { item }
	onShift(nil, nil, "LCTRL")
	assert(refreshed == 0, "other modifiers do not refresh the tooltip")
	onShift(nil, nil, "LSHIFT")
	GameTooltip.infoList = { world }
	onShift(nil, nil, "RSHIFT")
	assert(refreshed == 2, "Shift rebuilds readable item and world tooltips")

	GameTooltip.infoList = { item, { tooltipData = { lines = { { unitToken = "secret" } } } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret unit line in appended data prevents the rebuild")

	GameTooltip.infoList = { item, { tooltipData = { lines = { { leftText = "name", leftColor = secretColor } } } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret line colour in appended data prevents the rebuild")

	GameTooltip.infoList = { item, { tooltipData = { lines = restrictedLines } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a table whose contents are secret prevents the rebuild")

	GameTooltip.infoList = { { getterName = "GetUnit", getterArgs = { "secret" }, tooltipData = world.tooltipData } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a secret getter argument prevents the rebuild")

	GameTooltip.infoList = { { tooltipData = { type = types.UnitAura, lines = {} } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a tooltip without Shift extras does not need to be rebuilt")

	GameTooltip.infoList = { world }
	restrictedUnit = "mouseover"
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "a newly restricted mouseover prevents replaying the world cursor getter")
	restrictedUnit = nil
	liveWorld = { type = types.Unit, lines = { { leftText = "name", rightText = "level", rightColor = secretColor } } }
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 2, "newly restricted line colours prevent the rebuild even with readable cached data and identity")
	liveWorld = world.tooltipData
	onShift(nil, nil, "LSHIFT")
	assert(refreshed == 3, "normal refresh resumes when the unit is readable again")

	GameTooltip, C_Secrets, issecretvalue = savedTooltip, savedSecrets, savedSecret
	issecrettable, C_TooltipInfo.GetWorldCursor = savedSecretTable, savedWorld
	module.db.shiftInfo = savedShiftInfo
	print("Shift tooltip refresh OK")
end)()
;(function()
	local module = ns:GetModule("Tooltip")
	local enter, leave = uv(module.OnLogin, "OnChatItemLinkEnter"), uv(module.OnLogin, "OnChatItemLinkLeave")
	local shiftChanged = uv(module.OnLogin, "OnShiftChanged")
	local onItem = uv(module.OnInitialize, "OnItemTooltip")
	local savedTooltip, savedUtil, savedCompare = GameTooltip, TooltipUtil, GameTooltip_ShowCompareItem
	local savedShift, savedSections, savedArrow = IsShiftKeyDown, ns.itemSections, ns.ItemLinkUpgradeState
	local savedGetter, savedEquippable = C_TooltipInfo.GetHyperlink, C_Item.IsEquippableItem
	local savedColoredLine = GameTooltip_AddColoredLine
	local savedFlag, savedCalls = module.db.shiftInfo, #TEST_POSTCALLS
	local armor, food = "item:1234:0:0:0", "item:5678:0:0:0"
	local shift, compared, lines, arrow = false, false, {}
	local tip = NewFrame("GameTooltip")
	GameTooltip, module.db.shiftInfo = tip, true
	module:OnInitialize()
	for i = #TEST_POSTCALLS, savedCalls + 1, -1 do TEST_POSTCALLS[i] = nil end
	tip:Hide()
	tip.SetOwner = function(self, owner) self.owner = owner end
	tip.GetOwner = function(self) return self.owner end
	tip.GetPrimaryTooltipInfo = function(self) return self.infoList and self.infoList[1] end
	tip.AddLine = function(_, line) lines[line] = true end
	GameTooltip_AddColoredLine = function(_, line, color) lines[line] = color end
	tip.CreateTexture = function()
		arrow = NewFrame("Texture")
		arrow.SetDesaturated = function(self, value) self.desaturated = value end
		return arrow
	end
	tip.Hide = function(self)
		self.shown, compared = false, false
		self:GetScript("OnHide")(self)
	end
	TooltipUtil = { ShouldDoItemComparison = function() return false end }
	GameTooltip_ShowCompareItem = function() compared = true end
	IsShiftKeyDown = function() return shift end
	ns.itemSections = { { fn = function() return { { left = "Shift item info" } } end } }
	ns.ItemLinkUpgradeState = function() return "later" end
	C_Item.IsEquippableItem = function(link) return link == armor end
	C_TooltipInfo.GetHyperlink = function(link)
		return { hyperlink = link, type = Enum.TooltipDataType.Item, lines = {} }
	end
	tip.SetHyperlink = function(self, link)
		lines, compared = {}, false
		self:GetScript("OnTooltipCleared")(self)
		local data = C_TooltipInfo.GetHyperlink(link)
		self.infoList = { { getterName = "GetHyperlink", getterArgs = { link }, tooltipData = data } }
		onItem(self, data)
		self:Show()
	end
	tip.RefreshData = function(self) self:SetHyperlink(self.infoList[1].getterArgs[1]) end

	enter(nil, ChatFrame1, "spell:1234")
	assert(not tip:IsShown(), "non-item chat links have no item preview")
	enter(nil, ChatFrame1, armor)
	assert(tip:IsShown() and compared and arrow:IsShown() and arrow.desaturated and not lines["Shift item info"],
		"chat equipment shows comparison and the level-gated upgrade arrow without opening a separate window")
	shift = true
	shiftChanged(nil, nil, "LSHIFT")
	assert(lines["Shift item info"] and compared and arrow:IsShown(), "pressing Shift updates the open chat preview")
	shift = false
	shiftChanged(nil, nil, "LSHIFT")
	assert(not lines["Shift item info"] and compared, "releasing Shift removes extras and keeps the comparison")
	ns.ItemLinkUpgradeState = function() return "worse" end
	tip:RefreshData()
	assert(lines[ns.L.ITEMS_DOWNGRADE] == RED_FONT_COLOR and arrow:IsShown()
		and arrow.rotation == math.pi and arrow.vertexColor[2] < 0.2,
		"chat previews label downgrades and show the red down arrow")
	leave(nil, ChatFrame1)
	assert(not tip:IsShown() and not compared and not arrow:IsShown(), "leaving the link closes the preview")
	enter(nil, ChatFrame1, food)
	assert(tip:IsShown() and not compared and not arrow:IsShown(), "non-equipment only shows the item tooltip")
	tip:SetOwner(UIParent)
	leave(nil, ChatFrame1)
	assert(tip:IsShown(), "chat leave does not close a tooltip taken over by another frame")
	enter(nil, ChatFrame1, armor)
	module.db.chatItemLinks = false
	module:OnOptionChanged("chatItemLinks")
	enter(nil, ChatFrame1, armor)
	assert(not tip:IsShown(), "disabling the option dismisses and prevents the hover preview")

	GameTooltip, TooltipUtil, GameTooltip_ShowCompareItem = savedTooltip, savedUtil, savedCompare
	IsShiftKeyDown, ns.itemSections, ns.ItemLinkUpgradeState = savedShift, savedSections, savedArrow
	C_TooltipInfo.GetHyperlink, C_Item.IsEquippableItem = savedGetter, savedEquippable
	GameTooltip_AddColoredLine = savedColoredLine
	module.db.shiftInfo, module.db.chatItemLinks = savedFlag, true
	print("Chat item hover, comparison and Shift OK")
end)()
-- Quest links in chat: hover preview with the quest level in the difficulty colour
;(function()
	local module = ns:GetModule("Tooltip")
	local enter, leave = uv(module.OnLogin, "OnChatItemLinkEnter"), uv(module.OnLogin, "OnChatItemLinkLeave")
	local savedTooltip, savedAdd, savedDiff = GameTooltip, GameTooltip_AddColoredLine, GetQuestDifficultyColor
	local savedGet, savedLevel, savedCalls = ns.QuestieDB.Get, UnitLevel, #TEST_POSTCALLS
	local added, color = {}, nil
	local quests = { [100] = { 12, 10 }, [200] = { 0, 15 }, [300] = { 30, 28 } }
	local tip = NewFrame("GameTooltip")
	GameTooltip = tip
	module:OnInitialize()
	for i = #TEST_POSTCALLS, savedCalls + 1, -1 do TEST_POSTCALLS[i] = nil end
	tip:Hide()
	tip.SetOwner = function(self, owner) self.owner = owner end
	tip.GetOwner = function(self) return self.owner end
	tip.GetPrimaryTooltipInfo = function(self) return self.infoList and self.infoList[1] end
	tip.Hide = function(self)
		self.shown = false
		self:GetScript("OnHide")(self)
	end
	tip.SetHyperlink = function(self, link)
		added, color = {}, nil
		self:GetScript("OnTooltipCleared")(self)
		self.infoList = { { getterName = "GetHyperlink", getterArgs = { link } } }
		self:Show()
	end
	GameTooltip_AddColoredLine = function(_, text, c) added[#added + 1], color = text, c end
	GetQuestDifficultyColor = function(level) return { difficulty = level } end
	UnitLevel = function() return 14 end
	ns.QuestieDB.Get = function()
		return { Quest = { GetAll = function(id) local q = quests[id]; return q and { q[1], q[2] } end } }
	end

	enter(nil, ChatFrame1, "quest:100:12")
	assert(tip:IsShown() and added[1] == ns.L.TOOLTIP_QUEST_LEVEL:format(12) and color.difficulty == 12,
		"quest link shows its tooltip with the level in the difficulty colour")
	enter(nil, ChatFrame1, "quest:100:12")
	assert(#added == 1, "the level line is added only once per tooltip")
	enter(nil, ChatFrame1, "quest:300:-1")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL_REQUIRED:format(30, 28) and color == RED_FONT_COLOR,
		"a quest the player cannot accept yet shows level and required level in red")
	enter(nil, ChatFrame1, "quest:200")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL_REQUIRED:format(15, 15), "without a quest level the required level is used")
	enter(nil, ChatFrame1, "quest:999:7")
	assert(added[1] == ns.L.TOOLTIP_QUEST_LEVEL:format(7) and color.difficulty == 7, "unknown quests use the link level")
	enter(nil, ChatFrame1, "quest:998:0")
	assert(tip:IsShown() and #added == 0, "without any level the quest tooltip stays without a level line")
	leave(nil, ChatFrame1)
	assert(not tip:IsShown(), "leaving the quest link closes the preview")
	enter(nil, ChatFrame1, "quest:100:12")
	module.db.chatQuestLinks = false
	module:OnOptionChanged("chatQuestLinks")
	assert(not tip:IsShown(), "disabling the option dismisses the quest preview")
	enter(nil, ChatFrame1, "quest:100:12")
	assert(not tip:IsShown(), "disabled quest previews stay hidden")
	module.db.chatItemLinks = false
	module.db.chatQuestLinks = true
	enter(nil, ChatFrame1, "quest:100:12")
	assert(tip:IsShown(), "quest previews do not depend on the item option")

	GameTooltip, GameTooltip_AddColoredLine, GetQuestDifficultyColor = savedTooltip, savedAdd, savedDiff
	ns.QuestieDB.Get, UnitLevel = savedGet, savedLevel
	module.db.chatItemLinks, module.db.chatQuestLinks = true, true
	print("Chat quest hover with level OK")
end)()
-- Tracking menu entries
do
	local mm = ns:GetModule("Minimap")
	local add = uv(mm.OnLogin, "AddForeverPlusEntries")
	local radar = ns:GetModule("RecipeRadar")
	local created, titles, checkboxes = 0, 0, {}
	local root = { CreateDivider = function() created = created + 1 end, CreateTitle = function() titles = titles + 1 end,
		CreateCheckbox = function(_, name, isOn, set) checkboxes[#checkboxes + 1] = { name = name, isOn = isOn, set = set } end,
		CreateButton = function() return { CreateCheckbox = function() return {} end } end }
	mm.db.trackingEntries = false
	add(root); assert(#checkboxes == 0, "option off: no entries")
	mm.db.trackingEntries = true
	radar.db.enabled, radar.db.minimap = true, true
	local values = {}
	Settings.SetValue = function(var, value) values[var] = value end
	local setOption = ns.SetOption
	ns.SetOption = function(moduleName, key, value) values["ForeverPlus_" .. moduleName .. "_" .. key] = value end
	add(root)
	assert(titles == 1 and #checkboxes >= 1, "radar entry added under a title") -- the harness runs OnLogin more than once
	checkboxes = { checkboxes[#checkboxes] }
	assert(checkboxes[1].isOn() == true, "on while the radar is shown on the minimap")
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_minimap == false, "click switches the minimap pins off")
	radar.db.minimap = false
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_minimap == true, "click switches them on")
	ns.SetOption = setOption
end
-- Flight popup: destinations by price, hovered one kept when the list is cut
do
	local flight = ns:GetModule("Flight")
	local nodes = {
		{ "Hier", "CURRENT", 0 }, { "Zeta", "REACHABLE", 300 }, { "Alpha", "REACHABLE", 300 }, { "Nah", "REACHABLE", 50 },
		{ "Fern", "REACHABLE", 900 }, { "Gesperrt", "UNREACHABLE", 0 },
	}
	NumTaxiNodes = function() return #nodes end
	TaxiNodeGetType = function(i) return nodes[i][2] end
	TaxiNodeName = function(i) return nodes[i][1] end
	TaxiNodeCost = function(i) return nodes[i][3] end
	flight.db.times["Hier -> Nah"] = 95
	local destinations = uv(uv(flight.OnLogin, "ShowRoutes"), "Destinations")
	local list, hidden = destinations(4, 10)
	assert(#list == 4 and hidden == 0, "four reachable destinations")
	assert(list[1].name == "Nah" and list[1].time == 95 and list[1].hovered, "cheapest first, time known, hovered")
	assert(list[2].name == "Alpha" and list[3].name == "Zeta" and list[4].name == "Fern", "price, then name")
	list, hidden = destinations(5, 2)
	assert(#list == 2 and hidden == 2, "cut to two, two hidden")
	local kept = false
	for _, entry in ipairs(list) do kept = kept or entry.name == "Fern" end
	assert(kept, "the hovered destination stays in the cut list")
end
print("chat history OK")
-- Sliced runner and timings
local sum, done = 0, false
C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
ns.RunSliced("Test: slices", 1000, function(i) sum = sum + i end, function() done = true end, 0.001)
assert(done and sum == 500500, "sliced run")
assert(ns.timings["Test: slices"].count > 1, "ran in several slices")
local printed = {}
ns.PrintAlways = function(msg, ...) printed[#printed + 1] = select("#", ...) > 0 and msg:format(...) or msg end
ns.PrintTimings()
print("  " .. printed[1]); print("  " .. printed[2])
print("timings OK")
-- Chat copy: plain text of the last lines
local chatC = ns:GetModule("Chat")
local shown
ns.ShowEditWindow = function(_, _, text) shown = text end
local msgs = {}
for i = 1, 60 do msgs[i] = "line " .. i end
msgs[60] = "|cff1eff00|Hitem:1::|h[Leinenstoff]|h|r von |Kq12|k |TInterface\\X:0|t ok"
local frame = { GetNumMessages = function() return #msgs end, GetMessageInfo = function(_, i) return msgs[i] end }
chatC:CopyChat(frame)
local lines = {}
for l in shown:gmatch("[^\n]+") do lines[#lines + 1] = l end
print("  copy last:", lines[#lines], #lines)
assert(#lines == 50 and lines[1] == "line 11" and lines[50] == "[Leinenstoff] von ?  ok", "chat copy")
print("chat copy OK")
-- Active self buffs greyed out
local vis = ns:GetModule("Visuals")
local updateWatch = uv(vis.OnOptionChanged, "UpdateAuraWatch")
local updateAuras = uv(updateWatch, "UpdateActiveAuras")
local colorBtn = uv(uv(updateAuras, "RecolorBuffButtons"), "ColorButton")
vis.db.actionColors, vis.db.colorActiveBuff, vis.db.colorRange = true, true, true
local auras = { { name = "Siegel der Rechtschaffenheit", auraInstanceID = 11 } }
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_Spell.IsSelfBuff = function(id) return id == 20154 end
C_Spell.GetSpellName = function(id) return id == 20154 and "Siegel der Rechtschaffenheit" or "Heiliges Licht" end
GetActionInfo = function(slot) return "spell", slot == 1 and 20154 or 635 end
C_ActionBar.IsUsableAction = function() return true end
local function mkBtn(slot) local b = { action = slot, icon = { SetVertexColor = function(self, r) self.r = r end, SetDesaturated = function(self, d) self.d = d end } } return b end
local seal, light = mkBtn(1), mkBtn(2)
updateWatch()
colorBtn(seal); colorBtn(light)
assert(seal.icon.d == true and not light.icon.d, "active seal greyed")
do
	local savedAfter, queued, scheduled, scans = C_Timer.After, nil, 0, 0
	C_Timer.After = function(_, fn) queued, scheduled = fn, scheduled + 1 end
	C_UnitAuras.GetUnitAuras = function() scans = scans + 1 return auras end
	local watcher = uv(updateWatch, "auraWatcher")
	local onEvent = watcher:GetScript("OnEvent")
	onEvent(watcher, "UNIT_AURA", "player", { updatedAuraInstanceIDs = { 11 } })
	onEvent(watcher, "UNIT_AURA", "player", { addedAuras = { { isHelpful = false } }, removedAuraInstanceIDs = { 22 } })
	assert(scheduled == 0, "refreshes and harmful auras skip the scan")
	local saved = auras
	auras = {}
	onEvent(watcher, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 11 } })
	onEvent(watcher, "UNIT_AURA", "player", { isFullUpdate = true })
	assert(scheduled == 1, "helpful removal and full update share a scan")
	light.icon.r = 0.25
	queued()
	assert(scans == 1 and seal.icon.d == false and light.icon.r == 0.25, "one batch read updates the buff button only")
	C_UnitAuras.GetUnitAuras = nil
	auras, C_Timer.After = saved, savedAfter
	updateAuras()
end
do
	C_Secrets.ShouldAurasBeSecret = function() return true end
	local saved = auras
	auras = {}
	updateAuras()
	colorBtn(seal)
	assert(seal.icon.d == true, "secret keeps last set")
	C_Secrets.ShouldAurasBeSecret = function() return false end
	C_UnitAuras.GetAuraDataByIndex = function() error("secret") end
	updateAuras()
	colorBtn(seal)
	assert(seal.icon.d == true, "error keeps last set")
	C_UnitAuras.GetAuraDataByIndex = function(_, i) return auras[i] end
	auras = saved
	print("secret auras OK")
end
auras = {}
updateAuras(); colorBtn(seal)
assert(seal.icon.d == false and seal.icon.r == 1, "seal back to normal")
print("active buff OK")
-- Weapon imbues are no auras: greyed by the weapon enchant that matches the spell
;(function()
	local savedImbues, savedSlot, savedItem, savedInfo = ns.WeaponImbues, Enum.WeaponSlot, C_Item, GetActionInfo
	local savedName, savedSelf = C_Spell.GetSpellName, C_Spell.IsSelfBuff
	ns.WeaponImbues = { [283] = { kind = "wind", spellID = 8232 }, [5] = { kind = "fire", spellID = 8024 } }
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	local enchants = { [1] = { { hasEnchant = true, enchantID = 283 } }, [2] = {} }
	C_Item = setmetatable({ GetWeaponEnchantInfo = function(slot) return enchants[slot] end }, { __index = savedItem })
	C_Spell.IsSelfBuff = function() return false end
	C_Spell.GetSpellName = function(id) return "Imbue " .. id end
	GetActionInfo = function(slot) return "spell", slot == 1 and 8232 or 8024 end
	local wind, fire = mkBtn(1), mkBtn(2)
	updateAuras()
	colorBtn(wind); colorBtn(fire)
	assert(wind.icon.d == true and not fire.icon.d, "active windfury imbue greyed, fire imbue not")
	enchants[1] = {}
	updateAuras()
	colorBtn(wind)
	assert(wind.icon.d == false, "imbue back to normal once the enchant is gone")
	enchants[1] = { { hasEnchant = true, enchantID = 283 } }
	updateAuras()
	vis.db.activeBuffExceptions = { ["Imbue 8232"] = true }
	colorBtn(wind)
	assert(not wind.icon.d, "exception keeps imbue normal")
	vis.db.activeBuffExceptions = {}
	-- Poisons and oils: the weapon tooltip carries the enchant line "Name (30 min)"
	local savedTip = C_TooltipInfo.GetInventoryItem
	local tip = { lines = { { leftText = "Sofort wirkendes Gift VII (30 Min.)" } } }
	C_TooltipInfo.GetInventoryItem = function() return tip end
	enchants[1], enchants[2] = { { hasEnchant = true, enchantID = 9999 } }, {}
	C_Item.GetItemInfo = function(id) return id == 100 and "Sofort wirkendes Gift VII" or id == 101 and "Sofort wirkendes Gift" or "Anderes" end
	C_Item.GetItemSpell = function() return nil end
	GetActionInfo = function(slot) return "item", 100 + slot - 1 end
	local poison, other = mkBtn(1), mkBtn(2)
	updateAuras()
	colorBtn(poison); colorBtn(other)
	assert(poison.icon.d == true and not other.icon.d, "applied poison greyed, other item not")
	enchants[1] = {}
	updateAuras()
	colorBtn(poison)
	assert(poison.icon.d == false, "poison back to normal once the enchant is gone")
	C_TooltipInfo.GetInventoryItem = savedTip
	ns.WeaponImbues, Enum.WeaponSlot, C_Item, GetActionInfo = savedImbues, savedSlot, savedItem, savedInfo
	C_Spell.GetSpellName, C_Spell.IsSelfBuff = savedName, savedSelf
	auras = {}
	updateAuras()
	print("weapon imbue OK")
end)()
;(function()
	-- A slow call during which the Lua memory went down carries "(GC)"; fast calls and growing memory do not.
	local savedTime, savedClock, savedGC = GetTime, debugprofilestop, collectgarbage
	local now, clock, memory = 900, 0, 1000
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	collectgarbage = function(option)
		if option == "count" then
			return memory
		end
		return savedGC(option)
	end
	ns.SetMeasuring(true)
	now = 901
	ns.Measured("Test: slow with GC", function() clock, memory = clock + 8, memory - 200 end)()
	ns.Measured("Test: slow, memory grows", function() clock, memory = clock + 8, memory + 50 end)()
	ns.Measured("Test: fast with GC", function() clock, memory = clock + 1, memory - 200 end)()
	assert(ns.timings["Test: slow with GC (GC)"] and not ns.timings["Test: slow with GC"], "slow call with GC is marked")
	assert(ns.timings["Test: slow, memory grows"] and ns.timings["Test: fast with GC"], "others keep their name")
	ns.SetMeasuring(false)
	GetTime, debugprofilestop, collectgarbage = savedTime, savedClock, savedGC
	print("GC mark OK")
end)()
-- Exceptions and timed measure
vis.db.activeBuffExceptions = { ["Siegel der Rechtschaffenheit"] = true }
auras = { { name = "Siegel der Rechtschaffenheit" } }
updateAuras(); colorBtn(seal)
assert(not seal.icon.d, "exception keeps seal normal")
vis.db.activeBuffExceptions = {}
;(function()
	local timerFn
	C_Timer.NewTimer = function(_, fn) timerFn = fn return { Cancel = function() end } end
	local savedTime = GetTime
	local now = 800
	GetTime = function() return now end
	ns.timings["old"] = { max = 1, count = 1, slow = 0 }
	local info = ns:GetModule("Info")
	local savedResult = info.lastMeasure
	local perf = uv(info.UpdatePerformance, "perfFrame")
	perf:GetScript("OnMouseUp")(perf, "MiddleButton")
	assert(ns.measuring and not ns.timings.old, "measuring, old values cleared")
	local lateStart = ns.Measured("Test: measurement start", function() ns.SetMeasuring(true) end)
	lateStart()
	assert(not ns.timings["Info: performance click"] and not ns.timings["Test: measurement start"], "startup calls stay outside the results")
	local sampleFrame = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local savedMetric = C_AddOnProfiler.GetAddOnMetric
	C_AddOnProfiler.GetAddOnMetric = function() return 35 end
	sampleFrame()
	assert(ns.spikes.samples == 0, "ignore the profiler value from before the current measurement")
	now = 801
	C_AddOnProfiler.GetAddOnMetric = function() return 5 end
	sampleFrame()
	assert(ns.spikes.samples == 0, "the frame containing the click stays outside the results")
	ns.RecordTiming("X: y", 0.9)
	ns.RecordTiming("Y: x", 0.4)
	now = 802
	C_AddOnProfiler.GetAddOnMetric = function() return 35 end
	sampleFrame()
	assert(ns.spikes.samples == 1 and ns.spikes.count == 1 and ns.spikes.worst == 35 and ns.spikes.name == "X: y",
		"one slow frame can occur even when every individual call is short")
	timerFn()
	assert(info.lastMeasure.frames == ns.spikes and not ns.measuring and ns.TopTimings(5)[1].name == "X: y", "timed measure")
	local oldFrames = ns.spikes
	ns.SetMeasuring(true)
	sampleFrame()
	now = 803
	sampleFrame()
	now = 804
	C_AddOnProfiler.GetAddOnMetric = function() return 0.7 end
	sampleFrame()
	assert(ns.spikes.worst == 0.7 and ns.spikes.count == 0 and oldFrames.worst == 35,
		"the next measurement shows a peak below the threshold without overwriting the previous result")
	ns.SetMeasuring(false)
	C_AddOnProfiler.GetAddOnMetric = savedMetric
	local captured = {}
	local savedTooltip = GameTooltip
	GameTooltip = NewFrame("Tooltip")
	GameTooltip.AddLine = function(_, line) captured[line] = true end
	GameTooltip.AddDoubleLine = function(_, label, value) captured[label] = value end
	local createPerfFrame = uv(info.UpdatePerformance, "CreatePerfFrame")
	uv(createPerfFrame, "RefreshCpuTooltip")(UIParent)
	assert(captured[ns.FormatMeasuredFrames(oldFrames)] and captured["X: y"] == "0.9 ms (1)",
		"the tooltip shows the finished measurement's frame peak alongside its individual calls")
	GameTooltip = savedTooltip
	info.lastMeasure = savedResult
	GetTime = savedTime
	print("exceptions/measure OK")
end)()
-- Popup list smoke test (layout logic)
local owner = NewFrame("Button")
local built = 0
ns.ShowPopupList(owner, function()
	built = built + 1
	local list = { { text = "Abschnitt" } }
	for i = 1, 20 do list[#list + 1] = { text = "Eintrag " .. i, icon = 1, checked = i % 2 == 0, onClick = function() end } end
	return { title = "Test", items = list, footer = { { text = "Alle", onClick = function() end } } }
end)
assert(built == 1, "popup built")
print("popup OK")
;(function()
	local profiles = ns:GetModule("Profiles")
	local savedShow, savedPrint, savedSnapshot, savedAfter = ns.ShowEditWindow, ns.PrintAlways, profiles.Snapshot, ns.After
	local savedStore, savedLastAuto, savedTime, savedDate = ns.db.profiles, profiles.db.lastAuto, time, date
	local now = 1784000000
	time, date = function() return now end, os.date
	ns.db.profiles = {}
	local store = ns.db.profiles
	local editor, message
	ns.ShowEditWindow = function(_, title, initial, _, accept) editor = { title = title, initial = initial, accept = accept } end
	ns.PrintAlways = function(text) message = text end
	profiles.Snapshot = function() return { time = now, cvars = { example = "1" }, bindings = {}, layouts = {}, addon = {} } end
	local owner = NewFrame("Button")
	profiles.ShowList(owner)
	local popup = ForeverPlusPopupProfiles
	local function Click(label)
		for index, entry in ipairs(popup.build().footer) do
			if entry.text == label then
				local button = popup.footer[index]
				button:GetScript("OnClick")(button)
				return
			end
		end
		error("profile action missing: " .. label)
	end
	Click(ns.L.PROFILES_CREATE)
	assert(not popup:IsShown() and editor.title == ns.L.PROFILES_CREATE_TITLE, "create is available in an empty list")
	editor.accept("  Original  ")
	local snapshot = assert(store.Original, "create saves current settings under the trimmed name")
	assert(popup:IsShown() and popup.build().items[1].checked, "created profile is selected")
	Click(ns.L.PROFILES_CREATE)
	editor.accept("Original")
	assert(message == ns.L.PROFILES_NAME_EXISTS and store.Original == snapshot, "create cannot overwrite an existing profile")
	assert(profiles.Save("Taken"), "save a second profile for the rename conflict")
	local target = store.Taken
	Click(ns.L.PROFILES_RENAME)
	assert(editor.initial == "Original", "rename starts with the selected profile name")
	editor.accept(" Taken ")
	assert(message == ns.L.PROFILES_NAME_EXISTS and store.Original == snapshot and store.Taken == target, "rename conflict keeps both profiles")
	Click(ns.L.PROFILES_RENAME)
	editor.accept(" ")
	assert(message == ns.L.PROFILES_NAME_REQUIRED and store.Original == snapshot, "rename requires a name")
	Click(ns.L.PROFILES_RENAME)
	editor.accept("  Main  ")
	assert(not store.Original and store.Main == snapshot and snapshot.cvars.example == "1", "rename keeps the same snapshot")
	assert(popup.build().items[1].checked and popup.build().items[1].text:find("^Main "), "renamed profile stays selected")
	Click(ns.L.PROFILES_LOAD)
	Click(ns.L.PROFILES_DELETE)
	popup:Hide()

	local prefix = ns.L.PROFILES_AUTO_PREFIX
	local legacy = prefix .. date("%Y-%m-%d %H:%M", now - 86400)
	store[legacy] = { time = now - 86400 }
	local custom = prefix .. date("%Y-%m-%d %H:%M", now)
	assert(profiles.Rename(legacy, custom), "an older automatic backup can be renamed")
	local retained = store[custom]
	ns.After = function(_, _, backup) backup() end
	profiles.db.lastAuto = 0
	profiles:OnLogin()
	assert(store[custom] == retained and store[custom .. " (2)"].automatic, "the new backup uses a free name")
	for _ = 2, 4 do
		now = now + 86400
		profiles:OnLogin()
	end
	local autoCount = 0
	for _, profile in pairs(store) do
		if profile.automatic then autoCount = autoCount + 1 end
	end
	assert(store[custom] == retained and autoCount == 3, "rotation protects renamed backups and keeps three automatic copies")
	assert(profiles.Save("Main") and store.Main ~= snapshot, "direct save can still refresh an existing profile")
	ns.ShowEditWindow, ns.PrintAlways, profiles.Snapshot, ns.After = savedShow, savedPrint, savedSnapshot, savedAfter
	ns.db.profiles, profiles.db.lastAuto, time, date = savedStore, savedLastAuto, savedTime, savedDate
	print("profile management and automatic backup rotation OK")
end)()

;(function()
	local savedSettings, savedPanel, savedHook = Settings, SettingsPanel, hooksecurefunc
	local main, childCategory = NewFrame("Frame"), NewFrame("Frame")
	local tab = NewFrame("Button")
	local inits = {}
	local function Init() return { InitFrame = function() end } end
	Settings = setmetatable({
		RegisterVerticalLayoutCategory = function() return main end,
		RegisterVerticalLayoutSubcategory = function() return childCategory end,
		CreateElementInitializer = Init,
		CreateCheckbox = function(category, setting)
			local initializer = Init()
			if setting.variable then
				inits[setting.variable] = { initializer = initializer, category = category }
			end
			return initializer
		end,
		RegisterAddOnSetting = function(_, variable) return { variable = variable, SetValueChangedCallback = function() end } end,
	}, { __index = savedSettings })
	SettingsPanel = { AddOnsTab = tab, GetLayout = savedPanel.GetLayout }
	hooksecurefunc = function(object, method, hook)
		local original = object[method]
		object[method] = function(...) original(...) hook(...) end
	end
	local mover = { name = "Mover", options = {
		{ type = "button", name = "Mover 1" }, { type = "button", name = "Mover 2" }, { type = "button", name = "Mover 3" },
	} }
	local profiles = { name = "Profiles", db = {}, defaults = { auto = true }, options = ns:GetModule("Profiles").options }
	local chat = { name = "Chat", db = {}, defaults = { tabFade = true, existing = false }, options = {
		{ key = "tabFade", type = "toggle", new = true },
		{ key = "existing", type = "toggle" },
	} }
	local modules = { Mover = mover, Profiles = profiles, Chat = chat }
	local tabBadge
	local settingsNS = setmetatable({
		db = {}, modules = {},
		GetModule = function(_, name) return modules[name] end,
		CreateNewBadge = function(owner, text)
			local badge = ns.CreateNewBadge(owner, text)
			if owner == tab then tabBadge = badge end
			return badge
		end,
	}, { __index = ns })
	assert(loadfile(root .. "/Core/Settings.lua"))("ForeverPlus", settingsNS)
	settingsNS:BuildSettings()
	local auto, other = inits.ForeverPlus_Profiles_auto, inits.ForeverPlus_Chat_tabFade
	assert(auto.category == main and other.category ~= main and auto.initializer.fpNewID, "both main page and subpage options have stable IDs")
	assert(not inits.ForeverPlus_Chat_existing.initializer.fpNewID, "the initial build treats existing unmarked settings as the baseline")
	-- Simulate a row with a label tooltip and a nested control, as in the settings list.
	local row, label, control = NewFrame("Frame"), NewFrame("Frame"), NewFrame("Button")
	row.fpNewBadge = false
	row.fpNewHooked, label.fpNewHooked, control.fpNewHooked = false, false, false
	row.fpNewMouseID = false
	row.GetChildren = function() return label end
	label.GetChildren = function() return control end
	local over = true
	row.IsMouseOver = function() return over end
	local function Show(initializer)
		row.GetElementData = function() return initializer end
		initializer:InitFrame(row)
	end
	local function TwoPasses(initializer)
		Show(initializer)
		assert(row.fpNewBadge:IsShown(), "unseen row is marked NEW")
		label:GetScript("OnEnter")(label)
		label:GetScript("OnLeave")(label)
		control:GetScript("OnEnter")(control)
		assert(row.fpNewBadge:IsShown() and settingsNS.db.settingsNewSeen[initializer.fpNewID] == 1, "moving within the row counts once")
		over = false
		control:GetScript("OnLeave")(control)
		over = true
		control:GetScript("OnEnter")(control)
		assert(not row.fpNewBadge:IsShown() and settingsNS.db.settingsNewSeen[initializer.fpNewID] == 2, "second mouseover clears NEW")
		row:GetScript("OnHide")(row)
		Show(initializer)
		assert(not row.fpNewBadge:IsShown(), "dismissal survives row recycling")
	end
	TwoPasses(other.initializer)
	assert(tabBadge:IsShown(), "main page still has an unseen option")
	TwoPasses(auto.initializer)
	assert(not tabBadge:IsShown(), "dismissing the last new option clears the tab badge")
	settingsNS.db.settingsNewSeen[auto.initializer.fpNewID] = 3
	Show(auto.initializer)
	assert(not row.fpNewBadge:IsShown(), "previously dismissed rows stay dismissed")

	chat.defaults.added, chat.defaults.classOption = false, false
	chat.options[#chat.options + 1] = { key = "added", type = "toggle" }
	chat.options[#chat.options + 1] = { key = "classOption", type = "toggle", newScope = "TestClass" }
	settingsNS:BuildSettings()
	local added = inits.ForeverPlus_Chat_added.initializer
	assert(added.fpNewID and tabBadge:IsShown(), "an option added in an update is marked without an explicit new flag")
	assert(not inits.ForeverPlus_Chat_classOption.initializer.fpNewID, "a class visited for the first time starts with a baseline")
	TwoPasses(added)
	settingsNS:BuildSettings()
	Show(inits.ForeverPlus_Chat_added.initializer)
	assert(not row.fpNewBadge:IsShown() and not tabBadge:IsShown(), "automatic dismissal survives rebuilding after a reload")
	Settings, SettingsPanel, hooksecurefunc = savedSettings, savedPanel, savedHook
	print("two mouseovers dismiss NEW on main and subpages OK")
end)()

-- Loot summary popup
local lootM = ns:GetModule("Loot")
local showSummary = uv(lootM.OnLogin, "ShowSummary")
local summariesT = uv(showSummary, "summaries")
summariesT[99] = { count = 2, order = { link }, items = { [link] = { count = 2, sources = { Kobold = 2 }, order = { "Kobold" } } }, money = 50, moneySources = { Kobold = 50 }, moneyOrder = { "Kobold" }, started = 0, ended = 60 }
C_Item.GetItemIconByID = function() return 123 end
date = os.date
local popupData
ns.ShowPopupList = function(_, build) popupData = build() end
showSummary(99)
for _, it in ipairs(popupData.items) do print("  loot popup:", it.text) end
assert(#popupData.items == 4 and popupData.items[2].icon == 123 and popupData.items[2].text:find("x2"), "loot popup")
-- Destroy only when cheaper than incoming loot
local itemsD = ns:GetModule("Items")
local offer = uv(itemsD.UI_ERROR_MESSAGE, "OfferDestroy")
local incoming = uv(offer, "IncomingValue")
GetNumLootItems = function() return 1 end
GetLootSlotType = function() return Enum.LootSlotType and Enum.LootSlotType.Item or 1 end
Enum.LootSlotType = { Item = 1 }
GetLootSlotType = function() return 1 end
GetLootSlotInfo = function() return nil, nil, 2, nil, nil, nil, false end
GetLootSlotLink = function() return "x" end
C_Item.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 30 end
assert(incoming() == 60, "incoming value")
GetLootSlotInfo = function() return nil, nil, 1, nil, nil, nil, true end
assert(incoming() == math.huge, "quest item")
print("loot popup/destroy OK")
-- sell button + stack size
do
	local Items = ns:GetModule("Items")
	local kids = {}
	print("sell button created", Items.db.sellButton)
	local Tooltip = ns:GetModule("Tooltip")
	-- the item tooltip's extra block: stack size section, all under one separator
	;(function()
	local Tooltip, uv = Tooltip, uv
	local orig = C_Item.GetItemInfo
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 20 end
	local stack
	for _, section in ipairs(ns.itemSections) do
		if section.order == 10 then stack = section end
	end
	assert(stack, "stack size section registered")
	local lines = stack.fn({ id = 2589 })
	assert(lines and #lines == 1 and lines[1].left == ns.L.TOOLTIP_STACK_SIZE and lines[1].right == "20", "stack size line")
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 1 end
	assert(stack.fn({ id = 1 }) == nil, "no line for single items")
	C_Item.GetItemInfo = orig
	-- composed: one separator, then the lines of the sections in order
	local order, added = {}, {}
	for _, section in ipairs(ns.itemSections) do order[#order + 1] = section.order end
	for i = 2, #order do assert(order[i - 1] <= order[i], "sections sorted") end
	local composed = {}
	local tipFake = { IsForbidden = function() return false end, AddLine = function(_, t) composed[#composed + 1] = t end,
		AddDoubleLine = function(_, a, b) composed[#composed + 1] = a .. "=" .. tostring(b) end, Show = function() end }
	ns.itemSections[#ns.itemSections + 1] = { order = 99, fn = function() return { { left = "last" } } end }
	C_Item.GetItemInfo = function() return "x", nil, 1, 1, 1, "", "", 20 end
	local OnItem = uv(Tooltip.OnInitialize, "OnItemTooltip")
	if OnItem then OnItem(tipFake, { id = 2589 }) end
	C_Item.GetItemInfo = orig
	table.remove(ns.itemSections)
	print("extra block:", table.concat(composed, " | "))
	end)()
	local jv = uv(uv(Items.Refresh, "CreateSellButton"), "UpdateSellButton")
	jv = uv(jv, "JunkValue")
	print("junk value with kept grey", jv())
end
do
	C_ActionBar = C_ActionBar or {}
	C_ActionBar.GetActionBarPage = function() return 1 end
	ActionBar_PageUp = function() end
	ActionBar_PageDown = function() end
	ns.StartWheelCheck()
	ActionBar_PageUp()
	print("wheel check OK")
	local vis = ns:GetModule("Visuals")
	local glow = uv(vis.OnLogin or vis.OnInitialize, "UpdateGlow")
	print("glow fn", glow ~= nil)
end
do
	local tt = ns:GetModule("Tooltip")
	local show = uv(tt.OnInitialize, "ShowTrainerCompare")
	print("trainer compare fn", show ~= nil)
	if show then
		_G.GetTrainerServiceItemLink = function() return "|cff1eff00|Hitem:3846::::|h[Stiefel]|h|r" end
		C_Item.GetItemInfoInstant = function() return 3846, "Rüstung", "Platte", "INVTYPE_FEET" end
		GetInventoryItemLink = function(_, slot) return slot == 8 and "|Hitem:1|h[Alt]|h" or nil end
		local tip = setmetatable({ IsForbidden = function() return false end, GetRight = function() return 500 end,
			GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end }, { __index = function() return function() end end })
		local ok, err = pcall(show, tip, 3)
		print("trainer compare run", ok, err)
		-- In the bubble at a nameplate the tooltip cannot be measured (error): the comparison still shows.
		tip.GetRight = function() error("Can't measure restricted regions") end
		GetCursorPosition = function() return 400, 300 end
		ok, err = pcall(show, tip, 3)
		assert(ok, "restricted tooltip: " .. tostring(err))
		print("trainer compare restricted OK")
		;(function()
			-- Critical hits pop up like the experience: small, past their size, back to exactly 1
			local ct = ns:GetModule("CombatText")
			local s0, a0 = ct.CritPop(0)
			assert(math.abs(s0 - 0.4) < 1e-9 and a0 == 0, "starts small and invisible")
			local peak = 0
			for t = 0, 0.75, 0.005 do peak = math.max(peak, (ct.CritPop(t))) end
			assert(peak > 1.6 and peak < 2, "clearly larger, like the experience: " .. peak)
			assert(ct.CritPop(0.4) == 1.6 and select(2, ct.CritPop(0.04)) > 0.9, "stays large a moment, visible at once")
			local s1, a1 = ct.CritPop(0.75)
			assert(s1 == 1 and a1 == 1, "ends at its size")
			print("crit pop OK")
		end)()
	end
end
do
	-- nearest anchor point
	local mover = ns:GetModule("Mover")
	local save = uv(uv(mover.GLOBAL_MOUSE_UP, "StopMoving"), "Save")
	local nearest = uv(save, "NearestPoint")
	local function region(l, b, w, h, es)
		return { GetLeft = function() return l end, GetRight = function() return l + w end, GetBottom = function() return b end,
			GetTop = function() return b + h end, GetCenter = function() return l + w / 2, b + h / 2 end, GetEffectiveScale = function() return es or 1 end }
	end
	local rel = region(0, 0, 1000, 600)
	local p, x, y = nearest(region(950, 560, 40, 20), rel)
	print("nearest topright", p, x, y)
	assert(p == "TOPRIGHT" and x == -10 and y == -20, "top right")
	p, x, y = nearest(region(480, 290, 40, 20), rel)
	assert(p == "CENTER" and x == 0 and y == 0, "center")
	p, x, y = nearest(region(10, 10, 40, 20, 2), region(0, 0, 1000, 600, 1))
	print("nearest scaled", p, x, y)
	-- nameplate fade
	local qol = ns:GetModule("QoL")
	local plates = { { IsForbidden = function() return false end, UnitFrame = { SetAlpha = function(self, a) self.a = a end } } }
	C_NamePlate = { GetNamePlates = function() return plates end, GetNamePlateForUnit = function() return plates[1] end }
	qol.db.nameplatesFade, qol.db.nameplatesFadeAmount = true, 70
	qol.db.nameplatesTargetFull, qol.db.nameplatesFadeCombat = true, false
	InCombatLockdown = function() return false end
	UnitExists = function() return false end -- no target
	qol:UpdateNameplates()
	print("plate alpha", plates[1].UnitFrame.a)
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "faded")
	uv(qol.UpdateNameplates, "OnCombatStart")()
	assert(plates[1].UnitFrame.a == 1, "combat full (old behaviour)")
	uv(qol.UpdateNameplates, "OnCombatEnd")()
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "faded again")
	-- new: the other units stay transparent in combat, the target never is
	qol.db.nameplatesFadeCombat = true
	uv(qol.UpdateNameplates, "OnCombatStart")()
	assert(math.abs(plates[1].UnitFrame.a - 0.3) < 1e-6, "others faded in combat")
	UnitExists = function() return true end -- the harness returns this plate for "target"
	uv(qol.UpdateNameplates, "FadeAllPlates")()
	assert(plates[1].UnitFrame.a == 1, "target fully visible")
	uv(qol.UpdateNameplates, "OnCombatEnd")()
	UnitExists = function() return false end
	qol.db.nameplatesFade = false
	qol:UpdateNameplates()
	assert(plates[1].UnitFrame.a == 1, "off full")
	print("new features OK")
end
do
	local items = ns:GetModule("Items")
	local scan = uv(items.Refresh, "ScanNewItems")
	print("scan fn", scan ~= nil)
	local showNext = uv(scan, "ShowNextUpgrade")
	local queue = uv(showNext, "upgradeQueue")
	items.db.upgradePopup = true
	InCombatLockdown = function() return false end
	queue[1] = { link = "|cff1eff00|Hitem:3846::::|h[Stiefel]|h|r", score = 15.8, equippedScore = 12.3, invSlot = 8 }
	C_Item.GetItemInfo = function() return "Stiefel", nil, 2, nil, nil, nil, nil, nil, nil, 133 end
	ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
	GetInventoryItemLink = function() return "|Hitem:1|h[Alt]|h" end
	local ok, err = pcall(showNext)
	assert(ok, "show upgrade: " .. tostring(err))
	queue[1] = { link = "x", score = 5, equippedScore = 0 }
	ok, err = pcall(showNext)
	assert(ok, "show upgrade empty slot: " .. tostring(err))
end
(function()
	-- Wowhead link in the right-click menus of tracker and quest log
	local quests = ns:GetModule("Quests")
	local savedMenu, savedLocale, savedEdit = Menu, GetLocale, ns.ShowEditWindow
	local modifiers, shown = {}, nil
	Menu = { ModifyMenu = function(tag, fn) modifiers[tag] = fn end }
	GetLocale = function() return "deDE" end
	ns.ShowEditWindow = function(key, _, text) shown = { key, text } end
	assert(quests.WowheadURL(783) == "https://www.wowhead.com/forever/de/quest=783", quests.WowheadURL(783))
	local function Root()
		local root = { buttons = {} }
		root.CreateDivider = function() end
		root.CreateButton = function(_, text, fn) root.buttons[#root.buttons + 1] = { text, fn } end
		return root
	end
	quests.db.wowheadLink = true
	quests.HookWowheadMenus()
	quests.hoveredQuest = 783
	local root = Root()
	modifiers.MENU_QUEST_OBJECTIVE_TRACKER(nil, root)
	assert(#root.buttons == 1 and root.buttons[1][1] == ns.L.QUESTS_WOWHEAD, "tracker entry")
	root.buttons[1][2]()
	assert(shown and shown[1] == "Wowhead" and shown[2]:find("quest=783", 1, true), "link window")
	root = Root()
	modifiers.MENU_QUEST_MAP_LOG_TITLE({ questID = 42 }, root)
	root.buttons[1][2]()
	assert(shown[2]:find("quest=42", 1, true), "quest log entry")
	root = Root()
	modifiers.MENU_QUEST_MAP_LOG_TITLE({}, root)
	assert(#root.buttons == 0, "waypoint menu without quest: no entry")
	quests.db.wowheadLink = false
	root = Root()
	modifiers.MENU_QUEST_OBJECTIVE_TRACKER(nil, root)
	assert(#root.buttons == 0, "option off")
	quests.db.wowheadLink, quests.hoveredQuest = true, nil
	Menu, GetLocale, ns.ShowEditWindow = savedMenu, savedLocale, savedEdit
	print("wowhead link OK")
end)()
;(function()
	-- unspent talent points: the currencies of the active tree, shown on the micro button
	local talents = ns:GetModule("Talents")
	local savedCT, savedTraits = C_ClassTalents, C_Traits
	C_ClassTalents = { GetActiveConfigID = function() return 7 end }
	C_Traits = { GetConfigInfo = function() return { treeIDs = { 3 } } end,
		GetTreeCurrencyInfo = function(configID, treeID) return configID == 7 and treeID == 3 and { { quantity = 2 }, { quantity = -1 } } or {} end }
	assert(talents.UnspentPoints() == 2, "unspent points " .. talents.UnspentPoints())
	PlayerSpellsMicroButton = CreateFrame("Button")
	talents.db.unspentBadge = true
	talents.UpdateUnspent()
	assert(talents.unspentBadge and talents.unspentBadge:IsShown() == true, "badge shown")
	C_Traits.GetTreeCurrencyInfo = function() return { { quantity = 0 } } end
	talents.UpdateUnspent()
	assert(talents.unspentBadge:IsShown() ~= true, "badge hidden without points")
	C_ClassTalents = { GetActiveConfigID = function() return nil end }
	assert(talents.UnspentPoints() == 0, "no tree, no points")
	C_ClassTalents, C_Traits, PlayerSpellsMicroButton = savedCT, savedTraits, nil
	print("unspent talents OK")
end)()
;(function()
	-- a sort only leaves a trace: marked junk is not moved (the game's cleanup would put it back)
	local items = ns:GetModule("Items")
	local onSort = uv(uv(items.OnLogin, "QueueSort") and items.OnLogin, "OnSortStarted")
	Enum.ItemQuality.Poor = 0
	items.db.junkPerCharacter = false
	items.db.junk = { [500] = true, [501] = true }
	local picked, savedPickup = 0, C_Container.PickupContainerItem
	C_Container.PickupContainerItem = function() picked = picked + 1 end
	local before = #items.trace
	onSort()
	C_Container.PickupContainerItem = savedPickup
	assert(picked == 0 and #items.trace == math.min(before + 1, 80), "only traced")
	assert(uv(onSort, "PlacingStep") == nil, "no placing left")
	print("junk placement OK")
end)()
;(function()
	-- real popup list with value column, quality border, stripes and sums
	C_Item.GetItemQualityColor = function() return 0, 0.44, 0.87 end
	local ok, err = pcall(realPopup, nil, function()
		return {
			title = "Beute", width = 460, striped = true,
			items = {
				{ text = "Gegenstände (2)" },
				{ text = "[Test] x1", icon = 1, quality = 3, right = "1g", onClick = function() end },
				{ text = "[Grau] x2", icon = 2, quality = 0, right = "-", onClick = function() end },
				{ text = "Geld" },
				{ text = "Quelle", right = "5s", onClick = function() end },
			},
			totals = { { "Händlerwert", "1g" }, { "Geld", "5s" }, { "Gesamt", "1g 5s", true } },
		}
	end, "TestLoot")
	assert(ok, tostring(err))
	print("loot popup OK")
end)()
;(function()
	-- dialog bubble: views and rendering
	local dialog = ns:GetModule("Dialog")
	dialog.db.enabled = true
	issecretvalue = function() return false end
	UnitName = function() return "Torwächter" end
	UnitExists = function() return false end
	InCombatLockdown = function() return false end
	C_GossipInfo = {
		GetText = function() return "Seid gegrüßt, Reisender." end,
		GetOptions = function() return { { gossipOptionID = 5, name = "Ich möchte reisen.", icon = 1 } } end,
		GetActiveQuests = function() return { { title = "Fertig", questID = 1, isComplete = true } } end,
		GetAvailableQuests = function() return { { title = "Neu", questID = 2 } } end,
	}
	local view = dialog.GossipView()
	assert(view.name == "Torwächter" and #view.blocks == 2 and #view.blocks[2].rows == 3, "gossip view rows " .. tostring(view.name) .. " " .. #view.blocks)
	GetTitleText = function() return "Die Jagd" end
	GetQuestText = function() return "Erlegt zehn Eber." end
	GetObjectiveText = function() return "Tötet 10 Eber." end
	GetProgressText = function() return "Habt Ihr sie?" end
	GetRewardText = function() return "Gut gemacht." end
	GetNumQuestChoices = function() return 2 end
	GetNumQuestRewards = function() return 1 end
	GetNumQuestItems = function() return 1 end
	GetQuestItemInfo = function() return "Ding", 134400, 2, 2 end
	GetRewardMoney = function() return 250 end
	GetRewardXP = function() return 100 end
	GetQuestMoneyToGet = function() return 0 end
	IsQuestCompletable = function() return true end
	QuestFlagsPVP = function() return false end
	QuestGetAutoAccept = function() return false end
	C_Item.GetItemQualityColor = function() return 0, 1, 0 end
	for event in pairs({ GOSSIP_SHOW = 1, QUEST_DETAIL = 1, QUEST_PROGRESS = 1, QUEST_COMPLETE = 1 }) do
		local ok, err = pcall(dialog.OnConversation, dialog, event)
		assert(ok, event .. ": " .. tostring(err))
	end
	-- back: gossip first, then a quest detail; "back" shows the gossip step again
	dialog:OnConversation("GOSSIP_SHOW")
	local bubble = ForeverPlusDialogBubble
	local rows = bubble.pools.row
	assert(rows[1].Glow and not rows[2].Glow and not rows[1].Qty and not rows[2].Qty,
		"fresh gossip rows only create the selected glow and no quantity fields")
	bubble.selectedRow = 2
	dialog.Rerender()
	assert(not rows[1].Glow[1]:IsShown() and rows[2].Glow[1]:IsShown(), "selection moves the glow")
	local active = uv(dialog.Rerender, "current").view.blocks[2].rows[2]
	active.counter = 2
	dialog.Rerender()
	local quantity = rows[2].Qty
	assert(quantity and quantity:IsShown(), "a row creates its quantity field when needed")
	active.counter = nil
	dialog.Rerender()
	assert(rows[2].Qty == quantity and not quantity:IsShown(), "a reused row hides the quantity field")
	dialog:OnConversation("QUEST_DETAIL")
	assert(pcall(dialog.GoBack), "back runs")
	GetQuestID = function() return 77 end
	assert(pcall(dialog.OnConversation, dialog, "QUEST_PROGRESS"), "progress with abandon")
	assert(pcall(dialog.AbandonQuest, 77), "abandon runs")
	local reward = dialog.RewardView()
	assert(#reward.buttons == 2 and reward.blocks[3].choose, "reward choice")
	-- A long reward page must survive clicks, late item data, and a repeated event for that quest.
	local savedHeight, savedBest, savedReward, savedQuestID =
		bubble.pools.text[2].GetStringHeight, ns.BestQuestChoice, GetQuestReward, GetQuestID
	local refreshReward, claimed
	bubble.pools.text[2].GetStringHeight = function() return 260 end
	ns.BestQuestChoice = function(onLoaded) refreshReward = onLoaded end
	GetQuestReward = function(choice) claimed = choice end
	dialog:OnConversation("QUEST_COMPLETE")
	bubble:Show() -- the harness does not create a nameplate for the quest giver
	bubble:GetScript("OnMouseWheel")(bubble, -20)
	local offset = bubble.Scroll:GetVerticalScroll()
	assert(offset > 0, "long reward page scrolls")
	local choice = bubble.pools.item[2]
	choice:GetScript("OnClick")(choice)
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "choosing keeps the rewards in view")
	refreshReward()
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "late item data preserves position")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == offset, "reopening the same reward page keeps the choice")
	uv(dialog.Rerender, "current").view.buttons[1].action()
	assert(claimed == 2, "completing the refreshed quest hands in with the selected reward")
	GetQuestID = function() return 78 end
	dialog:OnConversation("QUEST_COMPLETE")
	assert(not choice.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() == 0, "a different quest starts fresh")
	bubble.pools.text[2].GetStringHeight, ns.BestQuestChoice, GetQuestReward, GetQuestID =
		savedHeight, savedBest, savedReward, savedQuestID
	dialog.db.style = "DARK"
	assert(pcall(dialog.OnConversation, dialog, "QUEST_DETAIL"), "dark style")
	dialog.db.enabled = false
	print("dialog OK")
end)()
;(function()
	-- Voiced lines stay compact after completion, even in voice-only mode.
	local dialog = ns:GetModule("Dialog")
	local blocks = { { title = "Die Jagd" }, { text = "Worte", speech = true }, { text = "Ziel", objective = true },
		{ text = "Noch nicht", dim = true }, { rows = {} }, { items = {} }, { money = "5s" } }
	local kept = dialog.WithoutWords(blocks)
	assert(#kept == 4 and kept[1].dim and kept[2].rows and kept[3].items and kept[4].money, "title, words and objective dropped")
	assert(#blocks == 7, "the view's own blocks stay whole")
	local saved = _G.Spoken
	local clip, notifyAudio, notifyStopped, paused
	_G.Spoken = {
		IsCompatible = function() return true end,
		ShowsNarratorFor = function() return false end, -- "voice only"
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil and not paused end,
		IsPaused = function() return paused == true end,
		RegisterCallback = function(_, event, fn)
			if event == "AUDIO_CHANGED" then
				assert(not notifyAudio, "subscribe once to playback changes")
				notifyAudio = fn
			elseif event == "CLIP_STOPPED" then
				notifyStopped = fn
			end
		end,
	}
	local wasExists, wasEnabled, wasPortrait, savedDraw = UnitExists, dialog.db.enabled, dialog.db.portrait, SetPortraitTexture
	local faceUnit
	SetPortraitTexture = function(_, unit) faceUnit = unit end
	UnitExists = function(unit) return unit == "npc" end
	UnitGUID = function() return "Creature-0-0-0-0-1-0" end
	UnitName = function() return "Torwächter" end
	issecretvalue = function() return false end
	InCombatLockdown = function() return false end
	C_GossipInfo = {
		GetText = function() return "Seid gegrüßt, Reisender." end,
		GetOptions = function() return { { gossipOptionID = 5, name = "Ich möchte reisen.", icon = 1 } } end,
		GetActiveQuests = function() return { { title = "Fertig", questID = 1, isComplete = true } } end,
		GetAvailableQuests = function() return { { title = "Neu", questID = 2 } } end,
	}
	dialog.db.enabled, dialog.db.portrait = true, true
	dialog:OnConversation("GOSSIP_SHOW")
	local bubble = ForeverPlusDialogBubble
	assert(not bubble.Portrait:IsShown() and bubble.lastUsed.text == 2, "the words remain while no clip is playing")
	clip = { source = { key = "gossip" }, text = "Different dialogue.", unitGUID = UnitGUID("npc") }
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "an unrelated voiceover keeps the text visible")
	clip.text = C_GossipInfo.GetText()
	notifyAudio()
	assert(bubble.Portrait:IsShown() and faceUnit == "npc", "voice-only playback shows the speaker's face")
	assert(bubble.lastUsed.text == 0 and bubble.lastUsed.row == 3, "the three choices stay visible")
	paused = true
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and bubble.lastUsed.text == 2, "a paused clip leaves the words visible")
	paused = false
	clip.textOnly = true
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "a silent clip without a narrator does not replace the words")
	clip.textOnly = false
	dialog.db.portrait = false
	notifyAudio()
	assert(not bubble.Portrait:IsShown(), "option off: full bubble")
	dialog.db.portrait = true
	UnitExists = function(unit) return unit == "questnpc" end
	dialog:OnConversation("QUEST_COMPLETE")
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText(), unitGUID = UnitGUID("questnpc") }
	notifyAudio()
	assert(bubble.Portrait:IsShown() and faceUnit == "questnpc" and bubble.lastUsed.item == 3, "quest portrait preserves rewards")
	local item = bubble.pools.item[2]
	item:GetScript("OnClick")(item)
	local height = bubble.pools.text[2].GetStringHeight
	bubble.pools.text[2].GetStringHeight = function() return 260 end
	notifyStopped(clip, true)
	clip = nil
	notifyAudio()
	assert(bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.wordsHidden,
		"completed speech stays hidden and preserves the selected reward")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.wordsHidden,
		"refreshing the same reward page does not restore completed speech")
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText() }
	notifyStopped(clip, false)
	clip = nil
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and item.Chosen:IsShown() and bubble.Scroll:GetVerticalScroll() > 0,
		"interrupted speech remains readable and the selected reward stays in view")
	bubble.pools.text[2].GetStringHeight = height
	UnitExists = function() return false end
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetRewardText() }
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and bubble.wordsHidden, "a missing portrait does not repeat spoken words")
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	UnitExists, SetPortraitTexture = wasExists, savedDraw
	_G.Spoken = saved
	print("dialog portrait OK")
end)()
;(function()
	-- Resolve automatic speech before drawing, including delayed and failed starts.
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedReader, savedAfter = _G.Spoken, _G.VoiceOver, C_Timer.After
	local savedGossip, savedExists, savedGUID = C_GossipInfo, UnitExists, UnitGUID
	local wasEnabled, wasPortrait = dialog.db.enabled, dialog.db.portrait
	local clip, queue, startup, lookup, autoplay, available = nil, {}, nil, 0, true, true
	local lineText = "Diese Zeile kommt gleich."
	local callbacks = {}
	local guid = "Creature-0-1-1-1-1-1"
	local function Voice(text)
		return { source = { key = "gossip" }, text = text or C_GossipInfo.GetText(), unitGUID = guid }
	end
	_G.Spoken = {
		GetNowPlaying = function() return clip end,
		GetQueue = function() return queue end,
		IsPlaying = function() return clip ~= nil end,
		RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
	}
	_G.VoiceOver = { Addon = {
		IsAutoplayOn = function() return autoplay end,
		GetVisibleLine = function(_, event)
			lookup = lookup + 1
			if event == "QUEST_COMPLETE" then
				return { text = GetRewardText(), questID = GetQuestID(), unitGUID = guid }
			end
			assert(event == "GOSSIP_SHOW")
			return available and Voice() or nil
		end,
	} }
	C_Timer.After = function(delay, fn) if delay == 1.5 then startup = fn end end
	UnitExists = function(unit) return unit == "npc" end
	UnitGUID = function() return guid end
	C_GossipInfo = {
		GetText = function() return lineText end,
		GetOptions = function() return { { name = "Weiter.", gossipOptionID = 11 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
	}
	dialog.db.enabled, dialog.db.portrait = true, true
	dialog:OnConversation("GOSSIP_SHOW")
	local frame = ForeverPlusDialogBubble
	assert(frame.wordsHidden and frame.lastUsed.row == 1 and startup, "no text flash before automatic speech")
	dialog.Rerender()
	assert(lookup == 1, "recording lookup runs once per page")
	queue = { Voice() }
	startup()
	assert(frame.wordsHidden, "a queued line remains hidden beyond the startup timeout")
	clip = Voice("Eine andere Zeile.")
	callbacks.AUDIO_CHANGED()
	assert(frame.wordsHidden, "another playing line does not reveal the queued page")
	queue = {}
	clip = Voice()
	callbacks.AUDIO_CHANGED()
	callbacks.CLIP_STOPPED(clip, true)
	clip = nil
	callbacks.AUDIO_CHANGED()
	assert(frame.wordsHidden and frame.lastUsed.row == 1, "no text returns after successful playback")
	dialog:OnConversation("GOSSIP_SHOW")
	assert(frame.wordsHidden and lookup == 1, "a duplicate gossip event does not repeat completed speech")
	available = false
	lineText = "Eine andere Seite ohne Aufnahme."
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not frame.wordsHidden and frame.lastUsed.text == 2, "a missing recording remains readable immediately")
	available, autoplay = true, false
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not frame.wordsHidden, "autoplay off keeps the text readable")
	autoplay = true
	dialog:OnConversation("GOSSIP_SHOW")
	startup()
	assert(not frame.wordsHidden, "a resolved recording that never starts falls back to text")
	dialog:OnConversation("GOSSIP_SHOW")
	callbacks.CLIP_DROPPED(Voice(), "missing")
	callbacks.AUDIO_CHANGED()
	assert(not frame.wordsHidden, "a dropped recording restores text immediately")
	dialog:OnConversation("QUEST_COMPLETE")
	local rewardStartup = startup
	assert(frame.wordsHidden, "a resolved quest recording is hidden before starting")
	dialog:OnConversation("QUEST_COMPLETE")
	rewardStartup()
	assert(not frame.wordsHidden, "refreshing a reward page does not leave its startup timeout stuck")
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	_G.Spoken, _G.VoiceOver, C_Timer.After = savedSpoken, savedReader, savedAfter
	C_GossipInfo, UnitExists, UnitGUID = savedGossip, savedExists, savedGUID
	print("dialog voice lifecycle OK")
end)()
;(function()
	-- Small book button in portrait mode: toggles the NPC's words below the face,
	-- analogous to unvoiced bubbles (including textSpeed reveal and scroll layout).
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedExists, savedGUID = _G.Spoken, UnitExists, UnitGUID
	local savedGossip = C_GossipInfo
	local wasEnabled, wasPortrait = dialog.db.enabled, dialog.db.portrait
	local wasPortraitText, wasSpeed = dialog.db.portraitText, dialog.db.textSpeed
	local clip, notifyAudio
	_G.Spoken = {
		IsCompatible = function() return true end,
		ShowsNarratorFor = function() return false end,
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil end,
		IsPaused = function() return false end,
		RegisterCallback = function(_, event, fn)
			if event == "AUDIO_CHANGED" then notifyAudio = fn end
		end,
	}
	local guid = "Creature-0-1-1-1-9-1"
	UnitExists = function(unit) return unit == "npc" or unit == "questnpc" end
	UnitGUID = function() return guid end
	C_GossipInfo = {
		GetText = function() return "Willkommen in Sturmwind, Abenteurer." end,
		GetOptions = function() return { { gossipOptionID = 7, name = "Zeigt mir den Weg.", icon = 1 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
	}
	dialog.db.enabled, dialog.db.portrait, dialog.db.portraitText, dialog.db.textSpeed = true, true, false, "INSTANT"
	local bubble = ForeverPlusDialogBubble
	local scrollPoint, bookDesat
	local origScrollSetPoint = rawget(bubble.Scroll, "SetPoint")
	local origIconDesat = rawget(bubble.TextToggle.Icon, "SetDesaturated")
	bubble.Scroll.SetPoint = function(_, ...) scrollPoint = { ... } end
	bubble.TextToggle.Icon.SetDesaturated = function(_, v) bookDesat = v end
	-- Without Spoken clip: text is already shown, portrait and book button stay hidden.
	dialog:OnConversation("GOSSIP_SHOW")
	assert(not bubble.Portrait:IsShown() and not bubble.TextToggle:IsShown(), "no book button without voice")
	assert(not bubble.wordsHidden and bubble.lastUsed.text == 2, "unvoiced bubble shows name and speech")
	-- Spoken starts reading: portrait and book button appear, text hidden by default.
	clip = { source = { key = "gossip" }, text = C_GossipInfo.GetText(), unitGUID = guid }
	notifyAudio()
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown(), "voiced bubble shows portrait and book button")
	assert(bubble.wordsHidden and bubble.lastUsed.text == 0 and bookDesat == true, "text hidden and book grey initially")
	assert(scrollPoint and scrollPoint[5] == -78, "scroll sits directly under the portrait")
	-- Clicking the book button displays the text below the face while keeping the portrait.
	bubble.TextToggle:GetScript("OnClick")(bubble.TextToggle)
	assert(dialog.db.portraitText == true and not bubble.wordsHidden, "book click enables portrait text")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and bookDesat == false,
		"portrait stays visible and book lights up in colour")
	assert(bubble.lastUsed.text == 2 and bubble.lastUsed.row == 1, "name, speech and choice render under the face")
	assert(scrollPoint and scrollPoint[5] == -78, "text area remains anchored under the portrait")
	-- Slow text reveal works on a fresh voiced step with portraitText enabled, analogous to without Spoken.
	dialog.db.textSpeed = "SLOW"
	local speechText
	local text2 = bubble.pools.text[2]
	local origSetText = rawget(text2, "SetText")
	text2.SetText = function(_, t) speechText = t end
	local freshLine = "Dies ist ein neuer gesprochener Satz fuer den Test."
	C_GossipInfo.GetText = function() return freshLine end
	clip = { source = { key = "gossip" }, text = freshLine, unitGUID = guid }
	dialog:OnConversation("GOSSIP_SHOW")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"fresh voiced gossip keeps portrait and shows text when book is active")
	assert(speechText == "", "slow reveal starts empty on fresh step, analogous to unvoiced mode")
	local onUpdate = bubble:GetScript("OnUpdate")
	assert(onUpdate, "slow reveal update is active")
	onUpdate(bubble, 1)
	assert(type(speechText) == "string" and #speechText > 0, "slow reveal advances words below portrait")
	text2.SetText = origSetText
	-- Quest detail also renders title, speech and objectives below the portrait when active.
	dialog.db.textSpeed = "INSTANT"
	clip = { source = { key = "quests" }, questID = GetQuestID(), text = GetQuestText(), unitGUID = guid }
	dialog:OnConversation("QUEST_DETAIL")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"quest detail keeps portrait and shows text when book is active")
	assert(bubble.lastUsed.text >= 3, "quest name, title and speech render below portrait")
	-- Clicking the book button again hides the text, keeping the portrait.
	bubble.TextToggle:GetScript("OnClick")(bubble.TextToggle)
	assert(dialog.db.portraitText == false and bubble.wordsHidden, "second click hides text again")
	assert(bubble.Portrait:IsShown() and bubble.TextToggle:IsShown() and bookDesat == true,
		"portrait remains and book returns to grey")
	-- When Spoken stops (not reading), portrait and book button hide and text returns.
	clip = nil
	notifyAudio()
	assert(not bubble.Portrait:IsShown() and not bubble.TextToggle:IsShown() and not bubble.wordsHidden,
		"book button hides when voice stops")
	bubble.Scroll.SetPoint = origScrollSetPoint
	bubble.TextToggle.Icon.SetDesaturated = origIconDesat
	dialog.db.enabled, dialog.db.portrait = wasEnabled, wasPortrait
	dialog.db.portraitText, dialog.db.textSpeed = wasPortraitText, wasSpeed
	_G.Spoken, UnitExists, UnitGUID, C_GossipInfo = savedSpoken, savedExists, savedGUID, savedGossip
	print("dialog portrait text book OK")
end)()
;(function()
	-- Exercise the narrator renderer contract and bounded asynchronous model loading.
	local portrait, saved = ns.DialogPortrait, _G.Spoken
	local holder = { Face = NewFrame("Texture"), Scene = false }
	holder.Face.w, holder.Face.h = 64, 64
	local savedCreate = CreateFrame
	CreateFrame = function(...)
		local frame = savedCreate(...)
		frame.SetSize = function(self, width, height) self.w, self.h = width, height end
		return frame
	end
	local model = NewFrame("DressUpModel")
	local file, acquired, updated, released, animated = nil, 0, 0, 0, 0
	model.GetModelFileID = function() return file end
	model:SetScript("OnUpdate", function() animated = animated + 1 end)
	local renderer = {
		Acquire = function() acquired = acquired + 1 model:Show() return model end,
		Update = function(_, _, spec) updated = updated + 1 assert(spec.creatureID == 1) return file ~= nil end,
		Release = function() released = released + 1 model:Hide() end,
	}
	_G.Spoken = { GetPortraitRenderer = function(_, kind) assert(kind == "model") return renderer end }
	local clip = { present = { portrait = { kind = "model", creatureID = 1 } } }
	local animate = model:GetScript("OnUpdate")
	portrait.Update(holder, clip, true)
	local tick = holder.Scene:GetScript("OnUpdate")
	assert(holder.Scene:GetWidth() == 64 and holder.Scene:GetHeight() == 64,
		"use the entire face viewport instead of cropping the beard in an inscribed square")
	assert(holder.Face:IsShown() and model:GetAlpha() == 0 and not holder.Cover:IsShown(),
		"keep the still portrait while the model loads")
	tick(model, 0.5)
	assert(updated == 1 and model:GetScript("OnUpdate") == animate, "load once and retain the renderer's animation script")
	file = 119563
	tick(model, 0.1)
	model:GetScript("OnUpdate")(model, 0.1)
	assert(not holder.Face:IsShown() and model:GetAlpha() == 1 and animated == 1 and holder.Cover:IsShown(),
		"animate a loaded model with its circular cover above it")
	portrait.Update(holder, clip, true)
	assert(acquired == 1 and updated == 1, "redrawing the same clip does not reload the model")
	portrait.Update(holder, nil, true)
	assert(holder.Face:IsShown() and not model:IsShown() and not holder.Cover:IsShown()
		and not holder.Scene:GetScript("OnUpdate") and released == 1,
		"finishing or pausing releases the model and stops its updates")
	file = nil
	portrait.Update(holder, clip, true)
	holder.Scene:GetScript("OnUpdate")(holder.Scene, 2.1)
	assert(not model:IsShown() and holder.Face:IsShown() and released == 2, "abandon an unloaded model after two seconds")
	portrait.Update(holder, clip, true)
	assert(acquired == 2, "a failed clip is not retried by every redraw")
	local other = { present = clip.present }
	portrait.Update(holder, other, false)
	assert(acquired == 2, "the animation option prevents model acquisition")
	portrait.Update(holder, other, true)
	portrait.Stop(holder)
	assert(not model:IsShown() and not holder.Scene:GetScript("OnUpdate") and released == 3, "closing stops a pending load")
	_G.Spoken, CreateFrame = saved, savedCreate
	print("dialog portrait renderer OK")
end)()
;(function()
	-- Voice-only dialogue keeps choices and only provides subtitles for unread speech.
	local dialog = ns:GetModule("Dialog")
	local savedSpoken, savedCommand, savedCreate = _G.Spoken, SlashCmdList.SPOKEN, CreateFrame
	local savedGUID, savedExists, savedGossip = UnitGUID, UnitExists, C_GossipInfo
	local wasEnabled, wasCinematic = dialog.db.enabled, dialog.db.cinematic
	local guid = "Creature-0-1-1-1-1-1"
	local clip, selected, modelCreated
	local callbacks = {}
	local style = "subtitle"
	_G.Spoken = {
		GetPlayerStyle = function() return style end,
		GetNowPlaying = function() return clip end,
		IsPlaying = function() return clip ~= nil end,
		RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
	}
	SlashCmdList.SPOKEN = function(command)
		assert(command == "style voice" or command == "style subtitles", command)
		style = command == "style voice" and "none" or "subtitle"
	end
	CreateFrame = function(kind, name, ...)
		if kind == "DressUpModel" or kind == "PlayerModel" or kind == "ModelScene" or kind == "Model" then
			modelCreated = true
		end
		return savedCreate(kind, name, ...)
	end
	UnitExists = function(unit) return unit == "npc" or unit == "target" end
	UnitGUID = function(unit) return UnitExists(unit) and guid or nil end
	C_GossipInfo = {
		GetText = function() return "Ein Text ohne Aufnahme." end,
		GetOptions = function() return { { name = "Weiter.", gossipOptionID = 17 } } end,
		GetActiveQuests = function() return {} end,
		GetAvailableQuests = function() return {} end,
		SelectOption = function(id) selected = id end,
	}
	dialog.db.enabled, dialog.db.cinematic = true, true
	dialog:Apply()
	dialog:OnConversation("GOSSIP_SHOW")
	local frame = ForeverPlusDialogBubble
	assert(style == "none" and frame:IsShown() and not frame.Dark:IsShown() and not frame.Portrait:IsShown(),
		"voice only and floating controls without a nameplate or bubble")
	assert(frame.Subtitles:IsShown() and frame.Subtitles.text:find(C_GossipInfo.GetText(), 1, true),
		"unvoiced text stays visible in a separate subtitle")
	assert(frame.pools.row[1].ButtonBack:IsShown() and #frame.rowActions == 1, "the dialogue choice is a separate button")
	local voice = { source = { key = "gossip" }, unitGUID = guid, text = C_GossipInfo.GetText(),
		present = { portrait = { kind = "model", displayID = 123 } } }
	clip = voice
	callbacks.AUDIO_CHANGED()
	assert(not frame.Subtitles:IsShown() and frame.pools.row[1]:IsShown(), "while speaking, only the choices remain")
	clip = nil
	callbacks.AUDIO_CHANGED()
	assert(frame.Subtitles:IsShown(), "an interrupted voice restores the unread text")
	clip = voice
	callbacks.AUDIO_CHANGED()
	clip = nil
	callbacks.CLIP_STOPPED(voice, true)
	callbacks.AUDIO_CHANGED()
	assert(not frame.Subtitles:IsShown(), "a fully read page keeps only the choices")
	assert(not modelCreated, "dialogue playback never creates a 3D model")
	local row = frame.pools.row[1]
	row:GetScript("OnClick")(row, "LeftButton")
	assert(selected == 17, "the floating button selects the same dialogue option")
	dialog.db.cinematic = false
	dialog:Apply()
	assert(style == "subtitle" and not frame.Subtitles:IsShown() and not frame.pools.row[1].ButtonBack:IsShown(),
		"disabling restores the reader style and ordinary dialogue layout")
	dialog.db.enabled, dialog.db.cinematic = wasEnabled, wasCinematic
	dialog:Apply()
	_G.Spoken, SlashCmdList.SPOKEN, CreateFrame = savedSpoken, savedCommand, savedCreate
	UnitGUID, UnitExists, C_GossipInfo = savedGUID, savedExists, savedGossip
	print("dialog subtitles without 3D models OK")
end)()
;(function()
	-- reputation flash and trivial messages
	local flash = ns:GetModule("RepFlash")
	local ok, err = pcall(flash.Add, flash, "Eisenschmiede", 25)
	assert(ok, tostring(err))
	assert(pcall(flash.Add, flash, "Orgrimmar", -10), "second change merges")
	for index = 1, 5 do
		assert(pcall(flash.Add, flash, "Fraktion" .. index, 10 * index), "more than three lines make pages")
	end
	-- the colour of the numbers: class colour for gains, red for losses
	flash.db.classColor = true
	flash.db.xp = true
	assert(pcall(flash.Add, flash, "Eisenschmiede", 25), "rep in class colour")
	assert(pcall(flash.Add, flash, "EP", 40, "xp"), "xp in class colour")
	local combat = ns:GetModule("CombatText")
	combat.db.enabled = false
	issecretvalue = function() return false end
	UnitCanAttack = function() return true end
	UnitIsUnit = function() return false end
	assert(pcall(combat.Handle, "target", "WOUND", "CRITICAL", 120), "own damage off: nothing happens")
	combat.db.enabled = true
	for _, args in ipairs({ { "target", "WOUND", "CRITICAL", 120 }, { "target", "MISS", "", 0 }, { "player", "WOUND", "", 15 },
		{ "player", "HEAL", "", 30 }, { "party1", "WOUND", "", 5 }, { "player", "ENERGIZE", "", 5 } }) do
		local ok, err = pcall(combat.Handle, unpack(args))
		assert(ok, tostring(err))
	end
	-- options: no thick or shaking crits, colours by name, the place of the target instead of its plate
	combat.db.critBold, combat.db.critShake, combat.db.targetPlate, combat.db.colorCrit = false, false, false, "CLASS"
	assert(pcall(combat.Handle, "target", "WOUND", "CRITICAL", 99), "crit with the options off")
	local items = ns:GetModule("Items")
	assert(items.FreeSlots and items.CheckFull and items.PlayFullSound, "bag full sound functions")
	assert(pcall(items.CheckFull), "bags full check runs")
	combat.db.enabled = false
	local trivial = ns:GetModule("Trivial")
	DRUNK_MESSAGE_SELF1 = "Ihr fühlt Euch ein wenig beschwipst."
	MARKED_AFK = "Ihr seid jetzt AFK."
	trivial:OnLogin()
	local filter = uv(trivial.Apply, "Filter")
	trivial.db.enabled, trivial.db.shown = true, { afk = true }
	issecretvalue = function() return false end
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == true, "rested hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr fühlt Euch ein wenig beschwipst.") == true, "drunk hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == false, "afk kept while off")
	trivial.db.shown.afk = nil
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == true, "afk hidden when on")
	trivial.db.shown.rested = true
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == false, "rested kept when off")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Etwas ganz anderes.") == false, "other lines pass")
	assert(filter(nil, "CHAT_MSG_MONSTER_EMOTE", "%s versucht zu flüchten.") == true, "fleeing emote hidden")
	trivial.db.shown.flee = true
	assert(filter(nil, "CHAT_MSG_MONSTER_EMOTE", "%s versucht zu flüchten.") == false, "fleeing emote kept as exception")
	trivial.db.shown.flee = nil
	print("trivial OK")
end)()
;(function()
	-- durability on the character window
	local dura = ns:GetModule("Durability")
	issecretvalue = function() return false end
	GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 elseif slot == 2 then return 100, 100 end end
	assert(dura.db.threshold == 60, "threshold default 60 %")
	assert(dura.Percent(1) == 50, "half")
	assert(dura.Percent(2) == nil, "full hidden")
	assert(dura.Percent(3) == nil, "no durability")
	GetInventoryItemDurability = function(slot) if slot == 1 then return 70, 100 elseif slot == 2 then return 100, 100 end end
	assert(dura.Percent(1) == nil and not dura.FigureShown(), "70 %: above the threshold, nothing and no figure")
	dura.db.threshold = 80
	assert(dura.Percent(1) == 70 and dura.FigureShown(), "below a higher threshold: number and figure")
	dura.db.threshold = 60
	dura.db.showFull = true
	assert(dura.Percent(1) == 70 and dura.Percent(2) == 100 and dura.FigureShown(), "everything with the option")
	dura.db.showFull = false
	GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 elseif slot == 2 then return 100, 100 end end
	assert(pcall(dura.Update), "update runs")
	assert(dura.Raw(2) == 100 and dura.Raw(3) == nil, "raw percent")
	-- pet food
	local helpers = ns:GetModule("Helpers")
	assert(helpers.db.feedPet == true, "feed pet default")
	print("durability OK")
end)()
;(function()
	-- talent plan summary and the suggested distributions
	local lines, other = ns.TalentSummary.Build({
		"Erhöht Eure Chance, einen kritischen Treffer zu erzielen, um 3%.",
		"Erhöht die Chance auf kritische Treffer um 2%. Erhöht Eure Bewegungsgeschwindigkeit um 3%.",
		"Erhöht Eure Ausdauer um 10. Verringert die Abklingzeit um 15 Sek.",
	}, true)
	local text = {}
	for _, line in ipairs(lines) do text[#text + 1] = line.text end
	assert(table.concat(text, "|") == "+5 % Kritische Trefferchance|+3 % Bewegungsgeschwindigkeit|+10 Ausdauer", table.concat(text, "|"))
	assert(other == 1, "the cooldown sentence is only counted: " .. other)
	lines = ns.TalentSummary.Build({ "Increases your attack speed by 5%. Reduces threat caused by 10%." }, false)
	assert(#lines == 2 and lines[1].text == "+5 % Attack speed" and lines[2].text == "-10 % Threat", lines[1].text .. " / " .. lines[#lines].text)
	local gain = ns.TalentSummary.RankGain
	local weights = { STA = 1.5, DODGE = 12, DEF = 1.5 }
	assert(gain("Increases your Defense Skill by 4.", "Increases your Defense Skill by 8.", weights, {}, false) == 6,
		"score the next rank's increase")
	assert(gain(nil, "Erhöht Eure Ausdauer um 2%.", weights, { STA = 76 }, true) == 76 * 0.02 * 1.5,
		"estimate a percentage of the current attribute")
	local ret = upvalue(getW, "WEIGHTS").PALADIN[3]
	local stats = { INT = 100, STR = 100 }
	local intellectGain = gain("Increases your total Intellect by 2%.", "Increases your total Intellect by 4%.", ret, stats, false)
	assert(intellectGain == 2 * ret.INT and intellectGain > gain(nil, "Increases your Strength by 2%.", ret, stats, false),
		"recognize Divine Intellect and compare it with Divine Strength using the Retribution weights")
	assert(gain("Erhöht Eure gesamte Intelligenz um 2%.", "Erhöht deine gesamte Intelligenz um 4%.", ret, stats, true) == intellectGain
		and gain(nil, "Erhöht deine Stärke um 2%.", ret, stats, true) == 2 * ret.STR,
		"recognize the localized direct attribute bonuses")
	assert(gain(nil, "Increases your chance to dodge by an additional 2%.", weights, {}, false) == 24,
		"score a change in chance in percentage points")
	assert(gain(nil, "Increases your Parry chance by 1%.", { PARRY = 9 }, {}, false) == 9,
		"recognize the parry talent's description")
	local healer = { SP = 0.85, HEAL = 1, HASTE = 2, SHASTE = 6, SCRIT = 7 }
	assert(gain(nil, "Increases your spell power by 10.", healer, {}, false) == 10,
		"generic spell power has the same value in talents and in gear")
	assert(gain(nil, "Increases your melee attack speed by 2%.", healer, {}, false) == 4
		and gain(nil, "Erhöht Euer Zaubertempo um 2%.", healer, {}, true) == 12,
		"keep explicitly melee and spell haste talents separate")
	assert(gain(nil, "Erhöht Eure kritische Trefferchance mit allen Zaubern und Angriffen um 2%.", healer, {}, true) == 14,
		"use the profile's spell crit weight for a shared crit talent")
	assert(gain(nil, "Improves your chance to get a critical strike with all spells and attacks by 1%.", healer, {}, false) == 7,
		"recognize the shared crit talent's English description")
	assert(not gain(nil, "Increases your chance to dodge by 2% for 10 sec.", weights, {}, false)
		and not gain(nil, "Increases your Stamina by 2% while in Bear Form.", weights, { STA = 76 }, false),
		"temporary and conditional effects are outside the item model")
	local classes = 0
	for class, builds in pairs(ns.TalentPresets) do
		classes = classes + 1
		assert(#builds >= 4, class .. " has at least three standards and one special")
		for _, build in ipairs(builds) do
			local points, count = 0, 0
			for rank in build.ranks:gmatch("%d+:(%d+)") do points, count = points + tonumber(rank), count + 1 end
			assert(points == 51 and count > 10, class .. " " .. build.en .. " " .. points)
		end
	end
	assert(classes == 9, "all nine classes")
	local retPreset = ns.TalentPresets.PALADIN[3]
	local retRanks = ns.TalentBuilds.ParseRanks(retPreset.ranks)
	assert(retPreset.points == "12/8/31" and retRanks[105332] == 5 and retRanks[105638] == 3
		and retRanks[113630] == 5 and retRanks[105334] == 5 and retRanks[105704] == 2,
		"use the simulated Retribution secondary talents in Holy and Protection")
	print("talent summary and presets OK")
end)()
;(function()
	local tp = ns:GetModule("Teleports")
	IsPlayerSpell = function(id) return id == 18960 or id == 10059 end
	C_Item.GetItemCount = function(id) return id == 6948 and 1 or 0 end
	C_Item.GetItemNameByID = function(id) return "Item" .. id end
	C_Item.GetItemIconByID = function() return 1 end
	C_Container.GetItemCooldown = function() return 0, 0, 1 end
	C_Spell.GetSpellName = function(id) return "Spell" .. id end
	C_Spell.GetSpellTexture = function() return 2 end
	C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
	tp.db.portals = true
	local list = tp:Collect()
	assert(#list == 3 and list[1].hearth and list[2].id == 18960 and list[3].portal, "teleports found")
	tp.db.portals = false
	assert(#tp:Collect() == 2, "portals optional")
	tp.db.portals = true
	InCombatLockdown = function() return false end
	GetBindLocation = function() return "Orgrimmar" end
	local ok, err = pcall(tp.ShowMenu, tp) assert(ok, tostring(err))
	print("teleports OK")
end)()
;(function()
	local items = ns:GetModule("Items")
	local built, original = nil, ns.ShowPopupList
	ns.ShowPopupList = function(_, build) built = build() end
	items:ShowBagMenu({})
	ns.ShowPopupList = original
	assert(built and #built.items > 8, "bag menu items")
	local toggle
	for _, item in ipairs(built.items) do
		if item.checked ~= nil and item.text == ns.L.ITEMS_AUTOSORT then toggle = item end
	end
	assert(toggle, "autoSort entry")
	local before = items.db.autoSort
	toggle.onClick()
	assert(items.db.autoSort == not before, "toggle flips option")
	toggle.onClick()
	print("bag menu OK")
end)()
;(function()
	SKILL_RANK_UP = "Eure Fertigkeit '%s' hat sich auf %d erhöht."
	FACTION_STANDING_INCREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert."
	FACTION_STANDING_DECREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verschlechtert."
	ERR_LEARN_SPELL_S = "Ihr habt den Zauber %s erlernt."
	ERR_LEARN_ABILITY_S = "Ihr habt die Fähigkeit %s erlernt."
	ERR_LEARN_PASSIVE_S = "Ihr habt den passiven Zauber %s erlernt."
	local chunk = assert(loadfile(root .. "/Modules/Chat.lua"))
	ns.modules.Chat = nil
	chunk("ForeverPlus", ns)
	local chat = ns.modules.Chat
	chat.db = { repeatSummary = true, repeatDelay = 30 }
	local filter = uv(chat.UpdateRepeatSummary, "RepeatFilter")
	local flush = uv(filter, "FlushRepeat")
	local pending = uv(filter, "repeatPending")
	local timers = {}
	C_Timer.NewTimer = function(_, fn) local t = { Cancel = function(self) self.cancelled = true end, fn = fn } timers[#timers + 1] = t return t end
	ChatTypeInfo = { SKILL = { r = 0.3, g = 0.3, b = 1, id = 9 }, COMBAT_FACTION_CHANGE = { r = 0.5, g = 0.5, b = 1, id = 10 } }
	local out = {}
	local frameA = { AddMessage = function(_, t) out[#out + 1] = "A:" .. t end }
	local frameB = { AddMessage = function(_, t) out[#out + 1] = "B:" .. t end }
	local now = 0
	GetTime = function() return now end
	for rank = 4, 11 do
		now = now + 10
		assert(filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Kürschnerei' hat sich auf %d erhöht."):format(rank)) == true)
		filter(frameB, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Kürschnerei' hat sich auf %d erhöht."):format(rank))
	end
	for i = 1, 3 do
		now = now + 1
		filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Eisenschmiede' hat sich um 25 verbessert.")
	end
	assert(filter(frameA, "CHAT_MSG_SAY", "hallo") == false)
	for key in pairs(pending) do flush(key) end
	table.sort(out)
	for _, l in ipairs(out) do print("  ", l) end
	assert(#out == 3, "three lines")
	print("repeat summary OK")
	-- skills combined into one line
	chat.db.skillLine = true
	out = {}
	for rank = 31, 40 do filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Verteidigung' hat sich auf %d erhöht."):format(rank)) end
	for rank = 34, 36 do filter(frameA, "CHAT_MSG_SKILL", ("Eure Fertigkeit 'Äxte' hat sich auf %d erhöht."):format(rank)) end
	for key in pairs(pending) do flush(key) end
	assert(#out == 1 and out[1] == "A:" .. ns.L.CHAT_SKILL_LINE_TEXT:format("Verteidigung 30->40, Äxte 33->36"), out[1])
	print("skill line OK")
	-- reputation and new spells in one line each
	chat.db.repLine, chat.db.learnLine = true, true
	out = {}
	for i = 1, 3 do filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Eisenschmiede' hat sich um 25 verbessert.") end
	filter(frameA, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Euer Ruf bei der Fraktion 'Orgrimmar' hat sich um 10 verschlechtert.")
	assert(ns.ParseReputationMessage("Euer Ruf bei der Fraktion 'Orgrimmar' hat sich um 10 verschlechtert.") == "Orgrimmar", "rep parse")
	assert(filter(frameA, "CHAT_MSG_SYSTEM", "Ihr habt den Zauber |Hspell:133|h[Feuerball]|h erlernt.") == true, "learn caught")
	filter(frameA, "CHAT_MSG_SYSTEM", "Ihr habt die Fähigkeit |Hspell:116|h[Frostblitz]|h erlernt.")
	assert(filter(frameA, "CHAT_MSG_SYSTEM", "Etwas anderes.") == false, "other system lines pass")
	for key in pairs(pending) do flush(key) end
	table.sort(out)
	assert(#out == 2, "two lines: " .. #out)
	assert(out[1] == "A:Eisenschmiede +75, Orgrimmar -10", out[1])
	assert(out[2] == "A:" .. ns.L.CHAT_LEARN_LINE:format("|Hspell:133|h[Feuerball]|h, |Hspell:116|h[Frostblitz]|h"), out[2])
	print("rep and learn lines OK")
end)()
;(function()
	local q = ns:GetModule("Quests")
	local markLog
	-- hooksecurefunc in the harness may not keep the function; find it via OnLogin upvalues
	markLog = uv(q.OnLogin, "MarkQuestLog")
	q.db.foreverMark, q.db.foreverMarkStyle = true, "ICON"
	local function fs(t) return { t = t, GetText = function(self) return self.t end, SetText = function(self, v) self.t = v end, SetTextColor = function(self, r) self.r = r end } end
	local a, b = { questID = 99160, Text = fs("Neue Quest") }, { questID = 783, Text = fs("Alte Quest") }
	QuestScrollFrame = { titleFramePool = { EnumerateActive = function() local l, i = { a, b }, 0 return function() i = i + 1 return l[i] end end } }
	markLog()
	markLog()
	print("  marks", a.Text.t, "|", b.Text.t)
	assert(a.Text.t:find("auctionhouse%-icon%-favorite") and select(2, a.Text.t:gsub("favorite", "")) == 1 and b.Text.t == "Alte Quest", "icon mark once")
	q.db.foreverMarkStyle = "COLOR"
	a.HookScript = function() end
	markLog()
	assert(a.Text.r ~= nil and not b.Text.r, "color mark")
	print("forever marks OK")
end)()
;(function()
	-- World map: unexplored parts from the data, explored and mismatching maps skipped.
	local wm = ns:GetModule("WorldMap")
	-- Shipped data: every part has the tiles its size needs (256 pixel tiles).
	local parts = 0
	for art, raw in pairs(ns.MapOverlays) do
		for part in raw:gmatch("[^;]+") do
			local n = {}
			for number in part:gmatch("-?%d+") do n[#n + 1] = tonumber(number) end
			assert(#n - 4 == math.ceil(n[1] / 256) * math.ceil(n[2] / 256), "tiles of a part in art " .. art)
			parts = parts + 1
		end
	end
	print("  map data", ns.MapOverlayBuild, parts, "parts")
	local made = {}
	local function NewTexture(layer, sub)
		local t = { layer = layer, sub = sub, shown = true }
		function t:SetSize(w, h) self.w, self.h = w, h end
		function t:SetTexCoord(...) self.coord = { ... } end
		function t:ClearAllPoints() end
		function t:SetPoint(point, x, y) self.point, self.x, self.y = point, x, y end
		function t:SetTexture(file, _, _, filter) self.file, self.filter = file, filter end
		function t:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
		function t:SetAlpha(a) self.alpha = a end
		function t:Show() self.shown = true end
		function t:Hide() self.shown = false end
		made[#made + 1] = t
		return t
	end
	local layerIndex = 1
	local map = { GetMapID = function() return 1429 end, IsShown = function() return true end,
		GetCanvasContainer = function() return { GetCurrentLayerIndex = function() return layerIndex end } end }
	local pin = { GetMap = function() return map end, RefreshOverlays = function() end, RemoveAllData = function() end,
		CreateTexture = function(_, _, layer, _, sub) return NewTexture(layer, sub) end }
	WorldMapFrame.EnumeratePinsByTemplate = function(_, template)
		assert(template == "MapExplorationPinTemplate")
		local done
		return function() if not done then done = true return pin end end
	end
	WorldMapFrame.GetMapID = function() return 1429 end
	WorldMapFrame.GetCanvas = function() return CreateFrame("Frame") end
	WorldMapFrame.GetCanvasScale = function() return 1 end
	ns.MapOverlays, ns.MapOverlayBuild = { [15] = "300,200,10,20,1001,1002;100,100,400,5,2001;300,300,0,0,3001" }, "test"
	local explored = { { fileDataIDs = { 2001 } }, { fileDataIDs = {} } }
	C_Map.GetMapArtID = function(id) return id == 1429 and 15 or nil end
	C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end
	C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end }
	local function shown()
		local list = {}
		for _, t in ipairs(made) do if t.shown then list[#list + 1] = t end end
		return list
	end
	wm.db.reveal, wm.db.revealAlpha, wm.db.revealTint = true, 60, true
	wm:Apply()
	local list = shown()
	-- 300 x 200 in two tiles; the explored part and the one with a missing tile are left out.
	assert(#list == 2, "two tiles, got " .. #list)
	local a, b = list[1], list[2]
	assert(a.layer == "ARTWORK" and a.sub == -1, "below Blizzard's parts")
	assert(a.file == 1001 and a.w == 256 and a.h == 200 and a.x == 10 and a.y == -20, "first tile")
	assert(a.coord[2] == 1 and a.coord[4] == 200 / 256, "first tile coords")
	assert(b.file == 1002 and b.w == 44 and b.x == 266 and b.coord[2] == 44 / 64, "edge tile")
	assert(a.alpha == 0.6 and a.r == 0.75 and a.g == 1 and a.filter == "TRILINEAR", "faded and tinted")
	wm.db.revealTint = false
	wm:OnOptionChanged("revealTint", false)
	assert(#shown() == 2 and shown()[1].r == 1 and #made == 2, "untinted, textures reused")
	-- a colour of one's own from Blizzard's colour picker, on the map at once; Cancel restores
	local info
	local picked = { r = 1, g = 0.5, b = 0, a = 0.8 }
	ColorPickerFrame = { SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return picked.r, picked.g, picked.b end, GetColorAlpha = function() return picked.a end }
	wm.ChooseTint()
	assert(info.r == 0.75 and info.g == 1 and info.b == 0.75 and info.opacity == 0.6 and info.hasOpacity, "starts at the current colour and opacity")
	info.swatchFunc()
	local t = shown()[1]
	assert(wm.db.revealTint and wm.db.revealAlpha == 80 and t.r == 1 and t.g == 0.5 and t.b == 0 and t.alpha == 0.8 and #made == 2,
		"the chosen colour turns the tint on and shows without drawing again")
	info.cancelFunc()
	t = shown()[1]
	assert(not wm.db.revealTint and wm.db.revealAlpha == 60 and t.r == 1 and t.g == 1 and t.alpha == 0.6, "cancel restores")
	wm.ChooseTint()
	info.swatchFunc()
	wm:Apply()
	assert(shown()[1].g == 0.5 and wm.db.revealColor.r == 1, "kept and used when drawn again")
	picked.a = 0.02
	info.opacityFunc()
	assert(wm.db.revealAlpha == 10, "opacity at least 10 %")
	wm.db.revealColor = { r = "x", g = 2 }
	local r, g, b = wm.TintColor(wm.db)
	assert(r == 0.75 and g == 1 and b == 0.75, "damaged colour: defaults, values clamped")
	wm.db.revealColor = nil
	assert(select(3, wm.TintColor(wm.db)) == 0.75 and wm.TintColor({ revealTint = false }) == 1, "missing colour: green; tint off: white")
	wm.db.revealColor, wm.db.revealAlpha, wm.db.revealTint = { r = 0.75, g = 1, b = 0.75 }, 60, false
	explored = { { fileDataIDs = { 2001 } }, { fileDataIDs = { 9999 } } }
	wm:Apply()
	assert(#shown() == 0, "unknown explored part: map left alone")
	explored = {}
	layerIndex = 2
	wm:Apply()
	assert(#shown() == 0, "other art layer")
	layerIndex = 1
	wm:Apply()
	assert(#shown() == 3, "nothing explored: all complete parts")
	wm.db.reveal = false
	wm:OnOptionChanged("reveal", false)
	assert(#shown() == 0, "switched off")
	local printed = {}
	local printAlways = ns.PrintAlways
	ns.PrintAlways = function(msg, ...) printed[#printed + 1] = msg:format(...) end
	wm:PrintStatus()
	C_Map.GetMapArtID = function() return 99 end
	wm:PrintStatus()
	ns.PrintAlways = printAlways
	for _, line in ipairs(printed) do print("  ", line) end
	assert(#printed == 4 and printed[1]:find("1429") and printed[2]:find("0") and printed[3]:find("test"), "status lines")
	print("world map OK")
end)()
;(function()
	-- Talent planner in Blizzard's window: right-click plans, Shift + right-click removes, classic rules.
	local talents = ns:GetModule("Talents")
	talents.db.enabled, talents.db.planner = true, true
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	assert(onClick, "planner click handler")
	GameTooltip = { GetOwner = function() return nil end }
	do
	local plannerButtons = {}
	PlayerSpellsFrame = { TalentsFrame = { GetConfigID = function() return 1 end, EnumerateAllTalentButtons = function() return pairs(plannerButtons) end } }
	PlayerUtil = { GetCurrentSpecID = function() return 1 end }
	C_Traits = { GetNodeInfo = function() return { maxRanks = 3, ranksPurchased = 0 } end }
	IsShiftKeyDown = function() return false end
	IsControlKeyDown = function() return false end
	local btn = { GetNodeID = function() return 77 end, CanRefundRank = function() return false end }
	plannerButtons[btn] = true
	onClick(nil, btn, "RightButton"); onClick(nil, btn, "RightButton")
	local plan = uv(onClick, "CurrentPlan")()
	assert(plan[77] == 2, "planned 2 ranks")
	IsShiftKeyDown = function() return true end
	onClick(nil, btn, "RightButton")
	assert(plan[77] == 1, "shift removes")
	-- Tooltip shows the planned rank
	plan[77] = 3
	local lines = {}
	GameTooltip = { GetOwner = function() return btn end, Show = function() end }
	GameTooltip_AddBlankLineToTooltip = function() end
	GameTooltip_AddHighlightLine = function(_, text) lines[#lines + 1] = text end
	C_Traits.GetTraitDescription = function(entryID, rank) return "GetTraitEntry:" .. entryID .. ":" .. rank end
	GameTooltip_AddColoredLine = function(_, text) lines[#lines + 1] = text end
	C_Traits.GetNodeInfo = function() return { maxRanks = 3, ranksPurchased = 1, activeEntry = { entryID = 500, rank = 1 } } end
	uv(uv(uv(onClick, "RefreshTooltip"), "HookPlanTooltip"), "AddPlanTooltip")(btn)
	print("  plan tooltip", table.concat(lines, " | "))
	assert(lines[#lines] == "GetTraitEntry:500:3", "planned rank values")
	-- Row rule and arrows: node 2 in row 2 needs 5 points, node 3 needs node 1 at full rank
	local plan2 = uv(onClick, "CurrentPlan")()
	for k in pairs(plan2) do plan2[k] = nil end
	local defs = {
		[1] = { ID = 1, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = { { targetNode = 3, type = Enum.TraitEdgeType.RequiredForAvailability } } },
		[2] = { ID = 2, posY = 200, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {} },
		[3] = { ID = 3, posY = 100, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {} },
	}
	C_Traits.GetNodeInfo = function(_, id) local d = defs[id] local c = {} for k, v in pairs(d) do c[k] = v end return c end
	for k in pairs(plannerButtons) do plannerButtons[k] = nil end
	local bs = {}
	for id = 1, 3 do bs[id] = { GetNodeID = function() return id end, CanRefundRank = function() return false end, GetName = function() return "T" .. id end } plannerButtons[bs[id]] = true end
	IsShiftKeyDown = function() return false end
	local printed
	local oldPrint = ns.Print
	ns.Print = function(msg) printed = msg end
	talents:QueuePlanUpdate() -- another tree: in the game its events ask for a new reading
	onClick(nil, bs[3], "RightButton")
	assert(not plan2[3], "row 1 needs 5 points")
	-- the restriction shows in the tooltip of that talent, in the colour of the plan
	lines = {}
	GameTooltip = { GetOwner = function() return bs[3] end, Show = function() end }
	uv(uv(uv(onClick, "RefreshTooltip"), "HookPlanTooltip"), "AddPlanTooltip")(bs[3])
	print("  restriction tooltip", table.concat(lines, " | "))
	assert(#lines >= 1 and lines[#lines]:find("Plan:") and lines[#lines]:find("5"), "restriction in the tooltip")
	for _ = 1, 4 do onClick(nil, bs[1], "RightButton") end
	onClick(nil, bs[3], "RightButton")
	assert(not plan2[3], "needs node 1 at full rank / 5 points")
	onClick(nil, bs[1], "RightButton")
	onClick(nil, bs[3], "RightButton")
	assert(plan2[3] == 1, "row 1 unlocked with 5 points and arrow source maxed")
	IsShiftKeyDown = function() return true end
	onClick(nil, bs[1], "RightButton")
	assert(plan2[1] == 5, "removal blocked while node 3 depends on it")
	ns.Print = oldPrint
	print("  planner rules ok, last message:", printed)
	print("planner OK")
	end
end)()
;(function()
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local buildList, active = uv(menu, "BuildList"), uv(menu, "ActiveBuild")
	local key = uv(buildList, "PlanKey")()
	local class = key:match("^[^:]+")
	local list, original = buildList(), active()
	local savedCount, savedSeq, savedActive = #list, talents.db.buildSeq, talents.cdb.activeBuild[key]
	local savedNext = talents.db.planNext
	local savedFrame, savedTraits, savedSpell, savedLocale, savedStat = PlayerSpellsFrame, C_Traits, C_Spell, GetLocale, UnitStat
	local savedWeights, savedPresets, savedPrint, savedMenu = ns.StatWeights, ns.TalentPresets, ns.Print, MenuUtil.CreateContextMenu
	talents.db.planNext = false
	local buttons, defs = {}, {}
	local function Add(id, tree, row, column, maxRanks, learned)
		defs[id] = { ID = id, posX = tree * 1000 + column * 50, posY = row * 100, maxRanks = maxRanks,
			ranksPurchased = learned or 0, entryIDs = { id }, groupIDs = { tree } }
		local button = CreateFrame("Button")
		button.GetNodeID = function() return id end
		button.GetName = function() return "Talent " .. id end
		buttons[button] = true
	end
	local preset = {}
	for row = 0, 5 do
		Add(11 + row, 2, row, row % 3, 5)
		preset[#preset + 1] = (11 + row) .. ":5"
	end
	for row = 0, 3 do
		Add(1 + row, 1, row, row % 3, 5)
		preset[#preset + 1] = (1 + row) .. ":5"
	end
	Add(17, 2, 6, 0, 1)
	preset[#preset + 1] = "17:1"
	defs[11].visibleEdges = { { targetNode = 17, type = Enum.TraitEdgeType.RequiredForAvailability } }
	Add(18, 2, 0, 1, 5)
	Add(19, 2, 1, 2, 5)
	Add(31, 3, 0, 0, 2, 2)
	Add(32, 3, 0, 0, 5)
	defs[32].isVisible, defs[32].posX, defs[32].posY = false, 102800, -100
	defs[17].posX = 9000
	ns.TalentPresets = { [class] = {
		{ de = "Andere", en = "Other", points = "", ranks = "" },
		{ de = "Schutz", en = "Protection", points = "20/31/0", ranks = table.concat(preset, ",") },
		{ de = "Dritter Baum", en = "Third tree", points = "", ranks = "" },
		{ de = "Bär", en = "Bear", points = "20/31/0", ranks = table.concat(preset, ","):gsub("12:5", "19:5") },
	} }
	PlayerSpellsFrame = { TalentsFrame = {
		GetConfigID = function() return 1 end, IsVisible = function() return true end,
		EnumerateAllTalentButtons = function() return pairs(buttons) end,
	} }
	C_Traits = {
		GetConfigInfo = function() return { treeIDs = { 1117 } } end,
		GetGroupDisplayInfoByTreeID = function()
			return { { groupID = 3, orderIndex = 3 }, { groupID = 1, orderIndex = 1 }, { groupID = 2, orderIndex = 2 } }
		end,
		GetNodeInfo = function(_, id) return CopyTable(defs[id]) end,
		GetEntryInfo = function(_, id) return { definitionID = id } end,
		GetDefinitionInfo = function(id) return { spellID = id } end,
		GetTraitDescription = function(id, rank)
			if id == 11 or id == 12 then return ("Increases your Defense Skill by %d."):format(rank * 4) end
			if id == 18 or id == 19 then return ("Increases your chance to dodge by %d%%."):format(rank) end
			return "Grants a new ability."
		end,
	}
	C_Spell = { IsSpellPassive = function(id) return id ~= 17 end }
	GetLocale = function() return "enUS" end
	UnitStat = function() return 50, 50 end
	local weights = { DODGE = 12, DEF = 1.5 }
	ns.StatWeights = function() return weights, "Protection", 2 end
	ns.Print = function() end
	MenuUtil.CreateContextMenu = function(owner, generate)
		generate(owner, {
			CreateTitle = function() end, CreateRadio = function() end, CreateDivider = function() end,
			CreateButton = function(_, title, action) if title == ns.L.TALENTS_RECOMMEND then action() end end,
		})
	end
	talents:QueuePlanUpdate()
	menu({})
	local build = active()
	assert(build ~= original and ns.TalentBuilds.Points(build) == 51 and #build.order == 49 and build.ranks[31] == 2,
		"create a full plan with earned points included, leaving the original plan intact")
	assert(build.ranks[17] == 1 and build.ranks[11] == 5 and not build.ranks[18],
		"keep the unscored capstone and its required talent")
	assert(build.ranks[19] == 5 and not build.ranks[12], "prefer the higher-scoring eligible alternative in the same row")
	local replay = { [31] = 2 }
	for _, id in ipairs(build.order) do
		local node, above = defs[id], 0
		for previous, rank in pairs(replay) do
			if defs[previous].groupIDs[1] == node.groupIDs[1] and defs[previous].posY < node.posY then
				above = above + rank
			end
		end
		assert(above >= node.posY / 100 * 5 and (id ~= 17 or replay[11] == 5), "every step can be learned in order")
		replay[id] = (replay[id] or 0) + 1
		assert(replay[id] <= node.maxRanks, "respect the talent rank cap")
	end
	weights = { DEF = 1.5 }
	menu({})
	assert(active().ranks[12] == 5 and not active().ranks[19] and build.ranks[19] == 5,
		"changing the gear weights changes the recommended allocation")
	defs[31].ranksPurchased = 0
	weights = { DODGE = 12, DEF = 1.5 }
	talents:QueuePlanUpdate()
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 51 and active().ranks[17] == 1
		and active().ranks[12] == 5 and not active().ranks[19] and not active().ranks[32],
		"keep the complete tested allocation when learned ranks fit it, regardless of alternative gear gains")
	defs[31].ranksPurchased = 2
	talents:QueuePlanUpdate()
	C_Traits.GetTraitDescription = function() return "Grants a new ability." end
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 49 and active().ranks[17] == 1,
		"complete the plan from the template when no effects are directly scoreable")
	ns.StatWeights = function() return weights, "Bear", 2, 4 end
	menu({})
	assert(ns.TalentBuilds.Points(active()) == 51 and #active().order == 49 and active().ranks[19] == 5
		and not active().ranks[12], "use the selected bear template for the same talent tree")
	for index = #list, savedCount + 1, -1 do list[index] = nil end
	talents.db.buildSeq, talents.cdb.activeBuild[key], talents.db.planNext = savedSeq, savedActive, savedNext
	PlayerSpellsFrame, C_Traits, C_Spell, GetLocale, UnitStat = savedFrame, savedTraits, savedSpell, savedLocale, savedStat
	ns.StatWeights, ns.TalentPresets, ns.Print, MenuUtil.CreateContextMenu = savedWeights, savedPresets, savedPrint, savedMenu
	talents:QueuePlanUpdate()
	print("talent recommendations OK")
end)()
;(function()
	-- Order of the talent plan: steps per point, kept in line with the plan and the rules.
	local order = ns.TalentOrder
	local kept, missing = order.Reconcile({ 1, 1, 2, 1, 3 }, { [1] = 2, [2] = 1, [4] = 2 })
	assert(table.concat(kept, ",") == "1,2,1" and missing[4] == 2 and missing[1] == nil and missing[2] == nil,
		"learned points drop the earliest steps, a talent no longer planned drops all: " .. table.concat(kept, ","))
	local steps = { 1, 2, 1, 3 }
	assert(order.RemoveLast(steps, 1) and table.concat(steps, ",") == "1,2,3" and not order.RemoveLast(steps, 9), "the last step of a talent goes")
	-- talent 3 needs two points in the others first
	local ranks = { [1] = 1 }
	local repaired = order.Repair({ 3, 2, 1, 3 }, function(id, state)
		return id ~= 3 or (state[1] or 0) + (state[2] or 0) >= 2
	end, ranks)
	assert(table.concat(repaired, ",") == "2,3,1,3" and ranks[3] == 2, "first step the rules allow: " .. table.concat(repaired, ","))
	repaired = order.Repair({ 3, 1 }, function(id) return id == 1 end, {})
	assert(table.concat(repaired, ",") == "1,3", "a step nothing unlocks stays at the end")
	local texts = order.LevelTexts({ 1, 1, 1, 2, 1, 3 }, 14)
	assert(texts[1] == "14–16, 18" and texts[2] == "17" and texts[3] == "19" and texts[4] == nil, "levels of the steps: " .. tostring(texts[1]))

	-- In the planner: clicks keep their order, taking a rank back repairs it, "apply" buys in that order.
	local talents = ns:GetModule("Talents")
	talents.db.enabled, talents.db.planner, talents.db.planNext = true, true, true
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	local savedTraits, savedCT, savedSpec, savedSpell = C_Traits, C_ClassTalents, C_SpecializationInfo, C_Spell
	local defs = {
		[1] = { ID = 1, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 501 } },
		[2] = { ID = 2, posY = 0, maxRanks = 5, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 502 } },
		[3] = { ID = 3, posY = 100, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 503 } },
		[4] = { ID = 4, posY = 200, maxRanks = 1, ranksPurchased = 0, groupIDs = { 9 }, visibleEdges = {}, entryIDs = { 504 } },
	}
	local bought, points = {}, 99
	C_Traits = {
		GetNodeInfo = function(_, id) local c = {} for k, v in pairs(defs[id]) do c[k] = v end return c end,
		PurchaseRank = function(_, id)
			if #bought >= points then return false end
			bought[#bought + 1] = id
			return true
		end,
		GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1000 } end,
		GetDefinitionInfo = function(definitionID) return { spellID = definitionID + 1000 } end,
		GetConfigInfo = function() return nil end,
	}
	C_Spell = { GetSpellName = function(spellID) return "Zauber " .. spellID end }
	C_ClassTalents = { GetActiveConfigID = function() return 1 end }
	C_SpecializationInfo = { HasPlayerEarnedATalentPoint = function() return true end }
	InCombatLockdown = function() return false end
	PlayerUtil = { GetCurrentSpecID = function() return 1 end }
	IsControlKeyDown = function() return false end
	local buttons, bs = {}, {}
	for id = 1, 4 do
		bs[id] = { GetNodeID = function() return id end, CanRefundRank = function() return false end, GetName = function() return "T" .. id end }
		buttons[bs[id]] = true
	end
	PlayerSpellsFrame = { TalentsFrame = { GetConfigID = function() return 1 end, EnumerateAllTalentButtons = function() return pairs(buttons) end } }
	GameTooltip = { GetOwner = function() return nil end }
	local plan, stored = uv(onClick, "CurrentPlan")(), uv(onClick, "CurrentOrder")()
	wipe(plan); wipe(stored)
	talents:QueuePlanUpdate()
	local oldPrint = ns.Print
	ns.Print = function() end
	local function Applied()
		bought = {}
		talents:ApplyPlan()
		return table.concat(bought, ",")
	end
	IsShiftKeyDown = function() return false end
	for _ = 1, 5 do onClick(nil, bs[1], "RightButton") end
	onClick(nil, bs[3], "RightButton")
	for _ = 1, 5 do onClick(nil, bs[2], "RightButton") end
	assert(Applied() == "1,1,1,1,1,3,2,2,2,2,2", "the order of the clicks: " .. Applied())
	assert(talents.NextPlanned() == "Zauber 2501", "the next talent of the plan by name: " .. tostring(talents.NextPlanned()))
	-- one rank of the first talent taken back: the talent of the second row has to wait for a fifth point
	IsShiftKeyDown = function() return true end
	onClick(nil, bs[1], "RightButton")
	assert(plan[1] == 4 and Applied() == "1,1,1,1,2,3,2,2,2,2", "repaired after taking a rank back: " .. Applied())
	points = 3
	assert(Applied() == "1,1,1", "as far as the points go")
	points = 99
	-- a plan without steps (template, import, older plan): row by row; learned ranks need no step
	wipe(plan); wipe(stored)
	plan[4], plan[3], plan[2], plan[1] = 1, 1, 5, 5
	defs[1].ranksPurchased = 2
	talents:QueuePlanUpdate()
	assert(Applied() == "1,1,1,2,2,2,2,2,3,4", "derived order: " .. Applied())
	assert(talents.NextPlanned() == "Zauber 2501", "next: the first talent still short of its planned rank")
	defs[1].ranksPurchased = 5
	assert(talents.NextPlanned() == "Zauber 2502", "learned steps are passed over")
	talents.db.planNext = false
	assert(talents.NextPlanned() == nil, "option off: no hint")
	talents.db.planNext = true
	wipe(plan); wipe(stored)
	ns.Print = oldPrint
	C_Traits, C_ClassTalents, C_SpecializationInfo, C_Spell = savedTraits, savedCT, savedSpec, savedSpell
	print("talent plan order OK")
end)()
;(function()
	-- Talent plans by name: the list, what was stored before, and the plan a character works with.
	local builds = ns.TalentBuilds
	local ranks = builds.ParseRanks("11:5,12:2,x,13:0")
	assert(ranks[11] == 5 and ranks[12] == 2 and ranks[13] == 0 and builds.ParseRanks(nil)[1] == nil, "ranks of a stored template")
	local list, counter = {}, {}
	local first = builds.Add(list, counter, "Plan")
	local second = builds.Add(list, counter, "Plan", { [1] = 3, [2] = 1 })
	assert(first.id == 1 and second.id == 2 and second.name == "Plan (2)" and builds.Points(second) == 4 and builds.Points(first) == 0, "ids and names of their own")
	assert(builds.UniqueName(list, "Plan (2)", second) == "Plan (2)" and builds.UniqueName(list, "Plan") == "Plan (3)", "a plan keeps its own name")
	assert(builds.Find(list, 2) == second and builds.Find(list, 9) == nil and builds.Find(list, nil) == nil, "found by id")
	assert(builds.Remove(list, 1) and #list == 1 and not builds.Remove(list, 1) and builds.Add(list, counter, "X").id == 3, "removed; ids are not used again")
	list, counter = {}, { buildSeq = 4 }
	builds.Migrate(list, counter, { [7] = 2 }, { 7, 7 }, { { name = "Tank", points = 3, ranks = "7:1,8:2" }, { name = "leer", ranks = "" }, "kaputt" }, "Plan")
	assert(#list == 2 and list[1].name == "Plan" and list[1].ranks[7] == 2 and #list[1].order == 2 and list[1].id == 5
		and list[2].name == "Tank" and list[2].ranks[8] == 2 and #list[2].order == 0, "the old plan first, then the templates with talents")
	assert(#builds.Migrate({}, {}, {}, nil, nil, "Plan") == 0, "nothing stored: nothing added")

	local talents = ns:GetModule("Talents")
	local onClick = uv(uv(talents.OnLogin, "SetupPlanner"), "OnTalentClick")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local BuildList, ActiveBuild = uv(menu, "BuildList"), uv(menu, "ActiveBuild")
	local key = uv(BuildList, "PlanKey")()
	local savedDB, savedSeq, savedActive = talents.db.builds[key], talents.db.buildSeq, talents.cdb.activeBuild[key]
	local savedPrint, savedEdit, savedMenu, savedLocale = ns.Print, ns.ShowEditWindow, MenuUtil.CreateContextMenu, GetLocale
	ns.Print = function() end
	-- what an older version stored is taken over once, the old plan is the active one
	talents.db.builds[key], talents.cdb.activeBuild[key] = nil, nil
	talents.db.plans, talents.db.planOrder = { [key] = { [7] = 2 } }, { [key] = { 7, 7 } }
	talents.db.templates = { [key:match("^[^:]+")] = { { name = "Tank", ranks = "7:1,8:2" } } }
	assert(#BuildList() == 2 and next(talents.db.plans) == nil and next(talents.db.planOrder) == nil and next(talents.db.templates) == nil, "taken over, the old fields emptied")
	assert(#BuildList() == 2 and talents:CurrentPlan()[7] == 2 and ActiveBuild().name == ns.L.TALENTS_PLAN, "once only; the old plan is active")
	talents.db.plans, talents.db.planOrder, talents.db.templates = nil, nil, nil
	-- menu: the plans as a choice, then what can be done
	local radios, entries = {}, {}
	MenuUtil.CreateContextMenu = function(owner, gen)
		local root = {}
		function root.CreateTitle() end
		function root.CreateDivider() end
		function root.CreateRadio(_, text, isSelected, onSelect) radios[#radios + 1] = { text = text, isSelected = isSelected, onSelect = onSelect } end
		function root.CreateButton(_, text, fn) entries[text] = fn end
		gen(owner, root)
	end
	talents.db.planner = true
	menu({})
	assert(#radios == 2 and radios[1].text == ns.L.TALENTS_PLAN .. " (2)" and radios[2].text == "Tank (3)" and radios[1].isSelected() and not radios[2].isSelected(), "plans with their points, the active one marked")
	radios[2].onSelect()
	assert(ActiveBuild().name == "Tank" and talents:CurrentPlan()[8] == 2 and radios[2].isSelected(), "another plan chosen")
	-- new, rename, save a copy, remove
	local typed
	ns.ShowEditWindow = function(_, _, _, _, onAccept) onAccept(typed) end
	typed = "  Tank "
	entries[ns.L.TALENTS_PLAN_NEW]()
	assert(#BuildList() == 3 and ActiveBuild().name == "Tank (2)" and next(talents:CurrentPlan()) == nil, "a new, empty plan is the active one")
	typed = "Heiler"
	entries[ns.L.TALENTS_PLAN_RENAME]()
	assert(ActiveBuild().name == "Heiler", "renamed")
	typed = ""
	entries[ns.L.TALENTS_PLAN_RENAME]()
	assert(ActiveBuild().name == "Heiler", "no name: the plan keeps its own")
	-- a plan from outside takes the empty active plan, otherwise it becomes a plan of its own
	local StorePlan = uv(uv(menu, "ImportPlan"), "StorePlan")
	StorePlan("Link", { [7] = 1 })
	assert(#BuildList() == 3 and ActiveBuild().name == "Link" and talents:CurrentPlan()[7] == 1, "the empty plan is used")
	StorePlan("Link", { [8] = 1 })
	assert(#BuildList() == 4 and ActiveBuild().name == "Link (2)" and talents:CurrentPlan()[8] == 1 and BuildList()[3].ranks[7] == 1, "beside a plan with talents")
	entries[ns.L.TALENTS_PLAN_REMOVE]()
	assert(#BuildList() == 3 and ActiveBuild().name == ns.L.TALENTS_PLAN, "removed: the first plan is active")
	for _ = 1, 3 do entries[ns.L.TALENTS_PLAN_REMOVE]() end
	assert(#BuildList() == 0 and next(talents:CurrentPlan()) == nil and #BuildList() == 1, "without any plan there is an empty one as soon as it is asked for")
	-- planner off: the menu still exports
	radios, entries = {}, {}
	talents.db.planner = false
	menu({})
	assert(#radios == 0 and entries[ns.L.TALENTS_EXPORT_PLAN] and not entries[ns.L.TALENTS_PLAN_NEW], "planner off: export only")
	talents.db.planner = true
	assert(onClick, "planner reachable")
	talents.db.builds[key], talents.db.buildSeq, talents.cdb.activeBuild[key] = savedDB, savedSeq, savedActive
	ns.Print, ns.ShowEditWindow, MenuUtil.CreateContextMenu, GetLocale = savedPrint, savedEdit, savedMenu, savedLocale
	print("talent plans by name OK")
end)()
;(function()
	-- Time in the finished level: the difference of the level starts (total played time minus time in the level).
	local info = ns:GetModule("Info")
	info.db.levelTime = true
	UnitLevel = function() return 11 end
	SecondsToTime = function(seconds) return tostring(seconds) .. "s" end
	local handler = info.TIME_PLAYED_MSG
	local known = uv(handler, "LevelTimeKnown")
	assert(known, "level time reachable")
	-- level 10 began at 600 s (total 1000, 400 in the level)
	UnitLevel = function() return 10 end
	handler(info, "TIME_PLAYED_MSG", 1000, 400)
	-- level-up to 11: the request arrives with total 2600 and 5 s in the new level
	local index
	for i = 1, 60 do local name = debug.getupvalue(handler, i) if name == "levelPending" then index = i end end
	assert(index, "levelPending upvalue")
	debug.setupvalue(handler, index, { level = 11, at = GetTime() })
	UnitLevel = function() return 11 end
	handler(info, "TIME_PLAYED_MSG", 2600, 5)
	local text = uv(known, "levelText")
	assert(text and text:find("10") and text:find("1995"), "time of level 10: " .. tostring(text))
	print("level time OK")
end)()
;(function()
	-- Trainer in the bubble: affordable services are selectable rows, the rest follows dimmed.
	local dialog = ns:GetModule("Dialog")
	GetNumTrainerServices = function() return 3 end
	GetTrainerServiceInfo = function(i)
		local data = { { "Erste Hilfe", "available", 1, 1, "Lehrling" }, { "Zweiter", "unavailable", 2, 20, "" }, { "Alt", "used", 3, 1, "" } }
		return unpack(data[i])
	end
	GetTrainerServiceCost = function(i) return i == 1 and 100 or 500 end
	GetMoney = function() return 1000 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	UnitLevel = function() return 10 end
	-- recipes: the product of the first is better equipment (arrow), the second only at a higher level (grey arrow)
	local savedLink, savedState = GetTrainerServiceItemLink, ns.RecipeUpgradeState
	GetTrainerServiceItemLink = function(i) return i <= 2 and ("item:" .. (100 + i)) or nil end
	ns.RecipeUpgradeState = function(link) return link == "item:101" or (link == "item:102" and "later") end
	dialog.showLocked = true
	local preview = dialog.TrainerView()
	local previewRows
	for _, block in ipairs(preview.blocks) do if block.rows then previewRows = block.rows end end
	assert(previewRows[1].link == "item:101" and previewRows[1].upgrade == true and previewRows[1].arrowSlot, "recipe row: link and arrow")
	assert(previewRows[2].upgrade == "later", "only the level missing: grey arrow")
	ns:GetModule("ProfessionPlan").db.preview = false
	preview = dialog.TrainerView()
	for _, block in ipairs(preview.blocks) do if block.rows then previewRows = block.rows end end
	assert(not previewRows[1].upgrade, "preview switched off: no arrow")
	ns:GetModule("ProfessionPlan").db.preview = true
	dialog.showLocked = false
	GetTrainerServiceItemLink, ns.RecipeUpgradeState = function() return nil end, savedState
	local view = dialog.TrainerView()
	local rows
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows and #rows == 1 and rows[1].action, "only what can be learned by default")
	assert(view.tools and view.tools.locked == false, "the symbol for later levels is off")
	dialog.showLocked = true
	view = dialog.TrainerView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows and #rows == 2 and rows[1].action and not rows[2].action and rows[2].dim, "available first, locked dimmed, used left out")
	dialog.showLocked = false
	assert(dialog.ToolClickable("locked", false) and dialog.ToolClickable("repair", true) and not dialog.ToolClickable("repair", false), "the switch for locked wares can be clicked while off, a dim repair cannot")
	local alpha, grey = dialog.ToolAppearance("locked", false, false)
	assert(alpha == 0.6 and grey, "locked switch off: grey, not faint")
	alpha, grey = dialog.ToolAppearance("locked", true, false)
	assert(alpha == 1 and not grey, "locked switch on: in colour")
	alpha = dialog.ToolAppearance("repair", false, false)
	assert(alpha == 0.3, "repair without money stays faint")
	assert(view.buttons[2].enabled == false and view.buttons[3].enabled == true, "train needs a selection, train all is possible (button 1 says goodbye)")
	GetTrainerServiceItemLink = savedLink
	-- Try on only with the modifier.
	local savedModified, savedDress, tried = IsModifiedClick, DressUpItemLink, nil
	DressUpItemLink = function(link) tried = link return true end
	IsModifiedClick = function() return false end
	assert(not ns.TryOnRecipe("item:101") and tried == nil, "plain click: no try-on")
	IsModifiedClick = function(kind) return kind == "DRESSUP" end
	assert(ns.TryOnRecipe("item:101") and tried == "item:101", "Ctrl + click tries the product on")
	assert(not ns.TryOnRecipe("spell:5"), "no item: nothing")
	IsModifiedClick, DressUpItemLink = savedModified, savedDress
	print("trainer view OK")
end)()
;(function()
	-- Recipe radar: ticked-off or bagged recipes count as collected; a right click ticks off all a vendor shows.
	local radar = ns:GetModule("RecipeRadar")
	assert(radar.IsCollected(5, { [5] = true }, 0) and radar.IsCollected(6, {}, 1) and not radar.IsCollected(7, {}, 0), "collected by mark or by count")
	local marked = {}
	radar.MarkCollected({ recipes = { { 11, "ok" }, { 12, "low" } } }, marked)
	assert(marked[11] and marked[12], "right click marks every recipe of the vendor")
	local savedLocale = GetLocale
	GetLocale = function() return "deDE" end
	assert(radar.WowheadText({ recipes = { { 11, "ok" }, { 12, "low" } } }) == "https://www.wowhead.com/forever/de/item=11\nhttps://www.wowhead.com/forever/de/item=12", "one Wowhead page per recipe")
	GetLocale = function() return "enUS" end
	assert(ns.WowheadURL("quest", 5) == "https://www.wowhead.com/forever/quest=5", "without a language part in English")
	GetLocale = savedLocale
	-- the world map symbol: click opens the links, Shift + click sets the waypoint
	local click = uv(ns.MapSymbols.AddSource, "sources")
	local symbol
	for _, source in ipairs(click or {}) do
		source(1429, function(_, _, given) if given.kind == "radar" then symbol = given end end)
	end
	if symbol then
		local shown, waypoint
		local savedEdit, savedShift, savedCan = ns.ShowEditWindow, IsShiftKeyDown, C_Map.CanSetUserWaypointOnMap
		ns.ShowEditWindow = function(_, _, text) shown = text end
		C_Map.CanSetUserWaypointOnMap = function() waypoint = true return false end
		IsShiftKeyDown = function() return false end
		symbol.click(symbol, "LeftButton")
		assert(shown and shown:find("item=", 1, true) and not waypoint, "click: Wowhead")
		shown = nil
		IsShiftKeyDown = function() return true end
		symbol.click(symbol, "LeftButton")
		assert(waypoint and not shown, "Shift + click: waypoint")
		ns.ShowEditWindow, IsShiftKeyDown, C_Map.CanSetUserWaypointOnMap = savedEdit, savedShift, savedCan
	else
		print("  (no radar symbol on the test map: click checked by WowheadText only)")
	end
	print("radar collected OK")
end)()
;(function()
	-- Buff reminder for the target: only within reach (false or 0 from the game); unknown or secret keeps it.
	local buffs = ns:GetModule("Buffs")
	assert(buffs.OutOfRange(false) and buffs.OutOfRange(0), "out of reach")
	assert(not buffs.OutOfRange(true) and not buffs.OutOfRange(1) and not buffs.OutOfRange(nil), "within reach or unknown")
	print("buff range OK")
end)()
;(function()
	-- Performance table (60 FPS = 16.7 ms budget): Peak red from 15 ms, orange 5-15 ms; session >5 ms rate 1 / 4 per min.
	local info = ns:GetModule("Info")
	assert(ns.SLOW_MS == 5, "slow from 5 ms")
	assert(info.PeakLevel(4.5, 2) == "green" and info.PeakLevel(5.0, 2) == "orange" and info.PeakLevel(4.5, 3) == "orange", "orange between")
	assert(info.PeakLevel(15.0, 0) == "red" and info.PeakLevel(1, 20) == "red" and info.PeakLevel(12) == "orange", "red only for real spikes")
	assert(info.SlowRateLevel(0, 60) == "green" and info.SlowRateLevel(19, 41 * 60) == "green", "sparse session spikes stay green")
	assert(info.SlowRateLevel(6, 180) == "orange" and info.SlowRateLevel(12, 180) == "red", "dense per-minute spikes turn orange/red")
	assert(info.SlowRateLevel(1, 10) == "orange" and info.SlowRateLevel(4, 10) == "red", "first-minute burst still flags immediately")
	print("cpu colours OK")
end)()
;(function()
	-- Rating: a chosen talent tree wins over the automatic one, if the class has it.
	local items = ns:GetModule("Items")
	assert(items.PickTree(0, 2, 3) == 2 and items.PickTree(3, 2, 3) == 3 and items.PickTree(3, 1, 1) == 1 and items.PickTree(nil, 1, 3) == 1, "chosen or automatic tree")
	local choices = upvalue(getW, "WEIGHTS")
	local profileOptions
	for _, option in ipairs(items.options) do
		if option.key == "scoreSpec" then profileOptions = option.values end
	end
	local savedClass, savedProfile, savedLevel = upvalue(getW, "playerClass"), upvalue(getW, "weights"), UnitLevel
	local savedTraits, savedChoice = C_Traits, items.cdb.scoreSpec
	local state, treeName = upvalue(getW, "weightsTree"), upvalue(getW, "weightsName")
	local preset = upvalue(getW, "weightsPreset")
	local automatic = 0
	C_Traits = {
		GetConfigInfo = function() return { treeIDs = { 77 } } end,
		GetGroupDisplayInfoByTreeID = function() return { trees[3], trees[1], trees[2] } end,
		GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 10 + automatic, currencyInfos = { { spent = 5 } } } } end,
	}
	UnitLevel = function() return 60 end
	for class, profiles in pairs(choices) do
		setuv(getW, "playerClass", class)
		assert(#profiles == 3 and #profileOptions() == (class == "DRUID" and 5 or 4), "each tree is selectable for " .. class)
		assert(profiles[1] ~= profiles[2] and profiles[2] ~= profiles[3] and profiles[1] ~= profiles[3], "one profile per " .. class .. " tree")
		for index = 1, 3 do
			automatic = index
			items.cdb.scoreSpec = 0
			setuv(getW, "weights", nil)
			local weights, _, tree, plan = ns.StatWeights()
			assert(weights == profiles[index] and tree == index and plan == index, "automatic profile for " .. class)
			local override = index % 3 + 1
			items.cdb.scoreSpec = override
			setuv(getW, "weights", nil)
			weights, _, tree, plan = ns.StatWeights()
			assert(weights == profiles[override] and tree == override and plan == override, "explicit profile for " .. class)
		end
	end
	assert(choices.MAGE[1].INT > choices.MAGE[3].INT and choices.HUNTER[3].DPS > choices.HUNTER[1].DPS
		and choices.SHAMAN[2].STR > choices.SHAMAN[2].INT, "key Forever specialization differences")
	setuv(getW, "playerClass", "DRUID")
	setuv(getW, "weights", nil)
	items.cdb.scoreSpec = 4
	local bear, _, bearTree, bearPlan = ns.StatWeights()
	assert(bear.STA > choices.DRUID[2].STA and bear.ARMOR > choices.DRUID[2].ARMOR and bearTree == 2 and bearPlan == 4,
		"bear shares the feral tree and uses its own template")
	setuv(getW, "playerClass", savedClass)
	setuv(getW, "weights", savedProfile)
	setuv(getW, "weightsTree", state)
	setuv(getW, "weightsName", treeName)
	setuv(getW, "weightsPreset", preset)
	C_Traits, UnitLevel, items.cdb.scoreSpec = savedTraits, savedLevel, savedChoice
	print("score tree OK")
end)()
;(function()
	-- Books: plain text becomes one paragraph (the game takes fonts only per tag), HTML stays.
	local R = ns:GetModule("Readable")
	assert(R.AsHTML("a < b & c\nd") == "<html><body><p>a &lt; b &amp; c<br/>d</p></body></html>", R.AsHTML("a < b & c\nd"))
	assert(R.AsHTML(" <HTML><body>x</body></HTML>") == " <HTML><body>x</body></HTML>", "HTML unchanged")
	print("readable plain text OK")
end)()
;(function()
	-- Settings: a module listed with chosen keys shows only those; every option with a key must be on some page.
	local listed, keyed = {}, {}
	for _, page in ipairs(ns.SettingsPages) do
		for _, entry in ipairs(page) do
			local name = entry[1]
			if entry.keys then
				keyed[name] = keyed[name] or {}
				for key in pairs(entry.keys) do keyed[name][key] = true end
			else
				listed[name] = true
			end
		end
	end
	local missing = {}
	for name, keys in pairs(keyed) do
		if not listed[name] then
			local module = ns:GetModule(name)
			local options = type(module.options) == "function" and module:options() or module.options or {}
			for _, opt in ipairs(options) do
				if opt.key and opt.type ~= "header" and opt.type ~= "button" and not keys[opt.key] then
					missing[#missing + 1] = name .. "." .. opt.key
				end
			end
		end
	end
	table.sort(missing)
	assert(#missing == 0, "options on no settings page: " .. table.concat(missing, ", "))
	print("settings pages OK")
end)()
;(function()
	-- Merchant list in columns: whole rows only, a thin bar for the position, groups for long lists.
	local dialog = ns:GetModule("Dialog")
	assert(dialog.ListVisible(100, 19) == 100, "a short list shows whole")
	assert(dialog.ListVisible(40 * 19 - 3, 19) == 8 * 19 - 3, "a long list shows only whole rows (8 of 19 points in 150)")
	local top, height = dialog.ScrollThumb(0, 400, 100)
	assert(top == 0 and height == 25, "thumb at the top, as tall as the visible share")
	top = dialog.ScrollThumb(300, 400, 100)
	assert(top == 75, "thumb at the bottom at the end of the list")
	assert(dialog.ScrollThumb(0, 50, 100) == 0, "nothing to scroll")
	local grouped = dialog.GroupWares({ { k = "a" }, { k = "b" }, { k = "a" } }, function(e) return e.k, "H" .. e.k end)
	assert(#grouped == 5 and grouped[1].header == "Ha" and grouped[3].k == "a" and grouped[4].header == "Hb",
		"groups in the order first met, merchant's order kept inside")
	local single = { { k = "a" }, { k = "a" } }
	assert(dialog.GroupWares(single, function(e) return e.k, "H" end) == single, "one group: no heading")
	local saved = { GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair,
		GetNumBuybackItems, ns.MerchantTools, C_Item.GetItemInfoInstant, rawget(_G, "INVTYPE_CHEST"), rawget(_G, "INVTYPE_HAND"),
		dialog.db.merchantGroups, ns.RewardComparisonState }
	ns.MerchantTools, ns.RewardComparisonState = nil, nil
	GetMerchantNumItems = function() return 10 end
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = 10, stackCount = 1, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantItemLink = function(i) return "item:" .. i end
	C_Item.GetItemInfoInstant = function(link)
		local i = tonumber(link:match("%d+"))
		return i, nil, nil, i % 2 == 0 and "INVTYPE_HAND" or "INVTYPE_ROBE", nil, 4
	end
	INVTYPE_CHEST, INVTYPE_HAND = "Brust", "Hände"
	GetMoney = function() return 1000 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	dialog.db.merchantGroups = true
	local function Rows()
		for _, block in ipairs(dialog.MerchantView().blocks) do if block.rows then return block.rows end end
	end
	local rows = Rows()
	assert(#rows == 12 and rows[1].header == "Brust" and rows[7].header == "Hände", "robe counts as chest, two headings")
	assert(rows[2].number == 1 and rows[2].text:find("Ware1", 1, true) and rows[8].number == 6 and rows[8].text:find("Ware2", 1, true),
		"key numbers follow the wares as shown, headings have none")
	assert(rows[1].action == nil and rows[1].number == nil, "a heading is no ware")
	dialog.db.merchantGroups = false
	rows = Rows()
	assert(#rows == 10 and not rows[1].header, "option off: no groups")
	dialog.db.merchantGroups = true
	GetMerchantNumItems = function() return 8 end
	rows = Rows()
	assert(#rows == 8 and not rows[1].header, "a short list stays without groups")
	-- Drawn: no error, the chosen row has the warm background and keeps the size of the others.
	GetMerchantNumItems = function() return 10 end
	local wasOn, wasMerchant = dialog.db.enabled, dialog.db.merchant
	dialog.db.enabled, dialog.db.merchant, dialog.reported = true, true, nil
	dialog:OnConversation("MERCHANT_SHOW")
	for line = math.max(1, #ns.db.bubbleTrace - 15), #ns.db.bubbleTrace do
		assert(not ns.db.bubbleTrace[line]:find(ns.L.DIALOG_TRACE_DRAW_ERROR:format(""), 1, true), ns.db.bubbleTrace[line])
	end
	local bubble = uv(dialog.Rerender, "bubble")
	local drawn = bubble.pools.row
	assert(drawn[2].Selected:IsShown() and not drawn[3].Selected:IsShown() and not drawn[1].Selected:IsShown(),
		"the first ware is lit, not the heading")
	assert(drawn[2]:GetHeight() == drawn[3]:GetHeight() and drawn[1]:GetHeight() == drawn[2]:GetHeight(), "all rows one height")
	assert(drawn[2].Num:IsShown() and drawn[2].Price:IsShown() and not drawn[1].Num:IsShown() and not drawn[1].Price:IsShown(),
		"wares show number and price, the heading neither")
	-- The basket gets a fixed line even when empty. Model wrapping when the price outgrows its line.
	local basket = bubble.pools.text[bubble.lastUsed.text - 2]
	local buy = bubble.pools.button[2]
	local setHeight, setPoint = rawget(bubble, "SetHeight"), rawget(buy, "SetPoint")
	bubble.SetHeight = function(self, height) self.testHeight = height end
	buy.SetPoint = function(self, _, _, _, _, y) self.testY = y end
	local priceWidth, basketText, basketWidth, wraps, lineHeight = 0
	basket.SetWidth = function(_, width) basketWidth = width end
	basket.SetText = function(_, text) basketText = text end
	basket.SetHeight = function(_, height) lineHeight = height end
	basket.SetWordWrap = function(_, value) wraps = value end
	basket.GetStringHeight = function() return wraps and priceWidth > basketWidth and 24 or 12 end
	basket.IsTruncated = function() return priceWidth > basketWidth end
	local coinPrice = "2 |TSilver:14:14|t 25 |TCopper:14:14|t"
	GetMoneyString = function(copper) return copper == 50 and coinPrice or tostring(copper) .. "c" end
	dialog:OnConversation("MERCHANT_UPDATE")
	local height, buttonY = bubble.testHeight, buy.testY
	assert(basketText == "" and height and buttonY, "the empty basket has its own line above the buttons")
	priceWidth = 100
	drawn[2].action("LeftButton")
	assert(basketText == ns.L.DIALOG_MERCHANT_CHOSEN:format(1, "10c"), "the selected ware appears in the basket")
	assert(bubble.testHeight == height and buy.testY == buttonY, "selecting a ware keeps the layout")
	priceWidth = 180
	drawn[2].onQuantity(5)
	assert(basketText == ns.L.DIALOG_MERCHANT_CHOSEN:format(5, coinPrice) and priceWidth <= basketWidth and not wraps
		and lineHeight >= 14, "the total and both coin icons fit on their own line")
	assert(bubble.testHeight == height and buy.testY == buttonY, "adding a denomination keeps the layout")
	priceWidth = 500
	drawn[2].onQuantity(99)
	assert(bubble.testHeight == height and buy.testY == buttonY, "an overflowing total keeps the layout")
	assert(bubble.BasketOverflow:IsShown() and bubble.BasketOverflow.total == basketText, "the tooltip has the full total")
	priceWidth = 0
	drawn[2].onQuantity(0)
	assert(basketText == "" and bubble.testHeight == height and buy.testY == buttonY and not bubble.BasketOverflow:IsShown(),
		"emptying the basket keeps the layout and removes the tooltip")
	basket.SetWidth, basket.SetText, basket.SetHeight, basket.SetWordWrap, basket.GetStringHeight, basket.IsTruncated =
		nil, nil, nil, nil, nil, nil
	bubble.SetHeight, buy.SetPoint = setHeight, setPoint
	dialog.db.enabled, dialog.db.merchant = wasOn, wasMerchant
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair, GetNumBuybackItems,
		ns.MerchantTools, C_Item.GetItemInfoInstant, INVTYPE_CHEST, INVTYPE_HAND, dialog.db.merchantGroups, ns.RewardComparisonState = unpack(saved, 1, 13)
	print("merchant columns OK")
end)()
;(function()
	-- Switching the thin line on grey items with the combined bag never opened: size without buttons.
	local saved = ContainerFrameCombinedBags
	local function Empty(_, index) index = index + 1 if index <= 2 then return index, nil end end
	ContainerFrameCombinedBags = { IsShown = function() return true end, EnumerateValidItems = function(self) return Empty, self, 0 end }
	local ok, err = pcall(ns:GetModule("Visuals").OnOptionChanged, ns:GetModule("Visuals"), "bagActionFrame")
	ContainerFrameCombinedBags = saved
	assert(ok, err)
	print("bag frame refresh OK")
end)()
;(function()
	-- Merchant in the bubble: rows with prices, Buy needs a selection that can be paid; keys: Tab moves the light.
	local dialog = ns:GetModule("Dialog")
	local tools = ns.MerchantTools
	ns.MerchantTools = nil
	GetMerchantNumItems = function() return 2 end
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = i * 100, stackCount = 1, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantItemLink = function() return nil end
	GetMoney = function() return 150 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	local view = dialog.MerchantView()
	local rows
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	-- Name and price in columns of their own; a price above the player's money is red.
	assert(rows and #rows == 2 and rows[1].text:find("Ware1", 1, true) and not rows[1].text:find("100c", 1, true)
		and rows[1].price == "100c" and rows[2].price == "|cffff4040200c|r", "two wares, prices in their own column")
	local listBlock
	for _, block in ipairs(view.blocks) do if block.rows then listBlock = block end end
	assert(listBlock.columns, "the merchant list is drawn in columns")
	local money, keys = view.blocks[#view.blocks - 1], view.blocks[#view.blocks]
	assert(money.money == "" and money.right == ns.L.DIALOG_MONEY:format("150c"), "money at the right, no basket at the left")
	assert(keys.text == ns.L.DIALOG_MERCHANT_KEYS and keys.small, "what the mouse does in one small line below")
	assert(view.buttons[2].enabled == false, "nothing selected: no purchase")
	-- The whole list is drawn and scrolls in the bubble (no pages of 14): every ware, the list marked to scroll.
	local many = GetMerchantNumItems
	GetMerchantNumItems = function() return 40 end
	local long = dialog.MerchantView()
	for _, block in ipairs(long.blocks) do if block.rows then assert(#block.rows == 40 and block.scroll, "all 40 wares, scrolling") end end
	local wasOn, wasMerchant = dialog.db.enabled, dialog.db.merchant
	dialog.db.enabled, dialog.db.merchant, dialog.reported = true, true, nil
	dialog:OnConversation("MERCHANT_SHOW")
	dialog.db.enabled, dialog.db.merchant = wasOn, wasMerchant
	local drawn
	local drawPattern = ns.L.DIALOG_TRACE_DRAWN:format(-1, -1, 40, -1):gsub("%-1", "%%d+")
	for line = math.max(1, #ns.db.bubbleTrace - 15), #ns.db.bubbleTrace do
		assert(not ns.db.bubbleTrace[line]:find(ns.L.DIALOG_TRACE_DRAW_ERROR:format(""), 1, true), ns.db.bubbleTrace[line])
		drawn = drawn or ns.db.bubbleTrace[line]:find(drawPattern)
	end
	assert(drawn and not dialog.reported, "the long list draws: " .. table.concat(ns.db.bubbleTrace, "\n", math.max(1, #ns.db.bubbleTrace - 15)))
	GetMerchantNumItems = many
	assert(dialog.ListOffset(30, nil, nil, 150) == 30, "stays where it was scrolled")
	assert(dialog.ListOffset(30, 10, 16, 150) == 10, "lit row above: up to it")
	assert(dialog.ListOffset(0, 200, 16, 150) == 66, "lit row below: just into view")
	assert(dialog.ListOffset(30, 60, 16, 150) == 30, "lit row in view: no move")
	-- A ware in the basket: Space and the number keys never buy (they are jump and action bar); the button does,
	-- and the basket is empty afterwards.
	rows[1].action("LeftButton")
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	assert(rows[1].picked and view.buttons[2].enabled and view.buttons[2].spends, "picked ware can be bought, button marked as spending")
	local bought = {}
	BuyMerchantItem = function(index, quantity) bought[#bought + 1] = index .. "x" .. quantity end
	GetMerchantItemMaxStack = function() return 20 end
	local bubble = uv(dialog.Rerender, "bubble")
	local current = uv(dialog.Rerender, "current")
	if bubble and bubble.scripts and bubble.scripts.OnKeyDown and current then
		local saved = current.view
		current.view = view
		bubble.scripts.OnKeyDown(bubble, "SPACE")
		bubble.scripts.OnKeyDown(bubble, "1")
		current.view = saved
		assert(#bought == 0, "keys do not buy")
	end
	view.buttons[2].action()
	assert(bought[1] == "1x1" and #bought == 1, "button buys once: " .. table.concat(bought, ","))
	view = dialog.MerchantView()
	assert(view.buttons[2].enabled == false, "basket empty after buying")
	-- A pack of 200: quantity 2 means two packs, 400 items, bought pack by pack.
	local savedMerchant = C_MerchantFrame
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Pfeil", texture = 1, price = 10, stackCount = 200, numAvailable = -1, isPurchasable = true, isUsable = true } end }
	GetMerchantNumItems = function() return 1 end
	GetMoney = function() return 150 end
	local savedShift = IsShiftKeyDown
	IsShiftKeyDown = function() return false end
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	rows[1].action("LeftButton")
	view = dialog.MerchantView()
	for _, block in ipairs(view.blocks) do if block.rows then rows = block.rows end end
	rows[1].action("LeftButton") -- counts up to 2
	view = dialog.MerchantView()
	wipe(bought)
	view.buttons[2].action()
	assert(#bought == 2 and bought[1] == "1x200" and bought[2] == "1x200", "two packs of 200: " .. table.concat(bought, ","))
	IsShiftKeyDown = savedShift
	C_MerchantFrame = savedMerchant
	GetMerchantNumItems = function() return 2 end
	-- Restock at the merchant: a marked item sold singly is bought up to a full stack, capped by the purse.
	local restock = ns:GetModule("Restock")
	local savedDb, savedCdb = restock.db, restock.cdb
	restock.db, restock.cdb = { enabled = true, message = false }, { items = { [777] = true, [888] = "bank" } }
	GetMerchantItemLink = function(i) return i == 1 and "item:777" or nil end
	local savedItem = C_Item
	C_Item = setmetatable({ GetItemInfoInstant = function(link) return tonumber(tostring(link):match("item:(%d+)")) end,
		GetItemMaxStackSizeByID = function() return 20 end, GetItemCount = function() return 15 end }, { __index = savedItem })
	local plan, planCost = restock.MerchantPlan()
	assert(#plan == 1 and plan[1].index == 1 and plan[1].amount == 1, "restock buys the one missing item (money 150, price 100): " .. tostring(plan[1] and plan[1].amount))
	assert(planCost == 100, "restock cost")
	C_Item = savedItem
	restock.db, restock.cdb = savedDb, savedCdb
	GetMerchantItemLink = function() return nil end
	ns.MerchantTools = tools
	print("merchant view OK")
end)()
;(function()
	-- Drawing the bubble fails halfway: no empty bubble stays, Blizzard's window takes the step.
	local dialog = ns:GetModule("Dialog")
	local render = uv(dialog.Rerender, "Render")
	local body = uv(render, "RenderView")
	local printed = ns.Print
	ns.Print = function() end
	setuv(render, "RenderView", function() error("kaputt") end)
	setuv(dialog.Rerender, "current", { view = { kind = "GOSSIP_SHOW" } })
	render({ kind = "GOSSIP_SHOW" })
	assert(uv(dialog.Rerender, "current") == nil, "after a drawing error the bubble lets go of the step")
	setuv(render, "RenderView", body)
	ns.Print = printed
	dialog.reported = nil
	print("dialog render error OK")
end)()
;(function()
	-- The NPC's plate whose fields Blizzard has not filled yet is found by its unit token.
	local dialog = ns:GetModule("Dialog")
	local find = uv(dialog.WatchPlate, "NpcNameplate")
	local saved = { UnitExists, UnitGUID, C_NamePlate, UnitIsUnit }
	local plate = { IsForbidden = function() return false end } -- no unitToken yet
	UnitExists = function(token) return token == "nameplate3" end
	UnitGUID = function(token) return token == "nameplate3" and "Creature-NPC" or nil end
	UnitIsUnit = function() return false end
	C_NamePlate = { GetNamePlates = function() return { plate } end,
		GetNamePlateForUnit = function(token) return token == "nameplate3" and plate or nil end }
	setuv(find, "npcGuid", "Creature-NPC")
	assert(find() == plate, "plate found by its unit token")
	setuv(find, "npcGuid", nil)
	UnitExists, UnitGUID, C_NamePlate, UnitIsUnit = saved[1], saved[2], saved[3], saved[4]
	print("dialog plate by token OK")
end)()
;(function()
	-- The bubble stays wholly on the screen while the option "on screen" is on
	local dialog = ns:GetModule("Dialog")
	local place = uv(dialog.WatchPlate, "Place")
	local clamped
	local bubble = { ClearAllPoints = function() end, SetPoint = function() end, IsShown = function() return false end,
		SetClampedToScreen = function(_, on) clamped = on end }
	local savedBubble = uv(place, "bubble")
	setuv(place, "bubble", bubble)
	local savedScreen, savedHidePlate = dialog.db.onScreen, dialog.db.hidePlate
	dialog.db.onScreen, dialog.db.hidePlate = true, false
	local plate = CreateFrame("Frame")
	place(plate)
	assert(clamped == true, "clamped with the option")
	dialog.db.onScreen = false
	place(plate)
	assert(clamped == false, "free without it")
	dialog.db.onScreen, dialog.db.hidePlate = savedScreen, savedHidePlate
	dialog.anchorPlate = nil
	setuv(place, "bubble", savedBubble)
	print("dialog clamp OK")
end)()
;(function()
	-- Targeting a player can remove the NPC's plate and leave a stale alias or token behind.
	local dialog = ns:GetModule("Dialog")
	local show, hide = uv(dialog.GoBack, "Show"), uv(dialog.Apply, "Hide")
	hide()
	local bubble = uv(show, "bubble")
	local anchored
	local savedPoint, savedClear = bubble.SetPoint, bubble.ClearAllPoints
	bubble.SetPoint = function(_, _, to) anchored = to end
	bubble.ClearAllPoints = function() anchored = nil end
	local plateA, plateB, playerPlate = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
	local guid = { npc = "Creature-NPC", target = "Creature-NPC", nameplate1 = "Creature-NPC", nameplate3 = "Player-Self" }
	local plates = { npc = plateA, nameplate1 = plateA, nameplate3 = playerPlate }
	local saved = { C_NamePlate, UnitExists, UnitGUID, dialog.db.plates, dialog.db.hidePlate, dialog.db.enabled, dialog.db.style,
		dialog.db.fallback }
	local savedGet, savedSet = GetCVar, SetCVar
	local cvars = { nameplateShowAll = "0", nameplateShowFriendlyNpcs = "1" }
	GetCVar = function(cvar) return cvars[cvar] end
	SetCVar = function(cvar, value) cvars[cvar] = value end
	UnitExists = function(unit) return guid[unit] ~= nil end
	UnitGUID = function(unit) return guid[unit] end
	C_NamePlate = { GetNamePlates = function() return { plateA, playerPlate } end,
		GetNamePlateForUnit = function(unit)
			if guid[unit] == "Creature-NPC" and guid.target ~= guid[unit] and cvars.nameplateShowAll == "0" then
				return nil
			end
			return plates[unit]
		end }
	local savedGossip = GossipFrame
	GossipFrame = CreateFrame("Frame")
	local scale = 1
	GossipFrame.GetScale = function() return scale end
	GossipFrame.SetScale = function(_, value) scale = value end
	dialog.db.plates, dialog.db.hidePlate = true, false
	dialog.db.fallback = false
	dialog.db.enabled, dialog.db.style = true, "PLAYER"
	dialog:OnConversation("GOSSIP_SHOW")
	assert(anchored == plateA and bubble.Tail:IsShown(), "on the NPC's plate")
	assert(cvars.nameplateShowAll == "1" and scale == 0.001, "keeps all enabled plates available from opening")
	guid.target, plates.npc = "Player-Other", playerPlate
	dialog.WatchPlate()
	assert(anchored == plateA and bubble:IsShown(), "the NPC keeps its plate when a player is selected")
	dialog.OnPlateRemoved("nameplate1")
	assert(anchored == nil and dialog.anchorPlate == nil and not bubble:IsShown(), "off the plate that goes away")
	assert(scale == 0.001, "the native window stays collapsed during the brief wait")
	dialog.WatchPlate()
	assert(anchored == nil, "does not reattach while the removed token still reports the NPC")
	guid.nameplate1 = "Player-Other"
	dialog.OnPlateAdded("nameplate1")
	assert(anchored == nil, "does not attach to the selected player's recycled frame")
	guid.nameplate2, plates.nameplate2 = "Creature-NPC", plateB
	dialog.OnPlateAdded("nameplate2")
	assert(anchored == plateB, "back on the NPC")
	assert(bubble:IsShown() and bubble:GetAlpha() == 1 and bubble.Tail:IsShown(), "seen again on the plate")
	guid.nameplate2 = "Player-Other"
	dialog.WatchPlate()
	assert(anchored == nil and not bubble:IsShown(), "leaves a recycled plate even without a removal event")
	local savedTime = GetTime
	GetTime = function() return savedTime() + 1 end
	dialog.WatchPlate()
	GetTime = savedTime
	assert(not bubble:IsShown() and anchored == nil and GossipFrame:IsShown() and scale == 1
		and GossipFrame:GetAlpha() == 1, "the native dialog takes over after the wait")
	assert(cvars.nameplateShowAll == "0", "restores always-show setting after handoff")
	guid.npc = nil
	dialog:OnConversation("GOSSIP_SHOW")
	assert(anchored == nil and not bubble:IsShown(), "an already selected player cannot be captured as the speaker")
	guid.target, guid.nameplate2 = "Creature-NPC", "Creature-NPC"
	dialog.WatchPlate()
	assert(anchored == nil, "selecting an NPC later cannot change the speaker either")
	hide()
	bubble.SetPoint, bubble.ClearAllPoints = savedPoint, savedClear
	GossipFrame, GetCVar, SetCVar = savedGossip, savedGet, savedSet
	C_NamePlate, UnitExists, UnitGUID = unpack(saved, 1, 3)
	dialog.db.plates, dialog.db.hidePlate, dialog.db.enabled, dialog.db.style = unpack(saved, 4, 7)
	dialog.db.fallback = saved[8]
	print("dialog plate reuse OK")
end)()
;(function()
	-- Missing NPC nameplates must not prevent opening or retaining a quest reward.
	local dialog = ns:GetModule("Dialog")
	local hide = uv(dialog.Apply, "Hide")
	hide()
	local bubble = uv(uv(dialog.GoBack, "Show"), "bubble")
	local saved = { C_NamePlate, UnitExists, UnitGUID, GetTime, C_Timer.After, GetQuestID,
		dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic, dialog.db.style }
	local savedPoint, anchored = bubble.SetPoint
	bubble.SetPoint = function(_, _, target) anchored = target end
	local clock, plate, npc = 0, nil, CreateFrame("Frame")
	GetTime = function() return clock end
	C_Timer.After = function() end
	GetQuestID = function() return 78 end
	UnitExists = function(unit) return unit == "questnpc" or unit == "npc" or unit == "nameplate1" end
	UnitGUID = function() return "Creature-NPC" end
	C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return plate end }
	dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic = true, true, false
	dialog.db.style = "PLAYER"
	dialog:Apply()
	dialog:OnConversation("QUEST_COMPLETE")
	assert(not bubble:IsShown(), "briefly wait for the NPC nameplate")
	clock = 0.5
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == UIParent and not bubble.Tail:IsShown(),
		"the quest bubble opens at screen centre without an NPC nameplate")
	local choice = bubble.pools.item[2]
	choice:GetScript("OnClick")(choice)
	assert(choice.Chosen:IsShown(), "quest reward selection works without a nameplate")
	dialog:OnConversation("QUEST_COMPLETE")
	assert(bubble:IsShown() and choice.Chosen:IsShown() and anchored == UIParent,
		"refreshing the same quest keeps the floating bubble and its selected reward")
	plate = npc
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == npc and bubble.Tail:IsShown() and choice.Chosen:IsShown(),
		"a returning NPC nameplate reattaches the same quest bubble")
	plate = nil
	dialog.WatchPlate()
	clock = 1.1
	dialog.WatchPlate()
	assert(bubble:IsShown() and anchored == UIParent and choice.Chosen:IsShown(),
		"losing the nameplate preserves the bubble and reward choice")
	hide()
	bubble.SetPoint = savedPoint
	C_NamePlate, UnitExists, UnitGUID, GetTime, C_Timer.After, GetQuestID = unpack(saved, 1, 6)
	dialog.db.enabled, dialog.db.fallback, dialog.db.cinematic = unpack(saved, 7, 9)
	dialog.db.style = saved[10]
	dialog:Apply()
	print("dialog quest without nameplate OK")
end)()
;(function()
	-- A plate frame given to another unit still names the old unit token in its field: only the game's answer counts.
	local dialog = ns:GetModule("Dialog")
	local find = uv(dialog.WatchPlate, "NpcNameplate")
	local saved = { UnitExists, UnitGUID, C_NamePlate, UnitIsUnit }
	local stale = { unitToken = "nameplate1", IsForbidden = function() return false end }
	local right = { IsForbidden = function() return false end }
	UnitExists = function(token) return token == "nameplate1" or token == "nameplate2" end
	UnitGUID = function(token) return token == "nameplate2" and "Creature-NPC" or "Creature-Other" end
	UnitIsUnit = function() return false end
	C_NamePlate = { GetNamePlates = function() return { stale, right } end,
		GetNamePlateForUnit = function(token) return token == "nameplate2" and right or token == "nameplate1" and stale or nil end }
	setuv(find, "npcGuid", "Creature-NPC")
	assert(find() == right, "the plate the game names for the NPC")
	UnitGUID = function() return "Creature-Other" end
	assert(find() == nil, "no plate of another unit")
	setuv(find, "npcGuid", nil)
	UnitExists, UnitGUID, C_NamePlate, UnitIsUnit = saved[1], saved[2], saved[3], saved[4]
	print("dialog plate of the npc OK")
end)()
;(function()
	-- Merchant: wares all hidden by the filter are said to be hidden; special prices show in the basket.
	local dialog = ns:GetModule("Dialog")
	local saved = { GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair,
		GetNumBuybackItems, GetMerchantItemCostInfo, GetMerchantItemCostItem, ns.MerchantTools, dialog.db.merchantHide }
	ns.MerchantTools = nil
	GetMerchantNumItems = function() return 2 end
	local usable = false
	C_MerchantFrame = { GetItemInfo = function(i) return { name = "Ware" .. i, texture = 1, price = i == 2 and 30 or 0, stackCount = 1,
		numAvailable = -1, isPurchasable = true, isUsable = usable, hasExtendedCost = true } end }
	GetMerchantItemLink = function() return nil end
	GetMoney = function() return 150 end
	GetMoneyString = function(copper) return tostring(copper) .. "c" end
	CanMerchantRepair = function() return false end
	GetNumBuybackItems = function() return 0 end
	GetMerchantItemCostInfo = function() return 1 end
	GetMerchantItemCostItem = function(index) return "Ticket", index * 5 end
	local function Blocks()
		local view = dialog.MerchantView()
		local rows, texts = nil, {}
		for _, block in ipairs(view.blocks) do
			rows = block.rows or rows
			texts[#texts + 1] = block.text or block.money
			texts[#texts + 1] = block.right
		end
		return rows, table.concat(texts, "\n"), view
	end
	dialog.db.merchantHide = true
	local rows, text = Blocks()
	assert(rows == nil and text:find(ns.L.DIALOG_MERCHANT_HIDDEN:format(2), 1, true), "all hidden: said so")
	assert(not text:find(ns.L.DIALOG_MERCHANT_NONE, 1, true), "not: nothing to offer")
	dialog.db.merchantHide = false
	usable = true
	rows = Blocks()
	assert(#rows == 2 and rows[1].reserve == nil, "no free column while nothing is in the basket")
	local picked = uv(dialog.MerchantView, "merchantPicked")
	local qty = uv(dialog.MerchantView, "merchantQty")
	picked[1], qty[1], picked[2], qty[2] = true, 2, true, 1
	local view
	rows, text, view = Blocks()
	assert(rows[1].reserve == 48, "room for the quantity field of a ware in the basket")
	picked[2], qty[2] = nil, nil
	rows = Blocks()
	assert(rows[2].reserve == 48, "every row leaves the room while the basket has wares: prices stay in one column")
	picked[2], qty[2] = true, 1
	assert(text:find("20 |TTicket:14:14|t 30c", 1, true), "special prices summed (2 x 5 + 1 x 10) and the money: " .. text)
	assert(view.buttons[2].enabled == true, "payable")
	GetMoney = function() return 20 end
	rows, text, view = Blocks()
	assert(view.buttons[2].enabled == false, "the money of a ware with a special price counts")
	picked[1], qty[1], picked[2], qty[2] = nil, nil, nil, nil
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemLink, GetMoney, GetMoneyString, CanMerchantRepair, GetNumBuybackItems,
		GetMerchantItemCostInfo, GetMerchantItemCostItem, ns.MerchantTools, dialog.db.merchantHide = unpack(saved, 1, 11)
	-- The glow of a chosen row keeps the icons of the text (same width, same line breaks) and drops the colours.
	assert(dialog.GlowText("|cff9a9a9a1.|r |cff1eff00Umhang|r 32 |TCoin:14:14|t |A:x:14:14|a") == "1. Umhang 32 |TCoin:14:14|t |A:x:14:14|a",
		"glow text")
	local talents = ns:GetModule("Talents")
	assert(talents.CounterText(9, false) == "" and talents.CounterText(0, true) == "", "no plan, no counter")
	assert(talents.CounterText(9, true):find("9/", 1, true), "a plan shows its points")
	print("merchant hidden and special prices OK")
end)()
;(function()
	-- Flight: the time of a route is remembered when the player is off the taxi, also when the game still
	-- reports "on taxi" at the moment control comes back.
	local flight = ns:GetModule("Flight")
	local saved = { UnitOnTaxi, GetTime, ns.After, uv(flight.Finish, "current"), flight.db.times }
	flight.db.times = {}
	local onTaxi, now, again = true, 100, nil
	UnitOnTaxi = function() return onTaxi end
	GetTime = function() return now end
	ns.After = function(_, _, fn) again = fn end
	setuv(flight.Finish, "current", { route = "A -> B", start = 40 })
	flight:PLAYER_CONTROL_GAINED()
	assert(again and next(flight.db.times) == nil and uv(flight.Finish, "current"), "still on the taxi: asked again")
	flight:PLAYER_CONTROL_GAINED()
	onTaxi, now = false, 101
	again()
	assert(flight.db.times["A -> B"] == 61 and uv(flight.Finish, "current") == nil, "remembered after landing")
	assert(flight.Record("A -> C", 3) == false and flight.db.times["A -> C"] == nil, "too short: no flight")
	assert(flight.Record(nil, 60) == false, "no route, no time")
	UnitOnTaxi, GetTime, ns.After = saved[1], saved[2], saved[3]
	setuv(flight.Finish, "current", saved[4])
	flight.db.times = saved[5]
	print("flight time OK")
end)()
;(function()
	-- Flight bar: a middle-click hides it for this flight only, the flight is still timed.
	local flight = ns:GetModule("Flight")
	local savedBar, savedCurrent = uv(flight.OnBarClick, "bar"), uv(flight.Finish, "current")
	local shown = true
	local fake = { Hide = function() shown = false end }
	setuv(flight.OnBarClick, "bar", fake)
	local flying = { route = "A -> B", start = 0 }
	setuv(flight.Finish, "current", flying)
	flight.OnBarClick("LeftButton")
	flight.OnBarClick("RightButton")
	assert(shown, "other buttons leave the bar alone")
	flight.OnBarClick("MiddleButton")
	assert(not shown and uv(flight.Finish, "current") == flying, "hidden, the flight goes on being timed")
	setuv(flight.OnBarClick, "bar", savedBar)
	setuv(flight.Finish, "current", savedCurrent)
	print("flight bar middle-click OK")
end)()
;(function()
	-- Group finder: the roles chosen in the options are set, only while the option is on
	local finder = ns:GetModule("GroupFinder")
	assert(finder.PresetRoles({ presetRoles = false, roleTank = true }) == nil, "off: nothing set")
	assert(finder.PresetRoles({ presetRoles = true }) == nil, "no role chosen: nothing set")
	local roles = finder.PresetRoles({ presetRoles = true, roleTank = true, roleDps = true })
	assert(roles.tank == true and roles.healer == false and roles.dps == true, "several roles")
	local savedRoles, savedDB, set, limit = C_LFGListRoles, { finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps }, nil, nil
	C_LFGListRoles = { SetRoles = function(given, classOnly) set, limit = given, classOnly end }
	finder.db.presetRoles = false
	finder.ApplyRoles()
	assert(set == nil, "the game's roles stay while the option is off")
	finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps = true, true, false
	finder.ApplyRoles()
	assert(set and set.healer == true and set.dps == false and set.leader == nil and limit == true, "set, limited to the roles of the class")
	-- the dungeon finder: the same roles and the leader flag
	local lfg
	local savedLFG = SetLFGRoles
	SetLFGRoles = function(...) lfg = { ... } end
	finder.db.roleLeader = true
	finder.ApplyRoles()
	assert(lfg and lfg[1] == true and lfg[2] == false and lfg[3] == true and lfg[4] == false, "dungeon finder with the leader flag")
	finder.db.roleLeader = false
	finder.ApplyRoles()
	assert(lfg[1] == false, "without the leader flag")
	SetLFGRoles = savedLFG
	C_LFGListRoles = savedRoles
	finder.db.presetRoles, finder.db.roleHealer, finder.db.roleDps = savedDB[1], savedDB[2], savedDB[3]
	print("group finder roles OK")
end)()
;(function()
	-- Waypoint from coordinates: what is read, what is linked in the chat, what is set
	local way = ns:GetModule("Waypoint")
	local x, y, name = way.Parse("23, 34")
	assert(x == 23 and y == 34 and name == nil, "comma")
	x, y, name = way.Parse(" 23.5 34.2 Schmied ")
	assert(x == 23.5 and y == 34.2 and name == "Schmied", "decimals, blank and a name")
	x, y = way.Parse("23,5 / 34,2")
	assert(x == 23.5 and y == 34.2, "comma as the decimal sign")
	assert(way.Parse("123 45") == nil and way.Parse("hallo") == nil and way.Parse("") == nil and way.Parse(nil) == nil, "not coordinates")
	local linked = way.Linkify("Komm zu 45.2, 61 bitte")
	assert(linked:find("|Haddon:ForeverPlus:way:45.2:61|h[45.2, 61]|h", 1, true), "link in the chat: " .. linked)
	assert(way.Linkify("Ich habe 1,5 Gold und 120, 300 Punkte") == "Ich habe 1,5 Gold und 120, 300 Punkte", "a decimal number and big numbers stay text")
	assert(way.Linkify("Stufe 250, 300") == "Stufe 250, 300", "numbers above 100 are no coordinates")
	local saved = { C_Map.GetBestMapForUnit, C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, UiMapPoint, C_SuperTrack, ns.Print }
	local savedHasWaypoint, savedGetWaypoint = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint
	local set, tracked, cleared, can = nil, nil, nil, true
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.CanSetUserWaypointOnMap = function() return can end
	C_Map.SetUserWaypoint = function(point) set = point end
	C_Map.ClearUserWaypoint = function() set, cleared = nil, true end
	C_Map.HasUserWaypoint = function() return set ~= nil end
	C_Map.GetUserWaypoint = function() return set end
	UiMapPoint = { CreateFromCoordinates = function(mapID, px, py) return { uiMapID = mapID, position = { x = px, y = py } } end }
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) tracked = on end }
	ns.Print = function() end
	way.Command("way 23 34 Schmied")
	assert(set and set.uiMapID == 1429 and set.position.x == 0.23 and set.position.y == 0.34 and tracked == true, "set on the player's map, tracked")
	assert(way.Target().name == "Schmied", "reading the game waypoint preserves the name")
	assert(way.SetOnMap(1436, 42, 71, "Quest") and set.uiMapID == 1436 and set.position.y == 0.71,
		"the journal pin goes on the quest giver's map, not the player's map")
	can = false
	assert(not way.SetOnMap(1436, 30, 40) and set.position.x == 0.42, "an unsupported destination leaves the existing pin alone")
	can = true
	set = nil
	way.Command("way quatsch")
	assert(set == nil, "no numbers: nothing set")
	can = false
	assert(way.Set(10, 20) == true and set == nil and way.Target().mapID == 1429 and way.Target().y == 0.2, "a map without the game's waypoints: only our own")
	way.Command("weg")
	assert(cleared and way.Target() == nil, "without numbers the waypoint goes")
	-- direction and distance: north is up, the game's facing turns to the west
	local function near(a, b) return math.abs(a - b) < 1e-6 end
	local distance, angle = way.Bearing(0.5, 0.5, 0.5, 0.4, 1000, 1000, 0)
	assert(near(distance, 100) and near(angle, 0), "100 yards to the north, straight ahead")
	distance, angle = way.Bearing(0.5, 0.5, 0.4, 0.5, 1000, 1000, 0)
	assert(near(angle, math.pi / 2), "to the west: turned to the left")
	distance, angle = way.Bearing(0.5, 0.5, 0.6, 0.5, 1000, 500, math.pi / 2)
	assert(near(distance, 100) and near(angle, -math.pi), "facing west, the target in the east: behind")
	distance = way.Bearing(0.5, 0.5, 0.5, 0.6, 1000, 500, 0)
	assert(near(distance, 50), "the height of the map counts for north and south")
	-- the game's waypoint (map, recipe radar) is followed; the player on another map gets no direction
	local mapPos = { 0.5, 0.5 }
	set = { uiMapID = 1411, position = { x = 0.3, y = 0.4 } }
	C_Map.GetPlayerMapPosition = function(mapID) return mapID == 1411 and mapPos and { GetXY = function() return mapPos[1], mapPos[2] end } or nil end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	GetPlayerFacing = function() return 0 end
	distance = way.Where()
	assert(way.Target().mapID == 1411 and way.Target().x == 0.3 and near(distance, math.sqrt(0.2 ^ 2 + 0.1 ^ 2) * 1000), "the game's waypoint")
	mapPos = nil
	local _, goal = way.Where()
	assert(way.Where() == nil and goal.mapID == 1411, "another map: no distance")
	way.Clear()
	assert(way.Target() == nil, "cleared")
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint = savedHasWaypoint, savedGetWaypoint
	C_Map.GetBestMapForUnit, C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, UiMapPoint, C_SuperTrack, ns.Print = unpack(saved, 1, 7)
	print("waypoint OK")
end)()
;(function()
	local way = ns:GetModule("Waypoint")
	local wind = ns:GetModule("GuidingWind")
	local savedWindEnabled = wind and wind.db and wind.db.enabled
	if wind and wind.db then wind.db.enabled = false end
	way.Preview(false)
	local arrow = _G.ForeverPlusWaypointArrow
	local savedAPI, savedGhost, savedFacing = rawget(_G, "C_DeathInfo"), rawget(_G, "UnitIsGhost"), GetPlayerFacing
	local savedMap, savedMapInfo, savedPosition = C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition
	local savedHasWaypoint, savedGetWaypoint, savedClear = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint
	local savedNameText, savedText, savedFormat = arrow.Name.SetText, arrow.Text.SetText, arrow.Text.SetFormattedText
	local ghost, corpse
	local point = { uiMapID = 1429, position = { x = 0.8, y = 0.5 } }
	local function Vector(x, y)
		return { GetXY = function() return x, y end }
	end
	UnitIsGhost = function() return ghost end
	GetPlayerFacing = function() return 0 end
	C_DeathInfo = { GetCorpseMapPosition = function(mapID) return mapID == 1415 and corpse or nil end }
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(mapID) return mapID == 1429 and { mapType = 3, parentMapID = 1415 } or nil end
	C_Map.GetPlayerMapPosition = function() return Vector(0.5, 0.5) end
	C_Map.HasUserWaypoint = function() return point ~= nil end
	C_Map.GetUserWaypoint = function() return point end
	C_Map.ClearUserWaypoint = function() point = nil end
	arrow.Name.SetText = function(self, value) self.value = value end
	arrow.Text.SetText = arrow.Name.SetText
	arrow.Text.SetFormattedText = function(self, format, ...) self:SetText(format:format(...)) end

	local listeners = uv(ns.RegisterEvent, "listeners")
	local function Fire(event)
		listeners[event][way](way, event)
	end
	local function Update()
		assert(arrow:IsShown(), "the navigation display is active")
		arrow:GetScript("OnUpdate")(arrow, 0.3)
	end
	assert(way.db.corpseArrow, "corpse guidance is on by default")
	ghost = true
	Fire("PLAYER_ALIVE")
	Update()
	assert(not arrow.Arrow:IsShown() and arrow.Text.value == ns.L.WAYPOINT_CORPSE_UNKNOWN, "missing corpse data stays pending")
	corpse = Vector(0.375, 0.5)
	Update()
	assert(arrow.Arrow:IsShown() and arrow.Name.value == ns.L.WAYPOINT_CORPSE_NAME
		and math.abs(arrow.Arrow.rotation - math.pi / 2) < 1e-6
		and arrow.Text.value == ns.L.WAYPOINT_DISTANCE:format(125), "the corpse on the shared map is west, 125 yards away")
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	corpse = Vector(0.5, 0.5)
	Update()
	assert(arrow:IsShown() and point, "arrival and middle-click keep the saved waypoint in corpse mode")

	ghost = false
	Fire("PLAYER_UNGHOST")
	Update()
	assert(arrow.Arrow:IsShown() and arrow.Name.value ~= ns.L.WAYPOINT_CORPSE_NAME and way.Target().x == 0.8,
		"resurrection restores the original waypoint")
	way.db.arrow = false
	ghost = true
	Fire("PLAYER_ENTERING_WORLD")
	Update()
	assert(arrow.Name.value == ns.L.WAYPOINT_CORPSE_NAME, "reloading while a ghost works with the regular waypoint arrow disabled")
	way.db.corpseArrow = false
	way:OnOptionChanged("corpseArrow")
	assert(not arrow:IsShown(), "the corpse arrow can be disabled independently")

	way.Clear()
	way.db.arrow, way.db.corpseArrow = true, true
	if wind and wind.db then wind.db.enabled = savedWindEnabled end
	C_DeathInfo, UnitIsGhost, GetPlayerFacing = savedAPI, savedGhost, savedFacing
	C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition = savedMap, savedMapInfo, savedPosition
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint = savedHasWaypoint, savedGetWaypoint, savedClear
	arrow.Name.SetText, arrow.Text.SetText, arrow.Text.SetFormattedText = savedNameText, savedText, savedFormat
	print("corpse arrow OK")
end)()
;(function()
	-- Level ranges of the zones: Forever's own, after the name of the zone under the mouse, coloured like the game's
	local worldMap = ns:GetModule("WorldMap")
	assert(ns.ZoneLevels[1412][1] == 1 and ns.ZoneLevels[1412][2] == 14, "Mulgore is a starter zone")
	assert(ns.ZoneLevels[1434][1] == 28 and ns.ZoneLevels[1434][2] == 50, "Stranglethorn covers the full questing range")
	assert(ns.ZoneLevels[1446] and ns.ZoneLevels[2482] and ns.ZoneLevels[2548] and ns.ZoneLevels[2652], "late-game and new questing zones")
	assert(not ns.ZoneLevels[1414] and not ns.ZoneLevels[1415] and not ns.ZoneLevels[1453], "no ranges for continents and capitals")
	for mapID, range in pairs(ns.ZoneLevels) do
		assert(type(mapID) == "number" and range[1] >= 1 and range[1] <= range[2] and range[2] <= 60, "a range per zone")
	end
	local saved = { GetQuestDifficultyColor, QuestDifficultyColors, C_Map.GetMapInfoAtPosition, C_Map.GetMapLevels, worldMap.db.zoneLevels }
	local savedMapInfo, savedProviders = C_Map.GetMapInfo, WorldMapFrame.dataProviders
	GetQuestDifficultyColor = function(level) return { r = level, g = 0, b = 0 } end
	QuestDifficultyColors = { difficult = { r = 1, g = 1, b = 0 } }
	local text, color = worldMap.LevelText(10, 20, 5)
	assert(text == "(10-20)" and color.r == 10, "below: the colour of the lowest level")
	text, color = worldMap.LevelText(10, 20, 15)
	assert(color.r == 1 and color.g == 1, "within: yellow")
	text, color = worldMap.LevelText(10, 20, 30)
	assert(color.r == 18, "above: the highest level less two")
	assert(worldMap.LevelText(7, 7, 1) == "(7)", "one level")
	local focus, mapID = true, 1415
	local map = {
		IsCanvasMouseFocus = function() return focus end,
		GetMapID = function() return mapID end,
		GetNormalizedCursorPosition = function() return 0.4, 0.6 end,
	}
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1429, name = "Wald von Elwynn" } end
	C_Map.GetMapLevels = function() return 0, 0, 0, 0 end
	worldMap.db.zoneLevels = true
	local range, name = worldMap.HoveredRange(map)
	assert(range == ns.ZoneLevels[1429] and name == "Wald von Elwynn", "the zone under the mouse")
	C_Map.GetMapLevels = function() return 5, 10 end
	assert(worldMap.HoveredRange(map) == nil, "the game shows a range itself: none of ours")
	C_Map.GetMapLevels = function() return 5, 0 end
	assert(worldMap.HoveredRange(map) == ns.ZoneLevels[1429], "a partial client range is not displayed by the game")
	C_Map.GetMapLevels = function() return 0, 0 end
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1415, name = "Östliche Königreiche" } end
	assert(worldMap.HoveredRange(map) == nil, "the map itself is no zone under the mouse")
	focus = false
	C_Map.GetMapInfoAtPosition = function() return { mapID = 1429, name = "Wald von Elwynn" } end
	assert(worldMap.HoveredRange(map) == nil, "mouse not on the map")
	focus = true
	mapID = 2521
	C_Map.GetMapInfoAtPosition = function() return nil end
	C_Map.GetMapInfo = function(id) return { mapID = id, name = "Zephras Isle" } end
	local label = NewFrame("Frame")
	local labelName = ""
	label.Name.GetText = function() return labelName end
	label.labelInfoByType, label.fpLevels = {}, false
	label.dataProvider = { GetMap = function() return map end }
	WorldMapFrame.dataProviders = { [label.dataProvider] = true }
	label.dataProvider.Label = label
	assert(worldMap.HookAreaLabel() == label, "the world map provider is hooked")
	local levels = label.fpLevels
	levels.SetText = function(self, value) self.text = value end
	local update = label:GetScript("OnUpdate")
	update(label)
	assert(levels:IsShown() and levels.text == "Zephras Isle (1-12)", "the opened zone has a label on empty map space")
	labelName = "Valanaar"
	update(label)
	assert(not levels:IsShown(), "an area's own label does not get the whole zone's range")
	labelName = "Zephras Isle"
	update(label)
	assert(levels:IsShown() and levels.text == "(1-12)", "add just the range when the game displays the zone name")
	worldMap.db.zoneLevels = false
	update(label)
	assert(not levels:IsShown(), "option off")
	C_Map.GetMapInfo, WorldMapFrame.dataProviders = savedMapInfo, savedProviders
	GetQuestDifficultyColor, QuestDifficultyColors, C_Map.GetMapInfoAtPosition, C_Map.GetMapLevels, worldMap.db.zoneLevels = unpack(saved, 1, 5)
	print("zone levels OK")
end)()
;(function()
	-- Moments: one picture per boss (two events), a picture and a sound at a level-up, each only with its option
	local moments = ns:GetModule("Moments")
	assert(moments.ShotDue(1000) == true and moments.ShotDue(1002) == false and moments.ShotDue(1010) == true, "one picture per boss")
	local saved = { Screenshot, PlaySound, ns.After, GetTime, moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound }
	local shots, sounds, now = 0, 0, 2000
	Screenshot = function() shots = shots + 1 end
	-- Other modules listen to a level-up too: only this module's sound is counted.
	local savedLevelSound = moments.PlayLevelSound
	local kit
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = "fanfare"
	PlaySound = function(given) if given == "fanfare" then kit = given end end
	moments.PlayLevelSound = function() sounds = sounds + 1 savedLevelSound() end
	ns.After = function(_, _, fn) fn() end
	GetTime = function() return now end
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = false, false, false
	moments:Apply()
	Fire("PLAYER_LEVEL_UP", 20)
	Fire("BOSS_KILL", 1, "Boss")
	assert(shots == 0 and sounds == 0, "all off: nothing")
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = true, true, true
	moments:Apply()
	Fire("ENCOUNTER_END", 1, "Boss", 1, 5, 0)
	assert(shots == 0, "a wipe is no picture")
	Fire("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
	Fire("BOSS_KILL", 1, "Boss")
	assert(shots == 1, "boss dead: one picture for both events")
	now = 2100
	Fire("PLAYER_LEVEL_UP", 21)
	assert(shots == 2 and sounds == 1, "level-up: picture and fanfare (" .. shots .. ", " .. sounds .. ")")
	assert(kit == "fanfare" and moments.db.levelSoundKit == "UI_RAID_BOSS_DEFEATED", "the chosen sound of the game")
	assert(moments.SoundKey("UI_EPICLOOT_TOAST") == "UI_RAID_BOSS_DEFEATED" and moments.SoundKey("UI_SCENARIO_ENDING") == "UI_SCENARIO_ENDING", "a removed short sound falls back to the first")
	-- Without the interface: UIParent see-through for the picture, the level-up toast and the boss banner stay,
	-- everything back afterwards (by the timer here, by the screenshot event in the game).
	local savedFrames = { UIParent, EventToastManagerFrame, BossBanner, moments.db.shotHideUI }
	local function Fake(alpha, ignore)
		return { alpha = alpha, ignore = ignore,
			GetAlpha = function(self) return self.alpha end, SetAlpha = function(self, a) self.alpha = a end,
			IsIgnoringParentAlpha = function(self) return self.ignore end,
			SetIgnoreParentAlpha = function(self, i) self.ignore = i end }
	end
	UIParent, EventToastManagerFrame, BossBanner = Fake(0.9), Fake(1, false), Fake(1, true)
	local seen
	Screenshot = function()
		seen = { UIParent.alpha, EventToastManagerFrame.ignore, BossBanner.ignore }
	end
	moments.db.shotHideUI = true
	moments:Apply()
	now = 2200
	Fire("PLAYER_LEVEL_UP", 22)
	assert(seen and seen[1] == 0 and seen[2] == true and seen[3] == true, "picture: interface hidden, messages kept")
	assert(UIParent.alpha == 0.9 and EventToastManagerFrame.ignore == false and BossBanner.ignore == true, "interface back as before")
	moments.HideUI()
	Fire("SCREENSHOT_SUCCEEDED")
	assert(UIParent.alpha == 0.9 and EventToastManagerFrame.ignore == false, "back at the screenshot event")
	BossBanner = nil
	moments.HideUI()
	assert(UIParent.alpha == 0 and EventToastManagerFrame.ignore == true, "a missing banner is no error")
	moments.ShowUI()
	moments.db.shotHideUI = false
	seen = nil
	now = 2300
	Fire("PLAYER_LEVEL_UP", 23)
	assert(seen and seen[1] == 0.9 and seen[2] == false, "option off: picture with the interface")
	UIParent, EventToastManagerFrame, BossBanner, moments.db.shotHideUI = savedFrames[1], savedFrames[2], savedFrames[3], savedFrames[4]
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = nil
	moments.PlayLevelSound = savedLevelSound
	Screenshot, PlaySound, ns.After, GetTime = saved[1], saved[2], saved[3], saved[4]
	moments.db.shotBoss, moments.db.shotLevel, moments.db.levelSound = saved[5], saved[6], saved[7]
	moments:Apply()
	print("moments OK")
end)()
;(function()
	-- Solo Party uses independent events, even with the chat summaries disabled.
	local solo = ns:GetModule("SoloParty")
	local saved = { CreateFrame, GetMoney, issecretvalue, ns.NewTimer, GetMoneyString, SOUNDKIT, PlaySound, C_TradeSkillUI, PlaySoundFile }
	local money, timers, printed, visuals, positions = 1000, {}, {}, {}, {}
	local frames, played, effects = {}, {}, {}
	local bloodTextures, bloodLayer = {}, nil
	local fontSettings = ns:GetModule("Fonts").db
	local savedFace = fontSettings.face
	fontSettings.face = "Fonts\\FRIZQT__.TTF"
	C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(skill)
		local names = { [356] = "Fischfang", [186] = "Bergbau", [393] = "Kürschnerei",
			[182] = "Kräuterkunde", [185] = "Kochkunst", [129] = "Erste Hilfe", [165] = "Lederverarbeitung" }
		return { professionName = names[skill] }
	end }
	solo:OnLogin()
	SOUNDKIT = ns.CopyDefaults(SOUNDKIT, {})
	SOUNDKIT.UI_MISSION_SUCCESS_CHEERS = 74702
	SOUNDKIT.UI_RAID_BOSS_DEFEATED = 50111
	SOUNDKIT.UI_SCENARIO_STAGE_END = 31757
	SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_FAIL = 43501
	SOUNDKIT.UI_ADVENTURES_ADVENTURE_FAILURE_COMPLETE = 165976
	SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER = 43503
	local reward = { [74702] = true, [50111] = true, [31757] = true }
	local expense = { [43501] = true, [165976] = true, [43503] = true }
	local impacts = {}
	for _, id in ipairs({ 1240622, 1324858, 1240623, 1324859, 1240624, 1324860 }) do
		impacts[("Interface\\AddOns\\ForeverPlus\\Media\\LocalCrit\\%d.mp3"):format(id)] = id
	end
	local impactFiles = {}
	local rejectImpact, fallbackID
	PlaySoundFile = function(file, channel)
		assert(channel == "SFX", "critical sounds respect the effects channel")
		if rejectImpact and impacts[file] then
			assert(not fallbackID, "the fallback follows a single failed attempt")
			fallbackID = impacts[file]
			return false
		end
		if rejectImpact then
			assert(file == fallbackID, "the fallback plays the exact same sound by FileDataID")
		else
			assert(impacts[file], "successful clips do not play a fallback")
		end
		impactFiles[#impactFiles + 1] = file
		played[#played + 1] = file
		return true
	end
	PlaySound = function(kit, channel)
		if reward[kit] or expense[kit] then
			assert(channel == "SFX", "party sounds use the game's effects channel")
			played[#played + 1] = kit
		end
	end
	local layer
	GetMoney = function() return money end
	GetMoneyString = function(amount) return amount .. "c" end
	local secretCrit, secretMetrics = false, false
	issecretvalue = function(value)
		return value == "protected" or (secretCrit and (value == 4000 or value == "4000"))
			or (secretMetrics and value == 9999)
	end
	ns.NewTimer = function(_, _, fn)
		local timer = { fn = fn, Cancel = function(self) self.cancelled = true end }
		timers[#timers + 1] = timer
		return timer
	end
	local lastArtWidth, lastCardArt
	CreateFrame = function(kind, name, parent)
		local frame = NewFrame(kind, name)
		if parent == UIParent then
			frame.w, frame.h = 1400, 800
			frame.GetSize = function(self)
				if secretMetrics then
					return 9999, 9999
				end
				return self.w, self.h
			end
			layer = frame
		elseif layer and parent == layer then
			frame.SetPoint = function(_, _, _, _, x, y) positions[#positions + 1] = { x, y } end
		else
			frame.SetSize = function(self, w, h)
				self.w, self.h = w, h
				lastArtWidth = w
			end
			frame.SetScale = function(self, scale) self.scale = scale end
		end
		frame.CreateTexture = function(_, _, drawLayer)
			local texture = NewFrame("Texture")
			if drawLayer == "BACKGROUND" then
				texture.SetTexture = function(_, path)
					frames[#frames + 1], lastCardArt = path, frame
				end
			else
				local function Record(self, path)
					assert(not path:find("Skillbar_", 1, true), "the card does not draw profession-bar art")
					effects[#frames] = effects[#frames] or {}
					effects[#frames][self] = path
					if path:find("SoloPartyBloodSplats", 1, true) then
						bloodTextures[#bloodTextures + 1], bloodLayer = self, frame
					end
				end
				texture.SetTexture, texture.SetAtlas = Record, Record
				texture.SetTexCoord = function(self, left, _, top) self.u, self.v = left, top end
				texture.SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end
				texture.SetRotation = function(self, angle) self.rotation = angle end
				texture.SetSize = function(self, w, h) self.w, self.h = w, h end
				texture.AddMaskTexture = function(self, mask) self.mask = mask end
			end
			return texture
		end
		frame.CreateMaskTexture = function()
			local mask = NewFrame("Mask")
			mask.SetTexture = function(self, path) self.path = path end
			return mask
		end
		frame.CreateFontString = function()
			local region = NewFrame("FontString")
			region.secretText = false
			region.SetText = function(self, value)
				self.secretText = self.secretText or issecretvalue(value)
				printed[#printed + 1] = value
			end
			region.GetStringWidth = function(self)
				assert(not self.secretText, "protected damage text must not be measured for layout")
				return secretMetrics and 9999 or 80
			end
			region.SetFont = function(_, font, size, flags)
				visuals[#visuals + 1] = { font, size, flags }
				return true
			end
			return region
		end
		return frame
	end
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end
	local skill = "Eure Fertigkeit 'Kürschnerei' hat sich auf 51 erhöht."
	local function SetEnabled(value)
		solo.db.enabled = value
		solo:OnOptionChanged("enabled", value)
	end
	local function EnterWorld(value)
		money = value
		-- Other modules' world-entry callbacks need unrelated live data.
		local listeners = uv(ns.RegisterEvent, "listeners")
		listeners.PLAYER_ENTERING_WORLD[solo](solo, "PLAYER_ENTERING_WORLD")
	end
	local function Effect(index, name, left, top)
		for texture, path in pairs(effects[index] or {}) do
			if path:find(name, 1, true) and (left == nil or texture.u == left) and (top == nil or texture.v == top) then
				return texture
			end
		end
	end
	local random = math.random
	math.random = function(...)
		local first, last = ...
		-- Control variant draws while leaving positions and animation random.
		if last and last <= 6 then
			if first == 1 then return last end
			if first == 2 then return first end
		end
		return random(...)
	end
	assert(not solo.db.enabled and solo.db.sounds, "Solo Party defaults to off with sound available when enabled")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not layer and #played == 0, "disabled: no party frame or sound")
	SetEnabled(true)
	Fire("CHAT_MSG_SKILL", "protected")
	Fire("CHAT_MSG_SKILL", "Unrelated skill message")
	assert(not layer, "only readable skill increases qualify")
	Fire("CHAT_MSG_SKILL", skill)
	assert(printed[1] == "Kürschnerei" and printed[2] == ns.L.SOLO_PARTY_RANK:format(51), "the new skill rank pops: " .. table.concat(printed, ", "))

	money = 1099
	Fire("PLAYER_MONEY")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 99 Kupfer")
	timers[1].fn()
	assert(#printed == 2, "just below 10% of 1000c is quiet")
	EnterWorld(1000)
	Fire("CHAT_MSG_MONEY", "Ihr plündert 1 Silber")
	money = 1100
	Fire("PLAYER_MONEY")
	timers[2].fn()
	assert(printed[3] == ns.L.SOLO_PARTY_LOOT and printed[4] == "+100c", "exactly +10% of the purse before loot qualifies")
	money = 1500
	Fire("PLAYER_MONEY")
	money = 1351
	Fire("PLAYER_MONEY")
	assert(#printed == 4, "non-loot credits and spending below 10% are quiet")
	EnterWorld(1000)
	money = 900
	Fire("PLAYER_MONEY")
	assert(printed[5] == ns.L.SOLO_PARTY_SPENT and printed[6] == "−100c", "exactly -10% of the purse before spending qualifies")
	assert(#played == 3 and reward[played[1]] and reward[played[2]] and expense[played[3]], "each qualifying burst gets a sound from its pool")
	assert(#frames == 3 and frames[1] ~= frames[2] and frames[2] ~= frames[3] and frames[1] ~= frames[3], "all three card variants appear")
	assert(Effect(1, "SoloPartyMotifs", 0.5, 0), "skinning has strands")
	assert(Effect(2, "UI-GoldIcon") and Effect(3, "BonusChest-OrangeSmoke-Wide"), "loot has coins and spending has smoke")
	assert(visuals[1][3] == "" and visuals[2][3] == "", "card text uses a shadow without an outline")
	for _, path in ipairs(frames) do
		local asset = assert(io.open(root .. "/Media/" .. path:match("[^\\]+$") .. ".tga", "rb"))
		asset:close()
	end
	assert(positions[1][1] ~= positions[2][1] and positions[2][1] ~= positions[3][1], "consecutive bursts use different places")
	assert(visuals[4][1] == ns.GetFontFace() and visuals[6][1] == ns.GetFontFace() and visuals[4][2] ~= visuals[6][2],
		"cards use the selected interface typeface with different sizes")
	layer:GetScript("OnUpdate")(layer, 2)
	assert(not layer:IsShown(), "animation releases the overlay")

	EnterWorld(0)
	money = 11
	Fire("PLAYER_MONEY")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 10 Kupfer")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 1 Kupfer")
	timers[3].fn()
	assert(printed[8] == "+10c" and printed[10] == "+1c", "cash from zero and a second loot line in the same tick")
	assert(reward[played[4]] and played[1] ~= played[2] and played[4] ~= played[1] and played[4] ~= played[2]
		and played[5] == played[2], "the reward sound order changes after all three are used")
	assert(frames[4] == frames[2] and frames[5] == frames[1], "the card order changes after all three are used")
	Fire("CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer")
	SetEnabled(false)
	assert(timers[4].cancelled and not layer:IsShown(), "switching off clears pending loot and active effects")
	Fire("CHAT_MSG_SKILL", skill)
	assert(#printed == 10 and #played == 5, "switching off unregisters the events")
	local preview = solo.options[#solo.options].func
	preview()
	assert(#printed == 12 and #played == 6, "preview starts with one effect and one sound")
	local bubble = assert(Effect(6, "SoloPartyWater", 0.5), "fishing has bubble particles")
	local ripple = assert(Effect(6, "SoloPartyWater", 0), "fishing keeps its ripples")
	assert(ripple.mask.path:find("SoloPartyEffectMask", 1, true), "ripples taper softly")
	local bubbleY = bubble.y
	layer:GetScript("OnUpdate")(layer, 0.7)
	assert(bubble.y > bubbleY and bubble:GetAlpha() > 0, "fishing bubbles rise and become visible")
	local left, right, low, high = false, false, math.huge, -math.huge
	for texture, path in pairs(effects[6]) do
		if texture.u == 0.5 and path:find("SoloPartyWater", 1, true) then
			left, right = left or texture.x < 0, right or texture.x > 0
			low, high = math.min(low, texture.y), math.max(high, texture.y)
		end
	end
	assert(left and right and high - low > 4, "bubbles drift at different heights on both sides")
	timers[#timers].fn()
	assert(#printed == 14 and #played == 7, "preview plays the second effect separately")
	timers[#timers].fn()
	assert(#printed == 16 and #played == 8 and expense[played[8]], "preview plays the expense sound separately")
	timers[#timers].fn()
	assert(#printed == 18 and #played == 9 and printed[18] == ns.L.SOLO_PARTY_XP_VALUE:format(450), "preview includes experience")
	timers[#timers].fn()
	assert(#printed == 20 and #played == 10 and printed[19] == ns.L.SOLO_PARTY_CRIT and printed[20] == "1234"
		and #impactFiles == 1, "preview ends with a critical hit and a weapon impact sound")
	assert(not solo.db.enabled and money == 11, "preview leaves the mode and wallet alone")

	SetEnabled(true)
	for _ = 1, 2 do
		EnterWorld(1000)
		money = 900
		Fire("PLAYER_MONEY")
	end
	assert(expense[played[11]] and played[11] ~= played[8] and played[8] ~= played[3] and played[11] ~= played[3]
		and played[12] == played[8], "the expense sound order changes after all three are used")
	solo.db.sounds = false
	solo:OnOptionChanged("sounds")
	money = 810
	Fire("PLAYER_MONEY")
	assert(#printed == 26 and #played == 12 and solo.db.enabled, "muting keeps qualifying pop-ups active")
	Fire("CHAT_MSG_SKILL", "Eure Fertigkeit 'Fischfang' hat sich auf 51 erhöht.")
	assert(Effect(#frames, "SoloPartyWater", 0.5), "the fishing effect follows the client-localized skill name")
	Fire("CHAT_MSG_SKILL", "Eure Fertigkeit 'Bergbau' hat sich auf 51 erhöht.")
	local smoke = assert(Effect(#frames, "BonusChest-OrangeSmoke-Wide"), "mining gets the forge effect")
	for _, profession in ipairs({ { "Kräuterkunde", 0, 0 }, { "Kochkunst", 0, 0.5 }, { "Erste Hilfe", 0.5, 0.5 },
		{ "Lederverarbeitung", 0.5, 0 } }) do
		Fire("CHAT_MSG_SKILL", "Eure Fertigkeit '" .. profession[1] .. "' hat sich auf 51 erhöht.")
		assert(Effect(#frames, "SoloPartyMotifs", profession[2], profession[3]), "individual motif for " .. profession[1])
	end
	solo.db.effects = false
	solo:OnOptionChanged("effects")
	assert(not smoke:IsShown() and not bubble:IsShown(), "disabling effects clears active art")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not effects[#frames] and printed[#printed - 1] == "Kürschnerei", "the frame and text continue without effects")

	-- Experience: 10% of the level's need before the gain, level-ups counted across the boundary.
	local savedXP = { UnitXP, UnitXPMax }
	local xp, xpMax = 0, 1000
	UnitXP, UnitXPMax = function() return xp end, function() return xpMax end
	solo.db.sounds = true
	EnterWorld(1000)
	local shown, sounds = #printed, #played
	xp = 99
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown, "just below 10% of the level is quiet")
	xp = 199
	Fire("PLAYER_XP_UPDATE", "player")
	assert(printed[shown + 1] == ns.L.SOLO_PARTY_XP and printed[shown + 2] == ns.L.SOLO_PARTY_XP_VALUE:format(100),
		"exactly 10% of the level qualifies: " .. tostring(printed[shown + 2]))
	assert(#played == sounds + 1 and reward[played[#played]], "experience uses the reward sounds")
	xp, xpMax = 50, 1200
	Fire("PLAYER_XP_UPDATE", "player")
	assert(printed[shown + 4] == ns.L.SOLO_PARTY_XP_VALUE:format(851), "a level-up counts the rest of the old level: " .. tostring(printed[shown + 4]))
	xp = "protected"
	Fire("PLAYER_XP_UPDATE", "player")
	xp = 400
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown + 4, "a protected value is ignored and restarts the baseline")
	solo.db.sounds = false
	SetEnabled(false)
	xp = 900
	Fire("PLAYER_XP_UPDATE", "player")
	assert(#printed == shown + 4, "switching off unregisters the experience event")
	UnitXP, UnitXPMax = unpack(savedXP, 1, 2)

	-- Critical hits work while the independent combat-text module is off.
	local combat = ns:GetModule("CombatText")
	local savedCombat = { UnitCanAttack, UnitIsUnit, UnitThreatSituation, combat.db.enabled }
	local hostile, selfTarget, threat, aimed = true, false, 1, false
	UnitCanAttack = function() return hostile and selfTarget ~= true end
	UnitIsUnit = function(a) return a == "targettarget" and aimed or selfTarget end
	UnitThreatSituation = function() return threat end
	combat.db.enabled = false
	solo.db.effects, solo.db.sounds = true, true
	shown, sounds = #printed, #played
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	assert(#printed == shown, "disabled Solo Party ignores critical hits")
	SetEnabled(true)
	for _, args in ipairs({ { "target", "WOUND", "", 1234 }, { "player", "WOUND", "CRITICAL", 50 },
		{ "target", "HEAL", "CRITICAL", 1234 }, { "target", "WOUND", "protected", 1234 },
		{ "target", "WOUND", "CRITICAL", "protected" }, { "target", "WOUND", "CRITICAL", 0 } }) do
		Fire("UNIT_COMBAT", unpack(args))
	end
	hostile = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	hostile, selfTarget = true, true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	selfTarget, threat = false, nil
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1234)
	assert(#printed == shown and #played == sounds, "only critical damage on an involved hostile target qualifies")
	threat = 1
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1000)
	assert(printed[shown + 1] == ns.L.SOLO_PARTY_CRIT and printed[shown + 2] == "1000"
		and #played == sounds + 1 and impacts[played[#played]], "every critical gets its card and weapon impact sound")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 999)
	assert(printed[shown + 4] == "999" and #played == sounds + 2, "smaller criticals are shown too")
	assert(Effect(#frames, "star4"), "critical damage has sparks")
	solo.db.criticals = false
	solo:OnOptionChanged("criticals")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2000)
	assert(#printed == shown + 4, "critical-hit option unregisters the listener")
	solo.db.criticals = true
	solo:OnOptionChanged("criticals")
	threat, aimed = nil, true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2500)
	assert(printed[shown + 6] == "2500", "a target aiming at the player counts as involvement")
	for i = 1, 4 do
		Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2500 + i * 100)
	end
	local unique = {}
	for i = 1, 6 do
		assert(not unique[impactFiles[i]], "all six critical impact sounds play before a repeat")
		unique[impactFiles[i]] = true
	end
	assert(impactFiles[7] == impactFiles[5], "the impact sound order changes after all six are used")
	math.random = random
	local beforeCrit = #impactFiles
	solo.db.critSound = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 2900)
	assert(#impactFiles == beforeCrit and printed[#printed] == "2900", "the critical sound can be disabled on its own")
	local beforeReward = #played
	Fire("CHAT_MSG_SKILL", skill)
	assert(#played == beforeReward + 1 and reward[played[#played]], "the critical sound switch preserves other rewards")
	solo.db.critSound = true
	solo.db.sounds = false
	solo:OnOptionChanged("sounds")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 3000)
	assert(#impactFiles == 8 and printed[#printed] == "3000", "muting suppresses the impact while still showing the card")
	secretCrit = true
	solo.db.sounds = true
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	assert(printed[#printed] == "4000" and #impactFiles == 9,
		"protected damage, as the client always sends it, is shown without being compared or measured")
	secretCrit = false
	selfTarget = "protected"
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 3500)
	assert(#impactFiles == 10, "restricted identity comparisons do not suppress criticals")
	assert(not solo.db.bloody and not bloodLayer, "Bloody defaults to off")
	solo.db.bloody = true
	solo:OnOptionChanged("bloody")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	assert(frames[#frames]:find("SoloPartyBloody", 1, true) and #bloodTextures == 8 and bloodLayer:IsShown(),
		"Bloody swaps the critical card and scatters eight splashes")
	local previousSplashes = {}
	for i, texture in ipairs(bloodTextures) do
		assert(texture.x > 0 and texture.x < 1400 and texture.y > 0 and texture.y < 800, "blood splashes stay on screen")
		previousSplashes[i] = { texture.x, texture.u, texture.v }
	end
	layer:GetScript("OnUpdate")(layer, 0.3)
	assert(bloodTextures[1]:GetAlpha() > 0 and bloodTextures[8]:GetAlpha() > 0, "blood splashes become visible")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4100)
	assert(#bloodTextures == 8, "consecutive bloody criticals reuse the eight textures")
	for i, texture in ipairs(bloodTextures) do
		local previous = previousSplashes[i]
		assert(texture.x ~= previous[1] and (texture.u ~= previous[2] or texture.v ~= previous[3]),
			"each consecutive bloody critical changes the splash motif and position")
	end
	layer:GetScript("OnUpdate")(layer, 2.1)
	assert(not bloodLayer:IsShown() and not layer:IsShown(), "blood splashes and the overlay expire together")
	Fire("CHAT_MSG_SKILL", skill)
	assert(not frames[#frames]:find("SoloPartyBloody", 1, true) and not bloodLayer:IsShown(),
		"ordinary events keep their existing cards")
	secretCrit = true
	for _ = 1, 6 do
		Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4000)
	end
	secretCrit = false
	for _ = 1, 6 do
		Fire("CHAT_MSG_SKILL", skill)
		assert(lastArtWidth == 225, "reused slots measure clean skill text on the uncontaminated FontString")
	end
	secretMetrics = true
	Fire("CHAT_MSG_SKILL", skill)
	assert(lastArtWidth == 360, "secret text widths fall back to 220 instead of entering layout math")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4150)
	secretMetrics = false
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4200)
	solo.db.bloody = false
	solo:OnOptionChanged("bloody")
	assert(not bloodLayer:IsShown() and not frames[#frames]:find("SoloPartyBloody", 1, true),
		"switching off Bloody clears splashes and restores the active card")
	solo.db.bloody = true
	solo:OnOptionChanged("bloody")
	Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4300)
	SetEnabled(false)
	assert(not bloodLayer:IsShown(), "switching off Solo Party clears the blood overlay")
	solo.db.bloody = false
	local bloodyPreview
	for _, option in ipairs(solo.options) do
		if option.name == ns.L.SOLO_PARTY_BLOODY_PREVIEW then bloodyPreview = option.func end
	end
	assert(bloodyPreview and bloodyPreview ~= preview, "Bloody has its own test button alongside the unchanged general preview")
	shown, sounds = #printed, #played
	local timerCount = #timers
	bloodyPreview()
	assert(#printed == shown + 2 and printed[#printed - 1] == ns.L.SOLO_PARTY_CRIT and printed[#printed] == "1234"
		and #played == sounds + 1 and frames[#frames]:find("SoloPartyBloody", 1, true) and bloodLayer:IsShown(),
		"the Bloody test immediately shows only its critical card, splashes and impact sound")
	assert(not solo.db.enabled and not solo.db.bloody and #timers == timerCount,
		"the Bloody test changes no settings and schedules no preview sequence")
	rejectImpact = true
	bloodyPreview()
	assert(fallbackID and impactFiles[#impactFiles] == fallbackID, "missing local audio still plays the original in the preview")
	rejectImpact = false
	preview()
	local pendingPreview = timers[#timers]
	bloodyPreview()
	assert(pendingPreview.cancelled and #timers == timerCount + 1,
		"testing Bloody stops a pending general preview instead of mixing later preview steps into the test")
	for _, viewport in ipairs({ { 1400, 800 }, { 2200, 800 }, { 650, 900 } }) do
		local w, h = unpack(viewport)
		layer.w, layer.h = w, h
		local centerX, centerY, radius = w * 0.5, h * 0.45, math.min(w, h) * 0.12
		local smallSplash = 60 * math.min(w / 1200, h / 800)
		for _ = 1, 6 do
			bloodyPreview()
			layer:GetScript("OnUpdate")(layer, 0.124) -- Close to the maximum pop scale.
			local x, y = unpack(positions[#positions])
			local halfWidth = lastCardArt.w * lastCardArt.scale / 2
			local halfHeight = lastCardArt.h * lastCardArt.scale / 2
			local dx = math.max(0, math.abs(x - centerX) - halfWidth)
			local dy = math.max(0, math.abs(y - centerY) - halfHeight)
			assert(dx * dx + dy * dy >= radius * radius, "the whole Bloody card stays outside the circle at peak scale")
			assert(x - halfWidth >= 0 and x + halfWidth <= w and y - halfHeight >= 0 and y + halfHeight <= h,
				"the Bloody card remains on screen")
			local hasSmallCenterSplash = false
			for _, texture in ipairs(bloodTextures) do
				local sx, sy = texture.x - centerX, texture.y - centerY
				local distance = math.sqrt(sx * sx + sy * sy)
				if texture.w > smallSplash then
					assert(distance >= radius + texture.w / math.sqrt(2), "even rotated large splashes stay outside the circle")
				elseif distance < radius then
					hasSmallCenterSplash = true
				end
			end
			assert(hasSmallCenterSplash, "a small blood splash remains inside the circle")
		end
	end
	SetEnabled(false)
	UnitCanAttack, UnitIsUnit, UnitThreatSituation, combat.db.enabled = unpack(savedCombat, 1, 4)
	solo.db.sounds, solo.db.effects = true, true
	CreateFrame, GetMoney, issecretvalue, ns.NewTimer, GetMoneyString, SOUNDKIT, PlaySound, C_TradeSkillUI, PlaySoundFile = unpack(saved, 1, 9)
	fontSettings.face = savedFace
	print("solo party OK")
end)()
;(function()
	local globals = { "CreateFrame", "MinimapCluster", "MuteSoundFile", "UnmuteSoundFile", "PlaySoundFile", "StopSound",
		"CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "UISpecialFrames", "ForeverPlusEmitterSounds",
		"C_Map", "GetRealZoneText", "GetSubZoneText", "GetInstanceInfo", "IsSubmerged", "MenuUtil" }
	local saved = {}
	for _, key in ipairs(globals) do saved[key] = rawget(_G, key) end
	local tracking, trigger, initialize, results, visibleRow = NewFrame("DropdownButton")
	local muted, playing = {}, nil
	local currentMap, x, y = 1453, -8990, 478
	C_Map = setmetatable({
		GetBestMapForUnit = function() return currentMap end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.4 end } end,
		GetWorldPosFromMapPos = function() return 0, { GetXY = function() return x, y end } end,
	}, { __index = saved.C_Map })
	GetRealZoneText = function() return "Stormwind" end
	GetSubZoneText = function() return "" end
	GetInstanceInfo = function() return "", "none" end
	IsSubmerged = function() return false end
	MinimapCluster = { Tracking = { Button = tracking } }
	MuteSoundFile = function(id) muted[id] = true end
	UnmuteSoundFile = function(id) muted[id] = nil end
	PlaySoundFile = function(id, channel)
		assert(not muted[id] and channel == "SFX")
		playing = id
		return true, id
	end
	StopSound = function(handle) assert(handle == playing) playing = nil end
	CreateScrollBoxListLinearView = function()
		return { SetElementExtent = function() end, SetElementInitializer = function(_, _, fn) initialize = fn end }
	end
	CreateDataProvider = function(entries) return entries end
	ScrollUtil = { InitScrollBoxListWithScrollBar = function(list)
		list.SetDataProvider = function(_, entries) results = entries end
		list.ReinitializeFrames = function()
			if visibleRow then initialize(visibleRow, visibleRow.file) end
		end
	end }
	local filterEntries, categoryEntries
	MenuUtil = { CreateContextMenu = function(button, generator)
		filterEntries, categoryEntries = {}, {}
		local function AddRadioTo(entries)
			return function(_, _, selected, action, value)
				local entry = { selected = selected, action = action, enabled = true }
				entry.SetEnabled = function(self, enabled) self.enabled = enabled end
				entries[value] = entry
				return entry
			end
		end
		generator(button, {
			CreateTitle = function() end,
			CreateDivider = function() end,
			CreateRadio = AddRadioTo(filterEntries),
			CreateButton = function(_, name, action)
				local entry = { action = action, CreateRadio = AddRadioTo(categoryEntries) }
				entry.SetEnabled = function(self, enabled) self.enabled = enabled end
				filterEntries[name] = entry
				return entry
			end,
		})
	end }
	UISpecialFrames = {}
	CreateFrame = function(kind, name, parent)
		local frame = NewFrame(kind, name)
		frame.SetText = function(self, value) self.text = value end
		frame.GetText = function(self) return rawget(self, "text") or "" end
		frame.SetChecked = function(self, value) self.checked = value end
		frame.GetChecked = function(self) return rawget(self, "checked") end
		frame.Enable = function(self) self.enabled = true end
		frame.Disable = function(self) self.enabled = false end
		if parent == tracking then
			trigger = frame
			frame.RegisterForClicks = function(_, click) assert(click == "RightButtonUp") end
			frame.SetPassThroughButtons = function(_, first) assert(first == "LeftButton") end
		end
		return frame
	end
	local module
	local fixture = setmetatable({
		NewModule = function(_, _, spec)
			module = spec
			module.ToggleEvent = function() end
			module.RegisterEvent = function() end
			module.db = ns.CopyDefaults(spec.defaults, {})
			return module
		end,
		OnAddOnLoaded = function(name, fn) if name == "Blizzard_Minimap" then fn() end end,
		RegisterDisplay = function() end,
	}, { __index = ns })
	assert(loadfile(root .. "/Modules/Minimap.lua"))("ForeverPlus", fixture)
	module.db.mutedEmitters[7079224] = true
	module:OnLogin()
	assert(trigger:IsShown() and muted[7079224], "login installs the right-click trigger and reapplies saved mutes")
	trigger:GetScript("OnClick")(trigger, "RightButton")
	local window = ForeverPlusEmitterSounds
	local function FindSound(id)
		for _, sound in ipairs(results) do
			if sound[1] == id then return sound end
		end
	end
	local function Search(query)
		window.Search:SetText(query)
		window.Search:GetScript("OnTextChanged")(window.Search)
	end
	local function OpenFilters()
		window.Filter:GetScript("OnClick")(window.Filter)
		return filterEntries
	end
	local function SelectFilter(value)
		local entry = OpenFilters()[value]
		assert(entry and entry.enabled, "filter is selectable")
		entry.action(value)
	end
	local function SelectCategory(value)
		OpenFilters()
		assert(categoryEntries[value], "category is selectable in its own submenu")
		categoryEntries[value].action(value)
	end
	assert(window:IsShown() and window.Nearby:GetChecked() and #results > 0 and #results < 600,
		"right-click opens a short list of local sources and ambience")
	Search("wind")
	local bridge = assert(FindSound(4524098), "wind near the Stormwind entrance includes the bridge source")
	assert(bridge[3]:find("Bridge Wind", 1, true) and bridge[2]:find("ambience/", 1, true),
		"placement labels identify the source even for reused audio in a different archive folder")
	assert(not FindSound(7386632) and not FindSound(7139274), "unrelated Retail and Westfall files stay out of the local results")
	SelectCategory("wind")
	assert(module.db.emitterSoundCategory == "wind" and FindSound(4524098),
		"category filtering finds a wind source whose filename gives no clue")
	SelectCategory("water")
	assert(not FindSound(4524098), "water does not match the wind source")
	SelectCategory("all")
	local row = NewFrame("Frame")
	row.CreateFontString = function()
		local label = NewFrame("FontString")
		label.SetText = function(self, value) self.text = value end
		return label
	end
	row.Mute = false
	visibleRow = row
	initialize(row, bridge)
	local guessedWind = ns.L.MINIMAP_EMITTER_CATEGORY_INFERRED:format(ns.L.MINIMAP_EMITTER_CATEGORY_WIND)
	assert(row.Detail.text:find(guessedWind, 1, true), "a category inferred from the placement is marked as a guess")
	row.Preview:GetScript("OnClick")(row.Preview)
	local bulk = window.BulkMute
	local toggleBulk = bulk:GetScript("OnClick")
	local windResults = results
	assert(#windResults > 1 and bulk.enabled and bulk:GetText() == ns.L.MINIMAP_EMITTER_MUTE_ALL)
	toggleBulk(bulk)
	assert(not playing and row.Mute:GetChecked() and bulk:GetText() == ns.L.MINIMAP_EMITTER_UNMUTE_ALL)
	for _, sound in ipairs(windResults) do
		assert(muted[sound[1]] and module.db.mutedEmitters[sound[1]], "bulk mute saves every result, including off-screen rows")
	end
	toggleBulk(bulk)
	assert(not row.Mute:GetChecked() and bulk:GetText() == ns.L.MINIMAP_EMITTER_MUTE_ALL)
	for _, sound in ipairs(windResults) do
		assert(not muted[sound[1]] and not module.db.mutedEmitters[sound[1]], "bulk unmute frees every result")
	end
	assert(muted[7079224] and module.db.mutedEmitters[7079224], "bulk actions preserve mutes outside the active search")
	local runSearch
	fixture.After = function(_, _, callback) runSearch = callback end
	Search("no matching sound")
	assert(not bulk.enabled, "new search input invalidates the old bulk target before debounce ends")
	toggleBulk(bulk)
	assert(not muted[bridge[1]], "a pending search cannot mute stale results")
	runSearch()
	assert(#results == 0 and not bulk.enabled, "bulk action is unavailable on an empty list")
	fixture.After = nil
	x, y = -8990, 420
	Search("bridge wind")
	assert(FindSound(4524098), "default source range includes the bridge near the gate")
	SelectFilter("source")
	SelectFilter(25)
	assert(not FindSound(4524098), "a smaller radius removes the bridge source")
	SelectFilter(100)
	assert(FindSound(4524098), "the type and radius filter combine with the text search")
	assert(window.Filter:GetText() == ns.L.MINIMAP_EMITTER_FILTER_ACTIVE:format(2))
	SelectFilter("background")
	local radios = OpenFilters()
	assert(radios.background.selected("background") and not radios[100].enabled and not FindSound(4524098),
		"background filter hides placed sources and disables the radius")
	assert(module.db.emitterSoundRadius == 100, "switching categories remembers the radius")
	SelectFilter(ns.L.RESET)
	assert(FindSound(4524098) and module.db.emitterSoundRadius == 0 and module.db.emitterSoundKind == "all",
		"reset restores the default range and all categories")
	Search("")
	SelectFilter("rain")
	local rainResults = results
	assert(module.db.nearbyEmitters and #rainResults == 7 and not OpenFilters()[25].enabled,
		"rain finds the build's variants at any location without changing the saved local filter")
	assert(FindSound(538982) and FindSound(2057626) and FindSound(2057628) and not FindSound(4524098),
		"rain includes the loud loops and excludes other ambient sounds")
	Search(ns.L.MINIMAP_EMITTER_RAIN_HEAVY)
	assert(#results == 3 and FindSound(538982), "localized intensity labels can be searched")
	Search("")
	toggleBulk(bulk)
	for _, sound in ipairs(rainResults) do
		assert(muted[sound[1]] and module.db.mutedEmitters[sound[1]], "all rain loops can be muted together")
	end
	assert(not muted[4524098] and muted[7079224], "the rain filter leaves other files out of the bulk operation")
	toggleBulk(bulk)
	for _, sound in ipairs(rainResults) do
		assert(not muted[sound[1]] and not module.db.mutedEmitters[sound[1]], "all rain loops can be unmuted together")
	end
	SelectFilter(ns.L.RESET)
	x, y = -8600, 860
	Search("bridge wind")
	assert(not FindSound(4524098), "a bridge emitter leaves the results when out of range")
	currentMap, x, y = 1429, -9462, 60
	Search("")
	local forest = assert(FindSound(539108), "the current zone's background plays outside the emitters folder")
	assert(forest[4] == ns.L.MINIMAP_EMITTER_AMBIENCE, "the list identifies the source as zone background")
	SelectFilter("detail")
	assert(FindSound(648331) and not FindSound(539108), "other zone sounds can be filtered separately")
	SelectFilter("background")
	assert(FindSound(539108) and not FindSound(648331), "background excludes the secondary ambience of the zone")
	toggleBulk(bulk)
	assert(muted[539108] and not muted[648331], "bulk mute respects the selected sound category")
	toggleBulk(bulk)
	assert(not muted[539108], "bulk unmute respects the selected sound category")
	window.Nearby:SetChecked(false)
	window.Nearby:GetScript("OnClick")(window.Nearby)
	Search("")
	SelectFilter("source")
	assert(FindSound(7139274) and not FindSound(539108) and not OpenFilters()[50].enabled,
		"the kind filter works across Forever and only local sources have a radius")
	SelectFilter(ns.L.RESET)
	assert(FindSound(7139274) and not FindSound(7386632), "the global list includes Forever-linked files and omits unrelated Retail files")
	SelectCategory("water")
	local waterfall = assert(FindSound(566760), "the catalog has an explicit waterfall in the water category")
	assert(not FindSound(4524098) and not FindSound(604807), "bridge wind and windmills are excluded from water")
	initialize(row, waterfall)
	assert(row.Detail.text:find(ns.L.MINIMAP_EMITTER_CATEGORY_WATER .. "   ·", 1, true) == 1,
		"an explicit filename is displayed without a guess marker")
	Search(ns.L.MINIMAP_EMITTER_CATEGORY_WATER)
	assert(FindSound(566760), "localized category names are searchable")
	SelectFilter(ns.L.RESET)
	assert(module.db.emitterSoundCategory == "all", "reset clears the category selection")
	Search("  7079224  ")
	assert(#results == 1 and results[1][1] == 7079224, "search finds an exact FileDataID")
	initialize(row, results[1])
	assert(row.Mute:GetChecked(), "saved mutes are visibly checked")
	window.MutedOnly:SetChecked(true)
	row.Mute:SetChecked(false)
	row.Mute:GetScript("OnClick")(row.Mute)
	assert(not muted[7079224] and next(module.db.mutedEmitters) == nil and #results == 0,
		"unmuting updates the client, saved selection and muted-only list")
	module.db.mutedEmitters[7386632] = true
	Search("")
	SelectCategory("unknown")
	assert(#results == 1 and results[1][1] == 7386632, "previously muted files outside the new catalog can still be unmuted")
	toggleBulk(bulk)
	assert(#results == 0 and not module.db.mutedEmitters[7386632], "bulk unmute refreshes the muted-only list")
	SelectFilter(ns.L.RESET)
	window.MutedOnly:SetChecked(false)
	Search("EXT-29_51 LOOPA")
	assert(FindSound(7139274), "search accepts multiple terms and mixed filename punctuation")
	Search("7139274")
	initialize(row, results[1])
	row.Preview:GetScript("OnClick")(row.Preview)
	assert(playing == 7139274, "reused rows preview the current file")
	window.StopPreview:GetScript("OnClick")(window.StopPreview)
	assert(not playing, "the stop button ends the audition")
	row.Preview:GetScript("OnClick")(row.Preview)
	row.Mute:SetChecked(true)
	row.Mute:GetScript("OnClick")(row.Mute)
	assert(not playing and muted[7139274] and module.db.mutedEmitters[7139274], "muting stops the preview and saves the selected file")
	module.db.emitterSoundMenu = false
	module:OnOptionChanged("emitterSoundMenu")
	assert(not trigger:IsShown() and not window:IsShown() and muted[7139274], "disabling the menu keeps active mutes")
	for _, key in ipairs(globals) do _G[key] = saved[key] end
	print("emitter sounds OK")
end)()
;(function()
	-- The stats pane rebuilds a provider from its original rows and reuses frames for new rows.
	local rank = ns:GetModule("StatRank")
	local savedWeights, savedEnabled = ns.StatWeights, rank.db.enabled
	local savedPane, savedScrollUtil, savedHook = CharacterStatsPaneScrollBox, ScrollUtil, hooksecurefunc
	local weights = CopyTable(upvalue(savedWeights, "WEIGHTS").PALADIN[2])
	weights.HIT, weights.CRIT = 8, 4
	ns.StatWeights = function() return weights end

	local function Stat(name, index)
		return { name = name, unit = "player", statIndex = index }
	end
	local health, strength, agility, stamina = Stat("HEALTH", 1), Stat("STRENGTH", 1), Stat("AGILITY", 2), Stat("STAMINA", 3)
	local intellect, spirit = Stat("INTELLECT", 4), Stat("SPIRIT", 5)
	local hit, crit, spell = Stat("HITCHANCE", 1), Stat("CRITCHANCE", 2), Stat("SPELLPOWER", 3)
	local defense, dodge, parry = Stat("DEFENSE", 1), Stat("DODGE", 2), Stat("PARRY", 3)
	local block, armor = Stat("BLOCK", 4), Stat("ARMOR", 5)
	local rows = {
		{ isHeader = true }, health,
		{ isHeader = true }, strength, agility, stamina, intellect, spirit,
		{ isHeader = true }, hit, crit, spell,
		{ isHeader = true }, defense, dodge, parry, block, armor,
	}
	local frames, initialized, provider = {}, nil, nil
	local function NewRow()
		local row = { color = { 1, 0.82, 0 }, value = "76", labelX = 11 }
		row.Label = {
			GetPoint = function() return "LEFT", row, "LEFT", row.labelX, 0 end,
			SetPoint = function(_, _, _, _, x) row.labelX = x end,
			GetTextColor = function() return unpack(row.color) end,
			SetTextColor = function(_, ...) row.color = { ... } end,
		}
		row.Background = { SetShown = function(_, on) row.stripe = on end }
		row.CreateFontString = function()
			return {
				SetPoint = function() end,
				SetFormattedText = function(_, f, n) row.number = f:format(n) end,
				SetTextColor = function(_, ...) row.numberColor = { ... } end,
				SetShown = function(_, on) row.numberShown = on end,
			}
		end
		return row
	end
	local box = {
		GetDataProvider = function() return provider end,
		ForEachFrame = function(_, fn)
			for index, data in ipairs(provider.collection) do
				fn(frames[index], data)
			end
		end,
	}
	local function Draw()
		for index, data in ipairs(provider.collection) do
			frames[index] = frames[index] or (data.isHeader and {} or NewRow())
			initialized(nil, frames[index], data)
		end
	end
	function box:SetDataProvider(new)
		provider = new
		Draw()
	end
	hooksecurefunc = function(object, method, fn)
		local original = object[method]
		object[method] = function(...)
			original(...)
			fn(...)
		end
	end
	ScrollUtil = { AddInitializedFrameCallback = function(_, fn) initialized = fn end }
	CharacterStatsPaneScrollBox = { ScrollBox = box, elementData = rows }
	rank.db.enabled = true
	rank:OnLogin()
	local function Rebuild()
		local collection = {}
		for index, data in ipairs(rows) do collection[index] = data end
		box:SetDataProvider({
			collection = collection,
			GetCollection = function() return collection end,
			Sort = function(_, cmp) table.sort(collection, cmp); Draw() end,
		})
	end
	Rebuild()
	local collection = provider.collection
	assert(rows[4] == strength and collection[4] == stamina and collection[5] == strength and collection[6] == agility,
		"sort the visible primary stats, preserving Blizzard's order for ties")
	assert(frames[4].number == "1." and frames[5].number == "2." and frames[6].number == "2." and frames[7].number == "4.",
		"equal positive weights share a place")
	assert(frames[4].labelX == 19 and frames[7].labelX == 19 and frames[8].labelX == 19 and frames[2].labelX == 11,
		"leave room before the labels for the rank numbers and align unweighted attributes")
	assert(frames[4].color[1] < 0.5 and frames[4].color[3] == 1 and frames[4].numberColor[1] == frames[4].color[1],
		"highest tier and its number use the same turquoise")
	assert(frames[5].color[1] == 1 and frames[7].color[1] < 1 and not frames[8].numberShown and frames[8].color[1] == frames[8].color[3],
		"separate colours for useful, minor and unweighted stats")
	assert(frames[4].stripe and not frames[5].stripe and frames[6].stripe and frames[4].value == "76",
		"row striping follows the new order and the stat value is untouched")
	assert(frames[10].number == "1." and frames[11].number == "2.", "rank visible hit and crit independently of hidden variants")
	assert(collection[15] == block and collection[16] == dodge and collection[17] == parry
		and frames[15].number == "1." and frames[16].number == "2." and frames[17].number == "2.",
		"rank block ahead of dodge and parry using the protection paladin item weights")
	assert(not frames[14].numberShown and frames[14].color[3] == 0 and frames[14].labelX == 19
		and not frames[18].numberShown and frames[18].color[3] == 0 and frames[18].labelX == 19,
		"weighted defense and armor are aligned and use the original label color")

	local items = ns:GetModule("Items")
	local onTalentChange = upvalue(ns.RegisterEvent, "listeners").TRAIT_CONFIG_UPDATED[items]
	local savedAfter = ns.After
	ns.After = function(_, _, fn) fn() end
	weights = { INT = 1, SPI = 0.6, STA = 0.3, SP = 0.8 }
	onTalentChange()
	ns.After = savedAfter
	assert(collection[4] == intellect and collection[5] == spirit and collection[6] == stamina and collection[7] == strength,
		"changing the talent weights reorders the open pane")
	assert(collection[9].isHeader and collection[12] == spell and not frames[7].numberShown,
		"categories and incomparable rows retain their slots")

	Rebuild()
	assert(provider.collection[4] == intellect, "a newly built provider is also sorted")
	rank.db.enabled = false
	rank:OnOptionChanged()
	assert(provider.collection[4] == strength and provider.collection[6] == stamina and frames[4].color[1] == 1
		and frames[4].color[3] == 0 and not frames[4].numberShown and frames[4].stripe and frames[4].labelX == 11,
		"disabling restores the stock rows")
	ns.StatWeights, rank.db.enabled = savedWeights, savedEnabled
	CharacterStatsPaneScrollBox, ScrollUtil, hooksecurefunc = savedPane, savedScrollUtil, savedHook
	print("stat rank OK")
end)()
;(function()
	-- Talent links of the calculators on the web: read by place, put onto the talents of the game
	local talents = ns:GetModule("Talents")
	assert(talents.IsLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/0ab1a2b0aaaac")
		and talents.IsLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-33Oy1~70888-0650090c")
		and not talents.IsLink("CYGAAAAAAAAAAAAAAAAAAAAAAA"), "what is a link")
	-- the two links made on the sites with the same clicks: Holy 5/1/1, Protection 1, Retribution second talent 1
	local trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/0ab1a2b0aaaac", "PALADIN")
	assert(trees[1][1] == 5 and trees[1][2] == 1 and trees[1][3] == 1 and trees[2][1] == 1 and trees[3][1] == 0 and trees[3][2] == 1, "Wowhead: digits by place")
	trees = talents.ParseLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-33Oy1~70888-0650090c", "PALADIN")
	assert(trees[1][1] == 2 and trees[1][2] == 1 and trees[2][1] == 1 and trees[3][2] == 1 and trees[3][1] == nil, "Icy Veins: one character per point")
	local _, reason = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/mage/vkndmh2_t0/0A", "PALADIN")
	assert(reason == "class", "another class")
	_, reason = talents.ParseLink("https://www.icy-veins.com/wow-forever/mage-talent-calculator#tc-33~70888-0650090c", "PALADIN")
	assert(reason == "class", "another class (Icy Veins)")
	_, reason = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkn_dmh", "PALADIN")
	assert(reason == "format", "no ranks in it")
	_, reason = talents.ParseLink("https://www.icy-veins.com/wow-forever/paladin-talent-calculator#tc-3Z", "PALADIN")
	assert(reason == "format", "a character that stands for no talent of the class")
	trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/mage/vkndmh2-05-003_t0/0A", "MAGE")
	assert(trees[1][1] == 2 and trees[2][2] == 5 and trees[3][3] == 3, "three trees")
	local ordered = { { { 11, 5 }, { 12, 5 }, { 13, 3 } }, { { 21, 5 } }, { { 31, 5 }, { 32, 5 } } }
	trees = talents.ParseLink("https://www.wowhead.com/forever/talent-calc/paladin/vkndmh511-1-01_t0/x", "PALADIN")
	assert(talents.LinkRanks(trees, ordered) == "11:5,12:1,13:1,21:1,32:1", "ranks on the talents of the game: " .. tostring(talents.LinkRanks(trees, ordered)))
	assert(talents.LinkRanks({ { 5, 5, 5 }, {}, {} }, ordered) == nil, "more ranks than the talent has: does not fit")
	assert(talents.LinkRanks({ {}, { 0, 1 }, {} }, ordered) == nil, "a place the tree does not have: does not fit")
	print("talent links OK")
end)()
;(function()
	-- Import the published Shaman path with the first three rows of the applicable client trees.
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local import = uv(menu, "ImportPlan")
	local importLink = uv(import, "ImportLink")
	local playerClass, playerClassName = uv(importLink, "playerClass"), uv(importLink, "playerClassName")
	local active = uv(menu, "ActiveBuild")
	local key = uv(uv(menu, "BuildList"), "PlanKey")
	local savedFrame, savedTraits, savedClassTalents, savedSpec = PlayerSpellsFrame, C_Traits, C_ClassTalents, C_SpecializationInfo
	local savedGroups, savedEdit, savedPrint = ns.TalentGroups, ns.ShowEditWindow, ns.Print
	local queue = uv(talents.QueuePlanUpdate, "QueuePlanUpdate")
	local savedAfter, savedPending = ns.After, uv(queue, "updatePending")
	setuv(queue, "updatePending", false)
	ns.After = function(_, _, fn) fn() end
	local savedSeq = talents.db.buildSeq
	local className = GetLocale() == "deDE" and "Schamane" or "Shaman"
	setuv(importLink, "playerClass", "SHAMAN")
	setuv(importLink, "playerClassName", className)
	local planKey = key()
	local savedPlans, savedActive = talents.db.builds[planKey], talents.cdb.activeBuild[planKey]
	talents.db.builds[planKey], talents.cdb.activeBuild[planKey] = nil, nil
	local buttons, nodes, groups = {}, {}, { { groupID = 1 }, { groupID = 2 }, { groupID = 3 } }
	for tree, layout in pairs({
		[2] = { { 104757, 0, 0, 2 }, { 104753, 0, 1, 5 }, { 104756, 0, 2, 5 }, { 104754, 1, 0, 2 },
			{ 104755, 1, 1, 3 }, { 104751, 1, 2, 3 }, { 104750, 2, 0, 3 }, { 104749, 2, 2, 1 } },
		[3] = { { 104739, 0, 1, 5 }, { 104729, 0, 2, 5 }, { 104734, 1, 0, 3 }, { 104736, 1, 1, 3 },
			{ 104735, 1, 2, 5 }, { 104737, 1, 3, 2 }, { 104731, 2, 0, 3 }, { 104733, 2, 1, 3 }, { 104732, 2, 2, 1 } },
	}) do
		for _, slot in ipairs(layout) do
			local id, row, col, maxRanks = unpack(slot)
			nodes[id] = { ID = id, posY = row * 600, posX = col * 600 + tree * 4000, maxRanks = maxRanks,
				ranksPurchased = 0, groupIDs = { tree } }
			local button = CreateFrame("Button")
			button.GetNodeID = function() return id end
			buttons[button] = true
		end
	end
	local bought, message = {}
	C_Traits = {
		GetNodeInfo = function(_, id) return nodes[id] end,
		GetConfigInfo = function() return nil end,
		PurchaseRank = function(_, id) bought[#bought + 1] = id; return true end,
	}
	C_ClassTalents = { GetActiveConfigID = function() return 1 end }
	C_SpecializationInfo = { HasPlayerEarnedATalentPoint = function() return true end }
	ns.TalentGroups = function() return groups end
	PlayerSpellsFrame = { TalentsFrame = {
		GetConfigID = function() return 1 end,
		IsVisible = function() return true end,
		EnumerateAllTalentButtons = function() return pairs(buttons) end,
	} }
	local url = "https://www.wowhead.com/forever/it/talent-calc/shaman/vkndmh-05203001-053020001_t0/"
	local function Import(suffix)
		ns.ShowEditWindow = function(_, _, _, _, accept) accept(url .. suffix) end
		ns.Print = function(text) message = text end
		import()
		return active()
	end
	local expected = "104729,104729,104729,104729,104729,104734,104734,104734,104735,104735,104732,"
		.. "104753,104753,104753,104753,104753,104755,104755,104755,104756,104756,104749"
	local plan = Import("2BCeej1BEcch?test=1#main")
	local name = className .. " (0/11/11)"
	assert(plan.name == name, "the import is named for the localized class and the point totals by tree")
	assert(ns.TalentBuilds.Points(plan) == 22 and table.concat(plan.order, ",") == expected and #bought == 0,
		"the exact Wowhead level order is stored, without buying any points")
	talents:ApplyPlan()
	assert(table.concat(bought, ",") == expected, "apply follows the Wowhead order")
	nodes[104729].ranksPurchased = 2
	plan = Import("2BCeej1BEcch")
	assert(plan.name == name .. " (2)", "reimporting keeps both plans and uses the full point distribution in the name")
	local remaining = expected:gsub("^104729,104729,", "")
	assert(table.concat(plan.order, ",") == remaining, "the first two ranks were already learned: " .. table.concat(plan.order, ","))
	nodes[104729].ranksPurchased = 0
	local inferred = table.concat(Import("").order, ",")
	assert(inferred ~= expected, "a rank-only link still gets an inferred order")
	assert(Import("2B").order[1] == 104729, "valid steps of a partial order precede inferred steps")
	assert(table.concat(Import("2Bbb").order, ",") == inferred and message == ns.L.TALENTS_LINK_ORDER_BAD,
		"an order exceeding the link's ranks falls back with a message")
	talents.db.builds[planKey], talents.cdb.activeBuild[planKey], talents.db.buildSeq = savedPlans, savedActive, savedSeq
	setuv(importLink, "playerClass", playerClass)
	setuv(importLink, "playerClassName", playerClassName)
	PlayerSpellsFrame, C_Traits, C_ClassTalents, C_SpecializationInfo = savedFrame, savedTraits, savedClassTalents, savedSpec
	ns.TalentGroups, ns.ShowEditWindow, ns.Print = savedGroups, savedEdit, savedPrint
	ns.After = savedAfter
	setuv(queue, "updatePending", savedPending)
	talents:QueuePlanUpdate()
	print("Wowhead talent order OK")
end)()
;(function()
	-- A choice on a step reached with "back" that gets no answer: the step comes again soon and says why.
	local dialog = ns:GetModule("Dialog")
	local savedCurrent, savedBubble = uv(dialog.Pending, "current"), uv(dialog.Pending, "bubble")
	local savedAfter, savedGossip, savedRerender = ns.After, GossipFrame, dialog.Rerender
	local waited, fire, redrawn
	ns.After = function(_, delay, fn) waited, fire = delay, fn end
	dialog.Rerender = function() redrawn = true end
	GossipFrame = { IsShown = function() return true end }
	local view = { kind = "GOSSIP_SHOW", stale = true, blocks = {} }
	setuv(dialog.Pending, "current", { view = view })
	setuv(dialog.Pending, "bubble", { pools = {}, IsShown = function() return true end })
	dialog.Pending()
	assert(waited and waited < 1, "a step from before comes back soon")
	fire()
	assert(redrawn and view.blocks[1].text == ns.L.DIALOG_NO_ANSWER, "it says that the choice got no answer")
	dialog.Pending()
	fire()
	assert(#view.blocks == 1, "said once")
	local live = { kind = "GOSSIP_SHOW", blocks = {} }
	setuv(dialog.Pending, "current", { view = live })
	dialog.Pending()
	assert(waited > 1, "the step the game is at waits as before")
	fire()
	assert(#live.blocks == 0, "and gets no note")
	ns.After, GossipFrame, dialog.Rerender = savedAfter, savedGossip, savedRerender
	setuv(dialog.Pending, "current", savedCurrent)
	setuv(dialog.Pending, "bubble", savedBubble)
	print("dialog choice without answer OK")
end)()
;(function()
	-- New ability: first free slot of the bars in order; none when all are full
	local qol = ns:GetModule("QoL")
	local used = { [1] = true, [2] = true, [61] = true }
	local has = function(slot) return used[slot] end
	assert(qol.FirstFreeSlot({ { 1, 2, 3 }, { 61, 62 } }, has) == 3, "main bar first")
	assert(qol.FirstFreeSlot({ { 1, 2 }, { 61, 62 } }, has) == 62, "then bar 2")
	assert(qol.FirstFreeSlot({ { 1, 2 }, { 61 } }, has) == nil, "all full")
	print("auto place slot OK")
end)()
;(function()
	-- Chat at the left edge: after Blizzard's insets pushed it, it goes back to its Edit Mode place
	local chat = ns:GetModule("Chat")
	local apply = uv(uv(uv(chat.OnLogin, "StyleAll"), "StyleChatFrame"), "HookEdges")
	apply = apply and uv(apply, "ApplyEdges")
	assert(apply, "ApplyEdges reachable")
	local insets = { -40, 0, 50, 0 }
	local anchored = 0
	local frame = { systemInfo = {}, GetLeft = function() return 0 end,
		GetClampRectInsets = function() return unpack(insets) end,
		SetClampRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end,
		ApplySystemAnchor = function() anchored = anchored + 1 end }
	local db = chat.db
	local saved = { db.chatEdges, db.hideButtons, InCombatLockdown }
	db.chatEdges, db.hideButtons = true, true
	InCombatLockdown = function() return false end
	apply(frame)
	assert(insets[1] == 0 and anchored == 1, "own insets, placed again")
	apply(frame)
	assert(anchored == 1, "unchanged insets: not placed again")
	db.chatEdges, db.hideButtons, InCombatLockdown = saved[1], saved[2], saved[3]
	print("chat edges reanchor OK")
end)()
;(function()
	-- Input line: a header Blizzard once narrowed to half the line gets its own width back
	local chat = ns:GetModule("Chat")
	local fix = uv(uv(uv(chat.OnLogin, "StyleAll"), "StyleChatFrame"), "StyleEditBox")
	fix = fix and uv(fix, "FixHeaderWidth")
	assert(fix, "FixHeaderWidth reachable")
	local width, textWidth, suffixShown, insets = 220, 40, false, nil
	local header = { GetWidth = function() return width end, GetStringWidth = function() return textWidth end,
		SetWidth = function(_, w) width = w == 0 and textWidth or w end }
	local box = { header = header, GetWidth = function() return 440 end,
		headerSuffix = { IsShown = function() return suffixShown end, Hide = function() suffixShown = false end },
		SetTextInsets = function(_, l) insets = l end }
	fix(box)
	assert(width == 40 and insets == 55, "header freed, text right after it")
	insets, width, suffixShown = nil, 221, true
	fix(box)
	assert(width == 40 and not suffixShown and insets == 55, "short text with stuck suffix: freed too")
	insets, width, textWidth, suffixShown = nil, 220, 300, true
	fix(box)
	assert(width == 220 and suffixShown and insets == nil, "really long header keeps Blizzard's shortening")
	textWidth, width, suffixShown = 40, 40, false
	fix(box)
	assert(insets == nil, "fitting header untouched")
	print("chat input header OK")
end)()
;(function()
	-- Auction sell frame: one large line, the calculation for the tooltip
	local A = ns:GetModule("Auction")
	local saved = GetMoneyString
	GetMoneyString = function(v) return tostring(v) .. "c" end
	local s = A.SellSummary(306, 400, true, true)
	assert(s.text == ns.L.AUCTION_SELL_PROFIT:format("+74c"), "profit: " .. s.text)
	assert(#s.lines == 4 and s.lines[3]:find("380c", 1, true), "formula with net price")
	s = A.SellSummary(306, 300, true, true)
	assert(s.text == ns.L.AUCTION_SELL_BELOW:format("−21c") and #s.lines == 5, "warning large, details in tooltip")
	s = A.SellSummary(306, 300, true, false)
	assert(s.text == ns.L.AUCTION_SELL_LOSS:format("−21c"), "loss without warning option")
	assert(A.SellSummary(306, 400, false, true) == nil, "only warning option, price fine: nothing")
	assert(A.SellSummary(306, nil, true, false).text == ns.L.AUCTION_SELL_NO_PRICE, "no price yet")
	assert(A.SellSummary(nil, 400, true, true) == nil, "no merchant price")
	GetMoneyString = saved
	print("auction sell summary OK")
end)()
;(function()
	-- Chat with hanging indent: continuation lines start with blanks as wide as the timestamp.
	local indent = ns:GetModule("ChatIndent")
	assert(indent and indent.Wrap, "chat indent module")
	local measureBefore, fn = indent.measure, uv(indent.Wrap, "PrepareMeter")
	indent.measure = function(text) return #(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
	-- meter is created on demand from the hider frame; the mock is lenient, so only the key matters here
	local frame = { GetWidth = function() return 60 end, GetFontObject = function() return nil end }
	ChatFrameUtil = { GetTimestampFormat = function() return "%H:%M " end }
	TimeUtil = { BetterDate = function(format, t) return os.date(format, t) end }
	local message = "12:34 aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll"
	local ok, wrapped = pcall(indent.Wrap, frame, message)
	assert(ok, tostring(wrapped))
	if wrapped then
		local first, second = wrapped:match("^(.-)\n(.*)$")
		assert(first and second:sub(1, 6) == "      ", "continuation indented by the timestamp: " .. wrapped)
		assert(not indent.Wrap({ GetWidth = function() return 400 end, GetFontObject = function() return nil end }, message), "short text unchanged")
		local savedAfter, enabled = C_Timer.After, indent.db.enabled
		local nextMessage = message .. " mmmm nnnn oooo"
		local history, queued, timers, scans = { message, nextMessage, message }, nil, 0, 0
		C_Timer.After = function(_, fn) queued, timers = fn, timers + 1 end
		frame.TransformMessages = function(_, predicate, transform)
			scans = scans + 1
			for i, text in ipairs(history) do
				if predicate(text) then
					history[i] = transform(text)
				end
			end
		end
		local add = uv(uv(indent.Apply, "Hook"), "OnAddMessage")
		indent.db.enabled = true
		for _, text in ipairs(history) do add(frame, text) end
		assert(timers == 1 and scans == 0, "the burst queues one history pass")
		queued()
		assert(scans == 1 and history[1] == wrapped and history[3] == wrapped and history[2] == indent.Wrap(frame, nextMessage),
			"the single history pass wraps both distinct messages and the duplicate")
		C_Timer.After, indent.db.enabled = savedAfter, enabled
		print("chat indent OK")
	else
		error("chat indent: no wrap")
	end
	indent.measure = measureBefore
	assert(fn, "meter set-up reachable")
end)()
;(function()
	-- Talent plan as Blizzard's loadout text: same bit layout the game reads back.
	local talents = ns:GetModule("Talents")
	local menu = uv(uv(uv(talents.OnLogin, "SetupPlanner"), "CreatePlanBar"), "ShowBuildMenu")
	local ExportPlan = menu and uv(menu, "ExportPlan")
	local LoadoutString = ExportPlan and uv(ExportPlan, "LoadoutString")
	assert(LoadoutString, "loadout writer reachable")
	local bits = {}
	ExportUtil = { MakeExportDataStream = function()
		return { AddValue = function(_, width, value) bits[#bits + 1] = { width, value } end, GetExportString = function() return "ok" end }
	end }
	C_Traits = { GetLoadoutSerializationVersion = function() return 2 end, GetTreeHash = function() return { 1, 2 } end,
		GetTreeNodes = function() return { 10, 11, 12, 13 } end,
		GetNodeInfo = function(_, id)
			local nodes = {
				[10] = { maxRanks = 5, ranksPurchased = 0, activeRank = 1 },   -- granted
				[11] = { maxRanks = 5, ranksPurchased = 0, activeRank = 0 },   -- wanted 5: full
				[12] = { maxRanks = 3, ranksPurchased = 0, activeRank = 0 },   -- wanted 2: partial
				[13] = { maxRanks = 1, ranksPurchased = 0, activeRank = 0 },   -- not wanted
			}
			return nodes[id]
		end }
	PlayerUtil = { GetCurrentSpecID = function() return 7 end }
	local frame = { GetConfigID = function() return 1 end, GetTreeInfo = function() return { ID = 77 } end, GetSpecID = function() return 7 end }
	assert(LoadoutString(frame, { [11] = 5, [12] = 2 }) == "ok")
	-- header: version, spec, two hash bytes; then per node: selected [purchased [partial [ranks] choice]]
	local flat = {}
	for _, bit in ipairs(bits) do flat[#flat + 1] = bit[1] .. ":" .. bit[2] end
	local text = table.concat(flat, " ")
	assert(text == "8:2 16:7 8:1 8:2 1:1 1:0 1:1 1:1 1:0 1:0 1:1 1:1 1:1 6:2 1:0 1:0", text)
	-- Import: the build lands in the plan (granted ranks are not counted), nothing is learned.
	local ImportPlan = uv(menu, "ImportPlan")
	assert(ImportPlan, "import reachable")
	local callback
	local oldShow, oldPrint = ns.ShowEditWindow, ns.Print
	ns.ShowEditWindow = function(_, _, _, _, onAccept) callback = onAccept end
	local printed
	ns.Print = function(...) printed = { ... } end
	for i = 1, 60 do
		local name = debug.getupvalue(ImportPlan, i)
		if name == "ParseBuild" then
			debug.setupvalue(ImportPlan, i, function()
				return { { nodeID = 11, ranksPurchased = 3 }, { nodeID = 11, ranksPurchased = 4 }, { nodeID = 10, ranksPurchased = 0, ranksGranted = 1 }, { nodeID = 12, ranksPurchased = 2 } }
			end)
		end
	end
	PlayerSpellsFrame = { TalentsFrame = frame }
	ImportPlan()
	assert(callback, "import window")
	talents.db.planner = true
	callback("  abc  ")
	local plan = talents:CurrentPlan()
	assert(plan[11] == 5 and plan[12] == 2 and plan[10] == nil, "plan from the import (capped at the maximum ranks)")
	assert(printed and printed[2] == 7 and printed[3] == 2 and printed[4] == 16, "report: points, talents, level")
	ns.ShowEditWindow, ns.Print = oldShow, oldPrint
	print("talent loadout string OK")
end)()
;(function()
	-- Restock: tops up a marked item to a full stack from the bank.
	local r = ns:GetModule("Restock")
	r.cdb.items = { [2589] = true }
	local bags = { [0] = { [1] = { itemID = 2589, stackCount = 7 } }, [6] = { [3] = { itemID = 2589, stackCount = 30 } } }
	C_Container.GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end
	C_Container.GetContainerNumFreeSlots = function() return 3, 0 end
	local calls = {}
	C_Container.SplitContainerItem = function(bag, slot, n) calls[#calls + 1] = ("split %d %d %d"):format(bag, slot, n) end
	C_Container.PickupContainerItem = function(bag, slot) calls[#calls + 1] = ("pickup %d %d"):format(bag, slot) end
	C_Item.GetItemMaxStackSizeByID = function() return 20 end
	C_Item.GetItemCount = function() return 7 end
	C_Bank = { CanUseBank = function(t) return t == 0 end, FetchPurchasedBankTabIDs = function() return { 6 } end }
	Enum.BankType = { Character = 0, Account = 2 }
	GetCursorInfo = function() return nil end
	local Step = uv(uv(r.Apply, "Start"), "Step")
	local MoveOne = uv(Step, "MoveOne")
	setuv(MoveOne, "atBank", true)
	setuv(MoveOne, "run", { skip = {}, moved = {}, steps = 0 })
	assert(MoveOne(), "one move")
	print("  ", table.concat(calls, " | "))
	assert(calls[1] == "split 6 3 13" and calls[2] == "pickup 0 1", "13 from the bank onto the stack of 7")
	C_Item.GetItemCount = function() return 20 end
	assert(not MoveOne(), "full stack: nothing left")
	-- the other way round: marked for the bank, the bag stack goes onto the bank stack with room
	r.cdb.items = { [2589] = "bank" }
	bags[6][3] = { itemID = 2589, stackCount = 5 }
	calls = {}
	setuv(MoveOne, "run", { skip = {}, moved = {}, stored = {}, steps = 0 })
	assert(MoveOne() and calls[1] == "pickup 0 1" and calls[2] == "pickup 6 3", "bag stack onto the bank stack")
	r.cdb.items = {}
	setuv(MoveOne, "run", nil)
	setuv(MoveOne, "atBank", false)
	local update = uv(r.OnLogin, "PostUpdateItems")
	local savedItemID, itemIDReads = C_Container.GetContainerItemID, 0
	C_Container.GetContainerItemID = function()
		itemIDReads = itemIDReads + 1
		return 2589
	end
	local textures, atlasUpdates = {}, 0
	local button = NewFrame("Button")
	button.GetBagID, button.GetID = function() return 0 end, function() return 1 end
	button.CreateTexture = function()
		local texture = NewFrame("Texture")
		texture.SetAtlas = function() atlasUpdates = atlasUpdates + 1 end
		textures[#textures + 1] = texture
		return texture
	end
	local frame = { EnumerateValidItems = function() return ipairs({ button }) end }
	update(frame)
	assert(itemIDReads == 0 and button:GetScript("OnMouseUp"), "empty restock list still hooks marking without reading slots")
	r.cdb.items[2589] = true
	update(frame)
	update(frame)
	assert(itemIDReads == 2 and textures[1]:IsShown() and atlasUpdates == 1, "the same mark keeps its existing texture")
	r.cdb.items[2589] = nil
	update(frame)
	assert(itemIDReads == 2 and not textures[1]:IsShown() and not textures[2]:IsShown(), "removing the last mark clears its textures")
	C_Container.GetContainerItemID = savedItemID
	print("restock OK")
end)()
;(function()
	-- Quest preview: open objectives on the map, turn-in once they are done.
	local spawns = { [6] = { [12] = { { 40, 80 } } }, [7] = { [12] = { { 30, 30 }, { 31, 31 } } }, [20] = { [40] = { { 50, 50 } } },
		[30] = { [12] = { { 60, 60 } } } }
	local quest = { objectives = { { { 6, nil, 0 } }, nil, { { 750, nil, 0 } }, nil, { { { 20, 21 }, 22, nil, 0 } } },
		finishedBy = { { 30 } } }
	LibQuestieDB = {
		Support = { Get = function() return { private = { areaIdToUiMapId = { [12] = 1429, [40] = 1436 } } } end },
		Quest = { Exists = function(id) return id == 33 end, Get = function(_, key) return quest[key] end, GetAll = function() end, GetAllIds = function() return {} end },
		Npc = { Get = function(id, key) if key == "spawns" then return spawns[id] end if key == "name" then return id == 30 and "Marschall" end end },
		Item = { Get = function(id, key) return id == 750 and key == "npcDrops" and { 7 } or nil end },
		Object = { Get = function() end },
	}
	setuv(ns.QuestieDB.UiMapForArea, "areaToUiMap", nil)
	local objectives = { { type = "monster", text = "Kobold: 10/10", finished = true }, { type = "item", text = "Kerze: 0/8", finished = false },
		{ type = "monster", text = "Mine erkundet: 0/1", finished = false } }
	C_QuestLog.GetQuestObjectives = function() return objectives end
	C_QuestLog.GetTitleForQuestID = function() return "Koboldlager" end
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(id) return { name = id == 1429 and "Wald von Elwynn" or "Westfall" } end
	C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
	C_Map.GetMapArtLayerTextures = function() local t = {} for i = 1, 12 do t[i] = 100 + i end return t end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	C_MapExplorationInfo = { GetExploredMapTextures = function() return {} end }
	GameTooltip = CreateFrame("GameTooltip")
	ns:GetModule("WorldMap").db.reveal = false
	local P = ns.QuestPreview
	local build, bodyText = uv(P.Show, "Build"), uv(P.Show, "BodyText")
	local model = build(33)
	assert(#model.maps[1429] == 2 and #model.maps[1436] == 1 and not model.turnIn, "item drops in Elwynn, kill credit in Westfall")
	assert(uv(P.Show, "ChooseMap")(model.maps) == 1429, "player's map first")
	local text = bodyText(model, 1429)
	print("  ", (text:gsub("\n", " / ")))
	assert(text:find("Kerze") and text:find("Westfall"), "objectives and other zone")
	P.Show(CreateFrame("Frame"), 33)
	local release = uv(P.Show, "ReleaseAll")
	assert(uv(release, "mapUsed") == 12 and uv(release, "markUsed") == 5, "12 map tiles, 2 dots with rings, player arrow")
	for _, objective in ipairs(objectives) do objective.finished = true end
	model = build(33)
	assert(model.turnIn and #model.maps[1429] == 1 and model.turnInName == "Marschall", "turn-in")
	assert(bodyText(model, 1429):find("Marschall"), "turn-in line")
	P.Hide()
	print("quest preview OK")
end)()

;(function()
	-- World map symbols: instance entrances from the group finder list, flight masters and inns of the own faction,
	-- town and city names, recipe vendors.
	local wm = ns:GetModule("WorldMap")
	local S = ns.MapSymbols
	ns:GetModule("Library").db.symbols = false
	local dungeons = { [1581] = { "The Deadmines", nil, 40, { { 40, 42.5, 71.7 } } }, [1584] = { "Blackrock Depths", nil, 51, { { 51, 34.8, 85.3 } } },
		[2717] = { "Molten Core", nil, 51, { { 51, 35, 85 } } }, [2366] = { "The Black Morass", nil, 440, { { 440, 65.7, 49.8 } } } }
	local npcs = { [523] = { name = "Thor", subName = "Greifenmeister", npcFlags = 11, friendlyToFaction = "A", spawns = { [40] = { { 56.6, 52.6 } } } },
		[2995] = { name = "Tal", npcFlags = 11, friendlyToFaction = "H", spawns = { [40] = { { 10, 10 } } } },
		[100] = { name = "Händler", npcFlags = 4, friendlyToFaction = "A", spawns = { [40] = { { 20, 20 } } } },
		[8931] = { name = "Gastwirtin Heather", subName = "Gastwirtin", raw = "Innkeeper", npcFlags = 135, friendlyToFaction = "A", spawns = { [40] = { { 52.9, 53.7 } } } },
		[1460] = { name = "Unger Statforth", subName = "Pferdezüchter", raw = "Horse Breeder", npcFlags = 135, friendlyToFaction = "A", spawns = { [40] = { { 30, 30 } } } } }
	LibQuestieDB = {
		Support = { Get = function() return { private = { dungeons = dungeons, areaIdToUiMapId = { [40] = 1436, [51] = 1427, [440] = 1446 } },
			instanceIdToAreaId = { [36] = 1581, [230] = 1584, [409] = 2717, [269] = 2366 } } end },
		Quest = { Exists = function() return false end, Get = function() end, GetAll = function() end, GetAllIds = function() return {} end },
		Npc = { GetAllIds = function() return { 100, 523, 2995, 8931, 1460 } end, Get = function(id, key) return npcs[id] and npcs[id][key] end,
			GetRaw = function(id, key) return key == "subName" and npcs[id] and npcs[id].raw end },
	}
	setuv(ns.QuestieDB.UiMapForArea, "areaToUiMap", nil)
	ns.Instances = { [36] = "dungeon", [230] = "dungeon", [409] = "raid" }
	ns.Places = { { 0, -9480, 63, 87, "Goldshire", "town", 1429 }, { 0, -9154, 364, 1519, "Stormwind", "city", 1453 },
		{ 1, 1, 1, 0, "Razor Hill", "town", 1411 } }
	GetRealZoneText = function(id) return id == 36 and "Die Todesminen" or "" end
	UnitFactionGroup = function() return "Alliance" end
	CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
	C_Timer.NewTicker = function(_, fn) local t = { Cancel = function(self) self.dead = true end } repeat fn(t) until t.dead return t end
	local canvas = CreateFrame("Frame")
	canvas.GetWidth = function() return 1000 end
	canvas.GetHeight = function() return 600 end
	local mapID = 1436
	WorldMapFrame = CreateFrame("Frame")
	WorldMapFrame.GetCanvas = function() return canvas end
	WorldMapFrame.GetCanvasScale = function() return 2 end
	WorldMapFrame.GetMapID = function() return mapID end
	WorldMapFrame.EnumeratePinsByTemplate = function() return function() end end
	C_Map.GetMapInfo = function(id) return { mapType = id == 1415 and 2 or 3 } end
	C_Map.GetMapChildrenInfo = function() return { { mapID = 1436 }, { mapID = 1427 }, { mapID = 1429 } } end
	C_Map.GetMapRectOnMap = function(child) if child == 1436 then return 0.4, 0.5, 0.7, 0.8 end return 0.5, 0.6, 0.5, 0.6 end
	C_Map.GetWorldPosFromMapPos = function() return 0, CreateVector2D(0, 0) end
	-- Without a map the client answers with the continent (seen in the game: towns were missing).
	C_Map.GetMapPosFromWorldPos = function(_, pos, override)
		if override == 1429 then return 1429, CreateVector2D(pos.x == -9480 and 0.42 or 0.2, pos.x == -9480 and 0.66 or 0.2) end
		if override == 1415 then return 1415, CreateVector2D(0.45, 0.75) end
		if override == 1453 then return 1453, CreateVector2D(0.5, 0.5) end
		return override or 1415, CreateVector2D(1.5, 1.5) -- outside the map
	end
	C_Map.GetAreaInfo = function(id) return id == 87 and "Goldhain" or id == 1519 and "Sturmwind" or "" end
	Enum.UIMapType = { World = 1, Continent = 2, Zone = 3 }
	ns:GetModule("RecipeRadar").db.worldMap = false
	-- The earlier world map test set up the layer on its own map mock.
	local refresh = S.Refresh
	local draw = uv(refresh, "Draw")
	setuv(refresh, "layer", nil)
	setuv(refresh, "entrances", nil)
	setuv(uv(refresh, "BuildNpcs"), "npcs", nil)
	for _, source in ipairs(uv(uv(S.Count, "Collect"), "sources")) do
		local continent, place = uv(source, "Continent"), uv(source, "PlacePosition")
		if continent then setuv(continent, "continents", {}) end
		if place then setuv(place, "positions", {}) end
	end
	for k in pairs({ entrances = 1, flightPoints = 1, inns = 1, places = 1 }) do wm.db[k] = true end
	wm:Apply()
	local function active()
		local list, frames = {}, uv(draw, "frames")
		for i = 1, uv(draw, "used") do list[#list + 1] = frames[i].symbol end
		return list
	end
	local function kinds(list)
		local count = {}
		for _, symbol in ipairs(list) do count[symbol.kind] = (count[symbol.kind] or 0) + 1 end
		return count
	end
	local list = active()
	local count = kinds(list)
	assert(#list == 3 and count.entrance == 1 and count.flight == 1 and count.inn == 1, "Westfall: Deadmines, Thor, inn; got " .. #list)
	assert(list[1].data.names[1][1] == "Die Todesminen", "client name")
	assert(list[2].data.name == "Thor" and math.abs(list[2].x - 0.566) < 1e-9, "own faction only")
	assert(list[3].data.name == "Gastwirtin Heather", "innkeeper by base title, not the horse breeder")
	mapID = 1415
	draw()
	list = active()
	count = kinds(list)
	assert(count.entrance == 2 and count.flight == 2 and not count.inn and count.place == 1, "continent: zones' symbols, the capital, no inns")
	for _, symbol in ipairs(list) do
		if symbol.kind == "place" then assert(symbol.label == "Sturmwind" and symbol.x == 0.45, "capital on the continent") end
		if symbol.kind == "flight" and symbol.data.name == "Thor" then assert(math.abs(symbol.x - (0.4 + 0.566 * 0.1)) < 1e-9, "zone rect on continent") end
		if symbol.kind == "entrance" and #symbol.data.names == 2 then
			local k = {}
			for _, entry in ipairs(symbol.data.names) do k[entry[2]] = true end
			assert(k.raid and k.dungeon and symbol.atlas == "dungeon", "Blackrock Depths and Molten Core share a symbol")
		end
	end
	local savedLocale, savedLocales = GetLocale, {}
	for _, key in ipairs({ "WORLDMAP_FLIGHT", "WORLDMAP_FLIGHT_LOCATION", "WORLDMAP_FLIGHT_PLACES",
		"WORLDMAP_FLIGHT_TITLES", "WORLDMAP_FLIGHT_MASTERS" }) do
		savedLocales[key] = ns.L[key]
	end
	local german = { L = {} }
	GetLocale = function() return "deDE" end
	assert(loadfile(root .. "/Locales/deDE.lua"))("ForeverPlus", german)
	for key in pairs(savedLocales) do ns.L[key] = german.L[key] end
	local savedMapInfo, savedAreaInfo = C_Map.GetMapInfo, C_Map.GetAreaInfo
	C_Map.GetMapInfo = function(id) return id == 1425 and { name = "Hinterland", mapType = 3 } or savedMapInfo(id) end
	C_Map.GetAreaInfo = function(id) return id == 348 and "Nistgipfel" or savedAreaInfo(id) end
	local bundledFlights = uv(uv(refresh, "BuildNpcs"), "BundledFlights")
	local guthrum = bundledFlights("A")[1425][1]
	assert(guthrum.name == "Guthrum Thunderfist" and guthrum.title == "Greifenmeister"
		and guthrum.node == "Nistgipfel, Hinterland", "German flight tooltip uses localized role, settlement and zone")
	assert(bundledFlights("H")[1441][1].title == "Windreitermeisterin", "German title for Nyse")
	GetLocale, C_Map.GetMapInfo, C_Map.GetAreaInfo = savedLocale, savedMapInfo, savedAreaInfo
	for key, value in pairs(savedLocales) do ns.L[key] = value end
	mapID = 1429
	draw()
	list = active()
	local labels = {}
	for _, symbol in ipairs(list) do if symbol.label then labels[symbol.label] = symbol end end
	assert(labels.Goldhain and labels.Sturmwind and labels.Sturmwind.x == 0.2, "town and capital names on the zone map")
	mapID = 1453
	draw()
	assert(kinds(active()).place == nil, "no capital name on its own city map")
	wm.db.flightPoints, wm.db.inns, wm.db.places = false, false, false
	wm:OnOptionChanged("flightPoints", false)
	mapID = 1436
	draw()
	assert(#active() == 1, "flight points and inns off")
	local counts = S.Count(1436)
	assert(counts.entrance == 1, "count")
	-- Recipe vendors: round icons with their own click (waypoint).
	local radar = ns:GetModule("RecipeRadar")
	radar.db.worldMap = true
	local itemCount = C_Item.GetItemCount
	C_Item.GetItemCount = function() return 0 end -- earlier tests leave a count; a recipe in the bags counts as collected
	local getVendors
	for _, source in ipairs(uv(uv(S.Count, "Collect"), "sources")) do
		local ok, found = pcall(uv, source, "GetVendors")
		if ok and found then getVendors = source end
	end
	local vendorMap
	for id, list in pairs(uv(uv(getVendors, "GetVendors"), "vendorsByMap")) do if #list > 0 then vendorMap = id break end end
	mapID = vendorMap
	draw()
	local radarSymbol
	for _, symbol in ipairs(active()) do if symbol.kind == "radar" then radarSymbol = symbol end end
	print("  radar symbols on map", vendorMap, S.Count(vendorMap).radar)
	assert(radarSymbol and radarSymbol.round and radarSymbol.click and radarSymbol.mapID == vendorMap, "radar symbol")
	local fillTooltip = uv(radarSymbol.tooltip, "FillVendorTooltip")
	local npcTitle = uv(fillTooltip, "NpcTitle")
	local npcName = uv(fillTooltip, "NpcName")
	local savedDB = uv(npcTitle, "DB")
	setuv(npcTitle, "DB", nil)
	assert(npcName(5494) == "Catherine Leland", "bundled name without QuestieDB")
	local isGerman = GetLocale() == "deDE"
	local fishingTitle = isGerman and "Angelbedarf" or "Fishing Supplier"
	assert(npcTitle(5494) == fishingTitle, "local fishing supplier title")
	assert(npcTitle(4223) == (isGerman and "Kochbedarf" or "Cooking Supplies"), "later era title excluded")
	setuv(npcTitle, "DB", { Npc = { Get = function(id, field)
		if id == 5494 and field == "name" then return "Localised vendor name" end
		if id == -1 and field == "subName" then return "Fishing Supplier" end
	end } })
	assert(npcName(5494) == "Localised vendor name", "prefer QuestieDB's localised name")
	assert(npcName(4223) == "Fyldan", "use the bundled name when QuestieDB has none")
	assert(npcTitle(-1) == fishingTitle, "QuestieDB's English title can also be translated")
	setuv(npcTitle, "DB", savedDB)
	C_Item.GetItemCount = itemCount
	radar.db.worldMap = false
	print("world map symbols OK")
end)()
;(function()
	local map = ns:GetModule("WorldMap")
	local collect = uv(ns.MapSymbols.Count, "Collect")
	local savedLog, savedCVar, savedBundled = C_QuestLog, GetCVarBool, ns.QuestieDB.Bundled
	local blizzard, open, ready = false, true, true
	local quests = {
		{ questID = 1, title = "Ready A" }, { questID = 2, title = "Ready B" }, { questID = 3, title = "In progress" },
		{ questID = 4, title = "Failed" }, { questID = 5, title = "Fallback" }, { questID = 6, title = "Talk to someone" },
		{ questID = 7, title = "Remote turn-in", isAutoComplete = true },
	}
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #quests end,
		GetInfo = function(index) if index ~= 1 or open then return quests[index] end end,
		ReadyForTurnIn = function(id) return id ~= 3 and (id ~= 1 or ready) end,
		IsFailed = function(id) return id == 4 end,
		GetQuestsOnMap = function(mapID)
			if mapID == 1436 then
				return {
					{ questID = 1, x = 0.3, y = 0.4 }, { questID = 2, x = 0.3, y = 0.4 },
					{ questID = 3, x = 0.5, y = 0.4 }, { questID = 4, x = 0.5, y = 0.4 },
					{ questID = 5, x = 0, y = 0 }, { questID = 6, x = 0.6, y = 0.6 },
					{ questID = 7, x = 0.5, y = 0.4 }, { questID = 2, x = 0.5, y = 0.4, isQuestStart = true },
					{ questID = 2, x = 0.5, y = 0.4, isMapIndicatorQuest = true },
				}
			end
		end,
		IsQuestFlaggedCompleted = function() return false end,
		GetLogIndexForQuestID = function() return nil end,
	}
	ns.QuestieDB.Bundled = function()
		return { Quest = { Get = function(id, field)
			assert(field == "turnInPoint", "only hand-in data may supply the fallback")
			if id == 1 or id == 5 then return { { 1436, 70, 80 }, { 1436, 70, 80 } } end
		end } }
	end
	GetCVarBool = function(key) return key == "questPOI" and blizzard end
	local savedBoards, savedOption = GetNumQuestLeaderBoards, map.db.questTurnIns
	GetNumQuestLeaderBoards = function(index) return index ~= 6 and 1 or 0 end
	local function pins(mapID)
		local result = {}
		for _, pin in ipairs(collect(mapID)) do
			if pin.kind == "questTurnIn" then result[#result + 1] = pin end
		end
		table.sort(result, function(a, b) return a.x < b.x end)
		return result
	end
	assert(savedOption, "the filter is on by default")
	local list = pins(1436)
	assert(#list == 2 and list[1].atlas == "QuestTurnin" and list[1].x == 0.3 and list[1].y == 0.4
		and table.concat(list[1].data, ", ") == "Ready A, Ready B", "client coordinates and one pin per shared hand-in location")
	assert(list[2].x == 0.7 and list[2].y == 0.8 and table.concat(list[2].data) == "Fallback", "only the missing client point uses the bundled fallback")
	list = pins(1415)
	assert(#list == 1 and math.abs(list[1].x - 0.47) < 1e-9 and math.abs(list[1].y - 0.78) < 1e-9, "zone point on continent map")
	ready = false
	assert(table.concat(pins(1436)[1].data) == "Ready B", "the pin clears when the objectives are no longer complete")
	ready, open = true, false
	assert(table.concat(pins(1436)[1].data) == "Ready B", "the pin clears when the quest leaves the log")
	blizzard = true
	assert(#pins(1436) == 0, "Blizzard's quest filter avoids a duplicate overlay")
	blizzard, map.db.questTurnIns = false, false
	assert(#pins(1436) == 0, "the hand-in filter can be turned off independently")
	map.db.questTurnIns, GetNumQuestLeaderBoards = savedOption, savedBoards
	C_QuestLog, GetCVarBool, ns.QuestieDB.Bundled = savedLog, savedCVar, savedBundled
	print("quest turn-in pins OK")
end)()
assert(loadfile("quest_calendar.lua"))(ns, uv, setuv)
;(function()
	local wm, symbols = ns:GetModule("WorldMap"), ns.MapSymbols
	local db, collect = wm.db, uv(symbols.Count, "Collect")
	local savedFaction, savedComplete, savedLib = UnitFactionGroup, C_QuestLog.IsQuestFlaggedCompleted, ns.QuestieDB.Get
	local savedCount, savedJournal, savedRefresh = C_Item.GetItemCount, rawget(_G, "C_PetJournal"), symbols.Refresh
	local savedMarks = wm.cdb.collectedDiscoveries
	local marks, faction, completed, items, pets, redraws = {}, "Alliance", {}, {}, {}, 0
	wm.cdb.collectedDiscoveries = marks
	UnitFactionGroup = function() return faction end
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return completed[id] end
	C_Item.GetItemCount = function(id) return items[id] and 1 or 0 end
	C_PetJournal = { GetNumPetsInJournal = function(id) return 3, pets[id] and 1 or 0 end }
	symbols.Refresh = function() redraws = redraws + 1 end
	ns.QuestieDB.Get = function() return nil end
	local events = uv(ns.RegisterEvent, "listeners")
	local function fire(event, id) events[event][wm](wm, event, id) end
	local function pins(mapID)
		local result = {}
		for _, pin in ipairs(collect(mapID)) do
			if pin.kind == "discovery" then result[#result + 1] = pin end
		end
		return result
	end
	assert(db.discoveries == false, "discoveries are opt-in")
	for mapID in pairs(ns.MapDiscoveries) do
		assert(#pins(mapID) == 0, "the default filter hides every discovery")
	end
	db.discoveries = true
	local loch = pins(1432)
	assert(#loch == 7 and loch[1].x == 0.457 and loch[1].y == 0.433, "the toolbox, dam and hatchling, without QuestieDB")
	local lines = {}
	local tooltip = { AddLine = function(_, line) lines[#lines + 1] = line end }
	local savedInstruction = GameTooltip_AddInstructionLine
	GameTooltip_AddInstructionLine = tooltip.AddLine
	loch[1].tooltip(tooltip, loch[1])
	assert(lines[1] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER and lines[2] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER_TOOLBOX
		and lines[3] == ns.L.WORLDMAP_DISCOVERY_POSSIBLE:format(45.7, 43.3), "localized hint and possible coordinates")
	assert(lines[4] == ns.L.WORLDMAP_DISCOVERY_WAYPOINT_CLICK and lines[5] == ns.L.WORLDMAP_DISCOVERY_MARK,
		"the tooltip shows both mouse actions")
	assert(#pins(1415) == 0 and #pins(1447) == 1 and #pins(2521) == 3, "discoveries appear on their own zone maps")
	local waypoint = ns:GetModule("Waypoint")
	local savedSetOnMap, savedPrint = waypoint.SetOnMap, ns.PrintAlways
	local goal, message
	waypoint.SetOnMap = function(mapID, x, y, name)
		goal = { mapID, x, y, name }
		return true
	end
	loch[2].click(loch[2], "LeftButton")
	assert(goal and goal[1] == 1432 and goal[2] == 48 and goal[3] == 40 and goal[4] == ns.L.WORLDMAP_DISCOVERY_TEXT.SILVER,
		"left click sets a named waypoint at the selected possible location")
	assert(#pins(1432) == 7 and redraws == 0, "setting a waypoint leaves the discovery open")
	waypoint.SetOnMap = function() return false end
	ns.PrintAlways = function(text) message = text end
	loch[1].click(loch[1], "LeftButton")
	assert(message == ns.L.WAYPOINT_NOT_HERE and not marks.silver, "an unavailable waypoint reports the failure without marking the find")
	db.discoveryWaypoint = false
	message, lines = nil, {}
	loch[1].click(loch[1], "LeftButton")
	loch[1].tooltip(tooltip, loch[1])
	assert(not message and #lines == 4 and lines[4] == ns.L.WORLDMAP_DISCOVERY_MARK,
		"turning off discovery waypoints disables left click and its tooltip hint")
	loch[1].click(loch[1], "RightButton")
	assert(marks.silver == "manual" and #pins(1432) == 3 and redraws == 1, "right click hides all alternative positions")
	db.discoveryWaypoint = true
	waypoint.SetOnMap, ns.PrintAlways, GameTooltip_AddInstructionLine = savedSetOnMap, savedPrint, savedInstruction
	symbols.ResetDiscoveryMarks()
	assert(#pins(1432) == 7 and not marks.silver, "manual marks can be cleared")
	faction = "Horde"
	assert(#pins(1432) == 3 and #pins(1431) == 8 and #pins(1441) == 3 and #pins(1438) == 0, "faction applies to special quests and nests")
	fire("QUEST_TURNED_IN", 4821)
	assert(marks.alienEgg == true and #pins(1441) == 0, "the turn-in marks the egg even if it has already left the bags")
	fire("QUEST_ACCEPTED", 79007)
	assert(#pins(1413) == 0 and pins(1436)[1].data.id == "bagWestfall", "a Horde quest pickup marks only its own sleeping bag stop")
	completed[99267] = true
	faction = "Alliance"
	fire("PLAYER_ENTERING_WORLD")
	assert(#pins(1431) == 0, "existing completion of a quest variant is recognized")
	fire("QUEST_ACCEPTED", 86614)
	assert(marks.silver == true and #pins(1432) == 3, "the toolbox is collected as soon as the quest begins")
	local darkshore = pins(1439)
	darkshore[1].click(darkshore[1], "RightButton")
	pets[274334] = true
	fire("PET_JOURNAL_LIST_UPDATE")
	symbols.ResetDiscoveryMarks()
	assert(marks.tallstriderHatchling == true and #pins(1439) == 0, "learning the pet preserves a previously manual mark")
	db.discoveries, items[5167] = false, true
	fire("BAG_UPDATE_DELAYED")
	items[5167], db.discoveries = false, true
	assert(marks.webwoodEgg == true and #pins(1438) == 0, "looted nest items are remembered even with the filter off")
	local elwynn = pins(1429)
	assert(#elwynn == 2 and elwynn[1].data.id == "applejackStill" and elwynn[1].point[1] == 24.5,
		"the Applejack Still and its follow-up are marked in Elwynn")
	items[247824] = true
	fire("BAG_UPDATE_DELAYED")
	assert(marks.applejackStill == true and #pins(1429) == 1 and pins(1429)[1].data.id == "applejackTreat",
		"obtaining the Applejack leaves the follow-up visible")
	fire("QUEST_TURNED_IN", 91738)
	assert(marks.applejackTreat == true and #pins(1429) == 0, "the follow-up hides once turned in")
	assert(#pins(1453) == 1 and #pins(1454) == 0 and #pins(1434) == 1, "Alliance and neutral Alcaz contacts")
	faction = "Horde"
	marks.applejackStill, marks.applejackTreat = nil, nil
	assert(#pins(1429) == 0 and #pins(1453) == 0 and #pins(1454) == 1 and #pins(1434) == 1,
		"Horde and neutral Alcaz contacts, no Applejack quests")
	fire("QUEST_TURNED_IN", 96379)
	assert(#pins(1434) == 0 and #pins(1454) == 0, "the neutral turn-in also finishes the Horde route")
	faction = "Alliance"
	fire("QUEST_TURNED_IN", 96377)
	assert(#pins(1453) == 0, "the faction turn-in finishes the Alliance route")
	assert(#pins(1417) == 1 and #pins(1420) == 1 and #pins(1435) == 1 and #pins(1445) == 2, "all four Scarlet Echo stops")
	items[215427] = true
	fire("BAG_UPDATE_DELAYED")
	assert(marks.scarletArathi == true and not marks.scarletTheramore and #pins(1417) == 0,
		"one echo hides only its own marker")
	items[215427], items[278030] = false, true
	fire("PLAYER_ENTERING_WORLD")
	assert(marks.scarletGraveyard == true and marks.scarletSwamp == true and marks.scarletTheramore == true
		and #pins(1445) == 1 and pins(1445)[1].data.id == "alcazPrison", "owning the banner hides the remaining echo markers")
	local ids = {}
	for _, entries in pairs(ns.MapDiscoveries) do
		for _, entry in ipairs(entries) do
			assert(entry.id and not ids[entry.id] and (entry.items or entry.quests or entry.pet), "each discovery has a stable ID and detection data")
			assert(ns.L.WORLDMAP_DISCOVERY_TEXT[entry.name] and ns.L.WORLDMAP_DISCOVERY_TEXT[entry.hint], "each discovery has localized text")
			ids[entry.id] = true
		end
	end
	local questSource
	for _, source in ipairs(uv(collect, "sources")) do
		if uv(source, "QuestStartAvailable") then questSource = source end
	end
	local savedStarts, savedActive, savedOption = uv(questSource, "questStarts"), C_QuestLog.GetLogIndexForQuestID, db.questStarts
	setuv(questSource, "questStarts", { [1432] = { { x = 50.6, y = 53.4, data = { id = 86614 } } } })
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	ns.QuestieDB.Get = function() return {} end
	db.questStarts = true
	questSource(1432, function() error("a discovery replaces its ordinary quest start pin") end)
	db.discoveries = false
	local starts = 0
	questSource(1432, function() starts = starts + 1 end)
	assert(starts == 1, "the ordinary quest start is restored when discoveries are disabled")
	setuv(questSource, "questStarts", savedStarts)
	C_QuestLog.GetLogIndexForQuestID, db.questStarts = savedActive, savedOption
	UnitFactionGroup, C_QuestLog.IsQuestFlaggedCompleted, ns.QuestieDB.Get = savedFaction, savedComplete, savedLib
	C_Item.GetItemCount, C_PetJournal, symbols.Refresh = savedCount, savedJournal, savedRefresh
	wm.cdb.collectedDiscoveries = savedMarks
	print("map discoveries OK")
end)()
;(function()
	-- Buff reminder: a missing buff waits while the power for it is lacking.
	local buffs = ns:GetModule("Buffs")
	local update = uv(buffs.OnLogin, "Update")
	local evaluate = uv(uv(update, "EvaluateOwn"), "Evaluate")
	setuv(uv(evaluate, "PickSpell"), "classDB", {})
	local reminder = { key = "intellect", auras = { 1459 }, cast = { 1459 } }
	IsPlayerSpell = function() return true end
	C_SpellBook = C_SpellBook or {}
	C_SpellBook.IsSpellKnown = function() return true end
	setuv(evaluate, "FindAura", function() return nil end)
	local noPower = true
	C_Spell.IsSpellUsable = function() return false, noPower end
	local powerStates = {}
	assert(not evaluate(reminder, 60, powerStates) and powerStates.Spell1459 == true, "no mana: hidden, waits for power")
	noPower = false
	wipe(powerStates)
	assert(evaluate(reminder, 60, powerStates) and powerStates.Spell1459 == false, "mana back: shown and still watched")
	-- The target first, then oneself; the target's buff is read on the target
	assert(buffs.BuffUnit(true, true) == "target" and buffs.BuffUnit(true, false) == "player"
		and buffs.BuffUnit(false, false) == nil, "who the button buffs")
	local onUnit
	setuv(evaluate, "FindAura", function(_, unit) onUnit = unit return 30 end)
	local missing, expiring = buffs.EvaluateTarget(reminder, 60)
	assert(onUnit == "target" and missing and expiring, "target's buff runs out: shown faded")
	setuv(evaluate, "FindAura", function() return 0 end)
	assert(not buffs.EvaluateTarget(reminder, 60), "target has it: no button")
	-- Blessings per target: Might not for priests and hunters, Wisdom not for warriors, no second blessing of a
	-- kind, nothing while one's own is on the target
	local all = { kings = true, might = true, wisdom = true, salvation = true, light = true }
	local function pick(class, known, on)
		return (buffs.ChooseBlessing(class, false, known or all, on or {}, 60, 20))
	end
	assert(pick("PRIEST", { might = true, wisdom = true }) == "wisdom", "priest: Wisdom, never Might")
	assert(pick("PRIEST", { might = true }) == nil, "priest: no Might at all")
	assert(pick("WARRIOR", { might = true, wisdom = true }) == "might", "warrior: Might")
	assert(pick("WARRIOR", { wisdom = true }) == nil, "warrior: no Wisdom")
	assert(pick("HUNTER", { might = true, wisdom = true }) == "wisdom", "hunter: Might adds no ranged power")
	assert(pick("ROGUE") == "kings", "Kings first")
	assert(pick("ROGUE", nil, { kings = { remaining = 200 } }) == "might", "Kings from another paladin: Might")
	assert(pick("MAGE", nil, { kings = { remaining = 200 }, wisdom = { remaining = 200 } }) == "salvation", "next free kind")
	assert(pick("MAGE", nil, { might = { remaining = 200, mine = true } }) == nil, "own blessing on it: nothing")
	local kind, renew = buffs.ChooseBlessing("MAGE", false, all, { light = { remaining = 30, mine = true } }, 60, 20)
	assert(kind == "light" and renew, "own blessing runs out: renewed, same kind")
	assert(pick("DEATHKNIGHT", { might = true, wisdom = true }) == "might"
		and buffs.ChooseBlessing("DEATHKNIGHT", true, { might = true, wisdom = true }, {}, 60, 20) == "wisdom", "other class: by mana")
	assert(not buffs.HasMana("WARRIOR", true) and buffs.HasMana("HUNTER", false), "mana by class")
	-- One's own blessing: another paladin's blessing does not stand for it
	local function own(preferred, on)
		return buffs.ChooseBlessing("PALADIN", true, all, on or {}, 60, 20, false, preferred)
	end
	assert(own("wisdom", { might = { remaining = 200 } }) == "wisdom", "Might from another paladin, own Wisdom gone: Wisdom offered")
	assert(own("might", { might = { remaining = 200 } }) == "kings", "the chosen kind is on already: the next free one")
	assert(own("wisdom", { wisdom = { remaining = 200, mine = true }, might = { remaining = 200 } }) == nil, "own blessing on: nothing")
	local ownKind, ownRenew = own("wisdom", { wisdom = { remaining = 30, mine = true } })
	assert(ownKind == "wisdom" and ownRenew, "own blessing runs out: renewed")
	assert(own("wisdom", {}) == "wisdom", "nothing on: the chosen kind")
	-- The whole bar: a friendly player in the target lacks Intellect, the player has it
	local saved = { UnitExists, UnitIsPlayer, UnitIsUnit, UnitCanAssist, UnitIsDeadOrGhost, UnitIsConnected, UnitName }
	UnitExists, UnitIsPlayer = function() return true end, function() return true end
	UnitIsUnit = function(a, b) return a == b end
	UnitCanAssist, UnitIsConnected = function() return true end, function() return true end
	UnitIsDeadOrGhost, UnitName = function() return false end, function(unit) return unit == "target" and "Brann" or "Ich" end
	setuv(evaluate, "FindAura", function(_, unit) if unit == "target" then return nil end return 0 end)
	assert(uv(update, "bar"), "bar built at login")
	assert(rawget(_G, "ForeverPlusBuffButton1") and _G["BINDING_NAME_CLICK ForeverPlusBuffButton1:LeftButton"] == ns.L.BUFFS_BINDING,
		"first button exists for the key binding")
	-- In a rest area the same rule as for oneself: only with the option
	local savedResting, savedZones = IsResting, buffs.db.restingZones
	local savedTracking = C_Minimap.GetNumTrackingTypes
	C_Minimap.GetNumTrackingTypes = function() return 0 end
	buffs.db.restingZones = false
	update()
	local first = uv(update, "buttons")[1]
	assert(not (first and first.shown), "rest area without the option: no button for the target either")
	buffs.db.restingZones = true
	update()
	first = uv(update, "buttons")[1]
	assert(first and first.shown and first.targetName == "Brann", "rest area with the option: the target is buffed")
	buffs.db.restingZones = savedZones
	IsResting = function() return false end
	update()
	first = uv(update, "buttons")[1]
	assert(first and first.shown and first.targetName == "Brann", "button buffs the target, named below")

	local savedPower, savedCosts, savedPowerType = rawget(_G, "UnitPower"), C_Spell.GetSpellPowerCost, rawget(Enum, "PowerType")
	local events = uv(update, "events")
	local onEvent = events:GetScript("OnEvent")
	local eventRegistered = false
	events.RegisterUnitEvent = function(_, event, unit)
		if event == "UNIT_POWER_UPDATE" then eventRegistered = unit == "player" end
	end
	events.UnregisterEvent = function(_, event)
		if event == "UNIT_POWER_UPDATE" then eventRegistered = false end
	end
	Enum.PowerType = { Mana = 0 }
	local mana = 25
	UnitPower = function(unit, power)
		assert(unit == "player" and power == 0, "the caster pays the cost in mana")
		return mana
	end
	C_Spell.GetSpellPowerCost = function(spell)
		if spell == "Spell1459" then return { { type = 0, minCost = 80, cost = 100 } } end
	end
	update()
	assert(not first.shown and eventRegistered, "target-only reminder waits until the cast rank is affordable")
	mana = 80
	onEvent(events, "UNIT_POWER_UPDATE", "player", "MANA")
	assert(first.shown and first.targetName == "Brann" and eventRegistered, "target reminder returns at the minimum mana needed")
	mana = 79
	onEvent(events, "UNIT_POWER_UPDATE", "player", "MANA")
	assert(not first.shown and eventRegistered, "a visible reminder hides as mana drops below the cost")
	setuv(evaluate, "FindAura", function(_, unit) if unit == "target" then return 0 end end)
	assert(not evaluate(reminder, 60), "the caster's own reminder uses the same mana check")
	setuv(evaluate, "FindAura", function() return 0 end)
	update()
	assert(not eventRegistered, "mana is ignored while all buffs are active")
	events.RegisterUnitEvent, events.UnregisterEvent = nil, nil
	UnitPower, C_Spell.GetSpellPowerCost, Enum.PowerType = savedPower, savedCosts, savedPowerType

	local savedDescription, savedAura, savedClock = C_Spell.GetSpellDescription, C_UnitAuras.GetAuraDataBySpellName, GetServerTime
	local savedAfter, savedTimer, savedRange = ns.After, ns.NewTimer, buffs.db.targetRange
	local savedAttribute, attributes = first.SetAttribute, {}
	first.SetAttribute = function(_, key, value) attributes[key] = value end
	local now, targetMissing, auraDuration = 10000, true
	local scheduled, nextUpdate
	GetServerTime = function() return now end
	ns.After = function(_, _, fn) fn() end
	ns.NewTimer = function(_, delay, fn)
		scheduled, nextUpdate = delay, fn
		return { Cancel = function() end }
	end
	buffs.db.targetRange = false
	C_Spell.GetSpellDescription = function(id)
		if id == 1459 then
			return GetLocale() == "deDE" and "Hält 30 Min. lang an." or "Lasts 30 min."
		end
	end
	C_UnitAuras.GetAuraDataBySpellName = function(_, name)
		if name == "Spell1459" and auraDuration then return { duration = auraDuration } end
	end
	setuv(evaluate, "FindAura", function(_, unit)
		if unit == "target" and not targetMissing then return 0 end
	end)
	update()
	local click = first:GetScript("PostClick")
	click(first, "MiddleButton", false)
	assert(not next(buffs.cdb.mutedUntil) and attributes["*type3"] == nil, "target click does not mute")
	targetMissing = false
	update()
	assert(attributes.type == "spell" and attributes["*type3"] == "", "only the secure middle click action is blocked")
	click(first, "LeftButton", false)
	click(first, "MiddleButton", true)
	assert(first.spellID == 1459 and not next(buffs.cdb.mutedUntil), "mute only on middle button release")
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800 and scheduled == 1800.5, "mute for the full tooltip duration")
	assert(first.shown and first.spellID == 6117, "other self buffs still show")
	targetMissing = true
	update()
	assert(first.targetName == "Brann" and first.spellID == 1459 and scheduled == 1800.5,
		"target stays eligible and the own reminder's timer is still scheduled")
	targetMissing = false
	now = now + 1800
	nextUpdate()
	assert(first.shown and first.spellID == 1459 and not buffs.cdb.mutedUntil.intellect, "reminder returns at expiry")
	auraDuration = 3600
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 3600, "the active aura's full duration takes precedence")
	now = now + 3600
	nextUpdate()
	auraDuration = 0
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800, "an unlimited aura is muted for 30 minutes")
	now = now + 1800
	nextUpdate()
	auraDuration = nil
	C_Spell.GetSpellDescription = function() return "" end
	click(first, "MiddleButton", false)
	assert(buffs.cdb.mutedUntil.intellect == now + 1800 and first.spellID == 6117, "a buff without a duration is muted for 30 minutes")
	buffs.db.middleClickMute = false
	buffs:OnOptionChanged("middleClickMute")
	assert(first.spellID == 1459 and not next(buffs.cdb.mutedUntil), "disabling mute restores the reminder")
	assert(attributes["*type3"] == nil, "disabling mute restores the original middle click action")
	buffs.db.middleClickMute = true
	buffs.db.targetRange = savedRange
	first.SetAttribute = savedAttribute
	ns.After, ns.NewTimer = savedAfter, savedTimer
	C_Spell.GetSpellDescription, C_UnitAuras.GetAuraDataBySpellName, GetServerTime = savedDescription, savedAura, savedClock

	IsResting = savedResting
	C_Minimap.GetNumTrackingTypes = savedTracking
	UnitExists, UnitIsPlayer, UnitIsUnit, UnitCanAssist, UnitIsDeadOrGhost, UnitIsConnected, UnitName = unpack(saved)
	setuv(evaluate, "FindAura", function() return nil end)
	print("buff power OK")
end)()
;(function()
	local buffs = ns:GetModule("Buffs")
	local update = uv(buffs.OnLogin, "Update")
	local evaluate = uv(uv(update, "EvaluateOwn"), "Evaluate")
	local reminder = { key = "blessing", blessings = true, cast = { 19740, 19742, 20217 } }
	local choices = {}
	local pickSpell = uv(evaluate, "PickSpell")
	local savedClassDB = uv(pickSpell, "classDB")
	setuv(pickSpell, "classDB", choices)

	local savedLevel, savedRole, savedClass, savedTree = UnitLevel, rawget(_G, "UnitGroupRolesAssigned"), UnitClass, ns.TalentTreeOf
	local savedKnown, savedAura = C_SpellBook.IsSpellKnown, C_UnitAuras.GetAuraDataBySpellName
	local savedFindSlot, savedTrace = C_SpellBook.FindSpellBookSlotForSpell, buffs.lastBlessingTrace
	local level, role, tree, targetClass = 9, "NONE", 2, "PALADIN"
	local known = { [19740] = true, [19742] = true, [20217] = true, [19977] = true }
	local auras = {}
	UnitLevel = function() return level end
	UnitGroupRolesAssigned = function() return role end
	UnitClass = function(unit) return nil, unit == "target" and targetClass or "PALADIN" end
	ns.TalentTreeOf = function() return "Protection", nil, tree end
	C_SpellBook.IsSpellKnown = function(id) return known[id] or false end
	C_SpellBook.FindSpellBookSlotForSpell = function() return nil end
	C_UnitAuras.GetAuraDataBySpellName = function(unit, name) return unit == "target" and auras[name] or nil end

	local function targetSpell()
		return select(4, buffs.EvaluateTarget(reminder, 60))
	end
	local function ownSpell()
		return select(4, evaluate(reminder, 60))
	end
	for _, class in ipairs({ "WARRIOR", "ROGUE", "HUNTER", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN", "DRUID" }) do
		targetClass = class
		local fallback = (class == "WARRIOR" or class == "ROGUE") and 19740 or 19742
		for lowLevel = 1, 3 do
			level = lowLevel
			assert(targetSpell() == 19740, class .. ": levels 1 to 3 get rank 1 Might")
		end
		level = 4
		assert(targetSpell() == fallback, class .. ": first level eligible for rank 1 Wisdom")
		level = 9
		assert(targetSpell() == fallback, class .. ": level 9 gets a class-appropriate replacement")
		level = 10
		assert(targetSpell() == 20217, class .. ": level 10 can get Kings")
	end
	targetClass = "MAGE"
	level = 9
	known[19742] = nil
	assert(targetSpell() == 19740, "unknown Wisdom: low-level caster gets Might")
	known[19742] = true
	auras.Spell19742 = { expirationTime = GetTime() + 300, sourceUnit = "party1" }
	assert(targetSpell() == 19740, "Wisdom from another Paladin: low-level caster gets the other blessing")
	auras.Spell19740 = { expirationTime = GetTime() + 300, sourceUnit = "party2" }
	assert(not targetSpell(), "both replacements are active: no duplicate or higher-level blessing")
	auras.Spell19740, auras.Spell19742 = nil, nil

	local setupButton = uv(update, "SetupButton")
	local button, attributes = CreateFrame("CheckButton"), {}
	button.SetAttribute = function(_, key, value) attributes[key] = value end
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == 19742 and attributes.unit == "target", "the target button casts the exact low-level rank")
	level = 1
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == 19740 and attributes.unit == "target", "the other replacement also casts by rank ID")
	level = 10
	assert(setupButton(button, reminder, "target", targetSpell()))
	assert(attributes.spell == "Spell20217", "regular target still casts by spell name")

	targetClass = "PALADIN"
	level = 9
	auras.Spell25898 = { expirationTime = GetTime() + 30, sourceUnit = "player" }
	assert(targetSpell() == 19742, "expiring Greater Kings on level 9 target: choose an eligible blessing")
	auras.Spell25898 = nil
	assert(ownSpell() == 19742, "own Protection tree: automatic Wisdom when Kings cannot be cast")
	choices.blessingChoice = 20217
	assert(ownSpell() == 19742, "manual Kings also respects the level gate")
	level = 20
	choices.blessingChoice = 0
	assert(ownSpell() == 20217, "own Protection tree: automatic Kings before Might")
	choices.blessingChoice = 19740
	assert(ownSpell() == 19740, "own manual Might is respected")

	known[20217], known[19742], known[19977] = nil, nil, nil
	choices.blessingChoice = 0
	assert(ownSpell() == nil, "automatic Protection skips Might when it is the only known blessing")
	tree = 3
	assert(ownSpell() == 19740, "automatic Retribution can still select Might")
	role = "TANK"
	assert(targetSpell() == nil, "assigned paladin tank does not get automatic Might")
	role = "NONE"
	auras.Spell25780 = { expirationTime = 0 }
	assert(targetSpell() == nil, "Righteous Fury identifies a tank without an assigned role")
	auras.Spell25780 = nil
	assert(targetSpell() == 19740, "other paladin still gets Might as a fallback")

	UnitLevel, UnitGroupRolesAssigned, UnitClass, ns.TalentTreeOf = savedLevel, savedRole, savedClass, savedTree
	C_SpellBook.IsSpellKnown, C_UnitAuras.GetAuraDataBySpellName = savedKnown, savedAura
	C_SpellBook.FindSpellBookSlotForSpell, buffs.lastBlessingTrace = savedFindSlot, savedTrace
	setuv(pickSpell, "classDB", savedClassDB)
	print("blessing eligibility and tank priority OK")
end)()
;(function()
	-- Trainer: train all from the last entry, as far as the money goes; new professions left out.
	local services = ns:GetModule("Services")
	local learnable = uv(uv(services.Apply, "UpdateTrainButton"), "Learnable")
	local trainAll = uv(uv(services.Apply, "CreateTrainButton"), "TrainAll")
	local entries = { { "available", 100 }, { "used", 50 }, { "available", 300, true }, { "available", 200 }, { "unavailable", 10 } }
	GetNumTrainerServices = function() return #entries end
	GetTrainerServiceInfo = function(i) return "x", entries[i][1] end
	GetTrainerServiceCost = function(i) return entries[i][2], entries[i][3] end
	local list, total = learnable()
	assert(#list == 2 and total == 300, "learnable without professions")
	local bought = {}
	BuyTrainerService = function(i) bought[#bought + 1] = i end
	GetMoney = function() return 250 end
	trainAll()
	assert(#bought == 1 and bought[1] == 4, "last first, stops at the money")
	GetMoney = function() return 1000 end
	bought = {}
	trainAll()
	assert(bought[1] == 4 and bought[2] == 1, "all affordable, from the end")
	-- Bank: reagents onto a bank stack with room, the rest stays.
	local deposit = uv(uv(uv(services.Apply, "CreateDepositButton"), "DepositReagents"), "Step")
	local depositOne = uv(deposit, "DepositOne")
	local bags = { [0] = { [1] = { itemID = 2589, stackCount = 15, hyperlink = "item:2589" }, [2] = { itemID = 118, stackCount = 3, hyperlink = "item:118" } },
		[6] = { [1] = { itemID = 2589, stackCount = 10 } } }
	C_Container.GetContainerNumSlots = function(bag) return bags[bag] and 2 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end
	C_Item.GetItemInfo = function(link) return "x", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, link == "item:2589" end
	C_Item.GetItemMaxStackSizeByID = function() return 20 end
	C_Bank = { CanUseBank = function() return true end, FetchPurchasedBankTabIDs = function() return { 6 } end }
	local calls = {}
	C_Container.SplitContainerItem = function(bag, slot, n) calls[#calls + 1] = ("split %d %d %d"):format(bag, slot, n) end
	C_Container.PickupContainerItem = function(bag, slot) calls[#calls + 1] = ("pickup %d %d"):format(bag, slot) end
	GetCursorInfo = function() return nil end
	ns:GetModule("Restock").cdb.items = {} -- the restock test marked linen
	setuv(depositOne, "run", { steps = 0, moved = 0, skip = {} })
	assert(depositOne(), "one move")
	print("  ", table.concat(calls, " | "))
	assert(calls[1] == "split 0 1 10" and calls[2] == "pickup 6 1", "10 linen onto the bank stack of 10; the potion stays")
	setuv(depositOne, "run", nil)
	print("services OK")
end)()
;(function()
	-- Loot summary: items and money in one line.
	local loot = ns:GetModule("Loot")
	local flush = uv(uv(loot.CHAT_MSG_LOOT, "Touch"), "Flush")
	local frames = uv(uv(flush, "Print"), "frames")
	local out = {}
	local chat = { AddMessage = function(_, text) out[#out + 1] = text end }
	frames.LOOT[chat], frames.MONEY[chat] = true, true
	ChatTypeInfo = { LOOT = { r = 0, g = 1, b = 0 }, MONEY = { r = 1, g = 1, b = 0 } }
	GetMoneyString = function(money) return money .. "c" end
	setuv(flush, "batch", { items = {}, order = {}, count = 6, money = 81, moneySources = {}, moneyOrder = {}, started = 0 })
	loot.db.combineMoney, loot.db.inlineQuality = true, "NONE"
	flush()
	print("  ", out[1])
	assert(#out == 1 and out[1]:find("6") and out[1]:find("81c"), "one line")
	print("loot money OK")
end)()
;(function()
	-- /fp schrift: font object and group of the texts under the mouse
	local fonts = ns:GetModule("Fonts")
	local function fs(text, object, visible)
		return { GetObjectType = function() return "FontString" end, IsVisible = function() return visible end,
			GetText = function() return text end, GetFontObject = function() return object end,
			GetFont = function() return "x", 12 end }
	end
	local tex = { GetObjectType = function() return "Texture" end }
	local frame = { GetRegions = function()
		return tex, fs("|cffff0000Schwert|r", GameTooltipText, true), fs("versteckt", GameTooltipText, false),
			fs("eigen", nil, true)
	end }
	GameTooltipText.GetName = function() return "GameTooltipText" end
	local lines = fonts.InspectLines({ frame, { GetRegions = function() error("restricted") end } })
	assert(#lines == 2, "visible texts only, restricted frame skipped: " .. #lines)
	assert(lines[1]:find("Schwert", 1, true) and not lines[1]:find("|c", 1, true)
		and lines[1]:find("GameTooltipText", 1, true) and lines[1]:find(ns.L.FONTS_GROUP_tooltip, 1, true), lines[1])
	assert(lines[2]:find(ns.L.FONTS_INSPECT_OWN, 1, true), lines[2])
	ns.db.fontInspect = nil
	for _ = 1, 12 do
		fonts.SaveInspect(lines)
	end
	assert(#ns.db.fontInspect == 10 and #ns.db.fontInspect[10] == 4, "keeps last 10 with time and settings")
	assert(ns.db.fontInspect[1][2]:find("tooltip=", 1, true) and ns.db.fontInspect[1][3] == lines[1], ns.db.fontInspect[1][2])
	print("font inspect OK")
end)()
;(function()
	-- Traces open in a window to copy
	local saved, shown = ns.ShowEditWindow, nil
	ns.ShowEditWindow = function(key, _, text) shown = { key, text } end
	local items = ns:GetModule("Items")
	local savedTrace = items.trace
	items.trace = { "1.00 a", "2.00 b" }
	items.PrintTrace()
	assert(shown and shown[1] == "Trace" and shown[2]:find("1.00 a\n2.00 b", 1, true), "bags trace in window")
	shown = nil
	ns:GetModule("Dialog").PrintTrace()
	assert(shown and shown[1] == "Trace", "bubble trace in window")
	assert(type(ns.db.bubbleTrace) == "table", "bubble trace kept in the saved variables")
	-- screen values in the trace say why there is no number
	local measure = ns:GetModule("Dialog").Measure
	local savedSecret = issecretvalue
	issecretvalue = function(value) return value == "secret" end
	assert(measure(true, 412.6) == "412" and measure(true, nil) == ns.L.TRACE_MISSING and measure(false, "boom") == ns.L.TRACE_ERROR
		and measure(true, "secret") == ns.L.TRACE_PROTECTED, "measured values")
	issecretvalue = savedSecret
	items.trace, ns.ShowEditWindow = savedTrace, saved
	print("trace window OK")
end)()
;(function()
	-- Greyed self buffs in combat: a removed aura ends its greying, an unreadable removal ends all
	local vis = ns:GetModule("Visuals")
	local forget = vis.ForgetRemovedAuras
	local function setup()
		local active, ids = { Seal = true, Aura = true }, { [11] = "Seal", [12] = "Aura" }
		for i = 1, 60 do
			local n = debug.getupvalue(forget, i)
			if not n then break end
			if n == "activeAuras" then debug.setupvalue(forget, i, active) end
			if n == "auraIDs" then debug.setupvalue(forget, i, ids) end
		end
		return active, ids
	end
	local active = setup()
	forget({ removedAuraInstanceIDs = { 11 } })
	assert(active.Seal == nil and active.Aura, "used-up seal no longer grey, other aura stays")
	forget({ addedAuras = {} })
	assert(active.Aura, "nothing removed: unchanged")
	active = setup()
	forget(nil)
	assert(next(active) == nil, "unknown change: all greying ends")
	active = setup()
	local savedSecret = issecretvalue
	issecretvalue = function(v) return v == 99 end
	forget({ removedAuraInstanceIDs = { 99 } })
	issecretvalue = savedSecret
	assert(next(active) == nil, "secret removal: all greying ends")
	print("active buff combat OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local savedClass, savedTree, savedSpellBook = UnitClass, ns.TalentTreeOf, C_SpellBook
	local savedAuras, savedSecrets, savedEvents = C_UnitAuras, C_Secrets, C_EventUtils
	local savedName, savedAction, savedMacro = C_Spell.GetSpellName, GetActionInfo, GetMacroSpell
	local savedFrames, savedStance, savedForms = ActionBarButtonEventsFrame.frames, StanceBar, GetNumShapeshiftForms
	local savedFormInfo = GetShapeshiftFormInfo
	local savedOption = visuals.db.paladinRecommendations
	local savedSealOption = visuals.db.paladinSealRecommendation
	local savedColors = visuals.db.actionColors
	local savedCombat, savedTime, savedNewTimer = InCombatLockdown, GetTime, C_Timer.NewTimer
	local inCombat, now, sealTimer = false, 100
	InCombatLockdown = function() return inCombat end
	GetTime = function() return now end
	C_Timer.NewTimer = function(delay, callback)
		sealTimer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
		return sealTimer
	end
	local tree = 1
	local names = {
		[19740] = "Might", [19742] = "Wisdom", [19854] = "Wisdom", [25894] = "Greater Wisdom",
		[20217] = "Kings", [1044] = "Freedom", [465] = "Devotion", [19746] = "Concentration",
		[7294] = "Retribution", [19876] = "Shadow Resistance",
		[20375] = "Seal of Command", [20166] = "Seal of Wisdom", [1311649] = "Seal of Fury",
		[20154] = "Seal of Righteousness", [20164] = "Seal of Justice",
	}
	local known = { [19740] = true, [19742] = true, [20217] = true, [465] = true, [19746] = true, [7294] = true }
	known[20375], known[20166], known[1311649], known[20154] = true, true, true, true
	local spells = { 19854, 19740, 20217, 25894, 20375, 20166, 1311649, 20154 }
	local forms = { 19746, 465, 7294 }
	local function Button(slot)
		local button = CreateFrame("Button")
		button.action = slot
		return button
	end
	local wisdom, might, kings, greater = Button(1), Button(2), Button(3), Button(4)
	local sealCommand, sealWisdom, sealFury, sealRight = Button(5), Button(6), Button(7), Button(8)
	local concentration, devotion, retribution = Button(), Button(), Button()
	ActionBarButtonEventsFrame.frames = { wisdom, might, kings, greater, sealCommand, sealWisdom, sealFury, sealRight }
	StanceBar = { actionButtons = { concentration, devotion, retribution } }
	GetNumShapeshiftForms = function() return #forms end
	GetShapeshiftFormInfo = function(index) return 1, true, true, forms[index] end
	C_Spell.GetSpellName = function(id) return names[id] end
	GetActionInfo = function(slot) return slot == 4 and "macro" or "spell", spells[slot] end
	GetMacroSpell = function(id) return id end
	C_SpellBook = { IsSpellKnown = function(id) return known[id] end, FindSpellBookSlotForSpell = function() end }
	local buffs = {}
	C_UnitAuras = { GetUnitAuras = function() return buffs end }
	C_Secrets = { ShouldAurasBeSecret = function() return false end }
	C_EventUtils = { IsEventValid = function() return true end }
	ns.TalentTreeOf = function() return nil, nil, tree end
	UnitClass = function() return "Paladin", "PALADIN" end
	assert(savedOption and savedSealOption, "paladin recommendations start enabled")
	visuals.db.actionColors = false
	visuals:OnOptionChanged("paladinRecommendations")
	local updateWatch = uv(visuals.OnLogin, "UpdatePaladinWatch")
	local watcher = uv(updateWatch, "paladinWatch")
	local glows = uv(uv(updateWatch, "UpdatePaladinHighlights"), "recommendationGlows")
	local auraWatcher = uv(uv(visuals.OnLogin, "UpdateAuraWatch"), "auraWatcher")
	local function Fire(event, spellID) watcher.scripts.OnEvent(watcher, event, "player", nil, spellID) end
	local function FireAura(event, updateInfo) auraWatcher.scripts.OnEvent(auraWatcher, event, "player", updateInfo) end
	local function Lit(button) return glows[button] and glows[button]:IsShown() end
	assert(Lit(wisdom) and Lit(greater) and Lit(concentration), "Holy highlights missing Wisdom and Concentration independently of action colors")
	assert(not Lit(might) and not Lit(devotion), "only the recommended spell families glow")
	assert(not Lit(sealWisdom), "no seal glow out of combat")
	buffs = { { name = "Seal", auraInstanceID = 1 } }
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(concentration), "an unrelated buff does not hide either recommendation")
	buffs[2] = { name = "Kings", auraInstanceID = 2, sourceUnit = "party1" }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and not Lit(greater) and Lit(concentration), "a different blessing from a party member hides only the blessing")
	buffs = { { name = "Shadow Resistance", auraInstanceID = 3, sourceUnit = "party1" } }
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(greater) and not Lit(concentration), "an active resistance aura hides only the aura")
	buffs[2] = { name = "Greater Wisdom", auraInstanceID = 4 }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and not Lit(greater) and not Lit(concentration), "both categories are covered by a greater blessing and an aura")
	buffs = { { name = "Freedom", auraInstanceID = 5 } }
	FireAura("UNIT_AURA")
	assert(not Lit(wisdom) and Lit(concentration), "a utility blessing counts while active")
	buffs = {}
	FireAura("UNIT_AURA")
	assert(Lit(wisdom) and Lit(concentration), "both recommendations return after the buffs end")
	C_Secrets = { ShouldAurasBeSecret = function() return true end }
	FireAura("PLAYER_REGEN_DISABLED")
	assert(not Lit(wisdom) and not Lit(concentration), "recommendations are hidden while buff data is protected")
	tree = 2
	Fire("TRAIT_CONFIG_UPDATED")
	C_Secrets = { ShouldAurasBeSecret = function() return false end }
	FireAura("PLAYER_REGEN_ENABLED")
	assert(Lit(kings) and Lit(devotion) and not Lit(wisdom) and not Lit(concentration), "the new talent tree is shown after buff data becomes readable")
	tree, known[7294] = 3, nil
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(might) and Lit(devotion) and not Lit(kings), "Retribution falls back to Devotion until its aura is learned")
	known[7294] = true
	Fire("SPELLS_CHANGED")
	assert(Lit(retribution) and not Lit(devotion), "newly learned aura replaces the fallback")
	might.action, wisdom.action = 1, 2
	Fire("ACTIONBAR_PAGE_CHANGED")
	assert(Lit(wisdom) and not Lit(might), "the glow follows the spell to the new button")
	buffs = { { name = "Seal of Justice", auraInstanceID = 6, expirationTime = 115 } }
	FireAura("UNIT_AURA")
	inCombat = true
	C_Secrets.ShouldAurasBeSecret = function() return true end
	FireAura("PLAYER_REGEN_DISABLED")
	Fire("PLAYER_REGEN_DISABLED")
	assert(not Lit(sealCommand) and sealTimer.delay == 15, "precombat seal remains active for its actual remaining time")
	FireAura("UNIT_AURA", { removedAuraInstanceIDs = { 6 } })
	assert(Lit(sealCommand) and sealTimer.cancelled, "an early seal removal restores the glow in combat")
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20164)
	assert(not Lit(sealCommand) and sealTimer.delay == 30, "casting any seal removes the glow even with hidden auras")
	local previousTimer = sealTimer
	now = 110
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20375)
	assert(previousTimer.cancelled and sealTimer.delay == 30, "refreshing or switching seals replaces the expiry timer")
	previousTimer = sealTimer
	Fire("UNIT_SPELLCAST_SUCCEEDED", 20271) -- Judgement keeps the seal in Forever.
	assert(sealTimer == previousTimer and not Lit(sealCommand), "Judgement neither removes the seal nor restarts its timer")
	now = 140
	sealTimer.callback()
	assert(Lit(sealCommand) and not Lit(sealWisdom) and not Lit(sealFury), "expiry shows the Retribution recommendation")
	known[20375] = nil
	Fire("SPELLS_CHANGED")
	assert(Lit(sealRight) and not Lit(sealCommand), "Retribution falls back to Righteousness before learning Command")
	tree = 2
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(sealFury) and not Lit(sealRight), "Protection recommends Fury")
	visuals.db.paladinSealRecommendation = false
	visuals:OnOptionChanged("paladinSealRecommendation")
	assert(not Lit(sealFury), "the seal option clears the seal glow")
	inCombat = false
	C_Secrets.ShouldAurasBeSecret = function() return false end
	buffs = {}
	FireAura("PLAYER_REGEN_ENABLED")
	visuals.db.paladinSealRecommendation = savedSealOption
	visuals:OnOptionChanged("paladinSealRecommendation")
	assert(not Lit(sealFury), "the seal glow stays hidden after combat")
	tree, inCombat = 1, true
	Fire("ACTIVE_TALENT_GROUP_CHANGED")
	assert(Lit(sealWisdom) and not Lit(sealFury), "Holy recommends Wisdom")
	inCombat = false
	Fire("PLAYER_REGEN_ENABLED")
	assert(not Lit(sealWisdom), "leaving combat immediately clears a missing seal glow")
	visuals.db.paladinSealRecommendation = false
	visuals.db.paladinRecommendations = false
	visuals:OnOptionChanged("paladinRecommendations")
	assert(not Lit(wisdom) and not Lit(retribution), "turning the option off clears all glows")
	visuals.db.paladinRecommendations = savedOption
	visuals.db.paladinSealRecommendation = savedSealOption
	visuals.db.actionColors = savedColors
	UnitClass, ns.TalentTreeOf, C_SpellBook = savedClass, savedTree, savedSpellBook
	C_UnitAuras, C_Secrets, C_EventUtils = savedAuras, savedSecrets, savedEvents
	C_Spell.GetSpellName, GetActionInfo, GetMacroSpell = savedName, savedAction, savedMacro
	ActionBarButtonEventsFrame.frames, StanceBar, GetNumShapeshiftForms = savedFrames, savedStance, savedForms
	GetShapeshiftFormInfo = savedFormInfo
	InCombatLockdown, GetTime, C_Timer.NewTimer = savedCombat, savedTime, savedNewTimer
	print("paladin action bar recommendations OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local oldClass, oldTree, oldCombat = UnitClass, ns.TalentTreeOf, InCombatLockdown
	local oldSpellbook, oldAuras, oldEvents = C_SpellBook, C_UnitAuras, C_EventUtils
	local oldName, oldAction, oldUsable = C_Spell.GetSpellName, GetActionInfo, C_ActionBar.IsUsableAction
	local oldButtons, oldOption = ActionBarButtonEventsFrame.frames, visuals.db.combatBuffRecommendation
	local class, tree, combat, protected = "SHAMAN", 3, false, false
	local ids, auras, usable = {}, {}, {}
	local spells = { 324, 408510, 6774, 6673 }
	local names = { [324] = "Lightning Shield", [408510] = "Water Shield", [5171] = "Slice and Dice",
		[6774] = "Slice and Dice", [6673] = "Battle Shout" }
	local known = { [324] = true, [409941] = true, [5171] = true, [6673] = true }
	local buttons = {}
	for slot = 1, #spells do
		buttons[slot] = CreateFrame("Button")
		buttons[slot].action = slot
	end
	ActionBarButtonEventsFrame.frames = buttons
	UnitClass = function() return class, class end
	ns.TalentTreeOf = function() return nil, nil, tree end
	InCombatLockdown = function() return combat end
	C_Spell.GetSpellName = function(id) return names[id] end
	GetActionInfo = function(slot) return "spell", spells[slot] end
	C_ActionBar.IsUsableAction = function(slot) return usable[slot] == true end
	C_SpellBook = { IsSpellKnown = function(id) return known[id] end, FindSpellBookSlotForSpell = function() end }
	C_EventUtils = { IsEventValid = function() return true end }
	C_UnitAuras = {
		GetAuraDataBySpellName = function(_, name)
			assert(not protected, "protected aura lookup")
			return auras[name]
		end,
		GetUnitAuraInstanceIDs = function() return ids end,
	}
	local updateWatch = uv(visuals.OnLogin, "UpdateCombatBuffWatch")
	local glows = uv(uv(updateWatch, "UpdateCombatBuffHighlights"), "recommendationGlows")
	local function Lit(slot) return glows[buttons[slot]] and glows[buttons[slot]]:IsShown() end
	local function Fire(event, updateInfo, spellID)
		local watcher = uv(updateWatch, "combatBuffWatch")
		watcher.scripts.OnEvent(watcher, event, "player", updateInfo, spellID)
	end
	assert(oldOption == false, "optional combat buffs start off")
	visuals.db.combatBuffRecommendation = true
	auras["Lightning Shield"] = { auraInstanceID = 10 }
	ids, usable[1], usable[2] = { 10 }, true, true
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(1) and not Lit(2), "combat buffs are hidden outside combat")
	combat, protected = true, true
	Fire("PLAYER_REGEN_DISABLED")
	assert(not Lit(2), "a different shield seen before combat still counts")
	ids = {}
	Fire("UNIT_AURA")
	assert(Lit(2) and not Lit(1), "an exhausted shield detected by instance ID recommends Water Shield for Restoration")
	Fire("UNIT_SPELLCAST_SUCCEEDED", nil, 408510)
	assert(not Lit(2), "an observed Water Shield cast clears the recommendation with protected auras")
	protected, auras = false, {}
	tree = 2
	Fire("TRAIT_CONFIG_UPDATED")
	assert(Lit(1) and not Lit(2), "Enhancement recommends Lightning Shield")
	class = "ROGUE"
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(1) and not Lit(3), "Slice and Dice does not glow when unusable")
	usable[3] = true
	Fire("ACTION_USABLE_CHANGED")
	assert(Lit(3), "when resources allow it the higher rank of Slice and Dice glows")
	auras["Slice and Dice"] = { auraInstanceID = 11 }
	Fire("UNIT_AURA")
	assert(not Lit(3), "active Slice and Dice clears its glow")
	class, usable[4] = "WARRIOR", true
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(Lit(4), "Warrior recommends Battle Shout")
	auras["Battle Shout"] = { auraInstanceID = 12, sourceUnit = "party1" }
	Fire("UNIT_AURA")
	assert(not Lit(4), "a group member's Battle Shout counts")
	auras["Battle Shout"] = nil
	Fire("UNIT_AURA")
	assert(Lit(4), "the shout glows again when it falls off")
	combat = false
	Fire("PLAYER_REGEN_ENABLED")
	assert(not Lit(4), "leaving combat clears the shout glow")
	combat = true
	Fire("PLAYER_REGEN_DISABLED")
	assert(Lit(4), "the glow is rebuilt at the next pull")
	visuals.db.combatBuffRecommendation = false
	visuals:OnOptionChanged("combatBuffRecommendation")
	assert(not Lit(4), "disabling the option clears the glow")
	UnitClass, ns.TalentTreeOf, InCombatLockdown = oldClass, oldTree, oldCombat
	C_SpellBook, C_UnitAuras, C_EventUtils = oldSpellbook, oldAuras, oldEvents
	C_Spell.GetSpellName, GetActionInfo, C_ActionBar.IsUsableAction = oldName, oldAction, oldUsable
	ActionBarButtonEventsFrame.frames, visuals.db.combatBuffRecommendation = oldButtons, oldOption
	print("optional combat buff recommendations OK")
end)()
;(function()
	-- Casts left: mana divided by the spell's cost.
	local vis = ns:GetModule("Visuals")
	local update = uv(uv(vis.OnLogin, "UpdateCastWatch"), "UpdateAllCasts")
	local casts = uv(update, "UpdateCasts")
	vis.db.castsLeft = true
	GetActionInfo = function() return "spell", 403 end
	C_Spell.GetSpellPowerCost = function() return { { type = 0, cost = 25, minCost = 25 } } end
	Enum.PowerType = { Mana = 0 }
	UnitPower = function() return 110 end
	local shown
	local button = CreateFrame("Button")
	button.action = 1
	button.CreateFontString = function() local f = CreateFrame("FontString") f.SetText = function(_, t) shown = t end return f end
	casts(button)
	assert(shown == 4, "110 mana / 25 = 4 casts, got " .. tostring(shown))
	print("casts left OK")
end)()
;(function()
	-- Shared panel look: title, small close button, Escape.
	UISpecialFrames = {}
	local panel = ns.CreatePanel("ForeverPlusTestPanel", { close = true, movable = true })
	assert(panel.Title and panel.Close and not panel:IsShown(), "title, close, hidden")
	local listed
	for _, name in ipairs(UISpecialFrames) do listed = listed or name == "ForeverPlusTestPanel" end
	assert(listed, "Escape closes it")
	panel:Show()
	panel.Close.scripts.OnClick()
	assert(not panel:IsShown(), "close button hides")
	local quiet = ns.CreatePanel("ForeverPlusQuietPanel", { escape = false })
	listed = false
	for _, name in ipairs(UISpecialFrames) do listed = listed or name == "ForeverPlusQuietPanel" end
	assert(not listed and not rawget(quiet, "Close"), "tooltip-like panel")
	print("panel OK")
end)()
;(function()
	-- Local quest capture is opt-in and deduplicates unchanged snapshots.
	local capture = ns:GetModule("DataCapture")
	C_QuestLog.GetTitleForQuestID = function() return "Koboldlager" end
	C_QuestLog.GetQuestObjectives = function() return { { text = "Kobolde: 0/10", type = "monster", finished = false } } end
	capture.Clear()
	capture.SetEnabled(true)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	local rows = ForeverPlusDB.observations["33"]
	assert(rows and #rows == 1 and rows[1].title == "Koboldlager", "visible quest snapshot captured once")
	assert(rows[1].method == "QUEST_ACCEPTED" and rows[1].source == "client-visible quest log", "observation provenance")
	capture.SetEnabled(false)
	capture.OnEvent(capture, "QUEST_ACCEPTED", 33)
	assert(#rows == 1, "disabled capture records nothing")
	capture.Clear()
	print("data capture OK")
end)()
-- Quest starts on the map: level gate, prerequisites, active quests
;(function()
	local available
	for _, source in ipairs(uv(uv(ns.MapSymbols.Count, "Collect"), "sources")) do
		local ok, found = pcall(uv, source, "QuestStartAvailable")
		if ok and found then available = found end
	end
	assert(available, "quest start source found")
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 7 end
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 8 and 1 or nil end
	UnitLevel = function() return 20 end
	UnitRace = function() return "Human", "Human", 1 end
	UnitClass = function() return "Mage", "MAGE", 8 end
	local lib = { Enum = {} }
	local function quest(fields) fields.id = fields.id or 1 return { data = fields } end
	assert(available(quest({ gate = 20 * 100000000000 }), lib), "level reached")
	assert(not available(quest({ gate = 30 * 100000000000 }), lib), "level too low")
	assert(not available(quest({ id = 7 }), lib), "completed quests are hidden")
	assert(not available(quest({ id = 8 }), lib), "active quests are hidden")
	assert(available(quest({ all = { 7 } }), lib) and not available(quest({ all = { 9 } }), lib), "all prerequisites needed")
	assert(not available(quest({ any = { 9 } }), lib) and available(quest({ any = { 9, 7 } }), lib), "one of the alternatives")
	assert(not available(quest({ excluded = { 8 } }), lib), "an active exclusive quest hides it")
	assert(not available(quest({ parent = 5 }), lib), "needs the parent quest in the log")
	print("quest starts OK")
end)()
-- Zeppelin and boat rides
;(function()
	local T = ns:GetModule("Transports")
	local function run(samples)
		local state, rides = {}, {}
		for _, sample in ipairs(samples) do
			local ride = T.Step(state, sample)
			if ride then rides[#rides + 1] = ride end
		end
		return rides
	end
	local function series(t0, count, make)
		local list = {}
		for i = 0, count - 1 do
			local sample = make(i)
			sample.time = t0 + i * 0.5
			list[#list + 1] = sample
		end
		return list
	end
	local function append(a, b) for _, v in ipairs(b) do a[#a + 1] = v end return a end
	local still = function() return { mapID = 1411, x = 0.5, y = 0.5, speed = 0 } end
	-- 60 s on a zeppelin: moves along while standing still, then stands still again
	local samples = series(0, 6, still)
	append(samples, series(3, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * (i + 1), y = 0.5, speed = 0 } end))
	append(samples, series(63, 8, function() return { mapID = 1411, x = 0.86, y = 0.5, speed = 0 } end))
	local rides = run(samples)
	assert(#rides == 1, "one ride recorded")
	assert(math.abs(rides[1].seconds - 60) <= 2, "duration about 60 s: " .. rides[1].seconds)
	assert(rides[1].from.x == 0.5 and rides[1].to.x > 0.85, "dock and arrival")
	assert(#rides[1].path > 5, "path sampled")
	-- walking, a short lift, and a taxi do not count
	local walking = series(0, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * i, y = 0.5, speed = 7 } end)
	assert(#run(walking) == 0, "own movement is no ride")
	local lift = series(0, 6, still)
	append(lift, series(3, 20, function(i) return { mapID = 1411, x = 0.5, y = 0.5 + 0.003 * (i + 1), speed = 0 } end))
	append(lift, series(13, 8, function() return { mapID = 1411, x = 0.5, y = 0.56, speed = 0 } end))
	assert(#run(lift) == 0, "a ride under 20 s is no transport")
	local taxi = series(0, 120, function(i) return { mapID = 1411, x = 0.5 + 0.003 * i, y = 0.5, speed = 0, blocked = true } end)
	assert(#run(taxi) == 0, "taxi flights are excluded")
	-- a loading screen in the middle (boat between continents)
	local boat = series(0, 6, still)
	append(boat, series(3, 40, function(i) return { mapID = 1437, x = 0.5 + 0.003 * (i + 1), y = 0.5, speed = 0 } end))
	append(boat, series(23, 60, function(i) return { mapID = 1438, x = 0.2 + 0.003 * i, y = 0.4, speed = 0 } end))
	append(boat, series(53, 8, function() return { mapID = 1438, x = 0.38, y = 0.4, speed = 0 } end))
	rides = run(boat)
	assert(#rides == 1 and rides[1].crossed and rides[1].to.mapID == 1438, "crossing the map is one ride")
	-- docks: rides close together share a dock, routes collect the durations
	local docks = T.BuildDocks({ { 1411, 0.50, 0.50, 1420, 0.60, 0.40, 240 }, { 1411, 0.505, 0.5, 1420, 0.6, 0.4, 250 },
		{ 1411, 0.50, 0.50, 1437, 0.3, 0.3, 120 }, { "x" } })
	assert(#docks[1411] == 1 and #docks[1411][1].routes == 2, "one dock, two destinations")
	assert(#docks[1411][1].routes[1].seconds == 2, "the same route twice")
	local pathRides = T.PathRides(ns.TransportPaths)
	assert(#pathRides == 25, "shipped ship, zeppelin and airship legs")
	pathRides[#pathRides + 1] = { 1429, 0.055, 0.31, 1439, 0.31, 0.41, 123 }
	docks = T.BuildDocks(pathRides)
	local stormwind = docks[1453][1]
	assert(stormwind.kind == "ship" and #stormwind.routes == 1 and stormwind.routes[1].seconds[1] == 123 and not docks[1429],
		"recordings on the surrounding zone match the same harbor")
	local wetlands = docks[1437][2].routes[1]
	assert(wetlands.to.mapID == 1424 and wetlands.following[1][2][1] == 1439 and #wetlands.seconds == 0,
		"Menethil departs for Southshore, then Auberdine")
	local source
	for _, provider in ipairs(uv(uv(ns.MapSymbols.Count, "Collect"), "sources")) do
		if uv(provider, "DockTooltip") then source = provider break end
	end
	assert(source, "transport map source registered")
	local savedInfo, savedArea, savedDocks = C_Map.GetMapInfo, C_Map.GetAreaInfo, T.db.docks
	C_Map.GetMapInfo = function(id)
		return { mapID = id, mapType = id == 947 and 1 or (id == 1414 or id == 1415) and 2 or 3, name = tostring(id) }
	end
	local names = { [150] = "Hafen von Menethil", [271] = "Süderstade", [442] = "Auberdine" }
	C_Map.GetAreaInfo = function(id) return names[id] end
	T.db.docks, T.docks = true, nil
	local function MapDocks(mapID)
		local symbols = {}
		source(mapID, function(x, y, symbol)
			assert(x >= 0 and x <= 1 and y >= 0 and y <= 1 and not symbol.atlas, "transport uses its own texture")
			symbols[#symbols + 1] = symbol
		end)
		return symbols
	end
	local zone = MapDocks(1437)
	assert(#zone == 2 and zone[2].data.kind == "ship", "both piers show on the Wetlands zone map")
	local lines = {}
	zone[2].tooltip({ AddLine = function(_, line) lines[#lines + 1] = line end }, zone[2])
	assert(lines[1] == ns.L.TRANSPORTS_SHIP and lines[2] == names[150]
		and lines[3] == ns.L.TRANSPORTS_TO_KNOWN:format(names[271])
		and lines[4] == ns.L.TRANSPORTS_THEN:format(names[442]), "tooltip shows the type and the stops in order")
	local capital, zeppelins, island = MapDocks(1453), MapDocks(1411), MapDocks(2521)
	assert(#capital == 1 and #MapDocks(1429) == 1, "the harbor is on both city and zone maps")
	assert(#zeppelins == 1 and #zeppelins[1].routes == 2 and zeppelins[1].texture ~= capital[1].texture,
		"the Zeppelin tower shares its destinations and has a different icon")
	assert(#island == 2 and #MapDocks(1414) > 0 and #MapDocks(947) > 0, "island, continent and world map")
	local menethil
	for _, symbol in ipairs(MapDocks(1415)) do
		if symbol.data.area == 150 then menethil = symbol end
	end
	assert(menethil and #menethil.routes == 2, "overview groups both Menethil piers and lists both departures")
	T.db.docks = false
	assert(#MapDocks(1437) == 0, "transport filter hides docks")
	C_Map.GetMapInfo, C_Map.GetAreaInfo, T.db.docks, T.docks = savedInfo, savedArea, savedDocks, nil
	local text = T.ExportText({ { 1411, 0.5, 0.5, 1420, 0.6, 0.4, 240 } })
	assert(text:find("{ 1411, 0.5000, 0.5000, 1420, 0.6000, 0.4000, 240 },", 1, true), "export line")
	print("transports OK")
end)()
-- Damage meter reset modes
do
	local mr = ns:GetModule("MeterReset")
	local on = {}
	mr.ToggleEvent = function(_, event, enabled) on[event] = enabled end
	local resets = 0
	C_DamageMeter = { ResetAllCombatSessions = function() resets = resets + 1 end }
	assert(mr.db.mode == "never", "meter reset default")
	local function Check(mode, boss, mplus, combat)
		mr.db.mode = mode
		mr:Apply()
		assert(on.ENCOUNTER_START == boss and on.CHALLENGE_MODE_START == mplus and on.PLAYER_REGEN_DISABLED == combat, mode)
	end
	Check("never", false, false, false)
	Check("boss", true, false, false)
	Check("mplus", false, true, false)
	Check("bossMplus", true, true, false)
	Check("combat", false, false, true)
	mr.db.mode = "never"
	print("meter reset OK")
end
-- Library books
;(function()
	local Lib = ns:GetModule("Library")
	local seen, located = {}, 0
	for _, b in ipairs(ns.LibraryBooks) do
		seen[b[1]] = true
		if b[2] then
			located = located + 1
			assert(b[3] > 0 and b[3] < 100 and b[4] > 0 and b[4] < 100, "position in range " .. b[1])
		end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	assert(n == 40, "40 different books: " .. n)
	assert(located >= 30, "most books have a position")
	local source
	for _, candidate in ipairs(uv(ns.MapSymbols.AddSource, "sources")) do
		if uv(candidate, "Positions") then source = candidate break end
	end
	assert(source, "library source on the world map")
	local oldSymbols, oldPrint, oldMenu = Lib.db.symbols, ns.PrintAlways, MenuUtil.CreateContextMenu
	local oldOwned, oldQuestDone = Lib.cdb.owned, C_QuestLog.IsQuestFlaggedCompleted
	Lib.db.symbols, Lib.cdb.owned = true, {}
	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	local list = {}
	ns.PrintAlways = function(line, ...) list[#list + 1] = line:format(...) end
	Lib.Command("")
	assert(list[1] == ns.L.LIBRARY_STATUS:format(0, 40) and #list == 41, "Rumi counts and appears once")
	local function Pins(mapID)
		local pins = {}
		source(mapID, function(_, _, pin) pins[#pins + 1] = pin end)
		return pins
	end
	assert(#Pins(1431) == 1 and #Pins(1423) == 3, "new Duskwood and Eastern Plaguelands pins")
	assert(#Pins(1432) == 2 and #Pins(1436) == 2, "both Rumi locations are shown")
	assert(#Pins(1444) == 0, "the old SoD location has no shipped pin")
	local blackrock = Pins(1428)
	assert(#blackrock == 1, "the two Blackrock books share a single pin")
	local tooltip = {}
	blackrock[1].tooltip({ AddLine = function(_, line) tooltip[line] = true end }, blackrock[1])
	assert(tooltip[ns.L.LIBRARY_STONEWROUGHT_HINT] and tooltip[ns.L.LIBRARY_MAGMA_HINT], "both directions are shown")
	local choices = {}
	MenuUtil.CreateContextMenu = function(owner, build)
		build(owner, { CreateTitle = function() end, CreateButton = function(_, _, callback, itemID)
			choices[itemID] = function() callback(itemID) end
		end })
	end
	blackrock[1].click(blackrock[1], "RightButton")
	assert(choices[220349] and choices[228133], "choose either book from the shared pin")
	choices[220349]()
	blackrock = Pins(1428)
	assert(#blackrock == 1 and Lib.cdb.owned[220349] and not Lib.cdb.owned[228133], "mark only the chosen book")
	blackrock[1].click(blackrock[1], "RightButton")
	assert(Lib.cdb.owned[228133] and #Pins(1428) == 0, "last book is directly marked and the shared pin disappears")
	Lib.cdb.owned, C_QuestLog.IsQuestFlaggedCompleted = oldOwned, oldQuestDone
	Lib.db.symbols, ns.PrintAlways, MenuUtil.CreateContextMenu = oldSymbols, oldPrint, oldMenu
	-- a book in the bags after login counts as collected and its find is remembered
	local id = ns.LibraryBooks[1][1]
	local inBags = false
	C_Item.GetItemCount = function(item) return inBags and item == id and 1 or 0 end
	C_Map.GetBestMapForUnit = function() return 1455 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.757, 0.105 end } end
	Lib.Scan()
	assert(not Lib.cdb.owned[id], "no book yet")
	inBags = true
	Lib.Scan()
	assert(Lib.cdb.owned[id], "collected once in the bags")
	local find = ns.db.libraryFinds[id]
	assert(find and find[1] == 1455 and math.abs(find[2] - 75.7) < 0.01, "find location remembered")
	local text = Lib.ExportText(ns.db.libraryFinds)
	assert(text:find("{ " .. id .. ", 1455, 75.7, 10.5 },", 1, true), "export line")
	Lib.cdb.owned[id], ns.db.libraryFinds[id] = nil, nil
	-- a book handed in before (its quest is done) counts without ever being in the bags
	inBags = false
	local handedIn
	for _, b in ipairs(ns.LibraryBooks) do if b[6] then handedIn = b break end end
	assert(handedIn, "hand-in quests known")
	C_QuestLog.IsQuestFlaggedCompleted = function(quest) return quest == handedIn[6] end
	Lib.Scan()
	assert(Lib.cdb.owned[handedIn[1]] and not ns.db.libraryFinds[handedIn[1]], "quest done: collected, no find recorded")
	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	Lib.cdb.owned[handedIn[1]] = nil
	print("library OK")
end)()
-- Shipped flight points and instance entrances
;(function()
	local P = assert(ns.Points, "Data/Points.lua loaded")
	local listed = {}
	assert(loadfile(root .. "/Data/Instances.lua"))("ForeverPlus", listed)
	local n, factions = 0, {}
	for node, f in pairs(P.flights) do
		n = n + 1
		factions[f[5]] = true
		assert(type(f[1]) == "string" and f[2] > 1000 and f[3] > 0 and f[3] < 100 and f[4] > 0 and f[4] < 100, "flight " .. node)
	end
	assert(n >= 60 and factions.A and factions.H, "flight points of both factions: " .. n)
	for id, row in pairs(P.entrances) do
		assert(listed.Instances[id], "entrance of a listed instance " .. id)
		assert(row[2] == "w" or row[2] == "m", "entrance kind " .. id)
	end
	assert(P.entrances[36] and P.entrances[36][2] == "w", "Deadmines entrance from the game table")
	print("points OK")
end)()
-- Innkeepers
;(function()
	local I = ns:GetModule("Innkeepers")
	assert(I.NpcID("Creature-0-4379-0-27-8931-00001F5C36") == 8931, "NPC ID from the GUID")
	assert(I.NpcID("Player-4379-00112233") == nil and I.NpcID(nil) == nil, "only creatures")
	UnitGUID = function() return "Creature-0-4379-0-27-8931-00001F5C36" end
	UnitName = function() return "Gastwirtin Heather" end
	UnitFactionGroup = function() return "Alliance" end
	C_Map.GetBestMapForUnit = function() return 1436 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5293, 0.5374 end } end
	ns.db.innkeepers = {}
	I.Record()
	local inn = ns.db.innkeepers[8931]
	assert(inn and inn[1] == "Gastwirtin Heather" and inn[2] == 1436 and inn[3] == 52.9 and inn[4] == 53.7 and inn[5] == "A", "innkeeper remembered")
	UnitFactionGroup = function() return "Horde" end
	I.Record()
	assert(ns.db.innkeepers[8931][5] == "N" and ns.db.innkeepers[8931][3] == 52.9, "met by both factions: neutral, first position kept")
	-- the gossip window with the binder option records without binding
	ns.db.innkeepers = {}
	UnitFactionGroup = function() return "Alliance" end
	C_GossipInfo = { GetOptions = function() return { { icon = 132060 } } end }
	I.OnGossipShow()
	assert(next(ns.db.innkeepers) == nil, "a vendor option is no innkeeper")
	C_GossipInfo = { GetOptions = function() return { { icon = 132060 }, { icon = 132052 } } end }
	I.OnGossipShow()
	assert(ns.db.innkeepers[8931] and ns.db.innkeepers[8931][5] == "A", "binder option recorded")
	UnitFactionGroup = function() return "Horde" end
	I.Record()
	local text = I.ExportText(ns.db.innkeepers)
	assert(text:find('{ 8931, 1436, 52.9, 53.7, "N", "Gastwirtin Heather" },', 1, true), "export line")
	ns.db.innkeepers = {}
	print("innkeepers OK")
end)()
-- Companion
;(function()
	local C = ns:GetModule("Companion")
	local dead, combat, resting = false, false, false
	UnitIsDeadOrGhost = function() return dead end
	UnitAffectingCombat = function() return combat end
	IsResting = function() return resting end
	assert(C.State() == "idle", "idle")
	resting = true
	assert(C.State() == "rest", "resting")
	combat = true
	assert(C.State() == "combat", "combat beats resting")
	dead = true
	assert(C.State() == "dead", "dead beats everything")
	dead, combat, resting = false, false, false
	C.db.enabled = true
	C:Apply()
	local after, pending = C_Timer.After, nil
	C_Timer.After = function(_, fn) pending = fn end
	C.React("levelUp")
	assert(C.State() == "levelUp", "a reaction shows until it ends")
	pending()
	assert(C.State() == "idle", "back to idle afterwards")
	C_Timer.After = after
	C.db.enabled = false
	C:Apply()
	print("companion OK")
end)()
-- Auction house: profit filter
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local prices = { [9001] = 100, [9002] = 50, [9003] = 0 }
	C_Item.GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[id] end
	local timers, refreshes, savedAfter = {}, {}, C_Timer.After
	C_Timer.After = function(delay, fn)
		local queue = delay >= 10 and timers or refreshes
		queue[#queue + 1] = fn
	end
	local function FlushRefreshes()
		while #refreshes > 0 do table.remove(refreshes, 1)() end
	end
	local uncached = { [9004] = true, [9005] = true }
	C_Item.IsItemDataCachedByID = function(id) return not uncached[id] end
	local requested = {}
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	local full, more = false, 0
	C_AuctionHouse = { HasFullBrowseResults = function() return full end, RequestMoreBrowseResults = function() more = more + 1 end }
	A.db.vendorBuyFilter = true
	A.db.vendorMinMargin = 0
	local function row(id, price, quantity) return { itemKey = { itemID = id }, minPrice = price, totalQuantity = quantity or 5 } end
	assert(F.Profitable(row(9001, 99)) and not F.Profitable(row(9001, 100)) and not F.Profitable(row(9001, 101)), "vendor price must be above the buy price")
	A.db.vendorMinMargin = 10
	assert(F.Profitable(row(9001, 90)) and not F.Profitable(row(9001, 91)), "at least 10 % below the merchant price")
	A.db.vendorMinMargin = 0
	assert(not F.Profitable(row(9003, 1)), "no merchant value, no profit")
	assert(not F.Profitable(row(9002, 10, 0)) and not F.Profitable({ isVirtualEntry = true }), "empty and virtual rows are left out")
	assert(F.Profitable(row(9004, 1)) == nil, "an unknown merchant price is neither yes nor no")
	-- the view onto a list, growing with the pages
	local provider
	local redraws = 0
	local scrollEnd = 0
	local frame = { browseResults = { row(9001, 10), row(9001, 500), row(9002, 20) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			ScrollBox = { GetDataIndexEnd = function() return scrollEnd end },
			SetDataProvider = function(_, started, entry, count, hasFull) provider = { started = started, entry = entry, count = count, hasFull = hasFull } end,
			RefreshScrollFrame = function() redraws = redraws + 1 end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	F.Apply()
	F.Provider(frame, true)
	assert(provider.count() == 2 and provider.entry(1) == frame.browseResults[1] and provider.entry(2) == frame.browseResults[3], "only profitable rows")
	frame.browseResults[#frame.browseResults + 1] = row(9001, 1)
	assert(provider.count() == 3, "added rows are judged on the way")
	-- a row whose item data is missing: asked for once, judged when it arrives, kept in its place
	frame.browseResults[#frame.browseResults + 1] = row(9005, 5)
	frame.browseResults[#frame.browseResults + 1] = row(9005, 6)
	frame.browseResults[#frame.browseResults + 1] = row(9001, 2)
	assert(provider.count() == 4, "pending rows are not shown")
	local asked = 0
	for _, id in ipairs(requested) do if id == 9005 then asked = asked + 1 end end
	assert(asked == 1, "item data asked once per item")
	prices[9005] = 20
	uncached[9005] = nil
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 9005)
	assert(provider.count() == 4, "late verdicts wait for the batched refresh")
	FlushRefreshes()
	assert(provider.count() == 6, "both rows of the item judged")
	local r = frame.browseResults
	assert(provider.entry(1) == r[4] and provider.entry(2) == r[7] and provider.entry(3) == r[1] and provider.entry(4) == r[3]
		and provider.entry(5) == r[5] and provider.entry(6) == r[6], "highest merchant profit first, late rows at their place")
	A.db.vendorProfitSort = false
	F.Apply()
	assert(provider.count() == 6 and provider.entry(1) == r[1] and provider.entry(2) == r[3] and provider.entry(3) == r[4]
		and provider.entry(6) == r[7], "without the profit sort Blizzard's order stays")
	A.db.vendorProfitSort = true
	-- many rows are judged in portions
	local big = {}
	for i = 1, 400 do big[i] = row(9001, i == 400 and 10 or 500) end
	frame.browseResults = big
	F.Apply() -- (a new search resets the view through the query hook)
	redraws = 0
	provider.count()
	local judged = F.State.judged
	assert(judged > 0 and judged < 400 and #refreshes == 1, "one portion, then a queued slice")
	provider.count(); F.Page(frame)
	assert(F.State.judged == judged, "provider and paging calls share the pending slice")
	full = true
	FlushRefreshes()
	assert(F.State.judged == 400 and provider.count() == 1 and redraws == 1, "only the slice with a new hit redraws")
	full = false
	big[400] = row(9001, 500)
	F.Apply()
	more, redraws = 0, 0
	FlushRefreshes()
	assert(provider.count() == 0 and more == 1 and redraws == 0, "an empty filtered page keeps paging without a redraw")
	frame.browseResults = { row(9001, 500) }
	more = 0
	F.Apply()
	assert(provider.count() == 0, "a new result table starts a new view")
	assert(provider.hasFull() == false, "searching while pages are missing")
	-- paging: asks while the view is short, one request per answer
	F.Page(frame)
	F.Page(frame)
	assert(more == 1, "one request until new rows arrive")
	frame.browseResults[#frame.browseResults + 1] = row(9001, 500)
	F.Page(frame)
	assert(more == 2, "next page after new rows")
	full = true
	F.Page(frame)
	assert(more == 2 and provider.hasFull() == true, "nothing more to ask for when the list is complete")
	full = false
	-- the search for hits is given up after a while: no spinner for ever
	F.Apply()
	frame.browseResults = { row(9001, 500) }
	provider.count()
	more, timers = 0, {}
	F.Page(frame)
	assert(more == 1 and #timers >= 1 and provider.hasFull() == false, "searching, timer set")
	for _, fn in ipairs(timers) do fn() end
	FlushRefreshes()
	assert(provider.hasFull() == true, "given up: the list says no results instead of searching")
	F.Page(frame)
	assert(more == 1, "no more pages by itself after giving up")
	C_Timer.After = savedAfter
	-- filter off: Blizzard's provider comes back
	local restored
	frame.ItemList.SetDataProvider = function(_, a, b, c, d) restored = { a, b, c, d } end
	F.Provider(frame, false)
	assert(restored and restored[3] and restored[3]() == 0, "original provider restored")
	A.db.vendorBuyFilter = false
	print("auction filter OK")
end)()
-- Auction house: buy list sorted by item rating
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedRating, savedAPI, savedAfter = ns.ItemLinkRating, C_AuctionHouse, C_Timer.After
	local savedCached, savedRequest = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	local refreshes = {}
	C_Timer.After = function(_, fn) refreshes[#refreshes + 1] = fn end
	-- item ID -> gain, block; nil = still loading
	local ratings = { [1] = { 5, "ok" }, [2] = { 9, "level" }, [3] = { -2 }, [4] = { 12, "no" }, [6] = { 3, "ok" } }
	ns.ItemLinkRating = function(link)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id == 5 then return false end
		local r = ratings[id]
		if not r then return nil end
		return r[1], r[2]
	end
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end,
		GetItemKeySampleLink = function(key) return "|Hitem:" .. key.itemID .. "|h" end }
	C_Item.IsItemDataCachedByID = function() return true end
	C_Item.RequestLoadItemDataByID = function() end
	local function row(id) return { itemKey = { itemID = id }, minPrice = 10, totalQuantity = 1 } end
	local provider
	local frame = { browseResults = { row(3), row(5), row(1), row(4), row(2), row(6), row(7) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, started, entry, count, hasFull) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.scoreValueSort = false, true, false
	F.Apply()
	local r = frame.browseResults
	local order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(table.concat(order, ",") == "1,6,2",
		"only upgrades, wearable ones by gain, then later ones; worse, no comparison and loading left out: " .. table.concat(order, ","))
	assert(A.GainText(5) == "+5.0" and select(2, A.GainText(5)) == true, "a gain shows green with its sign")
	local worse, better = A.GainText(-2)
	assert(worse == "-2.0" and better == false and A.GainText(nil) == nil, "a loss shows grey, no rating no label")
	-- the label in the name cell: shown for rated rows while there is room, never over the name
	local function fakeText(width)
		local fs = { text = "", shown = false, w = width }
		function fs:SetText(t) self.text = t end
		function fs:GetStringWidth() return self.w or #self.text * 6 end
		function fs:SetShown(v) self.shown = v end
		function fs:Hide() self.shown = false end
		function fs:SetPoint() end
		function fs:SetTextColor() end
		return fs
	end
	local made
	local function cell(rowData, nameWidth)
		return { rowData = rowData, Icon = { IsShown = function() return true end, GetWidth = function() return 14 end },
			Text = fakeText(nameWidth), GetWidth = function() return 200 end,
			CreateFontString = function() made = fakeText() return made end }
	end
	local savedUpgrade = ns.ItemLinkUpgradeState
	ns.ItemLinkUpgradeState = function() return false end
	local c = cell(r[3], 100)
	F.ItemCell(c, r[3].itemKey)
	assert(made and made.text == "+5.0" and made.shown, "the gain of a rated row is shown")
	made = nil
	F.ItemCell(cell(r[3], 170), r[3].itemKey)
	assert(made and not made.shown, "a long name keeps its room")
	made = nil
	F.ItemCell(cell(r[2], 100), r[2].itemKey)
	assert(made == nil, "no label without a comparison")
	ns.ItemLinkUpgradeState = savedUpgrade
	-- a short list asks for the next page by itself
	local full, more = false, 0
	C_AuctionHouse.HasFullBrowseResults = function() return full end
	C_AuctionHouse.RequestMoreBrowseResults = function() more = more + 1 end
	F.Apply()
	provider.count()
	assert(more == 1, "a short list asks for the next page by itself")
	assert(A.FilterStatusText(2, 0, false, true) == ns.L.AUCTION_FILTER_STATUS_OTHER:format(2, 20, 10), "status line without profit wording")
	ratings[7] = { 8, "ok" }
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 7)
	while #refreshes > 0 do table.remove(refreshes, 1)() end
	assert(provider.count() == 4 and provider.entry(1) == r[7] and provider.entry(2) == r[3], "a late upgrade joins at its place")
	-- value: gain per gold of the cheapest offer, within the groups (5 for 4 g, 3 for 1 g, 8 for 2 g, later 9 for 1 c)
	ratings[1], ratings[6], ratings[7], ratings[2] = { 5, "ok" }, { 3, "ok" }, { 8, "ok" }, { 9, "level" }
	r[3].minPrice, r[6].minPrice, r[7].minPrice, r[5].minPrice = 40000, 10000, 20000, 1
	A.ClearOwnFilters()
	A.db.scoreValueSort = true
	A:OnOptionChanged("scoreValueSort")
	assert(not A.db.scoreSort, "value and upgrades exclude each other")
	order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(table.concat(order, ",") == "7,6,1,2", "most gain per gold first, later upgrades after: " .. table.concat(order, ","))
	A.db.scoreSort = true
	A:OnOptionChanged("scoreSort")
	assert(not A.db.scoreValueSort, "upgrades switch value off")
	A.db.scoreSort, A.db.scoreValueSort = false, true
	assert(A.GainText(3, 12) == "+3.0 · 12/g" and A.GainText(3, 0.5) == "+3.0 · 0.5/g", "gain and rating per gold in the row")
	A.db.scoreValueSort = false
	assert(A.GainText(3, 12) == "+3.0", "without the value sort only the gain")
	-- the order holds when rows arrive in pages and their item data later, in both modes (seen wrong in game)
	local gains = { 6.1, 4.5, 9.5, 5.6, 5.1, 0.4, 12.0, 7.3 }
	local costs = { 549, 600, 1200, 900, 899, 50, 75000, 2000 }
	for _, value in ipairs({ false, true }) do
		A.db.scoreSort, A.db.scoreValueSort = not value, value
		ratings = {}
		frame.browseResults = {}
		F.Apply()
		for id = 11, 14 do frame.browseResults[#frame.browseResults + 1] = { itemKey = { itemID = id }, minPrice = costs[id - 10] * 100, totalQuantity = 1 } end
		ratings[12], ratings[13] = { gains[2], "ok" }, { gains[3], "ok" }
		provider.count()
		for id = 15, 18 do frame.browseResults[#frame.browseResults + 1] = { itemKey = { itemID = id }, minPrice = costs[id - 10] * 100, totalQuantity = 1 } end
		provider.count()
		for id = 11, 18 do
			ratings[id] = { gains[id - 10], "ok" }
			F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", id)
			while #refreshes > 0 do table.remove(refreshes, 1)() end
		end
		local last
		for i = 1, provider.count() do
			local key = provider.entry(i).itemKey.itemID - 10
			local measure = value and gains[key] / costs[key] or gains[key]
			assert(not last or measure <= last, (value and "value" or "upgrades") .. ": row " .. i .. " out of order")
			last = measure
		end
		assert(provider.count() == 8, "all upgrades shown")
	end
	ratings = {}
	A.ClearOwnFilters()
	ns.ItemLinkRating, C_AuctionHouse, C_Timer.After = savedRating, savedAPI, savedAfter
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = savedCached, savedRequest
	print("auction rating sort OK")
end)()
-- Auction house: the work of a refresh is spread over frames
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedRating, savedAPI, savedAfter, savedClock = ns.ItemLinkRating, C_AuctionHouse, C_Timer.After, debugprofilestop
	local savedCached = C_Item.IsItemDataCachedByID
	local queue, clock, ratings, redraws = {}, 0, {}, 0
	C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
	local function Tick() table.remove(queue, 1)() end
	debugprofilestop = function() return clock end
	-- every rating costs 0.3 ms of the 0.5 ms slice
	ns.ItemLinkRating = function(link)
		clock = clock + 0.3
		local r = ratings[tonumber(link:match("item:(%d+)"))]
		if not r then return nil end
		return r[1], r[2]
	end
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end,
		GetItemKeySampleLink = function(key) return "|Hitem:" .. key.itemID .. "|h" end }
	C_Item.IsItemDataCachedByID = function() return true end
	local rows, provider = {}, nil
	for i = 1, 10 do rows[i] = { itemKey = { itemID = i }, minPrice = 10, totalQuantity = 1 } end
	local frame = { browseResults = rows, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, _, entry, count) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() redraws = redraws + 1 end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.scoreValueSort, A.db.hideVendorItems = false, true, false, false
	F.Apply()
	provider.count()
	while #queue > 0 do Tick() end
	-- "Upgrades" shows only rated upgrades: rows still waiting for item data are not shown yet
	assert(provider.count() == 0 and #F.State.loading == 10, "all rows judged, all waiting for item data")
	for i = 1, 10 do ratings[i] = { i, "ok" } end
	redraws = 0
	F.ItemInfo(A, "GET_ITEM_INFO_RECEIVED", 1)
	Tick()
	assert(#F.State.loading == 8, "rating again stops at the slice budget: " .. #F.State.loading)
	assert(redraws == 0, "the slice that changed the view does not redraw in the same frame")
	Tick()
	assert(redraws == 1, "Blizzard's list is redrawn on the next frame")
	while #queue > 0 do Tick() end
	local order = {}
	for i = 1, provider.count() do order[i] = provider.entry(i).itemKey.itemID end
	assert(#F.State.loading == 0 and table.concat(order, ",") == "10,9,8,7,6,5,4,3,2,1",
		"all rated in later slices and at their place: " .. table.concat(order, ","))
	A.db.scoreSort = false
	F.Apply()
	ns.ItemLinkRating, C_AuctionHouse, C_Timer.After, debugprofilestop = savedRating, savedAPI, savedAfter, savedClock
	C_Item.IsItemDataCachedByID = savedCached
	print("auction refresh slices OK")
end)()
-- Auction house: merchant goods hidden from the buy list
;(function()
	local A = ns:GetModule("Auction")
	local F = A.Filter
	local savedAPI, savedCdb = C_AuctionHouse, A.cdb
	C_AuctionHouse = { HasFullBrowseResults = function() return true end, RequestMoreBrowseResults = function() end }
	A.cdb = { vendorBuyPrices = { [424242] = 5 } }
	assert(A.IsMerchantGood(159) and A.IsMerchantGood(424242) and not A.IsMerchantGood(424243) and not A.IsMerchantGood(nil),
		"bundled list and own merchant visits")
	assert(A.IsMerchantGood(728) and A.IsMerchantGood(2697), "recipes of the recipe vendors (Westfall Stew, Goretusk Liver Pie)")
	local function row(id) return { itemKey = { itemID = id }, minPrice = 10, totalQuantity = 1 } end
	local provider
	local frame = { browseResults = { row(424243), row(159), row(424242), row(424244) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			SetDataProvider = function(_, _, entry, count) provider = { entry = entry, count = count } end,
			RefreshScrollFrame = function() end } }
	AuctionHouseFrame = { BrowseResultsFrame = frame }
	A.db.vendorBuyFilter, A.db.scoreSort, A.db.hideVendorItems = false, false, true
	F.Apply()
	local r = frame.browseResults
	assert(provider.count() == 2 and provider.entry(1) == r[1] and provider.entry(2) == r[4], "merchant goods left out, order kept")
	-- the first search after opening showed Blizzard's own list: a view that is on but not in place is put back
	local blizzardCount = function() return #frame.browseResults end
	frame.ItemList.getNumEntries = blizzardCount
	provider = nil
	F.Ensure(frame)
	assert(provider and provider.count() == 2, "the filtered view is put back in place")
	local own = provider
	provider = nil
	frame.ItemList.getNumEntries = own.count
	F.Ensure(frame)
	assert(provider == nil, "a view in place is left alone")
	-- Blizzard's clear button (the X) shows while an own filter is on and clears the own filters too
	local shown = false
	AuctionHouseFrame.SearchBar = { FilterButton = { ClearFiltersButton = { Show = function() shown = true end } } }
	A:OnOptionChanged("hideVendorItems")
	assert(shown and A.OwnFiltersOn(), "the X shows for an own filter")
	A.db.scoreSort = true
	A.ClearOwnFilters()
	assert(not A.OwnFiltersOn() and not A.db.hideVendorItems and not A.db.scoreSort, "the X clears the own filters")
	shown = false
	A:OnOptionChanged("hideVendorItems")
	assert(not shown, "no own filter, the X is Blizzard's alone")
	AuctionHouseFrame.SearchBar = nil
	A.db.hideVendorItems = false
	F.Apply()
	C_AuctionHouse, A.cdb = savedAPI, savedCdb
	print("auction merchant goods OK")
end)()
-- Auction house: quick buy plan
;(function()
	local A = ns:GetModule("Auction")
	local function row(price, quantity) return { itemKey = { itemID = 9001 }, minPrice = price, totalQuantity = quantity } end
	local id, count, unit, total = A.QuickBuyPlan(row(40, 10), 3)
	assert(id == 9001 and count == 3 and unit == 40 and total == 120, "quantity times the minimum price")
	assert(select(2, A.QuickBuyPlan(row(40, 2), 5)) == 2, "never more than offered")
	assert(select(2, A.QuickBuyPlan(row(40, 9), nil)) == 1 and select(2, A.QuickBuyPlan(row(40, 9), 0)) == 1, "at least one")
	assert(A.QuickBuyPlan(row(40, 0), 1) == nil and A.QuickBuyPlan(row(0, 5), 1) == nil, "no offer, no price: no plan")
	assert(A.QuickBuyPlan({ isVirtualEntry = true, minPrice = 5, totalQuantity = 5 }, 1) == nil, "virtual rows have no plan")
	assert(A.QuickBuyPlan({ minPrice = 5, totalQuantity = 5 }, 1) == nil and A.QuickBuyPlan(nil, 1) == nil, "no item, no plan")
	print("auction quick buy OK")
end)()
-- Bag sorting on open: one sort at a time, none while items are locked
;(function()
	local items = ns:GetModule("Items")
	local SortOnOpen = uv(uv(items.OnLogin, "QueueSort"), "SortOnOpen")
	local OnBagLayoutChanged = uv(items.OnLogin, "OnBagLayoutChanged")
	assert(SortOnOpen, "sort function")
	local saved = { C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo }
	local sorts, locked, now, ticker, itemId, slotReads = 0, false, 100, nil, 1, 0
	C_Container.SortBags = function() sorts = sorts + 1 end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot)
		slotReads = slotReads + 1
		return bag == 0 and slot == 1 and { isLocked = locked, itemID = itemId, stackCount = 1 } or nil
	end
	C_Timer.NewTicker = function(_, fn) ticker = { fn = fn, Cancel = function(self) self.dead = true end } return ticker end
	GetTime = function() return now end
	InCombatLockdown = function() return false end
	GetCursorInfo = function() return nil end
	items.db.autoSort = true
	for _, name in ipairs({ "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame", "ScrappingMachineFrame", "ItemSocketingFrame" }) do
		_G[name] = false
	end
	setuv(SortOnOpen, "sellTicker", nil)
	SortOnOpen()
	assert(sorts == 1 and ticker, "first sort runs and is watched")
	now = 110
	SortOnOpen()
	assert(sorts == 1, "no second sort while the first is watched")
	locked = true
	slotReads = 0
	ticker.fn(ticker); ticker.fn(ticker); ticker.fn(ticker)
	assert(not ticker.dead and slotReads == 2, "still running while locked, with one read for unchanged slots")
	locked = false
	now = 120
	SortOnOpen()
	assert(sorts == 1, "no sort before the bags were quiet")
	ticker.fn(ticker); ticker.fn(ticker)
	assert(ticker.dead, "over after two quiet looks")
	now = 125
	locked = true
	OnBagLayoutChanged(nil, nil, 0)
	SortOnOpen()
	assert(sorts == 1, "no sort while an item is locked")
	locked = false
	MerchantFrame = { IsShown = function() return true end }
	SortOnOpen()
	assert(sorts == 1, "no sort at a merchant")
	MerchantFrame = false
	now = 130
	slotReads = 0
	SortOnOpen()
	assert(sorts == 1, "no new sort while the sorted bags are unchanged (the junk must not jump to and fro)")
	assert(slotReads == 2, "locks and the unchanged layout are checked in a single slot pass")
	slotReads = 0
	SortOnOpen()
	assert(slotReads == 0, "the confirmed layout is reused until a bag event arrives")
	itemId = 2
	OnBagLayoutChanged(nil, nil, 0)
	local savedAfter, pending = C_Timer.After
	C_Timer.After = function(_, fn) pending = fn end
	SortOnOpen()
	assert(pending and sorts == 1, "the game sort runs after the inspection frame")
	OnBagLayoutChanged(nil, nil, 0)
	pending()
	assert(sorts == 1, "a bag change between inspection and execution cancels the stale sort")
	C_Timer.After = savedAfter
	SortOnOpen()
	assert(sorts == 2, "next sort afterwards")
	items.db.autoSort = false
	C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo = unpack(saved, 1, 7)
	print("bag sort OK")
end)()
;(function()
	-- Place texts: every name token resolves (the client's name or the English fallback), every key is a known place.
	local data = {}
	assert(loadfile("../Data/Places.lua"))("ForeverPlus", data)
	local keepPlaces = ns.Places
	ns.Places = data.Places
	local known = {}
	for _, place in ipairs(ns.Places) do known[place[4]] = true end
	local function Check(list, isInstance)
		for key, info in pairs(list) do
			assert(isInstance or known[key], "place of the text " .. tostring(key))
			for _, text in ipairs({ info.de, info.en }) do
				assert(not ns.PlaceText(text):find("%?") and not ns.PlaceText(text):find("{"), "names resolve in " .. tostring(key) .. ": " .. ns.PlaceText(text))
			end
		end
	end
	Check(ns.PlaceInfo, false)
	Check(ns.InstanceInfo, true)
	Check(ns.AreaInfo, true)
	local keepZone = GetRealZoneText
	GetRealZoneText = function() end
	assert(ns.PlaceText("in {m1431} / {a42} / {i36}") == "in Duskwood / Darkshire / The Deadmines", "english fallback names: " .. ns.PlaceText("in {m1431} / {a42} / {i36}"))
	GetRealZoneText = keepZone
	local saved = C_Map.GetMapInfo
	C_Map.GetMapInfo = function() return { name = "Dämmerwald" } end
	assert(ns.PlaceText("{m1431}") == "Dämmerwald", "the client's name wins")
	C_Map.GetMapInfo = saved
	ns.Places = keepPlaces
	print("place texts OK")
end)()

-- Nameplate quest marker: creatures whose drop a quest asks for
;(function()
	local quests = ns:GetModule("Quests")
	local plate = { IsForbidden = function() return false end, UnitFrame = {} }
	local isQuestUnit = uv(uv(quests.RefreshNameplates, "UpdateNameplate"), "IsQuestUnit")
	assert(isQuestUnit, "quest unit check")
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
	UnitIsPlayer = function() return false end
	UnitCanAttack = function() return true end
	Enum.TooltipDataLineType = { QuestObjective = 8 }
	C_TooltipInfo.GetUnit = function() return { lines = { { type = 8, leftText = "Klippeneberrippchen: 2/6" } } } end
	assert(isQuestUnit("nameplate1"), "found by the tooltip objective")
	C_TooltipInfo.GetUnit = function() return { lines = { { type = 0, leftText = "Wildtier" } } } end
	assert(not isQuestUnit("nameplate1"), "no objective, no marker")
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	assert(isQuestUnit("nameplate1"), "the game's flag still counts")
	UnitIsPlayer = function() return true end
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
	assert(not isQuestUnit("nameplate1"), "players are never quest units")
	print("nameplate quest marker OK", plate ~= nil)
end)()
-- Quest symbols share the nameplate rules in the unit tooltip and above the cursor.
;(function()
	local tip, quests = ns:GetModule("Tooltip"), ns:GetModule("Quests")
	local handler = uv(tip.OnInitialize, "OnUnitTooltip")
	local withIcon = uv(handler, "WithQuestIcon")
	local saved = { C_QuestLog, C_TooltipInfo, UnitIsPlayer, UnitCanAttack, UnitGUID, UnitName, UnitIsUnit,
		GameTooltip.GetUnit, GameTooltip.IsForbidden, GameTooltipTextLeft1, issecretvalue, ns.QuestData }
	local savedOptions = { tip.db.questIcon, quests.db.nameplateIcons, quests.db.dropObjectives }
	local sources = ns:GetModule("LootSources")
	local savedDrops = sources.DropsFrom
	local state = uv(uv(quests.IsQuestUnit, "DropObjectives"), "state")
	local related, player, scans = false, false, 0
	local data = { lines = { { type = Enum.TooltipDataLineType.QuestObjective, leftText = "Rippchen: 2/6" } } }
	C_QuestLog = { UnitIsRelatedToActiveQuest = function() return related end,
		GetQuestObjectives = function() return { { text = "Rippchen: 2/6", numFulfilled = 2, numRequired = 6, finished = false } } end,
		GetTitleForQuestID = function() return "Rippchen sammeln" end }
	C_TooltipInfo = { GetUnit = function() scans = scans + 1 return data end }
	UnitIsPlayer = function() return player end
	UnitCanAttack = function() return true end
	UnitGUID = function() return "Creature-0-0-0-0-123-0000000001" end
	UnitName = function() return "Klippeneber" end
	UnitIsUnit = function() return false end
	GameTooltip.GetUnit = function() return "Klippeneber", "mouseover" end
	GameTooltip.IsForbidden = function() return false end
	local text = "Klippeneber"
	GameTooltipTextLeft1 = { GetText = function() return text end, SetText = function(_, value) text = value end,
		GetTextColor = function() return 0.2, 0.6, 1 end }
	assert(tip.db.questIcon == true, "quest symbol is enabled by default")
	quests.db.nameplateIcons = false
	local marked = quests.unitIconPrefix .. "Klippeneber"
	assert(withIcon("Klippeneber", "mouseover", data) == marked and scans == 0,
		"tooltip objectives are reused even with nameplate symbols off")
	handler(GameTooltip, data)
	assert(text == marked, "quest symbol precedes the tooltip name")
	handler(GameTooltip, data)
	assert(text == marked, "tooltip updates do not duplicate the symbol")
	data.lines[1].leftText = "Rippchen: 6/6"
	related = true
	handler(GameTooltip, data)
	assert(text == "Klippeneber", "completed objectives remove the symbol despite the game's quest flag")
	data.lines[1].leftText = "Rippchen: 2/6"
	local showName = uv(tip.OnLogin, "ShowHoverName")
	local frame = uv(showName, "GetHover")()
	local savedSetText = frame.Name.SetText
	local hoverText
	frame.Name.SetText = function(_, value) hoverText = value end
	uv(showName, "Layout")(frame, data)
	assert(hoverText == marked, "same symbol precedes the name above the cursor")
	frame:Show()
	frame.object = false
	UnitIsUnit = function() return true end
	data.lines[1].leftText = "Rippchen: 6/6"
	handler(GameTooltip, data)
	assert(hoverText == "Klippeneber", "tooltip completion also updates the visible cursor name")
	data.lines[1].leftText = "Rippchen: 2/6"
	handler(GameTooltip, data)
	assert(hoverText == marked, "tooltip updates restore the cursor symbol for open objectives")
	tip.db.questIcon = false
	tip:OnOptionChanged("questIcon")
	assert(hoverText == "Klippeneber", "disabling immediately updates the visible cursor name")
	handler(GameTooltip, data)
	assert(text == "Klippeneber" and withIcon(marked, "mouseover", data) == "Klippeneber", "disabled symbol is removed")
	tip.db.questIcon = true
	related = false
	player = true
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "players get no quest symbol")
	player = false
	issecretvalue = function(value) return value == "secret-name" or value == "secret-unit" end
	assert(withIcon("secret-name", "mouseover", data) == "secret-name", "restricted names stay untouched")
	assert(withIcon("Klippeneber", "secret-unit", data) == "Klippeneber", "restricted unit tokens are not queried")
	assert(withIcon("Klippeneber", nil, data) == "Klippeneber", "missing unit tokens get no symbol")
	data = { lines = {} }
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "unrelated creatures get no symbol")
	ns.QuestData = { targets = { [999999] = { { "i", 999998 } } } }
	state[999999] = {}
	sources.DropsFrom = function(itemID, key) return itemID == 999998 and key == "npc:123" end
	quests.db.dropObjectives = true
	assert(withIcon("Klippeneber", "mouseover", data) == marked, "recorded quest drops use the shared marker rules")
	quests.db.dropObjectives = false
	assert(withIcon("Klippeneber", "mouseover", data) == "Klippeneber", "recorded drops respect their own option")
	GameTooltip.IsForbidden = function() return true end
	handler(GameTooltip, data)
	assert(text == "Klippeneber", "forbidden tooltips stay untouched")
	state[999999] = nil
	frame.Name.SetText = savedSetText
	sources.DropsFrom = savedDrops
	C_QuestLog, C_TooltipInfo, UnitIsPlayer, UnitCanAttack, UnitGUID, UnitName, UnitIsUnit,
		GameTooltip.GetUnit, GameTooltip.IsForbidden, GameTooltipTextLeft1, issecretvalue, ns.QuestData = unpack(saved, 1, 12)
	tip.db.questIcon, quests.db.nameplateIcons, quests.db.dropObjectives = unpack(savedOptions)
	print("quest symbols in tooltip and cursor name OK")
end)()
-- A native quest objective does not hide another open objective from the same creature's loot.
;(function()
	local quests = ns:GetModule("Quests")
	local handler = uv(quests.OnInitialize, "OnUnitTooltip")
	local state = uv(uv(handler, "DropObjectives"), "state")
	local questCall, lootCall
	for index, callback in ipairs(TEST_POSTCALLS) do
		local fn = uv(callback, "fn")
		if fn == handler then questCall = index end
		if fn and uv(fn, "MouseoverCreatureKey") then lootCall = index end
	end
	assert(questCall and lootCall and questCall < lootCall, "missing objectives precede the observed loot section")
	local savedLog, savedTypes, savedOption = C_QuestLog, Enum.TooltipDataLineType, quests.db.dropObjectives
	local savedAddLine, savedNumLines = GameTooltip.AddLine, GameTooltip.NumLines
	local questID = 92909
	local title, spring, stabilizer = "Die Ernter ernten", "Golemisofeder: 1/14", "Gyrostabilisator für Erntearbeiter: 5/5"
	local oldState = state[questID]
	quests.db.dropObjectives = true
	state[questID] = {}
	C_QuestLog = {
		GetQuestObjectives = function(id)
			if id == questID then
				return { { text = spring, numFulfilled = 1, numRequired = 14, finished = false },
					{ text = stabilizer, numFulfilled = 5, numRequired = 5, finished = true } }
			end
		end,
		GetTitleForQuestID = function() return title end,
	}
	local types = { QuestTitle = 17, QuestObjective = 8 }
	Enum.TooltipDataLineType = types
	local data = { guid = "Creature-0-0-0-0-114-0000000001", lines = {
		{ type = types.QuestTitle, id = questID, leftText = title, lineIndex = 4 },
		{ type = types.QuestObjective, leftText = stabilizer, completed = true, lineIndex = 5 },
	} }
	local added, numLines = {}, 5
	GameTooltip.AddLine = function(_, text) added[#added + 1] = text end
	GameTooltip.NumLines = function() return numLines end
	handler(GameTooltip, data)
	assert(#added == 1 and added[1] == "- " .. spring, "only the missing open drop follows the native quest block")
	added, numLines = {}, 6
	data.lines[3] = { type = types.QuestObjective, leftText = " |cffffffff- " .. spring .. "|r ", lineIndex = 6 }
	handler(GameTooltip, data)
	assert(#added == 0, "an already displayed objective is not duplicated")
	data.lines[3] = { type = types.QuestTitle, id = questID + 1, leftText = "Andere Quest", lineIndex = 6 }
	handler(GameTooltip, data)
	assert(#added == 2 and added[1] == title and added[2] == "- " .. spring, "a different trailing quest keeps its own heading")
	added, numLines, data.lines = {}, 3, {}
	handler(GameTooltip, data)
	assert(#added == 2 and added[1] == title and added[2] == "- " .. spring, "the recorded drop is also shown on its own")
	added = {}
	quests.db.dropObjectives = false
	handler(GameTooltip, data)
	assert(#added == 0, "the tooltip respects the recorded drop option")
	state[questID] = oldState
	C_QuestLog, Enum.TooltipDataLineType, quests.db.dropObjectives = savedLog, savedTypes, savedOption
	GameTooltip.AddLine, GameTooltip.NumLines = savedAddLine, savedNumLines
	print("missing quest objectives in unit tooltip OK")
end)()
-- Speech bubbles
;(function()
	local sb = ns:GetModule("SpeechBubbles")
	local saved = { UnitExists, UnitGUID, C_NamePlate, sb.db.fallback }
	local guid = { npc = "Creature-NPC", nameplate1 = "Creature-NPC" }
	local plate, playerPlate = CreateFrame("Frame"), CreateFrame("Frame")
	local plates = { npc = plate, nameplate1 = plate }
	UnitExists = function(unit) return guid[unit] ~= nil end
	UnitGUID = function(unit) return guid[unit] end
	C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }
	sb.db.fallback = true
	sb.Show("Willkommen, Reisender.")
	local bubble = uv(sb.Show, "speechBubble")
	local anchored
	bubble.SetPoint = function(_, _, to) anchored = to end
	sb.Show("Willkommen, Reisender.")
	assert(bubble:IsShown() and anchored == plate and bubble.Tail:IsShown(), "speech starts on the NPC's plate")
	guid.target, plates.npc = "Player-Other", playerPlate
	local watch = bubble:GetScript("OnUpdate")
	watch()
	assert(anchored == plate, "speech stays with the NPC when targeting a player")
	uv(sb.Apply, "OnPlateRemoved")(nil, nil, "nameplate1")
	watch()
	assert(anchored == UIParent and not bubble.Tail:IsShown(), "speech leaves a removed plate immediately")
	guid.nameplate1 = "Player-Other"
	uv(sb.Apply, "OnPlateAdded")(nil, nil, "nameplate1")
	assert(anchored == UIParent, "speech ignores the player on the recycled plate")
	guid.nameplate2, plates.nameplate2 = "Creature-NPC", plate
	uv(sb.Apply, "OnPlateAdded")(nil, nil, "nameplate2")
	assert(anchored == plate and bubble.Tail:IsShown(), "speech returns to the NPC")
	sb.Hide()
	sb.db.fallback = false
	sb.Show("Kein Platz am Bildschirm.")
	guid.nameplate2 = "Player-Other"
	watch()
	assert(not bubble:IsShown(), "speech hides when the NPC loses its plate and fallback is off")
	sb.Hide()
	bubble.SetPoint = nil
	UnitExists, UnitGUID, C_NamePlate, sb.db.fallback = unpack(saved, 1, 4)
	print("speech bubbles OK")
end)()
-- Diagnosis report
;(function()
	local dc = ns:GetModule("DataCapture")
	local text = dc.DiagnoseText()
	local errors = ns.L.DIAG_ERRORS:match("^(.-)%%d")
	assert(text:find("== ForeverPlus ==", 1, true) and text:find("== " .. errors, 1, true)
		and text:find("== " .. ns.L.DIAG_STATUS .. " ==", 1, true), "report sections")
	assert(text:find("== " .. ns.L.DIAG_CHANGED_OPTIONS .. " ==", 1, true), "options section")
	print("diagnose OK")
end)()
-- Loot sources
;(function()
	local S = ns:GetModule("LootSources")
	assert(S.SourceKey("Creature-0-4379-0-27-8931-00001F5C36") == "npc:8931", "corpse key")
	assert(S.SourceKey("GameObject-0-4379-0-27-2061-00001F5C36") == "object:2061", "node key")
	assert(S.SourceKey("Item-4379-0-400000001") == nil and S.SourceKey(nil) == nil, "containers and nothing are left out")
	ns.db.lootSources = {}
	S.count, S.merged = 0, nil
	S.Record("g1", "npc:777", { 100, 101 }, "Test Wolf")
	S.Record("g2", "npc:777", { 100 }, nil)
	local e = ns.db.lootSources["npc:777"]
	assert(e.windows == 2 and e.items[100] == 2 and e.items[101] == 1 and e.name == "Test Wolf", "windows and drops counted")
	assert(S.DropsFrom(100, "npc:777") and not S.DropsFrom(100, "npc:778") and not S.DropsFrom(99999999, "npc:777"), "drop lookup by source")
	local sources = S.Sources(100)
	assert(#sources >= 1 and sources[1].key == "npc:777" and sources[1].drops == 2 and sources[1].windows == 2, "own data in the lookup")
	-- shipped data and own windows add up
	local key, row
	for item, rows in pairs(ns.LootData.items) do key, row = item, rows[1] break end
	S.Record("g3", row[1], { key }, nil)
	local merged
	for _, s in ipairs(S.Sources(key)) do if s.key == row[1] then merged = s end end
	assert(merged and merged.drops == row[2] + 1 and merged.windows == row[3] + 1, "shipped and own windows add up")
	local text = S.ExportText(ns.db.lootSources)
	assert(text:find('{ "npc:777", "Test Wolf", 2, { [100] = 2, [101] = 1 } },', 1, true), "export line")
	ns.db.lootSources = {}
	S.count, S.merged = 0, nil
	-- names: unknown ones get the number, learned ones the client name
	local savedNames, savedGUID, savedUnitName = ns.LootData.names, UnitGUID, UnitName
	ns.LootData.names = { ["npc:8931"] = "?", ["npc:5"] = "Wolf" }
	ns.db.lootNames, S.nameCount = {}, 0
	assert(S.SourceName("npc:8931") == "Kreatur 8931" or S.SourceName("npc:8931") == "Creature 8931", "unknown name shows the number")
	assert(S.SourceName("npc:5") == "Wolf", "shipped name")
	UnitGUID, UnitName = function() return "Creature-0-4379-0-27-8931-00001F5C36" end, function() return "Zottel" end
	S.LearnName("mouseover")
	assert(S.SourceName("npc:8931") == "Zottel", "learned name replaces the number")
	UnitGUID = function() return "Creature-0-4379-0-27-999-00001F5C36" end
	S.LearnName("mouseover")
	assert(ns.db.lootNames["npc:999"] == nil, "units without a loot source are not stored")
	UnitGUID, UnitName, ns.LootData.names = savedGUID, savedUnitName, savedNames
	ns.db.lootNames, S.nameCount = {}, 0
	-- /fp daten export collects every recording
	ns.db.innkeepers = { [1] = { "Wirt", 1436, 10, 20, "A" } }
	local DC = ns:GetModule("DataCapture")
	local all = DC.ExportText()
	assert(all and all:find('{ 1, 1436, 10.0, 20.0, "A", "Wirt" },', 1, true), "combined export holds the innkeepers")
	assert(all:find("^%-%- @fp%-export 1 build=") and all:find("-- @fp inns", 1, true) and all:find("issues/new", 1, true), "export header and section tag")
	ns.db.innkeepers = {}
	print("loot sources OK")
end)()
;(function()
	local loot, items = ns:GetModule("LootSources"), ns:GetModule("Items")
	local savedSources, savedCount, savedMerged = ns.db.lootSources, loot.count, loot.merged
	local savedRecord, savedFastLoot, savedToggle = loot.db.record, items.db.fastLoot, loot.ToggleEvent
	local savedNum, savedType, savedLink, savedSource = GetNumLootItems, GetLootSlotType, GetLootSlotLink, GetLootSourceInfo
	local savedFishing, savedSlot, savedCVar, savedClick = IsFishingLoot, LootSlot, GetCVarBool, IsModifiedClick
	local savedGUID, savedName, savedSecret = UnitGUID, UnitName, issecretvalue
	local observations = ns:GetModule("Observations")
	local savedCreature, observed = observations.Creature, 0
	observations.Creature = function() observed = observed + 1 end
	ns.db.lootSources, loot.count, loot.merged = {}, 0, nil
	loot.db.record, items.db.fastLoot = true, true
	local handlers = {}
	loot.ToggleEvent = function(_, event, _, fn) handlers[event] = fn end
	loot:Apply()
	loot.ToggleEvent = savedToggle
	local first = "Creature-0-1-2-3-999981-0001"
	local second = "Creature-0-1-2-3-999981-0002"
	local third = "Creature-0-1-2-3-999982-0001"
	local key = "npc:999981"
	local window = { { 1, "item:35", first, 2, second, 1 }, { 1, "item:35", first, 1 }, { 2, nil, second, 15 } }
	GetNumLootItems = function() return #window end
	GetLootSlotType = function(i) return window[i][1] end
	GetLootSlotLink = function(i) return window[i][2] end
	GetLootSourceInfo = function(i)
		local slot = window[i]
		return unpack(slot, 3, slot[5] and 6 or 4)
	end
	IsFishingLoot = function() return false end
	GetCVarBool = function() return true end
	IsModifiedClick = function() return false end
	UnitGUID = function(unit) return unit == "mouseover" and first end
	UnitName = function() return "Wolf" end
	issecretvalue = function(v) return v == "secret" end
	LootSlot = function(i)
		assert(ns.db.lootSources[key] and ns.db.lootSources[key].windows == 2, "fast loot records every corpse before looting")
		table.remove(window, i)
	end
	items:LOOT_READY()
	local entry = ns.db.lootSources[key]
	assert(#window == 0 and entry.items[35] == 2 and entry.name == "Wolf" and observed == 2,
		"shared and duplicate item slots count once per corpse")
	handlers.LOOT_OPENED()
	window = { { 1, "item:35", first, 1 } }
	handlers.LOOT_OPENED()
	assert(entry.windows == 2, "reopening the same corpse and overlapping loot events do not double count")
	items.db.fastLoot = false
	window = { { 1, "secret", third, 1 } }
	handlers.LOOT_READY()
	window = { { 1, "item:25", third, 1 } }
	assert(not ns.db.lootSources["npc:999982"], "a protected item leaves the snapshot available to retry")
	handlers.UNIT_SPELLCAST_SENT(nil, nil, "player", nil, "skinning", 8613)
	handlers.LOOT_READY()
	assert(not ns.db.lootSources["npc:999982"], "skinning does not count as corpse loot")
	handlers.UNIT_SPELLCAST_INTERRUPTED(nil, nil, "player", "skinning")
	handlers.LOOT_OPENED(nil, nil, false, true)
	assert(not ns.db.lootSources["npc:999982"], "opening a bag item does not record a corpse")
	handlers.LOOT_OPENED()
	assert(ns.db.lootSources["npc:999982"].items[25] == 1, "manual opening retries once loot is readable")
	window = { { 2, nil, "Creature-0-1-2-3-999982-0002", 40 } }
	handlers.LOOT_READY()
	assert(ns.db.lootSources["npc:999982"].windows == 2, "a money-only corpse counts toward the number of windows")
	loot.db.record = false
	window = { { 1, "item:25", "Creature-0-1-2-3-999983-0001", 1 } }
	loot.CaptureWindow()
	assert(not ns.db.lootSources["npc:999983"], "recording off leaves the saved data alone")
	assert(ns:GetModule("DataCapture").DiagnoseText():find(ns.L.LOOTSRC_STATUS:format(NO, 2, 4), 1, true), "diagnosis shows saved loot counts")
	GetNumLootItems, GetLootSlotType, GetLootSlotLink, GetLootSourceInfo = savedNum, savedType, savedLink, savedSource
	IsFishingLoot, LootSlot, GetCVarBool, IsModifiedClick = savedFishing, savedSlot, savedCVar, savedClick
	UnitGUID, UnitName, issecretvalue, observations.Creature = savedGUID, savedName, savedSecret, savedCreature
	loot.db.record, items.db.fastLoot = savedRecord, savedFastLoot
	ns.db.lootSources, loot.count, loot.merged = savedSources, savedCount, savedMerged
	print("loot capture before fast loot OK")
end)()
;(function()
	local loot, tooltipModule = ns:GetModule("LootSources"), ns:GetModule("Tooltip")
	local onShift = uv(tooltipModule.OnLogin, "OnShiftChanged")
	local onUnit
	for _, callback in ipairs(TEST_POSTCALLS) do
		local fn = uv(callback, "fn")
		if fn and uv(fn, "MouseoverCreatureKey") then onUnit = callback break end
	end
	assert(onUnit, "loot is registered for unit tooltips")
	local savedTooltip, savedItem, savedGUID, savedAttack, savedShift = GameTooltip, C_Item, UnitGUID, UnitCanAttack, IsShiftKeyDown
	local savedItems, savedSources, savedCount, savedMerged = ns.LootData.items, ns.db.lootSources, loot.count, loot.merged
	local savedShiftInfo, savedUnitLoot = tooltipModule.db.shiftInfo, loot.db.unitLoot
	local guid = "Creature-0-1-2-3-999987-0001"
	local data = { type = Enum.TooltipDataType.Unit, guid = guid, lines = {} }
	local shift, attackable, mouseover, requests = false, true, guid, 0
	local lines, drops = {}, {}
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.infoList = { { tooltipData = data } }
	GameTooltip.GetPrimaryTooltipData = function() return data end
	GameTooltip.AddLine = function(_, line) lines[#lines + 1] = line end
	GameTooltip.AddDoubleLine = function(_, name, rate) drops[#drops + 1] = { name, rate } end
	GameTooltip.RefreshData = function()
		wipe(lines)
		wipe(drops)
		onUnit(GameTooltip, data)
	end
	UnitGUID = function() return mouseover end
	UnitCanAttack = function() return attackable end
	IsShiftKeyDown = function() return shift end
	local loaded = false
	C_Item = { GetItemInfo = function(id) if id ~= 2 or loaded then return "Drop " .. id, nil, 2 end end,
		RequestLoadItemDataByID = function(id) assert(id == 2) requests = requests + 1 end }
	local key = "npc:999987"
	ns.LootData.items = { [1] = { { key, 750, 2000 } }, [3] = { { key, 2100, 2000 } } }
	ns.db.lootSources = { [key] = { windows = 1, items = { [1] = 1, [2] = 1 } } }
	tooltipModule.db.shiftInfo, loot.db.unitLoot = false, true
	onUnit(GameTooltip, data)
	assert(#lines == 0 and requests == 0, "without Shift the creature tooltip does no loot work")
	shift = true
	onShift(nil, nil, "LSHIFT")
	assert(lines[2] == ns.L.LOOTSRC_UNIT_HEADER and #drops == 3, "pressing Shift adds loot independently of the global Shift setting")
	assert(lines[3] == ns.L.LOOTSRC_UNIT_OWN_WINDOWS:format(1), "local windows are visible separately")
	assert(drops[1][1] == "Drop 3" and drops[1][2] == ns.L.LOOTSRC_UNIT_COUNT:format(2100, 2001), "multiple slots show counts")
	assert(drops[2][1] == "Drop 1" and drops[2][2]:find("751", 1, true), "common drops first with both sets of records")
	assert(requests == 1 and drops[3][1] == ns.L.LOOTSRC_UNIT_ITEM:format(2)
		and drops[3][2] == ns.L.LOOTSRC_SHARE:format(ns.L.LOOTSRC_UNIT_BELOW, 1, 2001), "local-only drop uses all windows")
	local callbacks = {}
	local savedToggle, savedAfter = loot.ToggleEvent, ns.After
	loot.ToggleEvent = function(_, event, _, callback) callbacks[event] = callback end
	loot:Apply()
	loot.ToggleEvent = savedToggle
	local refresh
	ns.After = function(_, _, fn) refresh = fn end
	loaded = true
	callbacks.ITEM_DATA_LOAD_RESULT(nil, nil, 2, true)
	refresh()
	ns.After = savedAfter
	assert(drops[3][1] == "Drop 2" and requests == 1, "item data refreshes the visible name without repeating the request")
	loot.Record("tooltip-test", key, { 1 }, nil)
	GameTooltip:RefreshData()
	assert(drops[2][2]:find("752", 1, true), "new loot updates the cached list")
	shift = false
	onShift(nil, nil, "RSHIFT")
	assert(#lines == 0 and #drops == 0, "releasing Shift clears the section")
	shift, attackable = true, false
	onUnit(GameTooltip, data)
	assert(#lines == 0, "friendly creatures do not get the loot section")
	attackable, mouseover = true, "Creature-0-1-2-3-999986-0001"
	onUnit(GameTooltip, data)
	assert(#lines == 0, "another unit's tooltip does not get the mouseover loot")
	data.guid = mouseover
	onUnit(GameTooltip, data)
	assert(lines[3] == ns.L.LOOTSRC_UNIT_EMPTY, "missing data shows a clear message")
	loot.db.unitLoot = false
	GameTooltip:RefreshData()
	assert(#lines == 0, "loot option can be disabled")
	ns.LootData.items, ns.db.lootSources, loot.count, loot.merged = savedItems, savedSources, savedCount, savedMerged
	local onUnitTooltip = uv(onUnit, "fn")
	setuv(uv(onUnitTooltip, "CreatureDrops"), "shippedByCreature", nil)
	tooltipModule.db.shiftInfo, loot.db.unitLoot = savedShiftInfo, savedUnitLoot
	GameTooltip, C_Item, UnitGUID, UnitCanAttack, IsShiftKeyDown = savedTooltip, savedItem, savedGUID, savedAttack, savedShift
	print("enemy loot tooltip OK")
end)()
-- Observations
;(function()
	local O = ns:GetModule("Observations")
	-- cells merge close points
	local cells = {}
	O.AddCell(cells, 1436, 50.0, 50.0)
	O.AddCell(cells, 1436, 50.5, 50.4)
	O.AddCell(cells, 1436, 60.0, 50.0)
	assert(#cells == 2 and cells[1][4] == 2, "close points merge into one cell")
	-- NPC quests from the gossip window
	ns.db.npcQuests, ns.db.objectivePoints, ns.db.creaturePoints = {}, {}, {}
	O.npcCount, O.objectiveCount, O.creatureCount = 0, 0, 0
	UnitGUID = function() return "Creature-0-4379-0-27-8931-00001F5C36" end
	UnitName = function() return "Gastwirtin Heather" end
	C_Map.GetBestMapForUnit = function() return 1436 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	C_GossipInfo = { GetAvailableQuests = function() return { { questID = 11 }, { questID = 12 } } end,
		GetActiveQuests = function() return { { questID = 13, isComplete = true }, { questID = 14, isComplete = false } } end }
	ns:GetModule("Observations").RecordNpc(O.NpcID(UnitGUID("npc")), "offers", { 11, 12 })
	ns:GetModule("Observations").RecordNpc(8931, "takes", { 13 })
	local npc = O.Npc(8931)
	assert(npc and npc.offers[11] and npc.offers[12] and npc.takes[13] and not npc.takes[14] and npc.name == "Gastwirtin Heather", "NPC quests remembered")
	assert(#O.Takers(13) == 1 and O.Takers(13)[1].id == 8931, "who takes a quest back")
	-- shipped recordings are part of the lookup
	local shipped, row = next(ns.QuestData.npcs)
	assert(O.Npc(shipped).name == row[1], "shipped NPC")
	-- objective counts going up record where the player stood
	local count = 0
	C_QuestLog.GetQuestObjectives = function() return { { numFulfilled = count, finished = false } } end
	O.OnObjectiveUpdate(700)
	count = 3
	O.OnObjectiveUpdate(700)
	local points = O.ObjectivePoints(700, 1)
	assert(#points == 1 and points[1][1] == 1436 and points[1][2] == 50 and points[1][3] == 50, "objective point recorded")
	O.OnObjectiveUpdate(700)
	assert(#O.ObjectivePoints(700, 1) == 1 and ns.db.objectivePoints[700][1][1][4] == 1, "no change, no new point")
	-- the count arrives only after QUEST_WATCH_UPDATE: read again at the next QUEST_LOG_UPDATE, once
	local handlers = {}
	local savedToggle = O.ToggleEvent
	O.ToggleEvent = function(_, event, _, fn) handlers[event] = fn end
	O:Apply()
	O.ToggleEvent = savedToggle
	count = 0
	handlers.QUEST_WATCH_UPDATE(nil, "QUEST_WATCH_UPDATE", 701)
	assert(not ns.db.objectivePoints[701], "count not up yet")
	count = 4
	handlers.QUEST_LOG_UPDATE()
	handlers.QUEST_LOG_UPDATE()
	assert(ns.db.objectivePoints[701] and ns.db.objectivePoints[701][1][1][4] == 1, "recorded at the quest log update, once")
	-- the first update after loading only sets the counts: a count already reached gets no point here
	count = 2
	O.OnObjectiveUpdate(703, "watch")
	assert(not ns.db.objectivePoints[703], "count reached before /reload: no point")
	assert(ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("703/1", 1, true)
		and ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("Anfang", 1, true), ns.db.objectiveTrace[#ns.db.objectiveTrace])
	count = 3
	O.OnObjectiveUpdate(703, "log")
	assert(ns.db.objectivePoints[703] and ns.db.objectivePoints[703][1][1][4] == 1, "next step after loading is recorded")
	-- a progress bar counts in percent
	local percent = 0
	GetQuestProgressBarPercent = function() return percent end
	C_QuestLog.GetQuestObjectives = function() return { { type = "progressbar", numFulfilled = 0, finished = false } } end
	O.OnObjectiveUpdate(702)
	percent = 40
	O.OnObjectiveUpdate(702)
	GetQuestProgressBarPercent = nil
	assert(ns.db.objectivePoints[702], "progress bar point")
	assert(#ns.db.objectiveTrace > 0 and ns.db.objectiveTrace[#ns.db.objectiveTrace]:find("702/1 progressbar 40", 1, true),
		ns.db.objectiveTrace[#ns.db.objectiveTrace])
	O.db.record = true
	O.Creature(6)
	O.Creature(6)
	assert(ns.db.creaturePoints[6][1][4] == 2, "creature cell counted twice")
	local text = O.ExportText()
	assert(text:find('{ 8931, "Gastwirtin Heather", { 11, 12 }, { 13 }, { { 1436, 50.0, 50.0, 2 } } },', 1, true), "NPC export line")
	assert(text:find("{ 700, 1, { { 1436, 50.0, 50.0, 1 } } },", 1, true), "objective export line")
	assert(text:find("{ 6, { { 1436, 50.0, 50.0, 2 } } },", 1, true), "creature export line")
	-- quest targets: a creature objective leads to the places where that creature was seen
	local quest, targets
	for q, list in pairs(ns.QuestData.targets) do
		for _, t in ipairs(list) do
			if t[1] == "m" and #O.CreaturePoints(t[2]) > 0 then quest, targets = q, t break end
		end
		if quest then break end
	end
	assert(quest, "a shipped quest with a creature that has positions")
	local ordinal = 0
	for _, t in ipairs(ns.QuestData.targets[quest]) do
		if t[1] == "m" then ordinal = ordinal + 1 end
		if t == targets then break end
	end
	assert(#O.TargetPoints(quest, "monster", ordinal) > 0, "creature objective: points of the creature")
	assert(#O.TargetPoints(quest, "monster", 99) == 0 and #O.TargetPoints(0, "monster", 1) == 0, "no target, no points")
	-- quest requirements: level, side, race and the quest before
	local info = ns:GetModule("QuestieInfo")
	local savedRequirements = ns.QuestData.requirements
	ns.QuestData.requirements = {
		[9001] = { 20, 0, {} }, [9002] = { 1, "H", {} }, [9003] = { 1, { 3, 4 }, {} }, [9004] = { 1, 0, { 9005, 9006 } },
	}
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 9006 end
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	UnitLevel = function() return 19 end
	UnitFactionGroup = function() return "Alliance" end
	UnitRace = function() return "Zwerg", "Dwarf", 3 end
	assert(not info.OwnAvailable(9001), "level too low")
	UnitLevel = function() return 20 end
	assert(info.OwnAvailable(9001), "level reached")
	assert(not info.OwnAvailable(9002), "Horde quest for an Alliance player")
	assert(info.OwnAvailable(9003), "race in the list")
	UnitRace = function() return "Mensch", "Human", 1 end
	assert(not info.OwnAvailable(9003), "race not in the list")
	assert(info.OwnAvailable(9004), "one quest before it is done")
	assert(not info.OwnAvailable(9006), "done quests are not offered")
	ns.QuestData.requirements = savedRequirements
	ns.db.npcQuests, ns.db.objectivePoints, ns.db.creaturePoints = {}, {}, {}
	O.npcCount, O.objectiveCount, O.creatureCount = 0, 0, 0
	print("observations OK")
end)()
-- Gathering tracking reminder
;(function()
	local B = ns:GetModule("Buffs")
	local active = false
	C_Minimap = { GetNumTrackingTypes = function() return 3 end,
		GetTrackingInfo = function(i) return { active = active and i == 2, spellID = i == 2 and 2383 or 1000 + i } end }
	assert(B.TrackingActive({ 2383, 2580 }) == false, "nothing tracked")
	active = true
	assert(B.TrackingActive({ 2383, 2580 }) == true, "Find Herbs tracked")
	assert(B.TrackingActive({ 2580 }) == false, "another ability is not the tracked one")
	print("tracking reminder OK")
end)()
-- World map filter menu
;(function()
	local WM = ns:GetModule("WorldMap")
	local library = ns:GetModule("Library")
	local texts, setters, nested = {}, {}, 0
	local values = {}
	Settings.SetValue = function(var, value) values[var] = value end
	local setOption = ns.SetOption
	ns.SetOption = function(moduleName, key, value) values["ForeverPlus_" .. moduleName .. "_" .. key] = value end
	local function node(depth, parent)
		return { CreateDivider = function() end, CreateTitle = function(_, t) texts[#texts + 1] = "# " .. t end,
			CreateRadio = function(_, name, isOn, set) setters[name .. depth] = { isOn = isOn, set = set } end,
			CreateColorSwatch = function(_, name, onClick, color)
				setters[name] = { set = onClick, color = color }
				return { SetTooltip = function() end }
			end,
			CreateButton = function(_, name)
				texts[#texts + 1] = (depth > 0 and "  " or "") .. name
				nested = nested + 1
				return node(depth + 1, name)
			end,
			CreateCheckbox = function(_, name, isOn, set)
				texts[#texts + 1] = (depth > 0 and "  " or "") .. name
				setters[name] = { isOn = isOn, set = set, parent = parent }
				if depth > 0 then nested = nested + 1 end
				local box = node(depth + 1, name)
				box.SetTooltip = function() end
				return box
			end }
	end
	WM.db.filterMenu = false
	WM.AddFilterMenu(node(0))
	assert(#texts == 0, "option off: no entries")
	WM.db.filterMenu = true
	WM.AddFilterMenu(node(0))
	assert(texts[1] == "# " .. ns.L.MENU_EXTRAS, "localized heading for the extra map filters")
	assert(setters[ns.L.WORLDMAP_FLIGHTS] and setters[ns.L.WORLDMAP_INNS] and setters[ns.L.LIBRARY_SYMBOLS]
		and setters[ns.L.TRANSPORTS_DOCKS] and setters[ns.L.RADAR_TITLE], "symbols, books, docks and radar present")
	local discoveries, books = setters[ns.L.WORLDMAP_DISCOVERIES], setters[ns.L.LIBRARY_SYMBOLS]
	assert(discoveries and books and discoveries.parent == ns.L.WORLDMAP_DISCOVERIES_MENU and books.parent == ns.L.WORLDMAP_DISCOVERIES_MENU,
		"discoveries and books are in the Secrets submenu")
	assert(not discoveries.isOn(), "discoveries filter starts off")
	local savedBooks = library.db.symbols
	library.db.symbols = true
	assert(books.isOn(), "books keep their independent setting while discoveries are off")
	books.set()
	assert(values.ForeverPlus_Library_symbols == false and values.ForeverPlus_WorldMap_discoveries == nil,
		"the book filter only changes book markers")
	library.db.symbols = savedBooks
	discoveries.set()
	assert(values.ForeverPlus_WorldMap_discoveries == true, "the map filter enables discoveries")
	assert(nested >= 3, "recipe radar options as a submenu")
	local swatch = setters[ns.L.WORLDMAP_REVEAL_COLOR]
	assert(swatch and swatch.set == WM.ChooseTint and swatch.color.g == 1 and swatch.color.r == 0.75, "colour entry with the current tint")
	WM.db.flightPoints = true
	assert(setters[ns.L.WORLDMAP_FLIGHTS].isOn() == true, "state read from the option")
	setters[ns.L.WORLDMAP_FLIGHTS].set()
	assert(values.ForeverPlus_WorldMap_flightPoints == false, "click switches the option")
	setters[ns.L.RADAR_TITLE].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_worldMap ~= nil, "radar entry switches on")
	ns.SetOption = setOption
	print("map filter menu OK")
end)()
;(function()
	-- Readables: the material decides the look, a book shows two pages, Blizzard's window gives back its room
	local R = ns:GetModule("Readable")
	assert(R.Look(nil, 1, false) == "SHEET", "a single sheet on parchment")
	assert(R.Look("Parchment", 1, true) == "BOOK" and R.Look("Parchment", 2, false) == "BOOK", "several pages: a book")
	assert(R.Look("ParchmentLarge", 1, false) == "BOOK", "the large parchment is a book")
-- Choices in menus keep the menu open
;(function()
	MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
	local response, picked
	local parent = { CreateRadio = function(_, text, isSelected, setSelected, data)
		return { text = text, isSelected = isSelected, setSelected = setSelected, data = data,
			SetResponse = function(_, value) response = value end }
	end }
	local radio = ns.CreateMenuRadio(parent, "60 %", function() return true end, function(value) picked = value end, 60)
	radio.setSelected(radio.data)
	assert(radio.text == "60 %" and radio.isSelected() and picked == 60, "text, state and choice passed through")
	assert(response == MenuResponse.Refresh, "the menu stays open after a choice")
	local sizes = 0
	parent.CreateButton = function() return { CreateRadio = function(...) sizes = sizes + 1 return parent.CreateRadio(...) end } end
	response = nil
	ns.CreateSizeMenu(parent, "Size", "WorldMap", "symbolScale")
	assert(sizes == 6 and response == MenuResponse.Refresh, "size menus stay open too")
	print("menu choices OK")
end)()
	local look, material = R.Look("Stone", 1, true)
	assert(look == "SHEET" and material == "Stone", "stone stays a plate, also with several pages")
	assert(select(2, R.Look("Valentine", 1, false)) == "Parchment", "unknown material on parchment")
	assert(R.TextHeight(400, 0) == 400 and R.TextHeight(400, nil) == 400, "text keeps the page height before layout")
	assert(R.TextHeight(400, 620) == 630, "longer text grows and scrolls")
	-- the book font as a copy without outline, every alphabet kept, at the height the game uses now
	do
		local savedFamily, made = CreateFontFamily, nil
		CreateFontFamily = function(name, list) made = list return { name = name } end
		TestBookFont = { GetFont = function() return "Fonts\\MORPHEUS.ttf", 18, "OUTLINE" end }
		ns.FontFamilies.families.TestBookFont = { roman = { "Fonts\\MORPHEUS.ttf", 15 }, russian = { "Fonts\\MORPHEUS_CYR.TTF", 15 } }
		local plain = ns.PlainFont("TestBookFont")
		assert(plain ~= TestBookFont and made and #made == 2, "a family of its own")
		for _, member in ipairs(made) do
			assert(member.flags == "" and member.height == 18, "no outline, current height: " .. member.alphabet)
		end
		assert(ns.PlainFont("TestBookFont") == plain, "made once")
		CreateFontFamily = savedFamily
	end
	-- the outline option leaves our own font families alone when it runs again for a later addon (it made the
	-- book font one outlined file of another alphabet)
	do
		local own = NewFont("ForeverPlusFontFamily999", 15)
		own.face = "Fonts\\K_Pagetext.ttf"
		local savedGetFonts = GetFonts
		GetFonts = function() return { "ForeverPlusFontFamily999" } end
		local eventFrame = uv(ns.RegisterEvent, "eventFrame")
		eventFrame:GetScript("OnEvent")(eventFrame, "ADDON_LOADED", "Blizzard_Test")
		assert(own.flags == "", "own font family keeps no outline: " .. own.flags)
		GetFonts, ForeverPlusFontFamily999 = savedGetFonts, nil
	end
	-- a book of five pages, as the game hands them out one at a time
	local saved = { ItemTextFrame, ItemTextGetPage, ItemTextHasNextPage, ItemTextGetMaterial, ItemTextGetItem,
		ItemTextGetText, ItemTextGetCreator, ItemTextNextPage, ItemTextPrevPage, C_Timer.After }
	local current, last = 1, 5
	local function Ready()
		R.Show()
	end
	ItemTextGetPage, ItemTextHasNextPage = function() return current end, function() return current < last end
	ItemTextGetMaterial, ItemTextGetItem = function() return "Parchment" end, function() return "Ein Buch" end
	ItemTextGetText, ItemTextGetCreator = function() return "Seite " .. current end, function() return nil end
	local asked = 0
	ItemTextNextPage = function() asked = asked + 1; current = current + 1; Ready() end
	ItemTextPrevPage = function() asked = asked + 1; current = current - 1; Ready() end
	C_Timer.After = function() end
	local window = NewFrame("Frame", "ItemTextFrame")
	local scale = 1
	window.SetScale = function(_, value) scale = value end
	window.GetScale = function() return scale end
	ItemTextFrame = window
	R.db.enabled = true
	R.ResetSpread()
	Ready()
	local spread = R.spread
	assert(spread.left.page == 1 and spread.right.page == 2 and spread.right.text == "Seite 2", "opens on pages 1 and 2")
	assert(scale == 0.001 and window.alpha == 0, "Blizzard's window collapsed while the book shows")
	assert(not R.CanTurn(false) and R.CanTurn(true), "only forward from the first spread")
	local traced = table.concat(ns.db.readableTrace or {}, "\n")
	for page = 1, 2 do
		local label = strtrim(ns.L.READABLE_TRACE_STYLE:format(page, "BOOK", "Parchment", "Text", 7, "", "", ""))
		assert(traced:find(label, 1, true), "pages in the trace: " .. traced)
	end
	R.Turn(true)
	assert(R.spread.left.page == 3 and R.spread.right.page == 4, "forward: pages 3 and 4")
	R.Turn(true)
	assert(R.spread.left.page == 5 and not R.spread.right and not R.CanTurn(true), "last page alone on the left")
	asked = 0
	R.Turn(false)
	assert(R.spread.left.page == 3 and R.spread.right.page == 4 and asked == 3, "back: two pages down, then the right one")
	R.Hide()
	assert(scale == 1 and window.alpha == 1 and not R.spread.left, "window given back on closing")
	-- a stone plate with two pages turns one page at a time
	ItemTextGetMaterial = function() return "Stone" end
	current, last = 1, 2
	Ready()
	assert(not R.spread.left, "no spread for a plate")
	R.Turn(true)
	assert(current == 2, "plate turned to page 2")
	R.Hide()
	ItemTextFrame, ItemTextGetPage, ItemTextHasNextPage, ItemTextGetMaterial, ItemTextGetItem, ItemTextGetText,
		ItemTextGetCreator, ItemTextNextPage, ItemTextPrevPage, C_Timer.After = unpack(saved, 1, 10)
	print("readable OK")
end)()
;(function()
	local readable = ns:GetModule("Readable")
	local oldTooltip, oldContainerInfo = GameTooltip, C_Container.GetContainerItemInfo
	local oldPage, oldTitle, oldText = ItemTextGetPage, ItemTextGetItem, ItemTextGetText
	local oldStatus, oldEnabled, oldTitles = readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles
	local title, line, red, titleRed = "Chronik von Azeroth"
	local oldGray, oldFirst = GRAY_FONT_COLOR, GameTooltipTextLeft1
	GameTooltipTextLeft1 = { SetTextColor = function(_, r) titleRed = r end }
	GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
	local getter = "GetBagItem"
	local isReadable = true
	GameTooltip = NewFrame("GameTooltip")
	GameTooltip.GetProcessingTooltipInfo = function()
		return { getterName = getter, getterArgs = { 0, 1 } }
	end
	GameTooltip.AddLine = function(_, value, r) line, red = value, r end
	C_Container.GetContainerItemInfo = function(bag, slot)
		if bag == 0 and slot == 1 then return { isReadable = isReadable } end
	end
	ItemTextGetPage = function() return 1 end
	ItemTextGetItem = function() return title end
	ItemTextGetText = function() return "Erste Seite" end
	readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles = true, false, {}
	local calls = {}
	local addPostCall = TooltipDataProcessor.AddTooltipPostCall
	TooltipDataProcessor.AddTooltipPostCall = function(kind, fn) calls[kind] = fn end
	readable:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall = addPostCall
	local function Hover(kind, name)
		line, titleRed = nil, nil
		calls[kind](GameTooltip, { lines = { { leftText = name } } })
		return line
	end
	local types = Enum.TooltipDataType
	assert(Hover(types.Item, title) == ns.L.READABLE_UNREAD, "unopened book in the bag")
	getter = "GetWorldCursor"
	assert(Hover(types.Object, title) == nil, "no unread label on an unknown world object")
	readable.Show()
	assert(Hover(types.Object, title) == ns.L.READABLE_ALREADY_READ, "a text from the normal reading window counts")
	getter = "GetBagItem"
	assert(Hover(types.Item, title) == ns.L.READABLE_ALREADY_READ, "known book in the bag")
	assert(red == 0.5, "already read is shown in grey")
	isReadable = false
	assert(Hover(types.Item, title) == nil, "a non-readable item with the same title is ignored")
	getter = "GetWorldCursor"
	readable.db.readStatus = false
	assert(Hover(types.Object, title) == nil, "tooltip option can be disabled")
	assert(titleRed == 0.5, "opened text keeps its grey title without the option")
	assert(Hover(types.Object, "Anderes Buch") == nil and titleRed == nil, "unopened text keeps its title colour")
	ItemTextGetItem = function() return "Anderes Buch" end
	readable.Show()
	assert(readable.cdb.openedTitles["Anderes Buch"], "texts are recorded without the option")
	GameTooltipTextLeft1 = oldFirst
	GameTooltip, C_Container.GetContainerItemInfo, GRAY_FONT_COLOR = oldTooltip, oldContainerInfo, oldGray
	ItemTextGetPage, ItemTextGetItem, ItemTextGetText = oldPage, oldTitle, oldText
	readable.db.readStatus, readable.db.enabled, readable.cdb.openedTitles = oldStatus, oldEnabled, oldTitles
	print("read status on mouseover OK")
end)()
;(function()
	-- Coordinates with one decimal place or, with the option, whole numbers
	local M = ns:GetModule("Minimap")
	local saved = M.db.wholeCoords
	M.db.wholeCoords = false
	assert(M.Format(45.34, 61.75) == "45.3, 61.8", M.Format(45.34, 61.75))
	M.db.wholeCoords = true
	assert(M.Format(45.34, 61.75) == "45, 62", M.Format(45.34, 61.75))
	M.db.wholeCoords = saved
	print("coordinates OK")
end)()
;(function()
	local minimap = ns:GetModule("Minimap")
	local savedCluster, savedHasMail = rawget(_G, "MinimapCluster"), rawget(_G, "HasNewMail")
	local frame, icon = CreateFrame("Frame"), CreateFrame("Frame")
	local fallback, hasMail = nil, true
	MinimapCluster = { IndicatorFrame = { MailFrame = frame } }
	HasNewMail = function() return hasMail end
	frame.MailIcon = icon
	frame.NewMailAnim, frame.MailReminderAnim = false, false
	icon.GetAtlas = function() return "ui-hud-minimap-mail-icon" end
	frame.CreateTexture = function()
		assert(not fallback, "one fallback texture is enough")
		fallback = CreateFrame("Frame")
		return fallback
	end
	frame:SetScript("OnHide", function() icon:Hide() end)
	frame:SetScript("OnEvent", function()
		frame:SetShown(hasMail)
		icon:SetShown(hasMail)
	end)

	assert(minimap.db.restoreMailIcon == true, "restoring the icon is enabled by default")
	minimap:OnOptionChanged("restoreMailIcon")
	assert(not fallback, "the original icon is visible")
	frame:GetScript("OnHide")(frame) -- parent was hidden; the mail frame is still marked shown
	frame:GetScript("OnShow")(frame)
	assert(fallback and fallback:IsShown() and not icon:IsShown(), "restore the envelope after showing the UI")

	minimap.db.restoreMailIcon = false
	minimap:OnOptionChanged("restoreMailIcon")
	assert(not fallback:IsShown(), "disabling the option immediately hides the fallback")
	minimap.db.restoreMailIcon = true
	minimap:OnOptionChanged("restoreMailIcon")
	assert(fallback:IsShown(), "reenabling restores the envelope again")

	frame:GetScript("OnEvent")(frame, "UPDATE_PENDING_MAIL")
	assert(icon:IsShown() and not fallback:IsShown(), "only the original icon shows after the mail update")
	hasMail = false
	frame:GetScript("OnEvent")(frame, "UPDATE_PENDING_MAIL")
	assert(not frame:IsShown() and not fallback:IsShown(), "clearing new mail hides the envelope")
	MinimapCluster, HasNewMail = savedCluster, savedHasMail
	print("minimap mail icon OK")
end)()
;(function()
	-- The text of a step: all of it up to the limit, the rest scrolls; slow text grows by whole words
	local D = ns:GetModule("Dialog")
	assert(D.ContentHeight(120.4) == 121, "short text whole")
	assert(D.ContentHeight(900) == 150, "long text up to the limit")
	local text = "Seid gegrüßt, Reisender."
	assert(D.RevealCut(text, 3) == 0, "no half word")
	assert(text:sub(1, D.RevealCut(text, 16)) == "Seid gegrüßt,", text:sub(1, D.RevealCut(text, 16)))
	assert(D.RevealCut(text, 99) == #text, "all said")
	print("speech OK")
end)()
;(function()
	-- Weapon masters: own faction on its city map, masters standing together share a symbol
	local Symbols = ns.MapSymbols
	local orgrimmar = Symbols.WeaponMasterGroups(1454, "H")
	assert(#orgrimmar == 1 and #orgrimmar[1].masters == 2, "Hanashi and Sayoc together")
	assert(#Symbols.WeaponMasterGroups(1454, "A") == 0, "not for the other faction")
	assert(#Symbols.WeaponMasterGroups(1453, "A") == 1, "Woo Ping in Stormwind")
	for _, master in ipairs(ns.WeaponMasters) do
		for _, skill in ipairs(master[6]) do
			assert(ns.WeaponSkillClasses[skill] and ns.L["WEAPON_" .. skill], "known skill " .. skill)
		end
	end
	print("weapon masters OK")
end)()
;(function()
	-- Opening: the bubble shows once the NPC's plate has stopped growing; the plates stay on while anyone needs them
	local D = ns:GetModule("Dialog")
	assert(not D.OpenReady(0.1, 0.1), "not before the shortest wait")
	assert(not D.OpenReady(0.2, 0.01), "not while the plate grows")
	assert(D.OpenReady(0.2, 0.06), "once the plate is still")
	assert(D.OpenReady(0.5, 0), "at the latest")
	assert(D.ScaleMoved(0.89, 0.90) and not D.ScaleMoved(0.95, 0.951), "small steps do not count")
	assert(D.ScaleMoved(nil, 0.5) and not D.ScaleMoved(nil, nil), "a plate that comes moves")
	local getCVar, setCVar = GetCVar, SetCVar
	local values = { nameplateShowFriendlyNpcs = "0", nameplateShowAll = "1" }
	GetCVar = function(cvar) return values[cvar] end
	SetCVar = function(cvar, value) values[cvar] = value end
	ns.ShowFriendlyPlates(true, "dialog")
	ns.ShowFriendlyPlates(true, "speech")
	assert(values.nameplateShowFriendlyNpcs == "1" and values.nameplateShowAll == "1", "plates on")
	ns.ShowFriendlyPlates(false, "speech")
	assert(values.nameplateShowFriendlyNpcs == "1", "the gossip ends, the conversation goes on: plates stay")
	ns.ShowFriendlyPlates(false, "dialog")
	assert(values.nameplateShowFriendlyNpcs == "0" and values.nameplateShowAll == "1", "each setting is restored")
	values.nameplateShowAll = "0"
	ns.ShowFriendlyPlates(true, "dialog")
	uv(ns.RegisterEvent, "listeners").PLAYER_LOGOUT["NPC bubble nameplates"]()
	assert(values.nameplateShowFriendlyNpcs == "0" and values.nameplateShowAll == "0", "restores both settings on reload")
	GetCVar, SetCVar = getCVar, setCVar
	print("opening OK")
end)()
;(function()
	-- Group quests: the kind of group, the group finder activities found by name, a listing that grows
	local G = ns:GetModule("GroupFinder")
	assert(G.QuestKind({ tagID = 81 }) == "dungeon" and G.QuestKind(nil, 0, true) == "dungeon", "dungeon by tag or data")
	assert(G.QuestKind({ tagID = 62 }) == "raid" and G.QuestKind({ tagID = 1 }) == "elite", "raid, group")
	assert(G.QuestKind(nil, 3) == "elite" and G.QuestKind({ tagID = 0, isElite = true }) == "elite", "suggested group, elite")
	assert(G.QuestKind(nil, 0, false) == nil and G.QuestKind({ tagID = 0 }, 1) == nil, "a quest for one: no button")
	local activities = {
		{ id = 799, fullName = "Die Todesminen", shortName = "Todesminen", categoryID = 2 },
		{ id = 805, fullName = "Scharlachrotes Kloster - Friedhof", shortName = "Friedhof", categoryID = 2 },
		{ id = 829, fullName = "Scharlachrotes Kloster - Bibliothek", shortName = "Bibliothek", categoryID = 2 },
		{ id = 813, fullName = "Düsterbruch (Ost)", shortName = "Düsterbruch (Ost)", categoryID = 2 },
		{ id = 814, fullName = "Düsterbruch (West)", shortName = "Düsterbruch (West)", categoryID = 2 },
		{ id = 854, fullName = "Westfall", shortName = "Westfall", categoryID = 116 },
		{ id = 855, fullName = "Dämmerwald", shortName = "Dämmerwald", categoryID = 116 },
	}
	local function ids(t) return table.concat(t, ",") end
	assert(ids(G.MatchActivities({ "Die Todesminen" }, activities, "dungeon")) == "799", "exact dungeon")
	assert(ids(G.MatchActivities({ "Scharlachrotes Kloster" }, activities, "dungeon")) == "805,829", "all wings")
	assert(ids(G.MatchActivities({ "Düsterbruch" }, activities, "dungeon")) == "813,814", "bracketed wings")
	assert(ids(G.MatchActivities({ "Westfall" }, activities, "elite")) == "854", "elite quest: its zone")
	assert(ids(G.MatchActivities({ "Die Todesminen" }, activities, "elite")) == "799", "elite quest in a dungeon")
	assert(#G.MatchActivities({ "Westfal" }, activities, "elite") == 0, "no half names")
	assert(#G.MatchActivities({ "Rotkammgebirge" }, activities, "elite") == 0, "nothing fits: no button")
	assert(ids(G.MergeActivities({ 854, 799 }, { 799, 805 })) == "854,799,805", "listing keeps its activities")
	-- The tracker asks on every update: one match per place and kind, again for a new activity list.
	local match, calls = G.MatchActivities, 0
	G.MatchActivities = function(...)
		calls = calls + 1
		return match(...)
	end
	local first = G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "dungeon")
	assert(ids(first) == "805,829" and calls == 1, "cached match: first look")
	assert(G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "dungeon") == first and calls == 1,
		"cached match: same place again, no new match")
	assert(ids(G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, activities, "elite")) == "805,829" and calls == 2,
		"cached match: another kind")
	assert(ids(G.CachedMatch({ "Die Todesminen" }, activities, "dungeon")) == "799" and calls == 3, "cached match: other place")
	local fewer = { activities[1] }
	assert(#G.CachedMatch({ "Scharlachrotes Kloster", "Tirisfal" }, fewer, "dungeon") == 0 and calls == 4,
		"cached match: new activity list")
	G.MatchActivities = match
	print("group quests OK")
end)()
;(function()
	-- Auction prices: the newest look counts, within one look the lowest; the tooltip line for what one can make
	local A = ns:GetModule("Auction")
	local store = {}
	assert(A.RecordPrice(store, 2840, 500, 1000) and store[2840][1] == 500, "first price noted")
	assert(A.RecordPrice(store, 2840, 450, 1100) and store[2840][1] == 450, "lower in the same look")
	assert(not A.RecordPrice(store, 2840, 600, 1200) and store[2840][1] == 450, "higher in the same look: kept")
	assert(A.RecordPrice(store, 2840, 800, 1000 + 86400) and store[2840][1] == 800, "a later look replaces it")
	assert(not A.RecordPrice(store, 2840, 0, 1) and not A.RecordPrice(store, nil, 5, 1), "no price, no item")
	assert(A.PriceAge(60) == ns.L.AUCTION_AGE_NOW and A.PriceAge(7200) == ns.L.AUCTION_AGE_HOURS:format(2)
		and A.PriceAge(3 * 86400 + 5) == ns.L.AUCTION_AGE_DAYS:format(3), "age in words")
	local money = GetMoneyString
	GetMoneyString = function(copper) return copper .. "c" end
	local line = A.CraftPriceText(25, { 450, 1000 }, 1000 + 2 * 86400)
	assert(line:find("25c", 1, true) and line:find("450c", 1, true) and line:find(ns.L.AUCTION_AGE_DAYS:format(2), 1, true), line)
	assert(A.CraftPriceText(nil, nil, 0) == ns.L.AUCTION_CRAFT_UNKNOWN, "nothing known")
	assert(A.ShowsPriceLine(true, false, true) and A.ShowsPriceLine(nil, true, true), "crafted, or a known auction price")
	assert(not A.ShowsPriceLine(nil, false, true), "neither: no line")
	assert(not A.ShowsPriceLine(true, true, false), "extra lines only with Shift: hidden without")
	assert(A.FilterStatusText(4, 0, false):find("4", 1, true) and A.FilterStatusText(7, 0, true):find("7", 1, true),
		"filter status while searching and after")
	assert(A.FilterStatusText(3, 2, false) == nil, "hits shown: no status line")
	GetMoneyString = money
	do
		-- Upgrade arrow in the browse list
		local savedAPI, savedState = C_AuctionHouse, ns.ItemLinkUpgradeState
		local sample = "|Hitem:5::::|h[X]|h"
		C_AuctionHouse = { GetItemKeySampleLink = function(key) return key.itemID == 5 and sample or nil end }
		assert(A.RowLink({ itemLink = "|Hitem:9|h[Y]|h" }, { itemID = 5 }) == "|Hitem:9|h[Y]|h", "an auction's own link first")
		assert(A.RowLink({}, { itemID = 5 }) == sample, "else the sample link of the item key")
		assert(A.RowLink({}, { itemID = 6 }) == nil, "no sample link: no row link")
		assert(A.RowLink({ itemLink = "|Hbattlepet:1|h[P]|h" }) == nil, "pets get no arrow")
		local asked
		ns.ItemLinkUpgradeState = function(link) asked = link return "later" end
		local tex = NewFrame("Texture")
		function tex:SetDesaturated(v) self.desat = v end
		local cell = { Icon = { IsShown = function() return true end }, rowData = {},
			CreateTexture = function() return tex end }
		local onCell, onClear = uv(A.OnLogin, "OnItemCell"), uv(A.OnLogin, "OnItemCellCleared")
		onCell(cell, { itemID = 5 })
		assert(asked == sample and tex.shown and tex.desat, "grey arrow if only the level is missing")
		ns.ItemLinkUpgradeState = function() return "worse" end
		onCell(cell, { itemID = 5 })
		assert(tex.shown and tex.rotation == math.pi and tex.vertexColor[2] < 0.2, "worse auctions show the red down arrow")
		onClear(cell)
		assert(not tex.shown, "a cleared cell hides the arrow")
		cell.Prefix = {}
		onCell(cell, { itemID = 5 })
		assert(not tex.shown, "own auctions get no arrow")
		C_AuctionHouse, ns.ItemLinkUpgradeState = savedAPI, savedState
	end
	local savedAPI, savedStore, savedAfter, savedTime, savedProfile = C_AuctionHouse, ns.db.auctionPrices, C_Timer.After, time, debugprofilestop
	local timers, reads, now, ticks = {}, 0, 1000, 0
	C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
	time = function() return now end
	debugprofilestop = function() ticks = ticks + 1 return ticks * 0.15 end
	ns.db.auctionPrices = {}
	local function result(id, price) return { itemKey = { itemID = id }, minPrice = price } end
	C_AuctionHouse = {
		GetBrowseResults = function()
			reads = reads + 1
			return { result(1, 100), result(2, 200), result(3, 300), result(4, 400), result(5, 500) }
		end,
		GetCommoditySearchResultInfo = function() return { unitPrice = 150 } end,
	}
	local browse = uv(A.OnLogin, "OnBrowseResults")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { result(1, 80), result(6, 600) })
	do
		local frame = { UpdateBrowseResults = function() end, browseResults = { result(7, 700) } }
		local savedHook, savedUnregister, queue, unregistered = hooksecurefunc, A.UnregisterEvent, nil, 0
		hooksecurefunc = function(target, name, fn)
			assert(target == frame and name == "UpdateBrowseResults")
			queue = fn
		end
		A.UnregisterEvent = function() unregistered = unregistered + 1 end
		uv(A.OnLogin, "HookBrowsePrices")(frame)
		A.UnregisterEvent, hooksecurefunc = savedUnregister, savedHook
		assert(unregistered == 2, "the Blizzard hook replaces both browse event listeners")
		queue(frame)
		queue(frame, { result(7, 650) })
	end
	now = now + 1800
	uv(A.OnLogin, "OnCommodityResults")(A, "COMMODITY_SEARCH_RESULTS_UPDATED", 1)
	assert(reads == 1 and #timers == 1 and next(ns.db.auctionPrices) == nil, "pages queue together and additions use the payload")
	table.remove(timers, 1)()
	assert(ns.db.auctionPrices[1] and not ns.db.auctionPrices[5] and #timers == 1, "the first price slice yields at its budget")
	while #timers > 0 do table.remove(timers, 1)() end
	assert(ns.db.auctionPrices[1][1] == 150 and ns.db.auctionPrices[1][2] == now and ns.db.auctionPrices[6][1] == 600,
		"queued snapshots preserve order and the time of each event")
	assert(ns.db.auctionPrices[7][1] == 650, "the Blizzard snapshot and appended page are saved without another read")
	browse(A, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { result(8, 800) })
	uv(A.OnLogin, "SaveQueuedPrices")(true)
	assert(ns.db.auctionPrices[8][1] == 800, "logout saves the queued prices before the next frame")
	table.remove(timers, 1)()
	assert(#timers == 0, "a timer left after the flush has nothing to do")
	C_AuctionHouse, ns.db.auctionPrices, C_Timer.After, time, debugprofilestop = savedAPI, savedStore, savedAfter, savedTime, savedProfile
	print("craft prices OK")
end)()
;(function()
	-- Upcoming recipes: what is not known yet, by skill, learnable now when skill and level allow it
	local P = ns:GetModule("ProfessionPlan")
	local list = {
		{ name = "Grobes Schleifmittel", skill = 75 },
		{ name = "Bronzestab", skill = 50, known = true },
		{ name = "Kupferkettenhose", skill = 1 },
		{ name = "Geselle", skill = 50, level = 10 },
		{ name = "Experte", skill = 125, level = 20 },
	}
	local rows = P.Upcoming(list, { ["Kupferkettenhose"] = true }, 60, 12)
	local names = {}
	for _, row in ipairs(rows) do names[#names + 1] = row.entry.name .. (row.now and "+" or "") end
	assert(table.concat(names, ",") == "Geselle+,Grobes Schleifmittel,Experte", table.concat(names, ","))
	assert(#P.Upcoming(nil, {}, 0, 1) == 0, "no list")
	-- Blizzard sorts the divider and the native skill headers with the learned categories.
	local roots = {}
	local function Node(data)
		return { data = data, children = {}, GetData = function(self) return self.data end,
			SetCollapsed = function(self, value) self.collapsed = value end,
			Insert = function(self, childData)
				local child = Node(childData)
				self.children[#self.children + 1] = child
				return child
			end }
	end
	local function SortRoot(lhs, rhs)
		local left, right = lhs:GetData(), rhs:GetData()
		if left.group ~= right.group then
			return left.group < right.group
		end
		return left.categoryInfo.uiOrder < right.categoryInfo.uiOrder
	end
	roots[1] = Node({ group = 2, categoryInfo = { uiOrder = 1 } })
	roots[2] = Node({ group = 1, categoryInfo = { uiOrder = 2 } })
	local provider = {
		Insert = function(_, data)
			local node = Node(data)
			roots[#roots + 1] = node
			table.sort(roots, SortRoot)
			return node
		end,
		Remove = function(_, node)
			for i, root in ipairs(roots) do
				if root == node then return table.remove(roots, i) end
			end
		end,
	}
	local savedFrame, savedTradeSkill, savedLevel = ProfessionsFrame, C_TradeSkillUI, UnitLevel
	local searching, collapses = false, {}
	ProfessionsFrame = { CraftingPage = { GetCollapses = function() return collapses end,
		RecipeList = { ScrollBox = { GetDataProvider = function() return provider end },
			SearchBox = { HasText = function() return searching end } } } }
	local recipeScans = 0
	C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Schmiedekunst", skillLevel = 60 } end,
		GetAllRecipeIDs = function() recipeScans = recipeScans + 1 return { 1 } end,
		GetRecipeInfo = function() return { name = "Kupferkettenhose", learned = true } end }
	UnitLevel = function() return 12 end
	P.cdb.trainers["Schmiedekunst"] = list
	P.db.upcoming = true
	P.Inject()
	assert(recipeScans == 1, "check learned recipes for a saved trainer list")
	assert(#roots == 6 and roots[3].data.isDivider, "divider and three skill categories after the learned categories")
	local requirements = { 50, 75, 125 }
	for i, required in ipairs(requirements) do
		local category = roots[3 + i]
		local children = category.children
		assert(category.data.categoryInfo.name == ns.L.PROFPLAN_SKILL:format(required), "native categories in skill order")
		assert(#children == 3 and children[1].data.topPadding and children[3].data.bottomPadding, "native category spacing")
		assert(children[2].data.fpPlan == "recipe" and not children[2].data.recipeInfo, "upcoming recipes stay out of crafting selection")
	end
	assert(roots[4].children[2].data.right == ns.L.PROFPLAN_NOW, "learnable recipe keeps its status")
	assert(roots[6].children[2].data.right == ns.L.PROFPLAN_LEVEL:format(20), "level requirement stays visible")
	collapses[roots[4].data.categoryInfo.categoryID] = true
	P.Inject()
	assert(#roots == 6 and roots[4].collapsed, "refresh restores collapsed categories without duplicates")
	searching = true
	P.Inject()
	assert(#roots == 2 and recipeScans == 2, "search removes all upcoming categories without scanning")
	searching = false
	P.cdb.trainers["Schmiedekunst"] = nil
	P.Inject()
	assert(#roots == 3 and roots[3].children[1].data.fpPlan == "note" and recipeScans == 2,
		"no trainer list yet: show a note without scanning")
	P.db.upcoming = false
	P.Inject()
	assert(#roots == 2, "taken out when switched off")
	-- Hover a future recipe from an old saved trainer list, which had neither an item link nor a recipe ID.
	local savedSpell, savedTooltip, savedTitle, savedLine = C_Spell, GameTooltip, GameTooltip_SetTitle, GameTooltip_AddNormalLine
	local savedPreview, frame, shown, title = P.db.preview, NewFrame("Frame"), nil, nil
	local savedTimer, savedTicker, savedUpgrade = C_Timer.NewTimer, C_Timer.NewTicker, ns.RecipeUpgradeState
	local savedTooltipInfo = C_TooltipInfo
	local tooltipTimer, arrowTicker, schematicReads = nil, nil, 0
	C_Timer.NewTimer = function(delay, fn)
		tooltipTimer = { delay = delay, Run = fn, Cancel = function(self) self.cancelled = true end }
		return tooltipTimer
	end
	C_Timer.NewTicker = function(_, fn)
		arrowTicker = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return arrowTicker
	end
	local lines = {}
	frame.GetObjectType = function() return "Frame" end
	setmetatable(frame, { __index = function(self, key)
		if key:sub(1, 2) ~= "fp" then return frameMeta.__index(self, key) end
	end })
	C_Spell = { GetSpellIDForSpellIdentifier = function(name) return name == "Bronzener Kriegshammer" and 9985 or nil end }
	C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { parentProfessionName = "Schmiedekunst" } end
	C_TradeSkillUI.GetRecipeSchematic = function(id)
		schematicReads = schematicReads + 1
		return id == 9985 and { outputItemID = 7958 } or {}
	end
	local cachedItemData = { lines = {} }
	C_TooltipInfo = { GetHyperlink = function(link)
		assert(link == "item:7958")
		return cachedItemData
	end }
	GameTooltip = NewFrame("Tooltip")
	GameTooltip.SetOwner = function(self, owner) self.owner = owner end
	GameTooltip.IsOwned = function(self, owner) return self.owner == owner end
	GameTooltip.ProcessInfo = function(self, info)
		shown = info
		info.tooltipPostCall(self)
		return true
	end
	GameTooltip_SetTitle = function(_, name) title = name end
	GameTooltip_AddNormalLine = function(_, line) lines[#lines + 1] = line end
	P.db.preview = false
	local acquired = uv(P.HookList, "OnAcquired")
	local function hover(entry)
		shown, title, lines = nil, nil, {}
		acquired(nil, frame, Node({ fpPlan = "recipe", entry = entry, profession = "Schmiedekunst" }))
		frame:GetScript("OnEnter")(frame)
	end
	local hammer = { name = "Bronzener Kriegshammer", skill = 100, cost = 250 }
	hover(hammer)
	assert(tooltipTimer.delay > 0)
	frame:GetScript("OnLeave")(frame)
	assert(tooltipTimer.cancelled and schematicReads == 0 and not shown, "passing over a row skips the tooltip and schematic")
	hover(hammer)
	tooltipTimer:Run()
	assert(not shown and tooltipTimer.delay == 0, "tooltip data is prepared before rendering")
	tooltipTimer:Run()
	assert(shown and shown.getterName == "GetHyperlink" and shown.getterArgs[1] == "item:7958" and title == nil,
		"an old entry shows the native item tooltip even with recipe preview disabled")
	assert(shown.tooltipData == cachedItemData, "the renderer reuses the data read in the previous frame")
	assert(lines[1] == ns.L.PROFPLAN_SKILL:format(100) and lines[2] == GetMoneyString(250, true), "training details follow the item stats")
	hover(hammer)
	tooltipTimer:Run()
	tooltipTimer:Run()
	assert(schematicReads == 1, "repeated item tooltips reuse the output link")
	hover({ name = "Verzauberung", skill = 120, recipeID = 2000 })
	tooltipTimer:Run()
	tooltipTimer:Run()
	assert(shown and shown.getterName == "GetSpellByID" and shown.getterArgs[1] == 2000, "a recipe with no output item shows its spell")
	hover({ name = "Unbekannt", skill = 125 })
	tooltipTimer:Run()
	assert(shown == nil and title == "Unbekannt" and lines[1] == ns.L.PROFPLAN_SKILL:format(125), "no match: show the saved training details")
	P.db.preview = true
	ns.RecipeUpgradeState = function(link) return link == "item:7958" end
	hover(hammer)
	assert(not frame.fpArrow, "the list can draw before an arrow is checked")
	arrowTicker:Run()
	assert(frame.fpArrow:IsShown() and schematicReads == 2, "the deferred arrow uses the same cached output link")
	tooltipTimer:Run()
	acquired(nil, frame, Node({ bottomPadding = true }))
	assert(tooltipTimer.cancelled and not shown and not frame.fpText:IsShown() and not frame.fpArrow:IsShown()
		and not frame.fpHighlight:IsShown() and not frame.fpData,
		"a recipe frame recycled as padding clears its visuals and tooltip data")
	if not arrowTicker.cancelled then arrowTicker:Run() end
	P.db.preview = savedPreview
	C_Timer.NewTimer, C_Timer.NewTicker, ns.RecipeUpgradeState = savedTimer, savedTicker, savedUpgrade
	C_TooltipInfo = savedTooltipInfo
	C_Spell, GameTooltip, GameTooltip_SetTitle, GameTooltip_AddNormalLine = savedSpell, savedTooltip, savedTitle, savedLine
	ProfessionsFrame, C_TradeSkillUI, UnitLevel = savedFrame, savedTradeSkill, savedLevel
	print("profession plan OK")
end)()
;(function()
	local plan, auction = ns:GetModule("ProfessionPlan"), ns:GetModule("Auction")
	local savedAuction, savedVendor = ns.db.auctionPrices, auction.cdb.vendorBuyPrices
	local savedCount, savedMerchant, savedItemID = GetMerchantNumItems, C_MerchantFrame, GetMerchantItemID
	ns.db.auctionPrices = { [101] = { 10, 1 }, [102] = { 55, 1 }, [105] = { 60, 1 } }
	auction.cdb.vendorBuyPrices = {}
	local offers = {
		{ price = 250, stackCount = 5, numAvailable = -1, isPurchasable = true },
		{ price = 1, stackCount = 1, numAvailable = 1, isPurchasable = true },
		{ price = 1, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = true },
	}
	GetMerchantNumItems = function() return #offers end
	GetMerchantItemID = function(index) return ({ 105, 104, 103 })[index] end
	C_MerchantFrame = { GetItemInfo = function(index) return offers[index] end }
	uv(auction.OnLogin, "RecordMerchantPrices")()
	assert(auction.ReagentPrice(105) == 50 and not auction.ReagentPrice(104) and not auction.ReagentPrice(103),
		"only unlimited gold offers count and merchant stacks are priced per unit")
	GetMerchantNumItems, C_MerchantFrame, GetMerchantItemID = savedCount, savedMerchant, savedItemID

	local attached, redraws = true, 0
	local function Redraw()
		if attached then redraws = redraws + 1 end
	end
	local provider
	local function Node(data)
		local node = { data = data, children = {}, GetData = function(self) return self.data end }
		function node:GetNodes() return self.children end
		function node:GetParent() return self.parent end
		function node:InsertNode(child, index)
			child.parent = self
			table.insert(self.children, index or #self.children + 1, child)
			if provider then provider:Invalidate() else Redraw() end
			return child
		end
		function node:Insert(childData) return self:InsertNode(Node(childData)) end
		function node:Remove(child, skipInvalidation)
			for index, current in ipairs(self.children) do
				if child == current then
					local removed = table.remove(self.children, index)
					if not skipInvalidation then
						if provider then provider:Invalidate() else Redraw() end
					end
					return removed
				end
			end
		end
		return node
	end
	local root = Node()
	local linearized
	local function CollectNodes(excludeCollapsed)
		local nodes = {}
		local function Add(parent)
			for _, node in ipairs(parent.children) do
				nodes[#nodes + 1] = node
				if not (excludeCollapsed and node.collapsed) then Add(node) end
			end
		end
		Add(root)
		return nodes
	end
	provider = {
		GetRootNode = function() return root end,
		GetChildrenNodes = function() return root.children end,
		Insert = function(_, data) return root:Insert(data) end,
		Remove = function(_, node) return node.parent:Remove(node) end,
		IsEmpty = function() return #root.children == 0 end,
		Invalidate = function()
			linearized = nil
			Redraw()
		end,
		GetLinearized = function()
			if not linearized then
				linearized = CollectNodes(true)
			end
			return linearized
		end,
		GetSize = function(self, excludeCollapsed)
			if excludeCollapsed then
				return #self:GetLinearized()
			end
			return #CollectNodes(false)
		end,
		Enumerate = function(self, _, _, excludeCollapsed)
			if excludeCollapsed then
				return ipairs(self:GetLinearized())
			end
			return ipairs(CollectNodes(false))
		end,
	}
	function provider:EnumerateEntireRange() return self:Enumerate(nil, nil, false) end
	function provider:FindElementDataByPredicate(predicate, excludeCollapsed)
		for _, node in self:Enumerate(nil, nil, excludeCollapsed) do
			if predicate(node) then return node end
		end
	end
	local savedFrame, savedAPI, savedProfessions = ProfessionsFrame, C_TradeSkillUI, Professions
	local savedDifficulty, savedOption = Enum.TradeskillRelativeDifficulty, plan.db.efficientSkillUps
	local savedTicker, savedProfile, savedAfter = C_Timer.NewTicker, debugprofilestop, C_Timer.After
	local scan, clock, selectRecommended
	C_Timer.After = function(_, fn) selectRecommended = fn end
	C_Timer.NewTicker = function(_, fn)
		scan = { Run = fn, Cancel = function(self) self.cancelled = true end }
		return scan
	end
	clock = 0
	debugprofilestop = function() clock = clock + 0.3 return clock end
	local function FinishScan()
		for _ = 1, 20 do
			if scan.cancelled then return end
			scan:Run()
		end
		error("recipe scan did not finish")
	end
	local noResults, skill, skillUpOnly = NewFrame("FontString"), 25, true
	local selected
	local view = {
		DetachDataProviderCallbacks = function() assert(attached) attached = false end,
		AttachDataProviderCallbacks = function() assert(not attached) attached = true end,
		DataProviderContentsChanged = Redraw,
	}
	ProfessionsFrame = { CraftingPage = { RecipeList = { NoResultsText = noResults,
		ScrollBox = { GetDataProvider = function() return provider end, GetView = function() return view end },
		selectionBehavior = {
			GetFirstSelectedElementData = function() return selected end,
			DeselectElementData = function(_, node) assert(selected == node) selected = nil end,
		},
		SelectRecipe = function(_, info)
			for _, node in provider:EnumerateEntireRange() do
				if node.data.recipeInfo == info then selected = node return node end
			end
		end,
	} } }
	local rankedReads = 0
	Professions = { InLocalCraftingMode = function() return true end, GetHighestLearnedRecipe = function(recipe)
		assert(recipe.recipeID == 3)
		rankedReads = rankedReads + 1
		return { recipeID = 7, canSkillUp = true, numSkillUps = 1, relativeDifficulty = 2 }
	end }
	Enum.TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 }
	local category = root:Insert({ group = 1, categoryInfo = { uiOrder = 1 } })
	for id = 1, 6 do
		category:Insert({ recipeInfo = { recipeID = id, learned = true, canSkillUp = id ~= 3, numSkillUps = 1,
			relativeDifficulty = 0, nextRecipeID = id == 3 and 7 or nil, disabled = id == 6 } })
	end
	local reads = 0
	C_TradeSkillUI = {
		GetOnlyShowSkillUpRecipes = function() return skillUpOnly end,
		GetBaseProfessionInfo = function() return { skillLevel = skill, maxSkillLevel = 75 } end,
		GetRecipeSchematic = function(id)
			reads = reads + 1
			assert(id ~= 3, "use the highest learned rank's schematic")
			id = id == 7 and 3 or id
			local quantity = ({ 8, 2, 1, 1, 1 })[id]
			return { reagentSlotSchematics = {
				{ required = true, quantityRequired = quantity, reagents = { { itemID = id == 3 and 102 or id + 100 } } },
				{ required = false, quantityRequired = 10, reagents = {} },
			} }
		end,
	}
	local function Recommendations()
		return root.children[1].children
	end
	plan.db.efficientSkillUps = true
	selected, redraws = category.children[6], 0
	plan.Inject()
	assert(reads == 0 and root.children[1] == category, "the list hook leaves expensive recipe reads for later frames")
	scan:Run()
	assert(reads == 1 and root.children[1] == category and redraws == 0, "a scan slice yields before changing the visible list")
	FinishScan()
	local rows = Recommendations()
	assert(attached and redraws == 1 and not selected and selectRecommended, "the list redraws once before loading a new recipe")
	selectRecommended()
	assert(selected == rows[1], "the first available recipe is selected after the redraw")
	assert(#rows == 3 and rows[1].data.recipeInfo.recipeID == 5 and rows[2].data.recipeInfo.recipeID == 2
		and rows[3].data.recipeInfo.recipeID == 1, "top three balance reagent cost, reagent count and skill chance")
	assert(rows[1].data.fpSkillUp.cost == 50 and rows[2].data.fpSkillUp.units == 2 and reads == 5,
		"optional reagents and disabled recipes do not affect the ranking")
	assert(rankedReads == 1, "rank lookup is reserved for recipes with ranks")

	ns.db.auctionPrices = {}
	plan.Inject()
	FinishScan()
	rows = Recommendations()
	assert(rows[2].data.recipeInfo.recipeID == 4 and rows[2].data.fpSkillUp.cost == nil,
		"missing prices fall back to materials per skill point")

	selected, skillUpOnly = rows[1], false
	plan.Inject()
	assert(root.children[1] == category and #category.children == 6, "turning off the native filter restores the original tree")
	assert(selected == category.children[5], "the selected recipe is restored to its original row")
	skillUpOnly = true
	plan.Inject()
	scan:Run()
	local obsoleteScan = scan
	skillUpOnly = false
	plan.Inject()
	assert(obsoleteScan.cancelled and root.children[1] == category, "changing the filter cancels a pending scan")

	selected, skillUpOnly, skill = nil, true, 75
	root:Remove(category)
	noResults:Show()
	reads = 0
	plan.Inject()
	assert(reads == 0 and Recommendations()[1].data.text == ns.L.PROFPLAN_SKILL_CAP and not noResults:IsShown(),
		"at the cap the empty list shows a single message without reading recipes")
	plan.db.efficientSkillUps = false
	plan.Inject()
	assert(provider:IsEmpty() and noResults:IsShown(), "turning off the addon filter restores Blizzard's empty state")
	print("profession skill-up filter OK")

	local savedItemUtil = rawget(_G, "ItemUtil")
	local makeable, inventory = false, { [101] = 1, [102] = 4, [103] = 1, [104] = 2 }
	local inventoryReads = {}
	ItemUtil = { GetCraftingReagentCount = function(id)
		inventoryReads[id] = (inventoryReads[id] or 0) + 1
		return inventory[id] or 0
	end }
	C_TradeSkillUI.GetOnlyShowMakeableRecipes = function() return makeable end
	C_TradeSkillUI.GetRecipeSchematic = function(id)
		assert(id ~= 3, "material filter uses the highest learned rank")
		local reagents = { [1] = { { itemID = 101 } }, [2] = { { itemID = 102 } },
			[7] = { { itemID = 107 }, { itemID = 103 } }, [4] = { { itemID = 104 } },
			[5] = { { itemID = 107 } } }
		return { reagentSlotSchematics = reagents[id] and {
			{ required = id ~= 4, quantityRequired = 4, reagents = reagents[id] },
		} or {} }
	end
	root:InsertNode(category)
	local favorites = root:Insert({ categoryInfo = { uiOrder = 0 } })
	local favoriteInfo = { recipeID = 1, learned = true, favoritesInstance = true }
	local favorite = favorites:Insert({ recipeInfo = favoriteInfo })
	local empty = root:Insert({ categoryInfo = { uiOrder = 2 } })
	empty:Insert({ recipeInfo = { recipeID = 4, learned = true } })
	local unlearned = root:Insert({ categoryInfo = { uiOrder = 3 } })
	unlearned:Insert({ recipeInfo = { recipeID = 1, learned = false } })
	category.collapsed = true
	local padding = category:Insert({ bottomPadding = true })
	local before = { unpack(category.children) }
	local events = uv(ns.RegisterEvent, "listeners")
	assert(not plan.db.withMaterials, "material filtering is off by default")
	-- Populate LinearizedTreeDataProviderMixin's cache just like ScrollBox:SetDataProvider does.
	assert(provider:GetSize(true) == 7, "unfiltered linearized cache contains all visible rows")
	selected, redraws = favorite, 0
	ns.SetOption("ProfessionPlan", "withMaterials", true)
	FinishScan()
	assert(redraws == 1 and provider:GetSize(true) == 3,
		"material filter invalidates the linearized tree cache and redraws once")
	assert(#root.children == 2 and root.children[1] == category and root.children[2] == favorites
		and selected == favorite and category.collapsed, "material filter keeps matching categories, favorites and selection")
	assert(#category.children == 4 and category.children[1] == before[1] and category.children[2] == before[2]
		and category.children[3] == before[3] and category.children[4] == padding,
		"partial stacks, full stacks and alternative reagents match; optional or absent reagents do not")
	assert(inventoryReads[101] == 1 and inventoryReads[107] == 1 and not inventoryReads[104],
		"each reagent count is read once and optional reagents are skipped")

	category.collapsed = false
	provider:Invalidate()
	assert(provider:GetSize(true) == 7, "expanding category refreshes linearized cache before bag update")
	inventory = { [107] = 1 }
	events.BAG_UPDATE_DELAYED[plan]()
	assert(selected == favorite and root.children[2] == favorites, "the old result stays visible during a bag refresh")
	FinishScan()
	selectRecommended()
	assert(provider:GetSize(true) == 4 and #root.children == 1 and #category.children == 3
		and category.children[1] == before[3] and category.children[2] == before[5] and selected == before[3],
		"bag changes remove depleted recipes, refresh linearized cache and select the first visible match")
	inventory = {}
	events.PLAYERBANKSLOTS_CHANGED[plan]()
	FinishScan()
	assert(provider:IsEmpty() and provider:GetSize(true) == 0 and noResults:IsShown(),
		"an empty result clears linearized cache and uses the native empty state")

	makeable = true
	plan.Inject()
	assert(provider:GetSize(true) == 7 + #before and #root.children == 4 and #category.children == #before
		and not noResults:IsShown(),
		"the native makeable filter takes precedence and restores the native list")
	for index, node in ipairs(before) do assert(category.children[index] == node, "restored recipe order") end

	makeable, skill, inventory = false, 25, { [101] = 1, [102] = 4 }
	plan.db.efficientSkillUps = true
	plan.Inject()
	FinishScan()
	rows = Recommendations()
	assert(#rows == 2 and rows[1].data.fpSkillUp and rows[2].data.fpSkillUp,
		"the top skill-up recommendations respect available materials")
	plan.db.efficientSkillUps = false
	ns.SetOption("ProfessionPlan", "withMaterials", false)
	assert(#root.children == 4 and #category.children == #before and not (events.BAG_UPDATE_DELAYED or {})[plan],
		"switching off restores all native rows and stops bag monitoring")
	ItemUtil = savedItemUtil
	plan.db.efficientSkillUps = savedOption
	C_Timer.NewTicker, debugprofilestop, C_Timer.After = savedTicker, savedProfile, savedAfter
	Enum.TradeskillRelativeDifficulty, ProfessionsFrame, C_TradeSkillUI, Professions = savedDifficulty, savedFrame, savedAPI, savedProfessions
	ns.db.auctionPrices, auction.cdb.vendorBuyPrices = savedAuction, savedVendor
	print("profession material filter OK")
end)()
;(function()
	-- Core helpers
	local savedSecret = issecretvalue
	issecretvalue = function(value) return value == "geheim" end
	assert(ns.Secret("geheim") == true and ns.Secret("offen") == false and ns.Secret(nil) == false, "Secret")
	local kind, id = ns.GuidParts("Creature-0-1-2-3-1689-0000")
	assert(kind == "Creature" and id == 1689, "GuidParts")
	assert(ns.GuidParts("geheim") == nil and ns.GuidParts(nil) == nil and ns.GuidParts(5) == nil, "GuidParts: nothing usable")
	issecretvalue = savedSecret
	assert(ns.LowerCommand("BÜCHER Ärger ÖL") == "bücher ärger öl", "commands with capital umlauts")
	-- A listener registering another one for the same event while it runs: no error, the new one hears the next event
	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	local a, b, heard = {}, {}, 0
	for i = 1, 20 do
		ns:RegisterEvent("FP_TEST_EVENT", { name = "filler" .. i }, function() end)
	end
	ns:RegisterEvent("FP_TEST_EVENT", a, function()
		ns:RegisterEvent("FP_TEST_EVENT", b, function() heard = heard + 1 end)
	end)
	onEvent(nil, "FP_TEST_EVENT")
	local first = heard
	onEvent(nil, "FP_TEST_EVENT")
	assert(first <= 1 and heard == first + 1, "listener added during an event")
	-- An error names the listener and the event: the game's stack ends at the dispatcher's xpcall
	local savedHandler, reported = geterrorhandler, {}
	geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
	ns:RegisterEvent("FP_TEST_ERROR", { name = "Faulty" }, function() error("boom", 0) end)
	ns:RegisterEvent("FP_TEST_ERROR", { name = "Healthy" }, function() heard = heard + 1 end)
	heard = 0
	onEvent(nil, "FP_TEST_ERROR")
	geterrorhandler = savedHandler
	assert(#reported == 1 and reported[1] == "boom (ForeverPlus listener Faulty: FP_TEST_ERROR)" and heard == 1,
		"listener errors name the listener, the others still run: " .. tostring(reported[1]))
	-- Timers run through the measurement
	local savedAfter, savedTimer, savedTicker = C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker
	C_Timer.After = function(_, fn) fn() end
	C_Timer.NewTimer = function(_, fn) fn() return {} end
	C_Timer.NewTicker = function(_, fn, n) fn("ticker") return { n = n } end
	local savedTime = GetTime
	local now = savedTime()
	GetTime = function() return now end
	ns.SetMeasuring(true)
	now = now + 1
	local ran, got = 0, nil
	ns.After("Test: after", 1, function() ran = ran + 1 end)
	ns.NewTimer("Test: timer", 1, function() ran = ran + 1 end)
	local ticker = ns.NewTicker("Test: ticker", 1, function(t) got = t end, 3)
	assert(ran == 2 and got == "ticker" and ticker.n == 3, "timers call through")
	assert(ns.timings["Test: after"].count == 1 and ns.timings["Test: timer"].count == 1 and ns.timings["Test: ticker"].count == 1,
		"timers are measured")
	local spikeFrame = uv(ns.SetMeasuring, "spikeFrame")
	assert(spikeFrame.shown == true or spikeFrame:IsShown() == true, "spike counter runs while measuring")
	ns.SetMeasuring(false)
	GetTime = savedTime
	assert(not ns.measuring and spikeFrame:IsShown(), "session sampling continues after detailed measurement stops")
	C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker = savedAfter, savedTimer, savedTicker
	-- No timer bypasses the measurement
	for line in io.lines(root .. "/ForeverPlus.toc") do
		if not line:match("^##") and line:match("%.lua$") and not line:match("Core.Core%.lua$") then
			local path = line:gsub("\\", "/")
			local text = io.open(root .. "/" .. path):read("*a")
			for call in text:gmatch("C_Timer%.%a+%([^\n]*") do
				assert(call:find("ns.Measured", 1, true) or call:find("CheckRange", 1, true), path .. ": timer outside the measurement: " .. call)
			end
		end
	end
	-- The setup never overwrites existing local rules
	for line in io.lines(root .. "/tools/setup-local.sh") do
		if line:find("cp tools/local/rules.md", 1, true) then
			assert(line:find("[ -e CLAUDE.md ] ||", 1, true), "setup-local.sh: overwrites the local rules: " .. line)
		end
	end
	print("core helpers OK")
end)()
;(function()
	-- Talent tree after the class: the class line gets it once; others are asked for by inspection and kept
	local T = ns:GetModule("Tooltip")
	assert(T.db.talentTree == true and T.db.hoverTalentIcon == false, "defaults: tree on, symbol off")
	assert(T.WithTree("Stufe 20 Krieger (Spieler)", "Krieger", "Waffen") == "Stufe 20 Krieger (Waffen) (Spieler)", "after the class")
	assert(T.WithTree("Stufe 20 Krieger (Waffen)", "Krieger", "Waffen") == nil, "not twice")
	assert(T.WithTree("Gilde", "Krieger", "Waffen") == nil, "no class in the line")
	local saved = { UnitIsUnit, UnitGUID, CanInspect, NotifyInspect, InCombatLockdown, GetTime, ns.TalentTreeOf, InspectFrame }
	local asked = 0
	UnitIsUnit = function() return false end
	UnitGUID = function(unit) return unit == "mouseover" and "Player-1-0002" or "Player-1-0001" end
	CanInspect = function() return true end
	NotifyInspect = function() asked = asked + 1 end
	InCombatLockdown = function() return false end
	InspectFrame = { IsShown = function() return false end }
	ClearInspectPlayer = function() end
	local now = 100
	GetTime = function() return now end
	assert(T.TreeOf("target") == nil and asked == 1, "unknown player: inspected")
	assert(T.TreeOf("target") == nil and asked == 1, "not again within 1.5 s")
	ns.TalentTreeOf = function(configID) return configID == -1 and "Furor" or nil, 132347 end
	T.OnInspectReady(nil, "INSPECT_READY", "Player-1-0001")
	local tree = T.TreeOf("target")
	assert(tree and tree.name == "Furor" and tree.icon == 132347 and asked == 1, "kept after the inspection")
	now = 200
	InCombatLockdown = function() return true end
	T.TreeOf("focus")
	assert(asked == 1, "no inspection in combat")
	UnitIsUnit, UnitGUID, CanInspect, NotifyInspect, InCombatLockdown, GetTime, ns.TalentTreeOf, InspectFrame = unpack(saved, 1, 8)
	T.trees = {}
	print("talent tree tooltip OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local oldHook, oldTooltip = hooksecurefunc, GameTooltip
	local oldManager, oldInfo = StatusTrackingBarManager, StatusTrackingBarInfo
	local oldOption = visuals.db.unitBars
	local unitAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
	local xpAtlas, restedAtlas = "UI-HUD-ExperienceBar-Fill-Experience", "UI-HUD-ExperienceBar-Fill-Rested"
	local repAtlas = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green"
	local tooltipFile = [[Interface\TargetingFrame\UI-TargetingFrame-BarFill]]

	local function MakeBar(atlas, file)
		local bar = { atlas = atlas, file = file, color = { 1, 1, 1, 0.85 }, desaturation = 0.25 }
		function bar:GetStatusBarTexture()
			return { GetAtlas = function() return self.atlas end, GetTexture = function() return self.file end }
		end
		function bar:SetStatusBarTexture(asset)
			self.atlas, self.file = nil, nil
			if asset == tooltipFile then self.file = asset else self.atlas = asset end
			return true
		end
		function bar:GetStatusBarColor() return unpack(self.color) end
		function bar:SetStatusBarColor(...) self.color = { ... } end
		function bar:GetStatusBarDesaturation() return self.desaturation end
		function bar:SetStatusBarDesaturation(value) self.desaturation = value end
		return bar
	end

	local xp, rep, tooltip = MakeBar(xpAtlas), MakeBar(nil), MakeBar(nil, tooltipFile)
	hooksecurefunc = function(frame, key, callback)
		local original = assert(frame[key])
		frame[key] = function(self, asset)
			local result = original(self, asset)
			callback(self, asset)
			return result
		end
	end
	GameTooltip = { StatusBar = tooltip }
	StatusTrackingBarManager = { barContainers = { { bars = { { StatusBar = xp }, { StatusBar = rep } } } } }
	StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
	ns.SetOption("Visuals", "unitBars", false)
	uv(visuals.OnLogin, "HookTrackingBars")()
	assert(xp.atlas == xpAtlas and tooltip.file == tooltipFile, "loading with the option off leaves default textures")
	ns.SetOption("Visuals", "unitBars", true)
	assert(xp.atlas == unitAtlas and xp.color[1] == 0.58 and xp.color[4] == 0.85
		and xp.desaturation == 1 and tooltip.atlas == unitAtlas and tooltip.desaturation == 1, "enabling styles visible bars immediately")
	xp:SetStatusBarTexture(restedAtlas)
	rep:SetStatusBarTexture(repAtlas)
	assert(xp.atlas == unitAtlas and xp.color[3] == 0.88 and rep.atlas == unitAtlas and rep.color[2] == 0.6,
		"native rested and reputation texture updates keep the style and change the tint")
	ns.SetOption("Visuals", "unitBars", false)
	assert(xp.atlas == restedAtlas and rep.atlas == repAtlas and tooltip.file == tooltipFile
		and xp.color[1] == 1 and xp.desaturation == 0.25 and tooltip.desaturation == 0.25, "disabling restores current native appearances")
	xp:SetStatusBarTexture(xpAtlas)
	assert(xp.atlas == xpAtlas, "the hook allows native textures while off")
	ns.SetOption("Visuals", "unitBars", true)
	assert(xp.atlas == unitAtlas and xp.color[1] == 0.58, "re-enabling uses the current native XP state")
	ns.SetOption("Visuals", "unitBars", false)
	local tracked = uv(uv(visuals.OnLogin, "HookTrackingBars"), "trackingBars")
	tracked[xp], tracked[rep] = nil, nil
	hooksecurefunc, GameTooltip, StatusTrackingBarManager, StatusTrackingBarInfo = oldHook, oldTooltip, oldManager, oldInfo
	visuals.db.unitBars = oldOption
	print("unit bar textures OK")
end)()
;(function()
	local visuals = ns:GetModule("Visuals")
	local pm = ns.PortraitModes
	local wanderlust = ns:GetModule("Wanderlust")
	local helpers = ns:GetModule("Helpers")
	local roleplay = ns:GetModule("Roleplay")
	local dialog = ns:GetModule("Dialog")
	local speech = ns:GetModule("SpeechBubbles")
	local emotes = ns:GetModule("ChatEmotes")
	local camera = ns:GetModule("Camera")
	local solo = ns:GetModule("SoloParty")
	local landing = ns:GetModule("Landing")
	local combatText = ns:GetModule("CombatText")
	local wind = ns:GetModule("GuidingWind")
	local oldCreate, oldPlayer, oldHook = CreateFrame, PlayerFrame, hooksecurefunc
	local oldShift, oldMod, oldEdit, oldRegistry = IsShiftKeyDown, IsModifierKeyDown, EditModeManagerFrame, EventRegistry
	local oldCursor, oldTicker = GetCursorPosition, C_Timer.NewTicker
	C_Timer.NewTicker = function() return { Cancel = function() end } end
	local shift, modDown, edit = false, false, false
	local callbacks, textures = {}, {}
	local unitChanged, wheel, menuFrame, pickerFrame, ghostFrame
	local frame, container, original, mask = NewFrame("Button"), NewFrame("Frame"), NewFrame("Texture"), NewFrame("Mask")
	frame.unit, frame.PlayerFrameContainer = "player", container
	container.PlayerPortrait, container.PlayerPortraitMask = original, mask
	container.CreateTexture = function()
		local texture = NewFrame("Texture")
		texture.SetAllPoints = function(self, region) self.bounds = region end
		texture.AddMaskTexture = function(self, region) self.mask = region end
		texture.SetTexture = function(self, file) self.asset = file return true end
		texture.SetDesaturated = function(self, flag) self.desaturated = flag and true or false end
		textures[#textures + 1] = texture
		return texture
	end
	PlayerFrame = frame
	hooksecurefunc = function(name, fn)
		if name == "UnitFrame_SetUnit" then unitChanged = fn end
	end
	EventRegistry = { RegisterCallback = function(_, event, fn, owner) callbacks[event] = function() fn(owner) end end }
	IsShiftKeyDown = function() return shift end
	IsModifierKeyDown = function() return modDown end
	EditModeManagerFrame = { IsEditModeActive = function() return edit end }
	GetCursorPosition = function() return 200, 300 end
	CreateFrame = function(kind, name, parent, template)
		local region = oldCreate(kind, name, parent, template)
		region.EnableMouseWheel = function(self, enabled) self.wheelEnabled = enabled end
		region.SetAllPoints = function(self, bounds) self.bounds = bounds end
		region.SetMouseClickEnabled = function(self, enabled) self.clickEnabled = enabled end
		region.SetMouseMotionEnabled = function(self, enabled) self.motionEnabled = enabled end
		region.GetParent = function() return parent end
		if name == "ForeverPlusPlayerPortraitWheel" then
			assert(parent == container, "the portrait wheel belongs to the player portrait container")
			wheel = region
		elseif name == "ForeverPlusPortraitModeMenu" then
			menuFrame = region
		elseif name == "ForeverPlusPortraitModeIconPicker" then
			pickerFrame = region
		elseif template == "TooltipBackdropTemplate" and not name then
			ghostFrame = region
		end
		return region
	end

	-- Save module states so the test restores everything cleanly.
	local saved = {
		mode = visuals.cdb.playerPortraitMode,
		wl = wanderlust.db.enabled, wlBags = wanderlust.db.showBags,
		fish = helpers.db.fishing,
		rp = roleplay.db.enabled, dlg = dialog.db.enabled, sb = speech.db.enabled,
		em = emotes.db.enabled, cam = camera.db.enabled,
		spOn = solo.db.enabled, spCrit = solo.db.criticals, spBloody = solo.db.bloody,
		land = landing.db.enabled, ct = combatText.db.enabled,
		windOn = wind.db.enabled, windInt = wind.db.interval, windStr = wind.db.strength,
	}
	ns.SetOption("Wanderlust", "enabled", false)
	ns.SetOption("Helpers", "fishing", false)
	ns.SetOption("SoloParty", "enabled", false)
	ns.SetOption("SoloParty", "bloody", false)
	ns.SetOption("Landing", "enabled", true)
	ns.SetOption("CombatText", "enabled", false)
	ns.SetOption("GuidingWind", "enabled", false)

	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	assert(visuals.db.playerPortraitWheel and saved.mode == 1, "new characters start with their standard portrait")
	pm.Setup()
	local background, icon, shade, shine = unpack(textures)
	assert(wheel.bounds == original and wheel.clickEnabled == false and wheel.motionEnabled == false)
	assert(background.bounds == original and background.mask == mask and icon.mask == mask and shade.mask == mask and shine.mask == mask)
	assert(original:IsShown() and not background:IsShown() and not icon:IsShown() and not shade:IsShown())

	local scroll = wheel:GetScript("OnMouseWheel")
	local click = wheel:GetScript("OnClick")
	assert(not wheel.wheelEnabled)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 1 and not icon:IsShown(), "plain scrolling does not switch modes")

	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	assert(wheel.wheelEnabled)
	-- Slot 2: Wanderlust
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 2 and icon:IsShown() and background:IsShown())
	assert(icon.asset == 237386 and icon.rotation and icon.rotation < 0)
	assert(icon.desaturated == true and wheel.clickEnabled == true and wheel.motionEnabled == true)
	-- Left-click enables Wanderlust and lights up the emblem.
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	click(wheel, "LeftButton")
	assert(wanderlust.db.enabled == true and pm.IsModeActive("wanderlust") and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(wanderlust.db.enabled == false and not pm.IsModeActive("wanderlust") and icon.desaturated == true)

	-- External option change updates the portrait live.
	ns.SetOption("Wanderlust", "enabled", true)
	assert(icon.desaturated == false, "external option change refreshes portrait icon")
	ns.SetOption("Wanderlust", "enabled", false)
	assert(icon.desaturated == true)

	-- Slot 3: Angler
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 3 and icon.asset == 643874 and icon.rotation == 0)
	shift = false
	click(wheel, "LeftButton")
	assert(helpers.db.fishing == true and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(helpers.db.fishing == false and icon.desaturated == true)

	-- Slot 4: RP mode
	shift = true
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 4 and icon.asset == 133740)
	shift = false
	click(wheel, "LeftButton")
	assert(roleplay.db.enabled and dialog.db.enabled and speech.db.enabled and emotes.db.enabled and camera.db.enabled)
	assert(pm.IsModeActive("rp") and icon.desaturated == false)
	click(wheel, "LeftButton")
	assert(not roleplay.db.enabled and not dialog.db.enabled and not speech.db.enabled and not emotes.db.enabled and not camera.db.enabled)
	assert(not pm.IsModeActive("rp") and icon.desaturated == true)

	-- Slot 5: Berserker mode (Bloody crits + Landing jump sounds + CombatText)
	shift = true
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 5 and icon.asset == 132400)
	assert(not pm.IsModeActive("berserker"), "partial default state shows Berserker as inactive")
	shift = false
	click(wheel, "LeftButton")
	assert(solo.db.enabled and solo.db.criticals and solo.db.bloody and landing.db.enabled and combatText.db.enabled)
	assert(pm.IsModeActive("berserker") and icon.desaturated == false)
	-- Unchecking one feature while mode is active turns that feature off immediately while keeping the mode active.
	pm.SetFeatureSelected("combatText", false)
	assert(not combatText.db.enabled and solo.db.bloody and landing.db.enabled and pm.IsModeActive("berserker"))
	-- Turning the mode off turns off remaining checked features while preserving the saved checkmarks.
	click(wheel, "LeftButton")
	assert(not solo.db.bloody and not solo.db.enabled and not landing.db.enabled and not pm.IsModeActive("berserker"))
	assert(pm.IsFeatureSelected("bloody") and pm.IsFeatureSelected("landing") and not pm.IsFeatureSelected("combatText"))
	-- Re-checking while mode is off only saves the choice without enabling it yet.
	pm.SetFeatureSelected("combatText", true)
	assert(pm.IsFeatureSelected("combatText") and not combatText.db.enabled)

	-- Right-click opens the WoW-style PortraitFrameTemplate mode menu on the current mode tab.
	click(wheel, "RightButton")
	assert(menuFrame and menuFrame:IsShown(), "right-click opens the portrait mode menu")
	-- Tooltip uses WoW atlas markup instead of unsupported Unicode glyphs and lists sub-options indented.
	-- Feature lines stay unwrapped and never green; the green hints follow after a blank line.
	local tooltipLines, tipCalls = {}, {}
	local oldAddColored, oldBlank, oldInstr = GameTooltip_AddColoredLine, GameTooltip_AddBlankLineToTooltip,
		GameTooltip_AddInstructionLine
	local oldGreen, oldGray, oldWhite = GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR
	local function FakeColor() return { WrapTextInColorCode = function(_, text) return text end } end
	local green = FakeColor()
	GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = green, FakeColor(), FakeColor()
	GameTooltip_AddColoredLine = function(_, text, color, wrap, leftOffset)
		tooltipLines[#tooltipLines + 1] = { text = text, color = color, wrap = wrap, offset = leftOffset }
		tipCalls[#tipCalls + 1] = "line"
	end
	GameTooltip_AddBlankLineToTooltip = function() tipCalls[#tipCalls + 1] = "blank" end
	GameTooltip_AddInstructionLine = function(_, _, wrap) tipCalls[#tipCalls + 1] = wrap == false and "hint" or "wrapped hint" end
	wheel:GetScript("OnEnter")(wheel)
	GameTooltip_AddColoredLine, GameTooltip_AddBlankLineToTooltip, GameTooltip_AddInstructionLine = oldAddColored, oldBlank,
		oldInstr
	GREEN_FONT_COLOR, GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = oldGreen, oldGray, oldWhite
	local sawSubSound, sawSubEffect = false, false
	for _, line in ipairs(tooltipLines) do
		assert(not line.text:find("\226\156\147") and not line.text:find("\226\151\139"), "tooltip avoids missing glyph symbols")
		assert(line.color ~= green and line.wrap == false, "portrait tooltip feature lines are unwrapped and not green")
		local indented = (line.offset or 0) > 0
		if indented and line.text:find(ns.L.SOLO_PARTY_SOUNDS, 1, true) then sawSubSound = true end
		if indented and line.text:find(ns.L.SOLO_PARTY_EFFECTS, 1, true) then sawSubEffect = true end
	end
	assert(#tooltipLines == 5 and sawSubSound and sawSubEffect, "portrait tooltip includes indented sub-options")
	assert(table.concat(tipCalls, ",", #tipCalls - 3) == "blank,hint,hint,hint", "portrait tooltip separates unwrapped hints")
	local landingRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "feature" and row.entry.feature.key == "landing" then
			landingRow = row
			break
		end
	end
	assert(landingRow, "Berserker menu lists the landing sound feature")
	-- Drag 'landing' from Berserker onto the Wanderlust tab (tabs[1]).
	local wanderlustTab = menuFrame.tabs[1]
	wanderlustTab.IsMouseOver = function() return true end
	landingRow:GetScript("OnDragStart")(landingRow)
	assert(ghostFrame and ghostFrame:IsShown(), "dragging shows the floating ghost label")
	landingRow:GetScript("OnDragStop")(landingRow)
	assert(not ghostFrame:IsShown())
	assert(pm.FeatureMode("landing") == "wanderlust", "dropping on a mode tab reassigns the feature")
	-- Drag a sub-option ('SoloParty:sounds') from Berserker onto Wanderlust.
	local soundRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "sub" and row.entry.sub.id == "SoloParty:sounds" then
			soundRow = row
			break
		end
	end
	assert(soundRow, "Berserker menu displays the SoloParty sounds sub-option")
	local oldSounds = solo.db.sounds
	ns.SetOption("SoloParty", "sounds", false)
	wanderlustTab.IsMouseOver = function() return true end
	soundRow:GetScript("OnDragStart")(soundRow)
	assert(ghostFrame and ghostFrame:IsShown(), "dragging a sub-option shows the floating ghost")
	soundRow:GetScript("OnDragStop")(soundRow)
	assert(not ghostFrame:IsShown())
	assert(pm.FeatureMode("SoloParty:sounds") == "wanderlust", "dropping a sub-option on a tab moves it there")
	-- Turning Wanderlust on now toggles Wanderlust, Landing and the moved SoloParty:sounds together.
	pm.ToggleMode("wanderlust")
	assert(wanderlust.db.enabled and landing.db.enabled and solo.db.sounds and pm.IsModeActive("wanderlust"))
	pm.ToggleMode("wanderlust")
	assert(not wanderlust.db.enabled and not landing.db.enabled and not solo.db.sounds)
	-- Moving the sub-option back onto its parent's mode re-attaches it as a sub-option.
	assert(pm.MoveFeature("SoloParty:sounds", "berserker"))
	assert(pm.FeatureMode("SoloParty:sounds") == "berserker")
	ns.SetOption("SoloParty", "sounds", oldSounds)
	-- Open icon picker, pick a custom Blizzard icon, and verify live update + reset.
	menuFrame.IconButton:GetScript("OnClick")(menuFrame.IconButton)
	assert(pickerFrame and pickerFrame:IsShown(), "Icon button opens the WoW icon picker")
	assert(pickerFrame.cells[2] and pickerFrame.cells[2].iconID == 132397, "picker starts with Berserker icon presets")
	pickerFrame.cells[2]:GetScript("OnClick")(pickerFrame.cells[2])
	assert(pm.ModeIcon("berserker") == 132397 and icon.asset == 132397, "picking an icon updates the portrait live")
	-- Reset restores default assignments, checkmarks and icons.
	pm.ResetAssignments()
	assert(pm.FeatureMode("landing") == "berserker" and pm.IsFeatureSelected("combatText"))
	assert(pm.ModeIcon("berserker") == 132400 and icon.asset == 132400)
	menuFrame:Hide()

	-- Slot 6: Guiding Wind mode with its own WoW icon and menu controls.
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 6 and icon.asset == 236154, "slot 6 is Guiding Wind with gale icon")
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	click(wheel, "LeftButton")
	assert(wind.db.enabled == true and pm.IsModeActive("guidingWind") and icon.desaturated == false)
	-- Right-click opens Guiding Wind tab with interval and strength controls.
	click(wheel, "RightButton")
	assert(menuFrame and menuFrame:IsShown() and #menuFrame.tabs == 5, "portrait menu has 5 mode tabs")
	local intervalRow, strengthRow
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "control" then
			if row.entry.control.key == "interval" then intervalRow = row end
			if row.entry.control.key == "strength" then strengthRow = row end
		end
	end
	assert(intervalRow and strengthRow, "Guiding Wind tab exposes interval and strength controls")
	local startInt = wind.db.interval
	intervalRow.Plus:GetScript("OnClick")(intervalRow.Plus)
	assert(wind.db.interval == startInt + 1, "interval + button increases gust interval")
	intervalRow.Minus:GetScript("OnClick")(intervalRow.Minus)
	assert(wind.db.interval == startInt, "interval - button decreases gust interval")
	-- Moving all three sub-options away still leaves the interval & strength controls expandable and visible.
	assert(pm.MoveFeature("GuidingWind:autoGusts", "wanderlust")
		and pm.MoveFeature("GuidingWind:biomeParticles", "wanderlust")
		and pm.MoveFeature("GuidingWind:sound", "wanderlust"))
	local stillHasInterval = false
	for _, row in ipairs(menuFrame.rows) do
		if row:IsShown() and row.entry and row.entry.kind == "control" and row.entry.control.key == "interval" then
			stillHasInterval = true
			break
		end
	end
	assert(stillHasInterval, "Guiding Wind controls stay visible even after moving all sub-options")
	pm.ResetAssignments()
	assert(pm.PreviewFlash("guidingWind") == true and wind.GetState().active, "Guiding Wind header preview triggers a gust")
	menuFrame:Hide()
	click(wheel, "LeftButton")
	assert(wind.db.enabled == false and not wind.GetState().active and not pm.IsModeActive("guidingWind") and icon.desaturated == true)
	-- Preview still works when Guiding Wind is disabled (without re-enabling it or starting auto-gusts).
	assert(pm.PreviewFlash("guidingWind") == true and wind.GetState().active
		and wind.db.enabled == false and not wind.GetState().timerActive,
		"Guiding Wind preview works while mode is disabled")
	ns.SetOption("GuidingWind", "enabled", false)

	-- Wrap forward to normal and backward to slot 6.
	shift = true
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	scroll(wheel, 1)
	assert(visuals.cdb.playerPortraitMode == 1 and not icon:IsShown() and not background:IsShown())
	assert(wheel.clickEnabled == false and wheel.motionEnabled == false, "normal portrait passes clicks through")
	scroll(wheel, -1)
	assert(visuals.cdb.playerPortraitMode == 6 and icon:IsShown(), "reverse scrolling also wraps to slot 6")

	-- Vehicle, Edit Mode and disabling the option hide the overlay cleanly.
	frame.unit = "vehicle"
	unitChanged(frame)
	scroll(wheel, -1)
	assert(not wheel.wheelEnabled and not icon:IsShown() and visuals.cdb.playerPortraitMode == 6)
	frame.unit = "player"
	unitChanged(frame)
	assert(wheel.wheelEnabled and icon:IsShown())
	edit = true
	callbacks["EditMode.Enter"]()
	scroll(wheel, -1)
	assert(not wheel.wheelEnabled and not wheel.clickEnabled and visuals.cdb.playerPortraitMode == 6)
	edit = false
	callbacks["EditMode.Exit"]()
	assert(wheel.wheelEnabled and wheel.clickEnabled)
	shift = false
	onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	assert(not wheel.wheelEnabled)
	ns.SetOption("Visuals", "playerPortraitWheel", false)
	assert(not icon:IsShown() and not background:IsShown() and visuals.cdb.playerPortraitMode == 6)
	ns.SetOption("Visuals", "playerPortraitWheel", true)
	assert(icon:IsShown() and icon.asset == 236154)

	-- Restore state cleanly.
	ns.SetOption("Visuals", "playerPortraitWheel", false)
	visuals.db.playerPortraitWheel, visuals.cdb.playerPortraitMode = true, saved.mode
	pm.ResetAssignments()
	ns.SetOption("GuidingWind", "enabled", saved.windOn)
	ns.SetOption("GuidingWind", "interval", saved.windInt)
	ns.SetOption("GuidingWind", "strength", saved.windStr)
	ns.SetOption("Wanderlust", "enabled", saved.wl)
	ns.SetOption("Wanderlust", "showBags", saved.wlBags)
	ns.SetOption("Helpers", "fishing", saved.fish)
	ns.SetOption("Roleplay", "enabled", saved.rp)
	ns.SetOption("Dialog", "enabled", saved.dlg)
	ns.SetOption("SpeechBubbles", "enabled", saved.sb)
	ns.SetOption("ChatEmotes", "enabled", saved.em)
	ns.SetOption("Camera", "enabled", saved.cam)
	ns.SetOption("SoloParty", "enabled", saved.spOn)
	ns.SetOption("SoloParty", "criticals", saved.spCrit)
	ns.SetOption("SoloParty", "bloody", saved.spBloody)
	ns.SetOption("Landing", "enabled", saved.land)
	ns.SetOption("CombatText", "enabled", saved.ct)
	setuv(pm.Setup, "portraitWheel", nil)
	setuv(pm.Setup, "portraitBackground", nil)
	setuv(pm.Setup, "portraitIcon", nil)
	setuv(pm.Setup, "portraitShade", nil)
	setuv(pm.Setup, "portraitShine", nil)
	setuv(uv(pm.Setup, "OpenModeMenu"), "menu", nil)
	setuv(uv(uv(pm.Setup, "OpenModeMenu"), "CreateModeMenu"), "iconPicker", nil)
	CreateFrame, PlayerFrame, hooksecurefunc = oldCreate, oldPlayer, oldHook
	IsShiftKeyDown, IsModifierKeyDown, EditModeManagerFrame, EventRegistry = oldShift, oldMod, oldEdit, oldRegistry
	GetCursorPosition, C_Timer.NewTicker = oldCursor, oldTicker
	print("player portrait modes OK")
end)()
;(function()
	local rp = ns:GetModule("Roleplay")
	local now, player, friendly, own = 10000, true, true, false
	local messages, timeout, save, encodedFixtures = {}, nil, nil, {}
	local oldCreate = CreateFrame
	local targetFrame = NewFrame("Frame")
	targetFrame.GetPortrait = function() return NewFrame("Texture") end
	local visuals = ns:GetModule("Visuals")
	local oldDragon, oldScale = visuals.db.playerDragon, visuals.db.dragonScale
	local oldGroup, oldArt = uv(visuals.ApplyPlayerDragon, "dragonButtons"), uv(visuals.ApplyPlayerDragon, "dragon")
	setuv(visuals.ApplyPlayerDragon, "dragonButtons", nil)
	setuv(visuals.ApplyPlayerDragon, "dragon", nil)
	local modified, editMode = false, false
	local playerFrame = NewFrame("Button")
	playerFrame.unit = "player"
	local dragonArt = {}
	local function RecordLayout(frame)
		frame.SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end
		frame.SetSize = function(self, width, height) self.w, self.h = width, height end
	end
	playerFrame.PlayerFrameContainer.CreateTexture = function()
		local texture = NewFrame("Texture")
		RecordLayout(texture)
		texture.SetVertexColor = function(self, ...) self.color = { ... } end
		tinsert(dragonArt, texture)
		return texture
	end
	local testGlobals = {
		TargetFrame = targetFrame,
		PlayerFrame = playerFrame,
		IsModifierKeyDown = function() return modified end,
		UnitIsPlayer = function() return player end,
		UnitIsFriend = function() return friendly end,
		UnitIsUnit = function() return own end,
		UnitFullName = function() return "Aelwyn", "Test Realm" end,
		GetNormalizedRealmName = function() return "LocalRealm" end,
		GetTime = function() return now end,
		C_ChatInfo = {
			RegisterAddonMessagePrefix = function(prefix) assert(prefix == "ForeverPlusRP1") return 0 end,
			SendAddonMessage = function(prefix, text, channel, target)
				assert(prefix == "ForeverPlusRP1" and channel == "WHISPER" and #prefix + #text < 255)
				messages[#messages + 1] = { text = text, target = target }
				return 0
			end,
		},
		C_EncodingUtil = {
			EncodeBase64 = function(data)
				local encoded = ("a"):rep(math.ceil(#data / 3) * 4)
				encodedFixtures[encoded] = data
				return encoded
			end,
			DecodeBase64 = function(encoded) return encodedFixtures[encoded] end,
		},
		CreateFrame = function(kind, name, parent, template)
			local frame = oldCreate(kind, name)
			if name == "ForeverPlusPlayerDragonButtons" then
				frame.GetParent = function() return parent end
				frame.Hide = function(self)
					self.shown = false
					self:GetScript("OnHide")(self)
				end
			elseif parent and parent == rawget(_G, "ForeverPlusPlayerDragonButtons") then
				frame.GetParent = function() return parent end
				RecordLayout(frame)
			elseif parent and parent == rawget(_G, "ForeverPlusRoleplayEditor") and template == "UIPanelButtonTemplate" then
				save = frame
			elseif kind == "EditBox" or template == "ForeverPlusRoleplayStoryInputTemplate" then
				local box = kind == "EditBox" and frame or frame.EditBox
				box.GetText = function(self) return self.value or "" end
				box.SetText = function(self, value) self.value = value end
			end
			return frame
		end,
	}
	local originals = {}
	for key, value in pairs(testGlobals) do
		originals[key], _G[key] = _G[key], value
	end
	local oldAfter, oldEditMode = C_Timer.After, ns.IsEditModeActive
	ns.IsEditModeActive = function() return editMode end
	local timeoutDelay
	C_Timer.After = function(delay, fn) timeoutDelay, timeout = delay, fn end
	local oldRegister, oldSend = Enum.RegisterAddonMessagePrefixResult, Enum.SendAddonMessageResult
	Enum.RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1 }
	Enum.SendAddonMessageResult = { Success = 0 }

	rp:OnLogin()
	local profileTooltip = TEST_POSTCALLS[#TEST_POSTCALLS]
	local onEvent = uv(ns.RegisterEvent, "eventFrame"):GetScript("OnEvent")
	local function Deliver(text, sender, channel)
		onEvent(nil, "CHAT_MSG_ADDON", "ForeverPlusRP1", text, channel or "WHISPER", sender)
	end
	local button = ForeverPlusRoleplayTargetButton
	button.GetCenter = function() return 15 end
	local click = button:GetScript("OnClick")
	assert(button:IsShown() and not rp.cdb.shared, "friendly player has a portrait button and sharing starts off")
	assert(#messages == 0, "selecting a target does not send a request")
	Deliver("Q:aca123", "Reader")
	assert(messages[1].text == "N:aca123" and messages[1].target == "Reader-LocalRealm", "private profile returns no data")

	ns.SetOption("Visuals", "dragonScale", 100)
	ns.SetOption("Visuals", "playerDragon", "none")
	local group = ForeverPlusPlayerDragonButtons
	local function DragonButtonAt(x, y)
		for _, part in ipairs(group.parts) do
			if part:IsShown() and x >= part.x and x < part.x + part.w and y <= part.y and y > part.y - part.h then
				return part
			end
		end
	end
	local hiddenButton = assert(DragonButtonAt(12, -49), "the hidden dragon has the plain hit area on first login")
	assert(#dragonArt == 0 and not DragonButtonAt(53, -48), "the fallback creates no art and leaves the portrait centre free")
	hiddenButton:GetScript("OnEnter")(hiddenButton)
	assert(not group:GetScript("OnUpdate"), "the invisible dragon needs no hover animation")

	ns.SetOption("Visuals", "playerDragon", "bronze")
	local dragonButton = assert(DragonButtonAt(12, -49), "the dragon's body is clickable")
	assert(not DragonButtonAt(53, -48), "the transparent portrait centre has no RP hit area")
	assert(DragonButtonAt(85, -73) and not DragonButtonAt(90, -73), "the plain dragon reacts at the thin tail tip")
	assert(not playerFrame:GetScript("PostClick"), "the normal player portrait has no RP hook")
	local art, shine = unpack(dragonArt)
	local restY, restShine = art.y, shine:GetAlpha()
	dragonButton:GetScript("OnEnter")(dragonButton)
	group:GetScript("OnUpdate")(group, 0.2)
	assert(art.y > restY and shine:GetAlpha() > restShine and shine.color[2] == art.color[2], "hover lifts the dragon and adds matching shine")
	assert(not group:GetScript("OnUpdate"), "the animation stops at the raised position")
	dragonButton:GetScript("OnLeave")(dragonButton)
	group:GetScript("OnUpdate")(group, 0.2)
	assert(art.y == restY and shine:GetAlpha() == restShine, "leaving restores the original dragon")
	modified = true
	dragonButton:GetScript("OnClick")(dragonButton)
	modified, editMode = false, true
	dragonButton:GetScript("OnClick")(dragonButton)
	editMode = false
	assert(not rawget(_G, "ForeverPlusRoleplayEditor"), "modified clicks and Edit Mode do not open the editor")
	rp.db.playerPortraitClick = false
	rp:OnOptionChanged("playerPortraitClick")
	assert(not group:IsShown() and art:IsShown(), "disabling the RP shortcut keeps the dragon as decoration")
	rp.db.playerPortraitClick = true
	visuals.db.playerDragon = "none"
	visuals.ApplyPlayerDragon()
	assert(group:IsShown() and not art:IsShown() and not shine:IsShown(), "hiding the dragon keeps only the shortcut")
	hiddenButton:GetScript("OnClick")(hiddenButton)
	assert(ForeverPlusRoleplayEditor:IsShown(), "the invisible dragon opens the RP editor")
	ForeverPlusRoleplayEditor:Hide()
	ns.SetOption("Roleplay", "playerPortraitClick", false)
	assert(not group:IsShown(), "the RP option also disables the invisible shortcut")
	ns.SetOption("Roleplay", "playerPortraitClick", true)
	visuals.db.playerDragon, visuals.db.dragonScale = "silverWinged", 120
	visuals.ApplyPlayerDragon()
	assert(group:IsShown() and DragonButtonAt(12, -70) and not DragonButtonAt(70, -54), "the winged silhouette scales with the art")
	assert(DragonButtonAt(118, -80) and not DragonButtonAt(124, -80), "the scaled winged dragon reacts at the thin tail tip")
	dragonButton = DragonButtonAt(12, -70)
	dragonButton:GetScript("OnClick")(dragonButton)
	local editor = ForeverPlusRoleplayEditor
	assert(editor:IsShown(), "left-clicking the portrait dragon opens the RP editor")
	editor:Hide()
	SlashCmdList.FOREVERPLUS("rp")
	assert(editor:IsShown(), "the slash command still opens the editor")
	local story = "Über den Pass.\n|Hitem:1|h[Text]|h\n" .. ("é"):rep(540)
	editor.Fields.name:SetText("  Émeline  ")
	editor.Fields.occupation:SetText("Bergführerin " .. ("x"):rep(80))
	editor.Fields.birthplace:SetText("Dun Morogh " .. ("x"):rep(80))
	editor.Fields.residence:SetText("Eisenschmiede " .. ("x"):rep(80))
	editor.Fields.story:SetText(story)
	editor.Share.GetChecked = function() return true end
	save:GetScript("OnClick")()
	assert(not editor:IsShown() and rp.cdb.shared and rp.cdb.profile.name == "Émeline", "the editor saves per character")
	assert(rp.cdb.profile.story:sub(-2) == "é" and #rp.cdb.profile.story <= 1100, "UTF-8 story is trimmed to whole characters")

	click()
	local viewer = ForeverPlusRoleplayViewer
	local loading, reads = ns.L.RP_LOADING, {}
	viewer.Text.SetText = function(_, text) reads[#reads + 1] = text end
	viewer.Hide = function(self)
		self.shown = false
		self:GetScript("OnHide")()
	end
	local query = messages[2]
	assert(query.text:match("^Q:%x+$") and query.target == "Aelwyn-TestRealm", "portrait queries the full target name")
	Deliver("N:" .. query.text:sub(3), "Aelwyn-LocalRealm")
	Deliver("N:" .. query.text:sub(3), "Aelwyn-TestRealm", "GUILD")
	assert(#reads == 0, "wrong realm or channel cannot answer")
	Deliver(query.text, "Reader-LocalRealm")
	assert(#messages == 2, "a response waits for enough budget to send every piece")
	now = now + 1
	Deliver(query.text, "Reader-LocalRealm")
	assert(#messages == 11, "long profile fits in nine pieces")
	for index = #messages, 3, -1 do
		Deliver(messages[index].text, "Aelwyn-TestRealm")
		if index > 3 then
			assert(#reads == 0, "response waits for all pieces")
			Deliver(messages[index].text, "Aelwyn-TestRealm")
		end
	end
	assert(#reads == 1 and reads[1]:find("Dun Morogh", 1, true)
		and reads[1]:find("Eisenschmiede", 1, true)
		and reads[1]:find("\n||Hitem:1||h[Text]||h\n", 1, true), "profile renders UTF-8, line breaks and literal markup")
	timeout()
	assert(#reads == 1, "a completed response cancels its timeout")

	now = now + 10
	click()
	click()
	assert(reads[#reads] == loading, "reopening fetches a fresh profile")
	local stale = messages[#messages].text:sub(3)
	player = false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	Deliver("N:" .. stale, "Aelwyn-TestRealm")
	timeout()
	assert(not button:IsShown() and not viewer:IsShown() and reads[#reads] == loading, "target change cancels the request")

	player, friendly = true, false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	assert(not button:IsShown(), "hostile players have no portrait button")
	friendly = true
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	click()
	local lateID = messages[#messages].text:sub(3)
	assert(timeoutDelay == 3, "a silent native target stops showing the loading message after three seconds")
	now = now + timeoutDelay
	timeout()
	assert(reads[#reads] == ns.L.RP_NO_REPLY, "an unanswered native request shows its status")
	now = now + 1
	for index = 3, 11 do
		local packet = messages[index].text:gsub("^P:%x+:", "P:" .. lateID .. ":")
		Deliver(packet, "Aelwyn-TestRealm")
	end
	assert(reads[#reads]:find("Dun Morogh", 1, true), "a native reply still replaces the status after four seconds")

	own, rp.cdb.shared = true, false
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	local sent = #messages
	click()
	assert(viewer:IsShown() and not editor:IsShown() and #messages == sent
		and reads[#reads]:find("Émeline", 1, true), "self target opens a read-only preview of the saved private profile")
	local profile = rp.cdb.profile
	rp.cdb.profile = {}
	click()
	click()
	assert(viewer:IsShown() and reads[#reads] == ns.L.RP_EMPTY and #messages == sent, "empty self profile stays in the viewer")
	rp.cdb.profile, rp.cdb.shared = profile, true

	local oldNewTimer = C_Timer.NewTimer
	local hoverTimer, overBook, overViewer
	C_Timer.NewTimer = function(_, callback)
		hoverTimer = { Fire = callback, Cancel = function(self) self.cancelled = true end }
		return hoverTimer
	end
	button.IsMouseOver = function() return overBook end
	viewer.IsMouseOver = function() return overViewer end
	local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
	own, overBook = false, true
	onEvent(nil, "PLAYER_TARGET_CHANGED")
	enter(button)
	leave(button)
	assert(hoverTimer.cancelled and not viewer:IsShown() and #messages == sent, "passing over the book sends no request")
	enter(button)
	hoverTimer:Fire()
	assert(viewer:IsShown() and reads[#reads] == loading and #messages == sent + 1, "hover requests and opens the target profile")
	local update = viewer:GetScript("OnUpdate")
	overBook = false
	update(viewer, 0.15)
	overViewer = true
	update(viewer, 0.5)
	assert(viewer:IsShown(), "the preview stays open while crossing into and reading the window")
	click()
	assert(viewer:IsShown() and not viewer:GetScript("OnUpdate") and #messages == sent + 1, "click pins the existing preview without requesting it again")
	click()
	assert(not viewer:IsShown(), "the pinned preview closes with a second click")
	overBook, overViewer = true, false
	enter(button)
	hoverTimer:Fire()
	overBook = false
	viewer:GetScript("OnUpdate")(viewer, 0.4)
	assert(not viewer:IsShown() and not viewer:GetScript("OnUpdate"), "the preview closes after the pointer leaves the book and window")
	C_Timer.NewTimer = oldNewTimer

	rp.db.enabled = false
	rp:OnOptionChanged()
	local before = #messages
	Deliver("Q:aca456", "Reader-LocalRealm")
	assert(not button:IsShown() and not viewer:IsShown() and #messages == before, "disabling hides the UI and stops sharing")

	local oldTipUnit, oldTipAdd, oldRefresh = GameTooltip.GetUnit, GameTooltip.AddLine, ns.RefreshGameTooltip
	local oldBit, oldOwner = rawget(_G, "bit"), rawget(_G, "msp_RPAddOn")
	local function Bitwise(a, b, xor)
		local result, place = 0, 1
		while a > 0 or b > 0 do
			local left, right = a % 2, b % 2
			if (xor and left ~= right) or (not xor and left == 1 and right == 1) then result = result + place end
			a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
		end
		return result
	end
	bit = { band = Bitwise, bxor = function(a, b) return Bitwise(a, b, true) end,
		rshift = function(a, count) return math.floor(a / 2 ^ count) end }
	local actor, unit, refreshes, tipLines = "Wren", "mouseover", 0, {}
	local wasShown = GameTooltip:IsShown()
	GameTooltip:Show()
	UnitFullName = function() return actor, "Test Realm" end
	GameTooltip.GetUnit = function() return actor, unit end
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = line end
	ns.RefreshGameTooltip = function() refreshes = refreshes + 1 end
	local mspOut = {}
	local function SendMSP(logged, prefix, text, channel, target)
		assert(prefix == "MSP2" and #text <= 255 and channel == "WHISPER")
		assert(text:find("^00A%x%x%x%x%x%x%x%x%x"))
		mspOut[#mspOut + 1] = { text = text, logged = logged, target = target }
		return 0
	end
	local registerNative, sendNative = C_ChatInfo.RegisterAddonMessagePrefix, C_ChatInfo.SendAddonMessage
	C_ChatInfo.RegisterAddonMessagePrefix = function(prefix)
		if prefix == "MSP2" then return 0 end
		return registerNative(prefix)
	end
	C_ChatInfo.SendAddonMessage = function(prefix, ...)
		if prefix == "MSP2" then return SendMSP(false, prefix, ...) end
		return sendNative(prefix, ...)
	end
	C_ChatInfo.SendAddonMessageLogged = function(...) return SendMSP(true, ...) end
	local function MSPMessage(text, logged, sender, seq, length)
		local event = logged and "CHAT_MSG_ADDON_LOGGED" or "CHAT_MSG_ADDON"
		onEvent(nil, event, "MSP2", ("00ABCD%03X%03X%s"):format(seq or 1, length or 1, text),
			"WHISPER", sender or "Wren-TestRealm")
	end

	rp.db.enabled, rp.cdb.shared = true, false
	rp:OnOptionChanged()
	now = now + 20
	MSPMessage("?TT", false)
	assert(#mspOut == 0, "MSP never publishes a private profile")
	own = true
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Émeline" and tipLines[2]:find("Bergführerin", 1, true) and #mspOut == 0,
		"the own tooltip shows the saved name and occupation even for a private profile")
	own, tipLines = false, {}
	profileTooltip(GameTooltip)
	profileTooltip(GameTooltip)
	assert(#tipLines == 0 and #mspOut == 1 and not mspOut[1].logged
		and mspOut[1].target == "Wren-TestRealm" and mspOut[1].text:sub(13) == "?TT`?PX`?RC",
		"the player tooltip sends a throttled request for MSP summary fields")

	MSPMessage("NA:Unsolicited", true, "Wren-LocalRealm")
	MSPMessage("NA:Unlogged", false)
	assert(refreshes == 0, "a wrong-realm or unlogged MSP response cannot refresh the tooltip")
	MSPMessage("NA:~7Ccfffafa00Sire Élan~7Cr`PX:Sire`RC:Waldläufer`TT1234", true)
	assert(refreshes == 1, "the MSP response refreshes the current player tooltip")
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Sire Élan" and tipLines[2] == "Waldläufer",
		"the tooltip strips colour codes and uses the RP class if the short title is already part of the name")

	click()
	assert(#mspOut == 2 and mspOut[2].text:find("?HI", 13, true), "the target book also requests the full external profile")
	local prior = #reads
	MSPMessage("~7CLink~7C", true, nil, 2, 2)
	assert(#reads == prior, "profile waits for all parts")
	MSPMessage("NT:Hüterin`HB:Westfall`HH:Stormwind`DE:Beschreibung`PE:Silberner Ring`HI8AB1:Zeile~0A", true, nil, 1, 2)
	assert(reads[#reads]:find("Hüterin", 1, true) and reads[#reads]:find("Westfall", 1, true)
		and reads[#reads]:find("Stormwind", 1, true) and reads[#reads]:find("Beschreibung", 1, true)
		and reads[#reads]:find("Silberner Ring", 1, true)
		and reads[#reads]:find("Zeile\n||Link||", 1, true),
		"the target book maps external fields and displays escaped UTF-8 text")
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[2] == "Hüterin", "the long title takes precedence over the RP class")
	actor = "SomeoneElse"
	local beforeRefresh = refreshes
	MSPMessage("NT:New Title", true)
	assert(refreshes == beforeRefresh, "an answer never refreshes another player's tooltip")
	click()

	rp.cdb.shared = true
	local savedStory = rp.cdb.profile.story
	rp.cdb.profile.story = ("é~\\\n"):rep(175) .. "Ende"
	now = now + 20
	local first = #mspOut + 1
	MSPMessage("?VA`?NA`?NT`?HB`?HH`?HI", false)
	local wire = ns.RoleplayMSP
	local payload, fragments = nil, {}
	for index = first, #mspOut do
		local packet = mspOut[index]
		assert(packet.logged and packet.target == "Wren-TestRealm")
		payload = wire.Packet(packet.text, true, fragments) or payload
	end
	assert(#mspOut > first and payload, "the logged profile response is split into Chomp packets")
	local _, fields = wire.Commands(payload, true)
	assert(fields.VP == "3" and fields.VA == "ForeverPlus/" .. ns.version and fields.NA == "Émeline"
		and fields.NT == rp.cdb.profile.occupation and fields.HB == rp.cdb.profile.birthplace
		and fields.HH == rp.cdb.profile.residence and fields.HI == rp.cdb.profile.story,
		"other RP addons receive all five enabled fields, including multiline UTF-8 and codec characters")
	msp_RPAddOn = "Other RP"
	first = #mspOut
	MSPMessage("?TT", false)
	assert(#mspOut == first, "another local MSP addon owns the MSP answers")
	msp_RPAddOn = oldOwner
	local sendLogged = C_ChatInfo.SendAddonMessageLogged
	Enum.SendAddonMessageResult.AddonMessageThrottle = 3
	C_ChatInfo.SendAddonMessageLogged = function() return 3 end
	now, timeout = now + 20, nil
	MSPMessage("?TT", false)
	assert(timeout, "a throttled MSP reply schedules a retry")
	local retry = timeout
	C_ChatInfo.SendAddonMessageLogged = sendLogged
	rp.cdb.shared = false
	retry()
	assert(#mspOut == first, "an already queued reply stops when profile sharing is turned off")
	rp.cdb.shared = true
	rp.cdb.profile.story = savedStory

	rp.db.compatibleProfiles = false
	rp:OnOptionChanged("compatibleProfiles")
	MSPMessage("?TT", false)
	assert(#mspOut == first, "the compatibility toggle stops MSP replies")
	now = now + 20
	local nativeBefore = #messages
	profileTooltip(GameTooltip)
	assert(#messages == nativeBefore + 1 and #mspOut == first, "the tooltip uses native queries when MSP is off")
	local id = messages[#messages].text:sub(3)
	Deliver("Q:" .. id, "Reader")
	for index = nativeBefore + 2, #messages do Deliver(messages[index].text, "SomeoneElse-TestRealm") end
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Émeline", "the tooltip displays a native ForeverPlus profile")
	rp.db.profileTooltip = false
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(#tipLines == 0, "the tooltip option switches off both RP lines")
	rp.db.profileTooltip, rp.db.compatibleProfiles = true, true

	-- Forever units return a surname, while a message can append an internal realm to its sender.
	setuv(rp.OnLogin, "regionalNames", true)
	UnitFullName = function() return "Wren", "Stonefist" end
	rp:OnOptionChanged("compatibleProfiles")
	now = now + 20
	click()
	assert(mspOut[#mspOut].target == "Wren Stonefist" and messages[#messages].target == "Wren Stonefist",
		"Forever whispers address the full regional character name")
	local displayed = #reads
	MSPMessage("NA:Other profile", true, "Wren Birch-CAMWOW EU4 Realm 7 PvE")
	assert(#reads == displayed, "another character with the same first name cannot answer")
	MSPMessage("NA:Élan of Westfall`NT:Hüterin`HB:Westfall", true, "Wren Stonefist-CAMWOW EU4 Realm 7 PvE")
	assert(reads[#reads]:find("Élan of Westfall", 1, true), "a realm-decorated Forever reply matches the open profile")
	UnitFullName = function() return "Wren Stonefist", "CAMWOW EU4 Realm 7 PvE" end
	tipLines = {}
	profileTooltip(GameTooltip)
	assert(tipLines[1] == "Élan of Westfall" and tipLines[2] == "Hüterin",
		"the tooltip uses the same regional character key as the profile response")
	now = now + 20
	MSPMessage("?TT", false, "Reader Oak-CAMWOW EU4 Realm 7 PvE")
	assert(mspOut[#mspOut].logged and mspOut[#mspOut].target == "Reader Oak", "MSP replies strip the sender's internal realm")
	local activeProfile = rp.cdb.profile
	rp.cdb.profile = { name = "Émeline" }
	Deliver("Q:abc123", "Reader Oak-CAMWOW EU4 Realm 7 PvE")
	assert(messages[#messages].target == "Reader Oak" and messages[#messages].text:find("^P:abc123:"),
		"native replies also use the regional whisper name")
	rp.cdb.profile = activeProfile
	click()

	UnitFullName = function() return "Doran", "Amber" end
	now = now + 20
	local beforeProbe = #mspOut
	click()
	assert(timeoutDelay == 3, "a silent MSP target stops showing the loading message after three seconds")
	now = now + timeoutDelay
	timeout()
	assert(#mspOut == beforeProbe + 1 and reads[#reads] == ns.L.RP_NO_REPLY, "an unanswered MSP request shows its status")
	click()
	now = now + 16
	click()
	assert(#mspOut == beforeProbe + 1, "manual reopening does not resend during the response window")
	click()
	now = now + 1
	click()
	assert(#mspOut == beforeProbe + 2, "manual reopening can retry an unanswered MSP query once the response window ends")
	now = now + timeoutDelay
	timeout()
	assert(reads[#reads] == ns.L.RP_NO_REPLY)
	now = now + 7
	MSPMessage("NA:Doran of Ironforge", true, "Doran Amber")
	assert(reads[#reads]:find("Doran of Ironforge", 1, true), "an MSP reply still replaces the status after ten seconds")
	click()

	local workingSend = C_ChatInfo.SendAddonMessage
	C_ChatInfo.SendAddonMessage = function() return 7 end
	UnitFullName = function() return "Aldren", "Ash" end
	now = now + 20
	click()
	assert(reads[#reads] == ns.L.RP_SEND_FAILED, "the book reports a client send failure on both transports immediately")
	click()
	C_ChatInfo.SendAddonMessage = workingSend
	setuv(rp.OnLogin, "regionalNames", false)

	GameTooltip.GetUnit, GameTooltip.AddLine, ns.RefreshGameTooltip = oldTipUnit, oldTipAdd, oldRefresh
	GameTooltip:SetShown(wasShown)
	bit = oldBit

	visuals.db.playerDragon, visuals.db.dragonScale = oldDragon, oldScale
	setuv(visuals.ApplyPlayerDragon, "dragonButtons", oldGroup)
	setuv(visuals.ApplyPlayerDragon, "dragon", oldArt)
	visuals.ApplyPlayerDragon()
	for key, value in pairs(originals) do _G[key] = value end
	C_Timer.After, ns.IsEditModeActive = oldAfter, oldEditMode
	Enum.RegisterAddonMessagePrefixResult, Enum.SendAddonMessageResult = oldRegister, oldSend
	rp.db.enabled, rp.cdb.shared, rp.cdb.profile = true, false, {}
	print("roleplay editor, native and MSP profile exchange, and player tooltip OK")
end)()
;(function()
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
;(function()
	-- A timed measurement (middle click on the performance display) says in the chat that it has started
	local saved = { ns.PrintAlways, C_Timer.NewTimer, ns.measureTimer, ns.measureUntil }
	local said
	ns.PrintAlways = function(msg, ...) said = msg:format(...) end
	C_Timer.NewTimer = function() return { Cancel = function() end } end
	ns.measureTimer = nil
	ns.StartTimedMeasure(30)
	assert(said == ns.L.TIMINGS_ON_TIMED:format(30) and said:find("30"), "start message with the duration")
	ns.SetMeasuring(false)
	ns.PrintAlways, C_Timer.NewTimer, ns.measureTimer, ns.measureUntil = unpack(saved, 1, 4)
	print("timed measurement start OK")
end)()

-- Weapon reminder: a permanent enchant on the same weapon does not stand in for the imbue's time
;(function()
	local buffs = ns:GetModule("Buffs")
	local saved = Enum.ItemEnchantType
	Enum.ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 }
	local imbue = { hasEnchant = true, enchantType = 3, timeLeft = 1680000 }
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 0 }, imbue }) == 1680,
		"permanent enchant listed first with no timer: imbue time counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 1 }, imbue }) == 1680,
		"permanent enchant listed first with a tiny timer: imbue time counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 1, timeLeft = 0 } }) == nil,
		"only a permanent enchant: imbue missing")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = false, enchantType = 0, timeLeft = 0 } }) == nil, "nothing on the weapon")
	assert(buffs.EnchantTimeLeft(nil) == nil and buffs.EnchantTimeLeft({}) == nil, "no list")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 2, timeLeft = 30000 } }) == 30, "temporary enchant counts")
	assert(buffs.EnchantTimeLeft({ { hasEnchant = true, enchantType = 2, timeLeft = 30000 }, imbue }) == 1680,
		"two timed entries: the longer one")
	Enum.ItemEnchantType = saved
	print("weapon enchant time OK")
end)()
-- Auction house: cash register sound on live sales and unread sale mail with gold
;(function()
	local A = ns:GetModule("Auction")
	local saved = {
		PlaySoundFile, PlaySound, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo,
		ERR_AUCTION_SOLD_S, AUCTION_SOLD_MAIL_SUBJECT, Enum.AuctionHouseNotification, SOUNDKIT.LOOT_WINDOW_COIN_SOUND,
		A.db.saleSound,
	}
	local now, filePlays, kitPlays, fileOk = 100, {}, {}, true
	PlaySoundFile = function(file, channel)
		filePlays[#filePlays + 1] = { file, channel }
		return fileOk
	end
	PlaySound = function(kit, channel)
		kitPlays[#kitPlays + 1] = { kit, channel }
	end
	GetTime = function() return now end
	SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 895
	Enum.AuctionHouseNotification = {
		BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2,
		AuctionOutbid = 3, AuctionSold = 4, AuctionExpired = 5,
	}
	ERR_AUCTION_SOLD_S = "Für Eure Auktion von %s wurde ein Käufer gefunden."
	AUCTION_SOLD_MAIL_SUBJECT = "Auktion erfolgreich: %s"

	local inbox = {}
	GetInboxNumItems = function() return #inbox, #inbox end
	GetInboxHeaderInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, m.money, 0, 29, m.items, m.wasRead
	end
	GetInboxInvoiceInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return m.invoiceType, m.itemName, m.playerName, m.bid
	end

	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end

	A.db.saleSound = true
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()

	-- Live notification events: only AuctionSold plays
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionExpired, "Kupfererz")
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionOutbid, "Kupfererz")
	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionWon, "Kupfererz")
	assert(#filePlays == 0, "expired, outbid, won stay silent")

	Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold, "Kupfererz")
	assert(#filePlays == 1 and filePlays[1][1]:find("AuctionKaChing%.mp3$") and filePlays[1][2] == "Master",
		"live formatted AuctionSold plays the cash register sound on Master")

	-- Debounce prevents stacked noise when several auctions sell in the same second
	now = 100.5
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#filePlays == 1, "rapid second sale within cooldown stays silent")

	now = 103
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#filePlays == 2, "sale after cooldown plays again")

	-- System chat fallback matches both German and English ERR_AUCTION_SOLD_S
	now = 110
	Fire("CHAT_MSG_SYSTEM", "Eure Auktion von Kupfererz ist abgelaufen.")
	assert(#filePlays == 2, "unrelated system message stays silent")
	Fire("CHAT_MSG_SYSTEM", "Für Eure Auktion von Kupfererz wurde ein Käufer gefunden.")
	assert(#filePlays == 3, "German ERR_AUCTION_SOLD_S system message plays")
	ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
	now = 115
	Fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Copper Ore.")
	assert(#filePlays == 4, "English ERR_AUCTION_SOLD_S system message plays")

	-- Mailbox scan: only unread AH sale mail with money plays
	now = 120
	inbox = {
		{ sender = "Auktionshaus der Allianz", subject = "Auktion abgelaufen: Kupfererz", money = 0, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Überboten: Kupfererz", money = 5000, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion gewonnen: Leinenstoff", money = 0, wasRead = false, invoiceType = "buyer", itemName = "Leinenstoff", bid = 1200 },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Seidenstoff", money = 0, wasRead = false, invoiceType = "seller_temp_invoice", itemName = "Seidenstoff", bid = 3000 },
		{ sender = "Freund", subject = "Hier dein Gold", money = 10000, wasRead = false },
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Kupfererz", money = 4750, wasRead = true, invoiceType = "seller", itemName = "Kupfererz", bid = 5000 },
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 4, "expired, outbid, bought, pending temp invoice, player gold, and already-read sale mail stay silent")

	-- Unread seller mail with proceeds plays once, not repeatedly while the mailbox stays open
	now = 125
	inbox[#inbox + 1] = {
		sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz",
		money = 9500, wasRead = false, invoiceType = "seller", itemName = "Silbererz", bid = 10000,
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "unread AH sale mail with gold plays")

	now = 130
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "same unread sale mail does not replay on next inbox update")

	-- MAIL_SHOW with empty inbox before server response must not clear remembered unread mails
	local savedInbox = inbox
	inbox = {}
	now = 135
	Fire("MAIL_SHOW")
	inbox = savedInbox
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 5, "empty MAIL_SHOW before MAIL_INBOX_UPDATE keeps remembered sale mails")

	-- A second identical unread sale increases the count and plays
	now = 140
	inbox[#inbox + 1] = {
		sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz",
		money = 9500, wasRead = false, invoiceType = "seller", itemName = "Silbererz", bid = 10000,
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 6, "a second identical unread sale plays")

	-- After looting all mails, a later identical sale plays again
	inbox = {}
	now = 145
	Fire("MAIL_INBOX_UPDATE")
	inbox = {
		{ sender = "Auktionshaus der Allianz", subject = "Auktion erfolgreich: Silbererz", money = 9500, wasRead = false },
	}
	now = 150
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 7, "fallback subject match plays when invoice info is nil and money > 0")

	-- Fallback to Blizzard coin sound when PlaySoundFile returns false
	fileOk = false
	now = 155
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	assert(#kitPlays == 1 and kitPlays[1][1] == 895 and kitPlays[1][2] == "Master",
		"falls back to LOOT_WINDOW_COIN_SOUND when custom file fails")
	fileOk = true

	-- Option off unregisters events; test button still plays via force
	A.db.saleSound = false
	A:OnOptionChanged("saleSound")
	now = 160
	Fire("AUCTION_HOUSE_SHOW_NOTIFICATION", Enum.AuctionHouseNotification.AuctionSold)
	Fire("MAIL_INBOX_UPDATE")
	assert(#filePlays == 8, "option off: live sale and mailbox updates stay silent")
	assert(A.PlaySaleSound(true) == true and #filePlays == 9, "test button plays regardless of option and cooldown")
	assert(A.PlaySaleSound(true) == true and #filePlays == 10, "repeated test clicks play without cooldown")

	PlaySoundFile, PlaySound, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = unpack(saved, 1, 6)
	ERR_AUCTION_SOLD_S, AUCTION_SOLD_MAIL_SUBJECT, Enum.AuctionHouseNotification, SOUNDKIT.LOOT_WINDOW_COIN_SOUND = unpack(saved, 7, 10)
	A.db.saleSound = saved[11]
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()
	print("auction sale sound OK")
end)()
;(function()
	-- Emote tab: sections like the chat menu, aliases, faction filtering, search and token resolution.
	local emotes = ns:GetModule("ChatEmotes")
	assert(emotes and emotes.BuildSections and emotes.FilterSections and emotes.ResolveToken, "chat emotes module")
	local strings = {
		EMOTE1_TOKEN = "WAVE", EMOTE1_CMD1 = "/winken", EMOTE1_CMD2 = "/wave", EMOTE1_CMD3 = "/WINKEN",
		EMOTE2_TOKEN = "BOW", EMOTE2_CMD1 = "/Verbeugen", EMOTE2_CMD2 = "/bow",
		EMOTE3_TOKEN = "UNUSED", EMOTE3_CMD1 = "/unused",
		EMOTE4_TOKEN = "CHEER", EMOTE4_CMD1 = "/jubeln", EMOTE4_CMD2 = "/cheer",
		EMOTE5_TOKEN = "WAVE", EMOTE5_CMD1 = "/wave2",
		EMOTE6_TOKEN = "NOCMD",
		EMOTE7_TOKEN = "FORTHEALLIANCE", EMOTE7_CMD1 = "/fürdieallianz",
		EMOTE8_TOKEN = "FORTHEHORDE", EMOTE8_CMD1 = "/fürdiehorde",
	}
	local sections = emotes.BuildSections(
		function(name) return strings[name] end,
		{ "WAVE", "UNKNOWN" },
		{ "CHEER", "FORTHEALLIANCE", "FORTHEHORDE" },
		8,
		"Alliance"
	)
	assert(#sections == 3, "three sections")
	assert(sections[1].title == ns.L.CHATEMOTES_ANIMATED and sections[2].title == ns.L.CHATEMOTES_VOICE
		and sections[3].title == ns.L.CHATEMOTES_ALL, "section titles")
	assert(sections[1].entries[1].token == "WAVE" and sections[1].entries[1].command == "/winken", "animated: first index command")
	assert(#sections[1].entries[1].aliases == 1 and sections[1].entries[1].aliases[1] == "/wave", "aliases deduplicated case-insensitively")
	assert(sections[1].entries[2].command == "UNKNOWN", "token without command keeps token as label")
	assert(#sections[2].entries == 2 and sections[2].entries[1].token == "CHEER"
		and sections[2].entries[2].token == "FORTHEALLIANCE", "voice emotes skip opposite faction")
	local all = sections[3].entries
	assert(#all == 4, "all: skips UNUSED, NOCMD, duplicate WAVE and opposite faction: " .. #all)
	assert(all[1].token == "FORTHEALLIANCE" and all[2].token == "CHEER" and all[3].token == "BOW" and all[4].token == "WAVE",
		"all: sorted by command")
	assert(emotes.FilterSections(sections, "   ") == sections and emotes.FilterSections(sections, "/") == sections,
		"empty or slash-only filter keeps all sections")
	local byAlias = emotes.FilterSections(sections, "/WAVE")
	assert(#byAlias == 1 and #byAlias[1].entries == 1 and byAlias[1].entries[1].token == "WAVE", "filter matches English alias with slash")
	local byCmd = emotes.FilterSections(sections, "jubel")
	assert(#byCmd == 1 and #byCmd[1].entries == 1 and byCmd[1].entries[1].token == "CHEER", "filter matches localized command")
	assert(#emotes.FilterSections(sections, "gibtesnicht") == 0, "unmatched filter returns empty")
	assert(emotes.ResolveToken("FORTHEHORDE", "Alliance") == "FORTHEALLIANCE", "resolve switches battle cry to Alliance")
	assert(emotes.ResolveToken("FORTHEALLIANCE", "Horde") == "FORTHEHORDE", "resolve switches battle cry to Horde")
	assert(emotes.ResolveToken("WAVE", "Horde") == "WAVE", "resolve leaves normal emotes untouched")
	assert(#emotes.BuildSections(function() end, nil, nil, nil)[3].entries == 0, "missing game lists give empty sections")
	-- Virtualized layout: rows and visible viewport window.
	local rows, totalHeight, totalEntries = emotes.BuildRows(sections, 2)
	-- 3 sections: (2 -> 1 row), (2 -> 1 row), (4 -> 2 rows) = 3 headers + 4 entry rows = 7 rows.
	assert(#rows == 7 and totalEntries == 8 and totalHeight == 3 * (20 + 6) + 4 * 18, "virtual row layout math")
	assert(rows[1].header == ns.L.CHATEMOTES_ANIMATED and rows[2].first == 1 and rows[2].last == 2, "first section rows")
	assert(rows[6].first == 1 and rows[6].last == 2 and rows[7].first == 3 and rows[7].last == 4, "all section split into two rows")
	local first, last = emotes.VisibleRange(rows, 0, 40)
	assert(first == 1 and last >= 2 and last < #rows, "top viewport renders only visible prefix")
	local fMid, lMid = emotes.VisibleRange(rows, totalHeight - 36, 36)
	assert(fMid > 1 and lMid == #rows, "bottom viewport renders tail rows")
	local fEmpty, lEmpty = emotes.VisibleRange(rows, totalHeight + 200, 36)
	assert(fEmpty > lEmpty, "scroll past end renders nothing")
	local fZero, lZero = emotes.VisibleRange({}, 0, 100)
	assert(fZero > lZero, "empty rows render nothing")
	print("chat emotes OK")
end)()
;(function()
	local M = ns:GetModule("MacroIcons")
	assert(M and M.db.enabled == true, "macro icon search on by default")
	assert(M.Normalize("ÄÖÜ Sword_04") == "äöü sword 04", "normalize lowers ASCII, capital umlauts and underscores")
	local data = "\nspell fire flamebolt|fireball|feuerball\t135812\nability warrior charge|charge|sturmangriff\t132337\ninv sword 04\t135274\n"
	local found = M.Find(data, "Feuerball")
	assert(found[135812] and not found[132337], "German name finds the icon")
	found = M.Find(data, "FIREBALL")
	assert(found[135812], "English name, any case")
	found = M.Find(data, "fire  sword")
	assert(not next(found), "all words must match")
	found = M.Find(data, "sturm  warrior")
	assert(found[132337] and not found[135812], "several words from different names")
	found = M.Find(data, "135")
	assert(not next(found), "file IDs are not searched")
	assert(M.Find(data, "   ") == nil, "empty query searches nothing")
	-- Long line (> 256 bytes) and no trailing newline.
	local longData = "alpha|" .. string.rep("x", 320) .. "|omega\t999001"
	local longFound = M.Find(longData, "alpha omega")
	assert(longFound[999001], "multi-word match across >256-byte line without trailing newline")
	local icons = { "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK", 132337, 135812, 135274, 132337, "INTERFACE\\ICONS\\Spell_Fire_Fireball" }
	local f2, words = M.Find(data, "fire")
	local results = M.Collect(function(i) return icons[i] end, #icons, f2, words)
	assert(#results == 2 and results[1].icon == 135812 and results[1].index == 3
		and results[2].icon == "INTERFACE\\ICONS\\Spell_Fire_Fireball" and results[2].index == 6,
		"picker order, loose icons by file name, no repeats")
	f2, words = M.Find(data, "charge")
	results = M.Collect(function(i) return icons[i] end, #icons, f2, words)
	assert(#results == 1 and results[1].index == 2, "repeated icon listed once at its first place")

	-- Indexed & time-sliced search matches Collect and yields cleanly under a tight deadline.
	local idx = M.NewIndex(function(i) return icons[i] end, #icons)
	assert(M.StepIndex(idx) == true and idx.ready, "index builds completely")
	local findState, fWords = M.StartFind(data, "fire")
	assert(M.StepFind(findState) == true and findState.done, "step find completes")
	local st = { find = findState, words = fWords, collectPos = 1, collected = false }
	assert(M.StepCollect(idx, st) == true and st.collected, "direct indexed collect completes")
	assert(#st.results == 2 and st.results[1].icon == 135812 and st.results[1].index == 3
		and st.results[2].icon == "INTERFACE\\ICONS\\Spell_Fire_Fireball" and st.results[2].index == 6,
		"indexed direct collect matches Collect order")
	-- Force the large-match sliced path (count > 400) and verify identical picker order.
	local bigSt = { find = { found = findState.found, count = 500 }, words = fWords, collectPos = 1, collected = false }
	assert(M.StepCollect(idx, bigSt) == true and bigSt.collected, "sliced indexed collect completes")
	assert(#bigSt.results == 2 and bigSt.results[1].index == 3 and bigSt.results[2].index == 6,
		"sliced indexed collect matches Collect order")

	-- Bundled data: real names in both languages, fast enough per keystroke, exact match vs full scan.
	local bundled = ns.MacroIconNames
	assert(type(bundled) == "string" and #bundled > 500000, "bundled icon names loaded")
	local start = os.clock()
	local de = M.Find(bundled, "feuerball")
	local elapsed = os.clock() - start
	local en = M.Find(bundled, "fireball")
	assert(de[135812] and en[135812], "Fireball icon by German and English name")
	assert(M.Find(bundled, "sword")[135274], "file name search")
	assert(M.Find(bundled, "heiltrank")[134831], "German item name")
	-- Cross-check sliced Find against a reference gmatch scan on a multi-word query.
	local ref = {}
	for text, id in bundled:gmatch("([^\t\n]+)\t(%d+)") do
		if text:find("fire", 1, true) and text:find("bolt", 1, true) then ref[tonumber(id)] = true end
	end
	local savedClock, clock = debugprofilestop, 0
	debugprofilestop = function() clock = clock + 1 return clock end
	local sliced = M.StartFind(bundled, "fire bolt")
	local steps = 0
	while not M.StepFind(sliced, clock + 0.5) do steps = steps + 1 end
	local miss = M.StartFind(bundled, "zzzznotaniconzzzz")
	local missSteps = 0
	while not M.StepFind(miss, clock + 0.5) do missSteps = missSteps + 1 end
	debugprofilestop = savedClock
	assert(steps >= 1 and missSteps >= 1 and not next(miss.found), "chunked find yields on both hits and zero-match scans")
	local refCount, slicedCount = 0, 0
	for id in pairs(ref) do
		refCount = refCount + 1
		assert(sliced.found[id], "sliced find includes " .. id)
	end
	for id in pairs(sliced.found) do
		slicedCount = slicedCount + 1
		assert(ref[id], "sliced find has no extra id " .. id)
	end
	assert(refCount == slicedCount and refCount > 0, "sliced find matches reference scan exactly")
	assert(elapsed < 0.05, "search over all icons takes " .. elapsed .. " s")
	print(("macro icon search OK (%.1f ms)"):format(elapsed * 1000))
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	local db = visuals.db
	local savedClass, savedUsable, savedButton = UnitClass, C_Spell.IsSpellUsable, MultiCastRecallSpellButton
	local savedSecret, savedColors = issecretvalue, db.totemRecallColors
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local onEvent = eventFrame:GetScript("OnEvent")
	local icon = NewFrame("Texture")
	local button = { icon = icon }
	local usable, noMana, queries = false, false, 0
	local secret = {}
	issecretvalue = function(value) return value == secret end
	UnitClass = function() return "Shaman", "SHAMAN" end
	MultiCastRecallSpellButton = button
	C_Spell.IsSpellUsable = function(spellID)
		assert(spellID == 36936, "recall uses the spell ID assigned by the native button")
		queries = queries + 1
		return usable, noMana
	end
	assert(visuals.defaults.totemRecallColors, "recall colors default on")
	assert(_G["BINDING_NAME_CLICK MultiCastRecallSpellButton:LeftButton"] == ns.L.VISUALS_TOTEM_RECALL_BINDING,
		"binding targets the original recall button")
	db.totemRecallColors = true
	visuals:OnOptionChanged("totemRecallColors")
	assert(queries == 0, "unlearned recall has no spell usability query")

	button.spellId = 36936
	onEvent(eventFrame, "PLAYER_TOTEM_UPDATE")
	assert(icon.vertexColor[1] == 0.4 and icon.vertexColor[3] == 0.4, "unusable recall is gray")
	noMana = true
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 0.5 and icon.vertexColor[3] == 1, "low mana colors recall blue")
	usable = secret
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 0.5, "protected usability keeps the last readable color")
	usable, noMana = true, false
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 1, "usable recall has full color")

	usable = false
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	db.totemRecallColors = false
	visuals:OnOptionChanged("totemRecallColors")
	local before = queries
	onEvent(eventFrame, "SPELL_UPDATE_USABLE")
	assert(icon.vertexColor[1] == 1 and queries == before, "turning recall colors off restores the original icon")

	UnitClass, C_Spell.IsSpellUsable, MultiCastRecallSpellButton = savedClass, savedUsable, savedButton
	issecretvalue, db.totemRecallColors = savedSecret, savedColors
	visuals:OnOptionChanged("totemRecallColors")
	print("totem recall binding and action colors OK")
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	local setup = assert(uv(visuals.OnLogin, "SetupTotemBindings"))
	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local updateBindings = eventFrame:GetScript("OnEvent")
	local savedFrame, savedRegistry, savedMixin = CreateFrame, EventRegistry, QuickKeybindButtonTemplateMixin
	local savedQuickKeybindFrame = QuickKeybindFrame
	local savedRecallSpells, savedSummonSpells = TOTEM_MULTI_CAST_RECALL_SPELLS, TOTEM_MULTI_CAST_SUMMON_SPELLS
	local savedRecall, savedSummon, savedKey = MultiCastRecallSpellButton, MultiCastSummonSpellButton, GetBindingKey
	local savedClear, savedOverride = ClearOverrideBindings, SetOverrideBindingClick
	local recallCastName, summonCastName = "ForeverPlusTotemRecallCastButton", "ForeverPlusTotemSummonCastButton"
	local recallCommand = "CLICK MultiCastRecallSpellButton:LeftButton"
	local summonCommand = "CLICK MultiCastSummonSpellButton:LeftButton"
	local recall, summon = NewFrame("CheckButton"), NewFrame("CheckButton")
	local currentPage = 1
	local modeShown, summonHover, nativeEnters = false, false, 0
	summon.GetID = function() return currentPage end
	summon.IsMouseMotionFocus = function() return summonHover end
	summon:SetScript("OnEnter", function() nativeEnters = nativeEnters + 1 end)
	MultiCastRecallSpellButton, MultiCastSummonSpellButton = recall, summon
	local events, overrides, casts, selectors = {}, {}, {}, {}
	local keys = { [recallCommand] = { "SHIFT-R", "CTRL-R" }, [summonCommand] = { "SHIFT-T" } }
	TOTEM_MULTI_CAST_RECALL_SPELLS = { 36936 }
	TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 }
	EventRegistry = { RegisterCallback = function(_, event, fn, owner)
		events[event] = events[event] or {}
		events[event][owner] = fn
	end }
	local function Fire(event)
		for owner, callback in pairs(events[event]) do callback(owner) end
	end
	QuickKeybindButtonTemplateMixin = {}
	QuickKeybindFrame = {
		SetSelected = function(self, command, selector)
			self.command, self.mouseOverButton = command, selector
		end,
	}
	CreateFrame = function(kind, name, parent, template)
		local frame = savedFrame(kind, name, parent, template)
		local attributes = {}
		local frameRefs = {}
		frame.SetAttribute = function(_, key, value) attributes[key] = value end
		frame.GetAttribute = function(_, key) return attributes[key] end
		frame.SetFrameRef = function(_, key, value) frameRefs[key] = value end
		frame.GetFrameRef = function(_, key) return frameRefs[key] end
		frame.WrapScript = function(self, target, script, body)
			assert(template == "SecureActionButtonTemplate, SecureHandlerBaseTemplate", "page switching is secure")
			assert(target == self and script == "PreClick", "select the spell before casting")
			self.preClick = setfenv(assert(loadstring(body)), { self = target })
		end
		frame.RegisterForClicks = function(self, ...) self.clicks = table.concat({ ... }, ",") end
		frame.SetAllPoints = function(self, target) self.anchor = target end
		if template == "QuickKeybindButtonTemplate" then
			selectors[parent] = frame
			frame.DoModeChange = function(self, enabled) self.highlighted = enabled end
			frame.SetMouseMotionEnabled = function(self, enabled) self.mouseMotion = enabled end
			frame.SetMouseClickEnabled = function(self, enabled) self.mouseClick = enabled end
			frame.Show = function(self)
				self.shown = true
				local script = self:GetScript("OnShow")
				if script then script(self) end
			end
			frame.Hide = function(self)
				self.shown = false
				local script = self:GetScript("OnHide")
				if script then script(self) end
			end
			frame.QuickKeybindButtonOnEnter = function(self)
				assert(modeShown, "ordinary native hover does not enter quick binding")
				QuickKeybindFrame:SetSelected(self.commandName, self)
			end
			frame.QuickKeybindButtonOnLeave = function()
				if modeShown then QuickKeybindFrame:SetSelected(nil, nil) end
			end
		else
			casts[name] = frame
		end
		return frame
	end
	GetBindingKey = function(action)
		local bound = assert(keys[action], "each button uses its own saved command")
		return unpack(bound)
	end
	ClearOverrideBindings = function(owner)
		overrides[owner] = {}
	end
	SetOverrideBindingClick = function(owner, priority, key, name, mouseButton)
		assert(owner == casts[name] and not priority and mouseButton == "LeftButton", "ordinary binding priority")
		overrides[owner][key] = name
	end
	setup()
	local recallCast, summonCast = casts[recallCastName], casts[summonCastName]
	assert(recallCast:GetAttribute("type") == "spell" and recallCast:GetAttribute("spell") == 36936, "secure recall is unchanged")
	assert(summonCast:GetAttribute("type") == "spell", "the totem page casts a spell")
	assert(recallCast.clicks == "AnyUp,AnyDown" and summonCast.clicks == recallCast.clicks,
		"both buttons support the game's key press or release setting")
	for page, spellID in ipairs(TOTEM_MULTI_CAST_SUMMON_SPELLS) do
		currentPage = page
		summonCast.preClick()
		assert(summonCast:GetAttribute("spell") == spellID, "secure summon follows the native page at click time")
	end
	currentPage = 4
	summonCast.preClick()
	assert(summonCast:GetAttribute("spell") == nil, "an unknown page cannot reuse the previous summon spell")
	assert(overrides[recallCast]["SHIFT-R"] == recallCastName and overrides[recallCast]["CTRL-R"] == recallCastName,
		"both recall keys use the secure cast")
	assert(overrides[summonCast]["SHIFT-T"] == summonCastName, "summon has an independent binding")
	assert(selectors[recall].commandName == recallCommand and selectors[summon].commandName == summonCommand,
		"quick binding selects the correct saved command")
	for button, selector in pairs(selectors) do
		assert(selector.anchor == button and not selector:IsShown(), "each selector starts hidden over its native button")
	end
	assert(selectors[summon].mouseMotion == false and selectors[summon].mouseClick == true,
		"the selector leaves mouse motion to summon and catches clicks during quick binding")
	summon:GetScript("OnEnter")(summon, true)
	assert(nativeEnters == 1 and not QuickKeybindFrame.mouseOverButton, "native hover outside quick binding stays intact")
	modeShown, summonHover = true, true
	Fire("QuickKeybindFrame.QuickKeybindModeEnabled")
	assert(selectors[recall]:IsShown() and selectors[summon]:IsShown() and selectors[summon].highlighted,
		"quick binding shows both selectors")
	assert(QuickKeybindFrame.command == summonCommand, "opening while already over the native button selects summon")
	summon:GetScript("OnLeave")(summon, true)
	assert(not QuickKeybindFrame.mouseOverButton, "leaving the native button clears the selection")
	summon:GetScript("OnEnter")(summon, true)
	assert(nativeEnters == 2 and QuickKeybindFrame.mouseOverButton == selectors[summon],
		"the live hover script selects the shortcut while preserving native hover")
	keys[recallCommand], keys[summonCommand] = { "ALT-R" }, { "ALT-T" }
	updateBindings(eventFrame, "UPDATE_BINDINGS")
	assert(overrides[recallCast]["ALT-R"] == recallCastName and not overrides[recallCast]["SHIFT-R"]
		and not overrides[recallCast]["CTRL-R"], "rebinding recall replaces both old keys")
	assert(overrides[summonCast]["ALT-T"] == summonCastName and not overrides[summonCast]["SHIFT-T"],
		"rebinding summon replaces its old key")
	keys[summonCommand] = {}
	updateBindings(eventFrame, "UPDATE_BINDINGS")
	assert(not next(overrides[summonCast]) and overrides[recallCast]["ALT-R"] == recallCastName,
		"clearing summon leaves the recall shortcut intact")
	modeShown = false
	Fire("QuickKeybindFrame.QuickKeybindModeDisabled")
	assert(not selectors[recall]:IsShown() and not selectors[summon]:IsShown(),
		"closing quick binding returns mouse input to the native buttons")
	assert(not QuickKeybindFrame.mouseOverButton, "closing quick binding clears the summon key listener")
	visuals:UnregisterEvent("UPDATE_BINDINGS")
	_G[recallCastName], _G[summonCastName] = nil, nil
	CreateFrame, EventRegistry, QuickKeybindButtonTemplateMixin = savedFrame, savedRegistry, savedMixin
	QuickKeybindFrame = savedQuickKeybindFrame
	TOTEM_MULTI_CAST_RECALL_SPELLS, TOTEM_MULTI_CAST_SUMMON_SPELLS = savedRecallSpells, savedSummonSpells
	MultiCastRecallSpellButton, MultiCastSummonSpellButton, GetBindingKey = savedRecall, savedSummon, savedKey
	ClearOverrideBindings, SetOverrideBindingClick = savedClear, savedOverride
	print("totem summon and recall quick keybind, secure cast and page switching OK")
end)()

;(function()
	local visuals = ns:GetModule("Visuals")
	assert(visuals.defaults.totemTimers == true, "totem timers default on")
	local foundOption
	for _, opt in ipairs(visuals.options) do
		if opt.key == "totemTimers" then
			foundOption = opt
			break
		end
	end
	assert(foundOption and foundOption.new == true, "totem timers option carries the NEW mark")

	local saved = {
		UnitClass = UnitClass,
		CreateFrame = CreateFrame,
		hooksecurefunc = hooksecurefunc,
		GetTotemInfo = GetTotemInfo,
		GetTotemDuration = GetTotemDuration,
		GetTime = GetTime,
		issecretvalue = issecretvalue,
		NUM_MULTI_CAST_BUTTONS_PER_PAGE = NUM_MULTI_CAST_BUTTONS_PER_PAGE,
		MultiCastActionBarFrame_Update = MultiCastActionBarFrame_Update,
		ChangeMultiCastActionPage = ChangeMultiCastActionPage,
		Enum = Enum,
		option = visuals.db.totemTimers,
	}
	local savedSlots = {}
	for i = 1, 4 do
		savedSlots[i] = rawget(_G, "MultiCastSlotButton" .. i)
	end

	local currentClass = "SHAMAN"
	UnitClass = function() return "Shaman", currentClass end
	NUM_MULTI_CAST_BUTTONS_PER_PAGE = 4
	GetTime = function() return 1000 end
	Enum = setmetatable({
		StatusBarInterpolation = { Immediate = 0 },
		StatusBarTimerDirection = { RemainingTime = 1 },
	}, { __index = saved.Enum })
	hooksecurefunc = function(a, b, c)
		saved.hooksecurefunc(a, b, c)
		if type(a) == "string" and type(_G[a]) == "function" then
			local orig = _G[a]
			_G[a] = function(...)
				local r = orig(...)
				b(...)
				return r
			end
		end
	end

	local created = {}
	CreateFrame = function(kind, name, parent, template)
		local f = saved.CreateFrame(kind, name, parent, template)
		f.kind = kind
		f.parent = parent
		f.level = 1
		f.GetParent = function(self) return rawget(self, "parent") end
		f.SetFrameLevel = function(self, lvl) self.level = lvl end
		f.GetFrameLevel = function(self) return self.level end
		if kind == "StatusBar" then
			f.SetStatusBarTexture = function(self, tex) self.texture = tex end
			f.SetStatusBarColor = function(self, r, g, b) self.color = { r, g, b } end
			f.SetTimerDuration = function(self, dur, interp, dir) self.timerDur, self.timerInterp, self.timerDir = dur, interp, dir end
			f.SetMinMaxValues = function(self, lo, hi) self.minVal, self.maxVal = lo, hi end
			f.SetValue = function(self, v) self.val = v end
		elseif kind == "Cooldown" then
			local fs = NewFrame("FontString")
			fs.SetPoint = function(self, ...) self.anchor = { ... } end
			fs.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
			f.countdownFS = fs
			f.GetCountdownFontString = function(self) return self.countdownFS end
			f.SetDrawSwipe = function(self, v) self.drawSwipe = v end
			f.SetDrawEdge = function(self, v) self.drawEdge = v end
			f.SetDrawBling = function(self, v) self.drawBling = v end
			f.SetHideCountdownNumbers = function(self, v) self.hideNumbers = v end
			f.SetMinimumCountdownDuration = function(self, v) self.minDuration = v end
			f.SetCountdownAbbrevThreshold = function(self, v) self.abbrevThreshold = v end
			f.SetCountdownFont = function(self, v) self.countdownFont = v end
			f.SetCooldownFromDurationObject = function(self, dur, clearIfZero)
				self.durObj, self.clearIfZero, self.cleared = dur, clearIfZero, false
			end
			f.SetCooldown = function(self, s, d, m)
				self.start, self.duration, self.modRate, self.cleared = s, d, m, false
			end
			f.Clear = function(self)
				self.durObj, self.start, self.duration, self.cleared = nil, nil, nil, true
			end
		end
		created[#created + 1] = f
		return f
	end

	local slots = {}
	local slotIDs = { 1, 2, 3, 0 }
	for i = 1, 4 do
		local btn = NewFrame("CheckButton")
		btn.slotID = slotIDs[i]
		btn.GetID = function(self) return self.slotID end
		btn.GetFrameLevel = function() return 10 end
		btn.actionButton = { GetFrameLevel = function() return 14 end }
		btn.SetFrameLevel = function(self, lvl) self.level = lvl end
		_G["MultiCastSlotButton" .. i] = btn
		slots[i] = btn
	end
	local origOverlayFrameLevel
	local function FindOverlay(slotButton)
		for _, f in ipairs(created) do
			if f.kind == "Frame" and f:GetParent() == slotButton and f.cooldown and f.bar then
				return f
			end
		end
	end

	local totemInfo = {
		[1] = { true, "Searing Totem", 980, 60, 123, 1 },
		[2] = { false, "", 0, 0, 0, 1 },
		[3] = { true, "Healing Stream Totem", 990, 120, 456, 1 },
	}
	local durObjs = {
		[1] = { id = "fire-dur" },
		[2] = { id = "earth-zero" },
		[3] = { id = "water-dur" },
	}
	GetTotemInfo = function(slot)
		local info = totemInfo[slot]
		if info then return unpack(info, 1, 6) end
		return false, "", 0, 0, 0, 1
	end
	GetTotemDuration = function(slot) return durObjs[slot] end
	MultiCastActionBarFrame_Update = function() end
	ChangeMultiCastActionPage = function() end

	visuals.db.totemTimers = true
	visuals:OnOptionChanged("totemTimers")

	local fireOv = assert(FindOverlay(slots[1]), "fire totem overlay created")
	local waterOv = assert(FindOverlay(slots[3]), "water totem overlay created")
	assert(fireOv:IsShown() and waterOv:IsShown(), "active totem slots show overlays")
	assert(not FindOverlay(slots[2]) and not FindOverlay(slots[4]), "inactive or hidden slots stay empty")
	assert(fireOv.cooldown.durObj == durObjs[1] and fireOv.cooldown.clearIfZero == true, "duration object passed to cooldown")
	assert(fireOv.cooldown.drawSwipe == false and fireOv.cooldown.hideNumbers == false, "countdown shown without swipe")
	assert(fireOv.cooldown.abbrevThreshold == 600 and fireOv.cooldown.minDuration == 0, "mm:ss threshold and 0s min configured")
	assert(fireOv.cooldown.countdownFS.anchor and fireOv.cooldown.countdownFS.anchor[1] == "BOTTOM", "countdown anchored at bottom")
	assert(fireOv.bar:IsShown() and fireOv.bar.timerDur == durObjs[1] and fireOv.bar.timerDir == 1, "progress bar driven by duration object")
	assert(fireOv.bar.color[1] > 0.9 and waterOv.bar.color[3] > 0.9, "element colours distinguish fire and water")
	origOverlayFrameLevel = fireOv:GetFrameLevel()
	assert(origOverlayFrameLevel == 18, "overlay sits above the action button and its spell cooldown")

	-- Secret values in combat: GetTotemInfo returns secret booleans/numbers; GetTotemDuration drives the widgets safely.
	local secretVal = {}
	issecretvalue = function(v) return v == secretVal end
	totemInfo[2] = { secretVal, secretVal, secretVal, secretVal, secretVal, 1 }
	MultiCastActionBarFrame_Update()
	local earthOv = assert(FindOverlay(slots[2]), "secret totem slot still updates via duration object")
	assert(earthOv:IsShown() and earthOv.cooldown.durObj == durObjs[2] and earthOv.bar.timerDur == durObjs[2],
		"secret totem uses SetCooldownFromDurationObject and SetTimerDuration without Lua comparison")

	-- Expiring / recalling a totem hides and clears the overlay on PLAYER_TOTEM_UPDATE.
	issecretvalue = saved.issecretvalue
	totemInfo[1] = { false, "", 0, 0, 0, 1 }
	totemInfo[2] = { false, "", 0, 0, 0, 1 }
	ChangeMultiCastActionPage(2)
	assert(not fireOv:IsShown() and fireOv.cooldown.cleared and not fireOv.bar:IsShown(), "expired fire totem cleared")
	assert(not earthOv:IsShown() and earthOv.cooldown.cleared, "cleared earth totem hidden")

	-- Fallback path when GetTotemDuration is absent, triggered via PLAYER_TOTEM_UPDATE event.
	local watchFrame
	for _, f in ipairs(created) do
		if f.kind == "Frame" and rawget(f, "parent") == nil and f:GetScript("OnEvent") then
			watchFrame = f
			break
		end
	end
	assert(watchFrame, "totem watcher frame created")
	GetTotemDuration = nil
	totemInfo[1] = { true, "Searing Totem", 980, 60, 123, 1 }
	watchFrame:GetScript("OnEvent")(watchFrame, "PLAYER_TOTEM_UPDATE", 1)
	assert(fireOv:IsShown() and fireOv.cooldown.start == 980 and fireOv.cooldown.duration == 60, "fallback uses SetCooldown")
	assert(fireOv.bar:IsShown() and fireOv.bar.maxVal == 60 and fireOv.bar.val == 40, "fallback sets status bar remaining time")

	-- Disabling the option clears all overlays.
	visuals.db.totemTimers = false
	visuals:OnOptionChanged("totemTimers")
	assert(not fireOv:IsShown() and fireOv.cooldown.cleared and not waterOv:IsShown(), "turning option off hides all totem overlays")

	-- Non-shaman class stays inactive even when option is enabled.
	currentClass = "WARRIOR"
	visuals.db.totemTimers = true
	visuals:OnOptionChanged("totemTimers")
	assert(not fireOv:IsShown() and not waterOv:IsShown(), "non-shaman does not show totem overlays")

	-- Restore globals and option state.
	for i = 1, 4 do
		_G["MultiCastSlotButton" .. i] = savedSlots[i]
	end
	UnitClass = saved.UnitClass
	CreateFrame = saved.CreateFrame
	hooksecurefunc = saved.hooksecurefunc
	GetTotemInfo = saved.GetTotemInfo
	GetTotemDuration = saved.GetTotemDuration
	GetTime = saved.GetTime
	issecretvalue = saved.issecretvalue
	NUM_MULTI_CAST_BUTTONS_PER_PAGE = saved.NUM_MULTI_CAST_BUTTONS_PER_PAGE
	MultiCastActionBarFrame_Update = saved.MultiCastActionBarFrame_Update
	ChangeMultiCastActionPage = saved.ChangeMultiCastActionPage
	Enum = saved.Enum
	visuals.db.totemTimers = saved.option
	visuals:OnOptionChanged("totemTimers")
end)()
;(function()
	-- Persistent account-wide ignore list in Chat: save, restore after restart, explicit removal, chat filter and editor
	local chat = ns:GetModule("Chat")
	local saved = {
		C_FriendList = C_FriendList,
		GetNormalizedRealmName = GetNormalizedRealmName,
		GetRealmName = GetRealmName,
		RegionalUniqueNamesEnabled = RegionalUniqueNamesEnabled,
		UnitFullName = UnitFullName,
		GetTime = GetTime,
		hooksecurefunc = hooksecurefunc,
		issecretvalue = issecretvalue,
		ShowEditWindow = ns.ShowEditWindow,
		ERR_IGNORE_ADDED_S = ERR_IGNORE_ADDED_S,
		ERR_IGNORE_ALREADY_S = ERR_IGNORE_ALREADY_S,
		ERR_IGNORE_NOT_FOUND = ERR_IGNORE_NOT_FOUND,
		ERR_IGNORE_SELF = ERR_IGNORE_SELF,
		keepIgnore = chat.db.keepIgnore,
		ignoredPlayers = ns.db.ignoredPlayers,
	}

	local now = 100
	GetTime = function() return now end
	GetNormalizedRealmName = function() return "Everlook" end
	GetRealmName = function() return "Everlook" end
	local regional = false
	RegionalUniqueNamesEnabled = function() return regional end
	UnitFullName = function() return "OwnHero", "Everlook" end
	local secretVal = {}
	issecretvalue = function(v) return v == secretVal end
	ERR_IGNORE_ADDED_S = "%s is now being ignored."
	ERR_IGNORE_ALREADY_S = "%s is already being ignored."
	ERR_IGNORE_NOT_FOUND = "Player not found."
	ERR_IGNORE_SELF = "You can't ignore yourself."

	hooksecurefunc = function(object, method, hook)
		local original = object[method]
		object[method] = function(...)
			local r1, r2 = original(...)
			hook(...)
			return r1, r2
		end
	end

	-- Name normalisation: own realm stripped, foreign realm kept, Forever internal realm stripped.
	assert(chat.IgnoreCanonical("Spammer-Everlook") == "Spammer", "own realm stripped")
	assert(chat.IgnoreCanonical("Troll-OtherRealm") == "Troll-OtherRealm", "foreign realm kept")
	assert(chat.IgnoreCanonical(secretVal) == nil, "secret value ignored")
	regional = true
	assert(chat.IgnoreCanonical("Bob Smith-CAMWOWEU5Realm10RP") == "Bob Smith", "Forever regional name keeps surname and strips internal realm")
	regional = false

	local serverList = { "Spammer-Everlook", "Troll-OtherRealm" }
	local addedCalls, deletedCalls = {}, {}
	C_FriendList = {
		GetNumIgnores = function() return #serverList end,
		GetIgnoreName = function(i) return serverList[i] end,
		AddIgnore = function(name)
			addedCalls[#addedCalls + 1] = name
			return true
		end,
		DelIgnore = function(name)
			deletedCalls[#deletedCalls + 1] = name
			return true
		end,
		DelIgnoreByIndex = function(index)
			local name = serverList[index]
			if name then
				deletedCalls[#deletedCalls + 1] = name
			end
			return true
		end,
		AddOrDelIgnore = function() return true end,
	}

	ns.db.ignoredPlayers = {}
	chat.db.keepIgnore = true
	chat.ResetIgnoreSession()
	chat:UpdateIgnoreList(true)
	assert(ns.db.ignoredPlayers["spammer"] == "Spammer", "server ignore saved")
	assert(ns.db.ignoredPlayers["troll-otherrealm"] == "Troll-OtherRealm", "cross-realm server ignore saved")
	assert(#addedCalls == 0, "already present entries not re-added")

	-- Simulate restart: server returns empty list, saved entries (except own character) are restored once.
	ns.db.ignoredPlayers["ownhero"] = "OwnHero"
	ns.db.ignoredPlayers["offlineguy"] = "OfflineGuy"
	serverList = {}
	addedCalls = {}
	chat.ResetIgnoreSession()
	chat.SyncIgnoreList(true)
	assert(#addedCalls == 3, "three missing entries restored (own character skipped)")
	assert(addedCalls[1] == "OfflineGuy" and addedCalls[2] == "Spammer" and addedCalls[3] == "Troll-OtherRealm", "restored in deterministic order")

	-- Restore system messages suppressed during window, normal system messages allowed, after window allowed again.
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Spammer is now being ignored.") == true, "restore added message suppressed")
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Player not found.") == true, "restore not-found message suppressed")
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "You have gained a level.") == false, "unrelated system message kept")
	now = 105
	assert(chat.IgnoreSystemFilter(nil, "CHAT_MSG_SYSTEM", "Spammer is now being ignored.") == false, "system messages allowed after window")

	-- Second sync in same session does not loop AddIgnore for names still missing on server.
	addedCalls = {}
	chat.SyncIgnoreList(true)
	assert(#addedCalls == 0, "no repeated AddIgnore attempts in the same session")

	-- Chat filter blocks saved names (even while missing on server) and tolerates secret senders.
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_WHISPER", "hi", "OfflineGuy-Everlook") == true, "chat filter blocks saved name")
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", "Friendly-Everlook") == false, "chat filter allows non-ignored sender")
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", secretVal) == false, "chat filter skips secret sender")

	-- Explicit removals via DelIgnore, DelIgnoreByIndex and AddOrDelIgnore remove from backup too.
	serverList = { "Spammer", "Troll-OtherRealm", "OfflineGuy" }
	chat.SyncIgnoreList(false)
	C_FriendList.DelIgnore("Spammer")
	assert(ns.db.ignoredPlayers["spammer"] == nil, "DelIgnore removes entry from backup")
	-- Stale IGNORELIST_UPDATE right after removal must not re-add the removed name.
	chat.SyncIgnoreList(false)
	assert(ns.db.ignoredPlayers["spammer"] == nil, "stale update within grace window does not re-add removed name")
	-- Explicit re-add clears the removal guard so the next server sync records it again.
	C_FriendList.AddIgnore("Spammer")
	chat.SyncIgnoreList(false)
	assert(ns.db.ignoredPlayers["spammer"] == "Spammer", "explicit re-add clears guard and saves again")

	C_FriendList.DelIgnoreByIndex(2)
	assert(ns.db.ignoredPlayers["troll-otherrealm"] == nil, "DelIgnoreByIndex removes indexed entry from backup")
	C_FriendList.AddOrDelIgnore("OfflineGuy")
	assert(ns.db.ignoredPlayers["offlineguy"] == nil, "AddOrDelIgnore on ignored player removes entry from backup")

	-- Editor window: shows sorted list, removes deleted names from server+backup and adds new ones.
	serverList = { "Spammer" }
	chat.SyncIgnoreList(false)
	deletedCalls, addedCalls = {}, {}
	local editInitial, editAccept
	ns.ShowEditWindow = function(_, _, initial, _, accept)
		editInitial, editAccept = initial, accept
	end
	chat:EditIgnoreList()
	assert(editInitial:find("Spammer", 1, true), "editor prefilled with saved names")
	editAccept("NewBaddie\nOtherBaddie-RealmTwo")
	assert(ns.db.ignoredPlayers["spammer"] == nil and ns.db.ignoredPlayers["newbaddie"] == "NewBaddie"
		and ns.db.ignoredPlayers["otherbaddie-realmtwo"] == "OtherBaddie-RealmTwo", "editor updates saved list")
	assert(deletedCalls[1] == "Spammer", "editor removes deleted server ignore")
	assert(#addedCalls == 2, "editor adds newly typed ignores to server")

	-- Turning option off disables chat filter without wiping saved names.
	chat.db.keepIgnore = false
	chat:OnOptionChanged("keepIgnore", false)
	assert(chat.IgnoreChatFilter(nil, "CHAT_MSG_SAY", "hi", "NewBaddie") == false, "chat filter inactive when option is off")
	assert(ns.db.ignoredPlayers["newbaddie"] == "NewBaddie", "saved list kept when option is toggled off")

	-- Restore environment.
	chat.ResetIgnoreSession()
	C_FriendList = saved.C_FriendList
	GetNormalizedRealmName = saved.GetNormalizedRealmName
	GetRealmName = saved.GetRealmName
	RegionalUniqueNamesEnabled = saved.RegionalUniqueNamesEnabled
	UnitFullName = saved.UnitFullName
	GetTime = saved.GetTime
	hooksecurefunc = saved.hooksecurefunc
	issecretvalue = saved.issecretvalue
	ns.ShowEditWindow = saved.ShowEditWindow
	ERR_IGNORE_ADDED_S = saved.ERR_IGNORE_ADDED_S
	ERR_IGNORE_ALREADY_S = saved.ERR_IGNORE_ALREADY_S
	ERR_IGNORE_NOT_FOUND = saved.ERR_IGNORE_NOT_FOUND
	ERR_IGNORE_SELF = saved.ERR_IGNORE_SELF
	chat.db.keepIgnore = saved.keepIgnore
	ns.db.ignoredPlayers = saved.ignoredPlayers
	chat:UpdateIgnoreList(false)
	print("chat ignore list OK")
end)()
;(function()
	-- Performance regression tests: Camera CVar throttling/staggering, Helpers coalescing/quest-item gating,
	-- BankView incremental bag scans, and Quests prefix/suffix preservation + instance-quest cache.
	local camera = ns:GetModule("Camera")
	local saved = {
		GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, GetTime, ns.NewTicker,
		camera.State, camera.db.saved, camera.db.enabled,
	}
	local cvars = {
		CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0", test_cameraDynamicPitch = "0",
		test_cameraOverShoulder = "1", test_cameraDynamicPitchBaseFovPad = "0.3",
		cameraDistanceMaxZoomFactor = "2", cameraYawMoveSpeed = "180",
	}
	local setCalls, now, state, zoom = 0, 100, {}, 10
	GetCVar = function(k) return cvars[k] end
	SetCVar = function(k, v) setCalls = setCalls + 1; cvars[k] = tostring(v) end
	GetCameraZoom = function() return zoom end
	CameraZoomOut = function(d) zoom = zoom + d end
	CameraZoomIn = function(d) zoom = zoom - d end
	GetTime = function() return now end
	ns.NewTicker = function() return { Cancel = function() end } end
	camera.State = function() return state end
	camera.db.saved, camera.db.enabled = {}, true
	camera:OnOptionChanged("enabled", true)
	local blender = uv(uv(camera.Apply, "BlendTo"), "blender")
	local function Go(nextState)
		state = nextState
		camera.Update()
		now = now + 0.7
		camera.Update()
	end
	-- Start settled outdoors (shoulder=1, pad=0.3); indoors keeps shoulder=1, pad=0.3 -> 0 SetCVar calls during zoom blend.
	Go({})
	setCalls = 0
	Go({ indoors = true })
	for _ = 1, 10 do
		now = now + 0.1
		if blender and blender.scripts.OnUpdate then blender.scripts.OnUpdate(blender, 0.1) end
	end
	assert(setCalls == 0, "camera blend with unchanged shoulder/pad never calls SetCVar: " .. setCalls)

	-- Switch to combat (both shoulder 1->0.6 and pad 0.3->0.35 change): throttled (<0.05s = 0 calls) and staggered (<=1 per tick).
	Go({ combat = true })
	blender = uv(uv(camera.Apply, "BlendTo"), "blender")
	setCalls = 0
	for _ = 1, 5 do
		now = now + 0.008
		blender.scripts.OnUpdate(blender, 0.008)
	end
	assert(setCalls == 0, "camera blend skips SetCVar inside the 50 ms throttle window")
	now = now + 0.5
	setCalls = 0
	blender.scripts.OnUpdate(blender, 0.5)
	assert(setCalls <= 1, "camera blend staggers shoulder and pad to at most one SetCVar per intermediate frame: " .. setCalls)
	now = now + 3
	blender.scripts.OnUpdate(blender, 3)
	assert(cvars.test_cameraOverShoulder == "0.6" and cvars.test_cameraDynamicPitchBaseFovPad == "0.35",
		"camera blend still lands on exact targets at completion")
	camera.db.enabled = false
	camera:OnOptionChanged("enabled", false)
	GetCVar, SetCVar, GetCameraZoom, CameraZoomIn, CameraZoomOut, GetTime, ns.NewTicker = unpack(saved, 1, 7)
	camera.State, camera.db.saved, camera.db.enabled = saved[8], saved[9], saved[10]

	-- Helpers: QUEST_LOG_UPDATE skips scanning bags when bags contain no quest-starting item; bursts coalesce.
	local helpers = ns:GetModule("Helpers")
	local savedAfter, savedSlots, savedItem, savedQuestInfo = C_Timer.After, C_Container.GetContainerNumSlots,
		C_Container.GetContainerItemInfo, C_Container.GetContainerItemQuestInfo
	local savedOpenOpt = helpers.db.openButton
	local deferred, slotScans = {}, 0
	C_Timer.After = function(_, fn) deferred[#deferred + 1] = fn end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(_, slot)
		slotScans = slotScans + 1
		return slot == 1 and { itemID = 10, hasLoot = false, isLocked = false } or nil
	end
	C_Container.GetContainerItemQuestInfo = function() return nil end
	helpers.db.openButton = true
	local listeners = uv(ns.RegisterEvent, "listeners")
	local onBag = listeners.BAG_UPDATE_DELAYED[helpers]
	local onQuest = listeners.QUEST_LOG_UPDATE[helpers]
	onBag(helpers, "BAG_UPDATE_DELAYED")
	onQuest(helpers, "QUEST_LOG_UPDATE")
	assert(#deferred == 1 and slotScans == 0, "BAG_UPDATE_DELAYED + QUEST_LOG_UPDATE coalesce into one deferred scan")
	deferred[1]()
	assert(slotScans == 2, "coalesced scan runs once")
	deferred, slotScans = {}, 0
	onQuest(helpers, "QUEST_LOG_UPDATE")
	assert(#deferred == 0 and slotScans == 0, "QUEST_LOG_UPDATE skips bag scan when bags have no quest item")
	helpers.db.openButton = savedOpenOpt
	C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo,
		C_Container.GetContainerItemQuestInfo = savedAfter, savedSlots, savedItem, savedQuestInfo

	-- BankView: BAG_UPDATE(1) + BAG_UPDATE_DELAYED scans only bag 1 on the deferred tick, not all bags or gear.
	local bankView = ns:GetModule("BankView")
	local bvSaved = { C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, GetInventoryItemID }
	local scannedBags, gearScans, bvDeferred = {}, 0, {}
	C_Timer.After = function(_, fn) bvDeferred[#bvDeferred + 1] = fn end
	C_Container.GetContainerNumSlots = function(bag)
		scannedBags[bag] = (scannedBags[bag] or 0) + 1
		return 1
	end
	C_Container.GetContainerItemInfo = function(bag, slot)
		if bag == 1 and slot == 1 then return { itemID = 4242, stackCount = 7 } end
	end
	GetInventoryItemID = function() gearScans = gearScans + 1 return nil end
	listeners.BAG_UPDATE[bankView](bankView, "BAG_UPDATE", 1)
	listeners.BAG_UPDATE_DELAYED[bankView](bankView, "BAG_UPDATE_DELAYED")
	assert(#bvDeferred == 1 and not next(scannedBags), "BankView defers owned-count scan off BAG_UPDATE_DELAYED")
	bvDeferred[1]()
	assert(scannedBags[1] == 1 and not scannedBags[0] and not scannedBags[2] and gearScans == 0,
		"BankView only rescans the dirty bag and skips unchanged bags and gear")
	C_Timer.After, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo,
		GetInventoryItemID = unpack(bvSaved, 1, 4)

	-- Quests: WriteWatches preserves unchanged suffix/prefix after order verification.
	local quests = ns:GetModule("Quests")
	local qSort = uv(uv(quests.UpdateTrackerSort, "QueueSort"), "SortTracker")
	local writeWatches = uv(qSort, "WriteWatches")
	local qSaved = { C_QuestLog.RemoveQuestWatch, C_QuestLog.AddQuestWatch, C_SuperTrack.GetSuperTrackedQuestID }
	local removed, added = 0, 0
	C_QuestLog.RemoveQuestWatch = function() removed = removed + 1 end
	C_QuestLog.AddQuestWatch = function() added = added + 1 end
	C_SuperTrack.GetSuperTrackedQuestID = function() return 0 end
	local savedAddsOnTop = uv(writeWatches, "addsOnTop")
	local savedVerified = uv(writeWatches, "orderVerified")
	setuv(writeWatches, "addsOnTop", false)
	setuv(writeWatches, "orderVerified", true)
	writeWatches({ 11, 12, 13 }, { 11, 12, 13, 14 })
	assert(removed == 0 and added == 1, "WriteWatches keeps matching prefix and only adds the new bottom watch")
	removed, added = 0, 0
	setuv(writeWatches, "addsOnTop", true)
	writeWatches({ 11, 12, 13 }, { 14, 11, 12, 13 })
	assert(removed == 0 and added == 1, "WriteWatches keeps matching suffix when new watches land on top")
	setuv(writeWatches, "addsOnTop", savedAddsOnTop)
	setuv(writeWatches, "orderVerified", savedVerified)
	C_QuestLog.RemoveQuestWatch, C_QuestLog.AddQuestWatch, C_SuperTrack.GetSuperTrackedQuestID = unpack(qSaved, 1, 3)

	print("performance spike fixes OK")
end)()
;(function()
	-- Item rating: passive stat conversions and percentage stat multipliers scale with the character's learned talent ranks.
	local items = ns:GetModule("Items")
	local getW = ns.StatWeights
	local weightsTable = upvalue(getW, "WEIGHTS")
	local bearBase = upvalue(getW, "FERAL_BEAR")
	local function near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-4 end

	-- Warrior and Rogue have no passive stat-conversion or percentage stat-multiplier talents.
	for _, cls in ipairs({ "WARRIOR", "ROGUE" }) do
		for p = 1, 3 do
			assert(items.AdjustWeights(weightsTable[cls][p], cls, p, {}) == weightsTable[cls][p], cls .. " unchanged")
		end
	end

	-- Shaman: Mental Dexterity (415140), Mental Quickness (30812), Ancestral Knowledge (17485), Toughness (16252), Improved Reincarnation (16184).
	local enh = weightsTable.SHAMAN[2]
	assert(items.AdjustWeights(enh, "SHAMAN", 2, { [17485] = 3, [415140] = 3, [30812] = 2 }) == enh, "Enhancement reference identity")
	local enh0 = items.AdjustWeights(enh, "SHAMAN", 2, {})
	local enh1 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 1 })
	local enh2 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 2 })
	local enh3 = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 3 })
	local enh3mq = items.AdjustWeights(enh, "SHAMAN", 2, { [415140] = 3, [30812] = 2 })
	local enhMax = items.AdjustWeights(enh, "SHAMAN", 2, { [17485] = 5, [415140] = 3, [30812] = 2, [16252] = 5, [16184] = 2 })
	assert(near(enh0.INT, 0.25) and enh0.INT < enh1.INT and enh1.INT < enh2.INT and enh2.INT < enh3.INT
		and enh3.INT < enh3mq.INT and enh3mq.INT < enh.INT and enh.INT < enhMax.INT, "Enhancement INT scales cleanly per rank")
	assert(near(enhMax.STA, enh.STA * 1.10 * 1.04), "Shaman Toughness and Improved Reincarnation stack on STA")
	local restoMQ = items.AdjustWeights(weightsTable.SHAMAN[3], "SHAMAN", 3, { [17485] = 5, [30812] = 2, [415140] = 3 })
	assert(near(restoMQ.INT, weightsTable.SHAMAN[3].INT + 1.10 * 0.30 * weightsTable.SHAMAN[3].HEAL),
		"Restoration Shaman gains Mental Quickness healing conversion, ignores Mental Dexterity AP")

	-- Paladin: Champion of the Light (1311084), Divine Intellect (20257), Divine Strength (20262), Toughness (20143), Shield Specialization (20150).
	local ret = weightsTable.PALADIN[3]
	assert(items.AdjustWeights(ret, "PALADIN", 3, { [20262] = 5, [20257] = 5, [1311084] = 5 }) == ret, "Retribution reference identity")
	local ret0 = items.AdjustWeights(ret, "PALADIN", 3, {})
	assert(near(ret0.STR, ret.STR / 1.10) and near(ret0.INT, ret.INT / 1.10 - 0.60 * ret.SP), "Retribution at 0 ranks")
	local prot = weightsTable.PALADIN[2]
	local prot0 = items.AdjustWeights(prot, "PALADIN", 2, {})
	assert(near(prot0.BVAL, prot.BVAL / 1.30) and near(prot0.ARMOR, prot.ARMOR / 1.06), "Protection Paladin BVAL and ARMOR at 0 ranks")
	local protCotL = items.AdjustWeights(prot, "PALADIN", 2, { [20143] = 3, [20150] = 2, [1311084] = 5 })
	assert(near(protCotL.INT, prot.INT + 0.60 * prot.SP), "Protection Paladin benefits from Champion of the Light")
	local holyCotL = items.AdjustWeights(weightsTable.PALADIN[1], "PALADIN", 1, { [20257] = 5, [20143] = 5, [1311084] = 5 })
	assert(holyCotL == weightsTable.PALADIN[1], "Holy Paladin ignores damage-only Champion of the Light")

	-- Hunter: Careful Aim (1223984), Lightning Reflexes (19168), Survivalist (19255).
	local bm0 = items.AdjustWeights(weightsTable.HUNTER[1], "HUNTER", 1, {})
	assert(near(bm0.INT, weightsTable.HUNTER[1].INT - (weightsTable.HUNTER[1].AP + weightsTable.HUNTER[1].RAP)), "BM Hunter without Careful Aim")
	local sv0 = items.AdjustWeights(weightsTable.HUNTER[3], "HUNTER", 3, {})
	assert(near(sv0.AGI, weightsTable.HUNTER[3].AGI / 1.15) and near(sv0.INT, weightsTable.HUNTER[3].INT - 0.7), "Survival Hunter at 0 ranks")
	local bmSurv = items.AdjustWeights(weightsTable.HUNTER[1], "HUNTER", 1, { [1223984] = 5, [19255] = 5 })
	assert(near(bmSurv.STA, weightsTable.HUNTER[1].STA * 1.10), "Hunter Survivalist scales STA")

	-- Priest: Mental Strength (18551), Spiritual Guidance (14901).
	local holy0 = items.AdjustWeights(weightsTable.PRIEST[2], "PRIEST", 2, {})
	assert(near(holy0.SPI, weightsTable.PRIEST[2].SPI - 0.25) and near(holy0.INT, weightsTable.PRIEST[2].INT / 1.10), "Holy Priest at 0 ranks")
	local discSG = items.AdjustWeights(weightsTable.PRIEST[1], "PRIEST", 1, { [18551] = 5, [14901] = 5 })
	assert(near(discSG.SPI, weightsTable.PRIEST[1].SPI + 0.25), "Discipline Priest with Spiritual Guidance")
	local shadowSG = items.AdjustWeights(weightsTable.PRIEST[3], "PRIEST", 3, { [18551] = 3, [14901] = 5 })
	assert(near(shadowSG.SPI, weightsTable.PRIEST[3].SPI + 0.08), "Shadow Priest gets spell-damage portion of Spiritual Guidance")

	-- Mage: Arcane Mind (11232), Arcane Resilience (28574).
	local arcane0 = items.AdjustWeights(weightsTable.MAGE[1], "MAGE", 1, {})
	assert(near(arcane0.INT, weightsTable.MAGE[1].INT / 1.10), "Arcane Mage without Arcane Mind")
	local frost0 = items.AdjustWeights(weightsTable.MAGE[3], "MAGE", 3, {})
	assert(near(frost0.INT, weightsTable.MAGE[3].INT - 0.75 * weightsTable.MAGE[3].ARMOR), "Frost Mage without Arcane Resilience")

	-- Warlock: Demonic Embrace (18697).
	local aff0 = items.AdjustWeights(weightsTable.WARLOCK[1], "WARLOCK", 1, {})
	assert(near(aff0.STA, weightsTable.WARLOCK[1].STA / 1.15), "Affliction Warlock without Demonic Embrace")
	local demoDE = items.AdjustWeights(weightsTable.WARLOCK[2], "WARLOCK", 2, { [18697] = 5 })
	assert(near(demoDE.STA, weightsTable.WARLOCK[2].STA * 1.15), "Demonology Warlock with Demonic Embrace")

	-- Druid: Heart of the Wild (17003), Living Spirit (1309631), Natural Instinct (1223242), Thick Hide (16929).
	local cat0 = items.AdjustWeights(weightsTable.DRUID[2], "DRUID", 2, {})
	assert(near(cat0.STR, weightsTable.DRUID[2].STR / 1.10) and cat0.STA == weightsTable.DRUID[2].STA, "Cat Druid HotW scales STR only")
	local bear0 = items.AdjustWeights(bearBase, "DRUID", 4, {})
	assert(near(bear0.STA, bearBase.STA / 1.20) and near(bear0.DEF, bearBase.DEF - 2.0 * bearBase.ARMOR)
		and bear0.STR == bearBase.STR, "Bear Druid HotW STA and Thick Hide DEF->ARMOR")
	local restoDruid = items.AdjustWeights(weightsTable.DRUID[3], "DRUID", 3, { [17003] = 5, [1309631] = 3, [1223242] = 2, [16929] = 3 })
	assert(near(restoDruid.INT, weightsTable.DRUID[3].INT + 1.10 * 0.25 * weightsTable.DRUID[3].HEAL)
		and restoDruid.DEF == nil, "Resto Druid gains Natural Instinct HEAL, ignores form-only Thick Hide")

	-- End-to-end C_Traits integration in ns.StatWeights() (including Bear profile and fallback on missing/secret data).
	local saved = {
		class = upvalue(getW, "playerClass"), weights = upvalue(getW, "weights"),
		tree = upvalue(getW, "weightsTree"), name = upvalue(getW, "weightsName"), preset = upvalue(getW, "weightsPreset"),
		traits = C_Traits, ct = C_ClassTalents, level = UnitLevel, spec = items.cdb.scoreSpec,
	}
	local activeRanks = {}
	local nodeMap = { [1] = 415140, [2] = 30812, [3] = 17485, [4] = 17003, [5] = 16929 }
	C_ClassTalents = { GetActiveConfigID = function() return 42 end }
	C_Traits = {
		GetConfigInfo = function(id) return id == 42 and { treeIDs = { 99 } } or nil end,
		GetGroupDisplayInfoByTreeID = function()
			return {
				{ groupID = 1, orderIndex = 0, displayName = "Tree1" },
				{ groupID = 2, orderIndex = 1, displayName = "Tree2" },
				{ groupID = 3, orderIndex = 2, displayName = "Tree3" },
			}
		end,
		GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 2, currencyInfos = { { spent = 10 } } } } end,
		GetTreeNodes = function(tid) return tid == 99 and { 1, 2, 3, 4, 5 } or {} end,
		GetNodeInfo = function(_, nid)
			local r = activeRanks[nodeMap[nid]] or 0
			return { activeRank = r, activeEntry = r > 0 and { entryID = nid } or nil }
		end,
		GetEntryInfo = function(_, eid) return { definitionID = eid } end,
		GetDefinitionInfo = function(did) return { spellID = nodeMap[did] } end,
	}
	UnitLevel = function() return 60 end
	setuv(getW, "playerClass", "SHAMAN")
	items.cdb.scoreSpec = 2
	setuv(getW, "weights", nil)
	local w0 = ns.StatWeights()
	assert(near(w0.INT, 0.25), "live StatWeights lowers Enhancement INT when Mental Dexterity is 0/3")
	activeRanks[415140], activeRanks[30812], activeRanks[17485] = 3, 2, 3
	setuv(getW, "weights", nil)
	local wRef = ns.StatWeights()
	assert(wRef == weightsTable.SHAMAN[2], "live StatWeights matches reference table at reference ranks")
	setuv(getW, "playerClass", "DRUID")
	items.cdb.scoreSpec = 4
	activeRanks = { [17003] = 0, [16929] = 0 }
	setuv(getW, "weights", nil)
	local wBear0 = ns.StatWeights()
	assert(near(wBear0.STA, bearBase.STA / 1.20) and near(wBear0.DEF, bearBase.DEF - 2.0 * bearBase.ARMOR),
		"live StatWeights adjusts Bear profile via C_Traits")
	setuv(getW, "playerClass", saved.class)
	setuv(getW, "weights", saved.weights)
	setuv(getW, "weightsTree", saved.tree)
	setuv(getW, "weightsName", saved.name)
	setuv(getW, "weightsPreset", saved.preset)
	C_Traits, C_ClassTalents, UnitLevel, items.cdb.scoreSpec = saved.traits, saved.ct, saved.level, saved.spec
	print("talent stat weights OK")
end)()
;(function()
	-- ProfessionPlan ScanTrainer: skip tooltip builds for known/cached recipes and respect per-visit tooltip budget.
	local plan = ns:GetModule("ProfessionPlan")
	local scan = uv(plan.OnLogin, "ScanTrainer")
	local saved = {
		C_Trainer, Enum.TrainerType, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter,
		GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceSkillLine,
		GetTrainerServiceLevelReq, GetTrainerServiceCost, GetTrainerServiceItemLink, C_TooltipInfo,
		C_Spell, C_TradeSkillUI, debugprofilestop, plan.cdb.trainers,
	}
	local clock, tooltipReads = 0, 0
	local services = {
		{ name = "Known Recipe", kind = "used", skill = "Schmiedekunst", rank = 10 },
		{ name = "Cached Recipe", kind = "available", skill = "Schmiedekunst", rank = 25 },
		{ name = "Direct Link", kind = "available", skill = "Schmiedekunst", rank = 40, link = "|Hitem:1234|h[Sword]|h" },
		{ name = "Uncached One", kind = "available", skill = "Schmiedekunst", rank = 50, tipID = 5001 },
		{ name = "Over Budget", kind = "available", skill = "Schmiedekunst", rank = 60, tipID = 5002 },
	}
	Enum.TrainerType = { Tradeskills = 1 }
	C_Trainer = { GetTrainerType = function() return 1 end }
	GetTrainerServiceTypeFilter = function() return true end
	SetTrainerServiceTypeFilter = function() end
	GetNumTrainerServices = function() return #services end
	GetTrainerServiceInfo = function(i) return services[i].name, services[i].kind, 134400 end
	GetTrainerServiceSkillReq = function(i) return services[i].skill, services[i].rank end
	GetTrainerServiceSkillLine = function(i) return services[i].skill end
	GetTrainerServiceLevelReq = function() return 1 end
	GetTrainerServiceCost = function() return 100 end
	GetTrainerServiceItemLink = function(i) return services[i].link end
	C_Spell = { GetSpellIDForSpellIdentifier = function() return nil end }
	C_TradeSkillUI = { GetProfessionInfoByRecipeID = function() return nil end }
	C_TooltipInfo = { GetTrainerService = function(i)
		tooltipReads = tooltipReads + 1
		clock = clock + 2.0 -- first uncached tooltip exhausts the 1.5 ms budget
		return { id = services[i].tipID, type = Enum.TooltipDataType.Spell }
	end }
	debugprofilestop = function() return clock end
	plan.cdb.trainers = { ["Schmiedekunst"] = { { name = "Cached Recipe", recipeID = 4242 } } }
	scan()
	local savedList = plan.cdb.trainers["Schmiedekunst"]
	assert(tooltipReads == 1, "ScanTrainer skips known/cached/linked entries and stops after tooltip budget: " .. tooltipReads)
	assert(savedList[2].recipeID == 4242 and savedList[3].link == "|Hitem:1234|h[Sword]|h"
		and savedList[4].recipeID == 5001 and savedList[5].recipeID == nil,
		"ScanTrainer preserves cached IDs, direct links and budgeted tooltip IDs")
	-- Second visit reuses newly saved IDs without rebuilding tooltips for them.
	tooltipReads, clock = 0, 0
	scan()
	assert(tooltipReads == 1 and plan.cdb.trainers["Schmiedekunst"][5].recipeID == 5002,
		"next trainer visit fills only the remaining uncached entry")
	C_Trainer, Enum.TrainerType, GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = unpack(saved, 1, 4)
	GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceSkillLine = unpack(saved, 5, 8)
	GetTrainerServiceLevelReq, GetTrainerServiceCost, GetTrainerServiceItemLink, C_TooltipInfo = unpack(saved, 9, 12)
	C_Spell, C_TradeSkillUI, debugprofilestop, plan.cdb.trainers = unpack(saved, 13, 16)

	-- Instrumentation: ns.OnAddOnLoaded and /fp slash commands record timings into session/measuring stats.
	local savedEventUtil, savedClock2, savedTime = EventUtil, debugprofilestop, GetTime
	local tClock, tNow = 0, 2000
	GetTime = function() return tNow end
	debugprofilestop = function() return tClock end
	EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
	ns.SetMeasuring(true)
	tNow = 2001
	ns.OnAddOnLoaded("Blizzard_TestLoad", function() tClock = tClock + 6.0 end)
	assert(ns.timings["OnAddOnLoaded: Blizzard_TestLoad"] and ns.timings["OnAddOnLoaded: Blizzard_TestLoad"].max == 6.0,
		"ns.OnAddOnLoaded callbacks are measured")
	local savedPrint = ns.PrintAlways
	ns.PrintAlways = function() tClock = tClock + 7.5 end
	SlashCmdList.FOREVERPLUS("hilfe")
	ns.PrintAlways = savedPrint
	assert(ns.timings["Slash: /fp hilfe"] and ns.timings["Slash: /fp hilfe"].max == 7.5,
		"slash commands are measured")
	ns.SetMeasuring(false)
	EventUtil, debugprofilestop, GetTime = savedEventUtil, savedClock2, savedTime
	print("trainer scan and instrumentation OK")
end)()
;(function()
	-- Compact group loot roll frames (Modules/LootRoll.lua)
	local lr = ns:GetModule("LootRoll")
	assert(lr and lr.db.enabled == true, "LootRoll module loaded and enabled by default")
	for _, opt in ipairs(lr.options) do
		if opt.type ~= "button" then
			assert(opt.new == true, "LootRoll option marked NEW: " .. tostring(opt.key))
		end
	end
	lr._ResetStateForTests()

	local saved = {
		GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot, ConfirmLootRoll,
		IsShiftKeyDown, C_LootHistory, C_ClassColor, Enum.EncounterLootDropRollState,
		LOOT_ROLL_INELIGIBLE_REASON1, LOOT_ROLL_NEED, LOOT_ROLL_PASSED,
		C_Item.GetItemInfoInstant, ns.RewardComparisonState,
	}
	C_Item.GetItemInfoInstant = function(link)
		return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	end
	ns.RewardComparisonState = function(link)
		return type(link) == "string" and link:find("item:17182", 1, true) and "better" or nil
	end
	local rolls = {
		[101] = {
			tex = 135328, name = "Sulfuras Shard", count = 1, quality = 4, bop = true,
			canNeed = true, canGreed = true, canDE = false, rNeed = nil, rGreed = nil, rDE = nil, deSkill = nil, canTransmog = false,
			link = "|cffa335ee|Hitem:17182::::::::60:::::::|h[Sulfuras Shard]|h|r", left = 45000,
		},
		[102] = {
			tex = 134414, name = "Sapphire Ring", count = 2, quality = 3, bop = false,
			canNeed = false, canGreed = true, canDE = true, rNeed = 1, rGreed = nil, rDE = nil, deSkill = nil, canTransmog = true,
			link = "|cff0070dd|Hitem:20001::::::::60:::::::|h[Sapphire Ring]|h|r", left = 30000,
		},
	}
	LOOT_ROLL_INELIGIBLE_REASON1 = "Cannot roll need"
	LOOT_ROLL_NEED = "%s has selected Need for: %s"
	LOOT_ROLL_PASSED = "%s passed on: %s"
	GetLootRollItemInfo = function(id)
		local r = rolls[id]
		if not r then return nil end
		return r.tex, r.name, r.count, r.quality, r.bop, r.canNeed, r.canGreed, r.canDE, r.rNeed, r.rGreed, r.rDE, r.deSkill, r.canTransmog
	end
	GetLootRollItemLink = function(id) return rolls[id] and rolls[id].link end
	GetLootRollTimeLeft = function(id) return rolls[id] and rolls[id].left or 0 end
	local rolled, confirmed = {}, {}
	RollOnLoot = function(id, rt) rolled[#rolled + 1] = { id, rt } end
	ConfirmLootRoll = function(id, rt) confirmed[#confirmed + 1] = { id, rt } end
	local shiftDown = false
	IsShiftKeyDown = function() return shiftDown end
	Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
	C_ClassColor = {
		GetClassColor = function(cls)
			if cls == "WARRIOR" then
				return { WrapTextInColorCode = function(_, s) return "|cffc69b6d" .. s .. "|r" end }
			end
		end,
	}

	-- Open two rolls and verify BoP/BoE, Transmog/DE buttons and disabled reason.
	lr:START_LOOT_ROLL("START_LOOT_ROLL", 101, 60000)
	lr:START_LOOT_ROLL("START_LOOT_ROLL", 102, 60000)
	assert(#lr._activeBars == 2, "two compact loot roll bars opened")
	local b1, b2 = lr._activeBars[1], lr._activeBars[2]
	assert(b1.rollID == 101 and b1.bop == true and not b1.showTransmog and not b1.showDisenchant, "bar 1 BoP standard buttons")
	assert(b1.UpgradeArrow:IsShown() and not b2.UpgradeArrow:IsShown(), "upgrade arrow shown only for better gear")
	assert(b2.rollID == 102 and b2.bop == false and b2.showTransmog and b2.showDisenchant, "bar 2 BoE transmog + DE buttons")
	assert(b2.buttons.need.reason == "Cannot roll need", "disabled need button stores ineligible reason")

	-- Clicks: normal uses RollOnLoot, Shift uses ConfirmLootRoll for non-pass rolls.
	b1.buttons.need:GetScript("OnClick")(b1.buttons.need)
	assert(#rolled == 1 and rolled[1][1] == 101 and rolled[1][2] == 1, "normal click calls RollOnLoot")
	shiftDown = true
	b1.buttons.need:GetScript("OnClick")(b1.buttons.need)
	assert(#confirmed == 1 and confirmed[1][1] == 101 and confirmed[1][2] == 1, "shift-click calls ConfirmLootRoll")
	b1.buttons.pass:GetScript("OnClick")(b1.buttons.pass)
	assert(#rolled == 2 and rolled[2][1] == 101 and rolled[2][2] == 0, "shift-click on pass still uses RollOnLoot")
	shiftDown = false

	-- Chat fallback updates counts on rolls without C_LootHistory.
	lr:CHAT_MSG_LOOT("CHAT_MSG_LOOT", "Thrall has selected Need for: " .. rolls[101].link)
	assert(#b1.voters.need == 1 and b1.voters.need[1] == "Thrall", "chat fallback tracks non-boss roll votes")

	-- C_LootHistory updates counts with class colors and roll numbers, and takes precedence over chat.
	C_LootHistory = {
		GetSortedInfoForDrop = function()
			return {
				itemHyperlink = rolls[101].link,
				rollInfos = {
					{ playerName = "Arthas", playerClass = "WARRIOR", state = 0, roll = 92 },
					{ playerName = "Jaina", playerClass = "MAGE", state = 5 },
				},
			}
		end,
	}
	lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 1, 1)
	assert(#b1.voters.need == 1 and b1.voters.need[1] == "|cffc69b6dArthas|r (92)", "C_LootHistory sets class-colored roll voter")
	assert(#b1.voters.pass == 1 and b1.voters.pass[1] == "Jaina", "C_LootHistory sets pass voter")

	-- Cancel removes the roll bar cleanly; preview toggles and dismisses without calling RollOnLoot.
	lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 101)
	assert(#lr._activeBars == 1 and lr._activeBars[1].rollID == 102, "CANCEL_LOOT_ROLL removes only matching roll")
	lr:CANCEL_ALL_LOOT_ROLLS()
	assert(#lr._activeBars == 0, "CANCEL_ALL_LOOT_ROLLS clears active rolls")

	local rolledBefore = #rolled
	lr.TogglePreview()
	assert(#lr._activeBars == 3, "preview shows 3 sample bars")
	lr._activeBars[1].buttons.pass:GetScript("OnClick")(lr._activeBars[1].buttons.pass)
	assert(#lr._activeBars == 2 and #rolled == rolledBefore, "clicking preview bar dismisses it without RollOnLoot")
	lr.TogglePreview()
	assert(#lr._activeBars == 0, "second TogglePreview hides remaining preview bars")

	-- Height, width, scale and Edit Mode options panel integration.
	assert(lr.db.height == 28, "LootRoll height defaults to 28")
	local editEntry = ns.editFrames and ns.editFrames.LootRoll
	assert(editEntry and type(editEntry.onClick) == "function", "LootRoll registers Edit Mode click handler")
	local anchor = lr._GetAnchor()
	local anchorW, anchorH, barW, barH, barScale, barStrata
	local origAnchorSize = anchor.SetSize
	anchor.SetSize = function(_, w, h) anchorW, anchorH = w, h end
	local origBarSize, origBarScale, origBarStrata = b1.SetSize, b1.SetScale, b1.SetFrameStrata
	b1.SetSize = function(_, w, h) barW, barH = w, h end
	b1.SetScale = function(_, s) barScale = s end
	b1.SetFrameStrata = function(_, st) barStrata = st end

	ns.SetOption("LootRoll", "width", 400)
	ns.SetOption("LootRoll", "height", 36)
	ns.SetOption("LootRoll", "scale", 1.25)
	assert(anchorW == 500 and anchorH == 45, "anchor tracks scaled width and height")
	assert(barW == 400 and barH == 36 and barScale == 1.25, "bars apply width, height and scale")

	-- Edit Mode shows preview bars at LOW strata and opens the options panel with 3 sliders (scale, width, height).
	local savedIsEdit = ns.IsEditModeActive
	ns.IsEditModeActive = function() return true end
	editEntry.onEditMode(true)
	assert(#lr._activeBars == 2 and barStrata == "LOW", "Edit Mode shows preview bars behind selection frame")
	editEntry.onClick(anchor)
	local panel = lr._GetEditPanel()
	assert(panel and panel:IsShown() and #panel.refreshers == 3 and panel.growCheck,
		"Edit Mode options panel opens with scale, width, height sliders and growUp toggle")
	ns.IsEditModeActive = function() return false end
	editEntry.onEditMode(false)
	assert(not panel:IsShown() and #lr._activeBars == 0, "exiting Edit Mode hides options panel and preview bars")

	ns.IsEditModeActive = savedIsEdit
	anchor.SetSize = origAnchorSize
	b1.SetSize, b1.SetScale, b1.SetFrameStrata = origBarSize, origBarScale, origBarStrata
	ns.SetOption("LootRoll", "width", 328)
	ns.SetOption("LootRoll", "height", 28)
	ns.SetOption("LootRoll", "scale", 1)

	lr._ResetStateForTests()
	GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot, ConfirmLootRoll = unpack(saved, 1, 5)
	IsShiftKeyDown, C_LootHistory, C_ClassColor, Enum.EncounterLootDropRollState = unpack(saved, 6, 9)
	LOOT_ROLL_INELIGIBLE_REASON1, LOOT_ROLL_NEED, LOOT_ROLL_PASSED = unpack(saved, 10, 12)
	C_Item.GetItemInfoInstant, ns.RewardComparisonState = saved[13], saved[14]
	print("compact loot roll frames OK")
end)()
;(function()
	-- MapSymbols slicing, RecipeRadar targeted invalidation + scan budget, Camera state reuse,
	-- MeasuredReturn chat filters and frame-level GC tagging.
	local camera = ns:GetModule("Camera")
	local s1, s2 = camera.State(), camera.State()
	assert(s1 == s2, "Camera.State reuses its table instead of allocating every tick")

	-- MeasuredReturn preserves multiple return values (including nils) and records timings.
	local savedClock, savedTime = debugprofilestop, GetTime
	local clock, now = 0, 2100
	debugprofilestop = function() return clock end
	GetTime = function() return now end
	ns.SetMeasuring(true)
	now = 2101
	local wrapped = ns.MeasuredReturn("Test: multi return", function(a, b)
		clock = clock + 1.2
		return false, a, nil, b
	end)
	local r1, r2, r3, r4 = wrapped("msg", "sender")
	assert(r1 == false and r2 == "msg" and r3 == nil and r4 == "sender",
		"MeasuredReturn preserves all return values including false and nil")
	assert(ns.timings["Test: multi return"] and ns.timings["Test: multi return"].max == 1.2,
		"MeasuredReturn records call duration")
	ns.SetMeasuring(false)
	debugprofilestop, GetTime = savedClock, savedTime

	-- RecipeRadar OnItemInfo keeps cached entries for other recipes and ignores unrelated items.
	local radar = ns:GetModule("RecipeRadar")
	local refresh = uv(radar.RequestRefresh, "Refresh")
	local onItemInfo = uv(refresh, "OnItemInfo")
	local statusCache = uv(onItemInfo, "statusCache")
	local recipes = uv(onItemInfo, "recipes")
	local anyID = next(recipes)
	assert(anyID, "radar has recipe entries")
	local savedRefreshReq = radar.RequestRefresh
	local reqCount = 0
	radar.RequestRefresh = function() reqCount = reqCount + 1 end
	statusCache[anyID] = "ok"
	statusCache[999999] = "ok"
	onItemInfo(radar, "GET_ITEM_INFO_RECEIVED", 888888, true)
	assert(reqCount == 0 and statusCache[anyID] == "ok" and statusCache[999999] == "ok",
		"non-recipe GET_ITEM_INFO_RECEIVED does not wipe statusCache or schedule refresh")
	onItemInfo(radar, "GET_ITEM_INFO_RECEIVED", anyID, true)
	assert(reqCount == 1 and statusCache[anyID] == nil and statusCache[999999] == "ok",
		"recipe GET_ITEM_INFO_RECEIVED invalidates only the affected recipe")
	statusCache[999999] = nil
	radar.RequestRefresh = savedRefreshReq

	-- Unattributed >5 ms moment with frame-level GC drop gets the (GC) tag.
	local info = ns:GetModule("Info")
	local record = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "SampleAddonMetrics")
	record = uv(record, "RecordSpikeMoment")
	record(2102, { name = ns.name, title = ns.name, own = true }, 9.5, nil, nil, nil, nil, nil, true)
	local text = info.SpikesText()
	assert(text:find(ns.L.INFO_SPIKES_UNATTRIBUTED_GC, 1, true), "unattributed GC spike is labelled with (GC)")
	uv(info.ShowSpikes, "ResetSession")()
	assert(info.SpikesText(true) == nil, "ResetSession clears the recorded GC moment")
	print("map/radar/gc optimization OK")
end)()
;(function()
	-- Runtime stutter optimizations: lazy/incremental LootSources cache, single-pass nameplate scans,
	-- Blizzard_* exclusion in Info sampler, non-player Camera spellcast filtering, PortraitModes batching,
	-- SoloParty font reuse, and Waypoint unchanged-state skip.

	-- 1. LootSources: Record updates cache incrementally without rebuilding untouched items, DropsFrom stays lazy.
	local loot = ns:GetModule("LootSources")
	local savedSources, savedCount, savedMerged = ns.db.lootSources, loot.count, loot.merged
	ns.db.lootSources, loot.count, loot.merged = {}, 0, nil
	local itemA, itemB
	for id in pairs(ns.LootData.items) do
		if not itemA then itemA = id elseif not itemB then itemB = id break end
	end
	assert(itemA and itemB, "shipped loot table has at least two items")
	local rowA = ns.LootData.items[itemA][1]
	assert(loot.DropsFrom(itemA, rowA[1]), "lazy shipped drop lookup finds item")
	assert(loot.merged == nil, "DropsFrom does not eagerly build the full merge table")
	loot.Sources(itemA)
	loot.Sources(itemB)
	local cacheBefore = loot.merged
	local cachedB = cacheBefore.byItem[itemB]
	assert(cacheBefore and cacheBefore.byItem[itemA] and cachedB, "Sources caches only queried items")
	loot.Record("perf-g1", rowA[1], { itemA }, "Perf Mob")
	assert(loot.merged == cacheBefore, "Record keeps merge cache instance alive instead of wiping it")
	assert(cacheBefore.byItem[itemA] == nil and cacheBefore.byItem[itemB] == cachedB,
		"Record invalidates only the looted item and keeps untouched item caches")
	local updatedA
	for _, s in ipairs(loot.Sources(itemA)) do
		if s.key == rowA[1] then updatedA = s end
	end
	assert(updatedA and updatedA.drops == rowA[2] + 1 and updatedA.windows == rowA[3] + 1,
		"incremental Record update reflects new drop and window counts")
	ns.db.lootSources, loot.count, loot.merged = savedSources, savedCount, savedMerged

	-- 2. Quests: UpdateNameplate scans the unit tooltip at most once per nameplate.
	local quests = ns:GetModule("Quests")
	local updatePlate = uv(quests.RefreshNameplates, "UpdateNameplate")
	local qSaved = { C_NamePlate.GetNamePlateForUnit, C_QuestLog.UnitIsRelatedToActiveQuest, C_TooltipInfo.GetUnit,
		UnitIsPlayer, UnitCanAttack, quests.db.nameplateIcons }
	local tipCalls = 0
	local fakePlate = CreateFrame("Frame")
	C_NamePlate.GetNamePlateForUnit = function() return fakePlate end
	C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	C_TooltipInfo.GetUnit = function()
		tipCalls = tipCalls + 1
		return { lines = { { type = Enum.TooltipDataLineType.QuestObjective, leftText = "Felle: 2/5" } } }
	end
	UnitIsPlayer = function() return false end
	UnitCanAttack = function() return true end
	quests.db.nameplateIcons = true
	updatePlate("nameplate1")
	assert(tipCalls == 1, "UpdateNameplate scans the unit tooltip once instead of twice: " .. tipCalls)
	C_NamePlate.GetNamePlateForUnit, C_QuestLog.UnitIsRelatedToActiveQuest, C_TooltipInfo.GetUnit,
		UnitIsPlayer, UnitCanAttack, quests.db.nameplateIcons = unpack(qSaved, 1, 6)

	-- 3. Info: TrackAddon ignores Blizzard_* internal load-on-demand addons.
	local info = ns:GetModule("Info")
	local trackAddon = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "TrackAddon")
	local metrics = uv(trackAddon, "sessionMetrics")
	trackAddon("Blizzard_Professions", "Blizzard_Professions")
	assert(metrics["Blizzard_Professions"] == nil, "Blizzard_* LoD addons are not added to per-frame profiler sampling")

	-- 4. Camera: OnFastEvent ignores non-player UNIT_SPELLCAST_START / STOP.
	local camera = ns:GetModule("Camera")
	local onFast = uv(camera.Start, "OnFastEvent")
	local savedCamUpdate = camera.Update
	local camCalls = 0
	camera.Update = function() camCalls = camCalls + 1 end
	onFast(camera, "UNIT_SPELLCAST_START", "nameplate1")
	onFast(camera, "UNIT_SPELLCAST_STOP", "target")
	assert(camCalls == 0, "Camera ignores non-player spellcast events")
	onFast(camera, "UNIT_SPELLCAST_START", "player")
	assert(camCalls == 1, "Camera handles player spellcast events")
	camera.Update = savedCamUpdate

	-- 5. PortraitModes: non-Shift modifier events do not call native input setters.
	local pm = ns.PortraitModes
	local wheelFrame = _G.ForeverPlusPlayerPortraitWheel
	if wheelFrame then
		local updateInput = uv(pm.Refresh, "UpdatePortraitInput")
		local savedEnableWheel = wheelFrame.EnableMouseWheel
		local wheelCalls = 0
		wheelFrame.EnableMouseWheel = function(self, on)
			wheelCalls = wheelCalls + 1
			return savedEnableWheel(self, on)
		end
		updateInput(nil, "MODIFIER_STATE_CHANGED", "LCTRL")
		updateInput(nil, "MODIFIER_STATE_CHANGED", "LALT")
		assert(wheelCalls == 0, "PortraitModes ignores Ctrl/Alt modifier events")
		wheelFrame.EnableMouseWheel = savedEnableWheel
	end

	-- 6. Visuals: UpdateImbues skips C_TooltipInfo.GetInventoryItem when weapon enchant signature is unchanged.
	local visuals = ns:GetModule("Visuals")
	local updateActiveAuras = uv(uv(uv(visuals.OnLogin, "UpdateAuraWatch"), "QueueAuraUpdate"), "UpdateActiveAuras")
	local updateImbues = uv(updateActiveAuras, "UpdateImbues")
	local scanImbues = uv(updateImbues, "ScanImbues")
	local savedWeaponEnchant, savedWeaponSlot, savedInvTip = C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot, C_TooltipInfo.GetInventoryItem
	local invTipCalls = 0
	Enum.WeaponSlot = { MainHand = 1, OffHand = 2 }
	C_Item.GetWeaponEnchantInfo = function(slot)
		if slot == 1 then return { { hasEnchant = true, enchantID = 29 } } end
		return {}
	end
	C_TooltipInfo.GetInventoryItem = function()
		invTipCalls = invTipCalls + 1
		return { lines = { { leftText = "Felsbeißer 3 (30 Min.)" } } }
	end
	setuv(scanImbues, "lastImbueSig", nil)
	updateImbues(false)
	assert(invTipCalls == 1, "first UpdateImbues reads weapon tooltip once")
	updateImbues(false)
	assert(invTipCalls == 1, "unchanged weapon enchants skip C_TooltipInfo.GetInventoryItem on UNIT_AURA")
	updateImbues(true)
	assert(invTipCalls == 2, "forced UpdateImbues (UNIT_INVENTORY_CHANGED) rescans weapon tooltip")
	C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot, C_TooltipInfo.GetInventoryItem = savedWeaponEnchant, savedWeaponSlot, savedInvTip

	-- 7. Quests: ScanQuests defers RefreshNameplates off the quest log scan frame.
	local scanQuests = uv(uv(quests.OnLogin, "QueueScan"), "ScanQuests")
	local savedAfter, savedRefreshPlates, savedNumEntries = C_Timer.After, quests.RefreshNameplates, C_QuestLog.GetNumQuestLogEntries
	local deferredPlates, plateRefreshes = {}, 0
	C_Timer.After = function(_, fn) deferredPlates[#deferredPlates + 1] = fn end
	quests.RefreshNameplates = function() plateRefreshes = plateRefreshes + 1 end
	C_QuestLog.GetNumQuestLogEntries = function() return 0 end
	quests.db.nameplateIcons = true
	scanQuests()
	assert(plateRefreshes == 0 and #deferredPlates == 1, "ScanQuests defers RefreshNameplates to the next frame")
	deferredPlates[1]()
	assert(plateRefreshes == 1, "deferred nameplate refresh runs on the next tick")
	C_Timer.After, quests.RefreshNameplates, C_QuestLog.GetNumQuestLogEntries = savedAfter, savedRefreshPlates, savedNumEntries

	-- 8. Minimap: MakeEmitterProvider attaches collection directly without InsertTable per row.
	local minimap = ns:GetModule("Minimap")
	local updateEmitterBtn = uv(minimap.OnOptionChanged, "UpdateEmitterButton")
	local refreshEmitters = uv(updateEmitterBtn, "RefreshEmitters")
	local applyMatches = uv(refreshEmitters, "ApplyEmitterMatches")
	local makeProvider = uv(applyMatches, "MakeEmitterProvider")
	local savedCreateDP = CreateDataProvider
	local insertCalls = 0
	CreateDataProvider = function(tbl)
		if tbl then insertCalls = insertCalls + #tbl end
		return { collection = tbl or {} }
	end
	local sample = { { 1, "a" }, { 2, "b" } }
	local dp = makeProvider(sample)
	assert(dp.collection == sample and insertCalls == 0, "MakeEmitterProvider attaches entries directly without per-row InsertTable")
	CreateDataProvider = savedCreateDP

	-- 9. Quests: QueueDistanceSort skips QueueSort when the player has not moved.
	local queueDistSort = uv(quests.UpdateTrackerSort, "QueueDistanceSort")
	local savedMapBest, savedMapPos = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition
	local savedQueueSort = uv(queueDistSort, "QueueSort")
	local distSorts, px, py = 0, 0.5, 0.5
	setuv(queueDistSort, "QueueSort", function() distSorts = distSorts + 1 end)
	setuv(queueDistSort, "lastDistMap", nil)
	C_Map.GetBestMapForUnit = function() return 1453 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end
	queueDistSort()
	queueDistSort()
	assert(distSorts == 1, "QueueDistanceSort skips repeated sort ticks while standing still: " .. distSorts)
	px = 0.51
	queueDistSort()
	assert(distSorts == 2, "QueueDistanceSort runs again once the player moves")
	setuv(queueDistSort, "QueueSort", savedQueueSort)
	C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = savedMapBest, savedMapPos

	-- 10. Landing: OnUpdate skips GetTime and Blocked checks while grounded.
	local landing = ns:GetModule("Landing")
	local landingUpdate = uv(landing.Apply, "OnUpdate")
	local savedFalling, savedSwimming = IsFalling, IsSwimming
	local swimCalls = 0
	IsFalling = function() return false end
	IsSwimming = function() swimCalls = swimCalls + 1 return false end
	landingUpdate()
	assert(swimCalls == 0, "Landing skips Blocked() checks when not falling")
	IsFalling, IsSwimming = savedFalling, savedSwimming

	-- 11. Mover: UpdateCatcherTarget skips GetMouseFoci when the cursor has not moved.
	local moverMod = ns:GetModule("Mover")
	local updateCatcherTarget = uv(moverMod.UpdateCatcher, "UpdateCatcherTarget")
	local savedCursor, savedFoci = GetCursorPosition, GetMouseFoci
	local fociCalls = 0
	GetCursorPosition = function() return 400, 300 end
	GetMouseFoci = function() fociCalls = fociCalls + 1 return {} end
	updateCatcherTarget(true)
	updateCatcherTarget(false)
	assert(fociCalls == 1, "Mover skips GetMouseFoci when cursor coordinates have not changed")
	GetCursorPosition, GetMouseFoci = savedCursor, savedFoci

	-- 12. Buffs: SyncWheelBindings skips ClearOverrideBindings / SetOverrideBindingClick when unchanged.
	local buffsMod = ns:GetModule("Buffs")
	local buffsUpdate = uv(buffsMod.OnLogin, "Update")
	local syncWheel = uv(buffsUpdate, "SyncWheelBindings")
	local savedClearBind, savedSetBind = ClearOverrideBindings, SetOverrideBindingClick
	local clearCalls, setCalls = 0, 0
	ClearOverrideBindings = function() clearCalls = clearCalls + 1 end
	SetOverrideBindingClick = function() setCalls = setCalls + 1 end
	setuv(syncWheel, "wheelBoundName", nil)
	syncWheel("ForeverPlusBuffButton1")
	syncWheel("ForeverPlusBuffButton1")
	assert(clearCalls == 1 and setCalls == 2, "Buffs updates wheel override bindings only when target changes")
	syncWheel(nil)
	syncWheel(nil)
	assert(clearCalls == 2 and setCalls == 2, "Buffs clears wheel override bindings only once")
	ClearOverrideBindings, SetOverrideBindingClick = savedClearBind, savedSetBind

	-- 13. Info: SampleAddonMetrics skips per-addon queries for foreign addons when GetOverallMetric shows no foreign work.
	local sampleMetrics = uv(uv(info.UpdatePerformance, "SetupProfilerSampler"), "SampleAddonMetrics")
	local savedRead, savedOverall = C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric
	local savedIgnore = uv(sampleMetrics, "ignoreUntil")
	local savedReset = uv(sampleMetrics, "resetAt")
	local savedLoading = uv(sampleMetrics, "loadingScreen")
	local foreignReads = 0
	C_AddOnProfiler.GetAddOnMetric = function(name)
		if name ~= ns.name then foreignReads = foreignReads + 1 end
		return name == ns.name and 0.4 or 0
	end
	C_AddOnProfiler.GetOverallMetric = function() return 0.41 end
	setuv(sampleMetrics, "ignoreUntil", 0)
	setuv(sampleMetrics, "resetAt", nil)
	setuv(sampleMetrics, "loadingScreen", false)
	sampleMetrics(100, nil, nil, 99, nil, nil, nil, false)
	assert(foreignReads == 0, "SampleAddonMetrics skips foreign GetAddOnMetric calls on quiet frames: " .. foreignReads)
	C_AddOnProfiler.GetOverallMetric = function() return 3.5 end
	sampleMetrics(101, nil, nil, 100, nil, nil, nil, false)
	assert(foreignReads > 0, "SampleAddonMetrics queries foreign addons when overall time exceeds ForeverPlus")
	setuv(sampleMetrics, "ignoreUntil", savedIgnore)
	setuv(sampleMetrics, "resetAt", savedReset)
	setuv(sampleMetrics, "loadingScreen", savedLoading)
	C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric = savedRead, savedOverall

	-- 14. ChatIndent: OnSizeChanged skips height-only resizes (e.g. ChatMinimize folding) and re-wraps on width changes.
	local indentMod = ns:GetModule("ChatIndent")
	local onIndentResize = uv(uv(indentMod.Apply, "Hook"), "OnSizeChanged")
	local savedAfterIndent, savedIndentEnabled = C_Timer.After, indentMod.db.enabled
	local indentTimers, indentTransforms = 0, 0
	local fakeChat = {
		width = 320,
		GetWidth = function(self) return self.width end,
		TransformMessages = function() indentTransforms = indentTransforms + 1 end,
	}
	C_Timer.After = function(_, fn) indentTimers = indentTimers + 1 fn() end
	indentMod.db.enabled = true
	onIndentResize(fakeChat, 320, 120) -- first recorded width
	local afterFirst = indentTransforms
	onIndentResize(fakeChat, 320, 28)  -- height-only fold: must not re-wrap
	onIndentResize(fakeChat, 320, 120) -- height-only unfold: must not re-wrap
	assert(indentTimers == 1 and indentTransforms == afterFirst,
		"ChatIndent skips height-only OnSizeChanged events: " .. indentTimers .. "/" .. indentTransforms)
	fakeChat.width = 400
	onIndentResize(fakeChat, 400, 120) -- real width change: must re-wrap
	assert(indentTimers == 2, "ChatIndent still re-wraps when chat width changes: " .. indentTimers)
	C_Timer.After, indentMod.db.enabled = savedAfterIndent, savedIndentEnabled

	-- 15. GroupFinder: QueueLogUpdate coalesces bursts of QuestLogQuests_Update into one deferred pass.
	local gfMod = ns:GetModule("GroupFinder")
	local queueLog = uv(gfMod.OnLogin, "QueueLogUpdate")
	local savedAfterGF = C_Timer.After
	local gfQueued, gfTimers = nil, 0
	C_Timer.After = function(_, fn) gfQueued, gfTimers = fn, gfTimers + 1 end
	queueLog()
	queueLog()
	queueLog()
	assert(gfTimers == 1 and gfQueued ~= nil, "GroupFinder coalesces multiple QuestLogQuests_Update calls into one timer")
	gfQueued()
	queueLog()
	assert(gfTimers == 2, "GroupFinder accepts a new coalesced pass after the previous one runs")
	gfQueued()
	C_Timer.After = savedAfterGF

	-- 16. MapSymbols: DRAW_SYNC_LIMIT stays compact (<= 10) to avoid >5 ms synchronous bursts on map open.
	local drawFn = uv(ns.MapSymbols.Refresh, "Draw")
	assert(uv(drawFn, "DRAW_SYNC_LIMIT") <= 10, "MapSymbols keeps synchronous initial draw batch <= 10 symbols")

	print("runtime stutter optimizations OK")
end)()
;(function()
	-- CPU display accuracy: nested ns.Measured self-time, per-column colors, and ignoring <5 ms calls as peak/slow culprits.
	local info = ns:GetModule("Info")
	local setup = uv(info.UpdatePerformance, "SetupProfilerSampler")
	local sampler = uv(setup, "profilerSampler")
	local onEvent = sampler:GetScript("OnEvent")
	local sample = uv(ns.SetMeasuring, "spikeFrame"):GetScript("OnUpdate")
	local metrics = uv(uv(setup, "SampleAddonMetrics"), "sessionMetrics")
	local perf = uv(info.UpdatePerformance, "perfFrame")
	local resetSession = uv(info.ShowSpikes, "ResetSession")

	local savedTime, savedClock = GetTime, debugprofilestop
	local savedMetric, savedOverall = C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric
	local savedAddLine, savedAddDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine

	local now, clock = 3000, 0
	local ownMs = 0
	GetTime = function() return now end
	debugprofilestop = function() return clock end
	C_AddOnProfiler.GetAddOnMetric = function(name) return name == ns.name and ownMs or 0 end
	C_AddOnProfiler.GetOverallMetric = function() return ownMs end

	onEvent(sampler, "LOADING_SCREEN_DISABLED")
	now = 3030
	resetSession()
	sample()

	-- 1. Nested ns.Measured calls record exclusive (self) time so an outer wrapper does not hide or double-count an inner spike.
	local inner = ns.Measured("Wanderlust: SetUIVisibility", function() clock = clock + 68.0 end)
	local outer = ns.Measured("Wanderlust: window activity", function()
		clock = clock + 0.1
		inner()
	end)
	now = 3031
	sample()
	outer()
	now, ownMs = 3032, 68.2
	sample()
	local own = metrics[ns.name]
	assert(own.peakCall == "Wanderlust: SetUIVisibility" and math.abs(own.peakCallTime - 68.0) < 0.01,
		"nested inner call is credited as peakCall instead of outer wrapper: " .. tostring(own.peakCall))
	assert(own.slowCall == "Wanderlust: SetUIVisibility", "inner call is credited as slowCall")

	-- 2. A short (<5 ms) call inside a later >5 ms frame must not replace slowCall or look like the culprit in the tooltip.
	local tiny = ns.Measured("Wanderlust: window activity", function() clock = clock + 0.2 end)
	tiny()
	now, ownMs = 3033, 15.5
	sample()
	assert(own.slowCall == "Wanderlust: SetUIVisibility" and own.slowFrame == 68.2,
		"a 0.2 ms call does not overwrite the last real >=5 ms slowCall")

	-- 3. Per-column coloring: low Avg stays green while high Max is red, and >5 ms scales with session rate (per minute).
	local savedG, savedO, savedR = GREEN_FONT_COLOR, ORANGE_FONT_COLOR, RED_FONT_COLOR
	GREEN_FONT_COLOR = { r = 0, g = 1, b = 0, WrapTextInColorCode = function(_, t) return "[G:" .. t .. "]" end }
	ORANGE_FONT_COLOR = { r = 1, g = 0.5, b = 0, WrapTextInColorCode = function(_, t) return "[O:" .. t .. "]" end }
	RED_FONT_COLOR = { r = 1, g = 0, b = 0, WrapTextInColorCode = function(_, t) return "[R:" .. t .. "]" end }
	own.recentTotal, own.recentCount, own.slow = 0.07 * 60, 60, 19
	local doubleLines, singleLines = {}, {}
	GameTooltip.AddDoubleLine = function(_, left, right)
		doubleLines[#doubleLines + 1] = { left = tostring(left), right = tostring(right) }
	end
	GameTooltip.AddLine = function(_, line)
		singleLines[#singleLines + 1] = tostring(line)
	end
	-- After 41 minutes, 19 spikes (~0.46/min) are green; in a 10-minute session (~1.9/min) they are orange;
	-- in a 3-minute session (~6.3/min) they are red.
	local function OwnCpuRow(atNow)
		wipe(doubleLines)
		now = atNow
		perf:GetScript("OnEnter")(perf)
		for _, row in ipairs(doubleLines) do
			if row.left == own.title then return row.right end
		end
	end
	assert(OwnCpuRow(3032 + 41 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[G:19×]"),
		"41-minute session keeps sparse >5 ms count green")
	assert(OwnCpuRow(3032 + 10 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[O:19×]"),
		"10-minute session flags 1.9/min >5 ms rate as orange")
	assert(OwnCpuRow(3032 + 3 * 60) == ns.L.INFO_CPU_LINE:format("[G:0.07]", "[R:68.2]", "[R:19×]"),
		"3-minute session flags 6.3/min >5 ms rate as red")
	GREEN_FONT_COLOR, ORANGE_FONT_COLOR, RED_FONT_COLOR = savedG, savedO, savedR

	local joinedSingle = table.concat(singleLines, "\n")
	local shortPrefix = ns.L.INFO_SPIKES_SHORT_CALLS:format(ns.SLOW_MS)
	assert(joinedSingle:find(shortPrefix .. " (Wanderlust: window activity (0.2 ms))", 1, true),
		"tooltip moment marks sub-5 ms captured calls clearly instead of blaming them")

	resetSession()
	onEvent(sampler, "LOADING_SCREEN_ENABLED")
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = savedAddLine, savedAddDouble
	C_AddOnProfiler.GetAddOnMetric, C_AddOnProfiler.GetOverallMetric = savedMetric, savedOverall
	GetTime, debugprofilestop = savedTime, savedClock
	print("cpu display accuracy OK")
end)()
;(function()
	-- Guiding Wind: bearing/direction vectors, biome mapping, instance & combat guards,
	-- waypoint arrow suppression, sound rules, idle cleanup, bindings/commands and PortraitModes.
	local wind = ns:GetModule("GuidingWind")
	local way = ns:GetModule("Waypoint")
	local pm = ns.PortraitModes
	assert(wind and way, "GuidingWind and Waypoint modules loaded")

	-- 1. Options, defaults, NEU flags and settings page registration.
	assert(wind.db.enabled == true and wind.db.autoGusts == true
		and wind.db.biomeParticles == true and wind.db.sound == true and wind.db.interval == 14
		and wind.db.strength == 75, "GuidingWind defaults are sensible and non-breaking")
	local foundOwnPage = false
	for _, page in ipairs(ns.SettingsPages) do
		if page.title == ns.L.WIND_TITLE and #page == 1 and page[1][1] == "GuidingWind" then
			foundOwnPage = true
		end
	end
	assert(foundOwnPage, "GuidingWind has its own dedicated settings page")
	local intervalOpt
	for _, opt in ipairs(wind.options) do
		if opt.key then
			assert(opt.new == true, "new GuidingWind option carries new=true: " .. tostring(opt.key))
		end
		if opt.key == "interval" then intervalOpt = opt end
	end
	assert(intervalOpt and intervalOpt.min == 5 and intervalOpt.max == 60, "interval slider covers 5..60 s")
	assert(type(ForeverPlus_SummonGuidingWind) == "function"
		and BINDING_NAME_FOREVERPLUS_GUIDINGWIND == ns.L.WIND_BINDING, "key binding hook and label registered")

	-- 2. Angle normalization and screen-space direction vector.
	local function near(a, b) return math.abs(a - b) < 1e-6 end
	local dx, dy, mode = wind.DirectionVector(0)
	assert(near(dx, 0) and near(dy, 1) and mode == "ahead", "0 rad points straight ahead (up)")
	dx, dy, mode = wind.DirectionVector(math.pi / 2)
	assert(near(dx, -1) and near(dy, 0) and mode == "left", "+pi/2 points left")
	dx, dy, mode = wind.DirectionVector(-math.pi / 2)
	assert(near(dx, 1) and near(dy, 0) and mode == "right", "-pi/2 points right")
	dx, dy, mode = wind.DirectionVector(math.pi)
	assert(near(dx, 0) and near(dy, -1) and mode == "behind", "pi points behind (down)")
	assert(near(wind.NormalizeAngle(3 * math.pi), math.pi)
		and near(wind.NormalizeAngle(-3 * math.pi / 2), math.pi / 2), "angle wraps into (-pi, pi]")

	-- 3. Biome mapping (direct zones, parentMapID sub-map walk, unknown fallback).
	local savedMapInfo = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(id)
		if id == 9901 then return { mapID = 9901, parentMapID = 1426, name = "Coldridge Cave" } end
		if id == 9999 then return { mapID = 9999, parentMapID = 0, name = "Unknown" } end
		return { mapID = id, parentMapID = 0, name = "Zone " .. tostring(id) }
	end
	assert(wind.BiomeForMap(1429) == "forest", "Elwynn Forest -> forest")
	assert(wind.BiomeForMap(1447) == "autumn", "Azshara -> autumn")
	assert(wind.BiomeForMap(1452) == "snow", "Winterspring -> snow")
	assert(wind.BiomeForMap(1446) == "desert", "Tanaris -> desert")
	assert(wind.BiomeForMap(1428) == "volcanic", "Burning Steppes -> volcanic")
	assert(wind.BiomeForMap(1431) == "marsh", "Duskwood -> marsh")
	assert(wind.BiomeForMap(9901) == "snow", "sub-map inherits parent zone biome (Dun Morogh -> snow)")
	assert(wind.BiomeForMap(9999) == "neutral" and wind.BiomeForMap(nil) == "neutral", "unknown maps fall back to neutral")

	-- 4. Live waypoint guidance, WorldFrame parent, sound rules, idle stop and arrow suppression.
	local savedBestMap, savedPlayerPos, savedWorldSize = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize
	local savedHasWp, savedGetWp, savedSetWp, savedClearWp, savedCanWp =
		C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, C_Map.CanSetUserWaypointOnMap
	local savedFacing, savedInstance, savedCombat, savedTaxi = GetPlayerFacing, rawget(_G, "IsInInstance"), InCombatLockdown, rawget(_G, "UnitOnTaxi")
	local savedPlaySoundFile, savedStopSound, savedTimer, savedTime, savedPrintAlways, savedPrint =
		PlaySoundFile, rawget(_G, "StopSound"), C_Timer.NewTimer, GetTime, ns.PrintAlways, ns.Print
	local savedUiMapPoint, savedSuperTrack = UiMapPoint, C_SuperTrack

	local currentMap, playerX, playerY, facing = 1429, 0.5, 0.5, 0
	local inInstance, inCombat, onTaxi, nowTime = false, false, false, 500
	local userWp, soundsPlayed, timers, printed = nil, {}, {}, {}

	C_Map.GetBestMapForUnit = function() return currentMap end
	C_Map.GetPlayerMapPosition = function(mapID)
		if mapID == currentMap then return { GetXY = function() return playerX, playerY end } end
		return nil
	end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.HasUserWaypoint = function() return userWp ~= nil end
	C_Map.GetUserWaypoint = function() return userWp end
	C_Map.SetUserWaypoint = function(pt) userWp = pt return true end
	C_Map.ClearUserWaypoint = function() userWp = nil end
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
	GetPlayerFacing = function() return facing end
	IsInInstance = function() return inInstance, inInstance and "party" or "none" end
	InCombatLockdown = function() return inCombat end
	UnitOnTaxi = function() return onTaxi end
	GetTime = function() return nowTime end
	PlaySoundFile = function(id, channel)
		soundsPlayed[#soundsPlayed + 1] = { id = id, channel = channel }
		return true, #soundsPlayed
	end
	StopSound = function() end
	C_Timer.NewTimer = function(delay, fn)
		local t = { delay = delay, fn = fn, cancelled = false }
		function t:Cancel() self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end
	ns.PrintAlways = function(msg, ...) printed[#printed + 1] = select("#", ...) > 0 and msg:format(...) or msg end
	ns.Print = ns.PrintAlways
	WorldMapFrame:Hide()

	-- No waypoint yet: manual summon reports clearly, plays no sound and leaves overlay idle.
	local ok, reason = wind.Summon(true)
	assert(not ok and reason == "none" and #soundsPlayed == 0 and not wind.GetState().active,
		"manual summon without waypoint prints hint and stays idle")
	assert(printed[#printed] == ns.L.WIND_NO_WAYPOINT, "no-waypoint hint shown")

	-- Set waypoint to the east (right when facing north = -pi/2).
	way.Set(80, 50, "Goldhain")
	local arrow = _G.ForeverPlusWaypointArrow
	assert(wind.HidesWaypointArrow() and (not arrow or not arrow:IsShown()),
		"GuidingWind always replaces and hides the waypoint arrow while enabled")
	assert(wind.GetState().timerActive, "auto gust timer starts once a waypoint exists")

	-- Manual summon triggers gust pointing right (-pi/2), forest biome, and plays a real wind sound.
	ok, reason = wind.Summon(true)
	assert(ok and reason == "waypoint", "manual summon succeeds for active waypoint")
	local state = wind.GetState()
	local overlay = _G.ForeverPlusGuidingWind
	assert(state.active and state.rootShown and state.biome == "forest" and near(state.angle, -math.pi / 2),
		"gust runs toward east (-pi/2) with forest biome")
	assert(#soundsPlayed == 1 and soundsPlayed[1].channel == "SFX", "manual summon plays wind sound")

	-- Advancing past the gust duration hides the overlay cleanly (no idle OnUpdate).
	local onUpdate = overlay:GetScript("OnUpdate")
	for _ = 1, 30 do
		if not overlay:IsShown() then break end
		onUpdate(overlay, 0.1)
	end
	assert(not overlay:IsShown() and not wind.GetState().active, "overlay hides itself after gust completes")

	-- Automatic gust fires silently (no sound) out of combat, and respects combat/instance guards.
	nowTime = nowTime + 5
	local latestTimer = timers[#timers]
	assert(latestTimer and not latestTimer.cancelled and latestTimer.delay == 14, "auto gust scheduled for configured interval")
	latestTimer.fn()
	assert(wind.GetState().active and #soundsPlayed == 1, "automatic gust runs without playing sound")
	for _ = 1, 30 do
		if not overlay:IsShown() then break end
		onUpdate(overlay, 0.1)
	end

	-- Combat guard blocks automatic gusts.
	inCombat = true
	timers[#timers].fn()
	assert(not wind.GetState().active, "automatic gust does not fire during combat")
	inCombat = false

	-- Instance / nil facing guard catches missing GetPlayerFacing cleanly.
	inInstance = true
	facing = nil
	ok, reason = wind.Summon(true)
	assert(not ok and reason == "no_facing" and not wind.GetState().active, "nil facing in instance is caught safely")
	assert(printed[#printed] == ns.L.WIND_NO_DIRECTION, "instance/no-facing message shown")
	-- Preview (/fp wind test links) still works even without facing.
	nowTime = nowTime + 5
	SlashCmdList.FOREVERPLUS("wind test links")
	assert(wind.GetState().active and near(wind.GetState().angle, math.pi / 2) and #soundsPlayed == 2,
		"/fp wind test links runs preview gust to the left with sound")
	inInstance = false
	facing = 0

	-- Waypoint arrow suppression & clean restore on disable.
	assert(wind.HidesWaypointArrow() and (not arrow or not arrow:IsShown()), "GuidingWind suppresses the waypoint arrow")
	ns.SetOption("GuidingWind", "enabled", false)
	arrow = _G.ForeverPlusWaypointArrow
	assert(not wind.HidesWaypointArrow() and arrow and arrow:IsShown(), "disabling GuidingWind restores the waypoint arrow")
	assert(not wind.GetState().active and not wind.GetState().timerActive and not overlay:IsShown(),
		"disabling GuidingWind stops active gust and cancels auto timer")

	-- Re-enable and verify arrival clears the waypoint even while arrow is hidden.
	ns.SetOption("GuidingWind", "enabled", true)
	assert(not arrow:IsShown(), "re-enabling GuidingWind hides the waypoint arrow again")
	playerX, playerY = 0.799, 0.5
	ok, reason = wind.Summon(true)
	assert(not ok and reason == "arrived" and way.Target() == nil, "arrival check clears waypoint when close")

	-- PortraitModes: guidingWind has its own dedicated mode slot with WoW gale icon.
	assert(pm.FeatureMode("guidingWind") == "guidingWind" and pm.IsFeatureSelected("guidingWind"),
		"GuidingWind is registered in its own portrait mode and selected by default")
	assert(pm.ModeIcon("guidingWind") == 236154, "GuidingWind mode uses verified WoW gale icon 236154")
	assert(pm.MoveFeature("guidingWind", "wanderlust") and pm.FeatureMode("guidingWind") == "wanderlust",
		"GuidingWind can be reassigned onto Wanderlust mode")
	pm.ResetAssignments()
	assert(pm.FeatureMode("guidingWind") == "guidingWind" and pm.IsFeatureSelected("guidingWind"),
		"ResetAssignments restores GuidingWind to its own portrait mode")

	-- Restore state cleanly.
	way.Clear()
	ns.SetOption("GuidingWind", "enabled", true)
	C_Map.GetMapInfo, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize =
		savedMapInfo, savedBestMap, savedPlayerPos, savedWorldSize
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint, C_Map.CanSetUserWaypointOnMap =
		savedHasWp, savedGetWp, savedSetWp, savedClearWp, savedCanWp
	GetPlayerFacing, IsInInstance, InCombatLockdown, UnitOnTaxi = savedFacing, savedInstance, savedCombat, savedTaxi
	PlaySoundFile, StopSound, C_Timer.NewTimer, GetTime, ns.PrintAlways, ns.Print =
		savedPlaySoundFile, savedStopSound, savedTimer, savedTime, savedPrintAlways, savedPrint
	UiMapPoint, C_SuperTrack = savedUiMapPoint, savedSuperTrack
	print("guiding wind OK")
end)()
;(function()
	local tooltip = ns:GetModule("Tooltip")
	local showHover = uv(tooltip.OnLogin, "ShowHoverName")
	local objectCall = uv(tooltip.OnInitialize, "OnObjectTooltip")
	local frame = uv(showHover, "GetHover")()

	local saved = {
		rawget(_G, "UnitEffectiveLevel"), rawget(_G, "UnitLevel"), rawget(_G, "UnitIsCorpse"),
		rawget(_G, "UnitIsWildBattlePet"), rawget(_G, "UnitIsBattlePetCompanion"),
		rawget(_G, "UnitExists"), rawget(_G, "UnitName"), rawget(_G, "UnitIsPlayer"),
		rawget(_G, "issecretvalue"), C_Texture.GetAtlasInfo,
		frame.SetSize, frame.Level.SetText, frame.Skull.SetSize,
		tooltip.db.hoverLevel, tooltip.db.hoverName, tooltip.db.hoverObjects,
	}

	local effectiveLevel, rawLevel, corpse, wildPet, companionPet = 13, 13, false, false, false
	local exists, unitName, secretVal = true, "Onyxia", nil
	local atlasInfo = { width = 16, height = 20 }
	local levelText, frameW, skullW, skullH

	UnitEffectiveLevel = function() return effectiveLevel end
	UnitLevel = function() return rawLevel end
	UnitIsCorpse = function() return corpse end
	UnitIsWildBattlePet = function() return wildPet end
	UnitIsBattlePetCompanion = function() return companionPet end
	UnitExists = function() return exists end
	UnitName = function() return unitName end
	UnitIsPlayer = function() return false end
	issecretvalue = function(v) return secretVal ~= nil and v == secretVal end
	C_Texture.GetAtlasInfo = function(atlas) return atlas == "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon" and atlasInfo or nil end
	frame.SetSize = function(self, w, h) frameW = w; self.w, self.h = w, h end
	frame.Level.SetText = function(_, text) levelText = text end
	frame.Skull.SetSize = function(_, w, h) skullW, skullH = w, h end
	tooltip.db.hoverName, tooltip.db.hoverLevel, tooltip.db.hoverObjects = true, true, true

	-- 1. Effective level overrides raw UnitLevel (matches TargetFrameMixin:CheckLevel).
	effectiveLevel, rawLevel = 25, 40
	local lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == 25 and not isSkull, "effective level is used instead of raw UnitLevel")
	showHover()
	assert(levelText == 25 and frame.Level:IsShown() and not frame.Skull:IsShown(),
		"normal effective level shows text and hides skull")

	-- 2. Skull target: UnitEffectiveLevel <= 0 shows skull even when UnitLevel returns a positive number.
	effectiveLevel, rawLevel = -1, 63
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "negative effective level marks skull despite positive UnitLevel")
	showHover()
	assert(not frame.Level:IsShown() and levelText == "" and frame.Skull:IsShown(),
		"skull target hides level text and shows skull texture")
	assert(skullW == 11 and skullH == 14 and frameW == 82 + 11 + 4,
		"skull texture keeps atlas aspect ratio and reserves layout width")

	-- 3. Zero effective level also shows skull.
	effectiveLevel, rawLevel = 0, 60
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "zero effective level shows skull")

	-- 4. Corpse shows skull even when effective level is positive (matches TargetFrameMixin:CheckLevel).
	effectiveLevel, rawLevel, corpse = 18, 18, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and isSkull, "corpse shows skull even with positive effective level")
	showHover()
	assert(frame.Skull:IsShown() and not frame.Level:IsShown(), "corpse renders skull on hover frame")
	corpse = false

	-- 5. Battle pets hide level and skull (matches Camelot CheckBattlePet).
	effectiveLevel, wildPet = 1, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "wild battle pet shows neither level nor skull")
	showHover()
	assert(not frame.Level:IsShown() and not frame.Skull:IsShown(), "wild battle pet hides level and skull")
	wildPet, companionPet = false, true
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "companion battle pet shows neither level nor skull")
	companionPet = false

	-- 6. Missing atlas falls back cleanly to "??".
	effectiveLevel, atlasInfo = -1, nil
	showHover()
	assert(frame.Level:IsShown() and levelText == "??" and not frame.Skull:IsShown(),
		"missing skull atlas falls back to ?? text")
	atlasInfo = { width = 16, height = 20 }

	-- 7. Secret values on level or flags hide level and skull without error.
	secretVal = "SECRET_LEVEL"
	effectiveLevel = secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret effective level hides level safely")
	effectiveLevel, corpse = 20, secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret corpse flag hides level safely")
	corpse, wildPet = false, secretVal
	lv, isSkull = tooltip.HoverLevel("mouseover")
	assert(lv == nil and not isSkull, "secret battle pet flag hides level safely")
	wildPet, secretVal = false, nil

	-- 8. Toggling hoverLevel off hides skull immediately; switching to object hides skull too.
	effectiveLevel = -1
	showHover()
	assert(frame.Skull:IsShown(), "skull shown before option toggle")
	tooltip.db.hoverLevel = false
	tooltip:OnOptionChanged("hoverLevel")
	assert(not frame.Skull:IsShown() and not frame.Level:IsShown(), "disabling hoverLevel hides skull immediately")
	tooltip.db.hoverLevel = true
	tooltip:OnOptionChanged("hoverLevel")
	assert(frame.Skull:IsShown(), "reenabling hoverLevel restores skull immediately")
	exists = false
	objectCall(GameTooltip)
	assert(not frame.Skull:IsShown() and not frame.Level:IsShown(), "object hover hides skull texture")

	UnitEffectiveLevel, UnitLevel, UnitIsCorpse, UnitIsWildBattlePet, UnitIsBattlePetCompanion,
		UnitExists, UnitName, UnitIsPlayer, issecretvalue, C_Texture.GetAtlasInfo,
		frame.SetSize, frame.Level.SetText, frame.Skull.SetSize,
		tooltip.db.hoverLevel, tooltip.db.hoverName, tooltip.db.hoverObjects = unpack(saved, 1, 16)
	print("hover skull level OK")
end)()
-- Auction house: total profit/loss for quantities > 1 (sell summary, cells, quick buy)
;(function()
	local A = ns:GetModule("Auction")
	local savedMoney = GetMoneyString
	local savedIsCached, savedGetInfo = C_Item.IsItemDataCachedByID, C_Item.GetItemInfo
	local savedDoesExist, savedGetItemID, savedGetStack = C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetStackCount
	local savedAddLine, savedOwner = GameTooltip.AddLine, GameTooltip.SetOwner
	local savedProfit, savedWarning, savedQty = A.db.vendorProfit, A.db.vendorWarning, A.db.vendorQuickBuyQty
	GetMoneyString = function(v) return tostring(v) .. "c" end

	-- SellSummary: quantity == 1 stays compact without repetition
	local s1 = A.SellSummary(306, 400, true, true, 1)
	assert(s1.text == ns.L.AUCTION_SELL_PROFIT:format("+74c") and s1.subtext == nil and #s1.lines == 4,
		"quantity 1 remains compact without total line")

	-- SellSummary: quantity > 1 shows per-item + total profit and full stack calculation
	local s20 = A.SellSummary(306, 400, true, true, 20)
	assert(s20.text == ns.L.AUCTION_SELL_PROFIT:format("+74c"), "quantity 20 per-item text")
	assert(s20.subtext == ns.L.AUCTION_SELL_TOTAL:format(20, "+1480c") and s20.total == 1480,
		"quantity 20 total profit subtext: " .. tostring(s20.subtext))
	assert(#s20.lines == 5, "quantity 20 tooltip has 5 calculation lines")
	assert(s20.lines[1]:find("6120c", 1, true), "merchant total in tooltip")
	assert(s20.lines[2]:find("8000c", 1, true), "gross total in tooltip")
	assert(s20.lines[3]:find("7600c", 1, true), "net total after 5% cut in tooltip")
	assert(s20.lines[5] == ns.L.AUCTION_SELL_RESULT_TOTAL:format(20, "+1480c"), "result total line")

	-- 5% fee rounding on total vs per-unit: 10 * 31c = 310c -> floor(310 * 0.95) = 294c, vendor 250c -> +44c
	local sRound = A.SellSummary(25, 31, true, true, 10)
	assert(sRound.text == ns.L.AUCTION_SELL_PROFIT:format("+4c"), "unit profit 29-25=+4c")
	assert(sRound.total == 44 and sRound.subtext == ns.L.AUCTION_SELL_TOTAL:format(10, "+44c"),
		"total profit uses exact 5% fee on total gross (294 - 250 = 44)")

	-- Below vendor warning with quantity > 1
	local sWarn = A.SellSummary(306, 300, true, true, 5)
	assert(sWarn.text == ns.L.AUCTION_SELL_BELOW:format("−21c"), "warning per item")
	assert(sWarn.subtext == ns.L.AUCTION_SELL_TOTAL:format(5, "−105c") and #sWarn.lines == 6,
		"warning total loss and below-vendor note")

	-- Loss without warning option and quantity > 1
	local sLoss = A.SellSummary(306, 300, true, false, 4)
	assert(sLoss.text == ns.L.AUCTION_SELL_LOSS:format("−21c") and sLoss.subtext == ns.L.AUCTION_SELL_TOTAL:format(4, "−84c"),
		"loss total without warning option")

	-- No price entered with quantity > 1: still shows total merchant value, no fake total profit
	local sNoPrice = A.SellSummary(306, nil, true, true, 10)
	assert(sNoPrice.text == ns.L.AUCTION_SELL_NO_PRICE and sNoPrice.subtext == nil and sNoPrice.lines[1]:find("3060c", 1, true),
		"no price keeps prompt and shows total merchant value")

	-- Commodity unit price cell & buyout cell: quantity > 1 carries total profit, quantity == 1 does not
	A.db.vendorProfit, A.db.vendorWarning = true, true
	local vendors = { [99001] = 300, [99002] = 60 }
	C_Item.IsItemDataCachedByID = function(id) return vendors[id] ~= nil end
	C_Item.GetItemInfo = function(id)
		if vendors[id] then return "Item", nil, nil, nil, nil, nil, nil, nil, nil, nil, vendors[id] end
	end
	local onUnit = uv(A.OnLogin, "OnUnitPriceCell")
	local onMin = uv(A.OnLogin, "OnMinPriceCell")
	local onBuyout = uv(A.OnLogin, "OnBuyoutCell")
	local unitCell1 = NewFrame("Frame")
	onUnit(unitCell1, { itemID = 99001, unitPrice = 200, quantity = 15 })
	assert(unitCell1.foreverPlusVendorProfit and unitCell1.foreverPlusVendorProfit.unit == 100
		and unitCell1.foreverPlusVendorProfit.quantity == 15 and unitCell1.foreverPlusVendorProfit.total == 1500,
		"commodity unit price cell computes total profit for quantity > 1")
	local unitCellSingle = NewFrame("Frame")
	onUnit(unitCellSingle, { itemID = 99001, unitPrice = 200, quantity = 1 })
	assert(unitCellSingle.foreverPlusVendorProfit and unitCellSingle.foreverPlusVendorProfit.unit == 100
		and unitCellSingle.foreverPlusVendorProfit.total == nil,
		"commodity unit price cell omits total for quantity == 1")
	local minCellEmpty = NewFrame("Frame")
	onMin(minCellEmpty, { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 0 })
	assert(rawget(minCellEmpty, "foreverPlusVendorProfit") == nil, "min price cell ignores totalQuantity == 0")
	local buyoutCell = NewFrame("Frame")
	onBuyout(buyoutCell, { itemKey = { itemID = 99002 }, buyoutAmount = 101, quantity = 2 })
	assert(buyoutCell.foreverPlusVendorProfit and buyoutCell.foreverPlusVendorProfit.unit == 10
		and buyoutCell.foreverPlusVendorProfit.total == 19,
		"buyout cell uses exact total (2*60 - 101 = 19)")

	-- Quick buy tooltip: count == 1 stays single profit line, count > 1 adds per-item and total
	local tipLines = {}
	GameTooltip.SetOwner = function() wipe(tipLines) end
	GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = tostring(line) end
	local onQuickCell = uv(A.OnLogin, "OnQuickBuyCell")
	local showQuickTip = uv(onQuickCell, "ShowQuickBuyTooltip")
	A.db.vendorQuickBuyQty = 1
	showQuickTip({ rowData = { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 10 } })
	assert(#tipLines == 2 and tipLines[2] == ns.L.AUCTION_QUICK_BUY_PROFIT:format("100c"),
		"quick buy qty 1 shows compact single profit line")
	A.db.vendorQuickBuyQty = 5
	showQuickTip({ rowData = { itemKey = { itemID = 99001 }, minPrice = 200, totalQuantity = 10 } })
	assert(#tipLines == 3 and tipLines[2] == ns.L.AUCTION_VENDOR_PROFIT:format("100c")
		and tipLines[3] == ns.L.AUCTION_QUICK_BUY_PROFIT_TOTAL:format(5, "500c"),
		"quick buy qty > 1 shows per-item and total profit")

	-- UpdateSellWarning on multisell ItemSellFrame (GetTotalPrice == price * quantity) keeps per-item price
	local updateSell = uv(uv(A.OnLogin, "HookSellFrames"), "UpdateSellWarning")
	C_Item.DoesItemExist = function() return true end
	C_Item.GetItemID = function() return 99001 end
	C_Item.GetStackCount = function() return 1 end
	local itemSellFrame = NewFrame("Frame")
	itemSellFrame.PostButton = NewFrame("Button")
	itemSellFrame.GetItem = function() return {} end
	itemSellFrame.GetQuantity = function() return 3 end
	itemSellFrame.GetPrice = function() return nil, 400 end
	itemSellFrame.GetTotalPrice = function() return 1200 end
	local shownText
	itemSellFrame.CreateFontString = function()
		local fs = NewFrame("FontString")
		fs.SetText = function(_, t) shownText = t end
		return fs
	end
	updateSell(itemSellFrame, 400)
	assert(shownText and shownText:find("+80c", 1, true) and shownText:find("+240c", 1, true),
		"multisell item frame preserves unit price and displays per-item + total: " .. tostring(shownText))

	GetMoneyString = savedMoney
	C_Item.IsItemDataCachedByID, C_Item.GetItemInfo = savedIsCached, savedGetInfo
	C_Item.DoesItemExist, C_Item.GetItemID, C_Item.GetStackCount = savedDoesExist, savedGetItemID, savedGetStack
	GameTooltip.AddLine, GameTooltip.SetOwner = savedAddLine, savedOwner
	A.db.vendorProfit, A.db.vendorWarning, A.db.vendorQuickBuyQty = savedProfit, savedWarning, savedQty
	print("auction stack profit OK")
end)()
-- Auction house: mailbox sale summary (revenue, costs, net profit, refunded deposit, batch total)
;(function()
	local A = ns:GetModule("Auction")
	local saved = {
		GetMoneyString, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo,
		C_Timer.After, ns.Print, PlaySoundFile, issecretvalue,
		A.db.saleMailSummary, A.db.saleSound, ns.db.quiet,
	}
	local now, messages, timers, soundPlays = 200, {}, {}, 0
	GetMoneyString = function(v) return tostring(v) .. "c" end
	GetTime = function() return now end
	PlaySoundFile = function() soundPlays = soundPlays + 1 return true end
	C_Timer.After = function(delay, fn)
		timers[#timers + 1] = { delay = delay, fn = fn }
	end
	ns.Print = function(msg, ...)
		if ns.db and ns.db.quiet then
			return
		end
		if select("#", ...) > 0 then
			msg = msg:format(...)
		end
		messages[#messages + 1] = tostring(msg)
	end

	local inbox = {}
	GetInboxNumItems = function() return #inbox, #inbox end
	GetInboxHeaderInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, m.money, 0, 29, m.items, m.wasRead
	end
	GetInboxInvoiceInfo = function(index)
		local m = inbox[index]
		if not m then return nil end
		return m.invoiceType, m.itemName, m.playerName, m.bid, m.buyout, m.deposit, m.consignment, nil, nil, nil, m.count
	end

	local eventFrame = uv(ns.RegisterEvent, "eventFrame")
	local function Fire(event, ...)
		eventFrame:GetScript("OnEvent")(eventFrame, event, ...)
	end

	ns.db.quiet = false
	A.db.saleMailSummary = true
	A.db.saleSound = false
	A:OnOptionChanged("saleSound")
	A:OnOptionChanged("saleMailSummary")
	A.ResetSaleMailSummaryState()

	-- ReadSaleMail: distinguishes seller mail from buyer/temp/regular mail and separates deposit from costs/net
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 190100, invoiceType = "seller", itemName = "Kupfererz", bid = 200000, deposit = 100, consignment = 10000, count = 20 },
		{ subject = "Auktion gewonnen: Leinenstoff", money = 0, invoiceType = "buyer", itemName = "Leinenstoff", bid = 1200 },
		{ subject = "Auktion erfolgreich: Seidenstoff", money = 0, invoiceType = "seller_temp_invoice", itemName = "Seidenstoff", bid = 3000 },
		{ subject = "Gold von Freund", money = 50000 },
	}
	local m1 = A.ReadSaleMail(1)
	assert(m1 and m1.itemName == "Kupfererz" and m1.count == 20 and m1.revenue == 200000
		and m1.cost == 10000 and m1.deposit == 100 and m1.net == 190000,
		"ReadSaleMail parses seller invoice fields and separates refunded deposit from net profit")
	assert(A.ReadSaleMail(2) == nil and A.ReadSaleMail(3) == nil and A.ReadSaleMail(4) == nil,
		"ReadSaleMail ignores buyer, temp invoice and non-auction mail")

	-- Single sale mail: prints one line, no total line when timer expires
	Fire("MAIL_SHOW")
	A.OnTakeSaleMail(1)
	-- Double-click before server response must not duplicate
	A.OnTakeSaleMail(1)
	table.remove(inbox, 1)
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 1, "single loot prints one chat line")
	assert(messages[1]:find("Kupfererz x20", 1, true) and messages[1]:find("200000c", 1, true)
		and messages[1]:find("10000c", 1, true) and messages[1]:find("190000c", 1, true)
		and messages[1]:find("100c", 1, true),
		"single line contains item+count, revenue, cost, net and separate refunded deposit: " .. messages[1])
	assert(#timers == 1, "batch timer scheduled")
	timers[1].fn()
	assert(#messages == 1, "single mail does not print a redundant total line")

	-- MAIL_FAILED cancels pending take without printing
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Eisenschwert", money = 490000, invoiceType = "seller", itemName = "Eisenschwert", bid = 500000, deposit = 15000, consignment = 25000, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1)
	Fire("MAIL_FAILED")
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "failed take prints nothing")

	-- MAIL_SUCCESS before MAIL_INBOX_UPDATE reports once (no double report on subsequent MAIL_INBOX_UPDATE)
	A.OnTakeSaleMail(1)
	Fire("MAIL_SUCCESS", nil)
	table.remove(inbox, 1)
	Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 1 and messages[1]:find("Eisenschwert", 1, true) and not messages[1]:find("x1", 1, true),
		"MAIL_SUCCESS before MAIL_INBOX_UPDATE prints once without x1 suffix")
	timers[#timers].fn()
	assert(#messages == 1, "still no total line for 1 mail")

	-- Rapid sequence of 3 sale mails (including 2 identical, like OpenAllMail): individual lines + total line
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 5 },
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 5 },
		{ subject = "Auktion erfolgreich: Silbererz", money = 19200, invoiceType = "seller", itemName = "Silbererz", bid = 20000, deposit = 200, consignment = 1000, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	for step = 1, 3 do
		now = now + 0.2
		A.OnTakeSaleMail(1)
		table.remove(inbox, 1)
		Fire("MAIL_INBOX_UPDATE")
		Fire("MAIL_SUCCESS", nil)
	end
	assert(#messages == 3, "three individual lines printed during rapid sequence")
	-- Stale earlier timers must not flush early
	timers[1].fn()
	timers[2].fn()
	assert(#messages == 3, "earlier superseded timers do not flush")
	-- Final timer flushes the total line
	timers[3].fn()
	assert(#messages == 4, "final timer prints total summary line")
	assert(messages[4]:find("3", 1, true) and messages[4]:find("40000c", 1, true)
		and messages[4]:find("2000c", 1, true) and messages[4]:find("38000c", 1, true)
		and messages[4]:find("200c", 1, true),
		"total line sums count, revenue, costs, net and refunded deposit: " .. messages[4])

	-- Closing mailbox flushes active batch immediately and prevents duplicate print when timer later fires
	wipe(messages); wipe(timers)
	inbox = {
		{ subject = "Auktion erfolgreich: Wollstoff", money = 4750, invoiceType = "seller", itemName = "Wollstoff", bid = 5000, deposit = 0, consignment = 250, count = 10 },
		{ subject = "Auktion erfolgreich: Seidenstoff", money = 9500, invoiceType = "seller", itemName = "Seidenstoff", bid = 10000, deposit = 0, consignment = 500, count = 10 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 2, "two lines printed before MAIL_CLOSED")
	Fire("MAIL_CLOSED")
	assert(#messages == 3 and messages[3]:find("15000c", 1, true) and messages[3]:find("750c", 1, true)
		and messages[3]:find("14250c", 1, true),
		"MAIL_CLOSED flushes total line immediately without deposit suffix when deposit == 0")
	timers[#timers].fn()
	assert(#messages == 3, "timer firing after MAIL_CLOSED does not duplicate total line")

	-- Respects ns.db.quiet ("mute all messages")
	wipe(messages); wipe(timers)
	ns.db.quiet = true
	inbox = {
		{ subject = "Auktion erfolgreich: Kupfererz", money = 9500, invoiceType = "seller", itemName = "Kupfererz", bid = 10000, deposit = 0, consignment = 500, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "ns.db.quiet silences sale mail summary")
	ns.db.quiet = false

	-- Option independence: disabling saleSound keeps saleMailSummary working, and vice versa
	wipe(messages); wipe(timers); soundPlays = 0
	A.db.saleSound = true
	A:OnOptionChanged("saleSound")
	A.ResetSaleMailState()
	A.db.saleMailSummary = false
	A:OnOptionChanged("saleMailSummary")
	inbox = {
		{ sender = "AH", subject = "Auktion erfolgreich: Golderz", money = 9500, wasRead = false, invoiceType = "seller", itemName = "Golderz", bid = 10000, deposit = 0, consignment = 500, count = 1 },
	}
	Fire("MAIL_INBOX_UPDATE")
	assert(soundPlays == 1, "disabling saleMailSummary leaves saleSound MAIL_INBOX_UPDATE active")
	A.OnTakeSaleMail(1); table.remove(inbox, 1); Fire("MAIL_INBOX_UPDATE")
	assert(#messages == 0, "saleMailSummary off prints nothing")

	-- Secret values in inbox data are skipped safely without error
	local secretTag = {}
	issecretvalue = function(v) return v == secretTag end
	inbox = {
		{ subject = "Auktion", money = secretTag, invoiceType = "seller", itemName = "Erz", bid = 1000, deposit = 0, consignment = 50, count = 1 },
		{ subject = "Auktion", money = 950, invoiceType = secretTag, itemName = "Erz", bid = 1000, deposit = 0, consignment = 50, count = 1 },
	}
	assert(A.ReadSaleMail(1) == nil and A.ReadSaleMail(2) == nil, "ReadSaleMail skips secret values safely")
	issecretvalue = saved[9]

	GetMoneyString, GetTime, GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = unpack(saved, 1, 5)
	C_Timer.After, ns.Print, PlaySoundFile, issecretvalue = unpack(saved, 6, 9)
	A.db.saleMailSummary, A.db.saleSound, ns.db.quiet = unpack(saved, 10, 12)
	A:OnOptionChanged("saleSound")
	A:OnOptionChanged("saleMailSummary")
	A.ResetSaleMailState()
	A.ResetSaleMailSummaryState()
	print("auction sale mail summary OK")
end)()
;(function()
	-- World map quest starts: profession skill & max-level filtering, nearby pin grouping and combined tooltip.
	local symbols = ns.MapSymbols
	local wm = ns:GetModule("WorldMap")
	local collect = uv(symbols.Count, "Collect")
	local questSource
	for _, source in ipairs(uv(collect, "sources")) do
		if uv(source, "QuestStartAvailable") then questSource = source end
	end
	assert(questSource, "quest start source registered")
	local savedStarts, savedLib = uv(questSource, "questStarts"), ns.QuestieDB.Get
	local savedComplete, savedActive, savedTitle = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetTitleForQuestID
	local savedLevel, savedProfs, savedProfInfo = UnitLevel, GetProfessions, GetProfessionInfo
	local savedOption, savedDisc = wm.db.questStarts, wm.db.discoveries

	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	C_QuestLog.GetLogIndexForQuestID = function() return nil end
	C_QuestLog.GetTitleForQuestID = function() return nil end
	ns.QuestieDB.Get = function() return { Quest = { Get = function() return nil end } } end
	wm.db.questStarts, wm.db.discoveries = true, false
	UnitLevel = function() return 10 end
	-- Player knows Alchemy (171) at rank 50 only; nil hole in slot 1 verifies select() handling.
	GetProfessions = function() return nil, 2 end
	GetProfessionInfo = function(i)
		if i == 2 then return "Alchemie", 1, 50, 75, 0, 0, 171 end
	end

	setuv(questSource, "questStarts", {
		[1429] = {
			-- Two quests on the same NPC + one slightly offset within 0.8% -> merged into 1 pin, duplicate ID deduped.
			{ x = 42.1, y = 65.9, data = { id = 1001, name = "Alpha Quest" } },
			{ x = 42.1, y = 65.9, data = { id = 1002, name = "Beta Quest" } },
			{ x = 42.5, y = 66.1, data = { id = 1001, name = "Alpha Quest" } },
			-- Profession quest met (Alchemy 1) and unmet (Blacksmithing 1, Alchemy 75).
			{ x = 42.2, y = 65.9, data = { id = 1003, name = "Alchemy Intro", skill = 1710001 } },
			{ x = 42.2, y = 65.9, data = { id = 1004, name = "Smithing Intro", skill = 1640001 } },
			{ x = 42.2, y = 65.9, data = { id = 1005, name = "Alchemy Expert", skill = 1710075 } },
			-- Max-level gate: maxLevel 8 hidden at level 10, maxLevel 10 allowed at level 10.
			{ x = 42.2, y = 65.9, data = { id = 1006, name = "Too High", maxLevel = 8 } },
			{ x = 42.2, y = 65.9, data = { id = 1007, name = "Just In Time", maxLevel = 10 } },
			-- Separate location >0.8% away -> second pin.
			{ x = 48.9, y = 41.6, data = { id = 1008, name = "Northshire Quest" } },
		},
	})

	local pins = {}
	questSource(1429, function(x, y, symbol)
		pins[#pins + 1] = { x = x, y = y, symbol = symbol }
	end)
	assert(#pins == 2, "nearby starts merge into one pin while distant ones stay separate (got " .. #pins .. ")")
	assert(#pins[1].symbol.data == 4, "group keeps 4 eligible unique quests (1001, 1002, 1003, 1007)")
	assert(#pins[2].symbol.data == 1 and pins[2].symbol.data[1].id == 1008, "single distant quest stays standalone")

	-- Verify tooltip formatting for single, grouped and >15 capped groups.
	local lines = {}
	local tip = { AddLine = function(_, text) lines[#lines + 1] = text end }
	pins[2].symbol.tooltip(tip, pins[2].symbol)
	assert(lines[1] == "Northshire Quest" and lines[2] == ns.L.WORLDMAP_QUEST_START, "single quest tooltip format")
	lines = {}
	pins[1].symbol.tooltip(tip, pins[1].symbol)
	assert(lines[1] == ns.L.WORLDMAP_QUEST_START_GROUP:format(4), "grouped tooltip header shows count")
	assert(lines[2] == "Alchemy Intro" and lines[3] == "Alpha Quest" and lines[4] == "Beta Quest" and lines[5] == "Just In Time",
		"grouped tooltip sorts titles alphabetically")

	local many = {}
	for i = 1, 18 do many[i] = { id = 2000 + i, name = ("Quest %02d"):format(i) } end
	lines = {}
	pins[1].symbol.tooltip(tip, { data = many })
	assert(lines[1] == ns.L.WORLDMAP_QUEST_START_GROUP:format(18) and lines[17] == ns.L.WORLDMAP_QUEST_START_MORE:format(3),
		"large group tooltips cap lines and show remainder count")

	setuv(questSource, "questStarts", savedStarts)
	ns.QuestieDB.Get, C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetTitleForQuestID =
		savedLib, savedComplete, savedActive, savedTitle
	UnitLevel, GetProfessions, GetProfessionInfo = savedLevel, savedProfs, savedProfInfo
	wm.db.questStarts, wm.db.discoveries = savedOption, savedDisc
	print("quest start filtering & grouping OK")
end)()
dofile("wanderlust.lua")
dofile("bundled.lua")
;(function()
	local voice = ns:GetModule("EmoteVoice")
	local calls = {}
	local saved = voice.Command
	voice.Command = function(msg) calls[#calls + 1] = msg end
	SlashCmdList.FOREVERPLUS("stimme taverne")
	SlashCmdList.FOREVERPLUS("voice epic")
	SlashCmdList.FOREVERPLUS("stimme")
	SlashCmdList.FOREVERPLUS("voice")
	voice.Command = saved
	assert(#calls == 4 and calls[1] == "stimme taverne" and calls[2] == "voice epic"
		and calls[3] == "stimme" and calls[4] == "voice", "slash commands route to EmoteVoice.Command")
end)()
;(function()
	-- Portrait mode activation flashes & natural-decay client sounds: Wanderlust (Brann), RP (Chromie), Berserker (Muradin/Grommash).
	local pm = ns.PortraitModes
	local visuals = ns:GetModule("Visuals")
	local helpers = ns:GetModule("Helpers")
	local flash = uv(pm.StopFlash, "Flash")
	assert(pm and visuals and helpers and flash, "PortraitModes Flash subsystem loaded")

	-- All four new TGA assets exist on disk.
	for _, file in ipairs({ "ModeBrann.tga", "ModeChromie.tga", "ModeMuradin.tga", "ModeGrommash.tga" }) do
		local f = io.open(root .. "/Media/" .. file, "rb")
		assert(f, "missing mode flash texture: " .. file)
		local header = f:read(18)
		f:close()
		assert(header and #header == 18, "valid TGA header for " .. file)
	end

	-- Visuals options expose portraitModeFlash and portraitModeFlashSound with new = true and sensible defaults.
	local flashOpt, soundOpt
	for _, opt in ipairs(visuals.options) do
		if opt.key == "portraitModeFlash" then flashOpt = opt end
		if opt.key == "portraitModeFlashSound" then soundOpt = opt end
	end
	assert(flashOpt and flashOpt.new == true and flashOpt.parent == "playerPortraitWheel" and visuals.db.portraitModeFlash == true,
		"portraitModeFlash defaults on, is child of playerPortraitWheel and marked NEW")
	assert(soundOpt and soundOpt.new == true and soundOpt.parent == "portraitModeFlash" and visuals.db.portraitModeFlashSound == true,
		"portraitModeFlashSound defaults on, is child of portraitModeFlash and marked NEW")

	local savedFlashOpt, savedSoundOpt = visuals.db.portraitModeFlash, visuals.db.portraitModeFlashSound
	local savedCreate, savedPlay, savedPlayFile, savedStop, savedAfter, savedTicker =
		CreateFrame, PlaySound, PlaySoundFile, StopSound, C_Timer.After, C_Timer.NewTicker
	local savedFaction, savedSecret = rawget(_G, "UnitFactionGroup"), rawget(_G, "issecretvalue")
	local savedW, savedH = UIParent.w, UIParent.h
	local savedFrame = flash.frame
	local savedGlobal = rawget(_G, "ForeverPlusModeFlash")

	local WIND_IDS = { [982361] = true, [982363] = true, [982365] = true, [982367] = true }
	local IMPACT_IDS = { [567634] = true, [1324858] = true, [1324859] = true }
	local flashFrame, texturePath, strata, mouseEnabled, ignoreAlpha
	local playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	local nextHandle = 400
	local factionValue, secretToken = "Alliance", nil

	UIParent.w, UIParent.h = 1600, 900
	flash.frame = nil
	ForeverPlusModeFlash = nil
	UnitFactionGroup = function() return factionValue end
	issecretvalue = function(v) return secretToken ~= nil and v == secretToken end
	PlaySound = function(kit, channel)
		nextHandle = nextHandle + 1
		playedKits[#playedKits + 1] = { kit = kit, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	PlaySoundFile = function(id, channel)
		nextHandle = nextHandle + 1
		playedFiles[#playedFiles + 1] = { id = id, channel = channel, handle = nextHandle }
		return true, nextHandle
	end
	StopSound = function(handle) stopped[#stopped + 1] = handle end
	C_Timer.After = function(delay, fn) pendingAfter[#pendingAfter + 1] = { delay = delay, fn = fn } end
	C_Timer.NewTicker = function() return { Cancel = function() end } end
	CreateFrame = function(kind, name, parent, template)
		local f = savedCreate(kind, name, parent, template)
		if name == "ForeverPlusModeFlash" then
			flashFrame = f
			local origStrata = f.SetFrameStrata
			f.SetFrameStrata = function(self, s) strata = s; return origStrata(self, s) end
			local origMouse = f.EnableMouse
			f.EnableMouse = function(self, on) mouseEnabled = on; return origMouse(self, on) end
			f.SetIgnoreParentAlpha = function(_, on) ignoreAlpha = on end
			f.SetSize = function(self, w, h) self.w, self.h = w, h end
			local origCreateTex = f.CreateTexture
			f.CreateTexture = function(self, ...)
				local tex = origCreateTex(self, ...)
				local origSetTex = tex.SetTexture
				tex.SetTexture = function(t, path) texturePath = path; return origSetTex(t, path) end
				return tex
			end
		end
		return f
	end

	-- 1. Wanderlust off -> on triggers Brann Bronzebeard, map open sound, delayed wind gust, natural decay on finish.
	local wander = ns:GetModule("Wanderlust")
	local savedWanderOn = wander.db.enabled
	if pm.IsModeActive("wanderlust") then pm.ToggleMode("wanderlust") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	pm.ToggleMode("wanderlust")
	assert(pm.IsModeActive("wanderlust") and flashFrame and flashFrame:IsShown(), "activating Wanderlust shows Brann")
	assert(strata == "FULLSCREEN_DIALOG" and mouseEnabled == false and ignoreAlpha == true,
		"mode flash uses non-interactive fullscreen overlay ignoring parent alpha")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeBrann.tga]], "Wanderlust shows ModeBrann.tga")
	assert(#playedKits == 1 and playedKits[1].kit == (SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844) and playedKits[1].channel == "SFX",
		"Wanderlust plays map/quest log open sound immediately on SFX")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.22) < 0.001, "Wanderlust schedules wind gust 0.22 s later")
	pendingAfter[1].fn()
	assert(#playedFiles == 1 and WIND_IDS[playedFiles[1].id] and playedFiles[1].channel == "SFX",
		"delayed Wanderlust timer plays verified wind gust on SFX")
	local update = flashFrame:GetScript("OnUpdate")
	assert(type(update) == "function", "mode flash runs OnUpdate while animating")
	update(flashFrame, 0.40)
	local holdW, holdA = flashFrame:GetWidth(), flashFrame:GetAlpha()
	assert(holdW > 700 and math.abs(holdW - flash.baseSize) < 1 and math.abs(holdA - 0.50) < 0.01,
		"Brann fills screen height at half alpha during hold")
	update(flashFrame, 1.35)
	assert(not flashFrame:IsShown() and flashFrame:GetAlpha() == 0 and flashFrame:GetScript("OnUpdate") == nil,
		"Brann finishes cleanly and stops OnUpdate (0 CPU idle)")
	assert(#stopped == 0, "normal completion lets Wanderlust sounds finish decaying naturally")

	-- 2. RP mode off -> on triggers Chromie, spellbook open + delayed quill sound.
	if pm.IsModeActive("rp") then pm.ToggleMode("rp") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	pm.ToggleMode("rp")
	assert(pm.IsModeActive("rp") and flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeChromie.tga]],
		"activating RP mode shows ModeChromie.tga")
	assert(#playedKits == 1 and playedKits[1].kit == (SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN or 829),
		"RP mode plays spellbook open immediately")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.26) < 0.001, "RP mode schedules quill sound 0.26 s later")
	pendingAfter[1].fn()
	assert(#playedKits == 2 and playedKits[2].kit == (SOUNDKIT and SOUNDKIT.IG_WRITE_QUEST or 3093),
		"delayed RP timer plays quill sound")
	-- Deactivating RP mode mid-flash stops the active portrait and sounds.
	local stoppedBeforeRP = #stopped
	pm.ToggleMode("rp")
	assert(not flashFrame:IsShown() and #stopped == stoppedBeforeRP + 2,
		"deactivating RP mode mid-flash stops visual and sound handles")

	-- 3. Berserker mode chooses Muradin for Alliance, Grommash for Horde, and falls back to Muradin on secret faction.
	if pm.IsModeActive("berserker") then pm.ToggleMode("berserker") end
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	factionValue = "Alliance"
	pm.ToggleMode("berserker")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]],
		"Alliance Berserker shows ModeMuradin.tga")
	assert(#playedFiles == 1 and playedFiles[1].id == 567473, "Berserker plays metal unsheathe immediately")
	assert(#pendingAfter == 1 and math.abs(pendingAfter[1].delay - 0.18) < 0.001, "Berserker schedules impact 0.18 s later")
	pendingAfter[1].fn()
	local firstImpactID = playedFiles[2] and playedFiles[2].id
	assert(#playedFiles == 2 and IMPACT_IDS[firstImpactID], "delayed Berserker timer plays verified heavy impact")
	-- Overshoot punch peaks above base size during fade-in end, then settles and finishes cleanly.
	flashFrame:GetScript("OnUpdate")(flashFrame, 0.14)
	assert(flashFrame:GetWidth() > flash.baseSize * 1.02, "Berserker has punch overshoot scale on entry")
	flashFrame:GetScript("OnUpdate")(flashFrame, 1.30)
	assert(not flashFrame:IsShown() and #stopped == 0, "Berserker finishes cleanly with natural sound decay")

	-- Horde Berserker shows Grommash and alternates the impact sound.
	pm.ToggleMode("berserker")
	playedKits, playedFiles, stopped, pendingAfter = {}, {}, {}, {}
	factionValue = "Horde"
	pm.ToggleMode("berserker")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeGrommash.tga]], "Horde Berserker shows ModeGrommash.tga")
	pendingAfter[1].fn()
	assert(IMPACT_IDS[playedFiles[2].id] and playedFiles[2].id ~= firstImpactID,
		"second Berserker impact alternates to another verified hit")

	-- Secret faction falls back cleanly to Muradin without error.
	secretToken = "SECRET_FACTION"
	factionValue = secretToken
	pm.PreviewFlash("berserker")
	assert(texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "secret faction falls back cleanly to Muradin")
	secretToken, factionValue = nil, "Alliance"

	-- 4. Disabling portraitModeFlashSound stops active sounds immediately and keeps future previews silent;
	--    disabling portraitModeFlash hides the active flash and suppresses ToggleMode flashes.
	ns.SetOption("Visuals", "portraitModeFlashSound", false)
	assert(flashFrame:IsShown() and #stopped > 0, "disabling portraitModeFlashSound stops active sounds without hiding portrait")
	ns.SetOption("Visuals", "portraitModeFlash", false)
	assert(not flashFrame:IsShown() and flashFrame:GetScript("OnUpdate") == nil, "disabling portraitModeFlash stops active flash")
	playedKits, playedFiles, pendingAfter = {}, {}, {}
	pm.ToggleMode("berserker")
	pm.ToggleMode("berserker")
	assert(not flashFrame:IsShown() and #playedFiles == 0, "portraitModeFlash = false suppresses activation flash")

	-- 5. Slash commands preview each mode and explicit faction variants.
	ns.SetOption("Visuals", "portraitModeFlash", true)
	SlashCmdList.FOREVERPLUS("brann")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeBrann.tga]], "/fp brann previews Brann")
	SlashCmdList.FOREVERPLUS("chromie")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeChromie.tga]], "/fp chromie previews Chromie")
	SlashCmdList.FOREVERPLUS("grommash")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeGrommash.tga]], "/fp grommash previews Grommash")
	SlashCmdList.FOREVERPLUS("muradin")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "/fp muradin previews Muradin")
	SlashCmdList.FOREVERPLUS("berserker")
	assert(flashFrame:IsShown() and texturePath == [[Interface\AddOns\ForeverPlus\Media\ModeMuradin.tga]], "/fp berserker uses player faction")

	-- 6. Mutual exclusion with Nat Pagle (Helpers.PreviewBear hides mode flash and vice versa).
	helpers.PreviewBear()
	assert(not flashFrame:IsShown(), "starting Nat Pagle flash stops active PortraitModes flash")
	pm.PreviewFlash("wanderlust")
	assert(flashFrame:IsShown(), "starting PortraitModes flash shows Brann cleanly")
	pm.StopFlash()
	helpers.StopBearFlash()

	-- Restore state cleanly.
	if pm.IsModeActive("wanderlust") ~= (savedWanderOn and true or false) then
		ns.SetOption("Wanderlust", "enabled", savedWanderOn)
	end
	if pm.IsModeActive("berserker") then pm.ToggleMode("berserker") end
	ns.SetOption("Visuals", "portraitModeFlashSound", savedSoundOpt)
	ns.SetOption("Visuals", "portraitModeFlash", savedFlashOpt)
	UIParent.w, UIParent.h = savedW, savedH
	CreateFrame, PlaySound, PlaySoundFile, StopSound, C_Timer.After, C_Timer.NewTicker =
		savedCreate, savedPlay, savedPlayFile, savedStop, savedAfter, savedTicker
	UnitFactionGroup, issecretvalue = savedFaction, savedSecret
	flash.frame = savedFrame
	ForeverPlusModeFlash = savedGlobal
	print("portrait mode flashes OK")
end)()
assert(loadfile("emote_voice.lua"))(root, ns)
assert(loadfile("chronicle.lua"))(root, ns, uv)
;(function()
	-- Waypoint: quest objective clicks (questPOI) and arrow designs/colors/preview
	local way = ns:GetModule("Waypoint")
	assert(way.db.questWaypoint == true, "questWaypoint enabled by default")
	assert(way.db.arrowStyle == "standard" and way.db.arrowColor == "DEFAULT", "default arrow style and color")
	assert(type(way.db.arrowCustomColor) == "table", "default custom arrow color")

	local optsByKey, hasColorBtn = {}, false
	for _, opt in ipairs(way.options) do
		if opt.key then optsByKey[opt.key] = opt end
		if opt.type == "button" and opt.func == way.ChooseColor then hasColorBtn = true end
	end
	assert(optsByKey.questWaypoint and optsByKey.questWaypoint.new == true, "questWaypoint has new=true")
	assert(optsByKey.arrowStyle and optsByKey.arrowStyle.new == true, "arrowStyle has new=true")
	assert(optsByKey.arrowColor and optsByKey.arrowColor.new == true, "arrowColor has new=true")
	assert(hasColorBtn, "custom arrow color picker button present")
	assert(#optsByKey.arrowStyle.values() == 5, "5 arrow designs available")
	local colorValues = optsByKey.arrowColor.values()
	assert(#colorValues == 11, "gold, 9 class colors plus custom available")
	assert(colorValues[1][1] == "DEFAULT" and colorValues[2][1] == "WARRIOR" and colorValues[10][1] == "HUNTER"
		and colorValues[11][1] == "CUSTOM", "gold first, class colors in Forever order, custom last")
	assert(colorValues[8][2]:find("Mage", 1, true), "class color named after the class")

	-- Old color presets become the same custom color
	local legacyDb = { arrowColor = "BLUE", arrowCustomColor = { r = 1, g = 0.82, b = 0 } }
	way.MigrateArrowColor(legacyDb)
	assert(legacyDb.arrowColor == "CUSTOM" and math.abs(legacyDb.arrowCustomColor.g - 0.78) < 1e-6,
		"old BLUE preset migrates to custom color")
	legacyDb = { arrowColor = "MAGE" }
	way.MigrateArrowColor(legacyDb)
	assert(legacyDb.arrowColor == "MAGE" and legacyDb.arrowCustomColor == nil, "class color left as is")

	-- Quest objective click tests
	local savedCVar, savedShift = GetCVarBool, IsShiftKeyDown
	local savedCan, savedSet, savedClear = C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint
	local savedHas, savedGet, savedBest, savedInfo = C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.GetBestMapForUnit, C_Map.GetMapInfo
	local savedUiPoint, savedSuper, savedPrint = UiMapPoint, C_SuperTrack, ns.Print
	local savedQuestsOnMap, savedNextWp, savedNextWpMap, savedTitle =
		C_QuestLog.GetQuestsOnMap, C_QuestLog.GetNextWaypoint, C_QuestLog.GetNextWaypointForMap, C_QuestLog.GetTitleForQuestID
	local savedContinent = Enum.UIMapType.Continent

	local questPOIOn, shiftDown = false, false
	local userWp, superUserWp, superQuestID
	GetCVarBool = function(name) return name == "questPOI" and questPOIOn or false end
	IsShiftKeyDown = function() return shiftDown end
	Enum.UIMapType.Continent = 2
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.SetUserWaypoint = function(pt) userWp = pt return true end
	C_Map.ClearUserWaypoint = function() userWp = nil end
	C_Map.HasUserWaypoint = function() return userWp ~= nil end
	C_Map.GetUserWaypoint = function() return userWp end
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(id) return { mapID = id, mapType = id == 1415 and 2 or 3, name = "Zone" .. tostring(id) } end
	UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
	C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(v) superUserWp = v end,
		GetSuperTrackedQuestID = function() return superQuestID end,
	}
	C_QuestLog.GetTitleForQuestID = function(id) return id == 33 and "Wolves Across the Border" or nil end
	C_QuestLog.GetQuestsOnMap = function(mapID)
		if mapID == 1429 then
			return { { questID = 33, x = 0.46, y = 0.62 } }
		end
		return {}
	end
	C_QuestLog.GetNextWaypoint = function(id)
		if id == 33 then return 1429, 0.48, 0.65 end
	end
	C_QuestLog.GetNextWaypointForMap = function() return nil end
	ns.Print = function() end

	local zonePin = {
		GetQuestID = function() return 33 end,
		GetMap = function() return { GetMapID = function() return 1429 end } end,
		GetPosition = function() return 0.47, 0.63 end,
	}
	local continentPin = {
		GetQuestID = function() return 33 end,
		GetMap = function() return { GetMapID = function() return 1415 end } end,
		GetPosition = function() return 0.50, 0.50 end,
	}
	local trackerBtn = { GetQuestID = function() return 33 end }

	-- Disabled when questPOI CVar is off
	way.Clear()
	superQuestID, questPOIOn = 33, false
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "no waypoint when Blizzard questPOI is disabled")

	-- Disabled when questWaypoint option is off
	questPOIOn, way.db.questWaypoint = true, false
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "no waypoint when questWaypoint option is disabled")
	way.db.questWaypoint = true

	-- Ignored for right-click and shift-click
	way.OnQuestPOIClick(zonePin, "RightButton")
	assert(way.Target() == nil, "right-click ignored")
	shiftDown = true
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil, "shift-click ignored")
	shiftDown = false

	-- Left-click on zone map pin uses unquantized GetQuestsOnMap coordinates and preserves quest super-tracking
	local wind = ns:GetModule("GuidingWind")
	local savedWindEnabled = wind and wind.db and wind.db.enabled
	if wind and wind.db then wind.db.enabled = true end
	superUserWp = nil
	way.OnQuestPOIClick(zonePin, "LeftButton")
	local goal = way.Target()
	assert(goal and goal.mapID == 1429 and math.abs(goal.x - 0.46) < 1e-6 and math.abs(goal.y - 0.62) < 1e-6
		and goal.name == "Wolves Across the Border" and goal.questID == 33, "zone pin sets quest waypoint")
	assert(userWp and userWp.uiMapID == 1429 and superUserWp == nil, "sets user waypoint without overriding quest super-track")
	assert(not (_G.ForeverPlusWaypointArrow and _G.ForeverPlusWaypointArrow:IsShown()),
		"active GuidingWind keeps the waypoint arrow hidden even after quest objective click")
	if wind and wind.db then wind.db.enabled = false end

	-- Clicking the same pin again (Blizzard clears super-tracking) clears the quest waypoint
	superQuestID = 0
	way.OnQuestPOIClick(zonePin, "LeftButton")
	assert(way.Target() == nil and userWp == nil, "deselecting quest objective clears its waypoint")

	-- Continent pin resolves to the zone map via GetNextWaypoint
	superQuestID = 33
	way.OnQuestPOIClick(continentPin, "LeftButton")
	goal = way.Target()
	assert(goal and goal.mapID == 1429 and math.abs(goal.x - 0.48) < 1e-6 and math.abs(goal.y - 0.65) < 1e-6,
		"continent pin resolves to zone waypoint")

	-- Tracker/log POI button (no GetMap) resolves via GetNextWaypoint
	way.Clear()
	way.OnQuestPOIClick(trackerBtn, "LeftButton")
	goal = way.Target()
	assert(goal and goal.mapID == 1429 and goal.questID == 33, "tracker POI button sets quest waypoint")

	-- QUEST_TURNED_IN clears matching quest waypoint, leaves unrelated ones intact
	local listeners = uv(ns.RegisterEvent, "listeners")
	listeners.QUEST_TURNED_IN[way](way, "QUEST_TURNED_IN", 999)
	assert(way.Target() ~= nil, "unrelated quest turn-in keeps waypoint")
	listeners.QUEST_TURNED_IN[way](way, "QUEST_TURNED_IN", 33)
	assert(way.Target() == nil, "matching quest turn-in clears quest waypoint")

	-- Tooltip hint on MapCanvas.QuestPin.OnEnter
	local savedTipOwner, savedTipShown, savedTipAdd = GameTooltip.GetOwner, GameTooltip.IsShown, GameTooltip_AddInstructionLine
	local tipLines = {}
	GameTooltip.IsShown = function() return true end
	GameTooltip.GetOwner = function() return zonePin end
	GameTooltip_AddInstructionLine = function(_, text) tipLines[#tipLines + 1] = text end
	way.OnQuestPinEnter(nil, zonePin, 33)
	assert(#tipLines == 1 and tipLines[1] == ns.L.WAYPOINT_QUEST_CLICK, "quest pin tooltip adds click hint")
	questPOIOn = false
	way.OnQuestPinEnter(nil, zonePin, 33)
	assert(#tipLines == 1, "no tooltip hint when questPOI is off")
	GameTooltip.GetOwner, GameTooltip.IsShown, GameTooltip_AddInstructionLine = savedTipOwner, savedTipShown, savedTipAdd

	-- HookQuestPOI installs post-hook on POIButtonMixin.OnClick once
	local savedMixin, savedHook = rawget(_G, "POIButtonMixin"), hooksecurefunc
	local hookCount = 0
	_G.POIButtonMixin = { OnClick = function() end }
	hooksecurefunc = function(tbl, method)
		if tbl == _G.POIButtonMixin and method == "OnClick" then hookCount = hookCount + 1 end
	end
	way.HookQuestPOI()
	way.HookQuestPOI()
	assert(hookCount == 1, "HookQuestPOI hooks POIButtonMixin.OnClick once")
	_G.POIButtonMixin, hooksecurefunc = savedMixin, savedHook

	-- Arrow designs, colors, custom color picker, corpse tint and preview
	local arrow = _G.ForeverPlusWaypointArrow
	local tex = arrow.Arrow
	local lastAtlas, lastTex, lastCoords, lastDesat
	local savedSetAtlas, savedSetTex, savedSetCoords, savedSetDesat = tex.SetAtlas, tex.SetTexture, tex.SetTexCoord, tex.SetDesaturated
	local savedNewTimer, savedPicker = ns.NewTimer, ColorPickerFrame
	local savedGhost = rawget(_G, "UnitIsGhost")
	local previewCallback, pickerSpec, pickerShown = nil, nil, false
	tex.SetAtlas = function(_, a) lastAtlas, lastTex, lastCoords = a, nil, nil end
	tex.SetTexture = function(_, t) lastTex, lastAtlas = t, nil end
	tex.SetTexCoord = function(_, l, r, t, b) lastCoords = { l, r, t, b } end
	tex.SetDesaturated = function(_, d) lastDesat = d end
	ns.NewTimer = function(_, _, fn)
		previewCallback = fn
		return { Cancel = function() previewCallback = nil end }
	end

	-- Standard + Default keeps original untinted atlas
	arrow.lastStyleKey, arrow.lastDesat, arrow.lastR = nil, nil, nil
	way.db.arrowStyle, way.db.arrowColor = "standard", "DEFAULT"
	way:OnOptionChanged("arrowStyle")
	assert(arrow:IsShown(), "preview shows arrow when no waypoint is active")
	assert(lastAtlas == "Navigation-Tracked-Arrow" and lastDesat == false
		and tex.vertexColor[1] == 1 and tex.vertexColor[2] == 1 and tex.vertexColor[3] == 1, "standard default untinted")
	assert(previewCallback ~= nil, "preview timer scheduled")
	previewCallback()
	assert(not arrow:IsShown(), "preview hides arrow after timer expires")

	-- Standard + class color desaturates and tints with the client's class color
	local savedGetClassColor = C_ClassColor.GetClassColor
	C_ClassColor.GetClassColor = function(classFile)
		if classFile == "MAGE" then
			return { GetRGB = function() return 0.25, 0.78, 0.92 end }
		end
	end
	way.db.arrowColor = "MAGE"
	way:OnOptionChanged("arrowColor")
	assert(lastDesat == true and math.abs(tex.vertexColor[1] - 0.25) < 0.01
		and math.abs(tex.vertexColor[3] - 0.92) < 0.01, "standard mage color tints desaturated atlas")
	way.db.arrowColor = "WARRIOR"
	way:OnOptionChanged("arrowColor")
	assert(math.abs(tex.vertexColor[1] - 1) < 0.01 and math.abs(tex.vertexColor[2] - 0.82) < 0.01
		and math.abs(tex.vertexColor[3] - 0) < 0.01, "unknown class color falls back to gold")
	C_ClassColor.GetClassColor = savedGetClassColor

	-- Custom arrow designs load Media\WaypointArrows.tga with 1/256 UV inset
	local expectedTiles = {
		classic = { 0, 0 }, compass = { 1, 0 }, chevron = { 0, 1 }, rune = { 1, 1 },
	}
	for styleKey, pos in pairs(expectedTiles) do
		way.db.arrowStyle = styleKey
		way:OnOptionChanged("arrowStyle")
		assert(lastTex and lastTex:find("WaypointArrows.tga", 1, true), styleKey .. " uses custom sheet")
		assert(lastDesat == false, styleKey .. " is not desaturated")
		local inset = 1 / 256
		assert(math.abs(lastCoords[1] - (pos[1] * 0.5 + inset)) < 1e-6
			and math.abs(lastCoords[2] - ((pos[1] + 1) * 0.5 - inset)) < 1e-6
			and math.abs(lastCoords[3] - (pos[2] * 0.5 + inset)) < 1e-6
			and math.abs(lastCoords[4] - ((pos[2] + 1) * 0.5 - inset)) < 1e-6, styleKey .. " UV coords inset")
	end

	-- Corpse run keeps user style and forces spectral blue tint
	UnitIsGhost = function() return true end
	way.Refresh()
	assert(lastTex and lastTex:find("WaypointArrows.tga", 1, true), "corpse keeps custom arrow style")
	assert(math.abs(tex.vertexColor[1] - 0.40) < 0.01 and math.abs(tex.vertexColor[2] - 0.85) < 0.01
		and math.abs(tex.vertexColor[3] - 1.00) < 0.01, "corpse uses spectral blue color")
	UnitIsGhost = function() return false end

	-- Color picker updates custom color and cancel restores previous state
	local pickedRGB = { 0.2, 0.9, 0.4 }
	ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, spec) pickerSpec = spec pickerShown = true end,
		GetColorRGB = function() return pickedRGB[1], pickedRGB[2], pickedRGB[3] end,
		IsShown = function() return pickerShown end,
	}
	way.db.arrowStyle, way.db.arrowColor = "classic", "MAGE"
	way.db.arrowCustomColor = { r = 1, g = 0.82, b = 0 }
	way.ChooseColor()
	assert(pickerSpec and pickerSpec.hasOpacity == false, "color picker opened without opacity")
	pickerSpec.swatchFunc()
	assert(way.db.arrowColor == "CUSTOM" and math.abs(tex.vertexColor[2] - 0.9) < 1e-6, "swatch applies custom color")
	pickerShown = false
	pickerSpec.cancelFunc()
	assert(way.db.arrowColor == "MAGE" and math.abs(way.db.arrowCustomColor.r - 1) < 1e-6, "cancel restores previous color")

	-- Middle-click during preview closes preview cleanly
	way.Preview(false)
	assert(arrow:IsShown(), "preview active")
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	assert(not arrow:IsShown(), "middle-click closes preview")

	-- Inline preview images in design dropdown & large preview panel when SettingsPanel is open
	way.db.arrowColor, way.db.arrowCustomColor = "CUSTOM", { r = 0.27, g = 0.78, b = 1.00 }
	local styleEntries = optsByKey.arrowStyle.values()
	assert(styleEntries[1][2]:find("Navigation-Tracked-Arrow", 1, true) or styleEntries[1][2]:find("MiniMap-QuestArrow", 1, true),
		"standard design dropdown entry carries inline arrow preview")
	assert(styleEntries[2][2]:find("|TInterface\\AddOns\\ForeverPlus\\Media\\WaypointArrows.tga:18:18:0:0:256:256:1:127:1:127:69:199:255|t", 1, true),
		"classic dropdown entry carries tinted inline sprite preview")
	assert(styleEntries[5][2]:find(":129:255:129:255:69:199:255|t", 1, true),
		"rune dropdown entry uses bottom-right tile in current color")

	local savedSettingsShown, savedSettingsHook = SettingsPanel.IsShown, SettingsPanel.HookScript
	local settingsHideFn
	SettingsPanel.IsShown = function() return true end
	SettingsPanel.HookScript = function(_, script, fn)
		if script == "OnHide" then settingsHideFn = fn end
	end
	way.db.arrowStyle, way.db.arrowColor = "rune", "CUSTOM"
	way.db.arrowCustomColor = { r = 1.00, g = 0.52, b = 0.15 }
	way:OnOptionChanged("arrowStyle")
	local previewFrame = _G.ForeverPlusWaypointPreview
	assert(previewFrame and previewFrame:IsShown(), "large preview panel opens beside SettingsPanel")
	assert(previewFrame.Arrow and previewFrame.Arrow.vertexColor
		and math.abs(previewFrame.Arrow.vertexColor[1] - 1.00) < 0.01
		and math.abs(previewFrame.Arrow.vertexColor[2] - 0.52) < 0.01, "preview panel renders chosen arrow tint")
	assert(settingsHideFn ~= nil, "SettingsPanel OnHide hook installed")
	settingsHideFn()
	assert(not previewFrame:IsShown(), "closing SettingsPanel hides preview panel")

	-- Regression: changing design while standing still re-applies arrow rotation, and middle-click clears active waypoint
	local savedPlayerPos, savedFacing = C_Map.GetPlayerMapPosition, GetPlayerFacing
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
	GetPlayerFacing = function() return 0 end
	way.Set(80, 50, "East")
	arrow:GetScript("OnUpdate")(arrow, 0.2)
	local rotBefore = tex.rotation
	assert(rotBefore and math.abs(rotBefore + math.pi / 2) < 1e-4, "active waypoint points east")
	tex.rotation = 0 -- simulate WoW resetting texture rotation on SetTexCoord/SetAtlas
	way.db.arrowStyle = "compass"
	way:OnOptionChanged("arrowStyle")
	assert(previewFrame:IsShown(), "preview panel opens alongside active waypoint in settings")
	arrow:GetScript("OnUpdate")(arrow, 0.2)
	assert(math.abs(tex.rotation - rotBefore) < 1e-4, "style change re-applies arrow rotation even while standing still")

	local click, doubleClick = arrow:GetScript("OnClick"), arrow:GetScript("OnDoubleClick")
	assert(way.db.clickArrowStyle and optsByKey.clickArrowStyle, "arrow click controls enabled by default")
	local savedList, savedGetSetting = SettingsPanel.GetSettingsList, Settings.GetSetting
	local setting, menu, label = {}, {}, nil
	local dropdown = {
		GetMenuDescription = function() return menu end,
		UpdateToMenuSelections = function(_, description)
			assert(description == menu)
			label = way.db.arrowStyle
		end,
	}
	local row = { GetSetting = function() return setting end, Control = { Dropdown = dropdown } }
	Settings.GetSetting = function(variable)
		if variable == "ForeverPlus_Waypoint_arrowStyle" then return setting end
	end
	SettingsPanel.GetSettingsList = function()
		return { ScrollBox = { ForEachFrame = function(_, visit) visit({}) visit(row) end } }
	end
	local goal = way.Target()
	for _, key in ipairs({ "chevron", "rune", "standard", "classic", "compass" }) do
		click(arrow, "LeftButton")
		assert(way.db.arrowStyle == key and arrow.lastStyleKey == key and label == key, "single-click selects and renders " .. key)
	end
	for _, entry in ipairs(way.ARROW_STYLES) do
		ns.SetOption("Waypoint", "arrowStyle", entry.key)
		click(arrow, "LeftButton")
		doubleClick(arrow, "LeftButton")
		assert(way.db.arrowStyle == "standard" and lastAtlas == "Navigation-Tracked-Arrow" and label == "standard", "double-click resets " .. entry.key)
	end
	assert(way.db.arrowColor == "CUSTOM" and way.Target() == goal, "design clicks preserve color and destination")
	ns.SetOption("Waypoint", "arrowStyle", "rune")
	click(arrow, "RightButton")
	doubleClick(arrow, "RightButton")
	assert(way.db.arrowStyle == "rune", "right-click leaves design alone")
	ns.SetOption("Waypoint", "clickArrowStyle", false)
	click(arrow, "LeftButton")
	doubleClick(arrow, "LeftButton")
	assert(way.db.arrowStyle == "rune", "disabled design gestures leave selection alone")
	ns.SetOption("Waypoint", "clickArrowStyle", true)
	SettingsPanel.GetSettingsList, Settings.GetSetting = savedList, savedGetSetting
	arrow:GetScript("OnMouseUp")(arrow, "MiddleButton")
	assert(way.Target() == nil, "middle-click on active arrow clears waypoint even while preview panel is shown")
	settingsHideFn()
	C_Map.GetPlayerMapPosition, GetPlayerFacing = savedPlayerPos, savedFacing
	SettingsPanel.IsShown, SettingsPanel.HookScript = savedSettingsShown, savedSettingsHook

	-- Restore all mocked state
	way.Clear()
	if wind and wind.db then wind.db.enabled = savedWindEnabled end
	way.db.questWaypoint, way.db.arrowStyle, way.db.arrowColor = true, "standard", "DEFAULT"
	way.db.arrowCustomColor = { r = 1, g = 0.82, b = 0 }
	tex.SetAtlas, tex.SetTexture, tex.SetTexCoord, tex.SetDesaturated = savedSetAtlas, savedSetTex, savedSetCoords, savedSetDesat
	ns.NewTimer, ColorPickerFrame, UnitIsGhost = savedNewTimer, savedPicker, savedGhost
	GetCVarBool, IsShiftKeyDown = savedCVar, savedShift
	C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.ClearUserWaypoint = savedCan, savedSet, savedClear
	C_Map.HasUserWaypoint, C_Map.GetUserWaypoint, C_Map.GetBestMapForUnit, C_Map.GetMapInfo = savedHas, savedGet, savedBest, savedInfo
	UiMapPoint, C_SuperTrack, ns.Print = savedUiPoint, savedSuper, savedPrint
	C_QuestLog.GetQuestsOnMap, C_QuestLog.GetNextWaypoint, C_QuestLog.GetNextWaypointForMap, C_QuestLog.GetTitleForQuestID =
		savedQuestsOnMap, savedNextWp, savedNextWpMap, savedTitle
	Enum.UIMapType.Continent = savedContinent
	print("waypoint quest POI & arrow styles OK")
end)()
;(function()
	-- WorldReactions: surfacing water droplets, campfire warmth/embers, worn armor clinking.
	local wr = ns:GetModule("WorldReactions")
	assert(wr, "WorldReactions module loaded")
	assert(wr.db.enabled == true and wr.db.waterDrops == true and wr.db.campfireGlow == true
		and wr.db.weaponSheathSound == nil and wr.db.armorRattle == true and wr.db.intensity == 75,
		"WorldReactions sensible defaults without weapon sheath sound")
	assert(wr.StepSheath == nil and wr.WeaponSoundKind == nil and wr.PlayWeaponSound == nil,
		"weapon sheath sound helpers removed")

	-- Registered on a settings page under Roleplay & every keyed option carries new = true.
	local foundOnPage = false
	for _, page in ipairs(ns.SettingsPages or {}) do
		for _, entry in ipairs(page) do
			if entry[1] == "WorldReactions" then foundOnPage = true end
		end
	end
	assert(foundOnPage, "WorldReactions is registered on a settings page")
	local buttonCount = 0
	for _, opt in ipairs(wr.options or {}) do
		assert(opt.key ~= "weaponSheathSound", "weaponSheathSound option removed")
		if opt.key then
			assert(opt.new == true, "new WorldReactions option carries new=true: " .. tostring(opt.key))
		elseif opt.type == "button" then
			buttonCount = buttonCount + 1
		end
	end
	assert(buttonCount == 3, "WorldReactions provides preview/test buttons for all three reactions")

	-- 1. Water emergence state machine
	local ws = { graceUntil = 5 }
	assert(not wr.StepWater(ws, true, true, 1.0, false), "water suppressed during login grace")
	assert(not wr.StepWater(ws, false, false, 4.0, false), "emerging during login grace stays silent")
	assert(not wr.StepWater(ws, true, true, 10.0, false), "diving down does not trigger yet")
	assert(not wr.StepWater(ws, false, true, 10.2, false), "brief dip below 0.35s does not trigger")
	assert(not wr.StepWater(ws, true, true, 11.0, false), "submerge again")
	assert(wr.StepWater(ws, false, true, 11.6, false), "surfacing after >= 0.35s triggers droplets")
	assert(not wr.StepWater(ws, false, false, 12.2, false), "climbing out within 4s cooldown does not double-trigger")
	assert(not wr.StepWater(ws, false, true, 17.0, false), "start surface swim after cooldown")
	assert(wr.StepWater(ws, false, false, 17.8, false), "exiting swim after >= 0.5s triggers droplets")
	assert(not wr.StepWater(ws, true, true, 25.0, false), "submerge before death")
	assert(not wr.StepWater(ws, false, false, 26.0, true), "blocked state (dead/taxi/flying) suppresses water trigger")

	-- 2. Worn armor durability & clinking state machine
	local savedDurability = GetInventoryItemDurability
	local slotDura = { [1] = { 40, 100 }, [5] = { 25, 100 }, [7] = { 80, 100 } }
	GetInventoryItemDurability = function(slot)
		local pair = slotDura[slot]
		if pair then return pair[1], pair[2] end
	end
	assert(wr.LowestArmorDurability() == 25, "lowest armor durability picks minimum across armor slots")
	local as = { graceUntil = 2 }
	assert(not wr.StepArmor(as, 20, false, 1.0, false), "login with already worn armor does not rattle immediately")
	assert(not wr.StepArmor(as, 50, false, 5.0, false), "repaired armor does not rattle")
	assert(wr.StepArmor(as, 28, false, 10.0, false), "dropping below 30% rattles once")
	assert(not wr.StepArmor(as, 25, false, 15.0, false), "further drop within 25s cooldown stays silent")
	assert(not wr.StepArmor(as, 25, true, 40.0, false), "jumping while worn starts fall timer")
	assert(wr.StepArmor(as, 25, false, 40.5, false), "landing after >= 0.15s while worn rattles after cooldown")
	assert(not wr.StepArmor(as, 60, true, 70.0, false) and not wr.StepArmor(as, 60, false, 70.6, false),
		"landing with healthy armor never rattles")

	-- 4. Overlay visuals, audio playback, campfire aura/proximity & combat fade
	local savedPlayFile, savedPlaySound, savedAfter = PlaySoundFile, PlaySound, ns.After
	local savedSecrets, savedUnitAuras, savedCombat = C_Secrets, C_UnitAuras, UnitAffectingCombat
	local savedGetTime, savedMapBest, savedMapPos, savedMapSize = GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize
	local playedFiles, playedKits, pendingAfter = {}, {}, {}
	local nowTime = 100
	GetTime = function() return nowTime end
	PlaySoundFile = function(id) playedFiles[#playedFiles + 1] = id return true, #playedFiles end
	PlaySound = function(kit) playedKits[#playedKits + 1] = kit return true end
	ns.After = function(_, _, fn) pendingAfter[#pendingAfter + 1] = fn end
	local combatFlag = false
	UnitAffectingCombat = function() return combatFlag end

	-- Trigger water runoff preview & verify receding lens sheet + slender downward-running rivulets
	wr.TriggerWater(true)
	local ov = _G.ForeverPlusWorldReactions
	assert(ov and ov:IsShown() and wr.GetState().dropsActive, "water trigger shows click-through overlay")
	assert(#playedFiles == 1, "splash sound played immediately")
	assert(#pendingAfter == 1, "drip sound scheduled")
	pendingAfter[1]()
	assert(#playedFiles == 2, "drip follow-up sound played")

	local dropPoolRef = uv(wr.TriggerWater, "dropPool")
	local sheetTexRef = uv(wr.TriggerWater, "sheetTexture")
	assert(sheetTexRef, "receding lens water sheet texture created")
	local recordedSize, recordedY = {}, {}
	for i, d in ipairs(dropPoolRef) do
		d.texture.SetSize = function(_, w, h) recordedSize[i] = { w = w, h = h } end
		d.texture.SetPoint = function(_, _, _, _, _, y) recordedY[i] = y end
	end
	local sheetY = nil
	sheetTexRef.SetPoint = function(_, _, _, _, _, y) sheetY = y end

	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(ov:IsShown() and sheetTexRef:IsShown(), "receding water sheet is visible right after surfacing")
	local firstSheetY = sheetY
	local firstY = {}
	local shownCount = 0
	for i, d in ipairs(dropPoolRef) do
		if d.texture:IsShown() then
			shownCount = shownCount + 1
			firstY[i] = recordedY[i]
			assert(recordedSize[i] and recordedSize[i].h > recordedSize[i].w * 2.5,
				"rivulet renders as a slender vertical streak rather than a round bubble")
		end
	end
	assert(shownCount > 0, "at least one water rivulet is visible after 0.3s")
	for _ = 1, 2 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(sheetY and firstSheetY and sheetY < firstSheetY, "receding water sheet slides downward across the lens")
	local movedDown = false
	for i, prevY in pairs(firstY) do
		if dropPoolRef[i].texture:IsShown() and recordedY[i] and recordedY[i] < prevY then
			movedDown = true
			break
		end
	end
	assert(movedDown, "water rivulets run downward over time")
	-- After WATER_SHEET_DURATION (0.72s) the receding sheet hides while rivulets finish running down
	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(not sheetTexRef:IsShown(), "receding water sheet finishes and hides before rivulets end")
	for _ = 1, 30 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end
	assert(not wr.GetState().dropsActive and not ov:IsShown() and not ov:GetScript("OnUpdate"),
		"overlay hides and clears OnUpdate once water runoff finishes")

	-- Surfacing in combat restricts active rivulets to the outer screen edges
	combatFlag = true
	wr:Apply()
	wr.TriggerWater(false)
	local activeCombatDrops = 0
	for _, d in ipairs(dropPoolRef) do
		if d.active then
			activeCombatDrops = activeCombatDrops + 1
			assert(d.x <= 0.16 or d.x >= 0.84, "combat surfacing keeps rivulets near outer edges: x=" .. tostring(d.x))
		end
	end
	assert(activeCombatDrops > 0 and activeCombatDrops < #dropPoolRef,
		"combat surfacing uses a reduced outer-edge subset of rivulets")
	combatFlag = false
	wr:Apply()
	for _ = 1, 35 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end

	-- Campfire via Cozy Fire aura 7353 & combat suppression + secret aura safety
	local cozyAura = { spellId = 7353 }
	local secretAuras = false
	C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end }
	C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return id == 7353 and cozyAura or nil end }
	wr:Apply()
	assert(wr.GetState().hasCozyFireAura and wr.GetState().campfireDesired, "Cozy Fire buff activates campfire glow")
	assert(ov:IsShown(), "campfire glow shows overlay")
	for _ = 1, 5 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(wr.GetState().campfireAlpha > 0.5, "campfire glow fades in smoothly")

	-- Secret aura restriction & secret UNIT_AURA unit/aura values keep last known state without throwing
	local evFrame = uv(ns.RegisterEvent, "eventFrame")
	local function FireEvent(event, ...)
		evFrame:GetScript("OnEvent")(evFrame, event, ...)
	end
	secretAuras = true
	assert(upvalue(ns.RegisterEvent, "listeners").UNIT_AURA[wr], "UNIT_AURA registered for campfire aura tracking")
	FireEvent("UNIT_AURA", "player")
	assert(wr.GetState().hasCozyFireAura, "restricted auras preserve last known Cozy Fire state safely")
	secretAuras = false
	local savedSecret = ns.Secret
	local secretToken = {}
	ns.Secret = function(v) return v == secretToken or savedSecret(v) end
	FireEvent("UNIT_AURA", secretToken)
	assert(wr.GetState().hasCozyFireAura, "secret UNIT_AURA unit token is ignored without comparing")
	cozyAura = secretToken
	FireEvent("UNIT_AURA", "player")
	assert(wr.GetState().hasCozyFireAura, "secret aura returned by GetPlayerAuraBySpellID preserves state safely")
	cozyAura = { spellId = 7353 }
	ns.Secret = savedSecret

	-- Disabling waterDrops while water runoff and campfire glow are both active hides water textures immediately
	pendingAfter = {}
	playedFiles = {}
	wr.TriggerWater(false)
	for _ = 1, 3 do
		ov:GetScript("OnUpdate")(ov, 0.1)
	end
	assert(wr.GetState().dropsActive and wr.GetState().campfireDesired, "both water runoff and campfire active together")
	local anyDropShown = false
	for _, d in ipairs(dropPoolRef) do
		if d.texture:IsShown() then anyDropShown = true break end
	end
	assert(anyDropShown and sheetTexRef:IsShown(), "water rivulet and sheet textures visible during animation")
	ns.SetOption("WorldReactions", "waterDrops", false)
	assert(not sheetTexRef:IsShown(), "disabling waterDrops hides receding water sheet immediately")
	for _, d in ipairs(dropPoolRef) do
		assert(not d.texture:IsShown(), "disabling waterDrops hides all rivulet textures immediately even while campfire stays active")
	end
	if pendingAfter[1] then pendingAfter[1]() end
	assert(#playedFiles == 1, "disabling waterDrops cancels scheduled follow-up drip sound")
	ns.SetOption("WorldReactions", "waterDrops", true)

	-- Combat suppresses campfire glow cleanly
	combatFlag = true
	FireEvent("PLAYER_REGEN_DISABLED")
	assert(not wr.GetState().campfireDesired, "entering combat fades out campfire glow")
	for _ = 1, 6 do
		local fn = ov:GetScript("OnUpdate")
		if fn then fn(ov, 0.1) end
	end
	assert(wr.GetState().campfireAlpha == 0 and not ov:IsShown(), "campfire glow fully hidden in combat")
	combatFlag = false
	FireEvent("PLAYER_REGEN_ENABLED")
	assert(wr.GetState().campfireDesired, "leaving combat near campfire restores glow")

	-- Campfire proximity via UNIT_SPELLCAST_SUCCEEDED (works even with Minimap campfires disabled)
	cozyAura = nil
	FireEvent("UNIT_AURA", "player")
	assert(not wr.GetState().campfireDesired, "losing Cozy Fire turns off campfire glow")
	local playerX, playerY = 0.50, 0.50
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end
	C_Map.GetMapWorldSize = function() return 1000, 1000 end
	assert(upvalue(ns.RegisterEvent, "listeners").UNIT_SPELLCAST_SUCCEEDED[wr],
		"UNIT_SPELLCAST_SUCCEEDED registered for campfire proximity")
	FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1307227)
	assert(wr.GetState().campfireDesired, "placing a Basic Campfire activates glow when nearby")
	playerX = 0.55 -- 50 yards away (> 14 yd radius)
	assert(not wr.IsNearCampfire(nowTime), "walking 50 yards away deactivates campfire proximity")

	-- ns.HasCampfireNearPlayer safely handles nil GetXY / missing GetMapWorldSize
	local savedCampfires = uv(ns.HasCampfireNearPlayer, "campfires")
	savedCampfires[#savedCampfires + 1] = { mapID = 1429, x = 0.50, y = 0.50, expires = nowTime + 60 }
	playerX, playerY = 0.50, 0.50
	assert(ns.HasCampfireNearPlayer(14), "Minimap campfire helper detects nearby fire")
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return nil, nil end } end
	assert(not ns.HasCampfireNearPlayer(14), "Minimap campfire helper handles nil GetXY safely")
	C_Map.GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end
	C_Map.GetMapWorldSize = nil
	assert(not ns.HasCampfireNearPlayer(14), "Minimap campfire helper handles missing GetMapWorldSize safely")
	table.remove(savedCampfires)
	C_Map.GetMapWorldSize = function() return 1000, 1000 end

	-- PLAYER_EQUIPMENT_CHANGED clears worn armor flag when damaged piece is swapped out
	slotDura = { [1] = { 20, 100 } }
	FireEvent("UPDATE_INVENTORY_DURABILITY")
	assert(wr.GetState().armorWorn, "UPDATE_INVENTORY_DURABILITY marks armor as worn below 30%")
	slotDura = { [1] = { 100, 100 } }
	FireEvent("PLAYER_EQUIPMENT_CHANGED")
	assert(not wr.GetState().armorWorn, "PLAYER_EQUIPMENT_CHANGED clears worn flag after swapping armor")

	-- Armor test sound with fallback
	playedFiles, playedKits = {}, {}
	PlaySoundFile = function() return false end
	SOUNDKIT = SOUNDKIT or {}
	local savedChainKit = SOUNDKIT.PUT_DOWN_SMALL_CHAIN
	SOUNDKIT.PUT_DOWN_SMALL_CHAIN = 1212
	assert(wr.PlayArmorRattle() and playedKits[1] == 1212, "armor rattle falls back to PUT_DOWN_SMALL_CHAIN when PlaySoundFile fails")

	-- Disabling WorldReactions stops overlay and clears watcher OnUpdate
	ns.SetOption("WorldReactions", "enabled", false)
	local st = wr.GetState()
	assert(not st.watcherActive and not st.overlayShown and not st.campfireDesired and not st.dropsActive,
		"disabling WorldReactions stops watcher and hides overlay")
	ns.SetOption("WorldReactions", "enabled", true)

	-- Restore mocked globals
	SOUNDKIT.PUT_DOWN_SMALL_CHAIN = savedChainKit
	GetInventoryItemDurability = savedDurability
	PlaySoundFile, PlaySound, ns.After = savedPlayFile, savedPlaySound, savedAfter
	C_Secrets, C_UnitAuras, UnitAffectingCombat = savedSecrets, savedUnitAuras, savedCombat
	GetTime, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapWorldSize = savedGetTime, savedMapBest, savedMapPos, savedMapSize
	wr:Apply()
	print("world reactions OK")
end)()

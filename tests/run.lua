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
		HookScript = function(self, s, fn) self.scripts[s] = fn end,
		Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
		SetShown = function(self, v) self.shown = v and true or false end,
		IsShown = function(self) return self.shown end, IsVisible = function(self) return self.shown end,
		GetAlpha = function(self) return self.alpha end, SetAlpha = function(self, a) self.alpha = a end,
		GetWidth = function(self) return self.w end, GetHeight = function(self) return self.h end,
		GetSize = function(self) return self.w, self.h end,
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
TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) postCalls[#postCalls + 1] = fn end }
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
	"ContainerFrameCombinedBags", "FramePositionDelegate", "ActionBarButtonEventsFrame", "BuffFrame", "MinimapBackdrop" }) do NewFrame("Frame", n) end
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
	GetMapWorldSize = function() return 1000, 700 end, GetWorldPosFromMapPos = function() return nil end,
	GetMapPosFromWorldPos = function() return nil end, GetMapRectOnMap = function() return nil end }
C_ClassColor = { GetClassColor = function(c, t) assert(t == nil, "GetClassColor extra arg") return { GetRGB = function() return 1, 1, 1 end, WrapTextInColorCode = function(_, x) return x end } end }
Enum = Mock("Enum"); Enum.ItemArmorSubclass = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }; Enum.UIMapType = { Zone = 3 }; Enum.ItemQuality = { Poor = 0, Uncommon = 2 }
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i) return "Prof", 1, 150, 300, 0, 0, i == 1 and 171 or 185 end
C_Item = Mock("C_Item"); C_Item.IsItemDataCachedByID = function() return true end
C_Item.GetItemInfoInstant = function() return 1, nil, nil, nil, nil, 9, 5 end
C_TooltipInfo = { GetItemByID = function() return { lines = {} } end, GetBagItem = function() return { lines = {} } end }
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
TRACKER_HEADER_QUESTS = "Quests"
C_Spell = { GetSpellName = function(id) return "Spell"..id end, GetSpellTexture = function() return 1 end }
C_SpellBook = { IsSpellKnown = function() return true end, FindSpellBookSlotForSpell = function() return 1 end }
C_UnitAuras = { GetAuraDataBySpellName = function() return nil end }
GetTime = function() return 100 end
UnitIsDeadOrGhost = function() return false end
min, max, floor = math.min, math.max, math.floor
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetMouseFoci = function() return {} end
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
C_AddOns.GetAddOnInfo = function(i) return i == 1 and "Slow" or "Fast", i == 1 and "|cffff0000Slow|r Addon" or "Fast" end
issecretvalue = function() return false end
MerchantSellAllJunkButton = CreateFrame("Button"); MerchantSellAllJunkButton.Icon = MerchantSellAllJunkButton:CreateTexture()
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
local itemsMod = ns:GetModule("Items")
local UpdateAllBags = upvalue(itemsMod.OnOptionChanged, "UpdateAllBags")
local UpdateContainerFrame = upvalue(UpdateAllBags, "UpdateContainerFrame")
local UpdateButton = upvalue(UpdateContainerFrame, "UpdateButton")
local IsUpgrade = upvalue(UpdateButton, "IsUpgrade")
assert(IsUpgrade, "IsUpgrade found")
Enum.ItemClass = { Armor = 4, Weapon = 2 }
local cache = upvalue(IsUpgrade, "upgradeCache")
local ITEMS = {
	["equippedBelt"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 25 } },
	["clothBelt"] = { "INVTYPE_WAIST", 4, 1, { RESISTANCE0_NAME = 9, ITEM_MOD_INTELLECT_SHORT = 5 } },
	["leatherAgi"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 30, ITEM_MOD_AGILITY_SHORT = 3 } },
	["leatherInt"] = { "INVTYPE_WAIST", 4, 2, { RESISTANCE0_NAME = 20, ITEM_MOD_INTELLECT_SHORT = 6 } },
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
local compare = upvalue(IsUpgrade, "CompareScores")
local up = upvalue(compare, "IsBestArmorType")
-- player class in harness is MAGE; force shaman
for i = 1, 200 do local n = debug.getupvalue(up, i) if not n then break end if n == "playerClass" then debug.setupvalue(up, i, "SHAMAN") end end
local GetWeights = upvalue(upvalue(compare, "EquippedScore"), "Score")
local function check(link, expect)
	for k in pairs(cache) do cache[k] = nil end
	local r = IsUpgrade(0, 1, link)
	print("  upgrade", link, r)
	assert(r == expect, link)
end
check("clothBelt", false)
check("leatherAgi", true)
check("leatherInt", true)
GetInventoryItemLink = function(_, slot) return slot == 6 and "leatherAgi" or nil end
check("leatherInt", false)
check("mailBelt", false) -- level 20: mail not best type
UnitLevel = function() return 40 end
print("dbg", up(4, 3, "INVTYPE_WAIST"), upvalue(up, "ARMOR_TYPE").SHAMAN[2], UnitLevel())
check("mailBelt", true)
print("upgrade OK")
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
local show = uv(uv(info.UpdatePerformance, "CreatePerfFrame"), "ShowCpuTooltip")
show(UIParent)
for _, l in ipairs(lines) do print("  " .. l) end
print("info OK")
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
C_QuestLog.IsComplete = function() return qstate.complete end
C_QuestLog.IsFailed = function() return false end
C_QuestLog.GetLogIndexForQuestID = function() return 1 end
GetNumQuestLeaderBoards = function() return 1 end
C_NamePlate = { GetNamePlates = function() return {} end }
local scan = uv(uv(quests.OnLogin, "QueueScan"), "ScanQuests")
scan(); qstate.done = 1; scan(); qstate.done = 2; qstate.complete = true; scan()
print("  sounds:", table.concat(played, ","))
assert(played[1] == 558137 or played[1] == "558137", "quest progress sound")
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
q.cdb.trackerTab = "instance"; sort()
assert(table.concat(watches, ",") == "15", "instance tab")
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
	ns.IsQuestReady = function(id) return id == readyID end
	q.cdb.watched = nil
	q.db.trackerSort = "default"; q.db.readyOnly = true; sort()
	assert(table.concat(watches, ",") == "12", "only the ready quest stays tracked")
	readyID = nil; sort()
	table.sort(watches)
	assert(table.concat(watches, ",") == "11,12,14,15,16", "nothing ready: all shown again")
	q.db.readyOnly = false; sort()
	ns.IsQuestReady = realReady
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
ns:ResetFramePositions()
assert(entry and not ns:HasSavedPosition(entry))
assert(next(ns.db.unlocked) == nil, "reset locks again")
print("mover OK")
-- Trainer spells glow
local talents = ns:GetModule("Talents")
local learn = uv(uv(talents.Update, "UpdateSpellsGlow"), "LearnableSpells")
C_SpellBook.IsSpellKnown = function(id) return id == 101 end; IsPlayerSpell = function(id) return id == 101 end; UnitLevel = function() return 20 end
local cs = uv(learn, "CollectSpells"); for k, v in pairs(cs()) do print("  lvl", k, #v) end
local l = learn()
print("  learnable:", #l, l[1], l[2], C_SpellBook.GetCurrentLevelSpells, GetMaxLevelForPlayerExpansion(), UnitLevel("player"))
C_Spell.GetSpellName = function(id) return "Spell" .. id end
C_Spell.GetSpellSubtext = function() return "" end
C_Spell.GetSpellTexture = function() return 1 end
l = learn()
assert(#l == 1 and l[1] == "Spell102|", "learnable spell")
local tl = uv(cs, "TrainerList")()
tl[1] = { name = "Future", level = 30, icon = 1 }
local all = cs()
assert(all[30] and all[30][1].name == "Future" and #learn() == 1, "trainer future spell")
talents.cdb.seenSpells = {}
print("talents glow OK")
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
local bound
SetOverrideBindingClick = function(_, _, key, name) bound = key .. ">" .. name end
InCombatLockdown = function() return false end
IsMounted = function() return false end
GetMouseFoci = function() return {} end
UnitExists = function() return false end
GetCursorPosition = function() return 100, 100 end
GetInventoryItemID = function() return 6256 end
Enum.ItemWeaponSubclass = { Fishingpole = 20 }
C_Item.GetItemInfoInstant = function() return 6256, nil, nil, nil, nil, 2, 20 end
helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
assert(bound == nil, "no binding on press")
helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
assert(bound == "BUTTON2>ForeverPlusFishButton", "fishing binding after short click")
-- Holding to turn the camera never arms it.
bound = nil
uv(helpers.GLOBAL_MOUSE_UP, "ClearFishBinding")()
helpers:GLOBAL_MOUSE_DOWN("GLOBAL_MOUSE_DOWN", "RightButton")
GetCursorPosition = function() return 180, 100 end
helpers:GLOBAL_MOUSE_UP("GLOBAL_MOUSE_UP", "RightButton")
assert(bound == nil, "camera turn does not arm fishing")
print("helpers OK")
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
	UnitExists = function() return true end
end
print("hover OK")
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
lootMod:CHAT_MSG_MONEY("CHAT_MSG_MONEY", "Ihr plündert 5 Kupfer")
uv(lootMod.Update, "Flush")()
for _, t in ipairs(out) do print("  ", t) end
assert(#out == 2 and out[1]:find(" 3 ", 1, true) and out[1]:find(link .. "x3", 1, true) and out[2]:find("5c", 1, true), "summary lines")
print("loot flow OK")

-- Upgrade: Forever talent trees, shaman hammer from the screenshot
local scoreFn = upvalue(upvalue(compare, "EquippedScore"), "Score")
local getW = upvalue(scoreFn, "GetWeights")
local function resetWeights() for i = 1, 200 do local n = debug.getupvalue(getW, i) if not n then break end if n == "weights" then debug.setupvalue(getW, i, nil) end if n == "playerClass" then debug.setupvalue(getW, i, "SHAMAN") end end end
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
assert(s1 > e1, "hammer better without points")
spent[11] = 1
resetWeights()
local s2, e2 = compare("hammer")
print("  elemental lvl10", s2, e2, select(2, getW()))
assert(select(2, getW()) == "Elementar" and s2 > e2, "hammer better for levelling elemental")
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
	add(root)
	assert(titles == 1 and #checkboxes >= 1, "radar entry added under a title") -- the harness runs OnLogin more than once
	checkboxes = { checkboxes[#checkboxes] }
	assert(checkboxes[1].isOn() == true, "on while the radar is shown on the minimap")
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_minimap == false, "click switches the minimap pins off")
	radar.db.minimap = false
	checkboxes[1].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_minimap == true, "click switches them on")
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
local colorBtn = uv(uv(updateAuras, "RecolorAll"), "ColorButton")
vis.db.actionColors, vis.db.colorActiveBuff, vis.db.colorRange = true, true, true
local auras = { { name = "Siegel der Rechtschaffenheit" } }
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_Spell.IsSelfBuff = function(id) return id == 20154 end
C_Spell.GetSpellName = function(id) return id == 20154 and "Siegel der Rechtschaffenheit" or "Heiliges Licht" end
GetActionInfo = function(slot) return "spell", slot == 1 and 20154 or 635 end
C_ActionBar.IsUsableAction = function() return true end
local function mkBtn(slot) local b = { action = slot, icon = { SetVertexColor = function(self, r) self.r = r end, SetDesaturated = function(self, d) self.d = d end } } return b end
local seal, light = mkBtn(1), mkBtn(2)
updateAuras()
colorBtn(seal); colorBtn(light)
assert(seal.icon.d == true and not light.icon.d, "active seal greyed")
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
-- Exceptions and timed measure
vis.db.activeBuffExceptions = { ["Siegel der Rechtschaffenheit"] = true }
auras = { { name = "Siegel der Rechtschaffenheit" } }
updateAuras(); colorBtn(seal)
assert(not seal.icon.d, "exception keeps seal normal")
vis.db.activeBuffExceptions = {}
local timerFn
C_Timer.NewTimer = function(_, fn) timerFn = fn return { Cancel = function() end } end
ns.timings["old"] = { max = 1, count = 1, slow = 0 }
local doneMeasure
ns.StartTimedMeasure(30, function() doneMeasure = true end)
assert(ns.measuring and not ns.timings.old, "measuring, old values cleared")
ns.RecordTiming("X: y", 3)
timerFn()
assert(doneMeasure and not ns.measuring and ns.TopTimings(5)[1].name == "X: y", "timed measure")
print("exceptions/measure OK")
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
	print("show upgrade", ok, err)
	queue[1] = { link = "x", score = 5, equippedScore = 0 }
	ok, err = pcall(showNext)
	print("show upgrade empty slot", ok, err)
end
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
	dialog:OnConversation("QUEST_DETAIL")
	assert(pcall(dialog.GoBack), "back runs")
	GetQuestID = function() return 77 end
	assert(pcall(dialog.OnConversation, dialog, "QUEST_PROGRESS"), "progress with abandon")
	assert(pcall(dialog.AbandonQuest, 77), "abandon runs")
	local reward = dialog.RewardView()
	assert(#reward.buttons == 2 and reward.blocks[3].choose, "reward choice")
	dialog.db.style = "DARK"
	assert(pcall(dialog.OnConversation, dialog, "QUEST_DETAIL"), "dark style")
	dialog.db.enabled = false
	print("dialog OK")
end)()
;(function()
	-- reputation flash and trivial messages
	local flash = ns:GetModule("RepFlash")
	local ok, err = pcall(flash.Add, flash, "Eisenschmiede", 25)
	assert(ok, tostring(err))
	assert(pcall(flash.Add, flash, "Orgrimmar", -10), "second change merges")
	local trivial = ns:GetModule("Trivial")
	DRUNK_MESSAGE_SELF1 = "Ihr fühlt Euch ein wenig beschwipst."
	MARKED_AFK = "Ihr seid jetzt AFK."
	trivial:OnLogin()
	local filter = uv(trivial.Apply, "Filter")
	trivial.db.enabled, trivial.db.rested, trivial.db.drunk, trivial.db.afk = true, true, true, false
	issecretvalue = function() return false end
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == true, "rested hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr fühlt Euch ein wenig beschwipst.") == true, "drunk hidden")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == false, "afk kept while off")
	trivial.db.afk = true
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid jetzt AFK.") == true, "afk hidden when on")
	trivial.db.rested = false
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Ihr seid nicht mehr erholt.") == false, "rested kept when off")
	assert(filter(nil, "CHAT_MSG_SYSTEM", "Etwas ganz anderes.") == false, "other lines pass")
	print("trivial OK")
end)()
;(function()
	-- durability on the character window
	local dura = ns:GetModule("Durability")
	issecretvalue = function() return false end
	GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 elseif slot == 2 then return 100, 100 end end
	assert(dura.Percent(1) == 50, "half")
	assert(dura.Percent(2) == nil, "full hidden")
	assert(dura.Percent(3) == nil, "no durability")
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
	-- Quest window as parchment page: buttons become text links in the page corners and come back.
	local q = ns:GetModule("Quests")
	local function Button(name)
		local b = { alpha = {}, points = { { "BOTTOMLEFT", "QuestFrame", "BOTTOMLEFT", 6, 4 } }, width = 78, fonts = { "GameFontNormal", "GameFontHighlight", "GameFontDisable" } }
		for _, key in ipairs({ "Left", "Middle", "Right" }) do
			b[key] = { SetAlpha = function(_, a) b.alpha[key] = a end }
		end
		b.hl = { SetAlpha = function(_, a) b.alpha.hl = a end }
		function b:GetHighlightTexture() return self.hl end
		function b:GetNormalFontObject() return self.fonts[1] end
		function b:GetHighlightFontObject() return self.fonts[2] end
		function b:GetDisabledFontObject() return self.fonts[3] end
		function b:SetNormalFontObject(f) self.fonts[1] = f end
		function b:SetHighlightFontObject(f) self.fonts[2] = f end
		function b:SetDisabledFontObject(f) self.fonts[3] = f end
		function b:GetWidth() return self.width end
		function b:SetWidth(w) self.width = w end
		function b:GetTextWidth() return 50 end
		function b:GetNumPoints() return #self.points end
		function b:GetPoint(i) return unpack(self.points[i]) end
		function b:ClearAllPoints() self.points = {} end
		function b:SetPoint(...) self.points[#self.points + 1] = { ... } end
		_G[name] = b
		return b
	end
	local accept, decline = Button("QuestFrameAcceptButton"), Button("QuestFrameDeclineButton")
	for _, n in ipairs({ "QuestFrameCompleteButton", "QuestFrameCompleteQuestButton", "QuestFrameGoodbyeButton", "QuestFrameGreetingGoodbyeButton" }) do Button(n) end
	QuestFrame, GossipFrame = CreateFrame("Frame"), CreateFrame("Frame")
	GossipFrame.GreetingPanel.GoodbyeButton = Button("GossipGoodbye")
	q.db.questParchment = true
	q:OnOptionChanged("questParchment", true)
	assert(accept.points[1][1] == "BOTTOMLEFT" and accept.points[1][4] == 8 and decline.points[1][1] == "BOTTOMRIGHT", "links in the page corners")
	assert(accept.width == 62 and accept.alpha.Left == 0 and accept.alpha.hl == 0 and accept.fonts[1] ~= "GameFontNormal", "text link look")
	assert(GossipFrame.GreetingPanel.GoodbyeButton.points[1][1] == "BOTTOMRIGHT", "gossip goodbye as link")
	q.db.questParchment = false
	q:OnOptionChanged("questParchment", false)
	assert(accept.points[1][2] == "QuestFrame" and accept.points[1][5] == 4 and accept.width == 78, "anchors back")
	assert(accept.alpha.Left == 1 and accept.fonts[1] == "GameFontNormal" and accept.fonts[3] == "GameFontDisable", "look back")
	print("quest parchment OK")
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
	GameTooltip = { GetOwner = function() return btn end, AppendInfo = function(_, getter, entryID, rank) lines[#lines + 1] = getter .. ":" .. entryID .. ":" .. rank end, Show = function() end }
	GameTooltip_AddBlankLineToTooltip = function() end
	GameTooltip_AddColoredLine = function(_, text) lines[#lines + 1] = text end
	C_Traits.GetNodeInfo = function() return { maxRanks = 3, ranksPurchased = 1, activeEntry = { entryID = 500, rank = 1 } } end
	uv(uv(onClick, "HookPlanTooltip"), "AddPlanTooltip")(btn)
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
	onClick(nil, bs[3], "RightButton")
	assert(not plan2[3], "row 1 needs 5 points")
	-- the restriction shows in the tooltip of that talent, in the colour of the plan
	lines = {}
	GameTooltip = { GetOwner = function() return bs[3] end, Show = function() end }
	uv(uv(onClick, "HookPlanTooltip"), "AddPlanTooltip")(bs[3])
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
	-- Space in the quest window: accept, continue or complete without Blizzard's dialogs.
	local q = ns:GetModule("Quests")
	q.db.questParchment = true
	q:UpdateQuestParchment()
	local keys = uv(ns.Parchment.Update, "questKeys")
	assert(keys and keys.scripts.OnKeyDown, "key frame")
	local propagate
	keys.SetPropagateKeyboardInput = function(_, value) propagate = value end
	local calls = {}
	local function panel(visible) return { IsVisible = function() return visible end } end
	local function button(enabled) return { IsEnabled = function() return enabled end } end
	local saved = { QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton }
	QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel = panel(true), panel(false), panel(false)
	QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton = button(true), button(true), button(true)
	AcceptQuest = function() calls[#calls + 1] = "accept" end
	CompleteQuest = function() calls[#calls + 1] = "complete" end
	GetQuestReward = function(choice) calls[#calls + 1] = "reward" .. choice end
	PlaySound = function() end
	SOUNDKIT = { IG_QUEST_LIST_OPEN = 1 }
	QuestFlagsPVP = function() return false end
	rawset(QuestFrame, "autoQuest", false)
	keys.scripts.OnKeyDown(keys, "SPACE")
	assert(calls[1] == "accept" and propagate == false, "space accepts")
	keys.scripts.OnKeyDown(keys, "W")
	assert(propagate == true and #calls == 1, "other keys pass")
	QuestFlagsPVP = function() return true end
	keys.scripts.OnKeyDown(keys, "SPACE")
	assert(#calls == 1 and propagate == true, "PvP quest stays with Blizzard's button")
	QuestFrameDetailPanel, QuestFrameRewardPanel = panel(false), panel(true)
	GetNumQuestChoices = function() return 2 end
	GetQuestMoneyToGet = function() return 0 end
	QuestInfoFrame = { itemChoice = 0 }
	keys.scripts.OnKeyDown(keys, "SPACE")
	assert(#calls == 1 and propagate == true, "reward not chosen yet")
	QuestInfoFrame.itemChoice = 2
	keys.scripts.OnKeyDown(keys, "SPACE")
	assert(calls[2] == "reward2" and propagate == false, "chosen reward taken")
	QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton = unpack(saved)
	q.db.questParchment = false
	q:UpdateQuestParchment()
	print("quest space key OK")
end)()
;(function()
	-- Books as parchment page: own page links instead of Blizzard's buttons.
	ItemTextFrame = CreateFrame("Frame")
	ItemTextFrame.HandlePagingDisplay = function() end
	local page, more = 2, false
	ItemTextGetPage = function() return page end
	ItemTextHasNextPage = function() return more end
	local placed
	ItemTextScrollFrame = CreateFrame("Frame")
	ItemTextScrollFrame.SetPoint = function(_, point, _, _, x, y) placed = { point, x, y } end
	ns.Parchment.Update(true)
	local book = uv(ns.Parchment.Update, "pages")[ItemTextFrame]
	assert(book and book.Prev.shown and not book.Next.shown, "page 2 of 2: back only")
	assert(placed[1] == "BOTTOMLEFT" and placed[3] == 36, "book text leaves room for the links")
	ns.Parchment.Update(false)
	assert(placed[3] == 6 and not book.shown, "book back to Blizzard's look")
	print("book page OK")
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
	Enum.UIMapType = { Continent = 2 }
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
	radar.db.worldMap = false
	print("world map symbols OK")
end)()
;(function()
	-- Buff reminder: a missing buff waits while the power for it is lacking.
	local buffs = ns:GetModule("Buffs")
	local update = uv(buffs.OnLogin, "Update")
	local evaluate = uv(update, "Evaluate")
	setuv(uv(evaluate, "PickSpell"), "classDB", {})
	local reminder = { key = "intellect", auras = { 1459 }, cast = { 1459 } }
	IsPlayerSpell = function() return true end
	C_SpellBook = C_SpellBook or {}
	C_SpellBook.IsSpellKnown = function() return true end
	setuv(evaluate, "FindAura", function() return nil end)
	local noPower = true
	C_Spell.IsSpellUsable = function() return false, noPower end
	local shown, _, _, waiting = evaluate(reminder, 60)
	assert(not shown and waiting, "no mana: hidden, waits for power")
	noPower = false
	shown, _, _, waiting = evaluate(reminder, 60)
	assert(shown and not waiting, "mana back: shown")
	print("buff power OK")
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
	local timers, savedAfter = {}, C_Timer.After
	C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
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
	local scrollEnd = 0
	local frame = { browseResults = { row(9001, 10), row(9001, 500), row(9002, 20) }, IsShown = function() return true end,
		ItemList = { getNumEntries = function() return 0 end, searchStartedFunc = function() return true end,
			ScrollBox = { GetDataIndexEnd = function() return scrollEnd end },
			SetDataProvider = function(_, started, entry, count, hasFull) provider = { started = started, entry = entry, count = count, hasFull = hasFull } end,
			RefreshScrollFrame = function() end } }
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
	assert(provider.count() == 6, "both rows of the item judged")
	assert(provider.entry(4) == frame.browseResults[5] and provider.entry(5) == frame.browseResults[6] and provider.entry(6) == frame.browseResults[7], "late rows land in order")
	-- many rows are judged in portions
	local big = {}
	for i = 1, 400 do big[i] = row(9001, 10) end
	frame.browseResults = big
	F.Apply() -- (a new search resets the view through the query hook)
	provider.count()
	assert(F.State.judged < 400, "a portion per call")
	provider.count(); provider.count()
	assert(F.State.judged == 400 and provider.count() == 400, "all judged after a few calls")
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
-- Bag sorting on open: one sort at a time, none while items are locked
;(function()
	local items = ns:GetModule("Items")
	local SortOnOpen = uv(uv(items.OnLogin, "QueueSort"), "SortOnOpen")
	assert(SortOnOpen, "sort function")
	local saved = { C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo }
	local sorts, locked, now, ticker = 0, false, 100, nil
	C_Container.SortBags = function() sorts = sorts + 1 end
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(bag, slot) return bag == 0 and slot == 1 and { isLocked = locked } or nil end
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
	ticker.fn(ticker); ticker.fn(ticker); ticker.fn(ticker)
	assert(not ticker.dead, "still running while items are locked")
	locked = false
	now = 120
	SortOnOpen()
	assert(sorts == 1, "no sort before the bags were quiet")
	ticker.fn(ticker); ticker.fn(ticker)
	assert(ticker.dead, "over after two quiet looks")
	now = 125
	locked = true
	SortOnOpen()
	assert(sorts == 1, "no sort while an item is locked")
	locked = false
	MerchantFrame = { IsShown = function() return true end }
	SortOnOpen()
	assert(sorts == 1, "no sort at a merchant")
	MerchantFrame = false
	now = 130
	SortOnOpen()
	assert(sorts == 2, "next sort afterwards")
	items.db.autoSort = false
	C_Container.SortBags, C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots, C_Timer.NewTicker, GetTime, InCombatLockdown, GetCursorInfo = unpack(saved, 1, 7)
	print("bag sort OK")
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
-- Speech bubbles
;(function()
	local sb = ns:GetModule("SpeechBubbles")
	UnitExists = function() return false end
	C_NamePlate = { GetNamePlateForUnit = function() return nil end }
	sb.db.fallback = true
	sb.Show("Willkommen, Reisender.")
	assert(sb.Show and sb.Hide, "bubble functions")
	sb.Hide()
	sb.db.fallback = false
	sb.Show("Kein Platz am Bildschirm.")
	sb.Hide()
	UnitExists = function() return true end
	print("speech bubbles OK")
end)()
-- Diagnosis report
;(function()
	local dc = ns:GetModule("DataCapture")
	local text = dc.DiagnoseText()
	assert(text:find("== ForeverPlus ==", 1, true) and text:find("== Errors (", 1, true) and text:find("== Status ==", 1, true), "report sections")
	assert(text:find("== Options that differ from the defaults ==", 1, true), "options section")
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
	local texts, setters, nested = {}, {}, 0
	local values = {}
	Settings.SetValue = function(var, value) values[var] = value end
	local function node(depth)
		return { CreateDivider = function() end, CreateTitle = function(_, t) texts[#texts + 1] = "# " .. t end,
			CreateCheckbox = function(_, name, isOn, set)
				texts[#texts + 1] = (depth > 0 and "  " or "") .. name
				setters[name] = { isOn = isOn, set = set }
				if depth > 0 then nested = nested + 1 end
				local box = node(depth + 1)
				box.SetTooltip = function() end
				return box
			end }
	end
	WM.db.filterMenu = false
	WM.AddFilterMenu(node(0))
	assert(#texts == 0, "option off: no entries")
	WM.db.filterMenu = true
	WM.AddFilterMenu(node(0))
	assert(texts[1] == "# " .. ns.L.MENU_EXTRAS, "own section under a title")
	assert(setters[ns.L.WORLDMAP_FLIGHTS] and setters[ns.L.WORLDMAP_INNS] and setters[ns.L.LIBRARY_SYMBOLS]
		and setters[ns.L.TRANSPORTS_DOCKS] and setters[ns.L.RADAR_TITLE], "symbols, books, docks and radar present")
	assert(nested >= 3, "recipe radar options as a submenu")
	WM.db.flightPoints = true
	assert(setters[ns.L.WORLDMAP_FLIGHTS].isOn() == true, "state read from the option")
	setters[ns.L.WORLDMAP_FLIGHTS].set()
	assert(values.ForeverPlus_WorldMap_flightPoints == false, "click switches the option")
	setters[ns.L.RADAR_TITLE].set()
	assert(values.ForeverPlus_RecipeRadar_enabled == true and values.ForeverPlus_RecipeRadar_worldMap ~= nil, "radar entry switches on")
	print("map filter menu OK")
end)()
dofile("bundled.lua")

-- Teleport menu: a click on the small north triangle of the minimap opens a
-- list of all teleports the character has (hearthstone, class spells, items).
-- The rows are secure buttons, so the menu cannot be opened in combat.
local _, ns = ...
local L = ns.L

local Teleports = ns:NewModule("Teleports", {
	title = L.TELEPORTS_TITLE,
	order = 3.5,
	defaults = {
		menu = true,
		portals = true,
		-- Position of the triangle in the frame of the minimap (see /fp nord).
		northWidth = 110,
		northHeight = 62,
		northOffset = 0,
		northSized = false,
	},
})

local HEARTHSTONE = 6948

-- kind: item (in the bags or worn) or spell (known). Missing ones are skipped.
local ENTRIES = {
	{ "item", HEARTHSTONE, hearth = true },
	{ "item", 21711 }, -- Lunar Festival Invitation (Moonglade)
	{ "item", 18984 }, -- Dimensional Ripper - Everlook
	{ "item", 18986 }, -- Ultrasafe Transporter: Gadgetzan
	{ "spell", 18960 }, -- Teleport: Moonglade
	{ "spell", 556 }, -- Astral Recall
	{ "spell", 3561 }, { "spell", 3562 }, { "spell", 3565 }, -- Teleport: Stormwind, Ironforge, Darnassus
	{ "spell", 3567 }, { "spell", 3563 }, { "spell", 3566 }, -- Teleport: Orgrimmar, Undercity, Thunder Bluff
	{ "spell", 10059, portal = true }, { "spell", 11416, portal = true }, { "spell", 11419, portal = true },
	{ "spell", 11417, portal = true }, { "spell", 11418, portal = true }, { "spell", 11420, portal = true },
}

local function Accessible(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then
		return nil
	end
	return value
end

local function Remaining(start, duration)
	start, duration = Accessible(start), Accessible(duration)
	if start and duration and start > 0 and duration > 1.5 then
		return math.max(0, start + duration - GetTime())
	end
	return 0
end

local function CooldownText(seconds)
	if seconds >= 3600 then
		return ("%d h %d min"):format(seconds / 3600, (seconds % 3600) / 60)
	elseif seconds >= 60 then
		return ("%d min"):format(math.ceil(seconds / 60))
	end
	return ("%d s"):format(math.ceil(seconds))
end

-- List of { kind, id, name, icon, remaining, hearth, portal } for this character.
function Teleports:Collect()
	local list = {}
	for _, entry in ipairs(ENTRIES) do
		local kind, id = entry[1], entry[2]
		if not (entry.portal and not self.db.portals) then
			local name, icon, remaining
			if kind == "item" then
				if (C_Item.GetItemCount(id) or 0) > 0 then
					name = C_Item.GetItemNameByID(id) or (C_Item.GetItemInfo(id))
					icon = C_Item.GetItemIconByID(id)
					remaining = Remaining(C_Container.GetItemCooldown(id))
					if not name then
						C_Item.RequestLoadItemDataByID(id)
						name = "item:" .. id
					end
				end
			elseif IsPlayerSpell(id) then
				name = C_Spell.GetSpellName(id)
				icon = C_Spell.GetSpellTexture(id)
				local cooldown = C_Spell.GetSpellCooldown(id)
				remaining = cooldown and Remaining(cooldown.startTime, cooldown.duration) or 0
			end
			if name then
				list[#list + 1] = {
					kind = kind, id = id, name = name, icon = icon, remaining = remaining or 0,
					hearth = entry.hearth, portal = entry.portal, order = #list + 1,
				}
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
local ROW_HEIGHT, WIDTH = 26, 300
local menu, rows

local function CreateRow(index)
	local row = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	local highlight = row:CreateTexture()
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row:SetHighlightTexture(highlight)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(20, 20)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Right:SetPoint("RIGHT", -4, 0)
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameTooltipText")
	row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
	row.Text:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
	row:SetScript("PostClick", function()
		menu:Hide()
	end)
	rows[index] = row
	return row
end

local function CreateMenu()
	menu = ns.CreatePanel("ForeverPlusTeleportMenu", { strata = "FULLSCREEN_DIALOG", close = true })
	menu:SetWidth(WIDTH)
	menu.Title:SetText(L.TELEPORTS_MENU_TITLE)
	menu.Empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	menu.Empty:SetPoint("TOPLEFT", menu.Title, "BOTTOMLEFT", 2, -8)
	menu.Empty:SetText(L.TELEPORTS_NONE)
	-- Section title with a line above the group portals.
	menu.PortalHeader = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	menu.PortalHeader:SetText(L.TELEPORTS_PORTAL_HEADER)
	menu.PortalLine = menu:CreateTexture(nil, "ARTWORK")
	menu.PortalLine:SetColorTexture(1, 0.82, 0, 0.35)
	menu.PortalLine:SetHeight(1)
	rows = {}
	menu:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (Teleports.trigger and Teleports.trigger:IsMouseOver()) then
			self:Hide()
		end
	end)
	menu:HookScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	menu:HookScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end)
end

function Teleports:ShowMenu()
	if InCombatLockdown() then
		ns.Print(L.TELEPORTS_COMBAT)
		return
	end
	if not menu then
		CreateMenu()
	end
	if menu:IsShown() then
		menu:Hide()
		return
	end
	local list = self:Collect()
	-- Teleports first, group portals in a section of their own.
	table.sort(list, function(a, b)
		if (a.portal or false) ~= (b.portal or false) then
			return not a.portal
		end
		return a.order < b.order
	end)
	local y = -(ns.PANEL_PADDING + 26)
	local sectionShown = false
	menu.PortalHeader:Hide()
	menu.PortalLine:Hide()
	for i = 1, math.max(#list, #rows) do
		local entry, row = list[i], rows[i] or CreateRow(i)
		if entry and entry.portal and not sectionShown then
			sectionShown = true
			y = y - 8
			menu.PortalHeader:ClearAllPoints()
			menu.PortalHeader:SetPoint("TOPLEFT", menu, "TOPLEFT", ns.PANEL_PADDING + 2, y)
			menu.PortalHeader:Show()
			menu.PortalLine:ClearAllPoints()
			menu.PortalLine:SetPoint("TOPLEFT", menu, "TOPLEFT", ns.PANEL_PADDING, y - 16)
			menu.PortalLine:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -ns.PANEL_PADDING, y - 16)
			menu.PortalLine:Show()
			y = y - 22
		end
		if entry then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", menu, "TOPLEFT", ns.PANEL_PADDING, y)
			row:SetPoint("RIGHT", menu, "RIGHT", -ns.PANEL_PADDING, 0)
			y = y - ROW_HEIGHT
			row.Icon:SetTexture(entry.icon)
			row.Text:SetText(entry.name)
			local right = ""
			if entry.remaining > 0 then
				right = "|cffff4040" .. CooldownText(entry.remaining) .. "|r"
			elseif entry.hearth then
				right = L.TELEPORTS_BOUND:format(GetBindLocation() or "?")
			end
			row.Right:SetText(right)
			row:SetAttribute("type", entry.kind)
			row:SetAttribute(entry.kind, entry.kind == "item" and ("item:" .. entry.id) or entry.name)
			row:Show()
		else
			row:Hide()
		end
	end
	menu.Empty:SetShown(#list == 0)
	menu:SetHeight(-y + ns.PANEL_PADDING + (#list == 0 and ROW_HEIGHT or 0))
	-- The menu holds secure buttons and counts as protected: protected frames may
	-- not anchor to other frames, so it sits at plain screen coordinates.
	menu:ClearAllPoints()
	local anchor = self.trigger or Minimap
	local centerX = anchor:GetCenter()
	local bottom = anchor:GetBottom()
	local scale = ns.Number(anchor:GetEffectiveScale(), 1) / ns.Number(menu:GetEffectiveScale(), 1)
	centerX, bottom = ns.Number(centerX), ns.Number(bottom)
	if centerX and bottom then
		menu:SetPoint("TOP", UIParent, "BOTTOMLEFT", centerX * scale, bottom * scale - 6)
	else
		menu:SetPoint("TOP", UIParent, "TOP", 0, -200)
	end
	menu:Show()
end

---------------------------------------------------------------------------
-- Trigger: invisible button over the north triangle, lights it up on mouse-over
---------------------------------------------------------------------------
local function LayoutTrigger()
	local trigger = Teleports.trigger
	if not trigger then
		return
	end
	local db = Teleports.db
	local rotated = GetCVar("rotateMinimap") == "1"
	trigger:SetShown(db.menu and not rotated)
	trigger:ClearAllPoints()
	trigger:SetSize(db.northWidth, db.northHeight)
	trigger:SetPoint("TOP", MinimapCompassTexture or Minimap, "TOP", 0, -db.northOffset)
	-- The same piece of the frame art, drawn once more additively.
	local atlas = MinimapCompassTexture and MinimapCompassTexture:GetAtlas()
	local info = atlas and C_Texture.GetAtlasInfo(atlas)
	local glow = trigger.Glow
	if info and info.file and info.width and info.width > 0 and info.height and info.height > 0 then
		local width, height = info.width, info.height
		local left, right = info.leftTexCoord, info.rightTexCoord
		local top, bottom = info.topTexCoord, info.bottomTexCoord
		local x0, x1 = (width - db.northWidth) / 2 / width, (width + db.northWidth) / 2 / width
		local y0, y1 = db.northOffset / height, (db.northOffset + db.northHeight) / height
		glow:SetTexture(info.file)
		glow:SetTexCoord(left + (right - left) * x0, left + (right - left) * x1,
			top + (bottom - top) * y0, top + (bottom - top) * y1)
		glow:SetVertexColor(1, 1, 1, 1)
		glow:SetAlpha(0.9)
	else
		glow:SetColorTexture(1, 1, 1, 0.3)
	end
end

function Teleports:CreateTrigger()
	local trigger = CreateFrame("Button", nil, Minimap)
	trigger:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	trigger:RegisterForClicks("LeftButtonUp")
	trigger.Glow = trigger:CreateTexture(nil, "OVERLAY")
	trigger.Glow:SetAllPoints()
	trigger.Glow:SetBlendMode("ADD")
	trigger.Glow:Hide()
	trigger.Debug = trigger:CreateTexture(nil, "OVERLAY", nil, 7)
	trigger.Debug:SetAllPoints()
	trigger.Debug:SetColorTexture(1, 0, 0, 0.4)
	trigger.Debug:Hide()
	trigger:SetScript("OnEnter", function(button)
		button.Glow:Show()
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.TELEPORTS_MENU_TITLE)
		GameTooltip_AddInstructionLine(GameTooltip, L.TELEPORTS_HINT)
		GameTooltip:Show()
	end)
	trigger:SetScript("OnLeave", function(button)
		button.Glow:Hide()
		GameTooltip_Hide()
	end)
	trigger:SetScript("OnClick", function()
		Teleports:ShowMenu()
	end)
	self.trigger = trigger
	if MinimapCompassTexture then
		-- Blizzard switches the frame art with "Rotate minimap".
		hooksecurefunc(MinimapCompassTexture, "SetAtlas", LayoutTrigger)
	end
	LayoutTrigger()
end

-- /fp nord [width height distance]: where the triangle lies, shown in red for 5 seconds.
function Teleports.Command(msg)
	local width, height, offset = msg:match("nord%s+(%d+)%s+(%d+)%s+(%-?%d+)")
	local db = Teleports.db
	if width then
		db.northWidth, db.northHeight, db.northOffset = tonumber(width), tonumber(height), tonumber(offset)
		LayoutTrigger()
	end
	ns.PrintAlways(L.TELEPORTS_NORTH_STATUS, db.northWidth, db.northHeight, db.northOffset)
	local trigger = Teleports.trigger
	if trigger then
		trigger.Debug:Show()
		C_Timer.After(5, function()
			trigger.Debug:Hide()
		end)
	end
end

function Teleports:OnLogin()
	-- Once: the area is the new, larger size (it only covered the tip of the triangle).
	if not self.db.northSized then
		self.db.northSized = true
		self.db.northWidth, self.db.northHeight, self.db.northOffset = 110, 62, 0
	end
	self:CreateTrigger()
end

function Teleports:OnOptionChanged()
	LayoutTrigger()
end

Teleports.options = {
	{ key = "menu", type = "toggle", name = L.TELEPORTS_MENU, desc = L.TELEPORTS_MENU_DESC, new = true },
	{ key = "portals", type = "toggle", name = L.TELEPORTS_PORTALS, desc = L.TELEPORTS_PORTALS_DESC, parent = "menu", new = true },
	{ key = "northWidth", type = "slider", name = L.TELEPORTS_WIDTH, desc = L.TELEPORTS_AREA_DESC, parent = "menu", min = 40, max = 220, step = 2, new = true },
	{ key = "northHeight", type = "slider", name = L.TELEPORTS_HEIGHT, desc = L.TELEPORTS_AREA_DESC, parent = "menu", min = 20, max = 140, step = 2, new = true },
}

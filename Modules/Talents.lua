-- Talents: spells by level and talent builds (save, export, import, apply)
-- on Blizzard's talent window. Builds use Blizzard's loadout string format.
local _, ns = ...
local L = ns.L

local Talents = ns:NewModule("Talents", {
	title = L.TALENTS_TITLE,
	order = 8.5,
	defaults = {
		enabled = true,
		builds = {}, -- classFile -> { { name =, text = }, ... }
	},
})

local MAX_APPLY_PASSES = 10
local _, playerClass = UnitClass("player")

---------------------------------------------------------------------------
-- Spells by level
---------------------------------------------------------------------------
local function IsKnown(spellID)
	return C_SpellBook.IsSpellKnown(spellID) or (IsPlayerSpell and IsPlayerSpell(spellID))
end

local function CollectSpells()
	local byLevel, seen = {}, {}
	local function Add(level, spellID)
		if spellID and level and level > 0 and not seen[spellID] then
			seen[spellID] = true
			byLevel[level] = byLevel[level] or {}
			tinsert(byLevel[level], spellID)
		end
	end
	-- Spells the game lists per level.
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
	for level = 1, maxLevel do
		for _, spellID in ipairs(C_SpellBook.GetCurrentLevelSpells(level) or {}) do
			Add(level, spellID)
		end
	end
	-- Spell book entries, including spells not learned yet.
	local bank = Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID and not info.isGuild then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.spellID then
					Add(C_SpellBook.GetSpellBookItemLevelLearned(index, bank), item.spellID)
				end
			end
		end
	end
	return byLevel
end

local function ShowSpellsByLevel()
	local byLevel = CollectSpells()
	local levels = {}
	for level in pairs(byLevel) do
		levels[#levels + 1] = level
	end
	table.sort(levels)
	local playerLevel = UnitLevel("player")
	local lines = {}
	for _, level in ipairs(levels) do
		local color = level <= playerLevel and NORMAL_FONT_COLOR or WHITE_FONT_COLOR
		lines[#lines + 1] = color:WrapTextInColorCode(L.TALENTS_LEVEL:format(level))
		for _, spellID in ipairs(byLevel[level]) do
			local name = C_Spell.GetSpellName(spellID) or ("spell:" .. spellID)
			local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
			if rank and rank ~= "" then
				name = ("%s (%s)"):format(name, rank)
			end
			local icon = C_Spell.GetSpellTexture(spellID)
			local text = ("   |T%s:16:16|t %s"):format(icon or 134400, name)
			lines[#lines + 1] = IsKnown(spellID) and GRAY_FONT_COLOR:WrapTextInColorCode(text) or text
		end
		lines[#lines + 1] = " "
	end
	if #levels == 0 then
		lines[1] = L.TALENTS_NO_SPELLS
	end
	ns.ShowTextWindow("Spells", L.TALENTS_SPELLS, table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
local function TalentsFrame()
	return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local function ClassBuilds()
	local builds = Talents.db.builds
	builds[playerClass] = builds[playerClass] or {}
	return builds[playerClass]
end

-- Parses a loadout string into node purchases using Blizzard's own reader.
local function ParseBuild(frame, text)
	local stream = ExportUtil.MakeImportDataStream(text)
	local valid, version, specID = frame:ReadLoadoutHeader(stream)
	if not valid then
		return nil, L.TALENTS_ERROR_STRING
	end
	if version ~= C_Traits.GetLoadoutSerializationVersion() then
		return nil, L.TALENTS_ERROR_VERSION
	end
	if specID ~= PlayerUtil.GetCurrentSpecID() then
		return nil, L.TALENTS_ERROR_SPEC
	end
	local configID, treeID = frame:GetConfigID(), frame:GetTreeInfo().ID
	local content = frame:ReadLoadoutContent(stream, treeID)
	return frame:ConvertToImportLoadoutEntryInfo(configID, treeID, content), nil, configID, treeID
end

-- Stages the build in the talent tree; Blizzard's apply button commits it.
local function ApplyBuild(build)
	local frame = TalentsFrame()
	if InCombatLockdown() or not frame or not frame:GetConfigID() then
		ns.Print(L.TALENTS_ERROR_FRAME)
		return
	end
	local entries, err, configID, treeID = ParseBuild(frame, build.text)
	if not entries then
		ns.Print(err)
		return
	end
	-- Ranks per node; tiered nodes come as several entries.
	local wanted, selection = {}, {}
	for _, entry in ipairs(entries) do
		if entry.ranksPurchased and entry.ranksPurchased > 0 then
			wanted[entry.nodeID] = (wanted[entry.nodeID] or 0) + entry.ranksPurchased
			selection[entry.nodeID] = selection[entry.nodeID] or entry.selectionEntryID
		end
	end
	C_Traits.ResetTree(configID, treeID)
	-- Prerequisites need several passes: buy what is possible until nothing changes.
	for _ = 1, MAX_APPLY_PASSES do
		local progress = false
		for nodeID, ranks in pairs(wanted) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			if node and node.ranksPurchased < ranks then
				if node.type == Enum.TraitNodeType.Selection and selection[nodeID] then
					if C_Traits.SetSelection(configID, nodeID, selection[nodeID]) then
						progress = true
					end
				else
					while node.ranksPurchased < ranks and C_Traits.PurchaseRank(configID, nodeID) do
						progress = true
						node = C_Traits.GetNodeInfo(configID, nodeID)
					end
				end
			end
		end
		if not progress then
			break
		end
	end
	ns.Print(L.TALENTS_APPLIED, build.name)
end

local function SaveBuild(name, text)
	if name == "" then
		name = date("%d.%m. %H:%M")
	end
	local builds = ClassBuilds()
	for _, build in ipairs(builds) do
		if build.name == name then
			build.text = text
			return
		end
	end
	tinsert(builds, { name = name, text = text })
end

local function SaveCurrent()
	local frame = TalentsFrame()
	if not frame or not frame:GetConfigID() then
		return
	end
	local text = frame:GetLoadoutExportString()
	ns.ShowEditWindow("BuildName", L.TALENTS_SAVE, "", SAVE, function(name)
		SaveBuild(name, text)
	end, L.TALENTS_NAME_HINT)
end

local function ImportBuild()
	ns.ShowEditWindow("BuildImport", L.TALENTS_IMPORT, "", L.TALENTS_IMPORT, function(text)
		if text == "" then
			return
		end
		local frame = TalentsFrame()
		if frame and frame:GetConfigID() then
			local entries, err = ParseBuild(frame, text)
			if not entries then
				ns.Print(err)
				return
			end
		end
		ns.ShowEditWindow("BuildName", L.TALENTS_SAVE, "", SAVE, function(name)
			SaveBuild(name, text)
		end, L.TALENTS_NAME_HINT)
	end, L.TALENTS_IMPORT_HINT)
end

local function ShowBuildMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L.TALENTS_BUILDS)
		root:CreateButton(L.TALENTS_SAVE, SaveCurrent)
		root:CreateButton(L.TALENTS_IMPORT, ImportBuild)
		local builds = ClassBuilds()
		if #builds > 0 then
			root:CreateDivider()
		end
		for index, build in ipairs(builds) do
			local sub = root:CreateButton(build.name)
			sub:CreateButton(L.TALENTS_APPLY, function()
				ApplyBuild(build)
			end)
			sub:CreateButton(L.TALENTS_EXPORT, function()
				ns.ShowEditWindow("BuildExport", build.name, build.text, CLOSE, nil, L.TALENTS_EXPORT_HINT)
			end)
			sub:CreateButton(DELETE, function()
				tremove(builds, index)
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Buttons below the talent window
---------------------------------------------------------------------------
local buttons

local function CreateButtons()
	local parent = PlayerSpellsFrame
	local builds = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	builds:SetSize(120, 22)
	builds:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -20, -2)
	builds:SetText(L.TALENTS_BUILDS)
	builds:SetScript("OnClick", ShowBuildMenu)

	local spells = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	spells:SetSize(150, 22)
	spells:SetPoint("RIGHT", builds, "LEFT", -6, 0)
	spells:SetText(L.TALENTS_SPELLS)
	spells:SetScript("OnClick", ShowSpellsByLevel)
	buttons = { builds, spells }
end

function Talents:Update()
	for _, button in ipairs(buttons or {}) do
		button:SetShown(self.db.enabled)
	end
end

function Talents:OnLogin()
	ns.OnAddOnLoaded("Blizzard_PlayerSpells", function()
		if PlayerSpellsFrame then
			CreateButtons()
			self:Update()
		end
	end)
end

function Talents:OnOptionChanged()
	self:Update()
end

Talents.options = {
	{ key = "enabled", type = "toggle", name = L.TALENTS_ENABLE, desc = L.TALENTS_ENABLE_DESC },
}

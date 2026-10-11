-- Layouts of the game's Edit Mode that come with the addon (Data/EditModeLayouts.lua): a button per layout copies
-- its text to the clipboard, the game's own import (Edit Mode, layout menu, import) takes it from there. Nothing is
-- written into the layouts of the game, so the Edit Mode stays clean of addon code.
local _, ns = ...
local L = ns.L

local EditLayouts = ns:NewModule("EditLayouts", {
	title = L.EDITLAYOUT_TITLE,
	order = 101,
	defaults = {},
})

local function Copy(entry)
	if not CopyToClipboard then
		ns.PrintAlways(L.EDITLAYOUT_NOCOPY)
		return
	end
	CopyToClipboard(entry.text)
	ns.PrintAlways(L.EDITLAYOUT_COPIED, GetLocale() == "deDE" and entry.de or entry.en)
end

EditLayouts.options = {}
for _, entry in ipairs(ns.EditModeLayouts or {}) do
	EditLayouts.options[#EditLayouts.options + 1] = {
		type = "button", name = GetLocale() == "deDE" and entry.de or entry.en, text = L.EDITLAYOUT_COPY,
		desc = L.EDITLAYOUT_DESC, func = function()
			Copy(entry)
		end,
	}
end

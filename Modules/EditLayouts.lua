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

-- The clipboard is closed to addons (CopyToClipboard): the text of the layout is shown, marked; Ctrl+C copies it.
local function Show(entry)
	ns.ShowEditWindow("LayoutText", GetLocale() == "deDE" and entry.de or entry.en, entry.text, CLOSE, nil, L.EDITLAYOUT_HINT)
end

EditLayouts.options = {}
for _, entry in ipairs(ns.EditModeLayouts or {}) do
	EditLayouts.options[#EditLayouts.options + 1] = {
		type = "button", name = GetLocale() == "deDE" and entry.de or entry.en, text = L.EDITLAYOUT_COPY,
		desc = L.EDITLAYOUT_DESC, func = function()
			Show(entry)
		end,
	}
end

-- Weapon masters of WoW Forever, after the guide of buffed.de (November 2026): map, x, y (0–100), faction,
-- name, weapon skills taught. exact = false: the guide gives no position, only "next to" another master,
-- whose position is used. Classes per skill as in the same guide.
local _, ns = ...

ns.WeaponMasters = {
	{ 1456, 41, 62, "H", "Ansekhwa", { "GUNS", "MACE1", "MACE2", "STAVES" } },
	{ 1458, 57, 32, "H", "Archibald", { "CROSSBOWS", "DAGGERS", "SWORD1", "SWORD2", "POLEARMS" } },
	{ 1454, 82, 20, "H", "Hanashi", { "BOWS", "AXE1", "AXE2", "STAVES", "THROWN" } },
	{ 1454, 82, 20, "H", "Sayoc", { "BOWS", "DAGGERS", "FIST", "AXE1", "AXE2", "THROWN" }, exact = false },
	{ 1455, 62, 89, "A", "Bixi Wobbelbonk", { "CROSSBOWS", "DAGGERS", "THROWN" } },
	{ 1455, 62, 89, "A", "Buliwyf Steinhand", { "FIST", "GUNS", "AXE1", "AXE2", "MACE1", "MACE2" }, exact = false },
	{ 1457, 58, 47, "A", "Ilyenia Mondfeuer", { "BOWS", "DAGGERS", "FIST", "STAVES", "THROWN" } },
	{ 1453, 64, 69, "A", "Woo Ping", { "CROSSBOWS", "DAGGERS", "SWORD1", "SWORD2", "STAVES", "POLEARMS" } },
}

-- Who can learn a weapon skill (class files).
ns.WeaponSkillClasses = {
	BOWS = { HUNTER = true, ROGUE = true, WARRIOR = true },
	CROSSBOWS = { HUNTER = true, ROGUE = true, WARRIOR = true },
	DAGGERS = { DRUID = true, HUNTER = true, MAGE = true, PRIEST = true, ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true },
	FIST = { DRUID = true, HUNTER = true, ROGUE = true, SHAMAN = true, WARRIOR = true },
	GUNS = { HUNTER = true, ROGUE = true, WARRIOR = true },
	AXE1 = { HUNTER = true, PALADIN = true, ROGUE = true, SHAMAN = true, WARRIOR = true },
	MACE1 = { DRUID = true, PALADIN = true, PRIEST = true, ROGUE = true, SHAMAN = true, WARRIOR = true },
	SWORD1 = { HUNTER = true, MAGE = true, PALADIN = true, ROGUE = true, WARLOCK = true, WARRIOR = true },
	POLEARMS = { DRUID = true, HUNTER = true, PALADIN = true, WARRIOR = true },
	STAVES = { DRUID = true, HUNTER = true, MAGE = true, PRIEST = true, SHAMAN = true, WARLOCK = true, WARRIOR = true },
	THROWN = { HUNTER = true, ROGUE = true, WARRIOR = true },
	AXE2 = { HUNTER = true, PALADIN = true, SHAMAN = true, WARRIOR = true },
	MACE2 = { DRUID = true, PALADIN = true, SHAMAN = true, WARRIOR = true },
	SWORD2 = { HUNTER = true, PALADIN = true, WARRIOR = true },
}

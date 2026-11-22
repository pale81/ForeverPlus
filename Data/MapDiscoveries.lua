-- Selected Forever discoveries, keyed by UiMapID. Positions are map percentages.
-- Multiple positions in one entry are alternative spawns. Sources: DATA-SOURCES.md.
-- Keep ids stable for saved marks. Quest IDs count on turn-in, or on pickup with onAccept.
-- A faction-keyed quest table describes a stop reached at different stages by each faction.
-- Any item in an items list counts as finding that stop.
local _, ns = ...

local alcazTurnIns = { 96376, 96377, 96379 }

ns.MapDiscoveries = {
	[1413] = { -- The Barrens
		{ id = "bagBarrens", name = "SLEEPING_BAG", hint = "BAG_BARRENS", onAccept = true,
			quests = { Alliance = 79192, Horde = 79007 }, points = { { 46.4, 73.8 } } },
	},
	[1417] = { -- Arathi Highlands
		{ id = "scarletArathi", name = "SCARLET_BANNER", hint = "SCARLET_ARATHI",
			items = { 215427, 278030 }, points = { { 62.0, 54.0 } } },
	},
	[1420] = { -- Tirisfal Glades
		{ id = "scarletGraveyard", name = "SCARLET_BANNER", hint = "SCARLET_MONASTERY",
			items = { 215426, 278030 }, points = { { 84.8, 30.3 } } },
	},
	[1424] = { -- Hillsbrad Foothills
		{ id = "bagWall", name = "SLEEPING_BAG", hint = "BAG_WALL", onAccept = true,
			quests = { 79976 }, items = { 211527 }, points = { { 87.3, 49.6 } } },
	},
	[1429] = { -- Elwynn Forest
		{ id = "applejackStill", name = "APPLEJACK_STILL", hint = "APPLEJACK_APPLES", faction = "Alliance",
			quests = { 91736, 91738 }, items = { 247824 }, replacesQuestStart = true, points = { { 24.5, 58.1 } } },
		{ id = "applejackTreat", name = "APPLEJACK_TREAT", hint = "APPLEJACK_SERGEANT", faction = "Alliance",
			quests = { 91738 }, points = { { 24.1, 73.1 } } },
	},
	[1431] = { -- Duskwood
		{ id = "torch", name = "TORCH", hint = "TORCH_GUARD", quests = { 98372, 99267 }, items = { 280612 },
			replacesQuestStart = true, points = {
			{ 17.2, 54.4 }, { 21.5, 72.5 }, { 23.6, 33.2 }, { 30.1, 67.5 },
			{ 45.6, 79.0 }, { 47.6, 59.5 }, { 66.1, 34.0 }, { 68.8, 69.7 },
		} },
	},
	[1432] = { -- Loch Modan
		{ id = "silver", name = "SILVER", hint = "SILVER_TOOLBOX", faction = "Alliance", quests = { 86614 },
			onAccept = true, items = { 278051 }, replacesQuestStart = true, points = {
			{ 45.7, 43.3 }, { 48.0, 40.0 }, { 48.9, 54.2 }, { 50.6, 53.4 },
		} },
		{ id = "bagDam", name = "SLEEPING_BAG", hint = "BAG_DAM", quests = { 79975 }, onAccept = true,
			points = { { 49.4, 12.9 } } },
		{ id = "condorHatchling", name = "CONDOR_EGG", hint = "CONDOR_DROP", items = { 282637 }, pet = 273956,
			points = { { 62.0, 77.4 }, { 78.0, 73.4 } } },
	},
	[1434] = { -- Stranglethorn Vale
		{ id = "alcazBootyBay", name = "ALCAZ_DISGUISE", hint = "ALCAZ_BOOTY_BAY",
			quests = alcazTurnIns, replacesQuestStart = true, points = { { 28.4, 75.8 } } },
	},
	[1435] = { -- Swamp of Sorrows
		{ id = "scarletSwamp", name = "SCARLET_BANNER", hint = "SCARLET_SWAMP",
			items = { 215425, 278030 }, points = { { 16.8, 53.8 } } },
	},
	[1436] = { -- Westfall
		{ id = "bagWestfall", name = "SLEEPING_BAG", hint = "BAG_WESTFALL", onAccept = true,
			quests = { Alliance = 79008, Horde = 79192 }, points = { { 37.5, 50.8 } } },
		{ id = "chickenEgg", name = "CHICKEN_EGG", hint = "CHICKEN_FARM", faction = "Alliance",
			items = { 11110 }, pet = 7392, points = { { 56.4, 30.5 } } },
		{ id = "alcazMoonbrook", name = "ALCAZ_DISGUISE", hint = "ALCAZ_MOONBROOK",
			quests = { 96337 }, points = { { 43.4, 67.8 } } },
	},
	[1438] = { -- Teldrassil
		{ id = "webwoodEgg", name = "WEBWOOD_EGG", hint = "WEBWOOD_NEST", faction = "Alliance",
			items = { 5167 }, quests = { 917 }, points = { { 56.8, 26.4 } } },
	},
	[1439] = { -- Darkshore
		{ id = "tallstriderHatchling", name = "TALLSTRIDER", hint = "TALLSTRIDER_DROP", items = { 284176 }, pet = 274334,
			points = { { 37.0, 91.0 }, { 35.6, 88.4 }, { 34.6, 83.4 } } },
	},
	[1441] = { -- Thousand Needles
		{ id = "alienEgg", name = "ALIEN_EGG", hint = "ALIEN_NEST", faction = "Horde", items = { 12467 },
			quests = { 4821 }, points = { { 37.0, 57.0 }, { 51.0, 56.0 }, { 56.0, 50.0 } } },
	},
	[1442] = { -- Stonetalon Mountains
		{ id = "bagCamp", name = "SLEEPING_BAG", hint = "BAG_CAMP", quests = { 79980 }, onAccept = true,
			points = { { 40.6, 52.4 } } },
		{ id = "bagMound", name = "SLEEPING_BAG", hint = "BAG_MOUND", quests = { 79974 }, onAccept = true,
			points = { { 39.6, 49.8 } } },
	},
	[1445] = { -- Dustwallow Marsh
		{ id = "scarletTheramore", name = "SCARLET_BANNER", hint = "SCARLET_THERAMORE",
			items = { 215428, 278030 }, points = { { 63.7, 42.5 } } },
		{ id = "alcazPrison", name = "ALCAZ_DISGUISE", hint = "ALCAZ_PRISON",
			quests = { 96335 }, points = { { 75.5, 13.7 } } },
	},
	[1447] = { -- Azshara
		{ id = "abyssalChest", name = "ABYSSAL_CHEST", hint = "DAWN_CHEST", items = { 282547 },
			points = { { 66.0, 54.1 } } },
	},
	[1453] = { -- Stormwind City
		{ id = "alcazStormwind", name = "ALCAZ_DISGUISE", hint = "ALCAZ_STORMWIND", faction = "Alliance",
			quests = alcazTurnIns, replacesQuestStart = true, points = { { 78.3, 71.1 } } },
	},
	[1454] = { -- Orgrimmar
		{ id = "alcazOrgrimmar", name = "ALCAZ_DISGUISE", hint = "ALCAZ_ORGRIMMAR", faction = "Horde",
			quests = alcazTurnIns, replacesQuestStart = true, points = { { 32.3, 35.8 } } },
	},
	[2521] = { -- Zephras Isle
		{ id = "heirloom", name = "HEIRLOOM", hint = "DAWN_RING", items = { 264908 }, points = { { 41.7, 23.4 } } },
		{ id = "ancientHilt", name = "ANCIENT_HILT", hint = "DAWN_HILT", items = { 282315 }, quests = { 93161 },
			onAccept = true, replacesQuestStart = true, points = { { 58.13, 24.06 } } },
		{ id = "gustjumper", name = "GUSTJUMPER", hint = "GUSTJUMPER_FROGS", items = { 268109 }, pet = 259842,
			points = { { 51.5, 72.3 } } },
	},
}

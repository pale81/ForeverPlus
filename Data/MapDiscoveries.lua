-- Selected Forever discoveries, keyed by UiMapID. Positions are map percentages.
-- Multiple positions in one entry are alternative spawns. Sources: DATA-SOURCES.md.
-- Keep ids stable for saved marks. Quest IDs count on turn-in, or on pickup with onAccept.
-- A faction-keyed quest table describes a stop reached at different stages by each faction.
local _, ns = ...

ns.MapDiscoveries = {
	[1413] = { -- The Barrens
		{ id = "bagBarrens", name = "SLEEPING_BAG", hint = "BAG_BARRENS", onAccept = true,
			quests = { Alliance = 79192, Horde = 79007 }, points = { { 46.4, 73.8 } } },
	},
	[1424] = { -- Hillsbrad Foothills
		{ id = "bagWall", name = "SLEEPING_BAG", hint = "BAG_WALL", onAccept = true,
			quests = { 79976 }, item = 211527, points = { { 87.3, 49.6 } } },
	},
	[1431] = { -- Duskwood
		{ id = "torch", name = "TORCH", hint = "TORCH_GUARD", quests = { 98372, 99267 }, item = 280612,
			replacesQuestStart = true, points = {
			{ 17.2, 54.4 }, { 21.5, 72.5 }, { 23.6, 33.2 }, { 30.1, 67.5 },
			{ 45.6, 79.0 }, { 47.6, 59.5 }, { 66.1, 34.0 }, { 68.8, 69.7 },
		} },
	},
	[1432] = { -- Loch Modan
		{ id = "silver", name = "SILVER", hint = "SILVER_TOOLBOX", faction = "Alliance", quests = { 86614 },
			onAccept = true, item = 278051, replacesQuestStart = true, points = {
			{ 45.7, 43.3 }, { 48.0, 40.0 }, { 48.9, 54.2 }, { 50.6, 53.4 },
		} },
		{ id = "bagDam", name = "SLEEPING_BAG", hint = "BAG_DAM", quests = { 79975 }, onAccept = true,
			points = { { 49.4, 12.9 } } },
		{ id = "condorHatchling", name = "CONDOR_EGG", hint = "CONDOR_DROP", item = 282637, pet = 273956,
			points = { { 62.0, 77.4 }, { 78.0, 73.4 } } },
	},
	[1436] = { -- Westfall
		{ id = "bagWestfall", name = "SLEEPING_BAG", hint = "BAG_WESTFALL", onAccept = true,
			quests = { Alliance = 79008, Horde = 79192 }, points = { { 37.5, 50.8 } } },
		{ id = "chickenEgg", name = "CHICKEN_EGG", hint = "CHICKEN_FARM", faction = "Alliance",
			item = 11110, pet = 7392, points = { { 56.4, 30.5 } } },
	},
	[1438] = { -- Teldrassil
		{ id = "webwoodEgg", name = "WEBWOOD_EGG", hint = "WEBWOOD_NEST", faction = "Alliance",
			item = 5167, quests = { 917 }, points = { { 56.8, 26.4 } } },
	},
	[1439] = { -- Darkshore
		{ id = "tallstriderHatchling", name = "TALLSTRIDER", hint = "TALLSTRIDER_DROP", item = 284176, pet = 274334,
			points = { { 37.0, 91.0 }, { 35.6, 88.4 }, { 34.6, 83.4 } } },
	},
	[1441] = { -- Thousand Needles
		{ id = "alienEgg", name = "ALIEN_EGG", hint = "ALIEN_NEST", faction = "Horde", item = 12467,
			quests = { 4821 }, points = { { 37.0, 57.0 }, { 51.0, 56.0 }, { 56.0, 50.0 } } },
	},
	[1442] = { -- Stonetalon Mountains
		{ id = "bagCamp", name = "SLEEPING_BAG", hint = "BAG_CAMP", quests = { 79980 }, onAccept = true,
			points = { { 40.6, 52.4 } } },
		{ id = "bagMound", name = "SLEEPING_BAG", hint = "BAG_MOUND", quests = { 79974 }, onAccept = true,
			points = { { 39.6, 49.8 } } },
	},
	[1447] = { -- Azshara
		{ id = "abyssalChest", name = "ABYSSAL_CHEST", hint = "DAWN_CHEST", item = 282547,
			points = { { 66.0, 54.1 } } },
	},
	[2521] = { -- Zephras Isle
		{ id = "heirloom", name = "HEIRLOOM", hint = "DAWN_RING", item = 264908, points = { { 41.7, 23.4 } } },
		{ id = "ancientHilt", name = "ANCIENT_HILT", hint = "DAWN_HILT", item = 282315, quests = { 93161 },
			onAccept = true, replacesQuestStart = true, points = { { 58.13, 24.06 } } },
		{ id = "gustjumper", name = "GUSTJUMPER", hint = "GUSTJUMPER_FROGS", item = 268109, pet = 259842,
			points = { { 51.5, 72.3 } } },
	},
}

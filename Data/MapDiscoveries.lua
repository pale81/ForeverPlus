-- Selected Forever discoveries, keyed by UiMapID. Positions are map percentages.
-- Multiple positions in one entry are alternative spawns. Sources: DATA-SOURCES.md.
local _, ns = ...

ns.MapDiscoveries = {
	[1413] = { -- The Barrens
		{ name = "SLEEPING_BAG", hint = "BAG_BARRENS", points = { { 46.4, 73.8 } } },
	},
	[1424] = { -- Hillsbrad Foothills
		{ name = "SLEEPING_BAG", hint = "BAG_WALL", points = { { 87.3, 49.6 } } },
	},
	[1431] = { -- Duskwood
		{ name = "TORCH", hint = "TORCH_GUARD", quests = { 98372, 99267 }, points = {
			{ 17.2, 54.4 }, { 21.5, 72.5 }, { 23.6, 33.2 }, { 30.1, 67.5 },
			{ 45.6, 79.0 }, { 47.6, 59.5 }, { 66.1, 34.0 }, { 68.8, 69.7 },
		} },
	},
	[1432] = { -- Loch Modan
		{ name = "SILVER", hint = "SILVER_TOOLBOX", faction = "Alliance", quests = { 86614 }, points = {
			{ 45.7, 43.3 }, { 48.0, 40.0 }, { 48.9, 54.2 }, { 50.6, 53.4 },
		} },
		{ name = "SLEEPING_BAG", hint = "BAG_DAM", points = { { 49.4, 12.9 } } },
	},
	[1436] = { -- Westfall
		{ name = "SLEEPING_BAG", hint = "BAG_WESTFALL", points = { { 37.5, 50.8 } } },
	},
	[1442] = { -- Stonetalon Mountains
		{ name = "SLEEPING_BAG", hint = "BAG_CAMP", points = { { 40.6, 52.4 } } },
		{ name = "SLEEPING_BAG", hint = "BAG_MOUND", points = { { 39.6, 49.8 } } },
	},
	[1447] = { -- Azshara
		{ name = "ABYSSAL_CHEST", hint = "DAWN_CHEST", points = { { 66.0, 54.1 } } },
	},
	[2521] = { -- Zephras Isle
		{ name = "HEIRLOOM", hint = "DAWN_RING", points = { { 41.7, 23.4 } } },
		{ name = "ANCIENT_HILT", hint = "DAWN_HILT", points = { { 58.13, 24.06 } } },
	},
}

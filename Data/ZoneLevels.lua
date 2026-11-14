-- Recommended player levels by UiMapID. Based on the outdoor questing ranges
-- of Forever's GroupFinderActivity (1.60.1.70888), capped at player level 60.
-- See DATA-SOURCES.md for the Zephras Isle and Shen'dralas ranges.
local _, ns = ...

ns.ZoneLevels = {
	[1411] = { 1, 14 }, -- Durotar
	[1412] = { 1, 14 }, -- Mulgore
	[1413] = { 8, 30 }, -- The Barrens
	[1416] = { 28, 44 }, -- Alterac Mountains
	[1417] = { 28, 44 }, -- Arathi Highlands
	[1418] = { 33, 50 }, -- Badlands
	[1419] = { 43, 60 }, -- Blasted Lands
	[1420] = { 1, 14 }, -- Tirisfal Glades
	[1421] = { 8, 24 }, -- Silverpine Forest
	[1422] = { 48, 60 }, -- Western Plaguelands
	[1423] = { 53, 60 }, -- Eastern Plaguelands
	[1424] = { 18, 34 }, -- Hillsbrad Foothills
	[1425] = { 38, 54 }, -- The Hinterlands
	[1426] = { 1, 14 }, -- Dun Morogh
	[1427] = { 43, 60 }, -- Searing Gorge
	[1428] = { 48, 60 }, -- Burning Steppes
	[1429] = { 1, 14 }, -- Elwynn Forest
	[1431] = { 18, 34 }, -- Duskwood
	[1432] = { 8, 24 }, -- Loch Modan
	[1433] = { 13, 30 }, -- Redridge Mountains
	[1434] = { 28, 50 }, -- Stranglethorn Vale
	[1435] = { 33, 50 }, -- Swamp of Sorrows
	[1436] = { 8, 24 }, -- Westfall
	[1437] = { 18, 34 }, -- Wetlands
	[1438] = { 1, 14 }, -- Teldrassil
	[1439] = { 8, 24 }, -- Darkshore
	[1440] = { 18, 34 }, -- Ashenvale
	[1441] = { 23, 40 }, -- Thousand Needles
	[1442] = { 13, 32 }, -- Stonetalon Mountains
	[1443] = { 28, 44 }, -- Desolace
	[1444] = { 38, 54 }, -- Feralas
	[1445] = { 33, 50 }, -- Dustwallow Marsh
	[1446] = { 38, 54 }, -- Tanaris
	[1447] = { 43, 60 }, -- Azshara
	[1448] = { 46, 60 }, -- Felwood
	[1449] = { 45, 60 }, -- Un'Goro Crater
	[1451] = { 53, 60 }, -- Silithus
	[1452] = { 53, 60 }, -- Winterspring
	[2482] = { 55, 60 }, -- Mount Hyjal
	[2521] = { 1, 12 }, -- Zephras Isle (Blizzard's starter guide)
	[2548] = { 33, 54 }, -- Riverglades
	[2652] = { 38, 45 }, -- Shen'dralas (local quest levels)
}

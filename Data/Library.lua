-- Library books (Friend of the Library): the 40 book items of the client data
-- (build 1.60.1.70291) and where to find them. Positions are in percent of the
-- zone map, taken from published guides where two sources agree or only one
-- names a position; books without a position (conflicting sources, dungeon) get
-- one from a player's own find (Modules/Library.lua, /fp bücher export).
-- { item ID, map ID (nil: unknown), x, y, name }
local _, ns = ...

ns.LibraryBooks = {
	{ 203754, 1455, 75.7, 10.5, "Archmage Antonidas: The Unabridged Autobiography" },
	{ 203755, 1429, 65.4, 70.1, "Archmage Theocritus' Research Journal" },
	{ 207972, 1454, 38.5, 78.2, "The Lessons of Ta'zo" },
	{ 208185, 1420, 59.4, 52.3, "The Apothecary's Metaphysical Primer" },
	{ 208800, 1413, 62.7, 36.3, "Baxtan: On Destructive Magics" },
	{ 208860, 1432, 35.6, 48.9, "Rumi of Gnomeregan: The Collected Works" },
	{ 208860, 1436, 52.7, 53.8, "Rumi of Gnomeregan: The Collected Works" },
	{ 209843, 1439, 59.6, 22.2, "Nar'thalas Almanac, Vol. 74" },
	{ 209844, 1421, 63.5, 63.1, "The Dalaran Digest, Vol. 23" },
	{ 209845, 1436, 45.4, 70.5, "Bewitchments and Glamours" },
	{ 209846, 1413, 46.0, 36.5, "Secrets of the Dreamers" },
	{ 209847, 1413, 56.3, 8.8, "Arcanic Systems Manual" },
	{ 209848, 1437, 33.6, 47.9, "Goaz Scrolls" },
	{ 209849, nil, 0, 0, "Crimes Against Anatomy" },
	{ 209850, 1432, 77.5, 14.1, "Runes of the Sorcerer-Kings" },
	{ 209851, 1442, 74.4, 85.7, "Fury of the Land" },
	{ 210177, 1421, 43.4, 41.2, "Ataeric: On Arcane Curiosities" },
	{ 213165, 1434, 41.3, 50.9, "Basilisks: Should Petrification be Feared?" },
	{ 215683, 1441, 34.4, 40.0, "Geomancy: The Stone-Cold Truth" },
	{ 215815, 1416, 48.4, 57.5, "Defensive Magics 101" },
	{ 215816, 1417, 73.6, 65.2, "A Web of Lies: Debunking Myths and Legends" },
	{ 215817, 1443, 55.1, 26.2, "Demons and You" },
	{ 215820, 1418, 56.7, 39.7, "Mummies: A Guide to the Unsavory Undead" },
	{ 215822, 1445, 57.1, 20.8, "RwlRwlRwlRwl!" },
	{ 215824, 1435, 61.0, 22.0, "A Luddite's Guide to Caring for Your Demonic Pet" },
	{ 220345, 1435, 70.2, 51.9, "Sanguine Sorcery" },
	{ 220346, 1446, 72.6, 47.5, "Legends of the Tidesages" },
	{ 220347, 1444, 50.6, 15.7, "The Liminal and the Arcane" },
	{ 220348, 1447, 20.4, 62.3, "Everyday Etiquette" },
	{ 220349, nil, 0, 0, "Stonewrought Design" },
	{ 220350, 1425, 35.8, 72.5, "Venomous Journeys" },
	{ 220352, 1427, 38.1, 49.8, "A Mind of Metal" },
	{ 220353, 1419, 55.3, 32.2, "Conjurer's Codex" },
	{ 228132, 1422, 38.26, 54.62, "Undead Potatoes" },
	{ 228133, nil, 0, 0, "Magma or Lava?" },
	{ 228134, 1448, 65.1, 3.2, "Northern Kalimdor - A Comprehensive Guide" },
	{ 228135, nil, 0, 0, "A Study of the Light" },
	{ 228136, 1452, 60.4, 37.4, "Ka-Boom!" },
	{ 228138, nil, 0, 0, "The Knight and the Lady" },
	{ 228140, nil, 0, 0, "Scourge: Undead Menace or Misunderstood?" },
	{ 228141, 1422, 69.18, 72.27, "Necromancy 101" },
}

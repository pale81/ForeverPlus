-- Library books (Friend of the Library): the 40 book items of the client data
-- (build 1.60.1.70862, unchanged since 70291) and where to find them. Guide
-- positions are in percent of the zone map. Own finds take precedence.
-- { item ID, map ID (nil: unknown), x, y, name, hand-in quest ID, optional hint key }
-- The hand-in quest IDs are from the Forever data of AllTheThings (MIT, Data/ThirdParty).
local _, ns = ...

ns.LibraryBooks = {
	{ 203754, 1455, 75.7, 10.5, "Archmage Antonidas: The Unabridged Autobiography", 79091 },
	{ 203755, 1429, 65.4, 70.1, "Archmage Theocritus' Research Journal", 79092 },
	{ 207972, 1454, 38.5, 78.2, "The Lessons of Ta'zo", 79094 },
	{ 208185, 1420, 59.4, 52.3, "The Apothecary's Metaphysical Primer", 79095 },
	{ 208800, 1413, 62.7, 36.3, "Baxtan: On Destructive Magics", 79097 },
	{ 208860, 1432, 35.6, 48.9, "Rumi of Gnomeregan: The Collected Works", 79093 },
	{ 208860, 1436, 52.7, 53.8, "Rumi of Gnomeregan: The Collected Works", 79093 },
	{ 209843, 1439, 59.6, 22.2, "Nar'thalas Almanac, Vol. 74", 78124 },
	{ 209844, 1421, 63.5, 63.1, "The Dalaran Digest, Vol. 23", 78127 },
	{ 209845, 1436, 45.4, 70.5, "Bewitchments and Glamours", 78142 },
	{ 209846, 1413, 46.0, 36.5, "Secrets of the Dreamers", 78143 },
	{ 209847, 1413, 56.3, 8.8, "Arcanic Systems Manual", 78145 },
	{ 209848, 1437, 33.6, 47.9, "Goaz Scrolls", 78146 },
	{ 209849, 1431, 16.7, 28.5, "Crimes Against Anatomy", 78147 },
	{ 209850, 1432, 77.5, 14.1, "Runes of the Sorcerer-Kings", 78148 },
	{ 209851, 1442, 74.4, 85.7, "Fury of the Land", 78149 },
	{ 210177, 1421, 43.4, 41.2, "Ataeric: On Arcane Curiosities", 79096 },
	{ 213165, 1434, 41.3, 50.9, "Basilisks: Should Petrification be Feared?", nil },
	{ 215683, 1441, 34.4, 40.0, "Geomancy: The Stone-Cold Truth", nil },
	{ 215815, 1416, 48.4, 57.5, "Defensive Magics 101", nil },
	{ 215816, 1417, 73.6, 65.2, "A Web of Lies: Debunking Myths and Legends", nil },
	{ 215817, 1443, 55.1, 26.2, "Demons and You", nil },
	{ 215820, 1418, 56.7, 39.7, "Mummies: A Guide to the Unsavory Undead", nil },
	{ 215822, 1445, 57.1, 20.8, "RwlRwlRwlRwl!", nil },
	{ 215824, 1435, 61.0, 22.0, "A Luddite's Guide to Caring for Your Demonic Pet", nil },
	{ 220345, 1435, 70.2, 51.9, "Sanguine Sorcery", nil },
	{ 220346, 1446, 72.6, 47.5, "Legends of the Tidesages", nil },
	{ 220347, nil, 0, 0, "The Liminal and the Arcane", nil }, -- Only the SoD location is known.
	{ 220348, 1447, 20.4, 62.3, "Everyday Etiquette", nil },
	-- The Forever client has no Blackrock Mountain map. Both books use the same
	-- approximate Burning Steppes position from Method, with directions at the marker.
	{ 220349, 1428, 31.1, 30.1, "Stonewrought Design", nil, "LIBRARY_STONEWROUGHT_HINT" },
	{ 220350, 1425, 35.8, 72.5, "Venomous Journeys", nil },
	{ 220352, 1427, 38.1, 49.8, "A Mind of Metal", nil },
	{ 220353, 1419, 55.3, 32.2, "Conjurer's Codex", nil },
	{ 228132, 1422, 38.26, 54.62, "Undead Potatoes", nil },
	{ 228133, 1428, 31.1, 30.1, "Magma or Lava?", nil, "LIBRARY_MAGMA_HINT" },
	{ 228134, 1448, 65.1, 3.2, "Northern Kalimdor - A Comprehensive Guide", nil },
	{ 228135, 1423, 71.8, 48.2, "A Study of the Light", nil },
	{ 228136, 1452, 60.4, 37.4, "Ka-Boom!", nil },
	{ 228138, 1423, 47.3, 42.3, "The Knight and the Lady", nil },
	{ 228140, 1423, 26.5, 15.0, "Scourge: Undead Menace or Misunderstood?", nil },
	{ 228141, 1422, 69.18, 72.27, "Necromancy 101", nil },
}

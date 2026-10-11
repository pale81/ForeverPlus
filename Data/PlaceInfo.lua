-- Short texts about the towns and capitals of Data/Places.lua and the entrances of the dungeons and raids, written for this addon in its own words (facts
-- only, no text taken from any wiki or game). Key: area ID of the place; de and en per entry.
-- Names of regions, places and dungeons are not typed in: {m1431} is the region with that map ID, {a42} the
-- place with that area ID, {i36} the dungeon or raid with that instance ID. They are filled with the names of the
-- client in its language (ns.PlaceText), so a renamed region reads right (Duskwood is Dämmerwald in German).
-- Names of persons and peoples are the English ones.
local _, ns = ...

-- English names, for when the client gives none (and for the tests).
local MAPS = {
	[1411] = "Durotar", [1412] = "Mulgore", [1413] = "The Barrens", [1416] = "Alterac Mountains", [1417] = "Arathi Highlands",
	[1418] = "Badlands", [1420] = "Tirisfal Glades", [1421] = "Silverpine Forest", [1424] = "Hillsbrad Foothills",
	[1425] = "The Hinterlands", [1426] = "Dun Morogh", [1429] = "Elwynn Forest", [1431] = "Duskwood", [1432] = "Loch Modan",
	[1433] = "Redridge Mountains", [1434] = "Stranglethorn Vale", [1435] = "Swamp of Sorrows", [1436] = "Westfall",
	[1437] = "Wetlands", [1439] = "Darkshore", [1440] = "Ashenvale", [1441] = "Thousand Needles", [1442] = "Stonetalon Mountains",
	[1443] = "Desolace", [1444] = "Feralas", [1445] = "Dustwallow Marsh", [1446] = "Tanaris", [1451] = "Silithus",
	[1452] = "Winterspring", [1438] = "Teldrassil", [1423] = "Eastern Plaguelands",
}
local INSTANCES = {
	[36] = "The Deadmines", [34] = "The Stockade", [33] = "Shadowfang Keep", [43] = "Wailing Caverns", [48] = "Blackfathom Deeps",
	[90] = "Gnomeregan", [70] = "Uldaman", [189] = "Scarlet Monastery", [109] = "The Temple of Atal'Hakkar", [209] = "Zul'Farrak",
	[229] = "Blackrock Spire", [230] = "Blackrock Depths", [289] = "Scholomance", [329] = "Stratholme", [349] = "Maraudon",
	[389] = "Ragefire Chasm", [429] = "Dire Maul", [409] = "Molten Core", [469] = "Blackwing Lair", [533] = "Naxxramas",
}

local function Name(kind, id)
	local name
	if kind == "m" and C_Map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(id)
		name = type(info) == "table" and info.name
	elseif kind == "a" and C_Map and C_Map.GetAreaInfo then
		name = C_Map.GetAreaInfo(id)
	elseif kind == "i" and GetRealZoneText then
		name = GetRealZoneText(id)
	end
	if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
		return name
	end
	if kind == "m" then
		return MAPS[id] or "?"
	elseif kind == "i" then
		return INSTANCES[id] or "?"
	end
	for _, place in ipairs(ns.Places or {}) do
		if place[4] == id then
			return place[5]
		end
	end
	return "?"
end

-- The text with its {m…}, {a…} and {i…} names filled in.
function ns.PlaceText(text)
	if type(text) ~= "string" then
		return text
	end
	return (text:gsub("{([mai])(%d+)}", function(kind, id)
		return Name(kind, tonumber(id))
	end))
end

ns.PlaceInfo = {
	-- Eastern Kingdoms
	[77] = {
		de = "Das Dorf junger Zwerge in den verschneiten Bergen der Region {m1426}. Von hier führt der Weg nach {a131} und weiter nach {a1537}.",
		en = "The village of young dwarves in the snowy mountains of the {m1426} region. From here the road leads to {a131} and on to {a1537}.",
	},
	[131] = {
		de = "Zwergensiedlung am Eingang der Region {m1426}, an der Straße nach {a1537}. Berühmt für die Thunderbrew Distillery; in der Nähe leben Frostmane-Trolle.",
		en = "Dwarven settlement at the entrance of the {m1426} region on the road to {a1537}. Famous for the Thunderbrew Distillery; Frostmane trolls live nearby.",
	},
	[1537] = {
		de = "Hauptstadt der Zwerge, in einen Berg gehauen. König Magni Bronzebeard regiert hier; die Great Forge, die Hall of Explorers und das Gnomenviertel Tinkertown liegen in der Stadt.",
		en = "Capital of the dwarves, carved into a mountain. King Magni Bronzebeard rules here; the Great Forge, the Hall of Explorers and the gnomish Tinkertown lie inside.",
	},
	[1519] = {
		de = "Hauptstadt des Königreichs Stormwind und wichtigster Sitz der Allianz. Die Stadt am Meer hat einen großen Hafen, ein Gefängnis ({i34}) und Viertel für Händler, Magier und Zwerge.",
		en = "Capital of the Kingdom of Stormwind and the main seat of the Alliance. The city by the sea has a large harbour, a prison ({i34}) and districts for traders, mages and dwarves.",
	},
	[24] = {
		de = "Die Abtei in der Region {m1429}, Heimat vieler junger Menschen. Die Kirche des Lichts lehrt hier die Kraft des Lichts.",
		en = "The abbey in the {m1429} region, home of many young humans. The Church of the Light teaches the power of the Light here.",
	},
	[87] = {
		de = "Das Hauptdorf der Region {m1429} an der Straße nach {a1519}, mit einem Gasthaus, in dem Abenteurer rasten. Marschall Dughan hält mit seinen Wachen die Gegend sicher.",
		en = "The main village of the {m1429} region on the road to {a1519}, with an inn where adventurers rest. Marshal Dughan and his guards keep the area safe.",
	},
	[42] = {
		de = "Eine unruhige Stadt in der Region {m1431}. Die Night Watch verteidigt sie gegen Untote und andere Schrecken, die nachts aus dem dunklen Wald kommen.",
		en = "An uneasy town in the {m1431} region. The Night Watch defends it against the undead and other horrors that come out of the dark forest at night.",
	},
	[94] = {
		de = "Kleine Siedlung in der Region {m1431} mit einem Friedhof, der Untote anzieht. Wer hier vorbeikommt, sollte nicht lange verweilen.",
		en = "A small settlement in the {m1431} region with a graveyard that attracts the undead. Visitors should not linger.",
	},
	[69] = {
		de = "Stadt am See in der Region {m1433}. Sie wird immer wieder von Orcs der Blackrock-Clans und von Gnollen bedroht.",
		en = "Lakeside town in the {m1433} region. It is threatened again and again by orcs of the Blackrock clans and by gnolls.",
	},
	[108] = {
		de = "Das größte Dorf der Region {m1436}. Gryan Stoutmantle ruft Abenteurer, um die Gegend gegen die Defias Brotherhood zu verteidigen.",
		en = "The largest village of the {m1436} region. Gryan Stoutmantle calls on adventurers to defend the land against the Defias Brotherhood.",
	},
	[20] = {
		de = "Verwüstetes Dorf in der Region {m1436} und ein Stützpunkt der Defias Brotherhood. Bei {a20} liegt der Eingang zu {i36}.",
		en = "A devastated village in the {m1436} region and a stronghold of the Defias Brotherhood. The entrance to {i36} lies at {a20}.",
	},
	[150] = {
		de = "Hafenstadt der Region {m1437}. Von hier fahren Schiffe nach {a442} und nach {a513}. Der Name erinnert an das Königshaus Menethil von Lordaeron.",
		en = "Harbour town of the {m1437} region. Ships sail from here to {a442} and to {a513}. The name recalls the royal house of Menethil of Lordaeron.",
	},
	[271] = {
		de = "Allianz-Siedlung in der Region {m1424}. Sie liegt nur wenige Wegstunden von {a272} entfernt, und die beiden Orte liefern sich seit jeher Gefechte.",
		en = "Alliance town in the {m1424} region. It lies only a short way from {a272}, and the two towns have always fought skirmishes.",
	},
	[272] = {
		de = "Siedlung der Region {m1424}, heute in der Hand der Horde und der Verlassenen. Das nahe {a271} ist ihr Gegenstück der Allianz; die Gefechte zwischen beiden sind berüchtigt.",
		en = "Settlement of the {m1424} region, now held by the Horde and the Forsaken. Nearby {a271} is its Alliance counterpart; the skirmishes between the two are notorious.",
	},
	[320] = {
		de = "Allianz-Dorf in der Region {m1417}, einst Heimat des ersten Menschenreiches Arathor. Gegenüber liegt der Horde-Posten {a321}.",
		en = "Alliance village in the {m1417} region, once the home of Arathor, the first human kingdom. The Horde outpost of {a321} faces it.",
	},
	[321] = {
		de = "Horde-Außenposten in der Region {m1417}, gegenüber von {a320}. An beiden Orten zeigt sich der Streit der Fraktionen um das Hochland.",
		en = "Horde outpost in the {m1417} region, opposite {a320}. Both places show the struggle of the factions over the highlands.",
	},
	[340] = {
		de = "Horde-Außenposten in der Region {m1418}, benannt nach Kargath Bladefist, dem Anführer des Shattered-Hand-Clans.",
		en = "Horde outpost in the {m1418} region, named after Kargath Bladefist, the leader of the Shattered Hand clan.",
	},
	[144] = {
		de = "Die größte Zwergensiedlung der Region {m1432}, am See im Zentrum des Tals. Die Zwerge hier verteidigen es gegen Troggs und die Orcs der Blackrock-Clans.",
		en = "The largest dwarven settlement of the {m1432} region, at the lake in the centre of the valley. The dwarves here defend it against troggs and the orcs of the Blackrock clans.",
	},
	[269] = {
		de = "Zwergenfestung am Pass zwischen den Regionen {m1432} und {m1437}.",
		en = "Dwarven fortress at the pass between the {m1432} and {m1437} regions.",
	},
	[205] = {
		de = "Zwergenfestung in der Region {m1437}, nahe der Grenze zur Region {m1417}.",
		en = "Dwarven fortress in the {m1437} region, near the border of the {m1417} region.",
	},
	[1497] = {
		de = "Hauptstadt der Verlassenen, unter den Ruinen der Hauptstadt von Lordaeron. Die Dark Lady, Sylvanas Windrunner, herrscht hier; die Verlassenen haben sich vom Lichkönig gelöst.",
		en = "Capital of the Forsaken, beneath the ruins of the capital of Lordaeron. The Dark Lady, Sylvanas Windrunner, rules here; the Forsaken have broken free from the Lich King.",
	},
	[154] = {
		de = "Das Dorf der Verlassenen in der Region {m1420}, mit einer zerstörten Kirche und einem Friedhof. Hier erwachen die Untoten und finden ihren Weg.",
		en = "The village of the Forsaken in the {m1420} region, with a ruined church and a graveyard. Here the undead awaken and find their way.",
	},
	[159] = {
		de = "Dorf der Region {m1420}, einst eine Siedlung der Menschen von Lordaeron und heute in der Hand der Verlassenen. Es liegt an der Straße nach {a1497}.",
		en = "Village of the {m1420} region, once a human settlement of Lordaeron and now held by the Forsaken. It lies on the road to {a1497}.",
	},
	[228] = {
		de = "Eine Festung der Verlassenen in der Region {m1421}, dem Wald, in dem auch {i33} liegt.",
		en = "A Forsaken stronghold in the {m1421} region, the forest that also holds {i33}.",
	},
	[35] = {
		de = "Neutrale Hafenstadt der Goblins in der Region {m1434}, Mitglied des Steamwheedle Cartel. Baron Revilgaz regiert hier; die Piraten der Bloodsail Buccaneers sind seine Feinde.",
		en = "Neutral goblin harbour town in the {m1434} region, a member of the Steamwheedle Cartel. Baron Revilgaz rules here; the pirates of the Bloodsail Buccaneers are his enemies.",
	},
	[117] = {
		de = "Lager der Horde in der Region {m1434}, benannt nach Grom Hellscream, der mit seinem Tod den Dämon Mannoroth erschlug und die Orcs vom Fluch des Dämonenbluts befreite.",
		en = "Horde camp in the {m1434} region, named after Grom Hellscream, whose death slew the demon Mannoroth and freed the orcs from the curse of the demon blood.",
	},
	[75] = {
		de = "Siedlung der Orcs in der Region {m1435}. Nicht weit liegt der versunkene Tempel {i109}.",
		en = "Orc settlement in the {m1435} region. The sunken temple {i109} lies not far away.",
	},
	[348] = {
		de = "Festung der Wildhammer-Zwerge in der Region {m1425}, von der Greifenreiter in die Lüfte aufsteigen. Falstad Wildhammer führt den Clan.",
		en = "Fortress of the Wildhammer dwarves in the {m1425} region, from which gryphon riders take to the air. Falstad Wildhammer leads the clan.",
	},
	[3317] = {
		de = "Dorf der Revantusk-Trolle in der Region {m1425}, die mit der Horde verbündet sind.",
		en = "Village of the Revantusk trolls in the {m1425} region, allies of the Horde.",
	},

	-- Kalimdor
	[1637] = {
		de = "Hauptstadt der Horde in der Region {m1411}, benannt nach Orgrim Doomhammer. Warchief Thrall führt die Horde von hier; in den Tiefen der Stadt liegt der Eingang zu {i389}.",
		en = "Capital of the Horde in the {m1411} region, named after Orgrim Doomhammer. Warchief Thrall leads the Horde from here; the entrance to {i389} lies in the depths of the city.",
	},
	[362] = {
		de = "Dorf der Orcs und Trolle in der Region {m1411} an der Straße nach {a1637}. Von hier aus hält die Horde das Umland gegen die Razormane-Trolle und die Burning Blade.",
		en = "Village of orcs and trolls in the {m1411} region on the road to {a1637}. From here the Horde holds the surrounding land against the Razormane trolls and the Burning Blade.",
	},
	[364] = {
		de = "Das Tal, in dem junge Orcs und Trolle sich ihren Platz in der Horde verdienen.",
		en = "The valley where young orcs and trolls earn their place in the Horde.",
	},
	[367] = {
		de = "Dorf der Darkspear-Trolle, benannt nach ihrem gefallenen Anführer Sen'jin. Sein Sohn Vol'jin führt den Stamm.",
		en = "Village of the Darkspear trolls, named after their fallen leader Sen'jin. His son Vol'jin leads the tribe.",
	},
	[222] = {
		de = "Dorf des Bloodhoof-Stammes in der Region {m1412}. Cairne Bloodhoof, der Oberhäuptling der Tauren, stammt aus diesem Stamm.",
		en = "Village of the Bloodhoof tribe in the {m1412} region. Cairne Bloodhoof, the high chieftain of the tauren, comes from this tribe.",
	},
	[1638] = {
		de = "Hauptstadt der Tauren auf hohen Felsplateaus, durch Hängebrücken verbunden und über Aufzüge zu erreichen. Cairne Bloodhoof herrscht hier, die Tauren folgen dem Weg der Erdenmutter.",
		en = "Capital of the tauren on high mesas, joined by rope bridges and reached by lifts. Cairne Bloodhoof rules here, and the tauren follow the way of the Earth Mother.",
	},
	[221] = {
		de = "Lager der Tauren in der Region {m1412}, wo junge Tauren die Jagd und die Wege der Erdenmutter lernen.",
		en = "Tauren camp in the {m1412} region where young tauren learn the hunt and the ways of the Earth Mother.",
	},
	[380] = {
		de = "Stützpunkt der Horde in der Region {m1413}, an der Kreuzung der großen Straßen. Karawanen und Reisende rasten hier.",
		en = "Horde stronghold in the {m1413} region at the crossing of the great roads. Caravans and travellers rest here.",
	},
	[378] = {
		de = "Lager der Tauren in der Region {m1413}, eine Rast auf dem Weg nach {m1412}.",
		en = "Tauren camp in the {m1413} region, a resting place on the way to {m1412}.",
	},
	[392] = {
		de = "Neutrale Hafenstadt der Goblins in der Region {m1413}, zugehörig zum Steamwheedle Cartel. Von hier fahren Schiffe nach {a35}.",
		en = "Neutral goblin harbour town in the {m1413} region, part of the Steamwheedle Cartel. Ships sail from here to {a35}.",
	},
	[186] = {
		de = "Dorf der Nachtelfen auf dem Weltenbaum Teldrassil. Von hier führt der Weg nach {a1657}.",
		en = "Night elf village on the world tree Teldrassil. From here the way leads to {a1657}.",
	},
	[1657] = {
		de = "Hauptstadt der Nachtelfen in der Krone des Weltenbaums Teldrassil. Hohepriesterin Tyrande Whisperwind leitet die Gläubigen Elunes; Wächterinnen und Druiden schützen die Stadt.",
		en = "Capital of the night elves in the crown of the world tree Teldrassil. High Priestess Tyrande Whisperwind leads the followers of Elune; sentinels and druids protect the city.",
	},
	[442] = {
		de = "Hafendorf der Nachtelfen in der Region {m1439}. Von hier fahren Schiffe nach {a150}.",
		en = "Night elf harbour village in the {m1439} region. Ships sail from here to {a150}.",
	},
	[415] = {
		de = "Siedlung der Nachtelfen in der Region {m1440}, die ihren Wald gegen die Horde verteidigen.",
		en = "Night elf settlement in the {m1440} region, defending their forest against the Horde.",
	},
	[431] = {
		de = "Außenposten der Horde in der Region {m1440}, der den Nachtelfen von {a415} den Wald streitig macht.",
		en = "Horde outpost in the {m1440} region that contests the forest with the night elves of {a415}.",
	},
	[467] = {
		de = "Außenposten der Nachtelfen auf einem Gipfel der Region {m1442}.",
		en = "Night elf outpost on a peak of the {m1442} region.",
	},
	[460] = {
		de = "Außenposten der Tauren in der Region {m1442}.",
		en = "Tauren outpost in the {m1442} region.",
	},
	[484] = {
		de = "Lager der Tauren in der Region {m1441}.",
		en = "Tauren camp in the {m1441} region.",
	},
	[1099] = {
		de = "Lager der Tauren in der Region {m1444}.",
		en = "Tauren camp in the {m1444} region.",
	},
	[1116] = {
		de = "Festung der Nachtelfen auf einer Insel vor der Region {m1444}. Shandris Feathermoon führt die Wächterinnen der Festung.",
		en = "Night elf fortress on an island off the {m1444} region. Shandris Feathermoon leads the sentinels of the fortress.",
	},
	[2408] = {
		de = "Dorf der Horde in der Region {m1443}.",
		en = "Horde village in the {m1443} region.",
	},
	[608] = {
		de = "Außenposten der Allianz in der Region {m1443}.",
		en = "Alliance outpost in the {m1443} region.",
	},
	[513] = {
		de = "Stadt auf einer Insel der Region {m1445}, gegründet von Jaina Proudmoore nach dem Dritten Krieg.",
		en = "City on an island of the {m1445} region, founded by Jaina Proudmoore after the Third War.",
	},
	[976] = {
		de = "Neutrale Handelsstadt der Goblins in der Wüste der Region {m1446} und Sitz des Steamwheedle Cartel.",
		en = "Neutral goblin trading town in the desert of the {m1446} region and seat of the Steamwheedle Cartel.",
	},
	[2255] = {
		de = "Handelsstadt der Goblins in der Region {m1452}, zugehörig zum Steamwheedle Cartel. In der Nähe leben die Furbolgs des Winterfall-Stammes.",
		en = "Goblin trading town in the {m1452} region, part of the Steamwheedle Cartel. The furbolgs of the Winterfall tribe live nearby.",
	},
	[3425] = {
		de = "Lager des Cenarion-Kreises in der Region {m1451}, dessen Druiden hier über das Gleichgewicht der Natur wachen. Die Tore von Ahn'Qiraj liegen nicht weit.",
		en = "Camp of the Cenarion Circle in the {m1451} region, whose druids watch over the balance of nature here. The gates of Ahn'Qiraj are not far.",
	},
}

-- The same for dungeon and raid entrances, key: the map ID of the instance (Data/Instances.lua).
ns.InstanceInfo = {
	[36] = {
		de = "{i36} unter {a20} in der Region {m1436}: der Stützpunkt der Defias Brotherhood. Hier wartet Edwin VanCleef auf seinem Schiff.",
		en = "{i36} below {a20} in the {m1436} region: the stronghold of the Defias Brotherhood. Edwin VanCleef waits here on his ship.",
	},
	[34] = {
		de = "Das Gefängnis von {a1519}. Hier sitzt unter anderem Bazil Thredd, ein Anführer der Defias Brotherhood.",
		en = "The prison of {a1519}. Bazil Thredd, a leader of the Defias Brotherhood, is held here among others.",
	},
	[33] = {
		de = "Die Festung von Archmage Arugal in der Region {m1421}; von hier aus verbreiteten sich seine Worgen.",
		en = "The fortress of Archmage Arugal in the {m1421} region; his worgen spread from here.",
	},
	[43] = {
		de = "{i43} in der Region {m1413}: Der Druide Naralex wollte die Höhlen heilen, sein Traum wurde zum Albtraum.",
		en = "{i43} in the {m1413} region: the druid Naralex wanted to heal the caves, and his dream turned into a nightmare.",
	},
	[48] = {
		de = "Der überflutete Tempel {i48} in der Region {m1440}, heute vom Twilight's Hammer und Aku'mai heimgesucht.",
		en = "The flooded temple {i48} in the {m1440} region, now haunted by the Twilight's Hammer and Aku'mai.",
	},
	[90] = {
		de = "Die Heimat der Gnome in der Region {m1426}, verseucht und von Troggs und Mekgineer Thermaplugg besetzt.",
		en = "The home of the gnomes in the {m1426} region, contaminated and held by troggs and Mekgineer Thermaplugg.",
	},
	[70] = {
		de = "Uralte Titan-Ruinen in der Region {m1418}, bewacht von Archaedas.",
		en = "Ancient titan ruins in the {m1418} region, guarded by Archaedas.",
	},
	[189] = {
		de = "Das Kloster der Scarlet Crusade in der Region {m1420}, mit vier Flügeln: Graveyard, Library, Armory und Cathedral.",
		en = "The monastery of the Scarlet Crusade in the {m1420} region, with four wings: Graveyard, Library, Armory and Cathedral.",
	},
	[109] = {
		de = "Der versunkene Tempel von Atal'Hakkar in der Region {m1435}.",
		en = "The sunken temple of Atal'Hakkar in the {m1435} region.",
	},
	[209] = {
		de = "Eine Trollstadt in der Region {m1446}.",
		en = "A troll city in the {m1446} region.",
	},
	[229] = {
		de = "Die Spitze des Blackrock Mountain, Sitz von Rend Blackhand und seinen Orcs.",
		en = "The spire of Blackrock Mountain, seat of Rend Blackhand and his orcs.",
	},
	[230] = {
		de = "Das Reich der Dark-Iron-Zwerge im Inneren des Blackrock Mountain, regiert von Imperator Dagran Thaurissan.",
		en = "The realm of the Dark Iron dwarves inside Blackrock Mountain, ruled by Emperor Dagran Thaurissan.",
	},
	[289] = {
		de = "Die Nekromantenschule unter Caer Darrow, geleitet von Darkmaster Gandling.",
		en = "The school of necromancy below Caer Darrow, run by Darkmaster Gandling.",
	},
	[329] = {
		de = "Die Stadt in der Region {m1423}, in der Arthas einst die Bevölkerung töten ließ.",
		en = "The city in the {m1423} region where Arthas once had the population killed.",
	},
	[349] = {
		de = "Die Höhlen von {i349} in der Region {m1443}.",
		en = "The caves of {i349} in the {m1443} region.",
	},
	[389] = {
		de = "Die Höhle unter {a1637}, Heimat der Searing-Blade-Kultisten.",
		en = "The cavern below {a1637}, home of the Searing Blade cultists.",
	},
	[429] = {
		de = "Die Elfenruinen von {i429} in der Region {m1444}.",
		en = "The elven ruins of {i429} in the {m1444} region.",
	},
	[409] = {
		de = "Der Feuerkern unter dem Blackrock Mountain: hier herrscht Ragnaros.",
		en = "The fire core below Blackrock Mountain: Ragnaros rules here.",
	},
	[469] = {
		de = "Das Versteck von Nefarian hoch im Blackrock Mountain.",
		en = "The lair of Nefarian high in Blackrock Mountain.",
	},
	[533] = {
		de = "Die schwebende Nekropole {i533}, Sitz von Kel'Thuzad.",
		en = "The floating necropolis {i533}, seat of Kel'Thuzad.",
	},
}

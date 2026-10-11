-- Short texts about the towns and capitals of Data/Places.lua and the entrances of the dungeons and raids, written for this addon in its own words (facts
-- only, no text taken from any wiki or game). Key: area ID of the place; de and en per entry. Names of
-- places and persons are the English ones in both languages (the client uses the Classic names of Forever).
local _, ns = ...

ns.PlaceInfo = {
	[77] = {
		de = "Das Dorf junger Zwerge in den verschneiten Bergen von Dun Morogh. Von hier führt der Weg nach Kharanos und weiter nach Ironforge.",
		en = "The village of young dwarves in the snowy mountains of Dun Morogh. From here the road leads to Kharanos and on to Ironforge.",
	},
	[131] = {
		de = "Zwergensiedlung am Eingang von Dun Morogh, an der Straße nach Ironforge. Berühmt für die Thunderbrew Distillery; in der Nähe leben Frostmane-Trolle.",
		en = "Dwarven settlement at the entrance of Dun Morogh on the road to Ironforge. Famous for the Thunderbrew Distillery; Frostmane trolls live nearby.",
	},
	[1537] = {
		de = "Hauptstadt der Zwerge, in einen Berg gehauen. König Magni Bronzebeard regiert hier; die Great Forge, die Hall of Explorers und das Gnomenviertel Tinkertown liegen in der Stadt.",
		en = "Capital of the dwarves, carved into a mountain. King Magni Bronzebeard rules here; the Great Forge, the Hall of Explorers and the gnomish Tinkertown lie inside.",
	},
	[1519] = {
		de = "Hauptstadt des Königreichs Stormwind und wichtigster Sitz der Allianz. Die Stadt am Meer hat einen großen Hafen, ein Gefängnis (The Stockade) und Viertel für Händler, Magier und Zwerge.",
		en = "Capital of the Kingdom of Stormwind and the main seat of the Alliance. The city by the sea has a large harbour, a prison (the Stockade) and districts for traders, mages and dwarves.",
	},
	[24] = {
		de = "Die Abtei im Elwynn Forest, Heimat vieler junger Menschen. Erzbischof Benedictus lehrt hier die Kraft des Lichts.",
		en = "The abbey in Elwynn Forest, home of many young humans. Archbishop Benedictus teaches the power of the Light here.",
	},
	[87] = {
		de = "Das Hauptdorf im Elwynn Forest an der Straße nach Stormwind, mit einem Gasthaus, in dem Abenteurer rasten. Marschall Dughan hält mit seinen Wachen die Gegend sicher.",
		en = "The main village of Elwynn Forest on the road to Stormwind, with an inn where adventurers rest. Marshal Dughan and his guards keep the area safe.",
	},
	[42] = {
		de = "Eine unruhige Stadt in Duskwood. Die Night Watch verteidigt sie gegen Untote und andere Schrecken, die nachts aus dem dunklen Wald kommen.",
		en = "An uneasy town in Duskwood. The Night Watch defends it against the undead and other horrors that come out of the dark forest at night.",
	},
	[94] = {
		de = "Kleine Siedlung in Duskwood mit einem Friedhof, der Untote anzieht. Wer hier vorbeikommt, sollte nicht lange verweilen.",
		en = "A small settlement in Duskwood with a graveyard that attracts the undead. Visitors should not linger.",
	},
	[69] = {
		de = "Stadt am See in den Redridge Mountains. Sie wird immer wieder von Orks der Blackrock-Clans und von Gnollen bedroht.",
		en = "Lakeside town in the Redridge Mountains. It is threatened again and again by orcs of the Blackrock clans and by gnolls.",
	},
	[108] = {
		de = "Das größte Dorf in Westfall. Gryan Stoutmantle ruft Abenteurer, um die Gegend gegen die Defias Brotherhood zu verteidigen.",
		en = "The largest village in Westfall. Gryan Stoutmantle calls on adventurers to defend the land against the Defias Brotherhood.",
	},
	[20] = {
		de = "Verwüstetes Dorf in Westfall und ein Stützpunkt der Defias Brotherhood. Bei Moonbrook liegt der Eingang zu den Deadmines.",
		en = "A devastated village in Westfall and a stronghold of the Defias Brotherhood. The entrance to the Deadmines lies at Moonbrook.",
	},
	[150] = {
		de = "Hafenstadt in den Wetlands. Von hier fahren Schiffe nach Auberdine und nach Theramore. Der Name erinnert an das Königshaus Menethil von Lordaeron.",
		en = "Harbour town in the Wetlands. Ships sail from here to Auberdine and to Theramore. The name recalls the royal house of Menethil of Lordaeron.",
	},
	[271] = {
		de = "Allianz-Siedlung in den Hillsbrad Foothills. Sie liegt nur wenige Wegstunden von Tarren Mill entfernt, und die beiden Orte liefern sich seit jeher Gefechte.",
		en = "Alliance town in the Hillsbrad Foothills. It lies only a short way from Tarren Mill, and the two towns have always fought skirmishes.",
	},
	[272] = {
		de = "Siedlung in den Hillsbrad Foothills, heute in der Hand der Horde und der Verlassenen. Das nahe Southshore ist ihr Gegenstück der Allianz; die Gefechte zwischen beiden sind berüchtigt.",
		en = "Settlement in the Hillsbrad Foothills, now held by the Horde and the Forsaken. Nearby Southshore is its Alliance counterpart; the skirmishes between the two are notorious.",
	},
	[320] = {
		de = "Allianz-Dorf in den Arathi Highlands, einst Heimat des ersten Menschenreiches Arathor. Gegenüber liegt der Horde-Posten Hammerfall.",
		en = "Alliance village in the Arathi Highlands, once the home of Arathor, the first human kingdom. The Horde outpost of Hammerfall faces it.",
	},
	[321] = {
		de = "Horde-Außenposten in den Arathi Highlands, gegenüber von Refuge Pointe. An beiden Orten zeigt sich der Streit der Fraktionen um das Hochland.",
		en = "Horde outpost in the Arathi Highlands, opposite Refuge Pointe. Both places show the struggle of the factions over the highlands.",
	},
	[340] = {
		de = "Horde-Außenposten in den Badlands, benannt nach Kargath Bladefist, dem Anführer des Shattered-Hand-Clans.",
		en = "Horde outpost in the Badlands, named after Kargath Bladefist, the leader of the Shattered Hand clan.",
	},
	[144] = {
		de = "Die größte Zwergensiedlung in Loch Modan, am See im Zentrum des Tals. Die Zwerge hier verteidigen es gegen Troggs und die Orks der Blackrock-Clans.",
		en = "The largest dwarven settlement in Loch Modan, at the lake in the centre of the valley. The dwarves here defend it against troggs and the orcs of the Blackrock clans.",
	},
	[1497] = {
		de = "Hauptstadt der Verlassenen, unter den Ruinen der Hauptstadt von Lordaeron. Die Dark Lady, Sylvanas Windrunner, herrscht hier; die Verlassenen haben sich vom Lichkönig gelöst.",
		en = "Capital of the Forsaken, beneath the ruins of the capital of Lordaeron. The Dark Lady, Sylvanas Windrunner, rules here; the Forsaken have broken free from the Lich King.",
	},
	[154] = {
		de = "Das Dorf der Verlassenen in den Tirisfal Glades, mit einer zerstörten Kirche und einem Friedhof. Hier erwachen die Untoten und finden ihren Weg.",
		en = "The village of the Forsaken in Tirisfal Glades, with a ruined church and a graveyard. Here the undead awaken and find their way.",
	},
	[159] = {
		de = "Dorf in den Tirisfal Glades, einst eine Siedlung der Menschen von Lordaeron und heute in der Hand der Verlassenen. Es liegt an der Straße zur Undercity.",
		en = "Village in Tirisfal Glades, once a human settlement of Lordaeron and now held by the Forsaken. It lies on the road to the Undercity.",
	},
	[228] = {
		de = "Eine Festung der Verlassenen in Silverpine Forest, dem Wald, in dem auch Shadowfang Keep liegt.",
		en = "A Forsaken stronghold in Silverpine Forest, the forest that also holds Shadowfang Keep.",
	},
}

-- The same for dungeon and raid entrances, key: the map ID of the instance (Data/Instances.lua).
ns.InstanceInfo = {
	[36] = {
		de = "Die Deadmines unter Moonbrook in Westfall: der Stützpunkt der Defias Brotherhood. Hier wartet Edwin VanCleef auf seinem Schiff.",
		en = "The Deadmines below Moonbrook in Westfall: the stronghold of the Defias Brotherhood. Edwin VanCleef waits here on his ship.",
	},
	[34] = {
		de = "Das Gefängnis von Stormwind. Hier sitzt unter anderem Bazil Thredd, ein Anführer der Defias Brotherhood.",
		en = "The prison of Stormwind. Bazil Thredd, a leader of the Defias Brotherhood, is held here among others.",
	},
	[33] = {
		de = "Die Festung von Archmage Arugal im Silverpine Forest; von hier aus verbreiteten sich seine Worgen.",
		en = "The fortress of Archmage Arugal in Silverpine Forest; his worgen spread from here.",
	},
	[43] = {
		de = "Die Wailing Caverns im Barrens: Der Druide Naralex wollte die Höhlen heilen, sein Traum wurde zum Albtraum.",
		en = "The Wailing Caverns in the Barrens: the druid Naralex wanted to heal the caves, and his dream turned into a nightmare.",
	},
	[48] = {
		de = "Der überflutete Tempel von Blackfathom Deeps in Ashenvale, heute vom Twilight's Hammer und Aku'mai heimgesucht.",
		en = "The flooded temple of Blackfathom Deeps in Ashenvale, now haunted by the Twilight's Hammer and Aku'mai.",
	},
	[90] = {
		de = "Die Heimat der Gnome in Dun Morogh, verseucht und von Troggs und Mekgineer Thermaplugg besetzt.",
		en = "The home of the gnomes in Dun Morogh, contaminated and held by troggs and Mekgineer Thermaplugg.",
	},
	[70] = {
		de = "Uralte Titan-Ruinen in den Badlands, bewacht von Archaedas.",
		en = "Ancient titan ruins in the Badlands, guarded by Archaedas.",
	},
	[189] = {
		de = "Das Kloster der Scarlet Crusade in den Tirisfal Glades, mit vier Flügeln: Graveyard, Library, Armory und Cathedral.",
		en = "The monastery of the Scarlet Crusade in Tirisfal Glades, with four wings: Graveyard, Library, Armory and Cathedral.",
	},
	[109] = {
		de = "Der versunkene Tempel von Atal'Hakkar in den Swamp of Sorrows.",
		en = "The sunken temple of Atal'Hakkar in the Swamp of Sorrows.",
	},
	[209] = {
		de = "Eine Trollstadt in Tanaris.",
		en = "A troll city in Tanaris.",
	},
	[229] = {
		de = "Die Spitze des Blackrock Mountain, Sitz von Rend Blackhand und seiner Orks.",
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
		de = "Die Stadt in den Eastern Plaguelands, in der Arthas einst die Bevölkerung töten ließ.",
		en = "The city in the Eastern Plaguelands where Arthas once had the population killed.",
	},
	[349] = {
		de = "Die Höhlen von Maraudon in Desolace.",
		en = "The caves of Maraudon in Desolace.",
	},
	[389] = {
		de = "Die Höhle unter Orgrimmar, Heimat der Searing-Blade-Kultisten.",
		en = "The cavern below Orgrimmar, home of the Searing Blade cultists.",
	},
	[429] = {
		de = "Die Elfenruinen von Dire Maul in Feralas.",
		en = "The elven ruins of Dire Maul in Feralas.",
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
		de = "Die schwebende Nekropole Naxxramas, Sitz von Kel'Thuzad.",
		en = "The floating necropolis Naxxramas, seat of Kel'Thuzad.",
	},
}

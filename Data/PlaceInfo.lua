-- Short texts about the towns and capitals of Data/Places.lua, written for this addon in its own words (facts
-- only, no text taken from any wiki or game). Key: area ID of the place; de and en per entry. Names of
-- places and persons follow the game's German names where they are known to the author, else the English ones.
local _, ns = ...

ns.PlaceInfo = {
	[77] = {
		de = "Das Startdorf junger Zwerge in Dun Morogh. Von hier führt der Weg durch die verschneiten Berge nach Kharanos und weiter nach Eisenschmiede.",
		en = "The starting village of young dwarves in Dun Morogh. From here the road leads through the snowy mountains to Kharanos and on to Ironforge.",
	},
	[131] = {
		de = "Zwergensiedlung am Eingang von Dun Morogh, an der Straße nach Eisenschmiede. Berühmt für die Donnerbräu-Brauerei (Thunderbrew); in der Nähe leben Frostmähnen-Trolle.",
		en = "Dwarven settlement at the entrance of Dun Morogh on the road to Ironforge. Famous for the Thunderbrew Distillery; Frostmane trolls live nearby.",
	},
	[1537] = {
		de = "Hauptstadt der Zwerge, in einen Berg gehauen. König Magni Bronzebart regiert hier; die Große Schmiede, die Halle der Forscher und das Gnomenviertel Tüftlerstadt liegen in der Stadt.",
		en = "Capital of the dwarves, carved into a mountain. King Magni Bronzebeard rules here; the Great Forge, the Hall of Explorers and the gnomish Tinkertown lie inside.",
	},
	[1519] = {
		de = "Hauptstadt des Königreichs Sturmwind und wichtigster Sitz der Allianz. Die Stadt am Meer hat einen großen Hafen, ein Gefängnis (Stockade) und Viertel für Händler, Magier und Zwerge.",
		en = "Capital of the Kingdom of Stormwind and the main seat of the Alliance. The city by the sea has a large harbour, a prison (the Stockade) and districts for traders, mages and dwarves.",
	},
	[24] = {
		de = "Die Abtei im Wald von Elwynn, Startpunkt der Menschen. Erzbischof Benedictus lehrt hier die Kraft des Lichts.",
		en = "The abbey in Elwynn Forest, starting point of the humans. Archbishop Benedictus teaches the power of the Light here.",
	},
	[87] = {
		de = "Das Hauptdorf im Wald von Elwynn an der Straße nach Sturmwind, mit einem Gasthaus, in dem Abenteurer rasten. Marschall Dughan hält mit seinen Wachen die Gegend sicher.",
		en = "The main village of Elwynn Forest on the road to Stormwind, with an inn where adventurers rest. Marshal Dughan and his guards keep the area safe.",
	},
	[42] = {
		de = "Eine unruhige Stadt im Dämmerwald. Die Nachtwache verteidigt sie gegen Untote und andere Schrecken, die nachts aus dem dunklen Wald kommen.",
		en = "An uneasy town in Duskwood. The Night Watch defends it against the undead and other horrors that come out of the dark forest at night.",
	},
	[94] = {
		de = "Kleine Siedlung im Dämmerwald mit einem Friedhof, der Untote anzieht. Wer hier vorbeikommt, sollte nicht lange verweilen.",
		en = "A small settlement in Duskwood with a graveyard that attracts the undead. Visitors should not linger.",
	},
	[69] = {
		de = "Stadt am See im Rotkammgebirge. Sie wird immer wieder von Orks der Schwarzfels-Clans und von Gnollen bedroht.",
		en = "Lakeside town in the Redridge Mountains. It is threatened again and again by orcs of the Blackrock clans and by gnolls.",
	},
	[108] = {
		de = "Das größte Dorf in Westfall. Gryan Starkmantel (Stoutmantle) ruft Abenteurer, um die Gegend gegen die Defias-Bruderschaft zu verteidigen.",
		en = "The largest village in Westfall. Gryan Stoutmantle calls on adventurers to defend the land against the Defias Brotherhood.",
	},
	[20] = {
		de = "Verwüstetes Dorf in Westfall und ein Stützpunkt der Defias-Bruderschaft. Bei Moonbrook liegt der Eingang zu den Todesminen.",
		en = "A devastated village in Westfall and a stronghold of the Defias Brotherhood. The entrance to the Deadmines lies at Moonbrook.",
	},
	[150] = {
		de = "Hafenstadt im Sumpfland. Von hier fahren Schiffe nach Auberdine und nach Theramore. Der Name erinnert an das Königshaus Menethil von Lordaeron.",
		en = "Harbour town in the Wetlands. Ships sail from here to Auberdine and to Theramore. The name recalls the royal house of Menethil of Lordaeron.",
	},
	[271] = {
		de = "Alliierte Siedlung im Hügelland von Hillsbrad. Sie liegt nur wenige Wegstunden von Tarrens Mühle entfernt, und die beiden Orte liefern sich seit jeher Gefechte.",
		en = "Alliance town in the Hillsbrad Foothills. It lies only a short way from Tarren Mill, and the two towns have always fought skirmishes.",
	},
	[272] = {
		de = "Siedlung im Hügelland von Hillsbrad, heute in der Hand der Horde und der Verlassenen. Das nahe Süderstade ist ihr Gegenstück der Allianz; in Classic sind die Schlachten zwischen beiden berühmt.",
		en = "Settlement in the Hillsbrad Foothills, now held by the Horde and the Forsaken. Nearby Southshore is its Alliance counterpart; in Classic the battles between the two are famous.",
	},
	[320] = {
		de = "Allianz-Dorf im Arathihochland, einst Heimat des ersten Menschenreiches Arathor. Gegenüber liegt der Horde-Posten Hammerfall.",
		en = "Alliance village in the Arathi Highlands, once the home of Arathor, the first human kingdom. The Horde outpost of Hammerfall faces it.",
	},
	[321] = {
		de = "Horde-Außenposten im Arathihochland, gegenüber von Refuge Pointe. An beiden Orten zeigt sich der Streit der Fraktionen um das Hochland.",
		en = "Horde outpost in the Arathi Highlands, opposite Refuge Pointe. Both places show the struggle of the factions over the highlands.",
	},
	[340] = {
		de = "Horde-Außenposten im Ödland, benannt nach Kargath Messerfaust (Bladefist), dem Anführer des Clans der Zerschmetterten Hand.",
		en = "Horde outpost in the Badlands, named after Kargath Bladefist, the leader of the Shattered Hand clan.",
	},
	[144] = {
		de = "Die größte Siedlung der Zwerge in Loch Modan, am See im Zentrum des Tals. Die Zwerge hier verteidigen es gegen Troggs und die Orks der Schwarzfels-Clans.",
		en = "The largest dwarven settlement in Loch Modan, at the lake in the centre of the valley. The dwarves here defend it against troggs and the orcs of the Blackrock clans.",
	},
	[1497] = {
		de = "Hauptstadt der Verlassenen, unter den Ruinen der Hauptstadt von Lordaeron. Dunkle Fürstin Sylvanas Windläufer herrscht hier; die Verlassenen haben sich vom Lichkönig gelöst.",
		en = "Capital of the Forsaken, beneath the ruins of the capital of Lordaeron. The Dark Lady, Sylvanas Windrunner, rules here; the Forsaken have broken free from the Lich King.",
	},
	[154] = {
		de = "Das Startdorf der Verlassenen in den Tirisfal-Gläsern, mit einer zerstörten Kirche und einem Friedhof. Hier beginnt der Weg der Untoten nach dem Erwachen.",
		en = "The starting village of the Forsaken in Tirisfal Glades, with a ruined church and a graveyard. This is where the undead begin their path after awakening.",
	},
	[159] = {
		de = "Dorf in den Tirisfal-Gläsern, einst eine Siedlung der Menschen von Lordaeron und heute in der Hand der Verlassenen. Es liegt an der Straße zur Unterstadt.",
		en = "Village in Tirisfal Glades, once a human settlement of Lordaeron and now held by the Forsaken. It lies on the road to the Undercity.",
	},
	[228] = {
		de = "Eine Festung der Verlassenen im Silberwald, dem Wald, in dem auch Burg Schattenfang liegt.",
		en = "A Forsaken stronghold in Silverpine Forest, the forest that also holds Shadowfang Keep.",
	},
}

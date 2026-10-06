# ForeverPlus

AddOn für **World of Warcraft: Forever** (Client 1.60.x, TOC-Interface `16001`, Mainline-API 12.x mit „Secret Values“).
Verbessert das originale Forever-Interface (Blizzard-Code „Camelot“) und bleibt optisch beim Original.

Einstellungen: **Esc → Optionen → AddOns → ForeverPlus** (je Thema ein Untermenü: Chat, Tooltip, Gegenstände, Quests, Aktionsleisten, Kampf, Buff-Erinnerung, Talente, Minimap & Infos, Erfahrung & Ruf, Optik, Schrift, Rezeptradar) oder `/fp`. Auf der Hauptseite: „Alle Meldungen stumm“, „Verschieben, Skalieren, Sperren“, „Alle Positionen sperren“, „Alle Positionen zurücksetzen“, „Mehrere Fenster zugleich“.

Alles Bewegliche (Fenster und ForeverPlus-Anzeigen wie Koordinaten, FPS/MS, Weltkarten-Koordinaten) wird gleich bedient: **Alt + Ziehen** verschiebt, **Strg + Mausrad** skaliert, **Alt + Rechtsklick** sperrt/entsperrt einzeln. ForeverPlus-Anzeigen gehen zusätzlich ohne Taste (Ziehen, Mausrad, Rechtsklick); bei Blizzard-Fenstern würde das mit Gegenstände-Ziehen, Listen-Scrollen und Rechtsklick-Menüs kollidieren.
`/rl` lädt das Interface neu, `/fp fehler` öffnet die Fehlerliste, `/fp schrott` die Schrottmarkierungen, `/fp radar` zeigt den Zustand des Rezeptradars.

## Funktionen

| Bereich | Funktion | Option |
|---|---|---|
| Chat | Drei Symbole links vom Chat (Soziales, Kanäle, Chatmenü) ausblenden | ja |
| | Mittelklick auf einen Chatreiter wechselt zur nächsten Sprache | ja |
| | Reiterbeschriftungen blenden mit dem Chat aus (sichtbar bei Mouseover oder neuen Nachrichten) | ja |
| | Chatschrift mit Outline | – |
| | Reiter-Hintergründe (Allgemein, Kampflog, …) entfernt | – |
| | Eingabefeld oben über den Reitern, ohne Rahmen/Hintergrund | – |
| | Chathintergrund-Regler auf 0 (100 % transparent) | ja |
| | Pfeil hoch/runter blättert im Eingabeverlauf (ohne Alt) | – |
| Tooltip | Gesundheitsleiste unten im Tooltip | – |
| | Name (und optional Stufe) der Einheit unter der Maus mittig über dem Zeiger (Tooltip-Farbe) | ja |
| | Spieler im Tooltip: Name und Klasse in Klassenfarbe | ja |
| | Stückpreis bei Stapeln direkt hinter dem Verkaufspreis | ja |
| | Scharfer Rahmen (1 Pixel, leicht abgerundete Ecken) in Qualitätsfarbe bei Gegenständen | ja |
| Minimap | Koordinaten (größer, Outline, Klassenfarbe) oben unter dem Norddreieck; verschieb- und sperrbar | – |
| Weltkarte | Eigene Koordinatenanzeige (Mauszeiger, Spieler) fester Größe unten links, verschieb-, skalier- und sperrbar (Position relativ zur Karte); Blizzards Anzeige wird ausgeblendet | ja |
| Gegenstände | Schrott verkaufen, reparieren (optional aus der Gildenbank) | ja |
| | Mittelklick (Maustaste 3/4/5 wählbar) oder frei belegbare Taste (Tastaturbelegung → AddOns) markiert/entmarkiert als Schrott (gelbe Münze), wird mitverkauft; alles, was verkauft wird, trägt die Münze; graue Gegenstände lassen sich so vom Verkauf ausnehmen; Liste aller Markierungen, Klick entfernt einzeln (`/fp schrott`); Gegenstände mit Zufallssuffix („des Affen“, „des Frostschutzes“) werden einzeln markiert | ja |
| | Wertvollste Questbelohnung mit der Schrott-Münze hervorheben | ja |
| | Grüner Pfeil nur bei echter Verbesserung für Klasse und Spezialisierung: beste Rüstungsart der Klasse (Kette/Platte ab Stufe 40), höherer gewichteter Wert als das schwächste getragene Teil des Platzes (Wertgewichte je Spezialisierung, aus der Spielmechanik abgeleitet), verwendbar; keine Berufswerkzeuge | ja |
| | Schnelles Plündern (schaltet automatisches Plündern mit ein) | ja |
| | Schlagwort-Alarm: Klang (wählbar) bei eigenen Schlagwörtern im Chat; Liste je Charakter, vorbelegt mit Name und Klasse | ja |
| | Chatmeldungen: je Funktion abschaltbar (Verkauf, Reparatur, Markierung, Wegpunkt, Sperren); Hauptseite: alle Meldungen stumm | ja |
| | Taschen voll: billigster Gegenstand (Händlerwert) wird angezeigt, nach Bestätigung aufgenommen; Vernichten über Blizzards eigene Abfrage | ja |
| | Seelengebunden beim Aufheben automatisch bestätigen (Plündern und Würfeln) | ja |
| | Würfelfenster: Anzahl Bedarf/Gier/Passen auf den Knöpfen, Namen beim Überfahren | ja |
| Auktionshaus | Warnsymbol bei Auktionen mit Stückpreis ≤ Händlerpreis, Warnung beim Einstellen | ja |
| | Laufzeit 24 Std. je Sitzung vorgewählt (über Blizzards eigene Einstellung) | ja |
| Komfort | Mikromenü, Questtracker, Taschenleiste, Aktionsleisten 1–8, Haltungs- und Begleiterleiste nur bei Mouseover (jede Leiste einzeln wählbar, Aktionsleisten standardmäßig aus) | ja |
| | Gegnerische Namensplaketten nur im Kampf | ja |
| | Rote Fehlermeldungen in der Bildschirmmitte ausblenden (Standard an) | ja |
| | Questtracker-Überschrift „Quests 7/25“ (angenommen/Maximum) | – |
| | Questtracker-Sortierung (Questlog, Stufe, Zone, Entfernung, Name, Fortschritt) per Knopf neben dem Zuklapp-Knopf | ja |
| | Fehlerfenster unterdrückt, Fehler gesammelt; Tag/Nacht-Anzeige der Minimap ist der Knopf, leuchtet bei neuen Fehlern; Liste neueste zuerst; Detailfenster mit Vor/Zurück und Kopier-Symbol; Rechtsklick löscht alle Fehler, Shift-Klick lädt das Interface neu | ja |
| | Tastenbelegungs-Nummern und Makronamen auf Aktionstasten ausblenden (einzeln) | ja |
| | Freie/gesamte Taschenplätze am Rucksack | ja |
| | Minimap-Buttons anderer Addons ausblenden (Karten-Pins bleiben) | ja |
| | Gespielte Zeit aller Charaktere im Uhr-Tooltip (ohne Chatmeldung erfasst) | ja |
| | FPS/MS unten in der Minimap (Zahlen in Klassenfarbe); Mouseover: CPU-Zeit aller Addons grün/orange/rot; verschieb- und sperrbar | ja |
| | Blizzard-Koordinaten unter der Minimap einmalig ausgeschaltet (wieder einschaltbar in den WoW-Optionen) | – |
| Quests | Questklänge (abschaltbar) bei Questfortschritt und erledigter Quest (Peon „Arbeit abgeschlossen“ bzw. „Bereit zur Arbeit“ u. a.), Questsymbol mit Fortschritt an Namensplaketten | ja |
| | Extra-Knopf für den Questgegenstand der nächsten Quest (in Reichweite), Bearbeitungsmodus, Tastenbelegung | ja |
| Flugzeiten | Jeder Flug wird gemessen und je Strecke gespeichert; Dauer im Tooltip der Flugkarte, Restzeit-Leiste während des Flugs (verschieb- und sperrbar) | ja |
| Erfahrung & Ruf | Zahlen immer oder nur bei Mouseover (Standard: Mouseover); EP- und Rufleiste: Prozent, Zahl und Prozent, Rest bis Stufe/Rufstufe, alles (EP inkl. Erholung, Quest-EP); EP abgabebereiter Quests (nur Quests mit Zielen, alle erfüllt) als dunkler Balkenteil | ja |
| Talente | „Zauber beim Lehrer“ (erlernte grau; künftige Zauber aus der beim Lehrerbesuch gespeicherten Liste; das Symbol funkelt, solange es Neues zu lernen gibt, bis zum nächsten Öffnen); Builds speichern, exportieren, importieren, übernehmen (Blizzard-Loadout-Format); Talentplaner: Rechtsklick plant einen Rang (blau, blauer Zähler über dem Talent), Shift + Rechtsklick nimmt ihn zurück, bis Stufe 60, „Plan übernehmen“ | ja |
| Anprobe | Knöpfe „Ausziehen“/„Wieder anziehen“; Klick auf einen Eintrag der Vorlagenliste blendet das Teil aus/ein | – |
| Buff-Erinnerung | Klickbare Aktionstasten für fehlende Klassen-Buffs, Richtung rechts/links/oben/unten, Größe, Vorwarnzeit, leuchtet wie Blizzards Zauberhinweise, bald ablaufende Buffs blass (Deckkraft einstellbar), Zauberwahl je Gruppe (Rüstung, Aspekt, Segen, Aura, Gift …), optional Buffen per Mausrad, in Ruhezonen standardmäßig aus; Talent-Buffs erscheinen, sobald gelernt; verschiebbar im Bearbeitungsmodus | ja |
| Optik | Qualitätsrahmen (2 Pixel, leicht runde Ecken, wie beim Tooltip) auf Gegenstandsknöpfen ab „Ungewöhnlich“ | – |
| | iSquidMod-Endkappen (mit Autorenangabe) | ja |
| | Aktionstasten: außer Reichweite rot, kein Mana blau, nicht verwendbar grau (einzeln) | ja |
| | Drache um das eigene Porträt: Gold, Silber, Bronze, jeweils mit/ohne Flügel; am Porträt ausgerichtet, Größe einstellbar | ja |
| | Buff-Symbole, Questgegenstände im Questtracker und Questbelohnungen mit Aktionstasten-Rahmen und abgerundeten Ecken (Stil: freistehend/Aktionsleiste) | ja |
| | Erfahrungs-, Ruf- und Tooltip-Gesundheitsleiste mit der Leistentextur der Einheitenfenster | ja |
| | Outline für alle Schriften (bereits umrandete werden übersprungen; dunkle Schrift auf Pergament – Quests, Gespräche, Bücher – bleibt ohne) | – |
| Schrift | Globale Schriftart und -größe; je Gruppe (klein, normal, Überschriften, Zahlen, Tooltip, Questtext, Chat) eigene Schriftart und Größe; Schriften aus SharedMedia (LibSharedMedia-3.0) werden angeboten | ja |
| Helfer | Alt: verarbeitbare Taschengegenstände leuchten (lila Entzaubern, gelb Schlossknacken), Alt + Rechtsklick führt es aus | ja |
| | Knopf für öffnbare Gegenstände (Muscheln, Beutel, geknackte Kassetten), Bearbeitungsmodus | ja |
| | Doppel-Rechtsklick in die Welt wirft die Angel aus | ja |
| | Bereits bekannte Rezepte in Taschen und beim Händler ausgegraut | ja |
| Rezeptradar | Händler mit unbekannten Rezepten deiner Berufe auf Welt- und/oder Minimap; Klick setzt Wegpunkt (Daten: QuestieDB, Forever-Datensatz) | ja |
| | Rezeptquellen im Tooltip: Händler + Zone, Quests, Anzahl droppender Gegner | ja |
| Fenster | Alt + Ziehen verschiebt jedes Fenster und jede ForeverPlus-Anzeige, Strg + Mausrad skaliert, Alt + Rechtsklick sperrt; Position/Größe je Element gespeichert | ja |
| | Mehrere Fenster gleichzeitig offen (z. B. Taschen + Charakter + Händler) | ja |

## Technik / CPU

- Nur offizielle API des Forever-Clients (geprüft gegen den Blizzard-UI-Quellcode, Branch `forever`, Build 1.60.1.70205).
- Ausschließlich `hooksecurefunc`/`HookScript`, `TooltipDataProcessor`, Settings-API, `EventRegistry` (Bearbeitungsmodus) – keine Ersetzung von Blizzard-Funktionen.
- Ereignisse werden nur registriert, solange eine Funktion aktiv ist. Dauerhafte `OnUpdate`-Schleifen gibt es nur für das Mouseover-Ausblenden (Prüfung alle 0,1 s, Überblendung nur während des Übergangs). Koordinaten und Minimap-Pins aktualisieren nur während der Bewegung, der Skalierungs-Fänger nur bei gedrückter Strg-Taste.
- Lua-Fehler werden aus Blizzards eigenem `ScriptErrorsFrame` gelesen (kein eigener Error-Handler); das Popup wird über die CVar `scriptErrors` unterdrückt und beim Deaktivieren wiederhergestellt.

## Bekannte Grenzen / ungeprüft

- Kein Test im laufenden Spiel möglich gewesen; geprüft wurden Syntax, `luacheck`, ein Lade-/Initialisierungstest mit simulierter API sowie alle verwendeten Funktionen gegen den Forever-UI-Quellcode.
- Buff-Erinnerung nutzt Classic-Zauber-IDs; nicht existierende IDs werden still übersprungen.
- Rezeptradar und Rezeptquellen benötigen das Addon **QuestieDB** (Teil des Questie-Downloads, GPL-3.0). ForeverPlus liest dessen öffentliche API zur Laufzeit (`LibQuestieDB`), kopiert keine Daten und ist ohne QuestieDB voll funktionsfähig, nur das Rezeptradar ist dann inaktiv. Der Forever-Datensatz von QuestieDB ist selbst noch in Arbeit (laut Projekt nicht vollständig live geprüft).
- „Mehrere Fenster gleichzeitig“ gilt nicht für Spielmenü, Optionen, Zauberbuch, Sammlungen, Dungeonbrowser und geschützte Fenster: deren Anzeige über Addon-Werte zu steuern würde Abmelden/Beenden bzw. Kampfaktionen blockieren (Taint).
- Kopieren in die Zwischenablage ist für Addons gesperrt (`CopyToClipboard` ist eingeschränkt); das Kopier-Symbol markiert den Text, kopiert wird mit Strg+C.
- Schrift: Namen über Köpfen und Kampftext nutzen vom Client beim Start gelesene globale Schriftpfade; diese zu ändern würde Taint riskieren, daher nicht enthalten.
- Auktionshaus: keine zusätzlichen Kategorien/Filter. Kaufen und Einstellen (`PlaceBid`, `PostItem`, …) sind eingeschränkte Funktionen; ob Änderungen an Blizzards Suchlogik sie blockieren, ist ohne Test im Spiel nicht verifizierbar. Die Warnung liest nur Daten und fügt eigene Symbole hinzu.
- Vernichten (`DeleteCursorItem`) ist für Addons gesperrt; deshalb wird der Gegenstand nur aufgenommen und über Blizzards Abfrage vernichtet.
- Sprachwechsel per Mittelklick: setzt die Sprache mit demselben Aufruf wie Blizzards Menü, der Wert stammt aber aus Addon-Code. `SendChatMessage` ist eingeschränkt; ob das Senden in Instanzen dadurch blockiert wird, ist ohne Test nicht verifizierbar. Abschaltbar.
- Talentplaner: prüft keine Voraussetzungen (Punkte je Reihe, vorausgesetzte Talente); „Plan übernehmen“ kauft nur, was der Baum gerade erlaubt, bestätigt wird mit Blizzards Knopf. Rechtsklick auf einen vorgemerkten, noch nicht bestätigten Rang bleibt Blizzards Rückerstattung.
- Zeit bis zum Tod und Färbung nach Gesundheit sind nicht möglich: `UnitHealth` liefert Addons laut Forever-API-Doku immer einen geschützten Wert (`SecretReturns`), das Kampflog ist eingeschränkt.
- Flugzeiten: Daten entstehen erst durch eigene Flüge (keine mitgelieferte Datenbank).
- Peon-Klänge: Datei-IDs 558132 (`peonbuildingcomplete1.ogg`) und 558137 (`peonready1.ogg`) laut Community-Listfile; ob der Forever-Client sie enthält, ist ungeprüft. Fehlt eine Datei, ertönt ein Blizzard-Klang.
- Questtracker-Sortierung: Blizzards Tracker zeigt beobachtete Quests in Beobachtungsreihenfolge und sortiert bei Zonenwechsel selbst nach Nähe; ForeverPlus fügt die Beobachtungen danach in der gewählten Reihenfolge neu hinzu. Ob neue Beobachtungen oben oder unten landen, wird beim ersten Sortieren erkannt.
- Das `ADDON_ACTION_FORBIDDEN`-Popup wird nur protokolliert, nicht unterdrückt (Unterdrücken würde StaticPopups tainten).

- Angeln per Doppel-Rechtsklick: nur mit angelegter Angel; erst nach dem Loslassen eines kurzen, ruhigen Rechtsklicks wird die rechte Maustaste für 0,4 s mit einem sicheren Knopf belegt. Kamera drehen (Rechtsklick halten) und Rechtsklick-Interaktion bleiben unberührt.
- Bekannte Rezepte im Auktionshaus werden nicht ausgegraut (Blizzards Tooltip zeigt dort weiterhin „Bereits bekannt“).

## Danksagungen / Lizenzen

- Code: MIT (siehe `LICENSE`).
- iSquidMod-Grafiken (`Media/iSquidMod`): Ganders & Imithat, Originalautor SAM – WML 1.0, siehe `Media/iSquidMod/LICENSE.txt`.
- Rezeptdaten: zur Laufzeit aus [QuestieDB](https://github.com/Questie/QuestieDB) (Questie-Team).
- Ideen: oGlow (haste), Leatrix Plus, BlizzMove, RecipeRadar, Questie/Quester/Plumber, ncHoverName, ExtraQuestButton.

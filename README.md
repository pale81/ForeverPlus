# ForeverPlus

AddOn für **World of Warcraft: Forever** (Client 1.60.x, TOC-Interface `16001`, Mainline-API 12.x mit „Secret Values“).
Verbessert das originale Forever-Interface (Blizzard-Code „Camelot“) und bleibt optisch beim Original.

Einstellungen: **Esc → Optionen → AddOns → ForeverPlus** (je Thema ein Untermenü) oder `/fp`. Auf der Hauptseite: „Alle Positionen sperren“.
`/fp fehler` öffnet die Fehlerliste, `/fp schrott` die Schrottmarkierungen, `/fp radar` zeigt den Zustand des Rezeptradars.

## Funktionen

| Bereich | Funktion | Option |
|---|---|---|
| Chat | Drei Symbole links vom Chat (Soziales, Kanäle, Chatmenü) ausblenden | ja |
| | Blizzards Chatmenü-Knopf (gelbe Sprechblase) rechts oben am Chat, Sprachauswahl im Menü, aktuelle Sprache im Tooltip | ja |
| | Chatschrift mit Outline | – |
| | Reiter-Hintergründe (Allgemein, Kampflog, …) entfernt | – |
| | Eingabefeld oben über den Reitern, ohne Rahmen/Hintergrund | – |
| | Chathintergrund-Regler auf 0 (100 % transparent) | ja |
| | Pfeil hoch/runter blättert im Eingabeverlauf (ohne Alt) | – |
| Tooltip | Gesundheitsleiste unten im Tooltip | – |
| | Name und Stufe der Einheit unter der Maus neben dem Zeiger (Tooltip-Farbe) | ja |
| | Stückpreis bei Stapeln | ja |
| | Scharfer Rahmen (2 Pixel, leicht abgerundete Ecken) in Qualitätsfarbe bei Gegenständen | – |
| Minimap | Koordinaten (größer, Outline, Klassenfarbe) oben unter dem Norddreieck; verschiebbar, Rechtsklick sperrt | ja |
| Weltkarte | Blizzard-Koordinaten etwas höher, mit der Maus verschiebbar (Position gespeichert), Rechtsklick sperrt | ja |
| Gegenstände | Schrott verkaufen, reparieren (optional aus der Gildenbank) | ja |
| | Mittelklick (Maustaste 3/4/5 wählbar) oder frei belegbare Taste (Tastaturbelegung → AddOns) markiert/entmarkiert als Schrott (gelbe Münze), wird mitverkauft; alles, was verkauft wird, trägt die Münze; graue Gegenstände lassen sich so vom Verkauf ausnehmen; Liste aller Markierungen, Klick entfernt einzeln (`/fp schrott`) | ja |
| | Wertvollste Questbelohnung mit Münze hervorheben | ja |
| | Grüner Pfeil nur bei echter Verbesserung für Klasse und Spezialisierung: beste Rüstungsart der Klasse (Kette/Platte ab Stufe 40), höherer gewichteter Wert als das schwächste getragene Teil des Platzes (Wertgewichte je Spezialisierung, aus der Spielmechanik abgeleitet), verwendbar; keine Berufswerkzeuge | ja |
| | Schnelles Plündern | ja |
| | Schlagwort-Alarm: Klang (wählbar) bei eigenen Schlagwörtern im Chat | ja |
| | Chatmeldungen: je Funktion abschaltbar (Verkauf, Reparatur, Markierung, Wegpunkt, Sperren); Hauptseite: alle ForeverPlus-Meldungen stumm | ja |
| | Taschen voll: billigster Gegenstand (Händlerwert) wird angezeigt, nach Bestätigung aufgenommen; Vernichten über Blizzards eigene Abfrage | ja |
| | Seelengebunden beim Aufheben automatisch bestätigen (Plündern und Würfeln) | ja |
| | Würfelfenster: Anzahl Bedarf/Gier/Passen auf den Knöpfen, Namen beim Überfahren | ja |
| Auktionshaus | Warnsymbol bei Auktionen mit Stückpreis ≤ Händlerpreis, Warnung beim Einstellen | ja |
| Komfort | Mikromenü, Questtracker, Taschenleiste, Aktionsleisten 1–8, Haltungs-/Begleiterleiste nur bei Mouseover (einzeln wählbar, Aktionsleisten standardmäßig aus) | ja |
| | Gegnerische Namensplaketten nur im Kampf | ja |
| | Rote Fehlermeldungen in der Bildschirmmitte ausblenden | ja |
| | Questtracker-Überschrift „Quests 7/25“ (angenommen/Maximum) | – |
| | Questtracker-Sortierung (Questlog, Stufe, Zone, Entfernung, Name, Fortschritt) per Knopf neben dem Zuklapp-Knopf | ja |
| | Fehlerfenster unterdrückt, Fehler gesammelt; Tag/Nacht-Anzeige der Minimap ist der Knopf, leuchtet bei neuen Fehlern; Liste neueste zuerst; Detailfenster mit Vor/Zurück und Kopier-Symbol; Rechtsklick löscht alle Fehler, Shift-Klick lädt das Interface neu | ja |
| | Tastenbelegungs-Nummern und Makronamen auf Aktionstasten ausblenden (einzeln) | ja |
| | Freie/gesamte Taschenplätze am Rucksack | ja |
| | Minimap-Buttons anderer Addons ausblenden (Karten-Pins bleiben) | ja |
| | Gespielte Zeit aller Charaktere im Uhr-Tooltip (ohne Chatmeldung erfasst) | ja |
| | FPS/MS unten in der Minimap (Zahlen in Klassenfarbe); Mouseover: CPU-Zeit aller Addons grün/orange/rot; verschiebbar, Rechtsklick sperrt | ja |
| | Blizzard-Koordinaten unter der Minimap einmalig ausgeschaltet (wieder einschaltbar in den WoW-Optionen) | – |
| Quests | Klang bei Questfortschritt und erledigter Quest (Peon „Arbeit abgeschlossen“ u. a.), Questsymbol mit Fortschritt an Namensplaketten | ja |
| | Extra-Knopf für den Questgegenstand der nächsten Quest (in Reichweite), Bearbeitungsmodus, Tastenbelegung | ja |
| Erfahrungsleiste | Text immer sichtbar; Format: Prozent, Zahl und Prozent, Rest bis Stufe, alles (inkl. Erholung, Quest-EP); EP abgabebereiter Quests als dunkler Balkenteil | ja |
| Talente | „Zauber nach Stufe“ (erlernte grau); Builds speichern, exportieren, importieren, übernehmen (Blizzard-Loadout-Format) | ja |
| Anprobe | Knöpfe „Ausziehen“/„Wieder anziehen“; Klick auf einen Eintrag der Vorlagenliste blendet das Teil aus/ein | – |
| Buff-Erinnerung | Klickbare Aktionstasten für fehlende Klassen-Buffs, Richtung rechts/links/oben/unten, Größe, Vorwarnzeit, leuchtet wie Blizzards Zauberhinweise, bald ablaufende Buffs blass (Deckkraft einstellbar), Zauberwahl je Gruppe (Rüstung, Aspekt, Segen, Aura, Gift …), optional Buffen per Mausrad; Talent-Buffs erscheinen, sobald gelernt; verschiebbar im Bearbeitungsmodus | ja |
| Optik | Qualitätsrahmen (2 Pixel, leicht runde Ecken, wie beim Tooltip) auf Gegenstandsknöpfen ab „Ungewöhnlich“ | – |
| | iSquidMod-Endkappen (mit Autorenangabe) | ja |
| | Aktionstasten: außer Reichweite rot, kein Mana blau, nicht verwendbar grau (einzeln) | ja |
| | Drache um das eigene Porträt: Gold, Silber, Bronze, jeweils mit/ohne Flügel | ja |
| | Buff-Symbole und Questgegenstände im Questtracker mit Aktionstasten-Rahmen und abgerundeten Ecken (Stil: freistehend/Aktionsleiste) | ja |
| | Erfahrungs-, Ruf- und Tooltip-Gesundheitsleiste mit der Leistentextur der Einheitenfenster | ja |
| | Outline für alle Schriften (bereits umrandete werden übersprungen; dunkle Schrift auf Pergament – Quests, Gespräche, Bücher – bleibt ohne) | – |
| Schrift | Globale Schriftart und -größe; je Gruppe (klein, normal, Überschriften, Zahlen, Tooltip, Questtext, Chat) eigene Schriftart und Größe; Schriften aus SharedMedia (LibSharedMedia-3.0) werden angeboten | ja |
| Rezeptradar | Händler mit unbekannten Rezepten deiner Berufe auf Welt- und/oder Minimap; Klick setzt Wegpunkt (Daten: QuestieDB, Forever-Datensatz) | ja |
| | Rezeptquellen im Tooltip: Händler + Zone, Quests, Anzahl droppender Gegner | ja |
| Fenster | Alt + Ziehen verschiebt jedes Fenster, Strg + Mausrad skaliert; Position/Größe je Fenster gespeichert | ja |
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
- Sprachwahl im Chat: kein eigener Ein-Klick-Umschalter. Ein von einem Addon gesetzter Sprachwert würde jede gesendete Chatnachricht „tainten“ (`SendChatMessage` ist eingeschränkt); deshalb wird Blizzards eigener Menü-Knopf versetzt.
- Talentbuilds: Planen geht mit Blizzards Talentbaum (Talente anklicken, nicht übernehmen) bis zur Zahl der vorhandenen Punkte; ein eigener Planer für spätere Stufen ist nicht enthalten. „Übernehmen“ merkt den Build im Baum vor, bestätigt wird mit Blizzards Knopf.
- Peon-Klang: Dateipfad aus dem Classic-Client; fehlt die Datei, ertönt Blizzards Quest-Klang.
- Das `ADDON_ACTION_FORBIDDEN`-Popup wird nur protokolliert, nicht unterdrückt (Unterdrücken würde StaticPopups tainten).

## Danksagungen / Lizenzen

- Code: MIT (siehe `LICENSE`).
- iSquidMod-Grafiken (`Media/iSquidMod`): Ganders & Imithat, Originalautor SAM – WML 1.0, siehe `Media/iSquidMod/LICENSE.txt`.
- Rezeptdaten: zur Laufzeit aus [QuestieDB](https://github.com/Questie/QuestieDB) (Questie-Team).
- Ideen: oGlow (haste), Leatrix Plus, BlizzMove, RecipeRadar, Questie/Quester/Plumber, ncHoverName, ExtraQuestButton.

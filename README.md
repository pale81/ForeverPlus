# ForeverPlus

AddOn für **World of Warcraft: Forever** (Client 1.60.x, TOC-Interface `16001`, Mainline-API 12.x mit „Secret Values“).
Verbessert das originale Forever-Interface (Blizzard-Code „Camelot“) und bleibt optisch beim Original.

Einstellungen: **Esc → Optionen → AddOns → ForeverPlus** (je Thema ein Untermenü) oder `/fp`.
`/fp fehler` öffnet die Fehlerliste, `/fp schrott` die Schrottmarkierungen.

## Funktionen

| Bereich | Funktion | Option |
|---|---|---|
| Chat | Drei Symbole links vom Chat (Soziales, Kanäle, Chatmenü) ausblenden | ja |
| | Chatschrift mit Outline | – |
| | Reiter-Hintergründe (Allgemein, Kampflog, …) entfernt | – |
| | Eingabefeld oben über den Reitern, ohne Rahmen/Hintergrund | – |
| | Chathintergrund-Regler auf 0 (100 % transparent) | ja |
| | Pfeil hoch/runter blättert im Eingabeverlauf (ohne Alt) | – |
| Tooltip | Gesundheitsleiste unten im Tooltip | – |
| | Stückpreis bei Stapeln | ja |
| | Scharfer Rahmen (2 Pixel) in Qualitätsfarbe bei Gegenständen | – |
| Minimap | Koordinaten (größer, Outline, Klassenfarbe) oben unter dem Norddreieck | – |
| Gegenstände | Schrott verkaufen, reparieren (optional aus der Gildenbank) | ja |
| | Mittelklick (Maustaste 3/4/5 wählbar) oder frei belegbare Taste (Tastaturbelegung → AddOns) markiert/entmarkiert als Schrott (gelbe Münze), wird mitverkauft; Liste aller Markierungen, Klick entfernt einzeln (`/fp schrott`) | ja |
| | Wertvollste Questbelohnung mit Münze hervorheben | ja |
| | Grüner Pfeil nur bei echter Verbesserung: höhere Gegenstandsstufe als das schwächste getragene Teil des Platzes, keine geringeren Werte/DPS, verwendbar; keine Berufswerkzeuge | ja |
| | Schnelles Plündern | ja |
| Komfort | Mikromenü, Questtracker, Taschenleiste nur bei Mouseover (einzeln wählbar) | ja |
| | Questtracker-Überschrift „Quests 7/25“ (angenommen/Maximum) | – |
| | Fehlerfenster unterdrückt, Fehler gesammelt; Tag/Nacht-Anzeige der Minimap ist der Knopf, leuchtet bei neuen Fehlern; Liste neueste zuerst; Detailfenster mit Vor/Zurück und Kopier-Symbol | ja |
| | Tastenbelegungs-Nummern und Makronamen auf Aktionstasten ausblenden (einzeln) | ja |
| | Freie/gesamte Taschenplätze am Rucksack | ja |
| | Minimap-Buttons anderer Addons ausblenden (Karten-Pins bleiben) | ja |
| | Blizzard-Koordinaten unter der Minimap ausblenden | ja |
| Anprobe | Knöpfe „Ausziehen“/„Wieder anziehen“; Klick auf einen Eintrag der Vorlagenliste blendet das Teil aus/ein | – |
| Buff-Erinnerung | Klickbare Aktionstasten für fehlende Klassen-Buffs, Richtung rechts/links/oben/unten, Größe, Vorwarnzeit, leuchtet wie Blizzards Zauberhinweise, Zauberwahl je Gruppe (Rüstung, Aspekt, Segen, Aura, Gift …), optional Buffen per Mausrad; Talent-Buffs erscheinen, sobald gelernt; verschiebbar im Bearbeitungsmodus | ja |
| Optik | oGlow: dickes Leuchten in Qualitätsfarbe ab „Ungewöhnlich“ | – |
| | iSquidMod-Endkappen (mit Autorenangabe) | ja |
| | Aktionstasten: außer Reichweite rot, kein Mana blau, nicht verwendbar grau (einzeln) | ja |
| | Buff-Symbole oben rechts mit Aktionsleisten-Rahmen und abgerundeten Ecken | – |
| | Outline für alle Schriften (bereits umrandete werden übersprungen) | – |
| Schrift | Globale Schriftart und -größe; je Gruppe (klein, normal, Überschriften, Zahlen, Tooltip, Questtext, Chat) eigene Schriftart und Größe | ja |
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
- Das `ADDON_ACTION_FORBIDDEN`-Popup wird nur protokolliert, nicht unterdrückt (Unterdrücken würde StaticPopups tainten).

## Danksagungen / Lizenzen

- Code: MIT (siehe `LICENSE`).
- iSquidMod-Grafiken (`Media/iSquidMod`): Ganders & Imithat, Originalautor SAM – WML 1.0, siehe `Media/iSquidMod/LICENSE.txt`.
- Rezeptdaten: zur Laufzeit aus [QuestieDB](https://github.com/Questie/QuestieDB) (Questie-Team).
- Ideen: oGlow (haste), Leatrix Plus (schnelles Plündern), BlizzMove, RecipeRadar.

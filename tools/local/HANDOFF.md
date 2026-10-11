# Übergabe

Stand: `main` nach #119. Alle Änderungen sind eingecheckt; dieser Ordner ist die Arbeitskopie.

## Zuerst lesen
`README.md` (Funktionsliste, bekannte Lücken, was im Spiel ungeprüft ist), `DATA-SOURCES.md` (Datenquellen, Lizenzen),
`CLAUDE.md` bzw. `tools/local/rules.md` (Arbeitsregeln). Prüfen vor jedem Commit: `sh tools/check.sh`.
Im Spiel testen: `/rl`. Fehler und Zustand: `/fp diagnose` (Bericht zum Kopieren), `/fp messen`, `/fp fehler`.

## Aufbau
- `Core/`: Namensraum, Ereignisse, Module, Einstellungen, Mover. `Locales/`: deDE und enUS, immer beide pflegen.
- `Modules/`: ein Thema je Datei. Tooltip (Gegenstands-Zusatzblock, Objektnamen), LootSources (Beute-Herkunft, Namen lernen),
  Observations (NPC-Quests, Positionen), Auction (Händlerwarnung, Kauffilter), Restock (Aufstockliste, Einlagern),
  Talents (Zauber beim Lehrer, Builds, Planer mit blauer Leiste), Quests (Tracker, Plakettensymbol), SpeechBubbles,
  Buffs, Items, Info (FPS/MS, CPU-Liste), WorldMap/MapSymbols (Karte), DataCapture (`/fp daten export`, `/fp diagnose`).
- `Data/`: mitgelieferte Daten, erzeugt von `tools/` (nicht von Hand ändern, außer `Library.lua`). `contrib/`: Beiträge anderer Spieler.
- `tests/run.lua`: nachgebaute WoW-Umgebung; unbekannte Globale sind nachsichtige Platzhalter (ganze Tabellen zuweisen).

## Offene Punkte (im Spiel prüfen)
- Beute-Zusammenfassung (Optionsseite Chat, Standard aus): `/fp beute` zeigt, ob sie läuft und was sie gesehen hat.
- Talentplaner: Planleiste oben rechts im Talentreiter (`/fp talente` zeigt ihren Zustand), blauer Ring an freigeschalteten Talenten.
- Auktionshaus-Kauffilter (Schalter im Suchfiltermenü): Spinner-Zeitgrenze, Mindestabstand 10 %, Leistung beim Blättern.
- Plaketten-Questsymbol für Kreaturen mit Quest-Beute (Klippeneber), Sprechblasen (neu), Tierfähigkeiten beim Lehrer (Jäger).
- Objektnamen bei Mouseover: der Tooltip soll dabei in die Ecke wandern (`SetAnchorType`).
- Spitzen in der Bildzeit: `/fp messen` (zweimal) zeigt, wie viel davon im Addon liegt.

## Daten und Einsendungen
- Einsendungen: Formular „Daten einsenden“ im Projekt, Workflow `.github/workflows/data.yml` macht daraus Pull Requests mit `contrib/<Name>.txt`.
  Voraussetzungen auf GitHub: Actions dürfen Pull Requests erstellen; „Interaction limits“ nicht auf „collaborators only“.
- Einrechnen: `python3 -I tools/contrib.py`, dann `python3 -I tools/build_eg.py <Efficient-Games-Checkout>` (Beute, Gasthäuser, Questdaten, Fahrten).
- Quellen für die Generatoren holt `sh tools/setup-local.sh --data` nach `~/ForeverPlus-dev`.

## Bekannte Beschränkungen
- Kein Talentbaum für Jägertiere im Client; Tierfähigkeiten kommen aus der Liste des Tiertrainers (bei jedem Besuch gespeichert).
- QuestieDB bleibt optional (Instanzeingänge von 10 Instanzen, Instanzquestketten, Spawnpunkte, einige Beutequellen hängen noch daran).
- Alles, was in der README „im Spiel ungeprüft“ heißt, ist nur gegen die Tests und den Blizzard-Quelltext (Forever-Zweig) geprüft.

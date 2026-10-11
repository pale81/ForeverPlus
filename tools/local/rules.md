# ForeverPlus – Arbeitsregeln

Addon für WoW Forever (Client 1.60.x, Mainline-12-API, Spieltyp `camelot`). Lua 5.1 im Spiel, kein `io`/`os`.

## Antworten
- Deutsch, kurz, analytisch. Tatsachen, Schlussfolgerungen und Wertungen trennen; Annahmen kennzeichnen.
- Nicht verifizierbares so nennen („nicht verifizierbar“, „im Spiel ungeprüft“); nichts erfinden.
- Priorität: Fehler, die das Ergebnis ändern. Klare Empfehlung statt künstlichem Mittelweg.

## Code
- Taint-sicher: nur lesen, eigene Regionen hinzufügen, `hooksecurefunc`; Blizzards geschützte Funktionen nie anfassen.
- Jede Funktion bekommt eine Option (Standard sinnvoll wählen). Verschiebbare Elemente starten gesperrt.
- Texte in `Locales/deDE.lua` und `Locales/enUS.lua`, immer beide. Keine Addon-Namen in Menüs außer aus Urheberrechtsgründen.
- Neue Blizzard-Globale in `.luacheckrc` (`read_globals`).
- Messbar halten: Hooks und Skripte mit `ns.Measured` / `ns.SetUpdate` (siehe `/fp messen`).
- Keine Rückschritte: bestehende Funktionen bleiben, es kommen nur Verbesserungen und neue Punkte dazu.
- README.md (und DATA-SOURCES.md bei Daten) bei jeder Änderung nachziehen.

## Daten
- Eigene Daten statt QuestieDB (bleibt optional). Quellen und Lizenzen: DATA-SOURCES.md.
  GPL-Quellen (cMaNGOS, VMaNGOS, Questie, pfQuest, ForeverTome, ForeverGuide) nicht importieren.
- Generatoren: `tools/build_eg.py`, `build_radar.lua`, `build_points.lua`, `build_database.py`; Spielerbeiträge: `contrib/` und `tools/contrib.py`.

## Prüfen (vor jedem Commit)
`sh tools/check.sh` – Tests (`tests/run.lua`) und `luacheck .` müssen ohne Fehler und mit 0 Warnungen durchlaufen.
Einrichtung einmalig: `sh tools/setup-local.sh`.
Harness: unbekannte Globale sind nachsichtige Platzhalter, die nicht in `_G` landen (ganze Tabellen zuweisen);
`C_Timer.After` läuft sofort; neue Tests in `;(function() … end)()` kapseln (200-Locals-Grenze).

## Git
- Commits als EphemeraCore, ohne Co-Autor- oder Sitzungszeilen. Keine KI-Erwähnung in Commits, Pull Requests, Code oder Doku.
- Zweig `main`; Änderungen über Pull Request, Squash-Merge.

## Im Spiel testen
- Der Ordner liegt im AddOns-Verzeichnis; nach Änderungen `/rl`.
- Fehler: `/fp diagnose` (Bericht zum Kopieren), `/fp fehler`, `/fp messen`; Fehlerprotokolle unter `…/_classic_beta_/Logs/`.
- Gespeicherte Daten: `…/_classic_beta_/WTF/Account/<KONTO>/SavedVariables/ForeverPlus.lua`.

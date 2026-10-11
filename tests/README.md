# Tests

`run.lua` lädt alle Dateien aus `ForeverPlus.toc` in einer nachgebauten WoW-Umgebung (unbekannte Globale werden zu nachsichtigen Platzhaltern) und prüft die Module mit `assert`. Die Rezeptradar- und Questdaten-Tests lesen die echten Forever-Daten aus einem QuestieDB-Checkout.

```sh
git clone --depth 1 https://github.com/Questie/QuestieDB.git /pfad/QuestieDB
cd tests
QUESTIEDB=/pfad/QuestieDB/ lua5.1 run.lua ..
```

Ohne `QUESTIEDB` wird `../../QuestieDB/` (neben dem Addon-Ordner) erwartet. Ein Fehler bricht mit `lua5.1: run.lua:<Zeile>: <Meldung>` ab; sonst endet die Ausgabe mit den letzten `… OK`-Zeilen.

`sh tools/check.sh` führt Tests und luacheck zusammen aus (Voraussetzungen: `sh tools/setup-local.sh`).

Weitere Prüfungen:

- `luacheck .` im Addon-Ordner: 0 Warnungen. Neue Blizzard-Globale gehören in `read_globals` in `.luacheckrc`.
- `python3 tools/locales.py strings.json` setzt Texte in `Locales/deDE.lua` und `Locales/enUS.lua` (`{"de": {...}, "en": {...}, "del": [...]}`).

Blizzards Interface-Quellcode des Forever-Clients (Spieltyp `camelot`) zum Nachschlagen:

```sh
git clone --depth 1 -b forever https://github.com/Gethe/wow-ui-source.git
```

`bundled.lua` prüft die mitgelieferten Questdaten (`Data/Database.lua`) ohne QuestieDB und läuft am Ende von `run.lua` mit. `lua5.1 tools/validate_database.lua .` prüft den Aufbau der Datei (im Addon-Ordner aufrufen).

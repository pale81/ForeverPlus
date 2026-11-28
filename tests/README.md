# Tests

`run.lua` lädt (in `suite/01_setup.lua`) alle Dateien aus `ForeverPlus.toc` in einer nachgebauten WoW-Umgebung (unbekannte Globale werden zu nachsichtigen Platzhaltern) und prüft die Module mit `assert`. Die Rezeptradar- und Questdaten-Tests lesen die echten Forever-Daten aus einem QuestieDB-Checkout.

Die Tests stehen in `suite/` (höchstens 1000 Zeilen je Datei) und laufen in der Reihenfolge, die `run.lua` aufführt, in einer gemeinsamen Umgebung. Top-Level-Locals, die eine spätere Datei braucht, stehen in `SHARED` in `run.lua` und werden ohne `local` deklariert; alles andere bleibt `local` in seiner Datei. Neue Tests kommen in die passende Datei; ist sie voll, eine neue anlegen und in `run.lua` eintragen. Eine Datei darf nicht mit `;` beginnen (auch nicht nach Kommentaren): Lua 5.1 bricht dort mit „unexpected symbol near ';'“ ab.

```sh
git clone --depth 1 https://github.com/Questie/QuestieDB.git /pfad/QuestieDB
cd tests
QUESTIEDB=/pfad/QuestieDB/ lua5.1 run.lua ..
```

Ohne `QUESTIEDB` wird `../../QuestieDB/` (neben dem Addon-Ordner) erwartet. Ein Fehler bricht mit `suite/<Datei>:<Zeile>: <Meldung>` ab; sonst endet die Ausgabe mit den letzten `… OK`-Zeilen.

`sh tools/check.sh` führt Tests und luacheck zusammen aus (Voraussetzungen: `sh tools/setup-local.sh`). Der Testlauf verwendet standardmäßig `enUS`. `LOC=deDE sh tools/check.sh` prüft mit deutschen Addon-Texten.

Weitere Prüfungen:

- `luacheck .` im Addon-Ordner: 0 Warnungen. Neue Blizzard-Globale gehören in `read_globals` in `.luacheckrc`.
- `python3 tools/locales.py strings.json` setzt Texte in `Locales/deDE.lua` und `Locales/enUS.lua` (`{"de": {...}, "en": {...}, "del": [...]}`).

Blizzards Interface-Quellcode des Forever-Clients (Spieltyp `camelot`) zum Nachschlagen:

```sh
git clone --depth 1 -b forever https://github.com/Gethe/wow-ui-source.git
```

`bundled.lua` prüft die mitgelieferten Questdaten (`Data/Database.lua`) ohne QuestieDB und läuft am Ende von `run.lua` mit. `lua5.1 tools/validate_database.lua .` prüft den Aufbau der Datei (im Addon-Ordner aufrufen).

---
name: wow-development
description: ForeverPlus-Funktionen und Fehlerkorrekturen in Lua, XML, Daten oder Einstellungen umsetzen. Hilft bei Modulzuständigkeit, Ladefolge, SavedVariables und der WoW-Forever-API.
---

# ForeverPlus entwickeln

- Nutze [die Arbeitsregeln](../../../tools/local/rules.md). `ForeverPlus.toc` bestimmt die Ladefolge. In `Core/Core.lua` registriert `ns:NewModule` Module unter ihrem beständigen Namen. `ADDON_LOADED` lädt die SavedVariables, ruft `OnInitialize` auf und baut die Einstellungen. `PLAYER_LOGIN` ruft `OnLogin` auf. Prüfe bei neuen Abhängigkeiten, welcher Schritt die benötigten Daten bereitstellt.
- Belasse die Funktion im zuständigen Modul unter `Modules/`. Nutze `Core/Settings.lua` und `Core/Settings.xml` für Einstellungen, `Core/Widgets.lua` für gemeinsame UI-Bausteine und `Core/Mover.lua` für verschiebbare Elemente. Verwende `module.defaults` und `module.charDefaults` passend zu `ForeverPlusDB` und `ForeverPlusCharDB`. Prüfe bestehende Profile, Optionswechsel und die automatische NEU-Marke.
- Gleiche neue API-Aufrufe mit Blizzards Forever-UI-Quelltext ab (lokal `~/ForeverPlus-dev/wow-ui-source`, Branch `forever`, Client-Typ `camelot`). Prüfe geschützte Frames und Secret Values am tatsächlichen Aufruf. Nutze bei Bedarf `ns.RunOutOfCombat` und `ns.Secret`. Lies bei Änderungen an Blizzard-Oberflächen auch [die Taint-Falle](../../../docs/fallen/taint-blizzard-zustand.md).
- Nutze die vorhandene Ereignisregistrierung, bei Bedarf `ToggleEvent` und die Messhelfer aus `Core/Core.lua`. Schließe aufgeschobene Arbeit, Timer und Registrierungen passend zum Lebenszyklus ab. Prüfe bei großen Durchläufen `ns.RunSliced`.
- Verfolge bei Datenänderungen den Ladepfad über `Data/DatabaseLoader.lua` oder den betroffenen Datensatz. Halte Generator und erzeugte Daten konsistent und dokumentiere Quellen in [DATA-SOURCES.md](../../../DATA-SOURCES.md).

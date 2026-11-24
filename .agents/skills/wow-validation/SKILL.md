---
name: wow-validation
description: ForeverPlus-Änderungen anhand von Akzeptanzkriterien, Camelot-API, Taint, Performance und Regressionstests prüfen. Nutze den Skill für unabhängige Diffs und gezielte Funktionsprüfungen.
---

# ForeverPlus prüfen

- Verfolge die betroffenen normalen Einstiegspunkte und Zustandswechsel. Prüfe je nach Diff Initialisierung und Reload, vorhandene SavedVariables, Optionswechsel, Kampfgrenzen, optionale Abhängigkeiten und fehlende Daten.
- Vergleiche Signaturen, Ereignisse und geschützte Werte mit dem tatsächlichen Forever-UI-Quelltext auf Branch `forever`. Beachte [die Taint-Falle](../../../docs/fallen/taint-blizzard-zustand.md). Prüfe auch boolesche Secret Values vor Bedingungen und geheime Werte vor Vergleichen oder Verwendung als Tabellenschlüssel.
- Prüfe bei häufigen Events, Hooks, Timern und `OnUpdate` die Arbeit pro Aufruf, doppelte Läufe, Allokationen, Registrierung und Aufräumen. Nutze die Instrumentierung aus `Core/Core.lua`. Bei nötigen Messungen im Spiel sind `/fp messen` und `/fp spitzen` die vorhandenen Einstiegspunkte.
- Führe `sh tools/check.sh` aus. Nutze zusätzlich `LOC=deDE sh tools/check.sh` bei Texten oder locale-abhängigen Pfaden und gezielte Prüffälle für den Diff. Der [Test-Harness](../../../tests/README.md) lädt die TOC und simuliert WoW. Stelle relevante APIs und Zustände explizit nach. Platzhalter für unbekannte Globale und das sofortige `C_Timer.After` können Unterschiede zum Client verdecken.
- Prüfe nach Möglichkeit offline. Nenne Befunde mit Datei und Zeile, dem konkreten Szenario und der Auswirkung. Halte fest, welche Funktionen durch Tests oder Quelltext belegt sind und was im Spiel ungeprüft bleibt.

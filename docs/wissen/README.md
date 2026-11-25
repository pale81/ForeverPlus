# Spielwissen für WoW Forever

Belegte Spielregeln (Klassen, Völker, Zauber, Forever-Abweichungen), damit sie nicht jedes Mal neu gesucht werden.

## Regeln
- Vor jeder spielmechanischen Annahme hier per grep suchen (`grep -rn -i '<Begriff>' docs/wissen`).
- Fehlt der Eintrag: in der Quelle unten belegen und hier ergänzen. Unbelegtes kommt nicht hinein.
- Jeder Eintrag nennt Quelle, Client-Build und Datum. Widerspricht eine neuere Quelle, den Eintrag ersetzen, nicht ergänzen.
- Offene Fragen stehen getrennt unter „Offen“ in der jeweiligen Datei.

## Wo was steht
| Frage | Quelle |
|---|---|
| Welche Klasse hat welchen Zauber | Client-Tabelle `SkillLineAbility` (Spalten `Spell`, `SkillLine`, `ClassMask`), siehe `klassen.md` |
| Was ein Lehrer lehrt, ab welcher Stufe | `Data/TrainerSpells.lua` (bisher nur Schamane) |
| Quests mit Klassen-, Volks-, Stufenbedingungen | `Data/Database.lua` (`requiredRaces`, `requiredClasses`, `requiredLevel`), `Data/QuestsEG.lua` |
| Beute von Gegnern, Händlerwaren | `Data/LootEG.lua`, `Data/VendorItemsEG.lua` |
| Dungeons, Bosse, Stufen | `Data/Instances.lua`, `Data/DungeonJournal*.lua`, `Data/ZoneLevels.lua` |
| Orte, Gasthäuser, Flug- und Schiffsrouten | `Data/Places.lua`, `Data/Inns.lua`, `Data/TransportPaths.lua` |
| Talent-Vorlagen | `Data/TalentPresets.lua` |
| Blizzard-API, Templates, Atlanten, Schriften | `~/ForeverPlus-dev/wow-ui-source` (Branch `forever`) |
| Herkunft und Lizenz der Daten | `DATA-SOURCES.md` |

## Client-Tabellen abfragen
Alle Tabellen des Clients als CSV, Build passend zum Client wählen (die Kopfzeilen in `Data/` nennen ihn):

```sh
curl -s "https://wago.tools/db2/<Tabelle>/csv?build=1.60.1.71037" -o <Tabelle>.csv
```

# Klassen und Zauber

`ClassMask` in `SkillLineAbility`: Bit `2^(ClassID-1)`, ClassID aus `ChrClasses` (Schamane = 7 → 64).

## Belegt
- **Klassen im Client: 9.** `ChrClasses`: 1 Krieger, 2 Paladin, 3 Jäger, 4 Schurke, 5 Priester, 7 Schamane, 8 Magier, 9 Hexenmeister, 11 Druide. Keine Todesritter, Mönche, Dämonenjäger, Rufer. Build 1.60.1.71037, geprüft 2026-11-25.
- **Geisterwolf (2645): nur Schamane.** `SkillLineAbility` ID 8700: SkillLine 373, ClassMask 64. Build 1.60.1.71037, geprüft 2026-11-25.

## Offen
- Geisterwolf steht nicht in `Data/TrainerSpells.lua`. Wie er in Forever gelernt wird (Quest, automatisch, Stufe), ist nicht belegt.

# Klassen und Zauber

`ClassMask` in `SkillLineAbility`: Bit `2^(ClassID-1)`, ClassID aus `ChrClasses` (Schamane = 7 → 64).

## Belegt
- **Klassen im Client: 9.** `ChrClasses`: 1 Krieger, 2 Paladin, 3 Jäger, 4 Schurke, 5 Priester, 7 Schamane, 8 Magier, 9 Hexenmeister, 11 Druide. Keine Todesritter, Mönche, Dämonenjäger, Rufer. Build 1.60.1.71037, geprüft 2026-11-25.
- **Geisterwolf (2645): nur Schamane.** `SkillLineAbility` ID 8700: SkillLine 373, ClassMask 64. Build 1.60.1.71037, geprüft 2026-11-25.
- **Rüstungs- und Waffenfertigkeiten (inkl. beim Lehrer/Waffenmeister lernbarer Fertigkeiten).** `SkillLineAbility` (Kategorien 6 und 8) sowie `ItemSubClass` (ClassID 2 und 4), Build 1.60.1.71037, geprüft 2026-11-28:
  - Rüstung: Stoff (`4/1`, SL 415, Maske 1503) alle 9 Klassen; Leder (`4/2`, SL 414, Maske 1103) Krieger, Paladin, Jäger, Schurke, Schamane, Druide; Kette (`4/3`, SL 413, Maske 71) Krieger, Paladin, Jäger, Schamane; Platte (`4/4`, SL 293, Maske 3) Krieger, Paladin; Schilde (`4/6`, SL 433, Maske 67) Krieger, Paladin, Schamane; Relikte laut `ItemSubClass`: Buchbände (`4/7`) Paladin, Götzen (`4/8`) Druide, Totems (`4/9`) Schamane.
  - Waffen: Einhandäxte (`2/0`, SL 44, Maske 79) Krieger, Paladin, Jäger, Schurke, Schamane; Zweihandäxte (`2/1`, SL 172, Maske 71) Krieger, Paladin, Jäger, Schamane; Bögen (`2/2`, SL 45, Maske 13), Schusswaffen (`2/3`, SL 46, Maske 13), Wurfwaffen (`2/16`, SL 176, Maske 13), Armbrüste (`2/18`, SL 226, Maske 13) Krieger, Jäger, Schurke; Einhandstreitkolben (`2/4`, SL 54, Maske 1115) Krieger, Paladin, Schurke, Priester, Schamane, Druide; Zweihandstreitkolben (`2/5`, SL 160, Maske 1091) Krieger, Paladin, Schamane, Druide; Stangenwaffen (`2/6`, SL 229, Maske 1031) Krieger, Paladin, Jäger, Druide; Einhandschwerter (`2/7`, SL 43, Maske 399) Krieger, Paladin, Jäger, Schurke, Magier, Hexenmeister; Zweihandschwerter (`2/8`, SL 55, Maske 7) Krieger, Paladin, Jäger; Stäbe (`2/10`, SL 136, Maske 1493) Krieger, Jäger, Priester, Schamane, Magier, Hexenmeister, Druide; Faustwaffen (`2/13`, SL 473, Maske 1101) Krieger, Jäger, Schurke, Schamane, Druide; Dolche (`2/15`, SL 173, Maske 1501) alle außer Paladin; Zauberstäbe (`2/19`, SL 228, Maske 400) Priester, Magier, Hexenmeister. Sonstige Waffen (`2/14`, z. B. Spitzhacken/Kürschnermesser) und Angelruten (`2/20`) für alle Klassen.

## Offen
- Geisterwolf steht nicht in `Data/TrainerSpells.lua`. Wie er in Forever gelernt wird (Quest, automatisch, Stufe), ist nicht belegt.

# Builds Data/TalentPresets.lua: suggested talent distributions per class for the
# talent planner ("Vorlage übernehmen"). The trees come from the game tables
# TraitNode, TraitNodeEntry, TraitNodeXTraitNodeEntry, TraitDefinition,
# TraitEdge and SpellName (CSV from wago.tools/db2 for the client build); the
# distributions are the authors' own suggestions: a talent priority per
# specialisation, filled up by the rules of the classic trees (5 points per
# row, arrows need their source talent at full rank).
# Usage: python3 -I tools/build_presets.py <folder with the CSV files> BUILD
import csv
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POINTS_PER_ROW = 5
SUFFICIENT, REQUIRED = 2, 3  # edge types: one source at full rank is enough / every source is needed
ROW_TOLERANCE = 50
ERRORS = []  # wrong names or ranks: reported together, nothing is written  # node positions of one row differ by up to 10 units

# class file -> trait tree of the class (the tree 1083 is an older Druid copy)
CLASS_TREE = {
    'SHAMAN': 1082, 'DRUID': 1089, 'HUNTER': 1091, 'PALADIN': 1100, 'ROGUE': 1111,
    'MAGE': 1112, 'PRIEST': 1114, 'WARLOCK': 1116, 'WARRIOR': 1117,
}
# Names of the three specialisations (left, middle, right in the tree): German, English.
SPECS = {
    'WARRIOR': [('Waffen', 'Arms'), ('Furor', 'Fury'), ('Schutz', 'Protection')],
    'PALADIN': [('Heilig', 'Holy'), ('Schutz', 'Protection'), ('Vergeltung', 'Retribution')],
    'HUNTER': [('Tierherrschaft', 'Beast Mastery'), ('Treffsicherheit', 'Marksmanship'), ('Überleben', 'Survival')],
    'ROGUE': [('Meucheln', 'Assassination'), ('Kampf', 'Combat'), ('Täuschung', 'Subtlety')],
    'PRIEST': [('Disziplin', 'Discipline'), ('Heilig', 'Holy'), ('Schatten', 'Shadow')],
    'SHAMAN': [('Elementar', 'Elemental'), ('Verstärkung', 'Enhancement'), ('Wiederherstellung', 'Restoration')],
    'MAGE': [('Arkan', 'Arcane'), ('Feuer', 'Fire'), ('Frost', 'Frost')],
    'WARLOCK': [('Gebrechen', 'Affliction'), ('Dämonologie', 'Demonology'), ('Zerstörung', 'Destruction')],
    'DRUID': [('Gleichgewicht', 'Balance'), ('Wilder Kampf', 'Feral'), ('Wiederherstellung', 'Restoration')],
}

# Each build: (German name, English name or None for the specialisation names,
# {specialisation index: points}, {specialisation index: [talent names in order of importance]}).
# Talents not named are filled in row by row. Names are those of the client (English).
BUILDS = {
    'WARRIOR': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Mortal Strike', 'Two-Handed Weapon Specialization', 'Deep Wounds', 'Impale', 'Improved Heroic Strike',
                'Anger Management', 'Sweeping Strikes', 'Improved Overpower', 'Improved Charge', 'Improved Slam'],
            1: ['Cruelty', 'Unbridled Wrath', 'Enrage', 'Booming Voice']}),
        (None, None, {1: 31, 0: 20}, {
            1: ['Bloodthirst', 'Death Wish', 'Flurry', 'Enrage', 'Cruelty', 'Dual Wield Specialization', 'Unbridled Wrath',
                'Improved Berserker Rage', 'Furious Precision', 'Blood Craze', 'Gore Drinker'],
            0: ['Improved Heroic Strike', 'Anger Management', 'Deep Wounds', 'Improved Charge']}),
        (None, None, {2: 31, 1: 20}, {
            2: ['Shield Slam', 'Last Stand', 'Shield Specialization', 'Defiance', 'Anticipation', 'Improved Shield Wall',
                'Concussion Blow', 'Bastion', 'Focused Rage', 'Master of Defense', 'Improved Revenge', 'Improved Sunder Armor',
                'Improved Thunder Clap'],
            1: ['Cruelty', 'Unbridled Wrath', 'Enrage', 'Booming Voice']}),
        ('Furor-Schutz (Tank mit Furor)', 'Fury-Prot (fury tank)', {1: 31, 2: 20}, {
            1: ['Bloodthirst', 'Death Wish', 'Flurry', 'Enrage', 'Cruelty', 'Dual Wield Specialization', 'Unbridled Wrath'],
            2: ['Shield Specialization', 'Anticipation', 'Improved Bloodrage', 'Improved Revenge', 'Defiance', 'Iron Will']}),
    ],
    'PALADIN': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Holy Shock', 'Illumination', 'Divine Favor', 'Holy Power', "Light's Vigil", 'Healing Light',
                'Divine Precision', 'Infusion of Light', 'Reverence', 'Improved Seals', 'Purifying Power', 'Consecrated Ground'],
            1: ['Redoubt', 'Toughness', 'Precision', "Guardian's Favor", 'Anticipation']}),
        (None, None, {1: 31, 0: 20}, {
            1: ['Holy Shield', 'Iron Creed', 'Reckoning', "Templar's Bulwark", 'One-Handed Weapon Specialization',
                'Shield Specialization', 'Redoubt', 'Toughness', 'Precision', 'Improved Righteous Fury', 'Sacred Duty',
                'Anticipation', 'Improved Hammer of Justice', 'Swift Judgement'],
            0: ['Divine Strength', 'Healing Light', 'Improved Seals', 'Spiritual Focus']}),
        (None, None, {2: 31, 1: 20}, {
            2: ['Twist of Light', 'Champion of the Light', 'Instrument of Law', 'Two-Handed Weapon Specialization', 'Vengeance',
                'Repentance', 'Conviction', 'Sanctified Judgement', 'Seal of Command', 'Benediction', 'Vindication',
                'Pursuit of Justice', 'Improved Judgement', 'Sacred Arbiter', 'Eye for an Eye'],
            1: ['Precision', 'Toughness', 'Redoubt', "Guardian's Favor", 'Anticipation']}),
        ('Schockadin (Heilig/Vergeltung)', 'Shockadin (Holy/Retribution)', {0: 31, 2: 20}, {
            0: ['Holy Shock', 'Illumination', 'Divine Favor', 'Holy Power', "Light's Vigil", 'Healing Light',
                'Divine Precision', 'Infusion of Light', 'Reverence'],
            2: ['Benediction', 'Conviction', 'Improved Judgement', 'Vindication', 'Seal of Command']}),
    ],
    'HUNTER': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Bestial Wrath', 'Frenzy', 'Bestial Discipline', 'Intimidation', 'Spirit Bond', 'Ferocity', 'Unleashed Fury',
                'Bestial Swiftness', 'Endurance Training', 'Focused Fire', 'Improved Aspect of the Monkey', 'Improved Mend Pet',
                'Deadly Aspects'],
            1: ['Lethal Attacks', 'Careful Aim', 'Efficiency', 'Hawk Eye', 'Improved Arcane Shot']}),
        (None, None, {1: 31, 2: 20}, {
            1: ['Sniper Shot', 'Ranged Weapon Specialization', 'Mortal Shots', 'Barrage', 'Trueshot Aura', 'Lethal Attacks',
                'Careful Aim', 'Efficiency', 'Improved Arcane Shot', 'Rapid Killing', 'Hawk Eye', 'Improved Stings',
                'Scatter Shot', 'Rapid Recuperation', 'Lone Wolf'],
            2: ['Survivalist', 'Savage Strikes', 'Surefooted', 'Deflection', 'Improved Tracking']}),
        (None, None, {2: 31, 1: 20}, {
            2: ['Lacerating Strikes', "Predator's Edge", 'Lightning Reflexes', 'Survival Tactics', 'Counterattack', 'Deterrence',
                'Surefooted', 'Expose Prey', "Survivalist's Discipline", 'Resourcefulness', 'Entrapment', 'Savage Strikes',
                'Survivalist', 'Clever Traps', 'Strider Kick'],
            1: ['Lethal Attacks', 'Careful Aim', 'Efficiency', 'Hawk Eye', 'Mortal Shots']}),
        ('Tierherrschaft/Überleben', 'Beast Mastery/Survival', {0: 31, 2: 20}, {
            0: ['Bestial Wrath', 'Frenzy', 'Bestial Discipline', 'Intimidation', 'Spirit Bond', 'Ferocity', 'Unleashed Fury',
                'Bestial Swiftness', 'Endurance Training', 'Focused Fire'],
            2: ['Survivalist', 'Savage Strikes', 'Surefooted', 'Deflection', 'Improved Tracking']}),
    ],
    'ROGUE': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Mutilate', 'Venom', 'Seal Fate', 'Malice', 'Lethality', 'Ruthlessness', 'Relentless Strikes', 'Cold Blood',
                'Improved Poisons', 'Vile Poisons', 'Remorseless Attacks', 'Improved Kidney Shot', 'Blood Splatter', 'Vigor',
                'Improved Slice and Dice'],
            1: ['Improved Eviscerate', 'Improved Sinister Strike', 'Precision', 'Puncturing Wounds', 'Lightning Reflexes']}),
        (None, None, {1: 31, 0: 20}, {
            1: ['Adrenaline Rush', 'Blade Flurry', 'Dual Wield Specialization', 'Hack and Slash', 'Weapon Expertise',
                'Aggression', 'Precision', 'Improved Sinister Strike', 'Improved Eviscerate', 'Lightning Reflexes',
                'Puncturing Wounds', 'Flawless Execution', 'Improved Kick', 'Endurance', 'Riposte'],
            0: ['Malice', 'Lethality', 'Ruthlessness', 'Remorseless Attacks', 'Vigor']}),
        (None, None, {2: 31, 1: 20}, {
            2: ['Thousand Cuts', 'Cutthroat', 'Quietus', 'Preparation', 'Premeditation', 'Hemorrhage', 'Dirty Deeds',
                'Serrated Blades', 'Heightened Senses', 'Initiative', 'Ghostly Strike', 'Improved Ambush', 'Elusiveness',
                'Master of Deception', 'Setup', 'Opportunity'],
            1: ['Improved Sinister Strike', 'Lightning Reflexes', 'Precision', 'Improved Eviscerate', 'Dual Wield Specialization']}),
        ('Meucheln/Täuschung (Dolche)', 'Assassination/Subtlety (daggers)', {0: 31, 2: 20}, {
            0: ['Mutilate', 'Venom', 'Seal Fate', 'Malice', 'Lethality', 'Ruthlessness', 'Relentless Strikes', 'Cold Blood',
                'Improved Poisons', 'Vile Poisons', 'Remorseless Attacks', 'Blood Splatter'],
            2: ['Master of Deception', 'Opportunity', 'Camouflage', 'Setup', 'Initiative', 'Elusiveness']}),
    ],
    'PRIEST': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Power Infusion', 'Divine Aegis', 'Penance', 'Renewed Hope', 'Inner Focus', 'Mental Strength',
                'Improved Power Word: Shield', 'Meditation', 'Mental Agility', 'Power in Light', 'Twin Disciplines',
                'Silent Resolve', 'Improved Inner Fire', 'Soul Warding'],
            1: ['Holy Specialization', 'Divine Fury', 'Improved Renew', 'Spell Warding']}),
        (None, None, {1: 31, 0: 20}, {
            1: ['Prayer of Mending', 'Spiritual Healing', 'Spiritual Guidance', 'Litany of Light', 'Spirit of Redemption',
                'Improved Healing', 'Holy Binding', 'Searing Light', 'Holy Reach', 'Inspiration', 'Blessed Recovery',
                'Holy Nova', 'Divine Fury', 'Spell Warding', 'Holy Specialization', 'Improved Renew'],
            0: ['Power in Light', 'Twin Disciplines', 'Silent Resolve', 'Improved Power Word: Shield', 'Mental Agility',
                'Inner Focus']}),
        (None, None, {2: 31, 0: 20}, {
            2: ['Shadowform', 'Darkness', 'Early Demise', 'Devouring Contagion', 'Silence', 'Shadow Weaving', 'Vampiric Embrace',
                'Improved Mind Blast', 'Improved Mind Flay', 'Mind Flay', 'Shadow Focus', 'Blackout', 'Spirit Tap',
                'Improved Shadow Word: Pain'],
            0: ['Twin Disciplines', 'Power in Light', 'Silent Resolve', 'Improved Power Word: Shield', 'Meditation',
                'Mental Agility', 'Inner Focus']}),
        ('Schatten/Heilig', 'Shadow/Holy', {2: 31, 1: 20}, {
            2: ['Shadowform', 'Darkness', 'Early Demise', 'Devouring Contagion', 'Silence', 'Shadow Weaving', 'Vampiric Embrace',
                'Improved Mind Blast', 'Improved Mind Flay', 'Mind Flay', 'Shadow Focus', 'Blackout', 'Spirit Tap'],
            1: ['Holy Specialization', 'Divine Fury', 'Improved Renew', 'Spell Warding', 'Twilight Focus']}),
    ],
    'SHAMAN': [
        (None, None, {0: 31, 2: 20}, {
            0: ['Convection', 'Concussion', 'Call of Flame', 'Elemental Focus', 'Reverberation', 'Elemental Devastation',
                'Call of Thunder', 'Lightning Overload', 'Elemental Fury', 'Lightning Mastery', 'Elemental Alacrity', 'Elemental Reach'],
            2: ['Totemic Focus', 'Tidal Focus', 'Natural Grace', 'Mindfulness', 'Water Shield']}),
        (None, None, {1: 31, 0: 20}, {
            1: ['Thundering Strikes', 'Ancestral Knowledge', 'Flurry', 'Elemental Weapons', 'Shamanistic Focus', 'Stormstrike',
                'Improved Stormstrike', 'Maelstrom Weapon', 'Mental Quickness', 'Toughness', 'Spirit Weapons', 'Anticipation',
                'Rage of the Farseer'],
            0: ['Convection', 'Concussion', 'Call of Flame', 'Elemental Focus', 'Reverberation']}),
        (None, None, {2: 31, 0: 20}, {
            2: ['Improved Healing Wave', 'Tidal Focus', 'Totemic Focus', 'Natural Grace', 'Healing Focus', 'Ancestral Healing',
                'Tidal Mastery', 'Restorative Totems', 'Mana Tide Totem', 'Purification', 'Healing Way', "Nature's Swiftness",
                'Riptide', 'Water Shield', 'Mindfulness'],
            0: ['Convection', 'Concussion', 'Call of Flame', 'Elemental Focus']}),
        ('Verstärkung/Wiederherstellung', 'Enhancement/Restoration', {1: 31, 2: 20}, {
            1: ['Thundering Strikes', 'Ancestral Knowledge', 'Flurry', 'Elemental Weapons', 'Shamanistic Focus', 'Stormstrike',
                'Improved Stormstrike', 'Maelstrom Weapon', 'Mental Quickness', 'Toughness', 'Spirit Weapons'],
            2: ['Improved Healing Wave', 'Tidal Focus', 'Totemic Focus', 'Natural Grace', 'Water Shield']}),
    ],
    'MAGE': [
        (None, None, {0: 31, 2: 20}, {
            0: ['Arcane Power', 'Presence of Mind', 'Arcane Instability', 'Arcane Mind', 'Arcane Blast', 'Missile Barrage',
                'Arcane Meditation', 'Arcane Concentration', 'Arcane Wrath', 'Arcane Impact', 'Arcane Geometry',
                'Improved Counterspell', 'Arcane Subtlety', 'Magic Absorption'],
            2: ['Precision', 'Improved Frostbolt', 'Ice Shards', 'Frostbite', 'Frost Channeling']}),
        (None, None, {1: 31, 2: 20}, {
            1: ['Combustion', 'Fire Power', 'Critical Mass', 'Ignite', 'Incineration', 'Accelerant', 'Pyroblast',
                'Blast Wave', 'Master of Elements', 'Heating Up', 'Impact', 'Burning Soul', 'Improved Scorch', 'Flame Throwing'],
            2: ['Precision', 'Improved Frostbolt', 'Ice Shards', 'Frostbite', 'Frost Channeling']}),
        (None, None, {2: 31, 0: 20}, {
            2: ['Ice Barrier', "Winter's Chill", 'Fingers of Frost', 'Cold Snap', 'Improved Cone of Cold', 'Shatter', 'Ice Block',
                'Ice Lance', 'Arctic Reach', 'Fingers of Frost', 'Precision', 'Improved Frostbolt', 'Ice Shards',
                'Permafrost', 'Frostbite', 'Frost Channeling'],
            0: ['Arcane Concentration', 'Arcane Subtlety', 'Arcane Geometry', 'Arcane Impact', 'Arcane Blast']}),
        ('Frost/Feuer', 'Frost/Fire', {2: 31, 1: 20}, {
            2: ['Ice Barrier', "Winter's Chill", 'Fingers of Frost', 'Cold Snap', 'Shatter', 'Ice Block', 'Ice Lance',
                'Fingers of Frost', 'Precision', 'Improved Frostbolt', 'Ice Shards', 'Permafrost'],
            1: ['Incineration', 'Ignite', 'Impact', 'Accelerant', 'Improved Scorch']}),
    ],
    'WARLOCK': [
        (None, None, {0: 31, 1: 20}, {
            0: ['Shadow Mastery', 'Siphon Life', 'Soul Siphon', 'Malevolence', 'Nightfall', 'Pandemic', 'Fel Concentration',
                'Improved Bane of Agony', 'Amplify Curse', 'Wrack', 'Improved Corruption', 'Suppression'],
            1: ['Demonic Embrace', 'Improved Imp', 'Fel Vitality', 'Unholy Power', 'Improved Voidwalker']}),
        (None, None, {1: 31, 2: 20}, {
            1: ['Master Demonologist', 'Demonic Knowledge', 'Soul Link', 'Demonic Sacrifice', 'Decimation', 'Master Summoner',
                'Fel Domination', 'Improved Felhunter', 'Demonic Brand', 'Improved Sayaad', 'Demonic Embrace', 'Unholy Power',
                'Fel Vitality', 'Improved Imp', 'Demonic Aegis'],
            2: ['Improved Shadow Bolt', 'Bane', 'Cataclysm', 'Aftermath', 'Molten Skin']}),
        (None, None, {2: 31, 0: 20}, {
            2: ['Incinerate', 'Shadow and Flame', 'Fire and Brimstone', 'Pyroclasm', 'Conflagrate', 'Shadowburn', 'Ruin',
                'Intensity', 'Agonizing Flames', 'Bane', 'Improved Shadow Bolt', 'Cataclysm', 'Aftermath', 'Molten Skin'],
            0: ['Suppression', 'Improved Corruption', 'Soul Harvest', 'Improved Drains']}),
        ('Opferung (Dämonologie/Zerstörung)', 'Sacrifice (Demonology/Destruction)', {1: 21, 2: 30}, {
            1: ['Demonic Embrace', 'Improved Imp', 'Fel Vitality', 'Unholy Power', 'Demonic Aegis', 'Demonic Sacrifice',
                'Improved Voidwalker', 'Master Summoner'],
            2: ['Improved Shadow Bolt', 'Bane', 'Cataclysm', 'Aftermath', 'Ruin', 'Shadowburn', 'Intensity', 'Conflagrate',
                'Pyroclasm', 'Fire and Brimstone']}),
    ],
    'DRUID': [
        (None, None, {0: 31, 2: 20}, {
            0: ['Moonkin Form', 'Moonfury', 'Eclipse', "Nature's Grace", 'Vengeance', 'Improved Starfire', 'Overgrowth',
                'Insect Swarm', 'Improved Wrath', 'Genesis', 'Improved Entangling Roots', "Nature's Splendor",
                'Improved Moonfire', "Nature's Majesty", 'Moonglow'],
            2: ["Nature's Focus", 'Heart of the Wild', 'Naturalist', 'Subtlety', 'Natural Shapeshifter']}),
        (None, None, {1: 31, 2: 20}, {
            1: ['Primal Bite', 'Natural Reaction', 'Rend and Tear', 'Leader of the Pack', 'Predatory Strikes',
                'Shifting Power', 'Primal Bite', 'Blood Frenzy', 'Natural Instinct', 'Savage Fury',
                'Sharpened Claws', 'Shredding Attacks', 'Feral Charge', 'Feral Swiftness', 'Ferocity', 'Furor'],
            2: ['Heart of the Wild', 'Naturalist', "Nature's Focus", 'Natural Shapeshifter']}),
        (None, None, {2: 31, 1: 20}, {
            2: ['Wild Growth', 'Improved Regrowth', 'Swiftmend', "Nature's Swiftness", 'Living Spirit', 'Improved Tranquility',
                'Improved Rejuvenation', 'Tranquil Spirit', 'Bloom', 'Gift of Nature', 'Reflection',
                'Naturalist', 'Subtlety', 'Natural Shapeshifter', 'Heart of the Wild', "Nature's Focus"],
            1: ['Ferocity', 'Furor', 'Feral Instinct', 'Feral Swiftness', 'Thick Hide']}),
        ('Bär (Wilder Kampf/Wiederherstellung)', 'Bear (Feral/Restoration)', {1: 31, 2: 20}, {
            1: ['Thick Hide', 'Feral Instinct', 'Furor', 'Brutal Impact', 'Sharpened Claws', 'Predatory Strikes',
                'Natural Reaction', 'Feral Charge', 'Savage Fury', 'Leader of the Pack', 'Primal Bite', 'Ferocity'],
            2: ['Heart of the Wild', 'Naturalist', "Nature's Focus", 'Natural Shapeshifter']}),
    ],
}


# Builds of the WoW Forever class guides of buffed.de (November 2026), replacing our own suggestions of the same
# specialisation: the talents with the ranks the guide names, in its order. The guides for paladins stop at about
# level 40: their main tree is the guide's, the rest (`fill`) our suggestion. Index: place in BUILDS[class].
GUIDES = {
    'ROGUE': {
        0: {'talents': [('Gnadenlose Angriffe', 2), ('Tücke', 5), ('Verbessertes Zerhäckseln', 3), ('Tödlichkeit', 2),
                        ('Skrupellosigkeit', 3), ('Kaltblütigkeit', 1), ('Verbesserte Gifte', 5), ('Toxin', 1),
                        ('Unerbittliche Stöße', 5), ('Schicksal besiegeln', 3), ('Verstümmeln', 1),
                        ('Günstige Gelegenheit', 5), ('Blitzartige Reflexe', 5), ('Durchbohrende Wunden', 3),
                        ('Präzision', 3), ('Verbessertes Sprinten', 2), ('Durchhaltevermögen', 2)]},
        1: {'talents': [('Efficient Strikes', 2), ('Gnadenstoß', 3), ('Abwehr', 3), ('Präzision', 3), ('Riposte', 1),
                        ('Durchhaltevermögen', 2), ('Composure', 2), ('Perfekte Ausführung', 1), ('Aggression', 3),
                        ('Klingenwirbel', 1), ('Niedermetzeln', 5), ('Beidhändigkeitsspezialisierung', 2),
                        ('Flash of Steel', 5), ('Adrenalinrausch', 1), ('Waffenexperte', 2),
                        ('Tücke', 5), ('Skrupellosigkeit', 3), ('Verbessertes Zerhäckseln', 3), ('Lebenskraft', 2),
                        ('Tödlichkeit', 2)]},
        2: {'talents': [('Günstige Gelegenheit', 5), ('Camouflage', 3), ('Verbesserter Hinterhalt', 3), ('Initiative', 3),
                        ('Gezahnte Klingen', 3), ('Geisterhafter Stoß', 1), ('Konzentration', 1), ('Gemeinheiten', 2),
                        ('Blutsturz', 1), ('Vorbereitung', 1), ('Flüchtigkeit', 2), ('Boot Knife', 5), ('Todesmal', 1),
                        ('Gnadenstoß', 3), ('Effiziente Schläge', 2), ('Präzision', 3), ('Tücke', 5),
                        ('Skrupellosigkeit', 3), ('Verbessertes Zerhäckseln', 3), ('Blood Splatter', 1)]},
    },
    'HUNTER': {
        0: {'talents': [('Tödliche Aspekte', 5), ('Konzentriertes Feuer', 2), ('Verbessertes Tier wiederbeleben', 2),
                        ('Belastbarkeit-Ausbildung', 1), ('Entfesselter Zorn', 5), ('Falke beschwören', 1),
                        ('Erhöhte Tiergeschwindigkeit', 1), ('Wildheit', 5), ('Einschüchterung', 1), ('Orientierung', 1),
                        ('Wildtierdisziplin', 1), ('Raserei', 5), ('Zorn des Wildtiers', 1),
                        ('Tödliche Angriffe', 5), ('Sorgfältiges Zielen', 5), ('Effizienz', 5), ('Aura des Volltreffers', 1),
                        ('Todbringende Schüsse', 4)]},
        1: {'talents': [('Tödliche Angriffe', 5), ('Sorgfältiges Zielen', 5), ('Falkenauge', 3), ('Schneller Tod', 2),
                        ('Todbringende Schüsse', 5), ('Aura des Volltreffers', 1), ('Sperrfeuer', 3), ('Streuschuss', 1),
                        ('Distanzwaffen-Spezialisierung', 5), ('Heckenschützenschuss', 1), ('Effizienz', 5),
                        ('Rasche Erholung', 2), ('Verbesserte Stiche und Bisse', 3),
                        ('Tödliche Aspekte', 5), ('Verbessertes Fährtenlesen', 5)]},
    },
    'PALADIN': {
        0: {'talents': [('Spiritueller Fokus', 5), ('Heilendes Licht', 3), ('Andacht', 2), ('Illumination', 5),
                        ('Eid des Lichts', 1), ('Lichtinfusion', 2), ('Göttliche Gunst', 1), ('Reinigende Macht', 2),
                        ('Heiliger Schock', 1), ('Grenzenloses Licht', 2), ('Göttliche Präzision', 2), ('Heilige Kraft', 5),
                        ('Lichtwacht', 1), ('Göttliche Weisheit', 5)],
            'fill': {1: 14}, 'fill_priorities': {1: ['Redoubt', 'Toughness', 'Precision', "Guardian's Favor", 'Anticipation']}},
        1: {'talents': [('Verschanzen', 5), ('Präzision', 3), ('Heilige Pflicht', 2), ('Schild-Spezialisierung', 2),
                        ('Zähigkeit', 3), ('Bollwerk des Templers', 1), ('Vorahnung', 5), ('Schnelles Richturteil', 1),
                        ('Verbesserter Zorn der Gerechtigkeit', 3), ('Heiliger Schild', 1), ('Abrechnung', 5),
                        ('Eiserner Glaube', 3), ('Schildgeschworen', 1)],
            'fill': {2: 16}, 'fill_priorities': {2: ['Abwehr', 'Verbessertes Richturteil', 'Segnung', 'Überzeugung']}},
        2: {'talents': [('Segnung', 5), ('Verbessertes Richturteil', 2), ('Gesegnetes Richturteil', 3),
                        ('Siegel des Befehls', 1), ('Überzeugung', 3), ('Streben nach Gerechtigkeit', 2),
                        ('Zweihandwaffen-Spezialisierung', 3), ('Heiliger Richter', 1), ('Rache', 3), ('Buße', 1),
                        ('Rechtschaffene Schwächung', 1), ('Champion des Lichts', 5), ('Entfesselter Zorn', 1)],
            'fill': {0: 12, 1: 8}, 'fill_priorities': {0: ['Göttliche Stärke', 'Verbesserte Siegel', 'Holy Conduit'],
                                                     1: ['Göttliche Weisheit', 'Precision']}},
    },
}
for _class, _builds in GUIDES.items():
    for _index, _guide in _builds.items():
        BUILDS[_class][_index] = _guide


def rows(folder, name):
    with open(os.path.join(folder, name + '.csv'), newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))


def load_tree(folder):
    """Nodes per class tree: {tree: [dict(id, spec, row, x, ranks, name, de, edges)]}."""
    names = {r['ID']: r['Name_lang'] for r in rows(folder, 'SpellName')}
    # German names (SpellName_deDE.csv, wago.tools with locale=deDE) for the builds of German guides.
    german = {}
    if os.path.exists(os.path.join(folder, 'SpellName_deDE.csv')):
        german = {r['ID']: r['Name_lang'] for r in rows(folder, 'SpellName_deDE')}
    definitions = {r['ID']: r for r in rows(folder, 'TraitDefinition')}
    entries = {r['ID']: r for r in rows(folder, 'TraitNodeEntry')}
    first_entry = {}
    for r in rows(folder, 'TraitNodeXTraitNodeEntry'):
        first_entry.setdefault(r['TraitNodeID'], entries[r['TraitNodeEntryID']])
    edges = defaultdict(list)  # right node -> [(left node, type)]: the sources at full rank it needs
    for r in rows(folder, 'TraitEdge'):
        if int(r['Type']) in (SUFFICIENT, REQUIRED):
            edges[r['RightTraitNodeID']].append((r['LeftTraitNodeID'], int(r['Type'])))
    trees = defaultdict(list)
    for n in rows(folder, 'TraitNode'):
        entry = first_entry.get(n['ID'])
        if entry:
            spell = definitions[entry['TraitDefinitionID']]['SpellID']
            trees[int(n['TraitTreeID'])].append({
                'id': n['ID'], 'x': int(n['PosX']), 'y': int(n['PosY']), 'max': int(entry['MaxRanks']),
                'name': names.get(spell, '?'), 'de': german.get(spell), 'edges': edges.get(n['ID'], []),
            })
    for nodes in trees.values():
        # Rows: positions that differ by a few units (2120 / 2130) are one row.
        row_of, row, previous = {}, -1, None
        for y in sorted({n['y'] for n in nodes}):
            if previous is None or y - previous > ROW_TOLERANCE:
                row += 1
            row_of[y] = row
            previous = y
        for n in nodes:
            n['row'] = row_of[n['y']]
            n['spec'] = 0 if n['x'] < 4000 else 1 if n['x'] < 8000 else 2
    return trees


def resolve_guide(nodes, guide, label):
    """A build of a guide: talents with their ranks (German or English names, any tree) become points per
    tree, priorities in the listed order and the rank of each talent as its cap; `fill` adds points to trees
    the guide does not name, with their own priorities."""
    allocation, priorities, caps = defaultdict(int), defaultdict(list), {}
    for name, rank in guide['talents']:
        found = [n for n in nodes if name in (n['name'], n['de'])]
        if len(found) != 1:
            ERRORS.append('%s: talent %r found %d times' % (label, name, len(found))); continue
        n = found[0]
        if rank > n['max']:
            ERRORS.append('%s: %r has only %d ranks' % (label, name, n['max'])); rank = n['max']
        allocation[n['spec']] += rank
        priorities[n['spec']].append(n['name'])
        caps[n['id']] = rank
    for spec, points in guide.get('fill', {}).items():
        allocation[spec] += points
        for name in guide.get('fill_priorities', {}).get(spec, []):
            found = [n for n in nodes if n['spec'] == spec and name in (n['name'], n['de'])]
            if len(found) != 1:
                ERRORS.append('%s: fill talent %r found %d times' % (label, name, len(found))); continue
            if found[0]['name'] not in priorities[spec]:
                priorities[spec].append(found[0]['name'])
    return dict(allocation), dict(priorities), caps


def make_build(nodes, allocation, priorities, label, caps=None):
    caps = caps or {}
    by_id = {n['id']: n for n in nodes}
    by_name = {}
    for n in nodes:
        by_name.setdefault((n['spec'], n['name']), n)
    for spec, names in priorities.items():
        for name in names:
            if (spec, name) not in by_name:
                ERRORS.append('%s: unknown talent %r in specialisation %d' % (label, name, spec))
    priorities = {spec: [name for name in names if (spec, name) in by_name] for spec, names in priorities.items()}
    rank = {n['id']: 0 for n in nodes}
    spent = defaultdict(int)

    def above(spec, row):
        return sum(rank[n['id']] for n in nodes if n['spec'] == spec and n['row'] < row)

    def addable(n):
        if rank[n['id']] >= caps.get(n['id'], n['max']) or spent[n['spec']] >= allocation.get(n['spec'], 0):
            return False
        if above(n['spec'], n['row']) < n['row'] * POINTS_PER_ROW:
            return False
        required = [s for s, kind in n['edges'] if kind == REQUIRED and s in by_id]
        sufficient = [s for s, kind in n['edges'] if kind == SUFFICIENT and s in by_id]
        if any(rank[s] < by_id[s]['max'] for s in required):
            return False
        return not sufficient or any(rank[s] >= by_id[s]['max'] for s in sufficient)

    # The deepest listed talent within reach (row 6 needs 30 points in the rows above) and
    # everything it needs by arrows come first as soon as the rows allow them.
    boosted = set()
    for spec, names in priorities.items():
        if allocation.get(spec, 0) >= 31:
            reach = [by_name[(spec, name)] for name in names if by_name[(spec, name)]['row'] <= 6]
            if reach:
                top = max(reach, key=lambda n: n['row'])
                stack = [top['id']]
                while stack:
                    current = stack.pop()
                    if current not in boosted:
                        boosted.add(current)
                        # the source above it (a reverse edge points down the tree)
                        stack.extend(s for s, _ in by_id[current]['edges']
                                     if s in by_id and by_id[s]['row'] < by_id[current]['row'])

    def score(n):
        names = priorities.get(n['spec'], [])
        if n['id'] in boosted:
            return 20000
        if n['name'] in names:
            return 10000 - names.index(n['name']) * 20
        return 100 - n['row'] * 10 - n['x'] / 10000.0

    total = sum(allocation.values())
    for _ in range(total):
        candidates = [n for n in nodes if addable(n)]
        if not candidates:
            break
        best = max(candidates, key=score)
        rank[best['id']] += 1
        spent[best['spec']] += 1
    missing = []
    for spec, names in priorities.items():
        for name in names:
            n = by_name[(spec, name)]
            if rank[n['id']] < caps.get(n['id'], n['max']):
                missing.append('%s %d/%d' % (name, rank[n['id']], n['max']))
    return {i: r for i, r in rank.items() if r > 0}, spent, missing


def main(folder, build):
    trees = load_tree(folder)
    out = ['-- Generated by tools/build_presets.py from the game tables TraitNode, TraitNodeEntry, TraitNodeXTraitNodeEntry,',
           '-- TraitDefinition, TraitEdge and SpellName, build %s; the talent priorities are suggestions of the authors.' % build,
           '-- Class file -> { { de = name, en = name, points = "31/20/0", ranks = "nodeID:rank,…" }, … }.',
           'local _, ns = ...', 'ns.TalentPresets = {']
    for class_file, tree in CLASS_TREE.items():
        nodes = trees[tree]
        out.append('\t%s = {' % class_file)
        for build in BUILDS[class_file]:
            if isinstance(build, dict):
                de, en = build.get('de'), build.get('en')
                label = '%s %s' % (class_file, de or build['talents'][0][0])
                allocation, priorities, caps = resolve_guide(nodes, build, label)
                if sum(allocation.values()) != 51:
                    ERRORS.append('%s: %d points instead of 51' % (label, sum(allocation.values())))
            else:
                de, en, allocation, priorities = build
                label = '%s %s' % (class_file, de or allocation)
                caps = None
            ranks, spent, missing = make_build(nodes, allocation, priorities, label, caps)
            specs = SPECS[class_file]
            main_spec = max(allocation, key=lambda s: allocation[s])
            summary = '/'.join(str(spent[s]) for s in range(3))
            de = de or specs[main_spec][0]
            en = en or specs[main_spec][1]
            if missing:
                print('%s %s: not reached: %s' % (class_file, summary, ', '.join(missing)))
            text = ','.join('%s:%d' % (i, r) for i, r in sorted(ranks.items(), key=lambda p: int(p[0])))
            out.append('\t\t{ de = "%s", en = "%s", points = "%s", ranks = "%s" },' % (de, en, summary, text))
        out.append('\t},')
    out.append('}')
    if ERRORS:
        raise SystemExit('\n'.join(ERRORS) + '\nnothing written')
    path = os.path.join(ROOT, 'Data', 'TalentPresets.lua')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('written', path)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])

# Builds Data/TalentPresets.lua from the client talent tables (CSV from wago.tools/db2).
# Usage: python3 -I tools/build_presets.py <folder with the CSV files> BUILD
import csv
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POINTS_PER_ROW = 5
SUFFICIENT, REQUIRED = 2, 3  # edge types: one source at full rank is enough / every source is needed
ROW_TOLERANCE = 50

# class file -> trait tree of the class (the tree 1083 is an older Druid copy)
CLASS_TREE = {
    'SHAMAN': 1082, 'DRUID': 1089, 'HUNTER': 1091, 'PALADIN': 1100, 'ROGUE': 1111,
    'MAGE': 1112, 'PRIEST': 1114, 'WARLOCK': 1116, 'WARRIOR': 1117,
}
# Retired Hunter and Priest nodes still present outside the displayed trees.
HIDDEN_NODES = {"104982", "105003", "105865"}


# Talent names are those of the English client. Ranks are fixed at level 60.
# See DATA-SOURCES.md for the comparison and the intended roles.
BUILDS = {
    'WARRIOR': [
        ('Waffen', 'Arms', [
            ('Improved Heroic Strike', 3), ('Improved Rend', 3), ('Improved Tactical Mastery', 3),
            ('Improved Overpower', 2), ('Anger Management', 1), ('Deep Wounds', 3), ('Spearing Strike', 1),
            ('Two-Handed Weapon Specialization', 3), ('Impale', 2), ('Bloodthrill', 2), ('Sweeping Strikes', 1),
            ('Weaponmaster', 5), ('Improved Slam', 2), ('Mortal Strike', 1),
            ('Booming Voice', 5), ('Cruelty', 5), ('Unbridled Wrath', 5), ('Improved Execute', 2),
            ('Improved Bloodrage', 2),
        ]),
        ('Furor', 'Fury', [
            ('Improved Heroic Strike', 3), ('Improved Rend', 3), ('Improved Tactical Mastery', 3),
            ('Improved Overpower', 2), ('Anger Management', 1), ('Deep Wounds', 3), ('Impale', 2),
            ('Booming Voice', 3), ('Cruelty', 5), ('Unbridled Wrath', 5), ('Furious Precision', 3),
            ('Dual Wield Specialization', 5), ('Reckless Swings', 1), ('Improved Execute', 2),
            ('Improved Berserker Rage', 2), ('Death Wish', 1), ('Improved Whirlwind', 2), ('Flurry', 3),
            ('Bloodthirst', 1),
            ('Improved Bloodrage', 1),
        ]),
        ('Schutz', 'Protection', [
            ('Deflection', 5),
            ('Cruelty', 5), ('Unbridled Wrath', 5), ('Enrage', 5),
            ('Improved Bloodrage', 1), ('Shield Specialization', 5), ('Anticipation', 5),
            ('Improved Revenge', 3), ('Improved Thunder Clap', 1), ('Last Stand', 1), ('Master of Defense', 2),
            ('Defiance', 3), ('Concussion Blow', 1), ('Focused Rage', 3), ('Bastion', 5), ('Shield Slam', 1),
        ]),
        ('Furor-Schutz (Tank mit Furor)', 'Fury-Prot (fury tank)', [
            ('Booming Voice', 5), ('Cruelty', 5), ('Lingering Rage', 1), ('Unbridled Wrath', 5), ('Enrage', 5),
            ('Dual Wield Specialization', 5), ('Death Wish', 1), ('Flurry', 3), ('Bloodthirst', 1),
            ('Improved Bloodrage', 2), ('Shield Specialization', 5), ('Iron Will', 2), ('Anticipation', 5),
            ('Improved Revenge', 3), ('Defiance', 3),
        ]),
    ],
    'PALADIN': [
        ('Heilig', 'Holy', [
            ('Spiritual Focus', 5), ('Healing Light', 3), ('Reverence', 2), ('Purifying Power', 2),
            ('Divine Favor', 1), ('Illumination', 5), ('Divine Precision', 2), ('Infusion of Light', 2),
            ('Oath of Light', 1), ('Holy Shock', 1), ('Boundless Light', 2), ('Holy Power', 5),
            ("Light's Vigil", 1),
            ('Divine Intellect', 5), ('Redoubt', 5), ('Precision', 3), ("Guardian's Favor", 1), ('Toughness', 5),
        ]),
        ('Schutz', 'Protection', [
            ('Redoubt', 5), ('Precision', 3), ('Sacred Duty', 2), ("Templar's Bulwark", 1),
            ('Shield Specialization', 2), ('Toughness', 3), ('Swift Judgement', 1),
            ('Improved Righteous Fury', 3), ('Anticipation', 5), ('Holy Shield', 1), ('Reckoning', 5),
            ('Iron Creed', 3), ('Shieldsworn', 1),
            ('Deflection', 5), ('Benediction', 5), ('Improved Judgement', 2), ('Conviction', 3),
            ('Sanctified Judgement', 1),
        ]),
        ('Vergeltung', 'Retribution', [
            ('Divine Strength', 5), ('Improved Seals', 5), ('Holy Conduit', 2),
            ('Divine Intellect', 5), ('Precision', 3),
            ('Benediction', 5), ('Improved Judgement', 2), ('Conviction', 3), ('Sanctified Judgement', 3),
            ('Vindication', 1), ('Seal of Command', 1), ('Pursuit of Justice', 2), ('Sacred Arbiter', 1),
            ('Two-Handed Weapon Specialization', 3), ('Repentance', 1), ('Vengeance', 3),
            ('Champion of the Light', 5), ('Unsealed Wrath', 1),
        ]),
        ('Schockadin (Heilig/Vergeltung)', 'Shockadin (Holy/Retribution)', [
            ('Divine Strength', 5), ('Reverence', 2), ('Improved Seals', 5), ('Purifying Power', 2),
            ('Divine Favor', 1), ('Holy Conduit', 2), ('Divine Precision', 2), ('Infusion of Light', 1),
            ('Consecrated Ground', 2), ('Holy Shock', 1),
            ('Benediction', 5), ('Improved Judgement', 2), ('Conviction', 3), ('Sanctified Judgement', 3),
            ('Vindication', 3), ('Seal of Command', 1), ('Pursuit of Justice', 1), ('Sacred Arbiter', 1),
            ('Two-Handed Weapon Specialization', 3), ('Vengeance', 3), ('Champion of the Light', 3),
        ]),
    ],
    'HUNTER': [
        ('Tierherrschaft', 'Beast Mastery', [
            ('Deadly Aspects', 5), ('Endurance Training', 3), ('Focused Fire', 2), ('Bestial Swiftness', 1),
            ('Unleashed Fury', 5), ('Ferocity', 5), ('Summon Hawk', 1), ('Intimidation', 1),
            ('Bestial Discipline', 2), ('Frenzy', 5), ('Bestial Wrath', 1),
            ('Lethal Attacks', 5), ('Improved Stings', 2), ('Careful Aim', 5), ('Improved Arcane Shot', 3),
            ('Trueshot Aura', 1),
            ('Improved Tracking', 4),
        ]),
        ('Treffsicherheit', 'Marksmanship', [
            ('Deadly Aspects', 5),
            ('Lethal Attacks', 5), ('Improved Stings', 3), ('Efficiency', 4), ('Careful Aim', 5),
            ('Rapid Killing', 2), ('Improved Arcane Shot', 5), ('Lone Wolf', 1), ('Trueshot Aura', 1),
            ('Mortal Shots', 5), ('Rapid Recuperation', 2), ('Barrage', 2), ('Ranged Weapon Specialization', 5),
            ('Sniper Shot', 1),
            ('Improved Tracking', 5),
        ]),
        ('Überleben', 'Survival', [
            ('Lethal Attacks', 5), ('Improved Stings', 3), ('Careful Aim', 5), ('Improved Arcane Shot', 1),
            ('Lone Wolf', 1), ('Trueshot Aura', 1), ('Mortal Shots', 4),
            ('Improved Tracking', 5), ('Deflection', 3), ('Savage Strikes', 2), ('Clever Traps', 2),
            ('Surefooted', 3), ("Predator's Edge", 5), ('Resourcefulness', 2), ('Expose Prey', 2),
            ('Strider Kick', 1), ('Lightning Reflexes', 5), ('Lacerating Strikes', 1),
        ]),
        ('Tierherrschaft/Überleben', 'Beast Mastery/Survival', [
            ('Deadly Aspects', 5), ('Endurance Training', 3), ('Focused Fire', 2), ('Bestial Swiftness', 1),
            ('Unleashed Fury', 5), ('Ferocity', 5), ('Spirit Bond', 1), ('Intimidation', 1),
            ('Bestial Discipline', 2), ('Frenzy', 5), ('Bestial Wrath', 1),
            ('Improved Tracking', 5), ('Deflection', 5), ('Savage Strikes', 2), ('Survivalist', 5),
            ('Surefooted', 3),
        ]),
    ],
    'ROGUE': [
        ('Meucheln', 'Assassination', [
            ('Malice', 5), ('Ruthlessness', 3), ('Improved Slice and Dice', 3), ('Vigor', 1),
            ('Blood Splatter', 1), ('Lethality', 2), ('Vile Poisons', 3), ('Cold Blood', 1),
            ('Improved Poisons', 2), ('Relentless Strikes', 5), ('Venom', 1), ('Seal Fate', 3), ('Mutilate', 1),
            ('Coup de Grace', 3), ('Efficient Strikes', 2), ('Puncturing Wounds', 3), ('Precision', 3),
            ('Endurance', 2), ('Composure', 2), ('Flawless Execution', 1), ('Aggression', 3),
            ('Opportunity', 1),
        ]),
        ('Kampf', 'Combat', [
            ('Malice', 5), ('Ruthlessness', 3), ('Improved Slice and Dice', 3), ('Vigor', 2), ('Lethality', 2),
            ('Cold Blood', 1),
            ('Coup de Grace', 3), ('Efficient Strikes', 2), ('Deflection', 1), ('Precision', 3),
            ('Improved Sprint', 2), ('Endurance', 2), ('Composure', 2), ('Flawless Execution', 1),
            ('Weapon Expertise', 2), ('Aggression', 3), ('Dual Wield Specialization', 2), ('Blade Flurry', 1),
            ('Hack and Slash', 5), ('Flash of Steel', 5), ('Adrenaline Rush', 1),
        ]),
        ('Täuschung', 'Subtlety', [
            ('Malice', 5), ('Ruthlessness', 3), ('Improved Slice and Dice', 3), ('Blood Splatter', 1),
            ('Coup de Grace', 3), ('Efficient Strikes', 2), ('Precision', 3),
            ('Opportunity', 5), ('Dirty Deeds', 2), ('Camouflage', 3), ('Improved Ambush', 3), ('Initiative', 3),
            ('Premeditation', 1), ('Serrated Blades', 3), ('Elusiveness', 2), ('Ghostly Strike', 1),
            ('Preparation', 1), ('Hemorrhage', 1), ('Boot Knife', 5), ('Death Mark', 1),
        ]),
        ('Meucheln/Täuschung (Dolche)', 'Assassination/Subtlety (daggers)', [
            ('Improved Gouge', 2), ('Remorseless Attacks', 2), ('Malice', 5), ('Ruthlessness', 3),
            ('Blood Splatter', 1), ('Lethality', 2), ('Cold Blood', 1), ('Improved Poisons', 5),
            ('Relentless Strikes', 5), ('Venom', 1), ('Seal Fate', 3), ('Mutilate', 1),
            ('Setup', 3), ('Master of Deception', 3), ('Opportunity', 5), ('Dirty Deeds', 1), ('Camouflage', 3),
            ('Initiative', 3), ('Elusiveness', 2),
        ]),
    ],
    'PRIEST': [
        ('Disziplin', 'Discipline', [
            ('Power in Light', 5), ('Twin Disciplines', 1), ('Mental Strength', 5), ('Mental Agility', 2),
            ('Inner Focus', 1), ('Improved Power Word: Shield', 3), ('Meditation', 3), ('Soul Warding', 1),
            ('Penance', 1), ('Renewed Hope', 5), ('Divine Aegis', 3), ('Power Infusion', 1),
            ('Twilight Focus', 2), ('Improved Renew', 3), ('Holy Specialization', 5), ('Spell Warding', 5),
            ('Divine Fury', 5),
        ]),
        ('Heilig', 'Holy', [
            ('Power in Light', 3), ('Twin Disciplines', 5), ('Mental Strength', 5), ('Mental Agility', 3),
            ('Inner Focus', 1), ('Meditation', 3),
            ('Holy Specialization', 5), ('Divine Fury', 5), ('Blessed Recovery', 2), ('Inspiration', 3),
            ('Improved Healing', 3), ('Searing Light', 1), ('Holy Binding', 1), ('Litany of Light', 1),
            ('Spirit of Redemption', 1), ('Spiritual Guidance', 5), ('Spiritual Healing', 3),
            ('Prayer of Mending', 1),
        ]),
        ('Schatten', 'Shadow', [
            ('Twin Disciplines', 5), ('Silent Resolve', 3), ('Mental Strength', 3), ('Inner Focus', 1),
            ('Meditation', 3),
            ('Twilight Focus', 3),
            ('Shadow Focus', 5), ('Improved Mind Blast', 4), ('Improved Shadow Word: Pain', 2),
            ('Shadow Reach', 2), ('Mind Flay', 1), ('Improved Mind Flay', 2), ('Dark Inspiration', 5),
            ('Vampiric Embrace', 1), ('Shadow Weaving', 3), ('Devouring Contagion', 2), ('Darkness', 5),
            ('Shadowform', 1),
        ]),
        ('Schatten/Heilig', 'Shadow/Holy', [
            ('Twilight Focus', 3), ('Improved Renew', 2), ('Holy Specialization', 5), ('Divine Fury', 5),
            ('Improved Healing', 1), ('Searing Light', 2),
            ('Shadow Focus', 5), ('Improved Mind Blast', 4), ('Improved Shadow Word: Pain', 2),
            ('Shadow Reach', 2), ('Mind Flay', 1), ('Improved Mind Flay', 2), ('Dark Inspiration', 5),
            ('Vampiric Embrace', 1), ('Shadow Weaving', 3), ('Devouring Contagion', 2), ('Darkness', 5),
            ('Shadowform', 1),
        ]),
    ],
    'SHAMAN': [
        ('Elementar', 'Elemental', [
            ('Convection', 5), ('Concussion', 5), ('Elemental Alacrity', 3), ('Call of Flame', 3),
            ('Elemental Focus', 1), ('Trial by Fire', 2), ('Eye of the Storm', 3), ('Call of Thunder', 1),
            ('Lightning Overload', 3), ('Elemental Fury', 5), ('Lightning Mastery', 1),
            ('Thundering Strikes', 5), ('Ancestral Knowledge', 5), ('Shamanistic Focus', 1),
            ('Tidal Focus', 5), ('Mindfulness', 3),
        ]),
        ('Verstärkung', 'Enhancement', [
            ('Concussion', 5), ('Elemental Devastation', 3), ('Reverberation', 3), ('Call of Flame', 3),
            ('Elemental Focus', 1), ('Trial by Fire', 2),
            ('Thundering Strikes', 5), ('Ancestral Knowledge', 3), ('Mental Dexterity', 3),
            ('Elemental Weapons', 3), ('Shamanistic Focus', 1), ('Flurry', 5), ('Stormstrike', 1),
            ('Mental Quickness', 2), ('Improved Stormstrike', 2), ('Maelstrom Weapon', 5),
            ('Rage of the Farseer', 1),
            ('Tidal Focus', 3),
        ]),
        ('Wiederherstellung', 'Restoration', [
            ('Ancestral Knowledge', 5),
            ('Improved Healing Wave', 5), ('Tidal Focus', 5), ('Mindfulness', 3), ('Natural Grace', 3),
            ('Totemic Focus', 5), ('Ancestral Healing', 3), ('Water Shield', 1), ('Tidal Mastery', 5),
            ('Restorative Totems', 5), ('Mana Tide Totem', 1), ('Healing Way', 3), ("Nature's Swiftness", 1),
            ('Purification', 5), ('Riptide', 1),
        ]),
        ('Verstärkung/Wiederherstellung', 'Enhancement/Restoration', [
            ('Thundering Strikes', 5), ('Ancestral Knowledge', 3), ('Mental Dexterity', 3),
            ('Elemental Weapons', 3), ('Shamanistic Focus', 1), ('Flurry', 5), ('Stormstrike', 1),
            ('Mental Quickness', 2), ('Improved Stormstrike', 2), ('Maelstrom Weapon', 5),
            ('Rage of the Farseer', 1),
            ('Improved Healing Wave', 3), ('Tidal Focus', 5), ('Mindfulness', 3), ('Natural Grace', 3),
            ('Water Shield', 1), ('Tidal Mastery', 4), ('Mana Tide Totem', 1),
        ]),
    ],
    'MAGE': [
        ('Arkan', 'Arcane', [
            ('Improved Channeling', 5), ('Arcane Subtlety', 2), ('Arcane Concentration', 5),
            ('Missile Barrage', 2), ('Arcane Geometry', 2), ('Arcane Impact', 3), ('Arcane Blast', 1),
            ('Improved Counterspell', 1), ('Arcane Meditation', 3), ('Arcane Wrath', 1), ('Presence of Mind', 1),
            ('Arcane Mind', 5), ('Arcane Instability', 3), ('Arcane Power', 1),
            ('Incineration', 5), ('Accelerant', 5), ('Improved Flamestrike', 3),
            ('Precision', 3),
        ]),
        ('Feuer', 'Fire', [
            ('Improved Channeling', 5), ('Arcane Subtlety', 2), ('Arcane Concentration', 5),
            ('Missile Barrage', 2), ('Arcane Blast', 1), ('Arcane Meditation', 1),
            ('Incineration', 5), ('Accelerant', 5), ('Ignite', 5), ('Pyroblast', 1), ('Improved Fire Blast', 2),
            ('Improved Scorch', 3), ('Heating Up', 1), ('Master of Elements', 3), ('Critical Mass', 3),
            ('Fire Power', 3), ('Combustion', 1),
            ('Precision', 3),
        ]),
        ('Frost', 'Frost', [
            ('Wand Specialization', 2), ('Arcane Resilience', 3), ('Arcane Subtlety', 2),
            ('Arcane Concentration', 5),
            ('Incineration', 5),
            ('Improved Frostbolt', 5), ('Precision', 3), ('Ice Shards', 5), ('Frost Channeling', 1),
            ('Improved Blizzard', 1), ('Ice Lance', 1), ('Arctic Reach', 2), ('Ice Block', 1), ('Shatter', 3),
            ('Improved Cone of Cold', 3), ('Cold Snap', 1), ('Fingers of Frost', 2), ("Winter's Chill", 5),
            ('Ice Barrier', 1),
        ]),
        ('Frostfeuer (Feuer/Frost)', 'Frostfire (Fire/Frost)', [
            ('Incineration', 5), ('Accelerant', 5), ('Ignite', 5), ('Pyroblast', 1), ('Improved Fire Blast', 2),
            ('Improved Scorch', 3), ('Heating Up', 1), ('Master of Elements', 1), ('Critical Mass', 3),
            ('Fire Power', 3),
            ('Frost Warding', 2), ('Precision', 3), ('Ice Shards', 5), ('Improved Frost Nova', 1),
            ('Frost Channeling', 3), ('Improved Blizzard', 1), ('Ice Lance', 1), ('Ice Block', 1),
            ('Shatter', 3), ('Fingers of Frost', 2),
        ]),
    ],
    'WARLOCK': [
        ('Gebrechen', 'Affliction', [
            ('Improved Life Tap', 2), ('Suppression', 5), ('Improved Corruption', 5),
            ('Improved Bane of Agony', 2), ('Amplify Curse', 1), ('Pandemic', 3), ('Malevolence', 5),
            ('Nightfall', 2), ('Siphon Life', 1), ('Soul Siphon', 3), ('Shadow Mastery', 5), ('Wrack', 1),
            ('Demonic Embrace', 5), ('Demonic Aegis', 2), ('Fel Vitality', 3), ('Demonic Sacrifice', 1),
            ('Improved Shadow Bolt', 5),
        ]),
        ('Dämonologie', 'Demonology', [
            ('Suppression', 1), ('Improved Corruption', 1),
            ('Unholy Power', 5), ('Fel Vitality', 3), ('Demonic Energies', 2), ('Improved Sayaad', 3),
            ('Demonic Sacrifice', 1), ('Master Summoner', 2), ('Decimation', 2), ('Demonic Brand', 3),
            ('Soul Link', 1), ('Demonic Knowledge', 3), ('Master Demonologist', 5), ('Demonic Pact', 1),
            ('Improved Shadow Bolt', 5), ('Bane', 5), ('Ruin', 5), ('Agonizing Flames', 3),
        ]),
        ('Zerstörung', 'Destruction', [
            ('Improved Life Tap', 2), ('Suppression', 5), ('Improved Corruption', 5),
            ('Improved Bane of Agony', 2), ('Amplify Curse', 1), ('Pandemic', 3),
            ('Bane', 5), ('Cataclysm', 3), ('Aftermath', 5), ('Ruin', 5), ('Shadowburn', 1),
            ('Agonizing Flames', 3), ('Conflagrate', 1), ('Bane of Havoc', 1), ('Fire and Brimstone', 3),
            ('Shadow and Flame', 5), ('Incinerate', 1),
        ]),
        ('Opferung (Dämonologie/Zerstörung)', 'Sacrifice (Demonology/Destruction)', [
            ('Demonic Embrace', 5), ('Unholy Power', 5), ('Demonic Aegis', 2), ('Fel Vitality', 3),
            ('Demonic Energies', 2), ('Demonic Sacrifice', 1), ('Master Summoner', 2),
            ('Improved Shadow Bolt', 5), ('Bane', 5), ('Cataclysm', 3), ('Aftermath', 5), ('Ruin', 5),
            ('Agonizing Flames', 3), ('Conflagrate', 1), ('Shadow and Flame', 4),
        ]),
    ],
    'DRUID': [
        ('Gleichgewicht', 'Balance', [
            ('Improved Wrath', 5), ('Genesis', 2), ('Moonglow', 3), ('Improved Moonfire', 2),
            ("Nature's Majesty", 2), ("Nature's Reach", 2), ("Nature's Splendor", 1), ('Insect Swarm', 1),
            ('Vengeance', 5), ('Improved Starfire', 5), ("Nature's Grace", 1), ('Eclipse', 3), ('Moonfury', 5),
            ('Moonkin Form', 1),
            ("Nature's Focus", 5), ('Naturalist', 5), ('Reflection', 3),
        ]),
        ('Wilder Kampf', 'Feral', [
            ('Genesis', 5), ("Nature's Majesty", 2), ("Nature's Reach", 2),
            ('Ferocity', 5), ('Furor', 3), ('Feral Swiftness', 2), ('Shredding Attacks', 3), ('Savage Fury', 2),
            ('Feral Charge', 1), ('Sharpened Claws', 2), ('Predatory Strikes', 3), ('Predatory Discipline', 1),
            ('Blood Frenzy', 2), ('Leader of the Pack', 1), ('Natural Instinct', 2), ('Rend and Tear', 4),
            ('Shifting Power', 1),
            ('Heart of the Wild', 5), ('Naturalist', 5),
        ]),
        ('Wiederherstellung', 'Restoration', [
            ('Genesis', 5),
            ("Nature's Focus", 5), ('Heart of the Wild', 5), ('Naturalist', 5), ('Reflection', 3),
            ('Subtlety', 1), ('Gift of Nature', 5), ('Bloom', 1), ('Tranquil Spirit', 5),
            ('Improved Rejuvenation', 3), ('Swiftmend', 1), ("Nature's Swiftness", 1), ('Living Spirit', 3),
            ('Improved Tranquility', 2), ('Improved Regrowth', 5), ('Wild Growth', 1),
        ]),
        ('Bär (Tank)', 'Bear (tank)', [
            ('Genesis', 5), ("Nature's Majesty", 2), ("Nature's Reach", 2),
            ('Ferocity', 2), ('Furor', 3), ('Feral Swiftness', 2), ('Feral Instinct', 2), ('Thick Hide', 3),
            ('Savage Fury', 2), ('Feral Charge', 1), ('Sharpened Claws', 2), ('Predatory Strikes', 3),
            ('Lacerate', 1), ('Blood Frenzy', 2), ('Leader of the Pack', 1), ('Natural Instinct', 2),
            ('Natural Reaction', 5), ('Primal Bite', 1),
            ('Heart of the Wild', 5), ('Naturalist', 5),
        ]),
    ],
}


def rows(folder, name):
    with open(os.path.join(folder, name + '.csv'), newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))


def load_tree(folder):
    """Nodes per class tree: {tree: [dict(id, spec, row, x, max, name, edges)]}."""
    names = {r['ID']: r['Name_lang'] for r in rows(folder, 'SpellName')}
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
        if entry and n['ID'] not in HIDDEN_NODES and int(n['TraitTreeID']) in CLASS_TREE.values():
            spell = definitions[entry['TraitDefinitionID']]['SpellID']
            trees[int(n['TraitTreeID'])].append({
                'id': n['ID'], 'x': int(n['PosX']), 'y': int(n['PosY']), 'max': int(entry['MaxRanks']),
                'name': names.get(spell, '?'), 'edges': edges.get(n['ID'], []),
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


def make_build(nodes, talents, label):
    by_id = {n['id']: n for n in nodes}
    by_name = defaultdict(list)
    for n in nodes:
        by_name[n['name']].append(n)

    targets, points = {}, [0, 0, 0]
    for name, rank in talents:
        matches = by_name[name]
        if len(matches) != 1:
            raise ValueError(f'{label}: talent {name!r} found {len(matches)} times')
        node = matches[0]
        if node['id'] in targets or not 0 < rank <= node['max']:
            raise ValueError(f'{label}: invalid rank {rank} for {name!r}')
        targets[node['id']] = rank
        points[node['spec']] += rank
    if sum(points) != 51:
        raise ValueError(f'{label}: {sum(points)} points instead of 51')

    # Replay the allocation to check row gates, arrows and dependency order.
    learned = {}
    pending = dict(targets)
    while pending:
        for node_id, rank in pending.items():
            node = by_id[node_id]
            above = sum(r for i, r in learned.items()
                        if by_id[i]['spec'] == node['spec'] and by_id[i]['row'] < node['row'])
            if above < node['row'] * POINTS_PER_ROW:
                continue
            required = [s for s, kind in node['edges'] if kind == REQUIRED and s in by_id]
            sufficient = [s for s, kind in node['edges'] if kind == SUFFICIENT and s in by_id]
            if any(learned.get(s, 0) < by_id[s]['max'] for s in required):
                continue
            if sufficient and not any(learned.get(s, 0) >= by_id[s]['max'] for s in sufficient):
                continue
            learned[node_id] = rank
            del pending[node_id]
            break
        else:
            missing = ', '.join(by_id[i]['name'] for i in pending)
            raise ValueError(f'{label}: cannot learn {missing}')
    return targets, points


def main(folder, build):
    trees = load_tree(folder)
    out = ['-- Generated by tools/build_presets.py from the game tables TraitNode, TraitNodeEntry, TraitNodeXTraitNodeEntry,',
           f'-- TraitDefinition, TraitEdge and SpellName, build {build}. See DATA-SOURCES.md for the talent recommendations.',
           '-- Class file -> { { de = name, en = name, points = "31/20/0", ranks = "nodeID:rank,…" }, … }.',
           'local _, ns = ...', 'ns.TalentPresets = {']
    for class_file, tree in CLASS_TREE.items():
        out.append(f'\t{class_file} = {{')
        for de, en, talents in BUILDS[class_file]:
            ranks, points = make_build(trees[tree], talents, f'{class_file} {en}')
            summary = '/'.join(map(str, points))
            encoded = ','.join(f'{node_id}:{ranks[node_id]}' for node_id in sorted(ranks, key=int))
            out.append(f'\t\t{{ de = "{de}", en = "{en}", points = "{summary}", ranks = "{encoded}" }},')
        out.append('\t},')
    out.append('}')
    path = os.path.join(ROOT, 'Data', 'TalentPresets.lua')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('written', path)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: python3 -I tools/build_presets.py CSV_FOLDER BUILD')
    main(sys.argv[1], sys.argv[2])

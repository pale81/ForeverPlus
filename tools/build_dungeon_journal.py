"""Build the dungeon journal from pinned client tables, WDTs and ATT quest IDs.

Usage: python3 tools/build_dungeon_journal.py CLIENT_DIR ATT_QUESTS LISTFILE BUILD
CLIENT_DIR contains Map, Map-deDE, LoadingScreens, GroupFinderActivity, QuestV2,
DungeonEncounter and DungeonEncounter-deDE as CSV and wdt/<WdtFileDataID>.
Also supply tiles/<FileDataID> (BLP) for the exported minimap regions. Pillow
reads the minimap images to remove blank tiles and crop the empty margins.
ATT_QUESTS is the output of tools/dungeon_quests.lua; LISTFILE is the wowdev
community listfile (file IDs and paths). Only texture references are written.
"""
import csv
import json
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]

# Classic client floor plans; these predate Forever's redesigns. Use the
# Forever minimap texture layout ahead of a legacy plan for new instances.
LEGACY = {
    33: ("shadowfangkeep", 7), 34: ("thestockade", 1), 36: ("thedeadmines", 2),
    43: ("wailingcaverns", 1), 47: ("razorfenkraul", 1), 48: ("blackfathomdeeps", 3),
    70: ("uldaman", 2), 90: ("gnomeregan", 4), 109: ("thetempleofatalhakkar", 1),
    129: ("razorfendowns", 1), 189: ("scarletmonasteryold/scarletmonastery", 4),
    229: ("blackrockspire", 7), 230: ("blackrockdepths", 2), 249: ("onyxiaslair", 1),
    289: ("scholomanceold", 4), 329: ("stratholme", 2), 349: ("maraudon", 2),
    389: ("ragefire", 1), 409: ("moltencore", 1), 429: ("diremaul", 6),
    469: ("blackwinglair", 4), 531: ("ahnqiraj", 3), 533: ("naxxramas", 6),
}

# Quest ID, faction, minimum level and English fallback. See DATA-SOURCES.md.
EXTRA_QUESTS = {
    2875: [(86971, "-", 0, "Curious Karazhan Curios!")],
    3001: [
        (95790, "A", 55, "Digestible Research"),
        (95924, "A", 55, "Panic at the Digsite"),
        (95925, "A", 55, "Mapping the Way Forward"),
        (95926, "H", 55, "The Dark Crystal"),
        (95928, "H", 55, "Crystalline Elements"),
        (97049, "H", 55, "Essence of Seeping Slimes"),
    ],
}


def rows(path):
    with open(path, newline="", encoding="utf-8-sig") as file:
        return list(csv.DictReader(file))


def quote(text):
    return json.dumps(text, ensure_ascii=False)


def lua_list(items):
    return "{ " + ", ".join(map(str, items)) + " }"


def legacy_files(path):
    prefixes = {f"interface/worldmap/{name if '/' in name else name + '/' + name}"
                for name, _ in LEGACY.values()}
    files = {}
    with open(path, encoding="utf-8", errors="replace") as file:
        for line in file:
            file_id, sep, asset = line.strip().partition(";")
            if not sep or not asset.startswith("interface/worldmap/"):
                continue
            match = re.fullmatch(r"(.+?)([1-9])_(\d+)\.blp", asset)
            if match and match[1] in prefixes:
                files[asset] = int(file_id)
    return files


def legacy_floors(map_id, files):
    if map_id not in LEGACY:
        return []
    path, count = LEGACY[map_id]
    stem = path if "/" in path else path + "/" + path
    floors = []
    for floor in range(1, count + 1):
        files_for_floor = [files.get(f"interface/worldmap/{stem}{floor}_{i}.blp") for i in range(1, 13)]
        if all(files_for_floor):
            floors.append(files_for_floor)
    return floors


def minimap(path):
    data = path.read_bytes()
    offset = 0
    while offset + 8 <= len(data):
        chunk, size = struct.unpack_from("<4sI", data, offset)
        offset += 8
        if chunk == b"DIAM":  # WDT MAID: 64x64 terrain tiles, minimap FileDataID in column 8.
            assert size == 64 * 64 * 32
            return {i: row[7] for i, row in enumerate(struct.iter_unpack("<8I", data[offset:offset + size])) if row[7]}
        offset += size
    return {}


def tile_bounds(path):
    with Image.open(path) as source:
        image = source.convert("RGB").resize((256, 256), Image.Resampling.BOX)
    edges = (image.crop((0, 0, 256, 1)), image.crop((0, 255, 256, 256)),
             image.crop((0, 0, 1, 256)), image.crop((255, 0, 256, 256)))
    # One flat grey/black background point per edge is enough for the crop.
    bg = tuple(int(channel) for channel in ImageStat.Stat(edges[0]).median)
    if max(bg) - min(bg) > 6 or not (bg[0] <= 8 or 100 <= bg[0] <= 132):
        return 0, 0, 256, 256
    if sum(max(abs(a - b) for a, b in zip(bg, ImageStat.Stat(edge).median)) <= 6 for edge in edges) < 2:
        return 0, 0, 256, 256
    difference = ImageChops.difference(image, Image.new("RGB", image.size, bg)).convert("L")
    return difference.point(lambda value: 255 if value > 20 else 0).getbbox()


def minimap_sections(tiles, folder):
    """Keep disconnected regions separate, to avoid tiny maps inside a huge empty area."""
    bounds = {index: tile_bounds(folder / str(file)) for index, file in tiles.items()}
    sections = []
    remaining = set(tiles)
    while remaining:
        index = min(remaining)
        pending, component = [index], {index}
        remaining.remove(index)
        while pending:
            point = pending.pop()
            x, y = point % 64, point // 64
            for near in (point - 64, point + 64, point - 1 if x else -1, point + 1 if x < 63 else -1):
                if near in remaining:
                    pending.append(near)
                    component.add(near)
                    remaining.remove(near)
        visible = {index: bounds[index] for index in component if bounds[index]}
        if not visible:
            continue
        left = min((i % 64) * 256 + b[0] for i, b in visible.items()) - 12
        top = min((i // 64) * 256 + b[1] for i, b in visible.items()) - 12
        right = max((i % 64) * 256 + b[2] for i, b in visible.items()) + 12
        bottom = max((i // 64) * 256 + b[3] for i, b in visible.items()) + 12
        refs = [lua_list((tiles[i], (i % 64) * 256 - left, (i // 64) * 256 - top)) for i in sorted(visible)]
        sections.append((len(visible), lua_list((right - left, bottom - top, lua_list(refs)))))
    return [group for _, group in sorted(sections, key=lambda group: -group[0])]


def build(client, att_quests, listfile, version):
    activities = defaultdict(list)
    for row in rows(client / "GroupFinderActivity.csv"):
        if row["GroupFinderCategoryID"] in {"2", "114"} and int(row["MapID"]) > 0:
            activities[int(row["MapID"])].append(row)

    quest_ids = {int(row["ID"]) for row in rows(client / "QuestV2.csv")}
    quests = defaultdict(dict)
    for line in att_quests.read_text().splitlines():
        map_id, quest_id, faction, level, classes = line.split()
        map_id, quest_id = int(map_id), int(quest_id)
        if map_id in activities and quest_id in quest_ids:
            data = (faction, int(level), tuple(map(int, classes.split(","))) if classes != "-" else ())
            quests[map_id].setdefault(quest_id, []).append(data)
    fallbacks = {}
    for map_id, entries in EXTRA_QUESTS.items():
        for quest_id, side, level, title in entries:
            if quest_id in quest_ids:
                quests[map_id].setdefault(quest_id, [(side, level, ())])
                fallbacks[quest_id] = title

    de_bosses = {int(row["ID"]): row["Name_lang"] for row in rows(client / "DungeonEncounter-deDE.csv")}
    de_maps = {int(row["ID"]): row["MapName_lang"] for row in rows(client / "Map-deDE.csv")}
    encounters = defaultdict(list)
    for row in rows(client / "DungeonEncounter.csv"):
        map_id = int(row["MapID"])
        if map_id in activities:
            encounters[map_id].append(row)
    art = legacy_files(listfile)
    loading = {r["ID"]: int(r["MainImageFileDataID"]) or int(r["WideScreen169FileDataID"])
               or int(r["WideScreenFileDataID"]) or int(r["NarrowScreenFileDataID"])
               for r in rows(client / "LoadingScreens.csv")}
    out = ["-- Generated by tools/build_dungeon_journal.py; see DATA-SOURCES.md.", "local _, ns = ...", "",
           "ns.DungeonJournalData = {", f"\tbuild = {quote(version)},", "\tinstances = {"]
    for row in sorted(rows(client / "Map.csv"), key=lambda r: int(r["ID"])):
        map_id = int(row["ID"])
        if map_id not in activities:
            continue
        runs = activities[map_id]
        dungeon = any(a["GroupFinderCategoryID"] == "2" for a in runs)
        main = [a for a in runs if a["GroupFinderCategoryID"] == ("2" if dungeon else "114")]
        low = min(int(a["MinLevel"]) for a in main)
        high = max(int(a["MaxLevelSuggestion"]) for a in main)
        kind = "dungeon" if dungeon else "raid"
        en, de = row["MapName_lang"], de_maps.get(map_id)
        names = f"{quote(en)}, {quote(de) if de and de != en else 'false'}"
        image = loading.get(row["LoadingScreenID"], 0)
        out.append(f'\t\t[{map_id}] = {{ name = {{ {names} }}, kind = "{kind}", min = {low}, max = {high}, art = {image},')
        floors = legacy_floors(map_id, art)
        if floors:
            out.append("\t\t\tfloors = " + lua_list(lua_list(floor) for floor in floors) + ",")
        else:
            panes = minimap_sections(minimap(client / "wdt" / row["WdtFileDataID"]), client / "tiles")
            if panes:
                out.append("\t\t\tminimap = " + lua_list(panes) + ",")
        out.append("\t\t\tbosses = {")
        # A 5-player journal uses current normal encounters (0 = shared, 1 = normal),
        # skipping the separate seasonal/raid versions of e.g. BFD, Gnomeregan and ST.
        picked = [b for b in encounters[map_id] if not dungeon or int(b["DifficultyID"]) in {0, 1}]
        if not picked:
            picked = encounters[map_id]
        for boss in sorted(picked, key=lambda b: (int(b["OrderIndex"]), int(b["ID"]))):
            boss_id = int(boss["ID"])
            if boss_id == 3018:  # Completion record for Molten Core itself.
                continue
            name = boss["Name_lang"]
            german = de_bosses.get(boss_id)
            out.append(f"\t\t\t\t{{ {boss_id}, {quote(name)}"
                       + (f", {quote(german)}" if german and german != name else "") + " },")
        out.append("\t\t\t},")
        qs = []
        for quest_id, variants in sorted(quests[map_id].items()):
            factions = {v[0] for v in variants}
            faction = next(iter(factions)) if len(factions) == 1 else "-"
            level = min((v[1] for v in variants if v[1] > 0), default=0)
            classes = sorted({c for v in variants for c in v[2]}) if all(v[2] for v in variants) else []
            extras = f", {quote(faction)}, {level}" if faction != "-" or level or classes else ""
            if classes:
                extras += ", " + lua_list(classes)
            if quest_id in fallbacks:
                extras = f", {quote(faction)}, {level}, " + (lua_list(classes) if classes else "false")
                extras += ", " + quote(fallbacks[quest_id])
            qs.append(f"{{ {quest_id}{extras} }}")
        if qs:
            batches = [", ".join(qs[i:i + 6]) + "," for i in range(0, len(qs), 6)]
            out.extend(["\t\t\tquests = {", *("\t\t\t\t" + batch for batch in batches), "\t\t\t},"])
        out.append("\t\t},")
    out.extend(["\t},", "}", ""])
    (ROOT / "Data" / "DungeonJournal.lua").write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    build(*map(Path, sys.argv[1:4]), sys.argv[4])

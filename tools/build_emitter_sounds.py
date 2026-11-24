#!/usr/bin/env python3
"""Build the Forever ambience finder from client DB2 CSVs and a community listfile."""

import argparse
from collections import defaultdict
import csv
from functools import cache
import json
from pathlib import Path
import re


def table(directory, name):
    with (directory / (name + ".csv")).open(encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def lua(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is None:
        return "false"
    if isinstance(value, (tuple, list)):
        return "{ " + ", ".join(map(lua, value)) + " }"
    return str(value)


def build(directory, listfile):
    entries = defaultdict(set)
    children = defaultdict(set)
    for row in table(directory, "SoundKitEntry"):
        if int(row["FileDataID"]) > 0 and float(row["Volume"]) > 0:
            entries[int(row["SoundKitID"])].add(int(row["FileDataID"]))
    for row in table(directory, "SoundKitChild"):
        children[int(row["ParentSoundKitID"])].add(int(row["SoundKitID"]))

    @cache
    def kit_files(kit):
        pending = [kit]
        seen = set()
        files = set()
        while pending:
            current = pending.pop()
            if current not in seen:
                seen.add(current)
                files.update(entries.get(current, ()))
                pending.extend(children.get(current, ()))
        return sorted(files)

    ranges = {int(row["ID"]): float(row["DistanceCutoff"]) for row in table(directory, "SoundKit")}
    ambience = defaultdict(set)
    flavors = defaultdict(set)
    for row in table(directory, "SoundAmbience"):
        for name, value in row.items():
            if name.startswith(("AmbienceID_", "SoundKitID_", "AmbienceStartID_", "AmbienceStopID_")):
                ambience[int(row["ID"])].update(kit_files(int(value)))
    for row in table(directory, "SoundAmbienceFlavor"):
        for name in ("SoundEntriesIDDay", "SoundEntriesIDNight"):
            flavors[int(row["SoundAmbienceID"])].update(kit_files(int(row[name])))

    rain_candidates = set()
    for row in table(directory, "Weather"):
        if int(row["Type"]) == 1:
            weather_ambience = int(row["SoundAmbienceID"])
            rain_candidates.update(kit_files(int(row["AmbienceID"])))
            rain_candidates.update(ambience[weather_ambience])
            rain_candidates.update(flavors[weather_ambience])
    for legacy_rain_kit in (8533, 8534, 8535):
        rain_candidates.update(kit_files(legacy_rain_kit))

    areas = {int(row["ID"]): row for row in table(directory, "AreaTable")}
    area_children = defaultdict(list)
    for area, row in areas.items():
        area_children[int(row["ParentAreaID"])].append(area)
    maps = {}
    for row in table(directory, "UiMapAssignment"):
        area = int(row["AreaID"])
        if area in areas and int(row["OrderIndex"]) == 0:
            maps[int(row["UiMapID"])] = (int(row["MapID"]), area)

    area_sounds = {}
    for _, root in maps.values():
        pending = [root]
        seen = set()
        sounds = {}
        while pending:
            area = pending.pop()
            if area in seen:
                continue
            seen.add(area)
            row = areas[area]
            sounds[area] = (int(row["AmbienceID"]), int(row["UwAmbience"]))
            pending.extend(area_children[area])
        area_sounds[root] = sounds

    def position(row):
        return tuple(round(float(row[f"Position_{axis}"]), 1) for axis in (0, 1))

    points = defaultdict(list)
    for row in table(directory, "SoundEmitterPillPoints"):
        order = int(row["Field_11_0_0_54210_002"])
        points[int(row["SoundEmittersID"])].append((order, position(row)))

    emitters = defaultdict(list)
    labels = {}
    placement_kits = {}
    for row in table(directory, "SoundEmitters"):
        name = row["Name"]
        # Seasonal world-tree portals are present in the table of this build.
        if " - SoD - " in name:
            continue
        kit = int(row["SoundEntriesID"])
        files = kit_files(kit)
        coords = [p for _, p in sorted(points[int(row["ID"])])] or [position(row)]
        if not files or coords == [(0, 0)]:
            continue
        label = re.sub(r"^1\.60\s+(?:Amb(?:ience)?\s*)?-\s*", "", name).strip()
        emitters[int(row["MapID"])].append((label, round(ranges.get(kit, 0)), kit, sum(coords, ())))
        placement_kits[kit] = files
        for file_id in files:
            labels.setdefault(file_id, label)

    used = set(labels)
    ambient_kits = {}
    for sounds in area_sounds.values():
        for sound_ids in sounds.values():
            for sound_id in sound_ids:
                if sound_id and sound_id not in ambient_kits:
                    primary = sorted(ambience[sound_id])
                    extra = sorted(flavors[sound_id] - ambience[sound_id])
                    if primary or extra:
                        used.update(primary)
                        used.update(extra)
                        ambient_kits[sound_id] = (primary, extra)
    paths = {}
    rain_sounds = {}
    named_files = used | rain_candidates
    with listfile.open(encoding="utf-8-sig") as source:
        for line in source:
            id_text, _, path = line.rstrip().partition(";")
            if id_text.isdecimal() and (file_id := int(id_text)) in named_files:
                paths[file_id] = path
                if file_id in rain_candidates:
                    rain = re.fullmatch(r"sound/ambience/weather/(?:fx_weather_)?rain_?(light|med(?:ium)?|heavy).*\.ogg",
                                        path.lower())
                    if rain:
                        intensity = rain[1]
                        rain_sounds[file_id] = "medium" if intensity == "med" else intensity
    used.update(rain_sounds)
    files = sorted(((id_, paths.get(id_), labels.get(id_)) for id_ in used),
                   key=lambda row: (row[2] or row[1] or "", row[0]))
    return files, maps, area_sounds, ambient_kits, placement_kits, emitters, rain_sounds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("listfile", type=Path)
    parser.add_argument("tables", type=Path, help="Directory containing the Forever DB2 CSV exports")
    parser.add_argument("build", help="Client build of the DB2 exports")
    args = parser.parse_args()

    files, maps, areas, ambient_kits, placement_kits, emitters, rain_sounds = build(args.tables, args.listfile)
    if not files or not maps or not emitters or not rain_sounds:
        parser.error("Missing Forever sound, weather or map records")
    output = Path(__file__).resolve().parents[1] / "Data" / "EmitterSounds.lua"
    with output.open("w", encoding="utf-8", newline="\n") as target:
        target.write(f"-- Generated by tools/build_emitter_sounds.py for Forever {args.build}.\n")
        target.write("local _, ns = ...\n")
        target.write("ns.EmitterSounds = {\n")
        for record in files:
            target.write(f"\t{lua(record)},\n")
        target.write("}\nns.EmitterRainSounds = {\n")
        for file_id, intensity in sorted(rain_sounds.items()):
            target.write(f"\t[{file_id}] = {lua(intensity)},\n")
        target.write("}\nns.EmitterMapAreas = {\n")
        for key, value in sorted(maps.items()):
            target.write(f"\t[{key}] = {lua(value)},\n")
        target.write("}\nns.EmitterAmbience = {\n")
        for root, sounds in sorted(areas.items()):
            target.write(f"\t[{root}] = {{\n")
            for area, files in sorted(sounds.items()):
                target.write(f"\t\t[{area}] = {lua(files)},\n")
            target.write("\t},\n")
        target.write("}\nns.EmitterAmbienceFiles = {\n")
        for sound_id, groups in sorted(ambient_kits.items()):
            target.write(f"\t[{sound_id}] = {lua(groups)},\n")
        target.write("}\nns.EmitterKitFiles = {\n")
        for kit, file_ids in sorted(placement_kits.items()):
            target.write(f"\t[{kit}] = {lua(file_ids)},\n")
        target.write("}\nns.EmitterLocations = {\n")
        for map_id, placements in sorted(emitters.items()):
            target.write(f"\t[{map_id}] = {{\n")
            for placement in placements:
                target.write(f"\t\t{lua(placement)},\n")
            target.write("\t},\n")
        target.write("}\n")


if __name__ == "__main__":
    main()

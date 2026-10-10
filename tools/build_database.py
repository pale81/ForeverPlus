#!/usr/bin/env python3
"""Build ForeverPlus's Lua data snapshot.

By default only the quest tables (Everything Quests, MIT) are written. The
AHledger item catalog (27k items, about 4 MB) is added with --items; the
addon itself does not need it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools" / "data_sources.json"
DEFAULT_OUTPUT = ROOT / "Data" / "Database.lua"
CLASSES = (
    "armor", "weapon", "consumable", "container", "quest", "key",
    "miscellaneous", "projectile", "trade-goods", "recipe", "reagent", "quiver",
)
EVERYTHING_QUESTS_COMMIT = "bb29c7326185377d05381a0a7c6817e4d3f1e883"
EVERYTHING_QUEST_FILES = ("QuestCoords_Forever.lua", "QuestTurnIn_Forever.lua", "QuestAvailable_Forever.lua")
ITEM_CLASSES = {
    "consumable": 0, "container": 1, "weapon": 2, "armor": 4,
    "reagent": 5, "projectile": 6, "trade-goods": 7, "recipe": 9,
    "quiver": 11, "quest": 12, "key": 13, "miscellaneous": 15,
}
RECIPE_SUBCLASSES = {
    "Leatherworking": 1, "Tailoring": 2, "Engineering": 3,
    "Blacksmithing": 4, "Cooking": 5, "Alchemy": 6,
    "First Aid": 7, "Enchanting": 8, "Fishing": 9,
}
ENTITY_FIELDS = {
    "Quest": ["name", "zoneOrSort", "requiredLevel", "requiredRaces", "requiredClasses",
              "preQuestSingle", "preQuestGroup", "nextQuestInChain", "breadcrumbForQuestId",
              "exclusiveTo", "objectives", "triggerEnd", "finishedBy", "questLevel",
              "previewPoint", "turnInPoint", "startPoints", "startGate", "startRequiresAny",
              "startRequiresAll", "startExcluded", "startBlockedBy", "startParent"],
    "Npc": ["name", "subName", "spawns", "friendlyToFaction", "npcFlags", "questStarts", "questEnds"],
    "Item": ["name", "class", "subClass", "vendors", "npcDrops", "objectDrops", "itemDrops",
             "questRewards", "startQuest", "quality", "itemLevel", "requiredLevel", "icon", "equipLoc"],
    "Object": ["name", "spawns", "questStarts", "questEnds"],
}


def fetch_catalog(category: str) -> bytes:
    url = "https://ahledger.com/api/catalog?" + urllib.parse.urlencode({"class": category})
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ForeverPlus data importer; attribution: https://ahledger.com"},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
            parsed = json.loads(payload)
            if not isinstance(parsed, dict) or not isinstance(parsed.get("rows"), list):
                raise RuntimeError(f"AHledger returned an unexpected response for {category}")
            return payload
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < 3:
                time.sleep(int(exc.headers.get("Retry-After", "2")))
                continue
            raise RuntimeError(f"AHledger request failed for {category}: HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            if attempt == 3:
                raise RuntimeError(f"AHledger request failed for {category}: {exc}") from exc
            time.sleep(attempt + 1)
    raise RuntimeError(f"AHledger request failed for {category}")


def fetch_everything_quests(filename: str) -> bytes:
    url = ("https://raw.githubusercontent.com/wheelbarrel00/EverythingQuests/"
           f"{EVERYTHING_QUESTS_COMMIT}/Data/{filename}")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ForeverPlus data importer; MIT data attribution in DATA-SOURCES.md"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except (urllib.error.HTTPError, urllib.error.URLError) as exc:
        raise RuntimeError(f"Everything Quests request failed for {filename}: {exc}") from exc


def decode_packed_point(map_id: int, packed: int) -> list:
    # Everything Quests' packed objective coordinate: map is the table key;
    # x and y occupy four decimal places in the low eight digits.
    rest = packed % 100_000_000
    x = (rest // 10_000) / 10_000
    y = (rest % 10_000) / 10_000
    if map_id <= 0 or not (0 <= x <= 100 and 0 <= y <= 100):
        raise RuntimeError(f"invalid Everything Quests coordinate: map={map_id}, value={packed}")
    return [map_id, x, y]


def parse_quest_coordinates(filename: str, field: str, payload: bytes) -> dict[int, list]:
    text = payload.decode("utf-8-sig")
    marker = "ns.CLASSIC_QUEST_COORDS = {" if field == "previewPoint" else "ns.CLASSIC_QUEST_TURNIN = {"
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"{filename} has no expected table {marker!r}")
    body = text[start + len(marker):]
    # Return every known coordinate as { questID: [{mapID, x, y}, ...] }.
    result: dict[int, list] = {}
    if field == "previewPoint":
        # For the objective table, packed values include uiMapID in the high
        # digits (unlike the turn-in table, whose map is an outer key).
        for match in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)\s*,", body):
            packed = int(match.group(2))
            map_id = packed // 100_000_000
            result[int(match.group(1))] = [decode_packed_point(map_id, packed)]
    else:
        # Each quest row can include several maps and alternative locations.
        for match in re.finditer(r"\[(\d+)\]\s*=\s*\{([^\n]*)", body):
            quest_id = int(match.group(1))
            points = []
            for map_match in re.finditer(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", match.group(2)):
                map_id = int(map_match.group(1))
                for packed_text in re.findall(r"\d+", map_match.group(2)):
                    point = decode_packed_point(map_id, int(packed_text))
                    if point not in points:
                        points.append(point)
            if points:
                result[quest_id] = points
    if not result:
        raise RuntimeError(f"could not parse any points from {filename}")
    return result


def table_section(text: str, name: str) -> str:
    marker = name + " = {"
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"QuestAvailable_Forever.lua has no {name} table")
    start += len(marker)
    next_section = re.search(r"\n(?:gates|names|pre|preAll|excl|chain|parent|skill|minRep|maxRep) = \{", text[start:])
    end = start + next_section.start() if next_section else text.find("\n}", start)
    if end < start:
        raise RuntimeError(f"could not delimit {name} table")
    return text[start:end]


def parse_quest_starts(payload: bytes) -> dict[int, list]:
    text = payload.decode("utf-8-sig")
    body = table_section(text, "start")
    starts: dict[int, list] = {}
    for line in body.splitlines():
        quest_match = re.match(r"\s*\[(\d+)\]\s*=\s*\{(.*)", line)
        if not quest_match:
            continue
        quest_id = int(quest_match.group(1))
        points = []
        for map_match in re.finditer(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", quest_match.group(2)):
            map_id = int(map_match.group(1))
            for packed_text in re.findall(r"\d+", map_match.group(2)):
                packed = int(packed_text)
                rest = packed % 100_000_000
                point = decode_packed_point(map_id, rest)
                if point not in points:
                    points.append(point)
        if points:
            starts[quest_id] = points
    if not starts:
        raise RuntimeError("could not parse quest start points")
    return starts


def parse_quest_values(payload: bytes, section: str, *, lists: bool = False, strings: bool = False) -> dict[int, object]:
    text = payload.decode("utf-8-sig")
    body = table_section(text, section)
    result: dict[int, object] = {}
    for line in body.splitlines():
        match = re.match(r"\s*\[(\d+)\]\s*=\s*(.+?),?\s*$", line)
        if not match:
            continue
        quest_id, value = int(match.group(1)), match.group(2).strip().rstrip(",")
        if lists:
            values = [int(item) for item in re.findall(r"\d+", value)]
            if values:
                result[quest_id] = values
        elif strings:
            try:
                result[quest_id] = json.loads(value)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"invalid quest name for {quest_id}") from exc
        elif re.fullmatch(r"\d+", value):
            result[quest_id] = int(value)
    return result


def quote_lua(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def lua(value) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return quote_lua(value)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        parts = []
        for key in sorted(value, key=lambda item: (type(item).__name__, str(item))):
            lua_key = f"[{lua(key)}]" if isinstance(key, str) else f"[{key}]"
            parts.append(f"{lua_key}={lua(value[key])}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"cannot serialize {type(value).__name__} as Lua")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--client-build", default="1.60.1.70291")
    parser.add_argument("--items", action="store_true", help="also fetch the AHledger item catalog")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    source = manifest["sources"][0]
    items: dict[int, dict] = {}
    hashes: dict[str, str] = {}
    for position, category in enumerate(CLASSES if args.items else ()):
        payload = fetch_catalog(category)
        hashes[category] = hashlib.sha256(payload).hexdigest()
        rows = json.loads(payload)["rows"]
        for row in rows:
            if not isinstance(row, list) or len(row) < 8:
                raise RuntimeError(f"malformed catalog row in {category}: {row!r}")
            item_id, name, quality, subclass, item_level, required_level, icon, equip_loc = row[:8]
            if not isinstance(item_id, int) or item_id <= 0 or not isinstance(name, str):
                raise RuntimeError(f"invalid id or name in {category}: {row!r}")
            subclass_value = RECIPE_SUBCLASSES.get(subclass) if category == "recipe" else subclass
            item = {
                "name": name,
                "class": ITEM_CLASSES[category],
                "subClass": subclass_value,
                "quality": quality,
                "itemLevel": item_level,
                "requiredLevel": required_level,
                "icon": icon,
                "equipLoc": equip_loc,
            }
            previous = items.get(item_id)
            if previous is not None and previous != item:
                raise RuntimeError(f"conflicting AHledger rows for item {item_id}")
            items[item_id] = item
        if position + 1 < len(CLASSES):
            time.sleep(0.15)

    quest_points: dict[int, dict[str, object]] = {}
    quest_hashes: dict[str, str] = {}
    for filename, field in ((EVERYTHING_QUEST_FILES[0], "previewPoint"), (EVERYTHING_QUEST_FILES[1], "turnInPoint")):
        payload = fetch_everything_quests(filename)
        quest_hashes[filename] = hashlib.sha256(payload).hexdigest()
        for quest_id, point in parse_quest_coordinates(filename, field, payload).items():
            quest_points.setdefault(quest_id, {})[field] = point

    available_filename = EVERYTHING_QUEST_FILES[2]
    available_payload = fetch_everything_quests(available_filename)
    quest_hashes[available_filename] = hashlib.sha256(available_payload).hexdigest()
    availability = {
        "startPoints": parse_quest_starts(available_payload),
        "startGate": parse_quest_values(available_payload, "gates"),
        "name": parse_quest_values(available_payload, "names", strings=True),
        "startRequiresAny": parse_quest_values(available_payload, "pre", lists=True),
        "startRequiresAll": parse_quest_values(available_payload, "preAll", lists=True),
        "startExcluded": parse_quest_values(available_payload, "excl", lists=True),
        "startBlockedBy": parse_quest_values(available_payload, "chain"),
        "startParent": parse_quest_values(available_payload, "parent"),
    }
    for field, values in availability.items():
        for quest_id, value in values.items():
            quest_points.setdefault(quest_id, {})[field] = value

    item_ids = sorted(items)
    item_rows = {
        item_id: [items[item_id].get(field) for field in ENTITY_FIELDS["Item"]]
        for item_id in item_ids
    }
    empty = {"fields": [], "ids": [], "rows": {}}
    quest_ids = sorted(quest_points)
    quest_rows = {
        quest_id: [quest_points[quest_id].get(field) for field in ENTITY_FIELDS["Quest"]]
        for quest_id in quest_ids
    }
    entities = {
        "Quest": {"fields": ENTITY_FIELDS["Quest"], "ids": quest_ids, "rows": quest_rows},
        "Npc": {"fields": ENTITY_FIELDS["Npc"], "ids": [], "rows": {}},
        "Item": {"fields": ENTITY_FIELDS["Item"], "ids": item_ids, "rows": item_rows},
        "Object": {"fields": ENTITY_FIELDS["Object"], "ids": [], "rows": {}},
    }
    snapshot_date = date.today().isoformat()
    meta = {
        "schema": 1,
        "source": ("AHledger public catalog API; " if args.items else "") + "Everything Quests MIT quest tables",
        "sourceRevision": f"client build {args.client_build}; Everything Quests {EVERYTHING_QUESTS_COMMIT}; snapshot {snapshot_date}",
        "clientBuild": args.client_build,
        "snapshotDate": snapshot_date,
        "license": ("AHledger API terms with attribution/no-feed-resale; " if args.items else "") + "Everything Quests MIT License and included AllTheThings MIT notice",
        "licenseEvidence": (source["license_evidence"] + " " if args.items else "") + "Waypoint data: Everything Quests MIT-licensed repository at commit " + EVERYTHING_QUESTS_COMMIT + "; MIT notices shipped under Data/ThirdParty. This does not itself grant rights to Blizzard-owned underlying game content.",
        "trust": ("AHledger item catalog; " if args.items else "") + "MIT quest waypoint and availability tables; no NPC/object spawn facts",
        "counts": {"Quest": len(quest_ids), "Npc": 0, "Item": len(item_ids), "Object": 0},
        "apiResponseSha256": hashes,
        "questSource": "Everything Quests; objective/turn-in points and quest-start availability tables",
        "questSourceCommit": EVERYTHING_QUESTS_COMMIT,
        "questSourceSha256": quest_hashes,
        "questPointCounts": {
            "objectiveOrFallback": sum("previewPoint" in row for row in quest_points.values()),
            "turnIn": sum("turnInPoint" in row for row in quest_points.values()),
            "turnInAlternatives": sum(len(row.get("turnInPoint", [])) for row in quest_points.values()),
            "startPoints": sum(len(row.get("startPoints", [])) for row in quest_points.values()),
            "uniqueQuests": len(quest_ids),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("-- Generated by tools/build_database.py from the Everything Quests tables" + (" and AHledger's public catalog API" if args.items else "") + ".\n")
        stream.write("-- Attribution and source limits are documented in DATA-SOURCES.md.\n")
        stream.write("local _, ns = ...\nns.BundledDatabase = {\n")
        stream.write("meta = " + lua(meta) + ",\n")
        stream.write("zone = {},\nenum = {},\nentities = {\n")
        for kind in ("Quest", "Npc", "Item", "Object"):
            entity = entities[kind]
            stream.write(f"{kind} = {{ fields = {lua(entity['fields'])}, ids = {lua(entity['ids'])}, rows = {{\n")
            for item_id in entity["ids"]:
                stream.write(f"[{item_id}] = {lua(entity['rows'][item_id])},\n")
            stream.write("}},\n")
        stream.write("},\n}\n")
    print(f"Exported {len(item_ids)} catalog items and {len(quest_ids)} quest waypoint/availability records; no NPC/object spawn database.")
    print(f"Client build {args.client_build}; Everything Quests {EVERYTHING_QUESTS_COMMIT}; captured {snapshot_date}.")
    print(f"Wrote {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, RuntimeError, TypeError) as exc:
        raise SystemExit(f"database build failed: {exc}")

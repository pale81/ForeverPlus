# ForeverPlus database sources and limits

## Bundled dataset

`Data/Database.lua` is generated from three pinned MIT quest tables of Everything Quests: `QuestCoords_Forever.lua` (one general objective-area point), `QuestTurnIn_Forever.lua` (all known hand-in alternatives) and `QuestAvailable_Forever.lua` (quest start points, English name fallbacks and start requirements), commit `bb29c7326185377d05381a0a7c6817e4d3f1e883`. File hashes and the source revision are stored in the database metadata. The snapshot has 4467 quests (about 1 MB, 40 ms to load).

The quest tables are adapted from [Everything Quests](https://github.com/wheelbarrel00/EverythingQuests), whose repository is MIT-licensed. Its README identifies 323 quests new to Forever and says 319 have pickup markers. Quest data from AllTheThings is called out separately by the upstream project and carries its own MIT notice. Both notices are included under `Data/ThirdParty/`. The imported start table includes source coordinates, English title fallbacks and selected level/race/class/prerequisite/exclusion rules. The waypoint tables do **not** contain quest descriptions, NPC/object spawn lists or per-objective associations. For an active quest, ForeverPlus uses the game's objective text and shows a general objective-area point; after objectives are complete it uses the known hand-in alternatives. A richer optional QuestieDB provider can supply per-objective points. The MIT licence does not itself grant rights to Blizzard-owned underlying game content.

**Item catalog (not shipped).** An earlier snapshot also contained the 27k-item catalog of AHledger's public API. It was removed from the shipped file: none of ForeverPlus's features can use items without vendor, drop or spawn data, and it cost 4 MB and about 22 MB of memory. `python3 tools/build_database.py --items` adds it again. AHledger's [API terms](https://ahledger.com/terms) (updated 2026-09-19) allow personal and commercial use of the public API if the data is credited with a link wherever it is shown and is not resold as a feed; item names, icons and game data belong to Blizzard.

## What is and is not included

Quest rows contain the bundled point and availability fields described above. ForeverPlus keeps other unknown relations empty instead of deriving them from another database.

The current snapshot contains **no bundled item, NPC, entity spawn, object, vendor, loot, quest description or per-objective data**. It does include English quest-title fallbacks and quest-start coordinates. Recipe-map vendor pins, flight master, inn and instance entrance symbols, loot sources and detailed per-objective pins still require a richer provider (QuestieDB when installed); bundled waypoint rows supply general objective and hand-in points. Gaps are to be filled with openly licensed data or with observations players record themselves (`/fp daten`, see below). Start pins apply known level/race/class/prerequisite rules, but not every possible reputation or event requirement. The Quest tracker still uses the in-game quest APIs for active quest state.

Local observation capture remains opt-in (`/fp daten an|aus|löschen`) and stores client-visible quest titles/objectives separately in SavedVariables. The WoW client does not expose arbitrary hidden server data, full quest descriptions, drop probabilities, or coordinates for every entity through supported addon APIs. No local observation is silently merged into the shipped snapshot.

## Sources reviewed

| Source | What it offers | Decision |
| --- | --- | --- |
| [AHledger open data](https://ahledger.com/data), [API](https://ahledger.com/developers), [terms](https://ahledger.com/terms) | Forever item catalog read from the game client; public JSON by item class. The site separately describes player-observed quest/vendor/creature reports. | **Optional item catalog (`--items`), not shipped**, under the API's express attribution/no-feed-resale terms. Observed reports are not imported because no bulk public API for them is documented. |
| [Everything Quests](https://github.com/wheelbarrel00/EverythingQuests), pinned commit `bb29c7326185377d05381a0a7c6817e4d3f1e883` | Forever quest start, objective-area and hand-in point tables; its README describes 323 new-to-Forever quests, 319 with pickup markers. The repo is MIT-licensed and carries a separate MIT notice for AllTheThings quest data. | **Imported quest points and selected availability fields**, preserving both MIT notices. No descriptions, NPC/object spawns, or objective-to-source links are imported. MIT covers upstream rights but is not a Blizzard content grant. |
| [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings), `.contrib/.db/forever` and generated `db/Camelot` | Forever quest, vendor, recipe, flight path, object and instance data in ATT's format: about 1000 NPCs with map coordinates, 155 recipe vendors with their recipes, recipe drop sources, instance coordinates. Repository LICENSE: MIT (the CurseForge page says "All Rights Reserved"). | **Used for the library book hand-in quest IDs** (`Data/Library.lua`). The vendor/recipe/flight tables are the candidate replacement for the QuestieDB-dependent features; not imported yet. |
| [QuestieDB Forever](https://github.com/Questie/QuestieDB) | Lua tables for quests, NPCs, items and objects, including spawn and relationship fields. | Not bundled. Its initial data/schema came from Questie; the pinned repository snapshot had no dataset license. Questie's maintainer says historical Questie data should be treated as all rights reserved ([issue #4447](https://github.com/Questie/Questie/issues/4447)). |
| [WoW Forever data page](https://wowforever.ninja/about/data/) | Documents a Classic baseline, client-derived Forever facts, in-game observations, and provenance labels. | Not imported: no stable bulk dataset/API and redistribution terms established in this review. |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | SQL database for Classic 1.12; repository code/data are presented with GPL notices. | Not imported: its copyright notice separately restricts Blizzard-derived content and describes a non-commercial demo use. |
| [ForeverTome](https://github.com/Skold177/ForeverTome) | GPL-2.0 collector and exporter for player observations. | Used as a reference for capture/provenance ideas only. Its code license does not license the collected game data; no separate redistribution grant for its saved data was established. |

## Rebuild

Requirements: Python 3 and network access to `raw.githubusercontent.com` (and `ahledger.com` with `--items`). From the addon directory:

```sh
python3 tools/build_database.py
```

To target another client build explicitly:

```sh
python3 tools/build_database.py --client-build 1.60.1.70291
```

The build fetches the three Everything Quests files at the pinned commit; with `--items` it also fetches the 12 AHledger catalog classes listed in `tools/data_sources.json`. It validates row shapes and coordinates, rejects conflicting item IDs, and writes the snapshot. It records the capture date, client build, upstream commit, and content hashes. Review generated diffs before publishing; AHledger's results (with `--items`) are live and may change, so refresh the licence/terms check then. Review any upstream pin change before updating the manifest.

## Local observations and data quality

Observation capture is off by default. `/fp daten an` saves client-visible quest titles and objective snapshots to `ForeverPlusDB` under `observations`; `/fp daten aus` stops it, `/fp daten` reports status, and `/fp daten löschen` clears it. Entries include quest IDs, time and capture method. Repeated identical objectives are deduplicated; history is capped at 20 snapshots per quest and 200 quests. This is local user state and is not sent anywhere or included by the build.

The validator checks sorted unique IDs, row shapes, counts, source metadata, response hashes, and that quest point lists contain valid map coordinates. Lua syntax and the addon's host API still need separate checks; no live-client test is implied by a successful data build.

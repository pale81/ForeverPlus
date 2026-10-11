#!/bin/sh
# Richtet die Arbeitsumgebung auf dem Mac ein (einmalig): Lua 5.1, luacheck, die Referenzdaten
# (QuestieDB fuer die Tests, Blizzards Interface-Quelltext zum Nachschlagen) und die lokalen Arbeitsregeln.
#   sh tools/setup-local.sh          Pflichtteile
#   sh tools/setup-local.sh --data   zusaetzlich die Quellen der Datengeneratoren (gross)
set -eu
cd "$(dirname "$0")/.."
DIR="$(pwd)"
DEV="${FP_DEV:-$HOME/ForeverPlus-dev}"
mkdir -p "$DEV"

command -v brew >/dev/null 2>&1 || { echo "Homebrew fehlt (https://brew.sh), danach noch einmal."; exit 1; }
if ! { command -v lua5.1 || command -v lua-5.1; } >/dev/null 2>&1; then brew install lua@5.1 || true; fi
command -v luacheck >/dev/null 2>&1 || brew install luacheck
command -v python3 >/dev/null 2>&1 || brew install python

clone() { # url dir [branch]
	if [ -d "$DEV/$2/.git" ]; then git -C "$DEV/$2" pull --ff-only --quiet || true; return; fi
	if [ -n "${3:-}" ]; then git clone --depth 1 -b "$3" "$1" "$DEV/$2"; else git clone --depth 1 "$1" "$DEV/$2"; fi
}
clone https://github.com/Questie/QuestieDB.git QuestieDB
clone https://github.com/Gethe/wow-ui-source.git wow-ui-source forever
if [ "${1:-}" = "--data" ]; then
	clone https://github.com/JIVESCORP/eg-link-output-wowf eg
	[ -d "$DEV/att/.git" ] || git clone --depth 1 --filter=blob:none https://github.com/ATTWoWAddon/allthethings "$DEV/att"
fi

# Arbeitsregeln fuer die lokale Sitzung: bleiben aus dem Repository heraus.
cp tools/local/rules.md CLAUDE.md
grep -qx "CLAUDE.md" .git/info/exclude 2>/dev/null || echo "CLAUDE.md" >> .git/info/exclude

echo
echo "Fertig. Referenzdaten in $DEV (QuestieDB, wow-ui-source)."
echo "Pruefen: sh tools/check.sh"
echo "Das Auto-Pull braucht es lokal nicht mehr: sh tools/autopull.sh uninstall"

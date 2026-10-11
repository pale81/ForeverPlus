#!/bin/sh
# Tests und luacheck. Aufruf im Addon-Ordner: sh tools/check.sh
set -eu
cd "$(dirname "$0")/.."
DEV="${FP_DEV:-$HOME/ForeverPlus-dev}"
LUA=""
# Homebrew's lua@5.1 is not linked into the PATH ("keg-only"), so its folders are looked at too.
for name in lua5.1 lua-5.1 lua51 /opt/homebrew/opt/lua@5.1/bin/lua5.1 /opt/homebrew/opt/lua@5.1/bin/lua-5.1 /usr/local/opt/lua@5.1/bin/lua5.1 /usr/local/opt/lua@5.1/bin/lua-5.1 lua; do
	if command -v "$name" >/dev/null 2>&1 && "$name" -v 2>&1 | grep -q "5\.1"; then LUA="$name"; break; fi
done
[ -n "$LUA" ] || { echo "Lua 5.1 fehlt: sh tools/setup-local.sh"; exit 1; }
export QUESTIEDB="${QUESTIEDB:-$DEV/QuestieDB/}"
[ -d "$QUESTIEDB" ] || { echo "QuestieDB fehlt in $QUESTIEDB: sh tools/setup-local.sh"; exit 1; }
(cd tests && "$LUA" run.lua ..) | tail -n 3
command -v luacheck >/dev/null 2>&1 || { echo "luacheck fehlt: sh tools/setup-local.sh"; exit 1; }
luacheck . | tail -n 2

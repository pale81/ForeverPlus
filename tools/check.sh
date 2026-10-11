#!/bin/sh
# Tests und luacheck. Aufruf im Addon-Ordner: sh tools/check.sh
set -eu
cd "$(dirname "$0")/.."
DEV="${FP_DEV:-$HOME/ForeverPlus-dev}"
LUA=""
# Lua 5.1 kommt aus $DEV/lua51 (gebaut von setup-local.sh, Homebrew fuehrt lua@5.1 nicht mehr) oder aus dem PATH.
for name in "$DEV/lua51/bin/lua" lua5.1 lua-5.1 lua51 /opt/homebrew/opt/lua@5.1/bin/lua5.1 /opt/homebrew/opt/lua@5.1/bin/lua-5.1 /usr/local/opt/lua@5.1/bin/lua5.1 /usr/local/opt/lua@5.1/bin/lua-5.1 lua; do
	if command -v "$name" >/dev/null 2>&1 && "$name" -v 2>&1 | grep -q "Lua 5\.1"; then LUA="$name"; break; fi
done
[ -n "$LUA" ] || { echo "Lua 5.1 fehlt: sh tools/setup-local.sh"; exit 1; }
export QUESTIEDB="${QUESTIEDB:-$DEV/QuestieDB/}"
[ -d "$QUESTIEDB" ] || { echo "QuestieDB fehlt in $QUESTIEDB: sh tools/setup-local.sh"; exit 1; }
(cd tests && "$LUA" run.lua ..) | tail -n 3
command -v luacheck >/dev/null 2>&1 || { echo "luacheck fehlt: sh tools/setup-local.sh"; exit 1; }
luacheck . | tail -n 2

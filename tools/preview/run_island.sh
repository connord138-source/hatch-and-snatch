#!/bin/bash
# Top-down map of the island layout: zones, fortress footprints, paths and every
# landmark part (from src/server/Landmarks.luau), for checking against the concept.
#   bash tools/preview/run_island.sh <out.png>
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/island.png}
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' ../tests/stub.luau
	grep -v '^return true$' world_stub.luau
	echo 'local Landmarks = (function()'
	grep -v '^--!strict' ../../src/server/Landmarks.luau \
		| sed 's#require(script.Parent.Props)#{ template = function() return nil end, spawn = function() return nil end }#'
	echo 'end)()'
	cat <<'LUA'
local root = Instance.new("Folder")
Landmarks.build(root, { groundY = 0.2, islandRadius = 410, zoneInner = 205, zoneOuter = 295, plazaRadius = 56 })
dumpParts(root)
LUA
} > "$chunk"
luau "$chunk" > "${OUT%.png}.txt"
rm "$chunk"
python3 island_map.py "${OUT%.png}.txt" "$OUT"

#!/bin/bash
# Dumps the part-built fortress (and a stand-in plot) for each base level, then
# renders them: bash tools/preview/run_fortress.sh <out_dir> [theme_wall_material]
# Needs the luau CLI and Blender's Python (BPY, default /tmp/claude-0/bpyenv/bin/python).
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/fortress_preview}
mkdir -p "$OUT"
for level in 1 2 3 4 5; do
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' ../tests/stub.luau
		grep -v '^return true$' world_stub.luau
		bash keep_constants.sh # WorldService's layout numbers, for plot_context
		grep -v '^return true$' plot_context.luau
		grep -v '^return true$' props_stub.luau
		echo 'local CastleKits = (function()'
		grep -v '^--!strict' ../../src/server/CastleKits.luau | sed 's#require(script.Parent.Props)#PreviewProps#'
		echo 'end)()'
		echo 'local Fortress = (function()'
		grep -v '^--!strict' ../../src/server/Fortress.luau \
			| sed 's#require(ReplicatedStorage.Shared.Config)#{}#' \
			| sed 's#require(script.Parent.CastleKits)#CastleKits#' \
			| sed 's#require(script.Parent.Props)#PreviewProps#'
		echo 'end)()'
		cat <<LUA
local root = Instance.new("Folder")
local W, D = plotContext(root, $level)
local theme = { trimColor = Color3.fromRGB(70, 95, 160), laserColor = Color3.fromRGB(220, 40, 40), wall = nil }
Fortress.build(root, CFrame.identity, $level, W, D, -22, theme)
dumpParts(root)
LUA
	} > "$chunk"
	luau "$chunk" > "$OUT/level$level.txt"
	rm "$chunk"
done
EGL_PLATFORM=surfaceless ${BPY:-/tmp/claude-0/bpyenv/bin/python} render_parts.py -- "$OUT" 2>&1 | grep -E "wrote|Error" || true

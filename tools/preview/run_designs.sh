#!/bin/bash
# Renders the maxed Citadel in several Castle Designer presets (Config.CastleDesigns):
#   bash tools/preview/run_designs.sh <out_dir> [Preset Preset ...]
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/designs_preview}
shift || true
PRESETS=${@:-Classic Ice Fire Light Dark Rainbow}
mkdir -p "$OUT"
rm -f "$OUT"/level*.txt
for preset in $PRESETS; do
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' ../tests/stub.luau
		grep -v '^return true$' world_stub.luau
		grep -v '^return true$' plot_context.luau
		echo 'local Designs = (function()'
		grep -v '^--!strict' ../../src/shared/Config/CastleDesigns.luau | sed 's#require(script.Parent.Progression)#{}#'
		echo 'end)()'
		echo 'local Fortress = (function()'
		grep -v '^--!strict' ../../src/server/Fortress.luau \
			| sed 's#require(ReplicatedStorage.Shared.Config)#{}#' \
			| sed 's#require(script.Parent.Props)#{ template = function() return nil end, spawn = function() return nil end }#'
		echo 'end)()'
		cat <<LUA
local root = Instance.new("Folder")
local W, D = plotContext(root, 5)
local theme = Designs.resolve(Designs.presetsById["$preset"].picks)
-- The stand-in plot takes the design's floor and stone like WorldService does
for _, d in root:GetDescendants() do
	if d.IsPart and (d.Name == "Floor" or d.Name == "Floor2" or d.Name == "Floor3" or d.Name == "Ramp") then
		d.Material = theme.floorMaterial
		d.Color = theme.floorColor
	elseif d.IsPart and (d.Name == "Wall" or d.Name == "Trim") and theme.wall then
		d.Material = theme.wall.material
		d.Color = theme.wall.color
	end
end
Fortress.build(root, CFrame.identity, 5, W, D, -22, theme)
dumpParts(root)
LUA
	} > "$chunk"
	luau "$chunk" > "$OUT/level_$preset.txt"
	rm "$chunk"
done
EGL_PLATFORM=surfaceless ${BPY:-/tmp/claude-0/bpyenv/bin/python} render_parts.py -- "$OUT" 2>&1 | grep -E "wrote|Error" || true

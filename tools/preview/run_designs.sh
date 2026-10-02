#!/bin/bash
# Renders the maxed Citadel in several Castle Designer presets (Config.CastleDesigns),
# with the theme kits' real models where their GLBs are on disk (assets/tripo/props):
#   bash tools/preview/run_designs.sh <out_dir> [Preset Preset ...]
# NIGHT=1 renders at night, so the kits' themed lights show like the concepts.
# VIEW=front uses the concepts' camera; RENDER=0 writes only the part dumps.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/designs_preview}
shift || true
PRESETS=${@:-Classic Ice Fire Light Dark Rainbow}
mkdir -p "$OUT"
rm -f "$OUT"/level*.txt
# Creatures stand on the pedestals when their GLBs are on disk (fetch_assets.py)
export CREATURE_DIR=${CREATURE_DIR:-/tmp/claude-0/allglb}
AVAILABLE=$( { python3 glb_extents.py ../../assets/tripo/props; [ -d "$CREATURE_DIR" ] && python3 glb_extents.py "$CREATURE_DIR"; } | tr '\n' ' ')
for preset in $PRESETS; do
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' ../tests/stub.luau
		grep -v '^return true$' world_stub.luau
		grep -v '^return true$' plot_context.luau
		echo "AVAILABLE_PROPS = { $AVAILABLE }"
		grep -v '^return true$' props_stub.luau
		echo 'local Designs = (function()'
		grep -v '^--!strict' ../../src/shared/Config/CastleDesigns.luau | sed 's#require(script.Parent.Progression)#{}#'
		echo 'end)()'
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
local W, D = plotContext(root, 5)
local theme = Designs.resolve(Designs.presetsById["$preset"].picks)
-- The stand-in plot takes the design's floor and stone like WorldService does
for _, d in root:GetDescendants() do
	if d.IsPart and (d.Name == "Floor" or d.Name == "Floor2" or d.Name == "Floor3" or d.Name == "Ramp") then
		d.Material = theme.floorMaterial
		d.Color = theme.floorColor
	elseif d.IsPart and d.Name == "VaultDoor" then
		d.Color = theme.laserColor -- WorldService glows them in the design's glow
	elseif d.IsPart and (d:GetAttribute("Glass") or d:GetAttribute("Keep")) and theme.wall then
		d.Material = theme.wall.material
		d.Color = if d:GetAttribute("Keep") then theme.wall.color:Lerp(Color3.new(1, 1, 1), 0.12) else theme.wall.color
	end
end
Fortress.build(root, CFrame.identity, 5, W, D, -22, theme)
-- The keep takes the kit too (WorldService.dressKeep), with the same piece names
local kit = CastleKits.get(theme.kit)
if kit then
	local keep = {}
	for _, d in root:GetDescendants() do
		if d.IsPart and (d:GetAttribute("Glass") or d:GetAttribute("Keep") or (d.Name == "Floor" and d.CFrame.Position.Y > 5)) then
			table.insert(keep, d)
		end
	end
	CastleKits.dressKeep(root, kit, keep)
end
dumpParts(root)
LUA
	} > "$chunk"
	luau "$chunk" > "$OUT/level_$preset.txt" || { echo "luau failed for $preset (chunk kept at $chunk)"; exit 1; }
	rm "$chunk"
done
# RENDER=0 stops after the part dumps (level_<Preset>.txt)
[ "${RENDER:-1}" = 0 ] && exit 0
EGL_PLATFORM=surfaceless ${BPY:-/tmp/claude-0/bpyenv/bin/python} render_parts.py -- "$OUT" ${VIEW:-aerial} 2>&1 | grep -E "wrote|Error" || true

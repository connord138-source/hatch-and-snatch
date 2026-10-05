#!/bin/bash
# Renders the part-built conveyor loop (src/server/Conveyor.luau) with a few eggs
# on it and a stand-in reactor: bash tools/preview/run_conveyor.sh <out_dir>
# (NIGHT=1 for the night look). Needs the luau CLI and Blender's Python.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/conveyor_preview}
mkdir -p "$OUT"
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' ../tests/stub.luau
	grep -v '^return true$' world_stub.luau
	echo 'local Belt = (function()'
	grep -v '^--!strict' ../../src/shared/Belt.luau \
		| sed 's#require(script.Parent.Config)#{ Eggs = { conveyor = { spawnSeconds = 2.5, speed = 7, radius = 46, height = 3.4, tunnelCenterDegrees = 30, tunnelHalfDegrees = 14 } } }#'
	echo 'end)()'
	echo 'local Conveyor = (function()'
	grep -v '^--!strict' ../../src/server/Conveyor.luau | sed 's#require(ReplicatedStorage.Shared.Belt)#Belt#'
	echo 'end)()'
	cat <<'LUA'
local root = Instance.new("Folder")
Conveyor.build(root, Vector3.new(0, 0, 0), 46)
for i = 0, 7 do
	local egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(2.4, 2.4, 2.4)
	egg.Color = Color3.fromRGB(120 + i * 15, 200 - i * 10, 120)
	egg.CFrame = Belt.cframe(Vector3.new(0, 0, 0), 4.0 + i * 0.12)
	egg.Parent = root
end
local reactor = Instance.new("Part")
reactor.Shape = Enum.PartType.Cylinder
reactor.Size = Vector3.new(10, 26, 26)
reactor.CFrame = CFrame.new(0, 5, 0) * CFrame.Angles(0, 0, math.pi / 2)
reactor.Color = Color3.fromRGB(60, 58, 62)
reactor.Parent = root
dumpParts(root)
LUA
} > "$chunk"
luau "$chunk" > "$OUT/level1.txt"
rm "$chunk"
EGL_PLATFORM=surfaceless ${BPY:-/tmp/claude-0/bpyenv/bin/python} render_parts.py -- "$OUT" belt 2>&1 | grep -E "wrote|Error" || true

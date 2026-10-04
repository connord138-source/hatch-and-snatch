#!/bin/bash
# Renders the part-built Luck Wheel (src/server/LuckWheel.luau) with the real
# slices from Config/Economy.luau: level1 at rest, level2 turned 37° with the
# flapper swung by a peg. Two cameras: square on (wheel) and three-quarter (wheel34).
#   bash tools/preview/run_wheel.sh <out_dir>      (NIGHT=1 for the night look)
# Needs the luau CLI and Blender's Python (BPY, default /tmp/claude-0/bpyenv/bin/python).
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/wheel_preview}
mkdir -p "$OUT/front" "$OUT/side"
segments=$(awk '/^\tluckWheel = \{/{on=1} on{print} on&&/^\t\},$/{exit}' ../../src/shared/Config/Economy.luau \
	| sed '1s/.*luckWheel = /local SEGMENTS = /; $s/},$/}/')
for pose in 1 2; do
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' ../tests/stub.luau
		grep -v '^return true$' world_stub.luau
		echo "$segments"
		echo 'local LuckWheel = (function()'
		grep -v '^--!strict' ../../src/server/LuckWheel.luau
		echo 'end)()'
		cat <<LUA
local root = Instance.new("Folder")
local built = LuckWheel.build(root, Vector3.new(0, 0, 0), Vector3.new(0, 0, -100), SEGMENTS, 20, 10)
if $pose == 2 then
	local base = built.base
	local turn = base * CFrame.Angles(0, 0, math.rad(37)) * base:Inverse()
	for _, d in built.disc:GetDescendants() do
		if d.IsPart then d.CFrame = turn * d.CFrame end
	end
	local flapper = built.model:FindFirstChild("Flapper")
	local pivot = flapper:GetAttribute("PivotCFrame")
	local swing = pivot * CFrame.Angles(0, 0, math.rad(-30)) * pivot:Inverse()
	for _, d in flapper:GetChildren() do
		if d.IsPart then d.CFrame = swing * d.CFrame end
	end
end
dumpParts(root)
LUA
	} > "$chunk"
	luau "$chunk" > "$OUT/front/level$pose.txt"
	cp "$OUT/front/level$pose.txt" "$OUT/side/level$pose.txt"
	rm "$chunk"
done
BPY=${BPY:-/tmp/claude-0/bpyenv/bin/python}
EGL_PLATFORM=surfaceless $BPY render_parts.py -- "$OUT/front" wheel 2>&1 | grep -E "wrote|Error" || true
EGL_PLATFORM=surfaceless $BPY render_parts.py -- "$OUT/side" wheel34 2>&1 | grep -E "wrote|Error" || true

#!/bin/bash
# Checks the pedestal slot layout against the real Config (see slots_test.luau).
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
for f in ../../src/shared/Config/*.luau; do
	name=$(basename "$f")
	[ "$name" = "init.luau" ] && name="Config.luau"
	{
		cat ../sim/stub.luau
		sed -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/g; s/require\(script\.([A-Za-z]+)\)/require(".\/\1")/g' "$f"
	} > "$out/$name"
done
cp slots_test.luau "$out/"
luau "$out/slots_test.luau"

#!/bin/bash
# Checks the Castle Designer config against the real Config (see designs_test.luau).
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
cp designs_test.luau "$out/"
luau "$out/designs_test.luau"

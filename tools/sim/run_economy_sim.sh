#!/bin/bash
# Runs the economy simulator (economy_sim.luau) against the real Config in
# src/shared/Config. The luau CLI has no Roblox globals and no `script`, so each
# Config module gets stub.luau prepended and its requires rewritten to paths.
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
for f in ../../src/shared/Config/*.luau; do
	name=$(basename "$f")
	[ "$name" = "init.luau" ] && name="Config.luau"
	{
		cat stub.luau
		sed -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/g; s/require\(script\.([A-Za-z]+)\)/require(".\/\1")/g' "$f"
	} > "$out/$name"
done
cp economy_sim.luau "$out/"
luau "$out/economy_sim.luau" -a "$@"

#!/bin/bash
# Luau CLI modules don't share globals, so glue the stub, the module and the test into one chunk
cd "$(dirname "$0")"
out=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' stub.luau
	echo 'local CreatureGrounding = (function()'
	grep -v '^--!strict' ../../src/client/CreatureGrounding.luau
	echo 'end)()'
	cat grounding_test.luau
} > "$out"
luau "$out"

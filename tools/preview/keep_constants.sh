#!/bin/bash
# Prints WorldService's plot and keep layout constants (plot sizes, floors, spots,
# ramps, vaults, niches) as Luau, for plot_context.luau to build the preview's keep
# from the game's own numbers instead of a copy that drifts.
grep -E '^local (TOP|PLOT_FRONT|PLOT_WIDTHS|PLOT_DEPTHS|FLOOR_HEIGHT|FLOOR_X|FLOOR_Z0|FLOOR_Z1|FLOOR_ROW_Z|FLOOR_FRONT_X|FLOOR_SIDE_X|FLOOR_SIDE_Z|RAMP2_EXIT|RAMP2_ENTRY|FLOOR_WALL|VAULT_SIZE|VAULT_Z0|DOOR_WIDTH|GROUND_COLUMNS|GROUND_ROWS|NICHE_BACK|NICHE_WIDTH|NICHE_HEIGHT)\b' \
	"$(dirname "$0")/../../src/server/Services/WorldService.luau"

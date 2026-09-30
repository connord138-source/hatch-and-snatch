# Session handoff: after the Juvenile and set-piece batch

Start a new session with **"read docs/HANDOFF.md and continue"**. Read `CLAUDE.md`
first: it holds the owner's preferences and the art-direction lessons, and they are
binding.

## How we work (owner's rules)

- Claude builds everything. The owner playtests through a separate Claude session on the PC ("the other chat").
- **Anything the PC session has to do goes to the owner as a paste-ready prompt.**
- Full permission for this project, including Higgsfield and Tripo spend. Report costs as you go.
- Repo `connord138-source/hatch-and-snatch`, branch **`claude/core-systems`**.

## State at handoff (2026-09-30)

### Round 3 playtest (owner, 2026-09-29), all pushed

- **Confirmed working:**
  - Creature facing: the 8 checked adults and 5 Juveniles run head-first.
  - The Juveniles look right.
  - Arches and the glowcap ring are walkable, and the crag lightning fires.
  - Every node, shrine and zone middle can be reached from its gate.
- **Changes from the PC session:**
  - Set pieces size by height or footprint.
  - Storm Peaks got a storm-worn look: dead trees, slate shards, scorch marks, and a storm cloud with rain and lightning (`ZoneMoodController`).
  - StudioDebug gained a "store" action.
- **Owner's complaint:** most creatures hovered above the ground. The cause was the idle sit pose: it pitched `Hips`, the parent of the whole skeleton, which swung the front legs up, and folded the hind legs without lowering the body.
  - The fix is `src/client/CreatureGrounding.luau` (forward kinematics over the bones, solved per model), wired into `CreatureAnimator`.
  - The sit now tilts the body nose-up about the front feet, folds the hind legs to meet the ground, and keeps the front legs upright.
  - Every frame, the lowest foot is clamped to the ground, so mid-run landings touch down too.
  - Tested on toy rigs (`tools/tests/run_grounding.sh`) and previewed on real rigs in Blender. **Not yet seen in Studio.**

### Open

- Max Players = 6 has to be set in Creator Hub (owner).
- **What players do inside the biomes is thin:** 7 shared nodes → Essence → shrine egg (15) or blessing (8). The owner asked about it; options are in the chat reply and a decision is pending. The recommendation is wild nests (a rare wild egg spawns in a zone, gets announced, and players race to carry it home, where it can be stolen on the way), then biome events tied to the set pieces.

### Credits left

- **Tripo API: 65.** Enough for 2 textured models, kept as a buffer for redos after the playtest. 935 were spent on 20 Juveniles, 12 props and concepts.
- **Higgsfield: 0.25.** Needs a top-up for any `gpt_image_2_5` concepts (0.5 each at medium).

## Next steps

1. Wait for the owner's check of the grounding fix: pedestal sits, sitting beside the owner, and run landings. If a species sits oddly, the per-body-plan tilt is `SIT_TILT` in `CreatureGrounding.luau`.
   - Then build whichever biome activity the owner picks.
   - For set pieces: Set-piece sizes are the `size` boxes in `SetPieces.luau`. Positions are the `heroes` angle and distance in `WorldService` (same layout as the harvest nodes: angle 0 = gate direction).
2. The remaining 18 Juveniles need about 35 credits each (5 for the concept, 30 for the model), about 630 in all. Top up first.
   - Ultra-rares: Sylvanox, Capybaron, Lurehound, Pyrodrake, Solarion, Glacierion, Stormgriff, Halosaur, Lunaris, Quasarfox, Singularis, Nullcat.
   - Junk: Toastoise, Fridgehog, Grillgator, Laundrophant, Lawnmoose, Bassdog.
   - Toastoise and Fridgehog concepts already exist (uploads `d0d68ca8`, `ffe908cf`) but came out nearly identical to the adults. Redo them with a stronger juvenile push before converting.
3. After any new models, run the facing check (see CLAUDE.md → Rigging) and add `"flip"` where needed.

## Verifying from a cloud session

```
rojo sourcemap default.project.json -o /tmp/sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=/tmp/sourcemap.json --ignore="**/Packages/**" src
stylua --check src --glob '!**/Packages/**'     # use the pinned StyLua 2.0.2; newer versions reformat
```

selene can't fetch the Roblox API dump from the sandbox. For Blender work: `python3.11 -m venv v && v/bin/pip install bpy pillow`.

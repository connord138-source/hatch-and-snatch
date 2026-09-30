# Session handoff: after the economy retune

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
  - Tested on toy rigs (`tools/tests/run_grounding.sh`) and previewed on real rigs in Blender. **Confirmed in Studio 2026-09-30** on pedestals and beside the player.

### Open

- Max Players = 6 has to be set in Creator Hub (owner).
- **Zone set-piece events** are built (`ZoneEventService`, GDD §7.3). The owner picked these over wild nests.
  - **All six were confirmed in Studio 2026-09-30.** They pay out as designed, the heads-ups arrive 10 s ahead, and there were no errors.
  - The PC session made the crater walkable (7891fae).
  - A single round-robin scheduler replaced the per-zone timers, which drifted together.
  - Trigger one with `game.ServerStorage.StudioDebug:Invoke("zone", "<BiomeId>")`.
- **Round-robin confirmed** in Studio 2026-09-30 (gaps 46–58 s, in order). The Frost boulder glow was dimmed further at the owner's request.
- **Monetization is built and confirmed in Studio** (a9beb37, PC fix 4b00361). See GDD §9, `Config/Monetization.luau`, `MonetizationService` and `ShopMenu`.
  - Test without Robux: `game.ServerStorage.StudioDebug:Invoke("pass", "<Key>")` or `Invoke("product", "<Key>")`.
  - **Blocked on the owner:** create the 6 passes and 6 products (5 plus AdBoost) in Creator Hub, and paste the ids into the config. The PC browser was signed in as Dillionaire2424, which has no access; the game belongs to **Dillionaire138**. Placeholder icons are ready on the PC.
  - Flag if asked: VIP is a tag + 10 storage + 10% cash (not +10 pedestals), and Instant Restock was dropped.
- **Free rewards and analytics are confirmed in Studio** (467f78f, PC ids 76c4fd0, ad fix ea9f578). All 6 passes and 6 products have Creator Hub ids. Group skipped (it costs 100 Robux; `tuning.group.id` stays 0). Max Players = 6 is set.
- **Economy retuned** (d49dbaa) after the owner asked that nobody maxes their base on day 1. See GDD §7 "Pacing" and `tools/sim/economy_sim.luau`. Rerun the sim after any economy change.
- **v1 launches with every biome** (owner): no two-biome soft launch; unlocks come from Hatcher Level and base level.
- **First-session guide** (`GuideController`): a goal card on the right edge plus a beam to the next objective, driven by `data.onboarding`. Confirmed in Studio (ff7e9a6, PC fixes 62e9ee5 and 3ec745d). The card moved off top-center afterwards because it stacked with the moon-event and carry banners and hid the ⬇ over distant eggs. `StudioDebug:Invoke("guide")` restarts it.
- **Economy numbers confirmed in the UI** (all prices, B/T/Qa formatting, rebirth at $1T).
- **Batches A, B and C confirmed in Studio** (2026-09-30, PC fixes ec03ea4…e05f635). Measured: steals, reach checks, mobile scaling (UIScale 0.59 on iPhone 14), about 3 KB/s per client with 4 clients, 60 FPS at a full base, and daily rewards Days 1–7 plus quests.
  - The store title and description are set. **The icon and thumbnails still need uploading** (the built-in browser can't attach files): `marketing/icon_512.png` (realistic-eyed Emberlynx, 50464a2) and `thumb_1`…`thumb_4`.
- **Open design question (from the audit):** a walked creature can't be stolen and keeps earning, so an AFK player can protect their best one forever. Options: no earnings while walked, or a walk time limit. Ask the owner.
- **All 41 Juveniles exist** (the 18 ultra-rare and Junk ones were added 2026-09-30, 630 Tripo credits). They are rigged and facing-checked in the sandbox (flips: Grillgator, Lunaris, Quasarfox, Solarion; Sylvanox `+x`). The PC still has to fetch, rig and import them. **The ultra-rare designs themselves still await the owner's approval** (a sheet was sent 2026-09-30; five are lean cat or dog bodies).
- **Launch checklist:** `docs/LAUNCH.md`.
- **Later (owner's ideas):** taming, training, biome shops, larger biomes. Wild nests (race a wild egg home) are still a good fit.

### Credits left

- **Tripo API: 135** after the owner's top-up (API credits cost $0.01 each). 935 were spent on 20 Juveniles, 12 props and concepts.
- **Higgsfield: 0.25.** Needs a top-up for any `gpt_image_2_5` concepts (0.5 each at medium).

## Next steps

1. Wait for the owner's check of the grounding fix: pedestal sits, sitting beside the owner, and run landings. If a species sits oddly, the per-body-plan tilt is `SIT_TILT` in `CreatureGrounding.luau`.
   - Then build whichever biome activity the owner picks.
   - For set pieces: Set-piece sizes are the `size` boxes in `SetPieces.luau`. Positions are the `heroes` angle and distance in `WorldService` (same layout as the harvest nodes: angle 0 = gate direction).
2. Launch: work through `docs/LAUNCH.md` with the owner, and get the ultra-rare designs approved. Redesigning one means a new concept plus new adult, baby and juvenile models: about 110 credits (roughly $1.10).
3. After any new models, run the facing check (see CLAUDE.md → Rigging) and add `"flip"` where needed.

## Verifying from a cloud session

```
rojo sourcemap default.project.json -o /tmp/sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=/tmp/sourcemap.json --ignore="**/Packages/**" src
stylua --check src --glob '!**/Packages/**'     # use the pinned StyLua 2.0.2; newer versions reformat
```

selene can't fetch the Roblox API dump from the sandbox. For Blender work: `python3.11 -m venv v && v/bin/pip install bpy pillow`.

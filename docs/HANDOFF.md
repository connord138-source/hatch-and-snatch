# Session handoff: after the Juvenile and set-piece batch

Start a new session with **"read docs/HANDOFF.md and continue"**. Read `CLAUDE.md`
first: it holds the owner's preferences and the art-direction lessons, and they are
binding.

## How we work (owner's rules)

- Claude builds everything. The owner playtests through a separate Claude session on the PC ("the other chat").
- **Anything the PC session has to do goes to the owner as a paste-ready prompt.**
- Full permission for this project, including Higgsfield and Tripo spend. Report costs as you go.
- Repo `connord138-source/hatch-and-snatch`, branch **`claude/core-systems`**.

## State at handoff (2026-09-29)

### Done this session (pushed; the PC session hasn't imported or playtested it yet)

- **20 new Juvenile models:** every Common–Legendary species now has `<SpeciesId>_Juvenile` (23 of 41 including Mossmunk, Brambloar and Hivebadger). They're listed in `tools/assets_manifest.json` → `juveniles`.
- **12 biome set pieces**, in `src/server/SetPieces.luau`, wired in by `WorldService.buildZones` (the `heroes` list per zone):
  - HollowStump and a GlowcapRing of GiantGlowcaps in Mossvale.
  - TideArch and GiantClam in Coral Coast.
  - LavaVent and ObsidianSpikes in Magma Rift.
  - IceArch and FrozenBoulder in Frost Shelf.
  - LightningCrag and 2 WindSpires in Storm Peaks. The crag gets struck by lightning every 6–14 s.
  - MoonMonolith ×2 and CraterRim in Moonfall.
  - Each uses its GLB when imported (`WorldProps.<Name>`) and a part-built stand-in otherwise. Lights and particles are added either way.
  - GDD §7.3 lists them.
- **Rig fixes, found by auditing all 105 creature models headless with bpy:**
  - Tripo bodies come in 20–35° off-axis, so `rig_creature.py` now squares them up with PCA.
  - The head guess was wrong on 23 models, including **16 adults that ran tail-first**: Emberlynx, Coalby, Slagodon, Frostbun, Squallcoon, Novapanda, Nebulion, Lunaris, Grillgator, Bassdog, Pyrodrake, Solarion, Quasarfox, Nullcat, Mossmunk and Tidalotl.
  - The fixes are per-stage `"flip"` overrides in `bodyplans.json`: `front`, `frontBaby`, `frontJuvenile`.
  - `tools/blender/facing_check.py` draws colored side and top views for checking.
  - The PC session must **re-rig and re-import every creature** to get the fixes.
- **Pipeline:**
  - `tools/tripo.py` drives the Tripo API directly. `tools/tripo_jobs.json` records exactly what was made, and `tools/tripo_log.json` holds the task ids and credits.
  - GLBs are hosted permanently on Higgsfield file storage (`d2ol7oe51mr4n9.cloudfront.net`). See `docs/ASSETS.md`.

### Also still pending from before

The Luck Wheel, security upgrades, upper deck, zones, Release and Index photos (commit 47fa53e) still await the owner's playtest.

### Credits left

- **Tripo API: 65.** Enough for 2 textured models, kept as a buffer for redos after the playtest. 935 were spent on 20 Juveniles, 12 props and concepts.
- **Higgsfield: 0.25.** Needs a top-up for any `gpt_image_2_5` concepts (0.5 each at medium).

## Next steps

1. Wait for the owner's playtest notes: Juveniles, set-piece placement and size, facing after the re-rig, and the older features.
   - Fix what they report. Set-piece sizes are the `size` boxes in `SetPieces.luau`. Positions are the `heroes` angle and distance in `WorldService` (same layout as the harvest nodes: angle 0 = gate direction).
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

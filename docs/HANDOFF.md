# Session handoff: Juveniles + biome set pieces via direct Tripo API

Start a new session with: **"read docs/HANDOFF.md and continue"**. Read `CLAUDE.md`
first. It holds the owner's preferences and the art-direction lessons, and they
are binding.

## How we work (owner's rules)

- Claude builds everything. The owner playtests through a separate local PC
  Claude session ("the other chat").
- **Anything the PC session has to do goes to the owner as a paste-ready prompt.**
- The owner granted full permission for this project, including Higgsfield and
  Tripo spend, so don't keep asking. Report costs as you go.
- Repo: `connord138-source/hatch-and-snatch`, branch **`claude/core-systems`**.
  The PC session pulls this branch. If the new session starts in another repo,
  attach this one with `add_repo` (push access) and clone it.

## State at handoff (2026-09-29, commit 47fa53e)

Done and pushed; the PC session hasn't playtested it yet:
- the physical Luck Wheel;
- security upgrades;
- the upper deck at base level 4 and up;
- walled, level-gated biome zones with harvest nodes, Essence and shrines;
- Release for Essence;
- slow turntable rotation on pedestals;
- Index photos.

The owner has a pending PC-session prompt for playtesting all of this. Expect
screenshots or notes back.

## Tooling (re-download; the old session's scratchpad is gone)

Rojo 7, luau-lsp (plus `globalTypes.d.luau` from the luau-lsp repo) and StyLua,
from their GitHub releases. Check with:

```
stylua src --glob '!**/Packages/**'
rojo sourcemap default.project.json -o /tmp/sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=/tmp/sourcemap.json --ignore="**/Packages/**" src
```

## Credentials and network

- `TRIPO_API_KEY` is set in the environment (the owner has about 3000 Tripo
  credits). Never print it.
- `api.tripo3d.ai` is allowed, and the session has full internet access.
- Higgsfield has about 7 credits left. The owner may top it up.

## Task 1: the 38 missing Juvenile models

`tools/assets_manifest.json` → `juveniles` has only Mossmunk, Brambloar and
Hivebadger. Every other species in `src/shared/Config/Creatures.luau` (41 total)
needs `<SpeciesId>_Juvenile`. The code already uses them when present
(`CreatureService` picks `<SpeciesId>_Juvenile` for the Juvenile stage). The
pipeline (`fetch_assets.py` → `rig_all.py` → `organize_imports.luau`) already
handles the `juveniles` group.

Order: the players see Mossvale and Coral Coast most, so do them first, then
Magma, Frost, Storm, Moonfall and Junk.

### Step A: concept image (Higgsfield, or a cheaper route)

The proven recipe was `gpt_image_2`, quality high, 1k, 1:1, costing about 8–9
credits each. The reference media (`role: "image"`) is the species' **adult
source image**; its Higgsfield id is in `docs/ASSETS.md` under "Source images".
The prompt that worked:

> Using the creature from the reference image, create its JUVENILE (teenage) version as a single clean 3D character reference render: same species, same materials, colors and markings, but an adolescent: lanky proportions with slightly long legs, a head a little large for the body, a leaner body than the adult, and its signature features only half-grown (horns, antlers, crystals, plates, manes, tail clubs and glowing parts about half their adult size). Semi-realistic like the reference, not cartoon. Side three-quarter view, neutral stance with all four legs straight, clearly separated and slightly apart, mouth closed, no ground, plain flat light gray background, even neutral lighting, no particles, no text.

For low-slung bodies (Hivebadger needed this), name the actual feature (for
example "honeycomb plates about half their adult size") and add "belly held
above the ground with nothing hanging between the legs".

Cost savers to try before a big batch:
- a cheaper Higgsfield image model or a lower quality setting;
- whether Tripo's own API offers image generation or multiview-from-reference
  (check the Tripo docs).

Show the owner **one test Juvenile** from any new route before batching. The
art lessons in `CLAUDE.md` still apply: no cartoon eyes, no toy proportions, no
glossy "AI" look.

Higgsfield MCP quirks:
- Calls often time out at 60 s even though the job was submitted. Check
  `balance` and `show_generations` before retrying, so you don't pay twice.
- `gpt_image_2_5` no longer exists; use `gpt_image_2`.

### Step B: 3D model (Tripo API direct)

The old pipeline ran Tripo **through Higgsfield**
(`tripo_h3_1_image_to_3d`, `face_limit: 8000`, `texture: true`, `pbr: true`).
Match those settings on the direct API:
1. Upload the concept image, or pass its URL.
2. Create an `image_to_model` task.
3. Poll it.
4. Download the GLB.

Check the current Tripo API docs for the exact model-version name and cost per
task. Try `GET /v2/openapi/user/balance` first to confirm the key works.

### Step C: host the GLB and register it

Tripo's output URLs expire, and `assets/` is gitignored, so pick a durable
home:
- **Option 1:** re-host on Higgsfield's CDN (`media_import_url` /
  `media_upload`), like every other asset. The manifest entries are
  `d8j0ntlcm91z4.cloudfront.net` URLs.
- **Option 2:** commit the GLBs, which are small at 8000 faces, to e.g.
  `tools/glb/juveniles/`, and teach `fetch_assets.py` to copy repo-relative
  paths as well as URLs.

Then:
1. Add each entry to `tools/assets_manifest.json` → `juveniles`.
2. Add a line to `docs/ASSETS.md` with the concept-image id.
3. Commit and push.
4. Give the owner a PC-session prompt:
   - `python tools/fetch_assets.py`;
   - `rig_all.py` (Juveniles need the rig);
   - import the new FBX files from `assets/fbx/`;
   - run `organize_imports.luau` in the Command Bar;
   - save;
   - check the Juveniles at Juvenile stage, using the Studio hook
     `game.ServerStorage.StudioDebug:Invoke("grant", "<Species>", "Normal", "Juvenile")`.

## Task 2: biome set pieces (after the Juveniles)

The zones are 88-stud walled circles (`WorldService.buildZones`, `ZONES`
table). Each has a `decor` list of WorldProps names plus a height table in the
decor loop. Storm Peaks and Moonfall look sparse. Add 2–3 hero props per biome:

| Biome | Hero props |
|---|---|
| Mossvale | giant hollow stump, glowcap ring |
| Coral Coast | tide-pool rock arch, giant clam |
| Magma Rift | lava vent, obsidian spikes |
| Frost Shelf | ice arch, frozen boulder |
| Storm Peaks | lightning-rod crag, wind-bent rock spire |
| Moonfall | moon-crystal monolith, crater rim |

These are props (GLB, no rig):
1. Add them to the manifest's `props` group.
2. Add them to that biome's `decor` list.
3. Give them a sensible height in the decor loop.
4. Keep them clear of nodes, the shrine and the gate path. The loop already
   does this.

## Afterwards

- Update `docs/GDD.md` and `CLAUDE.md` if anything about the design changes.
- Always finish with a paste-ready PC-session prompt for the owner.

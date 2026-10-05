# 3D Assets: import guide

Every model the game uses is listed in **`tools/assets_manifest.json`**, which maps each name to its GLB link:

- **creatures:** all 41 species (adults), from clean neutral-pose model sheets.
- **babies:** `<SpeciesId>_Baby` models with baby proportions: big head, big eyes, stubby legs.
- **juveniles:** `<SpeciesId>_Juvenile` teenage models, all 41. (A species without one would use its adult model at the Juvenile stage.)
- **eggs:** one per biome, plus `Egg`, the generic fallback that gets tinted.
- **props:** the reactor, pedestal, nursery nest, incubator, cash pad, lock button, entrance arch, lamp post, 8 kinds of decor, and 12 biome-zone set pieces (`src/server/SetPieces.luau`).

The code runs without any of them: each piece falls back to a plain block until its model is imported.

## One-time setup (owner's PC)

Needs Python 3 and Blender 4.x (free from blender.org). You never have to open Blender.

```
git pull
python tools/fetch_assets.py
python tools/blender/rig_all.py "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

1. `fetch_assets.py` downloads everything into `assets/`: `glb/` for creatures and babies, `eggs/` and `props/`. It skips files you already have.
2. `rig_all.py` turns every creature GLB into a skinned FBX in `assets/fbx/`, with bones named for the procedural run animation.

## Import into Studio

1. **File → Import 3D**, select **all** files in `assets/fbx/` (creatures and babies, rigged), then **Import All**. Keep textures on and rig/skinning on.
2. Do the same for all files in `assets/eggs/` and `assets/props/` (GLB, no rig).
3. Open **View → Command Bar**, paste the contents of `tools/studio/organize_imports.luau` and press Enter. It moves every imported model into the folder the code reads and sets its PrimaryPart:
   - `ReplicatedStorage.CreatureModels`
   - `ReplicatedStorage.EggModels`
   - `ReplicatedStorage.WorldProps`
4. **Save the place** (Ctrl+S). Rojo doesn't manage these folders; they live in the place file.

Don't scale or position anything; the code does it:

| Model | What the code does |
|---|---|
| Creatures | Scaled to 7 studs at the longest side, then by stage. Babies use `<SpeciesId>_Baby` when it exists. Stands on the pedestal. |
| Eggs | 3.4 studs tall on the conveyor, and 2.4 studs inside incubators. Biome models are untinted; the generic `Egg` is tinted per biome. |
| Props | `Props.luau` fits each prop over its placeholder part, and that part keeps collision, prompts and labels. Decor is scattered deterministically around the island, keeping plots clear. |

## Check in Studio

- **Updating models:** `fetch_assets.py` re-downloads any model whose link changed in the manifest (it remembers links in `assets/.sources.json`), and `rig_all.py` re-rigs only models that changed (`assets/fbx/.rigged.json`; `--all` re-rigs everything). Re-import just the changed FBXs and rerun the organizer.
- **Facing:** `rig_creature.py` squares each body up and guesses the head end. A raised tail club, tuft or swirl can fool the guess.
  - The fix is `"flip"` in `tools/blender/bodyplans.json`, under `front` (adult), `frontBaby` or `frontJuvenile`. Each GLB has its own orientation, so a species can need it for one stage only.
  - Then rerun `rig_all.py` and re-import that model. Re-running the organizer replaces the old copy.
  - All 105 current models were checked with `tools/blender/facing_check.py` (2026-09-29) and 23 carry a flip.
- **Legs:** if they bend the wrong way, flip `pitch` in `src/client/Controllers/CreatureAnimator.luau`.
- **Stringing** (mesh stretched into strings at a leg or tail when it moves): rig v2 (2026-10-01) smooths the skin weights along the surface (16 passes, seam vertices welded, loose tufts moved as one piece). Over all 123 models, posed like the run and the sit, stretched edges fell 60% (Mossmunk 88%), and feet stay on their lower-leg bones. `rig_all.py` re-rigs everything when `RIG_VERSION` changes, so re-import every FBX after that. Rig v3 (2026-10-03) fixed the rest: feet found as whole ground patches (not mid-box quadrants), a harmonic leg-to-body hand-over at the hip, front and hind legs never sharing a vertex, and a smarter 4-influence cap; the string score over all 123 models fell from 332 to 30. Re-run `rig_all.py` and re-import every FBX.
- **Props:** a prop that sits sideways was modeled lying down. Rotate the imported model once in WorldProps and save.

## What the code does with them

- **Finishes** (Gold, Chrome, Diamond and so on) remove the texture and apply a solid material. Normal creatures keep their texture.
- **Movement:** every creature does the bounding hop. Rigged models also get a procedural gait on their bones: front legs together, back legs together, spine flex, head bob and tail sway.
- **Incubators** show the actual biome egg inside and glow in the rarity color for Epic and up, brighter as the egg nears hatching.
- **Lamp posts** ring the conveyor and cast warm light.

## Source images (Higgsfield job ids, for redoing a model)

The clean model sheets are the inputs to 3D conversion; the concepts live in `docs/ROSTER.md`.

Coalby `10b3feba` · Slagodon `5ee493de` · Calderhorn `60b03d4a` · Frostbun `beefdb56` · Iceadillo `3303a3df` · Glacibear `156595d1` · Thunderhoof `d2b538bf` · Stormback `0c32ad0d` · Zapybara `884081b3` · Squallcoon `2be71438` · Novapanda `895649ff` · Aurorox `391b8e5f` · Nebulion `3c60398c` · Eclipsaur `354c7dcd` · Lunaris `56bb5605` · Toastoise `ebca2a80` · Fridgehog `7b3d2abd` · Grillgator `601bc9ee` · Laundrophant `481c5dc5` · Lawnmoose `3ca7e661` · Bassdog `9037075f` · Sylvanox `f76b8118` · Capybaron `900b0601` · Lurehound `653e9600` · Pyrodrake `032bb7ca` · Glacierion `b66f0133` · Stormgriff `3c9f0e00` · Solarion `8a78bbea` · Halosaur `4f6e5272` · Quasarfox `97af6d05` · Singularis `17da7fed` · Nullcat `c42f59d0` · Mossmunk `b802fc40` · Brambloar `6f4a7dcd` · Hivebadger `85dfad83` · Geodeer `c895f9df` · Kelpotter `82e8804d` · Clamodon `80c50911` · Coralope `7a51097c` · Tidalotl `c06063d0` · Emberlynx `3532202e`

Eggs: Mossvale `af112e5a` · CoralCoast `488cbccd` · MagmaRift `8a701ed4` · FrostShelf `0fd1769f` · StormPeaks `80ef524a` · Moonfall `2de9fcf5` · Junk `5e1e5007` · generic `4d87f13c`

Props: HatcheryReactor `db53ee3f` · Pedestal `7b096c76` · NurseryNest `21cba2fc` · Incubator `1ebc1fa1` · Collector `3a4cc5c1` · LockButton `c60f5654` · MossTree `0b1bd165` · RockCluster `bd80a0a6` · BerryBush `11e81571` · MushroomCluster `eb6dca66` · CrystalCluster `e85b0179` · CoralCluster `0afaa00a` · LavaRock `fd86cb46` · IceSpire `ad45e3f7` · LampPost `b6587dec` · PlotArch `052389a8`

Babies: Coalby `7abeb627` · Slagodon `3ffbc4f3` · Calderhorn `61aca522` · Frostbun `c4749f76` · Iceadillo `db43148d` · Glacibear `ba2a9b09` · Thunderhoof `73cf0a99` · Stormback `6e9a2bc4` · Zapybara `a314e838` · Squallcoon `872118cf` · Novapanda `2daea7d9` · Aurorox `0b76f3e8` · Nebulion `17c986a4` · Eclipsaur `0c330293` · Lunaris `7470fb96` · Toastoise `36b6ae87` · Fridgehog `7e4ce7ae` · Grillgator `8fbaeb38` · Laundrophant `46c63a89` · Lawnmoose `95a927f9` · Bassdog `eb19b4f3` · Sylvanox `05ce04a8` · Capybaron `c1cc59f2` · Lurehound `62b0d230` · Pyrodrake `8cea3e74` · Glacierion `fc387bb9` · Stormgriff `590a60b4` · Solarion `000dade1` · Halosaur `0fbd8eb1` · Quasarfox `e3edc364` · Singularis `eefab87c` · Nullcat `15f75539` · Mossmunk `10ee1c9e` · Brambloar `84f64a2a` · Hivebadger `68692fe7` · Geodeer `06fae8cf` · Kelpotter `938c79f2` · Clamodon `e5700f54` · Coralope `05831810` · Tidalotl `b7d85d3d` · Emberlynx `183d9421`

Juveniles (concept image the model was made from; plain ids are Higgsfield jobs, "upload" ids are Higgsfield media uploads of Tripo-made concepts). Mossmunk, Brambloar and Hivebadger came from the earlier Higgsfield run:

Geodeer 4bc5f9d8 · Kelpotter 9566053c · Clamodon upload 6c03ed64 · Coralope dace4571 · Tidalotl 190415ee · Coalby 0fb94bd1 · Slagodon upload a6305212 · Emberlynx f6f5a5ad · Calderhorn f1eb251b · Frostbun 5a9a6268 · Iceadillo upload e4f1f7a0 · Glacibear upload 517cce74 · Aurorox upload 91808e49 · Zapybara upload df2ab93f · Squallcoon upload c165890a · Thunderhoof upload 0ec39d1e · Stormback upload 9f02c823 · Novapanda upload 332293a2 · Nebulion upload 72f8d24b · Eclipsaur upload 52077973 · Toastoise upload d0d68ca8 · Fridgehog upload ffe908cf

Ultra-rare and Junk Juveniles (2026-09-30). The concepts came from `tools/tripo_jobs_juveniles2.json` (Nano Banana; the six `_v2` redos used Nano Banana Pro because the first try looked too much like the adult). The Junk ones read younger through a smaller appliance: a 2-slice toaster, a mini-fridge, a hibachi grill and so on. The GLBs are hosted as Higgsfield files (media ids): Sylvanox `9fc7efbe` · Lurehound `674d9567` · Pyrodrake `ae720d7b` · Glacierion `804b3be5` · Stormgriff `315efa15` · Lunaris `60ae1486` · Solarion `4b0d65a3` · Halosaur `26d074a0` · Quasarfox `f71738f1` · Singularis `1d2271d2` · Capybaron `25730091` · Nullcat `0a829d51` · Toastoise `45821c28` · Fridgehog `3d1c66f0` · Grillgator `c1e0a2d8` · Laundrophant `8f88c736` · Lawnmoose `b8f69588` · Bassdog `0451c1db`

Set pieces (Tripo text_to_model task ids; the prompts are in `tools/tripo_jobs.json`):

HollowStump ef9b172f · GiantGlowcap 3d45884a · TideArch 78dfeb40 · GiantClam e8fe8626 · LavaVent 49b02563 · ObsidianSpikes 304be4df · IceArch f3a42c70 · FrozenBoulder 893575e2 · LightningCrag f753db9f · WindSpire c9c95566 · MoonMonolith 07760467 · CraterRim 04f67810

## Making new models (direct Tripo API)

`tools/tripo.py` runs Tripo tasks from a jobs file, downloads the results into `assets/tripo/` and logs every task in `tools/tripo_log.json`, skipping jobs that already succeeded:

    python tools/tripo.py balance
    python tools/tripo.py run jobs.json --dry

Settings match the old Higgsfield route: v3.1, 8000 faces, standard texture with PBR. Tripo's download links expire within minutes, so host each GLB on Higgsfield file storage (`media_upload` → PUT → `media_confirm` with type `file`) before adding its permanent URL to the manifest.

Ultra-rare rework (2026-10-01, Tripo direct; jobs in `tools/tripo_jobs_ultrarework.json`). These 18 models replaced the earlier ones: Glacierion, Lurehound, Solarion, Quasarfox and Nullcat (all three stages), the Capybaron Baby and Juvenile, and the Halosaur adult. All were rigged and facing-checked in the sandbox; Solarion (adult) and Nullcat (adult and Juvenile) needed `"flip"`.

## Fortress, base and island props (2026-10-01)

40 props from the Tripo API (text-to-3D, or a clean concept sheet then image-to-3D for the towers and gatehouses), hosted on Higgsfield file storage and listed under `props` in `tools/assets_manifest.json`. Every one has a part-built stand-in in code, so nothing breaks before they're imported.

| Group | Props | Used by |
|---|---|---|
| Fortress kit | WatchtowerWood, TowerStone, TowerRoofed, TowerCitadel, GatehouseStone, GatehouseCitadel, Brazier | `Fortress.luau`: towers fit to the tower's height (an invisible column keeps it solid); gatehouses fit by width with a 9-stud arch between invisible colliders |
| Base | BaseTerminal, BuyPad, HideHaystack, HideBarrels, HideHedge, HideChest, SpikeStrip, NetBallista, SearchlightTower, AlarmBell | `BaseKit.luau` (BuyPad isn't placed yet; the pads are part-built rings) |
| Decor | CampSupplies, WallTorch, Campfire, FlowerPlanter, TrainingDummy, StoneWell, Fountain | `BaseDecor.luau` |
| Open land | Lighthouse, Windmill, RuinsArch, StoneCircle, WaterfallCliff, CampTents, Shipwreck, PalmTree, Signpost, WoodBridge, OakTree, FishingHut, Dock, MarketStall, FlowerMeadow, Boulders | `Landmarks.luau` (Dock isn't placed: the walkable pier is part-built) |
| Castle theme kits | CoralShellSpire, CoralBranches, CoralFan, CoralTubes, CoralClamBrazier, CoralAnemoneRock, CoralStarfishPlaque, CoralPearlLantern, CoralStaghorn, CoralStarfish, CoralScallop, CoralConch, FireSpire, FireObsidianSpikes, FireSkullBrazier, FireLavaRock, FireDragonGate, IceCrystalSpire, IceCrystalCluster, IceLantern, IceGateArch, SnowDrift, StormTeslaSpire, StormThunderStone, StormPlasmaBrazier, StormLightningRod, StormCloud, MossMushrooms, MossMushroomLantern, MossRoots, MossGiantTree, MoonFinial, MoonCrystal, MoonLantern, MoonGateArch, MoonBigCrescent, GoldSpire, GoldLion, GoldBrazier, GoldCrownCrest, DiamondCrown, DiamondCluster, DiamondLantern, DiamondGateCrest, VoidShards, VoidCrystals, VoidBrazier, VoidPortal, VoidRunePillar; variations and keep interiors (2026-10-02): CoralGiantClam, CoralOyster, CoralBrain, CoralAnemone, CoralUrchins, CoralBarnacleRock, MossGlowCap, MossShelfLog, MossFern, MossFlowers, FireMagmaCrystals, FireCauldron, FireDragonSkull, IceSnowPine, IceShards, IceBrazier, StormCrystals, StormCoil, StormThunderRock, MoonShard, MoonFlower, MoonLampPost, GoldUrn, GoldCoins, GoldChest, DiamondGems, DiamondGeode, DiamondChandelier, VoidEyeOrb, VoidThornTree, VoidObelisk | `CastleKits.luau` (the Castle Designer's Theme slot) |

- The gatehouses were redrawn with open archways (the first drafts had closed gates), and the Citadel one wide, with a tower at each end, so its arch spans the gate.
- **Facing:** the landmarks and fixtures face the hub (or the way the code says) along the model's -Z. A model that comes in turned, or lying down, gets rotated once in WorldProps and saved, as for the earlier props.
- **Castle theme kits** (2026-10-02, Tripo direct: prop sheets cut from the approved theme concepts with `tools/crop_sheet.py`, then image_to_model; jobs in `tools/tripo_jobs_castle_kits*.json`). The kit coral and ice cap are `CoralBranches` and `IceCrystalSpire`, because `CoralCluster` and `IceSpire` are already zone props. Flat pieces (crests, plaque, crescent, portal) turn their broad side out in code, and the lion, dragon head, skull brazier and starfish plaque carry a fixed turn in `CastleKits.TURN`, measured on the GLBs knowing Studio imports a GLB half round (the waterfall cliff). `organize_imports.luau` drops their metalness maps (metal reflected the night sky: the shell spires went navy, the gold spires near-black). The glowing mushrooms and moon crystals turn to neon in code (`CastleKits.NEON`), as a SurfaceAppearance can't glow. The coral, starfish and shells are tinted per piece through `SurfaceAppearance.Color`, so they ship pale (the clams, oyster, urchins and barnacle rock keep their own colors: `CastleKits.NATURAL`); the variation pieces came from one 2×2 sheet per theme (`tools/tripo_jobs_castle_kits5*.json`); the starfish GLB was squared flat in Blender (Tripo kept the sheet's three-quarter tilt).
- **Mutation skins** (not in the manifest; made on the PC): `python tools/mutations/run_all.py` bakes every creature GLB, makes its five skins with the eyes in `tools/mutations/eyes.json` and packs them into `assets/skins/glb/<Model>_Skins.glb` (about 1 MB each, about 2 minutes per model). Import those, then run `tools/studio/organize_skins.luau`, which files them under `ReplicatedStorage.MutationSkins`. Eye picks for a new model: `python3 tools/mutations/eye_sheets.py <maps dir> <out>` makes gridded face sheets, `--qa tools/mutations/eyes.json` draws the picks to check them.
  - **Screen before uploading (required since a skin got the owner's account suspended, 2026-10-03):** `pip install numpy scipy pillow torch transformers`, then `python tools/mutations/screen_skins.py assets/skins --move-flagged assets/skins_flagged`, re-pack what it prints, then `python tools/mutations/screen_skins.py assets/skins/glb --move-flagged assets/skins_flagged` (the gate: it reads the exact JPEG bytes that get uploaded) and repeat until it says "none flagged" and exits 0. Exit 2 means the classifier couldn't run, which never clears an upload. Import only `assets/skins/glb` after that, and delete the old `ReplicatedStorage.MutationSkins` first. The first run downloads a ~350 MB classifier from Hugging Face.
- **Castle textures** (2026-10-02; not models): a Castle Designer stone can wear a custom material, a MaterialVariant listed in `src/shared/Config/Materials.luau` (the Diamond stone's `DiamondStone`). `python tools/textures/make_diamond_tex.py` makes its tileable color, normal and roughness maps in `assets/textures/` (1024², seamless; the previews land there untracked). Import the three in Studio's Asset Manager, copy their ids (right-click → Copy ▸ → Copy ID) into `Materials.luau`, then run `tools/studio/make_materials.luau` in the Command Bar in edit mode and save the place: only plugins and the Command Bar can set a variant's maps, so the variants live in the place file.

## Sound pack (2026-10-05)

Every game sound is synthesized by `tools/audio/make_sfx.py` (numpy, scipy, soundfile) into ONE file, `assets/audio/hatch_sfx.ogg`: the stinger for each rarity, then the Legendary+ sequence (Riser, Heartbeat, Impact), the reel's Whoosh and Tick, Mutation and Shine. The script rewrites the regions block in `src/shared/Config/Sounds.luau`; the game plays each sound's stretch with `Sound.PlaybackRegion` (`src/client/Sfx.luau`), so the whole pack is a single upload.

To ship it: Creator Hub → Creations → Development Items → Audio → Upload Asset, pick `hatch_sfx.ogg` (one upload, well inside the monthly audio quota), wait for it to be approved, then paste its id into `Config/Sounds.luau` `id` and commit. While the id is 0 the game plays pitched pings instead. If the sounds change, rerun the script and upload the new file (a new id).


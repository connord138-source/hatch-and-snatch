# 3D Assets: import guide

Every model the game uses is listed in **`tools/assets_manifest.json`**, which maps each name to its GLB link:

- **creatures:** all 41 species (adults), from clean neutral-pose model sheets.
- **babies:** `<SpeciesId>_Baby` models with baby proportions: big head, big eyes, stubby legs.
- **eggs:** one per biome, plus `Egg`, the generic fallback that gets tinted.
- **props:** the reactor, pedestal, nursery nest, incubator, cash pad, lock button, entrance arch, lamp post and 8 kinds of decor.

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

- **Facing:** a creature that walks backwards needs its `"front"` set in `tools/blender/bodyplans.json` (`+x`, `-x`, `+y`, `-y`); then rerun `rig_all.py` and re-import that one. Re-running the organizer replaces the old copy.
- **Legs:** if they bend the wrong way, flip `pitch` in `src/client/Controllers/CreatureAnimator.luau`.
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

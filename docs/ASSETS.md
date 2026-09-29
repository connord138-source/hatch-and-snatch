# 3D Assets: import guide

The concept art in docs/ROSTER.md is **2D only**. These are the real 3D models (GLB files,
converted with Tripo H3.1 at 8k faces or fewer, with textures). Anything without a model here
still shows as a placeholder block in-game.

## Ready to import

| Model | Import as | GLB |
|---|---|---|
| Emberlynx | `ReplicatedStorage.CreatureModels.Emberlynx` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260927_203854_d7458a22-a7fe-4158-af1c-e068152c61f6.glb |
| Mossmunk | `ReplicatedStorage.CreatureModels.Mossmunk` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005715_d97e8ad1-5097-468d-bfef-eecd1671b579.glb |
| Brambloar | `ReplicatedStorage.CreatureModels.Brambloar` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005717_bb14f3eb-1d21-4ae4-b224-d3e872969f64.glb |
| Hivebadger | `ReplicatedStorage.CreatureModels.Hivebadger` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005719_2c8deaec-a60b-4234-bbae-7df80f441d72.glb |
| Geodeer | `ReplicatedStorage.CreatureModels.Geodeer` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005722_14399bf9-3e49-465f-acc0-9adcbfb3d61f.glb |
| Kelpotter | `ReplicatedStorage.CreatureModels.Kelpotter` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005725_55dcbe93-6324-493c-8f81-8a2e160a1f93.glb |
| Clamodon | `ReplicatedStorage.CreatureModels.Clamodon` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005727_abb5c54c-ec0d-4a90-98f5-1d334538f1c4.glb |
| Coralope | `ReplicatedStorage.CreatureModels.Coralope` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005729_dfb9cb94-59a5-40f1-9e4b-2a88b7f5783c.glb |
| Tidalotl | `ReplicatedStorage.CreatureModels.Tidalotl` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005731_fda88a91-92e5-4239-9c68-e87c8551af39.glb |
| Mossvale egg (bark and moss) | `ReplicatedStorage.EggModels.Mossvale` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_030242_269e9439-fcc0-410b-a90f-275a33a46288.glb |
| Coral Coast egg (seashell and coral) | `ReplicatedStorage.EggModels.CoralCoast` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_030245_3202159f-8157-46a3-8b86-eb362b7ab1d7.glb |
| Egg (generic fallback, tinted per biome in code) | `ReplicatedStorage.EggModels.Egg` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005812_193e47b8-a68d-489c-9268-d7c7ec579c31.glb |

That covers the soft-launch biomes (Mossvale and Coral Coast) plus Emberlynx. The remaining 21
creatures still need converting (about 9 Higgsfield credits each).

## How to import (Studio)

1. Download the GLB files, for example into `assets/glb/` in the repo. That folder is gitignored.
2. In Studio, go to **File → Import 3D** and pick the GLB.
   - In the importer, keep **textures** on.
   - Make sure it imports as a **Model**.
3. In **ReplicatedStorage**, create a Folder named `CreatureModels` (and one named `EggModels` for the egg).
4. Move the imported Model into that folder and **rename it exactly** to the species id, e.g. `Mossmunk`. For eggs, use the biome id (`Mossvale`, `CoralCoast`) or `Egg` for the generic fallback.
5. Set the Model's **PrimaryPart** to its main MeshPart.
6. Check that it faces **-Z**, which is the model's front in Studio. If it's turned sideways, rotate the whole model 90° before saving.
7. Don't scale or position anything; the code handles it:
   - CreatureService scales each creature to 7 studs at its longest side, then applies the Baby, Juvenile or Adult size, and stands it on the pedestal.
   - EggService scales the egg to 3.4 studs tall. It uses `EggModels.<BiomeId>` when one exists, untinted. Otherwise it falls back to the generic `Egg`, tinted per biome.
8. **Save the place** (Ctrl+S). Rojo doesn't manage `CreatureModels` or `EggModels`, so the models live in the place file.

## What the code does with them

- **Finishes** (Gold, Chrome, Diamond and so on) remove the texture and apply a solid material, giving the finish-sheet look. Normal creatures keep their texture.
- **Glow:** Moonfall and Junk eggs get a point light.
- **Movement:** every creature does the bounding hop. Rigged models (below) also get a procedural gait from CreatureAnimator: front legs together, back legs together, spine flex, head bob and tail sway. It drives the bone names the rig script creates, so no animation uploads are needed.
- **Incubators** glow in the rarity color for Epic and up, brighter as the egg nears hatching.

## Rigging in Blender (automatic)

Needs Blender 4.x (free, blender.org). Everything runs headless; you never need to open Blender.

1. Save each creature GLB as `assets/glb/<SpeciesId>.glb`, e.g. `assets/glb/Emberlynx.glb`.
2. From the repo root, run:
   ```
   python tools/blender/rig_all.py "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
   ```
   It writes `assets/fbx/<SpeciesId>.fbx`, a skinned mesh with the skeleton Root > Hips > Spine > Chest > Neck > Head, Tail1-3 and a two-bone leg per foot.
3. In Studio, import the **FBX** (File → Import 3D) instead of the GLB and follow the same steps as above. Keep "Rig" / skinned mesh import on.
4. If a creature walks backwards, set its `"front"` in `tools/blender/bodyplans.json` to `+x`, `-x`, `+y` or `-y` and rerun that one:
   ```
   blender --background --python tools/blender/rig_creature.py -- assets/glb/X.glb assets/fbx/X.fbx <bodyPlan> <front>
   ```
5. The weights are automatic, so check each model in Studio. If legs bend in the wrong direction, the leg axis in `CreatureAnimator.luau` (`pitch`) can be flipped.

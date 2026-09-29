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
| Egg (shared by all biomes; tinted in code) | `ReplicatedStorage.EggModels.Egg` | https://d8j0ntlcm91z4.cloudfront.net/user_3064wa0TplLG2iNgb80G3unfKiu/hf_20260929_005812_193e47b8-a68d-489c-9268-d7c7ec579c31.glb |

That covers the soft-launch biomes (Mossvale and Coral Coast) plus Emberlynx. The remaining 21
creatures still need converting (about 9 Higgsfield credits each).

## How to import (Studio)

1. Download the GLB files, for example into `assets/glb/` in the repo. That folder is gitignored.
2. In Studio, go to **File → Import 3D** and pick the GLB.
   - In the importer, keep **textures** on.
   - Make sure it imports as a **Model**.
3. In **ReplicatedStorage**, create a Folder named `CreatureModels` (and one named `EggModels` for the egg).
4. Move the imported Model into that folder and **rename it exactly** to the species id, e.g. `Mossmunk`, or `Egg` for the egg.
5. Set the Model's **PrimaryPart** to its main MeshPart.
6. Check that it faces **-Z**, which is the model's front in Studio. If it's turned sideways, rotate the whole model 90° before saving.
7. Don't scale or position anything; the code handles it:
   - CreatureService scales each creature to 7 studs at its longest side, then applies the Baby, Juvenile or Adult size, and stands it on the pedestal.
   - EggService scales the egg to 3.4 studs tall and tints it per biome.
8. **Save the place** (Ctrl+S). Rojo doesn't manage `CreatureModels` or `EggModels`, so the models live in the place file.

## What the code does with them

- **Finishes** (Gold, Chrome, Diamond and so on) remove the texture and apply a solid material, giving the finish-sheet look. Normal creatures keep their texture.
- **Glow:** Moonfall and Junk eggs get a point light.
- **Movement:** creatures still use the placeholder bouncing motion. Real animation needs the model split into jointed parts or rigged in Blender, which is the next art step (see docs/GDD.md §10).

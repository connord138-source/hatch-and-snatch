# Store page (Creator Hub → the experience → Places/Configure)

The files to upload are in `marketing/`. Rebuild them with `python3 tools/marketing/compose.py`; the sources are listed below.

## Icon

`marketing/icon_512.png` (512×512): the baby Emberlynx hatching from a glowing cracked egg on a blue burst. It's rendered in Blender from the game's own 3D model, because the owner felt the image-model icons looked AI (2026-10-01).
- Alternatives: `icon_512_snatch.png` (a thief's glove reaching in; the glove still reads weakly) and `icon_512_tidalotl.png`.
- No text on the icon, because the game name shows under it and text is unreadable at list size.
- Rebuild: render the 3D layer with `EGL_PLATFORM=surfaceless <bpy python> tools/marketing/render_icon.py -- <creature.glb> assets/icon_src/renders/<name>.png <snatch|hatch>`, then run `python3 tools/marketing/compose.py icons` for the burst, glow, outline and sparkles. The creature GLBs come from `tools/assets_manifest.json`. Eevee needs `libegl1` and Mesa in the sandbox.
- Roblox can A/B test icons once the game has traffic.

## Thumbnails (1920×1080, in this order)

1. `thumb_1_steal.jpg`: logo plus "STEAL THEIR RAREST!", a player sprinting off with a giant Tidalotl while the owner chases. This is the lead image and says what the game is.
2. `thumb_2_hatch.jpg`: "HATCH A 1 IN 10,000!", a Cosmic creature bursting from an incubator.
3. `thumb_3_collect.jpg`: "COLLECT 41 CREATURES / 7 SHINY FINISHES", the finish lineup.
4. `thumb_4_moon.jpg`: "MOON EVENTS!", the cracked Moon Egg turning red.

Tips:
- Roblox rotates thumbnails, and the first one is also the default share image.
- Once the game has traffic, A/B test the lead thumbnail with Creator Hub's thumbnail personalization.

## Title

`Hatch & Snatch 🥚` at launch. During events, put a tag in front, for example `[🌕 BLOOD MOON] Hatch & Snatch`. Tags like that lift click-through; change them with each update.

## Description (paste as is)

976 characters, under Roblox's 1,000 limit. Rewritten 2026-10-01 (owner: the first version read as AI): concrete moments from a session instead of a feature list.

```
Every egg on the conveyor could hatch a 1 in 50,000 Secret. Raise it, show it off, and keep it safe, because everyone in your server wants it. 🥚

🆕 FLOORS & VAULTS: put your rarest on the top floor and lock it in a vault when a thief walks in.

🐣 Grab eggs off the hatchery belt, carry them home and watch the incubator glow. Every hatch rolls a species, a shiny finish and a mutation.
🐾 Babies grow into Juveniles and Adults. Bigger creatures earn more, but they're harder to protect.
🏃 Sneak into other bases and run off with their creatures. Adults slow you to half speed, so the owner can knock them loose.
🔒 Lock your laser gate, set alarms and tripwires, and guard your nursery.
🌋 41 creatures across 6 biomes: a magma lynx, a black-hole tortoise, a toaster that thinks it's a turtle...
🌕 When the Moon Egg turns red, gold, void or prism, the odds change for the whole server.

🎁 Free codes: HATCH · MOONEGG · SNATCH (Shop → Free rewards)
👍 Like the game for more codes!
```

Keep the first line punchy, because only the first ~150 characters show in search and on mobile.

## Sources

- Icon: Blender render of the baby Emberlynx and Tidalotl models (`tools/marketing/render_icon.py`).
- Thumbnails 1–3 are Higgsfield drafts (see `docs/ROSTER.md` → Store art): `0a0bc141`, `c826ccbe`, `a95a62f6`, `1ccbf410`.
- Logo and thumbnail 4 were made with the Tripo API (`tools/tripo_jobs_marketing.json`, Nano Banana Pro, 10 credits each); the outputs are in `assets/tripo/marketing/`.
- Fonts: Luckiest Guy (Apache 2.0), Lilita One and Titan One (SIL OFL). The license files are in `tools/marketing/fonts/`.

# Store page (Creator Hub → the experience → Places/Configure)

The files to upload are in `marketing/`. Rebuild them with `python3 tools/marketing/compose.py`; the sources are listed below.

## Icon

`marketing/icon_512.png` (512×512): a baby Emberlynx bursting out of a glowing egg while a thief's hand reaches in. It carries no text, because the game name shows under the icon and text is unreadable at list size.

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

```
🥚 Hatch creatures from the conveyor, raise them from baby to adult, and build the richest base on Crackpoint Island... then SNATCH the rarest creatures from everyone else! 🏃‍♂️💨

🐾 41 creatures across 6 biomes, from a magma lynx to a coral axolotl
✨ Rare finishes: Gold, Chrome, Diamond, Molten, Galaxy, Prismatic and Blood Moon
🌕 Moon events: Blood, Gold, Void and Prism moons change everything for 10 minutes
🔒 Lock your base, set tripwires and alarms, and guard your nursery
🎡 Spin the Luck Wheel and chase 1 in 50,000 Secrets
🌋 Explore biome zones for Essence, shrines and wild set-piece events

👍 Like the game! New codes drop at like goals.
🎁 Codes: HATCH · MOONEGG · SNATCH (Shop → Free rewards)
```

Keep the first line punchy, because only the first ~150 characters show in search and on mobile.

## Sources

- Icon and thumbnails 1–3 are Higgsfield drafts (see `docs/ROSTER.md` → Store art): `0a0bc141`, `c826ccbe`, `a95a62f6`, `1ccbf410`.
- Logo and thumbnail 4 were made with the Tripo API (`tools/tripo_jobs_marketing.json`, Nano Banana Pro, 10 credits each); the outputs are in `assets/tripo/marketing/`.
- Fonts: Luckiest Guy (Apache 2.0), Lilita One and Titan One (SIL OFL). The license files are in `tools/marketing/fonts/`.

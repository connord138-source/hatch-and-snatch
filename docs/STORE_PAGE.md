# Store page (Creator Hub → the experience → Places/Configure)

The files to upload are in `marketing/`. Rebuild them with `python3 tools/marketing/compose.py`; the sources are listed below.

## Icon

`marketing/icon_512.png` (512×512): a young Emberlynx snarls out of a cracked golden egg while a thief's gloved hand reaches in. It has realistic eyes, per the art direction.
- `icon_512_alt.png` is the runner-up: the first draft's cute kitten, with its cartoon eyes fixed.
- Neither carries text, because the game name shows under the icon and text is unreadable at list size.
- Roblox can A/B test icons once the game has traffic.

## Thumbnails (1920×1080, in this order)

1. `thumb_1_steal.jpg`: logo plus "STEAL THEIR RAREST!", a player sprinting off with a giant Tidalotl while the owner chases. This is the lead image and says what the game is.
2. `thumb_2_hatch.jpg`: "HATCH A COSMIC!", a Cosmic creature bursting from an incubator (was "1 IN 10,000" before the 2026-10-03 odds change).
3. `thumb_3_collect.jpg`: "COLLECT 41 CREATURES / 7 SHINY FINISHES", the finish lineup.
4. `thumb_4_moon.jpg`: "MOON EVENTS!", the cracked Moon Egg turning red.
5. `thumb_5_fortress.jpg`: "BUILD YOUR FORTRESS! / 3 FLOORS · 4 VAULTS", the three-story base from above.
6. `thumb_6_vault.jpg`: "LOCK THE VAULT!", a Sylvanox behind a glowing vault door.
7. `thumb_7_reveal.jpg`: "1 IN 20,000 SECRET! / WATCH THE REEL SPIN", the hatch reveal landing on Capybaron.
8. `thumb_8_lineup.jpg`: "SHOW OFF YOUR RAREST!", rarity halos and stardust at night.
9. `thumb_9_biome.jpg`: "EXPLORE 6 BIOMES! / ERUPTIONS · METEORS · LIGHTNING", the Magma Rift mid-eruption.

Tips:
- Roblox rotates thumbnails, and the first one is also the default share image.
- Once the game has traffic, A/B test the lead thumbnail with Creator Hub's thumbnail personalization.

## Title

`Hatch & Snatch 🥚` at launch. During events, put a tag in front, for example `[🌕 BLOOD MOON] Hatch & Snatch`. Tags like that lift click-through; change them with each update.

## Description (paste as is)

976 characters, under Roblox's 1,000 limit. Rewritten 2026-10-01 (owner: the first version read as AI): concrete moments from a session instead of a feature list.

```
Every egg on the conveyor could hatch a 1 in 20,000 Secret. Raise it, show it off, and keep it safe, because everyone in your server wants it. 🥚

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

### Launch week (2026-10-06 to 10-13)

The ×2 luck runs until 2026-10-14 04:00 UTC (`Config/Economy.luau` `tunables.launchLuck`). For that week, use this description (943 characters: the luck line leads, and the 🆕 line makes room), and the title `[🍀 2x LUCK] Hatch & Snatch 🥚`. Switch both back to the ones above on Oct 14.

```
🍀 LAUNCH WEEK: ×2 LUCK on every egg for everyone, until Oct 13!

Every egg on the conveyor could hatch a 1 in 20,000 Secret. Raise it, show it off, and keep it safe, because everyone in your server wants it. 🥚

🐣 Grab eggs off the hatchery belt, carry them home and watch the incubator glow. Every hatch rolls a species, a shiny finish and a mutation.
🐾 Babies grow into Juveniles and Adults. Bigger creatures earn more, but they're harder to protect.
🏃 Sneak into other bases and run off with their creatures. Adults slow you to half speed, so the owner can knock them loose.
🔒 Lock your laser gate, set alarms and tripwires, and guard your nursery.
🌋 41 creatures across 6 biomes: a magma lynx, a black-hole tortoise, a toaster that thinks it's a turtle...
🌕 When the Moon Egg turns red, gold, void or prism, the odds change for the whole server.

🎁 Free codes: HATCH · MOONEGG · SNATCH (Shop → Free rewards)
👍 Like the game for more codes!
```

## Sources

- Icon: `IconRealEyesB` / `IconRealEyesA` (Tripo, `tools/tripo_jobs_marketing.json`).
- Thumbnails 1–3 are Higgsfield drafts (see `docs/ROSTER.md` → Store art): `0a0bc141`, `c826ccbe`, `a95a62f6`, `1ccbf410`.
- Thumbnails 5–9 are in-game captures from Studio (`marketing/raw/`, no UI text), with the text added by `python3 tools/marketing/compose.py shots`.
- Logo and thumbnail 4 were made with the Tripo API (`tools/tripo_jobs_marketing.json`, Nano Banana Pro, 10 credits each); the outputs are in `assets/tripo/marketing/`.
- Fonts: Luckiest Guy (Apache 2.0), Lilita One and Titan One (SIL OFL). The license files are in `tools/marketing/fonts/`.

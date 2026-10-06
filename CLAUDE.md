# HATCH & SNATCH — Roblox game (read this first)

Roblox creature game: hatch eggs from a conveyor, grow creatures from baby to
adult, earn cash, and steal (or get stolen from). The goal is passive income
(game passes, dev products, Premium Payouts, rewarded ads).

Repo: `connord138-source/hatch-and-snatch`. History was carried over from the
`hatch-and-snatch/` folder of `polymarket-scanner`; that copy is retired. It is
unrelated to the Polymarket worker.

## Owner's machine

- Local clone: `C:\Users\neos1\Desktop\hatch-and-snatch` on Connor's Windows PC.
- Work branch: `claude/core-systems`.
- Start syncing from that folder with `rokit install`, then `rojo serve`, and connect the Rojo plugin in Studio.
- Division of work: Claude does the building (code and Studio). Connor does the playtesting and reports the Output window or screenshots.

## Decisions already made (do not re-litigate)

- **Concept:** the "Hatch & Snatch" tycoon won over survival co-op, obby and fishing ideas.
- **World:** Crackpoint Island.
  - A **Moon Egg** hangs cracked in the sky and drives the events: Blood, Gold, Void and Prism moons.
  - A Hatchery Reactor sits in the center, with a **conveyor loop** carrying eggs.
  - **8 base plots** are arranged in a ring around the loop.
  - The owner approved the loop and plot layout.
- **Art style:** inspired by *Creatures of Sonaria*, taking only the style and never its designs.
  - Semi-realistic fantasy animals with natural proportions and **realistic eyes**.
  - Faceted models with smooth shading and solid color regions.
  - Each creature is fused with a **real natural material or element**: magma, geode, coral, ice, lightning, void.
- **Approved references:**
  - **Emberlynx** (the magma lynx; a 3D model already exists).
  - **Tidalotl** (the coral axolotl).
  - **Hivebadger**.
- **Tone by rarity:** Common and Uncommon are cute or funny, Rare sits in between, Epic and above are majestic. Junk Egg creatures are pure comedy.
- **Growth, not evolution:** Baby → Juvenile → Adult, like Sonaria life stages.
- **Movement:** a slow bounding run with a hop, not a walk.
  - Babies are bouncy and clumsy, and sometimes face-plant.
  - Adults land with heavy, powerful bounds.
- **Stealing:** every stage can be stolen.
  - Carry speed goes Baby 100% → Juvenile 75% → Adult 50%.
  - "Homegrown" creatures get +25% earnings, struggle when grabbed, and can break free once.
  - Stolen creatures carry a permanent "Stolen from X" tag.
  - Each base has protected **nursery** slots for players who prefer raising their own.
- **Rarity layers:** species rarity, then genetic mutations at hatch, then **finishes** (Gold → Chrome → Diamond → Molten → Galaxy → Prismatic, plus event-only Blood Moon), then color palettes.
  - The owner loved the finish-sheet look (the toaster tortoise in 7 finishes).
  - **Finish effects dialed up** (owner, 2026-10-03): every finish has brighter, layered particles and a stronger light (`CreatureService` `FINISH_FX`); Diamond is a Fortnite-style faceted crystal (the `DiamondGem` MaterialVariant from `tools/textures/make_gem_tex.py`, glass until its maps are uploaded and `make_materials.luau` is run), and Diamond, Blood Moon and Molten animate on the client (`FinishLooks` `shine`: opal drift, a heartbeat pulse, a flicker). Viewports (reveal, details card) get matching 2D glints.
  - **Galaxy** (owner, 2026-10-01): the starfield holds still on screen while the creature moves through it (like galaxy skins elsewhere). Roblox has no custom shaders, so CreatureAnimator slides a tiling Texture on each face (`FinishLooks` `sky`); it's off until `assets/textures/galaxy_sky.png` is uploaded and its id pasted in.
- **Junk Egg:** rare and event-only, containing comic household-object creatures such as the Toaster Tortoise and Fridge Hedgehog.
- **Roster:** 30 launch creatures are final. See `docs/ROSTER.md` and `src/shared/Config/Creatures.luau`.
- **Ultra-rares above Legendary** (owner asked for them): Mythic (1 per biome, about 1/800), Celestial (moon events only), Cosmic (Moonfall only, about 1/2,500 each) and Secret (1/20,000 from every biome egg, earning like the egg's biome; ??? in the Index). That adds 11 species, all approved 2026-10-01 after a rework (docs/ROSTER.md). See docs/GDD.md §7.1.
  - The owner's rule from that rework: a design must **match its name** (a "-lion" is a lion, a "-fox" a fox), and its baby, juvenile and adult must read as **one creature growing up**. Body-shape swaps that broke the name (seal, yeti, pangolin, jerboa) were rejected.
- **Servers:** 6 players, 6 plots (set Max Players = 6 in Game Settings).
- **Progression:** Hatcher Level (XP) plus base level unlock biome eggs; there are achievements; rebirth is prestige only. See GDD §7.2.
- **Eggs and incubators:**
  - Bought eggs are carried over your head and placed into an incubator.
  - Players start with 1 incubator and can buy up to 6.
  - Incubator tiers (Basic → Cosmic) hatch faster and accept later biomes.
  - The rarity color fades in from 40% incubation.
  - **Hatch times** (owner, 2026-10-03: "shouldn't be long at all"): 10 s Common, 20 s Uncommon, 45 s Rare, 2 min Epic, 4 min Legendary, 8–15 min for the ultra-rares, 1 min Junk (`Config/Rarities.luau` `hatchSeconds`), divided by the incubator tier's speed (up to ×4).
  - There is a physical Luck Wheel at the North Commons (charges the next egg's luck) and a case-opening hatch reveal. See GDD §3.1.
  - **Hatch reveal by rarity** (owner, 2026-10-05: "different sounds for different rarities drawn and a more involved sequence when a legendary or higher is drawn"): each rarity has its own synthesized stinger, and Legendary+ gets a long creeping reel, riser, heartbeat pause, impact, rays, confetti and a light pillar from the incubator (`RevealController`, `Shared/RevealTiming.luau`, `HatchPillar.luau`; GDD §3.1). The sounds are one audio file, `assets/audio/hatch_sfx.ogg` from `tools/audio/make_sfx.py`, uploaded once; its id goes in `Config/Sounds.luau` (regions are rewritten by the script) and `src/client/Sfx.luau` plays each stretch with `PlaybackRegion`, falling back to pitched pings while the id is 0. The Luck Wheel uses the same pack.
  - **Luck Wheel rebuilt** (owner, 2026-10-04: "VERY crude and glitchy"): a game-show wheel built from parts in `src/server/LuckWheel.luau` (true wedge slices with icons from `Config/Economy.luau` `luckWheel` `icon`/`big`/`sub`, pegs and a flapper, marquee bulbs, arch sign, red button, odds board). `WheelService` keeps a line instead of rejecting a second spinner, plus Spin all (R); the spin lives on `ReplicatedStorage.LuckWheelState`. `LuckWheelController` binds by the `LuckWheel` tag (the model streams Atomic), moves the disc with BulkMoveTo, and plays ticks only near the wheel. Preview: `bash tools/preview/run_wheel.sh <dir>`.
- **Belt:** eggs roll out of and back into the hatchery tunnel; they never vanish in view.
- **Creatures:** they sit when idle and only run (hop) while following. Walking a creature makes it follow you, prevents stealing and doubles growth speed (×4 inside its own biome's zone, owner 2026-10-03); it keeps earning, and AFK walking is fine (owner, 2026-10-03).
- **Worth** (owner, 2026-10-03: a Lunaris earning ~2M/s "only worth 13M" made no sense): a creature's Sell price is half its egg's price for an average Adult from that egg, scaled by its earnings, and at least 15 s / 2 min / 10 min of its earnings as a Baby / Juvenile / Adult (`Economy.sellValue`). Fresh Babies stay below their egg, so hatch-to-sell never pays.
- **Bases:** 5 upgrade levels (bigger plot, ground pedestals up to 20, longer lock), 3 security upgrades (alarm, tripwire, auto-lock) and the Castle Designer. See GDD §6.1.
  - **Roomy ground floor** (owner, 2026-10-02: "far too cramped together on the bottom floor ... spots on the left and right of the center"): the plot grows to 88×80, and the 20 ground spots stand in two wings (2 columns × 5 rows a side, 13 studs apart) either side of an open hall with the kit's centerpiece at its end (`WorldService` `GROUND_COLUMNS`, `GROUND_ROWS`).
- **Fortress bases** (owner, 2026-10-01; approved concepts FortressStages/FortressCitadel): the walls grow with base level, Camp → Stockade → Keep → Fortress → Citadel (`Fortress.luau`). The floors are a solid stone keep, never glass ("not see-through").
  - **Every upgrade is a walk-over buy pad** in the front yard (stand 0.6 s). Customizing is in the Base menu, opened only at the base's **Command Terminal** (`BaseKit.luau`).
  - **Security rule (owner):** every security measure has a timer or a release, so no base is ever unbreakable. Items: Spike Strip, Searchlight, Ramp Gates, Net Ballista (`Config/BaseBuilds.luau`).
  - **Hiding spots** (owner): 4 buyable spots, one creature each; thieves can search them (empty ones are decoys) and Mythic+ sparkle now and then, so ultra-rares are never hidden for good.
  - Decor items (torches, banners, moat, statues of your rarest, ...) can be switched on or off at the terminal.
  - **Castle Designer** (owner, 2026-10-01; replaced the nine base themes): seven mix-and-match slots (stone, roofs, banners, glow, floor, grounds, theme kit), each option bought once when its biome zone, base progress or a rebirth unlocks it, plus 16 one-click presets (Ice, Fire, Light, Dark, Red, Green, Rainbow, ...). `Config/CastleDesigns.luau` resolves picks into the same `BaseTheme` record the world code already used. Imported tower and gatehouse models only show for the Classic look (their textures are Classic); other designs build towers from parts. Rainbow parts carry the `Rainbow` tag and `RainbowController` cycles them on the client.
    - **Diamond stone** (owner, 2026-10-02: "a diamond texture rather than actual diamond ... imprint iridescence in the skin of the castle as we did with the creatures"): a cut-diamond brick MaterialVariant (`Config/Materials.luau`, a stone's `variant`) whose parts carry the `Iridescent` tag, so `RainbowController` drifts a faint pastel sheen over them. A white castle glares under lights: its torches, gate glow and niche lights follow the kit's `lightScale` too.
    - **Rebirth ladder** (owner: "the more desirable and harder to get ones should require multiple rebirths to generate return players"): Molten 1 → Rainbow 2 → Solid Gold 3 → Diamond trim and Rainbow glow 4 → Diamond stone 5 → Void 6, each priced near its rebirth's cost. The Rebirth menu shows the next unlock (`CastleDesigns.rebirthUnlocks`). Put new prestige looks on this ladder, not behind cash alone.
    - **Theme kits** (owner, 2026-10-01/02: "physical assets that add a feeling of I earned this", "exactly like the photos", "dont cut corners on the castles"): a seventh designer slot, Theme, adds a kit of real 3D pieces (`src/server/CastleKits.luau`): tower caps, tinted growths on every battlement, banners, a stone band, themed light everywhere, gate dressing, ground and basins, set pieces. The approved concepts are `assets/tripo/concepts/Theme*.png`; compare previews against them (`NIGHT=1 VIEW=front bash tools/preview/run_designs.sh`). Green 25M → Coral 150M → Fire 2B → Ice 15B → Storm 75B → Moon 750B, then Golden, Diamond and Void on rebirths 3, 5 and 6. Late kits should take tens of hours of income ("1000 hours is too long"). Kit prop names must not clash with existing WorldProps (the kit coral is `CoralBranches`, the ice cap `IceCrystalSpire`).
      - **Variety and interiors** (owner, 2026-10-02: "not the same repeated asset over and over", "clams with pearls", "still need interior detail", "spacing and second story spots for the creatures as there are in the renders"): each theme mixes 3–6 models in growths, gardens and interiors (31 variation models, `tripo_jobs_castle_kits5*.json`). Every pedestal has an arched **display niche** that glows in its creature's rarity color (`WorldService.setNicheGlow`, lit from CreatureService); the floors' pedestals stand inside their arches; the ground floor has its own arcade; ramps are drawn as stairs; each floor has a themed centerpiece and hanging lights (`CastleKits.dressNiche`, `dressFloor`).
- **Floors and vaults** (owner, 2026-10-01; replaced the level-4 deck): two bought floors (+9 pedestals each since 2026-10-02: 5 across the front arches and 2 along each side wall; harder to steal from: ramps, longer Steal hold, grab only from the same floor) and 4 bought vault rooms (one creature each, door locked on a timer). Floors and vaults unlock more Castle Designer options. Prices rise each step; see GDD §6.1 and `Config/Economy.luau` (`floors`, `vaults`).
- **World:** walled, level-gated biome zones, each with harvest nodes (biome Essence) and a shrine (forge an egg or take the biome's blessing). Releasing creatures also pays Essence, and creatures eat their own biome's Essence to grow at once (Feed on the details card: 10 Essence per 15 min, `Zones.feed`; owner, 2026-10-03). See GDD §7.3 and `Config/Zones.luau`.
  - **Island layout (owner, 2026-10-01: "exactly like" the approved IslandDressed concept):** reactor in the middle, a ring of fortresses, a ring of six walled biome sectors open north and south (`ZoneShape.luau`), and roomy open land to the beach full of landmarks (`Landmarks.luau`). Radii (2026-10-02, after the bigger castles and the owner's "more space between the bases and the biomes ... so players can see biomes behind built castle bases"): plots 140, zones 260–350, island 465 (`WorldService`). The outer land holds the stations: North Commons (Luck Wheel, Quest Board, Daily Chest) and South Event Grounds (moon event board).
  - **The sea is the border** (owner): players can't go into it (an invisible shoreline wall); the pier leaves room for boats to more islands later.
- **Zone set-piece events** (approved 2026-09-30): bloom, pearl, eruption, boulder, strike and meteor, each paying Essence, spins or a luck charge. See GDD §7.3.
  - Later, per the owner: taming, training, biome shops and larger biomes.
- **Monetization** (built 2026-09-30): 6 game passes and 5 developer products, with Server Luck as the headline product. See GDD §9.
  - VIP is a tag, +10 storage and +10% cash, because +10 pedestals doesn't fit the plots. Instant Restock was dropped.
  - Names, prices, descriptions, Creator Hub ids and tuning all live in `src/shared/Config/Monetization.luau`. An item with id 0 is hidden in the live Shop.
  - **Paid random items (2026-10-01):** eggs count, because Robux buys cash and Server Luck. Eggs roll species, finish and mutation at purchase, and the odds panel (`Shared/Odds.luau`, `OddsController`) shows exact odds summing to 100% before buying. `paidRandom` products are hidden for `ArePaidRandomItemsRestricted` players. The questionnaire answer is Yes / Yes.
  - Free rewards (`RewardsService`): codes (`Config/Codes.luau`), a Roblox group perk (id 0 until the group exists), a Premium perk, and a rewarded ad giving ×2 cash (ad rewards can't be random, so it isn't a free egg).
- **Launch (owner, 2026-09-30):** v1 ships with every biome. Players unlock them through Hatcher Level and base level. Later updates add creatures, maps and features, not gated biomes.
  - **Go (owner, 2026-10-05):** Public, Console on, thumbnails re-uploaded, launch 2026-10-06. **Launch week ×2 luck** for everyone until 2026-10-14 04:00 UTC (`Config/Economy.luau` `tunables.launchLuck`; all egg luck goes through `Odds.luck`, which both HatchService and the odds panel use, so they can't disagree). Controllers drive the menus (`MenuController`: D-pad ▲ to the bar, B closes a menu or steps off the bar; the window is a SelectionGroup that stops at every edge, and scrolling lists are `Selectable = false` so the D-pad lands on their rows). Published as v177 from 5dd0f66 after a full PC re-test (2026-10-05).
- **Economy pacing (owner, 2026-09-30):** players must not max their base on day 1. The economy was retuned so a 3 h/day player reaches Frost around day 3–4, Storm around day 10 and base 5 plus Moonfall around days 19–22; rebirth is the endgame sink after that. See GDD §7 "Pacing".
  - Rerun `bash tools/sim/run_economy_sim.sh` after any change to prices, earnings, costs or XP.
  - **Drop rates** (owner, 2026-10-03: "pretty ruthless ... not too much for the extreme rares"): species weights 46/28/16/7/3 (Common → Legendary), Mythic ~1/800, finishes per pull Gold 1/8, Chrome 1/25, Diamond 1/80, Molten 1/250, Galaxy 1/4,000, Prismatic 1/16,000 (owner: "Galaxy can stay 1 in 4000 out of total pulls ... per pull, not per creature"; finishes and mutations always roll per egg, never per species), the common mutations 1/8,000 and 1/12,000. Then ("50000 still feels crazy even 10k"): each Cosmic 1/2,500 and the Secret 1/20,000 from every biome egg (a 3 h/day player buys only ~260 Mossvale eggs a month); store description and thumbnails 2 and 7 updated. Iridescent stays 1/100,000. The pacing was held by Epic/Legendary earning 18/60 (were 25/80) and base 5 costing 800B (was 500B).
- **Daily rewards** (built 2026-09-30): a 7-day login streak and 3 daily quests (GDD §7.4, `Config/Daily.luau`).
- **Store page** (built 2026-09-30): the files to upload are in `marketing/`, and the copy is in `docs/STORE_PAGE.md`. Rebuild with `python3 tools/marketing/compose.py`. Store art must be attention-grabbing (owner).
- **Day/night** (owner, 2026-10-02): 12 min day, 4 min night, from the server's clock on each client (`Shared/DayNight.luau`, `DayNightController`); the server's lighting is the daytime look.
- **Admin panel** (owner, 2026-10-03): an Admin button (bottom-left) for the experience's owner only: cash add/set, XP, spins, rebirths, Essence, spawn any creature (stage, finish, mutation; the target sees the hatch reveal), eggs (random, or set to hatch the picked creature), hatch/grow all, max base, every design, passes and products, moon and zone events, holding the sky at day/dusk/night, testing aids; targets me, everyone or one player. `Admin.luau` decides who (the owning user or group owner, `ADMIN_USER_IDS`, anyone in Studio) and re-checks every call; `AdminActions.luau` holds the actions (shared with the Studio Command Bar hook); `AdminController` is the client panel. Admin cash is logged under the `Admin` SKU.
- **Creature details** (owner, 2026-10-03): tapping a name in the Creatures menu opens a card with the model, genetics (finish, mutation, origin), the earnings breakdown, growth and location; the hatch reveal also spells out the finish and mutation. Both use `Shared/Genetics.luau`, and the spinning model is `src/client/CreatureViewport.luau` (shared with the reveal).
- **Instructions for the owner's PC session must be written as a paste-ready prompt** (the owner asked for this).
- **Mutations** (owner, 2026-10-01: "like Galaxy, other people will want them; by far the most desirable yet rarest", "professional and clean", then "immensely more detail... Albino needs red eyes"): Albino and Melanistic 1/8,000 ×10, Piebald and Chimera 1/12,000 ×12 (Chimera replaced Leucistic, which read as a paler Albino), Iridescent 1/100,000 ×40 (the rarest roll in the game), stacking with finishes.
  - **⚠ Do not upload mutation skins (2026-10-03):** the owner's account was suspended 7 days for "Sexual Content" over an uploaded Chimera skin atlas (asset 84739040638074). Automated image moderation misread the pale pinkish fur pieces of the unwrapped atlas as human skin. The recipes were recolored the same day (no pink, peach or beige; a swapped `smoothstep` had put pink on every Albino texel), and `tools/mutations/screen_skins.py` now gates uploads (color checks against each creature's own accepted texture plus an NSFW classifier on the packed GLBs; see docs/ASSETS.md). Upload only skins from a classifier-enabled `screen_skins.py assets/skins/glb` run that exits 0; 42 of 615 stay held back (37 at the PNG screen, 5 more once JPEG-packed) and fall back to the v1 look. The suspension was lifted on appeal (2026-10-04). The 462 old pink images (uploaded 2026-10-03 07:37–07:44) stay on the account unused: Creator Hub can't archive or delete Images (only Configure, View details, Copy ID), and Open Cloud's `:archive` refuses them too ("not an archivable asset type", tried 2026-10-04 with `tools/mutations/archive_old_skins.py`), so the owner went ahead without it. Before any skin upload: regenerate (`run_all.py --force`), screen, and import in small batches, waiting for moderation between them. Never upload from another account while one is suspended (Roblox treats that as evading enforcement).
  - **v2 skins** (approved 2026-10-01): each mutation is a recolor of the model's own texture made offline (`tools/mutations/`: bake per-texel 3D position and normal, eyes picked by hand on face renders in `eyes.json`, recipes in `make_skins.py`), shipped as `ReplicatedStorage.MutationSkins.<Model>.<Mutation>`. `MutationLooks.apply` wears the skin and falls back to the v1 solid looks (`Config/Mutations.luau`, `Shared/MutationLooks.luau`, GDD §5). Skins ship non-metallic (a metallic Tripo map turned the albino Quasarfox grey).
  - Plus an accent ring round the halo, accent-colored name, soft glints, a server announcement with the odds and a reveal banner. The tint system only darkens (SurfaceAppearance.Color multiplies), which is why whitening looks need real skins.
- **Rarity looks** (owner, 2026-10-01): every creature has a rarity-colored halo plus stardust that grows each tier; Mythic and up are also tinted toward their rarity color (`Shared/RarityLooks.luau`, GDD §5). A species whose own colors fight the tint gets an override in `SPECIES_TINT`: Glacierion has none (and a white light), so it stays white ice, and Solarion uses warm gold.
- **Eggs:** each biome gets its own egg design (`EggModels.<BiomeId>`), and the generic tinted `Egg` is the fallback. Incubators glow in the rarity color for Epic and up as the egg nears hatching.

## Art direction lessons (learned the hard way)

The owner rejected all of the following:

- Generic cube or sphere creatures.
- Glossy "AI-looking" premium renders.
- A Pixar look, which doesn't translate to Roblox.
- Cartoon or anime eyes, and toy-like "cute" proportions (Kitefin, Puffleece, Crateroo, the first Cometoad).
- Too many similar lean cat or dog bodies.
- Everything standing in the **same side-on pose**.

How to prompt for concepts:

1. Use **2–3 approved creatures together** as style references, never just one; a single reference copies its body and pose. Tell the model to copy style only, not species, pose or camera.
2. Give every creature a **distinct body shape** (see the body-shape groups in `docs/ART_BIBLE.md`) and a **signature pose and silhouette**.
3. Use the neutral, legs-apart pose only for the clean model sheet sent to 3D conversion.

## 3D assets

- **Everything has a model now** (the Sept 2026 credit promo): 41 adults, babies, 8 eggs and 16 world props, plus 40 fortress, base and island props (2026-10-01, Tripo direct; `tools/tripo_jobs_world.json`, `_fortress_kit.json`, `_hiding.json`).
  - Juveniles: all 41 (the 12 ultra-rares and 6 Junk were added 2026-09-30).
  - Set pieces: 12 (`src/server/SetPieces.luau`, 2–3 per biome zone), each with a part-built stand-in.
  - The links are in `tools/assets_manifest.json`; the workflow is in `docs/ASSETS.md`.
  - `fetch_assets.py` downloads them, `rig_all.py` rigs them, Studio imports them, and `tools/studio/organize_imports.luau` files them.
- **Folders the code reads:**
  - `ReplicatedStorage.CreatureModels.<SpeciesId>`, plus `<SpeciesId>_Baby` and `<SpeciesId>_Juvenile` for those stages.
  - `EggModels.<BiomeId>` (or `Egg`).
  - `WorldProps.<Name>`.
  - `src/server/Props.luau` fits props over placeholder parts; code must keep working when a model is missing.
- Clean model sheets (neutral pose) are the 3D inputs. Never convert an action-pose concept directly, because it rigs badly.
- **Rigging:** `tools/blender/rig_all.py` auto-rigs GLBs to FBX headless, and CreatureAnimator drives the bone names procedurally.
  - All 105 creature models rig cleanly in the sandbox (`pip install bpy pillow`; bpy 5.0 needs Python 3.11).
  - Tripo keeps the concept's three-quarter turn, so the rig squares each body up (PCA) before guessing the head end.
  - Skin weights are smoothed along the surface (rig v2, 2026-10-01): raw nearest-bone weights stretched legs and tails into strings (Mossmunk). Bump `RIG_VERSION` in `rig_all.py` whenever the rig's output changes, so every model is rigged again.
  - Rig v3 (2026-10-03, owner: "a few of the creatures still have leg stringing"): feet are found as whole ground patches split front/back at the widest gap (v2's mid-box quadrants gave a hind foot's toes to the front leg, which then swallowed the thigh: Lunaris, Stormback); the leg-to-body hand-over is a harmonic field solved along the surface so it lands at the hip; front and hind legs never share a vertex; the 4-influence cap hands a dropped bone's weight to its skeleton neighbour. Two-legged models (Frostbun, Squallcoon, Pyrodrake_Juvenile) stand on the hind-leg bones and leave the front ones empty. Measured over 14 game poses on all 123 models, the string score fell 332 → 30 (54 models over 1 → 7; the rest are belly stretch on deep-bellied short-legged bodies like Capybaron, from the leg pivots sitting high, not strings).
  - The head guess (higher end = head) fails on raised tail clubs, tufts and swirls. Wrong ones carry `"flip"` in `bodyplans.json`, under `front`, `frontBaby` or `frontJuvenile` (each GLB has its own orientation).
  - After adding models, check them with `tools/blender/facing_check.py`: colored side and top views, head should be on the left.
  - If antlers or wings are wider than the body is long, PCA squares the model up sideways and the top view isn't lengthwise. Give the head's axis instead (`+x`, `-x`, `+y` or `-y`; the Sylvanox Juvenile is `+x`).
  - Grounding: `src/client/CreatureGrounding.luau` does forward kinematics on the bones, solves the sit per model (tilt about the front feet, hind legs folded to the ground) and keeps the lowest foot on the ground. Don't pitch `Hips` for poses: it's the parent of the whole skeleton and swings the front legs off the ground. Test: `bash tools/tests/run_grounding.sh` (luau CLI).

## Tooling notes

- **Higgsfield:** project "Hatch & Snatch — Art Tests".
  - Folder/project id `6d89dc0f-9bb7-4421-aa38-a2c3f0e1a49a`, workspace `0e9c384c-231d-44f7-92bd-b44c00f8b6ff`.
  - Concept images: `gpt_image_2_5` costs 0.25 (low), 0.5 (medium) or 1.5 (high) credits. **Medium matches the old 8–9-credit recipe** for stage variants.
  - 3D: `tripo_h3_1_image_to_3d` with face_limit 8000, about 9 credits.
  - File storage: `media_upload` accepts `.glb` as a general file and returns a permanent `d2ol7oe51mr4n9.cloudfront.net` URL. PUT with `Content-Type` and `If-None-Match: *`, then `media_confirm` with type `file`. This is how the direct-Tripo GLBs are hosted.
- **Tripo API direct** (`tools/tripo.py`, key in `TRIPO_API_KEY`). API credits are separate from the tripo3d.ai web app's credits.
  - Costs: image_to_model (v3.1, textured) 30, text_to_model 20, generate_image 5 (`gemini_2.5_flash_image_preview`, `gpt_4o`) or 10 (`gpt_image_2`).
  - Text-to-3D is good enough for props.
  - For concepts use nano-banana (`gemini_2.5_flash_image_preview`); `gpt_4o` drifts to cartoon eyes.
  - Every task is logged in `tools/tripo_log.json`.
- **Images are reachable from the sandbox now** (CloudFront downloads work as of 2026-09-29), so review concepts and Tripo previews before converting.
- **Evolution sheets** (2026-10-01): to design or redo a creature's stages, generate one sheet with baby, juvenile and adult side by side (Nano Banana Pro, `gemini_3_pro_image_preview`, 10 credits), get it approved, then render each stage from the sheet as its own clean model sheet (Nano Banana, 5 credits) for 3D. Cutting stages out of the sheet doesn't work (they touch, and the crops are small).
  - Name the age in the per-stage prompt ("a newborn kit: round body, big head, stubby legs"), or the baby comes out as a small adult. Capybaras have no tail; say so.
  - Tripo rejects prompts over about 1,800 characters (error 1004).
- **Juvenile prompts:**
  - "Lanky, slightly long legs" puts heavy, low and shelled bodies on stilts. For those, use "legs only a little longer in proportion but still short and sturdy like the reference".
  - Name the signature feature to keep (for example "keep its shaggy aurora-tipped coat").
- The owner has granted **full permission** for this work, including Higgsfield spend at this scale. Don't ask for small confirmations.
- The owner prefers compact, decision-focused replies and keeping conversation context.

## Tech

- Rojo 7 (`default.project.json`) with Luau `--!strict`.
- Tool versions are pinned in `rokit.toml`; lint with selene and format with StyLua.
- Config is data-driven in `src/shared/Config/*`. New content means editing tables, not code.
- The server is authoritative for cash, hatching, growth and stealing, since stealing games attract exploiters.
- Player data: ProfileStore, vendored at `src/server/Packages` (Apache-2.0). Studio sessions use the separate `PlayerData_Studio_v1` store, and live servers use `PlayerData_v2`, so Studio testing never touches real profiles. An unpublished place falls back to a mock store.
- Purchases: `MonetizationService` owns ProcessReceipt. A product's effect is registered with `MonetizationService.onProduct(key, fn)` by the service that owns it, and `fn` may only change that player's data (it runs once per receipt, and the receipt is confirmed after a save). Check passes with `MonetizationService.hasPass(player, key)`.
- Security (2026-09-30 audit): anything that pays out from a ProximityPrompt or touch pad checks `src/server/Reach.luau` (the player really is there). Steals check movement server-side (see GDD §6), and passes are confirmed with `UserOwnsGamePassAsync` before being granted. Signal listeners are isolated (one failing listener can't stop a join or leave).
- Bandwidth: `StateService` sends only the top-level state fields that changed, and the client merges them (`ClientState`). Belt eggs follow a shared time-based path (`src/shared/Belt.luau`): the server moves them at 4 Hz and clients animate them every frame.
- UI: `Ui.autoScale(screenGui)` scales pixel layouts down on phones and small windows (touch-only screens use a 960×540 design size, so phones scale down less; `Ui.isTouch()`), and `Ui.hint(text)` drops " (E)"-style key hints for players with no keyboard (touch and console). Write prompt hints as " (E)", never "Hold E". The menu window fills the space above the bottom bar, and the server drops a repeat of the same toast within 1 s (`Net.notify`) while the client merges repeats.
- Sprint (owner, 2026-10-05): `SprintController`, client-side (Left Shift held, ButtonL3 or the touch "Run" button toggle). It only swaps the normal speed for ×1.6 and back, never touches a speed the server set (carry pace, net, tripwire), and is off while carrying, so the server's carry checks still see the normal speed. Walked creatures match the owner's speed. Any new server speed change must use a value other than the normal walk speed or set the Carrying attribute.
- Audio (owner, 2026-10-05): event cues go through `Net.cue` / `Net.cueAll(name, at?)` and `CueController`'s table (sounds from the one sound pack; give a position for a sound in the world). Music is `Config/Music.luau` (day, night, moon lists of Roblox-licensed or owner-owned ids; 7 APM tracks picked by the owner) played by `MusicController`, ducked under reveals; never ship an id the owner's account can't use (it fails to load and is skipped with a warning). Music must stay **subtle** (owner): every track has its own level in `trackVolume` (licensed tracks are mastered up to 2.6× apart), set so loudness × volume ≈ 16 day / 14 night / 18 moon, about 10 dB under the Common stinger. Measure a new track's loudness in Studio (PlaybackLoudness ignores Volume) and add its entry.
- Prismatic is glossy SmoothPlastic with its color cycled at 0.65 saturation (owner, 2026-10-05: Neon melted the creature into an unrecognizable glowing blob). Don't put a whole creature in Neon.
- Controllers (Xbox): `PromptFilter` gives each ProximityPrompt the controller button for its key (E → X, R → Y, F → B). Every prompt defaults to X and only one prompt per button shows at a time, so a new prompt key needs an entry in `GAMEPAD_KEYS`.
- Team Test servers probably report `IsStudio() == false`, so they would use the live `PlayerData_v2` store.
- Analytics: log through `src/server/Analytics.luau`. `EconomyService.spend` and `grant` take an item SKU for the economy dashboard, so keep SKUs to small fixed sets.
- Services live in `src/server/Services`. The start order in `init.server.luau` matters: each service connects to `DataService.loaded` inside its `start()`, and DataService starts last.
- **Previewing world code from a cloud session:** `bash tools/preview/run_fortress.sh <dir>` runs `Fortress.luau` in the luau CLI (Roblox shims in `tools/preview/world_stub.luau`) and renders every tier in Blender; `bash tools/preview/run_island.sh <png>` draws the island layout top-down from `Landmarks.luau`. `bash tools/preview/run_wheel.sh <dir>` renders the Luck Wheel. The previews' stand-in plot (`tools/preview/plot_context.luau`) reads WorldService's layout constants through `keep_constants.sh`, so new sizes carry over; a change to buildPlot's geometry (new pieces, ramps, spots) still needs mirroring there.
- **Verifying from a cloud session** (no Studio available): use `rojo sourcemap`, then `luau-lsp analyze --definitions=<globalTypes.d.luau> --sourcemap=... --ignore="**/Packages/**" src`, then `stylua --check src`. Pure config and economy logic can run in the plain `luau` runtime after swapping `script.Parent.X` requires for `./X` and stubbing `Color3`.
- Server pushes (ramp gates, auto-lock, ballista, locked zones) go through `Net.teleport(player, cframe)`: a server `PivotTo` alone was undone by the client's own physics about half the time, so the client's `TeleportController` repeats the move.
- Lighting: `WorldService.setupLighting` deletes any post effect or Atmosphere in Lighting that isn't its own (`OWN_EFFECTS`). The place template had left a Bloom, SunRays, DepthOfField and Atmosphere that stacked on ours (Ice and Diamond blew out at night). Look up our effects by name (`IslandAtmosphere`, `IslandBloom`), never `FindFirstChildOfClass`.
- Custom materials: a game script can't set a MaterialVariant's maps ("lacking capability Plugin"), so the variants live in the place file. After changing `Config/Materials.luau`, run `tools/studio/make_materials.luau` in Studio's Command Bar (edit mode) and save the place; WorldService warns at start if one is missing, and a stone without its variant shows the plain base material.
- Place an anchor part where it goes before `Props.weldCentered` welds a model to it outside the Workspace: a WeldConstraint takes its offset when the parts reach the Workspace, so moving the anchor afterwards strands the mesh. The belt eggs' meshes sat at the conveyor's center, invisible, from b67abbc until 4aea1ef.
- Set an Attachment's `WorldPosition` only after parenting it. Set while unparented, it's stored as a local offset, so the attachment lands far away (this hid the rarity halo and the element glow light until b0e854b).
- UI text: ✦ (U+2726) and ▾/▴ render as empty boxes in Roblox fonts, so use ✨ and ▼/▲. The other symbols in use (→ ⚠ ✓ ✔ ⬇ ★ ◆ and emoji) render fine.
- luau-lsp quirk: indexing `{ [Types.BiomeId]: T }` maps with values from other modules raises false singleton errors, so biome-keyed maps use `string` keys.

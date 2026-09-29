# Hatch & Snatch: Game Design Document

Status: **pre-production.** The world, art style and roster are locked. The
numbers are first-pass drafts to tune during playtesting. Gameplay values live
in `src/shared/Config/*`, and that code is the source of truth; this document
explains the reasoning behind them.

## 1. Pitch

On an island under a cracked Moon Egg, players buy eggs off a conveyor, hatch
semi-realistic elemental creatures, raise them from cute babies into majestic
adults, and earn cash from them. Every other player can sneak in and **steal**
them. Players who'd rather raise their own get protection and bonuses for
doing so.

**Design goals**
1. **Learn it in 10 seconds:** buy an egg, place it, collect cash.
2. **Progress continues while you're away:** hatch and growth timers run offline, and cash is banked (capped at 8 hours).
3. **Social tension creates stories:** steals, revenge and trades produce clips people share.
4. **A collection that keeps pulling you in:** species × growth stage × mutation × finish × palette.
5. **Server-wide moments:** moon events bring players back at set times.

## 2. World: Crackpoint Island

- **Hatchery Reactor** (center): a glowing glass dome. The **egg conveyor loop** starts here and circles the island.
- **8 base plots** are arranged in a ring around the loop, so every base is equally close to the eggs and to each other. Each plot has:
  - pedestals (10 to start, upgradeable to 30),
  - a laser-gate **base lock** with a countdown light,
  - a cash collector and an incubator rack,
  - **nursery** slots.
- **The Moon Egg** hangs in the sky. Its color is the server's event alarm (section 8). Long-term, a big update lets the moon hatch, releasing Lunaris.
- **Biome eggs:** the conveyor carries eggs from biomes the player has unlocked through rebirths, and the map's look expands with them. The biomes, in order: Mossvale Forest → Coral Coast → Magma Rift → Frost Shelf → Storm Peaks → Moonfall.

## 3. Core loop

```
buy egg from the belt → carry it home → place it in an incubator (optional Luck Wheel spin)
    → hatch reveal → creature sits on a pedestal earning cash/sec → grows Baby → Juvenile → Adult
    → XP from all of it raises your Hatcher Level → new biome eggs unlock
    → spend cash on more/better incubators, base upgrades, base themes, pricier eggs
    ↘ steal other players' creatures / defend your own ↙        (rebirth = prestige)
```

### 3.1 Eggs and incubators

- **The belt:** eggs roll out of the hatchery tunnel, ride one lap of the conveyor and roll back in. Eggs never vanish in the open, and the belt can't clog. They can't be bought inside the tunnel.
- **Carrying:** buying puts the egg over your head. You carry it home and place it in a free incubator (E). You can only carry one egg at a time.
- **Incubators:** you start with 1 bay and can buy up to 6 ($0 / 2K / 30K / 400K / 6M / 90M). Each bay upgrades through tiers:

| Tier | Speed | Takes eggs from | Upgrade cost |
|---|---|---|---|
| Basic | ×1 | Mossvale, Coral Coast | — |
| Heated | ×1.5 | + Magma Rift | 25K |
| Thermal | ×2 | + Frost Shelf | 500K |
| Arcane | ×3 | + Storm Peaks | 8M |
| Cosmic | ×4 | + Moonfall | 150M |

  Upgrading while an egg is inside speeds up the rest of its time. Junk Eggs fit in any tier.
- **Rarity tease:** each incubator shows a countdown and a progress bar. From 40% progress the bar, the timer and a glow take on the egg's rarity color, fading in from white; the egg wobbles harder and harder over the last 15%.
- **Luck Wheel:** spend a spin on an incubating egg (Q) and the wheel lands on a luck multiplier (×1.5 34%, ×2 28%, ×3 20%, ×5 11%, ×10 5%, ×25 jackpot 2%). The egg is re-rolled with Epic+ weights multiplied by that luck, and the better result is kept (it can never get worse). One spin per egg. Spins come from playtime (1 per 20 minutes, up to 10 banked), achievements and rebirths; later they can also be sold as a Robux product.
- **Hatch reveal:** a case-opening reel of creature cards from that egg's odds slows down and lands on what hatched, with rare cards teased right beside it. Then a big rarity-colored reveal shows the creature spinning; Mythic and rarer flash the whole screen, and the server announces it once the reveal ends.

## 4. Creatures

- **Roster:** 30 at launch (`docs/ROSTER.md`): 5 biomes × 4, plus 4 in Moonfall and 6 in the Junk Egg.
- **Rarity tiers:** Common, Uncommon, Rare, Epic, Legendary, then the ultra-rares Mythic, Celestial, Cosmic and Secret (§7.1). Junk is its own event-only tier.
- **Tone by rarity:** cute or funny at the low end, majestic at the top. The most valuable creatures should look the most worth stealing.
- **Visual value:** rarer creatures glow more, so a player can read value from across the map before committing to a steal.

### 4.1 Growth (not merging)

| Stage | Earnings | Size | Carry speed when stolen |
|---|---|---|---|
| Baby | ×1 | small | 100% (full speed, can jump) |
| Juvenile | ×4 | medium | 75% |
| Adult | ×15 | large | 50% (no jumping) |

- **Growth time** is a base time multiplied by a rarity factor, and it keeps running while the player is offline.
- **Duplicates can be "fed"** to a creature of the same species to speed up its growth. This gives duplicates a use besides selling. *(Open question: confirm this during playtesting.)*

### 4.2 Movement

- **On a pedestal, creatures sit:** back legs folded, rear lowered, breathing, looking around and swishing their tail. They don't hop in place.
- **Walks:** you can take one creature for a walk (R, or Walk in the Creatures menu). It follows you with the bounding run while you move and sits beside you when you stop. A walked creature can't be stolen and grows 2× faster; it still earns from its pedestal.
- **The run itself is a slow bound with a hop:** front paws reach together, back legs push off together, there's a short airborne arc, and a squash on landing.

- **By stage:** babies bounce too much and occasionally face-plant; adults land with heavy, powerful bounds, a thud, and a puff of their element (dust, embers, frost, sparks).
- **By body shape:** hoppers hop, heavy creatures stomp, and low-slung creatures scurry.
- **How it's built:** one hand-keyed bound animation per skeleton family, plus a shared procedural movement script. It handles hop height, landing squash, trailing tail and ears, head tracking toward nearby players (especially thieves), random blinks, and wandering around the base.

## 5. Rarity layers (the collection)

1. **Species rarity:** see the roster.
2. **Genetic mutations**, rolled at hatch. These give natural variety and are mostly cosmetic, with a small value bonus:
   - Albino 5%, Melanistic 3%, Leucistic 2%, Piebald 2%, Iridescent 0.2%.
3. **Finishes**, the flashy layer. Each is a material and particle swap, so no new models are needed:

| Finish | Odds | Earnings | Look |
|---|---|---|---|
| Normal | — | ×1 | — |
| Gold | 1 in 25 | ×1.5 | Gold with sparkles |
| Chrome | 1 in 100 | ×2 | Mirror finish that reflects the world |
| Diamond | 1 in 400 | ×3 | See-through crystal that bends light |
| Molten | 1 in 1,500 | ×5 | Glowing lava cracks, drips embers, sizzles |
| Galaxy | 1 in 5,000 | ×8 | Starfield skin with a tiny orbiting planet; server announcement |
| Prismatic | 1 in 20,000 | ×15 | Color-shifting glow and a rainbow trail; server-wide fanfare |
| Blood Moon | Blood Moon event only | ×10 | Black and red with a red aura |

4. **Color palettes:** unlockable recolors of each species' color regions. Palettes are a collection track and something players can buy.

**Collection size:** 41 species × 3 stages × 8 finishes = 984 versions before mutations and palettes are counted.

## 6. Stealing

| Rule | Draft value |
|---|---|
| All growth stages can be stolen | yes |
| Base lock duration, then cooldown | 60 s locked, 45 s cooldown |
| New-player protection | first 10 minutes |
| Creatures leave with their owner | theft only happens while the owner is online |
| Owner can knock a thief down so they drop the creature | yes; adults are dropped more easily |
| **Homegrown** (hatched and raised by you) | +25% earnings, struggles when grabbed (thief moves slower), can break free once per steal |
| **Stolen from [name]** tag | permanent; a stolen creature loses Homegrown status |
| **Nursery** slots (nothing in them can be stolen) | 1 to start; up to 3 with cash upgrades or the game pass |

All of this is checked on the server: grab range, carry state, drop-off at the thief's own base, and the lock state.

### 6.1 Base upgrades and themes

- **Base level 1 to 5:** upgrade at the gold-gem station by the lock (or in the Base menu) for 7.5K, 90K, 1.2M and 15M. Each level:
  - widens and deepens the plot (44×44 up to 68×80 studs), so thieves have a longer run out;
  - adds a row of 5 pedestals (10 up to 30);
  - adds 15 s to the laser lock (+60 s at max).
- **Base themes:** each biome has a look for your plot: floor material, trim, laser color and edge decor. A theme can be bought once its biome's eggs are unlocked (Coral 20K, Magma 400K, Frost 6M, Storm 90M, Moonfall 1.5B). Owned themes can be switched freely.
- **Servers:** 6 players per server (6 plots); set Max Players = 6 in Game Settings.

## 7. Economy (first-pass draft; tune in playtests)

| Rarity | Base cash/sec | Hatch time | Growth factor |
|---|---|---|---|
| Common | 1 | 30 s | ×1 |
| Uncommon | 4 | 90 s | ×1.25 |
| Rare | 15 | 5 min | ×1.5 |
| Epic | 60 | 15 min | ×2 |
| Legendary | 250 | 45 min | ×3 |
| Mythic | 1500 | 3 h | ×4 |
| Celestial | 6000 | 4 h | ×5 |
| Cosmic | 20000 | 6 h | ×6 |
| Secret | 50000 | 8 h | ×8 |
| Junk | 100 | 20 min | ×1.5 |

- **Growth times:** Baby → Juvenile takes 30 min × the growth factor; Juvenile → Adult takes 3 h × the growth factor.
- **Egg prices:** $150 × the biome's price multiplier (×8 per biome). New players start with $300 (two eggs).
- **Biome earnings multiplier:** creatures earn base cash/sec × their biome's earnings multiplier (Mossvale 1, Coral 4, Magma 16, Frost 60, Storm 220, Moonfall 300, Junk 1). It grows slower than egg prices, so payback lengthens as players progress.
- **Resulting payback** for a Common baby: about 2 min in Mossvale, 4 min in Coral, 8 min in Magma, 17 min in Frost, 37 min in Storm. Expected value per egg pays back faster because of the rare rolls, and growing to Adult (×15) is the big payoff. All of this is a first pass to tune in playtests.
- **Rebirth** resets cash and pedestals, keeps creatures, unlocks the next biome and gives +10% earnings for each rebirth.
- **Offline earnings** are capped at 8 hours; the cap can be raised by a game pass.

### 7.1 Ultra-rares (above Legendary)

| Tier | Where it rolls | Odds per egg | Species |
|---|---|---|---|
| Mythic | Any biome egg, any time | about 1 in 1,000 | Sylvanox (Mossvale), Lurehound (Coral), Pyrodrake (Magma), Glacierion (Frost), Stormgriff (Storm), Lunaris (Moonfall) |
| Celestial | Magma and Storm eggs, **only during a moon event** | about 1 in 3,000 | Solarion (Magma), Halosaur (Storm) |
| Cosmic | Moonfall eggs only | about 1 in 10,000 each | Quasarfox, Singularis |
| Secret | Hidden in ordinary eggs; shows as ??? in the Index | about 1 in 50,000 | Capybaron (Mossvale, the $150 starter egg), Nullcat (Junk Egg) |

- Moonfall eggs start at Rare, so their Mythic/Cosmic weights are overridden (`Eggs.biomeRarityWeights`) to keep the odds in line with other biomes.
- Every ultra-rare hatch is announced server-wide in its tier color.
- **Incubator tease:** since the species is rolled at purchase, Epic+ eggs glow in their rarity color, brighter as they near hatching, and pulse in the last 10%. An ultra-rare incubator is visible across the base, which is both hype and a clip moment.
- A Secret in the $150 starter egg is deliberate: any new player can hit the 1-in-50,000 and it spreads by word of mouth.

### 7.2 Progression: Hatcher Level

- **XP sources:** each hatch gives 12 × the biome's order (Junk counts as 3); +60 for a new species, +10 when a creature grows to Juvenile and +40 at Adult, +45 per steal, +150 × level for base upgrades, +60 per incubator bought and +40 per incubator upgrade.
- **Level curve:** it takes 60 + 40 × level XP to reach the next level. That's 640 XP for level 5, 3,300 for level 12, 8,740 for 20, 19,140 for 30 and 33,540 for 40.
- **Biome eggs unlock:** Mossvale at the start, Coral Coast at level 5, Magma Rift at level 12 + base level 2, Frost Shelf at 20 + base 3, Storm Peaks at 30 + base 4, and Moonfall at 40 + base 5. You also need an incubator tier that fits the egg.
- **Achievements:** 18 goals (hatch counts, adults raised, steals, discoveries, rare finishes, upgrades, incubators, walking, spins, lifetime cash), each paying XP and Luck Wheel spins. Listed in the Progress menu.
- **Rebirth** is now pure prestige: it resets cash, gives +10% earnings for good and 3 spins, and keeps everything else. It no longer unlocks biomes.

### 7.3 World

- **The island:** a round grass island with a sandy beach and the sea around it, and a cobblestone plaza under the hub and conveyor. Stone paths run from each plot to the plaza.
- **Hub:** the hatchery tunnel over the belt, with 12 egg-lantern lamp posts around the loop.
- **Biome zones:** one in each gap between plots (Mossvale, Coral Coast, Magma Rift, Frost Shelf, Storm Peaks, Moonfall). Each has a themed ground patch, a matching terrain hill, a name sign and biome decor, so every biome is visible from the start as something to work toward.
- **Lighting:** atmosphere, bloom, sun rays, clouds and a slight color grade. During moon events the whole world is tinted in the moon's color, and the banner says what the event does.

## 8. Moon events (server-wide, hourly)

| Moon | Effect | Lasts |
|---|---|---|
| 🔴 Blood Moon | Finish chance ×5; Blood Moon finish available | 10 min |
| 🟡 Gold Moon | ×2 earnings | 10 min |
| 🟣 Void Moon | Thief night: locks shortened, bonus cash per steal | 10 min |
| 🌈 Prism Moon (rare) | Chance of a Prismatic finish; Junk Egg appears on the conveyor | 5 min |

A **weekly update at a fixed time**, with an admin-hosted live event, runs on top of this.

## 9. Monetization

The rule: everything that matters can be earned. Paying buys speed, convenience, protection or cosmetics. Eggs that can be bought with Robux are never the only way to get a creature. Odds must be shown for any random item bought with Robux, as Roblox policy requires.

- **Game passes (bought once):** 2× Cash, VIP Plot (+10 pedestals and a VIP tag), Auto-Collect, Extra Nursery, Longer Lock, Offline Cap +8h.
- **Developer products (bought repeatedly):**
  - **Server Luck Boost:** the whole server benefits, the buyer's name is announced, and it stacks. This is the headline product.
  - Instant Restock, Growth Elixir, Skip Hatch, Cash packs.
- **Other income:** Premium Payouts (from long sessions), rewarded video ads ("watch an ad for a free egg"), private servers.
- **Free promotion channels:** a like-goal code system, and a reward for joining the Roblox group.

## 10. Technical plan

- **Tooling:** Rojo 7 and Luau `--!strict`, with Rokit to pin tool versions. Format with StyLua, lint with selene.
- **Player data:** ProfileStore for saves, plus a session lock so the same account can't load in two servers at once.
- **Server-authoritative services:**
  - EggService (conveyor spawns and purchases)
  - HatchService
  - GrowthService
  - EconomyService (cash ticks and offline catch-up)
  - StealService (grab, carry, drop, locks)
  - EventService (moon events)
  - MonetizationService
- **Client:** UI, VFX and the procedural creature movement script (visual only; never trusted by the server).
- **Data-driven content:** creatures, rarities, finishes, mutations, biomes and the economy are Luau tables in `src/shared/Config`. Adding content means editing data.

### Art pipeline

1. Concept image in Higgsfield. Rules are in `docs/ART_BIBLE.md`.
2. Clean model sheet: neutral pose, legs apart.
3. Tripo H3.1 image-to-3D, capped at 8k faces.
4. Blender:
   - clean up, target 3–8k triangles,
   - split into jointed parts (head, neck, torso, 2-segment legs, 3-segment tail, plus prop parts),
   - rig with a shared skeleton family,
   - move glowing parts onto separate meshes (Neon material, swapped per finish).
5. Import through Studio's 3D Importer, then make baby, juvenile and adult versions by scaling proportions (babies get bigger heads and shorter legs).

## 11. Roadmap

| Week | Goal |
|---|---|
| 0 (now) | Design, art direction, roster ✅; repo scaffold ✅ |
| 1 | Studio set up on the owner's PC; Emberlynx imported and rigged; bounding-run test |
| 2 | Core loop: conveyor, buying, incubator, hatching, pedestals, cash, saving |
| 3 | Growth stages, stealing, base locks, nursery, Homegrown |
| 4 | Finishes and mutations, moon events, the collection index |
| 5 | Monetization, rebirth, UI polish, analytics |
| 6 | Soft launch with Mossvale and Coral Coast only; other biomes arrive in weekly updates |

Rolling out one biome per update is deliberate: it gives the weekly updates their content.

## 12. Open questions

- Should feeding duplicates to speed growth replace selling them, or sit alongside it?
- Should trading ship at launch or in the first update? (Leaning toward the first update, with trade locks.)
- The final game name: "Hatch & Snatch" is a working title.

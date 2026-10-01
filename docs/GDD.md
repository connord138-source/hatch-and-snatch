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
- **Incubators:** you start with 1 bay and can buy up to 6 ($0 / 5K / 2M / 250M / 30B / 600B). Each bay upgrades through tiers:

| Tier | Speed | Takes eggs from | Upgrade cost |
|---|---|---|---|
| Basic | ×1 | Mossvale, Coral Coast | — |
| Heated | ×1.5 | + Magma Rift | 100K |
| Thermal | ×2 | + Frost Shelf | 25M |
| Arcane | ×3 | + Storm Peaks | 5B |
| Cosmic | ×4 | + Moonfall | 500B |

  Upgrading while an egg is inside speeds up the rest of its time. Junk Eggs fit in any tier.
- **Rarity tease:** each incubator shows a countdown and a progress bar. From 40% progress the bar, the timer and a glow take on the egg's rarity color, fading in from white; the egg wobbles harder and harder over the last 15%.
- **Luck Wheel:** a physical wheel stands by the plaza. Walk up and hold E to spend a spin; everyone nearby watches it turn. Prizes: ×2 luck 30%, cash (5 min of income) 24%, ×3 luck 18%, +2 spins 12%, ×10 luck 12%, ×25 jackpot 4%. A luck prize charges your **next egg** (bought or forged); its Epic+ weights are multiplied by the luck. Spins come from playtime (1 per 20 minutes, up to 10 banked), achievements, rebirths, the Coral Coast shrine and releasing rare creatures.
- **Odds panel** (paid random items, 2026-10-01): while an egg's Buy prompt (or a shrine's Forge prompt) is on screen, a panel lists every species, finish and genetic mutation that egg can give, with percentages that add up to 100%. It updates live with the player's luck charge, Server Luck and moon events. Everything is rolled the moment the egg is bought, with exactly those odds (`Shared/Odds.luau`, `OddsController`), so Skip Hatch and incubator upgrades never change what's inside.
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
| Juvenile | ×2.5 | medium | 75% |
| Adult | ×6 | large | 50% (no jumping) |

- **Growth time** is a base time multiplied by a rarity factor, and it keeps running while the player is offline.
- **Duplicates can be "fed"** to a creature of the same species to speed up its growth. This gives duplicates a use besides selling. *(Open question: confirm this during playtesting.)*

### 4.2 Movement

- **On a pedestal, creatures sit:** the body tilts nose-up about the front feet, the back legs fold down so the rear rests low, and they breathe, look around and swish their tail. They don't hop in place. Feet always stay on the ground: the pose is solved per model (`src/client/CreatureGrounding.luau`), and the lowest foot is clamped to the ground every frame, including mid-run landings.
- **Walks:** you can take one creature for a walk (R, or Walk in the Creatures menu). It follows you with the bounding run while you move and sits beside you when you stop. A walked creature can't be stolen and grows 2× faster; it still earns from its pedestal.
- **The run itself is a slow bound with a hop:** front paws reach together, back legs push off together, there's a short airborne arc, and a squash on landing.

- **By stage:** babies bounce too much and occasionally face-plant; adults land with heavy, powerful bounds, a thud, and a puff of their element (dust, embers, frost, sparks).
- **By body shape:** hoppers hop, heavy creatures stomp, and low-slung creatures scurry.
- **How it's built:** one hand-keyed bound animation per skeleton family, plus a shared procedural movement script. It handles hop height, landing squash, trailing tail and ears, head tracking toward nearby players (especially thieves), random blinks, and wandering around the base.

## 5. Rarity layers (the collection)

1. **Species rarity:** see the roster. Everyone can read it on sight (owner, 2026-10-01; `Shared/RarityLooks.luau`):
   - **Halo:** every creature has a soft halo of its rarity color behind it, stronger with each tier and visible from across the island.
   - **Stardust:** from Uncommon up, sparkles in the rarity color rise off the creature, thicker and brighter with each tier (Uncommon 1/s up to Legendary 8/s, then Mythic 16, Celestial 20, Cosmic 26 and Secret 32, which bloom).
   - **Color conversion (Mythic and up):** the creature's texture is tinted toward its rarity color (Mythic crimson, Celestial pale blue, Cosmic violet), keeping its details and eyes. Secret shifts slowly through the rainbow. A finish replaces the tint; the halo and stardust stay.
   - Lights are added from Epic up. The name tag shows the rarity under the name.
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

All of this is checked on the server: grab range, carry state, drop-off at the thief's own base, and the lock state. Hardened after the 2026-09-30 security audit:

- A thief must be inside the base for about a second before grabbing, so the alarm and auto-lock get their chance.
- A carry that moves faster than its carry speed allows (a teleport or speed hack) drops the creature, and delivery must take about as long as the run would.
- A creature stolen again within 30 minutes still changes hands, but pays no XP, bonus or announcement. This stops two accounts farming each other.
- While someone is in your base, you can't pull pedestal creatures into storage, the nursery or a walk.
- A locked gate that pushes a thief out takes the owner's creature back.
- Both saves are written right after a delivery.

### 6.1 Base upgrades and themes

- **Base level 1 to 5:** upgrade at the gold-gem station by the lock (or in the Base menu) for 60K, 25M, 5B and 500B. Each level:
  - widens and deepens the plot (60×48 up to 76×68 studs), so thieves have a longer run out;
  - adds pedestals (10 up to 30), spaced 11 studs apart; from level 4 the extra pedestals go on an upper deck reached by a ramp;
  - adds 15 s to the laser lock (+60 s at max).
- **Security (Base menu):** three one-time upgrades — Intruder Alarm 40K (you're told when someone walks into your base and they glow red), Tripwire 10M (thieves carrying your creatures move 25% slower inside your base), Auto-Lock 2B (the laser lock turns itself on when an intruder enters, if it's off cooldown).
- **Base themes:** each biome has a look for your plot: floor material, trim, laser color and edge decor. A theme can be bought once its biome's eggs are unlocked (Coral 100K, Magma 25M, Frost 5B, Storm 500B, Moonfall 50T). Owned themes can be switched freely.
- **Servers:** 6 players per server (6 plots); set Max Players = 6 in Game Settings.

## 7. Economy (retuned 2026-09-30 for multi-week pacing; tune in playtests)

| Rarity | Base cash/sec | Hatch time | Growth factor |
|---|---|---|---|
| Common | 1 | 30 s | ×1 |
| Uncommon | 3 | 90 s | ×1.25 |
| Rare | 8 | 5 min | ×1.5 |
| Epic | 25 | 15 min | ×2 |
| Legendary | 80 | 45 min | ×3 |
| Mythic | 400 | 3 h | ×4 |
| Celestial | 1200 | 4 h | ×5 |
| Cosmic | 3000 | 6 h | ×6 |
| Secret | 6000 | 8 h | ×8 |
| Junk | 30 | 20 min | ×1.5 |

- **Growth times:** Baby → Juvenile takes 30 min × the growth factor; Juvenile → Adult takes 3 h × the growth factor.
- **Egg prices:** $150 × the biome's price multiplier (×16 per biome): Mossvale 150, Coral 2.4K, Magma 38.4K, Frost 614K, Storm 9.8M, Moonfall 157M (Junk 38.4K). New players start with $300 (two eggs).
- **Biome earnings multiplier:** creatures earn base cash/sec × their biome's earnings multiplier (Mossvale 1, Coral 4, Magma 16, Frost 60, Storm 220, Moonfall 300, Junk 1). It grows much slower than egg prices, so each biome is a bigger investment than the last.
- **Resulting payback** for a Common baby: 2 min in Mossvale, 8 min in Coral, 32 min in Magma, 2.3 h in Frost, 10 h in Storm and 15 h in Moonfall (whose eggs start at Rare). Adults earn ×6, and rare rolls pay back much faster.
- **Rarity earnings are compressed** (Legendary is 80× a Common, not 250×). Players keep only their best creatures on pedestals, so a steep rarity curve made income explode after a few hundred hatches.
- **Rebirth** is the endgame sink (see §7.2): the first costs 1T, then 2.5T, 6T, 15T and 40T, and each one after that costs ×2.5.
- **Offline earnings** are capped at 8 hours; the cap can be raised by a game pass.

### Pacing (simulated)

`bash tools/sim/run_economy_sim.sh [runs]` plays the real config as an efficient free-to-play player, with no stealing, events or passes. Each day is one session followed by offline time. The player keeps the best earners on pedestals and spends half its income on the best eggs it can fit, one trip to the belt (25 s) at a time. Upgrades are bought cheapest-first. Median of 5 runs:

| Milestone | 1 h/day | 3 h/day | 8 h/day | 12 h/day |
|---|---|---|---|---|
| Coral Coast (Lv 4) | 22 min | 22 min | 22 min | 22 min |
| Base level 2 | day 1 | day 1 | day 1 | day 1 |
| Magma Rift | day 2 | day 2 | day 1 | day 1 |
| Frost Shelf | day 8 | day 4 | day 2 | day 1 |
| Storm Peaks | day 28 | day 11 | day 5 | day 3 |
| Base level 5 (max) | — | day 19 | day 9 | day 7 |
| Moonfall | — | day 22 | day 9 | day 7 |
| Everything bought (6 Cosmic incubators) | — | — | day 19 | day 14 |
| First rebirth | — | — | day 21 | day 16 |

Before the retune, a 3 h/day player had bought everything in about 3 hours of play. Rerun the sim after any economy change. Paid boosts, events and stealing make real players somewhat faster than this baseline.

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
- **Level curve:** it takes 40 + 30 × level + 16 × level² XP to reach the next level. That's 524 XP in total for level 4, 10.5K for 12, 46K for 20, 151K for 30 and 354K for 40.
- **Biome eggs unlock:** Mossvale at the start, Coral Coast at level 4, Magma Rift at level 12 + base level 2, Frost Shelf at 20 + base 3, Storm Peaks at 30 + base 4, and Moonfall at 40 + base 5. You also need an incubator tier that fits the egg.
- **Achievements:** 18 goals (hatch counts, adults raised, steals, discoveries, rare finishes, upgrades, incubators, walking, spins, lifetime cash), each paying XP and Luck Wheel spins. Listed in the Progress menu.
- **Rebirth** is now pure prestige: it resets cash, gives +10% earnings for good and 3 spins, and keeps everything else. It no longer unlocks biomes.

### 7.3 World

- **The island:** a round grass island with a sandy beach and the sea around it, and a cobblestone plaza under the hub and conveyor. Stone paths run from each plot to the plaza.
- **Hub:** the hatchery tunnel over the belt, with 12 egg-lantern lamp posts around the loop.
- **Biome zones:** one walled zone in each gap between plots (Mossvale, Coral Coast, Magma Rift, Frost Shelf, Storm Peaks, Moonfall), 88 studs across. The gate faces the hub and shows the requirement (the same Hatcher Level + base level that unlocks the biome's eggs); it glows green once you qualify. Locked-out players are bounced back out.
  - **Harvest nodes:** 7 glowing crystal nodes per zone (hold E). Each gives 1–2 of that biome's Essence and regrows after 40 s. Nodes are shared, so it pays to get there first.
  - **Shrine:** spend Essence on a **forged egg** of that biome (15) or on the biome's **blessing** (8): Mossvale cash (3 min of income), Coral +3 spins, Magma halves the time left on every incubating egg, Frost ×5 luck on the next egg, Storm XP (400 × level), Moonfall ×25 luck on the next egg.
  - **Set pieces:** each zone has 2–3 landmark props (`src/server/SetPieces.luau`), placed clear of the nodes, the shrine and the gate path:
    - Mossvale: a glowing fairy ring of giant glowcaps around the middle and a giant hollow stump.
    - Coral Coast: a tide-pool rock arch over the gate path and a giant clam with a glowing pearl.
    - Magma Rift: a smoking lava vent behind the middle and a cluster of obsidian spikes.
    - Frost Shelf: an ice arch over the gate path and a boulder frozen in ice.
    - Storm Peaks: a lightning-rod crag that gets struck every 6–14 s, and two wind-bent spires.
    - Moonfall: a moon-crystal monolith (plus a smaller one) and a meteor crater.
  - **Set-piece events** (`ZoneEventService`, tuning in `Config.Zones.events`): the zones take turns. Every ~50 s the next zone's landmark does something, so each zone's event comes round every 5 minutes, always in the same order.
    - It's announced 10 s ahead to players who have that zone unlocked.
    - Most prizes are first-come, which pulls players away from their bases and opens steal windows.
    - Luck prizes charge the next egg like the Luck Wheel does: the best unspent charge counts, and a player who already holds more gets spins instead.

    | Zone | Event | Prize |
    |---|---|---|
    | Mossvale | Glowcap bloom, 20 s | Everyone inside the ring gets 1 Moss Essence every 4 s (about 5) |
    | Coral Coast | The clam opens and a pearl rolls out | First to grab it: +2 spins. A 10% Black Pearl gives ×10 luck instead |
    | Magma Rift | The vent erupts 8 Ember shards | 2 Ember Essence each. A 15% gold shard gives a free Forge Heat (6 Essence if no egg is incubating) |
    | Frost Shelf | The boulder cracks; players break it together (8 holds) | Every helper gets 3–5 Frost Essence, plus a 25% chance of ×3 luck |
    | Storm Peaks | A huge strike on the crag | Crystals within 28 studs regrow and pay ×3 for 30 s |
    | Moonfall | A meteor lands in the crater | First to grab the moonstone: ×10 luck (+3 spins if already lucky) |
  - **Later (owner's ideas, 2026-09-30):** taming wild creatures, training, biome shops, and larger biomes. Essence is the natural currency for all of them.
  - **Release:** unwanted or duplicate creatures can be released from the Creatures menu for their biome's Essence (by rarity × stage: Baby ×1, Juvenile ×2, Adult ×3), plus Luck Wheel spins for Legendary and up. Selling for cash is still there.
- **Lighting:** atmosphere, bloom, sun rays, clouds and a slight color grade. During moon events the whole world is tinted in the moon's color, and the banner says what the event does.

### 7.4 Daily rewards (retention)

Built 2026-09-30: `Config/Daily.luau`, `DailyService`, and the Daily menu (a red dot while a reward is waiting; it opens by itself once per session). Days are UTC days.

- **Login streak (7-day cycle):**

  | Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 ★ |
  |---|---|---|---|---|---|---|---|
  | Reward | 2 spins | 10 min of cash | ×3 luck | 20 min of cash | 3 spins | 15 min ×2 growth | ×10 luck + 5 spins |

  Claiming on consecutive days walks the cycle, then it repeats. Missing a day restarts at day 1. Cash rewards are minutes of the player's own income (at least $500), so they stay useful at every stage.
- **Daily quests:** 3 a day, picked by weight from: hatch 8 eggs, buy 10 eggs, spin the wheel 3 times, walk a creature 5 minutes, collect 20 minutes' worth of income, harvest 6 Essence nodes, raise a creature to Adult, steal a creature.
  - Progress is the growth of a lifetime stat since the quest was given, so every way of doing it counts. Rewards pay the moment a quest is done.
  - Finishing all three pays +2 spins and ×5 luck. One swap per day replaces a quest you don't want (a peaceful player can swap out the steal).

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

Built 2026-09-30 (`Config/Monetization.luau`, `MonetizationService`). Prices are suggestions; ids stay 0 until each item is created in Creator Hub, and items with id 0 don't show in the live Shop.

- **Game passes (bought once):**

  | Pass | R$ | Effect |
  |---|---|---|
  | 2× Cash | 249 | Every creature earns ×2 |
  | VIP | 349 | Gold VIP tag over the base, +10 storage, +10% cash |
  | Auto-Collect | 149 | Earnings go straight to the wallet |
  | Extra Nursery | 99 | +1 protected nursery slot at every base level |
  | Longer Lock | 99 | Laser lock lasts ×2 |
  | Offline +8h | 79 | Offline cap 8 h → 16 h |

  VIP changed from "VIP Plot (+10 pedestals)": pedestal count is set by base level and plot size, and 10 more don't fit a low-level plot, so VIP gives storage and cash instead.
- **Developer products (bought repeatedly):**

  | Product | R$ | Effect |
  |---|---|---|
  | Server Luck | 99 | Headline product. Epic+ odds ×2 on every egg rolled in the server for 15 min, buyer announced. Each repeat adds 15 min and +1 (max ×5) |
  | Growth Elixir | 49 | Your creatures grow ×2 for 30 min, stacking with walking |
  | Skip Hatch | 29 | Hatches every incubating egg now; with none incubating, the next egg placed hatches instantly |
  | Cash Pouch | 29 | 10 min of income, at least $1,000 |
  | Cash Chest | 149 | 90 min of income, at least $10,000 |

  Instant Restock was dropped: the conveyor has no stock to restock.
- **Paid random items (Roblox policy):** eggs are random, and Robux buys cash (Cash Pouch, Cash Chest) and better odds (Server Luck), so the game has paid random items. Two things follow:
  - Every egg shows its full odds before buying (§3.1, odds panel).
  - Players whose `PolicyService` policy has `ArePaidRandomItemsRestricted` never see those three products (`paidRandom = true` in `Config/Monetization.luau`). Until the check answers, or if it fails, they count as restricted. A purchase that goes through anyway is still granted, because Robux was charged. Test it with `StudioDebug:Invoke("perk", "restricted")`.
- **Receipts:** each purchase id is recorded in the player's data and only confirmed to Roblox after a save containing it, so a crash can't double-grant or lose a purchase. Pass ownership is checked with Roblox on join and also stored in data.
- **Free perks and rewards** (built 2026-09-30, `RewardsService`, Shop → Free rewards):
  - **Codes** (`Config/Codes.luau`): once per player, paying spins, luck charge, cash or Essence, with an optional expiry date. Launch codes: HATCH (3 spins), MOONEGG (×3 luck), SNATCH ($1,000). Like-goal codes are added to the table when a goal is hit.
  - **Roblox group:** members earn +5% cash, and joining pays 3 spins once. Joining uses the in-game prompt. The group id stays 0 until the group exists.
  - **Roblox Premium:** +10% cash. Premium Payouts pay for Premium members' time in the game, so this perk helps keep them.
  - **Rewarded video ad:** ×2 cash for 15 minutes a watch, stacking to 60 minutes (the `AdBoost` product). Changed from "a free egg" because Roblox forbids random ad rewards. Roblox only serves ads to public games with 2,000+ monthly visitors and an ID-verified owner, and the button stays hidden until then.
- **Other income:** Premium Payouts (automatic), private servers.
- **Analytics** (`src/server/Analytics.luau`, Creator Hub → Analytics):
  - Economy: every cash source and sink, with an item SKU.
  - Onboarding funnel: joined → bought an egg → placed it → hatched → collected cash → upgraded the base.
  - Progression: Hatcher Level and base level.
  - Custom events: Hatch (rarity, biome, finish), Steal, Rebirth, CodeRedeemed, GroupReward, AdWatched.

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
| 6 | Launch v1 with every biome, unlocked through Hatcher Level and base level (owner, 2026-09-30) |

Updates after launch add creatures, maps and features: taming, training, biome shops and larger biomes are on the owner's list.

## 12. Open questions

- Should feeding duplicates to speed growth replace selling them, or sit alongside it?
- Should trading ship at launch or in the first update? (Leaning toward the first update, with trade locks.)
- The final game name: "Hatch & Snatch" is a working title.

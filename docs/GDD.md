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
- **6 base plots** are arranged in a ring around the loop, so every base is equally close to the eggs and to each other. Each plot grows into a **fortress** (§6.1) and has:
  - pedestals (10 to start, upgradeable to 30, plus vaults and hiding spots),
  - a laser-gate **base lock** with a countdown light,
  - a cash collector, an incubator rack and a **Command Terminal**,
  - walk-over **buy pads** for every upgrade,
  - **nursery** slots.
- **Layout** (owner-approved concept, 2026-10-01): the reactor and belt in the middle; the ring of fortresses; a ring of six walled biome zones, open to the north and south; and the open land out to the beach with the landmarks and the two station plazas (§7.3).
- **Day and night** (owner, 2026-10-02): 12 minutes of day, then 4 of night, the same for everyone (each client runs the clock from the server's time; `Shared/DayNight.luau`, `DayNightController`). Dusk and dawn glow warm; the night is moonlit blue and bright enough to play, with stronger bloom so the castles' lanterns, braziers, crystals and niches glow like the concepts. By day only kit lights within 110 studs stay on (230 at night). The bright themes' lights are scaled down (`lightScale`: Diamond 0.5, Ice 0.6, Moss 0.5, Golden 0.8; Moss's glowing caps are a deeper green, as brighter ones hazed the whole hold), as they washed out their own walls at night.
- **The Moon Egg** hangs in the sky. Its color is the server's event alarm (section 8). Long-term, a big update lets the moon hatch, releasing Lunaris.
- **Biome eggs:** the conveyor carries eggs from biomes the player has unlocked through rebirths, and the map's look expands with them. The biomes, in order: Mossvale Forest → Coral Coast → Magma Rift → Frost Shelf → Storm Peaks → Moonfall.

## 3. Core loop

```
buy egg from the belt → carry it home → place it in an incubator (optional Luck Wheel spin)
    → hatch reveal → creature sits on a pedestal earning cash/sec → grows Baby → Juvenile → Adult
    → XP from all of it raises your Hatcher Level → new biome eggs unlock
    → spend cash on more/better incubators, base upgrades, castle designs, pricier eggs
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
- **Luck Wheel:** a physical wheel stands at the North Commons, out past the biome ring (§7.3). Walk up and hold E to spend a spin; everyone nearby watches it turn. Prizes: ×2 luck 30%, cash (5 min of income) 24%, ×3 luck 18%, +2 spins 12%, ×10 luck 12%, ×25 jackpot 4%. A luck prize charges your **next egg** (bought or forged); its Epic+ weights are multiplied by the luck. Spins come from playtime (1 per 20 minutes, up to 10 banked), achievements, rebirths, the Coral Coast shrine and releasing rare creatures.
- **Odds panel** (paid random items, 2026-10-01): while an egg's Buy prompt (or a shrine's Forge prompt) is on screen, a panel lists every species, finish and genetic mutation that egg can give, with percentages that add up to 100%. It updates live with the player's luck charge, Server Luck and moon events. Everything is rolled the moment the egg is bought, with exactly those odds (`Shared/Odds.luau`, `OddsController`), so Skip Hatch and incubator upgrades never change what's inside.
- **Hatch reveal:** a case-opening reel of creature cards from that egg's odds slows down and lands on what hatched, with rare cards teased right beside it. Then a big rarity-colored reveal shows the creature spinning; Mythic and rarer flash the whole screen, and the server announces it once the reveal ends. Under its name a line always says what it was born with and what each pays ("✨ Gold finish ×1.5 · 🧬 Albino ×10", or "No finish · No mutation"; owner, 2026-10-03; `Shared/Genetics.luau`).

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
- **Walks:** you can take one creature for a walk (R, or Walk in the Creatures menu). It follows you with the bounding run while you move and sits beside you when you stop. A walked creature can't be stolen and grows 2× faster, or **4× inside its own biome's zone** (owner, 2026-10-03: "a way to speed up the growth rate ... walking or taking them into biomes"; Junk creatures have no zone); it still earns from its pedestal. (Owner, 2026-10-03: AFK-walking your best creature is fine; it shows active players, and the rest of the base can still be raided.)
- **The run itself is a slow bound with a hop:** front paws reach together, back legs push off together, there's a short airborne arc, and a squash on landing.

- **By stage:** babies bounce too much and occasionally face-plant; adults land with heavy, powerful bounds, a thud, and a puff of their element (dust, embers, frost, sparks).
- **By body shape:** hoppers hop, heavy creatures stomp, and low-slung creatures scurry.
- **How it's built:** one hand-keyed bound animation per skeleton family, plus a shared procedural movement script. It handles hop height, landing squash, trailing tail and ears, head tracking toward nearby players (especially thieves), random blinks, and wandering around the base.

## 5. Rarity layers (the collection)

1. **Species rarity:** see the roster. Everyone can read it on sight (owner, 2026-10-01; `Shared/RarityLooks.luau`):
   - **Halo:** every creature has a soft halo of its rarity color behind it, stronger with each tier and visible from across the island.
   - **Stardust:** from Uncommon up, sparkles in the rarity color rise off the creature, thicker and brighter with each tier (Uncommon 1/s up to Legendary 8/s, then Mythic 16, Celestial 20, Cosmic 26 and Secret 32, which bloom).
   - **Color conversion (Mythic and up):** the creature's texture is tinted toward its rarity color (Mythic crimson, Celestial pale blue, Cosmic violet), keeping its details and eyes. Secret shifts slowly through the rainbow. A finish replaces the tint; the halo and stardust stay. Species whose own colors fight the tint have an override: Glacierion keeps its white ice (crimson turned it into a red lion) and gets a white light (the crimson one still turned it pink in shade), and Solarion gets warm gold instead of pale blue (which turned its mane olive).
   - Lights are added from Epic up. The name tag shows the rarity under the name.
2. **Genetic mutations** (owner, 2026-10-01: "like Galaxy, other people will want them; by far the most desirable yet rarest", and they must "look professional and clean"). Rolled when the egg is bought, at most one per egg. Each is rarer than a Galaxy finish, stacks with any finish and multiplies earnings on top of it (an Iridescent Prismatic earns ×600). `Config/Mutations.luau`, looks in `Shared/MutationLooks.luau`.

   | Mutation | Odds | Earnings | Look |
   |---|---|---|---|
   | Albino | 1 in 8,000 | ×10 | Snow-white coat that keeps its fur detail, pink skin in the creases, pale element, ruby-red eyes |
   | Melanistic | 1 in 8,000 | ×10 | Jet-black coat with its pattern ghosting through; the element and eyes blaze against it |
   | Piebald | 1 in 12,000 | ×12 | White patches laid out like a real animal's: face, chest and paws first, the spine keeps its color |
   | Chimera | 1 in 12,000 | ×12 | Split down the middle: its normal self on one side, the opposite on the other, one odd-colored eye |
   | Iridescent | 1 in 100,000 | ×40 | An oil-slick film whose colors follow the body's curves; in game it also drifts slowly (the rarest roll in the game) |

   - **Skins, not paint** (owner, 2026-10-01: "immensely more detail... Albino needs red eyes"; v2 approved the same day, Chimera replacing Leucistic, which read as a paler Albino). Finishes change what a creature is made of; mutations change how it was born. Each mutation is a texture made offline from the model's own texture (`tools/mutations/`): the patterns are laid out on the 3D body (no seams), and the eyes are picked on face renders and recolored on purpose. In game they live in `ReplicatedStorage.MutationSkins.<Model>.<Mutation>` (a SurfaceAppearance, or an image id for a plain MeshPart). A model without its skins falls back to the v1 solid looks (Leucistic saves became Chimera).
   - Plus a thin ring in the mutation's accent color round the rarity halo (readable across a base), its name in that color on the nameplate and in the Creatures menu, and a few soft glints. No outlines or particle clouds.
   - **On a finish** the texture is already gone, so the mutation shifts the finish's color instead: a black-gold Melanistic, a white-gold Albino. Piebald patches and a lighter Iridescent sheen go over any finish.
   - **Hype:** every mutated hatch is announced to the whole server with its odds ("🧬 Connor hatched an ALBINO Emberlynx! (1 in 8,000)"), the hatch reveal gives it a banner and a second flash in its accent color, and the first one earns the "One in Ten Thousand" achievement (3,000 XP, 5 spins).
   - The odds panel lists them before purchase (paid random items). Rerun the economy sim after changing them; the 2026-10-01 rework moved pacing by about a day at most.
3. **Finishes**, the flashy layer. Each is a material and particle swap, so no new models are needed:

Odds are **per pull**: every egg rolls its finish, whatever species hatches (loosened 2026-10-03 for Gold to Molten; Galaxy and Prismatic stay).

| Finish | Odds | Earnings | Look |
|---|---|---|---|
| Normal | — | ×1 | — |
| Gold | 1 in 8 | ×1.5 | Gold with sparkles |
| Chrome | 1 in 25 | ×2 | Mirror finish that reflects the world |
| Diamond | 1 in 80 | ×3 | See-through crystal that bends light |
| Molten | 1 in 250 | ×5 | Glowing lava cracks, drips embers, sizzles |
| Galaxy | 1 in 4,000 | ×8 | A window onto space: a starfield that holds still on screen while the creature moves through it (`FinishLooks` sky texture, slid each frame by CreatureAnimator; the image is `assets/textures/galaxy_sky.png`), plus a tiny orbiting planet; server announcement |
| Prismatic | 1 in 16,000 | ×15 | Color-shifting glow and a rainbow trail; server-wide fanfare |
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
- While someone is in your base, you can't pull pedestal creatures into storage, the nursery, a walk or another floor (menu or in-world prompt).
- The server times every Steal hold (from when the button went down), so an exploit that fires the prompt instantly gets nothing.
- Floors and vaults (§6.1): a creature can only be grabbed from its own floor, and one in a vault only from inside the room while its door is open.
- A locked gate that pushes a thief out takes the owner's creature back.
- Both saves are written right after a delivery.

### 6.1 Base upgrades and the Castle Designer

- **Buying:** every upgrade is a walk-over **buy pad** in the front yard (owner, 2026-10-01; `BaseKit.luau`, `BaseService`). Stand on one for 0.6 s to buy; step off to buy again, so walking past never buys anything. Eight pads, one each for the next base level, security level, floor, vault and hiding spot, then the three cheapest decor or security items open to you. A pad only shows once its step is open, green when you can afford it, red when not.
- **Command Terminal:** a console with a monitor by the lock button (it replaced the old upgrade gem). Its screen shows the base's tier and counts, and its prompt opens the **Base menu** (it has no menu-bar button): status and what's next, decor switched on or off, the security items, and the Castle Designer.
- **The fortress** (`Fortress.luau`; owner, 2026-10-01): the walls round the plot grow with the base level, free with each upgrade. From the Stockade up the walls are too tall to jump, so the gate (where the laser lock is) is the only way in.
  1. **Camp:** a picket fence and a timber arch.
  2. **Stockade:** log palisade walls and wooden watchtowers at the back corners.
  3. **Keep:** stone walls with battlements, round stone towers at the back and a stone gatehouse.
  4. **Fortress:** taller walls, four towers with slate cone roofs and flags, braziers at the gate.
  5. **Citadel:** pale stone and gold, crystal-tipped spires.
  - The Castle Designer sets the stone, the roofs, the banners and the glow (below). Tower and gatehouse models replace the part-built ones when imported (a 9-stud walk-through arch between invisible colliders); they carry the Classic look in their textures, so they are used only for the Classic design and any other design builds its towers from parts in its own colors. The gatehouse model is turned to face out whichever way it was imported. At the Citadel a custom design also recolors the gold trim (tower bands, wall caps, gate trim) to its banner color.
  - The floors above are a **stone keep**: solid stone walls (the glass boxes looked see-through and unfinished), an arched front with balustrades so the creatures show, stone pillars, battlements on the Top Floor. Tall arches run across the ground floor's front under the Second Floor too, and the ramps are drawn as stone stairs (the slope underneath is what players walk on).
  - **Display niches** (owner, 2026-10-02: in the concepts every creature stands in its own alcove, "spacing and second story spots"): every pedestal but the vaults' and hiding spots' has an arched stone niche behind it with a glowing panel. It glows in the **rarity color of the creature standing there**; an empty one shows dim warm stone with a faint light (empty neon panels bloomed into white blobs at night). Each floor has 9 spots (owner, 2026-10-02: "more spots on second and third floors"): 5 just inside the front arches, so the upper creatures show from outside like the concepts' two rows of alcoves, and 2 along each side wall facing in, clear of the vault doors (the Top Floor has no front posts: the Second Floor's side and back walls rise to meet its slab instead, so nothing sticks out along the walls). A walkway runs in front and gaps between the niches lead to the back.
- **Base level 1 to 5:** 60K, 25M, 5B and 800B. Each level:
  - widens and deepens the plot (64×56 up to 88×80 studs), so thieves have a longer run out;
  - adds ground pedestals at levels 2 and 3 (10 → 15 → 20); levels 3 and 4 open the floors above. The ground's spots stand in two wings either side of an open hall down the middle (owner, 2026-10-02: "far too cramped together on the bottom floor ... spots on the left and right of the center"): two columns a side, 13 studs apart, in rows 12 apart, with the theme kit's centerpiece at the hall's far end;
  - adds 15 s to the laser lock (+60 s at max).
- **Floors** (owner, 2026-10-01; Base menu, bought in order): the Second Floor (800M, needs base 3) and the Top Floor (60B, needs base 4) each add 9 pedestals one story up (18 studs; 38 pedestals in all). Higher floors are harder to steal from:
  - Stone walls are too tall to jump, so thieves walk up the ramps (right side to the Second Floor; the Top Floor's leaves the Second Floor at its back left, so a thief crosses the whole floor, and climbs forward along the left wall) and carry the creature all the way back down.
  - The Steal hold is +50% per floor up, timed on the server.
  - A grab only works from the creature's own floor, not from below.
  - Creatures menu → **Move ▾** sends a creature to storage, a floor or a vault (swapping with the least valuable one there when it's full). **⬆ Rarest up top** sorts every pedestal creature by value into the vaults first, then the Top Floor, the Second Floor and the ground.
- **Vaults** (bought in order; 2 per floor, in its back corners): Vault 1 1.5B and Vault 2 3B on the Second Floor, Vault 3 120B and Vault 4 250B on the Top Floor. Each holds one creature (it earns like a pedestal) behind a door:
  - Hold E at the door to lock it for 3 minutes (×2 with Longer Lock; moon events scale it like the base lock), then it recharges for 1 minute. The sign over the door shows the countdown.
  - While locked, nothing inside can be stolen. A locking door pushes everyone else out, and a thief caught inside drops what they took.
  - Unlocked, the Steal hold is ×2 on top of the floor's, and only works from inside the room.
  - Auto-Lock (security 3) locks every charged vault too when an intruder walks in.

- **Security levels** (pad): three one-time upgrades — Intruder Alarm 40K (you're told when someone walks into your base and they glow red; a bell appears by the left wall), Tripwire 10M (thieves carrying your creatures move 25% slower inside your base), Auto-Lock 2B (the laser lock turns itself on when an intruder enters, if it's off cooldown).
- **Security items** (pads; `Config.BaseBuilds`). The owner's rule: every measure runs on a timer or a recharge, so no base is ever unbreakable; a patient thief can always wait one out.
  - **Spike Strip** 5M (base 2): spikes inside the gate root the first intruder for 1.5 s, then reset for 40 s.
  - **Searchlight Tower** 400M (base 3): a thief who grabs one of your creatures is lit up and tagged "THIEF!" for everyone for 10 s (30 s recharge).
  - **Ramp Gates** 6B (base 3, needs the Second Floor): pull the lever by the ramp to bar both ramps for 45 s, so nobody gets up or down (90 s recharge).
  - **Net Ballista** 40B (base 4): hold E at it to net the nearest thief carrying your creature within 80 studs; they drop it and it goes home (2 min reload).
- **Hiding spots** (pads, bought in order): the Haystack 3M (base 2), Barrel Pile 300M (base 3), Hedge 8B (base 4) and Secret Chest 150B (base 5) stand inside the side walls. Each holds one creature out of sight (Creatures → Move; slots 51-54), and it still earns.
  - Thieves hold E for 3 s to **search** any spot. An empty one is a decoy ("Nothing in there but hay!"); an occupied one gives up its creature under the normal grab rules (locked base, new-player protection and so on).
  - Hidden **Mythic and rarer** creatures give themselves away with a burst of sparkles in their rarity color every ~12 s, so an ultra-rare is never hidden for good.
  - Hiding spots aren't auto-filled and Rarest up top leaves them alone; moving a creature in or out isn't allowed while an intruder is in the base.
- **Decor** (pads; switch each on or off at the terminal; `BaseDecor.luau`): Camp Supplies 15K, Wall Torches 40K, Campfire 150K, Flower Planters 600K, Banners 2.5M (theme colors), Training Yard 8M, Stone Well 40M, Lantern Path 150M, Fountain 900M, Guardian Statues 4B (stone statues of your two rarest creatures by the gate), Moat & Drawbridge 30B, Royal Gold Trim 350B (base 5).
- **Castle Designer** (owner, 2026-10-01: "ice, fire, light, dark, red, blue, green, rainbow, tons of combos"; `Config/CastleDesigns.luau`, Base menu at the terminal). It replaced the nine fixed base themes. A base's look is seven picks that mix and match (prices repriced 2026-10-02 from the economy sim: late options cost tens of hours of income, never a thousand):
  - **Stone** (walls, towers, keep): Classic free, Mossy 25K, Sandstone 120K, Basalt 30M, Obsidian 120M, Ice 6B, Storm Slate 12B, Moonstone 90B; Fortress Stone 2B, Marble 10B, Royal Granite 30B (base progress).
  - **Roofs** and **Banners** (the same colors each): Royal Blue, Crimson and Forest Green free; Sunflower 40K, Lagoon Teal 150K, Coral Pink 250K, Ember Orange 30M, Charcoal 60M, Snow White 6B, Ice Blue 8B, Thunder Yellow 10B, Gold foil 50B, Moon Lilac 60B (the Moon Palace's roofs), Void Purple 70B.
  - **Glow** (laser gate, vault doors, spire and royal crystals): Laser Red free, Toxic Green 50K, Ocean 150K, Fire 30M, Ice 6B, Light 8B, Lightning 12B, Royal Gold 30B (base), Dark 80B.
  - **Floor:** Wood free, Sand 100K, Basalt 25M, Glacier 5B, Slate 10B, Moon Pebble 60B; Cobblestone 1B, Marble 8B, Dark Granite 25B (base).
  - **Grounds** (the plants and rocks round the walls): Forest free, Meadow 60K, Coral Shore 100K, Volcanic 25M, Frozen 5B, Stormy Crags 10B, Lunar 60B; Rocky 1B, Crystal Garden 10B (base).
  - **Theme** (owner, 2026-10-01/02: themes "need physical assets that add a feeling of I earned this", and must look "exactly like" the approved concepts `assets/tripo/concepts/Theme*.png`; late ones "should take quite a while to earn... 1000 hours is too long though"). A kit of real 3D pieces built onto the castle (`src/server/CastleKits.luau`): Green Hold 25M, Coral Fort 150M, Fire Keep 2B, Ice Castle 15B, Storm Spire 75B, Moon Palace 750B, then Golden Palace 5T (rebirth 3), Diamond Citadel 16T (rebirth 5) and Void Throne 30T (rebirth 6). Each kit brings:
    - a **cap** on every tower in place of the roof (shell spire, obsidian spire, ice spire, tesla coil, gold spire, diamond crown; Ice's front towers wear huge crystal clusters) or the cone roof dressed (Moon crescents and inset gems, Void's black crystals jutting out, Moss's moss and ivy), ringed by six **growths** on the crown;
    - **growths** that grow out of the castle rather than sit on it (owner, 2026-10-02: the first coral "looks lazily sat upon the castle"): leaning clusters sunk into the stone at irregular spots, with pieces sprouting from the wall faces, big bouquets round every tower's cap, clusters crowning the keep's vault rooms and over its balconies. Coral grows in six tints from pale models (tall staghorns for the big pieces, branches, fans and tubes to fill in); Moss's mushrooms in small clusters; Ice, Diamond and Void crystals gather near the towers and the gate; Fire's spikes crown every other merlon; Storm's lightning rods stand in a row;
    - Coral's walls and towers are **set with starfish, scallops and conches** in bright tints, with a sea-glass band under the battlements, a sea-blue mosaic band at the foot, coral beds either side of the gate, little coral gardens along the walls' feet and a pink scallop over the gate; and every theme's **lanterns or braziers stand on the battlements** every few merlons;
    - **banners** on every tower and on the gatehouse, each with the theme's **emblem** (starfish, flame, snowflake, lightning bolt, leaf, constellation, crown, diamond, rune), a **band of another stone** round the feet (Coral's blue-gray, Fire's glowing cracked lava, Golden's marble, Moss's mossy stone), and **tower dressing**: lava cracks (Fire), ivy (Moss), rune columns (Void), icicles and snow (Ice), diamond inlays and gold rings (Diamond), marble rings (Golden), copper rings (Storm);
    - its **light** everywhere: sconces, glowing windows, a light in each tower crown, glowing crystals and mushrooms, and a **glowing raised portcullis**;
    - the **gatehouse**: two tall towers with banners, braziers or lanterns on top (four on Moon), the gate's crest or arch (ice arch, crescent arch, crown shield, diamond crest), gems round the gate (Diamond), a great glyph (Void), lightning across it (Storm), and at its feet the front braziers (Fire's dragon heads), statues (Golden's lions, Moss's giant mushrooms), cypresses and flower boxes (Moss), a red carpet (Golden);
    - the **ground** round the castle in the theme (sand, basalt, a frozen lake with ice floes, slate, moss, pebble, marble) and **basins** at the front towers (tide pools, a lava lake with crust, swamp water with lily pads), with clusters at the tower feet (anemone rocks, lava rocks, ice crystals, roots, rune pillars, Moss's giant glowing mushrooms);
    - the **keep** dressed to match: growths on its battlements, icicles and snow on its arcades and floors (Ice), ivy and moss (Moss), lava cracks (Fire), rune columns (Void), pearl strings (Coral), giant mushrooms on its top floor (Moss);
    - the keep's **interior** (owner, 2026-10-02: "still need interior detail"): a theme piece at the foot of every creature's niche and a crown on every other arch, a big **centerpiece** at the back of each floor (Coral's giant pearl clam, Fire's lava cauldron, Ice's frost brazier, Storm's tesla coil, Moss's giant glowing mushroom, Moon's crystal, Golden's treasure chest, Diamond's geode, Void's eye orb) and **hanging lights** on chains under each floor (pearl lanterns, lava cauldrons, ice lanterns, thunder-stones, mushroom lanterns, moon lanterns, crystal chandeliers, eye orbs);
    - **variety** (owner, 2026-10-02: "more variations of assets so it's not the same repeated asset over and over"): each theme mixes several models in its growths, gardens and interiors. Coral adds clams and oysters with pearls, brain coral, anemones, urchins and barnacle rocks; Moss tall glowing mushrooms, shelf-fungus logs, ferns and wildflowers; Fire magma crystals, dragon skulls and cauldrons; Ice snowy pines, ice shards and frost braziers; Storm storm crystals, small coils and cracked thunder-rocks; Moon crystal shards, moon flowers and lamp posts; Golden urns, coin piles and treasure chests; Diamond gem piles, geodes and chandeliers; Void eye orbs, thorn trees and obelisks. Clams, oysters, urchins and barnacle rocks keep their own colors; the pale pieces are tinted;
    - **set pieces:** Moss's giant trees, Fire's lava falls and smoke plumes, Ice's icicles and snow drifts, Storm's chained thunder-stones, coils crackling with lightning that jumps up into the storm cloud and down onto the keep, Moon's crystals ringing every roof and the keep's giant crescent with violet mist, Void's portal, floating rocks and glowing chains slung between the towers, plus each theme's drifting particles. `CastleFxController` animates the floating pieces, the arcs, the portal and the storm flashes near the camera.
    - **Diamond Citadel is diamond throughout** (owner, 2026-10-02: "clear diamond crystals... fully diamond structure, walls and all"; it had read as the Ice Castle): the Diamond stone (rebirth 5) is a cut-diamond brick texture on every wall, tower, gatehouse, keep piece and niche (owner, 2026-10-02: "a diamond texture rather than actual diamond ... imprint iridescence in the skin of the castle as we did with the creatures"): a MaterialVariant on Salt (`Config/Materials.luau`, maps from `tools/textures/make_diamond_tex.py`) with faint opal tints baked in, mid-tone so the sun doesn't blow it out, and a slow pastel sheen drifting across it on the client (`RainbowController`, tag `Iridescent`). Glass with a shine glared day and night, and plain white Salt still glared under the low sun. Its torches, gate glow and niche lights follow the kit's `lightScale` like its own lights (at full strength they hazed the front wall white by day and fogged the keep at night); its crowns, clusters and gem piles are clear colorless glass with rainbow prism glints round the crowns' cores; clear crystals crown the battlements; its light is white, not blue.
    - Every theme's gardens line the outside of its walls (not only Coral's).
    - Every piece has a part-built stand-in or is skipped, so a castle still reads as its theme before the models are imported. The pieces lose their metalness map on import (`organize_imports.luau`): metal reflected the night sky and turned the shell spires navy and the gold spires near-black. Pieces that glow in the concepts (Moss's mushrooms, Moon's crystals) turn to solid neon, crystal crowns (Ice, Diamond) glow from a core inside, and the client switches off kit lights more than 230 studs from the camera.
  - **Rebirth ladder** (owner, 2026-10-01: "the more desirable and harder to get ones should require multiple rebirths to generate return players"). The flashiest looks unlock one rebirth at a time:
    | Rebirth | Unlocks | Price |
    |---|---|---|
    | 1 | Molten roofs and banners (glowing neon) | 500B each |
    | 2 | Rainbow roofs and banners (the color cycles) | 1.5T each |
    | 3 | Solid Gold stone; Gold Tiles floor; Golden Palace theme | 3T; 2T; 5T |
    | 4 | Diamond roofs and banners (foil); Rainbow glow | 5T each; 6T |
    | 5 | Diamond stone; Diamond floor; Diamond Citadel theme | 10T; 6T; 16T |
    | 6 | Void Steel stone; Void Glow roofs and banners (neon); Void Throne theme | 15T; 12T each; 30T |
    - The rebirth stones (Solid Gold, Diamond, Void Steel) also twinkle on the towers.
    - The Rebirth menu shows what the next rebirth unlocks, and rebirthing announces it.
    - Simulated pace (150 days, free to play): a 3 h/day player reaches rebirth 1 around day 41, rebirth 3 around day 60 and rebirth 5 around day 117; an 8 h/day player reaches them around days 22, 33 and 60, and rebirth 6 around day 92. Rebirth 6 is the long-term goal, and more steps can be added above it later.
  - Biome options open with that biome's eggs (Mossvale, Coral, Magma, Frost, Storm, Moonfall), the rest with base progress or a rebirth. Each is bought once and can be picked freely after; free options count as owned.
  - **16 presets** set every slot at once and buy whatever is missing in one payment (all of it must be unlocked): Classic, Red Bastion, Green Hold, Coral Fort, Fire Keep, Ice Castle, Light Citadel, Storm Spire, Dark Fortress, Moon Palace, Royal Vault, then the rebirth ones: Molten Keep (1), Golden Palace (3), Rainbow Castle (4), Diamond Citadel (5) and Void Throne (6). The nine theme presets match their concepts: stone, roofs, banners, glow, floor, grounds and kit together.
  - Old saves migrate: every theme a player owned becomes its stone, floor, glow and grounds options, and their active theme becomes their design (`DataService`, `fromTheme`).
  - Preview: `bash tools/preview/run_designs.sh <dir> [Preset ...]` renders the Citadel in each preset with the kits' real models where their GLBs are on disk (`NIGHT=1 VIEW=front` matches the concepts' camera and light); `bash tools/tests/run_designs.sh` checks the presets, options and unlocks.
- **Servers:** 6 players per server (6 plots); set Max Players = 6 in Game Settings.

## 7. Economy (retuned 2026-09-30 for multi-week pacing; tune in playtests)

| Rarity | Base cash/sec | Hatch time | Growth factor |
|---|---|---|---|
| Common | 1 | 10 s | ×1 |
| Uncommon | 3 | 20 s | ×1.25 |
| Rare | 8 | 45 s | ×1.5 |
| Epic | 18 | 2 min | ×2 |
| Legendary | 60 | 4 min | ×3 |
| Mythic | 400 | 8 min | ×4 |
| Celestial | 1200 | 10 min | ×5 |
| Cosmic | 3000 | 12 min | ×6 |
| Secret | 6000 | 15 min | ×8 |
| Junk | 30 | 1 min | ×1.5 |

- **Hatch times** (owner, 2026-10-03: "shouldn't be long at all"; were 30 s to 8 h) are for a Basic incubator; better tiers divide them by up to 4 (Cosmic). Skip Hatch now mostly matters for ultra-rares.
- **Growth times:** Baby → Juvenile takes 30 min × the growth factor; Juvenile → Adult takes 3 h × the growth factor.
- **Egg prices:** $150 × the biome's price multiplier (×16 per biome): Mossvale 150, Coral 2.4K, Magma 38.4K, Frost 614K, Storm 9.8M, Moonfall 157M (Junk 38.4K). New players start with $300 (two eggs).
- **Biome earnings multiplier:** creatures earn base cash/sec × their biome's earnings multiplier (Mossvale 1, Coral 4, Magma 16, Frost 60, Storm 220, Moonfall 300, Junk 1). It grows much slower than egg prices, so each biome is a bigger investment than the last.
- **Resulting payback** for a Common baby: 2 min in Mossvale, 8 min in Coral, 32 min in Magma, 2.3 h in Frost, 10 h in Storm and 15 h in Moonfall (whose eggs start at Rare). Adults earn ×6, and rare rolls pay back much faster.
- **Drop rates** (loosened 2026-10-03, owner: "pretty ruthless ... not too much for the extreme rares"): a biome egg is about 47–55% Common, 29–33% Uncommon, 17% Rare, 7–8% Epic and 3–4% Legendary (was 60/25/11/3/1); Mythic about 1 in 800, Celestial 1 in 2,500, each Cosmic 1 in 2,500 and the Secret 1 in 20,000 from **every** biome egg (§7.1). Iridescent stays 1 in 100,000. To keep the pacing, Epic and Legendary earn 18 and 60 (were 25 and 80) and base level 5 costs 800B (was 500B).
- **Rarity earnings are compressed** (Legendary is 60× a Common, not 250×). Players keep only their best creatures on pedestals, so a steep rarity curve made income explode after a few hundred hatches.
- **Rebirth** is the endgame sink (see §7.2): the first costs 1T, then 2.5T, 6T, 15T and 40T, and each one after that costs ×2.5.
- **Offline earnings** are capped at 8 hours; the cap can be raised by a game pass.

### Pacing (simulated)

`bash tools/sim/run_economy_sim.sh [runs]` plays the real config as an efficient free-to-play player, with no stealing, events or passes. Each day is one session followed by offline time. The player keeps the best earners on pedestals and spends half its income on the best eggs it can fit, one trip to the belt (25 s) at a time. Upgrades are bought cheapest-first. Median of 5 runs:

| Milestone | 1 h/day | 3 h/day | 8 h/day | 12 h/day |
|---|---|---|---|---|
| Coral Coast (Lv 4) | 9 min | 9 min | 9 min | 9 min |
| Base level 2 | day 1 | day 1 | day 1 | day 1 |
| Magma Rift | day 2 | day 1 | day 1 | day 1 |
| Second Floor | day 3 | day 2 | day 2 | day 1 |
| Vault 2 | day 4 | day 3 | day 2 | day 2 |
| Frost Shelf | day 7 | day 3 | day 2 | day 1 |
| Top Floor | day 14 | day 8 | day 4 | day 3 |
| Vault 4 | day 26 | day 13 | day 7 | day 5 |
| Storm Peaks | day 27 | day 10 | day 4 | day 3 |
| Base level 5 (max) | — | day 19 | day 10 | day 8 |
| Moonfall | — | day 22 | day 10 | day 8 |
| Everything bought (6 Cosmic incubators) | — | day 19 | day 16 | day 12 |
| First rebirth | — | — | day 17 | day 12 |

Before the retune, a 3 h/day player had bought everything in about 3 hours of play. Rerun the sim after any economy change. Paid boosts, events and stealing make real players somewhat faster than this baseline.

### 7.1 Ultra-rares (above Legendary)

| Tier | Where it rolls | Odds per egg | Species |
|---|---|---|---|
| Mythic | Any biome egg, any time | about 1 in 800 | Sylvanox (Mossvale), Lurehound (Coral), Pyrodrake (Magma), Glacierion (Frost), Stormgriff (Storm), Lunaris (Moonfall) |
| Celestial | Magma and Storm eggs, **only during a moon event** | about 1 in 2,500 | Solarion (Magma), Halosaur (Storm) |
| Cosmic | Moonfall eggs only | about 1 in 2,500 each (1 in 1,250 for either) | Quasarfox, Singularis |
| Secret | Hidden in **every** biome egg; shows as ??? in the Index | 1 in 20,000 | Capybaron (any biome egg; it earns like a creature of the egg's biome, `CreatureRecord.eggBiome`), Nullcat (Junk Egg, about 1 in 20,000) |

- Odds rework (owner, 2026-10-03: "50000 still feels crazy even 10k feels crazy for a single hyper rare especially if it can be stolen"): a 3 h/day player buys about 10,800 eggs in a month but only ~260 of them Mossvale and ~470 Moonfall, so the old Mossvale-only 1-in-50,000 Secret and the 1-in-10,000 Cosmics almost never came. Now, in the sim's egg counts, a Mythic comes every couple of days, a Cosmic every few weeks after Moonfall opens (about a week for an 8 h/day player) and a Secret in about two months (three weeks at 8 h/day).
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

- **The island** (rebuilt 2026-10-01 to the owner-approved concept; `WorldService`, `Landmarks.luau`): a round grass island 410 studs across the radius, with a sandy beach and the open sea around it. The sea is the border: an invisible wall at the beach's edge keeps players out of the water, with a gap only for the pier, where boats to future islands will tie up.
  - **Rings:** the hub and belt (plaza out to 56 studs, with a dirt ring path); the six fortresses (128 studs out); a ring road past the zone gates (196); the biome ring (205–295); an outer loop path through the open land (~334); the beach.
  - **Main paths** run north and south from the plaza, through the two gaps in the biome ring, out to the beach, with lanterns and signposts. Spur paths lead to the landmarks.
  - **Landmarks:** a striped lighthouse, a fishing hut and a walled pier on the northwest beach; a windmill, a stone circle and crumbling ruins in the north; a cliff waterfall in the northeast (running water: a falling particle curtain with mist, and foam drifting down the stream) whose stream runs along the coast to the sea under a footbridge, with a campsite beyond; a second stone circle and palms to the southeast; a campsite and pines to the south; a beached shipwreck on the southwest beach; oak and pine woods in the west; meadows and boulders everywhere. Each uses its imported model and has a part-built stand-in.
  - **North Commons:** the Luck Wheel, the Quest Board (opens Daily quests) and the Daily Chest (opens Daily rewards), with market stalls.
  - **South Event Grounds:** a board showing the moon event now on, or when the next one rises, with stalls and a campfire.
- **Hub:** the hatchery tunnel over the belt, with 12 egg-lantern lamp posts around the loop.
- **Biome zones:** walled sectors of the ring around the fortresses (`ZoneShape.luau` is the inside test), open to the north and south. East half from the north: Frost Shelf, Magma Rift, Storm Peaks; west half from the south: Coral Coast, Mossvale, Moonfall. Each is 90 studs deep and about 305 studs along its arc (mid-depth); its inner wall stands about 48 studs behind the fortresses' back towers, so the biomes show behind a built castle (owner, 2026-10-02: "more space between the bases and the biomes"). The gate faces the hub and shows the requirement (the same Hatcher Level + base level that unlocks the biome's eggs); it glows green once you qualify. Locked-out players are bounced back out.
  - **Harvest nodes:** 7 glowing crystal nodes per zone (hold E). Each gives 1–2 of that biome's Essence and regrows after 40 s. Nodes are shared, so it pays to get there first.
  - **Shrine:** spend Essence on a **forged egg** of that biome (15) or on the biome's **blessing** (8): Mossvale cash (3 min of income), Coral +3 spins, Magma halves the time left on every incubating egg, Frost ×5 luck on the next egg, Storm XP (400 × level), Moonfall ×25 luck on the next egg.
  - **Set pieces:** each zone has 2–3 landmark props (`src/server/SetPieces.luau`), placed clear of the nodes, the shrine and the gate path:
    - Mossvale: a glowing fairy ring of giant glowcaps around the middle and a giant hollow stump.
    - Coral Coast: a tide-pool rock arch over the gate path and a giant clam with a glowing pearl.
    - Magma Rift: a smoking lava vent behind the middle and a cluster of obsidian spikes.
    - Frost Shelf: an ice arch over the gate path and a boulder frozen in ice.
    - Storm Peaks: a lightning-rod crag that gets struck every 6–14 s, and two wind-bent spires, under a storm cloud covering the whole zone (owner, 2026-10-02: "bigger and more detailed"; `SetPieces.stormSky`): a dark flat-bottomed bank with billows on top, six thunderheads swelling out of it, ragged scud underneath and small puffs fraying its edges, with rain and mist along the arc and flashes inside it.
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
  - **Details card** (owner, 2026-10-03: "a screen under creatures where they can view each creature and its benefits/genetics"): tap a creature's name in the Creatures menu. It shows the creature spinning in its stage, finish and mutation; its genetics (finish and mutation with their earnings and odds, homegrown or stolen, and for a Secret the egg it hatched from); what it earns and the sum behind it (base × biome × stage × finish × mutation × homegrown × your boosts); what it sells for; its growth with a countdown, a bar and how to speed it up; and where it is.
- **Release:** unwanted or duplicate creatures can be released from the Creatures menu for their biome's Essence (by rarity × stage: Baby ×1, Juvenile ×2, Adult ×3), plus Luck Wheel spins for Legendary and up. Selling for cash is still there.
  - **Worth (the Sell price; owner, 2026-10-03):** an average Adult from an egg is worth half that egg, and better earners are worth more in proportion, so a rare hatch is worth many eggs (`Economy.sellValue`). It's never under its own earnings for 15 s (Baby), 2 min (Juvenile) or 10 min (Adult). So every grown creature is worth real money: a Lunaris (Moonfall Mythic, 900K/s) is worth 1.8B, where 15 s of earnings had made it 13.5M. A fresh Baby still sells for under half its egg on average, so buying eggs to sell never pays. The same worth ranks creatures for Rarest up top, full-floor swaps and the Guardian Statues.
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

### Admin panel

The owner's account (the user who owns the experience, or the owner of the group that does, plus any UserId in `Admin.luau`'s `ADMIN_USER_IDS`; anyone in Studio) gets an **Admin** button in the bottom-left corner. The panel applies to *me*, *everyone* or one player in the server:

- **Cash:** add or set any amount (type 2.5M, 1B, 3T, 1e15…), quick +1M/+1B/+1T. **Progress:** add XP, add Luck Wheel spins, set rebirths, give a biome's Essence.
- **Creatures:** spawn any species at any stage, finish and mutation, which plays the hatch reveal on each target's screen (or only play the reveal); give a biome's egg to the hands, random or set to hatch into the creature, finish and mutation picked above (owner, 2026-10-03); hatch every incubator now; grow every creature to Adult; move everything to storage.
- **Base:** max it (level 5, floors, vaults, security, hiding spots, every build), own every Castle Designer option, grant a pass, run a product's effect.
- **World (whole server):** start a moon event or a zone event, hold the sky at day, dusk or night (or let it run).
- **Testing:** restart the first-session guide, skip to the next day, reset redeemed codes.

The server re-checks the caller on every request (a client can't make itself an admin), prints each action to the server log, and admin cash goes to Analytics under its own `Admin` SKU so the economy dashboard can leave it out. It's allowed by Roblox's rules; don't sell admin powers or items off-platform.

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

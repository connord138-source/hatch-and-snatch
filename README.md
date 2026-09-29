# Hatch & Snatch (working title)

A Roblox creature game: hatch eggs off the conveyor, grow creatures from cute
babies into majestic adults, earn cash from them, and steal from other players
or protect your own.

- **Design:** [`docs/GDD.md`](docs/GDD.md)
- **Creatures:** [`docs/ROSTER.md`](docs/ROSTER.md), with concept images
- **Art rules:** [`docs/ART_BIBLE.md`](docs/ART_BIBLE.md)
- **Context for Claude sessions:** [`CLAUDE.md`](CLAUDE.md)

## One-time setup on your PC

1. **Roblox Studio:** install it and sign in.
2. **Git:** https://git-scm.com
3. **VS Code:** https://code.visualstudio.com. Add the extensions **Luau Language Server** (JohnnyMorganz), **StyLua**, **Selene** and **Rojo**.
4. **Rokit** (installs the pinned tools):
   - Windows PowerShell: `irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex`
   - Then, inside this folder: `rokit install`. That installs Rojo, StyLua and Selene at the versions pinned in `rokit.toml`.
5. **Rojo plugin for Studio:** run `rojo plugin install`, or install it from the Creator Store.
6. **Blender:** https://www.blender.org, for rigging and cleaning up creature models.
7. **A Roblox group** to own the game. Group ownership keeps payouts and team access clean.

## Daily workflow

```bash
rojo serve          # in this folder, keep it running
```

In Studio, open a Baseplate, then **Rojo plugin → Connect**. Code in `src/` syncs
live into Studio. Press **Play** to test. The server prints a config summary on
start. If it errors, the config data has a mistake.

```bash
stylua src          # format
selene src          # lint
```

## Layout

```
src/
  shared/Config/   data tables: creatures, rarities, finishes, mutations, biomes, economy, events
  server/          server bootstrap + services (authoritative: cash, hatching, growth, stealing)
  client/          UI, VFX, creature movement (visual only)
docs/              design, roster, art bible
```

## Playtesting the core loop (Studio)

1. `rojo serve`, connect the plugin, press **Play**.
2. You spawn on your own plot. Walk to the conveyor ring and press **E** on an egg to buy it.
3. It incubates at your base (timers are shown on the left), hatches, and the creature appears on a pedestal.
4. Cash builds up on your green pad; step on it to collect.
5. The buttons under the incubators open three menus:
   - **Creatures:** every creature you own. **Store** takes one off its pedestal (it stops earning), **Place** puts it back, **To Nursery** protects it, and **Sell** (press twice) sells it for 15 seconds of its earnings.
   - **Index:** all 30 species by biome. The ones you've owned show their gag, the dots are rare finishes you've collected, and ADULT means you've raised one.
   - **Rebirth:** costs $25K for the first (see `rebirthCosts` in `Economy.luau`). It resets your cash, keeps your creatures, unlocks the next biome's eggs and adds +10% earnings.

**Studio test mode** (`src/shared/Config/Debug.luau`, ignored in live servers):
- Hatching and growth run 20× faster.
- Your cash is topped up to $1M every time you press Play. Only Mossvale eggs are unlocked at first: rebirth to unlock the next biome, then Stop and Play again for another $1M. Set `studioUnlockAllBiomes = true` to skip that.
- A moon event fires every 2 minutes.
- Studio saves go to their own DataStore (`PlayerData_Studio_v1`), so test cash never reaches live saves.

Drop a real model into `ReplicatedStorage.CreatureModels` named after the species id
(for example `Emberlynx`, with its PrimaryPart set) and it replaces the placeholder block creature.

Set **Game Settings → Places → Max Players = 8**: there are 8 base plots per server.

## Testing stealing (needs 2 players)

In Studio, pick **Server & Clients** in the mode dropdown next to Play, set the player count beside it to **2**, then press Play. (Or start the server and use **Test → Add Clients** in its window, once per player.) A server window and two client windows open; they stack on top of each other, so drag them apart. Switch the dropdown back to **Test** for normal Play.

1. **Player 1:** buy and hatch a creature.
2. **Player 2:** walk into Player 1's base and hold **E** on the creature (Steal).
   - It lifts over your head.
   - Carry speed drops with growth stage, and you can't jump while carrying an adult.
   - While it's being carried it earns nothing for Player 1.
3. **Player 2:** run back into your own plot to deliver it. It arrives tagged "stolen from Player1".
4. **Player 1** can instead hold **E** on the thief to take it back (fastest for adults), or try:
   - pressing **F** on their own creature to move it into the blue Nursery pedestal, where it can't be stolen;
   - pressing the red **Lock** button for a 60-second laser gate that pushes intruders out.
5. Homegrown creatures have a 35% chance to break free on the way.

New-player protection (10 minutes) is switched off in Studio so you can test right away.

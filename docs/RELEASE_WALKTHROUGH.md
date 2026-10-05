# Release walkthrough (v1 launch, 2026-10-06)

The full check before Hatch & Snatch goes public. The PC session works through it top to bottom in Studio, reports each section (pass, or what broke with the Output text and a screenshot), and stops at the first blocker. Claude fixes and pushes; the PC pulls and re-checks only the broken item.

Test in **Studio Play** or **Test → Local Server** (2–6 players). Don't use Team Test: it probably uses the live `PlayerData_v2` store. The Admin panel (bottom-left, owner only) has every shortcut used below.

## 0. Setup

1. `git pull origin claude/core-systems`; Rojo syncing; Studio's scripts match the repo.
2. **Sound pack:** upload `assets/audio/hatch_sfx.ogg` once (Creator Hub → Creations → Development Items → Audio → Upload Asset). Wait until it's approved, then put its id in `src/shared/Config/Sounds.luau` `id`, commit ("Sound pack id") and push. Don't paste the id before it's approved: a pending sound plays silence, while id 0 plays the fallback pings.
3. Output on start: no errors (red) from any script. Note any warnings. A warning that starts with a loop's name in brackets, like `[CreatureService.tick]` or `[StateService.send]`, means a loop hit an error and carried on (the new guards): report it with its full text, it's a bug.
4. **Skins in the place:** count `ReplicatedStorage.MutationSkins` (it should hold the 573 screened skins) and check that none of their texture ids appears in `tools/mutations/old_skin_images_2026-10-03.csv` (the 462 old pink images). Any match is a moderation risk: report it before publishing.

## 1. Hatch reveal and sounds (new 2026-10-05)

Admin → Creatures → spawn one of each rarity on yourself (the reveal plays): Common, Uncommon, Rare, Epic, Legendary, Mythic, Celestial, Cosmic, Secret, Junk.

- [ ] Each rarity has its own sound, getting bigger as rarity rises; Junk is a cartoon boing with a wobbling title.
- [ ] Each reel card ticks as it passes the marker (a click, not a ping); the reel starts with a whoosh.
- [ ] **Legendary and up:** a longer reel that crawls over its last cards while a riser builds, the screen darkens and the marker glows; a heartbeat pause with a spotlight on the winning card; then an impact with a screen shake, flashes, rotating light rays behind the creature, the title slamming in with a shine sweeping across it, confetti and the creature popping in.
- [ ] **Mythic and up** also: color pulses, a second confetti burst, and "🍀 1 in N from this egg".
- [ ] A finish (spawn a Gold one) adds a shine sound; a mutation (spawn an Albino one) adds its chime, flash and banner.
- [ ] Skip and close: clicking during a Common reel slides it straight to the result; clicking the result closes it after ~1 s ("Click to continue" appears). A Legendary reel can't be skipped, and closes after ~3 s. Several reveals in a row play one after another.
- [ ] **Phones** (Studio's device emulator: an iPhone and a small Android): the reel stops with the winner exactly under the gold marker (this was a card off before); "Tap to continue".
- [ ] **Light pillar:** Local Server, 2 players. Player 1: Admin → Eggs → set to hatch a Legendary, place it, wait for it to hatch. Player 2, standing near player 1's base, sees a colored light pillar shoot up from the incubator with a shockwave ring and sparkles, and hears the fanfare. Then repeat with a Mythic: a taller, wider pillar, and a server announcement in chat after the reveal. (Legendary has no chat announcement on purpose, since 1 egg in 33 is Legendary and it would spam a full server; its pillar is its public moment. Mythic and up announce.)
- [ ] With the sound pack's id set, all of the above uses the new sounds; with id 0, pitched pings (still different per rarity).

## 2. Luck Wheel

- [ ] Spin 3 times: the flapper hangs straight when the wheel stops; the banner prize matches the slice under the flapper; ticks are clicks; a win plays the Rare chime, and the ×25 jackpot plays the Legendary fanfare.
- [ ] A second player pressing mid-spin joins the line; Spin all (R) runs until spins run out or a ×10+ luck win.
- [ ] Spin all only shows with 2 or more spins (with 0 or 1 it's hidden).
- [ ] A player who leaves mid-spin still gets the prize next time they join (check their cash, spins or "next egg ×N").
- [ ] Night: the bulbs chase; the sign text reads.

## 3. New player, start to finish

Use a fresh profile (a Local Server test player that has never played, or Admin → Restart guide for the guide only).

- [ ] Spawn on your own plot; the guide arrow and objectives lead the way.
- [ ] Buy an egg from the belt (eggs roll out of and back into the tunnel; none vanish in view), carry it overhead, place it in the incubator; the rarity color fades in from 40%; it hatches in about 10 s for a Common.
- [ ] The creature sits on a pedestal and earns; collect the cash; the Daily popup waits until the guide is done.
- [ ] Upgrade the base at a walk-over pad (stand 0.6 s); open the Base menu at the Command Terminal.
- [ ] Buy a second incubator and upgrade one; its egg keeps its progress.

## 4. Creatures

- [ ] Creatures menu: tap a name to open the details card (model, genetics, earnings breakdown, growth, location).
- [ ] Walk a creature: it follows with a hop and grows ×2 (×4 in its own biome's zone); it can't be stolen while walked.
- [ ] Feed (10 Essence of its biome per 15 min), Sell (an average Adult sells for about half its egg's price, better ones for more; a fresh Baby for less than its egg), Release (pays Essence; spins for Legendary+), storage and nursery.
- [ ] Albino, Melanistic, Piebald, Chimera and Iridescent creatures wear their skins (Admin spawn a few across species); the held-back ones fall back to the v1 look without errors.

## 5. Stealing (Local Server, 2–3 players)

- [ ] Steal a Baby, a Juvenile and an Adult: carry speed 100% / 75% / 50%; deliver to your base; the "Stolen from X" tag stays.
- [ ] A homegrown creature struggles and breaks free once; nursery creatures can't be stolen.
- [ ] Take Back: the owner must be next to the thief and hold the prompt; it does nothing from across the base. Sell and Release are refused while an intruder is inside (like Store and Move).
- [ ] Alarm, tripwire and auto-lock trigger; every security item has a timer or release (no base is unbreakable).
- [ ] Floors: grab only from the same floor, longer hold; vaults lock on a timer; hiding spots can be searched (empty ones are decoys; Mythic+ sparkle).

## 6. Bases and Castle Designer

- [ ] Base levels 1–5 (Admin → max base on a test player): walls grow Camp → Citadel; pedestals in two roomy wings; floors and ramps.
- [ ] Castle Designer: try 3–4 presets (Ice, Fire, Rainbow, Diamond); theme kits show their 3D pieces and niche glows; no z-fighting or floating parts.
- [ ] Click through designer options quickly: the base updates at most once a second and always ends on the last pick; re-picking the option in use does nothing. Buying at a pad rebuilds once (Security included).

## 7. World

- [ ] Walk the island: the reactor, the belt, all 6 plots, the biome ring (walls open north and south), the North Commons (Luck Wheel, Quest Board, Daily Chest), the South Event Grounds, landmarks; the sea wall stops you at the shore.
- [ ] A biome zone: the gate by level, harvest nodes give Essence, the shrine forges an egg or gives a blessing; trigger a zone event (Admin).
- [ ] Moon events (Admin): Blood, Gold, Void, Prism tint the sky and change odds; the odds panel updates and still sums to 100%.
- [ ] Day and night (Admin → hold dusk/night): lights read, nothing blows out (Ice and Diamond castles included).

## 8. Shop, rewards and progression

- [ ] Shop: every pass and product shows its name and price; Studio test-buy Skip Hatch, a Cash pouch and Server Luck: each applies once (Server Luck announces and shows its timer).
- [ ] The odds panel opens before buying an egg and lists species, finishes and mutations summing to 100%.
- [ ] Codes: HATCH, MOONEGG and SNATCH redeem once each (Admin → Reset codes to retest); the group perk stays hidden (no group yet).
- [ ] Daily: claim the streak reward; quests track and can be rerolled; Admin → Next day advances the streak.
- [ ] Achievements pay XP and spins; Hatcher Level unlocks biome eggs; Rebirth (Admin cash) works and the Rebirth menu shows the next castle unlock.

## 9. Devices and performance

- [ ] Phone and tablet (emulator): HUD, menus above the bottom bar, prompts without " (E)", the reveal and the wheel banner fit.
- [ ] Xbox controller: prompts show X / Y / B and don't hide each other; A closes a reveal; menus usable with the View-button cursor. Decide whether Console goes on at launch (docs/LAUNCH.md).
- [ ] Local Server with 6 players: F9 shows no error spam on the server or clients; frame rate stays smooth at a full base and the busy Commons.
- [ ] Leave and rejoin: cash, creatures, incubators, designs and the daily streak are still there.

## 10. Publish and live checks

- [ ] File → Publish to Roblox (the Rojo-synced build). Note the version number.
- [ ] Live, as the owner: the wheel works; an Admin-spawned Albino Emberlynx shows its skin; a Legendary rigged egg plays the full sequence and the pillar.
- [ ] Live, with a second account (docs/LAUNCH.md §2): buy and hatch, collect, upgrade once; rejoin after 30 s and everything is there; buy the cheapest product (applies exactly once); redeem a code; claim Daily; steal between the two accounts; F9 → Server console has no errors.

## 11. Launch settings (owner, in Creator Hub)

- [ ] Store page: icon, thumbnails (re-upload 2 and 7, which changed), title and description from `docs/STORE_PAGE.md`.
- [ ] Find why the console showed "Ages 16+" and set the lowest age the content allows (the questionnaire answers are Minimal).
- [ ] Max Players 6; Private Servers 99 R$/month; genre set; devices (Console only if section 9 passed).
- [ ] Delete the Open Cloud API key used for the archive attempt, if it still exists.
- [ ] Audience → **Public** when you're ready.

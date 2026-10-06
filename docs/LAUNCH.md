# Launch checklist (v1)

The owner does these steps in Creator Hub (signed in as **Dillionaire138**) and in the live game. Creator Hub menu names shift now and then; if one has moved, search Creator Hub for it.

## 1. Before going public

- [ ] **Store art uploaded:** `marketing/icon_512.png` and `thumb_1`…`thumb_4`, plus the title and description (`docs/STORE_PAGE.md`).
- [x] **Maturity & compliance questionnaire** (the experience → Audience → Maturity & Compliance). **Submitted 2026-10-01: Minimal**, no content descriptors, no non-compliant regions. Creator Hub asked two paid-random-items questions (has them: Yes; respects the regional restriction: Yes) and no separate odds question. The answers, for reference:
  - Violence: none. Players grab creatures; there are no weapons and no damage.
  - Blood or gore: none. "Blood Moon" is only a red event name and tint.
  - Paid random items: **Yes**. Eggs are random and bought with cash, and Robux buys cash (Cash Pouch, Cash Chest) and better odds (Server Luck). That counts under Roblox's rules.
  - Shows the odds before purchase: **Yes**. The odds panel lists every species, finish and mutation with percentages adding up to 100%, live with luck and moon events (GDD §3.1).
  - Respects `PolicyService` restrictions: **Yes**. `ArePaidRandomItemsRestricted` players never see Cash Pouch, Cash Chest or Server Luck (GDD §9).
  - Social: the default Roblox chat. No free-form text of our own except redeem codes.
  - Re-answer it if the game adds anything that changes these (e.g. new paid items).
- [x] **Devices:** Computer, Phone, Tablet and **Console** (owner, 2026-10-05; menus work on a controller since then: D-pad ▲ selects the menu bar, A opens, B closes). VR off.
- [x] **Thumbnails** 2 and 7 re-uploaded (owner, 2026-10-05).
- [ ] **Launch week ×2 luck** runs by itself until 2026-10-14 04:00 UTC (`Config/Economy.luau` `tunables.launchLuck`). Use the launch-week description and title in `docs/STORE_PAGE.md` that week, then switch back on Oct 14.
- [x] **Published v177** from 5dd0f66 (2026-10-05), after the final PC re-test passed.
- [x] **Server size:** Max Players 6.
- [x] **Private servers** (Monetization → Private Servers): turn them on at **99 Robux a month**. In a stealing game a friends-only server is worth paying for, and it's recurring income. The re-steal rule (no rewards for 30 min) stops alt-account farming there too.
- [x] **Genre:** Simulation or Tycoon, whichever fits best among Creator Hub's current genre options.
- [ ] **Social links:** skip for now. Add the group link when the group exists (that also turns on the group perk: `Config/Monetization.luau` → `tuning.group.id`).

## 2. Publish and smoke-test the live game

Studio and Team Test aren't enough: live servers use the real `PlayerData_v2` store and real Robux.

1. Publish from Studio (File → Publish to Roblox). Make sure the published place is the Rojo-synced build from `claude/core-systems`.
2. Make the experience **public** (the experience's overview or Settings → Privacy/Public).
3. On the **live** game with a second account (not the owner, who owns every pass):
   - Play a few minutes: buy and hatch an egg, collect, upgrade the base once.
   - Leave, wait 30 s, and rejoin: the cash, creatures, incubators and daily streak are still there.
   - Buy the cheapest product (Skip Hatch or Cash Pouch, 29 Robux). It should apply exactly once, and still show after a rejoin.
   - Optional: buy the cheapest pass (Offline +8h, 79 Robux). "Thanks! … is yours." appears and the Shop says "Owned ✓" after a rejoin.
   - Redeem `HATCH`, and claim the Daily reward.
   - Steal a creature between the two accounts in a live server.
4. Check the live server's console (F9 → Server) for errors.

## 3. Analytics (after the first players arrive)

Nothing needs turning on: the game already logs everything (`src/server/Analytics.luau`). Check these in Creator Hub → the experience → Analytics:

- **Retention and engagement:** day-1 and day-7 retention and average session time. These are the numbers Roblox's recommendations weigh most.
- **Funnels → Onboarding:** joined → bought an egg → placed it → hatched → collected → upgraded the base. The biggest drop is the next thing to fix.
- **Economy:** cash sources and sinks by SKU. Check it against the pacing table in GDD §7.
- **Custom events:** Hatch (by rarity, biome and finish), Steal, Rebirth, CodeRedeemed, DailyLogin, DailyQuest, AdWatched.
- **Monetization:** pass and product sales, and Premium Payouts.

## 4. First week

- Post the like-goal code plan in the description (add codes to `Config/Codes.luau` when goals are hit).
- Rewarded ads turn on by themselves once Roblox approves the game (2,000+ monthly visitors, ID-verified owner).
- Watch the onboarding funnel and day-1 retention, and bring the numbers to the next session.

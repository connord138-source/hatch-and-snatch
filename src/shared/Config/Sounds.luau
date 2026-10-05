--!strict
-- The game's sound pack (owner, 2026-10-05: "different sounds for different
-- rarities drawn and a more involved sequence when a legendary or higher is
-- drawn"). Every sound lives back to back in ONE audio file,
-- assets/audio/hatch_sfx.ogg, synthesized by tools/audio/make_sfx.py, so the pack
-- is a single upload; src/client/Sfx.luau plays each sound's own stretch of it
-- (Sound.PlaybackRegion). Until `id` is set, Sfx falls back to pitched pings.
--
-- Rarity stingers: Common .. Secret and Junk. Sequence: Riser (under a Legendary+
-- reel as it slows), Heartbeat (the pause before the reveal), Impact (the
-- Legendary+ hit), Whoosh (the reel starting), Tick (each card passing), Mutation
-- (a mutation's banner), Shine (a finish).
export type Region = { number } -- { start, length } in seconds

local Sounds: { id: number, regions: { [string]: Region } } = {
	id = 0, -- the uploaded hatch_sfx.ogg (Creator Hub → Development Items → Audio)
	regions = {
		-- BEGIN REGIONS (written by tools/audio/make_sfx.py; { start, length } in seconds)
		Common = { 0.100, 1.000 },
		Uncommon = { 1.450, 1.200 },
		Rare = { 3.000, 1.700 },
		Epic = { 5.050, 2.400 },
		Legendary = { 7.800, 3.800 },
		Mythic = { 11.950, 4.300 },
		Celestial = { 16.600, 4.700 },
		Cosmic = { 21.650, 5.100 },
		Secret = { 27.100, 5.200 },
		Junk = { 32.650, 1.700 },
		Riser = { 34.700, 3.000 },
		Impact = { 38.050, 1.900 },
		Heartbeat = { 40.300, 1.350 },
		Whoosh = { 42.000, 0.600 },
		Tick = { 42.950, 0.060 },
		Mutation = { 43.360, 2.400 },
		Shine = { 46.110, 1.100 },
		-- END REGIONS
	},
}

return Sounds

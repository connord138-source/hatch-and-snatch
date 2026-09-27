--!strict
-- Biomes unlock in `order` via rebirth. Moonfall is endgame; Junk is event-only (Prism Moon).
-- earningsMultiplier grows a bit slower than eggPriceMultiplier, so payback time
-- lengthens gradually as players progress (docs/GDD.md §7).
local Types = require(script.Parent.Types)

local Biomes: { [string]: Types.Biome } = {
	Mossvale = {
		id = "Mossvale",
		displayName = "Mossvale Forest",
		order = 1,
		eggPriceMultiplier = 1,
		earningsMultiplier = 1,
	},
	CoralCoast = {
		id = "CoralCoast",
		displayName = "Coral Coast",
		order = 2,
		eggPriceMultiplier = 8,
		earningsMultiplier = 4,
	},
	MagmaRift = {
		id = "MagmaRift",
		displayName = "Magma Rift",
		order = 3,
		eggPriceMultiplier = 64,
		earningsMultiplier = 16,
	},
	FrostShelf = {
		id = "FrostShelf",
		displayName = "Frost Shelf",
		order = 4,
		eggPriceMultiplier = 512,
		earningsMultiplier = 60,
	},
	StormPeaks = {
		id = "StormPeaks",
		displayName = "Storm Peaks",
		order = 5,
		eggPriceMultiplier = 4096,
		earningsMultiplier = 220,
	},
	Moonfall = {
		id = "Moonfall",
		displayName = "Moonfall",
		order = 6,
		eggPriceMultiplier = 32768,
		earningsMultiplier = 300,
	},
	Junk = {
		id = "Junk",
		displayName = "Junk Egg",
		order = 0,
		eggPriceMultiplier = 256,
		earningsMultiplier = 1,
	},
}

return Biomes

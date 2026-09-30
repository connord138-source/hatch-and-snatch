--!strict
-- Species rarity tiers. Numbers are first-pass drafts (docs/GDD.md §7); tune in playtests.
local Types = require(script.Parent.Types)

local Rarities: { [Types.RarityId]: Types.Rarity } = {
	Common = {
		id = "Common",
		order = 1,
		baseCashPerSec = 1,
		hatchSeconds = 30,
		growthFactor = 1,
		eventOnly = false,
		announce = false,
		color = Color3.fromRGB(170, 170, 170),
	},
	Uncommon = {
		id = "Uncommon",
		order = 2,
		baseCashPerSec = 3,
		hatchSeconds = 90,
		growthFactor = 1.25,
		eventOnly = false,
		announce = false,
		color = Color3.fromRGB(90, 200, 90),
	},
	Rare = {
		id = "Rare",
		order = 3,
		baseCashPerSec = 8,
		hatchSeconds = 5 * 60,
		growthFactor = 1.5,
		eventOnly = false,
		announce = false,
		color = Color3.fromRGB(70, 140, 255),
	},
	Epic = {
		id = "Epic",
		order = 4,
		baseCashPerSec = 25,
		hatchSeconds = 15 * 60,
		growthFactor = 2,
		eventOnly = false,
		announce = false,
		color = Color3.fromRGB(170, 80, 255),
	},
	Legendary = {
		id = "Legendary",
		order = 5,
		baseCashPerSec = 80,
		hatchSeconds = 45 * 60,
		growthFactor = 3,
		eventOnly = false,
		announce = false,
		color = Color3.fromRGB(255, 170, 30),
	},
	-- Ultra-rares (docs/GDD.md §7.1). Mythic: one per biome, always rollable.
	Mythic = {
		id = "Mythic",
		order = 6,
		baseCashPerSec = 400,
		hatchSeconds = 3 * 60 * 60,
		growthFactor = 4,
		eventOnly = false,
		announce = true,
		color = Color3.fromRGB(255, 60, 90),
	},
	-- Celestial: only rollable while a moon event is active.
	Celestial = {
		id = "Celestial",
		order = 7,
		baseCashPerSec = 1200,
		hatchSeconds = 4 * 60 * 60,
		growthFactor = 5,
		eventOnly = true,
		announce = true,
		color = Color3.fromRGB(150, 235, 255),
	},
	-- Cosmic: Moonfall eggs only.
	Cosmic = {
		id = "Cosmic",
		order = 8,
		baseCashPerSec = 3000,
		hatchSeconds = 6 * 60 * 60,
		growthFactor = 6,
		eventOnly = false,
		announce = true,
		color = Color3.fromRGB(140, 70, 255),
	},
	-- Secret: 1-in-50,000 hidden in ordinary eggs; shows as ??? in the Index until found.
	Secret = {
		id = "Secret",
		order = 9,
		baseCashPerSec = 6000,
		hatchSeconds = 8 * 60 * 60,
		growthFactor = 8,
		eventOnly = false,
		announce = true,
		color = Color3.fromRGB(255, 255, 255),
	},
	Junk = {
		id = "Junk",
		order = 5, -- ranks with Legendary for steal alerts and rare toasts
		baseCashPerSec = 30,
		hatchSeconds = 20 * 60,
		growthFactor = 1.5,
		eventOnly = true,
		announce = false,
		color = Color3.fromRGB(150, 110, 70),
	},
}

return Rarities

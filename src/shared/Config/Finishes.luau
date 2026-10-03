--!strict
-- Finishes: the flashy rarity layer. Material + particle swaps, no new models.
-- Rolled rarest-first when the egg is bought; see Economy.finishOdds / rollFinish.
local Types = require(script.Parent.Types)

local Finishes: { Types.Finish } = {
	{ id = "Normal", displayName = "Normal", oneIn = nil, earningsMultiplier = 1, announce = "none" },
	{ id = "Gold", displayName = "Gold", oneIn = 15, earningsMultiplier = 1.5, announce = "none" },
	{ id = "Chrome", displayName = "Chrome", oneIn = 60, earningsMultiplier = 2, announce = "none" },
	{ id = "Diamond", displayName = "Diamond", oneIn = 250, earningsMultiplier = 3, announce = "none" },
	{ id = "Molten", displayName = "Molten", oneIn = 1000, earningsMultiplier = 5, announce = "none" },
	{ id = "Galaxy", displayName = "Galaxy", oneIn = 4000, earningsMultiplier = 8, announce = "server" },
	{
		id = "Prismatic",
		displayName = "Prismatic",
		oneIn = 16000,
		earningsMultiplier = 15,
		announce = "fanfare",
	},
	{
		id = "BloodMoon",
		displayName = "Blood Moon",
		oneIn = 150,
		earningsMultiplier = 10,
		announce = "server",
		eventOnly = "BloodMoon",
	},
}

return Finishes

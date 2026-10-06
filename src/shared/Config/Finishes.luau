--!strict
-- Finishes: the flashy rarity layer. Material + particle swaps, no new models.
-- Rolled rarest-first when the egg is bought; see Economy.finishOdds / rollFinish.
-- Odds are per pull (every egg, whatever species hatches). Loosened 2026-10-03
-- (owner: 100+ pulls each and only a few Golds): Gold 1/8, Chrome 1/25, Diamond
-- 1/80, Molten 1/250; Galaxy 1/4,000 and Prismatic 1/16,000 stay ("Galaxy can stay
-- 1 in 4000 out of total pulls").
local Types = require(script.Parent.Types)

local Finishes: { Types.Finish } = {
	{ id = "Normal", displayName = "Normal", oneIn = nil, earningsMultiplier = 1, announce = "none" },
	{ id = "Gold", displayName = "Gold", oneIn = 8, earningsMultiplier = 1.5, announce = "none" },
	{ id = "Chrome", displayName = "Chrome", oneIn = 25, earningsMultiplier = 2, announce = "none" },
	{ id = "Diamond", displayName = "Diamond", oneIn = 80, earningsMultiplier = 3, announce = "none" },
	{ id = "Molten", displayName = "Molten", oneIn = 250, earningsMultiplier = 5, announce = "server" },
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

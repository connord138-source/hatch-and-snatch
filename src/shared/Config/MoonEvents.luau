--!strict
-- Hourly server-wide moon events. The Moon Egg's color is the event alarm.
local Types = require(script.Parent.Types)

local MoonEvents: { Types.MoonEvent } = {
	{
		id = "BloodMoon",
		displayName = "Blood Moon",
		durationSeconds = 10 * 60,
		weight = 4,
		finishChanceMultiplier = 5,
		earningsMultiplier = 1,
		lockDurationMultiplier = 1,
		stealCashBonus = 0,
		spawnsJunkEgg = false,
		description = "5× rare finish chance + Blood Moon finish · Celestials can hatch",
	},
	{
		id = "GoldMoon",
		displayName = "Gold Moon",
		durationSeconds = 10 * 60,
		weight = 4,
		finishChanceMultiplier = 1,
		earningsMultiplier = 2,
		lockDurationMultiplier = 1,
		stealCashBonus = 0,
		spawnsJunkEgg = false,
		description = "2× cash from every creature · Celestials can hatch",
	},
	{
		id = "VoidMoon",
		displayName = "Void Moon",
		durationSeconds = 10 * 60,
		weight = 3,
		finishChanceMultiplier = 1,
		earningsMultiplier = 1,
		lockDurationMultiplier = 0.5,
		stealCashBonus = 0.25,
		spawnsJunkEgg = false,
		description = "Base locks last half as long · thieves grab bonus cash · Celestials can hatch",
	},
	{
		id = "PrismMoon",
		displayName = "Prism Moon",
		durationSeconds = 5 * 60,
		weight = 1,
		finishChanceMultiplier = 2,
		earningsMultiplier = 1,
		lockDurationMultiplier = 1,
		stealCashBonus = 0,
		spawnsJunkEgg = true,
		description = "Junk Eggs on the belt · 2× rare finish chance · Celestials can hatch",
	},
}

return MoonEvents

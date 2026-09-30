--!strict
-- Daily login streak and daily quests (DailyService, GDD §7.4). Days are UTC days.
--
-- Login streak: claim once a day in the Daily menu. Claiming on consecutive days
-- walks through `streak` (day 7 is the big one), then the cycle repeats; missing a
-- day starts again at day 1.
--
-- Quests: `questsPerDay` picked each day from `quests` (weighted, the same picks
-- for a player all day). Progress is how much a lifetime stat (PlayerData.stats)
-- grew since the quest was given, so any way of doing it counts. Rewards are paid
-- the moment a quest is done; finishing them all pays `allDoneBonus`.
export type Reward = {
	spins: number?,
	luck: number?, -- charges the next egg, like the Luck Wheel
	cashMinutes: number?, -- that many minutes of the player's income (at least `cashFloor`)
	growthMinutes: number?, -- all your creatures grow ×2 (the Growth Elixir effect)
}

export type Quest = {
	id: string,
	stat: string, -- a key of PlayerData.stats
	goal: number?,
	goalIncomeMinutes: number?, -- goal = that many minutes of income when the quest is given
	text: string, -- "{goal}" is replaced by the goal
	reward: Reward,
	weight: number,
}

local streak: { Reward } = {
	{ spins = 2 },
	{ cashMinutes = 10 },
	{ luck = 3 },
	{ cashMinutes = 20 },
	{ spins = 3 },
	{ growthMinutes = 15 },
	{ luck = 10, spins = 5 },
}

local quests: { Quest } = {
	{
		id = "hatch",
		stat = "hatched",
		goal = 8,
		text = "Hatch {goal} eggs",
		reward = { spins = 1 },
		weight = 3,
	},
	{
		id = "buy",
		stat = "eggsBought",
		goal = 10,
		text = "Buy {goal} eggs from the belt",
		reward = { cashMinutes = 10 },
		weight = 3,
	},
	{
		id = "spin",
		stat = "spinsUsed",
		goal = 3,
		text = "Spin the Luck Wheel {goal} times",
		reward = { luck = 3 },
		weight = 2,
	},
	{
		id = "walk",
		stat = "walkSeconds",
		goal = 300,
		text = "Walk a creature for 5 minutes",
		reward = { spins = 1 },
		weight = 2,
	},
	{
		id = "earn",
		stat = "earned",
		goalIncomeMinutes = 20,
		text = "Collect {goal}",
		reward = { spins = 2 },
		weight = 3,
	},
	{
		id = "harvest",
		stat = "harvests",
		goal = 6,
		text = "Harvest {goal} Essence nodes in the biome zones",
		reward = { cashMinutes = 15 },
		weight = 2,
	},
	{
		id = "adult",
		stat = "adults",
		goal = 1,
		text = "Raise a creature to Adult",
		reward = { luck = 5 },
		weight = 1,
	},
	{
		id = "steal",
		stat = "steals",
		goal = 1,
		text = "Steal a creature",
		reward = { spins = 2 },
		weight = 1,
	},
}

local byId: { [string]: Quest } = {}
for _, quest in quests do
	byId[quest.id] = quest
end

-- "2 spins + ×3 luck" for a reward (the Daily menu and toasts).
local function rewardText(reward: Reward): string
	local parts: { string } = {}
	if reward.spins then
		table.insert(parts, `{reward.spins} spin{if reward.spins == 1 then "" else "s"}`)
	end
	if reward.luck then
		table.insert(parts, `×{reward.luck} luck`)
	end
	if reward.cashMinutes then
		table.insert(parts, `{reward.cashMinutes} min of cash`)
	end
	if reward.growthMinutes then
		table.insert(parts, `{reward.growthMinutes} min ×2 growth`)
	end
	return table.concat(parts, " + ")
end

return {
	streak = streak,
	quests = quests,
	questsById = byId,
	questsPerDay = 3,
	rerollsPerDay = 1,
	allDoneBonus = { spins = 2, luck = 5 } :: Reward,
	cashFloor = 500,
	rewardText = rewardText,
}

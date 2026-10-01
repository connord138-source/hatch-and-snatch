--!strict
-- Economy tunables + pure helper math (no Roblox services, safe on client and server).
local Types = require(script.Parent.Types)
local Rarities = require(script.Parent.Rarities)
local Stages = require(script.Parent.Stages)
local Finishes = require(script.Parent.Finishes)
local Mutations = require(script.Parent.Mutations)
local Biomes = require(script.Parent.Biomes)

local Tunables = {
	-- Growth: stage N -> N+1 takes base × rarity growthFactor (runs offline too)
	growthSeconds = {
		Baby = 30 * 60, -- Baby -> Juvenile
		Juvenile = 3 * 60 * 60, -- Juvenile -> Adult
	} :: { [Types.StageId]: number },

	startingCash = 300, -- two starter eggs
	offlineCapSeconds = 8 * 60 * 60,
	homegrownBonus = 0.25,
	rebirthBonusPerLevel = 0.10,

	-- Stealing / base defence
	lockDurationSeconds = 60,
	lockCooldownSeconds = 45,
	newPlayerProtectionSeconds = 10 * 60,
	nurserySlotsBase = 1,
	nurserySlotsMax = 3,
	pedestalsBase = 10,
	pedestalsMax = 30,
	basePlotsPerServer = 6, -- also set Max Players = 6 in Game Settings → Places

	-- Creatures menu. A creature sells for this many seconds of its own earnings:
	-- low enough that a fresh hatch sells for less than its egg on average, even in
	-- a Blood Moon, so buying eggs just to sell them never pays.
	sellValueSeconds = 15,
	storageSlots = 40, -- off-pedestal creatures; buying and stealing stop when full

	-- Rebirth N costs rebirthCosts[N]; after the list each one costs
	-- rebirthCostGrowth× the last. Rebirth is the endgame sink: the first one
	-- lands after Moonfall and a full base (tools/sim/economy_sim.luau), and each
	-- +10% makes the next one only a little easier than the cost grows.
	rebirthCostGrowth = 2.5,
	rebirthCosts = {
		1_000_000_000_000,
		2_500_000_000_000,
		6_000_000_000_000,
		15_000_000_000_000,
		40_000_000_000_000,
	},

	-- Moon events
	moonEventIntervalSeconds = 60 * 60,

	-- Base upgrades: each level widens and deepens the plot (longer escape run for
	-- thieves), adds a row of 5 pedestals and lengthens the laser lock.
	baseLevels = {
		{ cost = 0, pedestals = 10, lockBonusSeconds = 0 },
		{ cost = 60_000, pedestals = 15, lockBonusSeconds = 15 },
		{ cost = 25_000_000, pedestals = 20, lockBonusSeconds = 30 },
		{ cost = 5_000_000_000, pedestals = 25, lockBonusSeconds = 45 },
		{ cost = 500_000_000_000, pedestals = 30, lockBonusSeconds = 60 },
	},

	-- Base security (bought in order in the Base menu)
	securityLevels = {
		{
			name = "Intruder Alarm",
			cost = 40_000,
			description = "Alerts you when someone walks into your base; intruders glow red",
		},
		{
			name = "Tripwire",
			cost = 10_000_000,
			description = "Thieves carrying your creatures move 25% slower inside your base",
		},
		{
			name = "Auto-Lock",
			cost = 2_000_000_000,
			description = "Your laser gate locks itself when an intruder walks in (if it's charged)",
		},
	},
	tripwireSlow = 0.75,

	-- Walking a creature: it follows you around, can't be stolen, and grows faster
	walkGrowthMultiplier = 2,

	-- Luck Wheel: a physical wheel by the hub. Spending a spin lands on a prize.
	-- "luck" charges the player's NEXT egg (Epic+ weights × value; the best unspent
	-- charge is kept); "cash" pays `value` minutes of the player's current income
	-- (at least $500); "spin" gives spins back. Slices are drawn equal, so the real
	-- odds are printed on the wheel's sign.
	freeSpinSeconds = 20 * 60, -- one free spin per 20 minutes played
	startingSpins = 3,
	maxBankedSpins = 10,
	luckWheel = {
		{ label = "×2 LUCK", kind = "luck", value = 2, weight = 30, color = Color3.fromRGB(80, 160, 255) },
		{ label = "CASH", kind = "cash", value = 5, weight = 24, color = Color3.fromRGB(80, 200, 110) },
		{ label = "×3 LUCK", kind = "luck", value = 3, weight = 18, color = Color3.fromRGB(170, 90, 255) },
		{ label = "+2 SPINS", kind = "spin", value = 2, weight = 12, color = Color3.fromRGB(255, 170, 40) },
		{ label = "×10 LUCK", kind = "luck", value = 10, weight = 12, color = Color3.fromRGB(255, 70, 100) },
		{
			label = "×25 JACKPOT",
			kind = "luck",
			value = 25,
			weight = 4,
			color = Color3.fromRGB(255, 235, 120),
		},
	},
}

export type CreatureInstanceStats = {
	biome: string,
	rarity: Types.RarityId,
	stage: Types.StageId,
	finish: string,
	mutation: string?,
	homegrown: boolean,
}

local finishById: { [string]: Types.Finish } = {}
for _, finish in Finishes do
	finishById[finish.id] = finish
end

local mutationById: { [string]: Types.Mutation } = {}
for _, mutation in Mutations do
	mutationById[mutation.id] = mutation
end

-- Cash per second for one creature, before server-wide multipliers (events, passes, rebirth).
local function cashPerSecond(stats: CreatureInstanceStats): number
	local rarity = Rarities[stats.rarity]
	local stage = Stages[stats.stage]
	local finish = finishById[stats.finish] or finishById.Normal
	local bonus = 1
	if stats.mutation then
		local mutation = mutationById[stats.mutation]
		if mutation then
			bonus += mutation.valueBonus
		end
	end
	if stats.homegrown then
		bonus += Tunables.homegrownBonus
	end
	local biome = Biomes[stats.biome]
	local biomeMultiplier = if biome then biome.earningsMultiplier else 1
	return rarity.baseCashPerSec
		* biomeMultiplier
		* stage.earningsMultiplier
		* finish.earningsMultiplier
		* bonus
end

-- Cash a creature sells for in the Creatures menu.
local function sellValue(stats: CreatureInstanceStats): number
	return math.floor(cashPerSecond(stats) * Tunables.sellValueSeconds)
end

-- Cash needed for the next rebirth, given how many the player has done.
local function rebirthCost(rebirthsDone: number): number
	local costs = Tunables.rebirthCosts
	local nth = rebirthsDone + 1
	if nth <= #costs then
		return costs[nth]
	end
	return costs[#costs] * Tunables.rebirthCostGrowth ^ (nth - #costs)
end

local maxBiomeOrder = 0
for _, biome in Biomes do
	maxBiomeOrder = math.max(maxBiomeOrder, biome.order)
end

-- Seconds to grow from `stage` to the next stage (nil when already Adult).
local function secondsToNextStage(rarityId: Types.RarityId, stage: Types.StageId): number?
	local base = Tunables.growthSeconds[stage]
	if base == nil then
		return nil
	end
	return base * Rarities[rarityId].growthFactor
end

-- Rolls a finish rarest-first. `activeEventId` enables event-only finishes;
-- `chanceMultiplier` comes from moon events / luck boosts. `rng` is injected for testability.
export type Chance = { id: string, chance: number }

-- The exact chance of every finish for one roll (they sum to 1): rarest first,
-- each eligible finish takes `chanceMultiplier / oneIn` of what's left, and
-- Normal gets the rest. `activeEventId` enables event-only finishes;
-- `chanceMultiplier` comes from moon events. The odds panel shows these, and
-- rollFinish samples them, so what players see is what they get.
local function finishOdds(activeEventId: string?, chanceMultiplier: number): { Chance }
	local ordered = table.clone(Finishes)
	table.sort(ordered, function(a, b)
		return (a.oneIn or 0) > (b.oneIn or 0)
	end)
	local remaining = 1
	local odds: { Chance } = {}
	for _, finish in ordered do
		local oneIn = finish.oneIn
		if oneIn ~= nil and (finish.eventOnly == nil or finish.eventOnly == activeEventId) then
			local p = math.min(1, chanceMultiplier / oneIn)
			table.insert(odds, { id = finish.id, chance = remaining * p })
			remaining *= 1 - p
		end
	end
	table.insert(odds, { id = "Normal", chance = remaining })
	return odds
end

-- The exact chance of each genetic mutation, plus "None" (they sum to 1).
local function mutationOdds(): { Chance }
	local odds: { Chance } = {}
	local total = 0
	for _, mutation in Mutations do
		table.insert(odds, { id = mutation.id, chance = mutation.chance })
		total += mutation.chance
	end
	table.insert(odds, { id = "None", chance = 1 - total })
	return odds
end

local function sample(rng: Random, odds: { Chance }): string
	local roll = rng:NextNumber()
	for _, entry in odds do
		roll -= entry.chance
		if roll < 0 then
			return entry.id
		end
	end
	return odds[#odds].id
end

-- Rolls a finish from finishOdds. `rng` is injected for testability.
local function rollFinish(rng: Random, activeEventId: string?, chanceMultiplier: number): string
	return sample(rng, finishOdds(activeEventId, chanceMultiplier))
end

-- Rolls at most one genetic mutation, from mutationOdds.
local function rollMutation(rng: Random): string?
	local id = sample(rng, mutationOdds())
	return if id == "None" then nil else id
end

-- Base level config, clamped to the table.
local function baseLevel(level: number): { cost: number, pedestals: number, lockBonusSeconds: number }
	local levels = Tunables.baseLevels
	return levels[math.clamp(level, 1, #levels)]
end

local Economy = table.freeze({
	baseLevel = baseLevel,
	tunables = Tunables,
	maxBiomeOrder = maxBiomeOrder,
	cashPerSecond = cashPerSecond,
	sellValue = sellValue,
	rebirthCost = rebirthCost,
	secondsToNextStage = secondsToNextStage,
	rollFinish = rollFinish,
	rollMutation = rollMutation,
	finishOdds = finishOdds,
	mutationOdds = mutationOdds,
})

return Economy

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
	incubatorSlots = 3,
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
	basePlotsPerServer = 8,

	-- Creatures menu. A creature sells for this many seconds of its own earnings:
	-- low enough that a fresh hatch sells for less than its egg on average, even in
	-- a Blood Moon, so buying eggs just to sell them never pays.
	sellValueSeconds = 15,
	storageSlots = 40, -- off-pedestal creatures; buying and stealing stop when full

	-- Rebirth N costs rebirthCosts[N]; after the list each one costs 10× the last.
	-- ×10 per step (eggs cost ×8 per biome, earnings grow ×4), so every rebirth
	-- takes a little longer than the one before. First pass; tune in playtests.
	rebirthCosts = { 25_000, 250_000, 2_500_000, 25_000_000, 250_000_000 },

	-- Moon events
	moonEventIntervalSeconds = 60 * 60,
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
	return costs[#costs] * 10 ^ (nth - #costs)
end

local maxBiomeOrder = 0
for _, biome in Biomes do
	maxBiomeOrder = math.max(maxBiomeOrder, biome.order)
end

-- Highest Biomes[].order whose eggs a player may buy: each rebirth unlocks the next.
local function unlockedBiome(rebirthsDone: number): number
	return math.min(maxBiomeOrder, rebirthsDone + 1)
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
local function rollFinish(rng: Random, activeEventId: string?, chanceMultiplier: number): string
	local ordered = table.clone(Finishes)
	table.sort(ordered, function(a, b)
		return (a.oneIn or 0) > (b.oneIn or 0)
	end)
	for _, finish in ordered do
		local oneIn = finish.oneIn
		local eligible = oneIn ~= nil and (finish.eventOnly == nil or finish.eventOnly == activeEventId)
		if eligible and rng:NextNumber() < chanceMultiplier / (oneIn :: number) then
			return finish.id
		end
	end
	return "Normal"
end

-- Rolls at most one genetic mutation.
local function rollMutation(rng: Random): string?
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, mutation in Mutations do
		cumulative += mutation.chance
		if roll < cumulative then
			return mutation.id
		end
	end
	return nil
end

local Economy = table.freeze({
	tunables = Tunables,
	maxBiomeOrder = maxBiomeOrder,
	cashPerSecond = cashPerSecond,
	sellValue = sellValue,
	rebirthCost = rebirthCost,
	unlockedBiome = unlockedBiome,
	secondsToNextStage = secondsToNextStage,
	rollFinish = rollFinish,
	rollMutation = rollMutation,
})

return Economy

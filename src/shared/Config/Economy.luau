--!strict
-- Economy tunables + pure helper math (no Roblox services, safe on client and server).
local Types = require(script.Parent.Types)
local Rarities = require(script.Parent.Rarities)
local Stages = require(script.Parent.Stages)
local Finishes = require(script.Parent.Finishes)
local Mutations = require(script.Parent.Mutations)
local Biomes = require(script.Parent.Biomes)
local BaseBuilds = require(script.Parent.BaseBuilds)
local Eggs = require(script.Parent.Eggs)
local Creatures = require(script.Parent.Creatures)

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
	basePlotsPerServer = 6, -- also set Max Players = 6 in Game Settings → Places

	-- What a creature is worth (sellValue, the Creatures menu's Sell): this share of
	-- its egg's price for an average Adult from that egg, more or less with its
	-- earnings, and never under sellValueSeconds of its own earnings for its stage.
	-- A fresh hatch (a Baby) stays worth less than its egg on average, even in a
	-- Blood Moon, so buying eggs just to sell them never pays; grown creatures took
	-- half an hour to hours to raise, so they're worth minutes of their earnings.
	sellEggShare = 0.5,
	sellValueSeconds = { Baby = 15, Juvenile = 120, Adult = 600 } :: { [Types.StageId]: number },
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
	-- thieves) and lengthens the laser lock. Levels 2-3 add 5 ground pedestals each
	-- (`pedestals` = ground pedestals, up to 20, in two wings either side of an open
	-- hall); levels 3 and 4 open the floors above (`floors`).
	baseLevels = {
		{ cost = 0, pedestals = 10, lockBonusSeconds = 0 },
		{ cost = 60_000, pedestals = 15, lockBonusSeconds = 15 },
		{ cost = 25_000_000, pedestals = 20, lockBonusSeconds = 30 },
		{ cost = 5_000_000_000, pedestals = 20, lockBonusSeconds = 45 },
		{ cost = 500_000_000_000, pedestals = 20, lockBonusSeconds = 60 },
	},

	-- Floors (owner, 2026-10-01), bought in order in the Base menu. Each adds 9
	-- pedestals one story up (owner, 2026-10-02: "more spots on second and third
	-- floors": a row of 5 behind the front arches and 2 along each side wall):
	-- harder to steal from, since thieves must climb the ramps, the Steal hold gets
	-- longer each floor up (`floorStealHold`), and the creature has to be carried all
	-- the way back down. Each floor also has room for two vaults. Floor 1 is the
	-- ground.
	floors = {
		{ name = "Second Floor", cost = 800_000_000, baseLevel = 3, pedestals = 9 },
		{ name = "Top Floor", cost = 60_000_000_000, baseLevel = 4, pedestals = 9 },
	},
	floorStealHold = 0.5, -- each floor up adds 50% to the Steal hold

	-- Vaults: single rooms for one creature each, behind a door the owner locks for
	-- `vaultLockSeconds` (then `vaultCooldownSeconds` before it can lock again).
	-- While locked nothing inside can be stolen; unlocked, the Steal hold is
	-- `vaultStealHold`× longer. Bought in order; each needs its floor.
	vaults = {
		{ cost = 1_500_000_000, floor = 2 },
		{ cost = 3_000_000_000, floor = 2 },
		{ cost = 120_000_000_000, floor = 3 },
		{ cost = 250_000_000_000, floor = 3 },
	},
	vaultLockSeconds = 180,
	vaultCooldownSeconds = 60,
	vaultStealHold = 2,

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
			description = "Your laser gate and vaults lock themselves when an intruder walks in (if charged)",
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
	local mutation = if stats.mutation then mutationById[stats.mutation] else nil
	local mutationMultiplier = if mutation then mutation.earningsMultiplier else 1
	if stats.homegrown then
		bonus += Tunables.homegrownBonus
	end
	local biome = Biomes[stats.biome]
	local biomeMultiplier = if biome then biome.earningsMultiplier else 1
	return rarity.baseCashPerSec
		* biomeMultiplier
		* stage.earningsMultiplier
		* finish.earningsMultiplier
		* mutationMultiplier
		* bonus
end

-- What an average Adult hatched from a biome's egg earns (no finish or mutation,
-- homegrown as hatched creatures are), worked out once per biome.
local creaturesById: { [string]: Types.Creature } = {}
for _, creature in Creatures do
	creaturesById[creature.id] = creature
end
local averageAdult: { [string]: number } = {}
local function averageAdultRate(biomeId: string): number
	local cached = averageAdult[biomeId]
	if cached then
		return cached
	end
	local total = 0
	for _, entry in Eggs.speciesOdds(biomeId, false) do
		local creature = creaturesById[entry.id]
		if creature then
			total += entry.chance * cashPerSecond({
				biome = biomeId,
				rarity = creature.rarity,
				stage = "Adult",
				finish = "Normal",
				homegrown = true,
			})
		end
	end
	averageAdult[biomeId] = total
	return total
end

-- What a creature is worth: the Creatures menu's Sell price, and how bases rank
-- their creatures (Rarest up top, statues). An average Adult from an egg is worth
-- half that egg; better earners are worth more in proportion, so a rare hatch is
-- worth many eggs (owner, 2026-10-03: a Lunaris earning ~2M/s "only worth 13M"
-- made no sense; it was 15 s of earnings everywhere, a sliver of a Moonfall egg).
-- Never under minutes of its own earnings once grown (10 for an Adult), so a rare
-- creature from a cheap early egg isn't near-worthless either. A Baby's floor is
-- only 15 s, so hatching to sell straight away always loses.
local function sellValue(stats: CreatureInstanceStats): number
	local rate = cashPerSecond(stats)
	local average = averageAdultRate(stats.biome)
	local basis = if average > 0 then Eggs.price(stats.biome) * Tunables.sellEggShare * rate / average else 0
	return math.floor(math.max(basis, rate * (Tunables.sellValueSeconds[stats.stage] or 15)))
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

-- Pedestal slots: 1-20 on the ground, 21-29 on the Second Floor, 30-38 on the
-- Top Floor, the vaults at 41-44 (`VAULT_SLOT_BASE` + vault number) and the
-- hiding spots at 51-54 (`HIDE_SLOT_BASE` + spot number, Config.BaseBuilds).
-- The floors' pedestals must stay under VAULT_SLOT_BASE (20 at most).
local GROUND_SLOTS = 20
local VAULT_SLOT_BASE = 40
local HIDE_SLOT_BASE = 50

-- The floor (1 = ground) a pedestal slot stands on.
local function slotFloor(slot: number): number
	if slot > VAULT_SLOT_BASE then
		local vault = Tunables.vaults[slot - VAULT_SLOT_BASE]
		return if vault then vault.floor else 1
	end
	local floor, last = 1, GROUND_SLOTS
	for i, extra in Tunables.floors do
		if slot <= last then
			return floor
		end
		floor, last = i + 1, last + extra.pedestals
	end
	return floor
end

-- The vault number a slot belongs to, or nil for an open pedestal.
local function vaultOfSlot(slot: number?): number?
	if slot and slot > VAULT_SLOT_BASE and Tunables.vaults[slot - VAULT_SLOT_BASE] then
		return slot - VAULT_SLOT_BASE
	end
	return nil
end

local function vaultSlot(vault: number): number
	return VAULT_SLOT_BASE + vault
end

-- The hiding spot a slot is, or nil.
local function hideOfSlot(slot: number?): number?
	if slot and slot > HIDE_SLOT_BASE and BaseBuilds.hidingSpots[slot - HIDE_SLOT_BASE] then
		return slot - HIDE_SLOT_BASE
	end
	return nil
end

local function hideSlot(spot: number): number
	return HIDE_SLOT_BASE + spot
end

-- Every pedestal slot a base has, in fill order: the ground, the floors bought
-- (`floors` counts the ground: 1-3), the vaults bought, then the hiding spots.
local function slots(level: number, floors: number, vaults: number, hides: number?): { number }
	local list: { number } = {}
	for slot = 1, baseLevel(level).pedestals do
		table.insert(list, slot)
	end
	local first = GROUND_SLOTS + 1
	for i, extra in Tunables.floors do
		if i + 1 > floors then
			break
		end
		for slot = first, first + extra.pedestals - 1 do
			table.insert(list, slot)
		end
		first += extra.pedestals
	end
	for vault = 1, math.min(vaults, #Tunables.vaults) do
		table.insert(list, VAULT_SLOT_BASE + vault)
	end
	for spot = 1, math.min(hides or 0, #BaseBuilds.hidingSpots) do
		table.insert(list, HIDE_SLOT_BASE + spot)
	end
	return list
end

local Economy = table.freeze({
	baseLevel = baseLevel,
	slotFloor = slotFloor,
	vaultOfSlot = vaultOfSlot,
	vaultSlot = vaultSlot,
	hideOfSlot = hideOfSlot,
	hideSlot = hideSlot,
	slots = slots,
	groundSlots = GROUND_SLOTS,
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

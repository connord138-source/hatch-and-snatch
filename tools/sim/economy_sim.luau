-- Economy pacing simulator: plays the real Config (src/shared/Config) as a
-- reasonably efficient player and reports when each milestone lands.
-- Run: bash tools/sim/run_economy_sim.sh [runs]
--
-- The player model:
--  * Plays one session of `activeHours` a day; the rest of the day is offline
--    (creatures keep growing, eggs finish, earnings accrue up to the offline cap).
--  * Keeps the best current earners on pedestals; everything else grows in
--    storage and the worst potential is sold when storage is full.
--  * Buys upgrades (base level, incubator slots, incubator tiers needed for the
--    best unlocked biome) as soon as they're affordable, cheapest first.
--  * Spends up to half its income on eggs: always the best unlocked egg it can
--    afford and fit, one per trip to the belt (HANDLE_SECONDS), as fast as the
--    belt (shared with 5 others) and its incubators allow. Uses Luck Wheel spins.
--  * Rebirths only once nothing else is left to buy.
-- No stealing, zone Essence, moon events, passes or products: this is the
-- free-to-play baseline.
local Config = require("./Config")

local Economy = Config.Economy
local Eggs = Config.Eggs
local Progression = Config.Progression
local Rarities = Config.Rarities
local Biomes = Config.Biomes
local T = Economy.tunables

local args = { ... }
local RUNS = tonumber(args[1]) or 5
local DAYS = 30
local STEP = 10 -- seconds per active tick
local BELT_SHARE = 0.4 -- share of each biome's belt eggs this player gets
local EGG_BUDGET = 0.5 -- share of collected income the player spends on eggs
local HANDLE_SECONDS = 25 -- walk to the belt, buy, carry home, place: one egg at a time

local PROFILES = {
	{ name = "Casual 1h/day", activeHours = 1 },
	{ name = "Regular 3h/day", activeHours = 3 },
	{ name = "Grinder 8h/day", activeHours = 8 },
	{ name = "Marathon 12h/day", activeHours = 12 },
}

local biomeList = {}
for id, biome in Biomes do
	if biome.order > 0 then
		table.insert(biomeList, id)
	end
end
table.sort(biomeList, function(a, b)
	return Biomes[a].order < Biomes[b].order
end)

local rng = { NextNumber = function()
	return math.random()
end }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function rateOf(c, rebirths: number): number
	return Economy.cashPerSecond(c) * (1 + rebirths * T.rebirthBonusPerLevel)
end

local function potentialOf(c): number
	if c.potential then
		return c.potential
	end
	c.potential = Economy.cashPerSecond({
		biome = c.biome,
		rarity = c.rarity,
		stage = "Adult",
		finish = c.finish,
		mutation = c.mutation,
		homegrown = c.homegrown,
	})
	return c.potential
end

-- Expected adult cash/s of one egg (for "is this egg worth buying").
local eggPotentialCache = {}
local function eggPotential(biomeId: string): number
	local cached = eggPotentialCache[biomeId]
	if cached then
		return cached
	end
	local total = 0
	for _, entry in Eggs.speciesOdds(biomeId, false, 1) do
		local species = Config.CreaturesById[entry.id]
		total += entry.chance
			* Economy.cashPerSecond({
				biome = biomeId,
				rarity = species.rarity,
				stage = "Adult",
				finish = "Normal",
				homegrown = true,
			})
	end
	eggPotentialCache[biomeId] = total
	return total
end

local function level(s): number
	if s.levelXp ~= s.xp then
		s.levelXp = s.xp
		s.level = (Progression.levelFromXp(s.xp))
	end
	return s.level
end

local function pedestals(s): number
	return #Economy.slots(s.baseLevel, s.floors, s.vaults)
end

local function fmtCash(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local i = 1
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return if n >= 100 then string.format("$%.0f%s", n, units[i]) else string.format("$%.1f%s", n, units[i])
end

---------------------------------------------------------------------------
-- One player
---------------------------------------------------------------------------

local function newState()
	return {
		t = 0,
		active = 0, -- seconds played
		cash = T.startingCash,
		eggBudget = T.startingCash,
		xp = 0,
		level = 1,
		levelXp = 0,
		baseLevel = 1,
		floors = 1, -- counting the ground
		vaults = 0,
		rebirths = 0,
		incubators = { { tier = 1, egg = nil } },
		creatures = {},
		discovered = {},
		stats = {
			hatched = 0,
			eggsBought = 0,
			adults = 0,
			steals = 0,
			discovered = 0,
			finishes = 0,
			baseUpgrades = 0,
			incubators = 1,
			walkSeconds = 0,
			spinsUsed = 0,
			earned = 0,
		},
		achievements = {},
		spins = T.startingSpins,
		spinProgress = 0,
		luckCharge = 1,
		nextEgg = {},
		income = 0,
		incomeDirty = true,
		milestones = {},
		log = {},
	}
end

local function mark(s, key: string)
	if s.milestones[key] == nil then
		s.milestones[key] = { active = s.active, day = s.t / 86400 }
	end
end

local function checkAchievements(s)
	for _, a in Progression.achievements do
		if not s.achievements[a.id] and (s.stats[a.stat] or 0) >= a.goal then
			s.achievements[a.id] = true
			s.xp += a.xp
			s.spins += a.spins
		end
	end
end

local function addXp(s, amount: number)
	s.xp += amount
end

local function refreshUnlocks(s)
	local lvl = level(s)
	for _, id in biomeList do
		if Progression.biomeUnlocked(id, lvl, s.baseLevel) then
			mark(s, "unlock " .. id)
		end
	end
	for _, l in { 5, 12, 20, 30, 40, 50 } do
		if lvl >= l then
			mark(s, "level " .. l)
		end
	end
end

-- Pedestals hold the best current earners; recomputed when creatures change.
local function recomputeIncome(s)
	local rates = {}
	for _, c in s.creatures do
		table.insert(rates, rateOf(c, s.rebirths))
	end
	table.sort(rates, function(a, b)
		return a > b
	end)
	local total = 0
	for i = 1, math.min(pedestals(s), #rates) do
		total += rates[i]
	end
	s.income = total
	s.incomeDirty = false
end

local function grow(s, now: number)
	for _, c in s.creatures do
		local need = Economy.secondsToNextStage(c.rarity, c.stage)
		while need and now >= c.stageStart + need do
			c.stageStart += need
			c.stage = if c.stage == "Baby" then "Juvenile" else "Adult"
			addXp(s, if c.stage == "Adult" then Progression.xp.growAdult else Progression.xp.growJuvenile)
			if c.stage == "Adult" then
				s.stats.adults += 1
			end
			s.incomeDirty = true
			need = Economy.secondsToNextStage(c.rarity, c.stage)
		end
	end
end

local function capacity(s): number
	return pedestals(s) + T.storageSlots
end

-- Sells the creature with the lowest potential (to make room).
local function sellWorst(s)
	local worstIndex, worst = nil, math.huge
	for i, c in s.creatures do
		local p = potentialOf(c)
		if p < worst then
			worst, worstIndex = p, i
		end
	end
	if worstIndex then
		local c = table.remove(s.creatures, worstIndex)
		s.cash += Economy.sellValue(c)
		s.incomeDirty = true
	end
end

local function hatch(s, inc, now: number)
	local egg = inc.egg
	inc.egg = nil
	local c = {
		biome = egg.biome,
		rarity = egg.rarity,
		stage = "Baby",
		stageStart = egg.hatchAt,
		finish = Economy.rollFinish(rng, nil, 1),
		mutation = Economy.rollMutation(rng),
		homegrown = true,
	}
	while #s.creatures >= capacity(s) do
		sellWorst(s)
	end
	table.insert(s.creatures, c)
	s.incomeDirty = true
	s.stats.hatched += 1
	if c.finish ~= "Normal" then
		s.stats.finishes += 1
	end
	if not s.discovered[egg.species] then
		s.discovered[egg.species] = true
		s.stats.discovered += 1
		addXp(s, Progression.xp.newSpecies)
	end
	addXp(s, Progression.xp.hatchPerBiomeOrder * Biomes[egg.biome].order)
	if Rarities[c.rarity].order >= 6 then
		mark(s, "first ultra-rare")
	end
end

local function hatchReady(s, now: number)
	for _, inc in s.incubators do
		if inc.egg and now >= inc.egg.hatchAt then
			hatch(s, inc, now)
		end
	end
end

local function collect(s, amount: number)
	s.cash += amount
	s.eggBudget += amount * EGG_BUDGET
	s.stats.earned += amount
end

local function spend(s, amount: number)
	s.cash -= amount
	s.eggBudget = math.min(s.eggBudget, s.cash)
end

-- Cheapest pending upgrade: next base level, next incubator slot, or an
-- incubator tier the best unlocked biome needs.
local function nextUpgrade(s): (string?, number, any)
	local best, cost, detail = nil, math.huge, nil
	local nextLevel = T.baseLevels[s.baseLevel + 1]
	if nextLevel and nextLevel.cost < cost then
		best, cost = "base", nextLevel.cost
	end
	local nextFloor = T.floors[s.floors]
	if nextFloor and s.baseLevel >= nextFloor.baseLevel and nextFloor.cost < cost then
		best, cost = "floor", nextFloor.cost
	end
	local nextVault = T.vaults[s.vaults + 1]
	if nextVault and s.floors >= nextVault.floor and nextVault.cost < cost then
		best, cost = "vault", nextVault.cost
	end
	local slotCost = Progression.incubatorSlotCosts[#s.incubators + 1]
	if slotCost and slotCost < cost then
		best, cost = "slot", slotCost
	end
	local lvl = level(s)
	local neededTier = 1
	for _, id in biomeList do
		if Progression.biomeUnlocked(id, lvl, s.baseLevel) then
			neededTier = math.max(neededTier, Progression.tierForBiome(Biomes[id].order))
		end
	end
	for i, inc in s.incubators do
		if inc.tier < neededTier then
			local tierCost = Progression.incubatorTiers[inc.tier + 1].upgradeCost
			if tierCost < cost then
				best, cost, detail = "tier", tierCost, i
			end
		end
	end
	return best, cost, detail
end

local function buyUpgrades(s)
	while true do
		local kind, cost, detail = nextUpgrade(s)
		if kind == nil or cost > s.cash then
			break
		end
		spend(s, cost)
		if kind == "base" then
			s.baseLevel += 1
			s.stats.baseUpgrades += 1
			addXp(s, Progression.xp.baseUpgradePerLevel * s.baseLevel)
			s.incomeDirty = true
			mark(s, "base " .. s.baseLevel)
		elseif kind == "floor" then
			s.floors += 1
			addXp(s, Progression.xp.baseUpgradePerLevel * (s.floors + 2))
			s.incomeDirty = true
			mark(s, "floor " .. s.floors)
		elseif kind == "vault" then
			s.vaults += 1
			addXp(s, Progression.xp.baseUpgradePerLevel * (s.vaults + 2))
			s.incomeDirty = true
			mark(s, "vault " .. s.vaults)
		elseif kind == "slot" then
			table.insert(s.incubators, { tier = 1, egg = nil })
			s.stats.incubators = #s.incubators
			addXp(s, Progression.xp.incubatorBought)
			mark(s, "incubators " .. #s.incubators)
		else
			local inc = s.incubators[detail]
			inc.tier += 1
			addXp(s, Progression.xp.incubatorUpgraded)
			mark(s, "tier " .. Progression.incubatorTiers[inc.tier].name)
		end
	end
	-- Rebirth once nothing else is left to buy
	if nextUpgrade(s) == nil then
		mark(s, "everything bought")
		local cost = Economy.rebirthCost(s.rebirths)
		if s.cash >= cost then
			s.rebirths += 1
			s.cash = T.startingCash
			s.eggBudget = T.startingCash
			s.spins += 3
			s.incomeDirty = true
			mark(s, "rebirth " .. s.rebirths)
		end
	end
end

local function useSpins(s)
	while s.spins > 0 and s.luckCharge == 1 do
		s.spins -= 1
		s.stats.spinsUsed += 1
		local total = 0
		for _, seg in T.luckWheel do
			total += seg.weight
		end
		local roll = math.random() * total
		for _, seg in T.luckWheel do
			roll -= seg.weight
			if roll <= 0 then
				if seg.kind == "luck" then
					s.luckCharge = math.max(s.luckCharge, seg.value)
				elseif seg.kind == "cash" then
					collect(s, math.max(500, s.income * 60 * seg.value))
				else
					s.spins += seg.value
				end
				break
			end
		end
	end
end

local function buyEggs(s, now: number)
	if now < (s.nextTrip or 0) then
		return
	end
	local lvl = level(s)
	for _, inc in s.incubators do
		if inc.egg == nil and now >= (s.nextTrip or 0) then
			local tier = Progression.incubatorTiers[inc.tier]
			local choice = nil
			for i = #biomeList, 1, -1 do
				local id = biomeList[i]
				local biome = Biomes[id]
				local price = Eggs.price(id)
				if
					Progression.biomeUnlocked(id, lvl, s.baseLevel)
					and biome.order <= tier.maxBiomeOrder
					and price <= s.eggBudget
					and now >= (s.nextEgg[id] or 0)
				then
					choice = id
					break
				end
			end
			if choice then
				local price = Eggs.price(choice)
				spend(s, price)
				s.eggBudget -= price
				s.stats.eggsBought += 1
				local species = Eggs.rollSpecies(choice, rng, false, s.luckCharge)
				s.luckCharge = 1
				local rarity = Config.CreaturesById[species].rarity
				inc.egg = {
					species = species,
					biome = choice,
					rarity = rarity,
					hatchAt = now + Rarities[rarity].hatchSeconds / tier.speed,
				}
				-- The next egg of this biome rides past after a random wait
				local perSecond = Eggs.conveyorWeights[choice] / 100 / Eggs.conveyor.spawnSeconds * BELT_SHARE
				s.nextEgg[choice] = now - math.log(1 - math.random()) / perSecond
				useSpins(s)
				s.nextTrip = now + HANDLE_SECONDS
			end
		end
	end
end

local function offline(s, seconds: number)
	local now = s.t + seconds
	-- Eggs hatch and creatures grow the whole time; earnings use the rate at return
	for _, inc in s.incubators do
		if inc.egg and now >= inc.egg.hatchAt then
			hatch(s, inc, inc.egg.hatchAt)
		end
	end
	grow(s, now)
	recomputeIncome(s)
	collect(s, s.income * math.min(seconds, T.offlineCapSeconds))
	s.t = now
end

local function playSession(s, seconds: number)
	local stop = s.t + seconds
	local sinceIncome = 0
	while s.t < stop do
		s.t += STEP
		s.active += STEP
		hatchReady(s, s.t)
		sinceIncome += STEP
		if sinceIncome >= 30 then
			grow(s, s.t)
			sinceIncome = 0
		end
		if s.incomeDirty then
			recomputeIncome(s)
		end
		collect(s, s.income * STEP)
		s.spinProgress += STEP
		if s.spinProgress >= T.freeSpinSeconds then
			s.spinProgress -= T.freeSpinSeconds
			s.spins = math.min(s.spins + 1, T.maxBankedSpins)
		end
		if sinceIncome == 0 then
			checkAchievements(s)
			refreshUnlocks(s)
			buyUpgrades(s)
		end
		buyEggs(s, s.t)
	end
end

local function simulate(profile)
	local s = newState()
	local active = profile.activeHours * 3600
	local dayIncome = {}
	for day = 1, DAYS do
		playSession(s, active)
		offline(s, 86400 - active)
		dayIncome[day] = s.income
	end
	return s, dayIncome
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

local MILESTONES = {
	"unlock CoralCoast",
	"base 2",
	"incubators 3",
	"unlock MagmaRift",
	"base 3",
	"floor 2",
	"vault 2",
	"unlock FrostShelf",
	"base 4",
	"floor 3",
	"vault 4",
	"unlock StormPeaks",
	"base 5",
	"unlock Moonfall",
	"incubators 6",
	"tier Cosmic",
	"everything bought",
	"rebirth 1",
	"rebirth 3",
	"rebirth 5",
	"first ultra-rare",
}

local function when(m): string
	if m == nil then
		return "—"
	end
	local hours = m.active / 3600
	local played = if hours < 1 then string.format("%dm", math.floor(m.active / 60)) else string.format("%.1fh", hours)
	return string.format("day %d (%s played)", math.floor(m.day) + 1, played)
end

local function median(values: { number }): number
	table.sort(values)
	return values[math.ceil(#values / 2)]
end

print(`Economy sim: {RUNS} runs per profile, {DAYS} days, belt share {BELT_SHARE}, egg budget {EGG_BUDGET}`)
for _, profile in PROFILES do
	local runs = {}
	for r = 1, RUNS do
		math.randomseed(r * 7919)
		local s, dayIncome = simulate(profile)
		table.insert(runs, { s = s, dayIncome = dayIncome })
	end
	print(`\n== {profile.name} ==`)
	for _, key in MILESTONES do
		local actives, days = {}, {}
		for _, run in runs do
			local m = run.s.milestones[key]
			table.insert(actives, if m then m.active else math.huge)
			table.insert(days, if m then m.day else math.huge)
		end
		local a, d = median(actives), median(days)
		print(string.format("  %-20s %s", key, if a == math.huge then "—" else when({ active = a, day = d })))
	end
	local line = {}
	for _, day in { 1, 2, 3, 7, 14, 30 } do
		local values = {}
		for _, run in runs do
			table.insert(values, run.dayIncome[day])
		end
		table.insert(line, `d{day} {fmtCash(median(values))}/s`)
	end
	print("  income: " .. table.concat(line, ", "))
	local levels, rebirths = {}, {}
	for _, run in runs do
		table.insert(levels, level(run.s))
		table.insert(rebirths, run.s.rebirths)
	end
	print(`  after {DAYS} days: Hatcher Lv {median(levels)}, {median(rebirths)} rebirths`)
end

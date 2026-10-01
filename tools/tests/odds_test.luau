-- Paid random items: the odds players see must be the odds they get.
-- Every odds table sums to 1, and rolls follow the displayed odds.
local Config = require("./Config")
local Economy, Eggs = Config.Economy, Config.Eggs

local failures = 0
local function check(ok: boolean, message: string)
	if not ok then
		failures += 1
		print("FAIL " .. message)
	end
end
local function sum(odds): number
	local total = 0
	for _, entry in odds do
		total += entry.chance
	end
	return total
end

local events = { false }
for _, event in Config.MoonEvents do
	table.insert(events, event)
end
for biomeId in Config.Biomes do
	for _, luck in { 1, 2, 3, 10, 25, 125 } do
		for _, event in events do
			local odds = Eggs.speciesOdds(biomeId, event ~= false, luck)
			check(math.abs(sum(odds) - 1) < 1e-9, `species {biomeId} luck {luck}: sums to {sum(odds)}`)
		end
	end
end
for _, event in events do
	local id = if event then event.id else nil
	local multiplier = if event then event.finishChanceMultiplier else 1
	local odds = Economy.finishOdds(id, multiplier)
	check(math.abs(sum(odds) - 1) < 1e-9, `finishes {id}: sums to {sum(odds)}`)
end
check(math.abs(sum(Economy.mutationOdds()) - 1) < 1e-9, "mutations sum to 1")

-- Sampling matches the table (Blood Moon: event finish + ×5 multiplier)
local rng = { NextNumber = function()
	return math.random()
end }
math.randomseed(42)
local odds = Economy.finishOdds("BloodMoon", 5)
local counts = {}
local N = 400000
for _ = 1, N do
	local id = Economy.rollFinish(rng :: any, "BloodMoon", 5)
	counts[id] = (counts[id] or 0) + 1
end
for _, entry in odds do
	local seen = (counts[entry.id] or 0) / N
	local tolerance = 4 * math.sqrt(entry.chance * (1 - entry.chance) / N) + 1e-5
	check(math.abs(seen - entry.chance) <= tolerance, `roll {entry.id}: {seen} vs {entry.chance}`)
end
print(if failures == 0 then "odds: all tables sum to 100% and rolls match" else `odds: {failures} failure(s)`)

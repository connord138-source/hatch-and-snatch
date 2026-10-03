--!strict
-- What an egg can give and the exact odds, for the odds panel (OddsController).
-- Eggs are paid random items (Robux can buy cash, and Server Luck changes the
-- odds), so every outcome's chance is shown before purchase, as percentages that
-- add up to 100, updated live for luck and moon events. The server rolls with
-- the same functions (HatchService.giveEgg), so the panel is exactly right.
local Config = require(script.Parent.Config)
local EconomyConfig = require(script.Parent.Config.Economy)

export type Line = { label: string, detail: string?, percent: string, color: Color3? }
export type EggOdds = { species: { Line }, finishes: { Line }, mutations: { Line } }

local DECIMALS = 4 -- enough to show a 1-in-20,000 Secret (0.0050%)

local Odds = {}

-- Percent strings with DECIMALS places that add up to exactly 100 (largest remainder).
function Odds.percents(chances: { number }): { string }
	local scale = 100 * 10 ^ DECIMALS
	local units: { number } = {}
	local order: { number } = {}
	local total = 0
	for i, chance in chances do
		units[i] = math.floor(chance * scale)
		total += units[i]
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		return chances[a] * scale - units[a] > chances[b] * scale - units[b]
	end)
	for k = 1, math.max(0, scale - total) do
		local i = order[(k - 1) % #order + 1]
		units[i] += 1
	end
	local out: { string } = {}
	for i, unit in units do
		out[i] = string.format(`%.{DECIMALS}f%%`, unit / 10 ^ DECIMALS)
	end
	return out
end

-- The luck a new egg of `biomeId` rolls with: the player's Luck Wheel charge ×
-- Server Luck (Junk eggs ignore luck), as in HatchService.giveEgg.
function Odds.luck(biomeId: string, luckCharge: number, serverLuck: number): number
	if biomeId == "Junk" then
		return 1
	end
	return (if luckCharge > 1 then luckCharge else 1) * math.max(serverLuck, 1)
end

local function eventById(eventId: string?): Config.MoonEvent?
	for _, event in Config.MoonEvents do
		if event.id == eventId then
			return event
		end
	end
	return nil
end

-- Every outcome of one egg: species, finish and mutation, each list summing to 100%.
function Odds.forEgg(biomeId: string, eventId: string?, luck: number): EggOdds
	local species = Config.Eggs.speciesOdds(biomeId, eventId ~= nil, if luck > 1 then luck else nil)
	table.sort(species, function(a, b)
		return a.chance > b.chance
	end)
	local chances: { number } = {}
	for i, entry in species do
		chances[i] = entry.chance
	end
	local percents = Odds.percents(chances)
	local speciesLines: { Line } = {}
	for i, entry in species do
		local creature = Config.CreaturesById[entry.id]
		local rarity = Config.Rarities[creature.rarity]
		table.insert(speciesLines, {
			label = creature.displayName,
			detail = tostring(creature.rarity),
			percent = percents[i],
			color = rarity.color,
		})
	end

	local event = eventById(eventId)
	local function lines(odds: { EconomyConfig.Chance }, names: { [string]: string }): { Line }
		local list: { number } = {}
		for i, entry in odds do
			list[i] = entry.chance
		end
		local texts = Odds.percents(list)
		local out: { Line } = {}
		for i, entry in odds do
			table.insert(out, { label = names[entry.id] or entry.id, percent = texts[i] })
		end
		return out
	end
	local finishNames: { [string]: string } = {}
	for _, finish in Config.Finishes do
		finishNames[finish.id] = finish.displayName
	end
	local mutationNames: { [string]: string } = { None = "No mutation" }
	for _, mutation in Config.Mutations do
		mutationNames[mutation.id] = mutation.displayName
	end
	return {
		species = speciesLines,
		finishes = lines(
			Config.Economy.finishOdds(eventId, if event then event.finishChanceMultiplier else 1),
			finishNames
		),
		mutations = lines(Config.Economy.mutationOdds(), mutationNames),
	}
end

return Odds

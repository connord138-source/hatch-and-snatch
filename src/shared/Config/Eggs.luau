--!strict
-- Egg odds, prices and conveyor tunables. Odds here are also what the game shows
-- players (required for any Robux-purchasable random item).
local Types = require(script.Parent.Types)
local Creatures = require(script.Parent.Creatures)
local Rarities = require(script.Parent.Rarities)
local Biomes = require(script.Parent.Biomes)

export type SpeciesOdds = { id: string, chance: number }

local basePrice = 150

-- Species weight inside a biome egg = weight of its rarity.
local rarityWeights: { [Types.RarityId]: number } = {
	Common = 60,
	Uncommon = 25,
	Rare = 11,
	Epic = 3,
	Legendary = 1,
	Mythic = 0.1, -- ~1 in 1,000
	Celestial = 0.03, -- ~1 in 3,300, moon events only
	Cosmic = 0.01, -- ~1 in 10,000, Moonfall only
	Secret = 0.002, -- ~1 in 50,000
	Junk = 0,
}

-- Per-biome overrides. Moonfall eggs start at Rare, so the shared weights would
-- make its ultra-rares ~7x more common than anywhere else.
local biomeRarityWeights: { [string]: { [string]: number } } = {
	Moonfall = {
		Mythic = 0.015, -- ~1 in 1,000
		Cosmic = 0.0015, -- ~1 in 10,000 each
	},
}

-- Junk Egg uses per-species weights instead (comic creatures, rarest last).
local junkWeights: { [string]: number } = {
	Toastoise = 30,
	Fridgehog = 25,
	Grillgator = 20,
	Laundrophant = 12,
	Lawnmoose = 8,
	Bassdog = 5,
	Nullcat = 0.002, -- Secret
}

-- How often each biome's egg shows up on the shared conveyor.
local conveyorWeights: { [string]: number } = {
	Mossvale = 40,
	CoralCoast = 25,
	MagmaRift = 15,
	FrostShelf = 10,
	StormPeaks = 6,
	Moonfall = 4,
	Junk = 10, -- only while a moon event with spawnsJunkEgg is active
}

local eggColors: { [string]: Color3 } = {
	Mossvale = Color3.fromRGB(96, 140, 70),
	CoralCoast = Color3.fromRGB(240, 170, 160),
	MagmaRift = Color3.fromRGB(45, 38, 38),
	FrostShelf = Color3.fromRGB(170, 215, 245),
	StormPeaks = Color3.fromRGB(110, 120, 150),
	Moonfall = Color3.fromRGB(70, 40, 120),
	Junk = Color3.fromRGB(190, 190, 195),
}

local conveyor = {
	spawnSeconds = 2.5,
	speed = 7, -- studs per second along the loop
	radius = 46,
	height = 3.4,
}

local function price(biomeId: string): number
	return basePrice * Biomes[biomeId].eggPriceMultiplier
end

-- Normalized odds for one egg. `eventActive` unlocks event-only species (Celestial).
local function speciesOdds(biomeId: string, eventActive: boolean): { SpeciesOdds }
	local weighted: { SpeciesOdds } = {}
	local total = 0
	for _, creature in Creatures do
		if creature.biome == biomeId then
			local weight: number
			if biomeId == "Junk" then
				weight = junkWeights[creature.id] or 0
			elseif Rarities[creature.rarity].eventOnly and not eventActive then
				weight = 0
			else
				local override = biomeRarityWeights[biomeId]
				weight = (override and override[creature.rarity]) or rarityWeights[creature.rarity]
			end
			if weight > 0 then
				table.insert(weighted, { id = creature.id, chance = weight })
				total += weight
			end
		end
	end
	for _, entry in weighted do
		entry.chance /= total
	end
	return weighted
end

local function rollSpecies(biomeId: string, rng: Random, eventActive: boolean): string
	local odds = speciesOdds(biomeId, eventActive)
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, entry in odds do
		cumulative += entry.chance
		if roll < cumulative then
			return entry.id
		end
	end
	return odds[#odds].id
end

return table.freeze({
	basePrice = basePrice,
	rarityWeights = rarityWeights,
	biomeRarityWeights = biomeRarityWeights,
	junkWeights = junkWeights,
	conveyorWeights = conveyorWeights,
	eggColors = eggColors,
	conveyor = conveyor,
	price = price,
	speciesOdds = speciesOdds,
	rollSpecies = rollSpecies,
})

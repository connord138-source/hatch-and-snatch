--!strict
-- Biome zones: each biome has a walled zone on the island, gated by the same
-- requirement as its eggs (Progression.biomeRequirements). Inside are harvest
-- nodes that give that biome's Essence, and a shrine that spends it on an egg
-- of that biome or on the biome's own blessing. Releasing a creature also pays
-- Essence of its biome (see releaseEssence).

export type BlessingKind = "cash" | "spins" | "hatchSpeed" | "luck" | "xp"

export type ZoneInfo = {
	essence: string, -- "Moss Essence"
	node: string, -- what a harvest node is called
	blessing: {
		name: string,
		description: string,
		kind: BlessingKind,
		value: number,
	},
}

local Zones = {
	nodesPerZone = 7,
	nodeRespawnSeconds = 40,
	nodeYield = { 1, 2 }, -- min, max Essence per harvest
	blessingCost = 8,
	eggCost = 15,
	-- Essence for releasing a creature, by rarity order (Common = 1 … Secret = 9),
	-- times the stage multiplier. Legendary and up also pay Luck Wheel spins.
	releaseEssence = { 1, 2, 3, 5, 8, 12, 18, 25, 40 },
	releaseStageMultiplier = { Baby = 1, Juvenile = 2, Adult = 3 } :: { [string]: number },
	releaseSpins = { 0, 0, 0, 0, 1, 1, 2, 3, 5 },

	byBiome = {
		Mossvale = {
			essence = "Moss Essence",
			node = "Glowcap",
			blessing = {
				name = "Harvest Gift",
				description = "Cash worth 3 minutes of your income",
				kind = "cash",
				value = 180,
			},
		},
		CoralCoast = {
			essence = "Pearl Essence",
			node = "Pearl Clam",
			blessing = {
				name = "Tide Luck",
				description = "+3 Luck Wheel spins",
				kind = "spins",
				value = 3,
			},
		},
		MagmaRift = {
			essence = "Ember Essence",
			node = "Ember Shard",
			blessing = {
				name = "Forge Heat",
				description = "Every egg in your incubators hatches twice as fast (time left halves)",
				kind = "hatchSpeed",
				value = 0.5,
			},
		},
		FrostShelf = {
			essence = "Frost Essence",
			node = "Frost Geode",
			blessing = {
				name = "Frozen Fortune",
				description = "×5 luck on the next egg you get",
				kind = "luck",
				value = 5,
			},
		},
		StormPeaks = {
			essence = "Storm Essence",
			node = "Storm Crystal",
			blessing = {
				name = "Lightning Study",
				description = "XP worth 400 × your Hatcher Level",
				kind = "xp",
				value = 400,
			},
		},
		Moonfall = {
			essence = "Moon Essence",
			node = "Moonstone",
			blessing = {
				name = "Moon Jackpot",
				description = "×25 luck on the next egg you get",
				kind = "luck",
				value = 25,
			},
		},
	} :: { [string]: ZoneInfo },
}

-- What releasing a creature pays: Essence of its biome and Luck Wheel spins.
-- Junk creatures (no zone) pay spins only, at least one.
function Zones.releaseReward(rarityOrder: number, stage: string, biome: string): (number, number)
	local order = math.clamp(rarityOrder, 1, #Zones.releaseEssence)
	local spins = Zones.releaseSpins[order]
	if Zones.byBiome[biome] == nil then
		return 0, math.max(1, spins)
	end
	return Zones.releaseEssence[order] * (Zones.releaseStageMultiplier[stage] or 1), spins
end

return Zones

--!strict
-- Player progression (docs/GDD.md §7.2): Hatcher Level from XP, achievements,
-- what unlocks each biome's eggs, base themes, and incubator slots/tiers.
-- Pure data + math, safe on client and server.
local Biomes = require(script.Parent.Biomes)

-- XP per action. Hatching scales with the egg's biome order so later biomes level faster.
local xp = {
	hatchPerBiomeOrder = 12, -- × biome order (Junk counts as 3)
	newSpecies = 60,
	growJuvenile = 10,
	growAdult = 40,
	steal = 45,
	baseUpgradePerLevel = 150, -- × the new base level
	incubatorBought = 60,
	incubatorUpgraded = 40,
}

-- XP needed to go from `level` to `level + 1`.
local function xpToNext(level: number): number
	return 40 + 30 * level + 16 * level * level
end

-- Level + leftover XP from a lifetime XP total.
local function levelFromXp(total: number): (number, number, number)
	local level, remaining = 1, total
	while remaining >= xpToNext(level) do
		remaining -= xpToNext(level)
		level += 1
	end
	return level, remaining, xpToNext(level)
end

-- What each biome's eggs need. Biomes not listed (Junk) need nothing.
export type BiomeRequirement = { level: number, baseLevel: number }
local biomeRequirements: { [string]: BiomeRequirement } = {
	Mossvale = { level = 1, baseLevel = 1 },
	CoralCoast = { level = 4, baseLevel = 1 },
	MagmaRift = { level = 12, baseLevel = 2 },
	FrostShelf = { level = 20, baseLevel = 3 },
	StormPeaks = { level = 30, baseLevel = 4 },
	Moonfall = { level = 40, baseLevel = 5 },
}

local function biomeUnlocked(biomeId: string, level: number, baseLevel: number): boolean
	local need = biomeRequirements[biomeId]
	return need == nil or (level >= need.level and baseLevel >= need.baseLevel)
end

-- Achievements: `stat` is a key of PlayerData.stats; reaching `goal` pays out once.
export type Achievement = {
	id: string,
	name: string,
	description: string,
	stat: string,
	goal: number,
	xp: number,
	spins: number,
}
local achievements: { Achievement } = {
	{
		id = "Hatch1",
		name = "It's Alive!",
		description = "Hatch your first egg",
		stat = "hatched",
		goal = 1,
		xp = 50,
		spins = 1,
	},
	{
		id = "Hatch25",
		name = "Egg Enthusiast",
		description = "Hatch 25 eggs",
		stat = "hatched",
		goal = 25,
		xp = 250,
		spins = 1,
	},
	{
		id = "Hatch100",
		name = "Hatchery Boss",
		description = "Hatch 100 eggs",
		stat = "hatched",
		goal = 100,
		xp = 800,
		spins = 2,
	},
	{
		id = "Hatch500",
		name = "Egg Tycoon",
		description = "Hatch 500 eggs",
		stat = "hatched",
		goal = 500,
		xp = 3000,
		spins = 5,
	},
	{
		id = "Adult1",
		name = "Proud Parent",
		description = "Raise a creature to Adult",
		stat = "adults",
		goal = 1,
		xp = 150,
		spins = 1,
	},
	{
		id = "Adult10",
		name = "Big Family",
		description = "Raise 10 creatures to Adult",
		stat = "adults",
		goal = 10,
		xp = 600,
		spins = 2,
	},
	{
		id = "Steal1",
		name = "Sticky Fingers",
		description = "Steal a creature",
		stat = "steals",
		goal = 1,
		xp = 100,
		spins = 1,
	},
	{
		id = "Steal10",
		name = "Master Thief",
		description = "Steal 10 creatures",
		stat = "steals",
		goal = 10,
		xp = 700,
		spins = 2,
	},
	{
		id = "Index10",
		name = "Collector",
		description = "Discover 10 species",
		stat = "discovered",
		goal = 10,
		xp = 400,
		spins = 2,
	},
	{
		id = "Index25",
		name = "Naturalist",
		description = "Discover 25 species",
		stat = "discovered",
		goal = 25,
		xp = 1500,
		spins = 4,
	},
	{
		id = "Shiny1",
		name = "Shiny!",
		description = "Hatch a creature with a rare finish",
		stat = "finishes",
		goal = 1,
		xp = 200,
		spins = 1,
	},
	{
		id = "Upgrade1",
		name = "Home Improvement",
		description = "Upgrade your base",
		stat = "baseUpgrades",
		goal = 1,
		xp = 150,
		spins = 1,
	},
	{
		id = "Upgrade4",
		name = "Fortress",
		description = "Reach base level 5",
		stat = "baseUpgrades",
		goal = 4,
		xp = 2500,
		spins = 5,
	},
	{
		id = "Incubator3",
		name = "Egg Farm",
		description = "Own 3 incubators",
		stat = "incubators",
		goal = 3,
		xp = 300,
		spins = 1,
	},
	{
		id = "Walk600",
		name = "Walkies",
		description = "Walk a creature for 10 minutes",
		stat = "walkSeconds",
		goal = 600,
		xp = 200,
		spins = 1,
	},
	{
		id = "Spin10",
		name = "Feeling Lucky",
		description = "Spin the Luck Wheel 10 times",
		stat = "spinsUsed",
		goal = 10,
		xp = 300,
		spins = 2,
	},
	{
		id = "Earn1M",
		name = "Millionaire",
		description = "Collect $1M in total",
		stat = "earned",
		goal = 1_000_000,
		xp = 1000,
		spins = 3,
	},
	{
		id = "Earn1B",
		name = "Billionaire",
		description = "Collect $1B in total",
		stat = "earned",
		goal = 1_000_000_000,
		xp = 5000,
		spins = 10,
	},
}

-- Base themes: a biome look for your plot, buyable once that biome's eggs are
-- unlocked; and looks unlocked by building up (floors and vaults, owner 2026-10-01).
export type BaseTheme = {
	id: string, -- a biome id, or the look's own id
	name: string?, -- display name (biome themes use the biome's)
	requires: { floors: number?, vaults: number? }?, -- unlocked by floors/vaults, not a biome
	cost: number,
	floorMaterial: Enum.Material,
	floorColor: Color3,
	trimColor: Color3,
	laserColor: Color3,
	decor: { string }, -- WorldProps names scattered around the plot edge
	-- The fortress's stone walls and towers from the Keep up (wooden tiers stay wood);
	-- without one they're gray cobblestone. Roofs take trimColor, flags laserColor,
	-- unless the Castle Designer (Config.CastleDesigns) sets them below.
	wall: { material: Enum.Material, color: Color3 }?,
	roofColor: Color3?,
	roofMaterial: Enum.Material?,
	bannerColor: Color3?,
	bannerMaterial: Enum.Material?,
	-- Parts the client cycles through the colors (RainbowController)
	rainbow: { roof: boolean, banner: boolean, glow: boolean }?,
	-- Build the towers and gatehouse from parts in these colors, not the imported
	-- models (whose textures carry the Classic look)
	customTowers: boolean?,
	sparkle: Color3?, -- the Castle Designer's rebirth stones twinkle on the towers
}
local themes: { BaseTheme } = {
	{
		id = "Mossvale",
		cost = 0,
		floorMaterial = Enum.Material.WoodPlanks,
		floorColor = Color3.fromRGB(150, 120, 85),
		trimColor = Color3.fromRGB(90, 120, 60),
		laserColor = Color3.fromRGB(255, 40, 40),
		decor = { "BerryBush", "MushroomCluster", "FlowerPatch", "FallenLog" },
	},
	{
		id = "CoralCoast",
		cost = 100_000,
		floorMaterial = Enum.Material.Sand,
		floorColor = Color3.fromRGB(235, 215, 170),
		trimColor = Color3.fromRGB(240, 150, 150),
		laserColor = Color3.fromRGB(60, 220, 255),
		decor = { "CoralCluster", "RockCluster" },
		wall = { material = Enum.Material.Sandstone, color = Color3.fromRGB(232, 206, 168) },
	},
	{
		id = "MagmaRift",
		cost = 25_000_000,
		floorMaterial = Enum.Material.Basalt,
		floorColor = Color3.fromRGB(55, 48, 48),
		trimColor = Color3.fromRGB(255, 110, 30),
		laserColor = Color3.fromRGB(255, 120, 20),
		decor = { "LavaRock", "RockCluster" },
		wall = { material = Enum.Material.Basalt, color = Color3.fromRGB(70, 60, 58) },
	},
	{
		id = "FrostShelf",
		cost = 5_000_000_000,
		floorMaterial = Enum.Material.Glacier,
		floorColor = Color3.fromRGB(190, 225, 245),
		trimColor = Color3.fromRGB(255, 255, 255),
		laserColor = Color3.fromRGB(150, 220, 255),
		decor = { "IceSpire", "PineTree" },
		wall = { material = Enum.Material.Glacier, color = Color3.fromRGB(205, 232, 250) },
	},
	{
		id = "StormPeaks",
		cost = 500_000_000_000,
		floorMaterial = Enum.Material.Slate,
		floorColor = Color3.fromRGB(95, 100, 120),
		trimColor = Color3.fromRGB(255, 240, 90),
		laserColor = Color3.fromRGB(255, 240, 90),
		decor = { "RockCluster", "PineTree" },
		wall = { material = Enum.Material.Slate, color = Color3.fromRGB(92, 97, 118) },
	},
	{
		id = "Moonfall",
		cost = 50_000_000_000_000,
		floorMaterial = Enum.Material.Pebble,
		floorColor = Color3.fromRGB(120, 110, 150),
		trimColor = Color3.fromRGB(190, 120, 255),
		laserColor = Color3.fromRGB(190, 90, 255),
		decor = { "CrystalCluster", "RockCluster" },
		wall = { material = Enum.Material.Limestone, color = Color3.fromRGB(152, 138, 188) },
	},
	{
		id = "Fortress",
		name = "Stone Fortress",
		requires = { floors = 2 },
		cost = 2_000_000_000,
		floorMaterial = Enum.Material.Cobblestone,
		floorColor = Color3.fromRGB(125, 120, 112),
		trimColor = Color3.fromRGB(205, 165, 80),
		laserColor = Color3.fromRGB(255, 150, 40),
		decor = { "RockCluster", "FallenLog" },
		wall = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(132, 127, 120) },
	},
	{
		id = "SkyPalace",
		name = "Sky Palace",
		requires = { floors = 3 },
		cost = 150_000_000_000,
		floorMaterial = Enum.Material.Marble,
		floorColor = Color3.fromRGB(236, 236, 242),
		trimColor = Color3.fromRGB(120, 200, 255),
		laserColor = Color3.fromRGB(120, 220, 255),
		decor = { "CrystalCluster", "FlowerPatch" },
		wall = { material = Enum.Material.Marble, color = Color3.fromRGB(240, 240, 246) },
	},
	{
		id = "RoyalVault",
		name = "Royal Vault",
		requires = { vaults = 4 },
		cost = 1_000_000_000_000,
		floorMaterial = Enum.Material.Granite,
		floorColor = Color3.fromRGB(38, 34, 44),
		trimColor = Color3.fromRGB(255, 200, 60),
		laserColor = Color3.fromRGB(255, 210, 80),
		decor = { "CrystalCluster", "RockCluster" },
		wall = { material = Enum.Material.Granite, color = Color3.fromRGB(48, 42, 58) },
	},
}
local themesById: { [string]: BaseTheme } = {}
for _, theme in themes do
	themesById[theme.id] = theme
end

-- Incubators: you start with one; the rest are bought. Each can be upgraded:
-- higher tiers hatch faster and accept eggs from later biomes.
local incubatorSlotCosts = { 0, 5000, 2_000_000, 250_000_000, 30_000_000_000, 600_000_000_000 }

export type IncubatorTier = {
	name: string,
	speed: number, -- hatch time is divided by this
	maxBiomeOrder: number, -- highest Biomes[].order it accepts (Junk eggs fit anywhere)
	upgradeCost: number, -- cost to reach this tier from the one below
	color: Color3,
}
local incubatorTiers: { IncubatorTier } = {
	{ name = "Basic", speed = 1, maxBiomeOrder = 2, upgradeCost = 0, color = Color3.fromRGB(190, 140, 90) },
	{
		name = "Heated",
		speed = 1.5,
		maxBiomeOrder = 3,
		upgradeCost = 100_000,
		color = Color3.fromRGB(255, 130, 60),
	},
	{
		name = "Thermal",
		speed = 2,
		maxBiomeOrder = 4,
		upgradeCost = 25_000_000,
		color = Color3.fromRGB(80, 200, 255),
	},
	{
		name = "Arcane",
		speed = 3,
		maxBiomeOrder = 5,
		upgradeCost = 5_000_000_000,
		color = Color3.fromRGB(180, 90, 255),
	},
	{
		name = "Cosmic",
		speed = 4,
		maxBiomeOrder = 6,
		upgradeCost = 500_000_000_000,
		color = Color3.fromRGB(255, 230, 120),
	},
}

-- Lowest incubator tier that accepts eggs of `biomeOrder` (0 = Junk).
local function tierForBiome(biomeOrder: number): number
	if biomeOrder <= 0 then
		return 1
	end
	for index, tier in incubatorTiers do
		if tier.maxBiomeOrder >= biomeOrder then
			return index
		end
	end
	return #incubatorTiers
end

-- A theme's display name.
local function themeName(theme: BaseTheme): string
	if theme.name then
		return theme.name
	end
	local biome = Biomes[theme.id :: any]
	return if biome then biome.displayName else theme.id
end

-- Whether a built-up look (`requires`) is unlocked by a base's floors and vaults.
local function themeBuilt(theme: BaseTheme, floors: number, vaults: number): boolean
	local need = theme.requires
	return need ~= nil and floors >= (need.floors or 0) and vaults >= (need.vaults or 0)
end

return table.freeze({
	themeName = themeName,
	themeBuilt = themeBuilt,
	xp = xp,
	xpToNext = xpToNext,
	levelFromXp = levelFromXp,
	biomeRequirements = biomeRequirements,
	biomeUnlocked = biomeUnlocked,
	achievements = achievements,
	themes = themes,
	themesById = themesById,
	incubatorSlotCosts = incubatorSlotCosts,
	incubatorTiers = incubatorTiers,
	tierForBiome = tierForBiome,
})

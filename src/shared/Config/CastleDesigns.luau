--!strict
-- The Castle Designer (owner, 2026-10-01: "the castle needs to be designable, and
-- designs are bought once zones are unlocked: ice, fire, light, dark, red, blue,
-- green, rainbow, tons of combos"). A base's look is six picks that mix and match:
--
--   stone   the fortress walls, towers and keep
--   roof    tower roofs and the watchtowers' tops
--   banner  flags on the towers and the wall banners
--   glow    the laser gate, vault doors, spire crystals and royal crystals
--   floor   the ground floor and the keep's slabs
--   grounds the plants and rocks around the walls
--
-- Each option unlocks with a biome zone (its colors and materials), the base's
-- progress or a rebirth, is bought once at the Command Terminal and can be
-- picked freely after that. Presets set every slot at once (buying what's
-- missing). This replaced the nine fixed base themes; old saves keep what they
-- owned (DataService migration, `fromTheme`).
local Progression = require(script.Parent.Progression)
export type Unlock = {
	biome: string?, -- unlocked with this biome's eggs (Config.Biomes order)
	baseLevel: number?,
	floors: number?, -- counting the ground (2 = the Second Floor)
	vaults: number?,
	rebirths: number?,
}

export type Option = {
	id: string,
	name: string,
	cost: number,
	unlock: Unlock?,
	color: Color3?, -- swatch and look; nil for the stone's tier default
	material: Enum.Material?,
	rainbow: boolean?, -- the client cycles it through the colors
	decor: { string }?, -- grounds: WorldProps scattered round the walls
}

export type Slot = {
	id: string,
	name: string,
	options: { Option },
	default: string,
}

export type Preset = {
	id: string,
	name: string,
	picks: { [string]: string },
}

-- Costs follow the biomes' price steps (Coral 100K, Magma 25M, Frost 5B, Storm
-- 500B, Moonfall 50T) so every zone opens a few looks worth saving for.
local MOSS, CORAL, MAGMA, FROST, STORM, MOON =
	"Mossvale", "CoralCoast", "MagmaRift", "FrostShelf", "StormPeaks", "Moonfall"

local function colors(): { Option }
	-- The shared color set for roofs and banners
	return {
		{ id = "Blue", name = "Royal Blue", cost = 0, color = Color3.fromRGB(60, 85, 170) },
		{ id = "Red", name = "Crimson", cost = 0, color = Color3.fromRGB(180, 40, 45) },
		{ id = "Green", name = "Forest Green", cost = 0, color = Color3.fromRGB(55, 125, 65) },
		{
			id = "Yellow",
			name = "Sunflower",
			cost = 40_000,
			unlock = { biome = MOSS },
			color = Color3.fromRGB(240, 200, 60),
		},
		{
			id = "Teal",
			name = "Lagoon Teal",
			cost = 150_000,
			unlock = { biome = CORAL },
			color = Color3.fromRGB(40, 170, 175),
		},
		{
			id = "Pink",
			name = "Coral Pink",
			cost = 250_000,
			unlock = { biome = CORAL },
			color = Color3.fromRGB(240, 130, 150),
		},
		{
			id = "Orange",
			name = "Ember Orange",
			cost = 30_000_000,
			unlock = { biome = MAGMA },
			color = Color3.fromRGB(240, 110, 30),
		},
		{
			id = "Black",
			name = "Charcoal",
			cost = 60_000_000,
			unlock = { biome = MAGMA },
			color = Color3.fromRGB(35, 32, 38),
		},
		{
			id = "White",
			name = "Snow White",
			cost = 6_000_000_000,
			unlock = { biome = FROST },
			color = Color3.fromRGB(240, 244, 250),
		},
		{
			id = "IceBlue",
			name = "Ice Blue",
			cost = 8_000_000_000,
			unlock = { biome = FROST },
			color = Color3.fromRGB(150, 210, 245),
		},
		{
			id = "Storm",
			name = "Thunder Yellow",
			cost = 600_000_000_000,
			unlock = { biome = STORM },
			color = Color3.fromRGB(250, 225, 70),
		},
		{
			id = "Purple",
			name = "Void Purple",
			cost = 60_000_000_000_000,
			unlock = { biome = MOON },
			color = Color3.fromRGB(110, 60, 190),
		},
		{
			id = "Gold",
			name = "Gold",
			cost = 400_000_000_000,
			unlock = { baseLevel = 5 },
			color = Color3.fromRGB(240, 195, 70),
			material = Enum.Material.Foil,
		},
		{
			id = "Rainbow",
			name = "Rainbow",
			cost = 100_000_000_000_000,
			unlock = { rebirths = 1 },
			color = Color3.fromRGB(255, 120, 200),
			rainbow = true,
		},
	}
end

local slots: { Slot } = {
	{
		id = "stone",
		name = "Stone",
		default = "Tier",
		options = {
			{ id = "Tier", name = "Classic", cost = 0 }, -- gray stone, pale and gold at the Citadel
			{
				id = "Mossy",
				name = "Mossy Stone",
				cost = 25_000,
				unlock = { biome = MOSS },
				material = Enum.Material.Cobblestone,
				color = Color3.fromRGB(118, 130, 104),
			},
			{
				id = "Sandstone",
				name = "Sandstone",
				cost = 120_000,
				unlock = { biome = CORAL },
				material = Enum.Material.Sandstone,
				color = Color3.fromRGB(232, 206, 168),
			},
			{
				id = "Basalt",
				name = "Basalt",
				cost = 30_000_000,
				unlock = { biome = MAGMA },
				material = Enum.Material.Basalt,
				color = Color3.fromRGB(70, 60, 58),
			},
			{
				id = "Obsidian",
				name = "Obsidian",
				cost = 120_000_000,
				unlock = { biome = MAGMA },
				material = Enum.Material.Slate,
				color = Color3.fromRGB(32, 27, 40),
			},
			{
				id = "Ice",
				name = "Ice",
				cost = 6_000_000_000,
				unlock = { biome = FROST },
				material = Enum.Material.Glacier,
				color = Color3.fromRGB(205, 232, 250),
			},
			{
				id = "StormSlate",
				name = "Storm Slate",
				cost = 600_000_000_000,
				unlock = { biome = STORM },
				material = Enum.Material.Slate,
				color = Color3.fromRGB(92, 97, 118),
			},
			{
				id = "Moonstone",
				name = "Moonstone",
				cost = 60_000_000_000_000,
				unlock = { biome = MOON },
				material = Enum.Material.Limestone,
				color = Color3.fromRGB(152, 138, 188),
			},
			{
				id = "Cobble",
				name = "Fortress Stone",
				cost = 2_000_000_000,
				unlock = { floors = 2 },
				material = Enum.Material.Cobblestone,
				color = Color3.fromRGB(132, 127, 120),
			},
			{
				id = "Marble",
				name = "Marble",
				cost = 150_000_000_000,
				unlock = { floors = 3 },
				material = Enum.Material.Marble,
				color = Color3.fromRGB(240, 240, 246),
			},
			{
				id = "Granite",
				name = "Royal Granite",
				cost = 1_000_000_000_000,
				unlock = { vaults = 4 },
				material = Enum.Material.Granite,
				color = Color3.fromRGB(150, 116, 120),
			},
			{
				id = "Golden",
				name = "Solid Gold",
				cost = 150_000_000_000_000,
				unlock = { rebirths = 1 },
				material = Enum.Material.Foil,
				color = Color3.fromRGB(235, 190, 70),
			},
		},
	},
	{ id = "roof", name = "Roofs", default = "Blue", options = colors() },
	{ id = "banner", name = "Banners", default = "Blue", options = colors() },
	{
		id = "glow",
		name = "Glow",
		default = "Laser",
		options = {
			{ id = "Laser", name = "Laser Red", cost = 0, color = Color3.fromRGB(255, 40, 40) },
			{
				id = "Toxic",
				name = "Toxic Green",
				cost = 50_000,
				unlock = { biome = MOSS },
				color = Color3.fromRGB(110, 255, 90),
			},
			{
				id = "Ocean",
				name = "Ocean",
				cost = 150_000,
				unlock = { biome = CORAL },
				color = Color3.fromRGB(60, 220, 255),
			},
			{
				id = "Fire",
				name = "Fire",
				cost = 30_000_000,
				unlock = { biome = MAGMA },
				color = Color3.fromRGB(255, 120, 20),
			},
			{
				id = "Ice",
				name = "Ice",
				cost = 6_000_000_000,
				unlock = { biome = FROST },
				color = Color3.fromRGB(150, 225, 255),
			},
			{
				id = "Light",
				name = "Light",
				cost = 8_000_000_000,
				unlock = { baseLevel = 4 },
				color = Color3.fromRGB(255, 240, 190),
			},
			{
				id = "Storm",
				name = "Lightning",
				cost = 600_000_000_000,
				unlock = { biome = STORM },
				color = Color3.fromRGB(255, 240, 90),
			},
			{
				id = "Dark",
				name = "Dark",
				cost = 60_000_000_000_000,
				unlock = { biome = MOON },
				color = Color3.fromRGB(140, 60, 255),
			},
			{
				id = "Gold",
				name = "Royal Gold",
				cost = 1_000_000_000_000,
				unlock = { vaults = 4 },
				color = Color3.fromRGB(255, 210, 80),
			},
			{
				id = "Rainbow",
				name = "Rainbow",
				cost = 100_000_000_000_000,
				unlock = { rebirths = 1 },
				color = Color3.fromRGB(255, 120, 200),
				rainbow = true,
			},
		},
	},
	{
		id = "floor",
		name = "Floor",
		default = "Wood",
		options = {
			{
				id = "Wood",
				name = "Wood Planks",
				cost = 0,
				material = Enum.Material.WoodPlanks,
				color = Color3.fromRGB(150, 120, 85),
			},
			{
				id = "Sand",
				name = "Sand",
				cost = 100_000,
				unlock = { biome = CORAL },
				material = Enum.Material.Sand,
				color = Color3.fromRGB(235, 215, 170),
			},
			{
				id = "Basalt",
				name = "Basalt",
				cost = 25_000_000,
				unlock = { biome = MAGMA },
				material = Enum.Material.Basalt,
				color = Color3.fromRGB(55, 48, 48),
			},
			{
				id = "Glacier",
				name = "Glacier",
				cost = 5_000_000_000,
				unlock = { biome = FROST },
				material = Enum.Material.Glacier,
				color = Color3.fromRGB(190, 225, 245),
			},
			{
				id = "Slate",
				name = "Slate",
				cost = 500_000_000_000,
				unlock = { biome = STORM },
				material = Enum.Material.Slate,
				color = Color3.fromRGB(95, 100, 120),
			},
			{
				id = "Pebble",
				name = "Moon Pebble",
				cost = 50_000_000_000_000,
				unlock = { biome = MOON },
				material = Enum.Material.Pebble,
				color = Color3.fromRGB(120, 110, 150),
			},
			{
				id = "Cobble",
				name = "Cobblestone",
				cost = 1_000_000_000,
				unlock = { floors = 2 },
				material = Enum.Material.Cobblestone,
				color = Color3.fromRGB(125, 120, 112),
			},
			{
				id = "Marble",
				name = "Marble",
				cost = 100_000_000_000,
				unlock = { floors = 3 },
				material = Enum.Material.Marble,
				color = Color3.fromRGB(236, 236, 242),
			},
			{
				id = "Granite",
				name = "Dark Granite",
				cost = 800_000_000_000,
				unlock = { vaults = 4 },
				material = Enum.Material.Granite,
				color = Color3.fromRGB(38, 34, 44),
			},
		},
	},
	{
		id = "grounds",
		name = "Grounds",
		default = "Forest",
		options = {
			{
				id = "Forest",
				name = "Forest",
				cost = 0,
				color = Color3.fromRGB(80, 140, 60),
				decor = { "BerryBush", "MushroomCluster", "FlowerPatch", "FallenLog" },
			},
			{
				id = "Meadow",
				name = "Meadow",
				cost = 60_000,
				unlock = { biome = MOSS },
				color = Color3.fromRGB(150, 200, 90),
				decor = { "FlowerPatch", "FlowerMeadow", "BerryBush" },
			},
			{
				id = "Coral",
				name = "Coral Shore",
				cost = 100_000,
				unlock = { biome = CORAL },
				color = Color3.fromRGB(240, 150, 150),
				decor = { "CoralCluster", "RockCluster", "PalmTree" },
			},
			{
				id = "Volcanic",
				name = "Volcanic",
				cost = 25_000_000,
				unlock = { biome = MAGMA },
				color = Color3.fromRGB(200, 80, 30),
				decor = { "LavaRock", "RockCluster" },
			},
			{
				id = "Frozen",
				name = "Frozen",
				cost = 5_000_000_000,
				unlock = { biome = FROST },
				color = Color3.fromRGB(200, 230, 250),
				decor = { "IceSpire", "PineTree" },
			},
			{
				id = "Stormy",
				name = "Stormy Crags",
				cost = 500_000_000_000,
				unlock = { biome = STORM },
				color = Color3.fromRGB(110, 115, 140),
				decor = { "RockCluster", "PineTree" },
			},
			{
				id = "Lunar",
				name = "Lunar",
				cost = 50_000_000_000_000,
				unlock = { biome = MOON },
				color = Color3.fromRGB(170, 120, 240),
				decor = { "CrystalCluster", "RockCluster" },
			},
			{
				id = "Rocky",
				name = "Rocky",
				cost = 1_000_000_000,
				unlock = { floors = 2 },
				color = Color3.fromRGB(140, 135, 125),
				decor = { "RockCluster", "FallenLog", "Boulders" },
			},
			{
				id = "Crystal",
				name = "Crystal Garden",
				cost = 150_000_000_000,
				unlock = { floors = 3 },
				color = Color3.fromRGB(130, 210, 255),
				decor = { "CrystalCluster", "FlowerPatch" },
			},
		},
	},
}

-- One-click looks (the owner's examples first). A preset buys whatever it needs
-- that you don't own yet, as long as all of it is unlocked.
local presets: { Preset } = {
	{
		id = "Classic",
		name = "Classic Castle",
		picks = {
			stone = "Tier",
			roof = "Blue",
			banner = "Blue",
			glow = "Laser",
			floor = "Wood",
			grounds = "Forest",
		},
	},
	{
		id = "Red",
		name = "Red Bastion",
		picks = {
			stone = "Tier",
			roof = "Red",
			banner = "Red",
			glow = "Laser",
			floor = "Wood",
			grounds = "Forest",
		},
	},
	{
		id = "Green",
		name = "Green Hold",
		picks = {
			stone = "Mossy",
			roof = "Green",
			banner = "Green",
			glow = "Toxic",
			floor = "Wood",
			grounds = "Meadow",
		},
	},
	{
		id = "Coral",
		name = "Coral Fort",
		picks = {
			stone = "Sandstone",
			roof = "Teal",
			banner = "Pink",
			glow = "Ocean",
			floor = "Sand",
			grounds = "Coral",
		},
	},
	{
		id = "Fire",
		name = "Fire Keep",
		picks = {
			stone = "Basalt",
			roof = "Orange",
			banner = "Red",
			glow = "Fire",
			floor = "Basalt",
			grounds = "Volcanic",
		},
	},
	{
		id = "Ice",
		name = "Ice Castle",
		picks = {
			stone = "Ice",
			roof = "IceBlue",
			banner = "White",
			glow = "Ice",
			floor = "Glacier",
			grounds = "Frozen",
		},
	},
	{
		id = "Light",
		name = "Light Citadel",
		picks = {
			stone = "Marble",
			roof = "Gold",
			banner = "White",
			glow = "Light",
			floor = "Marble",
			grounds = "Crystal",
		},
	},
	{
		id = "Storm",
		name = "Storm Spire",
		picks = {
			stone = "StormSlate",
			roof = "Black",
			banner = "Storm",
			glow = "Storm",
			floor = "Slate",
			grounds = "Stormy",
		},
	},
	{
		id = "Dark",
		name = "Dark Fortress",
		picks = {
			stone = "Obsidian",
			roof = "Purple",
			banner = "Purple",
			glow = "Dark",
			floor = "Granite",
			grounds = "Lunar",
		},
	},
	{
		id = "Moon",
		name = "Moon Palace",
		picks = {
			stone = "Moonstone",
			roof = "White",
			banner = "Purple",
			glow = "Dark",
			floor = "Pebble",
			grounds = "Lunar",
		},
	},
	{
		id = "Royal",
		name = "Royal Vault",
		picks = {
			stone = "Granite",
			roof = "Gold",
			banner = "Red",
			glow = "Gold",
			floor = "Granite",
			grounds = "Rocky",
		},
	},
	{
		id = "Rainbow",
		name = "Rainbow Castle",
		picks = {
			stone = "Marble",
			roof = "Rainbow",
			banner = "Rainbow",
			glow = "Rainbow",
			floor = "Marble",
			grounds = "Crystal",
		},
	},
}

local slotsById: { [string]: Slot } = {}
local optionsBySlot: { [string]: { [string]: Option } } = {}
for _, slot in slots do
	slotsById[slot.id] = slot
	local byId: { [string]: Option } = {}
	for _, option in slot.options do
		byId[option.id] = option
	end
	optionsBySlot[slot.id] = byId
end
local presetsById: { [string]: Preset } = {}
for _, preset in presets do
	presetsById[preset.id] = preset
end

local CastleDesigns = {
	slots = slots,
	slotsById = slotsById,
	options = optionsBySlot,
	presets = presets,
	presetsById = presetsById,
}

-- Every slot at its default.
function CastleDesigns.defaults(): { [string]: string }
	local picks: { [string]: string } = {}
	for _, slot in slots do
		picks[slot.id] = slot.default
	end
	return picks
end

export type Progress = {
	unlockedBiome: number, -- highest Config.Biomes order unlocked
	baseLevel: number,
	floors: number,
	vaults: number,
	rebirths: number,
}

-- Whether an option can be bought yet, and if not, what it needs.
function CastleDesigns.unlocked(
	option: Option,
	progress: Progress,
	biomeOrder: (string) -> number
): (boolean, string?)
	local need = option.unlock
	if need == nil then
		return true, nil
	end
	if need.biome and biomeOrder(need.biome) > progress.unlockedBiome then
		return false, `unlock {need.biome}`
	end
	if need.baseLevel and progress.baseLevel < need.baseLevel then
		return false, `base Lv {need.baseLevel}`
	end
	if need.floors and progress.floors < need.floors then
		return false, if need.floors >= 3 then "the Top Floor" else "the Second Floor"
	end
	if need.vaults and progress.vaults < need.vaults then
		return false, `{need.vaults} vaults`
	end
	if need.rebirths and progress.rebirths < need.rebirths then
		return false, "a rebirth"
	end
	return true, nil
end

-- What each old base theme becomes (saves from before the designer own these
-- options, and the active theme's picks become their design).
CastleDesigns.fromTheme = {
	CoralCoast = { stone = "Sandstone", floor = "Sand", glow = "Ocean", grounds = "Coral" },
	MagmaRift = { stone = "Basalt", floor = "Basalt", glow = "Fire", grounds = "Volcanic" },
	FrostShelf = { stone = "Ice", floor = "Glacier", glow = "Ice", grounds = "Frozen" },
	StormPeaks = { stone = "StormSlate", floor = "Slate", glow = "Storm", grounds = "Stormy" },
	Moonfall = { stone = "Moonstone", floor = "Pebble", glow = "Dark", grounds = "Lunar" },
	Fortress = { stone = "Cobble", floor = "Cobble", grounds = "Rocky" },
	SkyPalace = { stone = "Marble", floor = "Marble", glow = "Ice", grounds = "Crystal" },
	RoyalVault = { stone = "Granite", floor = "Granite", glow = "Gold", grounds = "Rocky" },
} :: { [string]: { [string]: string } }

local function option(picks: { [string]: string }, slot: string): Option
	local byId = optionsBySlot[slot]
	return byId[picks[slot] or ""] or byId[slotsById[slot].default]
end

-- The look a design gives the base, as the theme record the world code reads
-- (WorldService.applyTheme, Fortress, BaseDecor). Its id changes with the picks.
function CastleDesigns.resolve(picks: { [string]: string }): Progression.BaseTheme
	local stone, roof, banner = option(picks, "stone"), option(picks, "roof"), option(picks, "banner")
	local glow, floor, grounds = option(picks, "glow"), option(picks, "floor"), option(picks, "grounds")
	local ids: { string } = {}
	for _, slot in slots do
		table.insert(ids, option(picks, slot.id).id)
	end
	return {
		id = "design:" .. table.concat(ids, "/"),
		name = "Custom",
		cost = 0,
		floorMaterial = floor.material or Enum.Material.WoodPlanks,
		floorColor = floor.color or Color3.fromRGB(150, 120, 85),
		trimColor = roof.color or Color3.fromRGB(60, 85, 170),
		laserColor = glow.color or Color3.fromRGB(255, 40, 40),
		decor = grounds.decor or {},
		wall = if stone.material and stone.color
			then { material = stone.material, color = stone.color }
			else nil,
		roofColor = roof.color,
		roofMaterial = roof.material,
		bannerColor = banner.color,
		bannerMaterial = banner.material,
		rainbow = {
			roof = roof.rainbow == true,
			banner = banner.rainbow == true,
			glow = glow.rainbow == true,
		},
		customTowers = not (stone.id == "Tier" and roof.id == "Blue" and banner.id == "Blue"),
	}
end

-- Free options are owned from the start.
function CastleDesigns.owns(owned: { [string]: boolean }, slot: string, id: string): boolean
	local option = optionsBySlot[slot] and optionsBySlot[slot][id]
	return option ~= nil and (option.cost == 0 or owned[`{slot}:{id}`] == true)
end

return CastleDesigns

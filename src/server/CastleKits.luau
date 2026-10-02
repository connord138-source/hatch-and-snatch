--!strict
-- Castle theme kits (owner, 2026-10-02: themes "need physical assets that add a
-- feeling of I earned this", and the castles must look "exactly like" the
-- approved theme concepts, assets/tripo/concepts/Theme*.png). The Castle
-- Designer's Theme slot picks one; Fortress.build calls in here to dress the
-- castle: a cap that replaces every tower roof, growths along the battlements,
-- clusters at the tower bases, themed braziers and lanterns, a gate ornament,
-- floating pieces, big backdrop and overhead pieces, the theme's own flame and
-- light color, and part-built effects (lava falls, icicles, lightning arcs, a
-- storm cloud, the void portal, runes, a red carpet, pearl strings, ivy). Every
-- piece is an imported WorldProps model with a part-built stand-in, so a castle
-- still reads as its theme before the models are imported. Clients animate the
-- tagged pieces (CastleFxController): KitFloat bobs and turns, KitArc flickers
-- lightning, KitSpin turns the portal, KitFlicker flashes the storm light, and
-- KitLight lights far from the camera are switched off.
local CollectionService = game:GetService("CollectionService")

local Props = require(script.Parent.Props)

export type Ambient = {
	texture: string,
	colors: { Color3 },
	rate: number,
	size: number,
	speed: number,
	rise: number, -- upward drift (negative falls)
	lifetime: number,
	brightness: number,
}
export type Kit = {
	id: string,
	flame: Color3, -- braziers and torches
	flame2: Color3,
	light: Color3,
	cap: string?, -- replaces every tower roof (from the Keep up)
	capScale: number, -- cap height as a multiple of the tower's radius
	capColor: Color3, -- the stand-in stepped cone
	finial: string?, -- topper on the roof's tip (keeps the roof)
	growth: string?, -- along the battlements, outer edge
	growthSize: number,
	growthEvery: number,
	-- Colors the growths are tinted in, picked at random (SurfaceAppearance.Color
	-- multiplies a pale texture: one pale coral model becomes pink, orange, purple...)
	growthTints: { Color3 }?,
	growthAlts: { string }?, -- other growth shapes mixed in (when imported)
	bigGrowths: { string }?, -- the shapes used for the big pieces (default: all)
	growthGlow: boolean?, -- every few growths (and the gate statues) give off the theme's light
	plaque: string?, -- on the walls' outer faces
	base: string?, -- at each tower's foot
	baseSize: number,
	baseWrap: boolean?, -- wraps round the tower (roots) instead of beside it
	brazier: string?, -- the gate braziers
	lantern: string?, -- along the front and sides of the walls
	lanternSize: number,
	statue: string?, -- either side of the gate
	gate: string?, -- ornament at the gate: an arch round it or a crest over it
	gateMode: "arch" | "crest",
	floater: string?, -- floats round the tower tops
	floaterSize: number,
	backdrop: string?, -- big pieces behind the back corners
	overhead: string?, -- above the keep
	overheadSize: number,
	moat: { material: Enum.Material, color: Color3, transparency: number }?,
	-- The ground round the castle (sand, scorched rock, snow, moss, ...) and the
	-- basins hugging the front towers' feet (tide pools, a lava lake, ice, a swamp)
	ground: { material: Enum.Material, color: Color3 }?,
	pool: { material: Enum.Material, color: Color3, glow: boolean, size: number, crust: boolean? }?,
	-- A band of another stone round the walls' and towers' feet (`height` as a
	-- share of the wall): Coral's blue-gray base, Fire's glowing cracked lava, ...
	plinth: { material: Enum.Material, color: Color3, height: number }?,
	ambient: Ambient?,
	-- The shape on every banner (bolt, crown, stars, rune, leaf, flake, star, flame,
	-- diamond), in emblemColor (default: the theme's light), neon unless emblemFoil
	emblem: string?,
	emblemColor: Color3?,
	emblemFoil: boolean?,
	-- Lanterns or braziers standing on the battlements every few merlons, as in
	-- every concept; wallLightFlame burns (a brazier) rather than glows (a lantern)
	wallLight: string?,
	wallLightFlame: boolean?,
	frontBrazier: string?, -- in front of the gate (default: brazier)
	frontBrazierSize: number?,
	topBraziers: number?, -- on the gatehouse towers (default 2)
	frontCap: string?, -- the front towers' cap instead of `cap` (Ice: huge crystal clusters)
	frontCapScale: number?,
	floaterCount: number?, -- per tower (default 2)
	-- A cluster round the front towers' feet (Moss: giant glowing mushrooms)
	feet: { name: string, size: number, count: number, glow: boolean? }?,
	-- Rings round the towers (`at` as shares of the tower's height)
	bands: { color: Color3, material: Enum.Material, at: { number }, width: number }?,
	-- Pieces jutting out of the cone roofs (Void: black crystals)
	roofDress: { name: string, count: number, scale: number }?,
	carpetLength: number?,
	crystalCap: boolean?, -- the caps are crystals: a glowing core and glints inside
	-- The crystals split light into rainbow glints (Diamond: clear stones, so it
	-- never reads as the Ice Castle's blue ice; owner, 2026-10-02)
	prism: boolean?,
	-- How the growths sit on the walls (owner, 2026-10-02: the coral looked "lazily
	-- sat upon the castle"): "clusters" grow in leaning groups at irregular spots,
	-- sunk into the stone, with pieces out of the face too; "corners" the same,
	-- only near the towers and the gate; "merlons" one on every other merlon
	-- (Fire's spikes); "row" evenly along the wall (Storm's lightning rods)
	growthMode: string?,
	clusterSize: number?, -- pieces per cluster (default 3)
	growthLean: number?, -- how far they lean out, degrees (default 25)
	crownCount: number?, -- growths in the bouquet round each tower's cap (default 6)
	gateTint: Color3?, -- the gate crest's color (the pale pieces take it)
	-- Small pieces set into the walls' and towers' faces (Coral's starfish and
	-- shells), one per `every` square studs, about `size` across, tinted
	decor: { names: { string }, tints: { Color3 }, every: number, size: number }?,
	-- Little gardens along the outside of the walls' feet (Coral's corals and
	-- anemones), one every `every` studs, pieces about `size` tall (default: the growth's)
	garden: { names: { string }, every: number, size: number? }?,
	-- A band along the walls' tops, under the battlements (Coral's sea glass)
	wallTrim: { material: Enum.Material, color: Color3 }?,
	-- Inside the keep (owner, 2026-10-02: "still need interior detail"): small
	-- pieces at the foot of each creature's niche (`glow` ones give off light),
	-- a big centerpiece at the back of each floor, what hangs from the ceilings,
	-- and what crowns the niches' arches (default: the growth)
	interior: { names: { string }, size: number }?,
	centerpiece: { name: string, size: number, glow: boolean?, flame: boolean? }?,
	chandelier: string?,
	nicheCrown: string?,
	effects: { [string]: boolean },
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local KITS: { [string]: Kit } = {
	Moss = {
		id = "Moss",
		emblem = "leaf",
		emblemColor = Color3.fromRGB(170, 255, 140),
		wallLight = "MossMushroomLantern",
		feet = { name = "MossMushrooms", size = 11, count = 3, glow = true },
		topBraziers = 0, -- the concept's gatehouse wears giant mushrooms instead
		flame = Color3.fromRGB(140, 255, 120),
		flame2 = Color3.fromRGB(40, 160, 70),
		light = Color3.fromRGB(120, 255, 120),
		capScale = 0,
		capColor = Color3.fromRGB(55, 120, 60),
		growth = "MossMushrooms",
		growthSize = 4.6,
		growthEvery = 13,
		growthMode = "clusters",
		clusterSize = 2,
		growthLean = 12,
		growthGlow = true,
		statue = "MossMushrooms", -- giant glowing mushrooms flank the gate
		frontBrazierSize = 4.5,
		base = "MossRoots",
		baseSize = 12,
		baseWrap = true,
		lantern = "MossMushroomLantern",
		lanternSize = 6,
		brazier = "MossMushroomLantern",
		gateMode = "crest",
		backdrop = "MossGiantTree",
		overheadSize = 0,
		floaterSize = 0,
		moat = { material = Enum.Material.Glass, color = Color3.fromRGB(70, 140, 90), transparency = 0.2 },
		ambient = {
			texture = SPARKLE,
			colors = { Color3.fromRGB(200, 255, 120), Color3.fromRGB(120, 255, 160) },
			rate = 14,
			size = 0.35,
			speed = 0.6,
			rise = 0.2,
			lifetime = 6,
			brightness = 2,
		},
		ground = { material = Enum.Material.LeafyGrass, color = Color3.fromRGB(70, 125, 60) },
		plinth = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(88, 110, 74), height = 0.3 },
		pool = {
			material = Enum.Material.Glass,
			color = Color3.fromRGB(60, 150, 110),
			glow = false,
			size = 7,
		},
		growthAlts = { "MossGlowCap" },
		garden = { names = { "MossFern", "MossFlowers", "MossGlowCap", "MossFern" }, every = 11 },
		interior = { names = { "MossFern", "MossFlowers", "MossGlowCap", "MossShelfLog" }, size = 2.4 },
		centerpiece = { name = "MossGlowCap", size = 7, glow = true },
		chandelier = "MossMushroomLantern",
		effects = { vines = true, lilies = true, flowers = true, cypress = true, moss = true },
	},
	Coral = {
		id = "Coral",
		emblem = "star",
		emblemColor = Color3.fromRGB(255, 150, 70),
		wallLight = "CoralPearlLantern",
		flame = Color3.fromRGB(90, 255, 230),
		flame2 = Color3.fromRGB(20, 170, 190),
		light = Color3.fromRGB(80, 255, 225),
		cap = "CoralShellSpire",
		capScale = 3.2,
		capColor = Color3.fromRGB(120, 200, 180),
		growth = "CoralBranches",
		growthAlts = {
			"CoralStaghorn",
			"CoralStaghorn",
			"CoralFan",
			"CoralTubes",
			"CoralBrain",
			"CoralAnemone",
		},
		bigGrowths = { "CoralStaghorn", "CoralStaghorn", "CoralBranches" },
		growthSize = 5.5,
		growthEvery = 9,
		growthMode = "clusters",
		clusterSize = 4,
		growthLean = 32,
		crownCount = 11,
		gateTint = Color3.fromRGB(255, 160, 195),
		decor = {
			names = { "CoralStarfish", "CoralStarfish", "CoralScallop", "CoralConch" },
			tints = {
				Color3.fromRGB(255, 130, 40),
				Color3.fromRGB(255, 90, 150),
				Color3.fromRGB(170, 110, 255),
				Color3.fromRGB(255, 200, 70),
				Color3.fromRGB(255, 80, 80),
				Color3.fromRGB(70, 210, 200),
			},
			every = 15,
			size = 2.5,
		},
		garden = {
			names = {
				"CoralBranches",
				"CoralStaghorn",
				"CoralFan",
				"CoralTubes",
				"CoralBrain",
				"CoralAnemone",
				"CoralUrchins",
				"CoralGiantClam",
				"CoralOyster",
				"CoralBarnacleRock",
			},
			every = 8,
		},
		-- Clams with pearls, brain coral, anemones and urchins inside the keep
		interior = {
			names = { "CoralGiantClam", "CoralOyster", "CoralBrain", "CoralAnemone", "CoralUrchins" },
			size = 2.2,
		},
		centerpiece = { name = "CoralGiantClam", size = 6, glow = true },
		chandelier = "CoralPearlLantern",
		wallTrim = { material = Enum.Material.Glass, color = Color3.fromRGB(60, 196, 186) },
		bands = {
			color = Color3.fromRGB(70, 200, 190),
			material = Enum.Material.Glass,
			at = { 0.62, 0.93 },
			width = 0.9,
		},
		growthTints = {
			Color3.fromRGB(255, 95, 150),
			Color3.fromRGB(255, 140, 60),
			Color3.fromRGB(180, 110, 255),
			Color3.fromRGB(70, 225, 205),
			Color3.fromRGB(255, 210, 80),
			Color3.fromRGB(255, 90, 90),
		},
		plaque = "CoralStarfishPlaque",
		base = "CoralAnemoneRock",
		baseSize = 4,
		brazier = "CoralClamBrazier",
		frontBrazier = "CoralPearlLantern", -- the concept's teal lanterns flank the gate
		lantern = "CoralPearlLantern",
		lanternSize = 5,
		gate = "CoralScallop", -- a pink scallop over the gate
		gateMode = "crest",
		overheadSize = 0,
		floaterSize = 0,
		moat = { material = Enum.Material.Glass, color = Color3.fromRGB(40, 200, 200), transparency = 0.15 },
		ambient = {
			texture = SPARKLE,
			colors = { Color3.fromRGB(180, 255, 250), Color3.fromRGB(90, 230, 255) },
			rate = 10,
			size = 0.3,
			speed = 0.4,
			rise = 1,
			lifetime = 5,
			brightness = 1.6,
		},
		ground = { material = Enum.Material.Sand, color = Color3.fromRGB(226, 205, 160) },
		-- The concept's sea-blue mosaic band along the walls' feet
		plinth = { material = Enum.Material.Pebble, color = Color3.fromRGB(62, 128, 150), height = 0.38 },
		pool = { material = Enum.Material.Glass, color = Color3.fromRGB(40, 210, 205), glow = true, size = 7 },
		effects = { pearls = true, keepPearls = true, gateGarden = true },
	},
	Fire = {
		id = "Fire",
		emblem = "flame",
		emblemColor = Color3.fromRGB(255, 200, 90),
		wallLight = "FireSkullBrazier",
		wallLightFlame = true,
		-- The concept's gate is flanked by dragon heads with fire bowls; the
		-- gatehouse top carries spikes, not braziers
		frontBrazier = "FireDragonGate",
		frontBrazierSize = 8,
		topBraziers = 0,
		flame = Color3.fromRGB(255, 150, 50),
		flame2 = Color3.fromRGB(255, 60, 20),
		light = Color3.fromRGB(255, 130, 50),
		cap = "FireSpire",
		capScale = 2.8,
		capColor = Color3.fromRGB(40, 36, 40),
		growth = "FireObsidianSpikes",
		growthAlts = { "FireMagmaCrystals" },
		growthMode = "merlons",
		growthSize = 3.6,
		growthEvery = 6,
		base = "FireLavaRock",
		baseSize = 4.5,
		brazier = "FireSkullBrazier",
		gateMode = "crest",
		overheadSize = 0,
		floaterSize = 0,
		lanternSize = 0,
		moat = { material = Enum.Material.Neon, color = Color3.fromRGB(255, 100, 20), transparency = 0 },
		ambient = {
			texture = FIRE,
			colors = { Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20) },
			rate = 18,
			size = 0.3,
			speed = 0.8,
			rise = 2.5,
			lifetime = 4,
			brightness = 2,
		},
		ground = { material = Enum.Material.Basalt, color = Color3.fromRGB(45, 38, 38) },
		plinth = { material = Enum.Material.CrackedLava, color = Color3.fromRGB(70, 44, 38), height = 0.35 },
		pool = {
			material = Enum.Material.Neon,
			color = Color3.fromRGB(230, 70, 12),
			glow = true,
			size = 9,
			crust = true, -- dark rock floating on the lava, as in the concept
		},
		garden = { names = { "FireMagmaCrystals", "FireLavaRock", "FireDragonSkull" }, every = 12 },
		interior = {
			names = { "FireMagmaCrystals", "FireDragonSkull", "FireCauldron", "FireLavaRock" },
			size = 2.4,
		},
		centerpiece = { name = "FireCauldron", size = 4.5, flame = true },
		chandelier = "FireCauldron", -- iron cauldrons of lava hanging on chains
		nicheCrown = "FireObsidianSpikes",
		effects = { lavaFalls = true, veins = true, smoke = true },
	},
	Ice = {
		id = "Ice",
		emblem = "flake",
		emblemColor = Color3.fromRGB(235, 248, 255),
		wallLight = "IceLantern",
		frontCap = "IceCrystalCluster", -- the concept's front towers wear huge crystal clusters
		frontCapScale = 4.2,
		crystalCap = true,
		flame = Color3.fromRGB(170, 230, 255),
		flame2 = Color3.fromRGB(80, 160, 255),
		light = Color3.fromRGB(150, 215, 255),
		cap = "IceCrystalSpire",
		capScale = 3.6,
		capColor = Color3.fromRGB(190, 230, 255),
		growth = "IceCrystalCluster",
		growthAlts = { "IceShards" },
		growthMode = "corners",
		growthSize = 3.8,
		growthEvery = 7,
		growthGlow = true,
		base = "IceCrystalCluster", -- the concept's huge clusters round the towers' feet
		baseSize = 15,
		brazier = "IceLantern",
		lantern = "IceLantern",
		lanternSize = 6,
		gate = "IceGateArch",
		gateMode = "arch",
		backdrop = "SnowDrift",
		overheadSize = 0,
		floaterSize = 0,
		moat = { material = Enum.Material.Ice, color = Color3.fromRGB(200, 235, 255), transparency = 0.1 },
		ambient = {
			texture = SPARKLE,
			colors = { Color3.new(1, 1, 1), Color3.fromRGB(210, 235, 255) },
			rate = 24,
			size = 0.25,
			speed = 0.3,
			rise = -1.2,
			lifetime = 9,
			brightness = 1.4,
		},
		-- A frozen lake round the walls with floes on it, as in the concept
		ground = { material = Enum.Material.Glass, color = Color3.fromRGB(40, 92, 140) },
		pool = { material = Enum.Material.Ice, color = Color3.fromRGB(170, 215, 245), glow = false, size = 8 },
		garden = { names = { "IceSnowPine", "IceShards", "IceShards" }, every = 12 },
		interior = { names = { "IceShards", "IceBrazier", "IceSnowPine" }, size = 2.4 },
		centerpiece = { name = "IceBrazier", size = 4.5, flame = true },
		chandelier = "IceLantern",
		effects = { icicles = true, snow = true, floes = true },
	},
	Storm = {
		id = "Storm",
		emblem = "bolt",
		emblemColor = Color3.fromRGB(255, 225, 80),
		wallLight = "StormPlasmaBrazier",
		wallLightFlame = true,
		floaterCount = 1, -- one big chained thunder-stone per tower
		bands = {
			color = Color3.fromRGB(196, 116, 62),
			material = Enum.Material.Metal,
			at = { 0.8, 0.9 },
			width = 0.8,
		},
		flame = Color3.fromRGB(150, 220, 255),
		flame2 = Color3.fromRGB(255, 240, 120),
		light = Color3.fromRGB(170, 210, 255),
		cap = "StormTeslaSpire",
		capScale = 3.4,
		capColor = Color3.fromRGB(170, 110, 60),
		growth = "StormLightningRod",
		growthMode = "row",
		growthSize = 4,
		growthEvery = 18,
		brazier = "StormPlasmaBrazier",
		gateMode = "crest",
		floater = "StormThunderStone",
		floaterSize = 8,
		overhead = "StormCloud",
		overheadSize = 16,
		baseSize = 0,
		lanternSize = 0,
		ambient = {
			texture = SPARKLE,
			colors = { Color3.fromRGB(255, 245, 140), Color3.fromRGB(150, 220, 255) },
			rate = 8,
			size = 0.25,
			speed = 3,
			rise = 0,
			lifetime = 1.2,
			brightness = 3,
		},
		ground = { material = Enum.Material.Slate, color = Color3.fromRGB(70, 74, 88) },
		garden = { names = { "StormThunderRock", "StormCrystals" }, every = 13 },
		interior = { names = { "StormCrystals", "StormCoil", "StormThunderRock" }, size = 2.4 },
		centerpiece = { name = "StormCoil", size = 6, glow = true },
		chandelier = "StormThunderStone", -- glowing thunder-stones hung on chains
		nicheCrown = "StormCrystals",
		effects = { arcs = true, stormCloud = true, chains = true, gateBolts = true },
	},
	Moon = {
		id = "Moon",
		emblem = "stars",
		emblemColor = Color3.fromRGB(240, 236, 255),
		wallLight = "MoonLantern",
		topBraziers = 4,
		floaterCount = 6, -- a ring of crystals round every roof
		flame = Color3.fromRGB(200, 140, 255),
		flame2 = Color3.fromRGB(120, 70, 255),
		light = Color3.fromRGB(185, 120, 255),
		capScale = 0,
		capColor = Color3.fromRGB(215, 205, 235),
		finial = "MoonFinial",
		lantern = "MoonLantern",
		lanternSize = 5.5,
		brazier = "MoonLantern",
		gate = "MoonGateArch",
		gateMode = "arch",
		floater = "MoonCrystal",
		floaterSize = 3,
		overhead = "MoonBigCrescent",
		overheadSize = 18,
		growthSize = 0,
		growthEvery = 0,
		baseSize = 0,
		ambient = {
			texture = SPARKLE,
			colors = { Color3.fromRGB(230, 210, 255), Color3.fromRGB(160, 120, 255) },
			rate = 16,
			size = 0.3,
			speed = 0.3,
			rise = 0.3,
			lifetime = 6,
			brightness = 2,
		},
		ground = { material = Enum.Material.Pebble, color = Color3.fromRGB(120, 110, 150) },
		garden = { names = { "MoonFlower", "MoonShard", "MoonFlower" }, every = 11, size = 4 },
		interior = { names = { "MoonFlower", "MoonShard", "MoonLampPost" }, size = 2.6 },
		centerpiece = { name = "MoonShard", size = 6.5, glow = true },
		chandelier = "MoonLantern",
		nicheCrown = "MoonShard",
		effects = { mist = true, roofGems = true, keepCrystals = true },
	},
	Golden = {
		id = "Golden",
		emblem = "crown",
		emblemColor = Color3.fromRGB(245, 200, 80),
		emblemFoil = true,
		wallLight = "GoldBrazier",
		wallLightFlame = true,
		carpetLength = 30,
		bands = {
			color = Color3.fromRGB(244, 240, 232),
			material = Enum.Material.Marble,
			at = { 0.1, 0.9 },
			width = 1.4,
		},
		flame = Color3.fromRGB(255, 210, 100),
		flame2 = Color3.fromRGB(255, 140, 40),
		light = Color3.fromRGB(255, 205, 110),
		cap = "GoldSpire",
		capScale = 3,
		capColor = Color3.fromRGB(240, 195, 70),
		brazier = "GoldBrazier",
		statue = "GoldLion",
		gate = "GoldCrownCrest",
		gateMode = "crest",
		growthSize = 0,
		growthEvery = 0,
		baseSize = 0,
		lanternSize = 0,
		overheadSize = 0,
		floaterSize = 0,
		ambient = {
			texture = SPARKLE,
			colors = { Color3.fromRGB(255, 230, 140), Color3.new(1, 1, 1) },
			rate = 14,
			size = 0.3,
			speed = 0.4,
			rise = 0.4,
			lifetime = 3,
			brightness = 2.4,
		},
		ground = { material = Enum.Material.Marble, color = Color3.fromRGB(236, 232, 224) },
		plinth = { material = Enum.Material.Marble, color = Color3.fromRGB(242, 238, 230), height = 0.3 },
		garden = { names = { "GoldUrn" }, every = 14, size = 4.5 },
		interior = { names = { "GoldCoins", "GoldUrn", "GoldChest", "GoldCoins" }, size = 2.2 },
		centerpiece = { name = "GoldChest", size = 4 },
		chandelier = "DiamondChandelier",
		effects = { carpet = true },
	},
	Diamond = {
		id = "Diamond",
		emblem = "diamond",
		emblemColor = Color3.fromRGB(235, 248, 255),
		crystalCap = true,
		prism = true,
		wallLight = "DiamondLantern",
		bands = {
			color = Color3.fromRGB(240, 195, 70),
			material = Enum.Material.Foil,
			at = { 0.12, 0.5, 0.88 },
			width = 0.6,
		},
		flame = Color3.fromRGB(255, 252, 244),
		flame2 = Color3.fromRGB(255, 230, 180),
		light = Color3.fromRGB(255, 250, 240), -- white, a touch warm (ice is the blue one)
		cap = "DiamondCrown",
		capScale = 3.2,
		capColor = Color3.fromRGB(246, 248, 252),
		growth = "DiamondCluster",
		growthAlts = { "DiamondGems" },
		growthMode = "corners",
		growthSize = 3.4,
		growthEvery = 7,
		growthGlow = true,
		base = "DiamondCluster",
		baseSize = 5.5,
		lantern = "DiamondLantern",
		lanternSize = 5.5,
		gate = "DiamondGateCrest",
		gateMode = "crest",
		overheadSize = 0,
		floaterSize = 0,
		ambient = {
			texture = SPARKLE,
			colors = {
				Color3.fromRGB(255, 160, 200),
				Color3.fromRGB(160, 220, 255),
				Color3.fromRGB(200, 255, 190),
				Color3.fromRGB(255, 240, 170),
			},
			rate = 18,
			size = 0.32,
			speed = 0.5,
			rise = 0.3,
			lifetime = 2.4,
			brightness = 3,
		},
		ground = { material = Enum.Material.Marble, color = Color3.fromRGB(238, 240, 246) },
		garden = { names = { "DiamondGems", "DiamondCluster" }, every = 13 },
		interior = { names = { "DiamondGems", "DiamondGeode", "DiamondCluster" }, size = 2.2 },
		centerpiece = { name = "DiamondGeode", size = 5.5, glow = true },
		chandelier = "DiamondChandelier",
		effects = { inlays = true, studs = true },
	},
	Void = {
		id = "Void",
		emblem = "rune",
		wallLight = "VoidBrazier",
		wallLightFlame = true,
		floaterCount = 3,
		-- The concept keeps dark cone roofs with black crystals jutting out of them
		roofDress = { name = "VoidCrystals", count = 6, scale = 1.2 },
		flame = Color3.fromRGB(190, 110, 255),
		flame2 = Color3.fromRGB(90, 30, 200),
		light = Color3.fromRGB(165, 90, 255),
		capScale = 0,
		capColor = Color3.fromRGB(35, 25, 50),
		growth = "VoidCrystals",
		growthMode = "corners",
		clusterSize = 2,
		growthSize = 3.8,
		growthEvery = 7,
		growthGlow = true,
		base = "VoidRunePillar",
		baseSize = 7,
		brazier = "VoidBrazier",
		gateMode = "crest",
		floater = "VoidShards",
		floaterSize = 4,
		overheadSize = 18, -- the part-built vortex (portal effect) swirls like the concept
		lanternSize = 0,
		ambient = {
			texture = SMOKE,
			colors = { Color3.fromRGB(120, 60, 220), Color3.fromRGB(30, 10, 60) },
			rate = 6,
			size = 1.6,
			speed = 0.3,
			rise = 0.6,
			lifetime = 5,
			brightness = 1,
		},
		ground = { material = Enum.Material.Basalt, color = Color3.fromRGB(28, 22, 38) },
		garden = { names = { "VoidThornTree", "VoidObelisk", "VoidShards" }, every = 12 },
		interior = { names = { "VoidEyeOrb", "VoidObelisk", "VoidShards", "VoidThornTree" }, size = 2.4 },
		centerpiece = { name = "VoidEyeOrb", size = 5, glow = true },
		chandelier = "VoidEyeOrb",
		effects = { portal = true, runes = true, keepChains = true, rocks = true, gateGlyph = true },
	},
}

local CastleKits = {}

function CastleKits.get(id: string?): Kit?
	return if id then KITS[id] else nil
end

local function part(parent: Instance, props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	props.ClassName = nil
	local p = (Instance.new(className) :: any) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Every kit light is tagged KitLight: the client switches off the ones far from
-- the camera (CastleFxController), as six themed bases carry hundreds.
local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	CollectionService:AddTag(l, "KitLight")
	return l
end

-- A themed flame on `parent`: a Fire in the kit's colors and its light.
function CastleKits.flame(parent: BasePart, kit: Kit?, size: number, range: number)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = 7
	fire.Color = if kit then kit.flame else Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = if kit then kit.flame2 else Color3.fromRGB(255, 60, 20)
	fire.Parent = parent
	light(parent, if kit then kit.light else Color3.fromRGB(255, 160, 80), range, 1.4)
end

-- Pieces whose models came out of Tripo facing sideways, and the turn (degrees
-- about the vertical) that makes them face out along -Z once imported. Studio's
-- importer turns a GLB half round (glTF -Z ends up +Z: the waterfall cliff), so
-- these were measured on the GLBs with that in mind.
local TURN: { [string]: number } = {
	GoldLion = 90,
	FireDragonGate = 90,
	FireSkullBrazier = 90,
	CoralStarfishPlaque = -90,
}

-- Pieces that glow in the concepts (bright mushrooms, violet crystals): their
-- texture gives way to neon in this color, as a SurfaceAppearance can't glow.
local NEON: { [string]: Color3 } = {
	MossMushrooms = Color3.fromRGB(70, 235, 95),
	MoonCrystal = Color3.fromRGB(196, 120, 255),
	StormThunderStone = Color3.fromRGB(214, 228, 255),
	MossGlowCap = Color3.fromRGB(70, 235, 95),
	MoonShard = Color3.fromRGB(196, 120, 255),
	StormCrystals = Color3.fromRGB(255, 232, 140),
}

-- Pieces that are clear crystal: their texture gives way to colorless glass
-- with a bright reflection (the Diamond Citadel's diamonds; Tripo baked them pale blue)
local CLEAR: { [string]: Color3 } = {
	DiamondCrown = Color3.fromRGB(250, 252, 255),
	DiamondCluster = Color3.fromRGB(250, 252, 255),
	DiamondGems = Color3.fromRGB(250, 252, 255),
}

-- A diamond's light split into colors (Diamond's prism glints)
local RAINBOW = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(255, 200, 110),
	Color3.fromRGB(250, 245, 140),
	Color3.fromRGB(140, 245, 170),
	Color3.fromRGB(130, 210, 255),
	Color3.fromRGB(190, 150, 255),
}

-- Pieces that read better as a plain pearly surface than their dark texture at
-- night (the concept's shell spires are pearl white-teal).
local SOLID: { [string]: Color3 } = {
	CoralShellSpire = Color3.fromRGB(206, 236, 228),
}

-- An imported piece standing on `base` at `height`, or nil (no model imported).
local function piece(parent: Instance, name: string?, base: CFrame, height: number): Model?
	if name == nil or height <= 0 then
		return nil
	end
	local model = Props.spawn(name, base, height, parent)
	local turn = TURN[name]
	if model and turn then
		local box = model:GetBoundingBox()
		model:PivotTo(box * CFrame.Angles(0, math.rad(turn), 0) * box:ToObjectSpace(model:GetPivot()))
	end
	local solid = SOLID[name]
	if model and solid then
		model:SetAttribute("KitSolid", solid)
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Material = Enum.Material.SmoothPlastic
				d.Color = solid
				d.Reflectance = 0.12
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
		end
	end
	local clear = CLEAR[name]
	if model and clear then
		model:SetAttribute("KitClear", clear)
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Material = Enum.Material.Glass
				d.Color = clear
				d.Transparency = 0.18
				d.Reflectance = 0.3
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
		end
	end
	local neon = NEON[name]
	if model and neon then
		model:SetAttribute("KitNeon", neon)
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Material = Enum.Material.Neon
				d.Color = neon
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
		end
	end
	return model
end

-- The lit point of a model: its top middle, where a flame or light belongs.
local function topOf(model: Model): CFrame
	local box, size = model:GetBoundingBox()
	return box * CFrame.new(0, size.Y * 0.35, 0)
end

local function anchor(parent: Instance, at: CFrame, name: string): BasePart
	return part(parent, {
		Name = name,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = at,
		Transparency = 1,
	})
end

-- Tags a piece to float (bob and turn slowly) on the client.
local function float(instance: Instance, base: CFrame, bob: number, spin: number)
	instance:SetAttribute("FloatBase", base)
	instance:SetAttribute("FloatBob", bob)
	instance:SetAttribute("FloatSpin", spin)
	CollectionService:AddTag(instance, "KitFloat")
end

-- Tints a growth in one of the kit's colors (the pale texture takes the hue).
-- Pieces with colors of their own (a pink clam, purple urchins), which the
-- pale-piece tints would muddy
local NATURAL: { [string]: boolean } = {
	CoralGiantClam = true,
	CoralOyster = true,
	CoralUrchins = true,
	CoralBarnacleRock = true,
}

local function tint(model: Model?, kit: Kit, rng: Random)
	local tints = kit.growthTints
	if model == nil or tints == nil or #tints == 0 or NATURAL[model.Name] then
		return
	end
	local color = tints[rng:NextInteger(1, #tints)]
	model:SetAttribute("KitTint", color)
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			(d :: any).Color = color
		elseif d:IsA("MeshPart") and d.TextureID == "" then
			d.Color = color
		end
	end
end

-- Tints a pale piece one color (a gate crest, a shell).
local function tintWith(model: Model?, color: Color3)
	if model == nil then
		return
	end
	model:SetAttribute("KitTint", color)
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			(d :: any).Color = color
		elseif d:IsA("MeshPart") and d.TextureID == "" then
			d.Color = color
		end
	end
end

-- A growth from the kit (one of its shapes), tinted.
local function growth(folder: Instance, kit: Kit, at: CFrame, height: number, rng: Random): Model?
	local name = kit.growth
	-- Tall pieces come from the upright shapes only (a sea fan blown up to ten
	-- studs read as a giant disc); the rest fill in small
	local alts = if kit.bigGrowths and height > kit.growthSize * 1.05 then kit.bigGrowths else kit.growthAlts
	if alts and #alts > 0 then
		local pick = rng:NextInteger(0, #alts)
		if pick > 0 and Props.template("WorldProps", alts[pick]) then
			name = alts[pick]
		end
	end
	local model = piece(folder, name, at, height)
	tint(model, kit, rng)
	return model
end

-- Turns a flat piece (a crest, plaque, crescent or portal) so its broad side
-- faces out along its frame's -Z, whichever way the model was imported (a
-- crescent imported side-on showed only its edge).
local function faceOut(model: Model?)
	if model == nil then
		return
	end
	local box, size = model:GetBoundingBox()
	if size.X < size.Z * 0.8 then
		model:PivotTo(box * CFrame.Angles(0, math.pi / 2, 0) * box:ToObjectSpace(model:GetPivot()))
	end
end

-- Gives off the kit's light from a piece (glowing mushrooms and crystals).
local function glow(folder: Instance, model: Model?, kit: Kit, range: number)
	if model == nil then
		return
	end
	local box = model:GetBoundingBox()
	light(anchor(folder, box, "GrowthGlow"), kit.light, range, 1.1)
end

local function emitter(parent: BasePart, ambient: Ambient, shape: Enum.ParticleEmitterShape?)
	local e = Instance.new("ParticleEmitter")
	e.Name = "KitAmbient"
	e.Texture = ambient.texture
	local keys = {}
	for i, color in ambient.colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(#ambient.colors - 1, 1), color))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, ambient.colors[1]))
	end
	e.Color = ColorSequence.new(keys)
	e.Rate = ambient.rate
	e.Lifetime = NumberRange.new(ambient.lifetime * 0.6, ambient.lifetime)
	e.Speed = NumberRange.new(ambient.speed * 0.5, ambient.speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, ambient.rise, 0)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, ambient.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 1
	e.Brightness = ambient.brightness
	e.Shape = shape or Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = parent
end

--------------------------------------------------------------------------------
-- Tower caps
--------------------------------------------------------------------------------

-- Replaces a tower's roof: the kit's cap on `roofBase` (the top of the tower's
-- crown), sized to the tower (a front tower may wear `frontCap`). Returns the
-- tip, or nil when this kit keeps roofs.
function CastleKits.cap(
	folder: Instance,
	kit: Kit,
	roofBase: CFrame,
	radius: number,
	front: boolean?
): CFrame?
	if kit.capScale <= 0 then
		return nil
	end
	local frontCap = if front then kit.frontCap else nil
	local height = radius * (if frontCap then kit.frontCapScale or kit.capScale else kit.capScale)
	local model = piece(folder, frontCap or kit.cap, roofBase, height)
	if model then
		-- Lit from the front so the cap reads at night (shell spires, ice, gold)
		light(
			anchor(folder, roofBase * CFrame.new(0, height * 0.45, -radius - 3), "CapLight"),
			kit.light,
			radius * 3,
			1.2
		)
		if kit.crystalCap then
			-- A crystal crown glows from inside, with glints round it
			local core = part(folder, {
				Name = "CapCore",
				Size = Vector3.new(radius * 0.9, height * 0.55, radius * 0.9),
				CFrame = roofBase * CFrame.new(0, height * 0.3, 0) * CFrame.Angles(0, math.rad(45), 0),
				Material = Enum.Material.Neon,
				Color = kit.light,
			})
			light(core, kit.light, radius * 4, 2)
			if kit.prism then
				-- Light split into rainbow glints round the core, as in the concept
				for k, color in RAINBOW do
					local angle = k / #RAINBOW * math.pi * 2
					part(folder, {
						Name = "PrismGlint",
						Size = Vector3.new(0.35, height * 0.22, 0.35),
						CFrame = roofBase * CFrame.new(
							math.cos(angle) * radius * 0.62,
							height * (0.25 + 0.3 * ((k * 0.37) % 1)),
							math.sin(angle) * radius * 0.62
						) * CFrame.Angles(0, angle, math.rad(18)),
						Material = Enum.Material.Neon,
						Color = color,
					})
				end
			end
			if kit.ambient then
				emitter(core, {
					texture = SPARKLE,
					colors = kit.ambient.colors,
					rate = 6,
					size = 0.6,
					speed = 1.5,
					rise = 0,
					lifetime = 1.5,
					brightness = 4,
				})
			end
		end
	end
	if model == nil then
		-- Stand-in: a stepped cone in the cap's color
		local steps = 6
		for i = 0, steps - 1 do
			local d = (radius * 2 + 1.4) * (1 - i / steps) + 0.3
			local p = part(folder, {
				Name = "KitCap",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height / steps + 0.05, d, d),
				CFrame = roofBase
					* CFrame.new(0, i * height / steps + height / steps / 2, 0)
					* CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.SmoothPlastic,
				Color = kit.capColor,
			})
			p.Reflectance = 0.05
		end
	end
	return roofBase * CFrame.new(0, height, 0)
end

-- A topper on a roof's tip (the Moon kit's crescents).
function CastleKits.finial(folder: Instance, kit: Kit, tip: CFrame, radius: number)
	if kit.finial == nil then
		return
	end
	local model = piece(folder, kit.finial, tip * CFrame.new(0, -0.6, 0), radius * 2.3)
	if model == nil then
		local moon = part(folder, {
			Name = "KitFinial",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = tip * CFrame.new(0, 1.4, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(235, 230, 255),
		})
		light(moon, kit.light, 12, 1)
	else
		light(anchor(folder, topOf(model), "FinialLight"), kit.light, 12, 1)
	end
end

--------------------------------------------------------------------------------
-- Part-built effects
--------------------------------------------------------------------------------

-- A glowing lava fall down a wall face, pooling at its foot.
local function lavaFall(folder: Instance, top: CFrame, height: number, width: number)
	local fall = part(folder, {
		Name = "LavaFall",
		Size = Vector3.new(width, height, 0.35),
		CFrame = top * CFrame.new(0, -height / 2, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 110, 25),
	})
	part(folder, {
		Name = "LavaCrust",
		Size = Vector3.new(width * 0.6, height, 0.4),
		CFrame = top * CFrame.new(width * 0.15, -height / 2, -0.05),
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(255, 70, 15),
	})
	local drips = Instance.new("ParticleEmitter")
	drips.Name = "LavaFlow"
	drips.Texture = FIRE
	drips.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 70, 20))
	drips.EmissionDirection = Enum.NormalId.Bottom
	drips.Speed = NumberRange.new(5, 8)
	drips.Lifetime = NumberRange.new(height / 7, height / 5)
	drips.Rate = 14
	drips.Size = NumberSequence.new(width * 0.4, width * 0.2)
	drips.LightEmission = 1
	drips.Shape = Enum.ParticleEmitterShape.Box
	drips.Parent = fall
	part(folder, {
		Name = "LavaPool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, width * 2.4, width * 2.4),
		CFrame = top * CFrame.new(0, -height + 0.15, -width * 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 30),
	})
	light(fall, Color3.fromRGB(255, 120, 40), 18, 1.6)
end

-- A row of icicles hanging under a wall's top edge, from `a` to `b` (world).
local function icicles(folder: Instance, a: Vector3, b: Vector3, outward: Vector3, rng: Random)
	local length = (b - a).Magnitude
	local step = 1.9
	for i = 0, math.floor(length / step) do
		local at = a + (b - a).Unit * (i * step + rng:NextNumber(-0.3, 0.3))
		local long = rng:NextNumber(1.2, 3.2)
		part(folder, {
			ClassName = "WedgePart",
			Name = "Icicle",
			Size = Vector3.new(0.5, long, 0.7),
			CFrame = CFrame.lookAt(at, at + outward)
				* CFrame.new(0, -long / 2, 0)
				* CFrame.Angles(math.pi, 0, 0),
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(205, 238, 255),
			Transparency = 0.15,
		})
	end
end

-- Hanging ivy down a wall face.
local function vines(folder: Instance, a: Vector3, b: Vector3, outward: Vector3, height: number, rng: Random)
	local length = (b - a).Magnitude
	for i = 0, math.floor(length / 3.5) do
		local at = a + (b - a).Unit * (i * 3.5 + rng:NextNumber(0, 1.5))
		local long = height * rng:NextNumber(0.25, 0.7)
		part(folder, {
			Name = "Ivy",
			Size = Vector3.new(rng:NextNumber(0.9, 1.8), long, 0.25),
			CFrame = CFrame.lookAt(at, at + outward) * CFrame.new(0, -long / 2, -0.05),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(70, 140, 60):Lerp(Color3.fromRGB(110, 170, 70), rng:NextNumber()),
		})
	end
end

-- Glowing lava veins cracking up a wall face (the Fire concept's walls).
local function veins(folder: Instance, a: Vector3, b: Vector3, outward: Vector3, height: number, rng: Random)
	local length = (b - a).Magnitude
	local along = (b - a).Unit
	for i = 0, math.floor(length / 3.2) do
		local x = i * 3.2 + rng:NextNumber(0.3, 2.4)
		if x > length - 1 then
			break
		end
		local at = a + along * x + Vector3.new(0, -height + rng:NextNumber(0.5, height * 0.5), 0)
		for _ = 1, rng:NextInteger(3, 7) do
			local long = rng:NextNumber(1.6, 3.2)
			local tilt = rng:NextNumber(-0.7, 0.7)
			local step = (Vector3.new(0, 1, 0) * math.cos(tilt) + along * math.sin(tilt)) * long
			local mid = at + step / 2
			if mid.Y > a.Y - 1 then
				break
			end
			part(folder, {
				Name = "LavaVein",
				Size = Vector3.new(0.28, long + 0.15, 0.1),
				CFrame = CFrame.fromMatrix(mid, step.Unit:Cross(outward).Unit, step.Unit),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 110, 30),
			})
			at += step
		end
	end
end

-- Strings of glowing pearls sagging between the battlements.
local function pearls(folder: Instance, a: Vector3, b: Vector3, outward: Vector3)
	local length = (b - a).Magnitude
	local span = 4
	for i = 0, math.floor(length / span) - 1 do
		for k = 1, 4 do
			local t = k / 5
			local at = a
				+ (b - a).Unit * (i * span + t * span)
				+ outward * 0.3
				- Vector3.new(0, 0.9 * math.sin(t * math.pi) + 0.6, 0)
			part(folder, {
				Name = "Pearl",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.45, 0.45, 0.45),
				CFrame = CFrame.new(at),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(235, 255, 250),
			})
		end
	end
end

-- The void portal: a swirling vortex of violet light round a black core, that
-- turns (three spiral arms of glowing arcs, brighter toward the rim).
local function portal(folder: Instance, at: CFrame, size: number, kit: Kit)
	local ring = Instance.new("Model")
	ring.Name = "VoidPortalRing"
	local radius = size / 2
	local deep = Color3.fromRGB(70, 20, 150)
	for arm = 0, 2 do
		local steps = 26
		for i = 0, steps - 1 do
			local t = i / steps
			local r = radius * (0.18 + 0.82 * t)
			local angle = arm * math.pi * 2 / 3 + t * math.pi * 1.6
			local width = 0.5 + 1.3 * t
			part(ring, {
				Name = "PortalArm",
				Size = Vector3.new(r * 0.32 + 0.3, width, 0.3),
				CFrame = at * CFrame.Angles(0, 0, angle) * CFrame.new(0, r, 0.02 * i),
				Material = Enum.Material.Neon,
				Color = deep:Lerp(kit.light:Lerp(Color3.new(1, 1, 1), 0.08), t),
			})
		end
	end
	local segments = 28
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		part(ring, {
			Name = "PortalRing",
			Size = Vector3.new(radius * 2 * math.pi / segments + 0.2, 0.8, 0.6),
			CFrame = at * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0),
			Material = Enum.Material.Neon,
			Color = kit.light:Lerp(Color3.new(1, 1, 1), 0.12),
		})
	end
	local core = part(ring, {
		Name = "PortalCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 0.5, radius * 0.5),
		CFrame = at * CFrame.Angles(0, math.rad(90), 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(8, 4, 16),
	})
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = SPARKLE
	swirl.Color = ColorSequence.new(Color3.fromRGB(220, 160, 255), Color3.fromRGB(110, 40, 255))
	swirl.Rate = 30
	swirl.Lifetime = NumberRange.new(1.5, 2.5)
	swirl.Speed = NumberRange.new(0.5, 1.5)
	swirl.RotSpeed = NumberRange.new(-90, 90)
	swirl.Size = NumberSequence.new(0.7, 0)
	swirl.LightEmission = 1
	swirl.Shape = Enum.ParticleEmitterShape.Disc
	swirl.Parent = core
	light(core, kit.light, 45, 2.2)
	ring.PrimaryPart = core
	ring.Parent = folder
	ring:SetAttribute("SpinBase", at)
	ring:SetAttribute("SpinSpeed", 0.6)
	CollectionService:AddTag(ring, "KitSpin")
end

-- A dark storm cloud with flickering lightning inside.
local function stormCloud(folder: Instance, at: CFrame, size: number)
	local cloud = part(folder, {
		Name = "StormCloud",
		Size = Vector3.new(size * 1.6, size * 0.3, size),
		CFrame = at,
		Transparency = 1,
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 74, 92), Color3.fromRGB(40, 42, 56))
	smoke.Rate = 9
	smoke.Lifetime = NumberRange.new(6, 9)
	smoke.Speed = NumberRange.new(0.2, 0.6)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.35),
		NumberSequenceKeypoint.new(0.5, size * 0.55),
		NumberSequenceKeypoint.new(1, size * 0.4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.25),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Shape = Enum.ParticleEmitterShape.Box
	smoke.Parent = cloud
	local flash = light(cloud, Color3.fromRGB(190, 220, 255), 70, 0)
	CollectionService:AddTag(flash, "KitFlicker")
end

-- A low mist rolling round the castle's feet.
local function mist(folder: Instance, at: CFrame, size: Vector3, color: Color3)
	local zone = part(folder, {
		Name = "KitMist",
		Size = size,
		CFrame = at,
		Transparency = 1,
	})
	local fog = Instance.new("ParticleEmitter")
	fog.Texture = SMOKE
	fog.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.3))
	fog.Rate = 5
	fog.Lifetime = NumberRange.new(6, 10)
	fog.Speed = NumberRange.new(0.3, 0.8)
	fog.SpreadAngle = Vector2.new(180, 10)
	fog.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 9),
	})
	fog.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	fog.LightEmission = 0.4
	fog.Shape = Enum.ParticleEmitterShape.Box
	fog.Parent = zone
end

-- Lightning arcing between two tower tips (the client flickers it).
local function arc(folder: Instance, a: CFrame, b: CFrame)
	local holder = anchor(folder, a, "ArcStart")
	local endPart = anchor(folder, b, "ArcEnd")
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Parent = endPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 250, 200), Color3.fromRGB(160, 220, 255))
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.Segments = 12
	beam.Parent = holder
	CollectionService:AddTag(beam, "KitArc")
end

--------------------------------------------------------------------------------
-- Dressing the castle
--------------------------------------------------------------------------------

export type TowerSpot = { base: CFrame, radius: number, height: number, tip: CFrame }
export type Site = {
	origin: CFrame,
	halfW: number,
	front: number,
	back: number,
	gateHalf: number,
	height: number, -- wall height
	thickness: number,
	stone: boolean, -- stone walls (battlements to dress)
	level: number,
	gateTop: number?, -- the gatehouse towers' top (nil: no part-built gatehouse)
	gateDepth: number,
	banner: Color3, -- the design's banner color
	towers: { TowerSpot },
	runs: { { a: Vector3, b: Vector3 } }, -- plot-local wall runs on the ground
}

local GATE_CLEAR = 12

-- A cluster of growths on `base` (a surface, its -Z out): one big piece and
-- smaller ones round it, each sunk a little into the stone and leaning out, so
-- they grow out of the castle rather than sit on it.
local function cluster(
	folder: Instance,
	kit: Kit,
	base: CFrame,
	scale: number,
	rng: Random,
	count: number?
): { Model }
	local made: { Model } = {}
	local lean = math.rad(kit.growthLean or 25)
	for k = 1, count or kit.clusterSize or 3 do
		local main = k == 1
		local size = kit.growthSize
			* scale
			* (if main then rng:NextNumber(1.1, 1.45) else rng:NextNumber(0.5, 0.85))
		local offset = if main
			then Vector3.new(rng:NextNumber(-0.3, 0.3), 0, 0)
			else Vector3.new(rng:NextNumber(-2.4, 2.4), 0, rng:NextNumber(-0.7, 0.4))
		local at = base
			* CFrame.new(offset + Vector3.new(0, -size * 0.08, 0))
			* CFrame.Angles(-rng:NextNumber(lean * 0.3, lean), 0, rng:NextNumber(-lean * 0.5, lean * 0.5))
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local model = growth(folder, kit, at, size, rng)
		if model then
			table.insert(made, model)
		end
	end
	return made
end

-- One small piece set flat into a face (its -Z out), `s` across: a starfish or
-- shell lies with its back on the stone whichever way its model was made.
local function inset(folder: Instance, kit: Kit, name: string, face: CFrame, s: number, rng: Random)
	local template = Props.template("WorldProps", name)
	local decor = kit.decor
	if template == nil or decor == nil then
		return
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local ext = model:GetExtentsSize()
	local spin = CFrame.Angles(0, 0, rng:NextNumber(0, 6.28))
	if ext.Y <= math.min(ext.X, ext.Z) then
		-- Made lying down: its top turns to face out of the wall
		Props.place(
			model,
			face * CFrame.new(0, 0, -s * 0.2) * spin * CFrame.Angles(-math.pi / 2, 0, 0),
			Vector3.new(s, s * 0.4, s)
		)
	else
		-- Made standing: its thin side goes against the wall
		local turn = if ext.X < ext.Z then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity
		Props.place(
			model,
			face * CFrame.new(0, -s / 2, -s * 0.2) * CFrame.Angles(0, 0, rng:NextNumber(-0.4, 0.4)) * turn,
			Vector3.new(s, s, s * 0.4)
		)
	end
	tintWith(model, decor.tints[rng:NextInteger(1, #decor.tints)])
	model.Parent = folder
end

-- Starfish and shells scattered over an area of a face (its -Z out, centred).
local function scatter(folder: Instance, kit: Kit, face: CFrame, width: number, height: number, rng: Random)
	local decor = kit.decor
	if decor == nil then
		return
	end
	for _ = 1, math.floor(width * height / decor.every) do
		inset(
			folder,
			kit,
			decor.names[rng:NextInteger(1, #decor.names)],
			face
				* CFrame.new(
					rng:NextNumber(-width / 2, width / 2),
					rng:NextNumber(-height / 2, height / 2),
					0
				),
			decor.size * rng:NextNumber(0.7, 1.35),
			rng
		)
	end
end

-- A little garden on the ground at `at` (its -Z out): two or three small growths
-- from the garden's set and a starfish lying in the sand.
local function garden(folder: Instance, kit: Kit, at: CFrame, rng: Random)
	local set = kit.garden
	if set == nil then
		return
	end
	for _ = 1, rng:NextInteger(2, 3) do
		local name = set.names[rng:NextInteger(1, #set.names)]
		local model = piece(
			folder,
			name,
			at
				* CFrame.new(rng:NextNumber(-1.6, 1.6), -0.1, rng:NextNumber(-1, 1))
				* CFrame.Angles(-rng:NextNumber(0, 0.3), rng:NextNumber(0, 6.28), 0),
			(set.size or kit.growthSize) * rng:NextNumber(0.45, 0.8)
		)
		tint(model, kit, rng)
	end
	local decor = kit.decor
	if decor and rng:NextNumber() < 0.6 then
		local ground = at * CFrame.new(rng:NextNumber(-2, 2), 0.05, rng:NextNumber(-1.5, -0.5))
		inset(folder, kit, decor.names[1], ground * CFrame.Angles(math.pi / 2, 0, 0), decor.size * 1.2, rng)
	end
end

--------------------------------------------------------------------------------
-- Details: banners and emblems, glyphs, chains, inlays, towers and roofs
--------------------------------------------------------------------------------

local GOLD = Color3.fromRGB(240, 195, 70)
local IVY = Color3.fromRGB(64, 132, 56)
local SNOW = Color3.fromRGB(242, 247, 252)

-- A point on a tower's surface facing out: `angle` round from its outward face
-- (radians, toward its right), `y` up from its foot, `out` off the surface.
local function onTower(tower: TowerSpot, angle: number, y: number, out: number): CFrame
	local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	local at = dir * (tower.radius + out) + Vector3.new(0, y, 0)
	return tower.base * CFrame.lookAt(at, at + dir)
end

-- A bar on a face (its -Z out) from (x0, y0) to (x1, y1), in face units.
local function stroke(
	folder: Instance,
	face: CFrame,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	width: number,
	material: Enum.Material,
	color: Color3,
	name: string
)
	local dx, dy = x1 - x0, y1 - y0
	local long = math.sqrt(dx * dx + dy * dy)
	part(folder, {
		Name = name,
		Size = Vector3.new(width, long + width * 0.5, 0.06),
		CFrame = face
			* CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0)
			* CFrame.Angles(0, 0, math.atan2(-dx, dy)),
		Material = material,
		Color = color,
	})
end

-- A rune glyph (a stem and one or two strokes), `size` tall.
local function glyph(folder: Instance, face: CFrame, size: number, color: Color3, rng: Random)
	local at = face * CFrame.new(0, 0, -0.04)
	local w = size * 0.1
	local x = rng:NextNumber(-0.15, 0.15) * size
	stroke(folder, at, x, -size / 2, x, size / 2, w, Enum.Material.Neon, color, "Rune")
	for _ = 1, rng:NextInteger(1, 2) do
		local y0 = rng:NextNumber(-0.4, 0.3) * size
		local dir = if rng:NextNumber() < 0.5 then -1 else 1
		stroke(
			folder,
			at,
			x,
			y0,
			x + dir * rng:NextNumber(0.25, 0.4) * size,
			y0 + rng:NextNumber(-0.3, 0.3) * size,
			w,
			Enum.Material.Neon,
			color,
			"Rune"
		)
	end
end

-- The kit's emblem on a banner, `s` across.
local function emblem(folder: Instance, kit: Kit?, face: CFrame, s: number, rng: Random)
	local at = face * CFrame.new(0, 0, -0.1)
	local shape = if kit then kit.emblem else "diamond"
	local color = if kit then kit.emblemColor or kit.light else GOLD
	local material = if kit == nil or kit.emblemFoil then Enum.Material.Foil else Enum.Material.Neon
	local function bar(x0: number, y0: number, x1: number, y1: number, w: number)
		stroke(folder, at, x0 * s, y0 * s, x1 * s, y1 * s, w * s, material, color, "BannerEmblem")
	end
	local function dot(x: number, y: number, d: number)
		part(folder, {
			Name = "BannerEmblem",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d * s, d * s, d * s),
			CFrame = at * CFrame.new(x * s, y * s, 0),
			Material = material,
			Color = color,
		})
	end
	if shape == "bolt" then
		bar(0.2, 0.5, -0.15, 0.02, 0.16)
		bar(-0.15, 0.02, 0.15, 0.02, 0.14)
		bar(0.15, 0.02, -0.2, -0.5, 0.16)
	elseif shape == "crown" then
		bar(-0.36, -0.22, 0.36, -0.22, 0.18)
		bar(-0.34, -0.2, -0.4, 0.24, 0.11)
		bar(0, -0.2, 0, 0.32, 0.11)
		bar(0.34, -0.2, 0.4, 0.24, 0.11)
		dot(-0.4, 0.28, 0.14)
		dot(0, 0.37, 0.14)
		dot(0.4, 0.28, 0.14)
	elseif shape == "stars" then
		local points = {
			{ -0.3, 0.38 },
			{ -0.06, 0.16 },
			{ 0.26, 0.3 },
			{ 0.1, -0.12 },
			{ -0.24, -0.34 },
			{ 0.3, -0.42 },
		}
		for i, p in points do
			dot(p[1], p[2], if i % 2 == 0 then 0.13 else 0.09)
			local q = points[i + 1]
			if q then
				bar(p[1], p[2], q[1], q[2], 0.03)
			end
		end
	elseif shape == "rune" then
		glyph(folder, at, s * 0.9, color, rng)
	elseif shape == "leaf" then
		bar(0, -0.46, 0, 0.46, 0.07)
		for _, y in { -0.26, 0, 0.26 } do
			bar(0, y, -0.26, y + 0.2, 0.13)
			bar(0, y, 0.26, y + 0.2, 0.13)
		end
	elseif shape == "flake" then
		for k = 0, 2 do
			local a = k * math.pi / 3
			bar(-0.45 * math.sin(a), -0.45 * math.cos(a), 0.45 * math.sin(a), 0.45 * math.cos(a), 0.08)
		end
		dot(0, 0, 0.16)
	elseif shape == "star" then
		for k = 0, 4 do
			local a = k * math.pi * 2 / 5
			bar(0, 0, 0.42 * math.sin(a), 0.42 * math.cos(a), 0.17)
		end
		dot(0, 0, 0.22)
	elseif shape == "flame" then
		dot(0, -0.18, 0.42)
		bar(0, -0.1, 0.03, 0.42, 0.2)
		bar(-0.13, -0.08, -0.2, 0.22, 0.12)
		bar(0.13, -0.08, 0.21, 0.2, 0.12)
	else -- a diamond
		part(folder, {
			Name = "BannerEmblem",
			Size = Vector3.new(0.5 * s, 0.5 * s, 0.06),
			CFrame = at * CFrame.Angles(0, 0, math.rad(45)),
			Material = material,
			Color = color,
		})
	end
end

-- A hanging banner on a face (its -Z out), centred there: the cloth with a
-- pointed foot, a gold rod and the kit's emblem (a gold diamond without a kit).
function CastleKits.banner(
	folder: Instance,
	kit: Kit?,
	face: CFrame,
	width: number,
	long: number,
	color: Color3
)
	local rng = Random.new(math.floor(face.Position.X * 13 + face.Position.Z * 7 + face.Position.Y))
	part(folder, {
		Name = "TowerBanner",
		Size = Vector3.new(width, long, 0.12),
		CFrame = face,
		Material = Enum.Material.Fabric,
		Color = color,
	})
	local tip = width / math.sqrt(2)
	part(folder, {
		Name = "TowerBanner",
		Size = Vector3.new(tip, tip, 0.11),
		CFrame = face * CFrame.new(0, -long / 2, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Material = Enum.Material.Fabric,
		Color = color,
	})
	part(folder, {
		Name = "BannerRod",
		Size = Vector3.new(width + 0.6, 0.28, 0.28),
		CFrame = face * CFrame.new(0, long / 2 + 0.1, -0.06),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	emblem(folder, kit, face * CFrame.new(0, long * 0.1, 0), width * 0.62, rng)
end

-- A chain of links from `a` to `b` (world), sagging by `sag` in the middle.
local function chain(folder: Instance, a: Vector3, b: Vector3, sag: number, color: Color3, neon: boolean)
	local links = math.max(2, math.floor((b - a).Magnitude / 0.9))
	local prev = a
	for i = 1, links do
		local t = i / links
		local at = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		local mid = (prev + at) / 2
		part(folder, {
			Name = "ChainLink",
			Size = Vector3.new(0.18, 0.5, (at - prev).Magnitude + 0.3),
			CFrame = CFrame.lookAt(mid, at) * CFrame.Angles(0, 0, if i % 2 == 0 then math.rad(90) else 0),
			Material = if neon then Enum.Material.Neon else Enum.Material.Metal,
			Color = color,
		})
		prev = at
	end
end

-- A diamond set in a gold frame on a face (its -Z out), `s` across.
local function inlay(folder: Instance, face: CFrame, s: number)
	part(folder, {
		Name = "InlayFrame",
		Size = Vector3.new(s, s, 0.14),
		CFrame = face * CFrame.new(0, 0, -0.03) * CFrame.Angles(0, 0, math.rad(45)),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local gem = part(folder, {
		Name = "Inlay",
		Size = Vector3.new(s * 0.72, s * 0.72, 0.2),
		CFrame = face * CFrame.new(0, 0, -0.08) * CFrame.Angles(0, 0, math.rad(45)),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(246, 249, 255),
	})
	gem.Reflectance = 0.35
	part(folder, {
		Name = "InlayCore",
		Size = Vector3.new(s * 0.3, s * 0.3, 0.22),
		CFrame = face * CFrame.new(0, 0, -0.09) * CFrame.Angles(0, 0, math.rad(45)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(235, 248, 255),
	})
end

-- Snow lying on top of a block (a merlon, a cap): a slightly wider white slab.
local function snowCap(folder: Instance, cframe: CFrame, size: Vector3)
	part(folder, {
		Name = "Snow",
		Size = Vector3.new(size.X + 0.35, 0.4, size.Z + 0.35),
		CFrame = cframe * CFrame.new(0, size.Y / 2 + 0.15, 0),
		Material = Enum.Material.Snow,
		Color = SNOW,
	})
end

-- A flat round patch lying on the ground or a floor (snow, moss, an ice floe, a lily pad).
local function patch(
	folder: Instance,
	at: CFrame,
	diameter: number,
	material: Enum.Material,
	color: Color3,
	name: string
)
	part(folder, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, diameter, diameter),
		CFrame = at * CFrame.Angles(0, 0, math.rad(90)),
		Material = material,
		Color = color,
	})
end

-- A smoke plume rising from `at` (the Fire concept's smoking walls).
local function smoke(folder: Instance, at: CFrame)
	local source = part(folder, {
		Name = "KitSmoke",
		Size = Vector3.new(3, 1, 3),
		CFrame = at,
		Transparency = 1,
	})
	local plume = Instance.new("ParticleEmitter")
	plume.Name = "KitSmoke"
	plume.Texture = SMOKE
	plume.Color = ColorSequence.new(Color3.fromRGB(70, 62, 60), Color3.fromRGB(130, 124, 122))
	plume.Rate = 3
	plume.Lifetime = NumberRange.new(7, 10)
	plume.Speed = NumberRange.new(2, 3)
	plume.SpreadAngle = Vector2.new(12, 12)
	plume.Acceleration = Vector3.new(0.4, 0.8, 0)
	plume.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5),
		NumberSequenceKeypoint.new(1, 10),
	})
	plume.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	plume.EmissionDirection = Enum.NormalId.Top
	plume.Parent = source
end

-- A small cypress (a dark green cone of stepped tiers on a trunk).
local function cypress(folder: Instance, at: CFrame, height: number)
	part(folder, {
		Name = "CypressTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 0.5, 0.5),
		CFrame = at * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(80, 58, 40),
	})
	local steps = 7
	for i = 0, steps - 1 do
		local d = 2.6 * (1 - i / steps) + 0.4
		part(folder, {
			Name = "Cypress",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((height - 1) / steps + 0.1, d, d),
			CFrame = at
				* CFrame.new(0, 1 + (i + 0.5) * (height - 1) / steps, 0)
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromRGB(38, 92, 50),
		})
	end
end

-- A window box of flowers on a wall face (its -Z out).
local function flowerBox(folder: Instance, face: CFrame, width: number, rng: Random)
	part(folder, {
		Name = "FlowerBox",
		Size = Vector3.new(width, 0.9, 1.1),
		CFrame = face * CFrame.new(0, 0, -0.55),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(110, 78, 52),
	})
	local colors = {
		Color3.fromRGB(240, 110, 200),
		Color3.fromRGB(170, 120, 255),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(255, 255, 255),
	}
	for i = 1, math.floor(width / 0.55) do
		local x = -width / 2 + (i - 0.5) * 0.55
		part(folder, {
			Name = "FlowerLeaf",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7),
			CFrame = face * CFrame.new(x, 0.55, -0.55 + rng:NextNumber(-0.2, 0.2)),
			Material = Enum.Material.Grass,
			Color = IVY,
		})
		part(folder, {
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.42, 0.42, 0.42),
			CFrame = face * CFrame.new(x + rng:NextNumber(-0.15, 0.15), 0.95, -0.6),
			Material = Enum.Material.SmoothPlastic,
			Color = colors[rng:NextInteger(1, #colors)],
		})
	end
end

-- The kit's touches on one tower: rings, lava veins, ivy, rune columns, icicles
-- and snow, diamond inlays, and (front towers) the cluster round its feet.
local function dressTower(folder: Instance, kit: Kit, tower: TowerSpot, front: boolean, rng: Random)
	local r, h = tower.radius, tower.height
	local bands = kit.bands
	if bands then
		for _, at in bands.at do
			part(folder, {
				Name = "KitBand",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(bands.width, r * 2 + 0.4, r * 2 + 0.4),
				CFrame = tower.base * CFrame.new(0, h * at, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = bands.material,
				Color = bands.color,
			})
		end
	end
	if kit.effects.veins then
		-- Glowing cracks wandering up the tower
		for _, deg in { -150, -85, -25, 25, 85, 150 } do
			local angle, y = math.rad(deg + rng:NextNumber(-10, 10)), rng:NextNumber(0.4, 2.5)
			for _ = 1, rng:NextInteger(7, 12) do
				local long = rng:NextNumber(1.4, 2.8)
				local tilt = rng:NextNumber(-0.8, 0.8)
				local dy, da = long * math.cos(tilt), long * math.sin(tilt) / r
				if y + dy > h - 1.6 then
					break
				end
				part(folder, {
					Name = "LavaVein",
					Size = Vector3.new(0.3, long + 0.15, 0.1),
					CFrame = onTower(tower, angle + da / 2, y + dy / 2, 0.05) * CFrame.Angles(0, 0, -tilt),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 110, 30),
				})
				y += dy
				angle += da
			end
		end
	end
	if kit.effects.vines then
		-- Ivy falling from the crown, with leaves
		for k = 0, 8 do
			local angle = math.rad(-110 + k * 27.5 + rng:NextNumber(-6, 6))
			local long = h * rng:NextNumber(0.25, 0.7)
			part(folder, {
				Name = "Ivy",
				Size = Vector3.new(rng:NextNumber(0.8, 1.5), long, 0.2),
				CFrame = onTower(tower, angle, h - 1.4 - long / 2, 0.1),
				Material = Enum.Material.Grass,
				Color = IVY:Lerp(Color3.fromRGB(110, 170, 70), rng:NextNumber()),
			})
			for j = 1, math.floor(long / 2.2) do
				part(folder, {
					Name = "IvyLeaf",
					Size = Vector3.new(1.2, 0.9, 0.3),
					CFrame = onTower(tower, angle + rng:NextNumber(-0.08, 0.08), h - 1.4 - j * 2.2, 0.25)
						* CFrame.Angles(0, 0, rng:NextNumber(0, 6.28)),
					Material = Enum.Material.Grass,
					Color = IVY:Lerp(Color3.fromRGB(130, 190, 80), rng:NextNumber()),
				})
			end
		end
	end
	if kit.effects.runes then
		-- Columns of glyphs either side of each banner
		for _, deg in { -78, -22, 22, 78 } do
			for j = 0, 5 do
				glyph(folder, onTower(tower, math.rad(deg), h * 0.24 + j * 2, 0.02), 1.5, kit.light, rng)
			end
		end
	end
	if kit.effects.icicles then
		local ring = 2 * math.pi * (r + 0.7)
		local count = math.floor(ring / 1.5)
		for k = 1, count do
			local long = rng:NextNumber(0.9, 2.6)
			part(folder, {
				ClassName = "WedgePart",
				Name = "Icicle",
				Size = Vector3.new(0.45, long, 0.6),
				CFrame = onTower(tower, k / count * math.pi * 2, h - 1.4 - long / 2, 0.6)
					* CFrame.Angles(math.pi, 0, 0),
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(205, 238, 255),
				Transparency = 0.15,
			})
		end
	end
	if kit.effects.snow then
		patch(folder, tower.base * CFrame.new(0, h + 0.62, 0), r * 2 + 1.5, Enum.Material.Snow, SNOW, "Snow")
	end
	if kit.decor then
		-- Starfish and shells all over the tower's outer side
		local count = math.floor(h * r * 2.4 / kit.decor.every)
		for _ = 1, count do
			inset(
				folder,
				kit,
				kit.decor.names[rng:NextInteger(1, #kit.decor.names)],
				onTower(tower, math.rad(rng:NextNumber(-100, 100)), rng:NextNumber(h * 0.12, h * 0.9), 0.02),
				kit.decor.size * rng:NextNumber(0.7, 1.3),
				rng
			)
		end
	elseif kit.plaque then
		for _, deg in { -78, -22, 22, 78 } do
			piece(folder, kit.plaque, onTower(tower, math.rad(deg), h * 0.3, 0.15), 2.6)
		end
	end
	if kit.effects.inlays then
		for _, y in { h * 0.3, h * 0.66 } do
			for _, deg in { -75, -25, 25, 75 } do
				inlay(folder, onTower(tower, math.rad(deg), y, 0.02), 1.9)
			end
		end
	end
	local feet = kit.feet
	if front and feet then
		for k = 1, feet.count do
			local angle =
				math.rad(-70 + (k - 1) * 140 / math.max(feet.count - 1, 1) + rng:NextNumber(-10, 10))
			local at = tower.base
				* CFrame.new(math.sin(angle) * (r + 3.2), 0, -math.cos(angle) * (r + 3.2))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			local model =
				piece(folder, feet.name, at, feet.size * (if k == 2 then 1 else rng:NextNumber(0.6, 0.8)))
			tint(model, kit, rng)
			if feet.glow then
				glow(folder, model, kit, 20)
			end
		end
	end
end

-- Dressing on a cone roof, for kits that keep it: gems set in it (Moon), crystals
-- jutting out of it (Void), moss and ivy over it (Moss). `radius` is the roof's
-- at its eaves.
function CastleKits.roof(folder: Instance, kit: Kit, roofBase: CFrame, radius: number, height: number)
	local rng =
		Random.new(math.floor(math.abs(roofBase.Position.X) * 7 + math.abs(roofBase.Position.Z) * 3) + 1)
	-- A point on the cone's side: `angle` round from the front, `f` up its height
	-- (the face there, and the outward and surface-normal directions, in world space)
	local function side(angle: number, f: number, out: number): (CFrame, Vector3, Vector3)
		local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local at = dir * (radius * (1 - f) + out) + Vector3.new(0, f * height, 0)
		local normal = (dir * height + Vector3.new(0, radius, 0)).Unit
		return roofBase * CFrame.lookAt(at, at + normal),
			roofBase:VectorToWorldSpace(dir),
			roofBase:VectorToWorldSpace(normal)
	end
	if kit.effects.roofGems then
		for _, f in { 0.28, 0.52 } do
			for k = 0, 5 do
				local face = side(k / 6 * math.pi * 2 + f * 2, f, 0.06)
				part(folder, {
					Name = "RoofGem",
					Size = Vector3.new(0.9, 1.5, 0.3),
					CFrame = face * CFrame.Angles(0, 0, math.rad(45)),
					Material = Enum.Material.Neon,
					Color = kit.light,
				})
			end
		end
		light(
			anchor(folder, roofBase * CFrame.new(0, height * 0.4, -radius * 0.8), "RoofGlow"),
			kit.light,
			12,
			0.8
		)
	end
	local dress = kit.roofDress
	if dress then
		for k = 1, dress.count do
			local angle = k / dress.count * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local face, dir, normal = side(angle, rng:NextNumber(0.12, 0.35), -0.4)
			local up = (normal + roofBase.UpVector * 0.6).Unit
			local frame = CFrame.fromMatrix(face.Position, dir:Cross(up).Unit, up)
			piece(folder, dress.name, frame, radius * dress.scale * rng:NextNumber(0.8, 1.2))
		end
	end
	if kit.effects.moss then
		for _ = 1, 10 do
			local face = side(rng:NextNumber(0, 6.28), rng:NextNumber(0.05, 0.7), 0)
			part(folder, {
				Name = "RoofMoss",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1, 1, 1) * rng:NextNumber(1.2, 2.4),
				CFrame = face,
				Material = Enum.Material.Grass,
				Color = IVY:Lerp(Color3.fromRGB(100, 160, 70), rng:NextNumber()),
			})
		end
		-- Ivy hanging from the eaves
		for k = 1, 10 do
			local a = k / 10 * math.pi * 2
			local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
			local at = dir * (radius + 0.15)
			local long = rng:NextNumber(1.5, 4.5)
			part(folder, {
				Name = "Ivy",
				Size = Vector3.new(rng:NextNumber(0.6, 1.1), long, 0.2),
				CFrame = roofBase * CFrame.lookAt(at, at + dir) * CFrame.new(0, -long / 2, 0),
				Material = Enum.Material.Grass,
				Color = IVY,
			})
		end
	end
end

-- Columns of glowing glyphs down a wall face (the Void concept's walls).
local function runeWall(
	folder: Instance,
	a: Vector3,
	b: Vector3,
	outward: Vector3,
	height: number,
	kit: Kit,
	rng: Random
)
	local length = (b - a).Magnitude
	for i = 1, math.floor(length / 6) - 1 do
		local top = a + (b - a).Unit * (i * 6)
		for j = 0, math.floor(height * 0.55 / 2) do
			local at = top - Vector3.new(0, height * 0.2 + j * 2, 0)
			glyph(folder, CFrame.lookAt(at, at + outward), 1.6, kit.light, rng)
		end
	end
end

-- Everything a kit adds besides the caps, into `folder`.
function CastleKits.dress(folder: Instance, kit: Kit, site: Site)
	local origin = site.origin
	local rng = Random.new(site.level * 31 + #site.runs)
	local centre = Vector3.new(0, 0, (site.front + site.back) / 2)
	local h, t = site.height, site.thickness

	-- Along the walls: battlement growths, plaques, and the wall effects
	for _, run in site.runs do
		local a, b = run.a, run.b
		local length = (b - a).Magnitude
		if length < 4 then
			continue
		end
		local dir = (b - a).Unit
		local outward = Vector3.new(dir.Z, 0, -dir.X)
		if ((a + b) / 2 - centre):Dot(outward) < 0 then
			outward = -outward
		end
		local edgeA: Vector3 = origin * (a + outward * (t / 2 + 0.05) + Vector3.new(0, h, 0))
		local edgeB: Vector3 = origin * (b + outward * (t / 2 + 0.05) + Vector3.new(0, h, 0))
		local worldOut = origin:VectorToWorldSpace(outward)
		if site.stone and kit.growth and kit.growthEvery > 0 then
			local mode = kit.growthMode or "clusters"
			local function nearGate(spot: Vector3): boolean
				return math.abs(spot.X) < site.gateHalf + 6 and math.abs(spot.Z - site.front) < 1
			end
			if mode == "merlons" then
				-- One on every other merlon, sunk into its top
				local merlons = math.max(1, math.floor(length / 4))
				for i = 0, merlons, 2 do
					local spot = a + (b - a) * (i / merlons)
					if not nearGate(spot) then
						local at = origin
							* CFrame.lookAt(spot, spot + outward)
							* CFrame.new(0, h + 2.1, 0)
							* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
						growth(folder, kit, at, kit.growthSize * rng:NextNumber(0.8, 1.05), rng)
					end
				end
			elseif mode == "row" then
				local count = math.max(1, math.floor(length / kit.growthEvery))
				for i = 1, count do
					local spot = a + (b - a) * ((i - 0.5) / count)
					if not nearGate(spot) then
						local at = origin
							* CFrame.lookAt(spot + outward * (t * 0.25), spot + outward * 2)
							* CFrame.new(0, h + 0.6, 0)
						growth(folder, kit, at, kit.growthSize * rng:NextNumber(0.85, 1.2), rng)
					end
				end
			else
				-- Clusters at irregular spots along the outer edge, heavier near
				-- the towers and the gate ("corners": only there), with pieces
				-- growing out of the face below
				local x = rng:NextNumber(1, kit.growthEvery * 0.6)
				local index = 0
				while x < length - 1 do
					local spot = a + (b - a).Unit * x
					local nearCorner = math.min(x, length - x) < 9
						or (
							math.abs(spot.Z - site.front) < 1
							and math.abs(math.abs(spot.X) - site.gateHalf - 4.5) < 8
						)
					if not nearGate(spot) and (mode ~= "corners" or nearCorner) then
						index += 1
						local top = origin
							* CFrame.lookAt(spot + outward * (t * 0.3), spot + outward * 4)
							* CFrame.new(0, h + 0.6, 0)
						local made = cluster(folder, kit, top, if nearCorner then 1.15 else 0.95, rng)
						if mode == "clusters" and rng:NextNumber() < 0.65 then
							local face = origin
								* CFrame.lookAt(spot + outward * (t / 2), spot + outward * 4)
								* CFrame.new(rng:NextNumber(-1.5, 1.5), h - rng:NextNumber(1.5, 4), 0)
							growth(
								folder,
								kit,
								face
									* CFrame.Angles(-math.rad(rng:NextNumber(50, 70)), 0, 0)
									* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
								kit.growthSize * rng:NextNumber(0.45, 0.7),
								rng
							)
						end
						if kit.growthGlow and index % 3 == 1 and made[1] then
							glow(folder, made[1], kit, 10)
						end
					end
					x += kit.growthEvery * rng:NextNumber(0.6, 1.5)
				end
			end
		end
		if site.stone and kit.wallTrim then
			local mid = (a + b) / 2
			local face = origin * CFrame.lookAt(mid + outward * (t / 2 + 0.1), mid + outward * 4)
			part(folder, {
				Name = "KitWallTrim",
				Size = Vector3.new(length, 1.1, 0.3),
				CFrame = face * CFrame.new(0, h - 0.9, 0),
				Material = kit.wallTrim.material,
				Color = kit.wallTrim.color,
			})
		end
		-- Starfish and shells set into the face, and little gardens at its foot
		if site.stone and kit.decor then
			local mid = (a + b) / 2
			local face = origin
				* CFrame.lookAt(mid + outward * (t / 2 + 0.02), mid + outward * 4)
				* CFrame.new(0, h * 0.5, 0)
			local width = length - (if math.abs(mid.Z - site.front) < 1 then 2 else 6)
			scatter(folder, kit, face, width, h * 0.75, rng)
		end
		if kit.garden then
			local x = rng:NextNumber(2, kit.garden.every)
			while x < length - 2 do
				local spot = a + (b - a).Unit * x
				if not (math.abs(spot.X) < site.gateHalf + 3 and math.abs(spot.Z - site.front) < 1) then
					local at = origin * CFrame.lookAt(spot + outward * (t / 2 + 2.2), spot + outward * 8)
					garden(folder, kit, at, rng)
				end
				x += kit.garden.every * rng:NextNumber(0.7, 1.3)
			end
		end
		if site.stone and kit.plaque and kit.decor == nil then
			local count = math.max(1, math.floor(length / 7))
			for i = 1, count do
				local spot = a + (b - a) * ((i - 0.5) / count)
				if math.abs(spot.X) < site.gateHalf + 6 and math.abs(spot.Z - site.front) < 1 then
					continue
				end
				local at = origin
					* CFrame.lookAt(spot + outward * (t / 2 + 0.2), spot + outward * 4)
					* CFrame.new(rng:NextNumber(-1, 1), h * (if i % 2 == 0 then 0.32 else 0.5), 0)
				piece(folder, kit.plaque, at, rng:NextNumber(2.2, 3))
			end
		end
		if site.stone and kit.effects.icicles then
			icicles(folder, edgeA, edgeB, worldOut, rng)
		end
		if site.stone and kit.effects.vines then
			vines(folder, edgeA, edgeB, worldOut, h, rng)
		end
		if site.stone and kit.effects.runes then
			runeWall(folder, edgeA, edgeB, worldOut, h, kit, rng)
		end
		if site.stone and kit.effects.veins then
			veins(folder, edgeA + worldOut * 0.05, edgeB + worldOut * 0.05, worldOut, h, rng)
		end
		if site.stone then
			-- Sconces in the theme's light all along the walls (the concepts glow)
			local count = math.max(1, math.floor(length / 8))
			for i = 1, count do
				local spot = a + (b - a) * ((i - 0.5) / count)
				if math.abs(spot.X) < site.gateHalf + 4 and math.abs(spot.Z - site.front) < 1 then
					continue
				end
				local at = origin
					* CFrame.lookAt(spot + outward * (t / 2), spot + outward * 4)
					* CFrame.new(0, h * 0.62, -0.5)
				part(folder, {
					Name = "SconceBracket",
					Size = Vector3.new(0.5, 0.5, 1.1),
					CFrame = at * CFrame.new(0, -0.5, 0.2),
					Material = Enum.Material.Metal,
					Color = Color3.fromRGB(50, 50, 58),
				})
				local orb = part(folder, {
					Name = "Sconce",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(1, 1, 1),
					CFrame = at,
					Material = Enum.Material.Neon,
					Color = kit.flame,
				})
				if i % 2 == 1 then
					light(orb, kit.light, 16, 1.1)
				end
			end
			-- On the battlements: the theme's lanterns or braziers every few merlons
			-- (the same spacing Fortress gives them), and snow on every merlon
			local merlons = math.max(1, math.floor(length / 4))
			for i = 0, merlons do
				local spot = a + (b - a) * (i / merlons)
				local top = origin * CFrame.lookAt(spot, spot + outward) * CFrame.new(0, h + 2.4, 0)
				if kit.effects.snow then
					local cap = CFrame.fromMatrix(top.Position, worldOut, Vector3.yAxis)
					snowCap(folder, cap * CFrame.new(0, -0.9, 0), Vector3.new(t + 0.3, 1.8, 2))
				end
				local nearGate = math.abs(spot.X) < site.gateHalf + 6 and math.abs(spot.Z - site.front) < 1
				if kit.wallLight and i % 4 == 2 and i < merlons and not nearGate then
					local model = piece(folder, kit.wallLight, top, 3.4)
					if model and kit.wallLightFlame then
						CastleKits.flame(anchor(folder, topOf(model), "WallFlame"), kit, 2.4, 16)
					elseif model then
						light(anchor(folder, topOf(model), "WallLight"), kit.light, 16, 1.3)
					end
				end
			end
		end
		if site.stone and kit.effects.pearls then
			pearls(folder, edgeA + Vector3.new(0, 0.4, 0), edgeB + Vector3.new(0, 0.4, 0), worldOut)
		end
		if site.stone and kit.plinth then
			local band = h * kit.plinth.height
			local face = origin
				* CFrame.lookAt((a + b) / 2 + outward * (t / 2 + 0.2), b + outward * (t / 2 + 0.2))
			part(folder, {
				Name = "KitPlinth",
				Size = Vector3.new(0.4, band, length),
				CFrame = face * CFrame.new(0, band / 2, 0),
				Material = kit.plinth.material,
				Color = kit.plinth.color,
			})
			part(folder, {
				Name = "KitPlinthTrim",
				Size = Vector3.new(0.7, 0.45, length),
				CFrame = face * CFrame.new(0, band, 0),
				Material = kit.plinth.material,
				Color = kit.plinth.color:Lerp(Color3.new(1, 1, 1), 0.25),
			})
		end
	end

	-- The front: lava falls either side of the gate
	if site.stone and kit.effects.lavaFalls then
		for _, side in { -1, 1 } do
			local x = side * (site.gateHalf + 9)
			local top = origin
				* CFrame.lookAt(
					Vector3.new(x, h, site.front - t / 2 - 0.25),
					Vector3.new(x, h, site.front - 10)
				)
			lavaFall(folder, top, h, 2.4)
		end
	end

	-- The ground round the castle, in the theme's own (sand, scorched rock, snow...)
	if kit.ground then
		local ground = kit.ground
		local inner, ring = t / 2, 10 -- neighbours sit about 25 studs apart at the front corners
		local x0, x1 = site.halfW + inner, site.halfW + inner + ring
		local z0, z1 = site.front - inner - ring, site.back + inner + ring
		local strips = {
			{ Vector3.new(0, 0, (z0 + site.front - inner) / 2), Vector3.new(x1 * 2, 0.12, ring) },
			{ Vector3.new(0, 0, (site.back + inner + z1) / 2), Vector3.new(x1 * 2, 0.12, ring) },
			{ Vector3.new(-(x0 + x1) / 2, 0, (z0 + z1) / 2), Vector3.new(ring, 0.12, z1 - z0) },
			{ Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2), Vector3.new(ring, 0.12, z1 - z0) },
		}
		for _, strip in strips do
			local stripPart = part(folder, {
				Name = "KitGround",
				Size = strip[2],
				CFrame = origin * CFrame.new(strip[1] + Vector3.new(0, 0.07, 0)),
				Material = ground.material,
				Color = ground.color,
			})
			if kit.effects.floes then
				local area = strip[2]
				for _ = 1, math.floor(area.X * area.Z / 40) do
					patch(
						folder,
						stripPart.CFrame
							* CFrame.new(
								rng:NextNumber(-area.X / 2 + 1.5, area.X / 2 - 1.5),
								0.12,
								rng:NextNumber(-area.Z / 2 + 1.5, area.Z / 2 - 1.5)
							),
						rng:NextNumber(1.6, 3.6),
						Enum.Material.Snow,
						SNOW,
						"IceFloe"
					)
				end
			end
		end
	end

	-- Tower feet: a glowing pool, clusters beside each tower (or roots wrapped
	-- round it), a lantern, and growths on the crown
	for index, tower in site.towers do
		local isFront = origin:PointToObjectSpace(tower.base.Position).Z < centre.Z
		if kit.pool and isFront then
			-- A basin hugging the tower's outer side: overlapping discs make an
			-- organic shape, a darker rim round them, light from the water
			local pool = kit.pool
			local r = tower.radius
			for k, angle in { 0, 55, -55, 110, -110 } do
				local a = math.rad(angle)
				local reach = r + pool.size * 0.45
				local size = pool.size * (if k == 1 then 2.2 else 1.7)
				local at = tower.base * CFrame.new(math.sin(a) * reach, 0.1 + k * 0.004, -math.cos(a) * reach)
				local disc = part(folder, {
					Name = "KitPool",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.2, size, size),
					CFrame = at * CFrame.Angles(0, 0, math.rad(90)),
					Material = pool.material,
					Color = pool.color,
					Transparency = if pool.material == Enum.Material.Glass then 0.2 else 0,
				})
				part(folder, {
					Name = "KitPoolRim",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.3, size + 1.4, size + 1.4),
					CFrame = at * CFrame.new(0, -0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Material = if kit.ground then kit.ground.material else Enum.Material.Slate,
					Color = if kit.ground
						then kit.ground.color:Lerp(Color3.new(0, 0, 0), 0.3)
						else Color3.fromRGB(90, 90, 96),
				})
				if pool.glow and k <= 3 then
					light(disc, kit.light, 18, 1.4)
				end
				if kit.effects.lilies then
					for _ = 1, 3 do
						local spread = size * 0.32
						local pad = at
							* CFrame.new(
								rng:NextNumber(-spread, spread),
								0.14,
								rng:NextNumber(-spread, spread)
							)
						patch(
							folder,
							pad,
							rng:NextNumber(1.2, 2),
							Enum.Material.Grass,
							Color3.fromRGB(70, 150, 70),
							"LilyPad"
						)
						if rng:NextNumber() < 0.4 then
							part(folder, {
								Name = "LilyFlower",
								Shape = Enum.PartType.Ball,
								Size = Vector3.new(0.6, 0.6, 0.6),
								CFrame = pad * CFrame.new(0, 0.3, 0),
								Material = Enum.Material.SmoothPlastic,
								Color = Color3.fromRGB(255, 160, 210),
							})
						end
					end
				end
				if kit.effects.floes then
					for _ = 1, 2 do
						local spread = size * 0.3
						patch(
							folder,
							at
								* CFrame.new(
									rng:NextNumber(-spread, spread),
									0.15,
									rng:NextNumber(-spread, spread)
								),
							rng:NextNumber(1.6, 3.2),
							Enum.Material.Snow,
							SNOW,
							"IceFloe"
						)
					end
				end
				if pool.crust then
					for _ = 1, 7 do
						local spread = size * 0.32
						local chunk = rng:NextNumber(1.4, 3.4)
						part(folder, {
							Name = "LavaCrust",
							Size = Vector3.new(chunk, 0.35, chunk * rng:NextNumber(0.6, 1)),
							CFrame = at * CFrame.new(
								rng:NextNumber(-spread, spread),
								0.15,
								rng:NextNumber(-spread, spread)
							) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
							Material = Enum.Material.Basalt,
							Color = Color3.fromRGB(42, 33, 31),
						})
					end
				end
			end
		end
		if kit.lantern or kit.brazier then
			local lanternName = kit.lantern or kit.brazier
			local side = if index % 2 == 0 then 1 else -1
			local at = tower.base * CFrame.new(side * (tower.radius + 2.2), 0, -(tower.radius * 0.4))
			local lantern = piece(folder, lanternName, at, if kit.lantern then kit.lanternSize else 4.5)
			if lantern then
				light(anchor(folder, topOf(lantern), "TowerLantern"), kit.light, 16, 1.3)
			end
		end
		-- The crown glows in the theme's light, lighting the cap and its growths
		if site.stone then
			light(
				anchor(folder, tower.base * CFrame.new(0, tower.height + 3, -tower.radius), "CrownLight"),
				kit.light,
				18,
				1
			)
		end
		if site.stone and kit.growth and kit.growthSize > 0 then
			-- A bouquet round the crown: big pieces leaning out from round the
			-- cap and smaller ones between, sunk into the battlements
			local n = kit.crownCount or 6
			for k = 1, n do
				local angle = (k / n) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
				local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
				local pos = dir * (tower.radius + 0.1) + Vector3.new(0, tower.height + 1, 0)
				local big = k % 3 == 1
				local at = tower.base
					* CFrame.lookAt(pos, pos + dir)
					* CFrame.Angles(
						-math.rad(if big then rng:NextNumber(10, 28) else rng:NextNumber(20, 45)),
						0,
						0
					)
					* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
				growth(
					folder,
					kit,
					at,
					kit.growthSize * (if big then rng:NextNumber(1.3, 1.75) else rng:NextNumber(0.65, 1)),
					rng
				)
			end
		end
	end
	for _, tower in site.towers do
		local isFront = origin:PointToObjectSpace(tower.base.Position).Z < centre.Z
		if site.stone then
			dressTower(folder, kit, tower, isFront, rng)
		end
		if site.stone and kit.plinth then
			local band = h * kit.plinth.height
			part(folder, {
				Name = "KitPlinth",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(band, tower.radius * 2 + 0.5, tower.radius * 2 + 0.5),
				CFrame = tower.base * CFrame.new(0, band / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = kit.plinth.material,
				Color = kit.plinth.color,
			})
			part(folder, {
				Name = "KitPlinthTrim",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.45, tower.radius * 2 + 0.9, tower.radius * 2 + 0.9),
				CFrame = tower.base * CFrame.new(0, band, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = kit.plinth.material,
				Color = kit.plinth.color:Lerp(Color3.new(1, 1, 1), 0.25),
			})
		end
		if kit.base and kit.baseSize > 0 then
			if kit.baseWrap then
				piece(folder, kit.base, tower.base, kit.baseSize)
			else
				local at = tower.base * CFrame.new(tower.radius * 0.5, 0, -(tower.radius + 1.6))
				piece(folder, kit.base, at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), kit.baseSize)
				local side = tower.base * CFrame.new(-(tower.radius + 1.4), 0, -tower.radius * 0.6)
				piece(
					folder,
					kit.base,
					side * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
					kit.baseSize * 0.65
				)
			end
		end
		-- Floating pieces round the tower top
		if kit.floater and kit.floaterSize > 0 then
			local count = kit.floaterCount or 2
			for k = 1, count do
				-- Spread round the front of the tower (the side people see), or
				-- right round it when there are many
				local angle = if count >= 4
					then (k / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
					else math.rad(-70 + (k - 0.5) * 140 / count + rng:NextNumber(-10, 10))
				local at = tower.tip
					* CFrame.new(
						math.sin(angle) * (tower.radius + 3),
						-tower.radius * 0.8 - (k % 3) * 1.6,
						-math.cos(angle) * (tower.radius + 3)
					)
				if kit.effects.chains then
					-- Hung inward over the courtyard, between the tower and the keep
					local towerPoint = origin:PointToObjectSpace(tower.base.Position)
					local dir = Vector3.new(-towerPoint.X, 0, centre.Z - towerPoint.Z).Unit
					angle = math.atan2(dir.X, -dir.Z)
					at = origin * CFrame.new(towerPoint + dir * (tower.radius + 9) + Vector3.new(0, h + 7, 0))
				end
				local model = piece(folder, kit.floater, at, kit.floaterSize * rng:NextNumber(0.8, 1.1))
				if model then
					float(model, model:GetPivot(), 0.8, rng:NextNumber(0.2, 0.5))
					light(anchor(model, model:GetBoundingBox(), "FloatLight"), kit.light, 10, 0.8)
					if kit.effects.chains then
						-- Chained to the tower's crown and to the wall below, sagging,
						-- with lightning crackling round it
						local box = model:GetBoundingBox()
						local towerPoint = origin:PointToObjectSpace(tower.base.Position)
						local offset = origin:PointToObjectSpace(box.Position) - towerPoint
						local flat = Vector3.new(offset.X, 0, offset.Z).Unit
						local hold = origin
							* CFrame.new(
								towerPoint + flat * (tower.radius + 0.6) + Vector3.new(0, tower.height, 0)
							)
						chain(folder, hold.Position, box.Position, 1.5, Color3.fromRGB(60, 62, 70), false)
						for _ = 1, 2 do
							arc(
								folder,
								box,
								box
									* CFrame.new(
										rng:NextNumber(-4, 4),
										rng:NextNumber(-3, 3),
										rng:NextNumber(-4, 4)
									)
							)
						end
						light(anchor(folder, box, "StoneLight"), kit.light, 16, 1.6)
					end
				end
			end
		end
	end

	-- Lightning: crackling round every coil tip, from the back coils up into the
	-- storm cloud and from the cloud down onto the keep (the client flickers it)
	local over = origin
		* CFrame.lookAt(Vector3.new(0, 0, site.back - 12), Vector3.new(0, 0, site.front - 40))
		* CFrame.new(0, h + 44, 0)
	if kit.effects.arcs then
		for _, tower in site.towers do
			for _ = 1, 3 do
				arc(
					folder,
					tower.tip,
					tower.tip
						* CFrame.new(rng:NextNumber(-5, 5), rng:NextNumber(-3, 2), rng:NextNumber(-5, 5))
				)
			end
			local isBack = origin:PointToObjectSpace(tower.base.Position).Z > centre.Z
			if isBack and kit.effects.stormCloud then
				arc(folder, tower.tip, over * CFrame.new(rng:NextNumber(-6, 6), 2, 0))
			end
		end
		if kit.effects.stormCloud then
			arc(folder, over * CFrame.new(0, 1, 0), over * CFrame.new(rng:NextNumber(-3, 3), -16, 2))
		end
	end

	-- At the gate: braziers, guardian statues and the ornament
	local gateFront = site.front - site.gateDepth / 2
	local gateTop = site.gateTop or (GATE_CLEAR + 3.5)
	for _, side in { -1, 1 } do
		local x = side * (site.gateHalf + 8)
		local base = origin
			* CFrame.lookAt(Vector3.new(x, 0, site.front - 8.5), Vector3.new(x, 0, site.front - 20))
		local brazier = piece(folder, kit.frontBrazier or kit.brazier, base, kit.frontBrazierSize or 5)
		if brazier then
			local flameAt = anchor(folder, topOf(brazier), "BrazierFlame")
			CastleKits.flame(flameAt, kit, 3.5, 18)
		end
		if kit.effects.cypress then
			cypress(
				folder,
				origin * CFrame.new(side * (site.gateHalf + 5.2), 0, site.front - site.gateDepth / 2 - 2.6),
				7.5
			)
		end
		if kit.effects.flowers and site.stone then
			local boxX = side * (site.gateHalf + 9)
			local face = origin
				* CFrame.lookAt(
					Vector3.new(boxX, 4.5, site.front - t / 2),
					Vector3.new(boxX, 4.5, site.front - 10)
				)
			flowerBox(folder, face, 3.4, rng)
		end
		if kit.statue then
			local statueAt = origin
				* CFrame.lookAt(
					Vector3.new(side * (site.gateHalf + 3.2), 0, gateFront - 4),
					Vector3.new(side * (site.gateHalf + 3.2), 0, gateFront - 20)
				)
			local statue = piece(folder, kit.statue, statueAt, 7)
			if kit.growthGlow then
				glow(folder, statue, kit, 16)
			end
		end
	end
	-- Growths on the gatehouse towers' outer corners, beside the braziers
	if site.stone and kit.growth and kit.growthSize > 0 then
		for _, side in { -1, 1 } do
			local spot =
				Vector3.new(side * (site.gateHalf + 4.35), gateTop, site.front - site.gateDepth / 2 + 0.6)
			local at = origin * CFrame.lookAt(spot, spot + Vector3.new(side * 0.6, 0, -1))
			if (kit.growthMode or "clusters") == "clusters" then
				cluster(folder, kit, at, 1, rng, 3)
			else
				growth(
					folder,
					kit,
					at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
					kit.growthSize * 0.9,
					rng
				)
			end
		end
	end
	-- Coral beds either side of the way in (Coral), with the gatehouse's foot
	-- grown over
	if kit.effects.gateGarden then
		for _, side in { -1, 1 } do
			local x = side * (site.gateHalf + 3)
			local bed = origin * CFrame.new(x, 0.6, gateFront - 2.6)
			part(folder, {
				Name = "CoralBed",
				Size = Vector3.new(4.6, 1.2, 2.4),
				CFrame = bed,
				Material = Enum.Material.Sandstone,
				Color = Color3.fromRGB(222, 200, 160),
			})
			for k = 1, 5 do
				local name = if kit.garden then kit.garden.names[(k % #kit.garden.names) + 1] else kit.growth
				local model = piece(
					folder,
					name,
					bed
						* CFrame.new(-1.8 + (k - 1) * 0.9, 0.5, rng:NextNumber(-0.5, 0.5))
						* CFrame.Angles(-rng:NextNumber(0, 0.25), rng:NextNumber(0, 6.28), 0),
					kit.growthSize * rng:NextNumber(0.45, 0.7)
				)
				tint(model, kit, rng)
			end
		end
		if site.gateTop then
			for _, side in { -1, 1 } do
				local face = origin
					* CFrame.lookAt(
						Vector3.new(
							side * (site.gateHalf + 2.25),
							site.gateTop * 0.3,
							site.front - site.gateDepth / 2
						),
						Vector3.new(side * (site.gateHalf + 2.25), site.gateTop * 0.3, site.front - 20)
					)
				scatter(folder, kit, face, 3.6, site.gateTop * 0.5, rng)
			end
		end
	end
	-- Braziers or lanterns on top of the gatehouse towers (two, or four)
	local tops = kit.topBraziers or 2
	if site.stone and kit.brazier and tops > 0 then
		local spots: { number } = if tops >= 4 then { -3.4, -1.1, 1.1, 3.4 } else { -2.25, 2.25 }
		for _, dx in spots do
			local x = math.sign(dx) * (site.gateHalf + 2.25)
				+ (if tops >= 4 then math.sign(dx) * (math.abs(dx) - 2.25) else 0)
			local at = origin
				* CFrame.lookAt(Vector3.new(x, gateTop, site.front), Vector3.new(x, gateTop, site.front - 10))
			local top = piece(folder, kit.brazier, at, if tops >= 4 then 4.5 else 6.5)
			if top then
				CastleKits.flame(anchor(folder, topOf(top), "GateFlame"), kit, 4, 20)
			end
		end
	end
	if site.stone and kit.gate then
		local face = origin
			* CFrame.lookAt(Vector3.new(0, 0, gateFront - 0.4), Vector3.new(0, 0, gateFront - 10))
		if kit.gateMode == "arch" then
			local model = Props.template("WorldProps", kit.gate)
			if model then
				local arch = model:Clone()
				for _, d in arch:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				local span = site.gateHalf * 2 + 8
				local tall = GATE_CLEAR + 9
				-- Whichever way the model was imported, its long side spans the gate
				local extents = arch:GetExtentsSize()
				local turned = extents.Z > extents.X
				Props.place(
					arch,
					face
						* CFrame.new(0, tall / 2, -0.6)
						* (if turned then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity),
					if turned then Vector3.new(3, tall, span) else Vector3.new(span, tall, 3)
				)
				arch.Parent = folder
				light(anchor(folder, face * CFrame.new(0, tall * 0.6, -2), "ArchGlow"), kit.light, 18, 1.6)
			end
		else
			local crest = piece(folder, kit.gate, face * CFrame.new(0, GATE_CLEAR + 0.5, -0.6), 6)
			faceOut(crest)
			if kit.gateTint then
				tintWith(crest, kit.gateTint)
			end
		end
	end
	-- Banners on the gatehouse towers' fronts, as on every concept
	if site.stone and site.gateTop then
		for _, side in { -1, 1 } do
			local x = side * (site.gateHalf + 2.25)
			local y = gateTop - 2.4 - 3.2
			local face = origin
				* CFrame.lookAt(
					Vector3.new(x, y, site.front - site.gateDepth / 2 - 0.1),
					Vector3.new(x, y, site.front - 20)
				)
			CastleKits.banner(folder, kit, face, 2.6, 4.6, site.banner)
		end
	end
	-- Gems set round the gate (Diamond), a great glyph over it (Void), lightning
	-- across it (Storm), diamonds set along the front walls (Diamond)
	if site.stone and kit.effects.studs then
		local z = site.front - site.gateDepth / 2 - 0.05
		local studs = {}
		for y = 1.2, GATE_CLEAR - 1, 1.4 do
			table.insert(studs, Vector3.new(-site.gateHalf - 0.35, y, z))
			table.insert(studs, Vector3.new(site.gateHalf + 0.35, y, z))
		end
		for x = -site.gateHalf + 1, site.gateHalf - 1, 1.4 do
			table.insert(studs, Vector3.new(x, GATE_CLEAR + 0.35, z))
		end
		for _, at in studs do
			part(folder, {
				Name = "GateStud",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.6, 0.6, 0.6),
				CFrame = origin * CFrame.new(at),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(230, 245, 255),
			})
		end
	end
	if site.stone and kit.effects.gateGlyph then
		local y = (GATE_CLEAR + gateTop) / 2
		local face = origin
			* CFrame.lookAt(
				Vector3.new(0, y, site.front - site.gateDepth / 2 + 0.15),
				Vector3.new(0, y, site.front - 20)
			)
		glyph(folder, face, 2.4, kit.light, rng)
		light(anchor(folder, face * CFrame.new(0, 0, -1), "GlyphLight"), kit.light, 12, 1)
	end
	if site.stone and kit.effects.gateBolts then
		for _, y in { 4, 8 } do
			local z = site.front - site.gateDepth / 2 - 0.2
			arc(
				folder,
				origin * CFrame.new(-site.gateHalf + 0.5, y, z),
				origin * CFrame.new(site.gateHalf - 0.5, y + 1, z)
			)
		end
	end
	if site.stone and kit.effects.inlays then
		for _, run in site.runs do
			local a, b = run.a, run.b
			if math.abs(a.Z - site.front) > 1 or math.abs(b.Z - site.front) > 1 then
				continue -- the front walls only, as in the concept
			end
			local length = (b - a).Magnitude
			local outward = Vector3.new(0, 0, -1)
			for i = 1, math.floor(length / 5) do
				local spot = a + (b - a) * ((i - 0.5) / math.floor(length / 5))
				for _, y in { h * 0.25, h * 0.47 } do
					inlay(
						folder,
						origin
							* CFrame.lookAt(
								spot + outward * (t / 2 + 0.05) + Vector3.new(0, y, 0),
								spot + outward * 10 + Vector3.new(0, y, 0)
							),
						2.4
					)
				end
			end
		end
	end
	if kit.effects.carpet then
		local length = kit.carpetLength or 20
		local at = origin * CFrame.new(0, 0.08, gateFront - length / 2 + 1)
		part(folder, {
			Name = "Carpet",
			Size = Vector3.new(7, 0.15, length),
			CFrame = at,
			Material = Enum.Material.Fabric,
			Color = Color3.fromRGB(170, 20, 35),
		})
		for _, side in { -1, 1 } do
			part(folder, {
				Name = "CarpetTrim",
				Size = Vector3.new(0.5, 0.17, length),
				CFrame = at * CFrame.new(side * 3.3, 0, 0),
				Material = Enum.Material.Foil,
				Color = Color3.fromRGB(240, 195, 70),
			})
		end
	end

	-- Lanterns along the front and sides
	if kit.lantern and kit.lanternSize > 0 then
		local spots = {
			Vector3.new(-(site.gateHalf + 16), 0, site.front - 3.5),
			Vector3.new(site.gateHalf + 16, 0, site.front - 3.5),
			Vector3.new(-(site.halfW + 3.5), 0, (site.front + site.back) / 2),
			Vector3.new(site.halfW + 3.5, 0, (site.front + site.back) / 2),
		}
		for _, spot in spots do
			local base = origin * CFrame.lookAt(spot, spot + (spot - centre) * Vector3.new(1, 0, 1))
			local lantern = piece(folder, kit.lantern, base, kit.lanternSize)
			if lantern then
				light(anchor(folder, topOf(lantern), "LanternLight"), kit.light, 16, 1.3)
			end
		end
	end

	-- Big pieces behind the castle
	if kit.backdrop then
		for _, side in { -1, 1 } do
			local at = origin * CFrame.new(side * (site.halfW + 4), 0, site.back + 9)
			piece(
				folder,
				kit.backdrop,
				at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				if kit.id == "Ice" then 4 else 68
			)
		end
	end

	-- Above the keep
	if kit.overhead and kit.overheadSize > 0 then
		local model =
			piece(folder, kit.overhead, over * CFrame.new(0, -kit.overheadSize / 2, 0), kit.overheadSize)
		faceOut(model)
		if model then
			float(model, model:GetPivot(), 1.2, 0)
			light(anchor(model, model:GetBoundingBox(), "OverheadLight"), kit.light, 40, 1.8)
		end
	end
	if kit.effects.portal and kit.overheadSize > 0 then
		portal(folder, over * CFrame.new(0, 2, 0), kit.overheadSize, kit)
	end
	if kit.effects.stormCloud then
		stormCloud(folder, over * CFrame.new(0, 6, 0), 30)
	end

	if kit.effects.smoke and site.stone then
		for _, spot in
			{
				Vector3.new(-(site.halfW - 5), h + 1, site.front + 7),
				Vector3.new(site.halfW - 5, h + 1, site.front + 7),
				Vector3.new(-(site.halfW * 0.55), h + 1, site.back - 6),
				Vector3.new(site.halfW * 0.55, h + 1, site.back - 6),
			}
		do
			smoke(folder, origin * CFrame.new(spot))
		end
	end
	if kit.effects.rocks and kit.floater then
		-- Rocks drifting all round the castle
		for k = 1, 16 do
			local angle = k / 16 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
			local reach = rng:NextNumber(0.85, 1.25)
			local at = origin
				* CFrame.new(
					math.sin(angle) * (site.halfW + 8) * reach,
					rng:NextNumber(8, 34),
					centre.Z - math.cos(angle) * ((site.back - site.front) / 2 + 8) * reach
				)
				* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
			local model = piece(folder, kit.floater, at, rng:NextNumber(1.8, 3.6))
			if model then
				float(model, model:GetPivot(), 1, rng:NextNumber(0.1, 0.4))
			end
		end
	end
	if kit.effects.keepChains and site.stone then
		-- Glowing chains slung from each back tower's crown to the front one's
		for _, back in site.towers do
			local b = origin:PointToObjectSpace(back.base.Position)
			if b.Z <= centre.Z then
				continue
			end
			for _, front in site.towers do
				local f = origin:PointToObjectSpace(front.base.Position)
				if f.Z < centre.Z and math.sign(f.X) == math.sign(b.X) then
					chain(
						folder,
						(back.base * CFrame.new(0, back.height + 1, 0)).Position,
						(front.base * CFrame.new(0, front.height + 1, 0)).Position,
						8,
						kit.light,
						true
					)
				end
			end
		end
	end
	if kit.effects.keepCrystals and kit.floater then
		-- Crystals floating round the great crescent over the keep
		for k = 1, 8 do
			local angle = k / 8 * math.pi * 2
			local at = over * CFrame.new(math.sin(angle) * 14, -4 + (k % 3) * 3, math.cos(angle) * 6)
			local model = piece(folder, kit.floater, at, kit.floaterSize * 0.9)
			if model then
				float(model, model:GetPivot(), 0.8, rng:NextNumber(0.2, 0.5))
			end
		end
	end
	if kit.effects.mist then
		-- Round the outside of the walls, as in the concept (not over the courtyard)
		local depth = site.back - site.front
		for _, zone in
			{
				{ Vector3.new(0, 1.5, site.front - 6), Vector3.new(site.halfW * 2 + 20, 1, 8) },
				{ Vector3.new(0, 1.5, site.back + 6), Vector3.new(site.halfW * 2 + 20, 1, 8) },
				{ Vector3.new(-(site.halfW + 6), 1.5, centre.Z), Vector3.new(8, 1, depth) },
				{ Vector3.new(site.halfW + 6, 1.5, centre.Z), Vector3.new(8, 1, depth) },
			}
		do
			mist(folder, origin * CFrame.new(zone[1]), zone[2], kit.light)
		end
	end

	-- The air round the castle
	if kit.ambient then
		local zone = part(folder, {
			Name = "KitAir",
			Size = Vector3.new(site.halfW * 2 + 16, h + 20, site.back - site.front + 16),
			CFrame = origin * CFrame.new(0, (h + 20) / 2, centre.Z),
			Transparency = 1,
		})
		emitter(zone, kit.ambient)
	end
end

-- The keep (WorldService's floors), `pieces` being the keep parts that show: the
-- kit's growths on its battlements, and its touches on the arcades, walls and
-- floors as in the concepts (icicles and snow, ivy and moss, lava cracks, runes,
-- pearls, giant mushrooms).
-- A creature's display niche (WorldService): a piece of the theme at its foot,
-- and something crowning every other arch.
local function dressNiche(folder: Instance, kit: Kit, back: BasePart, rng: Random)
	local cf, size = back.CFrame, back.Size
	local slot = back:GetAttribute("Slot")
	local odd = typeof(slot) == "number" and slot % 2 == 1
	local set = kit.interior
	if set and #set.names > 0 then
		local side = if odd then -1 else 1
		local at = cf
			* CFrame.new(side * (size.X / 2 - 0.7), -size.Y / 2, -size.Z / 2 - 1.1)
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local model = piece(
			folder,
			set.names[rng:NextInteger(1, #set.names)],
			at,
			set.size * rng:NextNumber(0.85, 1.15)
		)
		tint(model, kit, rng)
	end
	local crown = kit.nicheCrown or kit.growth
	if crown and odd then
		-- The arch is a disc as wide as the back, centered on its top edge
		local top = (cf * CFrame.new(0, size.Y / 2 + size.X / 2 - 0.4, 0)).Position
		if kit.growthMode == "clusters" and crown == kit.growth then
			cluster(folder, kit, CFrame.lookAt(top, top + cf.LookVector), 0.45, rng, 3)
		else
			local model =
				piece(folder, crown, CFrame.new(top) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), 2.2)
			tint(model, kit, rng)
		end
	end
end

-- A floor of the keep (its slab): the theme's centerpiece at the back middle,
-- between the vault rooms, and lights hung on chains underneath, over the floor
-- below.
local function dressFloor(folder: Instance, kit: Kit, slab: BasePart, rng: Random)
	local cf, size = slab.CFrame, slab.Size
	local center = kit.centerpiece
	if center then
		local model = piece(
			folder,
			center.name,
			cf * CFrame.new(0, size.Y / 2, size.Z / 2 - 5) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			center.size
		)
		if model and center.glow then
			glow(folder, model, kit, 16)
		end
		if model and center.flame then
			CastleKits.flame(anchor(folder, topOf(model), "CenterFlame"), kit, 3, 16)
		end
	end
	local hang = kit.chandelier
	if hang then
		for _, x in { -11, 11 } do
			for _, side in { -1, 1 } do
				local top = cf * CFrame.new(x, -size.Y / 2, side * size.Z / 4)
				local drop, height = 2.6, 3.2
				chain(
					folder,
					top.Position,
					(top * CFrame.new(0.01, -drop, 0)).Position,
					0,
					Color3.fromRGB(70, 66, 72),
					false
				)
				local model = piece(folder, hang, top * CFrame.new(0, -drop - height, 0), height)
				if model then
					light(anchor(folder, topOf(model), "HangingLight"), kit.light, 16, 1.2)
				end
			end
		end
	end
end

function CastleKits.dressKeep(folder: Instance, kit: Kit, pieces: { BasePart })
	local rng = Random.new(#pieces * 7 + 3)
	if #pieces == 0 then
		return
	end
	local sum = Vector3.zero
	local topFloor: BasePart? = nil
	local slabs: { BasePart } = {}
	for _, p in pieces do
		sum += p.Position
		if p.Name == "Floor" then
			table.insert(slabs, p)
			if topFloor == nil or p.Position.Y > (topFloor :: BasePart).Position.Y then
				topFloor = p
			end
		end
	end
	local centre = sum / #pieces
	local merlon = 0
	for _, p in pieces do
		local cf, size = p.CFrame, p.Size
		if p.Name == "Merlon" then
			merlon += 1
			local mode = kit.growthMode or "clusters"
			if kit.growth and kit.growthSize > 0 and mode == "clusters" and merlon % 3 == 1 then
				-- Clusters leaning out over the keep's edge
				local out = (cf.Position - centre) * Vector3.new(1, 0, 1)
				local top = cf.Position + Vector3.new(0, size.Y / 2, 0)
				cluster(folder, kit, CFrame.lookAt(top, top + out.Unit), 0.9, rng, 3)
			elseif kit.growth and kit.growthSize > 0 and mode ~= "clusters" and merlon % 2 == 1 then
				growth(
					folder,
					kit,
					cf * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
					kit.growthSize * rng:NextNumber(0.7, 1),
					rng
				)
			end
			if kit.effects.snow then
				snowCap(folder, cf, size)
			end
		elseif p.Name == "ArchLintel" or p.Name == "ArchCap" then
			-- The arcade faces the gate (the plot's -Z)
			local out = cf.LookVector
			local a = (cf * CFrame.new(-size.X / 2 + 0.3, -size.Y / 2, -size.Z / 2 - 0.05)).Position
			local b = (cf * CFrame.new(size.X / 2 - 0.3, -size.Y / 2, -size.Z / 2 - 0.05)).Position
			if kit.effects.icicles then
				icicles(folder, a, b, out, rng)
			end
			if kit.effects.vines and p.Name == "ArchCap" then
				vines(folder, a, b, out, 7, rng)
			end
			if kit.effects.keepPearls and p.Name == "ArchLintel" then
				pearls(folder, a + Vector3.new(0, 0.2, 0), b + Vector3.new(0, 0.2, 0), out)
			end
			if kit.effects.snow and p.Name == "ArchCap" then
				snowCap(folder, cf, size)
			end
			if kit.effects.moss and p.Name == "ArchCap" then
				part(folder, {
					Name = "KeepMoss",
					Size = Vector3.new(size.X, 0.35, size.Z + 0.3),
					CFrame = cf * CFrame.new(0, size.Y / 2 + 0.12, 0),
					Material = Enum.Material.Grass,
					Color = IVY,
				})
			end
		elseif p.Name == "NicheBack" then
			dressNiche(folder, kit, p, rng)
		elseif p.Name == "VaultWall" and kit.growthMode == "clusters" and kit.growth and size.X < size.Z then
			-- A big cluster crowning each vault room (the concept's coral towers)
			local top = cf.Position + Vector3.new(0, size.Y / 2, 0)
			local out = (cf.Position - centre) * Vector3.new(1, 0, 1)
			cluster(folder, kit, CFrame.lookAt(top, top + out.Unit), 1.4, rng, 6)
		elseif
			p.Name == "Balustrade"
			and kit.growthMode == "clusters"
			and kit.growth
			and rng:NextNumber() < 0.45
		then
			-- Growing over the balconies' rails
			local top = (cf * CFrame.new(rng:NextNumber(-size.X / 3, size.X / 3), size.Y / 2, -size.Z / 2)).Position
			cluster(folder, kit, CFrame.lookAt(top, top + cf.LookVector), 0.6, rng, 2)
		elseif (p.Name == "ArchPillar" or p.Name == "FloorPost") and kit.effects.veins then
			local top = (cf * CFrame.new(0, size.Y / 2, -size.Z / 2 - 0.05)).Position
			veins(folder, top - cf.RightVector * 0.3, top + cf.RightVector * 0.3, cf.LookVector, size.Y, rng)
		elseif p.Name == "FloorWall" and (kit.effects.veins or kit.effects.runes or kit.effects.vines) then
			-- Its face away from the keep's middle
			local thinX = size.X < size.Z
			local axis = if thinX then cf.RightVector else cf.LookVector
			local out = if (cf.Position - centre):Dot(axis) >= 0 then axis else -axis
			local along = if thinX then cf.LookVector else cf.RightVector
			local half = (if thinX then size.Z else size.X) / 2 - 0.5
			local top = cf.Position
				+ out * ((if thinX then size.X else size.Z) / 2 + 0.05)
				+ Vector3.new(0, size.Y / 2, 0)
			local a, b = top - along * half, top + along * half
			if kit.effects.veins then
				veins(folder, a, b, out, size.Y, rng)
			end
			if kit.effects.runes then
				runeWall(folder, a, b, out, size.Y, kit, rng)
			end
			if kit.effects.vines then
				vines(folder, a, b, out, size.Y, rng)
			end
		elseif p.Name == "Floor" and (kit.effects.snow or kit.effects.moss) then
			-- Snow drifts (Ice) or moss (Moss) lying on the floor
			for _ = 1, 4 do
				patch(
					folder,
					cf
						* CFrame.new(
							rng:NextNumber(-size.X / 2 + 3, size.X / 2 - 3),
							size.Y / 2 + 0.05,
							rng:NextNumber(-size.Z / 2 + 3, size.Z / 2 - 3)
						),
					rng:NextNumber(3, 6),
					if kit.effects.snow then Enum.Material.Snow else Enum.Material.Grass,
					if kit.effects.snow then SNOW else IVY,
					if kit.effects.snow then "Snow" else "KeepMoss"
				)
			end
		end
	end
	for _, slab in slabs do
		dressFloor(folder, kit, slab, rng)
	end
	-- Giant glowing mushrooms on the top floor's front corners (Moss)
	local feet = kit.feet
	if feet and feet.glow and topFloor then
		local cf, size = topFloor.CFrame, topFloor.Size
		for _, side in { -1, 1 } do
			local at = cf * CFrame.new(side * (size.X / 2 - 2.5), size.Y / 2, -size.Z / 2 + 2.5)
			local model =
				piece(folder, feet.name, at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), feet.size * 0.6)
			glow(folder, model, kit, 16)
		end
	end
end

return CastleKits

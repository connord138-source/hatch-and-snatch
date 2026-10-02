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
-- lightning, KitSpin turns the portal, KitFlicker flashes the storm light.
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
	effects: { [string]: boolean },
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local KITS: { [string]: Kit } = {
	Moss = {
		id = "Moss",
		flame = Color3.fromRGB(140, 255, 120),
		flame2 = Color3.fromRGB(40, 160, 70),
		light = Color3.fromRGB(120, 255, 120),
		capScale = 0,
		capColor = Color3.fromRGB(55, 120, 60),
		growth = "MossMushrooms",
		growthSize = 4.6,
		growthEvery = 7,
		growthGlow = true,
		statue = "MossMushrooms", -- giant glowing mushrooms flank the gate
		base = "MossRoots",
		baseSize = 7,
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
		effects = { vines = true, lilies = true },
	},
	Coral = {
		id = "Coral",
		flame = Color3.fromRGB(90, 255, 230),
		flame2 = Color3.fromRGB(20, 170, 190),
		light = Color3.fromRGB(80, 255, 225),
		cap = "CoralShellSpire",
		capScale = 3.2,
		capColor = Color3.fromRGB(120, 200, 180),
		growth = "CoralBranches",
		growthAlts = { "CoralFan", "CoralTubes" },
		growthSize = 6,
		growthEvery = 5,
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
		lantern = "CoralPearlLantern",
		lanternSize = 5,
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
		plinth = { material = Enum.Material.Slate, color = Color3.fromRGB(96, 122, 140), height = 0.4 },
		pool = { material = Enum.Material.Glass, color = Color3.fromRGB(40, 210, 205), glow = true, size = 7 },
		effects = { pearls = true },
	},
	Fire = {
		id = "Fire",
		flame = Color3.fromRGB(255, 150, 50),
		flame2 = Color3.fromRGB(255, 60, 20),
		light = Color3.fromRGB(255, 130, 50),
		cap = "FireSpire",
		capScale = 2.8,
		capColor = Color3.fromRGB(40, 36, 40),
		growth = "FireObsidianSpikes",
		growthSize = 3.6,
		growthEvery = 6,
		base = "FireLavaRock",
		baseSize = 4.5,
		brazier = "FireSkullBrazier",
		gate = "FireDragonGate",
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
			color = Color3.fromRGB(240, 80, 15),
			glow = true,
			size = 9,
			crust = true, -- dark rock floating on the lava, as in the concept
		},
		effects = { lavaFalls = true, veins = true },
	},
	Ice = {
		id = "Ice",
		flame = Color3.fromRGB(170, 230, 255),
		flame2 = Color3.fromRGB(80, 160, 255),
		light = Color3.fromRGB(150, 215, 255),
		cap = "IceCrystalSpire",
		capScale = 3.6,
		capColor = Color3.fromRGB(190, 230, 255),
		growth = "IceCrystalCluster",
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
		ground = { material = Enum.Material.Snow, color = Color3.fromRGB(235, 242, 250) },
		pool = { material = Enum.Material.Ice, color = Color3.fromRGB(170, 215, 245), glow = false, size = 8 },
		effects = { icicles = true },
	},
	Storm = {
		id = "Storm",
		flame = Color3.fromRGB(150, 220, 255),
		flame2 = Color3.fromRGB(255, 240, 120),
		light = Color3.fromRGB(170, 210, 255),
		cap = "StormTeslaSpire",
		capScale = 3.4,
		capColor = Color3.fromRGB(170, 110, 60),
		growth = "StormLightningRod",
		growthSize = 4,
		growthEvery = 18,
		brazier = "StormPlasmaBrazier",
		gateMode = "crest",
		floater = "StormThunderStone",
		floaterSize = 3.4,
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
		effects = { arcs = true, stormCloud = true },
	},
	Moon = {
		id = "Moon",
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
		effects = { mist = true },
	},
	Golden = {
		id = "Golden",
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
		effects = { carpet = true },
	},
	Diamond = {
		id = "Diamond",
		flame = Color3.fromRGB(235, 248, 255),
		flame2 = Color3.fromRGB(170, 220, 255),
		light = Color3.fromRGB(235, 245, 255),
		cap = "DiamondCrown",
		capScale = 2.4,
		capColor = Color3.fromRGB(225, 245, 255),
		growth = "DiamondCluster",
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
		effects = {},
	},
	Void = {
		id = "Void",
		flame = Color3.fromRGB(190, 110, 255),
		flame2 = Color3.fromRGB(90, 30, 200),
		light = Color3.fromRGB(165, 90, 255),
		cap = "VoidCrystals",
		capScale = 2.8,
		capColor = Color3.fromRGB(35, 25, 50),
		growth = "VoidCrystals",
		growthSize = 3.8,
		growthEvery = 7,
		growthGlow = true,
		base = "VoidRunePillar",
		baseSize = 7,
		brazier = "VoidBrazier",
		gateMode = "crest",
		floater = "VoidShards",
		floaterSize = 4,
		overhead = "VoidPortal",
		overheadSize = 16,
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
		effects = { portal = true, runes = true },
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

local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
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
local function tint(model: Model?, kit: Kit, rng: Random)
	local tints = kit.growthTints
	if model == nil or tints == nil or #tints == 0 then
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

-- A growth from the kit (one of its shapes), tinted.
local function growth(folder: Instance, kit: Kit, at: CFrame, height: number, rng: Random): Model?
	local name = kit.growth
	local alts = kit.growthAlts
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

--------------------------------------------------------------------------------
-- Tower caps
--------------------------------------------------------------------------------

-- Replaces a tower's roof: the kit's cap on `roofBase` (the top of the tower's
-- crown), sized to the tower. Returns the tip, or nil when this kit keeps roofs.
function CastleKits.cap(folder: Instance, kit: Kit, roofBase: CFrame, radius: number): CFrame?
	if kit.capScale <= 0 then
		return nil
	end
	local height = radius * kit.capScale
	local model = piece(folder, kit.cap, roofBase, height)
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
	local model = piece(folder, kit.finial, tip * CFrame.new(0, -0.6, 0), radius * 1.5)
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
	for i = 0, math.floor(length / 6) do
		local x = i * 6 + rng:NextNumber(0.5, 4)
		if x > length - 1 then
			break
		end
		local at = a + along * x + Vector3.new(0, -height + rng:NextNumber(0.5, 2), 0)
		for _ = 1, rng:NextInteger(3, 5) do
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

-- Glowing rune slits along a wall face.
local function runes(folder: Instance, a: Vector3, b: Vector3, outward: Vector3, height: number, kit: Kit)
	local length = (b - a).Magnitude
	for i = 1, math.floor(length / 6) - 1 do
		local at = a + (b - a).Unit * (i * 6) + Vector3.new(0, -height * 0.55, 0)
		part(folder, {
			Name = "Rune",
			Size = Vector3.new(0.5, 2.6, 0.15),
			CFrame = CFrame.lookAt(at, at + outward) * CFrame.new(0, 0, -0.1),
			Material = Enum.Material.Neon,
			Color = kit.light,
		})
		part(folder, {
			Name = "Rune",
			Size = Vector3.new(1.4, 0.4, 0.15),
			CFrame = CFrame.lookAt(at, at + outward)
				* CFrame.new(0, 0.5, -0.1)
				* CFrame.Angles(0, 0, math.rad(35)),
			Material = Enum.Material.Neon,
			Color = kit.light,
		})
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

-- The void portal: a ring of violet light that turns, with a swirl inside.
local function portal(folder: Instance, at: CFrame, size: number, kit: Kit)
	local ring = Instance.new("Model")
	ring.Name = "VoidPortalRing"
	local segments = 18
	local radius = size / 2
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		part(ring, {
			Name = "PortalRing",
			Size = Vector3.new(radius * 2 * math.pi / segments + 0.2, 0.9, 0.9),
			CFrame = at * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0),
			Material = Enum.Material.Neon,
			Color = kit.light,
		})
	end
	local core = part(ring, {
		Name = "PortalCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, size * 0.92, size * 0.92),
		CFrame = at * CFrame.Angles(0, math.rad(90), 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(40, 10, 80),
		Transparency = 0.25,
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
	fog.Rate = 14
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
	towers: { TowerSpot },
	runs: { { a: Vector3, b: Vector3 } }, -- plot-local wall runs on the ground
}

local GATE_CLEAR = 12

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
			local count = math.max(1, math.floor(length / kit.growthEvery))
			for i = 1, count do
				local along = (i - 0.5) / count
				local spot = a + (b - a) * along
				-- Keep the gate and the tower corners clear
				if math.abs(spot.X) < site.gateHalf + 6 and math.abs(spot.Z - site.front) < 1 then
					continue
				end
				local at = origin
					* CFrame.lookAt(spot + outward * (t * 0.25), spot + outward * 2)
					* CFrame.new(0, h + 0.6, 0)
					* CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
				local model = growth(folder, kit, at, kit.growthSize * rng:NextNumber(0.85, 1.2), rng)
				if kit.growthGlow and i % 4 == 1 then
					glow(folder, model, kit, 10)
				end
			end
		end
		if site.stone and kit.plaque then
			for i = 1, math.max(1, math.floor(length / 16)) do
				local spot = a + (b - a) * ((i - 0.5) / math.max(1, math.floor(length / 16)))
				if math.abs(spot.X) < site.gateHalf + 6 and math.abs(spot.Z - site.front) < 1 then
					continue
				end
				local at = origin
					* CFrame.lookAt(spot + outward * (t / 2 + 0.2), spot + outward * 4)
					* CFrame.new(0, h * 0.55, 0)
				piece(folder, kit.plaque, at, 2.6)
			end
		end
		if site.stone and kit.effects.icicles then
			icicles(folder, edgeA, edgeB, worldOut, rng)
		end
		if site.stone and kit.effects.vines then
			vines(folder, edgeA, edgeB, worldOut, h, rng)
		end
		if site.stone and kit.effects.runes then
			runes(folder, edgeA, edgeB, worldOut, h, kit)
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
				light(orb, kit.light, 14, 1.1)
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
			part(folder, {
				Name = "KitGround",
				Size = strip[2],
				CFrame = origin * CFrame.new(strip[1] + Vector3.new(0, 0.07, 0)),
				Material = ground.material,
				Color = ground.color,
			})
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
				if pool.crust then
					for _ = 1, 3 do
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
			-- A ring of growths round the crown, sprouting about the cap
			for k = 1, 6 do
				local angle = (k / 6) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
				local at = tower.base
					* CFrame.new(
						math.sin(angle) * (tower.radius + 0.3),
						tower.height + 1.4,
						-math.cos(angle) * (tower.radius + 0.3)
					)
				growth(
					folder,
					kit,
					at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
					kit.growthSize * rng:NextNumber(0.75, 1.05),
					rng
				)
			end
		end
	end
	for _, tower in site.towers do
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
			for k = 1, 2 do
				local angle = (k / 2) * math.pi * 2 + rng:NextNumber(0, 1)
				local at = tower.tip
					* CFrame.new(
						math.cos(angle) * (tower.radius + 3),
						-tower.radius * 0.8 - k * 1.5,
						math.sin(angle) * (tower.radius + 3)
					)
				local model = piece(folder, kit.floater, at, kit.floaterSize)
				if model then
					float(model, model:GetPivot(), 0.8, rng:NextNumber(0.2, 0.5))
					light(anchor(model, model:GetBoundingBox(), "FloatLight"), kit.light, 10, 0.8)
				end
			end
		end
	end

	-- Lightning arcing round the tower tips
	if kit.effects.arcs and #site.towers >= 2 then
		local order = table.clone(site.towers)
		table.sort(order, function(p: TowerSpot, q: TowerSpot)
			local pa =
				math.atan2(p.base.Position.Z - (origin * centre).Z, p.base.Position.X - (origin * centre).X)
			local qa =
				math.atan2(q.base.Position.Z - (origin * centre).Z, q.base.Position.X - (origin * centre).X)
			return pa < qa
		end)
		for i = 1, #order do
			local nextTower = order[i % #order + 1]
			if #order > 2 or i == 1 then
				arc(folder, order[i].tip, nextTower.tip)
			end
		end
	end

	-- At the gate: braziers, guardian statues and the ornament
	local gateFront = site.front - site.gateDepth / 2
	local gateTop = site.gateTop or (GATE_CLEAR + 3.5)
	for _, side in { -1, 1 } do
		local x = side * (site.gateHalf + 8)
		local base = origin
			* CFrame.lookAt(Vector3.new(x, 0, site.front - 8.5), Vector3.new(x, 0, site.front - 20))
		local brazier = piece(folder, kit.brazier, base, 5)
		if brazier then
			local flameAt = anchor(folder, topOf(brazier), "BrazierFlame")
			CastleKits.flame(flameAt, kit, 3.5, 18)
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
			local at = origin * CFrame.new(side * (site.gateHalf + 4.35), gateTop, site.front)
			growth(folder, kit, at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), kit.growthSize * 0.9, rng)
		end
	end
	-- Twin braziers on top of the gatehouse
	if site.stone and kit.brazier then
		for _, side in { -1, 1 } do
			local at = origin
				* CFrame.lookAt(
					Vector3.new(side * (site.gateHalf + 2.25), gateTop, site.front),
					Vector3.new(side * (site.gateHalf + 2.25), gateTop, site.front - 10)
				)
			local top = piece(folder, kit.brazier, at, 6.5)
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
				local span = site.gateHalf * 2 + 6
				-- Whichever way the model was imported, its long side spans the gate
				local extents = arch:GetExtentsSize()
				local turned = extents.Z > extents.X
				Props.place(
					arch,
					face
						* CFrame.new(0, (GATE_CLEAR + 5) / 2, 0)
						* (if turned then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity),
					if turned
						then Vector3.new(3, GATE_CLEAR + 5, span)
						else Vector3.new(span, GATE_CLEAR + 5, 3)
				)
				arch.Parent = folder
			end
		else
			faceOut(piece(folder, kit.gate, face * CFrame.new(0, GATE_CLEAR + 0.5, -0.6), 6))
		end
	end
	if kit.effects.carpet then
		local length = 20
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
			local at = origin * CFrame.new(side * (site.halfW + 7), 0, site.back + 7)
			piece(
				folder,
				kit.backdrop,
				at * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				if kit.id == "Ice" then 4 else 46
			)
		end
	end

	-- Above the keep
	local over = origin
		* CFrame.lookAt(Vector3.new(0, 0, centre.Z), Vector3.new(0, 0, site.front - 40))
		* CFrame.new(0, h + 52, 0)
	if kit.overhead and kit.overheadSize > 0 then
		local model =
			piece(folder, kit.overhead, over * CFrame.new(0, -kit.overheadSize / 2, 0), kit.overheadSize)
		faceOut(model)
		if model then
			float(model, model:GetPivot(), 1.2, 0)
			light(anchor(model, model:GetBoundingBox(), "OverheadLight"), kit.light, 40, 1.8)
		elseif kit.effects.portal then
			portal(folder, over, kit.overheadSize, kit)
		end
	end
	if kit.effects.stormCloud then
		stormCloud(folder, over * CFrame.new(0, 6, 0), 30)
	end

	if kit.effects.mist then
		mist(
			folder,
			origin * CFrame.new(0, 1.5, centre.Z),
			Vector3.new(site.halfW * 2 + 20, 1, site.back - site.front + 20),
			kit.light
		)
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

-- The keep (WorldService's floors): growths on its battlements and pillar tops,
-- `tops` being the top middles of the keep pieces that show.
function CastleKits.dressKeep(folder: Instance, kit: Kit, tops: { CFrame })
	if kit.growth == nil or kit.growthSize <= 0 then
		return
	end
	local rng = Random.new(#tops * 7 + 3)
	for i, top in tops do
		if i % 2 == 1 then
			growth(
				folder,
				kit,
				top * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				kit.growthSize * rng:NextNumber(0.7, 1),
				rng
			)
		end
	end
end

return CastleKits

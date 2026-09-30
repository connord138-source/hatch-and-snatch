--!strict
-- Hero set pieces for the biome zones: two or three big landmarks per zone (a
-- hollow stump, a tide-pool arch, a lava vent ...). Each uses its imported model
-- (ReplicatedStorage.WorldProps.<Name>, see Props.luau) when there is one, and a
-- stand-in built from parts otherwise. Lights, particles and the storm crag's
-- lightning are added either way. WorldService decides where they stand.
-- Also here: part-built zone decor (dead trees, scorch marks) and the storm
-- over Storm Peaks (SetPieces.stormSky).
local Lighting = game:GetService("Lighting")

local Props = require(script.Parent.Props)

local SetPieces = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

type Builder = (model: Model, frame: CFrame, s: number, rng: Random) -> ()
type Effects = (model: Model, box: CFrame, size: Vector3) -> ()
type Spec = {
	size: Vector3, -- box an imported model is fitted into: X across, Y up, Z front to back
	radius: number, -- how far other decor keeps away
	walkable: boolean?, -- no collision (mushrooms)
	span: boolean?, -- an arch: its long side goes across, so the opening faces the look direction
	-- How an imported model fills the box (default: as big as fits inside it).
	-- "height": full box height at the model's own proportions (tall landmarks
	-- whose model is deeper than the box would otherwise come out short).
	-- "footprint": fills the box across, then flattens to the box height.
	fit: ("height" | "footprint")?,
	build: Builder, -- the stand-in when no model is imported
	effects: Effects?,
}

local function part(props: { [string]: any }, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Anchored = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- An ellipsoid: a block drawn as a stretched sphere (collision stays a box).
local function blob(props: { [string]: any }): BasePart
	local p = part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A pointed crystal: four wedges meeting in a cross-shaped spike, standing on `base`.
local function shard(base: CFrame, width: number, height: number, props: { [string]: any }, parent: Instance)
	for turn = 0, 3 do
		local spin = base * CFrame.Angles(0, turn * math.pi / 2, 0)
		local p = part(props, "WedgePart")
		p.Size = Vector3.new(width * 0.35, height, width / 2)
		p.CFrame = spin * CFrame.new(0, height / 2, -width / 4)
		p.Parent = parent
	end
end

local function mushroom(base: CFrame, height: number, cap: number, parent: Instance)
	part({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, cap * 0.35, cap * 0.35),
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(225, 220, 200),
		Parent = parent,
	})
	blob({
		Name = "Cap",
		Size = Vector3.new(cap * 2, cap * 0.8, cap * 2),
		CFrame = base * CFrame.new(0, height, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(90, 225, 205),
		Parent = parent,
	})
end

local function light(parent: BasePart, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	return l
end

local function emitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0.6
	e.Shape = Enum.ParticleEmitterShape.Box
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- An invisible anchor for lights and particles.
local function anchor(model: Model, cframe: CFrame, size: Vector3): BasePart
	return part({
		Name = "FxAnchor",
		Size = size,
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
end

local function fade(from: number, to: number): NumberSequence
	return NumberSequence.new(from, to)
end

-- A jagged bolt from the storm cloud (SetPieces.stormSky) down to `tip`, flashed
-- twice, then removed.
local function strike(tip: Vector3, model: Model, flash: PointLight, rng: Random)
	local bolt = Instance.new("Folder")
	bolt.Name = "Bolt"
	local points = { tip + Vector3.new(rng:NextNumber(-6, 6), 30, rng:NextNumber(-6, 6)) }
	for i = 1, 6 do
		local t = i / 7
		local along = points[1]:Lerp(tip, t)
		table.insert(points, along + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
	end
	table.insert(points, tip)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		part({
			Name = "Segment",
			Size = Vector3.new(0.6, 0.6, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(175, 215, 255),
			CanCollide = false,
			CastShadow = false,
			Parent = bolt,
		})
	end
	bolt.Parent = model
	flash.Brightness = 6
	task.wait(0.08)
	bolt.Parent = nil
	flash.Brightness = 0.5
	task.wait(0.06)
	bolt.Parent = model
	flash.Brightness = 8
	task.wait(0.12)
	bolt:Destroy()
	flash.Brightness = 0.5
end

local SPECS: { [string]: Spec } = {}

SPECS.HollowStump = {
	size = Vector3.new(14, 13, 14),
	radius = 8,
	build = function(model, frame, s, rng)
		local radius = 5.5 * s
		for i = 0, 11 do
			local angle = i * math.pi / 6
			if i ~= 0 then -- the gap at the front is the way in
				local height = 11 * s * rng:NextNumber(0.7, 1.05)
				part({
					Name = "Bark",
					Size = Vector3.new(3.4 * s, height, 1.8 * s),
					CFrame = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, height / 2, -radius),
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(105, 74, 48):Lerp(Color3.fromRGB(80, 58, 40), rng:NextNumber()),
					Parent = model,
				})
				if i % 3 == 1 then
					part({
						Name = "Moss",
						Size = Vector3.new(3.6 * s, 0.5 * s, 2.2 * s),
						CFrame = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, height, -radius),
						Material = Enum.Material.LeafyGrass,
						Color = Color3.fromRGB(100, 150, 70),
						Parent = model,
					})
				end
			end
			if i % 2 == 1 then
				part({
					Name = "Root",
					Size = Vector3.new(2 * s, 2.6 * s, 4 * s),
					CFrame = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 1.3 * s, -(radius + 2.4 * s)),
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(95, 68, 45),
					Parent = model,
				}, "WedgePart")
			end
		end
		mushroom(frame * CFrame.new(1.5 * s, 0, 1 * s), 1.8 * s, 0.9 * s, model)
		mushroom(frame * CFrame.new(-1.8 * s, 0, 2 * s), 1.2 * s, 0.7 * s, model)
	end,
	effects = function(model, box, size)
		local glow = anchor(model, box * CFrame.new(0, -size.Y / 2 + 2, 0), Vector3.new(1, 1, 1))
		light(glow, Color3.fromRGB(90, 225, 205), 0.8, 10)
	end,
}

SPECS.GiantGlowcap = {
	size = Vector3.new(6, 7, 6),
	radius = 3.5,
	walkable = true,
	build = function(model, frame, s)
		mushroom(frame, 6 * s, 2.2 * s, model)
		mushroom(frame * CFrame.new(1.8 * s, 0, 1.2 * s), 4 * s, 1.5 * s, model)
		mushroom(frame * CFrame.new(-1.5 * s, 0, 1.4 * s), 2.6 * s, 1.1 * s, model)
	end,
	effects = function(model, box, size)
		light(
			anchor(model, box * CFrame.new(0, size.Y / 2, 0), Vector3.new(1, 1, 1)),
			Color3.fromRGB(90, 225, 205),
			1,
			12
		)
	end,
}

local function archBuilder(material: Enum.Material, color: Color3, icy: boolean): Builder
	return function(model, frame, s, rng)
		local half = 8 * s -- half the opening
		for _, side in { -1, 1 } do
			part({
				Name = "Leg",
				Size = Vector3.new(4.5 * s, 12 * s, 5 * s),
				CFrame = frame
					* CFrame.new(side * (half + 2 * s), 6 * s, 0)
					* CFrame.Angles(0, 0, side * math.rad(6)),
				Material = material,
				Color = color,
				Transparency = if icy then 0.15 else 0,
				Parent = model,
			})
		end
		part({
			Name = "Span",
			Size = Vector3.new((half + 5 * s) * 2, 3.6 * s, 5.5 * s),
			CFrame = frame * CFrame.new(0, 13 * s, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))),
			Material = material,
			Color = color,
			Transparency = if icy then 0.15 else 0,
			Parent = model,
		})
		part({
			Name = "Crest",
			Size = Vector3.new(half * 1.4, 2.2 * s, 4.5 * s),
			CFrame = frame * CFrame.new(rng:NextNumber(-2, 2) * s, 15.6 * s, 0),
			Material = if icy then Enum.Material.Snow else material,
			Color = if icy then Color3.fromRGB(245, 250, 255) else color,
			Parent = model,
		})
		for i = 1, 6 do
			local x = rng:NextNumber(-half, half)
			if icy then
				shard(
					frame
						* CFrame.new(x, 11.2 * s, rng:NextNumber(-1.5, 1.5) * s)
						* CFrame.Angles(math.pi, 0, 0),
					0.9 * s,
					rng:NextNumber(1.5, 3.2) * s,
					{
						Material = Enum.Material.Ice,
						Color = Color3.fromRGB(200, 235, 255),
						CanCollide = false,
					},
					model
				)
			else
				local side = if i % 2 == 0 then -1 else 1
				blob({
					Name = "Coral",
					Size = Vector3.new(1.6, 1.2, 1.6) * s * rng:NextNumber(0.7, 1.3),
					CFrame = frame * CFrame.new(side * (half + 2 * s), rng:NextNumber(1, 10) * s, -2.6 * s),
					Material = Enum.Material.SmoothPlastic,
					Color = if i % 3 == 0
						then Color3.fromRGB(255, 150, 80)
						else Color3.fromRGB(255, 115, 140),
					CanCollide = false,
					Parent = model,
				})
			end
		end
	end
end

SPECS.TideArch = {
	size = Vector3.new(26, 17, 12),
	radius = 13,
	span = true,
	build = archBuilder(Enum.Material.Sandstone, Color3.fromRGB(205, 175, 135), false),
}

SPECS.IceArch = {
	size = Vector3.new(26, 17, 12),
	radius = 13,
	span = true,
	build = archBuilder(Enum.Material.Ice, Color3.fromRGB(170, 215, 240), true),
}

SPECS.GiantClam = {
	size = Vector3.new(13, 9, 12),
	radius = 7,
	build = function(model, frame, s)
		blob({
			Name = "LowerShell",
			Size = Vector3.new(12, 3.5, 10) * s,
			CFrame = frame * CFrame.new(0, 1.75 * s, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(235, 220, 190),
			Parent = model,
		})
		local hinge = frame * CFrame.new(0, 3 * s, 5 * s)
		blob({
			Name = "UpperShell",
			Size = Vector3.new(12, 3.5, 10) * s,
			CFrame = hinge * CFrame.Angles(math.rad(38), 0, 0) * CFrame.new(0, 0.5 * s, -5 * s),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(140, 200, 205),
			Parent = model,
		})
		part({
			Name = "Pearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.6, 2.6) * s,
			CFrame = frame * CFrame.new(0, 3.6 * s, -0.5 * s),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.25,
			Color = Color3.fromRGB(250, 248, 255),
			Parent = model,
		})
	end,
	effects = function(model, box, size)
		light(anchor(model, box, Vector3.new(1, 1, 1)), Color3.fromRGB(235, 240, 255), 1.2, 12)
	end,
}

SPECS.LavaVent = {
	size = Vector3.new(12, 11, 12),
	radius = 7.5,
	build = function(model, frame, s)
		local y = 0
		for _, tier in { { 6, 3 }, { 4.5, 2.6 }, { 3.2, 2.2 } } do
			local radius, height = tier[1] * s, tier[2] * s
			part({
				Name = "Cone",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, radius * 2, radius * 2),
				CFrame = frame * CFrame.new(0, y + height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Basalt,
				Color = Color3.fromRGB(48, 42, 42),
				Parent = model,
			})
			y += height
		end
		part({
			Name = "Crater",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4.6 * s, 4.6 * s),
			CFrame = frame * CFrame.new(0, y + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 120, 30),
			CanCollide = false,
			Parent = model,
		})
		for i = 0, 2 do
			part({
				Name = "LavaFlow",
				Size = Vector3.new(0.7 * s, 6 * s, 0.3),
				CFrame = frame
					* CFrame.Angles(0, i * 2.1, 0)
					* CFrame.new(0, 4 * s, -4.3 * s)
					* CFrame.Angles(math.rad(-38), 0, 0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 110, 25),
				CanCollide = false,
				Parent = model,
			})
		end
	end,
	effects = function(model, box, size)
		local top = anchor(model, box * CFrame.new(0, size.Y / 2, 0), Vector3.new(3, 0.5, 3))
		light(top, Color3.fromRGB(255, 120, 40), 2, 22)
		emitter(top, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(70, 60, 60), Color3.fromRGB(35, 32, 32)),
			LightEmission = 0,
			Rate = 5,
			Lifetime = NumberRange.new(4, 6),
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(12, 12),
			Size = NumberSequence.new(3, 9),
			Transparency = fade(0.35, 1),
		})
		emitter(top, {
			Texture = FIRE,
			Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 70, 20)),
			Rate = 12,
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, -12, 0),
			Size = NumberSequence.new(0.5, 0),
			Transparency = fade(0, 0.4),
		})
	end,
}

SPECS.ObsidianSpikes = {
	size = Vector3.new(11, 12, 11),
	radius = 7,
	build = function(model, frame, s, rng)
		blob({
			Name = "Mound",
			Size = Vector3.new(9, 3, 9) * s,
			CFrame = frame,
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(45, 40, 42),
			Parent = model,
		})
		for i = 1, 7 do
			local angle = i * 0.9
			local out = if i == 1 then 0 else rng:NextNumber(1.2, 3.4) * s
			shard(
				frame
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, 0.6 * s, -out)
					* CFrame.Angles(math.rad(-out * 4), 0, math.rad(rng:NextNumber(-8, 8))),
				rng:NextNumber(1.6, 2.6) * s,
				(if i == 1 then 11 else rng:NextNumber(4, 8.5)) * s,
				{ Material = Enum.Material.Glass, Color = Color3.fromRGB(28, 22, 38), Reflectance = 0.15 },
				model
			)
		end
	end,
	effects = function(model, box, size)
		light(
			anchor(model, box * CFrame.new(0, -size.Y / 2 + 1, 0), Vector3.new(1, 1, 1)),
			Color3.fromRGB(255, 110, 40),
			1.2,
			12
		)
	end,
}

SPECS.FrozenBoulder = {
	size = Vector3.new(11, 11, 11),
	radius = 7,
	build = function(model, frame, s, rng)
		part({
			Name = "Rock",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(6.5, 6.5, 6.5) * s,
			CFrame = frame * CFrame.new(0, 4.2 * s, 0),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(95, 95, 108),
			CanCollide = false,
			Parent = model,
		})
		blob({
			Name = "Ice",
			Size = Vector3.new(10, 9, 9.5) * s,
			CFrame = frame * CFrame.new(0, 4.3 * s, 0),
			Material = Enum.Material.Ice,
			Color = Color3.fromRGB(180, 225, 250),
			Transparency = 0.4,
			Parent = model,
		})
		blob({
			Name = "Snow",
			Size = Vector3.new(7, 1.6, 6.5) * s,
			CFrame = frame * CFrame.new(0.4 * s, 8.5 * s, 0),
			Material = Enum.Material.Snow,
			Color = Color3.fromRGB(245, 250, 255),
			Parent = model,
		})
		for i = 1, 3 do
			shard(
				frame
					* CFrame.Angles(0, i * 2.2, 0)
					* CFrame.new(0, 3 * s, -3.8 * s)
					* CFrame.Angles(math.rad(-50), 0, 0),
				1.2 * s,
				rng:NextNumber(2, 3.5) * s,
				{ Material = Enum.Material.Ice, Color = Color3.fromRGB(200, 235, 255), CanCollide = false },
				model
			)
		end
	end,
}

SPECS.LightningCrag = {
	size = Vector3.new(9, 20, 9),
	radius = 6.5,
	fit = "height",
	build = function(model, frame, s)
		local rocks = {
			{ size = Vector3.new(8, 5, 7), at = Vector3.new(0, 2.5, 0), tilt = 0 },
			{ size = Vector3.new(6, 4.5, 5.5), at = Vector3.new(0.5, 7, 0.3), tilt = 8 },
			{ size = Vector3.new(4, 3.5, 4), at = Vector3.new(-0.2, 10.8, 0), tilt = -6 },
		}
		for i, rock in rocks do
			part({
				Name = "Crag",
				Size = rock.size * s,
				CFrame = frame * CFrame.new(rock.at * s) * CFrame.Angles(0, i * 0.7, math.rad(rock.tilt)),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(88, 92, 108),
				Parent = model,
			})
		end
		part({
			Name = "Rod",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(7.5 * s, 0.5, 0.5),
			CFrame = frame * CFrame.new(0, 16.2 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.CorrodedMetal,
			Color = Color3.fromRGB(120, 85, 60),
			Parent = model,
		})
		part({
			Name = "Tip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = frame * CFrame.new(0, 20 * s, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(150, 205, 255),
			CanCollide = false,
			Parent = model,
		})
	end,
	effects = function(model, box, size)
		local tipAt = box * CFrame.new(0, size.Y / 2, 0)
		local flash =
			light(anchor(model, tipAt, Vector3.new(1, 1, 1)), Color3.fromRGB(170, 210, 255), 0.5, 40)
		task.spawn(function()
			local rng = Random.new()
			while model.Parent do
				task.wait(rng:NextNumber(6, 14))
				if model.Parent then
					strike(tipAt.Position, model, flash, rng)
				end
			end
		end)
	end,
}

SPECS.WindSpire = {
	size = Vector3.new(9, 17, 7),
	radius = 6,
	fit = "height",
	build = function(model, frame, s)
		local stack = {
			{ 5, 4, 0, 2, 0 },
			{ 4.4, 4, 0.8, 5.8, -8 },
			{ 3.8, 4, 2, 9.4, -16 },
			{ 3.2, 3.6, 3.6, 12.6, -24 },
			{ 2.4, 3, 5.4, 15.2, -32 },
		}
		for _, b in stack do
			part({
				Name = "Spire",
				Size = Vector3.new(b[1], b[2], b[1]) * s,
				CFrame = frame * CFrame.new(b[3] * s, b[4] * s, 0) * CFrame.Angles(0, 0, math.rad(b[5])),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(105, 112, 132),
				Parent = model,
			})
		end
	end,
	effects = function(model, box, size)
		local gust = anchor(model, box, Vector3.new(4, size.Y, 4))
		emitter(gust, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(235, 240, 250)),
			LightEmission = 0.2,
			Rate = 3,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(1, 2),
			Acceleration = box.RightVector * 14,
			Size = NumberSequence.new(1.2, 3),
			Transparency = fade(0.7, 1),
		})
	end,
}

-- Zone decor (WorldService scatters these like imported props).

-- A dead tree bent by the storm wind: a charred trunk leaning downwind (the frame's
-- look direction) with a few bare branches, and on some a glowing lightning scar.
SPECS.DeadTree = {
	size = Vector3.new(8, 13, 8),
	radius = 3,
	build = function(model, frame, s, rng)
		local bark = Color3.fromRGB(66, 60, 57):Lerp(Color3.fromRGB(40, 38, 41), rng:NextNumber())
		-- A round limb from `base` along its up direction; returns the tip
		local function limb(base: CFrame, length: number, thickness: number): CFrame
			part({
				Name = "Limb",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(length + thickness * 0.5, thickness, thickness),
				CFrame = base * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Wood,
				Color = bark,
				CanCollide = false,
				Parent = model,
			})
			return base * CFrame.new(0, length, 0)
		end
		local lean = math.rad(rng:NextNumber(6, 11))
		local scarred = rng:NextNumber() < 0.5
		local at = frame
		for i = 1, 3 do
			local thickness = (2.2 - i * 0.45) * s
			local length = (6.4 - i * 1.4) * s
			local base = at * CFrame.Angles(-lean, 0, 0) -- each segment bends further downwind
			at = limb(base, length, thickness)
			if scarred and i < 3 then
				part({
					Name = "Scar",
					Size = Vector3.new(0.22 * s, length * 0.85, 0.15),
					CFrame = base * CFrame.new(0, length / 2, thickness * 0.45),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(150, 205, 255),
					CanCollide = false,
					Parent = model,
				})
			end
			for _ = 1, if i == 1 then 1 else 2 do
				local sweep = CFrame.Angles(0, math.rad(rng:NextNumber(-80, 80)), 0)
					* CFrame.Angles(-math.rad(rng:NextNumber(45, 70)), 0, 0)
				local fork = base * CFrame.new(0, length * rng:NextNumber(0.55, 0.95), 0) * sweep
				local tip = limb(fork, rng:NextNumber(2.2, 3.8) * s, thickness * 0.35)
				if rng:NextNumber() < 0.5 then
					local bend =
						CFrame.Angles(math.rad(rng:NextNumber(-35, 35)), 0, math.rad(rng:NextNumber(-35, 35)))
					limb(tip * bend, rng:NextNumber(1, 1.8) * s, thickness * 0.22)
				end
			end
		end
		for i = 1, 3 do
			part({
				Name = "Root",
				Size = Vector3.new(0.9, 1.3, 2.2) * s,
				CFrame = frame
					* CFrame.Angles(0, i * 2.1 + rng:NextNumber(-0.3, 0.3), 0)
					* CFrame.new(0, 0.65 * s, -1.6 * s),
				Material = Enum.Material.Wood,
				Color = bark,
				CanCollide = false,
				Parent = model,
			}, "WedgePart")
		end
	end,
}

-- Ground scorched by a lightning strike: a dark burn with glowing cracks.
SPECS.ScorchMark = {
	size = Vector3.new(8, 0.4, 8),
	radius = 2,
	walkable = true,
	build = function(model, frame, s, rng)
		-- The zone's ground is 0.15 above the frame
		part({
			Name = "Burn",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 7 * s, 7 * s),
			CFrame = frame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(36, 34, 38),
			CanCollide = false,
			Parent = model,
		})
		for i = 1, 5 do
			local length = rng:NextNumber(1.8, 3.4) * s
			part({
				Name = "Crack",
				Size = Vector3.new(0.16, 0.06, length),
				CFrame = frame
					* CFrame.Angles(0, i * 1.26 + rng:NextNumber(-0.3, 0.3), 0)
					* CFrame.new(0, 0.27, -(0.4 * s + length / 2)),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(140, 200, 255),
				CanCollide = false,
				Parent = model,
			})
		end
	end,
}

local function moonCrystal(): { [string]: any }
	return { Material = Enum.Material.Glass, Color = Color3.fromRGB(190, 165, 240), Transparency = 0.1 }
end

SPECS.MoonMonolith = {
	size = Vector3.new(9, 18, 9),
	radius = 6.5,
	build = function(model, frame, s, rng)
		for i = 1, 3 do
			part({
				Name = "Base",
				Size = Vector3.new(4, 2, 3.5) * s,
				CFrame = frame * CFrame.Angles(0, i * 2.1, 0) * CFrame.new(0, 0.8 * s, -1.5 * s),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(95, 85, 120),
				Parent = model,
			})
		end
		shard(frame * CFrame.new(0, 1 * s, 0), 4.5 * s, 17 * s, moonCrystal(), model)
		part({
			Name = "Core",
			Size = Vector3.new(0.8, 10, 0.8) * s,
			CFrame = frame * CFrame.new(0, 6.5 * s, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(205, 175, 255),
			CanCollide = false,
			Parent = model,
		})
		for i = 1, 4 do
			shard(
				frame
					* CFrame.Angles(0, i * 1.6, 0)
					* CFrame.new(0, 0.5 * s, -3 * s)
					* CFrame.Angles(math.rad(-20), 0, 0),
				1.6 * s,
				rng:NextNumber(3.5, 7) * s,
				moonCrystal(),
				model
			)
		end
	end,
	effects = function(model, box, size)
		local glow = anchor(model, box, Vector3.new(4, size.Y * 0.8, 4))
		light(glow, Color3.fromRGB(190, 160, 255), 1.4, 22)
		emitter(glow, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(215, 195, 255)),
			Rate = 4,
			Lifetime = NumberRange.new(2, 3.5),
			Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0, 1.5, 0),
			Size = NumberSequence.new(0.6, 0),
			Transparency = fade(0.1, 1),
		})
	end,
}

SPECS.CraterRim = {
	size = Vector3.new(16, 5, 16),
	radius = 9,
	fit = "footprint",
	build = function(model, frame, s, rng)
		part({
			Name = "Bowl",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 13 * s, 13 * s),
			CFrame = frame * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(55, 50, 72),
			CanCollide = false,
			Parent = model,
		})
		for i = 1, 12 do
			if i ~= 1 then -- a gap to walk in through
				local height = rng:NextNumber(1.6, 3.4) * s
				part({
					Name = "Rim",
					Size = Vector3.new(rng:NextNumber(3, 4.2) * s, height, 2.6 * s),
					CFrame = frame
						* CFrame.Angles(0, i * math.pi / 6, 0)
						* CFrame.new(0, height / 2 - 0.3, -6.8 * s)
						* CFrame.Angles(math.rad(-14), 0, 0),
					Material = Enum.Material.Slate,
					Color = Color3.fromRGB(112, 102, 138),
					Parent = model,
				})
			end
		end
		for i = 1, 4 do
			shard(
				frame * CFrame.Angles(0, i * 1.7, 0) * CFrame.new(0, 0, -rng:NextNumber(0.5, 2.5) * s),
				0.9 * s,
				rng:NextNumber(1.2, 2.8) * s,
				{ Material = Enum.Material.Neon, Color = Color3.fromRGB(210, 170, 255), CanCollide = false },
				model
			)
		end
	end,
	effects = function(model, box, size)
		local glow = anchor(model, box * CFrame.new(0, -size.Y / 2 + 1, 0), Vector3.new(6, 1, 6))
		light(glow, Color3.fromRGB(200, 160, 255), 1, 14)
		emitter(glow, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(215, 190, 255)),
			Rate = 3,
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(1, 2),
			Size = NumberSequence.new(0.5, 0),
			Transparency = fade(0.1, 1),
		})
	end,
}

-- Fits WorldProps.<name> into the spec's box (an arch turns so its long side goes across).
local function fitImported(name: string, spec: Spec, frame: CFrame, s: number): Model?
	local template = Props.template("WorldProps", name)
	if template == nil then
		return nil
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = not spec.walkable
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	local size = spec.size * s
	local extents = model:GetExtentsSize()
	if spec.span and extents.Z > extents.X then
		Props.place(
			model,
			frame * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, size.Y / 2, 0),
			Vector3.new(size.Z, size.Y, size.X)
		)
	elseif spec.fit == "height" then
		local grow = size.Y / math.max(extents.Y, 0.01)
		Props.place(model, frame * CFrame.new(0, size.Y / 2, 0), extents * grow)
	else
		Props.place(model, frame * CFrame.new(0, size.Y / 2, 0), size, spec.fit == "footprint")
	end
	return model
end

-- Builds set piece `name` standing on the ground at `frame` (its front faces the
-- frame's look direction), scaled by `scale`, and returns how far other decor
-- should keep from it. "GlowcapRing" is a fairy ring of GiantGlowcaps.
function SetPieces.build(name: string, frame: CFrame, scale: number, parent: Instance, rng: Random): number
	if name == "GlowcapRing" then
		local ring = Instance.new("Model")
		ring.Name = "GlowcapRing"
		ring.Parent = parent
		part({
			Name = "FairyRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 20 * scale, 20 * scale),
			CFrame = frame * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromRGB(70, 120, 60),
			CanCollide = false,
			Parent = ring,
		})
		for i = 1, 6 do
			local angle = i * math.pi / 3 + rng:NextNumber(-0.2, 0.2)
			local spot = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -10 * scale)
			SetPieces.build(
				"GiantGlowcap",
				spot * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0),
				scale * rng:NextNumber(0.6, 1.05),
				ring,
				rng
			)
		end
		local spores = anchor(ring, frame * CFrame.new(0, 2, 0), Vector3.new(16, 1, 16) * scale)
		emitter(spores, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(130, 245, 220)),
			Rate = 6,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.3, 1),
			Acceleration = Vector3.new(0, 0.8, 0),
			Size = NumberSequence.new(0.35, 0),
			Transparency = fade(0.1, 1),
		})
		return 13 * scale
	end

	local spec = SPECS[name]
	assert(spec, `unknown set piece {name}`)
	local model = fitImported(name, spec, frame, scale)
	if model == nil then
		local standIn = Instance.new("Model")
		spec.build(standIn, frame, scale, rng)
		standIn.WorldPivot = frame -- keeps the bounding box upright for the effects below
		model = standIn
	end
	local built = model :: Model
	built.Name = name
	built.Parent = parent
	local box, size = built:GetBoundingBox()
	if spec.effects then
		spec.effects(built, box, size)
	end
	-- A model fitted by height can come out wider than its box
	return math.max(spec.radius * scale, math.max(size.X, size.Z) / 2)
end

-- True when `name` is something SetPieces.build can make (imported or not).
function SetPieces.has(name: string): boolean
	return SPECS[name] ~= nil
end

local CLOUD_HEIGHT = 38
local CLOUD_COLOR = Color3.fromRGB(52, 56, 66)
local CLOUD_TOP = Color3.fromRGB(98, 102, 114)
local FLASH_COLOR = Color3.fromRGB(175, 200, 245)

-- The storm over a zone `radius` studs across the middle: a low bank of dark cloud
-- (set off toward the sun, so its shadow falls on the zone), rain, mist blowing
-- along `wind`, and lightning flickering inside the cloud. The lightning crag's
-- bolts come down out of it.
function SetPieces.stormSky(center: Vector3, radius: number, wind: Vector3, parent: Instance)
	local rng = Random.new(1717)
	local sky = Instance.new("Model")
	sky.Name = "StormSky"
	local sun = Lighting:GetSunDirection()
	local shift = if sun.Y > 0.25 then Vector3.new(sun.X, 0, sun.Z) * (CLOUD_HEIGHT / sun.Y) else Vector3.zero
	if shift.Magnitude > 45 then
		shift = shift.Unit * 45
	end
	local bank = center + shift + Vector3.new(0, CLOUD_HEIGHT, 0)
	-- A flat, dark base with billows heaped on top (matte, so it doesn't shine like plastic)
	local puffs: { BasePart } = {}
	for i = 1, 30 do
		local base = i <= 9
		local angle = rng:NextNumber() * 2 * math.pi
		local distance = math.sqrt(rng:NextNumber()) * radius * (if base then 0.9 else 0.75)
		local width = if base then rng:NextNumber(26, 36) else rng:NextNumber(13, 24)
		local height = if base then width * 0.2 else width * rng:NextNumber(0.55, 0.8)
		local offset = Vector3.new(
			math.cos(angle) * distance,
			if base then 0 else rng:NextNumber(2, 8),
			math.sin(angle) * distance
		)
		local puff = blob({
			Name = "Cloud",
			Size = Vector3.new(width, height, width * rng:NextNumber(0.75, 1)),
			CFrame = CFrame.new(bank + offset) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Material = Enum.Material.Fabric,
			Color = if base then CLOUD_COLOR else CLOUD_COLOR:Lerp(CLOUD_TOP, rng:NextNumber()),
			CanCollide = false,
			Parent = sky,
		})
		table.insert(puffs, puff)
	end

	-- Rain over the whole zone (the client adds heavier rain around the player
	-- inside it, see ZoneMoodController)
	local rain = anchor(
		sky,
		CFrame.new(center + Vector3.new(0, CLOUD_HEIGHT - 8, 0)),
		Vector3.new(radius * 2, 1, radius * 2)
	)
	emitter(rain, {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(205, 215, 235)),
		LightEmission = 0.2,
		EmissionDirection = Enum.NormalId.Bottom,
		Rate = 450,
		Lifetime = NumberRange.new(0.5, 0.6),
		Speed = NumberRange.new(55, 65),
		Acceleration = wind * 12,
		Size = NumberSequence.new(0.55),
		Squash = NumberSequence.new(2.5),
		Transparency = NumberSequence.new(0.3),
	})

	-- Low mist drifting through on the wind
	local mist =
		anchor(sky, CFrame.new(center + Vector3.new(0, 2.5, 0)), Vector3.new(radius * 1.7, 2, radius * 1.7))
	emitter(mist, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(165, 172, 186)),
		LightEmission = 0,
		Rate = 4,
		Lifetime = NumberRange.new(7, 10),
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = wind * 1.5,
		RotSpeed = NumberRange.new(-8, 8),
		Size = NumberSequence.new(7, 13),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.8),
			NumberSequenceKeypoint.new(0.75, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- Sheet lightning: the cloud lights up from inside and the zone flickers
	local glow = light(
		anchor(sky, CFrame.new(center + Vector3.new(0, CLOUD_HEIGHT - 10, 0)), Vector3.new(1, 1, 1)),
		FLASH_COLOR,
		0,
		60
	)
	sky.Parent = parent
	task.spawn(function()
		local beat = Random.new()
		while sky.Parent do
			task.wait(beat:NextNumber(4, 11))
			local lit = { puffs[beat:NextInteger(1, #puffs)], puffs[beat:NextInteger(1, #puffs)] }
			local colors = { lit[1].Color, lit[2].Color }
			for _, puff in lit do
				puff.Material = Enum.Material.Neon
				puff.Color = FLASH_COLOR
			end
			for _, step in { { 3, 0.07 }, { 0.3, 0.08 }, { 5, 0.12 } } do
				glow.Brightness = step[1]
				task.wait(step[2])
			end
			glow.Brightness = 0
			for i, puff in lit do
				puff.Material = Enum.Material.Fabric
				puff.Color = colors[i]
			end
		end
	end)
end

-- Every model name a set piece can import (tools/studio/organize_imports.luau files these).
SetPieces.propNames = {} :: { string }
for name in SPECS do
	table.insert(SetPieces.propNames, name)
end
table.sort(SetPieces.propNames)

return SetPieces

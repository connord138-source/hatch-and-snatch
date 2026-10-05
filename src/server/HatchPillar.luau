--!strict
-- A pillar of light for Legendary and rarer hatches (owner, 2026-10-05: "a more
-- involved sequence when a legendary or higher is drawn"). When the hatcher's
-- reveal hits (RevealTiming), a beam in the rarity's color shoots up from their
-- incubator with a shockwave ring, rising sparkles and the rarity's sound, so the
-- whole server sees someone pulled something big. Everything is anchored,
-- non-colliding and gone after a few seconds. The sound is played by each client
-- (RevealController) except the hatcher's, whose reveal already played it (PC
-- playtest 2026-10-05: the hatcher heard the stinger twice, 19 ms apart).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local LIFETIME = 6.5

local HatchPillar = {}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- The rarity's stinger from the sound pack, heard around the pillar (not played
-- here: each client but the hatcher's plays it).
local function sound(parent: BasePart, name: string)
	local id = Config.Sounds.id
	local region = Config.Sounds.regions[name]
	local s = Instance.new("Sound")
	if id > 0 and region then
		s.SoundId = `rbxassetid://{id}`
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
	else
		s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		s.PlaybackSpeed = 0.5
	end
	s.Name = "PillarSound"
	s.Volume = 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 320
	s.Parent = parent
end

-- `base`: where the pillar stands (the incubator); `ultra`: Mythic and up (taller,
-- wider); `hatcherUserId`: whose hatch it is (their client doesn't replay the sound).
function HatchPillar.spawn(
	base: Vector3,
	color: Color3,
	rarityId: string,
	ultra: boolean,
	hatcherUserId: number
)
	local height = if ultra then 420 else 260
	local width = if ultra then 6 else 4
	local model = Instance.new("Model")
	model.Name = "HatchPillar"
	model:SetAttribute("HatcherUserId", hatcherUserId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- arrives whole, sound included
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is its X
	local center = CFrame.new(base + Vector3.new(0, height / 2, 0)) * upright
	local beam = part(model, {
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.4, 0.4),
		CFrame = center,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.2,
	})
	local core = part(model, {
		Name = "Core",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.2, 0.2),
		CFrame = center,
		Material = Enum.Material.Neon,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.1,
	})
	local ring = part(model, {
		Name = "Shockwave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 3, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * upright,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.1,
	})
	local anchor = part(model, {
		Name = "Anchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 1, 0)),
		Transparency = 1,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 45
	light.Brightness = 5
	light.Parent = anchor
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Lifetime = NumberRange.new(2, 3.2)
	sparkles.Speed = NumberRange.new(18, 40)
	sparkles.SpreadAngle = Vector2.new(14, 14)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Rate = if ultra then 70 else 45
	sparkles.Parent = anchor
	model.Parent = Workspace

	sound(anchor, rarityId)
	local grow = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(beam, grow, { Size = Vector3.new(height, width, width) }):Play()
	TweenService:Create(core, grow, { Size = Vector3.new(height, width * 0.35, width * 0.35) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 60, 60),
		Transparency = 1,
	}):Play()
	task.delay(3.4, function()
		sparkles.Rate = 0
		local fade = TweenInfo.new(LIFETIME - 3.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(beam, fade, { Transparency = 1, Size = Vector3.new(height, 0.3, 0.3) }):Play()
		TweenService:Create(core, fade, { Transparency = 1 }):Play()
		TweenService:Create(light, fade, { Brightness = 0 }):Play()
	end)
	task.delay(LIFETIME, function()
		model:Destroy()
	end)
end

return HatchPillar

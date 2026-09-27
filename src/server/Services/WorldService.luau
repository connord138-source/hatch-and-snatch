--!strict
-- Builds the placeholder Crackpoint Island layout from code: hub reactor, egg
-- conveyor loop, Moon Egg and a ring of 8 base plots. Real art replaces these
-- parts later; everything else only depends on the named parts/CFrames here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

export type PlotLayout = {
	index: number,
	model: Model,
	origin: CFrame, -- plot center on the ground, -Z faces the hub
	spawn: CFrame,
	pedestals: { CFrame }, -- where creatures stand
	incubators: { BasePart },
	collector: BasePart,
	label: TextLabel,
	collectorLabel: TextLabel,
}

local PLOT_RADIUS = 115
local PLOT_SIZE = 44
local GROUND_Y = 0.2

local WorldService = {
	plots = {} :: { PlotLayout },
	moon = nil :: BasePart?,
	conveyorCenter = Vector3.new(0, GROUND_Y, 0),
}

local worldFolder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function billboard(parent: BasePart, offset: Vector3, size: UDim2): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 150
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	return label
end

local function buildIsland()
	part({
		Name = "IslandGround",
		Size = Vector3.new(480, 2, 480),
		CFrame = CFrame.new(0, GROUND_Y - 1, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(86, 128, 68),
		Parent = worldFolder,
	})

	-- Hub reactor (placeholder): stone base + glowing glass dome
	part({
		Name = "ReactorBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 26, 26),
		CFrame = CFrame.new(0, GROUND_Y + 5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(60, 58, 62),
		Parent = worldFolder,
	})
	part({
		Name = "ReactorDome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(22, 22, 22),
		CFrame = CFrame.new(0, GROUND_Y + 10, 0),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = Color3.fromRGB(120, 220, 255),
		CanCollide = false,
		Parent = worldFolder,
	})

	-- Conveyor loop: a ring of belt segments
	local conveyor = Config.Eggs.conveyor
	local segments = 56
	local circumference = 2 * math.pi * conveyor.radius
	for i = 1, segments do
		local angle = (i - 1) / segments * 2 * math.pi
		local position =
			Vector3.new(math.cos(angle) * conveyor.radius, GROUND_Y + 1, math.sin(angle) * conveyor.radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		part({
			Name = "Belt",
			Size = Vector3.new(5, 1.2, circumference / segments + 0.3),
			CFrame = CFrame.lookAt(position, position + tangent),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(70, 72, 80),
			Parent = worldFolder,
		})
	end

	-- The Moon Egg — EventService recolors it for moon events
	local moon = part({
		Name = "MoonEgg",
		Size = Vector3.new(90, 90, 90),
		CFrame = CFrame.new(0, 420, -650),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(235, 230, 210),
		CanCollide = false,
		CastShadow = false,
		Parent = worldFolder,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = moon
	WorldService.moon = moon

	-- Keep default spawns out of the reactor; players are moved to their plot anyway
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant.CFrame = CFrame.new(0, GROUND_Y + 0.5, 30)
		end
	end
end

local function buildPlot(index: number): PlotLayout
	local angle = (index - 1) / Config.Economy.tunables.basePlotsPerServer * 2 * math.pi
	local center = Vector3.new(math.cos(angle) * PLOT_RADIUS, GROUND_Y, math.sin(angle) * PLOT_RADIUS)
	local origin = CFrame.lookAt(center, Vector3.new(0, GROUND_Y, 0))

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		CFrame = origin * CFrame.new(0, 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 120, 85),
		Parent = model,
	})
	model.PrimaryPart = floor
	local top = 1

	-- Pedestals: 2 rows of 5 across the back half (+Z is away from the hub)
	local pedestals: { CFrame } = {}
	local pedestalCount = Config.Economy.tunables.pedestalsBase
	for i = 1, pedestalCount do
		local column = (i - 1) % 5
		local row = (i - 1) // 5
		local localPos = Vector3.new(-16 + column * 8, top + 0.7, 6 + row * 10)
		local pedestal = part({
			Name = `Pedestal{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 6, 6),
			CFrame = origin * CFrame.new(localPos) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(110, 110, 118),
			Parent = model,
		})
		pedestal:SetAttribute("Index", i)
		table.insert(pedestals, origin * CFrame.new(localPos + Vector3.new(0, 0.7, 0)))
	end

	-- Incubator rack, front-left (-Z faces the hub)
	local incubators: { BasePart } = {}
	for i = 1, Config.Economy.tunables.incubatorSlots do
		local incubator = part({
			Name = `Incubator{i}`,
			Size = Vector3.new(3.4, 4, 3.4),
			CFrame = origin * CFrame.new(-17 + (i - 1) * 4.5, top + 2, -15),
			Material = Enum.Material.Glass,
			Transparency = 0.4,
			Color = Color3.fromRGB(200, 230, 255),
			Parent = model,
		})
		table.insert(incubators, incubator)
	end

	-- Cash collector pad, front-right
	local collector = part({
		Name = "Collector",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = origin * CFrame.new(15, top + 0.2, -15),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(80, 230, 120),
		Parent = model,
	})
	local collectorLabel = billboard(collector, Vector3.new(0, 4, 0), UDim2.fromOffset(160, 50))
	collectorLabel.Text = "$0"

	-- Owner sign at the front edge
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(10, 1, 1),
		CFrame = origin * CFrame.new(0, top + 6, -PLOT_SIZE / 2 + 1),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	local label = billboard(sign, Vector3.zero, UDim2.fromOffset(260, 60))
	label.Text = "Free plot"

	model.Parent = worldFolder

	return {
		index = index,
		model = model,
		origin = origin,
		spawn = origin * CFrame.new(0, top + 3, -8) * CFrame.Angles(0, math.pi, 0),
		pedestals = pedestals,
		incubators = incubators,
		collector = collector,
		label = label,
		collectorLabel = collectorLabel,
	}
end

function WorldService.start()
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace

	buildIsland()
	for i = 1, Config.Economy.tunables.basePlotsPerServer do
		table.insert(WorldService.plots, buildPlot(i))
	end
end

return WorldService

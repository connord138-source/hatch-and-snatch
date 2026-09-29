--!strict
-- Builds the Crackpoint Island layout from code: hub reactor, egg conveyor loop,
-- Moon Egg and a ring of 8 base plots. Each piece starts as a plain part; when
-- its 3D prop is imported (ReplicatedStorage.WorldProps, see Props.luau) the
-- prop is fitted over it. Everything else only depends on the parts/CFrames here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(script.Parent.Parent.Props)

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
	lockPrompt: ProximityPrompt,
	lockLabel: TextLabel,
	lasers: { BasePart },
}

local PLOT_RADIUS = 115
local PLOT_SIZE = 44
local GROUND_Y = 0.2
local INCUBATOR_GLASS = 0.45 -- transparency of the imported incubator model

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

-- Small labels use a pixel size and a short view distance; the base sign is sized
-- in studs (UDim2 scale) so other plots' signs shrink with distance instead of piling up.
local function billboard(parent: BasePart, offset: Vector3, size: UDim2, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance
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

	-- Hub reactor: stone base + glowing glass dome, or the imported HatcheryReactor
	local reactorBase = part({
		Name = "ReactorBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 26, 26),
		CFrame = CFrame.new(0, GROUND_Y + 5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(60, 58, 62),
		Parent = worldFolder,
	})
	local reactorDome = part({
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

	if Props.spawn("HatcheryReactor", CFrame.new(0, GROUND_Y, 0), 24, worldFolder) then
		reactorBase.Transparency = 1 -- keeps its collision
		reactorDome.Transparency = 1
	end

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
		if i <= Config.Economy.tunables.nurserySlotsBase then
			-- Nursery pedestal: nothing standing here can be stolen
			pedestal.Name = `Nursery{i}`
			pedestal.Material = Enum.Material.Fabric
			pedestal.Color = Color3.fromRGB(120, 180, 255)
			local nurseryLabel = billboard(pedestal, Vector3.new(0, 3, 0), UDim2.fromOffset(120, 30), 60)
			nurseryLabel.Text = "Nursery"
			nurseryLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		end
		local isNursery = i <= Config.Economy.tunables.nurserySlotsBase
		Props.dress(pedestal, if isNursery then "NurseryNest" else "Pedestal", {
			cframe = origin * CFrame.new(localPos),
			size = Vector3.new(6.4, 1.4, 6.4),
			stretch = true, -- the models are taller than a pedestal slot; fill the width instead
		})
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
		local incubatorProp = Props.dress(
			incubator,
			"Incubator",
			{ size = Vector3.new(3.6, 4.4, 3.6), cframe = incubator.CFrame * CFrame.new(0, 0.2, 0) }
		)
		if incubatorProp then
			-- The model's glass is baked opaque into its texture; see-through shows the egg inside
			for _, descendant in incubatorProp:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = INCUBATOR_GLASS
				end
			end
		end
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
	Props.dress(collector, "Collector", {
		size = Vector3.new(7.5, 1.2, 7.5),
		cframe = collector.CFrame * CFrame.new(0, 0.4, 0),
		stretch = true,
	})
	local collectorLabel = billboard(collector, Vector3.new(0, 4, 0), UDim2.fromOffset(160, 50), 60)
	collectorLabel.Text = "$0"

	-- Base lock button (front-center) + laser walls around the plot edge
	local lockButton = part({
		Name = "LockButton",
		Size = Vector3.new(3, 1.2, 3),
		CFrame = origin * CFrame.new(0, top + 0.6, -15),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 80, 80),
		Parent = model,
	})
	Props.dress(
		lockButton,
		"LockButton",
		{ size = Vector3.new(3.4, 3, 3.4), cframe = lockButton.CFrame * CFrame.new(0, 0.9, 0) }
	)
	local lockPrompt = Instance.new("ProximityPrompt")
	lockPrompt.Name = "Lock"
	lockPrompt.ActionText = "Lock Base"
	lockPrompt.ObjectText = "Laser gate"
	lockPrompt.HoldDuration = 0
	lockPrompt.MaxActivationDistance = 10
	lockPrompt.RequiresLineOfSight = false
	lockPrompt:SetAttribute("VisibleTo", "owner")
	lockPrompt.Parent = lockButton
	local lockLabel = billboard(lockButton, Vector3.new(0, 3, 0), UDim2.fromOffset(160, 36), 60)
	lockLabel.Text = "Unlocked"

	local lasers: { BasePart } = {}
	local half = PLOT_SIZE / 2
	for _, edge in
		{
			{ CFrame.new(0, 4, -half), Vector3.new(PLOT_SIZE, 7, 0.3) },
			{ CFrame.new(0, 4, half), Vector3.new(PLOT_SIZE, 7, 0.3) },
			{ CFrame.new(-half, 4, 0), Vector3.new(0.3, 7, PLOT_SIZE) },
			{ CFrame.new(half, 4, 0), Vector3.new(0.3, 7, PLOT_SIZE) },
		} :: { { any } }
	do
		local laser = part({
			Name = "Laser",
			Size = edge[2],
			CFrame = origin * edge[1],
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 40, 40),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = model,
		})
		table.insert(lasers, laser)
	end

	-- Owner sign at the front edge
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(10, 1, 1),
		CFrame = origin * CFrame.new(0, top + 6, -PLOT_SIZE / 2 + 1),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	local label = billboard(sign, Vector3.zero, UDim2.fromScale(18, 4), 300)
	label.Text = "Free plot"

	-- Entrance arch over the front edge (decor only). The model spans its own Z
	-- axis, so turn it 90° to span the front edge and let players walk through.
	Props.spawn(
		"PlotArch",
		origin * CFrame.new(0, top, -PLOT_SIZE / 2 + 0.5) * CFrame.Angles(0, math.pi / 2, 0),
		13,
		model
	)

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
		lockPrompt = lockPrompt,
		lockLabel = lockLabel,
		lasers = lasers,
	}
end

-- Decor between and around the plots. Deterministic, so every server matches.
local DECOR: { { name: string, height: number, weight: number } } = {
	{ name = "MossTree", height = 22, weight = 5 },
	{ name = "RockCluster", height = 5, weight = 4 },
	{ name = "BerryBush", height = 4, weight = 4 },
	{ name = "MushroomCluster", height = 3, weight = 3 },
	{ name = "CrystalCluster", height = 6, weight = 2 },
	{ name = "CoralCluster", height = 6, weight = 1 },
	{ name = "LavaRock", height = 5, weight = 1 },
	{ name = "IceSpire", height = 10, weight = 1 },
}

local function scatterDecor()
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = worldFolder
	local available: { { name: string, height: number, weight: number } } = {}
	local total = 0
	for _, entry in DECOR do
		if Props.template("WorldProps", entry.name) then
			table.insert(available, entry)
			total += entry.weight
		end
	end

	-- Lamp posts ring the conveyor so the egg loop reads at night
	local lampRadius = Config.Eggs.conveyor.radius + 6
	for i = 0, 11 do
		local angle = i / 12 * 2 * math.pi
		local position = Vector3.new(math.cos(angle) * lampRadius, GROUND_Y, math.sin(angle) * lampRadius)
		local lamp = Props.spawn("LampPost", CFrame.lookAt(position, Vector3.new(0, GROUND_Y, 0)), 9, folder)
		if lamp then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 210, 150)
			light.Range = 18
			light.Brightness = 1.5
			light.Parent = lamp.PrimaryPart or lamp:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	if total == 0 then
		return
	end
	local rng = Random.new(20260929)
	local plotCount = Config.Economy.tunables.basePlotsPerServer
	local placed = 0
	local attempts = 0
	while placed < 90 and attempts < 1000 do
		attempts += 1
		local angle = rng:NextNumber() * 2 * math.pi
		local radius = rng:NextNumber(Config.Eggs.conveyor.radius + 12, 235)
		local position = Vector3.new(math.cos(angle) * radius, GROUND_Y, math.sin(angle) * radius)
		-- Keep plots, their fronts and the walkways clear
		local blocked = false
		for i = 1, plotCount do
			local plotAngle = (i - 1) / plotCount * 2 * math.pi
			local plotCenter =
				Vector3.new(math.cos(plotAngle) * PLOT_RADIUS, GROUND_Y, math.sin(plotAngle) * PLOT_RADIUS)
			if (position - plotCenter).Magnitude < PLOT_SIZE * 0.85 then
				blocked = true
				break
			end
			-- Walkway from the plot's front edge in to the conveyor
			local radial = plotCenter.Unit
			local along = position:Dot(radial)
			local sideways = (position - radial * along).Magnitude
			if along > 0 and along < PLOT_RADIUS and sideways < 14 then
				blocked = true
				break
			end
		end
		if blocked then
			continue
		end
		local roll = rng:NextNumber() * total
		local pick = available[1]
		for _, entry in available do
			roll -= entry.weight
			if roll <= 0 then
				pick = entry
				break
			end
		end
		local scale = rng:NextNumber(0.75, 1.3)
		local cframe = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0)
		if Props.spawn(pick.name, cframe, pick.height * scale, folder) then
			placed += 1
		end
	end
end

-- True when a world position is inside the plot's footprint (any height).
function WorldService.isInsidePlot(plot: PlotLayout, position: Vector3): boolean
	local localPos = plot.origin:PointToObjectSpace(position)
	local half = PLOT_SIZE / 2
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half and localPos.Y < 40
end

-- Just outside the front edge of a plot (where the laser gate pushes intruders).
function WorldService.outsideFront(plot: PlotLayout): CFrame
	return plot.origin * CFrame.new(0, 4, -PLOT_SIZE / 2 - 6)
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
	scatterDecor()
end

return WorldService

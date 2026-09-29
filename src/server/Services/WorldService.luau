--!strict
-- Builds Crackpoint Island from code: a round grass island with a beach and sea,
-- the hub reactor, the egg conveyor (eggs roll out of and back into the hatchery
-- tunnel), the Moon Egg, a biome zone between each pair of plots, lighting, and
-- the ring of base plots. Plots grow with the owner's base level (setLevel) and
-- take a biome look (applyTheme). Each piece starts as a plain part; when its 3D
-- prop is imported (ReplicatedStorage.WorldProps, see Props.luau) the prop is
-- fitted over it. Gameplay only depends on the parts/CFrames exposed here.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(script.Parent.Parent.Props)

export type PlotLayout = {
	index: number,
	model: Model,
	origin: CFrame, -- plot center on the ground, -Z faces the hub
	spawn: CFrame,
	pedestals: { CFrame }, -- where creatures stand, for every pedestal a max-level base has
	incubators: { BasePart }, -- egg anchor inside each incubator bay (HatchService)
	incubatorPads: { BasePart }, -- the pad under each bay: tier ring + buy prompt
	collector: BasePart,
	label: TextLabel,
	collectorLabel: TextLabel,
	lockPrompt: ProximityPrompt,
	lockLabel: TextLabel,
	upgradePrompt: ProximityPrompt,
	upgradeLabel: TextLabel,
	lasers: { BasePart },
	floor: BasePart,
	trim: { BasePart },
	pedestalParts: { BasePart },
	pedestalProps: { Model? },
	level: number,
	width: number,
	depth: number,
}

local PLOT_RADIUS = 118
local PLOT_FRONT = -22 -- local Z of a plot's front edge (the side facing the hub)
local GROUND_Y = 0.2
local ISLAND_RADIUS = 262
local INCUBATOR_GLASS = 0.45 -- transparency of the imported incubator model
local TOP = 1 -- plot floor top, relative to the plot origin

local WorldService = {
	plots = {} :: { PlotLayout },
	moon = nil :: BasePart?,
	conveyorCenter = Vector3.new(0, GROUND_Y, 0),
}

local worldFolder: Folder
local moonTint: ColorCorrectionEffect?

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

-- A flat disc lying on the ground (a cylinder part turned on its side).
local function disc(
	name: string,
	center: Vector3,
	diameter: number,
	thickness: number,
	props: { [string]: any }
): Part
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thickness, diameter, diameter)
	props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
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

local function plotAngle(index: number): number
	return (index - 1) / Config.Economy.tunables.basePlotsPerServer * 2 * math.pi
end

-- Plot footprint for a base level: it widens and deepens (away from the hub).
local function plotSize(level: number): (number, number)
	return 44 + (level - 1) * 6, 44 + (level - 1) * 9
end

---------------------------------------------------------------------------
-- Lighting, sea, island
---------------------------------------------------------------------------

local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

local function setupLighting()
	Lighting.ClockTime = 14.3
	Lighting.Brightness = 2.4
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 140, 155)

	local atmosphere = effect("Atmosphere", "IslandAtmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(199, 215, 235)
	atmosphere.Decay = Color3.fromRGB(110, 120, 140)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4

	local bloom = effect("BloomEffect", "IslandBloom") :: BloomEffect
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.5

	local sunRays = effect("SunRaysEffect", "IslandSunRays") :: SunRaysEffect
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.8

	local grade = effect("ColorCorrectionEffect", "IslandGrade") :: ColorCorrectionEffect
	grade.Saturation = 0.15
	grade.Contrast = 0.07

	moonTint = effect("ColorCorrectionEffect", "MoonTint") :: ColorCorrectionEffect

	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = terrain
end

-- Tints the whole world during a moon event (nil = back to normal).
function WorldService.setMoonTint(color: Color3?)
	if moonTint == nil then
		return
	end
	local target = if color then color:Lerp(Color3.new(1, 1, 1), 0.65) else Color3.new(1, 1, 1)
	TweenService:Create(moonTint, TweenInfo.new(4), { TintColor = target }):Play()
end

local function buildSeaAndIsland()
	local terrain = Workspace.Terrain
	-- The place was made from Studio's Baseplate template: its 2048-stud grey floor
	-- (top at y 0) would cover the sea and hide the beach, which sits just below it.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	-- Sea around the island (terrain water), with a sandy sea floor
	terrain:FillCylinder(CFrame.new(0, -24, 0), 10, 1500, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -11, 0), 16, 1500, Enum.Material.Water)
	-- No water under the island itself: its top voxel layer (y -4..0) pokes up
	-- through the grass in blue patches. Keep it only under the beach's outer edge,
	-- where it laps up as a shoreline. (Runs before buildZones, so no hill is cut.)
	terrain:FillCylinder(CFrame.new(0, -11, 0), 18, ISLAND_RADIUS + 10, Enum.Material.Air)

	disc("Beach", Vector3.new(0, GROUND_Y - 2.4, 0), ISLAND_RADIUS * 2 + 40, 4, {
		Material = Enum.Material.Sand,
		Color = Color3.fromRGB(226, 205, 150),
		Parent = worldFolder,
	})
	disc("IslandGround", Vector3.new(0, GROUND_Y - 2, 0), ISLAND_RADIUS * 2, 4, {
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(88, 132, 66),
		Parent = worldFolder,
	})
end

---------------------------------------------------------------------------
-- Hub: reactor, conveyor, tunnel, moon
---------------------------------------------------------------------------

local function buildTunnel()
	local conveyor = Config.Eggs.conveyor
	local center = math.rad(conveyor.tunnelCenterDegrees)
	local half = math.rad(conveyor.tunnelHalfDegrees)
	local steps = 8
	local stone = Color3.fromRGB(96, 88, 80)
	for i = 0, steps - 1 do
		local a0 = center - half + (i / steps) * 2 * half
		local a1 = center - half + ((i + 1) / steps) * 2 * half
		local mid = (a0 + a1) / 2
		local length = (a1 - a0) * conveyor.radius + 0.4
		local radial = Vector3.new(math.cos(mid), 0, math.sin(mid))
		local tangent = Vector3.new(-math.sin(mid), 0, math.cos(mid))
		local basePosition = radial * conveyor.radius + Vector3.new(0, GROUND_Y, 0)
		local frame = CFrame.fromMatrix(basePosition, radial, Vector3.yAxis, -tangent)
		part({
			Name = "TunnelRoof",
			Size = Vector3.new(10, 1.4, length),
			CFrame = frame * CFrame.new(0, 7.6, 0),
			Material = Enum.Material.Cobblestone,
			Color = stone,
			Parent = worldFolder,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "TunnelWall",
				Size = Vector3.new(1.4, 7, length),
				CFrame = frame * CFrame.new(side * 4.3, 3.7, 0),
				Material = Enum.Material.Cobblestone,
				Color = stone,
				Parent = worldFolder,
			})
		end
	end
	-- Glowing arches at both mouths, and a sign on top
	for _, edge in { center - half, center + half } do
		local radial = Vector3.new(math.cos(edge), 0, math.sin(edge))
		local tangent = Vector3.new(-math.sin(edge), 0, math.cos(edge))
		local frame = CFrame.fromMatrix(
			radial * conveyor.radius + Vector3.new(0, GROUND_Y, 0),
			radial,
			Vector3.yAxis,
			-tangent
		)
		part({
			Name = "TunnelMouth",
			Size = Vector3.new(10.4, 0.6, 0.6),
			CFrame = frame * CFrame.new(0, 8.4, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(90, 220, 255),
			Parent = worldFolder,
		})
	end
	local sign = part({
		Name = "TunnelSign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(
			Vector3.new(math.cos(center), 0, math.sin(center)) * conveyor.radius
				+ Vector3.new(0, GROUND_Y + 8.6, 0)
		),
		Transparency = 1,
		CanCollide = false,
		Parent = worldFolder,
	})
	local label = billboard(sign, Vector3.new(0, 3, 0), UDim2.fromOffset(260, 50), 220)
	label.Text = "🥚 HATCHERY"
	label.TextColor3 = Color3.fromRGB(150, 235, 255)
end

local function buildHub()
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

	-- Stone plaza under the hub and conveyor
	disc("Plaza", Vector3.new(0, GROUND_Y - 0.15, 0), (Config.Eggs.conveyor.radius + 10) * 2, 0.5, {
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(150, 145, 135),
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
	buildTunnel()

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

---------------------------------------------------------------------------
-- Plots
---------------------------------------------------------------------------

local function buildPlot(index: number): PlotLayout
	local angle = plotAngle(index)
	local center = Vector3.new(math.cos(angle) * PLOT_RADIUS, GROUND_Y, math.sin(angle) * PLOT_RADIUS)
	local origin = CFrame.lookAt(center, Vector3.new(0, GROUND_Y, 0))

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(44, 1, 44),
		CFrame = origin * CFrame.new(0, 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 120, 85),
		Parent = model,
	})
	model.PrimaryPart = floor
	local trim: { BasePart } = {}
	for i = 1, 4 do
		trim[i] = part({
			Name = "Trim",
			Size = Vector3.new(1, 1.3, 1),
			CFrame = origin,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(90, 120, 60),
			CanCollide = false,
			Parent = model,
		})
	end

	-- Pedestals: rows of 5 from the front of the back area, one row per base level
	local maxPedestals = Config.Economy.tunables.pedestalsMax
	local pedestals: { CFrame } = {}
	local pedestalParts: { BasePart } = {}
	local pedestalProps: { Model? } = {}
	for i = 1, maxPedestals do
		local column = (i - 1) % 5
		local row = (i - 1) // 5
		local localPos = Vector3.new(-16 + column * 8, TOP + 0.7, 6 + row * 9.5)
		local isNursery = i <= Config.Economy.tunables.nurserySlotsBase
		local pedestal = part({
			Name = if isNursery then `Nursery{i}` else `Pedestal{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 6, 6),
			CFrame = origin * CFrame.new(localPos) * CFrame.Angles(0, 0, math.rad(90)),
			Material = if isNursery then Enum.Material.Fabric else Enum.Material.Slate,
			Color = if isNursery then Color3.fromRGB(120, 180, 255) else Color3.fromRGB(110, 110, 118),
			Parent = model,
		})
		pedestal:SetAttribute("Index", i)
		if isNursery then
			-- Nursery pedestal: nothing standing here can be stolen
			local nurseryLabel = billboard(pedestal, Vector3.new(0, 3, 0), UDim2.fromOffset(120, 30), 60)
			nurseryLabel.Text = "Nursery"
			nurseryLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		end
		pedestalProps[i] = Props.dress(pedestal, if isNursery then "NurseryNest" else "Pedestal", {
			cframe = origin * CFrame.new(localPos),
			size = Vector3.new(6.4, 1.4, 6.4),
			stretch = true, -- the models are taller than a pedestal slot; fill the width instead
		})
		pedestalParts[i] = pedestal
		pedestals[i] = origin * CFrame.new(localPos + Vector3.new(0, 0.7, 0))
	end

	-- Incubator bays, front-left: 2 rows of 3. HatchService shows owned/locked states.
	local incubators: { BasePart } = {}
	local incubatorPads: { BasePart } = {}
	for i = 1, #Config.Progression.incubatorSlotCosts do
		local column = (i - 1) % 3
		local row = (i - 1) // 3
		local bay = origin * CFrame.new(-18 + column * 4.6, TOP, -16 + row * 5.2)
		local pad = disc("IncubatorPad", (bay * CFrame.new(0, 0.1, 0)).Position, 4.2, 0.2, {
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(120, 120, 130),
			Parent = model,
		})
		pad:SetAttribute("Slot", i)
		local incubator = part({
			Name = `Incubator{i}`,
			Size = Vector3.new(3.4, 4, 3.4),
			CFrame = bay * CFrame.new(0, 2, 0),
			Material = Enum.Material.Glass,
			Transparency = 0.4,
			Color = Color3.fromRGB(200, 230, 255),
			CanCollide = false,
			Parent = model,
		})
		incubator:SetAttribute("Slot", i)
		local incubatorProp = Props.dress(
			incubator,
			"Incubator",
			{ size = Vector3.new(3.6, 4.4, 3.6), cframe = incubator.CFrame * CFrame.new(0, 0.2, 0) }
		)
		if incubatorProp then
			incubatorProp.Name = `IncubatorProp{i}`
			-- The model's glass is baked opaque into its texture; see-through shows the egg inside
			for _, descendant in incubatorProp:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = INCUBATOR_GLASS
				end
			end
		end
		incubators[i] = incubator
		incubatorPads[i] = pad
	end

	-- Cash collector pad, front-right
	local collector = part({
		Name = "Collector",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = origin * CFrame.new(15, TOP + 0.2, -15),
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

	-- Base lock button (front-center)
	local lockButton = part({
		Name = "LockButton",
		Size = Vector3.new(3, 1.2, 3),
		CFrame = origin * CFrame.new(0, TOP + 0.6, -16),
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

	-- Base upgrade station (between the lock and the cash pad)
	local station = part({
		Name = "UpgradeStation",
		Size = Vector3.new(2.4, 3.2, 2.4),
		CFrame = origin * CFrame.new(7.5, TOP + 1.6, -16),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(230, 225, 210),
		Parent = model,
	})
	part({
		Name = "UpgradeGem",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = station.CFrame * CFrame.new(0, 2.5, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 205, 70),
		CanCollide = false,
		Parent = model,
	})
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradeBase"
	upgradePrompt.ActionText = "Upgrade Base"
	upgradePrompt.ObjectText = "Base upgrade"
	upgradePrompt.HoldDuration = 0.4
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt:SetAttribute("VisibleTo", "owner")
	upgradePrompt.Parent = station
	local upgradeLabel = billboard(station, Vector3.new(0, 4.6, 0), UDim2.fromOffset(220, 48), 60)
	upgradeLabel.TextColor3 = Color3.fromRGB(255, 220, 110)
	upgradeLabel.Text = "Base Lv 1"

	-- Laser walls around the plot edge (placed by setLevel)
	local lasers: { BasePart } = {}
	for _ = 1, 4 do
		table.insert(
			lasers,
			part({
				Name = "Laser",
				Size = Vector3.new(1, 7, 0.3),
				CFrame = origin,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 40, 40),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
				Parent = model,
			})
		)
	end

	-- Owner sign at the front edge
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(10, 1, 1),
		CFrame = origin * CFrame.new(0, TOP + 6, PLOT_FRONT + 1),
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
		origin * CFrame.new(0, TOP, PLOT_FRONT + 0.5) * CFrame.Angles(0, math.pi / 2, 0),
		13,
		model
	)

	model.Parent = worldFolder

	local plot: PlotLayout = {
		index = index,
		model = model,
		origin = origin,
		spawn = origin * CFrame.new(0, TOP + 3, -8) * CFrame.Angles(0, math.pi, 0),
		pedestals = pedestals,
		incubators = incubators,
		incubatorPads = incubatorPads,
		collector = collector,
		label = label,
		collectorLabel = collectorLabel,
		lockPrompt = lockPrompt,
		lockLabel = lockLabel,
		upgradePrompt = upgradePrompt,
		upgradeLabel = upgradeLabel,
		lasers = lasers,
		floor = floor,
		trim = trim,
		pedestalParts = pedestalParts,
		pedestalProps = pedestalProps,
		level = 0,
		width = 44,
		depth = 44,
	}
	return plot
end

-- Resizes a plot for a base level: floor, trim, lasers and which pedestals exist.
function WorldService.setLevel(plot: PlotLayout, level: number)
	level = math.clamp(level, 1, #Config.Economy.tunables.baseLevels)
	if plot.level == level then
		return
	end
	plot.level = level
	local width, depth = plotSize(level)
	plot.width, plot.depth = width, depth
	local midZ = PLOT_FRONT + depth / 2
	plot.floor.Size = Vector3.new(width, 1, depth)
	plot.floor.CFrame = plot.origin * CFrame.new(0, 0.5, midZ)

	local halfW = width / 2
	local edges: { { any } } = {
		{ CFrame.new(0, 0, PLOT_FRONT), Vector3.new(width + 1, 1, 1) },
		{ CFrame.new(0, 0, PLOT_FRONT + depth), Vector3.new(width + 1, 1, 1) },
		{ CFrame.new(-halfW, 0, midZ), Vector3.new(1, 1, depth + 1) },
		{ CFrame.new(halfW, 0, midZ), Vector3.new(1, 1, depth + 1) },
	}
	for i, edge in edges do
		local offset: CFrame, size: Vector3 = edge[1], edge[2]
		plot.trim[i].Size = Vector3.new(size.X, 1.3, size.Z)
		plot.trim[i].CFrame = plot.origin * offset * CFrame.new(0, 0.65, 0)
		local laser = plot.lasers[i]
		laser.Size = Vector3.new(if size.X > 1 then size.X else 0.3, 7, if size.Z > 1 then size.Z else 0.3)
		laser.CFrame = plot.origin * offset * CFrame.new(0, 4, 0)
	end

	local count = Config.Economy.baseLevel(level).pedestals
	for i, pedestal in plot.pedestalParts do
		local shown = i <= count
		local prop = plot.pedestalProps[i]
		pedestal.CanCollide = shown
		pedestal.CanQuery = shown
		if prop then
			prop.Parent = if shown then plot.model else nil
			pedestal.Transparency = 1
		else
			pedestal.Transparency = if shown then 0 else 1
		end
		local gui = pedestal:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Enabled = shown
		end
	end
end

-- Restyles a plot with a biome theme: floor, trim, lasers and edge decor.
function WorldService.applyTheme(plot: PlotLayout, theme: Config.BaseTheme)
	if
		plot.model:GetAttribute("Theme") == theme.id
		and plot.model:GetAttribute("ThemeLevel") == plot.level
	then
		return
	end
	plot.model:SetAttribute("Theme", theme.id)
	plot.model:SetAttribute("ThemeLevel", plot.level)
	plot.floor.Material = theme.floorMaterial
	plot.floor.Color = theme.floorColor
	for _, trim in plot.trim do
		trim.Color = theme.trimColor
	end
	for _, laser in plot.lasers do
		laser.Color = theme.laserColor
	end

	local existing = plot.model:FindFirstChild("ThemeDecor")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "ThemeDecor"
	folder.Parent = plot.model
	local available: { string } = {}
	for _, name in theme.decor do
		if Props.template("WorldProps", name) then
			table.insert(available, name)
		end
	end
	if #available == 0 then
		return
	end
	-- Along both sides and the back, just outside the plot edge
	local rng = Random.new(plot.index * 97 + #theme.id)
	local halfW = plot.width / 2
	local spots: { Vector3 } = {}
	for z = PLOT_FRONT + 8, PLOT_FRONT + plot.depth - 2, 9 do
		table.insert(spots, Vector3.new(-halfW - 3.5, 0, z))
		table.insert(spots, Vector3.new(halfW + 3.5, 0, z))
	end
	for x = -halfW + 4, halfW - 4, 9 do
		table.insert(spots, Vector3.new(x, 0, PLOT_FRONT + plot.depth + 3.5))
	end
	for _, spot in spots do
		local name = available[rng:NextInteger(1, #available)]
		local height = if name == "PineTree" then 16 elseif name == "IceSpire" then 8 else 3.5
		local cframe = plot.origin * CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0)
		Props.spawn(name, cframe, height * rng:NextNumber(0.8, 1.2), folder)
	end
end

---------------------------------------------------------------------------
-- Biome zones + decor
---------------------------------------------------------------------------

type Zone = {
	biome: string,
	material: Enum.Material,
	color: Color3,
	terrain: Enum.Material,
	decor: { string },
}
-- One zone in each gap between plots, in biome unlock order
local ZONES: { Zone } = {
	{
		biome = "Mossvale",
		material = Enum.Material.LeafyGrass,
		color = Color3.fromRGB(96, 150, 70),
		terrain = Enum.Material.LeafyGrass,
		decor = { "MossTree", "BerryBush", "MushroomCluster", "FlowerPatch", "FallenLog" },
	},
	{
		biome = "CoralCoast",
		material = Enum.Material.Sand,
		color = Color3.fromRGB(232, 212, 165),
		terrain = Enum.Material.Sand,
		decor = { "CoralCluster", "RockCluster", "CoralCluster" },
	},
	{
		biome = "MagmaRift",
		material = Enum.Material.CrackedLava,
		color = Color3.fromRGB(70, 50, 45),
		terrain = Enum.Material.Basalt,
		decor = { "LavaRock", "LavaRock", "RockCluster" },
	},
	{
		biome = "FrostShelf",
		material = Enum.Material.Snow,
		color = Color3.fromRGB(235, 245, 255),
		terrain = Enum.Material.Snow,
		decor = { "IceSpire", "PineTree", "IceSpire" },
	},
	{
		biome = "StormPeaks",
		material = Enum.Material.Slate,
		color = Color3.fromRGB(100, 105, 125),
		terrain = Enum.Material.Rock,
		decor = { "RockCluster", "PineTree", "RockCluster" },
	},
	{
		biome = "Moonfall",
		material = Enum.Material.Pebble,
		color = Color3.fromRGB(110, 95, 145),
		terrain = Enum.Material.Salt,
		decor = { "CrystalCluster", "CrystalCluster", "RockCluster" },
	},
}

local ZONE_RADIUS = 175 -- distance from the hub
local ZONE_SIZE = 64 -- diameter of each zone's ground patch

local function zoneCenters(): { Vector3 }
	local centers = {}
	local plots = Config.Economy.tunables.basePlotsPerServer
	for i = 1, plots do
		local angle = plotAngle(i) + math.pi / plots
		centers[i] = Vector3.new(math.cos(angle) * ZONE_RADIUS, GROUND_Y, math.sin(angle) * ZONE_RADIUS)
	end
	return centers
end

-- True when a spot would sit on a (max-size) plot or its walkway.
local function onPlotOrWalkway(position: Vector3): boolean
	local maxWidth, maxDepth = plotSize(#Config.Economy.tunables.baseLevels)
	for _, plot in WorldService.plots do
		local localPos = plot.origin:PointToObjectSpace(position)
		if
			math.abs(localPos.X) < maxWidth / 2 + 7
			and localPos.Z > PLOT_FRONT - 7
			and localPos.Z < PLOT_FRONT + maxDepth + 7
		then
			return true
		end
		-- Walkway from the plot's front edge in to the conveyor
		if math.abs(localPos.X) < 13 and localPos.Z < PLOT_FRONT then
			return true
		end
	end
	return false
end

local function buildZones(folder: Folder)
	local terrain = Workspace.Terrain
	local rng = Random.new(6061)
	for i, center in zoneCenters() do
		local zone = ZONES[(i - 1) % #ZONES + 1]
		disc(`{zone.biome}Zone`, center + Vector3.new(0, -0.1, 0), ZONE_SIZE, 0.5, {
			Material = zone.material,
			Color = zone.color,
			CanCollide = false,
			Parent = folder,
		})
		-- A hill behind the zone, out toward the beach
		local outward = Vector3.new(center.X, 0, center.Z).Unit
		terrain:FillBall(center + outward * 52 + Vector3.new(0, -16, 0), 30, zone.terrain)

		local signPart = part({
			Name = "ZoneSign",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(center + Vector3.new(0, 10, 0)),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		local label = billboard(signPart, Vector3.zero, UDim2.fromOffset(240, 44), 260)
		label.Text = Config.Biomes[zone.biome].displayName
		label.TextColor3 = Config.Eggs.eggColors[zone.biome]:Lerp(Color3.new(1, 1, 1), 0.35)

		local available: { string } = {}
		for _, name in zone.decor do
			if Props.template("WorldProps", name) then
				table.insert(available, name)
			end
		end
		if #available > 0 then
			for _ = 1, 14 do
				local angle = rng:NextNumber() * 2 * math.pi
				local distance = rng:NextNumber(6, ZONE_SIZE / 2 - 4)
				local position = center
					+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				if not onPlotOrWalkway(position) then
					local name = available[rng:NextInteger(1, #available)]
					local height = if name == "MossTree" or name == "PineTree"
						then 20
						elseif name == "IceSpire" then 11
						else 5
					Props.spawn(
						name,
						CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0),
						height * rng:NextNumber(0.8, 1.25),
						folder
					)
				end
			end
		end
	end
end

-- General greenery scattered over the island. Deterministic, so every server matches.
local DECOR: { { name: string, height: number, weight: number } } = {
	{ name = "MossTree", height = 22, weight = 5 },
	{ name = "PineTree", height = 20, weight = 3 },
	{ name = "RockCluster", height = 5, weight = 4 },
	{ name = "BerryBush", height = 4, weight = 4 },
	{ name = "FlowerPatch", height = 1.6, weight = 6 },
	{ name = "MushroomCluster", height = 3, weight = 3 },
	{ name = "FallenLog", height = 3, weight = 2 },
}

local function scatterDecor()
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = worldFolder
	buildZones(folder)

	-- Lamp posts ring the conveyor so the egg loop reads at night
	local lampRadius = Config.Eggs.conveyor.radius + 7
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

	-- Stone paths from each plot's front edge to the plaza
	for _, plot in WorldService.plots do
		local from = (plot.origin * CFrame.new(0, 0, PLOT_FRONT)).Position
		local flat = Vector3.new(from.X, 0, from.Z)
		local to = flat.Unit * (Config.Eggs.conveyor.radius + 9) + Vector3.new(0, GROUND_Y, 0)
		local length = (from - to).Magnitude
		part({
			Name = "Path",
			Size = Vector3.new(9, 0.3, length),
			CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, -0.05, 0),
			Material = Enum.Material.Cobblestone,
			Color = Color3.fromRGB(160, 150, 130),
			CanCollide = false,
			Parent = folder,
		})
	end

	local available: { { name: string, height: number, weight: number } } = {}
	local total = 0
	for _, entry in DECOR do
		if Props.template("WorldProps", entry.name) then
			table.insert(available, entry)
			total += entry.weight
		end
	end
	if total == 0 then
		return
	end
	local zones = zoneCenters()
	local rng = Random.new(20260929)
	local placed = 0
	local attempts = 0
	while placed < 150 and attempts < 2000 do
		attempts += 1
		local angle = rng:NextNumber() * 2 * math.pi
		local radius = rng:NextNumber(Config.Eggs.conveyor.radius + 14, ISLAND_RADIUS - 8)
		local position = Vector3.new(math.cos(angle) * radius, GROUND_Y, math.sin(angle) * radius)
		local roll = rng:NextNumber() * total
		local pick = available[1]
		for _, entry in available do
			roll -= entry.weight
			if roll <= 0 then
				pick = entry
				break
			end
		end
		local height = pick.height * rng:NextNumber(0.75, 1.3)
		local blocked = onPlotOrWalkway(position)
		-- Keep the biome zones clear, including a big tree's canopy hanging over the
		-- patch edge (green forest trees were shading the Coral and Magma patches)
		local margin = 2 + height * 0.45
		for _, zoneCenter in zones do
			if (position - zoneCenter).Magnitude < ZONE_SIZE / 2 + margin then
				blocked = true
			end
		end
		if blocked then
			continue
		end
		local cframe = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0)
		if Props.spawn(pick.name, cframe, height, folder) then
			placed += 1
		end
	end
end

-- True when a world position is inside the plot's current footprint (any height).
function WorldService.isInsidePlot(plot: PlotLayout, position: Vector3): boolean
	local localPos = plot.origin:PointToObjectSpace(position)
	return math.abs(localPos.X) <= plot.width / 2
		and localPos.Z >= PLOT_FRONT
		and localPos.Z <= PLOT_FRONT + plot.depth
		and localPos.Y < 40
end

-- Just outside the front edge of a plot (where the laser gate pushes intruders).
function WorldService.outsideFront(plot: PlotLayout): CFrame
	return plot.origin * CFrame.new(0, 4, PLOT_FRONT - 6)
end

function WorldService.start()
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = Workspace

	setupLighting()
	buildSeaAndIsland()
	buildHub()
	for i = 1, Config.Economy.tunables.basePlotsPerServer do
		local plot = buildPlot(i)
		table.insert(WorldService.plots, plot)
		WorldService.setLevel(plot, 1)
		WorldService.applyTheme(plot, Config.Progression.themes[1])
	end
	scatterDecor()
end

return WorldService

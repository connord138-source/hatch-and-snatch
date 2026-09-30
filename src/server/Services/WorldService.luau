--!strict
-- Builds Crackpoint Island from code: a round grass island with a beach and sea,
-- the hub reactor, the egg conveyor (eggs roll out of and back into the hatchery
-- tunnel), the Moon Egg, a walled biome zone between each pair of plots (gate,
-- harvest nodes, shrine — ZoneService runs them), lighting, and
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
local SetPieces = require(script.Parent.Parent.SetPieces)

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
	deckParts: { BasePart },
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

export type LuckWheel = {
	disc: Model, -- the spinning part; rotate with base * CFrame.Angles(0, 0, angle)
	base: CFrame, -- wheel center, -Z facing the hub
	prompt: ProximityPrompt,
	sign: TextLabel,
}

local WorldService = {
	plots = {} :: { PlotLayout },
	luckWheel = nil :: LuckWheel?,
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
-- Levels 4-5 add the upper deck instead of more depth.
local PLOT_WIDTHS = { 60, 64, 68, 72, 76 }
local PLOT_DEPTHS = { 48, 56, 68, 68, 68 }
local function plotSize(level: number): (number, number)
	local i = math.clamp(level, 1, #PLOT_WIDTHS)
	return PLOT_WIDTHS[i], PLOT_DEPTHS[i]
end

-- Upper deck (base level 4+): a floor over the back of the plot, reached by a ramp
-- on the right side, so creatures up there take a longer run to steal.
local DECK_LEVEL = 4
local DECK_TOP = 15 -- deck floor height above the plot floor
local DECK_X = 28 -- half width
local DECK_Z0, DECK_Z1 = 2, 46
local PEDESTAL_SPACING = 11

-- Where pedestal `i` stands, relative to the plot origin (center of its top face
-- minus 0.7): 1-20 on the ground in rows of 5, 21-30 on the deck.
local function pedestalPosition(i: number): Vector3
	local column = (i - 1) % 5
	local x = -22 + column * PEDESTAL_SPACING
	if i <= 20 then
		local row = (i - 1) // 5
		return Vector3.new(x, TOP + 0.7, 6 + row * PEDESTAL_SPACING)
	end
	local row = (i - 21) // 5
	return Vector3.new(x, TOP + DECK_TOP + 0.7, 12 + row * 16)
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
	-- A hint of the moon's color, not a wash over everything
	local target = if color then color:Lerp(Color3.new(1, 1, 1), 0.85) else Color3.new(1, 1, 1)
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

-- The Luck Wheel: a big upright wheel on a stone stand beside the plaza, facing
-- the hub. Its slices match Config.Economy.tunables.luckWheel (slice i is centered
-- (i - 1) × 60° clockwise from the top); WheelService spins it.
local WHEEL_RADIUS = 9
local WHEEL_HEIGHT = 12.5

local function buildLuckWheel()
	local angle = math.rad(210)
	local ground = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 76 + Vector3.new(0, GROUND_Y, 0)
	local base =
		CFrame.lookAt(ground + Vector3.new(0, WHEEL_HEIGHT, 0), Vector3.new(0, GROUND_Y + WHEEL_HEIGHT, 0))
	local folder = Instance.new("Model")
	folder.Name = "LuckWheel"
	folder.Parent = worldFolder

	-- Stand
	local plinth = part({
		Name = "WheelPlinth",
		Size = Vector3.new(20, 1.4, 10),
		CFrame = CFrame.lookAt(ground + Vector3.new(0, 0.7, 0), Vector3.new(0, GROUND_Y + 0.7, 0)),
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(140, 130, 120),
		Parent = folder,
	})
	part({
		Name = "WheelPost",
		Size = Vector3.new(2.2, WHEEL_HEIGHT, 2.2),
		CFrame = base * CFrame.new(0, -WHEEL_HEIGHT / 2 + 0.7, 1.6),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 75, 45),
		Parent = folder,
	})
	part({
		Name = "WheelPointer",
		Size = Vector3.new(1.4, 2.4, 0.8),
		CFrame = base * CFrame.new(0, WHEEL_RADIUS + 1.1, -0.9),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 60, 60),
		Parent = folder,
	})

	-- The disc (everything that spins)
	local disc = Instance.new("Model")
	disc.Name = "WheelDisc"
	local hub = part({
		Name = "Hub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 3.4, 3.4),
		CFrame = base * CFrame.new(0, 0, -0.5) * CFrame.Angles(0, math.pi / 2, 0),
		Material = Enum.Material.Foil,
		Color = Color3.fromRGB(255, 200, 70),
		Parent = disc,
	})
	part({
		Name = "Backing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, WHEEL_RADIUS * 2 + 1.2, WHEEL_RADIUS * 2 + 1.2),
		CFrame = base * CFrame.new(0, 0, 0.3) * CFrame.Angles(0, math.pi / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(35, 30, 40),
		Parent = disc,
	})
	local segments = Config.Economy.tunables.luckWheel
	local slice = 2 * math.pi / #segments
	local spokeLength = WHEEL_RADIUS - 1.6
	for i, segment in segments do
		local center = (i - 1) * slice
		-- Each slice is a fan of spokes; a spoke's +Y points out from the hub
		for k = -2, 2 do
			local theta = center + k * slice / 5.5
			part({
				Name = "Slice",
				Size = Vector3.new(2.1, spokeLength, 0.4),
				CFrame = base * CFrame.Angles(0, 0, -theta) * CFrame.new(0, 1.6 + spokeLength / 2, -0.1),
				Material = Enum.Material.SmoothPlastic,
				Color = segment.color,
				CanCollide = false,
				Parent = disc,
			})
		end
		local labelPart = part({
			Name = "SliceLabel",
			Size = Vector3.new(5, 1.6, 0.2),
			CFrame = base * CFrame.Angles(0, 0, -center) * CFrame.new(0, WHEEL_RADIUS * 0.62, -0.45),
			Transparency = 1,
			CanCollide = false,
			Parent = disc,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(250, 80)
		gui.Parent = labelPart
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.2
		text.Text = segment.label
		text.Parent = gui
	end
	-- Bulbs around the rim
	for i = 0, 23 do
		local theta = i / 24 * 2 * math.pi
		part({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7),
			CFrame = base * CFrame.Angles(0, 0, -theta) * CFrame.new(0, WHEEL_RADIUS + 0.3, -0.2),
			Material = Enum.Material.Neon,
			Color = if i % 2 == 0 then Color3.fromRGB(255, 230, 150) else Color3.fromRGB(255, 120, 80),
			CanCollide = false,
			Parent = disc,
		})
	end
	disc.PrimaryPart = hub
	disc.WorldPivot = base
	disc:SetAttribute("BaseCFrame", base)
	disc:SetAttribute("Angle", 0)
	disc.Parent = folder

	-- Sign with the real odds (slices are drawn equal)
	local total = 0
	for _, segment in segments do
		total += segment.weight
	end
	local odds = {}
	for _, segment in segments do
		table.insert(odds, `{segment.label} {math.floor(segment.weight / total * 100 + 0.5)}%`)
	end
	local signPart = part({
		Name = "WheelSign",
		Size = Vector3.new(1, 1, 1),
		CFrame = base * CFrame.new(0, WHEEL_RADIUS + 4.5, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	local sign = billboard(signPart, Vector3.zero, UDim2.fromOffset(320, 70), 140)
	sign.RichText = true
	sign.Text = `🎡 LUCK WHEEL\n<font size="14">{table.concat(odds, " · ")}</font>`
	sign.TextColor3 = Color3.fromRGB(255, 225, 120)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinWheel"
	prompt.ActionText = "Spin (1 spin)"
	prompt.ObjectText = "Luck Wheel"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = plinth

	WorldService.luckWheel = { disc = disc, base = base, prompt = prompt, sign = sign }
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
		local localPos = pedestalPosition(i)
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

	-- Upper deck, its rails and the ramp up to it (shown from base level 4)
	local deckParts: { BasePart } = {}
	local deckColor = Color3.fromRGB(120, 95, 70)
	local function deckPart(name: string, size: Vector3, offset: CFrame)
		table.insert(
			deckParts,
			part({
				Name = name,
				Size = size,
				CFrame = origin * offset,
				Material = Enum.Material.WoodPlanks,
				Color = deckColor,
				Parent = model,
			})
		)
	end
	local deckMidZ = (DECK_Z0 + DECK_Z1) / 2
	local deckDepth = DECK_Z1 - DECK_Z0
	deckPart("Deck", Vector3.new(DECK_X * 2, 1, deckDepth), CFrame.new(0, TOP + DECK_TOP - 0.5, deckMidZ))
	-- Rails (open at the front-right corner where the ramp arrives)
	deckPart("DeckRail", Vector3.new(DECK_X * 2 - 6, 3, 0.6), CFrame.new(-3, TOP + DECK_TOP + 1.5, DECK_Z0))
	deckPart("DeckRail", Vector3.new(DECK_X * 2, 3, 0.6), CFrame.new(0, TOP + DECK_TOP + 1.5, DECK_Z1))
	deckPart("DeckRail", Vector3.new(0.6, 3, deckDepth), CFrame.new(-DECK_X, TOP + DECK_TOP + 1.5, deckMidZ))
	deckPart(
		"DeckRail",
		Vector3.new(0.6, 3, deckDepth - 10),
		CFrame.new(DECK_X, TOP + DECK_TOP + 1.5, deckMidZ + 5)
	)
	-- Support posts
	for _, corner in { Vector2.new(-1, 0), Vector2.new(1, 0), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		deckPart(
			"DeckPost",
			Vector3.new(1.6, DECK_TOP, 1.6),
			CFrame.new(
				corner.X * (DECK_X - 1),
				TOP + DECK_TOP / 2,
				if corner.Y == 0 then DECK_Z0 + 1 else DECK_Z1 - 1
			)
		)
	end
	-- Ramp from the front-right up to the deck's open corner
	local rampFrom = Vector3.new(DECK_X + 3, TOP, -16)
	local rampTo = Vector3.new(DECK_X + 3, TOP + DECK_TOP, DECK_Z0 + 6)
	local rampLength = (rampTo - rampFrom).Magnitude
	deckPart(
		"Ramp",
		Vector3.new(6, 1, rampLength),
		CFrame.lookAt((rampFrom + rampTo) / 2, rampTo) * CFrame.new(0, -0.5, 0)
	)
	deckPart(
		"RampLanding",
		Vector3.new(7, 1, 10),
		CFrame.new(DECK_X + 0.5, TOP + DECK_TOP - 0.5, DECK_Z0 + 8)
	)

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
		deckParts = deckParts,
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
		-- Lasers grow tall enough to cover the deck once it exists
		local laserHeight = if level >= DECK_LEVEL then DECK_TOP + 8 else 7
		local laser = plot.lasers[i]
		laser.Size =
			Vector3.new(if size.X > 1 then size.X else 0.3, laserHeight, if size.Z > 1 then size.Z else 0.3)
		laser.CFrame = plot.origin * offset * CFrame.new(0, 0.5 + laserHeight / 2, 0)
	end

	local hasDeck = level >= DECK_LEVEL
	for _, deckPiece in plot.deckParts do
		deckPiece.Transparency = if hasDeck then 0 else 1
		deckPiece.CanCollide = hasDeck
		deckPiece.CanQuery = hasDeck
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
	wall: Enum.Material,
	wallColor: Color3,
	decor: { string },
	-- Hero set pieces (SetPieces.luau): angle in degrees from the gate direction and
	-- distance from the zone center, same layout as the harvest nodes
	heroes: { { name: string, angle: number, distance: number, scale: number? } },
}
-- One zone in each gap between plots, in biome unlock order
local ZONES: { Zone } = {
	{
		biome = "Mossvale",
		material = Enum.Material.LeafyGrass,
		color = Color3.fromRGB(96, 150, 70),
		terrain = Enum.Material.LeafyGrass,
		wall = Enum.Material.WoodPlanks,
		wallColor = Color3.fromRGB(120, 85, 55),
		decor = { "MossTree", "BerryBush", "MushroomCluster", "FlowerPatch", "FallenLog" },
		heroes = {
			{ name = "GlowcapRing", angle = 0, distance = 0 },
			{ name = "HollowStump", angle = 67.5, distance = 35 },
		},
	},
	{
		biome = "CoralCoast",
		material = Enum.Material.Sand,
		color = Color3.fromRGB(232, 212, 165),
		terrain = Enum.Material.Sand,
		wall = Enum.Material.Sandstone,
		wallColor = Color3.fromRGB(215, 190, 150),
		decor = { "CoralCluster", "RockCluster", "CoralCluster" },
		heroes = {
			{ name = "TideArch", angle = 0, distance = 17 },
			{ name = "GiantClam", angle = 292.5, distance = 35 },
		},
	},
	{
		biome = "MagmaRift",
		material = Enum.Material.CrackedLava,
		color = Color3.fromRGB(70, 50, 45),
		terrain = Enum.Material.Basalt,
		wall = Enum.Material.Basalt,
		wallColor = Color3.fromRGB(55, 45, 45),
		decor = { "LavaRock", "LavaRock", "RockCluster" },
		heroes = {
			{ name = "LavaVent", angle = 180, distance = 7 },
			{ name = "ObsidianSpikes", angle = 67.5, distance = 35 },
		},
	},
	{
		biome = "FrostShelf",
		material = Enum.Material.Snow,
		color = Color3.fromRGB(235, 245, 255),
		terrain = Enum.Material.Snow,
		wall = Enum.Material.Ice,
		wallColor = Color3.fromRGB(175, 215, 240),
		decor = { "IceSpire", "PineTree", "IceSpire" },
		heroes = {
			{ name = "IceArch", angle = 0, distance = 17 },
			{ name = "FrozenBoulder", angle = 292.5, distance = 35 },
		},
	},
	{
		biome = "StormPeaks",
		material = Enum.Material.Slate,
		color = Color3.fromRGB(100, 105, 125),
		terrain = Enum.Material.Rock,
		wall = Enum.Material.Slate,
		wallColor = Color3.fromRGB(80, 85, 100),
		decor = { "RockCluster", "PineTree", "RockCluster" },
		heroes = {
			{ name = "LightningCrag", angle = 180, distance = 7 },
			{ name = "WindSpire", angle = 67.5, distance = 36 },
			{ name = "WindSpire", angle = 292.5, distance = 37, scale = 0.75 },
		},
	},
	{
		biome = "Moonfall",
		material = Enum.Material.Pebble,
		color = Color3.fromRGB(110, 95, 145),
		terrain = Enum.Material.Salt,
		wall = Enum.Material.Marble,
		wallColor = Color3.fromRGB(90, 80, 125),
		decor = { "CrystalCluster", "CrystalCluster", "RockCluster" },
		heroes = {
			{ name = "MoonMonolith", angle = 180, distance = 7 },
			{ name = "CraterRim", angle = 292.5, distance = 35, scale = 0.85 },
			{ name = "MoonMonolith", angle = 67.5, distance = 37, scale = 0.55 },
		},
	},
}

-- What ZoneService needs: the walled area, where to bounce locked-out players,
-- the gate (its label shows the requirement), harvest nodes and the shrine.
export type ZoneLayout = {
	biome: string,
	center: Vector3,
	radius: number, -- inside the wall
	outside: CFrame, -- just outside the gate, facing away from it
	gate: BasePart,
	gateLabel: TextLabel,
	nodes: { Model }, -- PrimaryPart is the rock the prompt sits on; "Crystal" parts hide when picked
	shrine: BasePart,
	shrineLabel: TextLabel,
}
WorldService.zones = {} :: { ZoneLayout }

local ZONE_RADIUS = 195 -- distance from the hub
local ZONE_SIZE = 88 -- diameter of each zone's ground patch
local WALL_RADIUS = ZONE_SIZE / 2 + 2
local WALL_HEIGHT = 11
local WALL_SEGMENTS = 24
local GATE_WIDTH = 12

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
	local wheel = WorldService.luckWheel
	if wheel then
		local offset = position - wheel.base.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < 18 then
			return true -- keep the Luck Wheel's stand clear
		end
	end
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

-- A harvest node: a rock with glowing crystals on top. Picking it hides the crystals.
local function buildNode(cframe: CFrame, color: Color3, rng: Random, folder: Instance): Model
	local model = Instance.new("Model")
	model.Name = "HarvestNode"
	local rock = part({
		Name = "Rock",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.5, 4.5, 4.5),
		CFrame = cframe * CFrame.new(0, -0.6, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(85, 85, 95),
		Parent = model,
	})
	for i = 1, 3 do
		local lean = CFrame.Angles(rng:NextNumber(-0.45, 0.45), i * 2.1, rng:NextNumber(-0.45, 0.45))
		part({
			Name = "Crystal",
			Size = Vector3.new(0.9, rng:NextNumber(2.6, 4), 0.9),
			CFrame = cframe * CFrame.new(0, 1.8, 0) * lean * CFrame.new(0.5, 0.8, 0),
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
			Parent = model,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0.6
	light.Range = 8
	light.Parent = rock
	model.PrimaryPart = rock
	model.Parent = folder
	return model
end

local function buildZones(folder: Folder)
	local terrain = Workspace.Terrain
	local rng = Random.new(6061)
	for i, center in zoneCenters() do
		local zone = ZONES[(i - 1) % #ZONES + 1]
		local biomeColor = Config.Eggs.eggColors[zone.biome]
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = `{zone.biome}Zone`
		zoneFolder.Parent = folder
		disc("Ground", center + Vector3.new(0, -0.1, 0), ZONE_SIZE, 0.5, {
			Material = zone.material,
			Color = zone.color,
			CanCollide = false,
			Parent = zoneFolder,
		})
		-- A hill behind the zone, out toward the beach (clear of the wall)
		local outward = Vector3.new(center.X, 0, center.Z).Unit
		local inward = -outward
		terrain:FillBall(center + outward * 72 + Vector3.new(0, -18, 0), 26, zone.terrain)

		-- Wall ring with a gap for the gate on the side facing the hub
		local inwardAngle = math.atan2(inward.Z, inward.X)
		local step = 2 * math.pi / WALL_SEGMENTS
		local length = 2 * WALL_RADIUS * math.sin(step / 2) + 0.6
		for s = 1, WALL_SEGMENTS - 1 do
			local angle = inwardAngle + s * step
			local position = center
				+ Vector3.new(math.cos(angle) * WALL_RADIUS, WALL_HEIGHT / 2, math.sin(angle) * WALL_RADIUS)
			part({
				Name = "Wall",
				Size = Vector3.new(length, WALL_HEIGHT, 2.5),
				CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)),
				Material = zone.wall,
				Color = zone.wallColor,
				Parent = zoneFolder,
			})
		end

		-- Gate: two pillars, a lintel and a shimmering barrier across the gap
		local gateCenter = center + inward * WALL_RADIUS
		local gateFrame = CFrame.lookAt(gateCenter, gateCenter + inward) -- -Z faces the hub
		for _, side in { -1, 1 } do
			part({
				Name = "GatePillar",
				Size = Vector3.new(3, WALL_HEIGHT + 4, 3.5),
				CFrame = gateFrame * CFrame.new(side * (GATE_WIDTH / 2 + 1.5), (WALL_HEIGHT + 4) / 2, 0),
				Material = zone.wall,
				Color = zone.wallColor:Lerp(Color3.new(0, 0, 0), 0.2),
				Parent = zoneFolder,
			})
		end
		local lintel = part({
			Name = "GateLintel",
			Size = Vector3.new(GATE_WIDTH + 6, 2.5, 3.5),
			CFrame = gateFrame * CFrame.new(0, WALL_HEIGHT + 5, 0),
			Material = zone.wall,
			Color = zone.wallColor:Lerp(Color3.new(0, 0, 0), 0.2),
			Parent = zoneFolder,
		})
		local gate: BasePart = part({
			Name = "ZoneGate",
			Size = Vector3.new(GATE_WIDTH, WALL_HEIGHT + 3, 0.6),
			CFrame = gateFrame * CFrame.new(0, (WALL_HEIGHT + 3) / 2, 0),
			Material = Enum.Material.ForceField,
			Color = Color3.fromRGB(255, 90, 90),
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Parent = zoneFolder,
		})
		gate:SetAttribute("Biome", zone.biome)
		local gateLabel = billboard(lintel, Vector3.new(0, 4.5, 0), UDim2.fromScale(20, 4), 160)
		gateLabel.Text = Config.Biomes[zone.biome].displayName
		gateLabel.TextColor3 = biomeColor:Lerp(Color3.new(1, 1, 1), 0.35)

		-- Shrine at the back of the zone
		local shrineAt = center + outward * (WALL_RADIUS - 12)
		local shrineFrame = CFrame.lookAt(shrineAt, center)
		part({
			Name = "ShrineStep",
			Size = Vector3.new(12, 1.2, 10),
			CFrame = shrineFrame * CFrame.new(0, 0.6, 0),
			Material = Enum.Material.Slate,
			Color = zone.wallColor,
			Parent = zoneFolder,
		})
		local shrine: BasePart = part({
			Name = "Shrine",
			Size = Vector3.new(5, 6, 3),
			CFrame = shrineFrame * CFrame.new(0, 4.2, 0),
			Material = Enum.Material.Marble,
			Color = zone.wallColor:Lerp(Color3.new(1, 1, 1), 0.4),
			Parent = zoneFolder,
		})
		part({
			Name = "ShrineOrb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			CFrame = shrineFrame * CFrame.new(0, 8.8, 0),
			Material = Enum.Material.Neon,
			Color = biomeColor,
			CanCollide = false,
			Parent = zoneFolder,
		})
		local shrineLabel = billboard(shrine, Vector3.new(0, 8, 0), UDim2.fromScale(14, 3.2), 70)
		shrineLabel.Text = `{Config.Zones.byBiome[zone.biome].essence} Shrine`
		shrineLabel.TextColor3 = biomeColor:Lerp(Color3.new(1, 1, 1), 0.35)

		-- Harvest nodes spread around the inner ring, leaving the gate path clear
		local nodes: { Model } = {}
		local count = Config.Zones.nodesPerZone
		for n = 1, count do
			local angle = inwardAngle + math.rad(45) + (n - 1) / (count - 1) * math.rad(270)
			local distance = if n % 2 == 0 then 22 else 32
			local position = center + Vector3.new(math.cos(angle) * distance, 1, math.sin(angle) * distance)
			local node = buildNode(CFrame.new(position), biomeColor, rng, zoneFolder)
			node:SetAttribute("Biome", zone.biome)
			table.insert(nodes, node)
		end

		table.insert(WorldService.zones, {
			biome = zone.biome,
			center = center,
			radius = WALL_RADIUS - 1,
			outside = CFrame.lookAt(
				gateCenter + inward * 8 + Vector3.new(0, 3, 0),
				gateCenter + inward * 20 + Vector3.new(0, 3, 0)
			),
			gate = gate,
			gateLabel = gateLabel,
			nodes = nodes,
			shrine = shrine,
			shrineLabel = shrineLabel,
		})

		-- Hero set pieces: side ones face the middle, central ones face the gate
		local heroSpots: { { position: Vector3, radius: number } } = {}
		for _, hero in zone.heroes do
			local angle = inwardAngle + math.rad(hero.angle)
			local position = center
				+ Vector3.new(math.cos(angle) * hero.distance, 0, math.sin(angle) * hero.distance)
			local facing = if hero.distance > 20 then center else gateCenter
			local frame = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
			local radius = SetPieces.build(hero.name, frame, hero.scale or 1, zoneFolder, rng)
			table.insert(heroSpots, { position = position, radius = radius })
		end

		-- Decor inside the walls, clear of the nodes, the shrine, the set pieces and the gate path
		local available: { string } = {}
		for _, name in zone.decor do
			if Props.template("WorldProps", name) then
				table.insert(available, name)
			end
		end
		if #available > 0 then
			local placed = 0
			for _ = 1, 120 do
				if placed >= 26 then
					break
				end
				local angle = rng:NextNumber() * 2 * math.pi
				local distance = rng:NextNumber(6, WALL_RADIUS - 5)
				local position = center
					+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				local blocked = (position - shrineAt).Magnitude < 11
				local fromCenter = position - center
				-- The walk from the gate to the middle
				if
					fromCenter:Dot(inward) > 0
					and (fromCenter - inward * fromCenter:Dot(inward)).Magnitude < 9
				then
					blocked = true
				end
				for _, node in nodes do
					local nodePos = (node.PrimaryPart :: BasePart).Position
					if (Vector3.new(nodePos.X, position.Y, nodePos.Z) - position).Magnitude < 6 then
						blocked = true
					end
				end
				for _, spot in heroSpots do
					if (position - spot.position).Magnitude < spot.radius + 3 then
						blocked = true
					end
				end
				if not blocked then
					local name = available[rng:NextInteger(1, #available)]
					local height = if name == "MossTree" or name == "PineTree"
						then 20
						elseif name == "IceSpire" then 11
						else 5
					Props.spawn(
						name,
						CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0),
						height * rng:NextNumber(0.8, 1.25),
						zoneFolder
					)
					placed += 1
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
			if (position - zoneCenter).Magnitude < WALL_RADIUS + margin then
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
	buildLuckWheel()
	for i = 1, Config.Economy.tunables.basePlotsPerServer do
		local plot = buildPlot(i)
		table.insert(WorldService.plots, plot)
		WorldService.setLevel(plot, 1)
		WorldService.applyTheme(plot, Config.Progression.themes[1])
	end
	scatterDecor()
end

return WorldService

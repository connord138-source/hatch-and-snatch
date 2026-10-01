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
	pedestals: { [number]: CFrame }, -- where creatures stand, by slot (Config.Economy.slots)
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
	pedestalParts: { [number]: BasePart },
	pedestalProps: { [number]: Model? },
	floorPieces: { FloorPiece }, -- the floors above the ground, their walls and ramps
	vaults: { VaultRoom },
	level: number,
	floors: number, -- floors shown, counting the ground
	width: number,
	depth: number,
}

-- A part of the floors above the ground: shown while the base has `from`+ floors
-- (and at most `to`), at its own transparency (glass walls are see-through).
export type FloorPiece = { part: BasePart, from: number, to: number?, transparency: number, vault: number? }

-- A vault room: one pedestal behind a door the owner locks (StealService).
export type VaultRoom = {
	floor: number,
	door: BasePart,
	label: TextLabel,
	prompt: ProximityPrompt,
	minX: number, -- interior bounds, plot-local
	maxX: number,
	minZ: number,
	maxZ: number,
	owned: boolean,
	locked: boolean,
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
-- Levels 4-5 keep the depth: the floors above (setFloors) give the room instead.
local PLOT_WIDTHS = { 60, 64, 68, 72, 76 }
local PLOT_DEPTHS = { 48, 56, 68, 68, 68 }
local function plotSize(level: number): (number, number)
	local i = math.clamp(level, 1, #PLOT_WIDTHS)
	return PLOT_WIDTHS[i], PLOT_DEPTHS[i]
end

-- Floors above the ground (Config.Economy.tunables.floors): stacked slabs over the
-- back of the plot, FLOOR_HEIGHT apart (beyond a Steal prompt's reach), with glass
-- walls too tall to jump and ramps up the sides, so thieves have to walk up and
-- carry the creature back down. The Second Floor's ramp climbs the right side from
-- the front; the Top Floor's climbs the left side from the Second Floor. Each floor
-- has a vault room in each back corner.
local FLOOR_HEIGHT = 18
local FLOOR_X = 28 -- half width
local FLOOR_Z0: { [number]: number } = { [2] = 2, [3] = 14 } -- front edges (the top floor is set back)
local FLOOR_Z1 = 46
local FLOOR_ROW_Z: { [number]: number } = { [2] = 20, [3] = 22 } -- the pedestal row on each floor
local FLOOR_WALL = 9 -- taller than a jump
local WALL_GLASS = 0.6
local VAULT_SIZE = 11 -- inside width and depth of a vault room
local VAULT_Z0 = FLOOR_Z1 - 1 - VAULT_SIZE -- vault front walls
local DOOR_WIDTH = 6
local PEDESTAL_SPACING = 11
local GROUND_SLOTS = Config.Economy.groundSlots

local function floorTop(floor: number): number
	return TOP + (floor - 1) * FLOOR_HEIGHT
end

-- A vault's floor, side (-1 left, 1 right) and center, plot-local.
local function vaultLayout(vault: number): (number, number, Vector3)
	local floor = Config.Economy.tunables.vaults[vault].floor
	local side = if vault % 2 == 1 then -1 else 1
	local centerX = side * (FLOOR_X - 1 - VAULT_SIZE / 2)
	return floor, side, Vector3.new(centerX, floorTop(floor), VAULT_Z0 + VAULT_SIZE / 2)
end

-- Where pedestal slot `i` stands, relative to the plot origin (center of its top
-- face minus 0.7): 1-20 on the ground in rows of 5, then a row of 5 on each floor
-- above, and the vaults (Config.Economy.slots).
local function pedestalPosition(i: number): Vector3
	local vault = Config.Economy.vaultOfSlot(i)
	if vault then
		local _, _, center = vaultLayout(vault)
		return center + Vector3.new(0, 0.7, 0)
	end
	local column = (i - 1) % 5
	local x = -22 + column * PEDESTAL_SPACING
	if i <= GROUND_SLOTS then
		local row = (i - 1) // 5
		return Vector3.new(x, TOP + 0.7, 6 + row * PEDESTAL_SPACING)
	end
	local floor = Config.Economy.slotFloor(i)
	return Vector3.new(x, floorTop(floor) + 0.7, FLOOR_ROW_Z[floor] or 20)
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

	-- An invisible wall at the beach's outer edge keeps players out of the sea (owner,
	-- 2026-10-01: the open ocean is the border, but swimming out showed where the map
	-- ends). Too tall to jump; ignored by raycasts, so the camera and grabs see through
	-- it. A bridge or dock to a future island would leave a gap here.
	local shore = ISLAND_RADIUS + 21
	local segments = 48
	local width = 2 * shore * math.sin(math.pi / segments) + 1
	for i = 1, segments do
		local angle = (i / segments) * 2 * math.pi
		part({
			Name = "ShoreWall",
			Size = Vector3.new(width, 80, 2),
			CFrame = CFrame.new(math.cos(angle) * shore, GROUND_Y + 36, math.sin(angle) * shore)
				* CFrame.Angles(0, math.pi / 2 - angle, 0),
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = worldFolder,
		})
	end
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
	-- A model with a PrimaryPart ignores WorldPivot and pivots on the primary part,
	-- so move the hub's pivot to the wheel's center (the hub itself is turned 90°)
	hub.PivotOffset = hub.CFrame:ToObjectSpace(base)
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

	-- Pedestals: rows of 5 from the front of the back area, one row per base level,
	-- then the floors' rows and the vaults (shown by setFloors)
	local allSlots = Config.Economy.slots(
		#Config.Economy.tunables.baseLevels,
		#Config.Economy.tunables.floors + 1,
		#Config.Economy.tunables.vaults
	)
	local pedestals: { [number]: CFrame } = {}
	local pedestalParts: { [number]: BasePart } = {}
	local pedestalProps: { [number]: Model? } = {}
	for _, i in allSlots do
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
		pedestal:SetAttribute("Nursery", isNursery)
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

	-- The floors above the ground, their glass walls, ramps and vault rooms (setFloors
	-- shows what the owner has bought)
	local floorPieces: { FloorPiece } = {}
	local function piece(
		from: number,
		to: number?,
		name: string,
		size: Vector3,
		offset: CFrame,
		glass: boolean?,
		vault: number?
	): Part
		local p = part({
			Name = name,
			Size = size,
			CFrame = origin * offset,
			Material = if glass then Enum.Material.Glass else Enum.Material.WoodPlanks,
			Color = if glass then Color3.fromRGB(200, 230, 255) else Color3.fromRGB(120, 95, 70),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		p:SetAttribute("Glass", glass == true)
		local entry: FloorPiece = {
			part = p :: BasePart,
			from = from,
			to = to,
			transparency = if glass then WALL_GLASS else 0,
			vault = vault,
		}
		table.insert(floorPieces, entry)
		return p
	end
	-- A wall along x (from x0 to x1 at z) or along z (from z0 to z1 at x), standing on a floor
	local function wallX(from: number, to: number?, x0: number, x1: number, z: number, top: number)
		piece(
			from,
			to,
			"FloorWall",
			Vector3.new(math.abs(x1 - x0), FLOOR_WALL, 0.4),
			CFrame.new((x0 + x1) / 2, top + FLOOR_WALL / 2, z),
			true
		)
	end
	local function wallZ(
		from: number,
		to: number?,
		z0: number,
		z1: number,
		x: number,
		top: number,
		vault: number?
	)
		piece(
			from,
			to,
			if vault then "VaultWall" else "FloorWall",
			Vector3.new(0.4, FLOOR_WALL, math.abs(z1 - z0)),
			CFrame.new(x, top + FLOOR_WALL / 2, (z0 + z1) / 2),
			true,
			vault
		)
	end
	-- A ramp between two points, with glass walls on both sides. The walls stand
	-- upright in steps, each at least FLOOR_WALL above the ramp along its whole
	-- length (a wall tilted with the ramp would sink low enough to hop near the top).
	local RAMP_STEPS = 4
	local function ramp(from: number, a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local frame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0)
		piece(from, nil, "Ramp", Vector3.new(6, 1, length), frame)
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local along = flat.Unit
		local right = along:Cross(Vector3.yAxis)
		for step = 0, RAMP_STEPS - 1 do
			local p0 = a:Lerp(b, step / RAMP_STEPS)
			local p1 = a:Lerp(b, (step + 1) / RAMP_STEPS)
			local bottom = p0.Y - 1
			local height = p1.Y + FLOOR_WALL - bottom
			local mid = Vector3.new((p0.X + p1.X) / 2, bottom + height / 2, (p0.Z + p1.Z) / 2)
			for _, side in { -1, 1 } do
				local at = mid + right * side * 3.2
				piece(
					from,
					nil,
					"RampWall",
					Vector3.new(0.4, height, flat.Magnitude / RAMP_STEPS + 0.05),
					CFrame.lookAt(at, at + along),
					true
				)
			end
		end
	end

	for story = 2, #Config.Economy.tunables.floors + 1 do
		local top = floorTop(story)
		local z0 = FLOOR_Z0[story]
		local depth = FLOOR_Z1 - z0
		local midZ = (z0 + FLOOR_Z1) / 2
		piece(story, nil, "Floor", Vector3.new(FLOOR_X * 2, 1, depth), CFrame.new(0, top - 0.5, midZ))
		-- Support posts down to the floor below
		for _, corner in { Vector2.new(-1, 0), Vector2.new(1, 0), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			piece(
				story,
				nil,
				"FloorPost",
				Vector3.new(1.6, FLOOR_HEIGHT, 1.6),
				CFrame.new(
					corner.X * (FLOOR_X - 1),
					top - FLOOR_HEIGHT / 2,
					if corner.Y == 0 then z0 + 1 else FLOOR_Z1 - 1
				)
			)
		end
		-- Glass walls round the edge, open where the ramps arrive
		wallX(story, nil, -FLOOR_X, FLOOR_X, z0, top)
		wallX(story, nil, -FLOOR_X, FLOOR_X, FLOOR_Z1, top)
		if story == 2 then
			-- Right: the ramp from the ground lands at z 6-12. Left: the way up to the
			-- Top Floor leaves at z 2-8 (walled off until it's bought).
			wallZ(2, nil, z0, 6, FLOOR_X, top)
			wallZ(2, nil, 12, FLOOR_Z1, FLOOR_X, top)
			wallZ(2, nil, 8, FLOOR_Z1, -FLOOR_X, top)
			wallZ(2, 2, z0, 8, -FLOOR_X, top)
		else
			-- Left: the ramp from the Second Floor lands at z 28-34
			wallZ(story, nil, z0, 28, -FLOOR_X, top)
			wallZ(story, nil, 34, FLOOR_Z1, -FLOOR_X, top)
			wallZ(story, nil, z0, FLOOR_Z1, FLOOR_X, top)
		end
	end
	-- Ground → Second Floor: up the right side from the front
	local secondTop = floorTop(2)
	ramp(2, Vector3.new(FLOOR_X + 3, TOP, -18), Vector3.new(FLOOR_X + 3, secondTop, 6))
	piece(2, nil, "RampLanding", Vector3.new(6, 1, 6), CFrame.new(FLOOR_X + 3, secondTop - 0.5, 9))
	wallZ(2, nil, 6, 12, FLOOR_X + 6, secondTop)
	wallX(2, nil, FLOOR_X, FLOOR_X + 6, 12, secondTop)
	-- Second Floor → Top Floor: up the left side, from a landing at its front-left
	if #Config.Economy.tunables.floors >= 2 then
		local thirdTop = floorTop(3)
		piece(3, nil, "RampLanding", Vector3.new(6, 1, 6), CFrame.new(-FLOOR_X - 3, secondTop - 0.5, 5))
		wallX(3, nil, -FLOOR_X - 6, -FLOOR_X, 2, secondTop)
		wallZ(3, nil, 2, 8, -FLOOR_X - 6, secondTop)
		ramp(3, Vector3.new(-FLOOR_X - 3, secondTop, 8), Vector3.new(-FLOOR_X - 3, thirdTop, 28))
		piece(3, nil, "RampLanding", Vector3.new(6, 1, 6), CFrame.new(-FLOOR_X - 3, thirdTop - 0.5, 31))
		wallZ(3, nil, 28, 34, -FLOOR_X - 6, thirdTop)
		wallX(3, nil, -FLOOR_X - 6, -FLOOR_X, 34, thirdTop)
	end

	-- Vault rooms: glass walls on the inner side and the front, a door in the front
	local vaults: { VaultRoom } = {}
	for vault = 1, #Config.Economy.tunables.vaults do
		local story, side, roomCenter = vaultLayout(vault)
		local top = roomCenter.Y
		local innerX = side * (FLOOR_X - 1 - VAULT_SIZE)
		local outerX = side * FLOOR_X
		wallZ(story, nil, VAULT_Z0, FLOOR_Z1, innerX, top, vault)
		local doorLeft = roomCenter.X - DOOR_WIDTH / 2
		local doorRight = roomCenter.X + DOOR_WIDTH / 2
		local nearX = if side < 0 then outerX else innerX -- the room's left edge
		local farX = if side < 0 then innerX else outerX
		for _, span in { { nearX, doorLeft }, { doorRight, farX } } do
			piece(
				story,
				nil,
				"VaultWall",
				Vector3.new(math.abs(span[2] - span[1]), FLOOR_WALL, 0.6),
				CFrame.new((span[1] + span[2]) / 2, top + FLOOR_WALL / 2, VAULT_Z0),
				true,
				vault
			)
		end
		local door = part({
			Name = `VaultDoor{vault}`,
			Size = Vector3.new(DOOR_WIDTH, FLOOR_WALL, 0.6),
			CFrame = origin * CFrame.new(roomCenter.X, top + FLOOR_WALL / 2, VAULT_Z0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 60, 60),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = model,
		})
		local doorLabel =
			billboard(door, Vector3.new(0, FLOOR_WALL / 2 + 1.2, 0), UDim2.fromOffset(170, 40), 60)
		doorLabel.Text = `Vault {vault}`
		local doorGui = doorLabel.Parent
		if doorGui and doorGui:IsA("BillboardGui") then
			doorGui.Enabled = false
		end
		local lockVault = Instance.new("ProximityPrompt")
		lockVault.Name = "LockVault"
		lockVault.ActionText = "Lock Vault"
		lockVault.ObjectText = `Vault {vault}`
		lockVault.HoldDuration = 0.3
		lockVault.MaxActivationDistance = 10
		lockVault.RequiresLineOfSight = false
		lockVault:SetAttribute("VisibleTo", "owner")
		lockVault:SetAttribute("Active", false)
		lockVault.Parent = door
		local minX = math.min(innerX, outerX)
		local maxX = math.max(innerX, outerX)
		vaults[vault] = {
			floor = story,
			door = door,
			label = doorLabel,
			prompt = lockVault,
			minX = minX,
			maxX = maxX,
			minZ = VAULT_Z0,
			maxZ = FLOOR_Z1,
			owned = false,
			locked = false,
		}
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
		floorPieces = floorPieces,
		vaults = vaults,
		level = 0,
		floors = 1,
		width = 44,
		depth = 44,
	}
	return plot
end

-- The lasers stand on the plot edge, tall enough to cover every floor it has.
local function placeLasers(plot: PlotLayout)
	local width, depth = plot.width, plot.depth
	local halfW = width / 2
	local midZ = PLOT_FRONT + depth / 2
	local height = if plot.floors >= 2 then (plot.floors - 1) * FLOOR_HEIGHT + FLOOR_WALL else 7
	local edges: { { any } } = {
		{ CFrame.new(0, 0, PLOT_FRONT), Vector3.new(width + 1, 1, 1) },
		{ CFrame.new(0, 0, PLOT_FRONT + depth), Vector3.new(width + 1, 1, 1) },
		{ CFrame.new(-halfW, 0, midZ), Vector3.new(1, 1, depth + 1) },
		{ CFrame.new(halfW, 0, midZ), Vector3.new(1, 1, depth + 1) },
	}
	for i, edge in edges do
		local offset: CFrame, size: Vector3 = edge[1], edge[2]
		local laser = plot.lasers[i]
		laser.Size =
			Vector3.new(if size.X > 1 then size.X else 0.3, height, if size.Z > 1 then size.Z else 0.3)
		laser.CFrame = plot.origin * offset * CFrame.new(0, 0.5 + height / 2, 0)
	end
end

local function showDoor(room: VaultRoom)
	room.door.Transparency = if not room.owned then 1 elseif room.locked then 0.25 else 0.85
	room.door.CanCollide = room.owned and room.locked
	room.door.CanQuery = room.owned
end

-- Resizes a plot for a base level: floor, trim and lasers. (Which pedestals exist
-- is up to setFloors, which BaseService runs right after.)
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
	end
	placeLasers(plot)
end

-- Shows the floors, vault rooms and pedestals a base has: `floors` counts the
-- ground, `vaults` the vault rooms bought (Config.Economy.slots).
function WorldService.setFloors(plot: PlotLayout, floors: number, vaults: number)
	plot.floors = floors
	for _, entry in plot.floorPieces do
		local shown = floors >= entry.from
			and (entry.to == nil or floors <= entry.to)
			and (entry.vault == nil or vaults >= entry.vault)
		entry.part.Transparency = if shown then entry.transparency else 1
		entry.part.CanCollide = shown
		entry.part.CanQuery = shown
	end
	for vault, room in plot.vaults do
		room.owned = vaults >= vault and floors >= room.floor
		room.prompt:SetAttribute("Active", room.owned)
		local gui = room.label.Parent
		if gui and gui:IsA("BillboardGui") then
			gui.Enabled = room.owned
		end
		showDoor(room)
	end
	local shownSlots: { [number]: boolean } = {}
	for _, slot in Config.Economy.slots(plot.level, floors, vaults) do
		shownSlots[slot] = true
	end
	for i, pedestal in plot.pedestalParts do
		local shown = shownSlots[i] == true
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
	placeLasers(plot)
end

-- A vault door: locked (solid, glowing, blocks the way) or open, and its sign.
function WorldService.setVaultDoor(plot: PlotLayout, vault: number, locked: boolean, text: string)
	local room = plot.vaults[vault]
	if room == nil then
		return
	end
	room.locked = locked
	room.label.Text = text
	showDoor(room)
end

-- Which floor (1 = ground) a world position is on, by height.
function WorldService.floorAt(plot: PlotLayout, position: Vector3): number
	local y = plot.origin:PointToObjectSpace(position).Y
	return math.clamp(math.floor((y - TOP + 4) / FLOOR_HEIGHT) + 1, 1, #Config.Economy.tunables.floors + 1)
end

-- Whether a world position is on a floor: at its height, and over its slab (not
-- beside it on a ramp).
function WorldService.onFloor(plot: PlotLayout, position: Vector3, floor: number): boolean
	if WorldService.floorAt(plot, position) ~= floor then
		return false
	end
	if floor <= 1 then
		return true
	end
	local localPos = plot.origin:PointToObjectSpace(position)
	return math.abs(localPos.X) <= FLOOR_X and localPos.Z >= FLOOR_Z0[floor] and localPos.Z <= FLOOR_Z1
end

-- Whether a world position is inside a vault room.
function WorldService.inVault(plot: PlotLayout, vault: number, position: Vector3): boolean
	local room = plot.vaults[vault]
	if room == nil then
		return false
	end
	local localPos = plot.origin:PointToObjectSpace(position)
	return localPos.X >= room.minX
		and localPos.X <= room.maxX
		and localPos.Z >= room.minZ
		and localPos.Z <= room.maxZ
		and WorldService.floorAt(plot, position) == room.floor
end

-- Just outside a vault's door (where a locking door pushes visitors).
function WorldService.vaultOutside(plot: PlotLayout, vault: number): CFrame
	local _, _, center = vaultLayout(vault)
	return plot.origin * CFrame.new(center.X, center.Y + 3, VAULT_Z0 - 4)
end

-- Makes the first `count` pedestals nursery pedestals (blue fabric, nest, "Nursery"
-- sign) and the rest of the first few regular ones: the owner's nursery size.
function WorldService.setNursery(plot: PlotLayout, count: number)
	for i = 1, Config.Economy.tunables.nurserySlotsMax do
		local pedestal = plot.pedestalParts[i]
		local nursery = i <= count
		if pedestal:GetAttribute("Nursery") == nursery then
			continue
		end
		pedestal:SetAttribute("Nursery", nursery)
		pedestal.Name = if nursery then `Nursery{i}` else `Pedestal{i}`
		pedestal.Material = if nursery then Enum.Material.Fabric else Enum.Material.Slate
		pedestal.Color = if nursery then Color3.fromRGB(120, 180, 255) else Color3.fromRGB(110, 110, 118)
		local sign = pedestal:FindFirstChildOfClass("BillboardGui")
		if nursery and sign == nil then
			local nurseryLabel = billboard(pedestal, Vector3.new(0, 3, 0), UDim2.fromOffset(120, 30), 60)
			nurseryLabel.Text = "Nursery"
			nurseryLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		elseif not nursery and sign then
			sign:Destroy()
		end
		local old = plot.pedestalProps[i]
		if old then
			old:Destroy()
		end
		pedestal.Transparency = 0
		plot.pedestalProps[i] = Props.dress(pedestal, if nursery then "NurseryNest" else "Pedestal", {
			cframe = plot.pedestals[i] * CFrame.new(0, -0.7, 0),
			size = Vector3.new(6.4, 1.4, 6.4),
			stretch = true,
		})
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
	-- The floors above take the theme too: its floor on slabs and ramps, its trim
	-- color in the glass, its laser color on the vault doors
	for _, entry in plot.floorPieces do
		if entry.part:GetAttribute("Glass") then
			entry.part.Color = theme.trimColor:Lerp(Color3.new(1, 1, 1), 0.45)
		else
			entry.part.Material = theme.floorMaterial
			entry.part.Color = theme.floorColor:Lerp(Color3.new(0, 0, 0), 0.12)
		end
	end
	for _, room in plot.vaults do
		room.door.Color = theme.laserColor
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
	-- Scattered inside the walls: imported WorldProps, or part-built decor from SetPieces
	decor: { string },
	-- Re-skins the imported decor in a plain material (Storm Peaks: weathered slate)
	decorSkin: { material: Enum.Material, color: Color3 }?,
	storm: boolean?, -- a storm overhead: cloud, rain, mist, lightning (SetPieces.stormSky)
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
		color = Color3.fromRGB(82, 86, 98),
		terrain = Enum.Material.Rock,
		wall = Enum.Material.Slate,
		wallColor = Color3.fromRGB(64, 68, 80),
		-- Storm-worn, not green: jagged slate shards (the ice spire, re-skinned), bare
		-- dead trees and lightning scorch marks
		decor = { "IceSpire", "IceSpire", "RockCluster", "DeadTree", "DeadTree", "ScorchMark" },
		decorSkin = { material = Enum.Material.Slate, color = Color3.fromRGB(92, 96, 108) },
		storm = true,
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
	folder: Folder, -- the zone's parts; zone events put their pieces here
	landmarks: { [string]: Landmark }, -- set pieces by name (the first of each), for zone events
}
-- Where a set piece stands (ZoneEventService stages its events on these)
export type Landmark = {
	position: Vector3, -- on the ground at its middle
	frame: CFrame, -- that spot, facing the way the piece faces
	radius: number, -- how far it reaches across
	top: Vector3, -- top middle of the fitted model
	size: Vector3, -- its fitted bounding box
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

		local landmarks: { [string]: Landmark } = {}
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
			folder = zoneFolder,
			landmarks = landmarks,
		})

		-- Hero set pieces: side ones face the middle, central ones face the gate
		local heroSpots: { { position: Vector3, radius: number } } = {}
		for _, hero in zone.heroes do
			local angle = inwardAngle + math.rad(hero.angle)
			local position = center
				+ Vector3.new(math.cos(angle) * hero.distance, 0, math.sin(angle) * hero.distance)
			local facing = if hero.distance > 20 then center else gateCenter
			local frame = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
			local radius, model = SetPieces.build(hero.name, frame, hero.scale or 1, zoneFolder, rng)
			table.insert(heroSpots, { position = position, radius = radius })
			if landmarks[hero.name] == nil then
				local box, size = model:GetBoundingBox()
				landmarks[hero.name] = {
					position = position,
					frame = frame,
					radius = radius,
					top = (box * CFrame.new(0, size.Y / 2, 0)).Position,
					size = size,
				}
			end
		end

		-- The weather blows around the ring; ZoneMoodController reads these attributes
		local wind = outward:Cross(Vector3.yAxis)
		if zone.storm then
			SetPieces.stormSky(center, WALL_RADIUS, wind, zoneFolder)
			zoneFolder:SetAttribute("Mood", "storm")
		end
		zoneFolder:SetAttribute("Center", center)
		zoneFolder:SetAttribute("Radius", WALL_RADIUS)

		-- Decor inside the walls, clear of the nodes, the shrine, the set pieces and the gate path
		local available: { string } = {}
		for _, name in zone.decor do
			if Props.template("WorldProps", name) or SetPieces.has(name) then
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
					if SetPieces.has(name) then
						-- Part-built decor leans downwind
						local frame = CFrame.lookAt(position, position + wind)
						SetPieces.build(name, frame, rng:NextNumber(0.85, 1.2), zoneFolder, rng)
					else
						local height = if name == "MossTree" or name == "PineTree"
							then 20
							elseif name == "IceSpire" then 11
							else 5
						local model = Props.spawn(
							name,
							CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0),
							height * rng:NextNumber(0.8, 1.25),
							zoneFolder
						)
						local skin = zone.decorSkin
						if model and skin then
							Props.reskin(model, skin.material, skin.color)
						end
					end
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
		and localPos.Y < floorTop(#Config.Economy.tunables.floors + 1) + 25
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
		WorldService.setFloors(plot, 1, 0)
		WorldService.applyTheme(plot, Config.Progression.themes[1])
	end
	scatterDecor()
end

return WorldService

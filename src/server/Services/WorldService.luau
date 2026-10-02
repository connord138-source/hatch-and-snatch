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
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(script.Parent.Parent.Props)
local SetPieces = require(script.Parent.Parent.SetPieces)
local CastleKits = require(script.Parent.Parent.CastleKits)
local Fortress = require(script.Parent.Parent.Fortress)
local ZoneShape = require(ReplicatedStorage.Shared.ZoneShape)
local Landmarks = require(script.Parent.Parent.Landmarks)
local BaseKit = require(script.Parent.Parent.BaseKit)
local BaseDecor = require(script.Parent.Parent.BaseDecor)

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
	terminalPrompt: ProximityPrompt, -- opens the Base menu (OpensMenu attribute)
	terminalScreen: TextLabel, -- the monitor's text
	pads: { BaseKit.Pad }, -- walk-over buy pads (BaseService decides what each sells)
	hides: { BaseKit.HideSpot },
	security: BaseKit.Security,
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
	arch: Model?, -- the timber gate arch (Camp and Stockade; a gatehouse replaces it)
	fortress: Fortress.Layout?, -- where the fortress walls stand (applyTheme)
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

local PLOT_RADIUS = 128 -- room between neighbours for the fortress walls and towers
local PLOT_FRONT = -22 -- local Z of a plot's front edge (the side facing the hub)
local GROUND_Y = 0.2
local ISLAND_RADIUS = 410 -- roomy (owner, 2026-10-01): open land and landmarks past the zones
local ZONE_INNER = 205 -- the biome ring's inner wall radius (buildZones)
local ZONE_OUTER = 295 -- and its outer wall radius
local INCUBATOR_GLASS = 0.45 -- transparency of the imported incubator model
local TOP = 1 -- plot floor top, relative to the plot origin

export type LuckWheel = {
	disc: Model, -- the spinning part; rotate with base * CFrame.Angles(0, 0, angle)
	base: CFrame, -- wheel center, -Z facing the hub
	prompt: ProximityPrompt,
	sign: TextLabel,
}

local WorldService = {
	eventBoard = nil :: TextLabel?, -- the moon event board at the South Event Grounds
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
	local pier = Landmarks.at(Landmarks.PIER_BEARING, 1, 0)
	local pierAngle = math.atan2(pier.Z, pier.X)
	local gap = (Landmarks.PIER_WIDTH / 2 + 0.4) / shore -- the pier's own rails close it
	local from, to = pierAngle + gap, pierAngle - gap + 2 * math.pi
	local segments = 96
	local step = (to - from) / segments
	local width = 2 * shore * math.sin(step / 2) + 0.5
	for i = 0, segments - 1 do
		local angle = from + (i + 0.5) * step
		local inset = shore * math.cos(step / 2)
		part({
			Name = "ShoreWall",
			Size = Vector3.new(width, 80, 2),
			CFrame = CFrame.new(math.cos(angle) * inset, GROUND_Y + 36, math.sin(angle) * inset)
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
	-- At the North Commons, out past the biome ring (owner, 2026-10-01)
	local ground = Landmarks.at(0, Landmarks.outerLoop(ZONE_OUTER, ISLAND_RADIUS) + 30, GROUND_Y)
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
	-- `glass` pieces are the walls: solid stone in the fortress's style (applyTheme;
	-- owner 2026-10-01: the glass boxes looked see-through and unfinished). A
	-- `barrier` is an invisible wall (behind the arched fronts); `keep` marks stone
	-- trim (pillars, arches, battlements) styled the same way.
	local function piece(
		from: number,
		to: number?,
		name: string,
		size: Vector3,
		offset: CFrame,
		glass: boolean?,
		vault: number?,
		barrier: boolean?,
		keep: boolean?
	): Part
		local p = part({
			Name = name,
			Size = size,
			CFrame = origin * offset,
			Material = if glass or keep then Enum.Material.Cobblestone else Enum.Material.WoodPlanks,
			Color = if glass or keep then Color3.fromRGB(140, 134, 126) else Color3.fromRGB(120, 95, 70),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		p:SetAttribute("Glass", glass == true and not barrier)
		p:SetAttribute("Keep", keep == true)
		local entry: FloorPiece = {
			part = p :: BasePart,
			from = from,
			to = to,
			transparency = if barrier then 1 else 0,
			vault = vault,
		}
		table.insert(floorPieces, entry)
		return p
	end
	-- The side of a floor facing the hub: an arcade of stone arches over low
	-- balustrades, so the creatures inside show, with an invisible wall behind it
	-- that's still too tall to jump
	local function arcade(story: number, x0: number, x1: number, z: number, top: number)
		piece(
			story,
			nil,
			"FloorWall",
			Vector3.new(math.abs(x1 - x0), FLOOR_WALL, 0.4),
			CFrame.new((x0 + x1) / 2, top + FLOOR_WALL / 2, z),
			true,
			nil,
			true
		)
		local bays = math.max(1, math.floor(math.abs(x1 - x0) / 10.5 + 0.5))
		local bay = (x1 - x0) / bays
		for i = 0, bays do
			piece(
				story,
				nil,
				"ArchPillar",
				Vector3.new(1.8, FLOOR_WALL, 1.8),
				CFrame.new(x0 + i * bay, top + FLOOR_WALL / 2, z),
				nil,
				nil,
				nil,
				true
			)
		end
		for i = 0, bays - 1 do
			local x = x0 + (i + 0.5) * bay
			local span = math.abs(bay) - 1.8
			piece(
				story,
				nil,
				"ArchLintel",
				Vector3.new(span, 1.8, 1.4),
				CFrame.new(x, top + FLOOR_WALL - 0.9, z),
				nil,
				nil,
				nil,
				true
			)
			for _, side in { -1, 1 } do
				piece(
					story,
					nil,
					"ArchCorner",
					Vector3.new(2.4, 2.4, 1.2),
					CFrame.new(x + side * (span / 2 - 0.5), top + FLOOR_WALL - 1.8, z)
						* CFrame.Angles(0, 0, math.rad(45)),
					nil,
					nil,
					nil,
					true
				)
			end
			piece(
				story,
				nil,
				"Balustrade",
				Vector3.new(span, 2.6, 0.9),
				CFrame.new(x, top + 1.3, z),
				nil,
				nil,
				nil,
				true
			)
		end
		piece(
			story,
			nil,
			"ArchCap",
			Vector3.new(math.abs(x1 - x0) + 2, 0.8, 2.2),
			CFrame.new((x0 + x1) / 2, top + FLOOR_WALL + 0.4, z),
			nil,
			nil,
			nil,
			true
		)
		-- A stone band along the slab's edge underneath
		piece(
			story,
			nil,
			"FloorFascia",
			Vector3.new(math.abs(x1 - x0) + 1, 1.6, 0.8),
			CFrame.new((x0 + x1) / 2, top - 1.1, z - 0.2),
			nil,
			nil,
			nil,
			true
		)
	end
	-- Battlements along the top of a wall (the Top Floor is open to the sky)
	local function merlons(story: number, a: Vector3, b: Vector3, top: number)
		local length = (b - a).Magnitude
		local count = math.max(1, math.floor(length / 4))
		for i = 0, count do
			local at = a:Lerp(b, i / count)
			piece(
				story,
				nil,
				"Merlon",
				Vector3.new(1.8, 1.8, 1.8),
				CFrame.new(at.X, top + FLOOR_WALL + 0.9, at.Z),
				nil,
				nil,
				nil,
				true
			)
		end
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
				Vector3.new(2.4, FLOOR_HEIGHT, 2.4),
				CFrame.new(
					corner.X * (FLOOR_X - 1),
					top - FLOOR_HEIGHT / 2,
					if corner.Y == 0 then z0 + 1 else FLOOR_Z1 - 1
				),
				nil,
				nil,
				nil,
				true
			)
		end
		-- Stone walls round the edge, open where the ramps arrive; arches at the front
		arcade(story, -FLOOR_X, FLOOR_X, z0, top)
		wallX(story, nil, -FLOOR_X, FLOOR_X, FLOOR_Z1, top)
		if story == #Config.Economy.tunables.floors + 1 then
			merlons(story, Vector3.new(-FLOOR_X, 0, FLOOR_Z1), Vector3.new(FLOOR_X, 0, FLOOR_Z1), top)
			merlons(story, Vector3.new(FLOOR_X, 0, z0 + 2), Vector3.new(FLOOR_X, 0, FLOOR_Z1 - 2), top)
			merlons(story, Vector3.new(-FLOOR_X, 0, 36), Vector3.new(-FLOOR_X, 0, FLOOR_Z1 - 2), top)
		end
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

	-- The Command Terminal (between the lock and the cash pad), buy pads, hiding
	-- spots and security fixtures (BaseKit)
	local _, terminalPrompt, terminalScreen = BaseKit.terminal(model, origin)
	local pads = BaseKit.pads(model, origin)
	local hides = BaseKit.hideSpots(model, origin)
	local security = BaseKit.security(model, origin)

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
	local arch = Props.spawn(
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
		terminalPrompt = terminalPrompt,
		terminalScreen = terminalScreen,
		pads = pads,
		hides = hides,
		security = security,
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
		arch = arch,
		fortress = nil,
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
-- A theme kit's dressing on the keep (the pieces that show: battlements, arcades,
-- walls and floors), rebuilt whenever the theme or the floors change.
local function dressKeep(plot: PlotLayout)
	local existing = plot.model:FindFirstChild("KeepKit")
	if existing then
		existing:Destroy()
	end
	local kitId = plot.model:GetAttribute("Kit")
	local kit = CastleKits.get(if typeof(kitId) == "string" then kitId else nil)
	if kit == nil then
		return
	end
	local shown: { BasePart } = {}
	for _, entry in plot.floorPieces do
		if entry.part.Transparency < 1 then
			table.insert(shown, entry.part)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "KeepKit"
	CastleKits.dressKeep(folder, kit, shown)
	folder.Parent = plot.model
end

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
	dressKeep(plot)
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

-- Shows the first `count` hiding spots (placed for the plot's current width) and
-- seats hidden creatures there (pedestal slots 51-54).
function WorldService.setHides(plot: PlotLayout, count: number)
	for slot, seat in BaseKit.placeHides(plot.model, plot.hides, plot.origin, plot.width, count) do
		plot.pedestals[slot] = seat
	end
end

-- Hides every buy pad (a plot without an owner sells nothing).
function WorldService.clearPads(plot: PlotLayout)
	for _, pad in plot.pads do
		BaseKit.setPad(pad, nil)
	end
end

-- Places the security fixtures the owner has (Config.BaseBuilds items, and the
-- alarm bell from security level 1).
function WorldService.setSecurity(plot: PlotLayout, owned: { [string]: boolean }, alarm: boolean)
	BaseKit.placeSecurity(
		plot.model,
		plot.security,
		plot.origin,
		plot.width,
		plot.depth,
		PLOT_FRONT,
		owned,
		alarm,
		plot.floors
	)
end

-- Rebuilds the decor the owner has bought and left switched on (`statues`: the
-- owner's two rarest species, for the Guardian Statues).
function WorldService.setBuilds(
	plot: PlotLayout,
	shown: { [string]: boolean },
	theme: Config.BaseTheme,
	statues: { string }
)
	local layout = plot.fortress or Fortress.layout(plot.level, plot.width, plot.depth, PLOT_FRONT)
	BaseDecor.build(plot.model, plot.origin, layout, shown, theme, statues)
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
	plot.model:SetAttribute("Kit", theme.kit)
	plot.floor.Material = theme.floorMaterial
	plot.floor.Color = theme.floorColor
	for _, trim in plot.trim do
		trim.Color = theme.trimColor
	end
	-- The glow: lasers and vault doors (a rainbow glow cycles on the client)
	local rainbowGlow = theme.rainbow ~= nil and theme.rainbow.glow
	local function glow(part: BasePart)
		part.Color = theme.laserColor
		if rainbowGlow then
			CollectionService:AddTag(part, "Rainbow")
		else
			CollectionService:RemoveTag(part, "Rainbow")
		end
	end
	for _, laser in plot.lasers do
		glow(laser)
	end
	-- The floors above take the theme too: the fortress's stone on their walls,
	-- arches and pillars, its floor on slabs and ramps, its laser color on the doors
	local stoneMaterial, stoneColor = Fortress.stone(plot.level, theme)
	for _, entry in plot.floorPieces do
		if entry.part:GetAttribute("Glass") then
			entry.part.Material = stoneMaterial
			entry.part.Color = stoneColor
		elseif entry.part:GetAttribute("Keep") then
			entry.part.Material = stoneMaterial
			entry.part.Color = stoneColor:Lerp(Color3.new(1, 1, 1), 0.12)
		else
			entry.part.Material = theme.floorMaterial
			entry.part.Color = theme.floorColor:Lerp(Color3.new(0, 0, 0), 0.12)
		end
	end
	for _, room in plot.vaults do
		glow(room.door)
	end
	dressKeep(plot)

	-- The fortress around the plot follows the level and takes the theme's colors
	local layout =
		Fortress.build(plot.model, plot.origin, plot.level, plot.width, plot.depth, PLOT_FRONT, theme)
	plot.fortress = layout
	local gatehouse = Fortress.style(plot.level).gatehouse
	if plot.arch then
		plot.arch.Parent = if gatehouse then nil else plot.model
	end
	-- The owner's name floats over the gate, above a gatehouse once there is one
	-- (it overlapped the lock button's label under the gatehouse)
	local signGui = plot.label.Parent
	local sign = signGui and signGui.Parent
	if sign and sign:IsA("BasePart") then
		sign.CFrame = plot.origin
			* CFrame.new(
				0,
				if gatehouse then layout.height + 14 else TOP + 6,
				if gatehouse then layout.front else PLOT_FRONT + 1
			)
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
	-- Along both sides and the back, just outside the fortress walls (clear of the
	-- corner towers)
	local rng = Random.new(plot.index * 97 + #theme.id)
	local halfW = layout.halfW
	local spots: { Vector3 } = {}
	for z = layout.front + 10, layout.back - 9, 9 do
		table.insert(spots, Vector3.new(-halfW - 10, 0, z))
		table.insert(spots, Vector3.new(halfW + 10, 0, z))
	end
	for x = -halfW + 9, halfW - 9, 9 do
		table.insert(spots, Vector3.new(x, 0, layout.back + 10))
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
	center: Vector3, -- the middle of the zone, on the ground
	radius: number, -- half its depth (a rough size; use `sector` for inside checks)
	sector: ZoneShape.Sector, -- its walls (ZoneShape.contains)
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

-- The biome ring (owner, 2026-10-01, the approved island concept): six walled
-- sectors between the fortresses and the open land, with the ring open to the north
-- and south where the main paths run out to the beach. East half from the north:
-- Frost Shelf, Magma Rift, Storm Peaks; west half from the south: Coral Coast,
-- Mossvale, Moonfall. Each zone's gate faces the fortresses.
local ZONE_GAP = math.rad(8) -- the open paths through the ring, north and south
local NORTH = -math.pi / 2 -- atan2 angle of north (-Z)
local WALL_HEIGHT = 11
local WALL_THICKNESS = 2.5
local GATE_WIDTH = 12
local ZONE_SLOT: { [string]: number } = {
	FrostShelf = 1,
	MagmaRift = 2,
	StormPeaks = 3,
	CoralCoast = 4,
	Mossvale = 5,
	Moonfall = 6,
}

local function zoneSector(biome: string): ZoneShape.Sector
	local slot = ZONE_SLOT[biome] or 1
	local span = (math.pi - ZONE_GAP) / 3
	local halfStart = if slot <= 3 then NORTH + ZONE_GAP / 2 else NORTH + math.pi + ZONE_GAP / 2
	local from = halfStart + ((slot - 1) % 3) * span
	return { inner = ZONE_INNER, outer = ZONE_OUTER, from = from, to = from + span }
end

-- True when a spot is inside a zone's walls, or within `margin` studs of them.
local function nearZone(position: Vector3, margin: number): boolean
	local distance = Vector3.new(position.X, 0, position.Z).Magnitude
	for _, zone in ZONES do
		local sector = zoneSector(zone.biome)
		local pad = margin / math.max(distance, 1)
		if
			ZoneShape.contains({
				inner = sector.inner - margin,
				outer = sector.outer + margin,
				from = sector.from - pad,
				to = sector.to + pad,
			}, position)
		then
			return true
		end
	end
	return false
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
			math.abs(localPos.X) < maxWidth / 2 + 14
			and localPos.Z > PLOT_FRONT - 12
			and localPos.Z < PLOT_FRONT + maxDepth + 14
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

-- One arc of a zone wall at `radius`, from angle a0 to a1, in chord segments.
local function arcWall(folder: Instance, zone: Zone, radius: number, a0: number, a1: number)
	if a1 - a0 <= 0 then
		return
	end
	local segments = math.max(1, math.ceil(radius * (a1 - a0) / 14))
	local step = (a1 - a0) / segments
	local length = 2 * radius * math.sin(step / 2) + 0.6
	for s = 0, segments - 1 do
		local angle = a0 + (s + 0.5) * step
		local position = Vector3.new(
			math.cos(angle) * radius * math.cos(step / 2),
			GROUND_Y + WALL_HEIGHT / 2,
			math.sin(angle) * radius * math.cos(step / 2)
		)
		part({
			Name = "Wall",
			Size = Vector3.new(length, WALL_HEIGHT, WALL_THICKNESS),
			CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)),
			Material = zone.wall,
			Color = zone.wallColor,
			Parent = folder,
		})
	end
end

-- A straight wall along a sector edge, from the inner arc to the outer one.
local function radialWall(folder: Instance, zone: Zone, angle: number)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local from = direction * (ZONE_INNER - WALL_THICKNESS / 2)
	local to = direction * (ZONE_OUTER + WALL_THICKNESS / 2)
	local middle = (from + to) / 2 + Vector3.new(0, GROUND_Y + WALL_HEIGHT / 2, 0)
	part({
		Name = "Wall",
		Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, (to - from).Magnitude),
		CFrame = CFrame.lookAt(middle, middle + direction),
		Material = zone.wall,
		Color = zone.wallColor,
		Parent = folder,
	})
	-- A sturdier post where it meets each arc
	for _, radius in { ZONE_INNER, ZONE_OUTER } do
		part({
			Name = "WallPost",
			Size = Vector3.new(4, WALL_HEIGHT + 1.5, 4),
			CFrame = CFrame.new(direction * radius + Vector3.new(0, GROUND_Y + (WALL_HEIGHT + 1.5) / 2, 0))
				* CFrame.Angles(0, -angle, 0),
			Material = zone.wall,
			Color = zone.wallColor:Lerp(Color3.new(0, 0, 0), 0.2),
			Parent = folder,
		})
	end
end

local function buildZones(folder: Folder)
	local rng = Random.new(6061)
	for _, zone in ZONES do
		local sector = zoneSector(zone.biome)
		local slot = ZONE_SLOT[zone.biome] or 1
		local biomeColor = Config.Eggs.eggColors[zone.biome]
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = `{zone.biome}Zone`
		zoneFolder.Parent = folder

		local middleAngle = (sector.from + sector.to) / 2
		local outward = Vector3.new(math.cos(middleAngle), 0, math.sin(middleAngle))
		local inward = -outward
		local tangent = Vector3.new(-math.sin(middleAngle), 0, math.cos(middleAngle)) -- toward `to`
		local center = outward * ((ZONE_INNER + ZONE_OUTER) / 2) + Vector3.new(0, GROUND_Y, 0)
		local halfArc = (sector.to - sector.from) / 2 * (ZONE_INNER + ZONE_OUTER) / 2
		local halfDepth = (ZONE_OUTER - ZONE_INNER) / 2

		-- Ground: wedge-ish strips across the sector. Zones sit a hair apart in height
		-- so the strips that overlap under a shared wall don't flicker.
		local strips = math.ceil(math.deg(sector.to - sector.from) / 2)
		local stripAngle = (sector.to - sector.from) / strips
		for k = 0, strips - 1 do
			local angle = sector.from + (k + 0.5) * stripAngle
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local middle = direction * ((ZONE_INNER + ZONE_OUTER) / 2)
				+ Vector3.new(0, GROUND_Y - 0.2 + slot * 0.03, 0)
			part({
				Name = "Ground",
				Size = Vector3.new(
					2 * ZONE_OUTER * math.sin(stripAngle / 2) + 0.4,
					0.5,
					ZONE_OUTER - ZONE_INNER
				),
				CFrame = CFrame.lookAt(middle, middle + direction),
				Material = zone.material,
				Color = zone.color,
				CanCollide = false,
				Parent = zoneFolder,
			})
		end

		-- Walls: the inner arc (with the gate in its middle), the outer arc, and the
		-- straight edges. A shared edge is built once, by the zone after it; the zone
		-- before a gap also closes its far edge.
		local gateHalf = (GATE_WIDTH / 2 + 3) / ZONE_INNER
		arcWall(zoneFolder, zone, ZONE_INNER, sector.from, middleAngle - gateHalf)
		arcWall(zoneFolder, zone, ZONE_INNER, middleAngle + gateHalf, sector.to)
		arcWall(zoneFolder, zone, ZONE_OUTER, sector.from, sector.to)
		radialWall(zoneFolder, zone, sector.from)
		if slot % 3 == 0 then
			radialWall(zoneFolder, zone, sector.to)
		end

		-- Gate: two pillars, a lintel and a shimmering barrier across the gap
		local gateCenter = outward * ZONE_INNER + Vector3.new(0, GROUND_Y, 0)
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

		-- Shrine at the back of the zone, facing the gate
		local shrineAt = outward * (ZONE_OUTER - 14) + Vector3.new(0, GROUND_Y, 0)
		local shrineFrame = CFrame.lookAt(shrineAt, gateCenter)
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

		-- Hero set pieces, laid out around the zone's middle: their angle (from the
		-- gate direction) and distance stretch along the arc, which is much wider
		-- than it is deep. Side ones face the middle, central ones face the gate.
		local function spread(angleDegrees: number, distance: number): Vector3
			local a = math.rad(angleDegrees)
			return center + inward * (math.cos(a) * distance * 1.1) + tangent * (math.sin(a) * distance * 2.2)
		end
		local landmarks: { [string]: Landmark } = {}
		local heroSpots: { { position: Vector3, radius: number } } = {}
		for _, hero in zone.heroes do
			local position = spread(hero.angle, hero.distance)
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
		local function clearOfHeroes(position: Vector3, margin: number): boolean
			for _, spot in heroSpots do
				if
					(Vector3.new(spot.position.X, position.Y, spot.position.Z) - position).Magnitude
					< spot.radius + margin
				then
					return false
				end
			end
			return true
		end
		-- The walk from the gate to the middle stays open
		local function inGatePath(position: Vector3): boolean
			local offset = position - center
			return offset:Dot(inward) > -6 and math.abs(offset:Dot(tangent)) < 10
		end

		-- Harvest nodes in two rows across the zone, clear of the set pieces and the gate path
		local nodes: { Model } = {}
		local count = Config.Zones.nodesPerZone
		for n = 1, count do
			local along = ((n - 0.5) / count * 2 - 1) * halfArc * 0.8
			local rows: { number } = if n % 2 == 0 then { 16, -18, 30, -32 } else { -18, 16, -32, 30 }
			local position = center + tangent * along + inward * rows[1] + Vector3.new(0, 1, 0)
			for _, row in rows do
				local spot = center + tangent * along + inward * row + Vector3.new(0, 1, 0)
				if clearOfHeroes(spot, 5) and not inGatePath(spot) then
					position = spot
					break
				end
			end
			local node = buildNode(CFrame.new(position), biomeColor, rng, zoneFolder)
			node:SetAttribute("Biome", zone.biome)
			table.insert(nodes, node)
		end

		table.insert(WorldService.zones, {
			biome = zone.biome,
			center = center,
			radius = halfDepth,
			sector = sector,
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

		-- The weather blows along the ring; ZoneMoodController reads these attributes
		local wind = tangent
		if zone.storm then
			SetPieces.stormSky(center, halfDepth + 20, wind, zoneFolder)
			zoneFolder:SetAttribute("Mood", "storm")
		end
		zoneFolder:SetAttribute("Center", center)
		zoneFolder:SetAttribute("Radius", halfDepth)
		zoneFolder:SetAttribute("Inner", sector.inner)
		zoneFolder:SetAttribute("Outer", sector.outer)
		zoneFolder:SetAttribute("From", sector.from)
		zoneFolder:SetAttribute("To", sector.to)

		-- Decor inside the walls, clear of the nodes, the shrine, the set pieces and the gate path
		local available: { string } = {}
		for _, name in zone.decor do
			if Props.template("WorldProps", name) or SetPieces.has(name) then
				table.insert(available, name)
			end
		end
		if #available > 0 then
			local placed = 0
			for _ = 1, 260 do
				if placed >= 48 then
					break
				end
				local position =
					ZoneShape.point(sector, rng:NextNumber(0.04, 0.96), rng:NextNumber(0.08, 0.92), GROUND_Y)
				local blocked = (position - shrineAt).Magnitude < 11 or inGatePath(position)
				for _, node in nodes do
					local nodePos = (node.PrimaryPart :: BasePart).Position
					if (Vector3.new(nodePos.X, position.Y, nodePos.Z) - position).Magnitude < 6 then
						blocked = true
					end
				end
				if blocked or not clearOfHeroes(position, 3) then
					continue
				end
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
	local land = Landmarks.build(folder, {
		groundY = GROUND_Y,
		islandRadius = ISLAND_RADIUS,
		zoneInner = ZONE_INNER,
		zoneOuter = ZONE_OUTER,
		plazaRadius = Config.Eggs.conveyor.radius + 10,
	})
	WorldService.eventBoard = land.eventBoard

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
	local function offPaths(position: Vector3, margin: number): boolean
		for _, segment in land.paths do
			local along = segment.to - segment.from
			local t =
				math.clamp((position - segment.from):Dot(along) / math.max(along:Dot(along), 1e-6), 0, 1)
			local nearest = segment.from + along * t
			if
				Vector3.new(position.X - nearest.X, 0, position.Z - nearest.Z).Magnitude
				< segment.width / 2 + margin
			then
				return false
			end
		end
		for _, circle in land.clear do
			if
				Vector3.new(position.X - circle.position.X, 0, position.Z - circle.position.Z).Magnitude
				< circle.radius + margin
			then
				return false
			end
		end
		return true
	end
	local rng = Random.new(20260929)
	local placed = 0
	local attempts = 0
	while placed < 240 and attempts < 4000 do
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
		-- Keep the biome zones clear, including a big tree's canopy hanging over the
		-- walls (green forest trees were shading the Coral and Magma patches), and
		-- the paths and landmarks
		local margin = 2 + height * 0.45
		if onPlotOrWalkway(position) or nearZone(position, margin) or not offPaths(position, margin) then
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
		WorldService.applyTheme(plot, Config.CastleDesigns.resolve({}))
		WorldService.setHides(plot, 0)
		WorldService.setSecurity(plot, {}, false)
	end
	scatterDecor()
end

return WorldService

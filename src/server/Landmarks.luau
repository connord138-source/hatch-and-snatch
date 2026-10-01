--!strict
-- The open land around the biome ring, laid out like the approved island concept
-- (owner, 2026-10-01): dirt paths with lanterns and signposts, a lighthouse and a
-- pier on the northwest beach (where boats to future islands will tie up), a
-- windmill, crumbling ruins and stone circles, a cliff waterfall feeding a stream
-- to the sea with a footbridge, campsites, a beached shipwreck, palms along the
-- beach and woods in the west. Two station plazas: the North Commons (Luck Wheel,
-- Quest Board, Daily Chest) and the South Event Grounds (the moon event board).
--
-- Every piece uses its imported model (WorldProps.<Name>) when there is one and a
-- simple part-built stand-in otherwise. Positions are compass bearings (degrees
-- clockwise from north, which is -Z) and distances from the hub.
local Props = require(script.Parent.Props)

export type Circle = { position: Vector3, radius: number }
export type Segment = { from: Vector3, to: Vector3, width: number }
export type Result = {
	clear: { Circle }, -- keep scattered decor out of these
	paths: { Segment }, -- and off these
	eventBoard: TextLabel?, -- the South Event Grounds board text (EventService fills it)
	pier: { from: Vector3, to: Vector3 }, -- the pier, for the shoreline wall's gap
}
export type Options = {
	groundY: number,
	islandRadius: number,
	zoneInner: number,
	zoneOuter: number,
	plazaRadius: number,
}

local NORTH = -math.pi / 2
local PATH_COLOR = Color3.fromRGB(152, 120, 86)
local PATH_WIDTH = 9
local LANTERN_GLOW = Color3.fromRGB(255, 205, 140)

local Landmarks = {}

-- Where a compass bearing (degrees clockwise from north) and distance land, on the ground.
function Landmarks.at(bearing: number, distance: number, y: number): Vector3
	local angle = NORTH + math.rad(bearing)
	return Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance)
end

-- The loop path through the open land, between the zone ring and the beach.
function Landmarks.outerLoop(zoneOuter: number, islandRadius: number): number
	return (zoneOuter + islandRadius) / 2 - 18
end

-- The pier's bearing: the shoreline wall leaves a gap here (WorldService).
Landmarks.PIER_BEARING = -52
Landmarks.PIER_LENGTH = 54
Landmarks.PIER_WIDTH = 9

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function trim(parent: Instance, props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(parent, props)
end

local function column(
	parent: Instance,
	base: CFrame,
	diameter: number,
	height: number,
	props: { [string]: any }
): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, props)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
end

-- The imported model if there is one (`height` tall, standing on `base`), else the
-- stand-in (when given).
local function prop(
	name: string,
	parent: Instance,
	base: CFrame,
	height: number,
	standIn: ((Instance, CFrame) -> ())?
): Model?
	local model = Props.spawn(name, base, height, parent)
	if model == nil and standIn then
		local folder = Instance.new("Model")
		folder.Name = name
		standIn(folder, base)
		folder.Parent = parent
	end
	return model
end

---------------------------------------------------------------------------
-- Stand-ins (only used until the models are imported)
---------------------------------------------------------------------------

local function standInLighthouse(folder: Instance, base: CFrame)
	for i = 0, 5 do
		column(folder, base * CFrame.new(0, i * 5.5, 0), 9 - i * 0.6, 5.5, {
			Name = "Tower",
			Material = Enum.Material.SmoothPlastic,
			Color = if i % 2 == 0 then Color3.fromRGB(235, 235, 235) else Color3.fromRGB(205, 50, 45),
		})
	end
	column(
		folder,
		base * CFrame.new(0, 33, 0),
		6.5,
		1,
		{ Name = "Gallery", Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 40, 45) }
	)
	local lamp = column(folder, base * CFrame.new(0, 34, 0), 4.2, 4, {
		Name = "Lamp",
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 235, 150),
	})
	light(lamp, Color3.fromRGB(255, 230, 160), 40, 2)
	column(
		folder,
		base * CFrame.new(0, 38, 0),
		5,
		2,
		{ Name = "Cap", Material = Enum.Material.Metal, Color = Color3.fromRGB(180, 40, 40) }
	)
end

local function standInWindmill(folder: Instance, base: CFrame)
	column(
		folder,
		base,
		11,
		20,
		{ Name = "Tower", Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(150, 140, 125) }
	)
	column(
		folder,
		base * CFrame.new(0, 20, 0),
		12,
		3,
		{ Name = "Cap", Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(120, 85, 55) }
	)
	local hub = base * CFrame.new(0, 19, -6.2)
	for i = 0, 3 do
		trim(folder, {
			Name = "Sail",
			Size = Vector3.new(2.6, 14, 0.3),
			CFrame = hub * CFrame.Angles(0, 0, math.rad(45 + i * 90)) * CFrame.new(0, 7.5, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(225, 210, 180),
		})
	end
end

local function standInStones(folder: Instance, base: CFrame)
	for i = 0, 6 do
		local angle = i / 7 * 2 * math.pi
		local height = 7 + (i % 3) * 1.6
		part(folder, {
			Name = "Stone",
			Size = Vector3.new(2.8, height, 1.8),
			CFrame = base
				* CFrame.new(math.cos(angle) * 9, height / 2, math.sin(angle) * 9)
				* CFrame.Angles(0, -angle, 0),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(125, 128, 120),
		})
	end
end

local function standInRuins(folder: Instance, base: CFrame)
	for i = -1, 1 do
		local arch = base * CFrame.new(i * 8, 0, 0)
		for _, side in { -1, 1 } do
			part(folder, {
				Name = "Pillar",
				Size = Vector3.new(1.8, 9 - math.abs(i) * 1.5, 1.8),
				CFrame = arch * CFrame.new(side * 2.8, (9 - math.abs(i) * 1.5) / 2, 0),
				Material = Enum.Material.Cobblestone,
				Color = Color3.fromRGB(160, 155, 140),
			})
		end
		if i ~= 1 then
			trim(folder, {
				Name = "Lintel",
				Size = Vector3.new(7.4, 1.4, 1.8),
				CFrame = arch * CFrame.new(0, 9 - math.abs(i) * 1.5, 0),
				Material = Enum.Material.Cobblestone,
				Color = Color3.fromRGB(160, 155, 140),
			})
		end
	end
end

local function standInCliff(folder: Instance, base: CFrame)
	for i, size in { Vector3.new(30, 12, 18), Vector3.new(24, 10, 15), Vector3.new(16, 8, 11) } do
		part(folder, {
			Name = "Cliff",
			Size = size,
			CFrame = base * CFrame.new(0, (i - 1) * 9 + size.Y / 2, (i - 1) * 2),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(115, 118, 112),
		})
	end
	trim(folder, {
		Name = "Falls",
		Size = Vector3.new(7, 26, 0.6),
		CFrame = base * CFrame.new(0, 13, -9.6),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(190, 230, 255),
		Transparency = 0.25,
	})
end

local function standInTents(folder: Instance, base: CFrame)
	for i, color in { Color3.fromRGB(60, 110, 200), Color3.fromRGB(235, 150, 40) } do
		local tent = base * CFrame.new((i - 1.5) * 9, 0, 0)
		for _, side in { -1, 1 } do
			part(folder, {
				Name = "Tent",
				Size = Vector3.new(0.3, 5, 6),
				CFrame = tent * CFrame.new(side * 1.6, 2.2, 0) * CFrame.Angles(0, 0, math.rad(side * 32)),
				Material = Enum.Material.Fabric,
				Color = color,
			})
		end
	end
end

local function standInPalm(folder: Instance, base: CFrame)
	column(
		folder,
		base,
		1.4,
		14,
		{ Name = "Trunk", Material = Enum.Material.Wood, Color = Color3.fromRGB(140, 105, 70) }
	)
	for i = 0, 4 do
		trim(folder, {
			Name = "Frond",
			Size = Vector3.new(1.6, 0.3, 7),
			CFrame = base * CFrame.new(0, 14, 0) * CFrame.Angles(0, i / 5 * 2 * math.pi, 0) * CFrame.Angles(
				math.rad(-18),
				0,
				0
			) * CFrame.new(0, 0, -3.2),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(70, 150, 60),
		})
	end
end

local function standInTree(folder: Instance, base: CFrame)
	column(
		folder,
		base,
		2.2,
		8,
		{ Name = "Trunk", Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 50) }
	)
	part(folder, {
		Name = "Canopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(13, 11, 13),
		CFrame = base * CFrame.new(0, 12, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(80, 140, 60),
		CanCollide = false,
	})
end

local function standInBoulders(folder: Instance, base: CFrame)
	for i, size in { 7, 5, 3.5 } do
		part(folder, {
			Name = "Boulder",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = base * CFrame.new((i - 2) * 4.5, size * 0.3, (i % 2) * 2),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(128, 130, 125),
		})
	end
end

local function standInStall(folder: Instance, base: CFrame)
	part(folder, {
		Name = "Counter",
		Size = Vector3.new(8, 3, 3),
		CFrame = base * CFrame.new(0, 1.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70),
	})
	trim(folder, {
		Name = "Canopy",
		Size = Vector3.new(9, 0.4, 5),
		CFrame = base * CFrame.new(0, 6.5, 0.5) * CFrame.Angles(math.rad(10), 0, 0),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(200, 60, 55),
	})
	for _, x in { -3.8, 3.8 } do
		trim(folder, {
			Name = "Post",
			Size = Vector3.new(0.4, 6.5, 0.4),
			CFrame = base * CFrame.new(x, 3.25, -1.2),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(110, 78, 50),
		})
	end
end

local function standInSign(folder: Instance, base: CFrame)
	trim(folder, {
		Name = "Post",
		Size = Vector3.new(0.6, 7, 0.6),
		CFrame = base * CFrame.new(0, 3.5, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(115, 80, 50),
	})
	for i, angle in { 25, -40, 140 } do
		trim(folder, {
			Name = "Arrow",
			Size = Vector3.new(3.4, 0.8, 0.2),
			CFrame = base
				* CFrame.new(0, 4 + i * 0.9, 0)
				* CFrame.Angles(0, math.rad(angle), 0)
				* CFrame.new(1.6, 0, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(165, 120, 75),
		})
	end
end

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------

local function pathPiece(
	folder: Instance,
	from: Vector3,
	to: Vector3,
	width: number,
	y: number,
	paths: { Segment }
)
	local a, b = Vector3.new(from.X, y, from.Z), Vector3.new(to.X, y, to.Z)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	trim(folder, {
		Name = "Path",
		Size = Vector3.new(width, 0.3, length + width * 0.3),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Material = Enum.Material.Ground,
		Color = PATH_COLOR,
	})
	table.insert(paths, { from = a, to = b, width = width })
end

-- A path along a circle, bearing b0 to b1 (degrees, either direction).
local function pathArc(
	folder: Instance,
	radius: number,
	b0: number,
	b1: number,
	width: number,
	y: number,
	paths: { Segment }
)
	local steps = math.max(1, math.ceil(math.abs(math.rad(b1 - b0)) * radius / 10))
	for i = 0, steps - 1 do
		local from = Landmarks.at(b0 + (b1 - b0) * i / steps, radius, y)
		local to = Landmarks.at(b0 + (b1 - b0) * (i + 1) / steps, radius, y)
		pathPiece(folder, from, to, width, y, paths)
	end
end

local function lantern(folder: Instance, position: Vector3, facing: Vector3)
	local base = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	local model = Props.spawn("LampPost", base, 9, folder)
	local glowPart: BasePart? = if model
		then (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
		else nil
	if model == nil then
		trim(folder, {
			Name = "LanternPost",
			Size = Vector3.new(0.5, 8, 0.5),
			CFrame = base * CFrame.new(0, 4, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(90, 65, 45),
		})
		glowPart = trim(folder, {
			Name = "Lantern",
			Size = Vector3.new(1.2, 1.4, 1.2),
			CFrame = base * CFrame.new(0, 8.4, 0),
			Material = Enum.Material.Neon,
			Color = LANTERN_GLOW,
		})
	end
	if glowPart then
		light(glowPart, LANTERN_GLOW, 16, 1.2)
	end
end

---------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------

local function plaza(folder: Instance, center: Vector3, radius: number)
	part(folder, {
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(165, 155, 140),
		CanCollide = false,
	})
end

-- A notice board or chest players walk up to: its prompt opens a menu on their
-- screen (MenuController listens for prompts with an OpensMenu attribute).
local function menuPrompt(parent: BasePart, menu: string, action: string, object: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenMenu"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpensMenu", menu)
	prompt.Parent = parent
end

local function questBoard(folder: Instance, base: CFrame)
	for _, x in { -3.6, 3.6 } do
		part(folder, {
			Name = "BoardPost",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = base * CFrame.new(x, 4.5, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(105, 75, 48),
		})
	end
	local board = part(folder, {
		Name = "QuestBoard",
		Size = Vector3.new(7.6, 5, 0.5),
		CFrame = base * CFrame.new(0, 5.6, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70),
	})
	trim(folder, {
		Name = "BoardRoof",
		Size = Vector3.new(9, 0.5, 2.4),
		CFrame = base * CFrame.new(0, 8.8, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 50, 40),
	})
	for i, offset in
		{
			Vector3.new(-2.2, 0.8, -0.3),
			Vector3.new(0.4, 1.1, -0.3),
			Vector3.new(2.4, 0.5, -0.3),
			Vector3.new(-1, -1.1, -0.3),
			Vector3.new(1.6, -1.2, -0.3),
		}
	do
		trim(folder, {
			Name = "Note",
			Size = Vector3.new(1.5, 1.8, 0.05),
			CFrame = base
				* CFrame.new(0, 5.6, 0)
				* CFrame.new(offset)
				* CFrame.Angles(0, 0, math.rad((i % 3 - 1) * 6)),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(245, 235, 205),
		})
	end
	menuPrompt(board, "Daily", "Daily Quests", "Quest Board")
end

local function dailyChest(folder: Instance, base: CFrame)
	local chest = part(folder, {
		Name = "DailyChest",
		Size = Vector3.new(5, 3, 3.4),
		CFrame = base * CFrame.new(0, 1.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(140, 85, 45),
	})
	trim(folder, {
		Name = "ChestLid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 3.4, 3.4),
		CFrame = base * CFrame.new(0, 3, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 92, 50),
	})
	for _, x in { -1.8, 1.8 } do
		trim(folder, {
			Name = "ChestBand",
			Size = Vector3.new(0.4, 4.9, 3.6),
			CFrame = base * CFrame.new(x, 2.4, 0),
			Material = Enum.Material.Foil,
			Color = Color3.fromRGB(240, 195, 70),
		})
	end
	local glow = trim(folder, {
		Name = "ChestGlow",
		Size = Vector3.new(1, 1.2, 0.3),
		CFrame = base * CFrame.new(0, 2.6, -1.75),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 110),
	})
	light(glow, Color3.fromRGB(255, 220, 120), 12, 1)
	menuPrompt(chest, "Daily", "Daily Rewards", "Daily Chest")
end

local function eventBoard(folder: Instance, base: CFrame): TextLabel
	for _, x in { -6, 6 } do
		part(folder, {
			Name = "BoardPost",
			Size = Vector3.new(1.2, 13, 1.2),
			CFrame = base * CFrame.new(x, 6.5, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(90, 62, 40),
		})
	end
	local board = part(folder, {
		Name = "EventBoard",
		Size = Vector3.new(12, 7, 0.6),
		CFrame = base * CFrame.new(0, 8, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(28, 22, 48),
	})
	local moon = trim(folder, {
		Name = "BoardMoon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = base * CFrame.new(0, 13.5, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(235, 225, 255),
	})
	light(moon, Color3.fromRGB(200, 190, 255), 18, 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.Text = "🌙 Moon Events"
	label.Parent = gui
	return label
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function Landmarks.build(parent: Instance, options: Options): Result
	local folder = Instance.new("Folder")
	folder.Name = "Landmarks"
	folder.Parent = parent
	local y = options.groundY
	local island = options.islandRadius
	local outerLoop = Landmarks.outerLoop(options.zoneOuter, island)
	local ringRoad = options.zoneInner - 9
	local clear: { Circle } = {}
	local paths: { Segment } = {}
	local function keep(position: Vector3, radius: number)
		table.insert(clear, { position = position, radius = radius })
	end
	local function facingHub(position: Vector3): CFrame
		return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	end
	local function place(
		name: string,
		bearing: number,
		distance: number,
		height: number,
		radius: number,
		standIn: ((Instance, CFrame) -> ())?,
		turn: number?
	): Model?
		local position = Landmarks.at(bearing, distance, y)
		keep(position, radius)
		return prop(
			name,
			folder,
			facingHub(position) * CFrame.Angles(0, math.rad(turn or 0), 0),
			height,
			standIn
		)
	end

	-- Paths: a ring round the plaza, a ring road past the zone gates, the two main
	-- paths out through the gaps in the ring, and a loop through the open land
	pathArc(folder, options.plazaRadius + 9, 0, 360, 7, y + 0.08, paths)
	pathArc(folder, ringRoad, 0, 360, 8, y + 0.08, paths)
	pathArc(folder, outerLoop, 0, 360, 8, y + 0.08, paths)
	for _, bearing in { 0, 180 } do
		pathPiece(
			folder,
			Landmarks.at(bearing, options.plazaRadius + 9, y),
			Landmarks.at(bearing, island - 6, y),
			PATH_WIDTH + 1,
			y + 0.1,
			paths
		)
	end
	-- Spurs out to the landmarks
	local spurs = {
		{ -45, -50, island - 4 }, -- the lighthouse and pier
		{ -22, -22, outerLoop + 32 }, -- the windmill
		{ 28, 28, outerLoop + 22 }, -- the ruins
		{ 48, 50, island - 20 }, -- the waterfall
		{ 58, 58, island - 10 }, -- over the footbridge to the east campsite
		{ 205, 205, outerLoop + 36 }, -- the south campsite
		{ 228, 228, island - 2 }, -- the shipwreck
	}
	for _, spur in spurs do
		pathPiece(
			folder,
			Landmarks.at(spur[1], outerLoop, y),
			Landmarks.at(spur[2], spur[3], y),
			6,
			y + 0.09,
			paths
		)
	end

	-- Lanterns along the main paths and the outer loop; signposts at the crossings
	for _, bearing in { 0, 180 } do
		local d = options.plazaRadius + 30
		local side = 1
		while d < island - 20 do
			local inGap = d > options.zoneInner - 4 and d < options.zoneOuter + 4
			if not inGap then
				lantern(folder, Landmarks.at(bearing + side * math.deg(7 / d), d, y), Vector3.zero)
			end
			side = -side
			d += 34
		end
		for _, distance in { ringRoad, outerLoop } do
			local spot = Landmarks.at(bearing + math.deg(9 / distance), distance + 7, y)
			prop("Signpost", folder, facingHub(spot), 7, standInSign)
			keep(spot, 3)
		end
	end
	for bearing = 15, 345, 30 do
		lantern(folder, Landmarks.at(bearing, outerLoop - 6, y), Vector3.zero)
	end

	-- North Commons: the Luck Wheel with the Quest Board and the Daily Chest
	local commons = Landmarks.at(0, outerLoop + 22, y)
	plaza(folder, commons, 24)
	keep(commons, 26)
	questBoard(folder, facingHub(Landmarks.at(-7.5, outerLoop + 20, y)))
	dailyChest(folder, facingHub(Landmarks.at(7.5, outerLoop + 20, y)))
	place("MarketStall", -11, outerLoop + 36, 8, 6, standInStall, 20)
	place("MarketStall", 11, outerLoop + 36, 8, 6, standInStall, -20)

	-- South Event Grounds: the moon event board, stalls and banners
	local grounds = Landmarks.at(180, outerLoop + 22, y)
	plaza(folder, grounds, 24)
	keep(grounds, 26)
	local board = eventBoard(folder, facingHub(Landmarks.at(180, outerLoop + 32, y)))
	place("MarketStall", 169, outerLoop + 30, 8, 6, standInStall, 30)
	place("MarketStall", 191, outerLoop + 30, 8, 6, standInStall, -30)
	place("Campfire", 180, outerLoop + 12, 3.5, 5)

	-- Northwest beach: the lighthouse, the pier and a fishing hut
	place("Lighthouse", -45, island + 6, 40, 8, standInLighthouse)
	place("FishingHut", -60, island - 2, 11, 7)
	local pierStart = Landmarks.at(Landmarks.PIER_BEARING, island + 4, y)
	local pierEnd = Landmarks.at(Landmarks.PIER_BEARING, island + 4 + Landmarks.PIER_LENGTH, y)
	local pierFrame = CFrame.lookAt((pierStart + pierEnd) / 2, pierEnd)
	part(folder, {
		Name = "Pier",
		Size = Vector3.new(Landmarks.PIER_WIDTH, 1, Landmarks.PIER_LENGTH + 4),
		CFrame = pierFrame * CFrame.new(0, 0.6, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 112, 75),
	})
	for i = 0, 6 do
		for _, side in { -1, 1 } do
			column(
				folder,
				pierFrame
					* CFrame.new(
						side * (Landmarks.PIER_WIDTH / 2 - 0.4),
						-10,
						-Landmarks.PIER_LENGTH / 2 + i * Landmarks.PIER_LENGTH / 6
					),
				1.1,
				13.5,
				{
					Name = "Piling",
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(95, 70, 48),
					CanCollide = false,
				}
			)
		end
	end
	-- Rails keep players on the pier (the sea stays off limits)
	for _, side in { -1, 1 } do
		part(folder, {
			Name = "PierRail",
			Size = Vector3.new(0.4, 2.6, Landmarks.PIER_LENGTH),
			CFrame = pierFrame * CFrame.new(side * Landmarks.PIER_WIDTH / 2, 2.3, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(110, 80, 52),
		})
		part(folder, {
			Name = "PierWall",
			Size = Vector3.new(0.6, 60, Landmarks.PIER_LENGTH + 4),
			CFrame = pierFrame * CFrame.new(side * (Landmarks.PIER_WIDTH / 2 + 0.4), 30, 0),
			Transparency = 1,
			CanQuery = false,
		})
	end
	part(folder, {
		Name = "PierWall",
		Size = Vector3.new(Landmarks.PIER_WIDTH + 2, 60, 0.6),
		CFrame = pierFrame * CFrame.new(0, 30, -Landmarks.PIER_LENGTH / 2 - 1.5),
		Transparency = 1,
		CanQuery = false,
	})
	prop(
		"Dock",
		folder,
		pierFrame * CFrame.new(5, -1.2, -Landmarks.PIER_LENGTH / 2 + 4) * CFrame.Angles(0, math.rad(90), 0),
		5
	)
	keep(pierStart, 8)

	-- The north: windmill, stone circle, ruins
	place("Windmill", -22, outerLoop + 40, 30, 10, standInWindmill)
	place("FlowerMeadow", -14, outerLoop + 50, 3, 8)
	place("FlowerMeadow", -34, outerLoop + 28, 3, 8)
	place("StoneCircle", 12, options.zoneOuter + 22, 9, 12, standInStones)
	place("RuinsArch", 28, outerLoop + 30, 12, 14, standInRuins)

	-- Northeast: the cliff waterfall, its stream to the sea and the footbridge
	local cliff = Landmarks.at(50, island - 8, y)
	keep(cliff, 22)
	prop("WaterfallCliff", folder, CFrame.lookAt(cliff, Vector3.new(0, y, 0)), 30, standInCliff)
	-- The stream: from the waterfall's pool it runs along the coast, then out to sea
	-- (the island ground is one solid part, so the water is a strip of parts)
	local water = {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(80, 165, 220),
		Transparency = 0.12,
		Reflectance = 0.15,
	}
	local bends = {
		Landmarks.at(46, island - 30, y),
		Landmarks.at(70, island - 24, y),
		Landmarks.at(77, island + 28, y),
	}
	for i = 1, #bends - 1 do
		local from, to = bends[i], bends[i + 1]
		local frame = CFrame.lookAt((from + to) / 2, to)
		local length = (to - from).Magnitude + 8
		trim(folder, {
			Name = "Stream",
			Size = Vector3.new(8, 0.2, length),
			CFrame = frame * CFrame.new(0, 0.12, 0),
			Material = water.Material,
			Color = water.Color,
			Transparency = water.Transparency,
			Reflectance = water.Reflectance,
		})
		trim(folder, {
			Name = "StreamBank",
			Size = Vector3.new(10.5, 0.16, length),
			CFrame = frame * CFrame.new(0, 0.09, 0),
			Material = Enum.Material.Sand,
			Color = Color3.fromRGB(200, 185, 145),
		})
		table.insert(paths, { from = from, to = to, width = 14 })
	end
	trim(folder, {
		Name = "Pool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.22, 18, 18),
		CFrame = CFrame.new(bends[1] + Vector3.new(0, 0.13, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = water.Material,
		Color = water.Color,
		Transparency = water.Transparency,
		Reflectance = water.Reflectance,
	})
	-- The east campsite's path crosses it on a footbridge
	local crossing = Landmarks.at(58, island - 27, y)
	local across = CFrame.lookAt(crossing, Vector3.new(0, y, 0))
	local bridge = prop("WoodBridge", folder, across, 4)
	part(folder, {
		Name = "BridgeDeck",
		Size = Vector3.new(7, 0.6, 16),
		CFrame = across * CFrame.new(0, 0.4, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 112, 75),
		Transparency = if bridge then 1 else 0,
	})
	place("CampTents", 61, island - 8, 7, 12, standInTents, 90)
	place("Campfire", 55, island - 9, 3.5, 4)

	-- The east and southeast: a second stone circle and palms on the beach
	place("StoneCircle", 118, options.zoneOuter + 26, 8, 12, standInStones, 40)
	for i = 0, 7 do
		place("PalmTree", 95 + i * 7.5, island + 4 + (i % 2) * 6, 16 + (i % 3) * 2, 3, standInPalm, i * 47)
	end

	-- The south: a campsite, the event grounds (above) and pines toward the beach
	place("CampTents", 205, outerLoop + 38, 7, 12, standInTents, 180)
	place("Campfire", 205, outerLoop + 28, 3.5, 4)
	for i = 0, 9 do
		place("PineTree", 150 + i * 6 + (i % 2) * 2, island - 14 - (i % 3) * 7, 18 + (i % 3) * 3, 4)
	end

	-- Southwest beach: the shipwreck
	place("Shipwreck", 228, island + 8, 16, 16, nil, 110)
	place("Boulders", 238, island - 10, 6, 6, standInBoulders)

	-- The west woods: oaks and pines, palms on the western beach
	for i = 0, 15 do
		local bearing = 248 + i * 4
		local distance = outerLoop + 14 + (i % 4) * 11
		if i % 3 == 0 then
			place("PineTree", bearing, distance, 20 + (i % 2) * 3, 4)
		else
			place("OakTree", bearing, distance, 17 + (i % 3) * 2, 6, standInTree, i * 31)
		end
	end
	for i = 0, 4 do
		place("PalmTree", 262 + i * 9, island + 5, 16 + (i % 2) * 3, 3, standInPalm, i * 61)
	end

	-- Meadows and boulders across the open land
	for _, spot in { { 150, 0.4 }, { 210, 0.6 }, { 300, 0.3 }, { 330, 0.7 }, { 95, 0.5 }, { 60, 0.2 } } do
		place("FlowerMeadow", spot[1], options.zoneOuter + 14 + spot[2] * 40, 3, 7)
	end
	for _, spot in { { 135, 0.6 }, { 245, 0.2 }, { 320, 0.8 }, { 20, 0.9 }, { 160, 0.2 } } do
		place("Boulders", spot[1], options.zoneOuter + 14 + spot[2] * 70, 6, 6, standInBoulders, spot[1])
	end

	return {
		clear = clear,
		paths = paths,
		eventBoard = board,
		pier = { from = pierStart, to = pierEnd },
	}
end

return Landmarks

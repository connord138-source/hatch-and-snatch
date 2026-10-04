--!strict
-- The Luck Wheel's stand, built from parts (docs/GDD.md §3.1). Owner, 2026-10-04:
-- "the spin wheel needs a major upgrade, both looks wise as well as functionality.
-- It is VERY crude and glitchy." So it's a game-show wheel on a marble stage:
-- true pie slices (pairs of wedges, no gaps), a gold rim with pegs that a red
-- flapper ticks against, a lacquered frame and an arch sign ringed with marquee
-- bulbs between two pillars, a big red button on a podium, and two boards (the
-- prizes' odds, and where spins come from). WheelService spins it;
-- LuckWheelController animates the disc, the flapper and the bulbs on each client.
--
-- Layout, in the wheel's own frame (`base`): the origin is the wheel's center, -Z
-- faces the hub (the front), +Y is up, so +X is on the viewer's left. Slice i is
-- centered (i - 1) × slice counter-clockwise from the top as seen from the front,
-- and the wheel turns clockwise, so turning it by that angle brings slice i under
-- the flapper. Pegs sit every 360 / PEGS degrees, starting at the top.
local CollectionService = game:GetService("CollectionService")

local LuckWheel = {}

LuckWheel.TAG = "LuckWheel" -- on the whole model; the client binds to it as it streams in
LuckWheel.RADIUS = 9 -- the slices' radius
LuckWheel.HEIGHT = 14 -- the wheel's center above the ground
LuckWheel.PEGS = 24
LuckWheel.CLEAR_RADIUS = 26 -- keep scenery this far from the wheel (stage and boards)

export type Segment = {
	label: string,
	kind: string,
	value: number,
	weight: number,
	color: Color3,
	icon: string,
	big: string,
	sub: string,
}

export type Built = {
	model: Model, -- tagged LuckWheel, streams in and out whole
	disc: Model, -- everything that turns; rotate with base * CFrame.Angles(0, 0, angle)
	base: CFrame,
	prompt: ProximityPrompt, -- "Spin" (E) on the big red button
	spinAllPrompt: ProximityPrompt, -- "Spin all" (R)
	status: TextLabel, -- RichText line on the arch sign (who's spinning, who won)
}

local R = LuckWheel.RADIUS
local H = LuckWheel.HEIGHT
local SLICE_STEPS = 5 -- triangles per slice; at radius 9 the edge is round to the eye
local FRAME_R = R + 1.55 -- the lacquered frame round the wheel
local PILLAR_X = 13.4
local SIGN_Y = FRAME_R + 3.4 -- the arch sign's center, above the wheel's center
local STAGE_TOP = 1.8 -- the upper step's top above the ground
local FLAPPER_PIVOT = Vector3.new(0, R + 1.4, -0.85)
local PEG_RADIUS = R - 0.55

local GOLD = Color3.fromRGB(255, 196, 64)
local GOLD_LIGHT = Color3.fromRGB(255, 224, 140)
local CRIMSON = Color3.fromRGB(128, 18, 40)
local CRIMSON_DARK = Color3.fromRGB(80, 12, 28)
local MARBLE = Color3.fromRGB(226, 220, 210)
local BACKING = Color3.fromRGB(26, 22, 44)
local BULB = Color3.fromRGB(255, 236, 190)
local TEXT_STROKE = Color3.fromRGB(40, 8, 18)

local function apply(p: BasePart, props: { [string]: any })
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
end

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	apply(p, props)
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, props: { [string]: any }): WedgePart
	local w = Instance.new("WedgePart")
	apply(w, props)
	w.Parent = parent
	return w
end

-- A flat triangle a-b-c, `thickness` thick, as two right-angled wedges that meet
-- on the altitude from its longest edge.
local function triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	props: { [string]: any }
): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	-- Now bc is the longest edge and a the corner across from it
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local first = wedge(parent, props)
	first.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local second = wedge(parent, props)
	second.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return { first, second }
end

-- A point on the wheel's face: `theta` counter-clockwise from the top (as seen
-- from the front), `radius` out from the center, `z` toward the back.
local function onFace(base: CFrame, theta: number, radius: number, z: number): Vector3
	return base * Vector3.new(math.sin(theta) * radius, math.cos(theta) * radius, z)
end

-- The frame of a piece standing on the face at `theta`: +Y points out from the center.
local function radial(base: CFrame, theta: number, radius: number, z: number): CFrame
	return base * CFrame.Angles(0, 0, -theta) * CFrame.new(0, radius, z)
end

-- A ring of short cylinders standing in for a torus, round the wheel's center.
local function ring(
	parent: Instance,
	base: CFrame,
	radius: number,
	tube: number,
	z: number,
	count: number,
	props: { [string]: any }
)
	local length = 2 * radius * math.sin(math.pi / count) + tube * 0.4
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, tube, tube)
	for i = 0, count - 1 do
		-- A cylinder's axis is its X, which lies along the ring here
		props.CFrame = radial(base, (i + 0.5) / count * 2 * math.pi, radius * math.cos(math.pi / count), z)
		part(parent, props)
	end
end

-- A cylinder whose axis runs front to back (a hub, a peg, a crest).
local function facing(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, math.pi / 2, 0)
end

-- A cylinder standing upright.
local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

local function surface(target: BasePart, face: Enum.NormalId, canvas: Vector2): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = canvas
	gui.LightInfluence = 0 -- reads at night too
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.Parent = target
	return gui
end

-- A scaled TextLabel with a dark outline `stroke` canvas pixels thick.
local function text(parent: Instance, stroke: number, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(label :: any)[key] = value
	end
	local outline = Instance.new("UIStroke")
	outline.Color = TEXT_STROKE
	outline.Thickness = stroke
	outline.Parent = label
	label.Parent = parent
	return label
end

local function bulb(parent: Instance, cf: CFrame, size: number, group: string, index: number): Part
	local b = part(parent, {
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = cf,
		Material = Enum.Material.Neon,
		Color = BULB,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	b:SetAttribute("Group", group)
	b:SetAttribute("Index", index)
	return b
end

---------------------------------------------------------------------------
-- The disc: everything that turns
---------------------------------------------------------------------------

local function buildDisc(parent: Instance, base: CFrame, segments: { Segment }): Model
	local disc = Instance.new("Model")
	disc.Name = "WheelDisc"
	local loose = { CanCollide = false, CanQuery = false, CanTouch = false }

	local hub = part(disc, {
		Name = "Hub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 5.6, 5.6),
		CFrame = facing(base * CFrame.new(0, 0, -0.3)),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})
	part(disc, {
		Name = "HubRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 4.2, 4.2),
		CFrame = facing(base * CFrame.new(0, 0, -0.55)),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		CanCollide = false,
	})
	local dome = part(disc, {
		Name = "HubDome",
		Size = Vector3.new(3.4, 3.4, 1.8),
		CFrame = base * CFrame.new(0, 0, -0.8),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = dome
	local jewel = part(disc, {
		Name = "Jewel",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = base * CFrame.new(0, 0, -1.6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 60, 110),
		CanCollide = false,
		CastShadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 90, 140)
	glow.Range = 8
	glow.Brightness = 1.2
	glow.Parent = jewel
	part(disc, {
		Name = "Backing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, R * 2 + 1, R * 2 + 1),
		CFrame = facing(base * CFrame.new(0, 0, 0.35)),
		Material = Enum.Material.SmoothPlastic,
		Color = BACKING,
		CanCollide = false,
	})

	-- Slices: true pie wedges, a fan of triangles each, meeting the rim with no gaps
	local slice = 2 * math.pi / #segments
	for i, segment in segments do
		local center = (i - 1) * slice
		local props = {
			Name = "Slice",
			Material = Enum.Material.SmoothPlastic,
			Color = segment.color,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}
		for step = 0, SLICE_STEPS - 1 do
			local from = center - slice / 2 + step * slice / SLICE_STEPS
			local to = from + slice / SLICE_STEPS
			local pieces = triangle(
				disc,
				base * Vector3.new(0, 0, 0),
				onFace(base, from, R, 0),
				onFace(base, to, R, 0),
				0.3,
				props
			)
			for _, piece in pieces do
				piece:SetAttribute("Slice", i)
			end
		end
		-- Gold divider on the slice's leading edge
		part(disc, {
			Name = "Divider",
			Size = Vector3.new(0.3, R - 2.6, 0.2),
			CFrame = radial(base, center + slice / 2, (R + 2.6) / 2, -0.22),
			Material = Enum.Material.Foil,
			Color = GOLD_LIGHT,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})

		-- Icon near the rim, then the prize in two lines; upright when the slice is on top
		local iconPart = part(disc, {
			Name = "SliceIcon",
			Size = Vector3.new(2.6, 2.6, 0.05),
			CFrame = radial(base, center, R * 0.72, -0.2),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		text(surface(iconPart, Enum.NormalId.Front, Vector2.new(200, 200)), 2, {
			Size = UDim2.fromScale(1, 1),
			Text = segment.icon,
		})
		local labelPart = part(disc, {
			Name = "SliceLabel",
			Size = Vector3.new(4.4, 2.2, 0.05),
			CFrame = radial(base, center, R * 0.47, -0.2),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		local gui = surface(labelPart, Enum.NormalId.Front, Vector2.new(440, 220))
		text(gui, 5, { Size = UDim2.fromScale(1, 0.62), Text = segment.big })
		text(gui, 4, {
			Position = UDim2.fromScale(0.08, 0.62),
			Size = UDim2.fromScale(0.84, 0.36),
			Text = segment.sub,
		})
		if segment.kind == "luck" and segment.value >= 25 then
			-- The jackpot slice glitters
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170))
			sparkle.LightEmission = 1
			sparkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Lifetime = NumberRange.new(0.6, 1.2)
			sparkle.Rate = 5
			sparkle.Speed = NumberRange.new(0.3, 0.8)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = iconPart
		end
	end

	-- Rim and pegs (the pegs at slice edges have bigger, lit heads)
	local rimProps: { [string]: any } = table.clone(loose)
	rimProps.Name = "Rim"
	rimProps.Material = Enum.Material.Foil
	rimProps.Color = GOLD
	ring(disc, base, R + 0.35, 0.9, -0.05, 36, rimProps)
	local perSlice = LuckWheel.PEGS // #segments
	for k = 0, LuckWheel.PEGS - 1 do
		local theta = k / LuckWheel.PEGS * 2 * math.pi
		local edge = perSlice > 0 and k % perSlice == perSlice // 2
		part(disc, {
			Name = "Peg",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 0.32, 0.32),
			CFrame = facing(radial(base, theta, PEG_RADIUS, -0.65)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(225, 225, 235),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		local head = if edge then 0.62 else 0.46
		part(disc, {
			Name = "PegHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(head, head, head),
			CFrame = radial(base, theta, PEG_RADIUS, -1.2),
			Material = if edge then Enum.Material.Neon else Enum.Material.Foil,
			Color = if edge then BULB else GOLD,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
	end

	disc.PrimaryPart = hub
	-- A model with a PrimaryPart pivots on it, so move the hub's pivot to the
	-- wheel's center (the hub itself is turned 90°)
	hub.PivotOffset = hub.CFrame:ToObjectSpace(base)
	local count = 0
	for _, descendant in disc:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	disc:SetAttribute("Parts", count) -- the client waits until it has them all
	disc.Parent = parent
	return disc
end

---------------------------------------------------------------------------
-- The flapper: pivots at its top; the client swings it as pegs pass
---------------------------------------------------------------------------

local function buildFlapper(parent: Instance, base: CFrame): Model
	local flapper = Instance.new("Model")
	flapper.Name = "Flapper"
	local loose = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	local function point(x: number, y: number, z: number): Vector3
		return base * Vector3.new(x, y, z)
	end
	local outline: { [string]: any } = table.clone(loose)
	outline.Name = "FlapperTrim"
	outline.Material = Enum.Material.Foil
	outline.Color = GOLD
	triangle(
		flapper,
		point(-1.05, R + 1.75, -0.62),
		point(1.05, R + 1.75, -0.62),
		point(0, R - 1.4, -0.62),
		0.16,
		outline
	)
	local arrow: { [string]: any } = table.clone(loose)
	arrow.Name = "FlapperArrow"
	arrow.Material = Enum.Material.SmoothPlastic
	arrow.Color = Color3.fromRGB(225, 32, 52)
	triangle(
		flapper,
		point(-0.8, R + 1.6, -0.85),
		point(0.8, R + 1.6, -0.85),
		point(0, R - 1.05, -0.85),
		0.3,
		arrow
	)
	local cap: { [string]: any } = table.clone(loose)
	cap.Name = "FlapperCap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.6, 0.9, 0.9)
	cap.CFrame = facing(base * CFrame.new(FLAPPER_PIVOT.X, FLAPPER_PIVOT.Y, -1.15))
	cap.Material = Enum.Material.Foil
	cap.Color = GOLD_LIGHT
	part(flapper, cap)
	flapper:SetAttribute("PivotCFrame", base * CFrame.new(FLAPPER_PIVOT))
	local count = 0
	for _, child in flapper:GetChildren() do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	flapper:SetAttribute("Parts", count)
	flapper.Parent = parent
	return flapper
end

---------------------------------------------------------------------------
-- Boards beside the stage
---------------------------------------------------------------------------

local function board(parent: Instance, origin: CFrame, title: string, body: string)
	local folder = Instance.new("Model")
	folder.Name = "WheelBoard"
	for _, x in { -3.2, 3.2 } do
		part(folder, {
			Name = "Post",
			Size = Vector3.new(0.45, 9.2, 0.45),
			CFrame = origin * CFrame.new(x, 4.6, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
	end
	part(folder, {
		Name = "Plate",
		Size = Vector3.new(7.6, 6.8, 0.25),
		CFrame = origin * CFrame.new(0, 5.6, 0.3),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local panel = part(folder, {
		Name = "Panel",
		Size = Vector3.new(7, 6.2, 0.4),
		CFrame = origin * CFrame.new(0, 5.6, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
	})
	part(folder, {
		Name = "Cap",
		Size = Vector3.new(7.9, 0.4, 0.9),
		CFrame = origin * CFrame.new(0, 9.1, 0.2),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local gui = surface(panel, Enum.NormalId.Front, Vector2.new(560, 496))
	text(gui, 4, {
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.17),
		Font = Enum.Font.LuckiestGuy,
		Text = title,
		TextColor3 = GOLD_LIGHT,
	})
	local lines = text(gui, 2, {
		Position = UDim2.fromScale(0.07, 0.23),
		Size = UDim2.fromScale(0.86, 0.72),
		Font = Enum.Font.GothamBold,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = body,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 40
	limit.Parent = lines
	folder.Parent = parent
end

---------------------------------------------------------------------------
-- The whole wheel
---------------------------------------------------------------------------

-- Builds the wheel standing on `ground`, its face turned toward `faceToward`.
-- `freeSpinMinutes` and `maxBanked` fill in the spins board.
function LuckWheel.build(
	parent: Instance,
	ground: Vector3,
	faceToward: Vector3,
	segments: { Segment },
	freeSpinMinutes: number,
	maxBanked: number
): Built
	local target = Vector3.new(faceToward.X, ground.Y + H, faceToward.Z)
	local base = CFrame.lookAt(ground + Vector3.new(0, H, 0), target)
	local floor = base * CFrame.new(0, -H, 0) -- the same frame, on the ground
	local model = Instance.new("Model")
	model.Name = "LuckWheel"
	model:SetAttribute("BaseCFrame", base)
	model:SetAttribute("Pegs", LuckWheel.PEGS)

	-- Stage: two marble steps with gold edges, and a carpet to the button
	local steps = { { 35, 0 }, { 29, STAGE_TOP / 2 } }
	for index, step in steps do
		local diameter, bottom = step[1], step[2]
		local top = bottom + STAGE_TOP / 2
		part(model, {
			Name = "Stage",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(STAGE_TOP / 2, diameter, diameter),
			CFrame = upright(floor * CFrame.new(0, bottom + STAGE_TOP / 4, 0)),
			Material = Enum.Material.Marble,
			Color = MARBLE,
		})
		part(model, {
			Name = "StageTrim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, diameter + 0.3, diameter + 0.3),
			CFrame = upright(floor * CFrame.new(0, top - 0.12, 0)),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
		-- Carpet across this step's front, from the podium out
		local inner = if index == 2 then 10.8 else 29 / 2 + 0.1
		local outer = math.sqrt((diameter / 2) ^ 2 - 2.5 ^ 2) - 0.05
		part(model, {
			Name = "Carpet",
			Size = Vector3.new(5, 0.08, outer - inner),
			CFrame = floor * CFrame.new(0, top + 0.04, -(inner + outer) / 2),
			Material = Enum.Material.Fabric,
			Color = Color3.fromRGB(150, 20, 45),
			CanCollide = false,
		})
	end

	-- Back post and axle
	part(model, {
		Name = "Post",
		Size = Vector3.new(1.8, H - STAGE_TOP + 0.9, 1.4),
		CFrame = floor * CFrame.new(0, (STAGE_TOP + H + 0.9) / 2, 2.4),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON_DARK,
	})
	part(model, {
		Name = "Axle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 1.2, 1.2),
		CFrame = facing(base * CFrame.new(0, 0, 1.5)),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})

	-- Frame round the wheel: lacquer tube, gold pinstripe, marquee bulbs
	local lacquer: { [string]: any } = {
		Name = "Frame",
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
		Reflectance = 0.06,
		CanCollide = false,
	}
	ring(model, base, FRAME_R, 1.3, 0.15, 36, lacquer)
	ring(model, base, FRAME_R + 0.75, 0.35, 0, 36, {
		Name = "FrameTrim",
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
		CastShadow = false,
	})
	local bulbs = Instance.new("Model")
	bulbs.Name = "Bulbs"
	local ringBulbs = 32
	for i = 0, ringBulbs - 1 do
		-- Numbered clockwise from the top (as seen from the front), so the chase runs with the wheel
		bulb(bulbs, radial(base, -i / ringBulbs * 2 * math.pi, FRAME_R, -0.75), 0.62, "Ring", i + 1)
	end
	part(model, {
		Name = "FlapperMount", -- the client's tick sounds and confetti come from here
		Size = Vector3.new(1.8, 1.4, 1),
		CFrame = base * CFrame.new(0, FRAME_R + 0.2, -0.9),
		Material = Enum.Material.Foil,
		Color = GOLD,
		CanCollide = false,
	})

	-- Pillars either side, gold arms to the frame
	for _, side in { -1, 1 } do
		local x = side * PILLAR_X
		local bottom = -H + STAGE_TOP
		local top = SIGN_Y + 2.7
		part(model, {
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(top - bottom, 1.9, 1.9),
			CFrame = upright(base * CFrame.new(x, (top + bottom) / 2, 0.3)),
			Material = Enum.Material.SmoothPlastic,
			Color = CRIMSON,
			Reflectance = 0.06,
		})
		part(model, {
			Name = "PillarFoot",
			Size = Vector3.new(3, 1.6, 3),
			CFrame = base * CFrame.new(x, bottom + 0.8, 0.3),
			Material = Enum.Material.Marble,
			Color = MARBLE,
		})
		for _, y in { bottom + 1.7, -6, 2, 10, top - 0.4 } do
			part(model, {
				Name = "PillarBand",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 2.15, 2.15),
				CFrame = upright(base * CFrame.new(x, y, 0.3)),
				Material = Enum.Material.Foil,
				Color = GOLD,
				CanCollide = false,
			})
		end
		part(model, {
			Name = "PillarCap",
			Size = Vector3.new(2.8, 0.9, 2.8),
			CFrame = base * CFrame.new(x, top + 0.45, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
		part(model, {
			Name = "Finial",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = base * CFrame.new(x, top + 1.8, 0.3),
			Material = Enum.Material.Foil,
			Color = GOLD,
		})
		bulb(bulbs, base * CFrame.new(x, top + 3, 0.3), 0.8, "Finial", 1)
		for i = 0, 8 do
			bulb(bulbs, base * CFrame.new(x, -9 + i * 2.6, -0.72), 0.5, "Pillar", i + 1)
		end
		part(model, {
			Name = "Arm",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PILLAR_X - FRAME_R - 0.2, 0.7, 0.7),
			CFrame = base * CFrame.new(side * (FRAME_R + PILLAR_X) / 2, 0, 0.2),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
		part(model, {
			Name = "ArmJoint",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = base * CFrame.new(side * (FRAME_R + 0.6), 0, 0.15),
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
		})
	end

	-- Arch sign across the pillars, with a crest and bulbs along both edges
	local signWidth = PILLAR_X * 2 - 1.9
	local sign = part(model, {
		Name = "Sign",
		Size = Vector3.new(signWidth, 4.4, 0.8),
		CFrame = base * CFrame.new(0, SIGN_Y, -0.3),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
	})
	part(model, {
		Name = "SignPlate",
		Size = Vector3.new(signWidth + 1, 5.4, 0.5),
		CFrame = base * CFrame.new(0, SIGN_Y, 0.1),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "CrestTrim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 8.8, 8.8),
		CFrame = facing(base * CFrame.new(0, SIGN_Y + 2.2, 0.45)),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	local crest = part(model, {
		Name = "Crest",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 8, 8),
		CFrame = facing(base * CFrame.new(0, SIGN_Y + 2.2, 0.2)),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON_DARK,
	})
	-- A cylinder's flat end is its Right face, which the turn above points at the front
	text(surface(crest, Enum.NormalId.Right, Vector2.new(400, 400)), 2, {
		Position = UDim2.fromScale(0.27, 0.04),
		Size = UDim2.fromScale(0.46, 0.4),
		Text = "🍀",
	})
	for i = 0, 8 do
		local theta = (i / 8 - 0.5) * math.pi * 0.9
		bulb(
			bulbs,
			base * CFrame.new(-math.sin(theta) * 4.4, SIGN_Y + 2.2 + math.cos(theta) * 4.4, -0.1),
			0.5,
			"Crest",
			i + 1
		)
	end
	local edgeBulbs = 20
	for i = 0, edgeBulbs - 1 do
		local x = (i / (edgeBulbs - 1) - 0.5) * (signWidth - 0.6)
		bulb(bulbs, base * CFrame.new(-x, SIGN_Y + 2.45, -0.45), 0.5, "Sign", i + 1)
		bulb(bulbs, base * CFrame.new(x, SIGN_Y - 2.45, -0.45), 0.5, "Sign", edgeBulbs + i + 1)
	end
	local signGui = surface(sign, Enum.NormalId.Front, Vector2.new(1245, 220))
	text(signGui, 6, {
		Position = UDim2.fromScale(0, 0.02),
		Size = UDim2.fromScale(1, 0.6),
		Font = Enum.Font.LuckiestGuy,
		Text = "LUCK WHEEL",
		TextColor3 = Color3.fromRGB(255, 214, 90),
	})
	local status = text(signGui, 3, {
		Position = UDim2.fromScale(0.04, 0.63),
		Size = UDim2.fromScale(0.92, 0.32),
		Font = Enum.Font.GothamBold,
		RichText = true,
		Text = "Press the big red button to spin!",
	})
	bulbs.Parent = model

	-- Light on the wheel's face (it reads at night)
	local lamp = part(model, {
		Name = "WheelLamp",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = base * CFrame.new(0, 2, -8),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Range = 20
	light.Brightness = 1.1
	light.Parent = lamp

	-- Podium with the big red button
	local podiumZ = -10
	part(model, {
		Name = "Podium",
		Size = Vector3.new(2.2, 3, 2.2),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 1.5, podiumZ),
		Material = Enum.Material.SmoothPlastic,
		Color = CRIMSON,
	})
	local podiumFront = part(model, {
		Name = "PodiumFace",
		Size = Vector3.new(2, 1.2, 0.05),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 1.8, podiumZ - 1.13),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	text(surface(podiumFront, Enum.NormalId.Front, Vector2.new(200, 120)), 3, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.LuckiestGuy,
		Text = "SPIN!",
		TextColor3 = GOLD_LIGHT,
	})
	part(model, {
		Name = "PodiumFoot",
		Size = Vector3.new(2.7, 0.3, 2.7),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 0.15, podiumZ),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "PodiumCap",
		Size = Vector3.new(2.7, 0.35, 2.7),
		CFrame = floor * CFrame.new(0, STAGE_TOP + 3.175, podiumZ),
		Material = Enum.Material.Foil,
		Color = GOLD,
	})
	part(model, {
		Name = "ButtonRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = upright(floor * CFrame.new(0, STAGE_TOP + 3.5, podiumZ)),
		Material = Enum.Material.Foil,
		Color = GOLD_LIGHT,
	})
	local button = part(model, {
		Name = "SpinButton",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 1.6, 1.6),
		CFrame = upright(floor * CFrame.new(0, STAGE_TOP + 3.75, podiumZ)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 60),
	})
	local buttonGlow = Instance.new("PointLight")
	buttonGlow.Color = Color3.fromRGB(255, 60, 70)
	buttonGlow.Range = 6
	buttonGlow.Brightness = 1
	buttonGlow.Parent = button

	-- Boards either side: the odds (slices are drawn equal) and where spins come from
	local total = 0
	for _, segment in segments do
		total += segment.weight
	end
	local odds: { string } = {}
	for _, segment in segments do
		table.insert(
			odds,
			`<font color="#{segment.color:ToHex()}">◆</font> {segment.icon} {segment.label}  <b>{math.floor(
				segment.weight / total * 100 + 0.5
			)}%</b>`
		)
	end
	board(
		model,
		floor * CFrame.new(-17, 0, -7) * CFrame.Angles(0, math.rad(-25), 0),
		"PRIZES & ODDS",
		table.concat(odds, "\n")
	)
	board(
		model,
		floor * CFrame.new(17, 0, -7) * CFrame.Angles(0, math.rad(25), 0),
		"FREE SPINS",
		`🎡 1 spin every {freeSpinMinutes} min you play (up to {maxBanked} banked)\n🏆 Achievements, daily rewards and rebirths\n🍀 Luck charges your NEXT egg; your best charge is kept\n⏩ Busy? Press anyway to join the line`
	)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinWheel"
	prompt.ActionText = "Spin"
	prompt.ObjectText = "Luck Wheel"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = button
	local spinAll = Instance.new("ProximityPrompt")
	spinAll.Name = "SpinAll"
	spinAll.ActionText = "Spin all"
	spinAll.ObjectText = "Luck Wheel"
	spinAll.KeyboardKeyCode = Enum.KeyCode.R
	spinAll.HoldDuration = 0.6
	spinAll.MaxActivationDistance = 10
	spinAll.RequiresLineOfSight = false
	-- Below the Spin prompt: both sit on the button, and at the same offset Spin all
	-- covered it (playtest 2026-10-04)
	spinAll.UIOffset = Vector2.new(0, 76)
	spinAll.Parent = button

	local disc = buildDisc(model, base, segments)
	buildFlapper(model, base)

	-- Stream the wheel in and out whole, so the client never holds half a disc
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, LuckWheel.TAG)
	model.Parent = parent
	return {
		model = model,
		disc = disc,
		base = base,
		prompt = prompt,
		spinAllPrompt = spinAll,
		status = status,
	}
end

return LuckWheel

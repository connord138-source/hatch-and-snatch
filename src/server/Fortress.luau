--!strict
-- The fortress around a plot: walls, corner towers and a gatehouse that grow with
-- the base level (Config.BaseBuilds.tiers; owner, 2026-10-01: the boxy plot looked
-- plain). 1 Camp: a picket fence. 2 Stockade: log palisade and wooden watchtowers.
-- 3 Keep: stone walls with battlements, stone towers and a gatehouse. 4 Fortress:
-- taller walls, four roofed towers with flags, braziers. 5 Citadel: pale stone and
-- gold, crystal-tipped spires.
--
-- Built from parts so it always works. When a tower or gatehouse model is imported
-- (WorldProps.TowerStone and so on, see docs/ASSETS.md) it replaces the part-built
-- one, and an invisible collider keeps its footprint solid. From the Stockade up
-- the walls are too tall to jump, so the gate (where the laser lock is) is the way
-- in. Everything is plot-local: -Z faces the hub, y 0 is the ground.
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CastleKits = require(script.Parent.CastleKits)
local Props = require(script.Parent.Props)

export type Layout = {
	halfW: number, -- wall center line, either side
	front: number, -- front wall center line (z)
	back: number, -- back wall center line (z)
	gateHalf: number, -- half the gate opening
	height: number, -- wall height
	thickness: number,
	level: number,
	frontTowers: number, -- the front corner towers' radius (0 without any)
	gatehouse: boolean, -- a gatehouse stands over the gate
	gateOuter: number, -- half the gate structure's width along the wall (decor keeps clear)
}

type Style = {
	wall: "fence" | "palisade" | "stone",
	height: number,
	thickness: number,
	towers: "none" | "back" | "all",
	tower: "wood" | "stone" | "roofed" | "spire" | "none",
	towerHeight: number,
	towerRadius: number,
	gatehouse: boolean,
	braziers: boolean,
	pale: boolean, -- the Citadel's cream stone and gold
	towerProp: string?,
	gateProp: string?,
	gateWidth: number?, -- the gatehouse model's width, fitted
	-- Where the front walls end inside the model (plot-local |x|): in its end towers,
	-- as the Citadel model's wings are lower than the walls (owner, 2026-10-02: the
	-- walls' merlons and caps cut through its turrets)
	gateJoin: number?,
}

local GAP = 2 -- walls stand this far outside the plot edge
local GATE_HALF = 7 -- the gate opening is 14 studs wide
local GATE_CLEAR = 12 -- and this tall

local STYLES: { Style } = {
	{
		wall = "fence",
		height = 3.2,
		thickness = 0.5,
		towers = "none",
		tower = "none",
		towerHeight = 0,
		towerRadius = 0,
		gatehouse = false,
		braziers = false,
		pale = false,
	},
	{
		wall = "palisade",
		height = 9,
		thickness = 1.4,
		towers = "back",
		tower = "wood",
		towerHeight = 17,
		towerRadius = 3.5,
		gatehouse = false,
		braziers = false,
		pale = false,
		towerProp = "WatchtowerWood",
	},
	{
		wall = "stone",
		height = 10,
		thickness = 2.4,
		towers = "back",
		tower = "stone",
		towerHeight = 17,
		towerRadius = 4.5,
		gatehouse = true,
		braziers = false,
		pale = false,
		towerProp = "TowerStone",
		gateProp = "GatehouseStone",
		gateWidth = 26,
		gateJoin = GATE_HALF + 4.5, -- inside its full-height end blocks (4.9 to 13)
	},
	{
		wall = "stone",
		height = 12,
		thickness = 2.6,
		towers = "all",
		tower = "roofed",
		towerHeight = 26,
		towerRadius = 5,
		gatehouse = true,
		braziers = true,
		pale = false,
		towerProp = "TowerRoofed",
		gateProp = "GatehouseStone",
		gateWidth = 26,
		gateJoin = GATE_HALF + 4.5,
	},
	{
		wall = "stone",
		height = 13,
		thickness = 2.8,
		towers = "all",
		tower = "spire",
		towerHeight = 38,
		towerRadius = 5.5,
		gatehouse = true,
		braziers = true,
		pale = true,
		towerProp = "TowerCitadel",
		gateProp = "GatehouseCitadel",
		gateWidth = 40,
		-- At its end towers' middles (they stand 12.5 to 20 out, peaking at 16; its
		-- wings are only 10 high), so the walls' end merlons hide inside them
		gateJoin = 16,
	},
}

local WOOD = Color3.fromRGB(128, 90, 58)
local WOOD_DARK = Color3.fromRGB(92, 64, 42)
local STONE = Color3.fromRGB(140, 134, 126)
local PALE = Color3.fromRGB(236, 226, 206)
local GOLD = Color3.fromRGB(240, 195, 70)
-- The Citadel's gold trim, which a custom design recolors (see build)
local GILDED = { GoldBand = true, WallCap = true, GateTrim = true, RoofCap = true }
local IRON = Color3.fromRGB(55, 55, 62)

type Look = {
	material: Enum.Material,
	color: Color3,
	roof: Color3,
	flag: Color3,
}

local Fortress = {}

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

-- A decorative part: no collision, no queries.
local function trim(parent: Instance, props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(parent, props)
end

-- A vertical cylinder standing on `base` (its bottom center).
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

-- The rebirth stones' twinkle: a few star glints on a tower's surface.
local function twinkle(tower: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Twinkle"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Rate = 5
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Parent = tower
end

function Fortress.style(level: number): Style
	return STYLES[math.clamp(level, 1, #STYLES)]
end

-- The stone of the walls (and of the keep floors inside): the theme's own, else
-- gray cobblestone, or pale limestone for the Citadel.
function Fortress.stone(level: number, theme: Config.BaseTheme): (Enum.Material, Color3)
	local wall = theme.wall
	if wall then
		return wall.material, wall.color
	end
	if Fortress.style(level).pale then
		return Enum.Material.Limestone, PALE
	end
	return Enum.Material.Cobblestone, STONE
end

-- Where the walls go for a plot of this size and level.
function Fortress.layout(level: number, width: number, depth: number, plotFront: number): Layout
	local style = Fortress.style(level)
	return {
		halfW = width / 2 + GAP,
		front = plotFront - GAP,
		back = plotFront + depth + GAP,
		gateHalf = GATE_HALF,
		height = style.height,
		thickness = style.thickness,
		level = level,
		frontTowers = if style.towers == "all" then style.towerRadius else 0,
		gatehouse = style.gatehouse,
		-- the part-built gatehouse's; build widens it for an imported model
		gateOuter = if style.gatehouse then GATE_HALF + 4.5 else GATE_HALF,
	}
end

-- One straight run of wall from a to b (plot-local, on the ground).
local function wallRun(folder: Instance, origin: CFrame, a: Vector3, b: Vector3, style: Style, look: Look)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	-- Z runs along the wall, X is its thickness
	local frame = origin * CFrame.lookAt((a + b) / 2, b)
	local h, t = style.height, style.thickness
	if style.wall == "fence" then
		-- A picket fence: a post every 4 studs and two rails (low enough to hop)
		local posts = math.max(1, math.floor(length / 4))
		for i = 0, posts do
			part(folder, {
				Name = "FencePost",
				Size = Vector3.new(0.6, h, 0.6),
				CFrame = frame * CFrame.new(0, h / 2, -length / 2 + i * length / posts),
				Material = Enum.Material.Wood,
				Color = WOOD_DARK,
			})
		end
		for _, y in { h * 0.42, h * 0.8 } do
			part(folder, {
				Name = "FenceRail",
				Size = Vector3.new(0.3, 0.45, length),
				CFrame = frame * CFrame.new(0, y, 0),
				Material = Enum.Material.WoodPlanks,
				Color = WOOD,
			})
		end
		return
	end
	if style.wall == "palisade" then
		-- Sharpened logs: a log wall with a pointed tip every 2.6 studs
		part(folder, {
			Name = "FortressWall",
			Size = Vector3.new(t, h - 1, length + t),
			CFrame = frame * CFrame.new(0, (h - 1) / 2, 0),
			Material = Enum.Material.Wood,
			Color = WOOD,
		})
		for _, y in { 1.6, h - 3 } do
			trim(folder, {
				Name = "WallBand",
				Size = Vector3.new(t + 0.3, 0.6, length + t),
				CFrame = frame * CFrame.new(0, y, 0),
				Material = Enum.Material.Wood,
				Color = WOOD_DARK,
			})
		end
		local tips = math.max(1, math.floor(length / 2.6))
		for i = 0, tips do
			trim(folder, {
				Name = "LogTip",
				Size = Vector3.new(t * 0.9, 1.7, 1.7),
				CFrame = frame
					* CFrame.new(0, h - 1, -length / 2 + i * length / tips)
					* CFrame.Angles(math.rad(45), 0, 0),
				Material = Enum.Material.Wood,
				Color = WOOD,
			})
		end
		return
	end
	-- Stone: a darker plinth, the wall, a walkway cap and battlements on top
	part(folder, {
		Name = "FortressWall",
		Size = Vector3.new(t, h, length + t),
		CFrame = frame * CFrame.new(0, h / 2, 0),
		Material = look.material,
		Color = look.color,
	})
	trim(folder, {
		Name = "WallPlinth",
		Size = Vector3.new(t + 0.8, 1.6, length + t + 0.8),
		CFrame = frame * CFrame.new(0, 0.8, 0),
		Material = look.material,
		Color = look.color:Lerp(Color3.new(0, 0, 0), 0.25),
	})
	trim(folder, {
		Name = "WallCap",
		Size = Vector3.new(t + 0.5, 0.6, length + t + 0.5),
		CFrame = frame * CFrame.new(0, h + 0.3, 0),
		Material = if style.pale then Enum.Material.Foil else look.material,
		Color = if style.pale then GOLD else look.color:Lerp(Color3.new(1, 1, 1), 0.12),
	})
	local merlons = math.max(1, math.floor(length / 4))
	for i = 0, merlons do
		part(folder, {
			Name = "Merlon",
			Size = Vector3.new(t + 0.3, 1.8, 2),
			CFrame = frame * CFrame.new(0, h + 0.6 + 0.9, -length / 2 + i * length / merlons),
			Material = look.material,
			Color = look.color,
			CanQuery = false,
		})
	end
end

-- A stepped cone roof (stacked discs) on top of a round tower.
local function coneRoof(
	folder: Instance,
	base: CFrame,
	diameter: number,
	height: number,
	color: Color3,
	pale: boolean
)
	local steps = 10 -- fine steps read as a smooth cone from a distance
	for i = 0, steps - 1 do
		local d = diameter * (1 - i / steps) + 0.4
		column(folder, base * CFrame.new(0, i * height / steps, 0), d, height / steps + 0.05, {
			Name = "Roof",
			Material = Enum.Material.Slate,
			Color = color,
			CanCollide = false,
			CanQuery = false,
		})
	end
	if pale then
		column(folder, base * CFrame.new(0, height, 0), 0.5, 1.2, {
			Name = "RoofCap",
			Material = Enum.Material.Foil,
			Color = GOLD,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

local function flag(folder: Instance, top: CFrame, color: Color3)
	trim(folder, {
		Name = "FlagPole",
		Size = Vector3.new(0.25, 5, 0.25),
		CFrame = top * CFrame.new(0, 2.5, 0),
		Material = Enum.Material.Metal,
		Color = IRON,
	})
	trim(folder, {
		Name = "Flag",
		Size = Vector3.new(0.1, 1.7, 2.8),
		CFrame = top * CFrame.new(0, 4, 1.45),
		Material = Enum.Material.Fabric,
		Color = color,
	})
end

-- A tower standing at `base` (plot-local frame on the ground, -Z facing outward).
-- Returns where its tip is, for a theme kit's lightning and floating pieces.
local function tower(
	folder: Instance,
	base: CFrame,
	style: Style,
	look: Look,
	models: boolean,
	kit: CastleKits.Kit?,
	front: boolean
): CastleKits.TowerSpot
	local r, h = style.towerRadius, style.towerHeight
	local spot: CastleKits.TowerSpot =
		{ base = base, radius = r, height = h, tip = base * CFrame.new(0, h + 3, 0) }
	if models and style.towerProp and Props.template("WorldProps", style.towerProp) then
		local roof = if style.tower == "roofed" or style.tower == "spire" then r * 2.4 else 0
		local model = Props.spawn(style.towerProp, base, h + roof, folder)
		if model then
			-- The model has no collision: an invisible column keeps it solid
			column(folder, base, r * 1.8, h, {
				Name = "TowerCollider",
				Transparency = 1,
				CanQuery = false,
			})
			spot.tip = base * CFrame.new(0, h + roof, 0)
			return spot
		end
	end
	if style.tower == "wood" then
		-- Four log legs, a plank lookout platform with a rail, a stepped roof
		local leg = r * 0.75
		for _, corner in
			{
				Vector3.new(-leg, 0, -leg),
				Vector3.new(leg, 0, -leg),
				Vector3.new(-leg, 0, leg),
				Vector3.new(leg, 0, leg),
			}
		do
			column(folder, base * CFrame.new(corner), 0.9, h + 3, {
				Name = "TowerLeg",
				Material = Enum.Material.Wood,
				Color = WOOD_DARK,
			})
		end
		for _, y in { h * 0.35, h * 0.62 } do
			for _, offset in { Vector3.new(0, y, -leg), Vector3.new(0, y, leg) } do
				trim(folder, {
					Name = "TowerBrace",
					Size = Vector3.new(leg * 2, 0.4, 0.4),
					CFrame = base * CFrame.new(offset),
					Material = Enum.Material.Wood,
					Color = WOOD,
				})
			end
		end
		part(folder, {
			Name = "TowerPlatform",
			Size = Vector3.new(r * 2 + 1, 0.6, r * 2 + 1),
			CFrame = base * CFrame.new(0, h, 0),
			Material = Enum.Material.WoodPlanks,
			Color = WOOD,
		})
		for _, side in { -1, 1 } do
			trim(folder, {
				Name = "TowerRail",
				Size = Vector3.new(r * 2 + 1, 0.4, 0.3),
				CFrame = base * CFrame.new(0, h + 1.4, side * (r + 0.4)),
				Material = Enum.Material.Wood,
				Color = WOOD_DARK,
			})
			trim(folder, {
				Name = "TowerRail",
				Size = Vector3.new(0.3, 0.4, r * 2 + 1),
				CFrame = base * CFrame.new(side * (r + 0.4), h + 1.4, 0),
				Material = Enum.Material.Wood,
				Color = WOOD_DARK,
			})
		end
		for i = 0, 2 do
			local size = (r * 2 + 2.2) * (1 - i * 0.3)
			trim(folder, {
				Name = "Roof",
				Size = Vector3.new(size, 0.9, size),
				CFrame = base * CFrame.new(0, h + 3.3 + i * 0.9, 0),
				Material = Enum.Material.WoodPlanks,
				Color = look.roof,
			})
		end
		trim(folder, {
			Name = "TowerBanner",
			Size = Vector3.new(1.8, 3.2, 0.1),
			CFrame = base * CFrame.new(0, h - 1.8, -(r + 0.7)),
			Material = Enum.Material.Fabric,
			Color = look.flag,
		})
		spot.tip = base * CFrame.new(0, h + 6, 0)
		return spot
	end
	-- Stone towers: a round body, a wider crown with battlements, window slits
	local pale = style.pale
	local color = look.color
	column(folder, base, r * 2, h, {
		Name = "Tower",
		Material = look.material,
		Color = color,
	})
	column(folder, base * CFrame.new(0, h - 0.4, 0), r * 2 + 1.4, 2, {
		Name = "TowerCrown",
		Material = look.material,
		Color = color:Lerp(Color3.new(1, 1, 1), 0.1),
		CanQuery = false,
	})
	for i = 0, 7 do
		local angle = i / 8 * 2 * math.pi
		trim(folder, {
			Name = "Merlon",
			Size = Vector3.new(1.5, 1.7, 1.5),
			CFrame = base * CFrame.new(math.cos(angle) * (r + 0.2), h + 2.4, math.sin(angle) * (r + 0.2)),
			Material = look.material,
			Color = color,
		})
	end
	for _, y in { h * 0.45, h * 0.75 } do
		trim(folder, {
			Name = "WindowSlit",
			Size = Vector3.new(0.7, 2.2, 0.4),
			CFrame = base * CFrame.new(0, y, -r + 0.05),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(25, 22, 30),
		})
	end
	if pale or kit then
		-- Banners hanging on the tower's outer faces (every theme concept has
		-- them), with the kit's emblem (a gold diamond on the Citadel)
		for _, angle in { -50, 50 } do
			local face = base * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, h * 0.56, -(r + 0.1))
			CastleKits.banner(folder, kit, face, r * 0.78, h * 0.3, look.flag)
		end
	end
	if pale then
		for _, y in { h * 0.33, h * 0.66, h - 0.6 } do
			column(folder, base * CFrame.new(0, y, 0), r * 2 + 0.3, 0.5, {
				Name = "GoldBand",
				Material = Enum.Material.Foil,
				Color = GOLD,
				CanCollide = false,
				CanQuery = false,
			})
		end
	end
	local roofBase = base * CFrame.new(0, h + 1.6, 0)
	-- A theme kit's cap replaces the roof (from the Keep up, so the plain stone
	-- towers get one too)
	local capTip = if kit then CastleKits.cap(folder, kit, roofBase, r, front) else nil
	if capTip then
		spot.tip = capTip
		return spot
	end
	if style.tower == "stone" then
		spot.tip = base * CFrame.new(0, h + 2.4, 0)
		return spot
	end
	local roofHeight = r * (if pale then 3 else 2.2)
	coneRoof(folder, roofBase, r * 2 + 1.6, roofHeight, look.roof, pale)
	if kit then
		CastleKits.roof(folder, kit, roofBase, r + 0.8, roofHeight)
	end
	local top = roofBase * CFrame.new(0, roofHeight, 0)
	spot.tip = top
	if kit and kit.finial then
		CastleKits.finial(folder, kit, top, r)
	elseif pale then
		-- A glowing crystal on the very tip
		local crystal = trim(folder, {
			Name = "SpireCrystal",
			Size = Vector3.new(1.3, 1.3, 1.3),
			CFrame = top * CFrame.new(0, 2, 0) * CFrame.Angles(math.rad(45), math.rad(35), math.rad(45)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(120, 235, 255),
		})
		local light = Instance.new("PointLight")
		light.Color = crystal.Color
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = crystal
	else
		flag(folder, top, look.flag)
	end
	return spot
end

-- The way in at the front: a timber arch (Camp, Stockade; WorldService's PlotArch),
-- a stone gatehouse from the Keep up.
local function gatehouse(
	folder: Instance,
	origin: CFrame,
	layout: Layout,
	style: Style,
	look: Look,
	models: boolean,
	kit: CastleKits.Kit?
): number?
	local z = layout.front
	local h = GATE_CLEAR + 3.5
	local width = GATE_HALF * 2 + 9
	local base = origin * CFrame.new(0, 0, z)
	local template = if models and style.gateProp then Props.template("WorldProps", style.gateProp) else nil
	if template and style.gateProp then
		-- Fitted by width: the model's arch is the way in (a 9-stud opening between
		-- invisible colliders that run out to the wall ends). The Citadel's gate is
		-- the wide one, with a tower at each end.
		local gateWidth = style.gateWidth or 26
		local model = template:Clone()
		model.Name = style.gateProp
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.Massless = true
			end
		end
		-- Whichever way the model was imported, its long side spans the wall (an
		-- arch that faced sideways along the wall was the PC's round-473db78 find)
		local extents = model:GetExtentsSize()
		local turned = extents.Z > extents.X
		local frame = if turned then base * CFrame.Angles(0, math.pi / 2, 0) else base
		local size = if turned
			then Vector3.new(gateWidth * 0.5, gateWidth * 0.8, gateWidth)
			else Vector3.new(gateWidth, gateWidth * 0.8, gateWidth * 0.5)
		Props.place(model, frame * CFrame.new(0, size.Y / 2, 0), size)
		model.Parent = folder
		local opening = 4.5
		local reach = style.gateJoin or GATE_HALF + 4.5
		for _, side in { -1, 1 } do
			part(folder, {
				Name = "GateCollider",
				Size = Vector3.new(reach - opening, h, layout.thickness + 2),
				CFrame = base * CFrame.new(side * (opening + reach) / 2, h / 2, 0),
				Transparency = 1,
				CanQuery = false,
			})
		end
		return nil
	end
	-- Two towers flank the way in and rise well above the walls, with an
	-- overhanging crown, merlons and arrow slits; arch corners soften the
	-- opening (the theme concepts' gatehouse). Same footprint as the walls'
	-- torches and colliders expect: 4.5 wide, the wall's depth plus 2.
	local depth = layout.thickness + 2
	local top = layout.height + 6
	local dark = look.color:Lerp(Color3.new(0, 0, 0), 0.08)
	local light = look.color:Lerp(Color3.new(1, 1, 1), 0.12)
	for _, side in { -1, 1 } do
		local x = side * (GATE_HALF + 2.25)
		part(folder, {
			Name = "GatePillar",
			Size = Vector3.new(4.5, top - 2.4, depth),
			CFrame = base * CFrame.new(x, (top - 2.4) / 2, 0),
			Material = look.material,
			Color = dark,
		})
		part(folder, {
			Name = "GateCrown",
			Size = Vector3.new(5.6, 2.4, depth + 1),
			CFrame = base * CFrame.new(x, top - 1.2, 0),
			Material = look.material,
			Color = look.color,
		})
		trim(folder, {
			Name = "GateTrim",
			Size = Vector3.new(5.9, 0.5, depth + 1.3),
			CFrame = base * CFrame.new(x, top - 2.4, 0),
			Material = if style.pale then Enum.Material.Foil else look.material,
			Color = if style.pale then GOLD else light,
		})
		for _, mx in { -1, 0, 1 } do
			for _, mz in { -1, 1 } do
				trim(folder, {
					Name = "Merlon",
					Size = Vector3.new(1.4, 1.8, 1.4),
					CFrame = base * CFrame.new(x + mx * 2.1, top + 0.9, mz * (depth / 2 - 0.2)),
					Material = look.material,
					Color = look.color,
				})
			end
		end
		for _, y in { (top - 2.4) * 0.42, (top - 2.4) * 0.72 } do
			trim(folder, {
				Name = "WindowSlit",
				Size = Vector3.new(0.7, 2.2, 0.4),
				CFrame = base * CFrame.new(x, y, -(depth / 2) + 0.15),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(25, 22, 30),
			})
		end
		-- An arch corner where the opening meets the lintel
		trim(folder, {
			Name = "GateArch",
			Size = Vector3.new(2.6, 2.6, depth - 0.4),
			CFrame = base * CFrame.new(side * GATE_HALF, GATE_CLEAR, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Material = look.material,
			Color = look.color,
		})
	end
	trim(folder, {
		Name = "GateLintel",
		Size = Vector3.new(width - 9, h - GATE_CLEAR, depth - 0.4),
		CFrame = base * CFrame.new(0, (GATE_CLEAR + h) / 2, 0),
		Material = look.material,
		Color = look.color,
	})
	trim(folder, {
		Name = "GateTrim",
		Size = Vector3.new(width - 8.8, 0.6, depth - 0.2),
		CFrame = base * CFrame.new(0, h + 0.3, 0),
		Material = if style.pale then Enum.Material.Foil else look.material,
		Color = if style.pale then GOLD else light,
	})
	for i = -1, 1 do
		trim(folder, {
			Name = "Merlon",
			Size = Vector3.new(1.6, 1.8, 1.4),
			CFrame = base * CFrame.new(i * 4.2, h + 1.5, -(depth / 2 - 0.5)),
			Material = look.material,
			Color = look.color,
		})
	end
	-- The raised portcullis on the gate's outer face: iron teeth under the
	-- lintel. A theme kit's glows in its light (the concepts' shining gates),
	-- still raised so the way in reads as open
	local teeth = if kit then 4 else 2.2
	local faceZ = -(depth / 2) + 0.4
	for i = -3, 3 do
		trim(folder, {
			Name = "Portcullis",
			Size = Vector3.new(0.35, teeth, 0.35),
			CFrame = base * CFrame.new(i * 1.9, GATE_CLEAR + 0.5 - teeth / 2, faceZ),
			Material = if kit then Enum.Material.Neon else Enum.Material.Metal,
			Color = if kit then kit.light else IRON,
		})
	end
	if kit then
		local bar = trim(folder, {
			Name = "Portcullis",
			Size = Vector3.new(GATE_HALF * 2 - 0.4, 0.35, 0.35),
			CFrame = base * CFrame.new(0, GATE_CLEAR + 0.5 - teeth * 0.7, faceZ),
			Material = Enum.Material.Neon,
			Color = kit.light,
		})
		local glow = Instance.new("PointLight")
		glow.Color = kit.light
		glow.Range = 16
		glow.Brightness = 1.6
		glow.Parent = bar
		-- A kit light, so the kit's lightScale dims it too (it glared on the Diamond gate)
		CollectionService:AddTag(glow, "KitLight")
	end
	return top
end

local function brazier(folder: Instance, base: CFrame)
	local model = if Props.template("WorldProps", "Brazier")
		then Props.spawn("Brazier", base, 4.5, folder)
		else nil
	local bowl: BasePart?
	if model then
		bowl = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	else
		column(folder, base, 0.7, 3.4, {
			Name = "BrazierStand",
			Material = Enum.Material.Metal,
			Color = IRON,
			CanCollide = false,
		})
		bowl = column(folder, base * CFrame.new(0, 3.4, 0), 2.6, 0.9, {
			Name = "BrazierBowl",
			Material = Enum.Material.Metal,
			Color = IRON,
			CanCollide = false,
		})
	end
	if bowl then
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 7
		fire.Color = Color3.fromRGB(255, 140, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Parent = bowl
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 80)
		light.Range = 16
		light.Brightness = 1.4
		light.Parent = bowl
	end
end

-- Builds the fortress for a plot into a new Folder "Fortress" under `parent`
-- (replacing the old one) and returns where its walls are.
function Fortress.build(
	parent: Instance,
	origin: CFrame,
	level: number,
	width: number,
	depth: number,
	plotFront: number,
	theme: Config.BaseTheme
): Layout
	local existing = parent:FindFirstChild("Fortress")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Fortress"
	local style = Fortress.style(level)
	local layout = Fortress.layout(level, width, depth, plotFront)
	local wall = theme.wall
	local look: Look = {
		material = if wall
			then wall.material
			elseif style.pale then Enum.Material.Limestone
			else Enum.Material.Cobblestone,
		color = if wall then wall.color elseif style.pale then PALE else STONE,
		roof = theme.roofColor or theme.trimColor:Lerp(Color3.new(0, 0, 0), 0.15),
		flag = theme.bannerColor or theme.laserColor,
	}
	-- Imported tower and gatehouse models carry the Classic look (gray or pale
	-- stone, blue roofs and banners) in their textures, so a custom design builds
	-- them from parts in its own colors instead
	local models = not theme.customTowers
	local kit = CastleKits.get(theme.kit)

	local x, f, b, g = layout.halfW, layout.front, layout.back, layout.gateHalf
	-- The front walls stop at the gatehouse: inside an imported model's end towers,
	-- or tucked into the part-built one's pillars
	local gateModel = style.gatehouse
		and models
		and style.gateProp ~= nil
		and Props.template("WorldProps", style.gateProp) ~= nil
	local join = if gateModel then style.gateJoin or g + 4.5 elseif style.gatehouse then g + 4.5 else g
	if gateModel then
		layout.gateOuter = (style.gateWidth or 26) / 2
	end
	local runs = {
		{ Vector3.new(-x, 0, b), Vector3.new(x, 0, b) },
		{ Vector3.new(-x, 0, f), Vector3.new(-x, 0, b) },
		{ Vector3.new(x, 0, f), Vector3.new(x, 0, b) },
		{ Vector3.new(-x, 0, f), Vector3.new(-join, 0, f) },
		{ Vector3.new(join, 0, f), Vector3.new(x, 0, f) },
	}
	for _, run in runs do
		wallRun(folder, origin, run[1], run[2], style, look)
	end

	local towers: { CastleKits.TowerSpot } = {}
	if style.towers ~= "none" then
		-- Corner towers, nudged outward so they clear the ramps inside
		local corners = { Vector3.new(-x - 1, 0, b + 1), Vector3.new(x + 1, 0, b + 1) }
		if style.towers == "all" then
			table.insert(corners, Vector3.new(-x - 1, 0, f - 1))
			table.insert(corners, Vector3.new(x + 1, 0, f - 1))
		end
		for _, corner in corners do
			-- Face outward, away from the plot's middle
			local outward = Vector3.new(corner.X, 0, corner.Z - (f + b) / 2)
			local base = origin * CFrame.lookAt(corner, corner + outward)
			table.insert(towers, tower(folder, base, style, look, models, kit, corner.Z < (f + b) / 2))
		end
	end
	local gateTop: number? = nil
	if style.gatehouse then
		gateTop = gatehouse(folder, origin, layout, style, look, models, kit)
	end
	if style.braziers and kit == nil then -- a kit brings its own (CastleKits.dress)
		for _, side in { -1, 1 } do
			brazier(folder, origin * CFrame.new(side * (g + 8), 0, f - 8.5)) -- clear of a moat (BaseDecor)
		end
	end
	-- The kit's dressing goes on first, so its banners take the design's banner
	-- material and rainbow like the towers' own
	if kit then
		local plotRuns: { { a: Vector3, b: Vector3 } } = {}
		for _, run in runs do
			table.insert(plotRuns, { a = run[1], b = run[2] })
		end
		CastleKits.dress(folder, kit, {
			origin = origin,
			halfW = x,
			front = f,
			back = b,
			gateHalf = g,
			height = layout.height,
			thickness = layout.thickness,
			stone = style.wall == "stone",
			level = level,
			gateTop = gateTop,
			gateDepth = layout.thickness + 2,
			banner = look.flag,
			towers = towers,
			runs = plotRuns,
		})
	end
	-- The designer's finishing touches: gold roofs or banners, banner-colored bands,
	-- the glow color on the spire crystals, and rainbow parts for the client to cycle (RainbowController)
	if kit then
		CastleKits.scaleLights(folder, kit)
	end
	local rainbow = theme.rainbow
	local shine = wall and wall.reflectance
	-- A stone with a custom material (Config.Materials, when it's made): every wall,
	-- tower and gatehouse piece of it, the texture carrying the color
	local variant = wall and wall.variant
	local painted = variant ~= nil and MaterialService:FindFirstChild(variant) ~= nil
	local value = if painted then Config.Materials[variant :: string].brightness else 1
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Tower" and theme.sparkle then
			twinkle(descendant, theme.sparkle)
		end
		if shine and wall and descendant:IsA("BasePart") and descendant.Material == wall.material then
			-- A shining stone: every wall, tower and gatehouse piece of it
			descendant.Reflectance = math.max(descendant.Reflectance, shine)
		end
		if painted and wall and descendant:IsA("BasePart") and descendant.Material == wall.material then
			descendant.MaterialVariant = variant :: string
			descendant.Color = Color3.new(value, value, value)
			-- and a faint pastel sheen rolling over it (RainbowController)
			CollectionService:AddTag(descendant, "Iridescent")
		end
		if kit and descendant:IsA("BasePart") and descendant.Name == "WindowSlit" then
			-- A themed castle's windows glow in its light
			descendant.Material = Enum.Material.Neon
			descendant.Color = kit.light
		end
		if descendant:IsA("BasePart") then
			local kind = if descendant.Name == "Roof"
				then "roof"
				elseif descendant.Name == "Flag" or descendant.Name == "TowerBanner" then "banner"
				elseif descendant.Name == "SpireCrystal" then "glow"
				elseif
					GILDED[descendant.Name]
					and descendant.Material == Enum.Material.Foil
					and theme.customTowers
				then "band"
				else nil
			if kind == "band" then
				-- The Citadel's gold trim takes the banner color (still metallic)
				descendant.Color = look.flag
				kind = "banner"
			elseif kind == "roof" and theme.roofMaterial then
				descendant.Material = theme.roofMaterial
			elseif kind == "banner" and theme.bannerMaterial then
				descendant.Material = theme.bannerMaterial
			elseif kind == "glow" then
				descendant.Color = theme.laserColor
				local light = descendant:FindFirstChildOfClass("PointLight")
				if light then
					light.Color = theme.laserColor
				end
			end
			if kind and rainbow and (rainbow :: any)[kind] then
				CollectionService:AddTag(descendant, "Rainbow")
			end
		end
	end
	folder.Parent = parent
	return layout
end

return Fortress

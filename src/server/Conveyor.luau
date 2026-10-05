--!strict
-- The egg conveyor loop round the hatchery, built from parts (owner, 2026-10-05:
-- "The conveyor belt could be detailed up a bit more too, its pretty crude"). A
-- steel bed with side skirts and yellow edge lines, a rubber belt, roller caps,
-- low guard rails, amber running lights along the outside, and cross-slats that
-- ride round with the eggs so the belt reads as moving. BeltController animates
-- the slats and the lights on each client; the eggs follow Shared/Belt.luau.
--
-- Built in rings of SEGMENTS pieces round `center` (the hub's ground center). The
-- belt's top is Belt.BELT_TOP above the ground; eggs ride at Belt's height.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Belt = require(ReplicatedStorage.Shared.Belt)

local Conveyor = {}

local SEGMENTS = 56
local SLATS = 96
local STEEL = Color3.fromRGB(52, 56, 64)
local SKIRT = Color3.fromRGB(78, 84, 96)
local BRIGHT_STEEL = Color3.fromRGB(150, 156, 168)
local RUBBER = Color3.fromRGB(36, 36, 40)
local EDGE = Color3.fromRGB(240, 190, 40)
local LIGHT_OFF = Color3.fromRGB(110, 60, 20)

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

local function decor(parent: Instance, props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return part(parent, props)
end

-- `center`: the loop's center on the ground; `radius`: the belt's center line.
function Conveyor.build(parent: Instance, center: Vector3, radius: number)
	local model = Instance.new("Model")
	model.Name = "Conveyor"
	local top = Belt.BELT_TOP
	local segmentAngle = 2 * math.pi / SEGMENTS
	-- Each ring's pieces are as long as the chord at their own radius, so the outer
	-- ones close up too
	local function chord(at: number): number
		return 2 * at * math.sin(segmentAngle / 2) + 0.15
	end
	local segLength = chord(radius + 2.5)
	local lights = Instance.new("Folder")
	lights.Name = "BeltLights"
	local lightIndex = 0

	for i = 0, SEGMENTS - 1 do
		local angle = i * segmentAngle
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = center + radial * radius * math.cos(segmentAngle / 2)
		-- X across the belt (outward), Z along it
		local frame = CFrame.fromMatrix(at, radial, Vector3.yAxis)
		part(model, {
			Name = "BeltBed",
			Size = Vector3.new(6.2, top - 0.6, chord(radius + 3.1)),
			CFrame = frame * CFrame.new(0, (top - 0.6) / 2, 0),
			Material = Enum.Material.Metal,
			Color = STEEL,
		})
		part(model, {
			Name = "Belt",
			Size = Vector3.new(5, 0.6, segLength + 0.05),
			CFrame = frame * CFrame.new(0, top - 0.3, 0),
			Material = Enum.Material.Rubber,
			Color = RUBBER,
		})
		for _, side in { -1, 1 } do
			local sideLength = chord(radius + side * 3.25)
			part(model, {
				Name = "BeltSkirt",
				Size = Vector3.new(0.5, top + 0.2, sideLength),
				CFrame = frame * CFrame.new(side * 2.85, (top + 0.2) / 2, 0),
				Material = Enum.Material.Metal,
				Color = SKIRT,
			})
			decor(model, {
				Name = "BeltEdge",
				Size = Vector3.new(0.55, 0.12, sideLength),
				CFrame = frame * CFrame.new(side * 2.85, top + 0.26, 0),
				Material = Enum.Material.SmoothPlastic,
				Color = EDGE,
			})
			if i % 2 == 0 then
				-- Roller ends showing through the skirts
				decor(model, {
					Name = "BeltRoller",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.3, 0.9, 0.9),
					CFrame = frame * CFrame.new(side * 3.15, top - 0.5, 0),
					Material = Enum.Material.Metal,
					Color = BRIGHT_STEEL,
				})
			end
			if i % 4 == 0 then
				decor(model, {
					Name = "BeltRailPost",
					Size = Vector3.new(0.3, 1.5, 0.3),
					CFrame = frame * CFrame.new(side * 3.25, top + 0.95, 0),
					Material = Enum.Material.Metal,
					Color = BRIGHT_STEEL,
				})
			end
			-- The guard rail (players walk through it: crossing the belt stays easy)
			decor(model, {
				Name = "BeltRail",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(sideLength, 0.28, 0.28),
				CFrame = frame * CFrame.new(side * 3.25, top + 1.7, 0) * CFrame.Angles(0, math.pi / 2, 0),
				Material = Enum.Material.Metal,
				Color = BRIGHT_STEEL,
			})
		end
		if i % 2 == 1 then
			-- Running lights along the outside, numbered the way the belt runs
			lightIndex += 1
			local light = decor(lights, {
				Name = "BeltLight",
				Size = Vector3.new(0.2, 0.35, 0.7),
				CFrame = frame * CFrame.new(3.12, top - 0.5, 0),
				Material = Enum.Material.Neon,
				Color = LIGHT_OFF,
			})
			light:SetAttribute("Index", lightIndex)
		end
	end
	lights:SetAttribute("Count", lightIndex)
	lights.Parent = model

	-- Cross-slats riding round with the eggs (placed at rest; the client moves them)
	local slats = Instance.new("Folder")
	slats.Name = "BeltSlats"
	slats:SetAttribute("Center", center)
	slats:SetAttribute("Count", SLATS)
	for i = 1, SLATS do
		local slat = decor(slats, {
			Name = "BeltSlat",
			Size = Vector3.new(4.6, 0.12, 0.4),
			CFrame = Belt.slatCFrame(center, (i - 1) / SLATS * 2 * math.pi),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(84, 88, 98),
		})
		slat:SetAttribute("Index", i)
	end
	slats.Parent = model
	model.Parent = parent
end

return Conveyor

-- A rough stand-in for the plot itself (floor, creature spots with their niches,
-- the keep's floors, ramps and vault rooms), so the fortress and design previews
-- show it in context. The runners prepend WorldService's own layout constants
-- (keep_constants.sh: PLOT_WIDTHS, FLOOR_X, GROUND_COLUMNS, FLOOR_SIDE_Z, ...), and
-- this builds the same pieces buildPlot does, named the same so CastleKits.dressKeep
-- dresses them alike. Keep the geometry in step with buildPlot when it changes.

-- Creatures shown on the pedestals (their GLBs from CREATURE_DIR) and their
-- rarity colors, which light their niches as in game (setNicheGlow)
local SHOWN = {
	{ "Emberlynx", Color3.fromRGB(170, 80, 255) }, { "Tidalotl", Color3.fromRGB(255, 170, 30) },
	{ "Hivebadger", Color3.fromRGB(70, 140, 255) }, { "Glacierion", Color3.fromRGB(255, 60, 90) },
	{ "Pyrodrake", Color3.fromRGB(255, 170, 30) }, { "Mossmunk", Color3.fromRGB(90, 200, 90) },
	{ "Stormgriff", Color3.fromRGB(170, 80, 255) }, { "Quasarfox", Color3.fromRGB(150, 235, 255) },
	{ "Geodeer", Color3.fromRGB(70, 140, 255) }, { "Capybaron", Color3.fromRGB(255, 60, 90) },
	{ "Frostbun", Color3.fromRGB(90, 200, 90) }, { "Solarion", Color3.fromRGB(140, 70, 255) },
	{ "Coralope", Color3.fromRGB(170, 80, 255) }, { "Thunderhoof", Color3.fromRGB(255, 170, 30) },
	{ "Kelpotter", Color3.fromRGB(70, 140, 255) }, { "Nebulion", Color3.fromRGB(255, 60, 90) },
	{ "Sylvanox", Color3.fromRGB(255, 170, 30) }, { "Calderhorn", Color3.fromRGB(170, 80, 255) },
}
local GROUND_SPOTS = { 10, 15, 20, 20, 20 } -- Config.Economy baseLevels' pedestals

-- buildPlot's slot order on the ground: rows front to back, the third row's inner
-- pair before its outer pair
local GROUND_ORDER = {}
for row = 1, #GROUND_ROWS do
	local columns = if row == 3 then { 2, 3, 1, 4 } else { 1, 2, 3, 4 }
	for _, column in columns do
		table.insert(GROUND_ORDER, { row, column })
	end
end

local function floorTop(floor)
	return TOP + (floor - 1) * FLOOR_HEIGHT
end

-- Builds the plot for a base level under `parent`; returns its width, depth and
-- where the ground floor's hall ends (CastleKits.dressHall's centerpiece goes there).
function plotContext(parent, level)
	local W, D = PLOT_WIDTHS[level], PLOT_DEPTHS[level]
	local function p(props)
		local x = Instance.new("Part")
		x.Anchored = true
		for k, v in props do
			x[k] = v
		end
		x.Parent = parent
		return x
	end
	p({
		Name = "Floor",
		Size = Vector3.new(W, 1, D),
		CFrame = CFrame.new(0, 0.5, PLOT_FRONT + D / 2),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 120, 85),
	})
	local stoneMat = if level >= 5 then Enum.Material.Limestone else Enum.Material.Cobblestone
	local stone = if level >= 5 then Color3.fromRGB(236, 226, 206) else Color3.fromRGB(140, 134, 126)
	local light = if level >= 5 then Color3.fromRGB(245, 238, 222) else Color3.fromRGB(156, 150, 142)
	-- Walls take the design's stone (Glass attribute), trim its lighter stone (Keep)
	local function wall(size, cf, name)
		local w = p({ Name = name or "FloorWall", Size = size, CFrame = cf, Material = stoneMat, Color = stone })
		w:SetAttribute("Glass", true)
		return w
	end
	local function trim(size, cf, name)
		local t = p({ Name = name or "Trim", Size = size, CFrame = cf, Material = stoneMat, Color = light })
		t:SetAttribute("Keep", true)
		return t
	end
	local function wallX(x0, x1, z, top)
		wall(Vector3.new(math.abs(x1 - x0), FLOOR_WALL, 0.4), CFrame.new((x0 + x1) / 2, top + FLOOR_WALL / 2, z))
	end
	local function wallZ(z0, z1, x, top, name)
		wall(
			Vector3.new(0.4, FLOOR_WALL, math.abs(z1 - z0)),
			CFrame.new(x, top + FLOOR_WALL / 2, (z0 + z1) / 2),
			name
		)
	end

	-- A creature spot: its pedestal, its niche behind it (turned by `yaw`, as
	-- buildPlot's pedestalSpot), lit in a rarity color, and a creature on it
	local shown = 0
	local function spot(x, floorY, z, yaw)
		shown += 1
		p({
			Name = "Pedestal",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 6, 6),
			CFrame = CFrame.new(x, floorY + 0.7, z) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(120, 120, 130),
		})
		local face = CFrame.new(x, floorY, z) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, NICHE_BACK)
		local roundFace = CFrame.Angles(0, math.pi / 2, 0)
		local back = p({
			Name = "NicheBack",
			Size = Vector3.new(NICHE_WIDTH, NICHE_HEIGHT, 0.8),
			CFrame = face * CFrame.new(0, NICHE_HEIGHT / 2, 0.4),
			Material = stoneMat,
			Color = stone,
		})
		back:SetAttribute("Keep", true)
		back:SetAttribute("Slot", shown)
		trim(Vector3.new(0.8, NICHE_WIDTH, NICHE_WIDTH), face * CFrame.new(0, NICHE_HEIGHT, 0.4) * roundFace, "NicheArch").Shape =
			Enum.PartType.Cylinder
		for _, side in { -1, 1 } do
			trim(
				Vector3.new(0.7, NICHE_HEIGHT + 0.6, 1.3),
				face * CFrame.new(side * (NICHE_WIDTH / 2 + 0.1), (NICHE_HEIGHT + 0.6) / 2, 0.25),
				"NichePilaster"
			)
		end
		local pick = SHOWN[(shown - 1) % #SHOWN + 1]
		local inner = NICHE_WIDTH - 1.6
		local panel = p({
			Name = "NicheGlow",
			Size = Vector3.new(inner, NICHE_HEIGHT - 1.4, 0.12),
			CFrame = face * CFrame.new(0, 0.7 + NICHE_HEIGHT / 2, -0.06),
			Material = Enum.Material.Neon,
			Color = pick[2],
		})
		p({
			Name = "NicheGlow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, inner, inner),
			CFrame = face * CFrame.new(0, NICHE_HEIGHT, -0.06) * roundFace,
			Material = Enum.Material.Neon,
			Color = pick[2],
		})
		local l = Instance.new("PointLight")
		l.Range = 9
		l.Brightness = 1.6
		l.Color = pick[2]
		l.Parent = panel
		-- The creature (adults: longest side 7, as CreatureService scales them),
		-- facing away from its niche
		local ext = AVAILABLE_PROPS and AVAILABLE_PROPS[pick[1]]
		if ext and type(ext) == "table" then
			local height = ext.Y * 7 / math.max(ext.X, ext.Y, ext.Z)
			PreviewProps.spawn(pick[1], CFrame.new(x, floorY + 1.4, z) * CFrame.Angles(0, yaw, 0), height, parent)
		end
	end

	-- The ground: two wings of two columns either side of an open hall
	for i = 1, GROUND_SPOTS[level] do
		local cell = GROUND_ORDER[i]
		spot(GROUND_COLUMNS[cell[2]], TOP, GROUND_ROWS[cell[1]], 0)
	end

	-- A floor's arched front (WorldService's arcade: bays about 10.5 wide)
	local function arcade(z, top)
		local x0, x1 = -FLOOR_X, FLOOR_X
		local bays = math.max(1, math.floor((x1 - x0) / 10.5 + 0.5))
		local bay = (x1 - x0) / bays
		for i = 0, bays do
			trim(Vector3.new(1.8, FLOOR_WALL, 1.8), CFrame.new(x0 + i * bay, top + FLOOR_WALL / 2, z), "ArchPillar")
		end
		for i = 0, bays - 1 do
			local x = x0 + (i + 0.5) * bay
			local span = bay - 1.8
			trim(Vector3.new(span, 1.8, 1.4), CFrame.new(x, top + FLOOR_WALL - 0.9, z), "ArchLintel")
			for _, side in { -1, 1 } do
				trim(
					Vector3.new(2.4, 2.4, 1.2),
					CFrame.new(x + side * (span / 2 - 0.5), top + FLOOR_WALL - 1.8, z) * CFrame.Angles(0, 0, math.rad(45)),
					"ArchCorner"
				)
			end
			trim(Vector3.new(span, 2.6, 0.9), CFrame.new(x, top + 1.3, z), "Balustrade")
		end
		trim(Vector3.new(x1 - x0 + 2, 0.8, 2.2), CFrame.new(0, top + FLOOR_WALL + 0.4, z), "ArchCap")
		trim(Vector3.new(x1 - x0 + 1, 1.6, 0.8), CFrame.new(0, top - 1.1, z - 0.2), "FloorFascia")
	end
	local function merlons(a, b, top)
		local count = math.max(1, math.floor((b - a).Magnitude / 4))
		for i = 0, count do
			local at = a:Lerp(b, i / count)
			trim(Vector3.new(1.8, 1.8, 1.8), CFrame.new(at.X, top + FLOOR_WALL + 0.9, at.Z), "Merlon")
		end
	end
	-- A ramp between two points on its surface, drawn as stairs with a stone
	-- balustrade both sides (WorldService: the security walls behind it are
	-- invisible, and the inner side's bottom quarter is open)
	local function ramp(a, b)
		local length = (b - a).Magnitude
		p({
			Name = "Ramp",
			Size = Vector3.new(6, 1, length),
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(130, 105, 75),
		})
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local along = flat.Unit
		local right = along:Cross(Vector3.new(0, 1, 0))
		local steps = math.max(4, math.floor(flat.Magnitude / 1.5))
		local run, rise = flat.Magnitude / steps, (b.Y - a.Y) / steps
		for step = 0, steps - 1 do
			local height = math.abs(rise) + 0.6
			local top = a.Y + (step + 0.5) * rise + 0.25
			local at = Vector3.new(a.X, top - height / 2, a.Z) + along * (step + 0.5) * run
			trim(Vector3.new(5.6, height, run + 0.02), CFrame.lookAt(at, at + along), "Stair")
		end
		for _, side in { -1, 1 } do
			local offset = right * side * 3.2
			local start = if side == 1 then 0.25 else 0
			local railA, railB = a:Lerp(b, start) + offset, b + offset
			local railLength = (railB - railA).Magnitude
			local railFrame = CFrame.lookAt((railA + railB) / 2, railB)
			trim(Vector3.new(0.8, 3, length), CFrame.lookAt((a + b) / 2 + offset, b + offset) * CFrame.new(0, -2, 0), "RampStringer")
			trim(Vector3.new(0.9, 2.6, railLength), railFrame * CFrame.new(0, 1.3, 0), "RampRail")
			trim(Vector3.new(1.3, 0.45, railLength + 0.3), railFrame * CFrame.new(0, 2.8, 0), "RampRailCap")
			local posts = math.max(2, math.floor(railLength / 6) + 1)
			for i = 0, posts - 1 do
				local at = railA:Lerp(railB, i / (posts - 1))
				trim(Vector3.new(1.3, 3.8, 1.3), CFrame.new(at + Vector3.new(0, 1.9, 0)), "RampPost")
			end
		end
	end

	local floors = if level >= 4 then 3 elseif level >= 3 then 2 else 1
	for story = 2, floors do
		local top = floorTop(story)
		local z0 = FLOOR_Z0[story]
		local depth = FLOOR_Z1 - z0
		local midZ = (z0 + FLOOR_Z1) / 2
		p({
			Name = "Floor",
			Size = Vector3.new(FLOOR_X * 2, 1, depth),
			CFrame = CFrame.new(0, top - 0.5, midZ),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(130, 105, 75),
		})
		-- Posts down to the floor below (none at the Top Floor's front: the walls
		-- below rise to meet its slab)
		for _, x in { -(FLOOR_X - 1), FLOOR_X - 1 } do
			for _, z in (if story > 2 then { FLOOR_Z1 - 1 } else { z0 + 1, FLOOR_Z1 - 1 }) do
				trim(Vector3.new(2.4, FLOOR_HEIGHT, 2.4), CFrame.new(x, top - FLOOR_HEIGHT / 2, z), "FloorPost")
			end
		end
		if story > 2 then
			local from = floorTop(story - 1) + FLOOR_WALL
			local height = top - 1 - from
			for _, side in { -1, 1 } do
				wall(Vector3.new(0.4, height, depth), CFrame.new(side * FLOOR_X, from + height / 2, midZ))
			end
			wall(Vector3.new(FLOOR_X * 2, height, 0.4), CFrame.new(0, from + height / 2, FLOOR_Z1))
		end
		arcade(z0, top)
		if story == 2 then
			-- Tall arches across the ground floor's front, under the Second Floor
			local bays = 5
			local bay = FLOOR_X * 2 / bays
			local below = top - 1 - TOP
			for i = 1, bays - 1 do
				trim(Vector3.new(1.8, below, 1.8), CFrame.new(-FLOOR_X + i * bay, TOP + below / 2, z0), "ArchPillar")
			end
			for i = 0, bays - 1 do
				local x = -FLOOR_X + (i + 0.5) * bay
				local span = bay - 1.8
				trim(Vector3.new(span, 1.8, 1.4), CFrame.new(x, top - 1 - 0.9, z0), "ArchLintel")
				for _, side in { -1, 1 } do
					trim(
						Vector3.new(3.4, 3.4, 1.2),
						CFrame.new(x + side * (span / 2 - 0.6), top - 1 - 2.2, z0) * CFrame.Angles(0, 0, math.rad(45)),
						"ArchCorner"
					)
				end
			end
		end
		wallX(-FLOOR_X, FLOOR_X, FLOOR_Z1, top)
		if story == 3 then
			merlons(Vector3.new(-FLOOR_X, 0, FLOOR_Z1), Vector3.new(FLOOR_X, 0, FLOOR_Z1), top)
			merlons(Vector3.new(FLOOR_X, 0, z0 + 2), Vector3.new(FLOOR_X, 0, FLOOR_Z1 - 2), top)
			merlons(Vector3.new(-FLOOR_X, 0, RAMP2_ENTRY[2] + 2), Vector3.new(-FLOOR_X, 0, FLOOR_Z1 - 2), top)
		end
		if story == 2 then
			-- Right: the ground ramp lands at z 6-12. Left: the way up leaves at the
			-- back (RAMP2_EXIT), walled while the Top Floor isn't bought
			wallZ(z0, 6, FLOOR_X, top)
			wallZ(12, FLOOR_Z1, FLOOR_X, top)
			wallZ(z0, RAMP2_EXIT[1], -FLOOR_X, top)
			wallZ(RAMP2_EXIT[2], FLOOR_Z1, -FLOOR_X, top)
			if floors == 2 then
				wallZ(RAMP2_EXIT[1], RAMP2_EXIT[2], -FLOOR_X, top)
			end
		else
			wallZ(z0, RAMP2_ENTRY[1], -FLOOR_X, top)
			wallZ(RAMP2_ENTRY[2], FLOOR_Z1, -FLOOR_X, top)
			wallZ(z0, FLOOR_Z1, FLOOR_X, top)
		end
		-- Its spots: a row of 5 inside the arches, then two along each side wall facing in
		for _, x in FLOOR_FRONT_X do
			spot(x, top, FLOOR_ROW_Z[story], 0)
		end
		for _, z in FLOOR_SIDE_Z[story] do
			for _, sign in { -1, 1 } do
				spot(sign * FLOOR_SIDE_X, top, z, sign * math.pi / 2)
			end
		end
		-- Its vault rooms in the back corners: an inner wall and a front wall round a door
		for _, side in { -1, 1 } do
			local innerX = side * (FLOOR_X - 1 - VAULT_SIZE)
			local outerX = side * FLOOR_X
			local centerX = side * (FLOOR_X - 1 - VAULT_SIZE / 2)
			wallZ(VAULT_Z0, FLOOR_Z1, innerX, top, "VaultWall")
			for _, span in { { outerX, centerX - side * DOOR_WIDTH / 2 }, { centerX + side * DOOR_WIDTH / 2, innerX } } do
				wall(
					Vector3.new(math.abs(span[2] - span[1]), FLOOR_WALL, 0.6),
					CFrame.new((span[1] + span[2]) / 2, top + FLOOR_WALL / 2, VAULT_Z0),
					"VaultWall"
				)
			end
			p({
				Name = "VaultDoor",
				Size = Vector3.new(DOOR_WIDTH, FLOOR_WALL, 0.6),
				CFrame = CFrame.new(centerX, top + FLOOR_WALL / 2, VAULT_Z0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(90, 200, 255),
			})
		end
	end
	if floors >= 2 then
		-- Ground → Second Floor up the right side from the front
		local secondTop = floorTop(2)
		ramp(Vector3.new(FLOOR_X + 3, TOP, -18), Vector3.new(FLOOR_X + 3, secondTop, 6))
		p({
			Name = "RampLanding",
			Size = Vector3.new(6, 1, 6),
			CFrame = CFrame.new(FLOOR_X + 3, secondTop - 0.5, 9),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(130, 105, 75),
		})
		wallZ(6, 12, FLOOR_X + 6, secondTop)
		wallX(FLOOR_X, FLOOR_X + 6, 12, secondTop)
		if floors >= 3 then
			-- Second Floor → Top Floor: off the back left, up the left side to the front
			local thirdTop = floorTop(3)
			local rampX = -FLOOR_X - 3
			local foot, head = RAMP2_EXIT[1], RAMP2_ENTRY[2]
			for _, landing in { { secondTop, foot + 3 }, { thirdTop, head - 3 } } do
				p({
					Name = "RampLanding",
					Size = Vector3.new(6, 1, 6),
					CFrame = CFrame.new(rampX, landing[1] - 0.5, landing[2]),
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(130, 105, 75),
				})
			end
			wallX(-FLOOR_X - 6, -FLOOR_X, RAMP2_EXIT[2], secondTop)
			wallZ(RAMP2_EXIT[1], RAMP2_EXIT[2], -FLOOR_X - 6, secondTop)
			ramp(Vector3.new(rampX, secondTop, foot), Vector3.new(rampX, thirdTop, head))
			wallZ(RAMP2_ENTRY[1], RAMP2_ENTRY[2], -FLOOR_X - 6, thirdTop)
			wallX(-FLOOR_X - 6, -FLOOR_X, RAMP2_ENTRY[1], thirdTop)
		end
	end
	-- The timber arch at the Camp and Stockade
	if level <= 2 then
		for _, x in { -7.5, 7.5 } do
			p({ Name = "Arch", Size = Vector3.new(1, 12, 1), CFrame = CFrame.new(x, 6, PLOT_FRONT), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50) })
		end
		p({ Name = "Arch", Size = Vector3.new(17, 1.2, 1.2), CFrame = CFrame.new(0, 12, PLOT_FRONT), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50) })
	end
	local hallEnd = math.min(GROUND_ROWS[#GROUND_ROWS], PLOT_FRONT + D - 6)
	return W, D, hallEnd
end
return true

-- A rough stand-in for the plot itself (floor, pedestals, floors above), so the
-- fortress preview shows it in context. Mirrors WorldService's sizes.
local WIDTHS, DEPTHS = { 60, 64, 68, 72, 76 }, { 48, 56, 68, 68, 68 }
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
function plotContext(parent, level)
	local W, D = WIDTHS[level], DEPTHS[level]
	local function p(props)
		local x = Instance.new("Part")
		x.Anchored = true
		for k, v in props do x[k] = v end
		x.Parent = parent
		return x
	end
	p({ Name = "Floor", Size = Vector3.new(W, 1, D), CFrame = CFrame.new(0, 0.5, -22 + D / 2), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 120, 85) })
	-- The keep floors (mirrors WorldService: stone walls, an arched front, battlements up top)
	local stoneMat = if level >= 5 then Enum.Material.Limestone else Enum.Material.Cobblestone
	local stone = if level >= 5 then Color3.fromRGB(236, 226, 206) else Color3.fromRGB(140, 134, 126)
	local light = if level >= 5 then Color3.fromRGB(245, 238, 222) else Color3.fromRGB(156, 150, 142)
	-- A creature spot: its pedestal, its display niche (WorldService's sizes) and a creature
	local shown = 0
	local function spot(x, floorY, z)
		shown += 1
		p({ Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 6, 6), CFrame = CFrame.new(x, floorY + 0.7, z) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 120, 130) })
		local W_, H_ = 6.2, 5.6
		local face = CFrame.new(x, floorY, z + 4)
		local roundFace = CFrame.Angles(0, math.pi / 2, 0)
		local back = p({ Name = "NicheBack", Size = Vector3.new(W_, H_, 0.8), CFrame = face * CFrame.new(0, H_ / 2, 0.4), Material = stoneMat, Color = stone })
		back:SetAttribute("Keep", true)
		back:SetAttribute("Slot", shown)
		local arch = p({ Name = "NicheArch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, W_, W_), CFrame = face * CFrame.new(0, H_, 0.4) * roundFace, Material = stoneMat, Color = light })
		arch:SetAttribute("Keep", true)
		for _, side in { -1, 1 } do
			local pil = p({ Name = "NichePilaster", Size = Vector3.new(0.7, H_ + 0.6, 1.3), CFrame = face * CFrame.new(side * (W_ / 2 + 0.1), (H_ + 0.6) / 2, 0.25), Material = stoneMat, Color = light })
			pil:SetAttribute("Keep", true)
		end
		local pick = SHOWN[(shown - 1) % #SHOWN + 1]
		local inner = W_ - 1.6
		local glowPanel = p({ Name = "NicheGlow", Size = Vector3.new(inner, H_ - 1.4, 0.12), CFrame = face * CFrame.new(0, 0.7 + H_ / 2, -0.06), Material = Enum.Material.Neon, Color = pick[2] })
		p({ Name = "NicheGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, inner, inner), CFrame = face * CFrame.new(0, H_, -0.06) * roundFace, Material = Enum.Material.Neon, Color = pick[2] })
		local l = Instance.new("PointLight")
		l.Range = 9
		l.Brightness = 1.6
		l.Color = pick[2]
		l.Parent = glowPanel
		-- The creature (adults: longest side 7, as CreatureService scales them)
		local ext = AVAILABLE_PROPS and AVAILABLE_PROPS[pick[1]]
		if ext and type(ext) == "table" then
			local height = ext.Y * 7 / math.max(ext.X, ext.Y, ext.Z)
			PreviewProps.spawn(pick[1], CFrame.new(x, floorY + 1.4, z), height, parent)
		end
	end
	local count = ({ 10, 15, 20, 20, 20 })[level]
	for i = 1, count do
		local col, row = (i - 1) % 5, (i - 1) // 5
		spot(-22 + col * 11, 1, 6 + row * 11)
	end
	-- Named like WorldService's floor pieces, so CastleKits.dressKeep dresses them the same
	local function wall(size, cf, name) local w = p({ Name = name or "FloorWall", Size = size, CFrame = cf, Material = stoneMat, Color = stone }); w:SetAttribute("Glass", true); return w end
	local function trim(size, cf, name) local t = p({ Name = name or "Trim", Size = size, CFrame = cf, Material = stoneMat, Color = light }); t:SetAttribute("Keep", true); return t end
	local function arcade(z, top)
		local bays = 5
		local bay = 56 / bays
		for i = 0, bays do trim(Vector3.new(1.8, 9, 1.8), CFrame.new(-28 + i * bay, top + 4.5, z), "ArchPillar") end
		for i = 0, bays - 1 do
			local x = -28 + (i + 0.5) * bay
			local span = bay - 1.8
			trim(Vector3.new(span, 1.8, 1.4), CFrame.new(x, top + 8.1, z), "ArchLintel")
			for _, side in { -1, 1 } do trim(Vector3.new(2.4, 2.4, 1.2), CFrame.new(x + side * (span / 2 - 0.5), top + 7.2, z) * CFrame.Angles(0, 0, math.rad(45)), "ArchCorner") end
			trim(Vector3.new(span, 2.6, 0.9), CFrame.new(x, top + 1.3, z), "Balustrade")
		end
		trim(Vector3.new(58, 0.8, 2.2), CFrame.new(0, top + 9.4, z), "ArchCap")
		trim(Vector3.new(57, 1.6, 0.8), CFrame.new(0, top - 1.1, z - 0.2), "FloorFascia")
	end
	local function storey(top, z0)
		for col = 0, 4 do
			spot(-21.6 + col * 10.8, top, z0 + 6)
		end
		local depth = 46 - z0
		p({ Name = "Floor", Size = Vector3.new(56, 1, depth), CFrame = CFrame.new(0, top - 0.5, (z0 + 46) / 2), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(130, 105, 75) })
		arcade(z0, top)
		wall(Vector3.new(56, 9, 0.4), CFrame.new(0, top + 4.5, 46))
		for _, x in { -28, 28 } do wall(Vector3.new(0.4, 9, depth), CFrame.new(x, top + 4.5, (z0 + 46) / 2)) end
		for _, x in { -27, 27 } do for _, z in (if top > 20 then { 45 } else { z0 + 1, 45 }) do trim(Vector3.new(2.4, 18, 2.4), CFrame.new(x, top - 9, z), "FloorPost") end end
		if top > 20 then
			-- The floor below's walls rise to meet this slab (WorldService: no front posts up here)
			for _, x in { -28, 28 } do wall(Vector3.new(0.4, 8, depth), CFrame.new(x, top - 5, (z0 + 46) / 2)) end
			wall(Vector3.new(56, 8, 0.4), CFrame.new(0, top - 5, 46))
		end
		-- vault rooms in the back corners
		for _, side in { -1, 1 } do
			wall(Vector3.new(0.4, 9, 12), CFrame.new(side * 16, top + 4.5, 40), "VaultWall")
			wall(Vector3.new(12, 9, 0.6), CFrame.new(side * 22, top + 4.5, 34), "VaultWall")
			p({ Name = "VaultDoor", Size = Vector3.new(6, 8, 0.7), CFrame = CFrame.new(side * 21.5, top + 4, 33.9), Material = Enum.Material.Neon, Color = Color3.fromRGB(90, 200, 255) })
		end
	end
	local function rampUp(a, b)
		local len = (b - a).Magnitude
		p({ Name = "Ramp", Size = Vector3.new(6, 1, len), CFrame = CFrame.lookAt((a + b) / 2, b), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(130, 105, 75) })
		-- Stone stairs drawn on it (WorldService's ramp)
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local along = flat.Unit
		local steps = math.max(4, math.floor(flat.Magnitude / 1.5))
		local run, rise = flat.Magnitude / steps, (b.Y - a.Y) / steps
		for step = 0, steps - 1 do
			local height = math.abs(rise) + 0.6
			local top = a.Y + 0.5 + (step + 0.5) * rise + 0.25
			local at = Vector3.new(a.X, top - height / 2, a.Z) + along * (step + 0.5) * run
			trim(Vector3.new(5.6, height, run + 0.02), CFrame.lookAt(at, at + along), "Stair")
		end
		for i = 0, 3 do
			local p0, p1 = a + (b - a) * (i / 4), a + (b - a) * ((i + 1) / 4)
			local bottom, height = p0.Y - 1, p1.Y + 9 - (p0.Y - 1)
			for _, side in { -1, 1 } do
				wall(Vector3.new(0.4, height, len / 4), CFrame.new(a.X + side * 3.2, bottom + height / 2, (p0.Z + p1.Z) / 2), "RampWall")
			end
		end
	end
	if level >= 3 then
		storey(19, 2)
		-- Tall arches across the ground floor's front, under the Second Floor
		local bay = 56 / 5
		for i = 1, 4 do trim(Vector3.new(1.8, 17, 1.8), CFrame.new(-28 + i * bay, 1 + 8.5, 2), "ArchPillar") end
		for i = 0, 4 do
			local x = -28 + (i + 0.5) * bay
			local span = bay - 1.8
			trim(Vector3.new(span, 1.8, 1.4), CFrame.new(x, 17.1, 2), "ArchLintel")
			for _, side in { -1, 1 } do trim(Vector3.new(3.4, 3.4, 1.2), CFrame.new(x + side * (span / 2 - 0.6), 15.8, 2) * CFrame.Angles(0, 0, math.rad(45)), "ArchCorner") end
		end
		rampUp(Vector3.new(31, 1, -18), Vector3.new(31, 19, 6))
	end
	if level >= 4 then
		storey(37, 14)
		rampUp(Vector3.new(-31, 19, 8), Vector3.new(-31, 37, 28))
		for i = 0, 14 do trim(Vector3.new(1.8, 1.8, 1.8), CFrame.new(-28 + i * 4, 46.9, 46), "Merlon") end
		for i = 0, 7 do trim(Vector3.new(1.8, 1.8, 1.8), CFrame.new(28, 46.9, 16 + i * 4), "Merlon") end
	end
	-- The timber arch at the Camp and Stockade
	if level <= 2 then
		for _, x in { -7.5, 7.5 } do p({ Name = "Arch", Size = Vector3.new(1, 12, 1), CFrame = CFrame.new(x, 6, -22), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50) }) end
		p({ Name = "Arch", Size = Vector3.new(17, 1.2, 1.2), CFrame = CFrame.new(0, 12, -22), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50) })
	end
	return W, D
end
return true

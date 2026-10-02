-- A rough stand-in for the plot itself (floor, pedestals, floors above), so the
-- fortress preview shows it in context. Mirrors WorldService's sizes.
local WIDTHS, DEPTHS = { 60, 64, 68, 72, 76 }, { 48, 56, 68, 68, 68 }
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
	local count = ({ 10, 15, 20, 20, 20 })[level]
	for i = 1, count do
		local col, row = (i - 1) % 5, (i - 1) // 5
		p({ Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 6, 6), CFrame = CFrame.new(-22 + col * 11, 1.7, 6 + row * 11) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 120, 130) })
	end
	-- The keep floors (mirrors WorldService: stone walls, an arched front, battlements up top)
	local stoneMat = if level >= 5 then Enum.Material.Limestone else Enum.Material.Cobblestone
	local stone = if level >= 5 then Color3.fromRGB(236, 226, 206) else Color3.fromRGB(140, 134, 126)
	local light = if level >= 5 then Color3.fromRGB(245, 238, 222) else Color3.fromRGB(156, 150, 142)
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
		local depth = 46 - z0
		p({ Name = "Floor", Size = Vector3.new(56, 1, depth), CFrame = CFrame.new(0, top - 0.5, (z0 + 46) / 2), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(130, 105, 75) })
		arcade(z0, top)
		wall(Vector3.new(56, 9, 0.4), CFrame.new(0, top + 4.5, 46))
		for _, x in { -28, 28 } do wall(Vector3.new(0.4, 9, depth), CFrame.new(x, top + 4.5, (z0 + 46) / 2)) end
		for _, x in { -27, 27 } do for _, z in { z0 + 1, 45 } do trim(Vector3.new(2.4, 18, 2.4), CFrame.new(x, top - 9, z), "FloorPost") end end
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

--!strict
-- Decor bought for a base (Config.BaseBuilds items of kind "Decor"; owner,
-- 2026-10-01: lots of buyable features and props). Each item has its own spot,
-- mostly outside the fortress walls where everyone sees them: torches and banners
-- on the walls, planters, a campfire, a training yard, a well, a lantern path up
-- to the gate, a fountain, stone statues of the owner's two rarest creatures by
-- the gate, a moat with a drawbridge, and gold trim with crystals for the Citadel.
-- Imported models (WorldProps) where there are some, parts otherwise. Rebuilt
-- whole into a Folder "Builds" whenever what's shown changes.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Fortress = require(script.Parent.Fortress)
local Props = require(script.Parent.Props)

local BaseDecor = {}

local GOLD = Color3.fromRGB(240, 195, 70)
local FIRE = Color3.fromRGB(255, 150, 60)

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
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

local function flame(parent: BasePart, size: number, lit: boolean)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = 6
	fire.Color = FIRE
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = parent
	if lit then
		local light = Instance.new("PointLight")
		light.Color = FIRE
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = parent
	end
end

-- An imported model standing on `base`, or the stand-in.
local function prop(parent: Instance, name: string, base: CFrame, height: number, standIn: (CFrame) -> ())
	if not Props.spawn(name, base, height, parent) then
		standIn(base)
	end
end

-- The `Statue` look: a creature model turned to stone on a plinth.
local function statue(parent: Instance, species: string, base: CFrame)
	part(parent, {
		Name = "StatuePlinth",
		Size = Vector3.new(4.6, 3, 4.6),
		CFrame = base * CFrame.new(0, 1.5, 0),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(205, 200, 190),
		CanCollide = true,
	})
	local template = Props.template("CreatureModels", species)
	if template == nil then
		return
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
	Props.reskin(model, Enum.Material.Slate, Color3.fromRGB(170, 168, 160))
	Props.place(model, base * CFrame.new(0, 3 + 3.5, 0), Vector3.new(6, 7, 6))
	model.Name = "Statue"
	model.Parent = parent
end

-- Builds the decor in `shown` (item ids) for a plot. `statues` names the owner's
-- two rarest species for the Guardian Statues.
function BaseDecor.build(
	parent: Instance,
	origin: CFrame,
	layout: Fortress.Layout,
	shown: { [string]: boolean },
	theme: Config.BaseTheme,
	statues: { string }?
)
	local existing = parent:FindFirstChild("Builds")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Builds"
	local x, f, b, g = layout.halfW, layout.front, layout.back, layout.gateHalf
	local face = layout.thickness / 2 -- from the wall's middle to its outer face
	local low = layout.height < 6 -- the Camp's fence: hang things on poles instead
	local function at(px: number, pz: number, facing: number?): CFrame
		return origin * CFrame.new(px, 0, pz) * CFrame.Angles(0, math.rad(facing or 180), 0)
	end

	if shown.WallTorches then
		local spots = {
			Vector3.new(-g - 5, 0, f - face - 0.7),
			Vector3.new(g + 5, 0, f - face - 0.7),
			Vector3.new(-x + 4, 0, f - face - 0.7),
			Vector3.new(x - 4, 0, f - face - 0.7),
			Vector3.new(-x - face - 0.7, 0, (f + b) / 2),
			Vector3.new(x + face + 0.7, 0, (f + b) / 2),
		}
		for i, spot in spots do
			prop(folder, "WallTorch", at(spot.X, spot.Z), 5.5, function(base)
				column(
					folder,
					base,
					0.4,
					4.6,
					{ Name = "TorchPost", Material = Enum.Material.Wood, Color = Color3.fromRGB(95, 65, 40) }
				)
				local head = part(folder, {
					Name = "TorchHead",
					Size = Vector3.new(0.7, 0.9, 0.7),
					CFrame = base * CFrame.new(0, 5, 0),
					Material = Enum.Material.Neon,
					Color = FIRE,
				})
				flame(head, 2.5, i <= 4)
			end)
		end
	end

	if shown.CampSupplies then
		prop(folder, "CampSupplies", at(-g - 13, f - 6, 200), 4, function(base)
			for i, offset in { Vector3.new(-1.5, 0, 0), Vector3.new(1.5, 0, 0.4), Vector3.new(0, 0, -2) } do
				local size = if i == 3 then Vector3.new(2.6, 2.6, 2.6) else Vector3.new(2.2, 2.2, 2.2)
				part(folder, {
					Name = "Crate",
					Size = size,
					CFrame = base * CFrame.new(offset + Vector3.new(0, size.Y / 2, 0)),
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(150, 110, 70),
					CanCollide = true,
				})
			end
			column(
				folder,
				base * CFrame.new(3.4, 0, -1),
				2,
				2.6,
				{ Name = "Barrel", Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(125, 85, 50) }
			)
		end)
	end

	if shown.Campfire then
		prop(folder, "Campfire", at(-g - 24, f - 14), 3.2, function(base)
			for i = 0, 7 do
				local angle = i / 8 * 2 * math.pi
				part(folder, {
					Name = "FireStone",
					Size = Vector3.new(1.2, 0.8, 1.2),
					CFrame = base * CFrame.new(math.cos(angle) * 2.2, 0.4, math.sin(angle) * 2.2),
					Material = Enum.Material.Slate,
					Color = Color3.fromRGB(120, 120, 120),
				})
			end
			local logs = part(folder, {
				Name = "Logs",
				Size = Vector3.new(2.6, 0.6, 0.6),
				CFrame = base * CFrame.new(0, 0.5, 0),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(90, 60, 40),
			})
			flame(logs, 5, true)
		end)
	end

	if shown.FlowerPlanters then
		for _, px in { -g - 9, -g - 19, g + 9, g + 19 } do
			prop(folder, "FlowerPlanter", at(px, f - face - 1), 2.2, function(base)
				part(folder, {
					Name = "Planter",
					Size = Vector3.new(5, 1.4, 1.6),
					CFrame = base * CFrame.new(0, 0.7, 0),
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(135, 95, 60),
				})
				for i = -2, 2 do
					part(folder, {
						Name = "Bloom",
						Shape = Enum.PartType.Ball,
						Size = Vector3.new(0.9, 0.9, 0.9),
						CFrame = base * CFrame.new(i * 0.95, 1.8, 0),
						Material = Enum.Material.SmoothPlastic,
						Color = ({
							Color3.fromRGB(230, 70, 80),
							Color3.fromRGB(250, 210, 70),
							Color3.fromRGB(160, 90, 230),
						})[(i + 3) % 3 + 1],
					})
				end
			end)
		end
	end

	if shown.Banners then
		local banner = theme.bannerColor or theme.laserColor
		local stripe = theme.roofColor or theme.trimColor
		for _, px in { -g - 7.5, g + 7.5, -x + 8, x - 8 } do
			local top = if low then 8 else layout.height - 0.5
			local base = at(px, f - face - 0.3)
			if low then
				column(
					folder,
					base,
					0.3,
					8.5,
					{ Name = "BannerPole", Material = Enum.Material.Wood, Color = Color3.fromRGB(95, 65, 40) }
				)
			end
			part(folder, {
				Name = "Banner",
				Size = Vector3.new(2.6, 5.5, 0.12),
				CFrame = base * CFrame.new(0, top - 2.75, 0),
				Material = theme.bannerMaterial or Enum.Material.Fabric,
				Color = banner,
			})
			part(folder, {
				Name = "BannerStripe",
				Size = Vector3.new(2.7, 0.5, 0.14),
				CFrame = base * CFrame.new(0, top - 4.6, 0),
				Material = Enum.Material.Fabric,
				Color = stripe,
			})
			part(folder, {
				Name = "BannerRod",
				Size = Vector3.new(3.2, 0.25, 0.25),
				CFrame = base * CFrame.new(0, top, 0),
				Material = Enum.Material.Metal,
				Color = GOLD,
			})
		end
	end

	if shown.TrainingYard then
		prop(folder, "TrainingDummy", at(g + 20, f - 13, 160), 5, function(base)
			column(
				folder,
				base,
				0.4,
				4,
				{ Name = "DummyPost", Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 50) }
			)
			part(folder, {
				Name = "DummyBody",
				Size = Vector3.new(1.6, 2.2, 1),
				CFrame = base * CFrame.new(0, 3.4, 0),
				Material = Enum.Material.Fabric,
				Color = Color3.fromRGB(210, 180, 110),
			})
			part(folder, {
				Name = "DummyHead",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.2, 1.2, 1.2),
				CFrame = base * CFrame.new(0, 5, 0),
				Material = Enum.Material.Fabric,
				Color = Color3.fromRGB(200, 170, 105),
			})
		end)
	end

	if shown.StoneWell then
		prop(folder, "StoneWell", at(g + 22, f - 28, 200), 6, function(base)
			column(folder, base, 4.4, 2.4, {
				Name = "Well",
				Material = Enum.Material.Cobblestone,
				Color = Color3.fromRGB(140, 135, 125),
				CanCollide = true,
			})
			for _, side in { -1, 1 } do
				part(folder, {
					Name = "WellPost",
					Size = Vector3.new(0.4, 4, 0.4),
					CFrame = base * CFrame.new(side * 1.9, 3.6, 0),
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(110, 78, 50),
				})
			end
			part(folder, {
				Name = "WellRoof",
				Size = Vector3.new(5, 0.4, 3.4),
				CFrame = base * CFrame.new(0, 5.7, 0),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(150, 60, 45),
			})
		end)
	end

	if shown.LanternPath then
		for _, pz in { f - 11, f - 22, f - 33 } do
			for _, side in { -1, 1 } do
				local base = at(side * 6.5, pz)
				local lamp = Props.spawn("LampPost", base, 9, folder)
				local glowAt: BasePart? = if lamp
					then (lamp.PrimaryPart or lamp:FindFirstChildWhichIsA("BasePart", true))
					else nil
				if lamp == nil then
					column(folder, base, 0.4, 8, {
						Name = "LanternPost",
						Material = Enum.Material.Metal,
						Color = Color3.fromRGB(45, 45, 50),
					})
					glowAt = part(folder, {
						Name = "Lantern",
						Size = Vector3.new(1, 1.3, 1),
						CFrame = base * CFrame.new(0, 8.4, 0),
						Material = Enum.Material.Neon,
						Color = Color3.fromRGB(255, 210, 140),
					})
				end
				if glowAt then
					local light = Instance.new("PointLight")
					light.Color = Color3.fromRGB(255, 205, 140)
					light.Range = 14
					light.Brightness = 1
					light.Parent = glowAt
				end
			end
		end
	end

	if shown.Fountain then
		prop(folder, "Fountain", at(-g - 22, f - 30), 7, function(base)
			column(folder, base, 9, 1.4, {
				Name = "FountainBasin",
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(215, 210, 200),
				CanCollide = true,
			})
			column(folder, base * CFrame.new(0, 1.2, 0), 8, 0.3, {
				Name = "FountainWater",
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(110, 180, 230),
				Transparency = 0.2,
			})
			column(folder, base, 1.2, 4.6, {
				Name = "FountainPillar",
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(215, 210, 200),
			})
			column(folder, base * CFrame.new(0, 4.6, 0), 3.4, 0.5, {
				Name = "FountainBowl",
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(225, 220, 210),
			})
		end)
	end

	if shown.GuardianStatues then
		local list = statues or {}
		for i, side in { -1, 1 } do
			local species = list[i] or list[1]
			local base = at(side * (g + 3), f - 9)
			if species then
				statue(folder, species, base)
			else
				part(folder, {
					Name = "StatuePlinth",
					Size = Vector3.new(4.6, 3, 4.6),
					CFrame = base * CFrame.new(0, 1.5, 0),
					Material = Enum.Material.Marble,
					Color = Color3.fromRGB(205, 200, 190),
					CanCollide = true,
				})
			end
		end
	end

	if shown.Moat then
		-- Water round the outside of the walls, with a drawbridge at the gate
		local inner = face + 1.5
		local width = 3.2
		local water = {
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(70, 150, 210),
			Transparency = 0.15,
			Reflectance = 0.15,
		}
		local function strip(cx: number, cz: number, sx: number, sz: number)
			part(folder, {
				Name = "Moat",
				Size = Vector3.new(sx, 0.2, sz),
				CFrame = origin * CFrame.new(cx, 0.14, cz),
				Material = water.Material,
				Color = water.Color,
				Transparency = water.Transparency,
				Reflectance = water.Reflectance,
			})
		end
		local mid = inner + width / 2
		local outerX = x + inner + width
		strip(0, b + mid, outerX * 2, width) -- back
		strip(-x - mid, (f + b) / 2, width, b - f + (inner + width) * 2) -- left
		strip(x + mid, (f + b) / 2, width, b - f + (inner + width) * 2) -- right
		local gapHalf = 6
		strip(-(outerX + gapHalf) / 2, f - mid, outerX - gapHalf, width) -- front, either side of the bridge
		strip((outerX + gapHalf) / 2, f - mid, outerX - gapHalf, width)
		part(folder, {
			Name = "Drawbridge",
			Size = Vector3.new(gapHalf * 2, 0.5, width + 2.5),
			CFrame = origin * CFrame.new(0, 0.3, f - mid),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(130, 92, 58),
		})
		for _, side in { -1, 1 } do
			part(folder, {
				Name = "BridgeChain",
				Size = Vector3.new(0.25, 0.25, layout.height),
				CFrame = origin
					* CFrame.new(side * (gapHalf - 0.5), layout.height / 2, f - mid + 0.6)
					* CFrame.Angles(math.rad(-58), 0, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(60, 60, 66),
			})
		end
	end

	if shown.RoyalTrim then
		-- Gold along the battlements and a floating crystal over every corner
		local runs: { { center: Vector3, length: number } } = {
			{ center = Vector3.new(0, 0, b), length = x * 2 },
			{ center = Vector3.new(-x, 0, (f + b) / 2), length = b - f },
			{ center = Vector3.new(x, 0, (f + b) / 2), length = b - f },
		}
		for _, run in runs do
			local center, length = run.center, run.length
			local alongZ = center.X ~= 0
			part(folder, {
				Name = "GoldTrim",
				Size = if alongZ
					then Vector3.new(layout.thickness + 0.7, 0.4, length)
					else Vector3.new(length, 0.4, layout.thickness + 0.7),
				CFrame = origin * CFrame.new(center.X, layout.height + 0.65, center.Z),
				Material = Enum.Material.Foil,
				Color = GOLD,
			})
		end
		for _, corner in
			{
				Vector3.new(-x - 1, 0, b + 1),
				Vector3.new(x + 1, 0, b + 1),
				Vector3.new(-x - 1, 0, f - 1),
				Vector3.new(x + 1, 0, f - 1),
			}
		do
			local style = Fortress.style(layout.level)
			local crystal = part(folder, {
				Name = "RoyalCrystal",
				Size = Vector3.new(2, 2, 2),
				CFrame = origin
					* CFrame.new(corner.X, style.towerHeight + style.towerRadius * 3 + 6, corner.Z)
					* CFrame.Angles(math.rad(45), math.rad(35), math.rad(45)),
				Material = Enum.Material.Neon,
				Color = theme.laserColor,
			})
			local light = Instance.new("PointLight")
			light.Color = crystal.Color
			light.Range = 16
			light.Brightness = 1
			light.Parent = crystal
		end
	end

	-- Rainbow designs: the client cycles these through the colors
	local rainbow = theme.rainbow
	if rainbow then
		for _, descendant in folder:GetDescendants() do
			if
				(rainbow.banner and descendant.Name == "Banner")
				or (rainbow.glow and descendant.Name == "RoyalCrystal")
			then
				CollectionService:AddTag(descendant, "Rainbow")
			end
		end
	end
	folder.Parent = parent
end

return BaseDecor

--!strict
-- How each finish recolors a creature: a solid material in place of its texture
-- (the look of the approved finish sheet). Shared by the server (creatures on
-- pedestals) and the client (the hatch reveal's spinning model). Sparkles, auras,
-- the Galaxy planet and Prismatic color cycling are added on top by their owners.
--
-- Dialed up 2026-10-03 (owner: "the blood moon and other effects needed to be
-- tweaked and dialed up. Diamond is far too flat and needs to resemble diamond from
-- Fortnite"): Diamond wears the DiamondGem material (brilliant-cut facets, falling
-- back to glass until Studio has it), and finishes with a `shine` get the SHINE_TAG
-- so the client animates them: Diamond's opal glints drift, Blood Moon's color and
-- light beat like a heart, Molten's light flickers (CreatureAnimator).
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")

local Materials = require(script.Parent.Config.Materials)

export type Look = {
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	-- A tiling image on every face that the client slides each frame so it holds
	-- still on screen while the creature moves through it (CreatureAnimator)
	sky: { texture: string, studsPerTile: number }?,
	-- A custom material (Config/Materials.luau); `fallback` is worn until Studio has it
	variant: string?,
	fallback: { color: Color3?, material: Enum.Material?, transparency: number?, reflectance: number? }?,
	-- How the client animates it (CreatureAnimator, CreatureViewport)
	shine: ("Diamond" | "BloodMoon" | "Molten")?,
}

local LOOKS: { [string]: Look } = {
	Gold = { color = Color3.fromRGB(255, 200, 50), material = Enum.Material.Foil, reflectance = 0.35 },
	Chrome = {
		color = Color3.fromRGB(228, 233, 240),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.75,
	},
	-- Fortnite-style diamond: faceted crystal, mostly white with blue facets, glossy
	Diamond = {
		color = Color3.fromRGB(244, 249, 255),
		variant = "DiamondGem",
		reflectance = 0.2,
		fallback = {
			color = Color3.fromRGB(205, 240, 255),
			material = Enum.Material.Glass,
			transparency = 0.12,
			reflectance = 0.35,
		},
		shine = "Diamond",
	},
	Molten = { color = Color3.fromRGB(255, 110, 20), material = Enum.Material.CrackedLava, shine = "Molten" },
	-- Deep-space indigo with a sheen; its stars are sparkles, plus an orbiting planet.
	-- Not ForceField: on meshes that draws only a faint outline and the creature vanished.
	-- With `sky` set, the creature is a window onto space: the starfield stays still on
	-- screen as the creature moves (owner, 2026-10-01, like galaxy skins in other
	-- games). The texture is assets/textures/galaxy_sky.png; "" keeps the plain look.
	Galaxy = {
		color = Color3.fromRGB(58, 34, 138),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.35,
		sky = { texture = "rbxassetid://129645056585841", studsPerTile = 6 },
	},
	Prismatic = { material = Enum.Material.Neon }, -- the client cycles the color
	BloodMoon = {
		color = Color3.fromRGB(165, 8, 24),
		material = Enum.Material.CrackedLava,
		shine = "BloodMoon",
	},
}

local SKY_FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
}

local FinishLooks = {}

FinishLooks.SKY_TAG = "SkyFinish"
FinishLooks.SHINE_TAG = "FinishShine" -- with a "Shine" attribute: the look's `shine`

-- How the client animates `finish` (nil when it doesn't).
function FinishLooks.shine(finish: string): string?
	local look = LOOKS[finish]
	return if look then look.shine else nil
end

-- Restyles `model` for `finish`. Returns false for Normal (or an unknown finish).
function FinishLooks.apply(model: Model, finish: string): boolean
	local look = LOOKS[finish]
	if look == nil then
		return false
	end
	-- Imported meshes carry their texture in a SurfaceAppearance, which would hide the color
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") then
			descendant:Destroy()
		end
	end
	-- A custom material only once Studio has made it (tools/studio/make_materials.luau)
	local variant = look.variant
	local material = if variant then Materials[variant] else nil
	local useVariant = variant ~= nil and material ~= nil and MaterialService:FindFirstChild(variant) ~= nil
	local surface = if variant and not useVariant and look.fallback then look.fallback else look
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:GetAttribute("KeepMaterial") then
			if surface.color then
				descendant.Color = surface.color
			end
			if useVariant and variant and material then
				descendant.Material = material.base
				descendant.MaterialVariant = variant
			elseif surface.material then
				descendant.Material = surface.material
				descendant.MaterialVariant = ""
			end
			if surface.transparency then
				descendant.Transparency = surface.transparency
			end
			if surface.reflectance then
				descendant.Reflectance = surface.reflectance
			end
			local sky = look.sky
			if sky and sky.texture ~= "" then
				-- A MeshPart takes each face's texture as a projection from that side
				for _, face in SKY_FACES do
					local texture = Instance.new("Texture")
					texture.Name = "Sky"
					texture.Face = face
					texture.Texture = sky.texture
					texture.StudsPerTileU = sky.studsPerTile
					texture.StudsPerTileV = sky.studsPerTile
					texture.Parent = descendant
				end
			end
		end
	end
	if look.sky and look.sky.texture ~= "" then
		CollectionService:AddTag(model, FinishLooks.SKY_TAG)
	end
	if look.shine then
		model:SetAttribute("Shine", look.shine)
		CollectionService:AddTag(model, FinishLooks.SHINE_TAG)
	end
	return true
end

return FinishLooks

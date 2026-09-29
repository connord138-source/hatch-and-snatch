--!strict
-- How each finish recolors a creature: a solid material in place of its texture
-- (the look of the approved finish sheet). Shared by the server (creatures on
-- pedestals) and the client (the hatch reveal's spinning model). Sparkles, auras,
-- the Galaxy planet and Prismatic color cycling are added on top by their owners.
export type Look = {
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
}

local LOOKS: { [string]: Look } = {
	Gold = { color = Color3.fromRGB(255, 196, 45), material = Enum.Material.Foil, reflectance = 0.25 },
	Chrome = {
		color = Color3.fromRGB(215, 220, 228),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.6,
	},
	Diamond = { color = Color3.fromRGB(190, 240, 255), material = Enum.Material.Glass, transparency = 0.3 },
	Molten = { color = Color3.fromRGB(255, 110, 20), material = Enum.Material.CrackedLava },
	-- Deep-space indigo with a sheen; its stars are sparkles, plus an orbiting planet.
	-- Not ForceField: on meshes that draws only a faint outline and the creature vanished.
	Galaxy = {
		color = Color3.fromRGB(58, 34, 138),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.35,
	},
	Prismatic = { material = Enum.Material.Neon }, -- the client cycles the color
	BloodMoon = { color = Color3.fromRGB(120, 0, 10), material = Enum.Material.CrackedLava },
}

local FinishLooks = {}

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
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:GetAttribute("KeepMaterial") then
			if look.color then
				descendant.Color = look.color
			end
			if look.material then
				descendant.Material = look.material
			end
			if look.transparency then
				descendant.Transparency = look.transparency
			end
			if look.reflectance then
				descendant.Reflectance = look.reflectance
			end
		end
	end
	return true
end

return FinishLooks

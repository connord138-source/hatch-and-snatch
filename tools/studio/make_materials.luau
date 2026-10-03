-- Paste into Studio's Command Bar in edit mode (not Play), then File -> Save to
-- Roblox. Makes or updates the custom castle materials listed in
-- src/shared/Config/Materials.luau as MaterialVariants in MaterialService.
--
-- Why a Studio step: a MaterialVariant's maps can only be set by plugins and the
-- Command Bar (a game script gets "lacking capability Plugin"), so the variants live
-- in the place file. Rerun this after uploading new maps and changing their ids.
local MaterialService = game:GetService("MaterialService")
-- A fresh copy: the Command Bar keeps the first require of a module
local materials = require(game.ReplicatedStorage.Shared.Config.Materials:Clone()) :: any

local made = {}
for name, material in materials do
	if material.colorMap == "" then
		continue
	end
	local variant = MaterialService:FindFirstChild(name)
	if variant == nil or not variant:IsA("MaterialVariant") then
		variant = Instance.new("MaterialVariant")
		variant.Name = name
	end
	variant.BaseMaterial = material.base
	variant.ColorMap = material.colorMap
	variant.NormalMap = material.normalMap
	variant.RoughnessMap = material.roughnessMap
	variant.StudsPerTile = material.studsPerTile
	variant.MaterialPattern = Enum.MaterialPattern.Regular
	variant.Parent = MaterialService
	table.insert(made, name)
end
print(`Materials ready: {table.concat(made, ", ")}. Now File -> Save to Roblox.`)

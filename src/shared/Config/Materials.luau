--!strict
-- Custom materials (Roblox MaterialVariants) for castle stone; a Castle Designer
-- stone opts in by name (its `variant`). Game scripts can't set a MaterialVariant's
-- maps, so the variants live in the place file: after changing the ids here, run
-- tools/studio/make_materials.luau in Studio's Command Bar and save the place. A
-- stone whose variant isn't there shows its plain base material.
--
--   DiamondStone (owner, 2026-10-02: "a diamond texture rather than actual diamond
--   for the base itself ... imprint iridescence in the skin of the castle as we did
--   with the creatures"): cut-diamond bricks with faint opal tints baked into the
--   color map, mid-tone (max 235) so sun and bloom don't blow it out. Made by
--   tools/textures/make_diamond_tex.py (assets/textures/diamond_*.png).
--
--   DiamondGem (owner, 2026-10-03: the creatures' Diamond finish was "far too flat
--   and needs to resemble diamond from Fortnite"): a crystal skin of brilliant-cut
--   facets, ice-white faces against blue ones with bright seams and opal tints, for
--   FinishLooks. Made by tools/textures/make_gem_tex.py (assets/textures/gem_*.png).
export type Material = {
	base: Enum.Material, -- parts must be this material for the variant to show
	colorMap: string,
	normalMap: string,
	roughnessMap: string,
	studsPerTile: number,
	-- The parts' color value, which multiplies the texture: below 1 keeps a white
	-- texture under the bloom threshold in full sun
	brightness: number,
}

local materials: { [string]: Material } = {
	DiamondStone = {
		base = Enum.Material.Salt,
		colorMap = "rbxassetid://105342885317428",
		normalMap = "rbxassetid://87940945454649",
		roughnessMap = "rbxassetid://98779874609985",
		studsPerTile = 8,
		brightness = 0.92,
	},
	DiamondGem = {
		base = Enum.Material.Ice,
		colorMap = "rbxassetid://83891185187480", -- assets/textures/gem_color.png
		normalMap = "rbxassetid://122955736534217", -- gem_normal.png
		roughnessMap = "rbxassetid://79115828987523", -- gem_roughness.png
		studsPerTile = 4,
		brightness = 0.96,
	},
}

return table.freeze(materials)

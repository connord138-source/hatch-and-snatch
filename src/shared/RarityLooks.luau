--!strict
-- How a creature shows its species rarity, so everyone can read it at a glance
-- (owner, 2026-10-01). Every creature gets a soft halo of its rarity color behind
-- it, stronger the rarer it is, and from Uncommon up a stream of stardust in that
-- color that thickens with each tier. The ultra-rares (Mythic and up) are also
-- color-converted toward their rarity color: a tint over their texture, so their
-- details and realistic eyes survive. A finish (Gold, Chrome, ...) replaces the
-- tint; the halo and stardust stay. Shared by the server (CreatureService builds
-- the effects) and the client (the hatch reveal's tint, Secret's shimmer).
local Config = require(script.Parent.Config)

export type Stardust = {
	rate: number, -- sparkles per second
	size: number,
	rise: number, -- upward drift (studs/s²)
	lifetime: number,
	brightness: number, -- above 1 blooms
	colors: { Color3 }?, -- default: the rarity color fading to white
}
export type Look = {
	halo: number, -- 0..1: how strong the halo behind the creature is
	stardust: Stardust?,
	light: number?, -- PointLight brightness (rarer tiers only: lights are costly)
	tint: Color3?, -- ultra-rares: multiplies the texture (SurfaceAppearance.Color)
	shimmer: boolean?, -- Secret: the client cycles the tint through the rainbow
}

local RAINBOW = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 230, 80),
	Color3.fromRGB(80, 255, 140),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(220, 90, 255),
}

local LOOKS: { [string]: Look } = {
	Common = { halo = 0.3 },
	Uncommon = {
		halo = 0.4,
		stardust = { rate = 1, size = 0.3, rise = 0.6, lifetime = 1.6, brightness = 1 },
	},
	Rare = {
		halo = 0.5,
		stardust = { rate = 2, size = 0.32, rise = 0.8, lifetime = 1.8, brightness = 1 },
	},
	Epic = {
		halo = 0.6,
		stardust = { rate = 4, size = 0.36, rise = 1, lifetime = 2, brightness = 1.2 },
		light = 0.3,
	},
	Legendary = {
		halo = 0.72,
		stardust = { rate = 8, size = 0.45, rise = 1.5, lifetime = 2, brightness = 1.5 },
		light = 0.5,
	},
	Mythic = {
		halo = 0.82,
		stardust = {
			rate = 16,
			size = 0.55,
			rise = 2,
			lifetime = 2.2,
			brightness = 2,
			colors = { Color3.fromRGB(255, 70, 110), Color3.fromRGB(255, 190, 205) },
		},
		light = 0.7,
		tint = Color3.fromRGB(255, 130, 150),
	},
	Celestial = {
		halo = 0.88,
		stardust = {
			rate = 20,
			size = 0.6,
			rise = 3,
			lifetime = 2.6,
			brightness = 2.2,
			colors = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(150, 235, 255) },
		},
		light = 0.8,
		tint = Color3.fromRGB(195, 238, 255),
	},
	Cosmic = {
		halo = 0.94,
		stardust = {
			rate = 26,
			size = 0.55,
			rise = 0.5,
			lifetime = 3.5,
			brightness = 2.5,
			colors = { Color3.fromRGB(140, 70, 255), Color3.fromRGB(90, 200, 255), Color3.new(1, 1, 1) },
		},
		light = 0.9,
		tint = Color3.fromRGB(175, 140, 255),
	},
	Secret = {
		halo = 1,
		stardust = { rate = 32, size = 0.6, rise = 1.2, lifetime = 2.8, brightness = 2.8, colors = RAINBOW },
		light = 1,
		tint = Color3.new(1, 1, 1),
		shimmer = true,
	},
	-- Junk Eggs' household-object creatures: a dusty halo, no sparkle
	Junk = { halo = 0.45 },
}

-- Species whose own colors fight their rarity tint (PC round 9da730a): the
-- Mythic crimson turned the white-ice Glacierion red, and the Celestial pale blue
-- turned Solarion's gold mane olive. `false` keeps the creature's own colors; a
-- color tints with that instead. Their halo and stardust keep the rarity color.
local SPECIES_TINT: { [string]: Color3 | false } = {
	Glacierion = false,
	Solarion = Color3.fromRGB(255, 232, 180), -- warmer gold, still a step up from its texture
}

local RarityLooks = {}

RarityLooks.rainbow = RAINBOW

function RarityLooks.get(rarity: string): Look
	return LOOKS[rarity] or LOOKS.Common
end

-- The halo and stardust color: the rarity color (Secret's white reads as silver)
function RarityLooks.color(rarity: string): Color3
	local entry = Config.Rarities[rarity :: any]
	return if entry then entry.color else Color3.new(1, 1, 1)
end

-- The tint for one species at its rarity (nil: no tint).
function RarityLooks.tintFor(species: string, rarity: string): Color3?
	local override = SPECIES_TINT[species]
	if override == false then
		return nil
	elseif typeof(override) == "Color3" then
		return override
	end
	return RarityLooks.get(rarity).tint
end

-- Tints every textured part of `model` with `color` (SurfaceAppearance.Color
-- multiplies the texture). Untextured parts get the same tint on their color.
function RarityLooks.tint(model: Model, color: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") then
			-- Guarded: if a Roblox update ever made it read-only, the creature still builds
			pcall(function()
				descendant.Color = color
			end)
		elseif descendant:IsA("BasePart") and not descendant:GetAttribute("KeepMaterial") then
			local part: BasePart = descendant
			local textured = part:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
				or (part:IsA("MeshPart") and part.TextureID ~= "")
			if not textured then
				local base = part.Color
				part.Color = Color3.new(base.R * color.R, base.G * color.G, base.B * color.B)
			end
		end
	end
end

return RarityLooks

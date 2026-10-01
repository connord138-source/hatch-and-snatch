--!strict
-- How each genetic mutation looks (owner, 2026-10-01): mutations are the rarest,
-- most-wanted layer in the game, "like Galaxy: other people will want them", and
-- they have to look professional and clean. So each one is a single body
-- treatment in the style of the approved finish sheet, a thin ring in its accent
-- color round the rarity halo (readable across a base), its name in that color on
-- the nameplate, and at most a few soft glints. Shared by the server (pedestal
-- and walked models) and the client (the hatch reveal).
--
--   Albino      pearl white, ruby accents
--   Melanistic  its own texture darkened to near-black (details survive), amber accents
--   Leucistic   a pale pastel of its biome's color
--   Piebald     crisp white patches over its own colors (a tiling texture)
--   Iridescent  pearl, its sheen drifting slowly through soft hues (the client cycles it)
--
-- On a finish the texture is already gone, so the mutation shifts the finish's
-- color instead: a black-gold Melanistic, a white-gold Albino. Piebald patches and
-- a lighter Iridescent sheen go over any finish.
local CollectionService = game:GetService("CollectionService")

export type Glint = {
	colors: { Color3 },
	rate: number,
	size: number,
	lifetime: number,
	rise: number,
}
export type Look = {
	accent: Color3, -- ring, nameplate and reveal color
	solid: { color: Color3, reflectance: number }?, -- replaces the texture (Albino)
	pastel: boolean?, -- Leucistic: solid, in its biome's pastel
	tint: Color3?, -- multiplies the texture (Melanistic)
	shift: { color: Color3, amount: number }?, -- on a finish: lerp its color toward this
	spots: boolean?, -- Piebald: the patch texture on every side
	iridescent: boolean?, -- the client drifts it through the hues
	glint: Glint?,
}

-- assets/textures/piebald_spots.png, uploaded as an image. "" until it is: the
-- Piebald then shows only its ring, name and glints.
local SPOTS_TEXTURE = ""
local SPOTS_STUDS_PER_TILE = 5
local SPOT_FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
}

-- Leucistic: each biome's own color washed almost to white
local PASTELS: { [string]: Color3 } = {
	Mossvale = Color3.fromRGB(206, 238, 196), -- mint
	CoralCoast = Color3.fromRGB(255, 208, 214), -- blush
	MagmaRift = Color3.fromRGB(255, 214, 182), -- peach
	FrostShelf = Color3.fromRGB(206, 226, 255), -- ice blue
	StormPeaks = Color3.fromRGB(255, 240, 180), -- butter
	Moonfall = Color3.fromRGB(226, 208, 255), -- lavender
	Junk = Color3.fromRGB(225, 225, 232),
}

local LOOKS: { [string]: Look } = {
	Albino = {
		accent = Color3.fromRGB(255, 105, 135),
		solid = { color = Color3.fromRGB(246, 243, 240), reflectance = 0.04 },
		shift = { color = Color3.fromRGB(250, 248, 245), amount = 0.6 },
		glint = {
			colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 190, 205) },
			rate = 3,
			size = 0.22,
			lifetime = 2.4,
			rise = 0.4,
		},
	},
	Melanistic = {
		accent = Color3.fromRGB(255, 184, 70),
		tint = Color3.fromRGB(60, 54, 66),
		shift = { color = Color3.fromRGB(22, 20, 26), amount = 0.72 },
		glint = {
			colors = { Color3.fromRGB(255, 196, 90), Color3.fromRGB(190, 110, 30) },
			rate = 3,
			size = 0.2,
			lifetime = 1.8,
			rise = 0.25,
		},
	},
	Leucistic = {
		accent = Color3.fromRGB(150, 225, 255),
		pastel = true,
		shift = { color = Color3.fromRGB(240, 246, 255), amount = 0.45 },
		glint = {
			colors = { Color3.fromRGB(220, 245, 255), Color3.new(1, 1, 1) },
			rate = 3,
			size = 0.22,
			lifetime = 2.6,
			rise = 0.5,
		},
	},
	Piebald = {
		accent = Color3.fromRGB(245, 232, 205),
		spots = true,
		glint = {
			colors = { Color3.fromRGB(255, 248, 230), Color3.new(1, 1, 1) },
			rate = 2,
			size = 0.2,
			lifetime = 2,
			rise = 0.3,
		},
	},
	Iridescent = {
		accent = Color3.fromRGB(170, 140, 255), -- the ring drifts through the hues
		solid = { color = Color3.fromHSV(0.8, 0.3, 1), reflectance = 0.12 }, -- pearl
		iridescent = true,
		glint = {
			colors = {
				Color3.fromRGB(255, 150, 200),
				Color3.fromRGB(150, 220, 255),
				Color3.fromRGB(170, 255, 200),
				Color3.fromRGB(255, 235, 150),
			},
			rate = 5,
			size = 0.24,
			lifetime = 2.2,
			rise = 0.5,
		},
	},
}

local MutationLooks = {}

MutationLooks.IRIDESCENT_TAG = "Iridescent"

function MutationLooks.get(mutation: string?): Look?
	return if mutation then LOOKS[mutation] else nil
end

-- The sheen's color at time `t` (seconds): soft pearl hues, slow, never a
-- rainbow flash (that is the Prismatic finish).
function MutationLooks.sheen(t: number, seed: number): Color3
	return Color3.fromHSV((t * 0.05 + seed) % 1, 0.3, 1)
end

local function bodyParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:GetAttribute("KeepMaterial") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Restyles `model` for its mutation, after its finish and rarity tint are on.
-- Returns false when there is no mutation (or an unknown one).
function MutationLooks.apply(model: Model, mutation: string?, finish: string, biome: string): boolean
	local look = MutationLooks.get(mutation)
	if look == nil then
		return false
	end
	local textured = finish == "Normal"
	local solid = if look.pastel
		then { color = PASTELS[biome] or PASTELS.Junk, reflectance = 0.02 }
		else look.solid
	if textured and solid then
		-- The texture goes, like a finish: one clean color with the mesh's own shading
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("SurfaceAppearance") then
				descendant:Destroy()
			end
		end
		for _, part in bodyParts(model) do
			part.Color = solid.color
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = solid.reflectance
		end
	elseif textured and look.tint then
		local tint = look.tint
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("SurfaceAppearance") then
				pcall(function()
					descendant.Color = tint
				end)
			end
		end
		for _, part in bodyParts(model) do
			if part:FindFirstChildWhichIsA("SurfaceAppearance") == nil then
				part.Color = Color3.new(part.Color.R * tint.R, part.Color.G * tint.G, part.Color.B * tint.B)
			end
		end
	elseif not textured and look.shift then
		local shift = look.shift
		for _, part in bodyParts(model) do
			part.Color = part.Color:Lerp(shift.color, shift.amount)
		end
	end
	if look.spots and SPOTS_TEXTURE ~= "" then
		-- A MeshPart takes each face's texture as a projection from that side
		for _, part in bodyParts(model) do
			for _, face in SPOT_FACES do
				local texture = Instance.new("Texture")
				texture.Name = "Piebald"
				texture.Face = face
				texture.Texture = SPOTS_TEXTURE
				texture.StudsPerTileU = SPOTS_STUDS_PER_TILE
				texture.StudsPerTileV = SPOTS_STUDS_PER_TILE
				texture.Parent = part
			end
		end
	end
	if look.iridescent then
		-- The client drifts each part through the hues: all the way on the pearl
		-- body, a light sheen over a finish's own color (kept here)
		for _, part in bodyParts(model) do
			part:SetAttribute("BaseColor", part.Color)
			part:SetAttribute("Sheen", if textured then 1 else 0.35)
		end
		CollectionService:AddTag(model, MutationLooks.IRIDESCENT_TAG)
	end
	return true
end

-- One frame of the Iridescent sheen (parts marked by apply).
function MutationLooks.shimmer(parts: { BasePart }, color: Color3)
	for _, part in parts do
		local base = part:GetAttribute("BaseColor")
		local amount = part:GetAttribute("Sheen")
		if typeof(base) == "Color3" and typeof(amount) == "number" then
			part.Color = base:Lerp(color, amount)
		end
	end
end

-- The mutation's name wrapped in its accent color, for RichText labels.
function MutationLooks.richName(mutation: string, displayName: string): string
	local look = LOOKS[mutation]
	if look == nil then
		return displayName
	end
	return `<font color="#{look.accent:ToHex()}">{displayName}</font>`
end

return MutationLooks

--!strict
-- How each genetic mutation looks (owner, 2026-10-01/02): mutations are the
-- rarest, most-wanted layer in the game, "like Galaxy: other people will want
-- them", and they must not look like decolored skins. Finishes change what a
-- creature is made of; mutations change how it was born, so each one is a SKIN
-- made from the creature's own texture (tools/mutations): every painted detail
-- stays and only the pigment, patterns and eyes change.
--
--   Albino      snow-white coat, pink skin, pale element, ruby-red eyes
--   Melanistic  jet-black coat with its pattern ghosting through, element and eyes blazing
--   Piebald     natural white patches (face, chest and paws first)
--   Chimera     split down the middle: its normal self and the opposite, one odd eye
--   Iridescent  an oil-slick film following the body's curves, drifting in game
--
-- The skins live in ReplicatedStorage.MutationSkins.<model>.<Mutation> (built in
-- Studio by tools/studio/organize_skins.luau): a SurfaceAppearance, or a
-- StringValue holding an image id. Until a model has its skin, the older solid
-- looks below stand in. Every mutation also gets a thin ring in its accent color
-- round the rarity halo, its name in that color and a few soft glints.
--
-- On a finish the texture is already gone, so the mutation shifts the finish's
-- color instead: a black-gold Melanistic, a white-gold Albino. Piebald patches and
-- a lighter Iridescent sheen go over any finish.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	solid: { color: Color3, reflectance: number }?, -- no skin yet: replaces the texture (Albino)
	tint: Color3?, -- no skin yet: multiplies the texture (Melanistic)
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
	Chimera = {
		accent = Color3.fromRGB(110, 200, 255), -- its odd eye
		glint = {
			colors = { Color3.fromRGB(190, 230, 255), Color3.new(1, 1, 1) },
			rate = 3,
			size = 0.22,
			lifetime = 2.2,
			rise = 0.4,
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

-- The skin for one model (its template name: "Emberlynx", "Emberlynx_Baby", ...)
-- and mutation, if Studio has it: a SurfaceAppearance or an image id StringValue.
function MutationLooks.skin(modelName: string?, mutation: string?): Instance?
	local skins = ReplicatedStorage:FindFirstChild("MutationSkins")
	local folder = if skins and modelName then skins:FindFirstChild(modelName) else nil
	return if folder and mutation then folder:FindFirstChild(mutation) else nil
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

-- Puts a skin on every textured part of `model` (in place of its own texture).
local function wear(model: Model, skin: Instance)
	for _, part in bodyParts(model) do
		local own = part:FindFirstChildWhichIsA("SurfaceAppearance")
		local textured = own ~= nil or (part:IsA("MeshPart") and part.TextureID ~= "")
		if textured then
			if own then
				own:Destroy()
			end
			if skin:IsA("SurfaceAppearance") then
				skin:Clone().Parent = part
			elseif skin:IsA("StringValue") and part:IsA("MeshPart") then
				part.TextureID = skin.Value
			end
		end
	end
end

-- Restyles `model` for its mutation, after its finish and rarity tint are on.
-- `modelName` is the template it was cloned from, for its skin. Returns false
-- when there is no mutation (or an unknown one).
function MutationLooks.apply(model: Model, mutation: string?, finish: string, modelName: string?): boolean
	local look = MutationLooks.get(mutation)
	if look == nil then
		return false
	end
	local textured = finish == "Normal"
	local skin = if textured then MutationLooks.skin(modelName, mutation) else nil
	local solid = look.solid
	if skin then
		wear(model, skin)
		if look.iridescent and skin:IsA("SurfaceAppearance") then
			-- The client drifts the film's tint slowly (CreatureAnimator)
			model:SetAttribute("SkinSheen", true)
			CollectionService:AddTag(model, MutationLooks.IRIDESCENT_TAG)
		end
		return true
	elseif textured and solid then
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

-- One frame of the Iridescent sheen (parts marked by apply). On a skin the film is
-- already painted in, so it only drifts the tint a little.
function MutationLooks.shimmer(parts: { BasePart }, color: Color3, appearances: { SurfaceAppearance }?)
	if appearances then
		local soft = Color3.new(1, 1, 1):Lerp(color, 0.5)
		pcall(function()
			for _, appearance in appearances do
				appearance.Color = soft
			end
		end)
		return
	end
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

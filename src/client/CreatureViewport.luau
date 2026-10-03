--!strict
-- A creature spinning in a ViewportFrame, wearing its finish and mutation: the hatch
-- reveal (RevealController) and the creature details card (CreaturesMenu) use it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local FinishLooks = require(ReplicatedStorage.Shared.FinishLooks)
local MutationLooks = require(ReplicatedStorage.Shared.MutationLooks)
local RarityLooks = require(ReplicatedStorage.Shared.RarityLooks)

export type Placement = {
	position: UDim2,
	size: UDim2,
	maxSize: Vector2?,
	zIndex: number?,
}

local CreatureViewport = {}

-- Twinkling stars over the reveal's viewport, standing in for the Galaxy finish's
-- star particles. 2D frames on top (a diamond each), so no image assets are needed.
local STAR_COLORS = { Color3.new(1, 1, 1), Color3.fromRGB(190, 170, 255), Color3.fromRGB(150, 220, 255) }

local function starfield(parent: Instance, over: ViewportFrame)
	local layer = Instance.new("Frame")
	layer.BackgroundTransparency = 1
	layer.AnchorPoint = over.AnchorPoint
	layer.Position = over.Position
	layer.Size = over.Size
	layer.ZIndex = over.ZIndex + 1
	local limit = over:FindFirstChildOfClass("UISizeConstraint")
	if limit then
		limit:Clone().Parent = layer
	end
	layer.Parent = parent
	local rng = Random.new()
	for i = 1, 22 do
		local star = Instance.new("Frame")
		local size = rng:NextInteger(4, 9)
		star.Size = UDim2.fromOffset(size, size)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(rng:NextNumber(0.2, 0.8), rng:NextNumber(0.15, 0.85))
		star.Rotation = 45
		star.BorderSizePixel = 0
		star.BackgroundColor3 = STAR_COLORS[(i % #STAR_COLORS) + 1]
		star.BackgroundTransparency = 1
		star.ZIndex = layer.ZIndex
		star.Parent = layer
		TweenService:Create(
			star,
			TweenInfo.new(
				rng:NextNumber(0.5, 1.1),
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true,
				rng:NextNumber(0, 1.5)
			),
			{ BackgroundTransparency = 0.05 }
		):Play()
	end
end

-- The model for a stage: `<id>_Baby` / `<id>_Juvenile`, falling back to the adult.
local function templateFor(speciesId: string, stage: string): Model?
	local templates = ReplicatedStorage:FindFirstChild("CreatureModels")
	if templates == nil then
		return nil
	end
	local staged = if stage ~= "Adult" then templates:FindFirstChild(`{speciesId}_{stage}`) else nil
	local template = staged or templates:FindFirstChild(speciesId)
	return if template and template:IsA("Model") then template else nil
end

-- Spins `speciesId` at `stage` in a new ViewportFrame under `parent` (centered on
-- `placement.position`); nil when its model isn't imported.
function CreatureViewport.create(
	parent: Instance,
	speciesId: string,
	stage: string,
	finish: string,
	mutation: string?,
	placement: Placement
): ViewportFrame?
	local template = templateFor(speciesId, stage)
	if template == nil then
		return nil
	end
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = placement.size
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = placement.position
	frame.ZIndex = placement.zIndex or 21
	if placement.maxSize then
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = placement.maxSize
		limit.Parent = frame
	end
	frame.Parent = parent
	local model = template:Clone()
	-- Show the finish that actually hatched; without one, an ultra-rare's rarity tint
	if not FinishLooks.apply(model, finish) then
		local creature = Config.CreaturesById[speciesId]
		if creature then
			local tint = RarityLooks.tintFor(speciesId, creature.rarity)
			if tint then
				RarityLooks.tint(model, tint)
			end
		end
	end
	-- Then its mutation over that (Shared/MutationLooks): its skin, if Studio has it
	local mutated = MutationLooks.apply(model, mutation, finish, template.Name)
	local look = MutationLooks.get(mutation)
	local iridescent = mutated and look ~= nil and look.iridescent == true
	local parts: { BasePart } = {}
	local appearances: { SurfaceAppearance }? = nil
	if model:GetAttribute("SkinSheen") then
		appearances = {}
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- A viewport has nothing to reflect, so reflectance only washes colors out
			descendant.Reflectance = 0
			table.insert(parts, descendant)
		elseif appearances and descendant:IsA("SurfaceAppearance") then
			table.insert(appearances, descendant)
		end
	end
	-- A viewport has one light and no sky. Its default light came from behind the
	-- model, so a solid finish (no texture to carry its shading) showed as a flat
	-- silhouette: the Galaxy Sylvanox was a purple shape (PC, 2026-10-01). A light
	-- from the side shades every flank as the model spins, whichever way the
	-- engine reads the direction, and a brighter ambient lifts the dark finishes.
	frame.Ambient = Color3.fromRGB(190, 190, 205)
	frame.LightColor = Color3.fromRGB(235, 235, 235)
	frame.LightDirection = Vector3.new(-1, -0.35, 0)
	model:PivotTo(CFrame.new())
	model.Parent = frame
	if finish == "Galaxy" then
		-- Its stars are particles in the world, which viewports don't draw
		starfield(parent, frame)
	end
	-- Spin around the model's own middle (its pivot can sit at its feet or off to one
	-- side), and put the camera just far enough back for it to fill the frame
	local boxCFrame, size = model:GetBoundingBox()
	local toCenter = CFrame.new(-boxCFrame.Position)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local fit = math.max(size.X, size.Z, size.Y * 1.3) / 2 / math.tan(math.rad(camera.FieldOfView / 2))
	camera.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.35, -fit * 1.15), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera
	task.spawn(function()
		local angle = 0
		local started = os.clock()
		while frame.Parent do
			angle += 0.03
			model:PivotTo(CFrame.Angles(0, angle, 0) * toCenter)
			if iridescent then
				-- Faster than in the world, so the sheen shows during the reveal
				MutationLooks.shimmer(parts, MutationLooks.sheen((os.clock() - started) * 4, 0), appearances)
			end
			task.wait()
		end
	end)
	return frame
end

return CreatureViewport

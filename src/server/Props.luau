--!strict
-- Imported 3D props (docs/ASSETS.md). Every world object is built from plain
-- parts first; when a matching model has been imported into ReplicatedStorage,
-- it is fitted over that part and the part turns invisible (it keeps its
-- collision, prompts and labels). Without imports the game still runs on blocks.
--
--   ReplicatedStorage.WorldProps.<Name>   reactor, pedestals, incubators, decor
--   ReplicatedStorage.EggModels.<BiomeId> per-biome eggs (EggModels.Egg = tinted fallback)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Props = {}

function Props.template(folderName: string, name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function prepare(model: Model, anchored: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

-- Squashes (or stretches) `model` vertically by `factor` about its bounding-box
-- center. Only parts upright in the box are resized; imported props are one or a
-- few upright MeshParts, so the mesh simply gets flatter or taller.
local function scaleHeight(model: Model, factor: number)
	local boxCFrame = model:GetBoundingBox()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local offset = boxCFrame:PointToObjectSpace(part.Position)
			if math.abs(part.CFrame.UpVector:Dot(boxCFrame.UpVector)) > 0.99 then
				part.Size = Vector3.new(part.Size.X, part.Size.Y * factor, part.Size.Z)
			end
			part.Position = boxCFrame:PointToWorldSpace(Vector3.new(offset.X, offset.Y * factor, offset.Z))
		end
	end
end

-- Scales `model` uniformly to fit inside `size` and stands its bounding box on
-- the bottom face of the box described by (cframe, size), centered. With
-- `stretch`, it fills the footprint and is then squashed to the box's height, for
-- flat things (pedestals, the cash pad) whose model is taller than their slot.
function Props.place(model: Model, cframe: CFrame, size: Vector3, stretch: boolean?)
	local extents = model:GetExtentsSize()
	local footprint = math.min(size.X / math.max(extents.X, 0.01), size.Z / math.max(extents.Z, 0.01))
	local ratio = if stretch then footprint else math.min(footprint, size.Y / math.max(extents.Y, 0.01))
	model:ScaleTo(model:GetScale() * ratio)
	if stretch then
		scaleHeight(model, size.Y / math.max(model:GetExtentsSize().Y, 0.01))
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivotToBox = model:GetPivot():ToObjectSpace(boxCFrame)
	local targetBox = cframe * CFrame.new(0, -size.Y / 2 + boxSize.Y / 2, 0)
	model:PivotTo(targetBox * pivotToBox:Inverse())
end

export type DressOptions = {
	size: Vector3?, -- box to fill (default: the part's size)
	cframe: CFrame?, -- center of that box, upright (default: the part's CFrame)
	keepVisible: boolean?, -- leave the placeholder part showing
	stretch: boolean?, -- fill the footprint, then flatten to the box height (see Props.place)
}

-- Fits WorldProps.<name> over `part` and hides the part. Returns the model, or
-- nil when no prop is imported (the part then stays as the placeholder).
function Props.dress(part: BasePart, name: string, options: DressOptions?): Model?
	local template = Props.template("WorldProps", name)
	if template == nil then
		return nil
	end
	local opts: DressOptions = options or {}
	local model = template:Clone()
	model.Name = `{name}Prop`
	prepare(model, true)
	Props.place(model, opts.cframe or part.CFrame, opts.size or part.Size, opts.stretch)
	model.Parent = part.Parent
	if not opts.keepVisible then
		part.Transparency = 1
	end
	part:SetAttribute("Dressed", true)
	return model
end

-- Places WorldProps.<name> standing on the ground at `cframe`, scaled to `height`.
function Props.spawn(name: string, cframe: CFrame, height: number, parent: Instance): Model?
	local template = Props.template("WorldProps", name)
	if template == nil then
		return nil
	end
	local model = template:Clone()
	prepare(model, true)
	local extents = model:GetExtentsSize()
	local scale = height / math.max(extents.Y, 0.01)
	Props.place(model, cframe * CFrame.new(0, height / 2, 0), extents * scale)
	model.Parent = parent
	return model
end

-- A biome's egg model, unanchored and unpositioned (callers weld or place it).
-- Uses EggModels.<BiomeId> as-is, or the generic EggModels.Egg tinted per biome.
function Props.egg(biomeId: string, height: number): Model?
	local ownDesign = Props.template("EggModels", biomeId)
	local template = ownDesign or Props.template("EggModels", "Egg")
	if template == nil then
		return nil
	end
	local model = template:Clone()
	model.Name = `{biomeId}EggModel`
	prepare(model, false)
	local size = model:GetExtentsSize()
	model:ScaleTo(model:GetScale() * (height / math.max(size.Y, 0.01)))
	if ownDesign == nil then
		local tint = Config.Eggs.eggColors[biomeId]
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = tint
			elseif descendant:IsA("SurfaceAppearance") then
				(descendant :: any).Color = tint
			end
		end
	end
	return model
end

-- Welds `model` to `anchor`, centered on it.
function Props.weldCentered(model: Model, anchor: BasePart)
	model:PivotTo(CFrame.new())
	local boxCFrame = model:GetBoundingBox()
	model:PivotTo(anchor.CFrame * boxCFrame:Inverse())
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchor
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	model.Parent = anchor
end

return Props

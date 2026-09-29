--!strict
-- A still "photo" of a creature: its model in a ViewportFrame, framed around its
-- middle from a three-quarter angle. Used by the Index cards. Returns nil when the
-- model hasn't been imported yet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreaturePhoto = {}

function CreaturePhoto.make(parent: Instance, speciesId: string, stage: string?): ViewportFrame?
	local templates = ReplicatedStorage:FindFirstChild("CreatureModels")
	if templates == nil then
		return nil
	end
	local template = (
		if stage and stage ~= "Adult" then templates:FindFirstChild(`{speciesId}_{stage}`) else nil
	) or templates:FindFirstChild(speciesId)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(170, 170, 180)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-1, -1.5, -0.8)
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Reflectance = 0
		end
	end
	model:PivotTo(CFrame.new())
	local boxCFrame, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-boxCFrame.Position)) -- center the body on the origin
	model.Parent = frame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local fit = math.max(size.X, size.Y, size.Z) / 2 / math.tan(math.rad(camera.FieldOfView / 2))
	local eye = Vector3.new(-0.6, 0.35, -1).Unit * fit * 1.25
	camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	return frame
end

return CreaturePhoto

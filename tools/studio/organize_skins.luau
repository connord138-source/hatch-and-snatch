-- Paste into Studio's Command Bar (View → Command Bar) after importing the mutation
-- skins (File → Import 3D, select every assets/skins/glb/*_Skins.glb made by
-- tools/mutations/run_all.py). Each imported <Model>_Skins holds one quad per
-- mutation; this files each quad's SurfaceAppearance (or its texture id, when the
-- importer made a plain textured MeshPart) under
--   ReplicatedStorage.MutationSkins.<Model>.<Mutation>
-- where MutationLooks finds it, and removes the imported model. Safe to run again:
-- a re-import replaces that model's skins. Then File → Save (Ctrl+S).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MUTATIONS = { "Albino", "Melanistic", "Piebald", "Chimera", "Iridescent" }

local root = ReplicatedStorage:FindFirstChild("MutationSkins")
if root == nil then
	root = Instance.new("Folder")
	root.Name = "MutationSkins"
	root.Parent = ReplicatedStorage
end

local function mutationOf(name)
	for _, mutation in MUTATIONS do
		if string.find(name, mutation, 1, true) then
			return mutation
		end
	end
	return nil
end

local models, skins = 0, 0
for _, model in workspace:GetChildren() do
	local modelName = model:IsA("Model") and string.match(model.Name, "^(.+)_Skins$")
	if not modelName then
		continue
	end
	local folder = root:FindFirstChild(modelName)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = modelName
		folder.Parent = root
	end
	for _, part in model:GetDescendants() do
		local mutation = part:IsA("MeshPart") and mutationOf(part.Name)
		if not mutation then
			continue
		end
		local old = folder:FindFirstChild(mutation)
		if old then
			old:Destroy()
		end
		local appearance = part:FindFirstChildWhichIsA("SurfaceAppearance")
		if appearance then
			appearance.Name = mutation
			appearance.MetalnessMap = "" -- skins are non-metallic
			appearance.Parent = folder
			skins += 1
		elseif part.TextureID ~= "" then
			local value = Instance.new("StringValue")
			value.Name = mutation
			value.Value = part.TextureID
			value.Parent = folder
			skins += 1
		end
	end
	model:Destroy()
	models += 1
end
print(`Filed {skins} skin(s) for {models} model(s) under ReplicatedStorage.MutationSkins.`)

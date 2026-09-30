--!strict
-- Moves the conveyor's eggs smoothly on this client. The server only updates their
-- positions a few times a second (for the buy prompts); both follow Belt's path
-- from each egg's SpawnedAt, so they agree. Presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Belt = require(ReplicatedStorage.Shared.Belt)

local BeltController = {}

function BeltController.start()
	local folder = Workspace:WaitForChild("ConveyorEggs")
	RunService.RenderStepped:Connect(function()
		local center = folder:GetAttribute("Center")
		if typeof(center) ~= "Vector3" then
			return
		end
		local now = Workspace:GetServerTimeNow()
		for _, egg in folder:GetChildren() do
			local spawnedAt = egg:GetAttribute("SpawnedAt")
			if egg:IsA("BasePart") and typeof(spawnedAt) == "number" then
				egg.CFrame = Belt.cframe(center, Belt.angle(now - spawnedAt))
			end
		end
	end)
end

return BeltController

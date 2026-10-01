--!strict
-- Server pushes (a base or vault locking with you inside, a locked zone) move your
-- character on your own client too, since the client owns its physics (Net.teleport).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportController = {}

function TeleportController.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Teleport") :: RemoteEvent
	remote.OnClientEvent:Connect(function(cframe: any)
		local character = Players.LocalPlayer.Character
		if typeof(cframe) ~= "CFrame" or character == nil then
			return
		end
		character:PivotTo(cframe)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

return TeleportController

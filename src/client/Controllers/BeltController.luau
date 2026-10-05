--!strict
-- Moves the conveyor's eggs smoothly on this client. The server only updates their
-- positions a few times a second (for the buy prompts); both follow Belt's path
-- from each egg's SpawnedAt, so they agree. Also runs the belt itself (Conveyor):
-- its cross-slats ride round at the eggs' speed so the belt reads as moving, and
-- its amber running lights chase the way it runs. Presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Belt = require(ReplicatedStorage.Shared.Belt)

local LIGHT_ON = Color3.fromRGB(255, 176, 60)
local LIGHT_OFF = Color3.fromRGB(110, 60, 20)
local CHASE_RATE = 5 -- light steps a second
local CHASE_GAP = 4 -- every 4th light is lit

local BeltController = {}

-- The parts in a streamed folder, kept current as they stream in and out
local function tracked(folder: Instance): { [BasePart]: number }
	local parts: { [BasePart]: number } = {}
	local function add(child: Instance)
		local index = child:GetAttribute("Index")
		if child:IsA("BasePart") and typeof(index) == "number" then
			parts[child] = index
		end
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			parts[child] = nil
		end
	end)
	return parts
end

local function runBelt()
	local world = Workspace:WaitForChild("World")
	local conveyor = world:WaitForChild("Conveyor", 30)
	if conveyor == nil then
		return
	end
	local slatFolder = conveyor:WaitForChild("BeltSlats", 10)
	local lightFolder = conveyor:WaitForChild("BeltLights", 10)
	if slatFolder == nil or lightFolder == nil then
		return
	end
	local slats = tracked(slatFolder)
	local lights = tracked(lightFolder)
	local lastStep = -1
	RunService.RenderStepped:Connect(function()
		local center = slatFolder:GetAttribute("Center")
		local count = slatFolder:GetAttribute("Count")
		if typeof(center) ~= "Vector3" or typeof(count) ~= "number" then
			return
		end
		local turn = Belt.ANGULAR_SPEED * Workspace:GetServerTimeNow()
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for slat, index in slats do
			table.insert(parts, slat)
			table.insert(cframes, Belt.slatCFrame(center, (index - 1) / count * 2 * math.pi + turn))
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		local step = math.floor(Workspace:GetServerTimeNow() * CHASE_RATE)
		if step ~= lastStep then
			lastStep = step
			for light, index in lights do
				light.Color = if (index - step) % CHASE_GAP == 0 then LIGHT_ON else LIGHT_OFF
			end
		end
	end)
end

function BeltController.start()
	task.spawn(runBelt)
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

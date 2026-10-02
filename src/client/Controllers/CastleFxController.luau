--!strict
-- Castle theme kits in motion (server CastleKits tags the pieces):
--   KitFloat    floating crystals, thunder-stones, rock shards and the big
--               crescent bob gently and turn (attributes FloatBase, FloatBob, FloatSpin)
--   KitSpin     the void portal turns about its face (SpinBase, SpinSpeed)
--   KitArc      lightning between the Storm Spire's tesla tips flickers and jumps
--   KitFlicker  the storm cloud's light flashes now and then
--   KitLight    every kit light: off beyond LIGHT_RANGE from the camera (a
--               themed base carries about a hundred), checked once a second
-- Only pieces near the camera are animated, so six themed bases stay cheap.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NEAR = 400 -- studs from the camera
local LIGHT_RANGE = 230 -- a neighbour's base still glows; the far side of the island doesn't

local CastleFxController = {}

local function collect(tag: string): { [Instance]: number }
	local set: { [Instance]: number } = {}
	for _, instance in CollectionService:GetTagged(tag) do
		set[instance] = math.random() * 100
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		set[instance] = math.random() * 100
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		set[instance] = nil
	end)
	return set
end

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Beam") and instance.Attachment0 then
		return instance.Attachment0.WorldPosition
	elseif instance:IsA("Light") and instance.Parent and instance.Parent:IsA("BasePart") then
		return instance.Parent.Position
	end
	return nil
end

local function near(instance: Instance, camera: Vector3): boolean
	local at = positionOf(instance)
	return at ~= nil and (at - camera).Magnitude < NEAR
end

local function pivot(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

function CastleFxController.start()
	local floats = collect("KitFloat")
	local spins = collect("KitSpin")
	local arcs = collect("KitArc")
	local flickers = collect("KitFlicker")
	local lights = collect("KitLight")
	local nextLights = 0
	local nextArc = 0
	local nextFlash = os.clock() + 3
	RunService.Heartbeat:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local eye = camera.CFrame.Position
		local t = os.clock()
		if t >= nextLights then
			nextLights = t + 1
			for instance in lights do
				if instance:IsA("Light") then
					local holder = instance.Parent
					if holder and holder:IsA("BasePart") then
						instance.Enabled = (holder.Position - eye).Magnitude < LIGHT_RANGE
					end
				end
			end
		end
		for instance, seed in floats do
			local base = instance:GetAttribute("FloatBase")
			if typeof(base) == "CFrame" and near(instance, eye) then
				local bob = instance:GetAttribute("FloatBob")
				local spin = instance:GetAttribute("FloatSpin")
				local lift = math.sin(t * 1.1 + seed) * (if typeof(bob) == "number" then bob else 0.6)
				local turn = (t + seed) * (if typeof(spin) == "number" then spin else 0.3)
				pivot(instance, base * CFrame.new(0, lift, 0) * CFrame.Angles(0, turn, 0))
			end
		end
		for instance, seed in spins do
			local base = instance:GetAttribute("SpinBase")
			if typeof(base) == "CFrame" and near(instance, eye) then
				local speed = instance:GetAttribute("SpinSpeed")
				pivot(
					instance,
					base
						* CFrame.Angles(0, 0, (t + seed) * (if typeof(speed) == "number" then speed else 0.5))
				)
			end
		end
		if t >= nextArc then
			-- Lightning jumps about ten times a second, and drops out now and then
			nextArc = t + 0.06 + math.random() * 0.08
			for instance in arcs do
				if instance:IsA("Beam") and near(instance, eye) then
					instance.Enabled = math.random() < 0.8
					instance.CurveSize0 = (math.random() - 0.5) * 8
					instance.CurveSize1 = (math.random() - 0.5) * 8
					local width = 0.25 + math.random() * 0.5
					instance.Width0 = width
					instance.Width1 = width * (0.5 + math.random())
				end
			end
		end
		for instance in flickers do
			if instance:IsA("PointLight") then
				if t >= nextFlash then
					instance.Brightness = 4
				else
					instance.Brightness = math.max(0, instance.Brightness - 0.35)
				end
			end
		end
		if t >= nextFlash then
			nextFlash = t + 2 + math.random() * 5
		end
	end)
end

return CastleFxController

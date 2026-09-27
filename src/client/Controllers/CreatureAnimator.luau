--!strict
-- Client-side procedural motion for creatures on pedestals: a slow bounding hop
-- in place with a little wander, tuned by growth stage (babies bouncy and quick,
-- adults heavy and slow). Visual only — the server's CFrame is the anchor point.
-- This is the placeholder for the real rigged bounding-run animation.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Tracked = {
	model: Model,
	base: CFrame,
	seed: number,
}

local STAGE_MOTION: { [string]: { period: number, height: number, wander: number } } = {
	Baby = { period = 0.55, height = 1.1, wander = 1.2 },
	Juvenile = { period = 0.75, height = 0.8, wander = 1.6 },
	Adult = { period = 1.0, height = 0.6, wander = 2.0 },
}
local MAX_DISTANCE = 160

local tracked: { [Model]: Tracked } = {}

local CreatureAnimator = {}

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	-- Wait a frame so the replicated pivot is final before we record it
	task.defer(function()
		if instance.Parent then
			tracked[instance] = { model = instance, base = instance:GetPivot(), seed = math.random() * 100 }
		end
	end)
end

local function untrack(instance: Instance)
	if instance:IsA("Model") then
		tracked[instance] = nil
	end
end

function CreatureAnimator.start()
	for _, instance in CollectionService:GetTagged("Creature") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("Creature"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Creature"):Connect(untrack)

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, info in tracked do
			if model.Parent == nil then
				tracked[model] = nil
				continue
			end
			if (info.base.Position - cameraPos).Magnitude > MAX_DISTANCE then
				continue
			end
			local stage = model:GetAttribute("Stage")
			local motion = STAGE_MOTION[if typeof(stage) == "string" then stage else "Baby"]
				or STAGE_MOTION.Baby

			-- Slow wander around the pedestal; creature faces where it's heading
			local wanderT = (t + info.seed) * 0.35
			local offset = Vector3.new(math.sin(wanderT), 0, math.sin(wanderT * 0.7 + 1.3)) * motion.wander
			local velocity = Vector3.new(math.cos(wanderT), 0, 0.7 * math.cos(wanderT * 0.7 + 1.3))

			-- Bounding hop: only the upper half of the sine, so it lands and pushes off
			local phase = ((t + info.seed) / motion.period) * math.pi
			local hop = math.max(0, math.sin(phase)) * motion.height

			local position = info.base.Position + offset + Vector3.new(0, hop, 0)
			local facing = if velocity.Magnitude > 0.01
				then position + velocity
				else position + info.base.LookVector
			model:PivotTo(CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z)))

			if CollectionService:HasTag(model, "Prismatic") then
				local color = Color3.fromHSV((t * 0.2 + info.seed) % 1, 0.8, 1)
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Color = color
					end
				end
			end
		end
	end)
end

return CreatureAnimator

--!strict
-- Client-side procedural motion for creatures on pedestals: a slow bounding hop
-- in place with a little wander, tuned by growth stage (babies bouncy and quick,
-- adults heavy and slow). Visual only — the server's CFrame is the anchor point.
-- Models rigged by tools/blender/rig_creature.py also get a bounding gait on
-- their named bones (front legs together, back legs together, half a stride
-- apart), spine flex, head bob and tail sway — no uploaded animations needed.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Tracked = {
	model: Model,
	base: CFrame,
	seed: number,
	bones: { [string]: Bone },
	rigged: boolean,
}

local STAGE_MOTION: { [string]: { period: number, height: number, wander: number } } = {
	Baby = { period = 0.55, height = 1.1, wander = 1.2 },
	Juvenile = { period = 0.75, height = 0.8, wander = 1.6 },
	Adult = { period = 1.0, height = 0.6, wander = 2.0 },
}
local MAX_DISTANCE = 160
local BONE_DISTANCE = 90 -- beyond this only the body hop runs
local RIGGED_HOP = 0.5 -- rigged legs do part of the work, so the body lifts less

-- Rig bones point along their local Y (Blender convention), so pitch is local X
-- and side-to-side sway is local Z.
local function pitch(angle: number): CFrame
	return CFrame.Angles(angle, 0, 0)
end
local function sway(angle: number): CFrame
	return CFrame.Angles(0, 0, angle)
end

local function collectBones(model: Model): { [string]: Bone }
	local bones: { [string]: Bone } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	return bones
end

-- `phase` is the hop phase in radians; one stride per hop, landing at phase 0.
local function poseBones(bones: { [string]: Bone }, phase: number)
	local stride = math.sin(phase)
	for _, side in { "L", "R" } do
		local front, back = bones[`LegF{side}_Upper`], bones[`LegB{side}_Upper`]
		if front then
			front.Transform = pitch(stride * 0.55)
		end
		if back then
			back.Transform = pitch(-stride * 0.5)
		end
		-- Knees fold while each pair swings forward (lifted), straighten to land
		local frontKnee, backKnee = bones[`LegF{side}_Lower`], bones[`LegB{side}_Lower`]
		if frontKnee then
			frontKnee.Transform = pitch(-math.max(0, math.cos(phase)) * 0.7)
		end
		if backKnee then
			backKnee.Transform = pitch(math.max(0, -math.cos(phase)) * 0.7)
		end
	end
	local flex = math.sin(phase * 2)
	if bones.Spine then
		bones.Spine.Transform = pitch(flex * 0.08)
	end
	if bones.Chest then
		bones.Chest.Transform = pitch(-flex * 0.06)
	end
	if bones.Neck then
		bones.Neck.Transform = pitch(-flex * 0.05)
	end
	if bones.Head then
		bones.Head.Transform = pitch(-flex * 0.08) -- keeps the eyes level while the body bounds
	end
	for i = 1, 3 do
		local tail = bones[`Tail{i}`]
		if tail then
			tail.Transform = sway(math.sin(phase - i * 0.7) * 0.18 * i)
				* pitch(math.cos(phase - i * 0.5) * 0.1)
		end
	end
end

local tracked: { [Model]: Tracked } = {}

local CreatureAnimator = {}

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	-- Wait a frame so the replicated pivot is final before we record it
	task.defer(function()
		if instance.Parent then
			local bones = collectBones(instance)
			tracked[instance] = {
				model = instance,
				base = instance:GetPivot(),
				seed = math.random() * 100,
				bones = bones,
				rigged = next(bones) ~= nil,
			}
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
			local distance = (info.base.Position - cameraPos).Magnitude
			if distance > MAX_DISTANCE then
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
			if info.rigged then
				hop *= RIGGED_HOP
				if distance <= BONE_DISTANCE then
					poseBones(info.bones, phase)
				end
			end

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

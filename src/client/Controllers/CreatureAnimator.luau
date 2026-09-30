--!strict
-- Client-side creature motion. Visual only; the server's CFrame is the anchor.
--
--  * On a pedestal a creature SITS: body tilted nose-up about its front feet, hind
--    legs folded down to the ground, breathing, looking around now and then, tail
--    swishing. No hopping in place.
--  * A walked creature (Walking attribute, FollowUserId) follows its owner's
--    character and runs with the slow bounding hop only while it's moving; when
--    it catches up it sits down beside them.
--
-- Models rigged by tools/blender/rig_creature.py pose their named bones (legs,
-- spine, neck, head, tail) for both, and CreatureGrounding keeps their feet on the
-- ground whatever the legs are doing; unrigged models tilt/hop the whole body.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureGrounding = require(script.Parent.Parent.CreatureGrounding)

type Tracked = {
	model: Model,
	base: CFrame,
	seed: number,
	bones: { [string]: Bone },
	rigged: boolean,
	rig: CreatureGrounding.Rig?, -- measured once the leg bones are in
	rigChecked: boolean,
	pivotToBox: CFrame,
	halfHeight: number,
	-- following state
	position: Vector3?,
	facing: Vector3,
	phase: number,
	moving: number, -- 0 = sitting .. 1 = running (smoothed)
	-- idle look-around
	lookYaw: number,
	lookTarget: number,
	nextLook: number,
	-- Galaxy finish: a tiny planet orbiting the creature
	planet: BasePart?,
	-- Level of detail: seconds since this creature was last updated
	sinceUpdate: number,
	parts: { BasePart }?, -- Prismatic recolor list, gathered once
}

local STAGE_MOTION: { [string]: { stride: number, height: number, speed: number } } = {
	Baby = { stride = 2.2, height = 1.0, speed = 18 },
	Juvenile = { stride = 3.2, height = 0.8, speed = 19 },
	Adult = { stride = 4.5, height = 0.6, speed = 20 },
}
local MAX_DISTANCE = 160
local BONE_DISTANCE = 90 -- beyond this bones stay put
local RIGGED_HOP = 0.5 -- rigged legs do part of the work, so the body lifts less
local FOLLOW_OFFSET = CFrame.new(4, 0, 4.5) -- beside and behind the owner
local SNAP_DISTANCE = 70 -- teleported owner: jump straight there
local TURNTABLE_SPEED = 2 * math.pi / 24 -- one slow turn every 24 s on a pedestal

-- Level of detail: six full bases can hold ~180 creatures, so only the ones near
-- the camera update every frame; farther ones update at 20 Hz, then 8 Hz.
local function updateInterval(distance: number): number
	if distance < 45 then
		return 0
	elseif distance < 90 then
		return 1 / 20
	end
	return 1 / 8
end

-- Rig bones point along their local Y (Blender convention), so pitch is local X,
-- side-to-side sway is local Z and a head turn is local Y.
local function pitch(angle: number): CFrame
	return CFrame.Angles(angle, 0, 0)
end
local function sway(angle: number): CFrame
	return CFrame.Angles(0, 0, angle)
end
local function yaw(angle: number): CFrame
	return CFrame.Angles(0, angle, 0)
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

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- One leg's bounding-run swing and knee bend at this point of the stride.
local function gait(front: boolean, phase: number, m: number): (number, number)
	local stride = math.sin(phase) * m
	if front then
		return stride * 0.55, -math.max(0, math.cos(phase)) * 0.7 * m
	end
	return -stride * 0.5, math.max(0, -math.cos(phase)) * 0.7 * m
end

-- Blends a sitting pose (moving = 0) with the bounding run (moving = 1). The sit's
-- leg angles come from CreatureGrounding, which also tilts the body and keeps the
-- feet down; the Hips aren't pitched, since that swung the front legs off the ground.
local function poseBones(info: Tracked, t: number)
	local bones = info.bones
	local m = info.moving
	local phase = info.phase
	local breath = math.sin(t * 1.6 + info.seed) * 0.03 * (1 - m)
	local rig = info.rig
	if rig then
		for _, leg in rig.legs do
			local swing, knee = gait(leg.front, phase, m)
			leg.upper.Transform = pitch(swing + leg.sitUpper * (1 - m))
			leg.lower.Transform = pitch(knee + leg.sitLower * (1 - m))
		end
	else
		-- Not every leg bone came in: run with what there is, stand straight when idle
		for _, key in { "FL", "FR", "BL", "BR" } do
			local swing, knee = gait(string.sub(key, 1, 1) == "F", phase, m)
			local upper, lower = bones[`Leg{key}_Upper`], bones[`Leg{key}_Lower`]
			if upper then
				upper.Transform = pitch(swing)
			end
			if lower then
				lower.Transform = pitch(knee)
			end
		end
	end
	local flex = math.sin(phase * 2) * m
	if bones.Spine then
		bones.Spine.Transform = pitch(flex * 0.08 + breath)
	end
	if bones.Chest then
		bones.Chest.Transform = pitch(-flex * 0.06 - breath)
	end
	if bones.Neck then
		bones.Neck.Transform = pitch(-flex * 0.05) * yaw(info.lookYaw * 0.5 * (1 - m))
	end
	if bones.Head then
		bones.Head.Transform = pitch(-flex * 0.08) * yaw(info.lookYaw * 0.5 * (1 - m))
	end
	-- Tail: lazy swish when sitting, bouncing sway when running
	for i = 1, 3 do
		local tail = bones[`Tail{i}`]
		if tail then
			local run = math.sin(phase - i * 0.7) * 0.18 * i
			local idle = math.sin(t * 1.3 + info.seed - i * 0.6) * 0.12 * i
			tail.Transform = sway(lerp(idle, run, m)) * pitch(math.cos(phase - i * 0.5) * 0.1 * m)
		end
	end
end

local tracked: { [Model]: Tracked } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local CreatureAnimator = {}

-- Grow-up moment: a burst of gold sparkles when a creature reaches its next stage
local function growBurst(model: Model)
	local grewAt = model:GetAttribute("GrewAt")
	local primary = model.PrimaryPart
	if typeof(grewAt) ~= "number" or primary == nil or Workspace:GetServerTimeNow() - grewAt > 4 then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = primary
	emitter:Emit(60)
	task.delay(2, function()
		emitter:Destroy()
	end)
end

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	-- Wait a frame so the replicated pivot is final before we record it
	task.defer(function()
		if instance.Parent == nil then
			return
		end
		growBurst(instance)
		local bones = collectBones(instance)
		local pivot = instance:GetPivot()
		local boxCFrame, boxSize = instance:GetBoundingBox()
		local seed = math.random() * 100
		local planet = instance:FindFirstChild("GalaxyPlanet")
		-- With StreamingEnabled a model's parts (and the bones inside them) can arrive
		-- after the model itself: pick up late bones and the Galaxy planet as they land
		instance.DescendantAdded:Connect(function(descendant)
			local info = tracked[instance]
			if info == nil then
				return
			end
			if descendant:IsA("Bone") then
				info.bones = collectBones(instance)
				info.rigged = true
				info.rigChecked = false -- measure again with the new bone
			elseif descendant.Name == "GalaxyPlanet" and descendant:IsA("BasePart") then
				info.planet = descendant
			end
			if descendant:IsA("BasePart") then
				info.parts = nil -- regather for the Prismatic recolor
			end
		end)
		tracked[instance] = {
			model = instance,
			base = pivot,
			seed = seed,
			bones = bones,
			rigged = next(bones) ~= nil,
			rig = nil,
			rigChecked = false,
			pivotToBox = pivot:ToObjectSpace(boxCFrame),
			halfHeight = boxSize.Y / 2,
			position = nil,
			facing = pivot.LookVector,
			phase = 0,
			moving = 0,
			lookYaw = 0,
			lookTarget = 0,
			nextLook = os.clock() + seed % 4,
			planet = if planet and planet:IsA("BasePart") then planet else nil,
			sinceUpdate = math.huge, -- place it on the first frame
		}
	end)
end

local function untrack(instance: Instance)
	if instance:IsA("Model") then
		tracked[instance] = nil
	end
end

local function ownerRoot(model: Model): BasePart?
	local userId = model:GetAttribute("FollowUserId")
	if typeof(userId) ~= "number" then
		return nil
	end
	local owner = Players:GetPlayerByUserId(userId)
	local character = owner and owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function groundY(position: Vector3, ignore: { Instance }): number?
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

-- Moves a walked creature toward its spot beside the owner. Returns the pivot.
local function follow(info: Tracked, dt: number, root: BasePart): CFrame
	local motion = STAGE_MOTION[info.model:GetAttribute("Stage") :: string] or STAGE_MOTION.Baby
	local target = (root.CFrame * FOLLOW_OFFSET).Position
	local current = info.position or target
	local flatDelta = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	local distance = flatDelta.Magnitude
	local speed = 0
	if distance > SNAP_DISTANCE then
		current = target
	elseif distance > 1.5 then
		speed = math.min(motion.speed, distance * 2.2)
		local step = math.min(distance, speed * dt)
		current += flatDelta.Unit * step
		info.facing = flatDelta.Unit
	elseif root.AssemblyLinearVelocity.Magnitude < 1 then
		-- Caught up: sit facing the same way as the owner
		local look = root.CFrame.LookVector
		info.facing = info.facing:Lerp(Vector3.new(look.X, 0, look.Z).Unit, math.min(1, dt * 3))
	end
	local characterModel = root.Parent :: Instance
	local ground = groundY(current, { info.model, characterModel }) or (root.Position.Y - 3)
	current = Vector3.new(current.X, ground, current.Z)
	info.position = current

	-- Stride-synced bounding: the phase advances with distance travelled
	info.moving = lerp(info.moving, if speed > 0.5 then 1 else 0, math.min(1, dt * 6))
	info.phase += (speed * dt / motion.stride) * math.pi
	local hop = math.max(0, math.sin(info.phase)) * motion.height * info.moving
	if info.rigged then
		hop *= RIGGED_HOP
	end
	local center = current + Vector3.new(0, info.halfHeight + hop, 0)
	local facing = if info.facing.Magnitude > 0.01 then info.facing else Vector3.zAxis
	local boxCFrame = CFrame.lookAt(center, center + facing)
	return boxCFrame * info.pivotToBox:Inverse()
end

function CreatureAnimator.start()
	for _, instance in CollectionService:GetTagged("Creature") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("Creature"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Creature"):Connect(untrack)

	RunService.RenderStepped:Connect(function(frameDt: number)
		local camera = Workspace.CurrentCamera
		local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, info in tracked do
			if model.Parent == nil then
				tracked[model] = nil
				continue
			end
			local root = if model:GetAttribute("Walking") then ownerRoot(model) else nil
			local reference = if root then root.Position else info.base.Position
			local distance = (reference - cameraPos).Magnitude
			info.sinceUpdate += frameDt
			if distance > MAX_DISTANCE or info.sinceUpdate < updateInterval(distance) then
				continue
			end
			-- Everything below advances by the time since this creature's last update
			local dt = math.min(info.sinceUpdate, 0.25)
			info.sinceUpdate = 0

			-- Idle look-around: pick a new direction every few seconds
			if t >= info.nextLook then
				info.lookTarget = (math.random() - 0.5) * 1.4
				info.nextLook = t + 2.5 + math.random() * 4
			end
			info.lookYaw = lerp(info.lookYaw, info.lookTarget, math.min(1, dt * 2.5))

			local pivot: CFrame
			if root then
				pivot = follow(info, dt, root)
			else
				-- Sitting on the pedestal. Unrigged models lean back a little to read as sitting.
				-- Slow display turntable: the creature turns around its own middle
				info.moving = 0
				local boxCFrame = info.base * info.pivotToBox
				local spin = CFrame.Angles(0, (t * TURNTABLE_SPEED + info.seed) % (2 * math.pi), 0)
				local turned = CFrame.new(boxCFrame.Position) * spin * boxCFrame.Rotation
				pivot = turned * info.pivotToBox:Inverse()
				if not info.rigged then
					local breath = math.sin(t * 1.6 + info.seed) * 0.03
					pivot *= CFrame.Angles(math.rad(-6) + breath * 0.3, 0, 0)
				end
			end
			if info.rigged then
				if not info.rigChecked then
					info.rigChecked = true
					local bodyPlan = model:GetAttribute("BodyPlan")
					info.rig = CreatureGrounding.build(
						model,
						info.bones,
						if typeof(bodyPlan) == "string" then bodyPlan else nil
					)
				end
				if distance <= BONE_DISTANCE then
					poseBones(info, t)
				end
				local rig = info.rig
				if rig then
					-- Sit tilt, then drop (or raise) the body until the lowest foot touches down
					local tilt = CreatureGrounding.tilt(rig, 1 - info.moving)
					local lift =
						math.clamp(CreatureGrounding.lift(rig, tilt), -info.halfHeight, info.halfHeight)
					pivot = pivot * CFrame.new(0, -lift, 0) * tilt
				end
			end
			model:PivotTo(pivot)
			local body = model.PrimaryPart
			if info.planet and body then
				-- Measured from the body each frame: the model may still have been
				-- streaming in when it was tracked, so its first bounding box can be wrong
				local size = body.Size
				local radius = math.max(size.X, size.Z) * 0.55 + 0.6
				local angle = t * 1.1 + info.seed
				local lift = size.Y * 0.2 + math.sin(angle * 2) * 0.2
				local offset = Vector3.new(math.cos(angle) * radius, lift, math.sin(angle) * radius)
				info.planet.CFrame = CFrame.new(body.Position + offset)
			end

			if CollectionService:HasTag(model, "Prismatic") then
				local color = Color3.fromHSV((t * 0.2 + info.seed) % 1, 0.8, 1)
				if info.parts == nil then
					local parts: { BasePart } = {}
					for _, part in model:GetDescendants() do
						if part:IsA("BasePart") then
							table.insert(parts, part)
						end
					end
					info.parts = parts
				end
				for _, part in info.parts :: { BasePart } do
					part.Color = color
				end
			end
		end
	end)
end

return CreatureAnimator

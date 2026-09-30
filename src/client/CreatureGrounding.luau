--!strict
-- Keeps rigged creatures standing on the ground while CreatureAnimator poses their
-- bones. Bending legs on its own leaves a creature hanging in the air, so this works
-- out where the feet (and folded hind knees) end up and how far the body has to drop.
-- It also builds the idle sit: the body tilts nose-up about the front feet, the hind
-- legs fold just enough to reach the ground and the front legs stay upright.
--
-- All of it is in the model's pivot space, which is rigid: it's measured once per
-- model and reused wherever the model moves. A posed bone's CFrame is its parent's
-- posed CFrame * bone.CFrame * bone.Transform, the same rule the engine uses.
local CreatureGrounding = {}

-- Nose-up sit tilt per body plan, in radians. Upright bodies already sit tall.
local SIT_TILT: { [string]: number } = {
	["upright-bandit"] = 0,
	hopper = 0,
	shelled = 0.1,
	["low-long"] = 0.16,
	["small-round"] = 0.2,
	["big-floppy"] = 0.2,
}
local DEFAULT_TILT = 0.28
local LEG_KEYS = { "FL", "FR", "BL", "BR" }

type Leg = {
	upper: Bone,
	lower: Bone,
	front: boolean,
	foot: Vector3, -- where the foot meets the ground, in the lower bone's space
	sitUpper: number, -- sit pose pitch for the upper and lower bone
	sitLower: number,
}

export type Rig = {
	legs: { Leg },
	parts: { [Instance]: CFrame }, -- pivot-space CFrame of each part a bone chain hangs from
	ground: number, -- pivot-space height of the ground under the bind pose
	pivotPoint: Vector3, -- between the front feet; the sit tilts about it
	tiltSign: number, -- 1 when the head points toward -Z (the rig's front), else -1
	tilt: number, -- full sit tilt in radians
}

local function pitch(angle: number): CFrame
	return CFrame.Angles(angle, 0, 0)
end

-- Pivot-space CFrame of `bone` with the current Transforms (or the bind pose).
local function posed(rig: Rig, bone: Bone, memo: { [Instance]: CFrame }, bind: boolean): CFrame
	local cached = memo[bone]
	if cached then
		return cached
	end
	local parent = bone.Parent
	local base = CFrame.identity
	if parent and parent:IsA("Bone") then
		base = posed(rig, parent, memo, bind)
	elseif parent then
		base = rig.parts[parent] or CFrame.identity
	end
	local cf = base * bone.CFrame
	if not bind then
		cf *= bone.Transform
	end
	memo[bone] = cf
	return cf
end

-- The nose-up sit tilt about the front feet, `amount` of the way (0..1).
function CreatureGrounding.tilt(rig: Rig, amount: number): CFrame
	if rig.tilt == 0 or amount <= 0 then
		return CFrame.identity
	end
	local p = rig.pivotPoint
	return CFrame.new(p) * pitch(rig.tilt * amount * rig.tiltSign) * CFrame.new(-p)
end

-- How far the lowest foot (or folded hind knee) sits above the ground in the current
-- pose after `tilt`. Negative means it's sunk in.
function CreatureGrounding.lift(rig: Rig, tilt: CFrame): number
	local memo = {}
	local lowest = math.huge
	for _, leg in rig.legs do
		local lower = posed(rig, leg.lower, memo, false)
		lowest = math.min(lowest, (tilt * (lower * leg.foot)).Y)
		if not leg.front then
			lowest = math.min(lowest, (tilt * lower.Position).Y)
		end
	end
	return lowest - rig.ground
end

local function footAt(rig: Rig, leg: Leg, tilt: CFrame): Vector3
	return tilt * (posed(rig, leg.lower, {}, false) * leg.foot)
end

-- Front leg: the upper pitch that keeps the foot under the shoulder once tilted.
local function solveFront(rig: Rig, leg: Leg, tilt: CFrame)
	local function lean(angle: number): number
		leg.upper.Transform = pitch(angle)
		local shoulder = tilt * posed(rig, leg.upper, {}, false).Position
		return math.abs(footAt(rig, leg, tilt).Z - shoulder.Z)
	end
	local best, bestLean = 0, lean(0)
	for step = -40, 40 do
		local angle = step * 0.02
		local value = lean(angle)
		if value < bestLean then
			best, bestLean = angle, value
		end
	end
	leg.sitUpper, leg.sitLower = best, 0
end

-- Hind leg: fold (knee forward) until the foot comes up to `floor`, where the
-- straightened front feet ended up.
local function solveBack(rig: Rig, leg: Leg, tilt: CFrame, floor: number)
	-- The shin bends back against the thigh; if the two bones' rolls disagree, their
	-- local pitch axes point opposite ways and the shin's sign flips
	local bindMemo = {}
	local upperAxis = posed(rig, leg.upper, bindMemo, true).RightVector
	local lowerAxis = posed(rig, leg.lower, bindMemo, true).RightVector
	local shin = if upperAxis:Dot(lowerAxis) >= 0 then 1 else -1
	local function fold(sign: number, amount: number)
		leg.upper.Transform = pitch(sign * amount)
		leg.lower.Transform = pitch(-2 * sign * shin * amount)
	end
	-- Which sign sends the knee forward (toward the head) depends on the bone's roll
	fold(1, 0)
	local kneeRest = (tilt * posed(rig, leg.lower, {}, false).Position).Z
	fold(1, 0.4)
	local kneeBent = (tilt * posed(rig, leg.lower, {}, false).Position).Z
	local forward = if (kneeBent - kneeRest) * rig.tiltSign < 0 then 1 else -1
	local function gap(amount: number): number
		fold(forward, amount)
		return footAt(rig, leg, tilt).Y - floor
	end
	local low, high = 0, 1.4
	if gap(low) >= 0 then
		high = 0
	elseif gap(high) < 0 then
		low = high
	else
		for _ = 1, 24 do
			local mid = (low + high) / 2
			if gap(mid) < 0 then
				low = mid
			else
				high = mid
			end
		end
	end
	leg.sitUpper, leg.sitLower = forward * high, -2 * forward * shin * high
end

-- Measures a rigged model (tools/blender/rig_creature.py bone names) and solves its
-- sit. Returns nil when a leg bone is missing; the animator then leaves the legs alone.
function CreatureGrounding.build(model: Model, bones: { [string]: Bone }, bodyPlan: string?): Rig?
	local pivot = model:GetPivot()
	local rig: Rig = {
		legs = {},
		parts = {},
		ground = math.huge,
		pivotPoint = Vector3.zero,
		tiltSign = 1,
		tilt = SIT_TILT[bodyPlan or ""] or DEFAULT_TILT,
	}
	-- The ground is the bottom of the visible mesh in the bind pose
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant.Transparency < 1
			and descendant.Name ~= "GalaxyPlanet"
		then
			local cf = pivot:ToObjectSpace(descendant.CFrame)
			local half = descendant.Size / 2
			for _, corner in
				{
					Vector3.new(1, 1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, 1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, -1, -1),
				}
			do
				rig.ground = math.min(rig.ground, (cf * (half * corner)).Y)
			end
		end
	end
	for _, bone in bones do
		local parent = bone.Parent
		if parent and parent:IsA("BasePart") then
			rig.parts[parent] = pivot:ToObjectSpace(parent.CFrame)
		end
	end
	if rig.ground == math.huge then
		return nil
	end

	local bind = {}
	local frontFeet = {}
	for _, key in LEG_KEYS do
		local upper: Bone?, lower: Bone? = bones[`Leg{key}_Upper`], bones[`Leg{key}_Lower`]
		if upper == nil or lower == nil then
			return nil
		end
		-- The rig's lower legs run straight down from the knee to the foot
		local knee = posed(rig, lower, bind, true)
		local foot = Vector3.new(knee.Position.X, rig.ground, knee.Position.Z)
		local isFront = string.sub(key, 1, 1) == "F"
		table.insert(rig.legs, {
			upper = upper,
			lower = lower,
			front = isFront,
			foot = knee:PointToObjectSpace(foot),
			sitUpper = 0,
			sitLower = 0,
		})
		if isFront then
			table.insert(frontFeet, foot)
		end
	end
	rig.pivotPoint = (frontFeet[1] + frontFeet[2]) / 2
	local head, tail = bones.Head, bones.Tail1
	if head and tail then
		local headZ = posed(rig, head, bind, true).Position.Z
		local tailZ = posed(rig, tail, bind, true).Position.Z
		rig.tiltSign = if headZ <= tailZ then 1 else -1
	end

	-- Solve the sit on a clean pose, then put the animator's pose back
	local saved: { [Bone]: CFrame } = {}
	for _, bone in bones do
		saved[bone] = bone.Transform
		bone.Transform = CFrame.identity
	end
	local tilt = CreatureGrounding.tilt(rig, 1)
	local floor = math.huge
	for _, leg in rig.legs do
		if leg.front then
			solveFront(rig, leg, tilt)
			leg.upper.Transform = pitch(leg.sitUpper)
			floor = math.min(floor, footAt(rig, leg, tilt).Y)
			leg.upper.Transform = CFrame.identity
		end
	end
	for _, leg in rig.legs do
		if not leg.front then
			solveBack(rig, leg, tilt, floor)
			leg.upper.Transform, leg.lower.Transform = CFrame.identity, CFrame.identity
		end
	end
	for bone, transform in saved do
		bone.Transform = transform
	end
	return rig
end

return CreatureGrounding

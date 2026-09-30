-- Tests src/client/CreatureGrounding.luau outside Roblox on toy quadrupeds built
-- like tools/blender/rig_creature.py makes them, with random bone rolls, some facing
-- +Z and some shelled. Run: bash tools/tests/run_grounding.sh (needs the luau CLI).

local function inst(className, props)
	props.ClassName = className
	props.IsA = function(self, name)
		if name == "BasePart" then return self.ClassName == "MeshPart" or self.ClassName == "Part" end
		return self.ClassName == name
	end
	return props
end

local function build(seed, plan, dir)
	dir = dir or 1
	math.randomseed(seed)
	local L, H, W = 1.0, 0.7, 0.4
	local hip, neck, headZ, tailZ = 0.55 * H, 0.78 * H, 0.82 * H, 0.55 * H
	local pivot = CFrame.new(5, 2, -3) * CFrame.Angles(0, 0.7, 0)
	local partLocal = CFrame.new(0, H / 2, 0)
	local part = inst("MeshPart", { Name = "Body", Size = Vector3.new(W, H, L), Transparency = 0, CFrame = pivot * partLocal })
	local bones, world = {}, {}
	local function bone(name, head, tail, parent)
		local y = (tail - head).Unit
		local roll = if math.random() < 0.5 then 1 else -1
		local x = Vector3.new(roll, 0, 0)
		x = (x - y * x:Dot(y)).Unit
		local z = x:Cross(y)
		local w = pivot * CFrame.fromMatrix(head, x, y, z)
		world[name] = w
		local parentWorld = if parent then world[parent] else part.CFrame
		local b = inst("Bone", { Name = name, Parent = if parent then bones[parent] else part, CFrame = parentWorld:Inverse() * w, Transform = CFrame.identity })
		bones[name] = b
	end
	local v = function(x, y, z) return Vector3.new(x, y, z * dir) end
	bone("Root", v(0, 0, 0), v(0, 0.15 * H, 0))
	bone("Hips", v(0, hip, 0.22 * L), v(0, hip * 1.03, 0.02 * L), "Root")
	bone("Spine", v(0, hip * 1.03, 0.02 * L), v(0, hip * 1.06, -0.18 * L), "Hips")
	bone("Chest", v(0, hip * 1.06, -0.18 * L), v(0, (hip + neck) / 2, -0.26 * L), "Spine")
	bone("Neck", v(0, (hip + neck) / 2, -0.26 * L), v(0, neck, -0.36 * L), "Chest")
	bone("Head", v(0, neck, -0.36 * L), v(0, headZ, -0.5 * L), "Neck")
	bone("Tail1", v(0, tailZ, 0.22 * L), v(0, tailZ * 1.02, 0.32 * L), "Hips")
	for _, key in { "FL", "FR", "BL", "BR" } do
		local fx = if key:sub(2, 2) == "L" then 0.12 else -0.12
		local fz = if key:sub(1, 1) == "F" then -0.25 * L else 0.25 * L
		local parent = if key:sub(1, 1) == "F" then "Chest" else "Hips"
		bone(`Leg{key}_Upper`, v(fx * 0.85, hip * 0.95, fz), v(fx, hip * 0.45, fz), parent)
		bone(`Leg{key}_Lower`, v(fx, hip * 0.45, fz), v(fx, 0.02 * H, fz), `Leg{key}_Upper`)
	end
	local model = { GetPivot = function() return pivot end, GetDescendants = function() return { part } end }
	return CreatureGrounding.build(model, bones, plan), bones, pivot
end

local function near(a, b, tol, what)
	assert(math.abs(a - b) <= tol, `{what}: {a} vs {b}`)
end

local failures = 0
for seed = 1, 40 do
	local plan = if seed % 4 == 0 then "shelled" else nil
	local ok, err = pcall(function()
		local dir = if seed % 3 == 0 then -1 else 1
		local rig, bones = build(seed, plan, dir)
		assert(rig, "build failed")
		assert(rig.tiltSign == dir, "tilt sign follows the head")
		near(rig.ground, 0, 1e-6, "ground")
		near(CreatureGrounding.lift(rig, CFrame.identity), 0, 1e-3, "bind lift")
		-- full sit
		local headBind = (rig.parts[bones.Root.Parent] * bones.Root.CFrame * bones.Hips.CFrame * bones.Spine.CFrame * bones.Chest.CFrame * bones.Neck.CFrame * bones.Head.CFrame).Position
		for _, leg in rig.legs do
			leg.upper.Transform = CFrame.Angles(leg.sitUpper, 0, 0)
			leg.lower.Transform = CFrame.Angles(leg.sitLower, 0, 0)
		end
		local tilt = CreatureGrounding.tilt(rig, 1)
		local lift = CreatureGrounding.lift(rig, tilt)
		local lift0 = lift
		for _, leg in rig.legs do
			local chain = {}
			local b = leg.lower
			while b.ClassName == "Bone" do table.insert(chain, 1, b); b = b.Parent end
			local cfw = rig.parts[b]
			for _, x in chain do cfw = cfw * x.CFrame * x.Transform end
			local foot = tilt * (cfw * leg.foot)
			near(foot.Y, lift0, 0.002, (if leg.front then "front" else "back") .. " foot height")
			if not leg.front then
				assert(math.abs(leg.sitUpper) > 0.05 or rig.tilt < 0.12, "hind leg should fold")
			end
		end
		local headSit = tilt * headBind
		assert(headSit.Y > headBind.Y, "head should rise in the sit")
	end)
	if not ok then failures += 1; print(`seed {seed}: {err}`) end
end
-- symmetric fold: both hind knees end at the same height and depth whatever the rolls
local worst = 0
for seed = 1, 40 do
	local rig = build(seed)
	for _, leg in rig.legs do
		leg.upper.Transform = CFrame.Angles(leg.sitUpper, 0, 0)
		leg.lower.Transform = CFrame.Angles(leg.sitLower, 0, 0)
	end
	local tilt = CreatureGrounding.tilt(rig, 1)
	local knees = {}
	for _, leg in rig.legs do
		if not leg.front then
			local chain, b = {}, leg.lower
			while b.ClassName == "Bone" do table.insert(chain, 1, b); b = b.Parent end
			local cfw = rig.parts[b]
			for _, x in chain do cfw = cfw * x.CFrame * x.Transform end
			table.insert(knees, tilt * cfw.Position)
		end
	end
	worst = math.max(worst, math.abs(knees[1].Y - knees[2].Y), math.abs(knees[1].Z - knees[2].Z))
end
assert(worst < 1e-6, `hind knees fold differently: {worst}`)
assert(failures == 0, `{failures} rig(s) failed`)
print("grounding: all rigs sit level")

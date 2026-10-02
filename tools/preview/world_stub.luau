-- Roblox world shims on top of tools/tests/stub.luau, enough to run the server's
-- world builders (Fortress, BaseDecor, Landmarks) in the luau CLI and dump every
-- part they make. tools/preview/render_parts.py draws the dump in Blender.
CFrame.lookAt = function(pos, target, up)
	up = up or Vector3.new(0, 1, 0)
	local back = (pos - target).Unit
	local right = up:Cross(back).Unit
	local realUp = back:Cross(right)
	return CFrame.fromMatrix(pos, right, realUp, back)
end

local Col = {}
Col.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t)
			return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	end
	return nil
end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, Col) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Col) end,
}

local function enumGroup(name)
	-- Cached so items compare equal, as Roblox enum items do
	return setmetatable({}, { __index = function(t, k) local item = { Name = k, EnumType = name }; rawset(t, k, item); return item end })
end
-- Random (deterministic LCG, enough for layout jitter)
Random = {
	new = function(seed)
		local state = math.floor(seed or 1) % 2147483647
		if state <= 0 then state = state + 2147483646 end
		local function step() state = (state * 48271) % 2147483647; return state / 2147483647 end
		return {
			NextNumber = function(_, a, b) a = a or 0; b = b or 1; return a + (b - a) * step() end,
			NextInteger = function(_, a, b) return a + math.floor(step() * (b - a + 1)) end,
		}
	end,
}
ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
-- Particle types (the preview ignores particles)
NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(v) return { Keypoints = v } end }
ColorSequence = {
	new = function(a, b)
		if a and a.R ~= nil then return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } } end
		return { Keypoints = a }
	end,
}
Enum = setmetatable({}, { __index = function(t, k) local group = enumGroup(k); rawset(t, k, group); return group end })

local DEFAULTS = {
	Part = { Shape = { Name = "Block" }, Size = Vector3.new(4, 1, 2), Color = Color3.fromRGB(163, 162, 165), Material = { Name = "Plastic" }, Transparency = 0, Reflectance = 0 },
	WedgePart = { Shape = { Name = "Wedge" }, Size = Vector3.new(4, 1, 2), Color = Color3.fromRGB(163, 162, 165), Material = { Name = "Plastic" }, Transparency = 0, Reflectance = 0 },
}
local Inst = {}
Inst.__index = function(self, k)
	local raw = rawget(self, "_props")[k]
	if raw ~= nil then return raw end
	if k == "Parent" then return rawget(self, "_parent") end
	if k == "Position" then local cf = rawget(self, "_props").CFrame; return cf and cf.p end
	if k == "Name" then return rawget(self, "ClassName") end
	if k == "FindFirstChild" then
		return function(me, name)
			for _, c in rawget(me, "_children") do if c.Name == name then return c end end
			return nil
		end
	end
	if k == "FindFirstChildWhichIsA" then
		return function(me, class)
			for _, c in rawget(me, "_children") do if c.ClassName == class or (class == "BasePart" and c.IsPart) then return c end end
			return nil
		end
	end
	if k == "FindFirstChildOfClass" then
		return function(me, class)
			for _, c in rawget(me, "_children") do if c.ClassName == class then return c end end
			return nil
		end
	end
	if k == "GetChildren" then return function(me) return table.clone(rawget(me, "_children")) end end
	if k == "IsA" then return function(me, class) return me.ClassName == class or (class == "BasePart" and me.IsPart == true) end end
	if k == "Destroy" then return function(me) me.Parent = nil end end
	if k == "SetAttribute" then return function(me, a, v) rawget(me, "_attrs")[a] = v end end
	if k == "GetAttribute" then return function(me, a) return rawget(me, "_attrs")[a] end end
	if k == "GetDescendants" then
		return function(me)
			local out = {}
			local function walk(n) for _, c in rawget(n, "_children") do table.insert(out, c); walk(c) end end
			walk(me)
			return out
		end
	end
	return nil
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local kids = rawget(old, "_children")
			for i, c in kids do if c == self then table.remove(kids, i) break end end
		end
		rawset(self, "_parent", v)
		if v then table.insert(rawget(v, "_children"), self) end
		return
	end
	rawget(self, "_props")[k] = v
end
local PARTS = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true }
Instance = {
	new = function(class)
		local props = {}
		for k, v in DEFAULTS[class] or {} do props[k] = v end
		local self = setmetatable({ ClassName = class, IsPart = PARTS[class] or false, _props = props, _children = {}, _attrs = {} }, Inst)
		if self.IsPart and props.CFrame == nil then props.CFrame = CFrame.identity end
		return self
	end,
}
Vector3.yAxis = Vector3.new(0, 1, 0)
UDim2 = { new = function(...) return { ... } end, fromScale = function(...) return { ... } end, fromOffset = function(...) return { ... } end }
local collection = { AddTag = function() end, RemoveTag = function() end, HasTag = function() return false end }
game = {
	GetService = function(_, name)
		return if name == "CollectionService" then collection else Instance.new(name)
	end,
}

-- One line per part: name|shape|size|position|right|up|back|color|material|transparency|light
function dumpParts(root)
	for _, d in root:GetDescendants() do
		if d.IsPart and (d.Transparency or 0) < 1 then
			local cf, s, c = d.CFrame, d.Size, d.Color
			local light = ""
			for _, child in rawget(d, "_children") do
				if child.ClassName == "PointLight" or child.ClassName == "Fire" then light = "1" end
			end
			print(string.format("P|%s|%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.3f,%.3f,%.3f|%s|%.2f|%s",
				d.Name, d.Shape and d.Shape.Name or "Block", s.X, s.Y, s.Z, cf.p.X, cf.p.Y, cf.p.Z,
				cf.r.x.X, cf.r.x.Y, cf.r.x.Z, cf.r.y.X, cf.r.y.Y, cf.r.y.Z, cf.r.z.X, cf.r.z.Y, cf.r.z.Z,
				c.R, c.G, c.B, d.Material and d.Material.Name or "Plastic", d.Transparency or 0, light))
		end
		-- Beams between two parts' attachments (the Storm kit's lightning): B|from|to
		if d.ClassName == "Beam" and d.Attachment0 and d.Attachment1 then
			local p0, p1 = d.Attachment0.Parent.CFrame.p, d.Attachment1.Parent.CFrame.p
			print(string.format("B|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f", p0.X, p0.Y, p0.Z, p1.X, p1.Y, p1.Z))
		end
		-- Particles (the preview scatters stand-ins for them): E|kind|position|box size|color|rate|lifetime|speed|accel|size
		if d.IsPart then
			for _, child in rawget(d, "_children") do
				if child.ClassName == "Fire" then
					local p, c = d.CFrame.p, child.Color or Color3.fromRGB(255, 140, 40)
					print(string.format("F|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.2f", p.X, p.Y, p.Z, c.R, c.G, c.B, child.Size or 3))
				end
				if child.ClassName == "ParticleEmitter" then
					local tex = tostring(child.Texture or "")
					local kind = if string.find(tex, "smoke") then "smoke" elseif string.find(tex, "fire") then "fire" else "sparkle"
					local keys = child.Color and child.Color.Keypoints
					local c = (keys and keys[1] and keys[1].Value) or Color3.new(1, 1, 1)
					local life = child.Lifetime and child.Lifetime.Max or 2
					local speed = child.Speed and child.Speed.Max or 1
					local acc = child.Acceleration or Vector3.new(0, 0, 0)
					local size = 0.4
					local sk = child.Size and child.Size.Keypoints
					if type(sk) == "table" then
						for _, k in sk do if type(k) == "table" and k.Value then size = math.max(size, k.Value) end end
					elseif type(sk) == "number" then
						size = sk
					end
					local p, s = d.CFrame.p, d.Size
					print(string.format("E|%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.2f|%.2f|%.2f|%.2f|%.2f",
						kind, p.X, p.Y, p.Z, s.X, s.Y, s.Z, c.R, c.G, c.B, child.Rate or 5, life, speed, acc.Y, size))
				end
			end
		end
		-- Lights anywhere, even on invisible anchors (theme kit lights): L|position|color|range
		if d.IsPart then
			for _, child in rawget(d, "_children") do
				if child.ClassName == "PointLight" then
					local p, c = d.CFrame.p, child.Color or Color3.new(1, 1, 1)
					print(string.format("L|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.2f", p.X, p.Y, p.Z, c.R, c.G, c.B, child.Range or 12))
				end
			end
		end
	end
	-- Imported models (props_stub.luau): R|name|mode|position|right|up|back|size|tint
	for _, r in PROP_PLACEMENTS or {} do
		-- A spawned piece may have been turned or moved since (it stands on its base)
		local cf = if r.model and r.mode == "height" then r.model:GetPivot() * CFrame.new(0, -r.height / 2, 0) else r.cframe
		local size = if r.mode == "box" then r.size else Vector3.new(r.height, r.height, r.height)
		local tint = r.model and r.model:GetAttribute("KitTint")
		local neon = r.model and r.model:GetAttribute("KitNeon")
		local solid = r.model and r.model:GetAttribute("KitSolid")
		local clear = r.model and r.model:GetAttribute("KitClear")
		print(string.format("R|%s|%s|%.3f,%.3f,%.3f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.3f,%.3f,%.3f|%s|%s|%s|%s",
			r.name, r.mode, cf.p.X, cf.p.Y, cf.p.Z, cf.r.x.X, cf.r.x.Y, cf.r.x.Z, cf.r.y.X, cf.r.y.Y, cf.r.y.Z,
			cf.r.z.X, cf.r.z.Y, cf.r.z.Z, size.X, size.Y, size.Z,
			if tint then string.format("%.3f,%.3f,%.3f", tint.R, tint.G, tint.B) else "",
			if neon then string.format("%.3f,%.3f,%.3f", neon.R, neon.G, neon.B) else "",
			if solid then string.format("%.3f,%.3f,%.3f", solid.R, solid.G, solid.B) else "",
			if clear then string.format("%.3f,%.3f,%.3f", clear.R, clear.G, clear.B) else ""))
	end
end
return true

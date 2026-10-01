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
	return setmetatable({}, { __index = function(_, k) return { Name = k, EnumType = name } end })
end
Enum = setmetatable({}, { __index = function(_, k) return enumGroup(k) end })

local DEFAULTS = {
	Part = { Shape = { Name = "Block" }, Size = Vector3.new(4, 1, 2), Color = Color3.fromRGB(163, 162, 165), Material = { Name = "Plastic" }, Transparency = 0 },
	WedgePart = { Shape = { Name = "Wedge" }, Size = Vector3.new(4, 1, 2), Color = Color3.fromRGB(163, 162, 165), Material = { Name = "Plastic" }, Transparency = 0 },
}
local Inst = {}
Inst.__index = function(self, k)
	local raw = rawget(self, "_props")[k]
	if raw ~= nil then return raw end
	if k == "Parent" then return rawget(self, "_parent") end
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
game = { GetService = function(_, name) return Instance.new(name) end }

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
	end
end
return true

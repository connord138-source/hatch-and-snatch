-- Minimal Vector3 and CFrame for running pure pose math in the luau CLI (tools/tests).
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
	if k == "Cross" then return function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Lerp" then return function(a, b, t) return Vector3.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
	return nil
end
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
Vector3 = { new = vec, zero = vec(0, 0, 0) }

-- CFrame: rotation columns (right, up, back) + position
local C = {}
local function cf(p, r) return setmetatable({ p = p, r = r }, C) end
local function rotv(r, v) -- r = {x=right,y=up,z=back} columns
	return r.x * v.X + r.y * v.Y + r.z * v.Z
end
C.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X end
	if k == "Y" then return c.p.Y end
	if k == "Z" then return c.p.Z end
	if k == "RightVector" then return c.r.x end
	if k == "UpVector" then return c.r.y end
	if k == "LookVector" then return -c.r.z end
	if k == "Inverse" then
		return function(self)
			local r = self.r
			-- transpose
			local rt = {
				x = vec(r.x.X, r.y.X, r.z.X),
				y = vec(r.x.Y, r.y.Y, r.z.Y),
				z = vec(r.x.Z, r.y.Z, r.z.Z),
			}
			return cf(-rotv(rt, self.p), rt)
		end
	end
	if k == "PointToObjectSpace" then return function(self, v) return self:Inverse() * v end end
	if k == "VectorToWorldSpace" then return function(self, v) return rotv(self.r, v) end end
	if k == "PointToWorldSpace" then return function(self, v) return self * v end end
	if k == "ToObjectSpace" then return function(self, o) return self:Inverse() * o end end
	return nil
end
C.__mul = function(a, b)
	if getmetatable(b) == V then return a.p + rotv(a.r, b) end
	return cf(a.p + rotv(a.r, b.p), { x = rotv(a.r, b.r.x), y = rotv(a.r, b.r.y), z = rotv(a.r, b.r.z) })
end
local I = { x = vec(1, 0, 0), y = vec(0, 1, 0), z = vec(0, 0, 1) }
CFrame = {}
CFrame.identity = cf(vec(0, 0, 0), I)
CFrame.new = function(a, b, c)
	if a == nil then return CFrame.identity end
	if type(a) == "number" then return cf(vec(a, b, c), I) end
	return cf(a, I)
end
local function rx(t) local c, s = math.cos(t), math.sin(t); return cf(vec(0,0,0), { x = vec(1,0,0), y = vec(0,c,s), z = vec(0,-s,c) }) end
local function ry(t) local c, s = math.cos(t), math.sin(t); return cf(vec(0,0,0), { x = vec(c,0,-s), y = vec(0,1,0), z = vec(s,0,c) }) end
local function rz(t) local c, s = math.cos(t), math.sin(t); return cf(vec(0,0,0), { x = vec(c,s,0), y = vec(-s,c,0), z = vec(0,0,1) }) end
CFrame.Angles = function(x, y, z) return rx(x) * ry(y) * rz(z) end
CFrame.fromMatrix = function(p, right, up, back) return cf(p, { x = right, y = up, z = back or right:Cross(up) }) end
return true

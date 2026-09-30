-- Roblox globals the Config modules touch at load time, for the plain luau CLI.
Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}
Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}
Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, item)
				return `{group}.{item}`
			end,
		})
	end,
})

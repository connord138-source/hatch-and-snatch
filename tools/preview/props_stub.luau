-- Preview stand-in for src/server/Props.luau: instead of cloning WorldProps models,
-- records where each one goes (PROP_PLACEMENTS) so render_parts.py can drop the
-- real GLB there. AVAILABLE_PROPS (set by the runner) maps the models on disk to
-- their extents, so a stand-in has the real proportions (and code that turns a
-- piece by its shape turns it here too); any other name returns nil, like a model
-- not imported yet.
PROP_PLACEMENTS = PROP_PLACEMENTS or {}
local function fake(name, cframe, size)
	local m = Instance.new("Model")
	m.Name = name
	local box = cframe
	m.GetBoundingBox = function() return box, size end
	m.GetPivot = function() return box end
	m.PivotTo = function(_, cf) box = cf end
	m.GetExtentsSize = function() return size end
	m.Clone = function() return fake(name, cframe, size) end
	m.ScaleTo = function() end
	m.GetScale = function() return 1 end
	return m
end
PreviewProps = {
	template = function(_, name)
		local ext = AVAILABLE_PROPS and AVAILABLE_PROPS[name]
		if ext then
			return fake(name, CFrame.identity, if type(ext) == "table" then ext else Vector3.new(1, 1, 1))
		end
		return nil
	end,
	spawn = function(name, cframe, height, parent)
		local ext = AVAILABLE_PROPS and AVAILABLE_PROPS[name]
		if not ext then
			return nil
		end
		local size = if type(ext) == "table" then ext * (height / ext.Y) else Vector3.new(height * 0.6, height, height * 0.6)
		local m = fake(name, cframe * CFrame.new(0, height / 2, 0), size)
		table.insert(PROP_PLACEMENTS, { name = name, cframe = cframe, height = height, mode = "height", model = m })
		m.Parent = parent
		return m
	end,
	place = function(model, cframe, size)
		table.insert(PROP_PLACEMENTS, { name = model.Name, cframe = cframe, size = size, mode = "box", model = model })
	end,
	reskin = function() end,
	dress = function() return nil end,
}
return true

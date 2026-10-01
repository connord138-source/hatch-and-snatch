--!strict
-- Rainbow castle designs (Config.CastleDesigns): every part the server tagged
-- "Rainbow" (roofs, banners, the glow on lasers, vault doors and crystals) cycles
-- through the colors, offset by where it stands so the colors roll across the base.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RainbowController = {}

local parts: { [BasePart]: number } = {} -- part -> hue offset

local function track(instance: Instance)
	if instance:IsA("BasePart") then
		local at = instance.Position
		parts[instance] = ((at.X + at.Z) * 0.004) % 1
	end
end

function RainbowController.start()
	for _, instance in CollectionService:GetTagged("Rainbow") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("Rainbow"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Rainbow"):Connect(function(instance)
		if instance:IsA("BasePart") then
			parts[instance] = nil
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 1 / 15 then
			return
		end
		since = 0
		local t = os.clock() * 0.12
		for part, offset in parts do
			part.Color = Color3.fromHSV((t + offset) % 1, 0.7, 1)
		end
	end)
end

return RainbowController

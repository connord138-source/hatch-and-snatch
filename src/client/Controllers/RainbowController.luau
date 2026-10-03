--!strict
-- Rainbow castle designs (Config.CastleDesigns): every part the server tagged
-- "Rainbow" (roofs, banners, the glow on lasers, vault doors and crystals) cycles
-- through the colors, offset by where it stands so the colors roll across the base.
-- Parts tagged "Iridescent" (the Diamond stone's textured walls, Config.Materials)
-- get the same treatment much fainter and slower: a pastel sheen drifting over the
-- texture, like an iridescent creature's skin (owner, 2026-10-02: "that iridescent
-- hue subtle color shift").
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local RainbowController = {}

local SHEEN_SATURATION = 0.12 -- how strongly the sheen tints the texture
local SHEEN_SPEED = 0.04 -- hue cycles per second (a full turn in 25 s)
local SHEEN_RANGE = 320 -- castles farther than this from the camera skip their updates

local parts: { [BasePart]: number } = {} -- part -> hue offset
local sheen: { [BasePart]: number } = {}

local function follow(tag: string, list: { [BasePart]: number }, offset: (Vector3) -> number)
	local function track(instance: Instance)
		if instance:IsA("BasePart") then
			list[instance] = offset(instance.Position) % 1
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		if instance:IsA("BasePart") then
			list[instance] = nil
		end
	end)
end

function RainbowController.start()
	follow("Rainbow", parts, function(at)
		return (at.X + at.Z) * 0.004
	end)
	-- Rolls diagonally across the walls and up the towers
	follow("Iridescent", sheen, function(at)
		return (at.X - at.Z) * 0.006 + at.Y * 0.012
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
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local s = os.clock() * SHEEN_SPEED
		for part, offset in sheen do
			if (part.Position - eye).Magnitude < SHEEN_RANGE then
				-- at the material's own brightness, as the server colored it
				local material = Config.Materials[part.MaterialVariant]
				local value = if material then material.brightness else 1
				part.Color = Color3.fromHSV((s + offset) % 1, SHEEN_SATURATION, value)
			end
		end
	end)
end

return RainbowController

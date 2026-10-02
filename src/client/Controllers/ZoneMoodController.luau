--!strict
-- What a zone's weather feels like from inside it. While the player stands in a
-- zone whose folder has a Mood attribute (the storm over Storm Peaks), the view
-- darkens, loses color and hazes over, and rain falls thick around the camera;
-- it all clears on the way out. Presentation only: WorldService sets the
-- attributes and SetPieces.stormSky builds the storm everyone sees.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ZoneShape = require(game:GetService("ReplicatedStorage").Shared.ZoneShape)

type Look = { [string]: any }
type Mood = { grade: Look, atmosphere: Look, rain: number }

local MOODS: { [string]: Mood } = {
	storm = {
		grade = {
			Brightness = -0.06,
			Contrast = 0.12,
			Saturation = -0.35,
			TintColor = Color3.fromRGB(212, 222, 245),
		},
		atmosphere = { Density = 0.42, Haze = 2.4, Glare = 0, Color = Color3.fromRGB(150, 158, 172) },
		rain = 800, -- drops per second around the camera
	},
}
local CLEAR: Look = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }
local FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine)

local ZoneMoodController = {}

-- Rain streaks falling from a patch of sky that follows the camera (off until a mood turns it on).
local function rainAroundCamera(): ParticleEmitter
	local sky = Instance.new("Part")
	sky.Name = "LocalRain"
	sky.Anchored = true
	sky.CanCollide = false
	sky.CanQuery = false
	sky.CanTouch = false
	sky.Transparency = 1
	sky.Size = Vector3.new(60, 1, 60)
	sky.Parent = Workspace
	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drops.Shape = Enum.ParticleEmitterShape.Box
	drops.EmissionDirection = Enum.NormalId.Bottom
	drops.Rate = 0
	drops.Lifetime = NumberRange.new(0.45, 0.55)
	drops.Speed = NumberRange.new(55, 65)
	drops.Size = NumberSequence.new(0.5)
	drops.Squash = NumberSequence.new(2.5) -- thin and tall: a streak
	drops.Transparency = NumberSequence.new(0.35)
	drops.Color = ColorSequence.new(Color3.fromRGB(205, 215, 235))
	drops.LightEmission = 0.2
	drops.Parent = sky
	RunService.RenderStepped:Connect(function()
		if drops.Rate > 0 then
			sky.CFrame = CFrame.new(Workspace.CurrentCamera.CFrame.Position + Vector3.new(0, 26, 0))
		end
	end)
	return drops
end

function ZoneMoodController.start()
	local decor = Workspace:WaitForChild("World"):WaitForChild("Decor", 60)
	if decor == nil then
		return
	end
	local zones: { Instance } = {}
	local function track(child: Instance)
		if child:GetAttribute("Mood") ~= nil then
			table.insert(zones, child)
		end
	end
	for _, child in decor:GetChildren() do
		track(child)
	end
	decor.ChildAdded:Connect(track)

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "ZoneMood"
	grade.Parent = Lighting
	local drops = rainAroundCamera()
	local found = Lighting:FindFirstChild("IslandAtmosphere") -- WorldService's (not a template leftover)
	local atmosphere = if found and found:IsA("Atmosphere") then found else nil
	local clearAtmosphere: Look? = if atmosphere
		then {
			Density = atmosphere.Density,
			Haze = atmosphere.Haze,
			Glare = atmosphere.Glare,
			Color = atmosphere.Color,
		}
		else nil

	local current: string? = nil
	while true do
		task.wait(0.5)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local inside: string? = nil
		if root and root:IsA("BasePart") then
			for _, zone in zones do
				local mood = zone:GetAttribute("Mood")
				local inner, outer = zone:GetAttribute("Inner"), zone:GetAttribute("Outer")
				local from, to = zone:GetAttribute("From"), zone:GetAttribute("To")
				if
					typeof(mood) == "string"
					and MOODS[mood]
					and typeof(inner) == "number"
					and typeof(outer) == "number"
					and typeof(from) == "number"
					and typeof(to) == "number"
					and ZoneShape.contains(
						{ inner = inner, outer = outer, from = from, to = to },
						root.Position
					)
				then
					inside = mood
				end
			end
		end
		if inside ~= current then
			current = inside
			local mood = if inside then MOODS[inside] else nil
			TweenService:Create(grade, FADE, if mood then mood.grade else CLEAR):Play()
			if atmosphere and clearAtmosphere then
				TweenService:Create(atmosphere, FADE, if mood then mood.atmosphere else clearAtmosphere)
					:Play()
			end
			drops.Rate = if mood then mood.rain else 0
		end
	end
end

return ZoneMoodController

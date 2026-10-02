--!strict
-- Moves the sun and the lighting through the day and night (Shared/DayNight):
-- a warm glow at dusk and dawn, then a moonlit blue night, bright enough to
-- play in, with stronger bloom so the castles' lights glow. Presentation only,
-- set locally on each client from the server's clock (the server's lighting in
-- WorldService is the daytime look).
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DayNight = require(game:GetService("ReplicatedStorage").Shared.DayNight)

local STEP = 0.1 -- seconds between updates (the sun moves at most a few minutes of clock each)
-- Tuned from the PC's night pass (2026-10-02): the dark designs were too dark,
-- the white ones blown out (with the template's extra bloom, now removed)
local NIGHT_AMBIENT = Color3.fromRGB(100, 110, 152)
local NIGHT_BRIGHTNESS = 1.8
local NIGHT_EXPOSURE = 0.15
local NIGHT_BLOOM = 0.7
local NIGHT_TINT = Color3.fromRGB(202, 214, 255)
local TWILIGHT_TINT = Color3.fromRGB(255, 214, 186)
local WHITE = Color3.new(1, 1, 1)

local DayNightController = {}

function DayNightController.start()
	local dayAmbient = Lighting.OutdoorAmbient
	local dayBrightness = Lighting.Brightness
	local dayExposure = Lighting.ExposureCompensation
	local bloom = Lighting:FindFirstChild("IslandBloom")
	local dayBloom = if bloom and bloom:IsA("BloomEffect") then bloom.Intensity else 0
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "DayNightGrade"
	grade.Parent = Lighting

	local nextStep = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextStep then
			return
		end
		nextStep = now + STEP
		local clock = DayNight.clock(Workspace:GetServerTimeNow())
		local night = DayNight.night(clock)
		local twilight = 1 - math.abs(2 * night - 1) -- peaks halfway through dusk and dawn
		Lighting.ClockTime = clock
		Lighting.OutdoorAmbient = dayAmbient:Lerp(NIGHT_AMBIENT, night)
		Lighting.Brightness = dayBrightness + (NIGHT_BRIGHTNESS - dayBrightness) * night
		Lighting.ExposureCompensation = dayExposure + (NIGHT_EXPOSURE - dayExposure) * night
		if bloom and bloom:IsA("BloomEffect") then
			bloom.Intensity = dayBloom + (NIGHT_BLOOM - dayBloom) * night
		end
		grade.TintColor = WHITE:Lerp(TWILIGHT_TINT, twilight * 0.6):Lerp(NIGHT_TINT, night)
		grade.Contrast = 0.06 * night
		grade.Saturation = -0.08 * night
	end)
end

return DayNightController

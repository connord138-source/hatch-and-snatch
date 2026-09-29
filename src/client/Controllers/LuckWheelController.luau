--!strict
-- Animates the physical Luck Wheel on every client. WheelService sets SpinFrom,
-- SpinTo, SpinDuration and SpinStart (server clock) on the disc; each client
-- eases the disc between them, so everyone nearby watches the same spin.
-- Presentation only; the prize was decided on the server.
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local TICK_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local SLICES = 6

local LuckWheelController = {}

local function tick(pitch: number)
	local sound = Instance.new("Sound")
	sound.SoundId = TICK_SOUND
	sound.Volume = 0.3
	sound.PlaybackSpeed = pitch
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

function LuckWheelController.start()
	local world = Workspace:WaitForChild("World")
	local wheel = world:WaitForChild("LuckWheel", 30)
	local disc = wheel and wheel:WaitForChild("WheelDisc", 10)
	if disc == nil or not disc:IsA("Model") then
		return
	end
	local model = disc :: Model
	local lastSlice = 0

	RunService.RenderStepped:Connect(function()
		local base = model:GetAttribute("BaseCFrame")
		local start = model:GetAttribute("SpinStart")
		local from = model:GetAttribute("SpinFrom")
		local to = model:GetAttribute("SpinTo")
		local duration = model:GetAttribute("SpinDuration")
		if
			typeof(base) ~= "CFrame"
			or typeof(start) ~= "number"
			or typeof(from) ~= "number"
			or typeof(to) ~= "number"
			or typeof(duration) ~= "number"
		then
			return
		end
		local elapsed = Workspace:GetServerTimeNow() - start
		if elapsed < 0 or elapsed > duration + 0.5 then
			return -- not spinning; the server's resting pivot shows
		end
		local t = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - t) ^ 4
		local angle = from + (to - from) * eased
		model:PivotTo(base * CFrame.Angles(0, 0, math.rad(angle)))
		local slice = math.floor(angle / (360 / SLICES))
		if slice ~= lastSlice then
			lastSlice = slice
			tick(1.4 + (1 - t) * 0.6)
		end
	end)
end

return LuckWheelController

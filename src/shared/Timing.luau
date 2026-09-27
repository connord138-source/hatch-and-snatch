--!strict
-- Game-time helpers shared by server and client. In Studio, hatch/growth
-- durations are divided by Debug.studioSpeed so the loop can be tested quickly.
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local isStudio = RunService:IsStudio()

local Timing = {}

function Timing.isStudio(): boolean
	return isStudio
end

-- Multiplier applied to hatch and growth speed (1 in live games).
function Timing.speed(): number
	return if isStudio then Config.Debug.studioSpeed else 1
end

-- Real-world seconds for a design-time duration.
function Timing.scaled(seconds: number): number
	return seconds / Timing.speed()
end

-- Unix time. Server uses os.time() for persistence; clients compare against
-- workspace:GetServerTimeNow(), which is synced to the same clock.
function Timing.now(): number
	return os.time()
end

return Timing

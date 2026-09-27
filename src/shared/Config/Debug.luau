--!strict
-- Studio-only testing aids. Every value here is ignored in live servers
-- (gated by RunService:IsStudio() at the call sites via shared/Timing).
return table.freeze({
	studioSpeed = 20, -- hatch + growth run this many times faster in Studio
	studioStartingCash = 1_000_000,
	studioUnlockAllBiomes = true,
	studioMoonEventIntervalSeconds = 120,
})

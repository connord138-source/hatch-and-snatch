--!strict
-- Studio-only testing aids. Every value here is ignored in live servers
-- (gated by RunService:IsStudio() at the call sites via shared/Timing).
-- To grant a test creature or start a moon event right away, see src/server/StudioDebug.luau.
return table.freeze({
	studioSpeed = 20, -- hatch + growth run this many times faster in Studio
	studioStartingCash = 1_000_000, -- topped up to this on every join
	studioUnlockAllBiomes = false, -- true skips rebirths and unlocks every biome's eggs
	studioMoonEventIntervalSeconds = 120,
	studioSkipNewPlayerProtection = true, -- so two Studio test players can steal right away
})

--!strict
-- Genetic mutations rolled at purchase (at most one per egg). The owner wants them
-- to be the rarest, most-wanted layer in the game (2026-10-01: "like Galaxy, other
-- people will want them; by far the most desirable yet rarest"): each is rarer
-- than a Galaxy finish, Iridescent is the rarest roll of all, and they multiply
-- earnings on top of the finish (an Iridescent Prismatic earns ×600). Their looks
-- are in Shared/MutationLooks. Chimera replaced Leucistic (2026-10-02), which read
-- as a paler Albino; old saves are moved over in DataService.
local Types = require(script.Parent.Types)

local Mutations: { Types.Mutation } = {
	{ id = "Albino", displayName = "Albino", chance = 1 / 8_000, earningsMultiplier = 10 },
	{ id = "Melanistic", displayName = "Melanistic", chance = 1 / 8_000, earningsMultiplier = 10 },
	{ id = "Chimera", displayName = "Chimera", chance = 1 / 12_000, earningsMultiplier = 12 },
	{ id = "Piebald", displayName = "Piebald", chance = 1 / 12_000, earningsMultiplier = 12 },
	{ id = "Iridescent", displayName = "Iridescent", chance = 1 / 100_000, earningsMultiplier = 40 },
}

return Mutations

--!strict
-- How long the hatch reveal takes, shared by the client's reveal (RevealController)
-- and the server, which times the world's light pillar and the server-wide news to
-- the moment the hatcher sees the creature. Owner, 2026-10-05: "a more involved
-- sequence when a legendary or higher is drawn".
--   normal  Common to Epic: the reel, then the creature
--   big     Legendary: a longer reel that creeps to a stop, a riser, a heartbeat
--           pause, then an impact with light rays and confetti
--   ultra   Mythic and up: all of that, plus color pulses and the odds line
--   junk    the Junk Egg's comedy creatures: a boing and a wobble
local Config = require(script.Parent.Config)

export type Tier = "normal" | "big" | "ultra" | "junk"

local RevealTiming = {
	REEL_SECONDS = 4.6,
	BIG_REEL_SECONDS = 6.4, -- the big reel creeps past the last few cards
	SETTLE_SECONDS = 0.35, -- a normal reel's pause before the reveal
	SUSPENSE_SECONDS = 1.35, -- a big reel's heartbeat pause before the reveal
}

function RevealTiming.tier(rarityId: string): Tier
	if rarityId == "Junk" then
		return "junk"
	end
	local rarity = Config.Rarities[rarityId :: any]
	local order = if rarity then rarity.order else 1
	if order >= 6 then
		return "ultra"
	elseif order >= 5 then
		return "big"
	end
	return "normal"
end

-- Seconds from the reveal starting to the creature appearing.
function RevealTiming.revealAt(rarityId: string): number
	local tier = RevealTiming.tier(rarityId)
	if tier == "big" or tier == "ultra" then
		return RevealTiming.BIG_REEL_SECONDS + RevealTiming.SUSPENSE_SECONDS
	end
	return RevealTiming.REEL_SECONDS + RevealTiming.SETTLE_SECONDS
end

return RevealTiming

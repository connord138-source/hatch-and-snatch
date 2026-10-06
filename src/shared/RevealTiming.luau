--!strict
-- How long the hatch reveal takes (RevealController), and which tier a rarity
-- gets. The server's light pillar and news wait for the hatcher's client to report
-- the moment (RevealImpact), since queued reveals start late. Owner, 2026-10-05:
-- "a more involved sequence when a legendary or higher is drawn".
--   normal  Common to Epic: the reel, then the creature
--   big     Legendary: a longer reel that creeps to a stop, a riser, a heartbeat
--           pause, then an impact with light rays and confetti
--   ultra   Mythic and up: all of that, plus color pulses and the odds line
--   junk    the Junk Egg's comedy creatures: a boing and a wobble
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Config.Types)

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

-- A rare finish or mutation is a bigger pull than most species (owner, 2026-10-06:
-- "I haven't noticed any flashy add-ons when a prismatic or other rarity skin is
-- rolled"; a Prismatic Common got the plain Common reel). So the whole roll sets the
-- tier: whichever is rarest of the species, the finish and the mutation. These
-- finishes lift it, lit in their own color (Prismatic cycles the rainbow), with
-- their own stinger from the sound pack, in the reveal and in the world's pillar.
export type FinishFlair = { tier: Tier, color: Color3, sound: string, rainbow: boolean? }
local FINISHES: { [string]: FinishFlair } = {
	Molten = { tier = "big", color = Color3.fromRGB(255, 120, 30), sound = "Legendary" },
	BloodMoon = { tier = "big", color = Color3.fromRGB(215, 25, 45), sound = "Mythic" },
	Galaxy = { tier = "ultra", color = Color3.fromRGB(150, 105, 255), sound = "Cosmic" },
	Prismatic = {
		tier = "ultra" :: Tier,
		color = Color3.fromRGB(255, 130, 230),
		sound = "Celestial",
		rainbow = true,
	},
}
RevealTiming.FINISHES = FINISHES
RevealTiming.MUTATION_SOUND = "Mythic" -- a mutation lifts the reveal to ultra

local RANK: { [string]: number } = { junk = 0, normal = 1, big = 2, ultra = 3 }

-- The tier of the whole roll: the highest of the species', its finish's and (any
-- mutation is ultra) its mutation's.
function RevealTiming.tierFor(rarityId: string, finishId: string?, mutationId: string?): Tier
	local tier: Tier = RevealTiming.tier(rarityId)
	local flair = if finishId then RevealTiming.FINISHES[finishId] else nil
	if flair and RANK[flair.tier] > RANK[tier] then
		tier = flair.tier
	end
	if mutationId then
		tier = "ultra"
	end
	return tier
end

-- A species' chance from an egg of `biomeId` (as the reveal's reel shows the egg:
-- moon-only species included), or 1 if it isn't in that egg.
function RevealTiming.speciesChance(biomeId: string, speciesId: string): number
	for _, entry in Config.Eggs.speciesOdds(biomeId, true) do
		if entry.id == speciesId and entry.chance > 0 then
			return entry.chance
		end
	end
	return 1
end

-- Which part of the roll was the rarest, and so leads the reveal's color, title and
-- stinger: "species", "finish" (one with flair) or "mutation". `speciesChance` is
-- the species' chance from its egg; a finish's is 1 in its oneIn.
function RevealTiming.lead(speciesChance: number, finishId: string?, mutationId: string?): string
	local best, lead = speciesChance, "species"
	local finish: Types.Finish? = nil
	for _, entry in Config.Finishes do
		if entry.id == finishId then
			finish = entry
		end
	end
	if finish and finish.oneIn and RevealTiming.FINISHES[finish.id] and 1 / finish.oneIn < best then
		best, lead = 1 / finish.oneIn, "finish"
	end
	local mutation = if mutationId then Config.MutationsById[mutationId] else nil
	if mutation and mutation.chance < best then
		lead = "mutation"
	end
	return lead
end

-- Seconds from the reveal starting to the creature appearing.
function RevealTiming.revealAt(rarityId: string): number
	local tier: Tier = RevealTiming.tier(rarityId)
	if tier == "big" or tier == "ultra" then
		return RevealTiming.BIG_REEL_SECONDS + RevealTiming.SUSPENSE_SECONDS
	end
	return RevealTiming.REEL_SECONDS + RevealTiming.SETTLE_SECONDS
end

return RevealTiming

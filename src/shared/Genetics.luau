--!strict
-- Words for what a creature was born with (owner, 2026-10-03: "show them what
-- pigment/alteration it's born with" and "a screen ... to view each creature and its
-- benefits/genetics"): its finish, its mutation and what each pays. The hatch reveal
-- and the creature details card (CreaturesMenu) both use it, so they always agree
-- with Config.Economy.cashPerSecond.
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)
local MutationLooks = require(script.Parent.MutationLooks)

local FINISH_COLOR = "#FFD25A"
local MUTED_COLOR = "#B4B4C3"

local finishById: { [string]: any } = {}
for _, finish in Config.Finishes do
	finishById[finish.id] = finish
end

local Genetics = {}

local function times(multiplier: number): string
	return `×{(string.format("%.2f", multiplier):gsub("%.?0+$", ""))}`
end
Genetics.times = times

-- RichText for the reveal: "✨ Gold finish ×1.5 · 🧬 Albino ×10", or the plain
-- "✨ No finish · 🧬 No mutation" when it has neither.
function Genetics.summary(finishId: string, mutationId: string?): string
	local finish = finishById[finishId]
	local finishText = if finish and finishId ~= "Normal"
		then `<font color="{FINISH_COLOR}">✨ {finish.displayName} finish {times(finish.earningsMultiplier)}</font>`
		else `<font color="{MUTED_COLOR}">✨ No finish</font>`
	local mutation = if mutationId then Config.MutationsById[mutationId] else nil
	local mutationText = if mutation and mutationId
		then `🧬 {MutationLooks.richName(
			mutationId,
			`{mutation.displayName} {times(mutation.earningsMultiplier)}`
		)}`
		else `<font color="{MUTED_COLOR}">🧬 No mutation</font>`
	return `{finishText}   ·   {mutationText}`
end

-- "Gold · ×1.5 earnings · 1 in 15" (or "Normal · no finish").
function Genetics.finishLine(finishId: string): string
	local finish = finishById[finishId]
	if finish == nil or finishId == "Normal" then
		return "Normal · no finish"
	end
	local odds = if finish.eventOnly
		then "Blood Moon only"
		elseif finish.oneIn then `1 in {Format.count(finish.oneIn)}`
		else ""
	return `{finish.displayName} · {times(finish.earningsMultiplier)} earnings · {odds}`
end

-- RichText: "Albino · ×10 earnings · 1 in 8,000" in its accent color (or "None").
function Genetics.mutationLine(mutationId: string?): string
	local mutation = if mutationId then Config.MutationsById[mutationId] else nil
	if mutation == nil or mutationId == nil then
		return "None"
	end
	return MutationLooks.richName(
		mutationId,
		`{mutation.displayName} · {times(mutation.earningsMultiplier)} earnings · 1 in {Format.count(
			1 / mutation.chance
		)}`
	)
end

export type Factor = { label: string, multiplier: number }

-- What one creature's earnings are made of, in the order Config.Economy.cashPerSecond
-- multiplies them: its rarity's base cash, then each multiplier. `biome` is the
-- biome it earns as (a Secret earns as the egg it hatched from).
function Genetics.factors(
	speciesId: string,
	stage: string,
	finishId: string,
	mutationId: string?,
	homegrown: boolean,
	biome: string
): (number, { Factor })
	local creature = Config.CreaturesById[speciesId]
	local rarity = Config.Rarities[creature.rarity]
	local list: { Factor } = {}
	local biomeInfo = Config.Biomes[biome]
	if biomeInfo then
		table.insert(list, { label = biomeInfo.displayName, multiplier = biomeInfo.earningsMultiplier })
	end
	local stageInfo = Config.Stages[stage :: any]
	if stageInfo then
		table.insert(list, { label = stage, multiplier = stageInfo.earningsMultiplier })
	end
	local finish = finishById[finishId]
	if finish and finishId ~= "Normal" then
		table.insert(list, { label = finish.displayName, multiplier = finish.earningsMultiplier })
	end
	local mutation = if mutationId then Config.MutationsById[mutationId] else nil
	if mutation then
		table.insert(list, { label = mutation.displayName, multiplier = mutation.earningsMultiplier })
	end
	if homegrown then
		table.insert(list, { label = "Homegrown", multiplier = 1 + Config.Economy.tunables.homegrownBonus })
	end
	return rarity.baseCashPerSec, list
end

return Genetics

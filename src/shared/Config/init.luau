--!strict
-- Single entry point: `local Config = require(ReplicatedStorage.Shared.Config)`
local Types = require(script.Types)
local Creatures = require(script.Creatures)
local Progression = require(script.Progression)
local BaseBuilds = require(script.BaseBuilds)
local CastleDesigns = require(script.CastleDesigns)

export type BiomeId = Types.BiomeId
export type RarityId = Types.RarityId
export type StageId = Types.StageId
export type Creature = Types.Creature
export type Finish = Types.Finish
export type MoonEvent = Types.MoonEvent
export type BaseTheme = Progression.BaseTheme
export type Achievement = Progression.Achievement
export type BaseBuild = BaseBuilds.Item
export type HidingSpot = BaseBuilds.HidingSpot
export type DesignProgress = CastleDesigns.Progress

local creaturesById: { [string]: Types.Creature } = {}
for _, creature in Creatures do
	creaturesById[creature.id] = creature
end

local Mutations = require(script.Mutations)
local mutationsById: { [string]: Types.Mutation } = {}
for _, mutation in Mutations do
	mutationsById[mutation.id] = mutation
end

return {
	Rarities = require(script.Rarities),
	Biomes = require(script.Biomes),
	Stages = require(script.Stages),
	Finishes = require(script.Finishes),
	Mutations = Mutations,
	MutationsById = mutationsById,
	MoonEvents = require(script.MoonEvents),
	Creatures = Creatures,
	CreaturesById = creaturesById,
	Economy = require(script.Economy),
	Eggs = require(script.Eggs),
	Progression = Progression,
	BaseBuilds = BaseBuilds,
	CastleDesigns = CastleDesigns,
	Zones = require(script.Zones),
	Monetization = require(script.Monetization),
	Codes = require(script.Codes),
	Daily = require(script.Daily),
	Debug = require(script.Debug),
	Materials = require(script.Materials),
}

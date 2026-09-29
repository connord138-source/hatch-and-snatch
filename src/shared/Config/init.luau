--!strict
-- Single entry point: `local Config = require(ReplicatedStorage.Shared.Config)`
local Types = require(script.Types)
local Creatures = require(script.Creatures)
local Progression = require(script.Progression)

export type BiomeId = Types.BiomeId
export type RarityId = Types.RarityId
export type StageId = Types.StageId
export type Creature = Types.Creature
export type Finish = Types.Finish
export type MoonEvent = Types.MoonEvent
export type BaseTheme = Progression.BaseTheme
export type Achievement = Progression.Achievement

local creaturesById: { [string]: Types.Creature } = {}
for _, creature in Creatures do
	creaturesById[creature.id] = creature
end

return {
	Rarities = require(script.Rarities),
	Biomes = require(script.Biomes),
	Stages = require(script.Stages),
	Finishes = require(script.Finishes),
	Mutations = require(script.Mutations),
	MoonEvents = require(script.MoonEvents),
	Creatures = Creatures,
	CreaturesById = creaturesById,
	Economy = require(script.Economy),
	Eggs = require(script.Eggs),
	Progression = Progression,
	Zones = require(script.Zones),
	Debug = require(script.Debug),
}

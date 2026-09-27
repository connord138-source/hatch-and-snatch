--!strict
-- Replicates each player's own state to their client (HUD) a few times per second,
-- only when something changed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local StateService = {}

local function snapshot(player: Player): { [string]: any }?
	local data = DataService.get(player)
	if data == nil then
		return nil
	end
	local incubators = {}
	for _, egg in data.incubators do
		table.insert(incubators, { biome = egg.biome, startedAt = egg.startedAt, hatchAt = egg.hatchAt })
	end
	local creatures = {}
	for uid, record in data.creatures do
		table.insert(creatures, {
			uid = uid,
			species = record.species,
			stage = record.stage,
			finish = record.finish,
			mutation = record.mutation,
			slot = record.slot,
			nextStageAt = CreatureService.nextStageAt(record),
		})
	end
	return {
		cash = data.cash,
		uncollected = data.uncollected,
		rate = EconomyService.rate(player),
		unlockedBiome = data.unlockedBiome,
		incubatorSlots = Config.Economy.tunables.incubatorSlots,
		incubators = incubators,
		creatures = creatures,
	}
end

function StateService.start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in DataService.takeDirty() do
				local state = snapshot(player)
				if state then
					Net.sendState(player, state)
				end
			end
		end
	end)
end

return StateService

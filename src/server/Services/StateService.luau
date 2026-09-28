--!strict
-- Replicates each player's own state to their client (HUD) a few times per second,
-- only when something changed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StealService = require(script.Parent.StealService)

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
			homegrown = record.homegrown,
			stolenFrom = record.stolenFrom,
			nextStageAt = CreatureService.nextStageAt(record),
		})
	end
	local lock = StealService.lockState(player)
	return {
		lockedUntil = if lock then lock.lockedUntil else 0,
		lockCooldownUntil = if lock then lock.cooldownUntil else 0,
		carrying = StealService.carryingName(player),
		protectedUntil = if Timing.isStudio() and Config.Debug.studioSkipNewPlayerProtection
			then 0
			else data.createdAt + Config.Economy.tunables.newPlayerProtectionSeconds,
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

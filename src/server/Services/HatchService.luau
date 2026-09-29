--!strict
-- Incubators: an egg bought off the conveyor hatches after its rarity's hatch
-- time. The species is rolled at purchase (hidden); finish + mutation are rolled
-- at hatch so an active moon event / luck boost applies at the moment it cracks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)

type PlayerData = DataService.PlayerData

local rng = Random.new()
local EMPTY_COLOR = Color3.fromRGB(200, 230, 255)

local HatchService = {}

local finishById: { [string]: Types.Finish } = {}
for _, finish in Config.Finishes do
	finishById[finish.id] = finish
end

local function refreshIncubators(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	for i, part in plot.incubators do
		local egg = data.incubators[i]
		if egg then
			part.Color = Config.Eggs.eggColors[egg.biome] or EMPTY_COLOR
			part.Transparency = 0.1
		else
			part.Color = EMPTY_COLOR
			part.Transparency = 0.4
		end
	end
end

function HatchService.hasFreeSlot(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and #data.incubators < Config.Economy.tunables.incubatorSlots
end

-- Puts a purchased egg into an incubator. Caller has already charged the player.
function HatchService.incubate(player: Player, biomeId: string): boolean
	local data = DataService.get(player)
	if data == nil or #data.incubators >= Config.Economy.tunables.incubatorSlots then
		return false
	end
	local species = Config.Eggs.rollSpecies(biomeId, rng, EventService.activeId() ~= nil)
	local rarity = Config.Rarities[Config.CreaturesById[species].rarity]
	local now = Timing.now()
	table.insert(data.incubators, {
		biome = biomeId,
		species = species,
		startedAt = now,
		hatchAt = now + Timing.scaled(rarity.hatchSeconds),
	})
	data.stats.eggsBought += 1
	refreshIncubators(player, data)
	DataService.markDirty(player)
	return true
end

local function hatch(player: Player, data: PlayerData, index: number)
	local egg = table.remove(data.incubators, index)
	if egg == nil then
		return
	end
	local finishId = Config.Economy.rollFinish(rng, EventService.activeId(), EventService.finishMultiplier())
	local mutation = Config.Economy.rollMutation(rng)
	local uid = CreatureService.add(player, {
		species = egg.species,
		stage = "Baby",
		stageStartedAt = Timing.now(),
		finish = finishId,
		mutation = mutation,
		homegrown = true,
	})
	data.stats.hatched += 1

	local creature = Config.CreaturesById[egg.species]
	local finish = finishById[finishId]
	local parts = {}
	if finishId ~= "Normal" then
		table.insert(parts, finish.displayName)
	end
	if mutation then
		table.insert(parts, mutation)
	end
	table.insert(parts, creature.displayName)
	local name = table.concat(parts, " ")
	local rare = finishId ~= "Normal" or Config.Rarities[creature.rarity].order >= 4
	Net.notify(player, `Hatched: {name} ({creature.rarity})!`, if rare then "rare" else "good")
	if uid and data.creatures[uid] and data.creatures[uid].slot == nil then
		Net.notify(player, "Your pedestals are full, so it went to storage (Creatures menu).", "bad")
	end
	if finish.announce ~= "none" or creature.rarity == "Mythic" then
		Net.announce(`{player.DisplayName} hatched a {name}!`, Config.Rarities[creature.rarity].color)
	end
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		local hatchedAny = false
		for i = #data.incubators, 1, -1 do
			if now >= data.incubators[i].hatchAt then
				hatch(player, data, i)
				hatchedAny = true
			end
		end
		if hatchedAny then
			refreshIncubators(player, data)
			DataService.markDirty(player)
		end
	end
end

function HatchService.start()
	-- Runs after PlotService assigned the plot (connect order in init.server)
	DataService.loaded:connect(refreshIncubators)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return HatchService

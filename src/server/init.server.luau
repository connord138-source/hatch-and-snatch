--!strict
-- Server bootstrap: validate config data (content mistakes fail loudly the moment
-- you press Play), then start services. Order matters: every service connects its
-- DataService.loaded handler in start(), and DataService starts last so those
-- handlers run in this order for each joining player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local function validateConfig(): { string }
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	local perBiome: { [string]: number } = {}

	for _, creature in Config.Creatures do
		if seen[creature.id] then
			table.insert(problems, `duplicate creature id: {creature.id}`)
		end
		seen[creature.id] = true
		if Config.Biomes[creature.biome] == nil then
			table.insert(problems, `{creature.id}: unknown biome {creature.biome}`)
		end
		if Config.Rarities[creature.rarity] == nil then
			table.insert(problems, `{creature.id}: unknown rarity {creature.rarity}`)
		end
		perBiome[creature.biome] = (perBiome[creature.biome] or 0) + 1
	end

	for biomeId in Config.Biomes do
		if (perBiome[biomeId] or 0) == 0 then
			table.insert(problems, `biome {biomeId} has no creatures`)
		end
	end

	local mutationTotal = 0
	for _, mutation in Config.Mutations do
		mutationTotal += mutation.chance
	end
	if mutationTotal >= 1 then
		table.insert(problems, `mutation chances sum to {mutationTotal} (must be < 1)`)
	end

	return problems
end

local problems = validateConfig()
if #problems > 0 then
	error("[HatchAndSnatch] Config invalid:\n  " .. table.concat(problems, "\n  "))
end

print(`[HatchAndSnatch] Config OK — {#Config.Creatures} creatures loaded`)

local Services = script.Services
local WorldService = require(Services.WorldService)
local EventService = require(Services.EventService)
local PlotService = require(Services.PlotService)
local CreatureService = require(Services.CreatureService)
local HatchService = require(Services.HatchService)
local EconomyService = require(Services.EconomyService)
local EggService = require(Services.EggService)
local StateService = require(Services.StateService)
local DataService = require(Services.DataService)

WorldService.start() -- builds plots before anyone is assigned one
EventService.start()
PlotService.start() -- loaded: assign plot + teleport
CreatureService.start() -- loaded: offline growth, spawn models on pedestals
HatchService.start() -- loaded: show incubator state (offline hatches happen on first tick)
EconomyService.start() -- loaded: leaderstats + offline earnings
EggService.start()
StateService.start()
DataService.start() -- last: fires loaded for players already in the server

print("[HatchAndSnatch] Server started")

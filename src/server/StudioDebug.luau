--!strict
-- Studio-only test hook, for looking at things you'd otherwise wait hours for.
-- During Play, switch the Command Bar to the Server view and run e.g.:
--
--   game.ServerStorage.StudioDebug:Invoke("grant", "Tidalotl", "Galaxy", "Adult")
--       -- gives every player that creature (finish and stage optional)
--   game.ServerStorage.StudioDebug:Invoke("event", "BloodMoon")
--       -- starts a moon event now
--   game.ServerStorage.StudioDebug:Invoke("essence", "MagmaRift", 50)
--       -- gives every player that biome's Essence (shrine testing)
--
-- It is a BindableFunction, so only server code and the Studio Command Bar can
-- reach it (never clients), and it is only created in Studio.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local CreatureService = require(script.Parent.Services.CreatureService)
local DataService = require(script.Parent.Services.DataService)
local EventService = require(script.Parent.Services.EventService)
local ZoneService = require(script.Parent.Services.ZoneService)

local StudioDebug = {}

local function grant(species: any, finish: any, stage: any): string
	if typeof(species) ~= "string" or Config.CreaturesById[species] == nil then
		return "unknown species"
	end
	local stageId = if typeof(stage) == "string" and Config.Stages[stage :: any] then stage else "Adult"
	local finishId = if typeof(finish) == "string" then finish else "Normal"
	local given = 0
	for player in DataService.loadedPlayers() do
		CreatureService.add(player, {
			species = species,
			stage = stageId,
			stageStartedAt = Timing.now(),
			finish = finishId,
			mutation = nil,
			homegrown = true,
		})
		given += 1
	end
	return `gave {finishId} {stageId} {species} to {given} player(s)`
end

local function startEvent(id: any): string
	for _, event in Config.MoonEvents do
		if event.id == id then
			task.spawn(EventService.run, event)
			return `started {event.displayName}`
		end
	end
	return "unknown event"
end

local function essence(biomeId: any, amount: any): string
	if typeof(biomeId) ~= "string" or Config.Zones.byBiome[biomeId] == nil then
		return "unknown biome"
	end
	local count = if typeof(amount) == "number" then amount else 50
	for player in DataService.loadedPlayers() do
		ZoneService.grantEssence(player, biomeId, count)
	end
	return `gave {count} {Config.Zones.byBiome[biomeId].essence}`
end

function StudioDebug.start()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "StudioDebug"
	hook.OnInvoke = function(action: any, ...: any): string
		if action == "grant" then
			return grant(...)
		elseif action == "event" then
			return startEvent(...)
		elseif action == "essence" then
			return essence(...)
		end
		return "actions: grant(species, finish?, stage?), event(id), essence(biome, amount?)"
	end
	hook.Parent = ServerStorage
end

return StudioDebug

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
--   game.ServerStorage.StudioDebug:Invoke("zone", "MagmaRift")
--       -- runs that zone's set-piece event now (bloom, clam, eruption, boulder, strike, meteor)
--   game.ServerStorage.StudioDebug:Invoke("pass", "VIP")
--       -- gives every player that game pass (DoubleCash, VIP, AutoCollect, ExtraNursery, LongerLock, OfflinePlus)
--   game.ServerStorage.StudioDebug:Invoke("product", "ServerLuck")
--       -- runs a developer product's effect for every player (ServerLuck, GrowthElixir, SkipHatch, CashSmall, CashLarge)
--   game.ServerStorage.StudioDebug:Invoke("product", "AdBoost")
--       -- the rewarded-ad reward (×2 cash for 15 min) without an ad
--   game.ServerStorage.StudioDebug:Invoke("perk", "premium")
--       -- toggles pretend Roblox Premium ("premium") or group membership ("group") for every player
--   game.ServerStorage.StudioDebug:Invoke("codes")
--       -- forgets which codes every player redeemed (Config.Codes), to test them again
--   game.ServerStorage.StudioDebug:Invoke("cash", 1e12)
--       -- gives every player that much cash (late-game upgrades cost billions)
--   game.ServerStorage.StudioDebug:Invoke("store")
--       -- moves every creature on a pedestal to storage (free pedestals for grants)
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
local EconomyService = require(script.Parent.Services.EconomyService)
local EventService = require(script.Parent.Services.EventService)
local MonetizationService = require(script.Parent.Services.MonetizationService)
local ZoneEventService = require(script.Parent.Services.ZoneEventService)
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

-- Moves every creature on a pedestal into storage, so fresh grants land on pedestals.
local function storeAll(): string
	local moved = 0
	for player, data in DataService.loadedPlayers() do
		for uid, record in data.creatures do
			if record.slot ~= nil then
				CreatureService.store(player, uid)
				if record.slot == nil then
					moved += 1
				end
			end
		end
	end
	return `moved {moved} creature(s) to storage`
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

local function zoneEvent(biomeId: any): string
	local zone = if typeof(biomeId) == "string" then ZoneEventService.zone(biomeId) else nil
	if zone == nil then
		return "unknown biome"
	end
	task.spawn(ZoneEventService.run, zone, true)
	return `running the {biomeId} event`
end

local function pass(key: any): string
	if typeof(key) ~= "string" or Config.Monetization.passesByKey[key] == nil then
		return "unknown pass"
	end
	for player in DataService.loadedPlayers() do
		MonetizationService.grantPass(player, key)
	end
	return `granted {key}`
end

local function perk(name: any): string
	if name ~= "premium" and name ~= "group" then
		return "perk is premium or group"
	end
	local on = false
	for player in DataService.loadedPlayers() do
		on = not (
			if name == "premium"
				then MonetizationService.isPremium(player)
				else MonetizationService.inGroup(player)
		)
		MonetizationService.setDebugPerk(player, name, on)
	end
	return `{name} {if on then "on" else "off"}`
end

local function cash(amount: any): string
	if typeof(amount) ~= "number" or amount <= 0 then
		return "cash needs a positive amount"
	end
	for player in DataService.loadedPlayers() do
		EconomyService.grant(player, amount, "Debug")
	end
	return `gave {amount}`
end

local function resetCodes(): string
	for player, data in DataService.loadedPlayers() do
		table.clear(data.codes)
		DataService.markDirty(player)
	end
	return "codes can be redeemed again"
end

local function product(key: any): string
	if typeof(key) ~= "string" or Config.Monetization.productsByKey[key] == nil then
		return "unknown product"
	end
	local count = 0
	for player in DataService.loadedPlayers() do
		if MonetizationService.grantProduct(player, key) then
			count += 1
		end
		if key == "ServerLuck" then
			break -- server-wide: once is enough
		end
	end
	return `ran {key} for {count} player(s)`
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
		elseif action == "store" then
			return storeAll()
		elseif action == "zone" then
			return zoneEvent(...)
		elseif action == "pass" then
			return pass(...)
		elseif action == "product" then
			return product(...)
		elseif action == "perk" then
			return perk(...)
		elseif action == "codes" then
			return resetCodes()
		elseif action == "cash" then
			return cash(...)
		end
		return "actions: grant(species, finish?, stage?), event(id), essence(biome, amount?), zone(biome), pass(key), product(key), perk(premium|group), codes(), cash(amount), store()"
	end
	hook.Parent = ServerStorage
end

return StudioDebug

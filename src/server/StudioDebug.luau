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
--       -- toggles pretend Roblox Premium ("premium"), group membership ("group") or a
--       -- region that restricts paid random items ("restricted") for every player
--   game.ServerStorage.StudioDebug:Invoke("codes")
--       -- forgets which codes every player redeemed (Config.Codes), to test them again
--   game.ServerStorage.StudioDebug:Invoke("cash", 1e12)
--       -- gives every player that much cash (late-game upgrades cost billions)
--   game.ServerStorage.StudioDebug:Invoke("guide")
--       -- restarts the first-session guide for every player (from "buy an egg")
--   game.ServerStorage.StudioDebug:Invoke("daily")
--       -- pretends a day passed: the login reward and new daily quests come back
--   game.ServerStorage.StudioDebug:Invoke("reveal", "Capybaron", "Galaxy")
--       -- plays the hatch reveal for that species (finish optional) without granting
--       -- anything (store screenshots)
--   game.ServerStorage.StudioDebug:Invoke("build")
--       -- maxes every player's base: level 5, both floors, all 4 vaults, security,
--       -- the 4 hiding spots and every decor and security item
--   game.ServerStorage.StudioDebug:Invoke("designs")
--       -- gives every player every Castle Designer option (Rainbow needs a rebirth)
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
local Net = require(script.Parent.Net)
local BaseService = require(script.Parent.Services.BaseService)
local CreatureService = require(script.Parent.Services.CreatureService)
local DailyService = require(script.Parent.Services.DailyService)
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
	if name ~= "premium" and name ~= "group" and name ~= "restricted" then
		return "perk is premium, group or restricted"
	end
	local on = false
	for player in DataService.loadedPlayers() do
		on = not (
			if name == "premium"
				then MonetizationService.isPremium(player)
				elseif name == "group" then MonetizationService.inGroup(player)
				else MonetizationService.paidRandomRestricted(player)
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

local function restartGuide(): string
	for player, data in DataService.loadedPlayers() do
		data.onboarding = 1
		DataService.markDirty(player)
	end
	return "guide restarted"
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
		elseif action == "guide" then
			return restartGuide()
		elseif action == "reveal" then
			local species, finish = ...
			local creature = if typeof(species) == "string" then Config.CreaturesById[species] else nil
			if not creature then
				return "unknown species"
			end
			for player in DataService.loadedPlayers() do
				Net.hatchReveal(player, {
					species = species,
					biome = creature.biome,
					finish = if typeof(finish) == "string" then finish else "Normal",
				})
			end
			return `revealing {species}`
		elseif action == "build" then
			local tunables = Config.Economy.tunables
			for player, data in DataService.loadedPlayers() do
				data.baseLevel = #tunables.baseLevels
				data.floors = #tunables.floors + 1
				data.vaults = #tunables.vaults
				data.security = #tunables.securityLevels
				data.hides = #Config.BaseBuilds.hidingSpots
				for _, item in Config.BaseBuilds.items do
					data.builds[item.id] = true
				end
				BaseService.apply(player, data)
				DataService.markDirty(player)
			end
			return "every base maxed: level 5, both floors, all vaults, security, hiding spots and every build"
		elseif action == "designs" then
			for player, data in DataService.loadedPlayers() do
				for slot, options in Config.CastleDesigns.options do
					for id in options do
						data.ownedDesigns[`{slot}:{id}`] = true
					end
				end
				DataService.markDirty(player)
			end
			return "every Castle Designer option owned (pick them in the Base menu)"
		elseif action == "daily" then
			for player in DataService.loadedPlayers() do
				DailyService.debugNextDay(player)
			end
			return "a day passed (for the Daily menu)"
		end
		return "actions: grant(species, finish?, stage?), event(id), essence(biome, amount?), zone(biome), pass(key), product(key), perk(premium|group|restricted), codes(), cash(amount), guide(), daily(), store(), build(), designs(), reveal(species, finish?)"
	end
	hook.Parent = ServerStorage
end

return StudioDebug

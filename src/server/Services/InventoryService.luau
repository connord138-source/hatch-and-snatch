--!strict
-- The Creatures menu's actions: store a creature, put it back on a pedestal, move
-- it in or out of the nursery, sell it, or release it for biome Essence. Requests
-- come from the client, so every argument is checked here and nothing about the
-- creature is taken from the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StealService = require(script.Parent.StealService)
local ZoneService = require(script.Parent.ZoneService)

local InventoryService = {}

local function sell(player: Player, uid: string, record: DataService.CreatureRecord)
	local value = Config.Economy.sellValue(CreatureService.stats(record))
	local name = Config.CreaturesById[record.species].displayName
	CreatureService.remove(player, uid)
	EconomyService.grant(player, value, "Sell")
	Net.notify(player, `Sold your {name} for {Format.cash(value)}.`, "good")
end

-- Turn a creature in for Essence of its biome (plus spins for rare ones) instead of cash.
local function release(player: Player, uid: string, record: DataService.CreatureRecord)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local species = Config.CreaturesById[record.species]
	local essence, spins =
		Config.Zones.releaseReward(Config.Rarities[species.rarity].order, record.stage, species.biome)
	CreatureService.remove(player, uid)
	ZoneService.grantEssence(player, species.biome, essence)
	data.spins += spins
	DataService.markDirty(player)
	local rewards: { string } = {}
	if essence > 0 then
		table.insert(rewards, `{essence} {Config.Zones.byBiome[species.biome].essence}`)
	end
	if spins > 0 then
		table.insert(rewards, `{spins} Luck Wheel spin{if spins == 1 then "" else "s"}`)
	end
	Net.notify(player, `Released your {species.displayName}: +{table.concat(rewards, ", ")}.`, "good")
end

local function onCreatureAction(player: Player, action: any, uid: any)
	if typeof(action) ~= "string" or typeof(uid) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if record == nil then
		return
	end
	if CreatureService.isCarried(player, uid) then
		Net.notify(player, "A thief has that one! Take it back first.", "bad")
		return
	end
	-- No pulling a pedestal creature out of a thief's hands at the last second
	local dodge = action == "store"
		or (action == "walk" and CreatureService.walkingUid(player) ~= uid)
		or (
			action == "nursery" and not CreatureService.isNursery(data :: DataService.PlayerData, record.slot)
		)
	if dodge and record.slot ~= nil and StealService.underThreat(player) then
		Net.notify(player, "Not while an intruder is in your base! Lock it or chase them out.", "bad")
		return
	end
	if action == "store" then
		CreatureService.store(player, uid)
	elseif action == "place" then
		CreatureService.place(player, uid)
	elseif action == "nursery" then
		CreatureService.toggleNursery(player, uid)
	elseif action == "sell" then
		if CreatureService.walkingUid(player) == uid then
			CreatureService.stopWalking(player)
		end
		sell(player, uid, record)
	elseif action == "release" then
		if CreatureService.walkingUid(player) == uid then
			CreatureService.stopWalking(player)
		end
		release(player, uid, record)
	elseif action == "walk" then
		if CreatureService.walkingUid(player) == uid then
			CreatureService.stopWalking(player)
		else
			CreatureService.walk(player, uid)
		end
	end
end

function InventoryService.start()
	Net.onRequest("CreatureAction", onCreatureAction)
end

return InventoryService

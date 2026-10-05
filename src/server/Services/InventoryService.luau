--!strict
-- The Creatures menu's actions: store a creature, put it back on a pedestal, move
-- it in or out of the nursery, sell it, release it for biome Essence, or feed it
-- Essence to grow it at once. Requests
-- come from the client, so every argument is checked here and nothing about the
-- creature is taken from the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
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

-- Feeds a creature Essence of its own biome: each feed grows it Zones.feed.minutes
-- at once. `how` is "one" (a single feed) or "next" (as many as it takes to reach
-- its next stage, or as many as the player can afford).
local function feed(player: Player, record: DataService.CreatureRecord, how: any)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local species = Config.CreaturesById[record.species]
	local zone = Config.Zones.byBiome[species.biome]
	if zone == nil then
		Net.notify(player, `{species.displayName} runs on spare parts, not Essence.`, "bad")
		return
	end
	local nextAt = CreatureService.nextStageAt(record)
	if nextAt == nil then
		Net.notify(player, `{species.displayName} is fully grown.`, "bad")
		return
	end
	local tuning = Config.Zones.feed
	local step = Timing.scaled(tuning.minutes * 60)
	local wanted = if how == "next" then math.max(1, math.ceil((nextAt - Timing.now()) / step)) else 1
	local have = ZoneService.essence(data, species.biome)
	local feeds = math.min(wanted, have // tuning.essence)
	if feeds <= 0 then
		Net.notify(
			player,
			`Feeding costs {tuning.essence} {zone.essence} (you have {have}). Harvest the glowing nodes in {Config.Biomes[species.biome].displayName}.`,
			"bad"
		)
		return
	end
	local cost = feeds * tuning.essence
	data.essence[species.biome] = have - cost
	-- Growth runs from stageStartedAt, so moving it back grows the creature; the
	-- growth tick spawns the next stage within a second
	record.stageStartedAt -= feeds * step
	DataService.markDirty(player)
	Net.notify(
		player,
		`Fed your {species.displayName} {cost} {zone.essence}: {Format.duration(feeds * tuning.minutes * 60)} of growth.`,
		"good"
	)
end

local function onCreatureAction(player: Player, action: any, uid: any, target: any)
	if action == "arrange" then
		-- "Rarest up top" moves every pedestal creature, so not with a thief inside
		if StealService.underThreat(player) then
			Net.notify(player, "Not while an intruder is in your base! Lock it or chase them out.", "bad")
			return
		end
		CreatureService.arrange(player)
		return
	end
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
		or action == "move"
		or action == "sell" -- (release audit 2026-10-05: selling dodged a Steal hold too)
		or action == "release"
		or (action == "walk" and CreatureService.walkingUid(player) ~= uid)
		or (
			action == "nursery" and not CreatureService.isNursery(data :: DataService.PlayerData, record.slot)
		)
	-- (A move from storage counts too: it can swap a pedestal creature out.)
	if dodge and (record.slot ~= nil or action == "move") and StealService.underThreat(player) then
		Net.notify(player, "Not while an intruder is in your base! Lock it or chase them out.", "bad")
		return
	end
	if action == "store" then
		CreatureService.store(player, uid)
	elseif action == "place" then
		CreatureService.place(player, uid)
	elseif action == "nursery" then
		CreatureService.toggleNursery(player, uid)
	elseif action == "move" and typeof(target) == "string" then
		CreatureService.moveTo(player, uid, target)
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
	elseif action == "feed" then
		feed(player, record, target)
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
	CreatureService.actionRequested:connect(onCreatureAction) -- in-world Nursery and Walk prompts
end

return InventoryService

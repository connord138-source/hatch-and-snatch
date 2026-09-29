--!strict
-- The Creatures menu's actions: store a creature, put it back on a pedestal, move
-- it in or out of the nursery, or sell it. Requests come from the client, so every
-- argument is checked here and nothing about the creature is taken from the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local InventoryService = {}

local function sell(player: Player, uid: string, record: DataService.CreatureRecord)
	local value = Config.Economy.sellValue(CreatureService.stats(record))
	local name = Config.CreaturesById[record.species].displayName
	CreatureService.remove(player, uid)
	EconomyService.grant(player, value)
	Net.notify(player, `Sold your {name} for {Format.cash(value)}.`, "good")
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

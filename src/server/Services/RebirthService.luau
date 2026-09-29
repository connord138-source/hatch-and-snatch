--!strict
-- Rebirth (docs/GDD.md §7): pay the rebirth cost to reset your cash, keep every
-- creature and egg, unlock the next biome's eggs and earn +10% for good.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local ANNOUNCE_COLOR = Color3.fromRGB(255, 215, 90)

local RebirthService = {}

local function biomeWithOrder(order: number): Types.Biome?
	for _, biome in Config.Biomes do
		if biome.order == order then
			return biome
		end
	end
	return nil
end

local function rebirth(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local cost = Config.Economy.rebirthCost(data.rebirths)
	if data.cash < cost then
		Net.notify(player, `You need {Format.cash(cost)} to rebirth.`, "bad")
		return
	end

	local unlockedBefore = data.unlockedBiome
	data.rebirths += 1
	data.cash = Config.Economy.tunables.startingCash
	data.uncollected = 0
	data.unlockedBiome = math.max(data.unlockedBiome, Config.Economy.unlockedBiome(data.rebirths))
	EconomyService.refresh(player)

	local bonus = math.round(data.rebirths * Config.Economy.tunables.rebirthBonusPerLevel * 100)
	local biome = if data.unlockedBiome > unlockedBefore then biomeWithOrder(data.unlockedBiome) else nil
	if biome then
		Net.notify(
			player,
			`Rebirth {data.rebirths}! {biome.displayName} eggs unlocked, earnings +{bonus}%.`,
			"rare"
		)
	else
		Net.notify(player, `Rebirth {data.rebirths}! Earnings are now +{bonus}%.`, "rare")
	end
	Net.announce(`{player.DisplayName} reached Rebirth {data.rebirths}!`, ANNOUNCE_COLOR)
end

function RebirthService.start()
	Net.onRequest("Rebirth", rebirth)
end

return RebirthService

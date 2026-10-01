--!strict
-- Rebirth (docs/GDD.md §7): prestige. Pay the rebirth cost to reset your cash,
-- keep every creature, egg, level and upgrade, and earn +10% for good plus Luck
-- Wheel spins. (Biomes unlock through Hatcher Level + base level, not rebirth.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local ANNOUNCE_COLOR = Color3.fromRGB(255, 215, 90)
local REBIRTH_SPINS = 3

local RebirthService = {}

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

	data.rebirths += 1
	Analytics.cash(
		player,
		false,
		data.cash - Config.Economy.tunables.startingCash,
		Config.Economy.tunables.startingCash,
		"Shop",
		"Rebirth"
	)
	Analytics.event(player, "Rebirth", data.rebirths)
	data.cash = Config.Economy.tunables.startingCash
	data.uncollected = 0
	data.spins += REBIRTH_SPINS
	EconomyService.refresh(player)

	local bonus = math.round(data.rebirths * Config.Economy.tunables.rebirthBonusPerLevel * 100)
	Net.notify(
		player,
		`Rebirth {data.rebirths}! Earnings are now +{bonus}%, and +{REBIRTH_SPINS} Luck Wheel spins.`,
		"rare"
	)
	local looks = Config.CastleDesigns.rebirthUnlocks(data.rebirths)
	if looks then
		Net.notify(player, `🏰 New in the Castle Designer: {looks}!`, "rare")
	end
	Net.announce(`{player.DisplayName} reached Rebirth {data.rebirths}!`, ANNOUNCE_COLOR)
end

function RebirthService.start()
	Net.onRequest("Rebirth", rebirth)
end

return RebirthService

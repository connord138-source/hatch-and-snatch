--!strict
-- Cash: creatures on pedestals earn into the plot's collector every second;
-- stepping on the collector pad banks it. Offline time pays out on rejoin (capped).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Analytics = require(script.Parent.Parent.Analytics)
local Guard = require(script.Parent.Parent.Guard)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)

type CreatureRecord = DataService.CreatureRecord
type PlayerData = DataService.PlayerData

local tunables = Config.Economy.tunables
local passTuning = Config.Monetization.tuning

local EconomyService = {}

-- Personal cash multiplier: game passes (2× Cash, VIP), Roblox Premium, the Roblox
-- group and a rewarded-ad boost.
function EconomyService.bonusMultiplier(player: Player): number
	local multiplier = 1
	if MonetizationService.hasPass(player, "DoubleCash") then
		multiplier *= passTuning.doubleCash
	end
	if MonetizationService.hasPass(player, "VIP") then
		multiplier *= passTuning.vipCash
	end
	if MonetizationService.isPremium(player) then
		multiplier *= passTuning.premiumCash
	end
	if MonetizationService.inGroup(player) then
		multiplier *= passTuning.group.cash
	end
	local data = DataService.get(player)
	if data and (data.boosts.cash or 0) > Timing.now() then
		multiplier *= passTuning.adBoost.multiplier
	end
	return multiplier
end

-- Cash per second one creature earns on a pedestal (rebirth bonus included, moon events not).
function EconomyService.creatureRate(data: PlayerData, record: CreatureRecord): number
	return Config.Economy.cashPerSecond(CreatureService.stats(record))
		* (1 + data.rebirths * tunables.rebirthBonusPerLevel)
end

-- Cash per second for a player's placed creatures, excluding the moon event bonus.
-- A creature a thief is carrying off earns nothing until it's back on its pedestal.
local function baseRate(player: Player, data: PlayerData): number
	local total = 0
	for uid, record in data.creatures do
		if record.slot ~= nil and not CreatureService.isCarried(player, uid) then
			total += EconomyService.creatureRate(data, record)
		end
	end
	return total * EconomyService.bonusMultiplier(player)
end

function EconomyService.rate(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return baseRate(player, data) * EventService.earningsMultiplier()
end

local function updateLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash")
	if cash and cash:IsA("StringValue") then
		cash.Value = Format.cash(data.cash)
	end
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = data.rebirths
	end
end

-- Re-syncs the player list and HUD after cash or rebirths change outside spend/grant.
function EconomyService.refresh(player: Player)
	local data = DataService.get(player)
	if data then
		updateLeaderstats(player, data)
		DataService.markDirty(player)
	end
end

-- Deducts `amount` if affordable. Returns whether it succeeded. `sku` names what was
-- bought for Analytics (keep it to a small fixed set, e.g. "Egg_Mossvale").
function EconomyService.spend(
	player: Player,
	amount: number,
	sku: string,
	transaction: Analytics.Transaction?
): boolean
	local data = DataService.get(player)
	if data == nil or amount < 0 or data.cash < amount then
		return false
	end
	data.cash -= amount
	updateLeaderstats(player, data)
	DataService.markDirty(player)
	Analytics.cash(player, false, amount, data.cash, transaction or "Shop", sku)
	return true
end

-- Adds cash. `sku` names where it came from for Analytics.
function EconomyService.grant(
	player: Player,
	amount: number,
	sku: string,
	transaction: Analytics.Transaction?
)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	data.cash += amount
	updateLeaderstats(player, data)
	DataService.markDirty(player)
	Analytics.cash(player, true, amount, data.cash, transaction or "Gameplay", sku)
end

-- Auto-Collect banks every second; Analytics gets one event a minute instead
local autoCollected: { [Player]: number } = {}
local autoLoggedAt: { [Player]: number } = {}

-- Banks the collector. `quiet` skips the toast (Auto-Collect does this every second).
local function collect(player: Player, quiet: boolean?)
	local data = DataService.get(player)
	if data == nil or data.uncollected < 1 then
		return
	end
	local amount = math.floor(data.uncollected)
	data.uncollected -= amount
	data.cash += amount
	updateLeaderstats(player, data)
	if quiet then
		autoCollected[player] = (autoCollected[player] or 0) + amount
		if os.clock() - (autoLoggedAt[player] or 0) >= 60 then
			Analytics.cash(player, true, autoCollected[player], data.cash, "Gameplay", "AutoCollect")
			autoCollected[player] = 0
			autoLoggedAt[player] = os.clock()
		end
	else
		Net.notify(player, `Collected {Format.cash(amount)}`, "good")
		Analytics.cash(player, true, amount, data.cash, "Gameplay", "Collect")
	end
	Analytics.onboard(player, data, 5)
	ProgressionService.bump(player, "earned", amount)
	DataService.markDirty(player)
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		Guard.run("EconomyService.tick", function()
			local rate = EconomyService.rate(player)
			if rate > 0 then
				data.uncollected += rate
				DataService.markDirty(player)
			end
			if MonetizationService.hasPass(player, "AutoCollect") then
				collect(player, true)
			end
			data.lastSeen = now
			local plot = PlotService.get(player)
			if plot then
				plot.collectorLabel.Text = Format.cash(data.uncollected)
			end
		end)
	end
end

function EconomyService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		local cash = Instance.new("StringValue")
		cash.Name = "Cash"
		cash.Parent = leaderstats
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = leaderstats
		leaderstats.Parent = player
		updateLeaderstats(player, data)
		-- Profiles from before the guide existed have already played: skip it for them
		if data.onboarding == 0 and data.stats.hatched > 0 then
			data.onboarding = #Analytics.ONBOARDING
		end
		Analytics.onboard(player, data, 1)

		-- Offline earnings (uses the rate the base has now; growth already caught up)
		if data.lastSeen > 0 then
			local cap = tunables.offlineCapSeconds
				+ (
					if MonetizationService.hasPass(player, "OfflinePlus")
						then passTuning.offlineBonusSeconds
						else 0
				)
			local away = math.clamp(Timing.now() - data.lastSeen, 0, cap)
			local earned = math.floor(baseRate(player, data) * away)
			if earned > 0 then
				data.uncollected += earned
				Net.notify(player, `While you were away your creatures earned {Format.cash(earned)}!`, "good")
			end
		end
		data.lastSeen = Timing.now()
	end)

	PlotService.collectorTouched:connect(collect)
	Players.PlayerRemoving:Connect(function(player)
		autoCollected[player] = nil
		autoLoggedAt[player] = nil
	end)

	-- Cash packs: minutes of the player's current income, with a floor for new players
	for _, pack in
		{
			{ key = "CashSmall", tune = passTuning.cashSmall },
			{ key = "CashLarge", tune = passTuning.cashLarge },
		}
	do
		MonetizationService.onProduct(pack.key, function(player)
			local amount =
				math.max(pack.tune.minimum, math.floor(EconomyService.rate(player) * pack.tune.minutes * 60))
			EconomyService.grant(player, amount, pack.key, "IAP")
			Net.notify(player, `+{Format.cash(amount)}! Thanks for your purchase.`, "rare")
		end)
	end

	Guard.loop("EconomyService.tick", 1, tick)
end

return EconomyService

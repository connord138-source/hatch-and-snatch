--!strict
-- Cash: creatures on pedestals earn into the plot's collector every second;
-- stepping on the collector pad banks it. Offline time pays out on rejoin (capped).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)

type CreatureRecord = DataService.CreatureRecord
type PlayerData = DataService.PlayerData

local tunables = Config.Economy.tunables

local EconomyService = {}

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
	return total
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

-- Deducts `amount` if affordable. Returns whether it succeeded.
function EconomyService.spend(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if data == nil or amount < 0 or data.cash < amount then
		return false
	end
	data.cash -= amount
	updateLeaderstats(player, data)
	DataService.markDirty(player)
	return true
end

function EconomyService.grant(player: Player, amount: number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	data.cash += amount
	updateLeaderstats(player, data)
	DataService.markDirty(player)
end

local function collect(player: Player)
	local data = DataService.get(player)
	if data == nil or data.uncollected < 1 then
		return
	end
	local amount = math.floor(data.uncollected)
	data.uncollected -= amount
	data.cash += amount
	updateLeaderstats(player, data)
	Net.notify(player, `Collected {Format.cash(amount)}`, "good")
	ProgressionService.bump(player, "earned", amount)
	DataService.markDirty(player)
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		local rate = EconomyService.rate(player)
		if rate > 0 then
			data.uncollected += rate
			DataService.markDirty(player)
		end
		data.lastSeen = now
		local plot = PlotService.get(player)
		if plot then
			plot.collectorLabel.Text = Format.cash(data.uncollected)
		end
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

		-- Offline earnings (uses the rate the base has now; growth already caught up)
		if data.lastSeen > 0 then
			local away = math.clamp(Timing.now() - data.lastSeen, 0, tunables.offlineCapSeconds)
			local earned = math.floor(baseRate(player, data) * away)
			if earned > 0 then
				data.uncollected += earned
				Net.notify(player, `While you were away your creatures earned {Format.cash(earned)}!`, "good")
			end
		end
		data.lastSeen = Timing.now()
	end)

	PlotService.collectorTouched:connect(collect)

	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return EconomyService

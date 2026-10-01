--!strict
-- Replicates each player's own state to their client (HUD) a few times per second,
-- only when something changed, and then only the top-level fields that changed:
-- cash ticks every second, but the creature list and Index maps rarely do.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local ProgressionService = require(script.Parent.ProgressionService)
local StealService = require(script.Parent.StealService)

local StateService = {}

-- What each client last received: top-level key → encoded value
local sent: { [Player]: { [string]: string } } = {}
local ALWAYS = "\0" -- a value that couldn't be encoded; resend it every time

local function encode(value: any): string?
	if typeof(value) == "number" then
		return string.format("%.17g", value)
	elseif typeof(value) ~= "table" then
		return `{typeof(value)}:{tostring(value)}`
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, value)
	return if ok then json else nil
end

-- The keys that changed since the last send, the keys that went away, and
-- whether this is the first (full) snapshot.
local function diff(player: Player, state: { [string]: any }): ({ [string]: any }, { string }, boolean)
	local full = sent[player] == nil
	local last: { [string]: string } = sent[player] or {}
	local changes: { [string]: any } = {}
	local cleared: { string } = {}
	for key, value in state do
		local encoded = encode(value)
		if full or encoded == nil or last[key] ~= encoded then
			changes[key] = value
		end
		last[key] = encoded or ALWAYS
	end
	for key in last do
		if state[key] == nil then
			table.insert(cleared, key)
			last[key] = nil
		end
	end
	sent[player] = last
	return changes, cleared, full
end

local function snapshot(player: Player): { [string]: any }?
	local data = DataService.get(player)
	if data == nil then
		return nil
	end
	local incubators = {}
	for _, egg in data.incubators do
		table.insert(incubators, {
			biome = egg.biome,
			startedAt = egg.startedAt,
			hatchAt = egg.hatchAt,
			slot = egg.slot,
			spun = egg.spun,
		})
	end
	local creatures = {}
	local bonusMultiplier = EconomyService.bonusMultiplier(player)
	for uid, record in data.creatures do
		table.insert(creatures, {
			uid = uid,
			species = record.species,
			stage = record.stage,
			finish = record.finish,
			mutation = record.mutation,
			slot = record.slot,
			homegrown = record.homegrown,
			stolenFrom = record.stolenFrom,
			nextStageAt = CreatureService.nextStageAt(record),
			carried = CreatureService.isCarried(player, uid),
			rate = EconomyService.creatureRate(data, record) * bonusMultiplier,
			value = Config.Economy.sellValue(CreatureService.stats(record)),
		})
	end
	local lock = StealService.lockState(player)
	return {
		rebirths = data.rebirths,
		rebirthCost = Config.Economy.rebirthCost(data.rebirths),
		pedestals = CreatureService.pedestalCount(data),
		baseLevel = data.baseLevel,
		baseLevels = #Config.Economy.tunables.baseLevels,
		nextBaseCost = if Config.Economy.tunables.baseLevels[data.baseLevel + 1]
			then Config.Economy.tunables.baseLevels[data.baseLevel + 1].cost
			else nil,
		baseTheme = data.baseTheme,
		security = data.security,
		ownedThemes = data.ownedThemes,
		progression = ProgressionService.snapshot(data),
		spins = data.spins,
		luckCharge = data.luckCharge,
		essence = data.essence,
		spinProgress = data.spinProgress,
		heldEgg = if data.heldEgg then data.heldEgg.biome else nil,
		walking = CreatureService.walkingUid(player),
		incubatorTiers = data.incubatorTiers,
		storageSlots = CreatureService.storageSlots(data),
		nurserySlots = CreatureService.nurserySlots(data),
		passes = MonetizationService.ownedPasses(player),
		premium = MonetizationService.isPremium(player),
		inGroup = MonetizationService.inGroup(player),
		paidRandomRestricted = MonetizationService.paidRandomRestricted(player),
		groupRewarded = data.groupRewarded,
		onboarding = data.onboarding, -- first-session guide step (GuideController)
		daily = DailyService.snapshot(player, data),
		boosts = data.boosts,
		index = data.index,
		indexFinishes = data.indexFinishes,
		indexAdults = data.indexAdults,
		lockedUntil = if lock then lock.lockedUntil else 0,
		lockCooldownUntil = if lock then lock.cooldownUntil else 0,
		carrying = StealService.carryingName(player),
		protectedUntil = if Timing.isStudio() and Config.Debug.studioSkipNewPlayerProtection
			then 0
			else data.createdAt + Config.Economy.tunables.newPlayerProtectionSeconds,
		cash = data.cash,
		uncollected = data.uncollected,
		rate = EconomyService.rate(player),
		unlockedBiome = data.unlockedBiome,
		incubatorSlots = #data.incubatorTiers,
		incubators = incubators,
		creatures = creatures,
	}
end

function StateService.start()
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in DataService.takeDirty() do
				local state = snapshot(player)
				if state then
					local changes, cleared, full = diff(player, state)
					if full or next(changes) ~= nil or #cleared > 0 then
						Net.sendState(player, changes, cleared, full)
					end
				end
			end
		end
	end)
end

return StateService

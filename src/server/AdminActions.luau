--!strict
-- What the owner's admin panel (Admin.luau) and the Studio Command Bar hook
-- (StudioDebug.luau) can do. Every action takes the players it applies to and
-- returns a line of text saying what happened. The callers decide who may run
-- them; the arguments are checked here, as they can come from a client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Net)
local BaseService = require(script.Parent.Services.BaseService)
local CreatureService = require(script.Parent.Services.CreatureService)
local DailyService = require(script.Parent.Services.DailyService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local EventService = require(script.Parent.Services.EventService)
local HatchService = require(script.Parent.Services.HatchService)
local MonetizationService = require(script.Parent.Services.MonetizationService)
local PlotService = require(script.Parent.Services.PlotService)
local ProgressionService = require(script.Parent.Services.ProgressionService)
local ZoneEventService = require(script.Parent.Services.ZoneEventService)
local ZoneService = require(script.Parent.Services.ZoneService)

type PlayerData = DataService.PlayerData

local MAX_AMOUNT = 1e30 -- cash, XP and Essence: anything finite and sane

local AdminActions = {}

-- A finite number in [min, MAX_AMOUNT], or nil.
local function amountOf(value: any, min: number): number?
	if typeof(value) ~= "number" or value ~= value or value < min or value > MAX_AMOUNT then
		return nil
	end
	return value
end

-- Runs `fn` for each target whose save is loaded; returns how many.
local function each(targets: { Player }, fn: (Player, PlayerData) -> ()): number
	local count = 0
	for _, player in targets do
		local data = DataService.get(player)
		if data then
			fn(player, data)
			DataService.markDirty(player)
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Cash, Essence, XP, spins, rebirths
---------------------------------------------------------------------------

function AdminActions.addCash(targets: { Player }, amount: any): string
	local n = amountOf(amount, 1)
	if n == nil then
		return "Cash needs a positive amount"
	end
	-- Its own SKU, so the economy dashboard can leave admin cash out
	local count = each(targets, function(player)
		EconomyService.grant(player, n, "Admin")
	end)
	return `Gave ${n} to {count} player(s)`
end

function AdminActions.setCash(targets: { Player }, amount: any): string
	local n = amountOf(amount, 0)
	if n == nil then
		return "Cash needs an amount of 0 or more"
	end
	local count = each(targets, function(player, data)
		data.cash = n
		EconomyService.refresh(player)
	end)
	return `Set cash to ${n} for {count} player(s)`
end

function AdminActions.essence(targets: { Player }, biomeId: any, amount: any): string
	if typeof(biomeId) ~= "string" or Config.Zones.byBiome[biomeId] == nil then
		return "Unknown biome"
	end
	local n = amountOf(amount, 1) or 50
	each(targets, function(player)
		ZoneService.grantEssence(player, biomeId, n)
	end)
	return `Gave {n} {Config.Zones.byBiome[biomeId].essence}`
end

function AdminActions.xp(targets: { Player }, amount: any): string
	local n = amountOf(amount, 1)
	if n == nil then
		return "XP needs a positive amount"
	end
	local count = each(targets, function(player)
		ProgressionService.addXp(player, n)
	end)
	return `Gave {n} XP to {count} player(s)`
end

function AdminActions.spins(targets: { Player }, amount: any): string
	local n = math.floor(amountOf(amount, 1) or 10)
	local count = each(targets, function(_, data)
		data.spins += n
	end)
	return `Gave {n} Luck Wheel spins to {count} player(s)`
end

-- Sets the rebirth count (Castle Designer looks and biome eggs follow it).
function AdminActions.rebirths(targets: { Player }, amount: any): string
	local n = amountOf(amount, 0)
	if n == nil or n > 1000 then
		return "Rebirths needs a number from 0 to 1000"
	end
	local whole = math.floor(n)
	local count = each(targets, function(player, data)
		data.rebirths = whole
		ProgressionService.refresh(player)
		EconomyService.refresh(player)
	end)
	return `Set rebirths to {whole} for {count} player(s)`
end

---------------------------------------------------------------------------
-- Creatures and eggs
---------------------------------------------------------------------------

-- Spawns a creature (finish, stage and mutation optional; "Normal" for no finish).
function AdminActions.grant(targets: { Player }, species: any, finish: any, stage: any, mutation: any): string
	if typeof(species) ~= "string" or Config.CreaturesById[species] == nil then
		return "Unknown species"
	end
	local stageId = if typeof(stage) == "string" and Config.Stages[stage :: any] then stage else "Adult"
	local finishId = "Normal"
	for _, entry in Config.Finishes do
		if entry.id == finish then
			finishId = entry.id
		end
	end
	local mutationId = if typeof(mutation) == "string" and Config.MutationsById[mutation]
		then mutation
		else nil
	local count = each(targets, function(player)
		CreatureService.add(player, {
			species = species,
			stage = stageId,
			stageStartedAt = Timing.now(),
			finish = finishId,
			mutation = mutationId,
			homegrown = true,
		})
	end)
	local name = Config.CreaturesById[species].displayName
	return `Gave {if mutationId then mutationId .. " " else ""}{finishId} {stageId} {name} to {count} player(s)`
end

-- Puts a freshly rolled egg of a biome in each player's hands, to place in an incubator.
function AdminActions.egg(targets: { Player }, biomeId: any): string
	if typeof(biomeId) ~= "string" or Config.Biomes[biomeId] == nil then
		return "Unknown biome"
	end
	local count = 0
	for _, player in targets do
		local data = DataService.get(player)
		if data and data.heldEgg == nil then
			HatchService.giveEgg(player, biomeId)
			count += 1
		end
	end
	return `Gave a {Config.Biomes[biomeId].displayName} egg to {count} player(s) (hands must be empty)`
end

-- Every egg in an incubator hatches now.
function AdminActions.hatchAll(targets: { Player }): string
	local eggs = 0
	each(targets, function(player, data)
		local now = Timing.now()
		for _, record in data.incubators do
			record.hatchAt = now
			eggs += 1
		end
		HatchService.refresh(player, data)
	end)
	return `{eggs} egg(s) ready to hatch`
end

-- Every creature grows up to an Adult now.
function AdminActions.growAll(targets: { Player }): string
	local grown = 0
	each(targets, function(player, data)
		for uid, record in data.creatures do
			if record.stage ~= "Adult" then
				record.stage = "Adult"
				record.stageStartedAt = Timing.now()
				data.indexAdults[record.species] = true
				CreatureService.respawn(player, uid)
				grown += 1
			end
		end
	end)
	return `{grown} creature(s) grown to Adult`
end

-- Moves every creature on a pedestal into storage, so fresh grants land on pedestals.
function AdminActions.storeAll(targets: { Player }): string
	local moved = 0
	each(targets, function(player, data)
		for uid, record in data.creatures do
			if record.slot ~= nil then
				CreatureService.store(player, uid)
				if record.slot == nil then
					moved += 1
				end
			end
		end
	end)
	return `Moved {moved} creature(s) to storage`
end

-- Plays the hatch reveal for a species without granting anything (store screenshots).
function AdminActions.reveal(targets: { Player }, species: any, finish: any, mutation: any): string
	local creature = if typeof(species) == "string" then Config.CreaturesById[species] else nil
	if creature == nil then
		return "Unknown species"
	end
	for _, player in targets do
		Net.hatchReveal(player, {
			species = species,
			biome = creature.biome,
			finish = if typeof(finish) == "string" then finish else "Normal",
			mutation = if typeof(mutation) == "string" and Config.MutationsById[mutation]
				then mutation
				else nil,
		})
	end
	return `Revealing {creature.displayName}`
end

---------------------------------------------------------------------------
-- Base
---------------------------------------------------------------------------

-- Level 5, both floors, all vaults, security, the hiding spots and every build.
function AdminActions.maxBase(targets: { Player }): string
	local tunables = Config.Economy.tunables
	local count = each(targets, function(player, data)
		data.baseLevel = #tunables.baseLevels
		data.floors = #tunables.floors + 1
		data.vaults = #tunables.vaults
		data.security = #tunables.securityLevels
		data.hides = #Config.BaseBuilds.hidingSpots
		for _, item in Config.BaseBuilds.items do
			data.builds[item.id] = true
		end
		BaseService.apply(player, data)
	end)
	return `Maxed {count} base(s): level 5, both floors, all vaults, security, hiding spots and every build`
end

-- Owns every Castle Designer option (pick them at the Command Terminal).
function AdminActions.allDesigns(targets: { Player }): string
	local count = each(targets, function(_, data)
		for slot, options in Config.CastleDesigns.options do
			for id in options do
				data.ownedDesigns[`{slot}:{id}`] = true
			end
		end
	end)
	return `Every Castle Designer option owned for {count} player(s)`
end

function AdminActions.pass(targets: { Player }, key: any): string
	if typeof(key) ~= "string" or Config.Monetization.passesByKey[key] == nil then
		return "Unknown pass"
	end
	for _, player in targets do
		MonetizationService.grantPass(player, key)
	end
	return `Granted {key} (this session; a real purchase is what keeps it)`
end

-- Runs a developer product's effect (ServerLuck is server-wide: once is enough).
function AdminActions.product(targets: { Player }, key: any): string
	if typeof(key) ~= "string" or Config.Monetization.productsByKey[key] == nil then
		return "Unknown product"
	end
	local count = 0
	for _, player in targets do
		if MonetizationService.grantProduct(player, key) then
			count += 1
		end
		if key == "ServerLuck" then
			break
		end
	end
	return `Ran {key} for {count} player(s)`
end

---------------------------------------------------------------------------
-- World (server-wide)
---------------------------------------------------------------------------

function AdminActions.moonEvent(id: any): string
	for _, event in Config.MoonEvents do
		if event.id == id then
			task.spawn(EventService.run, event)
			return `Started {event.displayName}`
		end
	end
	return "Unknown moon event"
end

function AdminActions.zoneEvent(biomeId: any): string
	local zone = if typeof(biomeId) == "string" then ZoneEventService.zone(biomeId) else nil
	if zone == nil then
		return "Unknown biome"
	end
	task.spawn(ZoneEventService.run, zone, true)
	return `Running the {biomeId} zone event`
end

-- Holds everyone's sky at a time of day (Shared/DayNight reads the ClockHold
-- attribute), or lets the cycle run again ("auto").
local CLOCK_HOLDS: { [string]: number } = { day = 13, dusk = 18, night = 0 }
function AdminActions.clock(mode: any): string
	if mode == "auto" then
		Workspace:SetAttribute("ClockHold", nil)
		return "Day and night cycle running"
	end
	local hold = if typeof(mode) == "string" then CLOCK_HOLDS[mode] else nil
	if hold == nil then
		return "Time is day, dusk, night or auto"
	end
	Workspace:SetAttribute("ClockHold", hold)
	return `Holding the sky at {mode} (Auto lets the cycle run again)`
end

---------------------------------------------------------------------------
-- Testing aids
---------------------------------------------------------------------------

function AdminActions.restartGuide(targets: { Player }): string
	local count = each(targets, function(_, data)
		data.onboarding = 1
	end)
	return `First-session guide restarted for {count} player(s)`
end

function AdminActions.resetCodes(targets: { Player }): string
	local count = each(targets, function(_, data)
		table.clear(data.codes)
	end)
	return `Codes can be redeemed again by {count} player(s)`
end

function AdminActions.nextDay(targets: { Player }): string
	for _, player in targets do
		DailyService.debugNextDay(player)
	end
	return "A day passed (the login reward and new quests are back)"
end

-- Moves `player` to the front of `target`'s base.
function AdminActions.goToBase(player: Player, target: Player): string
	local plot = PlotService.get(target)
	if plot == nil then
		return `{target.DisplayName} has no base`
	end
	Net.teleport(player, plot.spawn)
	return `Went to {target.DisplayName}'s base`
end

return AdminActions

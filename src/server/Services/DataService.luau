--!strict
-- Player save data via ProfileStore (session-locked, auto-saving). In an
-- unpublished Studio place ProfileStore automatically falls back to a mock store.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Timing = require(ReplicatedStorage.Shared.Timing)

export type CreatureRecord = {
	species: string,
	stage: string, -- Types.StageId
	stageStartedAt: number, -- unix time the current stage began
	finish: string,
	mutation: string?,
	homegrown: boolean,
	stolenFrom: string?,
	slot: number?, -- pedestal index, nil = in storage
}

export type IncubatorRecord = {
	biome: string,
	species: string, -- rolled at purchase, revealed at hatch
	startedAt: number,
	hatchAt: number,
	spun: boolean?, -- Luck Wheel already used on this egg
	slot: number, -- which incubator (1 = the free one)
}

-- An egg bought off the conveyor that the player is carrying to an incubator
export type HeldEgg = {
	biome: string,
	species: string,
}

export type PlayerData = {
	version: number,
	cash: number,
	uncollected: number,
	lastSeen: number,
	createdAt: number, -- first join (new-player steal protection)
	rebirths: number,
	unlockedBiome: number, -- highest Biomes[].order the player may buy
	nextUid: number,
	creatures: { [string]: CreatureRecord },
	incubators: { IncubatorRecord },
	-- Collection index: species ever owned, their finishes, and ones raised to Adult
	index: { [string]: boolean },
	indexFinishes: { [string]: { [string]: boolean } },
	indexAdults: { [string]: boolean },
	stats: {
		hatched: number,
		eggsBought: number,
		adults: number,
		steals: number,
		discovered: number,
		finishes: number,
		baseUpgrades: number,
		incubators: number,
		walkSeconds: number,
		spinsUsed: number,
		earned: number,
	},
	xp: number, -- lifetime XP; the Hatcher Level is derived from it
	achievements: { [string]: boolean },
	incubatorTiers: { number }, -- one entry per owned incubator (its tier)
	heldEgg: HeldEgg?,
	baseTheme: string,
	ownedThemes: { [string]: boolean },
	baseLevel: number, -- Config.Economy.tunables.baseLevels index
	spins: number, -- banked Luck Wheel spins
	spinProgress: number, -- seconds played toward the next free spin
}

local TEMPLATE: PlayerData = {
	version = 1,
	cash = Config.Economy.tunables.startingCash,
	uncollected = 0,
	lastSeen = 0,
	createdAt = 0,
	rebirths = 0,
	unlockedBiome = 1,
	nextUid = 1,
	creatures = {},
	incubators = {},
	index = {},
	indexFinishes = {},
	indexAdults = {},
	stats = {
		hatched = 0,
		eggsBought = 0,
		adults = 0,
		steals = 0,
		discovered = 0,
		finishes = 0,
		baseUpgrades = 0,
		incubators = 1,
		walkSeconds = 0,
		spinsUsed = 0,
		earned = 0,
	},
	xp = 0,
	achievements = {},
	incubatorTiers = { 1 },
	heldEgg = nil,
	baseTheme = "Mossvale",
	ownedThemes = { Mossvale = true },
	baseLevel = 1,
	spins = Config.Economy.tunables.startingSpins,
	spinProgress = 0,
}

-- Studio reads and writes the live game's DataStores, so Studio sessions (debug
-- cash, unlocked biomes, test players) use their own store and never touch real saves.
local STORE_NAME = if Timing.isStudio() then "PlayerData_Studio_v1" else "PlayerData_v2"
local store = ProfileStore.New(STORE_NAME, TEMPLATE :: any)
local profiles: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local DataService = {
	-- (player, data) — fired after a profile loads; listeners run in connect order
	loaded = Signal.new(),
	-- (player, data) — fired right before the session ends so services can clean up
	releasing = Signal.new(),
}

function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data :: PlayerData else nil
end

function DataService.loadedPlayers(): { [Player]: PlayerData }
	local result: { [Player]: PlayerData } = {}
	for player, profile in profiles do
		result[player] = profile.Data :: PlayerData
	end
	return result
end

-- Flags the player's state for replication on the next StateService flush.
function DataService.markDirty(player: Player)
	dirty[player] = true
end

function DataService.takeDirty(): { Player }
	local list: { Player } = {}
	for player in dirty do
		table.insert(list, player)
	end
	table.clear(dirty)
	return list
end

function DataService.newUid(data: PlayerData): string
	local uid = "c" .. tostring(data.nextUid)
	data.nextUid += 1
	return uid
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(
		`Player_{player.UserId}`,
		{
			Cancel = function()
				return player.Parent ~= Players
			end,
		} :: any
	)
	if profile == nil then
		player:Kick("Could not load your data — please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was loaded on another server — please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data = profile.Data :: PlayerData
	if data.createdAt == 0 then
		data.createdAt = Timing.now()
	end
	if Timing.isStudio() then
		data.cash = math.max(data.cash, Config.Debug.studioStartingCash)
	end
	-- Saves from before incubator slots: keep every egg by giving it a slot (and
	-- the player enough incubators to hold them)
	for i, egg in data.incubators do
		if egg.slot == nil then
			egg.slot = i
		end
		while #data.incubatorTiers < egg.slot do
			table.insert(data.incubatorTiers, 1)
		end
	end
	data.stats.incubators = #data.incubatorTiers
	local discovered = 0
	for _ in data.index do
		discovered += 1
	end
	data.stats.discovered = discovered
	-- data.unlockedBiome is recomputed by ProgressionService on load

	profiles[player] = profile
	DataService.loaded:fire(player, data)
	dirty[player] = true
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	local data = profile.Data :: PlayerData
	data.lastSeen = Timing.now()
	DataService.releasing:fire(player, data)
	profiles[player] = nil
	dirty[player] = nil
	profile:EndSession()
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataService

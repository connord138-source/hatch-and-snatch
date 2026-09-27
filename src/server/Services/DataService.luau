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
}

export type PlayerData = {
	version: number,
	cash: number,
	uncollected: number,
	lastSeen: number,
	rebirths: number,
	unlockedBiome: number, -- highest Biomes[].order the player may buy
	nextUid: number,
	creatures: { [string]: CreatureRecord },
	incubators: { IncubatorRecord },
	index: { [string]: boolean }, -- species ever owned (collection book)
	stats: { hatched: number, eggsBought: number },
}

local TEMPLATE: PlayerData = {
	version = 1,
	cash = Config.Economy.tunables.startingCash,
	uncollected = 0,
	lastSeen = 0,
	rebirths = 0,
	unlockedBiome = 1,
	nextUid = 1,
	creatures = {},
	incubators = {},
	index = {},
	stats = { hatched = 0, eggsBought = 0 },
}

local store = ProfileStore.New("PlayerData_v1", TEMPLATE :: any)
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
	if Timing.isStudio() then
		data.cash = math.max(data.cash, Config.Debug.studioStartingCash)
		if Config.Debug.studioUnlockAllBiomes then
			data.unlockedBiome = 6
		end
	end

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

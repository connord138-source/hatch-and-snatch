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
	stolenAt: number?, -- unix time of the last steal (no steal rewards again for a while)
	slot: number?, -- pedestal index, nil = in storage
}

export type IncubatorRecord = {
	biome: string,
	species: string, -- rolled at purchase, revealed at hatch
	finish: string?, -- rolled at purchase too (older saves roll at hatch)
	mutation: string?,
	startedAt: number,
	hatchAt: number,
	spun: boolean?, -- Luck Wheel already used on this egg
	slot: number, -- which incubator (1 = the free one)
}

-- An egg bought off the conveyor that the player is carrying to an incubator
export type HeldEgg = {
	biome: string,
	species: string,
	finish: string?,
	mutation: string?,
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
		harvests: number,
	},
	xp: number, -- lifetime XP; the Hatcher Level is derived from it
	achievements: { [string]: boolean },
	incubatorTiers: { number }, -- one entry per owned incubator (its tier)
	heldEgg: HeldEgg?,
	baseTheme: string,
	ownedThemes: { [string]: boolean },
	baseLevel: number, -- Config.Economy.tunables.baseLevels index
	security: number, -- how many of Config.Economy.tunables.securityLevels are bought
	floors: number, -- floors the base has, counting the ground (1-3, Config.Economy.tunables.floors)
	vaults: number, -- vault rooms bought (Config.Economy.tunables.vaults)
	floorsMigrated: boolean, -- old saves: base levels 4-5 had the deck, now the floors
	spins: number, -- banked Luck Wheel spins
	luckCharge: number, -- luck multiplier waiting for the next egg bought (1 = none)
	spinProgress: number, -- seconds played toward the next free spin
	essence: { [string]: number }, -- per biome, from harvest nodes and releases (Config.Zones)
	-- Monetization (MonetizationService). Game passes are checked with Roblox on
	-- join; this also keeps passes bought or granted this session.
	passes: { [string]: boolean },
	purchaseIds: { string }, -- developer-product receipts already granted (newest last)
	boosts: { [string]: number }, -- personal boosts: Unix time each runs out (instantHatch: a count)
	codes: { [string]: boolean }, -- codes already redeemed (Config.Codes, upper case)
	groupRewarded: boolean, -- got the one-time Roblox group reward
	onboarding: number, -- furthest onboarding funnel step logged (Analytics.ONBOARDING)
	daily: DailyData, -- login streak and daily quests (DailyService)
}

export type DailyQuest = {
	id: string, -- Config.Daily.quests id
	goal: number,
	base: number, -- the stat's value when the quest was given
	done: boolean,
}

export type DailyData = {
	loginDay: number, -- UTC day number of the last login reward claimed (0 = never)
	streak: number, -- consecutive days claimed
	questDay: number, -- UTC day the quests below were given
	quests: { DailyQuest },
	rerolls: number, -- used today
	bonusPaid: boolean, -- all-quests bonus paid today
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
		harvests = 0,
	},
	xp = 0,
	achievements = {},
	incubatorTiers = { 1 },
	heldEgg = nil,
	baseTheme = "Mossvale",
	ownedThemes = { Mossvale = true },
	baseLevel = 1,
	security = 0,
	floors = 1,
	vaults = 0,
	floorsMigrated = false,
	spins = Config.Economy.tunables.startingSpins,
	luckCharge = 1,
	spinProgress = 0,
	essence = {},
	passes = {},
	purchaseIds = {},
	boosts = {},
	codes = {},
	groupRewarded = false,
	onboarding = 0,
	daily = {
		loginDay = 0,
		streak = 0,
		questDay = 0,
		quests = {},
		rerolls = 0,
		bonusPaid = false,
	},
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

local PURCHASE_ID_CACHE = 100

-- Grants a developer product exactly once, the way ProfileStore recommends: the
-- receipt's PurchaseId is recorded in the save alongside the grant, and Roblox is
-- only told "granted" once a save containing it has gone through. If the server
-- dies first, Roblox retries the receipt later and the recorded id stops a double
-- grant. `grant` changes the player's data; it runs at most once per PurchaseId.
function DataService.processPurchase(
	player: Player,
	purchaseId: string,
	grant: (PlayerData) -> ()
): Enum.ProductPurchaseDecision
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = profile.Data :: PlayerData
	if table.find(data.purchaseIds, purchaseId) == nil then
		local ok, problem = pcall(function(): any
			grant(data)
			return nil
		end)
		if not ok then
			warn(`[DataService] purchase {purchaseId} failed to grant: {problem}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #data.purchaseIds >= PURCHASE_ID_CACHE do
			table.remove(data.purchaseIds, 1)
		end
		table.insert(data.purchaseIds, purchaseId)
		dirty[player] = true
	end
	-- Wait for a save that includes it
	local decision: Enum.ProductPurchaseDecision? = nil
	local function check()
		local saved = profile.LastSavedData
		if saved and saved.purchaseIds and table.find(saved.purchaseIds, purchaseId) then
			decision = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	check()
	if decision then
		return decision
	end
	local connection = profile.OnAfterSave:Connect(check)
	profile:Save()
	local deadline = os.clock() + 30
	local nextSave = os.clock() + 10
	while decision == nil and profile:IsActive() and os.clock() < deadline do
		task.wait()
		if os.clock() >= nextSave then
			nextSave = os.clock() + 10
			profile:Save() -- the first save may have been throttled
		end
	end
	connection:Disconnect()
	return decision or Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Saves a player's data now (after something that must not be lost in a crash,
-- like a creature moving between two players' saves).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

function DataService.newUid(data: PlayerData): string
	local uid = "c" .. tostring(data.nextUid)
	data.nextUid += 1
	return uid
end

local function onPlayerAdded(player: Player)
	-- Give up after a minute (ProfileStore's own timeout is off when Cancel is set)
	local started = os.clock()
	local profile = store:StartSessionAsync(
		`Player_{player.UserId}`,
		{
			Cancel = function()
				return player.Parent ~= Players or os.clock() - started > 60
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
		-- The session ended under us (loaded on another server, or the lock was
		-- lost): let services clean up (plot, carries) as if the player left
		if profiles[player] == profile then
			DataService.releasing:fire(player, profile.Data)
			profiles[player] = nil
			dirty[player] = nil
		end
		if player.Parent == Players and not ProfileStore.IsClosing then
			player:Kick("Your data was loaded on another server — please rejoin.")
		end
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
	-- Saves from before floors (2026-10-01): base levels 4 and 5 had an upper deck
	-- on what are now the Second and Top Floors' pedestals, so they keep those floors
	if not data.floorsMigrated then
		data.floorsMigrated = true
		if data.baseLevel >= 4 then
			data.floors =
				math.max(data.floors, math.min(data.baseLevel - 2, #Config.Economy.tunables.floors + 1))
		end
	end
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

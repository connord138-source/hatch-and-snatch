--!strict
-- Hatcher Level (docs/GDD.md §7.2): XP from hatching, growing, stealing,
-- discovering species and upgrading; achievements pay XP + Luck Wheel spins.
-- The level (plus base level) decides which biomes' eggs a player can buy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)

type PlayerData = DataService.PlayerData

local Progression = Config.Progression
local LEVEL_UP_COLOR = Color3.fromRGB(120, 230, 255)

local ProgressionService = {}

function ProgressionService.level(data: PlayerData): number
	local level = Progression.levelFromXp(data.xp)
	return level
end

-- True when the player may buy `biomeId` eggs (Studio can unlock everything).
function ProgressionService.canBuyBiome(data: PlayerData, biomeId: string): boolean
	if Timing.isStudio() and Config.Debug.studioUnlockAllBiomes then
		return true
	end
	return Progression.biomeUnlocked(biomeId, ProgressionService.level(data), data.baseLevel)
end

-- Keeps data.unlockedBiome (highest unlocked biome order, used by the UI) current,
-- and announces newly unlocked biomes.
local function refreshUnlocks(player: Player, data: PlayerData, announce: boolean)
	local highest = 1
	for _, biome in Config.Biomes do
		if biome.order > 0 and ProgressionService.canBuyBiome(data, biome.id) then
			highest = math.max(highest, biome.order)
			if announce and biome.order > data.unlockedBiome then
				Net.notify(player, `{biome.displayName} eggs unlocked! Look for them on the belt.`, "rare")
			end
		end
	end
	data.unlockedBiome = highest
end

local function checkAchievements(player: Player, data: PlayerData)
	for _, achievement in Progression.achievements do
		if not data.achievements[achievement.id] then
			local value = (data.stats :: any)[achievement.stat]
			if typeof(value) == "number" and value >= achievement.goal then
				data.achievements[achievement.id] = true
				data.spins += achievement.spins
				-- Some names already end in "!" ("It's Alive!", "Shiny!"): don't double it
				local name = achievement.name
				local title = if string.sub(name, -1) == "!" then name else `{name}!`
				local plural = if achievement.spins == 1 then "" else "s"
				Net.notify(
					player,
					`Achievement: {title} +{achievement.xp} XP, +{achievement.spins} Luck Wheel spin{plural}`,
					"rare"
				)
				ProgressionService.addXp(player, achievement.xp)
			end
		end
	end
end

function ProgressionService.addXp(player: Player, amount: number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return
	end
	local before = ProgressionService.level(data)
	data.xp += math.floor(amount)
	local after = ProgressionService.level(data)
	if after > before then
		Net.notify(player, `Hatcher Level {after}!`, "rare")
		if after % 5 == 0 then
			Net.announce(`{player.DisplayName} reached Hatcher Level {after}!`, LEVEL_UP_COLOR)
		end
		refreshUnlocks(player, data, true)
	end
	DataService.markDirty(player)
end

-- Adds to a lifetime stat (PlayerData.stats) and pays out any achievement it completes.
function ProgressionService.bump(player: Player, stat: string, amount: number?)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local stats = data.stats :: any
	stats[stat] = (stats[stat] or 0) + (amount or 1)
	checkAchievements(player, data)
	DataService.markDirty(player)
end

-- Sets a stat to an absolute value (counts like "incubators owned").
function ProgressionService.setStat(player: Player, stat: string, value: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local stats = data.stats :: any
	stats[stat] = value
	checkAchievements(player, data)
end

-- Called after the base level changes: it can unlock biomes too.
function ProgressionService.refresh(player: Player)
	local data = DataService.get(player)
	if data then
		refreshUnlocks(player, data, true)
		DataService.markDirty(player)
	end
end

-- For the state snapshot / Progress menu.
function ProgressionService.snapshot(data: PlayerData): { [string]: any }
	local level, into, needed = Progression.levelFromXp(data.xp)
	return {
		level = level,
		xpInto = into,
		xpNeeded = needed,
		achievements = data.achievements,
		stats = data.stats,
	}
end

function ProgressionService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		refreshUnlocks(player, data, false)
		checkAchievements(player, data)
	end)
end

return ProgressionService

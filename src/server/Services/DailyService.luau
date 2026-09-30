--!strict
-- Daily login streak and daily quests (Config.Daily, GDD §7.4). Days are UTC
-- days. The login reward is claimed in the Daily menu; quests are checked every
-- couple of seconds from the growth of lifetime stats and pay out on their own.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyConfig = require(ReplicatedStorage.Shared.Config.Daily)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

type PlayerData = DataService.PlayerData
type DailyQuest = DataService.DailyQuest
type Reward = DailyConfig.Reward
type Quest = DailyConfig.Quest

local Daily = DailyConfig

local DailyService = {}

local function today(): number
	return math.floor(Timing.now() / 86400)
end

local function statOf(data: PlayerData, stat: string): number
	return ((data.stats :: any)[stat] or 0) :: number
end

-- Pays a Config.Daily reward. `sku` names it for Analytics.
local function grant(player: Player, data: PlayerData, reward: Reward, sku: string)
	if reward.spins then
		data.spins += reward.spins
	end
	if reward.luck then
		data.luckCharge = math.max(data.luckCharge, reward.luck)
	end
	if reward.cashMinutes then
		local amount =
			math.max(Daily.cashFloor, math.floor(EconomyService.rate(player) * reward.cashMinutes * 60))
		EconomyService.grant(player, amount, sku, "TimedReward")
	end
	if reward.growthMinutes then
		local now = Timing.now()
		data.boosts.growth = math.max(data.boosts.growth or 0, now) + reward.growthMinutes * 60
	end
	DataService.markDirty(player)
end

local function newQuest(player: Player, data: PlayerData, quest: Quest): DailyQuest
	local goal = quest.goal or 1
	if quest.goalIncomeMinutes then
		goal = math.max(1_000, math.floor(EconomyService.rate(player) * quest.goalIncomeMinutes * 60))
	end
	return { id = quest.id, goal = goal, base = statOf(data, quest.stat), done = false }
end

-- Picks a quest not already in the list (weighted), from a per-player-per-day seed.
local function pick(rng: Random, exclude: { [string]: boolean }): Quest?
	local total = 0
	for _, quest in Daily.quests do
		if not exclude[quest.id] then
			total += quest.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, quest in Daily.quests do
		if not exclude[quest.id] then
			roll -= quest.weight
			if roll <= 0 then
				return quest
			end
		end
	end
	return nil
end

-- Gives today's quests if the player still has yesterday's (or none).
local function ensureToday(player: Player, data: PlayerData)
	local day = today()
	local daily = data.daily
	if daily.questDay == day then
		return
	end
	local rng = Random.new(player.UserId * 1000 + day)
	local chosen: { [string]: boolean } = {}
	daily.quests = {}
	for _ = 1, Daily.questsPerDay do
		local quest = pick(rng, chosen)
		if quest then
			chosen[quest.id] = true
			table.insert(daily.quests, newQuest(player, data, quest))
		end
	end
	daily.questDay = day
	daily.rerolls = 0
	daily.bonusPaid = false
	DataService.markDirty(player)
end

local function questText(entry: DailyQuest): string
	local quest = Daily.questsById[entry.id]
	local goal = if quest.stat == "earned" then Format.cash(entry.goal) else tostring(entry.goal)
	return (quest.text:gsub("{goal}", goal))
end

-- The day in the 7-day cycle the next claim pays (1..7).
local function nextStreakDay(data: PlayerData): number
	local daily = data.daily
	local continuing = daily.loginDay == today() - 1 or daily.loginDay == today()
	local streak = if continuing then daily.streak else 0
	if daily.loginDay == today() then
		return ((streak - 1) % #Daily.streak) + 1 -- already claimed: show today's
	end
	return (streak % #Daily.streak) + 1
end

local function claimLogin(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local daily = data.daily
	local day = today()
	if daily.loginDay == day then
		Net.notify(player, "Already claimed today. Come back tomorrow!", "info")
		return
	end
	local index = nextStreakDay(data)
	daily.streak = if daily.loginDay == day - 1 then daily.streak + 1 else 1
	daily.loginDay = day
	local reward = Daily.streak[index]
	grant(player, data, reward, `DailyLogin{index}`)
	Net.notify(player, `Day {index} reward: {Daily.rewardText(reward)}!`, "rare")
	Analytics.event(player, "DailyLogin", daily.streak, { tostring(index) })
end

local function reroll(player: Player, index: any)
	local data = DataService.get(player)
	if data == nil or typeof(index) ~= "number" then
		return
	end
	ensureToday(player, data)
	local daily = data.daily
	local entry = daily.quests[index]
	if entry == nil or entry.done or daily.rerolls >= Daily.rerollsPerDay then
		return
	end
	local exclude: { [string]: boolean } = {}
	for _, other in daily.quests do
		exclude[other.id] = true
	end
	local quest = pick(Random.new(), exclude)
	if quest == nil then
		return
	end
	daily.quests[index] = newQuest(player, data, quest)
	daily.rerolls += 1
	DataService.markDirty(player)
end

local function checkQuests(player: Player, data: PlayerData)
	ensureToday(player, data)
	local daily = data.daily
	local allDone = #daily.quests > 0
	for _, entry in daily.quests do
		local quest = Daily.questsById[entry.id]
		if quest and not entry.done and statOf(data, quest.stat) - entry.base >= entry.goal then
			entry.done = true
			grant(player, data, quest.reward, `DailyQuest_{quest.id}`)
			Net.notify(
				player,
				`Daily quest done: {questText(entry)}! +{Daily.rewardText(quest.reward)}`,
				"rare"
			)
			Analytics.event(player, "DailyQuest", 1, { quest.id })
		end
		allDone = allDone and entry.done
	end
	if allDone and not daily.bonusPaid then
		daily.bonusPaid = true
		grant(player, data, Daily.allDoneBonus, "DailyBonus")
		Net.notify(player, `All daily quests done! Bonus: {Daily.rewardText(Daily.allDoneBonus)}`, "rare")
	end
end

-- The Daily menu's view of a player's streak and quests (StateService).
function DailyService.snapshot(player: Player, data: PlayerData): { [string]: any }
	ensureToday(player, data)
	local daily = data.daily
	local quests = {}
	for _, entry in daily.quests do
		local quest = Daily.questsById[entry.id]
		if quest then
			table.insert(quests, {
				text = questText(entry),
				progress = math.clamp(statOf(data, quest.stat) - entry.base, 0, entry.goal),
				goal = entry.goal,
				done = entry.done,
				reward = Daily.rewardText(quest.reward),
			})
		end
	end
	return {
		claimable = daily.loginDay ~= today(),
		streakDay = nextStreakDay(data),
		streak = if daily.loginDay >= today() - 1 then daily.streak else 0,
		quests = quests,
		rerollsLeft = math.max(0, Daily.rerollsPerDay - daily.rerolls),
		bonusPaid = daily.bonusPaid,
		resetsAt = (today() + 1) * 86400,
	}
end

-- Studio testing: pretend a day passed (the login reward and new quests come back).
function DailyService.debugNextDay(player: Player)
	local data = DataService.get(player)
	if data then
		local daily = data.daily
		if daily.loginDay > 0 then
			daily.loginDay -= 1
		end
		daily.questDay = 0
		DataService.markDirty(player)
	end
end

function DailyService.start()
	Net.onRequest("ClaimDaily", claimLogin)
	Net.onRequest("RerollQuest", reroll)
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		ensureToday(player, data)
		if data.daily.loginDay ~= today() and data.onboarding >= 5 then
			task.delay(4, function()
				if player.Parent == Players then
					Net.notify(player, "🎁 Your daily reward is ready! Open Daily to claim it.", "rare")
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			for player, data in DataService.loadedPlayers() do
				local ok, problem = pcall(function(): any
					checkQuests(player, data)
					return nil
				end)
				if not ok then
					warn(`[DailyService] {player.Name}: {problem}`)
				end
			end
		end
	end)
end

return DailyService

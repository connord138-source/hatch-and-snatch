--!strict
-- Free rewards (GDD §9): codes, the Roblox group, Roblox Premium and rewarded ads.
--
--  * Codes (Config.Codes): each player redeems each code once (data.codes).
--  * Group: members earn a little more cash (EconomyService.bonusMultiplier) and
--    joining pays Luck Wheel spins once (data.groupRewarded). Checked on join and
--    when the player presses Join/Claim in the Shop.
--  * Premium: members earn a little more cash. Roblox pays Premium Payouts for the
--    time Premium members spend in the game, so this is worth keeping generous.
--  * Rewarded video ads: the "AdBoost" developer product, ×2 cash for 15 minutes a
--    watch. Roblox only serves ads once the game qualifies (public, 2k+ monthly
--    visitors, ID-verified owner); until then the client never shows the button.
local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)

type PlayerData = DataService.PlayerData

local Tuning = Config.Monetization.tuning
local Codes = Config.Codes

local CODE_COOLDOWN = 2 -- seconds between one player's code attempts

local RewardsService = {}

local lastCodeAttempt: { [Player]: number } = {}
local busy: { [Player]: boolean } = {} -- a group check or an ad is in progress

local function percent(multiplier: number): number
	return math.round((multiplier - 1) * 100)
end

-- `expires` is a UTC date, "YYYY-MM-DD"; a malformed one counts as expired.
local function expired(expires: string?): boolean
	if expires == nil then
		return false
	end
	local year, month, day = expires:match("^(%d+)-(%d+)-(%d+)$")
	if year == nil then
		return true
	end
	local at = DateTime.fromUniversalTime(
		tonumber(year) :: number,
		tonumber(month) :: number,
		tonumber(day) :: number
	)
	return os.time() >= at.UnixTimestamp
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------

local function redeem(player: Player, raw: any)
	if typeof(raw) ~= "string" or #raw > 40 then
		return
	end
	local now = os.clock()
	if now - (lastCodeAttempt[player] or 0) < CODE_COOLDOWN then
		Net.notify(player, "One code at a time. Try again in a second.", "bad")
		return
	end
	lastCodeAttempt[player] = now
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local key = (raw:gsub("%s", "")):upper()
	local entry = Codes.byCode[key]
	if entry == nil then
		Net.notify(player, "That code doesn't exist.", "bad")
		return
	elseif expired(entry.expires) then
		Net.notify(player, "That code has expired.", "bad")
		return
	elseif data.codes[key] then
		Net.notify(player, "You already redeemed that code.", "bad")
		return
	end

	data.codes[key] = true
	local reward = entry.reward
	local parts: { string } = {}
	if reward.spins then
		data.spins += reward.spins
		table.insert(parts, `{reward.spins} Luck Wheel spins`)
	end
	if reward.luck then
		data.luckCharge = math.max(data.luckCharge, reward.luck)
		table.insert(parts, `×{reward.luck} luck on your next egg`)
	end
	if reward.cash then
		EconomyService.grant(player, reward.cash, `Code_{key}`)
		table.insert(parts, Format.cash(reward.cash))
	end
	if reward.essence then
		for biomeId, amount in reward.essence do
			data.essence[biomeId] = (data.essence[biomeId] or 0) + amount
			table.insert(parts, `{amount} {Config.Zones.byBiome[biomeId].essence}`)
		end
	end
	Net.notify(player, `Code redeemed: {table.concat(parts, ", ")}!`, "rare")
	Analytics.event(player, "CodeRedeemed", 1, { key })
	DataService.markDirty(player)
end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------

local function rewardGroup(player: Player, data: PlayerData)
	if data.groupRewarded then
		return
	end
	data.groupRewarded = true
	data.spins += Tuning.group.spins
	Net.notify(
		player,
		`Thanks for joining the group! +{Tuning.group.spins} Luck Wheel spins and +{percent(Tuning.group.cash)}% cash.`,
		"rare"
	)
	Analytics.event(player, "GroupReward")
	DataService.markDirty(player)
end

-- The Shop's Join/Claim button: the client shows Roblox's join prompt first, then asks.
local lastGroupCheck: { [Player]: number } = {}
local GROUP_CHECK_COOLDOWN = 10

local function claimGroup(player: Player)
	if busy[player] or Tuning.group.id == 0 then
		return
	end
	-- Each claim asks Roblox's web API, so not more often than every few seconds
	if os.clock() - (lastGroupCheck[player] or -math.huge) < GROUP_CHECK_COOLDOWN then
		Net.notify(player, "Give it a few seconds, then try again.", "info")
		return
	end
	lastGroupCheck[player] = os.clock()
	busy[player] = true
	local member = MonetizationService.checkGroup(player)
	busy[player] = nil
	local data = DataService.get(player)
	if data == nil then
		return
	end
	if member == nil then
		Net.notify(player, "Couldn't check the group right now. Try again in a moment.", "bad")
	elseif not member then
		Net.notify(player, "Join the group first, then claim.", "bad")
	elseif data.groupRewarded then
		Net.notify(player, `Group perk active: +{percent(Tuning.group.cash)}% cash.`, "info")
	else
		rewardGroup(player, data)
	end
	DataService.markDirty(player) -- the Shop shows the member perk
end

---------------------------------------------------------------------------
-- Rewarded video ads
---------------------------------------------------------------------------

local function watchAd(player: Player)
	local product = Config.Monetization.productsByKey.AdBoost
	if product == nil or product.id == 0 or busy[player] then
		return
	end
	busy[player] = true
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(product.id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	busy[player] = nil
	if player.Parent ~= Players then
		return
	end
	-- A finished ad pays through ProcessReceipt (the AdBoost handler below). Roblox
	-- reports most failures (no ad ready, an internal error) as a result, not an error.
	if ok and result == Enum.ShowAdResult.ShowCompleted then
		return
	elseif ok and result == Enum.ShowAdResult.ShowInterrupted then
		Net.notify(player, "The ad didn't finish, so no boost this time.", "bad")
	else
		Net.notify(player, "No ad to show right now. Try again later.", "bad")
	end
end

function RewardsService.start()
	Net.onRequest("RedeemCode", redeem)
	Net.onRequest("ClaimGroup", claimGroup)
	Net.onRequest("WatchAd", watchAd)

	-- Granted through ProcessReceipt once the ad has been watched to the end
	MonetizationService.onProduct("AdBoost", function(player, data)
		local tune = Tuning.adBoost
		local now = Timing.now()
		local from = math.max(data.boosts.cash or 0, now)
		data.boosts.cash = math.min(from + tune.minutes * 60, now + tune.maxMinutes * 60)
		Net.notify(
			player,
			`📺 Thanks for watching! ×{tune.multiplier} cash for {Format.duration(data.boosts.cash - now)}.`,
			"rare"
		)
		Analytics.event(player, "AdWatched")
	end)

	DataService.loaded:connect(function(player: Player, data: PlayerData)
		task.spawn(function()
			if MonetizationService.checkGroup(player) then
				rewardGroup(player, data)
				DataService.markDirty(player)
			end
		end)
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		if MonetizationService.isPremium(player) then
			Net.notify(player, `Premium perk: +{percent(Tuning.premiumCash)}% cash!`, "rare")
		end
		DataService.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCodeAttempt[player] = nil
		lastGroupCheck[player] = nil
		busy[player] = nil
	end)
end

return RewardsService

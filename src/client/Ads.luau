--!strict
-- Rewarded video ads: whether Roblox can show this player one right now. Checked
-- every minute once the AdBoost product has a Creator Hub id; the Shop and HUD show
-- their "Watch an ad" button only while `Ads.available` is true. Roblox only serves
-- ads once the game qualifies (see RewardsService), so until then it stays false.
local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.ClientState)

local CHECK_SECONDS = 60

local Ads = {
	available = false,
}

local function check()
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	Ads.available = ok and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

-- Asks the server to show an ad; the reward arrives as a toast once it's watched.
function Ads.watch()
	if not Ads.available then
		return
	end
	Ads.available = false
	ClientState.request("WatchAd")
	task.delay(5, check)
end

function Ads.start()
	local product = Config.Monetization.productsByKey.AdBoost
	if product == nil or product.id == 0 then
		return
	end
	while true do
		check()
		task.wait(CHECK_SECONDS)
	end
end

return Ads

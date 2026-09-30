--!strict
-- Game passes and developer products (Config.Monetization, GDD §9).
--
--  * Passes: ownership is asked of Roblox when a player joins (and cached), plus
--    anything bought or granted this session (data.passes). Other services ask
--    MonetizationService.hasPass(player, key).
--  * Products: MarketplaceService.ProcessReceipt → DataService.processPurchase,
--    which grants each receipt exactly once and only confirms it to Roblox after
--    the save that records it.
--  * Server Luck: a server-wide Epic+ odds multiplier with a timer, announced to
--    everyone; eggs rolled while it runs use it (MonetizationService.serverLuck).
--  * Free perks: Roblox Premium and Roblox group membership (checked on join and
--    when the player asks, see RewardsService).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)

type PlayerData = DataService.PlayerData

local Monetization = Config.Monetization
local Tuning = Monetization.tuning

local MonetizationService = {
	-- (player, passKey) — a pass became owned (bought, granted or found on join)
	passAdded = Signal.new(),
}

local owned: { [Player]: { [string]: boolean } } = {}
local groupMembers: { [Player]: boolean } = {}
local debugPerks: { [Player]: { [string]: boolean } } = {} -- StudioDebug "perk"

local luckUntil = 0 -- Workspace:GetServerTimeNow() when Server Luck runs out
local luckMultiplier = 1

-- Product effects: key → function(player, data) that changes the player's data.
-- Filled in by the services that own each effect (see MonetizationService.onProduct).
local productHandlers: { [string]: (Player, PlayerData) -> () } = {}

function MonetizationService.hasPass(player: Player, key: string): boolean
	local set = owned[player]
	if set and set[key] then
		return true
	end
	local data = DataService.get(player)
	return data ~= nil and data.passes[key] == true
end

-- Marks a pass owned (a purchase this session, a debug grant) and tells listeners.
function MonetizationService.grantPass(player: Player, key: string)
	if Monetization.passesByKey[key] == nil or MonetizationService.hasPass(player, key) then
		return
	end
	owned[player] = owned[player] or {}
	owned[player][key] = true
	local data = DataService.get(player)
	if data then
		data.passes[key] = true
		DataService.markDirty(player)
	end
	MonetizationService.passAdded:fire(player, key)
end

local function debugPerk(player: Player, perk: string): boolean
	local perks = debugPerks[player]
	return perks ~= nil and perks[perk] == true
end

function MonetizationService.isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium or debugPerk(player, "premium")
end

-- Whether the player is in the game's Roblox group (as of the last check).
function MonetizationService.inGroup(player: Player): boolean
	return groupMembers[player] == true or debugPerk(player, "group")
end

-- Studio testing: pretend the player has Premium ("premium") or is in the group ("group").
function MonetizationService.setDebugPerk(player: Player, perk: string, on: boolean)
	debugPerks[player] = debugPerks[player] or {}
	debugPerks[player][perk] = on
	DataService.markDirty(player)
end

-- Asks Roblox whether the player is in the group now (yields). Returns the answer,
-- or nil when there's no group set up or the check failed.
function MonetizationService.checkGroup(player: Player): boolean?
	local groupId = Tuning.group.id
	if groupId == 0 then
		return nil
	end
	local ok, member = pcall(player.IsInGroupAsync, player, groupId)
	if not ok then
		return nil
	end
	if player.Parent == Players then
		groupMembers[player] = member
	end
	return member
end

-- The pass keys a player owns, for the client's Shop.
function MonetizationService.ownedPasses(player: Player): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, pass in Monetization.passes do
		if MonetizationService.hasPass(player, pass.key) then
			result[pass.key] = true
		end
	end
	return result
end

-- Registers what a developer product does. `grant` runs once per receipt, inside
-- the save-confirmed purchase flow, so it must only change the player's data (and
-- world state that's fine to repeat, like announcements).
function MonetizationService.onProduct(key: string, grant: (Player, PlayerData) -> ())
	productHandlers[key] = grant
end

-- Runs a product's effect without a purchase (Studio testing).
function MonetizationService.grantProduct(player: Player, key: string): boolean
	local handler = productHandlers[key]
	local data = DataService.get(player)
	if handler == nil or data == nil then
		return false
	end
	handler(player, data)
	DataService.markDirty(player)
	return true
end

---------------------------------------------------------------------------
-- Server Luck
---------------------------------------------------------------------------

-- The server-wide Epic+ odds multiplier right now (1 when none is running).
function MonetizationService.serverLuck(): number
	if Workspace:GetServerTimeNow() >= luckUntil then
		return 1
	end
	return luckMultiplier
end

local function publishLuck()
	Workspace:SetAttribute("ServerLuck", MonetizationService.serverLuck())
	Workspace:SetAttribute("ServerLuckUntil", luckUntil)
end

-- Adds a Server Luck purchase: more time and a higher multiplier, announced to all.
function MonetizationService.boostServerLuck(buyer: Player)
	local tune = Tuning.serverLuck
	local now = Workspace:GetServerTimeNow()
	if now >= luckUntil then
		luckMultiplier = 1
		luckUntil = now
	end
	luckMultiplier = math.min(luckMultiplier + 1, tune.maxMultiplier)
	luckUntil = math.min(luckUntil + tune.minutes * 60, now + tune.maxMinutes * 60)
	publishLuck()
	local minutes = math.ceil((luckUntil - now) / 60)
	Net.announce(
		`🍀 {buyer.DisplayName} boosted the server: ×{luckMultiplier} luck for {minutes} min!`,
		Color3.fromRGB(120, 255, 140)
	)
end

---------------------------------------------------------------------------
-- Purchases
---------------------------------------------------------------------------

local function productByAssetId(assetId: number): typeof(Monetization.products[1])?
	for _, product in Monetization.products do
		if product.id == assetId and product.id ~= 0 then
			return product
		end
	end
	return nil
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productByAssetId(receipt.ProductId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product == nil then
		warn(`[MonetizationService] receipt for unknown product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local handler = productHandlers[product.key]
	if handler == nil then
		warn(`[MonetizationService] no handler for product {product.key}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- The data may still be loading if they bought right after joining
	local deadline = os.clock() + 20
	while DataService.get(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local decision = DataService.processPurchase(player, tostring(receipt.PurchaseId), function(data)
		handler(player, data)
	end)
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		DataService.markDirty(player)
	end
	return decision
end

local function checkPasses(player: Player)
	for _, pass in Monetization.passes do
		if pass.id ~= 0 then
			local ok, has =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			if ok and has then
				MonetizationService.grantPass(player, pass.key)
			end
		end
	end
	local data = DataService.get(player)
	if data then
		for key in data.passes do
			if not (owned[player] and owned[player][key]) then
				owned[player] = owned[player] or {}
				owned[player][key] = true
				MonetizationService.passAdded:fire(player, key)
			end
		end
	end
end

function MonetizationService.start()
	MonetizationService.onProduct("ServerLuck", function(player)
		MonetizationService.boostServerLuck(player)
	end)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in Monetization.passes do
			if pass.id == passId and pass.id ~= 0 then
				MonetizationService.grantPass(player, pass.key)
				Net.notify(player, `Thanks! {pass.name} is yours.`, "rare")
			end
		end
	end)
	DataService.loaded:connect(function(player: Player)
		task.spawn(checkPasses, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		groupMembers[player] = nil
		debugPerks[player] = nil
	end)
	publishLuck()
	-- Tell clients when Server Luck ends
	task.spawn(function()
		while true do
			task.wait(5)
			if Workspace:GetAttribute("ServerLuck") ~= MonetizationService.serverLuck() then
				publishLuck()
			end
		end
	end)
end

return MonetizationService

--!strict
-- Game passes and developer products (MonetizationService). The rule from the GDD:
-- everything that matters can be earned; Robux buys speed, convenience,
-- protection or cosmetics.
--
-- `id` is the asset id from Creator Hub (the experience → Monetization → Passes /
-- Developer Products). Anything with id 0 hasn't been created yet and stays out of
-- the Shop. Prices are what to set in Creator Hub (Robux); the Shop shows them.
export type Pass = {
	key: string,
	id: number,
	name: string,
	price: number,
	description: string,
}
export type Product = {
	key: string,
	id: number,
	name: string,
	price: number,
	description: string,
	shop: boolean?, -- false = not sold in the Shop (the rewarded-ad reward)
}

local passes: { Pass } = {
	{
		key = "DoubleCash",
		id = 2002052639,
		name = "2× Cash",
		price = 249,
		description = "Every creature you own earns double cash, forever.",
	},
	{
		key = "VIP",
		id = 2002946469,
		name = "VIP",
		price = 349,
		description = "A gold VIP tag over your base, +10 creature storage and +10% cash.",
	},
	{
		key = "AutoCollect",
		id = 2002826495,
		name = "Auto-Collect",
		price = 149,
		description = "Your earnings go straight into your wallet. No more stepping on the pad.",
	},
	{
		key = "ExtraNursery",
		id = 2002112636,
		name = "Extra Nursery",
		price = 99,
		description = "+1 protected nursery slot at every base level.",
	},
	{
		key = "LongerLock",
		id = 2002466629,
		name = "Longer Lock",
		price = 99,
		description = "Your base's laser lock stays up twice as long.",
	},
	{
		key = "OfflinePlus",
		id = 2003048495,
		name = "Offline +8h",
		price = 79,
		description = "Keep earning while you're away for up to 16 hours instead of 8.",
	},
}

local products: { Product } = {
	{
		key = "ServerLuck",
		id = 3715650749,
		name = "Server Luck",
		price = 99,
		description = "Doubles Epic+ odds on every egg for everyone in the server for 15 minutes, "
			.. "and your name is announced. Buying again while it runs adds 15 minutes and raises it "
			.. "to ×3, ×4, up to ×5.",
	},
	{
		key = "GrowthElixir",
		id = 3715650875,
		name = "Growth Elixir",
		price = 49,
		description = "All your creatures grow twice as fast for 30 minutes (on top of walking).",
	},
	{
		key = "SkipHatch",
		id = 3715650974,
		name = "Skip Hatch",
		price = 29,
		description = "Every egg in your incubators hatches right now (with none incubating, your next egg hatches instantly).",
	},
	{
		key = "CashSmall",
		id = 3715651058,
		name = "Cash Pouch",
		price = 29,
		description = "10 minutes of your income, at least $1,000.",
	},
	{
		key = "CashLarge",
		id = 3715651167,
		name = "Cash Chest",
		price = 149,
		description = "90 minutes of your income, at least $10,000.",
	},
	{
		-- The rewarded video ad's reward (Roblox grants ad rewards as a developer
		-- product, and they can't be random). Not sold in the Shop.
		key = "AdBoost",
		id = 3715651304,
		name = "Ad Boost",
		price = 5,
		description = "2× cash for 15 minutes.",
		shop = false,
	},
}

local Monetization = {
	passes = passes,
	products = products,
	passesByKey = {} :: { [string]: Pass },
	productsByKey = {} :: { [string]: Product },

	tuning = {
		doubleCash = 2,
		vipCash = 1.1,
		vipStorage = 10,
		extraNursery = 1,
		lockMultiplier = 2,
		offlineBonusSeconds = 8 * 60 * 60,
		-- Server Luck: each purchase adds `minutes` (up to `maxMinutes` left) and
		-- +1 to the multiplier (starting at ×2, up to `maxMultiplier`). Resets to ×1
		-- when it runs out.
		serverLuck = { minutes = 15, maxMinutes = 60, maxMultiplier = 5 },
		growthElixir = { minutes = 30, multiplier = 2 },
		cashSmall = { minutes = 10, minimum = 1_000 },
		cashLarge = { minutes = 90, minimum = 10_000 },
		-- Free perks
		premiumCash = 1.1, -- Roblox Premium members (more Premium playtime → Premium Payouts)
		-- The Roblox group: `id` 0 until the group exists. Members earn `cash` more;
		-- joining pays `spins` once.
		group = { id = 0, cash = 1.05, spins = 3 },
		-- Rewarded video ad: each watch adds `minutes` of ×`multiplier` cash, up to
		-- `maxMinutes` banked.
		adBoost = { minutes = 15, maxMinutes = 60, multiplier = 2 },
	},
}

for _, pass in passes do
	Monetization.passesByKey[pass.key] = pass
end
for _, product in products do
	Monetization.productsByKey[product.key] = product
end

return Monetization

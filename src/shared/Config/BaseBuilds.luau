--!strict
-- What a base looks like as it grows, and what can be bought for it (owner,
-- 2026-10-01: "should start to resemble a fortress with quite a few upgradeable
-- and buyable features and props, as well as security measures").
--
--  * `tiers`: the fortress around the plot follows the base level, free with each
--    upgrade: a fenced camp, a log stockade, a stone keep, a towered fortress and
--    a white-and-gold citadel. Only the camp's fence can be stepped over; from the
--    stockade up, walls are too tall to jump and the gate is the way in.
--  * `items`: bought once each in the Base menu, shown in fixed spots. Decor is
--    looks only. Security items all run on a timer or recharge, so no base is
--    ever fully closed: a patient thief can always wait one out (owner's rule).
--
-- Costs sit between the base level prices (60K, 25M, 5B, 500B) so each level
-- opens a few things worth saving for without slowing the next upgrade much.

export type Tier = {
	name: string,
	description: string, -- what the next upgrade adds, for the Base menu
}

-- A hiding spot: a prop in the base that holds one creature out of sight. Bought
-- in order. Thieves can search any spot (empty ones are decoys), and Mythic and
-- rarer creatures give themselves away with the odd sparkle, so a hidden
-- ultra-rare is never safe for good (owner, 2026-10-01).
export type HidingSpot = {
	name: string,
	prop: string, -- WorldProps model (a part-built stand-in otherwise)
	cost: number,
	baseLevel: number,
	empty: string, -- what a thief finds in an empty one
}

export type Item = {
	id: string,
	name: string,
	kind: "Decor" | "Security",
	cost: number,
	baseLevel: number, -- needs this base level
	floors: number?, -- needs this many floors (1 = ground only)
	description: string,
	-- Security timers, in seconds (StealService)
	active: number?, -- how long it holds once triggered
	recharge: number?, -- downtime after it ends before it can fire again
}

local tiers: { Tier } = {
	{ name = "Camp", description = "a picket fence, a timber gate and torches" },
	{ name = "Stockade", description = "log palisade walls too tall to jump and wooden watchtowers" },
	{ name = "Keep", description = "stone walls with battlements, stone towers and a gatehouse" },
	{ name = "Fortress", description = "tall walls, four roofed towers with flags and braziers" },
	{ name = "Citadel", description = "white-and-gold walls, crystal-tipped spires and royal banners" },
}

local items: { Item } = {
	-- Decor
	{
		id = "CampSupplies",
		name = "Camp Supplies",
		kind = "Decor",
		cost = 15_000,
		baseLevel = 1,
		description = "Crates, barrels and hay bales by the incubators",
	},
	{
		id = "WallTorches",
		name = "Wall Torches",
		kind = "Decor",
		cost = 40_000,
		baseLevel = 1,
		description = "Burning torches along your walls that light the base at night",
	},
	{
		id = "Campfire",
		name = "Campfire",
		kind = "Decor",
		cost = 150_000,
		baseLevel = 1,
		description = "A crackling campfire ringed with stones and log seats",
	},
	{
		id = "FlowerPlanters",
		name = "Flower Planters",
		kind = "Decor",
		cost = 600_000,
		baseLevel = 2,
		description = "Planter boxes of flowers along the front wall",
	},
	{
		id = "Banners",
		name = "Banners",
		kind = "Decor",
		cost = 2_500_000,
		baseLevel = 2,
		description = "Long banners in your theme's colors hanging from the walls",
	},
	{
		id = "TrainingYard",
		name = "Training Yard",
		kind = "Decor",
		cost = 8_000_000,
		baseLevel = 2,
		description = "Straw training dummies and a weapon rack",
	},
	{
		id = "StoneWell",
		name = "Stone Well",
		kind = "Decor",
		cost = 40_000_000,
		baseLevel = 3,
		description = "A stone well with a little roof and a bucket",
	},
	{
		id = "LanternPath",
		name = "Lantern Path",
		kind = "Decor",
		cost = 150_000_000,
		baseLevel = 3,
		description = "Lantern posts lighting the path up to your gate",
	},
	{
		id = "Fountain",
		name = "Fountain",
		kind = "Decor",
		cost = 900_000_000,
		baseLevel = 3,
		description = "A tiered stone fountain in front of your walls",
	},
	{
		id = "GuardianStatues",
		name = "Guardian Statues",
		kind = "Decor",
		cost = 4_000_000_000,
		baseLevel = 4,
		description = "Stone statues of your two rarest creatures flanking the gate",
	},
	{
		id = "Moat",
		name = "Moat & Drawbridge",
		kind = "Decor",
		cost = 30_000_000_000,
		baseLevel = 4,
		description = "Water around your walls and a drawbridge at the gate",
	},
	{
		id = "RoyalTrim",
		name = "Royal Gold Trim",
		kind = "Decor",
		cost = 350_000_000_000,
		baseLevel = 5,
		description = "Gold-trimmed battlements and glowing crystals on every tower",
	},

	-- Security: every one of these runs on a timer or a recharge
	{
		id = "SpikeStrip",
		name = "Spike Strip",
		kind = "Security",
		cost = 5_000_000,
		baseLevel = 2,
		description = "Spikes at your gate catch the first intruder for 1.5 s, then take 40 s to reset",
		active = 1.5,
		recharge = 40,
	},
	{
		id = "Searchlight",
		name = "Searchlight Tower",
		kind = "Security",
		cost = 400_000_000,
		baseLevel = 3,
		description = "A thief who runs off with your creature is lit up and marked for everyone for 10 s (30 s recharge)",
		active = 10,
		recharge = 30,
	},
	{
		id = "RampGates",
		name = "Ramp Gates",
		kind = "Security",
		cost = 6_000_000_000,
		baseLevel = 3,
		floors = 2,
		description = "Hold E at the gate lever to bar both ramps for 45 s, so nobody gets up or down (90 s recharge)",
		active = 45,
		recharge = 90,
	},
	{
		id = "NetBallista",
		name = "Net Ballista",
		kind = "Security",
		cost = 40_000_000_000,
		baseLevel = 4,
		description = "Hold E at the ballista to net the nearest thief carrying your creature within 80 studs: they drop it (2 min recharge)",
		recharge = 120,
	},
}

local hidingSpots: { HidingSpot } = {
	{
		name = "Haystack",
		prop = "HideHaystack",
		cost = 3_000_000,
		baseLevel = 2,
		empty = "Nothing in there but hay!",
	},
	{
		name = "Barrel Pile",
		prop = "HideBarrels",
		cost = 300_000_000,
		baseLevel = 3,
		empty = "Just empty barrels.",
	},
	{
		name = "Hedge",
		prop = "HideHedge",
		cost = 8_000_000_000,
		baseLevel = 4,
		empty = "Only leaves and a startled beetle.",
	},
	{
		name = "Secret Chest",
		prop = "HideChest",
		cost = 150_000_000_000,
		baseLevel = 5,
		empty = "The chest is empty. Sneaky!",
	},
}

local byId: { [string]: Item } = {}
for _, item in items do
	byId[item.id] = item
end

return table.freeze({
	tiers = tiers,
	items = items,
	byId = byId,
	hidingSpots = hidingSpots,
	searchSeconds = 3, -- the hold to search a hiding spot (the same for every spot)
	tellRarityOrder = 6, -- Mythic (Config.Rarities order) and up sparkle from hiding
	tellEverySeconds = 12, -- about how often they give themselves away
	padHoldSeconds = 0.6, -- stand on a buy pad this long to buy (no buying by walking past)
	ballistaRange = 80,
	searchlightRange = 300, -- how far the marker shows
})

--!strict
-- Roblox Analytics (Creator Hub → the experience → Analytics). Every event the game
-- logs goes through here so names stay consistent:
--  * Economy: each cash source and sink (EconomyService.spend/grant and collecting),
--    tagged with a transaction type and an item SKU.
--  * Onboarding funnel: the first-session steps in ONBOARDING, each logged once per
--    player (data.onboarding remembers how far they got).
--  * Progression: Hatcher Level and base level.
--  * Custom: hatches by rarity, steals, rebirths, codes, group and ad rewards.
-- A failing analytics call never breaks gameplay.
local AnalyticsService = game:GetService("AnalyticsService")

-- Enum.AnalyticsEconomyTransactionType names
export type Transaction = "Shop" | "IAP" | "Gameplay" | "TimedReward" | "Onboarding" | "ContextualPurchase"

local Analytics = {}

Analytics.ONBOARDING = {
	"Joined",
	"Bought an egg",
	"Placed an egg",
	"Hatched",
	"Collected cash",
	"Upgraded base",
}

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local warned = false
local function safely(log: () -> ())
	local ok, problem = pcall(function(): any
		log()
		return nil
	end)
	if not ok and not warned then
		warned = true
		warn(`[Analytics] logging failed (further failures are silent): {problem}`)
	end
end

-- Up to three strings for the custom-field filters in the dashboard. Keep their
-- values to small fixed sets (rarity names, biome ids): Roblox caps the combinations.
local function fields(values: { string }?): { [string]: string }?
	if values == nil then
		return nil
	end
	local result: { [string]: string } = {}
	for i, value in values do
		local key = FIELD_KEYS[i]
		if key then
			result[key] = value
		end
	end
	return result
end

function Analytics.cash(
	player: Player,
	source: boolean,
	amount: number,
	balance: number,
	transaction: Transaction,
	sku: string
)
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	safely(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			"Cash",
			amount,
			math.floor(balance),
			transaction,
			sku
		)
	end)
end

-- Marks onboarding step `step` (an index into ONBOARDING) as reached. Steps the
-- player skipped past are logged too, so the funnel never has holes.
function Analytics.onboard(player: Player, data: { onboarding: number }, step: number)
	if step <= data.onboarding or step > #Analytics.ONBOARDING then
		return
	end
	for i = data.onboarding + 1, step do
		safely(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, i, Analytics.ONBOARDING[i])
		end)
	end
	data.onboarding = step
end

-- A level reached on a progression path ("HatcherLevel", "BaseLevel").
function Analytics.progress(player: Player, path: string, level: number)
	safely(function()
		AnalyticsService:LogProgressionEvent(
			player,
			path,
			Enum.AnalyticsProgressionType.Complete,
			level,
			`Level {level}`
		)
	end)
end

function Analytics.event(player: Player, name: string, value: number?, values: { string }?)
	safely(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields(values))
	end)
end

return Analytics

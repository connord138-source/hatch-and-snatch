--!strict
-- Redeemable codes (Shop → Codes). Each player can redeem each code once. Codes are
-- matched without caring about case or spaces.
--
-- Like-goal codes: announce "at N likes we release a code" on the game page, then
-- add the code here when the goal is hit and publish. `expires` (optional) is a UTC
-- date, "YYYY-MM-DD"; the code stops working at the start of that day.
--
-- Rewards: `spins` (Luck Wheel), `luck` (next egg's luck charge, like the wheel),
-- `cash`, and `essence` per biome id.
export type Reward = {
	spins: number?,
	luck: number?,
	cash: number?,
	essence: { [string]: number }?,
}
export type Code = {
	code: string,
	reward: Reward,
	expires: string?,
}

local codes: { Code } = {
	{ code = "HATCH", reward = { spins = 3 } },
	{ code = "MOONEGG", reward = { luck = 3 } },
	{ code = "SNATCH", reward = { cash = 1_000 } },
}

local byCode: { [string]: Code } = {}
for _, entry in codes do
	byCode[entry.code:upper()] = entry
end

return {
	codes = codes,
	byCode = byCode,
}

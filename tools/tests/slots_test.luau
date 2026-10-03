-- Checks the pedestal slot layout (Config.Economy.slots / slotFloor / vaultOfSlot):
-- run with tools/tests/run_slots.sh.
local Economy = require("./Economy")
local T = Economy.tunables

local function check(ok: boolean, message: string)
	if not ok then
		error(message, 2)
	end
end

-- Ground only at level 1, every slot at the top
check(#Economy.slots(1, 1, 0) == 10, "level 1: 10 ground pedestals")
check(#Economy.slots(3, 1, 0) == 20, "level 3: 20 ground pedestals")
local all = Economy.slots(#T.baseLevels, #T.floors + 1, #T.vaults)
local floorSpots = 0
for _, floor in T.floors do
	floorSpots += floor.pedestals
end
check(#all == 20 + floorSpots + #T.vaults, "max base: ground + floors + vaults")
check(20 + floorSpots < Economy.vaultSlot(1), "the floors' slots stay below the vaults'")
local seen = {}
for _, slot in all do
	check(not seen[slot], `slot {slot} listed twice`)
	seen[slot] = true
end

-- Floors: 1-20 ground, then each floor's pedestals in turn (Second 21-29, Top
-- 30-38 with 9 each); vaults by their floor
for slot = 1, 20 do
	check(Economy.slotFloor(slot) == 1, `slot {slot} is on the ground`)
end
local first = 21
for i, floor in T.floors do
	for slot = first, first + floor.pedestals - 1 do
		check(Economy.slotFloor(slot) == i + 1, `slot {slot} is on floor {i + 1}`)
	end
	first += floor.pedestals
end
for vault, entry in T.vaults do
	local slot = Economy.vaultSlot(vault)
	check(Economy.vaultOfSlot(slot) == vault, `vault {vault} round-trips`)
	check(Economy.slotFloor(slot) == entry.floor, `vault {vault} is on floor {entry.floor}`)
	check(entry.floor <= #T.floors + 1, `vault {vault}'s floor exists`)
end
check(Economy.vaultOfSlot(first - 1) == nil and Economy.vaultOfSlot(nil) == nil, "open pedestals aren't vaults")

-- Buying order: each floor and vault costs more than the one before
for i = 2, #T.floors do
	check(T.floors[i].cost > T.floors[i - 1].cost, `floor {i + 1} costs more`)
end
for i = 2, #T.vaults do
	check(T.vaults[i].cost > T.vaults[i - 1].cost, `vault {i} costs more`)
end
-- A second-floor-only base has no top-floor slots
for _, slot in Economy.slots(5, 2, 2) do
	check(Economy.slotFloor(slot) <= 2, `slot {slot} needs the Top Floor`)
end
print("slots: layout, floors and vaults check out")

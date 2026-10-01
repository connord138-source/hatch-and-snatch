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
check(#all == 20 + 5 * #T.floors + #T.vaults, "max base: ground + floors + vaults")
local seen = {}
for _, slot in all do
	check(not seen[slot], `slot {slot} listed twice`)
	seen[slot] = true
end

-- Floors: 1-20 ground, 21-25 second, 26-30 top; vaults by their floor
for slot = 1, 20 do
	check(Economy.slotFloor(slot) == 1, `slot {slot} is on the ground`)
end
for slot = 21, 25 do
	check(Economy.slotFloor(slot) == 2, `slot {slot} is on the Second Floor`)
end
for slot = 26, 30 do
	check(Economy.slotFloor(slot) == 3, `slot {slot} is on the Top Floor`)
end
for vault, entry in T.vaults do
	local slot = Economy.vaultSlot(vault)
	check(Economy.vaultOfSlot(slot) == vault, `vault {vault} round-trips`)
	check(Economy.slotFloor(slot) == entry.floor, `vault {vault} is on floor {entry.floor}`)
	check(entry.floor <= #T.floors + 1, `vault {vault}'s floor exists`)
end
check(Economy.vaultOfSlot(25) == nil and Economy.vaultOfSlot(nil) == nil, "open pedestals aren't vaults")

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

-- Checks the Castle Designer config (Config.CastleDesigns): every preset and old
-- theme mapping names real options, every option but the stone's tier default has
-- a color, unlocks name real biomes, and resolve() gives each preset its own look.
-- Run with tools/tests/run_designs.sh.
local Designs = require("./CastleDesigns")
local Biomes = require("./Biomes")

local function check(ok: boolean, message: string)
	if not ok then
		error(message, 2)
	end
end

for _, slot in Designs.slots do
	check(Designs.options[slot.id][slot.default] ~= nil, `{slot.id}: default {slot.default} missing`)
	check(Designs.options[slot.id][slot.default].cost == 0, `{slot.id}: default must be free`)
	for _, option in slot.options do
		check(option.color ~= nil or (slot.id == "stone" and option.id == "Tier"), `{slot.id}.{option.id}: no color`)
		local unlock = option.unlock
		if unlock and unlock.biome then
			check(Biomes[unlock.biome] ~= nil, `{slot.id}.{option.id}: unknown biome {unlock.biome}`)
		end
		check(option.cost == 0 or unlock ~= nil, `{slot.id}.{option.id}: paid options need an unlock`)
	end
end

local looks = {}
for _, preset in Designs.presets do
	for _, slot in Designs.slots do
		check(preset.picks[slot.id] ~= nil, `{preset.id}: no {slot.id} pick`)
	end
	for slot, id in preset.picks do
		check(Designs.options[slot] and Designs.options[slot][id] ~= nil, `{preset.id}: unknown {slot}.{id}`)
	end
	local look = Designs.resolve(preset.picks)
	check(looks[look.id] == nil, `{preset.id} looks the same as {looks[look.id]}`)
	looks[look.id] = preset.id
end

for themeId, picks in Designs.fromTheme do
	for slot, id in picks do
		check(Designs.options[slot] and Designs.options[slot][id] ~= nil, `old theme {themeId}: unknown {slot}.{id}`)
	end
end

-- The Classic look keeps the imported tower models; a custom one builds its own
check(not Designs.resolve(Designs.defaults()).customTowers, "Classic should use the tower models")
check(Designs.resolve(Designs.presetsById.Ice.picks).customTowers == true, "Ice should build its own towers")

-- Unlocks
local progress = { unlockedBiome = 1, baseLevel = 1, floors = 1, vaults = 0, rebirths = 0 }
local function order(id: string): number
	return Biomes[id].order
end
check(Designs.unlocked(Designs.options.stone.Mossy, progress, order), "Mossy is open from the start")
check(not Designs.unlocked(Designs.options.stone.Ice, progress, order), "Ice needs the Frost Shelf")
check(not Designs.unlocked(Designs.options.roof.Rainbow, progress, order), "Rainbow needs a rebirth")

print(`designs: {#Designs.presets} presets and every option check out`)

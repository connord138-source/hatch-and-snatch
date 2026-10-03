--!strict
-- Base upgrades and themes (docs/GDD.md §6.1). Upgrading grows the plot (a longer
-- run for thieves), adds a row of ground pedestals and lengthens the laser lock.
-- Floors add a row of pedestals a story up and room for vaults (single rooms the
-- owner locks on a timer). Themes restyle the plot in a biome's look once that
-- biome is unlocked, or in a built-up look the floors and vaults unlock.
--
-- Every upgrade is bought by standing on a glowing pad in the base's front yard
-- (owner, 2026-10-01): base level, security, floors, vaults, hiding spots and the
-- decor and security items (Config.BaseBuilds). The Command Terminal opens the
-- Base menu for the rest: themes and switching decor on or off.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)
local BaseKit = require(script.Parent.Parent.BaseKit)

type PlayerData = DataService.PlayerData

local BaseService = {}

local function maxLevel(): number
	return #Config.Economy.tunables.baseLevels
end

-- The floor a base level makes buildable, if any.
local function floorOpenedAt(level: number): string?
	for _, floor in Config.Economy.tunables.floors do
		if floor.baseLevel == level then
			return floor.name
		end
	end
	return nil
end

type Offer = { key: string, title: string, cost: number }

local Designs = Config.CastleDesigns

-- The look the player's Castle Designer picks give their base.
local function lookOf(data: PlayerData): Config.BaseTheme
	return Designs.resolve(data.design)
end

local function biomeOrder(id: string): number
	local biome = Config.Biomes[id :: any]
	return if biome then biome.order else math.huge
end

local function progressOf(data: PlayerData): Config.DesignProgress
	return {
		unlockedBiome = data.unlockedBiome,
		baseLevel = data.baseLevel,
		floors = data.floors,
		vaults = data.vaults,
		rebirths = data.rebirths,
	}
end

local PAD_REACH = 2.6 -- how close to a pad's middle counts as standing on it

-- The owner's two rarest species, for the Guardian Statues.
local function rarestSpecies(data: PlayerData): { string }
	local best: { { species: string, value: number } } = {}
	for _, record in data.creatures do
		local value = Config.Economy.sellValue(CreatureService.stats(record))
		local known = false
		for _, entry in best do
			if entry.species == record.species then
				entry.value = math.max(entry.value, value)
				known = true
			end
		end
		if not known then
			table.insert(best, { species = record.species, value = value })
		end
	end
	table.sort(best, function(a, b)
		return a.value > b.value
	end)
	local list: { string } = {}
	for i = 1, math.min(2, #best) do
		table.insert(list, best[i].species)
	end
	return list
end

-- Decor and security items the player has, split by kind (decor they switched
-- off at the terminal stays off).
local function ownedBuilds(data: PlayerData): ({ [string]: boolean }, { [string]: boolean })
	local decor, security = {}, {}
	for id, owned in data.builds do
		local item = Config.BaseBuilds.byId[id]
		if owned and item then
			if item.kind == "Security" then
				security[id] = true
			elseif not data.hiddenBuilds[id] then
				decor[id] = true
			end
		end
	end
	return decor, security
end

-- What the pads offer right now: one pad each for the base level, security,
-- floors, vaults and hiding spots, then the three cheapest items available.
-- A pad whose next step isn't open yet (needs a higher base level) stays hidden.
local function offers(data: PlayerData): { Offer? }
	local tunables = Config.Economy.tunables
	local list: { Offer? } = {}
	local nextLevel = data.baseLevel + 1
	list[1] = if nextLevel <= maxLevel()
		then {
			key = "level",
			title = `Base Level {nextLevel}`,
			cost = Config.Economy.baseLevel(nextLevel).cost,
		}
		else nil
	local nextSecurity = tunables.securityLevels[data.security + 1]
	list[2] = if nextSecurity
		then { key = "security", title = nextSecurity.name, cost = nextSecurity.cost }
		else nil
	local floor = tunables.floors[data.floors]
	list[3] = if floor and data.baseLevel >= floor.baseLevel
		then { key = "floor", title = floor.name, cost = floor.cost }
		else nil
	local vault = tunables.vaults[data.vaults + 1]
	list[4] = if vault and data.floors >= vault.floor
		then { key = "vault", title = `Vault {data.vaults + 1}`, cost = vault.cost }
		else nil
	local hide = Config.BaseBuilds.hidingSpots[data.hides + 1]
	list[5] = if hide and data.baseLevel >= hide.baseLevel
		then { key = "hide", title = `Hiding Spot: {hide.name}`, cost = hide.cost }
		else nil
	local items: { Config.BaseBuild } = {}
	for _, item in Config.BaseBuilds.items do
		if
			not data.builds[item.id]
			and data.baseLevel >= item.baseLevel
			and data.floors >= (item.floors or 1)
		then
			table.insert(items, item)
		end
	end
	table.sort(items, function(a, b)
		return a.cost < b.cost
	end)
	for i = 1, 3 do
		local item = items[i]
		list[5 + i] = if item then { key = `build:{item.id}`, title = item.name, cost = item.cost } else nil
	end
	return list
end

local function refreshPads(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	local list = offers(data)
	for i, pad in plot.pads do
		local offer = list[i]
		if offer then
			BaseKit.setPad(pad, offer.key, offer.title, Format.cash(offer.cost), data.cash >= offer.cost)
		else
			BaseKit.setPad(pad, nil)
		end
	end
end

-- Pushes the player's level + theme onto their plot: walls, floors, nursery,
-- hiding spots, security fixtures, decor, pads and the terminal's screen.
local function apply(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	local theme = lookOf(data)
	WorldService.setLevel(plot, data.baseLevel)
	WorldService.setFloors(plot, data.floors, data.vaults)
	WorldService.applyTheme(plot, theme)
	WorldService.setNursery(plot, CreatureService.nurserySlots(data))
	WorldService.setHides(plot, data.hides)
	local decor, security = ownedBuilds(data)
	WorldService.setSecurity(plot, security, data.security >= 1)
	WorldService.setBuilds(plot, decor, theme, rarestSpecies(data))
	local vip = MonetizationService.hasPass(player, "VIP")
	plot.label.Text = if vip then `⭐ VIP · {player.DisplayName}'s Base` else `{player.DisplayName}'s Base`
	plot.label.TextColor3 = if vip then Color3.fromRGB(255, 215, 90) else Color3.new(1, 1, 1)
	local tunables = Config.Economy.tunables
	plot.terminalScreen.Text = table.concat({
		`{string.upper(Config.BaseBuilds.tiers[math.clamp(data.baseLevel, 1, #Config.BaseBuilds.tiers)].name)} · LV {data.baseLevel}/{maxLevel()}`,
		`FLOORS {data.floors}/{#tunables.floors + 1}  VAULTS {data.vaults}/{#tunables.vaults}`,
		`SECURITY {data.security}/{#tunables.securityLevels}  HIDES {data.hides}/{#Config.BaseBuilds.hidingSpots}`,
	}, "\n")
	refreshPads(player, data)
end

-- Re-applies a player's base (after a data change outside these functions).
BaseService.apply = apply

function BaseService.upgrade(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local nextLevel = data.baseLevel + 1
	if nextLevel > maxLevel() then
		Net.notify(player, "Your base is fully upgraded!", "info")
		return
	end
	local cost = Config.Economy.baseLevel(nextLevel).cost
	if not EconomyService.spend(player, cost, `BaseLevel{nextLevel}`) then
		Net.notify(player, `You need {Format.cash(cost)} to upgrade your base.`, "bad")
		return
	end
	data.baseLevel = nextLevel
	apply(player, data)
	Analytics.onboard(player, data, 6)
	Analytics.progress(player, "BaseLevel", nextLevel)
	local gain = Config.Economy.baseLevel(nextLevel).pedestals
		- Config.Economy.baseLevel(nextLevel - 1).pedestals
	local opens = floorOpenedAt(nextLevel)
	local gains = if gain > 0
		then `+{gain} pedestals and a bigger plot`
		else "a bigger plot and a longer lock"
	Net.notify(
		player,
		if opens
			then `Base upgraded to level {nextLevel}! {gains}, and the {opens} can be built (its pad is in your front yard).`
			else `Base upgraded to level {nextLevel}! {gains}.`,
		"rare"
	)
	ProgressionService.addXp(player, Config.Progression.xp.baseUpgradePerLevel * nextLevel)
	ProgressionService.bump(player, "baseUpgrades")
	ProgressionService.refresh(player) -- higher base levels open later biomes
	DataService.markDirty(player)
end

-- Castle Designer: picks an option for a slot, buying it first if needed (it has
-- to be unlocked: its biome, base progress or a rebirth).
function BaseService.designPick(player: Player, slot: any, id: any)
	if typeof(slot) ~= "string" or typeof(id) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local option = Designs.options[slot] and Designs.options[slot][id]
	if data == nil or option == nil then
		return
	end
	if not Designs.owns(data.ownedDesigns, slot, id) then
		local open, needs = Designs.unlocked(option, progressOf(data), biomeOrder)
		if not open then
			Net.notify(player, `{option.name} needs {needs} first.`, "bad")
			return
		end
		if not EconomyService.spend(player, option.cost, `Design_{slot}`) then
			Net.notify(player, `You need {Format.cash(option.cost)} for {option.name}.`, "bad")
			return
		end
		data.ownedDesigns[`{slot}:{id}`] = true
		Net.notify(player, `{option.name} unlocked for your castle!`, "rare")
	end
	data.design[slot] = id
	apply(player, data)
	DataService.markDirty(player)
end

-- Castle Designer: sets every slot from a preset, buying what it needs in one go
-- (all of it has to be unlocked).
function BaseService.designPreset(player: Player, presetId: any)
	if typeof(presetId) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local preset = Designs.presetsById[presetId]
	if data == nil or preset == nil then
		return
	end
	local total = 0
	local buying: { string } = {}
	for slot, id in preset.picks do
		local option = Designs.options[slot][id]
		if option and not Designs.owns(data.ownedDesigns, slot, id) then
			local open, needs = Designs.unlocked(option, progressOf(data), biomeOrder)
			if not open then
				Net.notify(player, `{preset.name} needs {needs} first ({option.name}).`, "bad")
				return
			end
			total += option.cost
			table.insert(buying, `{slot}:{id}`)
		end
	end
	if total > 0 and not EconomyService.spend(player, total, "DesignPreset") then
		Net.notify(player, `You need {Format.cash(total)} for {preset.name}.`, "bad")
		return
	end
	for _, key in buying do
		data.ownedDesigns[key] = true
	end
	for slot, id in preset.picks do
		data.design[slot] = id
	end
	apply(player, data)
	Net.notify(player, `{preset.name} applied!`, if total > 0 then "rare" else "info")
	DataService.markDirty(player)
end

-- Buys the next floor (needs its base level).
function BaseService.buyFloor(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local floor = Config.Economy.tunables.floors[data.floors] -- floors[1] is the Second Floor
	if floor == nil then
		Net.notify(player, "Your base has every floor!", "info")
		return
	end
	if data.baseLevel < floor.baseLevel then
		Net.notify(player, `The {floor.name} needs base level {floor.baseLevel}.`, "bad")
		return
	end
	if not EconomyService.spend(player, floor.cost, `Floor{data.floors + 1}`) then
		Net.notify(player, `You need {Format.cash(floor.cost)} for the {floor.name}.`, "bad")
		return
	end
	data.floors += 1
	apply(player, data)
	Analytics.progress(player, "Floor", data.floors)
	Net.notify(
		player,
		`{floor.name} built! +{floor.pedestals} pedestals up the ramp, and room for vaults. Move your rarest up there (Creatures menu).`,
		"rare"
	)
	ProgressionService.addXp(player, Config.Progression.xp.baseUpgradePerLevel * (data.floors + 2))
	DataService.markDirty(player)
end

-- Buys the next vault room (needs its floor).
function BaseService.buyVault(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local index = data.vaults + 1
	local vault = Config.Economy.tunables.vaults[index]
	if vault == nil then
		Net.notify(player, "Your base has every vault!", "info")
		return
	end
	if data.floors < vault.floor then
		local floorName = Config.Economy.tunables.floors[vault.floor - 1].name
		Net.notify(player, `Vault {index} needs the {floorName}.`, "bad")
		return
	end
	if not EconomyService.spend(player, vault.cost, `Vault{index}`) then
		Net.notify(player, `You need {Format.cash(vault.cost)} for Vault {index}.`, "bad")
		return
	end
	data.vaults = index
	apply(player, data)
	Analytics.progress(player, "Vault", index)
	Net.notify(player, `Vault {index} built! Put a rare creature inside and lock it at the door (E).`, "rare")
	ProgressionService.addXp(player, Config.Progression.xp.baseUpgradePerLevel * (index + 2))
	DataService.markDirty(player)
end

-- Buys the next security upgrade (alarm → tripwire → auto-lock).
function BaseService.buySecurity(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local nextLevel = Config.Economy.tunables.securityLevels[data.security + 1]
	if nextLevel == nil then
		Net.notify(player, "Your base security is maxed out!", "info")
		return
	end
	if not EconomyService.spend(player, nextLevel.cost, `Security{data.security + 1}`) then
		Net.notify(player, `You need {Format.cash(nextLevel.cost)} for the {nextLevel.name}.`, "bad")
		return
	end
	data.security += 1
	Net.notify(player, `{nextLevel.name} installed! {nextLevel.description}.`, "rare")
	ProgressionService.addXp(player, 100 * data.security)
	DataService.markDirty(player)
end

-- Buys the next hiding spot (needs its base level).
function BaseService.buyHide(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local index = data.hides + 1
	local spot = Config.BaseBuilds.hidingSpots[index]
	if spot == nil then
		Net.notify(player, "Your base has every hiding spot!", "info")
		return
	end
	if data.baseLevel < spot.baseLevel then
		Net.notify(player, `The {spot.name} needs base level {spot.baseLevel}.`, "bad")
		return
	end
	if not EconomyService.spend(player, spot.cost, `Hide{index}`) then
		Net.notify(player, `You need {Format.cash(spot.cost)} for the {spot.name}.`, "bad")
		return
	end
	data.hides = index
	apply(player, data)
	Analytics.progress(player, "HidingSpot", index)
	Net.notify(
		player,
		`{spot.name} built! Hide a creature in it (Creatures → Move). Thieves can search it, and Mythic and rarer sparkle now and then, so don't count on it forever.`,
		"rare"
	)
	ProgressionService.addXp(player, Config.Progression.xp.baseUpgradePerLevel * (index + 1))
	DataService.markDirty(player)
end

-- Buys a decor or security item (Config.BaseBuilds.items).
function BaseService.buyBuild(player: Player, id: any)
	if typeof(id) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local item = Config.BaseBuilds.byId[id]
	if data == nil or item == nil or data.builds[id] then
		return
	end
	if data.baseLevel < item.baseLevel then
		Net.notify(player, `{item.name} needs base level {item.baseLevel}.`, "bad")
		return
	end
	if data.floors < (item.floors or 1) then
		Net.notify(player, `{item.name} needs the Second Floor.`, "bad")
		return
	end
	if not EconomyService.spend(player, item.cost, `Build_{id}`) then
		Net.notify(player, `You need {Format.cash(item.cost)} for {item.name}.`, "bad")
		return
	end
	data.builds[id] = true
	apply(player, data)
	Analytics.progress(player, `Build_{id}`, 1)
	Net.notify(player, `{item.name} built! {item.description}.`, "rare")
	ProgressionService.addXp(player, math.max(50, math.floor(math.log10(item.cost) * 40)))
	DataService.markDirty(player)
end

-- Switches a bought decor item on or off (Command Terminal → Base menu).
function BaseService.toggleBuild(player: Player, id: any)
	if typeof(id) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local item = Config.BaseBuilds.byId[id]
	if data == nil or item == nil or item.kind ~= "Decor" or not data.builds[id] then
		return
	end
	if data.hiddenBuilds[id] then
		data.hiddenBuilds[id] = nil
	else
		data.hiddenBuilds[id] = true
	end
	apply(player, data)
	DataService.markDirty(player)
end

local function buyOffer(player: Player, key: string)
	if key == "level" then
		BaseService.upgrade(player)
	elseif key == "security" then
		BaseService.buySecurity(player)
	elseif key == "floor" then
		BaseService.buyFloor(player)
	elseif key == "vault" then
		BaseService.buyVault(player)
	elseif key == "hide" then
		BaseService.buyHide(player)
	else
		local id = string.match(key, "^build:(.+)$")
		if id then
			BaseService.buyBuild(player, id)
		end
	end
	local data = DataService.get(player)
	if data then
		apply(player, data) -- the pads move on to the next step either way
	end
end

-- Watches each base owner's feet: standing on a pad for a moment buys it, once
-- per visit (step off to buy again). Pad colors follow the owner's cash.
local standing: { [Player]: { pad: number, since: number, done: boolean } } = {}
local statuesShown: { [Player]: string } = {} -- the species the Guardian Statues show

-- The Guardian Statues follow the owner's two rarest creatures as they change
-- (they only updated on a full base refresh before; PC round 473db78).
local function refreshStatues(owner: Player, data: PlayerData)
	if not data.builds.GuardianStatues or data.hiddenBuilds.GuardianStatues then
		statuesShown[owner] = nil
		return
	end
	local species = rarestSpecies(data)
	local key = table.concat(species, ",")
	if statuesShown[owner] == key then
		return
	end
	local first = statuesShown[owner] == nil
	statuesShown[owner] = key
	local plot = PlotService.get(owner)
	if plot and not first then
		local decor = ownedBuilds(data)
		WorldService.setBuilds(plot, decor, lookOf(data), species)
	end
end
local function watchPads()
	local elapsed, recolor = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		recolor += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0
		local refresh = recolor >= 1
		if refresh then
			recolor = 0
		end
		for _, plot in WorldService.plots do
			local owner = PlotService.ownerOf(plot)
			if owner == nil then
				continue
			end
			local data = DataService.get(owner)
			if data and refresh then
				refreshPads(owner, data)
				refreshStatues(owner, data)
			end
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if data == nil or root == nil or not root:IsA("BasePart") then
				standing[owner] = nil
				continue
			end
			local on: number? = nil
			for i, pad in plot.pads do
				if pad.key then
					local offset = plot.origin:PointToObjectSpace(root.Position)
						- plot.origin:PointToObjectSpace(pad.part.Position)
					if
						Vector2.new(offset.X, offset.Z).Magnitude < PAD_REACH
						and offset.Y > -1
						and offset.Y < 6
					then
						on = i
					end
				end
			end
			local state = standing[owner]
			if on == nil then
				standing[owner] = nil
			elseif state == nil or state.pad ~= on then
				standing[owner] = { pad = on, since = os.clock(), done = false }
			elseif not state.done and os.clock() - state.since >= Config.BaseBuilds.padHoldSeconds then
				state.done = true
				local key = plot.pads[on].key
				if key then
					buyOffer(owner, key)
				end
			end
		end
	end)
end

function BaseService.start()
	DataService.loaded:connect(apply) -- after PlotService assigned the plot
	-- VIP sign, Extra Nursery pedestals
	MonetizationService.passAdded:connect(function(player: Player)
		local data = DataService.get(player)
		if data then
			apply(player, data)
		end
	end)
	watchPads()
	Players.PlayerRemoving:Connect(function(player)
		standing[player] = nil
		statuesShown[player] = nil
	end)
	Net.onRequest("ToggleBuild", BaseService.toggleBuild)
	Net.onRequest("UpgradeBase", BaseService.upgrade)
	Net.onRequest("DesignPick", BaseService.designPick)
	Net.onRequest("DesignPreset", BaseService.designPreset)
	Net.onRequest("Security", BaseService.buySecurity)
	Net.onRequest("BuyFloor", BaseService.buyFloor)
	Net.onRequest("BuyVault", BaseService.buyVault)
end

return BaseService

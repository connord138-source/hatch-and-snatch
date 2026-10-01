--!strict
-- Base upgrades and themes (docs/GDD.md §6.1). Upgrading grows the plot (a longer
-- run for thieves), adds a row of ground pedestals and lengthens the laser lock.
-- Floors add a row of pedestals a story up and room for vaults (single rooms the
-- owner locks on a timer). Themes restyle the plot in a biome's look once that
-- biome is unlocked, or in a built-up look the floors and vaults unlock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Pushes the player's level + theme onto their plot and its upgrade sign.
local function apply(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	WorldService.setLevel(plot, data.baseLevel)
	WorldService.setFloors(plot, data.floors, data.vaults)
	WorldService.applyTheme(
		plot,
		Config.Progression.themesById[data.baseTheme] or Config.Progression.themes[1]
	)
	WorldService.setNursery(plot, CreatureService.nurserySlots(data))
	local vip = MonetizationService.hasPass(player, "VIP")
	plot.label.Text = if vip then `⭐ VIP · {player.DisplayName}'s Base` else `{player.DisplayName}'s Base`
	plot.label.TextColor3 = if vip then Color3.fromRGB(255, 215, 90) else Color3.new(1, 1, 1)
	local nextLevel = data.baseLevel + 1
	if nextLevel <= maxLevel() then
		local cost = Config.Economy.baseLevel(nextLevel).cost
		plot.upgradePrompt:SetAttribute("Active", true) -- not Enabled: PromptFilter owns that
		plot.upgradePrompt.ActionText = `Upgrade Base ({Format.cash(cost)})`
		local gains: { string } = {}
		local gain = Config.Economy.baseLevel(nextLevel).pedestals
			- Config.Economy.baseLevel(data.baseLevel).pedestals
		if gain > 0 then
			table.insert(gains, `+{gain} pedestals`)
		end
		local opens = floorOpenedAt(nextLevel)
		if opens then
			table.insert(gains, `opens the {opens}`)
		end
		table.insert(gains, "bigger base · longer lock")
		plot.upgradeLabel.Text = `Base Lv {data.baseLevel} → {nextLevel}\n{table.concat(gains, " · ")}`
	else
		plot.upgradePrompt:SetAttribute("Active", false)
		plot.upgradeLabel.Text = `Base Lv {data.baseLevel} (max)`
	end
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
			then `Base upgraded to level {nextLevel}! {gains}, and the {opens} can be built (Base menu).`
			else `Base upgraded to level {nextLevel}! {gains}.`,
		"rare"
	)
	ProgressionService.addXp(player, Config.Progression.xp.baseUpgradePerLevel * nextLevel)
	ProgressionService.bump(player, "baseUpgrades")
	ProgressionService.refresh(player) -- higher base levels open later biomes
	DataService.markDirty(player)
end

-- Buys the theme if not owned (needs its biome unlocked), then applies it.
function BaseService.setTheme(player: Player, themeId: any)
	if typeof(themeId) ~= "string" then
		return
	end
	local data = DataService.get(player)
	local theme = Config.Progression.themesById[themeId]
	if data == nil or theme == nil then
		return
	end
	local name = Config.Progression.themeName(theme)
	if not data.ownedThemes[themeId] then
		if theme.requires then
			if not Config.Progression.themeBuilt(theme, data.floors, data.vaults) then
				Net.notify(player, `Build up your base to unlock {name} first.`, "bad")
				return
			end
		elseif not ProgressionService.canBuyBiome(data, themeId) then
			Net.notify(player, `Unlock {name} first.`, "bad")
			return
		end
		if not EconomyService.spend(player, theme.cost, `Theme_{themeId}`) then
			Net.notify(player, `You need {Format.cash(theme.cost)} for this theme.`, "bad")
			return
		end
		data.ownedThemes[themeId] = true
		Net.notify(player, `{name} base theme unlocked!`, "rare")
	end
	data.baseTheme = themeId
	apply(player, data)
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
	Net.notify(
		player,
		`Vault {index} built! Put a rare creature inside and lock the door (hold E at the door).`,
		"rare"
	)
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

function BaseService.start()
	DataService.loaded:connect(apply) -- after PlotService assigned the plot
	-- VIP sign, Extra Nursery pedestals
	MonetizationService.passAdded:connect(function(player: Player)
		local data = DataService.get(player)
		if data then
			apply(player, data)
		end
	end)
	for _, plot in WorldService.plots do
		plot.upgradePrompt.Triggered:Connect(function(player)
			if PlotService.ownerOf(plot) == player then
				BaseService.upgrade(player)
			end
		end)
	end
	Net.onRequest("UpgradeBase", BaseService.upgrade)
	Net.onRequest("Theme", BaseService.setTheme)
	Net.onRequest("Security", BaseService.buySecurity)
	Net.onRequest("BuyFloor", BaseService.buyFloor)
	Net.onRequest("BuyVault", BaseService.buyVault)
end

return BaseService

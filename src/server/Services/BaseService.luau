--!strict
-- Base upgrades and themes (docs/GDD.md §6.1). Upgrading grows the plot (a longer
-- run for thieves), adds a row of pedestals and lengthens the laser lock. Themes
-- restyle the plot in a biome's look once that biome is unlocked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
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

-- Pushes the player's level + theme onto their plot and its upgrade sign.
local function apply(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	WorldService.setLevel(plot, data.baseLevel)
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
		plot.upgradeLabel.Text =
			`Base Lv {data.baseLevel} → {nextLevel}\n+5 pedestals · bigger base · longer lock`
	else
		plot.upgradePrompt:SetAttribute("Active", false)
		plot.upgradeLabel.Text = `Base Lv {data.baseLevel} (max)`
	end
end

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
	if not EconomyService.spend(player, cost) then
		Net.notify(player, `You need {Format.cash(cost)} to upgrade your base.`, "bad")
		return
	end
	data.baseLevel = nextLevel
	apply(player, data)
	Net.notify(player, `Base upgraded to level {nextLevel}! +5 pedestals and a bigger plot.`, "rare")
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
	if not data.ownedThemes[themeId] then
		if not ProgressionService.canBuyBiome(data, themeId) then
			Net.notify(player, `Unlock {Config.Biomes[themeId].displayName} first.`, "bad")
			return
		end
		if not EconomyService.spend(player, theme.cost) then
			Net.notify(player, `You need {Format.cash(theme.cost)} for this theme.`, "bad")
			return
		end
		data.ownedThemes[themeId] = true
		Net.notify(player, `{Config.Biomes[themeId].displayName} base theme unlocked!`, "rare")
	end
	data.baseTheme = themeId
	apply(player, data)
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
	if not EconomyService.spend(player, nextLevel.cost) then
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
end

return BaseService

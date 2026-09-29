--!strict
-- Base menu: base level (what the next upgrade gives and costs), security
-- upgrades (alarm -> tripwire -> auto-lock), and base themes,
-- one per biome. A theme is buyable once its biome's eggs are unlocked; owned
-- themes can be switched freely. The server checks every request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local Progression = Config.Progression
local levels = Config.Economy.tunables.baseLevels
local securityLevels = Config.Economy.tunables.securityLevels

type ThemeRow = { frame: Frame, status: TextLabel, button: TextButton }

local levelLabel: TextLabel
local levelInfo: TextLabel
local upgradeButton: TextButton
local securityLabel: TextLabel
local securityInfo: TextLabel
local securityButton: TextButton
local themeRows: { [string]: ThemeRow } = {}
local affordable = false
local securityAffordable = false

local BaseMenu = {}

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

function BaseMenu.build(content: Frame)
	levelLabel = text(content, { Size = UDim2.new(1, -230, 0, 26), TextSize = 22 })
	levelInfo = text(content, {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, -230, 0, 40),
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Ui.colors.muted,
	})
	upgradeButton = Ui.button(content, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(220, 52),
	})
	upgradeButton.Activated:Connect(function()
		if affordable then
			ClientState.request("UpgradeBase")
		end
	end)

	securityLabel = text(content, {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, -230, 0, 24),
		TextSize = 19,
		TextColor3 = Color3.fromRGB(255, 130, 130),
	})
	securityInfo = text(content, {
		Position = UDim2.fromOffset(0, 102),
		Size = UDim2.new(1, -230, 0, 36),
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Ui.colors.muted,
	})
	securityButton = Ui.button(content, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 80),
		Size = UDim2.fromOffset(220, 48),
	})
	securityButton.Activated:Connect(function()
		if securityAffordable then
			ClientState.request("Security")
		end
	end)

	local header = text(content, {
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		Text = "Base themes — restyle your plot in a biome's look",
	})
	header.TextColor3 = Color3.fromRGB(255, 220, 120)
	local list =
		Ui.scrollList(content, { Position = UDim2.fromOffset(0, 174), Size = UDim2.new(1, 0, 1, -174) })
	for i, theme in Progression.themes do
		local frame = Ui.panel(list, {
			Size = UDim2.new(1, -10, 0, 50),
			BackgroundColor3 = Ui.colors.row,
			BackgroundTransparency = 0,
			LayoutOrder = i,
		})
		local swatch = Instance.new("Frame")
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromOffset(8, 8)
		swatch.Size = UDim2.fromOffset(34, 34)
		swatch.BackgroundColor3 = theme.floorColor
		swatch.Parent = frame
		local trim = Instance.new("UIStroke")
		trim.Color = theme.trimColor
		trim.Thickness = 3
		trim.Parent = swatch
		text(frame, {
			Position = UDim2.fromOffset(52, 5),
			Size = UDim2.new(1, -200, 0, 22),
			TextSize = 17,
			Text = Config.Biomes[theme.id].displayName,
		})
		local status = text(frame, {
			Position = UDim2.fromOffset(52, 27),
			Size = UDim2.new(1, -200, 0, 16),
			TextSize = 12,
			TextColor3 = Ui.colors.muted,
			TextStrokeTransparency = 1,
		})
		local button = Ui.button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(130, 36),
		})
		button.Activated:Connect(function()
			ClientState.request("Theme", theme.id)
		end)
		themeRows[theme.id] = { frame = frame, status = status, button = button }
	end
end

function BaseMenu.refresh(state: { [string]: any })
	local level: number = state.baseLevel or 1
	local current = levels[level]
	local nextLevel = levels[level + 1]
	levelLabel.Text = `Base level {level} / {#levels}`
	if nextLevel then
		levelInfo.Text =
			`Now: {current.pedestals} pedestals, lock +{current.lockBonusSeconds}s.  Next: {nextLevel.pedestals} pedestals, a bigger plot (longer run for thieves), lock +{nextLevel.lockBonusSeconds}s.`
		affordable = state.cash >= nextLevel.cost
		upgradeButton.Text = if affordable
			then `Upgrade — {Format.cash(nextLevel.cost)}`
			else `Need {Format.cash(nextLevel.cost - state.cash)} more`
		upgradeButton.BackgroundColor3 = if affordable then Ui.colors.good else Ui.colors.disabled
	else
		levelInfo.Text = `Fully upgraded: {current.pedestals} pedestals, lock +{current.lockBonusSeconds}s.`
		affordable = false
		upgradeButton.Text = "Max level"
		upgradeButton.BackgroundColor3 = Ui.colors.disabled
	end

	local security: number = state.security or 0
	local nextSecurity = securityLevels[security + 1]
	securityLabel.Text = if security > 0
		then `Security: {securityLevels[security].name} ({security} / {#securityLevels})`
		else `Security: none (0 / {#securityLevels})`
	if nextSecurity then
		securityInfo.Text = `Next — {nextSecurity.name}: {nextSecurity.description}.`
		securityAffordable = state.cash >= nextSecurity.cost
		securityButton.Text = if securityAffordable
			then `{nextSecurity.name} — {Format.cash(nextSecurity.cost)}`
			else `Need {Format.cash(nextSecurity.cost - state.cash)} more`
		securityButton.BackgroundColor3 = if securityAffordable then Ui.colors.good else Ui.colors.disabled
	else
		securityInfo.Text = "Fully secured: alarm, tripwire and auto-lock are all active."
		securityAffordable = false
		securityButton.Text = "Max security"
		securityButton.BackgroundColor3 = Ui.colors.disabled
	end

	for id, row in themeRows do
		local theme = Progression.themesById[id]
		local owned = state.ownedThemes and state.ownedThemes[id] == true
		local active = state.baseTheme == id
		local unlocked = Config.Biomes[id].order <= state.unlockedBiome
		if active then
			row.status.Text = "Active"
			row.button.Text = "Active"
			row.button.BackgroundColor3 = Ui.colors.disabled
		elseif owned then
			row.status.Text = "Owned"
			row.button.Text = "Use"
			row.button.BackgroundColor3 = Ui.colors.blue
		elseif unlocked then
			row.status.Text = `Unlocked — {Format.cash(theme.cost)}`
			row.button.Text = `Buy {Format.cash(theme.cost)}`
			row.button.BackgroundColor3 = if state.cash >= theme.cost
				then Ui.colors.good
				else Ui.colors.disabled
		else
			local need = Progression.biomeRequirements[id]
			row.status.Text = `Unlock {Config.Biomes[id].displayName} first (Hatcher Lv {need.level})`
			row.button.Text = "Locked"
			row.button.BackgroundColor3 = Ui.colors.disabled
		end
	end
end

return BaseMenu

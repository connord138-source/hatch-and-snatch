--!strict
-- The Command Terminal's menu (opened at the terminal in your base; owner,
-- 2026-10-01). Upgrades are bought on the glowing pads in the front yard, so this
-- shows where the base stands and what's next, and holds the customizing: decor
-- switched on or off, the security items, and base themes (one per biome, buyable
-- once its biome's eggs are unlocked, plus looks the floors and vaults unlock).
-- The server checks every request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local Progression = Config.Progression
local tunables = Config.Economy.tunables
local levels = tunables.baseLevels
local securityLevels = tunables.securityLevels

type ThemeRow = { frame: Frame, status: TextLabel, button: TextButton }
type BuyRow = { title: TextLabel, info: TextLabel, button: TextButton, ready: boolean, request: string }

local levelRow: BuyRow
local securityRow: BuyRow
local floorRow: BuyRow
local vaultRow: BuyRow
local hideRow: BuyRow
local itemRows: { [string]: BuyRow } = {}
local themeRows: { [string]: ThemeRow } = {}

local BaseMenu = {}

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

local function header(list: Instance, order: number, value: string)
	local label = text(list, {
		Size = UDim2.new(1, -10, 0, 26),
		TextSize = 17,
		Text = value,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		LayoutOrder = order,
	})
	label.TextStrokeTransparency = 0.6
end

-- A row with a title, a line of detail and a buy button that sends `request`.
local function buyRow(list: Instance, order: number, titleColor: Color3, request: string): BuyRow
	local frame = Ui.panel(list, {
		Size = UDim2.new(1, -10, 0, 74),
		BackgroundColor3 = Ui.colors.row,
		BackgroundTransparency = 0,
		LayoutOrder = order,
	})
	local row: BuyRow = {
		title = text(frame, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -250, 0, 24),
			TextSize = 19,
			TextColor3 = titleColor,
		}),
		info = text(frame, {
			Position = UDim2.fromOffset(12, 31),
			Size = UDim2.new(1, -250, 0, 38),
			TextSize = 13,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Ui.colors.muted,
			TextStrokeTransparency = 1,
		}),
		button = Ui.button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(220, 48),
		}),
		ready = false,
		request = request,
	}
	if request ~= "" and request ~= "ToggleBuild" then
		row.button.Activated:Connect(function()
			if row.ready then
				ClientState.request(request)
			end
		end)
	end
	return row
end

-- The button of a status row: what the next step costs (bought on its pad in the
-- base, so the button only reports), or blocked with a reason.
local function offer(row: BuyRow, cash: number, label: string, cost: number?, blocked: string?)
	if row.request == "" then
		row.ready = false
		row.button.Text = if cost == nil
			then label
			elseif blocked then blocked
			else `On its pad · {Format.cash(cost)}`
		row.button.BackgroundColor3 = if cost
				and not blocked
				and cash >= cost
			then Ui.colors.good
			else Ui.colors.disabled
		return
	end
	if cost == nil then
		row.ready = false
		row.button.Text = label
	elseif blocked then
		row.ready = false
		row.button.Text = blocked
	elseif cash >= cost then
		row.ready = true
		row.button.Text = `{label} — {Format.cash(cost)}`
	else
		row.ready = false
		row.button.Text = `Need {Format.cash(cost - cash)} more`
	end
	row.button.BackgroundColor3 = if row.ready then Ui.colors.good else Ui.colors.disabled
end

function BaseMenu.build(content: Frame)
	local list = Ui.scrollList(content, { Size = UDim2.fromScale(1, 1) })
	header(list, 0, "Buy upgrades on the glowing pads in your front yard (stand on one).")
	levelRow = buyRow(list, 1, Color3.new(1, 1, 1), "")
	securityRow = buyRow(list, 2, Color3.fromRGB(255, 130, 130), "")
	floorRow = buyRow(list, 3, Color3.fromRGB(150, 220, 255), "")
	vaultRow = buyRow(list, 4, Color3.fromRGB(255, 200, 90), "")
	hideRow = buyRow(list, 5, Color3.fromRGB(190, 240, 140), "")
	header(list, 6, "Decor: switch what you've built on or off")
	local order = 7
	for _, kind in { "Decor", "Security" } do
		if kind == "Security" then
			header(list, order, "Security items (each runs on a timer)")
			order += 1
		end
		for _, item in Config.BaseBuilds.items do
			if item.kind == kind then
				local row = buyRow(
					list,
					order,
					if kind == "Decor" then Color3.fromRGB(255, 225, 150) else Color3.fromRGB(255, 150, 150),
					"ToggleBuild"
				)
				row.title.Text = item.name
				row.info.Text = item.description
				row.button.Activated:Connect(function()
					if row.ready then
						ClientState.request("ToggleBuild", item.id)
					end
				end)
				itemRows[item.id] = row
				order += 1
			end
		end
	end
	header(list, 50, "Base themes: restyle your plot (biome looks, and looks your floors and vaults unlock)")
	for i, theme in Progression.themes do
		local frame = Ui.panel(list, {
			Size = UDim2.new(1, -10, 0, 50),
			BackgroundColor3 = Ui.colors.row,
			BackgroundTransparency = 0,
			LayoutOrder = 50 + i,
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
			Text = Progression.themeName(theme),
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

local function floorName(floors: number): string
	return if floors <= 1 then "Ground" else tunables.floors[floors - 1].name
end

function BaseMenu.refresh(state: { [string]: any })
	local cash: number = state.cash
	local level: number = state.baseLevel or 1
	local current = levels[level]
	local nextLevel = levels[level + 1]
	local tier = Config.BaseBuilds.tiers[math.clamp(level, 1, #Config.BaseBuilds.tiers)]
	levelRow.title.Text = `{tier.name} · base level {level} / {#levels}`
	if nextLevel then
		local gain = nextLevel.pedestals - current.pedestals
		local opens: string? = nil
		for _, floor in tunables.floors do
			if floor.baseLevel == level + 1 then
				opens = floor.name
			end
		end
		local gains: { string } = {}
		if gain > 0 then
			table.insert(gains, `+{gain} pedestals`)
		end
		if opens then
			table.insert(gains, `opens the {opens}`)
		end
		table.insert(gains, `a bigger plot and {Config.BaseBuilds.tiers[level + 1].description}`)
		table.insert(gains, `lock +{nextLevel.lockBonusSeconds}s`)
		levelRow.info.Text = `Next: {table.concat(gains, ", ")}.`
		offer(levelRow, cash, "Upgrade", nextLevel.cost)
	else
		levelRow.info.Text = `Fully upgraded: lock +{current.lockBonusSeconds}s.`
		offer(levelRow, cash, "Max level")
	end

	local security: number = state.security or 0
	local nextSecurity = securityLevels[security + 1]
	securityRow.title.Text = if security > 0
		then `Security: {securityLevels[security].name} ({security} / {#securityLevels})`
		else `Security: none (0 / {#securityLevels})`
	if nextSecurity then
		securityRow.info.Text = `Next: {nextSecurity.name}. {nextSecurity.description}.`
		offer(securityRow, cash, nextSecurity.name, nextSecurity.cost)
	else
		securityRow.info.Text = "Fully secured: alarm, tripwire and auto-lock (it locks your vaults too)."
		offer(securityRow, cash, "Max security")
	end

	-- Floors: a row of pedestals a story up, harder to steal from
	local floors: number = state.floors or 1
	local nextFloor = tunables.floors[floors]
	floorRow.title.Text = `Floors: up to the {floorName(floors)} ({floors} / {#tunables.floors + 1})`
	if nextFloor then
		floorRow.info.Text =
			`Next: {nextFloor.name}. +{nextFloor.pedestals} pedestals up the ramps, where thieves take longer to grab and must carry it back down. Room for 2 vaults.`
		offer(
			floorRow,
			cash,
			"Build",
			nextFloor.cost,
			if level < nextFloor.baseLevel then `Needs base Lv {nextFloor.baseLevel}` else nil
		)
	else
		floorRow.info.Text = "Every floor built. Use Creatures → Rarest up top to move your best up high."
		offer(floorRow, cash, "All floors built")
	end

	-- Vaults: single rooms the owner locks on a timer
	local vaults: number = state.vaults or 0
	local nextVault = tunables.vaults[vaults + 1]
	vaultRow.title.Text = `Vaults: {vaults} / {#tunables.vaults}`
	local how =
		`One creature each, behind a door you lock for {Format.duration(tunables.vaultLockSeconds)} (hold E at the door). Nothing in a locked vault can be stolen.`
	if nextVault then
		vaultRow.info.Text = `Next: Vault {vaults + 1} on the {floorName(nextVault.floor)}. {how}`
		offer(
			vaultRow,
			cash,
			"Build",
			nextVault.cost,
			if floors < nextVault.floor then `Needs the {floorName(nextVault.floor)}` else nil
		)
	else
		vaultRow.info.Text = `Every vault built. {how}`
		offer(vaultRow, cash, "All vaults built")
	end

	-- Hiding spots: bought in order
	local hides: number = state.hides or 0
	local spots = Config.BaseBuilds.hidingSpots
	local nextSpot = spots[hides + 1]
	hideRow.title.Text = `Hiding spots: {hides} / {#spots}`
	if nextSpot then
		hideRow.info.Text =
			`Next: {nextSpot.name}. Hides one creature out of sight (Creatures → Move). Thieves can search spots, and Mythic and rarer sparkle now and then.`
		offer(
			hideRow,
			cash,
			"Build",
			nextSpot.cost,
			if level < nextSpot.baseLevel then `Needs base Lv {nextSpot.baseLevel}` else nil
		)
	else
		hideRow.info.Text = "Every hiding spot built. Empty ones make good decoys."
		offer(hideRow, cash, "All built")
	end

	-- Decor and security items: owned decor toggles, the rest say where to get it
	local builds = state.builds or {}
	local hidden = state.hiddenBuilds or {}
	for id, row in itemRows do
		local item = Config.BaseBuilds.byId[id]
		if builds[id] then
			if item.kind == "Decor" then
				local shown = not hidden[id]
				row.ready = true
				row.button.Text = if shown then "Shown ✓" else "Hidden"
				row.button.BackgroundColor3 = if shown then Ui.colors.good else Ui.colors.blue
			else
				row.ready = false
				row.button.Text = "Installed ✓"
				row.button.BackgroundColor3 = Ui.colors.good
			end
		else
			row.ready = false
			row.button.Text = if level < item.baseLevel
				then `Needs base Lv {item.baseLevel}`
				elseif floors < (item.floors or 1) then "Needs the Second Floor"
				else `On its pad · {Format.cash(item.cost)}`
			row.button.BackgroundColor3 = Ui.colors.disabled
		end
	end

	for id, row in themeRows do
		local theme = Progression.themesById[id]
		local owned = state.ownedThemes and state.ownedThemes[id] == true
		local active = state.baseTheme == id
		local unlocked = if theme.requires
			then Progression.themeBuilt(theme, floors, vaults)
			else Config.Biomes[id].order <= state.unlockedBiome
		if active then
			row.status.Text = "Active"
			row.button.Text = "Active"
			row.button.BackgroundColor3 = Ui.colors.disabled
		elseif owned then
			row.status.Text = "Owned"
			row.button.Text = "Use"
			row.button.BackgroundColor3 = Ui.colors.blue
		elseif unlocked then
			row.status.Text = `Unlocked: {Format.cash(theme.cost)}`
			row.button.Text = `Buy {Format.cash(theme.cost)}`
			row.button.BackgroundColor3 = if cash >= theme.cost then Ui.colors.good else Ui.colors.disabled
		elseif theme.requires then
			local need = theme.requires
			row.status.Text = if need.vaults
				then `Build all {need.vaults} vaults to unlock`
				else `Build the {floorName(need.floors or 2)} to unlock`
			row.button.Text = "Locked"
			row.button.BackgroundColor3 = Ui.colors.disabled
		else
			local need = Progression.biomeRequirements[id]
			row.status.Text = `Unlock {Config.Biomes[id].displayName} first (Hatcher Lv {need.level})`
			row.button.Text = "Locked"
			row.button.BackgroundColor3 = Ui.colors.disabled
		end
	end
end

return BaseMenu

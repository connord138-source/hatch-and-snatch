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

local tunables = Config.Economy.tunables
local levels = tunables.baseLevels
local securityLevels = tunables.securityLevels

type BuyRow = { title: TextLabel, info: TextLabel, button: TextButton, ready: boolean, request: string }

local levelRow: BuyRow
local securityRow: BuyRow
local floorRow: BuyRow
local vaultRow: BuyRow
local hideRow: BuyRow
local itemRows: { [string]: BuyRow } = {}
type DesignCell = { button: TextButton, stroke: UIStroke, status: TextLabel }
local Designs = Config.CastleDesigns
local presetCells: { [string]: DesignCell } = {}
local optionCells: { [string]: { [string]: DesignCell } } = {}
local slotHeaders: { [string]: TextLabel } = {}

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
	-- The Castle Designer: presets, then one swatch grid per slot
	header(list, 50, "Castle Designer: mix and match your castle (new looks open with each zone)")
	local function grid(order: number, cell: Vector2): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, -10, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.LayoutOrder = order
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = list
		return frame
	end
	local function cell(
		parent: Instance,
		order: number,
		color: Color3?,
		title: string,
		onPick: () -> ()
	): DesignCell
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = true
		button.BackgroundColor3 = Ui.colors.row
		button.LayoutOrder = order
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 8)
		round.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Ui.colors.disabled
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		if color then
			local swatch = Instance.new("Frame")
			swatch.BorderSizePixel = 0
			swatch.Position = UDim2.fromOffset(6, 6)
			swatch.Size = UDim2.new(1, -12, 0, 14)
			swatch.BackgroundColor3 = color
			local swatchRound = Instance.new("UICorner")
			swatchRound.CornerRadius = UDim.new(0, 4)
			swatchRound.Parent = swatch
			swatch.Parent = button
		end
		local name = text(button, {
			Position = UDim2.fromOffset(6, if color then 22 else 6),
			Size = UDim2.new(1, -12, 0, 16),
			TextSize = 13,
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local status = text(button, {
			Position = UDim2.new(0, 6, 1, -20),
			Size = UDim2.new(1, -12, 0, 14),
			TextSize = 11,
			TextColor3 = Ui.colors.muted,
			TextStrokeTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		button.Activated:Connect(onPick)
		button.Parent = parent
		return { button = button, stroke = stroke, status = status }
	end
	local presetGrid = grid(51, Vector2.new(124, 46))
	for i, preset in Designs.presets do
		presetCells[preset.id] = cell(presetGrid, i, nil, preset.name, function()
			ClientState.request("DesignPreset", preset.id)
		end)
	end
	for i, slot in Designs.slots do
		slotHeaders[slot.id] = text(list, {
			Size = UDim2.new(1, -10, 0, 22),
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 220, 120),
			LayoutOrder = 52 + i * 2,
		})
		local slotGrid = grid(53 + i * 2, Vector2.new(96, 60))
		optionCells[slot.id] = {}
		for j, option in slot.options do
			local swatch = option.color or Color3.fromRGB(140, 134, 126)
			optionCells[slot.id][option.id] = cell(slotGrid, j, swatch, option.name, function()
				ClientState.request("DesignPick", slot.id, option.id)
			end)
		end
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

	-- The Castle Designer: what's in use, owned, for sale, or still locked
	local design = state.design or {}
	local owned = state.ownedDesigns or {}
	local progress: Config.DesignProgress = {
		unlockedBiome = state.unlockedBiome or 1,
		baseLevel = level,
		floors = floors,
		vaults = vaults,
		rebirths = state.rebirths or 0,
	}
	local function biomeOrder(id: string): number
		local biome = Config.Biomes[id :: any]
		return if biome then biome.order else math.huge
	end
	local function showCell(entry: DesignCell, inUse: boolean, has: boolean, cost: number, needs: string?)
		entry.stroke.Color = if inUse
			then Color3.fromRGB(255, 220, 90)
			elseif has then Ui.colors.good
			else Ui.colors.disabled
		entry.status.Text = if inUse
			then "✓ In use"
			elseif has then "Owned"
			elseif needs then `🔒 {needs}`
			else Format.cash(cost)
		entry.status.TextColor3 = if needs and not has
			then Ui.colors.warn
			elseif not has and cash >= cost then Ui.colors.cash
			else Ui.colors.muted
	end
	for _, slot in Designs.slots do
		local picked = design[slot.id] or slot.default
		local pickedOption = Designs.options[slot.id][picked]
		slotHeaders[slot.id].Text = `{slot.name}: {if pickedOption then pickedOption.name else picked}`
		for _, option in slot.options do
			local has = Designs.owns(owned, slot.id, option.id)
			local open, needs = Designs.unlocked(option, progress, biomeOrder)
			showCell(
				optionCells[slot.id][option.id],
				picked == option.id,
				has,
				option.cost,
				if open then nil else needs
			)
		end
	end
	for _, preset in Designs.presets do
		local inUse, total, blocked = true, 0, nil :: string?
		for slotId, id in preset.picks do
			local slot = Designs.slotsById[slotId]
			if (design[slotId] or slot.default) ~= id then
				inUse = false
			end
			local option = Designs.options[slotId][id]
			if option and not Designs.owns(owned, slotId, id) then
				local open, needs = Designs.unlocked(option, progress, biomeOrder)
				total += option.cost
				if not open then
					blocked = blocked or needs
				end
			end
		end
		showCell(presetCells[preset.id], inUse, total == 0, total, blocked)
		if total == 0 and not inUse then
			presetCells[preset.id].status.Text = "Apply"
		end
	end
end

return BaseMenu

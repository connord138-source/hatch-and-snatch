--!strict
-- Creatures menu: everything you own, where it is, what it earns and what it sells
-- for. Walk, Move (storage, a floor or a vault), Nursery, Release (for biome
-- Essence + spins) and Sell send requests, and "Rarest up top" sorts the most
-- valuable into the vaults and upper floors; the server checks and applies them.
-- Clicking a creature's name opens its details card (owner, 2026-10-03: "a screen
-- under creatures where they can view each creature and its benefits/genetics"):
-- the model, its finish and mutation, what its earnings are made of, and its growth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Genetics = require(ReplicatedStorage.Shared.Genetics)
local MutationLooks = require(ReplicatedStorage.Shared.MutationLooks)
local Timing = require(ReplicatedStorage.Shared.Timing)
local ClientState = require(script.Parent.Parent.ClientState)
local CreatureViewport = require(script.Parent.Parent.CreatureViewport)
local Ui = require(script.Parent.Parent.Ui)

type Creature = { [string]: any } -- one entry of state.creatures (see StateService)

type Row = {
	frame: Frame,
	strip: Frame,
	name: TextLabel,
	details: TextLabel,
	walk: TextButton,
	move: TextButton,
	picker: Frame,
	expanded: boolean,
	nursery: TextButton,
	sell: TextButton,
	sellArmedUntil: number,
	release: TextButton,
	releaseArmedUntil: number,
}

type Card = {
	frame: Frame,
	model: Frame,
	modelKey: string,
	name: TextLabel,
	subtitle: TextLabel,
	list: ScrollingFrame,
	lines: { [string]: TextLabel },
	growthBar: Frame,
	growthFill: Frame,
	uid: string?,
	opened: number, -- bumps on every open, so an old countdown loop stops
}

local CONFIRM_SECONDS = 3
local NEXT_STAGE: { [string]: string } = { Baby = "Juvenile", Juvenile = "Adult" }
local HEADER_COLOR = Color3.fromRGB(255, 210, 90)

local finishNames: { [string]: string } = {}
for _, finish in Config.Finishes do
	finishNames[finish.id] = finish.displayName
end

local ROW_HEIGHT = 58
local PICKER_HEIGHT = 40
local FLOOR_NAMES = { "Ground", "2nd floor", "Top floor" }

local summary: TextLabel
local arrangeButton: TextButton
local list: ScrollingFrame
local emptyLabel: TextLabel
local card: Card
local rows: { [string]: Row } = {}
local latest: { [string]: Creature } = {} -- uid -> newest snapshot entry
local walkingUid: string? = nil

local CreaturesMenu = {}

local function isNursery(slot: number?): boolean
	local state = ClientState.current
	local nursery: number = if state and state.nurserySlots
		then state.nurserySlots
		else Config.Economy.tunables.nurserySlotsBase
	return slot ~= nil and slot <= nursery
end

-- "Vault 2 (locked 2:31)" / "Vault 2 (open)", from the lock timers the server sends
-- Short labels for the hiding spots in the Move picker (Config.BaseBuilds.hidingSpots)
local HIDE_LABELS = { "🌾 Hay", "🛢 Barrels", "🌳 Hedge", "🎁 Chest" }

local function vaultText(vault: number): string
	local state = ClientState.current
	local lock = state and state.vaultLocks and state.vaultLocks[vault]
	local left = if lock then lock.lockedUntil - Workspace:GetServerTimeNow() else 0
	return if left > 0
		then `🔒 Vault {vault} (locked {Format.duration(math.ceil(left))})`
		else `Vault {vault} (open)`
end

-- RichText: a mutation shows first, in its accent color (Shared/MutationLooks)
local function fullName(creature: Creature): string
	local parts = {}
	local mutation = creature.mutation
	if mutation and Config.MutationsById[mutation] then
		table.insert(parts, MutationLooks.richName(mutation, Config.MutationsById[mutation].displayName))
	end
	if creature.finish ~= "Normal" then
		table.insert(parts, finishNames[creature.finish] or creature.finish)
	end
	table.insert(parts, Config.CreaturesById[creature.species].displayName)
	return table.concat(parts, " ")
end

local function setButton(button: TextButton, enabled: boolean, color: Color3)
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color else Ui.colors.disabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function updateSell(row: Row, creature: Creature)
	if os.clock() < row.sellArmedUntil then
		row.sell.Text = "Confirm?"
		setButton(row.sell, true, Ui.colors.bad)
	else
		row.sell.Text = `Sell {Format.cash(creature.value)}`
		setButton(row.sell, not creature.carried, Ui.colors.good)
	end
end

local function releaseText(creature: Creature): string
	local species = Config.CreaturesById[creature.species]
	local essence, spins =
		Config.Zones.releaseReward(Config.Rarities[species.rarity].order, creature.stage, species.biome)
	local parts: { string } = {}
	if essence > 0 then
		table.insert(parts, `{essence}✨`)
	end
	if spins > 0 then
		table.insert(parts, `{spins}🎡`)
	end
	return `Release {table.concat(parts, " ")}`
end

local function updateRelease(row: Row, creature: Creature)
	if os.clock() < row.releaseArmedUntil then
		row.release.Text = "Confirm?"
		setButton(row.release, true, Ui.colors.bad)
	else
		row.release.Text = releaseText(creature)
		setButton(row.release, not creature.carried, Color3.fromRGB(130, 90, 180))
	end
end

-- Where a creature is: "Nursery", "🔒 Vault 2 (locked 2:31)", "Top floor", ...
local function spotText(creature: Creature): string
	if creature.carried then
		return "BEING STOLEN!"
	elseif creature.slot == nil then
		return "In storage"
	end
	local vault = Config.Economy.vaultOfSlot(creature.slot)
	local hide = Config.Economy.hideOfSlot(creature.slot)
	return if isNursery(creature.slot)
		then "Nursery"
		elseif vault then vaultText(vault)
		elseif hide then `🤫 Hidden: {Config.BaseBuilds.hidingSpots[hide].name}`
		else FLOOR_NAMES[Config.Economy.slotFloor(creature.slot)] or "Pedestal"
end

local function updateRow(row: Row, creature: Creature)
	local species = Config.CreaturesById[creature.species]
	local rarityColor = Config.Rarities[species.rarity].color
	row.strip.BackgroundColor3 = rarityColor
	row.name.Text = fullName(creature)
	row.name.TextColor3 = rarityColor

	local where: string
	if creature.carried or creature.slot ~= nil then
		where = if creature.carried
			then spotText(creature)
			else `{spotText(creature)} · +{Format.cash(creature.rate)}/s`
	else
		where = `In storage (earns {Format.cash(creature.rate)}/s placed)`
	end
	-- Where it is comes first: the line is narrow beside the buttons and truncates at
	-- the end, and the vault state ("(locked 2:31)") is the part that changes
	local parts = { where, creature.stage, species.rarity }
	if creature.stolenFrom then
		table.insert(parts, `stolen from {creature.stolenFrom}`)
	elseif creature.homegrown then
		table.insert(parts, "Homegrown")
	end
	row.details.Text = table.concat(parts, " · ")
	row.details.TextColor3 = if creature.carried then Ui.colors.warn else Ui.colors.muted

	local free = not creature.carried
	local isWalking = walkingUid == creature.uid
	row.walk.Text = if isWalking then "Home" else "Walk"
	setButton(row.walk, free, if isWalking then Ui.colors.bad else Color3.fromRGB(150, 110, 40))
	if isWalking then
		row.details.Text = `On a walk (grows faster) · {row.details.Text}`
	end
	-- ▼/▲: the small triangles (▾ ▴) don't exist in Roblox's fonts and show as boxes
	row.move.Text = if row.expanded
		then "Close ▲"
		elseif creature.slot == nil then "Place ▼"
		else "Move ▼"
	setButton(row.move, free, Ui.colors.button)
	if creature.carried and row.expanded then
		row.expanded = false
		row.picker.Visible = false
		row.frame.Size = UDim2.new(1, -10, 0, ROW_HEIGHT)
	end
	row.nursery.Visible = creature.slot ~= nil
	row.nursery.Text = if isNursery(creature.slot) then "Leave Nursery" else "To Nursery"
	setButton(row.nursery, free, Ui.colors.blue)
	updateSell(row, creature)
	updateRelease(row, creature)
end

---------------------------------------------------------------------------
-- Details card
---------------------------------------------------------------------------

local function growthText(creature: Creature): (string, number)
	local nextAt = creature.nextStageAt
	local nextStage = NEXT_STAGE[creature.stage]
	if nextAt == nil or nextStage == nil then
		return "Fully grown Adult", 1
	end
	local species = Config.CreaturesById[creature.species]
	local total = Config.Economy.secondsToNextStage(species.rarity, creature.stage)
	local duration = if total then Timing.scaled(total) else 1
	local left = math.max(0, nextAt - Workspace:GetServerTimeNow())
	local tunables = Config.Economy.tunables
	local home = Config.Biomes[species.biome]
	local speedUp = if walkingUid == creature.uid
		then `On a walk: growing {tunables.walkGrowthMultiplier}×, {tunables.homeWalkGrowthMultiplier}× in {home.displayName}`
		else `Walk it to grow {tunables.walkGrowthMultiplier}× ({tunables.homeWalkGrowthMultiplier}× in {home.displayName})`
	if Config.Zones.byBiome[species.biome] == nil then
		speedUp = `Walk it to grow {tunables.walkGrowthMultiplier}×` -- Junk creatures have no zone
	end
	return `{nextStage} in {Format.duration(left)} · {speedUp}`, math.clamp(1 - left / duration, 0, 1)
end

local function fillCard(creature: Creature)
	local species = Config.CreaturesById[creature.species]
	local rarity = Config.Rarities[species.rarity]
	local earnsAs = creature.eggBiome or species.biome
	card.name.Text = fullName(creature)
	card.name.TextColor3 = rarity.color
	card.subtitle.Text = `{species.rarity} · {Config.Biomes[species.biome].displayName} · {creature.stage}`

	-- The model, rebuilt only when what it looks like changes (it grew, say)
	local key = `{creature.species}|{creature.stage}|{creature.finish}|{creature.mutation or ""}`
	if key ~= card.modelKey then
		card.modelKey = key
		card.model:ClearAllChildren()
		local view = CreatureViewport.create(
			card.model,
			creature.species,
			creature.stage,
			creature.finish,
			creature.mutation,
			{
				position = UDim2.fromScale(0.5, 0.5),
				size = UDim2.fromScale(1, 1),
				maxSize = Vector2.new(260, 260),
				zIndex = 7,
			}
		)
		if view == nil then
			Ui.label(card.model, {
				Size = UDim2.fromScale(1, 1),
				Text = "🥚",
				ZIndex = 7,
			})
		end
	end

	local lines = card.lines
	lines.finish.Text = `✨ Finish: {Genetics.finishLine(creature.finish)}`
	lines.mutation.Text = `🧬 Mutation: {Genetics.mutationLine(creature.mutation)}`
	local origin = if creature.stolenFrom
		then `Stolen from {creature.stolenFrom}`
		elseif creature.homegrown then `Homegrown · +{math.round(
			Config.Economy.tunables.homegrownBonus * 100
		)}% earnings, wriggles free once if grabbed`
		else "Not homegrown"
	if creature.eggBiome then
		origin ..= ` · hatched from a {Config.Biomes[creature.eggBiome].displayName} egg, so it earns like one`
	end
	lines.origin.Text = `🏡 Origin: {origin}`

	local base, factors = Genetics.factors(
		creature.species,
		creature.stage,
		creature.finish,
		creature.mutation,
		creature.homegrown == true,
		earnsAs
	)
	local product = base
	local parts = { `{Format.cash(base)} base` }
	for _, factor in factors do
		product *= factor.multiplier
		table.insert(parts, `{factor.label} {Genetics.times(factor.multiplier)}`)
	end
	local boosts = if product > 0 then creature.rate / product else 1
	if boosts > 1.001 then
		table.insert(parts, `your boosts {Genetics.times(boosts)}`)
	end
	lines.rate.Text = if creature.slot ~= nil
		then `💰 +{Format.cash(creature.rate)}/s on its pedestal`
		else `💰 Would earn +{Format.cash(creature.rate)}/s on a pedestal`
	lines.breakdown.Text = table.concat(parts, " × ")
	lines.worth.Text = `Sells for {Format.cash(creature.value)}`
	lines.about.Text = `{species.element}. {species.gag}`
	lines.where.Text = `📍 {spotText(creature)}`

	local text, progress = growthText(creature)
	lines.growth.Text = text
	card.growthFill.Size = UDim2.fromScale(progress, 1)
	card.growthFill.BackgroundColor3 = rarity.color
end

local function setListVisible(visible: boolean)
	list.Visible = visible
	summary.Visible = visible
	if not visible then
		arrangeButton.Visible = false
		emptyLabel.Visible = false
	end
end

local function closeCard()
	card.uid = nil
	card.frame.Visible = false
	card.model:ClearAllChildren()
	card.modelKey = ""
	setListVisible(true)
	local state = ClientState.current
	if state then
		CreaturesMenu.refresh(state)
	end
end

local function openCard(uid: string)
	local creature = latest[uid]
	if creature == nil then
		return
	end
	card.uid = uid
	card.opened += 1
	local opened = card.opened
	setListVisible(false)
	card.frame.Visible = true
	card.list.CanvasPosition = Vector2.zero
	fillCard(creature)
	-- The growth countdown ticks between state updates
	task.spawn(function()
		while card.opened == opened and card.uid == uid and card.frame.Visible do
			local current = latest[uid]
			if current then
				local text, progress = growthText(current)
				card.lines.growth.Text = text
				card.growthFill.Size = UDim2.fromScale(progress, 1)
			end
			task.wait(0.5)
		end
	end)
end

local function makeRow(uid: string): Row
	local frame = Ui.panel(list, {
		Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
		BackgroundColor3 = Ui.colors.row,
		BackgroundTransparency = 0,
	})
	local strip = Instance.new("Frame")
	strip.BorderSizePixel = 0
	strip.Position = UDim2.fromOffset(6, 8)
	strip.Size = UDim2.new(0, 6, 1, -16)
	strip.Parent = frame
	local name = Ui.label(frame, {
		Position = UDim2.fromOffset(20, 7),
		Size = UDim2.new(1, -490, 0, 22),
		RichText = true, -- the mutation's accent color
		TextScaled = false,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local details = Ui.label(frame, {
		Position = UDim2.fromOffset(20, 31),
		Size = UDim2.new(1, -490, 0, 18),
		TextScaled = false,
		TextSize = 13,
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- The name and details open the creature's card
	local open = Instance.new("TextButton")
	open.BackgroundTransparency = 1
	open.Text = ""
	open.Position = UDim2.fromOffset(14, 0)
	open.Size = UDim2.new(1, -490, 0, ROW_HEIGHT)
	open.Parent = frame
	open.Activated:Connect(function()
		openCard(uid)
	end)
	-- Where Move can send it: storage, each floor the base has, each vault
	local picker = Instance.new("Frame")
	picker.BackgroundTransparency = 1
	picker.Position = UDim2.fromOffset(20, ROW_HEIGHT - 4)
	picker.Size = UDim2.new(1, -28, 0, PICKER_HEIGHT - 6)
	picker.Visible = false
	picker.Parent = frame
	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.FillDirection = Enum.FillDirection.Horizontal
	pickerLayout.Padding = UDim.new(0, 6)
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = picker
	local row: Row = {
		frame = frame,
		strip = strip,
		name = name,
		details = details,
		picker = picker,
		expanded = false,
		walk = Ui.button(frame, { Position = UDim2.new(1, -358, 0, 11), Size = UDim2.fromOffset(64, 36) }),
		move = Ui.button(frame, { Position = UDim2.new(1, -288, 0, 11), Size = UDim2.fromOffset(78, 36) }),
		nursery = Ui.button(frame, { Position = UDim2.new(1, -204, 0, 11), Size = UDim2.fromOffset(96, 36) }),
		sell = Ui.button(frame, { Position = UDim2.new(1, -102, 0, 11), Size = UDim2.fromOffset(94, 36) }),
		sellArmedUntil = 0,
		release = Ui.button(
			frame,
			{ Position = UDim2.new(1, -470, 0, 11), Size = UDim2.fromOffset(106, 36) }
		),
		releaseArmedUntil = 0,
	}

	local function request(action: string)
		local creature = latest[uid]
		if creature and not creature.carried then
			ClientState.request("CreatureAction", action, uid)
		end
	end
	local function collapse()
		row.expanded = false
		picker.Visible = false
		frame.Size = UDim2.new(1, -10, 0, ROW_HEIGHT)
	end
	local function choice(order: number, count: number, label: string, enabled: boolean, onPick: () -> ())
		-- `count` buttons share the row (a full base has 8, which don't fit at 76 wide)
		local button = Ui.button(picker, {
			Size = UDim2.new(1 / count, -6 * (count - 1) / count, 0, PICKER_HEIGHT - 8),
			LayoutOrder = order,
			Text = label,
		})
		local widest = Instance.new("UISizeConstraint")
		widest.MaxSize = Vector2.new(76, math.huge)
		widest.Parent = button
		setButton(button, enabled, Ui.colors.blue)
		button.Activated:Connect(function()
			if enabled then
				onPick()
				collapse()
			end
		end)
	end
	local function expand()
		local creature = latest[uid]
		local state = ClientState.current
		if creature == nil or state == nil then
			return
		end
		for _, child in picker:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local here = creature.slot
		local hereVault = if here then Config.Economy.vaultOfSlot(here) else nil
		local hereHide = if here then Config.Economy.hideOfSlot(here) else nil
		local hereFloor = if here
				and not hereVault
				and not hereHide
				and not isNursery(here)
			then Config.Economy.slotFloor(here)
			else nil
		local count = 1 + (state.floors or 1) + (state.vaults or 0) + (state.hides or 0)
		choice(1, count, "Storage", here ~= nil, function()
			request("store")
		end)
		for floor = 1, state.floors or 1 do
			choice(1 + floor, count, FLOOR_NAMES[floor] or `Floor {floor}`, hereFloor ~= floor, function()
				ClientState.request("CreatureAction", "move", uid, `F{floor}`)
			end)
		end
		for vault = 1, state.vaults or 0 do
			choice(10 + vault, count, `🔒 Vault {vault}`, hereVault ~= vault, function()
				ClientState.request("CreatureAction", "move", uid, `V{vault}`)
			end)
		end
		for spot = 1, state.hides or 0 do
			local label = HIDE_LABELS[spot] or `Hide {spot}`
			choice(20 + spot, count, label, hereHide ~= spot, function()
				ClientState.request("CreatureAction", "move", uid, `H{spot}`)
			end)
		end
		row.expanded = true
		picker.Visible = true
		frame.Size = UDim2.new(1, -10, 0, ROW_HEIGHT + PICKER_HEIGHT)
	end
	row.move.Activated:Connect(function()
		local creature = latest[uid]
		if creature == nil or creature.carried then
			return
		end
		if row.expanded then
			collapse()
		else
			expand()
		end
		updateRow(row, creature)
	end)
	row.nursery.Activated:Connect(function()
		request("nursery")
	end)
	row.walk.Activated:Connect(function()
		request("walk")
	end)
	-- Sell and Release are two-click: the first click arms the button, a second
	-- click within a few seconds confirms
	local function armed(button: TextButton, field: "sellArmedUntil" | "releaseArmedUntil", action: string)
		local update: (Row, Creature) -> () = if field == "sellArmedUntil" then updateSell else updateRelease
		button.Activated:Connect(function()
			local creature = latest[uid]
			if creature == nil or creature.carried then
				return
			end
			if os.clock() < (row :: any)[field] then
				(row :: any)[field] = 0
				request(action)
				return
			end
			local armedUntil = os.clock() + CONFIRM_SECONDS;
			(row :: any)[field] = armedUntil
			update(row, creature)
			task.delay(CONFIRM_SECONDS, function()
				local current = latest[uid]
				if (row :: any)[field] == armedUntil and current then
					(row :: any)[field] = 0
					update(row, current)
				end
			end)
		end)
	end
	armed(row.sell, "sellArmedUntil", "sell")
	armed(row.release, "releaseArmedUntil", "release")
	return row
end

function CreaturesMenu.build(content: Frame)
	summary = Ui.label(content, {
		Size = UDim2.new(1, -200, 0, 22),
		TextScaled = false,
		TextSize = 15,
		TextColor3 = Ui.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	arrangeButton = Ui.button(content, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, -2),
		Size = UDim2.fromOffset(190, 28),
		Text = "⬆ Rarest up top",
		Visible = false,
	})
	arrangeButton.Activated:Connect(function()
		ClientState.request("CreatureAction", "arrange")
	end)
	list = Ui.scrollList(content, {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
	})
	emptyLabel = Ui.label(content, {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 30),
		TextScaled = false,
		TextSize = 18,
		TextColor3 = Ui.colors.muted,
		Text = "No creatures yet. Buy an egg from the conveyor!",
		Visible = false,
	})

	-- The details card covers the list while it's open
	local frame = Ui.panel(content, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.colors.row,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 6,
	})
	local back = Ui.button(frame, {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(96, 32),
		Text = "← Back",
		ZIndex = 7,
	})
	back.Activated:Connect(closeCard)
	local name = Ui.label(frame, {
		Position = UDim2.fromOffset(114, 6),
		Size = UDim2.new(1, -122, 0, 26),
		RichText = true,
		TextScaled = false,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	local subtitle = Ui.label(frame, {
		Position = UDim2.fromOffset(114, 32),
		Size = UDim2.new(1, -122, 0, 16),
		TextScaled = false,
		TextSize = 14,
		TextColor3 = Ui.colors.muted,
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local model = Instance.new("Frame")
	model.BackgroundTransparency = 1
	model.Position = UDim2.fromOffset(8, 56)
	model.Size = UDim2.new(0.38, -8, 1, -64)
	model.ZIndex = 7
	model.Parent = frame
	local info = Ui.scrollList(frame, {
		Position = UDim2.new(0.38, 8, 0, 56),
		Size = UDim2.new(0.62, -16, 1, -64),
		ZIndex = 7,
	})
	local order = 0
	local function line(props: { [string]: any }): TextLabel
		order += 1
		local l = Ui.label(info, {
			LayoutOrder = order,
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			TextStrokeTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		})
		for key, value in props do
			(l :: any)[key] = value
		end
		return l
	end
	local function header(text: string)
		line({ Text = text, TextSize = 16, TextColor3 = HEADER_COLOR })
	end
	local lines: { [string]: TextLabel } = {}
	header("GENETICS")
	lines.finish = line({})
	lines.mutation = line({ RichText = true })
	lines.origin = line({ TextColor3 = Ui.colors.muted })
	header("EARNINGS")
	lines.rate = line({ TextColor3 = Ui.colors.cash })
	lines.breakdown = line({ TextSize = 13, TextColor3 = Ui.colors.muted })
	lines.worth = line({})
	header("GROWTH")
	lines.growth = line({})
	order += 1
	local bar = Instance.new("Frame")
	bar.LayoutOrder = order
	bar.Size = UDim2.new(1, -10, 0, 10)
	bar.BackgroundColor3 = Ui.colors.panel
	bar.BorderSizePixel = 0
	bar.ZIndex = 7
	bar.Parent = info
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.ZIndex = 8
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
	header("ABOUT")
	lines.about = line({ TextColor3 = Ui.colors.muted })
	lines.where = line({})
	card = {
		frame = frame,
		model = model,
		modelKey = "",
		name = name,
		subtitle = subtitle,
		list = info,
		lines = lines,
		growthBar = bar,
		growthFill = fill,
		uid = nil,
		opened = 0,
	}
end

function CreaturesMenu.refresh(state: { [string]: any })
	walkingUid = state.walking
	-- Pedestals first (in slot order), then storage with the best earners on top
	local sorted: { Creature } = table.clone(state.creatures)
	table.sort(sorted, function(a, b)
		local slotA, slotB = a.slot or math.huge, b.slot or math.huge
		if slotA ~= slotB then
			return slotA < slotB
		end
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		return a.uid < b.uid
	end)

	local seen: { [string]: boolean } = {}
	local placed, stored = 0, 0
	for order, creature in sorted do
		local uid: string = creature.uid
		seen[uid] = true
		latest[uid] = creature
		local row = rows[uid]
		if row == nil then
			row = makeRow(uid)
			rows[uid] = row
		end
		row.frame.LayoutOrder = order
		updateRow(row, creature)
		if creature.slot == nil then
			stored += 1
		else
			placed += 1
		end
	end
	for uid, row in rows do
		if not seen[uid] then
			row.frame:Destroy()
			rows[uid] = nil
			latest[uid] = nil
		end
	end

	summary.Text =
		`Pedestals {placed}/{state.pedestals}   Storage {stored}/{state.storageSlots}   · Tap a name for info`
	if card.uid then
		-- The card stays open on the newest data, and closes if the creature is gone
		local creature = latest[card.uid]
		if creature then
			fillCard(creature)
		else
			closeCard()
		end
		return
	end
	-- Sorting only matters once there's somewhere safer to sort into
	arrangeButton.Visible = (state.floors or 1) > 1 or (state.vaults or 0) > 0
	emptyLabel.Visible = placed + stored == 0
end

return CreaturesMenu

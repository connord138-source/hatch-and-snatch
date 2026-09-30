--!strict
-- Creatures menu: everything you own, where it is, what it earns and what it sells
-- for. Walk, Place/Store, Nursery, Release (for biome Essence + spins) and Sell send
-- requests; the server checks and applies them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

type Creature = { [string]: any } -- one entry of state.creatures (see StateService)

type Row = {
	frame: Frame,
	strip: Frame,
	name: TextLabel,
	details: TextLabel,
	walk: TextButton,
	move: TextButton,
	nursery: TextButton,
	sell: TextButton,
	sellArmedUntil: number,
	release: TextButton,
	releaseArmedUntil: number,
}

local CONFIRM_SECONDS = 3

local finishNames: { [string]: string } = {}
for _, finish in Config.Finishes do
	finishNames[finish.id] = finish.displayName
end

local summary: TextLabel
local list: ScrollingFrame
local emptyLabel: TextLabel
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

local function fullName(creature: Creature): string
	local parts = {}
	if creature.finish ~= "Normal" then
		table.insert(parts, finishNames[creature.finish] or creature.finish)
	end
	if creature.mutation then
		table.insert(parts, creature.mutation)
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

local function updateRow(row: Row, creature: Creature)
	local species = Config.CreaturesById[creature.species]
	local rarityColor = Config.Rarities[species.rarity].color
	row.strip.BackgroundColor3 = rarityColor
	row.name.Text = fullName(creature)
	row.name.TextColor3 = rarityColor

	local where: string
	if creature.carried then
		where = "BEING STOLEN!"
	elseif creature.slot == nil then
		where = `In storage (earns {Format.cash(creature.rate)}/s placed)`
	else
		local spot = if isNursery(creature.slot) then "Nursery" else "Pedestal"
		where = `{spot} · +{Format.cash(creature.rate)}/s`
	end
	local parts = { creature.stage, species.rarity, where }
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
	row.move.Text = if creature.slot == nil then "Place" else "Store"
	setButton(row.move, free, Ui.colors.button)
	row.nursery.Visible = creature.slot ~= nil
	row.nursery.Text = if isNursery(creature.slot) then "Leave Nursery" else "To Nursery"
	setButton(row.nursery, free, Ui.colors.blue)
	updateSell(row, creature)
	updateRelease(row, creature)
end

local function makeRow(uid: string): Row
	local frame = Ui.panel(list, {
		Size = UDim2.new(1, -10, 0, 58),
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
	local row: Row = {
		frame = frame,
		strip = strip,
		name = name,
		details = details,
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
	row.move.Activated:Connect(function()
		local creature = latest[uid]
		if creature then
			request(if creature.slot == nil then "place" else "store")
		end
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
		Size = UDim2.new(1, 0, 0, 22),
		TextScaled = false,
		TextSize = 15,
		TextColor3 = Ui.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
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

	summary.Text = `On pedestals: {placed}/{state.pedestals}     In storage: {stored}/{state.storageSlots}`
	emptyLabel.Visible = placed + stored == 0
end

return CreaturesMenu

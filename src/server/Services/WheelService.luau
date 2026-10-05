--!strict
-- The Luck Wheel (docs/GDD.md §3.1): a game-show wheel at the North Commons
-- (LuckWheel.luau builds it). A player presses its big red button to spend a
-- spin; the server picks the prize and publishes the spin as attributes on
-- ReplicatedStorage.LuckWheelState, and every client animates the same spin from
-- them (LuckWheelController), even while the wheel itself is streamed out.
--
-- Owner, 2026-10-04 ("VERY crude and glitchy"): pressing while it turns joins a
-- line (one place per player) instead of being turned away, and "Spin all" keeps
-- a player in the line until their spins run out (it pauses on a ×10 or better
-- luck charge, so the next spins don't waste it). Each result stays up a moment
-- before the next spin starts. Prizes: a luck charge for the player's NEXT egg
-- (the best unspent charge is kept), cash, or spins back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local LuckWheel = require(script.Parent.Parent.LuckWheel)
local Net = require(script.Parent.Parent.Net)
local Reach = require(script.Parent.Parent.Reach)
local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.Parent.Guard)
local EconomyService = require(script.Parent.EconomyService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)

local SPIN_SECONDS = 5.5
local SETTLE_SECONDS = 0.25 -- after the clients' spin ends, the server pays out
local RESULT_SECONDS = 1.8 -- the result shows this long before the next spin in line
local IDLE_SECONDS = 8 -- then the sign goes back to inviting a spin
local AUTO_PAUSE_LUCK = 10 -- "Spin all" pauses once it wins a luck charge this big
local IDLE_TEXT = "Press the big red button to spin!"
local tunables = Config.Economy.tunables
local rng = Random.new()

type Entry = { player: Player, auto: boolean, prize: Prize?, paid: boolean? }
type Prize = { index: number, amount: number, detail: string }

local queue: { Entry } = {}
local current: Entry? = nil
local resting = false -- a result is showing; the next spin waits for it
local spinCount = 0
local state: Folder

local WheelService = {}

local function pickSegment(): number
	local total = 0
	for _, segment in tunables.luckWheel do
		total += segment.weight
	end
	local roll = rng:NextNumber() * total
	for index, segment in tunables.luckWheel do
		roll -= segment.weight
		if roll <= 0 then
			return index
		end
	end
	return 1
end

-- Where the wheel stops for slice `index`, in degrees: slice i sits (i - 1) × slice
-- round from the top, so turning by that angle brings it under the flapper. It
-- stops in a gap between two pegs, where the flapper hangs straight (playtest
-- 2026-10-04: stopped against a peg, it rested tilted ~30°). Between 0.70 and 0.85
-- of a gap past a peg no peg touches the flapper (LuckWheelController `pushed`);
-- the gaps used stay well inside the slice, clear of its edges.
local function landingAngle(index: number): number
	local slice = 360 / #tunables.luckWheel
	local spacing = 360 / LuckWheel.PEGS
	local offsets: { number } = {}
	for k = -LuckWheel.PEGS, LuckWheel.PEGS do
		local offset = (k + rng:NextNumber(0.7, 0.85)) * spacing
		if math.abs(offset) <= slice * 0.35 then
			table.insert(offsets, offset)
		end
	end
	local offset = if #offsets > 0 then offsets[rng:NextInteger(1, #offsets)] else 0
	return (index - 1) * slice + offset
end

local function setStatus(text: string)
	local wheel = WorldService.luckWheel
	if wheel then
		wheel.status.Text = text
	end
	state:SetAttribute("Queue", #queue)
end

local function spinningText(): string
	local name = if current then current.player.DisplayName else "Someone"
	local line = if #queue > 0 then `  ·  {#queue} in line` else ""
	return `🎡 <b>{name}</b> is spinning…{line}`
end

local function entryOf(player: Player): (Entry?, number?)
	if current and current.player == player then
		return current, 0
	end
	for place, entry in queue do
		if entry.player == player then
			return entry, place
		end
	end
	return nil, nil
end

local function nextFreeSpin(data: DataService.PlayerData): string
	local seconds = math.max(0, math.ceil(tunables.freeSpinSeconds - data.spinProgress))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- What the spin pays, worked out when it starts so the clients can show it as
-- the wheel stops (cash is valued at the player's income right now).
local function prepare(player: Player, data: DataService.PlayerData, index: number): Prize
	local segment = tunables.luckWheel[index]
	if segment.kind == "luck" then
		local detail = if segment.value > data.luckCharge
			then `Your next egg rolls with ×{segment.value} luck`
			else `You already hold ×{data.luckCharge} luck (kept)`
		return { index = index, amount = segment.value, detail = detail }
	elseif segment.kind == "cash" then
		local amount = math.max(500, math.floor(EconomyService.rate(player) * 60 * segment.value))
		return { index = index, amount = amount, detail = `+{Format.cash(amount)} cash` }
	end
	return { index = index, amount = segment.value, detail = `+{segment.value} spins` }
end

local function award(player: Player, prize: Prize)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local segment = tunables.luckWheel[prize.index]
	if segment.kind == "luck" then
		if prize.amount > data.luckCharge then
			data.luckCharge = prize.amount
		end
		if prize.amount >= 25 then
			Net.announce(`{player.DisplayName} hit the ×25 JACKPOT on the Luck Wheel!`, segment.color)
		end
	elseif segment.kind == "cash" then
		EconomyService.grant(player, prize.amount, "LuckWheel")
	elseif segment.kind == "spin" then
		data.spins += prize.amount
	end
	DataService.markDirty(player)
end

local startNext: () -> ()

-- Pays the entry's prize once (at the end of its spin, or as its player leaves).
local function payOut(entry: Entry)
	local prize = entry.prize
	if prize and not entry.paid then
		entry.paid = true
		award(entry.player, prize)
	end
end

local function settle(entry: Entry, prize: Prize, to: number)
	local wheel = WorldService.luckWheel
	local player = entry.player
	state:SetAttribute("Angle", to % 360)
	if wheel then
		wheel.disc:PivotTo(wheel.base * CFrame.Angles(0, 0, math.rad(to)))
	end
	local data = DataService.get(player)
	local before = if data then data.luckCharge else 1
	if player.Parent and data then
		payOut(entry)
	end
	local segment = tunables.luckWheel[prize.index]

	-- "Spin all": back of the line while spins last, unless it just won a big charge
	if entry.auto and player.Parent and data then
		if segment.kind == "luck" and prize.amount >= AUTO_PAUSE_LUCK and prize.amount > before then
			entry.auto = false
			Net.notify(
				player,
				`Auto-spin paused: your next egg has ×{prize.amount} luck. Buy an egg to use it!`,
				"rare"
			)
		elseif data.spins > 0 then
			table.insert(queue, entry)
		else
			Net.notify(player, "Auto-spin done: you're out of spins.", "info")
		end
	end

	local name = player.DisplayName
	setStatus(`<font color="#{segment.color:ToHex()}"><b>{name}</b> won {segment.label}!</font>`)
end

local function finish(entry: Entry, prize: Prize, to: number, id: number)
	-- Whatever goes wrong paying out, the wheel must free up for the next in line
	Guard.run("WheelService.finish", settle, entry, prize, to)
	current = nil
	resting = true
	task.delay(RESULT_SECONDS, function()
		resting = false
		startNext()
	end)
	task.delay(IDLE_SECONDS, function()
		if current == nil and #queue == 0 and spinCount == id then
			setStatus(IDLE_TEXT)
		end
	end)
end

-- Starts this entry's spin; false if it can't (left, or out of spins).
local function begin(entry: Entry): boolean
	local wheel = WorldService.luckWheel
	local player = entry.player
	local data = DataService.get(player)
	if wheel == nil or data == nil or player.Parent == nil or data.spins <= 0 then
		return false
	end
	data.spins -= 1
	ProgressionService.bump(player, "spinsUsed")
	DataService.markDirty(player)
	current = entry

	local index = pickSegment()
	local prize = prepare(player, data, index)
	entry.prize = prize
	entry.paid = false
	local from = (state:GetAttribute("Angle") :: number) % 360
	-- Five to six full turns, ending on the prize
	local to = 6 * 360 + landingAngle(index)
	spinCount += 1
	local id = spinCount
	state:SetAttribute("SpinFrom", from)
	state:SetAttribute("SpinTo", to)
	state:SetAttribute("SpinDuration", SPIN_SECONDS)
	state:SetAttribute("SpinStart", Workspace:GetServerTimeNow())
	state:SetAttribute("SpinIndex", index)
	state:SetAttribute("SpinnerUserId", player.UserId)
	state:SetAttribute("SpinnerName", player.DisplayName)
	state:SetAttribute("SpinDetail", prize.detail)
	state:SetAttribute("SpinId", id) -- last: clients read the whole spin when this changes
	setStatus(spinningText())

	task.delay(SPIN_SECONDS + SETTLE_SECONDS, finish, entry, prize, to, id)
	return true
end

startNext = function()
	if current or resting then
		return
	end
	while #queue > 0 do
		local entry = table.remove(queue, 1) :: Entry
		local started = false
		Guard.run("WheelService.begin", function()
			started = begin(entry)
		end)
		if started then
			return
		end
		current = nil -- it failed part-way: don't leave the wheel held
	end
	state:SetAttribute("Queue", 0)
end

local function request(player: Player, auto: boolean)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local entry, place = entryOf(player)
	if entry then
		if auto then
			entry.auto = not entry.auto
			Net.notify(
				player,
				if entry.auto
					then "Auto-spin on: you'll keep spinning until your spins run out."
					else "Auto-spin off.",
				"info"
			)
		elseif place == 0 then
			Net.notify(player, "Your spin is turning!", "info")
		else
			Net.notify(player, `You're #{place} in line for the wheel.`, "info")
		end
		return
	end
	if data.spins <= 0 then
		Net.notify(
			player,
			`No spins left. Next free spin in {nextFreeSpin(data)} (achievements and daily rewards give more).`,
			"bad"
		)
		return
	end
	table.insert(queue, { player = player, auto = auto })
	if current then
		Net.notify(player, `You're #{#queue} in line: the wheel is turning.`, "info")
		setStatus(spinningText())
	else
		startNext()
	end
end

function WheelService.start()
	state = Instance.new("Folder")
	state.Name = "LuckWheelState"
	state:SetAttribute("Angle", 0)
	state:SetAttribute("SpinId", 0)
	state:SetAttribute("Queue", 0)
	state.Parent = ReplicatedStorage

	-- Leaving mid-spin still pays (the spin was already spent)
	DataService.releasing:connect(function(player: Player)
		local spinning = current
		if spinning and spinning.player == player then
			Guard.run("WheelService.leave", payOut, spinning)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		for i = #queue, 1, -1 do
			if queue[i].player == player then
				table.remove(queue, i)
			end
		end
		state:SetAttribute("Queue", #queue)
	end)

	local wheel = WorldService.luckWheel
	if wheel then
		wheel.prompt.Triggered:Connect(function(player)
			if Reach.prompt(player, wheel.prompt) then
				request(player, false)
			end
		end)
		wheel.spinAllPrompt.Triggered:Connect(function(player)
			if Reach.prompt(player, wheel.spinAllPrompt) then
				request(player, true)
			end
		end)
	end
end

return WheelService

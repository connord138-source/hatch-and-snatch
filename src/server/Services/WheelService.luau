--!strict
-- The Luck Wheel (docs/GDD.md §3.1): a physical wheel beside the plaza. A player
-- spends a spin at its stand; the server picks the prize, and every client
-- animates the same spin (LuckWheelController) from attributes on the disc. One
-- spin at a time. Prizes: a luck charge for the player's NEXT egg (the best
-- unspent charge is kept), cash, or spins back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)

local SPIN_SECONDS = 5.5
local tunables = Config.Economy.tunables
local rng = Random.new()
local spinning = false

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

local function award(player: Player, index: number)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local segment = tunables.luckWheel[index]
	if segment.kind == "luck" then
		if segment.value > data.luckCharge then
			data.luckCharge = segment.value
		end
		Net.notify(player, `{segment.label}! Your next egg rolls with ×{data.luckCharge} luck.`, "rare")
		if segment.value >= 25 then
			Net.announce(`{player.DisplayName} hit the ×25 JACKPOT on the Luck Wheel!`, segment.color)
		end
	elseif segment.kind == "cash" then
		local amount = math.max(500, math.floor(EconomyService.rate(player) * 60 * segment.value))
		EconomyService.grant(player, amount, "LuckWheel")
		Net.notify(player, `Luck Wheel: +{Format.cash(amount)}!`, "good")
	elseif segment.kind == "spin" then
		data.spins += segment.value
		Net.notify(player, `Luck Wheel: +{segment.value} spins!`, "good")
	end
	DataService.markDirty(player)
end

local function spin(player: Player)
	local wheel = WorldService.luckWheel
	local data = DataService.get(player)
	if wheel == nil or data == nil then
		return
	end
	if spinning then
		Net.notify(player, "The wheel is already spinning — wait for it to stop.", "bad")
		return
	end
	if data.spins <= 0 then
		Net.notify(
			player,
			"No spins left. You earn one every 20 minutes you play (and from achievements).",
			"bad"
		)
		return
	end
	data.spins -= 1
	spinning = true
	ProgressionService.bump(player, "spinsUsed")
	DataService.markDirty(player)

	local index = pickSegment()
	local slice = 360 / #tunables.luckWheel
	local from = wheel.disc:GetAttribute("Angle") :: number
	-- Slice i sits (i - 1) × slice clockwise from the top; turning by that angle
	-- brings it under the pointer. Five full turns, plus a little jitter inside it.
	local landing = (index - 1) * slice + (rng:NextNumber() - 0.5) * slice * 0.6
	local to = (math.floor(from / 360) + 6) * 360 + landing
	wheel.disc:SetAttribute("SpinFrom", from)
	wheel.disc:SetAttribute("SpinTo", to)
	wheel.disc:SetAttribute("SpinDuration", SPIN_SECONDS)
	wheel.disc:SetAttribute("Spinner", player.DisplayName)
	wheel.disc:SetAttribute("SpinStart", Workspace:GetServerTimeNow())
	wheel.prompt.Enabled = false

	task.delay(SPIN_SECONDS + 0.2, function()
		wheel.disc:SetAttribute("Angle", to)
		wheel.disc:PivotTo(wheel.base * CFrame.Angles(0, 0, math.rad(to)))
		wheel.prompt.Enabled = true
		spinning = false
		if player.Parent then
			award(player, index)
		end
	end)
end

function WheelService.start()
	local wheel = WorldService.luckWheel
	if wheel then
		wheel.prompt.Triggered:Connect(spin)
	end
end

return WheelService

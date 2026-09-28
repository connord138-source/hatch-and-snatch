--!strict
-- Stealing (docs/GDD.md §6). Server-authoritative end to end:
--   • A thief holds "Steal" on someone else's creature -> it is lifted over their head.
--   • Carry speed depends on growth stage; adults can't be jumped with.
--   • Getting back inside your own plot delivers it: it moves to your collection,
--     loses Homegrown and gets a permanent "stolen from" tag.
--   • The owner can "Take back" (adults are easiest to knock loose), a Homegrown
--     creature may break free once, and dying / leaving / timing out returns it.
--   • Base lock: 60 s laser gate (then 45 s cooldown) that ejects intruders.
--   • The record stays in the owner's save until delivery, so a crash mid-steal
--     can never lose or duplicate a creature.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Net = require(script.Parent.Parent.Net)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local WorldService = require(script.Parent.WorldService)

type Outcome = "delivered" | "returned" | "brokeFree" | "takenBack" | "cancelled"

type Carry = {
	thief: Player,
	owner: Player,
	uid: string,
	model: Model,
	expiresAt: number,
	breakFreeAt: number?,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	connections: { RBXScriptConnection },
}

type LockState = { lockedUntil: number, cooldownUntil: number }

local tunables = Config.Economy.tunables
local CARRY_TIMEOUT = 120
local HOMEGROWN_STRUGGLE = 0.8 -- extra carry-speed multiplier for Homegrown creatures
local BREAK_FREE_CHANCE = 0.35
local TAKE_BACK_HOLD: { [string]: number } = { Baby = 1.0, Juvenile = 0.6, Adult = 0.3 }

local carries: { [Player]: Carry } = {} -- keyed by thief
local locks: { [number]: LockState } = {} -- keyed by plot index
local rng = Random.new()

local StealService = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

function StealService.carryingName(thief: Player): string?
	local carry = carries[thief]
	if carry == nil then
		return nil
	end
	local data = DataService.get(carry.owner)
	local record = data and data.creatures[carry.uid]
	return if record then Config.CreaturesById[record.species].displayName else nil
end

function StealService.lockState(player: Player): LockState?
	local plot = PlotService.get(player)
	return if plot then locks[plot.index] else nil
end

local function isLocked(plot: WorldService.PlotLayout): boolean
	local lock = locks[plot.index]
	return lock ~= nil and serverNow() < lock.lockedUntil
end

local function isProtected(owner: Player): boolean
	if Timing.isStudio() and Config.Debug.studioSkipNewPlayerProtection then
		return false
	end
	local data = DataService.get(owner)
	return data ~= nil and Timing.now() < data.createdAt + tunables.newPlayerProtectionSeconds
end

local function endCarry(carry: Carry, outcome: Outcome)
	if carries[carry.thief] ~= carry then
		return
	end
	carries[carry.thief] = nil
	for _, connection in carry.connections do
		connection:Disconnect()
	end
	carry.model:Destroy()

	local humanoid = humanoidOf(carry.thief)
	if humanoid then
		humanoid.WalkSpeed = carry.walkSpeed
		humanoid.JumpPower = carry.jumpPower
		humanoid.JumpHeight = carry.jumpHeight
	end

	local owner, thief, uid = carry.owner, carry.thief, carry.uid
	local ownerData = DataService.get(owner)
	local record = ownerData and ownerData.creatures[uid]
	local name = if record then Config.CreaturesById[record.species].displayName else "creature"

	if outcome == "delivered" and record then
		local creature = Config.CreaturesById[record.species]
		CreatureService.remove(owner, uid)
		CreatureService.add(thief, {
			species = record.species,
			stage = record.stage,
			stageStartedAt = record.stageStartedAt,
			finish = record.finish,
			mutation = record.mutation,
			homegrown = false,
			stolenFrom = owner.DisplayName,
		})
		Net.notify(thief, `You stole {owner.DisplayName}'s {name}!`, "rare")
		Net.notify(owner, `{thief.DisplayName} stole your {name}!`, "bad")
		local event = EventService.active()
		if event and event.stealCashBonus > 0 then
			local bonus = math.floor(Config.Eggs.price(creature.biome) * event.stealCashBonus)
			EconomyService.grant(thief, bonus)
			Net.notify(thief, `{event.displayName} bonus: +{Format.cash(bonus)}`, "good")
		end
		if Config.Rarities[creature.rarity].order >= 5 or record.finish ~= "Normal" then
			Net.announce(
				`{thief.DisplayName} stole {owner.DisplayName}'s {name}!`,
				Config.Rarities[creature.rarity].color
			)
		end
	else
		CreatureService.setCarried(owner, uid, false)
		if outcome ~= "cancelled" then
			CreatureService.respawn(owner, uid)
		end
		if outcome == "takenBack" then
			Net.notify(thief, `{owner.DisplayName} took their {name} back!`, "bad")
			Net.notify(owner, `You got your {name} back!`, "good")
		elseif outcome == "brokeFree" then
			Net.notify(thief, `The {name} broke free and ran home!`, "bad")
			Net.notify(owner, `Your Homegrown {name} escaped from {thief.DisplayName}!`, "good")
		elseif outcome == "returned" then
			Net.notify(thief, `You dropped the {name} — it went home.`, "bad")
			Net.notify(owner, `Your {name} made it home.`, "good")
		end
	end
	DataService.markDirty(thief)
	DataService.markDirty(owner)
end

local function tryGrab(thief: Player, owner: Player, uid: string)
	if thief == owner or carries[thief] then
		return
	end
	local ownerData, thiefData = DataService.get(owner), DataService.get(thief)
	local record = ownerData and ownerData.creatures[uid]
	local ownerPlot, thiefPlot = PlotService.get(owner), PlotService.get(thief)
	if record == nil or thiefData == nil or ownerPlot == nil or thiefPlot == nil then
		return
	end
	if CreatureService.isCarried(owner, uid) then
		return
	end
	if CreatureService.isNursery(record.slot) then
		Net.notify(thief, "Creatures in a nursery can't be stolen.", "bad")
		return
	end
	if isLocked(ownerPlot) then
		Net.notify(thief, "That base is locked!", "bad")
		return
	end
	if isProtected(owner) then
		Net.notify(thief, `{owner.DisplayName} is new — their base is protected for a few minutes.`, "bad")
		return
	end
	local humanoid, root = humanoidOf(thief)
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	local pedestalModel = ownerPlot.model:FindFirstChild(`{record.species}_{uid}`)
	local target = if pedestalModel and pedestalModel:IsA("Model")
		then pedestalModel:GetPivot().Position
		else ownerPlot.origin.Position
	if (root.Position - target).Magnitude > 16 then
		return -- prompt range is 10; allow some latency slack but reject far-away triggers
	end

	-- Lift the creature over the thief's head
	CreatureService.setCarried(owner, uid, true)
	local model = CreatureService.buildCarryModel(owner, uid, record)
	local extents = model:GetExtentsSize()
	model:PivotTo(root.CFrame * CFrame.new(0, 3 + extents.Y / 2, 0))
	local primary = model.PrimaryPart :: BasePart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = primary
	weld.Parent = model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= primary then
			local inner = Instance.new("WeldConstraint")
			inner.Part0 = primary
			inner.Part1 = descendant
			inner.Parent = descendant
		end
	end

	local stage = Config.Stages[record.stage :: Types.StageId]
	local takeBack = Instance.new("ProximityPrompt")
	takeBack.Name = "TakeBack"
	takeBack.ActionText = "Take back"
	takeBack.ObjectText = Config.CreaturesById[record.species].displayName
	takeBack.HoldDuration = TAKE_BACK_HOLD[record.stage] or 0.6
	takeBack.MaxActivationDistance = 12
	takeBack.RequiresLineOfSight = false
	takeBack:SetAttribute("VisibleTo", "owner")
	takeBack.Parent = primary
	model.Parent = thief.Character

	local carry: Carry = {
		thief = thief,
		owner = owner,
		uid = uid,
		model = model,
		expiresAt = os.clock() + CARRY_TIMEOUT,
		breakFreeAt = if record.homegrown and rng:NextNumber() < BREAK_FREE_CHANCE
			then os.clock() + rng:NextNumber(2, 5)
			else nil,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		connections = {},
	}
	carries[thief] = carry

	local speed = stage.carrySpeed * (if record.homegrown then HOMEGROWN_STRUGGLE else 1)
	humanoid.WalkSpeed = carry.walkSpeed * speed
	if not stage.thiefCanJump then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	table.insert(
		carry.connections,
		takeBack.Triggered:Connect(function(who)
			if who == owner then
				endCarry(carry, "takenBack")
			end
		end)
	)
	table.insert(
		carry.connections,
		humanoid.Died:Connect(function()
			endCarry(carry, "returned")
		end)
	)

	local name = Config.CreaturesById[record.species].displayName
	Net.notify(thief, `Got the {name}! Get it back to your base!`, "rare")
	Net.notify(owner, `{thief.DisplayName} is stealing your {name}! Catch them!`, "bad")
	DataService.markDirty(thief)
	DataService.markDirty(owner)
end

local function tryLock(player: Player, plot: WorldService.PlotLayout)
	if PlotService.ownerOf(plot) ~= player then
		return
	end
	local now = serverNow()
	local lock = locks[plot.index]
	if lock and now < lock.cooldownUntil then
		local wait = math.ceil(lock.cooldownUntil - now)
		Net.notify(player, `Lock recharging — {Format.duration(wait)}`, "bad")
		return
	end
	local event = EventService.active()
	local duration = tunables.lockDurationSeconds * (if event then event.lockDurationMultiplier else 1)
	locks[plot.index] =
		{ lockedUntil = now + duration, cooldownUntil = now + duration + tunables.lockCooldownSeconds }
	Net.notify(player, `Base locked for {Format.duration(duration)}!`, "good")
	DataService.markDirty(player)
end

local function refreshLockVisuals(now: number)
	for _, plot in WorldService.plots do
		local lock = locks[plot.index]
		local locked = lock ~= nil and now < lock.lockedUntil
		for _, laser in plot.lasers do
			laser.Transparency = if locked then 0.55 else 1
		end
		if locked and lock then
			plot.lockLabel.Text = `Locked {Format.duration(lock.lockedUntil - now)}`
		elseif lock and now < lock.cooldownUntil then
			plot.lockLabel.Text = `Recharging {Format.duration(lock.cooldownUntil - now)}`
		else
			plot.lockLabel.Text = "Unlocked"
		end
	end
end

local function tick()
	local now = serverNow()
	local clock = os.clock()

	for _, carry in carries do
		local _, root = humanoidOf(carry.thief)
		local thiefPlot = PlotService.get(carry.thief)
		if root and thiefPlot and WorldService.isInsidePlot(thiefPlot, root.Position) then
			endCarry(carry, "delivered")
		elseif carry.breakFreeAt and clock >= carry.breakFreeAt then
			endCarry(carry, "brokeFree")
		elseif clock >= carry.expiresAt or root == nil then
			endCarry(carry, "returned")
		end
	end

	-- Laser gate: push intruders out of locked bases
	for _, plot in WorldService.plots do
		if locks[plot.index] and PlotService.ownerOf(plot) == nil then
			locks[plot.index] = nil -- owner left
		end
		if isLocked(plot) then
			local owner = PlotService.ownerOf(plot)
			for _, player in Players:GetPlayers() do
				if player ~= owner then
					local _, root = humanoidOf(player)
					if root and WorldService.isInsidePlot(plot, root.Position) then
						(player.Character :: Model):PivotTo(WorldService.outsideFront(plot))
						Net.notify(player, "The laser gate pushed you out!", "bad")
					end
				end
			end
		end
	end

	refreshLockVisuals(now)
end

function StealService.start()
	CreatureService.stealRequested:connect(tryGrab)

	for _, plot in WorldService.plots do
		plot.lockPrompt.Triggered:Connect(function(player)
			tryLock(player, plot)
		end)
	end

	DataService.releasing:connect(function(player: Player)
		-- Thief left: the creature goes home. Owner left: it leaves with them.
		local carry = carries[player]
		if carry then
			endCarry(carry, "returned")
		end
		for _, other in carries do
			if other.owner == player then
				endCarry(other, "cancelled")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			tick()
		end
	end)
end

return StealService

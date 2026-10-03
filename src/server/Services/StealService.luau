--!strict
-- Stealing (docs/GDD.md §6). Server-authoritative end to end:
--   • A thief holds "Steal" on someone else's creature -> it is lifted over their head.
--   • Carry speed depends on growth stage; adults can't be jumped with.
--   • Getting back inside your own plot delivers it: it moves to your collection,
--     loses Homegrown and gets a permanent "stolen from" tag.
--   • The owner can "Take back" (adults are easiest to knock loose), a Homegrown
--     creature may break free once, and dying / leaving / timing out returns it.
--   • Base lock: 60 s laser gate (then 45 s cooldown) that ejects intruders.
--   • Floors and vaults: a creature can only be grabbed from its own floor, and one
--     in a vault only from inside the vault while its door is open. The owner locks
--     a vault for a few minutes (then it recharges); a locking door pushes visitors
--     out, and a thief caught inside drops what they took.
--   • The record stays in the owner's save until delivery, so a crash mid-steal
--     can never lose or duplicate a creature; both saves are written right after.
--   • Movement is the client's, so the server checks it: grabs only from inside
--     the base after the prompt's hold time, no moving faster than the carry
--     speed allows (a teleport drops the creature), and a re-stolen creature
--     pays no steal rewards for a while (so two accounts can't farm each other).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local Reach = require(script.Parent.Parent.Reach)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)
local BaseKit = require(script.Parent.Parent.BaseKit)

type Outcome = "delivered" | "returned" | "brokeFree" | "takenBack" | "cancelled"

type Carry = {
	thief: Player,
	owner: Player,
	uid: string,
	model: Model,
	expiresAt: number,
	breakFreeAt: number?,
	walkSpeed: number,
	moveSpeed: number, -- carrying speed (before any tripwire)
	jumpPower: number,
	jumpHeight: number,
	connections: { RBXScriptConnection },
	-- movement checks
	grabPosition: Vector3,
	grabbedAt: number,
	lastPosition: Vector3,
	lastAt: number,
}

type LockState = { lockedUntil: number, cooldownUntil: number }

local tunables = Config.Economy.tunables
local CARRY_TIMEOUT = 120
local HOMEGROWN_STRUGGLE = 0.8 -- extra carry-speed multiplier for Homegrown creatures
local BREAK_FREE_CHANCE = 0.35
local TAKE_BACK_HOLD: { [string]: number } = { Baby = 1.0, Juvenile = 0.6, Adult = 0.3 }
local MIN_INSIDE_SECONDS = 0.9 -- in the base at least this long before a grab (the Steal hold is 1.2 s+)
local MOVE_SLACK = 1.5 -- carry movement allowed per tick: speed × time × slack + MOVE_GRACE studs
local MOVE_GRACE = 3
local RESTEAL_COOLDOWN = 30 * 60 -- a creature stolen this recently pays no steal rewards
local ALARM_COOLDOWN = 10 -- seconds between alarms for the same intruder

local carries: { [Player]: Carry } = {} -- keyed by thief
local locks: { [number]: LockState } = {} -- keyed by plot index
local vaultLocks: { [number]: { [number]: LockState } } = {} -- plot index -> vault -> lock
local intruders: { [number]: { [Player]: number } } = {} -- plot index -> player -> os.clock() they walked in
local lastAlarm: { [number]: { [Player]: number } } = {} -- plot index -> player -> os.clock() of the alarm
local lastIntruderAt: { [number]: number } = {} -- plot index -> os.clock() someone was last inside
local THREAT_SECONDS = 5 -- how long after an intruder leaves the base still counts as under threat

-- Bought security items (Config.BaseBuilds), every one on a timer: nothing makes a
-- base unbreakable (owner, 2026-10-01). Keyed by plot index.
type Timer = { activeUntil: number, readyAt: number }
local spikes: { [number]: Timer } = {}
local rampGates: { [number]: Timer } = {}
local ballistaReadyAt: { [number]: number } = {}
local searchlightReadyAt: { [number]: number } = {}
local rooted: { [Player]: boolean } = {} -- caught in a spike strip right now

local function ownsBuild(owner: Player?, id: string): boolean
	local data = owner and DataService.get(owner)
	return data ~= nil and data.builds[id] == true
end

local function buildTimes(id: string): (number, number)
	local item = Config.BaseBuilds.byId[id]
	return item and item.active or 0, item and item.recharge or 0
end
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

-- Whether someone else is in the player's base (or just left): pedestal
-- creatures can't be stored, walked or moved to the nursery then, so a thief
-- can't be dodged by pulling a creature away mid-grab.
function StealService.underThreat(player: Player): boolean
	local plot = PlotService.get(player)
	local at = plot and lastIntruderAt[plot.index]
	return at ~= nil and os.clock() - at < THREAT_SECONDS
end

function StealService.lockState(player: Player): LockState?
	local plot = PlotService.get(player)
	return if plot then locks[plot.index] else nil
end

local function isLocked(plot: WorldService.PlotLayout): boolean
	local lock = locks[plot.index]
	return lock ~= nil and serverNow() < lock.lockedUntil
end

local function vaultLocked(plot: WorldService.PlotLayout, vault: number): boolean
	local lock = vaultLocks[plot.index] and vaultLocks[plot.index][vault]
	return lock ~= nil and serverNow() < lock.lockedUntil
end

-- Each vault's lock timers, for the client (0 when it has never been locked).
function StealService.vaultStates(player: Player): { LockState }
	local plot = PlotService.get(player)
	local states: { LockState } = {}
	for vault = 1, #tunables.vaults do
		local lock = plot and vaultLocks[plot.index] and vaultLocks[plot.index][vault]
		states[vault] = if lock
			then { lockedUntil = lock.lockedUntil, cooldownUntil = lock.cooldownUntil }
			else { lockedUntil = 0, cooldownUntil = 0 }
	end
	return states
end

local function isProtected(owner: Player): boolean
	if Timing.isStudio() and Config.Debug.studioSkipNewPlayerProtection then
		return false
	end
	local data = DataService.get(owner)
	return data ~= nil and Timing.now() < data.createdAt + tunables.newPlayerProtectionSeconds
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function endCarry(carry: Carry, outcome: Outcome)
	if carries[carry.thief] ~= carry then
		return
	end
	-- Delivery needs somewhere to put it: the thief's data and a free spot
	if outcome == "delivered" then
		local thiefData = DataService.get(carry.thief)
		if thiefData == nil then
			outcome = "returned"
		elseif not CreatureService.hasRoom(thiefData) then
			Net.notify(carry.thief, "You had no room for it, so it ran home.", "bad")
			outcome = "returned"
		end
	end
	carries[carry.thief] = nil
	carry.thief:SetAttribute("Carrying", nil)
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
		local now = Timing.now()
		-- Stolen again soon after its last steal: it still changes hands, but pays
		-- no XP, bonus or announcement (stops two accounts farming each other)
		local rewarded = record.stolenAt == nil or now - record.stolenAt >= RESTEAL_COOLDOWN
		CreatureService.remove(owner, uid)
		CreatureService.add(thief, {
			species = record.species,
			stage = record.stage,
			stageStartedAt = record.stageStartedAt,
			finish = record.finish,
			mutation = record.mutation,
			homegrown = false,
			eggBiome = record.eggBiome,
			stolenFrom = owner.DisplayName,
			stolenAt = now,
		})
		-- The creature just moved between two saves: write both now
		DataService.save(owner)
		DataService.save(thief)
		Net.notify(thief, `You stole {owner.DisplayName}'s {name}!`, "rare")
		Net.notify(owner, `{thief.DisplayName} stole your {name}!`, "bad")
		Analytics.event(thief, "Steal", 1, { tostring(creature.rarity), record.stage })
		if rewarded then
			ProgressionService.addXp(thief, Config.Progression.xp.steal)
			ProgressionService.bump(thief, "steals")
			local event = EventService.active()
			if event and event.stealCashBonus > 0 then
				local bonus = math.floor(Config.Eggs.price(creature.biome) * event.stealCashBonus)
				EconomyService.grant(thief, bonus, "MoonStealBonus")
				Net.notify(thief, `{event.displayName} bonus: +{Format.cash(bonus)}`, "good")
			end
			if Config.Rarities[creature.rarity].order >= 5 or record.finish ~= "Normal" then
				Net.announce(
					`{thief.DisplayName} stole {owner.DisplayName}'s {name}!`,
					Config.Rarities[creature.rarity].color
				)
			end
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

-- Searchlight: a thief grabbing from this base is lit up and marked for everyone
-- for a while (then the light recharges).
local function markThief(owner: Player, plot: WorldService.PlotLayout, thief: Player)
	local now = serverNow()
	if not ownsBuild(owner, "Searchlight") or now < (searchlightReadyAt[plot.index] or 0) then
		return
	end
	local active, recharge = buildTimes("Searchlight")
	searchlightReadyAt[plot.index] = now + active + recharge
	local character = thief.Character
	local head = character and character:FindFirstChild("Head")
	if character == nil then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "SearchlightMark"
	highlight.FillColor = Color3.fromRGB(255, 235, 120)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = Color3.fromRGB(255, 250, 200)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	local tag: BillboardGui? = nil
	if head and head:IsA("BasePart") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "SearchlightTag"
		gui.Size = UDim2.fromOffset(150, 40)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = Config.BaseBuilds.searchlightRange
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 235, 120)
		label.TextStrokeTransparency = 0.2
		label.Text = "🔦 THIEF!"
		label.Parent = gui
		gui.Parent = head
		tag = gui
	end
	Net.notify(owner, `🔦 Your searchlight is on {thief.DisplayName}!`, "bad")
	task.delay(active, function()
		highlight:Destroy()
		if tag then
			tag:Destroy()
		end
	end)
end

-- Spike strip: the first intruder through the gate is stuck for a moment.
local function trySpikes(owner: Player, plot: WorldService.PlotLayout, player: Player)
	local now = serverNow()
	local state = spikes[plot.index]
	if not ownsBuild(owner, "SpikeStrip") or (state and now < state.readyAt) or rooted[player] then
		return
	end
	local humanoid = humanoidOf(player)
	if humanoid == nil or carries[player] then
		return
	end
	local active, recharge = buildTimes("SpikeStrip")
	spikes[plot.index] = { activeUntil = now + active, readyAt = now + active + recharge }
	rooted[player] = true
	local walkSpeed, jumpPower, jumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	BaseKit.raiseSpikes(plot.security, true)
	Net.notify(player, "Ouch! Caught in the spikes!", "bad")
	Net.notify(owner, `Your spike strip caught {player.DisplayName}!`, "info")
	task.delay(active, function()
		rooted[player] = nil
		if humanoid.Parent and humanoid.WalkSpeed == 0 then
			humanoid.WalkSpeed = walkSpeed
			humanoid.JumpPower = jumpPower
			humanoid.JumpHeight = jumpHeight
		end
		BaseKit.raiseSpikes(plot.security, false)
	end)
end

local function tryGrab(thief: Player, owner: Player, uid: string)
	if thief == owner or carries[thief] or rooted[thief] then
		return
	end
	local ownerData, thiefData = DataService.get(owner), DataService.get(thief)
	local record = ownerData and ownerData.creatures[uid]
	local ownerPlot, thiefPlot = PlotService.get(owner), PlotService.get(thief)
	if record == nil or thiefData == nil or ownerPlot == nil or thiefPlot == nil then
		return
	end
	if
		CreatureService.isCarried(owner, uid)
		or record.slot == nil
		or CreatureService.walkingUid(owner) == uid
	then
		return -- only creatures sitting on a pedestal can be grabbed
	end
	if CreatureService.isNursery(ownerData :: DataService.PlayerData, record.slot) then
		Net.notify(thief, "Creatures in a nursery can't be stolen.", "bad")
		return
	end
	if not CreatureService.hasRoom(thiefData) then
		Net.notify(thief, "You have no room for it. Sell a creature first.", "bad")
		return
	end
	if isLocked(ownerPlot) then
		Net.notify(thief, "That base is locked!", "bad")
		return
	end
	local vault = Config.Economy.vaultOfSlot(record.slot)
	if vault and vaultLocked(ownerPlot, vault) then
		Net.notify(thief, "That vault is locked!", "bad")
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
	if pedestalModel == nil or not pedestalModel:IsA("Model") then
		return
	end
	if (root.Position - pedestalModel:GetPivot().Position).Magnitude > 16 then
		return -- prompt range is 10; allow some latency slack but reject far-away triggers
	end
	-- From inside the base only, and for about as long as the prompt's hold: a
	-- teleport-in-and-grab fails, and the alarm and auto-lock get their chance
	if not WorldService.isInsidePlot(ownerPlot, root.Position) then
		Net.notify(thief, "Get inside their base to steal it!", "bad")
		return
	end
	local enteredAt = intruders[ownerPlot.index] and intruders[ownerPlot.index][thief]
	if enteredAt == nil or os.clock() - enteredAt < MIN_INSIDE_SECONDS then
		return -- not seen inside yet (the tick records entries and sounds the alarm)
	end
	-- Upper floors: only from the creature's own floor (not from the one below);
	-- vaults: only from inside the room
	if
		not WorldService.onFloor(ownerPlot, root.Position, Config.Economy.slotFloor(record.slot :: number))
	then
		return
	end
	if vault and not WorldService.inVault(ownerPlot, vault, root.Position) then
		Net.notify(thief, "Get inside the vault to steal it!", "bad")
		return
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
		moveSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		connections = {},
		grabPosition = root.Position,
		grabbedAt = os.clock(),
		lastPosition = root.Position,
		lastAt = os.clock(),
	}
	carries[thief] = carry
	thief:SetAttribute("Carrying", true) -- clients hide Steal prompts while you carry one
	markThief(owner, ownerPlot, thief)

	local speed = stage.carrySpeed * (if record.homegrown then HOMEGROWN_STRUGGLE else 1)
	carry.moveSpeed = carry.walkSpeed * speed
	humanoid.WalkSpeed = carry.moveSpeed
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

local function security(owner: Player?): number
	local data = owner and DataService.get(owner)
	return if data then data.security else 0
end

local function tryLock(player: Player, plot: WorldService.PlotLayout, automatic: boolean?)
	if PlotService.ownerOf(plot) ~= player then
		return
	end
	if automatic then
		local lock = locks[plot.index]
		if lock and serverNow() < lock.cooldownUntil then
			return -- not charged: auto-lock stays quiet
		end
	end
	local now = serverNow()
	local lock = locks[plot.index]
	if lock and now < lock.cooldownUntil then
		local wait = math.ceil(lock.cooldownUntil - now)
		Net.notify(player, `Lock recharging — {Format.duration(wait)}`, "bad")
		return
	end
	local event = EventService.active()
	local data = DataService.get(player)
	local bonus = if data then Config.Economy.baseLevel(data.baseLevel).lockBonusSeconds else 0
	local duration = (tunables.lockDurationSeconds + bonus)
		* (if event then event.lockDurationMultiplier else 1)
		* (
			if MonetizationService.hasPass(player, "LongerLock")
				then Config.Monetization.tuning.lockMultiplier
				else 1
		)
	locks[plot.index] =
		{ lockedUntil = now + duration, cooldownUntil = now + duration + tunables.lockCooldownSeconds }
	Net.notify(
		player,
		if automatic
			then `Auto-Lock: an intruder walked in — base locked for {Format.duration(duration)}!`
			else `Base locked for {Format.duration(duration)}!`,
		"good"
	)
	DataService.markDirty(player)
end

-- Locks one of the owner's vaults (the door closes for vaultLockSeconds, then it
-- recharges). Anyone else inside is pushed out, dropping what they took.
local function tryLockVault(player: Player, plot: WorldService.PlotLayout, vault: number, automatic: boolean?)
	local data = DataService.get(player)
	local room = plot.vaults[vault]
	if PlotService.ownerOf(plot) ~= player or data == nil or room == nil or not room.owned then
		return
	end
	local now = serverNow()
	local states = vaultLocks[plot.index] or {}
	vaultLocks[plot.index] = states
	local lock = states[vault]
	if lock and now < lock.cooldownUntil then
		if not automatic then
			local wait = math.ceil(lock.cooldownUntil - now)
			Net.notify(player, `Vault {vault} is recharging — {Format.duration(wait)}`, "bad")
		end
		return
	end
	local event = EventService.active()
	local duration = tunables.vaultLockSeconds
		* (if event then event.lockDurationMultiplier else 1)
		* (
			if MonetizationService.hasPass(player, "LongerLock")
				then Config.Monetization.tuning.lockMultiplier
				else 1
		)
	states[vault] =
		{ lockedUntil = now + duration, cooldownUntil = now + duration + tunables.vaultCooldownSeconds }
	for _, other in Players:GetPlayers() do
		local _, root = humanoidOf(other)
		if other ~= player and root and WorldService.inVault(plot, vault, root.Position) then
			local carry = carries[other]
			if carry and carry.owner == player then
				endCarry(carry, "takenBack")
			end
			Net.teleport(other, WorldService.vaultOutside(plot, vault))
			Net.notify(other, "The vault door shut you out!", "bad")
		end
	end
	if not automatic then
		Net.notify(player, `Vault {vault} locked for {Format.duration(duration)}!`, "good")
	end
	DataService.markDirty(player)
end

local function refreshVaultDoors(now: number)
	for _, plot in WorldService.plots do
		local states = vaultLocks[plot.index]
		for vault, room in plot.vaults do
			if not room.owned then
				continue
			end
			local lock = states and states[vault]
			local locked = lock ~= nil and now < lock.lockedUntil
			local text = if locked and lock
				then `🔒 Vault {vault} · {Format.duration(math.ceil(lock.lockedUntil - now))}`
				elseif lock and now < lock.cooldownUntil then `Vault {vault} · recharging {Format.duration(
					math.ceil(lock.cooldownUntil - now)
				)}`
				else `Vault {vault} · open`
			if room.locked ~= locked or room.label.Text ~= text then
				WorldService.setVaultDoor(plot, vault, locked, text)
				room.prompt.ActionText = if locked
					then "Locked"
					elseif lock and now < lock.cooldownUntil then "Recharging"
					else "Lock Vault"
			end
		end
	end
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

-- One carry's checks: tripwire, movement sanity, delivery, break-free, timeout.
local function tickCarry(carry: Carry, clock: number)
	local humanoid, root = humanoidOf(carry.thief)
	local thiefPlot = PlotService.get(carry.thief)
	-- Tripwire: slower while still inside the owner's base
	local ownerPlot = PlotService.get(carry.owner)
	if humanoid and root and ownerPlot then
		local tripped = security(carry.owner) >= 2 and WorldService.isInsidePlot(ownerPlot, root.Position)
		humanoid.WalkSpeed = carry.moveSpeed * (if tripped then tunables.tripwireSlow else 1)
	end
	if root == nil or clock >= carry.expiresAt then
		endCarry(carry, "returned")
		return
	end
	-- Moving faster than the carry speed allows (a teleport or speed hack) drops it
	local moved = flat(root.Position - carry.lastPosition).Magnitude
	local allowed = carry.moveSpeed * (clock - carry.lastAt) * MOVE_SLACK + MOVE_GRACE
	carry.lastPosition = root.Position
	carry.lastAt = clock
	if moved > allowed then
		endCarry(carry, "returned")
		return
	end
	if thiefPlot and WorldService.isInsidePlot(thiefPlot, root.Position) then
		-- It must also have taken about as long as the run should take
		local edge = math.max(thiefPlot.width, thiefPlot.depth) / 2
		local run = math.max(0, flat(carry.grabPosition - thiefPlot.origin.Position).Magnitude - edge)
		if clock - carry.grabbedAt >= 0.7 * run / carry.moveSpeed then
			endCarry(carry, "delivered")
		else
			endCarry(carry, "returned")
		end
	elseif carry.breakFreeAt and clock >= carry.breakFreeAt then
		endCarry(carry, "brokeFree")
	end
end

-- A thief searches a hiding spot: an empty one is a decoy, an occupied one gives
-- up its creature (the normal grab rules apply: locked base, protection, ...).
local function searchSpot(thief: Player, plot: WorldService.PlotLayout, spot: number)
	local owner = PlotService.ownerOf(plot)
	local data = owner and DataService.get(owner)
	if owner == nil or data == nil or thief == owner or carries[thief] then
		return
	end
	local slot = Config.Economy.hideSlot(spot)
	local found: string? = nil
	for uid, record in data.creatures do
		if record.slot == slot and not CreatureService.isCarried(owner, uid) then
			found = uid
		end
	end
	if found == nil then
		Net.notify(thief, Config.BaseBuilds.hidingSpots[spot].empty, "info")
		return
	end
	tryGrab(thief, owner, found)
	local record = data.creatures[found]
	if carries[thief] and record then
		local name = Config.CreaturesById[record.species].displayName
		Net.notify(owner, `⚠ {thief.DisplayName} found your hidden {name}!`, "bad")
		Net.notify(thief, `You found a hidden {name}!`, "rare")
	end
end

-- Ramp gates: the owner pulls the lever and bars both ramps for a while.
local function barRamps(player: Player, plot: WorldService.PlotLayout)
	if PlotService.ownerOf(plot) ~= player or not ownsBuild(player, "RampGates") then
		return
	end
	local now = serverNow()
	local state = rampGates[plot.index]
	if state and now < state.readyAt then
		local left = if now < state.activeUntil then state.activeUntil - now else state.readyAt - now
		Net.notify(
			player,
			`The ramp gates are {if now < state.activeUntil then "down" else "resetting"} ({Format.duration(
				left
			)}).`,
			"info"
		)
		return
	end
	local active, recharge = buildTimes("RampGates")
	rampGates[plot.index] = { activeUntil = now + active, readyAt = now + active + recharge }
	BaseKit.setBars(plot.security, true, plot.floors)
	Net.notify(player, `Ramps barred for {Format.duration(active)}!`, "info")
end

-- Net ballista: the owner nets the nearest thief carrying one of their creatures.
local function fireNet(player: Player, plot: WorldService.PlotLayout)
	if PlotService.ownerOf(plot) ~= player or not ownsBuild(player, "NetBallista") then
		return
	end
	local now = serverNow()
	local readyAt = ballistaReadyAt[plot.index] or 0
	if now < readyAt then
		Net.notify(player, `The ballista is reloading ({Format.duration(readyAt - now)}).`, "info")
		return
	end
	local from = plot.security.ballista.Position
	local target: Carry? = nil
	local best = Config.BaseBuilds.ballistaRange
	for _, carry in carries do
		if carry.owner == player then
			local _, root = humanoidOf(carry.thief)
			local distance = if root then (root.Position - from).Magnitude else math.huge
			if distance <= best then
				best, target = distance, carry
			end
		end
	end
	if target == nil then
		Net.notify(player, "No thief with your creature in range.", "info")
		return
	end
	local _, recharge = buildTimes("NetBallista")
	ballistaReadyAt[plot.index] = now + recharge
	local _, root = humanoidOf(target.thief)
	-- The net flies, then the creature goes home
	local net = Instance.new("Part")
	net.Name = "BallistaNet"
	net.Size = Vector3.new(4, 4, 0.3)
	net.Material = Enum.Material.Fabric
	net.Color = Color3.fromRGB(200, 180, 130)
	net.Transparency = 0.2
	net.Anchored = true
	net.CanCollide = false
	net.CanQuery = false
	net.CFrame = CFrame.new(from + Vector3.new(0, 2, 0))
	net.Parent = Workspace
	if root then
		game:GetService("TweenService")
			:Create(net, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = CFrame.new(root.Position) })
			:Play()
	end
	task.delay(1.2, function()
		net:Destroy()
	end)
	Net.notify(target.thief, `Netted by {player.DisplayName}'s ballista! The creature ran home.`, "bad")
	Net.notify(player, `Got {target.thief.DisplayName}! Your creature is home.`, "rare")
	endCarry(target, "takenBack")
end

-- Security fixtures' prompts follow their timers.
local function refreshFixtures(now: number)
	for _, plot in WorldService.plots do
		local state = rampGates[plot.index]
		local security = plot.security
		if state and now >= state.activeUntil then
			BaseKit.setBars(security, false, plot.floors)
		end
		if state and now < state.activeUntil then
			security.leverPrompt.ActionText = `Barred {Format.duration(state.activeUntil - now)}`
		elseif state and now < state.readyAt then
			security.leverPrompt.ActionText = `Resetting {Format.duration(state.readyAt - now)}`
		else
			security.leverPrompt.ActionText = "Bar the Ramps"
		end
		local readyAt = ballistaReadyAt[plot.index] or 0
		security.ballistaPrompt.ActionText = if now < readyAt
			then `Reloading {Format.duration(readyAt - now)}`
			else "Fire Net"
	end
end

local function tick()
	local now = serverNow()
	local clock = os.clock()
	refreshFixtures(now)

	for _, carry in carries do
		local ok, problem = pcall(function(): any
			tickCarry(carry, clock)
			return nil
		end)
		if not ok then
			warn(`[StealService] carry check failed: {problem}`)
			endCarry(carry, "returned")
		end
	end

	-- Security: alarm (alert + red highlight) and auto-lock on intruders
	for _, plot in WorldService.plots do
		local owner = PlotService.ownerOf(plot)
		local level = security(owner)
		local inside = intruders[plot.index] or {}
		intruders[plot.index] = inside
		local alarms = lastAlarm[plot.index] or {}
		lastAlarm[plot.index] = alarms
		for _, player in Players:GetPlayers() do
			local _, root = humanoidOf(player)
			local isIn = owner ~= nil
				and player ~= owner
				and root ~= nil
				and WorldService.isInsidePlot(plot, (root :: BasePart).Position)
			local character = player.Character
			if isIn then
				lastIntruderAt[plot.index] = clock
			end
			if isIn and not inside[player] then
				inside[player] = clock
				if owner then
					trySpikes(owner, plot, player)
				end
				if
					level >= 1
					and owner
					and character
					and clock - (alarms[player] or -math.huge) >= ALARM_COOLDOWN
				then
					alarms[player] = clock
					Net.notify(owner, `⚠ {player.DisplayName} walked into your base!`, "bad")
				end
				if
					level >= 1
					and owner
					and character
					and character:FindFirstChild("IntruderHighlight") == nil
				then
					local highlight = Instance.new("Highlight")
					highlight.Name = "IntruderHighlight"
					highlight.FillColor = Color3.fromRGB(255, 40, 40)
					highlight.FillTransparency = 0.6
					highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
					highlight.Parent = character
				end
				if level >= 3 and owner and not isLocked(plot) then
					tryLock(owner, plot, true)
				end
				if level >= 3 and owner then
					-- Auto-Lock shuts the vaults too, each one that's charged
					for vault, room in plot.vaults do
						if room.owned and not vaultLocked(plot, vault) then
							tryLockVault(owner, plot, vault, true)
						end
					end
				end
			elseif not isIn and inside[player] then
				inside[player] = nil
				local highlight = character and character:FindFirstChild("IntruderHighlight")
				if highlight then
					highlight:Destroy()
				end
			end
		end
	end

	-- Laser gate: push intruders out of locked bases
	for _, plot in WorldService.plots do
		if PlotService.ownerOf(plot) == nil then
			locks[plot.index] = nil -- owner left
			vaultLocks[plot.index] = nil
		end
		-- A locked vault keeps everyone else out
		local states = vaultLocks[plot.index]
		if states then
			local owner = PlotService.ownerOf(plot)
			for vault in states do
				if vaultLocked(plot, vault) then
					for _, player in Players:GetPlayers() do
						local _, root = humanoidOf(player)
						if player ~= owner and root and WorldService.inVault(plot, vault, root.Position) then
							Net.teleport(player, WorldService.vaultOutside(plot, vault))
						end
					end
				end
			end
		end
		if isLocked(plot) then
			local owner = PlotService.ownerOf(plot)
			for _, player in Players:GetPlayers() do
				if player ~= owner then
					local _, root = humanoidOf(player)
					if root and WorldService.isInsidePlot(plot, root.Position) then
						-- The gate doesn't carry a thief (and the owner's creature) past the tripwire
						local carry = carries[player]
						if carry and carry.owner == owner then
							endCarry(carry, "takenBack")
						end
						Net.teleport(player, WorldService.outsideFront(plot))
						Net.notify(player, "The laser gate pushed you out!", "bad")
					end
				end
			end
		end
	end

	refreshLockVisuals(now)
	refreshVaultDoors(now)
end

function StealService.start()
	CreatureService.stealRequested:connect(tryGrab)
	-- A plot changing hands starts with its gate and vaults unlocked
	PlotService.released:connect(function(plot: WorldService.PlotLayout)
		locks[plot.index] = nil
		vaultLocks[plot.index] = nil
		spikes[plot.index] = nil
		rampGates[plot.index] = nil
		ballistaReadyAt[plot.index] = nil
		searchlightReadyAt[plot.index] = nil
		BaseKit.setBars(plot.security, false, 1)
	end)

	for _, plot in WorldService.plots do
		plot.lockPrompt.Triggered:Connect(function(player)
			tryLock(player, plot)
		end)
		for _, spot in plot.hides do
			local holdStarts: { [Player]: number } = {}
			spot.search.PromptButtonHoldBegan:Connect(function(thief)
				holdStarts[thief] = os.clock()
			end)
			spot.search.Triggered:Connect(function(thief)
				local began = holdStarts[thief]
				holdStarts[thief] = nil
				local held = if began then os.clock() - began else 0
				local hold = Config.BaseBuilds.searchSeconds
				if held < hold * 0.7 or held > hold + 5 or not Reach.prompt(thief, spot.search) then
					return
				end
				searchSpot(thief, plot, spot.spot)
			end)
		end
		plot.security.leverPrompt.Triggered:Connect(function(player)
			if Reach.prompt(player, plot.security.leverPrompt) then
				barRamps(player, plot)
			end
		end)
		plot.security.ballistaPrompt.Triggered:Connect(function(player)
			if Reach.prompt(player, plot.security.ballistaPrompt) then
				fireNet(player, plot)
			end
		end)
		for vault, room in plot.vaults do
			room.prompt.Triggered:Connect(function(player)
				if Reach.prompt(player, room.prompt) then
					tryLockVault(player, plot, vault)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		rooted[player] = nil
		for _, inside in intruders do
			inside[player] = nil
		end
		for _, alarms in lastAlarm do
			alarms[player] = nil
		end
	end)

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
			local ok, problem = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn(`[StealService] tick failed: {problem}`)
			end
		end
	end)
end

return StealService

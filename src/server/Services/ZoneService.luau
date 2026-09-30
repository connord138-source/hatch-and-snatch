--!strict
-- Biome zones (built by WorldService): the gate keeps out anyone who hasn't
-- unlocked the biome yet (same requirement as its eggs), harvest nodes pay that
-- biome's Essence, and the shrine spends it on an egg of the biome or on the
-- biome's blessing (Config.Zones). Nodes are shared: whoever picks one first gets
-- it, and it regrows after nodeRespawnSeconds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Net = require(script.Parent.Parent.Net)
local Reach = require(script.Parent.Parent.Reach)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HatchService = require(script.Parent.HatchService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)

type PlayerData = DataService.PlayerData

local Zones = Config.Zones
local Progression = Config.Progression

local ZoneService = {}

local rng = Random.new()
local lastWarned: { [Player]: number } = {}
-- Nodes a zone event has charged: harvests pay `multiplier` times until `untilTime`
local charged: { [Model]: { untilTime: number, multiplier: number } } = {}

local function essenceName(biomeId: string): string
	return Zones.byBiome[biomeId].essence
end

local function unlocked(data: PlayerData, biomeId: string): boolean
	return Config.Biomes[biomeId].order <= data.unlockedBiome
end

function ZoneService.essence(data: PlayerData, biomeId: string): number
	return data.essence[biomeId] or 0
end

function ZoneService.grantEssence(player: Player, biomeId: string, amount: number)
	local data = DataService.get(player)
	if data == nil or Zones.byBiome[biomeId] == nil or amount <= 0 then
		return
	end
	data.essence[biomeId] = (data.essence[biomeId] or 0) + amount
	DataService.markDirty(player)
end

local function spend(player: Player, data: PlayerData, biomeId: string, cost: number): boolean
	local have = ZoneService.essence(data, biomeId)
	if have < cost then
		Net.notify(
			player,
			`Need {cost - have} more {essenceName(biomeId)}. Harvest the glowing nodes here.`,
			"bad"
		)
		return false
	end
	data.essence[biomeId] = have - cost
	DataService.markDirty(player)
	return true
end

local function requirementText(biomeId: string): string
	local need = Progression.biomeRequirements[biomeId]
	if need == nil then
		return "Open"
	end
	return if need.baseLevel > 1
		then `Hatcher Lv {need.level} + Base Lv {need.baseLevel}`
		else `Hatcher Lv {need.level}`
end

---------------------------------------------------------------------------
-- Harvest nodes
---------------------------------------------------------------------------

local function setNodeVisible(node: Model, visible: boolean)
	for _, child in node:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Crystal" then
			child.Transparency = if visible then 0 else 1
		end
	end
	local light = (node.PrimaryPart :: BasePart):FindFirstChildWhichIsA("PointLight")
	if light then
		light.Enabled = visible
	end
end

local function harvest(player: Player, zone: WorldService.ZoneLayout, node: Model, prompt: ProximityPrompt)
	local data = DataService.get(player)
	if data == nil or not prompt.Enabled then
		return
	end
	if not unlocked(data, zone.biome) then
		return
	end
	prompt.Enabled = false
	setNodeVisible(node, false)
	local amount = rng:NextInteger(Zones.nodeYield[1], Zones.nodeYield[2])
	local charge = charged[node]
	local boosted = charge ~= nil and os.clock() < charge.untilTime
	if charge and boosted then
		amount *= charge.multiplier
	end
	ZoneService.grantEssence(player, zone.biome, amount)
	ProgressionService.addXp(player, 5 * Config.Biomes[zone.biome].order)
	ProgressionService.bump(player, "harvests")
	Net.notify(
		player,
		`{if boosted then "⚡ " else ""}+{amount} {essenceName(zone.biome)} ({ZoneService.essence(
			data,
			zone.biome
		)} total)`,
		"good"
	)
	task.delay(Timing.scaled(Zones.nodeRespawnSeconds), function()
		setNodeVisible(node, true)
		prompt.Enabled = true
	end)
end

-- Charges the zone's nodes within `radius` of `center` for `seconds` (a zone event):
-- picked ones grow back at once, and each pays `multiplier` times its usual Essence.
function ZoneService.chargeNodes(
	zone: WorldService.ZoneLayout,
	center: Vector3,
	radius: number,
	seconds: number,
	multiplier: number
)
	local untilTime = os.clock() + seconds
	for _, node in zone.nodes do
		local rock = node.PrimaryPart :: BasePart
		local offset = rock.Position - center
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > radius then
			continue
		end
		charged[node] = { untilTime = untilTime, multiplier = multiplier }
		local prompt = rock:FindFirstChild("Harvest")
		if prompt and prompt:IsA("ProximityPrompt") and not prompt.Enabled then
			setNodeVisible(node, true)
			prompt.Enabled = true
		end
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Charge"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
		sparks.LightEmission = 1
		sparks.Rate = 25
		sparks.Lifetime = NumberRange.new(0.3, 0.6)
		sparks.Speed = NumberRange.new(4, 9)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new(0.5, 0)
		sparks.Parent = rock
		local light = rock:FindFirstChildWhichIsA("PointLight")
		local brightness = if light then light.Brightness else 0
		if light then
			light.Brightness = brightness * 4
		end
		task.delay(seconds, function()
			sparks:Destroy()
			if light then
				light.Brightness = brightness
			end
			local current = charged[node]
			if current and current.untilTime == untilTime then
				charged[node] = nil
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Shrine
---------------------------------------------------------------------------

local function forgeEgg(player: Player, zone: WorldService.ZoneLayout)
	local data = DataService.get(player)
	if data == nil or not unlocked(data, zone.biome) then
		return
	end
	local biome = Config.Biomes[zone.biome]
	if data.heldEgg then
		Net.notify(player, "You're already carrying an egg — put it in an incubator first.", "bad")
		return
	end
	if not HatchService.hasTierFor(data, zone.biome) then
		Net.notify(
			player,
			`{biome.displayName} eggs need a {HatchService.tierNameFor(zone.biome)} incubator. Upgrade one at your base (R).`,
			"bad"
		)
		return
	end
	if not HatchService.freeIncubatorFor(data, zone.biome) then
		Net.notify(player, "Your incubators are busy — wait for a hatch or buy another incubator.", "bad")
		return
	end
	if not CreatureService.hasRoom(data) then
		Net.notify(player, "Your pedestals and storage are full. Release or sell a creature first.", "bad")
		return
	end
	if not spend(player, data, zone.biome, Zones.eggCost) then
		return
	end
	HatchService.giveEgg(player, zone.biome)
	Net.notify(player, `The shrine forged a {biome.displayName} egg! Carry it home to an incubator.`, "rare")
end

-- Why a blessing can't do anything right now, or nil when it can.
local function blessingBlocked(data: PlayerData, biomeId: string): string?
	local blessing = Zones.byBiome[biomeId].blessing
	if blessing.kind == "hatchSpeed" and #data.incubators == 0 then
		return "No eggs are incubating — start one first, then come back."
	end
	if blessing.kind == "luck" and data.luckCharge >= blessing.value then
		return `Your next egg already has ×{data.luckCharge} luck.`
	end
	return nil
end

local function applyBlessing(player: Player, data: PlayerData, biomeId: string)
	local blessing = Zones.byBiome[biomeId].blessing
	if blessing.kind == "cash" then
		local amount = math.max(250, math.floor(EconomyService.rate(player) * blessing.value))
		EconomyService.grant(player, amount, `Blessing_{biomeId}`)
		Net.notify(player, `{blessing.name}: +{Format.cash(amount)}!`, "good")
	elseif blessing.kind == "spins" then
		data.spins += blessing.value
		Net.notify(player, `{blessing.name}: +{blessing.value} Luck Wheel spins!`, "good")
	elseif blessing.kind == "hatchSpeed" then
		local now = Timing.now()
		for _, egg in data.incubators do
			if egg.hatchAt > now then
				egg.hatchAt = now + math.ceil((egg.hatchAt - now) * blessing.value)
			end
		end
		HatchService.refresh(player, data)
		Net.notify(player, `{blessing.name}: your eggs are hatching twice as fast!`, "good")
	elseif blessing.kind == "luck" then
		data.luckCharge = blessing.value
		Net.notify(player, `{blessing.name}: your next egg gets ×{blessing.value} luck!`, "rare")
	elseif blessing.kind == "xp" then
		local amount = blessing.value * ProgressionService.level(data)
		ProgressionService.addXp(player, amount)
		Net.notify(player, `{blessing.name}: +{amount} XP!`, "good")
	end
	DataService.markDirty(player)
end

-- A biome's blessing for free (zone event prizes). False when it wouldn't do
-- anything right now, so the caller can pay out something else instead.
function ZoneService.giveBlessing(player: Player, biomeId: string): boolean
	local data = DataService.get(player)
	if data == nil or blessingBlocked(data, biomeId) ~= nil then
		return false
	end
	applyBlessing(player, data, biomeId)
	return true
end

local function bless(player: Player, zone: WorldService.ZoneLayout)
	local data = DataService.get(player)
	if data == nil or not unlocked(data, zone.biome) then
		return
	end
	local blocked = blessingBlocked(data, zone.biome)
	if blocked then
		Net.notify(player, blocked, "bad")
		return
	end
	if not spend(player, data, zone.biome, Zones.blessingCost) then
		return
	end
	applyBlessing(player, data, zone.biome)
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	key: Enum.KeyCode,
	hold: number
)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.HoldDuration = hold
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Gate: bounce anyone who hasn't unlocked the zone
---------------------------------------------------------------------------

local function enforceGates()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if data == nil or character == nil or root == nil then
			continue
		end
		for _, zone in WorldService.zones do
			local offset = root.Position - zone.center
			if
				Vector3.new(offset.X, 0, offset.Z).Magnitude < zone.radius and not unlocked(data, zone.biome)
			then
				character:PivotTo(zone.outside)
				if now - (lastWarned[player] or 0) > 3 then
					lastWarned[player] = now
					Net.notify(
						player,
						`🔒 {Config.Biomes[zone.biome].displayName} is locked — needs {requirementText(
							zone.biome
						)}.`,
						"bad"
					)
				end
			end
		end
	end
end

function ZoneService.start()
	for _, zone in WorldService.zones do
		local info = Zones.byBiome[zone.biome]
		zone.gateLabel.Text = `{Config.Biomes[zone.biome].displayName}\n🔒 {requirementText(zone.biome)}`
		zone.gate:SetAttribute("Requirement", requirementText(zone.biome))
		for _, node in zone.nodes do
			local p = prompt(node.PrimaryPart :: BasePart, "Harvest", "Harvest", info.node, Enum.KeyCode.E, 1)
			p.Triggered:Connect(function(player)
				if Reach.prompt(player, p) then
					harvest(player, zone, node, p)
				end
			end)
		end
		local egg = prompt(
			zone.shrine,
			"ForgeEgg",
			`Forge egg ({Zones.eggCost} ✨)`,
			info.essence,
			Enum.KeyCode.E,
			0.6
		)
		egg.Triggered:Connect(function(player)
			if Reach.prompt(player, egg) then
				forgeEgg(player, zone)
			end
		end)
		local blessing = prompt(
			zone.shrine,
			"Blessing",
			`{info.blessing.name} ({Zones.blessingCost} ✨)`,
			info.blessing.description,
			Enum.KeyCode.F,
			0.6
		)
		blessing.Triggered:Connect(function(player)
			if Reach.prompt(player, blessing) then
				bless(player, zone)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastWarned[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			enforceGates()
		end
	end)
end

return ZoneService

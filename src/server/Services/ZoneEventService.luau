--!strict
-- Set-piece events in the biome zones (GDD §7.3, tuning in Config.Zones.events).
-- Every few minutes one landmark in each zone does something worth running for:
-- the Mossvale glowcap ring blooms, the Coral clam opens on a pearl, the Magma vent
-- erupts shards, the Frost boulder cracks open, a huge strike charges the Storm
-- crystals, and a meteor lands in the Moonfall crater. Most prizes go to whoever
-- gets there first, which pulls players away from their bases: a steal window.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local SetPieces = require(script.Parent.Parent.SetPieces)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local ZoneService = require(script.Parent.ZoneService)

type PlayerData = DataService.PlayerData
type Zone = WorldService.ZoneLayout
type Landmark = WorldService.Landmark

local Zones = Config.Zones
local Events = Zones.events

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local ZoneEventService = {}

local rng = Random.new()
local running: { [Zone]: boolean } = {}

local WARNINGS: { [string]: string } = {
	bloom = "🍄 The Glowcap Bloom starts in 10s: stand in the glowing ring for Moss Essence!",
	clam = "🦪 The Giant Clam opens in 10s: first to grab the pearl wins!",
	eruption = "🌋 The Lava Vent erupts in 10s: grab the Ember shards!",
	boulder = "🧊 The Frozen Boulder is cracking in 10s: break it open together!",
	strike = "⚡ A huge strike hits the crag in 10s: charged crystals give ×3 Essence!",
	meteor = "☄️ A meteor falls on Moonfall in 10s: first to grab the moonstone gets ×10 luck!",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function light(parent: BasePart, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = parent
	return l
end

local function emitter(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0.8
	e.Shape = Enum.ParticleEmitterShape.Box
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function sparkles(parent: BasePart, color: Color3, rate: number)
	emitter(parent, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color),
		Rate = rate,
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.5, 0),
		Transparency = NumberSequence.new(0.1, 1),
	})
end

local function unlocked(data: PlayerData, biomeId: string): boolean
	return Config.Biomes[biomeId].order <= data.unlockedBiome
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Players standing in the zone right now (who can use it), for "who got it" news.
local function playersInZone(zone: Zone): { Player }
	local inside = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and flatDistance(root.Position, zone.center) < zone.radius then
			table.insert(inside, player)
		end
	end
	return inside
end

local function tellZone(zone: Zone, text: string, except: Player?)
	for _, player in playersInZone(zone) do
		if player ~= except then
			Net.notify(player, text, "info")
		end
	end
end

-- Charges the player's next egg with ×`luck`. False when it already has that much.
local function chargeLuck(player: Player, data: PlayerData, luck: number): boolean
	if data.luckCharge >= luck then
		return false
	end
	data.luckCharge = luck
	DataService.markDirty(player)
	return true
end

local function giveSpins(player: Player, data: PlayerData, spins: number)
	data.spins += spins
	DataService.markDirty(player)
end

-- A glowing prize: the first player who has the zone unlocked to touch it gets
-- `onTake`. `dress` adds its glow (and flight) once it exists. It vanishes after
-- `seconds` if nobody takes it; returns once it's gone.
local function prize(
	props: { [string]: any },
	zone: Zone,
	seconds: number,
	onTake: (Player, PlayerData) -> (),
	dress: ((BasePart) -> ())?
)
	local p = part(props)
	p.CanTouch = true
	p.Parent = zone.folder
	local taken = false
	p.Touched:Connect(function(hit: BasePart)
		if taken then
			return
		end
		local character = hit.Parent
		local player = if character and character:IsA("Model")
			then Players:GetPlayerFromCharacter(character)
			else nil
		local data = player and DataService.get(player)
		if player == nil or data == nil or not unlocked(data, zone.biome) then
			return
		end
		taken = true
		p:Destroy()
		onTake(player, data)
	end)
	if dress then
		task.spawn(dress, p)
	end
	local deadline = os.clock() + seconds
	while not taken and os.clock() < deadline do
		task.wait(0.25)
	end
	if not taken then
		p:Destroy()
	end
end

---------------------------------------------------------------------------
-- The events
---------------------------------------------------------------------------

-- Mossvale: the glowcap ring blooms; everyone standing in it collects Essence.
local function bloom(zone: Zone, landmark: Landmark)
	local tune = Events.bloom
	local glow = part({
		Name = "Bloom",
		Size = Vector3.new(landmark.radius * 1.4, 1, landmark.radius * 1.4),
		CFrame = CFrame.new(landmark.position + Vector3.new(0, 1.5, 0)),
		Transparency = 1,
		Parent = zone.folder,
	})
	light(glow, Color3.fromRGB(120, 255, 225), 3, landmark.radius * 2.2)
	emitter(glow, {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(130, 255, 225), Color3.fromRGB(200, 255, 160)),
		Rate = 70,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 2.5, 0),
		Size = NumberSequence.new(0.7, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	local earned: { [Player]: number } = {}
	for _ = 1, math.floor(tune.duration / tune.tick) do
		task.wait(tune.tick)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			local root = rootOf(player)
			if
				data
				and root
				and unlocked(data, zone.biome)
				and flatDistance(root.Position, landmark.position) <= landmark.radius
			then
				ZoneService.grantEssence(player, zone.biome, tune.essence)
				earned[player] = (earned[player] or 0) + tune.essence
			end
		end
	end
	glow:Destroy()
	for player, amount in earned do
		if player.Parent then
			Net.notify(player, `🍄 Glowcap Bloom: +{amount} {Zones.byBiome[zone.biome].essence}`, "good")
		end
	end
end

-- Coral Coast: the giant clam opens on a pearl. First to grab it gets spins, or a
-- Black Pearl's luck.
local function clam(zone: Zone, landmark: Landmark)
	local tune = Events.clam
	local black = rng:NextNumber() < tune.blackPearlChance
	local color = if black then Color3.fromRGB(45, 35, 60) else Color3.fromRGB(250, 248, 255)
	-- The pearl rises out of the shell and rolls out in front of it, where players can reach it
	local at = landmark.position + Vector3.new(0, landmark.size.Y * 0.45, 0)
	local reach = math.max(landmark.size.X, landmark.size.Z) / 2 + 1.5
	local front = (landmark.frame * CFrame.new(0, 2.2, -reach)).Position
	prize(
		{
			Name = "Pearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.4, 2.4),
			CFrame = CFrame.new(at),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.3,
			Color = color,
		},
		zone,
		tune.duration,
		function(player, data)
			if black and chargeLuck(player, data, tune.blackPearlLuck) then
				Net.notify(
					player,
					`🖤 A Black Pearl! Your next egg gets ×{tune.blackPearlLuck} luck.`,
					"rare"
				)
			else
				giveSpins(player, data, tune.spins)
				Net.notify(player, `🦪 You got the pearl: +{tune.spins} Luck Wheel spins!`, "good")
			end
			tellZone(zone, `{player.DisplayName} grabbed the pearl.`, player)
		end,
		function(pearl)
			TweenService:Create(
				pearl,
				TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = front }
			):Play()
			light(
				pearl,
				if black then Color3.fromRGB(170, 120, 255) else Color3.fromRGB(235, 245, 255),
				2,
				16
			)
			sparkles(
				pearl,
				if black then Color3.fromRGB(190, 150, 255) else Color3.fromRGB(240, 250, 255),
				10
			)
		end
	)
end

-- Magma Rift: the vent erupts shards across the zone. Each pays Essence; a rare
-- gold one pays the Forge Heat blessing.
local function eruption(zone: Zone, landmark: Landmark)
	local tune = Events.eruption
	local blast = part({
		Name = "Eruption",
		Size = Vector3.new(3, 1, 3),
		CFrame = CFrame.new(landmark.top),
		Transparency = 1,
		Parent = zone.folder,
	})
	local flash = light(blast, Color3.fromRGB(255, 130, 40), 6, 45)
	local fire = emitter(blast, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 70, 20)),
		LightEmission = 1,
		Rate = 0,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(20, 35),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -25, 0),
		Size = NumberSequence.new(1.6, 0.2),
		Transparency = NumberSequence.new(0, 0.6),
	})
	emitter(blast, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(60, 50, 50)),
		LightEmission = 0,
		Rate = 25,
		Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(20, 20),
		Size = NumberSequence.new(4, 12),
		Transparency = NumberSequence.new(0.2, 1),
	})
	fire:Emit(120)
	task.delay(4, function()
		blast:Destroy()
	end)
	TweenService:Create(flash, TweenInfo.new(3), { Brightness = 0 }):Play()

	local gold = rng:NextNumber() < tune.goldChance
	local waiting = tune.shards
	for i = 1, tune.shards do
		local isGold = gold and i == 1
		local angle = rng:NextNumber() * 2 * math.pi
		local distance = rng:NextNumber(landmark.radius + 2, landmark.radius + 16)
		local landing = landmark.position
			+ Vector3.new(math.cos(angle) * distance, 1, math.sin(angle) * distance)
		-- Flies out of the vent in an arc and lands
		local function launch(shard: BasePart)
			if isGold then
				light(shard, Color3.fromRGB(255, 215, 80), 2, 14)
				sparkles(shard, Color3.fromRGB(255, 230, 140), 12)
			else
				light(shard, Color3.fromRGB(255, 120, 40), 1, 8)
			end
			local peak = (landmark.top + landing) / 2 + Vector3.new(0, 10, 0)
			local up = TweenService:Create(
				shard,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = peak }
			)
			up:Play()
			up.Completed:Wait()
			if shard.Parent then
				TweenService:Create(
					shard,
					TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = landing }
				):Play()
			end
		end
		task.spawn(function()
			prize(
				{
					Name = if isGold then "GoldShard" else "EmberShard",
					Size = Vector3.new(1, 1.8, 1),
					CFrame = CFrame.new(landmark.top) * CFrame.Angles(rng:NextNumber(), rng:NextNumber(), 0),
					Material = Enum.Material.Neon,
					Color = if isGold then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(255, 110, 30),
				},
				zone,
				tune.duration,
				function(player)
					local essence = Zones.byBiome[zone.biome].essence
					if isGold then
						if ZoneService.giveBlessing(player, zone.biome) then
							Net.notify(player, "✨ The gold shard carries the Forge Heat blessing!", "rare")
						else
							ZoneService.grantEssence(player, zone.biome, tune.goldEssence)
							Net.notify(player, `✨ Gold shard: +{tune.goldEssence} {essence}`, "rare")
						end
					else
						ZoneService.grantEssence(player, zone.biome, tune.essence)
						Net.notify(player, `+{tune.essence} {essence}`, "good")
					end
				end,
				launch
			)
			waiting -= 1
		end)
		task.wait(0.05)
	end
	while waiting > 0 do
		task.wait(0.5)
	end
end

-- Frost Shelf: the frozen boulder cracks. Players break it together, one hold each
-- time; everyone who helped gets Essence, and maybe a luck shard.
local function boulder(zone: Zone, landmark: Landmark)
	local tune = Events.boulder
	local core = part({
		Name = "Cracking",
		Size = landmark.size * 0.6,
		CFrame = CFrame.new(landmark.position + Vector3.new(0, landmark.size.Y * 0.5, 0)),
		Transparency = 1,
		Parent = zone.folder,
	})
	local glow = light(core, Color3.fromRGB(170, 230, 255), 1, landmark.radius * 2.5)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Break the ice"
	prompt.ObjectText = "Frozen Boulder"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = landmark.radius + 6
	prompt.RequiresLineOfSight = false
	prompt.Parent = core

	local helpers: { [Player]: boolean } = {}
	local hits = 0
	local done = false
	prompt.Triggered:Connect(function(player)
		local data = DataService.get(player)
		if done or data == nil or not unlocked(data, zone.biome) then
			return
		end
		helpers[player] = true
		hits += 1
		glow.Brightness = 1 + hits * 0.6
		-- A glowing crack for every hit
		local angle = rng:NextNumber() * 2 * math.pi
		local reach = math.min(landmark.size.X, landmark.size.Z) * 0.48
		part({
			Name = "Crack",
			Size = Vector3.new(0.25, landmark.size.Y * rng:NextNumber(0.3, 0.6), 0.25),
			CFrame = CFrame.new(
				core.Position + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
			) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), angle, rng:NextNumber(-0.5, 0.5)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(190, 240, 255),
			Parent = core,
		})
		if hits >= tune.hits then
			done = true
		end
	end)

	local deadline = os.clock() + tune.duration
	while not done and os.clock() < deadline do
		task.wait(0.2)
	end
	done = true
	prompt:Destroy()
	if hits >= tune.hits then
		local burst = emitter(core, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(210, 245, 255)),
			LightEmission = 1,
			Rate = 0,
			Lifetime = NumberRange.new(0.8, 1.5),
			Speed = NumberRange.new(15, 30),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -30, 0),
			Size = NumberSequence.new(1, 0),
		})
		burst:Emit(120)
		glow.Brightness = 8
		for player in helpers do
			local data = DataService.get(player)
			if data == nil then
				continue
			end
			local amount = rng:NextInteger(tune.essence[1], tune.essence[2])
			ZoneService.grantEssence(player, zone.biome, amount)
			local lucky = rng:NextNumber() < tune.luckChance and chargeLuck(player, data, tune.luck)
			Net.notify(
				player,
				`🧊 The boulder shattered! +{amount} {Zones.byBiome[zone.biome].essence}`
					.. (if lucky then ` and a luck shard: ×{tune.luck} luck on your next egg!` else ""),
				if lucky then "rare" else "good"
			)
		end
		task.wait(1.5)
	else
		for player in helpers do
			Net.notify(player, "🧊 The boulder froze over again. Bring help next time!", "info")
		end
	end
	core:Destroy()
end

-- Storm Peaks: a huge strike on the crag charges the crystals around it.
local function strike(zone: Zone, landmark: Landmark)
	local tune = Events.strike
	task.spawn(SetPieces.bigStrike, landmark.top, zone.folder)
	ZoneService.chargeNodes(zone, landmark.position, tune.radius, tune.duration, tune.multiplier)
	task.wait(tune.duration)
end

-- Moonfall: a meteor falls into the crater. First to grab the moonstone gets its luck.
local function meteor(zone: Zone, landmark: Landmark)
	local tune = Events.meteor
	-- Chest height in the middle of the crater, clear of the crater mesh
	local target = landmark.position + Vector3.new(0, 2.8, 0)
	local start = target + Vector3.new(60, 170, 40)
	local rock = part({
		Name = "Meteor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(start),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(215, 175, 255),
		Parent = zone.folder,
	})
	light(rock, Color3.fromRGB(200, 160, 255), 5, 60)
	emitter(rock, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(230, 200, 255), Color3.fromRGB(130, 80, 220)),
		LightEmission = 1,
		Rate = 120,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0, 1),
		Size = NumberSequence.new(3, 0),
		Transparency = NumberSequence.new(0, 1),
	})
	local fall = TweenService:Create(rock, TweenInfo.new(3, Enum.EasingStyle.Linear), { Position = target })
	fall:Play()
	fall.Completed:Wait()
	rock:Destroy()

	local impact = part({
		Name = "Impact",
		Size = Vector3.new(6, 1, 6),
		CFrame = CFrame.new(target),
		Transparency = 1,
		Parent = zone.folder,
	})
	local flash = light(impact, Color3.fromRGB(210, 170, 255), 10, 50)
	local burst = emitter(impact, {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(220, 190, 255)),
		LightEmission = 1,
		Rate = 0,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(15, 30),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -20, 0),
		Size = NumberSequence.new(1, 0),
	})
	burst:Emit(100)
	TweenService:Create(flash, TweenInfo.new(1.5), { Brightness = 0 }):Play()
	task.delay(3, function()
		impact:Destroy()
	end)

	prize(
		{
			Name = "Moonstone",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(target),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(225, 200, 255),
		},
		zone,
		tune.duration,
		function(player, data)
			if chargeLuck(player, data, tune.luck) then
				Net.notify(
					player,
					`☄️ The moonstone is yours: ×{tune.luck} luck on your next egg!`,
					"rare"
				)
			else
				giveSpins(player, data, tune.spins)
				Net.notify(
					player,
					`☄️ Moonstone: your next egg is already lucky, so +{tune.spins} spins instead!`,
					"good"
				)
			end
			tellZone(zone, `{player.DisplayName} grabbed the moonstone.`, player)
		end,
		function(stone)
			light(stone, Color3.fromRGB(200, 160, 255), 3, 18)
			sparkles(stone, Color3.fromRGB(225, 200, 255), 15)
			TweenService:Create(
				stone,
				TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = target + Vector3.new(0, 0.6, 0) }
			):Play()
		end
	)
end

local RUNNERS: { [string]: (Zone, Landmark) -> () } = {
	bloom = bloom,
	clam = clam,
	eruption = eruption,
	boulder = boulder,
	strike = strike,
	meteor = meteor,
}

---------------------------------------------------------------------------
-- Schedule
---------------------------------------------------------------------------

-- Runs `zone`'s event now (after the warning unless `skipWarning`). Returns false
-- when the zone has no event, its set piece is missing or one is already running.
function ZoneEventService.run(zone: Zone, skipWarning: boolean?): boolean
	local setup = Zones.eventByBiome[zone.biome]
	local landmark = setup and zone.landmarks[setup.landmark]
	local runner = setup and RUNNERS[setup.kind]
	if setup == nil or landmark == nil or runner == nil or running[zone] then
		return false
	end
	running[zone] = true
	if not skipWarning then
		for player, data in DataService.loadedPlayers() do
			if unlocked(data, zone.biome) then
				Net.notify(player, WARNINGS[setup.kind], "rare")
			end
		end
		task.wait(Events.warning)
	end
	local ok, problem = pcall(function(): any
		runner(zone, landmark)
		return nil
	end)
	if not ok then
		warn(`[ZoneEventService] {zone.biome} event failed: {problem}`)
	end
	running[zone] = nil
	return true
end

function ZoneEventService.zone(biomeId: string): Zone?
	for _, zone in WorldService.zones do
		if zone.biome == biomeId then
			return zone
		end
	end
	return nil
end

function ZoneEventService.start()
	local zones = WorldService.zones
	for i, zone in zones do
		task.spawn(function()
			-- Staggered, so the zones take turns
			task.wait(Events.firstDelay + (i - 1) * Events.interval / #zones)
			while true do
				ZoneEventService.run(zone)
				task.wait(Events.interval + rng:NextNumber(-Events.jitter, Events.jitter))
			end
		end)
	end
end

return ZoneEventService

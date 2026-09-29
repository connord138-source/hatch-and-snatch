--!strict
-- The shared egg conveyor: eggs spawn at the reactor, ride the loop once and
-- can be bought by any player (first come, first served) via a ProximityPrompt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Net)
local Props = require(script.Parent.Parent.Props)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local HatchService = require(script.Parent.HatchService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)

type Egg = {
	part: BasePart,
	biome: string,
	price: number,
	angle: number,
	travelled: number,
	sold: boolean,
}

local conveyor = Config.Eggs.conveyor
-- Eggs start in the middle of the hatchery tunnel, ride one lap and are removed
-- back in the middle of it, so none ever vanishes in view
local TUNNEL_CENTER = math.rad(conveyor.tunnelCenterDegrees)
local TUNNEL_HALF = math.rad(conveyor.tunnelHalfDegrees)
local EGG_HEIGHT = 3.4 -- studs, for imported egg meshes
local rng = Random.new()
local eggs: { Egg } = {}
local folder: Folder

local EggService = {}

local function pickBiome(): string
	local options: { { id: string, weight: number } } = {}
	local total = 0
	for _, biome in Config.Biomes do
		local biomeId = biome.id
		local weight = Config.Eggs.conveyorWeights[biomeId] or 0
		local allowed = if biome.order == 0 then EventService.spawnsJunkEgg() else true
		if allowed and weight > 0 then
			table.insert(options, { id = biomeId, weight = weight })
			total += weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, option in options do
		roll -= option.weight
		if roll <= 0 then
			return option.id
		end
	end
	return "Mossvale"
end

local function tryBuy(egg: Egg, player: Player)
	if egg.sold then
		return
	end
	local data = DataService.get(player)
	if data == nil or PlotService.get(player) == nil then
		return
	end
	local biome = Config.Biomes[egg.biome]
	if not ProgressionService.canBuyBiome(data, egg.biome) then
		local need = Config.Progression.biomeRequirements[egg.biome]
		local text = if need and need.baseLevel > data.baseLevel
			then `Hatcher Level {need.level} and base level {need.baseLevel}`
			else `Hatcher Level {if need then need.level else 1}`
		Net.notify(player, `{biome.displayName} eggs unlock at {text}.`, "bad")
		return
	end
	if data.heldEgg then
		Net.notify(player, "You're already carrying an egg — put it in an incubator first.", "bad")
		return
	end
	if not HatchService.hasTierFor(data, egg.biome) then
		Net.notify(
			player,
			`{biome.displayName} eggs need a {HatchService.tierNameFor(egg.biome)} incubator. Upgrade one at your base (R).`,
			"bad"
		)
		return
	end
	if not HatchService.freeIncubatorFor(data, egg.biome) then
		Net.notify(player, "Your incubators are busy — wait for a hatch or buy another incubator.", "bad")
		return
	end
	if not CreatureService.hasRoom(data) then
		Net.notify(player, "Your pedestals and storage are full. Sell a creature first.", "bad")
		return
	end
	if not EconomyService.spend(player, egg.price) then
		Net.notify(player, `You need {Format.cash(egg.price)} for this egg.`, "bad")
		return
	end
	egg.sold = true
	egg.part:Destroy()
	HatchService.giveEgg(player, egg.biome)
	Net.notify(player, `Got a {biome.displayName} egg! Carry it home and place it in an incubator.`, "good")
end

local function spawnEgg()
	local biomeId = pickBiome()
	local biome = Config.Biomes[biomeId]
	local price = Config.Eggs.price(biomeId)

	local part = Instance.new("Part")
	part.Name = `{biomeId}Egg`
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.Anchored = true
	part.CanCollide = false
	part.Color = Config.Eggs.eggColors[biomeId]
	part.Material = if biomeId == "Moonfall" or biomeId == "Junk"
		then Enum.Material.Neon
		else Enum.Material.SmoothPlastic
	-- Imported egg mesh (Props.egg): the anchor part goes invisible and the mesh is welded to it
	local eggModel = Props.egg(biomeId, EGG_HEIGHT)
	if eggModel then
		part.Transparency = 1
		Props.weldCentered(eggModel, part)
		if biomeId == "Moonfall" or biomeId == "Junk" then
			local light = Instance.new("PointLight")
			light.Color = Config.Eggs.eggColors[biomeId]
			light.Range = 8
			light.Brightness = 2
			light.Parent = part
		end
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = part
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy"
	prompt.ObjectText = `{biome.displayName} Egg — {Format.cash(price)}`
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local egg: Egg = {
		part = part,
		biome = biomeId,
		price = price,
		angle = TUNNEL_CENTER,
		travelled = 0,
		sold = false,
	}
	prompt.Triggered:Connect(function(player)
		tryBuy(egg, player)
	end)

	part.Parent = folder
	table.insert(eggs, egg)
end

local function step(dt: number)
	local center = WorldService.conveyorCenter
	local angularSpeed = conveyor.speed / conveyor.radius
	for i = #eggs, 1, -1 do
		local egg = eggs[i]
		if egg.sold then
			table.remove(eggs, i)
			continue
		end
		egg.angle += angularSpeed * dt
		egg.travelled += angularSpeed * dt
		if egg.travelled >= 2 * math.pi then
			egg.part:Destroy()
			table.remove(eggs, i)
			continue
		end
		-- No buying while it's inside the tunnel
		local fromCenter = math.abs(((egg.angle - TUNNEL_CENTER + math.pi) % (2 * math.pi)) - math.pi)
		local prompt = egg.part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = fromCenter > TUNNEL_HALF
		end
		local bob = math.sin(egg.angle * 6) * 0.15
		local position = center
			+ Vector3.new(
				math.cos(egg.angle) * conveyor.radius,
				conveyor.height + bob,
				math.sin(egg.angle) * conveyor.radius
			)
		egg.part.CFrame = CFrame.new(position) * CFrame.Angles(0, -egg.angle, 0)
	end
end

function EggService.start()
	folder = Instance.new("Folder")
	folder.Name = "ConveyorEggs"
	folder.Parent = Workspace

	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		while true do
			spawnEgg()
			task.wait(conveyor.spawnSeconds)
		end
	end)
end

return EggService

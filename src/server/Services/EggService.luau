--!strict
-- The shared egg conveyor: eggs spawn at the reactor, ride the loop once and
-- can be bought by any player (first come, first served) via a ProximityPrompt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local HatchService = require(script.Parent.HatchService)
local PlotService = require(script.Parent.PlotService)
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
	if biome.order > data.unlockedBiome then
		Net.notify(player, `Rebirth to unlock {biome.displayName} eggs.`, "bad")
		return
	end
	if not HatchService.hasFreeSlot(player) then
		Net.notify(player, "Your incubators are full — wait for an egg to hatch.", "bad")
		return
	end
	if not EconomyService.spend(player, egg.price) then
		Net.notify(player, `You need {Format.cash(egg.price)} for this egg.`, "bad")
		return
	end
	egg.sold = true
	egg.part:Destroy()
	HatchService.incubate(player, egg.biome)
	Net.notify(player, `Bought a {biome.displayName} egg! It's incubating at your base.`, "good")
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
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part

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
		angle = 0,
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

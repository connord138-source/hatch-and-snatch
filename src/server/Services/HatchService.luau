--!strict
-- Incubators: an egg bought off the conveyor hatches after its rarity's hatch
-- time. The species is rolled at purchase (hidden); finish + mutation are rolled
-- at hatch so an active moon event / luck boost applies at the moment it cracks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Net = require(script.Parent.Parent.Net)
local Props = require(script.Parent.Parent.Props)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)

type PlayerData = DataService.PlayerData

local rng = Random.new()
local EMPTY_COLOR = Color3.fromRGB(200, 230, 255)
local GLOW_MIN_ORDER = 4 -- Epic and up glow in their rarity color as they near hatching

local HatchService = {}

local finishById: { [string]: Types.Finish } = {}
for _, finish in Config.Finishes do
	finishById[finish.id] = finish
end

local INCUBATOR_EGG_HEIGHT = 2.4

-- The egg sitting in an incubator: the biome's egg model when imported.
local function setEggVisual(part: BasePart, biomeId: string?)
	local existing = part:FindFirstChild("EggVisual")
	if existing then
		existing:Destroy()
	end
	if biomeId == nil then
		return
	end
	local model = Props.egg(biomeId, INCUBATOR_EGG_HEIGHT)
	if model then
		model.Name = "EggVisual"
		Props.weldCentered(model, part)
	end
end

local function refreshIncubators(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	for i, part in plot.incubators do
		local egg = data.incubators[i]
		local biomeId = if egg then egg.biome else nil
		local current = part:GetAttribute("EggBiome")
		if current ~= biomeId then
			part:SetAttribute("EggBiome", biomeId)
			setEggVisual(part, biomeId)
		end
		local hasVisual = part:FindFirstChild("EggVisual") ~= nil
		if part:GetAttribute("Dressed") and not hasVisual then
			-- Imported incubator but no egg model: a tinted egg-shaped glow inside the glass
			if part:IsA("Part") then
				part.Shape = Enum.PartType.Ball
			end
			part.Size = Vector3.new(2, 2, 2)
			part.Material = Enum.Material.Neon
			part.Color = if egg then Config.Eggs.eggColors[egg.biome] or EMPTY_COLOR else EMPTY_COLOR
			part.Transparency = if egg then 0.1 else 1
		elseif part:GetAttribute("Dressed") then
			part.Transparency = 1
		elseif egg then
			part.Color = Config.Eggs.eggColors[egg.biome] or EMPTY_COLOR
			part.Transparency = if hasVisual then 0.75 else 0.1
		else
			part.Color = EMPTY_COLOR
			part.Transparency = 0.4
		end
	end
end

function HatchService.hasFreeSlot(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and #data.incubators < Config.Economy.tunables.incubatorSlots
end

-- Puts a purchased egg into an incubator. Caller has already charged the player.
function HatchService.incubate(player: Player, biomeId: string): boolean
	local data = DataService.get(player)
	if data == nil or #data.incubators >= Config.Economy.tunables.incubatorSlots then
		return false
	end
	local species = Config.Eggs.rollSpecies(biomeId, rng, EventService.activeId() ~= nil)
	local rarity = Config.Rarities[Config.CreaturesById[species].rarity]
	local now = Timing.now()
	table.insert(data.incubators, {
		biome = biomeId,
		species = species,
		startedAt = now,
		hatchAt = now + Timing.scaled(rarity.hatchSeconds),
	})
	data.stats.eggsBought += 1
	refreshIncubators(player, data)
	DataService.markDirty(player)
	return true
end

local function hatch(player: Player, data: PlayerData, index: number)
	local egg = table.remove(data.incubators, index)
	if egg == nil then
		return
	end
	local finishId = Config.Economy.rollFinish(rng, EventService.activeId(), EventService.finishMultiplier())
	local mutation = Config.Economy.rollMutation(rng)
	local uid = CreatureService.add(player, {
		species = egg.species,
		stage = "Baby",
		stageStartedAt = Timing.now(),
		finish = finishId,
		mutation = mutation,
		homegrown = true,
	})
	data.stats.hatched += 1

	local creature = Config.CreaturesById[egg.species]
	local finish = finishById[finishId]
	local parts = {}
	if finishId ~= "Normal" then
		table.insert(parts, finish.displayName)
	end
	if mutation then
		table.insert(parts, mutation)
	end
	table.insert(parts, creature.displayName)
	local name = table.concat(parts, " ")
	local rare = finishId ~= "Normal" or Config.Rarities[creature.rarity].order >= 4
	Net.notify(player, `Hatched: {name} ({creature.rarity})!`, if rare then "rare" else "good")
	if uid and data.creatures[uid] and data.creatures[uid].slot == nil then
		Net.notify(player, "Your pedestals are full, so it went to storage (Creatures menu).", "bad")
	end
	local rarity = Config.Rarities[creature.rarity]
	if rarity.announce then
		Net.announce(`{player.DisplayName} hatched a {creature.rarity:upper()} {name}!`, rarity.color)
	elseif finish.announce ~= "none" then
		Net.announce(`{player.DisplayName} hatched a {name}!`, rarity.color)
	end
end

-- The species is rolled at purchase, so the incubator can tease it: Epic+ eggs
-- glow in their rarity color, brighter and wider the closer they are to hatching.
local function updateGlow(player: Player, data: PlayerData, now: number)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	for i, part in plot.incubators do
		local egg = data.incubators[i]
		local light = part:FindFirstChild("RarityGlow") :: PointLight?
		local rarity = egg and Config.Rarities[Config.CreaturesById[egg.species].rarity]
		if egg == nil or rarity == nil or rarity.order < GLOW_MIN_ORDER then
			if light then
				light:Destroy()
			end
			continue
		end
		if light == nil then
			local newLight = Instance.new("PointLight")
			newLight.Name = "RarityGlow"
			newLight.Shadows = false
			newLight.Parent = part
			light = newLight
		end
		local glow = light :: PointLight
		local span = math.max(egg.hatchAt - egg.startedAt, 1)
		local progress = math.clamp((now - egg.startedAt) / span, 0, 1)
		local tier = rarity.order - GLOW_MIN_ORDER + 1 -- 1 (Epic) .. 6 (Secret)
		local pulse = if progress > 0.9 then 0.75 + 0.25 * math.sin(os.clock() * 8) else 1
		glow.Color = rarity.color
		glow.Brightness = (0.3 + progress * progress * tier) * pulse
		glow.Range = 6 + progress * (4 + tier * 2)
	end
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		local hatchedAny = false
		for i = #data.incubators, 1, -1 do
			if now >= data.incubators[i].hatchAt then
				hatch(player, data, i)
				hatchedAny = true
			end
		end
		if hatchedAny then
			refreshIncubators(player, data)
			DataService.markDirty(player)
		end
		updateGlow(player, data, now)
	end
end

function HatchService.start()
	-- Runs after PlotService assigned the plot (connect order in init.server)
	DataService.loaded:connect(refreshIncubators)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return HatchService

--!strict
-- Owns creature records at runtime: placing them on pedestals, growth over
-- real time (including offline catch-up) and the in-world models.
--
-- Models: if ReplicatedStorage.CreatureModels.<SpeciesId> exists it is cloned
-- (Babies/Juveniles use <SpeciesId>_Baby / _Juvenile when imported: their own stage look);
-- otherwise a placeholder is built.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FinishLooks = require(ReplicatedStorage.Shared.FinishLooks)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local PlotService = require(script.Parent.PlotService)

type CreatureRecord = DataService.CreatureRecord
type PlayerData = DataService.PlayerData

local STAGE_ORDER: { Types.StageId } = { "Baby", "Juvenile", "Adult" }

local models: { [Player]: { [string]: Model } } = {}
-- Creatures currently being carried by a thief (not shown on their pedestal)
local carried: { [Player]: { [string]: boolean? } } = {}
-- The one creature each player is walking (following them around), if any
local walking: { [Player]: string } = {}

local tunables = Config.Economy.tunables
local nurserySlots = tunables.nurserySlotsBase
local STEAL_HOLD: { [string]: number } = { Baby = 1.2, Juvenile = 1.6, Adult = 2.0 }

local CreatureService = {
	-- (thief: Player, owner: Player, uid: string) — a Steal prompt was completed
	stealRequested = Signal.new(),
}

function CreatureService.isNursery(slot: number?): boolean
	return slot ~= nil and slot <= nurserySlots
end

local function stageIndex(stage: string): number
	return table.find(STAGE_ORDER, stage :: Types.StageId) or 1
end

-- The numbers Config.Economy needs to price a creature (earnings, sell value).
function CreatureService.stats(record: CreatureRecord)
	local creature = Config.CreaturesById[record.species]
	return {
		biome = creature.biome :: string,
		rarity = creature.rarity,
		stage = record.stage :: Types.StageId,
		finish = record.finish,
		mutation = record.mutation,
		homegrown = record.homegrown,
	}
end

-- Collection index: every species, finish and Adult the player has ever owned.
-- `player` is nil when backfilling at load (no XP for that).
local function recordInIndex(player: Player?, data: PlayerData, record: CreatureRecord)
	if not data.index[record.species] and player then
		ProgressionService.addXp(player, Config.Progression.xp.newSpecies)
		ProgressionService.bump(player, "discovered")
	end
	data.index[record.species] = true
	local finishes = data.indexFinishes[record.species] or {}
	finishes[record.finish] = true
	data.indexFinishes[record.species] = finishes
	if record.stage == "Adult" then
		data.indexAdults[record.species] = true
	end
end

-- Pedestals the player's base level provides.
local function pedestalCount(data: PlayerData): number
	return Config.Economy.baseLevel(data.baseLevel).pedestals
end
CreatureService.pedestalCount = pedestalCount

-- Whether the player can take one more creature: owned creatures plus eggs still
-- incubating or carried must fit on pedestals + storage. Buying and stealing check this.
function CreatureService.hasRoom(data: PlayerData): boolean
	local owned = #data.incubators + (if data.heldEgg then 1 else 0)
	for _ in data.creatures do
		owned += 1
	end
	return owned < pedestalCount(data) + tunables.storageSlots
end

-- Absolute unix time the creature reaches its next stage (nil when Adult).
function CreatureService.nextStageAt(record: CreatureRecord): number?
	local creature = Config.CreaturesById[record.species]
	local seconds = Config.Economy.secondsToNextStage(creature.rarity, record.stage :: Types.StageId)
	if seconds == nil then
		return nil
	end
	return record.stageStartedAt + Timing.scaled(seconds)
end

-- Advances growth up to `now`. Returns true if the stage changed.
local function advance(record: CreatureRecord, now: number): boolean
	local changed = false
	while true do
		local nextAt = CreatureService.nextStageAt(record)
		if nextAt == nil or now < nextAt then
			break
		end
		record.stage = STAGE_ORDER[stageIndex(record.stage) + 1]
		record.stageStartedAt = nextAt
		changed = true
	end
	return changed
end

local function buildPlaceholder(record: CreatureRecord): Model
	local creature = Config.CreaturesById[record.species]
	local rarityColor = Config.Rarities[creature.rarity].color
	local model = Instance.new("Model")

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 2.4, 4.2)
	body.Color = rarityColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2)
	head.Color = rarityColor:Lerp(Color3.new(1, 1, 1), 0.25)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = body.CFrame * CFrame.new(0, 1.2, -2.4)
	head.Parent = model

	model.PrimaryPart = body
	return model
end

-- Particle looks shared by finishes (on any creature) and rarity auras (by species)
type ParticleSpec = {
	texture: string,
	colors: { Color3 },
	rate: number,
	size: number,
	speed: number,
	lifetime: number,
	rise: number,
	light: Color3?,
}
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function addParticles(part: BasePart, spec: ParticleSpec)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LookFx"
	emitter.Texture = spec.texture
	local keypoints = {}
	for i, color in spec.colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#spec.colors - 1, 1), color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, spec.colors[1]))
	end
	emitter.Color = ColorSequence.new(keypoints)
	emitter.LightEmission = 1
	emitter.Rate = spec.rate
	emitter.Lifetime = NumberRange.new(spec.lifetime * 0.6, spec.lifetime)
	emitter.Speed = NumberRange.new(spec.speed * 0.4, spec.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, spec.rise, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.size),
		NumberSequenceKeypoint.new(0.5, spec.size * 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = part
	if spec.light then
		local light = Instance.new("PointLight")
		light.Name = "LookLight"
		light.Color = spec.light
		light.Brightness = 0.45 -- subtle: brighter lights washed out neighbouring creatures
		light.Range = 6
		light.Parent = part
	end
end

local FINISH_FX: { [string]: ParticleSpec } = {
	Gold = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(255, 230, 120) },
		rate = 3,
		size = 0.35,
		speed = 0.5,
		lifetime = 1.2,
		rise = 0,
	},
	Chrome = {
		texture = SPARKLE,
		colors = { Color3.new(1, 1, 1) },
		rate = 2,
		size = 0.3,
		speed = 0.3,
		lifetime = 1,
		rise = 0,
	},
	Diamond = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(200, 245, 255), Color3.new(1, 1, 1) },
		rate = 8,
		size = 0.4,
		speed = 0.4,
		lifetime = 1.2,
		rise = 0,
		light = Color3.fromRGB(180, 230, 255),
	},
	Molten = {
		texture = FIRE,
		colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 70, 10) },
		rate = 14,
		size = 0.45,
		speed = 2,
		lifetime = 1.4,
		rise = 4,
		light = Color3.fromRGB(255, 120, 30),
	},
	Galaxy = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(190, 120, 255), Color3.new(1, 1, 1) },
		rate = 16,
		size = 0.35,
		speed = 0.4,
		lifetime = 3,
		rise = 0.3,
		light = Color3.fromRGB(120, 70, 255),
	},
	Prismatic = {
		texture = SPARKLE,
		colors = {
			Color3.fromRGB(255, 80, 80),
			Color3.fromRGB(255, 230, 80),
			Color3.fromRGB(80, 255, 140),
			Color3.fromRGB(80, 160, 255),
			Color3.fromRGB(220, 90, 255),
		},
		rate = 20,
		size = 0.45,
		speed = 1.5,
		lifetime = 2,
		rise = 1,
		light = Color3.new(1, 1, 1),
	},
	BloodMoon = {
		texture = SMOKE,
		colors = { Color3.fromRGB(200, 0, 20), Color3.fromRGB(40, 0, 0) },
		rate = 8,
		size = 1.2,
		speed = 0.6,
		lifetime = 2.5,
		rise = 1.5,
		light = Color3.fromRGB(255, 20, 30),
	},
}

-- Rarity auras by species rarity: rarer species glow more, readable across the map
local RARITY_FX: { [string]: ParticleSpec } = {
	Legendary = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(255, 190, 60) },
		rate = 4,
		size = 0.4,
		speed = 0.8,
		lifetime = 1.6,
		rise = 1.5,
	},
	Mythic = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(255, 70, 110), Color3.fromRGB(255, 180, 200) },
		rate = 9,
		size = 0.5,
		speed = 1,
		lifetime = 2,
		rise = 2,
		light = Color3.fromRGB(255, 70, 110),
	},
	Celestial = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(150, 235, 255) },
		rate = 12,
		size = 0.55,
		speed = 0.6,
		lifetime = 2.4,
		rise = 3,
		light = Color3.fromRGB(200, 240, 255),
	},
	Cosmic = {
		texture = SPARKLE,
		colors = { Color3.fromRGB(140, 70, 255), Color3.fromRGB(90, 200, 255), Color3.new(1, 1, 1) },
		rate = 18,
		size = 0.45,
		speed = 0.5,
		lifetime = 3.5,
		rise = 0.4,
		light = Color3.fromRGB(140, 70, 255),
	},
	Secret = {
		texture = SPARKLE,
		colors = {
			Color3.fromRGB(255, 80, 80),
			Color3.fromRGB(255, 230, 80),
			Color3.fromRGB(80, 255, 140),
			Color3.fromRGB(80, 160, 255),
			Color3.fromRGB(220, 90, 255),
		},
		rate = 22,
		size = 0.55,
		speed = 1.2,
		lifetime = 2.5,
		rise = 1,
		light = Color3.new(1, 1, 1),
	},
}

local function addRarityAura(model: Model, rarity: string)
	local fx = RARITY_FX[rarity]
	if fx and model.PrimaryPart then
		addParticles(model.PrimaryPart, fx)
	end
end

local function applyFinish(model: Model, finish: string)
	if not FinishLooks.apply(model, finish) then
		return -- Normal
	end
	local fx = FINISH_FX[finish]
	if fx and model.PrimaryPart then
		addParticles(model.PrimaryPart, fx)
	end
	if finish == "Prismatic" then
		CollectionService:AddTag(model, "Prismatic")
	end
	if finish == "Galaxy" and model.PrimaryPart then
		-- A tiny glowing planet; the client animator swings it around the creature.
		-- It starts inside the body so it doesn't change the model's bounding box.
		local extents = model:GetExtentsSize()
		local diameter = math.max(extents.X, extents.Y, extents.Z) * 0.09
		local planet = Instance.new("Part")
		planet.Name = "GalaxyPlanet"
		planet.Shape = Enum.PartType.Ball
		planet.Size = Vector3.new(diameter, diameter, diameter)
		planet.Material = Enum.Material.Neon
		planet.Color = Color3.fromRGB(120, 220, 255)
		planet.Anchored = true
		planet.CanCollide = false
		planet.CanQuery = false
		planet.CastShadow = false
		planet:SetAttribute("KeepMaterial", true)
		planet.CFrame = model.PrimaryPart.CFrame
		planet.Parent = model
	end
end

-- Element effects that grow in with the creature: none on a Baby, a light trail
-- on a Juvenile, the full effect plus a glow on an Adult.
type ElementFx = { texture: string, color: Color3, speed: number, drift: Vector3, size: number, light: boolean }
local ELEMENT_FX: { [string]: ElementFx } = {
	Mossvale = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		color = Color3.fromRGB(140, 210, 90),
		speed = 0.6,
		drift = Vector3.new(0, -0.6, 0),
		size = 0.35,
		light = false,
	},
	CoralCoast = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		color = Color3.fromRGB(150, 230, 255),
		speed = 1.2,
		drift = Vector3.new(0, 1.5, 0),
		size = 0.3,
		light = false,
	},
	MagmaRift = {
		texture = "rbxasset://textures/particles/fire_main.dds",
		color = Color3.fromRGB(255, 130, 40),
		speed = 2,
		drift = Vector3.new(0, 2.5, 0),
		size = 0.35,
		light = true,
	},
	FrostShelf = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		color = Color3.fromRGB(220, 240, 255),
		speed = 0.5,
		drift = Vector3.new(0, -0.4, 0),
		size = 0.3,
		light = false,
	},
	StormPeaks = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		color = Color3.fromRGB(255, 240, 110),
		speed = 5,
		drift = Vector3.zero,
		size = 0.25,
		light = true,
	},
	Moonfall = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		color = Color3.fromRGB(190, 130, 255),
		speed = 0.4,
		drift = Vector3.new(0, 0.5, 0),
		size = 0.4,
		light = true,
	},
	Junk = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		color = Color3.fromRGB(200, 200, 205),
		speed = 1,
		drift = Vector3.new(0, 1.2, 0),
		size = 0.6,
		light = false,
	},
}
local STAGE_FX_RATE: { [string]: number } = { Baby = 0, Juvenile = 2, Adult = 7 }

local function addStageEffects(model: Model, creature: Types.Creature, stage: string)
	local fx = ELEMENT_FX[creature.biome]
	local rate = STAGE_FX_RATE[stage] or 0
	local primary = model.PrimaryPart
	if fx == nil or rate <= 0 or primary == nil then
		return
	end
	local _, size = model:GetBoundingBox()
	local attachment = Instance.new("Attachment")
	attachment.Name = "ElementFx"
	attachment.WorldPosition = model:GetBoundingBox().Position
	attachment.Parent = primary
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = fx.texture
	emitter.Color = ColorSequence.new(fx.color)
	emitter.LightEmission = if fx.light then 0.8 else 0.2
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(fx.speed * 0.5, fx.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = fx.drift
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, fx.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Box-shaped emitter on the body part, so particles come off the creature itself
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Name = "ElementFx"
	emitter.Parent = primary
	if stage == "Adult" and fx.light then
		local glow = Instance.new("PointLight")
		glow.Color = fx.color
		glow.Brightness = 0.35
		glow.Range = math.max(size.X, size.Z) * 0.6 + 2
		glow.Parent = attachment
	end
end

-- Longest side (studs) of an imported adult model; babies/juveniles scale down from this.
local TEMPLATE_ADULT_SIZE = 7
local STAGE_MODEL_BOOST = 1.15

local function buildModel(owner: Player, uid: string, record: CreatureRecord, at: CFrame): Model
	local templates = ReplicatedStorage:FindFirstChild("CreatureModels")
	local template = templates and templates:FindFirstChild(record.species)
	-- Babies and Juveniles use their own stage model (<SpeciesId>_Baby / _Juvenile)
	-- when imported; `if` (not `and`) so a missing one is nil, not false
	local stageTemplate = if templates and record.stage ~= "Adult"
		then templates:FindFirstChild(`{record.species}_{record.stage}`)
		else nil
	local isStageModel = stageTemplate ~= nil
		and stageTemplate:IsA("Model")
		and stageTemplate.PrimaryPart ~= nil
	if isStageModel then
		template = stageTemplate
	end
	local model: Model
	local fromTemplate = template ~= nil and template:IsA("Model") and template.PrimaryPart ~= nil
	if fromTemplate then
		model = (template :: Model):Clone()
	else
		model = buildPlaceholder(record)
	end
	model.Name = `{record.species}_{uid}`

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	local stage = Config.Stages[record.stage :: Types.StageId]
	if fromTemplate then
		-- Imported meshes come in at arbitrary sizes: normalize the longest side, then apply the stage
		local size = model:GetExtentsSize()
		local longest = math.max(size.X, size.Y, size.Z, 0.01)
		-- Stage models already have young proportions; they read small enough a bit larger
		local stageScale = if isStageModel then stage.scale * STAGE_MODEL_BOOST else stage.scale
		model:ScaleTo(model:GetScale() * (TEMPLATE_ADULT_SIZE / longest) * stageScale)
	else
		model:ScaleTo(stage.scale)
	end
	applyFinish(model, record.finish)
	addStageEffects(model, Config.CreaturesById[record.species], record.stage)
	addRarityAura(model, Config.CreaturesById[record.species].rarity)

	-- Stand the model's bounding box on the pedestal, whatever its pivot is
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivotToBox = model:GetPivot():ToObjectSpace(boxCFrame)
	local targetBox = at * CFrame.new(0, boxSize.Y / 2, 0)
	model:PivotTo(targetBox * pivotToBox:Inverse())
	local extents = boxSize

	local creature = Config.CreaturesById[record.species]
	local tag = Instance.new("BillboardGui")
	-- Sized in studs (shrinks with distance) and only shown up close, so a full
	-- base doesn't turn into a wall of overlapping names
	tag.Size = UDim2.fromScale(7, 1.4)
	tag.StudsOffsetWorldSpace = Vector3.new(0, extents.Y / 2 + 1.2, 0)
	tag.MaxDistance = 32
	tag.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Config.Rarities[creature.rarity].color
	label.TextStrokeTransparency = 0.3
	local finishText = if record.finish ~= "Normal" then `{record.finish} ` else ""
	local origin = if record.stolenFrom
		then ` · stolen from {record.stolenFrom}`
		elseif record.homegrown then " · Homegrown"
		else ""
	label.Text = `{finishText}{creature.displayName}\n{record.stage}{origin}`
	label.Parent = tag

	model:SetAttribute("Uid", uid)
	model:SetAttribute("Species", record.species)
	model:SetAttribute("Stage", record.stage)
	model:SetAttribute("BodyPlan", creature.bodyPlan)
	model:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(model, "Creature")
	return model
end

local function addPrompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	hold: number,
	visibleTo: string
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("VisibleTo", visibleTo) -- client PromptFilter hides it for the wrong players
	prompt.Parent = parent
	return prompt
end

local function despawn(player: Player, uid: string)
	local playerModels = models[player]
	local model = playerModels and playerModels[uid]
	if model then
		model:Destroy()
		playerModels[uid] = nil
	end
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A walked creature: spawned beside its owner; the client animator makes it follow.
local function spawnWalking(player: Player, uid: string, record: CreatureRecord)
	local plot = PlotService.get(player)
	local root = characterRoot(player)
	if plot == nil or root == nil then
		return -- followOwner spawns it once the character exists
	end
	local at = CFrame.new((root.CFrame * CFrame.new(4, -3, 3)).Position)
	local model = buildModel(player, uid, record, at)
	model:SetAttribute("Walking", true)
	model:SetAttribute("FollowUserId", player.UserId)
	local primary = model.PrimaryPart :: BasePart
	local name = Config.CreaturesById[record.species].displayName
	local home = addPrompt(primary, "SendHome", "Send Home", name, 0, "owner")
	home.KeyboardKeyCode = Enum.KeyCode.R
	home.Triggered:Connect(function(who)
		if who == player then
			CreatureService.stopWalking(player)
		end
	end)
	model.Parent = plot.model
	models[player] = models[player] or {}
	models[player][uid] = model
end

local function spawn(player: Player, uid: string, record: CreatureRecord)
	despawn(player, uid)
	local plot = PlotService.get(player)
	if carried[player] and carried[player][uid] then
		return -- a thief is holding it; StealService respawns it if it comes home
	end
	if walking[player] == uid then
		spawnWalking(player, uid, record)
		return
	end
	local slot = record.slot
	if plot == nil or slot == nil or not plot.pedestals[slot] then
		return
	end
	local model = buildModel(player, uid, record, plot.pedestals[slot])
	local primary = model.PrimaryPart :: BasePart
	local name = Config.CreaturesById[record.species].displayName
	local inNursery = CreatureService.isNursery(slot)

	local steal = addPrompt(primary, "Steal", "Steal", name, STEAL_HOLD[record.stage] or 1.5, "others")
	steal:SetAttribute("Protected", inNursery)
	steal.Triggered:Connect(function(thief)
		CreatureService.stealRequested:fire(thief, player, uid)
	end)

	local nurseryPrompt = addPrompt(
		primary,
		"Nursery",
		if inNursery then "Move out of Nursery" else "Move to Nursery",
		name,
		0,
		"owner"
	)
	nurseryPrompt.KeyboardKeyCode = Enum.KeyCode.F
	nurseryPrompt.UIOffset = Vector2.new(0, 60)
	nurseryPrompt.Triggered:Connect(function(who)
		if who == player then
			CreatureService.toggleNursery(player, uid)
		end
	end)

	local walkPrompt = addPrompt(primary, "Walk", "Take for a Walk", name, 0, "owner")
	walkPrompt.KeyboardKeyCode = Enum.KeyCode.R
	walkPrompt.UIOffset = Vector2.new(0, 120)
	walkPrompt.Triggered:Connect(function(who)
		if who == player then
			CreatureService.walk(player, uid)
		end
	end)

	if inNursery then
		model:SetAttribute("Nursery", true)
	end
	model.Parent = plot.model
	models[player] = models[player] or {}
	models[player][uid] = model
end

-- Public wrappers used by StealService
function CreatureService.despawn(player: Player, uid: string)
	despawn(player, uid)
end

function CreatureService.respawn(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if record then
		spawn(player, uid, record)
	end
end

function CreatureService.setCarried(owner: Player, uid: string, isCarried: boolean)
	if isCarried then
		carried[owner] = carried[owner] or {}
		carried[owner][uid] = true
		despawn(owner, uid)
	elseif carried[owner] then
		carried[owner][uid] = nil
	end
end

function CreatureService.isCarried(owner: Player, uid: string): boolean
	return carried[owner] ~= nil and carried[owner][uid] == true
end

-- A copy of the creature's model to hold above a thief's head (not tagged for the animator).
function CreatureService.buildCarryModel(owner: Player, uid: string, record: CreatureRecord): Model
	local model = buildModel(owner, uid, record, CFrame.identity)
	CollectionService:RemoveTag(model, "Creature")
	CollectionService:RemoveTag(model, "Prismatic")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
		end
	end
	model:SetAttribute("Carried", true)
	return model
end

-- Keeps a walked creature near its owner on the server (the client animates the
-- actual following); respawns it if the owner respawned.
local function followOwner(player: Player, uid: string)
	local playerModels = models[player]
	local model: Model? = if playerModels then playerModels[uid] else nil
	local root = characterRoot(player)
	if root == nil then
		return
	end
	if model == nil or model.Parent == nil then
		CreatureService.respawn(player, uid)
		return
	end
	local offset = model:GetPivot().Position - root.Position
	if offset.Magnitude > 14 then
		model:PivotTo(CFrame.new((root.CFrame * CFrame.new(4, -3, 3)).Position))
	end
end

-- Takes a creature out for a walk: it follows its owner, can't be stolen and grows
-- faster. One at a time; walking another sends the first one home.
function CreatureService.walk(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil or CreatureService.isCarried(player, uid) then
		return
	end
	local previous = walking[player]
	walking[player] = uid
	if previous and previous ~= uid then
		CreatureService.respawn(player, previous)
	end
	spawn(player, uid, record)
	Net.notify(
		player,
		`{Config.CreaturesById[record.species].displayName} is following you! It grows {tunables.walkGrowthMultiplier}× faster on walks.`,
		"good"
	)
end

function CreatureService.stopWalking(player: Player)
	local uid = walking[player]
	if uid then
		walking[player] = nil
		CreatureService.respawn(player, uid)
	end
end

function CreatureService.walkingUid(player: Player): string?
	return walking[player]
end

local function freeSlot(data: PlayerData): number?
	local used: { [number]: boolean } = {}
	for _, record in data.creatures do
		if record.slot then
			used[record.slot] = true
		end
	end
	-- Regular pedestals first; the nursery is filled only on request (or as a last resort)
	for slot = nurserySlots + 1, pedestalCount(data) do
		if not used[slot] then
			return slot
		end
	end
	for slot = 1, nurserySlots do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Moves a creature off its pedestal into storage (it stops earning).
function CreatureService.store(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil or record.slot == nil or CreatureService.isCarried(player, uid) then
		return
	end
	local stored = 0
	for _, other in data.creatures do
		if other.slot == nil then
			stored += 1
		end
	end
	if stored >= tunables.storageSlots then
		Net.notify(player, "Your storage is full. Sell a creature first.", "bad")
		return
	end
	record.slot = nil
	despawn(player, uid)
	DataService.markDirty(player)
end

-- Puts a stored creature on the first free pedestal.
function CreatureService.place(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil or record.slot ~= nil then
		return
	end
	local slot = freeSlot(data)
	if slot == nil then
		Net.notify(player, "Every pedestal is taken. Store or sell a creature first.", "bad")
		return
	end
	record.slot = slot
	spawn(player, uid, record)
	DataService.markDirty(player)
end

-- Swaps a creature into the nursery (or back out to a regular pedestal).
function CreatureService.toggleNursery(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil or record.slot == nil or CreatureService.isCarried(player, uid) then
		return
	end
	local target: number? = nil
	if CreatureService.isNursery(record.slot) then
		for slot = nurserySlots + 1, pedestalCount(data) do
			local taken = false
			for _, other in data.creatures do
				if other.slot == slot then
					taken = true
				end
			end
			if not taken then
				target = slot
				break
			end
		end
		if target == nil then
			Net.notify(player, "No free pedestal to move it to.", "bad")
			return
		end
	else
		target = 1
	end
	-- Swap with whatever currently occupies the target slot
	for otherUid, other in data.creatures do
		if otherUid ~= uid and other.slot == target then
			other.slot = record.slot
			spawn(player, otherUid, other)
		end
	end
	record.slot = target
	spawn(player, uid, record)
	DataService.markDirty(player)
end

-- Removes a creature from a player's collection (e.g. it was stolen). Returns the record.
function CreatureService.remove(player: Player, uid: string): CreatureRecord?
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil then
		return nil
	end
	data.creatures[uid] = nil
	if walking[player] == uid then
		walking[player] = nil
	end
	if carried[player] then
		carried[player][uid] = nil
	end
	despawn(player, uid)
	DataService.markDirty(player)
	return record
end

-- Adds a freshly hatched (or later: stolen) creature. Returns its uid.
function CreatureService.add(player: Player, record: CreatureRecord): string?
	local data = DataService.get(player)
	if data == nil then
		return nil
	end
	local uid = DataService.newUid(data)
	record.slot = freeSlot(data)
	data.creatures[uid] = record
	recordInIndex(player, data, record)
	spawn(player, uid, record)
	DataService.markDirty(player)
	return uid
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		for uid, record in data.creatures do
			if walking[player] == uid then
				-- Walked creatures grow faster
				record.stageStartedAt -= tunables.walkGrowthMultiplier - 1
				ProgressionService.bump(player, "walkSeconds")
				followOwner(player, uid)
			end
			if advance(record, now) then
				recordInIndex(player, data, record)
				ProgressionService.addXp(
					player,
					if record.stage == "Adult"
						then Config.Progression.xp.growAdult
						else Config.Progression.xp.growJuvenile
				)
				if record.stage == "Adult" then
					ProgressionService.bump(player, "adults")
				end
				spawn(player, uid, record)
				local grown = models[player] and models[player][uid]
				if grown then
					grown:SetAttribute("GrewAt", Workspace:GetServerTimeNow()) -- client plays the grow-up burst
				end
				local name = Config.CreaturesById[record.species].displayName
				Net.notify(player, `Your {name} grew into a {record.stage}!`, "good")
				DataService.markDirty(player)
			end
		end
	end
end

function CreatureService.start()
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		local now = Timing.now()
		for uid, record in data.creatures do
			advance(record, now) -- offline growth catch-up
			recordInIndex(nil, data, record) -- also backfills saves from before the index
			spawn(player, uid, record)
		end
	end)
	DataService.releasing:connect(function(player: Player)
		local playerModels = models[player]
		if playerModels then
			for _, model in playerModels do
				model:Destroy()
			end
			models[player] = nil
		end
		carried[player] = nil
		walking[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return CreatureService

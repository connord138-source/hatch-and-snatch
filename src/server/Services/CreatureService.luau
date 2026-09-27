--!strict
-- Owns creature records at runtime: placing them on pedestals, growth over
-- real time (including offline catch-up) and the in-world models.
--
-- Models: if ReplicatedStorage.CreatureModels.<SpeciesId> exists it is cloned
-- (drop the imported Emberlynx there); otherwise a placeholder is built.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Net = require(script.Parent.Parent.Net)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type CreatureRecord = DataService.CreatureRecord
type PlayerData = DataService.PlayerData

local STAGE_ORDER: { Types.StageId } = { "Baby", "Juvenile", "Adult" }

local FINISH_LOOKS: { [string]: { color: Color3?, material: Enum.Material?, transparency: number?, reflectance: number? } } =
	{
		Gold = { color = Color3.fromRGB(255, 196, 45), material = Enum.Material.Foil, reflectance = 0.25 },
		Chrome = {
			color = Color3.fromRGB(215, 220, 228),
			material = Enum.Material.SmoothPlastic,
			reflectance = 0.6,
		},
		Diamond = {
			color = Color3.fromRGB(190, 240, 255),
			material = Enum.Material.Glass,
			transparency = 0.3,
		},
		Molten = { color = Color3.fromRGB(255, 110, 20), material = Enum.Material.Neon },
		Galaxy = { color = Color3.fromRGB(80, 40, 160), material = Enum.Material.Neon },
		Prismatic = { material = Enum.Material.Neon }, -- client cycles the color
		BloodMoon = { color = Color3.fromRGB(120, 0, 10), material = Enum.Material.Neon },
	}

local models: { [Player]: { [string]: Model } } = {}

local CreatureService = {}

local function stageIndex(stage: string): number
	return table.find(STAGE_ORDER, stage :: Types.StageId) or 1
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

local function applyFinish(model: Model, finish: string)
	local look = FINISH_LOOKS[finish]
	if look == nil then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:GetAttribute("KeepMaterial") then
			if look.color then
				descendant.Color = look.color
			end
			if look.material then
				descendant.Material = look.material
			end
			if look.transparency then
				descendant.Transparency = look.transparency
			end
			if look.reflectance then
				descendant.Reflectance = look.reflectance
			end
		end
	end
	if finish == "Galaxy" or finish == "Prismatic" or finish == "BloodMoon" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = look.color or Color3.new(1, 1, 1)
		sparkles.Parent = model.PrimaryPart
	end
	if finish == "Prismatic" then
		CollectionService:AddTag(model, "Prismatic")
	end
end

local function buildModel(owner: Player, uid: string, record: CreatureRecord, at: CFrame): Model
	local templates = ReplicatedStorage:FindFirstChild("CreatureModels")
	local template = templates and templates:FindFirstChild(record.species)
	local model: Model
	if template and template:IsA("Model") and template.PrimaryPart then
		model = template:Clone()
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
	model:ScaleTo(stage.scale)
	applyFinish(model, record.finish)

	local extents = model:GetExtentsSize()
	model:PivotTo(at * CFrame.new(0, extents.Y / 2, 0))

	local creature = Config.CreaturesById[record.species]
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 44)
	tag.StudsOffsetWorldSpace = Vector3.new(0, extents.Y / 2 + 1.5, 0)
	tag.MaxDistance = 80
	tag.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Config.Rarities[creature.rarity].color
	label.TextStrokeTransparency = 0.3
	local finishText = if record.finish ~= "Normal" then `{record.finish} ` else ""
	label.Text = `{finishText}{creature.displayName}\n{record.stage}`
	label.Parent = tag

	model:SetAttribute("Uid", uid)
	model:SetAttribute("Species", record.species)
	model:SetAttribute("Stage", record.stage)
	model:SetAttribute("BodyPlan", creature.bodyPlan)
	model:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(model, "Creature")
	return model
end

local function despawn(player: Player, uid: string)
	local playerModels = models[player]
	local model = playerModels and playerModels[uid]
	if model then
		model:Destroy()
		playerModels[uid] = nil
	end
end

local function spawn(player: Player, uid: string, record: CreatureRecord)
	despawn(player, uid)
	local plot = PlotService.get(player)
	local slot = record.slot
	if plot == nil or slot == nil or not plot.pedestals[slot] then
		return
	end
	local model = buildModel(player, uid, record, plot.pedestals[slot])
	model.Parent = plot.model
	models[player] = models[player] or {}
	models[player][uid] = model
end

local function freeSlot(data: PlayerData): number?
	local used: { [number]: boolean } = {}
	for _, record in data.creatures do
		if record.slot then
			used[record.slot] = true
		end
	end
	for slot = 1, Config.Economy.tunables.pedestalsBase do
		if not used[slot] then
			return slot
		end
	end
	return nil
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
	data.index[record.species] = true
	spawn(player, uid, record)
	DataService.markDirty(player)
	return uid
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		for uid, record in data.creatures do
			if advance(record, now) then
				spawn(player, uid, record)
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
			if record.slot == nil then
				record.slot = freeSlot(data)
			end
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
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return CreatureService

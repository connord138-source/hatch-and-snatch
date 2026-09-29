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
local Signal = require(ReplicatedStorage.Shared.Signal)
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
-- Creatures currently being carried by a thief (not shown on their pedestal)
local carried: { [Player]: { [string]: boolean? } } = {}

local nurserySlots = Config.Economy.tunables.nurserySlotsBase
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
	tag.Size = UDim2.fromOffset(220, 44)
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

local function spawn(player: Player, uid: string, record: CreatureRecord)
	despawn(player, uid)
	local plot = PlotService.get(player)
	local slot = record.slot
	if plot == nil or slot == nil or not plot.pedestals[slot] then
		return
	end
	if carried[player] and carried[player][uid] then
		return -- a thief is holding it; StealService respawns it if it comes home
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

local function freeSlot(data: PlayerData): number?
	local used: { [number]: boolean } = {}
	for _, record in data.creatures do
		if record.slot then
			used[record.slot] = true
		end
	end
	-- Regular pedestals first; the nursery is filled only on request (or as a last resort)
	for slot = nurserySlots + 1, Config.Economy.tunables.pedestalsBase do
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

-- Swaps a creature into the nursery (or back out to a regular pedestal).
function CreatureService.toggleNursery(player: Player, uid: string)
	local data = DataService.get(player)
	local record = data and data.creatures[uid]
	if data == nil or record == nil or CreatureService.isCarried(player, uid) then
		return
	end
	local target: number? = nil
	if CreatureService.isNursery(record.slot) then
		for slot = nurserySlots + 1, Config.Economy.tunables.pedestalsBase do
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
		carried[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return CreatureService

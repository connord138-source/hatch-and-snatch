--!strict
-- Eggs and incubators (docs/GDD.md §3.1).
--
--  * Buying an egg off the belt puts it in the player's hands (held over their
--    head). They carry it home and place it into a free incubator.
--  * Players start with one incubator and buy more bays; each bay can be upgraded
--    through tiers that hatch faster and accept eggs from later biomes.
--  * The species is rolled at purchase. Past 40% of incubation the incubator
--    starts showing the rarity's color, stronger the closer it gets.
--  * Luck: a luck charge won on the Luck Wheel (WheelService) is spent on the
--    next egg bought: its species roll uses Epic+ weights × the luck.
--  * Finish + mutation roll at hatch, then the client plays the hatch reveal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Timing = require(ReplicatedStorage.Shared.Timing)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local Analytics = require(script.Parent.Parent.Analytics)
local Net = require(script.Parent.Parent.Net)
local Props = require(script.Parent.Parent.Props)
local CreatureService = require(script.Parent.CreatureService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local WorldService = require(script.Parent.WorldService)

type PlayerData = DataService.PlayerData
type IncubatorRecord = DataService.IncubatorRecord

local Progression = Config.Progression
local tunables = Config.Economy.tunables
local rng = Random.new()

local INCUBATOR_EGG_HEIGHT = 2.4
local HELD_EGG_HEIGHT = 2.2
local HINT_START = 0.4 -- incubation progress where the rarity color starts to show
local LOCKED_PAD = Color3.fromRGB(90, 90, 100)

local HatchService = {}

local finishById: { [string]: Types.Finish } = {}
for _, finish in Config.Finishes do
	finishById[finish.id] = finish
end

type BayPrompts = {
	buy: ProximityPrompt,
	place: ProximityPrompt,
	upgrade: ProximityPrompt,
}
local bayPrompts: { [BasePart]: BayPrompts } = {}

local function eggInSlot(data: PlayerData, slot: number): IncubatorRecord?
	for _, egg in data.incubators do
		if egg.slot == slot then
			return egg
		end
	end
	return nil
end

local function biomeOrder(biomeId: string): number
	return Config.Biomes[biomeId].order
end

-- Can this incubator tier hold an egg from `biomeId`?
local function tierFits(tier: number, biomeId: string): boolean
	return tier >= Progression.tierForBiome(biomeOrder(biomeId))
end

---------------------------------------------------------------------------
-- Visuals + prompts
---------------------------------------------------------------------------

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

local function prompt(
	parent: Instance,
	name: string,
	key: Enum.KeyCode,
	offset: number,
	hold: number
): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.KeyboardKeyCode = key
	p.HoldDuration = hold
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.UIOffset = Vector2.new(0, offset)
	-- Shown/hidden with the Active attribute: the client PromptFilter owns Enabled
	p:SetAttribute("Active", false)
	p:SetAttribute("VisibleTo", "owner")
	p.Parent = parent
	return p
end

-- Brings one incubator bay in line with its owner's data (nil = free plot).
local function refreshBay(data: PlayerData?, slot: number, part: BasePart, pad: BasePart)
	local owned = data ~= nil and slot <= #data.incubatorTiers
	local tier = if data and owned then data.incubatorTiers[slot] else 0
	local egg = if data then eggInSlot(data, slot) else nil
	local eggBiome = if egg then egg.biome else nil

	part:SetAttribute("Owned", owned)
	part:SetAttribute("Tier", tier)
	part:SetAttribute("TierName", if owned then Progression.incubatorTiers[tier].name else nil)
	part:SetAttribute("StartedAt", if egg then egg.startedAt else nil)
	part:SetAttribute("HatchAt", if egg then egg.hatchAt else nil)
	if part:GetAttribute("EggBiome") ~= eggBiome then
		part:SetAttribute("EggBiome", eggBiome)
		setEggVisual(part, eggBiome)
	end

	-- The imported incubator model only shows on owned bays
	local prop = part.Parent and part.Parent:FindFirstChild(`IncubatorProp{slot}`)
	if prop then
		for _, descendant in prop:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = if owned then 0.45 else 1
			end
		end
	else
		part.Transparency = if owned then 0.4 else 1
	end
	pad.Color = if owned then Progression.incubatorTiers[tier].color else LOCKED_PAD
	pad.Transparency = if owned then 0 else 0.3

	local prompts = bayPrompts[part]
	if prompts == nil then
		return
	end
	local nextSlot = if data then #data.incubatorTiers + 1 else 0
	local slotCost = Progression.incubatorSlotCosts[slot]
	local held = if data then data.heldEgg else nil
	-- Not while carrying an egg: Roblox shows one E prompt at a time, and the next
	-- pad's Buy prompt kept winning over Place Egg on the bay beside it. (Carrying an
	-- egg means a free incubator exists — buying checks that — so nothing is lost.)
	prompts.buy:SetAttribute("Active", data ~= nil and slot == nextSlot and slotCost ~= nil and held == nil)
	prompts.buy.ActionText = `Buy Incubator ({Format.cash(slotCost or 0)})`

	prompts.place:SetAttribute("Active", owned and egg == nil and held ~= nil)
	if held and owned then
		local need = Progression.tierForBiome(biomeOrder(held.biome))
		prompts.place.ActionText = if tier >= need
			then "Place Egg"
			else `Needs a {Progression.incubatorTiers[need].name} incubator`
	end

	local nextTier = Progression.incubatorTiers[tier + 1]
	prompts.upgrade:SetAttribute("Active", owned and nextTier ~= nil)
	if nextTier then
		prompts.upgrade.ActionText = `Upgrade to {nextTier.name} ({Format.cash(nextTier.upgradeCost)})`
		prompts.upgrade.ObjectText = `{nextTier.speed}× speed · takes biome {nextTier.maxBiomeOrder} eggs`
	end
end

function HatchService.refresh(player: Player, data: PlayerData)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	for slot, part in plot.incubators do
		refreshBay(data, slot, part, plot.incubatorPads[slot])
	end
end
local refreshIncubators = HatchService.refresh

---------------------------------------------------------------------------
-- Held eggs
---------------------------------------------------------------------------

local function attachHeldEgg(player: Player, biomeId: string?)
	local character = player.Character
	if character == nil then
		return
	end
	local existing = character:FindFirstChild("HeldEgg")
	if existing then
		existing:Destroy()
	end
	if biomeId == nil then
		return
	end
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "HeldEgg"
	anchor.Size = Vector3.new(1.6, 2, 1.6)
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Massless = true
	anchor.Color = Config.Eggs.eggColors[biomeId]
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.CFrame = head.CFrame * CFrame.new(0, 2.4, 0)
	local model = Props.egg(biomeId, HELD_EGG_HEIGHT)
	if model then
		anchor.Transparency = 1
		Props.weldCentered(model, anchor)
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = anchor
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = anchor
	weld.Parent = anchor
	anchor.Parent = character
end

-- Some owned incubator that is free and can take this biome's eggs?
function HatchService.freeIncubatorFor(data: PlayerData, biomeId: string): boolean
	for slot, tier in data.incubatorTiers do
		if eggInSlot(data, slot) == nil and tierFits(tier, biomeId) then
			return true
		end
	end
	return false
end

-- Whether any owned incubator (busy or not) could ever take this biome's eggs.
function HatchService.hasTierFor(data: PlayerData, biomeId: string): boolean
	for _, tier in data.incubatorTiers do
		if tierFits(tier, biomeId) then
			return true
		end
	end
	return false
end

-- Name of the incubator tier a biome's eggs need.
function HatchService.tierNameFor(biomeId: string): string
	return Progression.incubatorTiers[Progression.tierForBiome(biomeOrder(biomeId))].name
end

-- Hands a just-bought egg to the player. Caller has already charged them.
function HatchService.giveEgg(player: Player, biomeId: string)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	-- A luck charge from the Luck Wheel is spent on this egg, and a Server Luck boost
	-- multiplies it (Junk eggs ignore luck)
	local charge = if data.luckCharge > 1 then data.luckCharge else nil
	local luck = if biomeId ~= "Junk" then (charge or 1) * MonetizationService.serverLuck() else 1
	-- Everything random about the egg is rolled now, when it's bought, with the
	-- same odds the odds panel showed the buyer (Eggs.speciesOdds,
	-- Economy.finishOdds and mutationOdds): paid random items must disclose them
	local species =
		Config.Eggs.rollSpecies(biomeId, rng, EventService.activeId() ~= nil, if luck > 1 then luck else nil)
	local finish = Config.Economy.rollFinish(rng, EventService.activeId(), EventService.finishMultiplier())
	local mutation = Config.Economy.rollMutation(rng)
	if charge and biomeId ~= "Junk" then
		data.luckCharge = 1
		Net.notify(player, `Your ×{charge} Luck Wheel charge was used on this egg!`, "rare")
	end
	data.heldEgg = { biome = biomeId, species = species, finish = finish, mutation = mutation }
	attachHeldEgg(player, biomeId)
	refreshIncubators(player, data)
	DataService.markDirty(player)
end

local function place(player: Player, slot: number)
	local data = DataService.get(player)
	if data == nil or data.heldEgg == nil or slot > #data.incubatorTiers or eggInSlot(data, slot) then
		return
	end
	local held = data.heldEgg :: DataService.HeldEgg
	local tier = data.incubatorTiers[slot]
	if not tierFits(tier, held.biome) then
		Net.notify(
			player,
			`{Config.Biomes[held.biome].displayName} eggs need a {HatchService.tierNameFor(held.biome)} incubator.`,
			"bad"
		)
		return
	end
	local rarity = Config.Rarities[Config.CreaturesById[held.species].rarity]
	local now = Timing.now()
	local hatchAt = now + Timing.scaled(rarity.hatchSeconds) / Progression.incubatorTiers[tier].speed
	-- A Skip Hatch bought with no egg incubating is kept for the next egg placed
	if (data.boosts.instantHatch or 0) > 0 then
		data.boosts.instantHatch -= 1
		hatchAt = now + 3
	end
	table.insert(data.incubators, {
		biome = held.biome,
		species = held.species,
		finish = held.finish,
		mutation = held.mutation,
		startedAt = now,
		hatchAt = hatchAt,
		slot = slot,
	})
	data.heldEgg = nil
	attachHeldEgg(player, nil)
	Analytics.onboard(player, data, 3)
	Net.notify(player, "Egg placed! Its glow shows the rarity as it gets close to hatching.", "good")
	refreshIncubators(player, data)
	DataService.markDirty(player)
end

---------------------------------------------------------------------------
-- Buying + upgrading incubators
---------------------------------------------------------------------------

local function buyIncubator(player: Player, slot: number)
	local data = DataService.get(player)
	if data == nil or slot ~= #data.incubatorTiers + 1 then
		return
	end
	local cost = Progression.incubatorSlotCosts[slot]
	if cost == nil then
		return
	end
	if not EconomyService.spend(player, cost, `Incubator{slot}`) then
		Net.notify(player, `You need {Format.cash(cost)} for another incubator.`, "bad")
		return
	end
	table.insert(data.incubatorTiers, 1)
	Net.notify(player, `Incubator {slot} built!`, "good")
	ProgressionService.addXp(player, Progression.xp.incubatorBought)
	ProgressionService.setStat(player, "incubators", #data.incubatorTiers)
	refreshIncubators(player, data)
	DataService.markDirty(player)
end

local function upgradeIncubator(player: Player, slot: number)
	local data = DataService.get(player)
	if data == nil or slot > #data.incubatorTiers then
		return
	end
	local tier = data.incubatorTiers[slot]
	local nextTier = Progression.incubatorTiers[tier + 1]
	if nextTier == nil then
		return
	end
	if not EconomyService.spend(player, nextTier.upgradeCost, `IncubatorTier{tier + 1}`) then
		Net.notify(
			player,
			`You need {Format.cash(nextTier.upgradeCost)} for a {nextTier.name} incubator.`,
			"bad"
		)
		return
	end
	data.incubatorTiers[slot] = tier + 1
	-- An egg already inside speeds up for the rest of its time, keeping its progress
	local egg = eggInSlot(data, slot)
	if egg then
		local now = Timing.now()
		local span = math.max(egg.hatchAt - egg.startedAt, 1)
		local progress = math.clamp((now - egg.startedAt) / span, 0, 1)
		local newSpan = span * Progression.incubatorTiers[tier].speed / nextTier.speed
		egg.startedAt = now - newSpan * progress
		egg.hatchAt = egg.startedAt + newSpan
	end
	Net.notify(player, `Incubator {slot} is now {nextTier.name}: {nextTier.speed}× speed!`, "rare")
	ProgressionService.addXp(player, Progression.xp.incubatorUpgraded)
	refreshIncubators(player, data)
	DataService.markDirty(player)
end

---------------------------------------------------------------------------
-- Hatching
---------------------------------------------------------------------------

local function hatch(player: Player, data: PlayerData, index: number)
	local egg = table.remove(data.incubators, index)
	if egg == nil then
		return
	end
	-- Rolled at purchase (eggs from older saves roll here)
	local finishId = egg.finish
		or Config.Economy.rollFinish(rng, EventService.activeId(), EventService.finishMultiplier())
	local mutation = if egg.finish then egg.mutation else Config.Economy.rollMutation(rng)
	local uid = CreatureService.add(player, {
		species = egg.species,
		stage = "Baby",
		stageStartedAt = Timing.now(),
		finish = finishId,
		mutation = mutation,
		homegrown = true,
	})

	local creature = Config.CreaturesById[egg.species]
	local finish = finishById[finishId]
	local rarity = Config.Rarities[creature.rarity]
	local parts = {}
	if finishId ~= "Normal" then
		table.insert(parts, finish.displayName)
	end
	if mutation then
		table.insert(parts, mutation)
	end
	table.insert(parts, creature.displayName)
	local name = table.concat(parts, " ")

	Analytics.onboard(player, data, 4)
	Analytics.event(
		player,
		"Hatch",
		1,
		{ tostring(creature.rarity), egg.biome, if finishId == "Normal" then "Normal" else "Finish" }
	)
	Net.hatchReveal(player, {
		species = egg.species,
		biome = egg.biome,
		finish = finishId,
		mutation = mutation,
	})
	if uid and data.creatures[uid] and data.creatures[uid].slot == nil then
		task.delay(5, function()
			Net.notify(player, "Your pedestals are full, so it went to storage (Creatures menu).", "bad")
		end)
	end
	-- Server-wide news waits for the reveal to finish on the hatcher's screen
	task.delay(5, function()
		if rarity.announce then
			Net.announce(`{player.DisplayName} hatched a {creature.rarity:upper()} {name}!`, rarity.color)
		elseif finish.announce ~= "none" then
			Net.announce(`{player.DisplayName} hatched a {name}!`, rarity.color)
		end
	end)

	local order = if Config.Biomes[egg.biome].order > 0 then Config.Biomes[egg.biome].order else 3
	ProgressionService.addXp(player, Progression.xp.hatchPerBiomeOrder * order)
	ProgressionService.bump(player, "hatched")
	if finishId ~= "Normal" then
		ProgressionService.bump(player, "finishes")
	end
end

-- Rarity hint + glow: nothing until HINT_START, then the rarity's color fades in.
local function updateHints(player: Player, data: PlayerData, now: number)
	local plot = PlotService.get(player)
	if plot == nil then
		return
	end
	for slot, part in plot.incubators do
		local egg = eggInSlot(data, slot)
		local light = part:FindFirstChild("RarityGlow") :: PointLight?
		local progress = 0
		if egg then
			progress = math.clamp((now - egg.startedAt) / math.max(egg.hatchAt - egg.startedAt, 1), 0, 1)
		end
		if egg == nil or progress < HINT_START then
			part:SetAttribute("HintColor", nil)
			if light then
				light:Destroy()
			end
			continue
		end
		local rarity = Config.Rarities[Config.CreaturesById[(egg :: IncubatorRecord).species].rarity]
		local strength = (progress - HINT_START) / (1 - HINT_START) -- 0..1
		local color = Color3.new(1, 1, 1):Lerp(rarity.color, strength)
		part:SetAttribute("HintColor", color)
		if light == nil then
			local newLight = Instance.new("PointLight")
			newLight.Name = "RarityGlow"
			newLight.Shadows = false
			newLight.Parent = part
			light = newLight
		end
		local glow = light :: PointLight
		glow.Color = color
		glow.Brightness = 0.4 + strength * strength * (1 + rarity.order * 0.5)
		glow.Range = 5 + strength * (5 + rarity.order * 1.5)
	end
end

local function tick()
	local now = Timing.now()
	for player, data in DataService.loadedPlayers() do
		local changed = false
		for i = #data.incubators, 1, -1 do
			if now >= data.incubators[i].hatchAt then
				hatch(player, data, i)
				changed = true
			end
		end
		-- Free Luck Wheel spins for time played
		data.spinProgress += 1
		if data.spinProgress >= tunables.freeSpinSeconds then
			data.spinProgress = 0
			if data.spins < tunables.maxBankedSpins then
				data.spins += 1
				Net.notify(player, `+1 Luck Wheel spin! ({data.spins} banked)`, "good")
				changed = true
			end
		end
		if changed then
			refreshIncubators(player, data)
			DataService.markDirty(player)
		end
		updateHints(player, data, now)
	end
end

function HatchService.start()
	-- Skip Hatch: every incubating egg hatches on the next tick; with none
	-- incubating, the next egg placed hatches right away
	MonetizationService.onProduct("SkipHatch", function(player, data)
		if #data.incubators > 0 then
			local now = Timing.now()
			for _, egg in data.incubators do
				egg.hatchAt = math.min(egg.hatchAt, now)
			end
			HatchService.refresh(player, data)
			Net.notify(player, "Skip Hatch: your eggs are hatching now!", "rare")
		else
			data.boosts.instantHatch = (data.boosts.instantHatch or 0) + 1
			Net.notify(player, "Skip Hatch: the next egg you place hatches instantly!", "rare")
		end
	end)
	-- Prompts on every bay; each checks that the triggering player owns the plot
	for _, plot in WorldService.plots do
		for slot, part in plot.incubators do
			local pad = plot.incubatorPads[slot]
			local prompts: BayPrompts = {
				buy = prompt(pad, "BuyIncubator", Enum.KeyCode.E, 0, 0.4),
				place = prompt(part, "PlaceEgg", Enum.KeyCode.E, 0, 0),
				upgrade = prompt(part, "UpgradeIncubator", Enum.KeyCode.R, 120, 0.6),
			}
			prompts.buy.ObjectText = "Incubator bay"
			prompts.place.ObjectText = "Incubator"
			bayPrompts[part] = prompts
			local actions: { [ProximityPrompt]: (Player, number) -> () } = {
				[prompts.buy] = buyIncubator,
				[prompts.place] = place,
				[prompts.upgrade] = upgradeIncubator,
			}
			for p, action in actions do
				p.Triggered:Connect(function(who)
					if PlotService.ownerOf(plot) == who then
						action(who, slot)
					end
				end)
			end
			refreshBay(nil, slot, part, pad)
		end
	end

	-- Runs after PlotService assigned the plot (connect order in init.server)
	DataService.loaded:connect(function(player: Player, data: PlayerData)
		refreshIncubators(player, data)
		local function onCharacter()
			task.wait(0.5) -- let the character finish loading
			local current = DataService.get(player)
			local held = current and current.heldEgg
			if held then
				attachHeldEgg(player, held.biome)
			end
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter)
		end
	end)
	PlotService.released:connect(function(plot: WorldService.PlotLayout)
		for slot, part in plot.incubators do
			refreshBay(nil, slot, part, plot.incubatorPads[slot])
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return HatchService

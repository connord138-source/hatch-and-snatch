--!strict
-- The working parts of a base (owner, 2026-10-01):
--  * the Command Terminal: a console with a monitor where the owner opens the base
--    menu (themes, decor, hiding spots);
--  * buy pads: walk-over pads in the front yard for every upgrade (base level,
--    security, floors, vaults, hiding spots, decor and security items). Stand on
--    one for a moment to buy (BaseService);
--  * hiding spots: props that each hold one creature out of sight, which thieves
--    can search (StealService);
--  * the security fixtures: spike strip, ramp gates, net ballista, searchlight
--    and the alarm bell (StealService runs their timers).
-- Everything is built once per plot, hidden, and placed or shown as the base
-- grows. Plot-local: -Z faces the hub, y 0 is the ground, the floor top is y 1.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Props = require(script.Parent.Props)

export type Pad = {
	part: BasePart,
	label: TextLabel,
	ring: BasePart,
	key: string?, -- what it buys right now (BaseService), nil when hidden
}
export type HideSpot = {
	spot: number,
	anchor: BasePart, -- where the hidden creature sits; carries the prompts
	search: ProximityPrompt, -- thieves
	manage: ProximityPrompt, -- the owner: opens the Creatures menu
	look: Instance?, -- the prop or its stand-in
	owned: boolean,
}
export type Security = {
	spikes: { BasePart },
	spikeBase: BasePart,
	lever: BasePart,
	leverPrompt: ProximityPrompt,
	bars: { BasePart }, -- [1] the ground ramp's foot, [2] the Top Floor ramp's foot
	ballista: BasePart,
	ballistaPrompt: ProximityPrompt,
	searchlight: BasePart,
	beam: SpotLight,
	bell: BasePart,
	looks: { [string]: Instance }, -- imported models by fixture
	spikesRaised: boolean,
}

local TOP = 1
local PAD_COUNT = 8
local PAD_SIZE = 5
local PAD_Z = -3 -- the band between the front row and the pedestals
local PAD_GAP = 7
local HIDE_INSET = 3.5
local HIDE_Z = { 12, 12, 28, 28 }
local HIDE_SIDE = { -1, 1, -1, 1 }

local BaseKit = {}

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function billboard(parent: BasePart, offset: Vector3, size: UDim2, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return label
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	hold: number,
	visibleTo: string
): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p:SetAttribute("VisibleTo", visibleTo)
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Command Terminal
---------------------------------------------------------------------------

-- Replaces the old upgrade gem (between the lock button and the cash pad).
function BaseKit.terminal(model: Model, origin: CFrame): (BasePart, ProximityPrompt, TextLabel)
	local base = origin * CFrame.new(7.5, TOP, -16) * CFrame.Angles(0, math.pi, 0) -- faces into the base
	local desk = part(model, {
		Name = "CommandTerminal",
		Size = Vector3.new(4.4, 3, 2.4),
		CFrame = base * CFrame.new(0, 1.5, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(90, 88, 96),
	})
	local imported = Props.spawn("BaseTerminal", base, 6, model)
	local screen: BasePart
	if imported then
		desk.Transparency = 1
		screen = part(model, {
			Name = "TerminalScreen",
			Size = Vector3.new(3.6, 2.4, 0.2),
			CFrame = base * CFrame.new(0, 4.6, 0.2) * CFrame.Angles(math.rad(-12), 0, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
	else
		part(model, {
			Name = "TerminalTrim",
			Size = Vector3.new(4.6, 0.3, 2.6),
			CFrame = base * CFrame.new(0, 3.1, 0),
			Material = Enum.Material.Foil,
			Color = Color3.fromRGB(205, 160, 70),
			CanCollide = false,
		})
		screen = part(model, {
			Name = "TerminalScreen",
			Size = Vector3.new(3.6, 2.4, 0.3),
			CFrame = base * CFrame.new(0, 4.6, 0.4) * CFrame.Angles(math.rad(-12), 0, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 150, 255),
			CanCollide = false,
		})
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(110, 180, 255)
	glow.Range = 10
	glow.Brightness = 1
	glow.Parent = screen
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the screen faces the player standing in the base
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = screen
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(12, 24, 48)
	text.BackgroundTransparency = 0.15
	text.Font = Enum.Font.Code
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(140, 220, 255)
	text.Text = "BASE TERMINAL"
	text.Parent = gui
	local open = prompt(desk, "Terminal", "Open Terminal", "Command Terminal", 0, "owner")
	open:SetAttribute("OpensMenu", "Base")
	return desk, open, text
end

---------------------------------------------------------------------------
-- Buy pads
---------------------------------------------------------------------------

function BaseKit.pads(model: Model, origin: CFrame): { Pad }
	local list: { Pad } = {}
	for i = 1, PAD_COUNT do
		local x = (i - (PAD_COUNT + 1) / 2) * PAD_GAP
		local base = origin * CFrame.new(x, TOP, PAD_Z)
		local pad = part(model, {
			Name = "BuyPad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, PAD_SIZE, PAD_SIZE),
			CFrame = base * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(70, 70, 78),
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
		})
		local ring = part(model, {
			Name = "BuyPadRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, PAD_SIZE - 0.8, PAD_SIZE - 0.8),
			CFrame = base * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(80, 230, 120),
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
		})
		local label = billboard(pad, Vector3.new(0, 3.6, 0), UDim2.fromOffset(170, 64), 45)
		label.RichText = true
		local gui = label.Parent :: BillboardGui
		gui.Enabled = false
		table.insert(list, { part = pad, label = label, ring = ring, key = nil })
	end
	return list
end

-- Shows a pad selling `title` for `price` (nil hides it). Green when affordable.
function BaseKit.setPad(pad: Pad, key: string?, title: string?, price: string?, affordable: boolean?)
	pad.key = key
	pad.part:SetAttribute("Offer", if key then string.match(key, "^[^:]+") else nil) -- the guide arrow finds "level"
	local shown = key ~= nil
	pad.part.Transparency = if shown then 0 else 1
	pad.ring.Transparency = if shown then 0.1 else 1
	pad.ring.Color = if affordable then Color3.fromRGB(80, 230, 120) else Color3.fromRGB(230, 80, 70)
	local gui = pad.label.Parent :: BillboardGui
	gui.Enabled = shown
	if shown then
		local color = if affordable then "#8CFF9E" else "#FF8C80"
		pad.label.Text = `{title}\n<font color="{color}">{price}</font>`
	end
end

---------------------------------------------------------------------------
-- Hiding spots
---------------------------------------------------------------------------

local function standInHide(spot: number, parent: Instance, base: CFrame)
	if spot == 1 then
		part(parent, {
			Name = "Hay",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 4.4, 4.4),
			CFrame = base * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(220, 185, 80),
			CanCollide = false,
		})
		part(parent, {
			Name = "Hay",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4.4, 3, 4.4),
			CFrame = base * CFrame.new(0, 3, 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(230, 195, 90),
			CanCollide = false,
		})
	elseif spot == 2 then
		for i, offset in { Vector3.new(-1.3, 0, 0), Vector3.new(1.3, 0, 0), Vector3.new(0, 2.6, 0) } do
			part(parent, {
				Name = "Barrel" .. i,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.6, 2.4, 2.4),
				CFrame = base
					* CFrame.new(offset + Vector3.new(0, 1.3, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(140, 95, 55),
				CanCollide = false,
			})
		end
	elseif spot == 3 then
		part(parent, {
			Name = "Hedge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5, 4.4, 5),
			CFrame = base * CFrame.new(0, 2.2, 0),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromRGB(60, 120, 50),
			CanCollide = false,
		})
	else
		part(parent, {
			Name = "Chest",
			Size = Vector3.new(4, 2.4, 2.8),
			CFrame = base * CFrame.new(0, 1.2, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(110, 65, 35),
			CanCollide = false,
		})
		part(parent, {
			Name = "ChestLid",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, 2.8, 2.8),
			CFrame = base * CFrame.new(0, 2.4, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(120, 72, 38),
			CanCollide = false,
		})
		part(parent, {
			Name = "ChestTrim",
			Size = Vector3.new(4.2, 0.4, 3),
			CFrame = base * CFrame.new(0, 2.4, 0),
			Material = Enum.Material.Foil,
			Color = Color3.fromRGB(240, 195, 70),
			CanCollide = false,
		})
	end
end

function BaseKit.hideSpots(model: Model, origin: CFrame): { HideSpot }
	local spots: { HideSpot } = {}
	for spot, info in Config.BaseBuilds.hidingSpots do
		local anchor = part(model, {
			Name = `HidingSpot{spot}`,
			Size = Vector3.new(4, 4.5, 4),
			CFrame = origin * CFrame.new(0, -50, 0), -- placed by placeHides
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local search =
			prompt(anchor, "Search", "Search", info.name, Config.BaseBuilds.searchSeconds, "others")
		search:SetAttribute("Active", false)
		local manage = prompt(anchor, "Hide", "Hide a Creature", info.name, 0, "owner")
		manage:SetAttribute("OpensMenu", "Creatures")
		manage:SetAttribute("Active", false)
		table.insert(
			spots,
			{ spot = spot, anchor = anchor, search = search, manage = manage, look = nil, owned = false }
		)
	end
	return spots
end

-- Places the spots for the plot's width (inside the side walls, by the pedestal
-- rows) and shows the first `count`. Returns where hidden creatures sit, by slot.
function BaseKit.placeHides(
	model: Model,
	spots: { HideSpot },
	origin: CFrame,
	width: number,
	count: number
): { [number]: CFrame }
	local seats: { [number]: CFrame } = {}
	for _, entry in spots do
		local spot = entry.spot
		local x = HIDE_SIDE[spot] * (width / 2 - HIDE_INSET)
		local base = origin
			* CFrame.new(x, TOP, HIDE_Z[spot])
			* CFrame.Angles(0, math.rad(HIDE_SIDE[spot] * -90), 0)
		entry.anchor.CFrame = base * CFrame.new(0, 2.25, 0)
		seats[Config.Economy.hideSlot(spot)] = base * CFrame.new(0, 0.6, 0)
		local owned = spot <= count
		entry.owned = owned
		entry.search:SetAttribute("Active", owned)
		entry.manage:SetAttribute("Active", owned)
		if entry.look then
			entry.look:Destroy()
			entry.look = nil
		end
		if owned then
			local info: Config.HidingSpot = Config.BaseBuilds.hidingSpots[spot]
			local look = Props.spawn(info.prop, base, 4.6, model)
			if look == nil then
				local folder = Instance.new("Model")
				folder.Name = info.prop
				standInHide(spot, folder, base)
				folder.Parent = model
				look = folder
			end
			entry.look = look
		end
	end
	return seats
end

---------------------------------------------------------------------------
-- Security fixtures
---------------------------------------------------------------------------

function BaseKit.security(model: Model, origin: CFrame): Security
	local hidden: { [string]: any } = { Transparency = 1, CanCollide = false, CanQuery = false }
	local function fixture(props: { [string]: any }): BasePart
		for key, value in hidden do
			if props[key] == nil then
				props[key] = value
			end
		end
		return part(model, props)
	end
	local spikeBase = fixture({
		Name = "SpikeStrip",
		Size = Vector3.new(12, 0.3, 2.2),
		CFrame = origin,
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 85, 55),
	})
	local spikes: { BasePart } = {}
	for _ = 1, 9 do
		table.insert(
			spikes,
			fixture({
				Name = "Spike",
				Size = Vector3.new(0.45, 1.3, 0.45),
				CFrame = origin,
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(70, 70, 78),
			})
		)
	end
	local lever = fixture({
		Name = "RampLever",
		Size = Vector3.new(1.6, 3.4, 1.6),
		CFrame = origin,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(80, 80, 90),
	})
	local leverPrompt = prompt(lever, "RampGates", "Bar the Ramps", "Ramp Gates", 0.3, "owner")
	leverPrompt:SetAttribute("Active", false)
	local bars: { BasePart } = {
		fixture({
			Name = "RampBars",
			Size = Vector3.new(6.6, 9, 0.6),
			CFrame = origin,
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(60, 60, 68),
		}),
		fixture({
			Name = "RampBars",
			Size = Vector3.new(6.6, 9, 0.6),
			CFrame = origin,
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(60, 60, 68),
		}),
	}
	local ballista = fixture({
		Name = "NetBallista",
		Size = Vector3.new(4, 3, 4),
		CFrame = origin,
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(130, 90, 55),
	})
	local ballistaPrompt = prompt(ballista, "NetBallista", "Fire Net", "Net Ballista", 0.3, "owner")
	ballistaPrompt.MaxActivationDistance = 10
	ballistaPrompt:SetAttribute("Active", false)
	local searchlight = fixture({
		Name = "Searchlight",
		Size = Vector3.new(2.4, 12, 2.4),
		CFrame = origin,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(90, 90, 98),
	})
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Angle = 35
	beam.Range = 50
	beam.Brightness = 3
	beam.Color = Color3.fromRGB(255, 245, 200)
	beam.Enabled = false
	beam.Parent = searchlight
	local bell = fixture({
		Name = "AlarmBell",
		Size = Vector3.new(3, 6, 2),
		CFrame = origin,
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 85, 55),
	})
	return {
		spikes = spikes,
		spikeBase = spikeBase,
		lever = lever,
		leverPrompt = leverPrompt,
		bars = bars,
		ballista = ballista,
		ballistaPrompt = ballistaPrompt,
		searchlight = searchlight,
		beam = beam,
		bell = bell,
		looks = {},
		spikesRaised = false,
	}
end

-- Where the security fixtures stand for a plot's size, and which are owned.
-- `raised` pops the spikes up (StealService, while the strip holds someone).
-- `gates` says where the keep's ramps start (WorldService's layout, plot-local):
-- the lever by the first one's foot and a bar across each ramp's foot.
export type Gates = { lever: Vector3, bars: { Vector3 } }

function BaseKit.placeSecurity(
	model: Model,
	security: Security,
	origin: CFrame,
	width: number,
	depth: number,
	plotFront: number,
	owned: { [string]: boolean },
	alarm: boolean,
	floors: number,
	gates: Gates
)
	local function set(p: BasePart, visible: boolean, cframe: CFrame, solid: boolean?)
		p.CFrame = cframe
		p.Transparency = if visible then 0 else 1
		p.CanCollide = visible and solid == true
		p.CanQuery = visible
	end
	local function look(name: string, visible: boolean, base: CFrame, height: number, stand: BasePart)
		local current = security.looks[name]
		if current then
			current:Destroy()
			security.looks[name] = nil
		end
		if visible then
			local imported = Props.spawn(name, base, height, model)
			if imported then
				security.looks[name] = imported
				stand.Transparency = 1
			end
		end
	end
	local halfW = width / 2

	-- Spike strip just inside the gate
	local spikeAt = origin * CFrame.new(0, TOP, plotFront + 2)
	local hasSpikes = owned.SpikeStrip == true
	set(security.spikeBase, hasSpikes, spikeAt * CFrame.new(0, 0.15, 0))
	security.spikesRaised = false
	for i, spike in security.spikes do
		set(spike, hasSpikes, spikeAt * CFrame.new(-5.6 + (i - 1) * 1.4, -0.2, 0))
	end
	look("SpikeStrip", hasSpikes, spikeAt, 1.2, security.spikeBase)

	-- Ramp gates: the lever by the foot of the ramp, bars at each ramp's foot
	local hasGates = owned.RampGates == true and floors >= 2
	set(security.lever, hasGates, origin * CFrame.new(gates.lever), true)
	security.leverPrompt:SetAttribute("Active", hasGates)
	for i, bar in security.bars do
		local at = gates.bars[i]
		if at then
			bar.CFrame = origin * CFrame.new(at)
		end
	end

	-- Net ballista in the front-left corner, looking out over the gate
	local hasBallista = owned.NetBallista == true
	local ballistaAt = origin * CFrame.new(-(halfW - 4), TOP, plotFront + 4) * CFrame.Angles(0, math.pi, 0)
	set(security.ballista, hasBallista, ballistaAt * CFrame.new(0, 1.5, 0), true)
	security.ballistaPrompt:SetAttribute("Active", hasBallista)
	look("NetBallista", hasBallista, ballistaAt, 5, security.ballista)

	-- Searchlight tower in the back-left corner, sweeping the yard
	local hasLight = owned.Searchlight == true
	local lightAt = origin * CFrame.new(-(halfW - 4), TOP, plotFront + depth - 4)
	set(
		security.searchlight,
		hasLight,
		CFrame.lookAt(
			(lightAt * CFrame.new(0, 6, 0)).Position,
			(origin * CFrame.new(0, 0, plotFront)).Position
		),
		true
	)
	security.beam.Enabled = hasLight
	look("SearchlightTower", hasLight, lightAt, 14, security.searchlight)

	-- The alarm bell (security level 1) by the left side
	local bellAt = origin * CFrame.new(-(halfW - 3), TOP, 2) * CFrame.Angles(0, math.rad(90), 0)
	set(security.bell, alarm, bellAt * CFrame.new(0, 3, 0), true)
	look("AlarmBell", alarm, bellAt, 6, security.bell)
end

-- The spikes stand up while the strip holds an intruder.
function BaseKit.raiseSpikes(security: Security, raised: boolean)
	if security.spikesRaised == raised then
		return
	end
	security.spikesRaised = raised
	for _, spike in security.spikes do
		spike.CFrame = spike.CFrame * CFrame.new(0, if raised then 0.9 else -0.9, 0)
	end
end

-- The ramp bars come down (solid) or go up (gone).
function BaseKit.setBars(security: Security, down: boolean, floors: number)
	for i, bar in security.bars do
		local present = down and floors >= i + 1
		bar.Transparency = if present then 0.05 else 1
		bar.CanCollide = present
		bar.CanQuery = present
	end
end

return BaseKit

--!strict
-- First-session guide: an objective banner plus a glowing beam from the player to
-- the next thing to do, following the onboarding step the server tracks
-- (state.onboarding, see Analytics.ONBOARDING):
--   1 joined         → buy an egg off the belt (beam to the nearest affordable egg)
--   2 bought an egg  → place it in an incubator (beam to a free incubator)
--   3 placed it      → wait for the hatch (beam to that incubator, countdown)
--   4 hatched        → collect cash on the green pad (beam to the pad)
--   5 collected      → save up and upgrade the base (beam once it's affordable)
--   6 upgraded       → done; nothing shows.
-- Presentation only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer
local DONE = 6
local BEAM_COLOR = Color3.fromRGB(255, 225, 90)

local GuideController = {}

local function myPlot(world: Instance): Model?
	for _, child in world:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == player.UserId then
			return child
		end
	end
	return nil
end

-- The nearest egg on the belt this player could buy right now.
local function nearestEgg(state: { [string]: any }, from: Vector3): BasePart?
	local folder = Workspace:FindFirstChild("ConveyorEggs")
	if folder == nil then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, egg in folder:GetChildren() do
		local biomeId = egg.Name:match("^(.+)Egg$")
		local biome = biomeId and Config.Biomes[biomeId]
		local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt")
		if
			egg:IsA("BasePart")
			and biome
			and biome.order > 0
			and biome.order <= (state.unlockedBiome or 1)
			and Config.Eggs.price(biomeId :: string) <= state.cash
			and prompt
			and prompt.Enabled
		then
			local distance = (egg.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = egg, distance
			end
		end
	end
	return best
end

-- An owned incubator: with an egg in it (`occupied`) or empty.
local function incubator(plot: Model, occupied: boolean): BasePart?
	for i = 1, #Config.Progression.incubatorSlotCosts do
		local bay = plot:FindFirstChild(`Incubator{i}`)
		if bay and bay:IsA("BasePart") and bay:GetAttribute("Owned") == true then
			local hasEgg = bay:GetAttribute("HatchAt") ~= nil
			if hasEgg == occupied then
				return bay
			end
		end
	end
	return nil
end

function GuideController.start()
	local world = Workspace:WaitForChild("World")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchGuide"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4 -- under the menus
	gui.Parent = player:WaitForChild("PlayerGui")
	local banner = Ui.panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(460, 44),
		BackgroundColor3 = Color3.fromRGB(60, 50, 20),
		Visible = false,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = BEAM_COLOR
	stroke.Thickness = 2
	stroke.Parent = banner
	local text = Ui.label(banner, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextColor3 = Color3.fromRGB(255, 240, 190),
	})

	-- The beam: from the character to the current target. The target end lives on
	-- Terrain and follows the target's position (a bought egg is destroyed, and a
	-- destroyed part would take the attachment with it).
	local toAttachment = Instance.new("Attachment")
	toAttachment.Name = "GuideTarget"
	toAttachment.Parent = Workspace.Terrain
	local fromAttachment: Attachment? = nil
	local currentTarget: BasePart? = nil
	local beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Segments = 12
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.3, 0.25),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	beam.Attachment1 = toAttachment
	beam.Enabled = false
	beam.Parent = Workspace

	-- A bobbing arrow over the target
	local marker = Instance.new("BillboardGui")
	marker.Name = "GuideMarker"
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(60, 60)
	marker.StudsOffset = Vector3.new(0, 4, 0)
	marker.Enabled = false
	marker.Adornee = toAttachment
	local arrow = Ui.label(marker, {
		Size = UDim2.fromScale(1, 1),
		Text = "⬇",
		TextColor3 = BEAM_COLOR,
	})
	marker.Parent = gui

	local function point(target: BasePart?)
		currentTarget = target
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if target == nil or root == nil or not root:IsA("BasePart") then
			beam.Enabled = false
			marker.Enabled = false
			return
		end
		-- A new character (respawn) needs a new attachment
		if fromAttachment == nil or fromAttachment.Parent ~= root then
			local attachment = Instance.new("Attachment")
			attachment.Name = "GuideFrom"
			attachment.Parent = root
			fromAttachment = attachment
			beam.Attachment0 = attachment
		end
		toAttachment.WorldPosition = target.Position
		beam.Enabled = true
		marker.Enabled = true
	end

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		arrow.Position = UDim2.fromOffset(0, math.sin(os.clock() * 4) * 6)
		local following = currentTarget
		if following and following.Parent then
			toAttachment.WorldPosition = following.Position -- belt eggs keep moving
		end
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0

		local state = ClientState.current
		local plot = myPlot(world)
		local step: number = if state then state.onboarding or DONE else DONE
		if state == nil or plot == nil or step >= DONE then
			banner.Visible = false
			point(nil)
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else Vector3.zero

		local message: string
		local target: BasePart? = nil
		if state.heldEgg then
			message = "Carry your egg home and place it in your incubator (E)"
			target = incubator(plot, false)
		elseif step <= 1 then
			message = "Buy an egg from the conveyor belt in the middle (E)"
			target = nearestEgg(state, from)
		elseif step == 2 then
			message = "Place your egg in your incubator (E)"
			target = incubator(plot, false)
		elseif step == 3 then
			local soonest = math.huge
			for _, egg in state.incubators do
				soonest = math.min(soonest, egg.hatchAt)
			end
			local left = soonest - Workspace:GetServerTimeNow()
			message = if soonest == math.huge or left <= 0
				then "Your egg is hatching!"
				else `Your egg hatches in {Format.duration(left)}. Its glow shows the rarity!`
			target = incubator(plot, true)
		elseif step == 4 then
			message = if state.uncollected >= 1
				then `Your creature earned {Format.cash(state.uncollected)}! Step on the green pad to collect it`
				else "Your creature earns cash every second. Collect it on the green pad"
			local pad = plot:FindFirstChild("Collector")
			target = if pad and pad:IsA("BasePart") then pad else nil
		else
			local cost: number? = state.nextBaseCost
			if cost == nil then
				banner.Visible = false
				point(nil)
				return
			end
			if state.cash >= cost then
				message = `You can upgrade your base for {Format.cash(cost)}: more pedestals, more cash!`
				local station = plot:FindFirstChild("UpgradeStation")
				target = if station and station:IsA("BasePart") then station else nil
			else
				message =
					`Next goal: upgrade your base ({Format.cash(state.cash)} / {Format.cash(cost)}). Keep hatching!`
			end
		end
		text.Text = message
		banner.Visible = true
		point(target)
	end)
end

return GuideController

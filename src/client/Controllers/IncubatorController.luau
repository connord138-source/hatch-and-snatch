--!strict
-- Incubator displays (client): above every owned incubator a tag with its tier,
-- a countdown and a progress bar. The bar and the text take on the egg's rarity
-- color once the server starts hinting it (HintColor, from 40% progress), and the
-- egg wobbles harder and harder over the last 15%. Reads attributes HatchService
-- sets on each incubator part; presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)

type Display = {
	part: BasePart,
	gui: BillboardGui,
	title: TextLabel,
	timer: TextLabel,
	fill: Frame,
	base: CFrame?,
}

local displays: { [BasePart]: Display } = {}

local IncubatorController = {}

-- Positions are fractions of the (stud-sized) billboard
local function text(parent: Instance, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = parent
	return label
end

local function build(part: BasePart): Display
	local gui = Instance.new("BillboardGui")
	gui.Name = "IncubatorInfo"
	-- In studs, so neighbouring bays' tags don't overlap; staggered by column
	local slot = part:GetAttribute("Slot")
	local lift = if typeof(slot) == "number" and slot % 2 == 0 then 1.3 else 0
	gui.Size = UDim2.fromScale(4.2, 1.8)
	gui.StudsOffset = Vector3.new(0, 3.4 + lift, 0)
	gui.MaxDistance = 40
	gui.AlwaysOnTop = false
	gui.Parent = part
	local title = text(gui, 0, 0.27)
	local timer = text(gui, 0.28, 0.38)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromScale(0.1, 0.72)
	bar.Size = UDim2.fromScale(0.8, 0.15)
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	return { part = part, gui = gui, title = title, timer = timer, fill = fill, base = nil }
end

local function isIncubator(instance: Instance): boolean
	return instance:IsA("BasePart") and instance.Name:match("^Incubator%d+$") ~= nil
end

local function update(display: Display, now: number, t: number)
	local part = display.part
	local owned = part:GetAttribute("Owned") == true
	display.gui.Enabled = owned
	if not owned then
		return
	end
	local tierName = part:GetAttribute("TierName")
	local hatchAt = part:GetAttribute("HatchAt")
	local startedAt = part:GetAttribute("StartedAt")
	local hint = part:GetAttribute("HintColor")
	local color = if typeof(hint) == "Color3" then hint else Color3.new(1, 1, 1)
	display.title.Text = if typeof(tierName) == "string" then `{tierName} Incubator` else "Incubator"

	if typeof(hatchAt) == "number" and typeof(startedAt) == "number" then
		local remaining = hatchAt - now
		local progress = math.clamp((now - startedAt) / math.max(hatchAt - startedAt, 1), 0, 1)
		display.timer.Text = if remaining > 0 then Format.duration(remaining) else "Hatching!"
		display.timer.TextColor3 = color
		display.fill.Size = UDim2.fromScale(progress, 1)
		display.fill.BackgroundColor3 = color
		-- Wobble over the last 15%, harder as it gets closer
		if progress > 0.85 then
			display.base = display.base or part.CFrame
			local strength = (progress - 0.85) / 0.15
			-- A gentle rock that quickens near the end, with short rests in between
			local rock = math.sin(t * (4 + strength * 5)) * math.rad(1.5 + strength * 4)
			local rest = if math.sin(t * 0.9) > 0.3 then 1 else 0.25
			part.CFrame = (display.base :: CFrame) * CFrame.Angles(0, 0, rock * rest)
		elseif display.base then
			part.CFrame = display.base
			display.base = nil
		end
	else
		display.timer.Text = "Empty — bring an egg"
		display.timer.TextColor3 = Color3.fromRGB(190, 190, 200)
		display.fill.Size = UDim2.fromScale(0, 1)
		if display.base then
			part.CFrame = display.base
			display.base = nil
		end
	end
end

function IncubatorController.start()
	local function add(instance: Instance)
		if isIncubator(instance) and displays[instance :: BasePart] == nil then
			displays[instance :: BasePart] = build(instance :: BasePart)
		end
	end
	local world = Workspace:WaitForChild("World")
	for _, descendant in world:GetDescendants() do
		add(descendant)
	end
	world.DescendantAdded:Connect(add)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local t = os.clock()
		for part, display in displays do
			if part.Parent == nil then
				displays[part] = nil
			else
				update(display, now, t)
			end
		end
	end)
end

return IncubatorController

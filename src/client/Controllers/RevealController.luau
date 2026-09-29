--!strict
-- The two "wow" moments (client, presentation only; the server already decided):
--  * Luck Wheel: a spinning wheel of luck multipliers that lands on the server's
--    segment, then says whether the egg was upgraded.
--  * Hatch reveal: a case-opening reel of creature cards from that egg's odds that
--    slows down and lands on what actually hatched, then a big rarity-colored
--    reveal with the creature spinning in a viewport. Mythic and rarer flash the
--    whole screen.
-- Events are queued so back-to-back hatches play one after another.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local TICK_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local CARD_W, CARD_H, CARD_GAP = 118, 150, 10
local REEL_CARDS = 44
local WINNER_INDEX = 38
local REEL_SECONDS = 4.6
local WHEEL_SECONDS = 4.2

local gui: ScreenGui
local queue: { () -> () } = {}
local busy = false

local RevealController = {}

local function play(soundId: string, volume: number, pitch: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function enqueue(job: () -> ())
	table.insert(queue, job)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			local next = table.remove(queue, 1) :: () -> ()
			next()
		end
		busy = false
	end)
end

local function flash(color: Color3, strength: number)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - strength
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = gui
	local tween = TweenService:Create(frame, TweenInfo.new(1.2), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		frame:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Luck Wheel
---------------------------------------------------------------------------

local function playWheel(segmentIndex: number, rarityAfter: string)
	local segments = Config.Economy.tunables.luckWheel
	local count = #segments
	local slice = 360 / count

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.ZIndex = 10
	overlay.Parent = gui

	local size = 340
	local wheel = Instance.new("Frame")
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.47)
	wheel.Size = UDim2.fromOffset(size, size)
	wheel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	wheel.ZIndex = 11
	wheel.Parent = overlay
	corner(wheel, size)
	local ring = Instance.new("UIStroke")
	ring.Thickness = 6
	ring.Color = Color3.fromRGB(255, 215, 90)
	ring.Parent = wheel

	-- Each segment is a colored petal from the hub to the rim, with its label
	for i, segment in segments do
		local angle = (i - 1) * slice + slice / 2
		local petal = Instance.new("Frame")
		petal.AnchorPoint = Vector2.new(0.5, 1)
		petal.Position = UDim2.fromScale(0.5, 0.5)
		petal.Size = UDim2.fromOffset(math.floor(size * math.pi / count * 0.9), size / 2 - 6)
		petal.BackgroundColor3 = segment.color
		petal.BorderSizePixel = 0
		petal.Rotation = angle
		petal.ZIndex = 12
		petal.Parent = wheel
		corner(petal, 16)
		label(petal, {
			Size = UDim2.new(1, -8, 0, 34),
			Position = UDim2.fromOffset(4, 8),
			Text = segment.label,
			TextColor3 = if segment.luck >= 25 then Color3.fromRGB(40, 30, 10) else Color3.new(1, 1, 1),
			ZIndex = 13,
		})
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(70, 70)
	hub.BackgroundColor3 = Color3.fromRGB(255, 215, 90)
	hub.ZIndex = 14
	hub.Parent = wheel
	corner(hub, 70)
	label(hub, {
		Size = UDim2.fromScale(0.8, 0.5),
		Position = UDim2.fromScale(0.1, 0.25),
		Text = "LUCK",
		TextColor3 = Color3.fromRGB(60, 40, 0),
		ZIndex = 15,
	})

	local pointer = label(overlay, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.47, -size / 2 + 14),
		Size = UDim2.fromOffset(44, 44),
		Text = "▼",
		TextColor3 = Color3.fromRGB(255, 80, 80),
		ZIndex = 20,
	})
	local result = label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.47, size / 2 + 16),
		Size = UDim2.fromOffset(520, 44),
		Text = "",
		ZIndex = 20,
	})
	-- Odds shown under the wheel: every segment's real chance
	local total = 0
	for _, segment in segments do
		total += segment.weight
	end
	local odds = {}
	for _, segment in segments do
		table.insert(odds, `{segment.label} {math.floor(segment.weight / total * 1000 + 0.5) / 10}%`)
	end
	label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.47, size / 2 + 64),
		Size = UDim2.fromOffset(620, 20),
		Font = Enum.Font.Gotham,
		Text = table.concat(odds, "  ·  "),
		TextColor3 = Color3.fromRGB(200, 200, 210),
		ZIndex = 20,
	})

	-- Land the chosen segment under the pointer (top), with a little jitter
	local center = (segmentIndex - 1) * slice + slice / 2
	local jitter = (math.random() - 0.5) * slice * 0.6
	local final = 360 * 6 - center + jitter
	local tween = TweenService:Create(
		wheel,
		TweenInfo.new(WHEEL_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Rotation = final }
	)
	local lastSlice = 0
	local tickConnection = RunService.RenderStepped:Connect(function()
		local current = math.floor(wheel.Rotation / slice)
		if current ~= lastSlice then
			lastSlice = current
			play(TICK_SOUND, 0.25, 1.6)
			pointer.Rotation = -12
			task.delay(0.05, function()
				pointer.Rotation = 0
			end)
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	tickConnection:Disconnect()

	local segment = segments[segmentIndex]
	if rarityAfter ~= "" then
		local rarity = Config.Rarities[rarityAfter :: Config.RarityId]
		result.Text = `{segment.label} luck — upgraded to {rarityAfter:upper()}!`
		result.TextColor3 = rarity.color
		flash(rarity.color, 0.5)
		play(TICK_SOUND, 0.8, 0.8)
	else
		result.Text = `{segment.label} luck — no upgrade this time`
		result.TextColor3 = Color3.fromRGB(220, 220, 230)
	end
	task.wait(2.6)
	overlay:Destroy()
end

---------------------------------------------------------------------------
-- Hatch reveal
---------------------------------------------------------------------------

local function pickWeighted(odds: { { id: string, chance: number } }): string
	local roll = math.random()
	for _, entry in odds do
		roll -= entry.chance
		if roll <= 0 then
			return entry.id
		end
	end
	return odds[#odds].id
end

local function card(parent: Instance, speciesId: string, x: number): Frame
	local creature = Config.CreaturesById[speciesId]
	local rarity = Config.Rarities[creature.rarity]
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(x, 0)
	frame.Size = UDim2.fromOffset(CARD_W, CARD_H)
	frame.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
	frame.ZIndex = 12
	frame.Parent = parent
	corner(frame, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.color
	stroke.Thickness = 3
	stroke.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(30, 32, 42), rarity.color)
	gradient.Rotation = 90
	gradient.Parent = frame
	label(frame, {
		Size = UDim2.new(1, -10, 0, 60),
		Position = UDim2.fromOffset(5, 26),
		Text = "🥚",
		ZIndex = 13,
	})
	label(frame, {
		Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.new(0, 5, 1, -54),
		Text = creature.displayName,
		ZIndex = 13,
	})
	label(frame, {
		Size = UDim2.new(1, -10, 0, 18),
		Position = UDim2.new(0, 5, 1, -28),
		Text = creature.rarity,
		TextColor3 = rarity.color,
		ZIndex = 13,
	})
	return frame
end

local function viewport(parent: Instance, speciesId: string): ViewportFrame?
	local templates = ReplicatedStorage:FindFirstChild("CreatureModels")
	local template = templates
		and (templates:FindFirstChild(`{speciesId}_Baby`) or templates:FindFirstChild(speciesId))
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(260, 220)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.36)
	frame.ZIndex = 21
	frame.Parent = parent
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = frame
	local _, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	local distance = math.max(size.X, size.Y, size.Z) * 1.6
	camera.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.25, -distance), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera
	task.spawn(function()
		local angle = 0
		while frame.Parent do
			angle += 0.03
			model:PivotTo(CFrame.Angles(0, angle, 0))
			task.wait()
		end
	end)
	return frame
end

local function playReveal(reveal: { [string]: any })
	local speciesId: string = reveal.species
	local creature = Config.CreaturesById[speciesId]
	if creature == nil then
		return
	end
	local rarity = Config.Rarities[creature.rarity]
	local odds = Config.Eggs.speciesOdds(reveal.biome, true)

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex = 10
	overlay.Parent = gui

	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0.9, 0, 0, CARD_H + 24)
	window.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
	window.ClipsDescendants = true
	window.ZIndex = 11
	window.Parent = overlay
	corner(window, 12)

	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(0, 12)
	strip.Size = UDim2.fromOffset(REEL_CARDS * (CARD_W + CARD_GAP), CARD_H)
	strip.ZIndex = 11
	strip.Parent = window

	-- Fill the reel from the egg's odds; tease rare cards right around the winner
	local rareTease: string? = nil
	for _, entry in odds do
		local order = Config.Rarities[Config.CreaturesById[entry.id].rarity].order
		if order >= 5 and entry.id ~= speciesId then
			rareTease = entry.id
		end
	end
	for i = 1, REEL_CARDS do
		local id = if i == WINNER_INDEX
			then speciesId
			elseif (i == WINNER_INDEX - 1 or i == WINNER_INDEX + 1) and rareTease then rareTease
			else pickWeighted(odds)
		card(strip, id, (i - 1) * (CARD_W + CARD_GAP))
	end
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.fromScale(0.5, 0)
	marker.Size = UDim2.new(0, 4, 1, 0)
	marker.BackgroundColor3 = Color3.fromRGB(255, 215, 90)
	marker.BorderSizePixel = 0
	marker.ZIndex = 16
	marker.Parent = window

	-- Scroll so the winner card ends centered under the marker (slightly off-center)
	local windowWidth = window.AbsoluteSize.X
	local winnerCenter = (WINNER_INDEX - 1) * (CARD_W + CARD_GAP) + CARD_W / 2
	local offset = (math.random() - 0.5) * CARD_W * 0.6
	local finalX = windowWidth / 2 - winnerCenter + offset
	strip.Position = UDim2.fromOffset(windowWidth / 2 - CARD_W * 2, 12)
	local tween = TweenService:Create(
		strip,
		TweenInfo.new(REEL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 12) }
	)
	local lastCard = 0
	local tickConnection = RunService.RenderStepped:Connect(function()
		local passed = math.floor((windowWidth / 2 - strip.Position.X.Offset) / (CARD_W + CARD_GAP))
		if passed ~= lastCard then
			lastCard = passed
			play(TICK_SOUND, 0.2, 1.8)
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	tickConnection:Disconnect()
	task.wait(0.35)

	-- The reveal
	window.Visible = false
	local ultra = rarity.order >= 6
	flash(rarity.color, if ultra then 0.85 else 0.45)
	local finish: string? = nil
	for _, entry in Config.Finishes do
		if entry.id == reveal.finish and entry.id ~= "Normal" then
			finish = entry.displayName
		end
	end
	local title = label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(700, 70),
		Text = `{creature.rarity:upper()}!`,
		TextColor3 = rarity.color,
		ZIndex = 21,
	})
	label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.69),
		Size = UDim2.fromOffset(700, 44),
		Text = table.concat({
			if finish then `{finish} ` else "",
			if reveal.mutation then `{reveal.mutation} ` else "",
			creature.displayName,
		}),
		ZIndex = 21,
	})
	label(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromOffset(700, 24),
		Font = Enum.Font.Gotham,
		Text = creature.gag,
		TextColor3 = Color3.fromRGB(210, 210, 220),
		ZIndex = 21,
	})
	viewport(overlay, speciesId)
	title.Size = UDim2.fromOffset(200, 20)
	TweenService:Create(
		title,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(700, 70) }
	):Play()
	play(TICK_SOUND, 0.9, if ultra then 0.5 else 0.8)
	if ultra then
		task.delay(0.4, function()
			flash(Color3.new(1, 1, 1), 0.6)
		end)
	end
	task.wait(if ultra then 5 else 3.2)
	overlay:Destroy()
end

function RevealController.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Reveals"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local wheelRemote = remotes:WaitForChild("WheelResult") :: RemoteEvent
	local revealRemote = remotes:WaitForChild("HatchReveal") :: RemoteEvent
	wheelRemote.OnClientEvent:Connect(function(segmentIndex: number, _before: string, rarityAfter: string)
		enqueue(function()
			playWheel(segmentIndex, rarityAfter)
		end)
	end)
	revealRemote.OnClientEvent:Connect(function(reveal: { [string]: any })
		enqueue(function()
			playReveal(reveal)
		end)
	end)
end

return RevealController

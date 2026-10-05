--!strict
-- The hatch "wow" moment (client, presentation only; the server already decided).
-- (The Luck Wheel is a physical wheel in the world: LuckWheelController.)
--  * A case-opening reel of creature cards from that egg's odds slows down and
--    lands on what actually hatched, then a rarity-colored reveal with the creature
--    spinning in a viewport.
--  * Every rarity has its own sound (owner, 2026-10-05: "different sounds for
--    different rarities drawn"), from Config.Sounds through Sfx; each card ticks as
--    it passes the marker, brighter for rarer cards.
--  * Legendary and up get "a more involved sequence" (same day): a longer reel that
--    creeps past the last cards under a rising build, the screen darkening and the
--    marker glowing, a heartbeat pause on the winning card, then an impact with a
--    shake, light rays, a slammed-in title and confetti. Mythic and up add color
--    pulses, a second burst and the odds of what you pulled. Junk is a boing.
--  * Tap, click, or A/B on a controller skips a normal reel and closes any reveal
--    once it has been seen (a Legendary+ reel always plays out).
-- RevealTiming holds the timings; the server times the world's light pillar and
-- the server-wide news to them. Events are queued so back-to-back hatches play in turn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local MutationLooks = require(ReplicatedStorage.Shared.MutationLooks)
local RevealTiming = require(ReplicatedStorage.Shared.RevealTiming)
local CreatureViewport = require(script.Parent.Parent.CreatureViewport)
local Genetics = require(ReplicatedStorage.Shared.Genetics)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Parent.Ui)
local OddsController = require(script.Parent.OddsController)

local CARD_W, CARD_H, CARD_GAP = 118, 150, 10
local REEL_CARDS = 44
local WINNER_INDEX = 38
local SKIP_SECONDS = 0.3 -- a skipped reel still slides into place this fast
local TICK_GAP = 0.03
local GOLD = Color3.fromRGB(255, 215, 90)

-- How long each tier's result stays up, and how soon it can be closed
local HOLD_SECONDS = { normal = 3.2, junk = 3.2, big = 6, ultra = 7.5 }
local MIN_SECONDS = { normal = 0.8, junk = 0.8, big = 2.6, ultra = 3.2 }

local gui: ScreenGui
local queue: { () -> () } = {}
local busy = false

local RevealController = {}

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
		-- The egg odds panel steps aside while reveals play. A failed reveal mustn't
		-- leave it hidden (eggs show their odds before buying) or stall the queue.
		OddsController.setRevealing(true)
		while #queue > 0 do
			local next = table.remove(queue, 1) :: () -> ()
			local ok, problem = pcall(function(): any
				next()
				return nil
			end)
			if not ok then
				warn(`[RevealController] reveal failed: {problem}`)
				for _, child in gui:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy() -- its half-built overlay
					end
				end
			end
		end
		OddsController.setRevealing(false)
		busy = false
	end)
end

local function flash(parent: Instance, color: Color3, strength: number, seconds: number?)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - strength
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = parent
	local tween = TweenService:Create(frame, TweenInfo.new(seconds or 1.2), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		frame:Destroy()
	end)
end

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

local function rarityOrder(speciesId: string): number
	local creature = Config.CreaturesById[speciesId]
	local rarity = if creature then Config.Rarities[creature.rarity] else nil
	return if rarity then rarity.order else 1
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

-- Light rays behind the creature (frames, no images): bars through the center,
-- each fading out toward both ends. A GuiObject turns about its own center and its
-- children don't follow, so `spin` turns every bar.
local function rays(parent: Instance, color: Color3, count: number): (Frame, (number) -> ())
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.33)
	hub.Size = UDim2.fromOffset(0, 0)
	hub.BackgroundTransparency = 1
	hub.ZIndex = 14
	hub.Parent = parent
	local bars: { Frame } = {}
	for i = 1, count // 2 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(if i % 2 == 0 then 70 else 44, 1800)
		bar.BackgroundColor3 = if i % 2 == 0 then color else Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.ZIndex = 14
		bar.Parent = hub
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = bar
		table.insert(bars, bar)
	end
	local turned = 0
	local function spin(degrees: number)
		turned += degrees
		for i, bar in bars do
			bar.Rotation = turned + (i - 1) * 360 / count
		end
	end
	spin(0)
	return hub, spin
end

-- A soft glow (stacked rings standing in for a radial gradient).
local function glow(parent: Instance, color: Color3)
	for i, transparency in { 0.93, 0.88, 0.82, 0.76 } do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.33)
		ring.Size = UDim2.fromOffset(560 - i * 90, 560 - i * 90)
		ring.BackgroundColor3 = color
		ring.BackgroundTransparency = transparency
		ring.BorderSizePixel = 0
		ring.ZIndex = 15
		ring.Parent = parent
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = ring
	end
end

-- Confetti flying out from the creature and falling, for `seconds`.
local function confetti(parent: Instance, colors: { Color3 }, count: number, seconds: number)
	local pieces = {}
	for i = 1, count do
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.36)
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(5, 9))
		piece.BackgroundColor3 = colors[(i - 1) % #colors + 1]
		piece.BorderSizePixel = 0
		piece.ZIndex = 40
		piece.Parent = parent
		local angle = math.random() * math.pi * 2
		local speed = 380 + math.random() * 520
		table.insert(pieces, {
			frame = piece,
			x = 0,
			y = 0,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed - 260,
			spin = (math.random() - 0.5) * 900,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local age = os.clock() - started
		if age > seconds or parent.Parent == nil then
			connection:Disconnect()
			for _, p in pieces do
				p.frame:Destroy()
			end
			return
		end
		for _, p in pieces do
			p.vy += 900 * dt
			p.vx *= 1 - 1.2 * dt
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.frame.Position = UDim2.new(0.5, p.x, 0.36, p.y)
			p.frame.Rotation += p.spin * dt
			p.frame.BackgroundTransparency = math.clamp((age - seconds * 0.6) / (seconds * 0.4), 0, 1)
		end
	end)
end

-- Shakes a frame around where it sits, fading out over `seconds`.
local function shake(target: GuiObject, strength: number, seconds: number)
	local home = target.Position
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local age = os.clock() - started
		if age >= seconds or target.Parent == nil then
			connection:Disconnect()
			target.Position = home
			return
		end
		local power = strength * (1 - age / seconds) ^ 2
		target.Position = home
			+ UDim2.fromOffset((math.random() - 0.5) * 2 * power, (math.random() - 0.5) * 2 * power)
	end)
end

local function pop(target: Instance, from: number, seconds: number)
	local scale = Instance.new("UIScale")
	scale.Scale = from
	scale.Parent = target
	TweenService
		:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- The chance of this species from this egg, as "1 in N" (for the ultra reveal).
local function oddsText(odds: { { id: string, chance: number } }, speciesId: string): string?
	for _, entry in odds do
		if entry.id == speciesId and entry.chance > 0 then
			return `1 in {Format.count(math.floor(1 / entry.chance + 0.5))}`
		end
	end
	return nil
end

local function playReveal(reveal: { [string]: any })
	local speciesId: string = reveal.species
	local creature = Config.CreaturesById[speciesId]
	if creature == nil then
		return
	end
	local rarity = Config.Rarities[creature.rarity]
	local tier = RevealTiming.tier(creature.rarity)
	local big = tier == "big" or tier == "ultra"
	local ultra = tier == "ultra"
	local odds = Config.Eggs.speciesOdds(reveal.biome, true)
	local finishId: string = if typeof(reveal.finish) == "string" then reveal.finish else "Normal"
	local mutationId: string? = if typeof(reveal.mutation) == "string" then reveal.mutation else nil

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex = 10
	overlay.Parent = gui
	-- Everything that shakes on the impact lives in `stage`
	local stage = Instance.new("Frame")
	stage.Size = UDim2.fromScale(1, 1)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 10
	stage.Parent = overlay

	-- Tap / click / A / B: skip a normal reel, or close a reveal that's been seen
	local skipRequested = false
	local catcher = Instance.new("TextButton")
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.ZIndex = 60
	catcher.Parent = overlay
	catcher.Activated:Connect(function()
		skipRequested = true
	end)
	local inputConnection = UserInputService.InputBegan:Connect(function(input)
		local key = input.KeyCode
		if
			key == Enum.KeyCode.ButtonA
			or key == Enum.KeyCode.ButtonB
			or key == Enum.KeyCode.Return
			or key == Enum.KeyCode.Space
		then
			skipRequested = true
		end
	end)
	overlay.Destroying:Once(function()
		inputConnection:Disconnect()
	end)

	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0.9, 0, 0, CARD_H + 24)
	window.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
	window.ClipsDescendants = true
	window.ZIndex = 11
	window.Parent = stage
	corner(window, 12)
	-- The creature, drawn small behind the reel, so its meshes, textures and skin have
	-- downloaded by the reveal. A model's assets only load once something draws it
	-- (a hidden viewport draws nothing, and PreloadAsync skips SurfaceAppearances):
	-- a species' first reveal showed it late and then white (PC, 2026-10-05).
	local warmUp = Instance.new("Frame")
	warmUp.AnchorPoint = Vector2.new(0.5, 0.5)
	warmUp.Position = UDim2.fromScale(0.5, 0.5)
	warmUp.Size = UDim2.fromOffset(120, 120)
	warmUp.BackgroundTransparency = 1
	warmUp.ZIndex = 10
	warmUp.Parent = stage
	CreatureViewport.create(warmUp, speciesId, "Baby", finishId, mutationId, {
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(1, 1),
		zIndex = 1,
	})
	local windowStroke = Instance.new("UIStroke")
	windowStroke.Color = GOLD
	windowStroke.Thickness = 0
	windowStroke.Parent = window

	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(0, 12)
	strip.Size = UDim2.fromOffset(REEL_CARDS * (CARD_W + CARD_GAP), CARD_H)
	strip.ZIndex = 11
	strip.Parent = window

	-- Fill the reel from the egg's odds; tease rare cards right around the winner
	local rareTease: string? = nil
	for _, entry in odds do
		if rarityOrder(entry.id) >= 5 and entry.id ~= speciesId then
			rareTease = entry.id
		end
	end
	local cardIds: { string } = {}
	local winnerCard: Frame? = nil
	for i = 1, REEL_CARDS do
		local id = if i == WINNER_INDEX
			then speciesId
			elseif (i == WINNER_INDEX - 1 or i == WINNER_INDEX + 1) and rareTease then rareTease
			else pickWeighted(odds)
		cardIds[i] = id
		local made = card(strip, id, (i - 1) * (CARD_W + CARD_GAP))
		if i == WINNER_INDEX then
			winnerCard = made
		end
	end
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.fromScale(0.5, 0)
	marker.Size = UDim2.new(0, 4, 1, 0)
	marker.BackgroundColor3 = GOLD
	marker.BorderSizePixel = 0
	marker.ZIndex = 16
	marker.Parent = window

	-- Layout math in the gui's own units: AbsoluteSize is in screen pixels, which
	-- differ from offsets once Ui.autoScale shrinks the gui (phones). Using screen
	-- pixels here stopped the reel a card off the marker on small screens.
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	local scale = if uiScale then uiScale.Scale else 1
	local windowWidth = window.AbsoluteSize.X / scale
	local pitch = CARD_W + CARD_GAP
	local winnerCenter = (WINNER_INDEX - 1) * pitch + CARD_W / 2
	local offset = (math.random() - 0.5) * CARD_W * 0.6
	local startX = windowWidth / 2 - CARD_W * 2
	local finalX = windowWidth / 2 - winnerCenter + offset
	strip.Position = UDim2.fromOffset(startX, 12)

	-- The reel: a fast start; a Legendary+ reel creeps over its last two cards
	local duration = if big then RevealTiming.BIG_REEL_SECONDS else RevealTiming.REEL_SECONDS
	local function ease(t: number): number
		local rest = 1 - t
		if big then
			return 1 - (0.65 * rest ^ 5 + 0.35 * rest ^ 2.2)
		end
		return 1 - rest ^ 5
	end
	Sfx.play("Whoosh", { volume = 0.5 })
	local t = 0
	local speed = 1 / duration
	local lastCard = -1
	local lastTick = 0
	local building = false
	skipRequested = false
	while t < 1 do
		local dt = RunService.RenderStepped:Wait()
		if skipRequested and not big and speed < (1 - t) / SKIP_SECONDS then
			speed = (1 - t) / SKIP_SECONDS
		end
		t = math.min(1, t + dt * speed)
		local x = startX + (finalX - startX) * ease(t)
		strip.Position = UDim2.fromOffset(x, 12)
		local under = math.floor((windowWidth / 2 - x) / pitch) + 1
		if under ~= lastCard then
			lastCard = under
			local now = os.clock()
			if now - lastTick >= TICK_GAP then
				lastTick = now
				local order = if cardIds[under] then rarityOrder(cardIds[under]) else 1
				Sfx.play("Tick", { volume = 0.35, pitch = 0.95 + 0.07 * order + math.random() * 0.04 })
			end
		end
		if big and not building and (1 - t) * duration <= Sfx.length("Riser") + 0.05 then
			-- The build: darker screen, a glowing marker and frame, the riser
			building = true
			Sfx.play("Riser", { volume = 0.75 })
			local remaining = (1 - t) * duration
			local info = TweenInfo.new(remaining, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(overlay, info, { BackgroundTransparency = 0.12 }):Play()
			TweenService
				:Create(
					marker,
					info,
					{ Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1) }
				)
				:Play()
			TweenService:Create(windowStroke, info, { Thickness = 4 }):Play()
		end
	end

	if big and winnerCard then
		-- The pause: a spotlight on the winning card, beating with the heartbeat
		local winnerLeft = finalX + (WINNER_INDEX - 1) * pitch
		for _, side in { "left", "right" } do
			local cover = Instance.new("Frame")
			cover.BackgroundColor3 = Color3.new(0, 0, 0)
			cover.BackgroundTransparency = 1
			cover.BorderSizePixel = 0
			cover.ZIndex = 15
			if side == "left" then
				cover.Size = UDim2.new(0, math.max(0, winnerLeft - 4), 1, 0)
			else
				cover.Position = UDim2.new(0, winnerLeft + CARD_W + 4, 0, 0)
				cover.Size = UDim2.new(1, 0, 1, 0)
			end
			cover.Parent = window
			TweenService:Create(cover, TweenInfo.new(0.3), { BackgroundTransparency = 0.25 }):Play()
		end
		local beat = Instance.new("UIScale")
		beat.Parent = winnerCard
		Sfx.play("Heartbeat", { volume = 0.9 })
		for _, at in { 0, 0.7 } do
			task.delay(at, function()
				local grow =
					TweenService:Create(beat, TweenInfo.new(0.09, Enum.EasingStyle.Quad), { Scale = 1.12 })
				grow:Play()
				grow.Completed:Once(function()
					TweenService:Create(beat, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Scale = 1.04 })
						:Play()
				end)
			end)
		end
		task.wait(RevealTiming.SUSPENSE_SECONDS)
	else
		task.wait(RevealTiming.SETTLE_SECONDS)
	end

	-- The reveal
	warmUp:Destroy()
	window.Visible = false
	skipRequested = false
	local shown = os.clock()
	if big then
		overlay.BackgroundTransparency = 0.15
		Sfx.play("Impact", { volume = 1 })
		Sfx.play(creature.rarity, { volume = 0.95 })
		flash(overlay, Color3.new(1, 1, 1), 0.9, 0.5)
		task.delay(0.12, function()
			flash(overlay, rarity.color, 0.6, 1.4)
		end)
		shake(stage, if ultra then 22 else 14, 0.55)
		local spokes, turn = rays(stage, rarity.color, if ultra then 16 else 12)
		glow(stage, rarity.color)
		local spin = RunService.RenderStepped:Connect(function(dt: number)
			turn(dt * (if ultra then 16 else 10))
		end)
		overlay.Destroying:Once(function()
			spin:Disconnect()
		end)
		pop(spokes, 0.2, 0.6)
		confetti(stage, { rarity.color, GOLD, Color3.new(1, 1, 1) }, if ultra then 80 else 55, 2.8)
		if ultra then
			for i, at in { 0.9, 1.8 } do
				task.delay(at, function()
					if overlay.Parent then
						flash(overlay, rarity.color, 0.45, 0.8)
						if i == 1 then
							confetti(stage, { rarity.color, Color3.new(1, 1, 1) }, 50, 2.4)
						end
					end
				end)
			end
		end
	elseif tier == "junk" then
		Sfx.play("Junk", { volume = 0.9 })
		flash(overlay, rarity.color, 0.35)
	else
		Sfx.play(creature.rarity, { volume = 0.85 })
		flash(overlay, rarity.color, 0.45)
	end
	if finishId ~= "Normal" then
		task.delay(if big then 0.9 else 0.35, function()
			Sfx.play("Shine", { volume = 0.6 })
		end)
	end

	local finish: string? = nil
	for _, entry in Config.Finishes do
		if entry.id == finishId and entry.id ~= "Normal" then
			finish = entry.displayName
		end
	end
	local title = label(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(700, if big then 84 else 70),
		Text = `{creature.rarity:upper()}!`,
		TextColor3 = rarity.color,
		ZIndex = 21,
	})
	label(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.69),
		Size = UDim2.fromOffset(700, 44),
		RichText = true,
		Text = table.concat({
			if mutationId and Config.MutationsById[mutationId]
				then MutationLooks.richName(mutationId, Config.MutationsById[mutationId].displayName) .. " "
				else "",
			if finish then `{finish} ` else "",
			creature.displayName,
		}),
		ZIndex = 21,
	})
	label(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromOffset(700, 24),
		Font = Enum.Font.Gotham,
		Text = creature.gag,
		TextColor3 = Color3.fromRGB(210, 210, 220),
		ZIndex = 21,
	})
	-- What it was born with, always spelled out (owner, 2026-10-03), with what each pays
	label(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.81),
		Size = UDim2.fromOffset(700, 28),
		RichText = true,
		Text = Genetics.summary(finishId, mutationId),
		ZIndex = 21,
	})
	local viewport = CreatureViewport.create(
		stage,
		speciesId,
		"Baby",
		finishId,
		mutationId,
		-- Height follows the screen so it stays clear of the title (at 60%) on short screens
		{
			position = UDim2.fromScale(0.5, 0.32),
			size = UDim2.new(0, 360, 0.38, 0),
			maxSize = Vector2.new(360, 300),
		}
	)
	if viewport then
		pop(viewport, if big then 0.1 else 0.6, if big then 0.55 else 0.35)
	end
	if ultra then
		-- The flex: how rare that was, from this egg
		local chance = oddsText(odds, speciesId)
		if chance then
			local line = label(stage, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.875),
				Size = UDim2.fromOffset(700, 30),
				Text = `🍀 {chance} from this egg`,
				TextColor3 = GOLD,
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				ZIndex = 21,
			})
			task.delay(1.1, function()
				TweenService
					:Create(line, TweenInfo.new(0.4), { TextTransparency = 0, TextStrokeTransparency = 0.2 })
					:Play()
			end)
		end
	end

	local mutationEntry = if mutationId then Config.MutationsById[mutationId] else nil
	local mutationLook = MutationLooks.get(mutationId)
	if mutationEntry and mutationLook then
		-- The rarest roll in the game gets its own moment: a banner in its accent
		-- color with the odds, a second flash and its own sound
		local banner = label(stage, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.535),
			Size = UDim2.fromOffset(700, 30),
			Text = `🧬 {mutationEntry.displayName:upper()} MUTATION · 1 in {Format.count(
				1 / mutationEntry.chance
			)}`,
			TextColor3 = mutationLook.accent,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			ZIndex = 21,
		})
		task.delay(if big then 1.5 else 0.7, function()
			if overlay.Parent == nil then
				return
			end
			flash(overlay, mutationLook.accent, 0.55)
			Sfx.play("Mutation", { volume = 0.9 })
			TweenService
				:Create(banner, TweenInfo.new(0.35), { TextTransparency = 0, TextStrokeTransparency = 0.2 })
				:Play()
		end)
	end

	-- The title: slammed in for Legendary+, a wobble for Junk, a pop otherwise
	if big then
		pop(title, 3, 0.4)
		-- A gradient can only darken text, so the text goes white and the gradient
		-- carries the rarity color with a white band sweeping across
		title.TextColor3 = Color3.new(1, 1, 1)
		local shine = Instance.new("UIGradient")
		shine.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rarity.color),
			ColorSequenceKeypoint.new(0.4, rarity.color),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.6, rarity.color),
			ColorSequenceKeypoint.new(1, rarity.color),
		})
		shine.Offset = Vector2.new(-1, 0)
		shine.Parent = title
		TweenService:Create(
			shine,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.5),
			{ Offset = Vector2.new(1, 0) }
		):Play()
	elseif tier == "junk" then
		pop(title, 0.3, 0.45)
		title.Rotation = -10
		TweenService:Create(
			title,
			TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true),
			{ Rotation = 10 }
		):Play()
		task.delay(1.9, function()
			title.Rotation = 0
		end)
	else
		pop(title, 0.3, 0.5)
	end

	-- Hold, then close: early once it's been seen, if the player taps
	local hold = HOLD_SECONDS[tier] + (if mutationEntry then 1.8 else 0)
	local minimum = MIN_SECONDS[tier] + (if mutationEntry then 1 else 0)
	local hint: TextLabel? = nil
	while os.clock() - shown < hold do
		local age = os.clock() - shown
		if age >= minimum then
			if hint == nil then
				hint = label(overlay, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -18),
					Size = UDim2.fromOffset(420, 22),
					Font = Enum.Font.GothamBold,
					Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
						then "Press A to continue"
						elseif Ui.isTouch() then "Tap to continue"
						else "Click to continue",
					TextColor3 = Color3.fromRGB(200, 200, 210),
					ZIndex = 61,
				})
			end
			if skipRequested then
				break
			end
		else
			skipRequested = false
		end
		RunService.RenderStepped:Wait()
	end
	overlay:Destroy()
end

function RevealController.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Reveals"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Ui.autoScale(gui)
	Sfx.preload()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local revealRemote = remotes:WaitForChild("HatchReveal") :: RemoteEvent
	revealRemote.OnClientEvent:Connect(function(reveal: { [string]: any })
		enqueue(function()
			playReveal(reveal)
		end)
	end)
end

return RevealController

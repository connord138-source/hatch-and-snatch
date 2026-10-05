--!strict
-- Sprinting (owner, 2026-10-05: "also need to turn on sprinting ability"). Hold
-- Left Shift; on a controller click the left stick, on a touch screen tap Run (both
-- toggle, and switch off when you stop for a moment). The camera widens a little
-- while you run.
--
-- Client-side, like the character's own movement: the server never sees the faster
-- speed, so its steal and carry checks keep using the normal one. Sprint only ever
-- swaps the normal speed for the sprint speed and back. Whenever the server has set
-- anything else (a carried creature's pace, a net, a tripwire) it leaves it alone,
-- and it never runs while you carry a creature (the server would see a thief
-- outrunning the carry speed and drop it).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SPRINT_MULTIPLIER = 1.6
local FOV_BOOST = 7
local STOP_SECONDS = 0.8 -- a toggled sprint switches off after standing still this long

local player = Players.LocalPlayer
local held = false -- Left Shift down
local toggled = false -- controller / touch toggle
local walkSpeed = 16 -- the character's normal speed, read when it spawns
local humanoid: Humanoid? = nil
local stillFor = 0
local baseFov: number? = nil

local SprintController = {}

local function sprintSpeed(): number
	return math.floor(walkSpeed * SPRINT_MULTIPLIER + 0.5)
end

local function onCharacter(character: Model)
	toggled = false
	local found = character:WaitForChild("Humanoid", 10)
	if found and found:IsA("Humanoid") then
		humanoid = found
		-- The normal speed as the game set it, before anything changed it
		walkSpeed = if found.WalkSpeed > 0 then found.WalkSpeed else 16
	end
end

local function step(dt: number)
	local h = humanoid
	if h == nil or h.Parent == nil then
		return
	end
	local moving = h.MoveDirection.Magnitude > 0.05
	if toggled then
		stillFor = if moving then 0 else stillFor + dt
		if stillFor >= STOP_SECONDS then
			toggled = false
		end
	end
	local carrying = player:GetAttribute("Carrying") == true
	local want = (held or toggled) and not carrying
	local fast = sprintSpeed()
	if want and h.WalkSpeed == walkSpeed then
		h.WalkSpeed = fast
	elseif not want and h.WalkSpeed == fast then
		h.WalkSpeed = walkSpeed
	end

	-- A little wider view while actually running
	local camera = Workspace.CurrentCamera
	if camera then
		local running = h.WalkSpeed == fast and moving
		if baseFov == nil then
			baseFov = camera.FieldOfView
		end
		local base = baseFov :: number
		local target = if running then base + FOV_BOOST else base
		local current = camera.FieldOfView
		if math.abs(current - target) > 0.05 then
			camera.FieldOfView = current + (target - current) * math.min(1, dt * 8)
		end
	end
end

function SprintController.start()
	ContextActionService:BindActionAtPriority(
		"Sprint",
		function(_, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				held = true
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				held = false
			end
			-- Sunk so Left Shift doesn't also flip Shift Lock (Right Shift still does)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftShift
	)
	ContextActionService:BindAction("SprintToggle", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			toggled = not toggled
			stillFor = 0
		end
	end, true, Enum.KeyCode.ButtonL3)
	-- The touch button sits in Roblox's ring around the jump button
	ContextActionService:SetTitle("SprintToggle", "Run")

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.RenderStepped:Connect(step)
end

return SprintController

--!strict
-- Shows each ProximityPrompt only to the players it is meant for, locally:
--   VisibleTo = "owner"  -> only the owner (Steal targets' owners, lock button, nursery, take back)
--   VisibleTo = "others" -> everyone except the owner (Steal)
--   Protected = true     -> hidden from everyone (creature is in a nursery)
--   Active = false       -> hidden: the server switches situational prompts (buy the
--                           next incubator, place an egg, spin...) on and off with this.
--                           It can't use Enabled, because this filter sets Enabled.
-- Steal prompts also hide while you're already carrying a creature (the server
-- sets a "Carrying" attribute on your Player). The owner is the nearest ancestor
-- with an OwnerUserId attribute. This is cosmetic only: the server re-validates
-- every trigger.
--
-- It also gives each prompt a controller button matching its key (Xbox players):
-- every prompt defaults to X, and only one prompt per button shows at a time, so
-- a pedestal creature's Walk (R) and Nursery (F) hid behind each other on a pad.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local localUserId = localPlayer.UserId
local prompts: { [ProximityPrompt]: boolean } = {}

-- Keyboard key -> controller button (E stays on the default X)
local GAMEPAD_KEYS: { [Enum.KeyCode]: Enum.KeyCode } = {
	[Enum.KeyCode.E] = Enum.KeyCode.ButtonX,
	[Enum.KeyCode.R] = Enum.KeyCode.ButtonY,
	[Enum.KeyCode.F] = Enum.KeyCode.ButtonB,
}

local PromptFilter = {}

local function ownerOf(instance: Instance): number?
	local current: Instance? = instance.Parent
	while current and current ~= Workspace do
		local owner = current:GetAttribute("OwnerUserId")
		if typeof(owner) == "number" then
			return owner
		end
		current = current.Parent
	end
	return nil
end

local function evaluate(prompt: ProximityPrompt)
	local visibleTo = prompt:GetAttribute("VisibleTo")
	if visibleTo == nil then
		return
	end
	local owner = ownerOf(prompt)
	local isOwner = owner == localUserId
	local visible = if visibleTo == "owner" then isOwner else (owner ~= nil and not isOwner)
	if prompt:GetAttribute("Protected") == true or prompt:GetAttribute("Active") == false then
		visible = false
	end
	if visibleTo == "others" and localPlayer:GetAttribute("Carrying") == true then
		visible = false
	end
	prompt.Enabled = visible
end

local function evaluateAll()
	for prompt in prompts do
		evaluate(prompt)
	end
end

local function matchGamepadKey(prompt: ProximityPrompt)
	local button = GAMEPAD_KEYS[prompt.KeyboardKeyCode]
	if button then
		prompt.GamepadKeyCode = button
	end
end

local function track(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		matchGamepadKey(instance)
		instance:GetPropertyChangedSignal("KeyboardKeyCode"):Connect(function()
			matchGamepadKey(instance)
		end)
	end
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("VisibleTo") ~= nil then
		prompts[instance] = true
		evaluate(instance)
		-- Show/hide the moment the server flips it, not on the next half-second sweep
		instance:GetAttributeChangedSignal("Active"):Connect(function()
			evaluate(instance)
		end)
	end
end

function PromptFilter.start()
	for _, descendant in Workspace:GetDescendants() do
		track(descendant)
	end
	Workspace.DescendantAdded:Connect(track)
	Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("ProximityPrompt") then
			prompts[instance] = nil
		end
	end)
	localPlayer:GetAttributeChangedSignal("Carrying"):Connect(evaluateAll)
	-- Ownership changes (plot assigned, creature carried) are rare; re-check twice a second
	task.spawn(function()
		while true do
			task.wait(0.5)
			evaluateAll()
		end
	end)
end

return PromptFilter

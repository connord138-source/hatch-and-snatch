--!strict
-- Shows each ProximityPrompt only to the players it is meant for, locally:
--   VisibleTo = "owner"  -> only the owner (Steal targets' owners, lock button, nursery, take back)
--   VisibleTo = "others" -> everyone except the owner (Steal)
--   Protected = true     -> hidden from everyone (creature is in a nursery)
-- The owner is the nearest ancestor with an OwnerUserId attribute. This is
-- cosmetic only: the server re-validates every trigger.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localUserId = Players.LocalPlayer.UserId
local prompts: { [ProximityPrompt]: boolean } = {}

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
	if prompt:GetAttribute("Protected") == true then
		visible = false
	end
	prompt.Enabled = visible
end

local function track(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("VisibleTo") ~= nil then
		prompts[instance] = true
		evaluate(instance)
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
	-- Ownership changes (plot assigned, creature carried) are rare; re-check twice a second
	task.spawn(function()
		while true do
			task.wait(0.5)
			for prompt in prompts do
				evaluate(prompt)
			end
		end
	end)
end

return PromptFilter

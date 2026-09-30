--!strict
-- Server-side reach checks. ProximityPrompts and touch pads can be fired from
-- anywhere by an exploit, so anything that pays out checks the player is really
-- there (and alive) before acting.
local Reach = {}

local SLACK = 8 -- studs of allowance for latency and body size

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Whether the player's character is alive and within `distance` studs of `position`.
function Reach.near(player: Player, position: Vector3, distance: number): boolean
	local root = rootOf(player)
	return root ~= nil and (root.Position - position).Magnitude <= distance
end

-- Whether the player is close enough to have triggered `prompt` legitimately.
function Reach.prompt(player: Player, prompt: ProximityPrompt): boolean
	local parent = prompt.Parent
	local position = if parent and parent:IsA("BasePart")
		then parent.Position
		elseif parent and parent:IsA("Attachment") then parent.WorldPosition
		else nil
	return position ~= nil and Reach.near(player, position, prompt.MaxActivationDistance + SLACK)
end

-- Whether the player is touching (or right next to) `part`.
function Reach.touching(player: Player, part: BasePart): boolean
	return Reach.near(player, part.Position, part.Size.Magnitude / 2 + SLACK)
end

return Reach

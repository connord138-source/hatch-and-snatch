--!strict
-- Tints each biome zone's gate for this player: green and "Open" once the biome
-- is unlocked, red with the requirement until then. Cosmetic only; ZoneService
-- bounces locked-out players on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.Parent.ClientState)

local OPEN = Color3.fromRGB(110, 230, 140)
local LOCKED = Color3.fromRGB(255, 90, 90)

local ZoneGateController = {}

type Gate = { part: BasePart, biome: string }

function ZoneGateController.start()
	local decor = Workspace:WaitForChild("World"):WaitForChild("Decor", 60)
	if decor == nil then
		return
	end
	local gates: { Gate } = {}
	local function refresh(state: { [string]: any })
		-- Gates that streamed out are gone for good (a streamed-in copy is a new part)
		for i = #gates, 1, -1 do
			if gates[i].part.Parent == nil then
				table.remove(gates, i)
			end
		end
		for _, gate in gates do
			local biome = Config.Biomes[gate.biome]
			local open = biome.order <= (state.unlockedBiome or 1)
			gate.part.Color = if open then OPEN else LOCKED
			gate.part.Transparency = if open then 0.75 else 0.2
			local lintel = gate.part.Parent and gate.part.Parent:FindFirstChild("GateLintel")
			local gui = lintel and lintel:FindFirstChildWhichIsA("BillboardGui")
			local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
			if label then
				label.Text = if open
					then `{biome.displayName}\n✔ Open`
					else `{biome.displayName}\n🔒 {gate.part:GetAttribute("Requirement") or ""}`
				label.TextColor3 = if open then OPEN else Color3.fromRGB(255, 170, 170)
			end
		end
	end
	local function track(instance: Instance)
		if instance:IsA("BasePart") and instance.Name == "ZoneGate" then
			local biome = instance:GetAttribute("Biome")
			if typeof(biome) == "string" and Config.Biomes[biome] then
				table.insert(gates, { part = instance, biome = biome })
				if ClientState.current then
					refresh(ClientState.current)
				end
			end
		end
	end
	for _, descendant in decor:GetDescendants() do
		track(descendant)
	end
	decor.DescendantAdded:Connect(track)
	ClientState.changed:connect(refresh)
	if ClientState.current then
		refresh(ClientState.current)
	end
end

return ZoneGateController

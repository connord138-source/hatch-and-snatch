--!strict
-- Assigns each player one of the base plots, keeps them spawning there and
-- exposes the collector pad touch as a signal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local Reach = require(script.Parent.Parent.Reach)

local owners: { [number]: Player } = {}
local plotOf: { [Player]: WorldService.PlotLayout } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local PlotService = {
	-- (player) — owner stepped on their own collector pad
	collectorTouched = Signal.new(),
	-- (plot) — a plot was freed when its owner left
	released = Signal.new(),
}

function PlotService.get(player: Player): WorldService.PlotLayout?
	return plotOf[player]
end

function PlotService.ownerOf(plot: WorldService.PlotLayout): Player?
	return owners[plot.index]
end

local function teleportHome(player: Player, character: Model)
	local plot = plotOf[player]
	if plot == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and root:IsA("BasePart") then
		task.defer(function()
			character:PivotTo(plot.spawn)
		end)
	end
end

local function assign(player: Player)
	for _, plot in WorldService.plots do
		if not owners[plot.index] then
			owners[plot.index] = player
			plotOf[player] = plot
			plot.label.Text = `{player.DisplayName}'s Base`
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			characterConnections[player] = player.CharacterAdded:Connect(function(character)
				teleportHome(player, character)
			end)
			if player.Character then
				teleportHome(player, player.Character)
			end
			return
		end
	end
	warn(`[PlotService] No free plot for {player.Name}`)
end

local function release(player: Player)
	local plot = plotOf[player]
	if plot == nil then
		return
	end
	owners[plot.index] = nil
	plotOf[player] = nil
	plot.label.Text = "Free plot"
	plot.label.TextColor3 = Color3.new(1, 1, 1)
	plot.collectorLabel.Text = "$0"
	plot.model:SetAttribute("OwnerUserId", nil)
	-- Back to a starter plot for the next owner
	WorldService.setLevel(plot, 1)
	WorldService.setFloors(plot, 1, 0)
	WorldService.applyTheme(plot, Config.Progression.themes[1])
	WorldService.setNursery(plot, Config.Economy.tunables.nurserySlotsBase)
	PlotService.released:fire(plot)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

function PlotService.start()
	DataService.loaded:connect(function(player: Player)
		assign(player)
	end)
	DataService.releasing:connect(function(player: Player)
		release(player)
	end)

	local lastTouch: { [Player]: number } = {}
	for _, plot in WorldService.plots do
		plot.collector.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if
				player == nil
				or owners[plot.index] ~= player
				or not Reach.touching(player, plot.collector)
			then
				return
			end
			local now = os.clock()
			if now - (lastTouch[player] or 0) < 0.5 then
				return
			end
			lastTouch[player] = now
			PlotService.collectorTouched:fire(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

return PlotService

--!strict
-- The odds panel: while an egg's Buy prompt (or a shrine's Forge prompt) is on
-- screen, it lists everything that egg can give with the exact chances
-- (Shared/Odds): every species, finish and mutation, each list adding up to 100%,
-- updated live for the player's luck charge, Server Luck, the launch week's luck
-- and moon events. Eggs are paid random items (Robux buys cash and Server Luck),
-- so the odds must be shown before buying. Presentation only; the server rolls with the same odds.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Odds = require(ReplicatedStorage.Shared.Odds)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local REFRESH_SECONDS = 0.5

local OddsController = {
	open = false, -- an egg's prompt has the panel up (the guide hides its goal card meanwhile)
}

-- The hatch reveal plays over everything (RevealController), and the panel stayed
-- on screen under it (playtest 2026-10-03): it steps aside meanwhile and comes
-- back if the egg's prompt is still up.
local revealing = false
local applyVisible: () -> () = function() end

function OddsController.setRevealing(value: boolean)
	revealing = value
	applyVisible()
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.7
	return Ui.label(parent, props)
end

-- Which biome's egg a prompt sells: a belt egg, or a zone shrine's forge.
local function biomeOf(prompt: ProximityPrompt): string?
	local part = prompt.Parent
	local belt = Workspace:FindFirstChild("ConveyorEggs")
	if part and belt and part.Parent == belt then
		return part.Name:match("^(.+)Egg$")
	end
	if prompt.Name == "ForgeEgg" then
		local node: Instance? = prompt.Parent
		while node and node ~= Workspace do
			local biome = node.Name:match("^(.+)Zone$")
			if biome and Config.Biomes[biome] then
				return biome
			end
			node = node.Parent
		end
	end
	return nil
end

local function serverLuck(): number
	local luck = Workspace:GetAttribute("ServerLuck")
	local untilTime = Workspace:GetAttribute("ServerLuckUntil")
	if
		typeof(luck) == "number"
		and typeof(untilTime) == "number"
		and untilTime > Workspace:GetServerTimeNow()
	then
		return luck
	end
	return 1
end

function OddsController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchOdds"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Ui.autoScale(gui)

	-- Top-right, under a desktop's player list; phones hide the list, and the panel
	-- needs the height there
	local panel = Ui.panel(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, if Ui.isTouch() then 12 else 70),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.12,
		Visible = false,
	})
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = panel
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 1)
	contentLayout.Parent = content

	local order = 0
	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = content
	end
	local function line(label: string, percent: string, color: Color3?, detail: string?)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 17)
		text(row, {
			Size = UDim2.new(1, -86, 1, 0),
			TextSize = 14,
			Text = if detail then `{label}  <font size="11" color="#aab">{detail}</font>` else label,
			RichText = true,
			TextColor3 = color or Color3.new(1, 1, 1),
		})
		text(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(84, 17),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = percent,
		})
		add(row)
	end
	local function grid(lines: { Odds.Line })
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.Size = UDim2.new(1, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		local cells = Instance.new("UIGridLayout")
		cells.CellSize = UDim2.new(0.5, -4, 0, 16)
		cells.CellPadding = UDim2.fromOffset(8, 1)
		cells.SortOrder = Enum.SortOrder.LayoutOrder
		cells.Parent = box
		for i, entry in lines do
			local cell = text(box, {
				TextSize = 12,
				Text = `{entry.label}  {entry.percent}`,
				TextColor3 = Color3.fromRGB(220, 222, 235),
			})
			cell.LayoutOrder = i
		end
		add(box)
	end
	local function heading(value: string, color: Color3?)
		add(text(content, {
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 15,
			Text = value,
			TextColor3 = color or Color3.fromRGB(255, 220, 120),
		}))
	end
	local function note(value: string)
		add(text(content, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 12,
			TextWrapped = true,
			Text = value,
			TextColor3 = Ui.colors.muted,
		}))
	end

	local shownBiome: string? = nil
	local shownPrompt: ProximityPrompt? = nil
	local lastKey = ""

	local function render(biomeId: string)
		local state = ClientState.current
		local charge: number = if state then state.luckCharge or 1 else 1
		local server = serverLuck()
		local luck = Odds.luck(biomeId, charge, server, Workspace:GetServerTimeNow())
		local eventId = Workspace:GetAttribute("MoonEvent")
		local event = if typeof(eventId) == "string" then eventId else nil
		local key = `{biomeId}|{luck}|{event}`
		if key == lastKey then
			return
		end
		lastKey = key
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		order = 0
		local odds = Odds.forEgg(biomeId, event, luck)
		heading(`{Config.Biomes[biomeId].displayName} Egg: what's inside`)
		if luck > 1 then
			local parts: { string } = {}
			if server > 1 then
				table.insert(parts, `Server Luck ×{server}`)
			end
			if charge > 1 then
				table.insert(parts, `your wheel charge ×{charge}`)
			end
			local launch = Odds.launchLuck(Workspace:GetServerTimeNow())
			if launch > 1 then
				table.insert(parts, `Launch Week ×{launch}`)
			end
			note(
				`🍀 Luck ×{luck} on Epic and rarer ({table.concat(parts, " · ")}). The odds below include it.`
			)
		end
		if event then
			note(`🌕 {Workspace:GetAttribute("MoonEventName") or event} is on: included below.`)
		end
		for _, entry in odds.species do
			line(entry.label, entry.percent, entry.color, entry.detail)
		end
		heading("Finish", Color3.fromRGB(200, 230, 255))
		grid(odds.finishes)
		heading("Genetic mutation", Color3.fromRGB(200, 230, 255))
		grid(odds.mutations)
		note("Everything is rolled the moment you buy, with exactly these odds.")
	end

	applyVisible = function()
		panel.Visible = shownBiome ~= nil and not revealing
	end
	local function show(prompt: ProximityPrompt, biomeId: string)
		shownPrompt = prompt
		shownBiome = biomeId
		lastKey = ""
		render(biomeId)
		applyVisible()
		OddsController.open = true
	end
	local function hide()
		shownPrompt = nil
		shownBiome = nil
		applyVisible()
		OddsController.open = false
	end

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local biome = biomeOf(prompt)
		if biome then
			show(prompt, biome)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt == shownPrompt then
			hide()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			local prompt = shownPrompt
			if prompt and (prompt.Parent == nil or not prompt.Enabled) then
				hide()
			elseif shownBiome then
				render(shownBiome)
			end
		end
	end)
end

return OddsController

--!strict
-- The owner's admin panel: an Admin button in the bottom-left corner, only for
-- players the server marked as admins (Admin.luau). Every button asks the server,
-- which checks again who is asking, runs it (AdminActions) and answers with a
-- line of text shown at the bottom of the panel. Pick who it applies to at the
-- top: you, everyone, or one player in the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Parent.Ui)

type Option = { label: string, value: any }
type Picker = { get: () -> any, setOptions: ({ Option }) -> () }

local ROW_HEIGHT = 40
local SUFFIXES: { [string]: number } = {
	k = 1e3,
	m = 1e6,
	b = 1e9,
	t = 1e12,
	qa = 1e15,
	qi = 1e18,
	sx = 1e21,
	sp = 1e24,
}

local AdminController = {}

-- "1.5B", "250m", "3e12" or "1000" → a number (nil if it isn't one).
local function parseAmount(text: string): number?
	local cleaned = text:gsub("[%s,%$]", ""):lower()
	local number, suffix = cleaned:match("^([%d%.e%+%-]+)(%a*)$")
	local value = if number then tonumber(number) else nil
	if value == nil then
		return nil
	end
	if suffix ~= "" then
		local multiplier = SUFFIXES[suffix :: string]
		if multiplier == nil then
			return nil
		end
		value *= multiplier
	end
	return value
end

local function build(gui: ScreenGui)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteFunction

	local window = Ui.panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 540),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
	})
	Ui.label(window, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Admin",
	})
	local close = Ui.button(window, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(36, 34),
		BackgroundColor3 = Ui.colors.bad,
		Text = "X",
	})
	local result = Ui.label(window, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -8),
		Size = UDim2.new(1, -32, 0, 24),
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Ui.colors.cash,
		Text = "",
	})
	local list = Ui.scrollList(window, {
		Position = UDim2.fromOffset(12, 48),
		Size = UDim2.new(1, -24, 1, -88),
	})

	-- A dropdown's options float over the panel
	local overlay = Ui.panel(window, {
		Size = UDim2.fromOffset(260, 300),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 40,
	})
	local overlayList = Ui.scrollList(overlay, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 41,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function header(text: string)
		Ui.label(list, {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -12, 0, 26),
			TextScaled = false,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 210, 90),
			Text = text,
		})
	end
	local function row(): Frame
		local frame = Instance.new("Frame")
		frame.LayoutOrder = nextOrder()
		frame.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
		frame.BackgroundTransparency = 1
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = list
		return frame
	end

	local targetPicker: Picker
	local function send(action: string, ...: any)
		result.TextColor3 = Ui.colors.muted
		result.Text = "…"
		local args = table.pack(...)
		task.spawn(function()
			local ok, reply = pcall(function()
				return remote:InvokeServer(action, targetPicker.get(), table.unpack(args, 1, args.n))
			end)
			result.TextColor3 = if ok then Ui.colors.cash else Ui.colors.warn
			result.Text = if ok then tostring(reply) else "No answer from the server"
		end)
	end
	local function button(
		parent: Instance,
		text: string,
		width: number,
		color: Color3?,
		onClick: () -> ()
	): TextButton
		local b = Ui.button(parent, {
			Size = UDim2.fromOffset(width, ROW_HEIGHT - 6),
			BackgroundColor3 = color or Ui.colors.button,
			Text = text,
		})
		b.Activated:Connect(onClick)
		return b
	end
	local function box(parent: Instance, placeholder: string, width: number): TextBox
		local b = Instance.new("TextBox")
		b.Size = UDim2.fromOffset(width, ROW_HEIGHT - 6)
		b.BackgroundColor3 = Ui.colors.row
		b.TextColor3 = Color3.new(1, 1, 1)
		b.PlaceholderText = placeholder
		b.PlaceholderColor3 = Ui.colors.muted
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.Text = ""
		b.ClearTextOnFocus = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		b.Parent = parent
		return b
	end
	-- A button showing the picked option; clicking it lists the options to pick from
	local function picker(parent: Instance, width: number, options: { Option }): Picker
		local current = options[1]
		local b = Ui.button(parent, {
			Size = UDim2.fromOffset(width, ROW_HEIGHT - 6),
			BackgroundColor3 = Ui.colors.row,
			Text = (current and current.label or "-") .. " ▼",
		})
		local function choose(option: Option)
			current = option
			b.Text = option.label .. " ▼"
		end
		b.Activated:Connect(function()
			for _, child in overlayList:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			for i, option in options do
				local item = Ui.button(overlayList, {
					LayoutOrder = i,
					Size = UDim2.new(1, -10, 0, 30),
					Text = option.label,
					ZIndex = 42,
				})
				item.Activated:Connect(function()
					choose(option)
					overlay.Visible = false
				end)
			end
			local at = b.AbsolutePosition - window.AbsolutePosition
			local scale = window.AbsoluteSize.X / 700
			overlay.Position = UDim2.fromOffset(
				math.min(at.X / scale, 700 - 266),
				math.min(at.Y / scale + ROW_HEIGHT, 540 - 306)
			)
			overlay.Visible = true
		end)
		return {
			get = function(): any
				return current and current.value
			end,
			setOptions = function(newOptions: { Option })
				options = newOptions
				local still = nil
				for _, option in newOptions do
					if current and option.value == current.value then
						still = option
					end
				end
				choose(still or newOptions[1])
			end,
		}
	end
	local function amountFrom(input: TextBox): number?
		local value = parseAmount(input.Text)
		if value == nil then
			result.TextColor3 = Ui.colors.warn
			result.Text = "Type an amount like 5000, 2.5M, 1B, 3T or 1e15"
		end
		return value
	end

	-- Option lists from the shared config
	local speciesOptions: { Option } = {}
	for _, creature in Config.Creatures do
		table.insert(
			speciesOptions,
			{ label = `{creature.displayName} ({creature.rarity})`, value = creature.id }
		)
	end
	table.sort(speciesOptions, function(a, b)
		return a.label < b.label
	end)
	local biomeOptions: { Option } = {}
	for id, biome in Config.Biomes do
		table.insert(biomeOptions, { label = biome.displayName, value = id, order = biome.order } :: any)
	end
	table.sort(biomeOptions, function(a: any, b: any)
		return a.order < b.order
	end)
	local zoneOptions: { Option } = {}
	for _, option in biomeOptions do
		if Config.Zones.byBiome[option.value] then
			table.insert(zoneOptions, option)
		end
	end
	local finishOptions: { Option } = {}
	for _, finish in Config.Finishes do
		table.insert(finishOptions, { label = finish.displayName, value = finish.id })
	end
	local mutationOptions: { Option } = { { label = "No mutation", value = false } }
	for _, mutation in Config.Mutations do
		table.insert(mutationOptions, { label = mutation.displayName, value = mutation.id })
	end
	local stageOptions: { Option } = {
		{ label = "Adult", value = "Adult" },
		{ label = "Juvenile", value = "Juvenile" },
		{ label = "Baby", value = "Baby" },
	}
	local eventOptions: { Option } = {}
	for _, event in Config.MoonEvents do
		table.insert(eventOptions, { label = event.displayName, value = event.id })
	end
	local passOptions: { Option } = {}
	for _, pass in Config.Monetization.passes do
		table.insert(passOptions, { label = pass.name, value = pass.key })
	end
	local productOptions: { Option } = {}
	for _, product in Config.Monetization.products do
		table.insert(productOptions, { label = product.name, value = product.key })
	end

	-- Who
	header("Applies to")
	local whoRow = row()
	targetPicker = picker(whoRow, 260, { { label = "Me", value = "me" } })
	local function refreshPlayers()
		local options: { Option } = { { label = "Me", value = "me" }, { label = "Everyone", value = "all" } }
		for _, player in Players:GetPlayers() do
			if player ~= Players.LocalPlayer then
				table.insert(options, { label = player.DisplayName, value = player.UserId })
			end
		end
		targetPicker.setOptions(options)
	end
	refreshPlayers()
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayers)
	end)
	button(whoRow, "Go to their base", 170, Ui.colors.blue, function()
		send("goToBase")
	end)

	-- Cash and progress
	header("Cash")
	local cashRow = row()
	local cashBox = box(cashRow, "Amount (2.5M, 1B, 3T…)", 220)
	button(cashRow, "Add", 80, Ui.colors.good, function()
		local value = amountFrom(cashBox)
		if value then
			send("addCash", value)
		end
	end)
	button(cashRow, "Set to", 80, Ui.colors.blue, function()
		local value = amountFrom(cashBox)
		if value then
			send("setCash", value)
		end
	end)
	for _, quick in
		{ { label = "+1M", value = 1e6 }, { label = "+1B", value = 1e9 }, { label = "+1T", value = 1e12 } }
	do
		button(cashRow, quick.label, 62, nil, function()
			send("addCash", quick.value)
		end)
	end
	header("Progress")
	local progressRow = row()
	local progressBox = box(progressRow, "Amount", 150)
	button(progressRow, "Add XP", 100, Ui.colors.good, function()
		local value = amountFrom(progressBox)
		if value then
			send("xp", value)
		end
	end)
	button(progressRow, "Add spins", 110, nil, function()
		send("spins", parseAmount(progressBox.Text) or 10)
	end)
	button(progressRow, "Set rebirths", 130, Ui.colors.blue, function()
		local value = amountFrom(progressBox)
		if value then
			send("rebirths", value)
		end
	end)
	local essenceRow = row()
	local essenceBiome = picker(essenceRow, 230, zoneOptions)
	local essenceBox = box(essenceRow, "Amount", 120)
	button(essenceRow, "Give Essence", 140, Ui.colors.good, function()
		send("essence", essenceBiome.get(), parseAmount(essenceBox.Text) or 50)
	end)

	-- Creatures and eggs
	header("Spawn a creature")
	local creatureRow = row()
	local species = picker(creatureRow, 300, speciesOptions)
	local stage = picker(creatureRow, 120, stageOptions)
	local finish = picker(creatureRow, 140, finishOptions)
	local creatureRow2 = row()
	local mutation = picker(creatureRow2, 170, mutationOptions)
	button(creatureRow2, "Spawn", 100, Ui.colors.good, function()
		local mutationId = mutation.get()
		send("grant", species.get(), finish.get(), stage.get(), if mutationId then mutationId else nil)
	end)
	button(creatureRow2, "Show reveal only", 170, nil, function()
		local mutationId = mutation.get()
		send("reveal", species.get(), finish.get(), if mutationId then mutationId else nil)
	end)
	header("Eggs and growth")
	local eggRow = row()
	local eggBiome = picker(eggRow, 230, biomeOptions)
	button(eggRow, "Give egg (to hands)", 190, Ui.colors.good, function()
		send("egg", eggBiome.get())
	end)
	local growRow = row()
	button(growRow, "Hatch all incubators", 200, nil, function()
		send("hatchAll")
	end)
	button(growRow, "Grow all to Adult", 180, nil, function()
		send("growAll")
	end)
	button(growRow, "Store all", 110, nil, function()
		send("storeAll")
	end)

	-- Base, passes and products
	header("Base")
	local baseRow = row()
	button(baseRow, "Max base", 130, Ui.colors.good, function()
		send("maxBase")
	end)
	button(baseRow, "Own every Castle Designer option", 300, Ui.colors.good, function()
		send("allDesigns")
	end)
	local passRow = row()
	local pass = picker(passRow, 230, passOptions)
	button(passRow, "Grant pass", 120, nil, function()
		send("pass", pass.get())
	end)
	local product = picker(passRow, 190, productOptions)
	button(passRow, "Run", 70, nil, function()
		send("product", product.get())
	end)

	-- The world (everyone in the server)
	header("World (whole server)")
	local eventRow = row()
	local event = picker(eventRow, 180, eventOptions)
	button(eventRow, "Start moon event", 170, Ui.colors.blue, function()
		send("moonEvent", event.get())
	end)
	local zone = picker(eventRow, 170, zoneOptions)
	button(eventRow, "Zone event", 120, Ui.colors.blue, function()
		send("zoneEvent", zone.get())
	end)
	local clockRow = row()
	for _, mode in { "day", "dusk", "night", "auto" } do
		button(
			clockRow,
			if mode == "auto" then "Auto sky" else mode:sub(1, 1):upper() .. mode:sub(2),
			110,
			nil,
			function()
				send("clock", mode)
			end
		)
	end

	-- Testing aids
	header("Testing")
	local testRow = row()
	button(testRow, "Restart guide", 150, nil, function()
		send("restartGuide")
	end)
	button(testRow, "Next day", 110, nil, function()
		send("nextDay")
	end)
	button(testRow, "Reset codes", 130, nil, function()
		send("resetCodes")
	end)

	local toggle = Ui.button(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(90, 38),
		BackgroundColor3 = Color3.fromRGB(150, 60, 170),
		Text = "Admin",
	})
	toggle.Activated:Connect(function()
		window.Visible = not window.Visible
		overlay.Visible = false
	end)
	close.Activated:Connect(function()
		window.Visible = false
		overlay.Visible = false
	end)
end

function AdminController.start()
	local player = Players.LocalPlayer
	if player:GetAttribute("Admin") ~= true then
		player:GetAttributeChangedSignal("Admin"):Wait()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20 -- over the menus
	gui.Parent = player:WaitForChild("PlayerGui")
	Ui.autoScale(gui)
	build(gui)
end

return AdminController

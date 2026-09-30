--!strict
-- Shop menu: game passes and developer products (Config.Monetization). Buttons open
-- Roblox's own purchase prompt; the server grants what was bought
-- (MonetizationService). Items without a Creator Hub id yet are hidden in a live
-- game and shown greyed out in Studio, so the layout can be checked early.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Parent.Ui)

local Monetization = Config.Monetization
local SHOW_UNSET = RunService:IsStudio()

type Row = { button: TextButton, note: TextLabel?, key: string, pass: boolean }

local rows: { Row } = {}
local luckLine: TextLabel
local emptyNote: TextLabel

local ShopMenu = {}

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

local function header(list: Instance, order: number, title: string)
	local label = text(list, {
		Size = UDim2.new(1, -10, 0, 26),
		TextSize = 18,
		Text = title,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		LayoutOrder = order,
	})
	label.TextStrokeTransparency = 0.6
end

local function row(list: Instance, order: number, name: string, description: string): (Frame, TextButton)
	local frame = Ui.panel(list, {
		Size = UDim2.new(1, -10, 0, 64),
		BackgroundColor3 = Ui.colors.row,
		BackgroundTransparency = 0,
		LayoutOrder = order,
	})
	text(frame, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -160, 0, 22),
		TextSize = 18,
		Text = name,
	})
	text(frame, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -160, 0, 32),
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Ui.colors.muted,
		TextStrokeTransparency = 1,
		Text = description,
	})
	local button = Ui.button(frame, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(130, 42),
	})
	return frame, button
end

function ShopMenu.build(content: Frame)
	luckLine = text(content, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 16,
		TextColor3 = Color3.fromRGB(140, 255, 160),
	})
	local list =
		Ui.scrollList(content, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	emptyNote = text(list, {
		Size = UDim2.new(1, -10, 0, 40),
		TextSize = 16,
		TextColor3 = Ui.colors.muted,
		Text = "The shop opens soon!",
		Visible = false,
		LayoutOrder = 0,
	})

	local order = 1
	header(list, order, "Game passes: yours forever")
	for _, pass in Monetization.passes do
		if pass.id == 0 and not SHOW_UNSET then
			continue
		end
		order += 1
		local _, button = row(list, order, pass.name, pass.description)
		button.Activated:Connect(function()
			if pass.id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
			end
		end)
		table.insert(rows, { button = button, key = pass.key, pass = true })
	end
	order += 1
	header(list, order, "Boosts and cash")
	for _, product in Monetization.products do
		if product.id == 0 and not SHOW_UNSET then
			continue
		end
		order += 1
		local frame, button = row(list, order, product.name, product.description)
		local note = text(frame, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -2),
			Size = UDim2.fromOffset(130, 14),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(140, 255, 160),
			TextStrokeTransparency = 1,
		})
		button.Activated:Connect(function()
			if product.id ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
			end
		end)
		table.insert(rows, { button = button, note = note, key = product.key, pass = false })
	end
	emptyNote.Visible = #rows == 0
end

function ShopMenu.refresh(state: { [string]: any })
	local owned: { [string]: boolean } = state.passes or {}
	local boosts: { [string]: number } = state.boosts or {}
	local now = Workspace:GetServerTimeNow()

	local luck = Workspace:GetAttribute("ServerLuck")
	local luckUntil = Workspace:GetAttribute("ServerLuckUntil")
	if typeof(luck) == "number" and luck > 1 and typeof(luckUntil) == "number" and luckUntil > now then
		luckLine.Text = `🍀 Server Luck ×{luck} is on: {Format.duration(math.ceil(luckUntil - now))} left`
	else
		luckLine.Text = "Everything that matters can be earned in-game. These just speed things up."
	end

	for _, entry in rows do
		local item = if entry.pass
			then Monetization.passesByKey[entry.key]
			else Monetization.productsByKey[entry.key]
		local button = entry.button
		if item.id == 0 then
			button.Text = "Not set up"
			button.BackgroundColor3 = Ui.colors.disabled
			button.AutoButtonColor = false
		elseif entry.pass and owned[entry.key] then
			button.Text = "Owned ✓"
			button.BackgroundColor3 = Ui.colors.disabled
			button.AutoButtonColor = false
		else
			button.Text = `R$ {item.price}`
			button.BackgroundColor3 = Ui.colors.good
			button.AutoButtonColor = true
		end
		local note = entry.note
		if note then
			local growth = boosts.growth
			if entry.key == "GrowthElixir" and growth and growth > os.time() then
				note.Text = `Active: {Format.duration(growth - os.time())} left`
			elseif entry.key == "SkipHatch" and (boosts.instantHatch or 0) > 0 then
				note.Text = `{boosts.instantHatch} saved for your next egg`
			else
				note.Text = ""
			end
		end
	end
end

return ShopMenu

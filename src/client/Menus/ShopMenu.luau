--!strict
-- Shop menu: free rewards (codes, Roblox group, Premium, rewarded ad), then game
-- passes and developer products (Config.Monetization). Buttons open Roblox's own
-- prompts; the server grants everything (MonetizationService, RewardsService). Items
-- without a Creator Hub id yet are hidden in a live game and shown greyed out in
-- Studio, so the layout can be checked early. Paid random items (cash and Server
-- Luck, `paidRandom`) are hidden where the player's policy restricts them.
local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ads = require(script.Parent.Parent.Ads)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local Monetization = Config.Monetization
local Tuning = Monetization.tuning
local SHOW_UNSET = RunService:IsStudio()

type Row = { frame: Frame, button: TextButton, note: TextLabel?, key: string, pass: boolean }

local rows: { Row } = {}
local luckLine: TextLabel
local groupButton: TextButton?
local premiumButton: TextButton
local adRow: Frame?
local adNote: TextLabel?

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
		Size = UDim2.new(1, -10, 0, 78), -- room for a three-line description (Server Luck)
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
		Size = UDim2.new(1, -160, 0, 46),
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

	local order = 1
	header(list, order, "Free rewards")

	-- Codes
	order += 1
	local codeFrame, redeem = row(list, order, "Codes", "")
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(12, 32)
	box.Size = UDim2.new(1, -160, 0, 34)
	box.BackgroundColor3 = Ui.colors.panel
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = "Enter a code (new ones drop at like goals)"
	box.PlaceholderColor3 = Ui.colors.muted
	box.Font = Enum.Font.GothamBold
	box.TextSize = 16
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = codeFrame
	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 8)
	boxCorner.Parent = box
	redeem.Text = "Redeem"
	redeem.BackgroundColor3 = Ui.colors.blue
	local function submit()
		if box.Text:match("%S") then
			ClientState.request("RedeemCode", box.Text)
			box.Text = ""
		end
	end
	redeem.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)

	-- Roblox group (once it exists)
	local groupId = Tuning.group.id
	if groupId ~= 0 then
		order += 1
		local _, button = row(
			list,
			order,
			"Join the group",
			`Group members earn +{math.round((Tuning.group.cash - 1) * 100)}% cash, and joining gives {Tuning.group.spins} free Luck Wheel spins.`
		)
		button.Activated:Connect(function()
			local state = ClientState.current
			if state and state.inGroup then
				ClientState.request("ClaimGroup")
				return
			end
			task.spawn(function()
				pcall(GroupService.PromptJoinAsync, GroupService, groupId)
				ClientState.request("ClaimGroup")
			end)
		end)
		groupButton = button
	end

	-- Roblox Premium
	order += 1
	local _, premium = row(
		list,
		order,
		"Roblox Premium",
		`Premium members earn +{math.round((Tuning.premiumCash - 1) * 100)}% cash here, on top of everything else.`
	)
	premium.Activated:Connect(function()
		local state = ClientState.current
		if not (state and state.premium) then
			MarketplaceService:PromptPremiumPurchase(Players.LocalPlayer)
		end
	end)
	premiumButton = premium

	-- Rewarded video ad (only while Roblox has one to show)
	local ad = Monetization.productsByKey.AdBoost
	if ad and ad.id ~= 0 then
		order += 1
		local frame, watch = row(
			list,
			order,
			"Watch an ad",
			`×{Tuning.adBoost.multiplier} cash for {Tuning.adBoost.minutes} minutes. Watch again to stack up to {Tuning.adBoost.maxMinutes} minutes.`
		)
		frame.Visible = false
		watch.Text = "📺 Watch"
		watch.BackgroundColor3 = Ui.colors.good
		watch.Activated:Connect(Ads.watch)
		adNote = text(frame, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -2),
			Size = UDim2.fromOffset(130, 14),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(140, 255, 160),
			TextStrokeTransparency = 1,
		})
		adRow = frame
	end

	local function shown(id: number, shop: boolean?): boolean
		return shop ~= false and (id ~= 0 or SHOW_UNSET)
	end
	local anyPass = false
	for _, pass in Monetization.passes do
		anyPass = anyPass or shown(pass.id)
	end
	order += 1
	if anyPass then
		header(list, order, "Game passes: yours forever")
	end
	for _, pass in Monetization.passes do
		if not shown(pass.id) then
			continue
		end
		order += 1
		local frame, button = row(list, order, pass.name, pass.description)
		button.Activated:Connect(function()
			if pass.id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
			end
		end)
		table.insert(rows, { frame = frame, button = button, key = pass.key, pass = true })
	end
	local anyProduct = false
	for _, product in Monetization.products do
		anyProduct = anyProduct or shown(product.id, product.shop)
	end
	order += 1
	if anyProduct then
		header(list, order, "Boosts and cash")
	end
	for _, product in Monetization.products do
		if not shown(product.id, product.shop) then
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
			local state = ClientState.current
			local restricted = state == nil or state.paidRandomRestricted ~= false
			if product.id ~= 0 and not (product.paidRandom and restricted) then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
			end
		end)
		table.insert(rows, { frame = frame, button = button, note = note, key = product.key, pass = false })
	end
end

local function setButton(button: TextButton, label: string, enabled: boolean, color: Color3?)
	button.Text = label
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color or Ui.colors.good else Ui.colors.disabled
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

	if groupButton then
		if state.inGroup and state.groupRewarded then
			setButton(groupButton, "Joined ✓", false)
		elseif state.inGroup then
			setButton(groupButton, "Claim", true)
		else
			setButton(groupButton, "Join", true, Ui.colors.blue)
		end
	end
	if state.premium then
		setButton(premiumButton, "Active ✓", false)
	else
		setButton(premiumButton, "Get Premium", true, Ui.colors.blue)
	end
	if adRow and adNote then
		adRow.Visible = Ads.available
		local boostEnds = boosts.cash or 0
		adNote.Text = if boostEnds > os.time()
			then `Active: {Format.duration(boostEnds - os.time())} left`
			else ""
	end

	local restricted = state.paidRandomRestricted ~= false
	for _, entry in rows do
		local item = if entry.pass
			then Monetization.passesByKey[entry.key]
			else Monetization.productsByKey[entry.key]
		local product = if entry.pass then nil else Monetization.productsByKey[entry.key]
		entry.frame.Visible = not (product and product.paidRandom and restricted)
		local button = entry.button
		-- Ownership first: a pass granted in Studio (or bought) is owned even before
		-- it has a Creator Hub id
		if entry.pass and owned[entry.key] then
			button.Text = "Owned ✓"
			button.BackgroundColor3 = Ui.colors.disabled
			button.AutoButtonColor = false
		elseif item.id == 0 then
			button.Text = "Not set up"
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

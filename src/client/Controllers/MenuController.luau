--!strict
-- Menu buttons (a bar along the bottom of the screen) and the window they open, one
-- menu at a time. Each menu lives in Menus/ and only renders ClientState; its
-- buttons send requests that the server validates.
local Players = game:GetService("Players")

local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local CreaturesMenu = require(script.Parent.Parent.Menus.CreaturesMenu)
local IndexMenu = require(script.Parent.Parent.Menus.IndexMenu)
local RebirthMenu = require(script.Parent.Parent.Menus.RebirthMenu)
local ProgressMenu = require(script.Parent.Parent.Menus.ProgressMenu)
local BaseMenu = require(script.Parent.Parent.Menus.BaseMenu)
local ShopMenu = require(script.Parent.Parent.Menus.ShopMenu)
local DailyMenu = require(script.Parent.Parent.Menus.DailyMenu)

type Menu = {
	build: (content: Frame) -> (),
	refresh: (state: { [string]: any }) -> (),
}

local MENUS: { { id: string, title: string, menu: Menu } } = {
	{ id = "Creatures", title = "Your Creatures", menu = CreaturesMenu },
	{ id = "Progress", title = "Hatcher Level & Achievements", menu = ProgressMenu },
	{ id = "Base", title = "Your Base", menu = BaseMenu },
	{ id = "Index", title = "Collection Index", menu = IndexMenu },
	{ id = "Rebirth", title = "Rebirth", menu = RebirthMenu },
	{ id = "Daily", title = "Daily Rewards", menu = DailyMenu },
	{ id = "Shop", title = "Shop", menu = ShopMenu },
}

local BUTTON_W, BUTTON_GAP = 96, 8

local MenuController = {}

function MenuController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchMenus"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- above the HUD panels, below its toasts (HatchOverlay)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Ui.autoScale(gui)

	local window = Ui.panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.9, 0.78),
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(660, 500)
	sizeLimit.Parent = window
	local title = Ui.label(window, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = Ui.button(window, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(36, 34),
		BackgroundColor3 = Ui.colors.bad,
		Text = "X",
	})

	local contents: { [string]: Frame } = {}
	local buttons: { [string]: TextButton } = {}
	local open: string? = nil

	local function refreshOpen()
		local state = ClientState.current
		for _, entry in MENUS do
			if entry.id == open and state then
				entry.menu.refresh(state)
			end
		end
	end

	local function show(id: string?)
		open = id
		window.Visible = id ~= nil
		for menuId, content in contents do
			content.Visible = menuId == id
		end
		for _, entry in MENUS do
			if entry.id == id then
				title.Text = entry.title
			end
		end
		refreshOpen()
	end

	for i, entry in MENUS do
		local content = Instance.new("Frame")
		content.Name = entry.id
		content.BackgroundTransparency = 1
		content.Position = UDim2.fromOffset(12, 50)
		content.Size = UDim2.new(1, -24, 1, -60)
		content.Visible = false
		content.Parent = window
		entry.menu.build(content)
		contents[entry.id] = content

		local barWidth = #MENUS * BUTTON_W + (#MENUS - 1) * BUTTON_GAP
		local button = Ui.button(gui, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, -barWidth / 2 + (i - 1) * (BUTTON_W + BUTTON_GAP), 1, -12),
			Size = UDim2.fromOffset(BUTTON_W, 38),
			Text = entry.id,
		})
		if entry.id == "Shop" then
			button.BackgroundColor3 = Color3.fromRGB(190, 140, 30)
		end
		buttons[entry.id] = button
		button.Activated:Connect(function()
			show(if open == entry.id then nil else entry.id)
		end)
	end
	close.Activated:Connect(function()
		show(nil)
	end)

	ClientState.changed:connect(refreshOpen)

	-- Daily: a red dot while today's login reward is waiting, and the menu opens by
	-- itself once per session (after the first-session guide's early steps)
	local dailyButton = buttons.Daily
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.Size = UDim2.fromOffset(16, 16)
	badge.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
	badge.Visible = false
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = badge
	badge.Parent = dailyButton
	local autoOpened = false
	ClientState.changed:connect(function(state: { [string]: any })
		local claimable = state.daily ~= nil and state.daily.claimable == true
		badge.Visible = claimable
		if claimable and not autoOpened and (state.onboarding or 0) >= 5 and open == nil then
			autoOpened = true
			show("Daily")
		end
	end)
end

return MenuController

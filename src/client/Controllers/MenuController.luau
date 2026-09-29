--!strict
-- Menu buttons (left side, under the incubators) and the window they open, one
-- menu at a time. Each menu lives in Menus/ and only renders ClientState; its
-- buttons send requests that the server validates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local CreaturesMenu = require(script.Parent.Parent.Menus.CreaturesMenu)
local IndexMenu = require(script.Parent.Parent.Menus.IndexMenu)
local RebirthMenu = require(script.Parent.Parent.Menus.RebirthMenu)

type Menu = {
	build: (content: Frame) -> (),
	refresh: (state: { [string]: any }) -> (),
}

local MENUS: { { id: string, title: string, menu: Menu } } = {
	{ id = "Creatures", title = "Your Creatures", menu = CreaturesMenu },
	{ id = "Index", title = "Collection Index", menu = IndexMenu },
	{ id = "Rebirth", title = "Rebirth", menu = RebirthMenu },
}

-- Just under HudController's incubator panel (top 158, 40 + 30 per slot tall)
local BUTTONS_TOP = 158 + 40 + Config.Economy.tunables.incubatorSlots * 30 + 8

local MenuController = {}

function MenuController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchMenus"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- above the HUD panels, below its toasts (HatchOverlay)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

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

		local button = Ui.button(gui, {
			Position = UDim2.fromOffset(12 + (i - 1) * 85, BUTTONS_TOP),
			Size = UDim2.fromOffset(80, 34),
			Text = entry.id,
		})
		button.Activated:Connect(function()
			show(if open == entry.id then nil else entry.id)
		end)
	end
	close.Activated:Connect(function()
		show(nil)
	end)

	ClientState.changed:connect(refreshOpen)
end

return MenuController

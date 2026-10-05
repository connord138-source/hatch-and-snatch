--!strict
-- Menu buttons (a bar along the bottom of the screen) and the window they open, one
-- menu at a time. Each menu lives in Menus/ and only renders ClientState; its
-- buttons send requests that the server validates.
--
-- On a controller (Console on at launch, owner 2026-10-05): D-pad up selects the
-- bar, A opens a menu and selects its first button, the D-pad moves between
-- buttons (Roblox's own UI navigation), and B closes the menu.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

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

-- `station` menus have no button on the bar: they open from a prompt in the world
-- (the Base menu at a base's Command Terminal, owner 2026-10-01)
local MENUS: { { id: string, title: string, menu: Menu, station: boolean? } } = {
	{ id = "Creatures", title = "Your Creatures", menu = CreaturesMenu },
	{ id = "Progress", title = "Hatcher Level & Achievements", menu = ProgressMenu },
	{ id = "Base", title = "Command Terminal", menu = BaseMenu, station = true },
	{ id = "Index", title = "Collection Index", menu = IndexMenu },
	{ id = "Rebirth", title = "Rebirth", menu = RebirthMenu },
	{ id = "Daily", title = "Daily Rewards", menu = DailyMenu },
	{ id = "Shop", title = "Shop", menu = ShopMenu },
}

local BUTTON_W, BUTTON_GAP = 96, 8
local BAR_HEIGHT, BAR_BOTTOM = 38, 12
-- The window fills the room between the top of the screen and the bar (up to its
-- MaxSize): sized as a share of the screen, its bottom slid under the bar on a
-- short phone (playtest 2026-10-03: Daily, Shop and Creatures)
local WINDOW_TOP = 10
local WINDOW_BOTTOM = BAR_BOTTOM + BAR_HEIGHT + 10
local GUIDE_DONE = 6 -- the first-session guide's last step (GuideController's DONE)

local MenuController = {}

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:match("^Gamepad") ~= nil
end

-- Whether `object` shows, up to `root` (a hidden tab hides the buttons inside it)
local function shown(object: Instance, root: Instance): boolean
	local node: Instance? = object
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- The top-left visible button in a menu (where a controller's selection starts)
local function firstButton(root: Instance): GuiButton?
	local best: GuiButton? = nil
	for _, child in root:GetDescendants() do
		if child:IsA("GuiButton") and child.Selectable and shown(child, root) then
			local at = child.AbsolutePosition
			local bestAt = if best then best.AbsolutePosition else nil
			if
				bestAt == nil
				or at.Y < bestAt.Y - 4
				or (math.abs(at.Y - bestAt.Y) <= 4 and at.X < bestAt.X)
			then
				best = child
			end
		end
	end
	return best
end

local barGui: ScreenGui? = nil
local barWidth = 0

function MenuController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchMenus"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- above the HUD panels, below its toasts (HatchOverlay)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Ui.autoScale(gui)
	barGui = gui

	local window = Ui.panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, (WINDOW_TOP - WINDOW_BOTTOM) / 2),
		Size = UDim2.new(0.9, 0, 1, -(WINDOW_TOP + WINDOW_BOTTOM)),
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
		if id then
			ContextActionService:BindActionAtPriority("MenuClose", function(_, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					show(nil)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		else
			ContextActionService:UnbindAction("MenuClose")
		end
		if usingGamepad() then
			local selected = GuiService.SelectedObject
			if id then
				task.defer(function() -- once the menu has drawn its rows
					if open == id then
						GuiService.SelectedObject = firstButton(contents[id]) or close
					end
				end)
			elseif selected and selected:IsDescendantOf(window) then
				GuiService.SelectedObject = nil
			end
		end
	end

	local onBar = 0
	for _, entry in MENUS do
		if not entry.station then
			onBar += 1
		end
	end
	barWidth = onBar * BUTTON_W + (onBar - 1) * BUTTON_GAP
	local slot = 0
	for _, entry in MENUS do
		local content = Instance.new("Frame")
		content.Name = entry.id
		content.BackgroundTransparency = 1
		content.Position = UDim2.fromOffset(12, 50)
		content.Size = UDim2.new(1, -24, 1, -60)
		content.Visible = false
		content.Parent = window
		entry.menu.build(content)
		contents[entry.id] = content
		if entry.station then
			continue
		end

		slot += 1
		local button = Ui.button(gui, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, -barWidth / 2 + (slot - 1) * (BUTTON_W + BUTTON_GAP), 1, -BAR_BOTTOM),
			Size = UDim2.fromOffset(BUTTON_W, BAR_HEIGHT),
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

	-- Controllers: D-pad up selects the bar (only when nothing is selected, so it
	-- still moves the selection inside menus), with a hint beside it
	ContextActionService:BindAction("MenuBar", function(_, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin or open ~= nil or GuiService.SelectedObject ~= nil then
			return Enum.ContextActionResult.Pass
		end
		GuiService.SelectedObject = buttons.Creatures
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadUp)
	local padHint = Ui.label(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, barWidth / 2 + BUTTON_GAP, 1, -BAR_BOTTOM - 8),
		Size = UDim2.fromOffset(110, 22),
		Text = "D-pad ▲: menus",
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = usingGamepad(),
	})
	UserInputService.LastInputTypeChanged:Connect(function()
		padHint.Visible = usingGamepad()
	end)

	ClientState.changed:connect(refreshOpen)

	-- Daily: a red dot while today's login reward is waiting, and the menu opens by
	-- itself once per session, once the first-session guide is over (it popped up
	-- in the middle of the guide, playtest 2026-10-03; the dot shows meanwhile)
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
		if claimable and not autoOpened and (state.onboarding or 0) >= GUIDE_DONE and open == nil then
			autoOpened = true
			show("Daily")
		end
	end)

	-- World stations (the Quest Board, the Daily Chest, a base's command terminal)
	-- open a menu: their prompts name it in an OpensMenu attribute
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local menu = prompt:GetAttribute("OpensMenu")
		if typeof(menu) == "string" and contents[menu] then
			show(menu)
		end
	end)
end

-- A small square button just left of the bar (the music toggle). Call after start.
function MenuController.sideButton(text: string): TextButton
	return Ui.button(barGui :: ScreenGui, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -barWidth / 2 - BUTTON_GAP, 1, -BAR_BOTTOM),
		Size = UDim2.fromOffset(BAR_HEIGHT, BAR_HEIGHT),
		Text = text,
	})
end

return MenuController

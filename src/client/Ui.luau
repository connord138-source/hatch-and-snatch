--!strict
-- Builders for the placeholder UI made in code (HUD and menus). Presentation only.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = {}

-- The screen size the HUD and menus are laid out for, in pixels. Smaller screens
-- (phones, small windows) scale the whole UI down to fit; bigger ones keep 1:1.
local DESIGN_SIZE = Vector2.new(1100, 620)
local MIN_SCALE = 0.5

Ui.colors = {
	panel = Color3.fromRGB(20, 22, 30),
	row = Color3.fromRGB(36, 39, 52),
	button = Color3.fromRGB(58, 64, 82),
	blue = Color3.fromRGB(55, 105, 170),
	good = Color3.fromRGB(40, 150, 80),
	bad = Color3.fromRGB(170, 50, 50),
	disabled = Color3.fromRGB(48, 50, 58),
	muted = Color3.fromRGB(170, 172, 185),
	warn = Color3.fromRGB(255, 120, 120),
	cash = Color3.fromRGB(120, 255, 140),
}

local function apply(instance: Instance, props: { [string]: any })
	for key, value in props do
		(instance :: any)[key] = value
	end
end

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

function Ui.label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.TextScaled = true
	apply(l, props)
	l.Parent = parent
	return l
end

function Ui.panel(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Ui.colors.panel
	f.BackgroundTransparency = 0.25
	apply(f, props)
	corner(f, 10)
	f.Parent = parent
	return f
end

function Ui.button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Ui.colors.button
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	apply(b, props)
	corner(b, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = b
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = b
	b.Parent = parent
	return b
end

-- A vertical scrolling list that grows with its children (rows set LayoutOrder).
function Ui.scrollList(parent: Instance, props: { [string]: any }): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	apply(scroll, props)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- Scales a ScreenGui to the screen: everything laid out in pixels shrinks on
-- phones and small windows, and elements anchored to an edge stay on that edge.
function Ui.autoScale(gui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function update()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / DESIGN_SIZE.X, size.Y / DESIGN_SIZE.Y), MIN_SCALE, 1)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCamera = Workspace.CurrentCamera
		if newCamera then
			newCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
			update()
		end
	end)
end

-- Key hints like " (E)" mean nothing on a touch screen (prompts show a tap
-- button there), so they're dropped for touch-only players.
function Ui.hint(text: string): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return (text:gsub(" %(%u%)", ""))
	end
	return text
end

return Ui

--!strict
-- Rebirth menu (prestige): what the next rebirth costs, what it gives and what it resets.
-- The button needs a second press to confirm; the server re-checks the cost.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local CONFIRM_SECONDS = 3
local PER_REBIRTH = Config.Economy.tunables.rebirthBonusPerLevel

local status: TextLabel
local unlock: TextLabel
local bonus: TextLabel
local costLabel: TextLabel
local button: TextButton
local armedUntil = 0
local affordable = false

local RebirthMenu = {}

local function percent(rebirths: number): number
	return math.round(rebirths * PER_REBIRTH * 100)
end

local function line(parent: Instance, y: number, size: number, props: { [string]: any }): TextLabel
	props.Position = UDim2.fromOffset(0, y)
	props.Size = props.Size or UDim2.new(1, 0, 0, size + 8)
	props.TextScaled = false
	props.TextSize = size
	props.TextWrapped = true
	return Ui.label(parent, props)
end

function RebirthMenu.build(content: Frame)
	status = line(content, 10, 22, {})
	costLabel = line(content, 56, 28, {})
	unlock = line(content, 110, 20, { TextColor3 = Color3.fromRGB(150, 220, 255) })
	bonus = line(content, 146, 20, {})
	line(content, 196, 16, {
		Size = UDim2.new(1, 0, 0, 44),
		TextColor3 = Ui.colors.muted,
		TextStrokeTransparency = 1,
		Text = "Rebirthing resets your cash and uncollected cash.\nYou keep every creature, egg, level, upgrade and index entry.",
	})

	button = Ui.button(content, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(300, 54),
	})
	button.Activated:Connect(function()
		if not affordable then
			return
		end
		if os.clock() < armedUntil then
			armedUntil = 0
			ClientState.request("Rebirth")
			return
		end
		-- The first press arms the button; a second press within a few seconds rebirths
		local armed = os.clock() + CONFIRM_SECONDS
		armedUntil = armed
		button.Text = "Press again to rebirth"
		button.BackgroundColor3 = Ui.colors.bad
		task.delay(CONFIRM_SECONDS, function()
			local state = ClientState.current
			if armedUntil == armed and state then
				armedUntil = 0
				RebirthMenu.refresh(state)
			end
		end)
	end)
end

function RebirthMenu.refresh(state: { [string]: any })
	local rebirths: number = state.rebirths or 0
	local cost: number = state.rebirthCost
	affordable = state.cash >= cost

	status.Text = `Rebirths so far: {rebirths} (earnings +{percent(rebirths)}%)`
	costLabel.Text = `Next rebirth costs {Format.cash(cost)}`
	costLabel.TextColor3 = if affordable then Ui.colors.cash else Ui.colors.warn
	unlock.Text = "Also gives 3 Luck Wheel spins. Biomes unlock by Hatcher Level (Progress menu)."
	bonus.Text = `Earnings bonus: +{percent(rebirths)}% now, +{percent(rebirths + 1)}% after`

	if os.clock() >= armedUntil then
		button.Text = if affordable
			then `Rebirth for {Format.cash(cost)}`
			else `Need {Format.cash(cost - state.cash)} more`
		button.BackgroundColor3 = if affordable then Ui.colors.good else Ui.colors.disabled
		button.AutoButtonColor = affordable
	end
end

return RebirthMenu

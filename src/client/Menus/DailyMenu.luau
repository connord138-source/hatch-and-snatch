--!strict
-- Daily menu: the 7-day login streak (claim today's reward) and today's three
-- quests with progress, rewards and one swap a day (Config.Daily, DailyService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local Daily = Config.Daily

type DayCard = { frame: Frame, stroke: UIStroke, title: TextLabel }
type QuestRow = { frame: Frame, text: TextLabel, fill: Frame, info: TextLabel, swap: TextButton }

local streakLabel: TextLabel
local claimButton: TextButton
local cards: { DayCard } = {}
local questHeader: TextLabel
local questRows: { QuestRow } = {}
local bonusLabel: TextLabel

local DailyMenu = {}

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

local function setButton(button: TextButton, label: string, enabled: boolean, color: Color3)
	button.Text = label
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color else Ui.colors.disabled
end

function DailyMenu.build(content: Frame)
	streakLabel = text(content, {
		Size = UDim2.new(1, -170, 0, 28),
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 200, 90),
	})
	claimButton = Ui.button(content, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(160, 34),
	})
	claimButton.Activated:Connect(function()
		ClientState.request("ClaimDaily")
	end)

	-- Seven day cards in a row
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 40)
	row.Size = UDim2.new(1, 0, 0, 78)
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	for day, reward in Daily.streak do
		local frame = Ui.panel(row, {
			Size = UDim2.new(1 / #Daily.streak, -6, 1, 0),
			BackgroundColor3 = Ui.colors.row,
			BackgroundTransparency = 0,
			LayoutOrder = day,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = frame
		local title = text(frame, {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = if day == #Daily.streak then `Day {day} ★` else `Day {day}`,
		})
		text(frame, {
			Position = UDim2.fromOffset(4, 24),
			Size = UDim2.new(1, -8, 1, -28),
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Ui.colors.muted,
			TextStrokeTransparency = 1,
			Text = Daily.rewardText(reward),
		})
		cards[day] = { frame = frame, stroke = stroke, title = title }
	end

	questHeader = text(content, {
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 220, 120),
	})
	for i = 1, Daily.questsPerDay do
		local frame = Ui.panel(content, {
			Position = UDim2.fromOffset(0, 160 + (i - 1) * 66),
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundColor3 = Ui.colors.row,
			BackgroundTransparency = 0,
		})
		local label = text(frame, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -140, 0, 20),
			TextSize = 16,
		})
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
		bar.BorderSizePixel = 0
		bar.Position = UDim2.fromOffset(12, 30)
		bar.Size = UDim2.new(1, -140, 0, 8)
		bar.Parent = frame
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Color3.fromRGB(110, 220, 130)
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		local info = text(frame, {
			Position = UDim2.fromOffset(12, 40),
			Size = UDim2.new(1, -140, 0, 16),
			TextSize = 12,
			TextColor3 = Ui.colors.muted,
			TextStrokeTransparency = 1,
		})
		local swap = Ui.button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 36),
		})
		swap.Activated:Connect(function()
			ClientState.request("RerollQuest", i)
		end)
		questRows[i] = { frame = frame, text = label, fill = fill, info = info, swap = swap }
	end
	bonusLabel = text(content, {
		Position = UDim2.fromOffset(0, 160 + Daily.questsPerDay * 66),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(215, 185, 255),
	})
end

function DailyMenu.refresh(state: { [string]: any })
	local daily = state.daily
	if daily == nil then
		return
	end
	local left = math.max(0, daily.resetsAt - Workspace:GetServerTimeNow())
	streakLabel.Text = if daily.streak > 0
		then `🔥 Login streak: {daily.streak} day{if daily.streak == 1 then "" else "s"}`
		else "🔥 Log in every day for bigger rewards"
	if daily.claimable then
		setButton(claimButton, `Claim Day {daily.streakDay}`, true, Ui.colors.good)
	else
		setButton(claimButton, `Next in {Format.duration(left)}`, false, Ui.colors.good)
	end
	for day, card in cards do
		local claimed = day < daily.streakDay or (day == daily.streakDay and not daily.claimable)
		local current = day == daily.streakDay and daily.claimable
		card.frame.BackgroundColor3 = if claimed then Color3.fromRGB(34, 70, 44) else Ui.colors.row
		card.stroke.Color = if current then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(60, 64, 80)
		card.stroke.Thickness = if current then 3 else 1
		card.title.TextColor3 = if current then Color3.fromRGB(255, 220, 110) else Color3.new(1, 1, 1)
		card.title.Text = (if day == #Daily.streak then `Day {day} ★` else `Day {day}`)
			.. (if claimed then " ✓" else "")
	end

	questHeader.Text = `Daily quests: new ones in {Format.duration(left)}`
	for i, row in questRows do
		local quest = daily.quests[i]
		row.frame.Visible = quest ~= nil
		if quest then
			row.text.Text = quest.text
			row.fill.Size = UDim2.fromScale(math.clamp(quest.progress / quest.goal, 0, 1), 1)
			local progress = if quest.goal >= 1000
				then `{Format.cash(quest.progress)} / {Format.cash(quest.goal)}`
				else `{quest.progress} / {quest.goal}`
			row.info.Text = `{progress}  ·  Reward: {quest.reward}`
			if quest.done then
				setButton(row.swap, "✓ Done", false, Ui.colors.good)
			elseif daily.rerollsLeft > 0 then
				setButton(row.swap, "🔄 Swap", true, Ui.colors.blue)
			else
				setButton(row.swap, "No swaps left", false, Ui.colors.blue)
			end
		end
	end
	bonusLabel.Text = if daily.bonusPaid
		then "✓ All three done: bonus paid!"
		else `Finish all three: +{Daily.rewardText(Daily.allDoneBonus)}`
end

return DailyMenu

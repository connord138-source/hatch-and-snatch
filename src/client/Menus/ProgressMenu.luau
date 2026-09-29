--!strict
-- Progress menu: Hatcher Level + XP, what each biome's eggs need, and every
-- achievement with its progress and reward. Read-only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Parent.Ui)

local Progression = Config.Progression

local levelLabel: TextLabel
local xpFill: Frame
local biomeRows: { [string]: TextLabel } = {}
local achievementRows: { [string]: { name: TextLabel, info: TextLabel, strip: Frame } } = {}

local ProgressMenu = {}

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.TextScaled = false
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

function ProgressMenu.build(content: Frame)
	levelLabel = text(
		content,
		{ Size = UDim2.new(1, 0, 0, 26), TextSize = 22, TextColor3 = Color3.fromRGB(150, 220, 255) }
	)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(0, 30)
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.Parent = content
	xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = Color3.fromRGB(110, 200, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = bar

	local list =
		Ui.scrollList(content, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })

	local header =
		text(list, { Size = UDim2.new(1, -10, 0, 24), TextSize = 17, Text = "Biome eggs", LayoutOrder = 1 })
	header.TextColor3 = Color3.fromRGB(255, 220, 120)
	local biomes = {}
	for _, biome in Config.Biomes do
		if biome.order > 0 then
			table.insert(biomes, biome)
		end
	end
	table.sort(biomes, function(a, b)
		return a.order < b.order
	end)
	for i, biome in biomes do
		biomeRows[biome.id] = text(list, {
			Size = UDim2.new(1, -10, 0, 22),
			TextSize = 15,
			LayoutOrder = 1 + i,
		})
	end

	local achievementHeader = text(list, {
		Size = UDim2.new(1, -10, 0, 30),
		TextSize = 17,
		Text = "Achievements (XP + Luck Wheel spins)",
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = 20,
	})
	achievementHeader.TextColor3 = Color3.fromRGB(255, 220, 120)
	for i, achievement in Progression.achievements do
		local row = Ui.panel(list, {
			Size = UDim2.new(1, -10, 0, 44),
			BackgroundColor3 = Ui.colors.row,
			BackgroundTransparency = 0,
			LayoutOrder = 20 + i,
		})
		local strip = Instance.new("Frame")
		strip.BorderSizePixel = 0
		strip.Position = UDim2.fromOffset(6, 6)
		strip.Size = UDim2.new(0, 5, 1, -12)
		strip.Parent = row
		achievementRows[achievement.id] = {
			strip = strip,
			name = text(
				row,
				{ Position = UDim2.fromOffset(18, 4), Size = UDim2.new(1, -24, 0, 20), TextSize = 16 }
			),
			info = text(row, {
				Position = UDim2.fromOffset(18, 23),
				Size = UDim2.new(1, -24, 0, 16),
				TextSize = 12,
				TextColor3 = Ui.colors.muted,
				TextStrokeTransparency = 1,
			}),
		}
	end
end

function ProgressMenu.refresh(state: { [string]: any })
	local progression = state.progression
	if progression == nil then
		return
	end
	levelLabel.Text =
		`Hatcher Level {progression.level}   ·   {progression.xpInto} / {progression.xpNeeded} XP to level {progression.level + 1}`
	xpFill.Size = UDim2.fromScale(math.clamp(progression.xpInto / progression.xpNeeded, 0, 1), 1)

	for biomeId, row in biomeRows do
		local biome = Config.Biomes[biomeId]
		local need = Progression.biomeRequirements[biomeId]
		local unlocked = biome.order <= state.unlockedBiome
		if unlocked then
			row.Text =
				`✔ {biome.displayName} — unlocked ({Format.cash(Config.Eggs.price(biomeId))} per egg)`
			row.TextColor3 = Ui.colors.cash
		else
			local parts = { `Hatcher Level {need.level}` }
			if need.baseLevel > 1 then
				table.insert(parts, `base level {need.baseLevel}`)
			end
			row.Text =
				`🔒 {biome.displayName} — needs {table.concat(parts, " + ")} · {Progression.incubatorTiers[Progression.tierForBiome(
					biome.order
				)].name} incubator`
			row.TextColor3 = Ui.colors.muted
		end
	end

	for _, achievement in Progression.achievements do
		local row = achievementRows[achievement.id]
		local done = progression.achievements[achievement.id] == true
		local value = math.min(progression.stats[achievement.stat] or 0, achievement.goal)
		row.name.Text = `{if done then "✔ " else ""}{achievement.name} — {achievement.description}`
		row.name.TextColor3 = if done then Ui.colors.cash else Color3.new(1, 1, 1)
		local goalText = if achievement.stat == "earned"
			then Format.cash(achievement.goal)
			else tostring(achievement.goal)
		local valueText = if achievement.stat == "earned"
			then Format.cash(value)
			else tostring(math.floor(value))
		row.info.Text = if done
			then `Done! +{achievement.xp} XP, +{achievement.spins} spins`
			else `{valueText} / {goalText}   ·   reward {achievement.xp} XP + {achievement.spins} spin{if achievement.spins
					== 1
				then ""
				else "s"}`
		row.strip.BackgroundColor3 = if done then Ui.colors.cash else Color3.fromRGB(80, 84, 100)
	end
end

return ProgressMenu

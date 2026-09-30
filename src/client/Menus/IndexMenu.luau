--!strict
-- Collection index: every species, grouped by biome. Species you've owned show
-- their element and gag, which rare finishes you've collected (the dots) and
-- whether you've raised one to Adult; the rest stay "???".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Config.Types)
local CreaturePhoto = require(script.Parent.Parent.CreaturePhoto)
local Ui = require(script.Parent.Parent.Ui)

type Card = {
	frame: Frame,
	photo: ViewportFrame?,
	name: TextLabel,
	info: TextLabel,
	adult: TextLabel,
	dots: { [string]: Frame },
}

-- Collectable finishes, shown as dots in rarity order (Normal isn't one)
local FINISH_DOTS: { { id: string, color: Color3 } } = {
	{ id = "Gold", color = Color3.fromRGB(255, 196, 45) },
	{ id = "Chrome", color = Color3.fromRGB(215, 220, 228) },
	{ id = "Diamond", color = Color3.fromRGB(150, 230, 255) },
	{ id = "Molten", color = Color3.fromRGB(255, 110, 20) },
	{ id = "Galaxy", color = Color3.fromRGB(120, 70, 220) },
	{ id = "Prismatic", color = Color3.fromRGB(255, 120, 230) },
	{ id = "BloodMoon", color = Color3.fromRGB(200, 20, 30) },
}
local EMPTY_DOT = Color3.fromRGB(58, 61, 74)
local ADULT_COLOR = Color3.fromRGB(255, 215, 90)

local header: TextLabel
local cards: { [string]: Card } = {}

local IndexMenu = {}

local function text(
	parent: Instance,
	y: number,
	height: number,
	size: number,
	props: { [string]: any }
): TextLabel
	props.Position = UDim2.fromOffset(10, y)
	props.Size = UDim2.new(1, -80, 0, height) -- room for the photo on the right
	props.TextScaled = false
	props.TextSize = size
	props.TextXAlignment = Enum.TextXAlignment.Left
	return Ui.label(parent, props)
end

local function makeCard(parent: Instance, creature: Types.Creature, order: number): Card
	local rarityColor = Config.Rarities[creature.rarity].color
	local frame = Ui.panel(parent, {
		BackgroundColor3 = Ui.colors.row,
		BackgroundTransparency = 0,
		LayoutOrder = order,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local name = text(frame, 6, 20, 17, { TextTruncate = Enum.TextTruncate.AtEnd })
	text(frame, 27, 16, 13, { Text = creature.rarity, TextColor3 = rarityColor, TextStrokeTransparency = 1 })
	local adult = Ui.label(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 27),
		Size = UDim2.fromOffset(70, 16),
		TextScaled = false,
		TextSize = 12,
		Text = "ADULT",
		TextColor3 = ADULT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	})
	local info = text(frame, 45, 36, 11, {
		TextColor3 = Ui.colors.muted,
		TextStrokeTransparency = 1,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local dots: { [string]: Frame } = {}
	for i, finish in FINISH_DOTS do
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = EMPTY_DOT
		dot.Position = UDim2.fromOffset(10 + (i - 1) * 17, 85)
		dot.Size = UDim2.fromOffset(12, 12)
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = dot
		dot.Parent = frame
		dots[finish.id] = dot
	end
	return { frame = frame, photo = nil, name = name, info = info, adult = adult, dots = dots }
end

function IndexMenu.build(content: Frame)
	header = Ui.label(content, {
		Size = UDim2.new(1, 0, 0, 22),
		TextScaled = false,
		TextSize = 15,
		TextColor3 = Ui.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local scroll = Ui.scrollList(content, {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
	})

	-- Biomes in unlock order, with the event-only Junk Egg last
	local biomes: { Types.Biome } = {}
	for _, biome in Config.Biomes do
		table.insert(biomes, biome)
	end
	table.sort(biomes, function(a, b)
		return (if a.order == 0 then math.huge else a.order) < (if b.order == 0 then math.huge else b.order)
	end)

	for i, biome in biomes do
		local section = Instance.new("Frame")
		section.BackgroundTransparency = 1
		section.Size = UDim2.new(1, -10, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.LayoutOrder = i
		section.Parent = scroll
		local sectionLayout = Instance.new("UIListLayout")
		sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
		sectionLayout.Padding = UDim.new(0, 4)
		sectionLayout.Parent = section

		Ui.label(section, {
			Size = UDim2.new(1, 0, 0, 26),
			TextScaled = false,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = if biome.order == 0
				then `{biome.displayName} Egg (moon events only)`
				else biome.displayName,
			LayoutOrder = 1,
		})
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = 2
		grid.Parent = section
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(196, 104)
		gridLayout.CellPadding = UDim2.fromOffset(8, 8)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid

		-- Roster order already runs commonest-first within each biome
		for order, creature in Config.Creatures do
			if creature.biome == biome.id then
				cards[creature.id] = makeCard(grid, creature, order)
			end
		end
	end
end

function IndexMenu.refresh(state: { [string]: any })
	local owned: { [string]: boolean } = state.index or {}
	local finishes: { [string]: { [string]: boolean } } = state.indexFinishes or {}
	local adults: { [string]: boolean } = state.indexAdults or {}

	local found, rareFinishes = 0, 0
	for id, card in cards do
		local creature = Config.CreaturesById[id]
		local known = owned[id] == true
		if known then
			found += 1
		end
		-- A photo of the creature once you've discovered it
		if known and card.photo == nil then
			local photo = CreaturePhoto.make(card.frame, id)
			if photo then
				photo.AnchorPoint = Vector2.new(1, 0)
				photo.Position = UDim2.new(1, -4, 0, 4)
				photo.Size = UDim2.fromOffset(62, 62)
				photo.ZIndex = 2
				card.photo = photo
			end
		end
		card.name.Text = if known then creature.displayName else "???"
		card.name.TextColor3 = if known then Color3.new(1, 1, 1) else Ui.colors.muted
		card.info.Text = if known then `{creature.element} · {creature.gag}` else "Not discovered yet"
		local got = finishes[id] or {}
		for _, finish in FINISH_DOTS do
			local has = got[finish.id] == true
			if has then
				rareFinishes += 1
			end
			card.dots[finish.id].BackgroundColor3 = if has then finish.color else EMPTY_DOT
		end
		card.adult.Visible = adults[id] == true
	end

	local total = #Config.Creatures
	header.Text = `Species found: {found}/{total}     Rare finishes: {rareFinishes}/{total * #FINISH_DOTS}`
end

return IndexMenu

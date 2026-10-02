-- Paste into Studio's Command Bar (View → Command Bar) after importing the
-- 3D files (File → Import 3D, select them all). It moves every imported Model
-- from Workspace into the folder the game code reads, by name:
--   <SpeciesId> / <SpeciesId>_Baby -> ReplicatedStorage.CreatureModels
--   <BiomeId> / Egg                -> ReplicatedStorage.EggModels
--   prop names                     -> ReplicatedStorage.WorldProps
-- and sets each model's PrimaryPart to its largest part (creatures also get their
-- pivot squared up with the body; castle kit pieces lose their metalness map).
-- Safe to run again.
-- Then File → Save (Ctrl+S): these folders live in the place file, not in Rojo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EGGS = { Mossvale = true, CoralCoast = true, MagmaRift = true, FrostShelf = true, StormPeaks = true, Moonfall = true, Junk = true, Egg = true }
local PROPS = {
	HatcheryReactor = true, Pedestal = true, NurseryNest = true, Incubator = true, Collector = true,
	LockButton = true, PlotArch = true, LampPost = true, MossTree = true, RockCluster = true,
	BerryBush = true, MushroomCluster = true, CrystalCluster = true, CoralCluster = true,
	LavaRock = true, IceSpire = true, FlowerPatch = true, WoodFence = true, FallenLog = true, PineTree = true,
	-- Biome zone set pieces (src/server/SetPieces.luau)
	HollowStump = true, GiantGlowcap = true, TideArch = true, GiantClam = true, LavaVent = true,
	ObsidianSpikes = true, IceArch = true, FrozenBoulder = true, LightningCrag = true, WindSpire = true,
	MoonMonolith = true, CraterRim = true,
	-- Fortress kit (src/server/Fortress.luau)
	WatchtowerWood = true, TowerStone = true, TowerRoofed = true, TowerCitadel = true,
	GatehouseStone = true, GatehouseCitadel = true, Brazier = true,
	-- Base fixtures, hiding spots and decor (BaseKit.luau, BaseDecor.luau)
	BaseTerminal = true, BuyPad = true, HideHaystack = true, HideBarrels = true, HideHedge = true,
	HideChest = true, SpikeStrip = true, NetBallista = true, SearchlightTower = true, AlarmBell = true,
	CampSupplies = true, WallTorch = true, Campfire = true, FlowerPlanter = true, TrainingDummy = true,
	StoneWell = true, Fountain = true,
	-- The open land (src/server/Landmarks.luau)
	Lighthouse = true, Windmill = true, RuinsArch = true, StoneCircle = true, WaterfallCliff = true,
	CampTents = true, Shipwreck = true, PalmTree = true, Signpost = true, WoodBridge = true,
	OakTree = true, FishingHut = true, Dock = true, MarketStall = true, FlowerMeadow = true, Boulders = true,
}
-- Castle theme kits (src/server/CastleKits.luau). Their Tripo textures come with a
-- metalness map that turns them dark under a night sky (the pearly shell spires
-- came out navy, the gold spires near-black), so it is dropped.
local KIT = {
	"CoralShellSpire", "CoralBranches", "CoralFan", "CoralTubes", "CoralClamBrazier", "CoralAnemoneRock",
	"CoralStarfishPlaque", "CoralPearlLantern", "CoralStaghorn", "CoralStarfish", "CoralScallop", "CoralConch",
	"FireSpire", "FireObsidianSpikes", "FireSkullBrazier", "FireLavaRock", "FireDragonGate",
	"IceCrystalSpire", "IceCrystalCluster", "IceLantern", "IceGateArch", "SnowDrift",
	"StormTeslaSpire", "StormThunderStone", "StormPlasmaBrazier", "StormLightningRod", "StormCloud",
	"MossMushrooms", "MossMushroomLantern", "MossRoots", "MossGiantTree",
	"MoonFinial", "MoonCrystal", "MoonLantern", "MoonGateArch", "MoonBigCrescent",
	"GoldSpire", "GoldLion", "GoldBrazier", "GoldCrownCrest",
	"DiamondCrown", "DiamondCluster", "DiamondLantern", "DiamondGateCrest",
	"VoidShards", "VoidCrystals", "VoidBrazier", "VoidPortal", "VoidRunePillar",
	-- Variations and keep interiors (2026-10-02)
	"CoralGiantClam", "CoralOyster", "CoralBrain", "CoralAnemone", "CoralUrchins", "CoralBarnacleRock",
	"MossGlowCap", "MossShelfLog", "MossFern", "MossFlowers",
	"FireMagmaCrystals", "FireCauldron", "FireDragonSkull",
	"IceSnowPine", "IceShards", "IceBrazier",
	"StormCrystals", "StormCoil", "StormThunderRock",
	"MoonShard", "MoonFlower", "MoonLampPost",
	"GoldUrn", "GoldCoins", "GoldChest",
	"DiamondGems", "DiamondGeode", "DiamondChandelier",
	"VoidEyeOrb", "VoidThornTree", "VoidObelisk",
}
local kitPiece = {}
for _, name in KIT do
	PROPS[name] = true
	kitPiece[name] = true
end
local species = {}
for _, creature in require(ReplicatedStorage.Shared.Config).Creatures do
	species[creature.id] = true
end

local function folder(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local new = Instance.new("Folder")
	new.Name = name
	new.Parent = ReplicatedStorage
	return new
end

local moved, skipped = 0, {}
for _, model in workspace:GetChildren() do
	if not model:IsA("Model") then
		continue
	end
	local base = model.Name:gsub("_Baby$", ""):gsub("_Juvenile$", "")
	local target = if species[base] then "CreatureModels"
		elseif EGGS[model.Name] then "EggModels"
		elseif PROPS[model.Name] then "WorldProps"
		else nil
	if target == nil then
		continue
	end
	local largest, volume = nil, 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Size.X * part.Size.Y * part.Size.Z > volume then
			largest, volume = part, part.Size.X * part.Size.Y * part.Size.Z
		end
	end
	if largest == nil then
		table.insert(skipped, model.Name)
		continue
	end
	model.PrimaryPart = largest
	if kitPiece[model.Name] then
		for _, appearance in model:GetDescendants() do
			if appearance:IsA("SurfaceAppearance") then
				appearance.MetalnessMap = ""
			end
		end
	end
	if target == "CreatureModels" then
		-- An FBX exported without "Apply Transform" keeps its Z-up -> Y-up turn in the
		-- pivot, and the game stands creatures up by their pivot (they'd stand on their
		-- heads). Keep only the pivot's position so it matches the body's orientation.
		largest.PivotOffset = CFrame.new(largest.PivotOffset.Position)
	end
	local destination = folder(target)
	local old = destination:FindFirstChild(model.Name)
	if old then
		old:Destroy() -- a re-import replaces the previous version
	end
	model.Parent = destination
	moved += 1
end
print(`Organized {moved} model(s).` .. (if #skipped > 0 then ` Skipped (no parts): {table.concat(skipped, ", ")}` else ""))

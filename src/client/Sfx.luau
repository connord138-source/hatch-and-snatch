--!strict
-- Plays the game's sound pack (Config.Sounds): one uploaded audio file with every
-- sound back to back, each played from its own stretch (Sound.PlaybackRegion).
-- Until the pack's id is set, each sound falls back to a little tune of the
-- built-in ping, so rarities still sound different before the upload.
--   Sfx.play("Legendary")                                   -- on the player's screen
--   Sfx.play("Tick", { parent = part, volume = 0.4 })       -- 3D, from a part
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local PING = "rbxasset://sounds/electronicpingshort.wav"

-- `range`: how far a sound played from a part carries (studs, default 120)
export type Options = { volume: number?, pitch: number?, parent: Instance?, range: number? }

-- Fallback tunes: { delay, pitch, volume } notes of the ping
local FALLBACK: { [string]: { { number } } } = {
	Common = { { 0, 1, 0.45 } },
	Uncommon = { { 0, 1, 0.5 }, { 0.1, 1.5, 0.5 } },
	Rare = { { 0, 1, 0.55 }, { 0.09, 1.26, 0.55 }, { 0.18, 1.5, 0.6 } },
	Epic = { { 0, 1, 0.6 }, { 0.08, 1.26, 0.6 }, { 0.16, 1.5, 0.6 }, { 0.24, 2, 0.7 } },
	Legendary = {
		{ 0, 0.5, 0.8 },
		{ 0.12, 0.75, 0.7 },
		{ 0.24, 1, 0.7 },
		{ 0.38, 1.5, 0.8 },
		{ 0.5, 2, 0.8 },
	},
	Mythic = {
		{ 0, 0.45, 0.9 },
		{ 0.12, 0.67, 0.8 },
		{ 0.24, 0.9, 0.8 },
		{ 0.38, 1.35, 0.8 },
		{ 0.5, 1.8, 0.9 },
	},
	Celestial = {
		{ 0, 2.5, 0.5 },
		{ 0.09, 2.2, 0.5 },
		{ 0.18, 1.9, 0.5 },
		{ 0.27, 1.65, 0.5 },
		{ 0.4, 2.5, 0.7 },
	},
	Cosmic = { { 0, 0.35, 1 }, { 0.3, 0.5, 0.8 }, { 0.45, 0.75, 0.8 }, { 0.6, 1, 0.8 }, { 0.75, 1.5, 0.9 } },
	Secret = { { 0, 0.6, 0.7 }, { 0.3, 0.71, 0.7 }, { 0.6, 0.9, 0.7 }, { 1.2, 0.4, 1 }, { 1.32, 1, 0.9 } },
	Junk = { { 0, 0.6, 0.6 }, { 0.14, 0.45, 0.6 }, { 0.3, 0.35, 0.6 } },
	Impact = { { 0, 0.3, 1 } },
	Heartbeat = { { 0, 0.25, 0.8 }, { 0.22, 0.25, 0.6 }, { 0.7, 0.25, 0.8 }, { 0.92, 0.25, 0.6 } },
	Tick = { { 0, 1.8, 0.2 } },
	Mutation = {
		{ 0, 1, 0.5 },
		{ 0.06, 1.12, 0.5 },
		{ 0.12, 1.26, 0.5 },
		{ 0.18, 1.41, 0.5 },
		{ 0.24, 1.59, 0.6 },
	},
	Shine = { { 0, 2.2, 0.4 }, { 0.06, 2.8, 0.35 } },
	-- Riser and Whoosh have no ping version (silence is better than a fake)
}

local template: Sound? = nil

local Sfx = {}

local function soundId(): string?
	local id = Config.Sounds.id
	return if id and id > 0 then `rbxassetid://{id}` else nil
end

local function place(sound: Sound, parent: Instance?, range: number?)
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 14
		sound.RollOffMaxDistance = range or 120
	end
	sound.Parent = parent or SoundService
end

-- Loads the pack in the background so the first reveal isn't silent.
function Sfx.preload()
	local id = soundId()
	if id == nil or template then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "SfxPack"
	sound.SoundId = id
	sound.Parent = SoundService
	template = sound
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
end

-- Seconds the sound lasts (at pitch 1), or 0 if it doesn't exist.
function Sfx.length(name: string): number
	local region = Config.Sounds.regions[name]
	return if region then region[2] else 0
end

function Sfx.play(name: string, options: Options?)
	local volume = if options and options.volume then options.volume else 0.8
	local pitch = if options and options.pitch then options.pitch else 1
	local parent = if options then options.parent else nil
	local range = if options then options.range else nil
	local region = Config.Sounds.regions[name]
	local id = soundId()
	if id and region then
		Sfx.preload()
		local sound = if template then template:Clone() else Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
		sound.Volume = volume
		sound.PlaybackSpeed = pitch
		place(sound, parent, range)
		sound:Play()
		task.delay(region[2] / pitch + 0.25, function()
			sound:Destroy()
		end)
		return
	end
	local tune = FALLBACK[name]
	if tune == nil then
		return
	end
	for _, note in tune do
		task.delay(note[1], function()
			if parent and parent.Parent == nil then
				return -- its part went away (streamed out)
			end
			local sound = Instance.new("Sound")
			sound.SoundId = PING
			sound.Volume = note[3] * volume
			sound.PlaybackSpeed = note[2] * pitch
			place(sound, parent, range)
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end)
	end
end

return Sfx

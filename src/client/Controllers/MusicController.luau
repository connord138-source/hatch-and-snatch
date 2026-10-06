--!strict
-- Background music (owner, 2026-10-05: "should we add background music?"). Plays
-- Config.Music: the day list by day and the night list by night (DayNight), the
-- moon list while a moon event is on, shuffled, crossfading whenever the list
-- changes. It ducks under hatch reveals (RevealController), and the 🎵 button left
-- of the menu bar mutes it for the session. With no track ids it does nothing and
-- the button stays hidden. Presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DayNight = require(ReplicatedStorage.Shared.DayNight)
local MenuController = require(script.Parent.MenuController)

local Music = Config.Music
local DUCK = 0.3 -- share of the volume left under a hatch reveal
local LOAD_SECONDS = 20 -- a track that hasn't loaded by then is skipped
local CHECK_SECONDS = 1

local group: SoundGroup? = nil
local current: Sound? = nil
local currentList: string? = nil
local lastId = 0
local trackVolume = Music.volume -- the current track's own level (Config.Music.trackVolume)
local startedAt = 0
local endedAt: number? = nil
local muted = false
local ducked = false
local warned: { [string]: boolean } = {}
local rng = Random.new()

local MusicController = {}

local function level(): number
	if muted then
		return 0
	end
	return trackVolume * (if ducked then DUCK else 1)
end

local function fade(sound: Sound, volume: number, seconds: number)
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = volume }):Play()
end

local function tracks(list: string): { number }
	if list == "moon" then
		return Music.moon
	elseif list == "night" then
		return Music.night
	end
	return Music.day
end

-- Which list should be playing now (nil: there is no music at all)
local function wanted(): string?
	if Workspace:GetAttribute("MoonEvent") ~= nil and #Music.moon > 0 then
		return "moon"
	end
	local night = DayNight.night(DayNight.current()) > 0.5
	if night and #Music.night > 0 then
		return "night"
	elseif #Music.day > 0 then
		return "day"
	elseif #Music.night > 0 then
		return "night"
	end
	return nil
end

local function play(list: string)
	local ids = tracks(list)
	local id = ids[rng:NextInteger(1, #ids)]
	for _ = 1, 8 do -- not the same track twice running (when there's a choice)
		if id ~= lastId then
			break
		end
		id = ids[rng:NextInteger(1, #ids)]
	end
	lastId = id
	trackVolume = Music.trackVolume[id] or Music.volume
	local old = current
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = `rbxassetid://{id}`
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = group
	sound:Play()
	fade(sound, level(), Music.fadeSeconds)
	current, currentList, startedAt, endedAt = sound, list, os.clock(), nil
	sound.Ended:Once(function()
		if current == sound then
			endedAt = os.clock()
		end
	end)
	if old then
		fade(old, 0, Music.fadeSeconds)
		task.delay(Music.fadeSeconds + 0.2, function()
			old:Destroy()
		end)
	end
end

local function step()
	local list = wanted()
	if list == nil then
		return
	end
	local sound = current
	if
		sound == nil
		or list ~= currentList -- first track, or day/night/moon changed: crossfade
		or (endedAt and os.clock() - endedAt >= Music.gapSeconds) -- the next track
	then
		play(list)
	elseif not sound.IsLoaded and os.clock() - startedAt > LOAD_SECONDS then
		if not warned[sound.SoundId] then
			warned[sound.SoundId] = true
			warn(
				`[MusicController] {sound.SoundId} didn't load (not public, or not allowed here); skipping it`
			)
		end
		play(list)
	end
end

local function apply(seconds: number)
	if current then
		fade(current, level(), seconds)
	end
end

-- Quieter while a hatch reveal plays (RevealController, for its whole queue).
function MusicController.duck(on: boolean)
	if ducked ~= on then
		ducked = on
		apply(0.6)
	end
end

function MusicController.start()
	if #Music.day + #Music.night + #Music.moon == 0 then
		return
	end
	local g = Instance.new("SoundGroup")
	g.Name = "Music"
	g.Parent = SoundService
	group = g

	local button = MenuController.sideButton("🎵")
	button.Name = "MusicToggle"
	button.Activated:Connect(function()
		muted = not muted
		button.Text = if muted then "🔇" else "🎵"
		apply(0.5)
	end)

	task.spawn(function()
		while true do
			local ok, problem = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn(`[MusicController] {problem}`)
			end
			task.wait(CHECK_SECONDS)
		end
	end)
end

return MusicController

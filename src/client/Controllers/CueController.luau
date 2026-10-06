--!strict
-- Sound cues for timed events (owner, 2026-10-05: "a sound cue for timed events
-- before launch"). The server names a cue (Net.cue) and this plays it from the
-- sound pack (Sfx): on the screen, or with a position, from that spot in the world.
--   MoonWarning  a moon rises in a minute (with its toast)
--   MoonRising   the moon event starts (with its announcement)
--   MoonEnd      the moon sets
--   ZoneWarning  a zone's set-piece event starts in 10 s (with its toast)
--   ZoneEvent    the set piece going off, heard from nearby
--   BallistaFire / BallistaHit  a base's Net Ballista shooting, and its net landing
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Parent.Sfx)

type Note = { sound: string, volume: number, pitch: number?, delay: number? }

local CUES: { [string]: { Note } } = {
	MoonWarning = { { sound = "Mutation", volume = 0.55, pitch = 0.8 } },
	MoonRising = {
		{ sound = "Impact", volume = 0.5 },
		{ sound = "Celestial", volume = 0.75, delay = 0.12 },
	},
	MoonEnd = { { sound = "Shine", volume = 0.5, pitch = 0.7 } },
	ZoneWarning = { { sound = "Shine", volume = 0.4, pitch = 1.15 } },
	ZoneEvent = { { sound = "Epic", volume = 1 } },
	BallistaFire = {
		{ sound = "Whoosh", volume = 1, pitch = 0.75 },
		{ sound = "Impact", volume = 0.45, pitch = 1.6 },
	},
	BallistaHit = { { sound = "Impact", volume = 0.6, pitch = 1.25 } },
}
local WORLD_RANGE = 220 -- how far a cue in the world carries (studs)

local CueController = {}

local function play(name: string, at: Vector3?)
	local notes = CUES[name]
	if notes == nil then
		return
	end
	local anchor: Attachment? = nil
	if at then
		local a = Instance.new("Attachment")
		a.Name = `Cue{name}`
		a.Parent = Workspace.Terrain
		a.WorldPosition = at -- after parenting, or it's taken as a local offset
		anchor = a
	end
	local longest = 0
	for _, note in notes do
		local delay = note.delay or 0
		longest = math.max(longest, delay + Sfx.length(note.sound) / (note.pitch or 1))
		task.delay(delay, function()
			Sfx.play(note.sound, {
				volume = note.volume,
				pitch = note.pitch,
				parent = anchor :: Instance?,
				range = WORLD_RANGE,
			})
		end)
	end
	if anchor then
		task.delay(longest + 2, function()
			anchor:Destroy()
		end)
	end
end

function CueController.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cue") :: RemoteEvent
	remote.OnClientEvent:Connect(function(name: any, at: any)
		if typeof(name) == "string" then
			play(name, if typeof(at) == "Vector3" then at else nil)
		end
	end)
end

return CueController

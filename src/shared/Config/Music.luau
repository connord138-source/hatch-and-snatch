--!strict
-- Background music (owner, 2026-10-05: "should we add background music?"),
-- played by MusicController: the day list by day, the night list by night and the
-- moon list during a moon event (each falls back to the others when empty),
-- shuffled, crossfading when the list changes. Ducks under hatch reveals.
--
-- Ids must be audio this experience may play: Roblox's licensed library (Creator
-- Store → Audio → Music, made by "Roblox", free in any experience) or uploads the
-- owner's account owns. With every list empty there is no music and no 🎵 button.
export type Music = {
	volume: number,
	fadeSeconds: number,
	gapSeconds: number,
	day: { number },
	night: { number },
	moon: { number },
}

local Music: Music = {
	volume = 0.3, -- under the sound pack's stingers (they play at 0.5-1)
	fadeSeconds = 3, -- the crossfade between tracks and lists
	gapSeconds = 4, -- quiet between two tracks
	day = {}, -- bright, easy adventure (12 min of day)
	night = {}, -- calm, mysterious (4 min of night)
	moon = {}, -- tense, epic: a moon event is on
}

return Music

--!strict
-- Background music (owner, 2026-10-05: "should we add background music?"),
-- played by MusicController: the day list by day, the night list by night and the
-- moon list during a moon event (each falls back to the others when empty),
-- shuffled, crossfading when the list changes. Ducks under hatch reveals.
--
-- Ids must be audio this experience may play: Roblox's licensed library (Creator
-- Store → Audio → Music, made by "Roblox", free in any experience) or uploads the
-- owner's account owns. With every list empty there is no music and no 🎵 button.
--
-- Subtle, never loud (owner, 2026-10-05): each track has its own Volume, because
-- licensed tracks are mastered very differently (one measured 2.6x louder than
-- another). Studio's PlaybackLoudness ignores Volume, so it gives a track's own
-- loudness (whole-track average): every track plays at about loudness x Volume = 16
-- (14 at night, 18 for a moon), around a third of a Common stinger's 54 (63 x 0.85),
-- so the music sits about 10 dB under the quietest hatch sound.
export type Music = {
	volume: number,
	trackVolume: { [number]: number },
	fadeSeconds: number,
	gapSeconds: number,
	day: { number },
	night: { number },
	moon: { number },
}

local Music: Music = {
	volume = 0.15, -- a track missing from trackVolume (a typical licensed track)
	trackVolume = { -- by id: 16 (day), 14 (night) or 18 (moon) ÷ its measured loudness
		[1841593944] = 0.15, -- Enchanted Kingdom a: loudness 104
		[1835287580] = 0.27, -- Spring Awakens: 60
		[1841594035] = 0.23, -- Mischievous Elves a: 69
		[1841594125] = 0.23, -- Dreamcatcher a: 61
		[1838006048] = 0.12, -- Night-Time Waltz (a): 115
		[1843501525] = 0.12, -- Mythic Mountain - No Choir: 153
		[1843501635] = 0.115, -- Beast Rider - No Choir: 157
	},
	fadeSeconds = 3, -- the crossfade between tracks and lists
	gapSeconds = 4, -- quiet between two tracks
	-- Roblox's licensed APM library (Creator Store, uploader @APMOfficial; public,
	-- free in any experience), picked by the owner 2026-10-05
	day = { -- bright, easy adventure (12 min of day)
		1841593944, -- Enchanted Kingdom a (Magnum Opus)
		1835287580, -- Spring Awakens (2nd Foundation Music)
		1841594035, -- Mischievous Elves a (Magnum Opus)
	},
	night = { -- calm, mysterious (4 min of night)
		1841594125, -- Dreamcatcher a (Magnum Opus)
		1838006048, -- Night-Time Waltz (a) (Thomas Howe)
	},
	moon = { -- tense, epic: a moon event is on
		1843501525, -- Mythic Mountain - No Choir (George Alexander Christie)
		1843501635, -- Beast Rider - No Choir (George Alexander Christie)
	},
}

return Music

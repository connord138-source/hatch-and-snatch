--!strict
-- The island's day and night (owner, 2026-10-02): 12 minutes of day, then 4 of
-- night, when the castles' lanterns, braziers and crystals light up. The time
-- comes from the server's clock (Workspace:GetServerTimeNow), so every player
-- sees the same sky without any network traffic; DayNightController moves the
-- lighting each frame.
local DayNight = {
	DAY_SECONDS = 12 * 60,
	NIGHT_SECONDS = 4 * 60,
	SUNRISE = 6, -- ClockTime at the start of the day
	SUNSET = 18, -- and at nightfall
	TWILIGHT = 0.8, -- hours either side of sunrise and sunset that fade between the looks
}

local CYCLE = DayNight.DAY_SECONDS + DayNight.NIGHT_SECONDS
local DAY_HOURS = DayNight.SUNSET - DayNight.SUNRISE
local NIGHT_HOURS = 24 - DAY_HOURS

-- Lighting.ClockTime (0-24) at a server time: the day's hours pass slowly, the
-- night's quickly.
function DayNight.clock(serverTime: number): number
	local t = serverTime % CYCLE
	local hours = if t < DayNight.DAY_SECONDS
		then t / DayNight.DAY_SECONDS * DAY_HOURS
		else DAY_HOURS + (t - DayNight.DAY_SECONDS) / DayNight.NIGHT_SECONDS * NIGHT_HOURS
	return (DayNight.SUNRISE + hours) % 24
end

local function smooth(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

-- How much of the night look to show at a clock time: 0 by day, 1 by night,
-- eased through dusk and dawn.
function DayNight.night(clock: number): number
	local dusk = smooth((clock - (DayNight.SUNSET - DayNight.TWILIGHT)) / (2 * DayNight.TWILIGHT))
	local dawn = smooth(((DayNight.SUNRISE + DayNight.TWILIGHT) - clock) / (2 * DayNight.TWILIGHT))
	return math.max(dusk, dawn)
end

return DayNight

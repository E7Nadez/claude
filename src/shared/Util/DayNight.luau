--!strict
-- Night detection shared by night offers (server validation) and the neon
-- lighting / night stand on the client. Reads the replicated Lighting clock.

local Lighting = game:GetService("Lighting")

local Factory = require(script.Parent.Parent.Definitions.Factory)

local DayNight = {}

function DayNight.IsNight(clockTime: number?): boolean
	local clock = clockTime or Lighting.ClockTime
	local config = Factory.DayNight
	if config.NightStart > config.NightEnd then
		return clock >= config.NightStart or clock < config.NightEnd
	end
	return clock >= config.NightStart and clock < config.NightEnd
end

-- Game hours until the next night/day switch, converted to real seconds
-- when the server drives the clock (nil otherwise).
function DayNight.SecondsUntilSwitch(clockTime: number?): number?
	local config = Factory.DayNight
	if not config.DriveClock then
		return nil
	end
	local clock = clockTime or Lighting.ClockTime
	local target = if DayNight.IsNight(clock) then config.NightEnd else config.NightStart
	local hours = (target - clock) % 24
	local secondsPerHour = config.CycleMinutes * 60 / 24
	return hours * secondsPerHour
end

-- 0 during the day, fades to 1 within the first game hour after dusk and
-- back to 0 during the last game hour before dawn.
function DayNight.NightAlpha(clockTime: number?): number
	local clock = clockTime or Lighting.ClockTime
	if not DayNight.IsNight(clock) then
		return 0
	end
	local config = Factory.DayNight
	local sinceDusk = (clock - config.NightStart + 12) % 24 - 12
	local sinceDawn = (clock - config.NightEnd + 12) % 24 - 12
	return math.min(math.clamp(sinceDusk, 0, 1), math.clamp(-sinceDawn, 0, 1))
end

-- UTC day number used for the daily crate.
function DayNight.Day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function DayNight.SecondsUntilNextDay(unixTime: number): number
	return 86400 - (unixTime % 86400)
end

return DayNight

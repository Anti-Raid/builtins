local datetime = require "@antiraid/datetime"
local types = require "./types"

type Interval = {
    --- At what interval to start limiting at
    Start: number,
    --- At what interval to stop limiting at
    Stop: number,
}

--- Parses a Interval
---
--- Modes: Absolute: Absolute limiting from {StartUnixTime} to {StopUnixTime}
--- TimePerDay: Limit every day between Start and Stop times in a given Timezone
local function parseIntervalMode(mode: types.IntervalMode): Interval?
    if mode.type == "Absolute" then
        return {
            Start = mode.start,
            Stop = mode.stop,
        }
    elseif mode.type == "TimePerDay" then
        local tz = datetime.new(mode.timezone)
        local utcStartTime = tz:timeTzToUtc(mode.start.hours, mode.start.minutes, mode.start.seconds)
        local utcStopTime = tz:timeTzToUtc(mode.stop.hours, mode.stop.minutes, mode.stop.seconds)
        return {
            Start = utcStartTime.timestamp_seconds,
            Stop = utcStopTime.timestamp_seconds,
        }
    else
        return nil
    end
end

--- Given a a interval mode, returns either true or false if the id is limited based on this
--- specific interval mode (true = limited, false = not limited)
local function Strategy(mode: types.IntervalMode): boolean
    local interval = parseIntervalMode(mode)
    if not interval then return false end
    -- Check if we are in the interval
    local now = os.time()
    return now >= interval.Start and now <= interval.Stop 
end    
   
return Strategy
local gcra = require "@antiraid-ext/gcra"
local types = require "./types"

type Rate = {
    --- At what minimum count should limiting begin
    Count: number,
    --- What rate does this minimum count have to be at
    Time: number,
    --- Which limiterId to use
    LimiterId: string,
}

--- Parses a Rate mode
local function parseRateMode(mode: types.RateMode): Rate?
    if mode.type == "Rate" then
        return {
            Count = mode.count,
            Time = mode.time,
            LimiterId = mode.limiterId,
        }
    else
        return nil
    end
end

local gcraLimiters: {[string]: gcra.RateLimiter<string>} = {}

--- Given a a rate mode and a object id, returns either true or false if the id is limited based on this
--- specific rate mode (true = limited, false = not limited)
local function Strategy(mode: types.RateMode): boolean
    local rate = parseRateMode(mode)
    if not rate then return false end
    -- Check for a bucket, creating it if it does not exist
    local ratelimiter = gcraLimiters[rate.LimiterId]
    if not ratelimiter then
        ratelimiter = gcra(rate.Count, rate.Time) :: gcra.RateLimiter<string>
        gcraLimiters[rate.LimiterId] = ratelimiter -- Store it for future use
    end
    -- Returns true if action is allowed else false, so we need the inverse here
    -- (true = limited so action not allowed -> false from attemptAction)
    return not ratelimiter.attemptAction(rate.LimiterId)
end    

return Strategy
local data = require"../commands/data"

local fallbackScheduledExecs = {
    StingExpiry = require"./StingExpiry",
} :: { [string]: (data: data.ScheduledExecRunData) -> boolean }

return {
    fallbackScheduledExecs = fallbackScheduledExecs
}
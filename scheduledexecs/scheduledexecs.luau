local data = require"../commands/data"

local fallbackScheduledExecs = {
    StingExpiry = require"./StingExpiry".scheduledexec,
} :: { [string]: (data: data.ScheduledExecRunData) -> boolean }

return {
    fallbackScheduledExecs = fallbackScheduledExecs
}
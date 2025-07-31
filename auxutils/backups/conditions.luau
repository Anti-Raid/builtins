local MAX_MESSAGES = 200 -- Maximum number of messages to backup totally (200 is a sweet spot between usability and time needed to create and restore backups)
local MAX_PER_CHANNEL = 20 -- Maximum number of messages to backup per channel (50 is a sweet spot between usability and time needed to create and restore backups)
local MIN_PER_CHANNEL = 5 -- Minimum number of messages to backup per channel (5 is the minimum)
local MAX_STRIP_ITERS = 300

return {
    MAX_MESSAGES = MAX_MESSAGES,
    MAX_PER_CHANNEL = MAX_PER_CHANNEL,
    MIN_PER_CHANNEL = MIN_PER_CHANNEL,
    MAX_STRIP_ITERS = MAX_STRIP_ITERS,
}
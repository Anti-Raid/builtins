local types = require"../backups"

local MAX_MESSAGES = 200 -- Maximum number of messages to backup totally (200 is a sweet spot between usability and time needed to create and restore backups)
local MAX_PER_CHANNEL = 20 -- Maximum number of messages to backup per channel (50 is a sweet spot between usability and time needed to create and restore backups)
local MIN_PER_CHANNEL = 5 -- Minimum number of messages to backup per channel (5 is the minimum)

-- Flag to indicate if we are currently in a backup operation
local isCurrentlyInBackup = false

--- Validates the backup options to ensure they are within the allowed limits.
--- This function will throw an error if the options are invalid.
--- @param data The backup options to validate
--- @return nil if the options are valid, otherwise an error is thrown
local function validate(data: types.BackupCreateOpts) 
    if data.maxMessages < 1 or data.maxMessages > MAX_MESSAGES then
        error(`maxMessages must be between 1 and {MAX_MESSAGES}, got {data.maxMessages}`)
    end

    if data.perChannel < MIN_PER_CHANNEL or data.perChannel > MAX_PER_CHANNEL then
        error(`perChannel must be between {MIN_PER_CHANNEL} and {MAX_PER_CHANNEL}, got {data.perChannel}`)
    end

    if data.perChannel > data.maxMessages then
        error(`perChannel cannot be greater than maxMessages, got perChannel={data.perChannel} and maxMessages={data.maxMessages}`)
    end

    if isCurrentlyInBackup then
        error("Cannot validate backup options while already in a backup operation")
    end

    isCurrentlyInBackup = true
end

--- Marks the current operation as being in a backup operation.
---
--- This is used to prevent multiple backup operations from being started at the same time.
local function markInBackup()
    if isCurrentlyInBackup then
        error("Already in a backup operation")
    end
    isCurrentlyInBackup = true
end

--- Resets the backup operation state.
---
--- This should be called after the backup operation is complete to allow for new backup operations.
local function resetBackupState()
    isCurrentlyInBackup = false
end

return {
    validate = validate,
    markInBackup = markInBackup,
    resetBackupState = resetBackupState,

    -- Constants for validation
    MAX_MESSAGES = MAX_MESSAGES,
    MAX_PER_CHANNEL = MAX_PER_CHANNEL,
    MIN_PER_CHANNEL = MIN_PER_CHANNEL,
}
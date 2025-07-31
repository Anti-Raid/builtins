local types = require"../backups"
local conditions = require"../conditions"

-- Flag to indicate if we are currently in a backup operation
local isCurrentlyInBackup = false

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

--- Validates the backup options to ensure they are within the allowed limits.
--- This function will throw an error if the options are invalid.
--- @param data The backup options to validate
--- @return nil if the options are valid, otherwise an error is thrown
local function validate(data: types.BackupCreateOpts) 
    if data.maxMessages < 1 or data.maxMessages > conditions.MAX_MESSAGES then
        error(`maxMessages must be between 1 and {conditions.MAX_MESSAGES}, got {data.maxMessages}`)
    end

    if data.perChannel < conditions.MIN_PER_CHANNEL or data.perChannel > conditions.MAX_PER_CHANNEL then
        error(`perChannel must be between {conditions.MIN_PER_CHANNEL} and {conditions.MAX_PER_CHANNEL}, got {data.perChannel}`)
    end

    if data.perChannel > data.maxMessages then
        error(`perChannel cannot be greater than maxMessages, got perChannel={data.perChannel} and maxMessages={data.maxMessages}`)
    end

    markInBackup()
end

return {
    validate = validate,
    markInBackup = markInBackup,
    resetBackupState = resetBackupState,
}
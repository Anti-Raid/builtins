local types = require"../backups"
local conditions = require"../conditions"

-- Flag to indicate if we are currently in a backup operation
local isCurrentlyInBackup = false

--- Starts a backup operation in a scope
---
--- Rethrows any errors from the callback function
local function scope<R>(updater: types.Updater, callback: () -> R): R 
    if isCurrentlyInBackup then
        updater.setState("failed")
        error("Already in a backup operation")
    end
    isCurrentlyInBackup = true

    local ok, res = xpcall(callback, debug.traceback :: any)
    isCurrentlyInBackup = false
    if not ok then 
        -- Rethrow the error
        updater.setState("failed")
        error(res)
    end

    return res
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
end

return {
    validate = validate,
    scope = scope
}
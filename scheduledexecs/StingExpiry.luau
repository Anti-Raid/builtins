local data = require "../commands/data"

local function scheduledexec(data: data.ScheduledExecRunData) 
    local userid, stingid = data.stingManager.getStingFromScheduledExecId(data.scheduledExecId)
    if not userid or not stingid then
        return false
    end
    data.stingManager.deleteSting(userid, stingid, nil, "Sting has expired [Scheduled Sting Expiry]")
    return true
end

return {
    scheduledexec = scheduledexec,
}
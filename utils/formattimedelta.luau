local datetime = require"@antiraid/datetime"

local function formatTimeDelta(delta: datetime.TimeDelta): string
    local seconds = delta.seconds
    local minutes = math.floor(seconds / 60)
    seconds = seconds % 60

    if minutes == 0 then
        return ("%02ds"):format(seconds)
    end

    local hours = math.floor(minutes / 60)
    minutes = minutes % 60

    if hours == 0 then
        return ("%02dm %02ds"):format(minutes, seconds)
    end


    local days = math.floor(hours / 24)
    hours = hours % 24

    if days == 0 then
        return ("%02dh %02dm %02ds"):format(hours, minutes, seconds)
    end

    return ("%dd %02dh %02dm %02ds"):format(days, hours, minutes, seconds)
end

return formatTimeDelta
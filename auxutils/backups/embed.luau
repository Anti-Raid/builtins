local Primitives = require "@antiraid-core/primitives"
local apitypes = require "@discord-types/apiTypes"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local EmojiBuilder = require"@discord-types/builders/emoji"
local datetime = require"@antiraid/datetime"
local types = require"./backups"

local map = {
    running = ":hourglass_flowing_sand:",
    completed = ":white_check_mark:",
    failed = ":x:",
}

local function getIconOfState(state: string): string 
    return map[state] or map.__wildcard__
end

local function _formatValue(value: any): string
    if type(value) == "table" then
        local s = "{"

        for k, v in value do
            if type(k) == "number" then
                s ..= string.format("%s, ", _formatValue(v))
                continue
            end
            s ..= string.format("%s = %s, ", tostring(k), _formatValue(v))
        end

        -- Remove the last comma and space
        if #s > 1 then
            s = string.sub(s, 1, -3)
        end

        s ..= "}"
        return s
    elseif type(value) == "string" then
        return value
    else
        return tostring(value)
    end
end

export type Status = {
    ts: number,
    message: string
}

export type EmbedData = {
    statuses: {Status},
    state: "running" | "completed" | "failed",
    createdat: number,
    finalFilePath: string?,
    id: string,
    numUpdates: number,
}

local function backupJobToEmbed(
    ctx: Primitives.TemplateContext,
    job: EmbedData,
    showDownloadLink: boolean?
): (apitypes.EmbedObject, {apitypes.ComponentObjects})
    local jobStatuses: {string} = {}
    local jobStatusesLength = 0
    local components: {apitypes.ComponentObjects} = {}

    if #job.statuses > 0 then 
        for _, status in job.statuses do 
            if jobStatusesLength > 2500 then 
                -- Keep removing elements from start of array until we are under 2500 characters
                while jobStatusesLength > 2500 do 
                    local removed = table.remove(jobStatuses, 1)
                    jobStatusesLength -= (if removed then #removed else 0)
                end
            end

            local add = status.message

            if #add > 500 then
                add = string.sub(add, 1, 500) .. "..."
            end

            add ..= string.format(" <t:%d:R>", status.ts)

            jobStatusesLength += #add
            table.insert(jobStatuses, add)
        end
    end

    local description = string.format(
        "%s Job state: %s\nCreated at: <t:%d:R>",
        getIconOfState(job.state),
        job.state,
        job.createdat
    )

    if #jobStatuses > 0 then 
        description ..= string.format("\n\n%s", table.concat(jobStatuses, "\n"))
    end

    if showDownloadLink and job.state == "completed" and job.finalFilePath then 
        -- Create presigned URL
        local furl = ctx.ObjectStorage:get_file_url(job.finalFilePath, datetime.timedelta_minutes(5))
        description ..= string.format("\n\n[Download backup](%s)", furl)

        table.insert(
            components,
            ActionRowBuilder.new()
            :addComponent(
                ButtonBuilder.new()
                :setStyle("Blurple")
                :setLabel("Download")
                :setEmoji(
                    EmojiBuilder.new()
                    :setName("🔥")
                    :build()
                ) -- TODO: Validate this
                :setUrl(furl)
                :build()
            )
            :build() :: apitypes.ComponentObjects
        )
    end

    local embed: apitypes.EmbedObject = {
        title = "Status",
        description = description,
        color = if job.state == "completed" then 0x00FF00 else 0xFF0000, -- Green for completed, Red for failed
        footer = {
            text = "Job ID: " .. (job.id or "Unset") .. ", Num Updates = " .. job.numUpdates,
        },
    }

    return embed, components
end

export type EmbedUpdateOptions = {
    spawner: (updater: types.Updater, initial: EmbedData) -> (),
    callback: (EmbedData) -> (),
    interval: number
}

local function updateTillComplete(opts: EmbedUpdateOptions)
    local initialEmbedData: EmbedData = {
        id = "",
        createdat = os.time(),
        state = "running",
        statuses = {},
        numUpdates = 0,
    }

    -- Code to trigger a opts.callback but only if `opts.interval` seconds have passed
    local lastTriggered = os.clock()
    local function _triggerCallback() 
        local hasBeen = os.clock() - lastTriggered -- Figure out how long its been since we've last called callback
        if hasBeen < opts.interval then -- If hasBeen is less than opts.interval, start a delayed task that sets triggered to false, updates last triggered and calls the callback
            task.delay(opts.interval - hasBeen + 0.5, function() 
                local hasBeen = os.clock() - lastTriggered -- Figure out how long its been since we've last called callback
                if hasBeen < opts.interval then return end
                lastTriggered = os.clock()
                initialEmbedData.numUpdates += 1
                opts.callback(initialEmbedData)
            end)
        else -- If hasBeen is less than opts.interval, start a immediate task that sets triggered to false, updates last triggered and calls the callback
            task.spawn(function() 
                local hasBeen = os.clock() - lastTriggered -- Figure out how long its been since we've last called callback
                if hasBeen < opts.interval then return end
                lastTriggered = os.clock()
                initialEmbedData.numUpdates += 1
                opts.callback(initialEmbedData)
            end)
        end
    end

    local updater = {}
    updater.addStatus = function(s: string) 
        table.insert(initialEmbedData.statuses, { message = s, ts = os.time() })
        _triggerCallback()
    end
    updater.setState = function(state: "running" | "completed" | "failed") 
        initialEmbedData.state = state
        _triggerCallback()
    end
    updater.setId = function(id: string) 
        initialEmbedData.id = id
        _triggerCallback()
    end

    opts.spawner(updater, initialEmbedData)
    local ok, res = xpcall(opts.callback, debug.traceback :: any, initialEmbedData)
    if not ok then 
        updater.addStatus(tostring(res))
        updater.setState("failed")
    else 
        updater.setState("completed")
    end
end

return {
    backupJobToEmbed = backupJobToEmbed,
    updateTillComplete = updateTillComplete
}
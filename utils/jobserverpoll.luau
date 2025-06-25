local Primitives = require "@antiraid-core/primitives"
local dsP = require "@antiraid-core/plugins/datastores"
local apitypes = require "@discord-types/apiTypes"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"

export type PollOptions = {
    jobId: string,
    timeout_nostatuschange: number?,
    callback: (dsP.Job) -> nil,
}

local function pollJobserverTillComplete(
    ctx: Primitives.TemplateContext, 
    opts: PollOptions
)
    local jss = ctx.DataStores.JobServerStore
    if not jss then
        error("JobServerStore is not available in the context")
    end

    local currState = ""
    local currInstant = os.clock()
    local timeout = opts.timeout_nostatuschange or 500 -- Default timeout of 500 seconds
    local oldStatusLen = 0
    local oldStatus = ""
    while currState ~= "completed" and currState ~= "failed" do 
        local job = jss.get(opts.jobId)
        currState = job.state
        opts.callback(job) -- Regardless of current state, we call the callback with the job
        if currState == "completed" or currState == "failed" then
            return -- Return the job if it is completed or failed
        end

        if os.clock() - currInstant > timeout then
            error("Job polling timed out after " .. timeout .. " seconds")
        end

        if #job.statuses ~= oldStatusLen or job.state ~= oldStatus then
            oldStatusLen = #job.statuses
            oldStatus = job.state
            currInstant = os.clock() -- Reset the timer if the status has changed
        end

        task.wait(3) -- Wait 3 seconds before polling again
    end
end

local map = {
    pending = ":hourglass:",
    running = ":hourglass_flowing_sand:",
    completed = ":white_check_mark:",
    failed = ":x:",
    __wildcard__ = ":question:",
}
local function getIconOfState(state: string): string 
    return map[state] or map.__wildcard__
end

local function jobToEmbed(
    baseApiUrl: string,
    job: dsP.Job,
    showStatuses: boolean?
): (apitypes.EmbedObject, {apitypes.ComponentObjects})
    local jobStatuses: {string} = {}
    local jobStatusesLength = 0
    local components: {apitypes.ComponentObjects} = {}

    if showStatuses then 
        for _, status in job.statuses do 
            if jobStatusesLength > 2500 then 
                -- Keep removing elements from start of array until we are under 2500 characters
                while jobStatusesLength > 2500 do 
                    local removed = table.remove(jobStatuses, 1)
                    jobStatusesLength -= (if removed then #removed else 0)
                end
            end

            local add = string.format("`%s` %s", status.level, status.msg)

            -- Add extra info if available
            local vs = {}
            local bdi = (status.bot_display_ignore or {}) :: {string}

            for key, value in status.extra_info do 
                -- If not explicitly ignored from display, add it to string
                if not table.find(bdi, key) then
                    table.insert(vs, string.format("%s=%s", key, value))
                end
            end

            if #vs > 0 then
                add ..= " " .. table.concat(vs, ", ")
            end

            if #add > 500 then
                add = string.sub(add, 1, 500) .. "..."
            end

            add ..= string.format(" <t:%d:R>", status.ts)

            jobStatusesLength += #add
            table.insert(jobStatuses, add)
        end
    end

    local description = string.format(
        "%s Job state: %s\nJob ID: %s\n\n%s",
        getIconOfState(job.state),
        job.state,
        job.id,
        table.concat(jobStatuses, "\n")
    )

    if job.state == "completed" and job.output then 
        local furl = string.format("%s/jobs/%s/ioauth/download-link", baseApiUrl, job.id)
        description ..= string.format("\n\n[Download %s](%s)", job.output.filename, furl)

        table.insert(
            components,
            ActionRowBuilder.new()
            :addComponent(
                ButtonBuilder.new()
                :setStyle("Blurple")
                :setLabel("Download")
                :setEmoji("📥" :: any) -- TODO: Validate this
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
            text = "Job ID: " .. job.id,
        },
    }

    return embed, components
end

return {
    pollJobserverTillComplete = pollJobserverTillComplete,
    getIconOfState = getIconOfState,
    jobToEmbed = jobToEmbed,
}
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local promise = require "@antiraid/promise"
local datetime = require "@antiraid/datetime"
local parseunit = require "../../utils/unit"

local function register() 
    return commandBuilder.new({
        name = "remindme",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Sends a specified message to a user after a specified amount of time")
    :option(
        function(opt) 
            return opt
            :setType("String")
            :setName("message")
            :setDescription("The message to send")  
            :setRequired(true)
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("String")
            :setName("time")
            :setDescription("The amount of time to wait for")  
            :setRequired(true)
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local user = data.interaction.user
    local message: string? = nil
    local stime: number? = nil

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "message" then
            if opt.value.kind == "String" then
                message = opt.value.value
            end
        end

        if opt.name == "time" then
            if opt.value.kind == "String" then
                stime = parseunit(opt.value.value)
            end
        end
    end  

    if not user or not message or not stime then
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "Something went wrong while trying to find message and time. Please try again?",
                },
            },
            true
        )
    end

    local dt = datetime.UTC:now() + datetime.timedelta_seconds(stime)

    promise.yield(data.ge.scheduledexec:add({
        id = "remindme:" .. datetime.UTC:now().timestamp_seconds,
        data = {
            user_id = user.id,
            channel_id = data.interaction.channel_id or error("Channel ID is nil"),
            message = message,
        },
        run_at = tostring(
            dt
        ),
    }))

    return interactionutils.replySimple(
        data.ge,
        data.interaction,
        nil,
        {
            {
                title = "Created reminder",
                description = "You will be reminded at <t:" .. dt.timestamp_seconds .. ">",
            },
        },
        true
    )
end

local function scheduledexec(data: data.ScheduledExecRunData) 
    local userid = data.scheduledExecData.data.user_id
    local channelid = data.scheduledExecData.data.channel_id
    local message = data.scheduledExecData.data.message

    if not data.scheduledExecData.data.user_id or not data.scheduledExecData.data.channel_id or not message then
        return
    end

    promise.yield(data.ge.discord:create_message({
        channel_id = channelid,
        data = {
            embeds = {
                {
                    title = "Reminder",
                    description = string.format("<@%s> %s", userid, message),
                }
            } :: {apitypes.EmbedObject},
        }
    }))
end

return {
    register = register,
    run = run,
    scheduledexec = scheduledexec,
}
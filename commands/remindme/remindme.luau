local commandBuilder = require "@discord-types/builders/interaction/interaction"
local kexs = require"../../auxutils/kexs"
local apitypes = require "@discord-types/apiTypes"
local datetime = require "@antiraid/datetime"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local parseunit = require "@antiraid-ext/unit"
local isDevMode = require"../../devs".isInDevMode

local scopePrefix = if isDevMode then "builtins-dev" else "builtins"

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
    :option(
        function(opt) 
            return opt
            :setType("Boolean")
            :setName("ephemeral")
            :setDescription("Whether to make the response ephemeral or not")
            :build()
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local user = if data.interaction.member then data.interaction.member.user else data.interaction.user
    local message: string? = nil
    local stime: number? = nil
    local isResponseEphemeral = false

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

        if opt.name == "ephemeral" then
            if opt.value.kind == "Boolean" then
                isResponseEphemeral = opt.value.value
            end
        end
    end  

    if not user or not message or not stime then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "Something went wrong while trying to find message and time. Please try again?",
                },
            },
            isResponseEphemeral
        )
    end

    local dt = datetime.UTC:now() + datetime.timedelta_seconds(stime or 1)
    local key = kexs.getmanagers(data.ctx).remindmeexpiry.addat(dt, {
        userid = user.id,
        eventname = "BuiltinsReminder",
        data = {
            user_id = user.id,
            channel_id = data.interaction.channel_id or error("Channel ID is nil"),
            message = message,
            ephemeral = isResponseEphemeral,
        }
    })
    data.ctx.KV:set(key, {
        user_id = user.id,
        channel_id = data.interaction.channel_id or error("Channel ID is nil"),
        message = message,
        ephemeral = isResponseEphemeral,
    }, {scopePrefix .. ".remindme"})

    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Created reminder",
                description = "You will be reminded at <t:" .. dt.timestamp_seconds .. ">",
            },
        },
        isResponseEphemeral
    )
end

local function keyexpiries(data: data.KeyExpiryData) 
    -- Allow immediate expiry in dev mode for testing
    local kvr = data.ctx.KV:getrecord(data.data.key, {scopePrefix .. ".remindme"})
    if not kvr or not kvr.exists then
        error("Key not found or expired: " .. data.data.key)
        return
    end

    local userid = kvr.value.user_id
    local channelid = kvr.value.channel_id
    local message = kvr.value.message

    if not userid or not channelid or not message then
        return
    end

    data.ctx.Discord:create_message({
        channel_id = channelid,
        data = {
            embeds = {
                {
                    title = "Reminder",
                    description = string.format("<@%s> %s", userid :: any, message :: any),
                }
            } :: {apitypes.EmbedObject},
        }
    })
end

return {
    register = register,
    run = run,
    keyexpiries = {[scopePrefix .. ".remindme"] = keyexpiries},
}
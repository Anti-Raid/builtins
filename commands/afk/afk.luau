local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local datetime = require "@antiraid/datetime"
local parseunit = require "@antiraid-ext/unit"
local AFKManager = require "../../auxutils/afkmanager"
local registerEvent = require "@antiraid-ext/utils/eventmgmt".registerEvent

local function register() 
    return commandBuilder.new({
        name = "afk",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Set yourself as AFK")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("start")
            :setDescription("Start being AFK")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("The message to send when users try to interact with you")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("time")
                    :setDescription("How long you want to be AFK for")  
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
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("stop")
            :setDescription("Stop being AFK")  
            :build()
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "start" then
        local user = data.interaction.user
        local reason: string? = nil
        local stime: number? = nil
        local isResponseEphemeral = false

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
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

        if not user or not reason or not stime then
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

        AFKManager(data.ctx).set({
            user_id = user.id,
            reason = reason or "No reason provided",
            duration = datetime.timedelta_seconds(stime or 1),
        })

        registerEvent(data.ctx, "MESSAGE")

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "AFK Set",
                    description = "Enjoy the peace and quiet!",
                },
            },
            isResponseEphemeral
        )
    elseif cmdname == "stop" then
        local user = data.interaction.user
        if not user then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find user. Please try again?",
                    },
                },
                true
            )
        end

        local afk = AFKManager(data.ctx).get(user.id)
        if not afk then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "You are not AFK",
                        description = "You are not AFK, so you cannot stop being AFK.", 
                    },
                },
                true
            )
        end

        AFKManager(data.ctx).delete(user.id)
        
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "AFK Stopped",
                    description = "You are no longer AFK. Welcome back!",
                },
            },
            true
        )
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

--[[
local function keyexpiries(data: data.KeyExpiryData) 
    local kvr = data.ctx.KV:getrecord(data.data.key, {"builtins.remindme"})
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
]]

return {
    register = register,
    run = run,
    --keyexpiries = {["builtins.afks"] = keyexpiries},
}
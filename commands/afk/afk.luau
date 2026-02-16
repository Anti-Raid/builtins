local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local datetime = require "@antiraid/datetime"
local parseunit = require "@antiraid-ext/unit"
local managers = require "../../auxutils/managers/managers"

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
    local afkmanager = managers.getmanagers(data.ctx).afkmanager

    if cmdname == "start" then
        local user = if data.interaction.member then data.interaction.member.user else data.interaction.user
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
                        color = 0xff0000, -- Red color
                    },
                },
                isResponseEphemeral
            )
        end

        afkmanager.set({
            user_id = user.id,
            reason = reason or "No reason provided",
            duration = datetime.timedelta_seconds(stime or 1),
        })

        data.loop.subscribeEvent("MESSAGE", "afk")

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "AFK Set",
                    description = "Enjoy the peace and quiet!",
                    color = 0x00ff00, -- Green color
                },
            },
            isResponseEphemeral
        )
    elseif cmdname == "stop" then
        local user = if data.interaction.member then data.interaction.member.user else data.interaction.user
        if not user then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find user. Please try again?",
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        end

        local afk = afkmanager.get(user.id)
        if not afk then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "You are not AFK",
                        description = "You are not AFK, so you cannot stop being AFK.", 
                        color = 0xff0000, -- Red color
                    },
                },
                true
            )
        end

        afkmanager.delete(user.id)
        
        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "AFK Stopped",
                    description = "You are no longer AFK. Welcome back!",
                    color = 0x00ff00, -- Green color
                },
            },
            true
        )

        -- Unsubscribe if no more afks
        --
        -- TODO: Optimize this by adding a count() api to AntiRaid runtime that can be used here instead of fetching all afks and counting them
        local afks = afkmanager.list()
        if #afks == 0 then
            data.loop.unsubscribeEvent("MESSAGE", "afk")
        end

        return nil
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

return {
    register = register,
    run = run,
}
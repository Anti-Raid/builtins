local commandBuilder = require "@discord-types/builders/interaction/interaction"
local context = require"@antiraid-ext/frameworkv2/context"
local datetime = require "@antiraid/datetime"
local parseunit = require "@antiraid-ext/unit"
local managers = require "../../auxutils/managers/managers"

local command = commandBuilder.new({
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

local function run(data: context.CommandContext): nil
    local cmdname = data.command.nameList[2]
    local afkmanager = managers.getmanagers(data.framework.ctx).afkmanager

    if cmdname == "start" then
        local user = data.interaction.user()
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
            data.interaction.reply{
                embeds = {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find message and time. Please try again?",
                        color = 0xff0000, -- Red color
                    },
                },
                ephemeral = isResponseEphemeral
            }
            return nil
        end

        afkmanager.set({
            user_id = user.id,
            reason = reason or "No reason provided",
            duration = datetime.timedelta_seconds(stime or 1),
        })

        data.framework.loop.subscribeEvent("MESSAGE", "afk")

        data.interaction.reply{
            embeds = {
                {
                    title = "AFK Set",
                    description = "Enjoy the peace and quiet!",
                    color = 0x00ff00, -- Green color
                },
            },
            ephemeral = isResponseEphemeral
        }
        return nil
    elseif cmdname == "stop" then
        local user = data.interaction.user()
        if not user then
            data.interaction.reply{
                embeds = {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find user. Please try again?",
                        color = 0xff0000, -- Red color
                    },
                },
                ephemeral = true
            }
            return nil
        end

        local afk = afkmanager.get(user.id)
        if not afk then
            data.interaction.reply{
                embeds = {
                    {
                        title = "You are not AFK",
                        description = "You are not AFK, so you cannot stop being AFK.", 
                        color = 0xff0000, -- Red color
                    },
                },
                ephemeral = true
            }
            return nil
        end

        afkmanager.delete(user.id)

        data.interaction.reply{
            embeds = {
                {
                    title = "AFK Stopped",
                    description = "You are no longer AFK. Welcome back!",
                    color = 0x00ff00, -- Green color
                },
            },
            ephemeral = true
        }
        
        -- Unsubscribe if no more afks
        if afkmanager.count() == 0 then
            data.framework.loop.unsubscribeEvent("MESSAGE", "afk")
        end

        return nil
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

return {
    command = command,
    run = run,
}
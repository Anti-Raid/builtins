local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local datastores = require"@antiraid/datastores"
local promise = require("@antiraid/promise")
local datetime = require("@antiraid/datetime")
local formatTimeDelta = require "@antiraid-ext/formattimedelta"

local function register() 
    return commandBuilder.new({
        name = "moderation",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Moderation related commands")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("ban")
            :setDescription("Ban a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to ban")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for the ban")  
                    :setRequired(true)
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("stings")
                    :setDescription("Number of stings to give")  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("delete_message_days")
                    :setDescription("Number of days to prune messages for. Mutually exclusive with delete_message_seconds")  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("delete_message_seconds")
                    :setDescription("Number of seconds to prune messages for. Mutually exclusive with delete_message_days")  
                    :build()
                end
            )
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "ban" then
        
    else 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "Unknown subcommand",
                },
            },
            false
        )
    end
    return nil
end

return {
    register = register,
    run = run,
}
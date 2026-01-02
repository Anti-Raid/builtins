local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local ban = require "./ban"
local unban = require "./unban"
local kick = require "./kick"

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
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("duration")
                    :setDescription("How long should the user be banned for")
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
            :setName("unban")
            :setDescription("Unbans a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to unban")
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
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("kick")
            :setDescription("Kick a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to kick")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for kicking the user")  
                    :setRequired(true)
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

    if cmdname == "ban" then return ban(data) 
    elseif cmdname == "unban" then return unban(data)
    elseif cmdname == "kick" then return kick(data)
    else 
        return interactionutils.replySimple(
            data.ctx,
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
end

return {
    register = register,
    run = run,
}
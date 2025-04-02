local commandBuilder = require "@discord-types/builders/interaction/interaction"
--local commandOptionBuilder = require "@discord-types/builders/interaction/option"
local data = require "../data"

local function register() 
    return commandBuilder.new({
        name = "whois",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Provides basic information about a user")
    :option(
        function(opt) 
            return opt
            :setType("User")
            :setName("code")
            :setDescription("The code to evaluate")  
            :build()      
        end
    ) 
end

local function run(data: data.RunData) 
    data.ge.discord:create_message({
        channel_id = data.interaction.channel_id or error("no channel id"),
        data = {
            content = "pong",
        },
    })
end

return {
    register = register,
    run = run,
}
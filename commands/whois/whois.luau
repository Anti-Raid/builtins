local commandBuilder = require "@discord-types/builders/interaction/interaction"
--local commandOptionBuilder = require "@discord-types/builders/interaction/option"
local data = require "../data"
local interactionutils = require "../../utils/interaction"

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
    :build()
end

local function run(data: data.RunData) 
    interactionutils.replySimple(
        data.ge,
        data.interaction,
        "pong",
        nil,
        true
    )
end

return {
    register = register,
    run = run,
}
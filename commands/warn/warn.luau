local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local canModeratorAffectTarget = require "../../utils/modhierarchy".canModeratorAffectTarget

local function register() 
    return commandBuilder.new({
        name = "warn",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Stings/warns a user with a specified number of stings")
    :option(
        function(opt) 
            return opt
            :setType("User")
            :setName("user")
            :setDescription("The user to sting")  
            :setRequired(true)
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("Number")
            :setName("stings")
            :setDescription("The number of stings to give")  
            :setRequired(true)
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("String")
            :setName("reason")
            :setDescription("The reason to sting the user")  
            :setRequired(true)
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local user = nil
    local numberOfStings: number? = nil
    local reason: string? = nil

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "user" then 
            if opt.value.kind == "User" then
                user = opt.value.user
            end
        elseif opt.name == "stings" then
            if opt.value.kind == "Number" then
                numberOfStings = opt.value.value
            end
        elseif opt.name == "reason" then
            if opt.value.kind == "String" then
                reason = opt.value.value
            end
        end
    end
    
    if not user then 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "No user specified",
                    description = "Please specify a user to sting",
                },
            },
            false
        )
    end

    if not numberOfStings then 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "No number of stings specified",
                    description = "Please specify a number of stings to give",
                },
            },
            false
        )
    end

    if not reason then 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "No reason specified",
                    description = "Please specify a reason for the sting",
                },
            },
            false
        )
    end

    local modid = if data.interaction.user then data.interaction.user.id else nil

    if not modid then
        error("Moderator ID is nil")
    end

    canModeratorAffectTarget(data.ge, modid, user.id, "moderation.warn")

    data.stingManager.createUserSting({
        userId = user.id,
        modId = modid,
        reason = reason,
        stings = numberOfStings,
    })

    return interactionutils.replySimple(
        data.ge,
        data.interaction,
        nil,
        {
            {
                title = "Sting created",
                description = `Successfully stung {user.username} with \`\`{numberOfStings}\`\` for: \`\`{reason}\`\``,
            },
        },
        false
    )

    -- TODO: Support a log channel here
end

return {
    register = register,
    run = run,
}
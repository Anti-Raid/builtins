local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"

local function register() 
    return commandBuilder.new({
        name = "stings",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Shows all stings a user has")
    :option(
        function(opt) 
            return opt
            :setType("User")
            :setName("user")
            :setDescription("The user to lookup")  
            :setRequired(false)
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local user = data.interaction.user

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "user" then 
            if opt.value.kind == "User" then
                user = opt.value.user
            end
        end
    end
    
    local userid = if user then user.id else nil

    if not userid then
        error("User ID is nil")
    end

    local stings = data.stingManager.getStingsOnUser(userid)

    local stingEmbeds = {}
    for _, sting in stings do
        local fields = {
            { name = "Sting Count", value = tostring(sting.stings), inline = true },
            { name = "Moderator", value = if sting.modId then "<@" .. sting.modId .. ">" else "System", inline = true },
            { name = "Creation Date", value = "<t:" .. sting.created_at.timestamp_seconds .. ">", inline = true },
        }

        if #stings < 5 then 
            local _, stingExpiry = data.stingManager.getStingExpiration(sting.userId, sting.stingId)
            if stingExpiry then 
                table.insert(fields, {
                    name = "Sting Expiry",
                    value = "<t:" .. stingExpiry.timestamp_seconds .. ">",
                    inline = true,
                })
            else
                table.insert(fields, {
                    name = "Sting Expiry",
                    value = "Never",
                    inline = true,
                })
            end
        end

        local embed = {
            title = `Sting {sting.stingId}`,
            description = sting.reason,
            fields = fields,
        }

        table.insert(stingEmbeds, embed)
    end

    if #stingEmbeds == 0 then
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "No stings found",
                    description = `No stings found for <@{userid}>`,
                }
            },
            false
        )
    else
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            stingEmbeds,
            false
        )
    end
end

return {
    register = register,
    run = run,
}
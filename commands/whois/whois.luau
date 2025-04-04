local commandBuilder = require "@discord-types/builders/interaction/interaction"
--local commandOptionBuilder = require "@discord-types/builders/interaction/option"
local data = require "../data"
local apiTypes = require "@discord-types/apiTypes"
local interactionutils = require "../../utils/interaction"
local avatarUrl = require "../../utils/avatar".avatarUrl
local promise = require "@antiraid/promise"
local userinfoplugin = require "@antiraid/userinfo"
local kc = require "@antiraid-core/kittycat"

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
            :setName("user")
            :setDescription("The user to get information about")  
            :build()      
        end
    )
    :build()
end

-- TODO: Spruce this up with more information (e.g. what permissions they have etc)
local function run(data: data.RunData) 
    local user = data.interaction.user

    local userOpt = data.command.options[1]
    if userOpt then 
        if userOpt.value.kind == "User" then
            user = userOpt.value.user
        end
    end

    if not user then 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                title = "Error looking up user",
                description = "Something went wrong while trying to find the user. Please try again?",
            },
            true
        )
    end

    assert(user, "User cannot be nil at this point")

    local userinfook, userinfo = pcall(promise.yield, data.ge.userinfo:get(user.id))

    local baseFields = {
        {
            name = "User ID",
            value = user.id,
            inline = true,
        },
        {
            name = "Username",
            value = user.username,
            inline = true,
        }
    }

    if user.discriminator and user.discriminator ~= "0" then
        table.insert(baseFields, {
            name = "Discriminator",
            value = user.discriminator,
            inline = true,
        })
    end

    if userinfook then 
        userinfo = userinfo :: userinfoplugin.UserInfo

        local resolvedPerms = {}
        for _, perm in userinfo.kittycat_resolved_permissions do 
            table.insert(resolvedPerms, "``" .. tostring(kc.Permission.from_tab(perm)) .. "``")
        end

        local permsList: string = table.concat(resolvedPerms, ", ")

        if string.len(permsList) > 1024 then
            permsList = string.sub(permsList, 1, 1024) .. "..."
        end

        table.insert(baseFields, {
            name = "Resolved Permissions",
            value = permsList,
            inline = true,
        })
    end

    local avatarUrl = avatarUrl(user)
    return interactionutils.replySimple(
        data.ge,
        data.interaction,
        nil,
        {
            {
                title = "User Information",
                description = "Here is the information AntiRaid has found about the user",
                fields = baseFields,    
                thumbnail = {
                    url = avatarUrl,
                },
            }
        } :: {apiTypes.EmbedObject},
        true
    )
end

return {
    register = register,
    run = run,
}
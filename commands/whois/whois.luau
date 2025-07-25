local commandBuilder = require "@discord-types/builders/interaction/interaction"
--local commandOptionBuilder = require "@discord-types/builders/interaction/option"
local data = require"@antiraid-ext/framework/coretypes"
local apiTypes = require "@discord-types/apiTypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local avatarUrl = require "@antiraid-ext/utils/avatar".avatarUrl
local stingmanager = require("@antiraid-ext/utils/stingmanager")
local kc = require "@antiraid-core/kittycat"
local permissions = require "@discord-types/permission"
local permissionsFromBf = permissions.fromBitFlag
local userinfoplugin = require "@antiraid-ext/utils/userinfo"

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

local function dangerousPerms(discordPerms: {permissions.Permissions}): {permissions.Permissions} 
    local dangerPermsFound = {}
    for _, perm in discordPerms do
        if perm == "Administrator"
        or perm == "BanMembers"
        or perm == "KickMembers"
        or perm == "ManageChannels"
        or perm == "ManageGuild"
        or perm == "ManageRoles"
        or perm == "ManageMessages"
        or perm == "ManageNicknames"
        or perm == "ManageWebhooks"
        or perm == "ManageEmojisAndStickers" -- TODO: Rethink ManageEmojisAndStickers being dangerous
        or perm == "ManageEvents"
        or perm == "ManageThreads"
        or perm == "MentionEveryone"
        or perm == "ModerateMembers"
        then
            table.insert(dangerPermsFound, perm)
        end
    end

    return dangerPermsFound
end

-- TODO: Spruce this up with more information (e.g. what permissions they have etc)
local function run(data: data.RunData) 
    local user = if data.interaction.member then data.interaction.member.user else data.interaction.user
    local isResponseEphemeral = false

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "user" then 
            if opt.value.kind == "User" then
                user = opt.value.user
            elseif opt.value.kind == "Unresolved" then
                local userid = opt.value.id
                user = data.ctx.Discord:get_guild_member(userid).data.user
            end
        elseif opt.name == "ephemeral" then
            if opt.value.kind == "Boolean" then
                isResponseEphemeral = opt.value.value
            end
        end
    end

    if not user then 
        error("HERE")
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Error looking up user",
                    description = "Something went wrong while trying to find the user. Please try again?",
                }
            },
            true
        )
    end

    assert(user, "User cannot be nil at this point")

    local userinfook, userinfo = pcall(data.userinfomanager.get, user.id, data.interaction)

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

        -- Add in resolved antiraid permissions
        local resolvedPerms = {}
        for _, perm in userinfo.kittycat_resolved_permissions do 
            table.insert(resolvedPerms, "``" .. tostring(kc.Permission.from_tab(perm)) .. "``")
        end

        if #resolvedPerms > 0 then
            local permsList: string = table.concat(resolvedPerms, ", ")

            -- Limit to 1024 characters
            if string.len(permsList) > 1024 then
                permsList = string.sub(permsList, 1, 1024) .. "..."
            end

            -- Add
            table.insert(baseFields, {
                name = "Anti-Raid Permissions",
                value = permsList,
                inline = true,
            })
        end

        -- Add in discord permissions as a string
        local discordPerms = permissionsFromBf(userinfo.discord_permissions)

        if #discordPerms > 0 then
            local dangerPermsFound = dangerousPerms(discordPerms)

            if #dangerPermsFound > 0 then
                local dangerPermsList: string = "- " .. table.concat(dangerPermsFound, "\n- ")

                -- Limit to 800 characters
                if string.len(dangerPermsList) > 800 then
                    dangerPermsList = string.sub(dangerPermsList, 1, 800) .. "..."
                end

                table.insert(baseFields, {
                    name = "Dangerous Permissions",
                    value = dangerPermsList,
                    inline = false,
                })
            else
                table.insert(baseFields, {
                    name = "Dangerous Permissions",
                    value = ":white_check_mark: None",
                    inline = false,
                })
            end
        else 
            table.insert(baseFields, {
                name = "Dangerous Permissions",
                value = ":white_check_mark: None",
                inline = false,
            })
        end
    end

    local stings = data.stingManager.getCachedUserStings(user.id)
    local stingCount = 0
    local maxSting: stingmanager.Sting? = nil
    local mostRecentSting: stingmanager.Sting? = nil
    if stings then 
        for _, sting in stings do
            stingCount += sting.stings
            if not maxSting or sting.stings > maxSting.stings then
                maxSting = sting
            end

            if not mostRecentSting or sting.created_at > mostRecentSting.created_at then
                mostRecentSting = sting
            end
        end
    end

    if stingCount > 0 then
        table.insert(baseFields, {
            name = "Sting Count",
            value = tostring(stingCount),
            inline = true,
        })
    end

    if maxSting then
        table.insert(baseFields, {
            name = "Max Sting",
            value = data.stingManager.stingCompactString(maxSting),
            inline = true,
        })
    end

    if mostRecentSting then
        table.insert(baseFields, {
            name = "Most Recent Sting",
            value = data.stingManager.stingCompactString(mostRecentSting),
            inline = true,
        })
    end

    local avatarUrl = avatarUrl(user)
    return interactionutils.replySimple(
        data.ctx,
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
        isResponseEphemeral
    )
end

return {
    register = register,
    run = run,
}
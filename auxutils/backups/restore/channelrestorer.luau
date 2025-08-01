local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"
local permissions = require"@discord-types/permission"
local types = require"../backups"

--- Given a channel to restore and other ext data, create a resttypes.CreateGuildChannelRequest
local function createChannelData(
    channel: apitypes.ChannelObject, 
    restoredRoles: {[string]: apitypes.GuildRoleObject}, -- map of the old role ID to the new role object
    restoredChannels: {[string]: apitypes.ChannelObject}, -- map of the old channel ID to the new channel object
    srcGuildId: string, 
    targetGuildId: string,
    protectedRoles: {string},
    protectedChannels: {string},
    updater: types.Updater
): resttypes.CreateGuildChannelRequest
    -- Fix permission overwrites
    local permOverwrites: {apitypes.OverwriteObject} = table.create(#channel.permission_overwrites) :: {apitypes.OverwriteObject}

    for _, overwrite in channel.permission_overwrites do 
        if overwrite.type == permissions.OverwriteObjectTypeRole then 
            if overwrite.id == srcGuildId then
                -- Special case: @everyone role of source guild
                table.insert(permOverwrites, {
                    type = overwrite.type,
                    allow = overwrite.allow,
                    deny = overwrite.deny,
                    id = targetGuildId
                })
            elseif restoredRoles[overwrite.id] then 
                -- Case: Role in source guild restored to target
                table.insert(permOverwrites, {
                    type = overwrite.type,
                    allow = overwrite.allow,
                    deny = overwrite.deny,
                    id = restoredRoles[overwrite.id].id
                })
            elseif table.find(protectedRoles, overwrite.id) then
                table.insert(permOverwrites, overwrite) -- Protected role
            end
        else
            table.insert(permOverwrites, overwrite)
        end
    end

    local parentId = nil
    if channel.parent_id then 
        if table.find(protectedChannels, channel.parent_id) then
            parentId = channel.parent_id
        elseif restoredChannels[channel.parent_id] then
            parentId = restoredChannels[channel.parent_id].id
        else 
            updater.addStatus(`Parent channel could not be found while processing update data for channel \`\`{channel.id}\`\` and name \`\`{channel.name}\`\``)
        end
    end

    return {
        name = channel.name,
        type = channel.type,
        topic = channel.topic,
        user_limit = channel.user_limit,
        rate_limit_per_user = channel.rate_limit_per_user,
        position = channel.position,
        permission_overwrites = permOverwrites,
        parent_id = parentId,
        nsfw = channel.nsfw,
        default_thread_rate_limit_per_user = channel.default_thread_rate_limit_per_user,
    }
end

return createChannelData
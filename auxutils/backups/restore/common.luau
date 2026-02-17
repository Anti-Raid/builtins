local Primitives = require"@antiraid-core/primitives"
local types = require"../backups"
local load = require"./load"
local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"
local blob = require"@antiraid-core/blob"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local typesext = require"@antiraid/typesext"
local compare = require"@antiraid-ext/utils/rolecmp"
local discord = require"@antiraid-core/plugins/discord"
local permission = require"@discord-types/permission"

export type PermData = {
    currentBotMember: apitypes.GuildMemberObject,
    currentGuild: apitypes.GuildObject,
}

export type WebhookData = {
    webhookid: string,
    webhooktoken: string,
}

export type GuildFlags = {
    community: boolean,
    animated_icon: boolean,
    banner: boolean,
    animated_banner: boolean,
    invite_splash: boolean
}

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
        if overwrite.type == permission.OverwriteObjectTypeRole then 
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

--- Partial restore manager
export type BaseRestoreManager = {
    --- Returns the loaded backup
    getLoadedBackup: () -> types.LoadedBackup,
    --- Returns the current guild data, including current guild object and flags
    ---
    --- # Guarantees
    --- 1. Returned currentGuild.roles will always be sorted in hierarchy order (highest role first)
    --- 2. currentGuild will always have the roles field populated (either from the initial guild object or from an additional API call if it was not included in the initial get_guild response)
    --- 3. currentBotMember will always be included and valid
    getCurrentGuildData: () -> IGuildData,
    --- Validates the backup's compatibility with the current guild and returns the current guild data
    ---
    --- For example, if the backup was taken from a community guild but the current guild is not a community guild, then this function will throw an error as the backup is not compatible with the current guild. 
    ---
    --- This is to prevent users from accidentally restoring incompatible backups which can lead to errors during restores/partial restores
    validateBackupCompatibility: () -> (),
    --- Returns the highest role of the bot in the guild
    getBotHighestRole: () -> apitypes.GuildRoleObject,
    --- Restores a single role to the guild and returns the new role object
    createGuildRole: (role: apitypes.GuildRoleObject, guildData: IGuildData, discordCreateRolesExecutor: discord.DiscordExecutor) -> apitypes.GuildRoleObject,
    --- Returns if a role is protected from being restored
    isRoleProtected: (role: apitypes.GuildRoleObject, guildData: IGuildData) -> boolean,
    --- Restores the base guild settings from the backup
    restoreBaseGuildSettings: () -> (),
}

type IGuildData = {
    currentGuild: apitypes.GuildObject,
    currentGuildFlags: GuildFlags,
    currentBotMember: apitypes.GuildMemberObject,
    basePerms: typesext.U64,
}

--- Sets up a partial restore manager for restoring bits and pieces of a backup
local function BaseRestoreManager(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, updater: types.Updater, opts: types.BackupRestoreOpts): BaseRestoreManager
    local loadedBackup = load.loadBackupFile(ctx, src, enckey, updater)
    local coreData = loadedBackup.core
    local cachedGuildData: IGuildData? = nil
    
    local self = {}

    -- Helper method to get current guild data
    local function getCurrentGuildData() 
        if cachedGuildData then 
            return cachedGuildData
        end

        -- Test if coreData is valid    
        assert(coreData.guild.id and #coreData.guild.id > 0, "internal error: guild ID must be set in core data")

        local currentGuild = ctx.Discord:get_guild().data

        local currentGuildFlags: GuildFlags = {
            community = false,
            banner = false,
            animated_banner = false,
            animated_icon = false,
            invite_splash = false
        }

        -- Collect features
        if currentGuild.features then 
            for _, feature in currentGuild.features do 
                if feature == "COMMUNITY" then currentGuildFlags.community = true end
                if feature == "ANIMATED_ICON" then currentGuildFlags.animated_icon = true end
                if feature == "BANNER" then currentGuildFlags.banner = true end
                if feature == "ANIMATED_BANNER" then currentGuildFlags.animated_banner = true end
                if feature == "INVITE_SPLASH" then currentGuildFlags.invite_splash = true end
            end
        end

        local currentBotMember = ctx.Discord:get_guild_member(ctx.current_user.id).data
        if not currentBotMember then
            error("Cannot restore backup: bot is not a member of the guild")
        end

        if not currentGuild.roles or #currentGuild.roles == 0 then 
            local roles = ctx.Discord:get_guild_roles().data
            local rolesArr = {}
            for _, role in roles do table.insert(rolesArr, role) end
            currentGuild.roles = rolesArr
        end

        assert(currentGuild.roles, "internal error: guild roles must be loaded before restoring backup")

        compare.SortRolesByHierarchyDesc(currentGuild.roles) -- Sort current roles in hierarchy order

        local basePerms = discordpermcalc.BasePermissions(currentGuild, currentBotMember)
        
        local guild: IGuildData = {
            currentGuild = currentGuild,
            currentGuildFlags = currentGuildFlags,
            currentBotMember = currentBotMember,
            basePerms = basePerms,
        }

        cachedGuildData = guild
        return guild
    end

    local function validateBackupCompatibility() 
        local currentGuildData = getCurrentGuildData()

        local guildWasCommunity = coreData.guild.features and table.find(coreData.guild.features, "COMMUNITY" :: "COMMUNITY") ~= nil
        if guildWasCommunity and not currentGuildData.currentGuildFlags.community then
            error("Cannot restore a community guild backup to a non-community guild. Please enable the community features in your guild settings.")
        end
    end

    --- Returns the highest role of the bot in the guild
    local function getBotHighestRole() 
        local guildData = getCurrentGuildData()

        -- Find the highest role in the user's member roles
        local highestRole = nil

        local guildRolesMap = {}
        assert(guildData.currentGuild.roles, "internal error: guild roles must be loaded before restoring backup")
        for _, role in guildData.currentGuild.roles do
            guildRolesMap[role.id] = role
        end

        for _, memberRoleId in guildData.currentBotMember.roles do 
            local role = guildRolesMap[memberRoleId]
            if not role then
                continue -- Skip roles that are not present in guild_roles
            end

            if not highestRole or compare.IsRoleAGreaterThanRoleB(role :: apitypes.GuildRoleObject, highestRole) then
                highestRole = role :: apitypes.GuildRoleObject
            end
        end

        -- Check highest role
        assert(highestRole, "Bot does not have any roles in the guild")

        return highestRole
    end

    local function getLoadedBackup()
        return loadedBackup
    end

    -- Restore the base guild settings from the backup
    local function restoreBaseGuildSettings() 
        -- Note: verification_level and explicit_content_filter are not restored for now
        -- and owner, region can't be restored
        local desc = coreData.guild.description
        if desc and #desc > 300 then
            desc = desc:sub(1, 300)
            updater.addStatus("Guild description is longer than 300 characters, truncating to 300 characters")
        end
        local updateData: resttypes.ModifyGuildRequest = {
            name = coreData.guild.name,
            description = desc,
            default_message_notifications = coreData.guild.default_message_notifications,
            system_channel_flags = coreData.guild.system_channel_flags,
            afk_timeout = coreData.guild.afk_timeout,
        }

        local icon = loadedBackup.assets["icon"] :: blob.Blob?
        if icon then
            updateData.icon = load.assetToDataURL("image/jpeg", icon)
        end

        local banner = loadedBackup.assets["banner"] :: blob.Blob?
        if banner then
            updateData.banner = load.assetToDataURL("image/jpeg", banner)
        end

        local splash = loadedBackup.assets["splash"] :: blob.Blob?
        if splash then
            updateData.splash = load.assetToDataURL("image/jpeg", splash)
        end

        ctx.Discord:modify_guild({
            reason = "Restore backup: Restore base guild settings step",
            data = updateData
        })
    end

    local function createGuildRole(role: apitypes.GuildRoleObject, guildData: IGuildData, discordCreateRolesExecutor: discord.DiscordExecutor)
        -- Ensure role permissions meet our bots permissions
        if not discordpermcalc.HasPermission(guildData.basePerms, role.permissions) then 
            -- If the role permissions are not allowed by the bot, then do not set any role permissions
            --
            -- TODO: Perform granular disabling of permissions we don't have
            role.permissions = "0"
        end

        -- TODO: Support role icons/role emojis later
        local roleUpdate: resttypes.CreateGuildRoleRequest = {
            name = role.name,
            color = role.color,
            hoist = role.hoist,
            permissions = role.permissions,
            mentionable = role.mentionable,
        }

        return discordCreateRolesExecutor:create_guild_role({
            reason = "Backup restore: Create roles step",
            data = roleUpdate,
        }).data
    end

    local function isRoleProtected(role: apitypes.GuildRoleObject, guildData: IGuildData)
        if role.managed -- Managed role
        or role.id == guildData.currentGuild.id -- @everyone
        or table.find(opts.protectedRoles, role.id) -- Protected role
        or role.position <= 0 -- Invalid role
        then 
            return true
        end
        return false
    end

    self.getLoadedBackup = getLoadedBackup
    self.getCurrentGuildData = getCurrentGuildData
    self.validateBackupCompatibility = validateBackupCompatibility
    self.getBotHighestRole = getBotHighestRole
    self.restoreBaseGuildSettings = restoreBaseGuildSettings
    self.createGuildRole = createGuildRole
    self.isRoleProtected = isRoleProtected

    return self
end

return table.freeze{
    BaseRestoreManager = BaseRestoreManager,
    createChannelData = createChannelData
}
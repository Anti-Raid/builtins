local Primitives = require"@antiraid-core/primitives"
local types = require"../backups"
local load = require"./load"
local apitypes = require"@discord-types/apiTypes"
local channel = require"@discord-types/channel"
local resttypes = require"@discord-types/restTypes"
local blob = require"@antiraid-core/blob"
local restore = require"./restore"

--- Partial restore manager
export type PartialRestoreManager = {
    --- Restores the base guild settings from the backup
    restoreBaseGuildSettings: () -> (),
    --- Restores a single channel from the backup (with messages optionally restored)
    ---
    --- Does not delete any existing channels, just creates a new one with the same settings and tries restoring messages if requested
    ---
    --- The restored channel will be restored to inCategory if provided
    restoreChannel: (channelid: string, restoreMessages: boolean, inCategory: string?) -> apitypes.ChannelObject?,
}

type IGuildData = {
    currentGuild: apitypes.GuildObject,
    currentGuildFlags: restore.GuildFlags,
}

--- Given a channel to restore and other ext data, create a resttypes.CreateGuildChannelRequest for a partial channel restore
local function createChannelDataForPartialChannelRestore(
    channel: apitypes.ChannelObject, 
    parentId: string?
): resttypes.CreateGuildChannelRequest
    -- Fix permission overwrites
    local permOverwrites: {apitypes.OverwriteObject} = table.create(#channel.permission_overwrites) :: {apitypes.OverwriteObject}

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

--- Sets up a partial restore manager for restoring bits and pieces of a backup
local function PartialRestoreManager(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, updater: types.Updater): PartialRestoreManager
    local loadedBackup = load.loadBackupFile(ctx, src, enckey, updater)
    local coreData = loadedBackup.core
    local cachedGuildData: IGuildData? = nil

    local self = {} :: PartialRestoreManager

    -- Helper method to get current guild data
    local function _getCurrentGuildData() 
        if cachedGuildData then 
            return cachedGuildData
        end

        -- Test if coreData is valid    
        assert(coreData.guild.id and #coreData.guild.id > 0, "internal error: guild ID must be set in core data")

        local guildWasCommunity = coreData.guild.features and table.find(coreData.guild.features, "COMMUNITY" :: "COMMUNITY") ~= nil

        local currentGuild = ctx.Discord:get_guild().data

        local currentGuildFlags: restore.GuildFlags = {
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
        
        if guildWasCommunity and not currentGuildFlags.community then
            error("Cannot restore a community guild backup to a non-community guild. Please enable the community features in your guild settings.")
        end

        local guild: IGuildData = {
            currentGuild = currentGuild,
            currentGuildFlags = currentGuildFlags,
        }

        cachedGuildData = guild
        return guild
    end

    -- Restore the base guild settings from the backup
    local function restoreBaseGuildSettings() 
        updater.addStatus("Restoring guild data...")

        -- Note: verification_level and explicit_content_filter are not restored for now
        -- and owner, region can't be restored
        local updateData: resttypes.ModifyGuildRequest = {
            name = coreData.guild.name,
            description = coreData.guild.description,
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
            reason = "Partial restore of base guild settings from backup",
            data = updateData
        })

        updater.addStatus("Done modifying basic server settings")
    end

    -- See PartialRestoreManager type definition for docs
    local function restoreChannel(channelid: string, restoreMessages: boolean, inCategory: string?): apitypes.ChannelObject?
        local createdChannel: apitypes.ChannelObject? = nil
        for _, c in coreData.channels do 
            if c.id ~= channelid then 
                continue -- Skip non-category channels if we are restoring categories only
            end

            local ud = createChannelDataForPartialChannelRestore(c, inCategory)

            updater.addStatus("Creating channel ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")


            createdChannel = ctx.Discord:create_guild_channel({
                reason = "Backup restore: Create channels step",
                data = ud,
            }).data

            updater.addStatus("Created channel ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
        end

        return createdChannel
    end

    self.restoreBaseGuildSettings = restoreBaseGuildSettings
    self.restoreChannel = restoreChannel

    return self
end

return {
    PartialRestoreManager = PartialRestoreManager,
}
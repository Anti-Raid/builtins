local Primitives = require"@antiraid-core/primitives"
local types = require"../backups"
local load = require"./load"
local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"
local blob = require"@antiraid-core/blob"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission" 
local common = require"./common"

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

--- Partial restore manager
export type PartialRestoreManager = {
    --- Returns the base restore manager
    getBaseManager: () -> common.BaseRestoreManager,
    --- Restores a single channel from the backup (with messages optionally restored)
    ---
    --- Does not delete any existing channels, just creates a new one with the same settings and tries restoring messages if requested
    ---
    --- The restored channel will be restored to inCategory if provided
    restoreChannel: (channelid: string, restoreMessages: boolean, inCategory: string?) -> apitypes.ChannelObject?,
    --- Restores messages to a channel from the backup using a webhook
    restoreChannelMessages: (ctx: Primitives.TemplateContext, tgtChannel: apitypes.ChannelObject, messages: {apitypes.MessageObject}, webhook: WebhookData, permData: PermData, updater: types.Updater) -> (),
}

type IGuildData = {
    currentGuild: apitypes.GuildObject,
    currentGuildFlags: GuildFlags,
    currentBotMember: apitypes.GuildMemberObject,
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
local function PartialRestoreManager(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, updater: types.Updater, opts: types.BackupRestoreOpts): PartialRestoreManager
    local basemanager = common.BaseRestoreManager(ctx, src, enckey, updater, opts)
    local loadedBackup = basemanager.getLoadedBackup()
    local coreData = loadedBackup.core

    local self = {}

    local function getBaseManager() 
        return basemanager
    end

    -- Restore the base guild settings from the backup
    local function restoreBaseGuildSettings() 
        updater.addStatus("Restoring guild data...")

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

        updater.addStatus("Done modifying basic server settings")
    end

    -- See PartialRestoreManager type definition for docs
    local function restoreChannel(channelid: string, restoreMessages: boolean, inCategory: string?): apitypes.ChannelObject?
        local createdChannel: apitypes.ChannelObject? = nil
        for _, c in coreData.channels do 
            if c.id ~= channelid then 
                continue
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

    --- Restores the messages of a channel from the backup
    local function restoreChannelMessages(
        ctx: Primitives.TemplateContext,
        tgtChannel: apitypes.ChannelObject,
        messages: {apitypes.MessageObject},
        webhook: WebhookData,
        permData: PermData,
        updater: types.Updater
    ) 
        -- Check if we can restore messages to this channel
        local perms = discordpermcalc.MemberChannelPerms(permData.currentGuild, permData.currentBotMember, tgtChannel)
        local canManageWebhooks = discordpermcalc.HasPermission(perms, permission.PermissionSet.ManageWebhooks)
        if not canManageWebhooks then 
            updater.addStatus("Bot does not have 'Manage Webhooks' permissions in channel ``" .. tgtChannel.name .. "`` with ID: ``" .. tgtChannel.id .. "`` , ignoring message restore...")
            return
        else 
            updater.addStatus("Restoring " .. #messages .. " messages to channel ``" .. tgtChannel.name .. "`` with ID: ``" .. tgtChannel.id .. "``")
        end

        --- TODO: This is currently waiting on Webhook support in Khronos
        error("Not yet implemented")
    end

    self.getBaseManager = getBaseManager
    self.restoreBaseGuildSettings = restoreBaseGuildSettings
    self.restoreChannel = restoreChannel
    self.restoreChannelMessages = restoreChannelMessages

    return self
end

return PartialRestoreManager
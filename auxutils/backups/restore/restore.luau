local channel = require"@discord-types/channel"
local types = require"../backups"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission"
local RestoreManager = require"./impl"
local CheckpointManager = require"@antiraid-ext/checkpoint"

export type Opts = {
    opts: types.BackupRestoreOpts,
    src: types.RestoreSource, 
    enckey: string?, 
    gre: RestoreManager.GetRestored,

    -- For sending status updates
    channelid: string, -- The channel ID to send status updates to
    msgid: string, -- The message ID to send status updates to
}

--- Helper function to get the restore manager from the slate or create a new one if it doesn't exist. This is used to persist the restore manager across checkpoints.
local function getmanagerfromslate(ctx: CheckpointManager.CheckpointContext<Opts>): RestoreManager.BaseRestoreManager
    local slate = ctx.slate
    if slate.rm then 
        return slate.rm
    end

    local data = ctx.data()
    local updater: types.Updater = {} :: types.Updater -- TODO: Implement a proper updater that updates the checkpoint status as well
    local rm = RestoreManager(ctx.tctx, data.src, data.enckey, updater, {
        opts = data.opts,
        gre = data.gre
    })

    local loadedBackup = rm.getLoadedBackup()
    local coreData = loadedBackup.core
    local guildData = rm.getCurrentGuildData()
    rm.validateBackupCompatibility()
    assert(coreData.guild.id, "internal error: guild ID must be set in core data")

    -- Run the basic permission checks for restoring a backup before doing any more intensive operations, to fail fast if the bot doesn't have the required permissions
    if not discordpermcalc.HasPermission(guildData.basePerms, permission.PermissionSet.ManageChannels) then
        error("Cannot restore backup: bot does not have the 'Manage Channels' permission")
    end

    if not discordpermcalc.HasPermission(guildData.basePerms, permission.PermissionSet.ManageRoles) then
        error("Cannot restore backup: bot does not have the 'Manage Roles' permission")
    end

    if coreData.options.backupMessages and not discordpermcalc.HasPermission(guildData.basePerms, permission.PermissionSet.ManageWebhooks) then
        error("Cannot restore backup: bot does not have the 'Manage Webhooks' permission but backup contains messages")
    end

    slate.rm = rm
    return rm
end

-- The steps on how to restore a backup
local RESTORE_STEPS: {CheckpointManager.CheckpointStep<Opts>} = {
    {
        step = "EditBaseGuild",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            basemanager.restoreBaseGuildSettings()
            return nil
        end
    },
    {
        step = "DeleteOldRoles",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            local guildData = basemanager.getCurrentGuildData()

            local discordDeleteOldRolesExecutor = ctx.tctx.Discord:antiraid_bulk_op("delete_guild_role")
            assert(guildData.currentGuild.roles, "Internal Error: guildData.currentGuild.roles should not be nil here")
            for _, role in guildData.currentGuild.roles do
                basemanager.deleteRole(role, discordDeleteOldRolesExecutor)
                discordDeleteOldRolesExecutor:antiraid_bulk_op_wait()
            end

            return nil
        end
    },
    {
        step = "CreateRoles",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            local data = ctx.data()
            local coreData = basemanager.getLoadedBackup().core

            assert(coreData.guild.roles, "Internal Error: coreData.guild.roles should not be nil here")

            -- Now create the roles
            local discordCreateRolesExecutor = ctx.tctx.Discord:antiraid_bulk_op("create_guild_role")
            for _, role in coreData.guild.roles do 
                basemanager.createRole(role, discordCreateRolesExecutor)

                -- Update checkpoint
                data.gre = basemanager.getRestored() 
                ctx.save(data)

                discordCreateRolesExecutor:antiraid_bulk_op_wait()
            end

            -- Update currentGuild roles to the restored roles
            basemanager.syncCurrentGuild()

            data.gre = basemanager.getRestored() 
            return data
        end
    },
    {
        step = "DeleteOldChannels",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            local guildData = basemanager.getCurrentGuildData()

            local discordDeleteOldChannelsExecutor = ctx.tctx.Discord:antiraid_bulk_op("delete_channel")
            for _, channel in guildData.currentChannels do 
                basemanager.deleteChannel(channel, discordDeleteOldChannelsExecutor)
                discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
            end

            return nil -- preserve old checkpoint data since we will need it for the next step
        end
    },
    {
        step = "CreateChannels",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            local data = ctx.data()
            local coreData = basemanager.getLoadedBackup().core

            local discordCreateChannelsExecutor = ctx.tctx.Discord:antiraid_bulk_op("create_guild_channel")
            
            --- Helper function to restore channels
            --- @param categoryRestore boolean Whether to restore categories or not
            --- @return nil
            local function _restoreChans(categoryRestore: boolean) 
                assert(coreData.channels, "Internal Error: coreData.channels should not be nil here")

                for _, c in coreData.channels do 
                    if categoryRestore and c.type ~= channel.ChannelTypesMap.GuildCategory then 
                        continue -- Skip non-category channels if we are restoring categories only
                    end

                    basemanager.createChannel(c, discordCreateChannelsExecutor)

                    -- Update checkpoint
                    data.gre = basemanager.getRestored() 
                    ctx.save(data)

                    discordCreateChannelsExecutor:antiraid_bulk_op_wait()
                end
            end

            -- First restore categories
            _restoreChans(true)
            -- Now restore other channels
            _restoreChans(false)

            data.gre = basemanager.getRestored()
            return data
        end
    },
    {
        step = "FinishBaseRestore",
        fn = function(ctx) 
            local basemanager = getmanagerfromslate(ctx)
            basemanager.finishBaseRestore()
            return nil
        end
    }
}

return {
    RESTORE_STEPS = RESTORE_STEPS
}
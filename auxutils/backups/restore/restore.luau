local Primitives = require"@antiraid-core/primitives"
local channel = require"@discord-types/channel"
local types = require"../backups"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission"
local checkpoint = require"./checkpoint"
local validate = require"../create/validate"
local RestoreManager = require"./impl"

local function restoreBackup(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, opts: types.BackupRestoreOpts, checkpointId: string?, updater: types.Updater) 
    validate.scope(updater, function() 
        if checkpointId then updater.addStatus("Resuming backup restore from saved checkpoint: " .. checkpointId) end

        -- Setup checkpointer
        local checkpointer = nil
        if checkpointId then 
            checkpointer = checkpoint.Checkpoint(ctx, { 
                type = "existing", 
                id = checkpointId 
            })
        else 
            checkpointer = checkpoint.Checkpoint(ctx, { 
                type = "new", 
                base = {
                    source = src,
                    opts = opts,
                    enckey = enckey,
                } 
            })
        end

        -- Load the backup into memory
        local basemanager = RestoreManager(ctx, src, enckey, updater, {
            opts = opts,
            gre = checkpointer.data.gre
        })
        local loadedBackup = basemanager.getLoadedBackup()
        local coreData = loadedBackup.core
        local guildData = basemanager.getCurrentGuildData()
        local gre = basemanager.getRestored()
        basemanager.validateBackupCompatibility()
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

        -- Begin restoration process
        updater.addStatus("Restoring core data...")
        
        -- Scope will automatically remove checkpoint upon completion of callback
        checkpointer.scope(function() 
            assert(checkpointer, "Internal Error: Checkpoint should not be nil here")

            if checkpointer.data.step == "EditBaseGuild" then 
                basemanager.restoreBaseGuildSettings()

                checkpointer.saveCheckpoint({
                    step = "DeleteOldRoles" :: "DeleteOldRoles",
                    gre = gre,
                })
            end

            if checkpointer.data.step == "DeleteOldRoles" then 
                local discordDeleteOldRolesExecutor = ctx.Discord:antiraid_bulk_op("delete_guild_role")
                assert(guildData.currentGuild.roles, "Internal Error: guildData.currentGuild.roles should not be nil here")
                for _, role in guildData.currentGuild.roles do
                    basemanager.deleteRole(role, discordDeleteOldRolesExecutor)
                    discordDeleteOldRolesExecutor:antiraid_bulk_op_wait()
                end

                updater.addStatus("Finished deleting old roles")

                checkpointer.saveCheckpoint({
                    step = "CreateRoles" :: "CreateRoles",
                    gre = gre,
                })
            end

            if checkpointer.data.step == "CreateRoles" then 
                assert(coreData.guild.roles, "Internal Error: coreData.guild.roles should not be nil here")

                -- Now create the roles
                local discordCreateRolesExecutor = ctx.Discord:antiraid_bulk_op("create_guild_role")
                for _, role in coreData.guild.roles do 
                    basemanager.createRole(role, discordCreateRolesExecutor)

                    checkpointer.saveCheckpoint({
                        step = "CreateRoles" :: "CreateRoles",
                        gre = gre,
                    })

                    discordCreateRolesExecutor:antiraid_bulk_op_wait()
                end

                -- Update currentGuild roles to the restored roles
                basemanager.syncCurrentGuild()

                updater.addStatus("Finished creating roles")

                checkpointer.saveCheckpoint({
                    step = "DeleteOldChannels" :: "DeleteOldChannels",
                    gre = gre,
                })
            end

            if checkpointer.data.step == "DeleteOldChannels" then 
                updater.addStatus("Deleting old channels...")

                local discordDeleteOldChannelsExecutor = ctx.Discord:antiraid_bulk_op("delete_channel")
                for _, channel in guildData.currentChannels do 
                    basemanager.deleteChannel(channel, discordDeleteOldChannelsExecutor)
                    discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
                end

                updater.addStatus("Finished deleting old channels")

                checkpointer.saveCheckpoint({
                    step = "CreateChannels" :: "CreateChannels",
                    gre = gre,
                })
            end

            if checkpointer.data.step == "CreateChannels" then 
                local discordCreateChannelsExecutor = ctx.Discord:antiraid_bulk_op("create_guild_channel")
                
                --- Helper function to restore channels
                --- @param categoryRestore boolean Whether to restore categories or not
                --- @return nil
                local function _restoreChans(categoryRestore: boolean) 
                    assert(checkpointer, "Internal Error: Checkpointer should not be nil here")
                    assert(checkpointer.data.step == "CreateChannels", "Internal Error: Checkpointer step should be CreateChannels here")
                    assert(guildData.currentGuild.id, "Internal Error: currentGuild.id should not be nil here")

                    for _, c in coreData.channels do 
                        if categoryRestore and c.type ~= channel.ChannelTypesMap.GuildCategory then 
                            continue -- Skip non-category channels if we are restoring categories only
                        end

                        basemanager.createChannel(c, discordCreateChannelsExecutor)

                        checkpointer.saveCheckpoint({
                            step = "CreateChannels" :: "CreateChannels",
                            gre = gre,
                        })

                        discordCreateChannelsExecutor:antiraid_bulk_op_wait()
                    end
                end

                -- First restore categories
                _restoreChans(true)
                -- Now restore other channels
                _restoreChans(false)

                updater.addStatus("Finished creating channels")

                checkpointer.saveCheckpoint({
                    step = "FinishBaseRestore" :: "FinishBaseRestore",
                    gre = gre,
                })
            end

            guildData.currentGuild = ctx.Discord:get_guild().data -- Re-fetch the guild to get the updated channels and roles

            if checkpointer.data.step == "FinishBaseRestore" then 
                basemanager.finishBaseRestore()

                checkpointer.saveCheckpoint({
                    step = "Done" :: "Done",
                    gre = gre,
                })
            end

            return nil
        end)

        return nil
    end)

    updater.setState("completed")
end 

return {
    restoreBackup = restoreBackup,
}
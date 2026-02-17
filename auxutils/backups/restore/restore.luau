local Primitives = require"@antiraid-core/primitives"
local resttypes = require"@discord-types/restTypes"
local channel = require"@discord-types/channel"
local types = require"../backups"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission"
local compare = require"@antiraid-ext/utils/rolecmp"
local checkpoint = require"./checkpoint"
local validate = require"../create/validate"
local common = require"./common"

local function restoreBackup(ctx: Primitives.TemplateContext, src: types.RestoreSource, enckey: string?, opts: types.BackupRestoreOpts, checkpointId: string?, updater: types.Updater) 
    validate.scope(updater, function() 
        if checkpointId then updater.addStatus("Resuming backup restore from saved checkpoint: " .. checkpointId) end

        -- Load the backup into memory
        local basemanager = common.BaseRestoreManager(ctx, src, enckey, updater, opts)
        local loadedBackup = basemanager.getLoadedBackup()
        local coreData = loadedBackup.core
        local guildData = basemanager.getCurrentGuildData()
        basemanager.validateBackupCompatibility()
        local highestRole = basemanager.getBotHighestRole()
        assert(guildData.currentGuild.roles, "internal error: guild roles must be loaded before restoring backup")
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
        updater.addStatus("Highest role of bot is " .. highestRole.name .. " (ID: " .. highestRole.id .. ")")

        assert(highestRole.position > 0, "internal error: user's highest role must be above the @everyone role in the guild hierarchy")
        
        -- Resumable/Checkpointing code starts here
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

        -- Scope will automatically remove checkpoint upon completion of callback
        checkpointer.scope(function() 
            assert(checkpointer, "Internal Error: Checkpoint should not be nil here")

            if checkpointer.data.step == "EditBaseGuild" then 
                updater.addStatus("Restoring guild data...")
                basemanager.restoreBaseGuildSettings()
                updater.addStatus("Done modifying basic server settings")

                checkpointer.saveCheckpoint({
                    step = "DeleteOldRoles" :: "DeleteOldRoles"
                })
            end

            if checkpointer.data.step == "DeleteOldRoles" then 
                assert(highestRole, "Internal Error: highestRole should not be nil here")
                local discordDeleteOldRolesExecutor = ctx.Discord:antiraid_bulk_op("delete_guild_role")
                for _, role in guildData.currentGuild.roles do
                    if basemanager.isRoleProtected(role, guildData) or compare.IsRoleAGreaterThanOrEqualToRoleB(role, highestRole)
                    then 
                        updater.addStatus("Ignoring role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)
                        continue -- Ignore and continue
                    end

                    updater.addStatus("Deleting role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)

                    discordDeleteOldRolesExecutor:delete_guild_role({
                        reason = "Backup restore: Delete old roles step",
                        role_id = role.id
                    })

                    discordDeleteOldRolesExecutor:antiraid_bulk_op_wait()
                end

                updater.addStatus("Finished deleting old roles")

                checkpointer.saveCheckpoint({
                    step = "CreateRoles" :: "CreateRoles",
                    restoredRoles = {},
                })
            end

            if checkpointer.data.step == "CreateRoles" then 
                assert(coreData.guild.roles, "Internal Error: coreData.guild.roles should not be nil here")
                assert(highestRole, "Internal Error: highestRole should not be nil here")

                -- Sort roles in hierarchy order
                compare.SortRolesByHierarchyDesc(coreData.guild.roles)

                -- Now create the roles (position reassert will happen later)
                local discordCreateRolesExecutor = ctx.Discord:antiraid_bulk_op("create_guild_role")
                local restoredRoles = checkpointer.data.restoredRoles
                for _, role in coreData.guild.roles do 
                    if basemanager.isRoleProtected(role, guildData)
                    or restoredRoles[role.id] -- Already restored role
                    then 
                        continue -- Ignore and continue
                    end

                    updater.addStatus("Creating role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)

                    restoredRoles[role.id] = basemanager.createGuildRole(role, guildData, discordCreateRolesExecutor)

                    checkpointer.saveCheckpoint({
                        step = "CreateRoles" :: "CreateRoles",
                        restoredRoles = restoredRoles,
                    })

                    discordCreateRolesExecutor:antiraid_bulk_op_wait()
                end

                -- Update currentGuild roles to the restored roles
                guildData.currentGuild.roles = {}
                for _, role in restoredRoles do 
                    table.insert(guildData.currentGuild.roles, role)
                end

                compare.SortRolesByHierarchyDesc(guildData.currentGuild.roles)

                guildData.currentBotMember = ctx.Discord:get_guild_member(ctx.current_user.id).data -- Re-fetch the bot member to get the updated roles

                updater.addStatus("Finished creating roles")

                checkpointer.saveCheckpoint({
                    step = "DeleteOldChannels" :: "DeleteOldChannels",
                    restoredRoles = restoredRoles,
                })
            end

            local currentChannels = ctx.Discord:get_guild_channels().data

            if checkpointer.data.step == "DeleteOldChannels" then 
                updater.addStatus("Deleting old channels...")

                local discordDeleteOldChannelsExecutor = ctx.Discord:antiraid_bulk_op("delete_channel")
                for _, channel in currentChannels do 
                    if table.find(opts.protectedChannels, channel.id) then 
                        continue -- Ignore and continue
                    end

                    if channel.id == guildData.currentGuild.rules_channel_id or channel.id == guildData.currentGuild.public_updates_channel_id then
                        continue -- Ignore and continue
                    end

                    local channelPerms = discordpermcalc.ComputeMemberChannelOverwrites(guildData.basePerms, guildData.currentGuild, guildData.currentBotMember, channel)

                    if not discordpermcalc.HasPermission(channelPerms, permission.PermissionSet.ManageChannels) then
                        updater.addStatus("Ignoring channel ``" .. channel.name .. "`` with ID: ``" .. channel.id .. "`` as bot does not have 'Manage Channels' permission in it")
                        continue -- Ignore and continue
                    end

                    updater.addStatus("Deleting channel ``" .. channel.name .. "`` with ID: ``" .. channel.id .. "``")

                    discordDeleteOldChannelsExecutor:delete_channel({
                        reason = "Backup restore: Delete old channels step",
                        channel_id = channel.id,
                    })

                    discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
                end

                updater.addStatus("Finished deleting old channels")

                checkpointer.saveCheckpoint({
                    step = "CreateChannels" :: "CreateChannels",
                    restoredRoles = checkpointer.data.restoredRoles,
                    restoredChannels = {},
                })
            end

            if checkpointer.data.step == "CreateChannels" then 
                local restoredChannels = checkpointer.data.restoredChannels
                local discordCreateChannelsExecutor = ctx.Discord:antiraid_bulk_op("create_guild_channel")
                
                --- Helper function to restore channels
                --- @param categoryRestore boolean Whether to restore categories or not
                --- @return nil
                local function _restoreChans(categoryRestore: boolean) 
                    assert(checkpointer, "Internal Error: Checkpointer should not be nil here")
                    assert(checkpointer.data.step == "CreateChannels", "Internal Error: Checkpointer step should be CreateChannels here")
                    assert(guildData.currentGuild.id, "Internal Error: currentGuild.id should not be nil here")

                    for _, c in coreData.channels do 
                        if checkpointer.data.restoredChannels[c.id] then 
                            continue -- Skip channels that are already restored
                        end

                        if categoryRestore and c.type ~= channel.ChannelTypesMap.GuildCategory then 
                            continue -- Skip non-category channels if we are restoring categories only
                        end

                        local ud = common.createChannelData(
                            c,
                            checkpointer.data.restoredRoles,
                            checkpointer.data.restoredChannels,
                            coreData.guild.id,
                            guildData.currentGuild.id,
                            opts.protectedRoles,
                            opts.protectedChannels,
                            updater
                        )

                        if categoryRestore then
                            updater.addStatus("Creating category ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
                        else 
                            updater.addStatus("Creating channel ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
                        end

                        local createdChannel = discordCreateChannelsExecutor:create_guild_channel({
                            reason = "Backup restore: Create channels step",
                            data = ud,
                        }).data

                        restoredChannels[c.id] = createdChannel

                        checkpointer.saveCheckpoint({
                            step = "CreateChannels" :: "CreateChannels",
                            restoredRoles = checkpointer.data.restoredRoles,
                            restoredChannels = restoredChannels,
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
                    restoredRoles = checkpointer.data.restoredRoles,
                    restoredChannels = restoredChannels,
                })
            end

            guildData.currentGuild = ctx.Discord:get_guild().data -- Re-fetch the guild to get the updated channels and roles

            if checkpointer.data.step == "FinishBaseRestore" then 
                -- Update rules_channel_id and public_updates_channel_id if COMMUNITY
                if guildData.currentGuildFlags.community then 
                    local newRulesChannelId = nil
                    local newPublicUpdatesChannelId = nil
                    if coreData.guild.rules_channel_id then
                        newRulesChannelId = checkpointer.data.restoredChannels[coreData.guild.rules_channel_id]
                    end

                    if coreData.guild.public_updates_channel_id then
                        newPublicUpdatesChannelId = checkpointer.data.restoredChannels[coreData.guild.public_updates_channel_id]
                    end

                    if newRulesChannelId or newPublicUpdatesChannelId then
                        local updateData: resttypes.ModifyGuildRequest = {}
                        if newRulesChannelId then
                            updateData.rules_channel_id = newRulesChannelId.id
                        end
                        if newPublicUpdatesChannelId then
                            updateData.public_updates_channel_id = newPublicUpdatesChannelId.id
                        end

                        ctx.Discord:modify_guild({
                            reason = "Backup restore: Finish base restore step",
                            data = updateData,
                        })

                        updater.addStatus("Updated rules and public updates channels")

                        if newRulesChannelId then
                            guildData.currentGuild.rules_channel_id = newRulesChannelId.id
                        end

                        if newPublicUpdatesChannelId then
                            guildData.currentGuild.public_updates_channel_id = newPublicUpdatesChannelId.id
                        end

                        updater.addStatus("Deleted old rules and public updates channels")
                    end
                end

                checkpointer.saveCheckpoint({
                    step = "Done" :: "Done",
                })
            end

            -- Ensure that, at CreateWebhook and beyond, backupMessages is true
            assert(coreData.options.backupMessages, "Internal Error: coreData.options.backupMessages should be true at this point")            
        
            if checkpointer.data.step == "CreateWebhook" then 
                -- TODO: Support restoring messages later via a webhook but its not very critical
                updater.addStatus("Skipping webhook restoration as it is not implemented yet")
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
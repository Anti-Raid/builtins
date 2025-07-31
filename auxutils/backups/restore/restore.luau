local Primitives = require"@antiraid-core/primitives"
local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"
local channel = require"@discord-types/channel"
local types = require"../backups"
local load = require"./load"
local blob = require"@antiraid-core/blob"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission"
local compare = require"@antiraid-ext/utils/rolecmp"
local checkpoint = require"./checkpoint"
local datamgmt = require"@antiraid/datamgmt"
local createChannelData = require"./channelrestorer"

--- Helper function to convert a asset to a base64 data URL
local function assetToDataURL(mimetype: string, blob: blob.Blob): string
    return "data:" .. mimetype .. ";base64," .. datamgmt.base64encode(blob)
end

type GuildFlags = {
    community: boolean,
    animated_icon: boolean,
    banner: boolean,
    animated_banner: boolean,
    invite_splash: boolean
}

local function restoreBackup(ctx: Primitives.TemplateContext, filename: string, url: string, enckey: string?, opts: types.BackupRestoreOpts, checkpointId: string?, addStatus: (s: string) -> ()) 
    if checkpointId then addStatus("Resuming backup restore from saved checkpoint: " .. checkpointId) end
    
    addStatus("Loading backup data...")
    local blob = ctx.ObjectStorage:download_file(url)
    addStatus("Downloaded backup file of size " .. checkpointId.. #blob .. " bytes" :: any)
    local loadedBackup = load.loadBackupBlob(filename, blob, enckey)
    addStatus("Parsed backup data successfully")
    
    local coreData = loadedBackup.core

    -- Test if coreData is valid    
    assert(coreData.guild.id and #coreData.guild.id > 0, "internal error: guild ID must be set in core data")

    local guildWasCommunity = coreData.guild.features and table.find(coreData.guild.features, "COMMUNITY") ~= nil

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
    
    if guildWasCommunity and not currentGuildFlags.community then
        error("Cannot restore a community guild backup to a non-community guild. Please enable the community features in your guild settings.")
    end

    addStatus("Restoring core data...")

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

    local basePerms = discordpermcalc.BasePermissions(currentGuild, currentBotMember)

    if not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageChannels) then
        error("Cannot restore backup: bot does not have the 'Manage Channels' permission")
    end

    if not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageRoles) then
        error("Cannot restore backup: bot does not have the 'Manage Roles' permission")
    end

    if coreData.options.backupMessages and not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageWebhooks) then
        error("Cannot restore backup: bot does not have the 'Manage Webhooks' permission but backup contains messages")
    end

    -- Find the highest role in the user's member roles
    local highestRole = nil

    local guildRolesMap = {}
    assert(currentGuild.roles, "internal error: guild roles must be loaded before restoring backup")
    for _, role in currentGuild.roles do
        guildRolesMap[role.id] = role
    end

    compare.SortRolesByHierarchyDesc(currentGuild.roles) -- Sort current roles in hierarchy order

    for _, memberRoleId in currentBotMember.roles do 
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

    addStatus("Highest role of bot is " .. highestRole.name .. " (ID: " .. highestRole.id .. ")")

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
                filename = filename,
                url = url,
                opts = opts,
                enckey = enckey,
            } 
        })
    end

    -- Scope will automatically remove checkpoint upon completion of callback
    checkpointer.scope(function() 
        assert(checkpointer, "Internal Error: Checkpoint should not be nil here")

        if checkpointer.data.step == "EditBaseGuild" then 
            addStatus("Restoring guild data...")

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
                updateData.icon = assetToDataURL("image/jpeg", icon)
            end

            local banner = loadedBackup.assets["banner"] :: blob.Blob?
            if banner then
                updateData.banner = assetToDataURL("image/jpeg", banner)
            end

            local splash = loadedBackup.assets["splash"] :: blob.Blob?
            if splash then
                updateData.splash = assetToDataURL("image/jpeg", splash)
            end

            ctx.Discord:modify_guild({
                reason = "Backup restore",
                data = updateData
            })

            addStatus("Done modifying basic server settings")

            checkpointer.saveCheckpoint({
                step = "DeleteOldRoles" :: "DeleteOldRoles"
            })
        end

        if checkpointer.data.step == "DeleteOldRoles" then 
            assert(highestRole, "Internal Error: highestRole should not be nil here")
            local discordDeleteOldRolesExecutor = ctx.Discord:antiraid_bulk_op("delete_guild_role")
            for _, role in currentGuild.roles do
                if role.managed -- Managed role
                or role.id == currentGuild.id -- @everyone
                or table.find(opts.protectedRoles, role.id) -- Protected role
                or compare.IsRoleAGreaterThanOrEqualToRoleB(role, highestRole) -- Role higher on hierarchy
                then 
                    addStatus("Ignoring role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)
                    continue -- Ignore and continue
                end

                role = role :: apitypes.GuildRoleObject

                addStatus("Deleting role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)

                discordDeleteOldRolesExecutor:delete_guild_role({
                    reason = "Backup restore: Delete old roles step",
                    role_id = role.id
                })

                discordDeleteOldRolesExecutor:antiraid_bulk_op_wait()
            end

            addStatus("Finished deleting old roles")

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
                if role.managed -- Managed role
                or role.id == currentGuild.id -- @everyone
                or table.find(opts.protectedRoles, role.id) -- Protected role
                or restoredRoles[role.id] -- Already restored role
                then 
                    continue -- Ignore and continue
                end

                addStatus("Creating role ``" .. role.name .. "`` with ID: ``" .. role.id .. "`` and position " .. role.position :: any)

                -- Ensure role permissions meet our bots permissions
                if not discordpermcalc.HasPermission(basePerms, role.permissions) then 
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

                restoredRoles[role.id] = discordCreateRolesExecutor:create_guild_role({
                    reason = "Backup restore: Create roles step",
                    data = roleUpdate,
                }).data

                checkpointer.saveCheckpoint({
                    step = "CreateRoles" :: "CreateRoles",
                    restoredRoles = restoredRoles,
                })

                discordCreateRolesExecutor:antiraid_bulk_op_wait()
            end

            -- Update currentGuild roles to the restored roles
            currentGuild.roles = {}
            for _, role in restoredRoles do 
                table.insert(currentGuild.roles, role)
            end

            -- Now reassert the positions of the roles
            compare.SortRolesByHierarchyAsc(currentGuild.roles)
            addStatus("Reasserting role positions...")
            local reassertData: {resttypes.ModifyGuildRolePositionsRequest} = {}
            for _, role in currentGuild.roles do
                if role.managed -- Managed role
                or role.id == currentGuild.id -- @everyone
                or table.find(opts.protectedRoles, role.id) -- Protected role
                then 
                    continue -- Ignore and continue
                end
                reassertData[#reassertData + 1] = {
                    id = role.id,
                    position = #reassertData + 1,
                }
            end

            ctx.Discord:modify_guild_role_positions({
                reason = "Backup restore: Reassert role positions",
                data = reassertData,
            })

            compare.SortRolesByHierarchyDesc(currentGuild.roles)

            currentBotMember = ctx.Discord:get_guild_member(ctx.current_user.id).data -- Re-fetch the bot member to get the updated roles

            addStatus("Finished creating roles")

            checkpointer.saveCheckpoint({
                step = "DeleteOldChannels" :: "DeleteOldChannels",
                restoredRoles = restoredRoles,
            })
        end

        local currentChannels = ctx.Discord:get_guild_channels().data

        if checkpointer.data.step == "DeleteOldChannels" then 
            addStatus("Deleting old channels...")

            local discordDeleteOldChannelsExecutor = ctx.Discord:antiraid_bulk_op("delete_channel")
            for _, channel in currentChannels do 
                if table.find(opts.protectedChannels, channel.id) then 
                    continue -- Ignore and continue
                end

                if channel.id == currentGuild.rules_channel_id or channel.id == currentGuild.public_updates_channel_id then
                    continue -- Ignore and continue
                end

                local channelPerms = discordpermcalc.ComputeMemberChannelOverwrites(basePerms, currentGuild, currentBotMember, channel)

                if not discordpermcalc.HasPermission(channelPerms, permission.PermissionSet.ManageChannels) then
                    addStatus("Ignoring channel ``" .. channel.name .. "`` with ID: ``" .. channel.id .. "`` as bot does not have 'Manage Channels' permission in it")
                    continue -- Ignore and continue
                end

                addStatus("Deleting channel ``" .. channel.name .. "`` with ID: ``" .. channel.id .. "``")

                discordDeleteOldChannelsExecutor:delete_channel({
                    reason = "Backup restore: Delete old channels step",
                    channel_id = channel.id,
                })

                discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
            end

            addStatus("Finished deleting old channels")

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
                assert(currentGuild.id, "Internal Error: currentGuild.id should not be nil here")

                for _, c in coreData.channels do 
                    if checkpointer.data.restoredChannels[c.id] then 
                        continue -- Skip channels that are already restored
                    end

                    if categoryRestore and c.type ~= channel.ChannelTypesMap.GuildCategory then 
                        continue -- Skip non-category channels if we are restoring categories only
                    end

                    local ud = createChannelData(
                        c,
                        checkpointer.data.restoredRoles,
                        checkpointer.data.restoredChannels,
                        coreData.guild.id,
                        currentGuild.id,
                        opts.protectedRoles,
                        opts.protectedChannels,
                        addStatus
                    )

                    if categoryRestore then
                        addStatus("Creating category ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
                    else 
                        addStatus("Creating channel ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
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

                    if categoryRestore then
                        addStatus("Created category ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
                    else
                        addStatus("Created channel ``" .. c.name .. "`` with ID: ``" .. c.id .. "``")
                    end

                    discordCreateChannelsExecutor:antiraid_bulk_op_wait()
                end
            end

            -- First restore categories
            _restoreChans(true)
            -- Now restore other channels
            _restoreChans(false)

            addStatus("Finished creating channels")

            checkpointer.saveCheckpoint({
                step = "FinishBaseRestore" :: "FinishBaseRestore",
                restoredRoles = checkpointer.data.restoredRoles,
                restoredChannels = restoredChannels,
            })
        end

        currentGuild = ctx.Discord:get_guild().data -- Re-fetch the guild to get the updated channels and roles

        if checkpointer.data.step == "FinishBaseRestore" then 
            -- Update rules_channel_id and public_updates_channel_id if COMMUNITY
            if currentGuildFlags.community then 
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

                    addStatus("Updated rules and public updates channels")

                    -- Delete old rules and public updates channels
                    local discordDeleteOldChannelsExecutor = ctx.Discord:antiraid_bulk_op("delete_channel")
                    if currentGuild.rules_channel_id then 
                        discordDeleteOldChannelsExecutor:delete_channel({
                            reason = "Backup restore: Delete old rules channel",
                            channel_id = currentGuild.rules_channel_id,
                        })
                        discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
                    end

                    if currentGuild.public_updates_channel_id then 
                        discordDeleteOldChannelsExecutor:delete_channel({
                            reason = "Backup restore: Delete old public updates channel",
                            channel_id = currentGuild.public_updates_channel_id,
                        })
                        discordDeleteOldChannelsExecutor:antiraid_bulk_op_wait()
                    end

                    if newRulesChannelId then
                        currentGuild.rules_channel_id = newRulesChannelId.id
                    end

                    if newPublicUpdatesChannelId then
                        currentGuild.public_updates_channel_id = newPublicUpdatesChannelId.id
                    end

                    addStatus("Deleted old rules and public updates channels")
                end
            end

            if not coreData.options.backupMessages then 
                addStatus("Skipping message restoration as per backup options")
                return nil -- No need to restore messages
            end

            checkpointer.saveCheckpoint({
                step = "CreateWebhook" :: "CreateWebhook",
                restoredRoles = checkpointer.data.restoredRoles,
                restoredChannels = checkpointer.data.restoredChannels,
            })
        end

        -- Ensure that, at CreateWebhook and beyond, backupMessages is true
        assert(coreData.options.backupMessages, "Internal Error: coreData.options.backupMessages should be true at this point")            
    
        if checkpointer.data.step == "CreateWebhook" then 
            -- TODO: Support restoring messages later via a webhook but its not very critical
            addStatus("Skipping webhook restoration as it is not implemented yet")
        end

        return nil
    end)
end 

return restoreBackup
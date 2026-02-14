local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local backupTypes = require"../../auxutils/backups/backups"
local embed = require "../../auxutils/backups/embed"
local restoreBackup = require "../../auxutils/backups/restore/restore".restoreBackup

local POLL_INTERVAL_RESTORE = 10

local function restore(data: data.RunData): nil
    canModeratorDo(
        data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
        "backups.restore"
    )

    local opts: backupTypes.BackupRestoreOpts = {
        protectedChannels = {},
        protectedRoles = {},
    }
    local enckey: string? = nil
    local source: backupTypes.RestoreSource? = nil

    if data.interaction.channel_id then 
        opts.protectedChannels = {data.interaction.channel_id}
    end

    for _, opt in data.command.options do 
        if opt.name == "backup_file" then
            if opt.value.kind == "Attachment" then
                if source then 
                    return interactionutils.replySimple(
                        data.ctx,
                        data.interaction,
                        nil,
                        {
                            {
                                title = "Error processing command",
                                description = "You cannot specify both a backup file and a backup ID. Please choose one.",
                            },
                        },
                        false
                    )
                end
                source = {
                    type = "attachment" :: "attachment",
                    url = opt.value.attachment.url or error("No valid URL found for the backup file"),
                    filename = opt.value.attachment.filename or error("No valid filename found for the backup file"),
                }
            end
        elseif opt.name == "backup_id" then
            if opt.value.kind == "String" then
                if source then
                    return interactionutils.replySimple(
                        data.ctx,
                        data.interaction,
                        nil,
                        {
                            {
                                title = "Error processing command",
                                description = "You cannot specify both a backup file and a backup ID. Please choose one.",
                            },
                        },
                        false
                    )
                end

                local backupData = data.ctx.KV:getrecord(opt.value.value, {"builtins.backups.metadata"})
                if not backupData.exists then
                    return interactionutils.replySimple(
                        data.ctx,
                        data.interaction,
                        nil,
                        {
                            {
                                title = "Error processing command",
                                description = "Backup with ID `" .. opt.value.value .. "` does not exist.",
                            },
                        },
                        false
                    )
                end

                assert(type(backupData.value.filename) == "string", "Backup data does not contain a filename")

                source = {
                    type = "objectstorage" :: "objectstorage",
                    filepath = backupData.value.filename,
                }
            end
        elseif opt.name == "password" then
            if opt.value.kind == "String" then
                enckey = opt.value.value
            end
        elseif opt.name == "protected_channels" then
            if opt.value.kind == "String" then 
                local pc = string.split(opt.value.value, ",")
                for _, channelId in pc do
                    -- remove any whitespace
                    channelId = channelId:gsub("%s+", "")
                    if channelId ~= "" then
                        table.insert(opts.protectedChannels, channelId)
                    end
                end
            end
        elseif opt.name == "protected_roles" then
            if opt.value.kind == "String" then 
                local pr = string.split(opt.value.value, ",")
                for _, roleId in pr do
                    -- remove any whitespace
                    roleId = roleId:gsub("%s+", "")
                    if roleId ~= "" then
                        table.insert(opts.protectedRoles, roleId)
                    end
                end
            end
        end
    end

    -- Check if we have a backup source
    if not source then
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "You must specify either a backup file or a backup ID to restore from.",
                },
            },
            false
        )
    end

    -- Send spawning message
    interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Restoring backup",
                description = "Spawning restore job...",
            },
        },
        false
    )

    data.sethasEdited(true)

    embed.updateTillComplete({
        interval = POLL_INTERVAL_RESTORE,
        spawner = function(updater: backupTypes.Updater, initial: embed.EmbedData) 
            restoreBackup(data.ctx, source :: backupTypes.RestoreSource, enckey, opts, nil, updater)

            -- TODO: Consider storing metadata in KV about the restore job
        end,
        callback = function(embedData: embed.EmbedData) 
            if embedData.state == "failed" then return end
            local embed, components = embed.backupJobToEmbed(
                data.ctx,
                embedData,
                true,
                true
            )

            -- Edit original interaction response with the job status
            interactionutils.editSimple(
                data.ctx,
                data.interaction,
                nil,
                {embed},
                components
            )
        end,
    })
    return nil
end

return restore
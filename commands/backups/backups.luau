local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local discord = require "@discord-types/apiTypes"
local paginate = require "@antiraid-ext/framework/paginate"
local backupTypes = require "../../auxutils/backups/backups"
local createBackup = require "../../auxutils/backups/create/start"
local restoreBackup = require "../../auxutils/backups/restore/restore"
local embed = require "../../auxutils/backups/embed"

local function register() 
    return commandBuilder.new({
        name = "backups",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Manage and create backups of your server")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("create")
            :setDescription("Creates a new backup of the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("Boolean")
                    :setName("messages")
                    :setDescription("Whether to include messages in the backup (up to 500)")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("channels")
                    :setDescription("Channels to backup messages from (comma separated), otherwise all channels")  
                    :setRequired(false)
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("backup_guild_assets")
                    :setDescription("What assets to back up in comma-seperated form (icon,splash,banner)")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("max_messages")
                    :setDescription("The maximum number of messages to backup. Defaults to 500")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("per_channel")
                    :setDescription("The number of messages per channel to backup. Defaults to 100")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("special_allocations")
                    :setDescription("Specific channel allocation overrides. Format: channel_id=number,channel_id=number")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("password")
                    :setDescription("Password to encrypt the backup with. If not provided, the backup will not be encrypted")
                    :setRequired(false)  
                    :build()
                end
            )
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("restore")
            :setDescription("Restores a backup to the server")
            :option(
                function(opt) 
                    return opt
                    :setType("Attachment")
                    :setName("backup_file")
                    :setDescription("The backup attachment to restore")
                    :setRequired(false)  
                    :build()
                end   
            ) 
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("backup_id")
                    :setDescription("The backup ID to restore from")
                    :setRequired(false)  
                    :build()
                end   
            ) 
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("password")
                    :setDescription("Password to decrypt backup with. Should not be reused")
                    :setRequired(false)  
                    :build()
                end   
            ) 
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("protected_channels")
                    :setDescription("Channels to protect from being deleted. Comma separated")
                    :setRequired(false)  
                    :build()
                end   
            )
            :option(
                function(opt)
                    return opt
                    :setType("String")
                    :setName("protected_roles")
                    :setDescription("Roles to protect from being deleted. Comma separated")
                    :setRequired(false)  
                    :build()
                end
            )
            :build()
        end
    )
    :option(
        function(opt)
            return opt
            :setType("SubCommand")
            :setName("list")
            :setDescription("Lists all backups of the server")
            :build()
        end
    )
    :option(
        function(opt)
            return opt
            :setType("SubCommand")
            :setName("delete")
            :setDescription("Deletes a backup by its ID")
            :option(
                function(opt)
                    return opt
                    :setType("String")
                    :setName("backup_id")
                    :setDescription("The backup ID to delete")
                    :setRequired(true)
                    :build()
                end
            )
            :build()
        end
    )
    :build()
end

local POLL_INTERVAL_CREATE = 3
local POLL_INTERVAL_RESTORE = 10

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "create" then
        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.create"
        )

        local opts: backupTypes.BackupCreateOpts = {
            channels = {},
            perChannel = 100,
            maxMessages = 100,
            backupMessages = false,
            backupGuildAssets = {"icon","splash","banner"},
            rolloverLeftovers = true,
            specialAllocations = {},
        }
        local enckey: string? = nil

        for _, opt in data.command.options do 
            if opt.name == "channels" then
                if opt.value.kind == "String" then 
                    opts.channels = string.split(opt.value.value, ",")
                end
            elseif opt.name == "per_channel" then
                if opt.value.kind == "Integer" then
                    opts.perChannel = opt.value.value
                end
            elseif opt.name == "max_messages" then
                if opt.value.kind == "Integer" then
                    opts.maxMessages = opt.value.value
                end
            elseif opt.name == "messages" then
                if opt.value.kind == "Boolean" then
                    opts.backupMessages = opt.value.value
                end
            elseif opt.name == "backup_guild_assets" then
                if opt.value.kind == "String" then
                    opts.backupGuildAssets = string.split(opt.value.value, ",") :: any
                end
            elseif opt.name == "special_allocations" then
                if opt.value.kind == "String" then 
                    local specialAllocationsStr = opt.value.value
                    for _, pair in string.split(specialAllocationsStr, ",") do
                        local key, value = string.match(pair, "(%d+)=(%d+)")
                        if key and value then
                            opts.specialAllocations[key] = tonumber(value)
                        else 
                            return interactionutils.replySimple(
                                data.ctx,
                                data.interaction,
                                nil,
                                {
                                    {
                                        title = "Error processing command",
                                        description = "Invalid format for special allocations. Use channel_id=number,channel_id=number. Failing entry was: ``" .. pair .. "``",
                                    },
                                },
                                false
                            )
                        end
                    end                    
                end
            elseif opt.name == "password" then
                if opt.value.kind == "String" then
                    enckey = opt.value.value
                end
            end
        end

        -- Send spawning message
        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Creating backup",
                    description = "Starting backup...",
                },
            },
            true
        )

        data.sethasEdited(true)

        embed.updateTillComplete({
            interval = POLL_INTERVAL_CREATE,
            spawner = function(updater: backupTypes.Updater, initial: embed.EmbedData) 
                local built = createBackup(data.ctx, opts, enckey, updater)

                -- Upload and save metadata
                data.ctx.KV:set(
                    built.id, 
                    {
                        filename = built.filename,
                        created_by = extractUserIdFromInteraction(data.interaction),
                        num_updates = initial.numUpdates or 0,
                    },
                    {"builtins.backups.metadata"}
                )
                data.ctx.ObjectStorage:upload_file(built.filename, built.backup)
                initial.finalFilePath = built.filename
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
    elseif cmdname == "restore" then
        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

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
                        type = "attachment",
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
                        type = "objectstorage",
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
    elseif cmdname == "list" then
        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.list"
        )

        local backups = data.ctx.KV:find("%%", {"builtins.backups.metadata"})

        if #backups == 0 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No backups found",
                        description = "There are no backups available for this server.",
                    },
                },
                true
            )
        end

        paginate.paginate(data, {
            id = "backups",
            numPages = #backups,
            embed = function(currentIdx: number): discord.EmbedObject 
                local backupData = backups[currentIdx]
                assert(backupData and backupData.exists, "Backup data not found for index " .. currentIdx)
                assert(backupData.value.filename, "Backup data does not contain a filename")
                local embed, _ = embed.backupJobToEmbed(
                    data.ctx,
                    {
                        id = backupData.key,
                        createdat = backupData.created_at.timestamp_seconds,
                        statuses = {},
                        state = "completed", -- Backups v2 doesnt store failed backups
                        numUpdates = backupData.value.num_updates or 0,
                        finalFilePath = backupData.value.filename,
                    },
                    true
                )
                return embed
            end
        })
        return nil    
    elseif cmdname == "delete" then
        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.delete"
        )

        local backupId = nil
        for _, opt in data.command.options do
            if opt.name == "backup_id" and opt.value.kind == "String" then
                backupId = opt.value.value
            end
        end
        if not backupId then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "You must specify a backup ID to delete.",
                    },
                },
                false
            )
        end

        -- Directly call delete, rely on global xpcall for error handling
        local backupData = data.ctx.KV:getrecord(backupId, {"builtins.backups.metadata"})

        if not backupData.exists then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Backup with ID `" .. backupId .. "` does not exist.",
                    },
                },
                false
            )
        end

        assert(type(backupData.value.filename) == "string", "Backup data does not contain a filename")

        -- Delete the backup from ObjectStorage first
        
        data.ctx.ObjectStorage:delete_file(backupData.value.filename)
        data.ctx.KV:delete(backupId, {"builtins.backups.metadata"})

        interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Backup Deleted",
                    description = string.format("Backup with ID `%s` has been deleted.", backupId),
                },
            },
            false
        )
        return nil
    else
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "Unknown subcommand",
                },
            },
            false
        )
    end
end

return {
    register = register,
    run = run,
}

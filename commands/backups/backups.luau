local commandBuilder = require "@discord-types/builders/interaction/interaction"
local interactionChoiceBuilder = require "@discord-types/builders/interaction/choice"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local jsp = require"@antiraid-ext/utils/jobserverpoll"
local interop = require"@antiraid/interop"
local typesext = require"@antiraid/typesext"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"
local discord = require "@discord-types/apiTypes"

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
                    :setType("Boolean")
                    :setName("attachments")
                    :setDescription("Whether to include attachments in the backup. Requires 'messages' to be enabled")
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
                    :setType("Boolean")
                    :setName("rollover_leftovers")
                    :setDescription("Roll over leftover message quotas to other channels. May make backups slower. Defaults to true")
                    :setRequired(false)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Boolean")
                    :setName("ignore_message_backup_errors")
                    :setDescription("Whether to ignore errors while backing up messages or not and skip these channels. Defaults to true")
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
                    :setType("Boolean")
                    :setName("ignore_restore_errors")
                    :setDescription("Whether to ignore errors while restoring or not. Defaults to true")
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
            :option(
                function(opt)
                    return opt
                    :setType("String")
                    :setName("channel_restore_mode")
                    :setDescription("Channel backup restore method. Use 'full' if unsure")
                    :addChoice(
                        interactionChoiceBuilder.new()
                        :setName("Full")
                        :setValue("full")
                        :build()
                    )
                    :addChoice(
                        interactionChoiceBuilder.new()
                        :setName("Ignore Existing")
                        :setValue("ignore_existing")
                        :build()
                    )
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


--- Options available for backing up servers
export type BackupCreateOpts = {
    --- Channels to backup messages from, otherwise all channels will have messages backed up
    Channels: {string}?,
    --- The number of messages per channel to backup
    PerChannel: number,
    --- The maximum number of messages to backup
    MaxMessages: number,
    --- Whether to backup messages or not
    BackupMessages: boolean?,
    --- What assets to back up in comma-separated form (icon,splash,banner)
    BackupGuildAssets: {string},
    --- Whether to ignore errors while backing up messages or not and skip these channels
    IgnoreMessageBackupErrors: boolean?,
    --- Whether to attempt rollover of leftover message quota to another channels or not
    RolloverLeftovers: boolean?,
    --- Specific channel allocation overrides. Format: channel_id=number,channel_id=number
    SpecialAllocations: {[string]: number},
    --- Password to encrypt the backup with. If not provided, the backup will not be encrypted
    Encrypt: string?,
}

--[[
    IgnoreRestoreErrors bool               `description:"Whether to ignore errors while restoring or not and skip these channels/roles"`
    ProtectedChannels   []string           `description:"Channels to protect from being deleted"`
    ProtectedRoles      []string           `description:"Roles to protect from being deleted"`
    BackupSource        string             `description:"The source of the backup"`
    Decrypt             string             `description:"The key to decrypt backups with, if any"`
    ChannelRestoreMode  ChannelRestoreMode `description:"Channel backup restore method. Use 'full' if unsure"`
    RoleRestoreMode     RoleRestoreMode    `description:"Role backup restore method. Use 'full' if unsure"`
]]

export type BackupRestoreOpts = {
    --- Whether to ignore errors while restoring or not and skip these channels/roles
    IgnoreRestoreErrors: boolean?,
    --- Channels to protect from being deleted
    ProtectedChannels: {string},
    --- Roles to protect from being deleted
    ProtectedRoles: {string},
    --- The source of the backup
    BackupSource: string,
    --- The key to decrypt backups with, if any
    Decrypt: string?,
    --- Channel backup restore method. Use 'full' if unsure
    ChannelRestoreMode: "full" | "ignore_existing",
}

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "create" then
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            error("JobServerStore is not available in the context")
        end

        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.create"
        )

        local opts: BackupCreateOpts = {
            Channels = nil,
            PerChannel = 100,
            MaxMessages = 500,
            BackupMessages = false,
            BackupGuildAssets = {"icon","splash","banner"},
            IgnoreMessageBackupErrors = true,
            RolloverLeftovers = true,
            SpecialAllocations = {},
            Encrypt = ""
        }

        for _, opt in data.command.options do 
            if opt.name == "channels" then
                if opt.value.kind == "String" then 
                    opts.Channels = string.split(opt.value.value, ",")
                end
            elseif opt.name == "per_channel" then
                if opt.value.kind == "Integer" then
                    opts.PerChannel = opt.value.value
                end
            elseif opt.name == "max_messages" then
                if opt.value.kind == "Integer" then
                    opts.MaxMessages = opt.value.value
                end
            elseif opt.name == "messages" then
                if opt.value.kind == "Boolean" then
                    opts.BackupMessages = opt.value.value
                end
            elseif opt.name == "backup_guild_assets" then
                if opt.value.kind == "String" then
                    opts.BackupGuildAssets = string.split(opt.value.value, ",")
                end
            elseif opt.name == "ignore_message_backup_errors" then
                if opt.value.kind == "Boolean" then
                    opts.IgnoreMessageBackupErrors = opt.value.value
                end
            elseif opt.name == "rollover_leftovers" then
                if opt.value.kind == "Boolean" then
                    opts.RolloverLeftovers = opt.value.value
                end
            elseif opt.name == "special_allocations" then
                if opt.value.kind == "String" then 
                    local specialAllocationsStr = opt.value.value
                    for _, pair in string.split(specialAllocationsStr, ",") do
                        local key, value = string.match(pair, "(%d+)=(%d+)")
                        if key and value then
                            opts.SpecialAllocations[key] = tonumber(value)
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
                    opts.Encrypt = opt.value.value
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
                    description = "Spawning backup job...",
                },
            },
            true
        )

        data.sethasEdited(true)

        -- Now spawn the job to create the backup
        local jobId = jss.spawn({
            name = "guild_create_backup",
            data = {
                Options = opts
            },
            create = true,
            execute = true,
        })

        jsp.pollJobserverTillComplete(
            data.ctx, 
            {
                jobId = jobId,
                poll_interval = POLL_INTERVAL_CREATE,
                callback = function(job) 
                    local embed, components = jsp.jobToEmbed(
                        data.ctx,
                        job,
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

                    return nil
                end
            }
        )

        return nil
    elseif cmdname == "restore" then
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            error("JobServerStore is not available in the context")
        end

        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.restore"
        )

        local opts: BackupRestoreOpts = {
            IgnoreRestoreErrors = true,
            ProtectedChannels = setmetatable({}, interop.array_metatable),
            ProtectedRoles = setmetatable({}, interop.array_metatable),
            BackupSource = "",
            Decrypt = "",
            ChannelRestoreMode = "full",
        }

        if data.interaction.channel_id then 
            opts.ProtectedChannels = {data.interaction.channel_id}
        end

        for _, opt in data.command.options do 
            if opt.name == "backup_file" then
                if opt.value.kind == "Attachment" then
                    opts.BackupSource = opt.value.attachment.url or error("No valid URL found for the backup file")
                end
            elseif opt.name == "backup_id" then
                if opt.value.kind == "String" then
                    if opts.BackupSource ~= "" then
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

                    local job = jss.get(opt.value.value, false)

                    if job.name ~= "guild_create_backup" then
                        return interactionutils.replySimple(
                            data.ctx,
                            data.interaction,
                            nil,
                            {
                                {
                                    title = "Error processing command",
                                    description = "The provided job ID does not correspond to a valid backup creation job. Please check the ID and try again (got job type: " .. job.name .. ").",
                                },
                            },
                            false
                        )
                    end

                    if not job.job_file_path then
                        return interactionutils.replySimple(
                            data.ctx,
                            data.interaction,
                            nil,
                            {
                                {
                                    title = "Error processing command",
                                    description = "No backup file found for the given backup ID. Please check the ID and try again.",
                                },
                            },
                            false
                        )
                    end

                    opts.BackupSource = string.format("job:///%s", job.job_file_path)
                end
            elseif opt.name == "password" then
                if opt.value.kind == "String" then
                    opts.Decrypt = opt.value.value
                end
            elseif opt.name == "ignore_restore_errors" then
                if opt.value.kind == "Boolean" then
                    opts.IgnoreRestoreErrors = opt.value.value
                end
            elseif opt.name == "protected_channels" then
                if opt.value.kind == "String" then 
                    local pc = string.split(opt.value.value, ",")
                    for _, channelId in pc do
                        -- remove any whitespace
                        channelId = channelId:gsub("%s+", "")
                        if channelId ~= "" then
                            table.insert(opts.ProtectedChannels, channelId)
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
                            table.insert(opts.ProtectedRoles, roleId)
                        end
                    end
                end
            elseif opt.name == "channel_restore_mode" then 
                if opt.value.kind == "String" and (opt.value.value == "full" or opt.value.value == "ignore_existing") then 
                    opts.ChannelRestoreMode = opt.value.value
                end
            end
        end

        -- Check if we have a backup source
        if (opts.BackupSource :: string) == "" then
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

        -- Now spawn the job to restore the backup
        local jobId = jss.spawn({
            name = "guild_restore_backup",
            data = {
                Options = opts
            },
            create = true,
            execute = true,
        })

        jsp.pollJobserverTillComplete(
            data.ctx, 
            {
                jobId = jobId,
                poll_interval = POLL_INTERVAL_RESTORE,
                callback = function(job) 
                    local embed, components = jsp.jobToEmbed(
                        data.ctx,
                        job,
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

                    return nil
                end
            }
        )

        return nil
    elseif cmdname == "list" then
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            error("JobServerStore is not available in the context")
        end

        local lss = data.ctx.DataStores.LinksStore
        if not lss then
            error("LinksStore is not available in the context")
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction),
            "backups.list"
        )

        local backups = jss.list_named("guild_create_backup", false)
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

        local currentJobIdx = 1

        local jlPrevId = `helpcmd:prev:${typesext.randstring(16)}`
        local jlNextId = `helpcmd:next:${typesext.randstring(16)}`
    
        local prevButton = ButtonBuilder.new()
        :setStyle("Grey")
        :setLabel("Previous Page")
        :setCustomId(jlPrevId)
    
        local nextButton = ButtonBuilder.new()
        :setStyle("Grey")
        :setLabel("Next Page")
        :setCustomId(jlNextId)
        
        task.delay(120, function() 
            data.dropButtonCallback(jlPrevId) -- Make sure to remove the callback so it doesn't get called again
            data.dropButtonCallback(jlNextId) -- Make sure to remove the callback so it doesn't get called again
        end)    

        local authorId = extractUserIdFromInteraction(data.interaction)
        data.attachButtonCallback(jlPrevId, function(data: data.ButtonCallbackData): nil 
            local interactor = extractUserIdFromInteraction(data.interaction)
            if authorId ~= interactor then return nil end
            
            currentJobIdx -= 1
            if currentJobIdx < 1 then
                currentJobIdx = 1
            end

            local embed, _ = jsp.jobToEmbed(
                data.ctx,
                backups[currentJobIdx],
                false,
                true
            )

            if embed.title then
                embed.title ..= string.format(" (%d/%d)", currentJobIdx, #backups)
            end
    
            interactionutils.replyUpdate(
                data.ctx,
                data.interaction,
                nil,
                {embed},
                {
                    ActionRowBuilder.new()
                    :addComponent(
                        prevButton:build()
                    )
                    :addComponent(
                        nextButton:build()
                    )
                    :build() :: discord.ComponentObjects
                }
            )

            return nil
        end)

        data.attachButtonCallback(jlNextId, function(data: data.ButtonCallbackData): nil 
            local interactor = extractUserIdFromInteraction(data.interaction)
            if authorId ~= interactor then return nil end
            currentJobIdx += 1
            if currentJobIdx > #backups then
                currentJobIdx = #backups
            end

            local embed, _ = jsp.jobToEmbed(
                data.ctx,
                backups[currentJobIdx],
                false,
                true
            )

            if embed.title then
                embed.title ..= string.format(" (%d/%d)", currentJobIdx, #backups)
            end

            interactionutils.replyUpdate(
                data.ctx,
                data.interaction,
                nil,
                {embed},
                {
                    ActionRowBuilder.new()
                    :addComponent(
                        prevButton:build()
                    )
                    :addComponent(
                        nextButton:build()
                    )
                    :build() :: discord.ComponentObjects
                }
            )
    
            return nil    
        end)

        local embed, _ = jsp.jobToEmbed(
            data.ctx,
            backups[currentJobIdx],
            false,
            true
        )

        if embed.title then
            embed.title ..= string.format(" (%d/%d)", currentJobIdx, #backups)
        end

        interactionutils.replySimple(
            data.ctx, 
            data.interaction,
            nil, 
            {embed},
            true,
            {
                ActionRowBuilder.new()
                :addComponent(
                    prevButton:build()
                )
                :addComponent(
                    nextButton:build()
                )
                :build() :: discord.ComponentObjects
            }
        )
    
        data.sethasEdited(true)
        return nil    
    elseif cmdname == "delete" then
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            error("JobServerStore is not available in the context")
        end
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
        jss.delete(backupId)
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
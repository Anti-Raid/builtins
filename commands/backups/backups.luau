local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local extractUserIdFromInteraction = require "../../utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "../../utils/modhierarchy".canModeratorDo
local jsp = require"../../utils/jobserverpoll"

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
    :build()
end

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
    --- Whether to backup attachments or not. Requires 'messages' to be enabled
    BackupAttachments: boolean?,
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
            data.ctx,
            extractUserIdFromInteraction(data.interaction),
            "backups.create"
        )

        local opts: BackupCreateOpts = {
            Channels = nil,
            PerChannel = 100,
            MaxMessages = 500,
            BackupMessages = false,
            BackupAttachments = false,
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
            elseif opt.name == "attachments" then
                if opt.value.kind == "Boolean" then
                    opts.BackupAttachments = opt.value.value
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
            false
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
                callback = function(job) 
                    local embed, components = jsp.jobToEmbed(
                        lss.links().api_url,
                        job,
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
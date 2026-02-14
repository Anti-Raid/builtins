local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local discord = require "@discord-types/apiTypes"
local paginate = require "@antiraid-ext/framework/paginate"
local embed = require "../../auxutils/backups/embed"

local createcmd = require "./create"
local restorecmd = require "./restore"

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

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "create" then
        return createcmd(data)
    elseif cmdname == "restore" then
        return restorecmd(data)
    elseif cmdname == "list" then
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

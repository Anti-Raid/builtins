local commandBuilder = require "@discord-types/builders/interaction/interaction"
local interactionChoiceBuilder = require "@discord-types/builders/interaction/choice"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"

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

local function run(data: data.RunData): nil
    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "Currently Disabled",
                description = "Backups is currently temporarily disabled as it is being rewritten and migrated to a faster and more maintainable system. Please try again later.\n\nThank you for your patience.",
            },
        },
        false
    )
end

return {
    register = register,
    run = run,
}
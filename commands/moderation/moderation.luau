local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "@antiraid-ext/utils/interaction"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local permissions = require "@discord-types/permission"
local permissionsFromBf = permissions.fromBitFlag

local function register() 
    return commandBuilder.new({
        name = "moderation",
        description = "Moderation related commands"
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("ban")
            :setDescription("Ban a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to ban")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for the ban")  
                    :setRequired(true)
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("delete_message_days")
                    :setDescription("Number of days to prune messages for. Mutually exclusive with delete_message_seconds")  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("delete_message_seconds")
                    :setDescription("Number of seconds to prune messages for. Mutually exclusive with delete_message_days")  
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
            :setName("unban")
            :setDescription("Unbans a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to unban")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for the unban")  
                    :setRequired(true)
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
            :setName("kick")
            :setDescription("Kick a user from the server")  
            :option(
                function(opt) 
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("User to kick")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for kicking the user")  
                    :setRequired(true)
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
            :setName("purge")
            :setDescription("Bulk delete messages from a channel")
            :option(
                function(opt)
                    return opt
                    :setType("Integer")
                    :setName("amount")
                    :setDescription("Number of messages to delete (max 100)")
                    :setRequired(true)
                    :setMinValue(1)
                    :setMaxValue(100)
                    :build()
                end
            )
            :option(
                function(opt)
                    return opt
                    :setType("String")
                    :setName("reason")
                    :setDescription("Reason for purging messages")
                    :setRequired(true)
                    :build()
                end
            )
            :option(
                function(opt)
                    return opt
                    :setType("User")
                    :setName("user")
                    :setDescription("Only delete messages from this user")
                    :setRequired(false)
                    :build()
                end
            )
            :option(
                function(opt)
                    return opt
                    :setType("Integer")
                    :setName("days")
                    :setDescription("Number of days to look back for messages (default: 14, max: 14)")
                    :setRequired(false)
                    :setMinValue(1)
                    :setMaxValue(14)
                    :build()
                end
            )
            :option(
                function(opt)
                    return opt
                    :setType("Channel")
                    :setName("channel")
                    :setDescription("Channel to purge messages from (default: current channel)")
                    :setRequired(false)
                    :build()
                end
            )
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2] -- Changed back to 2 since we removed the actions group

    if cmdname == "ban" then
        local userid = nil
        local reason = nil
        local delete_message_seconds = 0

        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    userid = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    userid = opt.value.id
                end
            end

            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end

            if opt.name == "delete_message_days" then
                if opt.value.kind == "Integer" then
                    delete_message_seconds += opt.value.value * 86400 -- Convert days to seconds
                end
            end

            if opt.name == "delete_message_seconds" then
                if opt.value.kind == "Integer" then
                    delete_message_seconds += opt.value.value -- Already in seconds
                end
            end
        end

        if not userid then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot ban unknown user!",
                        description = "No user specified",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        if not reason or reason == "" then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot ban user without a reason!",
                        description = "Please provide a reason for the ban",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        data.punishmentmanager.createUserPunishment({
            userId = userid,
            punishment = "ban",
            modId = extractUserIdFromInteraction(data.interaction),
            reason = reason,
            delete_message_seconds = delete_message_seconds,
        })

        data.sethasEdited(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Successfully banned user",
                    description = "User <@" .. userid .. "> was successfully banned from this server!",
                    color = 0x00FF00
                },
            },
            false
        )
    elseif cmdname == "unban" then
        local userid = nil
        local reason = nil

        for _, opt in data.command.options do
            if opt.name == "user" then
                if opt.value.kind == "User" then
                    userid = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    userid = opt.value.id
                end
            end

            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end
        end

        if not userid then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot unban unknown user!",
                        description = "No user specified",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        if not reason or reason == "" then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot unban user without a reason!",
                        description = "Please provide a reason for the unban",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        data.punishmentmanager.reversePunishmentClass(
            userid,
            extractUserIdFromInteraction(data.interaction),
            "ban",
            reason
        )

        data.sethasEdited(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Successfully unbanned user",
                    description = "User <@" .. userid .. "> was successfully unbanned from this server!",
                    color = 0x00FF00
                },
            },
            false
        )
    elseif cmdname == "kick" then
        local userid = nil
        local reason = nil

        for _, opt in data.command.options do 
            if opt.name == "user" then 
                if opt.value.kind == "User" then
                    userid = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    userid = opt.value.id
                end
            end

            if opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            end
        end

        if not userid then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot kick unknown user!",
                        description = "No user specified",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        if not reason or reason == "" then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Cannot kick user without a reason!",
                        description = "Please provide a reason for the kick",
                        color = 0xFF0000,
                    },
                },
                false
            )
        end

        data.punishmentmanager.createUserPunishment({
            userId = userid,
            punishment = "kick",
            modId = extractUserIdFromInteraction(data.interaction),
            reason = reason,
        })

        data.sethasEdited(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Successfully kicked user",
                    description = "User <@" .. userid .. "> was successfully kicked from this server!",
                    color = 0x00FF00
                },
            },
            false
        )
elseif cmdname == "purge" then
        local amount = nil
        local user_id = nil
        local reason = nil
        local days = 14  -- Default to 14 days if not specified
        local channel_id = data.interaction.channel_id  -- Default to current channel
        local channels = {}  -- Will be populated based on channel_id

        for _, opt in data.command.options do
            if opt.name == "amount" then
                if opt.value.kind == "Integer" then
                    amount = math.clamp(opt.value.value, 1, 100)
                end
            elseif opt.name == "user" then
                if opt.value.kind == "User" then
                    user_id = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    user_id = opt.value.id
                end
            elseif opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            elseif opt.name == "days" then
                if opt.value.kind == "Integer" then
                    days = math.clamp(opt.value.value, 1, 14)
                end
            elseif opt.name == "channel" then
                if opt.value.kind == "Channel" then
                    channel_id = opt.value.channel.id
                end
            end
        end

        if not amount or not reason then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Amount and reason are required for purge command",
                    },
                },
                true
            )
        end

        -- Add the selected channel to the channels list
        table.insert(channels, channel_id)

        -- Check if user has permission to purge messages
        local moderator = data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction)
        local discordPerms = permissionsFromBf(moderator.discord_permissions)
        local hasManageMessages = false
        for _, perm in discordPerms do
            if perm == "ManageMessages" then
                hasManageMessages = true
                break
            end
        end
        if not hasManageMessages then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Permission Denied",
                        description = "You need the Manage Messages permission to use this command",
                    },
                },
                true
            )
        end

        -- Check if JobServerStore is available
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error",
                        description = "JobServerStore is not available in the context",
                        color = 0xFF0000
                    },
                },
                true
            )
        end

        -- Submit purge job to jobserver
        local jobId = jss.spawn({
            name = "message_prune",
            data = {
                Options = {
                    per_channel = math.max(amount, 100),  -- Use amount or minimum 100, whichever is higher
                    max_messages = amount,
                    prune_from = days * 24 * 60 * 60,
                    rollover_leftovers = false,
                    special_allocations = {},
                    channels = channels,
                    user_id = user_id
                }
            },
            create = true,
            execute = true
        })

        -- Send confirmation
        data.sethasEdited(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Purge Started",
                    description = string.format(
                        "Starting to purge %d messages%s in <#%s>\nLooking back %d days\nReason: %s", 
                        amount,
                        user_id and string.format(" from <@%s>", user_id) or "",
                        channel_id,
                        days,
                        reason
                    ),
                    color = 0x00FF00
                },
            },
            true
        )
    elseif cmdname == "purge" then
        local amount = nil
        local user_id = nil
        local reason = nil
        local days = 14  -- Default to 14 days if not specified
        local channel_id = data.interaction.channel_id  -- Default to current channel
        local channels = {}  -- Will be populated based on channel_id

        for _, opt in data.command.options do
            if opt.name == "amount" then
                if opt.value.kind == "Integer" then
                    amount = math.clamp(opt.value.value, 1, 100)
                end
            elseif opt.name == "user" then
                if opt.value.kind == "User" then
                    user_id = opt.value.user.id
                elseif opt.value.kind == "Unresolved" then
                    user_id = opt.value.id
                end
            elseif opt.name == "reason" then
                if opt.value.kind == "String" then
                    reason = opt.value.value
                end
            elseif opt.name == "days" then
                if opt.value.kind == "Integer" then
                    days = math.clamp(opt.value.value, 1, 14)
                end
            elseif opt.name == "channel" then
                if opt.value.kind == "Channel" then
                    channel_id = opt.value.channel.id
                end
            end
        end

        if not amount or not reason then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Amount and reason are required for purge command",
                    },
                },
                true
            )
        end

        -- Add the selected channel to the channels list
        table.insert(channels, channel_id)

        -- Check if user has permission to purge messages
        local moderator = data.userinfomanager.get(extractUserIdFromInteraction(data.interaction), data.interaction)
        local discordPerms = permissionsFromBf(moderator.discord_permissions)
        local hasManageMessages = false
        for _, perm in discordPerms do
            if perm == "ManageMessages" then
                hasManageMessages = true
                break
            end
        end
        if not hasManageMessages then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Permission Denied",
                        description = "You need the Manage Messages permission to use this command",
                    },
                },
                true
            )
        end

        -- Check if JobServerStore is available
        local jss = data.ctx.DataStores.JobServerStore
        if not jss then
            data.sethasEdited(true)
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error",
                        description = "JobServerStore is not available in the context",
                        color = 0xFF0000
                    },
                },
                true
            )
        end

        -- Submit purge job to jobserver
        local jobId = jss.spawn({
            name = "message_prune",
            data = {
                Options = {
                    PerChannel = 20,  -- Remove the math.max(amount, 100)
                    MaxMessages = 10,
                    PruneFrom = days * 24 * 60 * 60 * 1000000000,  -- Convert to nanoseconds
                    RolloverLeftovers = false,
                    SpecialAllocations = {},
                    Channels = channels,
                    UserID = user_id,  -- Capital U
                    -- Remove non-Options fields:
                    -- channel_id, amount, reason, moderator_id don't belong in Options
                }
            },
            create = true,
            execute = true
        })

        -- Send confirmation
        data.sethasEdited(true)
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Purge Started",
                    description = string.format(
                        "Starting to purge %d messages%s in <#%s>\nLooking back %d days\nReason: %s\nJob ID: %s", 
                        amount,
                        user_id and string.format(" from <@%s>", user_id) or "",
                        channel_id,
                        days,
                        reason,
                        jobId
                    ),
                    color = 0x00FF00
                },
            },
            true
        )
    else 
        data.sethasEdited(true)
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
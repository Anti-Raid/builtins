local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local extractUserIdFromInteraction = require "../../utils/modhierarchy".extractUserIdFromInteraction

local function register() 
    return commandBuilder.new({
        name = "moderation",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Moderation related commands")
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
                    :setDescription("Reason for the ban")  
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
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

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
            punishment = "ban",
            modId = extractUserIdFromInteraction(data.interaction),
            reason = reason,
        })

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
    --return
end

return {
    register = register,
    run = run,
}
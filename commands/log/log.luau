local commandBuilder = require "@discord-types/builders/interaction/interaction"
local apitypes = require "@discord-types/apiTypes"
local data = require "../data"
local interactionutils = require "../../utils/interaction"
local canModeratorDo = require "../../utils/modhierarchy".canModeratorDo
local canBotDoInChannel = require "../../utils/modhierarchy".canBotDoInChannel
local permissions = require "@discord-types/permission"
local permissionsToBf = permissions.toBitFlag

local function register() 
    return commandBuilder.new({
        name = "log",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Set a log channel. Omitting channel will delete the log channel.")
    :option(
        function(opt) 
            return opt
            :setType("Channel")
            :setName("channel")
            :setDescription("The channel")  
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("String")
            :setName("action")
            :setDescription("The action this channel should be used for in terms of logging")
            :setAutocompleteEnabled(true) 
            :build()      
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("Boolean")
            :setName("ephemeral")
            :setDescription("Whether to make the response ephemeral or not")
            :build()
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("Boolean")
            :setName("view")
            :setDescription("View the current log channel configuration. Conflicts with channel")  
            :setRequired(false)
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local channel: apitypes.ChannelObject? = nil
    local action: string? = nil
    local isResponseEphemeral = false
    local view: boolean? = nil

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "channel" then
            if opt.value.kind == "Channel" then
                channel = opt.value.channel
            end
        end

        if opt.name == "action" then
            if opt.value.kind == "String" then
                action = opt.value.value
            end
        end

        if opt.name == "view" then
            if opt.value.kind == "Boolean" then
                view = opt.value.value
            end
        end

        if opt.name == "ephemeral" then
            if opt.value.kind == "Boolean" then
                isResponseEphemeral = opt.value.value
            end
        end
    end  

    if not data.interaction.user then 
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "Something went wrong while trying to find the user. Please try again?",
                },
            },
            isResponseEphemeral
        )
    end

    if view and channel then
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "You cannot view the log channel and set it at the same time. Please try again?",
                    color = 0xFF0000,
                },
            },
            isResponseEphemeral
        )
    end

    if not action and not view then
        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Error processing command",
                    description = "You must specify either `action`, `view` or both.",
                    color = 0xFF0000,
                },
            },
            isResponseEphemeral
        )
    end

    if view then 
        canModeratorDo(
            data.ctx,
            data.ge,
            data.interaction.user.id,
            "moderation.viewlogchannel"
        )

        local logChannels = data.builtinSettingsManager.getAllModLogsChannels()

        local fields: {apitypes.EmbedFieldObject} = {}

        for caction, channelid in logChannels do
            if action and action ~= caction then
                continue
            end
            table.insert(fields, {
                name = tostring(caction or "default"),
                value = "<#" .. channelid .. ">",
                inline = true,
            })
        end

        if #fields == 0 then
            return interactionutils.replySimple(
                data.ge,
                data.interaction,
                nil,
                {
                    {
                        title = "No log channels set",
                        description = if action then "There is no log channel set for this action yet" else "There are no log channels set for this server",
                        color = 0xFF0000,
                    },
                },
                isResponseEphemeral
            )
        end

        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Log channels",
                    description = "The following log channels are set for this server",
                    fields = fields,
                },
            },
            isResponseEphemeral
        )
    end

    -- Check that the user has the right permissions
    canModeratorDo(
        data.ctx,
        data.ge,
        data.interaction.user.id,
        "moderation.setlogchannel"
    )

    if not channel then
        -- The user wants to remove the log channel
        data.builtinSettingsManager.deleteModLogsChannel(action)

        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Log channel removed",
                    description = if action then "The log channel for " .. action .. " has been unset" else "The default log channel has been unset",
                },
            },
            isResponseEphemeral
        )
    else 
        -- The user wants to set the log channel
        canBotDoInChannel(
            channel.id or error("Channel ID is nil"),
            data.ctx,
            data.ge,
            permissionsToBf({"SendMessages", "EmbedLinks", "ReadMessageHistory"})
        )

        if not channel.id then
            error("Channel ID is nil")
        end

        data.builtinSettingsManager.setModLogsChannel(
            action,
            channel.id
        )

        return interactionutils.replySimple(
            data.ge,
            data.interaction,
            nil,
            {
                {
                    title = "Log channel set",
                    description = if action then "The log channel for " .. action .. " has been set to <#" .. channel.id .. ">" else "The default log channel has been set to <#" .. channel.id .. ">",
                },
            },
            isResponseEphemeral
        )
    end
end

local function autocompleter(data: data.AutocompleteRunData): {apitypes.ApplicationCommandOptionChoiceObject}
    local choices: {apitypes.ApplicationCommandOptionChoiceObject} = {}

    if data.command.baseName == "log" and data.command.options then
        for _, opt in data.command.options do
            if opt.name == "action" and opt.value.kind == "String" and opt.focused then
                local valueInput = opt.value.value
                for _, action in data.builtinSettingsManager.getAllModLogsActions() do
                    -- If the action starts with the input value [case insensitive], add it to the choices
                    if string.find(action.name:lower(), (valueInput :: string):lower(), 1, true) then
                        table.insert(choices, {
                            name = action.name,
                            value = action.value,
                        })
                    end
                end
            end
        end
    end

    return choices
end

return {
    register = register,
    run = run,
    autocompleter = autocompleter,
}
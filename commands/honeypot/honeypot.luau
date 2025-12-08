local discord = require "@discord-types/apiTypes"
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local HoneypotManager = require "../../auxutils/honeypotmanager"
local registerEvent = require "@antiraid-ext/utils/eventmgmt".registerEvent
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local canModeratorDo = require "@antiraid-ext/utils/modhierarchy".canModeratorDo
local paginate = require "@antiraid-ext/framework/paginate"

local function register() 
    return commandBuilder.new({
        name = "honeypot",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Setup honeypot channels")
    :option(
        function(opt)
            return opt
            :setType("SubCommand")
            :setName("list")
            :setDescription("List all honeypot channels")
            :build()  
        end     
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("setup")
            :setDescription("Sets up a channel as a honeypot")  
            :option(
                function(opt) 
                    return opt
                    :setType("Channel")
                    :setName("channelid")
                    :setDescription("The channel to set as a honeypot")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Boolean")
                    :setName("botallowed")
                    :setDescription("Whether bots are allowed to message in this honeypot")  
                    :setRequired(true)
                    :build()      
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("punishment")
                    :setDescription("What punishment to apply (ban/kick)")
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
            :setName("remove")
            :setDescription("Remove a honeypot from a channel")
            :option(
                function(opt) 
                    return opt
                    :setType("Channel")
                    :setName("channelid")
                    :setDescription("The honeypot channel to remove")  
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

    if cmdname == "list" then
        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction)),
            "honeypots.list"
        )

        local honeypots = HoneypotManager(data.ctx).list()
        if #honeypots == 0 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No Honeypots",
                        description = "There are currently no honeypot channels set up.",
                        color = 0xffff00, -- Yellow color
                    },
                },
                false
            )
        end

        local honeypotEmbeds: {discord.EmbedObject} = {}
        for _, honeypot in honeypots do
            table.insert(honeypotEmbeds, {
                title = "Honeypot Channel",
                description = string.format(
                    "Channel ID: `%s`\nBots Allowed: `%s`\nPunishment: `%s`\nCreated At: `%s`",
                    honeypot.channelid,
                    tostring(honeypot.botallowed),
                    honeypot.punishment,
                    tostring(honeypot.created_at)
                ),
                color = 0x00ffff, -- Cyan color
            } :: discord.EmbedObject)
        end

        paginate.paginate(data, {
            id = "honeypot_list",
            numPages = #honeypotEmbeds,
            embed = function(currentIdx: number): discord.EmbedObject 
                return honeypotEmbeds[currentIdx]
            end
        })
        return nil    
    elseif cmdname == "add" then
        local channelid: string? = nil
        local botallowed: boolean? = nil
        local punishment: string? = nil

        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "channelid" then
                if opt.value.kind == "Channel" then
                    channelid = opt.value.channel.id
                end
            end
            if opt.name == "botallowed" then
                if opt.value.kind == "Boolean" then
                    botallowed = opt.value.value
                end
            end
            if opt.name == "punishment" then
                if opt.value.kind == "String" then
                    punishment = opt.value.value
                end
            end
        end  

        -- Recast due to type checking limitations
        channelid = channelid :: string
        botallowed = botallowed :: boolean
        punishment = punishment :: string

        -- TODO: Add more options here
        if punishment ~= "ban" and punishment ~= "kick" then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Invalid punishment",
                        description = "Punishment must be either 'ban' or 'kick'.",
                        color = 0xff0000, -- Red color
                    },
                },
                false
            )
        end
        
        if not channelid or not botallowed or not punishment then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find options. Please try again?",
                        color = 0xff0000, -- Red color
                    },
                },
                false
            )
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction)),
            "honeypots.add"
        )
        
        HoneypotManager(data.ctx).set({
            channelid = channelid,
            botallowed = botallowed,
            punishment = punishment,
        })

        registerEvent(data.ctx, "MESSAGE")

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Honeypot Added/Updated",
                    description = "Honeypot successfully added/updated for the specified channel.",
                    color = 0x00ff00, -- Green color
                },
            },
            false
        )
    elseif cmdname == "remove" then
        local channelid: string? = nil
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "channelid" then
                if opt.value.kind == "Channel" then
                    channelid = opt.value.channel.id
                end
            end
        end

        if not channelid then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Error processing command",
                        description = "Something went wrong while trying to find channel id. Please try again?",
                        color = 0xff0000, -- Red color
                    },
                },
                false
            )
        end

        canModeratorDo(
            data.userinfomanager.get(extractUserIdFromInteraction(data.interaction)),
            "honeypots.remove"
        )

        local honeypots = HoneypotManager(data.ctx).list()
        for _, honeypot in honeypots do
            if honeypot.channelid == channelid then
                HoneypotManager(data.ctx).delete(channelid)
                return interactionutils.replySimple(
                    data.ctx,
                    data.interaction,
                    nil,
                    {
                        {
                            title = "Honeypot Removed",
                            description = "Honeypot successfully removed from the specified channel.",
                            color = 0x00ff00, -- Green color
                        },
                    },
                    false
                )
            end
        end

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Honeypot Not Found",
                    description = "No honeypot found for the specified channel.",
                    color = 0xff0000, -- Red color
                },
            },
            false
        )
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

return {
    register = register,
    run = run,
}
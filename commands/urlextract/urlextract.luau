local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local interactionutils = require "@antiraid-ext/utils/interaction"
local parseUrls = require "@antiraid-ext/utils/urlextractor".parseUrls

local function register() 
    return commandBuilder.new({
        name = "urlextract",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Extracts URLs from a message")
    :option(
        function(opt) 
            return opt
            :setType("String")
            :setName("message")
            :setDescription("The message to extract URLs from")  
            :setRequired(true)
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local message: string? = nil

    -- Parse options
    for _, opt in data.command.options do 
        if opt.name == "message" then 
            if opt.value.kind == "String" then
                message = opt.value.value
            end
        end
    end
    
    if not message then 
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "No message specified",
                    description = "Please specify a message to extract URLs from",
                },
            },
            false
        )
    end

    local urls = parseUrls(message)

    if #urls == 0 then 
        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "No URLs found",
                    description = "No URLs were found in the message",
                },
            },
            false
        )
    end

    local msgCount = 0
    for i = 1, #urls do
        if msgCount + #urls[i] > 4000 then
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Too many URLs",
                        description = "The message is too long. Please try again with fewer URLs.",
                    },
                },
                false
            )
        end

        urls[i] = "``" .. urls[i] .. "``"
        msgCount += #urls[i]
    end

    urls[1] = "- " .. urls[1]
    return interactionutils.replySimple(
        data.ctx,
        data.interaction,
        nil,
        {
            {
                title = "URLs found",
                description = table.concat(urls, "\n- "),
            },
        },
        false
    )
end

return {
    register = register,
    run = run,
}
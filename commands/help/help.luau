local commandBuilder = require "@discord-types/builders/interaction/interaction"
local discord = require "@discord-types/apiTypes"    
local data = require "../data"
local appcommands = require "@antiraid-ext/appcommands"
local interactionutils = require"@antiraid-ext/utils/interaction"
local typesext = require"@antiraid/typesext"
local ActionRowBuilder = require"@discord-types/builders/message/components/actionRow"
local ButtonBuilder = require"@discord-types/builders/message/components/button"

local function register() 
    return commandBuilder.new({
        name = "help",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Get... help using AntiRaid?")
    :build()
end

local function createHelpForCommand(fullCmdName: string, cmd: appcommands.ParsedCommandData)
    local commandDescription = cmd.description or "No description available."
    local commandOptions = cmd.options
    local commandSubcommands = cmd.subcommands

    local helpMessage = "``/" .. fullCmdName .. "``\n"
    helpMessage = helpMessage .. commandDescription .. "\n"

    if commandOptions and #commandOptions > 0 then
        helpMessage = helpMessage .. "Options:\n"
        for i, option in commandOptions do
            helpMessage ..= string.format("- %s [%s, %s]\n%s", option.name, option.type, if option.required then "required" else "optional", option.description or "No description available.")
            if i < #commandOptions then
                helpMessage ..= "\n"
            end
        end
    end

    if #commandSubcommands > 0 then
        for i, subcommand in commandSubcommands do
            helpMessage ..= createHelpForCommand(fullCmdName .. " " .. subcommand.name, subcommand)

            if i < #commandSubcommands then
                helpMessage ..= "\n\n"
            end
        end
    end

    return helpMessage
end

-- Splits the help description into pages of 2000 characters each
local function splitHelpDescriptionIntoPages(text: string, maxLength: number): {string} 
    local pages = {}
    
    local left = #text

    -- Use substring to take out first
    while left > 0 do
        local page = text:sub(1, maxLength)
        table.insert(pages, page)
        text = text:sub(maxLength + 1)
        left = #text
    end

    return pages
end

--assert(table.concat(splitHelpDescriptionIntoPages("ABC", 2), "<sep>") == "AB<sep>C", "Got: " .. table.concat(splitHelpDescriptionIntoPages("ABC", 2), "<sep>"))
--assert(table.concat(splitHelpDescriptionIntoPages("ABC", 3), "<sep>") == "ABC", "Got: " .. table.concat(splitHelpDescriptionIntoPages("ABC", 3), "<sep>"))
--assert(table.concat(splitHelpDescriptionIntoPages("ABC", 4), "<sep>") == "ABC", "Got: " .. table.concat(splitHelpDescriptionIntoPages("ABC", 4), "<sep>"))

if not _G.cachedHelpMessagePages then
    _G.cachedHelpMessagePages = {} :: any
end

local function renderPage(page: number)
    -- Needs to be done inside run to avoid circular dependency
    local commands = require"../commands"

    if #_G.cachedHelpMessagePages == 0 then
        local helpMessagePages = {}
        for commandName, command in commands.commands do
            local parsedCommands = appcommands.parseApplicationCommandData(command().register())
            local helpText = createHelpForCommand(commandName, parsedCommands)
            
            for _, v in splitHelpDescriptionIntoPages(helpText, 4000) do 
                table.insert(helpMessagePages, v)
            end
        end
        
        _G.cachedHelpMessagePages = helpMessagePages
    end

    local helpMessageEmbed = {
        title = "Help (Page " .. page .. "/" .. #_G.cachedHelpMessagePages .. ")",
        description = _G.cachedHelpMessagePages[page],
        color = 0x00FF00,
    }

    return helpMessageEmbed
end

local function run(data: data.RunData): nil
    local page = 1

    local helpCustomPrevId = `helpcmd:prev:${typesext.randstring(16)}`
    local helpCustomNextId = `helpcmd:next:${typesext.randstring(16)}`

    local prevButton = ButtonBuilder.new()
    :setStyle("Grey")
    :setLabel("Previous Page")
    :setCustomId(helpCustomPrevId)

    local nextButton = ButtonBuilder.new()
    :setStyle("Grey")
    :setLabel("Next Page")
    :setCustomId(helpCustomNextId)

    task.delay(60, function() 
        data.dropButtonCallback(helpCustomPrevId) -- Make sure to remove the callback so it doesn't get called again
        data.dropButtonCallback(helpCustomNextId) -- Make sure to remove the callback so it doesn't get called again
    end)

    data.attachButtonCallback(helpCustomPrevId, function(data: data.ButtonCallbackData): nil         
        page -= 1
        if page < 1 then
            page = 1
        end

        interactionutils.replyUpdate(
            data.ctx,
            data.interaction,
            nil,
            {
                renderPage(page) :: discord.EmbedObject,
            },
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

    data.attachButtonCallback(helpCustomNextId, function(data: data.ButtonCallbackData): nil                 
        page += 1
        if page > #_G.cachedHelpMessagePages then
            page = #_G.cachedHelpMessagePages
        end
        
        interactionutils.replyUpdate(
            data.ctx,
            data.interaction,
            nil,
            {
                renderPage(page) :: discord.EmbedObject,
            },
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

    interactionutils.replySimple(
        data.ctx, 
        data.interaction,
        nil, 
        {renderPage(1)} :: {discord.EmbedObject},
        false,
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
end

return {
    register = register,
    run = run,
}
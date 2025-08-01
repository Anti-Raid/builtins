local commandBuilder = require "@discord-types/builders/interaction/interaction"
local discord = require "@discord-types/apiTypes"    
local data = require"@antiraid-ext/framework/coretypes"
local appcommands = require "@antiraid-ext/appcommands"
local paginate = require "@antiraid-ext/framework/paginate"

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

local cachedHelpMessagePages = {} :: {string}

local function createPagesIfNeeded() 
    -- Needs to be done inside run to avoid circular dependency
    local url = if true then "../commands" else ""
    local commands = require(url) :: { commands: {[string]: data.Command} }

    if #cachedHelpMessagePages == 0 then
        local helpMessagePages = {} :: {string}
        for _, command in commands.commands do
            local schema = command.command
            if command.register then 
                schema = command.register()
            end
            local parsedCommands = appcommands.parseApplicationCommandData(schema)
            local helpText = createHelpForCommand(parsedCommands.name, parsedCommands)
            
            for _, v in splitHelpDescriptionIntoPages(helpText, 4000) do 
                table.insert(helpMessagePages, v)
            end
        end
        
        cachedHelpMessagePages = helpMessagePages
    end
end

local function renderPage(page: number)
    local helpMessageEmbed = {
        title = "AntiRaid Help" ,
        description = cachedHelpMessagePages[page],
        color = 0x00FF00,
    }

    return helpMessageEmbed :: discord.EmbedObject
end

local function run(data: data.RunData): nil
    createPagesIfNeeded()
    paginate.paginate(data, {
        numPages = #cachedHelpMessagePages,
        id = "builtins.helpcmd",
        embed = renderPage
    })
    return nil
end

return {
    register = register,
    run = run,
}
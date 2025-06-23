local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require "../data"
local interactionutils = require "../../utils/interaction"

local function register() 
    return commandBuilder.new({
        name = "subcmdtest",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Test subcommand functionality")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("sub")
            :setDescription("Test subcommand")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("myarg")
                    :setDescription("My argument")  
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
            :setName("ban")
            :setDescription("Ban command")  
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("position")
                    :setDescription("My argument")  
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

    if cmdname == "sub" then
        local myarg: string? = nil
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "myarg" then
                if opt.value.kind == "String" then
                    myarg = opt.value.value
                end
            end
        end

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Subcommand",
                    description = "This is a subcommand " .. if myarg then myarg else "no argument",
                },
            },
            false
        )
    elseif cmdname == "ban" then
        local position: string? = nil
        -- Parse options
        for _, opt in data.command.options do 
            if opt.name == "position" then
                if opt.value.kind == "String" then
                    position = opt.value.value
                end
            end
        end

        return interactionutils.replySimple(
            data.ctx,
            data.interaction,
            nil,
            {
                {
                    title = "Ban command",
                    description = "This is a ban command " .. if position then position else "no argument",
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
end

return {
    register = register,
    run = run,
}
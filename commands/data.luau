local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local executor = require "@antiraid-ext/executor"
local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes" 

export type Command = {
    register: () -> discordRestTypes.CreateGuildApplicationCommandRequest,
    run: (data: RunData) -> (),
}

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    command: appcommands.ParsedApplicationCommand
}

return {}
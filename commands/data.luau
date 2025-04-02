local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local executor = require "@antiraid-ext/executor"
local discord = require "@discord-types/apiTypes"

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    command: appcommands.ParsedApplicationCommand
}

return {}
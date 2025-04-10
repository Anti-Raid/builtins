local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local executor = require "@antiraid-ext/executor"
local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes" 
local events = require "@antiraid-core/events"

export type Command = {
    register: () -> discordRestTypes.CreateGuildApplicationCommandRequest,
    run: (data: RunData) -> any,
    scheduledexec: ((data: ScheduledExecRunData) -> any)?,
}

export type ScheduledExecRunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event,
    scheduledExecData: events.ScheduledExecutionEventData,
    scheduledExecId: string,
    ge: executor.GlobalExecutor,
}

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    command: appcommands.ParsedApplicationCommand
}

return {}
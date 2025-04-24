local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local executor = require "@antiraid-ext/executor"
local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes" 
local events = require "@antiraid-core/events"
local stingmanager = require "../utils/stingmanager"
local builtinSettingsManager = require "../utils/builtinsettingsmanager"

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
    stingManager: stingmanager.StingManager,
    ge: executor.GlobalExecutor,
}

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    stingManager: stingmanager.StingManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager, 
    command: appcommands.ParsedApplicationCommand
}

return {}
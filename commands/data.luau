local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local executor = require "@antiraid-ext/executor"
local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes" 
local events = require "@antiraid-core/events"
local stingmanager = require "../utils/stingmanager"
local punishmentmanager = require"../utils/punishmentmanager"
local builtinSettingsManager = require "../utils/builtinsettingsmanager"

export type Command = {
    register: () -> discordRestTypes.CreateGuildApplicationCommandRequest,
    run: (data: RunData) -> any,
    scheduledexec: ((data: ScheduledExecRunData) -> any)?,
    autocompleter: ((data: AutocompleteRunData) -> {discord.ApplicationCommandOptionChoiceObject})?,
}

export type ScheduledExecRunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event,
    scheduledExecData: events.ScheduledExecutionEventData,
    scheduledExecId: string,
    stingManager: stingmanager.StingManager,
    ge: executor.GlobalExecutor,
}

export type ButtonCallbackData = {
    ctx: primitives.TemplateContext, 
    interaction: discord.InteractionObject, 
    removeCallback: () -> nil,
    event: primitives.Event,
    ge: executor.GlobalExecutor,
}

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    stingManager: stingmanager.StingManager,
    punishmentmanager: punishmentmanager.PunishmentManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager, 
    command: appcommands.ParsedApplicationCommand,
    attachButtonCallback: ((buttonId: string, callback: (bcd: ButtonCallbackData) -> nil) -> nil),
    dropButtonCallback: ((buttonId: string) -> nil),
    sethasEdited: (to: boolean) -> nil,
}

export type AutocompleteRunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    ge: executor.GlobalExecutor,
    stingManager: stingmanager.StingManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager, 
    command: appcommands.ParsedApplicationCommand,
}

return {}
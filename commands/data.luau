local appcommands = require "@antiraid-ext/appcommands"
local primitives = require "@antiraid-core/primitives"
local discord = require "@discord-types/apiTypes"
local discordRestTypes = require "@discord-types/restTypes" 
local events = require "@antiraid-core/events"
local stingmanager = require "../utils/stingmanager"
local punishmentmanager = require"../utils/punishmentmanager"
local builtinSettingsManager = require "../utils/builtinsettingsmanager"
local userinfomanager = require "../utils/userinfo"

export type Command = {
    register: () -> discordRestTypes.CreateGuildApplicationCommandRequest,
    run: (data: RunData) -> any,
    autocompleter: ((data: AutocompleteRunData) -> {discord.ApplicationCommandOptionChoiceObject})?,
    keyexpiries: {
        [string]: (data: KeyExpiryData) -> nil
    }?,
    devOnly: boolean?
}

export type KeyExpiryData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event,
    data: events.KeyExpiryEvent,
    stingManager: stingmanager.StingManager,
    punishmentmanager: punishmentmanager.PunishmentManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager,
    userinfomanager: userinfomanager.UserInfoManager
}

export type ButtonCallbackData = {
    ctx: primitives.TemplateContext, 
    interaction: discord.InteractionObject, 
    removeCallback: () -> nil,
    event: primitives.Event,
}

export type RunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    stingManager: stingmanager.StingManager,
    punishmentmanager: punishmentmanager.PunishmentManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager, 
    userinfomanager: userinfomanager.UserInfoManager,
    command: appcommands.ParsedApplicationCommand,
    attachButtonCallback: ((buttonId: string, callback: (bcd: ButtonCallbackData) -> nil) -> nil),
    dropButtonCallback: ((buttonId: string) -> nil),
    sethasEdited: (to: boolean) -> nil,
}

export type AutocompleteRunData = {
    ctx: primitives.TemplateContext, 
    event: primitives.Event, 
    interaction: discord.InteractionObject,
    stingManager: stingmanager.StingManager,
    builtinSettingsManager: builtinSettingsManager.BuiltinSettingsManager, 
    command: appcommands.ParsedApplicationCommand,
}

return {}
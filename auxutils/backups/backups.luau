--[[
The file format for backups v2:

Internally a backup is a TAR file with the .arb1 file extension. Encrypted backups are simply a AES256 encrypted ARB1 with the .arb1e file extension.

TAR File Contents:
- `core.json`: A JSON file containing the cote backup data.
- `assets/{asset_name}.jpg`: A directory containing all assets that are backed up, such as guild icons (and maybe emojis in the future?).

## Core Backup Data Format

The JSON file contains the following fields:
- `guild`: The guild object from Discord (a `discordTypes.GuildObject`)
- `channels`: The channels in the guild, as an array of `discordTypes.ChannelObject` (this is a subset of the channels that were backed up).
- `messages`: An array of messages (`discordTypes.MessageObject`).
- `options`: The options used to create the backup, as defined in `BackupCreateOpts`.
- `channel_allocation`: The final channel allocation for the backup, mapping channel IDs to the number of messages backed up in that channel.
]]
local discordTypes = require("@discord-types/apiTypes")

export type CoreBackupData = {
    guild: discordTypes.GuildObject, -- The guild object from Discord (a `discordTypes.GuildObject`)
    channels: {discordTypes.ChannelObject}, -- The channels in the guild, as an array of `discordTypes.ChannelObject`
    messages: {[string]: {discordTypes.MessageObject}}, -- An array of messages (`discordTypes.MessageObject`)
    options: BackupCreateOpts, -- The options used to create the backup
    channel_allocation: {[string]: number}, -- The final channel allocation for the backup, mapping channel IDs to the number of messages backed up in that channel
}

--- TODO: Strip down the not widely used options here to make it more maintainable
export type BackupCreateOpts = {
    channels: {string}, -- The channels to backup
    perChannel: number, -- The number of messages per channel
    maxMessages: number, -- The maximum number of messages to backup/restore
    backupMessages: boolean, -- Whether to backup messages or not
    backupGuildAssets: {"icon" | "banner" | "splash"}, -- Whether to backup guild assets (icon, banner, splash, emojis) or not
    ignoreBackupErrors: boolean, -- Whether to ignore errors while backing up messages or not
    rolloverLeftovers: boolean, -- Whether to attempt rollover of leftover message quota to another channels or not
    specialAllocations: {[string]: number}, -- Specific channel allocation overrides
}

return {}
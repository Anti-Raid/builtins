local Primitives = require"@antiraid-core/primitives"
local apitypes = require"@discord-types/apiTypes"
local resttypes = require"@discord-types/restTypes"
local channel = require"@discord-types/channel"
local types = require"../backups"
local channelallocs = require"../channelallocs"
local set = require"@antiraid-ext/set"
local typesext = require"@antiraid/typesext"
local load = require"./load"
local blob = require"@antiraid-core/blob"
local discordpermcalc = require"@antiraid-ext/utils/discordpermcalc"
local permission = require"@discord-types/permission"
local compare = require"@antiraid-ext/utils/rolecmp"
local checkpoint = require"./checkpoint"
local datamgmt = require"@antiraid/datamgmt"

--- Helper function to convert a asset to a base64 data URL
local function assetToDataURL(mimetype: string, blob: blob.Blob): string
    return "data:" .. mimetype .. ";base64," .. datamgmt.base64encode(blob)
end

local function restoreBackup(ctx: Primitives.TemplateContext, filename: string, enckey: string?, opts: types.BackupRestoreOpts, checkpointId: string?, addStatus: (s: string) -> ()) 
    addStatus("Loading backup data...")
    local blob = ctx.ObjectStorage:download_file(filename)
    addStatus("Downloaded backup file of size " .. #blob .. " bytes")
    local loadedBackup = load.loadBackupBlob(filename, blob, enckey)
    addStatus("Parsed backup data successfully")
    
    local coreData = loadedBackup.core

    -- Test if coreData is valid    
    assert(coreData.guild.id and #coreData.guild.id > 0, "internal error: guild ID must be set in core data")

    local guildWasCommunity = coreData.guild.features and table.find(coreData.guild.features, "COMMUNITY") ~= nil

    local currentGuild = ctx.Discord:get_guild().data
    local guildIsCommunity = currentGuild.features and table.find(currentGuild.features, "COMMUNITY") ~= nil

    if guildWasCommunity and not guildIsCommunity then
        error("Cannot restore a community guild backup to a non-community guild. Please enable the community features in your guild settings.")
    end

    addStatus("Restoring core data...")

    local currentBotMember = ctx.Discord:get_guild_member(ctx.current_user.id).data
    if not currentBotMember then
        error("Cannot restore backup: bot is not a member of the guild")
    end

    if not currentGuild.roles or #currentGuild.roles == 0 then 
        local roles = ctx.Discord:get_guild_roles().data
        local rolesArr = {}
        for _, role in roles do table.insert(rolesArr, role) end
        currentGuild.roles = rolesArr
    end

    local basePerms = discordpermcalc.BasePermissions(currentGuild, currentBotMember)

    if not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageChannels) then
        error("Cannot restore backup: bot does not have the 'Manage Channels' permission")
    end

    if not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageRoles) then
        error("Cannot restore backup: bot does not have the 'Manage Roles' permission")
    end

    if not discordpermcalc.HasPermission(basePerms, permission.PermissionSet.ManageWebhooks) then
        error("Cannot restore backup: bot does not have the 'Manage Webhooks' permission")
    end

    -- Find the highest role in the user's member roles
    local highestRole = nil

    local guildRolesMap = {}
    assert(currentGuild.roles, "internal error: guild roles must be loaded before restoring backup")
    for _, role in currentGuild.roles do
        guildRolesMap[role.id] = role
    end

    for _, memberRoleId in currentBotMember.roles do 
        local role = guildRolesMap[memberRoleId]
        if not role then
            continue -- Skip roles that are not present in guild_roles
        end

        if not highestRole or compare.IsRoleAGreaterThanRoleB(role :: apitypes.GuildRoleObject, highestRole) then
            highestRole = role :: apitypes.GuildRoleObject
        end
    end

    -- Check highest role
    if not highestRole then
        error("User does not have any roles in the guild")
    end

    addStatus("Highest role of bot is " .. highestRole.name .. " (ID: " .. highestRole.id .. ")")

    assert(highestRole.position <= 0, "internal error: user's highest role must be below the @everyone role in the guild hierarchy")
    
    -- Fetch channels of guild
    local currentChannels = ctx.Discord:get_guild_channels().data

    -- Checkpointing code
    local currentCheckpoint: checkpoint.Checkpoint = {
        step = "EditBaseGuild" :: "EditBaseGuild",
    }
    if checkpointId then 
        currentCheckpoint = checkpoint.getCheckpoint(ctx, checkpointId) or currentCheckpoint
    else 
        checkpointId = checkpoint.startCheckpointing(ctx)
    end

    if currentCheckpoint.step == "EditBaseGuild" then 
        addStatus("Restoring guild data...")

        local updateData: resttypes.ModifyGuildRequest = {
            name = coreData.guild.name,
            description = coreData.guild.description,
            default_message_notifications = coreData.guild.default_message_notifications,
            explicit_content_filter = coreData.guild.explicit_content_filter,
            verification_level = coreData.guild.verification_level,
            system_channel_flags = coreData.guild.system_channel_flags,
            afk_timeout = coreData.guild.afk_timeout,
        }

        -- TODO: Finish
    end
end 
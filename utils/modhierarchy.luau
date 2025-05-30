local executors = require"@antiraid-ext/executor"
local permissions = require "@discord-types/permission"
local permissionsFromBf = permissions.fromBitFlag
local promise = require "@antiraid/promise"
local kc = require "@antiraid-core/kittycat"
local Primitives = require "@antiraid-core/primitives"
local typesext = require "@antiraid/typesext"  
local apitypes = require "@discord-types/apiTypes" 

local SupportedAltPerms: {[string]: permissions.Permissions} = {
    ["moderation.sting"] = "ModerateMembers",
    ["moderation.curesting"] = "ModerateMembers",
    ["moderation.kick"] = "KickMembers",
    ["moderation.ban"] = "BanMembers",
    ["moderation.timeout"] = "ModerateMembers",
    ["moderation.unban"] = "BanMembers",
    ["moderation.viewlogchannel"] = "ViewAuditLog",
    ["moderation.setlogchannel"] = "ManageChannels"
}

local function canModeratorDo(ctx: Primitives.TemplateContext, ge: executors.GlobalExecutor, mod: string, cap: string) 
    local modInfo = promise.yield(ge.userinfo:get(mod))
    if modInfo.guild_owner_id == mod then 
        return
    end

    if not kc.has_perm(modInfo.kittycat_resolved_permissions, kc.Permission.from_string(cap)) then
        -- Check if an alternative discord permission is present on the mod
        if SupportedAltPerms[cap] then
            local modPerms = permissionsFromBf(modInfo.discord_permissions)
            if not table.find(modPerms, SupportedAltPerms[cap]) then
                error("Missing permission: ``" .. cap .. "`` or ``" .. SupportedAltPerms[cap] .. "``")
            end
        else
            error("Missing permission: ``" .. cap .. "``")
        end
    end
end

local function canBotDoInChannel(channelId: string, ctx: Primitives.TemplateContext, ge: executors.GlobalExecutor, botNeededPerms: typesext.U64Convertibles) 
    return promise.yield(ge.discord:antiraid_check_channel_permissions({
        needed_permissions = tostring(botNeededPerms),
        channel_id = channelId,
        user_id = ctx.current_user.id,
    }))
end

local function canModeratorAffectTarget(ge: executors.GlobalExecutor, mod: string, targetId: string, cap: string)
    if mod == targetId then
        error("You cannot moderate yourself!")
    end
    
    local modInfo = promise.yield(ge.userinfo:get(mod))
    if modInfo.guild_owner_id == targetId then
        error("Target user is the guild owner")
    elseif modInfo.guild_owner_id == mod then 
        return
    end

    -- Check caps
    if not kc.has_perm(modInfo.kittycat_resolved_permissions, kc.Permission.from_string(cap)) then
        -- Check if an alternative discord permission is present on the mod
        if SupportedAltPerms[cap] then
            local modPerms = permissionsFromBf(modInfo.discord_permissions)
            if not table.find(modPerms, SupportedAltPerms[cap]) then
                error("Missing permission: ``" .. cap .. "`` or ``" .. SupportedAltPerms[cap] .. "``")
            end
        else
            error("Missing permission: ``" .. cap .. "``")
        end
    end

    -- Check hierarchy
    promise.yield(ge.discord:antiraid_check_permissions_and_hierarchy({
        needed_permissions = "0",
        target_id = targetId,
        user_id = mod,
    }))
end

local function extractUserIdFromInteraction(interaction: apitypes.InteractionObject): string 
    return if interaction.user then interaction.user.id elseif (interaction.member and interaction.member.user) then interaction.member.user.id else error("No user found")
end

return {
    canModeratorAffectTarget = canModeratorAffectTarget,
    canModeratorDo = canModeratorDo,
    canBotDoInChannel = canBotDoInChannel,
    extractUserIdFromInteraction = extractUserIdFromInteraction,
}

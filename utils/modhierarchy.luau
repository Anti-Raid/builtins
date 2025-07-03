local permissions = require "@discord-types/permission"
local permissionsFromBf = permissions.fromBitFlag
local kc = require "@antiraid-core/kittycat"
local Primitives = require "@antiraid-core/primitives"
local typesext = require "@antiraid/typesext"  
local apitypes = require "@discord-types/apiTypes" 
local userinfo = require "./userinfo"

local SupportedAltPerms: {[string]: permissions.Permissions} = {
    ["moderation.sting"] = "ModerateMembers" :: "ModerateMembers",
    ["moderation.curesting"] = "ModerateMembers" :: "ModerateMembers",
    ["moderation.kick"] = "KickMembers" :: "KickMembers",
    ["moderation.ban"] = "BanMembers" :: "BanMembers",
    ["moderation.timeout"] = "ModerateMembers" :: "ModerateMembers",
    ["moderation.unban"] = "BanMembers" :: "BanMembers",
    ["moderation.viewlogchannel"] = "ViewAuditLog" :: "ViewAuditLog",
    ["moderation.setlogchannel"] = "ManageChannels" :: "ManageChannels"
}

local function canModeratorDo(userinfo: userinfo.UserInfo, cap: string) 
    if userinfo.guild_owner_id == userinfo.userid then 
        return
    end

    if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string(cap)) then
        -- Check if an alternative discord permission is present on the mod
        if SupportedAltPerms[cap] then
            local modPerms = permissionsFromBf(userinfo.discord_permissions)
            if not table.find(modPerms, SupportedAltPerms[cap]) then
                error("Missing permission: ``" .. cap .. "`` or ``" .. SupportedAltPerms[cap] .. "``")
            end
        else
            error("Missing permission: ``" .. cap .. "``")
        end
    end
end

local function canBotDoInChannel(channelId: string, ctx: Primitives.TemplateContext, botNeededPerms: typesext.U64Convertibles) 
    return ctx.Discord:antiraid_check_channel_permissions({
        needed_permissions = tostring(botNeededPerms),
        channel_id = channelId,
        user_id = ctx.current_user.id,
    })
end

local function canModeratorAffectTarget(ctx: Primitives.TemplateContext, userinfo: userinfo.UserInfo, targetId: string, cap: string)
    if userinfo.userid == targetId then
        error("You cannot moderate yourself!")
    end
    
    if userinfo.guild_owner_id == targetId then
        error("Target user is the guild owner")
    elseif userinfo.guild_owner_id == userinfo.userid then 
        return
    end

    -- Check caps
    if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string(cap)) then
        -- Check if an alternative discord permission is present on the mod
        if SupportedAltPerms[cap] then
            local modPerms = permissionsFromBf(userinfo.discord_permissions)
            if not table.find(modPerms, SupportedAltPerms[cap]) then
                error("Missing permission: ``" .. cap .. "`` or ``" .. SupportedAltPerms[cap] .. "``")
            end
        else
            error("Missing permission: ``" .. cap .. "``")
        end
    end

    -- Check hierarchy
    ctx.Discord:antiraid_check_permissions_and_hierarchy({
        needed_permissions = "0",
        target_id = targetId,
        user_id = userinfo.userid,
    })
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

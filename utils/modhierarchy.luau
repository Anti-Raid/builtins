local executors = require"@antiraid-ext/executor"
local permissions = require "@discord-types/permission"
local permissionsFromBf = permissions.fromBitFlag
local promise = require "@antiraid/promise"
local kc = require "@antiraid-core/kittycat"

local SupportedAltPerms: {[string]: permissions.Permissions} = {
    ["moderation.warn"] = "ModerateMembers",
    ["moderation.kick"] = "KickMembers",
    ["moderation.ban"] = "BanMembers",
    ["moderation.timeout"] = "ModerateMembers",
    ["moderation.unban"] = "BanMembers"
}

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

return {
    canModeratorAffectTarget = canModeratorAffectTarget
}
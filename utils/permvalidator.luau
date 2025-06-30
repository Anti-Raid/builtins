local discord = require("@discord-types/apiTypes")
local UserInfo = require"./userinfo"
local compare = require"./compare"
local kc = require "@antiraid-core/kittycat"

export type VerifyOpts = {
    op: "View"
} | {
    op: "Create",
    index: number,
    roleid: string,
    perms: {string},
} | {
    op: "Update",
    index: number,
    roleid: string,
    perms: {string},
} | {
    op: "Delete",
    roleid: string,
}

local function verifyRolePerms(vp: VerifyOpts, author: discord.Snowflake, userinfo: UserInfo.UserInfo) 
    if userinfo.guild_owner_id == author then
        return -- No further checks needed, owner can do anything, early return
    end

    if vp.op == "View" then 
        return -- For now, we do not limit view access to guild roles API
    end

    local settingsRole = userinfo.guild_roles and userinfo.guild_roles[vp.roleid]
    if not settingsRole then
        error("Role with ID " .. vp.roleid .. " does not exist in guild roles")
    end

    local highestRole = nil
    local lowestIndex = math.huge

    -- Find the highest role in the user's member roles
    for _, memberRoleId in userinfo.member_roles do 
        local role = userinfo.guild_roles and userinfo.guild_roles[memberRoleId]
        if not role then
            continue -- Skip roles that are not present in guild_roles
        end

        if not highestRole or compare.IsRoleAGreaterThanRoleB(role, highestRole) then
            highestRole = role
        end
    end

    -- Check highest role
    if not highestRole then
        error("User does not have any roles in the guild")
    end

    if compare.IsRoleALessThanOrEqualToRoleB(highestRole, settingsRole) then
        error("You do not have permission to edit this role's permissions as your highest role is less than or equal to the role you are trying to edit: " .. (highestRole.id or "nil") .. " < " .. (settingsRole.id or "nil"))
    end

    -- Find lowest index
    for _, position in userinfo.kittycat_staff_permissions.user_positions do 
        if position.index < lowestIndex then
            lowestIndex = position.index
        end
    end

    if vp.op == "Create" then 
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.create")) then
            error("You do not have permission to create guild roles. Please ask an administrator to give you the 'guild_roles.create' permission.")
        end

        if vp.index < lowestIndex then
            error("You do not have permission to edit this role's permissions as the new index would be lower than you and hence higher in hierarchy: " .. lowestIndex .. " < " .. vp.roleid)
        end     

        local permsMapped = {}
        for _, perm in vp.perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local ok, err = kc.check_patch_changes(userinfo.kittycat_resolved_permissions, {}, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end

    elseif vp.op == "Update" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.update")) then
            error("You do not have permission to update guild roles. Please ask an administrator to give you the 'guild_roles.update' permission.")
        end

        if vp.index < lowestIndex then
            error("You do not have permission to edit this role's permissions as the new index would be lower than you and hence higher in hierarchy: " .. lowestIndex .. " < " .. vp.roleid)
        end     

        local permsMapped = {}
        for _, perm in vp.perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local currentData = userinfo.guild_permissions[vp.roleid]

        if not currentData then
            error("Role with ID " .. vp.roleid .. " does not have any permissions set")
        end

        if currentData.position.index < lowestIndex then
            error("You do not have permission to edit this role's permissions as the current index of said role is lower than you and hence higher in hierarchy: " .. currentData.position.index .. " < " .. lowestIndex)
        end

        local ok, err = kc.check_patch_changes(userinfo.kittycat_resolved_permissions, currentData.position.perms, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end

    elseif vp.op == "Delete" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.delete")) then
            error("You do not have permission to delete guild roles. Please ask an administrator to give you the 'guild_roles.delete' permission.")
        end

        local currentData = userinfo.guild_permissions[vp.roleid]

        if not currentData then
            error("Role with ID " .. vp.roleid .. " does not have any permissions set")
        end

        if currentData.position.index < lowestIndex then
            error("You do not have permission to edit this role's permissions as the current index of said role is lower than you and hence higher in hierarchy: " .. currentData.position.index .. " < " .. lowestIndex)
        end

        local ok, err = kc.check_patch_changes(userinfo.kittycat_resolved_permissions, currentData.position.perms, {})
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end
    end
end

return {
    verifyRolePerms = verifyRolePerms
}
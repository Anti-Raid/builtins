local discord = require("@discord-types/apiTypes")
local UserInfo = require"./userinfo"
local compare = require"./compare"
local kc = require "@antiraid-core/kittycat"

export type VerifyOpts = {
    op: "View",
} | {
    op: "Create",
    author: discord.Snowflake,
    index: number,
    roleid: string,
    perms: {string},
    userinfo: UserInfo.UserInfo
} | {
    op: "Update",
    author: discord.Snowflake,
    index: number,
    roleid: string,
    perms: {string},
    userinfo: UserInfo.UserInfo
} | {
    op: "Delete",
    author: discord.Snowflake,
    roleid: string,
    userinfo: UserInfo.UserInfo
} | {
    op: "Reorder",
    author: discord.Snowflake,
    reorderList: {
        {
            role_id: discord.Snowflake,
            index: number,
        }
    },
    userinfo: UserInfo.UserInfo
}

--- Verify role permissions
--- Note that the userinfo passed to verifyRolePerms VerifyOpts argument
--- must be the userinfo of the author of the command, not the user being modified.
local function verifyRolePerms(vp: VerifyOpts) 
    if vp.op == "View" then 
        return -- For now, we do not limit view access to guild roles API
    end

    if vp.userinfo.guild_owner_id == vp.author then
        return -- No further checks needed, owner can do anything, early return
    end

    local highestRole = nil
    local lowestIndex = math.huge

    -- Find the highest role in the user's member roles
    for _, memberRoleId in vp.userinfo.member_roles do 
        local role = vp.userinfo.guild_roles and vp.userinfo.guild_roles[memberRoleId]
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

    -- Find lowest index
    for _, position in vp.userinfo.kittycat_staff_permissions.user_positions do 
        if position.index < lowestIndex then
            lowestIndex = position.index
        end
    end

    -- Handle reorder separately
    if vp.op == "Reorder" then 
        if not kc.has_perm(vp.userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.reorder")) then
            error("You do not have permission to mass reorder guild roles. Please ask an administrator to give you the 'guild_roles.reorder' permission.")
        end

        -- Validate all changed indices
        for _, newroledata in vp.reorderList do 
            local role = vp.userinfo.guild_roles and vp.userinfo.guild_roles[newroledata.role_id]
            if not role then
                error("Role with ID " .. newroledata.role_id .. " does not exist in guild_roles")
            end

            -- Get current index
            local currentData = vp.userinfo.guild_permissions[newroledata.role_id]

            if not currentData then
                error("Role with ID " .. newroledata.role_id .. " does not have any permissions set")
            end

            if currentData.position.index == newroledata.index then
                continue -- No change in index, skip
            end

            if newroledata.index <= lowestIndex then
                error("You do not have permission to reorder this role as its index is lower than you and hence higher in hierarchy: " .. newroledata.index .. " < " .. lowestIndex .. " for role " .. newroledata.role_id)
            end

        end
        
        return -- No further checks needed, early return
    end

    local settingsRole = vp.userinfo.guild_roles and vp.userinfo.guild_roles[vp.roleid]
    if not settingsRole then
        if vp.op ~= "Delete" then 
            error("Role with ID " .. vp.roleid .. " does not exist in guild_roles")
        end
        return -- Role does not exist in guild_roles, no need to verify permissions
    end

    assert(highestRole, "internal error: highest role is nil, this should not happen")
    if compare.IsRoleALessThanOrEqualToRoleB(highestRole, settingsRole) then
        error("You do not have permission to edit this role's permissions as your highest role is less than or equal to the role you are trying to edit: " .. (highestRole.id or "nil") .. " < " .. (settingsRole.id or "nil"))
    end

    if vp.op == "Create" then 
        if not kc.has_perm(vp.userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.create")) then
            error("You do not have permission to create guild roles. Please ask an administrator to give you the 'guild_roles.create' permission.")
        end

        if vp.index <= lowestIndex then
            error("You do not have permission to edit this role's permissions as the new index would be lower than you and hence higher in hierarchy: " .. lowestIndex .. " < " .. vp.roleid)
        end     

        local permsMapped = {}
        for _, perm in vp.perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local ok, err = kc.check_patch_changes(vp.userinfo.kittycat_resolved_permissions, {}, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end

    elseif vp.op == "Update" then
        if not kc.has_perm(vp.userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.update")) then
            error("You do not have permission to update guild roles. Please ask an administrator to give you the 'guild_roles.update' permission.")
        end

        if vp.index <= lowestIndex then
            error("You do not have permission to edit this role's permissions as the new index would be lower than you and hence higher in hierarchy: " .. lowestIndex .. " < " .. vp.roleid)
        end     

        local permsMapped = {}
        for _, perm in vp.perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local currentData = vp.userinfo.guild_permissions[vp.roleid]

        if not currentData then
            error("Role with ID " .. vp.roleid .. " does not have any permissions set")
        end

        if currentData.position.index < lowestIndex then
            error("You do not have permission to edit this role's permissions as the current index of said role is lower than you and hence higher in hierarchy: " .. currentData.position.index .. " < " .. lowestIndex)
        end

        local ok, err = kc.check_patch_changes(vp.userinfo.kittycat_resolved_permissions, currentData.position.perms, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end

    elseif vp.op == "Delete" then
        if not kc.has_perm(vp.userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.delete")) then
            error("You do not have permission to delete guild roles. Please ask an administrator to give you the 'guild_roles.delete' permission.")
        end

        local currentData = vp.userinfo.guild_permissions[vp.roleid]

        if not currentData then
            error("Role with ID " .. vp.roleid .. " does not have any permissions set")
        end

        if currentData.position.index <= lowestIndex then
            error("You do not have permission to delete this role's permissions as the current index of said role is lower than you and hence higher in hierarchy: " .. currentData.position.index .. " < " .. lowestIndex)
        end

        local ok, err = kc.check_patch_changes(vp.userinfo.kittycat_resolved_permissions, currentData.position.perms, {})
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end
    end
end

export type VerifyMemberOpts = {
    op: "View"
} | {
    op: "Create",
    author: discord.Snowflake,
    perm_overrides: {string},
    authorUserInfo: UserInfo.UserInfo,
    targetUserInfo: UserInfo.UserInfo,
} | {
    op: "Update",
    author: discord.Snowflake,
    perm_overrides: {string},
    authorUserInfo: UserInfo.UserInfo,
    targetUserInfo: UserInfo.UserInfo,
} | {
    op: "Delete",
    author: discord.Snowflake,
    authorUserInfo: UserInfo.UserInfo,
    targetUserInfo: UserInfo.UserInfo,
}

local function verifyMemberPermOverrideChange(vp: VerifyMemberOpts) 
    if vp.op == "View" then 
        return -- For now, we do not limit view access to guild members API
    end

    if vp.authorUserInfo.guild_owner_id == vp.author then
        return -- No further checks needed, owner can do anything, early return
    end

    -- Get lowest index of both current user and target user
    local lowestIndexCurr = math.huge
    for _, position in vp.authorUserInfo.kittycat_staff_permissions.user_positions do 
        if position.index < lowestIndexCurr then
            lowestIndexCurr = position.index
        end
    end

    local lowestIndexTarget = math.huge
    for _, position in vp.targetUserInfo.kittycat_staff_permissions.user_positions do
        if position.index < lowestIndexTarget then
            lowestIndexTarget = position.index
        end
    end
    
    if lowestIndexTarget < lowestIndexCurr then
        error("You do not have permission to edit this user's permissions as their lowest index is lower than yours: " .. lowestIndexTarget .. " < " .. lowestIndexCurr)
    end

    if vp.op == "Create" then 
        if not kc.has_perm(vp.authorUserInfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_members.set_permission_overrides")) then
            error("You do not have permission to set guild member permission overrides. Please ask an administrator to give you the 'guild_members.set_permission_overrides' permission.")
        end

        local permsMapped = {}
        for _, perm in vp.perm_overrides do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local ok, err = kc.check_patch_changes(vp.authorUserInfo.kittycat_resolved_permissions, {}, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end
    elseif vp.op == "Update" then
        if not kc.has_perm(vp.authorUserInfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_members.update_permission_overrides")) then
            error("You do not have permission to update guild member permission overrides. Please ask an administrator to give you the 'guild_members.update_permission_overrides' permission.")
        end

        local permsMapped = {}
        for _, perm in vp.perm_overrides do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local ok, err = kc.check_patch_changes(vp.authorUserInfo.kittycat_resolved_permissions, vp.targetUserInfo.kittycat_staff_permissions.perm_overrides, permsMapped)
        if not ok then 
            error(kc.cpce_to_string(err)) 
        end
    elseif vp.op == "Delete" then
        if not kc.has_perm(vp.authorUserInfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_members.delete_permission_overrides")) then
            error("You do not have permission to delete guild member permission overrides. Please ask an administrator to give you the 'guild_members.delete_permission_overrides' permission.")
        end

        local ok, err = kc.check_patch_changes(vp.authorUserInfo.kittycat_resolved_permissions, vp.targetUserInfo.kittycat_staff_permissions.perm_overrides, {})
        if not ok then 
            error(kc.cpce_to_string(err))  
        end
    end
end

return {
    verifyRolePerms = verifyRolePerms,
    verifyMemberPermOverrideChange = verifyMemberPermOverrideChange
}
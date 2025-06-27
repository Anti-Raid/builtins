local discord = require"@discord-types/apiTypes"
local Kittycat = require "@antiraid-core/kittycat"
local Primitives = require "@antiraid-core/primitives"

--- @class UserInfo
---
--- Represents a summary of a users permission related 
--- information on AntiRaid
---
--- @field discord_permissions discord.Snowflake The users discord permissions
--- @field kittycat_staff_permissions Kittycat.StaffPermissions The users kittycat staff permissions
--- @field kittycat_resolved_permissions {Kittycat.Permission} The users resolved kittycat permissions
--- @field guild_owner_id discord.Snowflake The ID of the guild owner
--- @field guild_roles {[discord.Snowflake]: discord.GuildRoleObject} The users guild roles (may not be present if guildRolesNeeded is not set)
--- @field member_roles {discord.Snowflake} The users member roles
---
export type UserInfo = {
    discord_permissions: discord.Snowflake,
    kittycat_staff_permissions: Kittycat.StaffPermissions,
    kittycat_resolved_permissions: {Kittycat.Permission},
    guild_owner_id: discord.Snowflake,
    guild_roles: {discord.GuildRoleObject}?,
    member_roles: {discord.Snowflake},
}

--- Stage1Data is a basic collation of user info that can then be cheaply expanded into a full UserInfo object
export type Stage1Data = {
    resolvedPerms: discord.Snowflake,
    memberRoles: {discord.Snowflake},
    guildRoles: {discord.GuildRoleObject},
    guildOwnerId: discord.Snowflake,
    pathUsed: string
}

--- UserInfoManager is a utility for fetching user info in a performant way
export type UserInfoManager = {
    --- Gets the Stage1Data for a user (basic collation of user info)
    --- @param user_id discord.Snowflake The ID of the user to get the UserInfo for
    --- @param interaction? discord.InteractionObject Optional interaction object to use for fetching permissions (can speed up fetching/remove unnecessary API calls)
    --- @return Stage1Data The Stage1Data for the user
    getStage1Data: (user_id: discord.Snowflake, interaction: discord.InteractionObject?) -> Stage1Data,

    --- Gets the UserInfo for a user (expansion of Stage1Data)
    --- @param user_id discord.Snowflake The ID of the user to get the UserInfo for
    --- @param interaction? discord.InteractionObject Optional interaction object to use for fetching permissions (can speed up fetching/remove unnecessary API calls)
    --- @return UserInfo The UserInfo for the user
    get: (user_id: discord.Snowflake, interaction: discord.InteractionObject?) -> UserInfo,

    --- Gets the guild permissions configured
    --- @return {Kittycat.PartialStaffPosition} The guild permissions for the user
    getGuildPermissions: () -> {Kittycat.PartialStaffPosition},

    --- Sets the guild permission for a position
    --- @param position Kittycat.PartialStaffPosition The position to set the permissions for
    --- @return nil
    setGuildPermission: (position: Kittycat.PartialStaffPosition) -> nil,

    --- Deletes the guild permission for a role
    --- @param roleid discord.Snowflake The ID of the role to delete the permissions
    --- @return nil
    deleteGuildPermission: (roleid: discord.Snowflake) -> nil,

    --- Gets the member permission overrides for a user
    --- @param userid discord.Snowflake The ID of the user to get the overrides for
    --- @return {Kittycat.Permission} The member permission overrides for the user
    getMemberPermissionOverrides: (userid: discord.Snowflake) -> {Kittycat.Permission},

    --- Sets the member permission overrides for a user
    --- @param userid discord.Snowflake The ID of the user to set the overrides for
    --- @param permissions {Kittycat.Permission} The permissions to set for the user
    --- @return nil
    setMemberPermissionOverrides: (userid: discord.Snowflake, permissions: {Kittycat.Permission}) -> nil,

    --- Deletes the member permission overrides for a user
    --- @param userid discord.Snowflake The ID of the user to delete the overrides for
    --- @return nil
    deleteMemberPermissionOverrides: (userid: discord.Snowflake) -> nil,
}

local function UserInfoManager(ctx: Primitives.TemplateContext): UserInfoManager
    local self = {}

    local function getGuildPermissions(): {Kittycat.PartialStaffPosition}
        local permissionRecords = ctx.KV:find("%%", {"builtins.guild_permissions"})

        local userPositions = table.create(#permissionRecords) :: {Kittycat.PartialStaffPosition}
        for _, record in permissionRecords do
            if not record.exists then continue end

            if not record.value or type(record.value) ~= "table" then
                continue
            end

            local value: {
                id: discord.Snowflake?,
                index: number?,
                perms: {string}?
            } = record.value

            if not value.id or not value.index or not value.perms then
                continue -- Skip invalid records
            end

            local roleId = value.id
            local index = value.index 
            local permissionsSet = value.perms

            local kittycatPermissions = table.create(#permissionsSet) :: {Kittycat.Permission}
            for _, perm in permissionsSet do
                local kittycatPerm = Kittycat.Permission.from_string(perm)
                table.insert(kittycatPermissions, kittycatPerm)
            end

            table.insert(userPositions, {
                id = roleId,
                index = index,
                perms = kittycatPermissions,
            })
        end

        return userPositions
    end

    local function setGuildPermission(position: Kittycat.PartialStaffPosition): nil
        assert(position.id, "Guild Role ID is required.")
        assert(position.index, "Position index is required.")
        assert(position.perms, "Position permissions are required.")

        local permsSet = {}
        for _, perm in position.perms do
            table.insert(permsSet, tostring(perm))
        end

        ctx.KV:set(position.id, {
            id = position.id,
            index = position.index,
            perms = permsSet,
        }, {"builtins.guild_permissions"})

        return nil
    end

    local function deleteGuildPermission(roleid: discord.Snowflake): nil
        assert(roleid, "Guild Role ID is required.")

        ctx.KV:delete(roleid, {"builtins.guild_permissions"})

        return nil
    end

    local function getMemberPermissionOverrides(userid: discord.Snowflake): {Kittycat.Permission}
        local overrides = ctx.KV:get(userid, {"builtins.guild_permissions.overrides"})

        if not overrides or type(overrides) ~= "table" then
            return {}
        end

        local kittycatPermissions = table.create(#overrides) :: {Kittycat.Permission}
        for _, perm in overrides do
            if type(perm) ~= "string" then
                continue -- Ignore non-string permissions
            end
            local kittycatPerm = Kittycat.Permission.from_string(perm)
            table.insert(kittycatPermissions, kittycatPerm)
        end

        return kittycatPermissions
    end

    local function setMemberPermissionOverrides(userid: discord.Snowflake, permissions: {Kittycat.Permission}): nil
        assert(userid, "User ID is required.")
        assert(permissions, "Permissions are required.")

        local permsSet: {string} = {}
        for _, perm in permissions do
            table.insert(permsSet, tostring(perm))
        end

        ctx.KV:set(userid, permsSet, {"builtins.guild_permissions.overrides"})

        return nil
    end

    local function deleteMemberPermissionOverrides(userid: discord.Snowflake): nil
        assert(userid, "User ID is required.")

        ctx.KV:delete(userid, {"builtins.guild_permissions.overrides"})

        return nil
    end

    --- Fast path to get Stage1Data when we have resolved permissions and member roles
    local function _getS1D_FastPath_HasResolvedAndMemberRoles(
        user_id: discord.Snowflake,
        currentPathUsed: string,
        resolvedPerms: discord.Snowflake,
        memberRoles: {discord.Snowflake}
    ): Stage1Data
        -- We still need to fetc
        local guild = ctx.Discord:get_guild().data

        assert(guild, "Guild is nil. This is a bug and should not happen.")

        return {
            resolvedPerms = resolvedPerms,
            memberRoles = memberRoles,
            guildRoles = guild.roles or error("No guild roles found. This is a bug and should not happen."), 
            guildOwnerId = guild.owner_id or error("No owner_id found. This is a bug and should not happen."),
            pathUsed = currentPathUsed .. "/fast_hramr",
        }
    end

    local function _getS1D_SlowPath(user_id: discord.Snowflake, currentPathUsed: string): Stage1Data 
        -- Slow path: we need to do a call to antiraid_get_fused_member to get the member and resolved permissions
        local fusedMember = ctx.Discord:antiraid_get_fused_member({user_id})
        local member = fusedMember.data.members[1] or error("Fused member does not have a member. This is a bug and should not happen.")
        local resolvedPerms = member.resolved_perms or error("Fused member does not have resolved permissions. This is a bug and should not happen.")
        local memberRoles = member.member.roles or error("Fused member does not have roles. This is a bug and should not happen.")
        local guild = fusedMember.data.guild or error("Fused member does not have a guild. This is a bug and should not happen.")

        local guildRoles = guild.roles or error("Interaction does not have guild roles. This is a bug and should not happen.")
            
        assert(#guildRoles > 0, "Interaction guild roles is empty. This is a bug and should not happen.")

        local guildOwnerId = guild.owner_id or error("Guild owner ID is not available. This is a bug and should not happen.")
                    
        return {
            resolvedPerms = resolvedPerms,
            memberRoles = memberRoles,
            guildRoles = guildRoles,
            guildOwnerId = guildOwnerId,
            pathUsed = currentPathUsed .. "/slow",
        }
    end

    --- @param user_id discord.Snowflake
    --- @param interaction? discord.InteractionObject
    local function getStage1Data(user_id: discord.Snowflake, interaction: discord.InteractionObject?): Stage1Data
        -- Fast path: if we have an interaction with a member on it, we can use it to get the permissions and member roles directly with zero API calls
        if interaction and interaction.member and interaction.member.user then 
            -- 3 cases here
            if interaction.member.user.id == user_id then 
                -- Fast path 1: if the interaction member is the user we are looking for, we can use the interaction member directly
                local resolvedPerms = interaction.member.permissions or error("Interaction member does not have permissions. This is a bug and should not happen.")
                local memberRoles = interaction.member.roles or error("Interaction member does not have roles. This is a bug and should not happen.")
                
                return _getS1D_FastPath_HasResolvedAndMemberRoles(
                    user_id,
                    "fast_path_1",
                    resolvedPerms,
                    memberRoles
                )
            
            else 
                -- Loop over all resolved members in the interaction to find the one matching the user ID
                local resolvedMembers = interaction.data and interaction.data.resolved and interaction.data.resolved.members

                if type(resolvedMembers) == "table" then 
                    local member = resolvedMembers[user_id]
                    if member then 
                        -- Fast path 2: if the interaction has resolved members and we find the user ID, we can use that
                        local resolvedPerms = member.permissions or error("Interaction resolved member does not have permissions. This is a bug and should not happen.")
                        local memberRoles = member.roles or error("Interaction resolved member does not have roles. This is a bug and should not happen.")

                        return _getS1D_FastPath_HasResolvedAndMemberRoles(
                            user_id,
                            "fast_path_2",
                            resolvedPerms,
                            memberRoles
                        )
                    end
                end

                -- Slow path: we need to do a call to antiraid_get_fused_member to get the member and resolved permissions
                return _getS1D_SlowPath(
                    user_id,
                    "useless_interaction"
                )
            end
        else 
            return _getS1D_SlowPath(
                user_id,
                "slow_path_no_interaction"
            )
        end
    end

    local function get(user_id: discord.Snowflake, interaction: discord.InteractionObject?): UserInfo
        local stage1Data = getStage1Data(user_id, interaction)

        local guildPerms = getGuildPermissions()

        -- Convert to hashmap
        local guildPermsMap = {}
        for _, perm in guildPerms do
            guildPermsMap[perm.id] = perm
        end

        local memberPositions = table.create(#guildPerms) :: {Kittycat.PartialStaffPosition}
        for _, role in stage1Data.memberRoles do
            local roleObj = guildPermsMap[role]
            if roleObj then
                table.insert(memberPositions, roleObj)
            end
        end

        local permOverrides = getMemberPermissionOverrides(user_id)

        local staffPerms = Kittycat.StaffPermissions.new(memberPositions, permOverrides)

        return {
            discord_permissions = stage1Data.resolvedPerms,
            kittycat_staff_permissions = staffPerms,
            kittycat_resolved_permissions = staffPerms:resolve(),
            guild_owner_id = stage1Data.guildOwnerId,
            guild_roles = stage1Data.guildRoles,
            member_roles = stage1Data.memberRoles,
        }
    end

    self.getStage1Data = getStage1Data
    self.get = get
    self.getGuildPermissions = getGuildPermissions
    self.setGuildPermission = setGuildPermission
    self.deleteGuildPermission = deleteGuildPermission
    self.getMemberPermissionOverrides = getMemberPermissionOverrides
    self.setMemberPermissionOverrides = setMemberPermissionOverrides
    self.deleteMemberPermissionOverrides = deleteMemberPermissionOverrides

    return self
end

return UserInfoManager
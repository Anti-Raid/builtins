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
    guild_roles: {[discord.Snowflake]: discord.GuildRoleObject}?,
    member_roles: {discord.Snowflake},
}

export type Stage1Data = {
    resolvedPerms: discord.Snowflake,
    memberRoles: {discord.Snowflake},
    guildRoles: {[discord.Snowflake]: discord.GuildRoleObject},
    guildOwnerId: discord.Snowflake,
    pathUsed: string
}

export type UserInfoManager = {
    --- Gets the Stage1Data for a user (basic collation of user info)
    --- @param user_id discord.Snowflake The ID of the user to get the UserInfo for
    --- @param interaction? discord.InteractionObject Optional interaction object to use for fetching permissions (can speed up fetching/remove unnecessary API calls)
    ---
    --- Note that the passed in interaction may be monkey patched with the guild data
    --- if discord has not provided it in the interaction object.
    ---
    --- @return Stage1Data The Stage1Data for the user
    getStage1Data: (user_id: discord.Snowflake, interaction: discord.InteractionObject?, auxMember: discord.GuildMemberObject?) -> Stage1Data,

    --- Gets the UserInfo for a user (expansion of Stage1Data)
    --- @param user_id discord.Snowflake The ID of the user to get the UserInfo for
    --- @param interaction? discord.InteractionObject Optional interaction object to use for fetching permissions (can speed up fetching/remove unnecessary API calls)
    --- @return UserInfo The UserInfo for the user
    --get: (user_id: discord.Snowflake, interaction: discord.InteractionObject?) -> UserInfo,
}

local function UserInfoManager(ctx: Primitives.TemplateContext): UserInfoManager
    local self = {}

    --- @param user_id discord.Snowflake
    --- @param interaction? discord.InteractionObject
    local function getStage1Data(user_id: discord.Snowflake, interaction: discord.InteractionObject?, auxMember: discord.GuildMemberObject?): Stage1Data
        -- Fast path: if we have an interaction with a member on it, we can use it to get the permissions and member roles directly with zero API calls
        if interaction and interaction.member then 
            
            assert(interaction.member.user, "Interaction member has no user. This is a bug and should not happen.")

            local resolvedPerms = nil
            local memberRoles = nil
            local guild = nil
            local pathUsed = "interaction_unfilled"

            if interaction.member.user.id == user_id then 
                -- Fast path 1: if the interaction member is the user we are looking for, we can use the interaction member directly
                resolvedPerms = interaction.member.permissions or error("Interaction member does not have permissions. This is a bug and should not happen.")
                memberRoles = interaction.member.roles or error("Interaction member does not have roles. This is a bug and should not happen.")
                guild = ctx.Discord:get_guild().data
                pathUsed = "fast_path_1"
            
            elseif auxMember 
            and auxMember.user -- Ensure auxMember has a user
            and auxMember.user.id == user_id -- Check if the aux member is the user we are looking for
            and auxMember.permissions -- Ensure auxMember has permissions (is from a interaction)
            then
                
                -- Fast path 2: if the caller has provided an aux member matching the user ID with the desired data, use that
                resolvedPerms = auxMember.permissions or error("Auxiliary member does not have permissions. This is a bug and should not happen.")
                memberRoles = auxMember.roles or error("Auxiliary member does not have roles. This is a bug and should not happen.")

                guild = ctx.Discord:get_guild().data

                pathUsed = "fast_path_2"
            else 

                -- Slow path: we need to do a call to antiraid_get_fused_member to get the member and resolved permissions
                local fusedMember = ctx.Discord:antiraid_get_fused_member({user_id})
                local member = fusedMember.data.members[1] or error("Fused member does not have a member. This is a bug and should not happen.")
                resolvedPerms = member.resolved_perms or error("Fused member does not have resolved permissions. This is a bug and should not happen.")
                memberRoles = member.member.roles or error("Fused member does not have roles. This is a bug and should not happen.")
                guild = fusedMember.data.guild or error("Fused member does not have a guild. This is a bug and should not happen.")
                pathUsed = "fast_path_movedtoslow"
            end

            assert(resolvedPerms, "Interaction member permissions is nil. This is a bug and should not happen.")
            assert(memberRoles, "Interaction member roles is nil. This is a bug and should not happen.")
            assert(guild, "Interaction guild is nil. This is a bug and should not happen.")

            local guildRoles = guild.roles or error("Interaction does not have guild roles. This is a bug and should not happen.")
            
            assert(#guildRoles > 0, "Interaction guild roles is empty. This is a bug and should not happen.")

            local guildRolesMap = {}
            for _, role in guildRoles do
                guildRolesMap[role.id or error("Role has no id. This is a bug and should not happen.")] = role
            end

            local guildOwnerId = guild.owner_id or error("Guild owner ID is not available. This is a bug and should not happen.")
                        
            return {
                resolvedPerms = resolvedPerms,
                memberRoles = memberRoles,
                guildRoles = guildRolesMap,
                guildOwnerId = guildOwnerId,
                pathUsed = pathUsed,
            }
        -- Slow path must be used if we don't have an interaction object to base on
        else 
            if auxMember 
            and auxMember.user -- Ensure auxMember has a user
            and auxMember.user.id == user_id -- Check if the aux member is the user we are looking for
            and auxMember.permissions -- Ensure auxMember has permissions (is from a interaction)
            then
                -- Fast path: we have aux member
                local resolvedPerms = auxMember.permissions or error("Auxiliary member does not have permissions. This is a bug and should not happen.")
                local memberRoles = auxMember.roles or error("Auxiliary member does not have roles. This is a bug and should not happen.")
                local pathUsed = "slowpath_fastauxmember"

                -- Fetch guild object for guild_roles
                local guild = ctx.Discord:get_guild()

                local guildRoles = guild.data.roles or error("Interaction does not have guild roles. This is a bug and should not happen.")

                assert(#guildRoles > 0, "Interaction guild roles is empty. This is a bug and should not happen.")

                local guildRolesMap = {}

                for _, role in guildRoles do
                    guildRolesMap[role.id or error("Role has no id. This is a bug and should not happen.")] = role
                end

                local guildOwnerId = guild.data.owner_id or error("Guild owner ID is not available. This is a bug and should not happen.")

                pathUsed ..= "/guildfetched_fastauxmember"

                return {
                    resolvedPerms = resolvedPerms,
                    memberRoles = memberRoles,
                    guildRoles = guildRolesMap,
                    guildOwnerId = guildOwnerId,
                    pathUsed = pathUsed,
                }
            end

            -- Fetch the member from the guild
            local fusedMember = ctx.Discord:antiraid_get_fused_member({user_id})
            local member = fusedMember.data.members[1] or error("Fused member does not have a member. This is a bug and should not happen.")
            local memberRoles = member.member.roles or error("Fused member does not have roles. This is a bug and should not happen.")
            local resolvedPerms = member.resolved_perms
            local guildRoles = fusedMember.data.guild.roles or error("Guild roles are not available. This is a bug and should not happen.")
            local guildOwnerId = fusedMember.data.guild.owner_id or error("Guild owner ID is not available. This is a bug and should not happen.")

            local guildRolesMap = {}
            for _, role in guildRoles do
                guildRolesMap[role.id or error("Role has no id. This is a bug and should not happen.")] = role
            end

            return {
                resolvedPerms = resolvedPerms,
                memberRoles = memberRoles,
                guildRoles = guildRolesMap,
                guildOwnerId = guildOwnerId,
                pathUsed = "slow_path",
            }
        end
    end

    self.getStage1Data = getStage1Data

    return self
end

return UserInfoManager
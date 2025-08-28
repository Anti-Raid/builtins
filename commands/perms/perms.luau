--!strict
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/framework/coretypes"
local verifyRolePerms = require"../../settings/permvalidator".verifyRolePerms
local verifyMemberPermOverrideChange = require"../../settings/permvalidator".verifyMemberPermOverrideChange
local paginate = require "@antiraid-ext/framework/paginate"
local interactionutils = require "@antiraid-ext/utils/interaction"
local apitypes = require "@discord-types/apiTypes"
local extractUserIdFromInteraction = require "@antiraid-ext/utils/modhierarchy".extractUserIdFromInteraction
local kc = require"@antiraid-core/kittycat"

local function register() 
    return commandBuilder.new({
        name = "perms",
    })
    :addIntegrationType("GuildInstall")
    :setType("ChatInput")
    :addContext("Guild")
    :setDescription("Manage user permissions on the server.")
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("listroles")
            :setDescription("List all current role permissions")  
            :build()
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("setroleperms")
            :setDescription("Sets the permissions for a role")  
            :option(
                function(opt) 
                    return opt
                    :setType("Role")
                    :setName("role")
                    :setDescription("The role to set permissions for")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("String")
                    :setName("perms")
                    :setDescription("The permissions to set for the role (comma separated)")
                    :setRequired(true)  
                    :build()
                end
            )
            :option(
                function(opt) 
                    return opt
                    :setType("Integer")
                    :setName("index")
                    :setDescription("The index of the role in the hierarchy (lower index means higher in hierarchy)")
                    :setRequired(false)  
                    :build()
                end
            )
            :build()
        end
    )
    :option(
        function(opt) 
            return opt
            :setType("SubCommand")
            :setName("listmembers")
            :setDescription("List all current member permission overrides")  
            :build()      
        end
    )
    :build()
end

local function run(data: data.RunData): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "listroles" then
        verifyRolePerms({op = "View"})

        local rolePerms = data.userinfomanager.getGuildPermissions()

        -- Sort the roles by descending index with lower indices (highest on hierarchy) first
        table.sort(rolePerms, function(a, b) 
            return a.position.index < b.position.index
        end)

        if #rolePerms == 0 then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No Roles Found",
                        description = "This server has no roles with custom permissions set.",
                        color = 0xe74c3c,
                    },
                },
                nil
            )
        end

        local embeds = {}
        for _, perm in rolePerms do 
            local permsMap = {} 
            for _, _perm in perm.position.perms do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(perm.raw.exists, "internal error: guild permissions for role " .. perm.position.id .. " does not exist in KV yet was found in KV at the same time")
            
            local createdAtTs = "<t:" .. perm.raw.created_at.timestamp_seconds .. ":f>"
            local updatedAtTs = "<t:" .. perm.raw.last_updated_at.timestamp_seconds .. ":f>"
            table.insert(embeds, {
                title = "Role ID: " .. perm.position.id,
                description = "Index: " .. tostring(perm.position.index) .. "\nPermissions: " .. (if #permsMap > 0 then table.concat(permsMap, ", ") else "None") .. "\nCreated At: " .. createdAtTs .. "\nLast Updated At: " .. updatedAtTs .. "\nRole Mention: <@&" .. perm.position.id .. ">",
                color = 0x3498db,
            })
        end

        local function renderPage(page: number)
            return embeds[page]
        end

        paginate.paginate(data, {
            numPages = #embeds,
            id = "perms.listroles",
            embed = renderPage
        })

        return nil
    elseif cmdname == "setroleperms" then
        local role: apitypes.GuildRoleObject? = nil
        local newRolePerms = nil
        local index = nil
        for _, opt in data.command.options do 
            if opt.name == "backup_file" then
                if opt.value.kind == "Role" then
                    role = opt.value.role
                end
            elseif opt.name == "perms" then
                if opt.value.kind == "String" then
                    if opt.value.value == "" then
                        return interactionutils.replySimple(
                            data.ctx,
                            data.interaction,
                            nil,
                            {
                                {
                                    title = "Invalid Permissions",
                                    description = "You must provide at least one permission to set for the role, or provide none to clear all permissions.",
                                    color = 0xe74c3c,
                                },
                            },
                            nil
                        )
                    end

                    local nperms = string.split(opt.value.value, ",")
                    newRolePerms = nperms
                end
            elseif opt.name == "index" then
                if opt.value.kind == "Integer" then
                    index = opt.value.value
                end
            end
        end

        if not newRolePerms then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Invalid Permissions",
                        description = "You must provide at least one permission to set for the role, or provide none to clear all permissions.",
                        color = 0xe74c3c,
                    },
                },
                nil
            )
        end

        if not role then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Invalid Role",
                        description = "You must provide a valid role to set permissions for.",
                        color = 0xe74c3c,
                    },
                },
                nil
            )
        end

        local rolePerms = data.userinfomanager.getGuildPermissionForRole(role.id)
        local userid = extractUserIdFromInteraction(data.interaction)
        local userinfo = data.userinfomanager.get(userid, nil)

        local permsMapped = {}
        for _, perm in newRolePerms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        if rolePerms then
            -- Update
            assert(role, "internal error: role is nil")
            assert(newRolePerms, "internal error: newRolePerms is nil")

            local updateIndex: number = index or rolePerms.position.index

            verifyRolePerms({
                op = "Update" :: "Update", 
                perms = newRolePerms, 
                index = updateIndex, 
                roleid = role.id, 
                userinfo = userinfo, 
                author = userid
            })

            local new = kc.PartialStaffPosition.new(role.id, updateIndex, permsMapped)
            data.userinfomanager.setGuildPermission(new)

            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Role Permissions Updated",
                        description = "The permissions for the role <@&" .. role.id .. "> have been updated.",
                        color = 0x2ecc71,
                    },
                },
                nil
            )
        else
            -- Create
            assert(role, "internal error: role is nil")
            assert(newRolePerms, "internal error: newRolePerms is nil")

            if not index then 
                return interactionutils.replySimple(
                    data.ctx,
                    data.interaction,
                    nil,
                    {
                        {
                            title = "Missing Index",
                            description = "You must provide an index when setting the permissions for a new role.",
                            color = 0xe74c3c,
                        },
                    },
                    nil
                )
            end

            verifyRolePerms({
                op = "Create" :: "Create", 
                perms = newRolePerms, 
                index = index, 
                roleid = role.id, 
                userinfo = userinfo, 
                author = userid
            })

            local new = kc.PartialStaffPosition.new(role.id, index, permsMapped)
            data.userinfomanager.setGuildPermission(new)

            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "Role Permissions Set",
                        description = "The permissions for the role <@&" .. role.id .. "> have been set.",
                        color = 0x2ecc71,
                    },
                },
                nil
            )
        end
    elseif cmdname == "listmembers" then
        -- TODO: Once chunking (and related infra) is added to template-worker,
        -- show permissions of all members
        verifyMemberPermOverrideChange({op = "View"})

        local memberPerms = data.userinfomanager.getMemberPermissionOverrides()

        if #memberPerms == 0 then 
            return interactionutils.replySimple(
                data.ctx,
                data.interaction,
                nil,
                {
                    {
                        title = "No Member Permission Overrides Found",
                        description = "This server has no members with custom permission overrides set.",
                        color = 0xe74c3c,
                    },
                },
                nil
            )
        end

        local embeds = {}
        for _, memberPermissions in memberPerms do             
            local permsMap = {} 
            for _, _perm in memberPermissions.perm_overrides do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(memberPermissions.raw.exists, "internal error: member data for member " .. memberPermissions.userid .. " does not exist in KV yet was found in KV at the same time")
            
            local createdAtTs = "<t:" .. memberPermissions.raw.created_at.timestamp_seconds .. ":f>"
            local updatedAtTs = "<t:" .. memberPermissions.raw.last_updated_at.timestamp_seconds .. ":f>"
            table.insert(embeds, {
                title = "User ID: " .. memberPermissions.userid,
                description = "Permissions: " .. (if #permsMap > 0 then table.concat(permsMap, ", ") else "None") .. "\nCreated At: " .. createdAtTs .. "\nLast Updated At: " .. updatedAtTs .. "\nUser Mention: <@" .. memberPermissions.userid .. ">",
            })
        end

        local function renderPage(page: number)
            return embeds[page]
        end

        paginate.paginate(data, {
            numPages = #embeds,
            id = "perms.listmembers",
            embed = renderPage
        })

        return nil
    else 
        error("Unknown subcommand: " .. tostring(cmdname))
    end
end

return {
    register = register,
    run = run,
}
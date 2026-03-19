--!strict
local commandBuilder = require "@discord-types/builders/interaction/interaction"
local data = require"@antiraid-ext/frameworkv2/context"
local verifyRolePerms = require"../../settings/permvalidator".verifyRolePerms
local verifyMemberPermOverrideChange = require"../../settings/permvalidator".verifyMemberPermOverrideChange
local paginate = require "@antiraid-ext/frameworkv2/paginate"
local apitypes = require "@discord-types/apiTypes"
local kc = require"@antiraid-core/kittycat"
local userinfomanager = require"@antiraid-ext/utils/userinfo"
local units = require"@antiraid-ext/frameworkv2/unit"
local strip = require"@antiraid-ext/strings/strip"

local command = commandBuilder.new({
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
    function(opts) 
        return opts
        :setType("SubCommand")
        :setName("removerole")
        :setDescription("Removes a role's permissions from the system")  
        :option(
            function(opt) 
                return opt
                :setType("Role")
                :setName("role")
                :setDescription("The role to remove permissions for")
                :setRequired(true)  
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

local function run(data: data.CommandContext): nil
    local cmdname = data.command.nameList[2]

    if cmdname == "listroles" then
        verifyRolePerms({op = "View"})

        local rolePerms = data.framework.userinfomanager.getGuildPermissions()

        -- Sort the roles by descending index with lower indices (highest on hierarchy) first
        table.sort<<userinfomanager.GuildRolePermission>>(rolePerms, function(a, b) 
            return a.position.index < b.position.index
        end)

        if #rolePerms == 0 then 
            return data.interaction.replysimpleembed("No Roles Found", "This server has no roles with custom permissions set.", units.RED_COLOR)
        end

        local embeds: {apitypes.EmbedObject} = {}
        for _, perm in rolePerms do 
            local permsMap: {string} = {} 
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
            } :: apitypes.EmbedObject)
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
        local role = data.args.role("role")
        local permstr = data.args.string("perms")
        local index = data.args.integer("index")

        if not permstr then 
            return data.interaction.replysimpleembed("Invalid Permissions", "You must provide at least one permission to set for the role, or provide none to clear all permissions.", units.RED_COLOR)
        end

        if not role then 
            return data.interaction.replysimpleembed("Invalid Role", "You must provide a valid role to set permissions for.", units.RED_COLOR)
        end

        local rolePerms = data.framework.userinfomanager.getGuildPermissionForRole(role.id)
        local modinfo = data.interaction.userinfo()

        local perms: {string} = {}
        for _, perm in string.split(permstr, ",") do 
            perm, _ = strip(perm)
            table.insert(perms, perm)
        end


        local permsMapped = {}
        for _, perm in perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        if rolePerms then
            -- Update
            assert(role, "internal error: role is nil")
            assert(perms, "internal error: newRolePerms is nil")

            local updateIndex: number = index or rolePerms.position.index

            verifyRolePerms({
                op = "Update" :: "Update", 
                perms = perms, 
                index = updateIndex, 
                roleid = role.id, 
                userinfo = modinfo, 
                author = modinfo.userid
            })

            local new = kc.PartialStaffPosition.new(role.id, updateIndex, permsMapped)
            data.framework.userinfomanager.setGuildPermission(new)
            return data.interaction.replysimpleembed("Role Permissions Updated", "The permissions for the role <@&" .. role.id .. "> have been updated.", units.GREEN_COLOR)
        else
            -- Create
            assert(role, "internal error: role is nil")
            assert(perms, "internal error: newRolePerms is nil")

            if not index then 
                return data.interaction.replysimpleembed("Missing Index", "You must provide an index when setting the permissions for a new role.", units.RED_COLOR)
            end

            verifyRolePerms({
                op = "Create" :: "Create", 
                perms = perms, 
                index = index, 
                roleid = role.id, 
                userinfo = modinfo, 
                author = modinfo.userid
            })

            local new = kc.PartialStaffPosition.new(role.id, index, permsMapped)
            data.framework.userinfomanager.setGuildPermission(new)
            return data.interaction.replysimpleembed("Role Permissions Set", "The permissions for the role <@&" .. role.id .. "> have been set.", units.GREEN_COLOR)
        end
    elseif cmdname == "removerole" then
        local role = data.args.role("role")

        if not role then 
            return data.interaction.replysimpleembed("Invalid Role", "You must provide a valid role to remove permissions for.", units.RED_COLOR)
        end

        local rolePerms = data.framework.userinfomanager.getGuildPermissionForRole(role.id)

        if not rolePerms then 
            return data.interaction.replysimpleembed("Role Not Found", "The role <@&" .. role.id .. "> does not have any permissions set.", units.RED_COLOR)
        end

        local modinfo = data.interaction.userinfo()
        verifyRolePerms({
            op = "Delete" :: "Delete", 
            roleid = role.id, 
            userinfo = modinfo, 
            author = modinfo.userid
        })

        data.framework.userinfomanager.deleteGuildPermission(role.id)
        return data.interaction.replysimpleembed("Role Permissions Deleted", "The permissions for the role <@&" .. role.id .. "> have been deleted.", units.GREEN_COLOR)
    elseif cmdname == "listmembers" then
        verifyMemberPermOverrideChange({op = "View"})

        local memberPerms = data.framework.userinfomanager.getMemberPermissionOverrides()

        if #memberPerms == 0 then 
            return data.interaction.replysimpleembed("No Member Permission Overrides Found", "This server has no members with custom permission overrides set.", units.RED_COLOR)
        end

        local embeds = {}
        for _, memberPermissions in memberPerms do             
            local permsMap: {string} = {} 
            for _, _perm in memberPermissions.perm_overrides do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(memberPermissions.raw.exists, "internal error: member data for member " .. memberPermissions.userid .. " does not exist in KV yet was found in KV at the same time")
            
            local createdAtTs = "<t:" .. memberPermissions.raw.created_at.timestamp_seconds .. ":f>"
            local updatedAtTs = "<t:" .. memberPermissions.raw.last_updated_at.timestamp_seconds .. ":f>"
            table.insert(embeds, {
                title = "User ID: " .. memberPermissions.userid,
                description = "Permissions: " .. (if #permsMap > 0 then table.concat(permsMap, ", ") else "None") .. "\nCreated At: " .. createdAtTs .. "\nLast Updated At: " .. updatedAtTs .. "\nUser Mention: <@" .. memberPermissions.userid .. ">",
            } :: apitypes.EmbedObject)
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
    command = command,
    run = run,
}
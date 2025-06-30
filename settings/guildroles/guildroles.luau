local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local verifyRolePerms = require"../../utils/permvalidator".verifyRolePerms
local kc = require"@antiraid-core/kittycat"
local data = require"../data"
local array_metatable = require"@antiraid/interop".array_metatable
local datetime = require"@antiraid/datetime"

local guildroles: settings.Setting = {
    id = "roles",
    name = "Server Roles",
    description = "Configure server roles permissions on AntiRaid",
    title_template = "{index} - {role_id}",
    operations = {"View", "Create", "Update", "Delete"},
    columns = {
        {
            id = "role_id",
            name = "Role ID", 
            description = "The role ID",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "role"),
            primary_key = true,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {"View"}
        },
        {
            id = "perms",
            name = "Permissions", 
            description = "What permissions should the role have",
            column_type = settingsExt.stringColumnType("Array", nil, nil, {}, "kittycat"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {}
        },
        {
            id = "index",
            name = "Index", 
            description = "Where in the role hierarchy should this role be on Anti-Raid for permission purposes. Note that a lower index implies higher on the hierarchy and vice versa",
            column_type = settingsExt.integerColumnType("Scalar"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {}
        },
        {
            id = "display_name",
            name = "Display Name", 
            description = "Name of the role",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "normal"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {"View", "Create", "Update", "Delete"}
        },
        settingsExt.columnCreatedAt(),
        settingsExt.columnCreatedBy(),
        settingsExt.columnLastUpdatedAt(),
        settingsExt.columnLastUpdatedBy(),
    }
}

local function execute(event: events.SettingExecuteEvent, data: data.SettingsData): any 
    local userinfo = data.userinfomanager.get(event.author, nil)

    if event.op == "View" then 
        verifyRolePerms({op = "View"}, event.author, userinfo)

        local result = setmetatable({}, array_metatable)

        for groleid, gperms in userinfo.guild_permissions do 
            local role = userinfo.guild_roles and userinfo.guild_roles[groleid]
            local displayName = if role then role.name else "Role with id: " .. groleid
            
            local permsMap = {} 
            for _, _perm in gperms.position.perms do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(gperms.raw.exists, "internal error: guild permissions for role " .. groleid .. " does not exist in KV yet was found in KV at the same time")
            
            table.insert(result, {
                role_id = groleid,
                perms = permsMap,
                index = gperms.position.index,
                display_name = displayName,
                created_at = gperms.raw.created_at,
                created_by = gperms.raw.value.created_by,
                last_updated_at = gperms.raw.last_updated_at,
                last_updated_by = gperms.raw.value.last_updated_by
            })
        end

        return result
    elseif event.op == "Create" then
        local index = settingsExt.assertInteger("index", event.fields.index)
        local roleid = settingsExt.assertString("role_id", event.fields.role_id)
        local perms = settingsExt.assertStringArray("perms", event.fields.perms)

        verifyRolePerms({op = "Create" :: "Create", perms = perms, index = index, roleid = roleid}, event.author, userinfo)

        local permsMapped = {}
        for _, perm in perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local new = kc.PartialStaffPosition.new(roleid, index, permsMapped)
        data.userinfomanager.setGuildPermission(new)

        local role = userinfo.guild_roles and userinfo.guild_roles[roleid]
        local displayName = if role then role.name else "Role with id: " .. roleid

        return {
            role_id = roleid,
            perms = perms,
            index = index,
            display_name = displayName,
            created_at = datetime.UTC:now(),
            created_by = event.author,
            last_updated_at = datetime.UTC:now(),
            last_updated_by = event.author
        }
    elseif event.op == "Update" then
        local index = settingsExt.assertInteger("index", event.fields.index)
        local roleid = settingsExt.assertString("role_id", event.fields.role_id)
        local perms = settingsExt.assertStringArray("perms", event.fields.perms)

        verifyRolePerms({op = "Update" :: "Update", perms = perms, index = index, roleid = roleid}, event.author, userinfo)

        local permsMapped = {}
        for _, perm in perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        data.userinfomanager.setGuildPermission(
            kc.PartialStaffPosition.new(roleid, index, permsMapped)
        )

        local role = userinfo.guild_roles and userinfo.guild_roles[roleid]
        local displayName = if role then role.name else "Role with id: " .. roleid

        return {
            role_id = roleid,
            perms = perms,
            index = index,
            display_name = displayName,
            last_updated_at = datetime.UTC:now(),
            last_updated_by = event.author
        }
    elseif event.op == "Delete" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("guild_roles.delete")) then
            error("You do not have permission to update guild roles. Please ask an administrator to give you the 'guild_roles.update' permission.")
        end

        local roleid = settingsExt.assertString("role_id", event.fields.role_id)

        verifyRolePerms({op = "Delete", roleid = roleid}, event.author, userinfo)

        data.userinfomanager.deleteGuildPermission(roleid)
        
        return {roleid = roleid}
    else
        error("Invalid setting being updated")
    end
end

return {
    schema = guildroles,
    execute = execute
}
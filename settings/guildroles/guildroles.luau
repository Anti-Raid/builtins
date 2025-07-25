local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local verifyRolePerms = require"../permvalidator".verifyRolePerms
local kc = require"@antiraid-core/kittycat"
local data = require"@antiraid-ext/framework/coretypes"
local array_metatable = require"@antiraid/interop".array_metatable

local EMPTY_ARRAY = setmetatable({}, array_metatable)
local guildroles: settings.Setting = {
    id = "roles",
    name = "Server Roles",
    description = "Configure server roles permissions on AntiRaid",
    view_template = [[
local data = ...
    
local name = ''

for _, role in data.guildData.roles do 
    if role.id == data.fields.role_id then 
        name = role.name
        break
    end
end

if not name or name == '' then 
    return `Unknown Role (${data.fields.role_id})`
end

data.fields.title = name
return data.fields   
]],
    validation_template = "local data = ...; if data.op ~= 'Reorder' then data.fields.__HASFOLLOWEDSCHEMA = 48 end; return data.fields",
    operations = {"View", "Create", "Update", "Delete"},
    index_by = "index",
    footer = {
        end_text = "Drag roles to reorder them in the hierarchy. Note that a lower index implies higher on the hierarchy and vice versa.",
    },
    columns = {
        {
            id = "role_id",
            name = "Role ID", 
            description = "The role ID",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "role"),
            primary_key = true,
            nullable = false,
            secret = false,
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
            readonly = EMPTY_ARRAY
        },
        {
            id = "index",
            name = "Index", 
            description = "Where in the role hierarchy should this role be on Anti-Raid for permission purposes. Note that a lower index implies higher on the hierarchy and vice versa",
            column_type = settingsExt.integerColumnType("Scalar"),
            primary_key = false,
            nullable = false,
            secret = false,
            readonly = EMPTY_ARRAY
        },
        settingsExt.columnCreatedAt(),
        settingsExt.columnLastUpdatedAt(),
    },
}

local function execute(event: events.SettingExecuteEvent, data: data.SettingsData): any 
    if event.op == "View" then 
        verifyRolePerms({op = "View"})

        local result = setmetatable({}, array_metatable)

        local rolePerms = data.userinfomanager.getGuildPermissions()

        for _, perm in rolePerms do 
            local permsMap = {} 
            for _, _perm in perm.position.perms do 
                table.insert(permsMap, tostring(_perm))
            end

            assert(perm.raw.exists, "internal error: guild permissions for role " .. perm.position.id .. " does not exist in KV yet was found in KV at the same time")
            
            table.insert(result, {
                role_id = perm.position.id,
                perms = if #permsMap > 0 then permsMap else EMPTY_ARRAY,
                index = perm.position.index,
                created_at = tostring(perm.raw.created_at),
                last_updated_at = tostring(perm.raw.last_updated_at),
            })
        end

        return result
    elseif event.op == "Create" then
        local userinfo = data.userinfomanager.get(event.author :: string, nil)

        local index = settingsExt.assertInteger("index", event.fields.index)
        local roleid = settingsExt.assertString("role_id", event.fields.role_id)
        local perms = settingsExt.assertStringArray("perms", event.fields.perms)

        verifyRolePerms({op = "Create" :: "Create", perms = perms, index = index, roleid = roleid, userinfo = userinfo, author = event.author})

        local permsMapped = {}
        for _, perm in perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        local new = kc.PartialStaffPosition.new(roleid, index, permsMapped)
        data.userinfomanager.setGuildPermission(new)

        return {}
    elseif event.op == "Update" then
        local userinfo = data.userinfomanager.get(event.author :: string, nil)
        
        local index = settingsExt.assertInteger("index", event.fields.index)
        local roleid = settingsExt.assertString("role_id", event.fields.role_id)
        local perms = settingsExt.assertStringArray("perms", event.fields.perms)

        verifyRolePerms({op = "Update" :: "Update", perms = perms, index = index, roleid = roleid, userinfo = userinfo, author = event.author})

        local permsMapped = {}
        for _, perm in perms do 
            table.insert(permsMapped, kc.Permission.from_string(perm))
        end    

        data.userinfomanager.setGuildPermission(
            kc.PartialStaffPosition.new(roleid, index, permsMapped)
        )

        return {}
    elseif event.op == "Delete" then
        local userinfo = data.userinfomanager.get(event.author, nil)
        
        local roleid = settingsExt.assertString("role_id", event.fields.role_id)

        verifyRolePerms({op = "Delete", roleid = roleid, userinfo = userinfo, author = event.author})

        data.userinfomanager.deleteGuildPermission(roleid)
        
        return {roleid = roleid}
    elseif event.op == "Reorder" then
        local userinfo = data.userinfomanager.get(event.author, nil)

        local reorderList: {
            {
                role_id: string,
                index: number,
            }
        } = event.fields :: any

        for _, item in reorderList do
            settingsExt.assertString("role_id", item.role_id)
            settingsExt.assertInteger("index", item.index)
        end

        verifyRolePerms({
            op = "Reorder" :: "Reorder",
            reorderList = reorderList,
            userinfo = userinfo,
            author = event.author
        })

        data.userinfomanager.applyReorder(reorderList)

        return {}
    else
        error("Invalid operation to guildroles setting: " .. event.op)
    end
end

return {
    schema = guildroles,
    execute = execute
}
local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local kc = require"@antiraid-core/kittycat"
local data = require"@antiraid-ext/framework/coretypes"
local primitives = require"@antiraid-core/primitives"
local array_metatable = require"@antiraid/interop".array_metatable
local tloop = require"@antiraid-core/templateloop"

local EMPTY_ARRAY = setmetatable({}, array_metatable)
local scripts: (ctx: primitives.TemplateContext) -> settings.Setting = function(ctx: primitives.TemplateContext)     
    return {
        id = "scripts",
        name = "Server Scripts",
        description = "Configure the server scripts (AKA templates) running on AntiRaid",
        view_template = [[
local data = ...
if data.perm_error then return {error = data.perm_error or "Unknown perm error"} end
data.fields.title = `{data.fields.name} ({data.fields.language})`
return data.fields
]],
        operations = {"View", "Create", "Update", "Delete"},
        columns = {
            {
                id = "name",
                name = "Name", 
                description = "The name of the script",
                column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "normal"),
                primary_key = true,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "language",
                name = "Language", 
                description = "The language of the script. Only Roblox Luau is currently supported here.",
                column_type = settingsExt.stringColumnType("Scalar", nil, 64, {"luau"}, "normal"),
                primary_key = false,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "content",
                name = "Content", 
                description = "The content of the script",
                column_type = settingsExt.jsonColumnType("Scalar", "template-content"),
                primary_key = false,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "paused",
                name = "Paused", 
                description = "Whether the script is paused or not",
                column_type = settingsExt.booleanColumnType("Scalar"),
                primary_key = false,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "error_channel",
                name = "Error Channel", 
                description = "The channel to report any errors to",
                column_type = settingsExt.stringColumnType("Scalar", nil, nil, {}, "channel"),
                primary_key = false,
                nullable = true,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            settingsExt.columnCreatedAt(),
            settingsExt.columnLastUpdatedAt(),
        }
    }
end

local function execute(event: events.SettingExecuteEvent, data: data.SettingsData): any 
    local userinfo = data.userinfomanager.get(event.author, nil)    
    if event.op == "View" then 
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.view")) then
            return {perm_error = "You need the `scripts.view` permission to view scripts"}
        end
        local entries = data.ctx.Runtime:listtemplates()

        local templates = {}
        for _, entry in entries do 
            if entry.source.type ~= "custom" then continue end
            local template = {
                name = entry.source.name,
                language = entry.source.language,
                content = entry.source.content,
                paused = entry.paused,
                allowed_caps = if #entry.allowed_caps > 0 then entry.allowed_caps else EMPTY_ARRAY,
                created_at = tostring(entry.created_at),
            }

            table.insert(templates, template)
        end

        return setmetatable(templates, array_metatable)
    elseif event.op == "Create" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.create")) then
            return {perm_error = "You need the `scripts.create` permission to create scripts"}
        end

        local id = data.ctx.Runtime:createtemplate({
            source = {
                type = "custom",
                name = settingsExt.assertString("name", event.fields.name),
                language = "luau",
                content = event.fields.content,
            },
            allowed_caps = settingsExt.assertStringArray("allowed_caps", event.fields.allowed_caps, "string"),
            paused = settingsExt.assertBoolean("paused", event.fields.paused, false),
        })
        return tloop.getRunningLoop(data.ctx).updateTemplateCache(id)
    elseif event.op == "Update" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.update")) then
            return {perm_error = "You need the `scripts.update` permission to update scripts"}
        end

        data.ctx.Runtime:updatetemplate(
            settingsExt.assertString("id", event.fields.id),
            {
                source = {
                    type = "custom",
                    name = settingsExt.assertString("name", event.fields.name),
                    language = "luau",
                    content = event.fields.content,
                },
                allowed_caps = settingsExt.assertStringArray("allowed_caps", event.fields.allowed_caps, "string"),
                paused = settingsExt.assertBoolean("paused", event.fields.paused, false),
            }
        )
        return tloop.getRunningLoop(data.ctx).updateTemplateCache(event.fields.id)
    elseif event.op == "Delete" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.delete")) then
            error("You need the `scripts.delete` permission to delete scripts")
        end

        local name = settingsExt.assertString("name", event.fields.name)

        data.ctx.Runtime:deletetemplate(name)

        return {}
    else
        error("Invalid operation to script setting: " .. event.op)
    end
end

return {
    dynSchema = scripts,
    execute = execute
}
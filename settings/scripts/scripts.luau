local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local kc = require"@antiraid-core/kittycat"
local data = require"../data"
local primitives = require"@antiraid-core/primitives"
local array_metatable = require"@antiraid/interop".array_metatable

local EMPTY_ARRAY = setmetatable({}, array_metatable)
local scripts: (ctx: primitives.TemplateContext) -> settings.Setting = function(ctx: primitives.TemplateContext) 
    local lss = ctx.DataStores.LinksStore
    if not lss then
        error("LinksStore is not available in this context")
    end
    
    return {
        id = "scripts",
        name = "Server Scripts",
        description = "Configure the server scripts (AKA templates) running on AntiRaid",
        title_template = "local data = ...; return `{data.fields.name} ({data.fields.language})`",
        operations = {"View", "Create", "Update", "Delete"},
        columns = {
            {
                id = "name",
                name = "Name", 
                description = "The name of the script",
                column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "normal"),
                primary_key = false,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "language",
                name = "Language", 
                description = "The language of the script. Only Roblox Luau is currently supported here.",
                column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "normal"),
                primary_key = false,
                nullable = false,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "content",
                name = "Content", 
                description = "The content of the script",
                column_type = settingsExt.jsonColumnType("Scalar", "template"),
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
                id = "events",
                name = "Events", 
                description = "The events that this script can be executed on.",
                column_type = settingsExt.stringColumnType("Array", nil, nil, {}, "normal", lss.event_list()),
                primary_key = false,
                nullable = true,
                secret = false,
                readonly = EMPTY_ARRAY
            },
            {
                id = "allowed_caps",
                name = "Capabilities", 
                description = "The capabilities the script will have.",
                column_type = settingsExt.stringColumnType("Array", nil, nil, {}, "normal"),
                primary_key = false,
                nullable = true,
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
    assert(data.ctx.DataStores.TemplateStore, "TemplateStore is not available in this context")
    
    if event.op == "View" then 
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.view")) then
            error("You need the `scripts.view` permission to view scripts")
        end
        return data.ctx.DataStores.TemplateStore.list()
    elseif event.op == "Create" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.create")) then
            error("You need the `scripts.create` permission to create scripts")
        end

        return data.ctx.DataStores.TemplateStore.create(event.fields)
    elseif event.op == "Update" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.update")) then
            error("You need the `scripts.update` permission to view scripts")
        end

        return data.ctx.DataStores.TemplateStore.update(event.fields)
    elseif event.op == "CreateOrUpdate" then
        -- Custom operation to create or update a script depending on whether it exists
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.create")) then
            error("You need the `scripts.create` permission to create scripts")
        end

        local ok, err = pcall(function()
            return data.ctx.DataStores.TemplateStore.create(event.fields)
        end)

        if not ok then
            if err and err:find("already exists") then
                -- If it already exists, update it instead
                if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.update")) then
                    error("You need the `scripts.update` permission to update scripts [this script already exists]")
                end
                data.ctx.DataStores.TemplateStore.update(event.fields)

                return {remark = "Used CreateOrUpdate fastpath", type = "Update"} -- Return the result of the create operation
            else
                error(err) -- Re-throw the error if it's not about existence
            end
        end

        return {remark = "Used CreateOrUpdate fastpath", type = "Create"} -- Return the result of the create operation
    elseif event.op == "Delete" then
        if not kc.has_perm(userinfo.kittycat_resolved_permissions, kc.Permission.from_string("scripts.delete")) then
            error("You need the `scripts.delete` permission to delete scripts")
        end

        local name = settingsExt.assertString("name", event.fields.name)

        data.ctx.DataStores.TemplateStore.delete(name)

        return {}
    else
        error("Invalid operation to script setting: " .. event.op)
    end
end

return {
    dynSchema = scripts,
    execute = execute
}
local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"
local events = require"@antiraid-core/events"
local data = require"../data"
local array_metatable = require"@antiraid/interop".array_metatable

local EMPTY_ARRAY = setmetatable({}, array_metatable)
local kv: settings.Setting = {
    id = "kv",
    name = "Key Value API",
    description = "Manage the AntiRaid Key Value API",
    title_template = "{id} ({key}) - [{scopes}]",
    operations = {"View", "Create", "Update", "Delete"},
    columns = {
        {
            id = "id",
            name = "ID", 
            description = "The ID of the record",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "uuid"),
            primary_key = true,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {"View"}
        },
        {
            id = "key",
            name = "Key", 
            description = "The key of the record",
            column_type = settingsExt.stringColumnType("Scalar", nil, nil, {}, "normal"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {"View"}
        },
        {
            id = "value",
            name = "Value", 
            description = "The value of the record. This can be any type, depending on what was stored.",
            column_type = settingsExt.jsonColumnType("Scalar", "khronosvalue"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = EMPTY_ARRAY
        },
        {
            id = "scopes",
            name = "Scopes", 
            description = "The scopes the key has",
            column_type = settingsExt.stringColumnType("Array", nil, nil, {}, "normal"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = EMPTY_ARRAY
        },
        settingsExt.columnCreatedAt(),
        settingsExt.columnLastUpdatedAt(),
        {
            id = "expires_at",
            name = "Expires At",
            description = "When the key will expire. If this is not set, the key will not expire.",
            primary_key = false,
            column_type = settingsExt.stringColumnType("Scalar", nil, nil, {}, "timestamp"),
            nullable = true,
            readonly = {"View", "Create", "Update", "Delete"},
            secret = false,
            suggestions = settingsExt.noSuggestions(),
        }
    }
}

local function execute(event: events.SettingExecuteEvent, data: data.SettingsData): any 
    error("This feature is currently under maintenance as we work to make it better!")
end

return {
    schema = kv,
    execute = execute
}
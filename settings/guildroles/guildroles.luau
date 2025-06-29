local settings = require"@antiraid-core/settings"
local settingsExt = require"@antiraid-ext/settings"

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
            description = "What should the role be displayed as in API's etc",
            column_type = settingsExt.stringColumnType("Scalar", nil, 64, {}, "normal"),
            primary_key = false,
            nullable = false,
            secret = false,
            suggestions = settingsExt.noSuggestions(),
            readonly = {}
        },
        settingsExt.columnCreatedAt(),
        settingsExt.columnCreatedBy(),
        settingsExt.columnLastUpdatedAt(),
        settingsExt.columnLastUpdatedBy(),
    }
}

return {
    schema = guildroles
}
local data = require"@antiraid-ext/framework/coretypes"

local settings = {
    guildroles = require"./guildroles/guildroles",
    guildmembers = require"./guildmembers/guildmembers",
    scripts = require"./scripts/scripts",
} :: { [string]: data.FrameworkSetting }

return {
    settings = settings,
}
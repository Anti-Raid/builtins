local data = require"./data"

local settings = {
    guildRoles = function() return require"./guildroles/guildroles" end,
} :: { [string]: () -> data.Setting }

return {
    settings = settings,
}
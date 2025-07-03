local data = require"./data"

local settings = {
    roles = function() return require"./guildroles/guildroles" end,
    members = function() return require"./guildmembers/guildmembers" end,
} :: { [string]: () -> data.Setting }

return {
    settings = settings,
}
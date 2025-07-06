local data = require"./data"

local settings = {
    guildroles = function() return require"./guildroles/guildroles" end,
    guildmembers = function() return require"./guildmembers/guildmembers" end,
   -- scripts = function()  return require"./scripts/scripts" end,
} :: { [string]: () -> data.Setting }

return {
    settings = settings,
}
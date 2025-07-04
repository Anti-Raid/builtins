local data = require"./data"

local settings = {
    --roles = function() return require"./guildroles/guildroles" end,
    --members = function() return require"./guildmembers/guildmembers" end,
    scripts = function()  return require"./scripts/scripts" end,
} :: { [string]: () -> data.Setting }

return {
    settings = settings,
}
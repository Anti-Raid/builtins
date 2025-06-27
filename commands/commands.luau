local data = require"./data"

local commands = {
    whois = function() return require"./whois/whois" end,
    remindme = function() return require"./remindme/remindme" end,
    settings = function() return require"./settings/settings" end,
    urlextract = function() return require"./urlextract/urlextract" end,
    subcmdtest = function() return require"./subcmdtest/subcmdtest" end,
    lockdowns = function() return require"./lockdowns/lockdowns" end,
    stings = function() return require"./stings/stings" end,
    stats = function() return require"./stats/stats" end,
    help = function() return require"./help/help" end,
    moderation = function() return require"./moderation/moderation" end,
    backups = function() return require"./backups/backups" end,
    vmeval = function() return require"./vmeval/vmeval" end,
} :: { [string]: () -> data.Command }

return {
    commands = commands,
    b = 3
}
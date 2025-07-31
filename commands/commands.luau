local data = require"@antiraid-ext/framework/coretypes"

local commands = {
    afk = require"./afk/afk",
    whois = require"./whois/whois",
    remindme = require"./remindme/remindme",
    settings = require"./settings/settings",
    urlextract = require"./urlextract/urlextract",
    urlblock = require"./urlblock/urlblock",
    subcmdtest = require"./subcmdtest/subcmdtest",
    lockdowns = require"./lockdowns/lockdowns",
    stings = require"./stings/stings",
    stats = require"./stats/stats",
    help = require"./help/help",
    moderation = require"./moderation/moderation",
    backups = require"./backups/backups",
    backupsv2 = require"./backupsv2/backupsv2",
    vmeval = require"./vmeval/vmeval",
    serverinfo = require"./serverinfo/serverinfo",
} :: { data.Command }

return {
    commands = commands,
    b = 3
}